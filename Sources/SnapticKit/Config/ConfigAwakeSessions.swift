import Foundation

// Sessions settings (owner: G; PLAN 0.3 §2.6 "System behavior", §2.14, consistency M2, R5-3, R5-11): presets, the
// default session and options, system behavior and recent apps.

package enum AwakePresetKind: Equatable, Sendable {
    case indefinite, duration(seconds: Int), untilTime(hour: Int, minute: Int)
    /// "At most" pop-up in the editor.
    case untilIdle(UntilIdleSpec, maxSeconds: Int?)
}

private enum PresetKindKey: String, CodingKey { case type, seconds, hour, minute, spec, maxSeconds }

extension AwakePresetKind: Codable {
    /// Type-tagged: {"type":"duration","seconds":3600}, {"type":"untilTime","hour":17,"minute":0},
    /// {"type":"untilIdle","spec":{…},"maxSeconds":7200}. An unknown type throws (the preset is dropped).
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PresetKindKey.self)
        switch try c.decode(String.self, forKey: .type) {
        case "indefinite":
            self = .indefinite
        case "duration":
            self = .duration(seconds: try c.decode(Int.self, forKey: .seconds))
        case "untilTime":
            self = .untilTime(hour: try c.decode(Int.self, forKey: .hour), minute: try c.decode(Int.self, forKey: .minute))
        case "untilIdle":
            self = .untilIdle(c.lossy(.spec, UntilIdleSpec()), maxSeconds: c.lossy(.maxSeconds, nil))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown preset kind")
        }
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PresetKindKey.self)
        switch self {
        case .indefinite:
            try c.encode("indefinite", forKey: .type)
        case .duration(let seconds):
            try c.encode("duration", forKey: .type)
            try c.encode(seconds, forKey: .seconds)
        case .untilTime(let hour, let minute):
            try c.encode("untilTime", forKey: .type)
            try c.encode(hour, forKey: .hour)
            try c.encode(minute, forKey: .minute)
        case .untilIdle(let spec, let maxSeconds):
            try c.encode("untilIdle", forKey: .type)
            try c.encode(spec, forKey: .spec)
            try c.encodeIfPresent(maxSeconds, forKey: .maxSeconds)
        }
    }
}

extension AwakePresetKind {
    /// In range: durations and caps 60 s ... 30 days, hour 0...23, minute 0...59, the idle spec clamped.
    package func sanitized() -> AwakePresetKind {
        switch self {
        case .indefinite:
            return .indefinite
        case .duration(let s):
            return .duration(seconds: AwakeMath.clamp(s, AwakeClock.durationRange))
        case .untilTime(let h, let m):
            return .untilTime(hour: AwakeMath.clamp(h, 0...23), minute: AwakeMath.clamp(m, 0...59))
        case .untilIdle(let spec, let cap):
            return .untilIdle(spec.sanitized(), maxSeconds: cap.map { AwakeMath.clamp($0, AwakeClock.durationRange) })
        }
    }

    /// The session kind this preset starts. `untilTime` needs the next matching wall instant, which the app
    /// resolves with Calendar (DST-correct); nil without it.
    package func sessionKind(untilUnixTime: Double?) -> AwakeSessionKind? {
        switch sanitized() {
        case .indefinite: return .indefinite
        case .duration(let s): return .duration(seconds: s)
        case .untilTime: return untilUnixTime.flatMap { $0.isFinite ? .until(unixTime: $0) : nil }
        case .untilIdle(let spec, let cap): return .untilIdle(spec, maxSeconds: cap)
        }
    }

    /// "Until Turned Off", "For 1 Hour", "Until 5:00 PM", "Until Downloads and Tasks Finish".
    package func title(_ text: AwakeTextContext) -> String {
        switch sanitized() {
        case .indefinite: return L("Until Turned Off")
        case .duration(let s): return L("For ") + Self.spanTitle(s)
        case .untilTime(let h, let m): return L("Until ") + AwakeCountdown.clock(hour: h, minute: m, uses24Hour: text.uses24Hour)
        case .untilIdle: return L("Until Downloads and Tasks Finish")
        }
    }

    /// "1 Hour", "30 Minutes", "1 Hour 30 Minutes", "2 Days" (title case, rounded up to the minute).
    package static func spanTitle(_ seconds: Int) -> String {
        let minutes = max(1, (AwakeMath.clamp(seconds, 0...AwakeClock.maxSessionSeconds) + 59) / 60)
        if minutes % 1_440 == 0 { return AwakeCountdown.unit(minutes / 1_440, L("Day"), L("Days")) }
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return AwakeCountdown.unit(m, L("Minute"), L("Minutes")) }
        if m == 0 { return AwakeCountdown.unit(h, L("Hour"), L("Hours")) }
        return AwakeCountdown.unit(h, L("Hour"), L("Hours")) + " " + AwakeCountdown.unit(m, L("Minute"), L("Minutes"))
    }
}

package struct AwakePreset: Codable, Equatable, Sendable, Identifiable {
    package var id: StableID
    /// nil = generated ("For 1 Hour", "Until 5:00 PM", "Until Turned Off").
    package var name: String?
    package var kind: AwakePresetKind
    /// nil = "Use default".
    package var options: AwakeSessionOptions?

    package init(id: StableID, name: String?, kind: AwakePresetKind, options: AwakeSessionOptions?) {
        self.id = id
        self.name = name
        self.kind = kind
        self.options = options
    }

    private enum CodingKeys: String, CodingKey { case id, name, kind, options }

    /// Hand-written (N18): id and kind required, the rest lossy.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(StableID.self, forKey: .id)
        kind = try c.decode(AwakePresetKind.self, forKey: .kind)
        name = c.lossy(.name, nil)
        options = c.lossy(.options, nil)
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(options, forKey: .options)
    }

    package static let maxNameScalars = 64

    /// Name cleaned (empty → nil, generated), kind and options clamped.
    package func sanitized() -> AwakePreset {
        var p = self
        let cleaned = name.map { TextSanitizer.clean($0, maxScalars: Self.maxNameScalars).trimmingCharacters(in: .whitespaces) }
        p.name = (cleaned?.isEmpty ?? true) ? nil : cleaned
        p.kind = kind.sanitized()
        p.options = options?.sanitized()
        return p
    }

    /// The list title (non-verb): the user's name or the generated one ("For 1 Hour").
    package func title(_ text: AwakeTextContext) -> String {
        if let n = sanitized().name { return n }
        return kind.title(text)
    }

    /// Menu title as a verb phrase for the first-level item: "Keep Awake Until Turned Off", "Keep Awake for 1 Hour",
    /// "Keep Awake Until 5:00 PM", "Keep Awake Until Downloads and Tasks Finish"; a named preset reads
    /// "Keep Awake: <name>".
    package func verbTitle(_ text: AwakeTextContext) -> String {
        if let n = sanitized().name { return L("Keep Awake: ") + n }
        switch kind.sanitized() {
        case .duration(let s): return L("Keep Awake for ") + AwakePresetKind.spanTitle(s)
        case .indefinite, .untilTime, .untilIdle: return L("Keep Awake ") + kind.title(text)
        }
    }
}

package enum UserSwitchEnd: String, Codable, CaseIterable, Sendable { case immediately, afterHour, never }

package struct AwakeBehavior: Codable, Equatable, Sendable {
    /// The "End when locked for" choices; nil = Never.
    package static let lockedHoursChoices = [1, 4, 12]

    package var endOnSystemSleep: Bool
    /// .afterHour: off console > 1 h ends `.userSwitch`.
    package var userSwitchEnd: UserSwitchEnd
    /// nil = Never; 1, 4, 12.
    package var endAfterLockedHours: Int?
    /// C1.
    package var keepDisplayOnWhileLocked: Bool
    package var resumeAfterRestart: Bool
    package var startAtLaunch: StableID?

    package init() {
        endOnSystemSleep = false
        userSwitchEnd = .afterHour
        endAfterLockedHours = nil
        keepDisplayOnWhileLocked = false
        resumeAfterRestart = true
        startAtLaunch = nil
    }

    private enum CodingKeys: String, CodingKey {
        case endOnSystemSleep, userSwitchEnd, endAfterLockedHours, keepDisplayOnWhileLocked, resumeAfterRestart,
             startAtLaunch
    }

    /// Lossy per field (rule 9).
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AwakeBehavior()
        endOnSystemSleep = c.lossy(.endOnSystemSleep, d.endOnSystemSleep)
        userSwitchEnd = c.lossy(.userSwitchEnd, d.userSwitchEnd)
        endAfterLockedHours = c.lossy(.endAfterLockedHours, nil)
        keepDisplayOnWhileLocked = c.lossy(.keepDisplayOnWhileLocked, d.keepDisplayOnWhileLocked)
        resumeAfterRestart = c.lossy(.resumeAfterRestart, d.resumeAfterRestart)
        startAtLaunch = c.lossy(.startAtLaunch, nil)
    }

    /// `endAfterLockedHours` snaps up to the next choice (1, 4, 12; above 12 → 12; ≤ 0 → Never).
    package func sanitized() -> AwakeBehavior {
        var b = self
        if let h = endAfterLockedHours {
            b.endAfterLockedHours = h <= 0 ? nil : (Self.lockedHoursChoices.first { $0 >= h } ?? 12)
        }
        return b
    }
}

package struct AwakeSessionsConfig: ConfigModel {
    package static let maxPresets = 12
    package static let maxRecentApps = 5
    package static let defaultNamespace = "awake.preset.default"
    /// The six defaults in R5-11 order, by derived-id name.
    package static let defaultPresetNames = ["indefinite", "30m", "1h", "2h", "5h", "idle"]

    /// ≤ 12, lossyUniqueArray (R5-3). Defaults (R5-11 order): Until Turned Off, 30 min, 1 h, 2 h, 5 h, Until
    /// Downloads and Tasks Finish, with ids derived from `defaultNamespace`.
    package var presets: [AwakePreset]
    /// nil or unknown → Until Turned Off (C10); UI "Default session".
    package var defaultPresetID: StableID?
    /// Used when a preset has nil options.
    package var defaultOptions: AwakeSessionOptions
    package var lastCustomSeconds: Int
    package var behavior: AwakeBehavior
    /// ≤ 5 bundle ids; local only, never exported.
    package var recentApps: [String]

    package init() {
        presets = Self.defaultPresets
        defaultPresetID = nil
        defaultOptions = AwakeSessionOptions()
        lastCustomSeconds = 5_400
        behavior = AwakeBehavior()
        recentApps = []
    }

    /// The id of a default preset ("indefinite", "30m", "1h", "2h", "5h", "idle"); the same on every run.
    package static func derivedPresetID(_ name: String) -> StableID {
        StableID.derived(namespace: defaultNamespace, name: name)
    }

    package static var defaultPresets: [AwakePreset] {
        let kinds: [AwakePresetKind] = [.indefinite, .duration(seconds: 1_800), .duration(seconds: 3_600),
                                        .duration(seconds: 7_200), .duration(seconds: 18_000),
                                        .untilIdle(UntilIdleSpec(), maxSeconds: nil)]
        return zip(defaultPresetNames, kinds).map { AwakePreset(id: derivedPresetID($0.0), name: nil, kind: $0.1, options: nil) }
    }

    private enum CodingKeys: String, CodingKey {
        case presets, defaultPresetID, defaultOptions, lastCustomSeconds, behavior, recentApps
    }

    /// R5-3: lossy per field; presets lossyUniqueArray, recentApps lossyArray + uniqued.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AwakeSessionsConfig()
        presets = c.lossyUniqueArray(.presets, d.presets)
        defaultPresetID = c.lossy(.defaultPresetID, nil)
        defaultOptions = c.lossy(.defaultOptions, d.defaultOptions)
        lastCustomSeconds = c.lossy(.lastCustomSeconds, d.lastCustomSeconds)
        behavior = c.lossy(.behavior, d.behavior)
        recentApps = c.lossyArray(.recentApps, d.recentApps).uniqued()
    }

    /// Presets de-duplicated, sanitized and capped at 12; the default preset and start-at-launch must name a preset
    /// (else nil); options and behavior clamped; recent apps valid, unique and ≤ 5.
    package func sanitized() -> AwakeSessionsConfig {
        var c = self
        c.presets = Array(presets.uniquedByID().prefix(Self.maxPresets)).map { $0.sanitized() }
        let ids = Set(c.presets.map(\.id))
        if let d = defaultPresetID, !ids.contains(d) { c.defaultPresetID = nil }
        c.defaultOptions = defaultOptions.sanitized()
        c.lastCustomSeconds = AwakeMath.clamp(lastCustomSeconds, AwakeClock.durationRange)
        c.behavior = behavior.sanitized()
        if let s = c.behavior.startAtLaunch, !ids.contains(s) { c.behavior.startAtLaunch = nil }
        c.recentApps = Array(recentApps.filter(AwakeBundleID.isValid).uniqued().prefix(Self.maxRecentApps))
        return c
    }

    /// The default session: `defaultPresetID`'s preset, else the first Until Turned Off preset, else a built-in one.
    package var defaultPreset: AwakePreset {
        if let id = defaultPresetID, let p = presets.first(where: { $0.id == id }) { return p }
        if let p = presets.first(where: { $0.kind == .indefinite }) { return p }
        return AwakePreset(id: Self.derivedPresetID("indefinite"), name: nil, kind: .indefinite, options: nil)
    }

    package func preset(_ id: StableID) -> AwakePreset? { presets.first { $0.id == id } }

    /// A recent app moves to the front (≤ 5, valid bundle ids only).
    package func notingRecentApp(_ bundleID: String) -> AwakeSessionsConfig {
        guard AwakeBundleID.isValid(bundleID) else { return self }
        var c = self
        c.recentApps = Array(([bundleID] + recentApps.filter { $0 != bundleID }).prefix(Self.maxRecentApps))
        return c
    }

    /// preset.options ?? defaultOptions, for every kind (R5-11: no per-kind maySleep default). Then activity is
    /// clamped to what is effective: anything → `.off` unless activity is effective, `.nudge` → `.declare` unless
    /// pointerNudge is effective (consistency M2).
    package func effectiveOptions(for kind: AwakeSessionKind, preset: AwakePreset?,
                                  effective: Set<AwakeFeature>) -> AwakeSessionOptions {
        var o = (preset?.options ?? defaultOptions).sanitized()
        if !effective.contains(.activity) {
            o.activity = .off
        } else if o.activity == .nudge && !effective.contains(.pointerNudge) {
            o.activity = .declare
        }
        return o
    }

    /// Presets and the default options without pointer movement (restore, export and import).
    package func withoutNudge() -> AwakeSessionsConfig {
        var c = self
        c.defaultOptions = defaultOptions.withoutNudge()
        c.presets = presets.map { p -> AwakePreset in
            var p = p
            p.options = p.options?.withoutNudge()
            return p
        }
        return c
    }

    /// Backup import (security S-2): pointer movement is removed only from what came from the file. Default options
    /// or a preset equal to this Mac's (same id), either as stored or as this Mac would export it, are this Mac's own
    /// and keep their value; anything else loses `nudge`. A kept value is exactly the current one, so a file can't
    /// turn pointer movement on.
    package func importing(over current: AwakeSessionsConfig) -> AwakeSessionsConfig {
        var c = withoutNudge()
        if defaultOptions == current.defaultOptions || defaultOptions == current.defaultOptions.withoutNudge() {
            c.defaultOptions = current.defaultOptions
        }
        var own: [StableID: AwakePreset] = [:]
        for p in current.presets where own[p.id] == nil { own[p.id] = p }
        c.presets = presets.map { p -> AwakePreset in
            if let mine = own[p.id] {
                var exported = mine
                exported.options = mine.options?.withoutNudge()
                if mine == p || exported == p { return mine }
            }
            var stripped = p
            stripped.options = p.options?.withoutNudge()
            return stripped
        }
        return c
    }

    /// The "Default (…)" label; R5-11: `defaultOptions.display` for every kind.
    package func defaultDisplayPolicy(for kind: AwakePresetKind) -> AwakeDisplayPolicy { defaultOptions.display }
}

extension AwakeConfig {
    /// Awake › Advanced "Appear active" (consistency M2): on sets `features.activity` and `defaultOptions.activity =
    /// .declare`; off sets both off. Presets with explicit options keep theirs (effectiveOptions clamps them).
    package func settingAppearActive(_ on: Bool) -> AwakeConfig {
        var c = self
        c.features[.activity] = on
        c.sessions.defaultOptions.activity = on ? .declare : .off
        if !on { c.features[.pointerNudge] = false }
        return c
    }

    /// "Move the pointer slightly": on sets `features.pointerNudge` and `defaultOptions.activity = .nudge`; off sets
    /// pointerNudge off and `defaultOptions.activity = .declare`.
    package func settingPointerNudge(_ on: Bool) -> AwakeConfig {
        var c = self
        c.features[.pointerNudge] = on
        c.sessions.defaultOptions.activity = on ? .nudge : .declare
        return c
    }

    /// "Keep the display on" (R5-11: applies to every session that uses default options).
    package func settingKeepDisplayOn(_ on: Bool) -> AwakeConfig {
        var c = self
        c.sessions.defaultOptions.display = on ? .keepOn : .maySleep
        return c
    }
}

// MARK: - Sessions sheet editing (§4.3 "Sessions sheet")

/// The kind pop-up of the Sessions sheet.
package enum AwakePresetKindChoice: String, CaseIterable, Sendable { case indefinite, duration, untilTime, untilIdle }

extension AwakePresetKind {
    package var choice: AwakePresetKindChoice {
        switch self {
        case .indefinite: return .indefinite
        case .duration: return .duration
        case .untilTime: return .untilTime
        case .untilIdle: return .untilIdle
        }
    }

    /// The kind after the pop-up changed: the same kind keeps its values; a duration and an "At most" cap carry over
    /// into each other (a length becomes the next "At most" choice, 1–12 hours); anything else starts from 1 hour,
    /// 5:00 PM or the default thresholds.
    package func switched(to choice: AwakePresetKindChoice) -> AwakePresetKind {
        guard choice != self.choice else { return self }
        switch choice {
        case .indefinite:
            return .indefinite
        case .duration:
            if case .untilIdle(_, let cap?) = self { return AwakePresetKind.duration(seconds: cap).sanitized() }
            return .duration(seconds: 3_600)
        case .untilTime:
            return .untilTime(hour: 17, minute: 0)
        case .untilIdle:
            if case .duration(let s) = self {
                let hours = (max(0, s) + 3_599) / 3_600
                let cap = (Self.atMostHours.first { $0 >= hours } ?? 12) * 3_600
                return .untilIdle(UntilIdleSpec(), maxSeconds: cap)
            }
            return .untilIdle(UntilIdleSpec(), maxSeconds: nil)
        }
    }

    /// The "At most" choices of task kinds (No limit, 1, 2, 4, 8, 12 hours; parity minor 6).
    package static let atMostHours = [1, 2, 4, 8, 12]
}

extension AwakeSessionsConfig {
    /// A new session for the + button: 1 hour with default options, or nil at the 12-session limit.
    package func addingPreset(id: StableID) -> AwakeSessionsConfig? {
        guard presets.count < Self.maxPresets, !presets.contains(where: { $0.id == id }) else { return nil }
        var c = self
        c.presets.append(AwakePreset(id: id, name: nil, kind: .duration(seconds: 3_600), options: nil))
        return c
    }

    /// Without the session `id`; the last session is never removed. The default session and the session started at
    /// launch fall back to their defaults when they named it.
    package func removingPreset(_ id: StableID) -> AwakeSessionsConfig {
        guard presets.count > 1, presets.contains(where: { $0.id == id }) else { return self }
        var c = self
        c.presets.removeAll { $0.id == id }
        if c.defaultPresetID == id { c.defaultPresetID = nil }
        if c.behavior.startAtLaunch == id { c.behavior.startAtLaunch = nil }
        return c
    }

    /// The six default sessions again (Sessions sheet › Restore Default Sessions…): presets and the default session
    /// only; the session started at launch is kept when it still exists.
    package func restoringDefaultPresets() -> AwakeSessionsConfig {
        var c = self
        c.presets = Self.defaultPresets
        c.defaultPresetID = nil
        if let s = c.behavior.startAtLaunch, !c.presets.contains(where: { $0.id == s }) { c.behavior.startAtLaunch = nil }
        return c
    }
}
