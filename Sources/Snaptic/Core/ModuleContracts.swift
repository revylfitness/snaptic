import AppKit
import SwiftUI
import SnapticKit

// Module protocols and value types (lead-owned contract; R5.1: no classes here).

enum ModuleState: Equatable {
    case stopped
    case running
    case degraded(String)
}

/// Whether a feature can run here (moved from DisplaysContracts in 0.3 so Awake doesn't depend on a Displays file).
enum FeatureAvailability: Equatable {
    case available
    case unavailable(String)

    var isAvailable: Bool { self == .available }
}

struct SafeModeState: Sendable, Equatable {
    let isActive: Bool
    let reason: String?
    static let off = SafeModeState(isActive: false, reason: nil)
}

/// A page in the Settings sidebar. Identity and hashing use `id` only.
struct SettingsPage: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let makeView: @MainActor () -> AnyView

    static func == (a: SettingsPage, b: SettingsPage) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - 0.3 settings shell contracts (PLAN 0.3 §4.1; the shell itself is H's SettingsShell)

/// Icon tile tint of a sidebar row or page header.
enum SettingsTint: String {
    case gray, graphite, blue, indigo, orange, green, red, purple, teal

    var color: Color {
        switch self {
        case .gray: return .gray
        case .graphite: return Color(nsColor: .darkGray)
        case .blue: return .blue
        case .indigo: return .indigo
        case .orange: return .orange
        case .green: return .green
        case .red: return .red
        case .purple: return .purple
        case .teal: return .teal
        }
    }
}

/// One "what this does" row shown while a module or feature group is off.
struct FeatureHighlight: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let text: String
}

/// A sidebar root. Identity and hashing use `id` only (closure property).
struct SettingsRoot: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let tint: SettingsTint
    let makeView: @MainActor () -> AnyView

    static func == (a: SettingsRoot, b: SettingsRoot) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Every page, sheet, section view and menu builder names its control table (§4.8): the declaration sits next to
/// the type by name while the data is in Kit, where the Linux test sees it.
@MainActor protocol ControlDeclaring {
    associatedtype Controls: ControlTable
}

// MARK: - Status items (PLAN 0.3 §2.11, §5.2)

/// What the host's plan asks a provider-built item to be (StatusItemPlan; code B3).
struct CustomItemRow: Equatable {
    /// StatusItemPlan.custom contains the module.
    let exists: Bool
    let presence: MenuPresence
    /// StatusItemPlan.sharedFooterInOwnMenus: add Recent Notices ›, Quit Snaptic.
    let footer: Bool
    /// Notices exist (with footer).
    let recentNotices: Bool
}

/// A module with a custom item builds it ONLY inside `applyStatusItem`, so the Kit plan and the item can't diverge
/// for a turn (code R2-M6).
@MainActor protocol StatusItemProvider: AnyObject {
    /// nil while the item doesn't exist.
    var statusItem: NSStatusItem? { get }
    /// Called from StatusMenu.applyPlan, in the same turn as the plan.
    func applyStatusItem(_ row: CustomItemRow)
}

/// A top-level utility (Window Switcher, Displays, Awake). PLAN §3.3.
@MainActor protocol SnapticModule: AnyObject {
    var id: ModuleID { get }
    var title: String { get }
    var symbolName: String { get }
    var summary: String { get }
    var state: ModuleState { get }
    /// Permissions needed for the current settings.
    var requiredPermissions: Set<Permission> { get }
    /// Idempotent.
    func start(_ context: ModuleContext)
    /// Synchronous, idempotent, never shows UI; resolves pending trials as Revert and
    /// undoes session/overlay/gamma/virtual/capture/helper state.
    func stop()
    func menuSection() -> [NSMenuItem]
    /// 0.2 pages; removed at the 0.3 step-3 exit (code R2-M2a).
    func settingsPages() -> [SettingsPage]
    // 0.3 (§4.1), with extension defaults so existing conformers compile:
    var tint: SettingsTint { get }
    /// Off-state block.
    var highlights: [FeatureHighlight] { get }
    /// Rendered whether running or not.
    func settingsRoot() -> SettingsRoot
    func settingsDestination(_ route: SettingsRoute) -> AnyView?
    /// Static per module; computed once.
    func settingsIndex() -> [SettingsSearchEntry]
}

extension SnapticModule {
    var tint: SettingsTint { .gray }
    var highlights: [FeatureHighlight] { [] }

    /// Wraps the module's 0.2 `settingsPages()` content until each module provides its own root.
    func settingsRoot() -> SettingsRoot {
        let pages = settingsPages()
        let moduleID = id
        return SettingsRoot(id: id.rawValue, title: title, symbol: symbolName, tint: tint) {
            AnyView(LegacyModuleHub(moduleID: moduleID, pages: pages))
        }
    }

    func settingsDestination(_ route: SettingsRoute) -> AnyView? { nil }
    func settingsIndex() -> [SettingsSearchEntry] { [] }
}
