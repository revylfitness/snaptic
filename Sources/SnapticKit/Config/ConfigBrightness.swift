import Foundation

// Brightness settings (owner: C). Every field has a default, decodes lossily and is
// clamped in sanitized() (TEAMS rule 9).

package enum BrightnessMethod: String, Codable, CaseIterable, Sendable {
    case apple, ddc, gamma, overlay

    package var isHardware: Bool { self == .apple || self == .ddc }

    package var feature: DisplayFeature {
        switch self {
        case .apple: return .brightnessApple
        case .ddc: return .brightnessDDC
        case .gamma: return .brightnessGamma
        case .overlay: return .brightnessOverlay
        }
    }

    package var title: String {
        switch self {
        case .apple: return L("Apple native")
        case .ddc: return L("DDC (monitor hardware)")
        case .gamma: return L("Color table (gamma)")
        case .overlay: return L("Overlay")
        }
    }
}

/// What "Restore on launch/wake" restores (parity §4.5).
package enum BrightnessRestoreMode: String, Codable, CaseIterable, Sendable {
    case brightness, adjustmentsOnly, off

    package var title: String {
        switch self {
        case .brightness: return L("Brightness and adjustments")
        case .adjustmentsOnly: return L("Adjustments only")
        case .off: return L("Don't restore")
        }
    }
}

/// XDR upscaling method (PLAN §6.4).
package enum XDRMethod: String, Codable, CaseIterable, Sendable {
    case automatic
    /// A: EDR overlay multiply (needs the overlay method).
    case overlay
    /// B: EDR trigger plus gamma above 1 (needs the gamma method; Apple silicon).
    case gamma

    package var title: String {
        switch self {
        case .automatic: return L("Automatic")
        case .overlay: return L("Overlay (A)")
        case .gamma: return L("Color table (B)")
        }
    }
}

package struct BrightnessConfig: ConfigModel {
    package var restoreMode: BrightnessRestoreMode
    /// 150 ms ramps (never with Reduce Motion).
    package var smoothTransitions: Bool
    /// Dim on lock target (0.1…1); gamma, 10% floor.
    package var dimOnLockLevel: Double
    /// Sync source; nil = the built-in display.
    package var syncSource: DisplayKey?
    package var syncMode: SyncMode
    /// Follow changes made outside Snaptic (for DDC sources this needs readback).
    package var syncExternalChanges: Bool
    /// Sync switched off from the menu or a shortcut (the feature stays on).
    package var syncPaused: Bool
    /// XDR user maximum (1.01…4.0, default 1.6).
    package var xdrMaxScale: Double
    package var xdrMethod: XDRMethod
    /// Battery level below which XDR pauses (0.2…0.9; 20% is the hard minimum).
    package var xdrBatteryFloor: Double
    package var xdrPauseOnLowPower: Bool
    /// OSD detent at 100% with hysteresis.
    package var xdrDetent: Bool
    /// Show nits next to the slider and in the OSD (when `nits` is effective).
    package var showNits: Bool

    /// Restore never goes below this.
    package static let restoreFloor = 0.15
    /// Software dimming floor without dim to black (PLAN §4.2 invariant 3).
    package static let dimFloor = 0.08
    /// Dim on lock floor.
    package static let dimOnLockFloor = 0.1
    package static let xdrScaleRange: ClosedRange<Double> = 1.01...4.0
    package static let batteryFloorRange: ClosedRange<Double> = 0.2...0.9

    package init() {
        restoreMode = .brightness
        smoothTransitions = true
        dimOnLockLevel = 0.5
        syncSource = nil
        syncMode = .absolute
        syncExternalChanges = true
        syncPaused = false
        xdrMaxScale = 1.6
        xdrMethod = .automatic
        xdrBatteryFloor = 0.2
        xdrPauseOnLowPower = true
        xdrDetent = true
        showNits = true
    }

    private enum CodingKeys: String, CodingKey {
        case restoreMode, smoothTransitions, dimOnLockLevel, syncSource, syncMode, syncExternalChanges, syncPaused, xdrMaxScale,
             xdrMethod, xdrBatteryFloor, xdrPauseOnLowPower, xdrDetent, showNits
    }

    package init(from decoder: Decoder) throws {
        let d = BrightnessConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        restoreMode = c.lossy(.restoreMode, d.restoreMode)
        smoothTransitions = c.lossy(.smoothTransitions, d.smoothTransitions)
        dimOnLockLevel = c.lossy(.dimOnLockLevel, d.dimOnLockLevel)
        syncSource = c.lossy(.syncSource, nil as DisplayKey?)
        syncMode = c.lossy(.syncMode, d.syncMode)
        syncExternalChanges = c.lossy(.syncExternalChanges, d.syncExternalChanges)
        syncPaused = c.lossy(.syncPaused, false)
        xdrMaxScale = c.lossy(.xdrMaxScale, d.xdrMaxScale)
        xdrMethod = c.lossy(.xdrMethod, d.xdrMethod)
        xdrBatteryFloor = c.lossy(.xdrBatteryFloor, d.xdrBatteryFloor)
        xdrPauseOnLowPower = c.lossy(.xdrPauseOnLowPower, d.xdrPauseOnLowPower)
        xdrDetent = c.lossy(.xdrDetent, d.xdrDetent)
        showNits = c.lossy(.showNits, d.showNits)
    }

    package func sanitized() -> BrightnessConfig {
        var c = self
        c.dimOnLockLevel = ConfigClamp.value(dimOnLockLevel, Self.dimOnLockFloor...1, fallback: 0.5)
        c.xdrMaxScale = ConfigClamp.value(xdrMaxScale, Self.xdrScaleRange, fallback: 1.6)
        c.xdrBatteryFloor = ConfigClamp.value(xdrBatteryFloor, Self.batteryFloorRange, fallback: 0.2)
        return c
    }
}

package struct PerDisplayBrightness: ConfigModel {
    /// Method override; nil = automatic.
    package var method: BrightnessMethod?
    /// Last combined slider position (0…1, SDR) for restore.
    package var value: Double?
    /// Switchover override; nil = the method's default.
    package var switchover: Double?
    /// Lowest hardware level the slider uses (0…0.99).
    package var minHardware: Double
    package var xdrEnabled: Bool
    /// Per-display XDR maximum, ≤ the global cap.
    package var xdrMax: Double?
    /// User-edited nits range; nil = model default.
    package var nits: NitsRange?
    /// Answer to "Did it get darker?" for gamma (nil = not asked yet).
    package var gammaWorks: Bool?
    /// XDR calibration answers ("Is it brighter?") per method.
    package var xdrOverlayWorks: Bool?
    package var xdrGammaWorks: Bool?
    /// Takes part in brightness sync as a target.
    package var syncEnabled: Bool
    /// Sync offset (−0.5…0.5).
    package var syncOffset: Double

    package init() {
        method = nil
        value = nil
        switchover = nil
        minHardware = 0
        xdrEnabled = false
        xdrMax = nil
        nits = nil
        gammaWorks = nil
        xdrOverlayWorks = nil
        xdrGammaWorks = nil
        syncEnabled = true
        syncOffset = 0
    }

    private enum CodingKeys: String, CodingKey {
        case method, value, switchover, minHardware, xdrEnabled, xdrMax, nits, gammaWorks, xdrOverlayWorks,
             xdrGammaWorks, syncEnabled, syncOffset
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        method = c.lossy(.method, nil as BrightnessMethod?)
        value = c.lossy(.value, nil as Double?)
        switchover = c.lossy(.switchover, nil as Double?)
        minHardware = c.lossy(.minHardware, 0.0)
        xdrEnabled = c.lossy(.xdrEnabled, false)
        xdrMax = c.lossy(.xdrMax, nil as Double?)
        nits = c.lossy(.nits, nil as NitsRange?)
        gammaWorks = c.lossy(.gammaWorks, nil as Bool?)
        xdrOverlayWorks = c.lossy(.xdrOverlayWorks, nil as Bool?)
        xdrGammaWorks = c.lossy(.xdrGammaWorks, nil as Bool?)
        syncEnabled = c.lossy(.syncEnabled, true)
        syncOffset = c.lossy(.syncOffset, 0.0)
    }

    package func sanitized() -> PerDisplayBrightness {
        var c = self
        c.value = value.map { ConfigClamp.value($0, 0...1, fallback: 1) }
        c.switchover = switchover.map { ConfigClamp.value($0, 0...0.99, fallback: 0) }
        c.minHardware = ConfigClamp.value(minHardware, 0...0.99, fallback: 0)
        c.xdrMax = xdrMax.map { ConfigClamp.value($0, BrightnessConfig.xdrScaleRange, fallback: 1.6) }
        c.nits = nits?.sanitized()
        c.syncOffset = ConfigClamp.value(syncOffset, -0.5...0.5, fallback: 0)
        return c
    }
}

/// Shared clamping helpers for C's config files.
package enum ConfigClamp {
    package static func value(_ v: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard v.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, v))
    }

    package static func int(_ v: Int, _ range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, v))
    }

    /// Sanitized display text (≤ `max` scalars).
    package static func text(_ s: String, max: Int = 64) -> String {
        TextSanitizer.clean(s, maxScalars: max)
    }
}
