import Foundation

// Display identity settings (owner: B). PLAN §5, §3.4, R5.7: per-display names and
// fingerprints (salted hashes only), and the rules for the DisplayKey salt, which lives in
// its own persistent-domain key and is never part of DisplaysConfig, exports or imports.

package struct IdentityConfig: ConfigModel {
    package static let forgetRange = 7...3650
    /// Offline displays not seen for this many days are forgotten (PLAN Appendix C 7.14).
    package var forgetAfterDays: Int
    /// List displays that are offline on the Display Names page.
    package var showOfflineDisplays: Bool

    package init() {
        forgetAfterDays = 90
        showOfflineDisplays = true
    }

    private enum CodingKeys: String, CodingKey { case forgetAfterDays, showOfflineDisplays }

    package init(from decoder: Decoder) throws {
        let d = IdentityConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        forgetAfterDays = c.lossy(.forgetAfterDays, d.forgetAfterDays)
        showOfflineDisplays = c.lossy(.showOfflineDisplays, d.showOfflineDisplays)
    }

    package func sanitized() -> IdentityConfig {
        var c = self
        c.forgetAfterDays = min(max(forgetAfterDays, Self.forgetRange.lowerBound), Self.forgetRange.upperBound)
        return c
    }

    // MARK: Salt rules

    /// Persistent-domain key of the 32-byte DisplayKey salt (R5.7). Never exported.
    package static let saltKey = "SnapticDisplaySalt"
    package static let saltLength = 32

    package static func isValidSalt(_ data: Data?) -> Bool {
        guard let data, data.count == saltLength else { return false }
        return data.contains { $0 != 0 }
    }

    /// Displays to forget: offline (not in `online`) and last seen more than `forgetAfterDays` ago.
    package func keysToForget(_ perDisplay: [DisplayKey: PerDisplayIdentity], online: Set<DisplayKey>,
                              now: Double) -> [DisplayKey] {
        let limit = Double(forgetAfterDays) * 86_400
        return perDisplay.compactMap { key, identity in
            guard !online.contains(key), let seen = identity.lastSeen, now - seen > limit else { return nil }
            return key
        }.sorted { $0.rawValue < $1.rawValue }
    }
}

/// Menu order and visibility live in MenuConfig (FIXES-R1 B7); old `menuOrder` /
/// `hiddenInMenu` keys in saved settings are ignored on decode.
package struct PerDisplayIdentity: ConfigModel {
    package static let maxNameScalars = 64
    package static let maxSymbolScalars = 64

    /// The user's name for this display; nil = the EDID/system name.
    package var customName: String?
    /// SF Symbol for the menu header; nil = by transport.
    package var symbol: String?
    /// Salted tier hashes (never raw serials).
    package var fingerprint: FingerprintRecord
    /// Unix seconds, day granularity (so it isn't rewritten on every reconfigure).
    package var lastSeen: Double?
    /// The name last read from the display, for listing it while offline (sanitized).
    package var lastKnownName: String?

    package init() {
        customName = nil
        symbol = nil
        fingerprint = FingerprintRecord()
        lastSeen = nil
        lastKnownName = nil
    }

    private enum CodingKeys: String, CodingKey {
        case customName, symbol, fingerprint, lastSeen, lastKnownName
    }

    package init(from decoder: Decoder) throws {
        let d = PerDisplayIdentity()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        customName = (try? c.decodeIfPresent(String.self, forKey: .customName)) ?? nil
        symbol = (try? c.decodeIfPresent(String.self, forKey: .symbol)) ?? nil
        fingerprint = c.lossy(.fingerprint, d.fingerprint)
        lastSeen = (try? c.decodeIfPresent(Double.self, forKey: .lastSeen)) ?? nil
        lastKnownName = (try? c.decodeIfPresent(String.self, forKey: .lastKnownName)) ?? nil
    }

    package func sanitized() -> PerDisplayIdentity {
        var c = self
        c.customName = Self.cleanName(customName)
        c.lastKnownName = Self.cleanName(lastKnownName)
        if let s = symbol {
            let ok = !s.isEmpty && s.unicodeScalars.count <= Self.maxSymbolScalars
                && s.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == ".") }
            c.symbol = ok ? s : nil
        }
        if let t = lastSeen, !(t.isFinite && t >= 0) { c.lastSeen = nil }
        return c
    }

    /// Sanitized display name (TextSanitizer, ≤ 64 scalars), nil when empty.
    package static func cleanName(_ name: String?) -> String? {
        guard let name else { return nil }
        let t = TextSanitizer.clean(name, maxScalars: maxNameScalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Rounds a time to the start of its UTC day (lastSeen granularity).
    package static func day(_ unixSeconds: Double) -> Double { (unixSeconds / 86_400).rounded(.down) * 86_400 }
}
