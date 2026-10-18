import Foundation

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §2.6, §2.14 + R5-3, R5-11 (kind S): the
// declared lossy decoders are real; presets, defaults and options logic are G's (step 1).

package enum AwakePresetKind: Equatable, Sendable {
    case indefinite, duration(seconds: Int), untilTime(hour: Int, minute: Int)
    /// "At most" pop-up in the editor.
    case untilIdle(UntilIdleSpec, maxSeconds: Int?)
}

private enum StubTypeKey: String, CodingKey { case type }

extension AwakePresetKind: Codable {
    /// Hand-written, type-tagged (G). Stub: throws, so the preset is dropped.
    package init(from decoder: Decoder) throws { throw StubError.notBuilt }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: StubTypeKey.self)
        try c.encode("notBuilt", forKey: .type)
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

    /// Menu title as a verb phrase ("Keep Awake for 1 Hour"). Stub: "Keep Awake".
    package func verbTitle(_ text: AwakeTextContext) -> String { L("Keep Awake") }
}

package enum UserSwitchEnd: String, Codable, CaseIterable, Sendable { case immediately, afterHour, never }

package struct AwakeBehavior: Codable, Equatable, Sendable {
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
}

package struct AwakeSessionsConfig: ConfigModel {
    /// ≤ 12, lossyUniqueArray (R5-3). G fills the six defaults (R5-11 order) in step 1. Stub: none.
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
        presets = []
        defaultPresetID = nil
        defaultOptions = AwakeSessionOptions()
        lastCustomSeconds = 5_400
        behavior = AwakeBehavior()
        recentApps = []
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

    package func sanitized() -> AwakeSessionsConfig {
        var c = self
        c.presets = Array(presets.uniquedByID().prefix(12))
        c.recentApps = Array(recentApps.uniqued().prefix(5))
        return c
    }

    /// preset.options ?? defaultOptions, clamped to the effective features. Stub: defaults with activity off.
    package func effectiveOptions(for kind: AwakeSessionKind, preset: AwakePreset?,
                                  effective: Set<AwakeFeature>) -> AwakeSessionOptions {
        var o = defaultOptions
        o.activity = .off
        return o
    }

    /// The "Default (…)" label; R5-11: `defaultOptions.display` for every kind.
    package func defaultDisplayPolicy(for kind: AwakePresetKind) -> AwakeDisplayPolicy { defaultOptions.display }
}
