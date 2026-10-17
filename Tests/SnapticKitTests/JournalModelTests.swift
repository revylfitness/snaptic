import XCTest
@testable import SnapticKit

final class JournalModelTests: XCTestCase {
    typealias L = BLayout
    private let boot = "BOOT-1"

    private func journal(_ live: LayoutSnapshot, undo: [UndoOp], at t: Double = 1000) -> SessionJournal {
        SessionJournal(bootSessionUUID: boot, uid: 501, createdAt: t, fingerprints: live.physicalFingerprints, undo: undo)
    }

    func testRecoverFiltersToSafeDirectionsWithCAS() {
        let before = L.snapshot([L.display(1, .builtin), L.display(2, x: 1920), L.display(3, x: 3840)])
        let changes: [DisplayChange] = [.enabled(2, false), .mode(1, L.mode(1280, 720)), .origin(3, x: 0, y: 1080),
                                        .mode(3, L.mode(800, 600))]
        let undo = UndoPlanner.undo(for: changes, before: before)
        let live = Invariants.predict(before, applying: changes)
        let publicModes: (UInt32) -> Set<ModeRef> = { id in id == 1 ? [L.mode(1920, 1080)] : [] }
        let d = JournalModel.evaluate(journal(live, undo: undo), bootSessionUUID: boot, uid: 501, now: 2000, live: live,
                                      publicModes: publicModes)
        guard case .recover(let ops, let colorSync) = d else { return XCTFail("\(d)") }
        XCTAssertFalse(colorSync)
        XCTAssertEqual(ops.map(\.property), [.enabled, .mode], "re-enable and the public-list mode; no origins")
        XCTAssertEqual(ops.last?.displayID, 1)
    }

    func testDiscardRules() {
        let live = L.snapshot([L.display(1), L.display(2)])
        let undo = UndoPlanner.undo(for: [.enabled(2, false)], before: live)
        let after = Invariants.predict(live, applying: [.enabled(2, false)])
        let j = journal(after, undo: undo)
        func decide(_ j: SessionJournal, boot b: String? = nil, uid: UInt32 = 501, now: Double = 2000,
                    live l: LayoutSnapshot? = nil) -> JournalModel.Decision {
            JournalModel.evaluate(j, bootSessionUUID: b ?? boot, uid: uid, now: now, live: l ?? after, publicModes: { _ in [] })
        }
        XCTAssertEqual(decide(j, boot: "OTHER"), .discard("boot"))
        XCTAssertEqual(decide(j, uid: 502), .discard("uid"))
        XCTAssertEqual(decide(j, now: 1000 + 25 * 3600), .discard("age"))
        var plugged = after
        plugged.entries.append(L.display(5))
        XCTAssertEqual(decide(j, live: plugged), .discard("displays"))
        XCTAssertEqual(decide(j, live: live), .discard("nothing to undo"), "already re-enabled: CAS skips it")
        if case .recover = decide(j) {} else { XCTFail("should recover") }
        // Snaptic's own virtuals don't count towards the display set.
        var withVirtual = after
        withVirtual.entries.append(L.display(10, .snapticVirtual))
        if case .recover = decide(j, live: withVirtual) {} else { XCTFail("virtuals are ignored") }
    }

    func testPermanentJournal() {
        var p = PermanentJournal(uid: 501)
        let rot = UndoOp(displayID: 2, fingerprint: "f2", property: .rotation, restore: .degrees(0), expected: .degrees(90))
        let rot2 = UndoOp(displayID: 2, fingerprint: "f2", property: .rotation, restore: .degrees(90), expected: .degrees(180))
        let hdr = UndoOp(displayID: 2, fingerprint: "f2", property: .hdr, restore: .bool(false), expected: .bool(true))
        let mode = UndoOp(displayID: 2, fingerprint: "f2", property: .mode, restore: .mode(L.mode(1, 1)), expected: .mode(L.mode(2, 2)))
        p.add(trial: 1, ops: [hdr, rot, mode])
        XCTAssertEqual(p.ops.count, 2, "only MonitorPanel steps")
        p.add(trial: 2, ops: [rot2])
        let revert = JournalModel.permanentToRevert(p, uid: 501)
        XCTAssertEqual(revert.map(\.property), [.rotation, .hdr], "rotation before HDR")
        XCTAssertEqual(revert.first?.restore, .degrees(0), "the oldest restore wins")
        XCTAssertTrue(JournalModel.permanentToRevert(p, uid: 0).isEmpty)
        p.resolve(trial: 1)
        p.resolve(trial: 2)
        XCTAssertTrue(p.isEmpty)
    }

    func testFilesAndNames() throws {
        let live = L.snapshot([L.display(1)])
        let j = journal(live, undo: [])
        let data = try XCTUnwrap(JournalModel.encode(j))
        XCTAssertEqual(JournalModel.decodeSession(data), j)
        XCTAssertNil(JournalModel.decodeSession(Data("{}".utf8)))
        XCTAssertNil(JournalModel.decodeSession(Data(count: JournalModel.maxFileBytes + 1)))
        let p = PermanentJournal(uid: 1, ops: [])
        XCTAssertEqual(JournalModel.decodePermanent(try XCTUnwrap(JournalModel.encode(p))), p)
        XCTAssertEqual(JournalModel.claimedName(pid: 123), "journal.claimed.123.json")
        XCTAssertEqual(JournalModel.claimedPID("journal.claimed.123.json"), 123)
        XCTAssertNil(JournalModel.claimedPID("journal.claimed..json"))
        XCTAssertNil(JournalModel.claimedPID("journal.claimed.-1.json"))
        XCTAssertNil(JournalModel.claimedPID("journal.claimed.12a.json"))
        XCTAssertNil(JournalModel.claimedPID("journal.json"))
    }

    func testFuzzDecodeNeverTraps() {
        var rng = SeededGenerator(seed: 0x10A1)
        let live = L.snapshot([L.display(1), L.display(2)])
        let seed = [UInt8](JournalModel.encode(journal(live, undo: UndoPlanner.undo(for: [.enabled(2, false)], before: live)))!)
        for _ in 0..<3000 {
            var b = seed
            for _ in 0..<Int(rng.next() % 8) { b[Int(rng.next() % UInt64(b.count))] = UInt8(truncatingIfNeeded: rng.next()) }
            if let j = JournalModel.decodeSession(Data(b)) {
                _ = JournalModel.evaluate(j, bootSessionUUID: boot, uid: 501, now: 2000, live: live, publicModes: { _ in [] })
            }
            _ = JournalModel.decodePermanent(Data(b))
        }
    }
}
