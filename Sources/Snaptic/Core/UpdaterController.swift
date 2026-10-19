import AppKit
import SnapticKit

// In-app updates (owner: T-update; PLAN 0.3.1 E4): wraps Sparkle's standard updater controller. The only file allowed to
// import Sparkle (lint L19); every Sparkle symbol is reached only after `Bundle(identifier:
// "org.sparkle-project.Sparkle") != nil`, so a build without the framework never touches it.
//
// Step 0 stub: the host-facing protocol; no Sparkle yet.

/// What the host, StatusMenu, the About page and Relauncher use (`ModuleHost.updater`).
@MainActor protocol UpdaterControlling: AnyObject {
    /// About's "Check for updates automatically" (Snaptic sets it from the user's consent, never Sparkle's prompt).
    var automaticallyChecksForUpdates: Bool { get set }
    /// About's "Download and install updates automatically" (never for root-owned copies).
    var automaticallyDownloadsUpdates: Bool { get set }
    /// The update Snaptic's own rows offer (gentle reminders), or nil.
    var availableUpdate: UpdateOffer? { get }
    /// Sparkle handed over an install-on-quit block (Relauncher calls it).
    var hasPendingQuitInstall: Bool { get }
    /// Check for Updates… (also in Safe Mode).
    func checkForUpdates()
    /// The menu row and About's Install and Relaunch…: Sparkle's window comes forward, or the pending install runs
    /// once UpdatePolicy allows it.
    func installUpdate()
}

/// Step 0 stub: never created (`ModuleHost.updater` stays nil).
@MainActor final class UpdaterController {
    init() {}
}
