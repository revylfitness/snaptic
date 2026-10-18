import Foundation

// Pure rules behind C's Displays settings pages (owner: C; PLAN 0.3 §4.3 Brightness and Dimming, Keyboard and its
// Keyboard Shortcuts sheet, §4.4 duplicates 3 and 5): how the pages show a stored combination of settings as one
// control, and how the shortcuts sheet groups and filters every Displays action. Tested on Linux.

// MARK: - Keyboard Shortcuts groups

/// The groups of Keyboard › Keyboard Shortcuts… (one grouped list of every Displays action), in display order.
package enum DisplayShortcutGroup: String, CaseIterable, Sendable {
    case brightness, color, volumeAndContrast, inputsAndPower, resolution, arrangement, pictureInPicture, tools,
         customActions

    package var title: String {
        switch self {
        case .brightness: return L("Brightness")
        case .color: return L("Color")
        case .volumeAndContrast: return L("Volume and contrast")
        case .inputsAndPower: return L("Inputs and power")
        case .resolution: return L("Resolution")
        case .arrangement: return L("Arrangement")
        case .pictureInPicture: return L("Picture in Picture")
        case .tools: return L("Tools")
        case .customActions: return L("Custom actions")
        }
    }

    /// The group of a registered action, from its id ("c.brightnessUp", "d.favorite3", "a.custom.<id>").
    /// Unknown ids land in Tools, so every action is listed somewhere.
    package static func group(for actionID: String) -> DisplayShortcutGroup {
        let id = actionID
        func starts(_ prefixes: String...) -> Bool { prefixes.contains { id.hasPrefix($0) } }
        if starts("a.custom") { return .customActions }
        if starts("c.brightness", "c.xdr", "c.sync") { return .brightness }
        if starts("c.volume", "c.mute", "c.contrast") { return .volumeAndContrast }
        if starts("c.gamma", "c.temperature", "c.invert", "c.color", "c.nightShift", "c.menuBarStrip") { return .color }
        if starts("c.ddcPower", "c.ddcStandby", "c.inputSlot") { return .inputsAndPower }
        if starts("d.resolution", "d.hiDPI", "d.native", "d.default", "d.notch", "d.matchUI", "d.favorite") {
            return .resolution
        }
        if starts("d.") { return .arrangement }
        if starts("e.") { return .pictureInPicture }
        return .tools
    }

    /// Whether a row matches the sheet's filter: every word of the query starts a word of the title or of the
    /// group's title (case and diacritics folded). An empty query matches everything.
    package static func matches(title: String, group: DisplayShortcutGroup, query: String) -> Bool {
        let wanted = SettingsSearch.words(String(query.prefix(SettingsSearch.maxQueryLength)))
        guard !wanted.isEmpty else { return true }
        let words = SettingsSearch.words(title) + SettingsSearch.words(group.title)
        return wanted.allSatisfy { w in words.contains { $0.hasPrefix(w) } }
    }
}

// MARK: - Brightness and volume indicator

/// Keyboard › "Brightness and volume indicator": one pop-up over `keys.osdStyle` and `keys.osdNative` (the system
/// indicator is offered only where macOS still draws it, 14 and 15).
package enum IndicatorStyleChoice: String, CaseIterable, Sendable {
    case automatic, classic, rounded, system
}

extension KeysConfig {
    /// The pop-up's value. `systemOffered` = macOS draws its own indicator and Snaptic can call it.
    package func indicatorChoice(systemOffered: Bool) -> IndicatorStyleChoice {
        if systemOffered && osdNative { return .system }
        switch osdStyle {
        case nil: return .automatic
        case .classic?: return .classic
        case .rounded?: return .rounded
        }
    }

    /// Writes a choice; "system" keeps the drawn style for when the system indicator can't be used.
    package func settingIndicator(_ choice: IndicatorStyleChoice) -> KeysConfig {
        var c = self
        switch choice {
        case .system:
            c.osdNative = true
        case .automatic:
            c.osdNative = false
            c.osdStyle = nil
        case .classic:
            c.osdNative = false
            c.osdStyle = .classic
        case .rounded:
            c.osdNative = false
            c.osdStyle = .rounded
        }
        return c
    }
}

// MARK: - Restore brightness

/// Brightness and Dimming › "Restore brightness at login and wake": one pop-up over the `brightnessRestore` feature
/// (Off) and `brightness.restoreMode`.
package enum BrightnessRestoreChoice {
    package static func shown(featureOn: Bool, mode: BrightnessRestoreMode) -> BrightnessRestoreMode {
        featureOn ? mode : .off
    }

    /// The feature state and mode to store for a choice; Off turns the feature off and keeps the stored mode.
    package static func stored(_ choice: BrightnessRestoreMode,
                               current mode: BrightnessRestoreMode) -> (featureOn: Bool, mode: BrightnessRestoreMode) {
        choice == .off ? (false, mode) : (true, choice)
    }
}

// MARK: - Restore defaults

extension DisplaysConfig {
    /// Keyboard › Advanced › Restore Keyboard Defaults…: every keyboard setting back to its default, except the
    /// shortcuts recorded in Keyboard Shortcuts… (a separate list the person built one by one).
    package func restoringKeyboardDefaults() -> DisplaysConfig {
        var c = restoringDefaults(scope: .keyboard)
        c.keys.shortcuts = keys.shortcuts
        return c
    }

    /// Color › Advanced › Restore Color Defaults… for one display (`key`) or every display (nil). The menu bar
    /// overlays (Display Details) and the reserved software brightness factor share `PerDisplayColor` but aren't
    /// color settings, so they stay.
    package func restoringColorDefaults(for key: DisplayKey?) -> DisplaysConfig {
        var c = restoringDefaults(scope: .color(key))
        for (k, old) in perDisplay.values where key == nil || k == key {
            guard var entry = c.perDisplay[k] else { continue }
            entry.color.menuBarStrip = old.color.menuBarStrip
            entry.color.cornerRadiusTop = old.color.cornerRadiusTop
            entry.color.cornerRadiusBottom = old.color.cornerRadiusBottom
            entry.color.adjustments.brightness = old.color.adjustments.brightness
            c.perDisplay[k] = entry
        }
        return c
    }
}

// MARK: - Hardware controls

package enum HardwareControlText {
    /// "0x10 Brightness"-style raw value entry: decimal, or hexadecimal with "0x" or a trailing "h".
    /// Nil when it isn't a 16-bit number.
    package static func parseValue(_ text: String) -> UInt16? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty, t.count <= 8 else { return nil }
        if t.hasPrefix("0x") { return UInt16(t.dropFirst(2), radix: 16) }
        if t.hasSuffix("h") { return UInt16(t.dropLast(), radix: 16) }
        return UInt16(t, radix: 10)
    }
}
