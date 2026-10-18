# Review r2: Design + UX (Settings §4, Menu bar §5, Awake UI)

Test: would this ship in System Settings or as an Apple menu extra? Counts: default features, 1 built-in + 1 DDC external.

**Totals: 0 Blockers, 7 Major, 14 Minor.** 21 of the 22 round-1 findings are resolved. M10 is resolved in §5.3 but came back in §5.2 and §5.4.

## 1. Round-1 verification

Resolved:
- B1 (N5, §4.3)
- B2 (§4.1, L12; fix [DS] §1.4, which still says "mini switches")
- M1 (§4.2, §4.3 Counts; Color arithmetic, m13)
- M2 (C2; copy, Major 5)
- M3 (C11; Show default, Major 5)
- M4 (file panels, m6)
- M5
- M6 (N4; field width, m7)
- M7 (partly rejected; the reason is fine and the strings are identical)
- M8
- M9 (density, Major 6)
- M11
- m1–m9

**M10 is not resolved.** The §5.2 mockup and §5.4 still use "Keep Awake For ›" containing "Until Turned Off" (Major 1).

## 2. Major

**M1. "Keep Awake For ›" + "Until Turned Off" is back, and the two Awake menus differ (§5.2, §5.4 vs §5.3).** That means two builders and two mental models.
Fix: one row set, `AwakeMenuRows`, used by both surfaces:
- header
- Turn Off
- Add
- **Start Session ›** (Amphetamine's "Start New Session"), whose items keep their prepositions
- While an App Is Running ›

The header must stay "Keep Awake". An "Awake" header with a switch would mean *module* in Settings and *session* in the menu, which is B1 across surfaces.

**M2. The Awake menu is still 13 rows idle and 16 active (§5.3); Apple extras have 6–12.** Most of the length is the 8 inline presets. "Keep Display On, always present so the menu never grows" doesn't hold, because flipping the header switch adds Turn Off and the Add rows anyway (Wi-Fi grows too, and that's fine). Idle, the item silently edits a stored default.
Fix (mockup A): presets go into Start Session › (the Focus "Do Not Disturb" options precedent); "Until a Time or Duration…" becomes **Custom…**; Keep Display On shows only while a session is active; the trigger status line becomes the submenu row's subtitle. **6 rows idle, 10 active.** Every task still takes ≤ 2 clicks and has a keyboard path.

**M3. The upgrade experience for migrated users isn't specified (C7, §4.3 card, §4.6 M1).**
- A 0.2 user who had "Prevent display sleep while DELL is connected" now gets a new cup icon with no explanation.
- That user's card says "Turn On Awake…", but Awake is already on, and the ellipsis is wrong.
- The card sits on General, but Settings reopens to the last route, so many users never see it.

Fix:
- One-time toast at the first activation: "Keeping your Mac awake while “DELL U2720Q” is connected is now part of Awake." [Show in Settings].
- State-dependent card. If Awake is off: [Turn On Awake] [Not Now]. If the user was migrated: "Your display sleep setting moved to Awake." [Show Awake] [OK].
- A "New" sidebar badge on Awake until the user first visits the page.

**M4. Automatic sessions have three off controls, no edit flow, and four names (§4.3 Awake, §5.3).**
- The section switch, the row switches and "Pause for 1 Hour" repeat the B1 pattern.
- Editing and deleting a rule are unspecified, and (i) can't edit.
- The same thing is called condition, automatic session, rule and trigger.

Fix (precedent: Focus › Set a Schedule):
- No section switch; `triggers` turns on implicitly with the first rule.
- Rows show name, a summary subtitle, "Active", "Waiting" or "Off", and a chevron.
- Click or Return opens `TriggerEditorSheet`, which holds the on switch and **Delete Rule…** (standard alert).
- Drag to reorder, with VoiceOver Move Up/Down actions.
- Terms: a **rule** has **conditions** (All/Any, as in Mail). Use "Add Rule…" and "Edit Rules…".
- Pause lives in the menu and the hotkey. While paused, the status row reads "Automatic sessions are paused until 4:00 PM." [Resume].

**M5. The Menu Bar page diverges from Control Center (§4.3 Menu Bar, §2.14).**
- Apple's pop-up reads *Always Show in Menu Bar / Show When Active / Don't Show in Menu Bar*; ours says "Own Icon…".
- Awake's options are in a different order from the other modules.
- "Hide when no external display is connected" is just *Show When Active* for Displays, which Apple's Display module has.
- The Snaptic icon, the least important control, comes first.
- The mockup shows "Icon and Time Remaining", but `style` defaults to `.icon` ([DS] §3.5 says off by default).
- The row label "Show" is ambiguous.
- "Display controls: Expanded/Compact" has no help.

Fix (mockup B):
- One option order for every module.
- `.ownIconWhenActive` is allowed for Displays too, and the Displays toggle migrates to it.

That leaves 8 settings + 1 button.

**M6. The Displays root mockup hides how tall the page is (§4.3 Displays).**
- The nav rows are drawn four per line, but grouped-form rows are full width. The page comes to about 900 pt against a default height of 640 pt, so every sub-page sits below the fold.
- "Brightness" is both a slider and a nav row, so VoiceOver announces it twice.
- Saved Layouts belongs with arrangement.
- The Undo and Redo buttons have no Apple precedent. Use ⌘Z/⇧⌘Z (Edit menu) plus items in Quick Changes ▾.
- "Extended" should read "Extended display", Apple's copy.

Fix (mockup C):
- Rename the sub-page **Brightness and Dimming**.
- Set the default height to 720.

**M7. The Awake page carries low-value rows (§4.3 Awake).**
- "Menu bar icon ›" uses a chevron but jumps to another sidebar root (chevron means push).
- The header has a second help line that repeats the confirmation alert.
- The idle text "Not keeping your Mac awake" describes a negative.
- "Started from the menu" is noise.
- The subordinate title "Below" is a fragment; VoiceOver reads "Below, 20 percent".

Fix (mockup D): 5 settings + 4 buttons/nav rows = 9.

## 3. Minor

- **m1. Serial comma** (Apple style): "Startup, command line, backup, and Safe Mode."; "Volume, input, and power…".
- **m2. Copy:**

| Now | Use |
|---|---|
| My display has no DDC | This display doesn't support hardware controls |
| Suspend on this display | Adjust this display |
| Allow dimming to black | Dim all the way to black |
| Keep on while I'm active / May sleep | Keep on until idle for [n min] / Can turn off |
| Stop after no input for | Stop when inactive for [1 hour ▾] (Lock Screen) |
| Even without a session | Also when no session is running |
| Interval (Drives) | Check drives every [2 min] |
| Menu visibility… | Customize Displays Menu… |
| Indicator style | Brightness and volume indicator |
| "No Modules Are On" + Open Settings… | … + Snaptic Settings… |
| Start preset 1–4 | Start “For 1 Hour” (preset names) |

- **m3. Display submenu:** "Mute" sits under the "Input" header. Move it to the group with Turn Off Display.
- **m4. Settings items in Awake's own menu:** §5.2 adds "Snaptic Settings…" to own menus, and §5.3 already has "Awake Settings…". Keep Awake Settings… (⌘,) + Quit only.
- **m5. Lid warning:** show it only when it applies (on battery, or no external display). Otherwise it is on screen for every laptop session.
- **m6. Sheets over sheets:** EDID Export…, LUT import and Import Settings… present file panels as sheets on a sheet. Present them from the page window instead, or move EDID Export… to Display Information.
- **m7. Field width:** a 48 pt `NumberField` can't fit "1512 × 982" or "6500 K". Derive the width from the widest value of each `ValueFormat`. Typing a width in the discrete resolution slider snaps to the nearest mode.
- **m8. Reset glyph:** the mockups show ↺ at default values and on live Brightness, which has no default. Show ↺ only when the value ≠ the default; with `defaultValue: nil` there is no glyph, but the slot is still reserved.
- **m9. Empty states:**
  - Hardware Controls: "Connect a display that supports hardware controls."
  - Saved Layouts: "Save your current arrangement to restore it later."
  - Virtual Displays: "Create a display that exists only in software."
  - PIP: "Show a live view of any window or display."
  - Automations: "Run a program when displays change."
- **m10. Accessibility:**
  - `GlyphTilePicker` is a radio group: arrow keys move the selection, and the group label is the row title.
  - Rule and preset rows offer Edit, Delete and Move actions.
  - The countdown never posts announcements; the end of a session posts one.
- **m11. Onboarding:** drop the Awake quick-setup step (it repeats two page controls); move the icon line into the Choose Modules row.
- **m12. Window Switcher:**
  - Merge the one-row Behavior section into Shortcut.
  - Rename "Keyboard Shortcuts…" to **More Shortcuts…** and put it under the primary shortcut.
  - When Advanced "Windows on other Spaces" is off, disable "Other Spaces" in the visible pop-up and give the reason in the footer.
- **m13. Counts:**
  - Color reads "8 | 0 | 9". State that `PerDisplayPicker` counts toward the total but not toward settings.
  - Customize Displays Menu has about 27 controls. Merge "Main display first" into the order list and drop "Header row with one display".
- **m14. Displays placement and naming:**
  - Display Tools ▾ has no home when the tiles are hidden; put it trailing in the Brightness section header.
  - About's "Diagnostics Report…" silently switches the sidebar root; title it "Display Information…".

## 4. Apple comparison

| Apple | Ours | Verdict |
|---|---|---|
| Control Center pop-ups (Always / When Active / Don't Show) | "Own Icon…", extra toggle | Fix (M5) |
| Focus menu: modes, options on demand | 8 presets inline | Fix (M2) |
| Wi-Fi: name header + switch | "Keep Awake" header | Justified (B1) |
| Lock Screen: "…when inactive [For 1 hour ▾]" | Advanced durations | Copy (m2) |
| Displays: tiles, "Extended display", footer buttons, no nav rows | Hub with 9 rows | Accepted hub, fix (M6) |
| Focus › Schedules: row opens a sheet with on + Delete | Section + row switches | Fix (M4) |

## 5. Mockups

**A. Awake menu.** The compact section uses the same rows, minus Automatic Sessions.
```
Keep Awake                                 [○]   detail "Off" or last end
────
Start Session                               ›    For 30 Minutes · ✓ For 1 Hour · For 2 Hours ·
                                                 For 5 Hours · Until Turned Off ·
                                                 Until Downloads and Tasks Finish · ─ · Custom…
While an App Is Running                     ›
────
Automatic Sessions                          ›    subtitle "Waiting for Desk dock"
────
Awake Settings…                            ⌘,
```
In an active timed session, the menu changes from idle as follows:
- The detail line reads "Until 3:45 PM · 1h 12m left".
- **Turn Off Keep Awake** follows the header.
- A new group follows it: Add 15 Minutes, Add 1 Hour (⌥ Add Time…), ✓ Keep Display On.

That makes 10 rows.

**B. Menu Bar page**
```
Window Switcher                    [Show in Snaptic Menu ▾]
Displays                           [Show in Snaptic Menu ▾]
Awake                              [Show When Active ▾]
    Time                           [Don't Show ▾]     Time Remaining / End Time
    Icon                           [cup] [eye] [bulb]
⚠ status rows, when true
────
Displays menu
Style                              [Standard | Compact]
    Compact shows one slider per display.
Scroll over a slider to adjust it                   (•)
Customize Displays Menu…
────
Snaptic icon                       [◫] [◩] [◰]
Restore Defaults…                                   (?)
```
The pop-up options are *Always Show in Menu Bar · Show When Active · Show in Snaptic Menu · ─ · Don't Show*.
- *Show When Active* is offered only for Displays and Awake.
- When Awake's Don't Show is disabled, the footer reads: "To hide Awake, first set a Keep Awake shortcut."

**C. Displays root, lower half** (the top is as in r2)
```
Use as                              [Extended display ▾]
Arrange Displays…
Saved Layouts                                   On  ›
────
Brightness and Dimming                              ›
Color                                          Off  ›
Hardware Controls                               On  ›
Keyboard                                            ›
────
Virtual Displays                               Off  ›
Picture in Picture                             Off  ›
Automations                                    Off  ›
────
Display Details…
Display Information                                 ›
```

**D. Awake page**
```
[☕] Awake                                           (●)
     Keep your Mac awake for a while, or automatically
     when certain conditions are met.
──────────────────────────────────────────────────
Your Mac can sleep as usual.                   [Keep Awake]
  active: Keeping your Mac awake until 3:45 PM [Extend ▾] [Turn Off]
──────────────────────────────────────────────────
Default duration                       [Until Turned Off ▾]
Keep the display on                                   (•)
  When off, your Mac stays awake but the display can turn off.
Durations in the menu                              [Edit…]
──────────────────────────────────────────────────
End sessions automatically
When the battery is low                               (•)
    Battery level       ━━━━●━━━━━  [ 20% ]
When the power adapter is disconnected                ( )
──────────────────────────────────────────────────
Start automatically
Desk dock                                      Active  ›
  While “DELL U2720Q” is connected
[Add Rule…]
──────────────────────────────────────────────────
Keyboard Shortcuts…
Drives                                            Off  ›
History                                  Today 2h 10m  ›
footer: Choose where Awake appears in Menu Bar settings.
                                           Advanced…  (?)
```
