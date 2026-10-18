import AppKit
import Combine
import SnapticKit

/// Runs hook and custom-action commands (PLAN §11, §4.10(1)) through HelperSpawner:
/// disclaimed, own process group, minimal environment, 30 s timeout, one run per hook and
/// event per 10 s. Refused in Safe Mode and while panic-latched. Deactivating (or panic)
/// kills every command still running.
@MainActor final class SpawnerService: DisplayServiceLifecycle {
    static var serviceID: DisplayServiceID { .spawner }
    static var privateSymbols: [PrivateSymbol] { [] }
    weak var context: DisplaysContext?

    private var lifetime: Lifetime?
    private var running: [UInt64: HelperHandle] = [:]
    private var serial: UInt64 = 0
    private var throttle = HookThrottle()
    /// Last refusal or failure, for the Automation page (no paths or arguments).
    private(set) var lastProblem: String?
    var onChange: (@MainActor () -> Void)?

    init() {}

    var runningCount: Int { running.count }

    func activate(_ context: DisplaysContext, lifetime: Lifetime) {
        self.context = context
        self.lifetime = lifetime
    }

    func deactivate() {
        stopAll()
        context = nil
        lifetime = nil
    }

    /// Runs `command`. Returns nil when started, otherwise why not (also kept in
    /// `lastProblem`). `throttleKey`: hooks pass "<hook id>.<event>".
    /// The spawner checks the command off main, so this awaits; the state is re-checked after.
    @discardableResult
    func run(_ command: CommandSpec, environment: [String: String], throttleKey: String?) async -> String? {
        guard let ctx = context, let lifetime, !lifetime.isEnded else { return report(L("Automation is off.")) }
        guard !ctx.safeMode.isActive else { return report(L("Hooks and actions don't run in Safe Mode.")) }
        guard !ctx.panic.isLatched else { return report(L("Hooks and actions are paused until display automation resumes.")) }
        if let key = throttleKey, !throttle.allow(key, now: ProcessInfo.processInfo.systemUptime) {
            return report(L("Skipped: this hook already ran in the last 10 seconds."))
        }
        serial &+= 1
        let id = serial
        do {
            let handle = try await ctx.helpers.spawnHook(executable: command.executable, arguments: command.arguments,
                                                         environment: environment) { [weak self] status in
                guard let self else { return }
                self.running[id] = nil
                if status != 0 { EventLog.shared.record(.automation, "Command exited with status \(status)") }
                self.onChange?()
            }
            // Deactivated, or panic latched, while the command was being checked.
            guard context === ctx, self.lifetime === lifetime, !lifetime.isEnded else {
                handle.signalGroup(SIGKILL)
                return report(L("Automation is off."))
            }
            guard !ctx.panic.isLatched, !ctx.safeMode.isActive else {
                handle.signalGroup(SIGKILL)
                return report(L("Hooks and actions are paused until display automation resumes."))
            }
            if handle.isReaped { running[id] = nil } else { running[id] = handle }
            lastProblem = nil
            onChange?()
            return nil
        } catch HelperSpawnError.refused(let refusal) {
            return report(refusal.message)
        } catch HelperSpawnError.unavailable(let reason) {
            return report(reason)
        } catch {
            return report(L("The command couldn't be started."))
        }
    }

    /// Panic and deactivation: every running command's process group is killed.
    func stopAll() {
        for handle in running.values { handle.signalGroup(SIGKILL) }
        running = [:]
        onChange?()
    }

    private func report(_ problem: String) -> String {
        lastProblem = problem
        EventLog.shared.record(.automation, "Command not run")
        onChange?()
        return problem
    }
}
