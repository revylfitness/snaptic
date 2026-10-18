import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

/// Sidebar selection, one NavigationStack path per root, search reveal (H, sole owner).
@MainActor final class SettingsShell: ObservableObject {
    /// Sidebar selection.
    @Published var root: String = "general"
    /// One NavigationStack path per root.
    @Published var paths: [String: [SettingsRoute]] = [:]
    @Published var openSheet: String?
    @Published var highlightedAnchor: String?
    /// Shared PerDisplayPicker selection.
    @Published var selectedDisplay: DisplayKey?
    /// R5-8: set by every externally requested open; cleared by the first mouse-down in the window.
    @Published private(set) var externalOpenPending = false

    init() {}

    func moduleEnabled(_ id: ModuleID) -> Binding<Bool> { .constant(false) }

    func push(_ route: SettingsRoute) { paths[root, default: []].append(route) }

    func pop() { _ = paths[root]?.popLast() }

    /// Sets root now, pushes the route on the next main-queue turn, opens the sheet, highlights after it appeared.
    func reveal(_ entry: SettingsSearchEntry) { root = entry.root }

    /// R5-8: false while the 1 s guard runs or while an external open is pending and the event is a keyDown.
    /// Stub: false (no session-start control exists yet).
    func mayStart() -> Bool { false }
}
