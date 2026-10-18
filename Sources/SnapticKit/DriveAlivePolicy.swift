import Foundation

// Drive Alive policy (owner: J; PLAN 0.3 §2.9, C9, R5-14). Pure and tested; DriveAliveService re-checks the live mount
// before every write (statfs, BSD name, volume UUID).

package enum DriveAliveError: String, Codable, Sendable { case notEligible, mountChanged, notOurFile, ioError, denied }

package enum DriveAlivePolicy {
    package struct VolumeFacts: Equatable, Sendable {
        package var isInternal, isRootFileSystem, isReadOnly, isLocal, isDiskImage, isTimeMachine, isBrowsable: Bool
        package var inBootContainer: Bool
        /// f_fstypename.
        package var fileSystem: String
        /// "disk4s1" from DiskArbitration.
        package var bsdName: String

        package init(isInternal: Bool, isRootFileSystem: Bool, isReadOnly: Bool, isLocal: Bool, isDiskImage: Bool,
                     isTimeMachine: Bool, isBrowsable: Bool, inBootContainer: Bool, fileSystem: String, bsdName: String) {
            self.isInternal = isInternal
            self.isRootFileSystem = isRootFileSystem
            self.isReadOnly = isReadOnly
            self.isLocal = isLocal
            self.isDiskImage = isDiskImage
            self.isTimeMachine = isTimeMachine
            self.isBrowsable = isBrowsable
            self.inBootContainer = inBootContainer
            self.fileSystem = fileSystem
            self.bsdName = bsdName
        }
    }

    /// Allowlist (security M5).
    package static let allowedFileSystems: Set<String> = ["apfs", "hfs", "exfat", "msdos"]
    /// External, local, writable, browsable, a real (non-image, non-Time Machine) volume on an allowlisted file system,
    /// outside the boot volume's APFS container, with a well-formed BSD name ("disk4s1").
    package static func isEligible(_ v: VolumeFacts) -> Bool {
        guard !v.isInternal, !v.isRootFileSystem, !v.isReadOnly, v.isLocal, !v.isDiskImage, !v.isTimeMachine,
              v.isBrowsable, !v.inBootContainer else { return false }
        return allowedFileSystems.contains(v.fileSystem) && isValidBSDName(v.bsdName)
    }

    /// "disk" + digits, then any number of "s" + digits ("disk4", "disk4s1", "disk5s2s1"); nothing else.
    package static func isValidBSDName(_ name: String) -> Bool {
        guard name.utf8.count <= 32, name.hasPrefix("disk") else { return false }
        let rest = Array(name.utf8.dropFirst(4))
        var i = 0
        func digits() -> Bool {
            let start = i
            while i < rest.count, rest[i] >= 0x30, rest[i] <= 0x39 { i += 1 }
            return i > start
        }
        guard digits() else { return false }
        while i < rest.count {
            guard rest[i] == 0x73 else { return false }   // "s"
            i += 1
            guard digits() else { return false }
        }
        return true
    }

    /// The whole-disk BSD name of a slice or APFS volume ("disk3s5" → "disk3"); nil when not a BSD disk name.
    package static func wholeDisk(_ bsdName: String) -> String? {
        guard isValidBSDName(bsdName) else { return nil }
        let tail = bsdName.dropFirst(4)
        return "disk" + String(tail.prefix(while: { $0 != "s" }))
    }

    /// The device path statfs reports in f_mntfromname for a BSD name.
    package static func devicePath(_ bsdName: String) -> String { "/dev/" + bsdName }
    package static let fileName = ".snaptic-keepalive"
    package static let fileSize = 8
    package static let intervalRange: ClosedRange<Int> = 30...600
    /// C9 + N1 + security M1/L1 (R5-14: a trigger session passes `.rule`, the holds-only state `.commandLine`, nothing
    /// governing nil). Never when guards forbid background work (hard floor, user floor, unreadable battery, critical
    /// heat) or before the UI-confirmed first write. Otherwise: "Also when no session is running" writes whatever
    /// governs; else only while a session runs whose (restore-preserved) source is not `.commandLine`.
    package static func shouldWrite(sessionActive: Bool, sessionSource: AwakeSessionSource?, evenWithoutSession: Bool,
                                    backgroundWorkAllowed: Bool, uiConfirmedFirstWrite: Bool) -> Bool {
        guard backgroundWorkAllowed, uiConfirmedFirstWrite else { return false }
        if evenWithoutSession { return true }
        guard sessionActive, let source = sessionSource else { return false }
        return source != .commandLine
    }

    /// The interval DriveAliveService uses, clamped to `intervalRange`.
    package static func clampedInterval(_ seconds: Int) -> Int {
        min(intervalRange.upperBound, max(intervalRange.lowerBound, seconds))
    }
}
