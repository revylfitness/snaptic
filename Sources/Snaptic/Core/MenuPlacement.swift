import AppKit
import CoreGraphics
import SnapticKit

/// Where module menus go (PLAN §3.5, 0.3 §5.2): the Snaptic item, an icon of their own (always or while active), or
/// nowhere (then Settings, shortcuts and a relaunch still reach everything). Titles are the `MenuPresence` ones
/// (Control Center wording).
enum MenuPlacement {
    static let defaultSharedSymbol = MenuLayout.snapticSymbol

    /// The Menu Bar page's presence pop-up (C2, Control Center wording; one option order for every module).
    static func title(_ presence: MenuPresence) -> String {
        switch presence {
        case .ownIcon: return L("Always Show in Menu Bar")
        case .ownIconWhenActive: return L("Show When Active")
        case .inSnapticMenu: return L("Show in Snaptic Menu")
        case .hidden: return L("Don’t Show")
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

    /// The SF Symbol of a module's own icon.
    @MainActor static func symbol(for module: any SnapticModule, in config: ModulesConfig) -> String {
        let chosen = config.preferences(module.id).symbol
        return chosen.isEmpty ? module.symbolName : chosen
    }

    /// The Snaptic item's glyph; `ownIcons`: the modules shown with an icon of their own (the default glyph steps
    /// aside for one that already uses it, `MenuLayout.sharedSymbol`).
    @MainActor static func sharedSymbol(in config: ModulesConfig, ownIcons: [any SnapticModule]) -> String {
        MenuLayout.sharedSymbol(stored: config.sharedSymbol, ownIconSymbols: ownIconSymbols(ownIcons, in: config))
    }

    @MainActor static func ownIconSymbols(_ modules: [any SnapticModule], in config: ModulesConfig) -> [String] {
        modules.map { symbol(for: $0, in: config) }
    }

    /// Any online display that isn't built in (cheap: CG display list only).
    @MainActor static var hasExternalDisplay: Bool {
        CGDirectDisplayID.online().contains { !$0.isBuiltin }
    }
}
