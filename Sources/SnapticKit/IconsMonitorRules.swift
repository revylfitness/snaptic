import Foundation

// Hidden Icons' monitors, as Kit decides them (lead; PLAN 0.4 §4.6, §4.10, §4.11; A3): the menu bar band, the
// window-list guards that hold auto-collapse, the exam guard's presentation-option bits, MenuBarAgent's launch and
// quit, and which launches start a new-icon re-read. `IconsMonitors` (app) only samples AppKit and Core Graphics and
// hands the facts here.

// MARK: - The band (§4.6)

package enum IconsBand {
    /// A screen's menu bar band in AppKit's global space: its top `NSStatusBar.system.thickness` points, or more where
    /// the bar is taller. `thickness` is 22 while macOS 27 draws a 30 pt bar (A3 probe), so the bar's real height
    /// (`frame.maxY − visibleFrame.maxY`) and the notch inset count too. An auto-hidden bar leaves no inset; it still
    /// has its band, at `thickness`.
    package static func band(_ frame: IconsRect, thickness: Double, safeAreaTop: Double = 0,
                             visibleTopInset: Double = 0) -> IconsRect {
        let parts = [thickness, safeAreaTop, visibleTopInset].map { $0.isFinite ? $0 : 0 }
        let height = min(frame.height, max(parts.max() ?? 0, 0))
        return IconsRect(x: frame.x, y: frame.maxY - height, width: frame.width, height: height)
    }

    /// One screen's band; `visibleTopInset` as above.
    package static func band(_ screen: IconsScreen, thickness: Double, visibleTopInset: Double = 0) -> IconsRect {
        band(screen.frame, thickness: thickness, safeAreaTop: screen.safeAreaTop, visibleTopInset: visibleTopInset)
    }

    /// The pointer (`NSEvent.mouseLocation`) is in a band. The top edge counts: the pointer can sit on `maxY`. No
    /// allocation: the hover handler calls this on every mouse move.
    package static func contains(_ bands: [IconsRect], x: Double, y: Double) -> Bool {
        for b in bands where x >= b.minX && x < b.maxX && y >= b.minY && y <= b.maxY {
            return true
        }
        return false
    }
}

// MARK: - Window list guards (§4.6, Y-11, X-13)

/// One on-screen window from `CGWindowListCopyWindowInfo`, bounds only (no Screen Recording), in AppKit's space.
package struct IconsWindowInfo: Equatable, Sendable {
    package var layer: Int
    package var frame: IconsRect
    package var pid: Int32
    package var owner: String?
    package var alpha: Double

    package init(layer: Int, frame: IconsRect, pid: Int32, owner: String? = nil, alpha: Double = 1) {
        self.layer = layer
        self.frame = frame
        self.pid = pid
        self.owner = owner
        self.alpha = alpha
    }
}

package enum IconsWindowGuard {
    /// `kCGPopUpMenuWindowLevel`.
    package static let menuLayer = 101
    /// `kCGStatusWindowLevel`.
    package static let statusLayer = 25
    /// `kCGFloatingWindowLevel`.
    package static let floatingLayer = 3
    /// A popover or panel this close to a band holds the timer.
    package static let nearDistance = 40.0
    /// Whose layer-25 windows are menus (Control Center, the clock, Wi-Fi and the like).
    package static let menuOwners: Set<String> = ["SystemUIServer", "ControlCenter"]
    /// A menu's top may sit a little inside the band, or a point below it.
    package static let touchSlack = 2.0

    /// Seen at all: not transparent (S0 probe: invisible overlay windows sit at 25–27 with alpha 0) and not a 1 pt
    /// marker window.
    package static func visible(_ w: IconsWindowInfo) -> Bool {
        !w.frame.isDegenerate && w.alpha > 0.01 && w.frame.width >= 2 && w.frame.height >= 2
    }

    /// The window hangs below the band: its top is at or near the band's bottom edge and it reaches under it. A status
    /// item's own window, wholly inside the band, never counts.
    package static func hangsFrom(_ w: IconsRect, _ band: IconsRect) -> Bool {
        w.minX < band.maxX && w.maxX > band.minX
            && w.minY < band.minY - 0.5
            && w.maxY >= band.minY - touchSlack
    }

    /// The gap between two rectangles; 0 when they touch or overlap.
    package static func distance(_ a: IconsRect, _ b: IconsRect) -> Double {
        let dx = max(0, max(a.minX - b.maxX, b.minX - a.maxX))
        let dy = max(0, max(a.minY - b.maxY, b.minY - a.maxY))
        return (dx * dx + dy * dy).squareRoot()
    }

    /// A menu is open: a pop-up menu (101), or a SystemUIServer/ControlCenter window at layer 25, hanging from a band.
    package static func menuOpen(_ windows: [IconsWindowInfo], bands: [IconsRect], ownPID: Int32) -> Bool {
        windows.contains { w in
            guard w.pid != ownPID, visible(w) else { return false }
            let menu = w.layer == menuLayer || (w.layer == statusLayer && w.owner.map(menuOwners.contains) == true)
            return menu && bands.contains { hangsFrom(w.frame, $0) }
        }
    }

    /// A popover or panel (layer 25…101), or a floating window of an app that owns an extra, within 40 pt of a band
    /// and not inside it. Layers above 101 are overlays (notch apps, the cursor, the screen saver), never a popover.
    package static func popoverNearBand(_ windows: [IconsWindowInfo], bands: [IconsRect], extraPIDs: Set<Int32>,
                                        ownPID: Int32) -> Bool {
        windows.contains { w in
            guard w.pid != ownPID, visible(w) else { return false }
            let kind = (statusLayer...menuLayer).contains(w.layer)
                || (w.layer == floatingLayer && extraPIDs.contains(w.pid))
            guard kind else { return false }
            return bands.contains { band in
                w.frame.minY < band.minY - 0.5 && distance(w.frame, band) <= nearDistance
            }
        }
    }

    /// The front app has a normal window covering the whole screen while macOS reports full screen. Both are needed: a
    /// zoomed window with an always-hidden bar also covers the screen.
    package static func fullScreen(_ windows: [IconsWindowInfo], screen: IconsRect, frontPID: Int32?,
                                   systemFullScreen: Bool) -> Bool {
        guard systemFullScreen, let frontPID else { return false }
        return windows.contains { w in
            w.layer == 0 && w.pid == frontPID && visible(w)
                && abs(w.frame.minX - screen.minX) <= 1 && abs(w.frame.maxX - screen.maxX) <= 1
                && abs(w.frame.minY - screen.minY) <= 1 && abs(w.frame.maxY - screen.maxY) <= 1
        }
    }
}

// MARK: - Presentation options (§4.11, R2-4)

extension IconsPresentationFlag {
    /// `NSApplication.PresentationOptions` bits.
    package var bit: UInt {
        switch self {
        case .disableProcessSwitching: 1 << 5
        case .disableForceQuit: 1 << 6
        case .disableSessionTermination: 1 << 7
        }
    }

    /// `.fullScreen`.
    package static let fullScreenBit: UInt = 1 << 10

    package static func flags(_ raw: UInt) -> Set<IconsPresentationFlag> {
        Set(allCases.filter { raw & $0.bit != 0 })
    }
}

// MARK: - MenuBarAgent and launches (§4.5, §4.11)

package enum IconsAgentWatch {
    /// A workspace launch or quit that is MenuBarAgent's (id and path, X-22), as a recovery event.
    package static func event(launched: Bool, bundleID: String?, bundlePath: String?) -> IconsRecoveryEvent? {
        guard IconsSystemIdentity.isMenuBarAgent(bundleID: bundleID, bundlePath: bundlePath) else { return nil }
        return launched ? .agentLaunched : .agentTerminated
    }
}

package enum IconsLaunchWatch {
    /// A launch that should start the new-icon re-reads: another app, with a bundle id, that isn't MenuBarAgent.
    package static func counts(bundleID: String?, pid: Int32, ownPID: Int32, bundlePath: String?) -> Bool {
        guard pid != ownPID, let bundleID, !bundleID.isEmpty else { return false }
        return !IconsSystemIdentity.isMenuBarAgent(bundleID: bundleID, bundlePath: bundlePath)
    }
}

extension KnownMenuBarHiders {
    /// The bundle id is a listed hider's, whatever the team: worth reading its signature (off main).
    package static func candidate(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return all.contains { $0.isPrefix ? bundleID == $0.bundleID || bundleID.hasPrefix($0.bundleID + ".")
                                          : bundleID == $0.bundleID }
    }
}
