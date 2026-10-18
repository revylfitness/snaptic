# Review r4: product + parity + design (PLAN.md r4)

**Totals: 0 Blocker, 1 Major, 7 Minor.** Setup: default config, 1 built-in + 1 DDC external, Awake Show When Active.

## 1. Round-3 verification (review-r3-product)

**All 5 Majors resolved.** M3 and M4 use lead mechanisms instead of the ones I proposed; both are acceptable products.
- **M1** §5.3, §5.4, §2.14 `verbTitle`: the first-level item is the default preset as a verb ("Keep Awake Until Turned Off") and shows only while idle. Turn Off Keep Awake takes its slot while active. Until Turned Off is back in Start Session ›, and ✓ marks only the running preset. Rows: idle 6, active 9. The §5.2 mockups are drawn per state.
- **M2** §4.3 status row Pause Rules ▾; §5.2/§5.4 Rules › appears whenever a rule exists; §4.4 #17. Pausing rules is now reachable at rest.
- **M3** §2.5: the toast "Rules can still keep your Mac awake." [Pause Rules], plus the detail "Then “Desk dock” keeps it awake." Clear (see Minor 3).
- **M4** N17, §2.10: holds stack, up to 8, and are never refused because a UI session is running. The CI-build journey works.
- **M5** §4.3 Customize Displays Menu: disclosure groups, a filter, three-way pop-ups only for per-display items, the collapsed "needs features that are off" row, and the §4.8 rows corrected.

**All 16 Minors resolved:** m1–m11 in §4.3 and §5.2–§5.4; m12 §2.14; m13 §4.1/§4.6 (two §4.3 cells still read "Restore Defaults…", but `RestoreDefaults.title` scopes them); m14 §4.2; m15 §2.5/§5.3; m16 §2.10/§4.3/HW-15 (≤ 24 lines; count 20).

## 2. Journeys re-run (default config)
Every r3 journey now succeeds:
- Keep awake 1 h: 2 clicks + hover.
- Build hold during a UI session: stacks.
- Stop with a rule active: toast explains why the Mac stays awake.
- Rule "power AND display": about 9 clicks.
- Pause rules at rest: icon → Rules ›.

One new failure: starting For 2 Hours with the menu-bar items hidden (M1).

## 3. Major

### M1. The Settings fallback can't start any session except the default (§4.3 status row, §5.5)
§5.5 says "every Awake and Displays function is reachable from Settings (Awake status row with Keep Awake / Options ▾ / Turn Off)". §4.3 says the status row "reaches everything when the status item is hidden, 26/27". But the idle row offers only **Keep Awake**, which starts the default preset. A user whose Snaptic and Awake items are hidden can't start For 2 Hours, a custom session, While an App Is Running or Until Downloads and Tasks Finish. The only workaround is to change Default session first. The preset hotkeys are unbound by default.

**Fix (small, Apple precedent):** make Keep Awake a pull-down with a primary action (SwiftUI `Menu(primaryAction:)`, like Mail's toolbar buttons):
- A click starts the default preset.
- ▾ lists the presets in order, then a separator, then While an App Is Running ▸ (a flat list is fine in a pull-down), then Custom….
- While a session is active, put the same list in Options ▾ as "Replace With ▸".

The status-action budget is unchanged. Add the row to the Awake control table and to HW-14.

## 4. Minor

1. **Holds and Turn Off contradict each other.**
   - §2.10 says "nothing but its own end conditions ends it (a UI Turn Off leaves holds running and says so)".
   - §2.5 `turnOff` and §5.3 say Turn Off and the switch **end the hold stack when holds govern**.
   - The §5.3 behavior is right: the switch is on, so off must mean off. Amend §2.10 to list "a user Turn Off while holds govern" among the hold's end conditions; the client gets "Awake hold ended in Snaptic.", exit 0.
   - In the holds-only state, Turn Off Keep Awake and End Command-Line Holds are then the same action. Show only Turn Off Keep Awake, and keep End Command-Line Holds for when another source governs.
2. **Preset order contradicts the menu.**
   - §2.14 sets the default `presets` order to 30 min, 1 h, 2 h, 5 h, Until Turned Off, Until Downloads…, and Start Session › lists "all presets in order".
   - §5.3 draws Until Turned Off first.
   - Make the §2.14 default order Until Turned Off, 30 min, 1 h, 2 h, 5 h, Until Downloads and Tasks Finish (the derived ids are unaffected).
3. **The Turn Off toast's action is heavier than needed.**
   - After a manual Turn Off over an active rule, [Pause Rules] pauses **every** rule for 1 h.
   - The proportionate action is **Turn Off “Desk dock”** (= `manualEnd`, which respects that rule's "After I turn it off").
   - Use that as the toast's default action, and keep Pause Rules as the second action.
4. **The status row's precedence while paused is undefined.**
   - §4.3 draws "paused: Rules are paused until 4:00 PM. [Resume]" as its own state.
   - A manual session can run while rules are paused. Specify that the primary line follows the session, the paused text becomes a detail line ("Rules are paused until 4:00 PM."), and Resume replaces Pause Rules ▾ in the same slot. Apply the same rule to the Rules › subtitle in §5.3.
5. **0.2 regressions for sleep-prevention users.**
   - The 0.2 CLI verb `prevent-sleep` disappears in step 3, so scripts get a usage error.
   - A bound `d.sleepPreventionToggle` hotkey is silently lost; §4.8 has no row that carries the combo.
   - Fix: keep `prevent-sleep` as a stub that prints "Moved to Awake: use `snaptic awake …`." and exits 2 until 0.4. When M1 migrated a rule, move the combo to `awake.pauseAutomatic` (the closest meaning) if that hotkey is unbound; otherwise drop the combo and say so in a Recent Notice.
6. **"Keep the display on" (Awake page) applies only to some sessions.**
   - When it is on, Until Downloads and app sessions still let the display sleep (per-kind defaults); only the help text says so.
   - Either label it for what it does ("Keep the display on during timed sessions"), or make the per-kind default follow this switch and drop the exception sentence.
   - The second option is simpler and matches Amphetamine's single "Allow display sleep" default.
7. **The Customize Displays Menu accordion isn't standard macOS behavior.**
   - "Expanding a group collapses the others" doesn't happen in System Settings or Finder disclosure groups, and it fights the filter, which expands several groups.
   - Keep independent disclosure groups (Per Display expanded by default) and count the List as 1 under §4.2, which is the counting r3 proposed. The ≤ 25 rule then holds without the accordion.

## 5. End-to-end assessment
- **Parity:** complete for the stated scope (§1.4).
- **0.2 controls:** coverage is mechanically enforced (N16, §4.8.1).
- **Settings:** within budget, with live slider fields and reset, search, and help copy.
- **Menus:** native, keyboard-reachable, within a row budget, with correct ✓ semantics.
- **Indicators:** sessions, rules and holds are each explained in the detail line.
- **Modularity:** each part has one owner.

M1 and the minors are local edits to §2.5, §2.10, §2.14, §4.3, §4.6 and §5.3. No further round is needed.

**Verdict: Ready with fixes**
