import Foundation

// Stub (owner: J). Hand-written by the lead in step 0 from PLAN 0.3 §2.9 + R5-14 (kind S): never eligible, never writes.

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
    /// Stub: false.
    package static func isEligible(_ v: VolumeFacts) -> Bool { false }
    package static let fileName = ".snaptic-keepalive"
    package static let fileSize = 8
    package static let intervalRange: ClosedRange<Int> = 30...600
    /// Stub: false.
    package static func shouldWrite(sessionActive: Bool, sessionSource: AwakeSessionSource?, evenWithoutSession: Bool,
                                    backgroundWorkAllowed: Bool, uiConfirmedFirstWrite: Bool) -> Bool { false }
}
