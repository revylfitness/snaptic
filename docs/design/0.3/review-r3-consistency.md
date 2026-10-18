# Review r3: internal consistency (PLAN.md r3)

Counts: **0 Blocker, 5 Major, 16 Minor.** Checked against `Sources/SnapticKit/Config/*`, `KitModules.swift`, `ManagementIDs.swift`, `scripts/stubs.tsv`, `scripts/lint.sh`, TEAMS.md, `ConfigModulesTests.swift` and review-r2-consistency.

## Major

**M1. Migration M10 uses a field, a case and an id that Kit doesn't have** (§4.6 M10, §4.8 `c.ddc.power` row, §6.4 step-0 row "M2–M5, M10").
- `menu.itemVisibility` doesn't exist. The field is `MenuConfig.items: LossyMap<DisplayMenuItemID, MenuItemVisibility>`.
- `HeaderPowerSwitch` has `none, disconnect, ddcStandby`. There is no `.connect`.
- `c.ddc.power` is declared only in the app target (`Displays/UI/DDCMenuItems.swift`, C), so lead Kit code in `ConfigDisplays.swift` can't name it. r2 M4 hit the same problem with `f.showPanel`. `d.disconnectItem` is fine: it is in Kit `ManagementIDs`.

*Fix:* in §4.6, write `menu.items[...]` and `.disconnect`. Declare `DisplayMenuItemID.cDDCPower = "c.ddc.power"` in Kit (lead, KitModules or ManagementIDs), and have DDCMenuItems use it. Add it to the §2.2 KitModules list.

**M2. M1's General card is erased by M3's decode filter** (§4.6 M1 vs M3, §4.3 General card, §6.6 "`newModuleCards` with an unknown id").
- M1 appends `"awake.migrated"` to `newModuleCards`.
- M3 decodes `newModuleCards` "filtered to known `ModuleID`s".
- So the card for migrated users is dropped at the next decode, or at once by `sanitized()`.

*Fix:* store card ids as a closed Kit enum, e.g. `NewModuleCard: String { case awake, awakeMigrated = "awake.migrated", displays }`, and filter against that enum. Restate M3 and the §6.6 test.

**M3. With pointer movement on, every CLI `start` is refused** (§2.10 start/preset rows, §3.1 "presets or options with `nudge` are refused", §2.3 `notAllowedFromCLI` vs the §2.14 activity-switch rule).
- Turning on "Move the pointer slightly" sets `defaultOptions.activity = .nudge`.
- `awake start` uses the default options, so "refused if the resulting options use nudge" rejects every plain `start`.
- `hold` has no such refusal, so the verbs disagree.
- lead-1/N10 already gate pointer movement at runtime (`uiStartedInProcess`), so the refusal is a leftover from r2.

*Fix:* drop the nudge refusal from §2.10, §3.1 and `notAllowedFromCLI`. CLI sessions keep `.nudge` in their options, and `ActivityPolicy` downgrades it to `declare`. Or clamp CLI options to `declare` in `effectiveOptions`. Either way, state it once.

**M4. The core N10 rule has no Kit home, but §6.6 tests it there.** §2.9 defines `ActivityInputs.nudgeAllowed` as an input that the app computes ("pointerNudge effective ∧ preflight ∧ manual ∧ `isDirectUserAction && uiStartedInProcess`"). Yet §6.6 tests "`ActivityPolicy` … nudgeAllowed false for every non-UI or restored session", and §6.5/HW-19 depend on that guarantee. No Kit function computes it.

*Fix:* add `ActivityPolicy.nudgeAllowed(governing: AwakeGoverning, pointerNudgeEffective: Bool, accessibility: Bool) -> Bool` to §2.9. ActivityController calls it, and §6.6 tests it.

**M5. Two G app types have no declaration, service id or context member.**
- The `schedule` criterion source is "Ticker (G)" (§1.1, §6.2), but Ticker is not an `AwakeServiceID`, not an `AwakeContext` member, and not a `CriterionSource`. So `AwakeFeatureGraph.services(of: .schedule)` and `AwakeContext.source(for: .schedule)` have nothing to return.
- `TaskSessionMonitor (untilIdle + hold)` appears only in §6.2. §2.5 gives untilIdle to `SessionController` + `TaskQuiet`, and hold to J's `ProcessWatch`.

*Fix:* either declare `Ticker: CriterionSource` with a `schedule` service id (§2.1, §2.2, §2.11 context) or say the schedule kind needs no service. Then delete `TaskSessionMonitor`, or give it a §2.5 signature and remove the overlap.

## Minor

1. **Leftover consent wording.** §2.12 crash row: "resumes the **admitted** manual session". *Fix:* "the persisted manual session".
2. **Duplicate count.** §0 says "the 14 duplicates removed", but §4.4 has 17 rows (#15–17 are Awake). *Fix:* "17 duplicates (14 from [UA] plus 3 for Awake)".
3. **Start Again rule can't be implemented.** §1.1 says Start Again is "not offered for command-line and automatic entries", but §4.3 History hides it only for `process` and `automatic` kinds. A CLI `start 2h` records `duration`, and `AwakeHistoryEntry` has no source. *Fix:* add `source: AwakeSessionSource` to the entry, or adopt §4.3's rule in §1.1.
4. **CLI privacy line contradicts the pid.** §3.6 says CLI status shows "kinds and trigger numbers only", but §2.10 `--json` adds `"pid"` (`AwakeStatusFacts.holdPID`). *Fix:* §3.6 also lists the hold pid.
5. **Name drift.**
   - §2.14 calls the Awake pop-up "Show" (comment on `AwakeIndicatorStyle.icon`); §4.3 calls it **Time**.
   - §4.8 calls the menu style "Display controls"; §4.3 calls it **Style**.
   - §4.8 calls the Display Details link "Menu visibility…"; §4.3 calls it **Customize Displays Menu…**.
   - §2.1 writes `EventLog.record(_:)`; §3.6 writes `EventLog.shared.record(_:)`.
   - The §2.10 hold reply says "(at most 12 h)" even with `--max`.

   *Fix:* use the §4.3 names everywhere, and make the reply show the actual cap.
6. **Wrong code name.** §2.13 says "`upgradeDefaults()` (0.1 users, where `modulesExisted` is false)". The code has no `modulesExisted`; the selector is `ModulesConfig.firstRun(launchedBefore:)`. *Fix:* name it.
7. **Forwarding call is missing an argument.** §5.2 says the legacy `statusItemPlan(running:)` forwards with three arguments, but the new function takes five. `sharedShownAtRest` is missing. *Fix:* add `sharedShownAtRest: true`.
8. **Default check mark contradicts C10.** The §5.3 idle mockup marks "✓ For 1 Hour" as the default, but C10 and §2.14 make Until Turned Off the default, and that item isn't in Start Session ›. *Fix:* no check mark in the idle mockup.
9. **One type, two owners.** `TaskActivitySample` is labelled "Kit, J" in §2.3 but lives in G's `AwakeSession.swift` (§6.2). *Fix:* pick one owner.
10. **Gaps in the S-stub rule.** §6.3 covers §2, §4.1, §4.5, §4.8 and §5.2, but not §4.6, where `AwakeMigration` and `AwakeMigrationResult` are declared (step 0 needs the `.nothing` stub).
    - `ToastAction` is referenced in §2.5 and §6.2 but never declared.
    - `SettingsIndex*.actions` (§4.8 `ControlCatalog`) has no declaration, and K20 emits only `entries`.

    *Fix:* add §4.6 to the rule, and declare both types.
11. **Ownership not marked.**
    - `ConfigModulesTests.swift` (A) and `ConfigMenuTests.swift` (F) should move with their sources (⇢ lead, ⇢ M).
    - `Core/MenuPlacement.swift` moves to M but still titles `MenuPlacementChoice` with 0.2 wording. Mark it ✗ or move its titles to `MenuPresence`.
    - `DisplaysOnboardingStep` belongs to F, but §4.7 gives the chip changes to H.
    - `ControlMap` is "H + owners" editing one H file, which TEAMS.md's "edit only files your team owns" forbids.
    - The Awake stores are "owned" by `AwakeModule` (§2.1) and by `ModuleHost` (§2.13).

    *Fix:* name one owner each, and give contributors a per-owner table file.
12. **Pre-N10 leftover in rules.** The rule editor (§4.3) offers "Move the pointer slightly", although rules never move the pointer (N10). §2.7 `sanitized()` still downgrades `nudge` only for triggers with an idle criterion (code M8). *Fix:* offer Off and Appear active only for rules, and map every trigger `nudge` to `declare`.
13. **Missing from §6.4.** J `OtherAssertionsReader`; A's `KitControl.protectedSettings` edit (§2.10); F's switch of `OverviewController` to the Kit constants (§2.2). Also, the `build.yml` selftest-controls step (lead, §6.2) can't pass at the step-0 exit, because A adds `--selftest-controls` in step 1. *Fix:* schedule them, and land the CI step in step 1.
14. **Anachronism.** The `ControlMapLegacy.actions` comment lists "AwakeActionID raw value" as a 0.2 action, but Awake didn't exist in 0.2. *Fix:* drop it.
15. **Tests without a Kit API.** §6.6 MenuLayout tests "slider never inSubmenu; ordering; compact mode", but MenuLayout declares only `statusItemPlan`. The `MenuItemCatalog` test ("every legacy id maps to a spec with showHide") also contradicts §4.8 ("…unless its row says otherwise"; removed ids have no spec). *Fix:* name the Kit functions (or move the tests to `ConfigMenuTests`) and use the §4.8 wording. Also, `AwakeRefusal` ("so CLI exit mapping and UI copy are tested") and `AwakeLogEvent` have no §6.6 entry.
16. **Stale citations and lists.**
    - "security L6" is cited for Restore Defaults and local bundle ids (§2.14 ×2, §3.2, §4.6), but r3's security L6 row is the rejected consent row. *Fix:* cite the round ("r1 security L6").
    - TEAMS.md's contract-file list isn't updated for the files that move to the lead (ConfigModules, ModuleHost, ModuleContext, ToastPresenter). Only the ratchet exception is mentioned (§6.3).
    - `AwakeDiagnostics` (G, app) must be incremented by A's `EventLog` overload, but there is no `static let shared` under `Awake/`, and the wiring is unstated (§3.6).

## Leftover scan (removed mechanisms)

- **Keychain / consent / `AwakeConsent*` / `admit:` / L11 / HW-22:** every hit is a "withdrawn" note, except Minor 1.
- **Quick menu:** only in the §4.8 X rows, C3 and the `MenuSlot.quick` ratchet deletion. These are correct.
- **`MenuPlacementChoice`:** still correctly the legacy type (`legacyPlacement`, the M2 writes). The only stale use is `MenuPlacement.swift` (Minor 11).
- **Features page:** only 0.2 references, N8, and `FeaturesPage ✗`. Correct.
- **`whilePID`, `--parent`, `AwakeMenuBuilder`, "Own Icon When Active", "Extend 1 Hour":** gone, apart from the "replaces r2's …" note.

## Spot-checks that passed

- **r3 change tables:** every row I traced (all consistency rows, the code sig rows, R2-M1…M11, design M1–M7/m1–m14, parity B1/M1–M6/m1–m12, security H1/M1–M5/L1–L5) is reflected in its cited sections. The totals match the row counts.
- **Source keys:** the M1–M5 keys exist in code (`features`, `management.preventSleep`, `identity.fingerprint/customName/lastKnownName`, `placement`, `hideWithoutExternalDisplay`, `showNewDisplaysCard`, `menu.showPanelShortcut/identifyShortcut`, `keys.osdShowNits`, `brightness.showNits`). `DisplayActionID` raw values `f.showPanel` and `f.identify` match OverviewController.
- **`ConfigModulesTests`:** line 16 (`placement == .shared`) does fail for Awake as §2.13 says.
- **Counts and enums:** Awake menu 6/10 rows, Awake Advanced 11, Menu Bar 8 settings, sidebar 7 rows; `AwakeServiceID` matches `AwakeContext`; hotkey ids and `awake status` kinds match.
