import AppKit
import Combine
import IOKit
import SwiftUI
import SnapticKit

// Host-level recovery from lid-closed mode (owner: T-lid-app; PLAN 0.3.1 B3.4): at launch (AppDelegate step 7, beside
// RevertJournal, whatever Awake's state, also in Safe Mode) it classifies the journal and the kernel's SleepDisabled;
// while sleep was left off it drives the leftover rows in every menu, on the Awake page and under Other Apps, and their
// buttons. It also finishes what LidClosedController hands it: a journal is kept until the kernel reads 0, and still 1
// after the wait means a leftover. Lives as long as the app, so a mode that ended with the module still gets its check.
// No journal field ever reaches root: Turn Sleep Back On… runs the fixed, argument-free restore script.

/// What lid-closed mode reads and writes outside the state machine (B3.1, B3.3, B3.4). Nonisolated: the heartbeat's
/// queue and the signal path use it too.
enum LidSystem {
    /// IOPMrootDomain's `SleepDisabled`, the kernel's value. nil only when the root domain can't be found; a root domain
    /// without the property reads as false, the state of every Mac that never set it (r3 code NB1). A value that is
    /// neither a boolean nor a number is unreadable (nil), never "off".
    static func kernelSleepDisabled() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return false }
        // CFBoolean and CFNumber both bridge to NSNumber.
        if let number = value as? NSNumber { return number.intValue != 0 }
        return nil
    }

    /// The Mac has a lid: IOPMrootDomain carries `AppleClamshellState`. Read synchronously (B3.1 step 1: feature
    /// availability, never the value published after the module started).
    static func hasLid() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() != nil
    }

    /// 32 lowercase hex characters: the only token shape that may name a file or reach the watchdog.
    static func isToken(_ text: String) -> Bool {
        text.utf8.count == 32 && text.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }

    /// A new token: 128 random bits (the system generator), as 32 lowercase hex characters.
    static func newToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return [UInt64.random(in: .min ... .max, using: &generator), UInt64.random(in: .min ... .max, using: &generator)]
            .map { word in
                let hex = String(word, radix: 16)
                return String(repeating: "0", count: 16 - hex.count) + hex
            }
            .joined()
    }

    /// `confstr(_CS_DARWIN_USER_TEMP_DIR)` with its trailing "/" trimmed, plus "/snaptic-lid". The watchdog gets this
    /// exact string (never a realpath) and checks its shape itself.
    static func beaconDirectory() -> String? {
        let size = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        guard size > 1, size < 4_096 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, size) == size else { return nil }
        var dir = String(cString: buffer)
        while dir.hasSuffix("/") { dir.removeLast() }
        guard dir.hasPrefix("/") else { return nil }
        return dir + "/snaptic-lid"
    }

    /// Creates `dir` (0700) when missing. True only when lstat shows a directory, not a link, owned by us, mode 0700.
    static func prepareBeaconDirectory(_ dir: String) -> Bool {
        if mkdir(dir, 0o700) != 0 && errno != EEXIST { return false }
        var info = stat()
        guard lstat(dir, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid(),
              (info.st_mode & 0o7777) == 0o700 else { return false }
        return true
    }

    /// Old `stop-*` and `beat-*` entries go (B3.1 step 3); `unlink` never follows a link.
    static func clearBeacons(_ dir: String) {
        guard let handle = opendir(dir) else { return }
        var names: [String] = []
        var seen = 0
        while let entry = readdir(handle), seen < 1_024 {
            seen += 1
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            if name.hasPrefix("stop-") || name.hasPrefix("beat-") { names.append(name) }
        }
        closedir(handle)
        for name in names { unlink(dir + "/" + name) }
    }

    /// `stop-<token>`: O_CREAT|O_NOFOLLOW, 0600 (B3.3 "Turning off" step 1). The beacon goes too, so a watchdog
    /// stops even if something planted a link where the stop file belongs (B6: either one turns sleep back on).
    static func requestStop(dir: String, token: String) {
        guard isToken(token) else { return }
        let fd = open(dir + "/stop-" + token, O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        if fd >= 0 { close(fd) }
        unlink(dir + "/beat-" + token)
    }
}

/// The stop file's path for the signal path (EmergencyActions runs on a global queue, maybe while main hangs, B3.3
/// "Quit"): immutable, and its C string is never freed, so a late signal never touches freed memory (r2 security m1).
final class LidStopPath: @unchecked Sendable {
    private let path: UnsafeMutablePointer<CChar>

    init?(dir: String, token: String) {
        guard LidSystem.isToken(token), let copy = strdup(dir + "/stop-" + token) else { return nil }
        path = copy
    }

    /// Creates the stop file, or leaves an existing one; never follows a planted link. Thread-safe, idempotent.
    func touch() {
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        if fd >= 0 { close(fd) }
    }
}

/// The one journal slot: `~/Library/Application Support/Snaptic/awake/lid.json`, 0600, written atomically (B3.1
/// step 2), inside a 0700 folder checked with lstat (JournalFiles, Displays' revert journals' writer).
enum LidJournalStore {
    static let name = "lid.json"

    private static func files() -> JournalFiles? {
        AccountPaths.home.map { JournalFiles(directory: $0 + "/Library/Application Support/Snaptic/awake") }
    }

    /// The journal, or nil. A file that doesn't decode, or holds a token of the wrong shape, is removed: it was never
    /// ours to act on, and a journal alone never prompts anyway.
    static func read() -> AwakeLidJournal? {
        guard let files = files(), let data = files.read(name) else { return nil }
        guard let journal = try? JSONDecoder().decode(AwakeLidJournal.self, from: data),
              LidSystem.isToken(journal.token) else {
            files.remove(name)
            return nil
        }
        return journal
    }

    @discardableResult
    static func write(_ journal: AwakeLidJournal) -> Bool {
        guard let files = files(), let data = try? JSONEncoder().encode(journal) else { return false }
        return files.write(data, to: name)
    }

    /// Removes the journal when it is `token`'s (nil: whatever it holds).
    static func remove(token: String?) {
        guard let files = files() else { return }
        if let token, let current = read(), current.token != token { return }
        files.remove(name)
    }
}

/// What step 7 found, handed to `LidRecoveryState.start` once the host exists.
struct LidLaunchFacts {
    let journal: AwakeLidJournal?
    let recovery: AwakeLidRecovery
}

/// `LidRecovery.atLaunch(safeMode:)` (B3.4).
enum LidRecovery {
    /// Startup step 7, before any module starts: classify, clear a journal whose sleep is back on, and ask a watchdog
    /// that may still run from a crashed copy to stop (its stop file; anything may turn sleep back on).
    @MainActor static func atLaunch(safeMode: SafeModeState) -> LidLaunchFacts {
        let journal = LidJournalStore.read()
        let now = AwakeModule.clockNow()
        let recovery = AwakeLidPolicy.classify(journal: journal, bootUUID: now.bootSession,
                                               sleepDisabled: LidSystem.kernelSleepDisabled(), now: now,
                                               ownPID: getpid())
        switch recovery {
        case .clear:
            LidJournalStore.remove(token: journal?.token)
        case .pending:
            if let token = journal?.token, let dir = LidSystem.beaconDirectory() {
                LidSystem.requestStop(dir: dir, token: token)
            }
        case .leftover:
            EventLog.shared.record(AwakeLogEvent.lidLeftover)
        case .nothing:
            break
        }
        if safeMode.isActive, recovery == .leftover {
            EventLog.shared.record(.safety, "Sleep was left off by an earlier lid-closed session")
        }
        return LidLaunchFacts(journal: journal, recovery: recovery == .clear ? .nothing : recovery)
    }
}

/// `ModuleHost.lidRecovery`.
@MainActor final class LidRecoveryState: ObservableObject {
    /// How long a same-boot journal may wait for the kernel to read 0 before it counts as a leftover (B3.4).
    static let pendingSeconds: Double = 30
    /// While a leftover shows, the kernel is re-read this often: sleep turned back on by any means clears the rows.
    static let leftoverRecheckSeconds: TimeInterval = 30
    static let pollSeconds: TimeInterval = 0.5

    /// The B3.4 classification (`.nothing` while there's no Snaptic journal to account for).
    @Published private(set) var recovery: AwakeLidRecovery = .nothing
    /// Not Now: the rows stay hidden until the next launch.
    @Published private(set) var dismissed = false
    /// Turn Sleep Back On… is waiting for its password or its result (single flight).
    @Published private(set) var restoring = false
    /// The journal step 7 found from an earlier run (B2: after a resume the header says "Snaptic quit").
    private(set) var launchJournal: AwakeLidJournal?

    private weak var spawner: HelperSpawner?
    private weak var toasts: ToastPresenter?
    private var awakeRunning: @MainActor () -> Bool = { false }
    private var openAwakeSettings: @MainActor () -> Void = {}
    /// The kernel check of a pending journal: whose token it waits for, until when (continuous), and who to tell.
    private var waitToken: String?
    private var waitUntil: Double?
    private var waiters: [@MainActor (Bool) -> Void] = []
    private var pollTimer: Timer?
    private var leftoverTimer: Timer?
    private var restoreOutput: Data?

    init() {}

    /// The leftover rows show ("Sleep Is Turned Off", Turn Sleep Back On…).
    var showsRows: Bool { recovery == .leftover && !dismissed }

    /// Turning lid-closed mode on is refused (B2: journal pending, or a leftover).
    var blocksTurnOn: Bool { recovery == .pending || recovery == .leftover }

    // MARK: Startup

    /// After the host exists (AppDelegate), before its menus are built.
    func start(_ launch: LidLaunchFacts, spawner: HelperSpawner, toasts: ToastPresenter,
               awakeRunning: @escaping @MainActor () -> Bool, openAwakeSettings: @escaping @MainActor () -> Void) {
        self.spawner = spawner
        self.toasts = toasts
        self.awakeRunning = awakeRunning
        self.openAwakeSettings = openAwakeSettings
        launchJournal = launch.journal
        switch launch.recovery {
        case .pending:
            watch(token: launch.journal?.token, seconds: Self.pendingSeconds)
        case .leftover:
            setRecovery(.leftover)
        case .nothing, .clear:
            break
        }
    }

    /// After the modules started: the toast for a leftover while Awake isn't running (B3.4).
    func launchFinished() {
        if recovery == .leftover { announceIfAwakeOff() }
    }

    // MARK: Waiting for the kernel

    /// Keeps the journal of `token` (nil: whatever it holds) until the kernel's SleepDisabled reads 0, checked now and
    /// every 0.5 s for up to `seconds`; then the journal goes and `completion(true)` runs. Still 1 (or unreadable)
    /// at the end: the leftover rows show and `completion(false)` runs. Turning the mode on is refused meanwhile.
    func watch(token: String?, seconds: Double, completion: (@MainActor (Bool) -> Void)? = nil) {
        let until = AwakeModule.clockNow().continuous + max(0, seconds)
        if waitToken != token { waitToken = token }
        waitUntil = max(waitUntil ?? until, until)
        if let completion { waiters.append(completion) }
        if recovery != .leftover { setRecovery(.pending) }
        poll()
        guard waitUntil != nil, pollTimer == nil else { return }
        let timer = Timer(timeInterval: Self.pollSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// Sleep was found still turned off after lid-closed mode ended (B3.3: the watchdog is gone but the kernel reads
    /// 1, or the turn-off wait ran out). The journal stays.
    func markLeftover() {
        finishWait(restored: false)
    }

    private func poll() {
        guard let until = waitUntil else { return }
        if LidSystem.kernelSleepDisabled() == false {
            LidJournalStore.remove(token: waitToken)
            finishWait(restored: true)
        } else if AwakeModule.clockNow().continuous >= until {
            finishWait(restored: false)
        }
    }

    private func finishWait(restored: Bool) {
        pollTimer?.invalidate()
        pollTimer = nil
        waitToken = nil
        waitUntil = nil
        let done = waiters
        waiters = []
        if restored {
            setRecovery(.nothing)
        } else if recovery != .leftover {
            EventLog.shared.record(AwakeLogEvent.lidLeftover)
            setRecovery(.leftover)
            announceIfAwakeOff()
        }
        for waiter in done { waiter(restored) }
    }

    private func setRecovery(_ value: AwakeLidRecovery) {
        if recovery != value { recovery = value }
        leftoverTimer?.invalidate()
        leftoverTimer = nil
        guard value == .leftover else { return }
        let timer = Timer(timeInterval: Self.leftoverRecheckSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheckLeftover() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        leftoverTimer = timer
    }

    /// The rows show only while SleepDisabled reads 1 (B3.4): sleep turned back on in any way clears them.
    private func recheckLeftover() {
        guard recovery == .leftover, !restoring, LidSystem.kernelSleepDisabled() == false else { return }
        LidJournalStore.remove(token: nil)
        setRecovery(.nothing)
    }

    /// "Your Mac can’t sleep…" as a toast when Awake isn't running (its page and menu can't show the rows then).
    private func announceIfAwakeOff() {
        guard recovery == .leftover, !dismissed, !awakeRunning(), let toasts else { return }
        toasts.show(L("Your Mac can’t sleep. This may be from an earlier lid-closed session that didn’t finish."),
                    actions: [
                        ToastAction(title: L("Turn Sleep Back On…")) { [weak self] in self?.turnSleepBackOn() },
                        ToastAction(title: L("Open Awake Settings…")) { [weak self] in self?.openAwakeSettings() },
                    ])
    }

    // MARK: The three buttons

    /// Turn Sleep Back On… (asks for the password): `LidWatchdog.restoreScript`, fixed and argument-free, through the
    /// same spawner and wrapper; then the kernel is re-read and the journal cleared. Never prompts while the kernel
    /// already reads 0 (a journal alone never prompts).
    func turnSleepBackOn() {
        guard recovery == .leftover, !restoring else { return }
        if LidSystem.kernelSleepDisabled() == false {
            LidJournalStore.remove(token: nil)
            setRecovery(.nothing)
            return
        }
        guard let spawner, let script = LidWatchdog.restoreScript(prompt: LidWatchdog.restorePromptText) else {
            EventLog.shared.record(AwakeLogEvent.lidFailed(.args))
            return
        }
        restoring = true
        restoreOutput = nil
        Task { @MainActor [weak self] in
            do {
                _ = try await spawner.spawnAdminScript(script, onLine: { [weak self] line in
                    if self?.restoreOutput == nil { self?.restoreOutput = line }
                }, onExit: { [weak self] _ in
                    self?.restoreFinished()
                })
            } catch {
                EventLog.shared.record(AwakeLogEvent.lidFailed(.spawn))
                self?.restoring = false
            }
        }
    }

    private func restoreFinished() {
        restoring = false
        let output = restoreOutput.map { String(decoding: $0, as: UTF8.self) } ?? ""
        restoreOutput = nil
        if LidWatchdog.parseResult(output) == .canceled { return }
        // powerd applies the preference to the kernel asynchronously: wait a little for 0.
        watch(token: nil, seconds: 10)
    }

    /// Keep Sleep Off: the journal goes and the rows go everywhere; no prompt, no root. Other Apps then reports the
    /// setting as anyone else's ("Snaptic leaves it as it is.").
    func keepSleepOff() {
        guard recovery == .leftover, !restoring else { return }
        LidJournalStore.remove(token: nil)
        setRecovery(.nothing)
    }

    /// Not Now: hides the rows everywhere until the next launch.
    func notNow() { dismissed = true }
}

/// The B3.4 rows on the Awake page and under Advanced › Other Apps: the text, Turn Sleep Back On…, Keep Sleep Off and
/// Not Now. The callers pass their own control ids (each table's ids are literals in its own files, L15).
struct LidLeftoverRow: View {
    @ObservedObject var recovery: LidRecoveryState
    let restore: ControlID
    let keepOff: ControlID
    let dismiss: ControlID

    var body: some View {
        if recovery.showsRows {
            StatusRow(L("Your Mac can’t sleep. This may be from an earlier lid-closed session that didn’t finish."),
                      style: .warning, actions: [
                          StatusAction(title: L("Turn Sleep Back On…"), control: restore) { [weak recovery = self.recovery] in
                              recovery?.turnSleepBackOn()
                          },
                          StatusAction(title: L("Keep Sleep Off"), control: keepOff) { [weak recovery = self.recovery] in
                              recovery?.keepSleepOff()
                          },
                          StatusAction(title: L("Not Now"), control: dismiss) { [weak recovery = self.recovery] in
                              recovery?.notNow()
                          },
                      ])
                .disabled(recovery.restoring)
        }
    }
}
