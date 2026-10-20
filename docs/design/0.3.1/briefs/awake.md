# Brief: Awake "keep awake with the lid closed" (0.3.1), code facts

Repo /home/claude/snaptic at 7c6e57a (0.3.0, Info.plist CFBundleShortVersionString 0.3.0). Paths are relative to the repo. I only read the code; nothing was compiled.

## 1. Session model

**Options** (`Sources/SnapticKit/AwakeSession.swift`)
- `AwakeDisplayPolicy {keepOn, maySleep, keepOnWhileActive}` (:6-13). `AwakeActivityMode {off, declare, nudge}` (:15).
- `AwakeSessionOptions {display, displayIdleMinutes 1...240, activity}` (:17-55). Decoding is lossy per field (:35-40). `withoutNudge()` (:49-54) maps `.nudge` to `.declare`. That is the only "dangerous option" stripping in the codebase.
- `AwakeSession` (:450-558) has `id, kind, options, presetID, source, startedAt, startedContinuous, deadline, bootSession`. **`overrideGuards` is "One-shot Start Anyway; not in CodingKeys, never persisted (security H2)"** (:465-470). It is reset to false in `init(from:)` (:499) and in `sanitized(now:)` (:525). This is the exact precedent for a per-session runtime-only flag that never survives a restore.
- `sanitized(now:)` (:517-547) drops `.rule` sources, sessions from another boot, out-of-range kinds and expired sessions.

**Kinds**: `AwakeSessionKind {indefinite, duration(seconds), until(unixTime), whileApp(bundleID, maxSeconds?), untilIdle(spec, maxSeconds?)}` (:246-293). `isTimed`, `cap` and `isTaskBound` are defined there, and kinds map to `AwakeHistoryKind` (:282).

**Sources**: `AwakeSessionSource {menu, hotkey, settings, commandLine, launch, rule}` (:436-448). `isDirectUserAction` is true only for menu, hotkey and settings. The source is persisted and kept through restore (security L1).

**What governs**: `AwakeGoverning {inactive, manual(AwakeSession), trigger(TriggerTop), holds([AwakeHold])}` (:589-623).
- A trigger reports source `.rule`. Holds report `.commandLine` with options `AwakeSessionOptions(display: .maySleep)`, so holds have no options of their own.
- `AwakeArbiter.governing(manual:top:holds:)` decides which one governs. Holds govern only when there is no manual session and no active trigger.

**End reasons**: `AwakeEndReason` (:560-572) has these cases: user, timeUp, appQuit, processExited, tasksFinished, replaced, triggerEnded, batteryLow, adapterDisconnected, lowPowerMode, thermal, systemSleep, userSwitch, lockedTooLong, moduleStopped, safeMode, reboot, assertionFailed, commandLineOff. `isUserEnd` is true for user and replaced. The enum is CaseIterable and appears in log keys (`AwakeLogEvent.sessionEnded`) and text (`AwakeEndText`).

**Refusals**: `AwakeRefusal` (:628-675) has guardActive, unavailable, invalid, notAllowedFromCLI, uiSessionRunning, holdLimit and endedAtStart. Every refusal exits 4.

**Start rules**: `AwakeStartRules.refusal` (`Sources/SnapticKit/AwakeSessionPolicy.swift:14-37`).
- A `.rule` source returns `.invalid`.
- From the CLI, an indefinite session returns `.notAllowedFromCLI`, and a start while a direct-UI session runs returns `.uiSessionRunning`.
- `cliCapped` (:39) caps a CLI untilIdle session at 12 h.

**Presets and config**: `Sources/SnapticKit/Config/ConfigAwakeSessions.swift`
- `AwakePresetKind` (:6-97). `AwakePreset {id, name?, kind, options?}`, where nil options means "Use default" (:100-161).
- `AwakeBehavior {endOnSystemSleep=false, userSwitchEnd=.afterHour, endAfterLockedHours, keepDisplayOnWhileLocked=false, resumeAfterRestart=true, startAtLaunch}` (:166-214).
- `AwakeSessionsConfig {presets ≤12, defaultPresetID, defaultOptions, lastCustomSeconds, behavior, recentApps}` (:216-233). Six default presets (:221).

**Choosing options per session**: `effectiveOptions(for:preset:effective:)` (:307-316) returns `preset.options ?? defaultOptions`, then clamps activity to the effective features.
- A start with explicit options (CLI `--display-may-sleep`, the Custom panel) goes through `SessionController.clamped` (`Sources/Snaptic/Awake/Core/SessionController.swift:217-226`).
- `usesDefaultOptions` (SC:46) makes a running session follow later changes to the default display options (`configDidChange`, SC:1114-1123).
- Settings helpers: `settingAppearActive`, `settingPointerNudge` and `settingKeepDisplayOn` (ConfigAwakeSessions:337-361). `withoutNudge()` on the whole sessions config (:319-328) is used by restore-defaults, export and import (`ConfigAwake.swift:71,138,141`).
- Rules: `AwakeTrigger.options` is sanitized with `withoutNudge()` (`AwakeTriggers.swift:481,515-519`), and so is `TriggerTop` (`AwakeTriggerEngine.swift:283`).

**Custom… panel**: `Sources/Snaptic/Awake/UI/CustomSessionPanel.swift`.
- Kinds: duration, until, whileApp, plus the single per-session option "Keep the display on" (:37, :85-87). No return-key binding (:5-9).
- `CustomSessionWindow.start` (:187-195) builds options from `effectiveOptions` and overrides `display`. A Settings start checks `SettingsShell.shared.mayStart()` (:182-185).
- Controls table: `CustomSessionPanelControls` (`awake.custom.start`, `awake.custom.cancel`).

**Holds** (`awake hold`)
- `AwakeHold {id, binding: HoldBinding(.connection|.process pid+startTime), startedAt, startedContinuous, deadline, bootSession}`, `maxHolds = 8` (AwakeSession.swift:372-433).
- `SessionController.addHold` (SC:232-271). ProcessWatch arms a kqueue first. Every hold has a cap: 12 h by default, up to 24 h with `--max` (`AwakeClock.swift:22-26`).
- Holds have no options and stack beside the manual session.

**N10 rule set** (PLAN-r4.md:161, quoted):
> | N10 | **No consent record** (r2's Keychain record is withdrawn: forgeable under the legacy file keychain that ad-hoc builds use, and lost on every ad-hoc update). Instead: (a) **pointer movement** acts only for a session started by a direct user action in Snaptic's own UI in this process (a menu click or a Settings button; a Snaptic hotkey only after the user clicks **Allow** on the confirmation toast "Move the pointer to keep apps active?", as 0.2 R5.7 does for Gather Windows), never for CLI, trigger, restored or resumed sessions; the flag that records this (`uiStartedInProcess`) is set only by those handlers and cleared on every restore, resume, CLI or trigger takeover, session replacement and module stop (§2.3 `AwakeActivityGate`), never while the screen is locked or the session is off console, and at most `activity.stopAfterHours` (default 1 h, max 8 h) measured on Snaptic's own continuous clock, never on system idle time (Snaptic's own declarations reset idle); (b) **Drive Alive** volumes are chosen in the UI and stored by volume UUID; (c) a fixed 5% battery floor and the critical-heat end apply whatever the config says; [...] Config changes made outside Snaptic take effect like any setting; the residual same-user risk is stated in §3.2 | Lead r3/r4; security H1/M1/M2, r3 security M1–M3 |

How N10 is implemented in code:
- **Gate**: `AwakeActivityGate` (`Sources/SnapticKit/AwakeActivityGate.swift`).
  - Runtime only and not Codable (:3-4). `uiStartedInProcess` is `private(set)` (:25).
  - `Pointer {notAllowed, askOnFirstUse, asking, allowed, declined}` (:7-18).
  - The truth table is `applying(_:)` (:66-119). `uiStart` sets it, `hotkeyStart` asks first, and `otherStart`, `restore`, `resume`, `takeover`, `replaced` and `ended` all clear it.
- **Mapping in `SessionController.start`** (SC:170-175): `.menu`/`.settings` → `.uiStart`, `.hotkey` → `.hotkeyStart`, `.commandLine`/`.launch`/`.rule` → `.otherStart`. Other events:
  - restore → `.restore` (SC:460);
  - trigger or holds takeover → `.takeover` (SC:693-698);
  - replacement → `.replaced` (SC:182);
  - module stop → `.moduleStop` (SC:1160).
- **Hotkey confirmation**: `requestPointerConfirmation` shows the toast "Move the pointer to keep apps active?" with Allow / Not Now (SC:419-449).
- **Final check**: `ActivityPolicy.nudgeAllowed` (`Sources/SnapticKit/ActivityPolicy.swift:63-72`) requires a manual governing session from a direct source, plus `gate.uiStartedInProcess && pointer == .allowed`.
- **Lint L16** (`scripts/lint03.py:340-345`): only SessionController.swift may assign `activityGate`.
- **README wording**: README.md:219-221 ("only for a session you started yourself in Snaptic's menu or Settings in the running copy of Snaptic; a session started with a shortcut asks … first"; "never for command-line sessions or holds, rules, a session started when Snaptic opens, or a session restored or resumed after a restart").

## 2. SessionController lifecycle (`Sources/Snaptic/Awake/Core/SessionController.swift`)

**Start**
- Entry points: `start(...)` (:104), `startPreset` (:110), `startDefault` (:118) and the private `start` (:135-214).
- Checks in order: restored and the feature effective → `AwakeStartRules` → whileApp running → guards (`AwakeGuards.evaluate`, :150-158). If a guard blocks a UI start, it calls `offerStartAnyway`.
- Then it resolves options, maps the gate event, replaces the old manual session (`finishManual(.replaced)`) and calls `AwakeClock.start`.
- Then: session lifetime, gate update, reminders reset, the log event `sessionStarted(kind)`, the CLI notice (`announceCommandLine`, :976-981, at most once per 10 min), `watch`, `arbitrate()`.
- If the first arbitration ended the session, the call returns `.endedAtStart(reason)` (:206-210).

**Extend**: `extend(by:source:)` (:320-328) applies to the manual session only and **does not check `source`**. A CLI `awake extend` therefore lengthens a session the user started in the UI. `AwakeClock.extended` (`AwakeClock.swift:117-130`) caps the total at `maxSessionSeconds`.

**Ending**
- `turnOff(source:)` (:359-395) ends whatever governs, then shows "Rules can still…" or a holds toast. `end(_:)` (:397-404) is used by CLI `awake stop` (`AwakeAutomation.swift:192-199`).
- `finishManual` (:766-791) clears the session, resets the gate (`.ended`), logs `sessionEnded(reason)`, fires `ends` (History and holds observe it), shows the end toast (`AwakeEndText.toast`), sets `runtime.lastEnd` for interruptions, then arbitrates.
- Expiry, app quit, locked or off-console ends (`AwakeSystemPolicy.end`) and untilIdle quiet are all checked in `arbitrateOnce` (:644-720).

**Arbitration**: `arbitrate()` (:627-642, re-entrant, at most 8 rounds) builds an `AwakeArbiterInput` and plan and calls `ctx.assertions.apply` (`AssertionManager`, the only file allowed to create assertions per lint L1, `lint03.py:275-280`). It then publishes the runtime (`publish`, :722-740, which includes `lidWillSleep`), reminders, tick, verify timer, `persist` and dynamic needs.

**History**: `HistoryController` observes `observeEnds` (`HistoryController.swift:103`). `AwakeHistoryEntry {start, end, kind, source, presetID, triggerID, bundleID, endReason}` (`AwakeHistory.swift:8-18`). "Start Again" from History is a `.settings` start (`AwakeHistoryPage.swift:175-182`).

**Sleep and wake**: `systemEvent` (:851-873).
- On `.willSleep`, if a manual session runs and `behavior.endOnSystemSleep`, the session ends with `.systemSleep`.
- On `.didWake`: quiet reset, arbitrate, `verifyAssertion`.
- `.lidChanged`, screens and session events → arbitrate.
- The Advanced help text for endOnSystemSleep reads "When you choose Sleep or close the lid." (`AwakeAdvancedSheet.swift:108`).

**30-day cap**: `AwakeClock.maxSessionSeconds = 30 * 86_400` (`AwakeClock.swift:20`) and `durationRange` 60 s…30 d (:29). The same limit is enforced in start rules, `sanitized` and `extended`. The reminders (`AwakeReminders`, SessionPolicy:89) are a toast 5 minutes before the end with "Add 1 Hour", and a toast after 8 h with Turn Off / Keep Going (SC:958-973).

**Quit**
- `stop()` (:1126-1176). When `host.signals.isTerminating`, it writes a clean snapshot that **keeps the manual session if `resumeAfterRestart`** (:1143-1147).
- It then fires `.moduleStopped` ends, `assertions.releaseAll()` and the gate `.moduleStop`.
- `AwakeModule` stop (`AwakeModule.swift:110-127`) keeps the snapshot on quit and clears it on disable or Safe Mode (:122-123).
- `AppDelegate.applicationWillTerminate` (`Sources/Snaptic/Core/AppDelegate.swift:113-120`) calls `host.shutdown()`.
- SIGTERM, SIGINT and SIGHUP go to a dispatch signal source that runs `EmergencyActions.shared.runAll()` and then terminates, with exit(0) 3 s later as a fallback (AppDelegate:199-211). This is the hook point for "turn sleep back on at quit even when main is hung".

**Crash and relaunch**
- **Yes, persisted sessions are restored.** The snapshot is `AwakeRuntimeSnapshot` (`Sources/SnapticKit/AwakeSnapshot.swift:7-35`; key `ModuleHost.awakeStateKey`, `ModuleHost.swift:18,99`). It is written on every change, plus a heartbeat stop stamp (SC:1014-1057).
- `restore(_:)` (SC:457-533) runs once at module start:
  - with `resumeAfterRestart` (default **true**), the manual session from the same boot resumes with its `source` kept and the gate set to `.restore`;
  - it is dropped if a guard fails or the app quit;
  - `--pid` holds are re-armed;
  - "Start a session when Snaptic opens" starts a `.launch` session (SC:562-567).
- A lid mode therefore must not come back on restore. The `overrideGuards` pattern (excluded from CodingKeys) does this automatically.
- There is no host-side crash journal for Awake. The precedents for crash recovery are elsewhere:
  - the Displays journal `RevertJournal.recoverAtLaunch` (AppDelegate:62), run before modules start and also in Safe Mode;
  - `SystemHotkeys.recoverFromPreviousRun()` (AppDelegate:56).

## 3. Guards

**Kit logic**: `Sources/SnapticKit/AwakeGuards.swift`
- `PowerFacts {batteryPresent (latched), onAC, percent?, charging, falling, lastRecovery, lowPowerMode, thermal, unreadableStreak}`. `discharging = batteryPresent && (!onAC || falling)` (:11-31).
- `AwakeGuardsConfig {batteryFloorEnabled=true, batteryFloor 20 (5...50 step 5), endOnAdapterDisconnect, endOnLowPowerMode}`. `monotonic(over:)` lets an import only make guards stricter (:47-98).
- `hardFloorPercent = 5`, "Fixed floor (N10): not stored, not exported, no kill switch" (:201-202). Thermal cooldown is 600 s, and 2 unreadable reads confirm an unreadable battery.
- `evaluate(...)` (:217-306), in order:
  1. critical heat → `.end(.thermal)`, never overridable;
  2. below 5% while discharging → `.end(.batteryLow)`, never overridable;
  3. below the user floor while discharging → end, unless `overrideBattery`;
  4. adapter disconnect (a transition, only while active);
  5. Low Power Mode → end, unless `overrideBattery`;
  6. serious heat → `.warn` once;
  7. Low Power Mode turning on with `!endOnLowPowerMode` → `.warn`.
- `GuardMemory` (:102-193) is a hold that blocks rule starts. `backgroundBlock` (:308+) stops activity and Drive Alive.

**Start Anyway**: `SessionController.offerStartAnyway` (SC:985-1007). It appears only for UI starts and only for batteryLow or lowPowerMode above the hard floor. It is a toast with `clickGuard: .confirmation`, re-checks `mayStart()` for Settings starts, and restarts with `overrideGuards: true`. It is never offered for the CLI (`start`: `override = overrideGuards && ui`, :148-149).

**Evaluation**
- `SessionController.evaluateGuards()` (SC:591-620) runs on every power change and on GuardsController's re-check.
- `.end` → `finishManual(reason)` (with an end toast) and every hold removed. For triggers it sets `runtime.lastEnd`.
- `.warn` → `guardNotices`. `GuardsController` (`Sources/Snaptic/Awake/Core/GuardsController.swift:21-36`) shows "Your Mac is running hot. Awake ends if it gets too hot." and "Low Power Mode is on. Awake keeps running.", plus the unreadable-battery toast. It also schedules the thermal cooldown re-check (:39-50).

**How guard ends are reported**
- End toast through `AwakeEndText.toast` (SC:781-787).
- The menu and status idle line `AwakeEndText.lastEnd`/`holding` (AwakeMenuRows:271-281), kept for 12 h.
- History `endReason`.
- The log counter `awake.session.ended.<reason>`.

**PowerMonitor** (`Sources/Snaptic/Awake/Sources/PowerMonitor.swift`)
- Event sources: the IOPS run-loop source (:161-177), `NSProcessInfoPowerStateDidChange` and `thermalStateDidChangeNotification` (:44).
- `refresh()` (:83-109) reads `IOPSCopyPowerSourcesInfo` (:130-145), `isLowPowerModeEnabled` and `ProcessInfo.thermalState` (:102-103, :147).
- It re-checks every 60 s while `falling` (:113). The battery is latched for the process lifetime (:30-31).
- All of this is in-process. Nothing evaluates guards if Snaptic hangs, so the root side needs its own battery and thermal checks.

## 4. Lid handling and the menu warning

**SystemEventsMonitor** (`Sources/Snaptic/Awake/Sources/SystemEventsMonitor.swift`)
- `lidClosed: Bool?` and `lidWillSleep: Bool?`, where nil means no lid (desktop) or unreadable (:48-51).
- `readLid()` (:168-178) reads IOPMrootDomain `AppleClamshellState`, then `AppleClamshellCausesSleep` (:175-176), and publishes `runtime.lidWillSleep` (:181-184).
- Lid notifications are an IOGeneralInterest notification on IOPMrootDomain, `kIOPMMessageClamshellStateChange` → `.lidChanged` (:190-211). The lid is re-read on `.didWake` and `.lidChanged` (:150-158).
- The service `system` is always used by `.sessions` (`AwakeFeatureGraph.swift:61`), so the lid is read whenever Awake runs.
- SessionController also republishes it (SC:735-736). Runtime field: `AwakeRuntimeState.lidWillSleep` (`AwakeRuntimeState.swift:40`).

**Warning condition**: `AwakeMenuRows.lidWarning` (`Sources/Snaptic/Awake/UI/AwakeMenuRows.swift:295-303`).

```swift
guard ctx.runtime.lidWillSleep != nil else { return false }   // has a lid; the Bool VALUE is ignored
let onBattery = ctx.runtime.power.map { $0.batteryPresent && !$0.onAC } ?? false
let external = NSScreen.screens.contains { CGDisplayIsBuiltin(...) == 0 }
return onBattery || !external
```

- It is combined as `input.lidWarning = rt.governing.isActive && lidWarning(ctx)` (:269).
- The `AppleClamshellCausesSleep` value is not used. A lid session with SleepDisabled=1 would still show the warning unless this changes.
- `observe()` (:305-323) does not subscribe to `$lidWillSleep` or to screen changes. Headers refresh only on the other runtime changes.

**Text**: `AwakeDetailInput.lidWarning` (`Sources/SnapticKit/AwakePresentation.swift:226-227`).
- `AwakeDetail.extras` appends "Closing the lid will put your Mac to sleep." while active (:319).
- `AwakeDetail.lines` keeps only `maxLines = 2` (:263, :325-328): the primary line plus the first extra. The lid line appears in the menu header only when no activity, holder or other line comes before it.
- The Settings status row (`AwakeStatusText.details`, :647-662) shows all extras, plus `lidRoute` = "To keep it awake with the lid closed, connect power and an external display." (:621, :658).
- It is shown by `AwakeStatusSection` (`Sources/Snaptic/Awake/UI/AwakeStatusSection.swift:31-37`, using `AwakeMenuRows.detailInput`).
- Tests: `AwakePresentationTests.swift:95-106, 353-355`.
- Design reference: PLAN-r4.md:216 and power-apis.md:98-105. Option 3 there is exactly this feature: "`pmset -a disablesleep 1/0` through an admin prompt (`NSAppleScript` 'do shell script … with administrator privileges'), each time … write a recovery journal before flipping it …, battery floor, thermal cutoff and session-end revert, and read the state back by parsing `pmset -g`".
- Interop hazard (awake-parity.md:124): another tool's root LaunchDaemon reset SleepDisabled every 2 s, so Insomnia re-reads the value 5 s after setting it.

## 5. OtherAssertions and SleepDisabled

**Reader**: `Sources/Snaptic/Awake/Sources/OtherAssertionsReader.swift`.
- It reads only while a view shows the section (a `NeedCounter`), every 5 s (:14-15, :61-74).
- Assertions: `IOPMCopyAssertionsByProcess`, which excludes `ownPID = getpid()` (:49, :104-115; Kit `OtherAssertions.holders` skips `owner == ownPID`, `OtherAssertions.swift:88-90`).
- SleepDisabled: `CFPreferencesCopyValue("SystemPowerSettings", "com.apple.PowerManagement", kCFPreferencesAnyUser, kCFPreferencesCurrentHost)` → `OtherAssertions.sleepDisabled` (:117-123; Kit :63-67, :145-148). The header comment says "Read-only: Snaptic never writes SleepDisabled and needs no root" (:9).

**Display**: `OtherAssertionsSection` in Awake › Advanced (`Sources/Snaptic/Awake/UI/OtherAssertionsSection.swift:16-19`).
- While SleepDisabled is on it shows a warning `StatusRow`: "Sleep is turned off for this Mac by another app or command. Snaptic can't change this."
- Footer: "These keep your Mac awake on their own, whatever Awake does." (:46). Control id `awake.advanced.otherApps`.
- It is never logged or shown in diagnostics or the CLI (header comments, PLAN-r4:216).

**Implications for the new mode**
- While Snaptic's own watchdog holds SleepDisabled, this row would wrongly blame "another app" and say Snaptic "can't change this". The reader needs Snaptic's own lid state passed in.
- A leftover after a failed watchdog should still be reported, with a Snaptic-specific recovery.
- If the root side ever held an assertion (for example via `caffeinate`), its pid is not `getpid()` and it would be listed as another app.

## 6. CLI

**Grammar**: `Sources/SnapticKit/AwakeCommandGrammar.swift`.
- `AwakeCommand {status(json), start(duration?, displayMaySleep), hold(pid?, maxSeconds?), preset(selector), extend(seconds), stop, pause(seconds?)}` (:40-51).
- `parse` (:109-178) is a closed grammar. Flags are only `--json`, `--display-may-sleep`, `--pid` and `--max`. At most 16 args of at most 256 bytes. The only option expressible from the CLI is `--display-may-sleep`.
- `AwakeStatusFacts` / `statusLine` / `statusJSON` (:55-99, :187-221) report kind and display policy, with no names.

**Verbs**: `Sources/Snaptic/Awake/Core/AwakeAutomation.swift:96-135`.
- Every CLI start uses `source: .commandLine` (start :150-165, preset :167-182 via `startPreset(..., source: .commandLine)`).
- `stopVerb` calls `sessions.end(.user)` (:192-199).
- Host rules in Kit: `KitControl.swift:173-199` (`ControlVerbRule`: `awake stop` and `awake pause` offOnly; start, hold, preset and extend are rate-limited at 1/s).
- `protectedSettings` (:382-386) includes awake, nudge, pointernudge, drivealive, activity and guards. Awake settings are not settable from the CLI (README.md:379).
- Hotkeys (`AwakeAutomation.perform`, :75-92) start with source `.hotkey`. That includes preset slots 1-4, so a lid preset could be started by a hotkey.

**Control server**: `Sources/Snaptic/Core/ControlServer.swift:5-16`.
- Unix socket at `~/Library/Application Support/Snaptic/control/snaptic.sock` (directory 0700, socket 0600), peer uid checked, off by default.
- Dispatch rules are in `ControlCommandRegistry.swift:4-15`.

**Can a CLI, rule, hold, launch or restore path reach a password prompt?**
- Today nothing prompts. If lid mode were part of `AwakeSessionOptions` or a preset, it would reach `start` from:
  - `awake preset` (`.commandLine`);
  - rules (TriggerTop options);
  - start-at-launch (`.launch`);
  - restore;
  - hotkey preset slots;
  - History "Start Again" (`.settings`).
- Gate it like N10:
  - allowed only for `.menu`/`.settings` (with `mayStart()`), and a hotkey only after a confirmation;
  - stripped like `withoutNudge()` in rules, export/import and CLI paths;
  - excluded from CodingKeys like `overrideGuards`.
- CLI `awake extend` (no source check, SC:320) and `awake stop` would extend or end a lid session. "Other apps can only turn it off" means `extend` must be refused for lid sessions.
- PLAN-r4 §3.1 (:1746) justifies CLI starts with "starting an Awake session grants nothing new (`caffeinate`)". That argument does not hold for a root SleepDisabled.

## 7. Settings pages, sheets, control registry, and the Kit/app split

**Pages and sheets**
- `AwakePage.swift` hosts `CustomSessionWindow(source: .settings)` (:13). Its controls are in `AwakePageControls` (`awake.page.*`: status.keepAwake, options, turnOff, defaultSession, keepDisplayOn, sessions, batteryLow, batteryFloor, adapter, rules, shortcuts, advanced …).
- `AwakeAdvancedSheet.swift` has sections activity, end, display-while-locked, restart, and `OtherAssertionsSection` (:23-34). Table `AwakeAdvancedSheetControls`: appearActive, pointerNudge, stopAfter, endOnSleep, userSwitch, lowPowerMode, endAfterLocked, keepDisplayOnWhileLocked, resumeAfterRestart, startAtLaunch, otherApps, restore (`Sources/SnapticKit/Controls/AwakeAdvancedSheetControls.swift:15-64`).
  - `pointerNudge` uses `when: awake + [.parentOn(appearActive)]`. This is the pattern for an experimental child setting.
- `PresetEditorSheetControls` (`awake.sessions.*`: list, add, name, kind, duration, untilTime, atMost, thresholds, display, activity `when: preset + [.awakeFeature(.activity)]`, restore).
- `CustomSessionPanelControls` (start, cancel).
- `AwakeMenuRowsControls` (`menu.awake.*`, 26 ids).

**Rules a new setting must satisfy**
- Every control id is a literal in its table, the table is listed in `ControlRegistry.tables`, and every declared id is used (lint L15, `lint03.py:772-807`).
- Each `.setting` needs a `SearchSpec` (`ControlRegistryTests.swift:134-144`).
- Each persisted config leaf must be named by some control's `keys:` or `ControlLegacy.internalKeys`. `ConfigFixtures.fullAwake()` must fill it (`testKeyCrossCheck`, :178-193).
- **Feature flags**: `AwakeFeature` (`AwakeFeatureGraph.swift:6-9`). The specs (:61-73) use levels `.always`, `.optIn`, `.standard`, `.experimental` (pointerNudge is `.experimental` and needs Accessibility). A new feature automatically gets an `Awake.disable.<feature>` kill switch (N14, README.md:442-452), which admins could use to forbid the mode. The unkillable set is `[.sessions, .batteryGuard, .thermalGuard]`.

**Kit vs app split**
- SnapticKit must be Foundation-only and Linux-compatible (`scripts/lint.sh:40-44` bans AppKit, CoreGraphics, IOKit, os and more). Every Kit declaration must be `package` (:46-50).
- Kit tests are in `Tests/SnapticKitTests` and run with `swift test` on Linux.
- New pure logic belongs in Kit, following `AwakeStartRules`, `AwakeActivityGate` and `AwakeGuards`. Examples:
  - a lid-mode eligibility table per source;
  - a gate truth table;
  - root-side threshold constants;
  - the fixed watchdog script text (if it is a constant with no interpolation of user data);
  - status and diagnostics formatting;
  - `AwakeEndReason` / `AwakeLogEvent` cases.
- Every new file needs a row in `scripts/stubs.tsv` (lint rule 6, `lint.sh:57-82`; format `path owner kind type extra`).
- Rule 4 (`lint.sh:111-139`): extensions of types declared in another file must be fileprivate.

## 8. Process spawning, signing, lint, and claims this feature contradicts

**Existing spawning**
- Only `Sources/Snaptic/Core/HelperSpawner.swift` (Swift) and `Sources/SnapticShims/SNSpawn.m` (`posix_spawn`, suspended, disclaim, own process group, :130-214) may spawn. Enforced by lint rule 12 (`scripts/lint.sh:148-152`; regex `\bProcess\(|NSTask|posix_spawn|\bpopen\(|[^.]\bsystem\(|\bfork\(|execv`).
- **`NSAppleScript` and `NSUserScriptTask` are not in the regex**, although PLAN-r4.md:1784 says rule 12 bans them. A plain `NSAppleScript` call would pass lint today.
- `HelperKind {displayGuard, virtualHost, hook, selftestChild}` (HelperSpawner:7-19).
  - `spawn` (:175-…) runs only Snaptic's own executable (`modeFlag`). It verifies the child's code identity against Snaptic's requirement while the child is suspended, and the child gets `--parent <pid>`.
  - `spawnHook` (:309-379) runs a user executable after `checkExecutable` and `KitHookPolicy` checks (absolute path, owned by the user or root, not writable by others, never Snaptic's own code, at most 8 arguments). It sends SIGTERM and then SIGKILL to the group after 30 s (`KitHookPolicy.timeoutSeconds`, :366-375). That makes it unsuitable as-is for a long-lived osascript.
  - Running `/usr/bin/osascript` therefore needs a new kind or path in HelperSpawner. It is the only allowed file.
- **Watchdog precedent**: DisplayGuard (`Sources/Snaptic/Displays/Safety/DisplayGuardClient.swift:5-9`, `DisplayGuardMain.swift:8-30`). Its design:
  - a separate process, with JSON lines over pipes;
  - the parent heartbeat carries `HostHeartbeat.mainAgeMillis()` (hang detection);
  - **EOF on the pipe = parent died** → revert;
  - constants in `Sources/SnapticKit/GuardProtocol.swift:52-66` (hangSeconds 10, staleHeartbeatSeconds 3, killParentAfterSeconds 30).
  - Spawned children are disclaimed (`options: [.disclaim]`). An osascript child would then be its own responsible process for TCC and the auth dialog. Behavior under hardened runtime is unverified.
- Hooks (`Displays/Automation/SpawnerService.swift`) are the only user-program runner.
- `power-apis.md:286` shows a `Process` example (`pmset displaysleepnow`) in docs only.

**Signing**
- No `.entitlements` file exists. `Resources/` holds only `Info.plist` (no `NSAppleEventsUsageDescription`; LSUIElement).
- `scripts/build-app.sh:35-45` signs with `codesign --options runtime` ("Never add entitlements that weaken it") and refuses an unsigned runtime.
- `INSTALL=1` installs root-owned via sudo (:47-57). Package links `Security` (`Package.swift:23`).

**Lints touching this feature**
- L4 bans the string literals `"pmset"` and `"sudo"` anywhere in Sources (`scripts/lint03.py:288-289`). There is no ratchet row for L4 (`scripts/lint-legacy.tsv`), so one occurrence fails. `"/usr/bin/pmset"` inside a script string is not matched.
- L1 restricts assertion creation to AssertionManager.
- The network ban (lint.sh:32).
- Rule 9 forbids TCC APIs in helpers.
- Rule 12 bans spawning outside HelperSpawner and SNSpawn.
- No lint mentions "root" or "osascript".

**Claims the feature contradicts**

| File:line | Claim |
|---|---|
| README.md:19 | Awake "needs no administrator password" |
| README.md:155 | "It needs no administrator password, installs nothing, and leaves nothing behind: if Snaptic quits or crashes, macOS releases the assertion…" |
| README.md:252 | "Snaptic can't and won't change that setting" (SleepDisabled) |
| README.md:254-258 | Section "Why not with the lid closed on battery?": "can't … by design. macOS allows that only with root…" |
| README.md:273 | Parity table: "Closed-display mode on battery, Power Protect — Not offered" |
| README.md:275 | "SleepDisabled … Snaptic never touches"; "Snaptic never runs them" |
| README.md:610-611 | "What it can't be made to do: run a program (Awake spawns nothing…)"; "command line grants nothing new" |
| README.md:639 | Troubleshooting: "Closing the lid … always sleep a Mac" |
| README.md:652 | Known limitations: "A MacBook with its lid closed on battery sleeps … (by design)" |
| README.md:686 | Not included: "keeping a closed laptop awake on battery (`pmset disablesleep`…); a privileged helper, admin prompts…" |
| README.md:707 | "No root, nothing left behind. No `pmset`, no `caffeinate` process, no helper…" |
| README.md:718 | Awake reads SleepDisabled "and only reads" it |
| README.md:666 | HW test list (update for the new mode) |
| README.md:589 | "Helpers" only lists the safety helper and virtual-display hosts |
| site/index.html:401 | "a keep-awake switch that needs no password" |
| site/index.html:600 | "No administrator password, nothing installed, and nothing left behind if Snaptic quits." |
| site/index.html:637 | "Lid closed? Connect power and a display… No root tricks." |
| docs/design/0.3/RELEASE-NOTES-0.3.md:3 | "without an administrator password" |
| docs/design/0.3/RELEASE-NOTES-0.3.md:44 | "Awake can't keep a MacBook awake with its lid closed on battery, by design (it would need root)" |
| PLAN-r4.md:255-256 | Excluded: "Closed-lid on battery (`pmset disablesleep`…)"; "Privileged helper, root, admin prompts" |
| PLAN-r4.md:266 | "spawning is banned outside HelperSpawner" |
| PLAN-r4.md:248 | "Snaptic never runs commands (rule 12)" |
| PLAN-r4.md:1746 | §3.1 "grants nothing new" |
| PLAN-r4.md:1784 | §3.5 "Awake spawns nothing … no AppleScript" |
| power-apis.md:3 | "no root, no privileged helper" |
| awake-parity.md:187 | Exclusion rationale |
| OtherAssertionsReader.swift:9 | "Snaptic never writes SleepDisabled and needs no root" |
| OtherAssertions.swift:6 | "Read-only: Snaptic never writes SleepDisabled" |
| OtherAssertionsSection.swift:17 | "…by another app or command. Snaptic can't change this." |
| AwakePresentation.swift:319, :621 | Lid line and `lidRoute` copy |

The `review-r*-security.md` files contain no lid-specific findings (grep for lid, root, disablesleep and sudoers found none). The relevant security precedent is review-r3-security.md:100 ("No outside route to a UI start: no URL scheme, sdef, Services or Apple Event handlers… Synthetic input and AXPress need Accessibility").

## 9. Diagnostics, backup, About, and status reporting

**Diagnostics**: `Sources/Snaptic/Awake/Core/AwakeDiagnostics.swift:17-40` builds `AwakeDiagnosticsFacts` (`AwakePresentation.swift:472-509`). `AwakeDiagnosticsReport.lines` (:511-532) prints: Awake features, kill switches, governing (kind), assertion (errors), guard, services, holds, rules, drives and event counts. It contains no names or times. A lid-mode line (state, watchdog alive, SleepDisabled seen) belongs here.

**About**: `Sources/Snaptic/Core/AboutPage.swift:91-102` embeds `host.awake.diagnosticsLines()` in the shared report.

**Event log**: `AwakeLogEvent` is a closed enum (`Sources/SnapticKit/AwakeLogEvent.swift:8-40`). Counted cases produce keys like `awake.session.started.<kind>` and `awake.session.ended.<reason>`. Ring cases are errors only. New cases need fixed text, with no payload. PLAN-r4 §3.6.

**Backup**
- `Sources/Snaptic/Core/Backup.swift:9-48, 141-143` uses `AwakeConfig.exportable(includeTriggers:)` and `importable(current:)` (`ConfigAwake.swift:78-112`).
- `strippedForBackup` (:132-142) removes pointerNudge, drives, recentApps and startAtLaunch, and applies `withoutNudge()`.
- Any persisted lid flag (in presets or defaultOptions) must be stripped the same way, and the import must keep the current Mac's value, as is done for `features[.pointerNudge]` (:107).

**Other places that report Awake state**
- CLI `awake status` (`AwakeStatusFacts`, kind and display only).
- Menu header and status row (`AwakeDetail`, `AwakeStatusText`).
- History entries (`AwakeHistoryEntry` has no options field).
- The indicator, and VoiceOver "Awake turned off." (SC:707-712).
- The assertion name "Snaptic: keeping your Mac awake" with details `manual`/`automatic` (README.md:583, 705).
