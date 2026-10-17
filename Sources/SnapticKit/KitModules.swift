import Foundation

// Shared identifiers. Lead-owned: these are the names every team uses, so they
// live in one place and change only through the lead (PLAN §13, R5.1).

/// Thrown by stubs that haven't been implemented yet (step 0b convention).
package enum StubError: Error, Equatable, Sendable { case notBuilt }

package enum ModuleID: String, Codable, CaseIterable, Sendable { case windowSwitcher, displays }

package enum Permission: String, Codable, CaseIterable, Sendable { case accessibility, screenRecording }

/// All user-visible strings go through L() so a String Catalog can be added later.
package func L(_ s: String) -> String { s }

package struct HotkeyCombo: Codable, Hashable, Sendable {
    package var keyCode: UInt32
    package var carbonModifiers: UInt32
    package init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }
}

/// Identifies a display action (shortcut, menu item, CLI verb target). Open: teams
/// declare constants in their own files, prefixed by area ("c.brightnessUp").
package struct DisplayActionID: RawRepresentable, Codable, Hashable, Sendable {
    package let rawValue: String
    package init(rawValue: String) { self.rawValue = rawValue }
}

/// Identifies a menu item for the Menu customization page. Open, like DisplayActionID;
/// contributors register descriptors at runtime (R5.1).
package struct DisplayMenuItemID: RawRepresentable, Codable, Hashable, Sendable {
    package let rawValue: String
    package init(rawValue: String) { self.rawValue = rawValue }
}

package enum MenuPlacementChoice: String, Codable, CaseIterable, Sendable { case shared, ownIcon, hidden }

package enum MenuItemVisibility: String, Codable, CaseIterable, Sendable { case visible, inSubmenu, hidden }

/// User-facing Displays features (PLAN §2.1, R5.4). Raw values are persisted.
package enum DisplayFeature: String, Codable, CaseIterable, Sendable {
    case overview, diagnostics
    case resolution, hiddenModes, scaleMatch
    case brightness, brightnessApple, brightnessDDC, brightnessGamma, brightnessOverlay
    case brightnessRestore, dimToBlack, dimOnLock, nits, xdr, sync, autoBrightness
    case color, colorProfiles, nightShift, applePresets
    case ddcControls, ddcInput, ddcPower, ddcCustom
    case brightnessKeys, volumeKeys, shortcuts, osd, osdBroadcast
    case mainDisplay, arrangement, mirroring, rotation, underscan, hdrToggle
    case disconnect, autoDisconnectBuiltin, protection, layouts
    case virtualScreens, smartHiDPI, hdrVirtual
    case pip, pipFilters
    case menuBarOverlays, sleepPrevention
    case hooks, customActions
}

/// One controller class per id (PLAN §2.1 "Ctl" column).
package enum DisplayControllerID: String, Codable, CaseIterable, Sendable {
    case overview, diagnostics, resolution
    case brightness, xdr, sync, color, systemColors
    case ddc, keys, osd
    case arrangement, panelProps, power, protection, layouts
    case virtual, smartHiDPI, pip, menuBarOverlays, automation
}

/// Internal Displays services, activated by reference count (PLAN §3.6).
package enum DisplayServiceID: String, Codable, CaseIterable, Sendable {
    case registry, sessionGate, guardProcess, transactions
    case appleBrightness, ddc, gamma, overlays, edr, brightness
    case osd, colorSync, monitorPanel, mediaKeys
    case virtualHosts, capture, spawner
}

package enum OverlayKind: String, Codable, CaseIterable, Sendable {
    case dim, edr, nudge, menuBarStrip, roundedCorners, identify
}

package enum OSDKind: String, Codable, CaseIterable, Sendable {
    case brightness, contrast, volume, mute, xdr, resolution, layout, nightShift, input
}

/// Window Switcher features (PLAN §2.2). Raw values are persisted.
package enum SwitcherFeature: String, Codable, CaseIterable, Sendable {
    case thumbnails, preview, otherSpaces, windowlessApps, search
    case actionClose, actionMinimize, actionFullscreen, actionHide, actionQuit
    case hoverButtons, hoverSelect, commandTabTakeover, passthrough
}

/// EventLog categories, declared once so two teams can't define the same name.
package struct EventCategory: RawRepresentable, Hashable, Sendable {
    package let rawValue: String
    package init(rawValue: String) { self.rawValue = rawValue }

    package static let switcher = Self(rawValue: "switcher")
    package static let modules = Self(rawValue: "modules")
    package static let permissions = Self(rawValue: "permissions")
    package static let registry = Self(rawValue: "registry")
    package static let transaction = Self(rawValue: "transaction")
    package static let guardProcess = Self(rawValue: "guard")
    package static let journal = Self(rawValue: "journal")
    package static let privateAPI = Self(rawValue: "privateAPI")
    package static let ddc = Self(rawValue: "ddc")
    package static let brightness = Self(rawValue: "brightness")
    package static let gamma = Self(rawValue: "gamma")
    package static let overlay = Self(rawValue: "overlay")
    package static let edr = Self(rawValue: "edr")
    package static let keys = Self(rawValue: "keys")
    package static let osd = Self(rawValue: "osd")
    package static let resolution = Self(rawValue: "resolution")
    package static let arrangement = Self(rawValue: "arrangement")
    package static let virtualDisplay = Self(rawValue: "virtual")
    package static let smartHiDPI = Self(rawValue: "smartHiDPI")
    package static let layouts = Self(rawValue: "layouts")
    package static let protection = Self(rawValue: "protection")
    package static let planner = Self(rawValue: "planner")
    package static let pip = Self(rawValue: "pip")
    package static let automation = Self(rawValue: "automation")
    package static let control = Self(rawValue: "control")
    package static let safety = Self(rawValue: "safety")
}

/// Stable, salted identity of a display: 32 lowercase hex characters.
/// Validation lives in init?(rawValue:) because LossyMap decodes keys through it.
package struct DisplayKey: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    package let rawValue: String

    package init?(rawValue: String) {
        guard rawValue.utf8.count == 32,
              rawValue.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }) else { return nil }
        self.rawValue = rawValue
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let key = DisplayKey(rawValue: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid display key")
        }
        self = key
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    package var description: String { rawValue }
}

/// A UUID usable as a LossyMap key (virtual screen and layout ids).
package struct StableID: RawRepresentable, Hashable, Sendable, Codable {
    package let rawValue: String
    package init?(rawValue: String) {
        guard UUID(uuidString: rawValue) != nil else { return nil }
        self.rawValue = rawValue.uppercased()
    }
    package init(_ uuid: UUID = UUID()) { rawValue = uuid.uuidString }
    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let id = StableID(rawValue: try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid id")
        }
        self = id
    }
    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
