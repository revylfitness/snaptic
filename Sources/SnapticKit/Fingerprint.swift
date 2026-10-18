import Foundation

// Display identity tiers and matching (owner: B). PLAN §5: tiers (1) EDID hash +
// alphanumeric serial, (2) UUID, (3) vendor/model/serial, (4) location. Kit builds the
// canonical strings; the app hashes them with the salt (CryptoKit), so nothing raw is stored.

package enum FingerprintTier: Int, Codable, CaseIterable, Sendable, Comparable {
    case edidSerial = 1, uuid = 2, vendorModelSerial = 3, location = 4, vendorModel = 5
    package static func < (a: FingerprintTier, b: FingerprintTier) -> Bool { a.rawValue < b.rawValue }
}

/// Raw identity facts for one display, read app-side and never persisted as-is.
package struct DisplayIdentityFacts: Equatable, Sendable {
    /// Hex digest of the raw EDID (or the framebuffer's "EDID UUID" string on Apple silicon).
    package var edidHash: String?
    package var alphanumericSerial: String?
    /// CGDisplayCreateUUIDFromDisplayID.
    package var uuid: String?
    package var vendor: UInt32
    package var model: UInt32
    package var serial: UInt32
    /// IORegistry location (port), the last-resort tie-break.
    package var location: String?
    package var isBuiltin: Bool

    package init(edidHash: String? = nil, alphanumericSerial: String? = nil, uuid: String? = nil, vendor: UInt32 = 0,
                 model: UInt32 = 0, serial: UInt32 = 0, location: String? = nil, isBuiltin: Bool = false) {
        self.edidHash = edidHash
        self.alphanumericSerial = alphanumericSerial
        self.uuid = uuid
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.location = location
        self.isBuiltin = isBuiltin
    }
}

/// Salted hashes per tier, as stored in config (PerDisplayIdentity). Hex strings only.
package struct FingerprintRecord: Codable, Equatable, Sendable {
    package var t1: String?
    package var t2: String?
    package var t3: String?
    package var t4: String?
    package var t5: String?

    package init(t1: String? = nil, t2: String? = nil, t3: String? = nil, t4: String? = nil, t5: String? = nil) {
        self.t1 = t1
        self.t2 = t2
        self.t3 = t3
        self.t4 = t4
        self.t5 = t5
    }

    private enum CodingKeys: String, CodingKey { case t1, t2, t3, t4, t5 }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func hex(_ k: CodingKeys) -> String? {
            let v = (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil
            return v.flatMap { Fingerprint.isHexDigest($0) ? $0 : nil }
        }
        t1 = hex(.t1)
        t2 = hex(.t2)
        t3 = hex(.t3)
        t4 = hex(.t4)
        t5 = hex(.t5)
    }

    package subscript(tier: FingerprintTier) -> String? {
        get {
            switch tier {
            case .edidSerial: return t1
            case .uuid: return t2
            case .vendorModelSerial: return t3
            case .location: return t4
            case .vendorModel: return t5
            }
        }
        set {
            switch tier {
            case .edidSerial: t1 = newValue
            case .uuid: t2 = newValue
            case .vendorModelSerial: t3 = newValue
            case .location: t4 = newValue
            case .vendorModel: t5 = newValue
            }
        }
    }

    /// The most specific tier present.
    package var bestTier: FingerprintTier? { FingerprintTier.allCases.first { self[$0] != nil } }

    package var isEmpty: Bool { bestTier == nil }
}

package enum Fingerprint {
    /// Canonical strings per available tier (input to the salted hash). Serials are
    /// normalized (trimmed, uppercased); zero or placeholder serials don't count.
    package static func canonical(_ f: DisplayIdentityFacts) -> [FingerprintTier: String] {
        var out: [FingerprintTier: String] = [:]
        let vm = "\(f.vendor):\(f.model)"
        if let e = clean(f.edidHash), let s = cleanSerial(f.alphanumericSerial) {
            out[.edidSerial] = "t1|\(e.lowercased())|\(s)"
        }
        if let u = clean(f.uuid) { out[.uuid] = "t2|\(u.uppercased())" }
        if f.serial != 0 && f.serial != 0x0101_0101 && f.serial != 0xFFFF_FFFF {
            out[.vendorModelSerial] = "t3|\(vm):\(f.serial)"
        }
        if let l = clean(f.location) { out[.location] = "t4|\(vm)|\(l)" }
        out[.vendorModel] = "t5|\(vm)|\(f.isBuiltin ? "builtin" : "external")"
        return out
    }

    /// Whether a stored record and a live one name the same display (Awake's display criterion, which has no
    /// `DisplayKey` map). Only tiers present on **both** sides are compared: a stored tier the live side can't
    /// compute (t1 needs the EDID, t4 the IORegistry location) neither matches nor conflicts. The most specific
    /// shared tier decides, exactly like `match(_:in:)`: equal there is a match, different there is another
    /// display even when a weaker tier agrees (two identical monitors share t5). No shared tier is no match, so
    /// empty records never match anything.
    package static func matches(_ stored: FingerprintRecord, _ live: FingerprintRecord) -> Bool {
        for tier in FingerprintTier.allCases {
            guard let a = stored[tier], let b = live[tier] else { continue }
            return a == b
        }
        return false
    }

    /// The tier a new key derives from: the best one available.
    package static func bestTier(_ f: DisplayIdentityFacts) -> FingerprintTier {
        canonical(f).keys.min() ?? .vendorModel
    }

    /// Finds the stored display these hashes belong to. A higher tier decides; a lower tier
    /// only matches when neither side has a conflicting higher tier, and only uniquely.
    package static func match(_ record: FingerprintRecord, in stored: [DisplayKey: FingerprintRecord]) -> DisplayKey? {
        let keys = stored.keys.sorted { $0.rawValue < $1.rawValue }
        for tier in FingerprintTier.allCases {
            guard let mine = record[tier] else { continue }
            let hits = keys.filter { k in
                guard let other = stored[k], other[tier] == mine else { return false }
                // Reject when a more specific tier exists on both sides and differs.
                for higher in FingerprintTier.allCases where higher < tier {
                    if let a = record[higher], let b = other[higher], a != b { return false }
                }
                return true
            }
            if hits.count == 1 { return hits[0] }
            if hits.count > 1 && tier <= .uuid { return hits[0] }       // duplicates at t1/t2: first (stable order)
        }
        return nil
    }

    /// Builds a DisplayKey from a digest (the first 16 bytes, hex).
    package static func key(fromDigest digest: [UInt8]) -> DisplayKey? {
        guard digest.count >= 16 else { return nil }
        return DisplayKey(rawValue: hex(Array(digest.prefix(16))))
    }

    package static func hex(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef")
        var s = ""
        s.reserveCapacity(bytes.count * 2)
        for b in bytes {
            s.append(digits[Int(b >> 4)])
            s.append(digits[Int(b & 0x0F)])
        }
        return s
    }

    package static func isHexDigest(_ s: String) -> Bool {
        (16...128).contains(s.utf8.count) && s.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }

    /// The per-session identity used in layouts, undo ops and journals: the CG display UUID
    /// when known, else vendor/model/serial. Not salted (it never leaves this Mac's
    /// Application Support and is needed by the guard, which has no salt).
    package static func sessionFingerprint(uuid: String?, vendor: UInt32, model: UInt32, serial: UInt32) -> String {
        if let u = clean(uuid) { return "uuid:" + u.uppercased() }
        return "vms:\(vendor):\(model):\(serial)"
    }

    /// Masks a serial for diagnostics: "••••1234".
    package static func masked(_ serial: String) -> String {
        let s = serial.trimmingCharacters(in: .whitespaces)
        guard s.count > 4 else { return String(repeating: "•", count: s.count) }
        return "••••" + String(s.suffix(4))
    }

    private static func clean(_ s: String?) -> String? {
        guard let s else { return nil }
        var t = ""
        for scalar in s.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
        where scalar.value >= 0x20 && scalar.value < 0x7F && t.unicodeScalars.count < 128 {
            t.unicodeScalars.append(scalar)
        }
        return t.isEmpty ? nil : t
    }

    private static func cleanSerial(_ s: String?) -> String? {
        guard let t = clean(s)?.uppercased() else { return nil }
        let placeholder: Set<String> = ["0", "00000000", "0000000000", "123456789", "1234567890", "SERIAL", "NONE", "N/A"]
        if placeholder.contains(t) || t.allSatisfy({ $0 == "0" }) { return nil }
        return t
    }
}
