import AppKit
import CoreGraphics
import SnapticKit

/// Where module menus go (PLAN §3.5, 0.3 §5.2): the Snaptic item, an icon of their own (always or while active), or
/// nowhere (then Settings, shortcuts and a relaunch still reach everything). The `MenuPlacementChoice` titles are
/// 0.2's and go at the 0.3 step-3 exit; 0.3 UI uses the `MenuPresence` titles.
enum MenuPlacement {
    static let defaultSharedSymbol = "rectangle.on.rectangle"

    static func title(_ choice: MenuPlacementChoice) -> String {
        switch choice {
        case .shared: return L("In Snaptic's menu")
        case .ownIcon: return L("Own menu bar icon")
        case .hidden: return L("Hidden")
        }
    }

    /// The Menu Bar page's presence pop-up (C2, Control Center wording; one option order for every module).
    static func title(_ presence: MenuPresence) -> String {
        switch presence {
        case .ownIcon: return L("Always Show in Menu Bar")
        case .ownIconWhenActive: return L("Show When Active")
        case .inSnapticMenu: return L("Show in Snaptic Menu")
        case .hidden: return L("Don't Show")
        }
    }

    /// Help under a presence choice (§4.3 Menu Bar), when it needs one.
    static func help(_ presence: MenuPresence, for id: ModuleID) -> String? {
        switch (presence, id) {
        case (.ownIconWhenActive, .displays): return L("Shows the icon while an external display is connected.")
        case (.ownIconWhenActive, .awake): return L("Shows the icon while your Mac is being kept awake.")
        case (.hidden, _): return L("Use the keyboard shortcut or Settings to reach it.")
        default: return nil
        }
    }

    /// The presence choices a module's pop-up offers, in menu order (Show When Active only for Displays and Awake).
    static func presences(for id: ModuleID) -> [MenuPresence] { MenuPresence.allowed(for: id) }

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
