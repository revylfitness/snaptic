import AppKit
import CoreGraphics
import SnapticKit

/// Where module menus go (PLAN §3.5): the shared status item, an icon of their own, or
/// nowhere (then Settings, shortcuts and a relaunch still reach everything).
enum MenuPlacement {
    static let defaultSharedSymbol = "rectangle.on.rectangle"

    static func title(_ choice: MenuPlacementChoice) -> String {
        switch choice {
        case .shared: return L("In Snaptic's menu")
        case .ownIcon: return L("Own menu bar icon")
        case .hidden: return L("Hidden")
        }
    }

    static func title(_ visibility: MenuItemVisibility) -> String {
        switch visibility {
        case .visible: return L("Visible")
        case .inSubmenu: return L("In submenu")
        case .hidden: return L("Hidden")
        }
    }

    /// The SF Symbol of a module's own icon.
    @MainActor static func symbol(for module: any SnapticModule, in config: ModulesConfig) -> String {
        let chosen = config.preferences(module.id).symbol
        return chosen.isEmpty ? module.symbolName : chosen
    }

    static func sharedSymbol(in config: ModulesConfig) -> String {
        config.sharedSymbol.isEmpty ? defaultSharedSymbol : config.sharedSymbol
    }

    /// Any online display that isn't built in (cheap: CG display list only).
    @MainActor static var hasExternalDisplay: Bool {
        CGDirectDisplayID.online().contains { !$0.isBuiltin }
    }
}
