import Foundation

/// A display's luminance range in nits. Defaults are estimates (labeled so in the UI);
/// users can edit them per display (PLAN §6.1 "Nits").
package struct NitsRange: Codable, Equatable, Sendable {
    /// At hardware level 0.
    package var minimum: Double
    /// SDR white at hardware level 1.
    package var maximum: Double
    /// HDR peak (XDR headroom limit).
    package var peak: Double
    package var isEstimate: Bool

    package static let limits: ClosedRange<Double> = 0...10000

    package init(minimum: Double, maximum: Double, peak: Double, isEstimate: Bool) {
        self.minimum = minimum
        self.maximum = maximum
        self.peak = peak
        self.isEstimate = isEstimate
    }

    private enum CodingKeys: String, CodingKey { case minimum, maximum, peak, isEstimate }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minimum = c.lossy(.minimum, 2.0)
        maximum = c.lossy(.maximum, 300.0)
        peak = c.lossy(.peak, 300.0)
        isEstimate = c.lossy(.isEstimate, false)
    }

    /// Ordered and bounded: 0 ≤ minimum < maximum ≤ peak ≤ 10000.
    package func sanitized() -> NitsRange {
        func c(_ v: Double, _ fallback: Double) -> Double {
            v.isFinite ? min(Self.limits.upperBound, max(Self.limits.lowerBound, v)) : fallback
        }
        var r = self
        r.maximum = max(1, c(maximum, 300))
        r.minimum = min(c(minimum, 2), r.maximum - 1)
        r.peak = max(r.maximum, c(peak, r.maximum))
        return r
    }
}

package enum NitsModel {
    /// Per-model defaults: MacBook Pro XDR M1–M3 500 SDR, M4+ 1000 SDR; other built-ins
    /// 500; externals 300. XDR peaks 1600.
    package static func defaultRange(isBuiltin: Bool, isXDR: Bool, chipName: String) -> NitsRange {
        if isBuiltin {
            if isXDR {
                let generation = chipGeneration(chipName) ?? 1
                return NitsRange(minimum: 2, maximum: generation >= 4 ? 1000 : 500, peak: 1600, isEstimate: true)
            }
            return NitsRange(minimum: 2, maximum: 500, peak: 500, isEstimate: true)
        }
        return NitsRange(minimum: 25, maximum: 300, peak: isXDR ? 600 : 300, isEstimate: true)
    }

    /// "Apple M3 Pro" → 3. Nil for Intel or unknown names.
    package static func chipGeneration(_ chipName: String) -> Int? {
        guard let range = chipName.range(of: "Apple M") else { return nil }
        let digits = chipName[range.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    /// Estimated luminance. Hardware maps linearly between minimum and maximum; software
    /// dimming scales the signal, so light falls with its 2.2 power; XDR multiplies light.
    package static func nits(hardware: Double?, software: Double, xdr: Double, range: NitsRange) -> Double {
        let r = range.sanitized()
        let h = hardware.map { min(1, max(0, $0.isFinite ? $0 : 1)) }
        let base = h.map { r.minimum + (r.maximum - r.minimum) * $0 } ?? r.maximum
        let sw = min(1, max(0, software.isFinite ? software : 1))
        var value = base * pow(sw, 2.2)
        if xdr > 1, xdr.isFinite { value = min(r.peak, value * xdr) }
        return value
    }

    /// "350 nits", rounded sensibly.
    package static func label(_ nits: Double, estimate: Bool) -> String {
        let n = nits.isFinite ? min(100_000, max(0, nits)) : 0
        let rounded = n >= 100 ? (n / 10).rounded() * 10 : n.rounded()
        let text = String(Int(max(0, rounded))) + " " + L("nits")
        return estimate ? "≈" + text : text
    }
}
