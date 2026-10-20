import Combine
import Foundation
import SnapticKit

/// A non-user end shown for 12 h ("Ended at 3:12 AM: battery below 20%.").
struct AwakeLastEnd: Equatable {
    let reason: AwakeEndReason
    let at: Date
}

/// 0.3.1 B1: "Lid-closed mode ended at 3:12 AM: battery at 20%.", shown for 12 h, cleared at the next turn-on.
struct AwakeLastLidEnd: Equatable {
    let reason: AwakeLidEnd
    let at: Date
}

/// Awake's live state (lead; PLAN 0.3 §2.11). Owned by AwakeModule across starts; controllers write it.
@MainActor final class AwakeRuntimeState: ObservableObject {
    @Published var moduleState: ModuleState = .stopped
    @Published var effectiveFeatures: Set<AwakeFeature> = []
    @Published var availability: [AwakeFeature: FeatureAvailability] = [:]
    @Published var governing: AwakeGoverning = .inactive
    /// The hold stack, also while another source governs (N17).
    @Published var holds: [AwakeHold] = []
    /// "Held by Terminal (2)"; local UI only, recomputed when holds change.
    @Published var holderSummary: String?
    /// The hotkey confirmation toast is showing (gate `.asking`).
    @Published var pointerConfirmation = false
    /// Updated at AwakeCountdown.nextChange only.
    @Published var remaining: Double?
    @Published var assertion: AwakeAssertionType = .off
    @Published var power: PowerFacts?
    @Published var guardHold: AwakeEndReason?
    /// Shown for 12 h after a non-user end.
    @Published var lastEnd: AwakeLastEnd?
    @Published var activeTriggerIDs: [StableID] = []
    /// Enabled, condition true, start delay running.
    @Published var waitingTriggerIDs: [StableID] = []
    @Published var pausedUntil: Date?
    /// What acted at the last interval ("Appearing active" / "Moving the pointer").
    @Published var activity: AwakeActivityMode = .off
    /// "Stopped appearing active after 1 hour."
    @Published var activityCapped = false
    @Published var drives: [DriveAliveService.VolumeState] = []
    /// nil = no lid.
    @Published var lidWillSleep: Bool?
    /// 0.3.1 B3.3: the lid is shut (SystemEventsMonitor's `AppleClamshellState`); nil = no lid.
    @Published var lidClosed: Bool?
    /// 0.3.1 B3.0: lid-closed mode's state. Assigned only in LidClosedController.swift (lint L16), so `reset()`
    /// leaves it to the controller.
    @Published var lidMode: AwakeLidMode = .off
    /// 0.3.1 B1: kept for 12 h, like `lastEnd`; it survives `reset()`.
    @Published var lastLidEnd: AwakeLastLidEnd?
    /// Our status item exists and isVisible.
    @Published var indicatorVisible = false
    /// Shortcuts whose combo failed to register (conflict or system refusal; AwakeAutomation publishes it here, as
    /// the runtime outlives the controller). The menu bar treats a failed Keep Awake shortcut as unbound.
    @Published var failedShortcuts: Set<AwakeActionID> = []
    /// The Keep Awake (toggle) shortcut is registered right now (fix round 2 shared decision): false while the
    /// module is off, `shortcuts` isn't effective (setting, Safe Mode, kill switch), no combo is set, or the
    /// registration failed. The menu bar's Don't Show fallback reads only this.
    @Published var keepAwakeRegistered = false

    init() {}

    func isEffective(_ f: AwakeFeature) -> Bool { effectiveFeatures.contains(f) }

    /// Everything back to "stopped" (module stop). `lastEnd` stays: it is shown after the module restarts too.
    func reset() {
        moduleState = .stopped
        effectiveFeatures = []
        availability = [:]
        governing = .inactive
        holds = []
        holderSummary = nil
        pointerConfirmation = false
        remaining = nil
        assertion = .off
        power = nil
        guardHold = nil
        activeTriggerIDs = []
        waitingTriggerIDs = []
        pausedUntil = nil
        activity = .off
        activityCapped = false
        drives = []
        lidWillSleep = nil
        lidClosed = nil
        indicatorVisible = false
        failedShortcuts = []
        keepAwakeRegistered = false
    }
}
