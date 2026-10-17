import Darwin
import Foundation
import SnapticKit
import SnapticShims

/// Snaptic's own helper processes (the same executable in a helper mode).
enum HelperKind: String, Sendable {
    case displayGuard, virtualHost, hook, selftestChild

    /// argv[1] of the helper; nil for kinds that aren't our own executable.
    var modeFlag: String? {
        switch self {
        case .displayGuard: return "--display-guard"
        case .virtualHost: return "--virtual-host"
        case .selftestChild: return "--selftest-child"
        case .hook: return nil
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

    init() {}

    /// Nil while helpers can run; otherwise the reason shown on Safety/diagnostics pages.
    var unavailable: String? { unavailableReason }

    var isReady: Bool { identity != nil }

    /// Captures our code identity and runs the `/usr/bin/true` canary off the main thread.
    /// Called once at startup, before any helper or hook.
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

    /// Sinks are attached before the suspended child is resumed.
    func spawn(_ kind: HelperKind, arguments: [String], onLine: @escaping @MainActor (Data) -> Void,
               onExit: @escaping @MainActor (Int32) -> Void) throws -> HelperHandle {
        guard let flag = kind.modeFlag else { throw HelperSpawnError.unsupportedKind }
        if let reason = unavailableReason { throw HelperSpawnError.unavailable(reason) }
        if identity == nil {
            // Not prepared yet (a helper requested very early): do it now, synchronously.
            finishPreparing(Self.computeIdentity())
        }
        guard let identity else { throw HelperSpawnError.unavailable(unavailableReason ?? L("Helpers are unavailable")) }

        let argv = [flag, "--parent", String(getpid()), "--build", identity.build,
                    "--requirement", identity.requirement.base64EncodedString()] + arguments

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
        // ALWAYS, success or failure: otherwise no EOF ever reaches either side.
        defer { close(childIn); close(childOut) }

        var pid: pid_t = 0
        do {
            try SNSpawn.spawnSuspended(path: identity.executable, arguments: argv, stdinFD: childIn,
                                       stdoutFD: childOut, options: [.disclaim], pid: &pid)
        } catch {
            close(parentOut); close(parentIn)
            EventLog.shared.record(.modules, "Helper \(kind.rawValue) failed to spawn")
            throw HelperSpawnError.spawnFailed((error as NSError).localizedDescription)
        }

        // Verify while suspended: the pid can't be reused until we reap it.
        if let problem = Self.verify(pid: pid, requirement: identity.requirement) {
            Self.killAndReap(pid)
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
            Self.killAndReap(pid)
            close(parentOut); close(parentIn)
            throw HelperSpawnError.pipe(errno)
        }
        close(parentOut)
        let handle = HelperHandle(kind: kind, pid: pid, startTime: startTime, writer: writer)
        box.handle = handle

        // Reply pipe: one read source, which owns the descriptor.
        let flags = fcntl(parentIn, F_GETFL)
        if flags >= 0 { _ = fcntl(parentIn, F_SETFL, flags | O_NONBLOCK) }
        let reader = ReaderState(fd: parentIn)
        let readSource = DispatchSource.makeReadSource(fileDescriptor: parentIn,
                                                       queue: DispatchQueue(label: "app.snaptic.helper-reader"))
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

        // Exit: one process source on main; the child is reaped exactly once.
        let exitSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        exitSource.setEventHandler {
            MainActor.assumeIsolated {
                if let status = handle.reapIfExited() {
                    handle.cancelReader()
                    handle.writer?.close()
                    onExit(status)
                }
            }
        }
        handle.attach(read: readSource, exit: exitSource)
        readSource.resume()
        exitSource.resume()

        _ = kill(pid, SIGCONT)
        // Catch an exit that raced the source registration.
        if let status = handle.reapIfExited() {
            handle.cancelReader()
            handle.writer?.close()
            DispatchQueue.main.async { MainActor.assumeIsolated { onExit(status) } }
        }
        EventLog.shared.record(.modules, "Helper \(kind.rawValue) started")
        return handle
    }

    // MARK: Hooks and actions

    /// Runs a user-chosen executable for a hook or custom action (PLAN §4.10(1), R3C §5.3):
    /// path rules, never Snaptic's own code, a disclaimed suspended spawn in its own process
    /// group with a minimal environment, checked before SIGCONT, reaped exactly once, and
    /// SIGTERM then SIGKILL to the group after 30 s.
    func spawnHook(executable: String, arguments: [String], environment: [String: String],
                   onExit: @escaping @MainActor (Int32) -> Void) throws -> HelperHandle {
        if let reason = unavailableReason { throw HelperSpawnError.unavailable(reason) }
        if identity == nil { finishPreparing(Self.computeIdentity()) }
        guard identity != nil else { throw HelperSpawnError.unavailable(unavailableReason ?? L("Helpers are unavailable")) }
        if let refusal = Self.checkExecutable(executable) { throw HelperSpawnError.refused(refusal) }
        if let refusal = KitHookPolicy.checkArguments(arguments) { throw HelperSpawnError.refused(refusal) }

        var pid: pid_t = 0
        do {
            try SNSpawn.spawnSuspended(path: executable, arguments: arguments,
                                       environment: KitHookPolicy.environmentList(environment),
                                       stdinFD: -1, stdoutFD: -1, options: [.disclaim, .ownProcessGroup], pid: &pid)
        } catch {
            throw HelperSpawnError.spawnFailed((error as NSError).localizedDescription)
        }
        guard SNSpawn.isStopped(pid), SNSpawn.responsiblePID(for: pid) == pid else {
            Self.killAndReap(pid)
            throw HelperSpawnError.verificationFailed("responsibility")
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

    /// Path rules (lstat of every component) and "never Snaptic's own code".
    static func checkExecutable(_ path: String) -> HookRefusal? {
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
        if let own = SNProcess.signingIdentifierOfSelf(), SNProcess.signingIdentifier(path: path) == own {
            return .snapticIdentity
        }
        return nil
    }

    // MARK: Preparation

    private func finishPreparing(_ result: Result<Identity, HelperSpawnError>) {
        preparing = false
        guard identity == nil, unavailableReason == nil else { return }
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

    /// Off main where possible; bounded either way.
    nonisolated private static func computeIdentity() -> Result<Identity, HelperSpawnError> {
        guard SNSpawn.disclaimAvailable() else {
            return .failure(.unavailable(L("This version of macOS can't start Snaptic's helpers safely")))
        }
        guard let requirement = try? SNProcess.designatedRequirementOfSelf(), !requirement.isEmpty else {
            return .failure(.unavailable(L("Snaptic's code signature couldn't be read")))
        }
        guard let executable = SNProcess.path(for: getpid()), executable.hasPrefix("/") else {
            return .failure(.unavailable(L("Snaptic couldn't find its own executable")))
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

    private enum Problem: String { case notStopped, notResponsible, identity }

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

    func closeDescriptor() {
        guard !closed else { return }
        closed = true
        _ = close(fd)
    }
}
