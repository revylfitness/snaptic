import XCTest
@testable import SnapticKit

final class AwakeTriggersTests: XCTestCase {
    private let digest = String(repeating: "ab", count: 16)
    private func id(_ s: String) -> StableID { StableID.derived(namespace: "rules", name: s) }

    private var everyCriterion: [AwakeCriterion] {
        [
            .app(bundleID: "com.apple.dt.Xcode", name: "Xcode", frontmost: true),
            .display(.anyExternal), .display(.specific(record: FingerprintRecord(t2: digest), name: "DELL U2720Q")),
            .display(.mirroring),
            .power(.onAdapter), .power(.onBattery), .power(.charging), .power(.batteryAtLeast(40)),
            .schedule(days: .weekdays, startMinute: 540, endMinute: 1_020),
            .cpuAbove(percent: 50), .audio(.outputActive), .audio(.microphoneActive), .idle(atLeastMinutes: 10),
            .volumeMounted(uuid: "1B4E28BA-2FA1-11D2-883F-0016D3CCA427", name: "Backup"),
            .usbDevice(vendor: 0x05AC, product: 0x1234, serialHash: digest, name: "Dock"),
            .usbDevice(vendor: 1, product: 2, serialHash: nil, name: "Keyboard"),
            .network(.subnet(cidr: "10.0.0.0/8")), .network(.router(hash: digest, label: "Home")), .network(.vpnConnected),
            .networkActivity(atLeastKBps: 500),
            .bluetooth(.audio(uidHash: digest, name: "AirPods")), .bluetooth(.input(hash: digest, name: "Keyboard")),
            .bluetooth(.anyAudio),
        ]
    }

    private func text<T: Encodable>(_ v: T) throws -> String {
        String(decoding: try JSONEncoder().encode(v), as: UTF8.self)
    }

    func testEveryCriterionRoundTripsWithOneTypeKeyPerObject() throws {
        XCTAssertEqual(Set(everyCriterion.map(\.kind)), Set(AwakeCriterionKind.allCases))
        for c in everyCriterion {
            for negated in [false, true] {
                let entry = AwakeCriterionEntry(c, negated: negated)
                XCTAssertEqual(try JSONDecoder().decode(AwakeCriterionEntry.self, from: JSONEncoder().encode(entry)), entry)
            }
            XCTAssertEqual(c.sanitized(), c, "\(c) is already clean")
        }
        let nested = try text(AwakeCriterionEntry(.network(.subnet(cidr: "10.0.0.0/8"))))
        XCTAssertTrue(nested.contains(#""condition":{"#))
        XCTAssertEqual(nested.components(separatedBy: #""type""#).count - 1, 2, "one type key per object")
        let display = try text(AwakeCriterion.display(.anyExternal))
        XCTAssertTrue(display.contains(#""match":{"#))
    }

    func testDocumentedJSONShapeDecodes() throws {
        let json = #"{"criterion":{"type":"network","condition":{"type":"subnet","cidr":"10.0.0.0/8"}},"negated":false}"#
        let e = try JSONDecoder().decode(AwakeCriterionEntry.self, from: Data(json.utf8))
        XCTAssertEqual(e, AwakeCriterionEntry(.network(.subnet(cidr: "10.0.0.0/8"))))
        let app = #"{"criterion":{"type":"app","bundleID":"com.apple.dt.Xcode"},"negated":"yes"}"#
        XCTAssertEqual(try JSONDecoder().decode(AwakeCriterionEntry.self, from: Data(app.utf8)),
                       AwakeCriterionEntry(.app(bundleID: "com.apple.dt.Xcode", name: "", frontmost: false)))
    }

    func testUnknownKindsAndBrokenPayloadsDropTheEntry() {
        for json in [#"{"criterion":{"type":"weather","condition":"rain"}}"#,
                     #"{"criterion":{"type":"network","condition":{"type":"wifi6e"}}}"#,
                     #"{"criterion":{"type":"display","match":{"type":"hologram"}}}"#,
                     #"{"criterion":{"type":"power","condition":{"type":"batteryAtLeast"}}}"#,
                     #"{"criterion":{"type":"schedule","days":300,"startMinute":1,"endMinute":2}}"#,
                     #"{"criterion":{"type":"audio","condition":"speaker"}}"#,
                     #"{"criterion":{"type":"cpuAbove"}}"#, #"{"negated":true}"#,
                     #"{"criterion":{"type":"display","condition":{"type":"anyExternal"}}}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(AwakeCriterionEntry.self, from: Data(json.utf8)), json)
        }
    }

    func testRulesDecodeLossyPerEntryAndPerRule() throws {
        let a = id("a").rawValue, b = id("b").rawValue, c = id("c").rawValue
        let json = """
        {"triggers":[
          {"id":"\(a)","name":"Desk","criteria":[{"criterion":{"type":"weather"}},{"criterion":{"type":"power","condition":{"type":"onAdapter"}}}],
           "startDelaySeconds":"soon","match":"some"},
          {"id":"\(b)","name":"From 0.4","criteria":[],"options":{"display":"hologram"},"futureField":1},
          {"id":"not-an-id","name":"bad"},
          {"id":"\(c)","resumeAfterManualEndMinutes":15},
          {"id":"\(a)","name":"duplicate"}
        ]}
        """
        let config = try JSONDecoder().decode(AwakeTriggersConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.triggers.map(\.id.rawValue), [a, b, c])
        XCTAssertEqual(config.triggers[0].name, "Desk")
        XCTAssertEqual(config.triggers[0].criteria, [AwakeCriterionEntry(.power(.onAdapter))])
        XCTAssertEqual(config.triggers[0].startDelaySeconds, 0)
        XCTAssertEqual(config.triggers[0].match, .all)
        XCTAssertEqual(config.triggers[1].options, AwakeSessionOptions())
        XCTAssertEqual(config.triggers[2].resumeAfterManualEndMinutes, 15)
        XCTAssertEqual(config.triggers[2].endDelaySeconds, 30)
        // They survive the next save.
        let again = try JSONDecoder().decode(AwakeTriggersConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(again, config)
    }

    func testRuleRoundTrip() throws {
        var t = AwakeTrigger(id: id("x"), name: "Busy", criteria: everyCriterion.prefix(8).map { AwakeCriterionEntry($0) })
        t.match = .any
        t.enabled = false
        t.options = AwakeSessionOptions(display: .keepOnWhileActive, displayIdleMinutes: 12, activity: .declare)
        t.startDelaySeconds = 120
        t.endDelaySeconds = 0
        t.resumeAfterManualEndMinutes = 60
        XCTAssertEqual(try JSONDecoder().decode(AwakeTrigger.self, from: JSONEncoder().encode(t)), t)
    }

    func testDefaultsForNewRules() {
        let plain = AwakeTrigger(id: id("p"), name: "", criteria: [AwakeCriterionEntry(.power(.onAdapter))])
        XCTAssertTrue(plain.enabled)
        XCTAssertEqual(plain.match, .all)
        XCTAssertEqual(plain.startDelaySeconds, 0)
        XCTAssertEqual(plain.endDelaySeconds, 30)
        XCTAssertNil(plain.resumeAfterManualEndMinutes)
        let cpu = AwakeTrigger(id: id("c"), name: "", criteria: [AwakeCriterionEntry(.cpuAbove(percent: 50))])
        XCTAssertEqual(cpu.startDelaySeconds, 60)
        let net = AwakeTrigger(id: id("n"), name: "", criteria: [AwakeCriterionEntry(.networkActivity(atLeastKBps: 99))])
        XCTAssertEqual(net.startDelaySeconds, 60)
    }

    // MARK: Sanitize

    func testCriterionSanitizeClampsAndDrops() {
        XCTAssertEqual(AwakeCriterion.cpuAbove(percent: 1).sanitized(), .cpuAbove(percent: 5))
        XCTAssertEqual(AwakeCriterion.cpuAbove(percent: 500).sanitized(), .cpuAbove(percent: 100))
        XCTAssertEqual(AwakeCriterion.idle(atLeastMinutes: 0).sanitized(), .idle(atLeastMinutes: 1))
        XCTAssertEqual(AwakeCriterion.idle(atLeastMinutes: 9_999).sanitized(), .idle(atLeastMinutes: 480))
        XCTAssertEqual(AwakeCriterion.networkActivity(atLeastKBps: 1).sanitized(), .networkActivity(atLeastKBps: 10))
        XCTAssertEqual(AwakeCriterion.power(.batteryAtLeast(250)).sanitized(), .power(.batteryAtLeast(100)))
        XCTAssertEqual(AwakeCriterion.schedule(days: .everyDay, startMinute: -5, endMinute: 5_000).sanitized(),
                       .schedule(days: .everyDay, startMinute: 0, endMinute: 1_439))
        XCTAssertNil(AwakeCriterion.schedule(days: [], startMinute: 0, endMinute: 10).sanitized())
        XCTAssertNil(AwakeCriterion.app(bundleID: "Xcode", name: "", frontmost: false).sanitized())
        XCTAssertNil(AwakeCriterion.display(.specific(record: FingerprintRecord(), name: "x")).sanitized())
        XCTAssertNil(AwakeCriterion.volumeMounted(uuid: "nope", name: "x").sanitized())
        XCTAssertEqual(AwakeCriterion.volumeMounted(uuid: "1b4e28ba-2fa1-11d2-883f-0016d3cca427", name: "x").sanitized(),
                       .volumeMounted(uuid: "1B4E28BA-2FA1-11D2-883F-0016D3CCA427", name: "x"))
        XCTAssertNil(AwakeCriterion.usbDevice(vendor: 0x1_0000, product: 1, serialHash: nil, name: "").sanitized())
        XCTAssertNil(AwakeCriterion.usbDevice(vendor: 1, product: 1, serialHash: "RAW-SERIAL", name: "").sanitized())
        XCTAssertNil(AwakeCriterion.network(.router(hash: "aa:bb:cc:dd:ee:ff", label: "")).sanitized(), "raw MACs never stay")
        XCTAssertNil(AwakeCriterion.bluetooth(.audio(uidHash: "raw", name: "")).sanitized())
        let long = String(repeating: "x", count: 200) + "\u{202E}"
        if case .app(_, let n, _)? = AwakeCriterion.app(bundleID: "a.b", name: long, frontmost: false).sanitized() {
            XCTAssertEqual(n.unicodeScalars.count, 64)
        } else {
            XCTFail("app criterion dropped")
        }
    }

    func testCIDRShape() {
        for ok in ["10.0.0.0/8", "192.168.1.0/24", "fd00::/8", "2001:DB8::/32", "0.0.0.0/0", "::/128"] {
            XCTAssertTrue(AwakeCriterion.looksLikeCIDR(ok), ok)
        }
        for bad in ["10.0.0.0", "10.0.0.0/129", "10.0.0.0/-1", "/8", "x.y.z.w/8", "10.0.0.0/8/8", "10.0.0.0/ 8", "",
                    "1/8", String(repeating: "1", count: 60) + "/8"] {
            XCTAssertFalse(AwakeCriterion.looksLikeCIDR(bad), bad)
        }
    }

    func testRuleSanitize() {
        var t = AwakeTrigger(id: id("s"), name: String(repeating: "n", count: 100) + "\u{0007}",
                             criteria: (0..<12).map { AwakeCriterionEntry(.idle(atLeastMinutes: $0 + 1)) }
                                + [AwakeCriterionEntry(.app(bundleID: "bad id", name: "", frontmost: false))])
        t.options = AwakeSessionOptions(display: .keepOn, displayIdleMinutes: 0, activity: .nudge)
        t.startDelaySeconds = -1
        t.endDelaySeconds = 99_999
        t.resumeAfterManualEndMinutes = 0
        let s = t.sanitized()
        XCTAssertEqual(s.name.unicodeScalars.count, 64)
        XCTAssertEqual(s.criteria.count, AwakeTrigger.maxCriteria)
        XCTAssertEqual(s.options.activity, .declare, "rules never move the pointer")
        XCTAssertEqual(s.options.displayIdleMinutes, 1)
        XCTAssertEqual(s.startDelaySeconds, 0)
        XCTAssertEqual(s.endDelaySeconds, 3_600)
        XCTAssertEqual(s.resumeAfterManualEndMinutes, 1)
        XCTAssertTrue(s.enabled)
        // No valid criterion left → disabled.
        let empty = AwakeTrigger(id: id("e"), name: "", criteria: [AwakeCriterionEntry(.app(bundleID: "x", name: "", frontmost: false))])
        XCTAssertFalse(empty.sanitized().enabled)
        XCTAssertTrue(empty.sanitized().criteria.isEmpty)
        XCTAssertEqual(s.sanitized(), s, "idempotent")
    }

    func testConfigSanitizeLimitsAndDuplicates() {
        var c = AwakeTriggersConfig()
        c.triggers = (0..<40).map { AwakeTrigger(id: id("r\($0)"), name: "", criteria: [AwakeCriterionEntry(.power(.charging))]) }
        c.triggers.insert(AwakeTrigger(id: id("r3"), name: "dup", criteria: []), at: 5)
        let s = c.sanitized()
        XCTAssertEqual(s.triggers.count, AwakeTrigger.maxTriggers)
        XCTAssertEqual(s.triggers[5].id, id("r5"), "the later duplicate r3 was dropped")
        XCTAssertEqual(s.triggers.filter { $0.id == id("r3") }.count, 1)
        XCTAssertNotEqual(s.triggers.first { $0.id == id("r3") }?.name, "dup")
    }

    func testStrippingHashes() throws {
        var c = AwakeTriggersConfig()
        c.triggers = [
            AwakeTrigger(id: id("1"), name: "", criteria: [AwakeCriterionEntry(.display(.specific(record: FingerprintRecord(t3: digest), name: "D"))),
                                                           AwakeCriterionEntry(.power(.onAdapter))]),
            AwakeTrigger(id: id("2"), name: "", criteria: [AwakeCriterionEntry(.network(.router(hash: digest, label: "Home")))]),
            AwakeTrigger(id: id("3"), name: "", criteria: [AwakeCriterionEntry(.usbDevice(vendor: 1, product: 2, serialHash: digest, name: "Dock"), negated: true)]),
        ]
        let s = c.strippingHashes()
        XCTAssertEqual(s.triggers[0].criteria, [AwakeCriterionEntry(.power(.onAdapter))])
        XCTAssertFalse(s.triggers[0].enabled, "fewer conditions could apply more often: disabled")
        XCTAssertFalse(s.triggers[1].enabled)
        XCTAssertEqual(s.triggers[2].criteria,
                       [AwakeCriterionEntry(.usbDevice(vendor: 1, product: 2, serialHash: nil, name: "Dock"), negated: true)])
        XCTAssertFalse(s.triggers[2].enabled)
        XCTAssertFalse(try text(s).contains(digest))
        // A rule without salted conditions is untouched.
        var plain = AwakeTriggersConfig()
        plain.triggers = [AwakeTrigger(id: id("4"), name: "", criteria: [AwakeCriterionEntry(.power(.onAdapter))])]
        XCTAssertEqual(plain.strippingHashes(), plain)
    }

    func testWeekdaySet() throws {
        XCTAssertEqual(WeekdaySet(rawValue: 0xFF).rawValue, 0x7F, "masked")
        XCTAssertEqual(WeekdaySet.everyDay, WeekdaySet.weekdays.union(.weekend))
        XCTAssertTrue(WeekdaySet.weekdays.contains(day: 1))
        XCTAssertFalse(WeekdaySet.weekdays.contains(day: 0))
        XCTAssertTrue(WeekdaySet.weekend.contains(day: -1), "Saturday by wrap-around")
        XCTAssertTrue(WeekdaySet.weekend.contains(day: 7), "Sunday by wrap-around")
        XCTAssertEqual(try JSONDecoder().decode([WeekdaySet].self, from: Data("[127, 2]".utf8)), [.everyDay, .day(1)])
    }

    func testCriterionKinds() {
        XCTAssertEqual(AwakeCriterion.cpuAbove(percent: 5).kind, .cpu)
        XCTAssertEqual(AwakeCriterion.volumeMounted(uuid: "", name: "").kind, .volume)
        XCTAssertEqual(AwakeCriterion.usbDevice(vendor: 0, product: 0, serialHash: nil, name: "").kind, .usb)
        XCTAssertEqual(AwakeCriterion.networkActivity(atLeastKBps: 10).kind, .networkActivity)
    }

    func testDecodeFuzzNeverTraps() {
        var rng = SeededGenerator(seed: 0x7123)
        let pieces = [#"{"#, #"}"#, #"["#, #"]"#, #","#, #":"#, #""type""#, #""app""#, #""network""#, #""condition""#,
                      #""subnet""#, #""cidr""#, #""10.0.0.0/8""#, #""criterion""#, #""negated""#, "true", "1", "-7",
                      #""match""#, #""display""#, #""specific""#, #""record""#, #""t2""#, #""schedule""#, #""days""#]
        for _ in 0..<20_000 {
            let n = Int(rng.next() % 24)
            let json = (0..<n).map { _ in pieces[Int(rng.next() % UInt64(pieces.count))] }.joined()
            if let e = try? JSONDecoder().decode(AwakeCriterionEntry.self, from: Data(json.utf8)) {
                _ = e.criterion.sanitized()
                XCTAssertEqual(try? JSONDecoder().decode(AwakeCriterionEntry.self, from: JSONEncoder().encode(e)), e)
            }
            _ = try? JSONDecoder().decode(AwakeTriggersConfig.self, from: Data(json.utf8))
        }
    }

    // MARK: Rule editor

    func testCriterionChoicesRoundTrip() {
        for choice in AwakeCriterionChoice.allCases {
            XCTAssertFalse(choice.title.isEmpty)
            guard let c = choice.defaultCriterion else {
                XCTAssertTrue([.app, .volume, .usb, .router].contains(choice), choice.rawValue)
                continue
            }
            XCTAssertEqual(AwakeCriterionChoice(c), choice)
            XCTAssertEqual(c.kind, choice.kind)
            XCTAssertEqual(c.sanitized(), c, "\(choice.rawValue) starts valid")
        }
        XCTAssertEqual(AwakeCriterionChoice(.network(.router(hash: String(repeating: "a", count: 64), label: "Home"))), .router)
        XCTAssertEqual(AwakeCriterionChoice.router.title, "Connected to this network")
        XCTAssertFalse(AwakeCriterionChoice.power.allowsNegation)
        XCTAssertTrue(AwakeCriterionChoice.app.allowsNegation)
        XCTAssertTrue(AwakeCriterionChoice.bluetooth.isBeta)
    }

    func testEditorDelaysAndNewRules() {
        XCTAssertEqual(AwakeTrigger.delayTitle(0), "None")
        XCTAssertEqual(AwakeTrigger.delayTitle(30), "30 seconds")
        XCTAssertEqual(AwakeTrigger.delayTitle(60), "1 minute")
        XCTAssertEqual(AwakeTrigger.delayTitle(1_800), "30 minutes")
        XCTAssertEqual(AwakeTrigger.delayTitle(3_600), "1 hour")
        XCTAssertEqual(AwakeTrigger.delayTitle(90), "90 seconds")
        XCTAssertEqual(AwakeTrigger.choices([0, 30, 60], including: 45), [0, 30, 45, 60])
        XCTAssertEqual(AwakeTrigger.choices([0, 30, 60], including: 30), [0, 30, 60])
        let id = StableID()
        let rule = AwakeTrigger.new(id: id, criterion: nil)
        XCTAssertEqual(rule.criteria, [AwakeCriterionEntry(.display(.anyExternal))])
        XCTAssertTrue(rule.enabled)
        var cpu = AwakeTrigger.new(id: id, criterion: .cpuAbove(percent: 70))
        cpu.startDelaySeconds = 0
        XCTAssertEqual(cpu.savedFromEditor(wasNew: true).startDelaySeconds, 60, "CPU rules wait a minute")
        XCTAssertEqual(cpu.savedFromEditor(wasNew: false).startDelaySeconds, 0, "an edited rule keeps the choice")
        var nudging = rule
        nudging.options.activity = .nudge
        XCTAssertEqual(nudging.savedFromEditor(wasNew: true).options.activity, .declare, "rules never move the pointer")
    }
}
