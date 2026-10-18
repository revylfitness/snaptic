import Foundation

// Shared identifiers. Lead-owned: these are the names every team uses, so they
// live in one place and change only through the lead (PLAN §13, R5.1).

/// Thrown by stubs that haven't been implemented yet (step 0b convention).
package enum StubError: Error, Equatable, Sendable { case notBuilt }

/// Start order = declaration order (0.3: windowSwitcher, displays, awake; PLAN 0.3 §2.2).
package enum ModuleID: String, Codable, CaseIterable, Sendable { case windowSwitcher, displays, awake }

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

/// Where a module shows in the menu bar (0.3 §5.2, Control Center wording; replaces MenuPlacementChoice in the UI).
/// Cases are in menu order; raw values are persisted.
package enum MenuPresence: String, Codable, CaseIterable, Sendable {
    /// "Always Show in Menu Bar".
    case ownIcon
    /// "Show When Active": Displays while an external display is connected, Awake while a session runs.
    case ownIconWhenActive
    /// "Show in Snaptic Menu".
    case inSnapticMenu
    /// "Don't Show".
    case hidden

    /// The choices offered for a module: `ownIconWhenActive` only for Displays and Awake (sanitized → ownIcon elsewhere).
    package static func allowed(for id: ModuleID) -> [MenuPresence] {
        switch id {
        case .displays, .awake: return allCases
        case .windowSwitcher: return [.ownIcon, .inSnapticMenu, .hidden]
        }
    }

    /// What 0.2 reads (written for downgrades; migration M2). Displays' "when active" is the 0.2 ownIcon + hide flag.
    package var legacyPlacement: MenuPlacementChoice {
        switch self {
        case .ownIcon, .ownIconWhenActive: return .ownIcon
        case .inSnapticMenu: return .shared
        case .hidden: return .hidden
        }
    }

    /// The 0.2 → 0.3 mapping (M2) for one stored placement and its hide flag.
    package init(legacy placement: MenuPlacementChoice, hideWithoutExternalDisplay: Bool) {
        switch placement {
        case .shared: self = .inSnapticMenu
        case .hidden: self = .hidden
        case .ownIcon: self = hideWithoutExternalDisplay ? .ownIconWhenActive : .ownIcon
        }
    }
}

/// One-time General cards (0.3 §2.2): a closed enum, so "awake.migrated" survives migration M3's filter.
package enum NewModuleCard: String, Codable, CaseIterable, Sendable {
    case displays, awake, awakeMigrated = "awake.migrated"
}

/// Awake criterion kinds (0.3 §2.2); here so the Awake feature graph can reference them.
package enum AwakeCriterionKind: String, Codable, CaseIterable, Sendable {
    case app, display, power, schedule, cpu, audio, idle, volume, usb, network, networkActivity, bluetooth
}

/// Identifies an Awake action (hotkey, menu item). Open like DisplayActionID; raw values are "awake.*" and the
/// Awake team declares the constants.
package struct AwakeActionID: RawRepresentable, Codable, Hashable, Sendable {
    package let rawValue: String
    package init(rawValue: String) { self.rawValue = rawValue }
}

extension DisplayActionID {
    /// Show the floating Displays panel (migration M4 target; OverviewController registers it).
    package static let fShowPanel = DisplayActionID(rawValue: "f.showPanel")
    /// Identify displays (migration M4 target).
    package static let fIdentify = DisplayActionID(rawValue: "f.identify")
}

extension DisplayMenuItemID {
    /// "Turn Off Display" (DDC power) under a display's row (migration M10; C's DDCMenuItems uses it).
    package static let cDDCPower = DisplayMenuItemID(rawValue: "c.ddc.power")
}

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
    /// Awake: written only through EventLog's AwakeLogEvent overload (lint L9).
    package static let awake = Self(rawValue: "awake")

    /// Whether entries of this category may go into the exported diagnostics report (0.3 §3.6: never Awake).
    package var isExportedInDiagnostics: Bool { self != Self.awake }
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

/// 128-bit FNV-1a (0.3 §2.14, N18): offset basis 0x6c62272e07bb014262b821756295c58d, prime 2^88 + 0x13b, over the
/// given bytes. Not a secret or a MAC: Kit has no SHA (CryptoKit is app-only) and these ids aren't secrets.
package enum NameHash {
    package static let offsetBasis: (hi: UInt64, lo: UInt64) = (0x6c62_272e_07bb_0142, 0x62b8_2175_6295_c58d)

    package static func fnv1a128(_ bytes: [UInt8]) -> (hi: UInt64, lo: UInt64) {
        var hi = offsetBasis.hi
        var lo = offsetBasis.lo
        // prime = 2^88 + 0x13b: (hi·2^64 + lo)·prime mod 2^128
        //       = lo·0x13b + 2^64·(hi·0x13b + lo·2^24) mod 2^128.
        for byte in bytes {
            lo ^= UInt64(byte)
            let low = lo.multipliedFullWidth(by: 0x13b)
            let newHi = (hi &* 0x13b) &+ (lo &<< 24) &+ low.high
            lo = low.low
            hi = newHi
        }
        return (hi, lo)
    }
}

extension StableID {
    /// Name-based id (N18): fnv1a128(namespace ‖ 0x00 ‖ name) shaped as a UUID with RFC 9562 version 8 ("custom",
    /// the hash isn't SHA-1) and variant 10. Always a valid StableID; the same input gives the same id on every run
    /// and platform (migration M1 re-runs, default presets).
    package static func derived(namespace: String, name: String) -> StableID {
        let hash = NameHash.fnv1a128(Array(namespace.utf8) + [0] + Array(name.utf8))
        var bytes: [UInt8] = []
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: hash.hi >> UInt64(shift))) }
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: hash.lo >> UInt64(shift))) }
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map { byte -> String in
            let digits = Array("0123456789ABCDEF")
            return String([digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]])
        }
        let text = hex[0..<4].joined() + "-" + hex[4..<6].joined() + "-" + hex[6..<8].joined() + "-"
            + hex[8..<10].joined() + "-" + hex[10..<16].joined()
        // Always parses (36 hex/dash characters); the fallback only keeps this total.
        return StableID(rawValue: text) ?? StableID(UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                                                                 bytes[6], bytes[7], bytes[8], bytes[9], bytes[10],
                                                                 bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])))
    }
}
