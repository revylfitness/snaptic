import AppKit
import SnapticKit

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §5.3 (kind S): never creates an item.
// AwakeModule forwards StatusItemProvider to it; the item is created and removed only in `applyStatusItem`.

@MainActor final class IndicatorController: AwakeFeatureController {
    static var id: AwakeControllerID { .indicator }
    weak var context: AwakeContext?
    /// nil while the item doesn't exist.
    private(set) var statusItem: NSStatusItem?

    init() {}

    /// Called from AwakeModule.applyStatusItem (StatusMenu.applyPlan's turn). Stub: no item.
    func applyStatusItem(_ row: CustomItemRow) {}

    func availability(of feature: AwakeFeature, context: AwakeContext) -> FeatureAvailability { .available }
    func start(_ context: AwakeContext, lifetime: Lifetime, effective: Set<AwakeFeature>) { self.context = context }
    func effectiveFeaturesDidChange(_ effective: Set<AwakeFeature>) {}
    func configDidChange(from old: AwakeConfig, to new: AwakeConfig) {}
    func stop() { context = nil }
}
