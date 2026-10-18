import AppKit
import CoreAudio
import IOKit
import SnapticKit

// Connected Bluetooth devices (owner: J; PLAN 0.3 §2.8, Beta, [PA] Bluetooth row, HW-10): events only, and no TCC.
// IOBluetooth would need the Bluetooth permission (lint L4 bans it), so presence is read from two places that need
// none:
// - Bluetooth audio: CoreAudio's device list (a listener on kAudioHardwarePropertyDevices) filtered by transport type
//   Bluetooth / Bluetooth LE. HAL calls and the listener run on a private serial queue (they can block > 50 ms); the
//   listener is stored as a typed block so Remove gets the same block. Reading device properties opens no stream.
// - Bluetooth input devices (keyboards, mice, trackpads): IORegistry `IOHIDDevice` first-match and terminated
//   notifications on the main queue, filtered by the `Transport` property. Registry properties only: no HID device is
//   ever opened, so there is no Input Monitoring prompt.
// Other Bluetooth devices (phones, watches, controllers without HID) can't be seen this way: that is why the
// criterion is Beta, and the picker says so (`scopeNote`). Device identities are hashed with Awake's salt at once
// (Kit's AwakeHashMaterial); raw addresses and UIDs are never stored; names are local UI only.

@MainActor final class BluetoothPresence: CriterionSource {
    static var kinds: Set<AwakeCriterionKind> { [.bluetooth] }

    /// The "Bluetooth device" condition is Beta (§2.8): the rule editor labels it so.
    static let isBeta = true
    /// What the condition can see, for the rule editor's device picker.
    static let scopeNote = L("Detects Bluetooth headphones, speakers, keyboards, mice and trackpads.")

    /// One connected device, for the device picker (the name is local UI only).
    struct Device: Equatable {
        let name: String
        /// The condition the picker stores for this device.
        let match: BluetoothMatch
    }

    weak var context: AwakeContext?
    private let changes = ChangeFanout()
    private var active = false
    // Audio (CoreAudio, on the HAL queue).
    private var hal: BluetoothAudioHAL?
    /// Salted hash → name; nil until the first device-list read.
    private var audio: [String: String]?
    // Input (IOKit, main queue).
    private var port: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var refcon: UnsafeMutableRawPointer?
    /// Keyed by IORegistryEntryGetRegistryEntryID.
    private var inputs: [UInt64: (hash: String, name: String)] = [:]
    private var inputsReady = false

    init() {}

    /// Connected devices for the picker: audio first, then input devices, each sorted by name, one per identity.
    var devices: [Device] {
        let byName: ((String, String), (String, String)) -> Bool = { a, b in
            let order = a.1.localizedStandardCompare(b.1)
            return order == .orderedSame ? a.0 < b.0 : order == .orderedAscending
        }
        let audioRows = (audio ?? [:]).map { ($0.key, $0.value) }.sorted(by: byName)
        var seen = Set<String>()
        var inputRows: [(String, String)] = []
        for entry in inputs.values where seen.insert(entry.hash).inserted { inputRows.append((entry.hash, entry.name)) }
        return audioRows.map { Device(name: $0.1, match: .audio(uidHash: $0.0, name: $0.1)) }
            + inputRows.sorted(by: byName).map { Device(name: $0.1, match: .input(hash: $0.0, name: $0.1)) }
    }

    // MARK: AwakeServiceLifecycle

    func activate(_ context: AwakeContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        startAudio()
        startInputs()
    }

    func deactivate() {
        guard active else { return }
        active = false
        hal?.stop()
        hal = nil
        audio = nil
        if addedIterator != 0 { IOObjectRelease(addedIterator) }
        if removedIterator != 0 { IOObjectRelease(removedIterator) }
        addedIterator = 0
        removedIterator = 0
        if let port { IONotificationPortDestroy(port) }
        port = nil
        if let box = refcon { Unmanaged<CallbackTarget<BluetoothPresence>>.fromOpaque(box).release() }
        refcon = nil
        inputs = [:]
        inputsReady = false
        context = nil
    }

    // MARK: CriterionSource

    /// Unknown (nil) until both halves have been read once.
    func contribute(to facts: inout CriterionFacts) {
        guard active, inputsReady, let audio else { return }
        facts.bluetooth = BluetoothFact(audioUIDHashes: Set(audio.keys), inputHashes: Set(inputs.values.map(\.hash)))
    }

    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void) { changes.add(lifetime, handler) }

    // MARK: Audio

    private func startAudio() {
        let box = CallbackTarget(self)
        let hal = BluetoothAudioHAL { found in
            DispatchQueue.main.async { MainActor.assumeIsolated { box.target?.audioChanged(found) } }
        }
        self.hal = hal
        hal.start()
    }

    /// `found`: (hash material, raw name) per Bluetooth audio device; hashed here (the salt is read on main).
    private func audioChanged(_ found: [(material: String, name: String?)]) {
        guard active else { return }
        var next: [String: String] = [:]
        for device in found {
            let hash = AwakeIdentity.bluetoothHash(device.material)
            if next[hash] == nil {
                next[hash] = BluetoothPresenceRules.displayName(device.name, fallback: L("Bluetooth Audio"))
            }
        }
        guard next != audio else { return }
        audio = next
        if inputsReady { changes.fire() }
    }

    // MARK: Input devices

    private func startInputs() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            // No notifications: nothing can be seen, which reads as "none connected".
            inputsReady = true
            return
        }
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        self.port = port
        let box = Unmanaged.passRetained(CallbackTarget(self)).toOpaque()
        refcon = box
        let added: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let box = Unmanaged<CallbackTarget<BluetoothPresence>>.fromOpaque(refcon).takeUnretainedValue()
            // Delivered on the main queue (the port's dispatch queue); the drain must happen now to re-arm.
            MainActor.assumeIsolated {
                if let presence = box.target { presence.drain(iterator, added: true) } else { BluetoothPresence.discard(iterator) }
            }
        }
        let removed: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let box = Unmanaged<CallbackTarget<BluetoothPresence>>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated {
                if let presence = box.target { presence.drain(iterator, added: false) } else { BluetoothPresence.discard(iterator) }
            }
        }
        // Each call consumes its matching dictionary, so each gets its own.
        if IOServiceAddMatchingNotification(port, "IOServiceFirstMatch", IOServiceMatching("IOHIDDevice"), added, box,
                                            &addedIterator) == KERN_SUCCESS {
            drain(addedIterator, added: true)
        }
        if IOServiceAddMatchingNotification(port, "IOServiceTerminate", IOServiceMatching("IOHIDDevice"), removed, box,
                                            &removedIterator) == KERN_SUCCESS {
            drain(removedIterator, added: false)
        }
        inputsReady = true
        if audio != nil { changes.fire() }
    }

    /// Drains `iterator` (always, so the notification stays armed) and updates the device table.
    private func drain(_ iterator: io_iterator_t, added: Bool) {
        var changed = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard active else { continue }
            var entryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { continue }
            if added {
                guard let device = Self.inputDevice(service) else { continue }
                if inputs[entryID]?.hash != device.hash || inputs[entryID]?.name != device.name {
                    inputs[entryID] = device
                    changed = true
                }
            } else if inputs.removeValue(forKey: entryID) != nil {
                changed = true
            }
        }
        if changed && inputsReady && audio != nil { changes.fire() }
    }

    private static func discard(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
    }

    /// A Bluetooth HID device's identity and name from its registry properties; nil for every other transport.
    private static func inputDevice(_ service: io_service_t) -> (hash: String, name: String)? {
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        guard BluetoothPresenceRules.isBluetoothTransport(property("Transport") as? String) else { return nil }
        let address = (property("SerialNumber") as? String) ?? (property("DeviceAddress") as? String)
        let vendor = (property("VendorID") as? NSNumber)?.intValue ?? 0
        let product = (property("ProductID") as? NSNumber)?.intValue ?? 0
        guard let material = AwakeHashMaterial.bluetoothInput(address: address, vendor: vendor, product: product) else {
            return nil
        }
        let name = BluetoothPresenceRules.displayName(property("Product") as? String, fallback: L("Bluetooth Device"))
        return (AwakeIdentity.bluetoothHash(material), name)
    }
}

/// The HAL side. Every member is touched only on `queue` (hence @unchecked Sendable); `publish` is called there too.
private final class BluetoothAudioHAL: @unchecked Sendable {
    private let queue = DispatchQueue(label: "snaptic.awake.bluetooth", qos: .utility)
    private let publish: @Sendable ([(material: String, name: String?)]) -> Void
    private var running = false
    private var devicesBlock: AudioObjectPropertyListenerBlock?

    init(publish: @escaping @Sendable ([(material: String, name: String?)]) -> Void) {
        self.publish = publish
    }

    func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            var addr = Self.address(kAudioHardwarePropertyDevices)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.report() }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, queue, block) == noErr {
                devicesBlock = block
            }
            report()
        }
    }

    /// Asynchronous: the listener is removed on the queue; nothing reaches the main side afterwards because it has
    /// already dropped this object.
    func stop() {
        queue.async { [self] in
            guard running else { return }
            running = false
            if let block = devicesBlock {
                var addr = Self.address(kAudioHardwarePropertyDevices)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, queue, block)
            }
            devicesBlock = nil
        }
    }

    // MARK: On the queue

    private func report() {
        guard running else { return }
        var found: [(material: String, name: String?)] = []
        for device in Self.allDevices() {
            guard let transport = Self.uint32(device, kAudioDevicePropertyTransportType),
                  BluetoothPresenceRules.audioTransportTypes.contains(transport),
                  let uid = Self.string(device, kAudioDevicePropertyDeviceUID),
                  let material = AwakeHashMaterial.bluetoothAudio(uid: uid) else { continue }
            found.append((material: material, name: Self.string(device, kAudioObjectPropertyName)))
        }
        publish(found)
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func allDevices() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        guard count > 0, count <= 512 else { return [] }
        var ids = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        var got = UInt32(count * MemoryLayout<AudioObjectID>.stride)
        let status: OSStatus = ids.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return OSStatus(kAudioHardwareUnspecifiedError) }
            return AudioObjectGetPropertyData(system, &addr, 0, nil, &got, base)
        }
        guard status == noErr else { return [] }
        return Array(ids.prefix(Int(got) / MemoryLayout<AudioObjectID>.stride))
    }

    private static func uint32(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    /// A CFString property (returned retained by the HAL).
    private static func string(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
