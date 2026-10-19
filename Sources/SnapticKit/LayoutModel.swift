import Foundation

// Live display layout as plain values (owner: B). Used for prediction, invariants,
// undo planning and the guard protocol. Display ids are CGDirectDisplayID values.

package enum Transport: String, Codable, CaseIterable, Sendable {
    case builtin, wired, displayLink, airplay, sidecar, snapticVirtual, foreignVirtual
}

/// A display mode, identified by its full descriptor (ioModeID alone isn't unique).
package struct ModeRef: Codable, Hashable, Sendable {
    package var ioModeID: Int32
    package var pixelWidth: Int
    package var pixelHeight: Int
    package var pointWidth: Int
    package var pointHeight: Int
    package var refreshMilliHz: Int

    package init(ioModeID: Int32, pixelWidth: Int, pixelHeight: Int, pointWidth: Int, pointHeight: Int, refreshMilliHz: Int) {
        self.ioModeID = ioModeID
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.refreshMilliHz = refreshMilliHz
    }

    package var isHiDPI: Bool { pointWidth > 0 && pixelWidth >= pointWidth * 2 }

    /// Same mode, ignoring the ioModeID hint and allowing ±10 mHz refresh rounding.
    package func sameShape(as other: ModeRef) -> Bool {
        pixelWidth == other.pixelWidth && pixelHeight == other.pixelHeight && pointWidth == other.pointWidth
            && pointHeight == other.pointHeight && abs(refreshMilliHz - other.refreshMilliHz) <= 10
    }
}

package struct LayoutEntry: Codable, Equatable, Sendable {
    package var id: UInt32
    package var fingerprint: String
    package var transport: Transport
    package var isOnline: Bool
    package var isActive: Bool
    package var isAsleep: Bool
    /// Source display this one mirrors (hardware or software mirror), if any.
    package var mirrorOf: UInt32?
    package var x: Int32
    package var y: Int32
    /// Points, after rotation.
    package var width: Int
    package var height: Int
    package var rotation: Int
    package var mode: ModeRef?
    package var underscan: Double?
    package var hdrEnabled: Bool?
    /// Software dimming factor (gamma, or overlay when `overlayDim` isn't reported); 1.0 means none.
    package var softwareDim: Double
    /// Only Snaptic virtual screens created by the Headless recipe count as weakly visible.
    package var headlessPrimary: Bool
    /// Overlay dimming factor (1 − overlay alpha); 1.0 means no overlay.
    package var overlayDim: Double = 1
    /// True when Snaptic disabled this display (it stays online but inactive).
    package var disabledBySnaptic: Bool = false

    package init(id: UInt32, fingerprint: String, transport: Transport, isOnline: Bool, isActive: Bool, isAsleep: Bool = false,
                 mirrorOf: UInt32?, x: Int32, y: Int32, width: Int, height: Int, rotation: Int, mode: ModeRef?,
                 underscan: Double? = nil, hdrEnabled: Bool? = nil, softwareDim: Double = 1, headlessPrimary: Bool = false,
                 overlayDim: Double = 1, disabledBySnaptic: Bool = false) {
        self.id = id
        self.fingerprint = fingerprint
        self.transport = transport
        self.isOnline = isOnline
        self.isActive = isActive
        self.isAsleep = isAsleep
        self.mirrorOf = mirrorOf
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.mode = mode
        self.underscan = underscan
        self.hdrEnabled = hdrEnabled
        self.softwareDim = softwareDim
        self.headlessPrimary = headlessPrimary
        self.overlayDim = overlayDim
        self.disabledBySnaptic = disabledBySnaptic
    }
}

package struct LayoutSnapshot: Codable, Equatable, Sendable {
    package var entries: [LayoutEntry]
    package var mainID: UInt32
    package init(entries: [LayoutEntry], mainID: UInt32) {
        self.entries = entries
        self.mainID = mainID
    }
    package func entry(_ id: UInt32) -> LayoutEntry? { entries.first { $0.id == id } }

    package func index(of id: UInt32) -> Int? { entries.firstIndex { $0.id == id } }

    /// The entry for a fingerprint, if exactly one online display has it.
    package func entry(fingerprint: String) -> LayoutEntry? {
        guard !fingerprint.isEmpty else { return nil }
        let matches = entries.filter { $0.fingerprint == fingerprint }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Sorted fingerprints of online displays other than Snaptic's own virtual screens
    /// (those vanish with the app, so journals don't compare them).
    package var physicalFingerprints: [String] {
        entries.filter { $0.isOnline && $0.transport != .snapticVirtual }.map(\.fingerprint).sorted()
    }
}

extension LayoutEntry {
    /// Enabled = shows something: active, or a member of a mirror set (hardware mirror
    /// members aren't in the active list).
    package var isEnabled: Bool { isOnline && (isActive || mirrorOf != nil) }

    /// The visible brightness factor after every software dimming layer.
    package var effectiveDim: Double { min(max(softwareDim, 0), max(overlayDim, 0)) }

    package var isPhysical: Bool { transport == .builtin || transport == .wired }

    package var isRotatedSideways: Bool { rotation == 90 || rotation == 270 }
}

extension DisplayChange {
    /// Which property this change writes.
    package var property: DisplayProperty {
        switch self {
        case .mode: return .mode
        case .origin: return .origin
        case .mirror: return .mirrorOf
        case .enabled: return .enabled
        case .main: return .main
        case .rotation: return .rotation
        case .underscan: return .underscan
        case .hdr: return .hdr
        }
    }

    /// Changes applied through MonitorPanel (no CG configuration scope).
    package var isMonitorPanel: Bool {
        switch self {
        case .rotation, .underscan, .hdr: return true
        default: return false
        }
    }

    /// Changes that can only make more of the screen visible (invariant 6 bypass).
    package var isVisibilityRestoring: Bool {
        switch self {
        case .enabled(_, true), .mirror(_, of: nil): return true
        default: return false
        }
    }

    /// The scope Keep re-applies this change with (R5.2): mirrors and enable state are
    /// session-only; modes, origins and main persist. MonitorPanel changes have no scope.
    package var keepScope: FinalScope? {
        switch self {
        case .mode, .origin, .main: return .permanently
        case .mirror, .enabled: return .forSession
        case .rotation, .underscan, .hdr: return nil
        }
    }
}

/// A requested change, as data, so invariants can be checked before applying.
package enum DisplayChange: Codable, Equatable, Sendable {
    case mode(UInt32, ModeRef)
    case origin(UInt32, x: Int32, y: Int32)
    case mirror(UInt32, of: UInt32?)
    case enabled(UInt32, Bool)
    case main(UInt32)
    case rotation(UInt32, Int)
    case underscan(UInt32, Double)
    case hdr(UInt32, Bool)

    package var displayID: UInt32 {
        switch self {
        case .mode(let id, _), .origin(let id, _, _), .mirror(let id, _), .enabled(let id, _), .main(let id),
             .rotation(let id, _), .underscan(let id, _), .hdr(let id, _):
            return id
        }
    }
}

package enum InvariantViolation: Codable, Equatable, Sendable {
    case noVisibleDisplay
    case noPanelHost
    case dimToBlackWithoutOtherVisible(UInt32)
    case mainNotVisible(UInt32)
    case guardNotArmed
    /// The change can't run unattended on the only strongly visible display (R5.2),
    /// or needs a capability the safety helper lacks.
    case onlyDisplayUnsupported(UInt32)
}

extension InvariantViolation {
    /// A short, user-facing reason.
    package var message: String {
        switch self {
        case .noVisibleDisplay: return L("This would leave no usable display.")
        case .noPanelHost: return L("This would leave nowhere to show the confirmation.")
        case .dimToBlackWithoutOtherVisible: return L("Dimming to black needs another display that stays visible.")
        case .mainNotVisible: return L("The main display has to stay visible.")
        case .guardNotArmed: return L("Safety helper unavailable.")
        case .onlyDisplayUnsupported: return L("This can’t change unattended on your only visible display.")
        }
    }
}

package enum FinalScope: String, Codable, Sendable { case permanently, forSession }

/// What the parent tells the guard about each display (R3C §5.2).
package struct GuardDisplayClass: Codable, Equatable, Sendable {
    package var id: UInt32
    package var transport: Transport
    package var strong: Bool
    package var weak: Bool
    /// Smart HiDPI / association host for this display, if any (for hang handling).
    package var hostPID: Int32?
    package var hostStartTime: UInt64?
    package init(id: UInt32, transport: Transport, strong: Bool, weak: Bool, hostPID: Int32? = nil, hostStartTime: UInt64? = nil) {
        self.id = id
        self.transport = transport
        self.strong = strong
        self.weak = weak
        self.hostPID = hostPID
        self.hostStartTime = hostStartTime
    }
}
