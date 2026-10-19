# 0.3.1 plan review r1 — SECURITY

Lens: security. Focus: Part B (lid-closed mode), the root watchdog (B3.1), the admin/AppleScript path, what same-user/other-local-user/malicious-app attackers can achieve, the user-writable bundle, the journal, leftover recovery, EDR, threat-model honesty, and lint (rule 12 / L17). Checked against PLAN.md, briefs/{awake,research}.md, and `Sources/` (HelperSpawner.swift, SNSpawn.m, ControlServer.swift, ControlCommandRegistry.swift, EmergencyActions.swift, AppDelegate.swift, SessionController.swift, OtherAssertionsReader.swift, AwakeActivityGate.swift, scripts/lint.sh, scripts/lint03.py), plus the Apple sources named in the research brief (PowerManagement `pmset.m`, Libnotify) and TN2065.

Counts: **1 Blocker, 5 Majors, 6 Minors.**

---

## Blocker

### B1. The watchdog has no restore-on-exit safety net; any unexpected shell termination leaves `SleepDisabled` stuck on
Evidence: PLAN §B3.1 lines 249–288. The only restore paths are `trap restore TERM INT` (line 266) and the explicit loop checks that call `restore`. There is **no `EXIT` or error trap**. `/bin/sh` on macOS is bash in POSIX/sh mode; a fatal shell error (e.g. an empty command substitution inside `$(( ))`) aborts the whole script, and the TERM/INT trap does not fire on that path. The concrete trigger is line 276:
```
[ $((NOW-$(stat -f %m "$DIR/beat-$TOK"))) -le 20 ] || restore
```
If `stat -f %m` yields empty (the beat file is absent for an instant — a TOCTOU after the `owned` check on line 275, or a `/var/folders` temp purge), `$((NOW- ))` is an arithmetic parse error. Confirmed on `bash --posix` and `dash`: the shell exits (127 / 2) and aborts the loop. With no EXIT trap, `SleepDisabled` stays `1` with no live watchdog until the next launch's leftover recovery. "Stuck on" is precisely the catastrophic state the whole no-install design exists to avoid, so the watchdog must restore on *every* exit, not just on two signals and the happy-path checks.

Compounding bug: `restore()` (line 263) is ownership-unaware — it resets whenever `sd` reads `1`, relying purely on control flow (the `exit 3` start-guard) to avoid touching another tool's setting. So a naive `trap restore EXIT` would be wrong: the `exit 3` path (someone else already held `SleepDisabled`) would then reset a value Snaptic never set, breaking the "never take ownership" guarantee (lines 265, 303).

Why it matters: defeats the core safety promise and the "every stop path is a file the user can create" claim (B3.1 line 302) — a routine shell-fatal error has no stop path at all.

Fix (plan text, §B3.1): record ownership and restore on any exit. After line 267 set `WESET=1`. Add `cleanup() { [ "$WESET" = 1 ] && [ "$(sd)" = 1 ] && pmset -a disablesleep 0; }` and `trap 'cleanup; exit' EXIT TERM INT`. Make `restore()` just `exit 0` (the EXIT trap does the work). Guard every `$(( ))` against empty input, e.g. `M=$(stat -f %m "$DIR/beat-$TOK" 2>/dev/null); [ -n "$M" ] && [ $((NOW-M)) -le 20 ] || cleanup_and_exit`. Add an HW check: kill the watchdog with an induced shell error (or remove the beat file mid-iteration) and verify `pmset -g` shows `SleepDisabled 0`.

---

## Major

### M1. A user-writable bundle turns one admin-password entry into arbitrary root; warning is not enough
Evidence: PLAN §B1 line 162 (warn, don't refuse; open question 2), §B6 line 383 (threat model lists "a user-writable bundle risk"). Snaptic is ad-hoc signed and commonly lives in a user-writable location (`~/Downloads`, `~/Applications`). The script that runs as root is compiled into Snaptic (B3.1), so a same-user process that can write the bundle can replace the script body (or the whole binary) with anything, and the next time the user turns on lid-closed mode they type their admin password into a dialog they believe is Snaptic's — granting the tampered code full root. Before 0.3.1, a tampered Snaptic could only act as the user; adding an admin-password path is a genuine escalation of the user-writable-bundle risk to **local privilege escalation**, and the user has been trained to approve the prompt.

Why it matters: the entire "root does only `pmset`" model (B3.1 lines 292–294) assumes Snaptic's code is trusted, but nothing enforces that for a writable ad-hoc bundle.

Fix (plan text): resolve open question 2 toward **refuse** — do not offer/allow lid-closed mode when `Bundle.main.bundlePath` is writable by a non-root user (reuse the `KitHookPolicy` writability logic already in `HelperSpawner.checkExecutable`). If the owner insists on warn-only, §B6's threat model must state plainly: "If Snaptic's app bundle is writable by your account, any program running as you can replace Snaptic and obtain root the next time you enter your password for lid-closed mode."

### M2. The root script runs bare command names (PATH-dependent) instead of absolute paths; L17 pins a literal the script never contains
Evidence: PLAN §B3.1 lines 261–286 call `pmset`, `ioreg`, `notifyutil`, `awk`, `sed`, `stat`, `date`, `head`, `sleep`, `kill`, `printf` by bare name, relying on `PATH=/usr/bin:/bin:/usr/sbin:/sbin` (line 250). TN2065 (research §4 line 78) explicitly says to use absolute paths in `do shell script`. §B6 line 376 defines L17 to pin the literal `/usr/bin/pmset` — but the script as written contains `pmset`, not `/usr/bin/pmset`, so L17 would match nothing and give false assurance.

Why it matters: a root process resolving executables through `PATH` is a hardening anti-pattern; and the lint meant to constrain the dangerous literal does not match the code, so the enforcement is cosmetic.

Fix (plan text, §B3.1 + §B6): use absolute paths for every binary in the script (`/usr/bin/pmset`, `/usr/sbin/ioreg`, `/usr/bin/notifyutil`, `/usr/bin/awk`, `/usr/bin/sed`, `/usr/bin/stat`, `/bin/sleep`, `/bin/kill`, `/usr/bin/printf`, `/bin/date`). Keep the explicit `PATH` as belt-and-braces. Make L17 pin what actually appears: `disablesleep`, `/usr/bin/pmset`, and `with administrator privileges` all present in `LidWatchdog.swift`.

### M3. osascript is spawned with Snaptic's full inherited environment; no sanitization specified
Evidence: PLAN §B3 step 4 (line 237) and §B6 line 375 describe `spawnAdminScript(source:)` running `/usr/bin/osascript -e <script>`; nothing specifies the child's environment. TN2065 (research §4 line 78): `do shell script` "inherits the parent's environment". The root script never sets `IFS` or clears environment. `SNSpawn.spawnSuspended` already takes an `environment:` array (SNSpawn.m:70–128; the helper path passes `@[]`), but `HelperSpawner.spawn` uses the no-env overload (HelperSpawner.swift:201), so adminScript would inherit everything unless told otherwise.

Scope check (so the plan states this accurately, not as a confirmed RCE): `/bin/sh` in sh-mode does **not** auto-source `$ENV`/`$BASH_ENV` for `sh -c` (verified on `bash --posix`/`dash`), and SIP/library-validation strips `DYLD_*` for the Apple-signed `osascript`, `/bin/sh`, `pmset`, etc. So this is defense-in-depth, not a demonstrated escalation — but the design should not depend implicitly on those two facts. Residual concerns are `IFS` poisoning affecting the script's parsing (run as root) and locale vars affecting `awk`/`sed`.

Why it matters: a root shell should run with a known-minimal environment, not whatever environment Snaptic happened to be launched with (which a same-user launcher of Snaptic controls).

Fix (plan text, §B3/§B6): spawn osascript with an explicit minimal environment (`PATH`, `HOME`, nothing else); have the script set `IFS=' \t\n'; export PATH; unset ENV BASH_ENV CDPATH` as its first lines; note in §B6 that the spawn passes a sanitized environment.

### M4. The auth dialog names "osascript", not "Snaptic", as the requester
Evidence: PLAN §B1 line 174 ("macOS's own authorization dialog, through `/usr/bin/osascript`") and the prompt text at line 176 ("Snaptic wants to keep your Mac awake…") — that text is the `with prompt` reason, but the dialog's title/app identity is osascript's, since osascript is the process requesting the right (research §4 lines 80, 83; open question 3 is unresolved). Any app can produce the identical "osascript wants to make changes" dialog, so the user cannot visually tell Snaptic's root request apart from any other app's.

Why it matters: the security story leans on the user making an informed choice ("a dialog the user asked for", B3.1 line 300). If the requester shown is a generic system tool, that informed-consent claim is weaker than the plan implies, and it interacts with M1 (a tampered or unrelated app shows the same dialog).

Fix (plan text): resolve open question 3 before shipping; HW-35 must record the exact requester name/icon/title on 14/15/26/27. Update §B6 threat model and the README to state what the dialog actually names as the requester, and that the custom reason text is the only Snaptic-specific signal.

### M5. Lint does not pin the osascript spawn (path, `displaysleepnow`, `nohup`, `ioreg`, `notifyutil`) to one file
Evidence: PLAN §B6 line 374 adds `NSAppleScript|NSUserScriptTask|OSAScript` to rule 12's regex (good — brief §8:265 confirms the current gap), and line 376 pins three literals via L17. But the real mechanism spawns `/usr/bin/osascript` as a plain path string through the normal `SNSpawn`/`HelperSpawner` route, which the rule-12 regex does not catch, and L17 does not pin `osascript`, `displaysleepnow`, `nohup`, `ioreg`, `AppleClamshellState`, or `notifyutil`. So a future spawn of osascript-with-admin from another file would pass lint.

Why it matters: the brief's own rule-12 finding was that AppleScript slipped the net; the string-path spawn is the same class of gap, one layer down.

Fix (plan text, §B6): extend L17 so the literals `osascript`, `/usr/bin/osascript`, `displaysleepnow`, and `nohup` may appear only in `LidWatchdog.swift`, and add a lint that `HelperSpawner.spawnAdminScript` is the sole caller that passes an osascript path (mirror L16's single-file assignment check). State that `spawnAdminScript`'s `AdminScript` argument type has a `fileprivate` init in `LidWatchdog.swift` (already proposed at line 375) — and lint that `AdminScript(` appears only there.

---

## Minor

### m1. `sd()` / `restore` parsing fails toward "leave sleep off"
Evidence: PLAN §B3.1 lines 261, 263, 277. `sd()` prints `0` only via the awk `END` fallback when no `SleepDisabled` line is seen; `restore` resets only on an exact `"$(sd)" = 1`. `pmset -g` prints the `SleepDisabled` line only from the stored preference and only when the key exists (pmset.m:1196–1199, confirmed), so the common cases are fine, but any unexpected multi-token/garbled read makes the `=1` test false and *skips* the reset — the dangerous direction. Line 277 similarly `exit 0`s (no restore) whenever `sd` isn't exactly `1`.

Fix: parse defensively — treat "contains 1" vs "contains 0" explicitly, and fold this into B1's EXIT-trap cleanup so an unparseable read never silently leaves the bit set without a watchdog.

### m2. Ensure the watchdog detaches so osascript cleanup can't signal it
Evidence: PLAN §B3 step 4 line 238 ("its own process group") and §B3.1 line 247 (`nohup … &`); step 4 also SIGTERMs osascript after 120 s. `nohup` ignores SIGHUP but does not `setsid`. If the nohup'd `/bin/sh` watchdog shares osascript's process group, a later `killpg`/group cleanup of osascript could take the root watchdog with it.

Fix: have the watchdog detach into its own session (a leading `setsid`, or the `launchctl` option in open question 5) so no cleanup of osascript ever reaches it; HW-38 should test "SIGTERM osascript, watchdog still alive".

### m3. A user-writable journal lets a same-user process conjure a root password prompt
Evidence: PLAN §B3 step 2 line 233 (`lid.json`, 0600 in the 0700 dir) and §B3.3 lines 325–330 (leftover classification reads the journal; "Turn Sleep Back On…" shows a password prompt). A same-user process can write a fake `lid.json` (different `bootSessionUUID`) to make Snaptic display a persistent "leftover" row and present an admin-password prompt the user didn't initiate. The action behind it only runs `pmset -a disablesleep 0` (benign), but it is prompt-fatigue/social-engineering surface, and it pairs with M1/M4.

Fix: note this in §B6; only show the leftover row when `SleepDisabled` actually reads `1` (the plan already requires this in B3.3 — make it explicit that a journal alone never triggers a prompt), and never read any journal field into a shell/privileged context.

### m4. `kill -0 "$PID_"` as root is true for any live pid
Evidence: PLAN §B3.1 line 273 and the note at line 301. As root, `kill -0` succeeds for any existing pid regardless of owner, so after a Snaptic crash + pid reuse the "Snaptic gone" check never fires; only the 20 s beacon bounds it. The plan says this, but line 273's comment "Snaptic gone" overstates what the check provides.

Fix: reword the comment/note to "liveness hint only; the 20 s beacon is the real bound", and keep the beacon as the authoritative liveness signal.

### m5. Thermal/battery parses run `-ge`/`-le` on possibly non-integer input
Evidence: PLAN §B3.1 lines 280–283. `T=$(notifyutil … | awk '{print $2}')` then `[ "$T" -ge 2 ]`; `P=$(… sed …)` then `[ "$P" -le "$FLOOR" ]`. Non-integer input makes `test` emit "integer expression expected" (to the redirected stderr) and return error — not fatal, so it fails open (no cutoff), which is why the app-side guards must truly be independent. Libnotify confirms `com.apple.system.` is reserved world-readable (`rwr-r-`), so the key is readable, but it may be empty/unposted.

Fix: validate the parsed value is all-digits before the numeric test (same `case … in *[!0-9]*` idiom already used for args); confirm in §B4 that the app-side heat (`thermal >= serious`) and battery (`<= floor`) ends do not depend on the root parse succeeding.

### m6. Double turn-on could spawn two watchdogs
Evidence: PLAN §B3 (LidClosedController.turnOn) and §B3.1 line 265 (`[ "$(sd)" = 0 ] || exit 3`). Two near-simultaneous turn-ons can both read `sd=0` before either sets it, both `pmset disablesleep 1`, and both believe they own it; on stop, the first cleans up and the second (now seeing `sd=0`) exits without acting — survivable, but fragile and racy with the journal token.

Fix: §B3 should state that `LidClosedController.turnOn` serializes (ignores a second turn-on while one is pending/running), so at most one watchdog and one `lid.json`/token exist at a time.

---

## Part A (menu tabs) — security
Reviewed A1–A6. No security-relevant issues. The hidden ⌘1–⌘3 items (`allowsKeyEquivalentWhenHidden`, A3 line 109) are local, require the menu open, and add no external entry point. `snapticMenuTab` in `UserDefaults` (A5) is a lenient UI string with no privileged effect. Tab switching mutates menu items synchronously in the tracking mode (A2) — a correctness/UX matter, not security.

---

## Checked and found fine
- **No new remote/IPC entry point to the prompt.** Lid-closed mode is gated to in-process direct UI actions (§B2 lines 185–195), excluded from `AwakeSessionOptions`/presets/CodingKeys like `overrideGuards` (verified AwakeSession precedent in brief §1), and `AwakeLidGate` mirrors `AwakeActivityGate` (which `ActivityPolicy.nudgeAllowed` and lint L16 already enforce). The control socket (`ControlServer`, peer-uid checked, off by default) and the closed CLI grammar cannot express it; `awake extend` is refused (§B2 line 207) and only `stop` (turn-on → off) works.
- **Spawn plumbing.** `osascript` is Apple-signed; `SNSpawn` sets `POSIX_SPAWN_CLOEXEC_DEFAULT`, resets signal mask/dispositions, and can pass an explicit env — so the M3 fix is implementable without new shim code. `/usr/sbin/ioreg` SleepDisabled reads are root-free (research §6) and in-process on the app side.
- **Restore ownership semantics (happy path).** Start-guard `exit 3` plus "exit without touching it" on line 277 correctly avoid stealing another tool's `SleepDisabled` — the gap is only the missing-EXIT-trap case in B1.
- **Signal/quit coverage.** `EmergencyActions.runAll()` runs off the main thread via a dispatch signal source (AppDelegate.swift:203), so a write-stop-file action survives a hung main thread; crash/`kill -9` is covered by the beacon + pid check (modulo m4), and reboot persistence by leftover recovery (research §1 says `SleepDisabled` survives reboot).
- **Threat-model honesty.** §B6/§B7 update the ~30 contradicted README/site claims (brief §8 table), disclose EDR flagging (research §4, Elastic rule confirmed), stuck-on-after-power-loss, and "Awake runs one program". With M1/M3/M4 addressed the disclosure set is complete.
- **notifyutil thermal key** is readable without root (Libnotify reserves `com.apple.system.` as `rwr-r-`), so HW-36's read is feasible as planned.
