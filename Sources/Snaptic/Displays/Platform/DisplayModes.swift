import CoreGraphics
import Foundation
import SnapticKit
import SnapticShims

// Display modes (owner: B). PLAN §5: public modes from CGDisplayCopyAllDisplayModes with the
// HiDPI duplicates; CGS (hidden) modes only behind `hiddenModes`, sanity-checked in Kit.
// Nonisolated: the guard uses it too. Modes are resolved by the full ModeRef (R2C m10).

enum DisplayModes {
    private static let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary

    static func cgModes(_ id: CGDirectDisplayID) -> [CGDisplayMode] {
        (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
    }

    static func ref(_ m: CGDisplayMode) -> ModeRef {
        ModeRef(ioModeID: m.ioDisplayModeID, pixelWidth: m.pixelWidth, pixelHeight: m.pixelHeight,
                pointWidth: m.width, pointHeight: m.height, refreshMilliHz: Int((m.refreshRate * 1000).rounded()))
    }

    static func descriptor(_ m: CGDisplayMode) -> DisplayModeDescriptor {
        let flags = m.ioFlags
        return DisplayModeDescriptor(ref: ref(m), isNative: flags & DisplayModeDescriptor.nativeFlag != 0,
                                     isDefault: flags & DisplayModeDescriptor.defaultFlag != 0,
                                     isUsableForDesktop: m.isUsableForDesktopGUI(), ioFlags: flags, bitDepth: 8)
    }

    /// Public modes (deduplicated by full ModeRef).
    static func list(_ id: CGDirectDisplayID) -> [DisplayModeDescriptor] {
        var seen: Set<ModeRef> = []
        return cgModes(id).map(descriptor).filter { seen.insert($0.ref).inserted }
    }

    static func current(_ id: CGDirectDisplayID) -> DisplayModeDescriptor? {
        guard let m = CGDisplayCopyDisplayMode(id) else { return nil }
        return descriptor(m)
    }

    /// The CGDisplayMode for a ModeRef from a fresh list, or nil (never a guess).
    static func cgMode(for ref: ModeRef, display id: CGDirectDisplayID) -> CGDisplayMode? {
        let modes = cgModes(id)
        let descriptors = modes.map(descriptor)
        guard let match = DisplayModeDescriptor.resolve(ref, in: descriptors),
              let index = descriptors.firstIndex(of: match) else { return nil }
        return modes[index]
    }

    // MARK: Hidden (CGS) modes

    /// CGS modes, or nil when any record fails the sanity check (which disables the path).
    @MainActor static func hiddenList(_ id: CGDirectDisplayID, api: PrivateDisplayAPI) -> [DisplayModeDescriptor]? {
        guard let count = api.pointer(.cgsGetNumberOfDisplayModes), let describe = api.pointer(.cgsGetDisplayModeDescription),
              let records = SNCGSModes.records(display: id, countFunction: count, describeFunction: describe) else { return nil }
        var out: [DisplayModeDescriptor] = []
        for data in records {
            guard let r = CGSModeRecord.parse([UInt8](data)) else {
                EventLog.shared.record(.resolution, "Hidden mode list failed a sanity check; hidden modes are off")
                return nil
            }
            out.append(r.descriptor)
        }
        return out
    }
}
