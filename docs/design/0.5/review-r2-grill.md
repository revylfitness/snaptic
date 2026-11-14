# 0.5 plan review r2: Grill (product, strings, UX)

Reviewer: round-2 grill (product / UX / strings). Plan under review: `docs/design/0.5/PLAN.md` (r2, 1349 lines).

Grounding:

- The r1 grill (`review-r1-grill.md`) and the plan's §R1 dispositions. Nothing below repeats an r1 finding. Each
  finding is either new in r2's text, or a place where r2 doesn't yet carry out an accepted disposition (cited).
- Shipped sources: Settings pages, Advanced sheets, onboarding, the General page card, the Snaptic menu, the CLI
  grammars, and the 0.4 Hidden Icons module as the closest precedent.
- `README.md`, `docs/guide.md`, `docs/design/0.3/design-spec.md` (DS) and the 0.4 PLAN.
- DockDoor's behaviour is taken only from PLAN §1. No DockDoor or AltTab source was opened.

Q1–Q7 are settled and not reopened. Every proposal below stays inside them.

**Counts:** 0 Blockers, 7 Majors (G2-1 to G2-7), 8 Minors (G2-8 to G2-15).

Citation conventions:

- `PLAN:l.N` is a line of PLAN.md (r2).
- `DS:l.N`, `README:l.N` and `GUIDE:l.N` are lines of design-spec.md, README.md and `docs/guide.md`.
- Code is cited as a repo path with its line, for example `Sources/Snaptic/Icons/IconsModule.swift:167`.
- Proposed UI strings use curly apostrophes, as lint03 requires (G2-13).

## The Q2 question: does cutting "keys in previews" to ⌘W/⌘M/⌘H/⌘Q/Esc while engaged still honour Q2?

**Yes.**

- Q2 puts "keys in previews" in scope but names no key set (PLAN:l.54).
- The only parity reference is DockDoor's "⌘W, ⌘M and ⌘Q while hovering" (PLAN:l.130). r2's set (⌘W, ⌘M, ⌘H, ⌘Q
  and Esc) is a superset of it.
- Dropping arrows, Return and bare letters is what lets M40 hold: typing with the pointer parked on the panel still
  reaches the app. That cut was accepted at r1 (G-1, P-16; PLAN:l.1239).
- "While engaged" instead of "while hovering" is a safety rule, not a smaller scope.

**What isn't honoured yet** is discoverability and the target rules. As written, a user finds the keys only through
an Advanced help line that leaves out Esc. Some pointer positions could also let ⌘W or ⌘Q fall through to the
frontmost app. G2-1 fixes both without changing the key set.

---

## Majors

### G2-1 · Major · §4.5, §4.4, §4.1 rule 6 · The keys' targets, what gets swallowed, and how anyone learns the keys aren't defined

**Question.** While the panel is engaged, what does each key do when the pointer isn't on a card that supports it?
And how does a user find out the keys exist?

**Why it matters.**

- **Fall-through to the frontmost app.** Engagement is about the panel (PLAN:l.563–564), but the table acts on
  "the window or app under the pointer" (PLAN:l.567). Ground rule 4 says the tap swallows "only the keys they
  handle" (PLAN:l.89–90).
  - Scenario: the pointer rests on the header, in the gap between two cards, on a Finder card (Finder has no Quit),
    or on an other-Space card that "offers only Bring Forward" (PLAN:l.525). The user presses ⌘W.
  - If "handle" means "has a target", the key passes through and closes the frontmost document. M23 and M40 exist
    to prevent exactly that (PLAN:l.1127, l.1144).
  - ⌘Q over a gap is worse: it would quit the frontmost app.
- **⌘H on a hidden app.**
  - The right-click menu toggles to "Show Safari" (PLAN:l.545).
  - The key table only says "hides" (PLAN:l.567).
  - The header's Hide tooltip is fixed to "Hide Safari" (PLAN:l.549).
- **Esc and showing again.** §4.1 rule 6 locks the panel out after "a dismiss by click, Hide or Quit"
  (PLAN:l.470–471), but not after Esc.
  - Scenario: the user presses Esc, then moves back onto the same Dock item.
  - The plan doesn't say whether the panel shows again at once or stays away until the selection changes.
- **Nobody finds the keys.**
  - They're described only in the help of an Advanced switch (PLAN:l.581–582), and that help leaves out Esc.
  - The right-click menu items show no key equivalents (PLAN:l.541–547).
  - The secure-input rule turns off "the selection ring and key hints" (PLAN:l.577–578). Neither is defined
    anywhere in the plan, so there's nothing to turn off and nothing to test.

**Evidence.**

- Plan: PLAN:l.54, l.89–90, l.130, l.470–471, l.525, l.541–549, l.563–570, l.577–582, l.917–918 (the house's
  "Dock Previews (⌘n)" tooltip), l.1127, l.1144.
- Code:
  - `Sources/SnapticKit/Config/ConfigSwitcherFeatures.swift:80–89`: the switcher's hint line, "W close · M minimize
    · …", lists only the keys that work.

**Proposed answer.** Replace §4.5's "The table", "Secure input" and "Setting" bullets, and amend §4.1 and §4.4:

> - **The table.** While engaged, these five keys are always swallowed, whether or not they have a target:
>   - ⌘W closes, and ⌘M minimizes (or restores), the window whose card is under the pointer.
>   - ⌘H hides the previewed app, or shows it when it's hidden.
>   - ⌘Q quits the previewed app. It never quits Finder. Quitting Snaptic's own card goes through the normal quit
>     path (X-29).
>   - Esc hides the panel.
>   - A key with no target does nothing: the header, a gap, a card that offers only Bring Forward, or ⌘Q on Finder.
>     No handled key ever reaches the frontmost app.
>   - Each key does exactly what its menu item does, including §4.2's lockout and §4.4's after-action rule.
> - **§4.1 rule 6** reads "After a dismiss by click, Esc, Hide or Quit, …".
> - **Key hints** appear in two places, and only while the keys work: the setting is on, there's no kill switch, no
>   tripped breaker and no secure input.
>   - The card and header right-click menus show ⌘W, ⌘M, ⌘H and ⌘Q as key equivalents.
>   - The tooltips read “Close (⌘W)”, “Minimize (⌘M)”, “Hide Safari (⌘H)” (or “Show Safari (⌘H)”) and “Quit Safari
>     (⌘Q)”.
>   - Accessibility labels stay the bare words, as the menu tabs do (§4.19).
> - **Selection ring.** While engaged and the keys work, the card under the pointer shows a 2 pt accent ring, which
>   marks what ⌘W and ⌘M act on. Otherwise no card shows a ring. If no ring is wanted, delete "selection ring" from
>   the secure-input bullet instead.
> - **§4.4 header.** While the app is hidden, the Hide button, its tooltip and its label read “Show Safari”.
> - **Setting help:** “Press ⌘W to close, ⌘M to minimize, ⌘H to hide, or ⌘Q to quit what’s under the pointer. Esc
>   dismisses the preview.”
> - **M23 adds:** with the pointer on the header or in a gap, ⌘W and ⌘Q do nothing and reach no app.
> - The README's Dock Previews section lists the five keys (G2-14).

---

### G2-2 · Major · §4.13, §4.17 row 3, §4.21 · Safe Mode: "doesn't start" can't produce row 3's status, its menu row, or the Safe Mode refusal

**Question.** In Safe Mode, does `start()` run, what does it register, and what does `snaptic dock status` answer?

**Why it matters.**

- Four statements in the plan can't all be true:
  - §4.13: "Dock Previews doesn't start in Safe Mode" (PLAN:l.790).
  - §4.21: the verbs are "registered only while the module runs" (PLAN:l.938).
  - Row 3: `dock status` answers `paused`, reason `safeMode` (PLAN:l.839).
  - §4.21's refusal list includes "Dock Previews is paused in Safe Mode." (PLAN:l.951).
- If the module doesn't start, no verb is registered. The CLI then gives the off answer, `Unknown command` (exit 2).
- That is exactly what 0.4 does. Hidden Icons sets `.degraded("Paused in Safe Mode")` and returns before
  `cli.start` (`Sources/Snaptic/Icons/IconsModule.swift:167–171`, `:219`). Copying that shape loses row 3's CLI
  cell and the refusal without anyone noticing.
- **Scenario:** a Mac is in Safe Mode after a crash. A support script runs `snaptic dock status --json` and gets
  "Unknown command". It reports Dock Previews as off, while Settings says "Paused in Safe Mode".
- "Doesn't start" also leaves open who sets the page and menu rows. An unstarted module's state is `.stopped`, which
  isn't any row of the table.

**Evidence.**

- Plan: PLAN:l.790, l.839, l.938, l.947–951, l.1137 (M33).
- Code:
  - `Sources/Snaptic/Icons/IconsModule.swift:164–171`, `:219`.
  - `Sources/Snaptic/Icons/IconsCLI.swift:6`: "The verbs are registered only while the module runs, so an off
    module answers the house "Unknown command"".

**Proposed answer.** Replace PLAN:l.790 with:

> - In Safe Mode, `start()` sets the state to paused (`safeMode`), registers the three `dock` verbs and returns. It
>   creates no observer, tap, panel, capture or cache lease. The page row and the menu row read “Paused in Safe
>   Mode” (§4.17).
> - `dock status` answers row 3. `dock pause` and `dock resume` refuse with “Dock Previews is paused in Safe Mode.”
>   (exit 5).

- Change §4.21's first bullet to: "**Verbs**, registered whenever the module is on (in every row from 3 to 9), and
  never while it's off or killed:".
- M33 adds: "`snaptic dock status` prints `state=paused reason=safeMode`".

This intentionally differs from Hidden Icons in 0.4. The alternative is to follow 0.4: change row 3's CLI cell to
`Unknown command` (exit 2) and delete the refusal. I recommend the first, because a status verb that reports "off"
for a module that is on misleads anyone who scripts it.

---

### G2-3 · Major · §4.10, §4.18, §4.20, §2.6 · Shared privacy: either module's Restore Defaults wipes the other's protected apps, the store's home is unstated, and two promises go stale

**Question.** Where does the shared slice ("Protect private windows" and its app list) live? And what do the
switcher's and the Dock's Restore Defaults do to it?

**Why it matters.**

- **Restore Defaults reaches across modules.**
  - The switcher sheet's Restore Defaults calls `settings.reset()`, which is `config = Config()`. That resets
    `protectPrivateWindows` and `privateBundleIDs`.
  - The Dock main page's Restore resets "Advanced settings" (PLAN:l.888–890), and the Dock sheet's own Restore
    resets "Advanced settings only" (PLAN:l.904). The shared rows are on that sheet (PLAN:l.901).
  - **Scenario:** a user adds their banking app to the protected list on the switcher sheet. Weeks later, they
    restore Dock Previews' defaults to undo a slider experiment. The banking app is no longer protected, so its
    thumbnails show in both the switcher and the Dock panel. The confirmation never mentioned the switcher.
- **The store's home is unstated.**
  - §4.10 puts the slice in "a `WindowServices` config slice" (PLAN:l.707–708), without saying which store or
    keys.
  - If it moves out of the switcher's `Config`, 0.4 reads stale or default values after a downgrade. "Downgrading
    to 0.4 keeps every setting" (PLAN:l.932–934) and M30 (PLAN:l.1134) are then false for exactly the setting
    that matters most.
- **The switcher's Privacy footer is stale.**
  - It reads "Thumbnails stay in memory, are never saved, and are cleared when your Mac locks or sleeps."
    (`Sources/Snaptic/Switcher/SettingsView.swift:113`).
  - With 30-minute retention and a cache shared with the Dock (PLAN:l.337), that's incomplete. H9 doesn't list it.

**Evidence.**

- Plan: PLAN:l.337, l.707–708, l.888–890, l.901, l.904, l.932–934, l.1134.
- Code:
  - `Sources/Snaptic/Switcher/Settings.swift:254–256`, `:380`.
  - `Sources/Snaptic/Switcher/SettingsView.swift:21–23`, `:105–121`.
  - `Sources/Snaptic/SettingsUI/PageFooterButtons.swift:60–62`.

**Proposed answer.** Add to §4.10:

> - **Home.** The slice stays in the Window Switcher's store under its existing keys (`protectPrivateWindows`,
>   `privateBundleIDs`). `WindowServices` reads it from there, and the Dock sheet writes it there. Nothing migrates,
>   and 0.4 reads the same values after a downgrade. M30 checks a protected app added in 0.5.
> - **Restore Defaults** never touches the slice, on either page or either sheet. `Settings.reset()` keeps those
>   two fields. Only General › Reset All Settings resets them.
>   - Switcher sheet message: “Window Switcher settings go back to their defaults. Protect private windows and its
>     app list stay as they are, because Dock Previews uses them too.”
>   - Dock sheet message: “Advanced settings go back to their defaults. Protect private windows and its app list
>     stay as they are, because the Window Switcher uses them too.”
>   - Dock page message: G2-8.
> - **Privacy footer**, on both sheets: “Thumbnails stay in memory and are never saved. They’re cleared after 30
>   minutes, and when your Mac locks or sleeps. These settings also apply to Dock Previews.” On the Dock sheet, the
>   last sentence names the Window Switcher instead.

H9 adds `Sources/Snaptic/Switcher/SettingsView.swift:113` (G2-14).

---

### G2-4 · Major · §4.18 Advanced, §4.10 · One sheet, two app lists with near-synonym names that do different things

**Question.** On the Dock Advanced sheet, how does a user tell "Never show thumbnails for" (shared) from "Don't show
previews for" (Dock only)?

**Why it matters.**

- Both lists sit on the same sheet (PLAN:l.901–902), and to most people a thumbnail is a preview. They do very
  different things:
  - "Never show thumbnails for": the panel still appears, showing the app's icon and name, with no title
    (PLAN:l.709–710).
  - "Don't show previews for": no panel at all, and the switcher isn't affected (PLAN:l.658).
- **Scenario 1:** a user wants their banking app kept out of screen shares. They add it to "Don't show previews
  for". The Dock stops showing it, but the switcher still shows its thumbnails.
- **Scenario 2:** a user wants 1Password never to pop a panel. They add it to "Never show thumbnails for", and the
  panel still pops.
- The shipped help, "These apps show their icon instead of a thumbnail." (`SettingsView.swift:117`), says too
  little. A protected item's title is hidden too (`Sources/Snaptic/Switcher/WindowManager.swift:23`: "Never
  captured, and the title is hidden").
- r1 G-4 (accepted) says Dock Previews uses the switcher's wording where the switcher has the same concept. The
  switcher's concept here is "Apps hidden from the switcher" (`SettingsView.swift:102`).

**Evidence.**

- Plan: PLAN:l.658, l.672, l.707–710, l.901–902; r1 G-4 (PLAN:l.1265).
- Code: `Sources/Snaptic/Switcher/SettingsView.swift:102`, `:116–120`;
  `Sources/Snaptic/Switcher/WindowManager.swift:23–24`.

**Proposed answer.** In §4.18's Advanced list:

> - **Apps hidden from Dock previews** (replaces “Don’t show previews for”). Help: “Pointing at these apps in the
>   Dock shows nothing. The Window Switcher isn’t affected.”
> - The shared list keeps “Never show thumbnails for”. Its help on both sheets: “These apps show their icon and name
>   instead of a picture or window title, in the Window Switcher and Dock Previews.”
> - On the Dock sheet, the two shared rows sit in their own **Privacy** section, with G2-3's footer, away from the
>   Dock-only list.

Update l.658 and l.672 to the new name.

---

### G2-5 · Major · §4.16, §4.17 row 7, §4.11, §4.2 · VoiceOver: row 7 says "Paused" while clicks still act, it has no way out, and "Show previews while VoiceOver is on" hides the panel by the pointer

**Question.** What does a VoiceOver user see on the page? And with "Show previews while VoiceOver is on", what
dismisses the panel?

**Why it matters.**

- **"Paused" while clicks still act.**
  - Row 7 reads "Paused while VoiceOver is on" (PLAN:l.843), but Dock click actions keep running under VoiceOver
    (PLAN:l.732–733).
  - **Scenario:** a VoiceOver user with "Hide the App" set reads "Paused" and expects nothing to happen. Clicking
    the active app's Dock icon then hides it.
- **No way out on row 7.** Row 6 offers [Advanced…], but row 7 offers nothing. The only switch that changes row 7
  is in Advanced.
- **The switch can't work as written.** With the switch on, rule 5's exception lets the selection alone drive the
  panel (`byPointer == false`; PLAN:l.463–464). But §4.2's grace hides the panel 0.25 s after the pointer is
  "outside the item, the corridor and the panel" (`left`), and the safety net hides it after 1 s outside the Dock
  zone (PLAN:l.486–488). Both are pointer tests.
  - Scenario: a VoiceOver user's pointer sits over a document. Every panel hides a quarter-second after it shows.
  - If the Dock's selection clears when the VoiceOver cursor moves into the panel, `noItem` (PLAN:l.456–457) hides
    it too. S0-16 records how VoiceOver reaches the panel, but the rules don't say what changes.

**Evidence.**

- Plan: PLAN:l.456–457, l.463–464, l.486–488, l.732–733, l.820–828, l.842–843, l.859–860, l.1126 (M22).

**Proposed answer.**

> - **Row 7:** “Paused while VoiceOver is on” [Advanced…]. When a Dock click action or Restore all minimized
>   windows is on, the row reads “Previews are paused while VoiceOver is on. Dock click actions still work.”
>   [Advanced…]. The [Advanced…] button opens the sheet at “Show previews while VoiceOver is on”.
> - **`dock status`** reports `clickActions` as its effective value, so it stays `on` in row 7 (G2-12).
> - **§4.2, new bullet.** While `byPointer == false`:
>   - swap intent, the corridor, the grace (`left`) and the safety net don't run;
>   - the panel hides when the selection moves to another item or empties (`noItem`), on an activation, or on the
>     latch;
>   - while the VoiceOver cursor is in the panel, an empty Dock selection doesn't hide it.
> - **M22 adds:** with the switch on and the pointer parked over a document, VoiceOver moves into the panel and the
>   panel stays.

---

### G2-6 · Major · §4.17, §4.18, §4.12, §4.14, §4.9 · The state table doesn't say what the page shows around each row, and five rows have no strings

**Question.** For each row, which controls and footer buttons show? And what exactly do the rows the plan names
without text say?

**Why it matters.** These all show on the page, and none can be built from the plan as written:

1. **Controls and footer per row.**
   - In 0.4, Hidden Icons shows its controls and Advanced… only while running (`IconsPage.swift:79–99`).
   - Row 6's [Advanced…] and G2-5's row 7 exit both need the sheet while paused.
   - Scenario: a user who just turned Dock Previews on wants to set the delay before quitting DockDoor. Under the
     0.4 rule, they can't.
   - There's also no "Starting…" row between turning the module on and the observer attaching. Icons has one.
2. **S0-19's "the page explains why"** (PLAN:l.699–701) has no string. The same goes for where the Y-7 note
   (PLAN:l.699–700) sits.
3. **Per-feature kill switches** leave controls that look live.
   - With `Dock.disable.clickActions` set, controls 6 and 7 still look live but do nothing. The same goes for
     "Keyboard shortcuts in previews" under `Dock.disable.keys`.
   - The house rule is a disabled control with `DefaultsLockRow(key:)` under it
     (`DisplaysFeatureGroups.swift:186–195`, `AwakeAdvancedSheet.swift:52–58`, `StatusRow.swift:80–83`).
   - The sheet's Diagnostics lock row for `Modules.disable.dockPreviews` (PLAN:l.903) can't be reached: row 1
     already shows it, and with the module killed no sheet opens.
4. **The crash-guard row names one feature for seven symbols.**
   - §4.12 gives "both pages" a "stopped" row (PLAN:l.757), but §4.17's text names only "Thumbnails of minimized
     windows" (PLAN:l.854–855).
   - A stopped `raise` or `spaces` symbol would show the wrong sentence, or none.
5. **Permission strings.**
   - If S0-9 finds that the click tap needs Input Monitoring, the plan adds "that permission and its row"
     (PLAN:l.802–803). But `Permission` has only `accessibility` and `screenRecording`
     (`Sources/SnapticKit/KitModules.swift:22`). There's no pane name (which changes on macOS 27, as Accessibility's
     does), no purpose and no row text.
   - The Permissions page builds each row from one purpose per permission plus "Needed by …"
     (`PermissionsPage.swift:182`, `PermissionFlow.swift:274–281`). So §4.14's "row purpose … 'Pictures of your
     windows in Dock previews.'" (PLAN:l.798–799) has nowhere to go.
   - The Accessibility purpose ("…list and switch windows, and read display keys.") doesn't mention the Dock.

**Evidence.**

- Plan: PLAN:l.699–701, l.757, l.763–769, l.798–803, l.837–857, l.878–887, l.903.
- Code:
  - `Sources/Snaptic/Icons/UI/IconsPage.swift:79–99`.
  - `Sources/Snaptic/Displays/UI/DisplaysFeatureGroups.swift:186–195`.
  - `Sources/Snaptic/Awake/UI/AwakeAdvancedSheet.swift:52–58`.
  - `Sources/Snaptic/Core/PermissionsPage.swift:182`.
  - `Sources/Snaptic/Core/PermissionFlow.swift:264–281`.
  - `Sources/SnapticKit/KitModules.swift:22`.

**Proposed answer.** Add to §4.17:

> - **Around the row.** Rows 1 and 2 show only their row. Rows 3 to 9 show the seven controls and the footer
>   (Advanced…, Restore Defaults…), so a paused module can still be set up.
> - **Starting:** “Starting…”, until the Dock observer attaches or row 5 applies. No menu row; `dock status` gives
>   `starting`.
> - **Kill switches.**
>   - `Dock.disable.clickActions` disables controls 6 and 7 and shows `DefaultsLockRow(key:)` under them.
>   - `Dock.disable.keys` does the same for “Keyboard shortcuts in previews”.
>   - The Diagnostics section lists only `Dock.disable.*` and `Windows.disable.*`.
> - **Crash guard:** one row per stopped feature, each with [Try Again], in §4.12's table order:
>   - `hwCapture`: “Thumbnails of minimized windows and windows on other Spaces stopped after a problem in macOS.
>     Snaptic tries them again after a macOS update.”
>   - `axWindowID`: “Matching cards to their windows stopped after a problem in macOS, so some windows can only be
>     brought forward. Snaptic tries again after a macOS update.”
>   - `raise`: “Bringing a window forward from another Space stopped after a problem in macOS, so it switches to
>     the app instead. Snaptic tries again after a macOS update.”
>   - `spaces`: “Showing windows on other Spaces stopped after a problem in macOS. Snaptic tries again after a macOS
>     update.”
>   - `symbolicHotKeys` and `layoutType` show on the Window Switcher page only.

And to §4.9 and §4.14:

> - **If S0-19 finds a per-call alert**, the Thumbnails help adds: “Off by default, because macOS shows a screen
>   recording alert each time Snaptic takes a picture of a window.” The Y-7 sentence is the footer of the section
>   that holds Thumbnails.
> - **Accessibility purpose:** “Lets Snaptic see its shortcuts, list and switch windows, read display keys, and read
>   the Dock.” Screen Recording's purpose already covers previews, so §4.14's Dock-only purpose string is dropped.
> - **If S0-9 picks Input Monitoring:**
>   - K1 adds `Permission.inputMonitoring`, with its pane name on 15 and on 27 as recorded by S0-9.
>   - Purpose: “Lets Snaptic notice Dock clicks for Dock click actions.”
>   - Added row, shown while a click action or Restore all minimized windows is on: “Dock click actions need
>     \(paneName(.inputMonitoring)).” [Open Privacy Settings…].
>   - The downgrade check (H7) decodes a backup that names the new case.

---

### G2-7 · Major · H1, §4.17, §4.19 · The default menu presence is never stated, and with r1's `.hidden` nobody sees the section, Pause, or the attention mark

**Question.** What is `ModulesConfig.defaultPreferences(.dockPreviews).presence`? And where does a revoked
Accessibility show itself?

**Why it matters.**

- H1 gives `allowed` and `fallback` (`.hidden`) but never the default (PLAN:l.348–349). H7 only says the fixtures
  give the Dock `.inSnapticMenu` (PLAN:l.386–387). r1 G-3 proposed `.hidden`.
- **Pause and the section are unreachable.** With `.hidden`, the §4.19 section isn't in the Snaptic menu. That
  section is everything the plan builds there: the status item, "Pause for 1 Hour" and "Dock Previews Settings…".
  It's unreachable unless the user changes presence on the Menu Bar page.
- **The attention mark can't show.**
  - The "menu-bar attention mark" for rows 4 and 5 and a tripped breaker (PLAN:l.857) is the tab-bar mark.
  - `MenuTabs.attention` marks only tabs (`Sources/SnapticKit/MenuLayout.swift:184–187`, fed by
    `Sources/Snaptic/Core/StatusMenu.swift:663–670`). A hidden module has no tab, so the mark can't show.
  - **Scenario:** after a macOS update resets Accessibility, previews just stop. Nothing in the menu bar says why.
    The user concludes Dock Previews is broken.
- **r1's reason doesn't decide this.** r1 G-3's reason for `.hidden` was that "a new menu bar icon would only add
  clutter". `.inSnapticMenu` adds no icon, only a tab, which is how Hidden Icons ships: `enabled: false, presence:
  .inSnapticMenu`, fallback `.inSnapticMenu` (`ConfigModules.swift:228`, `KitModules.swift:99–114`).
- **`resetMenu()` needs a defined default.** It restores each module to its default presence
  (`ConfigModules.swift:303–311`), so the default is user-visible there too.

**Evidence.**

- Plan: PLAN:l.348–349, l.386–387, l.857, l.910–920, l.1148 (M44); r1 G-3 (PLAN:l.1264).
- Code:
  - `Sources/SnapticKit/Config/ConfigModules.swift:224–230`, `:303–311`.
  - `Sources/SnapticKit/KitModules.swift:99–114`.
  - `Sources/SnapticKit/MenuLayout.swift:184–187`.
  - `Sources/Snaptic/Core/StatusMenu.swift:663–670`.
  - `Tests/SnapticKitTests/ConfigModulesTests.swift:12–17`.

**Proposed answer.** Recommended, in H1:

> - `defaultPreferences(.dockPreviews)` is `enabled: false, presence: .inSnapticMenu`, as for Hidden Icons, and
>   `fallback(for: .dockPreviews)` is `.inSnapticMenu`. A tab adds no menu bar icon.
> - `ConfigModulesTests` asserts `presence(.dockPreviews) == .inSnapticMenu`, and that `resetMenu()` restores it.
> - §4.19's "Only module" rule and M44 then hold with no special case.

If the owner keeps `.hidden`, H1 must say so and §4.17 must say:

> - With Dock Previews hidden from the Snaptic menu, rows 4 and 5 and a tripped breaker show only in Settings.
> - "Pause for 1 Hour" is reachable only after Menu Bar › Show in Snaptic Menu.

Known limitations then gains: "Dock Previews doesn't show in the Snaptic menu until you choose Show in Snaptic Menu
on the Menu Bar page."

---

## Minors

### G2-8 · Minor · §4.18 · Settings page: no section for the Dock click actions, one wrong highlight, labels that break r1 G-4's wording rule, and a non-house Restore message

**Question.** Are the page's labels, layout and Restore message final?

**Why it matters.**

- **No section for the Dock click actions.**
  - Controls 6 and 7 are a different feature from controls 1–5, with a different trust story: a listen-only tap.
    They sit in the same list with no header.
  - DS allows up to 3 primary Sections (DS:l.11, l.53–58).
- **Wrong highlight.** "Its windows appear above the Dock" is wrong for a left or right Dock (PLAN:l.875, l.508).
- **Labels that break r1 G-4's rule.** r1 G-4 (accepted) says that where the switcher already has a setting, the
  Dock page uses the switcher's wording. Two labels don't:
  - "Thumbnails" (PLAN:l.882). The switcher's is "Window thumbnails" (`SettingsView.swift:27`,
    `ConfigSwitcherFeatures.swift:95`), and its permission row reads "Window thumbnails need Screen Recording."
    (`SwitcherPages.swift:121`).
  - "Show when an app has no open windows" (PLAN:l.897). The switcher's is "Apps with no open windows"
    (`ConfigSwitcherFeatures.swift:98`).
- **Restore message.** "…go back to how they were when you installed Snaptic" (PLAN:l.889–890) appears nowhere in
  the sources. Every shipped message uses "… go back to their defaults." (`MenuBarPage.swift:111`,
  `CustomizeMenuSheet.swift:49`, `IconsPageRules.swift:446`).
- **Slider.** The slider's step isn't given (PLAN:l.879–880).

**Evidence.**

- Plan: PLAN:l.508, l.875, l.878–890, l.897.
- r1 G-4 disposition: PLAN:l.1265.
- Code: the files cited above.

**Proposed answer.**

> - Controls 6 and 7 go under a section header, “Dock click actions”. Section footer: “Snaptic only watches Dock
>   clicks. The Dock still handles every click as usual.”
> - Highlight 1: “Point at an app in the Dock” / “Its windows appear next to the Dock, including minimized and
>   hidden ones.”
> - Control 3 becomes “Window thumbnails”. Help: “Pictures of your windows. Off: titles only, and no Screen
>   Recording needed.” Added row: “Window thumbnails need Screen Recording. Until then, previews show window
>   titles.”
> - The Advanced switch becomes “Apps with no open windows”, keeping its help.
> - Slider: 0 to 1 s in 0.1 s steps, with tick marks. The value reads “0.1 s” to “1 s” (`SentenceText.unit`), or
>   “Immediately” at 0.
> - Restore message: “Preview, Dock click, and Advanced settings go back to their defaults. Dock Previews stays on.
>   Protect private windows and its app list stay as they are, because the Window Switcher uses them too.”

---

### G2-9 · Minor · §4.17 row 4, §4.19 · Snaptic menu: row 4 shows the Open item twice, and Pause shows where it means nothing

**Question.** In each state, which rows does the menu section show?

**Why it matters.**

- **Row 4 shows the Open item twice.** Row 4's menu cell *is* "Open \(paneName(.accessibility)) Settings…"
  (PLAN:l.840). §4.19 then lists the status item, *and then* that same Open item "in state 4 only"
  (PLAN:l.913–914). So state 4 shows it twice. 0.4's status item for this case is "Needs Permission"
  (`IconsMenuRows.swift:99`).
- **Pause shows where it means nothing.** "Pause for 1 Hour" is offered in every state except 8 (PLAN:l.915).
  - Pausing in Safe Mode, while DockDoor runs, or under VoiceOver either does nothing or is refused by the CLI.
  - Its label doesn't name the module, while its partner does ("Resume Dock Previews"). Awake names its subject
    ("Pause Rules for 1 Hour" / "Resume Rules", `AwakeMenuRows.swift:262–272`).
- **Case (optional).** DS lists "status rows" under sentence case (DS:l.640), and 0.4 reuses the Settings reason
  string in the menu ("Paused while \(hider.name) runs", `IconsHiddenList.swift:108` via `IconsMenuRows.swift:97`).
  r1 G-3 asked for Title Case, so either is defensible. Reusing one string halves the canonical list.

**Evidence.**

- Plan: PLAN:l.837–845, l.912–916.
- Code:
  - `Sources/Snaptic/Icons/IconsMenuRows.swift:96–99`.
  - `Sources/SnapticKit/IconsHiddenList.swift:106–116`.
  - `Sources/Snaptic/Awake/UI/AwakeMenuRows.swift:262–272`.

**Proposed answer.**

> - Row 4 menu cell: “Needs Permission”, then §4.19 item 2.
> - §4.19 item 3: “Pause Dock Previews for 1 Hour” in row 9 only, and “Resume Dock Previews” in row 8 only. Neither
>   shows in rows 3 to 7.
> - Optional: rows 3, 6, 7 and 8 reuse their Settings strings in the menu (“Paused while DockDoor runs”).

---

### G2-10 · Minor · §4.15, §4.17 row 6 · The other-tool pause: when the footnote shows, which tool is named, and where [Advanced…] lands

**Question.** When is the "Both apps show a preview…" footnote shown? Which tool does row 6 name when two are
running? And where does row 6's button land?

**Why it matters.**

- **The footnote.** §4.15 gives the footnote without a condition (PLAN:l.813–815). 0.4 shows its footnote only
  while Run Both Anyway is chosen (`IconsAdvancedSheet.swift:69–71`), because it describes that choice.
- **Two tools.** `KnownDockTools` can match more than one running app. "Paused while … runs" names one, and 0.4's
  reason takes a single hider (`IconsHiddenList.swift:108`).
- **Where [Advanced…] lands.** Q5 says the page "offers Run Both" (PLAN:l.57). Row 6 does that through
  [Advanced…], so the sheet must open at the pop-up.

**Evidence.**

- Plan: PLAN:l.57, l.805–816, l.842.
- Code: `Sources/Snaptic/Icons/UI/IconsAdvancedSheet.swift:63–71`, `Sources/SnapticKit/IconsHiddenList.swift:108`.

**Proposed answer.**

> - The footnote shows only while “Run Both Anyway” is chosen.
> - With more than one known tool running, row 6 names the first in `KnownDockTools` order.
> - Row 6's [Advanced…] opens the sheet at “When another app shows Dock previews”, using that row's anchor.

---

### G2-11 · Minor · §4.20 · The onboarding row doesn't match the page summary

**Question.** Why do onboarding and the page describe the module in two different sentences?

**Why it matters.**

- `ModuleSwitchRow.summary` is one string per module, and in 0.4 it equals the page summary. Hidden Icons uses "Hide
  the menu bar icons you don’t need behind an arrow." in both places (`ModuleSwitchRow.swift:22–30`,
  `IconsModule.swift:21`).
- The plan writes "Preview an app's windows…" for onboarding (PLAN:l.926) but "See an app's windows…" for the page
  (PLAN:l.873). The New card also says "See…" (PLAN:l.929).
- Two strings for one row is also one more canonical string to keep in sync.

**Evidence.**

- Plan: PLAN:l.873, l.926, l.929.
- Code: `Sources/Snaptic/SettingsUI/ModuleSwitchRow.swift:22–30`, `Sources/Snaptic/Icons/IconsModule.swift:21`.

**Proposed answer.**

> - **Onboarding row:** “Dock Previews” / “See an app’s windows when you point at it in the Dock.” Off. This is the
>   page summary, through `ModuleSwitchRow.summary`.

---

### G2-12 · Minor · §4.21, §4.17 · CLI: the clock-time reply, the pause rule, the status format, the missing `keys` field and some strings

**Question.** Are the CLI's replies, formats and help lines final?

**Why it matters.**

- **Clock-time reply.** "Dock Previews is paused until 3:45 PM." (PLAN:l.945) is a local, 12-hour clock. The house
  CLI reply uses ISO UTC: "Rules are paused until 2026-…Z." (`AwakeAutomation.swift:202–208`, "(ISO, UTC: no
  locale, no names)"). Scripts parse it.
- **The pause rule.** "A second pause extends the first" (PLAN:l.945) doesn't say what `pause 30m` does during a
  2-hour pause. Awake never shortens: `pause(seconds:onlyExtend: true)`.
- **Status format.** The plain `status` line has no format. `--json` has no key order or null rule, and `thumbnails`
  and `clickActions` have no value sets (PLAN:l.859–860). Hidden Icons pins all three
  (`IconsCommandGrammar.swift:122–139`).
- **`keys` is missing,** although §4.5 has a setting, a kill switch and a breaker for it.
- **Help and errors.**
  - The pause help says "Pause previews" (PLAN:l.941), but the pause also stops Dock click actions (PLAN:l.734,
    l.809).
  - No usage string is given. The permission refusal is shorter than 0.4's ("… Open Snaptic Settings ›
    Permissions.", `IconsCommandGrammar.swift:61–65`).
  - Row 5 (`dockUnreadable`) has no pause answer.

**Evidence.**

- Plan: PLAN:l.734, l.809, l.859–860, l.936–952.
- Code:
  - `Sources/Snaptic/Awake/Core/AwakeAutomation.swift:202–208`.
  - `Sources/SnapticKit/IconsCommandGrammar.swift:61–65`, `:122–139`.
  - `Sources/Snaptic/Icons/IconsCLI.swift:6`.

**Proposed answer.**

> - **Help lines.**
>   - `dock pause`: “Pause Dock Previews and its Dock click actions for a while (1 h if no time is given)”.
>   - `dock resume`: “Resume Dock Previews and its Dock click actions”.
> - **Pause.**
>   - Reply: “Dock Previews is paused until 2026-11-12T20:45:00Z.” (exit 0).
>   - A pause never shortens one already running: the later end wins, and the reply gives that end.
>   - Pausing in row 5 works as in row 9.
>   - Over 24 h is a usage error.
> - **Usage error:** “Usage error. Run “snaptic help dock”.” (exit 2).
> - **Permission refusal:** “Dock Previews needs \(paneName(.accessibility)). Open Snaptic Settings › Permissions.”
>   (exit 5).
> - **`dock status`** always exits 0.
>   - Plain format: `state=<…> reason=<…|-> until=<ISO|-> thumbnails=<…> clickActions=<…> keys=<…> cacheEntries=<n>
>     cacheBytes=<n>`.
>   - `--json` uses the same keys in the same order, then `observerAttached` and the §4.22 counters. Absent values
>     are `null`.
> - **Value sets:**
>   - `thumbnails`: `on` | `off` | `noPermission`.
>   - `clickActions` and `keys`: `on` | `off` | `paused` | `stopped` (breaker) | `disabled` (kill switch).
>   - Each is the effective value, so `clickActions` stays `on` in row 7 (G2-5).

---

### G2-13 · Minor · §4 (all quoted strings), §4.24 · The plan's strings use straight apostrophes, which lint03 rejects and the canonical test will copy

**Question.** Which form is canonical: the plan's or the source's?

**Why it matters.**

- PLAN.md contains no curly apostrophe. The 0.4 PLAN has 34.
- DS requires curly apostrophes and quotes in every `L()` string (DS:l.674), and lint03 fails on a straight one
  (`scripts/lint03.py:1186`).
- §4.24 makes the plan the source of `DockControlsTests`' canonical list, and says "a change to a string changes
  this plan in the same commit" (PLAN:l.976–978).
- **Scenario:** an implementer copies "Don't show previews for" from the plan. Either lint03 fails, or they curl it
  and the plan and test list drift from the first commit.
- Affected strings include "See an app's windows…", "Dock Previews can't read the Dock…", "Can't Read the Dock",
  "Don't show previews for", "Dock Previews isn't paused.", "what's under the pointer" and "Snaptic doesn't import
  DockDoor's settings."

**Evidence.**

- Plan: PLAN:l.974–978.
- DS:l.674.
- Code: `scripts/lint03.py:1186`, `Tests/SnapticKitTests/IconsControlsTests.swift:119–143` (0.4's list, curly).

**Proposed answer.**

> - **§4.24 adds:** "Quoted UI strings in this plan are written exactly as they appear in `L()`, with curly
>   apostrophes and quotes (DS §4)."
> - Every quoted string in §4 and H1 is curled in r3.

---

### G2-14 · Minor · H9 · Five places that H9 doesn't list

**Question.** Is H9 the complete list of docs and texts to change?

**Why it matters.** Each of these will be wrong or incomplete at release:

- **`GUIDE:l.9`** has the credits ("Hidden Icons follows the design of Hidden Bar…") and the release-notes list
  ("0.4.0, 0.3.1, and 0.3"). It needs the DockDoor credit and a 0.5.0 link. H9 changes only README l.278.
- **`GUIDE:l.60`** says "⌘1–⌘4 choose a tab". H9 changes README l.202's "(⌘1–⌘4)" but not this one.
- **`README:l.272`** is the release-notes row ("[0.4.0] · [0.3.1] · [0.3]").
- **`Sources/Snaptic/Switcher/SettingsView.swift:113`**: the Privacy footer (G2-3).
- **The README's Dock Previews section** doesn't list the five keys (G2-1). D1's outline should say it does.

**Evidence.**

- Plan: PLAN:l.408–430.
- Docs: GUIDE:l.9, l.60; README:l.202, l.272, l.278.

**Proposed answer.** Add these rows to H9:

> | `GUIDE:l.9` | Add “Dock Previews follows ideas from DockDoor (GPL-3.0) in its own code; it shares no code with it and isn’t affiliated with it.” and a 0.5.0 release-notes link |
> | `GUIDE:l.60` | “⌘1–⌘4” → “⌘1, ⌘2, and so on” |
> | `README:l.272` | Add [0.5.0](docs/design/0.5/RELEASE-NOTES-0.5.0.md) first |
> | `Switcher/SettingsView.swift:113` | The G2-3 Privacy footer |
> | README Dock Previews section | Lists ⌘W, ⌘M, ⌘H, ⌘Q and Esc, “while the pointer is in the preview” |

---

### G2-15 · Minor · §4.16, §4.10, §4.3 · Accessibility labels for private and small cards

**Question.** What does VoiceOver read for a private card, a protected app's card, and the two small cards?

**Why it matters.**

- The label rule is "\(title), \(app)" (PLAN:l.827), and a private card has "no VoiceOver title" (PLAN:l.709–710).
  The label that results isn't given.
- If it's built naively, it reads ", Safari", or leaks the title through a fallback.
- The small cards, "No open windows" and "No windows shown" (PLAN:l.516–521), have no label at all.

**Evidence.**

- Plan: PLAN:l.516–521, l.709–710, l.822–828.

**Proposed answer.** Add to §4.16:

> - **Private card:** label and tooltip “Private window, Safari”. For a protected app, the label is the same form,
>   for example “Private window, 1Password”.
> - **No open windows card:** “No open windows, Safari”.
> - **No windows shown card:** “No windows shown, Safari”, with the tooltip from §4.3 as its accessibility help.
> - **Header Hide button**, while the app is hidden: label and tooltip “Show Safari” (G2-1).
