import Foundation

// Keys, shortcuts and OSD settings (owner: C; OSD style/position live here per R5.1).

/// OSD look (PLAN §8.3): style and position are separate settings.
package enum OSDStyle: String, Codable, CaseIterable, Sendable {
    /// Big square HUD.
    case classic
    /// macOS 27.2-style rounded capsule with a segmented bar.
    case rounded

    package static func osDefault(majorVersion: Int) -> OSDStyle { majorVersion >= 27 ? .rounded : .classic }

    package var title: String {
        switch self {
        case .classic: return L("Classic")
        case .rounded: return L("Rounded")
        }
    }
}

package enum OSDPosition: String, Codable, CaseIterable, Sendable {
    case underIcon, topRight, topCenter, center, bottomCenter

    /// Under the icon on 14–26; top center on 27 (top-right stacks on the system HUD, R5.8).
    package static func osDefault(majorVersion: Int) -> OSDPosition { majorVersion >= 27 ? .topCenter : .underIcon }

    package var title: String {
        switch self {
        case .underIcon: return L("Under the menu-bar icon")
        case .topRight: return L("Top right")
        case .topCenter: return L("Top center")
        case .center: return L("Center")
        case .bottomCenter: return L("Bottom center")
        }
    }
}

/// Which display shows the OSD.
package enum OSDTarget: String, Codable, CaseIterable, Sendable {
    case affected, active, main

    package var title: String {
        switch self {
        case .affected: return L("The display that changed")
        case .active: return L("The active display")
        case .main: return L("The main display")
        }
    }
}

/// When brightness keys act on displays (PLAN §8.1).
package enum KeyPolicy: String, Codable, CaseIterable, Sendable {
    /// Only for displays macOS can't control (plus the XDR exception).
    case uncontrollableOnly
    case always

    package var title: String {
        switch self {
        case .uncontrollableOnly: return L("Only for displays macOS can't control")
        case .always: return L("Always")
        }
    }
}

/// Which display a key press targets.
package enum KeyTarget: String, Codable, CaseIterable, Sendable {
    case pointer, focusedWindow, all

    package var title: String {
        switch self {
        case .pointer: return L("The display with the pointer")
        case .focusedWindow: return L("The display with the focused window")
        case .all: return L("All displays")
        }
    }
}

/// When volume keys go to a display's DDC volume.
package enum VolumePolicy: String, Codable, CaseIterable, Sendable {
    /// When the output device matches the display (default).
    case matchingOutput
    /// When the output device has no volume control (USB DACs, HDMI audio).
    case noVolumeControl
    case always

    package var title: String {
        switch self {
        case .matchingOutput: return L("When the sound output is the display")
        case .noVolumeControl: return L("When the sound output has no volume control")
        case .always: return L("Always")
        }
    }
}

/// One of the ten "input slot" shortcuts: a display plus an input value.
package struct InputSlot: Codable, Equatable, Sendable {
    package var display: DisplayKey?
    package var value: UInt16
    package var lgAlt: Bool

    package init(display: DisplayKey? = nil, value: UInt16 = 0x0F, lgAlt: Bool = false) {
        self.display = display
        self.value = value
        self.lgAlt = lgAlt
    }

    private enum CodingKeys: String, CodingKey { case display, value, lgAlt }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        display = c.lossy(.display, nil as DisplayKey?)
        value = c.lossy(.value, UInt16(0x0F))
        lgAlt = c.lossy(.lgAlt, false)
    }
}

package struct KeysConfig: ConfigModel {
    package var brightnessPolicy: KeyPolicy
    /// "Also let macOS handle it", per key.
    package var brightnessAlsoSystem: Bool
    package var volumeAlsoSystem: Bool
    package var muteAlsoSystem: Bool
    package var target: KeyTarget
    /// Steps per full range (default 16; ⌥⇧ uses `fineSteps`).
    package var steps: Int
    package var fineSteps: Int
    package var volumePolicy: VolumePolicy
    /// F14/F15 as brightness keys (Carbon hotkeys, never the tap).
    package var alternateKeys: Bool
    /// Custom shortcuts by action id (any team's actions; §8.2).
    package var shortcuts: LossyMap<DisplayActionID, HotkeyCombo>
    /// Input slots 1–10.
    package var inputSlots: [InputSlot]
    /// nil = the OS default (see OSDStyle/OSDPosition.osDefault).
    package var osdStyle: OSDStyle?
    package var osdPosition: OSDPosition?
    package var osdTarget: OSDTarget
    package var osdShowValue: Bool
    package var osdShowNits: Bool
    /// Use the system OSD on macOS 14/15 when available.
    package var osdNative: Bool

    package static let stepRange: ClosedRange<Int> = 4...100
    package static let fineStepRange: ClosedRange<Int> = 8...400
    package static let maxSlots = 10
    package static let maxShortcuts = 128

    package init() {
        brightnessPolicy = .uncontrollableOnly
        brightnessAlsoSystem = false
        volumeAlsoSystem = false
        muteAlsoSystem = false
        target = .pointer
        steps = 16
        fineSteps = 64
        volumePolicy = .matchingOutput
        alternateKeys = true
        shortcuts = LossyMap()
        inputSlots = []
        osdStyle = nil
        osdPosition = nil
        osdTarget = .affected
        osdShowValue = true
        osdShowNits = false
        osdNative = false
    }

    private enum CodingKeys: String, CodingKey {
        case brightnessPolicy, brightnessAlsoSystem, volumeAlsoSystem, muteAlsoSystem, target, steps, fineSteps,
             volumePolicy, alternateKeys, shortcuts, inputSlots, osdStyle, osdPosition, osdTarget, osdShowValue,
             osdShowNits, osdNative
    }

    package init(from decoder: Decoder) throws {
        let d = KeysConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightnessPolicy = c.lossy(.brightnessPolicy, d.brightnessPolicy)
        brightnessAlsoSystem = c.lossy(.brightnessAlsoSystem, false)
        volumeAlsoSystem = c.lossy(.volumeAlsoSystem, false)
        muteAlsoSystem = c.lossy(.muteAlsoSystem, false)
        target = c.lossy(.target, d.target)
        steps = c.lossy(.steps, d.steps)
        fineSteps = c.lossy(.fineSteps, d.fineSteps)
        volumePolicy = c.lossy(.volumePolicy, d.volumePolicy)
        alternateKeys = c.lossy(.alternateKeys, true)
        shortcuts = c.lossy(.shortcuts, LossyMap())
        inputSlots = c.lossy(.inputSlots, [LossyElement<InputSlot>]()).compactMap(\.value)
        osdStyle = c.lossy(.osdStyle, nil as OSDStyle?)
        osdPosition = c.lossy(.osdPosition, nil as OSDPosition?)
        osdTarget = c.lossy(.osdTarget, d.osdTarget)
        osdShowValue = c.lossy(.osdShowValue, true)
        osdShowNits = c.lossy(.osdShowNits, false)
        osdNative = c.lossy(.osdNative, false)
    }

    package func sanitized() -> KeysConfig {
        var c = self
        c.steps = ConfigClamp.int(steps, Self.stepRange)
        c.fineSteps = ConfigClamp.int(max(fineSteps, c.steps), Self.fineStepRange)
        // Shortcuts: plausible key codes and modifiers only, bounded count.
        let valid = shortcuts.values.filter { _, combo in combo.keyCode <= 0xFF && combo.carbonModifiers & ~0x1F00 == 0 }
        let kept = valid.keys.sorted { $0.rawValue < $1.rawValue }.prefix(Self.maxShortcuts)
        var map: [DisplayActionID: HotkeyCombo] = [:]
        for id in kept where id.rawValue.utf8.count <= 128 { map[id] = valid[id] }
        c.shortcuts = LossyMap(map)
        c.inputSlots = Array(inputSlots.prefix(Self.maxSlots))
        return c
    }

    package func step(fine: Bool) -> Double { 1 / Double(fine ? fineSteps : steps) }

    package func effectiveOSDStyle(osMajor: Int) -> OSDStyle { osdStyle ?? .osDefault(majorVersion: osMajor) }
    package func effectiveOSDPosition(osMajor: Int) -> OSDPosition { osdPosition ?? .osDefault(majorVersion: osMajor) }
}

package struct PerDisplayKeys: ConfigModel {
    /// Keys act on this display.
    package var keysEnabled: Bool
    package var showVolumeOSD: Bool
    /// Audio output device name override for the volume policy (≤ 64 scalars).
    package var audioDeviceName: String?

    package init() {
        keysEnabled = true
        showVolumeOSD = true
        audioDeviceName = nil
    }

    private enum CodingKeys: String, CodingKey { case keysEnabled, showVolumeOSD, audioDeviceName }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keysEnabled = c.lossy(.keysEnabled, true)
        showVolumeOSD = c.lossy(.showVolumeOSD, true)
        audioDeviceName = c.lossy(.audioDeviceName, nil as String?)
    }

    package func sanitized() -> PerDisplayKeys {
        var c = self
        if let name = audioDeviceName {
            let clean = ConfigClamp.text(name)
            c.audioDeviceName = clean.isEmpty ? nil : clean
        }
        return c
    }
}
