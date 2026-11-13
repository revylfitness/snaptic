import Foundation

// Dock Previews' settings store (lead; PLAN 0.5 §2.1, H10). `SnapticDockV1` holds every Dock Previews setting, and a
// backup carries all of them. "Protect private windows" and the protected apps aren't here: they stay in the
// switcher's `Config`, which both modules read (§4.10).

/// “Card size” (§4.18).
package enum DockCardSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large
}

/// “When you click the active app in the Dock” (§4.11).
package enum DockClickAction: String, Codable, CaseIterable, Sendable {
    case doNothing
    /// “Hide the App”, like ⌘H.
    case hideApp
    /// “Minimize Its Windows”.
    case minimizeWindows
}

/// Advanced › “Sort windows by” (§4.18, Y-13).
package enum DockSort: String, Codable, CaseIterable, Sendable {
    case recentlyUsed
    case minimizedAndHiddenLast
    case title
}

/// `SnapticDockV1`: the Dock Previews settings (H10).
package struct DockConfig: ConfigModel {
    package static let key = "SnapticDockV1"
    /// “Show previews after”: 0 to 1 s (§4.18).
    package static let delayRange: ClosedRange<Double> = 0...1
    package static let defaultDelay = 0.2
    /// “Apps hidden from Dock previews” keeps at most this many apps, as the switcher's lists do.
    package static let hiddenBundleIDsCap = 200

    /// “Show previews after”, in seconds; 0 reads “Immediately”.
    package var delay: Double
    /// “Card size”.
    package var cardSize: DockCardSize
    /// “Window thumbnails”: off shows titles only and needs no Screen Recording (§4.14).
    package var thumbnails: Bool
    /// “Include minimized and hidden windows”.
    package var includeMinimizedAndHidden: Bool
    /// “Windows on other Spaces”.
    package var otherSpaces: Bool
    /// “When you click the active app in the Dock” (§4.11; opt-in).
    package var clickActions: DockClickAction
    /// “Restore all minimized windows” (§4.11; opt-in).
    package var restoreAllMinimized: Bool
    /// Advanced › “Sort windows by”.
    package var sort: DockSort
    /// Advanced › “Keyboard shortcuts in previews” (§4.5).
    package var keys: Bool
    /// Advanced › “Apps with no open windows”: a small card instead of nothing.
    package var windowlessApps: Bool
    /// Advanced › “When another app shows Dock previews”: false is Pause Dock Previews, true is Run Both Anyway
    /// (§4.15).
    package var runAlongsideOtherTools: Bool
    /// Advanced › “Show previews while VoiceOver is on” (§4.16).
    package var showWithVoiceOver: Bool
    /// Advanced › “Apps hidden from Dock previews” (G2-4, D2-24): bundle ids whose Dock items never show a panel.
    package var hiddenBundleIDs: [String]

    package init() {
        delay = Self.defaultDelay
        cardSize = .medium
        thumbnails = true
        includeMinimizedAndHidden = true
        otherSpaces = true
        clickActions = .doNothing
        restoreAllMinimized = false
        sort = .recentlyUsed
        keys = true
        windowlessApps = true
        runAlongsideOtherTools = false
        showWithVoiceOver = false
        hiddenBundleIDs = []
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case delay, cardSize, thumbnails, includeMinimizedAndHidden, otherSpaces, clickActions, restoreAllMinimized,
             sort, keys, windowlessApps, runAlongsideOtherTools, showWithVoiceOver, hiddenBundleIDs
    }

    /// The keys a backup carries (H10): every setting, “Apps hidden from Dock previews” included.
    package static let exportedKeys: [String] = CodingKeys.allCases.map(\.stringValue)

    /// Field by field: a bad value falls back to its default without touching the others.
    package init(from decoder: Decoder) throws {
        let d = DockConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        delay = c.lossy(.delay, d.delay)
        cardSize = c.lossy(.cardSize, d.cardSize)
        thumbnails = c.lossy(.thumbnails, d.thumbnails)
        includeMinimizedAndHidden = c.lossy(.includeMinimizedAndHidden, d.includeMinimizedAndHidden)
        otherSpaces = c.lossy(.otherSpaces, d.otherSpaces)
        clickActions = c.lossy(.clickActions, d.clickActions)
        restoreAllMinimized = c.lossy(.restoreAllMinimized, d.restoreAllMinimized)
        sort = c.lossy(.sort, d.sort)
        keys = c.lossy(.keys, d.keys)
        windowlessApps = c.lossy(.windowlessApps, d.windowlessApps)
        runAlongsideOtherTools = c.lossy(.runAlongsideOtherTools, d.runAlongsideOtherTools)
        showWithVoiceOver = c.lossy(.showWithVoiceOver, d.showWithVoiceOver)
        hiddenBundleIDs = c.lossyArray(.hiddenBundleIDs, d.hiddenBundleIDs)
    }

    /// The delay within 0…1 s (NaN → the default; ±∞ → the nearer end); valid bundle ids only, each once, at most
    /// `hiddenBundleIDsCap`.
    package func sanitized() -> DockConfig {
        var c = self
        if delay.isNaN {
            c.delay = Self.defaultDelay
        } else {
            c.delay = min(max(delay, Self.delayRange.lowerBound), Self.delayRange.upperBound)
        }
        c.hiddenBundleIDs = Array(hiddenBundleIDs.filter(AwakeBundleID.isValid).uniqued().prefix(Self.hiddenBundleIDsCap))
        return c
    }

    /// What the module needs for these settings (§4.14): Accessibility, plus Screen Recording while Window thumbnails
    /// is on.
    package var requiredPermissions: Set<Permission> {
        thumbnails ? [.accessibility, .screenRecording] : [.accessibility]
    }
}
