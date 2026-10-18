import Foundation

// System authentication UI that Snaptic's dimming must never cover (owner: B). PLAN
// §4.10(10) + R5.7: full-path matching, zero-alpha and offscreen windows ignored,
// loginwindow only while locked; while one shows, full-screen overlays order out and
// gamma dim-to-black rises to ≥ 30 %. Re-check every 2 s, at most 60 s per episode.

/// One on-screen window as CGWindowListCopyWindowInfo reports it (no titles: those need
/// Screen Recording, and we never read them).
package struct WindowSample: Equatable, Sendable {
    package var ownerPath: String
    package var alpha: Double
    package var x: Double, y: Double, width: Double, height: Double
    package var layer: Int

    package init(ownerPath: String, alpha: Double, x: Double, y: Double, width: Double, height: Double, layer: Int = 0) {
        self.ownerPath = ownerPath
        self.alpha = alpha
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.layer = layer
    }
}

/// A screen rectangle in the same (global, top-left) coordinates as WindowSample.
package struct ScreenRect: Equatable, Sendable {
    package var x: Double, y: Double, width: Double, height: Double
    package init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

package enum AuthProcesses {
    /// Executable paths of the system processes that show authentication UI. [U] for the
    /// exact paths on 26/27 (Appendix D 12); several spellings are listed where they moved.
    package static let paths: Set<String> = [
        "/System/Library/Frameworks/Security.framework/Versions/A/MachServices/SecurityAgent.bundle/Contents/MacOS/SecurityAgent",
        "/System/Library/Frameworks/LocalAuthentication.framework/Support/coreautha.bundle/Contents/MacOS/coreautha",
        "/System/Library/Frameworks/LocalAuthentication.framework/Versions/A/Support/coreautha.bundle/Contents/MacOS/coreautha",
        "/System/Library/CoreServices/UserNotificationCenter.app/Contents/MacOS/UserNotificationCenter",
        "/System/Library/CoreServices/universalAccessAuthWarn.app/Contents/MacOS/universalAccessAuthWarn",
        "/System/Library/CoreServices/CoreServicesUIAgent.app/Contents/MacOS/CoreServicesUIAgent",
        "/System/Library/Frameworks/AuthenticationServices.framework/Versions/A/Support/AuthenticationServicesAgent",
        "/System/Library/Frameworks/AuthenticationServices.framework/Support/AuthenticationServicesAgent",
        loginWindowPath,
    ]
    package static let loginWindowPath = "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"

    /// Below this alpha a window is treated as invisible.
    package static let minimumAlpha = 0.05
    package static let recheckSeconds = 2.0
    package static let maxEpisodeSeconds = 60.0

    /// Whether this exact executable shows authentication UI (full path, no prefix tricks).
    package static func isAuthProcess(path: String, sessionLocked: Bool) -> Bool {
        guard paths.contains(path) else { return false }
        return path != loginWindowPath || sessionLocked
    }

    /// An auth window that a user could see: auth process, visible alpha, non-trivial size,
    /// and overlapping at least one screen.
    package static func isAuthWindow(_ w: WindowSample, screens: [ScreenRect], sessionLocked: Bool) -> Bool {
        guard isAuthProcess(path: w.ownerPath, sessionLocked: sessionLocked) else { return false }
        guard w.alpha.isFinite, w.alpha >= minimumAlpha, w.width >= 2, w.height >= 2 else { return false }
        return screens.contains { s in
            w.x < s.x + s.width && w.x + w.width > s.x && w.y < s.y + s.height && w.y + w.height > s.y
        }
    }

    package static func authWindowPresent(_ windows: [WindowSample], screens: [ScreenRect], sessionLocked: Bool) -> Bool {
        windows.contains { isAuthWindow($0, screens: screens, sessionLocked: sessionLocked) }
    }
}

/// Tracks one suppression episode. While `isSuppressing`, overlays stay ordered out and
/// gamma stays ≥ 30 %. An episode ends when the auth window goes away or after 60 s (so a
/// stuck system window can't disable dimming forever); a new one starts only after the
/// window was seen gone once.
package struct AuthEpisode: Equatable, Sendable {
    package private(set) var isSuppressing = false
    private var startedAt: Double?
    private var needsAbsence = false

    package init() {}

    /// Feeds one sample; returns true when `isSuppressing` changed.
    @discardableResult
    package mutating func update(present: Bool, at now: Double) -> Bool {
        let before = isSuppressing
        if !present {
            isSuppressing = false
            startedAt = nil
            needsAbsence = false
        } else if isSuppressing, let start = startedAt, now - start >= AuthProcesses.maxEpisodeSeconds {
            isSuppressing = false
            startedAt = nil
            needsAbsence = true
        } else if !isSuppressing && !needsAbsence {
            isSuppressing = true
            startedAt = now
        }
        return before != isSuppressing
    }

    /// How often to sample: every 2 s during an episode, else the caller's base rate.
    package func nextCheck(base: Double) -> Double { isSuppressing ? AuthProcesses.recheckSeconds : base }
}
