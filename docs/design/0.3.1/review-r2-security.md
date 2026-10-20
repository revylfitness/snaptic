# 0.3.1 plan review r2 — SECURITY

Plan: `docs/design/0.3.1/PLAN.md` r2 (8fd1b27). Lens: security, Part B. Checked against r1 findings, §R, briefs, and `Sources/` (HelperSpawner.swift, SNSpawn.m, EmergencyActions.swift, AppDelegate.swift:199–211).

Counts: **1 Blocker, 3 Majors, 10 Minors.**

## r1 findings: fixed / not fixed

| r1 | Topic | Status | Notes |
|---|---|---|---|
| B1 | No EXIT trap; restore unaware of ownership | **Fixed** | EXIT trap + `WESET`, `trap 'exit 0' TERM INT`, `num` guards before every `$(( ))`. Residual: the one deliberate non-restoring exit is driven by a weak parse (new M3). |
| M1 | Writable bundle → refuse | **Partly fixed / reasoning challenged** | The capability argument holds, but the B6 user guidance is exactly what a tampered bundle defeats (new M1). |
| M2 | Bare command names; L17 matched nothing | **Fixed** | Absolute paths everywhere (`printf`, `echo`, `[`, `case` are builtins). L18 pins the real literals. |
| M3 | Inherited environment | **Fixed** | Spawn env is `PATH`+`LANG`; script resets `IFS`/`PATH`/`ENV`/`BASH_ENV`/`CDPATH`. The outer `do shell script` shell also gets the minimal env. |
| M4 | Dialog names osascript | **Fixed** | Stated in B1/B6; HW-28 records it. |
| M5 | Lint pins | **Fixed, with nits** | See m7. |
| m1 | Parse fails toward "off" | **Fixed** | Three-valued `sd`; `?` counts toward restore. |
| m2 | Detach from osascript's group | **Fixed by policy** | Pid-only SIGTERM, HW-31. But what `&` actually detaches is wrong (B1). |
| m3 | Planted journal → prompt | **Fixed in text** | Prompt only while `SleepDisabled` = 1. Residual in m9. |
| m4 | `kill -0` as root | **Fixed** | Comment says it is a hint; the beacon is the bound. |
| m5 | Non-integer `-ge`/`-le` | **Fixed** | `num` guards. |
| m6 | Two watchdogs | **Fixed** | Single flight (B3.0), single-slot journal, refused while pending. |

---

## Blocker

### B1. `&` backgrounds the whole `check && nohup … run` list, so `check` is not in the foreground and `$!` is not the watchdog
**Evidence:** B3.2 line 386:
`/bin/sh -c <Q> snaptic-lid check … && /usr/bin/nohup /bin/sh -c <Q> snaptic-lid run … </dev/null >/dev/null 2>&1 & echo $!`

In POSIX sh grammar, `&` ends an AND-OR list, so the whole `check && nohup …` list runs asynchronously in a subshell. The redirections attach only to the `nohup` command. As a result:

- **`check` is not in the foreground.** Its `exit 3` (someone else holds sleep) and `exit 64` (arguments) never become `do shell script`'s exit code. B3.1 step 5 therefore never sees `err 3`/`err 64`; the user gets the generic verify failure after 10 s, and the "already turned off by another app" path (B3.1/§R code m10) is dead.
- **`$!` is the subshell's pid.** It may be the watchdog only if the shell happens to `exec` the last command. Bash 3.2 (`/bin/sh` on macOS) is not documented to do that. The pid recorded in the journal and used for liveness (`kill(pid,0)` plus start time, B3.3) then identifies the wrong process.
- **`do shell script` may wait for EOF.** The async subshell keeps the `do shell script` stdout pipe open while it waits for `nohup`, and TN2065 says un-redirected output makes the call wait. If so, osascript blocks until the 120 s timeout, the B3.0 failure path writes `stop-<token>`, and the mode never turns on.

**Why it matters:** the security properties claimed in B3.2 ("argument and ownership failures surface as the exit code", "pid-only signals", app liveness keyed to the watchdog's pid) do not hold as written. The B5 round-trip test checks argv quoting, not shell grammar, so it would pass.

**Fix (B3.2):**
- Group the background part explicitly: `… check … && { /usr/bin/nohup /bin/sh -c <Q> snaptic-lid run … </dev/null >/dev/null 2>&1 & echo $!; }`.
- Add a B5/CI test that runs `LidWatchdog.command` under `dash` and `bash --posix` on Linux, with a stub script and stub binaries, and asserts all of the following:
  - a `check` exit of 3 or 64 becomes the command's exit status;
  - `$!` equals the pid of the `run` process;
  - the command returns immediately.
- Add the same checks to HW-31 on macOS.

---

## Major

### M1. The "warn, not refuse" reasoning is incomplete: the README advice it relies on is what a writable bundle breaks
**Evidence:** B6 lines 621–625. The advice "Only enter your password right after you choose Keep Awake with the Lid Closed in Snaptic" is the user's only defence against a look-alike dialog. A separate same-user app can show the same dialog, but it cannot easily tell when the user has just chosen the lid item. A modified Snaptic knows that moment exactly, so its dialog matches the advice and the user's expectation. The capability argument is right: a same-user app can already ask for the password. The protection argument is not: refusing would keep the README advice true. Drag-to-Applications installs by admin users are usually writable by that user, so the weak setup is the default one.

**Fix:**
- Keep the warning if the owner wants, but make B6 and the README say it plainly: "This advice protects you only if Snaptic is installed owned by root (`INSTALL=1`). If your account can change Snaptic, a program running as you can make Snaptic's own prompt run something else as root."
- Show the writable-bundle warning in the lid flow itself (the "Asks for an Administrator Password" note row and the Custom… toggle help), not only in Advanced.
- Alternatively, refuse when the bundle is writable and offer the `INSTALL=1` route.

### M2. The gate's "keep on replacement" rule lets a hotkey carry lid-closed mode into a new session
**Evidence:** B2 line 295 keeps the mode when the session is replaced by a direct UI start "(menu, Settings or hotkey)". Line 281 says hotkeys can never request the mode. Lines 305–306 refuse `awake extend` from the CLI so that only the user lengthens a lid session. Hotkey bindings and presets are config-writable by any same-user process (0.3 review-r3-security M1, which N10 answered with a confirmation toast for hotkeys).

A hotkey replacement therefore turns a session the user chose into one whose length a same-user process chose, up to the cap. That is the same effect the `extend` refusal exists to prevent. It is bounded by the cap, the floor and heat, but it contradicts N19.

**Fix (B2):**
- **Keep** only for `.menu`, and `.settings` with `mayStart`.
- A hotkey replacement **ends** the mode (reason `replaced`), or keeps it only after an Allow/Not Now confirmation toast, as N10 does.
- Say that the cap clock is the one from the original turn-on (continuous) and is never restarted by a replacement (see m10).
- Add rows to the `AwakeLidGate` exhaustive test.

### M3. The watchdog's one non-restoring exit depends on a loosely scoped parse of `pmset -g`
**Evidence:** B3.2 lines 411–412 and 442. `sd` keeps the *last* line starting with `SleepDisabled` anywhere in `pmset -g` output ("last match wins"). The authoritative value is printed in the "System-wide power settings:" block, before the live "Currently in use:" block (pmset.m:1194–1199 and 594). The live block also contains free-text names of other processes holding assertions (pmset.m:1306–1410).

A reading of `0`, twice, takes the deliberate exit that clears `WESET` and leaves the setting as it is. That is the only exit that skips the restore, so it should rest on the most trustworthy source available.

**Why it matters:** the app-side liveness check catches a missing watchdog while Snaptic runs. If Snaptic has also quit or crashed, nothing restores sleep until the next launch's recovery.

**Fix (B3.2):**
- Decide "someone else reset it" from kernel truth: the `"SleepDisabled"` property in `/usr/sbin/ioreg -r -n IOPMrootDomain -d 1`, which the script already queries for the clamshell keys.
- Scope the `pmset -g` parse to the System-wide block, take the first match only, and accept only `0` or `1` (anything else is `?`).
- Require **both** sources to read 0 before the non-restoring exit. Any disagreement counts toward a restore.
- Golden-test `sd` against HW-29 output captures.

---

## Minor

- **m1. Lifetime of the EmergencyActions C string** (B3.3 line 516). `runAll()` copies the action list under the lock, then runs the actions unlocked (EmergencyActions.swift:29–34). If `remove` at `off` frees the string, a concurrent signal run can use freed memory.
  - Own the path in an immutable `final class` captured by the closure, and never free it explicitly.
  - Pass mode `0600` to `open(…O_CREAT…)`.
  - Also correct the wording: this is a dispatch signal source (AppDelegate.swift:203), so async-signal safety isn't required, but it does no harm.
- **m2. Closing the beacon fd races the heartbeat queue** (B3.3 line 487). If turning off closes the `O_NOFOLLOW` descriptor on main while a tick is calling `futimens` on the private queue, the fd number can be reused and the tick could touch another file's times.
  - Cancel the timer, and close the fd in the timer's cancel handler on the heartbeat queue.
- **m3. Bound the pid in `parseResult`** (B3.1 step 5). A pid of 0 or 1 makes `kill(pid, 0)` always succeed.
  - Accept only `^ok [0-9]+$` with 1 < pid ≤ `kern.maxproc`'s range.
  - At verify, also require that the pid's uid is 0 and that its start time is after the spawn. Otherwise treat it as stage `verify`.
- **m4. TERM waits for the foreground `/bin/sleep 5`, and shutdown can run `sleepnow`** (B3.2 lines 427 and 431). sh runs the trap only after the foreground child returns, so a shutdown SIGTERM can be followed by SIGKILL before `cleanup` runs (reboot recovery covers this). When `cleanup` does run at shutdown with the lid shut, it may call `sleepnow` in the middle of a shutdown.
  - Use `/bin/sleep 5 & wait $!`.
  - On TERM, set a flag that skips `sleepnow`.
- **m5. The `sleepnow` gate may read a stale `AppleClamshellCausesSleep`** (B3.2 line 425). If that property follows `SleepDisabled` with a delay, the read right after the restore can say `No`, so the Mac keeps running in a bag (the parity B2 case).
  - Gate on `AppleClamshellState = Yes` plus an external-display check, or re-read for a few seconds.
  - HW-34 should cover a closed lid on battery with no display, right after a cap end.
- **m6. `MODE` isn't validated** (B3.2 line 402). Anything other than `check` runs the watchdog.
  - Add `case "$MODE" in check|run) ;; *) exit 64;; esac`.
- **m7. Gaps in L18** (B6 lines 632–635).
  - The osascript code requirement (`identifier "com.apple.osascript"`) contains `osascript`. Keep it in `LidWatchdog.swift`, exposed as a constant.
  - The `spawnAdminScript(` caller rule must exempt its definition in `HelperSpawner.swift`.
  - Add the literal `do shell script` to the pinned list.
- **m8. Not disclaiming osascript lets the AppleScript interpreter run under Snaptic's TCC grants** (B3.1 step 4: Accessibility and Screen Recording, through responsibility). The source is fixed and tested, but least privilege says disclaim.
  - Disclaim unless HW-28 shows that disclaiming changes or breaks the dialog, and record the reason either way.
- **m9. The recovery prompt can be aimed at someone else's setting** (B3.4). A same-user process can plant `lid.json` while another tool or an administrator has `SleepDisabled = 1`. Snaptic then says "an earlier lid-closed session didn't finish" and offers to reset it. The direction is safe (sleep turns on), but the claim is not something Snaptic knows.
  - Reword it to "may be from an earlier lid-closed session".
  - Extend the B6 advice to cover the recovery prompt too ("…or Turn Sleep Back On… in Snaptic").
- **m10. The cap clock on a "keep" replacement is unspecified** (B2 line 295). If the app recomputes the cap from the new session, the app and the watchdog disagree. The root side ends at the original cap + 60 s, and the app then reports `watchdogLost` instead of `cap`.
  - Say that `capStart` comes from the original turn-on and never resets.

---

## Checked and found fine
- **Quoting layers.** `Q` (POSIX single-quote, `'\''`) inside AppleScript escaping of `\`, `"` and LF, refusing CR and other control characters. Arguments are validated in Kit and again in the script. The round-trip test is right for quoting; B1 is about grammar, not quoting.
- **`D` validation.** `case "$D" in /var/folders/*/snaptic-lid)` (`*` matches `/` in `case`), plus the `..` and charset checks. The path is never a realpath. If confstr ever returned `/private/var/…`, it would fail closed (exit 64).
- **Late password.** `owned stop-<T>` is checked before anything is set. The 120 s timeout writes the stop file. A crash during `authorizing` is caught by `kill -0`, and by the beacon that is never touched.
- **osascript identity before SIGCONT** (`anchor apple and identifier …`). It uses a minimal env and pid-only SIGTERM. `spawnAdminScript` works while helpers are unavailable, so recovery works.
- **Ownership.** `exit 3` in both `check` and `run`. Restore happens only when `WESET = 1`, with up to 3 tries.
- **Host-level `LidRecovery`.** It runs in Safe Mode and with the feature off. A journal alone never prompts. Turning on is refused while a journal is pending.
- **`IORequestIdle`** is app-side and needs no root. Root does no display work.
- **Gate exclusions.** CLI, socket, rules, holds, launch, restore and History can't request the mode. `extend` is refused and `stop` is allowed.
- **The Kit-only `AdminScript` init**, L16's two clauses, and the rule 12 regex addition.
- **Part A**: still no security-relevant change.
