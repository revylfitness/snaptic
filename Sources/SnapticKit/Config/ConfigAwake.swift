import Foundation

// Composition of the Awake settings (lead shell; 0.3 §2.14). Each section type lives in its owning team's file
// (G: sessions, guards, triggers, indicator; J: activity, drives). Key SnapticAwakeV1. `restoringDefaults`,
// `exportable` and `importable` hold G's rules (code M14).

package struct AwakeConfig: ConfigModel {
    package static let key = "SnapticAwakeV1"

    package var features: LossyMap<AwakeFeature, Bool>
    package var sessions: AwakeSessionsConfig
    package var guards: AwakeGuardsConfig
    package var triggers: AwakeTriggersConfig
    package var activity: AwakeActivityConfig
    package var drives: DriveAliveConfig
    /// Edited on the Menu Bar page.
    package var indicator: AwakeIndicatorConfig
    package var shortcuts: LossyMap<AwakeActionID, HotkeyCombo>

    package init() {
        features = LossyMap()
        sessions = AwakeSessionsConfig()
        guards = AwakeGuardsConfig()
        triggers = AwakeTriggersConfig()
        activity = AwakeActivityConfig()
        drives = DriveAliveConfig()
        indicator = AwakeIndicatorConfig()
        shortcuts = LossyMap()
    }

    private enum CodingKeys: String, CodingKey {
        case features, sessions, guards, triggers, activity, drives, indicator, shortcuts
    }

    /// Field by field: a bad section falls back to its defaults without touching the others.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        features = c.lossy(.features, LossyMap())
        sessions = c.lossy(.sessions, AwakeSessionsConfig())
        guards = c.lossy(.guards, AwakeGuardsConfig())
        triggers = c.lossy(.triggers, AwakeTriggersConfig())
        activity = c.lossy(.activity, AwakeActivityConfig())
        drives = c.lossy(.drives, DriveAliveConfig())
        indicator = c.lossy(.indicator, AwakeIndicatorConfig())
        shortcuts = c.lossy(.shortcuts, LossyMap())
    }

    package func sanitized() -> AwakeConfig {
        var c = self
        c.sessions = sessions.sanitized()
        c.guards = guards.sanitized()
        c.triggers = triggers.sanitized()
        c.activity = activity.sanitized()
        c.drives = drives.sanitized()
        c.indicator = indicator.sanitized()
        c.shortcuts.dropUnknown(keepingAtMost: 0)
        return c
    }

    /// Raw feature choices as a plain dictionary (for AwakeFeatureGraph).
    package var rawFeatures: [AwakeFeature: Bool] { features.values }

    /// Page Restore Defaults (G, §4.6, r1 security L6): features, sessions (the default presets with their derived
    /// ids, default options, behavior), guards, activity and Drive Alive back to defaults, so pointer movement is off
    /// and no volume is kept awake. Kept: the rules (user content; every `nudge` → `declare`, as always), the indicator
    /// (the Menu Bar page's scope), the shortcuts (the Keyboard Shortcuts sheet's scope) and the recent apps. The
    /// kept rules keep running: `features.triggers` (opt-in) is kept with them (review parity P1). For the same reason
    /// `keepingLidClosed` (lid-closed mode on or pending, `AwakeLidMode.locksOptIn`, read at the click) keeps
    /// `features.lidClosed`: clearing it would end the mode without a word (0.3.3 r2 P2-1). The caller says so
    /// (`AwakeLidText.restoreNotice`).
    package func restoringDefaults(keepingLidClosed: Bool = false) -> AwakeConfig {
        var c = AwakeConfig()
        c.features[.triggers] = features[.triggers]
        if keepingLidClosed { c.features[.lidClosed] = features[.lidClosed] }
        c.triggers = triggers.withoutNudge().sanitized()
        c.indicator = indicator.sanitized()
        c.shortcuts = shortcuts
        c.sessions.recentApps = sessions.sanitized().recentApps
        return c.sanitized()
    }

    /// Backup export (G, security M7): nudge → declare everywhere, without `drives`, `features.pointerNudge`,
    /// `features.lidClosed` (0.3.1 B5), `sessions.recentApps` and `sessions.behavior.startAtLaunch`; rules only with
    /// `includeTriggers`, and then without salted hashes (a rule that lost a condition is disabled).
    package func exportable(includeTriggers: Bool) -> AwakeConfig {
        var c = sanitized().strippedForBackup()
        c.triggers = includeTriggers ? c.triggers.strippingHashes() : AwakeTriggersConfig()
        return c.sanitized()
    }

    /// Backup import (G, security M7/L5/L7), applied by KitBackup after its generic merge: the same stripping as
    /// export; guards may only become stricter than `current`; `features.pointerNudge`, `features.lidClosed`
    /// (0.3.1 B5), `drives`, the recent apps and start-at-launch are kept from `current`, so a backup can't turn
    /// pointer movement or lid-closed mode on, pick volumes or start a session at launch. The stripping applies to what came from the file: a rule, preset or default
    /// options the merge left as this Mac has them (or as this Mac exports them) keep this Mac's value, salted
    /// hashes and pointer movement included (review security S-2); nothing the Mac didn't already have gets through.
    package func importable(current: AwakeConfig) -> AwakeConfig {
        let merged = sanitized()
        let now = current.sanitized()
        var c = merged.strippedForBackup()
        let stripped = c.triggers.strippingHashes().triggers
        c.triggers.triggers = zip(merged.triggers.triggers, stripped).map { incoming, safe in
            now.triggers.triggers.first { $0.id == incoming.id && Self.isOwn(incoming, of: $0) } ?? safe
        }
        c.sessions.presets = zip(merged.sessions.presets, c.sessions.presets).map { incoming, safe in
            now.sessions.presets.first { $0.id == incoming.id && Self.isOwn(incoming, of: $0) } ?? safe
        }
        if Self.isOwn(merged.sessions.defaultOptions, of: now.sessions.defaultOptions) {
            c.sessions.defaultOptions = now.sessions.defaultOptions
        }
        c.guards = c.guards.monotonic(over: now.guards)
        c.features[.pointerNudge] = now.features[.pointerNudge]
        c.features[.lidClosed] = now.features[.lidClosed]
        c.drives = now.drives
        c.sessions.recentApps = now.sessions.recentApps
        c.sessions.behavior.startAtLaunch = now.sessions.behavior.startAtLaunch
        return c.sanitized()
    }

    /// `incoming` is this Mac's rule as it is or as `exportable` writes it.
    private static func isOwn(_ incoming: AwakeTrigger, of own: AwakeTrigger) -> Bool {
        if incoming == own { return true }
        var one = AwakeTriggersConfig()
        one.triggers = [own]
        return one.withoutNudge().strippingHashes().sanitized().triggers.first == incoming
    }

    private static func isOwn(_ incoming: AwakePreset, of own: AwakePreset) -> Bool {
        var exported = own
        exported.options = own.options?.withoutNudge()
        return incoming == own || incoming == exported
    }

    private static func isOwn(_ incoming: AwakeSessionOptions, of own: AwakeSessionOptions) -> Bool {
        incoming == own || incoming == own.withoutNudge()
    }

    /// The fields no backup carries, and no pointer movement or lid-closed mode.
    private func strippedForBackup() -> AwakeConfig {
        var c = self
        c.features[.pointerNudge] = nil
        c.features[.lidClosed] = nil
        c.drives = DriveAliveConfig()
        c.sessions = sessions.withoutNudge()
        c.sessions.recentApps = []
        c.sessions.behavior.startAtLaunch = nil
        c.triggers = triggers.withoutNudge()
        return c
    }
}
