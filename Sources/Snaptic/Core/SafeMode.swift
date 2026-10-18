import AppKit
import SnapticKit

/// Safe Mode detection (PLAN §4.8): ⇧ held at launch, `--safe-mode`, or two consecutive
/// launches that ended in under 60 s without a clean quit.
enum SafeMode {
    @MainActor static func detect(argument: Bool, unstableLaunches: Bool) -> SafeModeState {
        if argument { return SafeModeState(isActive: true, reason: L("Started with --safe-mode.")) }
        if NSEvent.modifierFlags.contains(.shift) {
            return SafeModeState(isActive: true, reason: L("⇧ was held while Snaptic started."))
        }
        if unstableLaunches {
            return SafeModeState(isActive: true, reason: L("Snaptic quit unexpectedly twice in a row, shortly after starting."))
        }
        return .off
    }

    /// What Safe Mode skips, for the Safe Mode page and banner.
    static let skipped: [String] = [
        L("Brightness and color restore"),
        L("Virtual screen re-creation and Smart HiDPI"),
        L("Protection, layouts and remembered resolutions"),
        L("Associations and hooks"),
        L("Automatic DDC writes"),
        L("XDR"),
        L("Automatic display reconnection planning"),
    ]

    static let stillRuns: [String] = [
        L("Undoing unfinished display changes from the last run"),
        L("The window switcher and your shortcuts"),
    ]
}
