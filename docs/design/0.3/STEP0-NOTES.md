# 0.3 step 0: notes and deviations (lead)

Step 0 of `PLAN.md` (r5) is on `feature/v03-step0` (merged into `feature/v03`). Once stubs are on the branch the
code wins over the plan's prose (R5 rule carried forward). This file lists every place where the step-0 code
differs from, refines or adds to the plan text, so teams read the code and this file together.

## Contract refinements (the code is the contract)

| Area | Plan text | Code | Why |
|---|---|---|---|
| `ModulePreferences` (M2) | `presence` added; `placement` and `hideWithoutExternalDisplay` "stay declared and are written from it" | `presence` is the stored truth; `placement` and `hideWithoutExternalDisplay` are **computed** properties (get and set) derived from it, and both are still encoded. Setting `placement = .ownIcon` keeps "when active"; setting `hideWithoutExternalDisplay` toggles `.ownIcon` ↔ `.ownIconWhenActive` | 0.2 call sites (General › Menu, Onboarding, StatusMenu) keep reading and writing the 0.2 fields with no way for the two to diverge. Side effect: a hide flag is remembered only while the module is an own icon |
| M2, per module | "Awake's `.ownIcon` decodes as `.ownIconWhenActive` when `presence` is absent" | `ModulePreferences.init(from:)` maps placement + hide flag generically; `ModulesConfig.init(from:)` applies the Awake rule with a private probe that sees whether `presence` was stored | `ModulePreferences` doesn't know its module id |
| `ModulesConfig` additions | — | `presence(_:)`, `setPresence(_:for:)` (clamps to `MenuPresence.allowed(for:)`), `awakeUpgradePreferences`, `MenuPresence.init(legacy:hideWithoutExternalDisplay:)` | Shared by M2, the host and tests |
| `upgradeDefaults()` | Awake disabled | also `newModuleCards = [.displays]` (mirrors `showNewDisplaysCard = true`); `setEnabled(true, .displays)` removes `.displays` from `newModuleCards`; `resetMenu()` resets presence to the per-id default | Keeps the new and the legacy card field consistent |
| `MenuLayout.statusItemPlan(…)` (M's S stub) | "reproduces 0.2 placement" | 0.2's algorithm over Window Switcher and Displays only; Awake never gets a section, and is in `custom` for `.ownIcon` (or `.ownIconWhenActive` while active); `noModulesEnabled` is true when neither 0.2 module is on | Awake has nothing to show in step 0; 0.2 menus are unchanged |
| `DisplaysConfig.restoringDefaults(scope: .all)` | everything back to defaults | display identities (custom names, fingerprints) are kept | Remembered displays keep their keys and names |
| `DisplaysConfig.changedSections(old:new:)` | — | static func; non-empty whenever `old != new` (a per-display entry appearing or going away, or only unknown keys changing, marks every per-display section); `DisplaysConfigSection.perDisplaySections` helper | Fan-out in `DisplaysModule.configChanged` relies on it |
| `MigrationLedger` | `done: Set<String>`, ≤ 256 ids | encodes sorted; `sanitized()` keeps known ids first, then ≤ 256 printable ids of ≤ 64 bytes; `MigrationLedger.key` | Stable bytes for `ConfigStore`'s change detection |
| M1 hook (`ModuleHost`) | lead wires M1 in step 2 | step 0 calls G's stub and applies a non-`.nothing` result (rules replaced by id, module and `triggers` on, `.awakeMigrated` card); the `fromDisplays.v1` marker is recorded **only when something migrated**, so dev installs still run the real M1 after step 2. Step 2 records it always and adds the toast and hotkey move | The stub can't tell "nothing to migrate" from "not built" |
| `AwakeModule` start order | `SessionController.start` calls `restore(_:)` | `AwakeModule.start` calls `ctx.sessions.restore(snapshot)` right after the first apply (services active, controllers started) and before anything arbitrates; the "re-apply if the needs changed" step waits for G's `restore` | Same order; the module owns the sanitized snapshot |
| `AwakeModule.settingsPages()` | — | one 0.2-style page "Awake" rendering the stub `AwakePage` | Awake is present but stubbed in 0.2's Settings |
| `AwakeHost` | — | adds `lifetime` (the module's) | Services and controllers get child lifetimes from it |
| `ToastPresenter.show(_:actions:…)` | S stub that forwards and returns true | returns false when `lifetime` already ended; forwards `actions.first`; `remember`, `clickGuard`, `onDismiss` are ignored until step 2 | No step-0 caller uses them |
| `TriggerStepResult` | no init | `package init(hysteresis:suppressions:top:nextDeadline:)` | Kit structs need an explicit package init |
| `PowerMonitor.facts` | `@Published var facts: PowerFacts` | `@Published private(set) var facts: PowerFacts?` (nil until the first read); `PowerMonitor` is an `ObservableObject` | No meaningful default for a laptop vs a desktop |
| `SystemEventsMonitor` | multicast `observe` | conforms to `CriterionSource` with `kinds == []`; `SessionFacts` lives in its file | The plan gives it `observe` but no criterion kind |
| `AwakeLogEvent` | fixed `text` per case, counted vs ring | adds `isCounted` | The counted/ring split as data |
| SettingsUI `control:` (R5-13) | "last stored property or init parameter" | last init parameter on `SettingsPageHeader`, `NavigationRow`, `PageFooterButtons` (`advancedControl:`, `restoreControl:`); on `ButtonRow`, `ActionMenuItem` and `StatusAction` it comes **before** the trailing `action:` closure (each has an explicit init) | Trailing-closure call sites stay natural |
| MenuKit `control:` (R5-13) | on `header`, `status`, `device`, `settings`, `quit`, `alternate` | `header(_:control:)`, `status(_:symbol:control:)`, `device(_:symbol:dimmed:submenu:control:)`, `settings(_:control:_:)`, `quit(control:)`, `alternate(of:title:control:_:)` | Same |
| `Fingerprint.matches(_:_:)` (B) | S stub | added to B's existing `Fingerprint.swift` (the file stays kind L), returns false | B fills it in step 1 |
| Interim fix in C's `KeysController` | — | while registering `keys.shortcuts`, skips `f.showPanel`/`f.identify` when the combo equals `MenuConfig.showPanelShortcut`/`identifyShortcut` | Migration M4 copies those shortcuts into `keys.shortcuts` in step 0, while F's `OverviewController` still registers them from `MenuConfig`; without the skip the combo would be registered twice. F (step 1) removes OverviewController's own registration and C deletes the skip |

## Control registry

- **58 tables** (§4.8.2 plus the three R5-13 tables). Where §4.8.2 lists two files with one surface ("`BrightnessSubpage` + `BrightnessSections` (displays.brightness)", "`ResolutionSections` + `ResolutionOptionsSection`"), there is **one** table, named after the first file; the second file's stub already says `typealias Controls = BrightnessSubpageControls` / `ResolutionSectionsControls`. `CriterionEditors` uses `TriggerEditorSheetControls`, `OtherAssertionsSection` uses `AwakeAdvancedSheetControls`, `DisplaysFeatureGroups` uses `DisplaysAdvancedSheetControls`.
- Surfaces §4.8.2 doesn't name (owners may change theirs while their table is empty): `displays.matchTextSize`, `displays.arrange`, `displays.connection`, `displays.layouts`, `displays.virtual`, `displays.virtual.editor`, `menu.display.d` (Resolution, Virtual and Layouts menu items), `displays.pip`, `displays.pip.editor`, `menu.display.e`, `displays.automations`, `displays.automations.hook`, `displays.automations.action`. Shared surfaces are fine: ids are unique across all tables and only need the surface prefix.
- `ControlLegacy.ids` is the literal §4.8.1 list (588, generated from the plan table and checked by count). `ControlRemovals.removed` has 16 ids.
- `ControlLegacy.switcherKeyPaths` uses the walker's form for the shortcut list: `shortcuts.*.modifier` … (arrays are `*`, R5-13), not `shortcuts.modifier`. `internalKeys` starts with `shortcuts.*.id` and the ModulesConfig state keys (`onboarding`, `onboardingPermissions`, `showNewDisplaysCard`, `newModuleCards`); the lead extends it when the cross-check is turned on.
- `ConfigFixtures.keyPaths(_:)` lists every stored-property path **and every prefix**; a path is covered when it or an ancestor is declared (`ConfigFixtures.isCovered`). The fixtures set the top-level and per-display optionals; lists get one element each when the lead turns the key cross-check on at the step-3 exit.
- `ControlRegistryTests`: the per-table tests run now; totality and the key cross-check are `XCTSkip`ped until the step-3 exit.

## Lint and ratchet

- L1–L17 live in `scripts/lint03.py`, run by `scripts/lint.sh` (`--strict`, `--write-ratchet`). L3, L8 and L11 don't exist (dropped in the plan). L15–L17 have no ratchet.
- File sets the plan leaves open: L7's "Settings views" = `Displays/UI/`, `Awake/UI/`, `SettingsUI/`, `Switcher/{SettingsView,SwitcherPages}.swift`, `Core/{GeneralPages,Onboarding,SettingsWindowHost,MenuBarPage,CustomizeMenuSheet}.swift`; L13 = `Core/Menu*.swift`, `Core/StatusMenu.swift`, `Displays/UI/*Menu*.swift`, `Awake/UI/{AwakeMenuRows,IndicatorController}.swift`; L14 = `Awake/` and every `*Menu*.swift`; L9 is checked in Kit too (Kit declares `EventCategory.awake` as `Self(rawValue:)`, never by the banned token).
- The ratchet was generated with `--write-ratchet` on a checkout of 871c10b: L1 2 occurrences (PowerController), L5 143 (125 `.font(.caption)` + 18 `Slider(`/`Stepper(`; the plan's "≈ 54 + ≈ 125" overestimated the sliders), L6 18, L7 11 (4 + 7), plus the three permanent rows. No step-0 file adds a row.
- `gen-stubs.py` gained K15–K19 and K21. K18/K19's extra column is `Title` or `Title;Table` (the table's base name when the view shares another file's table). S rows without a generator entry are hand-written stubs and are skipped.

## Safe returns worth knowing

Fail-safe stub values chosen so nothing acts before its owner lands: `PowerFacts.discharging == true`, `PowerMath.falling == true`, `AwakeGuards.allowsBackgroundWork == false`, `TaskQuiet.isBusy == true`, `AwakeClock.isExpired == true`, `AwakeSession/AwakeHold.sanitized(now:) == nil`, `AwakeRuntimeSnapshot.sanitized(now:)` = empty snapshot, `SessionController` refuses every start, `AssertionManager.apply` refuses every active plan, `ProcessWatch.watch` refuses, `SystemEventsMonitor.sessionFacts()` = locked and off console, `SettingsShell.mayStart() == false`. The type-tagged enum decoders (`AwakeSessionKind`, `HoldBinding`, `AwakePresetKind`, the trigger conditions) throw, so stored elements are dropped rather than misread; the declared lossy list and field decoders (R5-3) are real.

## Left for teams that the plan didn't assign explicitly

- `StatusMenu.applyPlan` calling `StatusItemProvider.applyStatusItem(_:)` for `plan.custom`, and counting provider items in `hasVisibleItem` (M, with StatusMenu in step 1; AwakeModule already forwards to `IndicatorController`).
- `AwakeActionID` constants (`awake.toggle`, `awake.keepDisplayOn`, `awake.preset1…4`, `awake.pauseAutomatic`) (G; the host's step-2 M1 hotkey move uses `awake.pauseAutomatic`).
- The "Turned off by a defaults setting." page state for `Modules.disable.<id>` (H for the shell, G for Awake's header); `ModuleHost.disabledByDefaults` exposes it.
- `SettingsWindowHost` switching from `settingsPages()` to `settingsRoot()` (H, step 1).
