# Snaptic 0.4 manual checks

The hands-on checks for Hidden Icons (PLAN §7), plus the S0 rows and launch checks that S0 left for the owner.
Release gate: every **B** (Blocker) row passes on macOS 27.2 and, where **L** is marked, on the macOS 15 VM (Length).

**Status:** Pending = not yet run · Pass · Fail (with a note, and a PLAN §R3 row if it changes the plan) · N/A.
Record the OS build and the date in the Notes column. The automated coverage listed under "Already covered" checks
the logic only; it doesn't replace the row.

Branch `feature/v040-hidden-icons`, 2026-11-07. Automated state at R: `swift test` 1917 tests, 0 failures;
`scripts/lint.sh --strict` clean; `--selftest-controls` and `scripts/selftest-control-server.sh` pass (including
`iconsCases`).

## Before the checks

| # | Check | Status | Notes |
|---|---|---|---|
| H8 | Quit the running Snaptic, then `SNAPTIC_SELFTEST_EXPECT_ICONS_SHIM=available .build/debug/Snaptic --selftest-launch` prints `available` and 4 modules / 0 running; record in STEP0-NOTES | Pass | 2026-11-09, macOS 27.2 (26B123), 88a2c5f: 4 modules / 0 running, icons items 0, shim available, poison path ok |
| S0-15 | Bartender's team id: `codesign -dv /Applications/Bartender*.app`, then fill `KnownMenuBarHiders` and STEP0-NOTES | Pending | Not installed on this host |

## S0 rows carried to R (STEP0-NOTES)

| # | Check | B | Status | Notes |
|---|---|---|---|---|
| S0-7 | Camera (FaceTime), mic (Voice Memos) and location indicators stay visible with their apps hidden (27.2) | B | Pending | Screen recording passed at S0 |
| S0-8 (a) | ⌘-drag an allowed item and the arrow while restricted | B | Pending | |
| S0-8 (c) | Clock timer and FaceTime Live Activity while restricted | B | Pending | |
| S0-8 (b), (d)–(f) | System Settings › Menu Bar, a banner, Control Center and Notification Center, Spotlight, screenshots, Dock | | Pending | (b) overflow chevron recorded at S0 |
| S0-9 | Safari AAC exam page (or an `AEAssessmentSession` test app): record `NSApp.currentSystemPresentationOptions`; our collapse and expand never lift the exam's restriction; the page says "Paused during an exam session" | B | Pending | Guard R2-4 is in the code |
| S0-13 | 15 VM: `Preferred Position` seeding for the arrow and a new item | | Not run | No VM on this host; README fallback if it fails |
| S0-14 | 15 VM: Length collapse with L = 10 000 on a 5K display; widths ≥ L − 1 on the next tick | B | Not run | No VM on this host |

## M1–M37

| # | Check | B | L | 27.2 | 15 VM | Already covered | Notes |
|---|---|---|---|---|---|---|---|
| M1 | Turn on: items appear left of the Snaptic icon; How to Arrange opens; nothing hides | B | L | Pending | Pending | | |
| M2 | ⌘-drag arrow, `\|`, `⋮`; positions survive relaunch | B | L | Pending | Pending | | |
| M3 | Items can't be ⌘-dragged out of the bar | | L | Pending | Pending | | |
| M4 | Arabic as primary language: order and glyphs mirror | | L | Pending | Pending | `IconsLayoutTests` RTL | |
| M5 | First collapse; 27 confirmation when nothing is shown | B | L | Pending | Pending | | Cancel is the default |
| M6 | Collapse / expand / ⌥ expand with AH on and off, dividers on and off: every §4.2.4 row | B | L | Pending | Pending | `IconsEngineCoreTests` truth table | |
| M7 | Invalid arrangement refuses collapse with the row text | B | L | Pending | Pending | `IconsLayoutTests` guards | |
| M8 | Awake session with Awake's icon left of `\|`: collapse refused | B | L | Pending | Pending | `IconsPolicyTests` ownItemsGuard | |
| M9 | Translocated copy (27): refuses with the identity text | B | | Pending | N/A | | |
| M10 | Kill switch `Icons.disable.native` while collapsed: expands at once | B | | Pending | N/A | `IconsEngineCoreTests` preemption | |
| M11 | Privacy indicators stay visible while their app is hidden | B | | Pending | N/A | | Same hardware session as S0-7 |
| M12 | Forced main-thread hang (`Debug.icons.hangMainSeconds`, DEBUG): icons return within 4 s (27) | B | | Pending | N/A | | |
| M13 | Auto-collapse waits while the pointer is in the band, a menu is open, a popover is open, Settings is open | B | L | Pending | Pending | `IconsPolicyTests` | |
| M14 | Auto-collapse resumes after 120 s of a stuck popover | | L | Pending | Pending | `IconsPolicyTests` 120 s cap | |
| M15 | Hover expands after 0.5 s; never activates Snaptic | | L | Pending | Pending | | |
| M16 | New app launch (27, Show): its icon stays shown; Hide: it's hidden and listed | B | | Pending | N/A | `IconsPolicyTests` new-icon rules | |
| M17 | Length new-icon toast once per day | | L | Pending | Pending | | |
| M18 | Sleep/wake, lock/unlock, FUS, display connect/disconnect: state correct | B | L | Pending | Pending | | |
| M19 | `killall MenuBarAgent` while collapsed: icons return and re-collapse | B | | Pending | N/A | | S0-6 recorded the harness case |
| M20 | Hidden Bar running: Snaptic pauses with the row text; resumes on quit | B | L | Pending | Pending | `IconsPolicyTests` hider pause | Hidden Bar not installed here |
| M21 | Full menu bar on: Snaptic active while shown; focus returns on collapse; Dock icon goes | | L | Pending | Pending | `IconsActivationRuleTests` | |
| M22 | Full bar + open Settings + collapse: Snaptic stays active | B | L | Pending | Pending | `IconsActivationRuleTests` | |
| M23 | Hidden list rows: names, "App — Title", icons, VO labels | | L | Pending | Pending | | |
| M24 | Choosing a row opens that app's menu; auto-collapse waits 60 s | B | L | Pending | Pending | | |
| M25 | Behind the Notch on a notched Mac; absent on an external-only setup | | | Pending | Pending | `IconsLayoutTests` notch split | |
| M26 | Four tabs with ⌘1–⌘4; Icons tab only with Arrow and Snaptic Menu | B | L | Pending | Pending | `MenuTabsTests` | |
| M27 | Hidden Icons as the only shared module: Snaptic menu shows its section and footer | | L | Pending | Pending | | |
| M28 | Settings page, Sections (both engines), Advanced, Restore, Reset Arrow Position | B | L | Pending | Pending | `IconsControlsTests` strings | |
| M29 | Arrow hidden in System Settings › Menu Bar (27): icons expand; Show Arrow recovers | B | | Pending | N/A | | |
| M30 | 27 permission states (§4.12), incl. relaunch hint | B | | Pending | N/A | `IconsPolicyTests` AX table | |
| M31 | Fresh install onboarding with Hidden Icons on: `.arrange` step; nothing hides | B | L | Pending | Pending | | |
| M32 | Upgrade from 0.3.4: New card; Turn On flow; downgrade back to 0.3.4 keeps settings | B | L | Pending | Pending | `ConfigIconsTests` downgrade decode | |
| M33 | `snaptic icons show/hide/toggle/status --json` and every exit-2 text | B | L | Pending | Pending | `IconsCommandGrammarTests`, `--selftest-controls` `iconsCases` | |
| M34 | Quit while collapsed: icons return (both engines) | B | L | Pending | Pending | | S0-12 recorded SIGKILL |
| M35 | Safe Mode: Hidden Icons doesn't start | B | L | Pending | Pending | | |
| M36 | Module off: no items, timers, monitors, or prompts (Activity Monitor + EventLog); on/off 20× with no leak (A5) | B | L | Pending | Pending | | |
| M37 | Backup with Hidden Icons settings: export, change, import; the preview lists "Hidden Icons: …" and `arranged` and per-app choices stay (R3-81) | B | L | Pending | Pending | `KitBackupTests` | |
