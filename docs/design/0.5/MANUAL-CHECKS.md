# Snaptic 0.5 manual checks

The hands-on checks for Dock Previews and the Window Switcher changes (PLAN §7), plus the S0 rows and launch checks
that S0 left for the owner. Release gate: every **B** (Blocker) row passes on macOS 27.2 and, where **V** is marked,
on macOS 15 (a VM, or an owner check on a 15 Mac).

**Status:** Pending = not yet run · Pass · Fail (with a note, and a PLAN §R4 row if it changes the plan) · N/A.
Record the OS build and the date in the Notes column. The automated coverage listed under "Already covered" checks
the logic only; it doesn't replace the row.

Branch `feature/v050-dock-previews`, 2026-11-14, macOS 27.2 (26B123). Automated state at R: `swift test` 2353 tests,
0 failures; `scripts/lint.sh --strict` clean. CI runs `--selftest-launch`, `--selftest-controls` and
`scripts/selftest-control-server.sh` on the PR.

## Before the checks

Both self-tests need the running Snaptic quit, and a token file like CI's:

```bash
dir=$(mktemp -d); token=$(od -An -N30 -tx1 /dev/urandom | tr -d ' \n')
printf '%s\n' "$token" > "$dir/token"; chmod 600 "$dir/token"
SNAPTIC_SELFTEST_TOKEN="$token" SNAPTIC_SELFTEST_EXPECT_WINDOWS_API=available \
  .build/debug/Snaptic --selftest-launch "$dir/token"
SNAPTIC_SELFTEST_TOKEN="$token" .build/debug/Snaptic --selftest-controls "$dir/token"
```

| # | Check | B | Status | Notes |
|---|---|---|---|---|
| L1 | `--selftest-launch` prints “5 modules, 0 running”, the window symbol lines with `available`, and the poison path `ok` | B | Pending | Record in STEP0-NOTES |
| L2 | `--selftest-controls` prints “3 Dock verbs, 20 command lines in Safe Mode, 10 rows” and no `selftest: dock verbs:` problem | B | Pending | |
| S0-15 | Team ids for DockDoor, DockDoor Pro, HyperDock, Dock Mate and DockView 2: download each into its own new, empty folder and run `codesign -dv --verbose=2` on the `.app` without opening it. Then fill `KnownDockTools` and STEP0-NOTES' S0-15 table | | Pending | None is installed on this Mac; until then K1 matches by bundle id only |
| S0-32 | DockDoor as a black box, best in a separate macOS account: read every setting's default from its Settings UI, quit and remove it. Check each DockDoor value in the guide's Switching from DockDoor table | | Pending | The table was written from the plan only (D1). Its source is never opened |
| PC-3 | After S0-26's other-app leg, decide: either the 0.5 s bound for minimize and restore notifications counts from the end of the minimize animation (about 0.54 s after the call), or those two keep the 1 s tick | | Pending | The build has the 1 s tick while the panel is up (PLAN §R4, S0-26) |

## S0 rows carried to R (STEP0-NOTES)

Run them as STEP0-NOTES' **Owner session** lays out, Blocks 1–6 on this Mac (about 2 h 50 min) and Block 7
elsewhere. Each block ends with its own restore. The full steps are in its **Carried forward** table.

| # | What it needs | Gates | B | Status | Notes |
|---|---|---|---|---|---|
| S0-1 | (a) the 15 leg; (b) a folder and a web link in the Dock | R for (a) | B | Pending | |
| S0-2 | Hover with the Dock bottom, left and right, magnification, auto-hide, two copies of one app, a translocated app. 15 leg | R for 15 | B | Pending | The “· 2 instances” header waits on this |
| S0-3 | `killall Dock` ×10, sleep, lock, fast user switching, display changes | R | B | Pending | |
| S0-4 | Our window on another Space and full screen; a 5K display; no Screen Recording. 15 leg | R for 15 | B | Pending | |
| S0-5 | (a) a probe tile in Mission Control or App Exposé; (b) a symbolic hotkey round trip across a logout. 15 leg | R for 15 | B | Pending | Known limitations text if (a) shows a tile |
| S0-6 | A test panel over the Dock, a full-screen app's Dock and two Spaces; focus never moves | R | B | Pending | Known limitations text if focus moves |
| S0-7 | Auto-hide delays and `largesize` 128 | R | B | Pending | |
| S0-8 | 10 min idle (the display sleeps), then 50 raises | R | B | Pending | |
| S0-9 | A listen-only mouse tap; 200 Dock clicks; Secure Event Input; windowless apps' reopen | R | | Pending | `Permission.inputMonitoring` and a Known limitations text wait on this |
| S0-10 | Minimized, hidden, other-Space, full-screen and tabbed windows per app class; recapture after wake; Sidecar | R | B | Pending | |
| S0-11 | Stage Manager with two stages | R | | Pending | |
| S0-12 | The Dock on the 2x display; the built-in display above the main one | R | B | Pending | |
| S0-13 | Mission Control, App Exposé, Launchpad, Spotlight and Stage Manager while hovering | R | B | Pending | |
| S0-14 | 20 icons in 2 s; reads during Mission Control, a bounce and magnification | R | B | Pending | |
| S0-16 | VoiceOver through the Dock and into the panel | R | | Pending | |
| S0-17 | The 15 leg (14 or 26 optional) | R | B | Pending | |
| S0-18 | Owner pids without Screen Recording | R | B | Pending | |
| S0-19 | Indicators, reminders or alerts during 50 captures per path | R | B | Pending | Known limitations text, and the thumbnails default, if one shows |
| S0-20 | Taps: focus return, ⌥⇥ with both taps, a 30 s Accessibility revoke | R | B | Pending | |
| S0-21 | 20 diagonal moves to the far card, magnification off and on | R | | Pending | |
| S0-22 | The pointer on an app's icon while it quits | R | | Pending | |
| S0-23 | Reads without Screen Recording; an untitled other-Space window; a 50–100 window app | R | B | Pending | |
| S0-24 | Whether a `.none` panel appears in a screen share. 15 leg | R for 15 | | Pending | |
| S0-25 | Right-click, long-press, a frontmost click and a drag with the panel up | R | B | Pending | |
| S0-26 | Window notifications from Safari, Chrome, an Electron app, Finder and Terminal | R | B | Pending | Then PC-3 |
| S0-27 | 10 raises of other apps' windows, one on another Space | R | | Pending | |
| S0-28 | A 1 kHz mouse over the panel | R | | Pending | Needs the hardware |
| S0-29 | One `SLPSPostEventRecordTo` raise with Accessibility off | R | B | Pending | |
| S0-30 | A card click on 27.2 and on 26.3+ | R | B | Pending | 26.3+ needs another Mac |
| S0-31 | 8 h soak of the R build: sleep and wake, light and dark, a display change, a screen share, full screen in and out, an app hung across sleep | R | B | Pending | Unattended |

## M1–M50

| # | Check | B | V | 27.2 | 15 | Already covered | Notes |
|---|---|---|---|---|---|---|---|
| M1 | Switcher with Dock Previews off: ⌥⇥, ⌥\`, search and actions unchanged. Thumbnails as §4.23 describes. Nothing registered beyond today's set (M32). A launch with thumbnails off makes no private capture, the probe included; diagnostics show `hwCapture: notProbed` | B | V | Pending | Pending | CI `--selftest-launch`, `WindowSymbolContractTests` | |
| M2 | Switcher and Dock Previews on together; turn either off; the other keeps working | B | V | Pending | Pending | `WindowLeaseLedgerTests` | |
| M3 | Lock, display sleep, system sleep, fast user switching and revoking Screen Recording each purge thumbnails in both modules | B | V | Pending | Pending | `WindowLeaseLedgerTests` | |
| M4 | ⌘⇥ takeover still works; `Windows.disable.symbolicHotKeys` gives ⌘⇥ back to macOS | B | | Pending | N/A | | Plus one owner leg on macOS 14 or 26 |
| M5 | Switcher: minimized and other-Space windows have thumbnails, or the last-seen one with the badge | B | V | Pending | Pending | `ThumbnailIndexTests` | |
| M6 | `Windows.disable.hwCapture`: last-seen, then the icon | B | | Pending | N/A | | |
| M7 | Hover shows previews after the delay; moving along the Dock swaps at once | B | V | Pending | Pending | `DockPreviewPolicyTests` | |
| M8 | `killall Dock` while on: previews work again within 2 s | B | V | Pending | Pending | `DockReaderRulesTests` | Ask before `killall Dock`. ×10 gives 10 re-attaches in diagnostics |
| M9 | Sleep and wake ×5, lock and unlock, fast user switching: previews keep working | B | V | Pending | Pending | | |
| M10 | An app that stalls AX: other apps' previews are unaffected; that app shows titles | B | | Pending | N/A | | A 5 s stall keeps the main thread under 16 ms; record the S0-23 p95 |
| M11 | Bottom, left and right Dock, magnification on: positions correct; magnified, the panel doesn't move | B | V | Pending | Pending | `DockGeometryTests` | Record the Dock lines in diagnostics for each side |
| M12 | Auto-hidden Dock: the panel stays while the pointer is in it and hides with the Dock otherwise; the panel doesn't move while magnified | B | V | Pending | Pending | `DockGeometryTests` | |
| M13 | Dock on a second display; mixed Retina and non-Retina | B | | Pending | N/A | `DockGeometryTests` | Thumbnails use each display's scale (A5) |
| M14 | Full-screen app: the Dock's previews appear over it | B | | Pending | N/A | | |
| M15 | Never stuck: leave fast in every direction, scroll away, ⌘⇥ away, Mission Control | B | V | Pending | Pending | `DockPreviewPolicyTests` | |
| M16 | Click raises minimized, hidden, other-Space and full-screen windows; again with `Windows.disable.raise` on (other Space only activates the app) | B | V | Pending | Pending | | Plus one owner leg on macOS 14 or 26 |
| M17 | Middle-click closes; hover buttons; the card menu; Minimize All; Close All | B | V | Pending | Pending | `DockPanelHitTests` | |
| M18 | Text-only mode without Screen Recording; no prompt on hover | B | V | Pending | Pending | | |
| M19 | An app with 40 windows: cards shrink a size, then the panel scrolls; no card is out of reach. A 100-window app shows the windows read so far, then “More windows…” as the last cell, which scrolls into reach and VoiceOver reaches. Apps with no open windows show their card | | V | Pending | Pending | `DockPreviewRulesTests` | |
| M20 | Stage Manager on: previews are readable or text-only, never stuck | B | | Pending | N/A | `WindowCatalogRulesTests` | |
| M21 | 10 min idle with the module on: the display sleeps | B | V | Pending | Pending | | |
| M22 | VoiceOver on: paused by default. With the switch on, the announcement plays and cards are readable; with the pointer parked over a document, VoiceOver moves into the panel and the panel stays | B | | Pending | N/A | `DockPauseRulesTests` | |
| M23 | Engaged ⌘W, ⌘M, ⌘H, ⌘Q and Esc act on what's under the pointer. Over the header or a gap, ⌘W and ⌘Q do nothing and reach no app. No handled key reaches the frontmost app; bare letters, arrows and Return do. Hold ⌘Q over the last card for 2 s: only the previewed app quits | B | V | Pending | Pending | `DockKeyRulesTests` | |
| M24 | The keys tap is disabled while not engaged and gone with the module off (`CGGetEventTapList`) | B | | Pending | N/A | | Also: show and hide previews more than three times in 60 s and the keys still work (a disable Snaptic makes isn't counted by the breaker) |
| M25 | Dock click actions: Hide, Minimize and restore-all; a normal Dock click is never lost | B | V | Pending | Pending | `DockClickRulesTests` | |
| M26 | Revoke Accessibility with each tap enabled: no freeze over 30 s; the feature stops with its row | B | | Pending | N/A | `DockPageRulesTests` | Then grant it again without relaunching: click actions work at once, and keys at the next preview |
| M27 | Settings page, Advanced, both Restore Defaults, Permissions rows | B | V | Pending | Pending | `DockControlsTests`, `DockPageRulesTests` | |
| M28 | DockDoor running: paused with the row text; Run Both Anyway works | B | | Pending | N/A | `KnownDockToolsTests`, `DockPauseRulesTests` | |
| M29 | Fresh install onboarding with Dock Previews on; five module rows fit at the default text size | B | V | Pending | Pending | | |
| M30 | Upgrade from 0.4.0: the New card; Turn On. A protected app added in 0.5 survives a downgrade to 0.4.0, and Restore Defaults on either page; the downgrade keeps every other setting | B | V | Pending | Pending | `ConfigDockTests`, `ConfigMigrationsTests` | |
| M31 | `snaptic dock status`, `status --json`, `pause`, `resume`, and every exit-2 and exit-5 text. In Safe Mode, `status` answers `state=paused reason=safeMode` and `pause` exits 5 | B | V | Pending | Pending | `DockCommandGrammarTests`, `--selftest-controls` | |
| M32 | AX observers (`FocusTracker.liveObservers` plus the Dock observer). Dock Previews alone: 1 at rest, 2 while a preview is up, 1 again within 3 s of the hide. With the switcher on too: the switcher's count + 1, unchanged by a preview. Module off: the switcher's count | B | V | Pending | Pending | | |
| M33 | Safe Mode: the page row and the menu read “Paused in Safe Mode”; `dock status` gives `state=paused reason=safeMode`; the switcher shows minimized windows with the last-seen thumbnail or the icon; diagnostics show `hwCapture: safeMode`, 0 private captures (the probe included) and 0 Dock counters | B | V | Pending | Pending | `DockPauseRulesTests` | A click raises through activation and `kAXRaiseAction` only (R) |
| M34 | Backup export and import include Dock Previews settings and the protected apps; importing a backup with fewer protected apps keeps the current ones | B | V | Pending | Pending | `KitBackupTests` | |
| M35 | Crash-guard drill, once per symbol: `SNAPTIC_DEBUG_TRAP_IN=<symbol>` traps; the next launch disables only that symbol and shows its feature's row; Try Again clears it, and the next hover captures. The give-back drill, `SNAPTIC_DEBUG_TRAP_IN=symbolicHotKeys.giveBack`: the §4.17 row shows on the Window Switcher page with the switcher off, the list survives a relaunch, and Try Again gives ⌘⇥ back | B | | Pending | N/A | `CrashGuardTests` | Both the switcher and the Dock page halves |
| M36 | Right-click and long-press a Dock icon with the panel up: the Dock menu is never covered | B | V | Pending | Pending | | |
| M37 | Hide the App on: 50 clicks on background apps' icons hide nothing | B | V | Pending | Pending | `DockClickRulesTests` | |
| M38 | Share the screen (QuickTime and a browser meeting). Point at an app with a minimized window. Record whether its thumbnail appears in the share | B | | Pending | N/A | | If it does, Known limitations and the Window thumbnails help say so in those words |
| M39 | Revoke Screen Recording with both modules on: purge, then text-only, with no prompt | B | V | Pending | Pending | | |
| M40 | Park the pointer on the panel for 3 s, then type a sentence and press ⌘W: every key, ⌘W included, reaches the frontmost app. Move into the panel, wait 4 s, press ⌘W: it reaches the frontmost app | B | V | Pending | Pending | `DockKeyRulesTests` | |
| M41 | Quit from the header with unsaved work: the app asks to save; Finder has no Quit | B | | Pending | N/A | | |
| M42 | With VoiceOver off, ⌃F3 and Full Keyboard Access through the Dock: no previews | B | V | Pending | Pending | | |
| M43 | `snaptic dock pause 5m`: page row, menu and Resume agree; a relaunch resumes. Pause, then revoke Accessibility: row 4 and “Paused until…” [Resume] show, and `dock resume` answers “Dock Previews’ pause is cleared.” | B | V | Pending | Pending | `DockPauseRulesTests`, `DockCommandGrammarTests` | |
| M44 | Onboarding with Dock Previews as the only module: menu presence `.inSnapticMenu`; the Snaptic icon shows and the last step's text is true. With Accessibility revoked, the row-4 status item shows and there's no mark | B | V | Pending | Pending | `KitModulesTests` | |
| M45 | Switcher Window thumbnails off: the switcher never shows a thumbnail, even one the Dock captured | B | V | Pending | Pending | `ThumbnailIndexTests` | |
| M46 | Increase Contrast, Reduce Transparency and Reduce Motion each look as §4.7 says | B | V | Pending | Pending | | |
| M47 | Dock-not-readable row through the DEBUG test hook; Try Again; `dock status` gives `state=unavailable reason=dockUnreadable` | B | | Pending | N/A | `DockPageRulesTests` | DEBUG build with `SNAPTIC_DEBUG_DOCK_UNREADABLE=1` |
| M48 | Private windows and protected apps: no title, thumbnail or cache entry in either module | B | V | Pending | Pending | `WindowCatalogRulesTests` | |
| M49 | Idle 10 min with the module on: Snaptic's idle wake-ups (`top -stats pid,idlew`) are within 1 per second of the module being off | B | | Pending | N/A | | |
| M50 | Module on and off 20×: every live counter returns to 0; EventLog `dock.started` and `dock.stopped` counts match the cycles | B | V | Pending | Pending | `DockLiveTests` | |

## What a result changes

- **S0-2:** the panel header gains “· 2 instances” for an app with two copies running, if the Dock reports them
  as one item.
- **S0-9:** `Permission.inputMonitoring` joins the Permissions rows if the mouse tap needs it.
- **S0-15:** `KnownDockTools` gains each tool's team id.
- **S0-32:** the guide's Switching from DockDoor table is corrected wherever DockDoor's real default differs.
- **M38, S0-5, S0-6, S0-9, S0-19:** each adds its Known limitations sentence if the result calls for it (PLAN §R4,
  D1).
- **PC-3:** the owner's answer, recorded in PLAN §R4.
- **Any Fail:** a PLAN §R4 row, and the fix before release when the row is a Blocker.
