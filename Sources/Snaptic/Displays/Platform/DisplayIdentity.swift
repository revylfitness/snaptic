import CryptoKit
import Foundation
import Security
import SnapticKit

// Salted, stable DisplayKeys (owner: B). PLAN §5, R5.7: the salt lives in persistent-domain
// key `SnapticDisplaySalt` (32 random bytes, never exported); keys are SHA-256(salt ‖ tier)
// truncated to 16 bytes. Stored per-display records hold only salted tier hashes.

enum DisplayIdentity {
    /// The salt, created on first use. Read from the persistent domain only, so a launch
    /// argument can't inject one.
    @MainActor static func salt() -> Data {
        if let cached = cachedSalt { return cached }
        let domain = UserDefaults.standard.persistentDomain(forName: ConfigStore<DisplaysConfig>.persistentDomainName)
        if let data = domain?[IdentityConfig.saltKey] as? Data, IdentityConfig.isValidSalt(data) {
            cachedSalt = data
            return data
        }
        var bytes = [UInt8](repeating: 0, count: IdentityConfig.saltLength)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess || !bytes.contains(where: { $0 != 0 }) {
            // Fall back to the system RNG; never an all-zero salt.
            var g = SystemRandomNumberGenerator()
            for i in bytes.indices { bytes[i] = UInt8.random(in: 1...255, using: &g) }
        }
        let data = Data(bytes)
        UserDefaults.standard.set(data, forKey: IdentityConfig.saltKey)
        cachedSalt = data
        EventLog.shared.record(.registry, "Created a new display identity salt")
        return data
    }

    @MainActor private static var cachedSalt: Data?

    /// Salted hex digest of a canonical tier string.
    static func saltedHash(_ material: String, salt: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: salt)
        hasher.update(data: Data(material.utf8))
        return Fingerprint.hex(Array(hasher.finalize()))
    }

    /// Unsalted digest, for Snaptic's own virtual identities (stable ICC profiles, PLAN §4.10(7)).
    static func unsaltedHash(_ material: String) -> String {
        Fingerprint.hex(Array(SHA256.hash(data: Data(material.utf8))))
    }

    /// Hex SHA-256 of raw EDID bytes (the tier-1 input; the bytes themselves are never kept).
    static func edidHash(_ edid: Data) -> String { unsaltedHash(Fingerprint.hex([UInt8](edid))) }

    /// The salted per-tier record for these facts.
    static func record(for facts: DisplayIdentityFacts, salt: Data) -> FingerprintRecord {
        var r = FingerprintRecord()
        for (tier, material) in Fingerprint.canonical(facts) { r[tier] = saltedHash(material, salt: salt) }
        return r
    }

    /// A key derived from the best tier (for displays never seen before).
    static func newKey(for record: FingerprintRecord) -> DisplayKey? {
        guard let tier = record.bestTier, let hex = record[tier] else { return nil }
        return DisplayKey(rawValue: String(hex.prefix(32)))
    }

    /// Resolves facts to a key: an already-stored display when the record matches (so a key
    /// survives a tier becoming readable later), else a new key. `taken` holds keys already
    /// assigned in this enumeration, so two identical monitors never share a key.
    static func key(for record: FingerprintRecord, stored: [DisplayKey: FingerprintRecord],
                    taken: Set<DisplayKey>) -> DisplayKey? {
        let available = stored.filter { !taken.contains($0.key) }
        if let k = Fingerprint.match(record, in: available) { return k }
        guard var k = newKey(for: record) else { return nil }
        // Collision with a different display (identical twins at the same tier): derive a sibling.
        var n = 1
        while taken.contains(k) || (stored[k] != nil && Fingerprint.match(record, in: [k: stored[k]!]) == nil) {
            guard n < 16, let sibling = DisplayKey(rawValue: String(unsaltedHash(k.rawValue + "#\(n)").prefix(32))) else { break }
            k = sibling
            n += 1
        }
        return k
    }
}
