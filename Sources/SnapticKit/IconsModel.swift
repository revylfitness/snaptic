import Foundation

// Hidden Icons' shared vocabulary (lead; PLAN 0.4 §2). K1: what the stores and the kill switches need. K2: geometry,
// the three items and the inventory. K3: the engine's state, results, fail-safe reasons and counters.

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
    /// MenuBarAgent's extras, keyed by the first child's `AXIdentifier` (`com.apple.menuextra.*`), for the Native
    /// system-item check (§4.2.2). Nil when the read didn't get them.
    package var systemIdentifiers: Set<String>?

    package init(apps: [IconsAppRead], failed: Bool = false, readAt: Double = 0,
                 systemIdentifiers: Set<String>? = nil) {
        self.apps = apps
        self.failed = failed
        self.readAt = readAt
        self.systemIdentifiers = systemIdentifiers
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

// MARK: - Engine (K3, §4.2, §4.4, §4.11)

/// How the icons are shown (§4.3). ⌥ shows Always Hidden too. Never persisted: launch always starts plain.
package enum IconsExpandMode: String, Codable, CaseIterable, Sendable {
    case plain
    case all
}

/// Why the engine can't hide anything. Items still show, and the status row explains (§4.17).
package enum IconsUnavailableReason: String, Codable, CaseIterable, Sendable {
    /// `Icons.disable.native` or `Icons.disable.length`.
    case killSwitch
    /// `Icons.disable.inventory` on macOS 27: Native can't work without a read.
    case inventoryOff
    /// The shim's class or an encoding is missing, or it wasn't verified.
    case shimUnavailable
    /// The shim caught an exception; it stays off for the life of the process.
    case shimPoisoned
    /// `Icons.native.disabledBuild` is this OS build: a crash or a hidden system item.
    case disabledBuild
    /// Snaptic is translocated or isn't the copy macOS resolves for its bundle id.
    case identity
    /// Two activations in a row timed out; Native is off until relaunch.
    case timeouts
    /// The module stopped.
    case stopped
}

package enum IconsEngineState: Equatable, Sendable {
    case expanded(IconsExpandMode)
    /// A Native collapse is reading the inventory or waiting for its activation.
    case calibrating
    case collapsed
    case unavailable(IconsUnavailableReason)

    package var isCollapsed: Bool { self == .collapsed }
}

/// Why a collapse didn't start. Nothing changed; auto-collapse re-arms (§4.6).
package enum IconsRefusal: String, Codable, CaseIterable, Sendable {
    /// The arrow isn't in the menu bar (§4.1, G-4).
    case arrowHidden
    /// `|` isn't in the menu bar (Length).
    case dividerHidden
    /// `|` isn't on the hidden side of the arrow (Length, §4.2.5).
    case arrangement
    /// The own-items guard (§4.2.5).
    case ownItems
    /// Accessibility isn't granted or isn't effective (§4.12).
    case needsPermission
    /// An exam session holds the screen (§4.11).
    case exam
    /// Another menu bar hider runs and the policy is Pause (§4.10).
    case paused
    /// The first collapse after start waits for two matching reads (§4.5).
    case unstableInventory
    /// The identity check failed before an activation (§4.2.1).
    case identity
}

/// Why the engine showed every icon on its own (§4.11). "Fails safe" means icons shown (G-18).
package enum IconsFailSafeReason: String, Codable, CaseIterable, Sendable {
    case activationFailed
    case activateTimeout
    /// The divider's window didn't grow to the length asked for (Length).
    case lengthRejected
    /// The inventory was failed, empty, lost the third-party items, or had no boundary or screen.
    case unusableRead
    /// A MenuBarAgent item went missing after a collapse (Native, §4.2.2).
    case systemItemHidden
    /// `|` moved to the shown side, found before an inflate (Length).
    case arrangement
    case arrowHidden
    case ownItems
    case exam
    case agentRestart
    /// Session resign/become active, wake, lock (§4.11).
    case session
    /// The watchdog released the restriction while main was stuck.
    case hang
    case shimPoisoned

    /// The counter this reason records. Three have counters of their own (§3, H12).
    package var counter: IconsCounter {
        switch self {
        case .activateTimeout: .activateTimeout
        case .systemItemHidden: .systemItemHidden
        case .agentRestart: .agentRestart
        default: .failSafe(self)
        }
    }
}

/// What a collapse request ended with. Every request gets exactly one.
package enum IconsCollapseResult: Equatable, Sendable {
    case collapsed
    case refused(IconsRefusal)
    case failed(IconsFailSafeReason)
    case unavailable
    /// An expand, a fail-safe or `stop()` came first. Nothing is hidden by this request.
    case superseded
}

/// EventLog counters in `.icons` (§3, H12). Names carry only reason codes (§4.15).
package enum IconsCounter: Hashable, Sendable {
    case started
    case collapse
    case expand
    case failSafe(IconsFailSafeReason)
    case hangExpand
    case activateTimeout
    case dupCompletion
    case agentRestart
    case systemItemHidden
    case pressNoop
    case inventoryTimeout

    package var name: String {
        switch self {
        case .started: "icons.started"
        case .collapse: "icons.collapse"
        case .expand: "icons.expand"
        case .failSafe(let reason): "icons.failSafe." + reason.rawValue
        case .hangExpand: "icons.hangExpand"
        case .activateTimeout: "icons.activateTimeout"
        case .dupCompletion: "icons.dupCompletion"
        case .agentRestart: "icons.agentRestart"
        case .systemItemHidden: "icons.systemItemHidden"
        case .pressNoop: "icons.pressNoop"
        case .inventoryTimeout: "icons.inventoryTimeout"
        }
    }
}
