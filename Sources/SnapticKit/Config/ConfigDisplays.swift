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
