import XCTest
import SnapticKit

final class FeatureGraphTests: XCTestCase {
    private let all = Set(DisplayFeature.allCases)

    func testEveryFeatureHasASpecAndValidReferences() {
        for feature in DisplayFeature.allCases {
            let spec = FeatureGraph.spec(feature)
            XCTAssertFalse(spec.page.isEmpty, "\(feature) has no page")
            XCTAssertFalse(spec.requiresAll.contains(feature), "\(feature) requires itself")
            XCTAssertFalse(spec.requiresAny.contains(feature), "\(feature) requires itself")
        }
    }

    func testControllerMapIsTotal() {
        var covered: Set<DisplayControllerID> = []
        for feature in DisplayFeature.allCases {
            let c = FeatureGraph.controller(of: feature)
            covered.insert(c)
            XCTAssertTrue(FeatureGraph.features(of: c).contains(feature))
        }
        XCTAssertEqual(covered, Set(DisplayControllerID.allCases), "every controller id serves at least one feature")
    }

    func testActivationOrderCoversEveryServiceOnceAndRespectsDependencies() {
        let order = FeatureGraph.activationOrder
        XCTAssertEqual(order.count, Set(order).count)
        XCTAssertEqual(Set(order), Set(DisplayServiceID.allCases))
        for (index, service) in order.enumerated() {
            for dependency in FeatureGraph.dependencies(service) {
                let depIndex = order.firstIndex(of: dependency)
                XCTAssertNotNil(depIndex)
                XCTAssertLessThan(depIndex ?? Int.max, index, "\(dependency) must activate before \(service)")
            }
        }
    }

    func testRequiredServicesAreClosedOverDependencies() {
        let required = FeatureGraph.requiredServices(effective: all)
        for service in required {
            XCTAssertTrue(FeatureGraph.dependencies(service).isSubset(of: required))
        }
        XCTAssertTrue(FeatureGraph.requiredServices(effective: []).isEmpty)
    }

    func testDefaultsResolveToAClosedSet() {
        let effective = FeatureGraph.resolve(raw: [:], killSwitches: [], safeMode: false, unavailable: [], panicLatch: false)
        assertClosed(effective)
        XCTAssertTrue(effective.contains(.overview))
        XCTAssertTrue(effective.contains(.diagnostics))
        for feature in effective { XCTAssertTrue(FeatureGraph.isOnByDefault(feature), "\(feature) on without being default") }
    }

    func testAlwaysFeaturesCannotBeTurnedOff() {
        let raw: [DisplayFeature: Bool] = [.overview: false, .diagnostics: false]
        let effective = FeatureGraph.resolve(raw: raw, killSwitches: [], safeMode: false, unavailable: [], panicLatch: false)
        XCTAssertTrue(effective.isSuperset(of: [.overview, .diagnostics]))
    }

    func testSafeModeAndPanicRemovals() {
        var raw: [DisplayFeature: Bool] = [:]
        for f in DisplayFeature.allCases { raw[f] = true }
        let safe = FeatureGraph.resolve(raw: raw, killSwitches: [], safeMode: true, unavailable: [], panicLatch: false)
        XCTAssertTrue(safe.isDisjoint(with: FeatureGraph.safeModeRemoves))
        let latched = FeatureGraph.resolve(raw: raw, killSwitches: [], safeMode: false, unavailable: [], panicLatch: true)
        XCTAssertTrue(latched.isDisjoint(with: FeatureGraph.panicLatchRemoves))
        assertClosed(safe)
        assertClosed(latched)
    }

    func testKillSwitchesAndUnavailabilityPropagateToDependents() {
        var raw: [DisplayFeature: Bool] = [:]
        for f in DisplayFeature.allCases { raw[f] = true }
        let killed = FeatureGraph.resolve(raw: raw, killSwitches: [.resolution], safeMode: false, unavailable: [], panicLatch: false)
        XCTAssertFalse(killed.contains(.resolution))
        for f in killed { XCTAssertFalse(FeatureGraph.spec(f).requiresAll.contains(.resolution), "\(f) survived without resolution") }
        let noMethods = FeatureGraph.resolve(raw: raw, killSwitches: [], safeMode: false,
                                             unavailable: [.brightnessApple, .brightnessDDC, .brightnessGamma, .brightnessOverlay],
                                             panicLatch: false)
        XCTAssertFalse(noMethods.contains(.brightness), "brightness needs at least one method")
        assertClosed(noMethods)
    }

    func testEnablingTurnsOnRequirements() {
        for feature in DisplayFeature.allCases {
            let raw = FeatureGraph.enabling(feature, raw: [:], available: all)
            let effective = FeatureGraph.resolve(raw: raw, killSwitches: [], safeMode: false, unavailable: [], panicLatch: false)
            XCTAssertTrue(effective.contains(feature), "enabling \(feature) did not make it effective")
        }
    }

    func testDependentsAreThoseThatDropOut() {
        var raw: [DisplayFeature: Bool] = [:]
        for f in DisplayFeature.allCases { raw[f] = true }
        let effective = FeatureGraph.resolve(raw: raw, killSwitches: [], safeMode: false, unavailable: [], panicLatch: false)
        let deps = FeatureGraph.dependents(of: .resolution, effective: effective)
        XCTAssertFalse(deps.contains(.resolution))
        for d in deps { XCTAssertTrue(effective.contains(d)) }
    }

    /// 10,000 seeded random raw maps, kill switches and availability: the result is always
    /// closed under requirements and never contains removed features.
    func testRandomSubsetsResolveToClosedSets() {
        var rng = SeededGenerator(seed: 0x5EED)
        let features = DisplayFeature.allCases
        for _ in 0..<10_000 {
            var raw: [DisplayFeature: Bool] = [:]
            var kill: Set<DisplayFeature> = []
            var unavailable: Set<DisplayFeature> = []
            for f in features {
                switch rng.next() % 3 {
                case 0: raw[f] = true
                case 1: raw[f] = false
                default: break
                }
                if rng.next() % 20 == 0 { kill.insert(f) }
                if rng.next() % 20 == 0 { unavailable.insert(f) }
            }
            let safe = rng.next() % 4 == 0
            let latched = rng.next() % 4 == 0
            let effective = FeatureGraph.resolve(raw: raw, killSwitches: kill, safeMode: safe,
                                                 unavailable: unavailable, panicLatch: latched)
            assertClosed(effective)
            XCTAssertTrue(effective.isDisjoint(with: kill))
            XCTAssertTrue(effective.isDisjoint(with: unavailable))
            if safe { XCTAssertTrue(effective.isDisjoint(with: FeatureGraph.safeModeRemoves)) }
            if latched { XCTAssertTrue(effective.isDisjoint(with: FeatureGraph.panicLatchRemoves)) }
            // Idempotent: resolving the result again changes nothing.
            var again: [DisplayFeature: Bool] = [:]
            for f in features { again[f] = effective.contains(f) }
            XCTAssertEqual(FeatureGraph.resolve(raw: again, killSwitches: kill, safeMode: safe,
                                                unavailable: unavailable, panicLatch: latched), effective)
        }
    }

    private func assertClosed(_ set: Set<DisplayFeature>, file: StaticString = #filePath, line: UInt = #line) {
        for feature in set {
            let spec = FeatureGraph.spec(feature)
            for r in spec.requiresAll {
                XCTAssertTrue(set.contains(r), "\(feature) is effective without \(r)", file: file, line: line)
            }
            if !spec.requiresAny.isEmpty {
                XCTAssertTrue(spec.requiresAny.contains { set.contains($0) }, "\(feature) has none of its methods",
                              file: file, line: line)
            }
        }
    }
}

/// SplitMix64, so the fuzz run is identical on every platform.
struct SeededGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
