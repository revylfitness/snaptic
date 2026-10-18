import XCTest
@testable import SnapticKit

final class VCPPolicyTests: XCTestCase {
    private func tier(_ code: UInt8, _ value: UInt16 = 1, caps: DDCCapabilities? = nil) -> VCPTier {
        VCPPolicy.tier(code: code, value: value, capabilities: caps)
    }

    func testSafeTier() {
        for code: UInt8 in [0x10, 0x12, 0x13, 0x6B, 0x16, 0x18, 0x1A, 0x6C, 0x6E, 0x70, 0x62, 0x87, 0x8A] {
            XCTAssertEqual(tier(code, 50), .safe, VCPPolicy.hex(code))
        }
        XCTAssertEqual(tier(0x14, 0x05), .safe)
        XCTAssertEqual(tier(0x14, 0x0B), .safe)
    }

    func testColorPresetValuesFromCapsOrKnownList() {
        XCTAssertEqual(tier(0x14, 0x0E), .denied, "outside the known list")
        var caps = DDCCapabilities()
        caps.vcp[0x14] = [0x05, 0x08]
        XCTAssertEqual(tier(0x14, 0x05, caps: caps), .safe)
        XCTAssertEqual(tier(0x14, 0x0B, caps: caps), .denied, "caps narrow the list")
        caps.vcp[0x14] = []
        XCTAssertEqual(tier(0x14, 0x0B, caps: caps), .safe, "empty caps list falls back to the known list")
    }

    func testDisplayModeNeedsCaps() {
        XCTAssertEqual(tier(0xDC, 2), .denied)
        var caps = DDCCapabilities()
        caps.vcp[0xDC] = [0, 2, 3]
        XCTAssertEqual(tier(0xDC, 2, caps: caps), .safe)
        XCTAssertEqual(tier(0xDC, 5, caps: caps), .denied)
    }

    func testMuteBecomesPreConfirmWhenCapsSayScreenBlank() {
        XCTAssertEqual(tier(0x8D, 1), .safe)
        XCTAssertEqual(tier(0x8D, 2), .safe)
        XCTAssertEqual(tier(0x8D, 3), .preConfirm)
        var caps = DDCCapabilities()
        caps.vcp[0x8D] = [1, 2]
        XCTAssertEqual(tier(0x8D, 1, caps: caps), .safe)
        caps.vcp[0x8D] = [1, 2, 3, 4]
        XCTAssertEqual(tier(0x8D, 1, caps: caps), .preConfirm)
    }

    func testMuteValuesOutsideTheKnownOnesAreDenied() {
        for v: UInt16 in [0, 5, 0xFF, 0x0101, 0xFFFF] { XCTAssertEqual(tier(0x8D, v), .denied, "\(v)") }
        var caps = DDCCapabilities()
        caps.vcp[0x8D] = [1, 2, 3, 4, 5]
        XCTAssertEqual(tier(0x8D, 5, caps: caps), .denied, "caps never widen 0x8D")
        XCTAssertEqual(tier(0x8D, 4, caps: caps), .preConfirm)
    }

    func testPowerValues() {
        XCTAssertEqual(tier(0xD6, 1), .safe, "R5.8: power on is safe")
        for v: UInt16 in [2, 3, 4] { XCTAssertEqual(tier(0xD6, v), .preConfirm) }
        XCTAssertEqual(tier(0xD6, 5), .denied, "hard power-off can't be woken over DDC")
        XCTAssertEqual(tier(0xD6, 0), .denied)
        XCTAssertEqual(tier(0xD6, 6), .denied)
    }

    func testPreConfirmTier() {
        for code: UInt8 in [0x60, 0xF4, 0xE7, 0xE8, 0xE9, 0xF3] {
            XCTAssertEqual(tier(code, 0x0F), .preConfirm, VCPPolicy.hex(code))
            XCTAssertTrue(tier(code, 0x0F).needsConfirmation)
            XCTAssertFalse(tier(code, 0x0F).allowsAutomatic)
        }
    }

    func testUnlockableTier() {
        for code in 0xE0...0xFF {
            let c = UInt8(code)
            let expected: VCPTier = [0xE7, 0xE8, 0xE9, 0xF3, 0xF4].contains(c) ? .preConfirm : .unlockable
            XCTAssertEqual(tier(c, 1), expected, VCPPolicy.hex(c))
        }
    }

    func testDeniedTier() {
        for code: UInt8 in [0x01, 0x04, 0x05, 0x06, 0x08, 0x0A, 0xB0, 0xCA, 0xCC] {
            XCTAssertEqual(tier(code, 1), .denied, VCPPolicy.hex(code))
        }
        for code: UInt8 in [0x00, 0x02, 0x0B, 0x0C, 0x11, 0x20, 0x52, 0x72, 0xAA, 0xC0, 0xDF] {
            XCTAssertEqual(tier(code, 1), .denied, "anything else is denied: \(VCPPolicy.hex(code))")
        }
    }

    func testEveryCodeHasExactlyOneTierAndOnlySafeIsAutomatic() {
        var rng = SeededGenerator(seed: 0x7E1)
        for code in 0...255 {
            for _ in 0..<8 {
                let t = tier(UInt8(code), UInt16(truncatingIfNeeded: rng.next()))
                XCTAssertEqual(t.allowsAutomatic, t == .safe)
                XCTAssertEqual(t.needsConfirmation, t == .preConfirm || t == .unlockable)
            }
        }
    }

    func testAllowKeys() {
        XCTAssertEqual(VCPPolicy.allowKey(code: 0x60, value: 0x0F), "60:000F")
        XCTAssertTrue(VCPPolicy.isValidAllowKey("60:000F"))
        XCTAssertFalse(VCPPolicy.isValidAllowKey("60:0f"))
        XCTAssertFalse(VCPPolicy.isValidAllowKey("60:000f"))
        XCTAssertFalse(VCPPolicy.isValidAllowKey("6:000F"))
        XCTAssertFalse(VCPPolicy.isValidAllowKey("60000F"))
        XCTAssertFalse(VCPPolicy.isValidAllowKey("ZZ:000F"))
    }

    func testHexHelpers() {
        XCTAssertEqual(VCPPolicy.hex(0x0A), "0A")
        XCTAssertEqual(VCPPolicy.parseCode("0x10"), 0x10)
        XCTAssertEqual(VCPPolicy.parseCode("d6"), 0xD6)
        XCTAssertEqual(VCPPolicy.parseCode("62h"), 0x62)
        XCTAssertNil(VCPPolicy.parseCode("100"))
        XCTAssertNil(VCPPolicy.parseCode(""))
        XCTAssertEqual(VCPPolicy.inputName(0x11), "HDMI 1")
        XCTAssertEqual(VCPPolicy.name(0x10), "Brightness")
    }

    // MARK: Shim backstop (SNDDC.m repeats this table in C)

    private let sampleValues: [UInt16] = [0, 1, 2, 3, 4, 5, 6, 0x0B, 0x0D, 0x0E, 0x0F, 0x11, 0x7F, 0xFF, 0x100, 0x0101, 0x8000, 0xFFFF]

    func testBackstopNeverRefusesWhatThePolicyAllows() {
        var rng = SeededGenerator(seed: 0xBAC5)
        for code in 0...255 {
            let c = UInt8(code)
            let values = sampleValues + (0..<16).map { _ in UInt16(truncatingIfNeeded: rng.next()) }
            for v in values {
                let policy = tier(c, v)
                let backstop = VCPPolicy.backstopTier(code: c, value: v)
                let label = "\(VCPPolicy.hex(c)) = \(v)"
                if policy == .safe { XCTAssertTrue(VCPPolicy.backstopAllows(code: c, value: v, confirmed: false), label) }
                if policy != .denied { XCTAssertTrue(VCPPolicy.backstopAllows(code: c, value: v, confirmed: true), label) }
                if policy.needsConfirmation {
                    XCTAssertFalse(VCPPolicy.backstopAllows(code: c, value: v, confirmed: false), "unconfirmed \(label)")
                }
                if policy == .denied, c != VCPPolicy.colorPreset, c != VCPPolicy.displayMode {
                    XCTAssertEqual(backstop, .denied, label)
                }
            }
        }
    }

    func testBackstopAllowsCapabilityListedValuesWithinOneByte() {
        var caps = DDCCapabilities()
        caps.vcp[0x14] = [0x05, 0x20]
        caps.vcp[0xDC] = [0x00, 0x07]
        let pairs: [(UInt8, UInt16)] = [(0x14, 0x20), (0xDC, 0x07), (0xDC, 0x00)]
        for (code, value) in pairs {
            XCTAssertEqual(tier(code, value, caps: caps), .safe)
            XCTAssertTrue(VCPPolicy.backstopAllows(code: code, value: value, confirmed: false))
        }
        XCTAssertFalse(VCPPolicy.backstopAllows(code: 0x14, value: 0x100, confirmed: true))
        XCTAssertFalse(VCPPolicy.backstopAllows(code: 0xDC, value: 0xFFFF, confirmed: true))
    }

    func testBackstopManufacturerCodesNeedConfirmation() {
        for code in 0xE0...0xFF {
            let c = UInt8(code)
            XCTAssertFalse(VCPPolicy.backstopAllows(code: c, value: 1, confirmed: false), VCPPolicy.hex(c))
            XCTAssertTrue(VCPPolicy.backstopAllows(code: c, value: 1, confirmed: true), VCPPolicy.hex(c))
        }
    }

    func testBackstopPowerAndMute() {
        XCTAssertTrue(VCPPolicy.backstopAllows(code: 0xD6, value: 1, confirmed: false))
        for v: UInt16 in 2...4 {
            XCTAssertFalse(VCPPolicy.backstopAllows(code: 0xD6, value: v, confirmed: false))
            XCTAssertTrue(VCPPolicy.backstopAllows(code: 0xD6, value: v, confirmed: true))
        }
        for v: UInt16 in [0, 5, 0x0101] { XCTAssertFalse(VCPPolicy.backstopAllows(code: 0xD6, value: v, confirmed: true)) }
        XCTAssertTrue(VCPPolicy.backstopAllows(code: 0x8D, value: 1, confirmed: false))
        XCTAssertTrue(VCPPolicy.backstopAllows(code: 0x8D, value: 2, confirmed: false))
        XCTAssertFalse(VCPPolicy.backstopAllows(code: 0x8D, value: 3, confirmed: false))
        XCTAssertTrue(VCPPolicy.backstopAllows(code: 0x8D, value: 3, confirmed: true))
        for v: UInt16 in [0, 5, 0x0101] { XCTAssertFalse(VCPPolicy.backstopAllows(code: 0x8D, value: v, confirmed: true)) }
        XCTAssertFalse(VCPPolicy.backstopAllows(code: 0x60, value: 0x0F, confirmed: false), "input switches need confirmation")
        XCTAssertTrue(VCPPolicy.backstopAllows(code: 0x60, value: 0x0F, confirmed: true))
    }
}
