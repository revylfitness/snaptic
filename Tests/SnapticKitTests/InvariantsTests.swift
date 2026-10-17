import XCTest
@testable import SnapticKit

final class InvariantsTests: XCTestCase {
    typealias L = BLayout

    // MARK: Visibility

    func testBasicClassification() {
        let s = L.snapshot([L.display(1, .builtin), L.display(2, .airplay), L.display(3, .snapticVirtual),
                            L.display(4, .snapticVirtual, headless: true), L.display(5, .sidecar),
                            L.display(6, .wired, active: false)])
        let v = Invariants.visibility(s)
        XCTAssertEqual(v[1], .strong)
        XCTAssertEqual(v[2], .weak)
        XCTAssertEqual(v[3], Visibility.none)
        XCTAssertEqual(v[4], .weak, "headlessPrimary virtuals are weakly visible")
        XCTAssertEqual(v[5], .weak)
        XCTAssertEqual(v[6], Visibility.none, "inactive")
    }

    func testDimmedAsleepAndOfflineAreNotVisible() {
        var off = L.display(4)
        off.isOnline = false
        let s = L.snapshot([L.display(1, dim: 0.05), L.display(2, overlay: 0.01), L.display(3, asleep: true), off])
        XCTAssertTrue(Invariants.visible(s).isEmpty)
        XCTAssertEqual(Invariants.visibility(L.snapshot([L.display(1, dim: 0.08)]))[1], .strong, "floor is inclusive")
    }

    func testMirrorMembershipHardwareAndSoftware() {
        // Hardware mirror members are online but not active.
        let s = L.snapshot([L.display(1, .builtin), L.display(2, active: false, mirrorOf: 1)])
        XCTAssertEqual(Invariants.visibility(s)[2], .strong)
        XCTAssertEqual(Invariants.panelHosts(s), [1])
        // A member of a set whose source isn't strongly visible (AirPlay source) isn't strong.
        let s2 = L.snapshot([L.display(1, .airplay), L.display(2, mirrorOf: 1)])
        XCTAssertEqual(Invariants.visibility(s2)[2], Visibility.none)
        // A member of a non-physical transport never inherits.
        let s3 = L.snapshot([L.display(1, .builtin), L.display(2, .airplay, mirrorOf: 1)])
        XCTAssertEqual(Invariants.visibility(s3)[2], Visibility.none)
    }

    func testSmartHiDPIPairIsStronglyVisibleThroughTheVirtual() {
        let s = L.snapshot([L.display(10, .snapticVirtual), L.display(2, active: false, mirrorOf: 10)], main: 10)
        XCTAssertEqual(Invariants.visibility(s)[2], .strong)
        XCTAssertEqual(Invariants.panelHosts(s), [10], "the panel goes on the virtual source")
        XCTAssertTrue(Invariants.violations(before: s, changes: []).isEmpty, "main may be the virtual source")
        // Dimming the virtual to black blacks out the member.
        let dark = L.snapshot([L.display(10, .snapticVirtual, dim: 0), L.display(2, active: false, mirrorOf: 10)])
        XCTAssertEqual(Invariants.visibility(dark)[2], Visibility.none)
    }

    func testMirrorCycleAndMissingSourceAreNotVisible() {
        let s = L.snapshot([L.display(1, mirrorOf: 2), L.display(2, mirrorOf: 1)])
        XCTAssertNil(Invariants.mirrorRoot(of: 1, in: s))
        XCTAssertTrue(Invariants.visible(s).isEmpty)
        let missing = L.snapshot([L.display(1, mirrorOf: 9)])
        XCTAssertTrue(Invariants.visible(missing).isEmpty)
    }

    // MARK: Prediction

    func testPredictModeRotationAndMain() {
        let s = L.snapshot([L.display(1, .builtin), L.display(2, x: 1920)])
        let m = L.mode(2560, 1440, hidpi: true)
        var p = Invariants.predict(s, applying: [.mode(2, m), .rotation(2, 90)])
        XCTAssertEqual(p.entry(2)?.width, 1440)
        XCTAssertEqual(p.entry(2)?.height, 2560)
        XCTAssertEqual(p.entry(2)?.rotation, 90)
        p = Invariants.predict(s, applying: [.main(2)])
        XCTAssertEqual(p.mainID, 2)
        XCTAssertEqual(p.entry(2)?.x, 0, "the new main moves to the origin")
        XCTAssertEqual(p.entry(1)?.x, -1920)
        XCTAssertEqual(Invariants.normalizedRotation(-90), 270)
        XCTAssertEqual(Invariants.normalizedRotation(450), 90)
    }

    func testPredictDisableBreaksMirrorsOfThatSource() {
        let s = L.snapshot([L.display(1, .builtin), L.display(2, active: false, mirrorOf: 1), L.display(3)])
        let p = Invariants.predict(s, applying: [.enabled(1, false)])
        XCTAssertFalse(p.entry(1)!.isEnabled)
        XCTAssertTrue(p.entry(1)!.disabledBySnaptic)
        XCTAssertNil(p.entry(2)?.mirrorOf)
        XCTAssertEqual(p.entry(2)?.isActive, true)
        // Un-mirroring re-activates.
        let q = Invariants.predict(s, applying: [.mirror(2, of: nil)])
        XCTAssertEqual(q.entry(2)?.isActive, true)
    }

    // MARK: Invariants

    func testCannotDisableTheOnlyDisplay() {
        let s = L.snapshot([L.display(1, .builtin)])
        let v = Invariants.violations(before: s, changes: [.enabled(1, false)])
        XCTAssertTrue(v.contains(.noVisibleDisplay))
        XCTAssertTrue(v.contains(.noPanelHost))
    }

    func testStrongToWeakOnlyIsRefused() {
        let s = L.snapshot([L.display(1, .builtin), L.display(2, .airplay)])
        XCTAssertTrue(Invariants.violations(before: s, changes: [.enabled(1, false), .main(2)]).contains(.noVisibleDisplay))
        // Without any strong display, keeping a weak one is enough.
        let w = L.snapshot([L.display(2, .airplay), L.display(3, .sidecar)])
        XCTAssertFalse(Invariants.violations(before: w, changes: [.enabled(3, false)]).contains(.noVisibleDisplay))
    }

    func testDisablingOneOfTwoIsFineButMainMustMove() {
        let s = L.snapshot([L.display(1, .builtin), L.display(2, x: 1920)], main: 1)
        let v = Invariants.violations(before: s, changes: [.enabled(1, false)])
        XCTAssertEqual(v, [.mainNotVisible(1)])
        XCTAssertTrue(Invariants.violations(before: s, changes: [.main(2), .enabled(1, false)]).isEmpty)
    }

    func testMirroringEverythingOntoAVirtualKeepsVisibility() {
        let s = L.snapshot([L.display(1, .builtin), L.display(10, .snapticVirtual, x: 3000)], main: 1)
        let v = Invariants.violations(before: s, changes: [.mirror(1, of: 10), .main(10)])
        XCTAssertTrue(v.isEmpty, "\(v)")
    }

    func testDimToBlackNeedsAnotherStrongDisplay() {
        let one = L.snapshot([L.display(1, .builtin)])
        XCTAssertEqual(Invariants.violations(before: one, changes: [], context: InvariantContext(dimToBlack: [1])),
                       [.dimToBlackWithoutOtherVisible(1)])
        XCTAssertEqual(Invariants.dimFloor(for: 1, in: one), Invariants.dimFloor)
        let two = L.snapshot([L.display(1, .builtin), L.display(2)])
        XCTAssertTrue(Invariants.violations(before: two, changes: [], context: InvariantContext(dimToBlack: [1])).isEmpty)
        XCTAssertEqual(Invariants.dimFloor(for: 1, in: two), 0)
    }

    func testLongArmNeedsTheGuard() {
        let s = L.snapshot([L.display(1, .builtin), L.display(2)])
        let ctx = InvariantContext(guardAvailable: false)
        XCTAssertEqual(Invariants.violations(before: s, changes: [.enabled(2, false)], context: ctx), [.guardNotArmed])
        XCTAssertTrue(Invariants.violations(before: s, changes: [.origin(2, x: 0, y: 1080)], context: ctx).isEmpty)
    }

    func testUnattendedNeverModesetsTheOnlyStrongDisplay() {
        let s = L.snapshot([L.display(1), L.display(2, .airplay)])
        let ctx = InvariantContext(unattended: true)
        XCTAssertEqual(Invariants.violations(before: s, changes: [.mode(1, L.mode(1280, 720))], context: ctx),
                       [.onlyDisplayUnsupported(1)])
        XCTAssertTrue(Invariants.violations(before: s, changes: [.origin(1, x: 0, y: 0)], context: ctx).isEmpty)
        // Changing a Smart HiDPI virtual's mode modesets the panel behind it.
        let pair = L.snapshot([L.display(10, .snapticVirtual), L.display(2, active: false, mirrorOf: 10)], main: 10)
        XCTAssertEqual(Invariants.violations(before: pair, changes: [.mode(10, L.mode(1280, 720))], context: ctx),
                       [.onlyDisplayUnsupported(2)])
        let two = L.snapshot([L.display(1), L.display(2)])
        XCTAssertTrue(Invariants.violations(before: two, changes: [.mode(1, L.mode(1280, 720))], context: ctx).isEmpty)
    }

    func testRequiredLongArm() {
        XCTAssertTrue(Invariants.requiredLongArm(L.snapshot([L.display(1)])).isEmpty)
        let s = L.snapshot([L.display(1, .builtin), L.display(2, active: false, disabledBySnaptic: true),
                            L.display(10, .snapticVirtual), L.display(3, active: false, mirrorOf: 10),
                            L.display(4, dim: 0), L.display(5, overlay: 0.2)])
        let r = Invariants.requiredLongArm(s)
        XCTAssertEqual(r.reasons, [.disabledDisplay, .mirrorsSnapticVirtual, .dimToBlack, .overlayBelowFloor])
        XCTAssertTrue(r.restoreColorSync)
        XCTAssertTrue(r.impairsVisibility && r.dimImpairing)
        XCTAssertEqual(r.undo.map(\.property), [.enabled, .mirrorOf], "re-enable before un-mirror")
        XCTAssertEqual(r.undo.first?.restore, .bool(true))
        let mirrorOnly = Invariants.requiredLongArm(L.snapshot([L.display(10, .snapticVirtual), L.display(3, active: false, mirrorOf: 10)]))
        XCTAssertFalse(mirrorOnly.impairsVisibility, "healthy Smart HiDPI pairs are not impairing (R5.2)")
    }

    func testPanicLeavesALoneHeadlessPrimary() {
        let headless = L.snapshot([L.display(10, .snapticVirtual, headless: true), L.display(11, .snapticVirtual)], main: 10)
        XCTAssertEqual(Invariants.panicRemovableVirtuals(headless), [11])
        let withPanel = L.snapshot([L.display(1, .builtin), L.display(10, .snapticVirtual, headless: true)])
        XCTAssertEqual(Invariants.panicRemovableVirtuals(withPanel), [10])
        let pair = L.snapshot([L.display(10, .snapticVirtual), L.display(2, active: false, mirrorOf: 10)], main: 10)
        XCTAssertEqual(Invariants.panicRemovableVirtuals(pair), [10], "the panel shows its own framebuffer again")
    }

    // MARK: Fuzz

    func testFuzzInvariantsHold() {
        var rng = SeededGenerator(seed: 0x1A7A)
        for _ in 0..<5000 {
            let s = L.random(&rng)
            let changes = (0..<Int(rng.next() % 4)).map { _ in L.randomChange(&rng, count: s.entries.count) }
            let v = Invariants.violations(before: s, changes: changes)
            let after = Invariants.predict(s, applying: changes)
            // Whatever passes keeps a visible display if one was visible before.
            if v.isEmpty && !Invariants.visible(s).isEmpty {
                XCTAssertFalse(Invariants.visible(after).isEmpty)
                XCTAssertFalse(Invariants.panelHosts(after).isEmpty)
            }
            // Strong ⊆ visible, hosts are online displays.
            XCTAssertTrue(Invariants.stronglyVisible(after).isSubset(of: Invariants.visible(after)))
            for h in Invariants.panelHosts(after) { XCTAssertNotNil(after.entry(h)) }
            // Panic never removes the last visible display.
            let removable = Invariants.panicRemovableVirtuals(s)
            XCTAssertTrue(removable.isSubset(of: Set(s.entries.filter { $0.transport == .snapticVirtual }.map(\.id))))
        }
    }
}
