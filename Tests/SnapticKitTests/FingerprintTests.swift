import XCTest
@testable import SnapticKit

final class FingerprintTests: XCTestCase {
    private let full = DisplayIdentityFacts(edidHash: "ABCDEF0123456789", alphanumericSerial: " cn0abc123 ",
                                            uuid: "1234-abcd", vendor: 4268, model: 41234, serial: 1234,
                                            location: "IOService:/AppleARMPE/dispext0", isBuiltin: false)

    func testCanonicalTiers() {
        let c = Fingerprint.canonical(full)
        XCTAssertEqual(c[.edidSerial], "t1|abcdef0123456789|CN0ABC123")
        XCTAssertEqual(c[.uuid], "t2|1234-ABCD")
        XCTAssertEqual(c[.vendorModelSerial], "t3|4268:41234:1234")
        XCTAssertEqual(c[.location], "t4|4268:41234|IOService:/AppleARMPE/dispext0")
        XCTAssertEqual(c[.vendorModel], "t5|4268:41234|external")
        XCTAssertEqual(Fingerprint.bestTier(full), .edidSerial)
    }

    func testPlaceholderSerialsDontCount() {
        var f = full
        f.alphanumericSerial = "0000000"
        f.serial = 0x0101_0101
        let c = Fingerprint.canonical(f)
        XCTAssertNil(c[.edidSerial])
        XCTAssertNil(c[.vendorModelSerial])
        XCTAssertEqual(Fingerprint.bestTier(f), .uuid)
        XCTAssertEqual(Fingerprint.bestTier(DisplayIdentityFacts(vendor: 1, model: 2)), .vendorModel)
    }

    private func key(_ c: Character) -> DisplayKey { DisplayKey(rawValue: String(repeating: c, count: 32))! }
    private let h1 = String(repeating: "1", count: 32), h2 = String(repeating: "2", count: 32)
    private let h3 = String(repeating: "3", count: 32), h4 = String(repeating: "4", count: 32)

    func testMatchByHighestTierAndConflicts() {
        let stored: [DisplayKey: FingerprintRecord] = [
            key("a"): FingerprintRecord(t1: h1, t2: h2),
            key("b"): FingerprintRecord(t2: h3, t4: h4),
        ]
        XCTAssertEqual(Fingerprint.match(FingerprintRecord(t1: h1), in: stored), key("a"))
        XCTAssertEqual(Fingerprint.match(FingerprintRecord(t2: h2), in: stored), key("a"), "UUID when no serial")
        // Same UUID but a different EDID+serial: a different (identical-model) monitor.
        XCTAssertNil(Fingerprint.match(FingerprintRecord(t1: h4, t2: h2), in: stored))
        XCTAssertEqual(Fingerprint.match(FingerprintRecord(t4: h4), in: stored), key("b"))
        XCTAssertNil(Fingerprint.match(FingerprintRecord(t5: h1), in: stored))
        // Two candidates at a weak tier: ambiguous.
        let twins: [DisplayKey: FingerprintRecord] = [key("a"): FingerprintRecord(t5: h1), key("b"): FingerprintRecord(t5: h1)]
        XCTAssertNil(Fingerprint.match(FingerprintRecord(t5: h1), in: twins))
    }

    func testKeyAndHex() {
        let digest = (0..<32).map { UInt8($0) }
        XCTAssertEqual(Fingerprint.key(fromDigest: digest)?.rawValue, "000102030405060708090a0b0c0d0e0f")
        XCTAssertNil(Fingerprint.key(fromDigest: [1, 2, 3]))
        XCTAssertEqual(Fingerprint.hex([0xAB, 0x01]), "ab01")
        XCTAssertTrue(Fingerprint.isHexDigest(h1))
        XCTAssertFalse(Fingerprint.isHexDigest("XYZ"))
    }

    func testRecordDecodingDropsNonHex() throws {
        let json = #"{"t1":"\#(h1)","t2":"not hex!","t3":42}"#
        let r = try JSONDecoder().decode(FingerprintRecord.self, from: Data(json.utf8))
        XCTAssertEqual(r.t1, h1)
        XCTAssertNil(r.t2)
        XCTAssertNil(r.t3)
        XCTAssertEqual(r.bestTier, .edidSerial)
        XCTAssertTrue(FingerprintRecord().isEmpty)
    }

    func testSessionFingerprintAndMask() {
        XCTAssertEqual(Fingerprint.sessionFingerprint(uuid: "ab-cd", vendor: 1, model: 2, serial: 3), "uuid:AB-CD")
        XCTAssertEqual(Fingerprint.sessionFingerprint(uuid: nil, vendor: 1, model: 2, serial: 3), "vms:1:2:3")
        XCTAssertEqual(Fingerprint.masked("CN0ABC1234"), "••••1234")
        XCTAssertEqual(Fingerprint.masked("12"), "••")
    }

    // MARK: matches(_:_:) (pairwise, 0.3)

    private let h5 = String(repeating: "5", count: 32), h6 = String(repeating: "6", count: 32)

    func testMatchesComparesOnlySharedTiers() {
        // Stored by Displays with every tier; live from CG facts (t2, t3, t5 only).
        let stored = FingerprintRecord(t1: h1, t2: h2, t3: h3, t4: h4, t5: h5)
        XCTAssertTrue(Fingerprint.matches(stored, FingerprintRecord(t2: h2, t3: h3, t5: h5)))
        // t1 and t4 can't be computed live: absent there, never a conflict.
        XCTAssertTrue(Fingerprint.matches(stored, FingerprintRecord(t2: h2)))
        XCTAssertTrue(Fingerprint.matches(FingerprintRecord(t1: h1, t5: h5), FingerprintRecord(t2: h2, t5: h5)))
    }

    func testMatchesMostSpecificSharedTierDecides() {
        let stored = FingerprintRecord(t2: h2, t3: h3, t5: h5)
        // Same model (t5) but another UUID: an identical second monitor.
        XCTAssertFalse(Fingerprint.matches(stored, FingerprintRecord(t2: h6, t3: h3, t5: h5)))
        // Same UUID, different serial: the UUID is the more specific tier and decides.
        XCTAssertTrue(Fingerprint.matches(stored, FingerprintRecord(t2: h2, t3: h6, t5: h6)))
        // No UUID live (placeholder): serial decides.
        XCTAssertTrue(Fingerprint.matches(stored, FingerprintRecord(t3: h3, t5: h5)))
        XCTAssertFalse(Fingerprint.matches(stored, FingerprintRecord(t3: h6, t5: h5)))
        // Only the model is shared.
        XCTAssertTrue(Fingerprint.matches(FingerprintRecord(t5: h5), FingerprintRecord(t2: h2, t5: h5)))
        XCTAssertFalse(Fingerprint.matches(FingerprintRecord(t5: h5), FingerprintRecord(t5: h6)))
    }

    func testMatchesNeedsASharedTier() {
        XCTAssertFalse(Fingerprint.matches(FingerprintRecord(), FingerprintRecord()))
        XCTAssertFalse(Fingerprint.matches(FingerprintRecord(t1: h1), FingerprintRecord()))
        XCTAssertFalse(Fingerprint.matches(FingerprintRecord(t1: h1, t4: h4), FingerprintRecord(t2: h2, t3: h3, t5: h5)))
    }

    func testMatchesFuzzAgreesWithMatchAndIsSymmetric() {
        var rng = SeededGenerator(seed: 0xF1A6)
        let pool = [h1, h2, h3]
        func record() -> FingerprintRecord {
            var r = FingerprintRecord()
            for tier in FingerprintTier.allCases where rng.next() % 2 == 0 {
                r[tier] = pool[Int(rng.next() % UInt64(pool.count))]
            }
            return r
        }
        for _ in 0..<2_000 {
            let a = record(), b = record()
            XCTAssertEqual(Fingerprint.matches(a, b), Fingerprint.matches(b, a))
            XCTAssertEqual(Fingerprint.matches(a, a), !a.isEmpty)
            // With one stored display, uniqueness always holds, so the map-based matcher must agree.
            let viaMap = Fingerprint.match(b, in: [key("a"): a]) == key("a")
            XCTAssertEqual(Fingerprint.matches(a, b), viaMap, "\(a) vs \(b)")
        }
    }
}
