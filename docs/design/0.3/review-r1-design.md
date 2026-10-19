# Review r1: Design + UX (Settings §4, Menu bar §5, Awake UI)

Test: would this ship in System Settings or as an Apple menu extra? Counts: default features, 1 built-in + 1 DDC external.

**Totals: 2 Blockers, 11 Major, 9 Minor.**

## Blockers

**B1. The Awake page has two switches that look alike (§4.3 Awake, N5).** The header switch turns the *module* on or off; the status row below it controls the *session*. On Wi-Fi, the header switch *is* the feature, so people will flip "Awake" on and expect their Mac to stay awake. VoiceOver reads "Awake, switch, on" either way.
Fix: header switch AX label "Use Awake". The status row uses **buttons only**: "Keep Awake" when idle; "Extend ▾" + "End" when active. See mockup M1.

**B2. Row switches will be the wrong size (§4.1 `ToggleSetting(subordinate:)`, [DS] §2.1 `.mini : .regular`).** System Settings uses the small switch in every row. Only the header switch (Wi-Fi, Bluetooth) is regular. Regular-size row switches make every page look like a port.
Fix: rows get no `controlSize` override, so the grouped form default applies. Only `SettingsPageHeader` uses `.regular`. A subordinate row appears only when its parent is on and gets a 20 pt indent; it does not get a smaller switch. Lint: ban `controlSize(.regular)` outside the header. Compare with Lock Screen settings on 14–27.

## Major

**M1. Pages are over the plan's own 8-control budget (§4.2, §4.3).** Actual counts of interactive elements:
- **General.** Plan says 6; actual 11. Drop the Modules navigation rows: they repeat the sidebar, and System Settings never links to its own sidebar. Move Restore Defaults into Advanced (M5). That leaves 5.
- **Menu Bar.** Plan says 11; actual 13. See M2. That leaves 8.
- **Awake.** Plan says "8 + list"; actual ~17. See M1. That leaves 8.
- **Displays root.** Plan says "8 + 8 nav"; actual ~21. See M9.

Fix: correct the §4.3 counts. Buttons and navigation rows count toward the budget.

**M2. Menu-bar presence is a 3×2 grid of mini switches (§4.3 Menu Bar, C2).** This is not a macOS pattern, and "both off" needs a warning line. Apple's Control Center settings use one pop-up per item.
Fix: one `.menu` picker per module:
- Switcher and Displays: *In Snaptic Menu / Own Icon / Don't Show*.
- Awake: *Own Icon / Own Icon When Active / In Snaptic Menu / Don't Show*.

Remove "both" from the UI. The compact Awake section appears in the Snaptic menu **automatically whenever Awake has no visible icon**. `MenuPresence` can keep its two bools internally. "Don't Show" help: "Use the keyboard shortcut or Settings to reach it."

**M3. The default setup shows two icons (§4.6 M2, Awake `ownItem: true`).** Space next to the notch is scarce.
Fix: default Awake to **Own Icon When Active** (the Focus precedent). The Mac then shows one Snaptic icon while idle, plus the Awake glyph and countdown during a session. Starting a session goes through the compact section (M2). Onboarding line: "The Awake icon appears while your Mac is being kept awake."

**M4. Nested sheets, which §1.5 bans.**
- Displays › Advanced contains "Display Information…". Make it a sub-page (`displays.info`), linked from a navigation row at the bottom of the root page.
- Awake › Advanced contains "Sleep Status…". Make it an inline live section: "Other apps keeping your Mac awake", with empty text "No other apps are keeping your Mac awake."
- Display Details… contains "Copy Settings From…". Make it a pull-down button. "Forget…" uses a standard confirmation alert.

**M5. Footers carry 3–4 buttons (§4.1 `PageFooterButtons`).** Awake has Restore Defaults…, Keyboard Shortcuts…, Advanced… and (?). Apple's footers have one or two.
Fix:
- Footer: `Advanced…` + `(?)`, trailing.
- **Restore Defaults…** goes in the Advanced sheet's footer, leading, next to Done. On pages with no Advanced sheet it stays in the page footer, leading.
- **Keyboard Shortcuts…** becomes a button row in a "Keyboard" section, as in System Settings › Keyboard.

**M6. SliderSetting layout is unspecified and won't fit on one line (§4.1, N4).** A label (~150 pt), slider (≥160), field (52), unit, reset (16) and spacing overflow a ~460 pt row once labels are localized. It's also unclear whether a value label *and* a field both show; both would be clutter.
Normative layout:
```
│ Contrast                  ◐ ━━━━━━●━━━━ ●  [ 70% ] ↺ │
│ Software contrast, applied by Snaptic.                 │  ← LabeledContent subtitle
```
- Trailing cluster: slider (min 140, ideal 200) · 8 · field 48 · 4 · reset slot 16, always reserved.
- **The field is the live value**; there is no separate label. During a drag it shows `drag ?? value`. The unit sits inside the formatted text ("70%", "60 Hz", "15 min"). Focus selects all. It parses "70", "70 %" and "70%".
- Field style: native `.roundedBorder`, `.controlSize(.small)`, monospaced digits, trailing-aligned (the Keynote inspector precedent).
- Reset glyph: `arrow.counterclockwise`, 11 pt, borderless, secondary. Tooltip "Reset to 50%" names the default. AX label: "Reset Contrast to 50 percent". It fades in 0.15 s, instantly with Reduce Motion. The row's context menu has "Reset to Default".
- `ViewThatFits`: fallback stacks title row (field + reset trailing) over a full-width slider.
- Tick marks at ≤ 11 positions; ←/→ and `accessibilityAdjustableAction` move one step (or 1% of the range).
- Reset glyphs go only on continuous values. Switches and pickers get the context menu only; `SettingRow` enforces this.

**M7. The countdown "1:42" reads as 1 min 42 s (§2.3 `AwakeCountdown.short`, §5.3).** That is the timer convention, and mixing it with "42m" is inconsistent.
Fix: `DateComponentsFormatter` with `.abbreviated` and units [.hour, .minute]: "1h 42m", "42m", "<1m". The seconds style keeps "1:42:05" / "42:05".
- Width: monospaced digits keep the item stable; length changes only at band edges.
- Set the text via `button.title` + `button.font = monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)`. **Never use an `attributedTitle` with a color**: it breaks the system's menu-bar text treatment on transparent 26/27 bars and under Increase Contrast.
- Glyph: template, `SymbolConfiguration(pointSize: 15, weight: .regular, scale: .medium)`, compared optically with Wi-Fi. Outline when idle, `.fill` when active, same width.

**M8. The status item's AX label goes stale (§5.3, "state changes only").**
Fix: update `accessibilityLabel` and `toolTip` on every `nextChange` tick, including in icon-only style.

**M9. Displays IA (§4.3 Displays).**
- Put the 8 navigation rows in two spaced groups: (Brightness, Color, Hardware Controls, Keyboard) and (Saved Layouts, Virtual Displays, Picture in Picture, Automations). Display Information goes last (M4).
- Rename "Monitor Controls" to **Hardware Controls** ("Volume, input and power for displays that support them.") and "Monitor contrast" to "Hardware contrast". The plan's own term table bans "monitor". Rename "Keyboard & Indicator" to **Keyboard**.
- Root Advanced has 8 groups, ~60 controls. Keep cross-cutting groups only (Use Snaptic for, Confirm display changes, Other display apps, Experimental, Resolution filters); Brightness methods → Brightness › Advanced…; Connection and Match Text Size → Display Details. ≤ 25 controls per sheet.
- Tile (i) opens a *sheet* but InfoButton means *popover*: use a **Display Details…** button row instead.

**M10. The Awake menu is long and parts of it read wrong (§5.3).** An active session with 2 triggers is ~22 rows; Apple extras have 6–12.
- "Keep Awake For" + "Until Turned Off" is ungrammatical.
- Each trigger gets its own row, up to 32.
- "Pause for 1 Hour" has no object.
- "Display May Sleep ✓" is a double negative.
- "Awake is paused" is wrong: the guard *ended* the session.

Fix (M3 mockup):
- Default presets: 30 Minutes, 1 Hour, 2 Hours, 5 Hours, Until Turned Off.
- Titles carry their own preposition ("For 1 Hour", "Until Turned Off"); drop the section header.
- Collapse triggers into one status line plus "Automatic Sessions ›".
- Use **"Keep Display On"** (checked by default), always present so the menu doesn't grow while open.
- The guard line reads "Ended because the battery is below 20%."
- Clicking the checked preset restarts its timer.

**M11. NSHostingView rows in NSMenu (§5.1 `MenuHostingRows.swift`).** SwiftUI-hosted menu views size late, lose vibrancy on 26/27 menu material, and can need an activating first click.
Fix: build `MenuSliderRow` and `switchHeader` in AppKit:
- `NSSlider`, plus `NSSwitch` at `.small` (as in the Wi-Fi menu).
- `NSTextField` with `labelColor` / `secondaryLabelColor`.
- Fixed frames: 300×30 for sliders, 300×26 for headers. No fills.

Replace `MenuKit.detail` with native `NSMenuItem.subtitle` (14.4+, `#available`; add a HW item to verify it on the 15 SDK). Fall back to a disabled item on 14.0–14.3. Use subtitles for "Main" and "Active" too, instead of attributed tab-stop trailing text, which breaks as menu width changes.

## Minor

**m1. Displays menu images are misaligned (§5.1–5.2).** Device rows have images, but "Arrange Displays…" and "Display Tools ›" don't. NSMenu doesn't reserve an image column ([UA] §3.3 #2), and HIG says all items in a group or none.
Fix: give every item in the section a 16 pt template symbol (`rectangle.3.group`, `wrench.and.screwdriver`). Align the slider glyph to the image column and the track to the text column; measure per OS (HW-15).

**m2. The display submenu is ~15–18 items, against the plan's own "≤ ~8" (§5.2).**
```
✓ Default            2560 × 1440    ← subtitle
  Larger Text · More Space · More Resolutions…
─ Use as Main Display · Mirror “Built-in Retina Display”
─ Input (header, DDC) ✓ USB-C · HDMI 1
─ Turn Off Display · Display Settings…
```
Drop the color toggles from the menu.

**m3. Snaptic menu (§5.2, §5.4).**
- The "Awake" section header sits directly above the "Keep Awake" header row. Drop the section header.
- Rename "Settings…" to **"Snaptic Settings…"** to match "Awake Settings…" and Apple's "Sound Settings…".
- "Turn On Thumbnails…" is an action, not a status row.

**m4. Quit is only an ⌥ alternate in the Awake menu (§5.3).** When no Snaptic item is configured, show "Quit Snaptic ⌘Q" visibly.

**m5. Fewer glyph choices (§2.14, §4.3).** `mug` duplicates `cup`, `sun` collides with Displays, and `bolt` reads as charging. Keep cup, eye and lightbulb. Delete "Different icon for automatic sessions". Replace the segmented control and the two Advanced toggles with one pop-up: **Show: Icon / Icon and Time Remaining / Icon and End Time**.

**m6. Sidebar and window (§4.2).** Three of the eight tiles are blue. Give Menu Bar a graphite tile (the Control Center precedent; add `SettingsTint.graphite`). Fix width at 715 pt, vertical resize only ([DS]; plan says 780).

**m7. Copy.**
- "Display may sleep by default" → **"Keep the display on"**. Help: "When off, your Mac stays awake but the display can turn off to save energy."
- "Tell macOS I'm/you're active" (inconsistent between §1.1 and §4.3) → **"Appear active"**. Help: "Keeps apps from marking you as away while a session runs."
- "Move the pointer" → "Move the pointer slightly". Help: "Moves the pointer 1 point and back. Needs Accessibility."
- In Advanced, put the end conditions under the page's own header, **"End sessions automatically"**: "When your Mac sleeps" · "When you switch users" · "When Low Power Mode turns on" · "When your Mac gets very hot".
- CLI help: drop "Raycast" → "Lets scripts and other apps control Snaptic with the `snaptic` command."

**m8. Unspecified states (§4.1).**
- Hardware can't do it: hide the control.
- Precondition missing: show the control disabled with its help line kept, and put `disabledReason` in the **section footer** with a fix button ("Open Accessibility Settings…").
- Empty triggers: "Keep your Mac awake automatically, for example while a display is connected." plus Add Condition….
- Empty history: `ContentUnavailableView("No Sessions Yet", systemImage: "cup.and.saucer")`.

**m9. PerDisplayPicker (§4.1).** ≤ 4 tiles, else a pop-up; selection shared across pages (`SettingsShell.selectedDisplay`); group AX label "Display".

## Mockups

**M1. Awake page (8 visible)**
```
[☕] Awake                                        (●)  "Use Awake"
     Keep your Mac awake for a while, or whenever
     certain conditions are met.
─────────────────────────────────────────────────────
Keeping your Mac awake until 3:45 PM    [Extend ▾] [End]
1h 12m left · Started from the menu
─────────────────────────────────────────────────────
Default duration                     [Until Turned Off ▾]
Keep the display on                                 (•)
Durations in the menu                          [Edit…]
─────────────────────────────────────────────────────
End sessions automatically
When battery is low                                 (•)
    Below        ━━━━●━━━━━━  [ 20% ] ↺
When the power adapter is disconnected              ( )
─────────────────────────────────────────────────────
Start automatically                                 (•)
  While a display is connected          Active   (i)
  [Add Condition…]                   [Pause for 1 Hour]
─────────────────────────────────────────────────────
Keyboard Shortcuts…  ·  Drives ›  ·  History ›
                                      Advanced…  (?)
```
Edit… opens the preset sheet (ReorderableList, +/−, an "Options" disclosure). The pop-up sets the default, not a ★.

**M2. Menu Bar page (8 visible)**
```
Snaptic icon             [◫] [◩] [◰]   (.isSelected tiles)
─────────────────────────────────────────────────────
Show in the menu bar
Window Switcher                     [In Snaptic Menu ▾]
Displays                            [Own Icon ▾]
   Hide when no external display is connected   ( )
Awake                               [Own Icon When Active ▾]
   Show                             [Icon and Time Remaining ▾]
   Icon                             [cup] [eye] [bulb]
─────────────────────────────────────────────────────
Displays menu
Display controls                    [Expanded | Compact]
Scroll over a slider to adjust it                   (•)
Customize Displays Menu…
```

**M3. Awake status menu (active, timed)**
```
Keep Awake                                   [●]
  Until 3:45 PM · 1h 12m left           (subtitle)
  Closing the lid will put your Mac to sleep.
────
Add 15 Minutes
Add 1 Hour
✓ Keep Display On
────
  For 30 Minutes
✓ For 1 Hour
  For 2 Hours
  Until Turned Off
  Until a Time or Duration…
  While an App Is Running          ›
────
Automatic: Desk dock (waiting)
Automatic Sessions                 ›  rules ✓ · ─ · Pause for 1 Hour · Pause Until Tomorrow
────
Awake Settings…
```
11 rows idle, 16 active; every common task takes ≤ 2 clicks. "Until a Time or Duration…" opens a small titled panel: For | Until, h/m fields or a time picker, Return = Start.

Platform: the system draws menus on 26/27 even with the 15 SDK; the Settings window keeps pre-Tahoe chrome on 26, which is correct. No fake glass, no opaque row backgrounds, semantic colors only.
