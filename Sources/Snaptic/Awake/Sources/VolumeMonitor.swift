import AppKit
import DiskArbitration
import IOKit
import SnapticKit

// Mounted volumes (owner: J; PLAN 0.3 §2.8, §2.9): events only (didMount / didUnmount / willUnmount, main queue).
// Each mount gets its DiskArbitration description and statfs flags on a private utility queue (DA calls are
// synchronous IPC); results hop to main. Builds `DriveAlivePolicy.VolumeFacts`, including the BSD name the write path
// re-checks. Metadata only: no volume content is read, so no Removable Volumes prompt.

/// One mounted volume. `uuid` is nil for volumes without one (some network and FAT volumes).
struct MountedVolume: Equatable, Sendable {
    let uuid: VolumeUUIDKey?
    let name: String
    let path: String
    let facts: DriveAlivePolicy.VolumeFacts
    var isEligible: Bool { uuid != nil && DriveAlivePolicy.isEligible(facts) }
}

@MainActor final class VolumeMonitor: CriterionSource {
    static var kinds: Set<AwakeCriterionKind> { [.volume] }

    weak var context: AwakeContext?
    private let changes = ChangeFanout()
    private let willUnmount = EventFanout<VolumeUUIDKey>()
    private var active = false
    private var observers: [NSObjectProtocol] = []
    private var generation: UInt64 = 0
    private let queue = DispatchQueue(label: "snaptic.awake.volumes", qos: .utility)

    /// nil until the first scan finishes and while inactive.
    private(set) var volumes: [MountedVolume]?

    init() {}

    /// Drive Alive stops writing here before an eject (the handler runs before the volume goes away).
    func observeWillUnmount(_ lifetime: Lifetime, _ handler: @escaping @MainActor (VolumeUUIDKey) -> Void) {
        willUnmount.add(lifetime, handler)
    }

    func volume(_ uuid: VolumeUUIDKey) -> MountedVolume? { volumes?.first { $0.uuid == uuid } }

    // MARK: AwakeServiceLifecycle

    func activate(_ context: AwakeContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scan() }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.willUnmountNotification, object: nil, queue: .main) {
            [weak self] note in
            let path = (note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path
            MainActor.assumeIsolated { self?.noteWillUnmount(path) }
        })
        scan()
    }

    func deactivate() {
        guard active else { return }
        active = false
        generation &+= 1
        let center = NSWorkspace.shared.notificationCenter
        for token in observers { center.removeObserver(token) }
        observers = []
        volumes = nil
        context = nil
    }

    // MARK: CriterionSource

    func contribute(to facts: inout CriterionFacts) {
        guard active, let volumes else { return }
        facts.volumes = Set(volumes.compactMap { $0.uuid?.rawValue })
    }

    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void) { changes.add(lifetime, handler) }

    // MARK: Scanning

    private func noteWillUnmount(_ path: String?) {
        guard active, let path, let index = volumes?.firstIndex(where: { $0.path == path }) else { return }
        let gone = volumes?.remove(at: index)
        if let uuid = gone?.uuid { willUnmount.fire(uuid) }
        changes.fire()
    }

    /// Rescans every mount (a handful) off the main thread; a newer scan or a deactivate drops older results.
    private func scan() {
        guard active else { return }
        generation &+= 1
        let ticket = generation
        let box = CallbackTarget(self)
        queue.async {
            let found = VolumeScan.all()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { box.target?.finish(found, ticket: ticket) }
            }
        }
    }

    private func finish(_ found: [MountedVolume], ticket: UInt64) {
        guard active, ticket == generation, found != volumes else { return }
        volumes = found
        changes.fire()
    }
}

/// The off-main half: DiskArbitration descriptions, statfs and the APFS role, for every mounted volume.
private enum VolumeScan {
    static func all() -> [MountedVolume] {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return [] }
        // getfsstat only: no resource values, which would touch the volume root.
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        let bootWhole = wholeDisk(of: "/", session: session)
        return urls.compactMap { volume($0, session: session, bootWhole: bootWhole) }
    }

    private static func volume(_ url: URL, session: DASession, bootWhole: String?) -> MountedVolume? {
        let path = url.path
        var st = statfs()
        guard statfs(path, &st) == 0 else { return nil }
        let flags = UInt32(st.f_flags)
        let fileSystem = cString(st.f_fstypename)
        let mountedFrom = cString(st.f_mntfromname)
        var uuid: VolumeUUIDKey?
        var name = url.lastPathComponent
        var bsdName = mountedFrom.hasPrefix("/dev/") ? String(mountedFrom.dropFirst(5)) : ""
        var isInternal = true
        var isDiskImage = false
        var whole: String?
        if let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
           let d = DADiskCopyDescription(disk) as? [String: Any] {
            if let cf = d[kDADiskDescriptionVolumeUUIDKey as String], CFGetTypeID(cf as CFTypeRef) == CFUUIDGetTypeID() {
                // Never traps: the CF type id was checked above.
                let id = cf as! CFUUID
                uuid = (CFUUIDCreateString(kCFAllocatorDefault, id) as String?).flatMap { VolumeUUIDKey(rawValue: $0) }
            }
            if let n = d[kDADiskDescriptionVolumeNameKey as String] as? String, !n.isEmpty { name = n }
            if let b = d[kDADiskDescriptionMediaBSDNameKey as String] as? String { bsdName = b }
            isInternal = (d[kDADiskDescriptionDeviceInternalKey as String] as? Bool) ?? true
            isDiskImage = (d[kDADiskDescriptionDeviceModelKey as String] as? String) == "Disk Image"
            if let w = DADiskCopyWholeDisk(disk), let wd = DADiskCopyDescription(w) as? [String: Any] {
                whole = wd[kDADiskDescriptionMediaBSDNameKey as String] as? String
                if (wd[kDADiskDescriptionDeviceModelKey as String] as? String) == "Disk Image" { isDiskImage = true }
            }
        }
        if whole == nil { whole = DriveAlivePolicy.wholeDisk(bsdName) }
        let facts = DriveAlivePolicy.VolumeFacts(
            isInternal: isInternal,
            isRootFileSystem: flags & UInt32(MNT_ROOTFS) != 0 || path == "/",
            isReadOnly: flags & UInt32(MNT_RDONLY) != 0,
            isLocal: flags & UInt32(MNT_LOCAL) != 0,
            isDiskImage: isDiskImage || hasDiskImageAncestor(bsdName),
            isTimeMachine: isTimeMachine(path: path, bsdName: bsdName),
            isBrowsable: flags & UInt32(MNT_DONTBROWSE) == 0,
            inBootContainer: bootWhole != nil && whole == bootWhole,
            fileSystem: fileSystem,
            bsdName: bsdName)
        return MountedVolume(uuid: uuid, name: TextSanitizer.clean(name, maxScalars: 64), path: path,
                                           facts: facts)
    }

    private static func wholeDisk(of path: String, session: DASession) -> String? {
        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, URL(fileURLWithPath: path) as CFURL),
              let whole = DADiskCopyWholeDisk(disk),
              let d = DADiskCopyDescription(whole) as? [String: Any] else { return nil }
        return d[kDADiskDescriptionMediaBSDNameKey as String] as? String
    }

    /// The BSD node's IOMedia, if any.
    private static func media(_ bsdName: String) -> io_service_t {
        guard DriveAlivePolicy.isValidBSDName(bsdName),
              let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else { return 0 }
        return IOServiceGetMatchingService(kIOMainPortDefault, matching)
    }

    /// An IOHDIXController above the media: a mounted disk image.
    private static func hasDiskImageAncestor(_ bsdName: String) -> Bool {
        let service = media(bsdName)
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var entry = service
        IOObjectRetain(entry)
        for _ in 0..<32 {
            var parent: io_registry_entry_t = 0
            let kr = IORegistryEntryGetParentEntry(entry, "IOService", &parent)
            IOObjectRelease(entry)
            guard kr == KERN_SUCCESS, parent != 0 else { return false }
            if IOObjectConformsTo(parent, "IOHDIXController") != 0 {
                IOObjectRelease(parent)
                return true
            }
            entry = parent
        }
        IOObjectRelease(entry)
        return false
    }

    /// An APFS volume with the Backup role, or a mount under the Time Machine mount root. (HFS+ destinations are
    /// usually mounted nobrowse and excluded by `isBrowsable`; HW check.)
    private static func isTimeMachine(path: String, bsdName: String) -> Bool {
        if path.hasPrefix("/Volumes/.timemachine") || path.contains("/.timemachine/") { return true }
        let service = media(bsdName)
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let role = IORegistryEntryCreateCFProperty(service, "Role" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        if let roles = role as? [String] { return roles.contains("Backup") }
        if let single = role as? String { return single == "Backup" }
        return false
    }

    private static func cString<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
