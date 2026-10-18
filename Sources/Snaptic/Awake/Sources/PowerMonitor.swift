import AppKit
import SnapticKit

// Stub (owner: J). Hand-written by the lead in step 0 from PLAN 0.3 §2.8 + R5-6 (kind S). Always active with
// `sessions` (guards need it).

@MainActor final class PowerMonitor: ObservableObject, CriterionSource {
    static var kinds: Set<AwakeCriterionKind> { [.power] }
    weak var context: AwakeContext?
    /// nil until the first IOPS read (J). Stub: never read.
    @Published private(set) var facts: PowerFacts?
    private let changes = ChangeFanout()

    init() {}

    func activate(_ context: AwakeContext, lifetime: Lifetime) { self.context = context }
    func deactivate() { context = nil }
    func contribute(to facts: inout CriterionFacts) {}
    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void) { changes.add(lifetime, handler) }
}
