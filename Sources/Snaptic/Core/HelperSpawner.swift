import Darwin
import Foundation
import Security
import SnapticKit
import SnapticShims

/// Snaptic's own helper processes (the same executable in a helper mode).
enum HelperKind: String, Sendable {
    case displayGuard, virtualHost, hook, selftestChild
    /// 0.3.1 B3.1, B3.4: osascript running a fixed `LidWatchdog` admin script; B3.3: the fixed user-level tool.
    case adminScript, tool

    /// argv[1] of the helper; nil for kinds that aren't our own executable.
    var modeFlag: String? {
        switch self {
        case .displayGuard: return "--display-guard"
        case .virtualHost: return "--virtual-host"
        case .selftestChild: return "--selftest-child"
        case .hook, .adminScript, .tool: return nil
        }
    }
}

enum HelperSpawnError: Error, Equatable {
    /// Hooks and actions are user executables; SpawnerService launches them (step 2).
    case unsupportedKind
    /// Helpers can't run on this Mac or in this launch; the text says why.
    case unavailable(String)
    case pipe(Int32)
    case spawnFailed(String)
    /// The child failed a post-spawn check and was killed.
    case verificationFailed(String)
    /// A hook or action executable failed the path or identity rules.
    case refused(HookRefusal)
}

/// A running helper. The read source owns its descriptor (R5.5); the exit source keeps
/// the handle alive until the child is reaped, so a dropped handle never leaves a zombie.
final class HelperHandle: @unchecked Sendable {
    let kind: HelperKind
    let pid: pid_t
    let startTime: UInt64
    let writer: HelperPipeWriter?

    private let lock = NSLock()
    private var reaped = false
    private var didTimeOut = false
    private var exitStatus: Int32?
    private var exitSource: DispatchSourceProcess?
    private var readSource: DispatchSourceRead?

    init(kind: HelperKind, pid: pid_t, startTime: UInt64, writer: HelperPipeWriter?) {
        self.kind = kind
        self.pid = pid
        self.startTime = startTime
        self.writer = writer
    }

    var isReaped: Bool {
        lock.lock(); defer { lock.unlock() }
        return reaped
    }

    /// The child's wait status once it has been reaped.
    var status: Int32? {
        lock.lock(); defer { lock.unlock() }
        return exitStatus
    }

    /// 0.3.1 B3.1: the spawner ended the child because it ran past its time limit.
    var timedOut: Bool {
        lock.lock(); defer { lock.unlock() }
        return didTimeOut
    }

    fileprivate func markTimedOut() {
        lock.lock(); didTimeOut = true; lock.unlock()
    }

    /// `sig` to the child's pid only (never its group), only while unreaped and its start time still matches.
    fileprivate func signalProcess(_ sig: Int32) {
        lock.lock()
        let alive = !reaped
        lock.unlock()
        guard alive, pid > 0, startTime == 0 || SNProcess.startTime(for: pid) == startTime else { return }
        _ = kill(pid, sig)
    }

    /// SIGTERM to the child's pid only (a superseded password dialog closes; 0.3.1 B3.0).
    func interrupt() { signalProcess(SIGTERM) }

    /// SIGKILL, only while the child is unreaped and its start time still matches (so a
    /// reused pid is never signalled). Idempotent; also closes the writer.
    func terminate() {
        writer?.close()
        lock.lock()
        let alive = !reaped
        lock.unlock()
        guard alive, pid > 0 else { return }
        if startTime == 0 || SNProcess.startTime(for: pid) == startTime {
            _ = kill(pid, SIGKILL)
        }
    }

    fileprivate func attach(read: DispatchSourceRead?, exit: DispatchSourceProcess) {
        lock.lock()
        readSource = read
        exitSource = exit
        lock.unlock()
    }

    /// Reaps without blocking. Returns the status the first time the child is reaped.
    fileprivate func reapIfExited() -> Int32? {
        lock.lock()
        guard !reaped else { lock.unlock(); return nil }
        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        if result == pid || (result < 0 && errno == ECHILD) {
            reaped = true
            exitStatus = result == pid ? status : -1
            let source = exitSource
            exitSource = nil
            lock.unlock()
            source?.cancel()
            return result == pid ? status : -1
        }
        lock.unlock()
        return nil
    }

    /// Hooks lead their own process group: signal the whole group, only while unreaped
    /// (a reaped leader's group id can be reused).
    func signalGroup(_ sig: Int32) {
        lock.lock()
        let alive = !reaped
        lock.unlock()
        guard alive, pid > 0, startTime == 0 || SNProcess.startTime(for: pid) == startTime else { return }
        _ = killpg(pid, sig)
    }

    fileprivate func cancelReader() {
        lock.lock()
        let source = readSource
        readSource = nil
        lock.unlock()
        source?.cancel()
    }
}

/// Starts helpers (PLAN §3.2, R5.5, R4C §4.1–4.2). The only Swift file allowed to spawn.
@MainActor final class HelperSpawner {
    private struct Identity {
        let executable: String
        let requirement: Data
        let build: String
    }

    private var identity: Identity?
    private var unavailableReason: String?
    private var preparing = false
    private var preparedWaiters: [@MainActor (Bool) -> Void] = []

    init() {}

    /// Nil while helpers can run; otherwise the reason shown on Safety/diagnostics pages.
    var unavailable: String? { unavailableReason }

    var isReady: Bool { identity != nil }

    /// Why a spawn requested before `prepare()` finished is refused (transient).
    static var notReadyMessage: String { L("Snaptic’s helpers are still starting. Try again in a moment.") }

    /// Captures our code identity and runs the `/usr/bin/true` canary off the main thread
    /// (SecCode and the canary never run on main). Called once at startup, before any
    /// helper or hook; spawns before it finishes fail fast (`notReadyMessage`).
    func prepare() {
        guard identity == nil, unavailableReason == nil, !preparing else { return }
        preparing = true
        DispatchQueue.global(qos: .utility).async {
            let result = HelperSpawner.computeIdentity()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.finishPreparing(result) }
            }
        }
    }

    /// Runs `body` on main once preparation has finished: true when helpers can run.
    /// Runs it right away when that is already known. Starts preparing if nobody did.
    func whenPrepared(_ body: @escaping @MainActor (Bool) -> Void) {
        if identity != nil { body(true); return }
        if unavailableReason != nil { body(false); return }
        preparedWaiters.append(body)
        prepare()
    }

    /// Sinks are attached before the suspended child is resumed. The post-spawn checks
    /// (stopped, responsible pid, code identity; SecCode never runs on main) run off main
    /// while the child is still suspended; on any failure it is killed and reaped there.
    /// The exit source and SIGCONT follow on main. Callers re-check their own state after
    /// the await: they may have stopped while the child was being verified.
    func spawn(_ kind: HelperKind, arguments: [String], onLine: @escaping @MainActor (Data) -> Void,
               onExit: @escaping @MainActor (Int32) -> Void) async throws -> HelperHandle {
        guard let flag = kind.modeFlag else { throw HelperSpawnError.unsupportedKind }
        if let reason = unavailableReason { throw HelperSpawnError.unavailable(reason) }
        guard let identity else {
            // Never compute the identity on main: ask again once `whenPrepared` says so.
            prepare()
            throw HelperSpawnError.unavailable(Self.notReadyMessage)
        }

        // No requirement on the command line: the helper checks us against its own (R5.5).
        let argv = [flag, "--parent", String(getpid()), "--build", identity.build] + arguments

        // Request pipe (we write, child reads) and reply pipe (child writes, we read).
        // Darwin has no pipe2: raise every end to >= 3 with CLOEXEC.
        let request = try Self.makePipe()
        let reply: (read: Int32, write: Int32)
        do { reply = try Self.makePipe() } catch {
            close(request.read); close(request.write)
            throw error
        }
        let childIn = request.read, parentOut = request.write
        let parentIn = reply.read, childOut = reply.write

        var pid: pid_t = 0
        do {
            try SNSpawn.spawnSuspended(path: identity.executable, arguments: argv, stdinFD: childIn,
                                       stdoutFD: childOut, options: [.disclaim], pid: &pid)
        } catch {
            close(childIn); close(childOut)
            close(parentOut); close(parentIn)
            EventLog.shared.record(.modules, "Helper \(kind.rawValue) failed to spawn")
            throw HelperSpawnError.spawnFailed((error as NSError).localizedDescription)
        }
        // ALWAYS, before any await: the child has its own copies, and ours left open would
        // keep EOF from ever reaching either side.
        close(childIn); close(childOut)

        // Verify while suspended (the pid can't be reused until we reap it), off main:
        // stopped → responsible pid → identity; kill and reap there on any failure.
        let child = pid
        let requirement = identity.requirement
        let verdict: Problem? = await Self.offMain {
            let problem = HelperSpawner.verify(pid: child, requirement: requirement)
            if problem != nil { HelperSpawner.killAndReap(child) }
            return problem
        }
        if let problem = verdict {
            close(parentOut); close(parentIn)
            if problem == .identity {
                unavailableReason = L("Restart Snaptic to finish updating")
            }
            EventLog.shared.record(.modules, "Helper \(kind.rawValue) failed verification (\(problem.rawValue))")
            throw HelperSpawnError.verificationFailed(problem.rawValue)
        }

        let startTime = SNProcess.startTime(for: pid)
        let box = HandleBox()
        guard let writer = HelperPipeWriter(duplicating: parentOut, onBroken: {
            MainActor.assumeIsolated { box.handle?.terminate() }
        }) else {
            let saved = errno
            await Self.offMain { HelperSpawner.killAndReap(child) }
            close(parentOut); close(parentIn)
            throw HelperSpawnError.pipe(saved)
        }
        close(parentOut)
        let handle = HelperHandle(kind: kind, pid: pid, startTime: startTime, writer: writer)
        box.handle = handle

        // Reply pipe: one read source, which owns the descriptor.
        let flags = fcntl(parentIn, F_GETFL)
        if flags >= 0 { _ = fcntl(parentIn, F_SETFL, flags | O_NONBLOCK) }
        let reader = ReaderState(fd: parentIn)
        let readerQueue = DispatchQueue(label: "app.snaptic.helper-reader")
        let readSource = DispatchSource.makeReadSource(fileDescriptor: parentIn, queue: readerQueue)
        readSource.setEventHandler { [reader] in
            switch reader.drain() {
            case .lines(let lines):
                for line in lines {
                    DispatchQueue.main.async { MainActor.assumeIsolated { onLine(line) } }
                }
            case .wouldBlock:
                break
            case .finished:
                readSource.cancel()
            }
        }
        readSource.setCancelHandler { [reader] in
            reader.closeDescriptor()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // EOF, a read error or an oversized line: the helper is done for.
                    box.handle?.terminate()
                }
            }
        }

        // Exit: one process source on main; the child is reaped exactly once. FIXES-R3 4: the
        // reply pipe is drained to EOF (or EAGAIN) on the reader's queue first, and those last
        // lines are delivered before `onExit`. Lines the reader had already queued for main
        // were enqueued before this hop, so the order on main is: every line, then the exit.
        let finish: @MainActor (Int32) -> Void = { status in
            handle.writer?.close()
            readerQueue.async {
                let last = reader.drainToEnd()
                handle.cancelReader()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        for line in last { onLine(line) }
                        onExit(status)
                    }
                }
            }
        }
        let exitSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        exitSource.setEventHandler {
            MainActor.assumeIsolated {
                if let status = handle.reapIfExited() { finish(status) }
            }
        }
        handle.attach(read: readSource, exit: exitSource)
        readSource.resume()
        exitSource.resume()

        _ = kill(pid, SIGCONT)
        // Catch an exit that raced the source registration.
        if let status = handle.reapIfExited() { finish(status) }
        EventLog.shared.record(.modules, "Helper \(kind.rawValue) started")
        return handle
    }

    // MARK: Lid-closed mode (0.3.1 B3.1, B3.3, B3.4; T-lid-app)

    /// osascript gets SIGTERM (its pid only) after this long: nobody answered the password dialog (B3.1 step 4).
    static let adminTimeoutSeconds: TimeInterval = 120
    /// `pmset displaysleepnow` returns at once; one that hangs is ended, so its single flight can't stick.
    static let toolTimeoutSeconds: TimeInterval = 30
    /// The whole environment of osascript (and so of the root shell it starts) and of the tool (B6).
    nonisolated static let lidEnvironment = ["PATH=/usr/bin:/bin", "LANG=en_US.UTF-8"]
    /// Compiled once each (SecRequirementCreateWithString, SecRequirementCopyData). nil only if Security rejects the
    /// fixed text; every lid spawn is then refused (fail closed).
    nonisolated private static let osascriptRequirementData = compileRequirement(LidWatchdog.osascriptRequirement)
    nonisolated private static let toolRequirementData = compileRequirement(LidWatchdog.toolRequirement)
    /// Single flight: a kind is busy from the call until its child is reaped (or the spawn failed).
    private var lidBusy: Set<HelperKind> = []

    /// Runs `LidWatchdog.osascriptPath -e <script.source>`: a suspended, disclaimed spawn with the minimal environment,
    /// checked to be stopped and to satisfy `LidWatchdog.osascriptRequirement` before SIGCONT; stdout through a reply
    /// pipe (LineSplitter's 64 KB line cap); exit observed on main; SIGTERM to osascript's pid only after 120 s
    /// (`HelperHandle.timedOut`). It needs neither Snaptic's helper identity nor `unavailable == nil`, and skips the
    /// responsibility check (the child is disclaimed). Callers: LidClosedController and LidRecovery (lint L18).
    func spawnAdminScript(_ script: AdminScript, onLine: @escaping @MainActor (Data) -> Void,
                          onExit: @escaping @MainActor (Int32) -> Void) async throws -> HelperHandle {
        guard let requirement = Self.osascriptRequirementData else {
            throw HelperSpawnError.unavailable(L("Snaptic couldn’t check the password prompt’s signature."))
        }
        let handle = try await spawnLid(.adminScript, path: LidWatchdog.osascriptPath, arguments: ["-e", script.source],
                                        requirement: requirement, onLine: onLine, onExit: onExit)
        // Only osascript is signalled: the watchdog it may have started is detached, and Snaptic never signals it.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.adminTimeoutSeconds) { [weak handle] in
            MainActor.assumeIsolated {
                guard let handle, !handle.isReaped else { return }
                handle.markTimedOut()
                handle.signalProcess(SIGTERM)
            }
        }
        return handle
    }

    /// Runs a fixed user-level command (`LidWatchdog.displaySleepArgv`; only LidWatchdog.swift can make one) with the
    /// same checks: suspended, disclaimed, minimal environment, `anchor apple` before SIGCONT. Single flight: no new
    /// spawn while the previous one runs. Callers: LidClosedController and LidRecovery (lint L18).
    func spawnTool(_ command: ToolCommand, onExit: @escaping @MainActor (Int32) -> Void) async throws -> HelperHandle {
        guard let path = command.argv.first, path.hasPrefix("/"), let requirement = Self.toolRequirementData else {
            throw HelperSpawnError.unavailable(L("Snaptic couldn’t check the tool’s signature."))
        }
        let handle = try await spawnLid(.tool, path: path, arguments: Array(command.argv.dropFirst()),
                                        requirement: requirement, onLine: nil, onExit: onExit)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.toolTimeoutSeconds) { [weak handle] in
            MainActor.assumeIsolated {
                guard let handle, !handle.isReaped else { return }
                handle.markTimedOut()
                handle.signalProcess(SIGKILL)
            }
        }
        return handle
    }

    /// The shared path of `spawnAdminScript` and `spawnTool`.
    private func spawnLid(_ kind: HelperKind, path: String, arguments: [String], requirement: Data,
                          onLine: (@MainActor (Data) -> Void)?,
                          onExit: @escaping @MainActor (Int32) -> Void) async throws -> HelperHandle {
        guard !lidBusy.contains(kind) else {
            throw HelperSpawnError.unavailable(L("Snaptic is still finishing the previous request."))
        }
        // Checked and claimed with no suspension in between, so two calls can't both pass.
        lidBusy.insert(kind)
        var running = false
        defer { if !running { lidBusy.remove(kind) } }

        var pipe: (read: Int32, write: Int32)?
        if onLine != nil { pipe = try Self.makePipe() }
        let reply = pipe
        var pid: pid_t = 0
        do {
            try SNSpawn.spawnSuspended(path: path, arguments: arguments, environment: Self.lidEnvironment,
                                       stdinFD: -1, stdoutFD: reply?.write ?? -1, options: [.disclaim], pid: &pid)
        } catch {
            if let reply { close(reply.read); close(reply.write) }
            EventLog.shared.record(.modules, "Helper \(kind.rawValue) failed to spawn")
            throw HelperSpawnError.spawnFailed((error as NSError).localizedDescription)
        }
        // Before any await: the child has its own copy, and ours left open would keep EOF from reaching us.
        if let reply { close(reply.write) }

        // Off main, while suspended (the pid can't be reused until we reap it): stopped, then the code requirement;
        // killed and reaped there on any failure. SecCode never runs on main.
        let child = pid
        let verified: Bool = await Self.offMain {
            let ok = SNSpawn.isStopped(child) && SNProcess.process(child, satisfies: requirement)
            if !ok { HelperSpawner.killAndReap(child) }
            return ok
        }
        guard verified else {
            if let reply { close(reply.read) }
            EventLog.shared.record(.modules, "Helper \(kind.rawValue) failed verification (identity)")
            throw HelperSpawnError.verificationFailed("identity")
        }

        let handle = HelperHandle(kind: kind, pid: pid, startTime: SNProcess.startTime(for: pid), writer: nil)
        let readerQueue = DispatchQueue(label: "app.snaptic.lid-reader")
        var reader: ReaderState?
        var readSource: DispatchSourceRead?
        if let reply, let onLine {
            let flags = fcntl(reply.read, F_GETFL)
            if flags >= 0 { _ = fcntl(reply.read, F_SETFL, flags | O_NONBLOCK) }
            let state = ReaderState(fd: reply.read)
            let source = DispatchSource.makeReadSource(fileDescriptor: reply.read, queue: readerQueue)
            source.setEventHandler { [state] in
                switch state.drain() {
                case .lines(let lines):
                    for line in lines {
                        DispatchQueue.main.async { MainActor.assumeIsolated { onLine(line) } }
                    }
                case .wouldBlock:
                    break
                case .finished:
                    source.cancel()
                }
            }
            // EOF, a read error or a line over 64 KB: stop reading. Unlike `spawn`, the child isn't killed here:
            // osascript closes stdout only as it exits, and that exit is what the caller waits for.
            source.setCancelHandler { [state] in state.closeDescriptor() }
            reader = state
            readSource = source
        }
        let lastLines = reader
        // Exit: one process source on main, the child reaped exactly once; the pipe's last lines arrive before onExit.
        let finish: @MainActor (Int32) -> Void = { [weak self] status in
            self?.lidBusy.remove(kind)
            guard let lastLines else {
                onExit(status)
                return
            }
            readerQueue.async {
                let last = lastLines.drainToEnd()
                handle.cancelReader()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if let onLine { for line in last { onLine(line) } }
                        onExit(status)
                    }
                }
            }
        }
        let exitSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        exitSource.setEventHandler {
            MainActor.assumeIsolated {
                if let status = handle.reapIfExited() { finish(status) }
            }
        }
        handle.attach(read: readSource, exit: exitSource)
        readSource?.resume()
        exitSource.resume()
        running = true
        _ = kill(pid, SIGCONT)
        // Catch an exit that raced the source registration.
        if let status = handle.reapIfExited() { finish(status) }
        return handle
    }

    /// The fixed requirement text as SecRequirement data (for `SNProcess.process(_:satisfies:)`).
    nonisolated private static func compileRequirement(_ text: String) -> Data? {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        var data: CFData?
        guard SecRequirementCopyData(requirement, [], &data) == errSecSuccess, let data else { return nil }
        return data as Data
    }

    // MARK: Hooks and actions

    /// Runs a user-chosen executable for a hook or custom action (PLAN §4.10(1), R3C §5.3):
    /// path rules, never Snaptic's own code, a disclaimed suspended spawn in its own process
    /// group with a minimal environment, checked before SIGCONT, reaped exactly once, and
    /// SIGTERM then SIGKILL to the group after 30 s.
    /// The path rules and every SecCode/SecStaticCode check run off main; the child stays
    /// suspended until they pass. Callers re-check their own state after the await.
    func spawnHook(executable: String, arguments: [String], environment: [String: String],
                   onExit: @escaping @MainActor (Int32) -> Void) async throws -> HelperHandle {
        if let reason = unavailableReason { throw HelperSpawnError.unavailable(reason) }
        guard let identity else {
            prepare()
            throw HelperSpawnError.unavailable(Self.notReadyMessage)
        }
        if let refusal = await Self.offMain({ HelperSpawner.checkExecutable(executable) }) {
            throw HelperSpawnError.refused(refusal)
        }
        if let refusal = KitHookPolicy.checkArguments(arguments) { throw HelperSpawnError.refused(refusal) }

        var pid: pid_t = 0
        do {
            try SNSpawn.spawnSuspended(path: executable, arguments: arguments,
                                       environment: KitHookPolicy.environmentList(environment),
                                       stdinFD: -1, stdoutFD: -1, options: [.disclaim, .ownProcessGroup], pid: &pid)
        } catch {
            throw HelperSpawnError.spawnFailed((error as NSError).localizedDescription)
        }
        // Off main, while suspended: stopped → responsible pid → what actually runs (a script
        // runs its interpreter). Killed and reaped there on any failure.
        let child = pid
        let requirement = identity.requirement
        let failure: HelperSpawnError? = await Self.offMain {
            guard SNSpawn.isStopped(child), SNSpawn.responsiblePID(for: child) == child else {
                HelperSpawner.killAndReap(child)
                return HelperSpawnError.verificationFailed("responsibility")
            }
            if let refusal = HelperSpawner.checkRunningHook(pid: child, ownRequirement: requirement) {
                HelperSpawner.killAndReap(child)
                return HelperSpawnError.refused(refusal)
            }
            return nil
        }
        if let failure {
            if case .refused = failure { EventLog.shared.record(.automation, "Hook refused after spawn") }
            throw failure
        }
        let handle = HelperHandle(kind: .hook, pid: pid, startTime: SNProcess.startTime(for: pid), writer: nil)
        let exitSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        exitSource.setEventHandler {
            MainActor.assumeIsolated {
                if let status = handle.reapIfExited() { onExit(status) }
            }
        }
        handle.attach(read: nil, exit: exitSource)
        exitSource.resume()
        _ = kill(pid, SIGCONT)
        if let status = handle.reapIfExited() {
            DispatchQueue.main.async { MainActor.assumeIsolated { onExit(status) } }
        }
        // The timeout: TERM to the group, then KILL; both only while unreaped.
        DispatchQueue.main.asyncAfter(deadline: .now() + KitHookPolicy.timeoutSeconds) { [weak handle] in
            MainActor.assumeIsolated {
                guard let handle, !handle.isReaped else { return }
                handle.signalGroup(SIGTERM)
                DispatchQueue.main.asyncAfter(deadline: .now() + KitHookPolicy.killGraceSeconds) { [weak handle] in
                    MainActor.assumeIsolated { handle?.signalGroup(SIGKILL) }
                }
            }
        }
        EventLog.shared.record(.automation, "Hook process started")
        return handle
    }

    /// Path rules (lstat of every component) and "never Snaptic's own code". Reads the file
    /// system and the code signature: spawns call it off main.
    nonisolated static func checkExecutable(_ path: String) -> HookRefusal? {
        if let refusal = KitHookPolicy.checkSyntax(path) { return refusal }
        let infos = KitHookPolicy.components(of: path).map { component -> PathComponentInfo in
            var info = stat()
            guard lstat(component, &info) == 0 else { return PathComponentInfo(path: component, exists: false) }
            let type = info.st_mode & S_IFMT
            return PathComponentInfo(path: component, exists: true, isDirectory: type == S_IFDIR,
                                     isRegularFile: type == S_IFREG, isSymlink: type == S_IFLNK,
                                     owner: info.st_uid, mode: UInt32(info.st_mode) & 0o7777)
        }
        if let refusal = KitHookPolicy.check(infos, userID: getuid()) { return refusal }
        if KitHookPolicy.isInside(path, bundle: Bundle.main.bundlePath) { return .insideSnaptic }
        if let refusal = insideOwnCode(path) { return refusal }
        // Fail closed: without our own identifier nothing can be compared.
        guard let own = SNProcess.signingIdentifierOfSelf(), !own.isEmpty else { return .identityUnreadable }
        if SNProcess.signingIdentifier(path: path) == own { return .snapticIdentity }
        return nil
    }

    /// The suspended hook child must not be Snaptic's code: not satisfying our designated
    /// requirement, not carrying our signing identifier, not running from inside our
    /// bundle (realpath, case-folded). Anything unreadable refuses.
    nonisolated private static func checkRunningHook(pid: pid_t, ownRequirement: Data) -> HookRefusal? {
        if SNProcess.process(pid, satisfies: ownRequirement) { return .snapticIdentity }
        guard let own = SNProcess.signingIdentifierOfSelf(), !own.isEmpty else { return .identityUnreadable }
        guard let identifier = try? SNProcess.signingIdentifier(pid: pid) else { return .identityUnreadable }
        if identifier == own { return .snapticIdentity }
        guard let running = SNProcess.path(for: pid) else { return .identityUnreadable }
        return insideOwnCode(running)
    }

    /// `path` (resolved) inside our bundle or equal to our executable, compared the way a
    /// case-insensitive volume does. Nil when it isn't; unresolvable paths refuse.
    nonisolated private static func insideOwnCode(_ path: String) -> HookRefusal? {
        guard let resolved = realPath(path) else { return .identityUnreadable }
        let bundle = Bundle.main.bundlePath
        let roots = [realPath(bundle) ?? bundle, SNProcess.path(for: getpid()).flatMap(realPath)].compactMap { $0 }
        for root in roots where KitHookPolicy.isInsideFolded(resolved, bundle: root) { return .insideSnaptic }
        return nil
    }

    nonisolated private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    // MARK: Preparation

    private func finishPreparing(_ result: Result<Identity, HelperSpawnError>) {
        preparing = false
        if identity == nil, unavailableReason == nil {
            switch result {
            case .success(let id):
                identity = id
            case .failure(let error):
                if case .unavailable(let reason) = error { unavailableReason = reason } else {
                    unavailableReason = L("Helpers are unavailable")
                }
                EventLog.shared.record(.modules, "Helpers unavailable")
            }
        }
        let waiters = preparedWaiters
        preparedWaiters = []
        let ok = identity != nil
        waiters.forEach { $0(ok) }
    }

    /// Off main where possible; bounded either way.
    nonisolated private static func computeIdentity() -> Result<Identity, HelperSpawnError> {
        guard SNSpawn.disclaimAvailable() else {
            return .failure(.unavailable(L("This version of macOS can’t start Snaptic’s helpers safely")))
        }
        guard let requirement = try? SNProcess.designatedRequirementOfSelf(), !requirement.isEmpty else {
            return .failure(.unavailable(L("Snaptic’s code signature couldn’t be read")))
        }
        guard let executable = SNProcess.path(for: getpid()), executable.hasPrefix("/") else {
            return .failure(.unavailable(L("Snaptic couldn’t find its own executable")))
        }
        guard runCanary() else {
            return .failure(.unavailable(L("Starting helper processes failed a safety check")))
        }
        return .success(Identity(executable: executable, requirement: requirement,
                                 build: SNProcess.executableUUID() ?? "unknown"))
    }

    /// Spawns /usr/bin/true through the same path as helpers and checks that the
    /// suspended-spawn and responsibility checks behave, once per launch.
    nonisolated private static func runCanary() -> Bool {
        var pid: pid_t = 0
        do {
            try SNSpawn.spawnSuspended(path: "/usr/bin/true", arguments: [], stdinFD: -1, stdoutFD: -1,
                                       options: [.disclaim], pid: &pid)
        } catch {
            return false
        }
        guard pid > 0 else { return false }
        let stopped = SNSpawn.isStopped(pid)
        let responsible = SNSpawn.responsiblePID(for: pid)
        guard stopped, responsible == pid else {
            killAndReap(pid)
            return false
        }
        _ = kill(pid, SIGCONT)
        // /usr/bin/true exits at once; poll briefly instead of blocking.
        var status: Int32 = 0
        for _ in 0..<200 {
            let r = waitpid(pid, &status, WNOHANG)
            if r == pid { return true }
            if r < 0 { return false }
            usleep(2_000)
        }
        killAndReap(pid)
        return false
    }

    // MARK: Helpers

    private enum Problem: String, Sendable { case notStopped, notResponsible, identity }

    /// Runs `work` on a background queue and resumes the caller with its result.
    nonisolated private static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
        }
    }

    nonisolated private static func verify(pid: pid_t, requirement: Data) -> Problem? {
        guard SNSpawn.isStopped(pid) else { return .notStopped }
        guard SNSpawn.responsiblePID(for: pid) == pid else { return .notResponsible }
        guard SNProcess.process(pid, satisfies: requirement) else { return .identity }
        return nil
    }

    /// SIGKILL then a blocking wait: bounded, because SIGKILL ends even a stopped child.
    nonisolated private static func killAndReap(_ pid: pid_t) {
        guard pid > 0 else { return }
        _ = kill(pid, SIGKILL)
        var status: Int32 = 0
        _ = waitpid(pid, &status, 0)
    }

    nonisolated private static func makePipe() throws -> (read: Int32, write: Int32) {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { throw HelperSpawnError.pipe(errno) }
        let raised = fds.map { fd -> Int32 in
            let d = fcntl(fd, F_DUPFD_CLOEXEC, 3)
            close(fd)
            return d
        }
        guard raised[0] >= 0, raised[1] >= 0 else {
            let saved = errno
            for fd in raised where fd >= 0 { close(fd) }
            throw HelperSpawnError.pipe(saved)
        }
        return (raised[0], raised[1])
    }
}

/// Lets callbacks created before the handle reach it later.
private final class HandleBox: @unchecked Sendable {
    weak var handle: HelperHandle?
}

/// Reply-pipe reading state; touched only on the reader queue (and the cancel handler,
/// which runs on it too).
private final class ReaderState: @unchecked Sendable {
    enum Outcome { case lines([Data]), wouldBlock, finished }

    private let fd: Int32
    private var splitter = LineSplitter()
    private var closed = false

    init(fd: Int32) { self.fd = fd }

    func drain() -> Outcome {
        var buffer = [UInt8](repeating: 0, count: 16_384)
        let n = buffer.withUnsafeMutableBytes { raw in read(fd, raw.baseAddress, raw.count) }
        if n < 0 && (errno == EINTR || errno == EAGAIN) { return .wouldBlock }
        guard n > 0, let lines = splitter.feed(Data(buffer[0..<n])) else { return .finished }
        return .lines(lines)
    }

    /// Everything left in the pipe once the child is gone: reads until EOF, EAGAIN, an error
    /// or an oversized line, at most 64 reads (1 MB). Only the lines read here are returned;
    /// earlier ones were already delivered by the read source.
    func drainToEnd() -> [Data] {
        guard !closed else { return [] }
        var out: [Data] = []
        var buffer = [UInt8](repeating: 0, count: 16_384)
        for _ in 0..<64 {
            let n = buffer.withUnsafeMutableBytes { raw in read(fd, raw.baseAddress, raw.count) }
            if n < 0 && errno == EINTR { continue }
            guard n > 0, let lines = splitter.feed(Data(buffer[0..<n])) else { break }
            out += lines
        }
        return out
    }

    func closeDescriptor() {
        guard !closed else { return }
        closed = true
        _ = close(fd)
    }
}
