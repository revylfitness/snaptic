import XCTest
@testable import SnapticKit

/// Layout builders shared by team B's tests.
enum BLayout {
    static func mode(_ w: Int, _ h: Int, hidpi: Bool = false, hz: Int = 60, id: Int32 = 1) -> ModeRef {
        let s = hidpi ? 2 : 1
        return ModeRef(ioModeID: id, pixelWidth: w * s, pixelHeight: h * s, pointWidth: w, pointHeight: h,
                       refreshMilliHz: hz * 1000)
    }

    static func display(_ id: UInt32, _ transport: Transport = .wired, x: Int32 = 0, y: Int32 = 0, active: Bool = true,
                        mirrorOf: UInt32? = nil, dim: Double = 1, overlay: Double = 1, headless: Bool = false,
                        asleep: Bool = false, disabledBySnaptic: Bool = false, rotation: Int = 0,
                        mode: ModeRef? = nil) -> LayoutEntry {
        let m = mode ?? BLayout.mode(1920, 1080)
        return LayoutEntry(id: id, fingerprint: "fp\(id)", transport: transport, isOnline: true, isActive: active,
                           isAsleep: asleep, mirrorOf: mirrorOf, x: x, y: y, width: m.pointWidth, height: m.pointHeight,
                           rotation: rotation, mode: m, underscan: 0, hdrEnabled: false, softwareDim: dim,
                           headlessPrimary: headless, overlayDim: overlay, disabledBySnaptic: disabledBySnaptic)
    }

    static func snapshot(_ entries: [LayoutEntry], main: UInt32? = nil) -> LayoutSnapshot {
        LayoutSnapshot(entries: entries, mainID: main ?? entries.first?.id ?? 0)
    }

    /// A random layout of 1–5 displays (fuzzing).
    static func random(_ rng: inout SeededGenerator) -> LayoutSnapshot {
        let count = Int(rng.next() % 5) + 1
        let transports = Transport.allCases
        var entries: [LayoutEntry] = []
        for i in 0..<count {
            let id = UInt32(i + 1)
            let t = transports[Int(rng.next() % UInt64(transports.count))]
            var e = display(id, t, x: Int32(i * 1920), active: rng.next() % 5 != 0,
                            mirrorOf: rng.next() % 4 == 0 ? UInt32(rng.next() % UInt64(count)) + 1 : nil,
                            dim: rng.next() % 6 == 0 ? 0 : 1, overlay: rng.next() % 8 == 0 ? 0.1 : 1,
                            headless: rng.next() % 3 == 0, asleep: rng.next() % 10 == 0,
                            disabledBySnaptic: rng.next() % 7 == 0)
            if e.mirrorOf == id { e.mirrorOf = nil }
            entries.append(e)
        }
        return snapshot(entries, main: UInt32(rng.next() % UInt64(count)) + 1)
    }

    static func randomChange(_ rng: inout SeededGenerator, count: Int) -> DisplayChange {
        let id = UInt32(rng.next() % UInt64(max(count, 1))) + 1
        switch rng.next() % 8 {
        case 0: return .mode(id, mode(1280, 720, hidpi: rng.next() % 2 == 0))
        case 1: return .origin(id, x: Int32(truncatingIfNeeded: rng.next() % 4000), y: 0)
        case 2: return .mirror(id, of: rng.next() % 2 == 0 ? nil : UInt32(rng.next() % UInt64(max(count, 1))) + 1)
        case 3: return .enabled(id, rng.next() % 2 == 0)
        case 4: return .main(id)
        case 5: return .rotation(id, [0, 90, 180, 270][Int(rng.next() % 4)])
        case 6: return .underscan(id, 0.5)
        default: return .hdr(id, rng.next() % 2 == 0)
        }
    }
}

final class LayoutModelTests: XCTestCase {
    func testModeRefHiDPIAndShape() {
        let a = BLayout.mode(1920, 1080, hidpi: true, id: 5)
        XCTAssertTrue(a.isHiDPI)
        XCTAssertFalse(BLayout.mode(1920, 1080).isHiDPI)
        var b = a
        b.ioModeID = 99
        b.refreshMilliHz += 5
        XCTAssertTrue(a.sameShape(as: b))
        b.refreshMilliHz += 50
        XCTAssertFalse(a.sameShape(as: b))
        XCTAssertFalse(ModeRef(ioModeID: 0, pixelWidth: 0, pixelHeight: 0, pointWidth: 0, pointHeight: 0, refreshMilliHz: 0).isHiDPI)
    }

    func testEnabledCountsMirrorMembers() {
        var e = BLayout.display(1, active: false, mirrorOf: 2)
        XCTAssertTrue(e.isEnabled)
        e.mirrorOf = nil
        XCTAssertFalse(e.isEnabled)
        e.isActive = true
        e.isOnline = false
        XCTAssertFalse(e.isEnabled)
    }

    func testEffectiveDimTakesTheDarkerLayer() {
        XCTAssertEqual(BLayout.display(1, dim: 0.5, overlay: 0.2).effectiveDim, 0.2, accuracy: 1e-9)
        XCTAssertEqual(BLayout.display(1, dim: -1).effectiveDim, 0)
    }

    func testFingerprintLookupRequiresUniqueness() {
        var a = BLayout.display(1), b = BLayout.display(2)
        b.fingerprint = a.fingerprint
        let s = BLayout.snapshot([a, b])
        XCTAssertNil(s.entry(fingerprint: a.fingerprint))
        a.fingerprint = "x"
        XCTAssertEqual(BLayout.snapshot([a, b]).entry(fingerprint: "x")?.id, 1)
        XCTAssertNil(s.entry(fingerprint: ""))
    }

    func testPhysicalFingerprintsSkipSnapticVirtuals() {
        let s = BLayout.snapshot([BLayout.display(2), BLayout.display(1, .snapticVirtual), BLayout.display(3, .builtin)])
        XCTAssertEqual(s.physicalFingerprints, ["fp2", "fp3"])
    }

    func testChangeClassification() {
        XCTAssertTrue(DisplayChange.enabled(1, true).isVisibilityRestoring)
        XCTAssertTrue(DisplayChange.mirror(1, of: nil).isVisibilityRestoring)
        XCTAssertFalse(DisplayChange.enabled(1, false).isVisibilityRestoring)
        XCTAssertTrue(DisplayChange.hdr(1, true).isMonitorPanel)
        XCTAssertEqual(DisplayChange.mode(1, BLayout.mode(1, 1)).keepScope, .permanently)
        XCTAssertEqual(DisplayChange.mirror(1, of: 2).keepScope, .forSession)
        XCTAssertNil(DisplayChange.rotation(1, 90).keepScope)
        XCTAssertEqual(DisplayChange.origin(3, x: 1, y: 2).displayID, 3)
        XCTAssertEqual(DisplayChange.main(3).property, .main)
    }

    func testSnapshotRoundTrips() throws {
        var rng = SeededGenerator(seed: 0xB10C)
        for _ in 0..<200 {
            let s = BLayout.random(&rng)
            let data = try JSONEncoder().encode(s)
            XCTAssertEqual(try JSONDecoder().decode(LayoutSnapshot.self, from: data), s)
        }
        let v: [InvariantViolation] = [.noVisibleDisplay, .mainNotVisible(3), .onlyDisplayUnsupported(1)]
        XCTAssertEqual(try JSONDecoder().decode([InvariantViolation].self, from: JSONEncoder().encode(v)), v)
        XCTAssertFalse(InvariantViolation.noPanelHost.message.isEmpty)
    }
}
