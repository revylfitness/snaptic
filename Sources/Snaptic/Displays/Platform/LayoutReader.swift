import ApplicationServices
import CoreGraphics
import Foundation
import SnapticKit

// Reads the live CG layout into a Kit LayoutSnapshot (owner: B). Nonisolated, so the guard
// and the app share it. Enumeration is CGGetOnlineDisplayList: hardware-mirror members aren't
// in the active list (PLAN §4.1). Fingerprints are Kit session fingerprints (CG UUID).

final class LayoutReader: @unchecked Sendable {
    /// What the caller knows that CG doesn't (dims, Snaptic-disabled displays, live hosts).
    struct Overlay {
        var transports: [UInt32: Transport] = [:]
        var softwareDim: [UInt32: Double] = [:]
        var overlayDim: [UInt32: Double] = [:]
        var headless: Set<UInt32> = []
        var disabledBySnaptic: Set<String> = []
        var underscan: [UInt32: Double] = [:]
        var hdrEnabled: [UInt32: Bool] = [:]

        init() {}
    }

    /// 'virt': CoreGraphics' model number for virtual and headless displays (Chromium).
    static let virtualModel: UInt32 = 0x7669_7274
    /// Snaptic's virtual display vendor id (D's hosts).
    static let snapticVendor: UInt32 = 0xD354

    init() {}

    func read(_ overlay: Overlay = Overlay()) -> LayoutSnapshot {
        var entries: [LayoutEntry] = []
        var mainID: UInt32 = CGMainDisplayID()
        for id in CGDirectDisplayID.online().prefix(64) {
            let bounds = CGDisplayBounds(id)
            let fp = Self.fingerprint(id)
            let modeRef = CGDisplayCopyDisplayMode(id).map(DisplayModes.ref)
            var e = LayoutEntry(id: id, fingerprint: fp, transport: overlay.transports[id] ?? Self.baseTransport(id),
                                isOnline: true, isActive: id.isActive, isAsleep: CGDisplayIsAsleep(id) != 0,
                                mirrorOf: id.mirrorSource,
                                x: Int32(clamping: Int(bounds.origin.x.rounded())), y: Int32(clamping: Int(bounds.origin.y.rounded())),
                                width: Int(bounds.width.rounded()), height: Int(bounds.height.rounded()),
                                rotation: Invariants.normalizedRotation(Int(CGDisplayRotation(id).rounded())),
                                mode: modeRef, underscan: overlay.underscan[id], hdrEnabled: overlay.hdrEnabled[id],
                                softwareDim: overlay.softwareDim[id] ?? 1, headlessPrimary: overlay.headless.contains(id))
            e.overlayDim = overlay.overlayDim[id] ?? 1
            e.disabledBySnaptic = overlay.disabledBySnaptic.contains(fp)
            entries.append(e)
        }
        if !entries.contains(where: { $0.id == mainID }) { mainID = entries.first?.id ?? 0 }
        return LayoutSnapshot(entries: entries, mainID: mainID)
    }

    /// Transport from public facts only (the app refines AirPlay, Sidecar, DisplayLink, Snaptic virtuals).
    static func baseTransport(_ id: CGDirectDisplayID) -> Transport {
        if id.isBuiltin { return .builtin }
        if id.modelNumber == virtualModel { return .foreignVirtual }
        return .wired
    }

    static func uuid(_ id: CGDirectDisplayID) -> String? {
        guard let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let s = CFUUIDCreateString(kCFAllocatorDefault, u) else { return nil }
        return s as String
    }

    static func fingerprint(_ id: CGDirectDisplayID) -> String {
        Fingerprint.sessionFingerprint(uuid: uuid(id), vendor: id.vendorNumber, model: id.modelNumber, serial: id.serialNumber)
    }
}
