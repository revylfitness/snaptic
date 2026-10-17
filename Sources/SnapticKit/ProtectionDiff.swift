import Foundation

// Configuration protection: desired state per presented-display set, and the diff that
// re-establishes it (owner: D). PLAN §9.6.

/// Identifies a set of presented displays: their keys, sorted, joined by "+".
package struct DisplaySetKey: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    package let rawValue: String
    package static let maxDisplays = 16

    package init?(rawValue: String) {
        let parts = rawValue.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.count <= Self.maxDisplays else { return nil }
        let keys = parts.compactMap(DisplayKey.init(rawValue:))
        guard keys.count == parts.count, parts == parts.sorted(), Set(parts).count == parts.count else { return nil }
        self.rawValue = rawValue
    }

    /// Nil for an empty set or one larger than `maxDisplays`.
    package init?(keys: Set<DisplayKey>) {
        guard !keys.isEmpty, keys.count <= Self.maxDisplays else { return nil }
        rawValue = keys.map(\.rawValue).sorted().joined(separator: "+")
    }

    package var keys: Set<DisplayKey> {
        Set(rawValue.split(separator: "+").compactMap { DisplayKey(rawValue: String($0)) })
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        guard let v = DisplaySetKey(rawValue: try c.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid display set")
        }
        self = v
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    package var description: String { rawValue }
}

/// Which properties protection enforces (each also needs its feature to be effective).
package struct ProtectedFields: Codable, Equatable, Sendable {
    package var mode: Bool
    package var origin: Bool
    package var main: Bool
    package var mirror: Bool
    package var rotation: Bool

    package init(mode: Bool = true, origin: Bool = true, main: Bool = true, mirror: Bool = true, rotation: Bool = true) {
        self.mode = mode
        self.origin = origin
        self.main = main
        self.mirror = mirror
        self.rotation = rotation
    }

    private enum CodingKeys: String, CodingKey { case mode, origin, main, mirror, rotation }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = c.lossy(.mode, true)
        origin = c.lossy(.origin, true)
        main = c.lossy(.main, true)
        mirror = c.lossy(.mirror, true)
        rotation = c.lossy(.rotation, true)
    }

    /// Drops fields whose feature isn't effective (§2.1 field gating).
    package func gated(by effective: Set<DisplayFeature>) -> ProtectedFields {
        ProtectedFields(mode: mode && effective.contains(.resolution),
                        origin: origin && effective.contains(.arrangement),
                        main: main && effective.contains(.mainDisplay),
                        mirror: mirror && effective.contains(.mirroring),
                        rotation: rotation && effective.contains(.rotation))
    }

    package var isEmpty: Bool { !(mode || origin || main || mirror || rotation) }
}

package struct ProtectedDisplayState: Codable, Equatable, Sendable {
    package var mode: ModeRef?
    package var x: Int32
    package var y: Int32
    package var rotation: Int
    /// The presented display this one mirrors; nil = not mirroring.
    package var mirrorOf: DisplayKey?
    package var isMain: Bool

    package init(mode: ModeRef?, x: Int32, y: Int32, rotation: Int, mirrorOf: DisplayKey?, isMain: Bool) {
        self.mode = mode
        self.x = x
        self.y = y
        self.rotation = rotation
        self.mirrorOf = mirrorOf
        self.isMain = isMain
    }
}

package struct ProtectionProfile: Codable, Equatable, Sendable {
    package var displays: LossyMap<DisplayKey, ProtectedDisplayState>
    /// Wall-clock seconds since 1970 (UI only).
    package var capturedAt: Double

    package init(displays: [DisplayKey: ProtectedDisplayState] = [:], capturedAt: Double = 0) {
        self.displays = LossyMap(displays)
        self.capturedAt = capturedAt
    }

    private enum CodingKeys: String, CodingKey { case displays, capturedAt }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displays = c.lossy(.displays, LossyMap())
        capturedAt = c.lossy(.capturedAt, 0)
    }

    package var setKey: DisplaySetKey? { DisplaySetKey(keys: Set(displays.values.keys)) }
}

/// A presented display as protection sees it now.
package struct LiveDisplayState: Equatable, Sendable {
    package var key: DisplayKey
    package var mode: ModeRef?
    package var x: Int32
    package var y: Int32
    package var rotation: Int
    package var mirrorOf: DisplayKey?
    package var isMain: Bool
    /// Public, desktop-usable modes (protection never uses hidden modes).
    package var availableModes: [ModeRef]

    package init(key: DisplayKey, mode: ModeRef?, x: Int32, y: Int32, rotation: Int, mirrorOf: DisplayKey?, isMain: Bool,
                 availableModes: [ModeRef]) {
        self.key = key
        self.mode = mode
        self.x = x
        self.y = y
        self.rotation = rotation
        self.mirrorOf = mirrorOf
        self.isMain = isMain
        self.availableModes = availableModes
    }
}

package enum ProtectionDelta: Codable, Equatable, Sendable {
    case mode(DisplayKey, ModeRef)
    case origin(DisplayKey, x: Int32, y: Int32)
    case rotation(DisplayKey, Int)
    case mirror(DisplayKey, of: DisplayKey?)
    case main(DisplayKey)

    package var key: DisplayKey {
        switch self {
        case .mode(let k, _), .origin(let k, _, _), .rotation(let k, _), .mirror(let k, _), .main(let k): return k
        }
    }

    package var isModeChange: Bool {
        if case .mode = self { return true }
        return false
    }
}

package enum ProtectionDiff {
    /// Captures the live state as the desired state.
    package static func capture(_ live: [LiveDisplayState], at time: Double = 0) -> ProtectionProfile {
        var d: [DisplayKey: ProtectedDisplayState] = [:]
        for l in live {
            d[l.key] = ProtectedDisplayState(mode: l.mode, x: l.x, y: l.y, rotation: l.rotation, mirrorOf: l.mirrorOf,
                                             isMain: l.isMain)
        }
        return ProtectionProfile(displays: d, capturedAt: time)
    }

    /// The same mode in the live list (ioModeID may differ after re-enumeration).
    package static func resolve(_ mode: ModeRef, in available: [ModeRef]) -> ModeRef? {
        if available.contains(mode) { return mode }
        return available.first {
            $0.pixelWidth == mode.pixelWidth && $0.pixelHeight == mode.pixelHeight && $0.pointWidth == mode.pointWidth
                && $0.pointHeight == mode.pointHeight && $0.refreshMilliHz == mode.refreshMilliHz
        }
    }

    /// Changes that re-establish `desired`, or [] when the live set differs from the
    /// profile's set or nothing differs. Hidden modes are never used.
    package static func diff(desired: ProtectionProfile, live: [LiveDisplayState], fields: ProtectedFields) -> [ProtectionDelta] {
        let liveKeys = Set(live.map(\.key))
        guard !live.isEmpty, liveKeys == Set(desired.displays.values.keys), !fields.isEmpty else { return [] }
        var deltas: [ProtectionDelta] = []
        let byKey = Dictionary(live.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let order = live.map(\.key).sorted { $0.rawValue < $1.rawValue }
        if fields.mirror {
            for k in order {
                guard let want = desired.displays[k], let now = byKey[k], want.mirrorOf != now.mirrorOf else { continue }
                if let src = want.mirrorOf, !liveKeys.contains(src) { continue }
                deltas.append(.mirror(k, of: want.mirrorOf))
            }
        }
        if fields.rotation {
            for k in order {
                guard let want = desired.displays[k], let now = byKey[k], want.rotation != now.rotation else { continue }
                guard [0, 90, 180, 270].contains(want.rotation) else { continue }
                deltas.append(.rotation(k, want.rotation))
            }
        }
        if fields.mode {
            for k in order {
                guard let want = desired.displays[k]?.mode, let now = byKey[k],
                      let target = resolve(want, in: now.availableModes), target != now.mode else { continue }
                deltas.append(.mode(k, target))
            }
        }
        if fields.origin {
            for k in order {
                guard let want = desired.displays[k], let now = byKey[k], want.mirrorOf == nil,
                      want.x != now.x || want.y != now.y else { continue }
                deltas.append(.origin(k, x: want.x, y: want.y))
            }
        }
        if fields.main, let wantMain = desired.displays.values.first(where: { $0.value.isMain })?.key,
           byKey[wantMain]?.isMain == false {
            deltas.append(.main(wantMain))
        }
        return deltas
    }

    /// Records a desired-state change from a Snaptic action (Keep, manual arrange).
    package static func updating(_ profile: ProtectionProfile, with live: [LiveDisplayState], at time: Double) -> ProtectionProfile {
        let fresh = capture(live, at: time)
        return Set(fresh.displays.values.keys) == Set(profile.displays.values.keys) ? fresh : profile
    }
}

/// "macOS keeps changing this arrangement": our state overwritten by a non-Snaptic
/// reconfiguration twice within 30 s stops protection for that set (§9.6).
package struct ProtectionFightTracker: Equatable, Sendable {
    package static let window: Double = 30
    package static let threshold = 2
    private var overwrites: [DisplaySetKey: [Double]] = [:]
    package private(set) var stopped: Set<DisplaySetKey> = []

    package init() {}

    /// Returns true when this overwrite means protection should stop for the set.
    package mutating func noteOverwrite(_ set: DisplaySetKey, at now: Double) -> Bool {
        var list = (overwrites[set] ?? []).filter { now - $0 <= Self.window && now >= $0 }
        list.append(now)
        overwrites[set] = list
        if list.count >= Self.threshold {
            stopped.insert(set)
            return true
        }
        return false
    }

    package func isStopped(_ set: DisplaySetKey) -> Bool { stopped.contains(set) }

    /// The user re-captured or re-enabled protection for the set.
    package mutating func reset(_ set: DisplaySetKey) {
        overwrites[set] = nil
        stopped.remove(set)
    }

    package mutating func resetAll() {
        overwrites = [:]
        stopped = []
    }
}
