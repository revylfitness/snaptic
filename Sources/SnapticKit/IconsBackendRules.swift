import Foundation

// Hidden Icons' app backends, as Kit decides them (lead; PLAN 0.4 §4.2.1, §4.2.2, §4.2.6, §4.11; A2): the shim's
// result codes, the Accessibility read's budgets, error mapping and coordinates, MenuBarAgent's item identity, the
// identity check and the hang watchdog's rule. `NativeBackend`, `AXInventory` and `IconsWatchdog` (app) only execute
// these.

// MARK: - Native (§4.2.2)

/// `SNMenuBarVisibilityResult`'s raw values, mapped onto the core's port result.
package enum IconsShimResult {
    package static let ok = 0
    package static let failed = 1
    package static let poisoned = 2
    package static let refused = 3

    /// A completion's code. An unknown code is a failure (the core then fails safe: icons shown).
    package static func completion(_ raw: Int) -> Result<Void, IconsActivationError> {
        switch raw {
        case ok: .success(())
        case poisoned: .failure(.poisoned)
        default: .failure(.failed)
        }
    }

    /// `activate` returned NO without calling its completion; `lastRefusal` says why. Never a success.
    package static func refusal(_ lastRefusal: Int) -> IconsActivationError {
        lastRefusal == poisoned ? .poisoned : .failed
    }
}

// MARK: - Accessibility read (§4.2.6)

package enum IconsReadBudget {
    /// `AXUIElementSetMessagingTimeout` on every element the read calls.
    package static let perCall = 0.15
    package static let perApp = 0.5
    package static let total = 1.2
    package static let maxExtras = 50

    /// The app's own deadline: its 0.5 s, cut short by what is left of the whole read's 1.2 s.
    package static func appDeadline(appStart: Double, readDeadline: Double) -> Double {
        min(appStart + perApp, readDeadline)
    }

    /// Apps that had extras last time go first, so a read cut short by the total budget still has them; the rest
    /// follow in pid order. Each pid once.
    package static func order(_ pids: [Int32], preferred: Set<Int32>) -> [Int32] {
        var seen = Set<Int32>()
        let unique = pids.filter { seen.insert($0).inserted }
        return unique.filter(preferred.contains).sorted() + unique.filter { !preferred.contains($0) }.sorted()
    }

    /// The read as a whole failed: no app answered with `.ok` or `.noExtras` though some were asked.
    package static func failed(_ results: [IconsReadResult]) -> Bool {
        !results.isEmpty && !results.contains { $0 == .ok || $0 == .noExtras }
    }
}

/// `AXError` raw values (`ApplicationServices`), so the mapping is testable off macOS.
package enum IconsAXError {
    package static let success: Int32 = 0
    package static let failure: Int32 = -25200
    package static let invalidUIElement: Int32 = -25202
    package static let cannotComplete: Int32 = -25204
    package static let attributeUnsupported: Int32 = -25205
    package static let notImplemented: Int32 = -25208
    package static let apiDisabled: Int32 = -25211
    package static let noValue: Int32 = -25212

    /// How an app's read ends on this error. `cannotComplete` is what a messaging timeout returns. An app that quit
    /// mid-read (`invalidUIElement`) has nothing to hide; anything else refused the read.
    package static func result(_ code: Int32) -> IconsReadResult {
        switch code {
        case success: .ok
        case cannotComplete: .timedOut
        case noValue, attributeUnsupported, invalidUIElement: .noExtras
        default: .denied
        }
    }
}

package enum IconsAXGeometry {
    /// Accessibility's global space has its origin at the primary screen's top-left with y down; AppKit's at its
    /// bottom-left with y up. x is the same in both (R3-12). Nil for a non-finite input or a primary screen with no
    /// height.
    package static func appKitRect(x: Double, y: Double, width: Double, height: Double,
                                   primaryHeight: Double) -> IconsRect? {
        guard [x, y, width, height, primaryHeight].allSatisfy(\.isFinite), primaryHeight > 0 else { return nil }
        return IconsRect(x: x, y: primaryHeight - y - height, width: width, height: height)
    }
}

/// MenuBarAgent's items (S0 notes): each extra is an `AXGroup` whose first child carries
/// `AXIdentifier = com.apple.menuextra.<name>`.
package enum IconsSystemIdentity {
    package static let prefix = "com.apple.menuextra."
    package static let menuBarAgentPath = "/System/Library/CoreServices/MenuBarAgent.app"

    /// The first child's identifier, else the extra's own; only `com.apple.menuextra.*` counts.
    package static func identifier(firstChild: String?, own: String?) -> String? {
        for id in [firstChild, own] {
            if let id, id.hasPrefix(prefix), id.count > prefix.count { return id }
        }
        return nil
    }

    /// The app is the system's MenuBarAgent: its id and its path both, so a spoofed id is a normal app (X-22).
    package static func isMenuBarAgent(bundleID: String?, bundlePath: String?) -> Bool {
        guard bundleID == IconsSkipRules.menuBarAgentID, let bundlePath else { return false }
        return IconsSkipRules.standardized(bundlePath) == menuBarAgentPath
    }
}

// MARK: - Identity (§4.2.1, Y-5)

package enum IconsIdentityCheck {
    /// Native runs only from the copy macOS resolves for Snaptic's bundle id, and never translocated. Paths are
    /// compared standardized, without a trailing slash, and must name an `.app` bundle; the app resolves symlinks
    /// first.
    package static func passes(translocated: Bool, resolvedPath: String?, ownPath: String?) -> Bool {
        guard !translocated, let resolvedPath, let ownPath else { return false }
        let a = IconsSkipRules.standardized(resolvedPath), b = IconsSkipRules.standardized(ownPath)
        return a.hasSuffix(".app") && a == b
    }
}

// MARK: - Hang watchdog (§4.11, X-1)

package enum IconsWatchdogRule {
    /// The main-queue heartbeat.
    package static let heartbeat = 0.5
    /// Main is hung once its last beat is older than this.
    package static let hangMillis = 3000.0
    /// How often the watchdog thread looks.
    package static let poll = 0.25
    /// `Debug.icons.hangMainSeconds` (DEBUG builds only, M12) is capped.
    package static let debugHangCap = 10.0

    /// Release every restriction off main: main is hung, something is held, and this hang hasn't fired yet (one
    /// release per hang; a fresh beat re-arms it).
    package static func shouldRelease(mainAgeMillis: Double, held: Int, firedThisHang: Bool) -> Bool {
        mainAgeMillis.isFinite && mainAgeMillis > hangMillis && held > 0 && !firedThisHang
    }

    /// Seconds to block main for M12, or nil.
    package static func debugHang(_ seconds: Double) -> Double? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        return min(seconds, debugHangCap)
    }
}
