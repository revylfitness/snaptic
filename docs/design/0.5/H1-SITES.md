# 0.5 H1: sites a fifth `ModuleID` touches

K1's audit (PLAN 0.5 H1, §R4). The pinned wide grep, re-run at base `73d2879`:

```
grep -rnE '\.(windowSwitcher|displays|awake|hiddenIcons)\b|ModuleID\b|NewModuleCard|SettingsRootID\.|EventCategory|KitBackup\.|KillSwitches|iconsStore|SnapticIconsV1' Sources Tests
```

At `73d2879` it finds **1574 hits in 215 files**, the same count as at `7dd972c`. Line numbers below are at the base.
On the K1 tree it finds 1652 hits in 218 files. The 78 extra hits are K1's own edits:

| File | Base | K1 tree |
|---|---:|---:|
| `Snaptic/Dock/DockPreviewsModule.swift` (new) | – | 3 |
| `SnapticKit/DockModel.swift` (new) | – | 1 |
| `SnapticKitTests/ConfigDockTests.swift` (new) | – | 55 |
| `SettingsUI/SettingsShell.swift` | 27 | 28 |
| `SnapticKit/SettingsShellRules.swift` | 15 | 17 |
| `ConfigModulesTests.swift` | 155 | 157 |
| `KitBackupTests.swift` | 128 | 139 |
| `KitModulesTests.swift` | 22 | 23 |
| `SettingsShellRulesTests.swift` | 7 | 9 |

Every base hit has one disposition:

| Disposition | Meaning |
|---|---|
| **K1** | changed in this item |
| **auto** | correct for `dockPreviews` with no edit |
| **n/a** | about one other module only, or not a `ModuleID` at all |
| **K5 / A6a / A7 / A8** | deferred to that plan item, which names it |

Exhaustive `switch`es fail the build, so the compiler found every one of those. Each is listed below as K1.

## Summary

| Disposition | Hits | Sources | Tests |
|---|---:|---:|---:|
| n/a | 800 | 751 | 49 |
| auto | 312 | 118 | 194 |
| K1 | 430 | 94 | 336 |
| K5 | 1 | 1 | – |
| A6a | 29 | 29 | – |
| A7 | 2 | 2 | – |
| **Total** | **1574** | **995** | **579** |

| Area | Hits | Dispositions |
|---|---:|---|
| `Snaptic/Awake` | 71 | n/a 71 |
| `Snaptic/Displays` | 213 | n/a 213 |
| `Snaptic/Switcher` | 10 | n/a 10 |
| `Snaptic/Icons` | 19 | n/a 18, auto 1 |
| `Snaptic/SettingsUI` | 36 | n/a 12, auto 11, K1 13 |
| `Snaptic/Core` | 195 | n/a 75, auto 56, K1 33, A6a 29, A7 2 |
| `SnapticKit/Controls` | 277 | n/a 275, K5 1, auto 1 |
| `SnapticKit` (other) | 174 | n/a 77, auto 49, K1 48 |
| `Tests` | 579 | K1 336, auto 194, n/a 49 |

## Kit (`Sources/SnapticKit`, not `Controls`)

| Site | Disposition | Note |
|---|---|---|
| `KitModules.swift:8` | K1 | The `KillSwitches` doc gains the `Dock.*` and `Windows.*` prefixes. |
| `KitModules.swift:20` `ModuleID` | K1 | `dockPreviews` last, so it starts last and stops first. |
| `KitModules.swift:102–106, 112–113` `MenuPresence.allowed`, `fallback` | K1 | `[.inSnapticMenu, .hidden]`; fallback `.inSnapticMenu`. |
| `KitModules.swift:136` `NewModuleCard`, `:216` `EventCategory` | K1 | `.dockPreviews` card; `.dock` category. |
| `KitModules.swift:252` `isExportedInDiagnostics` | auto | `.dock` is exported. |
| `KitControl.swift:474` CLI module names | auto | Built from `allCases`. The `dock` alias is in `ModuleHost`. |
| `SettingsIndex.swift:64` | auto | Roots come from `SettingsRootID.all`. |
| `MenuLayout.swift:97, 101–104` `shortTitle` | K1 | "Dock". |
| `MenuLayout.swift:326, 328` `ownIconIDs` | K1 | Guard `id != .dockPreviews`. The existing fuzz fails without it (1172 failures). |
| `MenuLayout.swift:89, 113–185` tabs | auto | K5 tests five tabs. |
| `MenuLayout.swift:275, 287, 290, 310` `statusItemPlan` | auto | Dock at `.inSnapticMenu` joins `shared` in start order. K5 decides the tab. |
| `MenuLayout.swift:315` `everythingHidden` | auto | Dock counts like any module. |
| `MenuLayout.swift:339, 346` | auto | |
| `MenuLayout.swift:91, 284, 292–309, 331, 361` | n/a | Awake and Hidden Icons only. |
| `SettingsShellRules.swift:10–13` roots, `:132–152` help anchors | K1 | Root after Hidden Icons; anchor "Dock Previews" (README heading lands at D1). |
| `SettingsShellRules.swift:75, 78, 181` | auto | |
| `SettingsPageRules.swift:9, 11–13, 20–21, 25–28` card → root, card shown | K1 | `.dockPreviews` cases. |
| `SettingsPageRules.swift:35, 38, 43–44` | auto | "Every module blocked" uses `allCases.count`. |
| `ConfigModules.swift:224–228` `defaultPreferences` | K1 | `(enabled: false, .inSnapticMenu)`. |
| `ConfigModules.swift:278` `setEnabled` clears the card | K1 | Clears `.dockPreviews` as for `.hiddenIcons`. |
| `ConfigModules.swift:424, 426, 429` `iconsNeedExternalDisplay` | K1 | Dock in the Snaptic Menu keeps the Snaptic icon; Don't Show adds nothing. |
| `ConfigModules.swift:484, 488` `insertingIconsCard` | K1 | The model for `insertingDockCard(upgrader:ledger:)` and `MigrationID.dockCard = "dockCard.v1"`. |
| `ConfigModules.swift:143, 150, 183, 258–269, 281–295, 365–410, 435–436` | auto | Sanitize, `enabledModules`, `setPresence`, menu rules. |
| `ConfigModules.swift:305` `resetMenu` | auto | Resets Dock to `.inSnapticMenu`; pinned (G2-7). |
| `ConfigModules.swift:186–189, 239–243, 273–275, 444–449, 468–472` | n/a | Awake migration; the 0.1 upgrade (Dock comes from defaults); the Displays and Hidden Icons cards. |
| `ConfigModules.swift:328–329` `onboardingSteps` | n/a | Dock adds no step. A8 adds only a permission row. |
| `KitBackup.swift:39` | n/a | A comment. |
| `IconsModel.swift:156`, `AwakeLogEvent.swift:4`, `AwakeTriggerEngine.swift:157, 159`, `MigrationNotices.swift:58`, `AwakeMigration.swift:42, 51`, `DisplaysUIModel.swift:811`, `AwakeSnapshot.swift:198`, `Config/ConfigManagement.swift:47, 57`, `Config/ConfigIcons.swift:3, 27, 29` | n/a | One other module only. |
| `ProtectionDiff.swift` (9), `AwakeFeatureGraph.swift` (3), `ConnectPlan.swift` (10), `LayoutPresetModel.swift` (14) | n/a | `config.displays` and similar members, not `ModuleID`. |

## Kit controls (`Sources/SnapticKit/Controls`, 277)

| Site | Disposition | Note |
|---|---|---|
| `MenuBarPageControls.swift:45` `iconsPresence` | K5 | Its Dock analog `dockPresence` lands with its K5 test. The row is A7. |
| `ControlRegistry.swift:43` `ControlGate.module(ModuleID)` | auto | |
| The other 275 hits | n/a | Each table gates and routes its own module's controls (`.module(.displays)`, `SettingsRootID.awake`, …). Dock's own tables arrive at K5. |

The n/a hits per file: AboutPageControls 6, ActionEditorSheetControls 2, ArrangeSheetControls 3,
AutomationsPageControls 12, AwakeAdvancedSheetControls 2, AwakeHistoryPageControls 2, AwakeMenuRowsControls 31,
AwakePageControls 2, BrightnessAdvancedSheetControls 2, BrightnessSubpageControls 2, ColorPageControls 8,
ConfirmChangesSectionControls 1, ConnectionSectionControls 5, ControlLegacy 5, CustomizeMenuSheetControls 1,
DDCMenuItemsControls 1, DisplayDetailsSheetControls 2, DisplayInformationPageControls 4,
DisplayLiveControlsControls 5, DisplayMenuBlockControls 1, DisplaysAdvancedSheetControls 1,
DisplaysMenuBuilderControls 26, DisplaysOnboardingStepControls 2, DisplaysPageControls 14, DrivesPageControls 9,
GeneralAdvancedSheetControls 4, GeneralPageControls 7, HardwareControlsPageControls 7, HookEditorSheetControls 2,
IconsAdvancedSheetControls 2, IconsItemsControls 1, IconsMenuRowsControls 1, IconsPageControls 2,
IconsSectionsPageControls 2, IndicatorControllerControls 3, KeyboardPageControls 8, MatchTextSizeSectionControls 2,
MenuBarOverlaysSectionControls 2, MenuBarPageControls 14, OnboardingControls 1, OverviewMenuItemsControls 3,
PIPEditorSheetControls 1, PIPPageControls 9, PermissionsPageControls 4, PresetEditorSheetControls 3,
ResolutionMenuItemsControls 1, ResolutionSectionsControls 13, SavedLayoutsPageControls 14,
SwitcherAdvancedSheetControls 1, SwitcherPageControls 1, SwitcherShortcutsSheetControls 2,
TriggerEditorSheetControls 3, VirtualDisplayEditorSheetControls 2, VirtualDisplaysPageControls 11.

## App (`Sources/Snaptic`)

| Site | Disposition | Note |
|---|---|---|
| `Core/ModuleContracts.swift:98` | K1 | The doc lists five modules. |
| `Core/ModuleHost.swift` `module(_:)` | K1 | `dock: DockPreviewsModule`, an inert shell: `.stopped`, `requiredPermissions` `[.accessibility]`. |
| `Core/ModuleHost.swift:420–425, 568–569` `module disable` names, help | K1 | `dock` alias; help reads `<…\|dockPreviews>`. |
| `Core/ModuleHost.swift:27, 43, 80, 403, 418, 429–433, 466, 474, 499, 727` | auto | Start, stop and status loops. |
| `Core/ModuleHost.swift:127` `Modules.disable.*` read | auto | `Modules.disable.dockPreviews` works with no edit. |
| `Core/ModuleHost.swift:696–698` `requestPermissions` | auto | Turning Dock on at K1 asks for Accessibility (§R4 candidate). |
| `Core/ModuleHost.swift:38, 149, 409, 736, 747` store, flush, reset | A6a | `SnapticDockV1` joins `init`, `shutdown` and `resetAllSettings`. |
| `Core/ModuleHost.swift:137, 166–172, 299, 307, 512, 604, 635, 718` | n/a | Other modules only (`:718` is the Hidden Icons reset note). |
| `Core/ModuleContext.swift:23, 27, 36, 38` | auto | A6a uses it as it is (H10). |
| `Core/Backup.swift:9, 12, 46–55, 137–152, 191` export, import, apply | A6a | The `dock` section. |
| `Core/Backup.swift:106, 128, 135` parse, preview, merge | auto | `KitBackup.merge` applies the new switcher union (D2-1) with no app edit. |
| `Core/Backup.swift:90, 93, 99` | n/a | `maxBytes`. |
| `Core/AboutPage.swift:141, 142, 153` `HostReport` | A6a | `dock:` line. |
| `Core/AboutPage.swift:18, 55, 140` | n/a | |
| `Core/StatusMenu.swift:484` sections | A7 | An enabled inert Dock may show an empty section until A7 (§R4 candidate). |
| `Core/StatusMenu.swift:27–59, 210, 382, 522, 557, 630–663, 678, 724–749` | auto | |
| `Core/StatusMenu.swift:92, 101, 117, 127, 155, 177, 183, 188–189, 238, 262, 547, 575–578, 667, 671` | n/a | Awake and Displays only. |
| `Core/MenuPlacement.swift:30` `help` | K1 | `(.hidden, .dockPreviews)` help. |
| `Core/MenuPlacement.swift:13, 42` | auto | Titles and `presences(for:)` come from `MenuPresence`. |
| `Core/MenuPlacement.swift:14, 32, 34, 35` | n/a | Hidden Icons, Displays, Awake. |
| `Core/MenuBarPage.swift:61` presence rows | K1 → A7 | Filtered out at K1. |
| `Core/MenuBarPage.swift:220–225, 229–233, 318–323` control ids, symbols | K1 → A7 | `nil` / `[]` for now. |
| `Core/MenuBarPage.swift:310` `showSnapticMenu` movable list | K1 | Skips Dock. |
| `Core/MenuBarPage.swift:145` `offHelp` | A7 | |
| `Core/MenuBarPage.swift:139, 247, 255, 340` | auto | |
| `Core/MenuBarPage.swift:28, 56, 107, 134, 152, 194, 298` | n/a | |
| `Core/GeneralPages.swift:251–272` card strings | K1 | "New: Dock Previews", body, "Turn On Dock Previews". |
| `Core/GeneralPages.swift:30, 44, 102, 117, 131, 221–222` | auto | `:102` is the fifth module row. |
| `Core/GeneralPages.swift:33, 92, 123` | n/a | `:123` is Hidden Icons' arrange sheet. Dock's Turn On uses the generic path. |
| `Core/Onboarding.swift:242` module list | auto | The fifth row. A8's M29 checks that the rows fit. |
| `Core/Onboarding.swift:180, 259, 267–268, 357, 404` | n/a | |
| `Core/SelfTestLaunch.swift:66` module count | auto | Counts five. |
| `Core/EventLog.swift:9, 22` | auto | `:33` is n/a (Awake). |
| `Core/PermissionsPage.swift:32, 105, 127–128` | n/a | Hidden Icons only. Dock's rows come from the generic `requiredPermissions` loops at `:111` and `:119`, which aren't grep hits. |
| `Core/CustomizeMenuSheet.swift` (12), `Core/AppDelegate.swift:94, 96, 97`, `Core/SelfTest.swift:230` | n/a | |
| `SettingsUI/SettingsShell.swift:59–66` sidebar style | K1 | `dock.rectangle`, `.green`. |
| `SettingsUI/SettingsShell.swift:84, 98, 103, 121, 180, 319, 435–436` | auto | |
| `SettingsUI/SettingsShell.swift:17, 78, 81, 92, 95, 111–114, 403, 442` | n/a | |
| `SettingsUI/ModuleSwitchRow.swift:23–28` summary | K1 | One-line summary. |
| `SettingsUI/ModuleSwitchRow.swift:8, 14`, `SettingsUI/StatusRow.swift:91` | auto | |
| `SettingsUI/PerDisplayPicker.swift:21` | n/a | |
| `Icons/IconsItems.swift:149` autosave names | auto | Every module but Hidden Icons. |
| `Icons/*` (18 more) | n/a | IconsModule 5, IconsPage 8, IconsMenuRows 2, IconsSectionsPage 1, IconsAdvancedSheet 1, PrivateMenuBarAPI 1. |
| `Switcher/*` (10) | n/a | SwitcherPages 8, WindowSwitcherModule 2. |
| `Awake/*` (71) | n/a | AwakeContext 2, AwakeModule 5, AwakeDiagnostics 2, AwakeFormat 1, HistoryController 2, LidClosedController 3, AudioMonitor 1, BluetoothPresence 1, DisplayPresence 1, OtherAssertionsReader 1, VolumeMonitor 1, AwakeAdvancedSheet 2, AwakeMenuRows 30, AwakePage 16, CriterionEditors 1, DrivesPage 1, IndicatorController 1. |
| `Displays/*` (213) | n/a | Each Displays page, controller and menu builder routes or gates itself (below). |

`Displays/*` per file: AutomationController 1, AppleBrightnessIO 1, BrightnessController 2, BrightnessService 2,
ColorController 4, ColorSyncService 1, GammaService 1, MenuBarOverlaysController 1, SyncController 3,
SystemColorsController 2, XDRController 4, DDCController 5, DDCService 1, DisplaysContext 1, DisplaysModule 6,
KeysController 10, OSDController 1, ArrangementController 6, ConnectPlanner 3, LayoutsController 8,
ManagementSupport 7, PanelPropsController 1, PowerController 6, ProtectionController 1, ResolutionController 5,
SmartHiDPIController 5, VirtualController 7, CaptureService 1, PIPController 5, ArrangeSheet 4, ArrangementCanvas 1,
AutomationsPage 1, BrightnessAdvancedSheet 1, BrightnessSections 1, BrightnessSubpage 2, ColorPage 3,
ConfirmChangesSection 2, ConnectionSection 2, DiagnosticsController 2, DisplayDetailsSheet 3,
DisplayInformationPage 3, DisplayLiveControls 2, DisplayPageSupport 3, DisplaysFeatureGroups 1,
DisplaysMenuBuilder 35, DisplaysOnboardingStep 3, DisplaysPage 9, HardwareControlsPage 4, HookEditorSheet 2,
KeyboardPage 4, KeyboardShortcutsSheet 2, ManagementMenuItems 1, MatchTextSizeSection 2, MenuBarOverlaysSection 1,
OverviewController 1, PIPMenuItems 1, PIPPage 4, ResolutionFiltersSection 1, ResolutionMenuItems 1,
ResolutionOptionsSection 1, ResolutionSections 3, SavedLayoutsPage 2, VirtualDisplayEditorSheet 2,
VirtualDisplaysPage 2.

## Tests (`Tests/SnapticKitTests`, 579)

| File | Hits | Disposition |
|---|---:|---|
| `ConfigModulesTests` | 155 | K1: `:13` fresh defaults (Dock off, `.inSnapticMenu`), `resetMenu` (G2-7), `:345` `iconsNeedExternalDisplay`, `:373` `defaultPreferences`. Dock versions of `:608`, `:621`, `:653` are `ConfigDockTests.testDockCard*`. |
| `KitBackupTests` | 128 | K1: the D2-1 union and safety tests; the switcher `"(all)"` pin is now true. |
| `ConfigIconsTests` | 24 | K1: `KitBackup.sections` gains `"dock"`. |
| `KitModulesTests` | 22 | K1: `allCases`, `allowed`, `fallback`, `SentenceText`. |
| `SettingsShellRulesTests` | 7 | K1: nine roots, groups `[2, 5, 2]`, `dock.` alias, bare `dock` is nil, `awaitingREADME`. |
| `MenuLayoutTests` 84, `MenuTabsTests` 31 | 115 | auto. K5 adds the Dock cases and five tabs. |
| `SettingsPageRulesTests` 32, `ConfigMenuTests` 16, `SettingsIndexTests` 14, `MigrationNoticesTests` 6, `ControlRegistryTests` 4 | 72 | auto |
| `IconsControlsTests` | 5 | auto. A8 updates `:196–197`, which aren't hits. |
| `Support/ConfigFixtures` | 2 | auto. `fullModules()` and `allCases` pass unchanged; `fullDock()` added. |
| `ConnectPlanTests` 16, `LayoutPresetModelTests` 7, `IconsPolicyTests` 3, `IconsLayoutTests` 3, `ConfirmChangesSectionControlsTests` 3, `AwakeTriggerEngineTests` 3, `KitControlTests` 2, `DisplaysUIModelTests` 2, `DisplaysMenuPlanTests` 2, `ConfigAwakeTests` 2, `AwakeMigrationTests` 2, `ProtectionDiffTests` 1, `FeatureGraphTests` 1, `AwakeSnapshotTests` 1, `AwakePresentationTests` 1 | 49 | n/a. `AwakePresentationTests` was edited only for the `SentenceText.unit` rename. |

New: `ConfigDockTests` (25) and `KnownDockToolsTests` (5).

## Sites the grep misses

| Site | Disposition | Note |
|---|---|---|
| `KitBackup` `sections`, `allowedPaths`, `unionPaths`, `safetyPaths`, `dockSectionData`, `importDock` | K1 | `dock` section; switcher `privateBundleIDs` union and `protectPrivateWindows` safety path (D2-1). |
| `SettingsShellRules` groups, `"dock"` alias, `dockPreviews` constant | K1 | |
| `KitModules` `SentenceText.properNames`, `unit` | K1 | "Dock Previews" and "Dock"; `unit` moved from `AwakeCountdown`. |
| `ConfigMigrations` `MigrationID.dockCard` | K1 | `runMigrations` wiring is A8. |
| `Controls/GeneralPageControls.swift:20` search keywords | K1 | Adds "dock previews" (H10). |
| `Controls/MenuBarPageControls` `dockPresence` | K5 | |
| `Core/SafeMode.swift` `skipped`, `stillRuns` | A6a | §4.13. |
| `Core/GeneralAdvancedSheet.swift`, `Windows.*` lock rows | A6a / A7 | D2-30. |
| `IconsControlsTests.swift:196–197` | A8 | Welcome text (P3-9). |
| `Core/Onboarding.swift:253` comment "four rows" | D1 / D3 | Left as is (H9). |
| `SettingsUI/SettingsShell.swift:69` comment "nine roots" | K1 | Updated with the roots; H9 lists it under D1 / D3. |

## Shared window services (D2-14)

`WindowServices` arrives at A1a (§2.3) and `ThumbnailIndex` at A2a. Today every client below is the Window
Switcher. Dock Previews has no call sites until A1a / A2a, and no test calls either.

**`ThumbnailStore`**

| Call site | Call |
|---|---|
| `Switcher/ThumbnailStore.swift:18–19` | definition and `shared` |
| `Switcher/WindowSwitcherModule.swift:6` | doc comment |
| `Switcher/WindowSwitcherModule.swift:92` | `purge()` in `stop()` |
| `Switcher/WindowSwitcherModule.swift:253` | `purge()` when thumbnails turn off |
| `Switcher/WindowSwitcherModule.swift:307` | `purge()` on `screensDidSleep` / `sessionDidResignActive` |
| `Switcher/WindowSwitcherModule.swift:316` | `purge()` on `com.apple.screenIsLocked` |
| `Switcher/SwitcherController.swift:255` | `prune(keeping:)` |
| `Switcher/SwitcherController.swift:432` | `invalidate()` |
| `Switcher/SwitcherController.swift:567` | `captureForPreview(_:blockedBundleIDs:maxPixels: 2400)` |
| `Switcher/SwitcherController.swift:579` | `cached(_:)` |
| `Switcher/SwitcherController.swift:581` | `refresh(_:blockedBundleIDs:maxPixels: 640, priority:)` |

**Sites that move into `WindowServices`** (A1a)

| Call site | Call |
|---|---|
| `Switcher/WindowSwitcherModule.swift:52` | AX messaging timeout (`WindowManager.axTimeout`) |
| `Switcher/WindowSwitcherModule.swift:65, 91` | `WindowManager.shared.start()`, `.stop()` |
| `Switcher/WindowSwitcherModule.swift:199` | `refreshFocusTracking()` |
| `Switcher/WindowSwitcherModule.swift:300–319` | `observePrivacyEvents`, which become the §2.5 purge observers |
| `Switcher/WindowManager.swift:181, 635` | `FocusTracker` |
| `Switcher/WindowManager.swift:601` | `ObserverThread` |
| `Switcher/WindowGatherer.swift:86, 89` | `WindowManager.axTimeout` (Gather Windows) |
| `Switcher/SwitcherController.swift:218` | `effectiveFrontPID` |
| `Switcher/SwitcherController.swift:232, 683` | `loadWindows` |
| `Switcher/SwitcherController.swift:397, 649` | `focus` |
| `Switcher/SwitcherController.swift:631, 640, 651, 661, 665` | `close`, `toggleMinimized`, `toggleFullscreen`, `quitApp`, `toggleHidden` |

**Privacy fields** `WindowServices` reads for both modules (§2.3, D2-1): `Core/ModuleHost.swift:40`
(`switcherSettings = AppSettings.shared`), `:412`, `:739`, `:749` (flush, reset); `Switcher/SwitcherController.swift:325,
327, 539`;
`Core/Backup.swift:46, 137, 187`; `Core/SelfTest.swift:75`.

## Onboarding permissions (D2-30)

`Core/Onboarding.swift:291–297`, unchanged since the base:

```swift
private var needed: [Permission] {
    var set = Set(store.value.onboardingPermissions)
    for module in [host.switcher as any SnapticModule, host.icons]
    where store.value.isEnabled(module.id) && !host.disabledByDefaults.contains(module.id) {
        set.formUnion(module.requiredPermissions)
    }
    return Permission.allCases.filter { set.contains($0) }
}
```

Line 293 loops over the switcher and Hidden Icons only. A8 makes it loop over every enabled module, so Dock lists
Accessibility, and Screen Recording while Window thumbnails is on (§4.14, §4.20). `ConfigDockTests.testRequiredPermissions`
pins `DockConfig.requiredPermissions` and is checked again at A8. The other permission sites
(`PermissionsPage.swift:111, 119`, `ModuleHost.swift` `requestPermissions`) already loop over every module.

## Downgrade (K1 exit, H7)

A one-off test decoded 0.5 fixtures with **0.4.0's types**. Nothing from it is committed.

- `git worktree add --detach /tmp/snaptic-k1-v040 v0.4.0` (`e9b150f`). `Package.swift`'s `#if os(macOS)` was set
  to `#if false` so the test target builds Kit only.
- `Tests/SnapticKitTests/K1Downgrade/K1DowngradeTests.swift`, with 0.4.0's switcher `Config` copied from
  `Settings.swift` l.1–340.
- Fixtures emitted by the 0.5 Kit:
  - `modules-card.json`: cards `[displays, awake, dockPreviews]`, Dock hidden;
  - `modules-on.json`: Dock enabled and hidden, Displays off;
  - `switcher.json`: `privateBundleIDs ["com.example.vault", "com.example.notes"]`, `protectPrivateWindows` false;
  - `backup.json`: `switcher`, `modules` and `dock` sections, `appVersion` 0.5.0.
- `swift test --filter K1DowngradeTests`: **4 tests, 0 failures.**

Results:

- The unknown card is skipped, so the cards read `[.displays, .awake]`. Onboarding reads `.done`.
- The other modules keep their settings. `dockPreviews` is kept and written back (`LossyMap`), hidden, and
  enabled in the on-fixture. A re-decode gives an equal value.
- The switcher `Config` keeps both privacy values after `sanitized()`.
- The backup: `parseDocument` drops `dock` and keeps `switcher` and `modules`. Merge, decode and sanitize over a
  current `["com.example.local"]` give the imported list and `protectPrivateWindows` false. 0.4.0 replaces the
  list rather than taking the union; 0.5's union (D2-1) applies only when 0.5 imports.

The worktree was removed and pruned, and the fixtures deleted. In-tree, `ConfigDockTests.testA05ModulesFileDecodesWithUnknownValues`
and `KitBackupTests.testA04BackupKeepsTheProtectedApps` pin the same paths.

## Notes

- **Rename.** `AwakeCountdown.unit` is now `SentenceText.unit` (P3-7), so Dock can use it. The rename touches 12 files.
- **`ownIconIDs` guard.** H1 put it with K5, but the MenuLayout fuzz fails at K1 without it.
- **`awaitingREADME`** in `SettingsShellRulesTests` lists "Dock Previews" until D1 adds the README heading.
- **`"(all)"`.** The switcher section now holds a safety path (`protectPrivateWindows`), so a whole switcher section
  replaced is safety-related. This flips the existing `KitBackupTests` pin from false to true.
- **`WindowGatherer`** logs the fixed string "Gathered windows" (no names or titles in logs).
