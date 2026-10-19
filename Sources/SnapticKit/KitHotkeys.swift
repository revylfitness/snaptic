import Foundation

/// Pure rules for global shortcuts (`HotkeyCombo` uses Carbon key codes and modifiers).
package enum HotkeyRules {
    // Carbon modifier bits (Events.h).
    package static let command: UInt32 = 0x0100
    package static let shift: UInt32 = 0x0200
    package static let option: UInt32 = 0x0800
    package static let control: UInt32 = 0x1000
    package static let allModifiers: UInt32 = command | shift | option | control

    /// F1–F20 key codes: these may be used without a modifier.
    package static let functionKeyCodes: Set<UInt32> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    /// Keys that never make a shortcut on their own (modifiers, Caps Lock, Fn).
    package static let modifierKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    package enum Problem: Equatable, Sendable {
        case needsModifier
        /// ⌥-only or ⇧-only (or ⌥⇧) combos: macOS 15 rejects them for Carbon hotkeys.
        case optionShiftOnly
        case modifierKey
        case unknownKey
    }

    /// Nil when the combo can be registered; otherwise why not.
    package static func problem(_ combo: HotkeyCombo) -> Problem? {
        guard combo.keyCode < 128 else { return .unknownKey }
        if modifierKeyCodes.contains(combo.keyCode) { return .modifierKey }
        let mods = combo.carbonModifiers & allModifiers
        if functionKeyCodes.contains(combo.keyCode) { return nil }
        if mods == 0 { return .needsModifier }
        if mods & (command | control) == 0 { return .optionShiftOnly }
        return nil
    }

    package static func message(_ problem: Problem) -> String {
        switch problem {
        case .needsModifier: return L("Add ⌘ or ⌃ (only F-keys work alone).")
        case .optionShiftOnly: return L("macOS doesn’t allow ⌥ or ⇧ alone; add ⌘ or ⌃.")
        case .modifierKey: return L("Press a key together with the modifiers.")
        case .unknownKey: return L("That key can’t be used.")
        }
    }

    /// Only the Carbon modifier bits we use, so equal shortcuts compare equal.
    package static func normalized(_ combo: HotkeyCombo) -> HotkeyCombo {
        HotkeyCombo(keyCode: combo.keyCode, carbonModifiers: combo.carbonModifiers & allModifiers)
    }

    /// "⌃⌥⇧⌘K", in Apple's modifier order.
    package static func displayString(_ combo: HotkeyCombo) -> String {
        var s = ""
        if combo.carbonModifiers & control != 0 { s += "⌃" }
        if combo.carbonModifiers & option != 0 { s += "⌥" }
        if combo.carbonModifiers & shift != 0 { s += "⇧" }
        if combo.carbonModifiers & command != 0 { s += "⌘" }
        return s + keyName(combo.keyCode)
    }

    /// Names for ANSI key codes (the physical key; layouts may print other characters).
    package static func keyName(_ code: UInt32) -> String {
        if let name = names[code] { return name }
        return L("Key ") + String(code)
    }

    private static let names: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L",
        46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W",
        7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
        10: "§", 36: "↩", 48: "⇥", 49: L("Space"), 51: "⌫", 53: "⎋", 117: "⌦", 115: "↖", 119: "↘",
        116: "⇞", 121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑", 76: "⌤",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
        65: L("Keypad ."), 67: L("Keypad *"), 69: L("Keypad +"), 75: L("Keypad /"), 78: L("Keypad -"),
        81: L("Keypad ="), 82: L("Keypad 0"), 83: L("Keypad 1"), 84: L("Keypad 2"), 85: L("Keypad 3"),
        86: L("Keypad 4"), 87: L("Keypad 5"), 88: L("Keypad 6"), 89: L("Keypad 7"), 91: L("Keypad 8"),
        92: L("Keypad 9"),
    ]
}
