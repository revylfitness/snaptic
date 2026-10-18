import Foundation

// Stub (owner: J). Hand-written by the lead in step 0 from PLAN 0.3 §2.14 + R5-3 (kind S): the declared lossy
// decoders and the key validation are real.

/// Canonical uppercase UUID (code M13).
package struct VolumeUUIDKey: RawRepresentable, Hashable, Sendable, Codable {
    package let rawValue: String

    /// nil unless UUID(uuidString:) parses.
    package init?(rawValue: String) {
        guard let uuid = UUID(uuidString: rawValue) else { return nil }
        self.rawValue = uuid.uuidString.uppercased()
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let key = VolumeUUIDKey(rawValue: try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid volume UUID")
        }
        self = key
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

package struct AwakeActivityConfig: ConfigModel {
    /// 1; 1...8, Snaptic's continuous clock from the first action (N10).
    package var stopAfterHours: Int

    package init() { stopAfterHours = 1 }

    private enum CodingKeys: String, CodingKey { case stopAfterHours }

    /// Lossy per field (R5-3).
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stopAfterHours = c.lossy(.stopAfterHours, 1)
    }

    package func sanitized() -> AwakeActivityConfig {
        var c = self
        c.stopAfterHours = min(8, max(1, stopAfterHours))
        return c
    }
}

package struct DriveAliveVolume: Codable, Equatable, Sendable {
    package var name: String
    package var enabled: Bool
    /// Set by the first write after the UI turned the volume on (§2.9).
    package var firstWriteDone: Bool = false

    package init(name: String, enabled: Bool, firstWriteDone: Bool = false) {
        self.name = name
        self.enabled = enabled
        self.firstWriteDone = firstWriteDone
    }

    private enum CodingKeys: String, CodingKey { case name, enabled, firstWriteDone }

    /// Lossy per field (rule 9).
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lossy(.name, "")
        enabled = c.lossy(.enabled, false)
        firstWriteDone = c.lossy(.firstWriteDone, false)
    }
}

package struct DriveAliveConfig: ConfigModel {
    /// ≤ 16.
    package var volumes: LossyMap<VolumeUUIDKey, DriveAliveVolume>
    /// 120, 30...600 ("Check drives every").
    package var intervalSeconds: Int
    /// C9, "Also when no session is running".
    package var evenWithoutSession: Bool

    package init() {
        volumes = LossyMap()
        intervalSeconds = 120
        evenWithoutSession = false
    }

    private enum CodingKeys: String, CodingKey { case volumes, intervalSeconds, evenWithoutSession }

    /// Lossy per field (R5-3; `volumes` is a LossyMap).
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volumes = c.lossy(.volumes, LossyMap())
        intervalSeconds = c.lossy(.intervalSeconds, 120)
        evenWithoutSession = c.lossy(.evenWithoutSession, false)
    }

    package func sanitized() -> DriveAliveConfig { self }
}
