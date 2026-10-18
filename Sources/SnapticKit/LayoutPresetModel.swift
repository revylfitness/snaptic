import Foundation

// Saved display layouts ("Layouts"), trust stamps and match rules (owner: D).
// PLAN §9.7, R5.4 naming, R5.7 trust rules.

/// Integrity stamp over a saved layout (not authentication; R5.7). The digest is
/// SHA-256 (computed in the app) of `LayoutPresetModel.trustInput(…)`.
package struct TrustStamp: Codable, Equatable, Sendable {
    package var digest: String
    /// macOS major version the stamp was made on; an OS major update clears trust.
    package var osMajor: Int

    package init(digest: String = "", osMajor: Int = 0) {
        self.digest = digest
        self.osMajor = osMajor
    }

    private enum CodingKeys: String, CodingKey { case digest, osMajor }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        digest = c.lossy(.digest, "")
        osMajor = c.lossy(.osMajor, 0)
    }
}

/// When a layout applies by itself (§4.11 step 3).
package enum LayoutAutoApply: String, Codable, CaseIterable, Sendable {
    case never
    /// The connected presented displays are exactly the referenced ones.
    case whenExactly
    /// The connected displays include every referenced one.
    case whenIncludes
}

/// How a referenced display was identified when the layout was saved (R5.7).
package struct LayoutDisplayIdentity: Codable, Equatable, Sendable {
    /// Tier 1 (EDID hash + alphanumeric serial) digest, when the display has a serial.
    package var tier1: String?
    /// Tier 2 (UUID) digest; matching on it alone shows a "no serial" warning.
    package var tier2: String?

    package init(tier1: String?, tier2: String?) {
        self.tier1 = tier1
        self.tier2 = tier2
    }
}

package struct SavedDisplaySettings: Codable, Equatable, Sendable {
    package var mode: ModeRef?
    package var x: Int32?
    package var y: Int32?
    package var isMain: Bool?
    package var rotation: Int?
    /// The presented display this one mirrors. `mirrorSet` false = leave mirroring alone.
    package var mirrorOf: DisplayKey?
    package var mirrorSet: Bool
    /// 0…1.
    package var brightness: Double?
    /// Software adjustments by name (owned by the color feature; opaque here).
    package var adjustments: [String: Double]?
    /// Never part of auto-apply (§9.7).
    package var ddcInput: UInt16?
    /// 0…1.
    package var volume: Double?
    package var identity: LayoutDisplayIdentity

    package init(mode: ModeRef? = nil, x: Int32? = nil, y: Int32? = nil, isMain: Bool? = nil, rotation: Int? = nil,
                 mirrorOf: DisplayKey? = nil, mirrorSet: Bool = false, brightness: Double? = nil,
                 adjustments: [String: Double]? = nil, ddcInput: UInt16? = nil, volume: Double? = nil,
                 identity: LayoutDisplayIdentity = LayoutDisplayIdentity(tier1: nil, tier2: nil)) {
        self.mode = mode
        self.x = x
        self.y = y
        self.isMain = isMain
        self.rotation = rotation
        self.mirrorOf = mirrorOf
        self.mirrorSet = mirrorSet
        self.brightness = brightness
        self.adjustments = adjustments
        self.ddcInput = ddcInput
        self.volume = volume
        self.identity = identity
    }

    private enum CodingKeys: String, CodingKey {
        case mode, x, y, isMain, rotation, mirrorOf, mirrorSet, brightness, adjustments, ddcInput, volume, identity
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = c.lossy(.mode, nil)
        x = c.lossy(.x, nil)
        y = c.lossy(.y, nil)
        isMain = c.lossy(.isMain, nil)
        rotation = c.lossy(.rotation, nil)
        mirrorOf = c.lossy(.mirrorOf, nil)
        mirrorSet = c.lossy(.mirrorSet, false)
        brightness = c.lossy(.brightness, nil)
        adjustments = c.lossy(.adjustments, nil)
        ddcInput = c.lossy(.ddcInput, nil)
        volume = c.lossy(.volume, nil)
        identity = c.lossy(.identity, LayoutDisplayIdentity(tier1: nil, tier2: nil))
    }

    package func sanitized() -> SavedDisplaySettings {
        var s = self
        if let b = brightness { s.brightness = b.isFinite ? min(1, max(0, b)) : nil }
        if let v = volume { s.volume = v.isFinite ? min(1, max(0, v)) : nil }
        if let r = rotation, ![0, 90, 180, 270].contains(r) { s.rotation = nil }
        if let a = adjustments {
            let clean = a.filter { $0.value.isFinite && $0.key.unicodeScalars.count <= 32 }
            s.adjustments = clean.count > 32 ? Dictionary(uniqueKeysWithValues: clean.sorted { $0.key < $1.key }.prefix(32).map { ($0.key, $0.value) }) : clean
        }
        if !mirrorSet { s.mirrorOf = nil }
        return s
    }

    /// Content that needs a trial when applied (not just low-risk origins/main/brightness).
    package var hasTrialContent: Bool { rotation != nil || mirrorSet }
}

package struct SavedLayout: Codable, Equatable, Sendable {
    package var id: StableID
    package var name: String
    package var displays: LossyMap<DisplayKey, SavedDisplaySettings>
    package var nightShift: Bool?
    package var virtualScreens: LossyMap<StableID, Bool>
    package var autoApply: LayoutAutoApply
    /// Higher wins.
    package var priority: Int
    package var trust: TrustStamp?

    package static let maxNameScalars = 64

    package init(id: StableID = StableID(), name: String, displays: [DisplayKey: SavedDisplaySettings] = [:],
                 nightShift: Bool? = nil, virtualScreens: [StableID: Bool] = [:], autoApply: LayoutAutoApply = .never,
                 priority: Int = 0, trust: TrustStamp? = nil) {
        self.id = id
        self.name = name
        self.displays = LossyMap(displays)
        self.nightShift = nightShift
        self.virtualScreens = LossyMap(virtualScreens)
        self.autoApply = autoApply
        self.priority = priority
        self.trust = trust
    }

    private enum CodingKeys: String, CodingKey { case id, name, displays, nightShift, virtualScreens, autoApply, priority, trust }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(StableID.self, forKey: .id)
        name = c.lossy(.name, L("Layout"))
        displays = c.lossy(.displays, LossyMap())
        nightShift = c.lossy(.nightShift, nil)
        virtualScreens = c.lossy(.virtualScreens, LossyMap())
        autoApply = c.lossy(.autoApply, .never)
        priority = c.lossy(.priority, 0)
        trust = c.lossy(.trust, nil)
    }

    package var referencedKeys: Set<DisplayKey> { Set(displays.values.keys) }

    package var hasTrialContent: Bool { displays.values.values.contains { $0.hasTrialContent } }

    package func sanitized() -> SavedLayout {
        var s = self
        let clean = TextSanitizer.clean(name, maxScalars: Self.maxNameScalars).trimmingCharacters(in: .whitespaces)
        s.name = clean.isEmpty ? L("Layout") : clean
        s.displays.dropUnknown(keepingAtMost: 0)
        s.virtualScreens.dropUnknown(keepingAtMost: 0)
        if s.displays.values.count > DisplaySetKey.maxDisplays {
            let current = s.displays.values
            let keep = current.keys.sorted { $0.rawValue < $1.rawValue }.prefix(DisplaySetKey.maxDisplays)
            s.displays = LossyMap(Dictionary(uniqueKeysWithValues: keep.compactMap { k in current[k].map { (k, $0) } }))
        }
        s.displays = LossyMap(s.displays.values.mapValues { $0.sanitized() })
        // Mirrors must point inside the layout.
        let keys = s.referencedKeys
        let settled = s.displays.values
        for (k, v) in settled where v.mirrorOf.map({ !keys.contains($0) || $0 == k }) == true {
            var fixed = v
            fixed.mirrorOf = nil
            fixed.mirrorSet = false
            s.displays[k] = fixed
        }
        s.priority = min(100, max(-100, priority))
        if s.virtualScreens.values.count > 8 {
            let current = s.virtualScreens.values
            let keep = current.keys.sorted { $0.rawValue < $1.rawValue }.prefix(8)
            s.virtualScreens = LossyMap(Dictionary(uniqueKeysWithValues: keep.compactMap { k in current[k].map { (k, $0) } }))
        }
        if let t = trust, t.digest.isEmpty || t.digest.utf8.count > 128 { s.trust = nil }
        return s
    }
}

/// A connected presented display, for matching (Snaptic virtual internals excluded).
package struct LiveLayoutDisplay: Equatable, Sendable {
    package var key: DisplayKey
    package var identity: LayoutDisplayIdentity

    package init(key: DisplayKey, identity: LayoutDisplayIdentity) {
        self.key = key
        self.identity = identity
    }
}

/// A presented display's live arrangement, for `LayoutPresetModel.isCurrent`.
package struct LayoutLiveState: Equatable, Sendable {
    package var mode: ModeRef?
    package var x: Int32
    package var y: Int32
    package var isMain: Bool
    package var rotation: Int
    package var mirrorOf: DisplayKey?

    package init(mode: ModeRef?, x: Int32, y: Int32, isMain: Bool, rotation: Int, mirrorOf: DisplayKey?) {
        self.mode = mode
        self.x = x
        self.y = y
        self.isMain = isMain
        self.rotation = rotation
        self.mirrorOf = mirrorOf
    }
}

package struct LayoutMatch: Equatable, Sendable {
    package var layoutID: StableID
    package var exact: Bool
    /// Some referenced display matched by UUID only (no serial).
    package var usesTier2: Bool

    package init(layoutID: StableID, exact: Bool, usesTier2: Bool) {
        self.layoutID = layoutID
        self.exact = exact
        self.usesTier2 = usesTier2
    }
}

package enum LayoutPresetModel {
    package static let maxLayouts = 32

    /// Whether `layout` matches the connected displays. Every referenced display must be
    /// present and identified by tier 1, or by tier 2 when the saved identity has no tier 1.
    package static func match(_ layout: SavedLayout, live: [LiveLayoutDisplay]) -> LayoutMatch? {
        let referenced = layout.referencedKeys
        guard !referenced.isEmpty else { return nil }
        let byKey = Dictionary(live.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var tier2 = false
        for key in referenced {
            guard let saved = layout.displays[key], let now = byKey[key] else { return nil }
            if let t1 = saved.identity.tier1 {
                guard now.identity.tier1 == t1 else { return nil }
            } else if let t2 = saved.identity.tier2 {
                guard now.identity.tier2 == t2 else { return nil }
                tier2 = true
            } else {
                return nil
            }
        }
        let exact = Set(byKey.keys) == referenced
        return LayoutMatch(layoutID: layout.id, exact: exact, usesTier2: tier2)
    }

    /// The auto-apply candidate: matching layouts with auto-apply on, by priority, then
    /// most specific (most displays), then exact over includes, then name and id.
    package static func select(_ layouts: [SavedLayout], live: [LiveLayoutDisplay]) -> (layout: SavedLayout, match: LayoutMatch)? {
        var candidates: [(SavedLayout, LayoutMatch)] = []
        for l in layouts where l.autoApply != .never {
            guard let m = match(l, live: live) else { continue }
            if l.autoApply == .whenExactly && !m.exact { continue }
            candidates.append((l, m))
        }
        candidates.sort { a, b in
            if a.0.priority != b.0.priority { return a.0.priority > b.0.priority }
            if a.0.displays.values.count != b.0.displays.values.count { return a.0.displays.values.count > b.0.displays.values.count }
            if a.1.exact != b.1.exact { return a.1.exact }
            if a.0.name != b.0.name { return a.0.name < b.0.name }
            return a.0.id.rawValue < b.0.id.rawValue
        }
        return candidates.first.map { (layout: $0.0, match: $0.1) }
    }

    /// The menu's "Apply Matching Layout" (0.3 §5.2): every matching layout, whatever its auto-apply setting, by the
    /// same order as `select` (priority, most displays, exact, name, id).
    package static func bestMatch(_ layouts: [SavedLayout], live: [LiveLayoutDisplay]) -> SavedLayout? {
        let manual = layouts.map { l -> SavedLayout in
            var copy = l
            copy.autoApply = .whenIncludes
            return copy
        }
        guard let picked = select(manual, live: live) else { return nil }
        return layouts.first { $0.id == picked.layout.id }
    }

    /// Whether the displays are arranged as `layout` says right now (the menu's checkmark). Every referenced display
    /// must be present; only the fields the layout saved are compared (mode by shape, origin unless mirrored, main,
    /// rotation, mirroring). A layout that saves nothing comparable is never current.
    package static func isCurrent(_ layout: SavedLayout, states: [DisplayKey: LayoutLiveState]) -> Bool {
        let saved = layout.displays.values
        guard !saved.isEmpty else { return false }
        var compared = false
        for (key, s) in saved {
            guard let now = states[key] else { return false }
            if let m = s.mode {
                guard let live = now.mode, live.sameShape(as: m) else { return false }
                compared = true
            }
            if let x = s.x, let y = s.y, !(s.mirrorSet && s.mirrorOf != nil) {
                guard now.x == x && now.y == y else { return false }
                compared = true
            }
            if s.isMain == true {
                guard now.isMain else { return false }
                compared = true
            }
            if let r = s.rotation {
                guard now.rotation == r else { return false }
                compared = true
            }
            if s.mirrorSet {
                guard now.mirrorOf == s.mirrorOf else { return false }
                compared = true
            }
        }
        return compared
    }

    /// Canonical bytes the trust digest covers: the layout content (without name, trust,
    /// priority or auto-apply), the matched displays' tier-1 identities, and the OS major.
    /// Nil when a referenced display has no tier-1 identity (trust needs tier 1, R5.7).
    package static func trustInput(_ layout: SavedLayout, osMajor: Int) -> Data? {
        var lines: [String] = ["snaptic-layout-trust-v1", "os=\(osMajor)"]
        for key in layout.referencedKeys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let d = layout.displays[key], let t1 = d.identity.tier1, !t1.isEmpty else { return nil }
            var parts = ["d=\(key.rawValue)", "id=\(t1)"]
            if let m = d.mode {
                parts.append("mode=\(m.ioModeID),\(m.pixelWidth)x\(m.pixelHeight),\(m.pointWidth)x\(m.pointHeight)@\(m.refreshMilliHz)")
            }
            if let x = d.x, let y = d.y { parts.append("at=\(x),\(y)") }
            if let main = d.isMain { parts.append("main=\(main)") }
            if let r = d.rotation { parts.append("rot=\(r)") }
            if d.mirrorSet { parts.append("mirror=\(d.mirrorOf?.rawValue ?? "none")") }
            if let b = d.brightness { parts.append("b=\(Int((b * 1000).rounded()))") }
            if let a = d.adjustments {
                for (k, v) in a.sorted(by: { $0.key < $1.key }) { parts.append("adj.\(k)=\(Int((v * 1000).rounded()))") }
            }
            if let i = d.ddcInput { parts.append("input=\(i)") }
            if let v = d.volume { parts.append("vol=\(Int((v * 1000).rounded()))") }
            lines.append(parts.joined(separator: ";"))
        }
        if let ns = layout.nightShift { lines.append("nightShift=\(ns)") }
        for (id, on) in layout.virtualScreens.values.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            lines.append("virtual=\(id.rawValue):\(on)")
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// Whether a stamp is still valid: same digest of the current content and OS major.
    /// `digest` is the app's SHA-256 (hex) of `trustInput`.
    package static func isTrusted(_ layout: SavedLayout, osMajor: Int, digest: (Data) -> String) -> Bool {
        guard let stamp = layout.trust, stamp.osMajor == osMajor, !stamp.digest.isEmpty,
              let input = trustInput(layout, osMajor: osMajor) else { return false }
        return digest(input) == stamp.digest
    }

    /// A fresh stamp (granted after a manual apply the user kept).
    package static func stamp(_ layout: SavedLayout, osMajor: Int, digest: (Data) -> String) -> TrustStamp? {
        guard let input = trustInput(layout, osMajor: osMajor) else { return nil }
        return TrustStamp(digest: digest(input), osMajor: osMajor)
    }

    /// Clears trust when a referenced display's live tier-1 identity no longer matches.
    package static func revalidated(_ layout: SavedLayout, live: [LiveLayoutDisplay]) -> SavedLayout {
        guard layout.trust != nil else { return layout }
        let byKey = Dictionary(live.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for (key, saved) in layout.displays.values {
            if let now = byKey[key], let t1 = saved.identity.tier1, now.identity.tier1 != nil, now.identity.tier1 != t1 {
                var copy = layout
                copy.trust = nil
                return copy
            }
        }
        return layout
    }
}
