# 0.3.1 plan r3 review: design, UX copy and consistency

Plan = `docs/design/0.3.1/PLAN.md` at 8059eeb. DS = `docs/design/0.3/design-spec.md`. r2 = `review-r2-design.md`.

Result: 0 Blockers, 1 Major, 15 Minors. All 17 r2 findings are handled. N3 is mostly fixed, with small gaps left; N8 was resolved with a different decision, which I accept. Part E has one Major.

## r2 findings: fixed or not fixed

| r2 | Topic | Status | Note |
|---|---|---|---|
| N1 | Upgrade item unreachable | Fixed | Stays in the footer (A1, A6) |
| N2 | Segment images, `.fit` | Fixed | Equal widths first; widths include the attention image; DS §3.3 exception; no active image |
| N3 | B7 kinds and conditions | **Mostly** | Kinds, ids, `ControlID` wrapper and the new states are all right. Some `when:` and `menu:` gaps remain → R3-m1 |
| N4 | Preset ellipses | Fixed | `AwakePreset.title + "…"`; note row removed |
| N5 | Pending text | Fixed | B0: Waiting for Password… / Turning On… / Turning Off… |
| N6 | Advanced footer | Fixed | Names the mode and the Awake page level. Line count → R3-m3 |
| N7 | Refusal wording | Fixed | B2 table. Leftover refusal hedging → R3-m5 |
| N8 | Missing strings, Not Now scope | Fixed, different decision | Toast and `.lidEnded` text added. "Not Now" hides the rows everywhere until relaunch (parity M2); "Keep Sleep Off" added. Accepted. `.lidEnded` wording → R3-m6 |
| N9 | Replace toast | Fixed | "Replaced the running session." |
| N10 | Translocated text | Fixed | Kit sibling string |
| N11 | Indicator badge | Fixed | `lidActiveSymbol` per family, or a composited bar; distinct from N11's dot; HW-30 |
| N12 | Singular hours | Fixed | `AwakeCountdown.unit` (the cap is now a fixed 24 h) |
| N13 | "at … at" | Fixed | "Lid-closed mode ended at 3:12 AM: …" |
| N14 | `lidRoute` | Fixed | Three Kit variants |
| N15 | Menu Bar copy | Fixed | A3 footer; summary unchanged |
| N16 | "checkbox" | Fixed | |
| N17 | Full Keyboard Access and Switch Control | Fixed | A3, with a live refresh |

---

## New findings

### Major

#### R3-M1. Part E's controls point at a menu item that doesn't exist, use the wrong id prefix, and duplicate About's button
**Evidence.**
- E1: "**Snaptic › Check for Updates…** (the existing item)". E7: "Menu table (existing 'Check for Updates…' item) | — | Keeps its id".
- No such menu item exists. The app menu (AppDelegate.swift:221-232) has About Snaptic, Settings…, Hide and Quit. No status menu builds an update item.
- The existing control is the Settings › About button `about.page.checkUpdates` (AboutPageControls.swift:8-10; AboutPage.swift:36-38). It has the search entry "Check for Updates" and the help "Opens the Snaptic releases page in your browser."
- E7 declares `general.updates.autoCheck`, `general.updates.autoInstall` and `general.updates.checkNow` in `GeneralPageControls`. That table's surface is `general.page` (GeneralPageControls.swift:6), and `ControlRegistryTests` requires every id to start with its surface. Step 0 would be red.
- `general.updates.checkNow` is a `.button` on a Settings surface, so `requiresSearch` is true. It has no `SearchSpec`. Even with one, Settings search would then list two "Check for Updates" results on two pages.
- `general.updates.autoInstall` (`.setting`) also has no `SearchSpec`.
- `keys: ["SUEnableAutomaticChecks"]` "listed … in `ControlLegacy.internalKeys`" is the wrong category. `keys` and `internalKeys` are **config-model key paths** (ControlLegacy.swift:62 "Config key paths that are state, not controls"). The cross-check (ControlRegistryTests.swift:176-191) walks only `DisplaysConfig`, `ModulesConfig` and `AwakeConfig` fixtures. The precedent for a setting stored outside Snaptic's config is `general.page.openAtLogin`, which has no `keys` at all.

**Fix.** Pick one home for updates, with one check button.
- **Preferred: the About page.** It already holds the version, "Check for Updates…" and the network sentence that changes (AboutPage.swift:56). Then:
  - reuse `about.page.checkUpdates`, with help "Checks GitHub for a newer version of Snaptic." when Sparkle is present, and the 0.3 help otherwise;
  - add `about.page.autoCheck` (`.setting`, no `keys`, `SearchSpec("Check for updates automatically", keywords: ["updates", "sparkle", "auto update", "version"], root: SettingsRootID.about)`);
  - add `about.page.autoInstall` (`.setting`, `when: [.parentOn(ControlID("about.page.autoCheck")), .state(.updaterAvailable)]`, `SearchSpec("Download and install updates automatically", keywords: ["auto install"], …)`);
  - add `ControlState.updaterAvailable` and put it on both toggles.
- **If it must be General:** use `general.page.updates.*` ids. Drop `checkNow` and keep `about.page.checkUpdates` as the only check control. Update General's page summary to "Startup, updates, command line, backup, and Safe Mode." (GeneralPages.swift:34).
- **Either way:**
  - drop "Snaptic › Check for Updates…" from E1;
  - if an app-menu item is wanted (the Sparkle convention), add it to AppDelegate's app menu, which has a permanent L6 ratchet row, as a new id;
  - remove the `internalKeys` sentence.

### Minor

#### R3-m1. Remaining B7 gaps
**Evidence.** B7, and the AwakeMenuRowsControls conventions (each menu spec has a `menu:` placement: `awakeMenu`, `startSubmenu`, …). `when:` is an existence condition: every listed condition must hold for the control to exist (ControlRegistry.swift:34-41).
- `menu.awake.lidClosed`: "`.state(.lidModeOn)` for the ✓ title". Putting it in `when:` would remove the off-state item. Keep `lidModeOn` out of `when:`, and record the ✓ as a comment or a `title` note.
- `menu.awake.lidSubmenu` and `menu.awake.lidCustom` have "—" as their condition. Give both `when: [.awakeFeature(.lidClosed)]`.
- Placements:
  - `lidClosed` and `lidSubmenu`: `menu: awakeMenu`;
  - `lidPreset` and `lidCustom`: a new `lidSubmenu = MenuPlacementSpec("Keep Awake with the Lid Closed submenu", customize: .none)`.
- `menu.snaptic.lidLeftover`, `.lidRestore` and `.lidKeepOff`: add `when: [.state(.lidLeftover)]`.
- `awake.custom.lidClosed`: add `when: [.awakeFeature(.lidClosed)]`.

#### R3-m2. The writable-bundle text stacks four lines of help under one toggle
**Evidence.** B1: the bundle text is "the toggle's secondary help (not a warning row)". The toggle's own help is two sentences, about 105 characters, and the bundle text is about 120 characters, so about four lines under one row. DS §2 "Help text": "Never stack more than two lines of help under one row." Secondary grey help is also the weakest way to show a security caveat. The house has a component for exactly this: `SettingsRowNote(text, fix:)` under a toggle (AwakeAdvancedSheet.swift:71, the Accessibility note under "Move the pointer slightly").
**Fix.** Keep the toggle help as it is. Show the bundle text as `SettingsRowNote(L("Your account can change this copy of Snaptic, so another app could change it and misuse the password prompt."), fix: StatusAction(title: L("Learn More…"), control: ControlID("awake.advanced.lidBundleLearnMore")))`. The B7 id already fits.

#### R3-m3. Footer length
**Evidence.** The B1 footer is now 3 sentences plus Learn More…, about 300 characters, so 4 lines in a 480 pt form. DS allows section caveats in footers, but rule 3 asks for about 90 characters per sentence. The first sentence is about 200.
**Fix.** Split it: "While lid-closed mode is on, your Mac can’t sleep for low battery or heat. Awake turns it off at the Awake page’s battery level (at least 10%), when your Mac gets hot, or after 24 hours. Use it on a hard surface, not in a bag. Learn More…"

#### R3-m4. "Keep Sleep Off" brings back a sentence that is now false
**Evidence.** B3.4: after **Keep Sleep Off**, "the value is reported as 'another app or command', as today". Today's row is "Sleep is turned off for this Mac by another app or command. Snaptic can’t change this." (OtherAssertionsSection.swift:17). Snaptic now can change it, through Turn Sleep Back On…; it chooses not to.
**Fix.** Change the 0.3.1 text to "Sleep is turned off for this Mac by another app or command. Snaptic leaves it as it is." Add it to B6's "UI strings" list.

#### R3-m5. The leftover refusal asserts what the other leftover strings only suggest
**Evidence.** B2 table: "Turn sleep back on first: an earlier lid-closed session didn’t finish." The leftover row and the restore prompt were softened to "may be from" / "may have been left off" (sec m9: a planted journal).
**Fix.** "Turn sleep back on first. It may have been left off by an earlier lid-closed session."

#### R3-m6. The `.lidEnded` toast breaks the toast pattern
**Evidence.** B3.3 toast: "Awake turned off: lid-closed mode ended with the lid closed." `AwakeEndText.toast` produces "Awake ended: <phrase>." (AwakePresentation.swift:94-105). The phrase "lid-closed mode ended with the lid closed" through that path reads "Awake ended: lid-closed mode ended…", which repeats "ended". The "Ended at 3:12 AM: …" line repeats it too.
**Fix.** Phrase: "lid-closed mode turned off while the lid was closed". That gives the toast "Awake ended: lid-closed mode turned off while the lid was closed." through the default branch, with no special case.

#### R3-m7. The deferral status covers only one of four reasons
**Evidence.** E4 lists four conditions that make an install wait: lid-closed mode, a pending display trial or busy queue, Safe Mode (paused), and a CLI hold (up to 1 h). But "the Updates row says 'Will install when lid-closed mode ends.'" covers only the first. The subject-less fragment also differs from the house's full-sentence status rows ("Safe Mode is on.").
**Fix.** Put the texts in Kit `UpdatePolicy.waitText`, with a test:
- "Version 0.3.2 will install when lid-closed mode ends."
- "…when the display change is kept or undone."
- "…when command-line holds end, or when Snaptic quits."
- "Updates are paused in Safe Mode."

#### R3-m8. The status row format and missing states
**Evidence.** E1: "Version 0.3.1 · Last checked today at 9:12 AM". `CFBundleVersion` becomes 301 (E4), so About's `SettingsText.version` shows "Version 0.3.1 (301)" (SettingsPageRules.swift:60-65). The two rows would disagree. The middle dot fits house style (AwakePresentation "Until 3:45 PM · 1h 12m left"). The relative date "today at" needs hand formatting in Kit (N12), and these states aren't specified: never checked, checking, failed, and update found but not installed.
**Fix.** Build it from `SettingsText.version(...)` plus a Kit `UpdateStatusText`:
- "Last checked today at 9:12 AM", "…yesterday at 9:12 AM", "…on Oct 12";
- "Not checked yet";
- "Checking…";
- "Snaptic couldn’t check for updates. Check your connection and try again." (rule 5);
- "Version 0.3.2 is ready to install."

On the About page (R3-M1, preferred), drop the version from this row, because the header already shows it.

#### R3-m9. Toggle help texts don't match what happens
**Evidence.**
- "Once a day, Snaptic asks GitHub whether a newer version is out. It sends nothing else." But E5 says GitHub sees "your IP address, a Sparkle User-Agent with the app version, and the macOS version". "Sends nothing else" sits next to a list of things that are sent.
- The auto-install help, "Updates install when you quit Snaptic, or when you choose Install and Relaunch.", describes the manual flow. With automatic install on, Sparkle downloads silently and installs at quit, with no Install and Relaunch window.

**Fix.**
- Auto-check: "Once a day, Snaptic checks GitHub for a newer version. GitHub sees your IP address and macOS version, nothing more."
- Auto-install: "Updates download in the background and install the next time Snaptic quits."

#### R3-m10. The ad-hoc build line doesn't tell the user what to do
**Evidence.** E1: "Updates are available in builds from GitHub Releases." The person reading it has a source build. The plan doesn't say whether the toggles still show; they do nothing without Sparkle.
**Fix.**
- Hide both toggles (`.state(.updaterAvailable)`, R3-M1).
- Show the status row "This copy was built from source, so it can’t update itself. Download Snaptic from GitHub Releases to get updates."
- `about.page.checkUpdates` keeps opening the Releases page (HW-37).

#### R3-m11. README "One network connection, for updates." is inaccurate
**Evidence.** E5 says Snaptic "contacts github.com". `releases/latest/download/appcast.xml` and the zip redirect to GitHub's asset host (`objects.githubusercontent.com` / `release-assets.githubusercontent.com`), which a firewall such as Little Snitch shows as separate hosts. A check plus a download is also more than "one connection". E5 lists AboutPage.swift:56 but gives no replacement for its footer ("Snaptic never connects to the network: no analytics and no automatic update checks.").
**Fix.**
- Heading: "**Network: only for updates, and only if you allow it.**"
- Body: "…contacts GitHub (github.com and its download host) once a day…".
- About footer: "Free and open source under the MIT License. Snaptic connects only to GitHub to check for updates, and only if you allow it. No analytics."
- site l.502 "No network." becomes "No tracking. Network only for updates you allow."

#### R3-m12. The B6 password advice now conflicts with Sparkle's installer prompt
**Evidence.** B6: "If Snaptic is installed owned by root (…), only enter your password right after you choose Keep Awake with the Lid Closed or Turn Sleep Back On… in Snaptic." E1: for root-owned copies, "macOS asks for an administrator password to install. That is Sparkle's own installer prompt." So the users who follow B6's advice will also get a third, legitimate prompt that the advice tells them to refuse.
**Fix.** B6: "…right after you choose Keep Awake with the Lid Closed, Turn Sleep Back On…, or Install and Relaunch in Snaptic." Name the Sparkle prompt in the README's process list (E8).

#### R3-m13. The General page summary and budget, if Updates stays there
**Evidence.** General's summary "Startup, command line, backup, and Safe Mode." (GeneralPages.swift:34) doesn't mention updates.
**Fix.** Covered by R3-M1. If the About page is chosen, nothing changes on General.

#### R3-m14. Sparkle's first-run question
**Evidence.** E1: Sparkle's standard "Check for updates automatically?" appears on the second launch. For an LSUIElement app this is a floating window with no Settings context, and its wording and buttons are Sparkle's, not house style.
**Fix.** No change in copy is needed: Sparkle's strings aren't `L()` text. But state in E1 that the window comes forward with `NSApp.activate`, and doesn't appear while onboarding is showing or in Safe Mode (HW-36).

#### R3-m15. The pending refusal toast doesn't fit a 30-second wait
**Evidence.** B2: "Snaptic is finishing an earlier lid-closed session. Try again in a minute." The pending window is 30 s (B3.4). That works, but it is the only refusal without a way forward if pending becomes leftover.
**Fix.** No text change. When pending becomes leftover, show the leftover rows at once (already in B3.4). Optionally, if the menu is open, the lid row shows "Finishing Earlier Session…" (disabled), so it doesn't look clickable and broken.

---

## Checked and found fine

- B0 pending texts are Title Case for disabled menu rows. The "Turning on lid-closed mode…" toast is sentence case. Ellipses mean "in progress" for disabled rows, as in "Starting…" and "Checking…" (AwakePage.swift:205, OtherAssertionsSection.swift:23).
- Leftover rows: "Sleep Is Turned Off" (status), "Turn Sleep Back On…" (asks), "Keep Sleep Off" (no input, no ellipsis), "Not Now" (house toast term). The Settings text uses ’ and hedges.
- Cap warning toast "Lid-closed mode turns off in 5 minutes. If the lid is closed then, your Mac goes to sleep." is sentence case, says the consequence, and is about 90 characters per sentence. The cap end toast says "24 hours", built with `AwakeCountdown.unit`.
- The "Ended at …: …" lines match the 0.3 pattern ("battery at 20%", "your Mac got hot", "time limit reached", "another app turned sleep back on", "Snaptic quit").
- The indicator glyph spec is template-only, distinct from N11's dot, and recorded in HW-30.
- The three `lidRoute` variants each say where to go, and the unavailable case keeps the 0.3 text.
- B7 ids and kinds:
  - `.statusAction` for page and Advanced leftover actions;
  - `.hardware(.battery)`;
  - `.parentOn(ControlID(…))`;
  - `.perItem("preset")` and `.perItem("module")`;
  - `ControlKind.menuTabBar`;
  - the three new `ControlState`s;
  - the `awake.custom` surface is exempt from search (SettingsIndex.swift:172).
- A1 and A3:
  - equal-width segments first, with tooltips per segment as HIG asks;
  - the attention exception recorded in DS;
  - the Menu Bar footer text, Title Case "Show … Tab" items, and positional ⌘n.
- Part E strings "Check for updates automatically" and "Download and install updates automatically" are sentence case, which matches house toggles ("Open at login"). The dependent row (`parentOn`) follows the `copyInstall` pattern. The " · " separator matches house style.
