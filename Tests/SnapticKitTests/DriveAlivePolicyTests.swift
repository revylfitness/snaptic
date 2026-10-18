import XCTest
@testable import SnapticKit

/// DriveAlivePolicy (PLAN 0.3 §2.9, C9, R5-14, §6.6).
final class DriveAlivePolicyTests: XCTestCase {
    private func external(fs: String = "apfs", bsd: String = "disk6s1") -> DriveAlivePolicy.VolumeFacts {
        DriveAlivePolicy.VolumeFacts(isInternal: false, isRootFileSystem: false, isReadOnly: false, isLocal: true,
                                     isDiskImage: false, isTimeMachine: false, isBrowsable: true, inBootContainer: false,
                                     fileSystem: fs, bsdName: bsd)
    }

    // MARK: Eligibility

    func testAnExternalWritableDiskIsEligible() {
        for fs in ["apfs", "hfs", "exfat", "msdos"] { XCTAssertTrue(DriveAlivePolicy.isEligible(external(fs: fs)), fs) }
    }

    func testEveryExclusion() {
        let exclusions: [(String, (inout DriveAlivePolicy.VolumeFacts) -> Void)] = [
            ("internal", { $0.isInternal = true }),
            ("root", { $0.isRootFileSystem = true }),
            ("read-only", { $0.isReadOnly = true }),
            ("network", { $0.isLocal = false }),
            ("disk image", { $0.isDiskImage = true }),
            ("Time Machine", { $0.isTimeMachine = true }),
            ("not browsable", { $0.isBrowsable = false }),
            ("boot container", { $0.inBootContainer = true }),
            ("smbfs", { $0.fileSystem = "smbfs" }),
            ("nfs", { $0.fileSystem = "nfs" }),
            ("macFUSE", { $0.fileSystem = "macfuse" }),
            ("FSKit", { $0.fileSystem = "fskit" }),
            ("ntfs", { $0.fileSystem = "ntfs" }),
            ("case", { $0.fileSystem = "APFS" }),
            ("empty fs", { $0.fileSystem = "" }),
            ("bad BSD name", { $0.bsdName = "disk6s1/../x" }),
            ("empty BSD name", { $0.bsdName = "" }),
        ]
        for (name, change) in exclusions {
            var v = external()
            change(&v)
            XCTAssertFalse(DriveAlivePolicy.isEligible(v), name)
        }
    }

    func testBSDNames() {
        for good in ["disk4", "disk4s1", "disk12s3", "disk5s2s1"] { XCTAssertTrue(DriveAlivePolicy.isValidBSDName(good), good) }
        for bad in ["", "disk", "disks1", "disk4s", "disk4s1x", "rdisk4", "Disk4", "disk4 s1", "disk-1", "disk٤",
                    "disk4ss1", String(repeating: "disk1s", count: 10)] {
            XCTAssertFalse(DriveAlivePolicy.isValidBSDName(bad), bad)
        }
        XCTAssertEqual(DriveAlivePolicy.wholeDisk("disk3s5"), "disk3")
        XCTAssertEqual(DriveAlivePolicy.wholeDisk("disk3s1s1"), "disk3")
        XCTAssertEqual(DriveAlivePolicy.wholeDisk("disk10"), "disk10")
        XCTAssertNil(DriveAlivePolicy.wholeDisk("/dev/disk3"))
        XCTAssertEqual(DriveAlivePolicy.devicePath("disk6s1"), "/dev/disk6s1")
    }

    func testIntervalClamp() {
        XCTAssertEqual(DriveAlivePolicy.clampedInterval(5), 30)
        XCTAssertEqual(DriveAlivePolicy.clampedInterval(120), 120)
        XCTAssertEqual(DriveAlivePolicy.clampedInterval(Int.max), 600)
        XCTAssertEqual(DriveAlivePolicy.clampedInterval(Int.min), 30)
    }

    // MARK: shouldWrite

    func testCommandLineSessionsNeverDriveDriveAlive() {
        // A CLI session, incl. one restored after a relaunch (its source survives), and the holds-only state.
        XCTAssertFalse(DriveAlivePolicy.shouldWrite(sessionActive: true, sessionSource: .commandLine, evenWithoutSession: false,
                                                    backgroundWorkAllowed: true, uiConfirmedFirstWrite: true))
    }

    func testOtherSessionsDrive() {
        for source in [AwakeSessionSource.menu, .hotkey, .settings, .launch, .rule] {
            XCTAssertTrue(DriveAlivePolicy.shouldWrite(sessionActive: true, sessionSource: source, evenWithoutSession: false,
                                                       backgroundWorkAllowed: true, uiConfirmedFirstWrite: true), "\(source)")
        }
    }

    func testNoSessionNeedsTheOption() {
        XCTAssertFalse(DriveAlivePolicy.shouldWrite(sessionActive: false, sessionSource: nil, evenWithoutSession: false,
                                                    backgroundWorkAllowed: true, uiConfirmedFirstWrite: true))
        XCTAssertTrue(DriveAlivePolicy.shouldWrite(sessionActive: false, sessionSource: nil, evenWithoutSession: true,
                                                   backgroundWorkAllowed: true, uiConfirmedFirstWrite: true))
        // An "active" flag without a source is not a session.
        XCTAssertFalse(DriveAlivePolicy.shouldWrite(sessionActive: true, sessionSource: nil, evenWithoutSession: false,
                                                    backgroundWorkAllowed: true, uiConfirmedFirstWrite: true))
    }

    func testGuardsAndTheFirstWriteGateEveryMode() {
        for even in [false, true] {
            for source in [AwakeSessionSource?.none, .menu, .rule, .commandLine] {
                for active in [false, true] {
                    XCTAssertFalse(DriveAlivePolicy.shouldWrite(sessionActive: active, sessionSource: source,
                                                                evenWithoutSession: even, backgroundWorkAllowed: false,
                                                                uiConfirmedFirstWrite: true))
                    XCTAssertFalse(DriveAlivePolicy.shouldWrite(sessionActive: active, sessionSource: source,
                                                                evenWithoutSession: even, backgroundWorkAllowed: true,
                                                                uiConfirmedFirstWrite: false))
                }
            }
        }
    }
}
