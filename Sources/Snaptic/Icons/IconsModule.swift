import AppKit
import SwiftUI
import SnapticKit

/// The Hidden Icons module (lead; PLAN 0.4 §2, H1). K1 shell: the host knows the fourth module, and the module
/// creates nothing. A5 replaces it with the real module (stores, engines, items, monitors).
@MainActor final class IconsModule: SnapticModule {
    let id: ModuleID = .hiddenIcons
    let title = L("Hidden Icons")
    let symbolName = "eye.slash.fill"
    let summary = L("Hide the menu bar icons you don’t need behind an arrow.")
    private(set) var state: ModuleState = .stopped
    var tint: SettingsTint { .teal }

    /// H4 arrives with A5; the shell needs nothing.
    var requiredPermissions: Set<Permission> { [] }

    init() {}

    // MARK: SnapticModule

    func start(_ context: ModuleContext) {
        guard state == .stopped else { return }
        state = .running
    }

    func stop() {
        state = .stopped
    }

    func menuSection() -> [NSMenuItem] { [] }

    func settingsRoot() -> SettingsRoot {
        let module = self
        return SettingsRoot(id: SettingsRootID.hiddenIcons, title: title, symbol: symbolName, tint: tint) {
            AnyView(IconsShellPage(title: module.title, symbol: module.symbolName, tint: module.tint))
        }
    }
}

/// The K1 placeholder page; A7 replaces it with `IconsPage`.
private struct IconsShellPage: View {
    let title: String
    let symbol: String
    let tint: SettingsTint

    var body: some View {
        SettingsPageScaffold(route: SettingsRoute(SettingsRootID.hiddenIcons)) {
            SettingsPageHeader(title,
                               summary: L("Keep your menu bar tidy: click the arrow to hide the icons to its left, and click again to show them."),
                               symbol: symbol, tint: tint)
        }
    }
}
