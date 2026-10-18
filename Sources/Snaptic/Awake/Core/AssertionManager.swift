import AppKit
import SnapticKit

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §2.4 (kind S): holds nothing. The ONLY
// IOPMAssertionCreate*/Release caller for sleep assertions (lint L1).

@MainActor final class AssertionManager: AwakeServiceLifecycle {
    private(set) var current: AwakeAssertionPlan = .inactive
    private(set) var lastError: Int32?
    weak var context: AwakeContext?

    init() {}

    /// Idempotent; create-then-release swaps (G). Stub: refuses every active plan.
    @discardableResult func apply(_ plan: AwakeAssertionPlan, now: ClockNow) -> Bool {
        plan.type == .off
    }

    func releaseAll() { current = .inactive }

    /// Re-creates a vanished assertion once (G). Stub: nothing held, nothing to verify.
    func verify(now: ClockNow) -> Bool { true }

    func activate(_ context: AwakeContext, lifetime: Lifetime) { self.context = context }

    func deactivate() {
        releaseAll()
        context = nil
    }
}
