import XCTest
@testable import SnapticKit

// 0.5 B1b (§4.12 step 6, H3, §6.1): the window symbols' crash guard — the launch rule, the in-flight ledger, the
// verified build, the give-back's own marker, Try Again, and the ⌘⇥ ledger with its pending list.

/// A marker directory in memory. Every write and remove is logged so the tests can check their order.
private final class FakeMarkerFiles: InflightMarkerFiles, @unchecked Sendable {
    private let lock = NSLock()
    private var present: [String: String] = [:]
    private var log: [String] = []
    private var failWrites = false
    private let build: String

    init(build: String) { self.build = build }

    func write(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if failWrites { return false }
        log.append("write " + name)
        present[name] = build
        return true
    }

    func remove(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        log.append("remove " + name)
        present[name] = nil
    }

    func setFailWrites(_ value: Bool) {
        lock.lock()
        failWrites = value
        lock.unlock()
    }

    func exists(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return present[name] != nil
    }

    /// What a crash leaves on disk, as the next launch reads it.
    var onDisk: [String: String?] {
        lock.lock()
        defer { lock.unlock() }
        return present.mapValues { Optional($0) }
    }

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

private func makeLedger(_ files: FakeMarkerFiles) -> InflightLedger {
    InflightLedger(names: CrashGuard.markerNames, files: files, makeLock: { _ in KitInflightLock() })
}

private let build = "26B123"

final class CrashGuardTests: XCTestCase {
    // MARK: Launch rule (X2-3, X3-8)

    func testOverlappingSymbolsLeaveOnlyTheCrashingOnesMarker() {
        let files = FakeMarkerFiles(build: build)
        let ledger = makeLedger(files)
        XCTAssertTrue(ledger.begin(WindowSymbolID.copySpaces.rawValue))
        XCTAssertTrue(ledger.begin(WindowSymbolID.postEventRecord.rawValue))
        ledger.end(WindowSymbolID.copySpaces.rawValue)
        // The process dies inside the second call.
        let decision = CrashGuard.atLaunch(markers: files.onDisk, currentBuild: build, previousRunCleanQuit: false)
        XCTAssertEqual(decision.disable, ["postEventRecord"])
        XCTAssertEqual(decision.remove, ["postEventRecord"])
    }

    func testAnotherBuildsMarkerIsIgnoredAndRemoved() {
        let markers: [String: String?] = ["copySpaces": "25A100", "layoutType": build + "\n"]
        let decision = CrashGuard.atLaunch(markers: markers, currentBuild: build, previousRunCleanQuit: false)
        XCTAssertEqual(decision.disable, ["layoutType"])
        XCTAssertEqual(decision.remove, ["copySpaces", "layoutType"])
    }

    func testAMarkerAfterACleanQuitIsIgnored() {
        let markers: [String: String?] = ["copySpaces": build, CrashGuard.giveBackMarker: build]
        let decision = CrashGuard.atLaunch(markers: markers, currentBuild: build, previousRunCleanQuit: true)
        XCTAssertEqual(decision.disable, [])
        XCTAssertEqual(decision.remove, ["copySpaces", CrashGuard.giveBackMarker].sorted())

        XCTAssertTrue(CrashGuard.previousRunCleanQuit(LaunchHistory()))
        let crashed = LaunchHistory(records: [LaunchRecord(startedAt: 1, survived: true, cleanQuit: true),
                                              LaunchRecord(startedAt: 2, survived: true, cleanQuit: false)])
        XCTAssertFalse(CrashGuard.previousRunCleanQuit(crashed))
        let clean = LaunchHistory(records: [LaunchRecord(startedAt: 2, survived: false, cleanQuit: true)])
        XCTAssertTrue(CrashGuard.previousRunCleanQuit(clean))
    }

    func testUnknownUnreadableAndBuildlessMarkersNeverDisable() {
        let markers: [String: String?] = ["stray": build, "copySpaces": nil, "hwCapture": ""]
        let decision = CrashGuard.atLaunch(markers: markers, currentBuild: build, previousRunCleanQuit: false)
        XCTAssertEqual(decision.disable, [])
        XCTAssertEqual(decision.remove, ["copySpaces", "hwCapture", "stray"])
        let noBuild = CrashGuard.atLaunch(markers: ["hwCapture": ""], currentBuild: "", previousRunCleanQuit: false)
        XCTAssertEqual(noBuild.disable, [])
    }

    func testDisabledBuildHoldsForThisBuildOnly() {
        XCTAssertTrue(CrashGuard.isDisabled(disabledBuild: build, currentBuild: build))
        XCTAssertFalse(CrashGuard.isDisabled(disabledBuild: "25A100", currentBuild: build))
        XCTAssertFalse(CrashGuard.isDisabled(disabledBuild: nil, currentBuild: build))
        XCTAssertFalse(CrashGuard.isDisabled(disabledBuild: "", currentBuild: ""))
    }

    // MARK: Names and Try Again (G3-2)

    func testTheGiveBackMarkerIsSeparateFromTheTake() {
        let names = CrashGuard.markerNames
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.contains(CrashGuard.giveBackMarker))
        XCTAssertTrue(names.contains(WindowSymbolID.setSymbolicHotKeyEnabled.rawValue))
        XCTAssertNotEqual(CrashGuard.giveBackTryAgainKey,
                          CrashGuard.disabledKey(WindowSymbolID.setSymbolicHotKeyEnabled.rawValue))
        XCTAssertEqual(CrashGuard.giveBackTryAgainKey, "Windows.disabledBuild.symbolicHotKeys.giveBack")
        let markers: [String: String?] = [CrashGuard.giveBackMarker: build]
        XCTAssertEqual(CrashGuard.atLaunch(markers: markers, currentBuild: build, previousRunCleanQuit: false).disable,
                       [CrashGuard.giveBackMarker])
    }

    func testTryAgainClearsOnlyItsFeature() {
        XCTAssertEqual(CrashGuard.tryAgainKeys(.raise), [
            "Windows.disabledBuild.getProcessForPID", "Windows.disabledBuild.setFrontProcess",
            "Windows.disabledBuild.postEventRecord",
        ])
        XCTAssertEqual(CrashGuard.tryAgainKeys(.symbolicHotKeys), [
            "Windows.disabledBuild.isSymbolicHotKeyEnabled", "Windows.disabledBuild.setSymbolicHotKeyEnabled",
        ])
        for feature in WindowFeature.allCases {
            XCTAssertFalse(CrashGuard.tryAgainKeys(feature).contains(CrashGuard.giveBackTryAgainKey), "\(feature)")
        }
        XCTAssertEqual(CrashGuard.verifiedKey("copySpaces"), "Windows.verifiedBuild.copySpaces")
        XCTAssertEqual(CrashGuard.probedKey("hwCapture"), "Windows.probedBuild.hwCapture")
    }

    // MARK: Verified build (X2-4)

    func testVerifiedBuildStopsMarkersForReadOnlySymbolsOnly() {
        for id in WindowSymbolID.allCases {
            XCTAssertTrue(CrashGuard.needsMarker(id, verifiedBuild: nil, currentBuild: build), "\(id)")
            XCTAssertTrue(CrashGuard.needsMarker(id, verifiedBuild: "25A100", currentBuild: build), "\(id)")
            XCTAssertEqual(CrashGuard.needsMarker(id, verifiedBuild: build, currentBuild: build), !id.readOnly, "\(id)")
        }
    }

    func testVerifiedAfterTwentySuccessesOnAVerifiedMajorOnly() {
        XCTAssertTrue(CrashGuard.shouldMarkVerified(.copySpaces, successes: 20, major: 27, alreadyVerified: false))
        XCTAssertTrue(CrashGuard.shouldMarkVerified(.layoutType, successes: 25, major: 15, alreadyVerified: false))
        XCTAssertFalse(CrashGuard.shouldMarkVerified(.copySpaces, successes: 19, major: 27, alreadyVerified: false))
        XCTAssertFalse(CrashGuard.shouldMarkVerified(.copySpaces, successes: 20, major: 26, alreadyVerified: false),
                       "0.4's symbols are never marked verified on an unverified major")
        XCTAssertFalse(CrashGuard.shouldMarkVerified(.copySpaces, successes: 20, major: 27, alreadyVerified: true))
        XCTAssertFalse(CrashGuard.shouldMarkVerified(.setSymbolicHotKeyEnabled, successes: 99, major: 27,
                                                     alreadyVerified: false))
        XCTAssertFalse(CrashGuard.shouldMarkVerified(.hwCapture, successes: 99, major: 27, alreadyVerified: false))
    }

    func testLedgerCountsSuccesses() {
        let files = FakeMarkerFiles(build: build)
        let ledger = makeLedger(files)
        let name = WindowSymbolID.copySpaces.rawValue
        XCTAssertTrue(ledger.begin(name))
        XCTAssertEqual(ledger.end(name, succeeded: true), 1)
        XCTAssertTrue(ledger.begin(name))
        XCTAssertEqual(ledger.end(name, succeeded: false), 1)
        XCTAssertEqual(ledger.noteSuccess(name), 2)
        XCTAssertEqual(files.events, ["write copySpaces", "remove copySpaces", "write copySpaces", "remove copySpaces"])
        XCTAssertFalse(ledger.begin("stray"))
        XCTAssertEqual(ledger.end("stray"), 0)
    }

    // MARK: Marker writes (X3-8, P3-6)

    func testAFailedMarkerWriteTakesTheFallbackWithNothingInFlight() {
        let files = FakeMarkerFiles(build: build)
        let ledger = makeLedger(files)
        let name = WindowSymbolID.hwCapture.rawValue
        files.setFailWrites(true)
        XCTAssertFalse(ledger.begin(name))
        XCTAssertEqual(ledger.inFlight(name), 0)
        files.setFailWrites(false)
        XCTAssertTrue(ledger.begin(name))
        XCTAssertEqual(ledger.inFlight(name), 1)
        XCTAssertTrue(files.exists(name))
        ledger.end(name)
        XCTAssertFalse(files.exists(name))
    }

    func testOverlappingCallsOnOneSymbolKeepTheMarkerUntilTheLastEnds() {
        let files = FakeMarkerFiles(build: build)
        let ledger = makeLedger(files)
        let name = WindowSymbolID.mainConnection.rawValue
        XCTAssertTrue(ledger.begin(name))
        XCTAssertTrue(ledger.begin(name))
        ledger.end(name)
        XCTAssertTrue(files.exists(name), "the second call is still in flight")
        ledger.end(name)
        XCTAssertFalse(files.exists(name))
        XCTAssertEqual(files.events, ["write mainConnection", "remove mainConnection"])
    }

    func testConcurrentCallsOnOneSymbolNeverLoseTheMarkerWhileInFlight() {
        let files = FakeMarkerFiles(build: build)
        let ledger = makeLedger(files)
        let name = WindowSymbolID.copySpaces.rawValue
        let missing = Counter()
        DispatchQueue.concurrentPerform(iterations: 2_000) { _ in
            guard ledger.begin(name) else { missing.add(); return }
            if !files.exists(name) { missing.add() }
            ledger.end(name)
        }
        XCTAssertEqual(missing.count, 0)
        XCTAssertEqual(ledger.inFlight(name), 0)
        XCTAssertFalse(files.exists(name))
        // Writes and removes alternate: an unlink never lands between another call's write and its count.
        let events = files.events
        XCTAssertFalse(events.isEmpty)
        for (i, event) in events.enumerated() {
            XCTAssertEqual(event, (i % 2 == 0 ? "write " : "remove ") + name, "event \(i)")
        }
    }

    // MARK: ⌘⇥ ledger (X3-2)

    func testPendingGiveBackSurvivesTheNextApplyAndBlocksTheTake() {
        let port = FakeHotkeyPort()
        port.saved = [6]
        port.pending = [1, 2]
        let ledger = SystemHotkeyLedger(port: port)
        XCTAssertEqual(ledger.atLaunch(giveBackDisabled: true), .movedToPending(3))
        XCTAssertEqual(port.pending, [1, 2, 6])
        XCTAssertNil(port.saved)
        XCTAssertFalse(port.events.contains { $0.hasPrefix("give") }, "no give-back under its own crash guard")

        port.events = []
        ledger.apply(SystemHotkeyLedger.wanted(commandTab: true, commandBacktick: true), takeBlocked: false)
        XCTAssertEqual(port.pending, [1, 2, 6], "apply never writes or removes the pending list")
        XCTAssertFalse(port.events.contains { $0.hasPrefix("take") }, "no take while the give-back is disabled")
        XCTAssertEqual(ledger.owned, [])
        ledger.reassert(takeBlocked: false)
        ledger.setSuspended(true, takeBlocked: false)
        ledger.setSuspended(false, takeBlocked: false)
        XCTAssertFalse(port.events.contains { $0.hasPrefix("take") })
        XCTAssertEqual(port.pending, [1, 2, 6])
    }

    func testTryAgainGivesThePendingListBackMarkerFirstAndRemovesTheKeyAfter() {
        let port = FakeHotkeyPort()
        port.saved = [1, 2]
        let ledger = SystemHotkeyLedger(port: port)
        _ = ledger.atLaunch(giveBackDisabled: true)
        port.events = []
        XCTAssertEqual(ledger.giveBackPendingNow(), 2)
        XCTAssertEqual(port.events, ["begin", "give 1", "give 2", "end", "removePending"])
        XCTAssertNil(port.pending)
        XCTAssertFalse(ledger.giveBackDisabled)

        // The take works again afterwards.
        port.events = []
        ledger.apply([1, 2], takeBlocked: false)
        XCTAssertEqual(ledger.owned, [1, 2])
        XCTAssertTrue(port.events.contains("take 1"))
    }

    func testANewBuildGivesSavedAndPendingBackThenRemovesBothKeys() {
        let port = FakeHotkeyPort()
        port.saved = [6]
        port.pending = [1, 2, 99]
        let ledger = SystemHotkeyLedger(port: port)
        XCTAssertEqual(ledger.atLaunch(giveBackDisabled: false), .gaveBack(3))
        XCTAssertEqual(port.events, ["begin", "give 1", "give 2", "give 6", "end", "removeSaved", "removePending"])
        XCTAssertNil(port.saved)
        XCTAssertNil(port.pending)
    }

    func testNothingToGiveBackAtLaunch() {
        let port = FakeHotkeyPort()
        let ledger = SystemHotkeyLedger(port: port)
        XCTAssertEqual(ledger.atLaunch(giveBackDisabled: false), .nothing)
        XCTAssertEqual(ledger.atLaunch(giveBackDisabled: true), .nothing)
        XCTAssertEqual(port.events, [])
    }

    func testApplySavesBeforeTakingAndSkipsShortcutsTheUserTurnedOff() {
        let port = FakeHotkeyPort()
        port.enabled[6] = false
        let ledger = SystemHotkeyLedger(port: port)
        ledger.apply(SystemHotkeyLedger.wanted(commandTab: true, commandBacktick: true), takeBlocked: false)
        XCTAssertEqual(port.events.first, "saved [1, 2]")
        XCTAssertEqual(Array(port.events.dropFirst().prefix(2)), ["take 1", "take 2"])
        XCTAssertEqual(ledger.owned, [1, 2])
        XCTAssertEqual(port.saved, [1, 2])
        XCTAssertEqual(port.held, [1, 2])
    }

    func testAFailedTakeIsDroppedAndABlockedTakeGivesBack() {
        let port = FakeHotkeyPort()
        port.failTakes = [2]
        let ledger = SystemHotkeyLedger(port: port)
        ledger.apply([1, 2], takeBlocked: false)
        XCTAssertEqual(ledger.owned, [1])
        XCTAssertEqual(port.saved, [1])

        port.events = []
        ledger.apply([1, 2], takeBlocked: true)
        XCTAssertEqual(port.events, ["saved [1]", "begin", "give 1", "end", "removeSaved", "guard []"])
        XCTAssertEqual(ledger.owned, [])
    }

    func testSuspendGivesBackAndResumeTakesAgainUnlessBlocked() {
        let port = FakeHotkeyPort()
        let ledger = SystemHotkeyLedger(port: port)
        ledger.apply([1, 2], takeBlocked: false)
        port.events = []
        ledger.setSuspended(true, takeBlocked: false)
        XCTAssertEqual(port.events, ["begin", "give 1", "give 2", "end", "guard []"])
        port.events = []
        ledger.setSuspended(false, takeBlocked: true)
        XCTAssertEqual(port.events, ["guard []"])
        XCTAssertEqual(ledger.owned, [1, 2], "still Snaptic's, so restore gives them back")
        ledger.setSuspended(true, takeBlocked: false)
        port.events = []
        ledger.setSuspended(false, takeBlocked: false)
        XCTAssertEqual(port.events, ["take 1", "take 2", "guard [1, 2]"])
    }

    func testRestoreGivesEverythingBackOnce() {
        let port = FakeHotkeyPort()
        let ledger = SystemHotkeyLedger(port: port)
        ledger.apply([1, 2, 6], takeBlocked: false)
        port.events = []
        ledger.restore()
        XCTAssertEqual(port.events, ["begin", "give 1", "give 2", "give 6", "end", "guard []", "removeSaved"])
        port.events = []
        ledger.restore()
        XCTAssertEqual(port.events, [])
    }
}

/// The ⌘⇥ port in memory. Ids are logged in the order the ledger sends them.
private final class FakeHotkeyPort: SystemHotkeyPort {
    var saved: [Int]?
    var pending: [Int]?
    var enabled: [Int32: Bool] = [:]
    var failTakes: Set<Int32> = []
    var held: Set<Int32> = []
    var events: [String] = []

    func savedIDs() -> [Int]? { saved }
    func setSavedIDs(_ ids: [Int]) { saved = ids; events.append("saved \(ids)") }
    func removeSavedIDs() { saved = nil; events.append("removeSaved") }
    func pendingIDs() -> [Int]? { pending }
    func setPendingIDs(_ ids: [Int]) { pending = ids; events.append("pending \(ids)") }
    func removePendingIDs() { pending = nil; events.append("removePending") }
    func isEnabled(_ id: Int32) -> Bool? { enabled[id] ?? true }

    func take(_ id: Int32) -> Bool {
        events.append("take \(id)")
        guard !failTakes.contains(id) else { return false }
        enabled[id] = false
        return true
    }

    func beginGiveBack() { events.append("begin") }

    func giveBack(_ id: Int32) {
        enabled[id] = true
        events.append("give \(id)")
    }

    func endGiveBack() { events.append("end") }

    func guardHolds(_ ids: Set<Int32>) {
        held = ids
        events.append("guard \(ids.sorted())")
    }
}
