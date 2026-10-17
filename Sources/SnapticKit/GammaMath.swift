import Foundation

/// Per-display color adjustments composed into one gamma table (PLAN §6.2, parity §5.1).
/// Neutral values make an identity table. Every field decodes lossily and is clamped.
package struct ColorAdjustments: Codable, Equatable, Sendable {
    /// Software brightness multiplier (reserved for layouts; the combined slider owns brightness).
    package var brightness: Double
    /// Linear contrast around mid-grey (1 = neutral).
    package var contrast: Double
    /// Overall gamma (1 = neutral; above 1 lifts mid-tones).
    package var gamma: Double
    /// Per-channel gains (1 = neutral).
    package var red: Double
    package var green: Double
    package var blue: Double
    package var inverted: Bool
    /// Per-channel gamma (1 = neutral).
    package var redGamma: Double
    package var greenGamma: Double
    package var blueGamma: Double
    /// Overall gain (1 = neutral).
    package var gain: Double
    /// White point in kelvin (6500 = neutral).
    package var temperature: Double
    /// Output levels (0 and 1 = neutral).
    package var blackLevel: Double
    package var whiteLevel: Double

    package init() {
        brightness = 1; contrast = 1; gamma = 1
        red = 1; green = 1; blue = 1
        inverted = false
        redGamma = 1; greenGamma = 1; blueGamma = 1
        gain = 1
        temperature = 6500
        blackLevel = 0; whiteLevel = 1
    }

    package var isIdentity: Bool { self == ColorAdjustments() }

    package static let brightnessRange: ClosedRange<Double> = 0.1...1
    package static let contrastRange: ClosedRange<Double> = 0.5...1.5
    package static let gammaRange: ClosedRange<Double> = 0.5...2
    package static let gainRange: ClosedRange<Double> = 0.2...1.5
    package static let temperatureRange: ClosedRange<Double> = 1900...10000
    package static let blackLevelRange: ClosedRange<Double> = 0...0.3
    package static let whiteLevelRange: ClosedRange<Double> = 0.7...1

    private enum CodingKeys: String, CodingKey {
        case brightness, contrast, gamma, red, green, blue, inverted, redGamma, greenGamma, blueGamma, gain,
             temperature, blackLevel, whiteLevel
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = c.lossy(.brightness, 1.0)
        contrast = c.lossy(.contrast, 1.0)
        gamma = c.lossy(.gamma, 1.0)
        red = c.lossy(.red, 1.0)
        green = c.lossy(.green, 1.0)
        blue = c.lossy(.blue, 1.0)
        inverted = c.lossy(.inverted, false)
        redGamma = c.lossy(.redGamma, 1.0)
        greenGamma = c.lossy(.greenGamma, 1.0)
        blueGamma = c.lossy(.blueGamma, 1.0)
        gain = c.lossy(.gain, 1.0)
        temperature = c.lossy(.temperature, 6500.0)
        blackLevel = c.lossy(.blackLevel, 0.0)
        whiteLevel = c.lossy(.whiteLevel, 1.0)
    }

    /// Clamps every value to what the UI can produce. NaN becomes neutral.
    package func sanitized() -> ColorAdjustments {
        var a = self
        a.brightness = Self.clamp(brightness, Self.brightnessRange, neutral: 1)
        a.contrast = Self.clamp(contrast, Self.contrastRange, neutral: 1)
        a.gamma = Self.clamp(gamma, Self.gammaRange, neutral: 1)
        a.red = Self.clamp(red, Self.gainRange, neutral: 1)
        a.green = Self.clamp(green, Self.gainRange, neutral: 1)
        a.blue = Self.clamp(blue, Self.gainRange, neutral: 1)
        a.redGamma = Self.clamp(redGamma, Self.gammaRange, neutral: 1)
        a.greenGamma = Self.clamp(greenGamma, Self.gammaRange, neutral: 1)
        a.blueGamma = Self.clamp(blueGamma, Self.gammaRange, neutral: 1)
        a.gain = Self.clamp(gain, Self.gainRange, neutral: 1)
        a.temperature = Self.clamp(temperature, Self.temperatureRange, neutral: 6500)
        a.blackLevel = Self.clamp(blackLevel, Self.blackLevelRange, neutral: 0)
        a.whiteLevel = Self.clamp(whiteLevel, Self.whiteLevelRange, neutral: 1)
        return a
    }

    package static func clamp(_ v: Double, _ range: ClosedRange<Double>, neutral: Double) -> Double {
        guard v.isFinite else { return neutral }
        return min(range.upperBound, max(range.lowerBound, v))
    }

    /// Everything but brightness is neutral (what "Suspend adjustments" applies).
    package var suspended: ColorAdjustments {
        var a = ColorAdjustments()
        a.brightness = brightness
        return a
    }
}

/// A three-channel transfer table, values 0…1 (above 1 only for XDR method B).
package struct GammaTable: Equatable, Sendable {
    package var red: [Float]
    package var green: [Float]
    package var blue: [Float]

    package init(red: [Float], green: [Float], blue: [Float]) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    package static func identity(samples: Int = GammaMath.samples) -> GammaTable {
        let n = max(2, min(GammaMath.maxSamples, samples))
        let ramp = (0..<n).map { Float($0) / Float(n - 1) }
        return GammaTable(red: ramp, green: ramp, blue: ramp)
    }

    package var count: Int { red.count }

    /// Same length on every channel, within bounds, every value finite and ≥ 0.
    package var isValid: Bool {
        let n = red.count
        guard n >= 2, n <= GammaMath.maxSamples, green.count == n, blue.count == n else { return false }
        return [red, green, blue].allSatisfy { $0.allSatisfy { $0.isFinite && $0 >= 0 } }
    }

    /// Largest value on any channel.
    package var peak: Float { max(red.max() ?? 0, green.max() ?? 0, blue.max() ?? 0) }

    package var isAllZero: Bool { peak <= 0 }

    package func channel(_ index: Int) -> [Float] {
        switch index {
        case 0: return red
        case 1: return green
        default: return blue
        }
    }
}

/// What the watchdog concluded from a read-back.
package enum GammaReadback: Equatable, Sendable {
    /// Matches what we wrote (±1/256).
    case ok
    /// Zeroed or collapsed (the wake "blank screen" bug): re-apply the last good table.
    case collapsed
    /// Something else wrote a different table (another gamma app, a profile change).
    case foreign
}

/// Gamma composition (PLAN §6.2): baseline ∘ adjustments × brightness × xdrScale,
/// 1024 samples, floor-clamped. Property-tested in GammaMathTests.
package enum GammaMath {
    package static let samples = 1024
    package static let maxSamples = 4096
    /// Read-back tolerance (PLAN §4.9).
    package static let tolerance: Float = 1.0 / 256.0
    /// A table whose peak is below this fraction of ours counts as collapsed (§4.9).
    package static let collapseFraction: Float = 0.1
    /// Largest XDR scale gamma may express.
    package static let maxXDRScale = 4.0

    package struct Inputs: Equatable, Sendable {
        package var adjustments: ColorAdjustments
        /// Software dimming factor 0…1.
        package var brightness: Double
        /// 1 = SDR; above 1 = XDR method B.
        package var xdrScale: Double
        /// The table's peak never ends below this (0.08 normally, 0 with dim to black).
        package var floor: Double

        package init(adjustments: ColorAdjustments = ColorAdjustments(), brightness: Double = 1, xdrScale: Double = 1,
                     floor: Double = 0.08) {
            self.adjustments = adjustments
            self.brightness = brightness
            self.xdrScale = xdrScale
            self.floor = floor
        }

        /// True when the composed table equals the baseline.
        package var isNeutral: Bool {
            adjustments.sanitized().isIdentity && brightness >= 1 && xdrScale <= 1
        }
    }

    /// Composes the table written to the display.
    package static func compose(baseline: GammaTable?, inputs: Inputs, samples: Int = GammaMath.samples) -> GammaTable {
        let n = max(2, min(maxSamples, samples))
        let a = inputs.adjustments.sanitized()
        let base = (baseline?.isValid ?? false) ? baseline : nil
        let temp = temperatureGains(kelvin: a.temperature)
        let gains = [a.red * temp.r * a.gain, a.green * temp.g * a.gain, a.blue * temp.b * a.gain]
        let gammas = [a.gamma * a.redGamma, a.gamma * a.greenGamma, a.gamma * a.blueGamma]
        let floor = clamp01(inputs.floor.isFinite ? inputs.floor : 0.08)
        let scale = max(1, min(maxXDRScale, inputs.xdrScale.isFinite ? inputs.xdrScale : 1))
        var dim = inputs.brightness.isFinite ? inputs.brightness : 1
        dim = max(floor, min(1, dim)) * a.brightness
        var channels: [[Float]] = [[], [], []]
        for c in 0..<3 {
            var out = [Float](repeating: 0, count: n)
            let exponent = 1 / max(0.01, gammas[c])
            let baseChannel = base?.channel(c)
            for i in 0..<n {
                let x = Double(i) / Double(n - 1)
                var v = a.inverted ? 1 - x : x
                v = clamp01(0.5 + (v - 0.5) * a.contrast)
                v = pow(v, exponent)
                v = clamp01(v * gains[c])
                v = a.blackLevel + v * (a.whiteLevel - a.blackLevel)
                if let table = baseChannel { v = sample(table, at: v) }
                v = min(scale, max(0, v * dim * scale))
                out[i] = Float(v)
            }
            channels[c] = out
        }
        var table = GammaTable(red: channels[0], green: channels[1], blue: channels[2])
        // Floor clamp: whatever the adjustments, the brightest output stays visible.
        let peak = Double(table.peak)
        if floor > 0, peak < floor {
            if peak > 0 {
                let k = Float(floor / peak)
                table = GammaTable(red: table.red.map { $0 * k }, green: table.green.map { $0 * k },
                                   blue: table.blue.map { $0 * k })
            } else {
                let ramp = (0..<n).map { Float(floor * Double($0) / Double(n - 1)) }
                table = GammaTable(red: ramp, green: ramp, blue: ramp)
            }
        }
        return table
    }

    package static func clamp01(_ v: Double) -> Double { v.isFinite ? min(1, max(0, v)) : 0 }

    /// Linear interpolation into a table at x ∈ 0…1.
    package static func sample(_ table: [Float], at x: Double) -> Double {
        guard let last = table.last else { return x }
        guard table.count > 1 else { return Double(last) }
        let position = clamp01(x) * Double(table.count - 1)
        let i = min(table.count - 2, Int(position))
        let frac = position - Double(i)
        return Double(table[i]) * (1 - frac) + Double(table[i + 1]) * frac
    }

    /// Resamples a table to `samples` entries per channel.
    package static func resample(_ table: GammaTable, to samples: Int) -> GammaTable {
        let n = max(2, min(maxSamples, samples))
        guard table.count != n else { return table }
        func r(_ c: [Float]) -> [Float] { (0..<n).map { Float(sample(c, at: Double($0) / Double(n - 1))) } }
        return GammaTable(red: r(table.red), green: r(table.green), blue: r(table.blue))
    }

    /// True when `a` and `b` agree within `tolerance` everywhere (different lengths are resampled).
    package static func matches(_ a: GammaTable, _ b: GammaTable, tolerance: Float = GammaMath.tolerance) -> Bool {
        guard a.isValid, b.isValid else { return false }
        let bb = resample(b, to: a.count)
        for c in 0..<3 {
            let x = a.channel(c), y = bb.channel(c)
            for i in 0..<x.count where abs(x[i] - y[i]) > tolerance { return false }
        }
        return true
    }

    /// Watchdog verdict for a read-back of what we last wrote.
    package static func check(readback: GammaTable, expected: GammaTable) -> GammaReadback {
        guard readback.isValid else { return .collapsed }
        let expectedPeak = expected.peak
        if readback.isAllZero || (expectedPeak > 0.05 && readback.peak < expectedPeak * collapseFraction) {
            return .collapsed
        }
        return matches(readback, expected) ? .ok : .foreign
    }

    /// Kelvin → per-channel gains relative to 6500 K, normalized so the largest is 1.
    package static func temperatureGains(kelvin: Double) -> (r: Double, g: Double, b: Double) {
        let k = ColorAdjustments.clamp(kelvin, ColorAdjustments.temperatureRange, neutral: 6500)
        let x = rgb(k), n = rgb(6500)
        var r = x.r / n.r, g = x.g / n.g, b = x.b / n.b
        let m = max(r, g, b)
        if m > 0 { r /= m; g /= m; b /= m }
        return (r, g, b)
    }

    /// Blackbody approximation (Tanner Helland), 0…1 per channel.
    private static func rgb(_ kelvin: Double) -> (r: Double, g: Double, b: Double) {
        let t = kelvin / 100
        var r: Double, g: Double, b: Double
        if t <= 66 {
            r = 255
            g = 99.4708025861 * log(t) - 161.1195681661
        } else {
            r = 329.698727446 * pow(t - 60, -0.1332047592)
            g = 288.1221695283 * pow(t - 60, -0.0755148492)
        }
        if t >= 66 {
            b = 255
        } else if t <= 19 {
            b = 0
        } else {
            b = 138.5177312231 * log(t - 10) - 305.0447927307
        }
        func c(_ v: Double) -> Double { max(1, min(255, v)) / 255 }
        return (c(r), c(g), c(b))
    }
}

/// Counts gamma fights (someone else rewrote our table). 3 in 60 s → give up on that
/// display and suggest the overlay method (PLAN §4.9).
package struct GammaFightTracker: Equatable, Sendable {
    package static let limit = 3
    package static let window = 60.0
    package private(set) var times: [Double] = []

    package init() {}

    /// Records a fight at `now` (seconds, monotonic). Returns true when the limit is reached.
    package mutating func record(at now: Double) -> Bool {
        times = times.filter { now - $0 < Self.window && $0 <= now }
        times.append(now)
        return times.count >= Self.limit
    }

    package mutating func reset() { times = [] }
}
