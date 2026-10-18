import XCTest
@testable import SnapticKit

final class AwakeTriggerEngineTests: XCTestCase {
    private let digest = String(repeating: "cd", count: 16)
    private func id(_ s: String) -> StableID { StableID.derived(namespace: "engine", name: s) }
    private func power(ac: Bool = true, battery: Bool = true, percent: Int? = 80, charging: Bool = false) -> PowerFacts {
        PowerFacts(batteryPresent: battery, onAC: ac, percent: percent, charging: charging, falling: false,
                   lastRecovery: nil, lowPowerMode: false, thermal: .nominal)
    }
    private func holds(_ c: AwakeCriterion, _ f: CriterionFacts, negated: Bool = false) -> Bool? {
        TriggerEngine.holds(AwakeCriterionEntry(c, negated: negated), facts: f)
    }
    private func rule(_ name: String, _ criteria: [AwakeCriterion], match: TriggerMatch = .all, start: Int = 0,
                      end: Int = 0) -> AwakeTrigger {
        var t = AwakeTrigger(id: id(name), name: name, criteria: criteria.map { AwakeCriterionEntry($0) })
        t.match = match
        t.startDelaySeconds = start
        t.endDelaySeconds = end
        return t
    }

    // MARK: Every criterion kind: true / false / unknown

    func testUnknownForEveryKindWhenItsSourceHasNoValue() {
        let empty = CriterionFacts()
        let all: [AwakeCriterion] = [
            .app(bundleID: "a.b", name: "", frontmost: false), .app(bundleID: "a.b", name: "", frontmost: true),
            .display(.anyExternal), .display(.specific(record: FingerprintRecord(t2: digest), name: "")), .display(.mirroring),
            .power(.onAdapter), .schedule(days: .everyDay, startMinute: 0, endMinute: 60), .cpuAbove(percent: 50),
            .audio(.outputActive), .audio(.microphoneActive), .idle(atLeastMinutes: 5), .volumeMounted(uuid: "U", name: ""),
            .usbDevice(vendor: 1, product: 2, serialHash: nil, name: ""), .network(.vpnConnected),
            .networkActivity(atLeastKBps: 10), .bluetooth(.anyAudio),
        ]
        for c in all {
            XCTAssertNil(holds(c, empty), "\(c)")
            XCTAssertNil(holds(c, empty, negated: true), "negated unknown stays unknown: \(c)")
        }
    }

    func testApp() {
        var f = CriterionFacts()
        f.runningApps = ["com.apple.dt.Xcode"]
        f.frontmostApp = .some("com.apple.Safari")
        XCTAssertEqual(holds(.app(bundleID: "com.apple.dt.Xcode", name: "", frontmost: false), f), true)
        XCTAssertEqual(holds(.app(bundleID: "com.apple.Music", name: "", frontmost: false), f), false)
        XCTAssertEqual(holds(.app(bundleID: "com.apple.Safari", name: "", frontmost: true), f), true)
        XCTAssertEqual(holds(.app(bundleID: "com.apple.dt.Xcode", name: "", frontmost: true), f), false)
        XCTAssertEqual(holds(.app(bundleID: "com.apple.dt.Xcode", name: "", frontmost: false), f, negated: true), false)
        f.frontmostApp = .some(nil)
        XCTAssertEqual(holds(.app(bundleID: "com.apple.Safari", name: "", frontmost: true), f), false, "no frontmost app")
    }

    func testDisplay() {
        var f = CriterionFacts()
        let builtin = DisplayFact(record: FingerprintRecord(t5: digest), isBuiltin: true)
        let external = DisplayFact(record: FingerprintRecord(t2: digest, t3: digest), isBuiltin: false)
        f.displays = [builtin]
        XCTAssertEqual(holds(.display(.anyExternal), f), false)
        f.displays = [builtin, external]
        XCTAssertEqual(holds(.display(.anyExternal), f), true)
        // Specific matching goes through B's Fingerprint.matches, whatever it decides.
        let stored = FingerprintRecord(t2: digest)
        XCTAssertEqual(holds(.display(.specific(record: stored, name: "")), f),
                       Fingerprint.matches(stored, builtin.record) || Fingerprint.matches(stored, external.record))
        f.displays = []
        XCTAssertEqual(holds(.display(.specific(record: stored, name: "")), f), false)
        f.mirroring = true
        XCTAssertEqual(holds(.display(.mirroring), f), true)
    }

    func testPower() {
        var f = CriterionFacts()
        f.power = power(ac: true, charging: true)
        XCTAssertEqual(holds(.power(.onAdapter), f), true)
        XCTAssertEqual(holds(.power(.onBattery), f), false)
        XCTAssertEqual(holds(.power(.charging), f), true)
        XCTAssertEqual(holds(.power(.batteryAtLeast(80)), f), true)
        XCTAssertEqual(holds(.power(.batteryAtLeast(81)), f), false)
        f.power = power(ac: false, percent: nil)
        XCTAssertEqual(holds(.power(.onBattery), f), true)
        XCTAssertNil(holds(.power(.batteryAtLeast(10)), f), "unreadable percent is unknown")
        f.power = power(ac: true, battery: false, percent: nil)
        XCTAssertEqual(holds(.power(.onBattery), f), false, "a desktop is never on battery")
        XCTAssertEqual(holds(.power(.batteryAtLeast(10)), f), false)
        XCTAssertEqual(holds(.power(.charging), f), false)
    }

    func testScheduleIncludingOvernightAndWeekWrap() {
        var f = CriterionFacts()
        let weekday9to5 = AwakeCriterion.schedule(days: .weekdays, startMinute: 540, endMinute: 1_020)
        func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Bool? {
            f.minuteOfWeek = day * 1_440 + h * 60 + m
            return holds(weekday9to5, f)
        }
        XCTAssertEqual(at(1, 9), true)
        XCTAssertEqual(at(1, 8, 59), false)
        XCTAssertEqual(at(1, 16, 59), true)
        XCTAssertEqual(at(1, 17), false, "end is exclusive")
        XCTAssertEqual(at(0, 12), false, "Sunday")
        // Overnight Friday 22:00 → 06:00: true late Friday and early Saturday only.
        let night = AwakeCriterion.schedule(days: .day(5), startMinute: 1_320, endMinute: 360)
        f.minuteOfWeek = 5 * 1_440 + 23 * 60
        XCTAssertEqual(holds(night, f), true)
        f.minuteOfWeek = 6 * 1_440 + 5 * 60
        XCTAssertEqual(holds(night, f), true)
        f.minuteOfWeek = 6 * 1_440 + 6 * 60
        XCTAssertEqual(holds(night, f), false)
        f.minuteOfWeek = 5 * 1_440 + 5 * 60
        XCTAssertEqual(holds(night, f), false, "early Friday belongs to Thursday's night")
        // Saturday night into Sunday wraps the week.
        let saturday = AwakeCriterion.schedule(days: .day(6), startMinute: 1_380, endMinute: 120)
        f.minuteOfWeek = 60
        XCTAssertEqual(holds(saturday, f), true)
        f.minuteOfWeek = 6 * 1_440 + 1_390
        XCTAssertEqual(holds(saturday, f), true)
        // start == end: 24 hours from start.
        let allDay = AwakeCriterion.schedule(days: .day(2), startMinute: 600, endMinute: 600)
        f.minuteOfWeek = 3 * 1_440 + 599
        XCTAssertEqual(holds(allDay, f), true)
        f.minuteOfWeek = 3 * 1_440 + 600
        XCTAssertEqual(holds(allDay, f), false)
        f.minuteOfWeek = 10_080
        XCTAssertNil(holds(allDay, f), "out of range is unknown")
    }

    func testThresholdKinds() {
        var f = CriterionFacts()
        f.cpuPercent = 50
        XCTAssertEqual(holds(.cpuAbove(percent: 50), f), false, "above, not at")
        f.cpuPercent = 50.5
        XCTAssertEqual(holds(.cpuAbove(percent: 50), f), true)
        f.cpuPercent = .nan
        XCTAssertEqual(holds(.cpuAbove(percent: 50), f), false)
        f.realIdleSeconds = 600
        XCTAssertEqual(holds(.idle(atLeastMinutes: 10), f), true)
        XCTAssertEqual(holds(.idle(atLeastMinutes: 11), f), false)
        f.throughputKBps = 99.9
        XCTAssertEqual(holds(.networkActivity(atLeastKBps: 100), f), false)
        f.throughputKBps = 100
        XCTAssertEqual(holds(.networkActivity(atLeastKBps: 100), f), true)
        f.audioOutput = true
        f.microphone = false
        XCTAssertEqual(holds(.audio(.outputActive), f), true)
        XCTAssertEqual(holds(.audio(.microphoneActive), f), false)
        XCTAssertEqual(holds(.audio(.microphoneActive), f, negated: true), true)
    }

    func testVolumesUSBNetworkBluetooth() {
        var f = CriterionFacts()
        f.volumes = ["1b4e28ba-2fa1-11d2-883f-0016d3cca427"]
        XCTAssertEqual(holds(.volumeMounted(uuid: "1B4E28BA-2FA1-11D2-883F-0016D3CCA427", name: ""), f), true)
        XCTAssertEqual(holds(.volumeMounted(uuid: "00000000-2FA1-11D2-883F-0016D3CCA427", name: ""), f), false)
        f.usb = [USBFact(vendor: 1, product: 2, serialHash: digest)]
        XCTAssertEqual(holds(.usbDevice(vendor: 1, product: 2, serialHash: nil, name: ""), f), true)
        XCTAssertEqual(holds(.usbDevice(vendor: 1, product: 2, serialHash: digest, name: ""), f), true)
        XCTAssertEqual(holds(.usbDevice(vendor: 1, product: 2, serialHash: "ee" + digest, name: ""), f), false)
        XCTAssertEqual(holds(.usbDevice(vendor: 1, product: 3, serialHash: nil, name: ""), f), false)
        f.network = NetworkFacts(addresses: ["10.1.2.3", "fe80::1"], routerHashes: [digest], vpn: false)
        XCTAssertEqual(holds(.network(.router(hash: digest, label: "")), f), true)
        XCTAssertEqual(holds(.network(.router(hash: "00" + digest, label: "")), f), false)
        XCTAssertEqual(holds(.network(.vpnConnected), f), false)
        XCTAssertEqual(holds(.network(.subnet(cidr: "10.0.0.0/8")), f),
                       NetworkMath.cidrContains("10.0.0.0/8", address: "10.1.2.3")
                        || NetworkMath.cidrContains("10.0.0.0/8", address: "fe80::1"))
        f.bluetooth = BluetoothFact(audioUIDHashes: [], inputHashes: [digest])
        XCTAssertEqual(holds(.bluetooth(.anyAudio), f), false)
        XCTAssertEqual(holds(.bluetooth(.input(hash: digest, name: "")), f), true)
        XCTAssertEqual(holds(.bluetooth(.audio(uidHash: digest, name: "")), f), false)
    }

    // MARK: Conditions

    func testAllAndAnyWithUnknowns() {
        var f = CriterionFacts()
        f.power = power(ac: true)
        let known = AwakeCriterion.power(.onAdapter)
        let unknown = AwakeCriterion.audio(.outputActive)
        XCTAssertTrue(TriggerEngine.condition(rule("a", [known]), facts: f))
        XCTAssertFalse(TriggerEngine.condition(rule("a", [known, unknown]), facts: f), "all: unknown counts as false")
        XCTAssertTrue(TriggerEngine.condition(rule("a", [known, unknown], match: .any), facts: f), "any: unknowns ignored")
        XCTAssertFalse(TriggerEngine.condition(rule("a", [unknown], match: .any), facts: f))
        XCTAssertFalse(TriggerEngine.condition(rule("a", []), facts: f))
        XCTAssertFalse(TriggerEngine.condition(rule("a", [], match: .any), facts: f))
        var negated = rule("n", [known])
        negated.criteria[0].negated = true
        XCTAssertFalse(TriggerEngine.condition(negated, facts: f))
    }

    // MARK: Step

    private func onAdapter(_ ac: Bool) -> CriterionFacts {
        var f = CriterionFacts()
        f.power = power(ac: ac)
        return f
    }

    private struct Runner {
        var hysteresis: [StableID: TriggerHysteresis] = [:]
        var suppressions: [StableID: TriggerSuppression] = [:]
        mutating func step(_ triggers: [AwakeTrigger], _ facts: CriterionFacts, at now: Double, paused: Bool = false,
                           guardsHold: Bool = false) -> TriggerStepResult {
            let r = TriggerEngine.step(triggers, facts: facts, now: now, hysteresis: hysteresis, suppressions: suppressions,
                                       paused: paused, guardsHold: guardsHold)
            hysteresis = r.hysteresis
            suppressions = r.suppressions
            return r
        }
    }

    func testStartAndEndDelaysOnTheContinuousClock() {
        let t = rule("desk", [.power(.onAdapter)], start: 60, end: 30)
        var run = Runner()
        var r = run.step([t], onAdapter(true), at: 1_000)
        XCTAssertNil(r.top)
        XCTAssertEqual(r.nextDeadline, 1_060)
        r = run.step([t], onAdapter(true), at: 1_059)
        XCTAssertNil(r.top)
        r = run.step([t], onAdapter(true), at: 1_060)
        XCTAssertEqual(r.top?.id, t.id)
        XCTAssertEqual(r.top?.since, 1_060)
        XCTAssertNil(r.nextDeadline)
        // A short drop inside the end delay keeps it active, and the start delay doesn't restart.
        r = run.step([t], onAdapter(false), at: 2_000)
        XCTAssertEqual(r.top?.id, t.id)
        XCTAssertEqual(r.nextDeadline, 2_030)
        r = run.step([t], onAdapter(true), at: 2_010)
        XCTAssertEqual(r.top?.since, 1_060, "since is stable through a blip")
        r = run.step([t], onAdapter(false), at: 3_000)
        r = run.step([t], onAdapter(false), at: 3_030)
        XCTAssertNil(r.top)
        XCTAssertNil(run.hysteresis[t.id]?.activeSince)
    }

    func testZeroDelaysActAtOnce() {
        let t = rule("z", [.power(.onAdapter)])
        var run = Runner()
        XCTAssertEqual(run.step([t], onAdapter(true), at: 5).top?.id, t.id)
        XCTAssertNil(run.step([t], onAdapter(false), at: 6).top)
    }

    func testPriorityIsListOrderAndReorderKeepsTheSession() {
        let a = rule("a", [.power(.onAdapter)]), b = rule("b", [.power(.charging)]), c = rule("c", [.power(.onAdapter)])
        var f = onAdapter(true)
        f.power = power(ac: true, charging: true)
        var run = Runner()
        var r = run.step([a, b, c], f, at: 10)
        XCTAssertEqual(r.top?.id, a.id)
        XCTAssertEqual(r.top?.index, 0)
        r = run.step([b, a, c], f, at: 11)
        XCTAssertEqual(r.top?.id, b.id)
        XCTAssertEqual(r.top?.since, 10, "already active: the reorder doesn't restart anything")
        f.power = power(ac: true, charging: false)
        r = run.step([b, a, c], f, at: 12)
        XCTAssertEqual(r.top?.id, a.id)
        XCTAssertEqual(r.top?.index, 1)
    }

    func testDisabledPausedGuardHeldAndEmptyRulesNeverGovernButKeepTheirHysteresis() {
        var off = rule("off", [.power(.onAdapter)])
        off.enabled = false
        let on = rule("on", [.power(.onAdapter)], start: 0)
        var run = Runner()
        var r = run.step([off], onAdapter(true), at: 1)
        XCTAssertNil(r.top)
        XCTAssertEqual(run.hysteresis[off.id]?.active, true, "hysteresis still advances")
        r = run.step([on], onAdapter(true), at: 2, paused: true)
        XCTAssertNil(r.top)
        r = run.step([on], onAdapter(true), at: 3, guardsHold: true)
        XCTAssertNil(r.top)
        // When the pause ends, a rule whose condition held all along governs at once, with its original since.
        r = run.step([on], onAdapter(true), at: 4)
        XCTAssertEqual(r.top?.id, on.id)
        XCTAssertEqual(r.top?.since, 2)
        XCTAssertNil(run.step([rule("empty", [])], onAdapter(true), at: 5).top)
    }

    func testManualEndWithoutResumeSuppressesUntilTheConditionGoesFalse() {
        let t = rule("t", [.power(.onAdapter)], end: 10)
        var run = Runner()
        XCTAssertNotNil(run.step([t], onAdapter(true), at: 0).top)
        run.suppressions[t.id] = TriggerEngine.manualEnd(t, now: 1)
        XCTAssertEqual(run.suppressions[t.id], TriggerSuppression(until: nil, untilFalse: true))
        XCTAssertNil(run.step([t], onAdapter(true), at: 2).top)
        XCTAssertNil(run.step([t], onAdapter(true), at: 5_000).top, "stays off while the condition holds")
        // False for less than the end delay: still suppressed.
        XCTAssertNil(run.step([t], onAdapter(false), at: 5_001).top)
        XCTAssertNil(run.step([t], onAdapter(true), at: 5_005).top)
        XCTAssertNotNil(run.suppressions[t.id])
        // Really false, then true again: governs again.
        XCTAssertNil(run.step([t], onAdapter(false), at: 6_000).top)
        XCTAssertNil(run.step([t], onAdapter(false), at: 6_010).top)
        XCTAssertNil(run.suppressions[t.id], "the suppression expired")
        XCTAssertEqual(run.step([t], onAdapter(true), at: 6_020).top?.id, t.id)
    }

    func testManualEndWithResumeMinutes() {
        var t = rule("t", [.power(.onAdapter)])
        t.resumeAfterManualEndMinutes = 15
        var run = Runner()
        XCTAssertNotNil(run.step([t], onAdapter(true), at: 0).top)
        run.suppressions[t.id] = TriggerEngine.manualEnd(t, now: 100)
        XCTAssertEqual(run.suppressions[t.id], TriggerSuppression(until: 1_000, untilFalse: false))
        let r = run.step([t], onAdapter(true), at: 500)
        XCTAssertNil(r.top)
        XCTAssertEqual(r.nextDeadline, 1_000, "the suppression's end is the next deadline")
        XCTAssertEqual(run.step([t], onAdapter(true), at: 1_000).top?.id, t.id)
        XCTAssertNil(run.suppressions[t.id])
    }

    func testSuppressionsForDeletedRulesAreDropped() {
        let t = rule("t", [.power(.onAdapter)])
        var run = Runner()
        run.suppressions[id("gone")] = TriggerSuppression(until: nil, untilFalse: true)
        run.suppressions[t.id] = TriggerSuppression(until: 50, untilFalse: false)
        _ = run.step([t], onAdapter(true), at: 10)
        XCTAssertEqual(Array(run.suppressions.keys), [t.id])
        XCTAssertNil(run.hysteresis[id("gone")])
    }

    func testRuleOptionsNeverNudgeAndDuplicatesAreIgnored() {
        var t = rule("t", [.power(.onAdapter)])
        t.options = AwakeSessionOptions(display: .maySleep, displayIdleMinutes: 0, activity: .nudge)
        var dup = rule("t", [.power(.onBattery)])
        dup.name = "dup"
        var run = Runner()
        let r = run.step([t, dup], onAdapter(true), at: 1)
        XCTAssertEqual(r.top?.options, AwakeSessionOptions(display: .maySleep, displayIdleMinutes: 1, activity: .declare))
        XCTAssertEqual(r.hysteresis.count, 1)
        XCTAssertNil(TriggerEngine.step([t], facts: onAdapter(true), now: .nan, hysteresis: [:], suppressions: [:],
                                        paused: false, guardsHold: false).top)
    }

    func testRequiredKindsAndScheduleBoundaries() {
        var off = rule("off", [.audio(.outputActive)])
        off.enabled = false
        let rules = [rule("a", [.power(.onAdapter), .schedule(days: .day(1), startMinute: 540, endMinute: 1_020)]),
                     rule("b", [.schedule(days: .day(6), startMinute: 1_380, endMinute: 120)]), off]
        XCTAssertEqual(TriggerEngine.requiredKinds(rules), [.power, .schedule])
        XCTAssertEqual(TriggerEngine.scheduleBoundaries(rules),
                       [1_440 + 540, 1_440 + 1_020, 6 * 1_440 + 1_380, 120])
        XCTAssertEqual(TriggerEngine.scheduleBoundaries([off]), [])
    }

    // MARK: Summary

    func testSummaryWording() {
        let r = rule("", [.app(bundleID: "com.apple.dt.Xcode", name: "Xcode", frontmost: false), .power(.onAdapter)])
        XCTAssertEqual(TriggerEngine.summary(r), "When Xcode is open and the power adapter is connected")
        var any = r
        any.match = .any
        any.criteria[1].negated = true
        XCTAssertEqual(TriggerEngine.summary(any), "When Xcode is open or the power adapter is not connected")
        let s = rule("", [.schedule(days: .weekdays, startMinute: 540, endMinute: 1_020)])
        XCTAssertEqual(TriggerEngine.summary(s), "When it's 9:00 AM–5:00 PM on weekdays")
        XCTAssertEqual(TriggerEngine.summary(s, text: AwakeTextContext(uses24Hour: true, decimalSeparator: ",")),
                       "When it's 09:00–17:00 on weekdays")
        XCTAssertEqual(TriggerEngine.summary(rule("", [.display(.specific(record: FingerprintRecord(t2: digest), name: "DELL U2720Q"))])),
                       "When “DELL U2720Q” is connected")
        XCTAssertEqual(TriggerEngine.summary(rule("", [])), "No conditions")
        XCTAssertEqual(TriggerEngine.daysText([.day(1), .day(3), .day(5)]), "on Mon, Wed, Fri")
        XCTAssertEqual(TriggerEngine.daysText(.everyDay), "every day")
        XCTAssertEqual(TriggerEngine.daysText(.weekend), "on weekends")
        XCTAssertEqual(rule("named", [.power(.charging)]).displayName(), "named")
        XCTAssertEqual(rule("", [.power(.charging)]).displayName(), "When the battery is charging")
    }

    func testEveryPhraseIsNonEmptyAndDiffersWhenNegated() {
        let all: [AwakeCriterion] = [
            .app(bundleID: "a.b", name: "", frontmost: true), .display(.anyExternal), .display(.mirroring),
            .display(.specific(record: FingerprintRecord(t2: digest), name: "")), .power(.onBattery), .power(.charging),
            .power(.batteryAtLeast(50)), .schedule(days: .everyDay, startMinute: 0, endMinute: 0), .cpuAbove(percent: 50),
            .audio(.outputActive), .audio(.microphoneActive), .idle(atLeastMinutes: 1), .volumeMounted(uuid: "u", name: ""),
            .usbDevice(vendor: 1, product: 1, serialHash: nil, name: "Dock"), .network(.subnet(cidr: "10.0.0.0/8")),
            .network(.router(hash: digest, label: "Home")), .network(.vpnConnected), .networkActivity(atLeastKBps: 10),
            .bluetooth(.audio(uidHash: digest, name: "")), .bluetooth(.input(hash: digest, name: "")), .bluetooth(.anyAudio),
        ]
        for c in all {
            let yes = TriggerEngine.phrase(AwakeCriterionEntry(c), text: .standard)
            let no = TriggerEngine.phrase(AwakeCriterionEntry(c, negated: true), text: .standard)
            XCTAssertFalse(yes.isEmpty)
            XCTAssertNotEqual(yes, no, "\(c)")
        }
    }

    // MARK: Fuzz

    func testStepFuzzPriorityAndDeterminism() {
        var rng = SeededGenerator(seed: 0x7E57)
        let pool: [AwakeCriterion] = [.power(.onAdapter), .power(.charging), .audio(.outputActive), .cpuAbove(percent: 50),
                                      .schedule(days: .weekdays, startMinute: 540, endMinute: 1_020),
                                      .idle(atLeastMinutes: 1)]
        for _ in 0..<300 {
            let count = 1 + Int(rng.next() % 6)
            var rules: [AwakeTrigger] = (0..<count).map { i in
                var t = rule("r\(i)", (0..<(1 + Int(rng.next() % 3))).map { _ in pool[Int(rng.next() % UInt64(pool.count))] },
                             match: rng.next() % 2 == 0 ? .all : .any, start: Int(rng.next() % 4) * 30,
                             end: Int(rng.next() % 4) * 30)
                t.enabled = rng.next() % 5 != 0
                return t
            }
            var runA = Runner(), runB = Runner()
            var now = 0.0
            for _ in 0..<60 {
                var f = CriterionFacts()
                if rng.next() % 4 != 0 { f.power = power(ac: rng.next() % 2 == 0, charging: rng.next() % 2 == 0) }
                if rng.next() % 3 != 0 { f.audioOutput = rng.next() % 2 == 0 }
                f.cpuPercent = Double(rng.next() % 100)
                f.minuteOfWeek = Int(rng.next() % 10_080)
                f.realIdleSeconds = Double(rng.next() % 200)
                let paused = rng.next() % 10 == 0, held = rng.next() % 10 == 0
                now += Double(rng.next() % 90)
                if rng.next() % 15 == 0 { rules.reverse() }
                let r = runA.step(rules, f, at: now, paused: paused, guardsHold: held)
                let again = runB.step(rules, f, at: now, paused: paused, guardsHold: held)
                XCTAssertEqual(r, again, "deterministic")
                if let top = r.top {
                    XCTAssertFalse(paused)
                    XCTAssertFalse(held)
                    // The top is the first eligible active rule in list order.
                    XCTAssertEqual(rules[top.index].id, top.id)
                    for earlier in rules[..<top.index] {
                        let eligible = earlier.enabled && r.hysteresis[earlier.id]?.active == true
                            && r.suppressions[earlier.id] == nil
                        XCTAssertFalse(eligible, "an earlier eligible rule exists")
                    }
                    XCTAssertTrue(rules[top.index].enabled)
                    XCTAssertNotEqual(top.options.activity, .nudge)
                    XCTAssertLessThanOrEqual(top.since, now)
                } else if !paused && !held {
                    for t in rules where t.enabled {
                        XCTAssertFalse(r.hysteresis[t.id]?.active == true && r.suppressions[t.id] == nil)
                    }
                }
                if let next = r.nextDeadline { XCTAssertGreaterThan(next, now) }
            }
        }
    }

    func testCommandLinePauseOnlyExtends() {
        let now = 1_000_000.0
        let day = 24 * 3_600.0
        // Paused until tomorrow: a 1-minute CLI pause leaves it.
        XCTAssertEqual(TriggerEngine.pausedUntil(current: now + 10 * 3_600, now: now, seconds: 60, limit: day, onlyExtend: true),
                       now + 10 * 3_600)
        // A longer CLI pause extends it, capped at the limit.
        XCTAssertEqual(TriggerEngine.pausedUntil(current: now + 600, now: now, seconds: 3_600, limit: day, onlyExtend: true),
                       now + 3_600)
        XCTAssertEqual(TriggerEngine.pausedUntil(current: nil, now: now, seconds: 9 * day, limit: day, onlyExtend: true),
                       now + day)
        // An expired pause doesn't count; the UI may shorten (its own choice).
        XCTAssertEqual(TriggerEngine.pausedUntil(current: now - 5, now: now, seconds: 60, limit: day, onlyExtend: true), now + 60)
        XCTAssertEqual(TriggerEngine.pausedUntil(current: now + day, now: now, seconds: 3_600, limit: day, onlyExtend: false),
                       now + 3_600)
        XCTAssertEqual(TriggerEngine.pausedUntil(current: nil, now: now, seconds: .nan, limit: day, onlyExtend: true), now + 60)
    }
}
