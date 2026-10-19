# PLAN 0.3.1 r2: adversarial review, code and platform feasibility

Checked against `feature/v031` @ 8fd1b27 (read-only). Apple's `pmset.m` was read from https://github.com/apple-oss-distributions/PowerManagement (main). Counts: **1 Blocker, 6 Majors, 10 Minors** (new), plus 5 r1 findings only partly fixed (listed in the table and handled by the new findings).

## r1 findings: fixed / not fixed

| r1 | Status |
|---|---|
| B1 `$SCRIPT` undefined, two quoting layers | **Fixed in design** (`Q` plus AppleScript escaping, round-trip test). The new command line breaks it in a different way: **NB1**. The literal script text can't be written as specified: **NM1**. |
| B2 watchdog exits without restoring | **Mostly fixed**: EXIT trap with `WESET`, `num` guards, three-valued `sd`, app liveness. Two residuals: the liveness pid is wrong (NB1, NM4), and the post-set check and kernel lag are missing (NM5). |
| M1 24 h cap | Fixed: 3 600…259 200 s, +60 s in the script; app options 1–72 h fit. |
| M2 state machine, late password | Fixed (B3.0; stop file checked before setting). |
| M3 Cancel vs failure, wait pattern | Fixed: the wrapper, stdout, exit source, pid-only SIGTERM. Residual: there's no API for the requirement check, and the responsibility check conflicts with "not disclaimed": **nm7**. |
| M4 App Nap | Fixed: background timer, `mainAgeMillis` gate, `beginActivity`. |
| M5 recovery gated behind Awake | Fixed (B3.4 host-level, single-slot journal). The StatusMenu ↔ LidRecovery interface is not in Step 0: **NM6**. |
| M6 full rows in tabs | Fixed (A4). |
| M7 ⌘n path | Fixed. Residual: VoiceOver state is read only at build: **nm8**. |
| M8 config, feature, backup, controls | Fixed. Residuals: a nonexistent kind and an L16 self-hit: **nm5**, **nm6**. |
| M9 team split | **Partly**: the table exists but has gaps: **NM6**. |
| m1 L17 collision | Fixed (L18). |
| m2 L16 names | Fixed (three names). The regex hits `AwakeSession.swift`: **nm5**. |
| m3 EmergencyActions off main | Fixed. |
| m4 ⌘, page | Moot (⌘, unchanged). |
| m5 width | Fixed by scratch measuring. Caveat: **nm2**. |
| m6 empty sections | Fixed. |
| m7 submenu open | Addressed. `cancelTracking` semantics: **nm1**. |
| m8 `sectionHeader` | Moot (kept for single-module menus). |
| m9 MenuKit factory | Fixed. |
| m10 silent validation | **Not fixed**: `check` runs in the background (NB1). |
| m11 `ioreg -k` | Fixed. |
| m12 `displaysleepnow` on externals | Replaced by app-side `IORequestIdle`, which **doesn't work on Apple silicon**: **NM2**. |
| m13 real uid | Fixed (HW-31). |
| m14 accuracy points | Fixed, except that the new start-time read fails for a root pid: **NM4**. |

---

## Blocker

### NB1. `check … && nohup … & echo $!` backgrounds the whole `&&` list (B3.2 "Command")

**Evidence:** POSIX shell grammar. `&` ends an *AND-OR list*, so `A && B >/dev/null 2>&1 & echo $!` runs `A && B` together in one asynchronous subshell. Three things follow.

1. **`check` doesn't run in the foreground.** `do shell script` sees only `echo $!`, which always succeeds. Codes 3 and 64 never reach `parseResult`, so m10 isn't fixed, and B3.1 step 5's "Code 3 from the `check` step" can't happen.
2. **`$!` is the subshell's pid, not the watchdog's.** In bash 3.2 that subshell forks `nohup` as a child; it doesn't exec it in place. B3.3's `kill(pid, 0)`, the start-time match and the journal pid then track the wrong process.
3. **`do shell script` likely hangs.** The redirections bind only to `B`. The subshell, and `check` inside it, keep fd 1, which is `do shell script`'s output pipe. TN2065: output must be redirected, or `do shell script` waits for it to close.
   - If the subshell stays alive as the watchdog's parent, osascript doesn't return until the watchdog exits.
   - The app then hits its 120 s timeout, takes the B3.0 failure path and writes `stop-<token>`, so lid-closed mode never turns on.

**Fix (B3.2):**
```
/bin/sh -c <Q(script)> snaptic-lid check <Q(a1)>…<Q(a6)> </dev/null >/dev/null 2>&1 || exit $?
/usr/bin/nohup /bin/sh -c <Q(script)> snaptic-lid run <Q(a1)>…<Q(a6)> </dev/null >/dev/null 2>&1 &
echo $!
```
- The three lines are joined with LF, which `appleScript` maps to `\n`.
- `do shell script` raises its error with the exit status as the number (TN2065), so `err 3` and `err 64` arrive as planned.
- `$!` is now `nohup`'s pid. `nohup` execs `/bin/sh`, so that pid is the watchdog.
- Add to the round-trip test: the parsed command is three commands, and only the second ends in `&`.
- Add to HW-31: osascript returns in under 1 s after the password, and `ps -p $! -o comm` shows `sh`.

---

## Major

### NM1. The script can't be stored as a Swift string literal as written (B3.2 "Script", B5)

**Evidence**
- **Interpolation.** In a regular Swift string literal, `sed -n 's/.*[^0-9]\([0-9][0-9]*\)%.*/\1/p'` is a compile error: `\(` starts string interpolation, and `\1` is an invalid escape.
- **The tab character.**
  - The `IFS=' <TAB><LF>'` line puts a literal **tab** in the text.
  - B3.2's `appleScript` "refuses CR and every other control character". TAB (0x09) is one, so `startScript` always refuses its own script.
  - The tab is also trailing whitespace on its line, which editors and `git` whitespace fixers strip silently.
- **The `unset` line.** `unset ENV BASH_ENV CDPATH` has no effect on the running shell: bash reads those at startup, and when invoked as `sh` it ignores them non-interactively. Harmless, but B6 counts it as a protection.

**Fix:**
- `LidWatchdog.script` is a raw literal (`#"""…"""#`).
- Replace the `IFS=` line with `unset IFS`. POSIX says an unset IFS behaves as space/tab/newline.
- Keep `unset ENV BASH_ENV CDPATH` only for child shells, and change B6 to say the protection is the minimal environment given to osascript.
- Add a Kit test that `script` contains no byte below 0x20 other than LF.

### NM2. `IORequestIdle` on `IODisplayWrangler` doesn't sleep the display on Apple silicon (B3.3 "Display while the lid is shut")

**Evidence**
- Apple's own `pmset displaysleepnow` (`pmset/pmset.m`, `displaySleepNow()`, around l.982-1006) has two branches:
  - `#if SLSDISPLAYMANAGER`: it calls `SLSDisplayManagerRequestDisplaysIdle()`;
  - only the `#else` branch uses `IORegistryEntryFromPath(… ":/IOResources/IODisplayWrangler")` + `IORequestIdle`, and it returns silently when the wrangler is missing.
- Field reports agree: `ioreg -n IODisplayWrangler` shows nothing on an M2 Pro (https://www.macscripter.net/t/how-to-detect-display-sleep-on-apple-silicon/74377), and Keyboard Maestro's Sleep Screen action failed on Apple silicon while `pmset displaysleepnow` worked (https://forum.keyboardmaestro.com/t/sleep-screen-action-fails-on-mac-mini-with-apple-silicon/20940).
- So on the main target hardware, the panel stays lit inside the closed lid. That brings back parity B1's heat and battery cost.

**Fix:** pick one, and state it in B3.3:
- **(a)** Resolve `SLSDisplayManagerRequestDisplaysIdle` at runtime in `PrivateDisplayAPI.swift`.
  - That is the only file rule 11 allows `dlsym` in, and it already does the SLS↔CGS aliasing.
  - Fall back to the `IODisplayWrangler` path when the symbol is missing (Intel).
  - Gate it with a kill switch.
- **(b)** Spawn `/usr/bin/pmset displaysleepnow` as the **user** (no root) through a fixed `LidWatchdog.displaySleepArgv` and a non-admin `HelperSpawner` path. L18 already makes `LidWatchdog.swift` the literal's home.

Either way, HW-30 runs on Apple silicon **and** Intel.

### NM3. `AssertionManager.declareUserActivity()` doesn't exist, and L2 forbids putting it there (B3.3)

**Evidence**
- L2 allows `IOPMAssertionDeclareUserActivity` **only** in `Awake/Sources/ActivitySimulator.swift` (lint03.py L2, ratcheted at 0 elsewhere).
- AssertionManager (L1's home) has no such method.
- ActivitySimulator runs only while the opt-in `.activity` feature is effective (`AwakeFeatureGraph.swift:67`), so it isn't there for most lid-mode users.

**Fix:** drop the call. Opening the lid is itself user activity and wakes the panel; HW-30 already checks "the panel wakes on lid open". If HW-30 fails, add `ActivitySimulator.wakeDisplayOnce()`, a static function with no feature dependency, owned by T-lid-app and inside L2's file.

### NM4. `proc_pidinfo(PROC_PIDTBSDINFO)` fails on a root pid from Snaptic (B3.1 step 6, B3.3 liveness)

**Evidence**
- `SNProcess.h` says it directly: `instanceID(for:)` uses `sysctl(KERN_PROC_PID)` "which (unlike PROC_PIDTBSDINFO) also answers for other users' processes".
- `startTime(for:)` therefore returns 0 for the root watchdog. Each tick's "start time must match" check then either always fails (immediate `watchdogLost`) or, if 0 is allowed, never protects against pid reuse.

**Fix:** record and compare `SNProcess.instanceID(for: pid)`. Treat 0 as "gone" only together with `kill(pid,0) == ESRCH`. This depends on NB1, so that the pid is the watchdog's.

### NM5. The root side reads the preference, not the kernel, with no check after setting; `sleepnow` races powerd (B3.2)

**Evidence**
- **`sd` parses `pmset -g`**, which reports the stored preference (research §6), and counts a missing line as 0.
  - If `pmset -g` output changes so that the line is missing (Insomnia saw macOS 27 change `pmset -g custom`), the start check passes.
  - The watchdog then sets `disablesleep 1`, reads 0 twice and takes the deliberate non-restoring exit (`WESET=0`).
  - Only the app's liveness check catches that, and only while Snaptic runs.
- **`cleanup` runs `pmset -a disablesleep 0` and then `pmset sleepnow` at once.**
  - `pmset` writes the preference synchronously. powerd applies it to the kernel asynchronously, after `kIOPMPrefsChangeNotify` (research §1).
  - The `sd` loop reads the preference, so it reads 0 at once.
  - While the kernel still has `userDisabledAllSleep` set, `sleepnow` is refused (`privateSleepSystem` → `kIOReturnNotPermitted`, research §1). The parity B2 fix ("Mac sleeps in the bag after the end") then fails silently. HW-34 might pass only by luck of timing.

**Fix (B3.2):**
- Add `ksd()`: `/usr/sbin/ioreg -r -n IOPMrootDomain -d 1 | awk '/"SleepDisabled"/{print ($NF=="Yes")?1:0; f=1} END{if(!f)print "?"}'`.
- **Post-set check.** After `pmset -a disablesleep 1; WESET=1`, require `sd` = 1 **and** `ksd` = 1 within 3 s; otherwise `exit 0`, and cleanup restores.
- **"Not ours".** Take this path only when `sd` and `ksd` both read 0 twice.
- **`cleanup`.** After the reset, wait up to 5 s for `ksd` = 0. Only then run `sleepnow`, and run it again once 2 s later if the lid is still shut.
- **Test.** Golden-test `ksd` against a captured `ioreg` sample; HW-29 records one.

### NM6. Step 0 can't work as specified, and the ownership table has gaps (Part D)

**Evidence**
- **`fatalError` is banned.** Step 0 says "`fatalError("Step 1")` bodies". `fatalError(` is banned everywhere in `Sources/` by lint.sh rule 13. The project's stub convention is safe returns with "no fatalError" (`scripts/gen-stubs.py` docstring, R4C §3.2).
- **Files no team owns:**
  - `SnapticKit/AwakeArbiter.swift` and its tests. The new `AwakeArbiterInput.lidShut` changes an explicit init with no defaults (`AwakeArbiter.swift:41-51`), which breaks every call site.
  - `Awake/AwakeRuntimeState.swift`: `lidMode`, `lastLidEnd`, `reset()`, and a published `lidClosed`. Today only `lidWillSleep` is published, and `lidShut` needs the physical state.
  - `Awake/AwakeContext.swift` / `AwakeContracts.swift`, to reach LidClosedController.
  - `SnapticKit/Controls/ControlRegistry.swift` (`ControlKind.menuTabBar`, `ControlState.lidModeOn`/`lidLeftover`), `SettingsIndex.swift`, every edited `Controls/*` table, `ControlRegistryTests.swift`.
  - `SnapticShims/SNProcess.*` (nm7).
  - `ActivitySimulator.swift` (NM3, if kept).
  - `PrivateDisplayAPI.swift` (NM2 a).
  - The Permissions copy file named in B1's "Both strings live in Kit next to the Permissions copy".
- **Missing interfaces between teams:**
  - StatusMenu (T-menu) draws LidRecovery's rows (T-lid-app) in the shared menu and adds the N11 ", even with the lid closed" label suffix. Step 0 lists no interface for either, such as `ModuleHost.lidRecovery: LidRecoveryState` and `AwakeHost.lidModeOn`.

**Fix:**
- Step 0 stubs use safe returns (`[]`, `nil`, `.off`, `false`, `StubError.notBuilt`).
- Add the files above to the table: Arbiter, RuntimeState, Context/Contracts and SNProcess to T-lid-app or T-lid-kit as their module dictates; the Controls/registry files to the lead in Step 0, then frozen.
- Default `lidShut: Bool = false` in `AwakeArbiterInput.init`.
- Add the two host interfaces to Step 0's signature list.

---

## Minor

### nm1. `cancelTracking()` on an open submenu may close the whole menu (A2 step 2)
- AppKit documents `cancelTracking` as "Dismisses the menu and ends all menu tracking". The tab switch would then happen in a closed menu.
- **Fix:** HW-24 records the behavior. If it closes the menu, skip `cancelTracking` and let removing the parent item close the submenu (HW-24 checks that this doesn't glitch). Otherwise ignore the click while a submenu is open.
- The tracking delegate must be a retained shared object, because `NSMenu.delegate` is weak.

### nm2. Scratch measuring needs cleanup and has a cost (A2 "Width")
- After reading `scratch.size.width`, call `scratch.removeAllItems()`. Without it, Awake's `headers` hold scratch items whose `menu` isn't nil, so they aren't pruned and are refreshed until the scratch menu goes away.
- The selected section is built twice on each open; say so.

### nm3. The tab item with `isEnabled = false` may also change how VoiceOver treats it (A2)
- A disabled item can be announced as dimmed, and VO interaction into its view may be refused.
- **Fix:** HW-25 tests both settings, and the enabled state is chosen by HW-24 **and** HW-25 together.

### nm4. `.layoutChanged` needs a real element (A2 step 5)
- NSMenu has no public window accessor.
- **Fix:** post on `tabBarView.window ?? tabBarView`.

### nm5. The L16 clause hits `AwakeSession.swift` itself (B2)
- `\.lidRequested\s*=(?!=)` matches `self.lidRequested = …` in `AwakeSession`'s init and the `s.lidRequested = false` in `sanitized` (cf. `AwakeSession.swift:484,524` for `overrideGuards`).
- **Fix:** exempt `SnapticKit/AwakeSession.swift` as well.

### nm6. `awake.advanced.lidBundle` "status" isn't a `ControlKind` (B7)
- The kinds are `setting, button, navigation, list, statusAction, shortcut, menu*` (`ControlRegistry.swift:44-46`).
- **Fix:** name one, for example `.statusAction` with `when: [.state(...)]`, or a plain status row with no control if it has no action.

### nm7. The osascript identity check needs pieces that don't exist yet (B3.1 step 4)
- `SNProcess.process(_:satisfies:)` takes SecRequirement **data**, and nothing compiles `anchor apple and identifier "com.apple.osascript"`.
  - **Fix:** add `SecRequirementCreateWithString` + `SecRequirementCopyData` (Security is already linked) as a `static let`.
- Because the spawn is not disclaimed, `responsiblePID == pid` (`HelperSpawner.swift:340`, `verify` :512) is false.
  - **Fix:** `spawnAdminScript` must skip that check and verify `isStopped` + requirement only.
- `LineSplitter.maxLine` is a fixed 64 KB constant (`LineSplitter.swift:5`), so "4 KB line cap" needs a new init parameter, or just drop the 4 KB claim.

### nm8. The VoiceOver check runs only at build (A3)
- If VoiceOver turns on while the slot isn't dirty, the Show … Tab items stay hidden.
- **Fix:** mark menus dirty on `NSWorkspace.shared` `isVoiceOverEnabled` KVO (with `.receive(on: DispatchQueue.main)`, L10) or on `accessibilityDisplayOptionsDidChangeNotification`.

### nm9. A second TERM aborts `cleanup` halfway (B3.2)
- `cleanup` runs as the EXIT trap after `trap 'exit 0' TERM`. If another TERM arrives during its `/bin/sleep 1` retries, `exit 0` runs inside the EXIT trap, bash doesn't re-run EXIT, and the retries and `sleepnow` are skipped.
- **Fix:** make the first line of `cleanup` `trap '' TERM INT`.

### nm10. "No lid" availability must not depend on the published runtime value (B3.1 step 1)
- `availabilityTable` runs at module start (`AwakeModule.swift:176-182`), before SystemEventsMonitor's first `readLid` publishes.
- **Fix:** `availability(of: .lidClosed)` reads `AppleClamshellState` from IORegistry synchronously, and the table is recomputed on `.didWake`.

---

## Checked and found fine

- **Traps.** `trap 'cleanup' EXIT; trap 'exit 0' TERM INT` in bash 3.2 sh mode: a TERM runs `exit 0`, the EXIT trap runs `cleanup` once, and the trap is deferred until the foreground `sleep 5` returns (≤ 5 s).
  - Exits before the trap is installed (`check`, the early stop file, `exit 3`/`64`) correctly restore nothing.
  - `{ WESET=0; exit 0; }` correctly skips the restore.
- **No `set -e`, no unguarded arithmetic.** Every arithmetic operand is `num`-checked except `START`, and a null `START` evaluates to 0, which trips the cap at once: a restore, which is safe.
- **`Q` quoting.** It round-trips the awk and sed programs (`'…'\''…'`). Backslashes survive inside single quotes, and AppleScript `\\` and `\"` escaping layers cleanly on top.
- **The AppleScript wrapper.** `osascript -e` prints the script's returned string plus LF on stdout and exits 0 in both branches. `do shell script` maps a nonzero exit status to the error number (TN2065).
- **Reading osascript's stdout.** `spawn`'s reply pipe plus `ReaderState` delivers every line before `onExit` (`HelperSpawner.swift:273-289`), so `parseResult` sees the line before the exit.
- **Liveness signals.** `kill(pid, 0)` from Snaptic to a root process returns EPERM while it lives and ESRCH once it is gone. `HostHeartbeat` stamps every 0.5 s in `.common` mode (`HostHeartbeat.swift:17-31`), so `mainAgeMillis` is valid in menus and modals.
- **`menuHasKeyEquivalent`** can return the hidden item's own public `target`/`action` (`MenuKitItem` sets `target = self`, `action = #selector(fire)`). No private selector is needed. Compare `menu === shared?.menu`.
- **The beacon path.** The `case "$D" in /var/folders/*/snaptic-lid` pattern matches the trimmed `confstr` path. `*` spans `/` in `case`.
- **Backups and features.** The B5 config, feature and backup rewrite agrees with `KitBackup.allowedPaths`/`removedPaths`, `ConfigAwake.importable`, and `AwakeFeatureGraphTests` (an opt-in mapped to `.sessions` keeps the controller set and the defaults).
- **`.hardware(.battery)`** is an existing condition (`AwakePageControls.swift:60`).
