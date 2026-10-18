import Foundation
@testable import SnapticKit

/// Full config values for the control key cross-check (lead; PLAN 0.3 §4.8 test 5, R5-13): every feature on, one
/// per-display entry, the optionals set. Step 0 sets the top-level and per-display optionals; lists get one element
/// each when the cross-check is turned on (step-3 exit).
enum ConfigFixtures {
    static let displayKey = DisplayKey(rawValue: String(repeating: "c", count: 32))!
    static let combo = HotkeyCombo(keyCode: 3, carbonModifiers: 0x0100)

    static func fullDisplays() -> DisplaysConfig {
        var c = DisplaysConfig()
        for f in DisplayFeature.allCases { c.features[f] = true }
        var entry = PerDisplayConfig()
        entry.identity.customName = "Desk"
        entry.identity.symbol = "display"
        entry.identity.lastSeen = 1
        entry.identity.lastKnownName = "Desk"
        entry.brightness.method = .ddc
        entry.brightness.value = 0.5
        entry.brightness.switchover = 0.5
        entry.brightness.xdrMax = 1.5
        entry.brightness.gammaWorks = true
        entry.brightness.xdrOverlayWorks = true
        entry.brightness.xdrGammaWorks = true
        entry.keys.audioDeviceName = "Speakers"
        c.perDisplay[displayKey] = entry
        c.brightness.syncSource = displayKey
        c.resolution.scaleMatchReference = displayKey
        c.keys.osdStyle = .compact
        c.keys.osdPosition = .center
        c.keys.shortcuts[.fShowPanel] = combo
        c.safety.panicHotkey = combo
        c.menu.showPanelShortcut = combo
        c.menu.identifyShortcut = HotkeyCombo(keyCode: 4, carbonModifiers: 0x0100)
        return c
    }

    static func fullModules() -> ModulesConfig {
        var c = ModulesConfig()
        for id in ModuleID.allCases { c.modules[id] = ModulePreferences(enabled: true, presence: .ownIcon, symbol: "bolt") }
        c.sharedSymbol = "bolt"
        c.newModuleCards = NewModuleCard.allCases
        c.commandLine = CommandLineSettings(enabled: true, maySkipConfirmation: true)
        c.onboardingPermissions = Permission.allCases
        return c
    }

    static func fullAwake() -> AwakeConfig {
        var c = AwakeConfig()
        for f in AwakeFeature.allCases { c.features[f] = true }
        c.sessions.defaultPresetID = StableID.derived(namespace: "awake.preset.default", name: "1h")
        c.sessions.behavior.endAfterLockedHours = 4
        c.sessions.behavior.startAtLaunch = c.sessions.defaultPresetID
        c.sessions.recentApps = ["com.apple.Terminal"]
        c.shortcuts[AwakeActionID(rawValue: "awake.toggle")] = combo
        c.drives.volumes[VolumeUUIDKey(rawValue: "1B4E28BA-2FA1-11D2-883F-0016D3CCA427")!] =
            DriveAliveVolume(name: "Backup", enabled: true, firstWriteDone: true)
        return c
    }

    /// Dotted stored-property paths of `value` (R5-13 walker rules): Swift property names, not CodingKeys;
    /// LossyMap walks only `values`; Dictionary, Array, Set and LossyArray become `*`; Optional is unwrapped; an enum
    /// with a payload contributes its case name, then the payload labels. Every prefix is listed too.
    static func keyPaths(_ value: Any) -> Set<String> {
        var out = Set<String>()
        walk(value, prefix: "", into: &out)
        return out
    }

    private static func walk(_ value: Any, prefix: String, into out: inout Set<String>) {
        let mirror = Mirror(reflecting: value)
        func join(_ name: String) -> String { prefix.isEmpty ? name : prefix + "." + name }
        switch mirror.displayStyle {
        case .optional:
            if let child = mirror.children.first { walk(child.value, prefix: prefix, into: &out) }
        case .collection, .set:
            for child in mirror.children { walk(child.value, prefix: join("*"), into: &out) }
        case .dictionary:
            for child in mirror.children {
                let pair = Mirror(reflecting: child.value).children.map(\.value)
                if pair.count == 2 { walk(pair[1], prefix: join("*"), into: &out) }
            }
        case .enum:
            guard let child = mirror.children.first, let name = child.label else { return }
            let path = join(name)
            out.insert(path)
            walk(child.value, prefix: path, into: &out)
        case .tuple:
            for child in mirror.children {
                guard let label = child.label, !label.hasPrefix(".") else {
                    walk(child.value, prefix: prefix, into: &out)
                    continue
                }
                let path = join(label)
                out.insert(path)
                walk(child.value, prefix: path, into: &out)
            }
        case .struct, .class:
            let typeName = String(describing: mirror.subjectType)
            if typeName.hasPrefix("LossyMap<") {
                if let values = mirror.children.first(where: { $0.label == "values" }) {
                    walk(values.value, prefix: prefix, into: &out)
                }
                return
            }
            if typeName.hasPrefix("LossyArray<") {
                if let items = mirror.children.first(where: { $0.label == "items" }) {
                    walk(items.value, prefix: prefix, into: &out)
                }
                return
            }
            for child in mirror.children {
                guard let label = child.label else { continue }
                let path = join(label)
                out.insert(path)
                walk(child.value, prefix: path, into: &out)
            }
        default:
            return
        }
    }

    /// A path is covered when it or one of its ancestors is declared.
    static func isCovered(_ path: String, by declared: Set<String>) -> Bool {
        var parts = path.split(separator: ".").map(String.init)
        while !parts.isEmpty {
            if declared.contains(parts.joined(separator: ".")) { return true }
            parts.removeLast()
        }
        return false
    }
}
