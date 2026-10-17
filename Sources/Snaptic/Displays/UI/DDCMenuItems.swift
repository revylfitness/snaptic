import AppKit
import SnapticKit

/// DDC items in each display block: volume (only when VCP 0x62 is supported), contrast,
/// input submenu, the header standby switch and custom controls. Constructed and
/// registered by DDCController in start().
@MainActor final class DDCMenuItems: DisplayMenuContributor {
    static let volumeItem = DisplayMenuItemID(rawValue: "c.ddc.volume")
    static let muteItem = DisplayMenuItemID(rawValue: "c.ddc.mute")
    static let contrastItem = DisplayMenuItemID(rawValue: "c.ddc.contrast")
    static let inputItem = DisplayMenuItemID(rawValue: "c.ddc.input")
    static let powerItem = DisplayMenuItemID(rawValue: "c.ddc.power")
    static let customItem = DisplayMenuItemID(rawValue: "c.ddc.custom")

    weak var context: DisplaysContext?
    weak var controller: DDCController?

    init(context: DisplaysContext) { self.context = context }

    convenience init(context: DisplaysContext, controller: DDCController) {
        self.init(context: context)
        self.controller = controller
    }

    var descriptors: [DisplayMenuItemDescriptor] {
        [
            DisplayMenuItemDescriptor(id: Self.volumeItem, title: L("Volume slider (DDC)"), slot: .display, defaultVisibility: .visible),
            DisplayMenuItemDescriptor(id: Self.muteItem, title: L("Mute (DDC)"), slot: .display, defaultVisibility: .inSubmenu),
            DisplayMenuItemDescriptor(id: Self.contrastItem, title: L("Contrast slider (DDC)"), slot: .display,
                                      defaultVisibility: .inSubmenu),
            DisplayMenuItemDescriptor(id: Self.inputItem, title: L("Input source"), slot: .display, defaultVisibility: .inSubmenu),
            DisplayMenuItemDescriptor(id: Self.powerItem, title: L("Standby switch (DDC)"), slot: .header, defaultVisibility: .visible),
            DisplayMenuItemDescriptor(id: Self.customItem, title: L("Custom DDC controls"), slot: .display,
                                      defaultVisibility: .inSubmenu),
        ]
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard let context, let controller, context.ddc.isAvailable(display.key) else { return [] }
        let key = display.key
        let eff = controller.effective
        let live = context.runtime.runtime(for: key)
        let caps = context.ddc.cachedCapabilities(key)
        var result: [(DisplayMenuItemID, NSMenuItem)] = []
        if eff.contains(.ddcControls) {
            // R5.8: the volume slider only when the display supports VCP 0x62.
            if caps?.supports(VCPPolicy.volume) == true || (caps == nil && context.ddc.lastReading(VCPPolicy.volume, of: key) != nil) {
                let slider = MenuSliderItem(title: L("Volume"), symbol: "speaker.wave.2", value: live.volume ?? 0.5) {
                    [weak controller] value in controller?.setFraction(VCPPolicy.volume, value, for: key)
                }
                result.append((Self.volumeItem, slider))
                result.append((Self.muteItem, CMenu.item(L("Mute"), on: live.muted ?? false) { [weak controller] in
                    controller?.toggleMute(.display(key))
                }))
            }
            if controller.isControlEnabled(VCPPolicy.contrast, for: key) {
                let slider = MenuSliderItem(title: L("Contrast"), symbol: "circle.lefthalf.filled", value: live.contrast ?? 0.5) {
                    [weak controller] value in controller?.setFraction(VCPPolicy.contrast, value, for: key)
                }
                result.append((Self.contrastItem, slider))
            }
        }
        if eff.contains(.ddcInput) {
            let inputs = controller.inputList(for: key)
            if !inputs.isEmpty {
                let items = inputs.map { entry in
                    CMenu.item(controller.inputName(entry), on: live.input == entry.value && !entry.lgAlt) { [weak controller] in
                        controller?.setInput(entry, on: key)
                    }
                }
                result.append((Self.inputItem, CMenu.submenu(L("Input Source"), items)))
            }
        }
        if eff.contains(.ddcPower), caps == nil || caps?.supports(VCPPolicy.power) == true {
            let on = live.powerOn ?? true
            result.append((Self.powerItem, CMenu.item(L("Screen On"), on: on) { [weak controller] in
                controller?.setPower(!on, on: key)
            }))
        }
        if eff.contains(.ddcCustom) {
            let customs = (context.config.value.perDisplay[key]?.ddc.customControls ?? []).filter(\.showInMenu)
            if !customs.isEmpty {
                var items: [NSMenuItem] = []
                for control in customs {
                    switch control.kind {
                    case .command:
                        items.append(CMenu.item(control.name.isEmpty ? VCPPolicy.name(control.code) : control.name) {
                            [weak controller] in controller?.runCustom(control, on: key)
                        })
                    case .range:
                        let current = context.ddc.lastReading(control.code, of: key).map { controller.fraction(key, control.code, $0) }
                        items.append(MenuSliderItem(title: control.name, symbol: "slider.horizontal.3", value: current ?? 0.5) {
                            [weak controller] value in controller?.runCustom(control, on: key, fraction: value)
                        })
                    }
                }
                result.append((Self.customItem, CMenu.submenu(L("Custom Controls"), items)))
            }
        }
        return result
    }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] { [] }
}
