import AppKit
import Combine
import CoreGraphics
import SnapticKit

enum KeyCode {
    static let tab = 48
    /// The key above Tab on ANSI/JIS keyboards (`).
    static let backtick = 50
    /// The key above Tab on ISO (European) keyboards (§ / ^ / <).
    static let isoSection = 10
    static let space = 49
    static let escape = 53
    static let returnKey = 36
    static let enter = 76
    static let delete = 51
    static let forwardDelete = 117
    static let left = 123
    static let right = 124
    static let down = 125
    static let up = 126

    /// Physical keys used for the switcher's action keys, so they work on any
    /// keyboard layout (Russian, Greek, Dvorak…).
    static let keyS = 1
    static let keyW = 13
    static let keyM = 46
    static let keyF = 3
    static let keyQ = 12
    static let keyH = 4
    static let slash = 44

    /// "Key above Tab" has a different key code on ISO (European) keyboards;
    /// on those, code 50 is the extra key next to left Shift instead.
    static func matches(_ pressed: Int, shortcutKey: Int) -> Bool {
        guard shortcutKey == backtick else { return pressed == shortcutKey }
        return pressed == (PrivateAPIs.isISOKeyboard ? isoSection : backtick)
    }
}

enum ModifierKey: String, Codable, CaseIterable, Identifiable {
    case option, command, control

    var id: String { rawValue }

    var label: String {
        switch self {
        case .option: return "⌥ Option"
        case .command: return "⌘ Command"
        case .control: return "⌃ Control"
        }
    }

    var symbol: String {
        switch self {
        case .option: return "⌥"
        case .command: return "⌘"
        case .control: return "⌃"
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .option: return .maskAlternate
        case .command: return .maskCommand
        case .control: return .maskControl
        }
    }
}

enum SwitcherScope: String, Codable, CaseIterable, Identifiable {
    case allWindows, activeApp, currentScreen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allWindows: return "All windows"
        case .activeApp: return "Active app only"
        case .currentScreen: return "This screen only"
        }
    }
}

enum SwitcherStyle: String, Codable, CaseIterable, Identifiable {
    case thumbnails, icons, titles

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thumbnails: return "Thumbnails"
        case .icons: return "App icons"
        case .titles: return "Titles list"
        }
    }
}

enum SpacesFilter: String, Codable, CaseIterable, Identifiable {
    case all, current, others

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All Spaces"
        case .current: return "Current Space only"
        case .others: return "Other Spaces only"
        }
    }
}

enum ScreenChoice: String, Codable, CaseIterable, Identifiable {
    case activeWindow, mouse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .activeWindow: return "Screen with the active window"
        case .mouse: return "Screen with the mouse pointer"
        }
    }
}

struct KeyChoice: Identifiable, Hashable {
    let code: Int
    let label: String
    var id: Int { code }
}

enum Keys {
    static let choices: [KeyChoice] = {
        var list = [
            KeyChoice(code: KeyCode.tab, label: "Tab"),
            KeyChoice(code: KeyCode.backtick, label: "Key above Tab"),
            KeyChoice(code: KeyCode.space, label: "Space"),
        ]
        let letters: [(String, Int)] = [
            ("A", 0), ("B", 11), ("C", 8), ("D", 2), ("E", 14), ("F", 3), ("G", 5), ("H", 4),
            ("I", 34), ("J", 38), ("K", 40), ("L", 37), ("M", 46), ("N", 45), ("O", 31), ("P", 35),
            ("Q", 12), ("R", 15), ("S", 1), ("T", 17), ("U", 32), ("V", 9), ("W", 13), ("X", 7),
            ("Y", 16), ("Z", 6),
        ]
        let digits: [(String, Int)] = [
            ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("5", 23),
            ("6", 22), ("7", 26), ("8", 28), ("9", 25), ("0", 29),
        ]
        list += letters.map { KeyChoice(code: $0.1, label: $0.0) }
        list += digits.map { KeyChoice(code: $0.1, label: $0.0) }
        return list
    }()

    /// Keys allowed with ⌘. Letters and digits are excluded so a shortcut can
    /// never hijack ⌘C, ⌘V, ⌘Q and friends system-wide.
    static let commandSafeCodes: Set<Int> = [KeyCode.tab, KeyCode.backtick, KeyCode.space]

    static func allowedChoices(for modifier: ModifierKey) -> [KeyChoice] {
        modifier == .command ? choices.filter { commandSafeCodes.contains($0.code) } : choices
    }

    static func isAllowed(_ shortcut: Shortcut) -> Bool {
        guard choices.contains(where: { $0.code == shortcut.keyCode }) else { return false }
        return shortcut.modifier != .command || commandSafeCodes.contains(shortcut.keyCode)
    }

    static func label(for code: Int) -> String {
        choices.first { $0.code == code }?.label ?? "Key \(code)"
    }

    static func shortLabel(for code: Int) -> String {
        switch code {
        case KeyCode.tab: return "⇥"
        case KeyCode.backtick: return PrivateAPIs.isISOKeyboard ? "§" : "`"
        case KeyCode.space: return "Space"
        default: return label(for: code)
        }
    }
}

struct Shortcut: Codable, Identifiable, Equatable {
    var id = UUID()
    var modifier: ModifierKey = .option
    var keyCode: Int = KeyCode.tab
    var scope: SwitcherScope = .allWindows
    var style: SwitcherStyle = .thumbnails
    var includeMinimized = true
    var includeWindowlessApps = false
    var spaces: SpacesFilter = .all
    /// Show each app once (its most recent window), like ⌘⇥.
    var oneWindowPerApp = false

    var displayName: String { "\(modifier.symbol)\(Keys.shortLabel(for: keyCode))" }

    func sameKeys(as other: Shortcut) -> Bool {
        modifier == other.modifier && keyCode == other.keyCode
    }
}

extension Shortcut {
    // Field-by-field decoding: a missing or unknown field falls back to its
    // default instead of throwing away every saved shortcut.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        if let v = try? c.decode(UUID.self, forKey: .id) { id = v }
        if let v = try? c.decode(ModifierKey.self, forKey: .modifier) { modifier = v }
        if let v = try? c.decode(Int.self, forKey: .keyCode) { keyCode = v }
        if let v = try? c.decode(SwitcherScope.self, forKey: .scope) { scope = v }
        if let v = try? c.decode(SwitcherStyle.self, forKey: .style) { style = v }
        if let v = try? c.decode(Bool.self, forKey: .includeMinimized) { includeMinimized = v }
        if let v = try? c.decode(Bool.self, forKey: .includeWindowlessApps) { includeWindowlessApps = v }
        if let v = try? c.decode(SpacesFilter.self, forKey: .spaces) { spaces = v }
        if let v = try? c.decode(Bool.self, forKey: .oneWindowPerApp) { oneWindowPerApp = v }
    }
}

/// Decodes an array, skipping elements that fail instead of failing the whole array.
private struct LossyShortcutList: Decodable {
    var items: [Shortcut] = []

    private struct Skip: Decodable {}

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let item = try? container.decode(Shortcut.self) {
                items.append(item)
            } else if (try? container.decode(Skip.self)) == nil {
                break   // can't advance past this element; stop rather than loop forever
            }
        }
    }
}

struct Config: Codable, Equatable {
    static let maxShortcuts = 9

    /// Matched exactly or as a prefix ("com.parallels" covers com.parallels.*).
    static let defaultPassthroughApps = [
        "com.parallels",
        "com.vmware.fusion",
        "com.utmapp.UTM",
        "org.virtualbox.app.VirtualBoxVM",
        "com.microsoft.rdc",
        "com.citrix.receiver",
        "com.omnissa.horizon",
        "com.vmware.horizon",
        "com.apple.ScreenSharing",
        "com.teamviewer.TeamViewer",
        "com.p5sys.jump.mac.viewer",
    ]

    /// Browsers (matched by plain prefix, so betas and nightlies count) whose
    /// windows are treated as private when the title can't be read.
    static let browserPrefixes = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.", "com.microsoft.edgemac",
        "com.brave.Browser", "company.thebrowser.", "com.operasoftware.", "com.vivaldi.",
        "org.torproject.", "com.duckduckgo.", "com.kagi.", "app.zen-browser.",
    ]

    static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return browserPrefixes.contains { bundleID.hasPrefix($0) }
    }

    static func bundleID(_ bundleID: String?, matchesAny entries: [String]) -> Bool {
        guard let bundleID else { return false }
        return entries.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
    }

    /// A plausible reverse-DNS bundle identifier (at least two parts), so an
    /// entry edited in from outside can't match nearly every app.
    static func isValidBundleIDEntry(_ entry: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        let parts = entry.split(separator: ".", omittingEmptySubsequences: false)
        return entry.count <= 255
            && parts.count >= 2
            && !parts.contains(where: { $0.isEmpty })
            && entry.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static let defaultPrivateApps = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.Passwords",
        "com.apple.keychainaccess",
        "in.sinew.Enpass-Desktop",
        "com.dashlane.dashlanephonefinal",
        "com.lastpass.LastPass",
        "org.torproject.torbrowser",
    ]

    var shortcuts: [Shortcut] = Config.defaultShortcuts
    var releaseToSwitch = true
    var previewSelected = true
    var showOtherSpaces = true
    var autoSize = true
    var thumbnailSize: Double = 170
    var showOnScreen: ScreenChoice = .activeWindow
    /// Off by default (as in AltTab): a bumped mouse shouldn't change the target.
    var selectOnHover = false
    /// Hand the shortcut to passthrough apps only while they're full screen.
    var passthroughOnlyWhenFullscreen = true
    /// Never listed in the switcher.
    var excludedBundleIDs: [String] = []
    /// When one of these apps is in front, Snaptic's shortcuts pass through to it
    /// (virtual machines, remote desktops).
    var passthroughBundleIDs: [String] = Config.defaultPassthroughApps
    /// Windows of these apps (and private-browsing windows) are never captured.
    var privateBundleIDs: [String] = Config.defaultPrivateApps
    var protectPrivateWindows = true
    /// Features turned off on the Features page (PLAN §2.2).
    var disabledFeatures = SwitcherFeaturesConfig()
    /// Optional global shortcut for "Gather windows here" (Carbon).
    var gatherShortcut: HotkeyCombo?

    static let defaultShortcuts: [Shortcut] = [
        Shortcut(modifier: .option, keyCode: KeyCode.tab, scope: .allWindows, style: .thumbnails),
        Shortcut(modifier: .option, keyCode: KeyCode.backtick, scope: .activeApp, style: .thumbnails),
    ]

    init() {}

    // Decode field by field so settings saved by an older version still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        shortcuts = (try? c.decode(LossyShortcutList.self, forKey: .shortcuts))?.items ?? d.shortcuts
        releaseToSwitch = (try? c.decode(Bool.self, forKey: .releaseToSwitch)) ?? d.releaseToSwitch
        previewSelected = (try? c.decode(Bool.self, forKey: .previewSelected)) ?? d.previewSelected
        showOtherSpaces = (try? c.decode(Bool.self, forKey: .showOtherSpaces)) ?? d.showOtherSpaces
        autoSize = (try? c.decode(Bool.self, forKey: .autoSize)) ?? d.autoSize
        thumbnailSize = (try? c.decode(Double.self, forKey: .thumbnailSize)) ?? d.thumbnailSize
        showOnScreen = (try? c.decode(ScreenChoice.self, forKey: .showOnScreen)) ?? d.showOnScreen
        selectOnHover = (try? c.decode(Bool.self, forKey: .selectOnHover)) ?? d.selectOnHover
        passthroughOnlyWhenFullscreen = (try? c.decode(Bool.self, forKey: .passthroughOnlyWhenFullscreen)) ?? d.passthroughOnlyWhenFullscreen
        excludedBundleIDs = (try? c.decode([String].self, forKey: .excludedBundleIDs)) ?? d.excludedBundleIDs
        passthroughBundleIDs = (try? c.decode([String].self, forKey: .passthroughBundleIDs)) ?? d.passthroughBundleIDs
        privateBundleIDs = (try? c.decode([String].self, forKey: .privateBundleIDs)) ?? d.privateBundleIDs
        protectPrivateWindows = (try? c.decode(Bool.self, forKey: .protectPrivateWindows)) ?? d.protectPrivateWindows
        disabledFeatures = c.lossy(.disabledFeatures, d.disabledFeatures)
        gatherShortcut = c.lossy(.gatherShortcut, nil)
    }

    /// Settings can be edited outside the app (`defaults write`), so clamp
    /// everything to values the UI could have produced.
    func sanitized() -> Config {
        var c = self
        var seen: [Shortcut] = []
        for shortcut in c.shortcuts where Keys.isAllowed(shortcut) && !seen.contains(where: { $0.sameKeys(as: shortcut) }) {
            seen.append(shortcut)
        }
        c.shortcuts = Array(seen.prefix(Config.maxShortcuts))
        if c.shortcuts.isEmpty { c.shortcuts = Config.defaultShortcuts }
        c.thumbnailSize = min(300, max(100, c.thumbnailSize.isFinite ? c.thumbnailSize : 170))
        c.excludedBundleIDs = Array(c.excludedBundleIDs.filter(Config.isValidBundleIDEntry).prefix(200))
        c.passthroughBundleIDs = Array(c.passthroughBundleIDs.filter(Config.isValidBundleIDEntry).prefix(200))
        c.privateBundleIDs = Array(c.privateBundleIDs.filter(Config.isValidBundleIDEntry).prefix(200))
        c.disabledFeatures = c.disabledFeatures.sanitized()
        if let combo = c.gatherShortcut {
            let normalized = HotkeyRules.normalized(combo)
            c.gatherShortcut = HotkeyRules.problem(normalized) == nil ? normalized : nil
        }
        return c
    }

    /// Whether a switcher feature is in effect: not turned off on the Features page and,
    /// for the aliased ones, its existing setting is on (PLAN §2.2).
    func isOn(_ feature: SwitcherFeature) -> Bool {
        guard disabledFeatures.isEnabled(feature) else { return false }
        switch feature {
        case .preview: return previewSelected && isOn(.thumbnails)
        case .otherSpaces: return showOtherSpaces
        case .hoverSelect: return selectOnHover
        default: return true
        }
    }

    /// The style a shortcut actually renders: with thumbnails off, icons.
    func effectiveStyle(_ shortcut: Shortcut) -> SwitcherStyle {
        shortcut.style == .thumbnails && !isOn(.thumbnails) ? .icons : shortcut.style
    }

    /// Shortcuts that may act: ⌘ shortcuts only while ⌘⇥ takeover is on.
    var activeShortcuts: [Shortcut] {
        isOn(.commandTabTakeover) ? shortcuts : shortcuts.filter { $0.modifier != .command }
    }

    var needsScreenCapture: Bool {
        guard isOn(.thumbnails) else { return false }
        return isOn(.preview) || shortcuts.contains { $0.style == .thumbnails }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private static let defaultsKey = "SnapticConfig.v1"

    @Published var config: Config {
        didSet {
            guard config != oldValue else { return }
            save()
            onChange?(config)
        }
    }

    var onChange: (@MainActor (Config) -> Void)?

    /// Reads only the persistent domain: launch arguments (`-SnapticConfig.v1 …`), the
    /// volatile domain and managed preferences are ignored (PLAN §3.4).
    private init() {
        if let data = ConfigStore<ModulesConfig>.persistentData(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(Config.self, from: data) {
            config = saved.sanitized()
        } else {
            config = Config()
        }
    }

    /// Saves are immediate; kept for the host's quit path.
    func flush() { save() }

    /// Back to defaults (General → Backup & Reset).
    func reset() { config = Config() }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
