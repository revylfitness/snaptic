import AppKit
import ApplicationServices

enum Permissions {
    /// Needed to read windows, focus them, and listen for the shortcut.
    static var accessibility: Bool { AXIsProcessTrusted() }

    /// Needed for thumbnails and for titles of windows on other Spaces.
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    static func promptAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        openPrivacyPane("Privacy_ScreenCapture")
    }

    private static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
