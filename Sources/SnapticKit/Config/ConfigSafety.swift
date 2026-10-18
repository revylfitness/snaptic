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
    /// "Revert after" (0.3 §4.3: StepperSetting 5–60; 0.2 allowed 10–60). The guard never needs a longer panel:
    /// its deadline is always the panel plus a fixed margin (`GuardProtocol.trialDeadline`, `panelExtension`), so a
    /// shorter countdown only reverts sooner, never later. A 0.2 build reading 5 clamps it up to 10 (safer).
    package static let confirmSecondsRange = 5...60
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

// MARK: - Restore All Displays shortcut (0.3 §4.6 M6, consistency M5)

/// What the one "Restore All Displays" shortcut row edits. **No data migration**: the row reads and writes the two
/// 0.2 fields with their 0.2 meanings, so a 0.3 → 0.2 → 0.3 round trip keeps the user's choice.
/// - `standard`: `panicHotkeyEnabled == true`, `panicHotkey == nil` → ⌃⌥⌘⎋, then ⌃⌥⌘⇧⎋ if that is taken.
/// - `custom`: `panicHotkeyEnabled == true`, `panicHotkey` set → that combo first, then the default and fallback.
/// - `off`: `panicHotkeyEnabled == false` → no shortcut at all (except while Snaptic holds a long-armed state).
package enum PanicShortcutState: Equatable, Sendable {
    case standard
    case custom(HotkeyCombo)
    case off
}

extension SafetyConfig {
    package var panicShortcutState: PanicShortcutState {
        guard panicHotkeyEnabled else { return .off }
        if let custom = panicHotkey, custom != Self.defaultPanicHotkey { return .custom(custom) }
        return .standard
    }

    /// What the shortcut recorder shows: the custom combo, the default one, or nothing when off.
    package var panicShortcutShown: HotkeyCombo? {
        switch panicShortcutState {
        case .standard: return Self.defaultPanicHotkey
        case .custom(let combo): return combo
        case .off: return nil
        }
    }

    /// The recorder wrote `combo`: a recorded combo turns the shortcut on (the default combo is stored as nil, so
    /// it keeps its fallback); Clear (`nil`) sets `panicHotkeyEnabled = false` and leaves `panicHotkey` as it was,
    /// exactly the 0.2 switch. A combo macOS can't register is ignored.
    package func settingPanicShortcut(_ combo: HotkeyCombo?) -> SafetyConfig {
        var c = self
        guard let combo else {
            c.panicHotkeyEnabled = false
            return c
        }
        let normalized = HotkeyRules.normalized(combo)
        guard HotkeyRules.problem(normalized) == nil, Self.isStorablePanicHotkey(normalized) else { return self }
        c.panicHotkeyEnabled = true
        c.panicHotkey = normalized == Self.defaultPanicHotkey ? nil : normalized
        return c
    }

    /// "Use Default": back to ⌃⌥⌘⎋ (with its fallback), on.
    package func usingDefaultPanicShortcut() -> SafetyConfig {
        var c = self
        c.panicHotkeyEnabled = true
        c.panicHotkey = nil
        return c
    }

    /// The combos to register, in order (the first one that registers wins); empty = no shortcut. While Snaptic
    /// holds a long-armed state (a display disconnected, mirrored to a virtual display, dimmed to black) the
    /// shortcut is registered whatever the setting says (PLAN 0.2 §4.7).
    package func panicHotkeys(longArmed: Bool) -> [HotkeyCombo] {
        guard panicHotkeyEnabled || longArmed else { return [] }
        return panicHotkeyCandidates
    }

    /// The rule `sanitized()` applies to a stored custom combo.
    package static func isStorablePanicHotkey(_ combo: HotkeyCombo) -> Bool {
        combo.keyCode < 128 && combo.carbonModifiers & 0x1B00 != 0
    }
}

// MARK: - Allowed without asking (one list, 0.3 §4.4 duplicate 2)

extension PreConfirmAllowList {
    /// "Input source: HDMI 1", "Power mode: Standby" for one stored entry; nil for an entry that doesn't parse.
    package static func describe(_ entry: String) -> String? {
        guard isValidEntry(entry) else { return nil }
        let parts = entry.split(separator: ":")
        guard let vcp = UInt8(parts[0], radix: 16), let value = UInt16(parts[1], radix: 16) else { return nil }
        return VCPPolicy.name(vcp) + ": " + valueName(vcp: vcp, value: value)
    }

    /// The words for one value of a confirmed code.
    package static func valueName(vcp: UInt8, value: UInt16) -> String {
        switch vcp {
        case 0x60: return VCPPolicy.inputName(value)
        case 0xD6:
            switch value {
            case 1: return L("On")
            case 2: return L("Standby")
            case 3: return L("Suspend")
            case 4, 5: return L("Off")
            default: return String(value)
            }
        default: return String(value)
        }
    }

    /// Every entry described, in stored order, without unreadable ones.
    package var descriptions: [String] { entries.compactMap(Self.describe) }
}
