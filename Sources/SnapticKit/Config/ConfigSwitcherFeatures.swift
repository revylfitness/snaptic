import Foundation

/// The Window Switcher's turned-off features (PLAN §2.2), stored inside the switcher's
/// `SnapticConfig.v1` as `disabledFeatures`: a JSON array of feature names.
///
/// Decoding is lossy per element. Names this version doesn't know (from a newer Snaptic)
/// are kept and written back unchanged, so stored settings are never rewritten.
package struct SwitcherFeaturesConfig: ConfigModel {
    package private(set) var disabled: Set<SwitcherFeature>
    private var unknown: [String]

    package static let maxUnknown = 32
    package static let maxNameLength = 64

    /// Features whose on/off state is an existing switcher setting (bound to the same key
    /// on the Features page): preview ↔ previewSelected, otherSpaces ↔ showOtherSpaces,
    /// hoverSelect ↔ selectOnHover.
    package static let aliased: Set<SwitcherFeature> = [.preview, .otherSpaces, .hoverSelect]

    /// Window actions available from keys and hover buttons while the switcher is open.
    package static let actions: [SwitcherFeature] = [.actionClose, .actionMinimize, .actionFullscreen,
                                                    .actionQuit, .actionHide]

    package init() {
        disabled = []
        unknown = []
    }

    package init(disabled: Set<SwitcherFeature>) {
        self.disabled = disabled
        unknown = []
    }

    package init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var known = Set<SwitcherFeature>()
        var other: [String] = []
        var count = 0
        while !container.isAtEnd && count < 256 {
            count += 1
            if let name = try? container.decode(String.self) {
                if let feature = SwitcherFeature(rawValue: name) {
                    known.insert(feature)
                } else {
                    other.append(name)
                }
            } else if (try? container.decode(Skip.self)) == nil {
                break   // can't advance past this element
            }
        }
        disabled = known
        unknown = other
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for name in disabled.map(\.rawValue).sorted() { try container.encode(name) }
        for name in unknown { try container.encode(name) }
    }

    package func sanitized() -> SwitcherFeaturesConfig {
        var c = self
        var seen = Set<String>()
        c.unknown = unknown.filter { name in
            guard !name.isEmpty, name.utf8.count <= Self.maxNameLength, !seen.contains(name) else { return false }
            seen.insert(name)
            return true
        }
        c.unknown = Array(c.unknown.sorted().prefix(Self.maxUnknown))
        return c
    }

    // MARK: Queries

    /// Not turned off here. Aliased features also need their switcher setting on.
    package func isEnabled(_ feature: SwitcherFeature) -> Bool { !disabled.contains(feature) }

    package mutating func set(_ feature: SwitcherFeature, enabled: Bool) {
        if enabled { disabled.remove(feature) } else { disabled.insert(feature) }
    }

    /// Names kept from a newer version (for tests and diagnostics).
    package var unknownNames: [String] { unknown }

    /// The hint line shown while the switcher is open, listing only the keys that work.
    package func hintLine() -> String {
        var parts: [String] = []
        if isEnabled(.search) { parts.append(L("S search")) }
        if isEnabled(.actionClose) { parts.append(L("W close")) }
        if isEnabled(.actionMinimize) { parts.append(L("M minimize")) }
        if isEnabled(.actionFullscreen) { parts.append(L("F full screen")) }
        if isEnabled(.actionQuit) { parts.append(L("Q quit")) }
        if isEnabled(.actionHide) { parts.append(L("H hide")) }
        return parts.joined(separator: " · ")
    }

    // MARK: Descriptions (Features page)

    package static func title(_ feature: SwitcherFeature) -> String {
        switch feature {
        case .thumbnails: return L("Window thumbnails")
        case .preview: return L("Full-size preview of the selected window")
        case .otherSpaces: return L("Windows on other Spaces")
        case .windowlessApps: return L("Apps with no open windows")
        case .search: return L("Search (S or /)")
        case .actionClose: return L("Close window (W)")
        case .actionMinimize: return L("Minimize window (M)")
        case .actionFullscreen: return L("Full screen (F)")
        case .actionHide: return L("Hide app (H)")
        case .actionQuit: return L("Quit app (Q)")
        case .hoverButtons: return L("Window buttons on hover")
        case .hoverSelect: return L("Hovering changes the selection")
        case .commandTabTakeover: return L("⌘ shortcuts (replace ⌘⇥)")
        case .passthrough: return L("Apps that keep the shortcut")
        }
    }

    package static func detail(_ feature: SwitcherFeature) -> String {
        switch feature {
        case .thumbnails:
            return L("Off: every shortcut shows app icons, with no live preview. Snaptic then never asks for Screen Recording.")
        case .preview: return L("Shows the selected window full size behind the switcher.")
        case .otherSpaces: return L("Off: only windows on the current Space are listed.")
        case .windowlessApps: return L("Off: apps without windows are hidden from every shortcut.")
        case .search: return L("Off: S and / do nothing while the switcher is open.")
        case .actionClose, .actionMinimize, .actionFullscreen, .actionHide, .actionQuit:
            return L("Off: the key does nothing while the switcher is open, and its button and hint are hidden.")
        case .hoverButtons: return L("Close, minimize and full-screen buttons on the window under the pointer.")
        case .hoverSelect: return L("Off by default, so a bumped mouse doesn't change the target.")
        case .commandTabTakeover: return L("Off: shortcuts that use ⌘ are ignored and macOS keeps ⌘⇥.")
        case .passthrough: return L("Off: the app exceptions list is ignored.")
        }
    }

    /// Consumes any JSON value without reading it.
    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
