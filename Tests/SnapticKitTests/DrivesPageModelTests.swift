import XCTest
@testable import SnapticKit

/// The Drives page model (PLAN 0.3 §2.9, §4.3 Drives).
final class DrivesPageModelTests: XCTestCase {
    private let a = VolumeUUIDKey(rawValue: "11111111-1111-1111-1111-111111111111")!
    private let b = VolumeUUIDKey(rawValue: "22222222-2222-2222-2222-222222222222")!
    private let c = VolumeUUIDKey(rawValue: "33333333-3333-3333-3333-333333333333")!

    private func facts(_ change: (inout DriveAlivePolicy.VolumeFacts) -> Void = { _ in }) -> DriveAlivePolicy.VolumeFacts {
        var f = DriveAlivePolicy.VolumeFacts(isInternal: false, isRootFileSystem: false, isReadOnly: false, isLocal: true,
                                             isDiskImage: false, isTimeMachine: false, isBrowsable: true,
                                             inBootContainer: false, fileSystem: "apfs", bsdName: "disk6s1")
        change(&f)
        return f
    }

    private func drive(_ uuid: VolumeUUIDKey?, _ name: String,
                       _ change: (inout DriveAlivePolicy.VolumeFacts) -> Void = { _ in }) -> DriveCandidate {
        DriveCandidate(uuid: uuid, name: name, facts: facts(change))
    }

    private func config(_ entries: [VolumeUUIDKey: DriveAliveVolume], evenWithoutSession: Bool = false) -> DriveAliveConfig {
        var c = DriveAliveConfig()
        c.volumes = LossyMap(entries)
        c.evenWithoutSession = evenWithoutSession
        return c
    }

    private func inputs(_ mounted: [DriveCandidate]?, _ config: DriveAliveConfig, session: Bool = true,
                        background: Bool = true) -> DrivesPageModel.Inputs {
        DrivesPageModel.Inputs(mounted: mounted, config: config, sessionAllowsWrites: session,
                               backgroundWorkAllowed: background)
    }

    // MARK: Listing

    func testOnlyExternalPhysicalVolumesAreListed() {
        let hidden: [(String, (inout DriveAlivePolicy.VolumeFacts) -> Void)] = [
            ("internal", { $0.isInternal = true }),
            ("root", { $0.isRootFileSystem = true }),
            ("network", { $0.isLocal = false }),
            ("disk image", { $0.isDiskImage = true }),
            ("not browsable", { $0.isBrowsable = false }),
            ("boot container", { $0.inBootContainer = true }),
        ]
        for (name, change) in hidden {
            XCTAssertFalse(DrivesPageModel.isListed(facts(change)), name)
            let rows = DrivesPageModel.rows(inputs([drive(a, name, change)], DriveAliveConfig()))
            XCTAssertTrue(rows.isEmpty, name)
        }
        XCTAssertTrue(DrivesPageModel.isListed(facts()))
        XCTAssertTrue(DrivesPageModel.isListed(facts { $0.isReadOnly = true }), "listed with a reason")
        XCTAssertTrue(DrivesPageModel.isListed(facts { $0.isTimeMachine = true }), "listed with a reason")
    }

    func testRowsAreSortedByNameNumerically() {
        let rows = DrivesPageModel.rows(inputs([drive(a, "Disk 10"), drive(b, "disk 9"), drive(c, "Archive")],
                                               DriveAliveConfig()))
        XCTAssertEqual(rows.map(\.name), ["Archive", "disk 9", "Disk 10"])
        XCTAssertTrue(rows.allSatisfy { $0.status == .off && !$0.isOn && $0.canToggle })
        XCTAssertEqual(rows.map(\.id), [c.rawValue, b.rawValue, a.rawValue])
    }

    func testUnknownMountsShowNothingNotEvenDisconnectedVolumes() {
        let cfg = config([a: DriveAliveVolume(name: "Backup", enabled: true, firstWriteDone: true)])
        XCTAssertTrue(DrivesPageModel.rows(inputs(nil, cfg)).isEmpty)
        XCTAssertEqual(DrivesPageModel.rows(inputs([], cfg)).map(\.status), [.notConnected])
    }

    func testDuplicateUUIDsKeepTheFirst() {
        let rows = DrivesPageModel.rows(inputs([drive(a, "One"), drive(a, "Two")], DriveAliveConfig()))
        XCTAssertEqual(rows.map(\.name), ["One"])
    }

    // MARK: Unsupported

    func testUnsupportedReasons() {
        XCTAssertNil(DrivesPageModel.unsupportedReason(drive(a, "x")))
        XCTAssertEqual(DrivesPageModel.unsupportedReason(drive(nil, "x")), .noIdentifier)
        XCTAssertEqual(DrivesPageModel.unsupportedReason(drive(a, "x") { $0.isReadOnly = true }), .readOnly)
        XCTAssertEqual(DrivesPageModel.unsupportedReason(drive(a, "x") { $0.isTimeMachine = true; $0.isReadOnly = true }),
                       .timeMachine)
        XCTAssertEqual(DrivesPageModel.unsupportedReason(drive(a, "x") { $0.fileSystem = "ntfs" }), .fileSystem("NTFS"))
        XCTAssertEqual(DrivesPageModel.unsupportedReason(drive(a, "x") { $0.fileSystem = "\u{202E}ntfs\u{0}" }),
                       .fileSystem("NTFS"), "cleaned before it is shown")
        XCTAssertEqual(DrivesPageModel.unsupportedReason(drive(a, "x") { $0.fileSystem = "" }), .other)
        XCTAssertEqual(DrivesPageModel.unsupportedReason(drive(a, "x") { $0.bsdName = "bad" }), .other)
    }

    func testUnsupportedRowsAreDisabledUnlessOn() {
        let ro = drive(a, "Camera card") { $0.isReadOnly = true }
        let off = DrivesPageModel.rows(inputs([ro], DriveAliveConfig()))
        XCTAssertEqual(off.first?.status, .unsupported(.readOnly))
        XCTAssertEqual(off.first?.canToggle, false)
        let on = DrivesPageModel.rows(inputs([ro], config([a: DriveAliveVolume(name: "Camera card", enabled: true)])))
        XCTAssertEqual(on.first?.isOn, true)
        XCTAssertEqual(on.first?.canToggle, true, "a volume that is on can always be turned off")
        XCTAssertEqual(on.first?.status, .unsupported(.readOnly))
        let noID = DrivesPageModel.rows(inputs([drive(nil, "FAT")], DriveAliveConfig()))
        XCTAssertEqual(noID.first?.id, "path:FAT")
        XCTAssertEqual(noID.first?.offersWrite, false)
    }

    func testAnEnabledVolumeThatIsNoLongerListedStaysVisible() {
        let internalNow = drive(a, "Moved") { $0.isInternal = true }
        let rows = DrivesPageModel.rows(inputs([internalNow], config([a: DriveAliveVolume(name: "Moved", enabled: true)])))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.status, .unsupported(.other))
        XCTAssertEqual(rows.first?.canToggle, true)
    }

    // MARK: Status of a volume that is on

    func testStatusOrder() {
        let mounted = [drive(a, "Backup")]
        let unconfirmed = config([a: DriveAliveVolume(name: "Backup", enabled: true)])
        let confirmed = config([a: DriveAliveVolume(name: "Backup", enabled: true, firstWriteDone: true)])
        let when = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(DrivesPageModel.rows(inputs(mounted, unconfirmed)).first?.status, .needsFirstWrite)
        XCTAssertEqual(DrivesPageModel.rows(inputs(mounted, unconfirmed)).first?.offersWrite, true)

        var i = inputs(mounted, unconfirmed)
        i.firstWriteRunning = [a]
        i.firstWriteFailures = [a: .denied]
        XCTAssertEqual(DrivesPageModel.rows(i).first?.status, .firstWriteRunning, "running wins over an old failure")
        i.firstWriteRunning = []
        XCTAssertEqual(DrivesPageModel.rows(i).first?.status, .failed(.denied))
        XCTAssertEqual(DrivesPageModel.rows(i).first?.offersWrite, true)

        var j = inputs(mounted, confirmed)
        j.results = [a: DriveWriteResult(lastWrite: when, lastError: .ioError)]
        XCTAssertEqual(DrivesPageModel.rows(j).first?.status, .failed(.ioError))
        j.results = [a: DriveWriteResult(lastWrite: when, lastError: nil)]
        XCTAssertEqual(DrivesPageModel.rows(j).first?.status, .active(lastWrite: when))
        XCTAssertEqual(DrivesPageModel.rows(j).first?.offersWrite, false)
        j.sessionAllowsWrites = false
        XCTAssertEqual(DrivesPageModel.rows(j).first?.status, .waitingForSession)
        j.backgroundWorkAllowed = false
        XCTAssertEqual(DrivesPageModel.rows(j).first?.status, .paused, "guards before sessions")
        j.results = [:]
        j.backgroundWorkAllowed = true
        j.sessionAllowsWrites = true
        XCTAssertEqual(DrivesPageModel.rows(j).first?.status, .active(lastWrite: nil))
    }

    func testDisconnectedVolumesFollowTheMounts() {
        let cfg = config([
            a: DriveAliveVolume(name: "Zed", enabled: true, firstWriteDone: true),
            b: DriveAliveVolume(name: "", enabled: true),
            c: DriveAliveVolume(name: "Off", enabled: false),
        ])
        let rows = DrivesPageModel.rows(inputs([drive(c, "Off")], cfg))
        XCTAssertEqual(rows.map(\.name), ["Off", "Unnamed drive", "Zed"])
        XCTAssertEqual(rows.map(\.status), [.off, .notConnected, .notConnected])
        XCTAssertTrue(rows.dropFirst().allSatisfy { $0.isOn && $0.canToggle && !$0.offersWrite })
    }

    // MARK: Turning volumes on and off

    func testTurningOnAlwaysNeedsAFreshFirstWrite() {
        let cfg = config([a: DriveAliveVolume(name: "Old", enabled: false, firstWriteDone: true)])
        let on = DrivesPageModel.turningOn(a, name: "Backup\u{202E}", in: cfg)
        XCTAssertEqual(on.volumes[a], DriveAliveVolume(name: "Backup", enabled: true, firstWriteDone: false))
        let off = DrivesPageModel.turningOff(a, in: on)
        XCTAssertEqual(off.volumes[a], DriveAliveVolume(name: "Backup", enabled: false, firstWriteDone: false))
        XCTAssertEqual(DrivesPageModel.turningOff(b, in: off), off, "nothing to turn off")
        var confirmed = on
        confirmed.volumes[a]?.firstWriteDone = true
        XCTAssertEqual(DrivesPageModel.turningOff(a, in: confirmed).volumes[a]?.firstWriteDone, false)
    }

    func testTheSixteenVolumeLimit() {
        var entries: [VolumeUUIDKey: DriveAliveVolume] = [:]
        var keys: [VolumeUUIDKey] = []
        for n in 0..<DriveAliveConfig.maxVolumes {
            let key = VolumeUUIDKey(rawValue: String(format: "00000000-0000-0000-0000-%012d", n))!
            keys.append(key)
            entries[key] = DriveAliveVolume(name: "V\(n)", enabled: true)
        }
        let full = config(entries)
        XCTAssertEqual(DrivesPageModel.turningOn(a, name: "New", in: full), full, "16 on: refused")
        // Re-enabling one of the 16 is fine.
        XCTAssertEqual(DrivesPageModel.turningOn(keys[3], name: "V3", in: full).volumes[keys[3]]?.enabled, true)
        // One of them off: it is forgotten to make room.
        var oneOff = full
        oneOff.volumes[keys[5]]?.enabled = false
        let made = DrivesPageModel.turningOn(a, name: "New", in: oneOff)
        XCTAssertNil(made.volumes[keys[5]])
        XCTAssertEqual(made.volumes[a]?.enabled, true)
        XCTAssertEqual(made.volumes.values.count, DriveAliveConfig.maxVolumes)
        XCTAssertEqual(made.sanitized().volumes.values.count, DriveAliveConfig.maxVolumes)
    }

    // MARK: A failed removal (security r2 S2-1)

    func testAFailedRemovalShowsOnTheOffRowOnly() {
        let mounted = [drive(a, "Backup"), drive(b, "Photos")]
        var i = inputs(mounted, config([b: DriveAliveVolume(name: "Photos", enabled: true, firstWriteDone: true)]))
        i.removeFailures = [a: .notOurFile, b: .ioError]
        let rows = DrivesPageModel.rows(i)
        XCTAssertEqual(rows.map(\.status), [.removeFailed(.notOurFile), .active(lastWrite: nil)],
                       "an on row ignores an old removal failure")
        XCTAssertEqual(rows.first?.canToggle, true)
        XCTAssertEqual(rows.first?.offersWrite, false)
        XCTAssertEqual(DrivesPageModel.statusText(.removeFailed(.ioError), time: { _ in "" }),
                       "Turned off. Snaptic couldn’t delete its hidden .snaptic-keepalive file from the drive.")
        // An unsupported volume keeps its own reason.
        var j = inputs([drive(a, "Backup") { $0.isReadOnly = true }], config([:]))
        j.removeFailures = [a: .ioError]
        XCTAssertEqual(DrivesPageModel.rows(j).first?.status, .unsupported(.readOnly))
    }

    // MARK: Text

    func testEveryStatusHasSentenceText() {
        let statuses: [DriveRowStatus] = [
            .firstWriteRunning, .needsFirstWrite, .active(lastWrite: nil), .active(lastWrite: Date()),
            .waitingForSession, .paused, .notConnected,
        ] + [DriveAliveError.notEligible, .mountChanged, .notOurFile, .ioError, .denied].map(DriveRowStatus.failed)
          + [DriveUnsupportedReason.readOnly, .fileSystem("NTFS"), .timeMachine, .noIdentifier, .other]
            .map(DriveRowStatus.unsupported)
          + [DriveAliveError.notEligible, .mountChanged, .notOurFile, .ioError, .denied].map(DriveRowStatus.removeFailed)
        for status in statuses {
            let text = DrivesPageModel.statusText(status, time: { _ in "3:12 PM" })
            XCTAssertNotNil(text, "\(status)")
            guard let text else { continue }
            XCTAssertTrue(text.hasSuffix(".") || text.hasSuffix("…"), text)
            XCTAssertEqual(text.first.map { String($0).uppercased() == String($0) }, true, text)
        }
        XCTAssertNil(DrivesPageModel.statusText(.off, time: { _ in "" }))
        XCTAssertEqual(DrivesPageModel.statusText(.active(lastWrite: Date()), time: { _ in "3:12 PM" }),
                       "Kept awake. Last write at 3:12 PM.")
        XCTAssertTrue(DrivesPageModel.statusText(.failed(.denied), time: { _ in "" })!
            .hasPrefix("Can’t keep this drive awake: macOS denied access."))
    }

    func testNavigationValue() {
        let cfg = config([a: DriveAliveVolume(name: "A", enabled: true), b: DriveAliveVolume(name: "B", enabled: true),
                          c: DriveAliveVolume(name: "C", enabled: false)])
        XCTAssertEqual(DrivesPageModel.navigationValue(featureOn: false, config: cfg), "Off")
        XCTAssertEqual(DrivesPageModel.navigationValue(featureOn: true, config: DriveAliveConfig()), "On")
        XCTAssertEqual(DrivesPageModel.navigationValue(featureOn: true, config: cfg), "2 drives")
        XCTAssertEqual(DrivesPageModel.navigationValue(featureOn: true, config: config([a: DriveAliveVolume(name: "A", enabled: true)])),
                       "1 drive")
    }

    func testSeededFuzzNeverTrapsAndKeepsInvariants() {
        var rng = SeededGenerator(seed: 0xD21E)
        let keys = (0..<6).map { VolumeUUIDKey(rawValue: String(format: "00000000-0000-0000-0000-%012d", $0))! }
        let errors: [DriveAliveError] = [.notEligible, .mountChanged, .notOurFile, .ioError, .denied]
        for _ in 0..<2_000 {
            var mounted: [DriveCandidate] = []
            for _ in 0..<Int(rng.next() % 6) {
                let key: VolumeUUIDKey? = rng.next() % 7 == 0 ? nil : keys[Int(rng.next() % 6)]
                mounted.append(drive(key, "V\(rng.next() % 9)") { f in
                    f.isInternal = rng.next() % 5 == 0
                    f.isReadOnly = rng.next() % 5 == 0
                    f.isTimeMachine = rng.next() % 9 == 0
                    f.fileSystem = ["apfs", "exfat", "ntfs", ""][Int(rng.next() % 4)]
                })
            }
            var entries: [VolumeUUIDKey: DriveAliveVolume] = [:]
            for key in keys where rng.next() % 2 == 0 {
                entries[key] = DriveAliveVolume(name: "C", enabled: rng.next() % 2 == 0, firstWriteDone: rng.next() % 2 == 0)
            }
            var i = inputs(rng.next() % 8 == 0 ? nil : mounted, config(entries), session: rng.next() % 2 == 0,
                           background: rng.next() % 2 == 0)
            for key in keys where rng.next() % 4 == 0 { i.firstWriteRunning.insert(key) }
            for key in keys where rng.next() % 4 == 0 { i.firstWriteFailures[key] = errors[Int(rng.next() % 5)] }
            for key in keys where rng.next() % 4 == 0 { i.removeFailures[key] = errors[Int(rng.next() % 5)] }
            let rows = DrivesPageModel.rows(i)
            XCTAssertEqual(rows.count, Set(rows.map(\.id)).count, "unique ids")
            for row in rows {
                if row.isOn { XCTAssertTrue(row.canToggle) }
                if !row.isOn {
                    XCTAssertTrue(row.status == .off || {
                        switch row.status {
                        case .unsupported, .removeFailed: return true
                        default: return false
                        }
                    }())
                    XCTAssertFalse(row.offersWrite)
                }
                if case .removeFailed = row.status { XCTAssertFalse(row.isOn) }
                if row.offersWrite { XCTAssertNotNil(row.uuid) }
            }
            // Every enabled volume is shown once the mounts are known.
            if i.mounted != nil {
                let shown = Set(rows.compactMap(\.uuid))
                XCTAssertTrue(i.config.enabledVolumes.isSubset(of: shown))
            }
        }
    }
}
