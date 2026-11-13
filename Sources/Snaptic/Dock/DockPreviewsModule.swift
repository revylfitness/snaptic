import AppKit
import SwiftUI
import SnapticKit

/// The Dock Previews module (lead; PLAN 0.5 §2, H1). K1 shell: the host knows the fifth module, and the module
/// creates nothing. `start()` and `stop()` do nothing and the state stays `.stopped`, so an on switch costs nothing
/// until A6a replaces the shell with the real module (stores, window services, the Dock observer).
@MainActor final class DockPreviewsModule: SnapticModule {
    let id: ModuleID = .dockPreviews
    let title = L("Dock Previews")
    let symbolName = "dock.rectangle"
    let summary = L("See an app’s windows when you point at it in the Dock.")
    let state: ModuleState = .stopped
    var tint: SettingsTint { .green }

    /// H1: Accessibility until A6a reads `DockConfig.requiredPermissions` (Screen Recording while thumbnails are on).
    var requiredPermissions: Set<Permission> { [.accessibility] }

    init() {}

    // MARK: SnapticModule

    func start(_ context: ModuleContext) {}

    func stop() {}

    func menuSection() -> [NSMenuItem] { [] }

    func settingsRoot() -> SettingsRoot {
        let module = self
        return SettingsRoot(id: SettingsRootID.dockPreviews, title: title, symbol: symbolName, tint: tint) {
            AnyView(DockShellPage(title: module.title, summary: module.summary, symbol: module.symbolName,
                                  tint: module.tint))
        }
    }
}

/// The K1 placeholder page; A7 replaces it with `DockPage`.
private struct DockShellPage: View {
    let title: String
    let summary: String
    let symbol: String
    let tint: SettingsTint

    var body: some View {
        SettingsPageScaffold(route: SettingsRoute(SettingsRootID.dockPreviews)) {
            SettingsPageHeader(title, summary: summary, symbol: symbol, tint: tint)
        }
    }
}
