# Review r2: internal consistency (PLAN.md r2)

Counts: **1 Blocker, 7 Major, 14 Minor.** Checked against `Sources/SnapticKit/Config/*`, `KitModules.swift`, `scripts/stubs.tsv`, TEAMS.md.

## Blocker

**B1. `StatusItemPlan`/`MenuPresence`: one type, two homes, two owners, wrong step.** §5.2 and §6.2 M put `MenuPresence`, `StatusItemPlan` and `ModulesConfig.statusItemPlan` in M's new `SnapticKit/MenuLayout.swift`, built in step 1. But `StatusItemPlan` and `statusItemPlan(running:)` **already exist** in `Config/ConfigModules.swift`, which §6.2 moves to the lead. Nothing says they move out. The lead's step-0 work also needs M's types: M2 needs `MenuPresence` and `legacyPlacement`, §6.4 needs "`StatusItemPlan.custom` (empty)", and `StatusItemProvider.presenceDidChange(MenuPresence)` (§2.11) needs `MenuPresence`. §6.3 says the lead hand-writes (S) "every Kit type in **§2**". These types are in §4/§5, and so are `SettingsRoute`, `SettingsSearchEntry` and `ValueFormat`, which the lead's `ModuleContracts` and M's `MenuSliderRow` reference. As written, step 0 either declares the type twice or edits M's file.
*Fix:* in §6.2, state that `StatusItemPlan` and `statusItemPlan` move from ConfigModules to MenuLayout (M), and that `MenuPresence` is declared in `KitModules.swift` (lead, beside `MenuPlacementChoice`). In §6.3, widen the S rule to "every Kit type in §2, §4.1, §4.5 and §5.2", so the lead writes the step-0 stubs of every type it references.

## Major

**M1. `awake hold` has no path for the peer pid.** §2.10 and §3.1 need `getsockopt(LOCAL_PEERPID)` on the client socket and a 1/s limit per verb. The CLI handler today receives no socket facts (`ControlCommandRegistry.register(... _ handler: Handler)`), and `Core/ControlServer.swift` (owner A) appears in no team's list in §6.2 and in no step in §6.4. J's `ProcessFacts` can't read a socket it never sees.
*Fix:* add to A in §6.2/§6.4 step 1: "ControlServer + ControlCommandRegistry: `Handler` gains a `ControlPeer { pid, uid }` argument; a per-verb rate limit option". Or make it a lead contract change in step 0.

**M2. "Appear active" / "Move the pointer slightly" can't take effect.** §4.3 Awake Advanced shows them as feature switches (`activity`, `pointerNudge`), and the help says "while a session runs". But `ActivityInputs.mode` (§2.9) comes from the session's options, `AwakeSessionOptions.activity` defaults to `.off` (§2.3), and the page edits only `defaultOptions.display` (§4.3 Durations row). A user who turns the switch on gets no activity unless they edit each preset.
*Fix:* define the rule in §2.14. Either the Advanced switch also sets `defaultOptions.activity` (`.declare` or `.nudge`), or `effectiveOptions` maps `.off`-by-default to `.declare` while the `activity` feature is effective. Add a Kit test in §6.6.

**M3. The rule for when the Snaptic item exists contradicts `everythingHidden` and N11.** §5.2 says the Snaptic item is shown iff "…or no module has its own icon or custom item". With every module on Don't Show, that clause shows the item. Yet `everythingHidden`, the Menu Bar warning "No Snaptic icon is shown" (§4.3), and N11 ("if no Snaptic icon exists either…") all assume it is absent.
*Fix:* make the third clause "or no module is enabled", and add "everything Don't Show → no item" to the §6.6 MenuLayout truth table.

**M4. M4's Kit migration references action ids that live only in the app.** §4.6 M4 writes `keys.shortcuts[showPanel]` and `[identify]`. The real ids are `DisplayActionID(rawValue: "f.showPanel")` and `"f.identify"`, declared in `Displays/UI/OverviewController.swift` (F, app target). Kit `DisplaysConfig.init(from:)` can't see them, and the names in the plan match no constant.
*Fix:* declare `DisplayActionID.fShowPanel` and `.fIdentify` in Kit (lead, KitModules), use them in M4 and in OverviewController, and spell the raw values in §4.6.

**M5. M6 is not scheduled, not tested, and misdescribes the code.** §4.6 gives M6 to B, but B's §6.4 steps are only `Fingerprint.matches`, observability and sub-pages. The step-0 row covers only M2–M5. §6.6 tests M4/M5 but not M6, while §6.5 requires "M1–M6 tested". Also `SafetyConfig.panicHotkey: HotkeyCombo?` already exists, as a custom combo placed first in `panicHotkeyCandidates` with the fixed default and fallback after it. "Make it editable; store the default explicitly" changes what the fallback ⌃⌥⌘⇧⎋ does.
*Fix:* schedule M6 for B in step 2 and add a `SafetyConfig` M6 test to §6.6. Restate M6: the UI edits `panicHotkey`, nil stays "default with fallback", and `panicHotkeyEnabled` keeps its meaning (or say otherwise explicitly).

**M6. Reset All Settings can't clear consent under the plan's own API and lint.** §2.13 and §3.2 have `ModuleHost` (Core) clear consent on Reset All. But `AwakeConsentStore` exposes only `record(_:)` (§2.14), and lint L11 allows `consent.record(` only under `Awake/UI/` and `SettingsUI/`.
*Fix:* add `func clear()` to `AwakeConsentStore` (lead), allowed in `Core/ModuleHost.swift`, and name it in L11.

**M7. Kit tests for Kit types that are never declared.** §6.6 tests `AwakeCommandGrammar`, `CPUMath` and `NetworkMath`, and §6.2 lists them as G/J Kit files, but §2 gives none of them a signature. Nothing says what `AwakeCommandGrammar` parses beyond `AwakeDurationGrammar`: `--pid/--parent`, `display-may-sleep`, `preset <n|name>`. "64-bit byte deltas" are tested under CPUMath but belong to network counters. Also undeclared: `AwakeMigrationResult` (§4.6 M1), the `DisplaysConfigSection` enum (§4.5), and the scope type of `DisplaysConfig.restoringDefaults(scope:)`. The lead can't write S stubs for these.
*Fix:* add signatures to §2.10 (`AwakeCommandGrammar.parse(verb:args:) -> AwakeCommand?`), §2.8 (`CPUMath.load(prev:now:)`, `NetworkMath.cidrContains`, `.byteDelta`), §4.5 (the full `DisplaysConfigSection` case list) and §4.6 (`AwakeMigrationResult`, `DisplaysRestoreScope`).

## Minor

1. **Sidebar has 7 rows, not 8.** §4.2's list has seven entries (General, Menu Bar, Window Switcher, Displays, Awake, Permissions, About). Yet §0 says "31 rows → 8", §4.2 says "8 rows", and §6.4's step-1 exit says "all 8 roots". *Fix:* say 7 everywhere.
2. **Wrong menu item name in own menus.** §5.2 and the r2 row "parity M3" say own and custom menus end with "Snaptic Settings…" and "Quit Snaptic". The §5.3 mockup ends with "Awake Settings…". §0 point 3 says "Settings… last", but Quit is last. *Fix:* §5.3 uses "Snaptic Settings…" when the Snaptic item is absent (else "Awake Settings…"); §0 says "Settings… then Quit last".
3. **r2 row "code m11" claims every `.none` case was renamed**, but `ActivityDecision` still has `case none` (§2.9). *Fix:* rename it `.idle` (or `.skip`).
4. **Extend copy differs.** The toast button says "Extend 1 Hour" (§1.4, §2.5), while the menu and Settings say "Add 1 Hour" (§5.3, §4.3). *Fix:* one label.
5. **Module-off confirmation copy differs** between §2.12 and §4.3. *Fix:* keep §4.3's text and reference it from §2.12.
6. **Preset sheet "Default (Keep on)" (§4.3) is wrong for task-bound kinds**, whose default is May sleep (§2.14 `effectiveOptions`, OQ-2). *Fix:* the label shows the per-kind default.
7. **"X" means two things.** In §4.8 the legend says X = removed, but `nightShift (X)`, `applePresets (X)` and `hdrVirtual (X)` mean Experimental and are kept in Col A / VD A. That risks wrong `ControlMap.removedSettings` rows. *Fix:* use "Exp" in those cells.
8. **`changedSections` per-display subsections (§4.5) leave out `perDisplayKeys` and `perDisplayPIP`**, which exist in `PerDisplayConfig`. *Fix:* add both.
9. **ConfigModulesTests updates are incomplete (§2.13).** Line 16 (`placement(id) == .shared` for every id) also fails once Awake defaults to `.ownIconWhenActive`. And 0.1 upgraders take `ModulesConfig.upgradeDefaults()`, which has no Awake entry and therefore gives Awake *enabled*, contrary to C7. *Fix:* add line 16 to the list and insert Awake disabled in `upgradeDefaults()`.
10. **Ownership moves are not marked ⇢ in §6.2.** `Displays/UI/MenuCustomizationPage.swift` and `Core/MenuSliderItem.swift` are A's today but listed under M. `ManagedMenuItem` lives in `Displays/Management/ManagementSupport.swift` (D), which §5.1 deletes but no list names. `EventLog.swift` (A) needs the `record(_:event: AwakeLogEvent)` overload (§3.6), unassigned. *Fix:* add these to §6.2.
11. **Onboarding has two owners.** §4.7 gives onboarding to H, but `AwakeOnboardingStep` is G's (§6.2) and no step in §6.4 schedules it. *Fix:* G does it in step 2, behind H's step protocol.
12. **No step schedules the ToastPresenter changes** (presenting/screensaver suppression, routing to Recent Notices; lead, §2.5/§6.2), and the §6.4 step-0 table omits them. *Fix:* add them to the lead's step 2.
13. **Several homes are unstated.** `AwakeBehavior`/`UserSwitchEnd` (§2.6) have no file: §2.6 sits under AwakeGuards.swift but says the type is "part of AwakeSessionsConfig". `ModuleContext.openSettings` is `(String?)` in code, while `AwakeHost.openSettings` takes `SettingsRoute?` with no adapter stated. `MenuSwitchHeader.swift` is listed (§5.1) but only `MenuKit.switchHeader` is declared. *Fix:* name the file and type for each.
14. **Some §4.3 wireframes and counts disagree with the defaults.**
    - The Menu Bar wireframe shows Show = "Icon and Time Remaining", but the default is `.icon` (§2.14).
    - The Brightness count is 6, but the page lists 7 visible controls (with `xdr`).
    - The Displays root counts "Automatically adjust brightness" as visible, although `autoBrightness` is Experimental and opt-in (Root A › Experimental).
    - The navigation rows "show On/Off", yet Brightness and Keyboard have no switch.

    *Fix:* align the wireframe defaults and state which assumptions the counts use.

## Spot-checks that passed

- DisplayFeature: 49 cases, matching the 47 + 2 claim and the §4.8 rows exactly.
- The 12 criterion kinds match.
- Every M1/M2/M3/M5 source key exists in the code (`features`, `management.preventSleep`, `identity.fingerprint/customName/lastKnownName`, `placement` shared/ownIcon/hidden, `showNewDisplaysCard`, `keys.osdShowNits`, `brightness.showNits`).
- The ratchet baseline counts match the current tree (54 Slider/Stepper, 125 captions, 18 `NSMenuItem(`, 7 `State(initialValue:`).
- Every other r2-table row I sampled is reflected in its cited sections.
