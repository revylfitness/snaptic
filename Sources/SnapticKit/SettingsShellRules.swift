import Foundation

// Pure rules of the Settings shell (H; PLAN 0.3 §4.2, R5-8): sidebar root ids, where an `openSettings(page:)`
// string leads, the remembered location, and the focus guard for session starts.

/// The seven sidebar roots. Module roots use the module id (`SnapticModule.settingsRoot().id`).
package enum SettingsRootID {
    package static let general = "general"
    package static let menuBar = "menuBar"
    package static let windowSwitcher = ModuleID.windowSwitcher.rawValue
    package static let displays = ModuleID.displays.rawValue
    package static let awake = ModuleID.awake.rawValue
    package static let permissions = "permissions"
    package static let about = "about"

    /// Sidebar order; groups are separated by spacing.
    package static let groups: [[String]] = [[general, menuBar], [windowSwitcher, displays, awake], [permissions, about]]
    package static var all: [String] { groups.flatMap { $0 } }

    /// First words of page ids that name a root ("switcher.features" is Window Switcher).
    package static let aliases: [String: String] = [
        "switcher": windowSwitcher, "menubar": menuBar, "menu": menuBar, "about": about,
    ]

    /// 0.2 page ids whose 0.3 home is a root of its own.
    package static let legacyPages: [String: String] = [
        "general.modules": general,
        "general.menu": menuBar,
        "general.permissions": permissions,
        "general.about": about,
    ]
}

/// A sidebar root and, optionally, the sub-page shown on top of it.
package struct SettingsLocation: Equatable, Sendable {
    package var root: String
    package var route: SettingsRoute?

    package init(root: String, route: SettingsRoute? = nil) {
        self.root = root
        self.route = route
    }

    /// Ids are short and printable: letters, digits, ".", "-", "_"; at most 64 bytes.
    package static func isValidID(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= 64 else { return false }
        return id.utf8.allSatisfy { b in
            (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x2E || b == 0x2D
                || b == 0x5F
        }
    }

    /// "root" or "root route" (the remembered location; `@AppStorage("settingsLastRoute")`).
    package var encoded: String { route.map { root + " " + $0.id } ?? root }

    /// Reads `encoded`; nil when the text is malformed or names a root that doesn't exist.
    package init?(encoded: String, roots: Set<String>) {
        let parts = encoded.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 1 || parts.count == 2, roots.contains(parts[0]), Self.isValidID(parts[0]) else { return nil }
        if parts.count == 2 {
            guard Self.isValidID(parts[1]) else { return nil }
            self.init(root: parts[0], route: SettingsRoute(parts[1]))
        } else {
            self.init(root: parts[0])
        }
    }

    /// Where `openSettings(page:)` leads: a root id → that root; a 0.2 page id with a root of its own → that root;
    /// "<root or alias>.<rest>" → that root with the whole id as its route ("displays.color", "awake.history").
    /// nil for anything else (the window opens where it was).
    package static func resolve(_ page: String, roots: Set<String>) -> SettingsLocation? {
        guard isValidID(page) else { return nil }
        if roots.contains(page) { return SettingsLocation(root: page) }
        if let root = SettingsRootID.legacyPages[page] { return roots.contains(root) ? SettingsLocation(root: root) : nil }
        guard let dot = page.firstIndex(of: "."), dot != page.startIndex else { return nil }
        let head = String(page[..<dot])
        let root = roots.contains(head) ? head : SettingsRootID.aliases[head.lowercased()]
        guard let root, roots.contains(root), page.index(after: dot) != page.endIndex else { return nil }
        return SettingsLocation(root: root, route: SettingsRoute(page))
    }
}

/// R5-8 focus safety for session starts from Settings. Times are monotonic seconds (system uptime).
package struct SettingsFocusGuard: Equatable, Sendable {
    /// Start handlers ignore events this long after an externally requested open.
    package static let guardSeconds = 1.0

    package private(set) var externalOpenAt: Double?
    /// Set by an external open (reopen, `open-settings`); cleared by the first mouse-down in the window or an
    /// open from Snaptic's own menu or hotkey.
    package private(set) var externalOpenPending = false

    package init() {}

    package mutating func externalOpen(now: Double) {
        externalOpenAt = now
        externalOpenPending = true
    }

    /// An open from Snaptic's own menu or hotkey: the person asked for it here.
    package mutating func internalOpen() {
        externalOpenAt = nil
        externalOpenPending = false
    }

    /// The first real mouse-down inside the window.
    package mutating func mouseDown() {
        externalOpenPending = false
    }

    /// False while the guard runs (also when the clock reads earlier than the open, fail-safe), and for a key press
    /// while an external open is pending. VoiceOver and AX presses carry no key event, so they act.
    package func mayStart(now: Double, eventIsKeyDown: Bool) -> Bool {
        if let t = externalOpenAt, now < t + Self.guardSeconds { return false }
        if externalOpenPending && eventIsKeyDown { return false }
        return true
    }
}
