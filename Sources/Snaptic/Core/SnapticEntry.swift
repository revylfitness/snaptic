import AppKit
import SnapticKit
import SnapticShims

/// Process entry point. Helper modes (display guard, virtual display host,
/// command-line client) are dispatched here before AppKit starts.
enum SnapticEntry {
    static func run(_ arguments: [String]) {
        // Toolchain self-check: exercises cross-module `package` access and the
        // Objective-C shim in every build configuration and architecture.
        _ = KitProbe.selfCheck()
        _ = SNEncoding.normalizedEncoding("c24@0:8@16")

        // Snaptic runs as a menu-bar ("accessory") app: no Dock icon, no main window.
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
            withExtendedLifetime(delegate) {}
        }
    }
}
