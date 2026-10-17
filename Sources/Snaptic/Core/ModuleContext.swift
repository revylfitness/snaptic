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
    let lifetime: Lifetime
    let requestMenuRebuild: @MainActor () -> Void

    init(safeMode: SafeModeState, hotkeys: GlobalHotkeys, commands: ControlCommandRegistry, toasts: ToastPresenter,
         permissions: PermissionFlow, spawner: HelperSpawner, lifetime: Lifetime,
         requestMenuRebuild: @escaping @MainActor () -> Void) {
        self.safeMode = safeMode
        self.hotkeys = hotkeys
        self.commands = commands
        self.toasts = toasts
        self.permissions = permissions
        self.spawner = spawner
        self.lifetime = lifetime
        self.requestMenuRebuild = requestMenuRebuild
    }
}
