import Foundation

// Rule model (owner: G; PLAN 0.3 §2.7, N18, R5-3). Every enum with associated values has a hand-written, type-tagged
// Codable: each object has exactly one "type" key at its own level, and a nested enum sits whole under "condition"
// (or "match" for DisplayMatch/BluetoothMatch). An unknown type throws, so only that entry (or rule) is dropped.

package enum TriggerMatch: String, Codable, CaseIterable, Sendable { case all, any }

/// Bit 0 = Sunday.
package struct WeekdaySet: OptionSet, Codable, Hashable, Sendable {
    package let rawValue: UInt8
    package init(rawValue: UInt8) { self.rawValue = rawValue & 0x7F }
    package static let everyDay = WeekdaySet(rawValue: 0x7F)
    /// Monday through Friday.
    package static let weekdays = WeekdaySet(rawValue: 0b0111110)
    /// Saturday and Sunday.
    package static let weekend = WeekdaySet(rawValue: 0b1000001)

    /// 0 = Sunday … 6 = Saturday.
    package static func day(_ index: Int) -> WeekdaySet {
        WeekdaySet(rawValue: UInt8(truncatingIfNeeded: 1 << (((index % 7) + 7) % 7)))
    }

    package func contains(day index: Int) -> Bool { contains(.day(index)) }
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
    /// Minutes since midnight; end ≤ start = overnight (end == start: 24 hours from start).
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

    package static let cpuRange: ClosedRange<Int> = 5...100
    package static let idleRange: ClosedRange<Int> = 1...480
    package static let networkActivityRange: ClosedRange<Int> = 10...1_000_000
    package static let batteryRange: ClosedRange<Int> = 1...100
    package static let maxNameScalars = 64

    /// The criterion clamped to what the editor produces, or nil when it can't be kept (bad bundle id, UUID, hash,
    /// empty day set, empty display record).
    package func sanitized() -> AwakeCriterion? {
        let name = { (s: String) in TextSanitizer.clean(s, maxScalars: Self.maxNameScalars) }
        switch self {
        case .app(let bundleID, let n, let frontmost):
            guard AwakeBundleID.isValid(bundleID) else { return nil }
            return .app(bundleID: bundleID, name: name(n), frontmost: frontmost)
        case .display(let match):
            switch match {
            case .anyExternal, .mirroring: return self
            case .specific(let record, let n):
                guard !record.isEmpty else { return nil }
                return .display(.specific(record: record, name: name(n)))
            }
        case .power(let condition):
            if case .batteryAtLeast(let p) = condition {
                return .power(.batteryAtLeast(AwakeMath.clamp(p, Self.batteryRange)))
            }
            return self
        case .schedule(let days, let start, let end):
            guard !days.isEmpty else { return nil }
            return .schedule(days: days, startMinute: AwakeMath.clamp(start, 0...1_439),
                             endMinute: AwakeMath.clamp(end, 0...1_439))
        case .cpuAbove(let p):
            return .cpuAbove(percent: AwakeMath.clamp(p, Self.cpuRange))
        case .audio:
            return self
        case .idle(let m):
            return .idle(atLeastMinutes: AwakeMath.clamp(m, Self.idleRange))
        case .volumeMounted(let uuid, let n):
            guard let u = UUID(uuidString: uuid) else { return nil }
            return .volumeMounted(uuid: u.uuidString.uppercased(), name: name(n))
        case .usbDevice(let vendor, let product, let serialHash, let n):
            guard (0...0xFFFF).contains(vendor), (0...0xFFFF).contains(product) else { return nil }
            if let h = serialHash, !Fingerprint.isHexDigest(h) { return nil }
            return .usbDevice(vendor: vendor, product: product, serialHash: serialHash, name: name(n))
        case .network(let condition):
            switch condition {
            case .subnet(let cidr):
                guard Self.looksLikeCIDR(cidr) else { return nil }
                return self
            case .router(let hash, let label):
                guard Fingerprint.isHexDigest(hash) else { return nil }
                return .network(.router(hash: hash, label: name(label)))
            case .vpnConnected:
                return self
            }
        case .networkActivity(let k):
            return .networkActivity(atLeastKBps: AwakeMath.clamp(k, Self.networkActivityRange))
        case .bluetooth(let match):
            switch match {
            case .anyAudio: return self
            case .audio(let h, let n):
                guard Fingerprint.isHexDigest(h) else { return nil }
                return .bluetooth(.audio(uidHash: h, name: name(n)))
            case .input(let h, let n):
                guard Fingerprint.isHexDigest(h) else { return nil }
                return .bluetooth(.input(hash: h, name: name(n)))
            }
        }
    }

    /// Shape check only ("10.0.0.0/8", "fd00::/8"): hex digits, ".", ":" and one "/" with a 0...128 prefix. The
    /// address itself is validated by NetworkMath when the rule is evaluated (an invalid one never matches).
    package static func looksLikeCIDR(_ s: String) -> Bool {
        let parts = s.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, (2...45).contains(parts[0].utf8.count), (1...3).contains(parts[1].utf8.count) else {
            return false
        }
        guard parts[0].utf8.allSatisfy(isAddressByte) else { return false }
        guard parts[1].utf8.allSatisfy({ (0x30...0x39).contains($0) }), let prefix = Int(parts[1]) else { return false }
        return (0...128).contains(prefix)
    }

    /// Hex digits, "." and ":".
    private static func isAddressByte(_ b: UInt8) -> Bool {
        switch b {
        case 0x30...0x39, 0x41...0x46, 0x61...0x66, 0x2E, 0x3A: return true
        default: return false
        }
    }
}

private enum TagKey: String, CodingKey {
    case type, record, name, percent, cidr, hash, label, uidHash, bundleID, frontmost, match, condition, days,
         startMinute, endMinute, atLeastMinutes, uuid, vendor, product, serialHash, atLeastKBps
}

private func unknownType(_ c: KeyedDecodingContainer<TagKey>) -> DecodingError {
    DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown type")
}

extension DisplayMatch: Codable {
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TagKey.self)
        switch try c.decode(String.self, forKey: .type) {
        case "anyExternal": self = .anyExternal
        case "mirroring": self = .mirroring
        case "specific":
            self = .specific(record: try c.decode(FingerprintRecord.self, forKey: .record), name: c.lossy(.name, ""))
        default: throw unknownType(c)
        }
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: TagKey.self)
        switch self {
        case .anyExternal: try c.encode("anyExternal", forKey: .type)
        case .mirroring: try c.encode("mirroring", forKey: .type)
        case .specific(let record, let name):
            try c.encode("specific", forKey: .type)
            try c.encode(record, forKey: .record)
            try c.encode(name, forKey: .name)
        }
    }
}

extension PowerCondition: Codable {
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TagKey.self)
        switch try c.decode(String.self, forKey: .type) {
        case "onAdapter": self = .onAdapter
        case "onBattery": self = .onBattery
        case "charging": self = .charging
        case "batteryAtLeast": self = .batteryAtLeast(try c.decode(Int.self, forKey: .percent))
        default: throw unknownType(c)
        }
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: TagKey.self)
        switch self {
        case .onAdapter: try c.encode("onAdapter", forKey: .type)
        case .onBattery: try c.encode("onBattery", forKey: .type)
        case .charging: try c.encode("charging", forKey: .type)
        case .batteryAtLeast(let p):
            try c.encode("batteryAtLeast", forKey: .type)
            try c.encode(p, forKey: .percent)
        }
    }
}

extension NetworkCondition: Codable {
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TagKey.self)
        switch try c.decode(String.self, forKey: .type) {
        case "subnet": self = .subnet(cidr: try c.decode(String.self, forKey: .cidr))
        case "router": self = .router(hash: try c.decode(String.self, forKey: .hash), label: c.lossy(.label, ""))
        case "vpnConnected": self = .vpnConnected
        default: throw unknownType(c)
        }
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: TagKey.self)
        switch self {
        case .subnet(let cidr):
            try c.encode("subnet", forKey: .type)
            try c.encode(cidr, forKey: .cidr)
        case .router(let hash, let label):
            try c.encode("router", forKey: .type)
            try c.encode(hash, forKey: .hash)
            try c.encode(label, forKey: .label)
        case .vpnConnected:
            try c.encode("vpnConnected", forKey: .type)
        }
    }
}

extension BluetoothMatch: Codable {
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TagKey.self)
        switch try c.decode(String.self, forKey: .type) {
        case "audio": self = .audio(uidHash: try c.decode(String.self, forKey: .uidHash), name: c.lossy(.name, ""))
        case "input": self = .input(hash: try c.decode(String.self, forKey: .hash), name: c.lossy(.name, ""))
        case "anyAudio": self = .anyAudio
        default: throw unknownType(c)
        }
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: TagKey.self)
        switch self {
        case .audio(let h, let n):
            try c.encode("audio", forKey: .type)
            try c.encode(h, forKey: .uidHash)
            try c.encode(n, forKey: .name)
        case .input(let h, let n):
            try c.encode("input", forKey: .type)
            try c.encode(h, forKey: .hash)
            try c.encode(n, forKey: .name)
        case .anyAudio:
            try c.encode("anyAudio", forKey: .type)
        }
    }
}

extension AwakeCriterion: Codable {
    /// {"type":"app","bundleID":…,"name":…,"frontmost":false}; nested enums under "match"/"condition".
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TagKey.self)
        switch try c.decode(String.self, forKey: .type) {
        case "app":
            self = .app(bundleID: try c.decode(String.self, forKey: .bundleID), name: c.lossy(.name, ""),
                        frontmost: c.lossy(.frontmost, false))
        case "display":
            self = .display(try c.decode(DisplayMatch.self, forKey: .match))
        case "power":
            self = .power(try c.decode(PowerCondition.self, forKey: .condition))
        case "schedule":
            self = .schedule(days: try c.decode(WeekdaySet.self, forKey: .days),
                             startMinute: try c.decode(Int.self, forKey: .startMinute),
                             endMinute: try c.decode(Int.self, forKey: .endMinute))
        case "cpuAbove":
            self = .cpuAbove(percent: try c.decode(Int.self, forKey: .percent))
        case "audio":
            self = .audio(try c.decode(AudioCondition.self, forKey: .condition))
        case "idle":
            self = .idle(atLeastMinutes: try c.decode(Int.self, forKey: .atLeastMinutes))
        case "volumeMounted":
            self = .volumeMounted(uuid: try c.decode(String.self, forKey: .uuid), name: c.lossy(.name, ""))
        case "usbDevice":
            self = .usbDevice(vendor: try c.decode(Int.self, forKey: .vendor), product: try c.decode(Int.self, forKey: .product),
                              serialHash: c.lossy(.serialHash, nil), name: c.lossy(.name, ""))
        case "network":
            self = .network(try c.decode(NetworkCondition.self, forKey: .condition))
        case "networkActivity":
            self = .networkActivity(atLeastKBps: try c.decode(Int.self, forKey: .atLeastKBps))
        case "bluetooth":
            self = .bluetooth(try c.decode(BluetoothMatch.self, forKey: .match))
        default:
            throw unknownType(c)
        }
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: TagKey.self)
        switch self {
        case .app(let bundleID, let name, let frontmost):
            try c.encode("app", forKey: .type)
            try c.encode(bundleID, forKey: .bundleID)
            try c.encode(name, forKey: .name)
            try c.encode(frontmost, forKey: .frontmost)
        case .display(let match):
            try c.encode("display", forKey: .type)
            try c.encode(match, forKey: .match)
        case .power(let condition):
            try c.encode("power", forKey: .type)
            try c.encode(condition, forKey: .condition)
        case .schedule(let days, let start, let end):
            try c.encode("schedule", forKey: .type)
            try c.encode(days, forKey: .days)
            try c.encode(start, forKey: .startMinute)
            try c.encode(end, forKey: .endMinute)
        case .cpuAbove(let p):
            try c.encode("cpuAbove", forKey: .type)
            try c.encode(p, forKey: .percent)
        case .audio(let condition):
            try c.encode("audio", forKey: .type)
            try c.encode(condition, forKey: .condition)
        case .idle(let m):
            try c.encode("idle", forKey: .type)
            try c.encode(m, forKey: .atLeastMinutes)
        case .volumeMounted(let uuid, let name):
            try c.encode("volumeMounted", forKey: .type)
            try c.encode(uuid, forKey: .uuid)
            try c.encode(name, forKey: .name)
        case .usbDevice(let vendor, let product, let serialHash, let name):
            try c.encode("usbDevice", forKey: .type)
            try c.encode(vendor, forKey: .vendor)
            try c.encode(product, forKey: .product)
            try c.encodeIfPresent(serialHash, forKey: .serialHash)
            try c.encode(name, forKey: .name)
        case .network(let condition):
            try c.encode("network", forKey: .type)
            try c.encode(condition, forKey: .condition)
        case .networkActivity(let k):
            try c.encode("networkActivity", forKey: .type)
            try c.encode(k, forKey: .atLeastKBps)
        case .bluetooth(let match):
            try c.encode("bluetooth", forKey: .type)
            try c.encode(match, forKey: .match)
        }
    }
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
    package static let delayRange: ClosedRange<Int> = 0...3_600
    package static let resumeRange: ClosedRange<Int> = 1...1_440
    package static let defaultEndDelaySeconds = 30
    /// The start delay a new rule gets for a criterion kind (cpu and network activity wait a minute).
    package static func defaultStartDelay(for kinds: Set<AwakeCriterionKind>) -> Int {
        kinds.contains(.cpu) || kinds.contains(.networkActivity) ? 60 : 0
    }

    package init(id: StableID, name: String, criteria: [AwakeCriterionEntry]) {
        self.id = id
        self.name = name
        enabled = true
        match = .all
        self.criteria = criteria
        options = AwakeSessionOptions()
        startDelaySeconds = Self.defaultStartDelay(for: Set(criteria.map(\.criterion.kind)))
        endDelaySeconds = Self.defaultEndDelaySeconds
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
        endDelaySeconds = c.lossy(.endDelaySeconds, Self.defaultEndDelaySeconds)
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

    /// Name cleaned to 64 scalars; criteria sanitized (invalid ones dropped) and capped at 8; no valid criterion →
    /// disabled; options clamped and `nudge` → `declare`; delays 0...3600; resume 1...1440 minutes.
    package func sanitized() -> AwakeTrigger {
        var t = self
        t.name = TextSanitizer.clean(name, maxScalars: AwakeCriterion.maxNameScalars)
        t.criteria = Array(criteria.compactMap { e -> AwakeCriterionEntry? in
            e.criterion.sanitized().map { AwakeCriterionEntry($0, negated: e.negated) }
        }.prefix(Self.maxCriteria))
        if t.criteria.isEmpty { t.enabled = false }
        t.options = options.sanitized().withoutNudge()
        t.startDelaySeconds = AwakeMath.clamp(startDelaySeconds, Self.delayRange)
        t.endDelaySeconds = AwakeMath.clamp(endDelaySeconds, Self.delayRange)
        t.resumeAfterManualEndMinutes = resumeAfterManualEndMinutes.map { AwakeMath.clamp($0, Self.resumeRange) }
        return t
    }

    /// The name to show: the user's, or the generated summary.
    package func displayName(_ text: AwakeTextContext = .standard) -> String {
        name.isEmpty ? TriggerEngine.summary(self, text: text) : name
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
        c.triggers = Array(triggers.uniquedByID().prefix(AwakeTrigger.maxTriggers)).map { $0.sanitized() }
        return c
    }

    /// Every rule's options without pointer movement (rules never move the pointer, N10).
    package func withoutNudge() -> AwakeTriggersConfig {
        var c = self
        c.triggers = triggers.map { t -> AwakeTrigger in
            var t = t
            t.options = t.options.withoutNudge()
            return t
        }
        return c
    }

    /// Exports without salted hashes (useless on another Mac): specific displays, routers, USB serials and Bluetooth
    /// devices lose those conditions. A rule that lost or changed a condition is disabled, because a rule with fewer
    /// conditions could apply more often than the user chose.
    package func strippingHashes() -> AwakeTriggersConfig {
        var c = self
        c.triggers = triggers.map(Self.strippingHashes)
        return c
    }

    /// One rule without salted hashes (see `strippingHashes()`).
    package static func strippingHashes(_ original: AwakeTrigger) -> AwakeTrigger {
        var t = original
        t.criteria = original.criteria.compactMap { e -> AwakeCriterionEntry? in
            switch e.criterion {
            case .display(.specific), .network(.router), .bluetooth(.audio), .bluetooth(.input):
                return nil
            case .usbDevice(let vendor, let product, _, let name):
                return AwakeCriterionEntry(.usbDevice(vendor: vendor, product: product, serialHash: nil, name: name),
                                           negated: e.negated)
            default:
                return e
            }
        }
        if t.criteria.isEmpty || t.criteria != original.criteria { t.enabled = false }
        return t
    }

    /// Backup import (security S-2): only what came from the file is stripped. A rule equal to this Mac's rule with
    /// the same id, either as stored or as this Mac would export it, is this Mac's own and is kept untouched (its
    /// salted hashes are valid here and it stays enabled); every other rule loses its salted hashes like an export.
    /// Nothing the file carries can add a hash or turn a rule on: a kept rule is exactly the current one.
    package func importing(over current: AwakeTriggersConfig) -> AwakeTriggersConfig {
        var c = self
        var own: [StableID: AwakeTrigger] = [:]
        for t in current.triggers where own[t.id] == nil { own[t.id] = t }
        c.triggers = triggers.map { t -> AwakeTrigger in
            if let mine = own[t.id] {
                let exported = Self.strippingHashes(mine).sanitized()
                if mine == t || mine.sanitized() == t || exported == t { return mine }
            }
            return Self.strippingHashes(t).sanitized()
        }
        return c
    }
}

// MARK: - Rule editor (§4.3 "Rule editor sheet")

/// The kind pop-up of a condition row: one entry per editor, so the network conditions are three entries and the
/// router one is titled "Connected to this network".
package enum AwakeCriterionChoice: String, CaseIterable, Sendable {
    case app, display, power, schedule, cpu, audio, idle, volume, usb, subnet, router, vpn, networkActivity, bluetooth

    package init(_ c: AwakeCriterion) {
        switch c {
        case .app: self = .app
        case .display: self = .display
        case .power: self = .power
        case .schedule: self = .schedule
        case .cpuAbove: self = .cpu
        case .audio: self = .audio
        case .idle: self = .idle
        case .volumeMounted: self = .volume
        case .usbDevice: self = .usb
        case .network(.subnet): self = .subnet
        case .network(.router): self = .router
        case .network(.vpnConnected): self = .vpn
        case .networkActivity: self = .networkActivity
        case .bluetooth: self = .bluetooth
        }
    }

    package var kind: AwakeCriterionKind {
        switch self {
        case .app: return .app
        case .display: return .display
        case .power: return .power
        case .schedule: return .schedule
        case .cpu: return .cpu
        case .audio: return .audio
        case .idle: return .idle
        case .volume: return .volume
        case .usb: return .usb
        case .subnet, .router, .vpn: return .network
        case .networkActivity: return .networkActivity
        case .bluetooth: return .bluetooth
        }
    }

    package var title: String {
        switch self {
        case .app: return L("App")
        case .display: return L("Display")
        case .power: return L("Power")
        case .schedule: return L("Schedule")
        case .cpu: return L("CPU use")
        case .audio: return L("Audio")
        case .idle: return L("Idle time")
        case .volume: return L("Drive")
        case .usb: return L("USB device")
        case .subnet: return L("IP address")
        case .router: return L("Connected to this network")
        case .vpn: return L("VPN")
        case .networkActivity: return L("Network activity")
        case .bluetooth: return L("Bluetooth audio")
        }
    }

    /// Power's values include their inverses ("On battery" / "On power adapter"), so it has no is / is not.
    package var allowsNegation: Bool { self != .power }

    /// Bluetooth is Beta (C6).
    package var isBeta: Bool { self == .bluetooth }

    /// What a row of this kind starts with; nil for kinds that need a choice first (an app, a drive, a USB device,
    /// the current network), which the editor makes from what is there now.
    package var defaultCriterion: AwakeCriterion? {
        switch self {
        case .app, .volume, .usb, .router: return nil
        case .display: return .display(.anyExternal)
        case .power: return .power(.onAdapter)
        case .schedule: return .schedule(days: .weekdays, startMinute: 9 * 60, endMinute: 17 * 60)
        case .cpu: return .cpuAbove(percent: 50)
        case .audio: return .audio(.outputActive)
        case .idle: return .idle(atLeastMinutes: 10)
        case .subnet: return .network(.subnet(cidr: "192.168.0.0/16"))
        case .vpn: return .network(.vpnConnected)
        case .networkActivity: return .networkActivity(atLeastKBps: 100)
        case .bluetooth: return .bluetooth(.anyAudio)
        }
    }
}

extension AwakeTrigger {
    /// Delay choices of the Timing disclosure, in seconds (None … 1 hour); a stored value not in the list is shown too.
    package static let delayChoices = [0, 10, 30, 60, 120, 300, 600, 1_800, 3_600]
    /// "After I turn it off" choices in minutes; nil = when the conditions are next met.
    package static let resumeChoices: [Int?] = [nil, 15, 60, 240]

    /// The choices with `current` added in order when it isn't one of them.
    package static func choices(_ list: [Int], including current: Int) -> [Int] {
        list.contains(current) ? list : (list + [current]).sorted()
    }

    /// "None", "30 seconds", "1 minute", "2 minutes", "1 hour".
    package static func delayTitle(_ seconds: Int) -> String {
        let s = AwakeMath.clamp(seconds, delayRange)
        if s == 0 { return L("None") }
        if s % 3_600 == 0 { return AwakeCountdown.unit(s / 3_600, L("hour"), L("hours")) }
        if s % 60 == 0 { return AwakeCountdown.unit(s / 60, L("minute"), L("minutes")) }
        return AwakeCountdown.unit(s, L("second"), L("seconds"))
    }

    /// A new rule from the editor's + : one condition, or the default display condition.
    package static func new(id: StableID, criterion: AwakeCriterion?) -> AwakeTrigger {
        AwakeTrigger(id: id, name: "", criteria: [AwakeCriterionEntry(criterion ?? .display(.anyExternal))])
    }

    /// Saved from the editor: sanitized, and the start delay a CPU or network-activity rule needs when the user left
    /// it at None (a spike shouldn't start a session).
    package func savedFromEditor(wasNew: Bool) -> AwakeTrigger {
        var t = sanitized()
        let kinds = Set(t.criteria.map(\.criterion.kind))
        if wasNew && t.startDelaySeconds == 0 { t.startDelaySeconds = Self.defaultStartDelay(for: kinds) }
        return t
    }
}
