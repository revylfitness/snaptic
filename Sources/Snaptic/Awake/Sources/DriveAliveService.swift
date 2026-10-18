import AppKit
import Combine
import Darwin
import SnapticKit

// Drive Alive writes (owner: J; PLAN 0.3 §2.9, §3.4, C9, security M3/M5/L3). Keeps chosen external drives from
// spinning down by rewriting an 8-byte hidden file (`.snaptic-keepalive`) every `interval` seconds. The volume root is
// always resolved from the live mount list by UUID (VolumeMonitor), never from config, and every write re-checks the
// mount on a private serial utility queue:
// 1. open(root, O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
// 2. fstatfs: f_mntonname == root, allowlisted f_fstypename, MNT_LOCAL, neither MNT_RDONLY nor MNT_ROOTFS,
//    f_mntfromname == /dev/<the BSD name DiskArbitration judged eligible>; fgetattrlist ATTR_VOL_UUID == the key
// 2b. a `.snaptic-keepalive.removing` left by a removal cut short is deleted if it is still ours (security r2 S2-1)
// 3. openat(fileName, O_WRONLY|O_CREAT|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK, 0600); fstat: regular, ours, one link,
//    ≤ 64 bytes, same device as the root
// 4. 8 bytes at offset 0, ftruncate(8), F_FULLFSYNC (fsync where unsupported); both fds closed; result hops to main.
// A failed check skips that volume with a reason and no retry until it is mounted again. At most one write is in
// flight per volume (the first open may block on the Removable Volumes prompt; ticks meanwhile coalesce). Whether to
// write at all (sessions, guards, the UI-confirmed first write) is DriveAliveController's decision.

@MainActor final class DriveAliveService: ObservableObject, AwakeServiceLifecycle {
    struct VolumeState: Equatable {
        let uuid: VolumeUUIDKey
        let name: String
        var lastWrite: Date?
        var lastError: DriveAliveError?
    }

    /// Every tracked (turned-on) volume, sorted by name.
    @Published private(set) var volumes: [VolumeState] = []
    /// Writing now (awake-correctness F1): at least one current target is mounted, eligible and not skipped after a
    /// failure (`DriveAlivePolicy.isWriting`). SessionController's `driveAliveWriting` (the PreventDiskIdle
    /// assertion) follows this, never "a volume is turned on"; DriveAliveController re-arbitrates when it flips.
    @Published private(set) var isWriting = false
    weak var context: AwakeContext?

    private var active = false
    private var lifetime: Lifetime?
    private var targets: Set<VolumeUUIDKey> = []
    private var interval: TimeInterval = TimeInterval(DriveAliveConfig().intervalSeconds)
    private let timer = SourceTimer()
    private var names: [VolumeUUIDKey: String] = [:]
    private var states: [VolumeUUIDKey: VolumeState] = [:]
    private var inFlight: Set<VolumeUUIDKey> = []
    /// Completions waiting for the write already in flight on that volume.
    private var waiters: [VolumeUUIDKey: [@MainActor (DriveAliveError?) -> Void]] = [:]
    /// Completions of removals in flight, by token.
    private var removals: [Int: @MainActor (DriveAliveError?) -> Void] = [:]
    private var nextRemoval = 0
    /// Continuous instant of the last attempt per volume (this activation).
    private var lastAttempt: [VolumeUUIDKey: Double] = [:]
    /// Failed volumes and the mount they failed on: skipped until that mount goes away.
    private var failedMounts: [VolumeUUIDKey: MountedVolume] = [:]
    private let queue = DispatchQueue(label: "snaptic.drivealive", qos: .utility)

    init() {}

    // MARK: Control (DriveAliveController, the Drives page)

    /// Writes start/stop per volume. Newly added targets are written at once, then every `interval` (clamped to
    /// 30...600 s); an empty set stops every periodic write (in-flight ones finish).
    func setTargets(_ uuids: Set<VolumeUUIDKey>, interval: TimeInterval) {
        let seconds = TimeInterval(DriveAlivePolicy.clampedInterval(Int(interval.isFinite ? interval : 120)))
        let added = uuids.subtracting(targets)
        let intervalChanged = seconds != self.interval
        targets = active ? uuids : []
        self.interval = seconds
        updateWriting()
        guard active else { return }
        if targets.isEmpty {
            timer.cancel()
        } else if !timer.isRunning || intervalChanged {
            // A short period finds due volumes soon after a mount or a skipped tick; each volume keeps its own
            // `interval` through `lastAttempt`.
            timer.start(every: min(seconds, 30), tolerance: 2) { [weak self] in self?.writeDue() }
        }
        if !added.isEmpty { writeDue() }
    }

    /// The volumes the Drives page and the menu show (every turned-on volume, written or not), by UUID → name.
    func track(_ tracked: [VolumeUUIDKey: String]) {
        names = tracked
        states = states.filter { tracked[$0.key] != nil }
        for (uuid, name) in tracked where states[uuid]?.name != name {
            states[uuid] = VolumeState(uuid: uuid, name: name, lastWrite: states[uuid]?.lastWrite,
                                       lastError: states[uuid]?.lastError)
        }
        publish()
    }

    /// The UI-confirmed write right after the user turns a volume on (§2.9, security M3: the Removable Volumes prompt
    /// follows a UI action). On success the volume's `firstWriteDone` is set, which lets periodic writes start.
    func firstWrite(_ uuid: VolumeUUIDKey, completion: (@MainActor (DriveAliveError?) -> Void)? = nil) {
        guard active else {
            completion?(.notEligible)
            return
        }
        failedMounts[uuid] = nil
        write(uuid) { [weak self] error in
            if error == nil, let config = self?.context?.config, config.value.drives.volumes[uuid]?.enabled == true {
                config.value.drives.volumes[uuid]?.firstWriteDone = true
            }
            completion?(error)
        }
    }

    /// When the user turns a volume off: the same mount checks, then the file is unlinked only if it is still ours
    /// (regular, our uid, one link, exactly 8 bytes, same device). Nothing happens for an unmounted volume. The result
    /// (nil = removed or nothing to remove) reaches `completion` on main, so the Drives page can show a failure.
    func removeKeepAliveFile(_ uuid: VolumeUUIDKey, completion: (@MainActor (DriveAliveError?) -> Void)? = nil) {
        targets.remove(uuid)
        updateWriting()
        guard active, let mount = context?.volumes.volume(uuid), mount.isEligible else {
            completion?(nil)
            return
        }
        let root = mount.path, bsd = mount.facts.bsdName
        // As with writes, the completion waits here and only Sendable values cross to the queue.
        let token = nextRemoval
        nextRemoval &+= 1
        if let completion { removals[token] = completion }
        let box = CallbackTarget(self)
        queue.async {
            let error = DriveAliveIO.remove(root: root, bsdName: bsd, uuid: uuid)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { box.target?.removed(token, error: error) }
            }
        }
    }

    private func removed(_ token: Int, error: DriveAliveError?) {
        removals.removeValue(forKey: token)?(error)
    }

    // MARK: AwakeServiceLifecycle

    func activate(_ context: AwakeContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        self.lifetime = lifetime
        context.volumes.observe(lifetime) { [weak self] in self?.mountsChanged() }
        context.volumes.observeWillUnmount(lifetime) { [weak self] uuid in self?.willUnmount(uuid) }
    }

    func deactivate() {
        guard active else { return }
        active = false
        timer.cancel()
        targets = []
        inFlight = []
        waiters = [:]
        lastAttempt = [:]
        failedMounts = [:]
        names = [:]
        states = [:]
        lifetime = nil
        volumes = []
        context = nil
        updateWriting()
    }

    // MARK: Writing

    private func mountsChanged() {
        guard active, let mounted = context?.volumes.volumes else { return }
        // A failure is kept only while the same mount is there; unmounted or remounted volumes may be tried again.
        failedMounts = failedMounts.filter { uuid, mount in mounted.contains(mount) && mounted.contains { $0.uuid == uuid } }
        updateWriting()
        writeDue()
    }

    private func willUnmount(_ uuid: VolumeUUIDKey) {
        // VolumeMonitor already dropped the mount, so nothing new starts on it; forget its schedule.
        lastAttempt[uuid] = nil
        failedMounts[uuid] = nil
        updateWriting()
    }

    private func writeDue() {
        guard active else { return }
        let now = AwakeSourceClock.now()
        for uuid in targets.sorted(by: { $0.rawValue < $1.rawValue }) where !inFlight.contains(uuid) {
            if let last = lastAttempt[uuid], now - last < interval - 1 { continue }
            write(uuid, completion: nil)
        }
    }

    private func write(_ uuid: VolumeUUIDKey, completion: (@MainActor (DriveAliveError?) -> Void)?) {
        guard !inFlight.contains(uuid) else {
            // Coalesced: the caller gets the in-flight write's result.
            if let completion { waiters[uuid, default: []].append(completion) }
            return
        }
        // Not mounted (or not scanned yet): nothing to do and nothing to report.
        guard let mount = context?.volumes.volume(uuid) else {
            completion?(.mountChanged)
            return
        }
        if let failed = failedMounts[uuid], failed == mount {
            completion?(states[uuid]?.lastError ?? .mountChanged)
            return
        }
        lastAttempt[uuid] = AwakeSourceClock.now()
        guard mount.isEligible else {
            finish(uuid, mount: mount, error: .notEligible, completion: completion)
            return
        }
        inFlight.insert(uuid)
        // The completion waits here, so only Sendable values cross to the write queue.
        if let completion { waiters[uuid, default: []].append(completion) }
        let root = mount.path, bsd = mount.facts.bsdName
        let box = CallbackTarget(self)
        queue.async {
            let error = DriveAliveIO.write(root: root, bsdName: bsd, uuid: uuid)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { box.target?.written(uuid, mount: mount, error: error) }
            }
        }
    }

    private func written(_ uuid: VolumeUUIDKey, mount: MountedVolume, error: DriveAliveError?) {
        inFlight.remove(uuid)
        let waiting = waiters.removeValue(forKey: uuid) ?? []
        finish(uuid, mount: mount, error: error, completion: nil)
        for waiter in waiting { waiter(error) }
    }

    private func finish(_ uuid: VolumeUUIDKey, mount: MountedVolume, error: DriveAliveError?,
                        completion: (@MainActor (DriveAliveError?) -> Void)?) {
        guard active else { return }
        if let error {
            failedMounts[uuid] = mount
            EventLog.shared.record(.driveAliveError(error))
        } else {
            failedMounts[uuid] = nil
        }
        updateWriting()
        if let name = names[uuid] {
            var state = states[uuid] ?? VolumeState(uuid: uuid, name: name, lastWrite: nil, lastError: nil)
            state.lastError = error
            if error == nil { state.lastWrite = Date() }
            states[uuid] = state
            publish()
        }
        completion?(error)
    }

    private func updateWriting() {
        var eligible = Set<VolumeUUIDKey>()
        if active, let mounted = context?.volumes.volumes {
            for volume in mounted where volume.isEligible { if let uuid = volume.uuid { eligible.insert(uuid) } }
        }
        let writing = active && DriveAlivePolicy.isWriting(targets: targets, eligibleMounted: eligible,
                                                           failed: Set(failedMounts.keys))
        if writing != isWriting { isWriting = writing }
    }

    private func publish() {
        let sorted = states.values.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.uuid.rawValue < $1.uuid.rawValue : order == .orderedAscending
        }
        if sorted != volumes { volumes = sorted }
    }
}

/// The off-main half: every system call of the write and remove procedures (§2.9). Pure functions of their inputs;
/// nil = success.
private enum DriveAliveIO {
    static let maxExistingBytes: Int64 = 64

    static func write(root: String, bsdName: String, uuid: VolumeUUIDKey) -> DriveAliveError? {
        let dir: Root
        switch openRoot(root: root, bsdName: bsdName, uuid: uuid) {
        case .opened(let opened): dir = opened
        case .failed(let error): return error
        }
        defer { close(dir.fd) }
        // A removal cut short (crash, I/O error, unplugged) left its temp name behind: delete it if it is still ours.
        // Its failure never blocks the write.
        _ = removeLeftover(dir)
        let fd = openat(dir.fd, DriveAlivePolicy.fileName, O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK,
                        mode_t(0o600))
        guard fd >= 0 else { return openError(errno) }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { return .ioError }
        guard isOurFile(st, device: dir.device), Int64(st.st_size) <= maxExistingBytes else { return .notOurFile }
        var stamp = UInt64(max(0, Date().timeIntervalSince1970)).bigEndian
        let size = DriveAlivePolicy.fileSize
        let written = withUnsafeBytes(of: &stamp) { raw in pwrite(fd, raw.baseAddress, size, 0) }
        guard written == size, ftruncate(fd, off_t(size)) == 0 else { return .ioError }
        if fcntl(fd, F_FULLFSYNC) != 0, fsync(fd) != 0 { return .ioError }
        return nil
    }

    /// Security N-3 and r2 S2-1: the unlink must hit the very file that was checked, not one swapped in under the same
    /// name. macOS has no fd-based unlink, so the name is first moved to the one fixed temp name
    /// (`removingFileName`, never over an existing entry) and the moved entry is compared with the checked file
    /// (`DriveAlivePolicy.isSameFile`: the inode, or on exFAT/FAT, whose ids may change on rename, the size,
    /// modification time and 8 bytes) before the temp name is unlinked. Anything else is put back (never over a file
    /// that took the name meanwhile) and left alone. A leftover temp from a removal cut short is deleted first (and
    /// by every write), so at most that one fixed name can ever stay behind.
    static func remove(root: String, bsdName: String, uuid: VolumeUUIDKey) -> DriveAliveError? {
        let dir: Root
        switch openRoot(root: root, bsdName: bsdName, uuid: uuid) {
        case .opened(let opened): dir = opened
        case .failed(let error): return error
        }
        defer { close(dir.fd) }
        // Something that isn't ours under the temp name blocks the removal (the exclusive move would fail anyway).
        if let error = removeLeftover(dir) { return error }
        let name = DriveAlivePolicy.fileName, temp = DriveAlivePolicy.removingFileName
        // A regular file before it is opened at all (opening a device node or FIFO can have side effects).
        var named = stat()
        guard fstatat(dir.fd, name, &named, AT_SYMLINK_NOFOLLOW) == 0 else { return errno == ENOENT ? nil : .ioError }
        guard isOurFile(named, device: dir.device) else { return .notOurFile }
        let fd = openat(dir.fd, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { return errno == ENOENT ? nil : openError(errno) }
        defer { close(fd) }
        var checked = stat()
        guard fstat(fd, &checked) == 0 else { return .ioError }
        guard isOurFile(checked, device: dir.device), Int64(checked.st_size) == Int64(DriveAlivePolicy.fileSize),
              checked.st_ino == named.st_ino else { return .notOurFile }
        guard let content = readContent(fd) else { return .ioError }
        let before = identity(checked, content: content)
        switch moveExclusive(dir: dir.fd, from: name, to: temp) {
        case 0: break
        case ENOENT: return nil
        case EEXIST: return .notOurFile
        default: return .ioError
        }
        var entry = stat()
        guard fstatat(dir.fd, temp, &entry, AT_SYMLINK_NOFOLLOW) == 0 else { return .ioError }
        var after = identity(entry, content: nil)
        if entry.st_ino != checked.st_ino, DriveAlivePolicy.renameMayChangeInode.contains(dir.fileSystem),
           isOurFile(entry, device: dir.device) {
            after = movedIdentity(dir: dir, name: temp, entry: entry) ?? after
        }
        guard DriveAlivePolicy.isSameFile(checked: before, moved: after, fileSystem: dir.fileSystem) else {
            putBack(dir: dir.fd, from: temp, to: name)
            return .notOurFile
        }
        // On failure the temp stays; the next write or removal on this volume deletes it.
        guard unlinkat(dir.fd, temp, 0) == 0 || errno == ENOENT else { return .ioError }
        return nil
    }

    /// Deletes a `removingFileName` left by a removal cut short, when it passes the same checks as our file (regular,
    /// ours, one link, same device, exactly 8 bytes, and the opened fd is the entry checked). nil = nothing left or
    /// deleted. The window between that check and the unlink by name is open only to processes of the same user, which
    /// could delete the file anyway; no other app has a reason to use this name.
    private static func removeLeftover(_ dir: Root) -> DriveAliveError? {
        let temp = DriveAlivePolicy.removingFileName
        var named = stat()
        guard fstatat(dir.fd, temp, &named, AT_SYMLINK_NOFOLLOW) == 0 else { return errno == ENOENT ? nil : .ioError }
        guard isOurFile(named, device: dir.device), Int64(named.st_size) == Int64(DriveAlivePolicy.fileSize) else {
            return .notOurFile
        }
        let fd = openat(dir.fd, temp, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { return errno == ENOENT ? nil : openError(errno) }
        defer { close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0 else { return .ioError }
        guard isOurFile(opened, device: dir.device), Int64(opened.st_size) == Int64(DriveAlivePolicy.fileSize),
              opened.st_ino == named.st_ino else { return .notOurFile }
        guard unlinkat(dir.fd, temp, 0) == 0 || errno == ENOENT else { return .ioError }
        return nil
    }

    /// The moved entry's identity with its 8 bytes, read through an fd that is verified to be that entry; nil when it
    /// can't be read or isn't an 8-byte file of ours.
    private static func movedIdentity(dir: Root, name: String, entry: stat) -> DriveAlivePolicy.FileIdentity? {
        let fd = openat(dir.fd, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, opened.st_dev == entry.st_dev, opened.st_ino == entry.st_ino,
              isOurFile(opened, device: dir.device), Int64(opened.st_size) == Int64(DriveAlivePolicy.fileSize),
              let content = readContent(fd) else { return nil }
        return identity(opened, content: content)
    }

    private static func readContent(_ fd: Int32) -> [UInt8]? {
        let size = DriveAlivePolicy.fileSize
        var bytes = [UInt8](repeating: 0, count: size)
        let read = bytes.withUnsafeMutableBytes { raw in pread(fd, raw.baseAddress, size, 0) }
        return read == size ? bytes : nil
    }

    private static func identity(_ st: stat, content: [UInt8]?) -> DriveAlivePolicy.FileIdentity {
        DriveAlivePolicy.FileIdentity(device: Int64(st.st_dev), inode: UInt64(st.st_ino), size: Int64(st.st_size),
                                      modifiedSeconds: Int64(st.st_mtimespec.tv_sec),
                                      modifiedNanoseconds: Int64(st.st_mtimespec.tv_nsec), content: content)
    }

    /// Renames without replacing anything: RENAME_EXCL, or where a file system lacks it (ENOTSUP/EINVAL: exFAT, FAT)
    /// a plain rename only while the target name is free. 0 on success, else the errno (EEXIST when taken).
    private static func moveExclusive(dir: Int32, from: String, to: String) -> Int32 {
        if renameatx_np(dir, from, dir, to, UInt32(RENAME_EXCL)) == 0 { return 0 }
        let code = errno
        guard code == ENOTSUP || code == EINVAL else { return code }
        var existing = stat()
        if fstatat(dir, to, &existing, AT_SYMLINK_NOFOLLOW) == 0 { return EEXIST }
        guard errno == ENOENT else { return errno }
        return renameat(dir, from, dir, to) == 0 ? 0 : errno
    }

    /// Moves a file that turned out not to be ours back to its name, never replacing a file that has that name now.
    private static func putBack(dir: Int32, from: String, to: String) {
        _ = moveExclusive(dir: dir, from: from, to: to)
    }

    // MARK: Checks

    private struct Root {
        let fd: Int32
        let device: dev_t
        /// f_fstypename ("apfs", "exfat", …).
        let fileSystem: String
    }

    private enum Opened {
        case opened(Root)
        case failed(DriveAliveError)
    }

    /// Steps 1–3 of §2.9: the directory fd of the volume root, only when the live mount is still the one judged
    /// eligible.
    private static func openRoot(root: String, bsdName: String, uuid: VolumeUUIDKey) -> Opened {
        guard root.hasPrefix("/"), root != "/", DriveAlivePolicy.isValidBSDName(bsdName) else { return .failed(.mountChanged) }
        let fd = open(root, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return .failed(openError(errno)) }
        var fs = statfs()
        var st = stat()
        guard fstatfs(fd, &fs) == 0, fstat(fd, &st) == 0 else {
            close(fd)
            return .failed(.mountChanged)
        }
        let flags = UInt32(fs.f_flags)
        let fileSystem = cString(fs.f_fstypename)
        let matches = cString(fs.f_mntonname) == root
            && DriveAlivePolicy.allowedFileSystems.contains(fileSystem)
            && flags & UInt32(MNT_LOCAL) != 0
            && flags & UInt32(MNT_RDONLY) == 0
            && flags & UInt32(MNT_ROOTFS) == 0
            && cString(fs.f_mntfromname) == DriveAlivePolicy.devicePath(bsdName)
            && volumeUUID(fd) == uuid
        guard matches else {
            close(fd)
            return .failed(.mountChanged)
        }
        return .opened(Root(fd: fd, device: st.st_dev, fileSystem: fileSystem))
    }

    /// A regular file we own with one link on the root's device.
    private static func isOurFile(_ st: stat, device: dev_t) -> Bool {
        (st.st_mode & 0o170000) == 0o100000 && st.st_uid == getuid() && st.st_nlink == 1 && st.st_dev == device
    }

    private static func openError(_ code: Int32) -> DriveAliveError {
        switch code {
        case EACCES, EPERM: return .denied
        case ELOOP, EISDIR, ENOTDIR: return .notOurFile
        case ENOENT, ENXIO, ENODEV: return .mountChanged
        default: return .ioError
        }
    }

    /// fgetattrlist(ATTR_VOL_INFO | ATTR_VOL_UUID): u_int32_t length, then the 16-byte uuid. nil when unsupported or
    /// all zero.
    private static func volumeUUID(_ fd: Int32) -> VolumeUUIDKey? {
        var request = attrlist()
        request.bitmapcount = 5                                  // ATTR_BIT_MAP_COUNT
        request.volattr = attrgroup_t(0x8000_0000) | attrgroup_t(0x0004_0000)   // ATTR_VOL_INFO | ATTR_VOL_UUID
        var buffer = [UInt8](repeating: 0, count: 64)
        let status = buffer.withUnsafeMutableBytes { raw in fgetattrlist(fd, &request, raw.baseAddress, raw.count, 0) }
        guard status == 0 else { return nil }
        let length = Int(buffer[0]) | Int(buffer[1]) << 8 | Int(buffer[2]) << 16 | Int(buffer[3]) << 24
        guard length >= 20 else { return nil }
        let bytes = Array(buffer[4..<20])
        guard bytes.contains(where: { $0 != 0 }) else { return nil }
        let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        return VolumeUUIDKey(rawValue: uuid.uuidString)
    }

    private static func cString<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
