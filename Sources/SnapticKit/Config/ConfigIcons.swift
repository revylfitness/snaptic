import Foundation

// Hidden Icons' two stores (lead; PLAN 0.4 H7, H10). `SnapticIconsV1` holds the settings, which are backed up (except
// `arranged`); `SnapticIconsAppsV1` holds everything that contains a bundle id, which never leaves this Mac (not in
// backups, not in diagnostics).

/// Advanced › “New apps’ icons” (§4.5; Native only).
package enum IconsNewAppPolicy: String, Codable, CaseIterable, Sendable {
    /// A new app's icon stays shown (`newShown`) until its section is known.
    case show
    /// Hidden Bar's behaviour: it lands where macOS puts it, usually in Hidden.
    case hide
}

/// Advanced › “When another menu bar app hides icons” (§4.10).
package enum IconsOtherHiderPolicy: String, Codable, CaseIterable, Sendable {
    case pause
    case runBoth
}

/// A per-app choice in Sections (§4.9; Native only, kept but unused on 14–26).
package enum IconsAppChoice: String, Codable, CaseIterable, Sendable {
    case alwaysShow
    case alwaysHide
}

/// `SnapticIconsV1`: the Hidden Icons settings plus `arranged` (H10).
package struct IconsConfig: ConfigModel {
    package static let key = "SnapticIconsV1"
    /// The auto-collapse delay's range (§4.6, a value field with a stepper).
    package static let autoCollapseRange = 5...300
    package static let defaultAutoCollapseSeconds = 10

    /// “Hide icons automatically after N seconds”.
    package var autoCollapse: Bool
    package var autoCollapseSeconds: Int
    /// “Hide icons when Snaptic opens” (§4.6: once per process start).
    package var collapseAtLaunch: Bool
    /// “Always Hidden section”.
    package var alwaysHidden: Bool
    /// “Section dividers”.
    package var dividers: Bool
    /// “Show or hide icons”.
    package var shortcut: HotkeyCombo?
    /// Advanced › “Show icons on hover”.
    package var hover: Bool
    /// Advanced › “New apps’ icons”.
    package var newApps: IconsNewAppPolicy
    /// Advanced › “When another menu bar app hides icons”.
    package var otherHiders: IconsOtherHiderPolicy
    /// Advanced › “Use the full menu bar while icons are shown” (§4.7).
    package var fullBarOnExpand: Bool
    /// The first collapse the user asked for has happened (§4.0). Until then nothing hides on its own. Never exported;
    /// Reset All Settings and Reset Arrow Position… clear it; Restore Defaults keeps it.
    package var arranged: Bool

    package init() {
        autoCollapse = true
        autoCollapseSeconds = Self.defaultAutoCollapseSeconds
        collapseAtLaunch = true
        alwaysHidden = false
        dividers = true
        shortcut = nil
        hover = false
        newApps = .show
        otherHiders = .pause
        fullBarOnExpand = false
        arranged = false
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case autoCollapse, autoCollapseSeconds, collapseAtLaunch, alwaysHidden, dividers, shortcut, hover, newApps,
             otherHiders, fullBarOnExpand, arranged
    }

    /// The keys a backup carries (H7): every setting except `arranged`, which describes this Mac's menu bar.
    package static let exportedKeys: [String] = CodingKeys.allCases.filter { $0 != .arranged }.map(\.stringValue)

    /// Field by field: a bad value falls back to its default without touching the others.
    package init(from decoder: Decoder) throws {
        let d = IconsConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoCollapse = c.lossy(.autoCollapse, d.autoCollapse)
        autoCollapseSeconds = c.lossy(.autoCollapseSeconds, d.autoCollapseSeconds)
        collapseAtLaunch = c.lossy(.collapseAtLaunch, d.collapseAtLaunch)
        alwaysHidden = c.lossy(.alwaysHidden, d.alwaysHidden)
        dividers = c.lossy(.dividers, d.dividers)
        shortcut = c.lossy(.shortcut, d.shortcut)
        hover = c.lossy(.hover, d.hover)
        newApps = c.lossy(.newApps, d.newApps)
        otherHiders = c.lossy(.otherHiders, d.otherHiders)
        fullBarOnExpand = c.lossy(.fullBarOnExpand, d.fullBarOnExpand)
        arranged = c.lossy(.arranged, d.arranged)
    }

    package func sanitized() -> IconsConfig {
        var c = self
        c.autoCollapseSeconds = min(max(autoCollapseSeconds, Self.autoCollapseRange.lowerBound),
                                    Self.autoCollapseRange.upperBound)
        return c
    }

    /// Page Restore Defaults (§4.9): every setting back to its default; `arranged` is kept, because where the icons
    /// are in the menu bar stays as it is. The apps store's part is `IconsAppsState.restoringDefaults()`.
    package func restoringDefaults() -> IconsConfig {
        var c = IconsConfig()
        c.arranged = arranged
        return c
    }

    /// The Advanced sheet's own Restore Defaults: only its rows.
    package func restoringAdvancedDefaults() -> IconsConfig {
        let d = IconsConfig()
        var c = self
        c.hover = d.hover
        c.newApps = d.newApps
        c.otherHiders = d.otherHiders
        c.fullBarOnExpand = d.fullBarOnExpand
        return c
    }
}

// MARK: - SnapticIconsAppsV1

/// Where each app's icons were at the last unrestricted read (§4.2.2): bundle → section, plus when it was read. Only
/// an unrestricted read replaces it.
package struct IconsLayoutCache: Codable, Equatable, Sendable {
    /// Wall-clock seconds since 1970.
    package var readAt: Double
    package var sections: [String: IconsSection]

    package init(readAt: Double = 0, sections: [String: IconsSection] = [:]) {
        self.readAt = readAt
        self.sections = sections
    }

    private enum CodingKeys: String, CodingKey { case readAt, sections }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        readAt = c.lossy(.readAt, 0)
        sections = c.lossyBundleMap(.sections)
    }
}

/// An app seen in the menu bar (§4.5): its last section, and when it was first and last seen.
package struct IconsKnownBundle: Codable, Equatable, Sendable {
    package var section: IconsSection?
    package var firstSeen: Double
    package var lastSeen: Double
    /// Unrestricted reads in a row that didn't see it; dropped at `IconsAppsState.dropAfterMissedReads`.
    package var missedReads: Int

    package init(section: IconsSection? = nil, firstSeen: Double, lastSeen: Double, missedReads: Int = 0) {
        self.section = section
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.missedReads = missedReads
    }

    private enum CodingKeys: String, CodingKey { case section, firstSeen, lastSeen, missedReads }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        section = c.lossy(.section, nil)
        firstSeen = c.lossy(.firstSeen, 0)
        lastSeen = c.lossy(.lastSeen, 0)
        missedReads = c.lossy(.missedReads, 0)
    }
}

/// `SnapticIconsAppsV1`: everything that contains a bundle id (H10). Excluded from backup and diagnostics; Reset All
/// Settings clears it; Restore Defaults clears `choices` and `newShown`.
package struct IconsAppsState: ConfigModel {
    package static let key = "SnapticIconsAppsV1"
    package static let knownBundlesCap = 512
    package static let newShownCap = 64
    package static let choicesCap = 512
    package static let layoutCap = 512
    package static let toastCap = 512
    /// A bundle leaves `knownBundles` after this many unrestricted reads in a row without it (§4.5).
    package static let dropAfterMissedReads = 3

    package var layout: IconsLayoutCache?
    package var knownBundles: [String: IconsKnownBundle]
    /// Bundles a new-app Show keeps visible (§4.5): bundle → when it was last seen (wall seconds).
    package var newShown: [String: Double]
    package var choices: [String: IconsAppChoice]
    /// The per-app daily new-icon toast (Length, §4.5): bundle → the day (`Int(wall / 86 400)`) it was last shown.
    package var toasts: [String: Int]

    package init() {
        layout = nil
        knownBundles = [:]
        newShown = [:]
        choices = [:]
        toasts = [:]
    }

    private enum CodingKeys: String, CodingKey { case layout, knownBundles, newShown, choices, toasts }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = c.lossy(.layout, nil)
        knownBundles = c.lossyBundleMap(.knownBundles)
        newShown = c.lossyBundleMap(.newShown)
        choices = c.lossyBundleMap(.choices)
        toasts = c.lossyBundleMap(.toasts)
    }

    /// Valid bundle ids only, finite non-negative times, and each map within its cap: the most recently seen entries
    /// win (LRU; ties by bundle id, so the result is deterministic).
    package func sanitized() -> IconsAppsState {
        var c = self
        if var l = layout {
            l.readAt = Self.time(l.readAt)
            l.sections = Self.capped(l.sections.filter { Self.isBundle($0.key) }, Self.layoutCap) { _ in 0 }
            c.layout = l
        }
        var known: [String: IconsKnownBundle] = [:]
        for (bundle, var k) in knownBundles where Self.isBundle(bundle) {
            k.firstSeen = Self.time(k.firstSeen)
            k.lastSeen = max(Self.time(k.lastSeen), k.firstSeen)
            k.missedReads = min(max(k.missedReads, 0), Self.dropAfterMissedReads)
            known[bundle] = k
        }
        c.knownBundles = Self.capped(known, Self.knownBundlesCap) { $0.lastSeen }
        c.newShown = Self.capped(newShown.filter { Self.isBundle($0.key) }.mapValues(Self.time),
                                   Self.newShownCap) { $0 }
        c.choices = Self.capped(choices.filter { Self.isBundle($0.key) }, Self.choicesCap) { _ in 0 }
        c.toasts = Self.capped(toasts.filter { Self.isBundle($0.key) }.mapValues { max($0, 0) },
                               Self.toastCap) { Double($0) }
        return c
    }

    /// Page Restore Defaults (§4.9): the per-app choices and the new-icon list go; what was read stays.
    package func restoringDefaults() -> IconsAppsState {
        var c = self
        c.choices = [:]
        c.newShown = [:]
        return c
    }

    /// Bundle ids as Awake validates them (reverse-DNS ASCII, ≤ 255 bytes).
    package static func isBundle(_ s: String) -> Bool { AwakeBundleID.isValid(s) }

    private static func time(_ t: Double) -> Double { t.isFinite && t > 0 ? t : 0 }

    /// The `cap` entries with the highest `rank`, ties broken by key.
    private static func capped<V>(_ map: [String: V], _ cap: Int, rank: (V) -> Double) -> [String: V] {
        guard map.count > cap else { return map }
        let kept = map.sorted { a, b in
            let ra = rank(a.value), rb = rank(b.value)
            return ra != rb ? ra > rb : a.key < b.key
        }.prefix(cap)
        return Dictionary(kept.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
    }
}

extension KeyedDecodingContainer {
    /// A bundle-keyed object decoded entry by entry: a bad value is skipped and the rest kept; a missing or non-object
    /// value gives an empty map. At most 4 × the largest cap entries are read (sanitize caps the rest).
    fileprivate func lossyBundleMap<V: Decodable>(_ key: Key) -> [String: V] {
        guard let nested = try? nestedContainer(keyedBy: AnyCodingKey.self, forKey: key) else { return [:] }
        var out: [String: V] = [:]
        for k in nested.allKeys.prefix(4 * IconsAppsState.knownBundlesCap) {
            if let v = try? nested.decode(V.self, forKey: k) { out[k.stringValue] = v }
        }
        return out
    }
}
