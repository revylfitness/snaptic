import Foundation

// The window catalog's rules (lead; PLAN 0.5 §2.1, §2.6, §4.3, §4.8–§4.10, §4.23): which windows are listed, which
// are private, how they sort, which badge a card shows, which capture path a window takes and when a thumbnail is
// fresh. The Window Switcher and Dock Previews both read windows through these rules; the switcher's inclusion and
// filter cases moved here from `Switcher/WindowManager.swift` and `Switcher/SwitcherController.swift` (K4).
// Values only: the app reads AX and `CGWindowList`, Kit decides.

/// What an AX subrole says a window is. `CGWindowList` gives no subrole, so a window read only from there is
/// `.unknown` and its layer stands in (§4.8).
package enum CatalogWindowKind: String, Equatable, Sendable {
    case standard
    case dialog
    case systemDialog
    /// Floating panels and system floating windows.
    case floating
    /// Any other subrole (notification-style pop-ups and the like).
    case other
    /// No subrole was read.
    case unknown

    package init(subrole: String?) {
        switch subrole {
        case nil: self = .unknown
        case "AXStandardWindow": self = .standard
        case "AXDialog": self = .dialog
        case "AXSystemDialog": self = .systemDialog
        case "AXFloatingWindow", "AXSystemFloatingWindow": self = .floating
        default: self = .other
        }
    }
}

/// One window as both modules see it (§2.1). Window ids at or above `firstSyntheticID` are made up for a window
/// without a trusted id, and for an app's "no windows" entry.
package struct CatalogWindow: Equatable, Sendable {
    package static let firstSyntheticID: UInt32 = 0xF000_0000

    package var id: UInt32
    package var pid: Int32
    package var hasTitle: Bool
    package var minimized: Bool
    package var hidden: Bool
    package var onScreen: Bool
    /// `SLSCopySpacesForWindows`: true when the window is on some Space, false when it's on none (inactive native tabs,
    /// helper windows), nil when it wasn't asked or can't be (the symbols are missing or `Windows.disable.spaces` is
    /// set; P-19).
    package var spaceKnown: Bool?
    package var fullscreen: Bool
    package var layer: Int
    /// Cocoa coordinates.
    package var bounds: DockRect
    package var isPrivate: Bool
    package var hasAXElement: Bool
    // K4 adds these (§R4): the subrole, the window server's alpha, the "no windows" entry, and Stage Manager's strip.
    package var kind: CatalogWindowKind
    /// `kCGWindowAlpha`; 1 when unknown.
    package var alpha: Double
    /// An app's "no windows" entry, not a window.
    package var windowless: Bool
    /// A window shown in Stage Manager's side strip (Y-8, S0-11): off screen but on this Space.
    package var inStageStrip: Bool
    /// On another Space (§2.6). Set from the read when the value is made, and kept as read: restoring a minimized
    /// window in place doesn't make it an other-Space window.
    package var onOtherSpace: Bool

    package init(id: UInt32, pid: Int32, hasTitle: Bool = true, minimized: Bool = false, hidden: Bool = false,
                 onScreen: Bool = true, spaceKnown: Bool? = nil, fullscreen: Bool = false, layer: Int = 0,
                 bounds: DockRect = DockRect(x: 0, y: 0, width: 800, height: 600), isPrivate: Bool = false,
                 hasAXElement: Bool = true, kind: CatalogWindowKind = .standard, alpha: Double = 1,
                 windowless: Bool = false, inStageStrip: Bool = false) {
        self.id = id
        self.pid = pid
        self.hasTitle = hasTitle
        self.minimized = minimized
        self.hidden = hidden
        self.onScreen = onScreen
        self.spaceKnown = spaceKnown
        self.fullscreen = fullscreen
        self.layer = layer
        self.bounds = bounds
        self.isPrivate = isPrivate
        self.hasAXElement = hasAXElement
        self.kind = kind
        self.alpha = alpha
        self.windowless = windowless
        self.inStageStrip = inStageStrip
        onOtherSpace = false
        onOtherSpace = WindowCatalogRules.isOnOtherSpace(self)
    }

    /// An app's "no windows" entry.
    package static func windowless(id: UInt32, pid: Int32, hidden: Bool) -> CatalogWindow {
        CatalogWindow(id: id, pid: pid, hasTitle: false, hidden: hidden, onScreen: false, bounds: .zero,
                      hasAXElement: false, kind: .unknown, windowless: true)
    }

    /// A real window-server id, not a made-up one.
    package var hasRealID: Bool { id < Self.firstSyntheticID }
}

/// Per-client inclusion thresholds. The switcher keeps its 0.4 list (§4.23, §2.6); Dock Previews follows §4.8.
package struct CatalogInclusion: Equatable, Sendable {
    /// The smallest width and height of an AX window, in points.
    package var minAXSide: Double
    /// The smallest width and height of a window read only from `CGWindowList`.
    package var minListSide: Double
    /// Untitled dialogs are listed.
    package var untitledDialogs: Bool
    /// Untitled windows read only from `CGWindowList` are listed (`allowUntitled`, §2.6).
    package var allowUntitled: Bool

    package init(minAXSide: Double, minListSide: Double, untitledDialogs: Bool, allowUntitled: Bool) {
        self.minAXSide = minAXSide
        self.minListSide = minListSide
        self.untitledDialogs = untitledDialogs
        self.allowUntitled = allowUntitled
    }

    package static let switcher = CatalogInclusion(minAXSide: 40, minListSide: 100, untitledDialogs: true,
                                                   allowUntitled: false)
    package static let dock = CatalogInclusion(minAXSide: 100, minListSide: 100, untitledDialogs: false,
                                               allowUntitled: true)
}

/// Why a window isn't listed.
package enum CatalogLeftOut: String, Equatable, Sendable {
    /// The pid isn't a running, listed app.
    case appGone
    /// Neither an AX element nor a real window id: nothing could act on it.
    case idGone
    /// Below the normal window layer (Finder's desktop window).
    case desktop
    /// Read only from `CGWindowList` and not on layer 0.
    case notNormalLayer
    /// Not a standard window or dialog: floating panels, system dialogs, pop-ups.
    case kind
    case untitledDialog
    case tooSmall
    /// On no Space: an inactive native tab or a helper window.
    case nativeTab
    /// Read only from `CGWindowList` while on screen: whatever it is, it isn't one of the app's windows.
    case onScreen
    /// Alpha 0.
    case transparent
    /// Read only from `CGWindowList`, and the Spaces check can't run (P-19).
    case spacesUnknown
    /// Read only from `CGWindowList` without a title, for a client that doesn't list those.
    case untitled
}

package struct CatalogVerdict: Equatable, Sendable {
    package var leftOut: CatalogLeftOut?
    /// The window still proves its app has a window, so the app gets no "no windows" entry.
    package var appHasWindow: Bool

    package init(leftOut: CatalogLeftOut?, appHasWindow: Bool) {
        self.leftOut = leftOut
        self.appHasWindow = appHasWindow
    }

    package var included: Bool { leftOut == nil }
}

/// The switcher shortcut's Spaces choice; Dock Previews uses `.all`.
package enum CatalogSpaces: Equatable, Sendable {
    case all, current, others
}

/// The switcher shortcut's scope; Dock Previews uses `.app` with the hovered app.
package enum CatalogScope: Equatable, Sendable {
    case allWindows
    /// One app's windows; nil keeps nothing.
    case app(Int32?)
    /// Windows whose centre is on this screen frame (Cocoa), and "no windows" entries; nil keeps everything.
    case screen(DockRect?)
}

/// The settings that narrow a listed catalog.
package struct CatalogFilter: Equatable, Sendable {
    /// "Windows on other Spaces".
    package var otherSpaces: Bool
    package var spaces: CatalogSpaces
    /// "Include minimized and hidden windows".
    package var minimizedAndHidden: Bool
    /// "Apps with no open windows".
    package var windowless: Bool
    package var scope: CatalogScope

    package init(otherSpaces: Bool, spaces: CatalogSpaces = .all, minimizedAndHidden: Bool, windowless: Bool,
                 scope: CatalogScope = .allWindows) {
        self.otherSpaces = otherSpaces
        self.spaces = spaces
        self.minimizedAndHidden = minimizedAndHidden
        self.windowless = windowless
        self.scope = scope
    }

    /// Dock Previews' filter for the hovered app.
    package static func dock(_ config: DockConfig, pid: Int32) -> CatalogFilter {
        CatalogFilter(otherSpaces: config.otherSpaces, minimizedAndHidden: config.includeMinimizedAndHidden,
                      windowless: config.windowlessApps, scope: .app(pid))
    }
}

/// The shared privacy rule's answer (§4.10).
package enum CatalogPrivacy: Equatable, Sendable {
    case none
    /// On the protected list: the card shows the app name.
    case protectedApp
    /// The title marks a private-browsing window: the card shows "Private window".
    case privateMarker
    /// A browser window whose title can't be read.
    case untitledBrowser

    package var isPrivate: Bool { self != .none }
}

/// One card badge at most (§4.3); the switcher keeps its own order and words (§4.23).
package enum CatalogBadge: Equatable, Sendable {
    case noWindows
    case windows(Int)
    case minimized
    case hidden
    case otherSpace
    case fullScreen
    /// The window's display name (`NSScreen.localizedName`).
    case display(String)
}

/// What a Dock card's text shows (§4.3, §4.10).
package enum CatalogCardText: Equatable, Sendable {
    case title
    case appName
    case privateWindow
    case windowOnAnotherSpace
}

/// What a card offers (§4.4).
package enum CatalogAction: Equatable, Sendable {
    /// Bring Forward.
    case raise
    case close
    case minimize
    case fullScreen
}

/// Why a capture is refused (§4.9).
package enum CaptureRefusal: Equatable, Sendable {
    case noScreenRecording
    /// The module's Window thumbnails is off, or its lease lacks `.thumbnails`.
    case noThumbnailsLease
    case privateWindow
    /// The window server's owner isn't the app being previewed (S0-18).
    case ownerMismatch
    case protectedApp
    /// A Dock Previews capture of an app on "Apps hidden from Dock previews" (G3-3).
    case hiddenFromDock
    case noWindowID
    case windowless
}

/// Where a card's picture comes from (§4.9).
package enum CapturePath: Equatable, Sendable {
    case screenCaptureKit
    /// `CGSHWCaptureWindowList`, for minimized and other-Space windows only.
    case privateCapture
    case lastSeen
    case icon
}

/// What a capture decision needs besides the window. The app fills it once per batch.
package struct CaptureGate: Equatable, Sendable {
    package var client: ModuleID
    /// `CGPreflightScreenCaptureAccess()`.
    package var screenRecording: Bool
    /// The module's Window thumbnails is on and its lease holds `.thumbnails`.
    package var thumbnailsLease: Bool
    /// The window server's owner pid is the app being previewed (S0-18).
    package var ownerMatches: Bool
    /// "Protect private windows" is on and the app is on its list.
    package var protectedApp: Bool
    /// The app is on "Apps hidden from Dock previews"; only a Dock Previews capture is refused for it.
    package var hiddenFromDock: Bool
    /// The private path is usable (§4.12).
    package var privatePath: Bool
    /// The store holds a last-seen thumbnail for this window.
    package var hasLastSeen: Bool

    package init(client: ModuleID, screenRecording: Bool, thumbnailsLease: Bool, ownerMatches: Bool,
                 protectedApp: Bool, hiddenFromDock: Bool, privatePath: Bool, hasLastSeen: Bool) {
        self.client = client
        self.screenRecording = screenRecording
        self.thumbnailsLease = thumbnailsLease
        self.ownerMatches = ownerMatches
        self.protectedApp = protectedApp
        self.hiddenFromDock = hiddenFromDock
        self.privatePath = privatePath
        self.hasLastSeen = hasLastSeen
    }

    /// The switcher's list-time gate: which items are captured, or keep a last-seen thumbnail. `WindowCapture` checks
    /// consent once per batch and the owner and the protected list on each capture; last-seen is the store's lookup,
    /// and the private path is A2b's.
    package static let switcherList = CaptureGate(client: .windowSwitcher, screenRecording: true, thumbnailsLease: true,
                                                  ownerMatches: true, protectedApp: false, hiddenFromDock: false,
                                                  privatePath: false, hasLastSeen: false)
}

package enum WindowCatalogRules {
    /// A thumbnail is fresh for this long (§4.9).
    package static let freshSeconds: Double = 30

    // MARK: Apps and ids

    /// The switcher lists regular apps other than Snaptic, minus its excluded apps.
    package static func listsApp(regular: Bool, isOwnProcess: Bool, bundleID: String?, excluded: [String]) -> Bool {
        regular && !isOwnProcess && !PIPPrivacy.matches(bundleID, prefixes: excluded)
    }

    /// An app reports its own window ids, so one is trusted only when the window server agrees the app owns it;
    /// otherwise an app could claim another app's window and get it captured.
    package static func trustedWindowID(claimed: UInt32?, pid: Int32, owners: [UInt32: Int32]) -> UInt32? {
        guard let claimed, owners[claimed] == pid else { return nil }
        return claimed
    }

    /// Dock items of apps on "Apps hidden from Dock previews" never show a panel (G2-4, D2-24). Exact bundle ids.
    package static func yieldsPanel(bundleID: String?, hiddenBundleIDs: [String]) -> Bool {
        !isHiddenFromDock(bundleID: bundleID, hiddenBundleIDs: hiddenBundleIDs)
    }

    package static func isHiddenFromDock(bundleID: String?, hiddenBundleIDs: [String]) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return hiddenBundleIDs.contains(bundleID)
    }

    // MARK: Inclusion (§4.8)

    /// The other-Space rule (§2.6): not minimized, not hidden and not on screen. A window read only from
    /// `CGWindowList` is always elsewhere, even for a hidden app (it's listed as Hidden). A Stage Manager strip
    /// window is on this Space.
    package static func isOnOtherSpace(_ w: CatalogWindow) -> Bool {
        guard !w.windowless, !w.inStageStrip, !w.onScreen else { return false }
        return !w.hasAXElement || (!w.minimized && !w.hidden)
    }

    /// The subrole check for AX windows: standard windows, and dialogs (titled ones only unless the options allow
    /// untitled ones). With `hasTitle` nil (not read yet), a dialog passes for now.
    package static func kindLeftOut(_ kind: CatalogWindowKind, hasTitle: Bool?,
                                    options: CatalogInclusion) -> CatalogLeftOut? {
        switch kind {
        case .standard: return nil
        case .dialog: return hasTitle == false && !options.untitledDialogs ? .untitledDialog : nil
        case .systemDialog, .floating, .other, .unknown: return .kind
        }
    }

    /// Anything narrower or shorter than `minimum` is left out.
    package static func sizeLeftOut(width: Double, height: Double, minimum: Double) -> CatalogLeftOut? {
        width >= minimum && height >= minimum ? nil : .tooSmall
    }

    /// Whether a window is listed (§4.8, Y-3). `appListed`: its pid is a running app the client lists. Duplicate ids
    /// are the reader's to drop.
    package static func inclusion(_ w: CatalogWindow, appListed: Bool, options: CatalogInclusion) -> CatalogVerdict {
        func out(_ reason: CatalogLeftOut, counts: Bool = false) -> CatalogVerdict {
            CatalogVerdict(leftOut: reason, appHasWindow: counts)
        }
        guard appListed else { return out(.appGone) }
        if w.windowless { return CatalogVerdict(leftOut: nil, appHasWindow: false) }
        guard w.hasAXElement || w.hasRealID else { return out(.idGone) }
        if w.layer < 0 { return out(.desktop) }

        if w.hasAXElement {
            if let reason = kindLeftOut(w.kind, hasTitle: w.hasTitle, options: options) { return out(reason) }
            if let reason = sizeLeftOut(width: w.bounds.width, height: w.bounds.height, minimum: options.minAXSide) {
                return out(reason)
            }
            // Native tabs that aren't the front tab are separate, off-screen windows on no Space: not windows to
            // switch to, though they still prove the app has a window.
            if !w.onScreen, !w.minimized, !w.hidden, !w.inStageStrip, w.spaceKnown == false {
                return out(.nativeTab, counts: true)
            }
            return CatalogVerdict(leftOut: nil, appHasWindow: true)
        }

        // Read only from `CGWindowList`: windows on other Spaces, which AX doesn't report.
        if w.layer != 0 { return out(.notNormalLayer) }
        if w.onScreen { return out(.onScreen) }
        if let reason = sizeLeftOut(width: w.bounds.width, height: w.bounds.height, minimum: options.minListSide) {
            return out(reason)
        }
        if !(w.alpha > 0) { return out(.transparent) }
        switch w.spaceKnown {
        case false?: return out(.nativeTab)
        case nil: return out(.spacesUnknown, counts: true)
        case true?: break
        }
        if !w.hasTitle, !options.allowUntitled { return out(.untitled, counts: true) }
        return CatalogVerdict(leftOut: nil, appHasWindow: true)
    }

    /// Whether the verdict turns on `spaceKnown`, so the reader asks `SLSCopySpacesForWindows` for this window only,
    /// and only once every cheaper check has passed.
    package static func needsSpaceCheck(_ w: CatalogWindow, appListed: Bool, options: CatalogInclusion) -> Bool {
        var onNone = w, onSome = w
        onNone.spaceKnown = false
        onSome.spaceKnown = true
        return inclusion(onNone, appListed: appListed, options: options)
            != inclusion(onSome, appListed: appListed, options: options)
    }

    // MARK: Filters

    /// The indices of the windows the settings keep, in order.
    package static func filter(_ windows: [CatalogWindow], _ filter: CatalogFilter) -> [Int] {
        windows.indices.filter { keeps(windows[$0], filter) }
    }

    package static func keeps(_ w: CatalogWindow, _ filter: CatalogFilter) -> Bool {
        if w.windowless, !filter.windowless { return false }
        if !filter.otherSpaces, w.onOtherSpace { return false }
        switch filter.scope {
        case .allWindows:
            break
        case .app(let pid):
            guard let pid, w.pid == pid else { return false }
        case .screen(let frame):
            if let frame, !w.windowless, !frame.contains(x: w.bounds.midX, y: w.bounds.midY) { return false }
        }
        switch filter.spaces {
        case .all: break
        case .current: if w.onOtherSpace { return false }
        case .others: if !w.onOtherSpace, !w.windowless { return false }
        }
        if !filter.minimizedAndHidden, w.minimized || w.hidden { return false }
        return true
    }

    /// "One window per app": each app's first window, with the number of windows it stands for ("no windows"
    /// entries don't count).
    package static func groupedByApp(_ windows: [CatalogWindow]) -> [(index: Int, count: Int)] {
        var counts: [Int32: Int] = [:]
        for w in windows where !w.windowless { counts[w.pid, default: 0] += 1 }
        var seen = Set<Int32>()
        var result: [(index: Int, count: Int)] = []
        for (index, w) in windows.enumerated() where !seen.contains(w.pid) {
            seen.insert(w.pid)
            result.append((index, counts[w.pid] ?? 1))
        }
        return result
    }

    // MARK: Privacy (§4.10)

    /// "Protect private windows" is on and the app is on its list.
    package static func isProtected(bundleID: String?, protect: Bool, protectedApps: [String]) -> Bool {
        protect && PIPPrivacy.matches(bundleID, prefixes: protectedApps)
    }

    /// The one privacy rule both modules apply, from `PIPPrivacy`: the protected apps, the private-window markers
    /// (read from the full title) and the browser with an empty title. "No windows" entries are never private.
    package static func privacy(bundleID: String?, hasTitle: Bool, hasPrivateMarker: Bool, windowless: Bool,
                                protect: Bool, protectedApps: [String]) -> CatalogPrivacy {
        guard protect, !windowless else { return .none }
        if isProtected(bundleID: bundleID, protect: protect, protectedApps: protectedApps) { return .protectedApp }
        if hasPrivateMarker { return .privateMarker }
        if !hasTitle, PIPPrivacy.isBrowser(bundleID) { return .untitledBrowser }
        return .none
    }

    // MARK: Order

    /// The switcher's order: the window you're in, then most recently used, then windows never focused while
    /// Snaptic ran in stacking order, then the rest; "no windows" entries last. Ties go by app name, then title.
    package static func switcherOrder(_ windows: [CatalogWindow], names: [(app: String, title: String)],
                                      focusedID: UInt32?, mru: [UInt32], zOrder: [UInt32: Int]) -> [Int] {
        var mruIndex: [UInt32: Int] = [:]
        for (index, id) in mru.enumerated() where mruIndex[id] == nil { mruIndex[id] = index }
        func rank(_ w: CatalogWindow) -> (Int, Int) {
            if w.windowless { return (4, 0) }
            if let focusedID, w.id == focusedID { return (0, 0) }
            if let r = mruIndex[w.id] { return (1, r) }
            if let z = zOrder[w.id] { return (2, z) }
            return (3, 0)
        }
        return windows.indices.sorted { a, b in
            let ra = rank(windows[a]), rb = rank(windows[b])
            if ra != rb { return ra < rb }
            let na = names[a], nb = names[b]
            if (na.app, na.title) != (nb.app, nb.title) { return (na.app, na.title) < (nb.app, nb.title) }
            return a < b
        }
    }

    /// The recency merge (§2.3, §4.8): `FocusTracker`'s order while a `.recency` lease is live (`recency` non-nil),
    /// then the app's `CGWindowList` front-to-back order, then minimized windows in AX order, then the rest in AX
    /// order. `windows` is in AX order.
    package static func recencyOrder(_ windows: [CatalogWindow], recency: [UInt32]?, zOrder: [UInt32: Int]) -> [Int] {
        var recent: [UInt32: Int] = [:]
        for (index, id) in (recency ?? []).enumerated() where recent[id] == nil { recent[id] = index }
        func rank(_ index: Int) -> (Int, Int) {
            let w = windows[index]
            if w.windowless { return (4, index) }
            if let r = recent[w.id] { return (0, r) }
            if let z = zOrder[w.id] { return (1, z) }
            if w.minimized { return (2, index) }
            return (3, index)
        }
        return windows.indices.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            return ra != rb ? ra < rb : a < b
        }
    }

    /// "Minimized and Hidden Last" (§4.23): `order` with every minimized or hidden window moved after the others,
    /// each group keeping its order.
    package static func minimizedAndHiddenLast(_ windows: [CatalogWindow], order: [Int]) -> [Int] {
        let last = order.filter { windows[$0].minimized || windows[$0].hidden }
        return order.filter { !(windows[$0].minimized || windows[$0].hidden) } + last
    }

    /// Dock Previews' "Sort windows by" (§4.18). `titles` are the cards' titles, by index. The Title sort ignores
    /// case and diacritics, and ties keep the recency order.
    package static func dockOrder(_ windows: [CatalogWindow], titles: [String], sort: DockSort, recency: [UInt32]?,
                                  zOrder: [UInt32: Int]) -> [Int] {
        let recent = recencyOrder(windows, recency: recency, zOrder: zOrder)
        switch sort {
        case .recentlyUsed:
            return recent
        case .minimizedAndHiddenLast:
            return minimizedAndHiddenLast(windows, order: recent)
        case .title:
            var position: [Int: Int] = [:]
            for (p, index) in recent.enumerated() { position[index] = p }
            let keys = titles.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
            return recent.sorted { a, b in
                keys[a] != keys[b] ? keys[a] < keys[b] : position[a, default: 0] < position[b, default: 0]
            }
        }
    }

    // MARK: Cards (§4.3, §4.4)

    /// The switcher's badge, in its 0.4 order and words (§4.23).
    package static func switcherBadge(_ w: CatalogWindow, groupedCount: Int) -> CatalogBadge? {
        if w.windowless { return .noWindows }
        if groupedCount > 1 { return .windows(groupedCount) }
        if w.minimized { return .minimized }
        if w.hidden { return .hidden }
        if w.onOtherSpace { return .otherSpace }
        if w.fullscreen { return .fullScreen }
        return nil
    }

    /// A Dock card's badge: Minimized > Full screen > On another Space > the display name, which shows only with
    /// more than one display. A hidden app shows Hidden once, in the header, never on a card (G-17).
    package static func dockBadge(_ w: CatalogWindow, displayName: String?, displayCount: Int) -> CatalogBadge? {
        if w.windowless { return nil }
        if w.minimized { return .minimized }
        if w.fullscreen { return .fullScreen }
        if w.onOtherSpace { return .otherSpace }
        if displayCount > 1, let displayName, !displayName.isEmpty { return .display(displayName) }
        return nil
    }

    /// A Dock card's text: the title, or the app name when it's empty; "Window on another Space" for an untitled
    /// card without an AX element; "Private window", or the app name for a protected app.
    package static func dockCardText(_ w: CatalogWindow, privacy: CatalogPrivacy) -> CatalogCardText {
        switch privacy {
        case .protectedApp: return .appName
        case .privateMarker, .untitledBrowser: return .privateWindow
        case .none: break
        }
        if w.hasTitle { return .title }
        return !w.hasAXElement && w.onOtherSpace ? .windowOnAnotherSpace : .appName
    }

    /// A card without an AX element offers only Bring Forward (§4.4, D2-25).
    package static func cardActions(_ w: CatalogWindow) -> [CatalogAction] {
        w.hasAXElement && !w.windowless ? [.raise, .close, .minimize, .fullScreen] : [.raise]
    }

    // MARK: Capture (§4.9)

    /// The first rule a capture breaks, or nil when it may run.
    package static func captureRefusal(_ w: CatalogWindow, gate: CaptureGate) -> CaptureRefusal? {
        if w.windowless { return .windowless }
        if !w.hasRealID { return .noWindowID }
        if !gate.thumbnailsLease { return .noThumbnailsLease }
        if w.isPrivate { return .privateWindow }
        if gate.protectedApp { return .protectedApp }
        if gate.client == .dockPreviews, gate.hiddenFromDock { return .hiddenFromDock }
        if !gate.ownerMatches { return .ownerMismatch }
        if !gate.screenRecording { return .noScreenRecording }
        return nil
    }

    /// The card's picture: SCK for on-screen windows; the private path only for minimized and other-Space windows;
    /// else last-seen; else the icon. A Stage Manager strip window gets its own capture (SCK while it's on screen,
    /// else the private path), else last-seen, else the icon; never the strip tile (Y-8, S0-11). A refused window
    /// shows the icon, except that a missing Screen Recording grant still shows last-seen.
    package static func capturePath(_ w: CatalogWindow, gate: CaptureGate) -> CapturePath {
        let fallback: CapturePath = gate.hasLastSeen ? .lastSeen : .icon
        if let refusal = captureRefusal(w, gate: gate) { return refusal == .noScreenRecording ? fallback : .icon }
        if w.minimized || w.onOtherSpace || (w.inStageStrip && !w.onScreen) {
            return gate.privatePath ? .privateCapture : fallback
        }
        if w.hidden { return fallback }
        return .screenCaptureKit
    }

    /// A thumbnail is fresh for 30 s after its capture (§4.9). A capture time after `now` isn't fresh.
    package static func isFresh(capturedAt: Double, now: Double) -> Bool {
        let age = now - capturedAt
        return age >= 0 && age < freshSeconds
    }
}
