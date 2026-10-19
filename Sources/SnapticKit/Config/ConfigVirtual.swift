import Foundation

// Virtual screens and Smart HiDPI settings (owner: D). PLAN §9.2–§9.5, §3.4 (≤ 8 screens).

/// A Smart HiDPI pair for one physical display (keyed by the physical display's key).
package struct SmartHiDPIPair: Codable, Equatable, Sendable {
    /// Stable id of the backing virtual screen (its unsalted serial seed is the physical fingerprint).
    package var specID: StableID
    /// The user kept the pair (re-established through the planner; first enable is a trial).
    package var kept: Bool
    /// The chosen virtual mode (points, HiDPI).
    package var mode: VirtualMode
    /// HDR (PQ) virtual modes (`hdrVirtual`).
    package var hdr: Bool
    /// The HiDPI check failed once: create with backing for the initial mode only (R5.6).
    package var limitToInitial: Bool

    package init(specID: StableID = StableID(), kept: Bool = false, mode: VirtualMode, hdr: Bool = false, limitToInitial: Bool = false) {
        self.specID = specID
        self.kept = kept
        self.mode = mode
        self.hdr = hdr
        self.limitToInitial = limitToInitial
    }

    private enum CodingKeys: String, CodingKey { case specID, kept, mode, hdr, limitToInitial }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        specID = try c.decode(StableID.self, forKey: .specID)
        kept = c.lossy(.kept, false)
        mode = try c.decode(VirtualMode.self, forKey: .mode)
        hdr = c.lossy(.hdr, false)
        limitToInitial = c.lossy(.limitToInitial, false)
    }
}

/// Where a virtual screen sat (global points, main display at 0,0) when it was last connected.
package struct VirtualOrigin: Codable, Equatable, Sendable {
    package var x: Int32
    package var y: Int32

    package static let limit: Int32 = 32_768

    package init(x: Int32, y: Int32) {
        self.x = x
        self.y = y
    }

    package var clamped: VirtualOrigin {
        VirtualOrigin(x: min(Self.limit, max(-Self.limit, x)), y: min(Self.limit, max(-Self.limit, y)))
    }
}

package struct VirtualConfig: ConfigModel {
    package var screens: [VirtualScreenSpec]
    /// Manual connection state per screen (used at launch only with `recreateOnLaunch`).
    package var connected: LossyMap<StableID, Bool>
    package var smartHiDPI: LossyMap<DisplayKey, SmartHiDPIPair>
    /// Restore the arrangement after a virtual screen connects (AS).
    package var restoreLayoutAfterConnect: Bool
    /// Reconnect virtual screens after wake (rebind semantics; recreate only on mismatch).
    package var reconnectAfterWake: Bool
    /// Disconnect on lock or screen saver and reconnect on return (session dictionary checked).
    package var disconnectOnLock: Bool
    /// Last arrangement position per screen, restored after it connects (`restoreLayoutAfterConnect`).
    package var lastOrigins: LossyMap<StableID, VirtualOrigin>

    package static let maxScreens = 8
    package static let maxPairs = 16

    package init() {
        screens = []
        connected = LossyMap()
        smartHiDPI = LossyMap()
        restoreLayoutAfterConnect = true
        reconnectAfterWake = true
        disconnectOnLock = false
        lastOrigins = LossyMap()
    }

    private enum CodingKeys: String, CodingKey {
        case screens, connected, smartHiDPI, restoreLayoutAfterConnect, reconnectAfterWake, disconnectOnLock, lastOrigins
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        screens = c.lossyArray(.screens, [])
        connected = c.lossy(.connected, LossyMap())
        smartHiDPI = c.lossy(.smartHiDPI, LossyMap())
        restoreLayoutAfterConnect = c.lossy(.restoreLayoutAfterConnect, true)
        reconnectAfterWake = c.lossy(.reconnectAfterWake, true)
        disconnectOnLock = c.lossy(.disconnectOnLock, false)
        lastOrigins = c.lossy(.lastOrigins, LossyMap())
    }

    package func sanitized() -> VirtualConfig { sanitized(soc: .appleEntry) }

    package func sanitized(soc: SoCClass) -> VirtualConfig {
        var c = self
        var ids = Set<StableID>()
        c.screens = screens.filter { ids.insert($0.id).inserted }.prefix(Self.maxScreens).map { $0.sanitized(soc: soc) }
        let live = Set(c.screens.map(\.id))
        c.connected.dropUnknown(keepingAtMost: 0)
        c.connected = LossyMap(c.connected.values.filter { live.contains($0.key) })
        c.lastOrigins.dropUnknown(keepingAtMost: 0)
        c.lastOrigins = LossyMap(c.lastOrigins.values.filter { live.contains($0.key) }.mapValues(\.clamped))
        c.smartHiDPI.dropUnknown(keepingAtMost: 0)
        var pairs = c.smartHiDPI.values
        let limit = SoCCaps.maxHiDPIPointDimension(soc)
        for (k, original) in pairs {
            var p = original
            p.mode.hiDPI = true
            p.mode.refreshMilliHz = min(VirtualScreenSpec.maxRefreshMilliHz, max(VirtualScreenSpec.minRefreshMilliHz, p.mode.refreshMilliHz))
            if p.mode.width < VirtualScreenSpec.minModeDimension || p.mode.height < VirtualScreenSpec.minModeDimension
                || p.mode.width > limit || p.mode.height > limit || ids.contains(p.specID) {
                pairs[k] = nil
            } else {
                pairs[k] = p
            }
        }
        if pairs.count > Self.maxPairs {
            let keep = Set(pairs.keys.sorted { $0.rawValue < $1.rawValue }.prefix(Self.maxPairs))
            pairs = pairs.filter { keep.contains($0.key) }
        }
        c.smartHiDPI = LossyMap(pairs)
        return c
    }

    package func screen(_ id: StableID) -> VirtualScreenSpec? { screens.first { $0.id == id } }

    /// Estimated backing of every user screen (for the budget).
    package var totalBackingBytes: UInt64 {
        screens.reduce(0) { total, screen in
            let (sum, overflow) = total.addingReportingOverflow(screen.estimatedBackingBytes)
            return overflow ? UInt64.max : sum
        }
    }
}
