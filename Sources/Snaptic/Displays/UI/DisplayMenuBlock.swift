import AppKit
import SnapticKit

/// One display's block in the Displays menu (PLAN §3.5): a header row (name, badges and
/// the `.header` slot switches), then the `.display` slot items, honoring the user's
/// MenuConfig (visible / "More" submenu / hidden), compact mode and collapsed blocks.
/// Item actions capture the DisplayKey and re-resolve it on click.
@MainActor final class DisplayMenuBlock: NSObject {
    let display: DisplayInfo
    private weak var context: DisplaysContext?
    private let showHeader: Bool
    /// Ignore collapsed state (the floating panel's "More options" menu).
    private let forceExpanded: Bool

    /// Features whose controls a block points to when they are off ("Turn On…" hints).
    private static let hintFeatures: [DisplayFeature] = [.brightness, .resolution, .ddcControls]

    init(display: DisplayInfo, context: DisplaysContext, showHeader: Bool, forceExpanded: Bool = false) {
        self.display = display
        self.context = context
        self.showHeader = showHeader
        self.forceExpanded = forceExpanded
        super.init()
    }

    func items() -> [NSMenuItem] {
        guard let ctx = context else { return [] }
        let menu = ctx.config.value.menu
        var content = Self.collect(for: display, context: ctx)
        let hints = Self.hintItems(for: display, context: ctx)
        if content.header.isEmpty && content.visible.isEmpty {
            content.visible += hints
        } else {
            content.more += hints
        }
        let key = display.key

        guard showHeader else {
            var items = content.header + content.visible
            if !content.more.isEmpty { items.append(Self.submenuItem(L("More"), symbol: "ellipsis.circle", content.more)) }
            return items
        }

        let collapsed = !forceExpanded && menu.isCollapsed(key)
        let header = headerItem(badges: menu.showBadges && !menu.compact)
        if collapsed {
            let expand = Self.actionItem(L("Expand in Menu"), symbol: "chevron.down") { [weak ctx] in
                ctx?.config.value.menu.setCollapsed(false, for: key)
            }
            var inner: [NSMenuItem] = [expand, NSMenuItem.separator()]
            inner += content.header
            inner += content.visible
            if !content.more.isEmpty {
                inner.append(NSMenuItem.separator())
                inner += content.more
            }
            header.submenu = Self.menu(inner, title: display.name)
            return [header]
        }
        if menu.compact {
            var inner: [NSMenuItem] = []
            if !forceExpanded {
                inner.append(Self.actionItem(L("Collapse in Menu"), symbol: "chevron.up") { [weak ctx] in
                    ctx?.config.value.menu.setCollapsed(true, for: key)
                })
            }
            if !content.more.isEmpty {
                if !inner.isEmpty { inner.append(.separator()) }
                inner += content.more
            }
            if !inner.isEmpty { header.submenu = Self.menu(inner, title: display.name) }
            return [header] + content.header + content.visible
        }
        if !forceExpanded {
            Self.attach(header) { [weak ctx] in ctx?.config.value.menu.setCollapsed(true, for: key) }
            header.toolTip = L("Click to collapse this display in the menu")
        }
        var items = [header] + content.header + content.visible
        if !content.more.isEmpty { items.append(Self.submenuItem(L("More"), symbol: "ellipsis.circle", content.more)) }
        return items
    }

    // MARK: Content

    struct Content {
        var header: [NSMenuItem] = []
        var visible: [NSMenuItem] = []
        var more: [NSMenuItem] = []
    }

    /// Asks every contributor for this display's items and sorts them by slot and the
    /// user's visibility choice. A header switch the user moved to "More" goes there.
    static func collect(for display: DisplayInfo, context: DisplaysContext) -> Content {
        let menu = context.config.value.menu
        var headerEntries: [(id: DisplayMenuItemID, item: NSMenuItem)] = []
        var displayEntries: [(id: DisplayMenuItemID, item: NSMenuItem)] = []
        var defaults: [DisplayMenuItemID: MenuItemVisibility] = [:]
        for contributor in context.menus.contributors {
            var slots: [DisplayMenuItemID: MenuSlot] = [:]
            for descriptor in contributor.descriptors {
                slots[descriptor.id] = descriptor.slot
                defaults[descriptor.id] = descriptor.defaultVisibility
            }
            for (id, item) in contributor.menuItems(for: display) {
                if slots[id] == .header {
                    headerEntries.append((id: id, item: item))
                } else {
                    displayEntries.append((id: id, item: item))
                }
            }
        }
        let header = menu.partition(headerEntries) { defaults[$0] ?? .visible }
        let body = menu.partition(displayEntries) { defaults[$0] ?? .visible }
        return Content(header: header.visible, visible: body.visible, more: header.more + body.more)
    }

    /// "Turn On Brightness Control" for features that are available but switched off, or
    /// the pause reason while another display app runs (PLAN §3.8).
    static func hintItems(for display: DisplayInfo, context: DisplaysContext) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for feature in hintFeatures {
            if feature == .ddcControls && display.isBuiltin { continue }
            if feature == .resolution && !display.isActive { continue }
            switch hint(for: feature, context: context) {
            case .nothing: break
            case .paused(let reason):
                items.append(infoItem("\(DisplaysUIText.title(feature)): \(reason)", symbol: "pause.circle"))
            case .turnOn:
                items.append(actionItem(L("Turn On \(DisplaysUIText.title(feature))"), symbol: "power") { [weak context] in
                    if let context { enable(feature, context: context) }
                })
            }
        }
        return items
    }

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
        // On but not effective (Safe Mode, panic latch, missing requirement): the banners
        // and the Features page explain that.
        if FeatureGraph.rawState(feature, in: context.config.value.rawFeatures) { return .nothing }
        return .turnOn
    }

    // MARK: Header

    private func headerItem(badges showBadges: Bool) -> NSMenuItem {
        let paused = !(context?.otherApps.pausedDisplayFeatures.isEmpty ?? true)
        let badges = showBadges ? Self.badges(for: display, paused: paused) : []
        let item = NSMenuItem(title: display.name, action: nil, keyEquivalent: "")
        let title = NSMutableAttributedString(string: display.name, attributes: [
            .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
        ])
        if !badges.isEmpty {
            title.append(NSAttributedString(string: "  " + badges.joined(separator: " · "), attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            // VoiceOver reads the plain title; keep the badges in it.
            item.title = display.name + ", " + badges.joined(separator: ", ")
        }
        item.attributedTitle = title
        item.image = NSImage(systemSymbolName: Self.symbol(for: display), accessibilityDescription: nil)
        return item
    }

    /// Status badges for a display header (PLAN §3.5). Safe Mode and Unprotected are
    /// global and shown as banners instead.
    static func badges(for display: DisplayInfo, paused: Bool) -> [String] {
        var badges: [String] = []
        if display.isMain { badges.append(L("Main")) }
        if display.transport == .snapticVirtual || display.transport == .foreignVirtual { badges.append(L("Virtual")) }
        if display.mirrorOf != nil { badges.append(L("Mirroring")) }
        if display.isSmartHiDPIPair { badges.append(L("Smart HiDPI")) }
        if !display.isOnline || !display.isActive { badges.append(L("Disconnected")) }
        if paused { badges.append(L("Paused")) }
        return badges
    }

    static func symbol(for display: DisplayInfo) -> String {
        switch display.transport {
        case .builtin: return "laptopcomputer"
        case .airplay: return "airplayvideo"
        case .sidecar: return "ipad.landscape"
        case .snapticVirtual, .foreignVirtual: return "rectangle.dashed"
        case .wired, .displayLink: return "display"
        }
    }

    // MARK: Menu item helpers (shared by the builder and the overview controller)

    /// Keeps a closure alive for an NSMenuItem (whose `target` is weak).
    @MainActor final class ActionTarget: NSObject {
        let handler: @MainActor () -> Void
        init(_ handler: @escaping @MainActor () -> Void) {
            self.handler = handler
            super.init()
        }
        @objc func fire(_ sender: Any?) { handler() }
    }

    static func attach(_ item: NSMenuItem, handler: @escaping @MainActor () -> Void) {
        let target = ActionTarget(handler)
        item.target = target
        item.action = #selector(ActionTarget.fire(_:))
        item.representedObject = target
        item.isEnabled = true
    }

    static func actionItem(_ title: String, symbol: String? = nil, handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        attach(item, handler: handler)
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    /// A disabled line of text (state, reason).
    static func infoItem(_ title: String, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    static func submenuItem(_ title: String, symbol: String? = nil, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        item.submenu = menu(items, title: title)
        return item
    }

    static func menu(_ items: [NSMenuItem], title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        for item in items {
            // An item can live in one menu only; contributors hand out fresh items, but be safe.
            item.menu?.removeItem(item)
            menu.addItem(item)
        }
        return menu
    }

    // MARK: Shared actions

    /// Turns a feature on with everything it requires (the same rule as
    /// DisplaysModule.enable, for places that only have the context).
    static func enable(_ feature: DisplayFeature, context: DisplaysContext) {
        let available = Set(context.runtime.availability.compactMap { $0.value.isAvailable ? $0.key : nil })
        var value = context.config.value
        for (f, on) in FeatureGraph.enabling(feature, raw: value.rawFeatures, available: available) {
            value.features[f] = on
        }
        context.config.value = value
        EventLog.shared.record(.modules, "Turned on \(feature.rawValue) from the Displays menu")
    }

    /// Posted with `userInfo["page"]` (a settings page id such as "displays.features") so
    /// the settings window can select that page (team A observes it).
    static let openSettingsNotification = Notification.Name("SnapticOpenSettingsPage")

    /// Opens Settings through the app's reopen path (which shows Settings, PLAN §3.5),
    /// then asks it to show `page`.
    static func openSettings(page: String) {
        if let delegate = NSApp.delegate {
            _ = delegate.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: true)
        }
        NotificationCenter.default.post(name: openSettingsNotification, object: nil, userInfo: ["page": page])
    }
}
