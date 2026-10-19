import Foundation

// The control registry (lead; PLAN 0.3 §4.8, R5-13). Every settings page, sheet, page-section file and menu builder
// declares its controls in a static `<TypeName>Controls` table (Kit, so the Linux test sees it); this file lists the
// tables. An owner that adds a table appends one line to `tables` in its own merge (TEAMS.md exception).

/// A 0.3 control id ("awake.page.batteryFloor"). Views and builders write it only as `ControlID("…")` with one
/// string literal (lint L15).
package struct ControlID: RawRepresentable, Hashable, Codable, Sendable {
    package let rawValue: String
    package init(rawValue: String) { self.rawValue = rawValue }
    package init(_ rawValue: String) { self.rawValue = rawValue }
}

/// A frozen 0.2 control id ("l.gen.cli.enabled", §4.8.1).
package struct LegacyControlID: RawRepresentable, Hashable, Sendable {
    package let rawValue: String
    package init(rawValue: String) { self.rawValue = rawValue }
}

package enum HardwareCondition: String, Hashable, Sendable {
    case builtinDisplay, externalDisplay, twoDisplays, ddcDisplay, ddcVolume, xdrDisplay, appleDisplay, hdrDisplay,
         notch, battery
}

/// Closed allowlist of runtime states a control can depend on.
package enum ControlState: String, Hashable, Sendable {
    case safeMode, automationPaused, helperStopped, pendingConfirmation, screenRecordingMissing, accessibilityMissing,
         awakeActive, awakeIdle, rulesExist, rulesPaused, holdsExist, notAtDefault, commandLineOn, hiddenIconWarning,
         disconnectedDisplay, timedOrCapped
}

/// Availability as data (the §4.2 States rules); every condition must hold for the control to exist.
package enum ControlCondition: Hashable, Sendable {
    case displayFeature(DisplayFeature), awakeFeature(AwakeFeature), switcherFeature(SwitcherFeature), module(ModuleID)
    case hardware(HardwareCondition)
    /// Subordinate rows: shown only while the parent is on (the parent is in the same table).
    case parentOn(ControlID)
    /// One instance per list item: "display", "rule", "preset", "customAction", …
    case perItem(String)
    case state(ControlState)
}

package enum ControlKind: String, Hashable, Sendable {
    case setting, button, navigation, list, statusAction, shortcut, menuItem, menuSlider, menuSubmenu, menuSwitchHeader
}

/// The row in Customize Displays Menu.
package enum MenuCustomize: String, Hashable, Sendable { case threeWay, checkbox, none }

package struct MenuPlacementSpec: Hashable, Sendable {
    /// "display submenu", "Displays section", "Display Tools", "Awake menu", …
    package let location: String
    package let customize: MenuCustomize
    package let legacyMenuID: DisplayMenuItemID?

    package init(_ location: String, customize: MenuCustomize, legacy: DisplayMenuItemID? = nil) {
        self.location = location
        self.customize = customize
        legacyMenuID = legacy
    }
}

/// The search entry a `setting` spec derives (R5-13; `SettingsSearchEntry.init(_:search:)`).
package struct SearchSpec: Hashable, Sendable {
    package let title: String
    package let keywords: [String]
    package let root: String
    package let route: SettingsRoute?
    package let sheet: String?

    package init(_ title: String, keywords: [String] = [], root: String, route: SettingsRoute? = nil, sheet: String? = nil) {
        self.title = title
        self.keywords = keywords
        self.root = root
        self.route = route
        self.sheet = sheet
    }
}

package struct ControlSpec: Hashable, Sendable {
    package let id: ControlID
    package let kind: ControlKind
    /// [] = always present.
    package let when: [ControlCondition]
    /// The frozen 0.2 controls this one is the home of.
    package let replaces: [LegacyControlID]
    /// Config key paths it edits (key cross-check); may be empty.
    package let keys: [String]
    package let menu: MenuPlacementSpec?
    /// R5-13: the search entry is derived from the spec.
    package let search: SearchSpec?

    package init(_ id: String, _ kind: ControlKind, when: [ControlCondition] = [], replaces: [String] = [],
                 keys: [String] = [], menu: MenuPlacementSpec? = nil, search: SearchSpec? = nil) {
        self.id = ControlID(id)
        self.kind = kind
        self.when = when
        self.replaces = replaces.map { LegacyControlID(rawValue: $0) }
        self.keys = keys
        self.menu = menu
        self.search = search
    }
}

/// One table per settings page, sheet, page section file and menu builder (§4.8.2): `<TypeName>Controls` in
/// `SnapticKit/Controls/<TypeName>Controls.swift`, owned by the owner of the view or builder.
package protocol ControlTable {
    /// Every id starts with surface + ".", e.g. "awake.page".
    static var surface: String { get }
    static var controls: [ControlSpec] { get }
}

/// The one list of tables (§4.8.2). Adding a table = one appended line here (lint L15 checks every conformer is
/// listed).
package enum ControlRegistry {
    package static var tables: [any ControlTable.Type] {
        [
            GeneralPageControls.self,
            GeneralAdvancedSheetControls.self,
            PermissionsPageControls.self,
            AboutPageControls.self,
            OnboardingControls.self,
            SwitcherPageControls.self,
            SwitcherAdvancedSheetControls.self,
            SwitcherShortcutsSheetControls.self,
            MenuBarPageControls.self,
            CustomizeMenuSheetControls.self,
            StatusMenuControls.self,
            DisplaysMenuBuilderControls.self,
            DisplayMenuBlockControls.self,
            DisplaysPageControls.self,
            DisplayDetailsSheetControls.self,
            DisplaysAdvancedSheetControls.self,
            DisplayInformationPageControls.self,
            DisplayLiveControlsControls.self,
            DisplaysOnboardingStepControls.self,
            OverviewMenuItemsControls.self,
            BrightnessSubpageControls.self,
            BrightnessAdvancedSheetControls.self,
            ColorPageControls.self,
            HardwareControlsPageControls.self,
            KeyboardPageControls.self,
            BrightnessMenuItemsControls.self,
            DDCMenuItemsControls.self,
            ColorMenuItemsControls.self,
            ResolutionSectionsControls.self,
            MatchTextSizeSectionControls.self,
            ArrangeSheetControls.self,
            ConnectionSectionControls.self,
            SavedLayoutsPageControls.self,
            VirtualDisplaysPageControls.self,
            VirtualDisplayEditorSheetControls.self,
            ResolutionMenuItemsControls.self,
            VirtualMenuItemsControls.self,
            LayoutsMenuItemsControls.self,
            ManagementMenuItemsControls.self,
            PIPPageControls.self,
            PIPEditorSheetControls.self,
            PIPMenuItemsControls.self,
            AutomationsPageControls.self,
            HookEditorSheetControls.self,
            ActionEditorSheetControls.self,
            WindowSwitcherModuleControls.self,
            AutomationMenuItemsControls.self,
            ConfirmChangesSectionControls.self,
            PanicCoordinatorControls.self,
            AwakePageControls.self,
            AwakeAdvancedSheetControls.self,
            PresetEditorSheetControls.self,
            TriggerEditorSheetControls.self,
            CustomSessionPanelControls.self,
            AwakeHistoryPageControls.self,
            AwakeMenuRowsControls.self,
            IndicatorControllerControls.self,
            DrivesPageControls.self,
            MenuBarOverlaysSectionControls.self,
        ]
    }
}
