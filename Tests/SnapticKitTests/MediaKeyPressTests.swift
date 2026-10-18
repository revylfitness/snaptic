import XCTest
@testable import SnapticKit

final class MediaKeyPressTests: XCTestCase {
    private func data1(code: Int, state: Int, repeat isRepeat: Bool = false) -> Int {
        (code << 16) | (state << 8) | (isRepeat ? 1 : 0)
    }

    func testParsesKeysStatesAndRepeat() {
        XCTAssertEqual(MediaKeyPress.parse(subtype: 8, data1: data1(code: 2, state: 0xA)),
                       MediaKeyPress(key: .brightnessUp, isDown: true, isRepeat: false))
        XCTAssertEqual(MediaKeyPress.parse(subtype: 8, data1: data1(code: 3, state: 0xB)),
                       MediaKeyPress(key: .brightnessDown, isDown: false, isRepeat: false))
        XCTAssertEqual(MediaKeyPress.parse(subtype: 8, data1: data1(code: 0, state: 0xA, repeat: true)),
                       MediaKeyPress(key: .volumeUp, isDown: true, isRepeat: true))
        XCTAssertEqual(MediaKeyPress.parse(subtype: 8, data1: data1(code: 1, state: 0xA))?.key, .volumeDown)
        XCTAssertEqual(MediaKeyPress.parse(subtype: 8, data1: data1(code: 7, state: 0xA))?.key, .mute)
    }

    func testRejectsOtherSubtypesKeysAndStates() {
        XCTAssertNil(MediaKeyPress.parse(subtype: 7, data1: data1(code: 2, state: 0xA)))
        XCTAssertNil(MediaKeyPress.parse(subtype: 8, data1: data1(code: 16, state: 0xA)), "play/pause is not ours")
        XCTAssertNil(MediaKeyPress.parse(subtype: 8, data1: data1(code: 2, state: 0x0)))
        XCTAssertNil(MediaKeyPress.parse(subtype: 8, data1: 0))
        XCTAssertNil(MediaKeyPress.parse(subtype: 8, data1: -1))
    }

    func testFuzzNeverTrapsAndOnlyKnownKeys() {
        var rng = SeededGenerator(seed: 0x4B455953)
        for _ in 0..<5_000 {
            let raw = Int(truncatingIfNeeded: rng.next())
            if let p = MediaKeyPress.parse(subtype: 8, data1: raw) {
                XCTAssertNotNil(MediaKeyPress.key(forCode: (raw & 0xFFFF_0000) >> 16))
                XCTAssertEqual(p.isDown, (raw & 0xFF00) >> 8 == 0xA)
            }
        }
    }

    func testNoticeShowsOnceForAnActingPressWhileUntrusted() {
        let down = MediaKeyPress(key: .brightnessUp, isDown: true, isRepeat: false)
        var notice = UntrustedKeyNotice()
        XCTAssertTrue(notice.wantsPresses(trusted: false))
        XCTAssertFalse(notice.shouldShow(down, trusted: true, wouldAct: true), "trusted: the tap handles it")
        XCTAssertFalse(notice.shouldShow(down, trusted: false, wouldAct: false), "macOS keeps this press anyway")
        XCTAssertFalse(notice.shouldShow(MediaKeyPress(key: .brightnessUp, isDown: false, isRepeat: false),
                                         trusted: false, wouldAct: true), "key-up")
        XCTAssertFalse(notice.shouldShow(MediaKeyPress(key: .brightnessUp, isDown: true, isRepeat: true),
                                         trusted: false, wouldAct: true), "repeat")
        XCTAssertTrue(notice.shouldShow(down, trusted: false, wouldAct: true))
        XCTAssertFalse(notice.shouldShow(down, trusted: false, wouldAct: true), "one time only")
        XCTAssertFalse(notice.wantsPresses(trusted: false))
        XCTAssertFalse(UntrustedKeyNotice().wantsPresses(trusted: true))
    }
}
