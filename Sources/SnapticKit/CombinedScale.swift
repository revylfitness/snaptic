import Foundation

/// The combined brightness slider (PLAN §6.1, parity §4.2): one position spans software
/// dimming → hardware range → XDR upscaling.
///
/// Position 0…1 is SDR; above 1 is the XDR boost factor (up to `xdrMax`). Below the
/// switchover the hardware sits at its minimum and software dims; above it software is
/// neutral and the hardware moves from `minHardware` to 1.
package struct CombinedScale: Equatable, Sendable {
    package var hasHardware: Bool
    package var hasSoftware: Bool
    /// Position where the hardware reaches its minimum (0…0.99). 0 = pure hardware.
    package var switchover: Double
    /// Lowest hardware level the slider uses (0…0.99), e.g. to stay above PWM flicker.
    package var minHardware: Double
    /// Software factor at position 0 (0.08 floor normally, 0 with dim to black).
    package var softwareFloor: Double
    /// Largest position (1 = no XDR).
    package var xdrMax: Double

    package struct Output: Equatable, Sendable {
        /// Hardware level 0…1, nil without a hardware method.
        package var hardware: Double?
        /// Software factor 0…1.
        package var software: Double
        /// XDR boost factor (1 = none).
        package var xdr: Double

        package init(hardware: Double?, software: Double, xdr: Double) {
            self.hardware = hardware
            self.software = software
            self.xdr = xdr
        }
    }

    package init(hasHardware: Bool, hasSoftware: Bool, switchover: Double, minHardware: Double = 0,
                 softwareFloor: Double = 0.08, xdrMax: Double = 1) {
        self.hasHardware = hasHardware
        self.hasSoftware = hasSoftware
        self.switchover = Self.clamp(switchover, 0, 0.99)
        self.minHardware = Self.clamp(minHardware, 0, 0.99)
        self.softwareFloor = Self.clamp(softwareFloor, 0, 1)
        self.xdrMax = max(1, min(4, xdrMax.isFinite ? xdrMax : 1))
    }

    /// Defaults: 25% for Apple native, 0% for DDC (pure hardware), 20% while XDR is on;
    /// software-only displays use the whole range.
    package static func defaultSwitchover(hardware: BrightnessMethod?, xdrOn: Bool) -> Double {
        if xdrOn { return 0.2 }
        switch hardware {
        case .apple?: return 0.25
        case .ddc?: return 0
        default: return 0
        }
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        guard v.isFinite else { return lo }
        return min(hi, max(lo, v))
    }

    package var range: ClosedRange<Double> { 0...xdrMax }

    /// Whether the slider has a software segment below the switchover.
    package var isCombined: Bool { hasHardware && hasSoftware && switchover > 0 }

    package func split(_ position: Double) -> Output {
        let p = Self.clamp(position, 0, xdrMax)
        if p > 1 {
            return Output(hardware: hasHardware ? 1 : nil, software: 1, xdr: p)
        }
        if isCombined {
            if p >= switchover {
                let t = (p - switchover) / (1 - switchover)
                return Output(hardware: minHardware + t * (1 - minHardware), software: 1, xdr: 1)
            }
            let t = p / switchover
            return Output(hardware: minHardware, software: softwareFloor + t * (1 - softwareFloor), xdr: 1)
        }
        if hasHardware {
            return Output(hardware: minHardware + p * (1 - minHardware), software: 1, xdr: 1)
        }
        return Output(hardware: nil, software: softwareFloor + p * (1 - softwareFloor), xdr: 1)
    }

    /// The position that produces (approximately) these levels; used when the hardware
    /// changed outside Snaptic.
    package func position(hardware: Double?, software: Double, xdr: Double = 1) -> Double {
        if xdr > 1, xdr.isFinite { return Self.clamp(xdr, 1, xdrMax) }
        let sw = Self.clamp(software, 0, 1)
        func hwPart(_ h: Double) -> Double {
            guard minHardware < 1 else { return 1 }
            return Self.clamp((Self.clamp(h, 0, 1) - minHardware) / (1 - minHardware), 0, 1)
        }
        func swPart() -> Double {
            guard softwareFloor < 1 else { return 1 }
            return Self.clamp((sw - softwareFloor) / (1 - softwareFloor), 0, 1)
        }
        if isCombined {
            if sw < 1 - 1e-12 { return switchover * swPart() }
            return switchover + hwPart(hardware ?? 1) * (1 - switchover)
        }
        if hasHardware { return hwPart(hardware ?? 1) }
        return swPart()
    }

    /// "Min HW" and "Max HW" snap marks.
    package var snapMarks: [Double] {
        var marks: [Double] = []
        if isCombined { marks.append(switchover) }
        if xdrMax > 1 { marks.append(1) }
        return marks
    }

    /// Snaps a dragged position onto a nearby mark.
    package func snapped(_ position: Double, threshold: Double = 0.015) -> Double {
        for mark in snapMarks where abs(position - mark) <= threshold { return mark }
        return Self.clamp(position, 0, xdrMax)
    }

    /// XDR detent: a press that would cross 100% stops at 100% first; the second press
    /// within the hysteresis window continues (PLAN §6.4).
    package static func applyDetent(from old: Double, to new: Double, armed: Bool) -> (value: Double, armDetent: Bool) {
        let crossesUp = old < 1 && new > 1
        let crossesDown = old > 1 && new < 1
        if (crossesUp || crossesDown) && !armed { return (1, true) }
        return (new, false)
    }
}
