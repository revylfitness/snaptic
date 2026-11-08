# 0.4 plan review r1: engineering pressure test

Reviewer: pressure-test (R1). Input: `docs/design/0.4/PLAN-draft.md` (draft r1), the Snaptic tree at `acbd102`
(plus the uncommitted icon files, untouched), and Hidden Bar at `/tmp/hidden-src/repo` `47937b9`.
I didn't reopen any of the owner decisions (Q1 to Q6). Every claim below was checked against the code. I ran one
read-only probe on this Mac (27.2): it resolved the MenuBarClientCore classes and selectors and read their type
encodings, and activated nothing.

Hidden Bar paths quoted in this review (the plan and the task prompt name some of them wrongly):
`hidden/Features/StatusBar/{StatusBarController,ExpandCollapseAction}.swift`,
`hidden/Features/StatusBar/Engine/{MenuBarEngine,MenuBarEngineFactory,LegacyLengthEngine,NativeVisibilityEngine}.swift`,
`hidden/Features/StatusBar/Engine/Native/{HBNativeVisibilityShim.h,.m,NativeVisibilityBridge.swift}`,
`hidden/Features/StatusBar/Layout/{MenuBarLayout,AccessibilityMenuBarInventory}.swift`, and the tests in
`HiddenBarTests/{MenuBarEngineTests,ExpandCollapseActionTests,AutoStartTests}.swift`. `hiddenTests/` holds only
the Notch Overflow tests.

Summary: 2 Blockers, 10 Majors, 12 Minors.

---

## Blockers

### P-1 · Blocker · §4.1 "Always Hidden", §4.3, K2: the Always Hidden design doesn't hide anything on the Length engine

**Finding.** The plan says: "Always Hidden. Collapsed, the separator length is 0. Expanded with ⌥, it is 20 … This
works on both engines and fixes Hidden Bar's 'only reliable with separators hidden' problem." The Length engine
hides items only by inflating an item. A `⋮` at length 0 (or 20) pushes nothing off-screen. With a plain expand
(main separator back at 20), every icon left of `|` reappears, and that includes the Always Hidden icons. Hidden
Bar keeps the always-hidden section hidden on Length only by inflating `⋮` to the full collapse length while
"separators hidden" is on. That inflation is exactly what made it "only reliable with separators hidden". The
Native behaviour the plan describes (exclude the always-hidden bundles from the allow-list) is right, but it
doesn't carry over to Length. The plan's "fix" for that known issue therefore doesn't exist on 14–26.

**Evidence.**
- `LegacyLengthEngine.swift:58-66`: `updateAlwaysHiddenSection` sets `⋮` to `collapsedLength` when `separatorHidden`,
  and to `expandedLength`/0 otherwise.
- `LegacyLengthEngine.swift:46-55`: only `separatorItem.length` changes on collapse and expand.
- `StatusBarController.swift:200-225`: ⌥-click flips `areSeparatorsHidden`, which drives that length.
- `NativeVisibilityEngine.swift:150-166`: on Native, expanded with always-hidden uses an allow-list of visible plus
  hidden.

**Proposed fix (plan text, §4.1).** Replace the Always Hidden bullet with:
> **Always Hidden.** The `⋮` length depends on the engine and the state.
>
> | State | Length engine `⋮` | Native engine `⋮` | Native allow-list |
> |---|---|---|---|
> | Collapsed | `collapsedLength` (both separators inflated) | 0 | visible |
> | Expanded (plain) | `collapsedLength`, which keeps the always-hidden icons off-screen | 20 if "Show section dividers", else 0 | visible + hidden |
> | Expanded with ⌥ ("show all") | 20 if "Show section dividers", else 0 | 20 / 0 | assertion released |
>
> On Length, the always-hidden icons stay hidden while the hidden section is shown, because `⋮` is the item that
> inflates. With two inflated items each length is capped separately (≤ 10 000). Kit test: K2 gets one table-driven
> case per row for each engine. M-check: on 14–26, a plain expand never shows an Always Hidden icon.

Also: §4.3's "Show section dividers" can't make `⋮` zero-width while expanded on Length (P-1 table). Say that
divider visibility applies to `|` only while `⋮` is inflated.

### P-2 · Blocker · H2, §2 (`IconsItems`), K4, A5: the status-item plan can't express Hidden Icons as written

**Finding.**
1. **Own-icon path.** H2 sets `MenuPresence.allowed(for: .hiddenIcons) == [.ownIcon]`. `ownIconIDs` returns every
   enabled, running module whose presence is `.ownIcon`, except `.awake`. StatusMenu then builds a fourth own-icon
   `NSStatusItem` with autosave `Snaptic.hiddenIcons` and a menu, in addition to the module's three items.
2. **Tab presence.** A Snaptic-menu tab exists only for modules in `plan.shared`, and `shared` requires presence
   `.inSnapticMenu`. So "presence is `.ownIcon` and the tab is opt-in (default on)" contradicts the model. There's no
   field to store "tab on", and `statusItemPlan` is a `ModulesConfig` method that can't see an icons config slice.
3. **Arrow-only state.** Suppose Hidden Icons is the only module on and its tab is off (or every other module is
   hidden). Then `showShared` is false and `own` and `custom` are empty, so `sharedFooterInOwnMenus` is false and
   no Snaptic item exists. The arrow's ⌃-click menu is the only route left, and §4.2 itself says not to rely on it
   on 27.
4. **Runtime checks.** `StatusMenu.hasVisibleItem` and `applyProviderRows` only know about Snaptic's own slots and
   `StatusItemProvider`s. If the arrow went through `StatusItemProvider`, it would count as a visible Snaptic item
   and get a `CustomItemRow`/footer. Awake-only branches (`header: id != .awake`, the `custom == [.awake]` fuzz
   invariant) also need decisions.

**Evidence.**
- `Sources/SnapticKit/MenuLayout.swift:284`: `shared = live.filter { $0 != .awake && presence($0) == .inSnapticMenu }`.
- `MenuLayout.swift:320-329`: `ownIconIDs` excludes only `.awake`.
- `MenuLayout.swift:313`: `sharedFooterInOwnMenus: !showShared && !(own.isEmpty && custom.isEmpty)`.
- `MenuLayout.swift:122-124`: tabs need `plan.shared.count >= 2`.
- `Sources/Snaptic/Core/StatusMenu.swift:27,195-205,229-264,267-286,465`.
- `Tests/SnapticKitTests/MenuLayoutTests.swift:418-433` (fuzz invariants, including `:420 p.custom.allSatisfy { $0 == .awake }`).

**Proposed fix (plan text, H2).** Replace H2 with:
> **H2. Menu presence.** The three icons items are owned by `IconsItems`, never by StatusMenu. Hidden Icons'
> `MenuPresence` describes **only its Snaptic-menu tab**: `allowed(for: .hiddenIcons) == [.inSnapticMenu, .hidden]`,
> and `defaultPreferences(.hiddenIcons) == ModulePreferences(enabled: false, presence: .inSnapticMenu)`. Then:
> - `ownIconIDs` excludes `.hiddenIcons`, as it does `.awake`, and `statusItemPlan` never puts it in `ownIcon` or
>   `custom`.
> - "Show Hidden Icons in the Snaptic menu" is that presence. No new field is needed, and backups and the key
>   cross-check already cover it.
> - A new plan rule: when Hidden Icons is the only live module that isn't `.hidden` (or the only live module) and
>   `shared` would be empty, the plan still shows the Snaptic item with the footer (Settings…, Quit). The arrow never
>   carries the footer.
> - `everythingHidden` ignores Hidden Icons, because the arrow is always visible while the module is on. The Menu Bar
>   page warning keeps its meaning.
> - The Menu Bar page shows the fixed row about the arrow plus the normal Show-in-menu pop-up limited to the two
>   allowed values.
> - Fuzz (`MenuLayoutTests` 390–467): add the invariants `!p.ownIcon.contains(.hiddenIcons)`,
>   `!p.custom.contains(.hiddenIcons)`, and "hiddenIcons live ⇒ showShared ∨ some other own or custom item".
> - `IconsItems` is not a `StatusItemProvider`, so `hasVisibleItem` doesn't count the arrow.

---

## Majors

### P-3 · Major · §2 (last paragraph), K1, K2, K3: the Hidden Bar test-port claims are wrong, and the Kit core can't hold the objects those tests use

**Finding.**
1. **Wrong home and count.** The tests live in `HiddenBarTests/`, not `hiddenTests/`. `MenuBarEngineTests.swift`
   has 6 resolver tests, 10 Native engine tests and 1 Length test. The plan says "all 8 of Hidden Bar's engine
   cases".
2. **Doesn't port line for line.** The fakes build real `NSStatusBar()`/`NSStatusItem` objects and `CGRect`s, and
   they assert on `items.separatorItem.isVisible` and `.length`. None of that can exist in Kit: lint rule 3 bans
   AppKit and CoreGraphics, and Linux has no `NSStatusItem`.
3. **Live state and behaviour.** Hidden Bar's Length engine *derives* its state from the live separator length
   (`length > 20`), and that's what makes it survive a length recompute while collapsed. The engine also exposes
   `isArrangementValid`, `isAlwaysHiddenSeparatorPlaced` and a `.calibrating` state, and a collapse during
   `.calibrating` returns **without calling its completion**. The plan names none of this.
4. **Click tests.** `ExpandCollapseActionTests` (6 cases: nil event, left, right, ⌥-left, ⌥-right, other mouse)
   is the obvious K3 seed, and the plan doesn't mention it.

**Evidence.**
- `HiddenBarTests/MenuBarEngineTests.swift:17-28` (FakeItems on `NSStatusBar()`), `:102-148` (resolver),
  `:178-320` (Native), `:322-337` (Length).
- `LegacyLengthEngine.swift:34-37`, `MenuBarEngine.swift:18-40`, `NativeVisibilityEngine.swift:78-85`.
- `HiddenBarTests/ExpandCollapseActionTests.swift:15-35`.
- `scripts/lint.sh:41`.

**Proposed fix (plan text, §2 and K1–K3).**
> The Kit engine core never sees an item. It talks to an `IconsItemsPort` (`frame(of: IconsItemRole) -> IconsRect?`,
> `setLength(_:for:)`, `setVisible(_:for:)`, `length(of:)`) and records commands, so the tests assert on the recorded
> lengths and visibility.
> - `IconsRect` is a new Kit struct (`x, y, width, height: Double`, `midX`), following `ArrangeRect`/`ScreenRect`.
> - Length engine state is derived from `itemsPort.length(of: .separator) > expandedLength`, as in Hidden Bar.
> - The core exposes `isArrangementValid` and `isAlwaysHiddenSeparatorPlaced` (P-9).
> - A collapse while `.calibrating` joins the in-flight request: its completion is queued and answered by the same
>   result. Hidden Bar's drop-on-the-floor isn't copied (it hangs the CLI, P-9).
> - K1 ports Hidden Bar's 6 resolver tests. K2 ports the 10 Native tests and 1 Length test, plus the P-1 table, an
>   activation timeout, kill switch mid-collapse, and stop() always expands. K3 ports the 6 `ExpandCollapseAction`
>   cases. Source paths: `HiddenBarTests/MenuBarEngineTests.swift`, `HiddenBarTests/ExpandCollapseActionTests.swift`.

### P-4 · Major · §2 (`Icons/IconsControls.swift`), K5, A5, A6: the control-table layout breaks lint L15 and the registry model

**Finding.** The plan puts one Kit file, `Icons/IconsControls.swift`, holding "the *Controls table, settings index,
CLI grammar". House rules (L15):
- Every `ControlTable` lives in `Sources/SnapticKit/Controls/<ViewOrBuilderName>Controls.swift`.
- Each one is listed once in `ControlRegistry.tables`.
- Each app file that uses `ControlID` literals declares exactly one `typealias Controls = X`.
- Every declared id must be used by some app file.

Four UI files (`IconsPage`, `IconsAdvancedSheet`, `IconsMenuRows`, `HiddenListMenu`) therefore need four tables,
not one. There's no separate "settings index" either: search comes from `ControlSpec.search` (`SearchSpec`). New
config keys must appear in some spec's `keys`, or `testKeyCrossCheck` fails, and that also needs a
`ConfigFixtures.fullIcons()`. Conditions like "Native only" or "needs Accessibility" need a `ControlCondition`
(e.g. `iconsFeature(IconsFeature)`) or new `ControlState` cases, because both enums are closed. CLI grammar belongs
in its own Kit file, as `AwakeCommandGrammar.swift` does.

**Evidence.**
- `scripts/lint03.py:1350-1398` (L15).
- `Sources/SnapticKit/Controls/ControlRegistry.swift:27-45` (closed `ControlState`/`ControlCondition`), `:119-122`
  (tables list).
- `Tests/SnapticKitTests/ControlRegistryTests.swift:207-215` (key cross-check fixtures).
- `Tests/SnapticKitTests/Support/ConfigFixtures.swift:96`.
- Precedent: `Controls/AwakePageControls.swift`, `AwakeAdvancedSheetControls.swift`, `AwakeMenuRowsControls.swift`,
  `IndicatorControllerControls.swift`, `WindowSwitcherModuleControls.swift`.

**Proposed fix (plan text, §2 and K5).**
> SnapticKit/Controls:
> - `IconsPageControls.swift` (surface `hiddenIcons`)
> - `IconsAdvancedSheetControls.swift` (`hiddenIcons.advanced`)
> - `IconsMenuRowsControls.swift` (`menu.hiddenIcons`)
> - `HiddenListMenuControls.swift` (`menu.hiddenIcons.list`)
> - `IconsItemsControls.swift` (the arrow/separator button identifiers)
>
> Each is appended to `ControlRegistry.tables`, and each app view declares `typealias Controls = …`. Search entries
> are `SearchSpec`s on those specs. `ControlCondition` gains `iconsFeature(IconsFeature)`. `ControlState` gains
> `iconsNative` and `iconsCollapsed` only if a spec needs them. `ConfigFixtures.fullIcons()` joins
> `testKeyCrossCheck`. The CLI grammar goes in `SnapticKit/IconsCommandGrammar.swift`.
>
> K5 done-when: Linux tests green **and** `lint.sh --strict` clean (L15).

### P-5 · Major · §3 (missing H-item), K4, A4: the config store and its host wiring are missing from the H list

**Finding.** The plan never says where IconsConfig is persisted. Every module slice in Snaptic has its own
`ConfigStore` key and is wired by hand in about ten places. None of them is in H1–H9.

**Evidence.**
- `Sources/Snaptic/Core/ModuleHost.swift`:
  - 14–20: store keys
  - 142–144: module and store construction
  - 152–189: `runMigrations` forced saves
  - 356–377: `shutdown` flushes each store
  - 672–700: `resetAllSettings` resets each store by name
- `Sources/SnapticKit/Config/ConfigModules.swift`:
  - ~246: `defaultPreferences` switch; today every module is on for a fresh install
  - `upgradeDefaults`/`insertingAwakeForUpgrader`: the "insert off + New card" migration with a ledger marker
  - `setEnabled` clears only the `.displays` card
- `Sources/SnapticKit/Config/ConfigMigrations.swift:9-19`: `MigrationLedger` markers.
- `Sources/SnapticKit/KitBackup.swift`:
  - 33–39: `sections`
  - `allowedPaths`, `sectionSensitiveKeys`, `removedPaths`, `safetyPaths`
  - 238–264: `awakeSectionData`/`importAwake`
- `Sources/Snaptic/Core/Backup.swift:43-52`: export and import list sections by name.
- Tests that pin today's defaults: `ConfigModulesTests.swift:15` (`enabledModules == ModuleID.allCases`), `:283`,
  `:500`.

**Proposed fix (plan text, new H10).**
> **H10. Store.** `IconsConfig` is stored under its own key `SnapticIconsV1` (`ConfigStore<IconsConfig>`), with the
> Kit file `Config/ConfigIcons.swift`. It's wired into:
> - `ModuleHost.init`
> - `runMigrations` (forced save)
> - `shutdown` (flush)
> - `resetAllSettings`, which also removes `NSStatusItem Preferred Position Snaptic.icons.*` and
>   `NSStatusItem Visible Snaptic.icons.*`
> - Safe Mode's store list
>
> `ModulesConfig.defaultPreferences(.hiddenIcons)` is off (P-2). An absent entry already reads as the default, so no
> "insert off" write is needed. A new ledger marker `iconsCard.v1` adds `NewModuleCard.hiddenIcons` once for upgraders
> and fresh installs alike. `setEnabled(.hiddenIcons, true)` clears the card.
>
> Backup: a new `icons` section in `KitBackup.sections`, with `allowedPaths` (an allowlist, as for Awake),
> `sectionSensitiveKeys` (the new-icon allow-list and per-app overrides, which hold bundle ids, are excluded),
> `importIcons` sanitizing, and `Backup.swift` export and import.
>
> Tests to update in K4: `KitModulesTests:40`, `ConfigModulesTests:15/283/500`, `SettingsShellRulesTests:12`,
> `ConfigFixtures:96`, `MenuLayoutTests` fuzz.

### P-6 · Major · H1: the site count is wrong, there is no "lint exhaustiveness rule", and several closed lists aren't switches

**Finding.** H1 says "All 84 switch sites … (31 files) … lint's exhaustiveness rule catches any that are missed".
- **Measured counts.** `.windowSwitcher` has 96 hits in 21 files, and `case .windowSwitcher` has 8 hits in 6 files.
- **No such rule.** There is no exhaustiveness rule in `lint.sh` or `lint03.py`. Only the compiler checks
  `switch`, and only for switches without `default:`.
- **Comparisons the compiler can't see.** These sites decide per-module behaviour through `==`/`!=` and get no
  compiler help: 19 comparisons in 9 files (`ConfigModules.swift` ×5, `MenuLayout.swift` ×4, `GeneralPages.swift` ×2,
  `MenuBarPage.swift` ×2, `ModuleHost.swift` ×2, `StatusMenu.swift`, `SettingsShell.swift`, `SettingsPageRules.swift`,
  `AwakePage.swift`).
- **Hard-coded lists.** Several lists don't use `ModuleID` at all:
  - `SettingsRootID.groups` (the sidebar)
  - the `module disable <windowSwitcher|displays|awake>` help string and name alias
  - `SelfTestLaunch`'s module-count check
  - `MenuLayout.shortTitle`
  - `SentenceText.properNames`
  - `EventCategory`
  - `KillSwitches` doc
  - `moduleDiagnostics` (Awake-only)

**Evidence.**
- `Sources/SnapticKit/SettingsShellRules.swift:7-18` (the `groups` literal) and `SettingsShellRulesTests.swift:8-13`.
- `ModuleHost.swift:451` (`moduleDiagnostics`), `:524` (help string), `:528` (alias).
- `SelfTestLaunch.swift:66`.
- `MenuLayout.swift:99-105`.
- `KitModules.swift:20` and `:30-33`.
- `ModuleID.allCases` users: `KitControl.swift:466`, `MenuLayout.swift:307`, `SettingsPageRules.swift:42`,
  `ConfigModules.swift:265/301`, `ModuleHost.swift:367/380/427/528/657/681`, `GeneralPages.swift:102`,
  `Onboarding.swift:241`, `MenuBarPage.swift:59`.

**Proposed fix (plan text, H1).**
> **H1.** `ModuleID` gains `.hiddenIcons`. Before the change, the implementer runs
> `grep -rnE '\.(windowSwitcher|displays|awake)\b|ModuleID\.allCases' Sources Tests` and lists each hit in
> `docs/design/0.4/H1-SITES.md` with a disposition. The compiler covers switches without `default:`. Every
> `==`/`!=` site and every `default:` switch is checked by hand. The explicit list:
> - `SettingsRootID.groups`: add the `hiddenIcons` root and the alias `icons`, so `open-settings icons` works
> - the `module disable` help string and alias
> - `SelfTestLaunch:66`
> - `MenuLayout.shortTitle` ("Icons")
> - `SentenceText.properNames` ("Hidden Icons")
> - `EventCategory.icons` (counts only; `isExportedInDiagnostics` decided and L9-checked)
> - the `KillSwitches` doc
> - `ModuleContext.moduleDiagnostics`: generalize from Awake-only
> - `Onboarding:241`, `GeneralPages:102`, `MenuBarPage:59` (iterate `allCases`; review the layout for 4)
>
> Remove the claim about a lint exhaustiveness rule.

### P-7 · Major · §2 (`SNMenuBarVisibility`), B1, Q5: the shim spec is below the house shim contract

**Finding.** Q5 says "like Snaptic's other private APIs". The existing contract (`SNMonitorPanel` plus
`PrivateDisplayAPI`) is: Swift reads raw type encodings, Kit `KitEncoding.Requirement` verifies them, the shim
refuses selectors that weren't verified, and an exception **poisons** the shim for the life of the process. The
umbrella header must also import the new header.

The plan copies Hidden Bar instead (`respondsToSelector` plus `@try`). That checks presence, not signature, and it
doesn't poison: after one exception the next collapse calls the same broken selector again.

Lint rule 11 bans `dlopen`/`NSClassFromString` in Swift outside two files, so an `IconsVisibilityBridge.swift` that
resolves anything fails lint. The completion's threading isn't specified either: the framework calls it on an
arbitrary queue, and rule2 requires `MainActor.assumeIsolated` in the hop.

The handler may also never be called (XPC death). Then `.calibrating` would stick forever and the bar would be
neither collapsed nor expanded. Hidden Bar has the same hole.

**Encodings on 27.2 (26B123), from a read-only probe:**

| Class | Selector | Encoding |
|---|---|---|
| `MBAssessmentModeConfiguration : NSObject` | `initWithAllowedSystemItems:allowedBundleIdentifiers:` | `@32@0:8@16@24` |
| `MBAssessmentModeConfiguration : NSObject` | `initWithUnrestrictedMenuBarItems` | `@16@0:8` |
| `MBAssessmentModeAssertion : NSObject` | `activateWithConfiguration:completionHandler:` | `v32@0:8@16@?24` |
| `MBAssessmentModeAssertion : NSObject` | `invalidate` | `v16@0:8` |
| `MBAssessmentModeAssertion : NSObject` | `init` | `@16@0:8` |

**Evidence.**
- `Sources/SnapticShims/include/SNMonitorPanel.h:3-22` (contract: rawEncoding, markVerified, isVerified,
  isPoisoned).
- `Sources/SnapticShims/include/SnapticShims.h` (umbrella and its rules).
- `Sources/Snaptic/Displays/Platform/PrivateDisplayAPI.swift` (`PrivateSymbol`, `KitEncoding.Requirement`, kill-switch
  key `Displays.disable.symbol.<name>`).
- `scripts/lint.sh:144-147` (rule 11) and `:57-82` (stubs K4 implies `include/<name>.h`).
- `HBNativeVisibilityShim.m:35-45` (presence-only check), `:53-56` (main-queue hop).

**Proposed fix (plan text, §2 and B1).**
> **SNMenuBarVisibility.h/.m** follows `SNMonitorPanel`:
> - API: `isAvailable`, `isPoisoned`, `rawEncodingForClass:selector:`, `markVerified:`,
>   `activateWithSystemItems:bundles:completion:`, `invalidate:`.
> - `dlopen(RTLD_LAZY|RTLD_LOCAL)` and `NSClassFromString` happen **inside the .m**, so lint rule 11 is unchanged.
> - Any `@catch` poisons the shim. A poisoned shim reports unavailable until relaunch, and the module fails open.
> - The completion is hopped to the main queue in the .m. Swift wraps it in `MainActor.assumeIsolated`.
> - Header imported in `SnapticShims.h`. stubs.tsv gets one K4 row.
>
> Swift side: `Icons/PrivateMenuBarAPI.swift` checks the five encodings above with `KitEncoding.Requirement` before
> `markVerified`, and reads `Icons.disable.native` before every resolve.
>
> The Kit core arms a **5 s activation timeout**. On expiry it bumps the generation, treats the request as a failure
> (fail open, one notice), and invalidates any late success. K2 test: "activation never completes".
>
> No `#if HIDDENBAR_NATIVE_VISIBILITY`-style compile flag: the CI SDK (Xcode 16.4, macOS 15) builds the shim
> unchanged.

### P-8 · Major · H9, §4.5, §4.9, A3b: the activation-policy inventory is incomplete, and collapse can deactivate safety panels

**Finding.**
1. **Wrong sites.** The policy is switched at four runtime sites in two files, not "three places":
   - `SettingsWindowHost.swift:50` (show) and `:131` (willClose)
   - `Onboarding.swift:61` (show) and `:144` (willClose)

   `SnapticEntry.swift:48` is the launch default and `:79` is the pre-run refusal alert. Neither is a switching
   site; both stay as they are.
2. **The deactivate problem.** Many places call `NSApp.activate()` while the app stays `.accessory`, to bring a
   Snaptic panel forward:
   - `Backup.swift:30/63/177` (save and open panels)
   - `PermissionFlow.swift:248`
   - `AppDelegate.swift:176/203`
   - `UpdaterController.swift:182` (Sparkle)
   - `Relauncher.swift:68`
   - `SafeModeLeave.swift:33`
   - `Displays/Safety/ConfirmPanel.swift:88/127` (the display-change confirmation countdown)
   - `PreConfirmPresenter.swift:129`
   - `SystemColorsController.swift:89`
   - `PIPWindow.swift:222`
   - `CustomSessionPanel.swift:189`

   §4.9's collapse runs `NSApp.deactivate()` and reactivates the previous app. An auto-collapse during any of those
   panels takes key focus from it. For ConfirmPanel, Return/Esc "Keep"/"Revert" then go to another app while the
   countdown runs.
3. **Deferral too narrow.** §4.5 defers auto-collapse only while "the Settings window is key". Hidden Bar's
   `isPreferencesWindowVisible` has the same gap, but Snaptic has many more windows.

**Evidence.** The file:line list above, plus `StatusBarController.swift:68-71` and `:276-298`.

**Proposed fix (plan text, H9 and §4.5).**
> **H9.** Kit rule: `regular ⇔ settingsOpen ∨ onboardingOpen ∨ (icons.fullBarOnExpand ∧ icons.expanded)`.
> `ActivationPolicyController` replaces the four `setActivationPolicy` calls in `SettingsWindowHost` (show,
> windowWillClose) and `Onboarding` (show, windowWillClose). `SnapticEntry`'s launch default and refusal alert stay.
>
> When the full-bar reason ends, the controller calls `NSApp.deactivate()` and reactivates the remembered app
> **only if Snaptic has no visible window other than status-item menus** (`NSApp.windows.contains { $0.isVisible
> && $0.level != .statusBar && !($0 is NSPanel && $0.isFloatingPanel == false && …) }`; the exact predicate goes
> in the Kit rule as an input `snapticWindowVisible`).
>
> §4.5 re-arm reasons: replace "the Settings window is key" with "any Snaptic window is visible (Settings,
> onboarding, confirmation and pre-confirm panels, save and open panels, Sparkle, custom session, PIP editor)".
>
> Truth-table test: rows for `snapticWindowVisible`. M-check: auto-collapse with a display ConfirmPanel up doesn't
> take focus from it.

### P-9 · Major · §4.1, §4.2, A1, A2: arrangement validity, item lifecycle and request joining are missing

**Finding.** Hidden Bar refuses to collapse when the arrangement can't hide anything. On Length that means the
separator isn't on the hidden side of the arrow (`isArrangementValid`). It also refuses to hide the separators
when `⋮` is misplaced (`isBtnAlwaysHiddenValidPosition`). Without this, Length inflates a separator sitting
*right* of the arrow and pushes the arrow, Snaptic's own items and the visible icons off-screen. The user then
can't expand again from the bar.

Hidden Bar also re-shows its items at launch (`isVisible = true`), because ⌘-dragging an item off the bar
persists `isVisible = false` and leaves the app unreachable. Awake's indicator uses `.removalAllowed` plus a KVO
handler. The plan says nothing about whether the icons items allow removal.

Finally, a collapse while `.calibrating` never calls back in Hidden Bar (P-3), so a `snaptic icons hide` arriving
during a launch collapse would hang its CLI connection.

**Evidence.**
- `StatusBarController.swift:40-43,147-157,248-251`.
- `LegacyLengthEngine.swift:70-76`.
- `NativeVisibilityEngine.swift:80-83`.
- `Sources/Snaptic/Awake/UI/IndicatorController.swift:59-80`.

**Proposed fix (plan text, §4.1 and A1/A2).**
> - The Kit core gets `isArrangementValid` (Length: `|` on the hidden side of the arrow; Native: always true) and
>   `isAlwaysHiddenSeparatorPlaced`. With an invalid arrangement, collapse is refused, the arrow shows its
>   "arrangement" state, the Settings status row says "Drag the | divider to the left of the arrow", and the CLI
>   answers exit 2 with that text.
> - The three items are created with `behavior = []` (removal not allowed) and `isVisible = true` at every start.
> - Collapse requests that arrive while `.calibrating` join the in-flight one and get its result (K2 test).
> - Every CLI verb answers within the activation timeout (P-7).

### P-10 · Major · §6 "Snaptic's own items", A1, S0: Snaptic's own items land in the hidden zone on Length, and the seeding claim isn't from Hidden Bar

**Finding.** On macOS ≤ 26 a newly created status item is inserted left of all existing items. While Hidden Icons
is on, any Snaptic item created later lands left of `⋮`, in Always Hidden, or left of `|`. That includes:
- Awake's indicator, whose first appearance is created on demand (`ownIconWhenActive`)
- Displays or Window Switcher switched to "Always Show"
- the shared "Snaptic" item reappearing after `noModulesEnabled`

On Length that item is then hidden whenever collapsed. Native is safe, because the own bundle is allow-listed.

The §6 mitigation ("Snaptic's items sit right of the arrow by seeding") depends on writing
`NSStatusItem Preferred Position <name>` keys. Hidden Bar never writes those keys (no match in its source), so this
is new, unverified mechanism. And S0 tests seeding only on 27.2, where Length isn't used.

**Evidence.**
- `grep -rn "Preferred Position" /tmp/hidden-src/repo/hidden` finds nothing.
- `StatusMenu.swift:241-256,365-367` (slots created and removed on plan changes).
- `IndicatorController.swift:59-90` (Awake creates and removes its item).

**Proposed fix (plan text, §6 and S0, A1).**
> S0 adds a **macOS 15 or 26 VM run** (UTM; the macos-15 CI image can't show a bar). It verifies:
> (a) the insertion side for new items;
> (b) that writing `NSStatusItem Preferred Position Snaptic.icons.toggle` before creation sets the first-run order;
> (c) that a Snaptic own item created later (Awake indicator) with an unseeded position lands where predicted.
>
> A1: on Length, before any Snaptic status item is created for the first time while Hidden Icons is on,
> `IconsItems.seedPosition(for:)` writes a Preferred Position between the arrow and the system items. This is the
> arrow's current position minus a margin. Positions are distances from the right edge.
>
> If S0 shows seeding doesn't work, §6 instead says: "On 14–26 a Snaptic icon that first appears while icons are
> collapsed can land in the hidden section; ⌘-drag it right once."

### P-11 · Major · §5 (A6 only), every work item: stubs.tsv rows and lint scope updates are needed per item, not once in A6

**Finding.** lint rule 6 requires *every* `.swift`/`.m`/`.h` under `Sources/` and `Tests/` to be listed in
`scripts/stubs.tsv`. K1 is the first commit with new files, so it fails lint as soon as it lands. The plan budgets
rows only in A6.

Several `lint03.py` scopes are path lists that won't cover `Icons/`:

| Rule | Current scope | Missing for Icons |
|---|---|---|
| L7 | `SETTINGS_VIEWS` (`:446`) | `Icons/UI/` |
| L13 (no NSHostingView in menus) | Core `Menu*`, `Displays/UI/*Menu*`, two Awake files | `Icons/UI/IconsMenuRows.swift`, `HiddenListMenu.swift` |
| L14 (`.common` run-loop modes) | `Awake/` and menu files | `Icons/`; the auto-collapse and dwell timers must fire while menus track |

Lint rule 9 also bans `AXUIElement`/`AXIsProcessTrusted` in `SelfTest*.swift`, so H8 can't touch the inventory.

**Evidence.**
- `scripts/lint.sh:57-82` (rule 6) and `:102-110` (rule 9).
- `scripts/lint03.py:446-448` (L7), `:512-520` (L13, L14), `:486` (L6: `NSMenuItem(` only in MenuKit).
- `scripts/stubs.tsv` (588 lines; kinds L/S/K*).

**Proposed fix (plan text, §5).**
> Every work item that adds a file adds its stubs.tsv row in the same commit (kind `L`, owner `lead`; K4 for the
> shim). Done-when for every item includes `scripts/lint.sh --strict` clean.
>
> K1 also extends `lint03.py`: add `"Icons/UI/"` to `SETTINGS_VIEWS`; add the two Icons menu files to L13; add
> `under(p, "Icons/")` to L14. Menu rows are built only through MenuKit (L6). Timers and observers use
> `MainActor.assumeIsolated` (rule2).

### P-12 · Major · §5 done-when (B1, A7, the manual checklist): several criteria can't be verified as written

**Finding.**
1. **B1.** "SelfTest `icons.shim` passes on 27": CI runs `macos-15` with Xcode 16.4, where MenuBarClientCore doesn't
   exist. There's also no named-check registry; SelfTest has modes (`--selftest-launch`, `--selftest-controls`, …).
   A check that "passes" only on 27 either fails CI or is never run.
2. **A7.** The Awake verbs are checked in-process by `--selftest-controls` (`awakeCases`), not by
   `selftest-control-server.sh`.
3. **Checklist numbering.** §5 says "M1–M22" but A3b uses M23–M25.
4. **Length coverage.** The Length engine is what every 14–26 user gets, yet the only test machine is 27.2. No item
   requires a 14–26 run before release.
5. **Off-state audit.** A4's audit checks an EventLog counter, but `--selftest-launch` already builds a `ModuleHost`
   and asserts no module started. Constructing `IconsModule` must create no status items, which is easy to break
   with a stored-property `NSStatusBar.system.statusItem(...)`, as Hidden Bar does.

**Evidence.**
- `.github/workflows/build.yml:121-135` (macos-15, Xcode 16.4).
- `Sources/Snaptic/Core/SelfTest.swift:37-43,67-95,113-150`.
- `SelfTestLaunch.swift:60-68`.
- `StatusBarController.swift:18-20`.

**Proposed fix (plan text, §5).**
> - **B1 done when:** `--selftest-launch` prints `selftest-launch: icons shim available|unavailable|poisoned` and
>   fails only on `poisoned` or on an encoding mismatch while available. On CI (macOS 15) it must print
>   `unavailable`. A local 27.2 run must print `available` (recorded in STEP0-NOTES).
> - **A7 done when:** `--selftest-controls` gains `iconsCases` (show, hide, toggle, `status`, `status --json`,
>   `--all`, bad args → usage) against probe handlers, as `awakeCases` does.
> - **A4 done when:** `--selftest-launch` still reports 4 modules and 0 running, and `IconsModule.init` creates no
>   `NSStatusItem` (items are made in `start()`).
> - **Checklist:** renumber to M1–M25 in one table.
> - **New R gate:** the Length-engine M-checks (M1–M14 subset) are run once on macOS 15 or 26 (VM), and the results go
>   in `MANUAL-CHECKS.md` before release.

---

## Minors

### P-13 · Minor · H3: kill-switch plumbing isn't spelled out

`KillSwitches.read` needs a `CaseIterable` Kit enum (`KitModules.swift:8-16`). Add `package enum IconsFeature:
String, CaseIterable { case native, length, inventory, hover, axpress }` in Kit. List each switch in the Advanced
sheet's diagnostics with a `DefaultsLockRow` (pattern: `MenuBarPage.swift:190`), and update the `KillSwitches` doc.

Say whether a switch set while running takes effect live. Proposed: through `DefaultsKeyObserver` for
`Icons.disable.native` and `Icons.disable.length`, which expands at once; the others at the next start. K2's "kill
switch mid-collapse" case needs that answer.

### P-14 · Minor · §2: Kit file homes don't follow the tree

SnapticKit is flat apart from `Config/` and `Controls/`, with module-prefixed files (`AwakeClock.swift`,
`AwakeCommandGrammar.swift`, `Config/ConfigAwake.swift`).

**Proposed:**
- `SnapticKit/IconsModel.swift`, `IconsLayout.swift`, `IconsEngineCore.swift`, `IconsPolicy.swift`,
  `IconsCommandGrammar.swift`, `IconsActivationRule.swift` (H9)
- `SnapticKit/Config/ConfigIcons.swift`
- tables per P-4

Use `ClockNow` (`AwakeClock.swift:6`) for time. Basenames must be unique per target (lint rule 1), so check
`IconsModel` and similar against the tree.

### P-15 · Minor · §6 "Two hiders": `OtherAppsMonitor` can't warn about hiders as it is

`KnownDisplayApp` is keyed by `overlapping: Set<DisplayFeature>`, and `OtherAppsPolicy.pauseOverlapping` pauses
display features (`OtherDisplayApps.swift:8-48`). Hidden Bar, Bartender, Ice and Thaw have no display feature.

**Proposed:** a separate Kit list `KnownMenuBarHiders` (bundle prefixes `com.dwarvesv.minimalbar`,
`com.surteesstudios.Bartender`, `com.jordanbaird.Ice`, and the Thaw id once verified). The Icons page shows a
warning row (a `ControlState`) when one is running. It doesn't pause anything.

### P-16 · Minor · H2: the tab shortcuts don't need to "grow"

`MenuTabs` already addresses ⌘1–⌘9 by position (`MenuLayout.swift:117`) and makes tabs only when two or more modules
are shared (`:122-124`). Icons is ⌘4 only when all four are tabs.

**Proposed:** "MenuTabs is unchanged. Add a test with 4 shared modules (`keyIndex`, `barHelp(tabCount: 4)`,
`labelStyle` with 4 widths for `shortFit`)."

### P-17 · Minor · §4.7: the CLI gating text and policy

A verb of an off module simply isn't registered, so it answers "Unknown command. Run “snaptic help” for the list."
(`ControlCommandRegistry.swift:97-100`). There's no per-module "is off" message.

**Proposed:**
- Either keep that (and say so) or add a Kit `KitControl.offModuleMessage(verb:)` for every module.
- Policies: `icons status` is `.read`; show, hide and toggle are `.low`; `offOnly: false`; `cliAllowed: true`.
- Add `icons` to nothing in `protectedSettings`.
- `status --json` keys: `engine`, `state`, `visible`, `hidden`, `alwaysHidden` (counts only).

### P-18 · Minor · K1 "multi-display": the coordinate spaces must be pinned

The AX inventory reports top-left global positions. The arrow's frame comes from its AppKit window (bottom-left,
on the screen whose menu bar holds it). Hidden Bar compares only x and assumes one bar.

**Proposed K1 text:** "The resolver compares x only. Both inputs are normalized by the app to the screen that holds
the arrow's window. Inventory items whose x falls outside that screen's `frame.minX…maxX` are dropped. Tests: two
screens side by side, the arrow on the secondary screen, an item at the same x on the other screen."

### P-19 · Minor · H4: `requiredPermissions` changes at runtime

`ModuleHost.swift:302` and `:655-659` compute needed permissions from running modules at start and request time.
H4 makes Hidden Icons' set depend on settings (the hidden-icon list, the new-icon policy).

**Proposed:** "Changing a setting that adds Accessibility calls `moduleContext.requestPermissions()`. A setting that
removes it never revokes anything. The Permissions page reads the live value." The page already derives rows from
`requiredPermissions` (`PermissionsPage.swift:110-117`), so the separate "row" text in H4 is automatic. Drop it, or
make it the module's subtitle.

### P-20 · Minor · §4.2: click wiring details

Copy Hidden Bar's `sendAction(on: [.leftMouseUp, .rightMouseUp])` and open the menu with
`menu.popUp(positioning:at:in:)` at the button's bottom edge. **Never use `performClick` from the button's own
action**: Hidden Bar documents a recursion crash and a clipped top row (`StatusBarController.swift:164-198`).

"⌥-click" means ⌥ with either button or with another mouse button (`ExpandCollapseActionTests`). VoiceOver AXPress
(nil event) toggles.

### P-21 · Minor · Document hygiene

- §4.1 "**[Q1]** decides whether 14–26 is supported at all" is stale; Q1 settled it. Delete the line.
- §4.9 sits between §4.5 and §4.6. Renumber.
- §1 calls the engine split "Same model", but Native hides `|` (`isVisible = false`) and uses the arrow as the
  boundary. Say so in §4.1's order line.
- Use `Bundle.main.bundleIdentifier` (it's `app.snaptic.Snaptic` today) rather than a literal.
- "Hidden icon" already means "a Snaptic module icon set to Don't Show" (`ControlState.hiddenIconWarning`,
  `menubar.page.warning`). Rename the new list "Hidden apps list" or "Icons list" in code ids, to avoid
  `hiddenIcon*` collisions in grep and search.
- Fix the Hidden Bar source paths as listed at the top of this review.

### P-22 · Minor · §4.4 Native new-icon allow-list: it needs a persistence and size rule

The allow-list holds bundle ids, which H7 keeps out of backups. Say where it lives: `SnapticIconsV1`, sanitized,
capped (e.g. 64 entries, LRU), cleared by Restore Defaults. Say when an entry leaves: when the next unrestricted read
places that bundle in any section. K2 test: a bundle that is allow-listed and then dragged into Hidden is removed
from the list on the next collapse.

### P-23 · Minor · §4.6: the AX reflow poll and AXPress run on the main thread

"Waits for reflow (≤ 300 ms, polling the AX position)" must not block the main thread. Each AX call has a 0.1 s
timeout, as in Hidden Bar. **Proposed:** poll on a background queue at 30 ms intervals, cap at 300 ms, then
AXPress there, and hop back to the main thread for the auto-collapse re-arm. The press goes through
`Icons.disable.axpress`.

### P-24 · Minor · A3b and §4.9: "not offered while the Window Switcher is mid-switch" has no hook

No API exposes "mid-switch". The switcher already filters Snaptic's own pid from its lists
(`WindowManager.swift:246-249`, `WindowGatherer.swift:60-62`), so a `.regular` Snaptic doesn't appear in them.

**Proposed:** drop the clause. Alternatively, define it as "the switcher panel is visible" and read it through a
`ModuleHost` query, and add it to the H9 rule's inputs.

---

## Ordering note

The order K1 → K5 → B1 → A1 … works, with two changes. K4 (the `ModuleID` change) breaks the four pinned tests (P-5),
so make it the first Kit item, or fold the test updates into it. And P-11's lint scope edits land with K1. Run S0's
VM leg (P-10) before A1, because the seeding result decides A1's design.
