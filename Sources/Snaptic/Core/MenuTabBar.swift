import AppKit
import SnapticKit

// The Snaptic menu's tab bar (owner: T-menu; PLAN 0.3.1 A2): `MenuKit.tabBar(…)` returns an item whose view is this. An
// NSView, not a MenuRowView, so it never draws the selection fill; it hosts a small segmented control, 28 pt tall.
//
// Step 0 stub: an empty view.

@MainActor final class MenuTabBarView: NSView {}
