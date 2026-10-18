import AppKit
import SnapticKit

/// Color, extra-brightness, menu-bar background, sync and Night Shift items (PLAN 0.3 §5.2, §4.8 "0.2 menu"; R5-13:
/// they moved here from their controllers). Per display, in the display submenu: ✓ "Adjust Colors" (on = not
/// suspended), ✓ "Extra Brightness", ✓ "Automatically Adjust Brightness", ✓ "Black Menu Bar Background", a "Color
/// Profile" header with the current, previous and recent profiles and "More Color Profiles…", and a "Preset" header
/// with the Apple display presets. In Display Tools: ✓ "Sync Brightness" and ✓ "Night Shift".
///
/// Each controller registers one instance for its own part, so an item exists exactly while its controller runs.
@MainActor final class ColorMenuItems: DisplayMenuContributor, ControlDeclaring {
    typealias Controls = ColorMenuItemsControls

    enum Part {
        /// ColorController: Adjust Colors.
        case color
        /// XDRController: Extra Brightness.
        case xdr
        /// SyncController: Sync Brightness (Display Tools).
        case sync
        /// SystemColorsController: profiles, presets, auto-brightness, Night Shift (Display Tools).
        case systemColors
        /// MenuBarOverlaysController: Black Menu Bar Background.
        case menuBarOverlays
    }

    static let adjustColorsItem = DisplayMenuItemID(rawValue: "c.color.submenu")
    static let profilesItem = DisplayMenuItemID(rawValue: "c.color.profiles")
    static let presetsItem = DisplayMenuItemID(rawValue: "c.color.applePresets")
    static let autoBrightnessItem = DisplayMenuItemID(rawValue: "c.color.autoBrightness")
    static let menuBarBackgroundItem = DisplayMenuItemID(rawValue: "c.menuBarStrip.toggle")
    static let extraBrightnessItem = DisplayMenuItemID(rawValue: "c.xdr.toggle")
    static let syncItem = DisplayMenuItemID(rawValue: "c.sync.toggle")
    static let nightShiftItem = DisplayMenuItemID(rawValue: "c.tools.nightShift")

    static var menuItemIDs: [DisplayMenuItemID] {
        [adjustColorsItem, profilesItem, presetsItem, autoBrightnessItem, menuBarBackgroundItem, extraBrightnessItem,
         syncItem, nightShiftItem]
    }

    weak var context: DisplaysContext?
    let part: Part
    private weak var owner: AnyObject?

    init(context: DisplaysContext, part: Part, owner: AnyObject) {
        self.context = context
        self.part = part
        self.owner = owner
    }

    var descriptors: [DisplayMenuItemDescriptor] {
        switch part {
        case .color:
            return [DisplayMenuItemDescriptor(id: Self.adjustColorsItem, title: L("Adjust Colors"), slot: .display,
                                              defaultVisibility: .inSubmenu)]
        case .xdr:
            return [DisplayMenuItemDescriptor(id: Self.extraBrightnessItem, title: L("Extra Brightness"), slot: .display,
                                              defaultVisibility: .inSubmenu)]
        case .sync:
            return [DisplayMenuItemDescriptor(id: Self.syncItem, title: L("Sync Brightness"), slot: .tools,
                                              defaultVisibility: .visible)]
        case .systemColors:
            return [
                DisplayMenuItemDescriptor(id: Self.profilesItem, title: L("Color Profile"), slot: .display,
                                          defaultVisibility: .inSubmenu),
                DisplayMenuItemDescriptor(id: Self.presetsItem, title: L("Preset"), slot: .display,
                                          defaultVisibility: .inSubmenu),
                DisplayMenuItemDescriptor(id: Self.autoBrightnessItem, title: L("Automatically Adjust Brightness"),
                                          slot: .display, defaultVisibility: .inSubmenu),
                DisplayMenuItemDescriptor(id: Self.nightShiftItem, title: L("Night Shift"), slot: .tools,
                                          defaultVisibility: .visible),
            ]
        case .menuBarOverlays:
            return [DisplayMenuItemDescriptor(id: Self.menuBarBackgroundItem, title: L("Black Menu Bar Background"),
                                              slot: .display, defaultVisibility: .inSubmenu)]
        }
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard let context, display.isOnline else { return [] }
        switch part {
        case .color: return colorItems(display, context)
        case .xdr: return xdrItems(display, context)
        case .systemColors: return systemColorItems(display, context)
        case .menuBarOverlays: return menuBarItems(display, context)
        case .sync: return []
        }
    }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard slot == .tools, let context else { return [] }
        switch part {
        case .sync:
            guard let sync = owner as? SyncController, context.runtime.isEffective(.sync) else { return [] }
            return [(Self.syncItem, MenuKit.toggle(L("Sync Brightness"), isOn: !sync.isPaused,
                                                   control: ControlID("menu.display.c.syncBrightness")) {
                [weak sync] in sync?.togglePaused()
            })]
        case .systemColors:
            guard let colors = owner as? SystemColorsController, context.runtime.isEffective(.nightShift) else { return [] }
            colors.refreshNightShift()
            guard let on = colors.nightShiftOn else { return [] }
            return [(Self.nightShiftItem, MenuKit.toggle(L("Night Shift"), isOn: on,
                                                         control: ControlID("menu.display.c.nightShift")) {
                [weak colors] in _ = colors?.toggleNightShift()
            })]
        case .color, .xdr, .menuBarOverlays:
            return []
        }
    }

    // MARK: Per part

    private func colorItems(_ display: DisplayInfo, _ context: DisplaysContext) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard let color = owner as? ColorController, context.runtime.isEffective(.color), color.canAdjust(display) else {
            return []
        }
        let key = display.key
        let suspended = context.config.value.perDisplay[key]?.color.suspended ?? false
        let item = MenuKit.toggle(L("Adjust Colors"), isOn: !suspended && !context.config.value.color.suspendAll,
                                  enabled: !context.config.value.color.suspendAll,
                                  control: ControlID("menu.display.c.adjustColors")) {
            [weak color] in color?.toggleSuspend(.display(key))
        }
        let note = context.config.value.color.suspendAll ? L("Paused on all displays") : nil
        return [(Self.adjustColorsItem, MenuKit.withSubtitle(item, note))]
    }

    private func xdrItems(_ display: DisplayInfo, _ context: DisplaysContext) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard let xdr = owner as? XDRController, context.runtime.isEffective(.xdr), xdr.method(for: display.key).0 != nil else {
            return []
        }
        let key = display.key
        let on = xdr.isEnabled(key)
        let item = MenuKit.toggle(L("Extra Brightness"), isOn: on, control: ControlID("menu.display.c.extraBrightness")) {
            [weak xdr] in _ = xdr?.toggle(.display(key))
        }
        var subtitle: String?
        if on, let reason = context.edr.pauseReason {
            subtitle = L("Paused: ") + reason
        } else if on, context.edr.isBoosting(key) {
            subtitle = L("\(Int((context.edr.appliedBoost(key) * 100).rounded()))% now")
        }
        return [(Self.extraBrightnessItem, MenuKit.withSubtitle(item, subtitle))]
    }

    private func menuBarItems(_ display: DisplayInfo, _ context: DisplaysContext) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard let overlays = owner as? MenuBarOverlaysController, context.runtime.isEffective(.menuBarOverlays),
              display.isActive, display.mirrorOf == nil else { return [] }
        let key = display.key
        let on = context.config.value.perDisplay[key]?.color.menuBarStrip ?? false
        return [(Self.menuBarBackgroundItem, MenuKit.toggle(L("Black Menu Bar Background"), isOn: on,
                                                            control: ControlID("menu.display.c.menuBarBackground")) {
            [weak overlays] in overlays?.toggleStrip(.display(key))
        })]
    }

    private func systemColorItems(_ display: DisplayInfo, _ context: DisplaysContext) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard let colors = owner as? SystemColorsController else { return [] }
        let key = display.key
        var result: [(DisplayMenuItemID, NSMenuItem)] = []
        if context.runtime.isEffective(.autoBrightness), let on = context.appleBrightness.autoBrightness(of: key) {
            result.append((Self.autoBrightnessItem, MenuKit.toggle(L("Automatically Adjust Brightness"), isOn: on,
                                                                   control: ControlID("menu.display.c.autoBrightness")) {
                [weak colors] in colors?.setAutoBrightness(!on, for: key)
            }))
        }
        if context.runtime.isEffective(.colorProfiles) {
            result += profileItems(display, context, colors)
        }
        if context.runtime.isEffective(.applePresets) {
            let presets = context.monitorPanel.presetList(for: key)
            if !presets.isEmpty {
                result.append((Self.presetsItem, MenuKit.header(L("Preset"), control: ControlID("menu.display.c.presetHeader"))))
                for preset in presets.prefix(12) {
                    result.append((Self.presetsItem, MenuKit.toggle(TextSanitizer.clean(preset.name, maxScalars: 64),
                                                                    isOn: preset.isActive,
                                                                    control: ControlID("menu.display.c.preset")) {
                        [weak colors] in colors?.applyPreset(preset, to: key)
                    }))
                }
            }
        }
        return result
    }

    /// "Color Profile" header, the current, previous and up to three recent profiles, then "More Color Profiles…".
    private func profileItems(_ display: DisplayInfo, _ context: DisplaysContext,
                              _ colors: SystemColorsController) -> [(DisplayMenuItemID, NSMenuItem)] {
        let key = display.key
        let sync = context.colorSync
        var names: [URL: String] = [:]
        for profile in sync.installedProfiles() { names[profile.url] = profile.name }
        if let current = sync.currentProfile(for: key) { names[current.url] = names[current.url] ?? current.name }
        let current = sync.currentChoice(for: key)
        let rows = ProfileMenuOrder.rows(current: current, previous: sync.previousChoice(for: key),
                                         recent: sync.recentChoices(for: key)) { choice in
            choice.url.map { names[$0] != nil } ?? true
        }
        var result: [(DisplayMenuItemID, NSMenuItem)] = [
            (Self.profilesItem, MenuKit.header(L("Color Profile"), control: ControlID("menu.display.c.profileHeader"))),
        ]
        for choice in rows {
            let title: String
            switch choice {
            case .factory: title = L("Factory Profile")
            case .profile(let url): title = TextSanitizer.clean(names[url] ?? url.deletingPathExtension().lastPathComponent,
                                                                maxScalars: 64)
            }
            let profile = choice.url.map { ColorProfileInfo(name: names[$0] ?? title, url: $0) }
            result.append((Self.profilesItem, MenuKit.toggle(title, isOn: choice == current,
                                                             control: ControlID("menu.display.c.profile")) {
                [weak colors] in
                guard choice != current else { return }
                colors?.applyProfile(profile, to: key)
            }))
        }
        result.append((Self.profilesItem, MenuKit.action(L("More Color Profiles…"),
                                                         control: ControlID("menu.display.c.moreProfiles")) {
            [weak context] in context?.openSettings("displays.color")
        }))
        return result
    }
}
