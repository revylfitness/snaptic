import Foundation

// Safety settings (owner: B). PLAN §4.3, §4.4, §4.7, R3C §2.2. Every field has a default,
// decodes lossily and is clamped in sanitized().

/// DDC writes the user allowed without asking, for one display ("vcp:value" pairs, hex).
package struct PreConfirmAllowList: Codable, Equatable, Sendable {
    package static let maxEntries = 32
    package var entries: [String]

    package init(entries: [String] = []) { self.entries = entries }

    package init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        entries = ((try? c.decode([String].self)) ?? []).filter(Self.isValidEntry)
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(entries)
    }

    package static func entry(vcp: UInt8, value: UInt16) -> String {
        String(format: "%02x:%04x", Int(vcp), Int(value))
    }

    package static func isValidEntry(_ s: String) -> Bool {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 4 else { return false }
        return UInt8(parts[0], radix: 16) != nil && UInt16(parts[1], radix: 16) != nil
            && s.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) || $0 == 0x3A }
    }

    package func allows(vcp: UInt8, value: UInt16) -> Bool { entries.contains(Self.entry(vcp: vcp, value: value)) }

    package func sanitized() -> PreConfirmAllowList {
        var seen: Set<String> = []
        let unique = entries.filter { Self.isValidEntry($0) && seen.insert($0).inserted }
        return PreConfirmAllowList(entries: Array(unique.suffix(Self.maxEntries)))
    }
}

/// Modes the user kept on one display (part of its known-good set, PLAN §4.3).
package struct KeptModes: Codable, Equatable, Sendable {
    package static let maxModes = 32
    package var modes: [ModeRef]

    package init(modes: [ModeRef] = []) { self.modes = modes }

    package init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        modes = (try? c.decode([LossyModeRef].self))?.compactMap(\.value) ?? []
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(modes)
    }

    package mutating func remember(_ m: ModeRef) {
        modes.removeAll { $0 == m || $0.sameShape(as: m) }
        modes.append(m)
        if modes.count > Self.maxModes { modes.removeFirst(modes.count - Self.maxModes) }
    }

    package mutating func forget(_ m: ModeRef) { modes.removeAll { $0 == m || $0.sameShape(as: m) } }

    package func sanitized() -> KeptModes {
        let valid = modes.filter { m in
            (1...32768).contains(m.pixelWidth) && (1...32768).contains(m.pixelHeight)
                && (1...16384).contains(m.pointWidth) && (1...16384).contains(m.pointHeight)
                && (0...1_000_000).contains(m.refreshMilliHz)
        }
        return KeptModes(modes: Array(valid.suffix(Self.maxModes)))
    }
}

/// Decodes one array element, or nil, without failing the array.
private struct LossyModeRef: Decodable {
    let value: ModeRef?
    init(from decoder: Decoder) throws { value = try? ModeRef(from: decoder) }
}

package struct SafetyConfig: ConfigModel {
    package static let confirmSecondsRange = 10...60
    package static let defaultConfirmSeconds = 15

    package var confirmResolution: ConfirmResolutionChanges
    /// Countdown on the confirm panel.
    package var confirmSeconds: Int
    /// ⌃⌥⌘⎋ (fallback ⌃⌥⌘⇧⎋). Can't be turned off while Snaptic holds a long-armed state.
    package var panicHotkeyEnabled: Bool
    /// A custom panic shortcut; nil = the default.
    package var panicHotkey: HotkeyCombo?
    /// Show a notice when a journal was replayed at launch.
    package var announceRecovery: Bool
    /// "Allow without asking" for preConfirm DDC writes, per display. Protected: never
    /// exported, never touched by the CLI.
    package var preConfirmAllowed: LossyMap<DisplayKey, PreConfirmAllowList>
    /// Modes the user kept, per display.
    package var keptModes: LossyMap<DisplayKey, KeptModes>

    package init() {
        confirmResolution = .newModesOnly
        confirmSeconds = Self.defaultConfirmSeconds
        panicHotkeyEnabled = true
        panicHotkey = nil
        announceRecovery = true
        preConfirmAllowed = LossyMap()
        keptModes = LossyMap()
    }

    private enum CodingKeys: String, CodingKey {
        case confirmResolution, confirmSeconds, panicHotkeyEnabled, panicHotkey, announceRecovery, preConfirmAllowed, keptModes
    }

    package init(from decoder: Decoder) throws {
        let d = SafetyConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        confirmResolution = c.lossy(.confirmResolution, d.confirmResolution)
        confirmSeconds = c.lossy(.confirmSeconds, d.confirmSeconds)
        panicHotkeyEnabled = c.lossy(.panicHotkeyEnabled, d.panicHotkeyEnabled)
        panicHotkey = (try? c.decodeIfPresent(HotkeyCombo.self, forKey: .panicHotkey)) ?? nil
        announceRecovery = c.lossy(.announceRecovery, d.announceRecovery)
        preConfirmAllowed = c.lossy(.preConfirmAllowed, d.preConfirmAllowed)
        keptModes = c.lossy(.keptModes, d.keptModes)
    }

    package func sanitized() -> SafetyConfig {
        var c = self
        c.confirmSeconds = min(max(confirmSeconds, Self.confirmSecondsRange.lowerBound), Self.confirmSecondsRange.upperBound)
        if let hk = panicHotkey, hk.keyCode >= 128 || hk.carbonModifiers & 0x1B00 == 0 { c.panicHotkey = nil }
        c.preConfirmAllowed.dropUnknown(keepingAtMost: 0)
        c.preConfirmAllowed = LossyMap(c.preConfirmAllowed.values.mapValues { $0.sanitized() }.filter { !$0.value.entries.isEmpty })
        c.keptModes.dropUnknown(keepingAtMost: 0)
        c.keptModes = LossyMap(c.keptModes.values.mapValues { $0.sanitized() }.filter { !$0.value.modes.isEmpty })
        return c
    }

    /// The copy Backup exports: protected fields removed (PLAN §3.4).
    package func strippedForExport() -> SafetyConfig {
        var c = self
        c.preConfirmAllowed = LossyMap()
        return c
    }

    /// Default panic shortcuts: ⌃⌥⌘⎋, then ⌃⌥⌘⇧⎋ if the first is taken.
    package static let defaultPanicHotkey = HotkeyCombo(keyCode: 53, carbonModifiers: 0x1000 | 0x0800 | 0x0100)
    package static let fallbackPanicHotkey = HotkeyCombo(keyCode: 53, carbonModifiers: 0x1000 | 0x0800 | 0x0100 | 0x0200)

    /// Shortcuts to try, in order.
    package var panicHotkeyCandidates: [HotkeyCombo] {
        var list: [HotkeyCombo] = []
        if let custom = panicHotkey { list.append(custom) }
        for d in [Self.defaultPanicHotkey, Self.fallbackPanicHotkey] where !list.contains(d) { list.append(d) }
        return list
    }
}
