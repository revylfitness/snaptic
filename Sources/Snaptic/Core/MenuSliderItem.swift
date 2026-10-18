import AppKit

/// 0.2's slider item is gone: every menu slider is a `MenuSliderRow` (PLAN 0.3 §5.1). Only the host still sets the
/// scroll switch by this name (`ModuleHost`); the step-3b merge points it at `MenuSliderRow.scrollToAdjust` and
/// deletes this file.
@MainActor enum MenuSliderItem {
    static var scrollToAdjust: Bool {
        get { MenuSliderRow.scrollToAdjust }
        set { MenuSliderRow.scrollToAdjust = newValue }
    }
}
