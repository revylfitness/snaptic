import Foundation

// Composition of the Displays settings (lead). Each section type lives in its
// owning team's Config file; teams add fields there only (PLAN A.4).

package struct DisplaysConfig: ConfigModel {
    package var features: LossyMap<DisplayFeature, Bool>
    package var perDisplay: LossyMap<DisplayKey, PerDisplayConfig>
    package var brightness: BrightnessConfig
    package var ddc: DDCConfig
    package var keys: KeysConfig
    package var color: ColorConfig
    package var resolution: ResolutionConfig
    package var virtualScreens: VirtualConfig
    package var management: ManagementConfig
    package var layouts: LayoutsConfig
    package var pip: PIPConfig
    package var automation: AutomationConfig
    package var safety: SafetyConfig
    package var identity: IdentityConfig
    package var menu: MenuConfig

    package static let maxRememberedDisplays = 64

    package init() {
        features = LossyMap()
        perDisplay = LossyMap()
        brightness = BrightnessConfig()
        ddc = DDCConfig()
        keys = KeysConfig()
        color = ColorConfig()
        resolution = ResolutionConfig()
        virtualScreens = VirtualConfig()
        management = ManagementConfig()
        layouts = LayoutsConfig()
        pip = PIPConfig()
        automation = AutomationConfig()
        safety = SafetyConfig()
        identity = IdentityConfig()
        menu = MenuConfig()
    }

    private enum CodingKeys: String, CodingKey {
        case features, perDisplay, brightness, ddc, keys, color, resolution, virtualScreens, management, layouts, pip,
             automation, safety, identity, menu
    }

    // Field by field: a bad section falls back to its defaults without touching the others.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        features = c.lossy(.features, LossyMap())
        perDisplay = c.lossy(.perDisplay, LossyMap())
        brightness = c.lossy(.brightness, BrightnessConfig())
        ddc = c.lossy(.ddc, DDCConfig())
        keys = c.lossy(.keys, KeysConfig())
        color = c.lossy(.color, ColorConfig())
        resolution = c.lossy(.resolution, ResolutionConfig())
        virtualScreens = c.lossy(.virtualScreens, VirtualConfig())
        management = c.lossy(.management, ManagementConfig())
        layouts = c.lossy(.layouts, LayoutsConfig())
        pip = c.lossy(.pip, PIPConfig())
        automation = c.lossy(.automation, AutomationConfig())
        safety = c.lossy(.safety, SafetyConfig())
        identity = c.lossy(.identity, IdentityConfig())
        menu = c.lossy(.menu, MenuConfig())
    }

    package func sanitized() -> DisplaysConfig {
        var c = self
        c.perDisplay.dropUnknown(keepingAtMost: 0)
        if c.perDisplay.values.count > Self.maxRememberedDisplays {
            // Keep a deterministic subset; teams' identity data decides recency later.
            let keep = c.perDisplay.values.keys.sorted { $0.rawValue < $1.rawValue }.prefix(Self.maxRememberedDisplays)
            c.perDisplay = LossyMap(Dictionary(uniqueKeysWithValues: keep.map { ($0, c.perDisplay.values[$0]!) }))
        }
        c.perDisplay = LossyMap(c.perDisplay.values.mapValues { $0.sanitized() })
        c.brightness = c.brightness.sanitized()
        c.ddc = c.ddc.sanitized()
        c.keys = c.keys.sanitized()
        c.color = c.color.sanitized()
        c.resolution = c.resolution.sanitized()
        c.virtualScreens = c.virtualScreens.sanitized()
        c.management = c.management.sanitized()
        c.layouts = c.layouts.sanitized()
        c.pip = c.pip.sanitized()
        c.automation = c.automation.sanitized()
        c.safety = c.safety.sanitized()
        c.identity = c.identity.sanitized()
        c.menu = c.menu.sanitized()
        return c
    }

    /// Raw feature choices as a plain dictionary (for FeatureGraph).
    package var rawFeatures: [DisplayFeature: Bool] { features.values }
}

package struct PerDisplayConfig: ConfigModel {
    package var brightness: PerDisplayBrightness
    package var ddc: PerDisplayDDC
    package var keys: PerDisplayKeys
    package var color: PerDisplayColor
    package var resolution: PerDisplayResolution
    package var management: PerDisplayManagement
    package var identity: PerDisplayIdentity
    package var pip: PerDisplayPIP

    package init() {
        brightness = PerDisplayBrightness()
        ddc = PerDisplayDDC()
        keys = PerDisplayKeys()
        color = PerDisplayColor()
        resolution = PerDisplayResolution()
        management = PerDisplayManagement()
        identity = PerDisplayIdentity()
        pip = PerDisplayPIP()
    }

    private enum CodingKeys: String, CodingKey { case brightness, ddc, keys, color, resolution, management, identity, pip }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = c.lossy(.brightness, PerDisplayBrightness())
        ddc = c.lossy(.ddc, PerDisplayDDC())
        keys = c.lossy(.keys, PerDisplayKeys())
        color = c.lossy(.color, PerDisplayColor())
        resolution = c.lossy(.resolution, PerDisplayResolution())
        management = c.lossy(.management, PerDisplayManagement())
        identity = c.lossy(.identity, PerDisplayIdentity())
        pip = c.lossy(.pip, PerDisplayPIP())
    }

    package func sanitized() -> PerDisplayConfig {
        var c = self
        c.brightness = c.brightness.sanitized()
        c.ddc = c.ddc.sanitized()
        c.keys = c.keys.sanitized()
        c.color = c.color.sanitized()
        c.resolution = c.resolution.sanitized()
        c.management = c.management.sanitized()
        c.identity = c.identity.sanitized()
        c.pip = c.pip.sanitized()
        return c
    }
}

// MARK: - 0.3: sections, restore scopes, migrations (lead; §4.5, §4.6, R5-2)

/// One case per `DisplaysConfig` field, with `perDisplay` split per subsection (consistency m8; R5-2: no
/// `migrations` case). Controllers declare the sections they observe (`observedSections`).
package enum DisplaysConfigSection: String, CaseIterable, Sendable {
    case features, brightness, ddc, keys, color, resolution, virtualScreens, management, layouts, pip, automation,
         safety, identity, menu
    case perDisplayBrightness, perDisplayDDC, perDisplayKeys, perDisplayColor, perDisplayResolution,
         perDisplayManagement, perDisplayIdentity, perDisplayPIP

    /// The per-display subsections.
    package static let perDisplaySections: Set<DisplaysConfigSection> = [
        .perDisplayBrightness, .perDisplayDDC, .perDisplayKeys, .perDisplayColor, .perDisplayResolution,
        .perDisplayManagement, .perDisplayIdentity, .perDisplayPIP,
    ]
}

/// Page Restore Defaults scopes (consistency M7). `.all` = Displays › Advanced; the others = that sub-page's
/// Advanced sheet. `color(nil)` = every display, `color(key)` = "This display".
package enum DisplaysRestoreScope: Equatable, Sendable {
    case all, brightness, color(DisplayKey?), hardware, keyboard, layouts, virtualDisplays, pip, automations, confirm
}

extension DisplaysConfig {
    /// The sections whose values differ. Non-empty whenever `old != new`.
    package static func changedSections(old: DisplaysConfig, new: DisplaysConfig) -> Set<DisplaysConfigSection> {
        var s = Set<DisplaysConfigSection>()
        if old.features != new.features { s.insert(.features) }
        if old.brightness != new.brightness { s.insert(.brightness) }
        if old.ddc != new.ddc { s.insert(.ddc) }
        if old.keys != new.keys { s.insert(.keys) }
        if old.color != new.color { s.insert(.color) }
        if old.resolution != new.resolution { s.insert(.resolution) }
        if old.virtualScreens != new.virtualScreens { s.insert(.virtualScreens) }
        if old.management != new.management { s.insert(.management) }
        if old.layouts != new.layouts { s.insert(.layouts) }
        if old.pip != new.pip { s.insert(.pip) }
        if old.automation != new.automation { s.insert(.automation) }
        if old.safety != new.safety { s.insert(.safety) }
        if old.identity != new.identity { s.insert(.identity) }
        if old.menu != new.menu { s.insert(.menu) }
        if old.perDisplay != new.perDisplay {
            let keys = Set(old.perDisplay.values.keys).union(new.perDisplay.values.keys)
            for key in keys {
                let a = old.perDisplay[key], b = new.perDisplay[key]
                if a?.brightness != b?.brightness { s.insert(.perDisplayBrightness) }
                if a?.ddc != b?.ddc { s.insert(.perDisplayDDC) }
                if a?.keys != b?.keys { s.insert(.perDisplayKeys) }
                if a?.color != b?.color { s.insert(.perDisplayColor) }
                if a?.resolution != b?.resolution { s.insert(.perDisplayResolution) }
                if a?.management != b?.management { s.insert(.perDisplayManagement) }
                if a?.identity != b?.identity { s.insert(.perDisplayIdentity) }
                if a?.pip != b?.pip { s.insert(.perDisplayPIP) }
            }
            // Only entries under unknown keys differ (kept for a newer Snaptic): every subsection may care.
            if s.isDisjoint(with: DisplaysConfigSection.perDisplaySections) {
                s.formUnion(DisplaysConfigSection.perDisplaySections)
            }
        }
        return s
    }

    /// Page Restore Defaults (§4.6): only `scope` goes back to defaults. Display identities (names, fingerprints)
    /// are never reset here, so remembered displays keep their keys.
    package func restoringDefaults(scope: DisplaysRestoreScope) -> DisplaysConfig {
        var c = self
        func eachDisplay(_ change: (inout PerDisplayConfig) -> Void) {
            var map = c.perDisplay
            for key in map.values.keys {
                guard var entry = map.values[key] else { continue }
                change(&entry)
                map.values[key] = entry
            }
            c.perDisplay = map
        }
        switch scope {
        case .all:
            let identities = perDisplay.values.mapValues(\.identity)
            c = DisplaysConfig()
            c.identity = identity
            var map = LossyMap<DisplayKey, PerDisplayConfig>()
            for (key, id) in identities {
                var entry = PerDisplayConfig()
                entry.identity = id
                map[key] = entry
            }
            c.perDisplay = map
        case .brightness:
            c.brightness = BrightnessConfig()
            eachDisplay { $0.brightness = PerDisplayBrightness() }
        case .color(let key):
            if let key {
                if var entry = c.perDisplay[key] {
                    entry.color = PerDisplayColor()
                    c.perDisplay[key] = entry
                }
            } else {
                c.color = ColorConfig()
                eachDisplay { $0.color = PerDisplayColor() }
            }
        case .hardware:
            c.ddc = DDCConfig()
            eachDisplay { $0.ddc = PerDisplayDDC() }
        case .keyboard:
            c.keys = KeysConfig()
            eachDisplay { $0.keys = PerDisplayKeys() }
        case .layouts:
            c.layouts = LayoutsConfig()
        case .virtualDisplays:
            c.virtualScreens = VirtualConfig()
        case .pip:
            c.pip = PIPConfig()
            eachDisplay { $0.pip = PerDisplayPIP() }
        case .automations:
            c.automation = AutomationConfig()
        case .confirm:
            c.safety = SafetyConfig()
        }
        return c
    }

    /// M4, then M5, then M10 (R5-2), each only while its marker is absent; records each marker it ran. Pure;
    /// ModuleHost runs it after loading the ledger. Legacy fields stay as they are (0.2 still reads them).
    package func migrated(ledger: inout MigrationLedger) -> DisplaysConfig {
        var c = self
        if !ledger.has(.menuShortcuts) {
            // M4: the panel and Identify shortcuts become ordinary Displays shortcuts, when those are unset.
            if c.keys.shortcuts[.fShowPanel] == nil, let combo = c.menu.showPanelShortcut {
                c.keys.shortcuts[.fShowPanel] = combo
            }
            if c.keys.shortcuts[.fIdentify] == nil, let combo = c.menu.identifyShortcut {
                c.keys.shortcuts[.fIdentify] = combo
            }
            ledger.record(.menuShortcuts)
        }
        if !ledger.has(.showNits) {
            // M5: once (r1 re-ran the OR on every decode, so a later "off" came back).
            if c.keys.osdShowNits { c.brightness.showNits = true }
            ledger.record(.showNits)
        }
        if !ledger.has(.powerSwitch) {
            // M10: the header power switch becomes a top-level item under the display's row.
            let switches = Set(c.perDisplay.values.values.map(\.management.powerSwitch))
            if switches.contains(.disconnect) { c.menu.items[.dDisconnectItem] = .visible }
            if switches.contains(.ddcStandby) { c.menu.items[.cDDCPower] = .visible }
            ledger.record(.powerSwitch)
        }
        return c
    }
}
