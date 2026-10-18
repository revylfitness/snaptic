import Foundation

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §2.7 + R5-3 (kind S). The type-tagged Codable
// of the condition enums is G's (stub: decoding throws, so an entry is dropped); the list decoders are real.

package enum TriggerMatch: String, Codable, CaseIterable, Sendable { case all, any }

/// Bit 0 = Sunday.
package struct WeekdaySet: OptionSet, Codable, Hashable, Sendable {
    package let rawValue: UInt8
    package init(rawValue: UInt8) { self.rawValue = rawValue & 0x7F }
    package static let everyDay = WeekdaySet(rawValue: 0x7F)
}

package enum DisplayMatch: Equatable, Sendable {
    /// ≥ 1 online non-built-in display.
    case anyExternal
    /// Salted tiers only; name sanitized ≤ 64.
    case specific(record: FingerprintRecord, name: String)
    case mirroring
}

package enum PowerCondition: Equatable, Sendable { case onAdapter, onBattery, charging, batteryAtLeast(Int) }
package enum AudioCondition: String, Codable, Sendable { case outputActive, microphoneActive }

package enum NetworkCondition: Equatable, Sendable {
    /// IPv4 or IPv6, validated.
    case subnet(cidr: String)
    /// "Connected to this network": salted SHA-256 of the router MAC.
    case router(hash: String, label: String)
    case vpnConnected
}

package enum BluetoothMatch: Equatable, Sendable {
    case audio(uidHash: String, name: String), input(hash: String, name: String), anyAudio
}

package enum AwakeCriterion: Equatable, Sendable {
    case app(bundleID: String, name: String, frontmost: Bool)
    case display(DisplayMatch)
    case power(PowerCondition)
    /// Minutes since midnight; end ≤ start = overnight.
    case schedule(days: WeekdaySet, startMinute: Int, endMinute: Int)
    /// 5...100.
    case cpuAbove(percent: Int)
    case audio(AudioCondition)
    /// 1...480.
    case idle(atLeastMinutes: Int)
    case volumeMounted(uuid: String, name: String)
    case usbDevice(vendor: Int, product: Int, serialHash: String?, name: String)
    case network(NetworkCondition)
    /// 10...1_000_000.
    case networkActivity(atLeastKBps: Int)
    case bluetooth(BluetoothMatch)

    package var kind: AwakeCriterionKind {
        switch self {
        case .app: return .app
        case .display: return .display
        case .power: return .power
        case .schedule: return .schedule
        case .cpuAbove: return .cpu
        case .audio: return .audio
        case .idle: return .idle
        case .volumeMounted: return .volume
        case .usbDevice: return .usb
        case .network: return .network
        case .networkActivity: return .networkActivity
        case .bluetooth: return .bluetooth
        }
    }
}

private enum StubTypeKey: String, CodingKey { case type }

private func encodeStubTag(_ encoder: Encoder) throws {
    var c = encoder.container(keyedBy: StubTypeKey.self)
    try c.encode("notBuilt", forKey: .type)
}

extension DisplayMatch: Codable {
    package init(from decoder: Decoder) throws { throw StubError.notBuilt }
    package func encode(to encoder: Encoder) throws { try encodeStubTag(encoder) }
}

extension PowerCondition: Codable {
    package init(from decoder: Decoder) throws { throw StubError.notBuilt }
    package func encode(to encoder: Encoder) throws { try encodeStubTag(encoder) }
}

extension NetworkCondition: Codable {
    package init(from decoder: Decoder) throws { throw StubError.notBuilt }
    package func encode(to encoder: Encoder) throws { try encodeStubTag(encoder) }
}

extension BluetoothMatch: Codable {
    package init(from decoder: Decoder) throws { throw StubError.notBuilt }
    package func encode(to encoder: Encoder) throws { try encodeStubTag(encoder) }
}

extension AwakeCriterion: Codable {
    package init(from decoder: Decoder) throws { throw StubError.notBuilt }
    package func encode(to encoder: Encoder) throws { try encodeStubTag(encoder) }
}

package struct AwakeCriterionEntry: Codable, Equatable, Sendable {
    package var criterion: AwakeCriterion
    package var negated: Bool

    package init(_ criterion: AwakeCriterion, negated: Bool = false) {
        self.criterion = criterion
        self.negated = negated
    }

    private enum CodingKeys: String, CodingKey { case criterion, negated }

    /// "criterion" throws → entry dropped; "negated" lossy (false).
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        criterion = try c.decode(AwakeCriterion.self, forKey: .criterion)
        negated = c.lossy(.negated, false)
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(criterion, forKey: .criterion)
        try c.encode(negated, forKey: .negated)
    }
}

package struct AwakeTrigger: Codable, Equatable, Sendable, Identifiable {
    package var id: StableID
    /// ≤ 64 scalars, TextSanitizer; empty → generated summary.
    package var name: String
    package var enabled: Bool
    package var match: TriggerMatch
    /// 1...8; a trigger with 0 valid criteria is disabled by sanitized().
    package var criteria: [AwakeCriterionEntry]
    /// sanitized(): every `nudge` → `declare` (rules never move the pointer, N10).
    package var options: AwakeSessionOptions
    /// 0...3600; cpu/networkActivity default 60.
    package var startDelaySeconds: Int
    /// 0...3600; default 30 (hysteresis).
    package var endDelaySeconds: Int
    /// nil = when the condition next becomes true.
    package var resumeAfterManualEndMinutes: Int?

    package static let maxTriggers = 32, maxCriteria = 8

    package init(id: StableID, name: String, criteria: [AwakeCriterionEntry]) {
        self.id = id
        self.name = name
        enabled = true
        match = .all
        self.criteria = criteria
        options = AwakeSessionOptions()
        startDelaySeconds = 0
        endDelaySeconds = 30
        resumeAfterManualEndMinutes = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, enabled, match, criteria, options, startDelaySeconds, endDelaySeconds, resumeAfterManualEndMinutes
    }

    /// `id` must decode (else the rule is dropped); `criteria` element-wise (R5-3); every other field lossy.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(StableID.self, forKey: .id)
        name = c.lossy(.name, "")
        enabled = c.lossy(.enabled, true)
        match = c.lossy(.match, .all)
        criteria = c.lossyArray(.criteria, [])
        options = c.lossy(.options, AwakeSessionOptions())
        startDelaySeconds = c.lossy(.startDelaySeconds, 0)
        endDelaySeconds = c.lossy(.endDelaySeconds, 30)
        resumeAfterManualEndMinutes = c.lossy(.resumeAfterManualEndMinutes, nil)
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(match, forKey: .match)
        try c.encode(criteria, forKey: .criteria)
        try c.encode(options, forKey: .options)
        try c.encode(startDelaySeconds, forKey: .startDelaySeconds)
        try c.encode(endDelaySeconds, forKey: .endDelaySeconds)
        try c.encodeIfPresent(resumeAfterManualEndMinutes, forKey: .resumeAfterManualEndMinutes)
    }
}

package struct AwakeTriggersConfig: ConfigModel {
    /// Order = priority; pausedUntil is runtime state (snapshot), not config.
    package var triggers: [AwakeTrigger]

    package init() { triggers = [] }

    private enum CodingKeys: String, CodingKey { case triggers }

    /// `triggers` via lossyUniqueArray (R5-3): one unknown 0.4 rule drops only itself; duplicate ids keep the first.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        triggers = c.lossyUniqueArray(.triggers, [])
    }

    package func sanitized() -> AwakeTriggersConfig {
        var c = self
        c.triggers = Array(triggers.uniquedByID().prefix(AwakeTrigger.maxTriggers))
        return c
    }
}
