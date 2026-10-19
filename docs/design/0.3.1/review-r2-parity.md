# Review r2: feature parity and product (0.3.1 PLAN r2, 8fd1b27)

**Totals: 0 Blockers, 2 Majors, 9 Minors, plus a cuts recommendation.**

All 16 of my r1 findings are fixed, though two of the fixes bring new problems (r2 M1 and m3).

---

## r1 findings: fixed or not fixed

| r1 | Finding | Status | Where in r2 / note |
|---|---|---|---|
| B1 | `displaysleepnow` was defeated by Snaptic's own display assertion | **Fixed** | B3.3: effective `maySleep` while the lid is shut; app-side `IORequestIdle` on every tick; wake on lid open; HW-30 covers (a) Keep Display On and (b) `caffeinate -d`. The `maySleep` rule is too broad; see new M1. |
| B2 | A closed Mac kept running after the mode ended | **Fixed** | B3.2 `cleanup` runs `sleepnow` when the lid is shut and the lid would sleep the Mac; B3.3 also ends the session (`.lidEnded`); HW-34. |
| M1 | Low Power Mode blocked or ended the mode | **Fixed** | B2, last paragraph. |
| M2 | Cancel left a session running | **Fixed** | B1/B3.1 step 6: the session starts only after verify, and Cancel starts nothing. |
| M3 | Indefinite session plus a silent 8 h end | **Fixed** | B1 idle submenu of presets plus Custom…. |
| M4 | Replacing the session dropped the mode | **Fixed** | B2 gate: "Keep" for a direct-UI replacement. |
| M5 | No row model, placement or controls | **Fixed** | B1 row cases in all three styles, with positions; B7 table. |
| M6 | Tabs hid warnings | **Fixed** | A1 attention and active marks; host-level leftover rows above the tabs (B3.4). The "paused" definition needs tightening; see new m4. |
| M7 | Silent end | **Fixed** | `AwakeLidEnd`, a 12 h header line, History `lidEnd`. |
| m1 | Opt-in was hidden | **Fixed, though harder to find** | `lidRoute` now points to Advanced. The toggle moved deeper, into the Advanced… sheet. The route line shows only while the lid warning is up. See new m6. |
| m2 | Two floors | **Fixed** | One derived floor (B1, B5 `floor(awakeGuards:)`). |
| m3 | 24 h cap | **Fixed** | Options run up to 72 h. See the cuts section for whether the picker is needed at all. |
| m4 | Indicator showed state only in a tooltip | **Fixed** | Badge variant, plus the N11 suffix. |
| m5 | Header line priority | **Fixed** | The lid line is the first extra. |
| m6 | `lidWillSleep` ignored SleepDisabled | **Fixed** | Warning rule `… && !lidModeOn …`, with a Kit test. |
| m7 | Resume dropped the mode silently | **Fixed** | The gate ends the mode on resume, and the header says so. |
| m8 | Title-flipping item | **Fixed** | B0 "✓ Keep Awake with the Lid Closed". |
| m9 | Upgrade item, Menu Bar copy | **Fixed** | A1 footer, A3 copy. |

---

## Majors

### M1. With the lid shut, `maySleep` also applies when an external display is in use, so "Keep Display On" is silently ignored on the screen the user is looking at
**Evidence**
- B3.3 says: "While the mode is on and the lid is closed … the session's **effective** display policy is `maySleep`". There is no condition on external displays.
- The `IORequestIdle` request in the next bullet *is* limited to "no external display is attached". So the plan already accepts that with an external display the built-in panel is not the problem, but it drops the user's display assertion anyway.

**Why it matters**
- Lid-closed mode makes a new setup possible: a closed MacBook driving an external monitor **on battery**, which macOS's own clamshell mode doesn't allow. Users of Amphetamine's closed-display mode use exactly this. The same happens when the user docks on AC with the mode already on.
- A user who chose Keep Display On, for a dashboard, a presentation, or a long build log, now gets an external display that sleeps after the idle timer, while the menu still shows "✓ Keep Display On".
- HW-30 tests only the no-display case.

**Fix (plan text)**
- B3.3: "`AwakeArbiterInput.lidShut` is true only while the lid is closed **and no external display is attached**." Re-evaluate on screen changes; the trigger already exists for the lid warning.
- Add HW-30 (c): lid closed on battery with one external display and a Keep Display On session. The external display stays on, and the built-in panel is off (record whether macOS turns it off by itself here).

### M2. Leftover recovery has no "keep it off" answer, so a user who declines is nagged in every menu and can never use the mode again
**Evidence**
- B3.4 offers only "Turn Sleep Back On…" and "Not Now", where "Not Now" hides the rows for this launch.
- The journal is cleared only when `SleepDisabled` reads 0.
- B2 refuses turn-on whenever "An earlier lid journal still exists".
- r1 had "Leave It Off", which cleared the journal. r2 dropped it without a §R entry.

**Why it matters**
- Some users keep sleep disabled on purpose: a Mac mini-style server, or someone who has since set `disablesleep 1` themselves.
- For them, every launch puts "Sleep Is Turned Off / Turn Sleep Back On…" at the top of **every** Snaptic menu.
- Lid-closed mode is also refused forever with "Try again in a minute", which is false.
- It is also unclear whether "Not Now" hides the menu rows or only the Awake page rows.

**Fix**
- B3.4: add **"Keep Sleep Off"**. It clears the journal, removes the rows everywhere, and from then on reports the value as "another app or command", as today. No prompt, no root.
- "Not Now" hides the rows in every menu and on every page until the next launch.
- B2: the toast for a leftover (not pending) journal becomes "Sleep is still turned off from an earlier lid-closed session. Choose Turn Sleep Back On… first."

---

## Minors

### m1. Nothing warns before the cap turns the mode off, and with the lid shut the cap now means instant sleep
**Evidence**
- B3.3 Cap: when the lid is shut, the session ends and `sleepnow` runs.
- Awake's 5-minute reminder (SC:958-973) fires only for the *session* end. A cap end can come earlier: for example, Until Turned Off or Until Downloads and Tasks Finish, with the default 8 h cap.

**Why it matters:** a user on battery driving an external monitor with the lid closed (M1's setup) is put to sleep mid-work with no warning. The battery-floor and heat ends are safety ends and are fine to be abrupt; the cap is not.

**Fix:** when the cap ends first, show a toast 5 minutes before it: "Lid-closed mode turns off in 5 minutes. If the lid is closed then, your Mac goes to sleep." No Add Time button: extending needs a new password, so the toast just says that choosing Keep Awake with the Lid Closed… again restarts it.

### m2. There is no feedback between the end of the password dialog and the session appearing
**Evidence:** the session starts only after verify, which polls for up to 10 s (B3.1 step 6). The menu is closed by then, the indicator stays idle, and "Waiting for Password…" is visible only if the user reopens the menu.

**Why it matters:** this is usually under 1 s, but on a slow powerd it reads as "it didn't work", and the user clicks again.

**Fix:**
- While the state is `verifying`, the Awake indicator (or the shared glyph) shows its active glyph at reduced opacity.
- If verify takes more than 2 s, a toast "Turning on lid-closed mode…" shows.
- Rename the disabled rows to "Turning On…" while `verifying`, so "Waiting for Password…" is used only while `authorizing`.

### m3. The writable-bundle warning shows for almost every user, and they can't act on it
**Evidence**
- README:528: the release install is "unzip it, and drag Snaptic to Applications". That leaves the bundle owned by the user, so B1's warning row shows.
- The only remedy given is `INSTALL=1`, which exists only for source builds (B6).
- B6's own reasoning is that the warning adds no protection.

**Why it matters:** a red warning under the toggle, for nearly everyone, with nothing to do about it, teaches users to ignore warnings. It also makes the feature look unsafe in the default install.

**Fix**
- Keep warn-not-refuse, but render it as the toggle's secondary help text, not a warning `StatusRow`.
- Show it only while the toggle is on.
- Learn More… goes to a README paragraph that also gives the release-zip remedy: `sudo chown -R root:wheel /Applications/Snaptic.app`. Check whether this matches the Permissions page's existing advice, which B1 says it reuses.

### m4. "Paused" Displays would keep a permanent attention mark
**Evidence**
- A1 lists "Displays: degraded, paused, or helper stopped".
- DisplaysMenuBuilder.swift:43-78 has two kinds of pause:
  - the panic latch ("Display Automation Is Paused"), which needs action;
  - `otherApps.pausedDisplayFeatures` ("Paused While MonitorControl Runs"), which is a steady state for anyone who runs MonitorControl or BetterDisplay alongside Snaptic.

**Fix:** define `menuAttention` for Displays as `degraded || panic.isLatched || unprotectedReason != nil`. Other-app pauses are excluded, and Kit's `attention` truth table says so.

### m5. While a lid start is authorizing, a normal start from the same menu can be replaced when the password succeeds
**Evidence**
- B3.0 disables only the lid rows. "Start Session ›", the header switch and Keep Awake stay live.
- B3.1 step 6 then starts the lid preset for an "idle start". The token rule's exception "(unless the mode was keeping a session that hasn't started yet)" lets that start go ahead, and it replaces the session the user started meanwhile, with "Keep" semantics.

**Fix:** B3.0: "Any manual start or Turn Off while `authorizing` or `verifying` an idle start supersedes the lid request: the token is stopped, and the B3.0 exit path runs silently."

### m6. After turning the option on, nothing says where to use it
**Evidence:** the toggle is in Awake › Advanced… (B1), and its help text says only "Only in sessions you start in Snaptic. Asks for an administrator password each time."

**Fix:** change the help text to "Choose Keep Awake with the Lid Closed in the Awake menu. Asks for an administrator password each time." Optionally show a one-time toast after the toggle turns on: "Lid-closed mode is ready. Choose it from the Awake menu."

### m7. HW-30 doesn't cover the external-display case
**Evidence:** it is unknown whether macOS turns off the built-in panel when the lid closes with an external display on battery while SleepDisabled is set. B3.3 assumes it does, because there is no `IORequestIdle` with an external display.

**Fix:** add the case to HW-30. This is the same check as M1's (c).

### m8. The submenu's note row reads like a menu command
**Evidence:** "Asks for an Administrator Password" is in Title Case as a disabled first row.

**Fix:** use a sentence-case status row, "Asks for an administrator password", the same style as the header detail lines. Alternatively, drop the row and put the text in the submenu item's tooltip and accessibility help, since the toggle's help text already says it.

### m9. Restart behaviour for a resumed session isn't stated in the header line
**Evidence:** "Lid-closed mode turned off when Snaptic quit." (B2) also covers a resumed session after a restart. Restart with the mode on is the leftover path, and the header text there should differ.

**Fix:** after a reboot, use `AwakeLidEnd.quit` only when `SleepDisabled` reads 0. Otherwise the leftover rows already explain the state, and the header line is suppressed.

---

## Is it still "an option, like Insomnia"? Cuts I recommend

**What the user sees is still simple:**
- one toggle in Advanced;
- one submenu (or one checkmark row while a session runs);
- a password;
- a badge on the indicator.

The size of the plan comes from the safety layers (watchdog, recovery, gate), and those are needed. A few user-facing additions, however, cost more than they return. In order of value:

1. **Drop the "Turn off after" picker; use a fixed cap.** The idle submenu now makes the user pick a length, so the cap matters only for Until Turned Off and task-bound presets.
   - Use a fixed 24 h cap, or 72 h if the owner wants the server case, and say "for up to 24 hours" in the submenu note and the prompt.
   - This removes a setting, `AwakeLidConfig`, its backup and monotonic rules, and the B7 control `awake.advanced.lidCap`.
   - The "until 6:40 PM" header line remains only for that case.
2. **Cut History's lid additions to one flag.** Keep `lidClosed`. Drop `lidEnd`, the " · Lid closed" subtitle, and the Start Again tooltip; the 12 h header line already explains ends.
3. **Cut the tab-separated CLI field.** Keep the JSON key only. Scripts that parse the tab-separated line by position have to deal with a new trailing field.
4. **Keep:**
   - the attention marks;
   - the host-level leftover rows;
   - the Custom… toggle, since While an App Is Running needs it;
   - the Settings pull-down items, since W16 requires a Settings path for every action;
   - the ⌘n items, since C4 requires a keyboard path.

---

## Checked and fine (new in r2)

- **Click count for the idle submenu:** with a default 3-tab menu on the Awake tab, it is icon → hover "Keep Awake with the Lid Closed ›" → choose a preset → Touch ID or password. That is 2 clicks plus one hover, plus one more click if another tab is remembered. This is on par with Amphetamine (icon → Start New Session › → length, with closed-display mode as a session option). Insomnia is click → type → Enter, but it has a sudoers rule; that is the owner's chosen trade-off.
- **Choosing the length together with "lid closed"** is what both Insomnia and Amphetamine users expect.
- **Session starts only after verify** keeps Cancel truly side-effect-free. Polling at 0.5 s makes the normal case feel instant; m2 covers the slow case.
- **`sleepnow` gating:** it runs only when `AppleClamshellState` is Yes and `AppleClamshellCausesSleep` is Yes, so true clamshell mode (AC plus external display) is not put to sleep. On battery with an external display the Mac does sleep at the end; that matches macOS's own rule and is acceptable for safety ends (m1 covers the cap).
- **Single derived floor:** with the defaults, the lid end and the session's battery guard both fire at 20%. The lid end is recorded first and then the session ends because the lid is shut, so the two give one coherent story.
- **Low Power Mode** no longer blocks the mode, and the README recommends it.
- **Host-level leftover rows in every menu** are the right call for a state that disables sleep system-wide (once M2 adds a way to keep sleep off).
- **Warn instead of refuse for the bundle** is right on the merits. Only how it is presented needs changing (m3).
- **Tabs:**
  - ⌘, is unchanged.
  - "More Display Features…" moved to the Displays tab.
  - The widest tab is measured at build, so the segment never moves under the pointer.
  - The tab is remembered, with a first-tab fallback.
  - Single-module menus keep their header.
