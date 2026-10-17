import XCTest
@testable import SnapticKit

final class ConfigResolutionTests: XCTestCase {
    private func mode(_ w: Int, _ h: Int, hiDPI: Bool = true, hz: Int = 60_000, id: Int32 = 1) -> ModeRef {
        ModeRef(ioModeID: id, pixelWidth: hiDPI ? w * 2 : w, pixelHeight: hiDPI ? h * 2 : h, pointWidth: w, pointHeight: h,
                refreshMilliHz: hz)
    }

    func testDefaultsRoundTrip() throws {
        let c = ResolutionConfig()
        XCTAssertEqual(c.confirm, .newModesOnly)
        XCTAssertFalse(c.allowBelow720p)
        XCTAssertTrue(c.persistedChoice)
        XCTAssertEqual(try JSONDecoder().decode(ResolutionConfig.self, from: JSONEncoder().encode(c)), c)
        XCTAssertEqual(try JSONDecoder().decode(ResolutionConfig.self, from: Data("{}".utf8)), c)
        let p = PerDisplayResolution()
        XCTAssertEqual(try JSONDecoder().decode(PerDisplayResolution.self, from: JSONEncoder().encode(p)), p)
    }

    func testLossyFields() throws {
        let json = #"{"confirm":"sometimes","allowBelow720p":true,"scaleMatchTolerance":"x","sliderLabel":"percent"}"#
        let c = try JSONDecoder().decode(ResolutionConfig.self, from: Data(json.utf8))
        XCTAssertEqual(c.confirm, .newModesOnly)
        XCTAssertTrue(c.allowBelow720p)
        XCTAssertEqual(c.scaleMatchTolerance, 0.10)
        XCTAssertEqual(c.sliderLabel, .percent)
    }

    func testSanitizeClamps() {
        var c = ResolutionConfig()
        c.scaleMatchTolerance = 9
        XCTAssertEqual(c.sanitized().scaleMatchTolerance, 0.5)
        c.scaleMatchTolerance = .nan
        XCTAssertEqual(c.sanitized().scaleMatchTolerance, 0.10)

        var p = PerDisplayResolution()
        p.favorites = (0..<9).map { FavoriteMode(width: 1000 + $0, height: 800, hiDPI: true, refreshMilliHz: 60_000) }
            + [FavoriteMode(width: -1, height: 1, hiDPI: false, refreshMilliHz: 0)]
        p.favorites.insert(p.favorites[0], at: 1)
        p.minWidth = 5000
        p.maxWidth = 100
        p.refreshFilter = -3
        p.bitDepthFilter = 7
        let s = p.sanitized()
        XCTAssertEqual(s.favorites.count, PerDisplayResolution.maxFavorites)
        XCTAssertEqual(Set(s.favorites).count, s.favorites.count)
        XCTAssertEqual(s.minWidth, 320)
        XCTAssertEqual(s.maxWidth, 5000)
        XCTAssertNil(s.refreshFilter)
        XCTAssertNil(s.bitDepthFilter)
        XCTAssertEqual(s.sanitized(), s)
    }

    func testFavoriteResolve() {
        let modes = [mode(1512, 982, hz: 120_000), mode(1512, 982, hiDPI: false), mode(1800, 1169)]
        let fav = FavoriteMode(mode(1512, 982, hz: 119_880))
        XCTAssertEqual(fav.resolve(in: modes), mode(1512, 982, hz: 120_000))
        XCTAssertNil(FavoriteMode(width: 1512, height: 982, hiDPI: true, refreshMilliHz: 60_000).resolve(in: modes))
        XCTAssertEqual(FavoriteMode(width: 1512, height: 982, hiDPI: false, refreshMilliHz: 0).resolve(in: modes),
                       mode(1512, 982, hiDPI: false))
        XCTAssertEqual(fav.label, "1512 × 982 HiDPI")
    }

    func testRange() {
        var p = PerDisplayResolution()
        p.minWidth = 1000
        p.maxWidth = 2000
        XCTAssertTrue(p.inRange(mode(1512, 982)))
        XCTAssertFalse(p.inRange(mode(800, 600)))
        XCTAssertFalse(p.inRange(mode(2560, 1440)))
        XCTAssertTrue(PerDisplayResolution().inRange(mode(10, 10)))
    }

    func testPersistedChoiceDecode() throws {
        var p = PerDisplayResolution()
        p.persisted = PersistedModeChoice(mode: mode(1920, 1080), preKeepMode: mode(2560, 1440), recordedAt: 5)
        let back = try JSONDecoder().decode(PerDisplayResolution.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.persisted, p.persisted)
        p.persisted = PersistedModeChoice(mode: mode(0, 0), preKeepMode: mode(2560, 1440), recordedAt: 5)
        XCTAssertNil(p.sanitized().persisted)
    }
}
