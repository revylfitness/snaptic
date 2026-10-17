import Foundation

// Color settings (owner: C): software adjustments, the custom-profile safeguard and
// the menu-bar overlays. Every field has a default, decodes lossily and is clamped.

package struct ColorConfig: ConfigModel {
    /// Keep gamma dimming and color adjustments even while a custom ColorSync profile is
    /// active (the safeguard's override; parity §5.8).
    package var allowGammaWithCustomProfile: Bool
    /// Suspend adjustments on every display (brightness stays).
    package var suspendAll: Bool
    /// Step for color ± shortcuts (gamma, contrast) as a fraction of the range.
    package var shortcutStep: Double
    /// Step for temperature ± shortcuts, in kelvin.
    package var temperatureStep: Double

    package init() {
        allowGammaWithCustomProfile = false
        suspendAll = false
        shortcutStep = 0.05
        temperatureStep = 250
    }

    private enum CodingKeys: String, CodingKey { case allowGammaWithCustomProfile, suspendAll, shortcutStep, temperatureStep }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        allowGammaWithCustomProfile = c.lossy(.allowGammaWithCustomProfile, false)
        suspendAll = c.lossy(.suspendAll, false)
        shortcutStep = c.lossy(.shortcutStep, 0.05)
        temperatureStep = c.lossy(.temperatureStep, 250.0)
    }

    package func sanitized() -> ColorConfig {
        var c = self
        c.shortcutStep = ConfigClamp.value(shortcutStep, 0.01...0.25, fallback: 0.05)
        c.temperatureStep = ConfigClamp.value(temperatureStep, 50...1000, fallback: 250)
        return c
    }
}

package struct PerDisplayColor: ConfigModel {
    package var adjustments: ColorAdjustments
    /// Adjustments suspended on this display (brightness stays).
    package var suspended: Bool
    /// Black strip behind the menu bar (hides the notch).
    package var menuBarStrip: Bool
    /// Rounded corner overlays, radius as a fraction of the shorter side (0…0.03).
    package var cornerRadiusTop: Double
    package var cornerRadiusBottom: Double

    package static let cornerRange: ClosedRange<Double> = 0...0.03

    package init() {
        adjustments = ColorAdjustments()
        suspended = false
        menuBarStrip = false
        cornerRadiusTop = 0
        cornerRadiusBottom = 0
    }

    private enum CodingKeys: String, CodingKey { case adjustments, suspended, menuBarStrip, cornerRadiusTop, cornerRadiusBottom }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        adjustments = c.lossy(.adjustments, ColorAdjustments())
        suspended = c.lossy(.suspended, false)
        menuBarStrip = c.lossy(.menuBarStrip, false)
        cornerRadiusTop = c.lossy(.cornerRadiusTop, 0.0)
        cornerRadiusBottom = c.lossy(.cornerRadiusBottom, 0.0)
    }

    package func sanitized() -> PerDisplayColor {
        var c = self
        c.adjustments = adjustments.sanitized()
        c.cornerRadiusTop = ConfigClamp.value(cornerRadiusTop, Self.cornerRange, fallback: 0)
        c.cornerRadiusBottom = ConfigClamp.value(cornerRadiusBottom, Self.cornerRange, fallback: 0)
        return c
    }

    /// The adjustments to apply given the suspend switches.
    package func effectiveAdjustments(suspendAll: Bool) -> ColorAdjustments {
        (suspended || suspendAll) ? adjustments.suspended : adjustments
    }

    package var hasRoundedCorners: Bool { cornerRadiusTop > 0 || cornerRadiusBottom > 0 }
}
