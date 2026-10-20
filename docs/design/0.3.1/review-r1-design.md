# 0.3.1 plan r1 review: design, UX copy and consistency

Reviewer lens: design-spec §3–§5 rules, 0.3 PLAN §5 menu rules, lint03 copy checks, HIG, accessibility, internal consistency and numbering. Plan = `docs/design/0.3.1/PLAN.md` (identical to PLAN-r1.md). DS = `docs/design/0.3/design-spec.md`. P03 = `docs/design/0.3/PLAN.md`.

No Blockers. 11 Majors, 22 Minors.

---

## Majors

### M1. "Snaptic Settings… ⌘," changes meaning and stops restoring the last pane
**Evidence.** Plan A1 "Snaptic Settings… ⌘,": opens the selected tab's module page. Today it calls `openSettings(page: nil)`, which restores `settingsLastRoute` (StatusMenu.swift:405-408, ModuleHost.swift:285, SettingsShell.swift:176-183). DS §1.1 and HIG Settings say "Restore the most recently viewed pane". Own-icon menus name this same action "<Module> Settings…" (StatusMenu.swift:419-421).
**Why it matters.** The item says "Snaptic", but it goes to a module page. Someone on the Displays tab who wants Menu Bar (to change the tabs), General or Permissions now lands on Displays every time. ⌘, then does something different in each tab. One title ends up with two meanings, and the HIG pane rule is broken for the main entry point.
**Fix.** Pick one:
- (a, preferred) Leave the footer as it is: "Snaptic Settings… ⌘," restores the last route. Delete `MenuTabs.settingsPage` and the A1 paragraph.
- (b) Make the title follow its target. The footer item becomes "<Tab> Settings… ⌘," (the own-menu wording), with an ⌥ alternate "Snaptic Settings…" (⌥⌘,) that restores the last route. Add `menu.snaptic.moduleSettings` reuse and the alternate's id to A6.

Either way, A1 must say what Awake's tab ends with. The plan drops "Awake Settings…" because "the footer covers it", and that is only true under (b).

### M2. The tab keyboard path is mapped to modules, can't be discovered, and probably closes the menu
**Evidence.** Plan A3: hidden items "Show Window Switcher / Show Displays / Show Awake" with ⌘1/⌘2/⌘3. A key equivalent pressed in an open NSMenu normally fires the item and ends tracking, and HW-33 is only asked to "decide". The plan doesn't say whether ⌘2 means "Displays" or "the second tab". Hidden items aren't shown, read by VoiceOver or type-selected. P03 §5.1 C4 / parity M4 asks for a native path that exists for the user.
**Why it matters.** A keyboard-only user who doesn't use VoiceOver has no way to learn that ⌘1–⌘3 exist. With Window Switcher on its own icon, the "Show Displays ⌘2" mapping leaves ⌘1 dead and gives the first tab ⌘2. The plan's main promise ("keeps the menu open") is the less likely HW-33 outcome.
**Fix.**
- Make the mapping positional: ⌘1…⌘n for tab n, and only as many hidden items as there are tabs.
- Rename the items "Show Window Switcher Tab" etc. "Show Window Switcher" reads as opening the switcher; DS §3.3's old sketch used exactly that title for the switcher action.
- Make the shortcuts discoverable:
  - the segmented control's `accessibilityHelp` reads "Press Command-1 to Command-3 to switch tabs.";
  - each segment's tooltip reads "Displays (⌘2)";
  - the Menu Bar page footer under the presence rows (MenuBarPage.swift:100) reads "With two or more modules in the Snaptic menu, it shows a tab for each. While it's open, press ⌘1, ⌘2, or ⌘3 to switch tabs."
- Write A3 for the likely case: "⌘n selects tab n and closes the menu; the next open shows it." Treat "stays open" as the bonus that HW-33 may confirm.
- README: "⌘1–⌘3 choose a tab (⌘1–⌘2 with two)".

### M3. Part B declares no controls, no conditions and no search entries
**Evidence.** Ground rule "every control is in a `*Controls` table" (plan l.20). B1 adds a toggle, a stepper, a picker, a warning row, the Awake-page button, two menu items, a Custom… toggle, and leftover rows with "Turn Sleep Back On…" / "Leave It Off". Part B names no `ControlSpec`. L15 (lint03.py:760-808) requires every literal to be declared and every declaration to be used. `ControlRegistryTests` requires `search` on `.setting` and `keys` coverage for every `AwakeConfig` leaf (`testKeyCrossCheck`). `HardwareCondition` (ControlRegistry.swift:21-24) has `battery` but no lid. `ControlState` has no lid states.
**Why it matters.** Step 0 must produce the signatures. If ids are left to T-lid-app, they get invented in parallel and spelled inconsistently, and the key cross-check fails on `AwakeLidConfig`.
**Fix.** Add a B1.1 "Controls" list. Proposed names follow the existing prefixes:
- Settings controls (Advanced, see M4):
  - `awake.advanced.lidClosed`, `.setting`, keys `awake.lid.allowed`, `when: awake + [.hardware(.battery)]`;
  - `awake.advanced.lidCap` and `awake.advanced.lidFloor`, both `when: … + [.parentOn("awake.advanced.lidClosed")]`.
- Search keywords: "lid", "clamshell", "closed-display", "disablesleep", "insomnia", "amphetamine".
- Awake page: `awake.page.status.lidLeftover` (`.statusAction`: Turn Sleep Back On… / Not Now).
- Awake menu:
  - `menu.awake.lidClosed` (`.menuItem`, both titles);
  - `menu.awake.lidLeftover` and `menu.awake.lidRestore`.
- Snaptic menu (see M8): `menu.snaptic.lidLeftover` and `menu.snaptic.lidRestore`.
- Custom… panel: `awake.custom.lidClosed`.
- Conditions:
  - `ControlState.lidClosedOn` and `.lidLeftover`;
  - use `HardwareCondition.battery` for "MacBook" (see m15).
- Name `ControlLegacy`/`keys` coverage and `ConfigFixtures.fullAwake()` filling `AwakeLidConfig`.

### M4. The "Lid Closed" group breaks the page budget, the help-text rules and DS's own placement
**Evidence.**
- Plan B1 adds to the Awake page a section with a toggle, a 1–24 stepper, a picker, a conditional warning row and a 4-sentence, about 390-character footer.
- DS l.11: at most about 8 controls before Advanced…, and the Awake page is already past that (AwakePage.swift: status, Sessions ×3, End ×3, rules, Keyboard, Drives, History, menu-bar link).
- DS §1.5 l.99 puts the lid option in **Advanced…** "(with a warning about heat)".
- DS §2 "Help text": one sentence describing the on state; "Never stack more than two lines of help under one row"; use (i) or Learn More… for more. Copy rule 3: at most about 90 characters.
- Precedent: the experimental `pointerNudge` and the hour picker "Stop appearing active after" (1/2/4/8 Hours) live in AwakeAdvancedSheet.swift:60-78.

**Fix.** Move the group to the Awake **Advanced…** sheet as section "Lid closed" (sentence case, like "Activity" and "Display"):
- `ToggleSetting(L("Keep awake with the lid closed"), help: L("Only in sessions you start in Snaptic. Asks for an administrator password each time."))`. This mirrors the "Move the pointer slightly" help.
- Dependent rows, shown only when the toggle is on (DS §1.4, 1–3 dependent options):
  - `PickerSetting(L("Turn off after"), options 1, 2, 4, 8, 12, 24 → "1 Hour"…"24 Hours")`, default 8 Hours. This replaces the raw 1–24 stepper and matches the activity-cap picker.
  - `PickerSetting(L("Turn off below"), options "10%", "20%", "30%")`.
- Footer, 2 sentences: "Your Mac can’t sleep for low battery or heat while this is on, so Snaptic turns it off at the battery level above or when your Mac gets hot. Use it on a hard surface, not in a bag." Then a **Learn More…** link to the README section from B6.
- On the main page, the existing `lidRoute` line (AwakePresentation.swift:621) becomes the pointer:
  - not allowed: "To keep it awake with the lid closed, connect power and an external display, or turn on lid-closed mode in Awake › Advanced."
  - allowed: "…or choose Keep Awake with the Lid Closed…".

### M5. The toggle and stepper labels break copy rules 1 and 2, and the footer contradicts the picker
**Evidence.**
- "Allow Keeping Awake with the Lid Closed" and "Turn Off After" are Title Case. Setting labels are sentence case (DS §4 rule 1; every label on AwakePage and the Advanced sheet is sentence case).
- Rule 2: "Don't write 'Enable', 'Disable' or 'Allow X to Y'".
- The footer says "Snaptic turns it off at 10% battery" while the picker defaults to 20%. "Your MacBook" breaks the house "your Mac" wording.
- "You'll enter your administrator password" is wrong for a standard account: macOS asks for an administrator's name and password.
- The battery-floor option strings "Turn off at 10% battery" put sentence-case text into pop-up options, which DS §4 rule 1 and lint03 `popup_case` require in Title Case.

**Fix.** Use the strings in M4. Say "an administrator password" everywhere (prompt, help, Custom… toggle). Pop-up options are numbers only.

### M6. One feature, five names; the pair of menu titles is ambiguous
**Evidence.** The plan uses all of these for the same mode:
- "Keep Awake with Lid Closed…" (menu, no article);
- "Allow Keeping Awake with the Lid Closed" (setting);
- "Lid Closed" (group);
- "lid-closed mode" (notices);
- "Lid closed mode on." (VoiceOver, no hyphen);
- "Also keep awake with the lid closed" (Custom…);
- "…, also with the lid closed" (tooltip).

The "on" title "Allow Sleep When Lid Closes" uses "Allow", which rule 2 forbids. It reads like a general setting rather than "stop this mode", and it isn't a recognisable state change of the "off" title (DS §4 rule 1 "Switch actions": a menu that knows the state names the change). The neighbouring session option already uses a checkmark: "✓ Keep Display On" (P03 §5.3).

**Fix.**
- Add a terminology row to DS §4.7: "closed-lid / clamshell / disablesleep / Power Protect → keep awake with the lid closed (noun: lid-closed mode)".
- Menu:
  - off: "Keep Awake with the Lid Closed…";
  - on: "✓ Keep Awake with the Lid Closed", with no ellipsis because turning it off asks nothing.
  - Place it in the active group directly after "✓ Keep Display On", and while idle directly after the default-preset item. A1 and P03 §5.3 must name the slot in `AwakeMenuModel.rows`.
- The Awake status section gets the same two titles as items of the existing "Keep Awake" (idle) and "Options" (active) pull-downs (AwakeStatusSection.swift:114-121, 176-202), not a separate button (see m14).
- VoiceOver: "Keeping your Mac awake with the lid closed." and "Lid-closed mode turned off." These match "Awake turned off." (SessionController.swift:711).
- Tooltip and accessibility label: "Awake, 1 hour 42 minutes remaining, even with the lid closed".

### M7. Cancelling the password leaves a session the user didn't ask for
**Evidence.** Plan B1: when idle, "Keep Awake with Lid Closed…" "starts the default session (preset) with lid-closed mode". It also says "Cancel leaves the session running without lid-closed mode and shows no error toast." When a session from the CLI or a hotkey is running, the item starts the default preset and so replaces that session (only menu/Settings sessions are "added to"). Neither case is mentioned in the copy.
**Why it matters.** The user asked for lid-closed mode and cancelled. Silently running a default-length (possibly Until Turned Off) session is a surprise that drains the battery. Silently replacing a `snaptic awake start 2h` session changes its end time.
**Fix.**
- B1: "If this action started the session, Cancel or a failed verify ends it again with no end toast (end reason `.user`, not shown in History)." Or start the session only after verify succeeds.
- For a running non-UI manual session: "the item replaces it; the toast after success says “Replaced the command-line session.”"
- Treat a `.hotkey` session like menu/Settings (it is a direct user action, AwakeSession.swift:436-448). Otherwise the item replaces a session the user just started with their own shortcut.

### M8. Leftover state is hidden behind a tab and, with Awake off, never shown
**Evidence.** Plan B3.3: the leftover row shows "in the Awake status section and the menu", and detection runs "At Awake start". With tabs, the Awake rows are only visible on the Awake tab (A1), or in Awake's own icon, which by default exists only while active. If Awake is turned off, `lid.json` is never examined. The text "Sleep is still turned off from an earlier lid-closed session." is 60 characters. A disabled status row that long widens a 300 pt menu (native rows don't wrap). Existing menu status rows are short Title Case ("Safe Mode Is On", "No Modules Are On", "No Displays Detected").
**Why it matters.** "Your Mac can't sleep at all" is the one Awake state that must be seen whatever tab is selected or module is on.
**Fix.**
- Run the leftover classification in the host at launch, next to `RevertJournal.recoverAtLaunch` (AppDelegate:62), whether or not Awake is enabled.
- Show it in the shared menu's first group, beside the Safe Mode rows and above the tab bar: status row "Sleep Is Turned Off", then "Turn Sleep Back On…".
- Show it in every own/custom menu's first group as well.
- On the Awake page and in Advanced › Other Apps, use the sentence-case row: "Your Mac can’t sleep: an earlier lid-closed session didn’t finish."
- Rename "Leave It Off" to "Not Now" (the existing toast vocabulary, SessionController.swift:419-449). It hides the row for this launch only. Advanced › Other Apps keeps a "Turn Sleep Back On…" button.
- After "Leave It Off", don't fall back to "another app or command. Snaptic can’t change this." (OtherAssertionsSection.swift:17). That sentence would then be false: Snaptic can change it.

### M9. The writable-bundle warning gives advice that doesn't work for the default install
**Evidence.** Plan B1 warning: "…Install Snaptic with `INSTALL=1 ./scripts/build-app.sh` or move it to Applications as an administrator." The README's primary install path is "Grab `Snaptic.zip`… drag Snaptic to Applications" (README.md:528). A Finder copy, even by an admin, is owned by and writable by that user, so the row shows for most users and "move it to Applications" doesn't clear it. Settings rows aren't the place for shell commands. The existing equivalent row is worded differently (PermissionsPage.swift:84: "Your account can change this folder, so another app could replace Snaptic and keep its permissions. Use a signed release, or install Snaptic in /Applications with an administrator account."). Translocated copies (PermissionsPage.swift:80) aren't mentioned.
**Fix.** Reuse the Permissions wording and its two conditions:
- writable: "Your account can change this copy of Snaptic, so another app could change it and misuse the password prompt. Learn More…", linking to README "Lid-closed mode and your password", which gives the `INSTALL=1` steps;
- translocated: the existing "Move it to Applications first" row, and lid-closed mode refused.

Keep both strings in Kit next to the Permissions copy, so they stay in step.

### M10. README and site copy direction is inaccurate and misses lines
**Evidence.**
- B7: "Awake runs one program…: macOS's own password prompt (`osascript`), which starts `pmset`". In fact osascript is the AppleScript runner. It shows the system authorization dialog and then runs a root `/bin/sh` loop for the whole session, which calls `pmset`, `ioreg`, `notifyutil`, `stat`, `awk` and `sed` (B3.1).
- B7 calls user-visible strings "Code comments": AwakePresentation.swift:319 (the lid line), :621 (`lidRoute`) and OtherAssertionsSection.swift:17 (a `StatusRow`).
- README lines that contradict the feature and aren't in B7's list:
  - 212 ("end sessions when your Mac sleeps (when you choose Sleep or close the lid)");
  - 318 (Awake needs no permission);
  - 543 ("Awake needs no root at any time; the password is only for installing.");
  - 589 (Helpers);
  - 666 and 673 (testing scope: lid and tabs).
- Renaming the heading at 254 breaks the `#why-not-with-the-lid-closed-on-battery` anchors at 273 and 639.
- AwakeAdvancedSheet.swift:108 help ("When you choose Sleep or close the lid.") becomes partly untrue while lid-closed mode is on.

**Fix.** Rewrite the claim: "Awake runs a program only while you use lid-closed mode: `/usr/bin/osascript` asks macOS for an administrator password, then starts a short shell script as root that runs `pmset` and turns sleep back on when the session ends, Snaptic quits or stops responding, the battery reaches your limit, or your Mac gets hot." Then:
- add the README lines above to B7;
- move the three strings from "Code comments" to a "UI strings" list with their new text;
- update both anchors;
- extend the Advanced help: "When you choose Sleep or close the lid (except in lid-closed mode)."

Site card: "Lid closed on battery? Turn on lid-closed mode with an administrator password. It stops at low battery, on heat, and after a time limit."

### M11. L16 extension contradicts B3: two `lidClosed` properties with different owners
**Evidence.**
- B2: `AwakeSession.lidClosed`, "Only `SessionController` may set it; lint L16 is extended to `lidClosed`".
- B3 step 5: `LidClosedController` "mark `runtime.lidClosed = .on(until:)`".
- B1 status line: `snaptic awake status` `lidClosed`, plus History `lidClosed`, plus `AwakeStatusFacts.lidClosed`.
- L16 today is the regex `activityGate\s*=(?!=)` outside SessionController (lint03.py:338-345). A naive `lidClosed\s*=` would flag LidClosedController and every presentation init.

**Fix.**
- Name the three things apart:
  - `AwakeSession.lidRequested: Bool` (runtime-only and SessionController-only; L16 pattern `\.lidRequested\s*=(?!=)` plus `AwakeLidGate\(`);
  - `AwakeRuntimeState.lidMode: AwakeLidMode` (published only by LidClosedController; a second L16 clause names that file);
  - `lidClosed` stays as the CLI/History field name.
- State in B3 which object owns turning on and off. LidClosedController asks SessionController to set or clear the request; SessionController calls back on session end.

---

## Minors

### m1. Dropping the single-module header contradicts 0.3 and A6
**Evidence.** A1 drops the header for a single shared module "because the icon names the menu". The shared item shows the Snaptic glyph, which doesn't name Displays or Window Switcher. That is the reason own-icon menus have no header and the shared one has. P03 §5.2 l.3444/3449 and DisplaysMenuBuilder.swift:16-19 rely on StatusMenu's header. A6 says `menu.snaptic.sectionHeader` "stays, for own-icon menus and single-module menus", but own menus already pass `header: false` (StatusMenu.swift:355), and A1 removes the single-module case. So the id would be used nowhere, and L15 fails "every declared id must be used".
**Fix.** Keep the header for a single non-Awake shared module (the 0.3 behavior), and keep the id. If the owner wants it gone, remove `menu.snaptic.sectionHeader` now with a `ControlRemovals` reason, and amend P03 §5.2 in the 0.3.1 doc. Don't leave an "if unused" clause.

### m2. Equal-width small segments will push English to "Switcher"
**Evidence.** A1/A2: `.small`, `.fillEqually`, 272 pt, so about 90 pt per segment minus bezel padding. "Window Switcher" at 11 pt is about 82–85 pt, so the fallback will fire on the default 3-tab setup in English. "Switcher" alone appears nowhere else in the menus or titles. Its only UI use is a section header in the Switcher's own page (SettingsView.swift:37).
**Fix.**
- Measure with `.fillEqually` first. If full titles don't fit, try a fitted distribution (`.fit`, centred) before switching to short names, which keeps module names consistent with Settings and the Menu Bar page.
- Keep each segment's accessibility label as the full title even when the short name shows. NSSegmentedControl reads the visible label, so HW-32 must check this.
- Put short names in Kit (`ModuleID.shortTitle`) through `L()`.

### m3. Hover highlight behind a segmented control
**Evidence.** A3: "the tab row highlights like other view rows (`willHighlight`)". `MenuRowView` draws the `.selection` fill whenever `enclosingMenuItem.isHighlighted`, which includes mouse hover (MenuKit.swift:203-255). `highlightDidChange` recolours only text fields. A blue fill behind an unrecoloured NSSegmentedControl looks broken and may lose contrast on 26/27. Return on a highlighted actionless view item closes the menu.
**Fix.** `MenuTabBarRow` never draws the selection fill. Try `isEnabled = false` on the item, so arrow keys skip it, if the segmented control still takes clicks (HW-31). Add "highlight/hover look in light, dark, Increase Contrast, Reduce Transparency" to HW-31.

### m4. Accessibility label and term
**Evidence.** A2 uses "Snaptic menu sections". User copy says "tab" (A6 summary, README "choose a tab"). Labels shouldn't repeat the app name.
**Fix.** Use the label "Menu tabs" and the help from M2.

### m5. VoiceOver may keep stale children after a swap
**Evidence.** A3 relies on the segmented control's value change announcement. The items below are replaced inside an open menu, which is new territory (brief menu §8).
**Fix.** After step 4 of "Switching tabs", post `NSAccessibility.post(element: menu's view/window, notification: .layoutChanged)` synchronously (no timer). HW-32 checks that VO-Down reaches the new section's first item.

### m6. The claim about module key equivalents is wrong
**Evidence.** A3 says "Displays' and Awake's own key equivalents work only on their tab". The only key equivalents in menus are ⌘, and ⌘Q (`key:` grep: MenuKit.swift:121,126; AppDelegate.swift:226), plus Switch Windows' drawn ⌥⇥, which never fires.
**Fix.** Replace it with: "Only ⌘, ⌘Q and ⌘1–⌘n work in the open Snaptic menu; type-select reaches only the visible tab." Don't document non-existent shortcuts in the README.

### m7. Restore Defaults clears the tab but General Reset doesn't
**Evidence.** A5. A full reset is less than a scoped one. The Menu Bar Restore confirmation (MenuBarPage.swift:107) doesn't mention the tab.
**Fix.** Treat it like `settingsLastRoute`, as navigation state: neither reset clears it.

### m8. Design-spec amendments are incomplete
**Evidence.**
- A6 updates DS §3.3 only. DS §3.4 says "update values in place while it's open, so it doesn't flicker or resize", which tab switching breaks on purpose.
- DS §1.5 l.99 still describes the lid option as "allow sleep when the lid is closed".
- P03 §5.1's "every … switch-header action also has a native path (C4)" needs the tab-row exception spelled out.

**Fix.** Amend DS §3.4 ("except a tab switch, which replaces the section synchronously and resizes the menu"), DS §1.5, and add a 0.3.1 note to P03 §5.1/§5.4. Answer for Open question 1: in tabs, the "full" rows differ from compact only by their two internal separators (AwakePresentation.swift:408-438), so use full rows.

### m9. Lint rule L17 already exists
**Evidence.** B6 "New rule L17". lint03.py:348-354 already defines L17 ("uniqueKeysWithValues is banned in Awake"), and the docstring at l.2 lists L16 and L17.
**Fix.** Call it L18, and update lint03.py's docstring.

### m10. "N20" skips N19, and "extended as" is unclear
**Evidence.** P03 §0.1 ends at N18 (PLAN.md:699-707), and no N19 exists anywhere (grep).
**Fix.** Name it **N19** ("lid gate; extends N10's direct-UI rule"), and use that id in B2, B5 and the README threat model.

### m11. HW ids skip HW-24 to HW-30
**Evidence.** P03 §6.7 ends at HW-23. Nothing uses HW-24…30 (grep over repo). There's no collision, but the gap is unexplained, and the plan says "added to PLAN §6.7's list" while 0.3's PLAN is final.
**Fix.** Number them HW-24…HW-33, or add one line saying 24–30 are reserved. Keep the list in the 0.3.1 doc and the README testing scope (README.md:666, 673), not in P03.

### m12. The password prompt text lacks the cap and the instruction
**Evidence.** B1 prompt. The AppleScript `with prompt` text replaces the default message, which ends "Type your password to allow this." [U] HW-35 should confirm what remains. The cap is the main limit and isn't mentioned. The restore prompt (`LidWatchdog.restoreScript`, B6) has no text at all.
**Fix.**
- Start prompt: "Snaptic wants to keep your Mac awake with the lid closed for up to 8 hours. Sleep turns back on when the session ends, when Snaptic quits, at 20% battery, or if your Mac gets hot. Enter an administrator password to allow this." Build it in Kit `promptText(floor:capHours:)`; hours are formatted with `AwakeCountdown.unit` (N12).
- Restore prompt: "Snaptic wants to turn sleep back on. An earlier lid-closed session didn’t finish. Enter an administrator password to allow this."
- HW-35 also checks that Displays' dimming overlays order out for this dialog (README.md:593).

### m13. Refusal, notice and toast texts are missing or off-pattern
**Evidence.**
- B2 "The refusal is a toast with the reason" gives no strings.
- B4 "The notice says why" gives none.
- Given strings use straight apostrophes ("Can't", "Couldn't", "Snaptic's", "won't"), which lint03 `straight_apostrophes` fails in `L()`.
- "Couldn't turn on lid-closed mode." doesn't say what to do (rule 5).
- The cap notice says "your Mac will sleep when you close the lid", but the lid is usually already closed at that point.
- The CLI refusal "Use Snaptic's menu." differs from the existing "Use the menu…" pattern (AwakeSession.swift:657-660).

**Fix.** Put these in Kit with tests:
- Start refusals:
  - "Lid-closed mode needs at least 25% battery." (floor+5, computed)
  - "Lid-closed mode isn’t available while Low Power Mode is on."
  - "Your Mac is too warm for lid-closed mode right now."
  - "Lid-closed mode can’t start in a session started with Start Anyway."
- Failures and other events:
  - "Snaptic couldn’t turn on lid-closed mode. Try again."
  - "Another app turned sleep back on, so lid-closed mode stopped."
- Ends:
  - "Lid-closed mode turned off after 8 hours. Awake is still on; your Mac sleeps while the lid is closed."
  - Floor/heat: "Lid-closed mode turned off at 20% battery." / "…because your Mac got hot."
- Still on: "Sleep is still turned off. Your Mac won’t sleep until it’s turned back on." with the button "Turn Sleep Back On…".
- CLI refusal: "Lid-closed sessions can’t be extended from the command line. Use Add 1 Hour in the menu."

### m14. A standalone status-section button, unlike the pull-downs
**Evidence.** B2 adds "the Awake page's 'Keep Awake with Lid Closed…' button in the status section". The section's actions are the "Keep Awake" and "Options" pull-downs (AwakeStatusSection.swift:114-121).
**Fix.** Make it an `ActionMenuItem` in those pull-downs (M6 titles). There is no new button row.

### m15. Group visibility rests on a nullable read at module start
**Evidence.** B1 "hidden when … `lidWillSleep == nil` at module start". nil also means "unreadable" (SystemEventsMonitor.swift:48-51), so a single failed read hides the group until relaunch. Search would need a matching `when`.
**Fix.** Use `.hardware(.battery)` (it exists: ControlRegistry.swift:23) for the controls' `when`. Use `lidWillSleep != nil` only to offer the menu item.

### m16. Custom… panel toggle copy and its Start button
**Evidence.** B1 "a checkbox 'Also keep awake with the lid closed (asks for your password)'". The panel uses `ToggleSetting` with help (CustomSessionPanel.swift:85-86). A parenthetical in a label breaks rule 2. The panel's extend mode (Add Time…) shouldn't show it. By the ellipsis rule, Start asks for more input when the toggle is on.
**Fix.** `ToggleSetting(L("Keep awake with the lid closed"), help: L("Asks for an administrator password when you click Start."))`, shown only in `.start` mode. The button reads "Start…" while it is on.

### m17. Header detail line priority and duplication
**Evidence.** B1 replaces the last extra (`AwakeDetail.extras`, AwakePresentation.swift:319). `lines` keeps only 2 (`maxLines`), so the lid line disappears whenever an untilIdle, "Then …" or holder line exists. "Stays awake with the lid closed until 6:40 PM." repeats the primary "Until 6:40 PM · …" when the cap isn't earlier.
**Fix.** While on, the lid line is the **first** extra. Its text is "Stays awake with the lid closed" when the session end is earliest, otherwise "…with the lid closed until 6:40 PM". Add a Kit test for the priority.

### m18. CLI status text line
**Evidence.** B1 adds `lidClosed` only to JSON. The tab-separated `statusLine` (AwakeCommandGrammar.swift:187-200) has fixed columns.
**Fix.** Append `lidClosed` as the last JSON key and as a last `\t`-field (`lid` or `-`), so existing parsers keep their indices. Document both in the README CLI table.

### m19. History presentation of the flag isn't specified
**Evidence.** B1 "History (new lossy `lidClosed` flag)". There's no UI copy.
**Fix.** Add a subtitle suffix " · Lid closed" in the History row, and the same in "Start Again". Start Again doesn't carry the flag (B2), so its tooltip says "Starts without lid-closed mode."

### m20. State visibility when Awake lives only in the Snaptic menu on another tab
**Evidence.** With Awake presence `.inSnapticMenu`, an active lid-closed session is visible only on the Awake tab. The N11 glyph says only "awake".
**Fix.** While lid-closed mode is on, append ", even with the lid closed" to the shared glyph's accessibility label (P03 §5.2 N11). Optionally, show the Snaptic menu's first-group row "Awake With the Lid Closed" (Title Case status) whatever the tab.

### m21. Plan copy uses straight apostrophes throughout
**Evidence.** Footer, notices and refusal text in B1, B2 and B3 ("You'll", "won't", "Can't", "Couldn't", "Snaptic's", "macOS's").
**Fix.** Write the plan's canonical strings with ’ so they can be copied into `L()`. lint03 `straight_apostrophes` fails otherwise.

### m22. Height jumps move the footer
**Evidence.** A2 "Height". Quit and Settings move on every switch. That's acceptable given the owner's choice, but HW-31 doesn't check the case where the tallest tab exceeds the screen (scroll arrows) and the menu then shrinks.
**Fix.** Add to HW-31: "13-inch at the largest text size, Displays tab with 3 externals: switch to Awake and back; no stuck scroll arrows, and the tab bar stays under the status item."

---

## Checked and found fine

- Ellipsis use follows "asks something": "Keep Awake with Lid Closed…", "Turn Sleep Back On…", "Leave Safe Mode…". "Allow Sleep…" correctly has none (title wording itself is in M6).
- The tab bar stays out of own-icon menus, and Safe Mode rows stay first (consistent with StatusMenu.swift:353).
- Remembered-tab fallback without overwriting the stored id. Lenient decode. Not in `ModulesConfig` (avoids `scheduleApply`), backups or the key cross-check.
- No timers or `RunLoop.main.perform` in the swap (N15/L14). The L6 exemption list is extended for the new file. `ControlKind.menuTabBar` plus the `SettingsIndex.requiresSearch` update.
- Width: 272 pt control = 300 − 2×14 inset; a menu with tabs is always 300 pt.
- Reduce Motion: neither an NSMenu resize nor a 15-SDK `NSSegmentedControl` selection animates, so nothing to gate.
- Tab order = `plan.shared` start order, and the tab count is ≤ 3, within HIG's segment limit.
- The prompt starts with "Snaptic wants to…", which identifies the requester despite osascript's dialog.
- Cancel shows no error toast.
- The kill switch name `Awake.disable.lidClosed` follows N14.
- `allowed` is never exported or imported, following the `pointerNudge` precedent.
