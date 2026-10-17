import Foundation

/// The four VCP write tiers (PLAN §7.4, R5.8). Reads are always allowed.
package enum VCPTier: String, Codable, CaseIterable, Sendable {
    /// Allowed (user-initiated or automatic).
    case safe
    /// Modal before sending unless the code + value is "Allow without asking" on that
    /// display. Never part of automatic plans.
    case preConfirm
    /// Manufacturer codes 0xE0–0xFF: a typed per-display unlock, then preConfirm.
    case unlockable
    /// Refused everywhere.
    case denied

    /// True when a write needs a PreConfirmToken.
    package var needsConfirmation: Bool { self == .preConfirm || self == .unlockable }
    /// True when automatic sources (restore, sync, layouts) may write it.
    package var allowsAutomatic: Bool { self == .safe }
}

package enum VCPPolicy {
    /// Continuous or harmless codes that are always safe.
    package static let safeCodes: Set<UInt8> = [
        0x10, 0x12, 0x13, 0x6B, 0x16, 0x18, 0x1A, 0x6C, 0x6E, 0x70, 0x62, 0x87, 0x8A,
    ]
    /// Color preset values MCCS defines (sRGB, native, 4000 K … 11500 K, user 1–3).
    package static let knownColorPresets: Set<UInt16> = Set(0x01...0x0D)
    /// Codes that can switch the picture away from this Mac.
    package static let preConfirmCodes: Set<UInt8> = [0x60, 0xF4, 0xE7, 0xE8, 0xE9, 0xF3]
    /// Codes that reset or lock the monitor.
    package static let deniedCodes: Set<UInt8> = [0x01, 0x04, 0x05, 0x06, 0x08, 0x0A, 0xB0, 0xCA, 0xCC]

    package static let brightness: UInt8 = 0x10
    package static let contrast: UInt8 = 0x12
    package static let colorPreset: UInt8 = 0x14
    package static let redGain: UInt8 = 0x16
    package static let greenGain: UInt8 = 0x18
    package static let blueGain: UInt8 = 0x1A
    package static let input: UInt8 = 0x60
    package static let volume: UInt8 = 0x62
    package static let sharpness: UInt8 = 0x87
    package static let mute: UInt8 = 0x8D
    package static let power: UInt8 = 0xD6
    package static let displayMode: UInt8 = 0xDC
    package static let lgAlternateInput: UInt8 = 0xF4

    /// Power values: 1 on, 2 standby, 3 suspend, 4 off (DPM), 5 hard off (denied).
    package static let powerOn: UInt16 = 1

    /// The tier of writing `value` to `code`. `capabilities` narrows the discrete codes.
    package static func tier(code: UInt8, value: UInt16, capabilities: DDCCapabilities?) -> VCPTier {
        if deniedCodes.contains(code) { return .denied }
        if safeCodes.contains(code) { return .safe }
        switch code {
        case colorPreset:
            let listed: Set<UInt16>? = capabilities?.values(for: colorPreset).map { Set($0) }
            let allowed = listed ?? knownColorPresets
            return allowed.contains(value) ? .safe : .denied
        case displayMode:
            guard let allowed = capabilities?.values(for: displayMode) else { return .denied }
            return allowed.contains(value) ? .safe : .denied
        case mute:
            // MCCS 0x8D is "audio mute / screen blank". If the display lists anything
            // beyond 1 (mute) and 2 (unmute), a write may blank the screen.
            let listed = capabilities?.vcp[mute] ?? []
            if listed.contains(where: { $0 > 2 }) { return .preConfirm }
            return value == 1 || value == 2 ? .safe : .preConfirm
        case power:
            switch value {
            case 1: return .safe
            case 2, 3, 4: return .preConfirm
            default: return .denied
            }
        default:
            break
        }
        if preConfirmCodes.contains(code) { return .preConfirm }
        if code >= 0xE0 { return .unlockable }
        return .denied
    }

    /// Codes Snaptic treats as continuous sliders.
    package static let continuousCodes: Set<UInt8> = [0x10, 0x12, 0x13, 0x16, 0x18, 0x1A, 0x62, 0x6C, 0x6E, 0x70, 0x87, 0x8A]

    /// Human name for a code (diagnostics, the DDC page).
    package static func name(_ code: UInt8) -> String {
        switch code {
        case 0x10: return L("Brightness")
        case 0x12: return L("Contrast")
        case 0x13: return L("Backlight")
        case 0x14: return L("Color preset")
        case 0x16: return L("Red gain")
        case 0x18: return L("Green gain")
        case 0x1A: return L("Blue gain")
        case 0x60: return L("Input source")
        case 0x62: return L("Volume")
        case 0x6B: return L("Backlight (white)")
        case 0x6C: return L("Red black level")
        case 0x6E: return L("Green black level")
        case 0x70: return L("Blue black level")
        case 0x87: return L("Sharpness")
        case 0x8A: return L("Saturation")
        case 0x8D: return L("Mute")
        case 0xD6: return L("Power mode")
        case 0xDC: return L("Display mode")
        case 0xDF: return L("VCP version")
        case 0xC8: return L("Controller type")
        case 0xC9: return L("Firmware level")
        case 0xC0: return L("Usage hours")
        case 0xF4: return L("Input source (LG)")
        default: return L("VCP ") + hex(code)
        }
    }

    /// Well-known MCCS input source values.
    package static func inputName(_ value: UInt16) -> String {
        switch value & 0xFF {
        case 0x01: return L("VGA 1")
        case 0x02: return L("VGA 2")
        case 0x03: return L("DVI 1")
        case 0x04: return L("DVI 2")
        case 0x05: return L("Composite 1")
        case 0x06: return L("Composite 2")
        case 0x07: return L("S-Video 1")
        case 0x08: return L("S-Video 2")
        case 0x09: return L("Tuner 1")
        case 0x0A: return L("Tuner 2")
        case 0x0B: return L("Tuner 3")
        case 0x0C: return L("Component 1")
        case 0x0D: return L("Component 2")
        case 0x0E: return L("Component 3")
        case 0x0F: return L("DisplayPort 1")
        case 0x10: return L("DisplayPort 2")
        case 0x11: return L("HDMI 1")
        case 0x12: return L("HDMI 2")
        case 0x1B: return L("USB-C")
        default: return L("Input ") + hex(UInt8(truncatingIfNeeded: value))
        }
    }

    /// "Allow without asking" key for a code + value pair: "60:000F".
    package static func allowKey(code: UInt8, value: UInt16) -> String {
        hex(code) + ":" + hex(UInt8(truncatingIfNeeded: value >> 8)) + hex(UInt8(truncatingIfNeeded: value))
    }

    package static func isValidAllowKey(_ key: String) -> Bool {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 4 else { return false }
        return parts[0].allSatisfy(\.isHexDigit) && parts[1].allSatisfy(\.isHexDigit)
            && key == key.uppercased()
    }

    /// Two uppercase hex digits.
    package static func hex(_ byte: UInt8) -> String {
        let digits = Array("0123456789ABCDEF")
        return String([digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]])
    }

    /// Parses "10", "0x10", "10h" into a code.
    package static func parseCode(_ text: String) -> UInt8? {
        var t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasPrefix("0x") { t.removeFirst(2) }
        if t.hasSuffix("h") { t.removeLast() }
        guard (1...2).contains(t.count), let v = UInt8(t, radix: 16) else { return nil }
        return v
    }
}
