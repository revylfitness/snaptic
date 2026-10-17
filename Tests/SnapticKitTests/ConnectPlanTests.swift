import XCTest
@testable import SnapticKit

final class ConnectPlanTests: XCTestCase {
    private func key(_ c: Character) -> DisplayKey { DisplayKey(rawValue: String(repeating: c, count: 32))! }
    private func sid(_ n: Int) -> StableID {
        let d = String(n)
        return StableID(rawValue: "00000000-0000-0000-0000-" + String(repeating: "0", count: 12 - d.count) + d)!
    }
    private func mode(_ w: Int, id: Int32 = 1) -> ModeRef {
        ModeRef(ioModeID: id, pixelWidth: w, pixelHeight: w / 2, pointWidth: w, pointHeight: w / 2, refreshMilliHz: 60_000)
    }
    private let all = Set(DisplayFeature.allCases)

    private func builtin(strong: Bool = true, main: Bool = true, disabled: Bool = false, dimmed: Bool = false,
                         mode m: Int = 1512) -> PlanDisplay {
        PlanDisplay(key: key("a"), transport: .builtin, isBuiltin: true, isActive: !disabled, isMain: main, strong: strong,
                    mode: mode(m), availableModes: [mode(1512), mode(1280)], disabledBySnaptic: disabled, dimmedBelowFloor: dimmed)
    }
    private func external(_ c: Character = "b", strong: Bool = true, main: Bool = false, mode m: Int = 2560) -> PlanDisplay {
        PlanDisplay(key: key(c), transport: .wired, isBuiltin: false, isMain: main, strong: strong, mode: mode(m),
                    availableModes: [mode(2560), mode(1920)], x: 1512)
    }

    // MARK: Step 1

    func testReenableAndFloorsWhenNothingStrong() {
        let inputs = ConnectInputs(trigger: .reconfigure, effective: all,
                                   displays: [builtin(strong: false, main: false, disabled: true),
                                              external("b", strong: false, main: true).with { $0.dimmedBelowFloor = true }])
        let steps = ConnectPlan.plan(inputs: inputs)
        XCTAssertTrue(steps.contains(.reenable(key("a"))))
        XCTAssertTrue(steps.contains(.raiseFloor(key("b"))))
        XCTAssertTrue(steps.allSatisfy(\.isVisibilityRestore))
    }

    func testNoReenableWhileSomethingStrong() {
        let inputs = ConnectInputs(trigger: .reconfigure, effective: all,
                                   displays: [builtin(strong: false, main: false, disabled: true), external(main: true)])
        XCTAssertFalse(ConnectPlan.plan(inputs: inputs).contains(.reenable(key("a"))))
    }

    func testOrphanGrace() {
        func steps(missing: Double, sinceWake: Double?, visible: Bool = true, isMain: Bool = false) -> [PlanStep] {
            let host = PlanHost(specID: sid(1), purpose: .smartHiDPI(physical: key("b")), isMain: isMain, physicalMissingSeconds: missing)
            let displays = visible ? [builtin(main: !isMain)] : [builtin(strong: false, main: !isMain)]
            return ConnectPlan.visibilitySteps(ConnectInputs(trigger: .reconfigure, secondsSinceWakeOrUnlock: sinceWake,
                                                             displays: displays, hosts: [host]))
        }
        XCTAssertFalse(steps(missing: 3.9, sinceWake: nil).contains(.destroyHost(sid(1), reason: .orphaned)))
        XCTAssertTrue(steps(missing: 4, sinceWake: nil).contains(.destroyHost(sid(1), reason: .orphaned)))
        XCTAssertFalse(steps(missing: 10, sinceWake: 60).contains(.destroyHost(sid(1), reason: .orphaned)), "30 s after wake")
        XCTAssertTrue(steps(missing: 30, sinceWake: 60).contains(.destroyHost(sid(1), reason: .orphaned)))
        XCTAssertTrue(steps(missing: 10, sinceWake: 200).contains(.destroyHost(sid(1), reason: .orphaned)), "wake window over")
        XCTAssertTrue(steps(missing: 4, sinceWake: 5, visible: false).contains(.destroyHost(sid(1), reason: .orphaned)),
                      "nothing visible: 4 s even after wake")
        XCTAssertEqual(steps(missing: 1, sinceWake: nil, isMain: true), [.moveMain(to: key("a"))], "main moves during grace")
        XCTAssertEqual(ConnectPlan.grace(secondsSinceWakeOrUnlock: 120, anyVisible: true), 30)
        XCTAssertEqual(ConnectPlan.grace(secondsSinceWakeOrUnlock: 121, anyVisible: true), 4)
    }

    func testMainMustBeStrong() {
        let v = PlanDisplay(key: key("7"), transport: .snapticVirtual, isBuiltin: false, isMain: true, strong: false)
        let steps = ConnectPlan.plan(inputs: ConnectInputs(trigger: .reconfigure, displays: [builtin(main: false), v]))
        XCTAssertEqual(steps, [.moveMain(to: key("a"))])
        // Headless only (weak): main may stay.
        let h = PlanDisplay(key: key("6"), transport: .snapticVirtual, isBuiltin: false, isMain: true, strong: false, weak: true)
        XCTAssertTrue(ConnectPlan.plan(inputs: ConnectInputs(trigger: .reconfigure, displays: [h])).isEmpty)
    }

    // MARK: Safe Mode / panic

    private func busyInputs(phase: ConnectPhase) -> ConnectInputs {
        let pair = PlanPair(physical: key("b"), specID: sid(2), physicalPresent: true, tier1Verified: true)
        let screen = PlanVirtualScreen(specID: sid(3), wantsConnected: true)
        let layout = SavedLayout(id: sid(4), name: "Office",
                                 displays: [key("a"): SavedDisplaySettings(x: 0, y: 0, identity: LayoutDisplayIdentity(tier1: "A", tier2: nil))],
                                 autoApply: .whenIncludes)
        return ConnectInputs(trigger: .launch, phase: phase, effective: all,
                             displays: [builtin(strong: false, main: false, disabled: true), external(main: true)],
                             pairs: [pair], virtualScreens: [screen], layouts: [layout],
                             liveIdentities: [LiveLayoutDisplay(key: key("a"), identity: LayoutDisplayIdentity(tier1: "A", tier2: nil))],
                             persisted: [PlanPersistedChoice(key: key("b"), mode: mode(1920), preKeepMode: mode(2560))])
    }

    func testSafeModeAndPanicRunStepOneOnly() {
        for phase in [ConnectPhase.virtuals, .rest] {
            var i = busyInputs(phase: phase)
            XCTAssertFalse(ConnectPlan.plan(inputs: i).filter { !$0.isVisibilityRestore }.isEmpty)
            i.safeMode = true
            XCTAssertTrue(ConnectPlan.plan(inputs: i).allSatisfy(\.isVisibilityRestore))
            i.safeMode = false
            i.panicLatch = true
            XCTAssertTrue(ConnectPlan.plan(inputs: i).allSatisfy(\.isVisibilityRestore))
        }
        // Step 1 still runs in Safe Mode.
        var i = busyInputs(phase: .virtuals)
        i.safeMode = true
        i.displays = [builtin(strong: false, main: false, disabled: true)]
        XCTAssertEqual(ConnectPlan.plan(inputs: i), [.reenable(key("a"))])
    }

    // MARK: Step 2

    func testPhaseOneCreatesAndRebinds() {
        var i = busyInputs(phase: .virtuals)
        let steps = ConnectPlan.plan(inputs: i)
        XCTAssertTrue(steps.contains(.createVirtual(sid(2), purpose: .smartHiDPI(physical: key("b")))))
        XCTAssertTrue(steps.contains(.createVirtual(sid(3), purpose: .virtualScreen)))
        XCTAssertFalse(steps.contains { $0.stage >= 3 }, "phase 1 stops after step 2")
        // After creation, phase 2 rebinds the live pair.
        i.phase = .rest
        i.hosts = [PlanHost(specID: sid(2), purpose: .smartHiDPI(physical: key("b"))), PlanHost(specID: sid(3), purpose: .virtualScreen)]
        let rest = ConnectPlan.plan(inputs: i)
        XCTAssertTrue(rest.contains(.rebind(specID: sid(2), physical: key("b"))))
        XCTAssertFalse(rest.contains { if case .createVirtual = $0 { return true }; return false })
        // Bound: nothing more for the pair.
        i.hosts[0].boundTo = key("b")
        XCTAssertFalse(ConnectPlan.plan(inputs: i).contains { $0.stage == 2 })
    }

    func testPairNeedsTier1AndRecreatesOnMismatch() {
        var i = busyInputs(phase: .virtuals)
        i.pairs[0].tier1Verified = false
        i.hosts = [PlanHost(specID: sid(2), purpose: .smartHiDPI(physical: key("b")))]
        XCTAssertTrue(ConnectPlan.plan(inputs: i).contains(.promptMirror(specID: sid(2), target: key("b"))))
        i.hosts[0].identityMatches = false
        let steps = ConnectPlan.plan(inputs: i)
        let d = steps.firstIndex(of: .destroyHost(sid(2), reason: .mismatch))
        let c = steps.firstIndex(of: .createVirtual(sid(2), purpose: .smartHiDPI(physical: key("b"))))
        XCTAssertNotNil(d)
        XCTAssertNotNil(c)
        XCTAssertLessThan(d!, c!)
        // Feature off: nothing.
        i.effective.remove(.smartHiDPI)
        XCTAssertFalse(ConnectPlan.plan(inputs: i).contains { if case .createVirtual(_, .smartHiDPI) = $0 { return true }; return false })
    }

    func testAssociations() {
        let present: Set<DisplayKey> = [key("a")]
        let s1 = PlanVirtualScreen(specID: sid(1), associations: [VirtualAssociation(target: key("a"))], wantsConnected: false)
        XCTAssertTrue(s1.desiredConnected(present: present))
        XCTAssertFalse(s1.desiredConnected(present: []))
        let s2 = PlanVirtualScreen(specID: sid(2), associations: [VirtualAssociation(target: key("9"), autoConnect: .whileAbsent)],
                                   wantsConnected: false)
        XCTAssertTrue(s2.desiredConnected(present: present))
        XCTAssertFalse(s2.desiredConnected(present: [key("9")]))
        let manual = PlanVirtualScreen(specID: sid(3), associations: [VirtualAssociation(target: key("a"), autoConnect: .never)],
                                       wantsConnected: true)
        XCTAssertTrue(manual.desiredConnected(present: []))
        XCTAssertFalse(manual.isAssociationManaged)

        // Association ended: torn down. Mirror/stream presentations only prompt.
        let mirror = PlanVirtualScreen(specID: sid(4), associations: [VirtualAssociation(target: key("b"), presentation: .mirror)],
                                       wantsConnected: false)
        let stream = PlanVirtualScreen(specID: sid(5), associations: [VirtualAssociation(target: key("b"), presentation: .flippedStream)],
                                       wantsConnected: false)
        let gone = PlanVirtualScreen(specID: sid(6), associations: [VirtualAssociation(target: key("8"))], wantsConnected: true)
        let i = ConnectInputs(trigger: .reconfigure, effective: all, displays: [builtin(), external()],
                              hosts: [PlanHost(specID: sid(4), purpose: .virtualScreen), PlanHost(specID: sid(5), purpose: .virtualScreen),
                                      PlanHost(specID: sid(6), purpose: .virtualScreen)],
                              virtualScreens: [mirror, stream, gone])
        let steps = ConnectPlan.plan(inputs: i)
        XCTAssertTrue(steps.contains(.promptMirror(specID: sid(4), target: key("b"))))
        XCTAssertTrue(steps.contains(.promptStream(specID: sid(5), target: key("b"), flipped: true)))
        XCTAssertTrue(steps.contains(.destroyHost(sid(6), reason: .associationEnded)))
        XCTAssertTrue(steps.filter { if case .promptMirror = $0 { return true }; return false }.allSatisfy(\.isPrompt))
    }

    // MARK: Step 3

    private func layoutInputs(trusted: Bool, trigger: ConnectTrigger = .launch, setChanged: Bool = true) -> ConnectInputs {
        let ident = LayoutDisplayIdentity(tier1: "A", tier2: nil)
        let layout = SavedLayout(id: sid(7), name: "Office",
                                 displays: [key("a"): SavedDisplaySettings(x: 0, y: 0, isMain: true, identity: ident),
                                            key("b"): SavedDisplaySettings(x: 1512, y: 0, identity: LayoutDisplayIdentity(tier1: "B", tier2: nil))],
                                 autoApply: .whenExactly)
        let desired = ProtectionProfile(displays: [
            key("a"): ProtectedDisplayState(mode: mode(1280), x: 0, y: 0, rotation: 0, mirrorOf: nil, isMain: true),
            key("b"): ProtectedDisplayState(mode: mode(1920), x: 1512, y: 0, rotation: 0, mirrorOf: nil, isMain: false),
        ])
        return ConnectInputs(trigger: trigger, phase: .rest, effective: all, displaySetChanged: setChanged,
                             displays: [builtin(), external()], layouts: [layout], trustedLayouts: trusted ? [sid(7)] : [],
                             liveIdentities: [LiveLayoutDisplay(key: key("a"), identity: ident),
                                              LiveLayoutDisplay(key: key("b"), identity: LayoutDisplayIdentity(tier1: "B", tier2: nil))],
                             protection: desired)
    }

    func testTrustedLayoutSkipsProtection() {
        let steps = ConnectPlan.plan(inputs: layoutInputs(trusted: true))
        XCTAssertTrue(steps.contains(.applyLayout(sid(7))))
        XCTAssertFalse(steps.contains { if case .protect = $0 { return true }; return false })
    }

    func testUntrustedLayoutPromptsAndProtects() {
        let steps = ConnectPlan.plan(inputs: layoutInputs(trusted: false))
        XCTAssertTrue(steps.contains(.promptLayout(sid(7))))
        XCTAssertTrue(steps.contains(.protect([.mode(key("a"), mode(1280)), .mode(key("b"), mode(1920))])))
    }

    func testLayoutOnlyOnSetChangeForReconfigure() {
        let steps = ConnectPlan.plan(inputs: layoutInputs(trusted: true, trigger: .reconfigure, setChanged: false))
        XCTAssertFalse(steps.contains(.applyLayout(sid(7))))
        XCTAssertTrue(steps.contains { if case .protect = $0 { return true }; return false })
    }

    func testOnlyStrongModesetNeedsPresence() {
        var i = layoutInputs(trusted: false)
        i.displays = [builtin(), external(strong: false)]
        let steps = ConnectPlan.plan(inputs: i)
        XCTAssertTrue(steps.contains(.promptRestore([.mode(key("a"), mode(1280))])))
        XCTAssertTrue(steps.contains(.protect([.mode(key("b"), mode(1920))])))
        // Protection stopped by fight detection, or feature off: nothing.
        i.protectionStopped = true
        XCTAssertFalse(ConnectPlan.plan(inputs: i).contains { $0.stage == 3 && !$0.isPrompt })
    }

    func testTrustedLayoutModesettingOnlyStrongBecomesPrompt() {
        var i = layoutInputs(trusted: true)
        i.layouts[0].displays[key("a")]?.mode = mode(1280)
        i.displays = [builtin(), external(strong: false)]
        let steps = ConnectPlan.plan(inputs: i)
        XCTAssertTrue(steps.contains(.promptLayout(sid(7))))
        XCTAssertFalse(steps.contains(.applyLayout(sid(7))))
    }

    // MARK: Step 4

    func testPersistedChoice() {
        var i = ConnectInputs(trigger: .launch, phase: .rest, effective: all, displays: [builtin(), external(mode: 2560)],
                              persisted: [PlanPersistedChoice(key: key("b"), mode: mode(1920), preKeepMode: mode(2560))])
        XCTAssertEqual(ConnectPlan.plan(inputs: i), [.restoreMode(key("b"), mode(1920))])
        // Current mode isn't the pre-Keep mode: the user (or macOS) chose something else.
        i.displays[1].mode = mode(1920, id: 5)
        XCTAssertTrue(ConnectPlan.plan(inputs: i).isEmpty)
        // Only strongly visible display: prompt (trial at presence).
        i.displays = [external(mode: 2560)]
        i.displays[0].isMain = true
        XCTAssertEqual(ConnectPlan.plan(inputs: i), [.promptRestoreMode(key("b"), mode(1920))])
        // Feature off.
        i.effective.remove(.resolution)
        XCTAssertTrue(ConnectPlan.plan(inputs: i).isEmpty)
    }

    func testPersistedChoiceSkipsTouchedDisplays() {
        var i = layoutInputs(trusted: false)
        i.persisted = [PlanPersistedChoice(key: key("b"), mode: mode(1920), preKeepMode: mode(2560))]
        let steps = ConnectPlan.plan(inputs: i)
        XCTAssertFalse(steps.contains(.restoreMode(key("b"), mode(1920))))
    }

    // MARK: Step 5

    func testAutoDisconnectLast() {
        let ad = PlanAutoDisconnect(builtin: key("a"), modelIdentifier: "Mac14,7", isAppleSilicon: true, lidOpen: true,
                                    externalPower: .on, externalIsAppleNative: false)
        var i = ConnectInputs(trigger: .reconfigure, phase: .rest, effective: all, displays: [builtin(main: false), external(main: true)],
                              persisted: [PlanPersistedChoice(key: key("b"), mode: mode(1920), preKeepMode: mode(2560))],
                              autoDisconnect: ad)
        let steps = ConnectPlan.plan(inputs: i)
        XCTAssertEqual(steps.last, .disconnectBuiltin(key("a")))
        XCTAssertEqual(steps.map(\.stage), steps.map(\.stage).sorted())
        i.autoDisconnect?.externalPower = .off
        XCTAssertFalse(ConnectPlan.plan(inputs: i).contains(.disconnectBuiltin(key("a"))))
        i.autoDisconnect?.externalPower = .on
        i.displays = [builtin()]
        XCTAssertFalse(ConnectPlan.plan(inputs: i).contains(.disconnectBuiltin(key("a"))), "needs a strong external")
        i.displays = [builtin(main: false), external(main: true)]
        i.autoDisconnect?.modelIdentifier = "Mac15,3"
        XCTAssertFalse(ConnectPlan.plan(inputs: i).contains(.disconnectBuiltin(key("a"))), "hazard table")
        i.autoDisconnect?.modelIdentifier = "Mac14,7"
        i.effective.remove(.autoDisconnectBuiltin)
        XCTAssertFalse(ConnectPlan.plan(inputs: i).contains(.disconnectBuiltin(key("a"))))
    }

    // MARK: Properties

    func testStagesAreOrdered() {
        var rng = SeededGenerator(seed: 0xC0)
        for _ in 0..<500 {
            var i = busyInputs(phase: rng.next() % 2 == 0 ? .virtuals : .rest)
            i.trigger = ConnectTrigger.allCases[Int(rng.next() % 4)]
            i.displaySetChanged = rng.next() % 2 == 0
            if rng.next() % 2 == 0 { i.hosts = [PlanHost(specID: sid(2), purpose: .smartHiDPI(physical: key("b")),
                                                         physicalMissingSeconds: Double(rng.next() % 40))] }
            i.effective = Set(DisplayFeature.allCases.filter { _ in rng.next() % 3 != 0 })
            let steps = ConnectPlan.plan(inputs: i)
            let stages = steps.map(\.stage)
            // Step-1 entries lead; the rest follow in stage order.
            let firstNonVisibility = stages.firstIndex { $0 != 1 } ?? stages.count
            XCTAssertTrue(stages[firstNonVisibility...].allSatisfy { $0 >= 2 })
            XCTAssertEqual(Array(stages[firstNonVisibility...]), stages[firstNonVisibility...].sorted())
            // Filtering by effective features.
            if !i.effective.contains(.layouts) { XCTAssertFalse(steps.contains { if case .applyLayout = $0 { return true }; return false }) }
            if !i.effective.contains(.virtualScreens) {
                XCTAssertFalse(steps.contains { if case .createVirtual(_, .virtualScreen) = $0 { return true }; return false })
            }
        }
    }

    func testPostApplyIsNoOp() {
        // Apply every unattended step of a plan to the inputs; planning again is empty.
        var i = layoutInputs(trusted: false)
        i.layouts = []
        i.displays = [builtin(main: false), external(main: true).with { $0.x = 99 }]
        i.persisted = []
        i.pairs = [PlanPair(physical: key("b"), specID: sid(2), physicalPresent: true, tier1Verified: true)]
        i.hosts = [PlanHost(specID: sid(2), purpose: .smartHiDPI(physical: key("b")))]
        let steps = ConnectPlan.plan(inputs: i)
        XCTAssertFalse(steps.isEmpty)
        for s in steps {
            switch s {
            case .rebind(let id, let k): if let h = i.hosts.firstIndex(where: { $0.specID == id }) { i.hosts[h].boundTo = k }
            case .protect(let deltas):
                for d in deltas {
                    guard let idx = i.displays.firstIndex(where: { $0.key == d.key }) else { continue }
                    switch d {
                    case .mode(_, let m): i.displays[idx].mode = m
                    case .origin(_, let x, let y): i.displays[idx].x = x; i.displays[idx].y = y
                    case .rotation(_, let r): i.displays[idx].rotation = r
                    case .mirror(_, let src): i.displays[idx].mirrorOf = src
                    case .main: for j in i.displays.indices { i.displays[j].isMain = j == idx }
                    }
                }
            default: XCTFail("unexpected \(s)")
            }
        }
        i.displaySetChanged = false
        XCTAssertEqual(ConnectPlan.plan(inputs: i), [])
    }

    // MARK: Runner helpers

    func testRateLimiter() {
        var r = PlanRateLimiter()
        let k: Set<DisplayKey> = [key("a")]
        XCTAssertTrue(r.allow(keys: k, now: 0))
        XCTAssertFalse(r.allow(keys: k, now: 1), "1 per 2 s")
        XCTAssertTrue(r.allow(keys: k, now: 2))
        XCTAssertTrue(r.allow(keys: k, now: 4))
        XCTAssertFalse(r.allow(keys: k, now: 6), "3 per display per 60 s")
        XCTAssertTrue(r.allow(keys: [key("b")], now: 6))
        XCTAssertTrue(r.allow(keys: k, now: 61))
    }

    func testLearning() {
        XCTAssertTrue(PersistedChoiceLearning.shouldLearn(changedAt: 100, now: 110, lastConnectOrWake: nil, causedBySnaptic: false))
        XCTAssertFalse(PersistedChoiceLearning.shouldLearn(changedAt: 100, now: 109, lastConnectOrWake: nil, causedBySnaptic: false))
        XCTAssertFalse(PersistedChoiceLearning.shouldLearn(changedAt: 100, now: 200, lastConnectOrWake: nil, causedBySnaptic: true))
        XCTAssertFalse(PersistedChoiceLearning.shouldLearn(changedAt: 100, now: 200, lastConnectOrWake: 90, causedBySnaptic: false))
        XCTAssertTrue(PersistedChoiceLearning.shouldLearn(changedAt: 100, now: 200, lastConnectOrWake: 80, causedBySnaptic: false))
    }

    func testQuietWindow() {
        var q = QuietWindow()
        XCTAssertNil(q.dueIn(now: 0))
        q.note(0)
        XCTAssertEqual(q.dueIn(now: 0), 3)
        q.note(2)
        XCTAssertEqual(q.dueIn(now: 2), 3)
        q.note(9)
        XCTAssertEqual(q.dueIn(now: 9), 1, "capped at 10 s after the first event")
        XCTAssertEqual(q.dueIn(now: 20), 0)
        q.reset()
        XCTAssertNil(q.dueIn(now: 20))
    }

    func testStepKeysAndCodable() throws {
        let steps: [PlanStep] = [.reenable(key("a")), .protect([.main(key("b"))]), .createVirtual(sid(1), purpose: .smartHiDPI(physical: key("c"))),
                                 .applyLayout(sid(2)), .promptStream(specID: sid(3), target: key("d"), flipped: false)]
        XCTAssertEqual(steps.map(\.keys), [[key("a")], [key("b")], [key("c")], [], [key("d")]])
        let data = try JSONEncoder().encode(steps)
        XCTAssertEqual(try JSONDecoder().decode([PlanStep].self, from: data), steps)
    }
}

private extension PlanDisplay {
    func with(_ change: (inout PlanDisplay) -> Void) -> PlanDisplay {
        var c = self
        change(&c)
        return c
    }
}
