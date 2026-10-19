import Foundation
@testable import SnapticKit

/// Full config values for the control key cross-check (lead; PLAN 0.3 §4.8 test 5, R5-13): every feature on, one
/// per-display entry, the optionals set, one element in every list and map (step-3 exit).
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
        entry.brightness.nits = NitsRange(minimum: 0.5, maximum: 500, peak: 1_000, isEstimate: true)
        entry.keys.audioDeviceName = "Speakers"
        entry.ddc.framing = DDCFraming.allCases.first
        var tuning = DDCControlTuning()
        tuning.enabled = true
        tuning.maximum = 100
        tuning.showInMenu = true
        entry.ddc.controls[VCPKey(0x10)] = tuning
        entry.ddc.inputs = [DDCInputEntry(value: 0x0F, name: "DisplayPort")]
        entry.ddc.unlockedCodes = [VCPKey(0xE0)]
        entry.ddc.customControls = [DDCCustomControl(name: "Sharpness", code: 0x87, kind: .range)]
        let mode = ModeRef(ioModeID: 1, pixelWidth: 3_840, pixelHeight: 2_160, pointWidth: 1_920, pointHeight: 1_080,
                           refreshMilliHz: 60_000)
        entry.resolution.favorites = [FavoriteMode(mode)]
        entry.resolution.minWidth = 1_024
        entry.resolution.maxWidth = 3_840
        entry.resolution.refreshFilter = 60
        entry.resolution.bitDepthFilter = 10
        entry.resolution.persisted = PersistedModeChoice(mode: mode, preKeepMode: mode, recordedAt: 1)
        entry.identity.fingerprint = FingerprintRecord(t1: "1", t2: "2", t3: "3", t4: "4", t5: "5")
        var pip = PIPConfiguration(name: "Stream", kind: .fullScreen)
        pip.target = displayKey
        pip.windowFrame = PIPRect(x: 0, y: 0, width: 640, height: 360)
        pip.crop = PIPRect(x: 0, y: 0, width: 1, height: 1)
        pip.filters = [FilterInstance(kind: FilterKind.allCases[0])]
        pip.lutID = StableID()
        entry.pip.configurations = [pip]
        c.perDisplay[displayKey] = entry
        c.brightness.syncSource = displayKey
        c.resolution.scaleMatchReference = displayKey
        c.keys.osdStyle = .classic
        c.keys.osdPosition = .center
        c.keys.shortcuts[.fShowPanel] = combo
        c.safety.panicHotkey = combo
        c.menu.showPanelShortcut = combo
        c.menu.identifyShortcut = HotkeyCombo(keyCode: 4, carbonModifiers: 0x0100)
        c.menu.items[DisplayMenuItemID(rawValue: "c.brightness.slider")] = .visible
        c.menu.hiddenDisplays = [displayKey]
        c.menu.displayOrder = [displayKey]
        c.menu.collapsedDisplays = [displayKey]
        c.keys.inputSlots = [InputSlot(display: displayKey, value: 0x11)]
        let spec = VirtualScreenSpec(name: "Virtual", aspectWidth: 16, aspectHeight: 9, sizeInches: 27, hiDPI: true,
                                     modes: [VirtualMode(width: 2_560, height: 1_440, hiDPI: true)],
                                     primaries: VirtualPrimaries(redX: 0.68, redY: 0.32, greenX: 0.265, greenY: 0.69,
                                                                 blueX: 0.15, blueY: 0.06, whiteX: 0.3127, whiteY: 0.329),
                                     associations: [VirtualAssociation(target: displayKey)])
        c.virtualScreens.screens = [spec]
        c.virtualScreens.connected[spec.id] = true
        c.virtualScreens.smartHiDPI[displayKey] = SmartHiDPIPair(mode: VirtualMode(width: 2_560, height: 1_440, hiDPI: true))
        c.virtualScreens.lastOrigins[spec.id] = VirtualOrigin(x: 0, y: 0)
        let state = ProtectedDisplayState(mode: mode, x: 0, y: 0, rotation: 0, mirrorOf: displayKey, isMain: true)
        c.management.protection[DisplaySetKey(keys: [displayKey])!] = ProtectionProfile(displays: [displayKey: state],
                                                                                        capturedAt: 1)
        let saved = SavedDisplaySettings(mode: mode, x: 0, y: 0, isMain: true, rotation: 0, mirrorOf: displayKey,
                                         brightness: 0.5, adjustments: ["gamma": 1], ddcInput: 0x0F, volume: 0.5,
                                         identity: LayoutDisplayIdentity(tier1: "1", tier2: "2"))
        c.layouts.layouts = [SavedLayout(name: "Desk", displays: [displayKey: saved], nightShift: true,
                                         virtualScreens: [spec.id: true], trust: TrustStamp(digest: "d", osMajor: 15))]
        c.pip.windowConfigurations = [PIPConfiguration(name: "Window")]
        c.pip.luts = [PIPLUTReference(name: "Film", size: 33)]
        c.automation.hooks = [HookSpec(name: "Hook", display: displayKey,
                                       command: CommandSpec(executable: "/usr/bin/true", arguments: ["-x"]))]
        c.automation.actions = [CustomActionSpec(name: "Action", command: CommandSpec(executable: "/usr/bin/true"),
                                                 shortcut: combo)]
        c.safety.preConfirmAllowed[displayKey] = PreConfirmAllowList(entries: ["mode"])
        c.safety.keptModes[displayKey] = KeptModes(modes: [mode])
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
        c.sessions.presets.append(AwakePreset(id: StableID.derived(namespace: "awake.preset.test", name: "idle"),
                                              name: "Until idle", kind: .untilIdle(UntilIdleSpec(), maxSeconds: 7_200),
                                              options: AwakeSessionOptions()))
        var trigger = AwakeTrigger(id: StableID.derived(namespace: "awake.trigger.test", name: "dock"), name: "Dock",
                                   criteria: [AwakeCriterionEntry(.usbDevice(vendor: 1, product: 2, serialHash: "h",
                                                                             name: "Dock"))])
        trigger.resumeAfterManualEndMinutes = 30
        c.triggers.triggers = [trigger]
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
