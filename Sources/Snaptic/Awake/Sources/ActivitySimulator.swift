import AppKit
import SnapticKit

// Stub (owner: J). Hand-written by the lead in step 0 from PLAN 0.3 §2.9 (kind S): never acts. The only file allowed
// to declare user activity and post CGEvents (lint L1/L2).

@MainActor final class ActivitySimulator: AwakeServiceLifecycle {
    weak var context: AwakeContext?
    /// Continuous times, last 10, for IdleMath.
    private(set) var recentNudges: [Double] = []
    /// Continuous times, last 10, for IdleMath.
    private(set) var recentDeclarations: [Double] = []

    init() {}

    /// ActivityController calls it once per interval. Stub: does nothing.
    func perform(_ decision: ActivityDecision) {}

    /// Releases the DeclareUserActivity id.
    func stop() {}

    func activate(_ context: AwakeContext, lifetime: Lifetime) { self.context = context }

    func deactivate() {
        stop()
        context = nil
    }
}
