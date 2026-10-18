import Foundation

/// Whether a newly seen display waits for its first DDC read before brightness manages it
/// (FIXES-R2 W17b). Starting with software dimming at 100% and switching to DDC when the
/// probe answers would then write that 100% to the monitor; waiting reads the monitor's
/// own level first. Menus show "Reading brightness…" meanwhile.
package enum BrightnessFirstRead {
    /// After this long without an answer, manage the display with what works (the probe
    /// may be held off after wake or the transport may never open).
    package static let maxWaitSeconds: Double = 10

    /// - Parameters:
    ///   - initialized: brightness already manages the display.
    ///   - hardwareChosen: a hardware method (Apple, DDC) is usable now.
    ///   - softwareOverride: the user chose a software method for this display.
    ///   - ddcCandidate: DDC brightness is on and the display is a wired external.
    ///   - ddcUnknown: the DDC link hasn't answered or failed yet.
    ///   - waited: seconds since the display was first seen.
    package static func shouldWait(initialized: Bool, hardwareChosen: Bool, softwareOverride: Bool,
                                   ddcCandidate: Bool, ddcUnknown: Bool, waited: Double) -> Bool {
        guard !initialized, !hardwareChosen, !softwareOverride, ddcCandidate, ddcUnknown else { return false }
        guard waited.isFinite, waited >= 0 else { return false }
        return waited < maxWaitSeconds
    }
}
