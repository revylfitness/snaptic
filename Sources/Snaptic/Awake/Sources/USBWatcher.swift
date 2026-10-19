import AppKit
import IOKit
import SnapticKit

// Connected USB devices (owner: J; PLAN 0.3 §2.7, §2.8): events only, first-match and terminated notifications on
// IOUSBHostDevice delivered on the main queue. Iterators are drained at arm (that arms them and reports present
// devices). Registry properties only, no device is opened, no TCC. A serial is hashed with Awake's salt at once and
// the raw value is never stored.

@MainActor final class USBWatcher: CriterionSource {
    static var kinds: Set<AwakeCriterionKind> { [.usb] }

    /// One connected device, for the criterion and the device picker (names are local UI only).
    struct USBDevice: Equatable {
        let fact: USBFact
        let name: String
    }

    weak var context: AwakeContext?
    private let changes = ChangeFanout()
    private var active = false
    private var port: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var refcon: UnsafeMutableRawPointer?
    /// Keyed by IORegistryEntryGetRegistryEntryID.
    private var devices: [UInt64: USBDevice] = [:]
    private var ready = false

    init() {}

    /// Connected devices sorted by name (picker).
    var connected: [USBDevice] {
        devices.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: AwakeServiceLifecycle

    func activate(_ context: AwakeContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        self.port = port
        let box = Unmanaged.passRetained(CallbackTarget(self)).toOpaque()
        refcon = box
        let added: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let box = Unmanaged<CallbackTarget<USBWatcher>>.fromOpaque(refcon).takeUnretainedValue()
            // Delivered on the main queue (the port's dispatch queue); the drain must happen now to re-arm.
            MainActor.assumeIsolated {
                if let watcher = box.target { watcher.drain(iterator, added: true) } else { USBWatcher.discard(iterator) }
            }
        }
        let removed: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let box = Unmanaged<CallbackTarget<USBWatcher>>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated {
                if let watcher = box.target { watcher.drain(iterator, added: false) } else { USBWatcher.discard(iterator) }
            }
        }
        // Each call consumes its matching dictionary, so each gets its own.
        if IOServiceAddMatchingNotification(port, "IOServiceFirstMatch", IOServiceMatching("IOUSBHostDevice"), added, box,
                                            &addedIterator) == KERN_SUCCESS {
            drain(addedIterator, added: true)
        }
        if IOServiceAddMatchingNotification(port, "IOServiceTerminate", IOServiceMatching("IOUSBHostDevice"), removed, box,
                                            &removedIterator) == KERN_SUCCESS {
            drain(removedIterator, added: false)
        }
        ready = true
        changes.fire()
    }

    func deactivate() {
        guard active else { return }
        active = false
        ready = false
        if addedIterator != 0 { IOObjectRelease(addedIterator) }
        if removedIterator != 0 { IOObjectRelease(removedIterator) }
        addedIterator = 0
        removedIterator = 0
        if let port { IONotificationPortDestroy(port) }
        port = nil
        if let box = refcon { Unmanaged<CallbackTarget<USBWatcher>>.fromOpaque(box).release() }
        refcon = nil
        devices = [:]
        context = nil
    }

    // MARK: CriterionSource

    func contribute(to facts: inout CriterionFacts) {
        guard active, ready else { return }
        facts.usb = devices.keys.sorted().compactMap { devices[$0]?.fact }
    }

    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void) { changes.add(lifetime, handler) }

    // MARK: Reading

    /// Drains `iterator` (always, so the notification stays armed) and updates the device table.
    private func drain(_ iterator: io_iterator_t, added: Bool) {
        var changed = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard active else { continue }
            var entryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { continue }
            if added {
                devices[entryID] = Self.device(service)
            } else if devices.removeValue(forKey: entryID) == nil {
                continue
            }
            changed = true
        }
        if changed && ready { changes.fire() }
    }

    private static func discard(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
    }

    private static func device(_ service: io_service_t) -> USBDevice {
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        let vendor = (property("idVendor") as? NSNumber)?.intValue ?? 0
        let product = (property("idProduct") as? NSNumber)?.intValue ?? 0
        let serialHash = (property("USB Serial Number") as? String).flatMap { AwakeIdentity.usbSerialHash($0) }
        let rawName = (property("USB Product Name") as? String) ?? (property("kUSBProductString") as? String)
        let name = TextSanitizer.clean(rawName ?? L("USB Device"), maxScalars: 64)
        return USBDevice(fact: USBFact(vendor: vendor, product: product, serialHash: serialHash), name: name)
    }
}
