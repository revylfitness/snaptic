import Foundation

// Migration M1 (owner: G; PLAN 0.3 §4.6, N18, R5-12): 0.2 Displays sleep prevention → Awake rules "While a display is
// connected". Reads the raw 0.2 JSON (not DisplaysConfig, whose `sleepPrevention` case goes away in step 3), is pure
// and deterministic: the same JSON gives the same rule ids, so the host's replace-by-id writer is idempotent.

package struct AwakeMigrationResult: Equatable, Sendable {
    /// Empty when nothing to migrate.
    package var triggers: [AwakeTrigger]
    /// 0.2 sleep prevention was effective.
    package var enableModule: Bool
    /// ≤ 8, for the one-time toast; local UI only.
    package var migratedDisplayNames: [String]
    /// R5-12: bind to awake.pauseAutomatic.
    package var pauseRulesShortcut: HotkeyCombo?
    /// R5-12: a 0.2 combo existed and wasn't moved → Recent Notice.
    package var droppedShortcut: Bool

    package init(triggers: [AwakeTrigger], enableModule: Bool, migratedDisplayNames: [String],
                 pauseRulesShortcut: HotkeyCombo? = nil, droppedShortcut: Bool = false) {
        self.triggers = triggers
        self.enableModule = enableModule
        self.migratedDisplayNames = migratedDisplayNames
        self.pauseRulesShortcut = pauseRulesShortcut
        self.droppedShortcut = droppedShortcut
    }

    package static let nothing = AwakeMigrationResult(triggers: [], enableModule: false, migratedDisplayNames: [])
}

package enum AwakeMigration {
    /// Rule ids: StableID.derived(namespace: idNamespace, name: "<chunk index>:<sorted display keys joined by ,>").
    package static let idNamespace = "awake.m1"
    package static let displaysPerRule = 8
    /// The 0.2 "Toggle display sleep prevention" action whose combo moves to Pause Rules (R5-12).
    package static let legacyToggleAction = "d.sleepPreventionToggle"

    /// M1 over the raw 0.2 Displays JSON. Rules are created (disabled unless 0.2 sleep prevention was effective:
    /// Displays module on ∧ feature on ∧ ≥ 1 display flagged) for every flagged display with a fingerprint, at most
    /// 8 per rule; the 0.2 hotkey moves to `awake.pauseAutomatic` when a rule was produced and that action is unbound,
    /// otherwise it is dropped with a notice. Corrupt JSON or nothing to move gives `.nothing`.
    package static func fromDisplays(rawJSON: Data?, modulesEnabled: Set<ModuleID>,
                                     awakeShortcuts: LossyMap<AwakeActionID, HotkeyCombo>) -> AwakeMigrationResult {
        guard let data = rawJSON, !data.isEmpty, data.count <= 16 * 1_024 * 1_024,
              let raw = try? JSONDecoder().decode(RawDisplays.self, from: data) else { return .nothing }

        let flagged = raw.perDisplay
            .filter { DisplayKey(rawValue: $0.key) != nil && $0.value.preventSleep }
            .sorted { $0.key < $1.key }
        let movable = flagged.filter { !$0.value.fingerprint.isEmpty }
        let effective = modulesEnabled.contains(.displays) && raw.sleepPreventionOn && !flagged.isEmpty

        var triggers: [AwakeTrigger] = []
        var names: [String] = []
        var chunkStart = 0
        while chunkStart < movable.count {
            let chunk = Array(movable[chunkStart..<min(chunkStart + displaysPerRule, movable.count)])
            let index = triggers.count
            let keys = chunk.map { $0.key }.joined(separator: ",")
            let id = StableID.derived(namespace: idNamespace, name: "\(index):" + keys)
            let criteria = chunk.map { entry -> AwakeCriterionEntry in
                let name = entry.value.displayName
                if names.count < displaysPerRule { names.append(name) }
                return AwakeCriterionEntry(.display(.specific(record: entry.value.fingerprint, name: name)))
            }
            let title = index == 0 ? L("While a display is connected") : L("While a display is connected (\(index + 1))")
            var rule = AwakeTrigger(id: id, name: title, criteria: criteria)
            rule.match = .any
            rule.options = AwakeSessionOptions(display: .keepOn)
            rule.enabled = effective
            triggers.append(rule.sanitized())
            chunkStart += displaysPerRule
        }

        var pauseShortcut: HotkeyCombo?
        var dropped = false
        if let combo = raw.toggleShortcut {
            if !triggers.isEmpty && awakeShortcuts[.pauseAutomatic] == nil {
                pauseShortcut = combo
            } else {
                dropped = true
            }
        }
        let result = AwakeMigrationResult(triggers: triggers, enableModule: effective && !triggers.isEmpty,
                                          migratedDisplayNames: names, pauseRulesShortcut: pauseShortcut,
                                          droppedShortcut: dropped)
        return result == .nothing ? .nothing : result
    }
}

// MARK: Raw 0.2 shapes (decoded leniently: any part that doesn't decode counts as absent)

private struct RawKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private struct RawDisplays: Decodable {
    var sleepPreventionOn = false
    var perDisplay: [String: RawPerDisplay] = [:]
    var toggleShortcut: HotkeyCombo?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: RawKey.self)
        if let features = try? c.nestedContainer(keyedBy: RawKey.self, forKey: RawKey("features")) {
            sleepPreventionOn = ((try? features.decodeIfPresent(Bool.self, forKey: RawKey("sleepPrevention"))) ?? nil) ?? false
        }
        if let displays = try? c.nestedContainer(keyedBy: RawKey.self, forKey: RawKey("perDisplay")) {
            for key in displays.allKeys.sorted(by: { $0.stringValue < $1.stringValue }).prefix(256) {
                if let entry = try? displays.decode(RawPerDisplay.self, forKey: key) { perDisplay[key.stringValue] = entry }
            }
        }
        if let keys = try? c.nestedContainer(keyedBy: RawKey.self, forKey: RawKey("keys")),
           let shortcuts = try? keys.nestedContainer(keyedBy: RawKey.self, forKey: RawKey("shortcuts")) {
            toggleShortcut = (try? shortcuts.decodeIfPresent(HotkeyCombo.self,
                                                             forKey: RawKey(AwakeMigration.legacyToggleAction))) ?? nil
        }
    }
}

private struct RawPerDisplay: Decodable {
    var preventSleep = false
    var fingerprint = FingerprintRecord()
    var customName: String?
    var lastKnownName: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: RawKey.self)
        if let m = try? c.nestedContainer(keyedBy: RawKey.self, forKey: RawKey("management")) {
            preventSleep = ((try? m.decodeIfPresent(Bool.self, forKey: RawKey("preventSleep"))) ?? nil) ?? false
        }
        if let i = try? c.nestedContainer(keyedBy: RawKey.self, forKey: RawKey("identity")) {
            fingerprint = ((try? i.decodeIfPresent(FingerprintRecord.self, forKey: RawKey("fingerprint"))) ?? nil)
                ?? FingerprintRecord()
            customName = (try? i.decodeIfPresent(String.self, forKey: RawKey("customName"))) ?? nil
            lastKnownName = (try? i.decodeIfPresent(String.self, forKey: RawKey("lastKnownName"))) ?? nil
        }
    }

    /// Custom name, else the last name read from the display, else "Display"; cleaned to 64 scalars.
    var displayName: String {
        for candidate in [customName, lastKnownName] {
            if let n = candidate {
                let cleaned = TextSanitizer.clean(n, maxScalars: AwakeCriterion.maxNameScalars)
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return L("Display")
    }
}
