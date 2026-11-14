import Foundation

// A4a: the pure parts of `DockPreviewController` (PLAN 0.5 §4.1–§4.4, §4.7, §4.8). The policy is K3's
// `DockPreviewPolicy` and the geometry K2's `DockGeometry`; these rules join them to the app's reads.

/// What the Dock observer last read, for the policy's geometry closures (§R4 K3: live K2 geometry, not the `plain…`
/// stand-ins). Item frames come from the observer's list-frame read; screens from `NSScreen` while the pointer is
/// watched. Cocoa coordinates.
package struct DockGeometrySnapshot: Equatable, Sendable {
    package var items: [DockRect]
    package var screens: [DockScreen]

    package init(items: [DockRect] = [], screens: [DockScreen] = []) {
        self.items = items
        self.screens = screens
    }
}

/// The one small card a panel can show instead of window cards (§4.3).
package enum DockSmallCard: String, CaseIterable, Sendable {
    /// “No open windows”: the app has no windows. A click activates it (G-18).
    case noOpenWindows
    /// “No windows shown”: settings hide every window it has.
    case noWindowsShown
    /// “Windows can’t be read right now”: the read timed out with nothing to fall back on.
    case cantRead
}

/// What a panel lists for one read: window indices in card order, then “More windows…” when the budget ran out, or
/// one small card, or nothing at all.
package struct DockCardPlan: Equatable, Sendable {
    /// Indices into the read's windows, in card order.
    package var order: [Int]
    /// “More windows…” as the last cell (§4.8, X3-12).
    package var moreWindows: Bool
    package var small: DockSmallCard?

    package init(order: [Int] = [], moreWindows: Bool = false, small: DockSmallCard? = nil) {
        self.order = order
        self.moreWindows = moreWindows
        self.small = small
    }

    /// Nothing to show: the panel stays hidden (the small cards' switch is off).
    package var isEmpty: Bool { order.isEmpty && !moreWindows && small == nil }
}

/// Where a panel for one anchor goes (§4.7): the anchor's screen, the Dock's edge and at-rest thickness, and the room
/// `DockGeometry.panelArea` leaves.
package struct DockPanelSite: Equatable, Sendable {
    package var screen: DockScreen
    package var edge: DockEdge
    package var restingThickness: Double
    package var area: DockRect

    package init(screen: DockScreen, edge: DockEdge, restingThickness: Double, area: DockRect) {
        self.screen = screen
        self.edge = edge
        self.restingThickness = restingThickness
        self.area = area
    }
}

/// §2.4's `pointerMoved`: at most one move per display frame (S0-28), and the last move of a burst is never lost.
package struct DockMoveThrottle: Equatable, Sendable {
    /// 60 Hz.
    package static let interval = 1.0 / 60

    private var lastSentAt = -Double.infinity
    private var held: DockPoint?

    package init() {}

    /// A move the throttle held back; `flush` sends it once `flushAt` is due.
    package var isHolding: Bool { held != nil }
    /// When the held move may go.
    package var flushAt: Double? { held == nil ? nil : lastSentAt + Self.interval }

    /// The point to send now, or nil when the move is held for `flush`.
    package mutating func moved(to p: DockPoint, now: Double) -> DockPoint? {
        if now - lastSentAt >= Self.interval {
            lastSentAt = now
            held = nil
            return p
        }
        held = p
        return nil
    }

    /// The held move, once it's due.
    package mutating func flush(now: Double) -> DockPoint? {
        guard let p = held, now - lastSentAt >= Self.interval else { return nil }
        held = nil
        lastSentAt = now
        return p
    }

    package mutating func reset() {
        self = DockMoveThrottle()
    }
}

package enum DockPreviewRules {

    // MARK: Geometry for the policy (§R4 K3)

    /// The policy's geometry from K2, reading the latest snapshot on each call. Without a screen for the item (a
    /// display change mid-read) it falls back to the `plain…` stand-ins, which need no screen.
    package static func liveGeometry(_ snapshot: @escaping @Sendable () -> DockGeometrySnapshot)
        -> DockPolicyGeometry {
        DockPolicyGeometry(
            hitBand: { s in hitBand(s, snapshot()) },
            edge: { s in edge(s, snapshot()) },
            zone: { s in zone(s, snapshot()) },
            corridor: { item, panel, edge in DockGeometry.corridor(item: item, panel: panel, edge: edge).points })
    }

    /// The Dock's edge for a selection: from its settled item frame and the Dock's frame on the item's screen.
    package static func edge(_ s: DockSelection, _ snapshot: DockGeometrySnapshot) -> DockEdge {
        guard let screen = DockGeometry.screen(holding: s.itemFrame, in: snapshot.screens) else {
            return DockPolicyGeometry.plainEdge(s)
        }
        return DockGeometry.edge(ofItem: s.itemFrame, dock: dockFrame(s, snapshot), on: screen)
    }

    /// K2's hit band. Cached item frames that overlap the item along the Dock are stale reads of this item or of
    /// neighbours magnification has pushed aside, so they're left out of the neighbour gaps.
    package static func hitBand(_ s: DockSelection, _ snapshot: DockGeometrySnapshot) -> DockRect {
        guard let screen = DockGeometry.screen(holding: s.itemFrame, in: snapshot.screens) else {
            return DockPolicyGeometry.plainHitBand(s)
        }
        let e = edge(s, snapshot)
        return DockGeometry.hitBand(item: s.itemFrame, items: neighbours(of: s.itemFrame, snapshot.items, edge: e),
                                    edge: e, screen: screen)
    }

    /// One selection's zone rects: the Dock's frame (the union of item frames and the list frame) and the item grown
    /// for magnification (§4.1).
    package static func zone(_ s: DockSelection, _ snapshot: DockGeometrySnapshot) -> [DockRect] {
        DockZone().adding(dock: dockFrame(s, snapshot), hoveredItem: s.itemFrame).rects
    }

    /// The Dock's frame: the item frames on the item's screen, with the list frame and the item itself.
    package static func dockFrame(_ s: DockSelection, _ snapshot: DockGeometrySnapshot) -> DockRect? {
        let screen = DockGeometry.screen(holding: s.itemFrame, in: snapshot.screens)
        let items = snapshot.items.filter { r in screen.map { $0.frame.intersects(r) } ?? true }
        return DockGeometry.dockFrame(items: items + [s.listFrame, s.itemFrame])
    }

    /// Neighbours may overlap the item by this much along the Dock and still count (rounding in AX frames).
    package static let neighbourOverlap = 1.0

    /// Item frames other than `item`'s, without any that overlap `item` along the Dock by more than
    /// `neighbourOverlap`: live neighbours abut it, so an overlapping one is a stale read.
    package static func neighbours(of item: DockRect, _ items: [DockRect], edge: DockEdge) -> [DockRect] {
        let lo = edge.isHorizontal ? item.minX : item.minY, hi = edge.isHorizontal ? item.maxX : item.maxY
        return items.filter { r in
            guard !r.isDegenerate, r != item else { return false }
            let rLo = edge.isHorizontal ? r.minX : r.minY, rHi = edge.isHorizontal ? r.maxX : r.maxY
            return min(hi, rHi) - max(lo, rLo) <= neighbourOverlap
        }
    }

    // MARK: Cards (§4.3, §4.8)

    /// What one window read shows. `windows` is the read in its own order (it never holds “no windows” entries);
    /// `titles` matches it. `timedOut`: AX read nothing in time.
    /// - Nothing read: “Windows can’t be read right now” after a timeout, else “No open windows”.
    /// - Every window filtered out: “No windows shown”.
    /// - Both small cards follow the Advanced switch (§4.18); the timeout card always shows.
    /// - The budget ran out: the windows read so far, then “More windows…”.
    package static func plan(windows: [CatalogWindow], titles: [String], config: DockConfig, pid: Int32,
                             unreadRemain: Bool, timedOut: Bool, zOrder: [UInt32: Int]) -> DockCardPlan {
        let kept = WindowCatalogRules.filter(windows, .dock(config, pid: pid))
        if kept.isEmpty && !unreadRemain {
            if windows.isEmpty && timedOut { return DockCardPlan(small: .cantRead) }
            guard config.windowlessApps else { return DockCardPlan() }
            return DockCardPlan(small: windows.isEmpty ? .noOpenWindows : .noWindowsShown)
        }
        let subset = kept.map { windows[$0] }
        let subTitles = kept.map { titles.indices.contains($0) ? titles[$0] : "" }
        let sorted = WindowCatalogRules.dockOrder(subset, titles: subTitles, sort: config.sort, recency: nil,
                                                  zOrder: zOrder)
        return DockCardPlan(order: sorted.map { kept[$0] }, moreWindows: unreadRemain)
    }

    // MARK: Placement (§4.7)

    /// The small card's size: one line of text beside the app icon.
    package static let smallCard = DockSize(width: 240, height: 64)

    /// The panel that holds the small card: the card and the standard padding, no header.
    package static func smallPanel(metrics: DockPanelMetrics = .standard) -> DockSize {
        DockSize(width: smallCard.width + 2 * metrics.padding, height: smallCard.height + 2 * metrics.padding)
    }

    /// Where a panel for `anchor` (the settled item frame) goes. The at-rest thickness counts the anchor with the
    /// item frames on its screen, so a Dock read before any list frame still places the panel past the item. Nil when
    /// no screen holds the anchor or the screen leaves no room.
    package static func site(anchor: DockRect, edge: DockEdge, snapshot: DockGeometrySnapshot) -> DockPanelSite? {
        guard !anchor.isDegenerate, let screen = DockGeometry.screen(holding: anchor, in: snapshot.screens) else {
            return nil
        }
        let items = snapshot.items.filter { !$0.isDegenerate && screen.frame.intersects($0) } + [anchor]
        guard let thickness = DockGeometry.restingThickness(items: items, edge: edge, screen: screen),
              let area = DockGeometry.panelArea(restingThickness: thickness, edge: edge, screen: screen) else {
            return nil
        }
        return DockPanelSite(screen: screen, edge: edge, restingThickness: thickness, area: area)
    }

    /// The panel's frame for `panel` at `site`, centred on the anchor along the Dock.
    package static func frame(panel: DockSize, anchor: DockRect, site: DockPanelSite) -> DockRect? {
        DockGeometry.placement(panel: panel, item: anchor, restingThickness: site.restingThickness, edge: site.edge,
                               screen: site.screen)
    }

    // MARK: Events (§2.4, §4.2)

    /// An activation this soon after our own action is `byUs`.
    package static let byUsWindow = 1.5
    /// …and this soon after our own Quit.
    package static let quitByUsWindow = 5.0

    /// Whether an activation at `now` follows our own `action` at `at` closely enough to be ours.
    package static func isByUs(action: DockAction?, at: Double?, now: Double) -> Bool {
        guard let action, let at, now >= at else { return false }
        return now - at <= (action == .quitApp ? quitByUsWindow : byUsWindow)
    }

    /// The selection the policy sees. An app on “Apps hidden from Dock previews” (G2-4) and an item under a pressed
    /// button (a drag over the Dock) lose their pid, so they never show a panel but still move the selection.
    /// `voiceOver` is §4.1 rule 5's exception (VoiceOver runs and “Show previews while VoiceOver is on” is on): the
    /// selection alone drives the panel then (`byPointer == false`, G2-5).
    package static func mapped(_ s: DockSelection?, hiddenFromDock: Bool, buttonDown: Bool,
                               voiceOver: Bool = false) -> DockSelection? {
        guard var s else { return nil }
        if hiddenFromDock || buttonDown { s.pid = nil }
        if voiceOver { s.byPointer = false }
        return s
    }

    /// A mouse-down outside our panel while the pointer is watched (X-12): on the selected item (its frame or hit
    /// band) or elsewhere.
    package static func mouseDown(at p: DockPoint, selection: DockSelection?, hitBand: DockRect?) -> DockEvent {
        if let selection, selection.itemFrame.contains(p) || hitBand?.contains(p) == true {
            return .mouseDownOnItem(selection)
        }
        return .mouseDownOutside
    }

    /// While shown, the panel re-reads its app's windows every this many ticks (S0-26: 1 s at 0.1 s a tick).
    package static let refreshTicks = 10

    // MARK: Words (A4b: §4.4, §4.16)

    /// “1 window” or “3 windows” (§4.3's header; `SentenceText.unit`, G-24).
    package static func windowCount(_ n: Int) -> String {
        SentenceText.unit(n, L("window"), L("windows"))
    }

    /// A card's VoiceOver label, which is also its tooltip (§4.16): “\(title), \(app)” plus one state. A private card
    /// or a card of a protected app reads “Private window, \(app)”: the title is never a fallback (G2-15). An untitled
    /// card reads as its text does (the app name, or “Window on another Space, \(app)”).
    /// - `title` is the window's title as read; the caller has already blanked it for a private card.
    package static func cardLabel(_ w: CatalogWindow, privacy: CatalogPrivacy, title: String, app: String) -> String {
        var saysOtherSpace = false
        let text: String
        if privacy.isPrivate {
            text = L("Private window, \(app)")
        } else {
            switch WindowCatalogRules.dockCardText(w, privacy: privacy) {
            case .title:
                text = L("\(title), \(app)")
            case .windowOnAnotherSpace:
                saysOtherSpace = true
                let title = L("Window on another Space")
                text = L("\(title), \(app)")
            case .appName, .privateWindow:
                text = app
            }
        }
        return text + stateSuffix(w, saysOtherSpace: saysOtherSpace)
    }

    /// One state at most, in the badges' order with Hidden after Minimized: minimized, hidden, full screen, on another
    /// Space (§4.3, §4.16; §R4 A4b).
    private static func stateSuffix(_ w: CatalogWindow, saysOtherSpace: Bool) -> String {
        if w.windowless { return "" }
        if w.minimized { return L(", minimized") }
        if w.hidden { return L(", hidden") }
        if w.fullscreen { return L(", full screen") }
        if w.onOtherSpace, !saysOtherSpace { return L(", on another Space") }
        return ""
    }

    /// The small cards' VoiceOver labels (§4.16).
    package static func smallCardLabel(_ small: DockSmallCard, app: String) -> String {
        switch small {
        case .noOpenWindows: return L("No open windows, \(app)")
        case .noWindowsShown: return L("No windows shown, \(app)")
        case .cantRead: return L("Windows can’t be read right now, \(app)")
        }
    }

    /// What VoiceOver announces as a panel shows or swaps (§4.16): “Safari, 3 windows”, or the small card's label.
    /// `windows` counts every card, private ones included; no title is ever part of it (§4.10).
    package static func announcement(app: String, windows n: Int, small: DockSmallCard?) -> String {
        if let small { return smallCardLabel(small, app: app) }
        let windows = windowCount(n)
        return L("\(app), \(windows)")
    }

    /// The panel's accessibility group label (§4.16): “Safari windows”.
    package static func panelLabel(app: String) -> String {
        L("\(app) windows")
    }

    /// A header button's accessibility label (§4.4): the bare words.
    package static func headerLabel(_ b: DockHeaderButton, app: String) -> String {
        switch b {
        case .minimizeAll: return L("Minimize All")
        case .hideApp: return L("Hide \(app)")
        case .showApp: return L("Show \(app)")
        case .quitApp: return L("Quit \(app)")
        }
    }

    /// A header button's tooltip (§4.4): the label, plus the key while keys work (§4.5). Show takes ⌘H like Hide
    /// (§R4 A4b).
    package static func headerHelp(_ b: DockHeaderButton, app: String, keysWork: Bool) -> String {
        let label = headerLabel(b, app: app)
        guard keysWork else { return label }
        switch b {
        case .minimizeAll: return label
        case .hideApp, .showApp: return label + " " + L("(⌘H)")
        case .quitApp: return label + " " + L("(⌘Q)")
        }
    }

    /// The header's Hide button: Show while the app is hidden (§4.4, G2-1).
    package static func hideButton(appHidden: Bool) -> DockHeaderButton {
        appHidden ? .showApp : .hideApp
    }

    /// A hover button's accessibility label (§4.4): the bare word. A minimized card's yellow button restores it
    /// (§R4 A4b).
    package static func hoverLabel(_ b: DockHoverButton, minimized: Bool, fullScreen: Bool) -> String {
        switch b {
        case .close: return L("Close")
        case .minimize: return minimized ? L("Restore") : L("Minimize")
        case .fullScreen: return fullScreen ? L("Exit Full Screen") : L("Enter Full Screen")
        }
    }

    /// A hover button's tooltip (§4.4): the same words, with the key while keys work.
    package static func hoverHelp(_ b: DockHoverButton, minimized: Bool, fullScreen: Bool, keysWork: Bool) -> String {
        guard keysWork else { return hoverLabel(b, minimized: minimized, fullScreen: fullScreen) }
        switch b {
        case .close: return L("Close (⌘W)")
        case .minimize: return minimized ? L("Restore (⌘M)") : L("Minimize (⌘M)")
        case .fullScreen: return hoverLabel(b, minimized: minimized, fullScreen: fullScreen)
        }
    }

    /// What a hover button does.
    package static func action(for b: DockHoverButton, minimized: Bool) -> DockAction {
        switch b {
        case .close: return .close
        case .minimize: return minimized ? .restore : .minimize
        case .fullScreen: return .fullScreen
        }
    }

    /// The card's right-click menu (§4.4, G-16). A card without an AX element offers only Bring Forward (D2-25).
    package static func cardMenu(hasAXElement: Bool, minimized: Bool, fullScreen: Bool, appHidden: Bool,
                                 appIsFinder: Bool) -> [DockPanelMenuItem] {
        guard hasAXElement else { return [.bringForward] }
        var items: [DockPanelMenuItem] = [.closeWindow, minimized ? .restoreWindow : .minimizeWindow,
                                     fullScreen ? .exitFullScreen : .enterFullScreen, .separator,
                                     appHidden ? .showApp : .hideApp]
        if !appIsFinder { items.append(.quitApp) }
        return items
    }

    /// The header's right-click menu (§4.4, Y-10): the header's actions plus Close All. Finder has no Quit.
    package static func headerMenu(appHidden: Bool, appIsFinder: Bool) -> [DockPanelMenuItem] {
        var items: [DockPanelMenuItem] = [.minimizeAll, .closeAll, .separator, appHidden ? .showApp : .hideApp]
        if !appIsFinder { items.append(.quitApp) }
        return items
    }

    /// A menu item's title (§4.4: Title Case, app-name items as templates).
    package static func menuTitle(_ item: DockPanelMenuItem, app: String) -> String {
        switch item {
        case .bringForward: return L("Bring Forward")
        case .closeWindow: return L("Close Window")
        case .minimizeWindow: return L("Minimize Window")
        case .restoreWindow: return L("Restore Window")
        case .enterFullScreen: return L("Enter Full Screen")
        case .exitFullScreen: return L("Exit Full Screen")
        case .hideApp: return headerLabel(.hideApp, app: app)
        case .showApp: return headerLabel(.showApp, app: app)
        case .quitApp: return headerLabel(.quitApp, app: app)
        case .minimizeAll: return L("Minimize All")
        case .closeAll: return L("Close All")
        case .separator: return ""
        }
    }

    /// A menu item's key equivalent, shown only while keys work (G2-1): ⌘W, ⌘M, ⌘H and ⌘Q.
    package static func menuKey(_ item: DockPanelMenuItem, keysWork: Bool) -> String {
        guard keysWork else { return "" }
        switch item {
        case .closeWindow: return "w"
        case .minimizeWindow, .restoreWindow: return "m"
        case .hideApp, .showApp: return "h"
        case .quitApp: return "q"
        case .bringForward, .enterFullScreen, .exitFullScreen, .minimizeAll, .closeAll, .separator: return ""
        }
    }

    /// What a menu item does; nil for the separator.
    package static func action(for item: DockPanelMenuItem) -> DockAction? {
        switch item {
        case .bringForward: return .raise
        case .closeWindow: return .close
        case .minimizeWindow: return .minimize
        case .restoreWindow: return .restore
        case .enterFullScreen, .exitFullScreen: return .fullScreen
        case .hideApp: return .hideApp
        case .showApp: return .showApp
        case .quitApp: return .quitApp
        case .minimizeAll: return .minimizeAll
        case .closeAll: return .closeAll
        case .separator: return nil
        }
    }

    /// What a handled key does (§4.5): nil for Esc, which only hides.
    package static func action(for key: DockKeyAction) -> DockAction? {
        switch key {
        case .close: return .close
        case .minimize: return .minimize
        case .restore: return .restore
        case .hideApp: return .hideApp
        case .showApp: return .showApp
        case .quitApp: return .quitApp
        case .escape: return nil
        }
    }

    /// Whether `action` needs the window's AX element (§4.4, D2-25): everything that acts on one window but Bring
    /// Forward.
    package static func needsAXElement(_ action: DockAction) -> Bool {
        switch action {
        case .close, .minimize, .restore, .fullScreen: return true
        case .raise, .activateApp, .minimizeAll, .closeAll, .hideApp, .showApp, .quitApp: return false
        }
    }
}

/// A card's hover buttons, top-left (§4.4).
package enum DockHoverButton: String, CaseIterable, Sendable {
    case close
    case minimize
    case fullScreen
}

/// The card's and the header's right-click menu items (§4.4).
package enum DockPanelMenuItem: String, CaseIterable, Sendable {
    case bringForward
    case closeWindow
    case minimizeWindow
    case restoreWindow
    case enterFullScreen
    case exitFullScreen
    case separator
    case hideApp
    case showApp
    case quitApp
    case minimizeAll
    case closeAll
}
