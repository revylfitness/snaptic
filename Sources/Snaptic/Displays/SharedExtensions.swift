import AppKit
import CoreGraphics
import SnapticKit

// Shared extensions on types no team owns (lead; R4C §3.3 item 13). Teams put other
// foreign extensions in their own files as fileprivate.

extension NSScreen {
    /// The CGDirectDisplayID behind this screen.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == id }
    }
}

extension CGDirectDisplayID {
    var isBuiltin: Bool { CGDisplayIsBuiltin(self) != 0 }
    var vendorNumber: UInt32 { CGDisplayVendorNumber(self) }
    var modelNumber: UInt32 { CGDisplayModelNumber(self) }
    /// Used only to build fingerprints; never logged or shown.
    var serialNumber: UInt32 { CGDisplaySerialNumber(self) }
    var isOnline: Bool { CGDisplayIsOnline(self) != 0 }
    var isActive: Bool { CGDisplayIsActive(self) != 0 }
    var isMain: Bool { CGDisplayIsMain(self) != 0 }
    /// The display this one mirrors (hardware or software), if any.
    var mirrorSource: CGDirectDisplayID? {
        let s = CGDisplayMirrorsDisplay(self)
        return s == kCGNullDirectDisplay ? nil : s
    }

    /// Online displays, or [] if the query fails.
    static func online() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
