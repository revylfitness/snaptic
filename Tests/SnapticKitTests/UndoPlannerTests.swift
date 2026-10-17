import XCTest
@testable import SnapticKit

final class UndoPlannerTests: XCTestCase {
    typealias L = BLayout

    func testUndoFromRequestNotDiff() {
        let s = L.snapshot([L.display(1, .builtin), L.display(2, x: 1920)])
        let m = L.mode(2560, 1440)
        let ops = UndoPlanner.undo(for: [.mode(2, m), .origin(2, x: 100, y: 0)], before: s)
        XCTAssertEqual(ops.count, 2)
        XCTAssertEqual(ops[0].property, .mode)
        XCTAssertEqual(ops[0].restore, .mode(L.mode(1920, 1080)))
        XCTAssertEqual(ops[0].expected, .mode(m))
        XCTAssertEqual(ops[1].restore, .point(x: 1920, y: 0))
        XCTAssertEqual(ops[0].fingerprint, "fp2")
    }

    func testEveryChangeKindHasAnUndo() {
        let s = L.snapshot([L.display(1, .builtin), L.display(2, mirrorOf: 3), L.display(3), L.display(4, active: false)])
        let changes: [DisplayChange] = [.enabled(1, false), .enabled(4, true), .mirror(2, of: nil), .mirror(3, of: 1),
                                        .main(3), .rotation(3, 90), .underscan(3, 0.5), .hdr(3, true)]
        let ops = UndoPlanner.undo(for: changes, before: s)
        XCTAssertEqual(ops.count, changes.count)
        XCTAssertTrue(ops.contains { $0.property == .enabled && $0.displayID == 4 && $0.restore == .bool(false) },
                      "reconnect undoes to disable")
        XCTAssertTrue(ops.contains { $0.property == .mirrorOf && $0.displayID == 2 && $0.restore == .display(3) },
                      "stop mirroring undoes to the previous source")
        let main = ops.first { $0.property == .main }
        XCTAssertEqual(main?.displayID, 1)
        XCTAssertEqual(main?.restore, .display(1))
        XCTAssertEqual(main?.expected, .display(3))
        for op in ops { XCTAssertNotNil(UndoPlanner.change(for: op), "\(op)") }
    }

    func testRepeatedChangesKeepFirstRestoreAndLastExpected() {
        let s = L.snapshot([L.display(1)])
        let ops = UndoPlanner.undo(for: [.origin(1, x: 10, y: 0), .origin(1, x: 20, y: 0)], before: s)
        XCTAssertEqual(ops, [UndoOp(displayID: 1, fingerprint: "fp1", property: .origin, restore: .point(x: 0, y: 0),
                                    expected: .point(x: 20, y: 0))])
        XCTAssertTrue(UndoPlanner.undo(for: [.origin(1, x: 0, y: 0)], before: s).isEmpty, "no-op changes need no undo")
    }

    func testCASSkipsValuesSomeoneElseChanged() {
        let s = L.snapshot([L.display(1), L.display(2, x: 1920)])
        let ops = UndoPlanner.undo(for: [.origin(2, x: 3000, y: 0), .mode(1, L.mode(1280, 720))], before: s)
        var live = Invariants.predict(s, applying: [.origin(2, x: 3000, y: 0), .mode(1, L.mode(1280, 720))])
        XCTAssertEqual(UndoPlanner.pending(ops, live: live).count, 2)
        live.entries[1].x = 2500                                 // the user moved it in System Settings
        let pending = UndoPlanner.pending(ops, live: live)
        XCTAssertEqual(pending.map(\.property), [.mode])
    }

    func testCASModeIgnoresIoModeIDHint() {
        let s = L.snapshot([L.display(1)])
        let target = L.mode(1280, 720, id: 7)
        let ops = UndoPlanner.undo(for: [.mode(1, target)], before: s)
        var live = s
        live.entries[0].mode = L.mode(1280, 720, id: 99)
        XCTAssertEqual(UndoPlanner.pending(ops, live: live).count, 1)
    }

    func testReplugResolvesByFingerprint() {
        let s = L.snapshot([L.display(1), L.display(2)])
        let ops = UndoPlanner.undo(for: [.enabled(2, false)], before: s)
        var live = Invariants.predict(s, applying: [.enabled(2, false)])
        live.entries[1].id = 7                                   // came back with a new id
        let pending = UndoPlanner.pending(ops, live: live)
        XCTAssertEqual(pending.first?.displayID, 7)
        live.entries[1].fingerprint = "other"
        XCTAssertTrue(UndoPlanner.pending(ops, live: live).isEmpty, "a different display took the id: skip")
    }

    func testSingleUndoOrder() {
        let s = L.snapshot([L.display(1), L.display(2, active: false), L.display(3, mirrorOf: 1), L.display(4)])
        let changes: [DisplayChange] = [.main(4), .origin(4, x: 5, y: 5), .mode(4, L.mode(800, 600)), .hdr(4, true),
                                        .rotation(4, 90), .underscan(4, 0.9), .mirror(3, of: nil), .enabled(2, true),
                                        .enabled(1, false), .mirror(4, of: 1)]
        let ordered = UndoPlanner.order(UndoPlanner.undo(for: changes, before: s))
        let kinds = ordered.map { op -> String in
            switch (op.property, op.restore) {
            case (.enabled, .bool(true)): return "enable"
            case (.enabled, _): return "disable"
            case (.mirrorOf, .display(nil)): return "unmirror"
            case (.mirrorOf, _): return "remirror"
            default: return op.property.rawValue
            }
        }
        XCTAssertEqual(kinds, ["enable", "unmirror", "rotation", "underscan", "hdr", "mode", "remirror", "origin", "main", "disable"])
        let stages = UndoPlanner.stages(ordered).map(\.stage)
        XCTAssertEqual(stages, [.enable, .unmirror, .monitorPanel, .configure])
    }

    func testMergeKeepsOlderRestore() {
        let a = [UndoOp(displayID: 1, fingerprint: "f", property: .origin, restore: .point(x: 0, y: 0), expected: .point(x: 5, y: 0))]
        let b = [UndoOp(displayID: 1, fingerprint: "f", property: .origin, restore: .point(x: 5, y: 0), expected: .point(x: 9, y: 0)),
                 UndoOp(displayID: 1, fingerprint: "f", property: .rotation, restore: .degrees(0), expected: .degrees(90))]
        let m = UndoPlanner.merge(a, b)
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(m[0].restore, .point(x: 0, y: 0))
        XCTAssertEqual(m[0].expected, .point(x: 9, y: 0))
        let back = [UndoOp(displayID: 1, fingerprint: "f", property: .origin, restore: .point(x: 9, y: 0), expected: .point(x: 0, y: 0))]
        XCTAssertEqual(UndoPlanner.merge(a, back).count, 0, "returning to the start cancels out")
    }

    func testSafeDirectionsAndFractions() {
        let enable = UndoOp(displayID: 1, fingerprint: "", property: .enabled, restore: .bool(true), expected: .bool(false))
        XCTAssertTrue(enable.isSafeDirection)
        XCTAssertFalse(UndoOp(displayID: 1, fingerprint: "", property: .enabled, restore: .bool(false), expected: .bool(true)).isSafeDirection)
        XCTAssertTrue(PropertyValue.fraction(0.5).matches(.fraction(0.5004)))
        XCTAssertFalse(PropertyValue.fraction(0.5).matches(.fraction(0.51)))
    }

    func testFuzzUndoRestoresTheBeforeState() {
        var rng = SeededGenerator(seed: 0xDEED)
        for _ in 0..<3000 {
            let s = L.random(&rng)
            let n = s.entries.count
            // Origins, rotations and HDR are independent per display: applying the undo must restore them.
            var changes: [DisplayChange] = []
            for _ in 0..<Int(rng.next() % 5) {
                let id = UInt32(rng.next() % UInt64(n)) + 1
                switch rng.next() % 3 {
                case 0: changes.append(.origin(id, x: Int32(rng.next() % 3000), y: Int32(rng.next() % 2000)))
                case 1: changes.append(.rotation(id, [0, 90, 180, 270][Int(rng.next() % 4)]))
                default: changes.append(.hdr(id, rng.next() % 2 == 0))
                }
            }
            let ops = UndoPlanner.undo(for: changes, before: s)
            let after = Invariants.predict(s, applying: changes)
            let pending = UndoPlanner.pending(ops, live: after)
            XCTAssertEqual(pending.count, ops.count, "every op is pending right after the apply")
            let restored = Invariants.predict(after, applying: UndoPlanner.order(pending).compactMap(UndoPlanner.change(for:)))
            for e in s.entries {
                XCTAssertEqual(restored.entry(e.id)?.x, e.x)
                XCTAssertEqual(restored.entry(e.id)?.y, e.y)
                XCTAssertEqual(restored.entry(e.id)?.rotation, e.rotation)
                XCTAssertEqual(restored.entry(e.id)?.hdrEnabled, e.hdrEnabled)
            }
            XCTAssertTrue(UndoPlanner.pending(ops, live: restored).isEmpty, "nothing left to undo")
        }
    }
}
