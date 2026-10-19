# Review r1: feature parity and product (0.3.1 PLAN r1)

**Totals: 2 Blockers, 7 Majors, 9 Minors.**

Lens: what Insomnia, Amphetamine (CDM and Power Protect) and Sleepless users expect, compared with Part B; and whether Part A delivers "a tab for each enabled module". I took the owner's decisions as given: tabs are a segmented control in the NSMenu that remembers the last tab, and lid-closed mode asks for a password on every start.

Sources: Insomnia cloned at HEAD (README, docs/spec.md, docs/lid-close.md, docs/release-validation.md, Sources/Insomnia/System/DisplayPower.swift); the xnu snapshot in `scratchpad/031/src/xnu`; Sleepless README (https://github.com/Aboudjem/Sleepless); docs/design/0.3/awake-parity.md; the repo at feature/v031.

---

## Blockers

### B1. The panel stays lit inside the closed lid in the default setup: `displaysleepnow` is ignored while a display assertion is held, and Snaptic holds one itself
**Evidence**
- PLAN §B3.1 (l.285) runs `pmset displaysleepnow` once, on the lid-close transition. §B3.1 "Display" (l.309) says "Display assertions don't stop `displaysleepnow`; HW-37 verifies."
- Insomnia measured the opposite on real hardware. `DisplayPower.swift:208-210`: "What `pmset displaysleepnow` does. Honoured only when no process holds a PreventUserIdleDisplaySleep assertion, and deferred by powerd for ~30 s after any wake." spec.md:430-437 says the same, and so does release-validation.md:~108-112: "display sleep via IORequestIdle … honoured only without PreventUserIdleDisplaySleep assertions and deferred ~30 s after a wake, so best effort."
- Snaptic's default session keeps the display on: `AwakeSessionOptions.init(display: .keepOn …)` (AwakeSession.swift:26), and `defaultOptions = AwakeSessionOptions()` (ConfigAwakeSessions.swift:238). Snaptic's own assertion therefore cancels its own display sleep request.
- Insomnia also found that with SleepDisabled set, the keyboard backlight stays on with the lid closed (lid-close.md:18-20). It needed an explicit wake on lid open (`IOPMAssertionDeclareUserActivity`, DisplayPower.swift:219-224). The plan covers neither.

**Why it matters:** this is the heat and battery hazard that research §1 [D] calls out, on the default path, on battery, in a bag. Every lid tool that ships has had to deal with it: Amphetamine 5.3 forces the display to sleep, and Insomnia sets brightness to 0.

**Fix (plan text)**
- B4, new bullet: "While lid-closed mode is on and the lid is closed, the session's effective display policy is `maySleep`. SessionController drops the display assertion through arbitration (a new `AwakeArbiterInput.lidShut`). The policy comes back when the lid opens."
- B3.1: request display sleep on every loop in which the lid is closed and `CGDisplayIsAsleep` is false, not only on the transition. This is because of powerd's 30 s deferral. It can be app-side `IORequestIdle` on IODisplayWrangler, which needs no root and no spawn (Insomnia does it this way). Keep the watchdog's call as the fallback when Snaptic hangs.
- On lid open, call `IOPMAssertionDeclareUserActivity` to wake the panel.
- Rewrite HW-37 as: "Lid closed on battery with (a) a Keep Display On session, (b) `caffeinate -d` running in another app: is the panel dark within 35 s? Is the keyboard backlight off? Does the panel wake on lid open?"
- README "Keeping awake with the lid closed" should state the limitation: another app's display assertion can keep the panel lit, and Other Apps lists it.

### B2. Ending lid-closed mode while the lid is closed does not put the Mac to sleep, and the plan keeps the session's assertion running
**Evidence**
- B4 (l.337): at the floor and at serious heat, "the app ends **lid-closed mode** (not the session)". B3.2 (l.321): at the cap it "keeps the session". B1 footer copy: "Snaptic turns it off at 10% battery or when your Mac gets hot."
- The kernel does not re-evaluate the closed clamshell when SleepDisabled is cleared. `kPowerEventUserDisabledSleep` only assigns `userDisabledAllSleep` (xnu IOPMrootDomain.cpp:8386-8389). Clamshell sleep runs only on `kLocalEvalClamshellCommand` (8886-8896), which is triggered by lid, AC and clamshell-mask changes (4563-4567, 6878, 8358, 9453), not by this setting.
- After restore, idle sleep is then the only path left, and the still-running session's PreventUserIdleSystemSleep assertion blocks it. The default session is Until Turned Off.

**Why it matters:** the cap, the battery floor and the heat cutoff all turn sleep back "on" while a closed MacBook keeps running in the bag. Only the app-side 5% hard floor and the user's session floor still apply. That is exactly the scenario the root floor exists to prevent, and the user-facing promise is false.

**Fix (plan text)**
- B4: "When lid-closed mode ends for any reason other than the session's own end while the lid is closed and `lidWillSleep == true`, the session ends too." The reason is the lid end reason; see M7.
- B3.1 `restore()`: after `pmset -a disablesleep 0`, if `AppleClamshellState` is Yes and `AppleClamshellCausesSleep` is Yes, run `pmset sleepnow`. That stays within root's existing write set, which is pmset.
- Correct the notice text "…so your Mac will sleep when you close the lid", which assumes the lid is open.
- Add HW-41: "Cap, floor and heat ends with the lid closed on battery: the Mac is asleep within 30 s (`pmset -g log`)."

---

## Majors

### M1. Low Power Mode blocks lid-closed mode, which is the opposite of Insomnia and of Awake's own default
**Evidence**
- B2 (l.215): refuse to start if Low Power Mode is on. B4 (l.338): lid-closed mode ends "when **Low Power Mode turns on**".
- Insomnia turns Low Power Mode **on** at lid close and below 40% (spec.md:610-624, README:115-120).
- Awake by default keeps running in Low Power Mode: `endOnLowPowerMode = false` (AwakeGuards.swift:62), and README:208 says "Otherwise Awake keeps running and says so once".

**Why it matters:** many laptop users set Low Power Mode to "Only on Battery". For them, the owner's headline case ("even on battery") never works, and the refusal toast blames the setting that saves battery and reduces heat. Only Sleepless steps aside in Low Power Mode, and it has no session model.

**Fix:**
- Remove "Low Power Mode is on" from the B2 refusals.
- Remove the B4 sentence "lid-closed mode also ends when Low Power Mode turns on".
- Lid-closed mode follows the session's `endOnLowPowerMode` like everything else.
- Add to README: "Low Power Mode is a good idea with the lid closed."
- Do not add `pmset lowpowermode` to the root script; list that under "Not included".

### M2. Cancelling the password prompt leaves an Until Turned Off session running that the user never asked for
**Evidence**
- B1 (l.167-178): with no session running, the item "starts the default session (preset) with lid-closed mode". "Cancel leaves the session running without lid-closed mode."
- The default preset is Until Turned Off (`defaultPreset`, ConfigAwakeSessions.swift:287-290) with the display kept on.

**Why it matters:** the user clicked one thing, said no to it, and the Mac now stays awake indefinitely with the screen on. The same happens on the 120 s timeout and on verify failure.

**Fix:** add to B1: "If this click started the session, a cancel, a timeout or a failed start ends that session with reason `.user` and no end toast. The menu returns to idle." Or start the session only after the verify succeeds, with a "Starting…" header state while the prompt is up.

### M3. The menu item starts an indefinite session whose lid part silently ends at 8 h (open question 6)
**Evidence**
- B1 (l.167): the item uses the default preset, which is Until Turned Off. The cap is 8 h (l.160).
- Insomnia sessions are "Never a toggle", always timed (spec.md:13, 96-104). Amphetamine's closed-display mode is a session option chosen together with the session's length (awake-parity.md §1.3). Sleepless offers a 1 h or 2 h auto-off.

**Why it matters:** users of all three tools pick "how long" when they choose "lid closed". Here they get "until turned off", the header says "until 6:40 PM" because of the cap, and the cap end (B2) then catches them in a bag.

**Fix:** answer open question 6 as follows.
- While idle, the row is a submenu "**Keep Awake with Lid Closed ›**". It lists the presets, including Until Downloads and Tasks Finish, which suits the agent use case, followed by "Custom…", which opens the panel with the checkbox ticked and covers While an App Is Running.
- The submenu's first row is a disabled note "Asks for your password", so the presets need no ellipsis each.
- While a manual UI session runs, the row is "Also Keep Awake with Lid Closed…".
- One gesture still means one prompt.

### M4. Changing the session drops lid-closed mode, so each change costs another password
**Evidence:** B2 "What ends lid-closed mode" includes "replacement by another session" (l.199).

**Why it matters:** with lid-closed mode on, the user picks For 2 Hours or Custom… from Start Session ›. Lid-closed mode turns off silently, and the next lid close sleeps the Mac. Getting it back needs a new prompt, because a 5-minute auth grace doesn't carry across osascript processes (research §4).

**Fix**
- B2: "A replacement started by a direct UI action in this process (menu or Settings) keeps lid-closed mode. The watchdog is untouched, and `until` is recomputed."
- Replacements from other sources end it with the toast "Lid-closed mode turned off." Today only hotkey starts can replace, because CLI starts are refused while a UI session runs.
- Add a row to the AwakeLidGate table.

### M5. Where the lid rows go in the menu is unspecified: no Kit row model, no compact placement, no Controls entries
**Evidence**
- B1 (l.164) says "The Awake menu" only. `AwakeMenuModel.rows` (AwakePresentation.swift:404-437) has no lid row.
- A1 (l.54) keeps the compact section when Awake is the only shared module. Awake's own icon menu (IndicatorController) uses the full rows.
- B3.3's leftover row is "in the menu", without a position.
- Part B has no Controls section: there are no ids for the menu rows, the Awake page button, or the Lid Closed group (toggle, stepper, picker, warning row) with their SearchSpecs. This breaks the ground rule (l.19) and the key cross-check for the new `AwakeLidConfig` leaves.

**Fix**
- Add new `AwakeMenuRow` cases to Kit: `.lidClosed(state: idle|on)` and `.lidLeftover`.
  - `.lidLeftover` goes directly after `.header`.
  - `.lidClosed` goes after Keep Display On (active) or after startDefault (idle), before Start Session ›.
  - Both appear in the compact and full rows, covering the Awake tab, Awake's own icon and a single shared module.
  - Add tests to AwakePresentationTests.
- Add a B6 "Controls" list:
  - `menu.awake.lidClosed`, `menu.awake.lidLeftover` and `menu.awake.lidRestore` in `AwakeMenuRowsControls`;
  - `awake.page.lid.allow`, `.cap`, `.floor`, `.bundleWarning` and `awake.page.status.lidClosed` in `AwakePageControls`, with `when: [.awakeFeature(.lidClosed)]` and SearchSpecs;
  - `awake.custom.lidClosed` in `CustomSessionPanelControls`.

### M6. Tabs hide other modules' warning and recovery rows
**Evidence**
- The stacked menu showed every module's status rows. Once a tab is remembered, the following are visible only on their own tab:
  - Displays' degraded, paused + Resume, and helper stopped + Restart Snaptic rows (DisplaysMenuBuilder.swift:43-80);
  - Switcher's "Open Accessibility Settings…";
  - Awake's "Sleep is still turned off from an earlier lid-closed session" (B3.3, l.329);
  - whether an Awake session is running, when Awake is set to Show in Snaptic Menu.
- A1 (l.65) keeps only the Safe Mode rows above the tab bar.

**Why it matters:** a user who lives on the Displays tab never sees that sleep has been left off for days, or that the switcher lost its permission. This is a regression from 0.3 that comes directly from tabs.

**Fix:** this keeps "remember the last tab".
- Add `MenuTabs.attention(sharedIDs:flags:) -> Set<ModuleID>` to Kit. A segment with attention shows a 10 pt `exclamationmark.circle` image, and VoiceOver adds "needs attention".
- While Awake governs, the Awake segment shows the active glyph.
- The lid leftover row, which is about safety, renders above the tab bar together with the Safe Mode rows, whatever tab is selected.
- Add both to HW-32.

### M7. Lid-closed mode ends exactly when nobody is looking, and its reason survives only in a 10-second toast
**Evidence**
- B5 (l.365): "new `AwakeEndReason` values are not needed, because lid-closed mode isn't a session". The header's `lastEnd` line, which is kept for 12 h, comes from session end reasons (brief-awake §3), and History gets only a `lidClosed` flag.
- Toasts expire after 10 s (ToastPresenter.swift:81).
- Insomnia posts a Notification Center notice for every end and floor action (spec.md:1050-1057).

**Why it matters:** the cap, the floor, heat, and "Another app turned sleep back on" all happen with the lid closed. When the user opens the lid, the only trace is a line in Recent Notices ›.

**Fix**
- Add `AwakeLidEnd {cap, battery, heat, otherApp, verifyFailed, quit}` with a time to the runtime.
- The Awake header and status row show "Lid-closed mode ended at 20% battery at 3:12 AM." for 12 h, and it is cleared when lid-closed mode next starts.
- The History entry gets `lidEnd` (lossy).
- The toast stays as it is.

---

## Minors

### m1. The opt-in is hidden in Settings, and the existing hint points the other way
**Evidence**
- B1: "Allow Keeping Awake with the Lid Closed" exists only in Settings › Awake › Lid Closed, and the menu shows nothing while it is off.
- The Settings status row still says `lidRoute`, "To keep it awake with the lid closed, connect power and an external display." (AwakePresentation.swift:621).

**Fix:** on a MacBook with the setting off, append " Or allow keeping awake with the lid closed below." to `lidRoute`, linking to the group. Put the group directly under the battery guards on the Awake page.

### m2. There are two battery floors
**Evidence**
- Awake has a battery floor (default 20%, 5-50), and the lid picker adds another (10/20/30, default 20%).
- With equal defaults both fire at once, so B4's "a step earlier" is false.
- Insomnia has one end floor (spec.md:618-621).

**Fix:** replace the picker with a derived floor, `max(10, awake floor if enabled else 20)`, and say so in the group footer. Or keep the picker with the default "Same as Awake (20%)".

### m3. Cap range (open question 4)
An 8 h default and a 20% floor are fine. The 24 h maximum (script `CAP ≤ 86400`) rules out the lid-closed home-server case on power, which Insomnia allows for up to 30 days.

**Fix:** allow 1-72 h, and state in README that the cap is a dead-man limit on top of the beacon.

### m4. The menu bar indicator shows lid state only in its tooltip
**Evidence**
- B1 "Status everywhere" changes only the tooltip. Hover and tracking are unreliable on macOS 27 (brief-menu §8).
- Amphetamine and Sleepless both change the icon (Sleepless adds a dot on battery).

**Fix:** add an indicator glyph variant, the active glyph with a small badge, while lid-closed mode is on, and add ", lid closed" to the accessibility label.

### m5. The lid line can be cut from the menu header
**Evidence:** `AwakeDetail.lines` keeps the primary line plus only the first extra (AwakePresentation.swift:263, 325-328).

**Fix:** while lid-closed mode is on, the "Stays awake with the lid closed until…" line ranks first among the extras.

### m6. `lidWillSleep` doesn't reflect SleepDisabled
**Evidence:** `AppleClamshellCausesSleep` comes from `shouldSleepOnClamshellClosed()`, which ignores `userDisabledAllSleep` (xnu IOPMrootDomain.cpp:4461-4470). Gating the warning on the `lidWillSleep` value (B1, l.170) still shows "Closing the lid will put your Mac to sleep." during lid-closed mode, unless the lid state is checked as well.

**Fix:** state the rule as `lidWarning = lidWillSleep == true && !lidClosedOn && (onBattery || !external)`, with a Kit test.

### m7. A resumed session loses lid-closed mode silently
**Evidence:** with `resumeAfterRestart` (on by default), a relaunch resumes the session without lid-closed mode (B2).

**Fix:** on resume, set the M7 `lidEnd = .quit`, so the header says "Lid-closed mode turned off when Snaptic quit."

### m8. A menu item whose title flips is harder to read than a checkmark
**Evidence:** "Allow Sleep When Lid Closes" replaces the original title in the same menu that uses "✓ Keep Display On" (AwakeMenuRows.swift:61).

**Fix:** while it is on, show "✓ Keep Awake with Lid Closed". Choosing it turns lid-closed mode off without a prompt, and the ellipsis appears only while it is off. This matches Amphetamine's per-session toggle.

### m9. Footer items and copy under tabs
**Evidence**
- "More Display Features…" sits in the shared footer, so it shows under the Switcher and Awake tabs too (A1 mockup).
- The `MenuBarPage` line "it shows a tab for each" doesn't say that modules set to their own icon or to Don't Show get no tab. The owner asked for "a tab for each enabled module".

**Fix**
- Show "More Display Features…" only on the Displays tab, or in the single-module Displays menu.
- Change the summary to: "When two or more modules are set to Show in Snaptic Menu, the menu shows a tab for each."

---

## Checked and fine

- **Owner's ask against the defaults:** a fresh install puts all three modules in the shared menu at rest and during a session. Awake's Show When Active gives the compact entry at rest and keeps it while active (MenuLayout.swift:126-145; MenuLayoutTests.swift:26-43), so the default menu has three tabs, matching the owner's screenshot. Awake is a tab by default.
- **Remembering the last tab** is fine, given M6. In the default setup, Awake's own icon appears while a session runs, so session controls are one click away from any tab, and the shared glyph turns active (N11). Auto-switching isn't needed.
- **Fallback to the first tab:** the stored id is kept, decoding is lenient, and the selection is kept out of `ModulesConfig` (no re-plan, no backup).
- **Turning lid-closed mode off needs no password** through the stop file. Amphetamine's script without Power Protect prompts at both start and end, so this is better on that count. Only leftover recovery prompts.
- **CLI:** `stop` works and `extend` is refused. A `lidClosed` status field matches the "anything may turn sleep back on" model.
- **Start refusal below `floor + 5` and the 10% root floor** are in line with Insomnia (10%) and Sleepless (15%).
- **Re-reading SleepDisabled after 5 s** and treating a journal-less SleepDisabled as someone else's both match Insomnia.
- **Scope:** I found no creep beyond what the two asks need. The ⌘1-⌘3 items, the label fallback, Settings ⌘, following the tab, the History flag, and the bundle warning (precedent: README:543) are all small and justified. Insomnia's app freezing, muting and private brightness work is rightly left out.
