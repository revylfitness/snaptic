import XCTest
@testable import SnapticKit

final class ConfigVirtualTests: XCTestCase {
    private func key(_ c: Character) -> DisplayKey { DisplayKey(rawValue: String(repeating: c, count: 32))! }

    func testDefaults() throws {
        let c = VirtualConfig()
        XCTAssertTrue(c.screens.isEmpty)
        XCTAssertTrue(c.restoreLayoutAfterConnect)
        XCTAssertFalse(c.disconnectOnLock)
        XCTAssertEqual(try JSONDecoder().decode(VirtualConfig.self, from: JSONEncoder().encode(c)), c)
        XCTAssertEqual(try JSONDecoder().decode(VirtualConfig.self, from: Data("{}".utf8)), c)
    }

    func testAtMostEightScreens() {
        var c = VirtualConfig()
        c.screens = (0..<12).map { _ in Recipes.spec(preset: Recipes.presets[0]) }
        c.screens.append(c.screens[0])  // duplicate id
        let s = c.sanitized()
        XCTAssertEqual(s.screens.count, VirtualConfig.maxScreens)
        XCTAssertEqual(Set(s.screens.map(\.id)).count, s.screens.count)
        XCTAssertEqual(s.sanitized(), s)
    }

    func testConnectedPrunedToKnownScreens() {
        var c = VirtualConfig()
        let spec = Recipes.spec(for: .headless)
        c.screens = [spec]
        c.connected = LossyMap([spec.id: true, StableID(): true])
        let s = c.sanitized()
        XCTAssertEqual(s.connected.values, [spec.id: true])
    }

    func testLastOriginsPrunedAndClamped() throws {
        var c = VirtualConfig()
        let spec = Recipes.spec(for: .portrait)
        c.screens = [spec]
        c.lastOrigins = LossyMap([spec.id: VirtualOrigin(x: 99_999, y: -99_999), StableID(): VirtualOrigin(x: 1, y: 2)])
        let s = c.sanitized()
        XCTAssertEqual(s.lastOrigins.values, [spec.id: VirtualOrigin(x: VirtualOrigin.limit, y: -VirtualOrigin.limit)])
        XCTAssertEqual(s.sanitized(), s)
        // Round trip, and a bad entry doesn't take the rest down.
        XCTAssertEqual(try JSONDecoder().decode(VirtualConfig.self, from: JSONEncoder().encode(s)), s)
        let json = #"{"lastOrigins":{"\#(spec.id.rawValue)":{"x":10,"y":"oops"}},"disconnectOnLock":true}"#
        let decoded = try JSONDecoder().decode(VirtualConfig.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.lastOrigins.values.isEmpty)
        XCTAssertTrue(decoded.disconnectOnLock)
    }

    func testSmartHiDPIPairsSanitized() {
        var c = VirtualConfig()
        c.smartHiDPI = LossyMap([
            key("a"): SmartHiDPIPair(mode: VirtualMode(width: 1920, height: 1080, hiDPI: false, refreshMilliHz: 1)),
            key("b"): SmartHiDPIPair(mode: VirtualMode(width: 5000, height: 3000, hiDPI: true)),
            key("c"): SmartHiDPIPair(mode: VirtualMode(width: 10, height: 10, hiDPI: true)),
        ])
        let s = c.sanitized(soc: .appleEntry)
        XCTAssertEqual(Set(s.smartHiDPI.values.keys), [key("a")])
        XCTAssertEqual(s.smartHiDPI[key("a")]?.mode, VirtualMode(width: 1920, height: 1080, hiDPI: true, refreshMilliHz: 24_000))
        // A pair can't reuse a user screen's id.
        var d = VirtualConfig()
        let spec = Recipes.spec(for: .portrait)
        d.screens = [spec]
        d.smartHiDPI = LossyMap([key("a"): SmartHiDPIPair(specID: spec.id, mode: VirtualMode(width: 1920, height: 1080, hiDPI: true))])
        XCTAssertTrue(d.sanitized().smartHiDPI.values.isEmpty)
    }

    func testLossyDecodeDropsBadScreens() throws {
        let good = Recipes.spec(for: .recording)
        let goodJSON = String(decoding: try JSONEncoder().encode(good), as: UTF8.self)
        let json = #"{"screens":[{"bad":1},"# + goodJSON + #",7],"disconnectOnLock":"yes","smartHiDPI":{"nothex":{}}}"#
        let c = try JSONDecoder().decode(VirtualConfig.self, from: Data(json.utf8))
        XCTAssertEqual(c.screens, [good])
        XCTAssertFalse(c.disconnectOnLock)
        XCTAssertTrue(c.smartHiDPI.values.isEmpty)
    }

    func testBacking() {
        var c = VirtualConfig()
        c.screens = [Recipes.spec(for: .headless), Recipes.spec(for: .recording)]
        XCTAssertEqual(c.totalBackingBytes, c.screens[0].estimatedBackingBytes + c.screens[1].estimatedBackingBytes)
        XCTAssertEqual(c.screen(c.screens[1].id), c.screens[1])
        XCTAssertNil(c.screen(StableID()))
    }
}
