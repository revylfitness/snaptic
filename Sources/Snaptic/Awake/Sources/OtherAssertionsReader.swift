import AppKit
import Combine
import IOKit.pwr_mgt
import SnapticKit

// "Other apps keeping your Mac awake" (owner: J; PLAN 0.3 §1.1, §2.8, §3.6, §4.3 Awake › Advanced). Reads other
// processes' power assertions (`IOPMCopyAssertionsByProcess`) and the system-wide SleepDisabled setting (the
// "SystemPowerSettings" value of the com.apple.PowerManagement preferences, the same read the private
// IOPMCopySystemPowerSettings() makes). Read-only: this reader never writes SleepDisabled; only lid-closed mode changes
// it (0.3.1 B3: LidClosedController's watchdog, the fixed root script, while the user has it on). Both reads are IPC,
// so they run on a private utility queue; names are resolved on main through ProcessWatch. Local UI only:
// no process name, assertion name or count is ever logged, stored, exported, put in diagnostics or sent over the CLI.

@MainActor final class OtherAssertionsReader: ObservableObject {
    /// While a view shows the list (5 s, `.common`, so it updates while a menu is open too).
    static let refreshSeconds: TimeInterval = 5

    /// One line per app or process name, sorted by name.
    @Published private(set) var rows: [OtherAssertionRow] = []
    /// SleepDisabled is on (the section says whose it is: another app's, or lid-closed mode's).
    @Published private(set) var sleepDisabled = false
    /// False until the first read finished (the view shows nothing rather than "No other apps…" before it).
    @Published private(set) var hasRead = false
    /// The assertion list couldn't be read (powerd unreachable); `rows` is then empty.
    @Published private(set) var readFailed = false

    private let viewers = NeedCounter()
    private let timer = SourceTimer()
    private var generation: UInt64 = 0
    private var inFlight = false
    private var pendingRefresh = false
    private let queue = DispatchQueue(label: "snaptic.awake.otherassertions", qos: .utility)

    init() {
        viewers.onChange = { [weak self] in self?.viewersChanged() }
    }

    /// Keeps the list fresh while `lifetime` lives (one per visible view); reads at once.
    func keepUpdated(_ lifetime: Lifetime) { viewers.add(lifetime) }

    /// Reads now (coalesced: at most one read in flight, one queued behind it).
    func refresh() {
        guard !inFlight else {
            pendingRefresh = true
            return
        }
        inFlight = true
        generation &+= 1
        let ticket = generation
        let own = getpid()
        let box = CallbackTarget(self)
        queue.async {
            let read = OtherAssertionsReader.read(ownPID: own)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { box.target?.finish(read, ticket: ticket) }
            }
        }
    }

    // MARK: Private

    private func viewersChanged() {
        if viewers.isNeeded {
            timer.start(every: Self.refreshSeconds, tolerance: 1) { [weak self] in self?.refresh() }
            refresh()
        } else {
            timer.cancel()
            // Nothing is kept once no view shows it.
            generation &+= 1
            rows = []
            hasRead = false
            readFailed = false
            sleepDisabled = false
        }
    }

    private struct Read: Sendable {
        var holders: [OtherAssertionHolder]?
        var sleepDisabled: Bool
    }

    private func finish(_ read: Read, ticket: UInt64) {
        inFlight = false
        defer {
            if pendingRefresh {
                pendingRefresh = false
                if viewers.isNeeded { refresh() }
            }
        }
        guard ticket == generation, viewers.isNeeded else { return }
        let newRows = read.holders.map { holders in
            OtherAssertions.rows(holders) { ProcessWatch.processName(for: $0.pid) ?? $0.reportedName }
        } ?? []
        if rows != newRows { rows = newRows }
        if readFailed != (read.holders == nil) { readFailed = read.holders == nil }
        if sleepDisabled != read.sleepDisabled { sleepDisabled = read.sleepDisabled }
        if !hasRead { hasRead = true }
    }

    /// Off main: both IPC reads, converted to Sendable Kit values.
    private nonisolated static func read(ownPID: Int32) -> Read {
        Read(holders: readAssertions(ownPID: ownPID), sleepDisabled: readSleepDisabled())
    }

    private nonisolated static func readAssertions(ownPID: Int32) -> [OtherAssertionHolder]? {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == 0, let dict = raw?.takeRetainedValue() as NSDictionary? else {
            return nil
        }
        var byProcess: [Int32: [[String: Any]]] = [:]
        for (key, value) in dict {
            guard let pid = (key as? NSNumber)?.int32Value, let list = value as? [Any] else { continue }
            byProcess[pid] = list.compactMap { $0 as? [String: Any] }
        }
        return OtherAssertions.holders(byProcess, ownPID: ownPID)
    }

    /// 0.3.1 B3.1: the stored SleepDisabled preference, for lid-closed mode's preflight (the kernel's value is read from
    /// IORegistry separately). IPC: call it off main.
    nonisolated static func sleepDisabledPreference() -> Bool { readSleepDisabled() }

    /// kCFPreferencesAnyUser + kCFPreferencesCurrentHost, read-only: what `pmset -g` reports as "SleepDisabled 1".
    private nonisolated static func readSleepDisabled() -> Bool {
        let value = CFPreferencesCopyValue(OtherAssertions.settingsKey as CFString,
                                           OtherAssertions.preferencesDomain as CFString,
                                           kCFPreferencesAnyUser, kCFPreferencesCurrentHost)
        return OtherAssertions.sleepDisabled(value as? [String: Any])
    }
}
