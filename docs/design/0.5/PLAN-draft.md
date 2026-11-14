# Snaptic 0.5 plan: Dock Previews (r1, draft)

> **Status: draft, for owner questions.** After the owner answers the questions, the draft gets three or more
> review rounds (adversarial, grill, pressure, and parity: `review-r1-*.md`). Then `PLAN.md` (final) records every
> finding's disposition. Implementation starts only on "approved".

## What 0.5 adds

0.5 adds a fifth module, **Dock Previews**. It does what [DockDoor](https://github.com/ejbills/DockDoor) does at
its core (GPL-3.0; this plan surveyed v1.42.4, 2026-11-08), plus fixes for that app's top complaints. Snaptic is
MIT, so this is a **clean-room build**: we reuse ideas and public facts, never code (see Ground rules).

- Hover an app in the Dock and a panel shows that app's windows: a thumbnail and title for each, with minimized,
  hidden and other-Space windows marked. Click one to bring it forward. Close, minimize or zoom it from the card.
- It works with the Dock at the bottom, left or right, magnified or not, auto-hidden or not, on any display.
- Without Screen Recording, the panel shows titles only (no thumbnails), and never asks for it on hover.
- Optional Dock click actions: click the frontmost app's icon to hide or minimize it, click an app whose windows
  are all minimized to bring them back.

The **Window Switcher** gets what DockDoor shows it's missing, because both modules share one window service:

- Thumbnails for **minimized and other-Space windows** (today they show the app icon).
- A thumbnail cache that survives between switcher openings, so thumbnails appear at once and refresh in place.
- Encoding checks, poisoning and kill switches for the switcher's private symbols, like the 0.4 private APIs.

It is **off by default**, ships in **0.5.0 (CFBundleVersion 500)**, and gets a "New: Dock Previews" card plus an
opt-in onboarding row.

## Owner decisions (2026-11-12; not reopened)

| Q | Decision |
|---|---|
| Q1 | **A fifth module, "Dock Previews"**, sharing one window service (`WindowServices`) with the Window Switcher. Own switch, Settings page, kill switch and CLI (`snaptic dock …`), `ModuleID.dockPreviews`. |
| Q2 | **Core plus extras:** hover previews, cards with badges, click / middle-click / hover buttons, text-only mode, keys in previews, right-click menu, Hide and Quit in the header, opt-in Dock click actions, the other-tool pause, VoiceOver handling, and the switcher upgrades. Not the ⌘⇥ overlay, widgets, live or pinned previews, or snapping (§9). |
| Q3 | **Private capture** (`CGSHWCaptureWindowList`) under the 0.4 private-API rules, falling back to the last-seen thumbnail, then the app icon. Shared with the switcher. |
| Q4 | **Dock click actions are opt-in and off by default:** click the frontmost app's icon to Hide or Minimize; click an app whose windows are all minimized to restore them all. A listen-only tap, so a Dock click is never swallowed. |
| Q5 | **Pause while DockDoor or a similar tool runs**, with "Paused while … runs" and **Run Both**. |
| Q6 | **Every switcher private symbol** gets the 0.4 treatment now: encoding check, poisoning, a kill switch, a selftest line. |
| Q7 | **0.5.0 (CFBundleVersion 500), off by default**, with a "New: Dock Previews" card and an onboarding opt-in. |

## Ground rules (carried over from 0.4)

- **While off, the module costs nothing.** No AX observers, event taps, timers, panels, captures or prompts.
  `DockPreviewsModule.init` creates nothing; everything is made in `start()` and torn down in `stop()`.
- **Pure logic lives in SnapticKit** (Foundation only, Linux-tested). The app holds only AppKit, AX, SCK and
  private-API adapters.
- **Every private symbol** is resolved at runtime and checked for the expected type encoding before use. Any
  exception poisons it for the life of the process. Each has a kill switch. A failure fails safe: **no preview, or a
  text-only preview; the Dock itself is never affected.**
- **No synthetic events.** Snaptic never posts mouse or key events, not even a "canary" (DockDoor #1634: a periodic
  synthetic event kept displays awake). Window actions use AX actions and attributes only.
- **Never touch the Dock's preferences.** We read Dock geometry from AX frames, not CoreDock or `com.apple.dock`
  writes.
- **No bundle ids, app names or window titles** in logs, EventLog, error text or diagnostics. Counts only.
- **Thumbnails stay in memory.** Never written to disk, purged on lock, sleep, fast user switching and `stop()`.
- **Every new file** adds its `scripts/stubs.tsv` row in the same commit. Each work item ends with
  `scripts/lint.sh --strict` clean, `swift build` and `swift test` green.
- **Clean room.** DockDoor is GPL-3.0 and parts of it derive from AltTab (GPL). Implementers work from this plan,
  Apple's documentation and our own S0 results. They don't open DockDoor or AltTab source while writing Snaptic code.
  §1 records behaviour and API names only (facts, not expression). `THIRD_PARTY_NOTICES.md` credits DockDoor's
  design; no file or snippet is copied.

---

## 1. What the source teaches (survey)

| DockDoor part | How it behaves | Snaptic decision |
|---|---|---|
| Dock hover detection | An AX observer on the Dock process's `AXList` watches `kAXSelectedChildrenChangedNotification` and reads `kAXSelectedChildren`. The Dock "selects" the item under the pointer. A 5 s health check re-attaches when the Dock's pid changes | Same signal, our own code (`DockObserver`). Re-attach on `NSWorkspace` Dock launch/terminate, wake, unlock and session-active, plus a 30 s health check that costs one AX read. No mouse polling |
| Dock item → app | Subrole `AXApplicationDockItem`, then `kAXURLAttribute` → bundle → running app | Same, with `pid` from `NSRunningApplication` matched by bundle URL (two copies of one app: S0-2). Folders, Trash, stacks, minimized-window tiles and separators dismiss |
| Window list | ScreenCaptureKit, then AX `kAXWindowsAttribute`, then a brute-force private AX lookup for other-Space windows | Reuse the switcher's `WindowGatherer` (already lists other Spaces via `SLSCopySpacesForWindows`). No new brute-force lookup |
| Thumbnails | Private `CGSHWCaptureWindowList` captures minimized and other-Space windows; 30 s cache; at most 4 captures at once | Q3: private capture under the 0.4 rules, with a last-seen cache as fallback. Shared with the switcher |
| Freshness | Shows cached data first, refreshes, debounced 0.3 s, driven by per-app AX observers and `NSWorkspace` | Same idea through the switcher's `FocusTracker` (one AX observer per app already exists) |
| Panel | Non-activating, all Spaces, status-bar level. Dock orientation, magnification and autohide come from private CoreDock calls | Non-activating panel (reuse `SnapticPanel`). Orientation and position from the hovered item's **AX frame** against its screen. No CoreDock |
| Dismissal | Tracking area plus a 0.2 s timer. Top complaint: previews that won't go away (#472) | Kit state machine with a pointer corridor and a hard safety net (§4.4) |
| Raise | `_SLPSSetFrontProcessWithOptions` + `SLPSPostEventRecordTo` + `kAXRaiseAction` | Reuse the switcher's `WindowManager.focus` (same symbols, already shipped) |
| Card actions | Click raises; middle-click closes; traffic-light buttons; ⌘W / ⌘M / ⌘Q while hovering; context menu with snapping and "bring to this Space" | Click, middle-click, hover buttons, right-click menu, and keys while the pointer is in the panel (§4.3). No snapping, no Space moves (§9) |
| Dock clicks | ⌘-right-click quits, Shift-click opens a new window, click restores minimized windows; scroll gestures off | Opt-in, listen-only tap, two actions (§4.9) |
| Cmd+Tab overlay | Window cards above the system ⌘⇥ switcher (off by default) | Not included: the switcher's ⌘⇥ takeover already replaces it (§9) |
| Widgets | Media (private MediaRemote, AppleScript fallback, lyrics from web APIs) and Calendar (EventKit) | Not included: private and restricted framework, two new permissions, network calls (§9) |
| Text-only mode | Works without Screen Recording | Same; never prompts on hover |
| Top issues | Previews die until relaunch (sleep/wake, taps); won't dismiss; auto-hide Dock timing; multi-monitor; Stage Manager; leaked taps and CPU; display won't sleep; Spaces | Each has an S0 row (§5) and a manual check (§7) |

**What DockDoor's own issues teach:** event-driven AX beats polling; re-attach after every lifecycle event; show the
cache first; back off from apps whose AX calls stall; never touch Dock preferences; never post synthetic events;
tear taps down completely.

---

## 2. Architecture and file homes

```
SnapticKit (Foundation only, Linux-tested)
  DockModel.swift             DockItemKind (app, folder, trash, minimizedWindow, separator, other), DockEdge
                              (bottom, left, right), DockHover (item, frame, screen), DockFeature
  DockGeometry.swift          edge from item frame vs screen; panel placement (centered on the item, clamped to the
                              visible frame, 8 pt margin, 6 pt gap); card grid (rows for bottom, columns for sides,
                              "+N more" past the screen); RTL
  DockPreviewPolicy.swift     hover state machine: delay, swap, corridor, grace, dismiss reasons, safety net;
                              card click resolver (left, middle, right, modifiers); Dock click action resolver;
                              pause rules (other Dock tools, VoiceOver, Safe Mode, kill switches)
  DockCommandGrammar.swift    `dock status|pause|resume [--json]`, help, errors
  KnownDockTools.swift        bundle ids of DockDoor, HyperDock and others (verified in S0)
  WindowCatalogRules.swift    shared: which windows count, recency merge, badge state, cache freshness, LRU budget
  Config/ConfigDock.swift     DockConfig, sanitize, defaults, backup allowlist
  Controls/DockPageControls.swift, DockAdvancedSheetControls.swift, DockMenuRowsControls.swift
Snaptic (app)
  Windows/WindowServices.swift      acquire/release by ModuleID; owns WindowManager, ThumbnailStore, FocusTracker;
                                    purge observers (lock, sleep, FUS) live here, not in either module
  Windows/PrivateWindowAPI.swift    moved from Switcher/PrivateAPIs.swift; KitEncoding checks, poisoning, kill
                                    switches; adds CGSHWCaptureWindowList
  Windows/WindowCapture.swift       SCK path, private path, last-seen cache, concurrency cap (4)
  Dock/DockPreviewsModule.swift     SnapticModule: start/stop, state, menuSection(tabbed:), requiredPermissions
  Dock/DockObserver.swift           AX observer on the Dock's AXList; re-attach; health check
  Dock/DockReader.swift             AX item → DockHover (budgeted, 0.15 s per call)
  Dock/DockPreviewController.swift  drives DockPreviewPolicy; shows, swaps and hides the panel
  Dock/DockPreviewPanel.swift       the panel (built on SnapticPanel): level, collection behaviour
  Dock/DockPreviewView.swift        SwiftUI cards, header, hover buttons, context menu, VoiceOver labels
  Dock/DockKeys.swift               keys while the pointer is in the panel (through HotkeyTap; §4.3)
  Dock/DockClickTap.swift           listen-only mouse tap for Dock click actions (opt-in; §4.9)
  Dock/DockCLI.swift                ControlCommandRegistry verbs
  Dock/UI/DockPage.swift, DockAdvancedSheet.swift, DockMenuRows.swift
```

The Kit policy never sees an `NSPanel` or an `AXUIElement`. It takes events (`hoverChanged`, `pointerMoved`,
`panelEntered`, `tick`, `appActivated`, `spaceChanged`, …) and returns commands (`show`, `swap`, `hide(reason)`,
`refresh(pid)`), so the tests assert on recorded commands.

**Why a shared window service.** Today `WindowManager.shared`, `ThumbnailStore.shared` and `FocusTracker` belong to
the switcher's lifecycle and are torn down when it stops. With two users, `WindowServices` counts who holds them:
the first `acquire` starts them, the last `release` stops and purges them. The switcher's behaviour doesn't change
when Dock Previews is off.

---

## 3. Host changes

- **H1. `ModuleID.dockPreviews`** (raw `dockPreviews`), last in start order. Before the change, run
  `grep -rnE '\.(windowSwitcher|displays|awake|hiddenIcons)\b|ModuleID\.allCases' Sources Tests` and record each hit
  with a disposition in `docs/design/0.5/H1-SITES.md`. Known lists: `SettingsRootID.groups` (+ alias `dock`), the
  `module disable` help and alias, `MenuPresence.allowed` (`[.inSnapticMenu, .hidden]`, default `.hidden`),
  `NewModuleCard.dockPreviews` (+ ledger marker `dockCard.v1`), `EventCategory.dock`, `KitBackup.sections`,
  `defaultPreferences`, `SettingsPageRules`, `MenuLayout` short title "Dock", onboarding rows.
- **H2. Window services** (§2). The switcher acquires on `start()` and releases on `stop()`. Purge observers move
  into `WindowServices`.
- **H3. Private window API** moves to `Windows/PrivateWindowAPI.swift`. Lint rule 11's dlsym allowlist swaps
  `Switcher/PrivateAPIs.swift` for the new path. Each symbol gets a `KitEncoding.Requirement` and a kill switch
  `Windows.disable.<name>` (§4.12). `--selftest-launch` prints one availability line per symbol.
- **H4. Settings:** a ninth sidebar page, **Dock Previews**, between Hidden Icons and Permissions.
- **H5. Permissions page:** Dock Previews needs Accessibility; Screen Recording only while thumbnails are on.
- **H6. Kill switches:** `Modules.disable.dockPreviews`, `Dock.disable.clickActions`, `Dock.disable.keys`, plus the
  `Windows.disable.*` set. All read at start and observed while running.
- **H7. Pinned tests:** `KitModulesTests`, `ConfigModulesTests`, `ConfigFixtures.fullModules()`,
  `SettingsShellRulesTests` (8 roots → 9), and a downgrade test (a 0.5 config decodes with the 0.4.0 types).
- **H8. Lint scopes:** L13, L14, L17, L20 and `SETTINGS_VIEWS` (`lint03.py:499`) add the Dock files. L2 (synthetic
  events) is unchanged and must stay green.
- **H9. Docs that count modules or pages:** README "⌘1–⌘4", guide "eight pages", the site's "Eight pages",
  `MANUAL-CHECKS` "4 modules" (`--selftest-launch` now prints 5 modules / 0 running).

---

## 4. Behaviour

### 4.1 Hover

1. The Dock's selection changes to an app item whose app is running → after the **delay** (default 0.2 s; 0–1 s
   slider) the panel shows that app's windows.
2. While the panel is up, the selection moves to another running app → the panel **swaps** at once (no delay).
3. Selection moves to a folder, Trash, stack, separator, a minimized-window tile or an app that isn't running →
   the panel hides after the grace time.
4. The Dock's AX selection lags the pointer by a frame or two; the policy never shows from a selection older than
   the last `pointerMoved` that left the Dock's frame.

### 4.2 Cards

- One card per window: thumbnail (or app icon in text-only mode), title (the app name when the title is empty),
  and badges: **Minimized**, **Hidden**, **Other Space**, **Full Screen**.
- Order: most recently used first (the switcher's `FocusTracker` recency). Setting: **Recent** or **Title**.
- Card size: **Small / Medium / Large** (200 / 280 / 360 pt wide; height follows the thumbnail's aspect, capped).
- A header with the app's icon and name, window count, and **Hide** and **Quit** buttons.
- Bottom Dock: one row, wrapping into more rows when it doesn't fit; side Docks: columns. Past the screen, a
  "+N more" card opens the Window Switcher filtered to that app.
- Apps with no windows: a single compact card, "No open windows". Setting to show nothing instead.
- Reduce Motion: no fade. Increase Contrast: borders on cards.

### 4.3 Actions

| Input | Action |
|---|---|
| Click a card | Bring that window forward (restores a minimized window, unhides a hidden app, switches Space) |
| Middle-click | Close the window |
| Hover buttons | Close, minimize, full screen (same style as the switcher's `hoverButtons`) |
| Right-click | Menu: Close, Minimize / Restore, Full Screen, Hide App, Quit App |
| Keys while the pointer is in the panel | Esc hides; ←/→ (↑/↓ on side Docks) move the selection; Return raises; W closes; M minimizes; Q quits the app |

Keys use the existing `HotkeyTap` machinery, installed only while the panel is visible **and** the pointer is in
it, removed the moment either stops. Feature switch "Keyboard in previews" (default on).

### 4.4 Dismissal (the #472 fix)

The panel hides when any of these holds:

- The Dock's selection is gone or not an app, **and** the pointer has been outside the panel and the **corridor**
  (the rectangle between the hovered icon and the panel) for the grace time (0.25 s).
- A hard safety net: the pointer has been outside the Dock's frame and the panel for 1 s, whatever AX says.
- A click outside the panel (a global mouse-down monitor that exists only while the panel is visible).
- We raised, closed or minimized a window from the panel (after the action completes).
- App activation by anything else, Space change, display change, lock, sleep, fast user switching, Mission Control
  (detected by its window appearing; S0-13), module stop, kill switch.

### 4.5 Placement

- The edge comes from the hovered item's AX frame against the screen that contains it: near the bottom → bottom,
  else near the left or right.
- The panel sits 6 pt off the Dock, centered on the item, clamped to the screen's visible frame with an 8 pt
  margin. Magnification is handled because the frame is read live.
- The panel's level is above the Dock and works over full-screen apps (S0-6 records the level).
- Auto-hidden Dock: the panel stays while the pointer is in it, even if the Dock hides behind it; otherwise it
  hides with the Dock. We don't keep the Dock revealed (that needs Dock preferences or synthetic events).

### 4.6 Data

- Show the cached window list and thumbnails at once; refresh in the background; update cards in place.
- AX calls are budgeted (0.15 s). An app that times out is skipped for 30 s and shown from `CGWindowList` data
  (titles only).
- Thumbnail cache: LRU, at most 120 entries or 96 MB, entries older than 30 s refresh when shown. Shared with the
  switcher, which now opens with cached thumbnails.

### 4.7 Permissions

- **Accessibility** is required. Without it the module shows "Needs Accessibility" and starts nothing.
- **Screen Recording** is optional. Without it: text-only cards, and one line on the Dock Previews page,
  "Allow Screen Recording to see thumbnails", with a button. Never a prompt on hover.

### 4.8 Other Dock tools

If DockDoor or another known Dock preview tool (`KnownDockTools`, verified in S0) is running, Dock Previews pauses
with "Paused while DockDoor runs", with **Run Both** in Advanced. Same pattern as Hidden Icons and Displays.

### 4.9 Dock click actions (opt-in, off by default)

- **Click the frontmost app's icon:** Hide the app (default) or Minimize its windows.
- **Click an app whose windows are all minimized:** restore them all (the Dock restores only one).
- A **listen-only** mouse tap (`.listenOnly`), so the Dock always gets the click first and a failed tap never
  swallows a click. It exists only while the feature is on, re-checks `AXIsProcessTrusted()` after any
  `tapDisabledBy*` event, has a circuit breaker (3 disables in 60 s → off until relaunch, with a row text) and is
  invalidated in `stop()`.

### 4.10 VoiceOver

Moving the VoiceOver cursor through the Dock changes its selection too, so previews would pop up as a VoiceOver
user reads the Dock. The draft **pauses while VoiceOver runs** ("Show with VoiceOver" in Advanced, off by default).
Cards have labels such as "Title, App, Minimized", and the panel is reachable with VoiceOver when it's shown.

### 4.11 Window Switcher changes

- Uses `WindowServices` (H2). No visible change when thumbnails are off.
- Minimized and other-Space windows get thumbnails when Q3's private capture is available; otherwise the
  last-seen thumbnail with the badge; otherwise the app icon, as today.
- Opens with cached thumbnails; refreshes in place.

### 4.12 Private APIs

| Symbol | Used for | New? | Kill switch |
|---|---|---|---|
| `CGSHWCaptureWindowList` | Thumbnails of minimized and other-Space windows | yes | `Windows.disable.hwCapture` |
| `_AXUIElementGetWindow` | AX window ↔ window id | moved | `Windows.disable.axWindowID` |
| `GetProcessForPID`, `_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo` | Raising a window | moved | `Windows.disable.raise` (falls back to `kAXRaiseAction` + `activate`) |
| `SLSMainConnectionID`, `SLSCopySpacesForWindows` | Other-Space badges | moved | `Windows.disable.spaces` |
| `SLS/CGSSetSymbolicHotKeyEnabled`, `SLSIsSymbolicHotKeyEnabled` | Switcher ⌘⇥ takeover | moved | `Windows.disable.symbolicHotKeys` |

Each gets an encoding requirement verified in S0 on 27.2 and the 15 VM. A poisoned symbol logs once and its
feature falls back as listed.

### 4.13 Settings page (draft strings)

- **Use Dock Previews** (module switch).
- Show previews after: slider 0–1 s (0.2 s).
- Card size: Small / Medium / Large. Order: Recent / Title.
- Show: Minimized windows ✓, Hidden apps ✓, Windows on other Spaces ✓, Apps with no windows ✓.
- Thumbnails ✓ (needs Screen Recording; off → titles only).
- Keyboard in previews ✓.
- Dock click actions: **Off** / Hide / Minimize; "Restore all minimized windows" ✓.
- **Advanced…:** grace time, Run Both, Show with VoiceOver, Restore Defaults.

### 4.14 CLI

`snaptic dock status [--json]` (on, paused reason, observer attached, cache counts), `snaptic dock pause
[--minutes N]`, `snaptic dock resume`. Exit 2 with text when the module is off.

### 4.15 Diagnostics

Counts and booleans only: observer attached, re-attach count, last hover-to-show latency, cache entries and bytes,
captures and failures by path, paused reason, poisoned symbols.

---

## 5. S0: the gate before any app code (macOS 27.2 host + a macOS 15 VM)

A throwaway harness under `/tmp/s0-dock/` (never committed), plus `docs/design/0.5/STEP0-NOTES.md` (committed).
Any failed Blocker row changes the plan before A3 starts.

| # | Check | Pass | Blocker |
|---|---|---|---|
| S0-1 | Dock AX tree: `AXList`, item subroles, `kAXURLAttribute`, frames, on 27.2 and 15 | Recorded; app items resolvable | yes |
| S0-2 | `kAXSelectedChildrenChangedNotification` on hover: bottom/left/right, magnification, autohide, two copies of one app | Fires within 50 ms; resolvable to a pid | yes |
| S0-3 | `killall Dock`; sleep/wake; lock/unlock; fast user switching | Observer re-attaches; events resume | yes |
| S0-4 | `CGSHWCaptureWindowList` presence, encoding, results for minimized, other-Space, hidden and full-screen windows; without Screen Recording; time per call | Recorded; decides Q3's path | yes |
| S0-5 | The switcher's private symbols' encodings on 27.2 and 15 | Recorded for §4.12 | yes |
| S0-6 | Panel level over the Dock, over a full-screen app's Dock, on all Spaces, without stealing focus | A level that works everywhere | yes |
| S0-7 | Auto-hide Dock: pointer from the Dock into the panel | Record whether the Dock hides and whether selection clears | yes |
| S0-8 | 10 min idle with the harness attached | Display sleeps; `pmset -g assertions` shows nothing from it | yes |
| S0-9 | Listen-only mouse tap over the Dock; order of Dock activation vs our hide; Secure Event Input | Hide works without a visible flicker of more than one frame | no (else §4.9 drops "Hide") |
| S0-10 | What AX, `CGWindowList` and SCK return for minimized, hidden, other-Space and full-screen windows | Recorded for `WindowCatalogRules` | yes |
| S0-11 | Stage Manager on | Record hover, frames and capture | no |
| S0-12 | Dock on a secondary display; mixed scale factors; display arranged above | Frames convert to the right screen | yes |
| S0-13 | Mission Control, App Exposé, Launchpad, Spotlight while hovering | Record the signals; the panel hides | no |
| S0-14 | Hover 20 apps in 2 s; an app that stalls AX for 5 s | Main thread never blocks over 50 ms | yes |
| S0-15 | Bundle ids of DockDoor, HyperDock and other Dock preview tools | Recorded in `KnownDockTools` | no |
| S0-16 | VoiceOver cursor through the Dock | Record selection events | no |

---

## 6. Work items (in order)

**Every item:** its new files' `stubs.tsv` rows; `scripts/lint.sh --strict` clean; `swift build` and `swift test`
green; one commit or more, each ending with the Co-Authored-By line. Kit items add Linux-safe tests only. App items
run `--selftest-launch` and `--selftest-controls` locally.

| ID | Work | Done when |
|---|---|---|
| **S0** | §5 harness and STEP0-NOTES | Every Blocker row has a result; any plan change is in §R2 |
| **K1** | `ModuleID.dockPreviews` + `H1-SITES.md`; MenuPresence; New card; `DockConfig` (sanitize, defaults, backup); `DockFeature`; `KnownDockTools`; EventCategory; pinned tests (H7); lint scopes (H8); downgrade test | Every H1 site has a disposition; tests pass; a 0.5 config decodes with 0.4.0 types |
| **K2** | `DockGeometry`: edges, placement, clamping, card grid, "+N more", RTL, multi-screen | `DockGeometryTests` pass |
| **K3** | `DockPreviewPolicy`: hover machine, swap, corridor, grace, safety net, every dismiss reason, click resolvers, Dock click resolver, pause rules | `DockPreviewPolicyTests` pass, including a race table |
| **K4** | `WindowCatalogRules`: inclusion, recency merge, badges, freshness, LRU budget | `WindowCatalogRulesTests` pass; the switcher's current inclusion cases still hold |
| **K5** | Controls tables + `DockCommandGrammar` + `MenuLayout` | `ControlsTests`, `MenuLayoutTests` pass; L15 passes |
| **B1** | `PrivateWindowAPI` (move + encoding checks + kill switches + `CGSHWCaptureWindowList`) + selftest lines | CI prints `unavailable` where expected; local 27.2 prints `available`; forced-exception poison path covered |
| **A1** | `WindowServices`; switcher moves onto it with no behaviour change | Switcher manual checks M1–M4 pass; on/off 20× leaks nothing |
| **A2** | `WindowCapture` (SCK + private + last-seen + cap of 4); switcher shows minimized/other-Space thumbnails | M5–M6 |
| **A3** | `DockObserver` + `DockReader` (re-attach, health, budgets) | M7–M10 |
| **A4** | `DockPreviewController`, panel and view (cards, header, actions, dismissal, placement, a11y) | M11–M22 |
| **A5** | `DockKeys` and `DockClickTap` | M23–M26 |
| **A6** | Module + host wiring (stores, shutdown, Safe Mode, kill-switch observers, diagnostics, EventLog, other-tool and VoiceOver pauses) | On/off 20× with no leaked observer, tap, panel or timer |
| **A7** | Settings page, Advanced, Permissions row, Menu Bar page, Snaptic-menu section, sidebar | Every §4.13 string matches the code (grep test); M27–M28 |
| **A8** | Onboarding row + New card + `dockCard.v1` | M29–M30 |
| **A9** | `DockCLI` + `dockCases` in `--selftest-controls` | M31 |
| **D1** | README and guide: Dock Previews section, Switcher changes, Known limitations, kill switches, Upgrading, CLI table, "nine pages", private API list | `scripts/lint.sh --strict` README rules pass |
| **D2** | `THIRD_PARTY_NOTICES.md` (DockDoor design credit, GPL-3.0, no code), release notes, `CFBundleShortVersionString` 0.5.0, `CFBundleVersion` 500 | Version checked by `scripts/build-app.sh` |
| **D3** | Site: module list and "nine pages" | Updated |
| **R** | Code review of the branch; manual checks on 27.2 and the 15 VM; PR with CI green | Every Blocker check passes; PR open with CI green, linked |

---

## 7. Manual checks (recorded in `docs/design/0.5/MANUAL-CHECKS.md`)

**B** = Blocker for release. **V** = also run on the macOS 15 VM.

| # | Check | B | V |
|---|---|---|---|
| M1 | Switcher with Dock Previews off: ⌥⇥, ⌥\`, thumbnails, search, actions unchanged | B | V |
| M2 | Switcher and Dock Previews on together; turn either off; the other keeps working | B | V |
| M3 | Lock, sleep, FUS purge thumbnails in both modules | B | V |
| M4 | ⌘⇥ takeover still works; kill switch `Windows.disable.symbolicHotKeys` restores macOS ⌘⇥ | B | |
| M5 | Switcher: minimized and other-Space windows have thumbnails (or the last-seen one, badged) | B | V |
| M6 | `Windows.disable.hwCapture`: falls back to last-seen, then icon | B | |
| M7 | Hover shows previews after the delay; swap between apps is instant | B | V |
| M8 | `killall Dock` while on: previews work again within 2 s | B | V |
| M9 | Sleep/wake ×5, lock/unlock, FUS: previews keep working | B | V |
| M10 | An app that stalls AX: other apps' previews unaffected; that app shows titles | B | |
| M11 | Bottom, left, right Dock; magnification on; positions correct | B | V |
| M12 | Auto-hidden Dock: preview stays while the pointer is in it; hides with the Dock otherwise | B | V |
| M13 | Dock on a second display; mixed Retina and non-Retina | B | |
| M14 | Full-screen app: the Dock's previews appear over it | B | |
| M15 | Never stuck: leave fast in every direction, scroll away, ⌘⇥ away, Mission Control | B | V |
| M16 | Click raises (minimized, hidden, other Space, full screen) | B | V |
| M17 | Middle-click closes; hover buttons; right-click menu items | B | V |
| M18 | Text-only mode without Screen Recording; no prompt on hover | B | V |
| M19 | Apps with no windows; "+N more" opens the switcher filtered | | V |
| M20 | Stage Manager on: previews usable or recorded as a limitation | | |
| M21 | 10 min idle with the module on: the display sleeps | B | V |
| M22 | VoiceOver on: paused by default; cards readable when "Show with VoiceOver" is on | B | |
| M23 | Keys in previews: Esc, arrows, Return, W, M, Q; no key reaches the frontmost app while handled | B | V |
| M24 | Keys tap gone when the pointer leaves the panel (`CGGetEventTapList`) | B | |
| M25 | Dock click actions: Hide, Minimize, restore-all; a normal Dock click is never lost | B | V |
| M26 | Revoke Accessibility while the click tap is on: no freeze; feature stops with a row text | B | |
| M27 | Settings page, Advanced, Restore Defaults, Permissions row | B | V |
| M28 | DockDoor running: paused with the row text; Run Both works | B | |
| M29 | Fresh install onboarding with Dock Previews on | B | V |
| M30 | Upgrade from 0.4.0: New card; Turn On flow; downgrade to 0.4.0 keeps settings | B | V |
| M31 | `snaptic dock status/pause/resume --json` and every exit-2 text | B | V |
| M32 | Module off: no observer, tap, timer or panel (Activity Monitor + EventLog) | B | V |
| M33 | Safe Mode: Dock Previews doesn't start | B | V |
| M34 | Backup export/import includes Dock Previews settings | B | V |

---

## 8. Risks

| Risk | Likelihood | Effect | Mitigation |
|---|---|---|---|
| Apple changes the Dock's AX tree or stops the selection notification | Medium | No previews | S0 on 27.2 and 15; the module reports "Dock not readable" and does nothing; no polling fallback |
| `CGSHWCaptureWindowList` changes or disappears | Medium | No minimized thumbnails | Encoding check, poison, kill switch, last-seen fallback |
| Stuck previews (DockDoor #472) | Medium | Annoying | Kit state machine with a safety net; M15 |
| Observer dies after lifecycle events (DockDoor's top complaint) | Medium | Previews stop until relaunch | Re-attach on every lifecycle signal + 30 s health check; M8–M9 |
| Window-service refactor regresses the switcher | Medium | Switcher bugs | A1 is behaviour-neutral and lands alone; M1–M4 |
| Memory from thumbnails | Low | High memory | LRU budget; purge on lock/sleep/stop |
| Mouse tap over the Dock freezes input on permission revoke (27.2) | Low | Severe | Listen-only, circuit breaker, re-check trust, off by default; M26 |
| GPL contamination | Low | Licence problem | Clean-room rule; plan is the only input; credit in notices |
| Two Dock preview tools fight | Medium | Double panels | Pause by default; Run Both opt-in |

## 9. Not included (recorded)

- **Media and Calendar widgets.** Media needs private MediaRemote (restricted to entitled processes since macOS
  15.4) or per-app Automation permission; lyrics need network calls (Snaptic's only traffic is the update check);
  Calendar needs a new permission.
- **The Cmd+Tab overlay.** The switcher's ⌘⇥ takeover already replaces macOS ⌘⇥.
- **Window snapping** (halves, quarters, center) from the context menu. Window management would be its own module.
- **Moving a window to the current Space.** Needs SkyLight Space-move calls that recent macOS restricts.
- **Live previews and pinned (floating) previews.** SCStream per window; costly; candidate for a later release.
- **Shift-click New Window, ⌘-right-click Quit, scroll gestures on Dock icons, trackpad gestures, title-bar
  gestures, "aero shake", Dock locking, the active-app indicator.**
- **AppleScript dictionary.** The `snaptic` CLI covers scripting.
- **Importing DockDoor settings.**
- **Liquid Glass styling.** Snaptic links the 15 SDK; cards use the existing design system.
