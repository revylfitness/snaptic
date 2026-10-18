# PLAN 0.3 r1: adversarial review (code, architecture, buildability)

Checked against `feature/displays`. Counts: **3 Blocker, 14 Major, 14 Minor**.

## Blockers

**B1. The step-0 exit "lint L1–L9 green" can't be met (§6.3, §6.4).** Existing code already breaks the new rules, and it is only removed in steps 2–3:
- L1: `PowerController.swift:300,314` (D).
- L5: 54 `Slider(`/`Stepper(`, 125 `.font(.caption)`.
- L6: 18 `NSMenuItem(`, including files no team is told to migrate: `AppDelegate.swift:218-246` (the app's main menu, which Settings text fields need for Edit), `PIPWindow.swift:270,280`, `WindowSwitcherModule.swift:121`.
- L7: 4 `objectWillChange.send()` and 7 `State(initialValue:`.

Fix: a ratchet file, `scripts/lint-legacy.tsv` (rule ⇥ path). Lint fails on any violation that isn't listed, and also on a listed entry that is now clean. Permanent rows: AppDelegate main menu, PIPWindow context menu, ArrangementCanvas (L5), and ActivitySimulator for `IOPMAssertionRelease` (M8). The step-3 exit criterion becomes "only permanent rows left".

**B2. Removing `sleepPrevention` in step 0 breaks 11 files owned by other teams (§6.2 vs §6.4 step 3).** Removing `DisplayFeature.sleepPrevention` and `DisplaysRuntimeState.sleepPreventionActive` breaks:
- `PowerController`, `ArrangementPage`, `ConfigManagement`, `ManagementIDs` (D)
- `DisplaysUIModel`, `DiagnosticsController`, `DisplayMenuBlock` (F)
- `KitBackup`, `KitBackupTests`, `KitControlTests` (A)

Fix: keep the enum case, its spec and the runtime property until step 3. D and F remove them in one coordinated merge together with the lead's lines. M1 reads the raw JSON either way.

**B3. Nobody owns the Awake status item: StatusMenu and IndicatorController would each build one (§2.11, §5.3, C2).** `StatusMenu.applyPlan` creates a `squareLength` slot with its own menu for every module in `StatusItemPlan.ownIcon`. With `ownItem = true`, M's StatusMenu builds one Awake item and G's IndicatorController builds a second. `hasVisibleItem` (relaunch → Settings) and `everythingHidden` never see G's item, and the "statusItems" host service in `AwakeContext` has no definition. Fix (lead contract, step 0):
```swift
@MainActor protocol StatusItemProvider: AnyObject {          // AwakeModule adopts
    var statusItem: NSStatusItem? { get }
    func presenceDidChange(_ p: MenuPresence)                  // called from StatusMenu.applyPlan
}
```
Add `StatusItemPlan.custom: [ModuleID]`. StatusMenu skips slots for those modules but counts their `statusItem` in `hasVisibleItem` and `everythingHidden`.

## Major

**M1. The assertion timeout is relative, inside an Equatable plan (§2.4).**
- `timeoutSeconds = ceil(remaining)+15` changes on every tick (1 Hz with seconds shown) and on every arbitration (sources run every 5–10 s). Each change sends a SetProperty call, breaking "plan stable when nothing changes", and HW-2 is still unknown.
- Fix: carry `deadline: Double?`, an absolute continuous-clock instant. Convert it to `TimeoutSeconds` only at create. When the deadline moves by more than 5 s (extend, a clock change for an Until session), re-arm by **swapping** (create, then release): no gap and no HW-2 dependency.
- `verify()`: use `IOPMAssertionCopyProperties(id) == nil`. If the assertion vanished, re-create it once and end the session only if that fails.
- `.assertionFailed` on a trigger session needs a guard-style hold with backoff. Otherwise `step` re-activates the trigger, the create fails again, and the loop repeats with a toast each time.

**M2. Trigger hysteresis uses wall time and is persisted (§2.7, §2.14).**
- `trueSince` and `falseSince` stall or fire early when the clock changes.
- Because they change every step, `SnapticAwakeStateV1` gets a defaults write every 5–10 s.
- Fix: keep hysteresis on the continuous clock, in memory only. Persist only the suppressions and `pausedUntil`.
- `pausedUntil` is currently in three places: §2.7 config, §2.5 state, and missing from the §2.14 struct. Put it in the snapshot only: it is runtime state, not exported or backed up.

**M3. M4–M6 aren't idempotent, and the downgrade claim is false (§4.6).** Struct Codable drops any field it no longer declares; only `LossyMap` keeps unknown keys.
- M5: `showNits` defaults to **true**, so `showNits || osdShowNits` is always true. The merge also re-runs on every decode, so a user's "off" comes back at the next launch.
- M4: an unbound `keys.shortcuts[showPanel]` is refilled from the retained legacy field.
- M6: the same problem with `panicHotkeyEnabled`.

Fix:
- Add `DisplaysConfig.migrations: [String]`, a lossy marker list: each migration runs once, then records its id. Legacy fields stay stored **and encoded** until 0.4.
- M2: keep writing `placement` derived from `presence`, so 0.2 still reads it.
- M3: decode `newModuleCards` as `[String]` and filter, since `Set<ModuleID>` fails as a whole on one unknown id.
- M1: call `save(force:true)` on both stores after it runs, and split more than 8 displays across triggers (`maxCriteria = 8`).

**M4. Upgraders get Awake on (C7 violated).** `ModulesConfig.defaultPreferences` returns `enabled: true` for any missing id, and `upgradeDefaults()` lists only the switcher and Displays. Every 0.2 user would start Awake with its status item. Fix (lead, step 0, tested): in `ModuleHost.init`, when `modulesExisted && modules[.awake] == nil`, insert Awake as disabled before M1 runs. Make defaults per id and update `ConfigModulesTests:15,34`.

**M5. `protectedChanges` only catches live external changes (§3.2).** `onExternalChange` fires only while Snaptic runs. A `defaults write` made while Snaptic is quit, or while the Awake module is stopped (if the module installs the hook), loads `pointerNudge` and Drive Alive volumes unchecked. Fix:
- ModuleHost installs the hook at store creation.
- At load, check the protected fields against an HMAC record keyed by a Keychain item (code-signature ACL), rewritten by the UI whenever the user changes them. A mismatch reverts the fields and shows the toast.
- If the Keychain is out of scope, weaken the §3.2 claim instead.

**M6. Notifications that arrive off the main thread will trap in `assumeIsolated` (§2.8).**
- `ProcessInfo.thermalStateDidChangeNotification` and `NSProcessInfoPowerStateDidChange` (Low Power Mode) post on arbitrary queues. Rule: every observer in Awake passes `queue: .main`, and lint flags `queue: nil` under `Awake/`.
- `TimeZone.current` and `Calendar.current` are cached. On a time-zone change, call `NSTimeZone.resetSystemTimeZone()` and use `Calendar.autoupdatingCurrent`.

**M7. Source fan-out and dynamic needs are under-specified (§2.1, §2.8).**
- `CriterionSource.onChange` has a single slot, but PowerMonitor (Guards and Triggers), SystemEventsMonitor (four consumers) and IdleSampler (arbiter and Activity) each need several. Fix: a multicast `observe(_ lifetime: Lifetime, _ h: @escaping @MainActor () -> Void)`.
- `requiredServices(…needsApps:)` can't express "idle is needed for `keepOnWhileActive`". Replace it with `dynamic: AwakeDynamicNeeds` (an OptionSet of `apps` and `idle`).
- Define one synchronous `SessionController.arbitrate()` that reads the cached trigger `top`, and coalesce only `step`. Otherwise §2.5 ("no gap, same turn") contradicts §2.7 ("one run per turn").

**M8. Snaptic's own activity feeds back into its idle readings (§2.9).**
- IdleSampler reads `.combinedSessionState`, which counts Snaptic's own nudges. As a result `keepOnWhileActive` with `nudge` never lets the display sleep, and an `idle ≥ N` trigger that uses nudge oscillates.
- Fix: post nudges from `CGEventSource(stateID: .privateState)` and measure user idle with `.hidSystemState`. Make `sanitized()` reject nudge on idle triggers.
- The `IOPMAssertionDeclareUserActivity` id must be released when activity stops, but L1 forbids that outside AssertionManager. Allow it in ActivitySimulator.

**M9. `stop()` can't tell quit from disable (§2.5).** Keeping the snapshot when quitting and clearing it when disabling needs a reason.
- Add `HostSignals.isTerminating`, set in `shutdown()` before any module stops.
- `resetAllSettings` leaves it false and clears the stores.
- "Start at launch" needs a per-process flag.

**M10. Deletions in parallel steps break other teams' builds (§5.1, §6.2).**
- `MenuSliderItem` is used by `ModuleHost` (lead), C's menu items and D's ResolutionMenuItems.
- `ClosureMenuItem` is used by A (AppDelegate, WindowSwitcherModule, AutomationController) and C.
- `ManagedMenuItem` is in 9 D files; `CMenu` in 8 C files.
- M4 (lead) reads the `MenuConfig` fields that M removes.
- Removing `MenuSlot.quick` breaks every contributor.

Rule: owners delete something only at the step-3 exit, after a grep shows no callers, and track it in the B1 ratchet until then.

**M11. Kit formatting will give different results on Linux and macOS.** `AwakeCountdown` end times, `SliderMath` parse/format ("1,5 s", "70 %"), search folding and DST handling in `untilTime` would be the first Kit code that relies on ICU. Kit tests run on both corelibs 5.10 and macOS, which disagree (U+202F before "PM", percent rules). Fix: Kit formats by hand from explicit inputs (`uses24Hour`, `decimalSeparator`, `TimeZone`) that the app derives once. Tests pin time zones and never compare against Foundation formatter output.

**M12. The live-update architecture still re-renders whole pages (§4.5).**
- `ControllerRevisions` is a single `@Published` dictionary, so any bump invalidates every observer.
- `DisplaysPageEnvironment` (DisplaysRuntimeState.swift:96–97) forwards config and runtime `objectWillChange`, so each 15 Hz commit re-renders the whole Displays tree.
- There is no UI → hardware contract for `.live` sliders.

Fix:
```swift
func token(_ id: DisplayControllerID) -> ControllerRevision   // one ObservableObject per id
@MainActor protocol DisplayLiveControlling {                    // latest-wins mailbox, DDC ≤ 20 Hz
    func set(_ c: LiveControl, _ v: Double, for: DisplayKey, phase: DragPhase) }
```
- Split `perDisplay` into per-subsection `DisplaysConfigSection` values.
- Give `observedSections` a protocol-extension default, or about 21 conformers break at step 0.

**M13. The contract signatures won't compile as written.**
- `ThermalLevel: Int, Comparable`: SE-0266 doesn't synthesize `Comparable` for raw-value enums. Write `<` by hand, as `FingerprintTier` already does.
- `WeekdaySet` needs an explicit `package init(rawValue:)`.
- `AwakeSessionKind`, `AwakePresetKind`, `AwakeCriterion` and `GuardMemory` sit inside Codable types but aren't Codable.
- `AwakeRuntimeSnapshot` and `AwakeHistory` must conform to `ConfigModel` to fit `ConfigStore`.
- `VolumeUUIDKey` and `ActivityInputs` are never defined.
- `SettingsRoot: Hashable` has a closure property: write `==` and `hash` by hand.
- `PickerOption` needs an `id`.
- `ReorderableList`'s `row` closure must be `@escaping`.
- `step` must return `nextDeadline`.
- `AwakeRefusal` belongs in Kit.

**M14. The step-0 scope assumes types that don't exist yet.** `protectedChanges` and `restoringDefaults` need G's and J's fields, which arrive in step 1; move them to G in step 2. `gen-stubs.py` has no kinds for Awake services, sources, controllers or SettingsUI views; add those kinds before writing about 110 stubs.

## Minor

1. **Clock.** `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)` is correct: it equals `mach_continuous_time`, counts sleep, and is system-wide per boot, so it is safe to persist with `bootsessionuuid`. Avoid `ContinuousClock`: its `Instant` is opaque and can't be persisted. `Timer` doesn't count sleep, so keep the wake checks.
2. **Duration display.** Show the end time as `wall + remaining`; the stored `endsAt` goes stale after a clock change.
3. **Settings navigation.** Use `NavigationStack(path:).id(root.id)` with one path per root. A search result sets the root and pushes on the next turn; macOS 14 drops a push made in the same transaction. Each page needs a scaffold that owns its `ScrollViewReader`, because the anchor modifier can't scroll. Inside sheets, highlight only after presentation. Use an `@AppStorage` key without dots.
4. **Menu rows.** Build `switchHeader` and `detail` from AppKit (`NSSwitch`), not `NSHostingView` (HW-15).
5. **Awake item visibility.** Ignore `isVisible` KVO during Snaptic's own changes and teardown. Set `isVisible = true` when the item is re-created, because the autosave name restores `false` after a removal.
6. **CoreAudio.** Store each listener as a typed `AudioObjectPropertyListenerBlock` so Remove gets the same block, and capture `[weak self]`. Move the listener when the default device changes. HAL calls can block the main thread for more than 50 ms.
7. **Network counters.** `if_data` counters are 32-bit and wrap within seconds at multi-gigabit speeds. Use `NET_RT_IFLIST2` with `if_data64`.
8. **Display matching.** Add a Kit `Fingerprint.matches(_:_:)` (owner B). `match` needs a DisplayKey map, which Awake's records don't have.
9. **Feature enabling.** `AwakeFeatureGraph.enabling` lacks the `available:` parameter, so it can turn on killed or unavailable features.
10. **Schedules across DST.** `nextScheduleChange` uses minute arithmetic and is off by an hour across DST. Use `Calendar.nextDate`, or cap the Ticker at 15 min.
11. **Naming.** `.none` cases and statics trigger "assuming Optional.none" warnings. Rename them `.inactive`.
12. **Ownership collisions.** `SettingsShell` is assigned to the lead in §4.1 and to H in §6.2. `SettingsTint` and `FeatureHighlight` are referenced from the lead's contract; move them into `ModuleContracts`.
13. **Lint and imports.** L3 duplicates lint rule 12. Extend the `static let shared` and `passUnretained` rules to `Awake/`. L8's literal scan is brittle; test the Kit index instead. `notify_register_dispatch` needs `import notify`; `HOST_CPU_LOAD_INFO_COUNT` isn't imported.
14. **Small runtime gaps.** Persist the "Start Anyway" override with the session. Drive Alive's first `open()` blocks its queue while the TCC prompt is up; coalesce the queued writes. The `module disable` help text omits Awake.
