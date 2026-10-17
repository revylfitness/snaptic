import Foundation
import SnapticKit

/// What the host gives a module when it starts.
@MainActor final class ModuleContext {
    let safeMode: SafeModeState
    let hotkeys: GlobalHotkeys
    let commands: ControlCommandRegistry
    let toasts: ToastPresenter
    let permissions: PermissionFlow
    let spawner: HelperSpawner
    let relauncher: Relauncher
    let otherApps: OtherAppsMonitor
    let lifetime: Lifetime
    let requestMenuRebuild: @MainActor () -> Void
    /// The module's settingsPages() changed (e.g. a feature turned on or off).
    let requestSettingsRefresh: @MainActor () -> Void
    /// Opens Settings, optionally at a page id.
    let openSettings: @MainActor (String?) -> Void

    init(safeMode: SafeModeState, hotkeys: GlobalHotkeys, commands: ControlCommandRegistry, toasts: ToastPresenter,
         permissions: PermissionFlow, spawner: HelperSpawner, relauncher: Relauncher, otherApps: OtherAppsMonitor,
         lifetime: Lifetime,
         requestMenuRebuild: @escaping @MainActor () -> Void,
         requestSettingsRefresh: @escaping @MainActor () -> Void = {},
         openSettings: @escaping @MainActor (String?) -> Void = { _ in }) {
        self.safeMode = safeMode
        self.hotkeys = hotkeys
        self.commands = commands
        self.toasts = toasts
        self.permissions = permissions
        self.spawner = spawner
        self.relauncher = relauncher
        self.otherApps = otherApps
        self.lifetime = lifetime
        self.requestMenuRebuild = requestMenuRebuild
        self.requestSettingsRefresh = requestSettingsRefresh
        self.openSettings = openSettings
    }
}
