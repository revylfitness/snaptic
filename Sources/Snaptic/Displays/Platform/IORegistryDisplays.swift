import ApplicationServices
import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics
import SnapticKit

// IOKit enumeration for display identity (owner: B). PLAN §5, R2C §8 c5: every io_object_t
// released, iterators drained, CF types checked with CFGetTypeID. Nothing here is logged.

/// What IOKit and CoreDisplay tell us about one display, beyond CoreGraphics.
struct IORegistryDisplayFacts: Equatable {
    var edid: Data?
    /// Apple silicon framebuffers expose "EDID UUID" instead of raw EDID.
    var edidUUID: String?
    var alphanumericSerial: String?
    var productName: String?
    var location: String?
    var isVirtualDevice = false
    var isAirPlay = false
    /// A framebuffer or driver class hinting at DisplayLink (UI-only label).
    var looksLikeDisplayLink = false
}

enum IORegistryDisplays {
    typealias InfoDictionaryFn = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?

    /// Gathers facts for one display. `coreDisplayInfo` is the resolved
    /// CoreDisplay_DisplayCreateInfoDictionary (+1), or nil.
    static func facts(for id: CGDirectDisplayID, coreDisplayInfo: InfoDictionaryFn?) -> IORegistryDisplayFacts {
        var f = IORegistryDisplayFacts()
        var info: [String: Any] = [:]
        if let fn = coreDisplayInfo, let dict = fn(id)?.takeRetainedValue() {
            info = (dict as NSDictionary) as? [String: Any] ?? [:]
        }
        f.isVirtualDevice = bool(info["kCGDisplayIsVirtualDevice"])
        f.isAirPlay = bool(info["kCGDisplayIsAirPlay"])
        f.productName = productName(info["DisplayProductName"])
        if let loc = info["IODisplayLocation"] as? String, loc.utf8.count <= 1024 {
            f.location = loc
            readFramebuffer(path: loc, into: &f)
        }
        if f.edid == nil, !id.isBuiltin || f.location == nil {
            readIntelDisplayConnect(for: id, into: &f)
        }
        if let edid = f.edid, edid.count > EDIDInfo.maxBytes { f.edid = edid.prefix(EDIDInfo.maxBytes) }
        return f
    }

    /// Apple silicon: the framebuffer entry at IODisplayLocation (AppleCLCD2 / IOMobileFramebufferShim).
    private static func readFramebuffer(path: String, into f: inout IORegistryDisplayFacts) {
        let entry = IORegistryEntryCopyFromPath(kIOMainPortDefault, path as CFString)
        guard entry != 0 else { return }
        defer { IOObjectRelease(entry) }
        if let uuid = property(entry, "EDID UUID") as? String, uuid.utf8.count <= 128 { f.edidUUID = uuid }
        if f.edidUUID == nil, let uuid = property(entry, "IOMFBUUID") as? String, uuid.utf8.count <= 128 { f.edidUUID = uuid }
        if let attrs = property(entry, "DisplayAttributes") as? [String: Any],
           let product = attrs["ProductAttributes"] as? [String: Any] {
            if let s = product["AlphanumericSerialNumber"] as? String, s.utf8.count <= 64 { f.alphanumericSerial = s }
            if f.productName == nil, let n = product["ProductName"] as? String { f.productName = PerDisplayIdentity.cleanName(n) }
        }
        if let edid = property(entry, "IODisplayEDID") as? Data { f.edid = edid }
        if let transport = property(entry, "Transport") as? [String: Any],
           let up = transport["Upstream"] as? String, up.localizedCaseInsensitiveContains("displaylink") {
            f.looksLikeDisplayLink = true
        }
    }

    /// Intel: IODisplayConnect services, matched by vendor/product/serial.
    private static func readIntelDisplayConnect(for id: CGDirectDisplayID, into f: inout IORegistryDisplayFacts) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == KERN_SUCCESS
        else { return }
        defer { IOObjectRelease(iterator) }
        var found = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard !found else { continue }                     // keep draining and releasing
            guard let dict = IODisplayCreateInfoDictionary(service, IOOptionBits(0x200))?.takeRetainedValue(),
                  let info = (dict as NSDictionary) as? [String: Any] else { continue }
            let vendor = (info["DisplayVendorID"] as? NSNumber)?.uint32Value
            let product = (info["DisplayProductID"] as? NSNumber)?.uint32Value
            let serial = (info["DisplaySerialNumber"] as? NSNumber)?.uint32Value ?? 0
            guard vendor == id.vendorNumber, product == id.modelNumber, serial == id.serialNumber || serial == 0 else { continue }
            found = true
            if let edid = info["IODisplayEDID"] as? Data { f.edid = edid }
            if f.location == nil, let loc = info["IODisplayLocation"] as? String, loc.utf8.count <= 1024 { f.location = loc }
        }
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        else { return nil }
        let type = CFGetTypeID(value)
        if type == CFStringGetTypeID() { return value as? String }
        if type == CFDataGetTypeID() { return value as? Data }
        if type == CFDictionaryGetTypeID() { return (value as? NSDictionary) as? [String: Any] }
        if type == CFNumberGetTypeID() { return value as? NSNumber }
        return nil
    }

    private static func bool(_ v: Any?) -> Bool { (v as? NSNumber)?.boolValue ?? false }

    /// DisplayProductName is a dictionary of localized names.
    private static func productName(_ v: Any?) -> String? {
        if let s = v as? String { return PerDisplayIdentity.cleanName(s) }
        guard let d = v as? [String: Any] else { return nil }
        let preferred = ["en_US", "en"] + Locale.preferredLanguages.map { $0.replacingOccurrences(of: "-", with: "_") }
        for k in preferred { if let s = d[k] as? String { return PerDisplayIdentity.cleanName(s) } }
        return d.keys.sorted().compactMap { d[$0] as? String }.first.flatMap { PerDisplayIdentity.cleanName($0) }
    }
}
