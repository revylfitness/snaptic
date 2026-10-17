import AppKit
import SwiftUI
import SnapticKit

// Module protocols and value types (lead-owned contract; R5.1: no classes here).

enum ModuleState: Equatable {
    case stopped
    case running
    case degraded(String)
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

/// A top-level utility (Window Switcher, Displays). PLAN §3.3.
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
    func settingsPages() -> [SettingsPage]
}
