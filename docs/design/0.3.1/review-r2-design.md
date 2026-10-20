# 0.3.1 plan r2 review: design, UX copy and consistency

Plan = `docs/design/0.3.1/PLAN.md` at 8fd1b27. DS = `docs/design/0.3/design-spec.md`. r1 = `review-r1-design.md`.

Result: 0 Blockers, 1 Major, 16 Minors. 30 of the 33 r1 findings are fixed. The other three are partly fixed, and their remaining gaps are new findings below.

## r1 findings: fixed or not fixed

| r1 | Topic | Status | Note |
|---|---|---|---|
| M1 | ⌘, meaning | Fixed | A1/A2 footer unchanged; it restores the last pane |
| M2 | ⌘n keyboard path | Fixed | Positional ⌘n; "Show … Tab" names; items visible when VoiceOver is on; tooltips, help and Menu Bar footer; menu-closes case designed for |
| M3 | Part B controls | **Partly** | Table exists (B7), but several kinds and conditions are wrong or missing → n3 |
| M4 | Advanced placement, budget | Fixed | Moved to Advanced, dependent cap picker, one floor. Footer wording → n6 |
| M5 | Sentence case, "Allow", administrator password | Fixed | |
| M6 | One name | Fixed | B0 table; checkmark state; VoiceOver and suffix aligned |
| M7 | Cancel leaves a session | Fixed | Session starts only after verify. Toast wording → n9 |
| M8 | Leftover visibility | **Partly** | Host-level `LidRecovery`, rows above the tabs, Not Now. The text of the toast shown when Awake isn't running is missing → n8 |
| M9 | Writable-bundle wording | **Partly** | Writable row fixed. The translocated row quotes text that doesn't exist → n10 |
| M10 | README and site | Fixed | Line list, anchors, UI strings vs comments, accurate root claim |
| M11 | L16 and two `lidClosed` names | Fixed | Three names, two L16 clauses |
| m1 | Single-module header | Fixed | |
| m2 | Label fit | Fixed | Adopted; HIG caveat in n2 |
| m3 | Highlight fill | Fixed | Plain `NSView`; disabled if clicks still work |
| m4 | Accessibility label | Fixed | "Menu tabs" |
| m5 | VoiceOver `.layoutChanged` | Fixed | A2 step 5 |
| m6 | Key-equivalent claim | Fixed | A3 "Other keys" |
| m7 | Reset | Fixed | No reset clears it |
| m8 | DS amendments | Fixed | §1.5, §3.4, §4.7 |
| m9 | L17 collision | Fixed | L18 |
| m10 | N20 | Fixed | N19 |
| m11 | HW numbering | Fixed | HW-24…35 |
| m12 | Prompt texts | Fixed | Start and restore prompts. Singular "1 hour" → n12 |
| m13 | Refusal and notice strings | Fixed | Some wording → n7 |
| m14 | Status-section button | Fixed | Pull-down items |
| m15 | Nullable lid read | Fixed | `.hardware(.battery)` plus feature availability |
| m16 | Custom… toggle, "Start…" | Fixed | |
| m17 | Header line priority | Fixed | |
| m18 | CLI line | Fixed | |
| m19 | History | Fixed | |
| m20 | Visibility | Fixed | Badge and N11 suffix. Badge unspecified → n11 |
| m21 | Apostrophes | Fixed | All new strings use ’ |
| m22 | Scroll case | Fixed | HW-24 |

---

## New findings

### Major

#### N1. "More Display Features…" can never show after the move
**Evidence.**
- A1 diagram: "More Display Features… (Displays tab only)".
- A1 Footer: it "moves from the footer to the end of the Displays tab, or to the single-module Displays menu".
- A6: `menu.snaptic.upgrade` "moves to the Displays tab".
- The item exists only while Displays is **off**: `guard !config.isEnabled(.displays), config.showNewDisplaysCard || …` (StatusMenu.swift `upgradeItem`, about l.433). A Displays tab or Displays menu exists only while Displays is **on**.
- Also, if `DisplaysMenuBuilder` emitted `menu.snaptic.upgrade`, L15 would fail. A literal must be in the table that the file aliases (`DisplaysMenuBuilderControls`), not `StatusMenuControls`.

**Why it matters.** The 0.2 upgrade prompt for people who haven't turned Displays on disappears completely. That is a parity regression that no test catches.

**Fix.** Revert the move. "More Display Features…" stays in the shared footer, which every tab shows. A tab bar can exist without Displays: Window Switcher plus Awake gives two tabs. Drop A6's "`menu.snaptic.upgrade` moves" line and the A1 bullet. Fix parity m9 another way if it was about crowding.

### Minor

#### N2. Images in segments go against HIG; `.fit` gives up equal widths
**Evidence.**
- A1 "Attention and active marks": a 10 pt `exclamationmark.circle`, and Awake's active glyph, next to some segment labels.
- HIG, Segmented controls › Content: "Prefer using either text or images — not a mix of both — in a single segmented control." Best practices: "In general, keep segment size consistent… it’s best to keep icon and title widths consistent too."
- `.fit` (A1, adopted from my r1 m2) gives unequal widths.
- `labelStyle(fullWidths:fitWidths:available:)` (A4) doesn't include image widths.
- The "active glyph" isn't named. The Menu Bar page lets the user choose an Awake glyph family (MenuBarPage.swift:155).

**Fix.**
- Keep the attention mark, because safety is worth the HIG deviation, but record it as a DS §3.3 exception.
- Measure label widths **with** the attention image in A4/Kit.
- Drop the Awake "active" image. The N11 shared glyph and the Awake indicator already show that a session is on. Keep only the VoiceOver ", on" suffix and the tooltip "Awake, on (⌘3)".
- Put `.fit` after the short-name fallback, not before it: `.fillEqually` with full names, then `.fillEqually` with short names, then `.fit`. That keeps HIG's equal widths in the common case. This reverses my r1 m2 advice, which went against HIG.

#### N3. B7 control kinds and conditions
**Evidence.** Checked against `ControlRegistry.swift:21-46`, `SettingsIndex.requiresSearch` (l.198-210) and the existing tables.
- **`awake.advanced.lidBundle`** is listed as "status, conditional". `ControlKind` has no status kind. A warning `StatusRow` isn't a control: the Permissions writable row (PermissionsPage.swift:84) has no id. Its Learn More… link is the only action.
  - Fix: drop the id, or declare the link as `awake.advanced.lidBundleLearnMore`, `.statusAction`, `when: awake + [.state(.bundleWritable)]` (new state).
- **`awake.advanced.lidLeftover`** and **`awake.page.status.lidLeftover`** are each one id for two buttons (Turn Sleep Back On… and Not Now). The menu side, by contrast, has separate status and restore ids.
  - Fix: use `…lidRestore` and `…lidDismiss`, both `.statusAction`, `when: … + [.state(.lidLeftover)]`.
- **`awake.advanced.lidCap`** is a `.setting` on a Settings surface, so it needs a `SearchSpec`, or `testSearchCoverage` fails. Only `lidClosed` lists keywords.
  - Fix: `SearchSpec("Turn off lid-closed mode after", keywords: ["lid", "time limit", "cap"], root: root, sheet: sheet)`.
- **`.parentOn("awake.advanced.lidClosed")`**: the case takes a `ControlID`, so the house form is `.parentOn(ControlID("awake.advanced.lidClosed"))` (AwakeAdvancedSheetControls.swift:21).
- **`awake.page.status.lidClosed`** says "(pull-down item)" with no kind. The idle pull-down item has preset children.
  - Fix: `.statusAction`, `when: awake + [.awakeFeature(.lidClosed)]`, plus a per-preset `awake.page.status.lidPreset`, `.statusAction`, `when: … + [.perItem("preset")]`, mirroring `keepAwakeMenu` and `replaceWith`.
- **The `menu.awake.lid*` rows** have no kinds or placements.
  - Fix:
    - `lidClosed`: `.menuItem`, menu `awakeMenu`;
    - `lidSubmenu`: `.menuSubmenu`;
    - `lidPreset`: `.menuItem`, `when: [.awakeFeature(.lidClosed), .perItem("preset")]`, menu "lid submenu";
    - `lidCustom` and `lidNote`: `.menuItem`;
    - all with `.awakeFeature(.lidClosed)`.
- **`awake.custom.lidClosed`** has no kind. Use `.setting`, which is fine because the `awake.custom` surface is exempt from search (SettingsIndex.swift:172).
- **`ControlState.lidModeOn`** is declared but no spec uses it. Either use it, for example on `menu.awake.lidClosed` for the ✓ state, or don't add it.
- **`menu.snaptic.lidLeftover` and `menu.snaptic.lidRestore`** must also appear in Awake's custom menu, which `IndicatorController`/`AwakeMenuRows` builds under `AwakeMenuRowsControls`. Under L15, a literal there must belong to that table.
  - Fix: the host builds these two items, with `menu.snaptic.*` ids, in StatusMenu and passes them to the provider through `CustomItemRow`, the same path as the shared footer. Add the placement `MenuPlacementSpec("Awake menu", customize: .none)` to their specs.

#### N4. The lid submenu's presets need ellipses
**Evidence.** B1 idle submenu: the note "Asks for an Administrator Password", then presets "in preset order", then "Custom…". Every preset there asks for a password. The ellipsis rule (DS §3.3; P03 §5.1) says an ellipsis goes on every item where more input follows. "Keep Awake with the Lid Closed…" (active) follows it; the presets don't.
**Fix.** Use "Until Turned Off…", "For 1 Hour…" and so on inside the lid submenu (Kit `AwakePreset.title + "…"`). The disabled note can then go: the ellipses say the same thing, and one menu line is saved. If the note stays, keep it as the last row before the separator, so the first row is actionable.

#### N5. "Waiting for Password…" is shown when no password is being asked for
**Evidence.** B3.0: "In every state except `off` and `on`, all lid entry points are disabled and show 'Waiting for Password…'". This includes `verifying`, which runs after the dialog has closed, and `stopping`, which needs no password at all (B0: "turning it off asks nothing"). B1 says the same for the dialog.
**Fix.** Show text per state:
- `authorizing`: "Waiting for Password…";
- `verifying`: "Turning On…";
- `stopping`: "Turning Off…".

All are disabled. Put them in Kit `AwakePresentation`.

#### N6. Advanced footer: "while this is on" points at the setting, not the mode
**Evidence.** B1 footer: "Your Mac can’t sleep for low battery or heat while this is on, so Snaptic turns it off at your battery limit (at least 10%)…". "This" grammatically refers to the toggle "Keep awake with the lid closed", which only makes the mode available; switching it on changes no sleep behavior. "Your battery limit" doesn't name a control. The battery level is set on the main page ("When the battery is low" › "Battery level"), and 20% applies when that is off. The rest of Awake's copy says "Awake ends…", while this says "Snaptic turns it off".
**Fix.** "While lid-closed mode is on, your Mac can’t sleep for low battery or heat, so Awake turns it off at the battery level set on the Awake page (at least 10%) or when your Mac gets hot. Use it on a hard surface, not in a bag. Learn More…"

#### N7. Refusal and toast wording
**Evidence and fix**, B2 table and B3:
- **Battery refusal.** "Lid-closed mode needs at least 25% battery." But the condition is "discharging and below", so connecting power also works. Use: "Lid-closed mode needs at least 25% battery, or connect power."
- **Heat refusal.** "Your Mac is too warm for lid-closed mode right now." Every other heat string says "hot" ("too hot to keep awake right now", AwakeSession.swift:646; "your Mac got hot"). Use: "Your Mac is too hot for lid-closed mode right now."
- **Start Anyway refusal.** "Lid-closed mode can’t start in a session started with Start Anyway." repeats "start". Use: "Lid-closed mode isn’t available in a Start Anyway session."
- **Pending vs leftover.** "Snaptic is finishing an earlier lid-closed session. Try again in a minute." is used for both pending and **leftover** (B3.4), but a leftover never finishes on its own. For a leftover, use: "Turn sleep back on first: an earlier lid-closed session didn’t finish." with the button "Turn Sleep Back On…".

#### N8. Missing strings
- **Leftover toast when Awake isn't running** (B3.4) has no text. Proposed: "Your Mac can’t sleep: an earlier lid-closed session didn’t finish." with "Turn Sleep Back On…".
- **`AwakeEndReason.lidEnded`** (B3.3, B5) needs `AwakeEndText` phrase, toast and History strings. Proposed phrase: "lid-closed mode ended with the lid closed", giving the toast "Awake turned off: lid-closed mode ended with the lid closed." (`AwakeEndText` has a Kit test per reason.)
- **Not Now scope.** "Not Now" hides the rows "for this launch" (B3.4). Say that it hides the Settings rows only, and that the menu rows stay while `SleepDisabled` reads 1, because that is the safety signal.

#### N9. "Replaced the command-line session." is also used for launch and restored sessions
**Evidence.** B1: "Active, with a session from the command line, at launch, or restored: … the success toast says 'Replaced the command-line session.'"
**Fix.** Choose the text by source:
- `.commandLine`: "Replaced the command-line session."
- `.launch`, or a restored session: "Replaced the session that started when Snaptic opened."

Or use one neutral line: "Replaced the running session."

#### N10. The translocated row quotes text that doesn't exist
**Evidence.** B1: "the existing row 'Move Snaptic to Applications first' shows". The actual text is "Snaptic is running from a temporary location. Move it to Applications before you allow anything." (PermissionsPage.swift:80). "Before you allow anything" is about permissions.
**Fix.** Add a Kit sibling string: "Snaptic is running from a temporary location. Move it to Applications to use lid-closed mode." Use it in the B2 refusal row as well.

#### N11. The indicator "badge variant" isn't specified
**Evidence.** B1 "Indicator": "the active glyph gets a small badge variant". Awake glyphs come in user-chosen families (AwakeGlyphFamily). The Snaptic shared glyph already uses a "badge-dot" variant to mean "active" (P03 §5.2 N11), so a badge on Awake would mean something different from the same mark on the neighbouring icon. Template rendering (P03 §5.3) rules out color.
**Fix.** Name the variant per family in Kit (`AwakeGlyphFamily.lidActive`), and check that it exists in the 15 SDK's SF Symbols. Otherwise draw one composited template image and test it at 15 pt. Make sure it differs from N11's dot. Add it to HW-14 or HW-30.

#### N12. The prompt and toast must format singular hours
**Evidence.** `promptText(floor:capHours:)` with "for up to 8 hours", and the cap toast "turned off after 8 hours". The cap picker includes 1 Hour.
**Fix.** Build both with `AwakeCountdown.unit(capHours, L("hour"), L("hours"))` (N12, hand formatting), and add a 1-hour golden test.

#### N13. 12-hour last-end lines read "at … at" and don't match the existing pattern
**Evidence.** B1: "Lid-closed mode turned off at 20% battery at 3:12 AM." and "…because your Mac got hot at 3:12 AM." The existing idle line is "Ended at 3:12 AM: battery below 20%." (P03 §5.3).
**Fix.** Use the same pattern:
- "Lid-closed mode ended at 3:12 AM: battery at 20%."
- "…ended at 3:12 AM: your Mac got hot."
- "…ended at 3:12 AM: Snaptic quit."

The B2 restore case currently reads "turned off when Snaptic quit".

#### N14. `lidRoute` variants
**Evidence.** B1:
- feature on: "…or choose Keep Awake with the Lid Closed." This doesn't say where.
- feature off: "…or turn on lid-closed mode in Advanced." This names the button "Advanced…" without its context.

Neither covers a translocated copy, where the mode is unavailable.

**Fix.**
- Feature on and available: "…or choose Keep Awake with the Lid Closed in the Awake menu."
- Feature off: "…or turn on lid-closed mode in Awake › Advanced."
- Unavailable (translocated or no lid): the 0.3 text, unchanged.

All three go in Kit with a test.

#### N15. Menu Bar page: an unspecified summary change and a vague footer
**Evidence.** A6 lists "`MenuBarPage` summary line, plus the ⌘n footer from A3" but gives no new summary text, and the summary "Choose where Window Switcher, Displays, and Awake appear in the menu bar." needs no change. The A3 footer says "the menu shows a tab for each", which is ambiguous on a page about several menus. It also always says "⌘1, ⌘2, or ⌘3".
**Fix.** Drop "summary line" from A6. Footer, replacing MenuBarPage.swift:100's line: "The Snaptic icon appears when a module is set to Show in Snaptic Menu. With two or more, the Snaptic menu shows a tab for each; while it’s open, press ⌘1, ⌘2, or ⌘3 to switch tabs."

#### N16. The Custom… panel's lid control is called a "checkbox"
**Evidence.** B1: "Custom…, which opens the panel with the lid checkbox ticked". But B1's panel control is a `ToggleSetting`, which is a switch.
**Fix.** "…opens the panel with Keep awake with the lid closed turned on."

#### N17. The "Show … Tab" items appear only for VoiceOver, so Full Keyboard Access users don't get them
**Evidence.** A3 shows the items only when `isVoiceOverEnabled` at build. Switch Control and Full Keyboard Access users are in the same position: they can't operate the segmented control from the keyboard and have no visible native items.
**Fix.** Show the items when `NSWorkspace.shared.isVoiceOverEnabled || isSwitchControlEnabled || NSApp.isFullKeyboardAccessEnabled`. Mark the shared slot dirty on the matching `NSWorkspace` accessibility-display-options notification. Add both to HW-25.

---

## Checked and found fine

- **Valid kinds and conditions:**
  - `.statusAction` is a valid `ControlKind`.
  - `.hardware(.battery)` exists (`HardwareCondition.battery`) and is already used on `awake.page.batteryFloor`.
  - `.perItem("module")` and `.perItem("preset")` follow existing usage.
  - The new `ControlKind.menuTabBar` plus `requiresSearch` covers the kind's exhaustive switch.
- **Title Case in menus:** "Sleep Is Turned Off", "Turn Sleep Back On…", "Show Displays Tab", "Nothing to Show", "Waiting for Password…" (in its own state), "Asks for an Administrator Password" ("an" lowercase), and "Keep Awake with the Lid Closed…/›/✓".
- **Sentence case:**
  - Settings: "Lid closed", "Keep awake with the lid closed", "Turn off after";
  - the History suffix " · Lid closed";
  - the tooltip "Starts without lid-closed mode." (starts with a verb).
- **Pop-up options:** "1 Hour"…"72 Hours" is 8 options, so a pop-up, Title Case.
- **Ellipses:** "Start…" while the toggle is on; "Turn Sleep Back On…" and "Keep Awake with the Lid Closed…" ask for input; "✓ Keep Awake with the Lid Closed" correctly has none.
- **Prompts:** both say "an administrator password", name Snaptic first, and match the B0 wording. The README warns that the dialog names osascript.
- **VoiceOver and status wording:** the announcements match "Awake turned off." in style. ", even with the lid closed" is used everywhere.
- **Advanced help:** "When you choose Sleep or close the lid (not in lid-closed mode)."
- **CLI refusal text** follows the curly-quote, "Use … in the menu" pattern.
- **Numbering:** HW-24…35 have no gap or collision, N19 follows N18, and L18 is free (lint03.py ends at L17).
- **A2:** the tab bar as a plain `NSView` (no fill); `isEnabled = false` gated on HW-24; "Menu tabs" plus help that names the range; `.layoutChanged` after the swap; width measured at build so the segments never move under the pointer.
