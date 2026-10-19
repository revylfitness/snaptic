# Review r3: parity + design/UX (PLAN.md r3)

**Totals: 0 Blocker, 5 Major, 16 Minor.** Setup: defaults, 1 built-in + 1 DDC external.

## 1. Round-2 verification

**Parity r2: 19/19 resolved** — B1 §4.8 "0.2 menu" (46 ids) + §5.2; M1 §4.8/§6.4; M2 N9/§2.5; M3 §2.10; M4 §4.3 Options ▾, §5.3, §5.4; M5 N11/§5.2; M6 §4.6 M10, §5.2; m1–m12 §2.5, §4.3, §4.7, §4.8, §5.2, §5.3. Side effect: m10 (Pause out of Settings) plus §5.4 (no rules row) leaves Pause unreachable at rest (M2).

**Design r2: 21/21 resolved** — M1/M2 §5.3 (`AwakeMenuRows`, 6/10; the lead's first-level "Until Turned Off" causes M1); M3 C7, §4.2, §4.3, §4.6; M4 §4.3, §4.4 #17; M5 C2, §4.3; M6 mockup C, 720; M7 mockup D; m1–m14 (m2, m13 partly rejected, acceptable). Regressions: ↺ drawn at the default "Battery level [20%]" (m8; Minor 1); §2.14 comment still says "Show" pop-up (Minor 12).

## 2. Journeys (default config)

| # | Journey | Path | Clicks | Friction |
|---|---|---|---|---|
| 1 | First run | Welcome → Choose Modules → Displays chips → Permissions (if needed) → Done | 4–5 | None; the Awake row explains the icon appears only while active |
| 2 | Upgrade, migrated | Toast at first activation → Show in Settings | 0–1 | None |
| 2b | Upgrade, not migrated | General card or "New" badge → Turn On Awake | 1 | None |
| 3 | Keep awake 1 h | Snaptic icon → Start Session › → For 1 Hour | 2 + hover | ✓ on a non-running item (M1) |
| 4a | While downloading | icon → Start Session › → Until Downloads and Tasks Finish | 2 + hover | No feedback on when it will end (m15) |
| 4b | While building (CLI) | One-time: General › Command-line control → Copy Install Command → Terminal; then `snaptic awake hold` | — | Refused if a UI session runs (M4) |
| 5 | Stop | cup → Turn Off Keep Awake | 2 | Mac may stay awake under a rule with no notice (M3) |
| 6 | Extend | cup → Add 1 Hour | 2 | None |
| 7 | Rule "on power AND external display" | icon → Snaptic Settings… → Awake → Add Rule… → kind ▾ Display → (value) → + → kind ▾ Power → value ▾ On adapter → Done | 11–13 + name | Blank sheet, required-looking Name, "Start when" copy (m5) |
| 7b | Pause rules | Not possible at rest; the hotkey is unbound by default | ∞ | M2 |
| 8 | Brightness from menu | icon → drag | 1 + drag | None |
| 9 | Change resolution | icon → device › → mode | 2 + hover | "Larger Text / More Space" items are undefined (m10) |
| 10 | Find a setting | type in sidebar search → result | 1 + typing | No ⌘F stated (m14) |
| 11 | Restore a default | Slider: ↺. Toggle/pop-up: context menu. Page: Advanced… → Restore Defaults… → confirm | 1 / 2 / 3 | Page-wide reset sits in a sheet named Advanced (m13) |

## 3. Major

### M1. The first-level "Until Turned Off" is a fragment, duplicates the detail line, and diverges from the switch (§5.3, §5.4, §5.2 mockup)
- No verb; in an active indefinite session the §5.2 mockup shows detail "Until turned off" right above action "Until Turned Off".
- The switch starts the **default preset**, the item always indefinite: with default For 1 Hour, two adjacent starts differ.
- "✓ = default or running" checks an idle item (Apple: ✓ = current state); the mockup ticks For 1 Hour although C10's default is Until Turned Off.

**Fix:**
- Replace the item with the **default preset as a verb phrase**: "Keep Awake Until Turned Off" or "Keep Awake for 1 Hour" (generated name). Show it **idle only**; while active, Turn Off Keep Awake takes its slot. The switch and this item start the same session.
- Put Until Turned Off back into Start Session › (first).
- ✓ marks only the running preset. The default gets the subtitle "Default" (14.4+), or nothing.
- Row counts: idle 6, active 9.
- Update the §5.2 mockup (draw idle and active separately), §5.4 and the §2.10 `awake.toggle` wording.

### M2. Pausing automatic sessions is unreachable at rest in the default config (§4.3 Start automatically, §5.4, §2.10)
Pause lives only in the Awake item (absent at rest under Show When Active) and an unbound hotkey; the compact section omits rules, the CLI is off, and the status row offers only Resume.

**Fix:**
- §5.4: include **Automatic Sessions ›** in the compact section whenever `triggers` is effective and at least 1 rule exists. That adds one row and carries the "Waiting for Desk dock" subtitle, Pause, and Edit Rules….
- Drop the sentence "Rules are reached from the Awake page or the Awake item."
- §4.3 status row, idle with rules: add a **Pause Automatic Sessions ▾** pull-down (1 Hour / Until Tomorrow). It counts as a status action, so the budget is unchanged.

### M3. "Turn Off Keep Awake" can silently leave the Mac awake (§2.5 rules, §5.3)
With a manual session over an active rule, Turn Off ends only the manual one and "the trigger governs again with no gap": the icon stays filled, the Mac stays awake, a second Turn Off is needed, and nothing says so.

**Fix:**
- A user Turn Off (switch, item, status row, `awake.toggle`) ends the manual session **and** calls `manualEnd` on every active rule, using each rule's "After I turn it off".
- When a rule is also active, add the ⌥ alternate **"End This Session Only"**.
- While a manual session overrides a rule, the detail adds: "Then “Desk dock” keeps it awake."
- Add a TriggerEngine test.

### M4. `awake hold` is refused while any UI session runs (§2.5 rules, §2.10)
User clicks For 2 Hours; a 3-hour build then runs `snaptic awake hold --pid $$` and gets exit 4; the UI session ends mid-build and the Mac sleeps. The "while building" journey fails when a session is most likely running.

**Fix:**
- A hold never *replaces* a UI session (this keeps security L4), but it becomes a **standby hold**. The reply is "Your Mac is already being kept awake. This hold takes over if that session ends (at most 12 h)." and the exit code is 0.
- One `standbyHold: HoldBinding?` slot; `arbitrate()` promotes it when the manual session ends; a user Turn Off clears it (M3). Test both.

### M5. Customize Displays Menu is about 46 pop-ups in one sheet (§4.3 C sheet, §4.8 "Menu ≈ 46 … pickers")
- This exceeds the ≤ 25-control sheet budget unless the group is counted as a list, and §4.3 doesn't say it is.
- Three-way pop-ups appear even where "In Display Submenu" doesn't apply.
- Dimmed "Turn on <feature>…" rows add more length.

**Fix:**
- Render "Menu items" as one grouped `List` (counted as 1 under §4.2) with three disclosure groups: Per Display, Displays Section, Display Tools. Only the Per Display group is expanded by default.
- Per-display items keep the pop-up Show / In Display Submenu / Hide. Every other item becomes a checkbox.
- Add a filter field.
- Collapse items whose feature is off into one row ("6 items need features that are off").
- Correct the §4.8 row text to match.

## 4. Minor

1. **§4.3 Awake mockup:** remove the ↺ after "[ 20% ]"; at the default the slot is empty (design m8).
2. **§5.2 compact mockup** mixes idle and active rows and shows no separators. Draw both states. Say whether the Add/Keep Display On group gets internal separators in the Snaptic menu (recommend none; spacing comes from the switch header).
3. **§5.3 rule alternate:** "Turn Off “Desk dock”" can mean ending the rule's session or disabling the rule. Specify that it ends the session (`manualEnd`) and title it **"End “Desk dock” Session"**. Disabling a rule stays in its editor.
4. **§5.3 idle detail "Off"** repeats the switch state; Wi-Fi and Bluetooth show no such line. Show a detail only for a last end or a guard hold, which lowers the idle row height.
5. **Rule editor (§4.3), journey 7:**
   - Open with one condition row whose kind pop-up is focused.
   - Make Name optional, with the placeholder = `TriggerEngine.summary`.
   - Copy: "Keep your Mac awake while [all ▾] of these conditions are met" (rules end too, so "Start when" is half the truth).
   - Hide is/is not for `power`, whose values already include their inverses.
      - This cuts journey 7 to about 9 clicks.
6. **Terminology:** "Default duration", "Durations in the menu" and "Durations sheet" all cover Until Turned Off and Until Downloads…, while the menu says Start Session ›. Use **Default session**, **Sessions in the Menu… [Edit…]**, sheet title "Sessions".
7. **Status row Options ▾** holds only ✓ Keep Display On for indefinite and uncapped sessions, which makes a one-item pull-down. Without Add items, show a plain "Keep Display On"/"Let Display Sleep" button instead (N5 holds).
8. **General:** show "Copy Install Command" as a subordinate row only while Command-line control is on. Help: "Copies a Terminal command that installs `snaptic`."
9. **Awake Advanced** "When your Mac sleeps" needs help: "When you choose Sleep or close the lid."
10. **Display submenu:** "Larger Text" and "More Space" have no defined modes. Either list concrete modes ("1280 × 800"), with "Larger Text" and "More Space" only as subtitles on the extremes, or define them as the next scaled mode down and up.
11. **Displays root:** Display Details… is per selected display but sits at the bottom next to the near-synonym Display Information ›. Move Display Details… into the Display section under the tiles, and keep Display Information last.
12. **§2.14** `AwakeIndicatorStyle` comment: change "Show" pop-up to "Time" pop-up.
13. **Restore Defaults** inside an Advanced sheet resets the visible settings too. Title it with the scope ("Restore Awake Defaults…", "Restore Displays Defaults…") in §4.1 `RestoreDefaults`.
14. **Search (§4.2):** ⌘F and Edit › Find focus the sidebar search field (System Settings precedent).
15. **untilIdle detail (§5.3, §4.3):** add the line "Ends after 5 min with no activity · quiet for 2 min" (from `TaskQuiet`), so users can trust the session.
16. **Menu Bar page:**
    - Give each module's Show When Active option its own help: Displays "while an external display is connected"; Awake "while your Mac is being kept awake".
    - CLI `display-may-sleep` is a bare word beside `--pid` and `--max`; make it `--display-may-sleep`.
    - State a Snaptic-menu row budget (default setup ≈ 21 rows) and check it in HW-15.

## 5. Mockups
Awake menu (6 idle), Awake page (11/5), Menu Bar page (Control Center wording, Snaptic icon last), Displays root hub, display submenu (~12) and the Awake footer copy pass; remaining defects are M1, M5 and minors 1, 2, 4, 10, 11.
