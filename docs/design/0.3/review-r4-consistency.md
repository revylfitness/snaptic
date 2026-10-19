# Review r4: internal consistency (PLAN.md r4)

Counts: **0 Blocker, 2 Major, 10 Minor.** Checked against the Kit sources and `Config/*`, the Core files the plan changes, `scripts/{stubs.tsv, lint.sh}`, TEAMS.md and review-r3-consistency.

## r3 findings

- **All 5 Majors are resolved.** M1: `menu.items`, `.disconnect`, Kit `cDDCPower`. M2: `NewModuleCard`. M3: the nudge refusal is gone from §2.3, §2.10 and §3.1. M4: `ActivityPolicy.nudgeAllowed`. M5: `schedule` has no service, and `TaskSessionMonitor` is gone.
- **14 of the 16 Minors are resolved.** Two are only partly resolved:
  - m11: the §2.1 diagram still gives the stores to `AwakeModule` (Minor 3 below).
  - m16: `KitLossy.swift` is listed as a "new lead file" (Minor 1 below).
- **Leftover scan is clean.** Every hit for consent, Keychain, `ControlCoverage`, `ControlMap`, `.hold` or `batteryUnreadable` is a "withdrawn" or "superseded" note.
- **§4.8.1 totals match:** 588 ids with no duplicates, and the code declares the 46 `DisplayMenuItemID`s the `l.menu.` row lists.

## Major

**M1. `ToastAction` already exists with a different shape** (§2.5, §6.2 lead row, §6.4 step-0 row).
- The plan declares `struct ToastAction { title; isDefault; action }` as if it were new (r3 m10's fix).
- `Core/ToastPresenter.swift:7` already declares `struct ToastAction { let title: String; let perform: @MainActor () -> Void }`.
- `show(_:action:lifetime:)` takes one of them.
- 15 files owned by A, B, C, D and E call `ToastAction(title:perform:)`, and the step-0 S stub as written would break all of them.

*Fix:* extend the existing type: `perform` stays, and add `var isDefault = false`. Add `show(_:actions:lifetime:)` beside `show(_:action:lifetime:)`. Say "extended" in §2.5 and §6.2.

**M2. The migration ledger can't reach the migrations that need it** (§4.6 intro vs the M3, M4, M5 and M10 rows; §6.2 "ConfigDisplays.swift (M4, M5, M10, migrations markers…)"; §6.6).
- The markers live in a separate `ConfigStore<MigrationLedger>` owned by `ModuleHost`.
- But M4, M5 and M10 run in "`DisplaysConfig.init(from:)` post-decode", and M3 runs in "`ConfigModules` decode". A decoder can't read or write another store.
- The legacy fields stay encoded until 0.4 (`osdShowNits`, `powerSwitch`, `showNewDisplaysCard`). So these migrations re-run on every decode, which is exactly r1's code M3 bug: the user's later off comes back, and hidden items and dismissed cards reappear.
- No Kit API applies a ledger at all. `AwakeMigration.fromDisplays` has no ledger parameter. That makes the §6.6 tests "M4/M5/M10 run once" and "ledger marker prevents a second run" impossible to write in Kit.

*Fix:* make them pure Kit functions over decoded values, e.g. `DisplaysConfig.migrated(ledger: inout MigrationLedger) -> DisplaysConfig` and `ModulesConfig.migrated(ledger:)`. `ModuleHost` calls them after loading, in the M1 save order. Move the "Where" column to `ModuleHost`, and give M3 a marker (`newModuleCards.v1`).

## Minor

1. **Ownership of `KitLossy.swift` and where types live.**
   - `stubs.tsv` gives `KitLossy.swift` and `KitLossyTests.swift` to **A**. §6.2 lists the file under Lead with no ⇢, and §6.3 calls it a "new lead file".
   - `NameHash` and `StableID.derived` sit in `KitLossy.swift` in §2.14 but in `KitModules.swift` in §6.2.
   - `ControlID` sits in `KitModules` in the §6.4 step-0 row but in `Controls/ControlRegistry.swift` in §2.2 and §4.8.

   *Fix:* mark both files ⇢ lead, and give each type one file.
2. **Leftover per-model migrations.** `DisplaysConfigSection.migrations` and §6.2's "migrations markers" in ConfigDisplays come from r3's per-model lists. `DisplaysConfig` has 15 top-level fields and no `migrations`, so "one case per DisplaysConfig field" is false. *Fix:* drop both.
3. **Store owner, again.** The §2.1 diagram says `AwakeModule` "owns AwakeConfig store, snapshot and history stores". §2.11, §2.13 and §6.2 say `ModuleHost` owns them.
4. **Trigger sessions and holds have no source.**
   - `AwakeHistoryEntry.source` is a non-optional `AwakeSessionSource`, and that enum has no trigger case. Yet automatic entries are recorded.
   - `DriveAlivePolicy.shouldWrite(sessionSource:)` doesn't say what a trigger session or a holds-only state passes. C9 says holds count as `.commandLine`.

   *Fix:* add `.rule` (and pass `.commandLine` for holds) or make it optional, and state the mapping.
5. **Search-index files have several owners.**
   - `SettingsIndexDisplays` takes "rows from owners via F".
   - J's Drives entries must go into G's `SettingsIndexAwake`.
   - `ControlRegistryTests` 3 requires an entry for every `setting` spec, so C/D/E/A/B and J must edit other teams' files. This is the pattern r3 m11 removed for control tables.

   *Fix:* use per-owner `SettingsIndex<Table>` files, or derive the entries from the specs.
6. **`AwakeTextContext` is never declared.** N12 and `AwakePreset.verbTitle(_:)` use it, yet the S rule needs it written from the plan in step 0. *Fix:* declare it (`uses24Hour`, `decimalSeparator`).
7. **Tests without a Kit API.**
   - "The 46 `DisplayMenuItemID`s all present": 26 of them are declared only in app files (BrightnessMenuItems, PIPMenuItems, PanicCoordinator, OverviewController, AutomationController), so a Kit test can't enumerate them.
   - "Assertion-hold backoff" has no Kit function.
   - §6.6 says `statusJSON` "incl. `pid`", but §2.10 emits `"pids"`.
8. **Protected words change too early.**
   - §2.10 and §6.4 step 1 replace `"sleepprevention"`, `"preventsleep"` in `KitControl.protectedSettings`.
   - §2.13 keeps `sleepPrevention`, including its KitControl rows, until step 3.
   - So from step 1 to step 3 the CLI can turn Displays sleep prevention on.

   *Fix:* add the Awake words in step 1 and remove the old ones in the step-3 merge.
9. **Two states with no defined behavior.**
   - §2.1 step 6 ("deactivating `process` ends every remaining hold") can't happen. The dynamic need `process` keeps ProcessWatch active while any hold exists, so turning the CLI off never ends `--pid` holds. Say which behavior is intended.
   - `Awake.disable.indicator` can be set, because `indicator` isn't unkillable. With every module set to Don't Show, a session then has no item at all, which contradicts N11. *Fix:* make `indicator` unkillable, or define the fallback.
10. **Wording drift.**
    - N4 and §6.5 say every Settings slider has a reset glyph. §4.1 and §4.3 deliberately give live Brightness none.
    - §4.1's example `ControlID("awake.batteryFloor")` lacks the `awake.page.` surface prefix that test 2 requires.
    - §2.13 cites `ConfigModulesTests` lines 15, 16 and 34, but only line 16 fails.
    - The same action is called "End Holds" and "End Command-Line Holds" in one status row (§4.3).
    - §2.5 says Start Anyway is "never from a menu item click", but §5.3 says a refused menu start "shows a toast with the button". Say "never as a menu item".

## Spot-checks that passed

- **Change tables.** lead-8…15 and the traced r3 rows appear in their cited sections.
- **Counts.** Awake menu 6/9 rows, Per Display group 23, Snaptic menu 17 + 3, Awake page 5/11 and Menu Bar 8/9 all add up.
- **Gate.** The `AwakeActivityGate` truth table agrees with N10, §2.5, §2.9 and §3.2.
- **Code names.** `SNProcess.startTime`, `ModuleContext.openSettings(String?)`, `firstRun(launchedBefore:)`, `dDisconnectItem`, `ControlCancellation` and `KitBackup.mergeByID`/`removedPaths` all match the code.

**Verdict: Ready with fixes.** Both Majors are mechanical: extend `ToastAction`, and move M3–M5/M10 to ledger-aware functions run by ModuleHost.
