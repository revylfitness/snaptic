import AppKit
import SnapticKit

// Stub (owner: J). Hand-written by the lead in step 0 from PLAN 0.3 §2.8 (kind S): refuses every watch. The only user
// of EVFILT_PROC and proc_pidinfo in Awake.

@MainActor final class ProcessWatch: AwakeServiceLifecycle {
    weak var context: AwakeContext?

    init() {}

    /// proc_pidinfo(PROC_PIDTBSDINFO): nil when the pid is gone or unreadable. Stub: nil.
    func facts(_ pid: Int32) -> (uid: uid_t, startTime: UInt64)? { nil }

    /// Arms the kqueue first, then re-reads facts; false refuses. Stub: false.
    func watch(pid: Int32, startTime: UInt64, lifetime: Lifetime, onExit: @escaping @MainActor () -> Void) -> Bool {
        false
    }

    /// N17 holder name; local UI only, never stored. Stub: nil ("the command line").
    func holderName(for pid: Int32) -> String? { nil }

    func activate(_ context: AwakeContext, lifetime: Lifetime) { self.context = context }

    /// Every watch's handler runs with .processExited (J).
    func deactivate() { context = nil }
}
