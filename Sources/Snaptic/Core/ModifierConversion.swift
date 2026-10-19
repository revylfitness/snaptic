import AppKit
import CoreGraphics
import SnapticKit

/// Conversions between AppKit, Quartz event and Carbon modifier flags (Carbon bits are
/// what `HotkeyCombo` stores).
enum ModifierConversion {
    static func carbon(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= HotkeyRules.command }
        if flags.contains(.shift) { result |= HotkeyRules.shift }
        if flags.contains(.option) { result |= HotkeyRules.option }
        if flags.contains(.control) { result |= HotkeyRules.control }
        return result
    }

    static func carbon(from flags: CGEventFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.maskCommand) { result |= HotkeyRules.command }
        if flags.contains(.maskShift) { result |= HotkeyRules.shift }
        if flags.contains(.maskAlternate) { result |= HotkeyRules.option }
        if flags.contains(.maskControl) { result |= HotkeyRules.control }
        return result
    }

    static func modifierFlags(fromCarbon carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & HotkeyRules.command != 0 { flags.insert(.command) }
        if carbon & HotkeyRules.shift != 0 { flags.insert(.shift) }
        if carbon & HotkeyRules.option != 0 { flags.insert(.option) }
        if carbon & HotkeyRules.control != 0 { flags.insert(.control) }
        return flags
    }

    /// A combo from a key-down event in a recorder.
    static func combo(from event: NSEvent) -> HotkeyCombo {
        HotkeyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: carbon(from: event.modifierFlags))
    }
}
