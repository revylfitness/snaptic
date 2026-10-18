import AppKit
import SnapticKit

/// One display in the Displays menu (PLAN 0.3 §5.2): a device row whose one-level submenu holds the display's
/// options, the display's sliders (`MenuSliderRow`, top level, never in a submenu) and, when the user chose Show,
/// Disconnect / Turn Off Display right under the device row (migration M10). A disconnected display keeps a dimmed
/// device row whose submenu offers Connect.
///
/// The contributors build the items (`DisplayMenuContributor.menuItems(for:)`, one `DisplayMenuItemID` per item,
/// several items per id allowed); this block places them with the Kit table (`DisplaysMenuPlan`) and the user's
/// Customize Displays Menu choices. An item a contributor still hands over as a submenu is flattened into the
/// display submenu under its header ("Rotation", "Input"…), and images are dropped inside the submenu (§5.1: images
/// on every item of a section or on none). Item actions capture the `DisplayKey` and re-resolve it on click.
@MainActor final class DisplayMenuBlock: NSObject, ControlDeclaring {
    typealias Controls = DisplayMenuBlockControls

    let display: DisplayInfo
    private weak var context: DisplaysContext?
    /// 0.2 parameters, kept for existing callers: `forceExpanded` with `showHeader == false` asks for the submenu
    /// content alone (the floating panel's "⋯" menu, §5.6).
    private let showHeader: Bool
    private let forceExpanded: Bool

    init(display: DisplayInfo, context: DisplaysContext, showHeader: Bool = true, forceExpanded: Bool = false) {
        self.display = display
        self.context = context
        self.showHeader = showHeader
        self.forceExpanded = forceExpanded
        super.init()
    }

    /// The panel's "⋯" menu (`showHeader: false, forceExpanded: true`): the submenu content; otherwise the block's
    /// top-level rows with the standard layout.
    func items() -> [NSMenuItem] {
        if forceExpanded && !showHeader { return submenuItems() }
        return topLevelItems(slidersFirst: false)
    }

    var isDisconnected: Bool { !display.isOnline || !display.isActive }

    // MARK: Top level

    /// Device row, sliders and promoted items. `slidersFirst`: one display with "Display row with one display" off
    /// (the sliders lead, the device row follows them).
    func topLevelItems(slidersFirst: Bool) -> [NSMenuItem] {
        guard let ctx = context else { return [] }
        let menu = ctx.config.value.menu
        let content = Self.collect(for: display, context: ctx)
        let device = deviceRow(submenu: submenu(from: content, context: ctx), context: ctx)
        guard !isDisconnected else { return [device] }

        var sliders = content.sliders
        if menu.style == .compact, let keep = DisplaysMenuPlan.compactSlider(sliders.map(\.id)) {
            sliders = [sliders[keep]]
        }
        let sliderItems = sliders.map(\.item)
        let promoted = content.underDevice.map { entry -> NSMenuItem in
            if let symbol = DisplaysMenuPlan.info(for: entry.id)?.symbol, let image = MenuKit.symbolImage(symbol) {
                entry.item.image = image
            }
            return entry.item
        }
        if slidersFirst { return sliderItems + [device] + promoted }
        return [device] + sliderItems + promoted
    }

    /// The display submenu's content (also the panel's "⋯" menu).
    func submenuItems() -> [NSMenuItem] {
        guard let ctx = context else { return [] }
        return submenu(from: Self.collect(for: display, context: ctx), context: ctx)
    }

    private func deviceRow(submenu: [NSMenuItem], context ctx: DisplaysContext) -> NSMenuItem {
        let symbol = Self.symbol(for: display, config: ctx.config.value)
        let row: NSMenuItem
        let subtitle: String?
        if isDisconnected {
            row = MenuKit.device(display.name, symbol: symbol, dimmed: true, submenu: submenu,
                                 control: ControlID("menu.display.disconnected"))
            subtitle = L("Disconnected")
        } else {
            row = MenuKit.device(display.name, symbol: symbol, submenu: submenu, control: ControlID("menu.display.device"))
            let menu = ctx.config.value.menu
            subtitle = DisplaysMenuPlan.deviceSubtitle(badges: Self.menuBadges(for: display, context: ctx),
                                                       style: menu.style, showBadges: menu.showBadges)
        }
        return MenuKit.withSubtitle(row, subtitle)
    }

    // MARK: Collecting

    /// One contributor's items for one id, in the contributor's order.
    struct Entry {
        let id: DisplayMenuItemID
        let item: NSMenuItem
    }

    struct Content {
        var sliders: [Entry] = []
        var underDevice: [Entry] = []
        var groups: [DisplaySubmenuGroup: [Entry]] = [:]
    }

    /// Asks every contributor for this display's items and places each with the Kit table and the user's choice.
    /// A disconnected display keeps only its connect items (Connect, Turn On Display), in the submenu.
    static func collect(for display: DisplayInfo, context: DisplaysContext) -> Content {
        let menu = context.config.value.menu
        var defaults: [DisplayMenuItemID: MenuItemVisibility] = [:]
        for descriptor in context.menus.descriptors where defaults[descriptor.id] == nil {
            defaults[descriptor.id] = descriptor.defaultVisibility
        }
        let disconnected = !display.isOnline || !display.isActive
        var content = Content()
        for contributor in context.menus.contributors {
            for (id, item) in contributor.menuItems(for: display) {
                detach(item)
                let entry = Entry(id: id, item: item)
                if disconnected {
                    if id.rawValue == "d.disconnectItem" || id == .cDDCPower, item.view == nil {
                        content.groups[.power, default: []].append(entry)
                    }
                    continue
                }
                let visibility = menu.visibility(of: id, default: DisplaysMenuPlan.defaultVisibility(id, declared: defaults[id]))
                switch DisplaysMenuPlan.place(id, visibility: visibility, perDisplay: true, isCustomRow: item.view != nil) {
                case .slider?: content.sliders.append(entry)
                case .underDevice?: content.underDevice.append(entry)
                case .submenu(let group)?: content.groups[group, default: []].append(entry)
                case .sectionItem?, .sectionMenu?, .tools?, .pausedStatus?, nil: break
                }
            }
        }
        content.sliders = sorted(content.sliders)
        content.underDevice = sorted(content.underDevice)
        for (group, entries) in content.groups { content.groups[group] = sorted(entries) }
        return content
    }

    /// Table order, stable within an id (a contributor's own order is kept).
    static func sorted(_ entries: [Entry]) -> [Entry] {
        entries.enumerated().sorted { a, b in
            let ra = DisplaysMenuPlan.rank(a.element.id), rb = DisplaysMenuPlan.rank(b.element.id)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: The submenu

    /// Groups in §5.2 order with one separator between non-empty groups, then "Display Settings…".
    private func submenu(from content: Content, context ctx: DisplaysContext) -> [NSMenuItem] {
        var blocks: [[NSMenuItem]] = []
        for group in DisplaySubmenuGroup.allCases {
            var items = Self.flatten(content.groups[group] ?? [])
            if group == .resolution, !items.isEmpty, !isDisconnected, ctx.runtime.isEffective(.resolution),
               !items.contains(where: { $0.title == L("More Resolutions…") }) {
                let open = ctx.openSettings
                items.append(MenuKit.action(L("More Resolutions…"), control: ControlID("menu.display.moreResolutions")) {
                    open("displays.resolution")
                })
            }
            if !items.isEmpty { blocks.append(items) }
        }
        let key = display.key
        let open = ctx.openSettings
        blocks.append([MenuKit.action(L("Display Settings…"), control: ControlID("menu.display.settings")) {
            SettingsShell.shared.selectedDisplay = key
            open("displays")
        }])
        var result: [NSMenuItem] = []
        for block in blocks {
            if !result.isEmpty { result.append(MenuKit.separator()) }
            result += block
        }
        return result
    }

    /// The rows of one submenu group: entries of one id together, a submenu handed over by a contributor flattened
    /// into its children (nested submenus dropped: one level only), the id's header in front where the table names
    /// one and the contributor didn't add it, images removed, and every row tagged with its control.
    static func flatten(_ entries: [Entry]) -> [NSMenuItem] {
        var result: [NSMenuItem] = []
        var index = 0
        while index < entries.count {
            let id = entries[index].id
            var rows: [NSMenuItem] = []
            while index < entries.count && entries[index].id == id {
                let item = entries[index].item
                if let sub = item.submenu {
                    let children = sub.items
                    sub.removeAllItems()
                    rows += children.filter { $0.submenu == nil }
                } else {
                    rows.append(item)
                }
                index += 1
            }
            while rows.first?.isSeparatorItem == true { rows.removeFirst() }
            while rows.last?.isSeparatorItem == true { rows.removeLast() }
            guard !rows.isEmpty else { continue }
            let control = Self.control(for: id)
            for row in rows {
                row.image = nil
                if row.identifier == nil, let control { row.identifier = NSUserInterfaceItemIdentifier(control.rawValue) }
            }
            if let header = DisplaysMenuPlan.info(for: id)?.header, !(rows.first?.isSectionHeader ?? false) {
                rows.insert(MenuKit.header(header, control: control), at: 0)
            }
            result += rows
        }
        return result
    }

    /// An item can live in one menu only.
    static func detach(_ item: NSMenuItem) {
        item.menu?.removeItem(item)
    }

    /// The control each per-display 0.2 menu id is placed as (DisplayMenuBlockControls).
    static func control(for id: DisplayMenuItemID) -> ControlID? {
        switch id.rawValue {
        case "c.brightness.slider": return ControlID("menu.display.brightness")
        case "c.ddc.volume": return ControlID("menu.display.volume")
        case "c.ddc.contrast": return ControlID("menu.display.contrast")
        case "c.ddc.custom": return ControlID("menu.display.customControl")
        case "d.resolutionSlider": return ControlID("menu.display.resolutionSlider")
        case "d.resolutionMenu": return ControlID("menu.display.resolutions")
        case "d.setMain": return ControlID("menu.display.useAsMain")
        case "d.mirrorMenu": return ControlID("menu.display.mirror")
        case "d.hdrToggle": return ControlID("menu.display.hdr")
        case "c.xdr.toggle": return ControlID("menu.display.extraBrightness")
        case "d.smartHiDPI": return ControlID("menu.display.sharperText")
        case "c.color.submenu": return ControlID("menu.display.adjustColors")
        case "c.color.autoBrightness": return ControlID("menu.display.autoBrightness")
        case "c.menuBarStrip.toggle": return ControlID("menu.display.menuBarBackground")
        case "d.underscanMenu": return ControlID("menu.display.underscan")
        case "e.pip.display": return ControlID("menu.display.pip")
        case "d.rotationMenu": return ControlID("menu.display.rotation")
        case "c.color.profiles": return ControlID("menu.display.colorProfile")
        case "c.color.applePresets": return ControlID("menu.display.preset")
        case "c.ddc.input": return ControlID("menu.display.input")
        case "c.ddc.mute": return ControlID("menu.display.mute")
        case "c.ddc.power": return ControlID("menu.display.power")
        case "d.disconnectItem": return ControlID("menu.display.disconnect")
        default: return nil
        }
    }

    // MARK: Badges and symbols

    /// The device row's subtitle words (§5.2 "Main"): state a person can't see from the name.
    static func menuBadges(for display: DisplayInfo, context: DisplaysContext) -> [String] {
        var badges: [String] = []
        if display.isMain { badges.append(L("Main")) }
        if display.transport == .snapticVirtual || display.transport == .foreignVirtual { badges.append(L("Virtual")) }
        if display.mirrorOf != nil { badges.append(L("Mirroring")) }
        if display.isSmartHiDPIPair { badges.append(L("Sharper Text")) }
        if !context.otherApps.pausedDisplayFeatures.isEmpty { badges.append(L("Paused")) }
        return badges
    }

    /// Status badges (0.2 wording, for the 0.2 pages until the step-3 exit).
    static func badges(for display: DisplayInfo, paused: Bool, keptAwake: Bool = false) -> [String] {
        var badges: [String] = []
        if display.isMain { badges.append(L("Main")) }
        if display.transport == .snapticVirtual || display.transport == .foreignVirtual { badges.append(L("Virtual")) }
        if display.mirrorOf != nil { badges.append(L("Mirroring")) }
        if display.isSmartHiDPIPair { badges.append(L("Smart HiDPI")) }
        if !display.isOnline || !display.isActive { badges.append(L("Disconnected")) }
        if keptAwake { badges.append(L("Kept Awake")) }
        if paused { badges.append(L("Paused")) }
        return badges
    }

    /// Badges from the live state: other-app pause, and "Kept Awake" while D's PowerController holds the sleep
    /// assertion for this display.
    static func badges(for display: DisplayInfo, context: DisplaysContext) -> [String] {
        badges(for: display, paused: !context.otherApps.pausedDisplayFeatures.isEmpty,
               keptAwake: isKeptAwake(display, context: context))
    }

    static func isKeptAwake(_ display: DisplayInfo, context: DisplaysContext) -> Bool {
        context.runtime.sleepPreventionActive && display.isOnline
            && (context.config.value.perDisplay[display.key]?.management.preventSleep ?? false)
    }

    /// The user's icon (Display Details) when it is a symbol this macOS has, else by transport.
    static func symbol(for display: DisplayInfo, config: DisplaysConfig?) -> String {
        if let chosen = config?.perDisplay[display.key]?.identity.symbol,
           NSImage(systemSymbolName: chosen, accessibilityDescription: nil) != nil {
            return chosen
        }
        return symbol(for: display)
    }

    /// The default icon for a display's connection.
    static func symbol(for display: DisplayInfo) -> String {
        switch display.transport {
        case .builtin: return "laptopcomputer"
        case .airplay: return "airplayvideo"
        case .sidecar: return "ipad.landscape"
        case .snapticVirtual, .foreignVirtual: return "rectangle.dashed"
        case .wired, .displayLink: return "display"
        }
    }

    // MARK: Feature hints (0.2 Overview page)

    enum Hint: Equatable {
        case nothing
        case paused(String)
        case turnOn
    }

    /// Why a feature's control is missing, if the user can do something about it.
    static func hint(for feature: DisplayFeature, context: DisplaysContext) -> Hint {
        if context.runtime.isEffective(feature) { return .nothing }
        if let reason = context.otherApps.pauseReason(for: feature) { return .paused(reason) }
        if let availability = context.runtime.availability[feature], !availability.isAvailable { return .nothing }
        // On but not effective (Safe Mode, panic latch, missing requirement): the status rows explain that.
        if FeatureGraph.rawState(feature, in: context.config.value.rawFeatures) { return .nothing }
        return .turnOn
    }

    // MARK: 0.2 item helpers (callers move to MenuKit; deleted at the 0.3 step-3 exit)

    static func actionItem(_ title: String, symbol: String? = nil, handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        MenuKit.action(title, symbol: symbol, handler)
    }

    /// A disabled line of text (state, reason).
    static func infoItem(_ title: String, symbol: String? = nil) -> NSMenuItem {
        MenuKit.status(title, symbol: symbol)
    }

    /// A submenu row. Unlike `MenuKit.submenu` it keeps nested submenus (0.2 contributors still build them).
    static func submenuItem(_ title: String, symbol: String? = nil, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = MenuKit.action(title, symbol: symbol) {}
        item.action = nil
        item.target = nil
        item.submenu = menu(items, title: title)
        return item
    }

    static func menu(_ items: [NSMenuItem], title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        for item in items {
            detach(item)
            menu.addItem(item)
        }
        return menu
    }

    // MARK: Shared actions

    /// Turns a feature on with everything it requires (the same rule as DisplaysModule.enable, for places that only
    /// have the context).
    static func enable(_ feature: DisplayFeature, context: DisplaysContext) {
        let available = Set(context.runtime.availability.compactMap { $0.value.isAvailable ? $0.key : nil })
        var value = context.config.value
        for (f, on) in FeatureGraph.enabling(feature, raw: value.rawFeatures, available: available) {
            value.features[f] = on
        }
        context.config.value = value
        EventLog.shared.record(.modules, "Turned on \(feature.rawValue) from the Displays menu")
    }

    /// Posted with `userInfo["page"]` (a settings page id such as "displays.features"); SettingsWindowHost
    /// observes it.
    static let openSettingsNotification = Notification.Name("SnapticOpenSettingsPage")

    /// For callers that have no context (E's PIP menu). Everything in F uses `ctx.openSettings(page)`, the host's
    /// own path.
    static func openSettings(page: String) {
        NotificationCenter.default.post(name: openSettingsNotification, object: nil, userInfo: ["page": page])
    }
}
