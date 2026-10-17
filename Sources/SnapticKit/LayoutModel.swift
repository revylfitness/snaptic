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

    package var isHiDPI: Bool { pixelWidth >= pointWidth * 2 }
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
    /// Software dimming factor; 1.0 means none.
    package var softwareDim: Double
    /// Only Snaptic virtual screens created by the Headless recipe count as weakly visible.
    package var headlessPrimary: Bool

    package init(id: UInt32, fingerprint: String, transport: Transport, isOnline: Bool, isActive: Bool, isAsleep: Bool = false,
                 mirrorOf: UInt32?, x: Int32, y: Int32, width: Int, height: Int, rotation: Int, mode: ModeRef?,
                 underscan: Double? = nil, hdrEnabled: Bool? = nil, softwareDim: Double = 1, headlessPrimary: Bool = false) {
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
    case onlyDisplayUnsupported(UInt32)
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
