import AppKit
import SnapticKit

/// The menu items of D's management controllers (PLAN 0.3 §5.2, R5-13), built with MenuKit: Arrangement (Use as Main
/// Display, Mirror “X”, Arrange Displays…), PanelProps (Rotation, High Dynamic Range, Underscan…), Power (Disconnect /
/// Connect, Connect All Displays, Disconnect All But Main, and the 0.2 display-sleep item until step 3), Protection
/// (Protect Arrangement) and SmartHiDPI (Sharper Text).
///
/// Each controller registers its own instance in `start()` with only its own reference set, so an instance's items
/// come and go with that controller. Rows read caches only (≤ 50 ms rebuilds); actions capture the `DisplayKey` and
/// re-resolve it on click. One submenu level: every per-display row sits directly in the display submenu.
@MainActor final class ManagementMenuItems: DisplayMenuContributor, ControlDeclaring {
    typealias Controls = ManagementMenuItemsControls

    weak var context: DisplaysContext?
    weak var arrangement: ArrangementController?
    weak var panelProps: PanelPropsController?
    weak var power: PowerController?
    weak var protection: ProtectionController?
    weak var smartHiDPI: SmartHiDPIController?

    init(context: DisplaysContext) { self.context = context }

    static var menuItemIDs: [DisplayMenuItemID] {
        [.dSetMain, .dMirrorMenu, .dArrange, .dRotationMenu, .dHDRToggle, .dUnderscanMenu, .dDisconnectItem, .dConnectAll,
         .dDisconnectAllButMain, .dSleepPrevention, .dProtection, .dSmartHiDPI]
    }

    // MARK: Descriptors (Customize Displays Menu rows)

    /// 0.3 defaults (§5.2): Use as Main and Mirror are in the display submenu; Rotation, High Dynamic Range,
    /// Underscan… and Sharper Text are opt-in (hidden until chosen); Disconnect stays in the submenu ("Show" puts it
    /// under the device row, slot `.header`); the tools are shown.
    var descriptors: [DisplayMenuItemDescriptor] {
        var list: [DisplayMenuItemDescriptor] = []
        if let a = arrangement {
            if a.effective.contains(.mainDisplay) {
                list.append(DisplayMenuItemDescriptor(id: .dSetMain, title: L("Use as Main Display"), slot: .display,
                                                      defaultVisibility: .inSubmenu))
            }
            if a.effective.contains(.mirroring) {
                list.append(DisplayMenuItemDescriptor(id: .dMirrorMenu, title: L("Mirroring"), slot: .display,
                                                      defaultVisibility: .inSubmenu))
            }
            if a.effective.contains(.arrangement) {
                list.append(DisplayMenuItemDescriptor(id: .dArrange, title: L("Arrange Displays…"), slot: .tools,
                                                      defaultVisibility: .visible))
            }
        }
        if let p = panelProps {
            if p.effective.contains(.rotation) {
                list.append(DisplayMenuItemDescriptor(id: .dRotationMenu, title: L("Rotation"), slot: .display,
                                                      defaultVisibility: .hidden))
            }
            if p.effective.contains(.hdrToggle) {
                list.append(DisplayMenuItemDescriptor(id: .dHDRToggle, title: L("High Dynamic Range"), slot: .display,
                                                      defaultVisibility: .hidden))
            }
            if p.effective.contains(.underscan) {
                list.append(DisplayMenuItemDescriptor(id: .dUnderscanMenu, title: L("Underscan"), slot: .display,
                                                      defaultVisibility: .hidden))
            }
        }
        if let w = power {
            if w.effective.contains(.disconnect) {
                list += [
                    DisplayMenuItemDescriptor(id: .dDisconnectItem, title: PowerController.disconnectTitle, slot: .header,
                                              defaultVisibility: .inSubmenu),
                    DisplayMenuItemDescriptor(id: .dConnectAll, title: L("Connect All Displays"), slot: .tools,
                                              defaultVisibility: .visible),
                    DisplayMenuItemDescriptor(id: .dDisconnectAllButMain, title: L("Disconnect All But Main"), slot: .tools,
                                              defaultVisibility: .visible),
                ]
            }
            if w.effective.contains(.sleepPrevention) {
                list.append(DisplayMenuItemDescriptor(id: .dSleepPrevention, title: L("Prevent Display Sleep"), slot: .display,
                                                      defaultVisibility: .inSubmenu))
            }
        }
        if let p = protection, p.effective.contains(.protection) {
            list.append(DisplayMenuItemDescriptor(id: .dProtection, title: L("Protect Arrangement"), slot: .tools,
                                                  defaultVisibility: .visible))
        }
        if let s = smartHiDPI, s.effective.contains(.smartHiDPI) {
            list.append(DisplayMenuItemDescriptor(id: .dSmartHiDPI, title: L("Sharper Text"), slot: .display,
                                                  defaultVisibility: .hidden))
        }
        return list
    }

    // MARK: Per display

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] {
        var items: [(DisplayMenuItemID, NSMenuItem)] = []
        if let a = arrangement { items += arrangementItems(a, display) }
        if let p = panelProps { items += panelItems(p, display) }
        if let s = smartHiDPI { items += smartHiDPIItems(s, display) }
        if let w = power { items += powerItems(w, display) }
        return items
    }

    private func arrangementItems(_ a: ArrangementController, _ display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard let ctx = context, display.isOnline else { return [] }
        let key = display.key
        var items: [(DisplayMenuItemID, NSMenuItem)] = []
        if a.effective.contains(.mainDisplay), display.isActive, !display.isMain, a.setMainRefusal(key) == nil {
            let item = MenuKit.action(L("Use as Main Display"), control: ControlID("menu.display.dm.useAsMain")) { [weak a] in
                a?.setMain(key)
            }
            items.append((.dSetMain, item))
        }
        if a.effective.contains(.mirroring), display.isActive {
            for other in ManagedDisplays.all(ctx) where other.key != key && other.isActive && other.mirrorOf == nil {
                let mirroring = display.mirrorOf == other.desktopID
                let source = other.key
                let item = MenuKit.toggle(L("Mirror “\(other.name)”"), isOn: mirroring,
                                          control: ControlID("menu.display.dm.mirror")) { [weak a] in
                    a?.mirror(key, of: mirroring ? nil : source)
                }
                items.append((.dMirrorMenu, item))
            }
        }
        return items
    }

    private func panelItems(_ p: PanelPropsController, _ display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] {
        let key = display.key
        var items: [(DisplayMenuItemID, NSMenuItem)] = []
        if p.effective.contains(.rotation), !display.isBuiltin, display.isActive {
            let current = p.rotation(display)
            let enabled = p.refusal(.rotation, for: display) == nil
            items.append((.dRotationMenu, MenuKit.header(L("Rotation"), control: ControlID("menu.display.dm.rotation"))))
            for degrees in PanelPropsController.rotations {
                let title = degrees == 0 ? L("Standard") : "\(degrees)°"
                let item = MenuKit.toggle(title, isOn: degrees == current, enabled: enabled,
                                          control: ControlID("menu.display.dm.rotation")) { [weak p] in
                    p?.rotate(key, to: degrees)
                }
                items.append((.dRotationMenu, item))
            }
        }
        if p.effective.contains(.hdrToggle), display.isActive, display.hdrSupported == true {
            let on = p.hdrEnabled(display) == true
            let refusal = p.refusal(.hdrToggle, for: display)
            let item = MenuKit.toggle(L("High Dynamic Range"), isOn: on, enabled: refusal == nil,
                                      control: ControlID("menu.display.dm.hdr")) { [weak p] in
                p?.setHDR(key, !on)
            }
            item.toolTip = refusal
            items.append((.dHDRToggle, item))
        }
        // Same rule as the Connection section: where macOS reports underscan, or for external displays.
        if p.effective.contains(.underscan), display.isActive, p.underscan(display) != nil || !display.isBuiltin {
            let item = MenuKit.action(L("Underscan…"), control: ControlID("menu.display.dm.underscan")) { [weak self] in
                self?.context?.openSettings("displays.connection")
            }
            items.append((.dUnderscanMenu, item))
        }
        return items
    }

    private func smartHiDPIItems(_ s: SmartHiDPIController, _ display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard s.effective.contains(.smartHiDPI),
              display.transport == .builtin || display.transport == .wired || display.isSmartHiDPIPair else { return [] }
        let key = display.key
        let item = MenuKit.toggle(L("Sharper Text"), isOn: s.isActive(key), enabled: !s.isBusy(key),
                                  control: ControlID("menu.display.dm.sharperText")) { [weak s] in
            s?.toggle(key)
        }
        return [(.dSmartHiDPI, item)]
    }

    private func powerItems(_ w: PowerController, _ display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard let ctx = context else { return [] }
        let key = display.key
        var items: [(DisplayMenuItemID, NSMenuItem)] = []
        if w.effective.contains(.disconnect) {
            if w.disabledKeys.contains(key) || (display.isOnline && !display.isActive) {
                // A disconnected display keeps a dimmed device row whose submenu offers Connect (parity M6).
                let item = MenuKit.action(L("Connect"), control: ControlID("menu.display.dm.connect")) { [weak w] in
                    w?.connect(key)
                }
                items.append((.dDisconnectItem, item))
            } else if display.isActive {
                let refusal = w.disconnectRefusal(display)
                let item = MenuKit.action(PowerController.disconnectTitle, enabled: refusal == nil,
                                          control: ControlID("menu.display.dm.disconnect")) { [weak w] in
                    w?.disconnect(key)
                }
                item.toolTip = refusal ?? PowerController.disconnectNote
                items.append((.dDisconnectItem, item))
            }
        }
        if w.effective.contains(.sleepPrevention), display.isOnline {
            let on = ctx.config.value.perDisplay[key]?.management.preventSleep ?? false
            let item = MenuKit.toggle(L("Prevent Display Sleep While Connected"), isOn: on,
                                      control: ControlID("menu.display.dm.preventSleep")) { [weak w] in
                w?.setPreventSleep(!on, for: key)
            }
            items.append((.dSleepPrevention, item))
        }
        return items
    }

    // MARK: Global

    /// `.tools` items: Arrange Displays… (the Displays section), Connect All Displays and Disconnect All But Main
    /// (Display Tools), and Protect Arrangement on its own while Saved Layouts is off (with Saved Layouts on it is in
    /// that submenu, through `protectArrangementItem()`).
    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard slot == .tools, let ctx = context else { return [] }
        var items: [(DisplayMenuItemID, NSMenuItem)] = []
        if let a = arrangement, a.effective.contains(.arrangement) {
            let item = MenuKit.action(L("Arrange Displays…"), symbol: "rectangle.3.group",
                                      control: ControlID("menu.display.dm.arrange")) { [weak self] in
                self?.context?.openSettings("displays.arrange")
            }
            items.append((.dArrange, item))
        }
        if let w = power, w.effective.contains(.disconnect) {
            let connectAll = MenuKit.action(L("Connect All Displays"), enabled: !w.disabledKeys.isEmpty,
                                            control: ControlID("menu.display.dm.connectAll")) { [weak w] in
                w?.connectAll()
            }
            let canDisconnect = ctx.registry.displays.contains { !$0.isMain && $0.isActive && w.disconnectRefusal($0) == nil }
            let allButMain = MenuKit.action(L("Disconnect All But Main"), enabled: canDisconnect,
                                            control: ControlID("menu.display.dm.disconnectAllButMain")) { [weak w] in
                w?.disconnectAllButMain()
            }
            items += [(.dConnectAll, connectAll), (.dDisconnectAllButMain, allButMain)]
        }
        if !ctx.runtime.isEffective(.layouts), let item = protectArrangementItem() {
            items.append((.dProtection, item))
        }
        return items
    }

    /// ✓ "Protect Arrangement" for the current display set; nil unless this instance is Protection's and the feature
    /// is on. LayoutsMenuItems puts it in Saved Layouts ›.
    func protectArrangementItem() -> NSMenuItem? {
        guard let p = protection, p.effective.contains(.protection) else { return nil }
        let item = MenuKit.toggle(L("Protect Arrangement"), isOn: p.isProtectingCurrent,
                                  control: ControlID("menu.display.dm.protectArrangement")) { [weak p] in
            p?.toggleCurrent()
        }
        if p.isPaused { item.toolTip = L("Paused because macOS keeps changing this arrangement") }
        return item
    }

    /// The Protection instance among the registered contributors (for LayoutsMenuItems).
    static func protectionItems(in registry: DisplayMenuRegistry) -> ManagementMenuItems? {
        registry.contributors.lazy.compactMap { $0 as? ManagementMenuItems }.first { $0.protection != nil }
    }
}
