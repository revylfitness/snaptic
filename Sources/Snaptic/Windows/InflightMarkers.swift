import Darwin
import Foundation
import os
import SnapticKit

// The window symbols' crash markers (lead; PLAN 0.5 §4.12 step 6, H3; X2-4, X3-8, P3-6; B1b). Kit `CrashGuard`
// holds the rules and the counters; this file writes `~/Library/Application Support/Snaptic/inflight/<symbol>`,
// holding the OS build, and runs launch step 3b.

/// One `os_unfair_lock` per marker. It covers the count and the `open` + `write(2)` or the `unlink`, never the call.
final class UnfairInflightLock: InflightLock, @unchecked Sendable {
    private let base = OSAllocatedUnfairLock()
    func lock() { base.lock() }
    func unlock() { base.unlock() }
}

/// The files: opened `O_WRONLY|O_CREAT|O_TRUNC|O_NOFOLLOW|O_CLOEXEC`, mode 0600, in a 0700 directory of our own.
struct PosixMarkerFiles: InflightMarkerFiles {
    let build: String

    func write(_ name: String) -> Bool {
        guard !build.isEmpty, let directory = InflightMarkers.directory() else { return false }
        let fd = open(directory + "/" + name, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let bytes = Array(build.utf8)
        let written = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        return written == bytes.count
    }

    func remove(_ name: String) {
        guard let directory = InflightMarkers.existingDirectory() else { return }
        unlink(directory + "/" + name)
    }
}

enum InflightMarkers {
    /// `kern.osversion` (for example "25C56"); empty when it can't be read, which turns every build check off.
    static let build: String = {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0, size < 256 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }()

    static let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

    static let ledger = InflightLedger(names: CrashGuard.markerNames, files: PosixMarkerFiles(build: build),
                                       makeLock: { _ in UnfairInflightLock() })

    /// `…/Snaptic/inflight`, created 0700 if missing; nil unless it's a directory we own.
    static func directory() -> String? {
        guard let support = AccountPaths.supportDirectory() else { return nil }
        let path = support + "/inflight"
        var info = stat()
        if lstat(path, &info) != 0 {
            guard mkdir(path, 0o700) == 0 || errno == EEXIST, lstat(path, &info) == 0 else { return nil }
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else { return nil }
        return path
    }

    /// The directory when it's already there (removal never creates it).
    static func existingDirectory() -> String? {
        guard let support = AccountPaths.supportDirectory() else { return nil }
        let path = support + "/inflight"
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else { return nil }
        return path
    }

    /// Every file in the directory, with its content (nil when it can't be read as a small regular file).
    static func scan() -> [String: String?] {
        guard let directory = existingDirectory(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [:] }
        var found: [String: String?] = [:]
        for name in names where !name.isEmpty && !name.contains("/") {
            found[name] = readSmall(directory + "/" + name)
        }
        return found
    }

    private static func readSmall(_ path: String) -> String? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var buffer = [UInt8](repeating: 0, count: 64)
        let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        guard count >= 0 else { return nil }
        return String(decoding: buffer.prefix(count), as: UTF8.self)
    }

    /// Launch step 3b (H3, X3-8), before step 4. A marker from this build, left by a run that didn't quit cleanly,
    /// sets its symbol's disabled build and logs `.safety`. Every marker is removed either way.
    @discardableResult
    static func atLaunch(previousRunCleanQuit: Bool) -> CrashGuard.LaunchDecision {
        let decision = CrashGuard.atLaunch(markers: scan(), currentBuild: build,
                                           previousRunCleanQuit: previousRunCleanQuit)
        for name in decision.disable {
            UserDefaults.standard.set(build, forKey: CrashGuard.disabledKey(name))
            EventLog.shared.record(.safety, "windows.crashGuard " + name + " stopped on this macOS build")
        }
        if let directory = existingDirectory() {
            for name in decision.remove where !name.contains("/") { unlink(directory + "/" + name) }
        }
        return decision
    }

    static func isDisabled(_ marker: String) -> Bool {
        CrashGuard.isDisabled(disabledBuild: UserDefaults.standard.string(forKey: CrashGuard.disabledKey(marker)),
                              currentBuild: build)
    }

    #if DEBUG
    /// `SNAPTIC_DEBUG_TRAP_IN=<marker>` crashes the debug build after that marker is written (M4's crash-guard row).
    static let debugTrap = ProcessInfo.processInfo.environment["SNAPTIC_DEBUG_TRAP_IN"]

    static func trapIfAsked(_ marker: String) {
        if debugTrap == marker { abort() }
    }
    #endif
}
