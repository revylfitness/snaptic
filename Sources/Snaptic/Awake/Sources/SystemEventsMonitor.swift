import AppKit
import SnapticKit

// Stub (owner: J). Hand-written by the lead in step 0 from PLAN 0.3 §2.8 (kind S). Not a criterion source of its
// own (no kinds) but multicast like one (code M7).

/// Read synchronously from CGSessionCopyCurrentDictionary() (security M2).
struct SessionFacts: Equatable, Sendable {
    var locked: Bool
    var onConsole: Bool
}

@MainActor final class SystemEventsMonitor: CriterionSource {
    static var kinds: Set<AwakeCriterionKind> { [] }
    weak var context: AwakeContext?
    private let changes = ChangeFanout()

    init() {}

    /// The session dictionary at the moment of use (J). Stub: locked and off console (nothing acts).
    func sessionFacts() -> SessionFacts { SessionFacts(locked: true, onConsole: false) }

    func activate(_ context: AwakeContext, lifetime: Lifetime) { self.context = context }
    func deactivate() { context = nil }
    func contribute(to facts: inout CriterionFacts) {}
    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void) { changes.add(lifetime, handler) }
}
