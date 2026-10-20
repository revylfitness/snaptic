# PLAN 0.3.1 r1: adversarial review, code and platform feasibility

Checked against `feature/v031` (read-only). No compiler; code, lint scripts and the briefs were read, and three platform facts were checked on the web (cited inline). Counts: **2 Blockers, 9 Majors, 14 Minors**.

---

## Blockers

### B1. The root command line can't work as written: `"$SCRIPT"` has no source, and the quoting covers only one of the two layers (B3.1, B5)

**Evidence**
- B3.1 runs `/usr/bin/nohup /bin/sh -c "$SCRIPT" snaptic-lid <args> … &` inside `do shell script`. Nothing defines `SCRIPT` in the root shell.
  - `SNSpawn` gives osascript an **empty environment** (`SNSpawn.m:66`, `environment:@[]`), so `SCRIPT` can't come from Snaptic's environment.
  - Whether `do shell script … with administrator privileges` passes osascript's environment through to the root shell is undocumented (research §4 [U]).
- B5 `appleScript(args:prompt:)` escapes only `\` and `"` for AppleScript. The script body would have to be embedded **as a shell word** inside the `do shell script` string, and that needs shell quoting first:
  - the body contains `'` in seven places (`trap ''`, the awk programs, `'%s'`, `'s/…/p'`), plus `$`, `"` and newlines;
  - AppleScript string escaping is then a second layer on top.
- B5's test "`appleScript` output contains each argument exactly once, only after `sh -c "$SCRIPT"`" encodes the broken design. T-lid-kit would build and golden-test it as written.

**Why it matters:** Part B's core mechanism doesn't run. T-lid-kit owns this in parallel from Step 0 signatures, so the error would only show on hardware (HW-38).

**Fix (plan text, B3.1 and B5):**
- "`LidWatchdog.command(args)` builds the root command line as `/usr/bin/nohup /bin/sh -c <Q(script)> snaptic-lid <Q(uid)> <Q(pid)> <Q(tok)> <Q(cap)> <Q(floor)> <Q(dir)> </dev/null >/dev/null 2>&1 & echo $!`."
  - `Q` is POSIX single-quoting: wrap the text in `'…'` and replace each `'` with `'\''`.
- "`appleScript` wraps that with AppleScript escaping: `\` → `\\`, `"` → `\"`, LF → `\n`. It refuses CR and every other control character. Nothing reads the environment."
- Tests:
  - `sh`-unquote(AppleScript-unescape(output)) == the intended argv (a tiny POSIX-quote parser in the test);
  - the golden script text;
  - a fuzz test that no argument outside the allowed charset validates.
- Optional: drop the `'`s from the script so `Q` is trivial. Use `trap - HUP`-style forms and awk programs in double quotes with escaped `$`. That isn't required once `Q` exists.

### B2. The watchdog has exit paths that leave `SleepDisabled = 1` and drop every root-side protection (B3.1)

**Evidence**
- **Arithmetic expansion error.** `[ $((NOW-$(stat -f %m "$DIR/beat-$TOK"))) -le 20 ]` runs after `owned "$DIR/beat-$TOK"`. If the beacon disappears between those two lines, `stat` prints nothing and the expression is `$((NOW-))`.
  - B3.1 calls deleting the beacon a safe stop path. The app also removes files around stop time.
  - Bash in POSIX mode (what `/bin/sh` runs on macOS): "Non-interactive shells exit if a syntax error in an arithmetic expansion results in an invalid expression" (bash POSIX notes, item 12: https://gitea.psi.ch/pmodules/bash/src/tag/bash-3.1-alpha/POSIX). dash and zsh-as-sh exit too.
  - The shell exits with no `TERM` trap and no restore.
- **`sd()` turns "unreadable" into 0.** `awk '… END{if(!f) print 0}'` prints 0 when `pmset -g` fails, times out or changes format. In the loop, `[ "$(sd)" = 1 ] || exit 0` ("someone reset it") then exits **without restoring**, and `restore()` skips the write for the same reason (`[ "$(sd)" = 1 ] && pmset …`).
  - If the line ever appears twice, `sd` prints `1\n1`, and every comparison fails the same way.
- **Nothing on the app side notices that the watchdog is gone.**
  - B3.2 polls `SleepDisabled` only at start (+5 s) and at turn-off.
  - The app keeps touching a beacon nobody reads. Sleep stays disabled until the session or cap ends, and it has no root battery floor or heat cutoff. That is the bag-on-battery case the design exists to prevent.

**Fix (plan text, B3.1):**
- Install `trap restore EXIT TERM INT` immediately after `pmset -a disablesleep 1`. On the deliberate "not ours anymore" path, run `trap - EXIT` before `exit 0`.
- Read the beacon's mtime defensively:
  - `M=$(stat -f %m "$DIR/beat-$TOK" 2>/dev/null) || restore`
  - `case $M in ''|*[!0-9]*) restore;; esac`
  - `[ $((NOW-M)) -le 20 ] || restore`
- Make `sd` three-valued: print `1`, `0` (line absent with `pmset` exit 0), or `?` (`pmset` failed). Take the **last** match: `awk '$1=="SleepDisabled"{v=$2} END{print (v==""?0:v)}'`.
  - In the loop: `?` twice in a row → restore. `0` → exit only after **two consecutive** 0 reads, 1 s apart.
- `restore`:
  - write `pmset -a disablesleep 0` unless `sd` reads exactly `0`;
  - retry up to 3 times with a 1 s pause, and verify each time.
- The app checks liveness every heartbeat:
  - The command prints the watchdog pid (`echo $!`, B1). osascript returns it on stdout (M3).
  - On each heartbeat the app calls `kill(pid, 0)`: `EPERM` or 0 means alive; `ESRCH` means gone. It compares `proc_pidinfo` start time to rule out pid reuse.
  - On each heartbeat it also reads the IORegistry `SleepDisabled`.
  - Watchdog gone or `SleepDisabled` 0 → end lid-closed mode at once. If sleep is still disabled, show the B3.3 "Sleep is still turned off… Turn Sleep Back On…" row.
- Add to HW-38: "delete the beacon in a tight loop while the watchdog runs; `pmset -g` must read 0 within 10 s".

---

## Major

### M1. A 24-hour cap makes the watchdog exit at validation (B1, B3.1, B3.2)

**Evidence**
- B1 allows `capHours` 1–24. B3.2 sets the watchdog cap to "the same value plus 60 s", so 24 h becomes 86 460 s.
- The script requires `[ "$CAP" -le 86400 ] || exit 64`.
- The watchdog is backgrounded, so the 64 is invisible (m10). The app sees only "Couldn't turn on lid-closed mode." at the 10 s verify.

**Fix:** pass the user cap in seconds (3 600…86 400) and add the 60 s inside the script (`CAP=$((CAP+60))` after validation). `Arguments.validated` and the script must use the same ranges, and a test must cover cap = 24 h.

### M2. `turnOn` has no state machine: re-entrancy and the late-password race (B3 steps 1–6, B3.2)

**Evidence**
- `turnOn` is `@MainActor` and waits up to 120 s for osascript. During that wait other main-actor work runs:
  - the session ends, is replaced or extended;
  - Allow Sleep, the module stops, Safe Mode, a guard end;
  - a second "Keep Awake with Lid Closed…" click from the menu, the Custom… panel or the Awake page.
- The plan defines no states, no single-flight rule and no generation check after the await.
- **Late password.** If the user authenticates at 119.9 s, the app SIGTERMs osascript at 120 s and reports "not turned on", while the root shell is already starting.
  - The cancel and timeout paths (step 4) don't write the stop file. Only the verify-failure path (step 5) does.
  - The beacon and journal are then cleaned or left inconsistently.
  - SIGTERM to osascript's group can't reach root children anyway.
- The plan's `kill -0` / beacon cover doesn't help if the app keeps the beacon fresh for its next session with the same directory.

**Fix (new B3.0 "States"):**
- States: `off → preparing(token) → authorizing(token, handle) → verifying(token, pid) → on(token, pid, until) → stopping(token) → off`, plus `failed`.
- One operation at a time. While not `off` or `on`, every entry point is disabled and shows "Waiting for Password…".
- After every await, compare the token. If the session is gone or the state changed, write `stop-<token>` and go to `stopping`.
- **Every** exit from `authorizing` other than "on" does the following:
  - write `stop-<token>`;
  - stop touching `beat-<token>`;
  - keep the journal until IORegistry `SleepDisabled` reads 0 or 30 s pass. If it doesn't, show the leftover row.
- The 120 s timeout sends SIGTERM to **osascript's pid only**; don't use `signalGroup`.

### M3. osascript's result can't be read through the existing spawner: Cancel looks like failure, and the wait pattern is unspecified (B1 "Cancel … no error toast", B3 step 4)

**Evidence**
- osascript reports a script error, including −128 "User canceled.", by printing to stderr and exiting 1; the −128 number is not the exit status. B3 step 4's "nonzero exit (including −128)" can't tell Cancel from a failed authorization or a broken script.
  - `SNSpawn` always sends fd 2 to `/dev/null` (`SNSpawn.m:201`).
  - `spawnHook` passes `stdoutFD: -1` (`HelperSpawner.swift:331`).
  - So neither stream is readable, and the watchdog pid from `echo $!` (B2) is lost too.
- "Waits … on a background queue" invites a blocking wait. `waitUntilExit` and `waitpid(-1` are banned (lint.sh:85-86). The house pattern is a `DispatchSourceProcess` on main with `reapIfExited` (`HelperSpawner.swift:355-366`).
- `spawnHook`'s fixed 30 s group TERM/KILL (`HelperSpawner.swift:367-376`) is wrong for an auth dialog.

**Fix (plan text, B3 step 4 and B5):**
- `LidWatchdog.appleScript` wraps the call:
  ```
  try
    return "ok " & (do shell script … with prompt … with administrator privileges)
  on error m number n
    return "err " & n
  end try
  ```
  osascript then always exits 0 and prints one line on stdout. `LidWatchdog.parseResult(_:) -> .launched(pid) | .canceled | .failed(code)` parses it in Kit and is tested.
- `spawnAdminScript(_ script: AdminScript, onResult:) async throws -> HelperHandle`:
  - suspended spawn of `/usr/bin/osascript` with a stdout pipe (reuse `spawn`'s reply-pipe and `ReaderState` code, with a 4 KB line cap) and an explicit minimal environment (`PATH=/usr/bin:/bin`, `LANG=en_US.UTF-8`);
  - before SIGCONT, check that the child satisfies `anchor apple and identifier "com.apple.osascript"` (`SNProcess.process(_:satisfies:)`);
  - an exit source on main;
  - a 120 s SIGTERM to the pid only (M2).
- `SNSpawn.m` and `SNSpawn.h` don't change if stdout is used; list them in Part D anyway in case stderr is chosen.
- `spawnAdminScript` must **not** require `identity` or `unavailableReason == nil`. The recovery "Turn Sleep Back On…" (B3.3) must work when helpers are unavailable ("Restart Snaptic to finish updating", or no disclaim SPI).

### M4. The heartbeat on the main queue will be starved by App Nap; the plan's own precedent does it differently (B3.2)

**Evidence**
- B3.2 runs a `DispatchSourceTimer` on main every 5 s and cites "DisplayGuard's hang model". DisplayGuard does something else:
  - its heartbeat timer runs on a **background** queue and sends `HostHeartbeat.mainAgeMillis()` (`DisplayGuardClient.swift:261-272`);
  - it holds `beginActivity(.userInitiatedAllowingIdleSystemSleep)` because "App Nap can't starve the main thread and the heartbeat (the guard would think we hung)" (`DisplayGuardClient.swift:452-461`, FIXES-R1 B5).
- Snaptic is LSUIElement. With the lid closed and the display asleep (B3.1 even forces `displaysleepnow`), App Nap timer coalescing is exactly the expected state. A beacon staler than 20 s means the watchdog restores sleep and the Mac sleeps in the bag: the feature fails as soon as it's used.

**Fix (B3.2):**
- While state is in `authorizing…on`, hold `ProcessInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Snaptic lid-closed mode")`.
- Run the beacon timer on a private serial queue (leeway 0.5 s). Each tick:
  - `futimens` the beacon through an `O_NOFOLLOW` fd **only if** `HostHeartbeat.shared.mainAgeMillis() < 10_000`;
  - run the B2 liveness checks, hopping to main for state changes (`DispatchQueue.main.async { MainActor.assumeIsolated … }`, rule 2).
- This keeps "main hung → restore" and removes the false positive.

### M5. Leftover recovery is gated behind Awake running, the feature and the kill switch; two watchdogs can fight (B3.3, B5 Feature)

**Evidence**
- B3.3 runs "at Awake start (before restore)". After a power loss with `SleepDisabled` stuck at 1, the journal is never read in any of these cases:
  - the user turned Awake off (Modules › Awake);
  - an admin set `Modules.disable.awake` or `Awake.disable.lidClosed`;
  - the user turned the "Allow…" toggle off.
- The host-level precedent runs before modules and also in Safe Mode: `RevertJournal.recoverAtLaunch` (`AppDelegate.swift:61-63`).
- **Same-boot relaunch.** For ≤ 20 s the old watchdog is alive. If the user turns lid-closed mode on again in that window:
  - preflight sees `SleepDisabled == 1` and blames "another app";
  - or the old watchdog's `restore` (`[ sd = 1 ] && pmset … 0`) switches off the **new** session's setting, and the new watchdog then takes the "someone reset it" exit.

**Fix (B3.3):**
- `LidRecovery.atLaunch(safeMode:)` runs in AppDelegate step 7 next to `RevertJournal`, whatever the module or feature state. It uses Kit `AwakeLidPolicy.classify`.
  - Its UI is a toast with "Turn Sleep Back On…" when Awake isn't running, and the B3.3 rows when it is.
- While a journal exists that isn't the current `on` token (classification pending or leftover), `turnOn` refuses with "Snaptic is finishing an earlier lid-closed session. Try again in a minute."
- The journal is a single slot.
- The kill switch and the toggle disable *turning on*, never recovery.

### M6. "Full Awake rows in a tab" has no mechanism; the plan's `compact: false` changes nothing (A1, A2 step 3)

**Evidence**
- `AwakeModule.menuSection()` always returns the compact rows (`AwakeModule.swift:138` → `IndicatorController.compactSection()` → `rows.items(compact: true)`, `IndicatorController.swift:47-50`).
- StatusMenu's `compact` parameter only strips separators (`StatusMenu.swift:392`). Passing `compact: false` just keeps separators that the compact rows never had.
- Full minus Settings is a third row set: separators yes, `.settings` no. `AwakeMenuFacts.compact: Bool` (`AwakePresentation.swift:389-397`) can't express it, and `AwakeMenuModel.rows` emits `.separator, .settings` together (:430-433).

**Fix (A2, A4, Step 0 signatures):**
- `AwakeMenuFacts.style: AwakeMenuStyle { own, compact, tab }`. `tab` gives the `own` rows minus `.settings`. Keep a `compact` computed property for the existing tests.
- `ModuleContracts`: add `func menuSection(tabbed: Bool) -> [NSMenuItem]` with a default that calls `menuSection()`. Awake overrides it.
- StatusMenu calls `menuSection(tabbed: true)` for the selected tab.
- `AwakePresentationTests` adds a `tab` truth table. Part B's new rows ("Keep Awake with Lid Closed…" / "Allow Sleep When Lid Closes", leftover row) are defined for all three styles **in the same Step 0 signature** (see M9).

### M7. The hidden ⌘1–⌘3 path is unlikely to work as described, and as specified it is invisible to VoiceOver (A3, HW-33)

**Evidence**
- `StatusMenu.menuHasKeyEquivalent` returns `false` unconditionally (`StatusMenu.swift:282-285`). For a delegate that implements it, AppKit takes that as "this menu has no key equivalent for the event" instead of scanning items.
  - Whether the scan inside an open tracking session also consults it is unverified. HW-33 as written tests only the hidden-item question.
- Choosing an item by key equivalent ends menu tracking. "Keeps the menu open" should not be the planned outcome.
  - The action then runs **after** `menuDidClose` (R3C §5.6).
  - The shared slot is not dirty after its build (`StatusMenu.swift:257-262`), so unless the action marks it dirty, the next open shows the old tab.
- The plan doesn't place the hidden items. If they sit in the swapped range, they are removed on every switch.
- Hidden items are absent from the accessibility tree. With the segmented control as the only VO path, the C4/M4 rule ("every custom-row action has a native path", `MenuKit.swift:131-132`) holds only if HW-32 passes.

**Fix (A3):**
- Put the "Show …" items in the footer group, just before Snaptic Settings….
- Their action stores the choice and sets `shared.dirty = true`. It never mutates the menu in place.
- Plan for "menu closes; next open shows the tab" as the outcome.
- `menuHasKeyEquivalent`: when `openMenus > 0` and the event is ⌘1–⌘n for n = tab count, return true with that item's target and action. Otherwise return false. HW-33 also checks that ⌘, and ⌘Q still fire in an open menu.
- When `NSWorkspace.shared.isVoiceOverEnabled` is true, make the "Show …" items visible (not hidden), so VO has a native path whatever HW-32 shows.

### M8. Part B's config, feature, backup and control plan is incomplete or contradictory; lint L15 and the key cross-check will fail (B1, B5 Config/Feature)

**Evidence**
- **Two switches for one thing.**
  - `AwakeLidConfig.allowed` and `AwakeFeature.lidClosed` (`.optIn`, "needs allowed"). Every other opt-in feature uses `features[f]` as its toggle (triggers, activity).
  - `AwakeFeatureGraph.requiresAll` lists features, not config fields (`AwakeFeatureGraph.swift:37-53`), so "needs allowed" can't be expressed.
- **Backups are an allowlist** for Awake (`KitBackup.swift:43-57`).
  - A new `lid` key is neither exported nor imported unless it is listed there, so `monotonic(over:)` is either dead code or needs an allowlist row.
  - `features.lidClosed` passes through `["features"]` unless it is added to `removedPaths` (:67-90) and kept from `current` in `importable` (`ConfigAwake.swift:107`, like pointerNudge).
- **No controls listed for Part B.** That includes the Settings toggle, stepper, picker, warning row and button; the menu items and leftover rows; and the Custom… checkbox.
  - L15 requires each id in a table and used (lint03.py:760+).
  - `testKeyCrossCheck` requires `lid.capHours` and `lid.floor` to be some spec's `keys` (`ControlRegistryTests.swift:176-193`).
  - Each `.setting` needs a `SearchSpec`.
  - The stepper must use the SettingsUI wrapper (L5 bans a raw `Stepper(`).
- **No controller id.** `testSpecsAreTotalAndControllersExist` requires the set of controllers mapped by features to equal `AwakeControllerID.allCases` (`AwakeFeatureGraphTests.swift:7-14`). The plan doesn't say whether `LidClosedController` is a new `AwakeControllerID` or part of `.sessions`.
- **Safe Mode.** `safeModeRemoves` (`AwakeFeatureGraph.swift:88`) doesn't include `.lidClosed`. B2 says Safe Mode ends the mode.
- **"Has a lid".** It is computed from `lidWillSleep == nil` "at module start". That value is reset to nil on stop (`SystemEventsMonitor.swift:126-127`) and published only after the first `readLid` and arbitrate. The existing mechanism is feature availability (`AwakeModule.swift:176-182`, `availability(of:)`).

**Fix (B5 Config/Feature, rewritten):**
- Drop `allowed`. The toggle is `features[.lidClosed]`:
  - `AwakeFeatureSpec(.optIn, all: [.sessions], uses: [.power, .system], controller: .sessions)`;
  - `.unavailable("No lid")` from the sessions controller's `availability(of:)` when `AppleClamshellState` is absent;
  - added to `safeModeRemoves`;
  - not unkillable.
- Backups:
  - `AwakeLidConfig {capHours 1…24 = 8, floor ∈ {10,20,30} = 20}` under key `lid`;
  - `KitBackup.allowedPaths[awake] += ["lid"]`;
  - `removedPaths += [awake, "features", "lidClosed"]`;
  - `importable`: `c.features[.lidClosed] = now.features[.lidClosed]` and `c.lid = c.lid.monotonic(over: now.lid)`;
  - `KitBackupTests` cases for both.
- Controls:
  - list every new `ControlSpec` id with its table: `AwakePageControls` (`awake.page.lid.allow`, `.capHours` keys `lid.capHours`, `.floor` keys `lid.floor`, `.keepAwakeLidClosed`, `.bundleWarning`, `.leftover`), `AwakeMenuRowsControls`, `CustomSessionPanelControls`, `AwakeAdvancedSheetControls`;
  - add `"lid"` to `awake.advanced.restore` keys (`AwakeAdvancedSheetControls.swift:62`);
  - fill `ConfigFixtures.fullAwake()`.

### M9. Part D's split leaves shared files unowned, which will cause merge conflicts and Step-1 lint breaks

**Evidence:** files that two Step-1 teams must edit, or that no team owns.

| File | Teams |
|---|---|
| `SnapticKit/AwakePresentation.swift` (`AwakeMenuFacts`/`AwakeMenuModel` tab style; lid rows; detail text; status facts) and `AwakePresentationTests.swift` | T-menu (M6), T-lid-kit |
| `Awake/UI/AwakeMenuRows.swift`, `IndicatorController.swift`, `AwakeModule.swift` (`menuSection(tabbed:)`, controller wiring) | T-menu, T-lid-app |
| `Core/ModuleContracts.swift` (+ Switcher and Displays module conformances) | T-menu; not listed |
| README (Menu Bar sections) | T-menu (A6), T-docs (B7) |
| `SnapticKit/Controls/*` tables, `ControlRegistry.swift` (`ControlKind`), `SettingsIndex.swift`, `ControlRegistryTests.swift`, `ConfigFixtures.swift` | T-menu, T-lid-kit, T-lid-app. L15's "every declared id is used" fails at Step 0 if ids are declared before any use |
| `AppDelegate.swift`, `EmergencyActions.swift` (recovery at launch, quit stop file) | not listed |
| `SnapticShims/SNSpawn.m/.h` (if stderr is used, M3) | not listed |
| `AwakeSession.swift`, `AwakeSessionPolicy.swift` (`AwakeRefusal`), `AwakeCommandGrammar.swift` (status JSON), `AwakeAutomation.swift` (extend refusal) | split between kit and app teams with no owner named |
| `AwakeHistory.swift`, `HistoryController.swift`, `AwakeRuntimeState.swift`, `AwakeDiagnostics.swift`, `OtherAssertions.swift`, `OtherAssertionsReader.swift`, `OtherAssertionsSection.swift` | T-lid-app, but the Kit halves are T-lid-kit |
| `scripts/lint03.py`, `lint.sh`, `stubs.tsv` (incl. new test files `LidWatchdogTests`, `AwakeLidGateTests`, `AwakeLidPolicyTests`) | Step 0 says "lint rule changes"; the test-file stubs aren't listed |

**Fix (Part D):**
- Step 0 lands the following:
  - every signature change in the shared files above: `AwakeMenuStyle`, `menuSection(tabbed:)`, new `AwakeMenuRow` cases, `AwakeRefusal.lidClosedSession`, `AwakeStatusFacts.lidMode`, runtime field names, `HelperSpawner.spawnAdminScript` signature, `EmergencyActions` usage;
  - **all** new `ControlSpec`s, each with one stub use in its aliased file, so L15 is green from Step 0;
  - stub rows for every new source and test file.
- Assign each README section to T-docs only; T-menu supplies the text in its PR description.
- Make one owner per shared file. Suggested: T-lid-kit owns `AwakePresentation.swift`, and T-lid-app owns `AwakeMenuRows`, `IndicatorController` and `AwakeModule`.

---

## Minor

### m1. "New rule L17" collides with the existing L17
The existing L17 is the `uniqueKeysWithValues` ban (lint03.py:348-354). Call the new rule L18.
- Also say it scans `Sources/` only, so `Tests/SnapticKitTests/LidWatchdogTests.swift` can hold the golden text.
- The osascript path literal lives in HelperSpawner; say so.

### m2. "lint L16 extended to `lidClosed`" would flag existing and planned code
- The regex would hit `SystemEventsMonitor.swift:49,126,170,175` (the physical lid state, `lidClosed = …`). It would also hit B3's `runtime.lidClosed = .on(until:)` in LidClosedController.
- LidClosedController decides when the mode is on (after verify) and when it ends (cap, floor, Allow Sleep), so it can't be the case that "only SessionController sets it".
- **Fix:** rename to `AwakeSession.lidMode` (the session's runtime flag) and `runtime.lidMode: LidModeState`. SessionController exposes `setLidMode(_:for sessionID:)`, which LidClosedController calls. The L16 regex is `\blidMode\s*=(?!=)` outside SessionController.swift.
- Note that `AwakeSession` is `Equatable`, so the flag changes `$governing` (intended: the menu rebuilds).

### m3. `EmergencyActions` runs off main, not on main (B3.2 "Quit")
- The signal source is on `.global(qos: .userInitiated)` (`AppDelegate.swift:199-211`); B3.2 says it runs on the main queue.
- **Fix:** register `EmergencyActions.shared.add("lid stop") { … }` at turn-on, capturing an immutable path string. The action does `open(O_CREAT|O_EXCL|O_NOFOLLOW|O_WRONLY, 0600)` then `close`, both async-signal-safe. Remove the token at `off`.

### m4. The footer's ⌘, page goes stale after a tab switch (A1)
- `sharedFooter` captures `page` at build (`StatusMenu.swift:407-409`), and the footer isn't rebuilt on a switch.
- **Fix:** the closure reads `MenuTabs.settingsPage(selected: self.selectedTab, …)` when it fires.

### m5. Width is not fixed at 300 pt (A2 "Width")
- `minimumWidth` is a floor (`StatusMenu.swift:372`). A wider native row in one tab widens the open menu on switch, which moves the segment under the pointer. Examples: long display names, Rules subtitles, "Gather Windows on This Display".
- **Fix:** at build, measure each tab's section in a scratch `NSMenu` (`.size.width`) and set `minimumWidth` to the maximum. Otherwise state "width may change on switch" and add it to HW-31.

### m6. The marker-range swap must handle empty sections and modules that stop mid-open (A2 step 2–3)
- `build` drops empty groups (`StatusMenu.swift:368-371`). Going from empty to non-empty therefore needs an extra separator, and the reverse needs one removed.
- A module stopped while the menu is open (plan pending) gives `[]`.
- **Fix:** keep `sectionItems: [NSMenuItem]` and remove exactly those. Insert after the tab separator, adding or removing the trailing separator as needed. If the section is empty, show `MenuKit.status("Nothing to Show")`.

### m7. A submenu open at switch time is untested
- A fast move from an open "Start Session ›" or "Display Tools ›" to a tab clicks while the submenu is still open. Its parent item is then removed during tracking.
- **Fix:** add this case to HW-31. If it glitches, call `cancelTracking()` on any open submenu first (MenuKit submenus get a delegate that records `isOpen`).

### m8. `menu.snaptic.sectionHeader` becomes definitely unused
- After A1, every `section()` call passes `header: false`. L15 fails.
- **Fix:** the plan should say "removed, with a `ControlRemovals` reason" (not "if it ends up unused").

### m9. Build the tab row in MenuKit instead of extending L6
- Add a `MenuKit.tabBar(_ labels:, selected:, control:, onSelect:)` factory, as for `switchHeader` (`MenuKit.swift:133-139`), with the view class in `MenuTabBar.swift`. Then L6 needs no new exemption, and the `ControlID` literal stays in StatusMenu, whose `typealias Controls = StatusMenuControls` already satisfies L15.
- `.menuTabBar` is only needed if tests treat it differently. Otherwise `.menuSwitchHeader`-style handling via `.menuItem` avoids touching the `SettingsIndex` switch.

### m10. Validation failures are invisible (B3.1)
- `exit 64` and `exit 3` happen in the backgrounded shell, so osascript still reports success, and the app learns only "verify failed" after 10 s.
- **Fix:** run the same script with a first argument `check` in the foreground before the backgrounded start: `/bin/sh -c <Q(script)> snaptic-lid check … && /usr/bin/nohup /bin/sh -c <Q(script)> snaptic-lid run … &`.
  - A nonzero `check` exit makes `do shell script` fail with that code, which M3's wrapper reports.
  - Map 3 to "Sleep is already turned off…" and 64 to `awake.lid.failed.args`.
- Also validate each numeric argument separately. `case "$UID_$PID_$CAP$FLOOR"` accepts an empty single argument.

### m11. `ioreg -r -k AppleClamshellState` walks the whole registry every 5 s
- **Fix:** `ioreg -r -n IOPMrootDomain -d 1 | awk '/"AppleClamshellState"/{print $NF; exit}'`.
- Each loop forks about 8 processes. That is acceptable, but measure it under HW-38 (`powermetrics` wakeups), and consider a 10 s period with stale = 30 s if wakeups matter.

### m12. `displaysleepnow` also sleeps an external display
- It runs on every lid-close edge, including clamshell use with an external display, where the user is working on that display.
- **Fix:** do it app-side and only when `NSScreen.screens` has no external display, via IOKit `IODisplayWrangler` `IORequestIdle`, which needs no subprocess and no root. Keep the root-side call only when the app's beacon is stale. Or drop it root-side, accepting a lit panel while Snaptic is hung.

### m13. "The watchdog can't be killed by the user" depends on its real uid
- If the authorization trampoline leaves ruid = user (euid 0), same-user processes can SIGKILL the watchdog, and B2's stuck state follows.
- **Fix:** add to HW-38: "`ps -o ruid,uid -p <watchdog>` shows 0 0". If not, B3.1's threat-model line changes and the app-side liveness check (B2) becomes the guarantee.

### m14. Smaller accuracy points
- **Slider sinks (A2).** "MenuSliderRow's sinks are weak to the view" is not accurate. The sink is owned by the row item and captures it weakly (`MenuSliderRow.swift:22,67-71`), and it dies when the removed item deallocates. No Displays builder retains rows (`BrightnessMenuItems.swift:41-46`, `DDCMenuItems.swift:62-92`). The conclusion holds; fix the wording.
- **SleepDisabled preference read (B3 step 1).** `OtherAssertionsReader` reads the preference only while the Advanced section is visible (NeedCounter, :61-74). Expose a synchronous `OtherAssertionsReader.sleepDisabledPreference()` for preflight.
- **History (B1 "Status everywhere").** The `lidClosed` history flag must mean "was on at any point" (set when the mode turns on), not the session's flag at its end. Allow Sleep clears that flag first.
- **Log events (B5).** `AwakeLogEvent.lidOff(reason)` / `lidFailed(stage)` have enum payloads, contradicting "no payload". Define `AwakeLidOffReason` and `AwakeLidFailStage` as `CaseIterable` closed enums so the keys stay fixed.
- **Beacon directory (B3 step 3).** `confstr(_CS_DARWIN_USER_TEMP_DIR)` returns `/var/folders/xx/…/T/` with a trailing slash and without `/private`. Both script patterns accept it, but trim the trailing `/` before appending `snaptic-lid` so Kit `validated(dir:)` and the script see the same string. Never pass a `realpath` form (`/private/var/…`) on one side only.

---

## Checked and found fine

- **NSSegmentedControl in a view item.** It uses the same cell `trackMouse` path as the `NSSwitch` and `NSSlider` rows already shipping in open menus (`MenuSwitchHeader.swift:54-58`, `MenuSliderRow.swift:252-259`). Its action fires at the end of its own tracking, so mutating other items synchronously in the action is sound. HW-31 and HW-34 cover the rest.
- **Live insert and remove on an open `NSMenu`.** This is supported AppKit behavior. The removed items are not under the pointer, so R2C c12 doesn't apply (but see m7).
- **Awake header pruning.** Pruning on `item.menu == nil` (`AwakeMenuRows.swift:44,327`) behaves correctly for remove-then-rebuild.
- **`overrideGuards` precedent.** It is exactly the runtime-only pattern needed: not in CodingKeys, reset in `init(from:)` and `sanitized` (`AwakeSession.swift:465-470,499,525`).
- **`DispatchSourceTimer`** is not matched by the L14 or rule-2 regexes (`lint03.py:332-336,626-627`), so there is no lint conflict.
- **Lint rules 4 and 12.** Rule-12 additions (`NSAppleScript|NSUserScriptTask|OSAScript`) don't hit the script text. L4's `"pmset"` (quoted) doesn't match bare `pmset` inside the script literal.
- **`AdminScript`.** A `package struct` with a `fileprivate init` in the same Kit file is creatable only there and readable from the app.
- **`/bin/sh` portability.** `${#}`, `$(( ))`, `case [!…]`, functions, `trap ''`, `kill -0` and `[ -L ]` are POSIX and behave the same in bash 3.2 sh mode, zsh sh emulation and dash. `stat -f %u/%m` is BSD stat.
- **Parsing.**
  - The `pmset -g batt` sed (`.*[^0-9]\([0-9][0-9]*\)%`) captures the percentage for the documented `-InternalBattery-0 (id=…)\t85%; discharging; …` line.
  - `*discharging*` doesn't match "not charging" or "charged".
  - `notifyutil -g` prints `<name> <n>`, so `$2` is the level, and ≥ 2 means heavy, which equals `ProcessInfo` `.serious`.
  - The `ioreg` awk doesn't match `AppleClamshellCausesSleep`.
- **`allowsKeyEquivalentWhenHidden`** exists from macOS 13. The deployment target is 14.
- **`AwakeFeatureGraphTests`** stay green with an opt-in `.lidClosed` mapped to `.sessions`. The default set and the unkillable set are unchanged.
- **Plan changes while the menu is open.** They remain deferred (`StatusMenu.swift:185-190`). The tab set can't change while open, so `MenuTabs.selected` only needs to run in `build`.
