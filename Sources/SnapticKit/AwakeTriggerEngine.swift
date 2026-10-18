import Foundation

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §2.7 (kind S): safe returns.

package struct DisplayFact: Equatable, Sendable {
    package var record: FingerprintRecord
    package var isBuiltin: Bool
    package init(record: FingerprintRecord, isBuiltin: Bool) {
        self.record = record
        self.isBuiltin = isBuiltin
    }
}

package struct USBFact: Equatable, Sendable {
    package var vendor: Int
    package var product: Int
    package var serialHash: String?
    package init(vendor: Int, product: Int, serialHash: String?) {
        self.vendor = vendor
        self.product = product
        self.serialHash = serialHash
    }
}

package struct NetworkFacts: Equatable, Sendable {
    package var addresses: [String]
    package var routerHashes: Set<String>
    package var vpn: Bool
    package init(addresses: [String], routerHashes: Set<String>, vpn: Bool) {
        self.addresses = addresses
        self.routerHashes = routerHashes
        self.vpn = vpn
    }
}

package struct BluetoothFact: Equatable, Sendable {
    package var audioUIDHashes: Set<String>
    package var inputHashes: Set<String>
    package init(audioUIDHashes: Set<String>, inputHashes: Set<String>) {
        self.audioUIDHashes = audioUIDHashes
        self.inputHashes = inputHashes
    }
}

/// nil = the source isn't running or hasn't produced a value yet ("unknown").
package struct CriterionFacts: Equatable, Sendable {
    package var runningApps: Set<String>?
    package var frontmostApp: String??
    package var displays: [DisplayFact]?
    package var mirroring: Bool?
    package var power: PowerFacts?
    /// 0..<10080, local time, computed by the app with Calendar.autoupdatingCurrent.
    package var minuteOfWeek: Int?
    package var cpuPercent: Double?
    package var audioOutput: Bool?
    package var microphone: Bool?
    package var realIdleSeconds: Double?
    package var volumes: Set<String>?
    package var usb: [USBFact]?
    package var network: NetworkFacts?
    package var throughputKBps: Double?
    package var bluetooth: BluetoothFact?

    package init() {}
}

/// In memory only, continuous clock.
package struct TriggerHysteresis: Equatable, Sendable {
    package var trueSince: Double?
    package var falseSince: Double?
    package var active: Bool
    package init() {
        trueSince = nil
        falseSince = nil
        active = false
    }
}

/// Persisted in the snapshot (same boot only for `until`).
package struct TriggerSuppression: Codable, Equatable, Sendable {
    package var until: Double?
    package var untilFalse: Bool

    package init(until: Double?, untilFalse: Bool) {
        self.until = until
        self.untilFalse = untilFalse
    }

    private enum CodingKeys: String, CodingKey { case until, untilFalse }

    /// Lossy per field (rule 9).
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        until = c.lossy(.until, nil)
        untilFalse = c.lossy(.untilFalse, false)
    }
}

package struct TriggerStepResult: Equatable, Sendable {
    package var hysteresis: [StableID: TriggerHysteresis]
    /// Expired ones removed.
    package var suppressions: [StableID: TriggerSuppression]
    package var top: TriggerTop?
    /// Continuous instant of the next delay expiry.
    package var nextDeadline: Double?

    package init(hysteresis: [StableID: TriggerHysteresis], suppressions: [StableID: TriggerSuppression],
                 top: TriggerTop?, nextDeadline: Double?) {
        self.hysteresis = hysteresis
        self.suppressions = suppressions
        self.top = top
        self.nextDeadline = nextDeadline
    }
}

package enum TriggerEngine {
    /// true / false / nil (unknown). Stub: unknown.
    package static func holds(_ entry: AwakeCriterionEntry, facts: CriterionFacts) -> Bool? { nil }
    /// Stub: false.
    package static func condition(_ t: AwakeTrigger, facts: CriterionFacts) -> Bool { false }
    /// Stub: nothing active.
    package static func step(_ triggers: [AwakeTrigger], facts: CriterionFacts, now: Double,
                             hysteresis: [StableID: TriggerHysteresis], suppressions: [StableID: TriggerSuppression],
                             paused: Bool, guardsHold: Bool) -> TriggerStepResult {
        TriggerStepResult(hysteresis: hysteresis, suppressions: suppressions, top: nil, nextDeadline: nil)
    }
    /// Stub: suppressed until the condition is next false.
    package static func manualEnd(_ t: AwakeTrigger, now: Double) -> TriggerSuppression {
        TriggerSuppression(until: nil, untilFalse: true)
    }
    package static func requiredKinds(_ triggers: [AwakeTrigger]) -> Set<AwakeCriterionKind> {
        Set(triggers.filter(\.enabled).flatMap { $0.criteria.map(\.criterion.kind) })
    }
    /// Stub: none.
    package static func scheduleBoundaries(_ triggers: [AwakeTrigger]) -> Set<Int> { [] }
    /// Stub: the rule's name.
    package static func summary(_ t: AwakeTrigger) -> String { t.name }
}
