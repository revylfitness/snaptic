import Foundation

// Stub (owner: J). Hand-written by the lead in step 0 from PLAN 0.3 §2.8 (kind S): safe returns.

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
    /// IPv4 or IPv6. Stub: nil.
    package static func parseCIDR(_ s: String) -> (address: [UInt8], prefix: Int)? { nil }
    /// Stub: false.
    package static func cidrContains(_ cidr: String, address: String) -> Bool { false }
    /// "aa:bb:…" lowercase. Stub: nil.
    package static func normalizeMAC(_ s: String) -> String? { nil }
    /// 64-bit counter delta; nil on a reset. Stub: nil.
    package static func byteDelta(prev: UInt64, now: UInt64) -> UInt64? { nil }
    /// KB/s over non-loopback interfaces. Stub: nil.
    package static func throughputKBps(prev: [InterfaceCounters], now: [InterfaceCounters], seconds: Double) -> Double? {
        nil
    }
}
