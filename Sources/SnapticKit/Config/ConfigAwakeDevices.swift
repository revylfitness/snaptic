import Foundation

// Awake device config (owner: J; PLAN 0.3 §2.14, R5-3): activity and Drive Alive settings, the volume key, and the
// rules for Awake's salted identifiers (router MACs, USB serials).

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

    package static let maxVolumes = 16
    package static let maxNameScalars = 64

    /// ≤ 16 volumes (enabled ones first, then by key), names cleaned to ≤ 64 scalars, the interval clamped to
    /// 30...600, unknown (non-UUID) keys dropped.
    package func sanitized() -> DriveAliveConfig {
        var c = self
        c.intervalSeconds = DriveAlivePolicy.clampedInterval(intervalSeconds)
        let ordered = volumes.values.sorted { a, b in
            a.value.enabled != b.value.enabled ? a.value.enabled : a.key.rawValue < b.key.rawValue
        }
        var kept: [VolumeUUIDKey: DriveAliveVolume] = [:]
        for (key, volume) in ordered.prefix(Self.maxVolumes) {
            var v = volume
            v.name = TextSanitizer.clean(volume.name, maxScalars: Self.maxNameScalars)
            kept[key] = v
        }
        c.volumes = LossyMap(kept)
        return c
    }

    /// Volumes the user turned on.
    package var enabledVolumes: Set<VolumeUUIDKey> {
        Set(volumes.values.compactMap { $0.value.enabled ? $0.key : nil })
    }
}

/// Awake's salt for stored identifiers (PLAN 0.3 §2.7, §3.6): 32 random bytes in its own persistent-domain key,
/// created on first use, never exported (same rules as `SnapticDisplaySalt`, R5.7).
package enum AwakeSaltRules {
    package static let key = "SnapticAwakeSalt"
    package static let length = 32

    package static func isValid(_ data: Data?) -> Bool {
        guard let data, data.count == length else { return false }
        return data.contains { $0 != 0 }
    }
}

/// The canonical text each salted identifier hashes (SHA-256(salt ‖ material), in the app). One definition, so the
/// rule editor and the live sources always hash the same bytes.
package enum AwakeHashMaterial {
    /// "router:aa:bb:cc:dd:ee:ff"; nil unless the MAC normalizes.
    package static func router(mac: String) -> String? {
        NetworkMath.normalizeMAC(mac).map { "router:" + $0 }
    }

    /// "usb:<serial>": surrounding whitespace and NULs trimmed, ≤ 128 scalars; nil when empty or only zeros (many
    /// devices report "0" or "000000" for "no serial").
    package static func usbSerial(_ serial: String) -> String? {
        let trimmed = serial.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= 128, trimmed.contains(where: { $0 != "0" }) else { return nil }
        return "usb:" + trimmed
    }

    /// "btaudio:<device>" for a CoreAudio Bluetooth device UID. Headsets publish one input and one output device
    /// ("AC-1D-DF-00-11-22:input", "…:output"), so the UID is reduced to its device part: the leading Bluetooth
    /// address when there is one (normalized like a MAC), else the UID without a trailing ":input"/":output". nil when
    /// nothing is left or the UID is longer than 256 scalars.
    package static func bluetoothAudio(uid: String) -> String? {
        let trimmed = uid.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= 256 else { return nil }
        let head = String(trimmed.prefix(17))
        if head.count == 17, let mac = NetworkMath.normalizeMAC(head) {
            let rest = trimmed.dropFirst(17)
            if rest.isEmpty || rest.hasPrefix(":") { return "btaudio:" + mac }
        }
        var device = trimmed
        for suffix in [":input", ":output"] where device.lowercased().hasSuffix(suffix) {
            device = String(device.dropLast(suffix.count))
        }
        return device.isEmpty ? nil : "btaudio:" + device
    }

    /// "bthid:<address>" for a Bluetooth input device whose IORegistry `SerialNumber` (or `DeviceAddress`) is its
    /// Bluetooth address; otherwise "bthid:v<vendor>p<product>" (two identical models then match each other); nil
    /// when neither is known.
    package static func bluetoothInput(address: String?, vendor: Int, product: Int) -> String? {
        if let address, let mac = NetworkMath.normalizeMAC(address) { return "bthid:" + mac }
        guard vendor > 0 || product > 0, (0...0xFFFF).contains(vendor), (0...0xFFFF).contains(product) else { return nil }
        return "bthid:v\(vendor)p\(product)"
    }

    /// Lowercase hex of a digest (64 characters for SHA-256).
    package static func hex(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef")
        return String(bytes.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 0x0F)]] })
    }
}

/// The TCC-free Bluetooth presence rules (PLAN 0.3 §2.8, Beta, [PA] Bluetooth row): Bluetooth audio from CoreAudio's
/// device list by transport type, Bluetooth input devices from IORegistry `IOHIDDevice` properties by `Transport`.
/// IOBluetooth (Bluetooth TCC) is never used, and no HID device is opened (Input Monitoring).
package enum BluetoothPresenceRules {
    /// kAudioDeviceTransportTypeBluetooth ('blue') and kAudioDeviceTransportTypeBluetoothLE ('blea').
    package static let audioTransportTypes: Set<UInt32> = [0x626C_7565, 0x626C_6561]

    /// IOHIDDevice `Transport`: "Bluetooth", "Bluetooth Low Energy" (any case); not "USB", "SPI", "Virtual", ….
    package static func isBluetoothTransport(_ transport: String?) -> Bool {
        guard let transport else { return false }
        return transport.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("bluetooth")
    }

    /// Picker names, cleaned; the fallback when a device has none.
    package static func displayName(_ raw: String?, fallback: String) -> String {
        let clean = TextSanitizer.clean(raw ?? "", maxScalars: 64).trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? fallback : clean
    }
}
