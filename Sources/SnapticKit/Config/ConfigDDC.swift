import Foundation

// DDC settings (owner: C). Every field has a default, decodes lossily and is clamped.

/// A VCP code as a LossyMap key: two uppercase hex digits ("10").
package struct VCPKey: RawRepresentable, Hashable, Codable, Sendable, Comparable {
    package let rawValue: String

    package init?(rawValue: String) {
        guard rawValue.count == 2, let code = UInt8(rawValue, radix: 16), VCPPolicy.hex(code) == rawValue else {
            return nil
        }
        self.rawValue = rawValue
    }

    package init(_ code: UInt8) { rawValue = VCPPolicy.hex(code) }

    package var code: UInt8 { UInt8(rawValue, radix: 16) ?? 0 }

    package init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        guard let key = VCPKey(rawValue: try c.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid VCP code")
        }
        self = key
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    package static func < (a: VCPKey, b: VCPKey) -> Bool { a.code < b.code }
}

/// Per-control tuning (parity §6.1): raw range, invert, periodic readback.
package struct DDCControlTuning: Codable, Equatable, Sendable {
    /// nil = automatic (on when the capabilities list the code).
    package var enabled: Bool?
    /// Raw value used for 0%.
    package var minimum: UInt16
    /// Raw value used for 100%; nil = the display's reported maximum.
    package var maximum: UInt16?
    package var inverted: Bool
    /// Seconds between readbacks (0 = off, else 0.5…3600). Needs DDCConfig.readback.
    package var readbackInterval: Double
    /// Show as a slider in the menu (nil = default: brightness and volume only).
    package var showInMenu: Bool?

    package init() {
        enabled = nil
        minimum = 0
        maximum = nil
        inverted = false
        readbackInterval = 0
        showInMenu = nil
    }

    private enum CodingKeys: String, CodingKey { case enabled, minimum, maximum, inverted, readbackInterval, showInMenu }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.lossy(.enabled, nil as Bool?)
        minimum = c.lossy(.minimum, UInt16(0))
        maximum = c.lossy(.maximum, nil as UInt16?)
        inverted = c.lossy(.inverted, false)
        readbackInterval = c.lossy(.readbackInterval, 0.0)
        showInMenu = c.lossy(.showInMenu, nil as Bool?)
    }

    package func sanitized() -> DDCControlTuning {
        var t = self
        if let maximum, maximum <= minimum { t.maximum = nil }
        if readbackInterval.isFinite, readbackInterval > 0 {
            t.readbackInterval = min(3600, max(0.5, readbackInterval))
        } else {
            t.readbackInterval = 0
        }
        return t
    }

    /// Raw value → 0…1 given the display's maximum.
    package func fraction(raw: UInt16, displayMax: UInt16) -> Double {
        let hi = Double(maximum ?? displayMax), lo = Double(min(minimum, maximum ?? displayMax))
        guard hi > lo else { return 0 }
        var f = (Double(raw) - lo) / (hi - lo)
        f = min(1, max(0, f))
        return inverted ? 1 - f : f
    }

    /// 0…1 → raw value given the display's maximum.
    package func raw(fraction: Double, displayMax: UInt16) -> UInt16 {
        let hi = Double(maximum ?? displayMax), lo = Double(min(minimum, maximum ?? displayMax))
        var f = fraction.isFinite ? min(1, max(0, fraction)) : 0
        if inverted { f = 1 - f }
        guard hi > lo else { return UInt16(clamping: Int(hi)) }
        return UInt16(clamping: Int((lo + f * (hi - lo)).rounded()))
    }
}

/// One input source (parity §6.1 "Input source list customization").
package struct DDCInputEntry: Codable, Equatable, Sendable, Identifiable {
    package var value: UInt16
    package var name: String
    package var hidden: Bool
    /// LG alternate addressing (VCP 0xF4, data address 0x50).
    package var lgAlt: Bool

    package var id: String { (lgAlt ? "lg:" : "") + String(value) }

    package init(value: UInt16, name: String, hidden: Bool = false, lgAlt: Bool = false) {
        self.value = value
        self.name = name
        self.hidden = hidden
        self.lgAlt = lgAlt
    }

    private enum CodingKeys: String, CodingKey { case value, name, hidden, lgAlt }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decode(UInt16.self, forKey: .value)
        name = c.lossy(.name, "")
        hidden = c.lossy(.hidden, false)
        lgAlt = c.lossy(.lgAlt, false)
    }
}

/// A user-defined VCP control (parity §6.6, ddcCustom): a slider or a one-shot command.
package struct DDCCustomControl: Codable, Equatable, Sendable, Identifiable {
    package enum Kind: String, Codable, CaseIterable, Sendable { case range, command }

    package var id: StableID
    package var name: String
    package var code: UInt8
    package var kind: Kind
    /// Value sent by a command.
    package var value: UInt16
    package var showInMenu: Bool

    package init(id: StableID = StableID(), name: String, code: UInt8, kind: Kind, value: UInt16 = 0,
                 showInMenu: Bool = false) {
        self.id = id
        self.name = name
        self.code = code
        self.kind = kind
        self.value = value
        self.showInMenu = showInMenu
    }

    private enum CodingKeys: String, CodingKey { case id, name, code, kind, value, showInMenu }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lossy(.id, StableID())
        name = c.lossy(.name, "")
        code = try c.decode(UInt8.self, forKey: .code)
        kind = c.lossy(.kind, Kind.range)
        value = c.lossy(.value, UInt16(0))
        showInMenu = c.lossy(.showInMenu, false)
    }
}

package struct DDCConfig: ConfigModel {
    /// Periodic readback (per-control interval). Needed to notice changes made with the
    /// monitor's own buttons (sync of external changes, R5.8).
    package var readback: Bool
    /// Default readback interval for brightness and volume (0.5…3600 s).
    package var defaultReadbackInterval: Double
    /// Re-apply values after wake when the read-back differs.
    package var restoreOnWake: Bool

    package init() {
        readback = false
        defaultReadbackInterval = 5
        restoreOnWake = true
    }

    private enum CodingKeys: String, CodingKey { case readback, defaultReadbackInterval, restoreOnWake }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        readback = c.lossy(.readback, false)
        defaultReadbackInterval = c.lossy(.defaultReadbackInterval, 5.0)
        restoreOnWake = c.lossy(.restoreOnWake, true)
    }

    package func sanitized() -> DDCConfig {
        var c = self
        c.defaultReadbackInterval = ConfigClamp.value(defaultReadbackInterval, 0.5...3600, fallback: 5)
        return c
    }
}

package struct PerDisplayDDC: ConfigModel {
    /// DDC on this display at all.
    package var enabled: Bool
    /// Remembered framing (nil = not learned yet).
    package var framing: DDCFraming?
    /// Wait before reading a reply (10…200 ms; 40+ for slow displays).
    package var replyDelayMs: Int
    package var retries: Int
    /// 1 = single write (default), 2 = send every write twice (flaky displays).
    package var writeCount: Int
    package var ignoreChecksum: Bool
    package var controls: LossyMap<VCPKey, DDCControlTuning>
    /// Input list in display order (≤ 32).
    package var inputs: [DDCInputEntry]
    /// Manufacturer codes (0xE0–0xFF) unlocked by typing them (≤ 32).
    package var unlockedCodes: [VCPKey]
    package var customControls: [DDCCustomControl]
    /// Value the standby switch sends (2 standby, 3 suspend, 4 off).
    package var standbyValue: UInt16

    package static let maxInputs = 32
    package static let maxUnlocked = 32
    package static let maxCustom = 32

    package init() {
        enabled = true
        framing = nil
        replyDelayMs = DDCPacket.defaultReplyDelayMs
        retries = DDCPacket.defaultRetries
        writeCount = 1
        ignoreChecksum = false
        controls = LossyMap()
        inputs = []
        unlockedCodes = []
        customControls = []
        standbyValue = 4
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, framing, replyDelayMs, retries, writeCount, ignoreChecksum, controls, inputs, unlockedCodes, customControls, standbyValue
    }

    package init(from decoder: Decoder) throws {
        let d = PerDisplayDDC()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.lossy(.enabled, true)
        framing = c.lossy(.framing, nil as DDCFraming?)
        replyDelayMs = c.lossy(.replyDelayMs, d.replyDelayMs)
        retries = c.lossy(.retries, d.retries)
        writeCount = c.lossy(.writeCount, 1)
        ignoreChecksum = c.lossy(.ignoreChecksum, false)
        controls = c.lossy(.controls, LossyMap())
        inputs = c.lossyArray(.inputs, [])
        unlockedCodes = c.lossyArray(.unlockedCodes, [])
        customControls = c.lossyArray(.customControls, [])
        standbyValue = c.lossy(.standbyValue, UInt16(4))
    }

    package func sanitized() -> PerDisplayDDC {
        var c = self
        c.replyDelayMs = ConfigClamp.int(replyDelayMs, 10...200)
        c.retries = ConfigClamp.int(retries, 0...8)
        c.writeCount = ConfigClamp.int(writeCount, 1...2)
        c.controls.dropUnknown(keepingAtMost: 0)
        c.controls = LossyMap(controls.values.mapValues { $0.sanitized() })
        var seen: Set<String> = []
        c.inputs = inputs.compactMap { entry -> DDCInputEntry? in
            guard seen.insert(entry.id).inserted else { return nil }
            var e = entry
            e.name = ConfigClamp.text(entry.name)
            return e
        }
        c.inputs = Array(c.inputs.prefix(Self.maxInputs))
        var unlocked: [VCPKey] = []
        for key in unlockedCodes
        where VCPPolicy.tier(code: key.code, value: 0, capabilities: nil) == .unlockable && !unlocked.contains(key) {
            unlocked.append(key)
        }
        c.unlockedCodes = Array(unlocked.prefix(Self.maxUnlocked))
        var ids: Set<StableID> = []
        c.customControls = customControls.compactMap { control -> DDCCustomControl? in
            guard ids.insert(control.id).inserted else { return nil }
            var x = control
            x.name = ConfigClamp.text(control.name)
            return x
        }
        c.customControls = Array(c.customControls.prefix(Self.maxCustom))
        if !(2...4).contains(standbyValue) { c.standbyValue = 4 }
        return c
    }

    package func tuning(_ code: UInt8) -> DDCControlTuning { controls[VCPKey(code)] ?? DDCControlTuning() }

    package func isUnlocked(_ code: UInt8) -> Bool { unlockedCodes.contains(VCPKey(code)) }
}

