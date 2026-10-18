import AppKit
import Combine
import SnapticKit

/// Hardware-control (DDC) items of each display (PLAN 0.3 §5.2, §4.8 "0.2 menu"): top-level `MenuSliderRow`s for
/// volume (only with VCP 0x62), contrast (default Hide) and every custom range control marked "Show in menu"; in the
/// display submenu an "Input" header with checkable inputs, and "Mute" and "Turn Off Display" / "Turn On Display"
/// in the power group (`cDDCPower`, which migration M10 can promote to the top level). Sliders follow live values
/// while the menu is open and write through `DisplayLiveController`. Constructed and registered by DDCController.
@MainActor final class DDCMenuItems: DisplayMenuContributor, ControlDeclaring {
    typealias Controls = DDCMenuItemsControls

    static let volumeItem = DisplayMenuItemID(rawValue: "c.ddc.volume")
    static let muteItem = DisplayMenuItemID(rawValue: "c.ddc.mute")
    static let contrastItem = DisplayMenuItemID(rawValue: "c.ddc.contrast")
    static let inputItem = DisplayMenuItemID(rawValue: "c.ddc.input")
    static let powerItem = DisplayMenuItemID.cDDCPower
    static let customItem = DisplayMenuItemID(rawValue: "c.ddc.custom")

    static var menuItemIDs: [DisplayMenuItemID] { [volumeItem, muteItem, contrastItem, inputItem, powerItem, customItem] }

    weak var context: DisplaysContext?
    weak var controller: DDCController?
    private let live: DisplayLiveController

    init(context: DisplaysContext) {
        self.context = context
        live = DisplayLiveController(context: context)
    }

    convenience init(context: DisplaysContext, controller: DDCController) {
        self.init(context: context)
        self.controller = controller
    }

    var descriptors: [DisplayMenuItemDescriptor] {
        [
            DisplayMenuItemDescriptor(id: Self.volumeItem, title: L("Volume slider"), slot: .display, defaultVisibility: .visible),
            DisplayMenuItemDescriptor(id: Self.muteItem, title: L("Mute"), slot: .display, defaultVisibility: .inSubmenu),
            DisplayMenuItemDescriptor(id: Self.contrastItem, title: L("Contrast slider"), slot: .display,
                                      defaultVisibility: .hidden),
            DisplayMenuItemDescriptor(id: Self.inputItem, title: L("Input"), slot: .display, defaultVisibility: .inSubmenu),
            DisplayMenuItemDescriptor(id: Self.powerItem, title: L("Turn Off Display"), slot: .display,
                                      defaultVisibility: .inSubmenu),
            DisplayMenuItemDescriptor(id: Self.customItem, title: L("Custom control sliders"), slot: .display,
                                      defaultVisibility: .visible),
        ]
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard let context, let controller, context.ddc.isAvailable(display.key) else { return [] }
        let key = display.key
        let name = TextSanitizer.clean(display.name, maxScalars: 64)
        let eff = controller.effective
        let runtime = context.runtime.runtime(for: key)
        let caps = context.ddc.cachedCapabilities(key)
        let hasVolume = caps?.supports(VCPPolicy.volume) == true
            || (caps == nil && context.ddc.lastReading(VCPPolicy.volume, of: key) != nil)
        var result: [(DisplayMenuItemID, NSMenuItem)] = []
        if eff.contains(.ddcControls) {
            // R5.8: the volume slider only when the display supports VCP 0x62.
            if hasVolume {
                let slider = MenuSliderRow(title: L("Volume of \(name)"), symbol: "speaker.wave.2", value: runtime.volume,
                                           range: runtime.volumeRange, format: .percent(of: 1),
                                           control: ControlID("menu.display.c.volume")) { [weak self] value, phase in
                    self?.live.set(.volume, value, for: key, phase: phase)
                }
                slider.bind(to: runtime.$volume.eraseToAnyPublisher())
                result.append((Self.volumeItem, slider))
            }
            if controller.isControlEnabled(VCPPolicy.contrast, for: key) {
                let slider = MenuSliderRow(title: L("Contrast of \(name)"), symbol: "circle.lefthalf.filled",
                                           value: runtime.contrast, range: runtime.contrastRange, format: .percent(of: 1),
                                           control: ControlID("menu.display.c.contrast")) { [weak self] value, phase in
                    self?.live.set(.contrast, value, for: key, phase: phase)
                }
                slider.bind(to: runtime.$contrast.eraseToAnyPublisher())
                result.append((Self.contrastItem, slider))
            }
        }
        if eff.contains(.ddcCustom) {
            for control in (context.config.value.perDisplay[key]?.ddc.customControls ?? []) where control.showInMenu {
                let title = control.name.isEmpty ? VCPPolicy.name(control.code) : TextSanitizer.clean(control.name, maxScalars: 64)
                switch control.kind {
                case .range:
                    let code = control.code
                    let slider = MenuSliderRow(title: L("\(title) of \(name)"), symbol: "slider.horizontal.3",
                                               value: controller.customValue(code, for: key), range: 0...1,
                                               format: .percent(of: 1),
                                               control: ControlID("menu.display.c.custom")) { [weak self] value, phase in
                        self?.live.set(.custom(code), value, for: key, phase: phase)
                    }
                    slider.bind(to: controller.customPublisher(code, for: key))
                    result.append((Self.customItem, slider))
                case .command:
                    result.append((Self.customItem, MenuKit.action(title, symbol: "command",
                                                                   control: ControlID("menu.display.c.customCommand")) {
                        [weak controller] in controller?.runCustom(control, on: key)
                    }))
                }
            }
        }
        if eff.contains(.ddcInput) {
            let inputs = controller.inputList(for: key)
            if !inputs.isEmpty {
                result.append((Self.inputItem, MenuKit.header(L("Input"), control: ControlID("menu.display.c.inputHeader"))))
                for entry in inputs {
                    let current = runtime.input == entry.value && !entry.lgAlt
                    result.append((Self.inputItem, MenuKit.toggle(controller.inputName(entry), isOn: current,
                                                                  control: ControlID("menu.display.c.input")) {
                        [weak controller] in controller?.setInput(entry, on: key)
                    }))
                }
            }
        }
        if eff.contains(.ddcControls), hasVolume {
            result.append((Self.muteItem, MenuKit.toggle(L("Mute"), isOn: runtime.muted ?? false,
                                                         control: ControlID("menu.display.c.mute")) {
                [weak controller] in controller?.toggleMute(.display(key))
            }))
        }
        if eff.contains(.ddcPower), caps == nil || caps?.supports(VCPPolicy.power) == true {
            let on = runtime.powerOn ?? true
            result.append((Self.powerItem, MenuKit.action(on ? L("Turn Off Display") : L("Turn On Display"),
                                                          control: ControlID("menu.display.c.power")) {
                [weak controller] in controller?.setPower(!on, on: key)
            }))
        }
        return result
    }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] { [] }
}
