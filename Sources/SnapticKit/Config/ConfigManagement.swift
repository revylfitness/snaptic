import Foundation

// Arrangement, power and protection settings (owner: D). PLAN §9.6.

/// What the switch in a display block's header does (§9.6).
package enum HeaderPowerSwitch: String, Codable, CaseIterable, Sendable {
    case none
    /// Soft disconnect / connect (needs `disconnect`).
    case disconnect
    /// DDC standby / power-on (needs `ddcPower`).
    case ddcStandby
}

package struct ManagementConfig: ConfigModel {
    /// Desired state per presented-display set.
    package var protection: LossyMap<DisplaySetKey, ProtectionProfile>
    package var protectionFields: ProtectedFields
    /// "My monitor has no DDC": allow auto-disconnect without a DDC power read (R5.7).
    package var autoDisconnectWithoutDDC: Bool
    /// Snap displays to each other's edges when dragging on the arrangement canvas.
    package var snapArrangement: Bool

    package static let maxProfiles = 32

    package init() {
        protection = LossyMap()
        protectionFields = ProtectedFields()
        autoDisconnectWithoutDDC = false
        snapArrangement = true
    }

    private enum CodingKeys: String, CodingKey { case protection, protectionFields, autoDisconnectWithoutDDC, snapArrangement }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        protection = c.lossy(.protection, LossyMap())
        protectionFields = c.lossy(.protectionFields, ProtectedFields())
        autoDisconnectWithoutDDC = c.lossy(.autoDisconnectWithoutDDC, false)
        snapArrangement = c.lossy(.snapArrangement, true)
    }

    package func sanitized() -> ManagementConfig {
        var c = self
        c.protection.dropUnknown(keepingAtMost: 0)
        var profiles = c.protection.values.filter { entry in
            // A profile must describe exactly its set.
            Set(entry.value.displays.values.keys) == entry.key.keys
        }
        if profiles.count > Self.maxProfiles {
            // Keep the most recently captured ones.
            let keep = Set(profiles.sorted { ($0.value.capturedAt, $0.key.rawValue) > ($1.value.capturedAt, $1.key.rawValue) }
                .prefix(Self.maxProfiles).map(\.key))
            profiles = profiles.filter { keep.contains($0.key) }
        }
        for (k, p) in profiles {
            var fixed = p
            fixed.displays.dropUnknown(keepingAtMost: 0)
            if !fixed.capturedAt.isFinite { fixed.capturedAt = 0 }
            profiles[k] = fixed
        }
        c.protection = LossyMap(profiles)
        return c
    }
}

package struct PerDisplayManagement: ConfigModel {
    package var powerSwitch: HeaderPowerSwitch
    /// Never auto-disconnect this (built-in) display.
    package var ignoreForAutoDisconnect: Bool
    /// 0.2's "prevent display sleep while connected". Ignored since 0.3 (migration M1 moved it to Awake, §2.13); kept
    /// decoded and encoded until 0.4 so a 0.2 downgrade still reads it.
    package var preventSleep: Bool

    package init() {
        powerSwitch = .none
        ignoreForAutoDisconnect = false
        preventSleep = false
    }

    private enum CodingKeys: String, CodingKey { case powerSwitch, ignoreForAutoDisconnect, preventSleep }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        powerSwitch = c.lossy(.powerSwitch, .none)
        ignoreForAutoDisconnect = c.lossy(.ignoreForAutoDisconnect, false)
        preventSleep = c.lossy(.preventSleep, false)
    }

    package func sanitized() -> PerDisplayManagement { self }
}
