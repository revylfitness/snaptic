import AppKit
import Combine
import SnapticKit

/// The brightness slider of each display (PLAN 0.3 §5.2, §4.8 `c.brightness.slider`): a top-level `MenuSliderRow`
/// under the display's row, over the combined range (above 100% with extra brightness on). It follows live changes
/// while the menu is open (keys, CLI, sync, Settings) through `DisplayRuntime`, and writes through the shared
/// `DisplaysContext.live`. Until the monitor's first DDC read answers it is a status row instead. The brightness
/// method choice is in Settings only (no submenus in submenus). Constructed and registered by BrightnessController.
@MainActor final class BrightnessMenuItems: DisplayMenuContributor, ControlDeclaring {
    typealias Controls = BrightnessMenuItemsControls

    static let sliderItem = DisplayMenuItemID(rawValue: "c.brightness.slider")

    static var menuItemIDs: [DisplayMenuItemID] { [sliderItem] }

    weak var context: DisplaysContext?

    init(context: DisplaysContext) {
        self.context = context
    }

    var descriptors: [DisplayMenuItemDescriptor] {
        [DisplayMenuItemDescriptor(id: Self.sliderItem, title: L("Brightness slider"), slot: .display,
                                   defaultVisibility: .visible)]
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard let context, context.runtime.isEffective(.brightness) else { return [] }
        let key = display.key
        if context.brightness.isAwaitingFirstRead(key) {
            // W17b: until the monitor's first DDC read answers (the menu rebuilds then).
            // It sits right under the display's row, which names the display.
            return [(Self.sliderItem, MenuKit.status(L("Reading Brightness…"), symbol: "sun.max",
                                                     control: ControlID("menu.display.c.brightnessReading")))]
        }
        let runtime = context.runtime.runtime(for: key)
        guard let value = runtime.brightnessPosition else { return [] }
        let range = runtime.brightnessRange
        let name = TextSanitizer.clean(display.name, maxScalars: 64)
        let slider = MenuSliderRow(title: L("Brightness of \(name)"), symbol: range.upperBound > 1 ? "sun.max.circle" : "sun.max",
                                   value: value, range: range, format: .percent(of: 1),
                                   control: ControlID("menu.display.c.brightness")) { [weak self] newValue, phase in
            self?.context?.live.set(.brightness, newValue, for: key, phase: phase)
        }
        slider.bind(to: runtime.$brightnessPosition.eraseToAnyPublisher())
        return [(Self.sliderItem, slider)]
    }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] { [] }
}
