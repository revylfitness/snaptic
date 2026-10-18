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
    /// 0.3: re-plans the status items now (StatusMenu.applyPlan in this turn).
    let requestStatusPlan: @MainActor () -> Void
    /// 0.3: writes a module's menu bar presence (ModulesConfig is the host's).
    let setPresence: @MainActor (ModuleID, MenuPresence) -> Void
    /// 0.3: host facts (switcher visible, terminating, launch session started).
    let hostSignals: HostSignals

    init(safeMode: SafeModeState, hotkeys: GlobalHotkeys, commands: ControlCommandRegistry, toasts: ToastPresenter,
         permissions: PermissionFlow, spawner: HelperSpawner, relauncher: Relauncher, otherApps: OtherAppsMonitor,
         lifetime: Lifetime,
         requestMenuRebuild: @escaping @MainActor () -> Void,
         requestSettingsRefresh: @escaping @MainActor () -> Void = {},
         openSettings: @escaping @MainActor (String?) -> Void = { _ in },
         requestStatusPlan: @escaping @MainActor () -> Void = {},
         setPresence: @escaping @MainActor (ModuleID, MenuPresence) -> Void = { _, _ in },
         hostSignals: HostSignals) {
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
        self.requestStatusPlan = requestStatusPlan
        self.setPresence = setPresence
        self.hostSignals = hostSignals
    }
}
