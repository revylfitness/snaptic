import XCTest
@testable import SnapticKit

/// NetworkMath (PLAN 0.3 §2.8, §6.6).
final class NetworkMathTests: XCTestCase {
    // MARK: Addresses

    func testIPv4Parsing() {
        XCTAssertEqual(NetworkMath.parseAddress("10.0.0.1"), [10, 0, 0, 1])
        XCTAssertEqual(NetworkMath.parseAddress("255.255.255.255"), [255, 255, 255, 255])
        XCTAssertEqual(NetworkMath.parseAddress("0.0.0.0"), [0, 0, 0, 0])
        for bad in ["", "1.2.3", "1.2.3.4.5", "256.1.1.1", "01.2.3.4", "1..2.3", "1.2.3.-4", "+1.2.3.4", "a.b.c.d",
                    "1.2.3.4 ", " 1.2.3.4", "1.2.3.4/8", "١.٢.٣.٤", "1234.1.1.1"] {
            XCTAssertNil(NetworkMath.parseAddress(bad), bad)
        }
    }

    func testIPv6Parsing() {
        XCTAssertEqual(NetworkMath.parseAddress("::"), [UInt8](repeating: 0, count: 16))
        XCTAssertEqual(NetworkMath.parseAddress("::1"), [UInt8](repeating: 0, count: 15) + [1])
        XCTAssertEqual(NetworkMath.parseAddress("fe80::1%en0"), [0xFE, 0x80] + [UInt8](repeating: 0, count: 13) + [1])
        XCTAssertEqual(NetworkMath.parseAddress("2001:db8:0:0:0:0:2:1"),
                       [0x20, 0x01, 0x0D, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 1])
        XCTAssertEqual(NetworkMath.parseAddress("2001:DB8::2:1"), NetworkMath.parseAddress("2001:db8:0:0:0:0:2:1"))
        XCTAssertEqual(NetworkMath.parseAddress("::ffff:192.168.1.2"),
                       [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF, 192, 168, 1, 2])
        XCTAssertEqual(NetworkMath.parseAddress("1:2:3:4:5:6:7::"), [0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7, 0, 0])
        for bad in [":", ":::", "1::2::3", "12345::", "1:2:3:4:5:6:7:8:9", "1:2:3:4:5:6:7", "g::1", "::1.2.3.4:5",
                    "1.2.3.4::", "fe80::1%", "::%en0x%", "1:2:3:4:5:6:7:8::", "::ffff:1.2.3"] {
            XCTAssertNil(NetworkMath.parseAddress(bad), bad)
        }
    }

    func testFormatting() {
        XCTAssertEqual(NetworkMath.format([10, 1, 2, 3]), "10.1.2.3")
        XCTAssertEqual(NetworkMath.format(NetworkMath.parseAddress("2001:db8:0:0:0:0:2:1")!), "2001:db8::2:1")
        XCTAssertEqual(NetworkMath.format(NetworkMath.parseAddress("::")!), "::")
        XCTAssertEqual(NetworkMath.format(NetworkMath.parseAddress("::1")!), "::1")
        XCTAssertEqual(NetworkMath.format(NetworkMath.parseAddress("1::")!), "1::")
        XCTAssertEqual(NetworkMath.format(NetworkMath.parseAddress("1:0:2:3:4:5:6:7")!), "1:0:2:3:4:5:6:7")
        XCTAssertEqual(NetworkMath.format(NetworkMath.parseAddress("1:0:0:2:0:0:0:3")!), "1:0:0:2::3")
        XCTAssertEqual(NetworkMath.format([1, 2, 3]), "")
    }

    // MARK: CIDR

    func testCIDRParsing() throws {
        let v4 = try XCTUnwrap(NetworkMath.parseCIDR("10.0.0.0/8"))
        XCTAssertEqual(v4.address, [10, 0, 0, 0])
        XCTAssertEqual(v4.prefix, 8)
        XCTAssertEqual(NetworkMath.parseCIDR("  192.168.1.0/24 ")?.prefix, 24)
        XCTAssertEqual(NetworkMath.parseCIDR("10.1.2.3")?.prefix, 32)
        XCTAssertEqual(NetworkMath.parseCIDR("fd00::/8")?.prefix, 8)
        XCTAssertEqual(NetworkMath.parseCIDR("::1")?.prefix, 128)
        XCTAssertEqual(NetworkMath.parseCIDR("0.0.0.0/0")?.prefix, 0)
        for bad in ["", "/8", "10.0.0.0/", "10.0.0.0/33", "10.0.0.0/-1", "10.0.0.0/08", "10.0.0.0/8/8", "fd00::/129",
                    "fe80::1%en0/64", "10.0.0.0/ 8", "10.0.0.0/8x", "x/8"] {
            XCTAssertNil(NetworkMath.parseCIDR(bad), bad)
        }
    }

    func testCanonicalCIDR() {
        XCTAssertEqual(NetworkMath.canonicalCIDR("10.1.2.3/8"), "10.0.0.0/8")
        XCTAssertEqual(NetworkMath.canonicalCIDR("2001:DB8:0:0:1::/32"), "2001:db8::/32")
        XCTAssertEqual(NetworkMath.canonicalCIDR("192.168.1.77/25"), "192.168.1.0/25")
        XCTAssertEqual(NetworkMath.canonicalCIDR("192.168.1.200/25"), "192.168.1.128/25")
        XCTAssertNil(NetworkMath.canonicalCIDR("nope"))
    }

    func testCIDRMatching() {
        XCTAssertTrue(NetworkMath.cidrContains("10.0.0.0/8", address: "10.200.3.4"))
        XCTAssertFalse(NetworkMath.cidrContains("10.0.0.0/8", address: "11.0.0.1"))
        XCTAssertTrue(NetworkMath.cidrContains("192.168.1.0/24", address: "192.168.1.255"))
        XCTAssertFalse(NetworkMath.cidrContains("192.168.1.0/24", address: "192.168.2.1"))
        XCTAssertTrue(NetworkMath.cidrContains("192.168.1.128/25", address: "192.168.1.130"))
        XCTAssertFalse(NetworkMath.cidrContains("192.168.1.128/25", address: "192.168.1.127"))
        XCTAssertTrue(NetworkMath.cidrContains("0.0.0.0/0", address: "8.8.8.8"))
        XCTAssertTrue(NetworkMath.cidrContains("10.1.2.3", address: "10.1.2.3"))
        XCTAssertFalse(NetworkMath.cidrContains("10.1.2.3", address: "10.1.2.4"))
        XCTAssertTrue(NetworkMath.cidrContains("fd00::/8", address: "fd12:3456::1"))
        XCTAssertFalse(NetworkMath.cidrContains("fd00::/8", address: "fe80::1"))
        XCTAssertTrue(NetworkMath.cidrContains("fe80::/10", address: "febf::1%en0"))
        XCTAssertTrue(NetworkMath.cidrContains("2001:db8::/33", address: "2001:db8:7fff::1"))
        XCTAssertFalse(NetworkMath.cidrContains("2001:db8::/33", address: "2001:db8:8000::1"))
        // Families: an IPv4-mapped address matches IPv4 networks; otherwise no cross-family match.
        XCTAssertTrue(NetworkMath.cidrContains("10.0.0.0/8", address: "::ffff:10.9.8.7"))
        XCTAssertFalse(NetworkMath.cidrContains("::/0", address: "10.0.0.1"))
        XCTAssertFalse(NetworkMath.cidrContains("10.0.0.0/8", address: "::1"))
        XCTAssertFalse(NetworkMath.cidrContains("bad", address: "10.0.0.1"))
        XCTAssertFalse(NetworkMath.cidrContains("10.0.0.0/8", address: "bad"))
    }

    func testLinkLocalAndLoopback() {
        XCTAssertTrue(NetworkMath.isLinkLocalOrLoopback([169, 254, 1, 1]))
        XCTAssertTrue(NetworkMath.isLinkLocalOrLoopback([127, 0, 0, 1]))
        XCTAssertFalse(NetworkMath.isLinkLocalOrLoopback([10, 0, 0, 1]))
        XCTAssertTrue(NetworkMath.isLinkLocalOrLoopback(NetworkMath.parseAddress("fe80::1")!))
        XCTAssertTrue(NetworkMath.isLinkLocalOrLoopback(NetworkMath.parseAddress("::1")!))
        XCTAssertFalse(NetworkMath.isLinkLocalOrLoopback(NetworkMath.parseAddress("fd00::1")!))
        XCTAssertTrue(NetworkMath.isLinkLocalOrLoopback([]))
    }

    // MARK: MAC

    func testMACNormalization() {
        XCTAssertEqual(NetworkMath.normalizeMAC("AA:BB:CC:DD:EE:FF"), "aa:bb:cc:dd:ee:ff")
        XCTAssertEqual(NetworkMath.normalizeMAC("0:1b:c:d:e:f"), "00:1b:0c:0d:0e:0f")   // `arp -a` style
        XCTAssertEqual(NetworkMath.normalizeMAC("aa-bb-cc-dd-ee-ff"), "aa:bb:cc:dd:ee:ff")
        XCTAssertEqual(NetworkMath.normalizeMAC("aabb.ccdd.eeff"), "aa:bb:cc:dd:ee:ff")
        XCTAssertEqual(NetworkMath.normalizeMAC("AABBCCDDEEFF"), "aa:bb:cc:dd:ee:ff")
        XCTAssertEqual(NetworkMath.normalizeMAC(" aa:bb:cc:dd:ee:ff "), "aa:bb:cc:dd:ee:ff")
        for bad in ["", "aa:bb:cc:dd:ee", "aa:bb:cc:dd:ee:ff:00", "aaa:bb:cc:dd:ee:ff", "gg:bb:cc:dd:ee:ff",
                    "aa:bb-cc:dd:ee:ff", "00:00:00:00:00:00", "ff:ff:ff:ff:ff:ff", "aabbccddeef", "aabb.ccdd",
                    "aa::cc:dd:ee:ff", "+a:bb:cc:dd:ee:ff", "aabb.ccdd.eeff.0011"] {
            XCTAssertNil(NetworkMath.normalizeMAC(bad), bad)
        }
    }

    func testMACFromBytesAndHashMaterial() {
        XCTAssertEqual(NetworkMath.macString([0, 0x1B, 0x2C, 0x3D, 0x4E, 0x5F]), "00:1b:2c:3d:4e:5f")
        XCTAssertNil(NetworkMath.macString([0, 0, 0, 0, 0, 0]))
        XCTAssertNil(NetworkMath.macString([1, 2, 3]))
        // The hash input is the normalized MAC whatever the source spelling.
        XCTAssertEqual(AwakeHashMaterial.router(mac: "0:1B:2c:3d:4e:5f"), "router:00:1b:2c:3d:4e:5f")
        XCTAssertEqual(AwakeHashMaterial.router(mac: "001b.2c3d.4e5f"), AwakeHashMaterial.router(mac: "00-1B-2C-3D-4E-5F"))
        XCTAssertNil(AwakeHashMaterial.router(mac: "incomplete"))
    }

    // MARK: VPN

    func testVPNDetection() {
        XCTAssertFalse(NetworkMath.vpnConnected(addresses: [("utun0", "fe80::1"), ("en0", "10.0.0.5")], primaryInterface: "en0"))
        XCTAssertTrue(NetworkMath.vpnConnected(addresses: [("utun3", "10.8.0.2"), ("en0", "10.0.0.5")], primaryInterface: "en0"))
        XCTAssertTrue(NetworkMath.vpnConnected(addresses: [("ipsec0", "fd00::2")], primaryInterface: nil))
        XCTAssertTrue(NetworkMath.vpnConnected(addresses: [], primaryInterface: "utun4"))
        XCTAssertFalse(NetworkMath.vpnConnected(addresses: [("en0", "10.0.0.5")], primaryInterface: nil))
        XCTAssertFalse(NetworkMath.vpnConnected(addresses: [("utun1", "garbage")], primaryInterface: "en0"))
    }

    // MARK: Byte deltas and throughput

    func testByteDeltas() {
        XCTAssertEqual(NetworkMath.byteDelta(prev: 10, now: 25), 15)
        XCTAssertEqual(NetworkMath.byteDelta(prev: 10, now: 10), 0)
        XCTAssertNil(NetworkMath.byteDelta(prev: 25, now: 10))
        // 64-bit counters: values past 32 bits (multi-gigabit for a few seconds) are fine.
        XCTAssertEqual(NetworkMath.byteDelta(prev: UInt64(UInt32.max) - 5, now: UInt64(UInt32.max) + 10), 15)
        XCTAssertEqual(NetworkMath.byteDelta(prev: 0, now: UInt64.max), UInt64.max)
    }

    private func c(_ name: String, _ i: UInt64, _ o: UInt64) -> InterfaceCounters {
        InterfaceCounters(name: name, bytesIn: i, bytesOut: o)
    }

    func testThroughputExcludesLoopback() throws {
        let prev = [c("lo0", 0, 0), c("en0", 0, 0)]
        let now = [c("lo0", 10_000_000, 10_000_000), c("en0", 51_200, 0)]
        XCTAssertEqual(try XCTUnwrap(NetworkMath.throughputKBps(prev: prev, now: now, seconds: 5)), 10, accuracy: 1e-9)
    }

    func testTunnelTrafficIsNotCountedTwice() throws {
        // VPN: the same bytes cross utun3 and en0; only en0 counts.
        let prev = [c("en0", 0, 0), c("utun3", 0, 0)]
        let now = [c("en0", 102_400, 0), c("utun3", 100_000, 0)]
        XCTAssertEqual(try XCTUnwrap(NetworkMath.throughputKBps(prev: prev, now: now, seconds: 10)), 10, accuracy: 1e-9)
        // Only the tunnel moved (physical counters unreadable or idle): the tunnel counts.
        let tunnelOnly = [c("en0", 0, 0), c("utun3", 20_480, 0)]
        XCTAssertEqual(try XCTUnwrap(NetworkMath.throughputKBps(prev: prev, now: tunnelOnly, seconds: 10)), 2, accuracy: 1e-9)
    }

    func testThroughputSumsInAndOutAcrossInterfaces() throws {
        let prev = [c("en0", 100, 100), c("en1", 0, 0), c("bridge0", 0, 0)]
        let now = [c("en0", 100 + 1_024, 100 + 1_024), c("en1", 2_048, 0), c("bridge0", 0, 1_024)]
        XCTAssertEqual(try XCTUnwrap(NetworkMath.throughputKBps(prev: prev, now: now, seconds: 1)), 5, accuracy: 1e-9)
    }

    func testResetsAndHotPlugContributeNothing() throws {
        let prev = [c("en0", 5_000, 5_000), c("en5", 0, 0)]
        let now = [c("en0", 10, 10), c("en6", 99_999_999, 0)]   // en0 reset, en5 gone, en6 new
        XCTAssertEqual(try XCTUnwrap(NetworkMath.throughputKBps(prev: prev, now: now, seconds: 5)), 0)
        XCTAssertNil(NetworkMath.throughputKBps(prev: [c("en5", 0, 0)], now: [c("en6", 1, 1)], seconds: 5))
        XCTAssertNil(NetworkMath.throughputKBps(prev: [c("lo0", 0, 0)], now: [c("lo0", 1, 1)], seconds: 5))
    }

    func testThroughputUnknowns() {
        let a = [c("en0", 0, 0)]
        XCTAssertNil(NetworkMath.throughputKBps(prev: a, now: a, seconds: 0))
        XCTAssertNil(NetworkMath.throughputKBps(prev: a, now: a, seconds: -2))
        XCTAssertNil(NetworkMath.throughputKBps(prev: a, now: a, seconds: .nan))
        XCTAssertNil(NetworkMath.throughputKBps(prev: [], now: [], seconds: 5))
        XCTAssertEqual(NetworkMath.throughputKBps(prev: a, now: a, seconds: 5), 0)
    }

    func testThroughputSaturatesInsteadOfTrapping() throws {
        let prev = [c("en0", 0, 0), c("en1", 0, 0)]
        let now = [c("en0", UInt64.max, UInt64.max), c("en1", UInt64.max, 0)]
        let v = try XCTUnwrap(NetworkMath.throughputKBps(prev: prev, now: now, seconds: 1))
        XCTAssertEqual(v, Double(UInt64.max) / 1024, accuracy: 1e6)
    }

    // MARK: Fuzz

    func testSeededFuzzOfParsersNeverTraps() {
        var rng = SeededGenerator(seed: 0x1D2E3F)
        let alphabet = Array("0123456789abcdefABCDEFgx:.:/%- ")
        var parsed = 0
        for _ in 0..<20_000 {
            let n = Int(rng.next() % 48)
            let s = String((0..<n).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
            if let a = NetworkMath.parseAddress(s) {
                parsed += 1
                XCTAssertTrue(a.count == 4 || a.count == 16)
                // Formatting a parsed address gives an address that parses back to the same bytes.
                XCTAssertEqual(NetworkMath.parseAddress(NetworkMath.format(a)), a, s)
            }
            if let parsed = NetworkMath.parseCIDR(s) {
                let address = parsed.address
                XCTAssertTrue((0...(address.count * 8)).contains(parsed.prefix))
                let canonical = NetworkMath.canonicalCIDR(s)
                XCTAssertNotNil(canonical)
                XCTAssertEqual(NetworkMath.canonicalCIDR(canonical ?? ""), canonical, "canonical form is stable")
                XCTAssertTrue(NetworkMath.cidrContains(s, address: NetworkMath.format(address)))
            }
            if let mac = NetworkMath.normalizeMAC(s) {
                XCTAssertEqual(mac.count, 17)
                XCTAssertEqual(NetworkMath.normalizeMAC(mac), mac)
            }
            _ = NetworkMath.cidrContains(s, address: s)
        }
        // Random structured addresses round-trip through format/parse.
        for _ in 0..<5_000 {
            let v6 = (0..<16).map { _ in UInt8(truncatingIfNeeded: rng.next() % 3 == 0 ? 0 : rng.next()) }
            XCTAssertEqual(NetworkMath.parseAddress(NetworkMath.format(v6)), v6)
            let v4 = (0..<4).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            XCTAssertEqual(NetworkMath.parseAddress(NetworkMath.format(v4)), v4)
            let prefix = Int(rng.next() % 129)
            XCTAssertTrue(NetworkMath.cidrContains(NetworkMath.format(v6) + "/" + String(prefix), address: NetworkMath.format(v6)))
        }
        XCTAssertGreaterThan(parsed, 0)
    }

    func testSeededFuzzOfThroughputIsNonNegative() {
        var rng = SeededGenerator(seed: 0xF00D)
        let names = ["lo0", "en0", "en1", "utun0", "utun3", "ipsec0", "ppp0", "bridge0", "awdl0"]
        for _ in 0..<5_000 {
            func sample() -> [InterfaceCounters] {
                (0..<Int(rng.next() % 8)).map { _ in
                    c(names[Int(rng.next() % UInt64(names.count))], rng.next() >> (rng.next() % 64), rng.next() >> (rng.next() % 64))
                }
            }
            if let v = NetworkMath.throughputKBps(prev: sample(), now: sample(), seconds: Double(rng.next() % 10)) {
                XCTAssertGreaterThanOrEqual(v, 0)
            }
        }
    }
}
