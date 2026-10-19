import XCTest
@testable import SnapticKit

final class AwakeFeatureGraphTests: XCTestCase {
    private let all = Set(AwakeFeature.allCases)

    func testSpecsAreTotalAndControllersExist() {
        XCTAssertEqual(Set(AwakeFeatureGraph.specs.keys), all)
        let controllers = Set(AwakeFeature.allCases.map { AwakeFeatureGraph.controller(of: $0) })
        XCTAssertEqual(controllers, Set(AwakeControllerID.allCases))
        for f in AwakeFeature.allCases {
            for r in AwakeFeatureGraph.spec(f).requiresAll { XCTAssertNotEqual(r, f) }
        }
    }

    func testDefaults() {
        let on = AwakeFeatureGraph.resolve(raw: [:], killSwitches: [], safeMode: false, unavailable: [])
        XCTAssertEqual(on, [.sessions, .presets, .batteryGuard, .thermalGuard, .indicator, .history, .shortcuts, .commandLine])
        XCTAssertTrue(AwakeFeatureGraph.rawState(.sessions, in: [.sessions: false]))   // always on
        XCTAssertFalse(AwakeFeatureGraph.rawState(.triggers, in: [:]))
        XCTAssertTrue(AwakeFeatureGraph.rawState(.triggers, in: [.triggers: true]))
        XCTAssertFalse(AwakeFeatureGraph.rawState(.history, in: [.history: false]))
    }

    func testUnkillableSurviveEveryKillSwitch() {
        let raw = Dictionary(uniqueKeysWithValues: AwakeFeature.allCases.map { ($0, true) })
        let on = AwakeFeatureGraph.resolve(raw: raw, killSwitches: all, safeMode: false, unavailable: [])
        XCTAssertEqual(on, AwakeFeatureGraph.unkillable)
        XCTAssertTrue(AwakeFeatureGraph.unkillable.contains(.indicator))   // R5 (N11)
        XCTAssertEqual(AwakeFeatureGraph.resolve(raw: raw, killSwitches: [], safeMode: false, unavailable: []), all)
    }

    func testSafeModeRemovesBackgroundFeaturesOnly() {
        let raw = Dictionary(uniqueKeysWithValues: AwakeFeature.allCases.map { ($0, true) })
        let on = AwakeFeatureGraph.resolve(raw: raw, killSwitches: [], safeMode: true, unavailable: [])
        XCTAssertEqual(on, all.subtracting(AwakeFeatureGraph.safeModeRemoves))
        XCTAssertTrue(on.contains(.sessions) && on.contains(.batteryGuard) && on.contains(.commandLine))
    }

    func testRequirementsCloseOver() {
        // pointerNudge needs activity, which needs sessions.
        let on = AwakeFeatureGraph.resolve(raw: [.pointerNudge: true, .activity: false], killSwitches: [], safeMode: false,
                                           unavailable: [])
        XCTAssertFalse(on.contains(.pointerNudge))
        let killed = AwakeFeatureGraph.resolve(raw: [.pointerNudge: true, .activity: true], killSwitches: [.activity],
                                               safeMode: false, unavailable: [])
        XCTAssertFalse(killed.contains(.pointerNudge))
        let unavailable = AwakeFeatureGraph.resolve(raw: [.history: true], killSwitches: [], safeMode: false,
                                                    unavailable: [.sessions])
        XCTAssertFalse(unavailable.contains(.history))
        XCTAssertFalse(unavailable.contains(.presets))
    }

    func testEnablingTurnsOnRequirementsOrRefuses() {
        let enabled = AwakeFeatureGraph.enabling(.pointerNudge, raw: [:], available: all)
        XCTAssertEqual(enabled?[.pointerNudge], true)
        XCTAssertEqual(enabled?[.activity], true)
        XCTAssertEqual(enabled?[.sessions], true)
        XCTAssertNil(AwakeFeatureGraph.enabling(.pointerNudge, raw: [:], available: all.subtracting([.activity])))
        XCTAssertNil(AwakeFeatureGraph.enabling(.driveAlive, raw: [:], available: []))
    }

    func testServicesPerCriterionKindAndNeed() {
        XCTAssertEqual(AwakeFeatureGraph.services(of: AwakeCriterionKind.schedule), [])
        XCTAssertEqual(AwakeFeatureGraph.services(of: AwakeCriterionKind.networkActivity), [.network])
        for kind in AwakeCriterionKind.allCases where kind != .schedule {
            XCTAssertEqual(AwakeFeatureGraph.services(of: kind).count, 1, kind.rawValue)
        }
        XCTAssertEqual(AwakeFeatureGraph.services(of: AwakeDynamicNeeds.taskQuiet), [.cpu, .disk, .network])
        XCTAssertEqual(AwakeFeatureGraph.services(of: [.apps, .idle, .process]), [.apps, .idle, .process])
        XCTAssertEqual(AwakeFeatureGraph.services(of: AwakeDynamicNeeds()), [])
    }

    func testRequiredServices() {
        let base = AwakeFeatureGraph.resolve(raw: [:], killSwitches: [], safeMode: false, unavailable: [])
        XCTAssertEqual(AwakeFeatureGraph.requiredServices(effective: base, criteria: [.usb], dynamic: []),
                       [.assertions, .power, .system, .process])
        let withTriggers = base.union([.triggers])
        XCTAssertEqual(AwakeFeatureGraph.requiredServices(effective: withTriggers, criteria: [.usb, .schedule], dynamic: [.idle]),
                       [.assertions, .power, .system, .process, .usb, .idle])
        XCTAssertEqual(AwakeFeatureGraph.requiredServices(effective: [], criteria: [.usb], dynamic: [.apps]), [])
    }

    func testActivationOrderCoversEveryServiceOnceDependenciesFirst() {
        let order = AwakeFeatureGraph.activationOrder
        XCTAssertEqual(Set(order), Set(AwakeServiceID.allCases))
        XCTAssertEqual(order.count, AwakeServiceID.allCases.count)
        XCTAssertEqual(Array(order.prefix(3)), [.assertions, .power, .system])
        XCTAssertEqual(Array(order.suffix(2)), [.activity, .driveAlive])
        XCTAssertLessThan(order.firstIndex(of: .volumes)!, order.firstIndex(of: .driveAlive)!)
        XCTAssertLessThan(order.firstIndex(of: .idle)!, order.firstIndex(of: .activity)!)
    }

    func testPermissions() {
        XCTAssertEqual(AwakeFeatureGraph.permissions(.pointerNudge), [.accessibility])
        XCTAssertEqual(AwakeFeatureGraph.permissions(.driveAlive), [])
    }

    func testFuzzedResolutionIsClosedAndRespectsUnkillable() {
        var rng = SeededGenerator(seed: 0xA3A4E)
        for _ in 0..<1_000 {
            var raw: [AwakeFeature: Bool] = [:]
            for f in AwakeFeature.allCases where rng.next() % 3 != 0 { raw[f] = rng.next() % 2 == 0 }
            let kills = Set(AwakeFeature.allCases.filter { _ in rng.next() % 4 == 0 })
            let unavailable = Set(AwakeFeature.allCases.filter { _ in rng.next() % 6 == 0 })
            let safe = rng.next() % 2 == 0
            let on = AwakeFeatureGraph.resolve(raw: raw, killSwitches: kills, safeMode: safe, unavailable: unavailable)
            for f in on {
                XCTAssertTrue(AwakeFeatureGraph.spec(f).requiresAll.allSatisfy { on.contains($0) })
                XCTAssertFalse(unavailable.contains(f))
                if safe { XCTAssertFalse(AwakeFeatureGraph.safeModeRemoves.contains(f)) }
                if kills.contains(f) { XCTAssertTrue(AwakeFeatureGraph.unkillable.contains(f)) }
            }
            for f in AwakeFeatureGraph.unkillable where !unavailable.contains(f) {
                // Unkillable features are on unless unavailable (or missing a requirement).
                if AwakeFeatureGraph.spec(f).requiresAll.allSatisfy({ !unavailable.contains($0) }) {
                    XCTAssertTrue(on.contains(f))
                }
            }
        }
    }
}

// MARK: - 0.3.1 B5: lid-closed mode's feature (owner: T-lid-kit)

extension AwakeFeatureGraphTests {
    func testLidClosedFeature() {
        let spec = AwakeFeatureGraph.spec(.lidClosed)
        XCTAssertEqual(spec.requiresAll, [.sessions])
        XCTAssertEqual(AwakeFeatureGraph.controller(of: .lidClosed), .sessions)
        XCTAssertFalse(AwakeFeatureGraph.rawState(.lidClosed, in: [:]), "opt-in: off by default")
        XCTAssertTrue(AwakeFeatureGraph.rawState(.lidClosed, in: [.lidClosed: true]))
        XCTAssertFalse(AwakeFeatureGraph.unkillable.contains(.lidClosed), "Awake.disable.lidClosed forbids it")
        XCTAssertTrue(AwakeFeatureGraph.safeModeRemoves.contains(.lidClosed))
        let raw: [AwakeFeature: Bool] = [.lidClosed: true]
        XCTAssertTrue(AwakeFeatureGraph.resolve(raw: raw, killSwitches: [], safeMode: false, unavailable: []).contains(.lidClosed))
        XCTAssertFalse(AwakeFeatureGraph.resolve(raw: raw, killSwitches: [.lidClosed], safeMode: false, unavailable: [])
            .contains(.lidClosed))
        XCTAssertFalse(AwakeFeatureGraph.resolve(raw: raw, killSwitches: [], safeMode: true, unavailable: []).contains(.lidClosed))
        XCTAssertFalse(AwakeFeatureGraph.resolve(raw: raw, killSwitches: [], safeMode: false, unavailable: [.lidClosed])
            .contains(.lidClosed))
        XCTAssertEqual(AwakeFeatureLock.of(.lidClosed, killSwitches: [.lidClosed], safeMode: true), .killSwitch)
        XCTAssertEqual(AwakeFeatureLock.of(.lidClosed, killSwitches: [], safeMode: true), .safeMode)
    }
}
