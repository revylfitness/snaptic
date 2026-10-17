import AppKit
import CoreGraphics
import Darwin
import SnapticKit
import SnapticShims

// Revert journals on disk (owner: B). PLAN §4.6: `~/Library/Application Support/Snaptic/
// Displays/` (0700, lstat-checked), atomic writes (O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC 0600,
// fsync, rename, fsync dir). `journal.json` protects one trial or restore; `permanent.json`
// holds MonitorPanel trial steps and survives reboots. Recovery runs at launch even in
// Safe Mode and with Displays off; the guard claims journals by rename before reverting.

/// File operations shared by the app and the guard (nonisolated).
struct JournalFiles {
    let directory: String

    /// The directory for the current user (from getpwuid_r, never $HOME).
    static func defaultDirectory() -> String? {
        guard let home = homeDirectory() else { return nil }
        return home + "/Library/Application Support/Snaptic/Displays"
    }

    static func homeDirectory() -> String? {
        var pwd = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16_384)
        guard getpwuid_r(getuid(), &pwd, &buffer, buffer.count, &result) == 0, result != nil, let dir = pwd.pw_dir else {
            return nil
        }
        return String(cString: dir)
    }

    /// Creates the directory chain (0700 for ours) and checks it isn't a symlink or foreign.
    func ensureDirectory() -> Bool {
        var path = ""
        let parts = directory.split(separator: "/")
        for (i, part) in parts.enumerated() {
            path += "/" + part
            var st = stat()
            if lstat(path, &st) != 0 {
                let mode: mode_t = i >= parts.count - 2 ? 0o700 : 0o755
                guard mkdir(path, mode) == 0 || errno == EEXIST else { return false }
                guard lstat(path, &st) == 0 else { return false }
            }
            guard (st.st_mode & S_IFMT) == S_IFDIR else { return false }
        }
        var st = stat()
        guard lstat(directory, &st) == 0, st.st_uid == getuid(), (st.st_mode & 0o077) == 0 else {
            _ = chmod(directory, 0o700)
            return lstat(directory, &st) == 0 && st.st_uid == getuid() && (st.st_mode & 0o077) == 0
        }
        return true
    }

    func path(_ name: String) -> String { directory + "/" + name }

    /// Atomic write: temp file (O_EXCL|O_NOFOLLOW, 0600), fsync, rename, fsync the directory.
    @discardableResult
    func write(_ data: Data, to name: String) -> Bool {
        guard ensureDirectory() else { return false }
        let temp = path(".\(name).\(getpid()).\(UInt32.random(in: 0...UInt32.max)).tmp")
        let fd = open(temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }
        let ok = data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, base + offset, raw.count - offset)
                if n > 0 { offset += n } else if n < 0 && errno == EINTR { continue } else { return false }
            }
            return true
        }
        let synced = fsync(fd) == 0
        close(fd)
        guard ok, synced, rename(temp, path(name)) == 0 else {
            unlink(temp)
            return false
        }
        let dfd = open(directory, O_RDONLY | O_CLOEXEC | O_DIRECTORY)
        if dfd >= 0 {
            fsync(dfd)
            close(dfd)
        }
        return true
    }

    /// Reads a regular file (no symlinks), at most `JournalModel.maxFileBytes`.
    func read(_ name: String) -> Data? {
        let fd = open(path(name), O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == getuid(),
              st.st_size <= off_t(JournalModel.maxFileBytes) else { return nil }
        var data = Data(count: Int(st.st_size))
        let n = data.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return Darwin.read(fd, base, raw.count)
        }
        guard n == Int(st.st_size) else { return nil }
        return data
    }

    func remove(_ name: String) { unlink(path(name)) }

    /// Renames `from` to `to` atomically (journal claims). False if `from` is gone.
    func claim(_ from: String, as to: String) -> Bool { rename(path(from), path(to)) == 0 }

    func list() -> [String] {
        guard let dir = opendir(directory) else { return [] }
        defer { closedir(dir) }
        var names: [String] = []
        while let entry = readdir(dir), names.count < 256 {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            if name != "." && name != ".." { names.append(name) }
        }
        return names
    }

    /// kern.bootsessionuuid with two-call sizing (R2C m3).
    static func bootSessionUUID() -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0, size < 256 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }
}

/// Applies undo ops staged (enable → un-mirror → MonitorPanel → re-read modes → CG), each
/// `.forSession` and CAS against a fresh read. Shared by launch recovery and the guard.
enum JournalApplier {
    /// `settle` waits for the layout to quiet between stages.
    static func apply(_ ops: [UndoOp], reader: LayoutReader, overlay: LayoutReader.Overlay = LayoutReader.Overlay(),
                      functions: CGConfigFunctions, canMonitorPanel: Bool,
                      settle: (Double) -> Void) -> (applied: Int, skipped: Int) {
        var applied = 0, skipped = 0
        for (stage, stageOps) in UndoPlanner.stages(ops) {
            let live = reader.read(overlay)
            let pending = stage == .monitorPanel ? monitorPanelPending(stageOps, live: live)
                                                 : UndoPlanner.pending(stageOps, live: live)
            skipped += stageOps.count - pending.count
            let changes = pending.compactMap(UndoPlanner.change(for:))
            switch stage {
            case .monitorPanel:
                guard canMonitorPanel else {
                    skipped += changes.count
                    continue
                }
                for c in changes { if CGConfig.applyMonitorPanel(c) { applied += 1 } else { skipped += 1 } }
            case .enable, .unmirror, .configure:
                let r = CGConfig.apply(changes, scope: .forSession, functions: functions)
                if r.ok { applied += r.applied } else {
                    // One failing op mustn't block the rest: retry individually.
                    for c in changes {
                        let single = CGConfig.apply([c], scope: .forSession, functions: functions)
                        if single.ok { applied += 1 } else { skipped += 1 }
                    }
                }
            }
            if !changes.isEmpty { settle(stage == .monitorPanel ? 2.0 : 1.5) }
        }
        return (applied, skipped)
    }

    /// MonitorPanel values aren't in the CG layout: CAS against the shim's live values
    /// (rotation comes from CGDisplayRotation).
    static func monitorPanelPending(_ ops: [UndoOp], live: LayoutSnapshot) -> [UndoOp] {
        ops.compactMap { op in
            guard let resolved = UndoPlanner.resolve(op, in: live) else { return nil }
            let value = resolved.property == .rotation ? UndoPlanner.liveValue(resolved, in: live) : monitorPanelLive(resolved)
            return value?.matches(resolved.expected) == true ? resolved : nil
        }
    }

    /// CAS for MonitorPanel ops against live values from the shim.
    static func monitorPanelLive(_ op: UndoOp) -> PropertyValue? {
        switch op.property {
        case .rotation: return SNMonitorPanel.orientation(display: op.displayID).map { .degrees($0.intValue) }
        case .hdr: return SNMonitorPanel.prefersHDR(display: op.displayID).map { .bool($0.boolValue) }
        case .underscan: return SNMonitorPanel.underscan(display: op.displayID).map { .fraction($0.doubleValue) }
        default: return nil
        }
    }
}

@MainActor final class RevertJournal {
    struct Recovery: Equatable {
        let restoredCount: Int
        let message: String?
    }

    let files: JournalFiles?
    private(set) var permanent: PermanentJournal

    init() {
        files = JournalFiles.defaultDirectory().map(JournalFiles.init(directory:))
        permanent = PermanentJournal(uid: getuid())
        if let data = files?.read(JournalModel.permanentFileName), let p = JournalModel.decodePermanent(data), p.uid == getuid() {
            permanent = p
        }
    }

    var hasSessionJournal: Bool { files?.read(JournalModel.sessionFileName) != nil }

    /// Writes the session journal before a trial or restore. False = refuse the change.
    func writeSession(undo: [UndoOp], restoreColorSync: Bool, trialID: UInt64?, live: LayoutSnapshot) -> Bool {
        guard let files else { return false }
        let j = SessionJournal(bootSessionUUID: JournalFiles.bootSessionUUID(), uid: getuid(),
                               createdAt: Date().timeIntervalSince1970, fingerprints: live.physicalFingerprints,
                               undo: undo, restoreColorSync: restoreColorSync, trialID: trialID)
        guard let data = JournalModel.encode(j) else { return false }
        return files.write(data, to: JournalModel.sessionFileName)
    }

    func clearSession() { files?.remove(JournalModel.sessionFileName) }

    /// Records a trial's MonitorPanel steps before they're applied.
    func addPermanent(trial: UInt64, ops: [UndoOp]) -> Bool {
        let mp = ops.filter { $0.stage == .monitorPanel }
        guard !mp.isEmpty else { return true }
        permanent.add(trial: trial, ops: mp)
        return savePermanent()
    }

    /// Keep or revert finished.
    func resolvePermanent(trial: UInt64) {
        guard permanent.ops.contains(where: { $0.trialID == trial }) else { return }
        permanent.resolve(trial: trial)
        _ = savePermanent()
    }

    private func savePermanent() -> Bool {
        guard let files else { return false }
        if permanent.isEmpty {
            files.remove(JournalModel.permanentFileName)
            return true
        }
        guard let data = JournalModel.encode(permanent) else { return false }
        return files.write(data, to: JournalModel.permanentFileName)
    }

    var permanentCount: Int { permanent.ops.count }

    // MARK: Launch recovery (AppDelegate step 7)

    /// Even with Displays off and in Safe Mode: reverts unconfirmed permanent ops, then
    /// replays a session journal (or an orphaned claim) in safe directions only.
    static func recoverAtLaunch(safeMode: SafeModeState) -> Recovery {
        guard let dir = JournalFiles.defaultDirectory() else { return Recovery(restoredCount: 0, message: nil) }
        let files = JournalFiles(directory: dir)
        guard files.ensureDirectory() else { return Recovery(restoredCount: 0, message: nil) }
        let reader = LayoutReader()
        let functions = CGConfigFunctions.resolvedForRestore()
        var restored = 0

        // 1. Permanent ops (HDR, underscan, rotation), not discarded on reboot.
        if let data = files.read(JournalModel.permanentFileName) {
            if let p = JournalModel.decodePermanent(data) {
                let ops = JournalModel.permanentToRevert(p, uid: getuid())
                let groups = PrivateSymbolResolver.verifyMonitorPanel()
                var pending: [UndoOp] = []
                for op in ops {
                    guard let resolved = UndoPlanner.resolve(op, in: reader.read()) else { continue }
                    if let live = JournalApplier.monitorPanelLive(resolved), live.matches(resolved.expected) {
                        pending.append(resolved)
                    }
                }
                if !pending.isEmpty && !groups.isEmpty {
                    for op in pending {
                        if let c = UndoPlanner.change(for: op), CGConfig.monitorPanelCanApply(c), CGConfig.applyMonitorPanel(c) {
                            restored += 1
                            pump(2)
                        }
                    }
                }
            }
            files.remove(JournalModel.permanentFileName)
        }

        // 2. The session journal, then orphaned claims from a dead guard.
        var candidates: [String] = []
        let mine = JournalModel.claimedName(pid: getpid())
        if files.claim(JournalModel.sessionFileName, as: mine) { candidates.append(mine) }
        for name in files.list() {
            guard let pid = JournalModel.claimedPID(name), pid != getpid() else { continue }
            if kill(pid, 0) == -1 && errno == ESRCH {
                let reclaimed = mine + ".\(pid)"
                if files.claim(name, as: reclaimed) { candidates.append(reclaimed) }
            }
        }
        var colorSync = false
        for name in candidates {
            defer { files.remove(name) }
            guard let data = files.read(name), let j = JournalModel.decodeSession(data) else { continue }
            let live = reader.read()
            let decision = JournalModel.evaluate(j, bootSessionUUID: JournalFiles.bootSessionUUID(), uid: getuid(),
                                                 now: Date().timeIntervalSince1970, live: live,
                                                 publicModes: { id in Set(DisplayModes.list(id).map(\.ref)) })
            switch decision {
            case .discard(let why):
                EventLog.shared.record(.journal, "Journal discarded (\(why))")
            case .recover(let ops, let restoreColorSync):
                let r = JournalApplier.apply(ops, reader: reader, functions: functions, canMonitorPanel: false,
                                             settle: { pump($0) })
                restored += r.applied
                colorSync = colorSync || restoreColorSync
                EventLog.shared.record(.journal, "Journal recovered: \(r.applied) applied, \(r.skipped) skipped")
            }
        }
        if colorSync {
            CGDisplayRestoreColorSyncSettings()
            restored += 1
        }
        guard restored > 0 else { return Recovery(restoredCount: 0, message: nil) }
        return Recovery(restoredCount: restored,
                        message: L("Snaptic restored your displays after an unexpected exit."))
    }

    /// Lets WindowServer settle at launch (no UI exists yet; bounded).
    private static func pump(_ seconds: Double) {
        _ = CFRunLoopRunInMode(.defaultMode, min(max(seconds, 0), 3), false)
    }
}
