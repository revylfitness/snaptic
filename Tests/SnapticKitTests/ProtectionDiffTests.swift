import XCTest
@testable import SnapticKit

final class ProtectionDiffTests: XCTestCase {
    private func key(_ c: Character) -> DisplayKey { DisplayKey(rawValue: String(repeating: c, count: 32))! }
    private func mode(_ w: Int, id: Int32 = 1) -> ModeRef {
        ModeRef(ioModeID: id, pixelWidth: w * 2, pixelHeight: w, pointWidth: w, pointHeight: w / 2, refreshMilliHz: 60_000)
    }
    private func live(_ k: Character, mode m: ModeRef?, x: Int32 = 0, y: Int32 = 0, rot: Int = 0, mirror: DisplayKey? = nil,
                      main: Bool = false, modes: [ModeRef] = []) -> LiveDisplayState {
        LiveDisplayState(key: key(k), mode: m, x: x, y: y, rotation: rot, mirrorOf: mirror, isMain: main, availableModes: modes)
    }

    func testSetKey() {
        let a = key("a"), b = key("b")
        let s = DisplaySetKey(keys: [b, a])!
        XCTAssertEqual(s.rawValue, a.rawValue + "+" + b.rawValue)
        XCTAssertEqual(s.keys, [a, b])
        XCTAssertEqual(DisplaySetKey(rawValue: s.rawValue), s)
        XCTAssertNil(DisplaySetKey(rawValue: b.rawValue + "+" + a.rawValue), "must be sorted")
        XCTAssertNil(DisplaySetKey(rawValue: a.rawValue + "+" + a.rawValue))
        XCTAssertNil(DisplaySetKey(rawValue: ""))
        XCTAssertNil(DisplaySetKey(rawValue: "zz"))
        XCTAssertNil(DisplaySetKey(keys: []))
        let decoded = try? JSONDecoder().decode(DisplaySetKey.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }

    func testNoDiffWhenEqual() {
        let l = [live("a", mode: mode(1512), main: true, modes: [mode(1512)]),
                 live("b", mode: mode(2560), x: 1512, modes: [mode(2560)])]
        let p = ProtectionDiff.capture(l)
        XCTAssertTrue(ProtectionDiff.diff(desired: p, live: l, fields: ProtectedFields()).isEmpty)
    }

    func testDiffRestoresEverything() {
        let want = [live("a", mode: mode(1512), main: true, modes: [mode(1512)]),
                    live("b", mode: mode(2560), x: 1512, y: -200, rot: 90, modes: [mode(2560), mode(1920)])]
        let p = ProtectionDiff.capture(want)
        let now = [live("a", mode: mode(1512), x: -1920, modes: [mode(1512)]),
                   live("b", mode: mode(1920, id: 7), main: true, modes: [mode(2560, id: 9), mode(1920, id: 7)])]
        let d = ProtectionDiff.diff(desired: p, live: now, fields: ProtectedFields())
        XCTAssertTrue(d.contains(.rotation(key("b"), 90)))
        XCTAssertTrue(d.contains(.mode(key("b"), mode(2560, id: 9))), "resolved against the live list")
        XCTAssertTrue(d.contains(.origin(key("a"), x: 0, y: 0)))
        XCTAssertTrue(d.contains(.origin(key("b"), x: 1512, y: -200)))
        XCTAssertTrue(d.contains(.main(key("a"))))
        // Gated fields.
        let gated = ProtectedFields().gated(by: [.arrangement])
        let g = ProtectionDiff.diff(desired: p, live: now, fields: gated)
        XCTAssertTrue(g.allSatisfy { if case .origin = $0 { return true }; return false })
    }

    func testNeverUsesUnavailableModes() {
        let p = ProtectionDiff.capture([live("a", mode: mode(3000), modes: [])])
        let d = ProtectionDiff.diff(desired: p, live: [live("a", mode: mode(1512), modes: [mode(1512)])], fields: ProtectedFields())
        XCTAssertTrue(d.isEmpty)
    }

    func testDifferentSetNoDiff() {
        let p = ProtectionDiff.capture([live("a", mode: mode(1512))])
        XCTAssertTrue(ProtectionDiff.diff(desired: p, live: [live("a", mode: mode(1000)), live("b", mode: nil)],
                                          fields: ProtectedFields()).isEmpty)
        XCTAssertTrue(ProtectionDiff.diff(desired: p, live: [], fields: ProtectedFields()).isEmpty)
    }

    func testMirrorAndMirroredOriginSkipped() {
        let want = [live("a", mode: mode(1512), main: true), live("b", mode: mode(1512), x: 50, mirror: key("a"))]
        let p = ProtectionDiff.capture(want)
        let now = [live("a", mode: mode(1512), main: true), live("b", mode: mode(1512), x: 1512)]
        let d = ProtectionDiff.diff(desired: p, live: now, fields: ProtectedFields())
        XCTAssertEqual(d, [.mirror(key("b"), of: key("a"))])
    }

    func testAppliedDiffIsNoOp() {
        // After applying the deltas, the diff is empty (planner no-op property).
        var rng = SeededGenerator(seed: 0xD1FF)
        for _ in 0..<500 {
            let modes = [mode(1280), mode(1512), mode(1920)]
            func random(_ k: Character, main: Bool) -> LiveDisplayState {
                live(k, mode: modes[Int(rng.next() % 3)], x: Int32(rng.next() % 3000), y: Int32(rng.next() % 1000),
                     rot: [0, 90, 180, 270][Int(rng.next() % 4)], main: main, modes: modes)
            }
            let want = [random("a", main: true), random("b", main: false)]
            var now = [random("a", main: rng.next() % 2 == 0), random("b", main: false)]
            now[1].isMain = !now[0].isMain
            let p = ProtectionDiff.capture(want)
            for delta in ProtectionDiff.diff(desired: p, live: now, fields: ProtectedFields()) {
                let i = now.firstIndex { $0.key == delta.key }!
                switch delta {
                case .mode(_, let m): now[i].mode = m
                case .origin(_, let x, let y): now[i].x = x; now[i].y = y
                case .rotation(_, let r): now[i].rotation = r
                case .mirror(_, let s): now[i].mirrorOf = s
                case .main: for j in now.indices { now[j].isMain = j == i }
                }
            }
            XCTAssertTrue(ProtectionDiff.diff(desired: p, live: now, fields: ProtectedFields()).isEmpty)
        }
    }

    func testFightTracker() {
        let s = DisplaySetKey(keys: [key("a")])!
        var t = ProtectionFightTracker()
        XCTAssertFalse(t.noteOverwrite(s, at: 0))
        XCTAssertFalse(t.noteOverwrite(s, at: 40), "outside the 30 s window")
        XCTAssertTrue(t.noteOverwrite(s, at: 55))
        XCTAssertTrue(t.isStopped(s))
        t.reset(s)
        XCTAssertFalse(t.isStopped(s))
        XCTAssertFalse(t.noteOverwrite(s, at: 60))
    }

    func testUpdatingKeepsSet() {
        let p = ProtectionDiff.capture([live("a", mode: mode(1512))], at: 1)
        let same = ProtectionDiff.updating(p, with: [live("a", mode: mode(1920))], at: 2)
        XCTAssertEqual(same.displays[key("a")]?.mode, mode(1920))
        let other = ProtectionDiff.updating(p, with: [live("b", mode: mode(1920))], at: 3)
        XCTAssertEqual(other, p)
    }
}
