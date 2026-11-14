# 0.5 plan review r3: Grill (product, strings, UX)

Reviewer: round-3 (final) grill (product, UX, strings). Plan under review: `docs/design/0.5/PLAN.md` (r3, 2,023
lines).

Grounding:

- All of PLAN.md r3, including §R1 and §R2. `review-r2-grill.md` and the other r1/r2 reviews were skimmed so nothing
  closed there is repeated. Q1–Q7 are settled and not reopened.
- Shipped sources at `7dd972c`: the Hidden Icons and Window Switcher Settings pages and Advanced sheets,
  `PageFooterButtons`, `SafeMode`, `MenuLayout`, `StatusMenu`, `ConfigModules`, `KitModules`, `KitLossy`,
  `PrivateAPIs` (`SystemHotkeys`), the Awake CLI replies, onboarding, the New card, the Menu Bar page.
- `README.md`, `docs/guide.md`, the site guide, and the 0.4 PLAN, to check the H9 line references (all correct).
- No DockDoor or AltTab source was opened. Nothing was launched, written to defaults, or fetched.

**Counts:** 0 Blockers, 2 Majors (G3-1, G3-2), 8 Minors (G3-3 to G3-10).

Citation conventions: `PLAN:l.N` is a line of PLAN.md r3. Code is cited as a repo path with its line. Proposed UI
strings use curly apostrophes (lint03).

## Round-2 Majors: closure check

| r2 | Closed? | Leftover |
|---|---|---|
| G2-1 key targets and discoverability | Yes (§4.1 rules 5 and 6, §4.5) | G3-9: the VoiceOver exception versus M42 and the Known limitation |
| G2-2 the Safe Mode model | Yes (§4.13 is one model, used by §4.17, §4.19 and §4.21) | G3-7: the same feature has two names |
| G2-3 shared privacy, Restore Defaults, downgrade | Yes. Downgrade is safe: `LossyMap` keeps unknown keys (`Sources/SnapticKit/KitLossy.swift:17–42`) | G3-10: the Dock sheet's confirmation question |
| G2-4 app-list names | Yes (“Apps hidden from Dock previews”, outside Privacy) | G3-3: §4.9 applies the list to every capture |
| G2-5 VoiceOver | Yes (row 7, the Advanced switch, §4.16) | G3-9 |
| G2-6 state-table controls and strings | Mostly | G3-1 (a held command pause is invisible), G3-6 (the footer while off) |
| G2-7 default menu presence | Yes for the default | G3-4: no attention mark when Dock Previews is the only module in the Snaptic item |

## Findings

### G3-1 · Major · §4.21, §4.17, §4.19 · A command pause held in Starting, row 4 or row 5 can't be seen, and `resume` says there isn't one

**Question.** After `snaptic dock pause 2h` while starting or in row 5, or after a row-8 pause when Accessibility is
then revoked (row 4), how does the user see the pause, and how do they clear it?

**Why it matters.** The verb × state table lets the pause be set in Starting and row 5, and says it “holds when the
Dock becomes readable”. Row 4 also comes before row 8, so a row-8 pause sits under row 4 when Accessibility is
revoked. In all three states:

- the page shows only the row's status;
- the menu shows no Resume;
- `dock resume` answers “Dock Previews isn’t paused.” (exit 0) while a pause is held.

When the Dock becomes readable or Accessibility comes back, previews stay off for up to 24 h. That contradicts what
`resume` just said, and nothing on screen explains it. A script that ran `resume` gets exit 0 and no previews.
`DockControlsTests` will pin these cells as written, so this has to be fixed in the plan.

**Evidence.**

- Verb × state: Starting pause is “as row 9” and resume is “isn’t paused” (PLAN:l.1309). Row 4 resume is “isn’t
  paused” (PLAN:l.1311). Row 5 pause “works as in row 9 (G2-12)” and resume is “isn’t paused” (PLAN:l.1312).
- “A command pause set in row 5 or while starting holds when the Dock becomes readable.” (PLAN:l.1318)
- Resume replies (PLAN:l.1295). The row-4 refusal is for pause only (PLAN:l.1299).
- Only row 8 shows “Paused until” and [Resume] (PLAN:l.1147). Starting has no menu status item (PLAN:l.1150–1151).
- Menu: “Resume Dock Previews” is “in row 8 only … Neither shows in rows 3 to 7 or while starting” (PLAN:l.1252–1253).
- `status` has an `until` key (PLAN:l.1321), but the table fills it only for row 8 (PLAN:l.1147).

**Proposed answer.**

- §4.17, Added rows, a new first bullet: “**A held command pause** (§4.21). While starting, or in row 4 or 5, with a
  command pause set: “Paused until 3:45 PM” [Resume]. When the row's own problem clears, row 8 takes over.”
- §4.19 item 3: “… or “Resume Dock Previews” in row 8, and while starting or in row 4 or 5 with a command pause set.
  Neither shows in rows 3, 6 and 7.”
- §4.21 verb × state, the `resume` cells for Starting, 4 and 5: “clears a held pause: “Dock Previews’ pause is
  cleared.” (exit 0); else “isn’t paused” (exit 0)”.
- §4.21 Replies, resume: add “Dock Previews’ pause is cleared.” for a pause cleared while starting or in row 4 or 5.
  (“on again” would be false there.)
- §4.21 `status` format: “`until` is set whenever a command pause is held, in any row from Starting to 8. `reason`
  stays the row's.”
- Rewrite PLAN:l.1318 as: “A command pause set while starting or in row 5, or one held when row 4 starts, stays set.
  It shows as an added row (§4.17), `resume` clears it, and `status` gives its `until`.”
- Add a `DockControlsTests` case and extend M43: “`pause 5m` in the row-5 hook, then `resume`: the reply is
  “Dock Previews’ pause is cleared.” and the added row goes away.”

### G3-2 · Major · §4.12 step 6, §4.17 · The ⌘⇥ give-back failure row has one string for two S0-5 outcomes, no home in §4.17, an unclear Try Again, and stays hidden while the switcher is off

**Question.** When giving ⌘⇥ back has crashed on this OS build, what does the user see, where, and what does
Try Again do?

**Why it matters.** This is the one failure that breaks the Mac outside Snaptic: ⌘⇥ stops working everywhere. The
plan has four gaps.

1. **The string.** “macOS may keep ⌘⇥ off until you log out. Snaptic couldn’t give it back.” is true only if S0-5
   finds that logout turns it back on. The plan says “the text follows that result”, but gives no text for the other
   outcome, where logging out does nothing.
2. **Its home.** The row isn't in §4.17's added rows or its crash-guard table. `symbolicHotKeys` (“Using ⌘⇥ for the
   Window Switcher”) is the take, a separate disabled build.
3. **Try Again.** Each feature's Try Again “clears that feature's disabled builds”. It's unclear whether the
   `symbolicHotKeys` row's Try Again also clears `symbolicHotKeys.giveBack`, or whether the give-back row has its own.
   It's also unclear whether Try Again gives ⌘⇥ back now or only at the next launch. M35 tests only the hover capture.
4. **Visibility.** The likely crash is in `restore()` when the user turns the switcher off. The Window Switcher page
   shows no rows while the switcher is off, only the highlights. So the row is hidden exactly when it's needed.

Also, Snaptic manages three shortcuts, not just ⌘⇥: ⌘⇥, ⌘⇧⇥ and ⌘ plus the key above Tab.

**Evidence.**

- PLAN:l.988–993: the give-back marker, its disabled build and the one string. PLAN:l.996: Try Again per feature.
- PLAN:l.435 and PLAN:l.460: step 4 skips the give-back.
- PLAN:l.1167: the stopped-row text. PLAN:l.1176: `symbolicHotKeys` is shown on the Window Switcher page only.
- PLAN:l.1381: S0-5 records the logout result. PLAN:l.1672: M35.
- `Sources/Snaptic/Switcher/SwitcherPages.swift:69–76`: when blocked or off, only `DefaultsLockRow` and
  `FeatureHighlights` show, with no `statusRows`.
- `Sources/Snaptic/Switcher/PrivateAPIs.swift:143–147`: `commandTab`, `commandShiftTab`, `commandKeyAboveTab`.
- `Sources/Snaptic/Switcher/PrivateAPIs.swift:153–161`: `recoverFromPreviousRun()` runs at every launch, whether the
  switcher is on or off.

**Proposed answer.** Replace the string sentence at PLAN:l.991–993 with a pointer to §4.17, and add to §4.17's
Added rows:

- “**⌘⇥ not given back** (§4.12 step 6). Shown on the Window Switcher page whenever the give-back's build is
  disabled, whether the switcher is on, off or killed. When the switcher is off, it shows above the highlights.
  - If S0-5 finds that logout turns it back on: “⌘⇥ may not switch apps until you log out, because Snaptic
    couldn’t turn it back on after a problem in macOS.” [Try Again]
  - If it stays off after logout: “⌘⇥ doesn’t switch apps, because Snaptic couldn’t turn it back on after a
    problem in macOS.” [Try Again]
  - Accessibility help: “This also affects ⌘⇧⇥ and ⌘ with the key above Tab.”
  - [Try Again] clears only `symbolicHotKeys.giveBack`'s disabled build and gives the saved shortcuts back at once,
    with the marker written first. The `symbolicHotKeys` row's Try Again clears only the take.”

Add to M35: “the give-back drill: trap in the give-back; the next launch shows the ⌘⇥ row with the switcher off;
Try Again turns ⌘⇥ back on without a relaunch and removes the saved list.”

### G3-3 · Minor · §4.9 vs §4.18 · “Apps hidden from Dock previews” blocks every capture, but its help says the Window Switcher isn't affected

**Question.** Does the Dock-only list stop the switcher's captures?

**Why it matters.** §4.9's “every capture, on either path” list includes the app list. That would hide the
switcher's thumbnails for those apps, while the sheet says “The Window Switcher isn’t affected.” One of the two
gets built and tested wrong.

**Evidence.** PLAN:l.821 (“Every capture, on either path, needs all of these”), PLAN:l.828, PLAN:l.814,
PLAN:l.1237–1238.

**Proposed answer.** PLAN:l.828 becomes: “The app isn't on the protected list. For a Dock Previews capture, the app
also isn't on “Apps hidden from Dock previews”.” Add a K-test: “an app on the Dock-only list still gets a
switcher thumbnail.”

### G3-4 · Minor · §4.17, §4.19 · No attention mark when Dock Previews is the only module in the Snaptic item

**Question.** Where does the row-4, row-5 or breaker attention mark show when Dock Previews is the only shared
module?

**Why it matters.** The mark is the tab mark, and tabs exist only with two or more shared modules. `setIcon` marks
only Awake's active state. With only Dock Previews in the Snaptic menu (M44's case, or the switcher and displays off),
row 4 gets no mark. §4.19 still says the mark is “there without a change”.

**Evidence.**

- PLAN:l.1184–1185, PLAN:l.1255–1256, PLAN:l.1260–1261, PLAN:l.1681 (M44).
- `Sources/SnapticKit/MenuLayout.swift:121–125` (`plan.shared.count >= 2 ? plan.shared : []`, “one module keeps
  its 0.3 header”).
- `Sources/SnapticKit/MenuLayout.swift:184–187`. `Sources/Snaptic/Core/StatusMenu.swift:397–415`.

**Proposed answer.** Add to PLAN:l.1185: “With fewer than two modules in the Snaptic item there's no tab bar, and so
no mark; the page row and the menu's status item still show.” PLAN:l.1255 becomes “… so the section, and with a
tab bar the attention mark, are there without a change …”. Add M44: “with Dock Previews alone, row 4 shows its
menu status item and no mark.” (If a mark is wanted here, it's a new `setIcon` badge and needs its own row. Out of
scope for 0.5.)

### G3-5 · Minor · §6 · A6a's acceptance checks verbs that don't exist until K5 and A9

**Question.** How does A6a show that Safe Mode “registers its verbs”?

**Why it matters.** A6a needs only K1 and A1a. `DockCommandGrammar` is K5, and `DockCLI` is A9. `dock live` is a
selftest-launch log line, not a verb. So the check can't be run at A6a, and the item would be passed on trust.

**Evidence.** PLAN:l.1480 (A6a), PLAN:l.1479 (K5), PLAN:l.1488 (A9), PLAN:l.1334 (`selftest-launch: dock live`).
A6b already uses “a DEBUG hook until A9” (PLAN:l.1485).

**Proposed answer.** A6a's acceptance: “… In Safe Mode the module starts paused (§4.13): it creates nothing, the
DEBUG state hook reports row 3, and `dock live` stays zero.” Add to A9's acceptance: “in Safe Mode, `dock status`
gives `state=paused reason=safeMode`, and `pause` and `resume` refuse (exit 5).”

### G3-6 · Minor · §4.17 vs §4.18 · Which footer buttons show while the module is off

**Question.** In rows 1 and 2, do (?) and Advanced… show?

**Why it matters.** §4.17 says rows 1 and 2 “show only their row”. §4.18's footer limits only Restore Defaults to
“while the module is on”, which implies Advanced… and (?) always show. Hidden Icons, the precedent, shows (?) while
off, and Advanced… only while running.

**Evidence.** PLAN:l.1152–1153, PLAN:l.1220–1221. `Sources/Snaptic/Icons/UI/IconsPage.swift:98–99`
(`advanced: enabled && running ? openAdvanced : nil`, `restoreDefaults: enabled ? restore : nil`, help always).

**Proposed answer.** PLAN:l.1152: “Rows 1 and 2 show their row and the footer's (?) only.” PLAN:l.1220: “**Restore
Defaults…** on the leading edge, and **Advanced…** on the trailing edge, both while the module is on (Starting and
rows 3 to 9); (?) on the trailing edge always.”

### G3-7 · Minor · §4.13 vs §4.17 · Two names for the minimized-window thumbnail feature

**Question.** Is it “Thumbnails of minimized and other-Space windows” or “Thumbnails of minimized windows and
windows on other Spaces”?

**Why it matters.** `SafeMode.skipped` uses “the words the Settings pages use”. A user who reads the Safe Mode page
and then the stopped row sees two names for one thing. `testEveryCanonicalStringIsInTheSources` will hold both.

**Evidence.** PLAN:l.1054, PLAN:l.1172. `Sources/Snaptic/Core/SafeMode.swift:18–29`.

**Proposed answer.** PLAN:l.1054: “`SafeMode.skipped` gains “Dock previews” and “Thumbnails of minimized windows and
windows on other Spaces” (§4.17's display name).”

### G3-8 · Minor · §4.15, §5 S0-32, §6 D1 · Where “Switching from DockDoor” lives

**Question.** Is “Switching from DockDoor” a guide page, a README table, or both?

**Why it matters.** §4.15 makes it a guide page. S0-32 sends the defaults to “the README's table”. D1 puts the
table in “README and GUIDE”, and the README section also links to it. Two copies drift. The README rule (G-13: one
paragraph, five bullets) also leaves no room for a table.

**Evidence.** PLAN:l.1107–1108, PLAN:l.1408, PLAN:l.1489.

**Proposed answer.** One home. S0-32's last cell: “… goes to the guide's “Switching from DockDoor” table (D1).”
D1: “GUIDE: the Switching from DockDoor section with its table (behaviour only, with every S0-32 default that
differs). README: the Dock Previews section links to it.”

### G3-9 · Minor · §4.16, M42 vs §4.1 rule 5 · With VoiceOver previews on, the keyboard does show the panel

**Question.** Is “Dock Previews works with the pointer” true when “Show previews while VoiceOver is on” is on?

**Why it matters.** Rule 5's exception lets the selection alone drive the panel when that switch is on. ⌃F3 and
VoiceOver's own navigation then show previews. M42 (“no previews”) and the Known limitation are unqualified, so M42
fails on a correct build with that switch on.

**Evidence.** PLAN:l.567–570, PLAN:l.1131, PLAN:l.1679.

**Proposed answer.** PLAN:l.569: “Without that exception, keyboard selection of the Dock (⌃F3, Full Keyboard Access)
… never shows a panel (M42).” Known limitation: “Dock Previews works with the pointer, or with VoiceOver when “Show
previews while VoiceOver is on” is on. With the keyboard alone, use the Window Switcher.” M42: “With VoiceOver off,
⌃F3 and Full Keyboard Access through the Dock: no previews.”

### G3-10 · Minor · §4.10, §4.18 · The Dock sheet's Restore Defaults asks the same question as the page's

**Question.** What are the Dock sheet's Restore Defaults title and question?

**Why it matters.** The plan gives only the sheet's message. With `RestoreDefaults(scopeName: "Dock Previews")`, the
default question is “Restore Dock Previews settings to their defaults?”. That's the page's question word for word,
but the sheet resets only the Advanced settings. The user can't tell the two apart until they read the small print.
The Window Switcher sheet is fine as it is: it resets the whole switcher, and its message says so.

**Evidence.** PLAN:l.886–887, PLAN:l.1222, PLAN:l.1241. `Sources/Snaptic/SettingsUI/PageFooterButtons.swift:60–62`.
`Sources/Snaptic/Icons/UI/IconsAdvancedSheet.swift:110–114`. `Sources/Snaptic/Switcher/SettingsView.swift:22`.

**Proposed answer.** PLAN:l.1241: “The sheet's own **Restore Defaults** (Advanced settings only, as in 0.4): button
“Restore Defaults…”, question “Restore Dock Previews’ Advanced settings to their defaults?”, and §4.10's Dock sheet
message. It uses the custom `RestoreDefaults(title:question:message:button:)` init, as the Hidden Icons page does
(`IconsPage.swift:216`).”
