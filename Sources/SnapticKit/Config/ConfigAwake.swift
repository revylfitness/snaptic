import Foundation

// Composition of the Awake settings (lead shell; 0.3 §2.14). Each section type lives in its owning team's file
// (G: sessions, guards, triggers, indicator; J: activity, drives). Key SnapticAwakeV1. G fills
// `restoringDefaults`, `exportable` and `importable` in step 2 (code M14); until then they are safe stubs.

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

    /// Page Restore Defaults: everything back to defaults; pointerNudge off, Drive Alive volumes cleared (r1 security
    /// L6). G refines it in step 2; the step-0 body is already safe (all defaults).
    package func restoringDefaults() -> AwakeConfig { AwakeConfig() }

    /// Backup export (security M7). Stub until G's step 2: defaults only (nothing personal leaves).
    package func exportable(includeTriggers: Bool) -> AwakeConfig { AwakeConfig() }

    /// Backup import, applied after KitBackup's merge. Stub until G's step 2: keeps `current` (nothing comes in).
    package func importable(current: AwakeConfig) -> AwakeConfig { current }
}
