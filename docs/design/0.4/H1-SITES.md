# 0.4 H1: sites a fourth `ModuleID` touches

K1's audit (PLAN 0.4 H1). The search is every `ModuleID` use, every `allCases` over modules, every
`.windowSwitcher`/`.displays`/`.awake` and every `switch` over a module id in `Sources/` and `Tests/`, taken at
743b668 plus the K1 work. It found **1045** hits. Each hit has a disposition below:

| Disposition | Meaning |
|---|---|
| **K1** | changed in this item |
| **auto** | correct for `hiddenIcons` with no edit |
| **n/a** | about one module only, or not a `ModuleID` at all |
| **K5 / A5 / A7 / A8** | deferred to that plan item, which names it |

Exhaustive `switch`es fail the build, so the compiler found every one of those. They're listed with the item that
filled in each case.

## Summary

| Bucket | Hits | Disposition |
|---|---:|---|
| Comments | 11 | n/a. Prose that mentions a module. Doc comments that state the module count were updated (K1). |
| Member accesses that aren't `ModuleID` (`config.displays`, `facts.displays`, `AwakeCriterionKind.displays`, `DisplaysMenuSection.displays`) | 309 | n/a |
| String literals (control ids, menu specs, CLI words) | 162 | n/a |
| Control-table gates `.module(.displays)` / `.module(.awake)` in `Sources/SnapticKit/Controls/*` | ≈140 | n/a. They gate their own module's controls. Hidden Icons gets its own tables and gates at A5–A7. |
| Tests | ≈280 | K1 pinned the lists (below). The others pass unchanged with four modules. |
| Source sites that need a decision | ≈140 | per site, below |

## Kit (`Sources/SnapticKit`)

| Site | Disposition | Note |
|---|---|---|
| `KitModules.swift` `ModuleID` | K1 | `hiddenIcons` last, so it starts last and stops first. |
| `KitModules.swift:104–105` `MenuPresence.allowed` | K1 | `[.inSnapticMenu, .hidden]`. The arrow is the module's own icon. `fallback(for:)` added. |
| `KitModules.swift` `NewModuleCard`, `EventCategory` | K1 | `.hiddenIcons` card; `.icons` category. |
| `KitModules.swift` `properNames`, KillSwitches doc | K1 | "Hidden Icons"; `Icons.disable.*` prefix. |
| `KitControl.swift:466` CLI module names | auto | Built from `allCases`; the `icons` alias is in ModuleHost. |
| `SettingsPageRules.swift:11–12, 25–26, 38` card → root, card shown | K1 | `.hiddenIcons` cases. |
| `SettingsPageRules.swift:44` "every module blocked" | auto | Uses `allCases.count`. |
| `SettingsShellRules.swift` roots, groups, aliases, help anchors | K1 | Root after Awake; alias `icons`; anchor "Hidden Icons" (README heading lands at D1). |
| `MenuLayout.swift:101–103` `shortTitle` | K1 | "Icons". |
| `MenuLayout.swift:91` hidden-but-reachable | auto | Awake only. |
| `MenuLayout.swift:284–308` `statusItemPlan` shared list | K5 | `hiddenIcons` at `.inSnapticMenu` already joins `shared` in start order. K5 decides `custom`: the arrow is its own item, never in the plan's `custom`. Fuzz gains the fourth id. |
| `MenuLayout.swift:323–326` own-icon ids | K5 | `.ownIcon` isn't allowed for `hiddenIcons`, so it's excluded today. K5 adds an explicit guard and a test. |
| `MenuLayout.swift:349` Awake fallback | n/a | |
| `ConfigModules.swift:225–226` `defaultPreferences` | K1 | `(enabled: false, .inSnapticMenu)`. |
| `ConfigModules.swift` sanitize, `setPresence` | K1 | A presence the module doesn't allow falls back with `MenuPresence.fallback(for:)`. |
| `ConfigModules.swift:266` `enabledModules` | auto | |
| `ConfigModules.swift:272–274` `setEnabled` clears the card | K1 | Clears `.hiddenIcons` as for `.displays`. |
| `ConfigModules.swift:304` `resetMenu` | auto | Resets to `.inSnapticMenu`. |
| `ConfigModules.swift:324` `onboardingSteps` | A8 | The `.arrange` step is added there. |
| `ConfigModules.swift:405–416` `iconsNeedExternalDisplay` | K1 | False while Hidden Icons is on, because the arrow always shows. Test added. |
| `ConfigModules.swift:186, 238–242, 434, 453–457` Awake migration, 0.1 upgrade, Displays card | n/a | `upgradeDefaults` gets nothing new. The `iconsCard.v1` ledger marker is A8. |
| `MigrationNotices.swift:58`, `AwakeMigration.swift:51`, `AwakeFeatureGraph.swift:136, 174`, `ProtectionDiff.swift:117`, `LayoutPresetModel.swift:155` | n/a | Awake/Displays-only, or not `ModuleID`. |
| `KitBackup.swift` `sections` | K1 | `icons` section (H7). |

## App (`Sources/Snaptic`)

| Site | Disposition | Note |
|---|---|---|
| `Core/ModuleContracts.swift` | K1 | Doc lists four modules. `diagnosticsLines()` is a requirement with a default `[]`. |
| `Core/ModuleHost.swift:386–388` `module(_:)` | K1 | `icons: IconsModule` (inert K1 shell). |
| `Core/ModuleHost.swift:369, 382, 430, 661, 685` start/stop loops | auto | |
| `Core/ModuleHost.swift:455` `moduleDiagnostics` | K1 | Any running module's `diagnosticsLines()`, not only Awake's. |
| `Core/ModuleHost.swift:531–532` `module disable` names, help | K1 | `icons` alias. |
| `Core/ModuleHost.swift` `init` stores, `runMigrations`, `shutdown`, `resetAllSettings`, Safe Mode list | A5 | `SnapticIconsV1` and `SnapticIconsAppsV1` (H10). |
| `Core/ModuleHost.swift:130, 273, 475, 567, 598` | n/a | Awake/Displays-only. |
| `Displays/DisplaysContext.swift:106` `awakeDiagnosticsLines` | A5 | The report adds Hidden Icons' lines (H12). |
| `Core/SelfTestLaunch.swift:66` module count | auto | Counts four. H8's shim line lands at K4. |
| `Core/MenuBarPage.swift:60` presence rows | K1 → A7 | Filtered out in K1. A7 adds Hidden Icons' own row and strings. |
| `Core/MenuBarPage.swift:219–230, 318–320` control ids, symbols | K1 → A7 | `nil` / `[]` for now. |
| `Core/MenuBarPage.swift:307` `showSnapticMenu` movable list | A7 | Exclude `hiddenIcons` as Awake is: Arrow Only is a choice, not a lost menu. |
| `Core/MenuBarPage.swift:133, 149, 295` | n/a | |
| `Core/MenuPlacement.swift:24–25` per-module help | A7 | "Arrow and Snaptic Menu" / "Arrow Only" titles and help. Today `(.hidden, _)` gives the generic text. |
| `Core/GeneralPages.swift:102` module switches | auto | Fourth row from `allCases`. |
| `Core/GeneralPages.swift:243–262` card strings | K1 | "New: Hidden Icons", body, "Turn On Hidden Icons". |
| `Core/StatusMenu.swift:465` sections | auto | `hiddenIcons` gets a header like Displays. Its rows land at A7. |
| `Core/StatusMenu.swift:117, 177, 183, 556–557, 652` | n/a | Awake/Displays-only. |
| `Core/Onboarding.swift:241` module list | auto → A8 | Shows the fourth row. A8 checks `scrollDisabled(true)` at the largest text size. |
| `Core/Onboarding.swift:180, 266–273, 375` | A8 / n/a | The arrange step at A8. Others are Displays/Switcher-only. |
| `Core/AboutPage.swift:55, 140`, `Core/PermissionsPage.swift:104`, `Core/AppDelegate.swift:96`, `Core/CustomizeMenuSheet.swift:241` | n/a | `CustomizeMenuSheet:241` is `DisplaysMenuSection`. |
| `SettingsUI/SettingsShell.swift:84` root for the switcher | n/a | Other modules use `settingsRoot()`. |
| `SettingsUI/SettingsShell.swift` sidebar style | K1 | Symbol and tint for Hidden Icons. |
| `SettingsUI/ModuleSwitchRow.swift:25–27` summary | K1 | One-line summary. |
| `Switcher/*`, `Displays/*`, `Awake/*` pages (`isRunning`, `disabledByDefaults`, `DefaultsLockRow`, `let id`) | n/a | Each module's own page. |

## Tests

| Site | Disposition |
|---|---|
| `KitModulesTests` start order, allowed presences | K1 |
| `ConfigModulesTests` fresh defaults and first-run `enabledModules` (Hidden Icons off); `iconsNeedExternalDisplay` | K1 |
| `ConfigFixtures.fullModules()` (each id's first allowed presence); `fullIcons()` | K1 |
| `SettingsShellRulesTests` eight roots, alias resolve; `SettingsHelpAnchorsTests` awaiting README | K1 |
| `MenuLayoutTests`, `MenuTabsTests`, `ConfigMenuTests`, `SettingsPageRulesTests`, `MigrationNoticesTests`, `ControlRegistryTests`, `SettingsIndexTests`, `AwakeMigrationTests` | auto: pass with four modules. MenuLayout fuzz gains Hidden Icons' presences at K5. |
| New: `ConfigIconsTests`, `KnownMenuBarHidersTests` | K1 |

## Downgrade (K1 exit)

A 0.4 `SnapticModulesV1` read by the **0.3.4 types** was run in a `v0.3.4` worktree (a throwaway test, not committed).
The file had `hiddenIcons` enabled at `.hidden`, a `hiddenIcons` card and onboarding at a step 0.3.4 doesn't have.

- The unknown id is kept and written back (`LossyMap`).
- The card is skipped.
- The step reads as `.done`.
- The other modules keep their settings.
- The written file decodes to the same value.

`ConfigIconsTests.testA04ModulesFileDecodesWithUnknownValues` pins the same paths in-tree. A 0.4 backup's `icons`
section is ignored by 0.3.4 (`parseDocument` keeps only the sections it knows).

## Renamed from the plan

`IconsAppsState.newAllowed` is now **`newShown`**. KitBackup strips any key that contains "allow" at any depth.
This store is never exported, but `ConfigIconsTests.testFieldNamesAvoidTheSensitiveFragments` keeps every Hidden
Icons field name clear of the fragments. PLAN.md was updated to match.
