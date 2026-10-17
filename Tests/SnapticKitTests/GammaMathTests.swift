import XCTest
@testable import SnapticKit

final class GammaMathTests: XCTestCase {
    private func identityInputs() -> GammaMath.Inputs { GammaMath.Inputs(floor: 0) }

    func testIdentityComposesToIdentity() {
        let t = GammaMath.compose(baseline: nil, inputs: identityInputs())
        XCTAssertEqual(t.count, GammaMath.samples)
        XCTAssertTrue(GammaMath.matches(t, .identity()))
        XCTAssertTrue(identityInputs().isNeutral)
    }

    func testBaselineIsPreservedWhenNeutral() {
        let baseline = GammaTable(red: (0..<256).map { pow(Float($0) / 255, 1.1) },
                                  green: (0..<256).map { Float($0) / 255 * 0.9 },
                                  blue: (0..<256).map { Float($0) / 255 })
        let t = GammaMath.compose(baseline: baseline, inputs: identityInputs(), samples: 256)
        XCTAssertTrue(GammaMath.matches(t, baseline))
    }

    func testBrightnessScalesAndRespectsFloor() {
        var inputs = GammaMath.Inputs(brightness: 0.5, floor: 0.08)
        XCTAssertEqual(GammaMath.compose(baseline: nil, inputs: inputs).peak, 0.5, accuracy: 1e-4)
        inputs.brightness = 0
        XCTAssertEqual(GammaMath.compose(baseline: nil, inputs: inputs).peak, 0.08, accuracy: 1e-4)
        inputs.floor = 0
        XCTAssertEqual(GammaMath.compose(baseline: nil, inputs: inputs).peak, 0, accuracy: 1e-6, "dim to black")
    }

    func testFloorHoldsAgainstDarkAdjustments() {
        var a = ColorAdjustments()
        a.gain = 0.2
        a.whiteLevel = 0.7
        a.brightness = 0.1
        let t = GammaMath.compose(baseline: nil, inputs: GammaMath.Inputs(adjustments: a, brightness: 0.08, floor: 0.08))
        XCTAssertGreaterThanOrEqual(t.peak, 0.08 - 1e-4)
    }

    func testInvertFlipsTheRamp() {
        var a = ColorAdjustments()
        a.inverted = true
        let t = GammaMath.compose(baseline: nil, inputs: GammaMath.Inputs(adjustments: a, floor: 0))
        XCTAssertEqual(t.red.first ?? 0, 1, accuracy: 1e-5)
        XCTAssertEqual(t.red.last ?? 1, 0, accuracy: 1e-5)
    }

    func testContrastPivotsAroundMidGrey() {
        var a = ColorAdjustments()
        a.contrast = 1.5
        let t = GammaMath.compose(baseline: nil, inputs: GammaMath.Inputs(adjustments: a, floor: 0), samples: 1025)
        XCTAssertEqual(t.green[512], 0.5, accuracy: 1e-3)
        XCTAssertEqual(t.green[0], 0, accuracy: 1e-5)
        XCTAssertEqual(t.green[1024], 1, accuracy: 1e-5)
        XCTAssertLessThan(t.green[256], 0.25)
    }

    func testGammaAboveOneLiftsMidtones() {
        var a = ColorAdjustments()
        a.gamma = 1.5
        let t = GammaMath.compose(baseline: nil, inputs: GammaMath.Inputs(adjustments: a, floor: 0), samples: 1025)
        XCTAssertGreaterThan(t.blue[512], 0.5)
        a.gamma = 1
        a.blueGamma = 0.7
        let u = GammaMath.compose(baseline: nil, inputs: GammaMath.Inputs(adjustments: a, floor: 0), samples: 1025)
        XCTAssertLessThan(u.blue[512], 0.5)
        XCTAssertEqual(u.red[512], 0.5, accuracy: 1e-3)
    }

    func testChannelGainsAndTemperature() {
        var a = ColorAdjustments()
        a.red = 0.5
        let t = GammaMath.compose(baseline: nil, inputs: GammaMath.Inputs(adjustments: a, floor: 0))
        XCTAssertEqual(t.red.last ?? 0, 0.5, accuracy: 1e-4)
        XCTAssertEqual(t.green.last ?? 0, 1, accuracy: 1e-4)

        let neutral = GammaMath.temperatureGains(kelvin: 6500)
        XCTAssertEqual(neutral.r, 1, accuracy: 1e-9)
        XCTAssertEqual(neutral.g, 1, accuracy: 1e-9)
        XCTAssertEqual(neutral.b, 1, accuracy: 1e-9)
        let warm = GammaMath.temperatureGains(kelvin: 3000)
        XCTAssertEqual(warm.r, 1, accuracy: 1e-9)
        XCTAssertLessThan(warm.b, warm.g)
        XCTAssertLessThan(warm.g, 1)
        let cool = GammaMath.temperatureGains(kelvin: 9500)
        XCTAssertEqual(cool.b, 1, accuracy: 1e-9)
        XCTAssertLessThan(cool.r, 1)
    }

    func testXDRScaleAboveOne() {
        let t = GammaMath.compose(baseline: nil, inputs: GammaMath.Inputs(xdrScale: 1.6, floor: 0))
        XCTAssertEqual(t.peak, 1.6, accuracy: 1e-4)
        let capped = GammaMath.compose(baseline: nil, inputs: GammaMath.Inputs(xdrScale: 99, floor: 0))
        XCTAssertEqual(Double(capped.peak), GammaMath.maxXDRScale, accuracy: 1e-4)
        XCTAssertFalse(GammaMath.Inputs(xdrScale: 1.6).isNeutral)
    }

    func testNaNInputsAreNeutralized() {
        var a = ColorAdjustments()
        a.gamma = .nan
        a.red = .infinity
        let t = GammaMath.compose(baseline: nil, inputs: GammaMath.Inputs(adjustments: a, brightness: .nan, xdrScale: .nan, floor: .nan))
        XCTAssertTrue(t.isValid)
    }

    func testInvalidBaselineIsIgnored() {
        let bad = GammaTable(red: [0, 1], green: [0], blue: [0, .nan])
        XCTAssertFalse(bad.isValid)
        let t = GammaMath.compose(baseline: bad, inputs: identityInputs())
        XCTAssertTrue(GammaMath.matches(t, .identity()))
    }

    func testSampleAndResample() {
        XCTAssertEqual(GammaMath.sample([0, 1], at: 0.25), 0.25, accuracy: 1e-9)
        XCTAssertEqual(GammaMath.sample([], at: 0.3), 0.3, accuracy: 1e-9)
        XCTAssertEqual(GammaMath.sample([0.7], at: 0.3), 0.7, accuracy: 1e-6)
        let r = GammaMath.resample(.identity(samples: 256), to: 1024)
        XCTAssertEqual(r.count, 1024)
        XCTAssertTrue(GammaMath.matches(r, .identity()))
    }

    func testWatchdogVerdicts() {
        let ours = GammaMath.compose(baseline: nil, inputs: GammaMath.Inputs(brightness: 0.6))
        XCTAssertEqual(GammaMath.check(readback: ours, expected: ours), .ok)
        // The system returns 256 entries for a 1024-entry write: still ours.
        XCTAssertEqual(GammaMath.check(readback: GammaMath.resample(ours, to: 256), expected: ours), .ok)
        let zero = GammaTable(red: [0, 0, 0], green: [0, 0, 0], blue: [0, 0, 0])
        XCTAssertEqual(GammaMath.check(readback: zero, expected: ours), .collapsed)
        let nearlyZero = GammaMath.compose(baseline: nil, inputs: GammaMath.Inputs(brightness: 0.05, floor: 0))
        XCTAssertEqual(GammaMath.check(readback: nearlyZero, expected: ours), .collapsed, "below 10% of ours")
        XCTAssertEqual(GammaMath.check(readback: .identity(), expected: ours), .foreign)
        XCTAssertEqual(GammaMath.check(readback: GammaTable(red: [], green: [], blue: []), expected: ours), .collapsed)
    }

    func testToleranceIsOne256th() {
        var t = GammaTable.identity(samples: 16)
        t.red[5] += 0.5 / 256
        XCTAssertTrue(GammaMath.matches(t, .identity(samples: 16)))
        t.red[5] += 2 / 256
        XCTAssertFalse(GammaMath.matches(t, .identity(samples: 16)))
    }

    func testFightTracker() {
        var f = GammaFightTracker()
        XCTAssertFalse(f.record(at: 0))
        XCTAssertFalse(f.record(at: 10))
        XCTAssertTrue(f.record(at: 59))
        f.reset()
        XCTAssertFalse(f.record(at: 100))
        XCTAssertFalse(f.record(at: 170))
        XCTAssertFalse(f.record(at: 240), "fights more than 60 s apart don't add up")
    }

    func testAdjustmentsSanitizeAndDecodeLossily() throws {
        var a = ColorAdjustments()
        a.contrast = 9
        a.temperature = -5
        a.gamma = .nan
        let s = a.sanitized()
        XCTAssertEqual(s.contrast, ColorAdjustments.contrastRange.upperBound)
        XCTAssertEqual(s.temperature, ColorAdjustments.temperatureRange.lowerBound)
        XCTAssertEqual(s.gamma, 1)
        let json = #"{"contrast":1.2,"red":"x","inverted":true}"#
        let d = try JSONDecoder().decode(ColorAdjustments.self, from: Data(json.utf8))
        XCTAssertEqual(d.contrast, 1.2)
        XCTAssertEqual(d.red, 1)
        XCTAssertTrue(d.inverted)
        XCTAssertEqual(d.temperature, 6500)
        XCTAssertEqual(try JSONDecoder().decode(ColorAdjustments.self, from: JSONEncoder().encode(s)), s)
        var withBrightness = ColorAdjustments()
        withBrightness.brightness = 0.5
        withBrightness.contrast = 1.3
        XCTAssertEqual(withBrightness.suspended.brightness, 0.5)
        XCTAssertEqual(withBrightness.suspended.contrast, 1)
    }

    /// Property test: for random adjustments the table is valid, monotonic per channel
    /// unless inverted, bounded by the XDR scale and never below the floor at its peak.
    func testPropertiesOverRandomAdjustments() {
        var rng = SeededGenerator(seed: 0x6A33A)
        func r(_ range: ClosedRange<Double>) -> Double {
            range.lowerBound + Double(rng.next() % 10_000) / 10_000 * (range.upperBound - range.lowerBound)
        }
        for _ in 0..<300 {
            var a = ColorAdjustments()
            a.contrast = r(ColorAdjustments.contrastRange)
            a.gamma = r(ColorAdjustments.gammaRange)
            a.redGamma = r(ColorAdjustments.gammaRange)
            a.red = r(ColorAdjustments.gainRange)
            a.gain = r(ColorAdjustments.gainRange)
            a.temperature = r(ColorAdjustments.temperatureRange)
            a.blackLevel = r(ColorAdjustments.blackLevelRange)
            a.whiteLevel = r(ColorAdjustments.whiteLevelRange)
            a.inverted = rng.next() % 4 == 0
            let floor = rng.next() % 2 == 0 ? 0.08 : 0
            let xdr = rng.next() % 3 == 0 ? r(1...3) : 1
            let inputs = GammaMath.Inputs(adjustments: a, brightness: r(0...1), xdrScale: xdr, floor: floor)
            let t = GammaMath.compose(baseline: nil, inputs: inputs, samples: 256)
            XCTAssertTrue(t.isValid)
            XCTAssertLessThanOrEqual(Double(t.peak), max(1, xdr) + 1e-4)
            XCTAssertGreaterThanOrEqual(Double(t.peak), floor - 1e-4)
            for c in 0..<3 {
                let ch = t.channel(c)
                for i in 1..<ch.count {
                    if a.inverted {
                        XCTAssertLessThanOrEqual(ch[i], ch[i - 1] + 1e-6)
                    } else {
                        XCTAssertGreaterThanOrEqual(ch[i], ch[i - 1] - 1e-6)
                    }
                }
            }
        }
    }
}
