import Foundation

// Network parsing and throughput math (owner: J; PLAN 0.3 §2.8). Pure and total: every parser returns nil on bad
// input and never traps (fuzzed in NetworkMathTests).

/// One if_msghdr2 row (NET_RT_IFLIST2, if_data64).
package struct InterfaceCounters: Equatable, Sendable {
    package var name: String
    package var bytesIn: UInt64
    package var bytesOut: UInt64
    package init(name: String, bytesIn: UInt64, bytesOut: UInt64) {
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

package enum NetworkMath {
    /// Interface name prefixes that carry tunnelled traffic (VPN, Private Relay, Continuity).
    package static let tunnelPrefixes = ["utun", "ipsec", "ppp"]
    /// Longest text the parsers look at (an IPv6 address with a zone and prefix is far shorter).
    package static let maxInputLength = 128

    // MARK: Addresses

    /// "a.b.c.d" (decimal, no leading zeros, no signs) → 4 bytes, or an IPv6 address ("::" compression, an embedded
    /// dotted IPv4 tail, hex groups of 1–4 digits; a "%zone" suffix of 1–16 ASCII letters and digits is ignored) → 16 bytes.
    package static func parseAddress(_ s: String) -> [UInt8]? {
        guard s.utf8.count <= maxInputLength else { return nil }
        var text = Substring(s)
        if let percent = text.firstIndex(of: "%") {
            let zone = text[text.index(after: percent)...]
            guard text.contains(":"), (1...16).contains(zone.count),
                  zone.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
            text = text[..<percent]
        }
        if text.contains(":") { return parseIPv6(text) }
        return parseIPv4(text)
    }

    /// "10.0.0.0/8", "fd00::/8"; an address without "/" is a host route (/32 or /128). Surrounding whitespace is
    /// ignored, a zone is not allowed. Host bits may be set ("10.1.2.3/8" is 10.0.0.0/8).
    package static func parseCIDR(_ s: String) -> (address: [UInt8], prefix: Int)? {
        let text = s.trimmingCharacters(in: .whitespaces)
        guard text.utf8.count <= maxInputLength, !text.contains("%") else { return nil }
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2, let address = parseAddress(String(parts[0])) else { return nil }
        let bits = address.count * 8
        guard parts.count == 2 else { return (address, bits) }
        guard let prefix = parseDecimal(parts[1], max: bits) else { return nil }
        return (address, prefix)
    }

    /// The canonical text of a valid CIDR (masked, lowercase, IPv6 compressed), nil when invalid.
    package static func canonicalCIDR(_ s: String) -> String? {
        guard let parsed = parseCIDR(s) else { return nil }
        return format(mask(parsed.address, prefix: parsed.prefix)) + "/" + String(parsed.prefix)
    }

    /// True when `address` (IPv4 or IPv6; an IPv4-mapped IPv6 address matches IPv4 networks) is inside `cidr`.
    package static func cidrContains(_ cidr: String, address: String) -> Bool {
        guard let parsed = parseCIDR(cidr), var host = parseAddress(address) else { return false }
        let network = parsed.address, prefix = parsed.prefix
        if network.count == 4, host.count == 16, host[0..<10].allSatisfy({ $0 == 0 }), host[10] == 0xFF, host[11] == 0xFF {
            host = Array(host[12..<16])
        }
        guard host.count == network.count else { return false }
        return mask(host, prefix: prefix) == mask(network, prefix: prefix)
    }

    /// IPv4 link-local (169.254/16), IPv6 link-local (fe80::/10) or loopback: not an address that names a network.
    package static func isLinkLocalOrLoopback(_ bytes: [UInt8]) -> Bool {
        switch bytes.count {
        case 4: return bytes[0] == 127 || (bytes[0] == 169 && bytes[1] == 254)
        case 16:
            if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 { return true }
            return bytes[0..<15].allSatisfy { $0 == 0 } && bytes[15] == 1
        default: return true
        }
    }

    /// Text form: dotted IPv4, or RFC 5952 IPv6 (lowercase, longest zero run of ≥ 2 groups compressed).
    package static func format(_ bytes: [UInt8]) -> String {
        if bytes.count == 4 { return bytes.map(String.init).joined(separator: ".") }
        guard bytes.count == 16 else { return "" }
        let groups = stride(from: 0, to: 16, by: 2).map { (UInt16(bytes[$0]) << 8) | UInt16(bytes[$0 + 1]) }
        var bestStart = -1, bestLength = 0, runStart = -1
        for i in 0...8 {
            if i < 8 && groups[i] == 0 {
                if runStart < 0 { runStart = i }
            } else if runStart >= 0 {
                if i - runStart > bestLength { bestStart = runStart; bestLength = i - runStart }
                runStart = -1
            }
        }
        let hex = groups.map { String($0, radix: 16) }
        guard bestLength >= 2 else { return hex.joined(separator: ":") }
        let head = hex[0..<bestStart].joined(separator: ":")
        let tail = hex[(bestStart + bestLength)...].joined(separator: ":")
        return head + "::" + tail
    }

    // MARK: MAC addresses

    /// "aa:bb:cc:dd:ee:ff" (lowercase, two digits per byte) from 6 groups of 1–2 hex digits separated by ":" or "-",
    /// 3 groups of 4 separated by ".", or 12 contiguous hex digits. nil for anything else and for the all-zero and
    /// broadcast addresses (an incomplete ARP entry is not a router).
    package static func normalizeMAC(_ s: String) -> String? {
        let text = s.trimmingCharacters(in: .whitespaces)
        guard text.utf8.count <= 32 else { return nil }
        var bytes: [UInt8] = []
        if text.contains(":") || text.contains("-") {
            let separator: Character = text.contains(":") ? ":" : "-"
            guard !(text.contains(":") && text.contains("-")) else { return nil }
            let groups = text.split(separator: separator, omittingEmptySubsequences: false)
            guard groups.count == 6 else { return nil }
            for g in groups {
                guard (1...2).contains(g.count), let b = parseHex(g) else { return nil }
                bytes.append(UInt8(b))
            }
        } else if text.contains(".") {
            let groups = text.split(separator: ".", omittingEmptySubsequences: false)
            guard groups.count == 3 else { return nil }
            for g in groups {
                guard g.count == 4, let v = parseHex(g) else { return nil }
                bytes.append(UInt8(v >> 8))
                bytes.append(UInt8(v & 0xFF))
            }
        } else {
            guard text.count == 12 else { return nil }
            var i = text.startIndex
            while i < text.endIndex {
                let j = text.index(i, offsetBy: 2)
                guard let b = parseHex(text[i..<j]) else { return nil }
                bytes.append(UInt8(b))
                i = j
            }
        }
        return macString(bytes)
    }

    /// "aa:bb:…" for 6 raw bytes (an sockaddr_dl's link-layer address); nil for other lengths, all-zero or broadcast.
    package static func macString(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 6, bytes.contains(where: { $0 != 0 }), bytes.contains(where: { $0 != 0xFF }) else { return nil }
        return bytes.map { b -> String in
            let digits = Array("0123456789abcdef")
            return String([digits[Int(b >> 4)], digits[Int(b & 0x0F)]])
        }.joined(separator: ":")
    }

    // MARK: Interfaces and throughput

    package static func isLoopback(_ name: String) -> Bool { name.hasPrefix("lo") }

    package static func isTunnel(_ name: String) -> Bool { tunnelPrefixes.contains { name.hasPrefix($0) } }

    /// A VPN is up when a tunnel interface has an address that names a network (macOS keeps several idle `utun`s
    /// for Private Relay and Continuity, which only have link-local addresses), or the primary interface is a tunnel.
    package static func vpnConnected(addresses: [(interface: String, address: String)], primaryInterface: String?) -> Bool {
        if let primary = primaryInterface, isTunnel(primary) { return true }
        return addresses.contains { entry in
            guard isTunnel(entry.interface), let bytes = parseAddress(entry.address) else { return false }
            return !isLinkLocalOrLoopback(bytes)
        }
    }

    /// 64-bit counter delta; nil on a reset (now < prev).
    package static func byteDelta(prev: UInt64, now: UInt64) -> UInt64? {
        now >= prev ? now - prev : nil
    }

    /// KB/s (1 KB = 1024 bytes) over all non-loopback interfaces present in both samples (`lo*` excluded; a counter
    /// reset counts 0 for that interface; an interface that appeared or vanished counts nothing). Tunnels (`utun*`,
    /// `ipsec*`, `ppp*`) count only when no physical interface moved bytes, so VPN traffic isn't counted twice.
    /// nil when `seconds` is invalid or no interface is in both samples (unknown).
    package static func throughputKBps(prev: [InterfaceCounters], now: [InterfaceCounters], seconds: Double) -> Double? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        var before: [String: InterfaceCounters] = [:]
        for c in prev where before[c.name] == nil { before[c.name] = c }
        var seen = Set<String>()
        var physical: UInt64 = 0, tunnel: UInt64 = 0
        var compared = false
        for c in now where !isLoopback(c.name) {
            guard seen.insert(c.name).inserted, let p = before[c.name] else { continue }
            compared = true
            let moved = (byteDelta(prev: p.bytesIn, now: c.bytesIn) ?? 0)
                .addingReportingOverflow(byteDelta(prev: p.bytesOut, now: c.bytesOut) ?? 0)
            let bytes = moved.overflow ? UInt64.max : moved.partialValue
            if isTunnel(c.name) {
                tunnel = tunnel.addingReportingOverflow(bytes).overflow ? UInt64.max : tunnel + bytes
            } else {
                physical = physical.addingReportingOverflow(bytes).overflow ? UInt64.max : physical + bytes
            }
        }
        guard compared else { return nil }
        let bytes = physical > 0 ? physical : tunnel
        return Double(bytes) / 1024 / seconds
    }

    // MARK: Private parsing

    private static func parseIPv4(_ s: Substring) -> [UInt8]? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var out: [UInt8] = []
        for p in parts {
            guard let v = parseDecimal(p, max: 255) else { return nil }
            out.append(UInt8(v))
        }
        return out
    }

    private static func parseIPv6(_ s: Substring) -> [UInt8]? {
        guard !s.isEmpty else { return nil }
        let halves = s.components(separatedBy: "::")
        guard halves.count <= 2 else { return nil }
        func groups(_ part: String, allowIPv4Tail: Bool) -> [UInt16]? {
            if part.isEmpty { return [] }
            let items = part.split(separator: ":", omittingEmptySubsequences: false)
            var out: [UInt16] = []
            for (i, item) in items.enumerated() {
                if item.contains(".") {
                    guard allowIPv4Tail, i == items.count - 1, let v4 = parseIPv4(item) else { return nil }
                    out.append((UInt16(v4[0]) << 8) | UInt16(v4[1]))
                    out.append((UInt16(v4[2]) << 8) | UInt16(v4[3]))
                } else {
                    guard (1...4).contains(item.count), let v = parseHex(item) else { return nil }
                    out.append(UInt16(v))
                }
            }
            return out
        }
        var all: [UInt16]
        if halves.count == 2 {
            guard let head = groups(halves[0], allowIPv4Tail: false), let tail = groups(halves[1], allowIPv4Tail: true),
                  head.count + tail.count <= 7 else { return nil }
            all = head + Array(repeating: 0, count: 8 - head.count - tail.count) + tail
        } else {
            guard let only = groups(halves[0], allowIPv4Tail: true), only.count == 8 else { return nil }
            all = only
        }
        return all.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
    }

    /// ASCII decimal digits only, no leading zeros (except "0"), ≤ `max`.
    private static func parseDecimal(_ s: Substring, max: Int) -> Int? {
        guard !s.isEmpty, s.count <= 3, s.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        guard s.count == 1 || s.first != "0", let v = Int(s), v <= max else { return nil }
        return v
    }

    /// ASCII hex digits only (1–4), no signs.
    private static func parseHex(_ s: Substring) -> Int? {
        guard !s.isEmpty, s.count <= 4, s.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return Int(s, radix: 16)
    }

    private static func mask(_ bytes: [UInt8], prefix: Int) -> [UInt8] {
        var out = bytes
        for i in out.indices {
            let bitsHere = min(8, max(0, prefix - i * 8))
            let m: UInt8 = bitsHere == 0 ? 0 : UInt8(truncatingIfNeeded: 0xFF << (8 - bitsHere))
            out[i] &= m
        }
        return out
    }
}
