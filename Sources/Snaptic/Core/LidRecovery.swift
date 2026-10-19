import AppKit
import Combine
import SnapticKit

// Host-level recovery from lid-closed mode (owner: T-lid-app; PLAN 0.3.1 B3.4): at launch (AppDelegate step 7, beside
// RevertJournal, whatever Awake's state, also in Safe Mode) it classifies the journal and SleepDisabled; while sleep
// was left off it drives the leftover rows in every menu, on the Awake page and under Other Apps, and their buttons.
//
// Step 0 stub: nothing to recover, so no row ever shows. The interface is what StatusMenu (T-menu), IndicatorController
// and the Awake pages read.

/// `ModuleHost.lidRecovery`.
@MainActor final class LidRecoveryState: ObservableObject {
    /// The B3.4 classification (`.nothing` while there's no Snaptic journal).
    @Published private(set) var recovery: AwakeLidRecovery = .nothing
    /// Not Now: the rows stay hidden until the next launch.
    @Published private(set) var dismissed = false

    init() {}

    /// The leftover rows show ("Sleep Is Turned Off", Turn Sleep Back On…).
    var showsRows: Bool { recovery == .leftover && !dismissed }

    /// Turning lid-closed mode on is refused (B2: journal pending, or a leftover).
    var blocksTurnOn: Bool { recovery == .pending || recovery == .leftover }

    /// Turn Sleep Back On… (asks for the password; runs `LidWatchdog.restoreScript`). Stub: does nothing.
    func turnSleepBackOn() {}

    /// Keep Sleep Off: clears the journal and removes the rows everywhere; no prompt, no root. Stub: does nothing.
    func keepSleepOff() {}

    /// Not Now: hides the rows everywhere until the next launch.
    func notNow() { dismissed = true }
}
