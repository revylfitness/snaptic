import AppKit
import SnapticKit

/// The one "Leave Safe Mode…" confirmation (review round 2 ux N5): General, General Advanced, the Displays status row,
/// Awake's status row and the Snaptic menu all call `confirm(relauncher:)`, so every entry point asks the same
/// question before Snaptic restarts.
@MainActor enum SafeModeLeave {
    static var title: String { L("Leave Safe Mode?") }
    static var message: String { L("Snaptic restarts with all of your settings.") }

    /// Asks "Leave Safe Mode?" and restarts on [Restart]. From Settings the alert is a sheet on the Settings window
    /// (or its open sheet); from the menu bar or a floating panel, Snaptic comes to the front and shows it as a
    /// standalone alert.
    static func confirm(relauncher: Relauncher) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Restart"))
        alert.addButton(withTitle: L("Cancel"))
        let finish: @MainActor (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            relauncher.relaunch(reason: "leave safe mode")
        }
        NSApp.activate()
        if let window = NSApp.keyWindow, window.isVisible, window.attachedSheet == nil, !(window is NSPanel) {
            alert.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated { finish(response) }
            }
        } else {
            finish(alert.runModal())
        }
    }
}
