import AppKit
import SnapticKit

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §2.5 + R5 (kind S): every start is refused,
// nothing is held. The only file that assigns `activityGate` (lint L16).

/// A manual session or a hold that ended.
enum AwakeEndedItem: Equatable { case session(AwakeSession), hold(AwakeHold) }

@MainActor final class SessionController: AwakeFeatureController {
    static var id: AwakeControllerID { .sessions }
    weak var context: AwakeContext?
    private(set) var holds: [AwakeHold] = []
    /// The runtime gate (§2.3), assigned only here, always through `applying(_:)`.
    private(set) var activityGate = AwakeActivityGate()

    init() {}

    func start(_ kind: AwakeSessionKind, options: AwakeSessionOptions?, presetID: StableID?,
               source: AwakeSessionSource, overrideGuards: Bool) -> Result<AwakeSession, AwakeRefusal> {
        .failure(.unavailable(.featureOff))
    }

    func startPreset(_ id: StableID, source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal> {
        .failure(.unavailable(.featureOff))
    }

    func startDefault(source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal> {
        .failure(.unavailable(.featureOff))
    }

    /// CLI `awake hold` (N17).
    func addHold(_ binding: HoldBinding, capSeconds: Int) -> Result<AwakeHold, AwakeRefusal> {
        .failure(.unavailable(.featureOff))
    }

    func endHold(_ id: StableID, _ reason: AwakeEndReason) {}

    /// "End Command-Line Holds" (R5-10).
    func endAllHolds(_ reason: AwakeEndReason) {}

    /// Manual only.
    func extend(by seconds: Int, source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal> {
        .failure(.invalid)
    }

    func setKeepDisplayOn(_ on: Bool) {}

    func turnOff(source: AwakeSessionSource) {}

    func end(_ reason: AwakeEndReason) {}

    func toggleDefault(source: AwakeSessionSource) {}

    func requestPointerConfirmation() {}

    func noteActivityActed(now: Double) {
        activityGate = activityGate.applying(.acted(now: now))
    }

    /// Called once from start(), after every needed service is active and before the first arbitrate().
    func restore(_ snapshot: AwakeRuntimeSnapshot) {
        activityGate = activityGate.applying(.restore)
    }

    func observeEnds(_ lifetime: Lifetime, _ handler: @escaping @MainActor (AwakeEndedItem, AwakeEndReason) -> Void) {}

    func arbitrate() {}

    // MARK: AwakeFeatureController

    func availability(of feature: AwakeFeature, context: AwakeContext) -> FeatureAvailability { .available }

    func start(_ context: AwakeContext, lifetime: Lifetime, effective: Set<AwakeFeature>) { self.context = context }

    func effectiveFeaturesDidChange(_ effective: Set<AwakeFeature>) {}

    func configDidChange(from old: AwakeConfig, to new: AwakeConfig) {}

    func stop() {
        activityGate = activityGate.applying(.moduleStop)
        holds = []
        context = nil
    }
}
