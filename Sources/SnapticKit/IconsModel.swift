import Foundation

// Hidden Icons' shared vocabulary (lead; PLAN 0.4 §2). K1: what the stores and the kill switches need. K2: geometry,
// the three items and the inventory. K3 adds the engine state and fail-safe reasons.

/// The three sections of the menu bar, from the arrow's point of view (§4.1). Raw values are persisted (the layout
/// cache and `knownBundles` in `SnapticIconsAppsV1`).
package enum IconsSection: String, Codable, CaseIterable, Sendable {
    /// Right of the arrow: always shown.
    case shown
    /// Between the divider and the arrow: hidden while collapsed.
    case hidden
    /// Left of the divider: hidden even while expanded, when Always Hidden is on.
    case alwaysHidden

    /// Lower is more visible. One app's extras share one section, and the most visible wins (§4.2.6).
    package var visibilityRank: Int {
        switch self {
        case .shown: 0
        case .hidden: 1
        case .alwaysHidden: 2
        }
    }
}

/// A rectangle in one global coordinate space. The resolver compares x only, and x is the same in AppKit's and
/// Accessibility's spaces. The app converts y before it passes frames in, so that the screen pick (`IconsScreen`) can
/// use both.
package struct IconsRect: Codable, Equatable, Sendable {
    package var x: Double
    package var y: Double
    package var width: Double
    package var height: Double

    package init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    package var minX: Double { x }
    package var maxX: Double { x + width }
    package var midX: Double { x + width / 2 }
    package var minY: Double { y }
    package var maxY: Double { y + height }
    package var midY: Double { y + height / 2 }

    /// Zero or negative size, or a coordinate that isn't finite. Such a frame never places anything.
    package var isDegenerate: Bool {
        !(x.isFinite && y.isFinite && width.isFinite && height.isFinite) || width <= 0 || height <= 0
    }

    package func contains(x px: Double, y py: Double) -> Bool {
        px >= minX && px < maxX && py >= minY && py < maxY
    }
}

/// Which engine hides icons (§4.2.1). Unavailable isn't a kind: the factory then has no engine.
package enum IconsEngineKind: String, Codable, CaseIterable, Sendable {
    /// macOS 27 and later: a private menu bar restriction by bundle id. The arrow is the Hidden boundary.
    case native
    /// macOS 14–26: `|` grows until everything on its far side is off the screen.
    case length
}

/// Hidden Icons' own three status items (§4.1). Autosave names are `Snaptic.icons.<rawValue>`.
package enum IconsItemRole: String, Codable, CaseIterable, Sendable {
    /// The arrow (‹ / ›). On Native it is the Hidden boundary.
    case toggle
    /// `|`, the Hidden boundary on Length; zero-length on Native.
    case separator
    /// `⋮`, the Always Hidden boundary.
    case alwaysHidden

    package static let autosavePrefix = "Snaptic.icons."
    package var autosaveName: String { Self.autosavePrefix + rawValue }
}

/// One menu bar extra another app owns, as Accessibility reports it (§4.2.6).
package struct IconsExtra: Equatable, Sendable {
    package var pid: Int32
    package var bundleID: String?
    /// The extra's position among its app's `AXExtrasMenuBar` children.
    package var index: Int
    package var frame: IconsRect
    /// The AX title, when there is one. Shown in the hidden list only; never logged (§4.15).
    package var title: String?

    package init(pid: Int32, bundleID: String?, index: Int, frame: IconsRect, title: String? = nil) {
        self.pid = pid
        self.bundleID = bundleID
        self.index = index
        self.frame = frame
        self.title = title
    }
}

/// How one app's read ended. Only `.ok` may change the app's section (§4.2.6).
package enum IconsReadResult: String, Codable, CaseIterable, Sendable {
    case ok
    /// The per-call (0.15 s) or per-app (0.5 s) budget ran out, or the total (1.2 s) did first.
    case timedOut
    /// The app has no `AXExtrasMenuBar`, or it has no children.
    case noExtras
    /// The app refused the read (`kAXErrorAPIDisabled`, `kAXErrorNotImplemented` and the like).
    case denied
}

/// One running app's read.
package struct IconsAppRead: Equatable, Sendable {
    package var pid: Int32
    package var bundleID: String?
    /// The app bundle's standardized path (`NSRunningApplication.bundleURL`). Skips go by path, never by id (X-22).
    package var bundlePath: String?
    package var result: IconsReadResult
    /// Up to 50 extras (the budget); empty unless `.ok`.
    package var extras: [IconsExtra]

    package init(pid: Int32, bundleID: String?, bundlePath: String?, result: IconsReadResult,
                 extras: [IconsExtra] = []) {
        self.pid = pid
        self.bundleID = bundleID
        self.bundlePath = bundlePath
        self.result = result
        self.extras = result == .ok ? extras : []
    }
}

/// One whole read of the menu bar.
package struct IconsInventory: Equatable, Sendable {
    package var apps: [IconsAppRead]
    /// The read as a whole failed: Accessibility is off, the queue was cancelled, or the total budget ran out before
    /// any app answered.
    package var failed: Bool
    /// When the read finished, in seconds since the reference date. It becomes the layout cache's `readAt`.
    package var readAt: Double

    package init(apps: [IconsAppRead], failed: Bool = false, readAt: Double = 0) {
        self.apps = apps
        self.failed = failed
        self.readAt = readAt
    }

    package static func failure(readAt: Double = 0) -> IconsInventory {
        IconsInventory(apps: [], failed: true, readAt: readAt)
    }
}

/// Per-feature kill switches (H3): `Icons.disable.<rawValue>` = true in Snaptic's persistent domain turns the feature
/// off (`KillSwitches.read(prefix: "Icons")`). `Modules.disable.hiddenIcons` turns off the whole module.
package enum IconsFeature: String, Codable, CaseIterable, Sendable {
    /// The macOS 27 engine (`MBAssessmentModeAssertion`); also observed live and re-read before each collapse.
    case native
    /// The macOS 14–26 engine (separator lengths); also observed live.
    case length
    /// Accessibility reads of other apps' menu bar extras (Sections, the hidden list, new-icon detection).
    case inventory
    /// Show icons on hover.
    case hover
    /// Opening a hidden icon's menu from the hidden list (AXPress).
    case axpress

    package static let prefix = "Icons"
}
