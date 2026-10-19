import XCTest
@testable import SnapticKit

final class AwakeArbiterTests: XCTestCase {
    private let boot = "B"
    private func now(_ c: Double, wall: Double? = nil) -> ClockNow {
        ClockNow(wall: wall ?? 1_700_000_000 + c, continuous: c, bootSession: boot)
    }
    private func id(_ s: String) -> StableID { StableID.derived(namespace: "arb", name: s) }

    private func manual(_ kind: AwakeSessionKind = .indefinite, display: AwakeDisplayPolicy = .keepOn,
                        idleMinutes: Int = 30) -> AwakeSession {
        AwakeClock.start(kind, options: AwakeSessionOptions(display: display, displayIdleMinutes: idleMinutes),
                         presetID: nil, source: .menu, now: now(100), id: id("m"))
    }
    private func top(_ display: AwakeDisplayPolicy = .keepOn, index: Int = 0) -> TriggerTop {
        TriggerTop(id: id("t\(index)"), index: index, options: AwakeSessionOptions(display: display), since: 50)
    }
    private func hold(_ n: Int, deadline: Double) -> AwakeHold {
        AwakeHold(id: id("h\(n)"), binding: .process(pid: Int32(100 + n), startTime: 1), startedAt: 1, startedContinuous: 10,
                  deadline: deadline, bootSession: boot)
    }
    private func input(_ g: AwakeGoverning, locked: Bool = false, console: Bool = true, idle: Double? = nil,
                       keepWhileLocked: Bool = false, disk: Bool = false, guardsHold: Bool = false,
                       end: Double? = nil) -> AwakeArbiterInput {
        AwakeArbiterInput(governing: g, screenLocked: locked, consoleActive: console, realIdleSeconds: idle,
                          keepDisplayOnWhileLocked: keepWhileLocked, driveAliveWriting: disk, guardsHold: guardsHold,
                          sessionEnd: end)
    }

    // MARK: Governing (N3, N17)

    func testGoverningPrecedence() {
        let m = manual(), t = top(), h = [hold(1, deadline: 500)]
        XCTAssertEqual(AwakeArbiter.governing(manual: m, top: t, holds: h), .manual(m))
        XCTAssertEqual(AwakeArbiter.governing(manual: nil, top: t, holds: h), .trigger(t))
        XCTAssertEqual(AwakeArbiter.governing(manual: nil, top: nil, holds: h), .holds(h))
        XCTAssertEqual(AwakeArbiter.governing(manual: nil, top: nil, holds: []), .inactive)
        XCTAssertEqual(AwakeArbiter.governing(manual: m, top: nil, holds: []), .manual(m))
    }

    // MARK: Plan rules

    func testInactiveIsOffAndCarriesTheDiskFlag() {
        XCTAssertEqual(AwakeArbiter.plan(input(.inactive)), .inactive)
        let p = AwakeArbiter.plan(input(.inactive, disk: true))
        XCTAssertEqual(p.type, .off)
        XCTAssertTrue(p.preventDiskIdle)
    }

    func testEveryDisplayPolicyByLockConsoleAndIdle() {
        for policy in AwakeDisplayPolicy.allCases {
            for locked in [false, true] {
                for console in [false, true] {
                    for keepWhileLocked in [false, true] {
                        for idle in [nil, 0.0, 1_799, 1_800, 99_999] as [Double?] {
                            let plan = AwakeArbiter.plan(input(.manual(manual(display: policy)), locked: locked,
                                                               console: console, idle: idle,
                                                               keepWhileLocked: keepWhileLocked))
                            let displayAllowed = console && (!locked || keepWhileLocked)
                            let expected: AwakeAssertionType
                            switch policy {
                            case .maySleep: expected = .system
                            case .keepOn: expected = displayAllowed ? .display : .system
                            case .keepOnWhileActive:
                                expected = displayAllowed && (idle ?? 0) < 1_800 ? .display : .system
                            }
                            XCTAssertEqual(plan.type, expected, "\(policy) locked=\(locked) console=\(console) idle=\(String(describing: idle))")
                            XCTAssertEqual(plan.details, .manual)
                        }
                    }
                }
            }
        }
    }

    func testRuleSessionsAreAutomaticWithoutBackstop() {
        let p = AwakeArbiter.plan(input(.trigger(top()), end: 900))
        XCTAssertEqual(p.type, .display)
        XCTAssertEqual(p.details, .automatic)
        XCTAssertNil(p.deadline)
        XCTAssertEqual(AwakeArbiter.plan(input(.trigger(top(.maySleep)))).type, .system)
        XCTAssertEqual(AwakeArbiter.plan(input(.trigger(top()), locked: true)).type, .system)
        let held = AwakeArbiter.plan(input(.trigger(top()), guardsHold: true))
        XCTAssertEqual(held.type, .off, "a guard hold never gives a rule an assertion")
    }

    func testHoldsPlanSystemWithTheLatestDeadline() {
        let holds = [hold(1, deadline: 500), hold(2, deadline: 900), hold(3, deadline: 700)]
        let p = AwakeArbiter.plan(input(.holds(holds)))
        XCTAssertEqual(p.type, .system)
        XCTAssertEqual(p.details, .manual)
        XCTAssertEqual(p.deadline, 900 + AwakeArbiter.timeoutGraceSeconds)
        // An explicit sessionEnd (the caller's latest hold deadline) wins.
        XCTAssertEqual(AwakeArbiter.plan(input(.holds(holds), end: 950)).deadline, 950 + AwakeArbiter.timeoutGraceSeconds)
        XCTAssertEqual(AwakeArbiter.sessionEnd(.holds(holds), now: now(200)), 900)
        XCTAssertEqual(AwakeArbiter.plan(input(.holds([]))).type, .off)
    }

    func testDeadlineGraceForManualSessionsWithAnEnd() {
        let d = manual(.duration(seconds: 3_600))
        let end = AwakeArbiter.sessionEnd(.manual(d), now: now(200))
        XCTAssertEqual(end, 3_700)
        XCTAssertEqual(AwakeArbiter.plan(input(.manual(d), end: end)).deadline, 3_715)
        // Kinds without an end get no deadline even when one is passed.
        XCTAssertNil(AwakeArbiter.plan(input(.manual(manual(.indefinite)), end: 3_700)).deadline)
        XCTAssertNil(AwakeArbiter.plan(input(.manual(manual(.whileApp(bundleID: "a.b", maxSeconds: nil))), end: 1)).deadline)
        let capped = manual(.untilIdle(UntilIdleSpec(), maxSeconds: 600))
        XCTAssertEqual(AwakeArbiter.plan(input(.manual(capped), end: AwakeArbiter.sessionEnd(.manual(capped), now: now(200))))
            .deadline, 715)
        XCTAssertNil(AwakeArbiter.plan(input(.manual(d), end: .nan)).deadline)
        XCTAssertNil(AwakeArbiter.sessionEnd(.trigger(top()), now: now(1)))
        XCTAssertNil(AwakeArbiter.sessionEnd(.inactive, now: now(1)))
    }

    func testDiskIdleFlagFollowsDriveAlive() {
        for g in [AwakeGoverning.inactive, .manual(manual()), .trigger(top()), .holds([hold(1, deadline: 9)])] {
            XCTAssertTrue(AwakeArbiter.plan(input(g, disk: true)).preventDiskIdle)
            XCTAssertFalse(AwakeArbiter.plan(input(g, disk: false)).preventDiskIdle)
        }
    }

    func testFixedVocabulary() {
        XCTAssertEqual(AwakeAssertionPlan.name, "Snaptic: keeping your Mac awake")
        XCTAssertEqual(Set([AwakeAssertionDetails.manual.rawValue, AwakeAssertionDetails.automatic.rawValue]),
                       ["manual", "automatic"])
    }

    // MARK: needsSwap

    func testNeedsSwapThresholds() {
        let base = AwakeAssertionPlan(type: .display, details: .manual, deadline: 1_000, preventDiskIdle: false)
        var next = base
        XCTAssertFalse(AwakeArbiter.needsSwap(current: base, next: next))
        next.deadline = 1_005
        XCTAssertFalse(AwakeArbiter.needsSwap(current: base, next: next), "5 s is within the threshold")
        next.deadline = 1_005.5
        XCTAssertTrue(AwakeArbiter.needsSwap(current: base, next: next))
        next.deadline = 994
        XCTAssertTrue(AwakeArbiter.needsSwap(current: base, next: next))
        next.deadline = nil
        XCTAssertTrue(AwakeArbiter.needsSwap(current: base, next: next), "deadline disappeared")
        XCTAssertTrue(AwakeArbiter.needsSwap(current: next, next: base), "deadline appeared")
        next = base
        next.type = .system
        XCTAssertTrue(AwakeArbiter.needsSwap(current: base, next: next))
        next = base
        next.details = .automatic
        XCTAssertTrue(AwakeArbiter.needsSwap(current: base, next: next))
        next = base
        next.preventDiskIdle = true
        XCTAssertFalse(AwakeArbiter.needsSwap(current: base, next: next), "disk idle is a separate assertion")
        XCTAssertFalse(AwakeArbiter.needsSwap(current: .inactive,
                                              next: AwakeAssertionPlan(type: .off, details: .automatic, deadline: 5,
                                                                       preventDiskIdle: true)))
        XCTAssertTrue(AwakeArbiter.needsSwap(current: .inactive, next: base))
        XCTAssertTrue(AwakeArbiter.needsSwap(current: base, next: .inactive))
    }

    func testPlanIsStableWhileNothingChanges() {
        // An until session's continuous end is recomputed from the wall clock at every arbitration; it drifts by
        // microseconds, so the plans are never compared with ==, only through needsSwap.
        let s = manual(.until(unixTime: 1_700_000_000 + 9_000))
        var current = AwakeAssertionPlan.inactive
        var swaps = 0
        var t = 200.0
        for i in 0..<1_000 {
            let n = now(t, wall: 1_700_000_000 + t + Double(i % 7) * 1e-6)
            let next = AwakeArbiter.plan(input(.manual(s), end: AwakeArbiter.sessionEnd(.manual(s), now: n)))
            if AwakeArbiter.needsSwap(current: current, next: next) {
                swaps += 1
                current = next
            }
            t += 3.7
        }
        XCTAssertEqual(swaps, 1)
    }

    func testClockChangeRearmsOnlyPastTheThreshold() {
        let s = manual(.until(unixTime: 1_700_000_000 + 9_000))
        let a = AwakeArbiter.plan(input(.manual(s), end: AwakeArbiter.sessionEnd(.manual(s), now: now(200))))
        let small = AwakeArbiter.plan(input(.manual(s), end: AwakeArbiter.sessionEnd(.manual(s),
                                                                                   now: now(200, wall: 1_700_000_203))))
        let big = AwakeArbiter.plan(input(.manual(s), end: AwakeArbiter.sessionEnd(.manual(s),
                                                                                 now: now(200, wall: 1_700_003_800))))
        XCTAssertFalse(AwakeArbiter.needsSwap(current: a, next: small))
        XCTAssertTrue(AwakeArbiter.needsSwap(current: a, next: big))
    }

    func testArbiterFuzzInvariants() {
        var rng = SeededGenerator(seed: 0xA2B1)
        func bool() -> Bool { rng.next() % 2 == 0 }
        for _ in 0..<20_000 {
            let policy = AwakeDisplayPolicy.allCases[Int(rng.next() % 3)]
            let holds = (0..<Int(rng.next() % 3)).map { hold($0, deadline: Double(rng.next() % 10_000)) }
            let m: AwakeSession? = bool() ? manual(bool() ? .indefinite : .duration(seconds: 3_600), display: policy) : nil
            let t: TriggerTop? = bool() ? top(policy, index: Int(rng.next() % 4)) : nil
            let g = AwakeArbiter.governing(manual: m, top: t, holds: holds)
            let idle: Double? = bool() ? Double(rng.next() % 4_000) : nil
            let inp = input(g, locked: bool(), console: bool(), idle: idle, keepWhileLocked: bool(), disk: bool(),
                            guardsHold: bool(), end: AwakeArbiter.sessionEnd(g, now: now(200)))
            let p = AwakeArbiter.plan(inp)
            // Governing follows N3/N17 precedence.
            if let m = m { XCTAssertEqual(g, .manual(m)) } else if let t = t { XCTAssertEqual(g, .trigger(t)) }
            // Never a display assertion while locked (without the option) or off console.
            if !inp.consoleActive || (inp.screenLocked && !inp.keepDisplayOnWhileLocked) { XCTAssertNotEqual(p.type, .display) }
            // Off exactly when nothing governs (or a guard holds a rule session).
            switch g {
            case .inactive: XCTAssertEqual(p.type, .off)
            case .trigger: XCTAssertEqual(p.type == .off, inp.guardsHold)
            case .manual, .holds: XCTAssertNotEqual(p.type, .off)
            }
            // Holds and maySleep never hold the display; rules are automatic and never have a deadline.
            if case .holds = g { XCTAssertEqual(p.type, .system) }
            if case .trigger = g { XCTAssertEqual(p.details, .automatic); XCTAssertNil(p.deadline) } else {
                XCTAssertEqual(p.details, .manual)
            }
            if let d = p.deadline { XCTAssertTrue(d.isFinite) }
            XCTAssertEqual(p.preventDiskIdle, inp.driveAliveWriting)
            XCTAssertFalse(AwakeArbiter.needsSwap(current: p, next: AwakeArbiter.plan(inp)), "deterministic")
        }
    }
}

// MARK: - 0.3.1 B3.3: the lid-shut rule (owner: T-lid-kit)

extension AwakeArbiterTests {
    /// While `lidShut`, every display policy counts as `maySleep`: a system assertion, never a display one; the
    /// deadline and details don't change. `lidShut` defaults to false, so 0.3 inputs plan as before.
    func testLidShutLetsTheDisplaySleep() {
        let governing: [AwakeGoverning] = AwakeDisplayPolicy.allCases.flatMap { policy in
            [.manual(manual(.duration(seconds: 3_600), display: policy)), .trigger(top(policy))]
        } + [.holds([hold(1, deadline: 500)]), .inactive]
        for g in governing {
            for idle in [nil, 0.0, 99_999] as [Double?] {
                var shut = input(g, idle: idle, end: 900)
                let open = AwakeArbiter.plan(shut)
                XCTAssertFalse(shut.lidShut, "defaults to false")
                shut.lidShut = true
                let p = AwakeArbiter.plan(shut)
                XCTAssertNotEqual(p.type, .display, "\(g)")
                XCTAssertEqual(p.type, open.type == .off ? .off : .system, "\(g)")
                XCTAssertEqual(p.details, open.details)
                XCTAssertEqual(p.deadline, open.deadline)
                XCTAssertEqual(p.preventDiskIdle, open.preventDiskIdle)
            }
        }
        // The external display case: lidShut stays false and Keep Display On stands.
        XCTAssertEqual(AwakeArbiter.plan(input(.manual(manual(display: .keepOn)))).type, .display)
    }
}
