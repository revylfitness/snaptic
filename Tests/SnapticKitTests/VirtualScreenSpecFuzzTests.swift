import XCTest
@testable import SnapticKit

/// Seeded fuzz of the virtual-screen parser (review 4 code F3/F5): `VirtualConfig` and `VirtualScreenSpec` decode
/// values another process or a backup can write. A mutated document never traps, always decodes (lossy), and
/// `sanitized(soc:)` lands inside the documented limits and is idempotent.
final class VirtualScreenSpecFuzzTests: XCTestCase {
    private func key(_ c: Character) -> DisplayKey { DisplayKey(rawValue: String(repeating: c, count: 32))! }

    /// A valid document with every field populated.
    private func baseDocument() throws -> Any {
        var c = VirtualConfig()
        var portrait = Recipes.spec(for: .portrait)
        portrait.associations = [VirtualAssociation(target: key("a"), presentation: .mirror),
                                 VirtualAssociation(target: key("b"), autoConnect: .whileAbsent)]
        portrait.primaries = .displayP3
        c.screens = [Recipes.spec(for: .recording), Recipes.spec(for: .headless), portrait]
        c.connected = LossyMap([c.screens[0].id: true])
        c.lastOrigins = LossyMap([c.screens[2].id: VirtualOrigin(x: -1200, y: 300)])
        c.smartHiDPI = LossyMap([key("c"): SmartHiDPIPair(mode: VirtualMode(width: 1920, height: 1080, hiDPI: true))])
        return try JSONSerialization.jsonObject(with: JSONEncoder().encode(c))
    }

    func testSeededMutationsNeverTrapAndSanitizeIdempotently() throws {
        let base = try baseDocument()
        var fuzz = JSONFuzzer(seed: 0x5EED_D003)
        var decodedCount = 0
        for round in 0..<600 {
            var doc = base
            for _ in 0..<(1 + fuzz.int(6)) { doc = fuzz.mutate(doc, depth: 0) }
            guard JSONSerialization.isValidJSONObject(doc),
                  let data = try? JSONSerialization.data(withJSONObject: doc) else { continue }
            // Every object decodes (each field is lossy); only a non-object root may throw.
            guard let decoded = try? JSONDecoder().decode(VirtualConfig.self, from: data) else {
                XCTAssertFalse(doc is [String: Any], "round \(round): an object root must decode")
                continue
            }
            decodedCount += 1
            let soc = SoCClass.allCases[fuzz.int(SoCClass.allCases.count)]
            // Derived values on the unsanitized decode never trap (hostile sizes saturate).
            _ = decoded.totalBackingBytes
            for spec in decoded.screens {
                _ = spec.largestMode
                _ = spec.maxPixels
                _ = spec.fallbackMaxPixels
                _ = spec.estimatedBackingBytes
                _ = spec.sizeInMillimeters
                _ = spec.modesLimited(toInitial: true)
                _ = VirtualSpecEdit.fillingSizes(spec, soc: soc)
            }
            let s = decoded.sanitized(soc: soc)
            XCTAssertEqual(s.sanitized(soc: soc), s, "round \(round): sanitized is idempotent")
            assertWithinLimits(s, soc: soc, round: round)
            let again = try JSONDecoder().decode(VirtualConfig.self, from: JSONEncoder().encode(s))
            XCTAssertEqual(again, s, "round \(round): a sanitized config round-trips")
        }
        XCTAssertGreaterThan(decodedCount, 300)
    }

    private func assertWithinLimits(_ c: VirtualConfig, soc: SoCClass, round: Int) {
        XCTAssertLessThanOrEqual(c.screens.count, VirtualConfig.maxScreens)
        XCTAssertEqual(Set(c.screens.map(\.id)).count, c.screens.count, "round \(round)")
        let limit = SoCCaps.maxBackingDimension(soc)
        for s in c.screens {
            XCTAssertFalse(s.name.isEmpty)
            XCTAssertLessThanOrEqual(s.name.unicodeScalars.count, VirtualScreenSpec.maxNameScalars)
            XCTAssertTrue((1...VirtualScreenSpec.maxAspectComponent).contains(s.aspectWidth))
            XCTAssertTrue((1...VirtualScreenSpec.maxAspectComponent).contains(s.aspectHeight))
            XCTAssertTrue(s.sizeInches.isFinite)
            XCTAssertTrue((VirtualScreenSpec.minSizeInches...VirtualScreenSpec.maxSizeInches).contains(s.sizeInches))
            XCTAssertFalse(s.modes.isEmpty, "round \(round): a screen always has a mode")
            XCTAssertLessThanOrEqual(s.modes.count, s.hiDPI ? VirtualScreenSpec.maxModesHiDPI : VirtualScreenSpec.maxModesLoDPI)
            XCTAssertEqual(Set(s.modes).count, s.modes.count)
            for m in s.modes {
                XCTAssertGreaterThanOrEqual(min(m.width, m.height), VirtualScreenSpec.minModeDimension)
                XCTAssertLessThanOrEqual(max(m.pixelWidth, m.pixelHeight), limit)
                XCTAssertTrue((VirtualScreenSpec.minRefreshMilliHz...VirtualScreenSpec.maxRefreshMilliHz).contains(m.refreshMilliHz))
                XCTAssertTrue(!m.hiDPI || s.hiDPI)
            }
            XCTAssertLessThanOrEqual(s.associations.count, 8)
            XCTAssertEqual(Set(s.associations.map(\.target)).count, s.associations.count)
            XCTAssertTrue(s.primaries?.isPlausible ?? true)
            XCTAssertGreaterThan(s.estimatedBackingBytes, 0)
        }
        let live = Set(c.screens.map(\.id))
        XCTAssertTrue(c.connected.values.keys.allSatisfy { live.contains($0) })
        XCTAssertTrue(c.lastOrigins.values.keys.allSatisfy { live.contains($0) })
        XCTAssertTrue(c.lastOrigins.values.values.allSatisfy { $0 == $0.clamped })
        XCTAssertLessThanOrEqual(c.smartHiDPI.values.count, VirtualConfig.maxPairs)
        for p in c.smartHiDPI.values.values {
            XCTAssertTrue(p.mode.hiDPI)
            XCTAssertLessThanOrEqual(max(p.mode.width, p.mode.height), SoCCaps.maxHiDPIPointDimension(soc))
            XCTAssertFalse(live.contains(p.specID))
        }
    }

    // MARK: Pinned cases the fuzz found classes of

    func testHostileSizesSaturateInsteadOfTrapping() throws {
        let json = """
        {"id":"6F1C3F9A-1D2B-4C5E-8F70-112233445566","aspectWidth":\(Int.max),"aspectHeight":\(Int.max),"hiDPI":true,
         "modes":[{"width":\(Int.max),"height":\(Int.max),"hiDPI":true,"refreshMilliHz":\(Int.min)},
                  {"width":"wide","height":1080,"hiDPI":true},
                  {"width":1920,"height":1080,"hiDPI":true,"refreshMilliHz":60000}]}
        """
        let spec = try JSONDecoder().decode(VirtualScreenSpec.self, from: Data(json.utf8))
        // Element-wise: the malformed mode is dropped, the hostile and the good ones kept until sanitize.
        XCTAssertEqual(spec.modes.count, 2)
        XCTAssertEqual(spec.modes[0].pixelWidth, Int.max)
        XCTAssertEqual(spec.maxPixels.wide, Int.max)
        XCTAssertEqual(spec.estimatedBackingBytes, UInt64.max)
        XCTAssertEqual(VirtualMode.doubled(Int.min), Int.min)
        XCTAssertEqual(VirtualMode.doubled(21), 42)
        XCTAssertFalse(VirtualScreenSpec.ladder(aspectWidth: Int.max, aspectHeight: 1, hiDPI: true).isEmpty)
        XCTAssertFalse(VirtualScreenSpec.ladder(aspectWidth: 1, aspectHeight: Int.max, hiDPI: false).isEmpty)
        let s = spec.sanitized(soc: .appleEntry)
        XCTAssertEqual(s.modes, [VirtualMode(width: 1920, height: 1080, hiDPI: true, refreshMilliHz: 60_000)])
        XCTAssertEqual(s.aspectWidth, VirtualScreenSpec.maxAspectComponent)
        XCTAssertEqual(SoCCaps.backingBytes(pixelsWide: Int.max, pixelsHigh: 2), UInt64.max)
        var c = VirtualConfig()
        c.screens = [spec, spec]
        XCTAssertEqual(c.totalBackingBytes, UInt64.max)
    }

    func testLossyArraysStopAfterTheAttemptCap() throws {
        let good = String(decoding: try JSONEncoder().encode(Recipes.spec(for: .headless)), as: UTF8.self)
        let junk = Array(repeating: "7", count: LossyArray<VirtualScreenSpec>.maxElements).joined(separator: ",")
        // A good screen after the cap of malformed ones isn't read (attempts are bounded, not successes) ...
        let late = try JSONDecoder().decode(VirtualConfig.self, from: Data(#"{"screens":[\#(junk),\#(good)]}"#.utf8))
        XCTAssertTrue(late.screens.isEmpty)
        // ... one before it is.
        let early = try JSONDecoder().decode(VirtualConfig.self, from: Data(#"{"screens":[\#(good),\#(junk)]}"#.utf8))
        XCTAssertEqual(early.screens.count, 1)
    }
}

/// Mutates a JSONSerialization tree deterministically: drops, duplicates and replaces values with wrong types,
/// hostile numbers and strings, and deep nesting.
struct JSONFuzzer {
    private var rng: SeededGenerator

    init(seed: UInt64) { rng = SeededGenerator(seed: seed) }

    mutating func int(_ n: Int) -> Int { n <= 1 ? 0 : Int(rng.next() % UInt64(n)) }

    mutating func garbage(depth: Int) -> Any {
        switch int(depth > 3 ? 12 : 15) {
        case 0: return NSNull()
        case 1: return int(2) == 0
        case 2: return Int.max
        case 3: return Int.min
        case 4: return -int(100_000)
        case 5: return 1e300
        case 6: return "\u{202E}" + String(repeating: "x", count: int(300))
        case 7: return int(20_000)
        case 8: return 0.5
        case 9: return ["  ", "\u{0301}", "\u{FEFF}a ", String(repeating: "é", count: 70), "", "6F1C3F9A-1D2B-4C5E-8F70-112233445566"][int(6)]
        case 10: return String(repeating: "c", count: 32)
        case 11: return int(2) == 0 ? 160 : 6144
        case 12: return [garbage(depth: depth + 1), garbage(depth: depth + 1)]
        case 13: return nested(garbage(depth: depth + 1), depth: 1 + int(60))
        default: return ["width": garbage(depth: depth + 1), "height": garbage(depth: depth + 1), "hiDPI": int(2) == 0]
        }
    }

    func nested(_ value: Any, depth: Int) -> Any {
        var out = value
        for _ in 0..<depth { out = [out] }
        return out
    }

    mutating func mutate(_ value: Any, depth: Int) -> Any {
        if var d = value as? [String: Any], !d.isEmpty {
            let keys = d.keys.sorted()
            let k = keys[int(keys.count)]
            switch int(6) {
            case 0: d[k] = nil
            case 1: d[k] = garbage(depth: depth)
            case 2: d["unknown\(int(4))"] = garbage(depth: depth)
            default: d[k] = mutate(d[k] ?? NSNull(), depth: depth + 1)
            }
            return d
        }
        if var a = value as? [Any], !a.isEmpty {
            let i = int(a.count)
            switch int(6) {
            case 0: a.remove(at: i)
            case 1: a.insert(a[i], at: i)
            case 2: a[i] = garbage(depth: depth)
            case 3: a.append(contentsOf: Array(repeating: a[i], count: 1 + int(12)))
            default: a[i] = mutate(a[i], depth: depth + 1)
            }
            return a
        }
        return int(3) == 0 ? value : garbage(depth: depth)
    }
}
