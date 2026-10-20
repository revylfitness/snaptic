# Brief: tabbed Snaptic menu (0.3.1), current state

Repo: /home/claude/snaptic, read-only. All paths are relative to it. "PLAN" means `docs/design/0.3/PLAN.md` (r5 final). `PLAN-r4.md` §5 is almost the same text at lines 2819–3046. PLAN's §5 starts at line 3380.

## 1. How StatusMenu builds menus, and the plan

**Slot** (`Sources/Snaptic/Core/StatusMenu.swift:25-35`): one `NSStatusItem`, one long-lived `NSMenu`, `module: ModuleID?` (nil means the shared "Snaptic" item) and `dirty = true`. `makeSlot` (289-299) sets `menu.delegate = self`, `autoenablesItems = false` and `item.menu = slot.menu`. The shared slot is `shared`; own-icon slots are `own[ModuleID]` (38-39).

**Dirty/rebuild:**
- `requestRebuild()` (236-242) only sets `dirty = true` on every slot. It also re-sends provider rows when Recent Notices appears or disappears, and only while no menu is open and no plan is pending.
- Rebuild triggers: Combine sinks in `install()` (64-118) fire on any Awake runtime `objectWillChange`, any `awakeStore` or `displaysStore` change, and `toasts.onRecentChange`. `ModuleContext.requestMenuRebuild` (ModuleHost.swift:329) is called by modules and Displays controllers, and `otherApps.onRunningChange` (ModuleHost.swift:366-369) also calls it.
- `menuNeedsUpdate` (257-262) calls `permissions.refresh()`, then builds only when the slot is dirty, then clears the flag. A requestRebuild while the menu is open changes nothing on screen until the next open.
- `menuWillOpen` / `menuDidClose` count `openMenus` (264-276). `menuDidClose` is deliberately "nothing structural" (comment 270, R3C §5.6). Its only job is to re-run a pending plan on the next main-queue turn.
- `willHighlight` forwards to `MenuKit.menu(_:willHighlight:)` (278-280).
- `menuHasKeyEquivalent` returns false (282-285; R4C §4.6: key-equivalent scans must not trigger rebuilds).

**applyPlan deferral** (185-220): while `openMenus > 0` it only sets `planPending = true` and returns. Otherwise it computes `currentPlan` (174-181, from `ModulesConfig.statusItemPlan(... sharedExistsNow:)`) and does the following in one turn:
- creates or removes the shared item and the own items;
- sets icons;
- calls `applyProviderRows`, which sends each `StatusItemProvider` a `CustomItemRow` (222-232);
- calls `requestRebuild()`.

**build(slot)** (345-373):
1. `removeAllItems()`.
2. Groups, in order: safe-mode rows (if active, 375-384).
3. Own slot: `section(id, header:false)` then `ownFooter`.
4. Shared slot: "No Modules Are On" when `plan.noModulesEnabled`, then one group per `plan.shared` id via `section(id, header: id != .awake, compact: id == .awake)` (361-364), then `sharedFooter`.
5. Groups are joined by a single separator (368-371).
6. `menu.minimumWidth = MenuKit.hasCustomRows(menu) ? 300 : 0` (372).

**section()** (389-400): calls `module.menuSection()` and detaches each item from any earlier menu (`item.menu?.removeItem`). It drops leading and doubled separators; in compact mode it drops all separators. It also drops trailing separators and returns `[]` when the section is empty, so empty sections get no group. Non-Awake sections get `MenuKit.header(module.title, control: "menu.snaptic.sectionHeader")`.

**Footers:**
- `sharedFooter` (403-413): optional "More Display Features…" (431-439), Recent Notices › (441-450), "Snaptic Settings…" ⌘, (opens General when no modules are on), Quit ⌘Q.
- `ownFooter` (417-429): "<Module> Settings…", plus upgrade, notices and Quit only when `plan.sharedFooterInOwnMenus`.

**Presence model:**
- `MenuPresence` (`Sources/SnapticKit/KitModules.swift:89-124`) has four cases: `.ownIcon` / `.ownIconWhenActive` / `.inSnapticMenu` / `.hidden`. `ownIconWhenActive` is allowed only for Displays and Awake (100-105).
- Stored per module in `ModulePreferences.presence` (`Config/ConfigModules.swift:4-72`).
- Defaults: Switcher and Displays `.inSnapticMenu`, Awake `.ownIconWhenActive` (194-199).
- `StatusItemPlan` (ConfigModules.swift:309-343) has these fields: `shared`, `ownIcon`, `showShared`, `noModulesEnabled`, `everythingHidden`, `custom`, `awakeCompactInShared`, `sharedActiveGlyph`, `sharedFooterInOwnMenus`.

**Plan logic** (`Sources/SnapticKit/MenuLayout.swift:112-153`):
- `shared` = live (enabled and running) non-Awake modules with `.inSnapticMenu`, plus `.awake` when `compact`. It is put in start order: `ModuleID.allCases` is `windowSwitcher, displays, awake` (KitModules.swift:20).
- Awake: `.ownIcon` means its own custom item (`custom=[.awake]`). `.ownIconWhenActive` means compact in shared while idle; while governing it means a custom item, plus compact only if the shared item was shown at rest. `.inSnapticMenu` means always compact. `.hidden` means nothing, or a custom item while governing if `shared` is empty or the shortcut is unbound.
- Displays and Switcher with an own icon go to `ownIcon` (`ownIconIDs`, 158-167; Displays' WhenActive needs an external display).
- So **0–3 modules can be in the shared menu at once**, and on a fresh install all three are (MenuLayoutTests.swift:26-37).
- `plan.shared` can change while Awake's state flips. Awake's compact entry can come and go, and the fuzz invariant at MenuLayoutTests.swift:436-442 shows the non-Awake members stay. Any of these changes is a pending plan while the menu is open.

**Custom provider:**
- Awake's own item is built by `IndicatorController` (`Awake/UI/IndicatorController.swift`). It is created and removed only in `applyStatusItem` (36-45). Its own `menuNeedsUpdate` rebuilds on every open with no dirty flag (132-136), using `rows.items(compact:false, footer:)`.
- `menuDidClose` calls `requestStatusPlan()` (143-147).

**Compact vs full Awake:**
- `AwakeModule.menuSection()` always returns the compact section (`AwakeModule.swift:138`, via `IndicatorController.compactSection()` 48-50).
- `AwakeMenuModel.rows` (`SnapticKit/AwakePresentation.swift:408-438`): compact omits every `.separator` and `.settings` ("Awake Settings…"). The full rows, with separators and "Awake Settings…" ⌘,, exist only in Awake's own menu.
- StatusMenu additionally strips separators and gives the compact section no header (363, 392). PLAN §5.4 (3598-3601) is normative: no header and no internal separators, because the switch header's height sets the group apart.

## 2. MenuKit and custom rows

`Core/MenuKit.swift` is the only item factory (lint L6). Each item carries its `ControlID` as its `identifier` (`tag`, 176-179).

**Custom rows:**
- `switchHeader` (133-139) builds `NSMenuItem(...)` with `view = MenuSwitchHeaderView`.
- `MenuSliderRow` is an `NSMenuItem` subclass (`MenuSliderRow.swift:14`).
- `MenuKit.width = 300`, `rowInset = 14`, `highlightInset = 5`, `highlightRadius = 4` (13-19).
- `hasCustomRows(menu)` is true when any item has a view (158). StatusMenu then sets minimumWidth 300, otherwise 0 (StatusMenu:372). Today a Switcher-only shared menu is native width.

**`MenuRowView`** (MenuKit.swift:203-255), the base class for view rows:
- An `NSVisualEffectView(.selection)` highlight inset 5 pt, shown by `setHighlighted`.
- `viewWillDraw` syncs the highlight from `enclosingMenuItem.isHighlighted && isEnabled`.
- `highlightDidChange` lets subclasses recolor text (`selectedMenuItemTextColor`).
- Doc comment: "Rows are never clickable themselves; their controls take the mouse."
- `MenuKit.menu(_:willHighlight:)` (151-155) walks every item and sets the highlight on each `MenuRowView` (for arrow-key navigation).

**Existing rows that host an NSControl inside an open menu:**
- `MenuSwitchHeaderView` (`Core/MenuSwitchHeader.swift`) hosts an `NSSwitch` (.small) with target/action `switched(_:)` (54-58, 114-118).
  - Height is fixed at open time (26/40/54) and `update(isOn:detail:)` changes it in place. A line-count change returns false so the owner rebuilds after close (89-102, MenuKit 141-147).
  - Accessibility: the title label is not an element; the switch carries the label and the detail is the help (50, 58, 109-112).
  - "Mouse only: the same action always exists as a native item (parity M4)" (4-8; PLAN §5.1 item rules, about line 3434: "every slider action and every switch-header action also has a native path (C4)").
  - Its owner closes the whole menu after a toggle: `root.cancelTracking()` walking `supermenu` (AwakeMenuRows.swift:97-101, ux m17).
- `MenuSliderRowView` (`MenuSliderRow.swift:139-243`) hosts an `NSSlider` subclass `RowSlider`.
  - `mouseDown` wraps `super.mouseDown` (the slider's own tracking loop inside the menu's tracking) to emit `.began`/`.ended` (252-259). Scroll-wheel adjust is at 261-286.
  - VoiceOver and keyboard changes without a drag emit `.changed` + `.ended` (231-242).
  - Live values come from `bind(to:)` with `.receive(on: DispatchQueue.main)` (67-71); "main queue runs in the menu's event-tracking mode too" (7-8). Updates are ignored while tracking (75).
  - Accessibility label is title + value; value description is spoken text (222-223).
- Neither row uses `NSSegmentedControl`, and nothing else in `Sources/Snaptic` does either.

## 3. Each module's menuSection()

**Window Switcher** (`Switcher/WindowSwitcherModule.swift:106-143`):
- Rows: optional "Open Accessibility Settings…"; "Switch Windows" with the first active shortcut drawn as a key equivalent (comment 166-167: the menu is closed before the switcher opens, so the equivalent never fires by itself); or a status "No Shortcut Set" / "⌘ Shortcuts Are Turned Off"; "Gather Windows on This Display"; optional "Turn On Thumbnails…".
- No symbols, no live rows. It calls `context.requestMenuRebuild()` on state changes (71, 102, 204, 261).

**Displays** (`DisplaysModule.swift:192-195` calls `DisplaysMenuBuilder(context:).build()`; `Displays/UI/DisplaysMenuBuilder.swift`):
- Order: status rows (degraded, paused + Resume, other apps, helper stopped + Restart Snaptic; 43-80), then `config.menu.orderedSections` (displays rows and/or tools items; 31-36).
- Display rows (97-123): "No Displays Detected" / "All Displays Are Hidden" + Show All, otherwise `DisplayMenuBlock.topLevelItems` per display (device row with a one-level submenu, `MenuSliderRow`s, promoted items; `DisplayMenuBlock.swift:44+`).
- Single-display sliders come first via `DisplaysMenuPlan.slidersBeforeDevice` (`SnapticKit/DisplaysMenuPlan.swift:368-369`).
- Global items are placed with `DisplaysMenuPlan.place` (137-169): Restore pending, Arrange Displays…, section submenus, Display Tools ›.
- Every top-level item has a 16 pt symbol (PLAN §5.1 "images all or none").
- Live rows: sliders bound to runtime publishers (`BrightnessMenuItems.swift:46`, `DDCMenuItems.swift:67,76,92`, `ResolutionMenuItems.swift:120`).
- Header comment (16-19) says "The section header … and Safe Mode's row come from StatusMenu."

**Awake** (`Awake/UI/AwakeMenuRows.swift`):
- `items(compact:footer:)` (43-83) builds from `AwakeMenuModel.rows`. Rows: header (switchHeader), startDefault or turnOff, Add 15 min / Add 1 Hour + ⌥ alternate "Add Time…" (115-125, which must directly follow its primary), Keep Display On, End Command-Line Holds, Start Session ›, While an App Is Running › (app icons), Rules › (subtitle via `withSubtitle`, ⌥ alternates).
- Live: `observe()` (306-322) merges 9 runtime publishers into `refreshHeaders()` (326-332), which calls `MenuKit.update` on every registered header still in a menu.
- Headers are pruned with `headers.removeAll { $0.item.menu == nil }` at build (44) and at refresh (327). A header item that is removed from the menu and later re-inserted is no longer refreshed unless `items()` builds a new one.

**Assumptions about position:**
- Awake's compact section relies on having no header and on StatusMenu's separator logic (StatusMenu 362-363, 392).
- Displays relies on StatusMenu adding the "Displays" header.
- `section()` assumes separators between groups come from `build`.
- Safe-mode rows are always the first group (353).

## 4. Control registry and lint

**Registry:**
- `ControlID` / `ControlSpec` / `ControlKind` / `MenuPlacementSpec` / `ControlTable` / `ControlRegistry.tables` are in `SnapticKit/Controls/ControlRegistry.swift`.
- `ControlKind` (44-46) has `setting, button, navigation, list, statusAction, shortcut, menuItem, menuSlider, menuSubmenu, menuSwitchHeader`. There is no tab or segmented kind.
- The only exhaustive switch over it is `SettingsIndex.requiresSearch` (`SnapticKit/SettingsIndex.swift:203-210`; menu kinds return false).
- `ControlDeclaring` (`Core/ModuleContracts.swift:70-72`): `StatusMenu` declares `typealias Controls = StatusMenuControls` (StatusMenu:18-19).
- `StatusMenuControls` (`SnapticKit/Controls/StatusMenuControls.swift`): surface `menu.snaptic`; placements "Snaptic menu" and "own menus" with `customize: .none`; 11 specs including `menu.snaptic.sectionHeader` (`.menuItem`, `when: [.perItem("module")]`).

**ControlRegistryTests** (`Tests/SnapticKitTests/ControlRegistryTests.swift`):
- Each table is listed once and is named `*Controls` (98-103).
- IDs are unique and prefixed by the surface (105-111).
- `parentOn` targets are in the same table; `replaces` ⊆ legacy and not removed.
- `.setting` must have `search`.
- `.menuSlider` is never in a "submenu" location; `l.menu.*` replacements need `customize != .none` (146-156).
- Key cross-check (178-192): every leaf stored property of `ConfigFixtures.fullModules()` (`Tests/SnapticKitTests/Support/ConfigFixtures.swift:94-102`, a Mirror walk at 128+) must be covered by some spec's `keys` or by `ControlLegacy.internalKeys` (`SnapticKit/Controls/ControlLegacy.swift:65-86`). Any new `ModulesConfig` stored property is therefore caught.

**lint** (`scripts/lint.sh` → `scripts/lint03.py`):
- **L15** (760-808): the table must live in `Controls/<Name>.swift` and be listed in `ControlRegistry.tables`. A `ControlSpec` id must be one plain literal. In app code, `ControlID("…")` must be a single literal; a file using literals needs `typealias Controls = X`; each literal must be in X; and **every declared id must be used by some file aliasing that table**. So the tab-bar id must be declared in `StatusMenuControls` (or a new `*Controls` table plus a registry line) and used as a literal in a file with the matching typealias.
- **L6** (283-286): `NSMenuItem(` is allowed only in `MenuKit.swift`, `MenuSliderRow.swift`, `MenuSwitchHeader.swift`. Ratchet count is 0 elsewhere: `scripts/lint-legacy.tsv` has no menu rows.
- **L13** (325-329): no `NSHostingView` in `Core/Menu*.swift`, `StatusMenu.swift`, `Displays/UI/*Menu*`, AwakeMenuRows, or IndicatorController.
- **L14** (331-336): in any file with "Menu" in its basename or under `Awake/`: no `scheduledTimer(`, `RunLoop.main.perform`, RunLoop.main schedulers or `.default` modes (N15, PLAN:704).
- **Rule 2** (615-735): main-queue `asyncAfter`, observer, `Timer(` and KVO closures must wrap `MainActor.assumeIsolated`.
- **Apostrophes** (460-476): `L("…")` text must not contain `'`.
- **popup_case** (479-573): checks only SwiftUI `PickerOption` / `Picker`. An AppKit segmented control's labels are not linted, but design-spec §4.1 (`docs/design/0.3/design-spec.md:602-603`) requires Title Case for segmented options.
- Ratchet: L1–L14 counts must not exceed `lint-legacy.tsv`; `--strict` also fails when a count drops below its row.

lint.sh also checks:
- Every new Swift file must be listed in `scripts/stubs.tsv` (step 6; e.g. `StatusMenu.swift M K5`, `MenuLayout.swift M S`, `MenuLayoutTests.swift M K3`, `StatusMenuControls.swift M K21 … menu.snaptic`).
- Basenames are unique per target, Kit is Foundation-only with `package` top-level declarations, and extensions of types declared elsewhere are fileprivate (steps 1, 3, 4, 10).

**What a tab-bar control needs to pass:**
- A `ControlSpec("menu.snaptic.<x>", <kind>, menu: snapticMenu)` in a registered table; a new `ControlKind` case means updating the `SettingsIndex` switch.
- Its literal used in a file with a matching `typealias Controls`.
- Its `NSMenuItem(` either built inside an L6-exempt file or the exemption list extended.
- No timers or hosting views.
- A stubs.tsv row for any new file.
- If it is `.setting`-like it would need `search`; menu kinds are exempt (SettingsIndex:208).

## 5. Kit tests and a home for tab logic

**Existing tests:**
- `Tests/SnapticKitTests/MenuLayoutTests.swift`: the plan truth table (`config()`/`plan()` helpers 8-22), presence cases, glyph, shortcut status, and a 5,000-case seeded fuzz of invariants (390-446, uses `SeededGenerator`).
- `DisplaysMenuPlanTests.swift` (29 tests: frozen 46 ids, placements, symbols, sliders never in submenus).
- `AwakePresentationTests.swift` (AwakeMenuModel rows).
- `ConfigModulesTests.swift` (round trip, `firstRun == ModulesConfig()` at 230-243, sanitize, M2/M3), `KitBackupTests.swift`, `ControlRegistryTests.swift`.
- The test target is SnapticKitTests only (Package.swift:8-11); the app target exists only on macOS.

**Natural home for pure selection logic:** `SnapticKit/MenuLayout.swift`.
- `package enum MenuLayout` is described as "Small pure helpers around the plan", owner M (stubs.tsv:525).
- It sits alongside `extension ModulesConfig { statusItemPlan… }`, with tests in `MenuLayoutTests.swift`. The fuzz harness already generates random configs and plans, which a "selected tab ∈ plan.shared, fallback" invariant could reuse.
- Constraint: Foundation only, `package` visibility, no `os`/Combine (lint.sh step 3).

## 6. Config, persistence, migration, backup

**Stores:** `ConfigStore<T>` (`Core/ConfigStore.swift`) holds one UserDefaults key per model.
- `didSet` schedules a save on change (11-12).
- Outside changes are seen via `DefaultsKeyObserver` (49-51).
- ModulesConfig lives under `SnapticModulesV1` (ConfigModules.swift:109-188). Its fields: `modules`, `sharedSymbol`, `showNewDisplaysCard`, `newModuleCards`, `commandLine`, `otherApps`, `onboarding`, `onboardingPermissions`.
- Decoding is lossy per key with defaults (`c.lossy(.key, default)`, 151-171); `sanitized()` is at 173-188.
- The Displays menu prefs are `DisplaysConfig.menu` (`MenuConfig`, `Config/ConfigMenu.swift:28-81`).

**Side effect of writing ModulesConfig:** `modulesStore.$value.dropFirst()` triggers `scheduleApply()` (ModuleHost.swift:219-222). That leads to `applyNow` (300-319): module start/stop transitions, then `statusMenu.applyPlan()`. While the menu is open this becomes `planPending`, then `applyPlan` runs after close, then `requestRebuild`, then a full rebuild on the next open.

**Precedent for UI-only remembered state outside config:**
- `SettingsShell.lastRouteKey = "settingsLastRoute"`, a plain `UserDefaults.standard` string (`SettingsUI/SettingsShell.swift:12, 176-183, 324-327`). It is decoded tolerantly, with fallback when the route no longer exists.
- It is not in any ConfigModel, not in backups, and not cleared by General › Reset (`ModuleHost.resetAllSettings` 556-584 resets the stores only).

**Migrations:**
- `MigrationLedger` / `MigrationID` (`Config/ConfigMigrations.swift`, stored in `SnapticMigrationsV1`). Markers are recorded once, and pure migrations run in ModuleHost.
- "decoders never migrate (M2 excepted)" (3-6).
- A new lossy key with a default needs no ledger entry; this is the pattern used for `presence` (ConfigModules 45-52, 151-160).
- `firstRun` equality must hold: a new field's default must equal `init()` (ConfigModulesTests:230-243).

**Backup** (`SnapticKit/KitBackup.swift`):
- The modules section is not allowlisted. Only Awake has `allowedPaths` (43-57), so a new ModulesConfig field is exported and imported by default unless added to `removedPaths` (67-90). `modules.commandLine`, `onboarding` and `onboardingPermissions` are the precedents for excluded local state.
- The app side is `Core/Backup.swift:45,135,180`.
- **Menu Bar › Restore Defaults** calls `modules.resetMenu()` (ConfigModules 270-278), plus `menu.restoringDefaults(scope:.menuBar)` and the Awake indicator (MenuBarPage.swift:338-342).
- **The key cross-check** (section 4) requires a new ModulesConfig field to be in `internalKeys` or a spec's `keys`.

## 7. Docs and Settings that describe the menu

**Code and Settings UI:**
- `Core/MenuBarPage.swift`: page summary "Choose where Window Switcher, Displays, and Awake appear in the menu bar." (53); "The Snaptic icon appears when a module is set to Show in Snaptic Menu." (100); doc sketch (5-18).
- `Core/MenuPlacement.swift:12-28`: presence titles and help.
- `MenuBarPageControls.swift` (search entries).
- `CustomizeMenuSheet.swift` covers the Displays section only (doc 5-14); nothing about stacking.
- Toast `IndicatorController.swift:90`: "Awake is now in the Snaptic menu".

**README:**
- "## Menu Bar" (README.md:42-52; nothing there yet on the shared menu's layout).
- "### In the menu bar" (242-244), which describes "the compact Awake section in the Snaptic menu".
- Testing scope (673): "custom menu rows (alignment, keyboard, VoiceOver, live values while the menu is open)".

**design-spec.md §3:**
- §3.3 sketch and rules (522-549) show stacked sections with a "Displays" header. This is r1-era: it mentions "Show Awake as a separate item" and hosting rows.
- §3.4 (551-577): highlighting custom rows, keyboard ("Assume sliders in menu rows work with the mouse only… every slider action has a keyboard path"), run loop, "update values in place while it's open, so it doesn't flicker or resize".

**PLAN:**
- §5.1 (3382-3434): custom-row rules.
- §5.2 (3436-3496): stacked mockup, "sections separated by one separator" (3440), and **row budget ≤ 24 lines in the default setup, checked in HW-15** (3491).
- §5.4 (3598-3601).
- HW-15 (3860).

**Others:** RELEASE-NOTES-0.3.md:24; site/index.html:649.

## 8. Risks found in comments and docs

- **C3 / macOS 27:** "no right-click, hover, programmatic highlight or occlusion dependence" (StatusMenu.swift:14-17; PLAN §5.5:3605). `power-apis.md` §8 lines 305 and 325, plus `docs/design/macos27.md:59-66,128`, list these 27 problems:
  - `button.highlight(true)` has no effect (FB23330269);
  - hover/tracking areas were broken until beta 5;
  - occlusionState no longer reflects hiding (FB23349447);
  - right-click is not delivered.
  These are status-button issues. They bear on any design that switches tabs on hover or highlights a segment programmatically.
- **W16** (`docs/design/FIXES-R2.md:49-51`; StatusMenu 148-161): on 27, `isVisible` and occlusion can't be trusted. Items may sit in the overflow, so every action must also be reachable from Settings, shortcuts or the CLI.
- **Never mutating in `menuDidClose`** (R3C.md:382-391 "AppKit calls menuDidClose before it dispatches the selected item's action. Removing or replacing items there drops the click"; StatusMenu:270). A tab switch must not defer its swap into close.
- **Removing items under the mouse during tracking** (R2C.md:806 c12): "removing items whose NSSlider view is under the mouse makes the slider glitch or stop responding". The project's answer was dirty-flag rebuilds on next open plus in-place value updates. The codebase today never structurally edits an open menu: switch-header height stays fixed while open and a line-count change is deferred (MenuSwitchHeader.swift:5-8, MenuKit.swift:141-147, review-r2-code.md:138, PLAN:3409). Swapping items while open is new territory for this code and is not covered by HW-15.
- **Run-loop mode** (N15, PLAN:704; review-r2-code.md:89-96): an open NSMenu runs `NSEventTrackingRunLoopMode`. Work from a tab click must run synchronously in the action or via `DispatchQueue.main.async`, never `RunLoop.main.perform` or a `.default` timer (lint L14).
- **Width and height:**
  - A view row forces `minimumWidth = 300` (StatusMenu:372). Today a Switcher-only menu is native width.
  - Sections differ a lot in height. Displays with sliders is tall (PLAN row budget 3491), and the Awake compact section is 4–8 rows. Swapping changes the open menu's height.
  - The switch header row height is fixed at open (MenuSwitchHeader:11, 29-31).
- **Keyboard/VoiceOver parity:** custom rows are mouse-only and need a native twin (PLAN §5.1 C4/parity M4; MenuKit:131-132). `MenuRowView` rows are "never clickable themselves" and receive arrow-key highlight via `willHighlight` (MenuKit:149-155, 200-202). Items in non-selected tabs are not in the menu, so their key equivalents can't fire while it is open. Examples: Switch Windows ⌥⇥ is display-only; Snaptic Settings… ⌘, and Quit ⌘Q stay in the footer. Type-select is also limited to the visible tab.
- **Live updates and stale references:**
  - Awake header refresh drops headers whose `item.menu == nil` (AwakeMenuRows:44, 327), so cached and re-inserted headers stop updating.
  - Slider rows keep their Combine sinks while detached (MenuSliderRow:67-71).
  - Rebuild requests while open only set `dirty`. Re-calling `menuSection()` on a tab switch would show fresher state than the rest of the open menu.
  - `section()` detaches items from previous menus (395).
- **Awake switch toggle closes the whole menu** (AwakeMenuRows:97-101), so reopening goes through `menuNeedsUpdate`.
- **Plan changes while open are deferred** (StatusMenu:187-190). The set of tabs (`plan.shared`) can't change mid-open, but it can differ on the next open: Awake compact appears or disappears with a session, a module is disabled, or presence changes. A remembered tab can name a module that is no longer shared.
- **Persisting the tab in ModulesConfig:**
  - Each write triggers `scheduleApply` and then `applyPlan` (pending while open, re-plan and rebuild after close).
  - It flows into backup export/import unless listed in `removedPaths`.
  - It needs an `internalKeys` entry for the key cross-check.
  - `resetMenu()` and General Reset then govern it.
  - A plain UserDefaults key like `settingsLastRoute` avoids all of these but bypasses ConfigStore's outside-change observation.
