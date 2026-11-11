import Foundation

// Hidden Icons' layout (lead; PLAN 0.4 §4.2.5, §4.2.6, §4.8). Pure: which section each app's icons are in, which
// reads may be trusted, where the notch is, and whether the user's arrangement lets a collapse happen. The app turns
// AppKit and Accessibility frames into `IconsRect`s in one global space first. Hidden Bar's `MenuBarLayoutResolver`
// and `NotchGeometry` are the design source; this is our own code.

/// One display, as the layout needs it.
package struct IconsScreen: Equatable, Sendable {
    package var frame: IconsRect
    /// `NSScreen.safeAreaInsets.top`. More than 0 on a display with a notch.
    package var safeAreaTop: Double
    /// `NSScreen.auxiliaryTopRightArea?.minX`, in the same global x as `frame`.
    package var auxiliaryTopRightMinX: Double?

    package init(frame: IconsRect, safeAreaTop: Double = 0, auxiliaryTopRightMinX: Double? = nil) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopRightMinX = auxiliaryTopRightMinX
    }
}

/// The lines that split the bar into sections.
package struct IconsBoundaries: Equatable, Sendable {
    /// Between Shown and Hidden: `|` on Length, the arrow on Native.
    package var hidden: IconsRect
    /// Between Hidden and Always Hidden: `⋮`, only while it is placed (§4.2.5). Nil makes Always Hidden part of Hidden.
    package var alwaysHidden: IconsRect?
    package var rightToLeft: Bool

    package init(hidden: IconsRect, alwaysHidden: IconsRect? = nil, rightToLeft: Bool = false) {
        self.hidden = hidden
        self.alwaysHidden = alwaysHidden
        self.rightToLeft = rightToLeft
    }
}

package enum IconsGeometry {
    /// A boundary item's line is its edge on the Shown side: `maxX` in LTR, `minX` in RTL. It stays put while Length
    /// grows the item away from the arrow, so one rule works collapsed and expanded.
    package static func line(of boundary: IconsRect, rightToLeft: Bool) -> Double {
        rightToLeft ? boundary.minX : boundary.maxX
    }

    /// Signed distance from a boundary's line to `x`, positive on the Shown side.
    package static func towardShown(_ x: Double, from boundary: IconsRect, rightToLeft: Bool) -> Double {
        let edge = line(of: boundary, rightToLeft: rightToLeft)
        return rightToLeft ? edge - x : x - edge
    }

    /// The item's middle is on the far side of the boundary from the arrow.
    package static func isBeyond(_ frame: IconsRect, _ boundary: IconsRect, rightToLeft: Bool) -> Bool {
        towardShown(frame.midX, from: boundary, rightToLeft: rightToLeft) < 0
    }

    package static func section(of frame: IconsRect, in boundaries: IconsBoundaries) -> IconsSection {
        let rtl = boundaries.rightToLeft
        guard isBeyond(frame, boundaries.hidden, rightToLeft: rtl) else { return .shown }
        if let alwaysHidden = boundaries.alwaysHidden, isBeyond(frame, alwaysHidden, rightToLeft: rtl) {
            return .alwaysHidden
        }
        return .hidden
    }

    /// The screen holding a frame's middle; failing that, the first whose x range holds it. Nil when none does.
    package static func screen(holding frame: IconsRect, in screens: [IconsScreen]) -> IconsScreen? {
        guard frame.midX.isFinite, frame.midY.isFinite else { return nil }
        if let exact = screens.first(where: { $0.frame.contains(x: frame.midX, y: frame.midY) }) { return exact }
        return screens.first { frame.midX >= $0.frame.minX && frame.midX < $0.frame.maxX }
    }

    /// On the screen's menu bar row, by x.
    package static func isOnScreen(_ frame: IconsRect, _ screen: IconsRect) -> Bool {
        !frame.isDegenerate && frame.midX >= screen.minX && frame.midX < screen.maxX
    }
}

// MARK: - Guards (§4.2.5)

/// A Snaptic status item other than Hidden Icons' own, for the own-items guard.
package struct IconsOwnItem: Equatable, Sendable {
    /// The item's autosave name. Never logged with a bundle id; it is Snaptic's own.
    package var id: String
    /// Its window frame, or nil before it has one.
    package var frame: IconsRect?
    /// Awake's icon, which must stay shown while a session holds (§4.2.5).
    package var isAwake: Bool

    package init(id: String, frame: IconsRect?, isAwake: Bool = false) {
        self.id = id
        self.frame = frame
        self.isAwake = isAwake
    }
}

/// Where Snaptic's own items sit relative to `|` (Length). `IconsPolicy.ownItemsGuard` (K4) decides what to do.
package struct IconsOwnItemsPlacement: Equatable, Sendable {
    /// False when the arrow's or `|`'s frame is missing, so nothing can be judged. The policy then refuses to collapse.
    package var known: Bool
    /// The arrow is on the hidden side of `|`.
    package var toggleBeyond: Bool
    /// Ids of the items on the hidden side of `|`, in input order.
    package var beyond: [String]
    /// Awake's icon is among them.
    package var awakeBeyond: Bool
    /// Ids of the items with no frame yet.
    package var unplaced: [String]

    package static let unknown = IconsOwnItemsPlacement(known: false, toggleBeyond: false, beyond: [],
                                                        awakeBeyond: false, unplaced: [])
}

package enum IconsGuards {
    /// `arrangementValid`: Length needs `|` on the hidden side of the arrow. Native is always valid.
    package static func arrangementValid(engine: IconsEngineKind, toggle: IconsRect?, separator: IconsRect?,
                                         rightToLeft: Bool) -> Bool {
        guard engine == .length else { return true }
        guard let toggle, let separator, hasPosition(toggle), hasPosition(separator) else { return false }
        // The whole of `|`, however long, is on the far side of the arrow.
        return rightToLeft ? separator.minX >= toggle.maxX : separator.maxX <= toggle.minX
    }

    /// `alwaysHiddenPlaced`: `⋮` is on the hidden side of `|` (Length) or of the arrow (Native), and its line is on
    /// the screen holding the arrow.
    package static func alwaysHiddenPlaced(engine: IconsEngineKind, toggle: IconsRect?, separator: IconsRect?,
                                           alwaysHidden: IconsRect?, screen: IconsRect?, rightToLeft: Bool) -> Bool {
        guard let alwaysHidden, hasPosition(alwaysHidden), let screen else { return false }
        guard let reference = engine == .native ? toggle : separator, hasPosition(reference) else { return false }
        let edge = IconsGeometry.line(of: alwaysHidden, rightToLeft: rightToLeft)
        guard edge >= screen.minX, edge <= screen.maxX else { return false }
        return rightToLeft
            ? edge > IconsGeometry.line(of: reference, rightToLeft: true)
            : edge < IconsGeometry.line(of: reference, rightToLeft: false)
    }

    /// The resolver's boundaries for the current frames. Nil when the Hidden boundary has no frame. An unplaced `⋮`
    /// is left out, so Always Hidden acts as part of Hidden.
    package static func boundaries(engine: IconsEngineKind, toggle: IconsRect?, separator: IconsRect?,
                                   alwaysHidden: IconsRect?, screen: IconsRect?,
                                   rightToLeft: Bool) -> IconsBoundaries? {
        guard let hidden = engine == .native ? toggle : separator, hasPosition(hidden) else { return nil }
        let placed = alwaysHiddenPlaced(engine: engine, toggle: toggle, separator: separator,
                                        alwaysHidden: alwaysHidden, screen: screen, rightToLeft: rightToLeft)
        return IconsBoundaries(hidden: hidden, alwaysHidden: placed ? alwaysHidden : nil, rightToLeft: rightToLeft)
    }

    /// The own-items guard's input (Length). Window frames only, so no Accessibility is needed.
    package static func ownItemsPlacement(toggle: IconsRect?, separator: IconsRect?, items: [IconsOwnItem],
                                          rightToLeft: Bool) -> IconsOwnItemsPlacement {
        guard let toggle, let separator, hasPosition(toggle), hasPosition(separator) else { return .unknown }
        var beyond: [String] = []
        var unplaced: [String] = []
        var awakeBeyond = false
        for item in items {
            guard let frame = item.frame, hasPosition(frame) else {
                unplaced.append(item.id)
                continue
            }
            if IconsGeometry.isBeyond(frame, separator, rightToLeft: rightToLeft) {
                beyond.append(item.id)
                awakeBeyond = awakeBeyond || item.isAwake
            }
        }
        return IconsOwnItemsPlacement(known: true,
                                      toggleBeyond: IconsGeometry.isBeyond(toggle, separator, rightToLeft: rightToLeft),
                                      beyond: beyond, awakeBeyond: awakeBeyond, unplaced: unplaced)
    }

    /// A boundary item may be zero-length (dividers off), so it needs only a finite position.
    private static func hasPosition(_ rect: IconsRect) -> Bool {
        rect.x.isFinite && rect.width.isFinite && rect.width >= 0
    }
}

// MARK: - Resolver (§4.2.6)

/// Why an app's icons were left out of the layout. Skips go by bundle path, never by id, so a spoofed id is just an
/// app (X-22).
package enum IconsSkip: String, Sendable {
    /// Snaptic itself: its own pid or its own bundle path.
    case own
    /// A macOS owner (bundle path under `/System/`). Its icons can't be hidden by bundle.
    case system
    /// No bundle id, so it can't be hidden or allowed by bundle.
    case unidentified
}

package struct IconsSkipRules: Equatable, Sendable {
    package var ownPID: Int32
    /// `Bundle.main.bundleURL`'s path.
    package var ownBundlePath: String?

    /// MenuBarAgent's items are allowed as system items (the 0..<64 range), never by bundle (R2-1).
    package static let menuBarAgentID = "com.apple.MenuBarAgent"

    package init(ownPID: Int32, ownBundlePath: String?) {
        self.ownPID = ownPID
        self.ownBundlePath = ownBundlePath.map(Self.standardized)
    }

    package func skip(_ app: IconsAppRead) -> IconsSkip? {
        let path = app.bundlePath.map(Self.standardized)
        if app.pid == ownPID { return .own }
        if let path, let ownBundlePath, path == ownBundlePath { return .own }
        if let path, Self.isSystemPath(path) { return .system }
        if app.bundleID?.isEmpty ?? true { return .unidentified }
        return nil
    }

    /// Under `/System/` after `..` and `.` are resolved, so `/System/../Applications/X.app` isn't a system path.
    package static func isSystemPath(_ path: String) -> Bool {
        standardized(path).hasPrefix("/System/")
    }

    static func standardized(_ path: String) -> String {
        guard path.hasPrefix("/") else { return path }
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(part)
            }
        }
        return "/" + parts.joined(separator: "/")
    }
}

/// Which frames a read may trust (§4.2.2 layout refresh).
package enum IconsReadScope: Equatable, Sendable {
    /// Nothing was restricted, so every frame is current.
    case unrestricted
    /// A restriction was active. Only the allowed bundles' frames are current: hidden items stay in Accessibility at
    /// stale frames (S0-10, R2-5).
    case restricted(allowed: Set<String>)
}

/// An extra with the section the resolver gave it.
package struct IconsPlacedExtra: Equatable, Sendable {
    package var extra: IconsExtra
    package var section: IconsSection
    /// Distance from the Hidden boundary's line; rows are ordered nearest first (§4.8).
    package var distance: Double
}

/// A read the layout can't use. None of them collapses: the engine expands and keeps the last good layout.
package enum IconsUnusableRead: String, Codable, CaseIterable, Sendable {
    /// The read as a whole failed.
    case failed
    /// No app reported a single extra, not even macOS's own.
    case empty
    /// No third-party icon was placed, though an app the last good read placed is still running.
    case lostThirdParty
    /// The Hidden boundary has no frame.
    case noBoundary
    /// No screen holds the arrow.
    case noScreen
}

package struct IconsLayout: Equatable, Sendable {
    /// One section per bundle, because hiding is per bundle.
    package var sections: [String: IconsSection]
    /// Skipped macOS owners other than MenuBarAgent, e.g. `com.apple.TextInputMenuAgent`. Native allows them (R2-1).
    package var systemBundles: Set<String>
    /// Bundles whose section didn't come from this read: a read that wasn't `.ok`, a frame the scope doesn't trust, or
    /// icons all off the arrow's screen. They kept their last section or count as shown.
    package var carried: Set<String>
    /// Every placed extra.
    package var extras: [IconsPlacedExtra]
    /// Extras of `.ok` apps that were off the arrow's screen. On Length while collapsed, the hidden ones are here.
    package var offScreen: [IconsExtra]
    package var scope: IconsReadScope
    package var readAt: Double

    /// Sorted, so allow-lists and tests are stable.
    package func bundles(in wanted: Set<IconsSection>) -> [String] {
        sections.filter { wanted.contains($0.value) }.map(\.key).sorted()
    }

    /// One section's extras, nearest the boundary first (§4.8).
    package func rows(in section: IconsSection) -> [IconsPlacedExtra] {
        extras.filter { $0.section == section }.sorted { a, b in
            if a.distance != b.distance { return a.distance < b.distance }
            if a.extra.pid != b.extra.pid { return a.extra.pid < b.extra.pid }
            return a.extra.index < b.extra.index
        }
    }

    /// For the layout cache in `SnapticIconsAppsV1`.
    package var cache: IconsLayoutCache { IconsLayoutCache(readAt: readAt, sections: sections) }
}

package enum IconsResolution: Equatable, Sendable {
    case usable(IconsLayout)
    case unusable(IconsUnusableRead)

    package var layout: IconsLayout? {
        if case .usable(let layout) = self { return layout }
        return nil
    }
}

package enum IconsLayoutResolver {
    /// - Parameters:
    ///   - boundaries: from `IconsGuards.boundaries`.
    ///   - screen: the frame of the screen holding the arrow's window. Extras outside its x range are dropped.
    ///   - previous: the last good layout's sections. Only apps this read can't place keep theirs.
    package static func resolve(_ inventory: IconsInventory, boundaries: IconsBoundaries?, screen: IconsRect?,
                                skip: IconsSkipRules, previous: [String: IconsSection]?,
                                scope: IconsReadScope = .unrestricted) -> IconsResolution {
        if inventory.failed { return .unusable(.failed) }
        if !inventory.apps.contains(where: { !$0.extras.isEmpty }) { return .unusable(.empty) }
        guard let boundaries else { return .unusable(.noBoundary) }
        guard let screen, !screen.isDegenerate else { return .unusable(.noScreen) }

        let previous = previous ?? [:]
        let allowed: Set<String>?
        if case .restricted(let set) = scope { allowed = set } else { allowed = nil }
        var sections: [String: IconsSection] = [:]
        var systemBundles: Set<String> = []
        var placed: [IconsPlacedExtra] = []
        var offScreen: [IconsExtra] = []
        var unplaced: [String] = []
        let line = IconsGeometry.line(of: boundaries.hidden, rightToLeft: boundaries.rightToLeft)

        for app in inventory.apps {
            if let reason = skip.skip(app) {
                if reason == .system, let id = app.bundleID, !id.isEmpty, id != IconsSkipRules.menuBarAgentID {
                    systemBundles.insert(id)
                }
                continue
            }
            guard let bundle = app.bundleID else { continue }
            if let allowed, !allowed.contains(bundle) {
                // A hidden app's frames are stale; it keeps its cached section, or stays out when it has none.
                unplaced.append(bundle)
                continue
            }
            let mine = app.extras.filter { IconsGeometry.isOnScreen($0.frame, screen) }
            offScreen += app.extras.filter { !$0.frame.isDegenerate && !IconsGeometry.isOnScreen($0.frame, screen) }
            guard app.result == .ok, !mine.isEmpty else {
                unplaced.append(bundle)
                continue
            }
            for extra in mine {
                let section = IconsGeometry.section(of: extra.frame, in: boundaries)
                placed.append(IconsPlacedExtra(extra: extra, section: section, distance: abs(extra.frame.midX - line)))
                // The most visible extra wins, so an icon the user kept shown is never hidden because a sibling sits in
                // the hidden section.
                if let current = sections[bundle], current.visibilityRank <= section.visibilityRank { continue }
                sections[bundle] = section
            }
        }

        if placed.isEmpty {
            // "No third-party items while the last good read had some." Only an app that is still running counts;
            // once every app the last read placed has quit, an empty bar is the truth.
            let running = Set(inventory.apps.compactMap(\.bundleID))
            if previous.keys.contains(where: { running.contains($0) && (allowed?.contains($0) ?? true) }) {
                return .unusable(.lostThirdParty)
            }
        }

        var carried: Set<String> = []
        for bundle in unplaced where sections[bundle] == nil {
            if let last = previous[bundle] {
                sections[bundle] = last
            } else if let allowed, !allowed.contains(bundle) {
                continue
            } else {
                // Never hidden by a read that couldn't place it (§4.2.6).
                sections[bundle] = .shown
            }
            carried.insert(bundle)
        }

        return .usable(IconsLayout(sections: sections, systemBundles: systemBundles, carried: carried, extras: placed,
                                   offScreen: offScreen, scope: scope, readAt: inventory.readAt))
    }
}

// MARK: - Notch (§4.8)

package enum IconsNotch {
    /// Hidden Bar's fallback when a notched screen reports no top-right area: about half of a 1728 pt screen. Measured
    /// from the screen's left edge, so it holds on any display.
    package static let fallbackOffset: Double = 972

    /// The x left of which an extra on this screen is behind the notch, or nil when the screen has no notch.
    package static func boundary(of screen: IconsScreen) -> Double? {
        guard screen.safeAreaTop.isFinite, screen.safeAreaTop > 0, !screen.frame.isDegenerate else { return nil }
        if let aux = screen.auxiliaryTopRightMinX, aux.isFinite, aux > screen.frame.minX, aux < screen.frame.maxX {
            return aux
        }
        return min(screen.frame.minX + fallbackOffset, screen.frame.maxX)
    }

    /// Splits rows into those in the clear and those behind a notch, each against the screen holding its middle.
    /// Zero-size extras are dropped. Order is kept, so callers pass rows already nearest-first.
    package static func split(_ rows: [IconsPlacedExtra],
                              screens: [IconsScreen]) -> (clear: [IconsPlacedExtra], behindNotch: [IconsPlacedExtra]) {
        var clear: [IconsPlacedExtra] = []
        var behind: [IconsPlacedExtra] = []
        for row in rows where !row.extra.frame.isDegenerate {
            if let screen = IconsGeometry.screen(holding: row.extra.frame, in: screens),
               let edge = boundary(of: screen), row.extra.frame.minX < edge {
                behind.append(row)
            } else {
                clear.append(row)
            }
        }
        return (clear, behind)
    }
}
