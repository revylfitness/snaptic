import Foundation

// Action and menu-item identifiers of the management features (owner: D). PLAN §8.2, R5.4.

extension DisplayActionID {
    package static let dResolutionUp = Self(rawValue: "d.resolutionUp")
    package static let dResolutionDown = Self(rawValue: "d.resolutionDown")
    package static let dHiDPIToggle = Self(rawValue: "d.hiDPIToggle")
    package static let dNativeMode = Self(rawValue: "d.nativeMode")
    package static let dDefaultMode = Self(rawValue: "d.defaultMode")
    package static let dNativeHalved = Self(rawValue: "d.nativeHalved")
    package static let dResolutionUndo = Self(rawValue: "d.resolutionUndo")
    package static let dResolutionRedo = Self(rawValue: "d.resolutionRedo")
    package static let dNotchToggle = Self(rawValue: "d.notchToggle")
    package static let dMatchUI = Self(rawValue: "d.matchUI")
    package static let dRotate = Self(rawValue: "d.rotate")
    package static let dHDRToggle = Self(rawValue: "d.hdrToggle")
    package static let dSetMain = Self(rawValue: "d.setMain")
    package static let dMirrorToggle = Self(rawValue: "d.mirrorToggle")
    package static let dToggleBuiltin = Self(rawValue: "d.toggleBuiltin")
    package static let dConnectAll = Self(rawValue: "d.connectAll")
    package static let dDisconnect = Self(rawValue: "d.disconnect")
    package static let dDisconnectAllButMain = Self(rawValue: "d.disconnectAllButMain")
    package static let dSleepPreventionToggle = Self(rawValue: "d.sleepPreventionToggle")
    package static let dProtectionToggle = Self(rawValue: "d.protectionToggle")
    package static let dSmartHiDPIToggle = Self(rawValue: "d.smartHiDPIToggle")

    /// Favorites 1–5.
    package static func dFavorite(_ n: Int) -> DisplayActionID { Self(rawValue: "d.favorite\(min(5, max(1, n)))") }
    /// Layouts 1–9 (menu order).
    package static func dLayout(_ n: Int) -> DisplayActionID { Self(rawValue: "d.layout\(min(9, max(1, n)))") }
    /// Virtual screen toggles 1–8 (list order).
    package static func dVirtualToggle(_ n: Int) -> DisplayActionID { Self(rawValue: "d.virtualToggle\(min(8, max(1, n)))") }

    package static var managementActions: [DisplayActionID] {
        [dResolutionUp, dResolutionDown, dHiDPIToggle, dNativeMode, dDefaultMode, dNativeHalved, dResolutionUndo,
         dResolutionRedo, dNotchToggle, dMatchUI, dRotate, dHDRToggle, dSetMain, dMirrorToggle, dToggleBuiltin, dConnectAll,
         dDisconnect, dDisconnectAllButMain, dSleepPreventionToggle, dProtectionToggle, dSmartHiDPIToggle]
            + (1...5).map(dFavorite) + (1...9).map(dLayout) + (1...8).map(dVirtualToggle)
    }
}

extension DisplayMenuItemID {
    package static let dResolutionSlider = Self(rawValue: "d.resolutionSlider")
    package static let dResolutionMenu = Self(rawValue: "d.resolutionMenu")
    package static let dMatchUI = Self(rawValue: "d.matchUI")
    package static let dSetMain = Self(rawValue: "d.setMain")
    package static let dMirrorMenu = Self(rawValue: "d.mirrorMenu")
    package static let dRotationMenu = Self(rawValue: "d.rotationMenu")
    package static let dHDRToggle = Self(rawValue: "d.hdrToggle")
    package static let dPowerSwitch = Self(rawValue: "d.powerSwitch")
    package static let dDisconnectItem = Self(rawValue: "d.disconnectItem")
    package static let dConnectAll = Self(rawValue: "d.connectAll")
    /// The right-click quick menu's own Connect All (visibility separate from Tools).
    package static let dConnectAllQuick = Self(rawValue: "d.connectAll.quick")
    package static let dDisconnectAllButMain = Self(rawValue: "d.disconnectAllButMain")
    /// Tools › "Arrange…" (opens the Arrangement page).
    package static let dArrange = Self(rawValue: "d.arrange")
    package static let dUnderscanMenu = Self(rawValue: "d.underscanMenu")
    package static let dSleepPrevention = Self(rawValue: "d.sleepPrevention")
    package static let dProtection = Self(rawValue: "d.protection")
    package static let dLayoutsMenu = Self(rawValue: "d.layoutsMenu")
    package static let dLayoutMatch = Self(rawValue: "d.layoutMatch")
    package static let dVirtualMenu = Self(rawValue: "d.virtualMenu")
    package static let dSmartHiDPI = Self(rawValue: "d.smartHiDPI")

    package static var managementItems: [DisplayMenuItemID] {
        [dResolutionSlider, dResolutionMenu, dMatchUI, dSetMain, dMirrorMenu, dRotationMenu, dHDRToggle, dPowerSwitch,
         dDisconnectItem, dConnectAll, dConnectAllQuick, dDisconnectAllButMain, dArrange, dUnderscanMenu, dSleepPrevention,
         dProtection, dLayoutsMenu, dLayoutMatch, dVirtualMenu, dSmartHiDPI]
    }
}
