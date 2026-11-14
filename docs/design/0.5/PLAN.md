# Snaptic 0.5 plan: Dock Previews

> **Status: Approved 2026-11-13 — reviewed in 3 rounds (r1: 103 findings, r2: 97, r3: 33); in implementation (§R4).**
>
> History:
> - `PLAN-draft.md` is r1, kept unchanged.
> - Round 1 has four reviews: `review-r1-adversarial.md` (X-n), `review-r1-grill.md` (G-n),
>   `review-r1-parity.md` (Y-n) and `review-r1-pressure.md` (P-n). §R1 records their dispositions.
> - Round 2 has four reviews: `review-r2-adversarial.md` (X2-n), `review-r2-grill.md` (G2-n),
>   `review-r2-pressure.md` (P2-n) and `review-r2-dispositions.md` (D2-n), which audits §R1. §R2 records their
>   dispositions, and the §R1 rows the audit found inaccurate are corrected in place.
> - Round 3 has three reviews: `review-r3-adversarial.md` (X3-n), `review-r3-grill.md` (G3-n) and
>   `review-r3-pressure.md` (P3-n). §R3 records their dispositions.
>
> A failed S0 row changes this plan before the items it gates start (§5, "If it fails"); that change is recorded in
> `STEP0-NOTES.md` and in §R4.
> Implementation starts only on the owner's "approved".

## What 0.5 adds

0.5 adds a fifth module, **Dock Previews**. It covers the core of [DockDoor](https://github.com/ejbills/DockDoor),
which is GPL-3.0 (this plan surveyed v1.42.4 on 2026-11-08). It also fixes that app's top complaints. Snaptic is
MIT, so this is a **clean-room build**: we reuse ideas and public facts, never code (see the Ground rules).

- **Previews.** Point at an app in the Dock and a panel shows that app's windows. Each card has a thumbnail and a
  title, and minimized, hidden and other-Space windows are marked.
- **Actions.** Click a card to bring its window forward. You can also close it, minimize it, or make it full
  screen from the card.
- **Where it works.** The Dock can be at the bottom, left or right, magnified or not, auto-hidden or not, on any
  display.
- **Without Screen Recording**, the panel shows titles instead of pictures. Snaptic never asks for the permission
  when you point at the Dock. macOS may still show its own screen-recording reminders (§4.9).
- **Optional Dock click actions**, off until you turn them on:
  - click the active app's icon to hide it or minimize its windows;
  - click an app whose windows are all minimized to bring them all back.

Both modules share one window service, so the **Window Switcher** gets these upgrades too:

- Thumbnails for **minimized and other-Space windows**, where macOS allows the capture (§4.9). Today they show the
  app icon.
- Its thumbnail cache stays in memory between openings for up to 30 minutes, so thumbnails appear at once and
  refresh in place.
- The shared window rules (§4.8):
  - tiny windows and notification-style pop-ups are left out;
  - a "Minimized and hidden last" sort option;
  - a display badge when there is more than one display.
- Its private symbols get the C-symbol contract (§4.12): presence and image checks, a probe, result checks,
  poisoning, a crash guard, kill switches and selftest lines.

Dock Previews is **off by default**. It ships in **0.5.0 (CFBundleVersion 500)**, with a "New: Dock Previews" card
and an opt-in row in onboarding.

## Owner decisions (2026-11-12; not reopened)

| Q | Decision |
|---|---|
| Q1 | **A fifth module, "Dock Previews"**, sharing one window service (`WindowServices`) with the Window Switcher. It has its own switch, Settings page, kill switch and CLI (`snaptic dock …`), and the id `ModuleID.dockPreviews`. |
| Q2 | **Core plus extras.** In scope: hover previews; cards with badges; click, middle-click and hover buttons; text-only mode; keys in previews; the right-click menu; Hide and Quit in the header; opt-in Dock click actions; the other-tool pause; VoiceOver handling; the switcher upgrades. Out of scope (§9): the ⌘⇥ overlay, widgets, live or pinned previews, and snapping. |
| Q3 | **Private capture** (`CGSHWCaptureWindowList`) under the private-API rules. It falls back to the last-seen thumbnail, then to the app icon, and is shared with the switcher. *r2 adds the conditions in §4.9: Screen Recording granted, an owner check, a content check, the crash guard and pacing.* |
| Q4 | **Dock click actions are opt-in and off by default.** Click the active app's icon to hide it or minimize its windows. Click an app whose windows are all minimized to restore them all. The tap is listen-only, so a Dock click is never swallowed. |
| Q5 | **Pause while DockDoor or a similar tool runs.** The page says "Paused while … runs" and offers **Run Both**. |
| Q6 | **Every switcher private symbol gets the 0.4 treatment now.** *Restated for C symbols (r2; X-1, P-2):* a C function has no type encoding to check and throws no exception to catch, so 0.4's "encoding check" and "exception poisons" become the §4.12 contract (presence and image, OS gate, pinned prototype, behavioural probe, result checks with poisoning, crash guard, typed kill switch, selftest line). The decision itself is unchanged. |
| Q7 | **0.5.0 (CFBundleVersion 500), off by default**, with a "New: Dock Previews" card and an opt-in in onboarding. |

## Ground rules (carried over from 0.4; restated after r1)

1. **While off, the module costs nothing.** No AX observers, event taps, timers, panels, captures or prompts.
   `DockPreviewsModule.init` creates nothing; `start()` makes everything and `stop()` tears it down.
   - **While on and idle**, it runs only the Dock observer (on its own thread), its 30 s health check and, while
     the thumbnail store holds entries, one one-shot retention timer (§2.5; X3-10).
   - **No pointer monitor, tick timer, panel or capture** exists unless a preview is shown or pending (X-10, P-14).
   - **Taps.** The Dock click tap exists only while that opt-in setting is on. The keys tap is created when a panel
     first shows, and it stays disabled except while a panel is engaged or a key it swallowed is still down (§4.5).
   - **"Disabled"** means `CGEvent.tapEnable(false)`: the tap gets no events. This is the one exception to "nothing
     unless shown".
2. **Pure logic lives in SnapticKit** (Foundation only, tested on Linux).
   - The app holds only the AppKit, AX, SCK and private-API adapters.
   - Kit code never reads a clock. The policy takes `now` in each event and emits `schedule(after:token:)` (P-13).
3. **Private C symbols follow the §4.12 contract** (Q6 restated). Each one:
   - is looked up with `dlsym` only in `Windows/PrivateWindowAPI.swift`. The capture symbol is the one exception: it
     is looked up in `SnapticShims/SNWindowServer.m`;
   - passes the presence, image and OS checks and its probe;
   - has its results checked; a second bad result in a row poisons it for the process;
   - is crash-guarded until it's verified on this OS build;
   - has a typed kill switch.

   **A failure fails safe:** no preview, or a text-only one. The Dock is never affected.
4. **No synthetic input** (X-22, P-3).
   - Snaptic never posts a mouse or key event to any app or to the Dock: no canary, no event that keeps the Dock
     revealed, no synthetic ⌘N.
   - **Awake's `ActivitySimulator`** (`Awake/Sources/ActivitySimulator.swift:129–130`) is outside this rule. It
     posts by design, and only while the user's Awake rules ask for it. L2 already confines it (D2-6).
   - **One exception in the window code, shipped since 0.3:** the raise path's `SLPSPostEventRecordTo`. It sends a
     window-server activation record to the target process and makes no HID event. S0-8 checks that it doesn't
     reset HID idle time.
   - Lint L2 allows that call in `Windows/PrivateWindowAPI.swift` only.
   - **Taps** are listen-only, with two exceptions that swallow only the keys they handle: the switcher's existing
     `HotkeyTap`, and the Dock keys tap while a panel is engaged (§4.5).
5. **Never touch the Dock's preferences.** Dock geometry comes from AX frames. No CoreDock calls and no
   `com.apple.dock` writes.
6. **Privacy.**
   - No bundle ids, app names or window titles go into logs, EventLog, error text or diagnostics; those carry counts,
     booleans and enums only.
   - Private windows are never captured or cached, and their titles are never shown or spoken (§4.10).
7. **Thumbnails stay in memory.** They are never written to disk, and an entry is kept at most 30 minutes.
   - They are purged on lock, display sleep, system sleep, session resign, Screen Recording revocation and the last
     release (§2.5).
8. **Stubs and lint.**
   - Every new file adds its `scripts/stubs.tsv` row in the same commit.
   - Each work item ends with `scripts/lint.sh --strict` clean, and `swift build` and `swift test` green.
   - The lint scope changes are listed in H8.
9. **Clean room.** DockDoor is GPL-3.0, and parts of it derive from AltTab (GPL).
   - Implementers work from this plan, Apple's documentation and our own S0 results. They don't open DockDoor or
     AltTab source.
   - §1 records behaviour, public API names, release notes and issue numbers only. It cites no DockDoor source lines
     (Y-6).
   - The installed DockDoor app may be run as a black box: its Settings UI and its visible behaviour (S0-15, S0-32,
     M28).
   - `THIRD_PARTY_NOTICES.md` credits DockDoor's design. No file or snippet is copied.

---

## 1. What the source teaches (survey, corrected after r1)

This table records behaviour only, from DockDoor's documentation, release notes, issues and visible behaviour.

| DockDoor part | How it behaves | Snaptic decision |
|---|---|---|
| Dock hover detection | An AX observer on the Dock's `AXList` watches `kAXSelectedChildrenChangedNotification`, because the Dock "selects" the item under the pointer. A periodic health check re-attaches when the Dock's pid changes. It also re-checks that the `AXList` is still valid and re-enables its own Dock tap (Y-6). | Same signal in our own code: `DockObserver`, on its own thread (X-15). Liveness and re-attach rules are in §4.8 (X-17). A rebuilt `AXList` under the same pid (after a display change) is caught by an invalid-element read. No mouse polling. |
| Dock item → app | Subrole `AXApplicationDockItem`, then `kAXURLAttribute`, then the bundle, then the running app. | Match in this order (X-28): bundle URL against `NSRunningApplication.bundleURL`, then the URL's Info.plist bundle id, then `AXTitle` against `localizedName`. Running state comes from `AXIsApplicationRunning`. Duplicate copies follow S0-2 (§4.8; Y-16). Folders, Trash, stacks, minimized-window tiles and separators dismiss the panel. |
| Window list | `CGWindowList`, SCK shareable content and AX, then a remote-token lookup for other-Space windows, then per-app quirks (Y-6). | A new per-app read, `WindowManager.windows(for pid:budget:allowUntitled:)`, using AX plus `CGWindowList` for that pid. Spaces come from `SLSCopySpacesForWindows` (X-8, P-1). No token lookup. An untitled other-Space window shows as "Window on another Space" and can only be raised (§4.8). |
| Thumbnails | `CGSHWCaptureWindowList` has been the only still-image path for every window since v1.5 (2024-12-30). SCK is used only to list and stream. The screen-recording indicator still shows (#795) (Y-6). | SCK stills for on-screen windows. The private path only for minimized and other-Space windows, under §4.9 and §4.12. Then last-seen, then the icon. |
| Freshness | Shows cached data first, then refreshes, debounced 0.3 s. Driven by per-app AX observers and `NSWorkspace`. | The shared `FocusTracker` gains created, miniaturized, deminiaturized and title-changed notifications, plus per-window destroyed. They are registered only while a lease asks for freshness (X-9; §2.3). |
| Panel level | Status-bar level only while "Show preview above app labels" is on (the default); floating otherwise (Y-6). | One level, chosen by S0-6, that clears the Dock's name label (X-30). No setting. |
| Panel | Non-activating and on all Spaces. Dock orientation, magnification and auto-hide come from private CoreDock calls. | A non-activating panel built on `SnapticPanel`. Geometry comes from AX frames against the screen (§4.7). No CoreDock. |
| Dismissal | A tracking area plus a 0.2 s timer. The top complaint is previews that won't go away (#472). | A Kit state machine with a corridor, an engagement rule, a dismiss latch and a hard safety net (§4.6). |
| Raise | `_SLPSSetFrontProcessWithOptions`, then `SLPSPostEventRecordTo`, then `kAXRaiseAction`. | Reuse the switcher's `WindowManager.focus`, which uses the same symbols and has shipped since 0.3, under §4.12. |
| Card actions | Click raises. Middle-click closes, and the middle-click action can be changed. Traffic-light buttons. ⌘W, ⌘M and ⌘Q while hovering. A context menu with snapping and "bring to this Space". | Click, middle-click (fixed to close), hover buttons and a right-click menu. ⌘W, ⌘M, ⌘H, ⌘Q and Esc only when the panel is engaged (§4.5). No snapping and no Space moves (§9). |
| Dock preview gestures | Card swipe gestures are on by default (Y-6). | None in 0.5 (§9). |
| Dock clicks | An **active** tap that swallows Dock clicks and scrolls. ⌘-right-click quits and is on by default (⌥ forces). Shift-click is always on and posts a synthetic new-window command. Dock-click hide is off by default; restore-all is on. | Listen-only, opt-in, two actions, nothing swallowed (§4.11). |
| Synthetic input and taps | DockDoor posted a periodic activity canary (#1634, #1648). It posts mouse-moved events to the Dock for "Prevent dock hide", which is on by default. It runs an always-on, session-wide active key tap. Users reported input lag (#813) and lost input (#1655). | None of these (ground rule 4). The keys tap is enabled only while a panel is engaged. |
| Folder previews | Off by default. | Not included (§9). |
| Cmd+Tab overlay | Window cards above the system ⌘⇥ switcher (off by default). | Not included: the switcher's ⌘⇥ takeover already replaces it (§9). |
| Widgets | Media uses private MediaRemote, with an AppleScript fallback and lyrics from web APIs. For players other than Music and Spotify, it uses a `/usr/bin/perl` adapter with a bundled framework. Calendar uses EventKit. | Not included (§9). |
| Text-only mode | Works without Screen Recording. | Same. Never asks for the permission on hover. |
| Top issues | Previews die until relaunch (sleep and wake, taps). Previews won't dismiss. Auto-hide Dock timing. Multiple monitors. Stage Manager. Leaked taps and CPU use. The display won't sleep. Spaces. | Each one has an S0 row (§5) and a manual check (§7). |

**What DockDoor's issues teach**

- Event-driven AX beats polling.
- Re-attach after every lifecycle event.
- Show the cache first.
- Back off from apps whose AX calls stall.
- Never touch the Dock's preferences.

**Where Snaptic differs on purpose.** These are deliberate differences, not parity gaps, and implementers must
not "fix" them toward DockDoor:

- no synthetic events;
- no active tap over the Dock;
- no always-on key tap;
- private windows protected;
- the crash guard;
- no capture without Screen Recording.

### 1.1 Defaults compared (G-19, Y-11, Y-12, Y-14)

The DockDoor column comes from its Settings UI, release notes and the parity review. S0-32 re-checks it on the
installed app. A difference found there is recorded in STEP0-NOTES, and it changes nothing here unless a round-2
reviewer asks.

| Setting | DockDoor | Snaptic | Why |
|---|---|---|---|
| Hover delay | short, adjustable | 0.2 s, 0–1 s | The draft's value; "Immediately" at 0 |
| Swap between apps | delayed (#54) | at once, unless the pointer is heading into the panel (§4.2) | Moving along the Dock shouldn't wait (Y-14) |
| Card size | 300 × 187.5 | Medium, 280 pt wide; 16:10 frame (Y-12) | Fits more cards in one row |
| Dynamic sizing | off | none: fixed 16:10, letterboxed | One shape is easier to scan |
| Rows (bottom Dock) | 1 | 1; shrink a size, then scroll (§4.3) | No hand-off to the switcher (G-12) |
| Columns (side Dock) | 2 | 2 | Same |
| Fade | 0.4 s | 0.15 s fade; nothing moves (§4.7) | Faster; safe under Reduce Motion |
| Windowless app | nothing shown | a small "No open windows" card (Advanced switch) | A hover with no response looks broken; the card also activates the app (Y-11) |
| Dock click hide | off | off (Do Nothing) | Q4 |
| Restore all minimized | on | off | Q4: every Dock click action is opt-in |
| Middle-click | close (configurable) | close (fixed) | One less setting |
| Panel level | above labels (on) | one level that clears the label (S0-6) | No setting |

---

## 2. Architecture and file homes

### 2.1 SnapticKit (Foundation only, Linux-tested)

Kit types never see an `NSPanel`, an `AXUIElement`, a `CGImage` or a clock. They take value types and `now`, and
they return values or commands, so every test asserts on plain data (P-13).

```
DockModel.swift             DockRect (x, y, w, h; Cocoa, bottom-left origin), DockPoint, DockScreen (id, frame,
                            visibleFrame, scale, isPrimary), DockEdge (bottom, left, right), DockItemKind (app,
                            folder, trash, minimizedWindow, separator, other), DockSelection (kind, pid?, itemFrame,
                            listFrame, byPointer), DockFeature (clickActions, keys)
DockGeometry.swift          AX → Cocoa conversion (Screens.cocoaRect rules, X-27); edge from the settled item frame;
                            the Dock zone (§4.1); the corridor hull; placement; card grid; shrink then scroll; RTL
DockPreviewPolicy.swift     the hover machine: delay, swap intent, engagement, corridor, grace, latch, lockouts,
                            safety net, every dismiss reason, the card-click resolver (§2.4)
DockClickRules.swift        the Dock click resolver over an activation history (§4.11)
DockKeyRules.swift          the key decision (§4.5): a snapshot (engaged, target, keys work, held key code, reflow
                            lock) and a key-down, key-up or autorepeat in; pass, or swallow with an action, out. The
                            tap callback calls it on the main run loop and does nothing else
DockPageRules.swift         the state table (§4.17): first row that applies wins; pause precedence; page row, menu
                            row, CLI state and the verb × state table (§4.21)
DockCommandGrammar.swift    `dock status|pause|resume`, using AwakeDurationGrammar for durations (§4.21)
KnownDockTools.swift        exact bundle ids from S0-15, same shape as KnownMenuBarHiders
WindowCatalogRules.swift    CatalogWindow (id, pid, hasTitle, minimized, hidden, onScreen, spaceKnown: Bool?,
                            fullscreen, layer, bounds: DockRect, isPrivate, hasAXElement); inclusion, privacy,
                            recency merge, sorts, badges, freshness (§4.8–§4.10)
ThumbnailIndex.swift        the thumbnail store's bookkeeping, without images (P2-3): keys (windowID, pixel bucket),
                            client tags, per-client generation, epoch, the stamp check, invalidate, prune, purge,
                            purgeAll, LRU by 120 entries and 96 MB, the oversize skip, 30-minute expiry and the next
                            expiry time, and the bucket lookup (§2.3)
WindowLeaseLedger.swift     leases by ModuleID; the union of needs; first and last edges per need (§2.3)
WindowSymbolContract.swift  WindowFeature (hwCapture, axWindowID, raise, spaces, symbolicHotKeys, layoutType); one
                            row per symbol (name, image list, feature, read-only or not); OS gate, result classes,
                            the poison counter and re-probe, fallback(for:), launch lines (§4.12). The app's
                            WindowSymbol struct (PrivateWindowAPI.swift) mirrors these rows (P2-8)
CrashGuard.swift            per-symbol in-flight counts, the launch decisions and verified-after-20 (§4.12);
                            IconsCrashGuard (IconsEngineCore.swift:163) stays as it is (§9)
Config/ConfigDock.swift     DockConfig: sanitize, defaults, backup allowlist, lossy enums, requiredPermissions
Controls/DockPageControls.swift, DockAdvancedSheetControls.swift, DockMenuRowsControls.swift
```

`AwakeCountdown.unit(_:_:_:)` moves from `AwakeClock.swift:210` into `SentenceText` unchanged (P3-7), so "1 window" and "3 windows" share
Awake's plural rule (G-24). `properNames` gains "Dock Previews" and "Dock" (G-15).

### 2.2 Snaptic (app)

```
Windows/WindowServices.swift      leases (§2.3); owns WindowManager, ThumbnailStore, FocusTracker and WindowCapture;
                                  the purge observers (§2.5); live counters
Windows/WindowManager.swift       git mv from Switcher/ (B1a); gains windows(for pid:budget:allowUntitled:) (A3; §4.8)
Windows/ObserverThread.swift      extracted from WindowManager.swift:601 (B1a); FocusTracker, the freshness observer,
                                  the window-read thread (§4.8) and DockObserver each run on their own instance
Windows/ThumbnailStore.swift      git mv from Switcher/; holds the images only, keyed by ThumbnailIndex (§2.3, §4.9)
Windows/PrivateWindowAPI.swift    every dlsym in Swift; the window symbols, the symbolic-hotkey symbols and the
                                  Carbon lookups, each under the §4.12 contract, except the public
                                  IsSecureEventInputEnabled (§4.12)
Windows/InflightMarkers.swift     the crash marker files: open + write(2) on a symbol's 0→1, unlink on 1→0 (§4.12)
Windows/WindowCapture.swift       the SCK path, the private path (through the shim), last-seen, gates and pacing
Switcher/SystemHotkeys.swift      SystemHotkeys and HotkeyGuard, split out of PrivateAPIs.swift; they call
                                  PrivateWindowAPI for their pointers (P-5)
SnapticShims/SNWindowServer.m/.h  the CGSHWCaptureWindowList call, with caller-allocated, bounded buffers (X-1)
Dock/DockPreviewsModule.swift     SnapticModule: start, stop, state, menuSection(tabbed:), requiredPermissions
Dock/DockObserver.swift           the AX observer on the Dock's AXList, on its own ObserverThread; liveness (§4.8)
Dock/DockReader.swift             AX item → DockSelection, multi-attribute reads, 0.15 s per element
Dock/DockPreviewController.swift  feeds DockPreviewPolicy, runs its commands; the pointer monitor and tick
Dock/DockPreviewPanel.swift       the panel, built on SnapticPanel (§4.7)
Dock/DockPreviewView.swift        SwiftUI cards, header, hover buttons, menus, accessibility labels
Dock/DockKeys.swift               the engaged-only keys tap (§4.5)
Dock/DockClickTap.swift           the listen-only Dock click tap (§4.11)
Dock/DockCLI.swift                ControlCommandRegistry verbs
Dock/UI/DockPage.swift, DockAdvancedSheet.swift, DockMenuRows.swift
```

`WindowGatherer` ("Gather windows here"), `HotkeyTap`, the secure-input timer and `SwitcherController` stay in
`Switcher/`.

### 2.3 The `WindowServices` contract (P-6, X-6, X-18, P-24)

- `acquire(_ client: ModuleID, needs: WindowNeeds) -> WindowLease`, `update(_ lease:, needs:)` and `release(_:)`.
- `WindowNeeds` is a set:
  - `.recency`: `FocusTracker` on every regular app, focus changes only, as today;
  - `.freshness(pid)`: the extra notifications for **one** app, which are `kAXWindowCreatedNotification`,
    `kAXUIElementDestroyedNotification`, `kAXWindowMiniaturizedNotification`,
    `kAXWindowDeminiaturizedNotification` and `kAXTitleChangedNotification` (X-9);
  - `.thumbnails`: this client's Window thumbnails setting is on, so it may capture and its entries are kept;
  - `.otherSpaces`: this client lists other-Space windows.
- Observers run for the union of live leases. Each one is removed when no lease asks for it. The union logic, the
  refcount and the edges per need are the Kit value type `WindowLeaseLedger`.
- **Edges (X2-9).** Each need starts and stops on its own edge:

  | Edge | Starts | Stops |
  |---|---|---|
  | First lease / last release | the system-wide AX messaging timeout of 0.15 s (moved from `WindowSwitcherModule.swift:52`) and the §2.5 purge observers | the last release cancels in-flight captures, purges the store and removes every observer |
  | First / last `.recency` | `FocusTracker` on its `ObserverThread`, as today | `FocusTracker` and its thread |
  | First / last `.freshness(pid)` | the five notifications for that pid. They are added to `FocusTracker`'s observer for that pid when `.recency` is live; otherwise one freshness `AXObserver` for that pid on its own `ObserverThread` (D2-5) | 2 s after the last freshness need drops; the thread stops with its last observer |

  Per-window `kAXUIElementDestroyedNotification` registrations are capped at the windows the last read returned
  (D2-18).
- **The switcher** acquires `[.recency]`, plus `.thumbnails` and `.otherSpaces` as its settings say, in `start()`. It
  releases in `stop()`. With Dock Previews off it registers exactly what it does today.
- **Dock Previews** acquires in `start()` with `.thumbnails` and `.otherSpaces` as its settings say, and no
  `.recency`. While a preview is pending or shown, it adds `.freshness(pid)` for the hovered app, and it drops it 2 s
  after the panel hides. The idle lease registers notification-centre observers only: no thread, timer or AX
  observer (ground rule 1). M32 counts each case.
- **Shared privacy settings (D2-1).** "Protect private windows" and its app list stay where 0.4 keeps them: in the
  switcher's `Config` (`privateBundleIDs` and `protectPrivateWindows`, `Settings.swift:255–256`), in the
  `SnapticConfig.v1` defaults key. `AppSettings.shared` is loaded by `ModuleHost` (`ModuleHost.swift:40`) whether
  or not the switcher runs, so `WindowServices` reads them from there for both modules. Nothing moves, so the upgrade
  keeps the list and a downgrade to 0.4 reads it unchanged. Backup and reset rules are in §4.10.
- **Recency.** The Dock uses `FocusTracker`'s order when a `.recency` lease is live. Otherwise it uses that app's
  `CGWindowList` front-to-back order, then minimized windows in AX order (§4.8).
- **The store** is client-tagged. `ThumbnailIndex` (Kit) holds every rule, and `ThumbnailStore` holds only the images
  under the index's keys (P2-3):
  - keyed by `(windowID, pixel bucket)`;
  - `generation`, `invalidate(client:)` and `prune(keeping:client:)` are per client; `prune` never removes another
    client's entry, and it keeps last-seen entries for windows that still exist;
  - `release` and `purge(client:)` bump that client's generation first, then drop its entries, so a capture that
    lands late is dropped by the stamp check. The calls run to the end and wait for nothing (X2-12);
  - an `update` that drops `.thumbnails` runs `purge(client:)` at once. A client without `.thumbnails` gets no
    thumbnail from any lookup, including another client's entry (X2-11);
  - `purgeAll()` runs on the §2.5 triggers;
  - a lookup takes the smallest cached bucket at least as large as asked, else the largest smaller one, shown at once
    while a fresh capture runs;
  - LRU eviction by 120 entries and 96 MB; one entry over 16 MB is skipped, not stored (§4.9; P3-5). A 2400-pixel
    switcher preview of a window squarer than about 3:2 is over 16 MB, so it's shown but not cached (X3-10).
  - **Staging (D2-22).** A1a keeps 0.4's limits (40 entries, 5 minutes). A2a switches to 120 entries, 96 MB and
    30 minutes, and D2's release notes list the switcher's new cache limits.
- **Counters** for selftests and diagnostics: `WindowServices.liveLeases`, `ThumbnailStore.liveEntries`,
  `ThumbnailStore.liveBytes`, `FocusTracker.liveObservers`, `WindowServices.freshnessObservers`.

### 2.4 Policy events and commands (P-13, P-14)

`DockPreviewPolicy` is a value type with `mutating func handle(_ event:, now:) -> [DockCommand]`.

| Events in | Source in the app |
|---|---|
| `selectionChanged(DockSelection?)` | `DockObserver` (its own thread; delivered on main, coalesced to the latest) |
| `pointerMoved(DockPoint)` | a global `.mouseMoved` / `.leftMouseDragged` monitor, throttled to 60 Hz, installed only while a preview is pending or shown (X-10) |
| `panelEntered`, `panelExited`, `pointerMovedInPanel(DockPoint)` | the panel's `NSTrackingArea` |
| `panelClicked` | any mouse-down in the panel (engages, §4.5) |
| `voiceOverFocusInPanel(Bool)` | the view's `@AccessibilityFocusState` (G2-5) |
| `tick` | a 0.1 s timer that runs only while the panel is up |
| `fired(token)` | a one-shot timer the app starts for `schedule(after:token:)` |
| `mouseDownOutside`, `mouseDownOnItem(DockSelection)`, `dragStarted` | a global mouse-down / drag monitor, only while a preview is pending or shown |
| `ownMenuOpened`, `ownMenuClosed` | `NSMenu` delegate of the card and header menus (X-25) |
| `dockMenuOpened`, `dockMenuClosed` | `kAXMenuOpenedNotification` / `kAXMenuClosedNotification` on the Dock (X-12) |
| `appActivated(pid, byUs)`, `appTerminated(pid)` | `NSWorkspace`; `byUs` within 1.5 s of our own action, 5 s for Quit (X-25) |
| `spaceChanged`, `displaysChanged`, `locked`, `screensSlept`, `willSleep`, `sessionResigned` | `NSWorkspace`, `DistributedNotificationCenter` |
| `switcherOpened`, `switcherClosed` | `WindowServices.switcherSessionActive` becoming true or false: a new flag the switcher sets while `SwitcherController.active` is non-nil (X-14, X2-15). While it's true, nothing shows or swaps |
| `windowsChanged(pid)` | the freshness lease, debounced 0.3 s |
| `actionDone(DockAction)` | our own raise, close, minimize, hide or quit |
| `keyHandled(DockKeyAction)`, `keyNotHandled` | `DockKeys` acted on a table key, or saw a key-down that isn't in its table (§4.5). `flagsChanged` is never sent |
| `pauseChanged(DockPauseReason?)` | the module (§4.17) |

| Commands out | Effect |
|---|---|
| `watchPointer(Bool)` | install or remove the pointer monitor |
| `show(pid, anchor: DockRect, edge:)`, `swap(pid, anchor:, edge:)` | the controller reads the windows and shows or swaps |
| `hide(DockDismissReason)` | hide; the reason is counted (enum only) |
| `refresh(pid)` | re-read the windows and update cards in place |
| `engageKeys(Bool)` | enable or disable the keys tap |
| `schedule(after:token:)` | start a one-shot timer; a stale token is ignored |

`DockDismissReason`: `left`, `safetyNet`, `clickOutside`, `itemClicked`, `dockMenu`, `raised`, `hidApp`,
`quitApp`, `escape`, `appTerminated`, `activation`, `space`, `display`, `lock`, `sleep`, `session`,
`switcherOpened`, `paused`, `stopped`, `noItem`. Mission Control and App Exposé need no reason: the panel is
`.transient` (X-16).

### 2.5 Purge and stale rules (X-18, ground rule 7)

- **`purgeAll()` runs on:**
  - lock (`com.apple.screenIsLocked`);
  - display sleep and system sleep;
  - session resign (fast user switching);
  - Screen Recording found revoked (the preflight at the next capture batch, or the page's 2 s permission poll
    while Settings is open);
  - the last release;
  - no live lease with `.thumbnails`.
- **Retention (X2-13).** Every entry expires 30 minutes after its capture, checked on lookup. One one-shot timer is
  set for the earliest expiry (`ThumbnailIndex.nextExpiry`), with 60 s of leeway (X3-10). It is re-armed after each sweep and cancelled when the
  store is empty, so an empty store has no timer.
- **Stale results.** Every capture is stamped `(client, generation, epoch)`. `purgeAll()` bumps `epoch`, and
  `purge(client:)` bumps that client's generation. A result whose stamp is stale is dropped before it reaches the
  store.
- `release` bumps that client's generation and returns. Its in-flight captures finish and are dropped by the stamp
  check (X2-12). M32 counts AX observers to prove nothing is left.

### 2.6 What the switcher has today, and what 0.5 changes (P-1)

| Today (`7dd972c`) | 0.5 |
|---|---|
| `WindowManager.loadWindows(includeOtherSpaces:includeWindowless:excluded:)` walks every regular app. There is no per-pid read, and `WindowGatherer` gathers windows; it doesn't list them. | Adds `windows(for pid:budget:allowUntitled:)` on the same AX and `CGWindowList` paths for one pid (§4.8). |
| Other-Space windows come from `CGWindowListCopyWindowInfo` with `axElement: nil`, and untitled ones are dropped (`:456`). Close, minimize and full screen guard on `axElement`. | The Dock path keeps untitled other-Space windows as "Window on another Space" (`allowUntitled: true`). Cards without an AX element offer only Bring Forward (§4.4). The switcher's own list is unchanged. |
| The "Other Space" state is `!minimized && !hidden && !onScreen`; `SLSCopySpacesForWindows` only filters out native tabs and helper windows. | Same rule, now in `WindowCatalogRules`. `Windows.disable.spaces` drops the other-Space list instead of showing it unfiltered (P-19). |
| `FocusTracker` is private to `WindowManager` and observes `kAXFocusedWindowChangedNotification` only. | It moves into `WindowServices`. `.freshness(pid)` adds five notifications for one app (§2.3). |
| `ThumbnailStore` captures on-screen windows only with SCK. It keeps 40 entries for 5 minutes, has one `generation`, and is purged by the switcher's `stop()` and by turning switcher thumbnails off. | Client-tagged, with its rules in Kit `ThumbnailIndex`. From A2a: byte-counted (120 entries, 96 MB) with 30-minute retention; A1a keeps 0.4's limits (D2-22). `WindowCapture` adds the private path for minimized and other-Space windows (§4.9). Thumbnails of a window both modules show are shared only while both clients have `.thumbnails` (§2.3). |
| The switcher already shows cached thumbnails between openings. | It also shows thumbnails the Dock captured, under the shared privacy rule (§4.10). |
| `ThumbnailStore`'s privacy note says nothing is captured once the switcher is dismissed. | Rewritten (A2a, and D1 for the README): "Captured only while the Window Switcher or a Dock preview is showing. Kept in memory for at most 30 minutes, and purged on lock, sleep, fast user switching and when the last module using them stops." |

---

## 3. Host changes

- **H1. `ModuleID.dockPreviews`** (raw `dockPreviews`), last in start order.
  - K1 creates `docs/design/0.5/H1-SITES.md` from r1 pressure Appendix A's recommended wide grep (the pinned
    command; 1574 hits in 215 files at `7dd972c`; re-run at K1's base) and gives every hit a disposition (P2-23).
    It also lists every `WindowServices` and `ThumbnailStore` call site with its client (D2-14) and the onboarding
    `requiredPermissions` line (D2-30).
  - Filling every exhaustive `switch` over `ModuleID` and `NewModuleCard` is a compile step. `SettingsRootID` is a
    case-less enum, so its root list, groups and aliases (`SettingsShellRules.swift:7–24`) are a grep step, checked by
    `SettingsShellRulesTests`.
  - Sites the compiler won't flag (P-10, G-3, G2-7):
    - `defaultPreferences(.dockPreviews)` is `enabled: false, presence: .inSnapticMenu`, as for Hidden Icons
      (`ConfigModules.swift:228`). `MenuPresence.allowed(.dockPreviews)` is `[.inSnapticMenu, .hidden]`, and
      `fallback(for: .dockPreviews)` is `.inSnapticMenu`. A tab adds no menu bar icon, and it is where Pause and the
      attention mark live (§4.19). `MenuLayout.ownIconIDs` never contains `.dockPreviews`, whatever is stored.
    - Turning Dock Previews on later never changes its presence (D2-29).
    - `MenuPlacement.help(.hidden, .dockPreviews)` is "Previews show when you point at the Dock. Change them in
      Settings."
    - `showSnapticMenu()` skips `.dockPreviews`, as it skips Awake.
  - K1 adds an inert `Dock/DockPreviewsModule.swift`: `start()` and `stop()` do nothing, `state == .stopped`, and
    `requiredPermissions` is `[.accessibility]`. It fills `ModuleHost.module(_:)` until A6a.
  - The Menu Bar page's per-module rows filter out `.dockPreviews` until A7.
- **H2. Window services** (§2.3). Each module acquires in `start()` and releases in `stop()`. The purge observers
  and the AX timeout move into `WindowServices`.
- **H3. The private-API split** (P-5, X-23, X-24).
  - `Switcher/PrivateAPIs.swift` is removed. Every `dlsym` and dynamic lookup moves to
    `Windows/PrivateWindowAPI.swift`, and `SystemHotkeys` and `HotkeyGuard` move to `Switcher/SystemHotkeys.swift`.
  - **Callers** (P2-12; checked at `7dd972c`). "Give" means it gives ⌘⇥ back; "take" means it disables it.

    | Site | Call | Symbol, feature | Under the contract |
    |---|---|---|---|
    | `AppDelegate.swift:58` | `recoverFromPreviousRun()` | hotkey setter, give | give-back guard (§4.12), never the take guard or the kill switch |
    | `AppDelegate.swift:71` | `HotkeyGuard.shared.start()` | none at start | — |
    | `AppDelegate.swift:72–74` | `HostHeartbeat` → `reassert()` | setter, take | B1b adds the kill-switch and poison checks |
    | `AppDelegate.swift:131`, `:132` | `restore()`, `releaseAll()` | setter, give | give-back guard |
    | `AppDelegate.swift:221` | `releaseAll()` in the signal handler | setter, give | pre-resolved pointers called bare: no marker, no defaults, no kill switch (D2-11) |
    | `HotkeyGuard.check()` | re-enables what macOS turned back | setter, give | give-back guard |
    | `WindowSwitcherModule.swift:90` | `restore()` | setter, give | give-back guard |
    | `WindowSwitcherModule.swift:219` | `apply(…)` | setter and `isSymbolicHotKeyEnabled`, take and give | take: full contract; give: give-back guard |
    | `WindowSwitcherModule.swift:229`, `:231` | `isSecureInputEnabled`, `setSuspended(blind)` | `IsSecureEventInputEnabled` (public, exempt); setter | §4.12 exemption; X2-2's unknown state |
    | `Settings.swift:37`, `:135` | `isISOKeyboard` | `KBGetLayoutType`, `LMGetKbdType` (`layoutType`) | full contract, once per keyboard type: `WindowServices.layout(for:)` caches the answer by keyboard type for the process. The tap reads the type from the event's public `keyboardEventKeyboardType` field and then a cached `Bool`, with no I/O. A type not seen yet is looked up off main, and that key-down uses the last cached answer (X3-7). Fallback ANSI |
    | `WindowManager.swift:283`, `:452` | `isOnAnySpace` | `SLS/CGSCopySpacesForWindows` (`spaces`) | full contract |
    | `WindowManager.swift:379` (inside `concurrentPerform`, `:354`), `:401`, `:540`, `:589` (AX callback), `:826` | `windowID(of:)` | `_AXUIElementGetWindow` (`axWindowID`) | full contract; the counter is atomic (§4.12) |
    | `WindowManager.swift:501`, `:531` | `bringToFront` | the raise trio (`raise`) | full contract |

  - **Launch order (X2-3).** A new step 3b in `continueStartup()` runs `CrashGuard.atLaunch` before step 4
    (`AppDelegate.swift:57–58`). It reads every in-flight marker and records the disabled builds (§4.12). Step 4
    skips the give-back when the give-back is disabled on this build, logs EventLog `.safety`, and moves the saved
    list to `Windows.pendingGiveBack` (§4.12 step 6; X3-2).
  - `HotkeyGuard.releaseAll()` in the signal handler (off main, `:221`) keeps using pointers resolved before the
    handler is installed. It reads no kill switch and no main-actor state, and it writes no crash marker.
  - The heartbeat at `:72–74` is `HostHeartbeat`, which drives `HotkeyGuard.beat()` (H6).
  - Lint rule 11: `Switcher/PrivateAPIs` → `Windows/PrivateWindowAPI`. It also gains a shim allowlist for `dlsym` and
    `dlopen` in `.m` files, which freezes today's shim files plus `SNWindowServer.m`.
- **H4. Settings.** A ninth sidebar page, **Dock Previews** (symbol `dock.rectangle`, tint `.green`; G-22), between
  Hidden Icons and Permissions. `SettingsRootID.dockPreviews`, alias `dock`.
- **H5. Permissions page** rows follow §4.14.
- **H6. Kill switches** (P-7 restated, P-27, G-20).
  - `Modules.disable.dockPreviews` is read once at launch, like the other four, and its text says "takes effect at
    the next launch".
  - `Dock.disable.*` (`DockFeature`) and `Windows.disable.*` (`WindowFeature`) are typed Kit enums read with
    `KillSwitches.read(domain, prefix: "Dock"|"Windows", as:)`. A key is
    `KillSwitches.key(prefix: "Windows", id: feature.rawValue)`, one per `WindowFeature`, not per symbol (P2-8). The
    K1 doc comment on `KillSwitches` lists all six prefixes: Modules, Displays, Awake, Icons, Dock and Windows (P2-17).
  - **Read once per batch** (P2-17), with no polling timer: at each window enumeration, each capture batch, each
    raise, each tap enable and each ⌘⇥ take. `Dock.disable.clickActions` is also read on each mouse-up the resolver
    would act on (D2-15). `KillSwitches.read` is a `UserDefaults` read, which is safe on any thread. A batch already
    running finishes, and the next one falls back.
  - The first read that sees a changed value logs one EventLog line, `windows.killSwitch.<name> on|off`.
  - `Windows.disable.symbolicHotKeys` blocks only *taking* ⌘⇥. Giving it back always runs: `restore()` at stop,
    `recoverFromPreviousRun()`, `HotkeyGuard.check()` and `releaseAll()`. No kill switch, OS gate (§4.12 step 2),
    image check or poisoning ever blocks it, on any macOS 0.4 supports. The `HostHeartbeat`, which already runs while
    ⌘⇥ is taken, reads the switch, and it calls `restore()` once when the switch turns on. The one exception is the
    give-back's own crash guard (§4.12 step 6): when giving ⌘⇥ back crashed on this OS build, the list waits in
    `Windows.pendingGiveBack` until Try Again or the next OS build (X2-3, X3-1, X3-2).
  - Advanced lock rows for `Windows.*` switches show on both Advanced sheets (D2-30).
  - The README and guide give one row per switch with its effect (G-20), and one `defaults write` example per prefix.
- **H7. Pinned tests** (P-18).
  - Updated in K1: `KitModulesTests` (`allCases`, `allowed`, `fallback`), `SettingsShellRulesTests` (9 roots, groups),
    and `ConfigModulesTests` `:13`, `:345` and `:373`, plus Dock versions of `:608`, `:621` and `:653`.
  - Updated in A8: `IconsControlsTests.swift:196–197`, which pins the welcome text §4.20 changes (P3-9).
  - `:13`: fresh defaults exclude `.dockPreviews` from the enabled set, as they exclude `.hiddenIcons`.
    `ConfigFixtures.fullModules()` passes unchanged. `ConfigModulesTests` asserts `presence(.dockPreviews) ==
    .inSnapticMenu` on fresh defaults and after `resetMenu()` (G2-7).
  - New: `ConfigDockTests.testA05ModulesFileDecodesWithUnknownValues` and
    `ConfigDockTests.testFieldNamesAvoidTheSensitiveFragments`. Run Both is stored as `runAlongsideOtherTools`.
  - If S0-9 adds `Permission.inputMonitoring` (§4.14), its `Codable` decode and the 0.4 decode of an unknown case are
    pinned here (G2-6).
  - **Downgrade.** In a throwaway `git worktree` at `v0.4.0`, a one-off test decodes the 0.5 fixtures with 0.4.0's
    types: a modules file with `dockPreviews` and the `dockPreviews` card; a backup with a `dock` section; and a
    switcher `Config` with a custom `privateBundleIDs` and `protectPrivateWindows == false`, which must decode with
    both values intact (D2-1). The command and result go in `H1-SITES.md`, and the worktree is deleted.
- **H8. Lint and stubs** (P-9, X-22, X-23). Each row lands in the item named.

  | Rule | Change | Item |
  |---|---|---|
  | L2 | Bans `CGEventPost`, `CGEventPostToPid`, `postToPid` and `IOHIDPostEvent` everywhere except Awake's `ActivitySimulator` (its shipped 0.3 path, ground rule 4); keeps today's `.post(tap:` rule; allows `SLPSPostEventRecordTo` only in `Windows/PrivateWindowAPI.swift` (D2-6) | B1a |
  | L13 | Adds `Sources/Snaptic/Dock/UI/DockMenuRows.swift` to the explicit list | K1 (rule), A7 (file) |
  | L14 | Adds `under(p, "Dock/") or under(p, "Windows/")`, and exempts `Windows/ObserverThread.swift`, which only moves (P2-10) | K1 |
  | L15 | `L15_PENDING` gains `DockPageControls`, `DockAdvancedSheetControls` and `DockMenuRowsControls` | K5 (add), A7 (empty again) |
  | L17 | Adds `Dock/`, `Windows/`, the Kit basenames starting `Dock`, `KnownDockTools`, `WindowCatalogRules`, `ThumbnailIndex`, `WindowSymbolContract`, `WindowLeaseLedger`, `CrashGuard` and `ConfigDock` | K1 |
  | L20 | Scope becomes `Icons/`, `Dock/`, `Windows/` and `Switcher/`, and the message says "under Icons/, Dock/, Windows/ or Switcher/". `Switcher/` has one hit today, `WindowGatherer.swift:70` (`"Gathered \(moved) windows"`). `record` has no count field, so K1 changes it to the fixed string `"Gathered windows"` (P2-11) | K1 |
  | `SETTINGS_VIEWS` | Adds `"Dock/UI/"` | K1 |
  | Rule 11 | Swaps the path and adds the shim allowlist (H3) | B1a |
  | Rule 10 | No change (`exempt = {"PrivateSymbol"}` in `scripts/lint.sh` rule 10). The window symbols are a new `WindowSymbol` struct declared in `PrivateWindowAPI.swift` (`name`, `image` where nil means `RTLD_DEFAULT`, `feature: WindowFeature`), mirroring Kit's `WindowSymbolContract` rows. No extension crosses a file, and Displays' `PrivateSymbol` is untouched (P2-8) | B1b |
  | `stubs.tsv` | B1a removes the `Switcher/PrivateAPIs.swift` row (l.127) and adds `Windows/PrivateWindowAPI.swift`, `Windows/ObserverThread.swift` and `Switcher/SystemHotkeys.swift`; the `git mv` items update their rows; B1b adds `Windows/InflightMarkers.swift`; every later file, Kit `ThumbnailIndex.swift` included, adds its row in the commit that creates it | each |

- **H9. Docs that count modules or describe Snaptic** (G-13). D1 and D3 change all of these:

  | Where | Change |
  |---|---|
  | README l.9 tagline | Add "· Preview windows from the Dock" |
  | README l.16 | "What's new in 0.5" → `docs/design/0.5/RELEASE-NOTES-0.5.0.md` |
  | README l.22 | "four everyday Mac utilities" → "five" |
  | README l.24–29 module table | New row: **Dock Previews**, "Point at an app in the Dock to see its windows, and click one to bring it forward." |
  | README l.48 switcher tiles | Add "Minimized windows and windows on other Spaces get thumbnails too, when macOS allows it." |
  | README l.202 | "(⌘1–⌘4)" → "(⌘1, ⌘2, and so on)" |
  | README l.210–211 permissions | Accessibility adds "Dock Previews". Screen Recording: "Switcher and Dock Previews thumbnails, the switcher's preview, and Picture in Picture." |
  | README l.241–248 CLI examples | Add `snaptic dock pause 30m   # no Dock previews for half an hour` |
  | README l.272 release notes | Add [0.5.0](docs/design/0.5/RELEASE-NOTES-0.5.0.md) first (G2-14) |
  | README l.278 credits | "Dock Previews follows ideas from [DockDoor](https://github.com/ejbills/DockDoor) (GPL-3.0) in its own code; it shares no code with it and isn’t affiliated with it." |
  | README privacy text | The §4.10 footer wording (30 minutes; both modules) |
  | README Dock Previews section (D1) | Lists ⌘W, ⌘M, ⌘H, ⌘Q and Esc, "while the pointer is in the preview" (G2-1, G2-14) |
  | GUIDE l.5, l.15–24, l.24 | Module list, table and the "Use …" switch list add Dock Previews |
  | GUIDE l.9 | The DockDoor credit sentence above, and a 0.5.0 release-notes link first (G2-14) |
  | GUIDE l.34 | "eight pages" → "nine pages", with a Dock Previews link |
  | GUIDE l.51 | Dock Previews offers only Show in Snaptic Menu and Don't Show |
  | GUIDE l.60 | "⌘1–⌘4" → "⌘1, ⌘2, and so on" (G2-14) |
  | `Switcher/SettingsView.swift:100–121` | The §4.10 Privacy footer, list help and Restore Defaults message (G2-3, G2-14). A2b |
  | SITE l.702 | "8 / Eight pages." → "9 / Nine pages." |
  | SITE l.723–750 | Fifth card: **Dock Previews**, "Shows an app's windows when you point at it in the Dock. Off until you turn it on." |
  | `MANUAL-CHECKS.md` | "4 modules" → 5; `--selftest-launch` prints 5 modules / 0 running |
  | `SettingsShell.swift:69`, `Onboarding.swift:253` comments | "eight roots", "four rows" updated |

  README l.22's "No event taps, no timers, no permission prompts" is about modules that are off, so it stays true.
- **H10. Store and host wiring** (P-10; K1 for Kit, A6a for the app; the Safe Mode details text in A6a, the page
  and menu strings in A7; P2-22).
  - The `DockConfig` store in `ModuleHost.init`, `runMigrations`, the shutdown flush, `resetAllSettings` and Safe
    Mode.
  - `KitBackup` (P2-9, D2-1):
    - `dockSection = "dock"` in `sections`;
    - `allowedPaths[dock] = DockConfig.exportedKeys.map { [$0] }`, where `exportedKeys` is every `CodingKey`, "Apps
      hidden from Dock previews" included, as the switcher exports `excludedBundleIDs`;
    - `safetyPaths` gains `[dock, "clickActions"]`, `[dock, "keys"]`, `[dock, "runAlongsideOtherTools"]` and
      `[dock, "showWithVoiceOver"]`;
    - the shared privacy keys stay in the `switcher` section. `unionPaths` gains `[switcher, "privateBundleIDs"]`, so
      an import never shrinks the protected list, and `safetyPaths` gains `[switcher, "protectPrivateWindows"]`
      (§4.10).
  - `Backup.swift` exports and imports the `dock` section (0.4 R3-81). M34 checks both, the protected list included.
  - `HostReport.sections(… dock:)`.
  - `EventCategory.dock`.
  - The `module disable` alias `dock` and its help line.
  - `ModuleSwitchRow` text, the `SettingsShell` icon, the General page card strings, `GeneralPageControls` keywords
    and `MenuBarPageControls.dockPresence`.
  - The Safe Mode details text (§4.13).
  - `ModuleContext` and `ModuleContracts.swift:98`, per `H1-SITES.md`.

---

## 4. Behaviour

Every number here is a constant in `DockPreviewPolicy`, `DockGeometry` or `WindowCatalogRules` unless it's named
as a setting. K2–K4 pin each one in a test.

### 4.1 Hover (X-10, X-26, G-11, Y-14)

1. **Show.** The Dock's selection changes to an app item whose app is running. After the **delay** (setting; 0.2 s,
   0–1 s, “Immediately” at 0) the panel shows that app's windows.
2. **Swap.** While the panel is up, the selection moves to another running app. The panel swaps at once, except
   while the pointer is heading into the panel (§4.2).
3. **Nothing to show.** The selection moves to a folder, Trash, a stack, a separator, a minimized-window tile, an
   app that isn't running, or nothing. The panel hides after the grace time (reason `noItem`).
4. **Stale selections.** The Dock's AX selection lags the pointer by a frame or two. A selection older than the last
   `pointerMoved` that left the Dock zone never shows.
5. **The pointer must agree (X2-10).** A selection change shows or swaps only when the pointer is inside the Dock
   zone **and** inside the selected item's **hit band**. The band is the item's frame grown along the Dock by half
   the gap to each neighbour, and stretched across the Dock to the screen edge. At a selection change with no
   monitor installed, the controller reads `NSEvent.mouseLocation` once; that's a single read, not polling.
   - If the test fails, the show stays pending for up to 0.5 s. The pointer monitor is installed, and the test runs
     again on each move and on the next settled frame read. If it still fails after 0.5 s, the monitor is removed.
     K2 tests a selection that arrives with the pointer 2 pt outside the frame before the frame grows: the panel
     shows.
   - **The exception:** VoiceOver is running and “Show previews while VoiceOver is on” is on. The selection alone
     drives the panel then (`DockSelection.byPointer == false`), because the VoiceOver cursor moves it.
   - Keyboard selection of the Dock (⌃F3, Full Keyboard Access) changes the selection without the pointer, so it
     never shows a panel, except under the VoiceOver exception above (M42; G3-9).
6. **Timing rows (Y-14).**
   - A pending show is cancelled when the pointer leaves the Dock zone.
   - A mouse-down on the Dock cancels a pending show.
   - After a dismiss by click, Esc, Hide or Quit, the same item doesn't show again until the selection changes or
     the pointer leaves the Dock zone and comes back (G2-1).
7. **While the switcher is open (X2-15).** Between `switcherOpened` and `switcherClosed`, selection changes never
   show or swap. The first selection change after it closes is handled normally.

**The Dock zone (X-10).** This is the area where the pointer counts as “on the Dock”:

- the `AXList` frame, converted to Cocoa coordinates;
- plus the hovered item's live frame grown by 24 pt on every side, which covers magnification;
- taken as a union over the hover session, so it only grows until the panel hides;
- when the frame can't be read, the last known zone.

### 4.2 Engagement, swap intent, corridor and latch (X-11, X-12, X-25)

- **Swap intent.** A selection change while the panel is up is held for 120 ms when the pointer's last 50 ms of
  motion points into the triangle from the pointer to the panel's two near corners. If the pointer is still heading
  in after 120 ms, the swap waits (X2-23). It's checked again on each `pointerMoved`. It runs when the pointer has
  stopped heading in for 120 ms while outside the panel, and it's dropped when the pointer enters the panel.
  Otherwise it runs at 120 ms. S0-21 checks the numbers.
- **Corridor.** The convex hull of the item frame and the panel's near edge. Inside it, the panel stays.
- **Grace.** Outside the item, the corridor and the panel for **0.25 s** → hide (`left`). A constant, not a setting
  (G-6).
- **Safety net.** Outside the Dock zone and the panel for **1 s** → hide (`safetyNet`), whatever AX says.
- **Lockouts after the header's Hide and Quit.** The panel hides at once. It doesn't show again until the pointer
  moves 8 pt or the selection empties, so the Dock's reflow can't put another app's panel under a still pointer
  (S0-22).
- **Double clicks.** The header ignores clicks for 300 ms after a show or a swap, so a second click can't land on
  the next app's Quit.
- **Dismiss latch (X-12).** A mouse-down outside the panel (including on the Dock item), the Dock's own menu
  opening, or a drag starting sets the latch.
  - The panel hides (`clickOutside`, `itemClicked` or `dockMenu`).
  - The latch holds until the selection leaves that item or the pointer leaves the Dock zone.
  - An open Dock menu is never covered (S0-25, M36).
- **Our own menus (X-25).** While the card's or the header's right-click menu is open, every timer pauses. They
  restart from zero when it closes.
- **Our own actions.** An activation within 1.5 s of our own action (5 s for Quit) is `byUs`. It never dismisses
  with `activation`. The panel hides or updates as §4.4 says, and the reason is that action's.
- **VoiceOver drives the selection (G2-5).** While `byPointer == false` (§4.1 rule 5):
  - swap intent, the corridor, the grace (`left`) and the safety net don't run;
  - the panel hides when the selection moves to another item or empties (`noItem`), on an activation, or on the
    latch;
  - while VoiceOver's focus is in the panel (`voiceOverFocusInPanel(true)`), an empty Dock selection doesn't hide
    it.

### 4.3 Cards (G-17, G-18, G-24, Y-10–Y-12, Y-16, X-29)

- **Size** (setting): Small, Medium or Large, 200, 280 or 360 pt wide. Each card is a fixed 16:10 frame, and the
  thumbnail is letterboxed inside it (Y-12).
- **Layout.** A bottom Dock gets one row; a left or right Dock gets two columns.
  - When the cards don't fit the visible frame, they drop one size (Large → Medium → Small).
  - If they still don't fit, the panel scrolls: horizontally for a bottom Dock, vertically for side Docks, with the
    scroll wheel or trackpad (D2-31). There is no “+N more” card and no hand-off to the switcher (G-12, P-21, X-29).
  - When the window read's budget runs out, the panel shows the windows read so far, then a “More windows…” row that
    reads the rest on demand (§4.8; D2-17, X3-12).
- **Card content.** The thumbnail, or the app icon in text-only mode. The title, or the app name when the title is
  empty. One badge at most.
- **Badges**, in order of precedence: **Minimized** > **Full screen** > **On another Space** > the display name.
  - The display badge is the `NSScreen.localizedName` of the window's screen, shown only with more than one display
    (Y-17).
  - A hidden app shows **Hidden** once, in the header, not on each card (G-17).
- **Header** (§4.4): “1 window” or “3 windows” (`SentenceText.unit`; G-24).
- **No open windows.** An app with no windows shows a small card, “No open windows”. Clicking it activates the
  app (G-18).
- **No windows shown.** When settings hide every window (minimized, hidden or on other Spaces), the card says “No
  windows shown”, with the tooltip “Its windows are minimized, hidden, or on other Spaces.”
  - Both small cards follow the Advanced switch “Show when an app has no open windows” (§4.18). With it off, nothing
    shows.
- **Cards without an AX element** (other-Space windows read from `CGWindowList`, or no window-id match) offer only
  Bring Forward (§4.4).
  - An untitled one shows as “Window on another Space”.
- **AX timeout without Screen Recording.** When the window read times out and there's no Screen Recording to fall
  back on, the panel shows one card: “Windows can’t be read right now”.
- **Our own windows.** Our panels are excluded by window number. Snaptic's Settings window shows as a normal app
  window.
- **Thumbnails** are requested only for cards in view, plus one beyond each edge of the scroll view.
- **One card per window.** Native tabs are filtered as the switcher does today. Two copies of one app follow S0-2's
  result: the panel lists the hovered copy's windows, and the header reads “Safari · 2 instances” when the Dock
  merges copies under one item (Y-16, X-28).

### 4.4 Actions and header (G-16, Y-10, Y-18)

- **Card clicks.** A click raises the window (`WindowManager.focus`). A middle-click closes it.
- **Hover buttons**, top-left: **Close**, **Minimize** and **Enter Full Screen**. Their tooltips are the same
  words, with the key while keys work (§4.5): “Close (⌘W)”, “Minimize (⌘M)”.
- **Card right-click menu** (G-16):
  - Close Window
  - Minimize Window (or Restore Window when minimized)
  - Enter Full Screen (or Exit Full Screen)
  - a separator
  - Hide Safari (or Show Safari)
  - Quit Safari (left out for Finder)
  - While keys work, the items show ⌘W, ⌘M, ⌘H and ⌘Q as key equivalents (G2-1).
- **A card without an AX element** (D2-25) offers only Bring Forward. Middle-click, the hover buttons, the card
  menu's window items, and ⌘W and ⌘M do nothing on it.
- **Header**, on the panel's edge away from the Dock: app icon, name, window count, a **Minimize All** button, and
  **Hide** and **Quit** buttons. Their tooltips are “Minimize All”, “Hide Safari” and “Quit Safari”, with “(⌘H)” and
  “(⌘Q)” while keys work.
  - While the app is hidden, the Hide button, its tooltip and its label read “Show Safari” (G2-1).
  - The header's right-click menu adds **Close All** (Y-10). Finder has no Quit.
  - Clicks and keys on the header itself, or in a gap between cards, act on no window (M23).
- **Quit** uses `NSRunningApplication.terminate()`, never `forceTerminate()`, so unsaved work asks first (M41).
  - Quitting Snaptic itself from its own header goes through the normal quit path (`LaunchStability.markCleanQuit`),
    so the next launch isn't counted as a crash (X-29).
- **After an action:**
  - Raise, Hide and Quit hide the panel (`raised`, `hidApp`, `quitApp`).
  - Close and Minimize update the card in place. When the last card goes, the panel shows the small card from §4.3,
    or hides if that switch is off.
  - A window closed elsewhere disappears from the panel in place (freshness, §2.3).
  - The hovered app quitting hides the panel (`appTerminated`; Y-18).

### 4.5 Keys (X-3, X-14, G-1, Y-2, P-16)

- **Engaged (D2-3, X2-5, X3-5).** The pointer has moved at least 4 pt in total inside the panel within the last
  1.5 s, and it has been inside the panel for at least 250 ms since `panelEntered`. A click in the panel also engages
  it. Neither condition depends on the selection ring, which follows engagement (below).
  - It disengages when the pointer leaves, the panel hides, 1.5 s pass without movement or a click, or a key-down
    arrives that isn't in the table. It engages again only by the same rule. `flagsChanged` (⌘ on its own) never
    disengages it and is never sent to the policy.
  - **Autorepeat** (`kCGKeyboardEventAutorepeat` = 1) of a table key is swallowed and does nothing. Holding ⌘W
    closes one window.
  - **Reflow.** For 300 ms after a card closes or minimizes, table keys are swallowed and do nothing while the
    cards move.
  - **Held keys (X3-4).** After the tap swallows a key-down, it stays enabled until that key's key-up, even if the
    panel hides or disengages meanwhile. Until then it swallows only that key code's repeats and its key-up; every
    other event passes. A 1 s cap, restarted at each repeat, ends the hold if the key-up never comes. Holding ⌘Q over
    the last card quits one app, and nothing reaches the app that comes forward.
- **The table (G2-1).** While engaged, these five keys are always swallowed, whether or not they have a target:
  - ⌘W closes, and ⌘M minimizes (or restores), the window whose card is under the pointer.
  - ⌘H hides the previewed app, or shows it when it's hidden.
  - ⌘Q quits the previewed app, never the frontmost one, and never Finder. Quitting Snaptic's own card goes through
    the normal quit path (§4.4).
  - Esc hides the panel (reason `escape`), with §4.1 rule 6's lockout.
  - A key with no target does nothing: the header, a gap between cards, a card that offers only Bring Forward, or
    ⌘Q on Finder. No handled key ever reaches the frontmost app.
  - Each key does exactly what its menu item does, including §4.2's lockouts and §4.4's after-action rule.
  - No arrows, no Return and never a bare letter, so typing parked on the panel always reaches the active app (M40).
- **The tap.** One active key tap (`DockKeys`), created the first time a panel shows and kept for the life of the
  module.
  - It is enabled only while engaged or while a key it swallowed is still down (X3-4), and never while `switcherSessionActive` is true. The switcher opening hides
    the panel.
  - Breaker: three disables by macOS within 60 s turn keys off until relaunch, with the §4.17 row.
  - The callback runs on the main run loop. It calls `DockKeyRules` with the current snapshot and returns. It does
    no AX and no I/O.
- **Secure input** is read when the panel shows and when it engages. While it's on, or unknown (§4.12), there's no
  selection ring and no key hints, and the tap stays disabled.
- **Keys work** when the setting is on, there's no `Dock.disable.keys`, no tripped breaker and no secure input.
  Only then:
  - **Selection ring.** The card under the pointer shows a 2 pt accent ring exactly while the panel is engaged
    (X3-5). It marks what ⌘W and ⌘M act on. Otherwise no card shows a ring.
  - **Key hints.** The card and header menus show the key equivalents, and the tooltips add the key (§4.4).
    Accessibility labels stay the bare words.
- **S0-20(a)** may replace the tap with a key panel that becomes key without activating Snaptic. The table and
  engagement rule don't change.
- **Setting:** “Keyboard shortcuts in previews” (on; Advanced). Help: “Press ⌘W to close, ⌘M to minimize, ⌘H to
  hide, or ⌘Q to quit what’s under the pointer. Esc dismisses the preview.” `Dock.disable.keys` turns the tap off.

### 4.6 Dismissal (the DockDoor #472 fix)

Grace (0.25 s) and the safety net (1 s) are constants with no setting (G-6). Every hide has one reason:

| Reason | Trigger |
|---|---|
| `left` | Outside the item, corridor and panel for 0.25 s |
| `safetyNet` | Outside the Dock zone and the panel for 1 s |
| `clickOutside`, `itemClicked`, `dockMenu` | The latch (§4.2) |
| `raised`, `hidApp`, `quitApp` | Our own action (§4.4) |
| `escape` | Esc while engaged (§4.5) |
| `appTerminated` | The hovered app quit |
| `activation` | Another app became active, not by us |
| `space`, `display` | Space change; display reconfiguration |
| `lock`, `sleep`, `session` | Lock, display or system sleep, fast user switching |
| `switcherOpened` | The Window Switcher opened |
| `paused`, `stopped` | A pause reason started (§4.17); the module stopped |
| `noItem` | The selection left every running app |

Mission Control, App Exposé and Launchpad hide the panel through `.transient`; we don't detect them (X-16, S0-13).

### 4.7 Placement (Y-5, X-27, X-30)

- **Settled frames.** Placement waits for the item frame to settle: two equal reads one or two display frames
  apart. That keeps the panel off a frame that's still magnifying or still sliding in from auto-hide.
- **Fixed until a swap.** The panel doesn't follow magnification while it's up.
- **Gap.** The panel sits 6 pt off the Dock's at-rest thickness (read when the Dock isn't magnified), with an 8 pt
  margin from the screen's visible edges.
- **Level.** One level, chosen by S0-6, that clears the Dock's name label (X-30). The panel is `.transient`, joins
  all Spaces and is non-activating.
- **Auto-hide.** Nothing keeps the Dock revealed (ground rule 4). If the Dock hides while the pointer is in the
  panel, the panel stays until it's dismissed. Otherwise it hides with the Dock (S0-7, M12).
- **Accessibility settings (G-11, Y-14).**
  - Motion: the panel fades in and out over 0.15 s and never slides, so Reduce Motion needs no special case.
  - Increase Contrast: 1 pt borders on cards and around the panel, and a header separator (D2-31).
  - Reduce Transparency: an opaque panel in `windowBackgroundColor`.
- **Coordinates** follow the `Screens.cocoaRect` rules. The capture scale comes from the screen that holds the
  window, not the Dock's screen (X-27). For a window that no screen holds (minimized, or on a Space of a display
  that's gone), it's the largest `backingScaleFactor` among the current screens (X2-20).

### 4.8 Reading the Dock and windows (X-8, X-15, X-17, X-28, Y-3, Y-8)

**The Dock observer.**

- `DockObserver` runs on its own `ObserverThread`, with a 0.15 s AX timeout per element. Reads use
  multi-attribute calls and coalesce to the latest selection. Main never waits on the Dock (S0-14: never over
  16 ms).
- **Back-off.** Three timeouts in 10 s → wait 1 s before the next read. Reported as `dockSlow` (count only).
- **Liveness (X-17).**
  - KVO on `NSWorkspace.runningApplications` sees the Dock's pid change; `kill(pid, 0)` confirms a pid is gone.
  - Re-attach ladder: 0.1, 0.25, 0.5, 1 and 2 s, then the 30 s health check. Within 2 minutes of login, the ladder
    adds 5 s and 10 s steps (X2-16).
  - Wake, unlock, session-active and a display change (`NSApplication.didChangeScreenParametersNotification`)
    always rebuild the observer, even when the pid is unchanged (D2-4).
  - Each attempt creates a fresh `AXObserver`. The old one is invalidated and its run-loop source removed.
  - **The health check** reads the `AXList` and `NSEvent.mouseLocation` once (D2-4).
    - An invalid element is a silent death.
    - So is a pointer inside the last Dock frame while AX reports a selected child different from the last one
      notified.
    - Either case re-attaches and counts `observer.silentReattach`.
- **Dock not readable.** After the ladder fails, or when the `AXList` can't be found, the module reports state 5
  (§4.17). The 30 s health check keeps running, and a successful read moves it to state 9. The Dock restarting or
  Try Again also re-attaches at once (X2-16).

**Item → app (X-28).** Match in this order:

1. `kAXURLAttribute` against `NSRunningApplication.bundleURL`;
2. the bundle id from that URL's `Info.plist` against `bundleIdentifier`;
3. `AXTitle` against `localizedName`.

`AXIsApplicationRunning` decides whether the item is running.

**The window list (X-8).**

- `WindowManager.windows(for pid:budget:allowUntitled:)` reads one app, on the AX and `CGWindowList` paths, with a
  0.5 s budget. It runs on its own `ObserverThread` (the window-read thread), never on main (D2-16). The result is
  cached for 2 s and marked dirty by the freshness lease.
- When the budget runs out after at least one window was read, the read returns the windows read so far, and the
  panel adds a “More windows…” row that reads the rest on demand (D2-17, X3-12). Windows already loaded stay across
  each refresh, and a refresh reads again only what's still unread. The row stays only while some windows are
  unread. It's the last cell, inside the scroll range, and VoiceOver reaches it.
- A **timeout** is a read that can't read even the first window within the budget. That app is skipped for 30 s and
  shown with titles only from `CGWindowList`, or the §4.3 “can’t be read” card.
- **Inclusion (Y-3)**, in `WindowCatalogRules`:
  - Standard windows and titled dialogs only.
  - Left out: floating panels, system dialogs, notification-style pop-ups, anything under 100 × 100 pt, Finder's
    desktop window, and windows whose id or pid is gone.
  - Each window is checked live again when the panel opens and on each refresh.
  - “Apps hidden from Dock previews” (Advanced) lists apps whose Dock items never show a panel (G2-4).
- **Stage Manager (Y-8, S0-11).** A window in a side strip gets an upright capture of the window itself; else its
  last-seen thumbnail; else the app icon. Never a capture of the strip tile.
- **Before any action**, the window id is resolved again, so a closed or reused id never gets the action.

### 4.9 Capture (X-4, X-5, X-19, X-20, Y-7, P-20)

**Every capture, on either path, needs all of these (X-4):**

- `CGPreflightScreenCaptureAccess()` is true. It's checked before each private-path capture, and once per batch for
  SCK, which enforces consent itself (X2-14). Snaptic never calls the request function on hover.
- That module's **Window thumbnails** setting is on, and the client's lease holds `.thumbnails` (§2.3).
- The window isn't private (§4.10).
- The window's owner pid matches the app being previewed (S0-18).
- The app isn't on the protected list. For a Dock Previews capture, it also isn't on “Apps hidden from Dock
  previews”; the switcher still captures it (G3-3).

**Paths.**

- **SCK** for on-screen windows, as the switcher does today.
- **Private** (`CGSHWCaptureWindowList`, through `SNWindowServer.m`) only for minimized and other-Space windows,
  under §4.12.
  - **Content check (X-5, X2-8).** A capture whose 16 × 16 luma has a standard deviation under 2 is *suspect*. The
    card keeps its last-seen thumbnail or the icon. After three suspects in a row, from at least two different
    windows, the private path runs the probe-window capture again (§4.12 step 4):
    - **The probe passes with the pattern check** (S0-4 recorded that our off-screen window captures): the path
      works and those windows are plain. Suspects from those windows are accepted from then on, and the counter
      resets.
    - **The probe passes on shape only:** that proves nothing about content, so nothing is accepted. Suspects keep
      the last-seen thumbnail or the icon, and the counter resets (X3-9).
    - **The probe fails:** the symbol is `poisoned` (§4.12 step 5).
    - Any capture that isn't suspect resets the counter. `WindowSymbolContract` holds the rule, and K4 tests both
      branches.
  - **Shape.** A result that isn't a `CFArray` of `CGImage`, has a zero width, or has more than 4× the pixels of the
    window's `CGWindowList` bounds at the largest screen `backingScaleFactor` is “impossible” (X3-6) (§4.12 result classes). It's discarded and counted.
- **Last-seen**, then the **app icon**.
- Each entry records its source (`sck`, `private`) and capture time.

**Pacing (X-20, Y-7).**

- Captures start only after the panel has been visible for 150 ms.
- Each window is captured at most once per 30 s unless it's dirty.
- At most 8 captures per second in total. SCK runs up to 4 at once; the private path runs one at a time and is
  scaled down at once to the largest card size × the scale from §4.7.
- `SCShareableContent` is cached for 2 s and shared by both clients.

**Budget (X-19, X-21, P-20).**

- 120 entries and 96 MB, counted as `bytesPerRow × height`. An entry over 16 MB is skipped. `ThumbnailIndex` holds
  these rules; A1a keeps 0.4's 40 entries and 5 minutes, and A2a switches (§2.3 Staging).
- Fresh for 30 s; kept for at most 30 minutes, with a timer at the next expiry (§2.5).
- Pixel buckets: 720 for the Dock; 640 and 2400 for the switcher (§2.3 lookup rule).

**System indicators (Y-7, G2-6).** The footer of the page section that holds Window thumbnails reads: “macOS may
show its screen-recording indicator or a reminder while thumbnails are taken.” If S0-19 finds a per-call alert,
Window thumbnails defaults to **off** for Dock Previews, and its help adds: “Off by default, because macOS shows a
screen recording alert each time Snaptic takes a picture of a window.”

### 4.10 Privacy (Y-1, X-7, P-4, G-4)

- **One rule.** `WindowCatalogRules.privacy` applies the switcher's existing `PIPPrivacy` rules to both modules: the
  protected apps, the private-window markers and the browser-with-empty-title rule.
- **One store, two views (G-4, D2-1, G2-3, P2-9).** “Protect private windows” and the protected apps stay where 0.4
  keeps them: the switcher `Config` fields `protectPrivateWindows` and `privateBundleIDs`
  (`Switcher/Settings.swift:255–256`), in the `SnapticConfig.v1` defaults key.
  - `ModuleHost` loads that store whether or not the switcher runs (`ModuleHost.swift:40`). `WindowServices` reads
    the two fields from it for both modules, and both sheets bind to them, so a change on one shows on the other.
  - **Upgrade:** nothing moves and nothing migrates. **Downgrade:** 0.4.0 reads the same values. H7's downgrade
    worktree checks a custom list and protect off.
  - **Backup:** both fields stay in the `switcher` section. `unionPaths` gains `[switcher, "privateBundleIDs"]`, so an
    import never shrinks the list, and `safetyPaths` gains `[switcher, "protectPrivateWindows"]` (H10).
  - **Restore Defaults** never touches them, on either page or either sheet. `AppSettings.reset()`
    (`Settings.swift:380`) keeps the two fields. Only General › Reset All Settings (`ModuleHost.swift:739`) resets
    them, through a separate `resetPrivacy()` call. `--selftest-controls` checks both on values.
  - Switcher sheet's Restore Defaults message: “Window Switcher settings go back to their defaults. Protect private
    windows and its app list stay as they are, because Dock Previews uses them too.”
  - Dock sheet's: “Advanced settings go back to their defaults. Protect private windows and its app list stay as they
    are, because the Window Switcher uses them too.”
- **Privacy section** (G2-3, G2-4). Both sheets show the two shared rows in a section named Privacy.
  - Footer on the switcher sheet (replaces `SettingsView.swift:113`): “Thumbnails stay in memory and are never saved.
    They’re cleared after 30 minutes, and when your Mac locks or sleeps. These settings also apply to Dock Previews.”
    On the Dock sheet, the last sentence reads “These settings also apply to the Window Switcher.”
  - The list keeps its name, “Never show thumbnails for”. Its help on both sheets: “These apps show their icon and
    name instead of a picture or window title, in the Window Switcher and Dock Previews.”
  - The Dock-only list, “Apps hidden from Dock previews”, sits outside the Privacy section (§4.18).
- **A private card** shows the app icon and “Private window” (or the app name for a protected app). No title, no
  thumbnail, no VoiceOver title and no cache entry. Its label is in §4.16.
- **The cache** refuses private window ids. An entry is dropped when its window turns private.
- **Screen sharing.** The panel sets `sharingType = .none`. S0-24 records whether SCK-based shares still see it.
  If they do, thumbnails of minimized and other-Space windows can appear in a share, and Known limitations and the
  Window thumbnails help say so in those words (M38; X2-19). Pausing while sharing is §9 (0.5.x).

### 4.11 Dock click actions (Q4; G-9, X-13, Y-15, P-26)

- **Pop-up** “When you click the active app in the Dock”: **Do Nothing** (default), **Hide the App**, **Minimize
  Its Windows**. Help: “Hide works like pressing ⌘H. Minimize sends each of its windows to the Dock.” If S0-9 fails,
  Hide the App is dropped.
- **Switch** “Restore all minimized windows” (off). Help: “When all of an app’s windows are minimized, clicking its
  Dock icon brings them all back.”
- **The resolver** (`DockClickRules`, X-13):
  - The app history is stamped with `mach_absolute_time`. “The active app” is the last activation at least 150 ms
    before the mouse-down. Every input below is sampled at mouse-down, before the Dock acts (D2-20).
  - **Ambiguous.** An activation of any other app between 150 ms before the mouse-down and the action makes the
    click ambiguous, and Snaptic does nothing.
  - Mouse-up lands on the same item within 0.5 s of the mouse-down. The item is `DockObserver`'s latest selection,
    checked against the §4.1 hit band. There's never an AX call in the tap callback (X2-17).
  - The app had at least one visible window on the current Space.
  - Hide or Minimize runs 100 ms after mouse-up. Hide is skipped if a window was created in that time: the pid's
    count of on-screen layer-0 windows in `CGWindowListCopyWindowInfo` grew between mouse-up and +100 ms (X2-17).
  - Restore-all needs every window minimized at mouse-down, and it wins over Hide and Minimize.
- **The tap** is listen-only, so a Dock click is never swallowed. It re-checks Accessibility trust on each disable.
  Breaker: three disables within 60 s turn click actions off until relaunch (§4.17). S0-9 records which TCC service
  the tap needs (P-26).
- It pauses with the module (§4.17). The VoiceOver pause doesn't stop it, because clicks still come from the
  pointer.
- `Dock.disable.clickActions` removes the tap at the next start. While running, each mouse-up the resolver would act
  on reads it first (H6, D2-15).
- The README says, next to these settings, that Snaptic never changes the Dock's own preferences (D2-30).

### 4.12 The C-symbol contract (Q6 restated; X-1, X-2, X-24, X-31, P-2, P-8, P-25; X2-1–X2-4, X2-6–X2-8, P2-1)

**Checks for each symbol**, in `WindowSymbolContract` (Kit) and `PrivateWindowAPI` (app). A symbol's state is
`available`, `unavailable` (absent, wrong image or the OS gate only), `disabled` (crash guard or kill switch) or
`poisoned` (a failed probe or bad results) (P2-14). A feature works while every symbol it needs is `available`.

1. **Presence and image (X2-7, P2-13).** `dlsym` finds it, and `dladdr` reports an image from that symbol's Image
   column below. S0-5 fills the column on 15 and 27; an image that differs between them is listed with both. On a
   verified major, an image outside the list means `unavailable`, and diagnostics say `imageMoved`.
2. **OS gate (X2-2, X2-22, P2-16, X3-1).** It applies only to what's new in 0.5: 0.5 never takes away, on any
   macOS, what 0.4 does there. A major is **verified** when S0 has run on it: 15 and 27 in 0.5.0. 14 and 26 stay
   unverified unless STEP0-NOTES records S0-4, S0-5 and S0-17 legs on them before R.
   - **What 0.4 already calls** runs on every major from 14 up, verified or not, newer ones included, under the rest
     of the contract (presence and image, prototype, probe, result classes, crash guard, kill switch): the raise
     trio, the symbolic-hotkey pair, the Spaces symbols, `_AXUIElementGetWindow` and the layout pair. On a major
     that isn't verified they're never marked verified, so their crash marker is written on every call.
   - **`CGSHWCaptureWindowList`**, and any symbol whose use is new in 0.5, runs only on a verified major. Elsewhere
     it's `unavailable`, and its fallback runs.
   - **The ⌘⇥ give-back** is exempt from the gate, the image check and poisoning. It turns on only ids from
     Snaptic's own saved list, under its own crash guard (step 6). H6 holds on every major.
   - `IsSecureEventInputEnabled` is exempt from the gate and the image check. It's public API, and it's called in
     Safe Mode too.
3. **Pinned prototype.** One Swift `@convention(c)` type per symbol, checked against S0-5's notes.
4. **Probe (X2-6, P2-15, D2-13, X3-3)**, lazily: each symbol is probed just before its first real use, off main on
   one serial queue. The probe window is created and ordered on main when a probe needs it. A caller that arrives
   before that symbol's probe finishes gets the fallback for that call, except the capture below.
   - **The capture probe** runs just before the first private capture that passes every §4.9 gate: Window
     thumbnails on, Screen Recording granted, a `.thumbnails` lease, not Safe Mode, no kill switch, a verified major.
     That capture waits for the probe. Until then diagnostics show `hwCapture: notProbed`, and a launch with
     thumbnails off, without Screen Recording or in Safe Mode never runs it (M1, M33).
   - **Cache.** A pass is kept per OS build in `Windows.probedBuild.<symbol>`, so a later launch on the same build
     skips that probe. A failure is never cached; step 5 probes it again.
   - **The probe window.** A dedicated 64 × 64 borderless window with normal collection behaviour (not
     `canJoinAllSpaces`), `sharingType = .none` and `.ignoresCycle`. It's ordered in at a frame outside every screen,
     drawn with a two-colour pattern, and ordered out after the probes. S0-5 records that it never appears in Mission
     Control.
   - `SLSMainConnectionID` returns nonzero, and equals `CGSMainConnectionID` when both exist.
   - `SLSCopySpacesForWindows` on the probe window returns a `CFArray` of at least one `CFNumber`.
   - `_AXUIElementGetWindow` on the probe window's AX element, sent from the probe queue, returns its
     `windowNumber`. It waits for Accessibility; until then, window ids use the fallback.
   - `CGSHWCaptureWindowList` on the probe window: if S0-4 records that an off-screen window of our own captures,
     the image must match the pattern (16 × 16 greyscale, mean absolute difference under 10%). Otherwise the probe
     checks the result's shape only, and a shape-only pass never lets §4.9's content check accept a suspect (X3-9).
   - `KBGetLayoutType` returns one of the three known layouts, or `'????'` (`kKeyboardUnknown`), which is no answer
     and reads as ANSI (X3-6).
   - The symbolic-hotkey pair is checked for presence here. At the first take, the setter's result is read back
     with `IsSymbolicHotKeyEnabled`. If it isn't off, Snaptic turns it back on and marks the take `poisoned` for the
     process.
   - The raise symbols are checked for presence only (a probe would move windows).
   - A probe with no answer (step 5) isn't a failure. The symbol stays on its fallback and is probed again at its
     next use, at most once a minute (X3-6). Only an impossible result fails a probe.
   - A failed probe makes that symbol `poisoned` (step 5). B1b drives every probe's failure branch with an injected
     result.
5. **Result classes (X2-1).** `WindowSymbolContract` sorts each result into one of two classes:
   - **No answer** is normal and never counts: AX errors (`cannotComplete`, `invalidUIElement`, `apiDisabled`,
     `notImplemented`, `attributeUnsupported`); NULL or an empty array for a window that has no Space or no longer
     exists; NULL from a capture of a window that closed; any raise error; `'????'` from `KBGetLayoutType` (X3-6). The caller falls back for that one window.
   - **Impossible** counts: a result no working symbol returns for any input (the table's last column).
   - **Answers an app controls never count.** The target app answers `_AXUIElementGetWindow`
     (`WindowManager.swift:376–380`). Its id is checked against the window server's owner list, and a mismatch drops
     that one id, as today.
   - Two impossible results in a row poison the symbol. A poisoned symbol is probed again after 10 minutes, and a
     pass clears it. A second poisoning lasts until Snaptic quits, and shows the §4.17 row with that feature's name.
6. **Crash guard (X2-4, P2-1, X2-3).** Kit `CrashGuard` holds the rules. The app's `Windows/InflightMarkers.swift`
   writes the files.
   - **One marker per symbol**, a file `~/Library/Application Support/Snaptic/inflight/<symbol>` holding the OS
     build, in a directory created 0700. A counter per symbol writes the file synchronously when it goes 0→1 and
     unlinks it when it goes 1→0. One `os_unfair_lock` per symbol covers the count together with the `open` and
     `write(2)`, or with the `unlink`, never the private call, so an unlink and a write on one symbol can't
     interleave (X3-8, P3-6). The file opens with `O_WRONLY|O_CREAT|O_TRUNC|O_NOFOLLOW|O_CLOEXEC`. A completed
     `write(2)` survives a process crash. A failed write takes the fallback for that call and counts
     `markerWriteFailed`. `UserDefaults` holds only `Windows.disabledBuild.<symbol>`,
     `Windows.verifiedBuild.<symbol>`, `Windows.probedBuild.<symbol>` (step 4) and `Windows.pendingGiveBack` (below).
   - **At launch**, step 3b (H3) runs `CrashGuard.atLaunch`. A marker from this OS build counts only if the previous
     run didn't reach `LaunchStability.markCleanQuit()` (`AppDelegate.swift:134`); then it sets that symbol's
     disabled build and logs EventLog `.safety` (X3-8). Every marker is removed either way.
   - **Verified.** After 20 successes on this OS build (counted in memory, written once), `verifiedBuild` stops the
     marker writes for the read-only symbols only. The capture, the raise trio and the setter keep their marker on
     every call. They're rare: at most 8 a second while a panel shows, and one per click.
   - **The ⌘⇥ give-back** has its own marker (`inflight/symbolicHotKeys.giveBack`) and its own disabled build,
     apart from the take (X3-2):
     - When it's disabled on this build, launch step 4 moves the saved list from `SnapticDisabledSystemHotkeys`
       (`PrivateAPIs.swift:146`) to `Windows.pendingGiveBack` and removes the old key.
     - `apply(…)`, `restore()` and `recoverFromPreviousRun()` never write `Windows.pendingGiveBack`, so the next
       start's `apply` can't overwrite it. `apply` treats the ids in it as Snaptic's own, never as the user's.
     - While the give-back is disabled, the switcher doesn't take ⌘⇥.
     - Try Again, or the first launch on a new OS build, gives back at once: marker first, then the call. The key is
       removed only after the give-back returns.
     - Any saved list is removed only after a give-back returns (today `PrivateAPIs.swift:155` removes it first).
     - The Window Switcher page's row and its strings are in §4.17 (G3-2). S0-5 records whether a turned-off
       symbolic hotkey survives logout, and the row's text follows that result.
   - The signal handler (`AppDelegate.swift:221`) calls the setter through pointers resolved at launch. It writes no
     marker and takes no lock.
   - Each feature has its own stopped row with **Try Again** (§4.17), which clears that feature's disabled builds.
   - Kit tests: two overlapping calls to different symbols, and a crash in either leaves only its own marker. M35
     uses a DEBUG `SNAPTIC_DEBUG_TRAP_IN=<symbol>`, which traps between the marker write and the call.

**Symbols and fallbacks.**

| Symbol | Used for (`WindowFeature`) | Kill switch | Fallback |
|---|---|---|---|
| `CGSHWCaptureWindowList` | Thumbnails of minimized windows and windows on other Spaces (`hwCapture`) | `Windows.disable.hwCapture` | Last-seen, then the icon |
| `_AXUIElementGetWindow` | AX window ↔ window id (`axWindowID`) | `Windows.disable.axWindowID` | Match by title and frame; cards without a match offer only Bring Forward |
| `GetProcessForPID`, `_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo` | Raising a window (`raise`) | `Windows.disable.raise` | `kAXRaiseAction` plus activate, with `yieldActivation` first when needed (S0-27). Another Space then only activates the app (Known limitation; P-25) |
| `SLSMainConnectionID` / `CGSMainConnectionID`, `SLSCopySpacesForWindows` / `CGSCopySpacesForWindows` | Spaces (`spaces`) | `Windows.disable.spaces` | The other-Space list is dropped (P-19) |
| `SLS`/`CGSSetSymbolicHotKeyEnabled`, `SLS`/`CGSIsSymbolicHotKeyEnabled` | The switcher's ⌘⇥ takeover (`symbolicHotKeys`) | `Windows.disable.symbolicHotKeys` | macOS keeps ⌘⇥. Giving it back always runs, except under its own crash guard (H6) |
| `KBGetLayoutType`, `LMGetKbdType` | Key layout for the switcher (`layoutType`) | `Windows.disable.layoutType` | The ANSI layout |
| `IsSecureEventInputEnabled` | Secure input | none (public API, exempt from the gate and the image check; called in Safe Mode) | **Unknown**: the switcher doesn't take ⌘⇥, so macOS keeps it. ⌥⇥ and the Dock keys tap keep working, and nothing is cancelled (X2-2) |

**Images and result rules (X2-1, X2-7, P2-13, P2-14).** S0-5 confirms the Image column on 15 and 27.

| Symbol | Image | Read-only | Impossible result (counts) |
|---|---|---|---|
| `CGSHWCaptureWindowList` | SkyLight | no | not a `CFArray` of `CGImage`; an image of zero width, or over 4× the pixels of the window's bounds at the largest screen scale (§4.9) |
| `_AXUIElementGetWindow` | HIServices | yes | none: the app answers it |
| `GetProcessForPID` | HIServices | no (raise) | none: raise errors are no answer |
| `_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo` | SkyLight | no | none: raise errors are no answer |
| `SLS`/`CGSMainConnectionID` | SkyLight | yes | 0 |
| `SLS`/`CGSCopySpacesForWindows` | SkyLight | yes | not a `CFArray`, or holds something other than a `CFNumber` |
| `SLS`/`CGSIsSymbolicHotKeyEnabled` | SkyLight | yes | none: it returns a `Bool` (X3-6) |
| `SLS`/`CGSSetSymbolicHotKeyEnabled` | SkyLight | no | a nonzero `CGError`, or the read-back disagrees |
| `KBGetLayoutType`, `LMGetKbdType` | HIToolbox | yes | a value other than `ANSI`, `ISO `, `JIS ` or `'????'` (X3-6) |

**Secure input (X2-2).** `watchSecureInput` keeps two states apart. “On” gives ⌘⇥ back and cancels the switcher, as
today. “Unknown” (the symbol is missing) only gives ⌘⇥ back. The Dock keys tap treats both as “keys don’t work”
(§4.5).

**Selftest lines (P-8, P2-7, P2-18, D2-12).**

- `selftest-launch: windows <symbol> available|unavailable|disabled|poisoned [SLS|CGS]`, one line per symbol in the
  table except `IsSecureEventInputEnabled`, from Kit `WindowSymbolContract.launchLines`. One more line reports
  `selftest-launch: windows secureInput available|unknown`.
- These lines check presence, image and prototype only. The selftest makes no AX or TCC call (lint rule 9) and no
  capture; the probes in step 4 run in the app.
- `SNAPTIC_SELFTEST_EXPECT_WINDOWS_API`: unset, the lines are only reported. CI on `macos-15` sets `=available` on
  the debug and app selftest steps (`build.yml:244–245`, `:299–300`), and the signed-app steps (`:507–508`,
  `:1174–1175`) set it too, because the shipped binary is the one that must find the symbols. With it set, any other
  state fails the run.
- The DEBUG-only `PrivateWindowAPI.forcePoisonForSelfTest()` runs right after the window lines, as the icons poison
  run does (`SelfTestLaunch.swift:79–84`). It poisons every symbol, calls none, and prints
  `selftest-launch: windows poison path ok|failed`: `ok` when every symbol then reports `poisoned` and none
  `available`. Nothing after it uses a window symbol. Only the debug step (`build.yml:244–245`) runs it.
- Each feature's fallback is a Kit table, `WindowSymbolContract.fallback(for:)`, tested in
  `WindowSymbolContractTests`. The fallbacks themselves run in M6, M16 and the S0 harness.
- `--selftest-launch` on 27.2 needs Snaptic quit, so it's an owner check at R (0.4 R3-10). B1b records a standalone
  27.2 probe from S0-5's harness in STEP0-NOTES.

### 4.13 Safe Mode (P-11, X-2; G2-2, D2-2, P2-2, D2-10, X2-18)

One model, used in §4.17, §4.19, §4.21 and M31/M33: **in Safe Mode the module starts paused.**

- `SafeMode.skipped` gains “Dock previews” and “Thumbnails of minimized windows and windows on other Spaces”.
- **Dock Previews.** In Safe Mode, `start()` sets `.degraded("Paused in Safe Mode")`, as Hidden Icons does
  (`IconsModule.swift:164–171`), and its state is row 3 (§4.17). It registers the three `dock` verbs and returns. It
  creates no observer, tap, panel, capture or lease. This differs from Hidden Icons on purpose: a status verb that
  answers “Unknown command” for a module that's on misleads a script.
  - `dock status` answers `state=paused reason=safeMode` (exit 0).
  - `dock pause` and `dock resume` refuse with “Dock Previews is paused in Safe Mode.” (exit 5).
- **The switcher** still runs (`SafeMode.stillRuns`), on SCK captures only, and raises with `kAXRaiseAction` plus
  activate.
  - The capture and the raise trio aren't called. Each falls back as §4.12's table says, so minimized windows show
    the last-seen thumbnail or the icon.
  - The other §4.12 symbols run as in 0.4: Spaces, the AX window id, the layout pair (so ISO keyboards keep the key
    above Tab), secure input, and the symbolic-hotkey pair unless its crash guard has disabled it.
  - Diagnostics report `hwCapture: safeMode`, and 0 private captures. The capture probe doesn't run (§4.12 step 4;
    X3-3).

### 4.14 Permissions (G-7, P-26)

- `requiredPermissions` is `[.accessibility]`, plus `.screenRecording` while the module's Window thumbnails setting is
  on. Kit's `DockConfig.requiredPermissions` computes it from the config, and the module returns that
  (`ConfigDockTests.testRequiredPermissions`).
- Onboarding's “needed” list loops over every enabled module's `requiredPermissions`, so it lists Dock Previews.
- **Turning the module on** without Accessibility shows the Accessibility guide once, with “Dock Previews needs it to
  read the Dock.”
- **Accessibility's purpose** on the Permissions page becomes “Lets Snaptic see its shortcuts, list and switch
  windows, read display keys, and read the Dock.” (G2-6). The page builds one purpose per permission plus “Needed
  by …” (`PermissionsPage.swift:182`), so there's no Dock-only purpose string.
- **Screen Recording** is asked for only from onboarding or the page's permission row, never on hover. Its existing
  purpose already covers pictures of windows. Without it, previews show titles (§4.17's added row).
- **The Permissions page** lists Dock Previews under Accessibility, and under Screen Recording while its Window
  thumbnails setting is on.
- **Input Monitoring, if S0-9 needs it (G2-6).** S0-9 records the TCC service the listen-only mouse tap needs
  (Accessibility or Input Monitoring). If it's Input Monitoring, before A5:
  - K1 adds `Permission.inputMonitoring` (`KitModules.swift:22`), with its pane name on 15 and 27 as S0-9 records;
  - its purpose reads “Lets Snaptic notice Dock clicks for Dock click actions.”;
  - an added row, shown while a click action or Restore all minimized windows is on: “Dock click actions need
    \(paneName(.inputMonitoring)).” [Open Privacy Settings…];
  - H7's downgrade check decodes a backup that names the new case.

### 4.15 Other Dock preview tools (Q5; G-10, X-33)

- `KnownDockTools` has the `KnownMenuBarHiders` shape: exact bundle ids from S0-15, Snaptic's own excluded. It's
  read from `NSWorkspace.runningApplications` on launch and terminate notifications, not polled.
- **The pause covers** previews, keys and Dock click actions.
- **Naming.** The Settings row and the Snaptic menu name the tool (“Paused while DockDoor runs”). With more than one
  known tool running, the row names the first in `KnownDockTools` order (G2-10). The CLI, logs and diagnostics never
  name it; they carry the enum case `otherTool` (X-33).
- **Pause reasons** are `safeMode`, `otherTool`, `voiceOver` and `command`. A kill switch is a state (row 1), not a
  pause reason. When several apply, `DockPageRules` picks the first in the order of §4.17's rows: Safe Mode, then
  other tool, then VoiceOver, then command.
- **Advanced pop-up** “When another app shows Dock previews”: **Pause Dock Previews** (default) or **Run Both
  Anyway**. While Run Both Anyway is chosen, a footnote reads “Both apps show a preview when you point at the Dock,
  and the previews may cover each other.” (G2-10, D2-29).
- Row 6's [Advanced…] opens the sheet at that pop-up, through the row's anchor.
- **Guide**: “Other Dock preview apps” and “Switching from DockDoor”. The second is a behaviour-only table (D1),
  including every S0-32 default that differs from Snaptic's. It ends: “Quit DockDoor, or remove it from Login Items,
  then turn on Dock Previews. Snaptic doesn’t import DockDoor’s settings.”

### 4.16 Accessibility and VoiceOver (G-11, X-32)

- **Paused while VoiceOver runs**, by default. Dock click actions keep working (§4.11), and row 7 says so (§4.17).
  The Advanced switch “Show previews while VoiceOver is on” (off) turns previews back on. Help: “Previews appear as
  VoiceOver moves through the Dock.”
- **With that switch on:**
  - the selection drives the panel, by §4.2's VoiceOver bullet (G2-5);
  - each show posts an announcement such as “Safari, 3 windows”, filtered by §4.10 (a private window adds to the
    count but never a title);
  - the panel is an accessibility group labelled “Safari windows”;
  - `@AccessibilityFocusState` on the panel feeds `voiceOverFocusInPanel` to `DockPreviewPolicy`;
  - S0-16 records how VoiceOver reaches the panel (the VO cursor, or a jump key). §7 M22 checks it.
- **Card labels**: “\(title), \(app)”, plus “, minimized”, “, hidden”, “, on another Space” or “, full screen”. Each
  label equals the card's tooltip.
- **Cards with no title (G2-15).**
  - A private card, or a card of a protected app: label and tooltip “Private window, Safari” (“Private window,
    1Password”). The title is never a fallback.
  - The No open windows card: “No open windows, Safari”.
  - The No windows shown card: “No windows shown, Safari”, with §4.3's tooltip as its accessibility help.
  - The header Hide button while the app is hidden: label and tooltip “Show Safari” (§4.4).
- **Known limitation** (G3-9): “Dock Previews works with the pointer, or with VoiceOver when “Show previews while
  VoiceOver is on” is on. With the keyboard alone, use the Window Switcher.”

### 4.17 States (G-2; G2-2, G2-5, G2-6, G2-9, X2-16, X2-24, D2-9)

`DockPageRules` takes the inputs and returns one state. The first row that applies wins. The menu rows reuse the
Settings strings (sentence case), as Hidden Icons does (G2-9).

| # | State | Settings status row | Snaptic menu (status item) | `dock status` |
|---|---|---|---|---|
| 1 | Kill switch | `DefaultsLockRow` | — (no section) | `Unknown command` (exit 2) |
| 2 | Off | `FeatureHighlights` | — | `Unknown command` (exit 2) |
| 3 | Safe Mode (§4.13) | “Paused in Safe Mode” | “Paused in Safe Mode” | `state=paused reason=safeMode` |
| 4 | No Accessibility | “Dock Previews needs \(paneName(.accessibility)) to read the Dock.” [Open Privacy Settings…] | “Needs Permission”, then §4.19 item 2 | `state=needsPermission` |
| 5 | Dock not readable | “Dock Previews can’t read the Dock. It tries again when the Dock restarts.” [Try Again] | “Can’t read the Dock” | `state=unavailable reason=dockUnreadable` |
| 6 | Other tool | “Paused while DockDoor runs” [Advanced…] | “Paused while DockDoor runs” | `state=paused reason=otherTool` |
| 7 | VoiceOver | “Paused while VoiceOver is on” [Advanced…]. With a Dock click action or Restore all minimized windows on: “Previews are paused while VoiceOver is on. Dock click actions still work.” [Advanced…] | “Paused while VoiceOver is on” | `state=paused reason=voiceOver` |
| 8 | Paused by command | “Paused until 3:45 PM” [Resume] | “Paused until 3:45 PM”, then **Resume Dock Previews** | `state=paused reason=command until=<ISO>` |
| 9 | Working | none | none, then **Pause Dock Previews for 1 Hour** | `state=on` |

- **Starting.** Between `start()` and the first attach, when rows 1–4 don't apply and row 5 doesn't yet, the row
  reads “Starting…”. There's no menu status item, and `dock status` gives `state=starting`.
- **Around the row (G2-6, G3-6).** Rows 1 and 2 show their row and the footer's (?) only. Starting and rows 3 to 9
  show the controls and the full footer (§4.18), so a paused module can still be set up.
- **Row 7's [Advanced…]** opens the sheet at “Show previews while VoiceOver is on”. Row 6's opens it at “When another
  app shows Dock previews” (§4.15).
- **Row 5** first shows after the login ladder ends (§4.8). Its attention mark waits until the row has held for
  2 minutes (X2-16).

**Added rows** show below the status row and never replace it:

- No Screen Recording while Window thumbnails is on: “Window thumbnails need Screen Recording. Until then, previews
  show window titles.” [Open Privacy Settings…]
- A tripped breaker (§4.5, §4.11): “Dock click actions stopped because macOS turned them off 3 times. Relaunch
  Snaptic to use them again.” [Relaunch Snaptic]. The keys breaker has the same row with “Keyboard shortcuts in
  previews”.
- **A crash-guard stop (§4.12; X2-24, D2-9).** One row per stopped feature, in §4.12's table order: “\(feature)
  stopped after a problem in macOS. Snaptic tries again after a macOS update.” [Try Again]. `\(feature)` is the
  `WindowFeature` display name:

  | `WindowFeature` | Display name | Shown on |
  |---|---|---|
  | `hwCapture` | Thumbnails of minimized windows and windows on other Spaces | Both pages |
  | `axWindowID` | Matching cards to their windows | Both pages |
  | `raise` | Bringing windows forward from other Spaces | Both pages |
  | `spaces` | Showing windows on other Spaces | Both pages |
  | `symbolicHotKeys` | Using ⌘⇥ for the Window Switcher | Window Switcher page only |
  | `layoutType` | Reading the keyboard layout | Window Switcher page only |

- **A second poisoning (§4.12 step 5)**: “\(feature) stopped because macOS answered in a way Snaptic didn’t expect.
  Quit and reopen Snaptic to try again.” No button.
- **A held command pause (§4.21; G3-1).** Under Starting, row 4 or row 5, while a command pause is held: “Paused
  until 3:45 PM” [Resume]. Resume clears it, as `dock resume` does. When the row's own problem clears, row 8 takes
  over.
- **⌘⇥ not given back (§4.12 step 6; X3-2, G3-2).** On the Window Switcher page only, whatever the switcher's state,
  while `Windows.pendingGiveBack` holds a list. While the switcher is off it shows above the page's highlights. The
  text follows S0-5's logout result:
  - ⌘⇥ comes back at logout: “⌘⇥ may not switch apps until you log out, because Snaptic couldn’t turn it back on
    after a problem in macOS.” [Try Again]
  - It doesn't: “⌘⇥ doesn’t switch apps, because Snaptic couldn’t turn it back on after a problem in macOS.”
    [Try Again]
  - Help: “This also affects ⌘⇧⇥ and ⌘ with the key above Tab.”
  - Try Again clears only the give-back's disabled build (`symbolicHotKeys.giveBack`) and gives ⌘⇥ back at once.
    The `symbolicHotKeys` row's Try Again clears only the take's.
- **Kill switches (G2-6).** `Dock.disable.clickActions` disables the Dock click actions section and shows
  `DefaultsLockRow(key:)` under it. `Dock.disable.keys` does the same for “Keyboard shortcuts in previews”.

The menu-bar attention mark shows only for row 4, for row 5 (after 2 minutes) and for a tripped breaker. It's the
tab mark, so it needs the module's tab: the default presence is `.inSnapticMenu` (H1; G2-7). With no tab bar (Dock
Previews is the only module in the Snaptic menu), there's no mark, and the row-4 status item is the signal (G3-4).

`dock status` formats, value sets and the verb × state replies are in §4.21. Never a name or a title.

**Kill switches and their effect (G-20)**, for the README and guide rows:

| Switch | Effect |
|---|---|
| `Modules.disable.dockPreviews` | Dock Previews stays off. Takes effect at the next launch. |
| `Dock.disable.clickActions` | Dock clicks are left entirely to the Dock. |
| `Dock.disable.keys` | Keys pass through to the active app; the pointer still works in previews. |
| `Windows.disable.<name>` | That symbol's fallback from §4.12, plus “Affects the Window Switcher and Dock Previews.” |

### 4.18 Settings page (G-5, G-6, G-4, Y-13; G2-4, G2-6, G2-8, D2-24, D2-29)

- **Summary**: “See an app’s windows when you point at it in the Dock.” Onboarding uses the same string (§4.20).
- **Highlights** (shown while off):
  - “Point at an app in the Dock” / “Its windows appear next to the Dock, including minimized and hidden ones.”
  - “Click a window to bring it forward” / “Or close, minimize, or quit from the preview.”
  - “Works without Screen Recording” / “Without it, previews show window titles instead of pictures.”
- **Status row** (§4.17), then two sections.
- **Previews** section:
  1. **Show previews after**: a slider from 0 to 1 s in 0.1 s steps, with tick marks. Help: “How long you point at
     an app before its windows appear.” The value reads “0.1 s” to “1 s” (at most one decimal, then `L(" s")`; P3-7), or “Immediately”
     at 0.
  2. **Card size**: Small / Medium / Large.
  3. **Window thumbnails** (on; the switcher's label, G-4). Help: “Pictures of your windows. Off: titles only, and no
     Screen Recording needed.” Section footer: §4.9's system-indicator sentence.
  4. **Include minimized and hidden windows** (on). Help: “Lists windows that are minimized or belong to hidden
     apps.”
  5. **Windows on other Spaces** (on). Help: “Off: only windows on the current Space are shown.”
- **Dock click actions** section (G2-8). Footer: “Snaptic only watches Dock clicks. The Dock still handles every
  click as usual.”
  6. **When you click the active app in the Dock** (§4.11).
  7. **Restore all minimized windows** (§4.11).
- **Footer** (D2-29, G3-6): **Restore Defaults…** on the leading edge and **Advanced…** on the trailing edge, both
  only while the module is on (Starting and rows 3 to 9); (?) on the trailing edge always. (?) links to README
  `#dock-previews`.
- **Restore Defaults confirmation**: “Restore Dock Previews settings to their defaults?” / “Preview, Dock click, and
  Advanced settings go back to their defaults. Dock Previews stays on. Protect private windows and its app list stay
  as they are, because the Window Switcher uses them too.”
- **Search**: `SearchSpec("Use Dock Previews", keywords: ["dockdoor", "hyperdock", "dock preview", "hover",
  "window preview", "thumbnail"])`, and one spec per control.

**Advanced sheet** (“Dock Previews Advanced Settings”):

- **Sort windows by**: Recently Used / Minimized and Hidden Last / Title (Y-13).
- **Keyboard shortcuts in previews** (§4.5).
- **Apps with no open windows** (on; the switcher's label, G2-8). Help: “Pointing at the app shows a small card
  instead of nothing.”
- **When another app shows Dock previews** (§4.15).
- **Show previews while VoiceOver is on** (§4.16).
- **Privacy** section: Protect private windows and “Never show thumbnails for”, the shared rows (§4.10).
- **Apps hidden from Dock previews** (G2-4, D2-24), outside the Privacy section: an app list. Help: “Pointing at
  these apps in the Dock shows nothing. The Window Switcher isn’t affected.”
- **Diagnostics lock rows** for `Dock.disable.*` and `Windows.disable.*` only. Row 1 already shows
  `Modules.disable.dockPreviews`, and the sheet can't open then (G2-6).
- The sheet's own **Restore Defaults** (Advanced settings only, as in 0.4), built with
  `RestoreDefaults(title:question:message:button:destructive:)` as `IconsPage.swift:216` uses it. Question:
  “Restore Dock Previews’ Advanced settings to their defaults?” Its message is §4.10's Dock sheet text (G3-10).

**Separate settings per module (G-4).** The switcher keeps its own Window thumbnails, size and sort settings. Only
privacy is shared. The switcher's Window thumbnails detail becomes: “Off: every shortcut shows app icons, with no
live preview. The Window Switcher then never asks for Screen Recording.”

### 4.19 Snaptic menu (G-3)

- The section, in order (G2-9):
  1. the status item from §4.17's menu column, in rows 3 to 8 only, and also “Paused until 3:45 PM” while a
     command pause is held under Starting, row 4 or row 5 (G3-1);
  2. “Open \(paneName(.accessibility)) Settings…” in row 4 only;
  3. “Pause Dock Previews for 1 Hour” in row 9 only, or “Resume Dock Previews” in row 8 and while a command pause
     is held under Starting, row 4 or row 5 (G3-1). Neither shows in rows 3, 6 and 7;
  4. “Dock Previews Settings…”.
- **Presence.** The default presence is `.inSnapticMenu` (H1; G2-7), so the section and the attention mark are
  there without a change on the Menu Bar page. With no tab bar, there's no mark (§4.17; G3-4). Turning Dock Previews on later never changes its presence. The Menu
  Bar page's help for Dock Previews: “Previews show when you point at the Dock. Change them in Settings.” (D2-29).
- Short title “Dock”; accessibility label “Dock Previews”; tooltip “Dock Previews (⌘n)”, where n is the tab's
  number.
- **Only module.** When Dock Previews is the only module on, `.inSnapticMenu` is stored, because `.ownIcon` isn't
  allowed.
- **Everything hidden.** With every module hidden and no shortcuts, the warning reads “No Snaptic icon is shown.
  Open Snaptic again to come back to Settings.”

### 4.20 Onboarding and upgrade (Q7; G-8)

- **Onboarding row** (G2-11): “Dock Previews” / “See an app’s windows when you point at it in the Dock.” Off. This
  is the page summary, through `ModuleSwitchRow.summary`.
- **Choosing Dock Previews** in onboarding lists Accessibility and Screen Recording in the “needed” list, through
  the `requiredPermissions` loop (§4.14; A8's Kit check; D2-30).
- **Welcome text**: “A window switcher, display controls, Keep Awake, hidden menu bar icons, and Dock previews. Turn
  on only what you want; everything else stays off.” M29 checks that five module rows fit at the default text size.
- **New card** (upgraders only, through the `dockCard.v1` marker): “New: Dock Previews” / “See an app’s windows when
  you point at it in the Dock, and click one to bring it forward.” [Turn On Dock Previews] [Not Now]. Turn On turns
  the module on and opens its page.
- **GUIDE “Upgrading”**: 0.5 adds Dock Previews (off); the switcher gets thumbnails for minimized and other-Space
  windows when macOS allows; the thumbnail cache now lasts up to 30 minutes in memory; downgrading to 0.4 keeps
  every setting, including the protected apps (§4.10). The 0.3.2 Upgrading entry gains “You’ll see Dock Previews as
  a new, off module.” (D2-30).

### 4.21 CLI (G-14, P-17, X-33; G2-2, G2-12, P2-2, P2-25, D2-27)

- **Verbs**, registered whenever the module is on (while starting and in rows 3 to 9), and never while it's off or
  killed (rows 1 and 2), which give the house `Unknown command` answer (exit 2):
  - `snaptic dock status [--json]`: “State, pause reason and cache counts (never names)”.
  - `snaptic dock pause [duration]`: “Pause Dock Previews and its Dock click actions for a while (1 h if no time is
    given)”.
  - `snaptic dock resume`: “Resume Dock Previews and its Dock click actions”.
- **Duration (P2-25).** `AwakeDurationGrammar.durationSeconds` only (`30m`, `2h`, `1h30m`, `90` = minutes), from
  1 minute to 24 h. `forever`, `idle`, `until …`, `0` and anything over 24 h are usage errors. A command pause isn't
  saved, so a relaunch resumes.
- **A pause never shortens one already running (G2-12).** The end becomes the later of the current end and now +
  duration, and the reply gives that end.
- **Replies** (times are ISO UTC, as Awake's are):
  - pause: “Dock Previews is paused until 2026-11-12T20:45:00Z.” (exit 0).
  - resume: “Dock Previews is on again.”, “Dock Previews’ pause is cleared.” (a pause held under Starting, row 4
    or row 5; G3-1) or “Dock Previews isn’t paused.” (exit 0).
  - usage error: `Usage error. Run “snaptic help dock”.` (exit 2), as Awake's (`AwakeAutomation.swift:135`).
- **Refusals** (`ControlExit.unavailable`, exit 5), for `pause` and `resume` only. `status` always answers, exit 0.
  - Row 3: “Dock Previews is paused in Safe Mode.”
  - Row 4 (pause only): “Dock Previews needs \(paneName(.accessibility)). Open Snaptic Settings › Permissions.”
  - Row 6: “Dock Previews is paused while another Dock preview app runs. Choose Run Both Anyway in Dock Previews’
    Advanced settings to use both.”
  - Row 7: “Dock Previews is paused while VoiceOver is on.”
- **Verb × state (P2-25, D2-27).** `DockCommandGrammar` holds it as data, and `DockControlsTests` checks each cell.

  | Row | `status` | `pause` | `resume` |
  |---|---|---|---|
  | 1, 2 | exit 2 (not registered) | exit 2 | exit 2 |
  | Starting | `state=starting` | as row 9 | “pause is cleared” when one is held, else “isn’t paused” (exit 0) |
  | 3 | `state=paused reason=safeMode` | exit 5 | exit 5 |
  | 4 | `state=needsPermission` | exit 5 | “pause is cleared” when one is held, else “isn’t paused” (exit 0) |
  | 5 | `state=unavailable reason=dockUnreadable` | works as in row 9 (G2-12) | “pause is cleared” when one is held, else “isn’t paused” (exit 0) |
  | 6 | `state=paused reason=otherTool` | exit 5 | exit 5 |
  | 7 | `state=paused reason=voiceOver` | exit 5 | exit 5 |
  | 8 | `state=paused reason=command until=<ISO>` | exit 0, the later end | exit 0, then the next row that applies |
  | 9 | `state=on` | exit 0 | “isn’t paused” (exit 0) |

  A command pause holds until it ends or `resume` clears it, whatever row shows meanwhile (G3-1). While one is held
  under Starting, row 4 or row 5, the page and the menu show “Paused until 3:45 PM” with Resume (§4.17, §4.19).
  `status` gives `until=<ISO>` whenever a pause is held, and `reason` stays the row's. `resume` there clears it with
  “Dock Previews’ pause is cleared.” Rows 3, 6 and 7 come before row 8, so a command pause can't be set or cleared
  under them.
- **`status` format (G2-12).**
  - Plain: `state=<…> reason=<…|-> until=<ISO|-> thumbnails=<…> clickActions=<…> keys=<…> cacheEntries=<n>
    cacheBytes=<n>`.
  - `--json`: the same keys in the same order, then `observerAttached` and the §4.22 live counters. An absent value
    is `null`.
  - `state`: `on` | `starting` | `paused` | `needsPermission` | `unavailable`. `reason`: `safeMode` | `otherTool` |
    `voiceOver` | `command` | `dockUnreadable`.
  - `thumbnails`: `on` | `off` | `noPermission`. `clickActions` and `keys`: `on` | `off` | `paused` | `stopped`
    (breaker) | `disabled` (kill switch). Each is the effective value, so `clickActions` stays `on` in row 7.

### 4.22 Diagnostics and live counters (P-15)

- **Live counters** (P3-2): one Kit `DockLive` holds `observer`, `clickTap`, `keys`, `panel` and `timers`, beside
  `WindowServices.liveLeases`. A6a adds it and its selftest line. A3 (observer), A4a (panel, timers) and A5
  (clickTap, keys) increment and decrement it.
- **Selftest**: `selftest-launch: dock live observer=0 clickTap=0 keys=0 panel=0 timers=0 leases=0`. Every value is 0
  in the selftest, because no module starts there.
- **EventLog**: `dock.started`, `dock.stopped`, pause changes, breaker trips and crash-guard stops, with enum values
  only.
- **Diagnostics** (counts, booleans and enums): observer attached, re-attach and silent re-attach counts, `dockSlow`,
  the last hover-to-show latency, the selection count and the last `DockItemKind`, cache entries and bytes, captures
  by path, `captures.rejected`, the pause reason, each symbol's state (§4.12, with `imageMoved`), and dismiss
  reasons by count.
- **`WindowServices`**: lease counts by client and condition, and `freshnessObservers` (the live count of freshness
  observers, 0 while no lease holds `.freshness(pid)`).

### 4.23 Window Switcher changes (Y-19)

- Uses `WindowServices` (H2). With Dock Previews off it registers exactly what it does today (M1, M32).
- These are the switcher's only visible changes (X2-21), and the release notes and GUIDE Upgrading list them:
  - minimized and other-Space windows get thumbnails from the private path where §4.9 allows; else last-seen with
    the badge; else the app icon, as today;
  - from A2a, the cache persists between openings (30 minutes), and opens with cached thumbnails that refresh in
    place. A1a keeps 0.4's 40 entries and 5 minutes (D2-22);
  - the Privacy footer and list help (§4.10), and the Window thumbnails detail (§4.18).
- Turning the switcher's Window thumbnails off drops its `.thumbnails` lease condition, which purges its entries at
  once, as in 0.4 (§2.3; X2-11).
- Shared rules: inclusion (§4.8), privacy (§4.10), the “Minimized and Hidden Last” sort, and the display badge.
- §9 records what's left for later: Vim keys, mouse follows focus, the swipe trigger and more sort orders.

### 4.24 Canonical strings (G2-13)

- Every quoted UI string in §4 is in `DockPageControls`, `DockAdvancedSheetControls`, `DockMenuRowsControls`,
  `DockCommandGrammar` or the views. `DockControlsTests.testEveryCanonicalStringIsInTheSources` reads a list of them
  from the test file and checks that each appears whole, as one literal, in `Sources/` (P-23, P3-1). Interpolations
  are listed in their source form (`\(feature)`), and app-name examples as templates.
  - K5 creates the test with its own strings. A4a, A4b, A6b and A7 append theirs as they land them; A7 covers
    §4.17 to §4.19. A8 appends §4.20's.
  - README, GUIDE and site strings aren't in this test: D1 and D3 check them.
  - A change to a string changes this plan in the same commit.
- Quoted UI strings in this plan are written exactly as they appear in `L()`, with curly apostrophes and quotes
  (DS §4; lint03). Code in backticks keeps straight quotes.

---

## 5. S0: the gate before the code that needs it (macOS 27.2 host and a macOS 15 VM)

A throwaway harness under `/tmp/s0-dock/` (never committed), plus `docs/design/0.5/STEP0-NOTES.md` (committed).
Every row has a decided answer if it fails (P2-20), so a failure changes scope, not the schedule. STEP0-NOTES
records which answer was taken, and §R4 lists it.

| # | Check | Pass | If it fails | Blocker |
|---|---|---|---|---|
| S0-1 | Dock AX tree: `AXList`, item subroles, `kAXURLAttribute`, frames, on 27.2 and 15 | Recorded; app items resolvable | Dock Previews doesn't ship in 0.5.0; the switcher upgrades ship alone. The owner decides from STEP0-NOTES | yes |
| S0-2 | `kAXSelectedChildrenChangedNotification` on hover: bottom, left and right; magnification; auto-hide; two copies of one app (Y-16); an app run from App Translocation (D2-21) | Fires within 50 ms; resolvable to a pid; the two-copies and translocated behaviour recorded for §4.3 and §4.8 | As S0-1 | yes |
| S0-3 | `killall Dock` ×10; sleep and wake; lock and unlock; fast user switching; a display change (arrangement and resolution) (D2-4). Record which `NSWorkspace` notifications arrive (X-17) | Re-attaches within 2 s every time, through the §4.8 ladder and KVO; after the display change, previews work within 2 s without a pid change | The 30 s health check (§4.8) is the backstop. Known limitations names the event that needs it | yes |
| S0-4 | `CGSHWCaptureWindowList` on our own patterned window, on screen and off screen, then on minimized, other-Space, hidden and full-screen windows: signature, size and scale, p50 and p95 time, peak memory under 150 MB over 100 calls on a 5K display, no growth over 1,000 calls. Without Screen Recording: result recorded, never used (X-4, X-19). The signature is the mean absolute difference of a 16 × 16 greyscale downsample against the drawn pattern (P2-20) | Signature under 10 % of full scale; the off-screen result recorded for the §4.12 probe | No private capture. Minimized and other-Space cards use last-seen, then the icon | yes |
| S0-5 | `dlsym`, `dladdr` and each §4.12 probe for every symbol, including the CGS fallbacks and `KBGetLayoutType`, on 27.2 and 15. The probe window in Mission Control. Whether a turned-off symbolic hotkey survives logout (X2-3) | Every symbol found in its §4.12 image on both OSes; the probe window never shows in Mission Control; the logout result recorded for §4.12 step 6 | A symbol missing on one OS is `unavailable` there, with its §4.12 fallback. If the probe window shows, the probes that need it become presence-only | yes |
| S0-6 | Panel level over the Dock, over a full-screen app's Dock, on all Spaces, without taking focus, and clear of the Dock's name label (X-30) | One level that works everywhere | A level per context (Dock, full-screen Dock), chosen at show. If none clears a full-screen app's Dock, no previews over full screen (Known limitation), and M14 is dropped | yes |
| S0-7 | Auto-hide Dock with `autohide-delay` 0, the modifier at 0 and 0.15 s, large magnification. Frames at rest and magnified (Y-5) | Records whether the Dock hides and the selection clears; the settled-frame rule holds | With auto-hide, show only after the Dock's frame has been unchanged for 0.1 s. The 1 s safety net covers a selection that doesn't clear | yes |
| S0-8 | 10 min idle with the harness attached, then 50 raises through the harness's copy of `bringToFront` (D2-6) | The display sleeps; `pmset -g assertions` shows nothing from it; `ioreg -c IOHIDSystem \| grep HIDIdleTime` keeps growing from the last raise | If the raise records reset idle time, the raise trio isn't used and its fallback runs (§4.12), decided before B1b. Any other failure is a bug fixed before A3 | yes |
| S0-9 | Listen-only mouse tap: 100 clicks plus 100 clicks under a 50 ms load every 100 ms; Dock activation order against our hide; Secure Event Input; reopen behaviour of Safari, Terminal and Finder; the TCC service (P-26) | Zero wrong-app hides; no flicker over one frame; the activation order recorded for K3's resolver | Hide the App is dropped from §4.11. A tap that needs Input Monitoring follows §4.14 | no |
| S0-10 | What AX, `CGWindowList` and SCK return for minimized, hidden, other-Space and full-screen windows; the odd-app set (Electron, Java, Catalyst, Finder's desktop window, Chrome full screen, PWAs, iOS apps, Calculator and Photos, Sidecar as a display) (D2-21); recapture after wake; tab windows of Ghostty, Finder and Terminal | Every window class has a recorded source, for `WindowCatalogRules` | A class with no source isn't listed (Known limitation) | yes |
| S0-11 | Stage Manager on, with two stages | Records hover, frames and capture; decides §4.8's rule (Y-8) | §4.8's rule as written: the window's own capture, else last-seen, else the icon | no |
| S0-12 | Dock on a secondary display; mixed scale factors; a display arranged above | Frames convert to the right screen | Must pass. A failure is a bug fixed before K2 | yes |
| S0-13 | Mission Control, App Exposé, Launchpad and Spotlight while hovering; Stage Manager with two stages; a click on a full-screen app's icon (X-16) | `.transient` hides the panel in each, and it's gone or correct within 1 s after they close (D2-21) | The 1 s safety net and the `activation` and `space` hides cover it. Known limitations lists what's left | yes |
| S0-14 | Hover 20 apps in 2 s; an app that stalls AX for 5 s; Dock read p50, p95 and max during Mission Control, App Exposé, a launch bounce and magnification (D2-16) | Dock reads never block main over 16 ms | Must pass. A failure is a bug fixed before A3 | yes |
| S0-15 | Bundle ids of DockDoor, HyperDock and other Dock preview tools | Recorded in `KnownDockTools` | A tool that isn't listed isn't detected, and both run (§4.15) | no |
| S0-16 | The VoiceOver cursor through the Dock; how VoiceOver reaches the panel; announcements | Recorded for §4.16 | Previews stay paused under VoiceOver by default (§4.16). Known limitations say what VoiceOver can reach | no |
| S0-17 | Each §4.12 probe run 1,000× (X-1) | Same result every time; no effect on window order, Spaces or symbolic hotkeys | A probe with a side effect becomes presence-only, like raise. A probe whose result varies leaves that symbol `unavailable`, with its fallback. A capture failure follows S0-4 | yes |
| S0-18 | Without Screen Recording: the owner pid from `CGWindowListCopyWindowInfo(.optionIncludingWindow)` for minimized and other-Space windows (X-4) | Owner pid present | Without Screen Recording, windows found only in `CGWindowList` (minimized, other Space) are dropped. AX-listed windows stay | yes |
| S0-19 | The capture indicator, the "bypass the private window picker" reminder, Remote Desktop alerts, and tccd CPU over 50 hovers, on both paths (X-20, Y-7) | No alert per call; which path is quieter is recorded | Window thumbnails defaults off for Dock Previews (§4.9). A quieter path is preferred (contingencies below) | yes |
| S0-20 | Keys: (a) a non-activating panel that can become key gets keys without activating Snaptic, and focus returns; (b) the Dock keys tap and the switcher's tap both installed: ⌥⇥ then arrows reach the switcher; (c) revoke Accessibility with the keys tap enabled (X-14) | (a) recorded; (b) arrows reach the switcher; (c) no freeze over 30 s | (b) The Dock keys tap is never enabled while the switcher's tap is installed. If arrows still don't reach the switcher, Keys ships off. (c) Keys is removed from 0.5.0 | yes |
| S0-21 | 20 diagonal moves from an icon to the panel's far card, magnification on and off (X-11) | The swap-intent rule keeps the original app in 20 of 20 | The §4.2 numbers (50 ms, 120 ms) are tuned from the recorded paths, and K3's table follows | no |
| S0-22 | Quit an unpinned app by script while the pointer rests on its icon; record the reflow (X-11) | The §4.2 lockout covers it | The lockout distance grows to cover the recorded reflow | no |
| S0-23 | Per-pid window read for 1, 10, 50 and 100-window apps, with and without Screen Recording (X-8, X-29) | p95 under 150 ms for 10 windows; untitled other-Space windows listed; the p95 recorded for A3 | Show the `CGWindowList` list at once (titles, or the app name), then fill in AX rows within the 0.5 s budget | yes |
| S0-24 | A `sharingType = .none` panel in an SCK-based share (QuickTime, a browser meeting), on 15 and 27.2 (X-7) | Recorded; Known limitations follow | Known limitations say so; pausing while shared is 0.5.x (§9) | no |
| S0-25 | Panel up: right-click an icon, long-press, click the frontmost app, drag a file onto an icon; record the Dock's menu notifications (X-12) | The Dock menu is never covered; the panel doesn't come back for the same item | A right mouse-down, or a 0.5 s press on an item, hides and latches for that item. Known limitation if the Dock's menu notification never arrives | yes |
| S0-26 | The five freshness notifications for Safari, Chrome, an Electron app, Finder and Terminal; registration cost (X-9) | Each delivered within 0.5 s; cost recorded | While the panel is up, a 1 s tick re-reads the hovered app. Nothing runs while it's hidden | yes |
| S0-27 | Fallback raise (`kAXRaiseAction` plus activate) from the non-activating panel (X-31) | Raises 10 of 10, or with `yieldActivation` first | Another Space only activates the app (Known limitation; P-25) | no |
| S0-28 | Pointer monitor cost while the panel is up, with a 1 kHz mouse (X-10) | Under 2 % of one core; nothing installed while hidden | The monitor handles at most one move per display frame, and the cost is recorded | no |
| S0-29 | 27.2: event posting refused, or Accessibility revoked, while `HotkeyTap` and the `DockKeys` tap are on. Does `SLPSPostEventRecordTo` trigger "prohibited from synthesizing events"? (Y-4) | Input keeps flowing; the tap is dropped; the raise result recorded | "Input keeps flowing; the tap is dropped" must pass. If `SLPSPostEventRecordTo` triggers the alert, the raise skips it on 27 (front process, then `kAXRaiseAction`) | yes |
| S0-30 | 26.3+ and 27.2: the first click on a card in the non-activating panel (Y-4) | Acts on the first click | `acceptsFirstMouse` on the card view. If it still takes two clicks, Known limitation | yes |
| S0-31 | 8 h soak: sleep and wake, a light/dark switch, a display change, another app's screen share, full screen in and out, an app hung across sleep; re-attach and hover-to-show counters (Y-4) | Previews work at the end; counters recorded | Must pass. A failure is a bug fixed before R | yes |
| S0-32 | DockDoor's defaults read from its Settings UI, run as a black box (G-19) | Recorded against §1.1 | §1.1 is corrected. Every default that differs from Snaptic's goes to the guide's "Switching from DockDoor" table (D1; D2-30, G3-8) | no |

**Gates (P-12, P2-19, D2-8).** Each row is done before the item that needs it:

| Item | Rows done first |
|---|---|
| K1 | S0-15 |
| K2 | S0-1, S0-2, S0-12 |
| K3 | S0-2, S0-7, S0-9, S0-13, S0-16, S0-21, S0-22, S0-25 |
| K4 | S0-10, S0-11, S0-18, S0-23 |
| B1b | S0-4, S0-5, S0-8, S0-17 |
| A1b | S0-26 |
| A2a | S0-19, S0-24 |
| A2b | S0-4, S0-5, S0-17 |
| A3 | S0-3, S0-8, S0-14, S0-23 |
| A4a | S0-6, S0-28, S0-30 |
| A4b | S0-27 |
| A5 | S0-9, S0-20, S0-29 |
| D1 | S0-32 |
| R | S0-31 |

Rows 1, 2, 4, 5, 10 and 12 run first, because they can change the architecture. If no macOS 15 VM is available, the
15 leg of each row becomes an owner check before R, and STEP0-NOTES says so. Legs on 14 and 26 are optional: S0-4,
S0-5 and S0-17 run there only if a Mac is at hand, and without them those majors stay unverified (§4.12 step 2,
P2-16): 0.4's symbols still run there, and only the private capture waits (X3-1). M4 and M16 each get one owner leg
on macOS 14 or 26 before R.

**Contingencies that change scope:**

- S0-1 or S0-2 fails on either OS: Dock Previews doesn't ship in 0.5.0, and the switcher upgrades ship alone. The
  owner decides from STEP0-NOTES.
- S0-20(a) passes: the key panel replaces the keys tap (§4.5).
- S0-19 finds one path quieter (no indicator, prompt or alert): that path is preferred for both modules, within the
  0.4 rules (D2-23). A per-call alert on both paths turns Window thumbnails off by default for Dock Previews.
- S0-9 finds that the click tap needs Input Monitoring: §4.14's contingency applies.
- Every other failure takes its row's **If it fails** answer.

---

## 6. Work items (P-12, P-13; P2-3–P2-6, P2-21, D2-7, D2-8)

**Every item:**

- its new files' `stubs.tsv` rows in the commit that creates them;
- `scripts/lint.sh --strict` clean, and `swift build` and `swift test` green;
- one or more commits, each ending with the `Co-Authored-By` line;
- Kit items add Linux-safe tests only. Logic that needs a unit test lives in Kit, because `SnapticKitTests` is the
  only test target (P2-3). App items also run `--selftest-launch` and `--selftest-controls` locally, with Snaptic
  quit only when the owner says so;
- an item starts only when every item in its **Needs** column is done, and the §5 gate rows for it have results;
- a done-when names only checks that the item and the items it needs can run. Until A7 builds the page, A4b and A5
  set Dock settings for their checks by importing a backup (A6a adds the `dock` section).

**Order.** The Needs column is the rule. One order that satisfies it: S0 → K1 → K4 → B1a → A1a → B1b → A1b → A2a →
A2b → K2 → K3 → K5 → A6a → A3 → A4a → A4b → A5 → A6b → A7 → A8 → A9 → D1 → D2 → D3 → R. K2, K3 and K5 can run any
time after K1 and their §5 gate rows.

**Critical path (P2-21):** S0 → K1 → K4 → B1a → A1a → A1b → A2a → A4a → A4b → A7 → A9 → D1 → R. A6a → A3, B1b and K3
join it at A4a; A5, A6b and A2b join at A7. K3 (L) has slack only while K4 → A2a runs.

| ID | Size | Needs | Work | Done when |
|---|---|---|---|---|
| **S0** | M | — | §5 harness and STEP0-NOTES | Every row except S0-31 has a result on 27.2, and on 15 or marked as an owner check; S0-31 runs at R (P3-4). Each gate row is done before its item (§5 gates). Any **If it fails** answer taken is in STEP0-NOTES |
| **K1** | M | S0-15 | `ModuleID.dockPreviews`; `H1-SITES.md` (H1, including the onboarding `requiredPermissions` line); the three non-switch sites (H1); the inert module shell; `NewModuleCard`; `DockConfig` (sanitize, defaults, backup allowlist); `DockFeature` and the `KillSwitches` doc comment; `KnownDockTools`; `EventCategory.dock`; `SentenceText.unit` and `properNames`; the shared privacy paths in `KitBackup` (§4.10); pinned tests (H7); lint rows (H8) | `H1-SITES.md` gives every hit a disposition. §6.1's K1 tests pass. The downgrade result is in `H1-SITES.md`. The H8 K1 rows land |
| **K4** | M–L | K1 | `WindowCatalogRules` (`CatalogWindow`, inclusion, privacy, recency merge, sorts, badges, freshness) and `WindowLeaseLedger` | §6.1's K4 tests pass. The switcher's inclusion cases are moved here from the app, not copied |
| **B1a** | S–M | K1 (the L14 and L20 rows) | Split `Switcher/PrivateAPIs.swift` into `Windows/PrivateWindowAPI.swift` and `Switcher/SystemHotkeys.swift`; update callers (H3); `git mv` `WindowManager` and `ThumbnailStore` to `Windows/` | A move only, with no behaviour change. M1 passes, and ⌘⇥ takeover still works (M4, first sentence). Rule 11, L2 and `stubs.tsv` are updated |
| **A1a** | M | B1a, K4 | `WindowServices` with the switcher as its only client; `FocusTracker` moves in; the AX timeout and purge observers move in; both modules read the privacy fields from the switcher `Config` (§4.10) | M1 and M4's first sentence pass. The `selftest-launch: windows leases 0` line prints (A6a folds it into `dock live`). `WindowLeaseLedgerTests` pass. The store keeps 0.4's 40 entries and 5 minutes (D2-22) |
| **B1b** | M | B1a, A1a | `WindowSymbolContract`, probes, result classes, Kit `CrashGuard`, `Windows/InflightMarkers.swift`, the give-back guard, typed kill switches read at each use, `SNWindowServer.m`, selftest lines and the CI expect variable | The §4.12 selftest lines print, and the poison path prints `ok`. CI sets the expect variable on the four steps of §4.12. §6.1's `WindowSymbolContractTests` and `CrashGuardTests` pass. A standalone 27.2 probe is in STEP0-NOTES. M4 passes in full on 27.2 and 15; its 14-or-26 leg is at R |
| **A1b** | M | A1a | Second-client semantics: Kit `ThumbnailIndex` (client tags, per-client generation, prune, invalidate, purge, stamps); `ThumbnailStore` keeps only images keyed by the index; `.freshness(pid)`; every `ThumbnailStore` call site passes a client (`H1-SITES.md`) | §6.1's `ThumbnailIndexTests` (client cases) pass. `ThumbnailStore` holds no bookkeeping of its own. `ThumbnailIndex.swift` has its `stubs.tsv` row |
| **A2a** | M | A1b | `WindowCapture`: SCK, last-seen, the cap of 4, pacing, the byte budget in `ThumbnailIndex`, the privacy rule, the purge triggers; the switcher's limits switch to 120 entries, 96 MB and 30 minutes | §6.1's `ThumbnailIndexTests` budget cases pass. M5 passes on the last-seen path. With the switcher alone, revoking Screen Recording purges, then shows text, with no prompt. The privacy note is rewritten (§2.6) |
| **A2b** | M | A2a, B1b | The `CGSHWCaptureWindowList` path behind B1b: the content check, scaling, the Safe Mode rule; the switcher shows minimized and other-Space thumbnails; the switcher page's stopped row with Try Again | M5 and M6 pass. M35 passes on the switcher page, where the step after Try Again is "the next switcher open captures". Safe Mode makes no private capture, the probe included |
| **K2** | M | K1; S0-1, 2, 12 | `DockGeometry` | §6.1's K2 tests pass |
| **K3** | L | K1; S0-2, 7, 9, 13, 16, 21, 22, 25 | `DockPreviewPolicy`, `DockClickRules`, `DockKeyRules` and `DockPageRules` | §6.1's K3 tests pass. No `Date()` in any of the four files (grep) |
| **K5** | M | K1 | Controls tables, `DockCommandGrammar`, `MenuLayout` | §6.1's K5 tests pass. `L15_PENDING` holds the three Dock tables |
| **A6a** | S | K1, A1a | The real module, still drawing nothing: stores, Backup, Safe Mode, kill switches, the Kit `DockLive` counters (§4.22) | The `selftest-launch: dock live` line prints all zeros, and `DockLiveTests` pass. M34 passes. In Safe Mode, read through a DEBUG state hook (G3-5), the state is `.degraded("Paused in Safe Mode")`, and diagnostics show the observer not attached, 0 leases and 0 captures. The verbs are checked at A9 (P3-2) |
| **A3** | M | A6a | `DockObserver` and `DockReader` on `ObserverThread`: liveness, budgets, item → app; `WindowManager.windows(for pid:budget:allowUntitled:)` (§4.8) | In a DEBUG build with the module on and no panel yet: diagnostics count selections and show the last `DockItemKind` for a bottom, left and right Dock; `killall Dock` ×10 gives `observer attached` and a re-attach count of 10; a 5 s AX stall in one app keeps main under 16 ms; M21 passes; `windows(for:)` meets S0-23's p95 for 10 windows |
| **A4a** | L | A3, A2a, B1b, K2, K3 | `DockPreviewController`, panel and view: placement, cards, layout, dismissal | M2, M3, M7–M15, M19, M32, M36, M39 and M45 pass |
| **A4b** | L | A4a | Actions, header, menus, VoiceOver, accessibility settings | M16–M18, M20, M41, M46 and M48 pass. M22 passes from “With the switch on” (its “paused by default” half is A6b's). M38's share result is in STEP0-NOTES for D1 |
| **A5** | M | A4a, K3 | `DockKeys` and `DockClickTap` | M23–M25, M37, M40 and M42 pass. M26 passes up to “no freeze over 30 s”; its row half is A7's |
| **A6b** | M | A4a, K5 | Pauses (other tool, VoiceOver, command), diagnostics, EventLog | With DockDoor running, `dock status` (a DEBUG hook until A9) reports `otherTool`, and no preview shows. The diagnostics half of M33 passes. M49 passes. M22's “paused by default” half passes. M50 runs at R |
| **A7** | L | A4b, A5, A6b, A2b, K5 | Settings page, Advanced, Permissions rows, Menu Bar page, Snaptic menu section, sidebar | `testEveryCanonicalStringIsInTheSources` passes with the strings of K5 and A4a to A7 (§4.24). `L15_PENDING` is empty. M27, M28, M33, M35 (Dock page) and M47 pass. M26's row half passes |
| **A8** | S | A7 | Onboarding row, welcome text, New card, `dockCard.v1` | M29, M30 and M44 pass. `ConfigDockTests.testRequiredPermissions` passes (D2-30). §4.20's strings are appended to `testEveryCanonicalStringIsInTheSources` and pass. `IconsControlsTests.swift:196–197` is updated (H7; P3-9) |
| **A9** | S–M | A7, K5 | `DockCLI` and `dockCases` in `--selftest-controls` | `dockCases` pass: in Safe Mode the verbs are registered, `status` gives `state=paused reason=safeMode`, and `pause` and `resume` exit 5 (P3-2); `status`; the `status --json` keys; `pause`, `pause 30m`, a later end that extends; `resume`; `resume` while not paused; each exit-5 refusal through its DEBUG hook; the §4.21 verb × state table. M31 and M43 pass |
| **D1** | M | A9 | README and GUIDE: the Dock Previews section (G-13: one paragraph, five bullets with the keys, a permissions sentence, links to the guide and Switching from DockDoor); the GUIDE's Switching from DockDoor table (behaviour only, with every S0-32 default that differs; G3-8); switcher changes; Known limitations; kill switches; Upgrading; the CLI table; the H9 rows | `lint.sh --strict` README rules pass. Every H9 README and GUIDE row is done. The GUIDE has the Switching from DockDoor section and table, and the README links to it. If M38 recorded thumbnails in a share, Known limitations says so. The README and GUIDE strings this plan quotes match it word for word (P3-1) |
| **D2** | S | D1 | `THIRD_PARTY_NOTICES.md` (DockDoor design credit, GPL-3.0, no code); `RELEASE-NOTES-0.5.0.md`, which lists the switcher's new cache limits; version 0.5.0 (500) | The `build.yml` version check passes against `docs/design/0.5/RELEASE-NOTES-0.5.0.md` (P-22). There is no `docs/design/0.5.0/` directory (D2-28) |
| **D3** | S | D1 | Site: the H9 SITE rows | The site builds, and both rows read as H9 says, word for word (P3-1) |
| **R** | — | all | Code review; manual checks on 27.2 and 15; owner checks, including M4 and M16 on 14 or 26; the S0-31 soak; PR | Every Blocker check passes. S0-31 passes. The owner checks are done, M4 and M16's 14-or-26 leg included. The PR is open with CI green |

About two releases' worth of 0.4 work: four L items (K3, A4a, A4b, A7) and about a dozen M.

### 6.1 K test lists (the authority; P2-4, D2-7, D2-19)

These lists replace r1 pressure Appendix B. A K item is done when its list passes.

**K1** (`ConfigDockTests`, plus the pinned files of H7):

- `testIDOrderAndRawValue`, `testAllowedContainsFallbackForEveryID`, `testSanitizeOwnIconFallsBackToInSnapticMenu`.
- `testFreshDefaultsDockOffInSnapticMenu`: off, `presence == .inSnapticMenu` (H7).
- `testDockCardGoesToUpgradersOnce`, `testDockCardSkipsFreshInstallsAcrossLaunches`,
  `testDockCardReachesZeroOneUpgraders`, `testSetEnabledClearsDockCard`.
- `testIconsNeedExternalDisplayIgnoresDockHidden`, `testIconsNeedExternalDisplayCountsDockInMenu`.
- `testDockConfigDefaults`, `testSanitizeClampsDelay` (0…1; NaN → 0.2; ±∞ clamped).
- `testLossyEnumsFallBack`, `testEmptyObjectDecodesToDefaults`, `testRoundTrip`,
  `testFieldNamesAvoidTheSensitiveFragments`, `testBackupAllowlistRoundTrip`, `testDockExportedKeysAreEveryCodingKey`,
  `testDockBackupSafetyPathsListedFirst`.
- `testA05ModulesFileDecodesWithUnknownValues`. Unknown module ids are already pinned by
  `ConfigModulesTests.testUnknownModulesSurviveARoundTrip` (`:80`); there's no new test for them.
- `ConfigModulesTests`: presence is `.inSnapticMenu` on fresh defaults and after `resetMenu()` (G2-7).
- `testEventCategoryDockExported`.
- `testRequiredPermissions`: `DockConfig.requiredPermissions` is `[.accessibility]`, plus `.screenRecording` while
  Window thumbnails is on (§4.14; checked again at A8).
- `KnownDockToolsTests`: ids unique, exact match only, Snaptic's own id excluded.
- `SettingsShellRulesTests`: 9 roots, group order, `dock.…` resolves through the alias, bare `dock` doesn't.
- `KitModulesTests` (`SentenceText`):
  - `properNames.contains("Dock Previews")` and `.contains("Dock")`;
  - `inSentence("Dock Previews settings")` is unchanged, and `inSentence("Dock click actions") == "Dock click
    actions"` (D2-29);
  - `SentenceText.unit(1, "window", "windows") == "1 window"` and `unit(3, "window", "windows") == "3 windows"`
    (P3-7).
- `KitBackupTests` (D2-1): an import never shrinks the switcher's `privateBundleIDs` (union); its
  `protectPrivateWindows` is a safety path; a 0.4 backup imports with the protected apps intact.

**K2** (`DockGeometryTests`):

- “More windows…” is the last cell and inside the scroll range (X3-12).
- Edge from the settled item frame for bottom, left and right, including a Dock on a secondary screen with negative
  x and a screen arranged above.
- AX → Cocoa round trip (`DockGeometry` owns the conversion).
- Placement centred on the item, clamped with an 8 pt margin and a 6 pt gap, at each screen edge.
- The Dock zone and the corridor hull.
- The hit band (X2-10): a pointer 2 pt outside the resting frame, and over a magnified icon before its frame grows,
  counts as on the item.
- Magnified frames: the panel doesn't move.
- Grid: one row for a bottom Dock, two columns for a side Dock.
- Cards that don't fit drop one size (Large → Medium → Small), then the panel scrolls: horizontally for a bottom
  Dock, vertically for a side Dock. There is no "+N more".
- A fixed 16:10 card with the thumbnail letterboxed, checked for very wide and very tall windows.
- RTL mirroring.
- Fuzz over 10,000 cases: the panel is inside the visible frame, never overlaps the item, and every card is
  reachable by scrolling.

**K3** (`DockPreviewPolicyTests`, `DockClickRulesTests`, `DockKeyRulesTests`, `DockPageRulesTests`):

- Delay 0.2 s; a new selection restarts it; delay 0 shows at once; no delay while shown (swap).
- Swap intent: S0-21's 20 diagonals as a table. A stale selection never shows. A held swap is checked again on each
  `pointerMoved` and runs once the pointer stops heading in (X2-23).
- Corridor; grace 0.25 s (0.24 keeps, 0.25 hides); re-entry inside grace cancels the hide.
- Safety net 1 s. A magnified icon above the resting frame doesn't trip it; leaving the union for 1 s does (X-10).
- The latch: `mouseDownOutside`, `mouseDownOnItem`, `dragStarted`. A mouse-down on the Dock cancels a pending show
  and resets the timer (Y-14).
- Our own menus pause the timers, and closing restarts them. The Dock's menu hides the panel with `dockMenu` and
  sets the latch (X3-11).
- Every `DockDismissReason` of §2.4, `escape` included, one to one, and nothing for Mission Control (`.transient`).
- Auto-hide: S0-7's recorded order.
- Races (X-11): a diagonal crossing; a reflow under a still pointer; a click within the lockout; hover → leave →
  hover in one tick; a swap during hide; `refresh` after hide.
- A windowless app swaps to its small card and never keeps the previous app's panel (Y-11).
- `switcherOpened` hides with `switcherOpened`; nothing shows or swaps until `switcherClosed` (X2-15).
- `pauseChanged(reason)` hides with `paused`.
- VoiceOver (G2-5): with `byPointer == false`, the corridor, grace and safety net don't run; the selection moving or
  emptying hides with `noItem`; `voiceOverFocusInPanel(true)` keeps the panel up while the selection is empty.
- Card clicks: left raises, middle closes. A card without an AX element offers only raise.
- `appTerminated(pid)` for the hovered app hides with `appTerminated`.
- Generation tokens: a stale `fired(token)` is ignored.
- `DockClickRules` (§4.11): the activation-history resolver table; one case per mouse-down rule (Y-15); state
  sampled at mouse-down; an activation in the 150 ms before mouse-down makes the click ambiguous, and nothing
  happens (D2-20).
- `DockKeyRules` (§4.5; D2-3, X2-5):
  - drift under 4 pt passes ⌘W through;
  - a held ⌘W (autorepeat for 1 s) closes one window;
  - 4 pt of movement and 250 ms inside the panel, then ⌘Q, quits the previewed app; 4 pt within the first 249 ms,
    then ⌘Q, passes through; after 1.5 s still, a 1 pt drift, then ⌘Q, passes through; 'a', then ⌘Q, passes
    through (X3-5);
  - a swallowed key's repeats and key-up are swallowed until release, even after the panel hides, with the 1 s cap
    restarting at each repeat; holding ⌘Q over the last card quits one app and nothing reaches the next app; holding
    ⌘W for 3 s closes one window (X3-4); table keys do nothing for 300 ms after a reflow; Esc hides
    with `escape`; ⌘Q on Finder and a key with no target are swallowed and do nothing;
  - secure input on or unknown never engages; never engaged while the switcher is active.
- `DockPageRules`: the 9 rows of §4.17 plus Starting; the first applying row wins; one test per adjacent pair;
  pause precedence; a held command pause adds its row under Starting, row 4 and row 5 (G3-1).
- `grep -n 'Date()'` on all four files is empty.

**K4** (`WindowCatalogRulesTests`, `WindowLeaseLedgerTests`):

- Inclusion (Y-3): minimized, hidden, windowless and full screen each on and off; floating panels, system dialogs and
  anything under 100 × 100 pt are left out.
- Other-Space with and without a title. `spaceKnown == nil` drops `CGWindowList`-only windows.
- Native tabs filtered. Stage Manager per §4.8.
- Privacy: protected app; private marker; browser with an empty title.
- An app on "Apps hidden from Dock previews" yields no panel, and the switcher's list still includes it (D2-24). The switcher still captures its
  thumbnails, and a Dock Previews capture of it is refused (G3-3).
- Recency merge, and the Title sort (case- and diacritic-insensitive).
- Badges: Minimized > Full screen > On another Space > display name (only with more than one display). Hidden is a
  header flag, not a card badge.
- Freshness at 29.9 and 30 s. Retention is tested in `ThumbnailIndexTests` only (P3-11).
- Capture path choice: on-screen → SCK; minimized or other-Space → private if available, else last-seen, else icon.
- `hasAXElement == false` → raise only.
- The switcher's current inclusion cases, moved here.
- `WindowLeaseLedger`: union of needs; first-acquire and last-release edges; `.freshness(pid)` dropped 2 s after
  hide; Dock Previews alone holds no `.recency`, so the observer count is the Dock plus the previewed app (D2-5).

**K5** (`DockCommandGrammarTests`, `MenuLayoutTests`, `DockControlsTests`):

- Grammar: `status`, `status --json`, `pause`, `pause 30m`, `pause 1h30m`, `pause 90`, `pause 24h` and `resume`
  parse. `pause 25h`, `pause 0`, `pause x`, `pause forever`, `pause idle`, `pause until 17:30` and an unknown flag are
  usage errors (exit 2). Help text.
- The §4.21 verb × state table, as data, including `resume` with a held pause under Starting, row 4 and row 5
  (G3-1).
- `MenuLayout`: short title “Dock”; `ownIconIDs` never contains `.dockPreviews`, even unsanitized; tabs with five
  modules; the existing fuzz passes with five.
- Controls: unique ids; all registered; `dockPresence` present; master switch for the `dockPreviews` root.
  `testEveryCanonicalStringIsInTheSources` is created here with K5's own strings (§4.24; P3-1).
- "Registered while the module runs, paused included" is an A9 `dockCases` check, not a Kit test.

**Kit tests built in B and A items:**

- `WindowSymbolContractTests` (B1b): each result class of §4.12 step 5 (X2-1), with 10 no-answers that never poison,
  2 impossible results that do, and an owner mismatch that never does; secure input `unknown` keeps the switcher
  open and doesn't cancel it (X2-2); each probe's failure branch through an injected result (D2-13); a failed probe
  is `poisoned`, the re-probe after 10 minutes, and a second poisoning that lasts (P2-14); `fallback(for:)` for every
  feature; `launchLines`; the OS gate on a verified and an unverified major, where 0.4's symbols run and the capture doesn't
  (X3-1); `'????'` from `KBGetLayoutType` is no answer, and a probe with no answer isn't a failure (X3-6); the pixel
  limit at screen scale (X3-6); a probe pass cached per OS build (X3-3).
- `CrashGuardTests` (B1b): two overlapping calls to different symbols leave only the crashing one's marker (X2-4);
  a marker from another OS build is ignored; `verifiedBuild` stops markers for read-only symbols only; the give-back
  marker is apart from the take (X2-3); Try Again clears one feature's disabled builds; an unlink and a write interleaved on one symbol keep the marker
  while a call is in flight (X3-8, P3-6); a marker after a clean quit is ignored (X3-8); `Windows.pendingGiveBack`
  survives the next start's `apply`, there's no take while the give-back is disabled, and Try Again or a new OS build
  gives back, marker first, and removes the key only after it returns (X3-2).
- `DockLiveTests` (A6a): the `dock live` line format, and every increment matched by a decrement (P3-2).
- `ThumbnailIndexTests` (A1b; the budget cases at A2a): one client's prune, invalidate and purge never touch the
  other's entries; a stale stamp is refused, including a capture that finishes after `purge(client:)` (X2-12); the
  last release empties the index; opening the switcher doesn't evict a minimized window's last-seen entry (D2-14);
  dropping `.thumbnails` purges that client's entries, and a client without it gets nothing from any lookup,
  including another client's entry (X2-11);
  120 entries, 96 MB, the oversize skip, the 30-minute expiry and `nextExpiry` (X2-13); 0.4's limits until A2a
  switches them (D2-22).

---

## 7. Manual checks (recorded in `docs/design/0.5/MANUAL-CHECKS.md`)

**B** = Blocker for release. **V** = also run on the macOS 15 VM (or an owner check on 15 if there's no VM).

| # | Check | B | V |
|---|---|---|---|
| M1 | Switcher with Dock Previews off: ⌥⇥, ⌥\`, search and actions unchanged. Thumbnails as §4.23 describes. Nothing registered beyond today's set (M32). A launch with thumbnails off makes no private capture, the probe included; diagnostics show `hwCapture: notProbed` (X3-3) | B | V |
| M2 | Switcher and Dock Previews on together; turn either off; the other keeps working | B | V |
| M3 | Lock, display sleep, system sleep, fast user switching and revoking Screen Recording each purge thumbnails in both modules | B | V |
| M4 | ⌘⇥ takeover still works; `Windows.disable.symbolicHotKeys` gives ⌘⇥ back to macOS. At R, an owner leg on macOS 14 or 26 (X3-1) | B | |
| M5 | Switcher: minimized and other-Space windows have thumbnails, or the last-seen one with the badge | B | V |
| M6 | `Windows.disable.hwCapture`: last-seen, then the icon | B | |
| M7 | Hover shows previews after the delay; moving along the Dock swaps at once | B | V |
| M8 | `killall Dock` while on: previews work again within 2 s | B | V |
| M9 | Sleep and wake ×5, lock and unlock, fast user switching: previews keep working | B | V |
| M10 | An app that stalls AX: other apps' previews are unaffected; that app shows titles | B | |
| M11 | Bottom, left and right Dock, magnification on: positions correct; magnified, the panel doesn't move | B | V |
| M12 | Auto-hidden Dock: the panel stays while the pointer is in it and hides with the Dock otherwise; the panel doesn't move while magnified | B | V |
| M13 | Dock on a second display; mixed Retina and non-Retina | B | |
| M14 | Full-screen app: the Dock's previews appear over it | B | |
| M15 | Never stuck: leave fast in every direction, scroll away, ⌘⇥ away, Mission Control | B | V |
| M16 | Click raises minimized, hidden, other-Space and full-screen windows; again with `Windows.disable.raise` on (other Space only activates the app). At R, an owner leg on macOS 14 or 26 (X3-1) | B | V |
| M17 | Middle-click closes; hover buttons; the card menu; Minimize All; Close All | B | V |
| M18 | Text-only mode without Screen Recording; no prompt on hover | B | V |
| M19 | An app with 40 windows: cards shrink a size, then the panel scrolls; no card is out of reach. A 100-window app shows the windows read so far, then “More windows…” as the last cell, which scrolls into reach and VoiceOver reaches (X3-12). Apps with no open windows show their card | | V |
| M20 | Stage Manager on: previews are readable or text-only, never stuck | B | |
| M21 | 10 min idle with the module on: the display sleeps | B | V |
| M22 | VoiceOver on: paused by default. With the switch on, the announcement plays and cards are readable; with the pointer parked over a document, VoiceOver moves into the panel and the panel stays (G2-5) | B | |
| M23 | Engaged ⌘W, ⌘M, ⌘H, ⌘Q and Esc act on what's under the pointer. Over the header or a gap, ⌘W and ⌘Q do nothing and reach no app. No handled key reaches the frontmost app; bare letters, arrows and Return do. Hold ⌘Q over the last card for 2 s: only the previewed app quits (X3-4) | B | V |
| M24 | The keys tap is disabled while not engaged and gone with the module off (`CGGetEventTapList`) | B | |
| M25 | Dock click actions: Hide, Minimize and restore-all; a normal Dock click is never lost | B | V |
| M26 | Revoke Accessibility with each tap enabled: no freeze over 30 s; the feature stops with its row | B | |
| M27 | Settings page, Advanced, both Restore Defaults, Permissions rows | B | V |
| M28 | DockDoor running: paused with the row text; Run Both Anyway works | B | |
| M29 | Fresh install onboarding with Dock Previews on; five module rows fit at the default text size | B | V |
| M30 | Upgrade from 0.4.0: the New card; Turn On. A protected app added in 0.5 survives a downgrade to 0.4.0, and Restore Defaults on either page; the downgrade keeps every other setting | B | V |
| M31 | `snaptic dock status`, `status --json`, `pause`, `resume`, and every exit-2 and exit-5 text. In Safe Mode, `status` answers `state=paused reason=safeMode` and `pause` exits 5 | B | V |
| M32 | AX observers (`FocusTracker.liveObservers` plus the Dock observer). Dock Previews alone: 1 at rest, 2 while a preview is up, 1 again within 3 s of the hide. With the switcher on too: the switcher's count + 1, unchanged by a preview. Module off: the switcher's count (D2-5) | B | V |
| M33 | Safe Mode: the page row and the menu read “Paused in Safe Mode”; `dock status` gives `state=paused reason=safeMode`; the switcher shows minimized windows with the last-seen thumbnail or the icon; diagnostics show `hwCapture: safeMode`, 0 private captures (the probe included; X3-3) and 0 Dock counters | B | V |
| M34 | Backup export and import include Dock Previews settings and the protected apps; importing a backup with fewer protected apps keeps the current ones | B | V |
| M35 | Crash-guard drill, once per symbol: `SNAPTIC_DEBUG_TRAP_IN=<symbol>` traps; the next launch disables only that symbol and shows its feature's row; Try Again clears it, and the next hover captures. The give-back drill, `SNAPTIC_DEBUG_TRAP_IN=symbolicHotKeys.giveBack`: the §4.17 row shows on the Window Switcher page with the switcher off, the list survives a relaunch, and Try Again gives ⌘⇥ back (X3-2, G3-2) | B | |
| M36 | Right-click and long-press a Dock icon with the panel up: the Dock menu is never covered | B | V |
| M37 | Hide the App on: 50 clicks on background apps' icons hide nothing | B | V |
| M38 | Share the screen (QuickTime and a browser meeting). Point at an app with a minimized window. Record whether its thumbnail appears in the share. If it does, Known limitations and the Window thumbnails help say so in those words (X2-19) | B | |
| M39 | Revoke Screen Recording with both modules on: purge, then text-only, with no prompt | B | V |
| M40 | Park the pointer on the panel for 3 s, then type a sentence and press ⌘W: every key, ⌘W included, reaches the frontmost app. Move into the panel, wait 4 s, press ⌘W: it reaches the frontmost app | B | V |
| M41 | Quit from the header with unsaved work: the app asks to save; Finder has no Quit | B | |
| M42 | With VoiceOver off, ⌃F3 and Full Keyboard Access through the Dock: no previews (G3-9) | B | V |
| M43 | `snaptic dock pause 5m`: page row, menu and Resume agree; a relaunch resumes. Pause, then revoke Accessibility: row 4 and “Paused until…” [Resume] show, and `dock resume` answers “Dock Previews’ pause is cleared.” (G3-1) | B | V |
| M44 | Onboarding with Dock Previews as the only module: menu presence `.inSnapticMenu`; the Snaptic icon shows and the last step's text is true. With Accessibility revoked, the row-4 status item shows and there's no mark (G3-4) | B | V |
| M45 | Switcher Window thumbnails off: the switcher never shows a thumbnail, even one the Dock captured | B | V |
| M46 | Increase Contrast, Reduce Transparency and Reduce Motion each look as §4.7 says | B | V |
| M47 | Dock-not-readable row through the DEBUG test hook; Try Again; `dock status` gives `state=unavailable reason=dockUnreadable` | B | |
| M48 | Private windows and protected apps: no title, thumbnail or cache entry in either module | B | V |
| M49 | Idle 10 min with the module on: Snaptic's idle wake-ups (`top -stats pid,idlew`) are within 1 per second of the module being off (D2-26) | B | |
| M50 | Module on and off 20×: every live counter returns to 0; EventLog `dock.started` and `dock.stopped` counts match the cycles | B | V |

---

## 8. Risks

| Risk | Likelihood | Effect | Mitigation |
|---|---|---|---|
| Apple changes the Dock's AX tree or stops the selection notification | Medium | No previews | S0-1 and S0-2 on 27.2 and 15; state 5 ("can't read the Dock"); no polling fallback |
| `CGSHWCaptureWindowList` changes, disappears or returns blanks | Medium | No minimized thumbnails | §4.12 contract (shape failures only poison; empty answers and timeouts don't, X2-1), content check, kill switch, last-seen fallback |
| A crash inside a private call | Low | Snaptic crashes on hover | Crash guard: one marker per symbol, written before the call; one crash per symbol per OS build, then only that symbol stays off until Try Again or an OS update (X-2, X2-4, P2-1). The ⌘⇥ give-back has its own guard (X2-3) |
| Stuck previews (DockDoor #472) | Medium | Annoying | Kit state machine with a corridor, latch and safety net; M15 |
| The observer dies after lifecycle events | Medium | Previews stop until relaunch | KVO, the re-attach ladder, rebuild on wake and unlock, the health check; M8, M9, S0-31 |
| The window-service refactor regresses the switcher | Medium | Switcher bugs | B1a and A1a are moves with no behaviour change and land alone; M1, M4 |
| Memory from thumbnails | Low | High memory | 120 entries and 96 MB counted in bytes; 16 MB cap per entry; purge triggers |
| An active tap loses input when macOS refuses or Accessibility is revoked | Low | Severe | Keys tap enabled only while engaged; breakers; trust re-check; S0-20(c), S0-29; M26 |
| The capture indicator or reminders on each hover | Medium | Users turn the module off | Pacing; S0-19; Window thumbnails defaults off if S0-19 finds a per-call alert; the page says so (§4.9) |
| A private window leaks into a card, the cache or a share | Low | Privacy | One shared rule and store (§4.10); `sharingType = .none`; M30, M34, M38, M48 |
| Stage Manager | Medium | Odd previews | The §4.8 rule; S0-11; M20 |
| GPL contamination | Low | Licence problem | The clean-room rule; this plan is the only input; credit in notices |
| Two Dock preview tools fight | Medium | Double panels | Paused by default; Run Both Anyway is opt-in |

---

## 9. Not included (recorded; Y-9)

- **Media and Calendar widgets.** Media needs private MediaRemote, which has checked entitlements since macOS 15.4,
  or per-app Automation. DockDoor works around this for other players by running `/usr/bin/perl` with a bundled
  framework, which is outside Snaptic's rules. Lyrics need network calls, and Snaptic's only traffic is the update
  check. Calendar needs a new permission.
- **The ⌘⇥ overlay.** The switcher's ⌘⇥ takeover already replaces macOS ⌘⇥.
- **Window snapping** from the card menu. Window management would be its own module.
- **Moving a window to the current Space.** It works only through an undocumented ObjC class on 26 and later, not
  on 15, and that class can't get the §4.12 contract. A candidate for later.
- **Live and pinned previews.** An SCK stream per window costs too much; a candidate for a later release.
- **Dock gestures and clicks that need an active tap or synthetic input:** ⌘-right-click Quit, Shift-click New
  Window (also a synthetic ⌘N), scrolling on Dock icons, title-bar scrolling and "aero shake", Dock locking.
- **Trackpad gestures** (the swipe to open the switcher): a gesture tap.
- **Card swipe gestures.** They'd fit the rules if read from the panel's own scroll events; out of scope for 0.5.
- **The active-app indicator.** It draws over the Dock and depends on Dock geometry that broke on 27.
- **Click or modifier-click to preview.** Click modes need a swallowing tap. "Only while ⌥ is held" fits the rules
  and is a later candidate.
- **Hover actions** (full-size preview, or bring forward on card hover).
- **Quit an app when its last window closes.**
- **A new window for a windowless app**: needs a synthetic ⌘N.
- **Folder previews**: reading Downloads, Documents or Desktop needs a new folder permission.
- **"Only this display"** and a separate **"Only this Space"**. The other-Spaces switch covers the second (Y-3).
- **Leaving single windows out of a panel.** "Apps hidden from Dock previews" (§4.8, §4.18) hides an app's whole
  panel, and the protected apps list (§4.10) covers privacy. A per-window list is a later candidate (Y-3, D2-24).
- **Pausing while the screen is shared**: 0.5.x, after S0-24 (X-7).
- **Merging `IconsCrashGuard` into `CrashGuard`.** Hidden Icons keeps its own guard and its 0.4 tests in 0.5
  (P2-24).
- **The Space number badge** (Y-17).
- **The AppleScript dictionary.** The `snaptic` CLI covers scripting.
- **Importing DockDoor settings.**
- **Liquid Glass styling.** `NSGlassEffectView` needs the 26 SDK; Snaptic links the 15 SDK, and cards use the
  existing design system.
- **For the switcher (Y-19):** Vim keys, mouse follows focus, the swipe trigger and more sort orders.

---

## R1. Dispositions of the r1 reviews

**A** = accepted as proposed. **M** = accepted with the modification noted. **P** = partly accepted. **R** = rejected,
with the reason. Where a finding is accepted, the plan section that carries it is named. No r1 row is P or R. Rows
the r2 audit found partial now also name the r3 fix (D2-33).

No finding reopens Q1–Q7. Q6 keeps its decision (every switcher private symbol gets checks now); its mechanism is
restated for C symbols in the Owner decisions row, because a C function has no encoding to check (X-1, P-2).

### Pressure (P)

| ID | Disposition | Where / why |
|---|---|---|
| P-1 | M | §2.6, §1, A1a/A1b. Untitled other-Space windows stay as "Window on another Space" cards with Bring Forward only (`allowUntitled`), not one "N windows on other Spaces" row per app, so text-only mode and thumbnails share one card shape (§4.3). A card without an AX element offers only Bring Forward (§4.4, D2-25) |
| P-2 | A | §4.12 six checks; ground rule 3; Q6 restated, not reopened (with X-1) |
| P-3 | A | Ground rule 4 names the raise path's one exception and the `ActivitySimulator` carve-out (with X-22); H8 L2; S0-8 runs the raises after 10 min idle (D2-6) |
| P-4 | A | §4.10 (with Y-1, X-7); K4. The store stays in the 0.4 keys, read by both modules (D2-1) |
| P-5 | A | H3: `Windows/PrivateWindowAPI.swift` and `Switcher/SystemHotkeys.swift`; B1a. `IsSecureEventInputEnabled` is listed under §4.12 as exempt public API (D2-12) |
| P-6 | A | §2.3 contract; A1a/A1b split; Kit `ThumbnailIndexTests` (§6.1), not an app-side `ThumbnailStoreClientTests`, because there is no app test target (D2-14, P2-3) |
| P-7 | M | H6. Switches are read at each use (before each private call, tap enable, capture batch and resolver mouse-up, D2-15) instead of by a 1 s poll: a `UserDefaults` read is cheap and thread-safe, and there's no timer to own or leak. The `symbolicHotKeys` give-back rule is as proposed, with its own crash guard (X2-3) |
| P-8 | A | §4.12 selftest lines, one per symbol (D2-12); B1b done-when |
| P-9 | A | H8 (each row names its item); §6 "Every item" |
| P-10 | M | H1 (wider grep, compile step, three sites) and H10. The `.hidden` help text uses G-3's wording instead |
| P-11 | A | §4.13 (with X-2). In Safe Mode the module starts paused (D2-2); M33, M35 |
| P-12 | A | §5 gates table; §6 Needs column and order (D2-8, P2-5) |
| P-13 | A | §2.1 value types; ground rule 2 (no clock in Kit); §2.4; §6.1's K test lists, inline, replace Appendix B (D2-7, P2-4) |
| P-14 | A | §2.4 event sources; ground rule 1; §4.1; M49 compares against the module off (D2-26) |
| P-15 | A | §4.22 live counters and the `selftest-launch: dock live` line; A6a/A6b; M50 with the EventLog counts (D2-26) |
| P-16 | M | §4.5. ⌘W, ⌘M, ⌘H and ⌘Q only while engaged, plus Esc. Arrows and Return are dropped too: neither is needed to act on a card, and both are keys a user types (with X-3, Y-2, G-1); M40 |
| P-17 | M | §4.21, K5, A9. Exit codes and the off answer as proposed. The duration uses `AwakeDurationGrammar` (`pause 30m`), not `--minutes`, so it reads like `awake`. The verb × state table and `dockCases` are §4.21 and A9 (D2-27) |
| P-18 | A | H7 downgrade worktree; K1 done-when records the result in `H1-SITES.md` |
| P-19 | A | §2.6 (`Windows.disable.spaces` drops the other-Space list); §4.12 table |
| P-20 | M | §4.9. Byte accounting, 120 entries / 96 MB, entries over 16 MB skipped, as proposed. One age becomes two (X-21): freshness 30 s and retention 30 min, not 5 min, so the switcher keeps instant thumbnails between openings; ground rule 7 keeps them in memory |
| P-21 | M | §4.3. No new switcher entry point and no "+N more": cards drop one size, then the panel scrolls, so every window is reachable with the switcher on or off (with G-12, X-29, Y-12). This makes the cut candidate unnecessary |
| P-22 | A | D2 done-when (the `build.yml` version check against `RELEASE-NOTES-0.5.0.md`; no `docs/design/0.5.0/` copy, D2-28) |
| P-23 | A | §4.24; A7 done-when (`DockControlsTests.testEveryCanonicalStringIsInTheSources`) |
| P-24 | M | §2.3, §4.8. As proposed, and `DockObserver`'s elements get the same per-element 0.15 s (X-15) |
| P-25 | A | §4.12 raise fallback; S0-27; M16 |
| P-26 | A | §4.11 (S0-9 records the tap's TCC service); §4.14 |
| P-27 | A | H6 typed `DockFeature` and `WindowFeature`; §4.12 |

Non-finding sections: "Ordering, dependencies and size" is §6's order, sizes and critical path (A). Appendix A is the
grep `H1-SITES.md` starts from (K1). Appendix B's test lists were the K done-whens in r2. §6.1 now writes the K lists
inline and is the authority (D2-7, P2-4); it keeps `testSanitizeClampsDelay` in place of `…DelayAndGrace`, because
grace is a constant (G-6). **Cut candidates:** neither is taken. "+N more" is
replaced by P-21's scroll, which needs no switcher entry point, and Stage Manager keeps the §4.8 rule, with S0-11
deciding it and M20 checking it (Y-8).

### Grill (G)

| ID | Disposition | Where / why |
|---|---|---|
| G-1 | M | §4.5, §4.4. ⌘ keys (including ⌘H) and the header's Hide and Quit buttons as proposed, but keys act only while the panel is engaged, and arrows and Return are dropped (P-16, X-3); M40 replaces M23's wording |
| G-2 | A | §4.17 states table (`DockPageRules.status`); row 3 is paused in Safe Mode (D2-2) |
| G-3 | A | H1 three sites; §4.19. Default presence `.inSnapticMenu`; turning the module on later never changes it (G2-7, D2-29) |
| G-4 | M | §4.10, §4.18; M45. Own settings, the switcher's wording and "the cache never overrides a setting" as proposed. Privacy is the exception: "Protect private windows" and the protected apps are one store shown on both pages, kept in the 0.4 keys (D2-1), because a window protected in one module mustn't reach the shared cache through the other (X-7, Y-1) |
| G-5 | A | §4.18 header, summary, highlights, search and control count; the 0.1 s slider steps and the footer layout (D2-29) |
| G-6 | M | §4.18 Advanced strings and Restore Defaults as proposed. Grace (0.25 s) and the safety net (1 s) are constants (§4.2, §4.6), not rows: fewer rows to explain, and K3 tests one value. The Run Both footnote shows only while it's chosen (§4.15, D2-29) |
| G-7 | A | §4.14; H1 (`requiredPermissions` loop); A8 (D2-30, D2-33) |
| G-8 | A | §4.20; A8; M29 (five rows fit) and the 0.3.2 Upgrading line (D2-30) |
| G-9 | M | §4.11. Strings, default and Restore-all as proposed. The resolver is its own Kit type, `DockClickRules`, and "already active" comes from X-13's activation history (150 ms before mouse-down), with Y-15's mouse-up rules. The README note sits next to these settings (D2-30) |
| G-10 | A | §4.15 (`KnownDockTools`, pause scope, guide pages); D1's Switching from DockDoor table (D2-30) |
| G-11 | M | §4.16, §4.1 rule 5, §4.7. As proposed, except Reduce Motion: the panel only fades (0.15 s) and never slides, so it needs no branch (with Y-14); borders around the panel too (D2-31); M46 |
| G-12 | A | §4.3 (drop a size, then scroll); K2 with the scroll direction; M19 (D2-31) |
| G-13 | A | H9; D1 README outline (D2-30) |
| G-14 | M | §4.21. Verbs, help lines and the off answer as proposed. Refusals use `ControlExit.unavailable` (exit 5), the house code (P-17); the pause duration uses `AwakeDurationGrammar`. Safe Mode's refusal is reachable, because the verbs stay registered (D2-2, D2-27) |
| G-15 | A | §2.1; K1 (`properNames` gains "Dock"; `inSentence("Dock click actions")`, D2-29) |
| G-16 | A | §4.4 card right-click menu |
| G-17 | A | §4.3 badges; "Hidden" once in the header |
| G-18 | A | §4.3 "No open windows" and "No windows shown" cards |
| G-19 | M | §1.1; §5 S0-32. Numbered S0-32 because the adversarial rows took S0-17..S0-28. Read from DockDoor's Settings window only; its source is never opened. Differences go to D1's Switching from DockDoor table (D2-30) |
| G-20 | A | H6 README and guide rows; §4.17 kill-switch effects table; `Windows.*` lock rows on both Advanced sheets (D2-30) |
| G-21 | M | §7 M35–M50. The rows are merged with the pressure and adversarial checks and renumbered; overlaps are kept once. r3 restores the B and V marks and clauses the merge lost (D2-32) |
| G-22 | A | H4 (`dock.rectangle`, `.green`); H7 (`SettingsShellRulesTests`, 9 roots) |
| G-23 | A | What 0.5 adds ("make it full screen"); §4.4 |
| G-24 | A | §4.3 header count; §2.1 (`SentenceText.unit`) |

### Adversarial (X)

| ID | Disposition | Where / why |
|---|---|---|
| X-1 | A | §4.12 six checks; ground rule 3; the Q6 row restated (with P-2); B1b, with an injected result for each probe's failure branch and the connection-id equality (D2-13) |
| X-2 | A | §4.12 crash guard, one marker per symbol (X2-4); §4.13 (the module starts paused, D2-2; the switcher skips only the capture and raise symbols, D2-10); §8; A2b; M33, M35 (D2-9) |
| X-3 | M | §4.5. The engagement rule as proposed: 4 pt of movement within 1.5 s with the ring up 250 ms, or a click (D2-3, X2-5; X3-5 replaced the ring with 250 ms inside the panel); arrows and Return dropped (P-16, Y-2); ⌘H added (G-1); K3 `DockKeyRules` cases (§6.1) |
| X-4 | A | §4.9 capture gate (Screen Recording checked before each private-path capture and once per batch for SCK, X2-14; the requesting module's Window thumbnails on); S0-4 |
| X-5 | M | §4.9 content check: the 16 × 16 luma standard-deviation test only. The "95 % one colour" test is dropped, because a dark terminal or a blank page is legitimately one colour and would lose its real thumbnail |
| X-6 | M | §2.3. One generation per owner as proposed. Entries are keyed by `(windowID, pixel bucket)` with a nearest-bucket lookup, so the Dock's small captures and the switcher's large ones neither evict nor blur each other; `ThumbnailIndexTests` (D2-14) |
| X-7 | M | §4.10. One privacy rule and one shared store shown on both pages, kept in the 0.4 keys; `KitBackup` unions the list (D2-1); `sharingType = .none`. Pausing while the screen is shared waits for S0-24 and is 0.5.x (§9) |
| X-8 | A | §4.8; §2.6 (`windows(for pid:budget:allowUntitled:)`); S0-10; the window cap (D2-17) |
| X-9 | A | §2.3 `.freshness(pid)`; S0-26, which gates A2a (D2-18, D2-8) |
| X-10 | A | Ground rule 1; §2.4; §4.1 Dock zone; its K3 tests (§6.1, D2-19) |
| X-11 | A | §4.2 swap intent; the reflow and click-within races in K3 (§6.1, D2-19) |
| X-12 | A | §2.4; §4.2 latch; M36 |
| X-13 | A | §4.11 resolver (ambiguous → nothing happens, D2-20); M37 |
| X-14 | M | §4.5, §2.4. One tap for the module's life, toggled with `tapEnable`, as proposed, but created at the first show rather than in `start()`, so an enabled module that never shows holds no tap (ground rule 1). Never enabled while `switcherSessionActive`. Window reads run on `ObserverThread` (D2-16) |
| X-15 | A | §4.8 (`ObserverThread`, per-element 0.15 s); S0-14 measures under Mission Control and the like (D2-16) |
| X-16 | A | §2.4; §4.6 (no window-based Mission Control detector); S0-13, gone or correct within 1 s (D2-21) |
| X-17 | A | §4.8 liveness and re-attach ladder (silent-death check, a fresh observer per attempt, rebuild on display change, D2-4); S0-3; §8 |
| X-18 | A | §2.3; §2.5; M32's counts match §2.3 (D2-5) |
| X-19 | A | §4.9 (one private capture at a time, downscaled at once) |
| X-20 | A | §4.9 promise; What 0.5 adds; S0-19; D1 Known limitations |
| X-21 | A | §4.9 freshness 30 s, retention 30 min (with P-20). A1a keeps 0.4's limits and A2a switches; the release notes list them (§2.3 Staging, D2-22) |
| X-22 | A | Ground rule 4; H8 L2 |
| X-23 | A | H3; H8 (rule 11 and the shim grep) |
| X-24 | A | §4.12 table (`Windows.disable.layoutType`; public lookups listed with no switch); per-symbol selftest lines (D2-12) |
| X-25 | A | §2.4 (`ownMenuOpened`, `ownMenuClosed`, own-action window 1.5 s / 5 s); §4.2 (D2-33) |
| X-26 | A | §4.1 rule 5 |
| X-27 | M | §2.1 (`DockGeometry` converts AX frames with the `Screens.cocoaRect` rules, so Kit owns and tests the conversion); §4.7; K2 negative-x and above-primary cases (D2-33) |
| X-28 | M | §4.8, §4.3. The matching ladder as proposed. When copies share one Dock item, the panel lists the hovered copy's windows under a "2 instances" header, per S0-2, rather than one merged list. S0-2 adds an app run from App Translocation (D2-21) |
| X-29 | M | §4.3, §4.4. Our panels excluded by window number, and the header's Quit Snaptic takes the clean-quit path, as proposed. Overflow drops a size then scrolls (P-21), not compact title rows. A 100-window app shows the windows read so far, then “More windows…” (§4.8, D2-17; M19) |
| X-30 | A | §4.7; S0-6 |
| X-31 | A | §4.12 raise fallback (`yieldActivation` first); S0-27; M16 |
| X-32 | M | §4.5, §4.16. No ring, no key hints and the tap disabled under secure input, as proposed. It's read when the panel shows and when it engages, not by a poll in `WindowServices`, so nothing ticks while idle (ground rule 1) |
| X-33 | M | §4.15, §4.21. The reason enum as proposed. `dock status` doesn't name the tool either, since its output gets pasted into bug reports; only the Settings row and the Snaptic menu do |

The "S0 gate coverage" section is §5 S0-17..S0-28 (A); its gates are in the §5 table.

### Parity (Y)

| ID | Disposition | Where / why |
|---|---|---|
| Y-1 | A | §4.10 (one rule, applied before any capture or cache write; the store stays in the 0.4 keys, D2-1); K4; M48 |
| Y-2 | M | §4.5. ⌘ for every destructive key and engagement first, as proposed; arrows and Return dropped rather than gated (P-16, X-3) |
| Y-3 | M | §4.8 window rules, live-id re-check and the switcher's cases, as proposed. "Only this Space" is the existing other-Spaces switch. "Only this display" is §9. An app-level list, "Apps hidden from Dock previews", is in 0.5 (§4.18); a per-window list is §9: the panel shows the app the user pointed at, so filtering its windows away hides what they came for (D2-24) |
| Y-4 | M | §5 S0-29..S0-31: added as proposed, numbered after the adversarial rows; S0-10's odd-app set is the proposed set (D2-21) |
| Y-5 | A | §4.7 settled-frame rule; S0-7 |
| Y-6 | A | §1 corrected; §1.1 rows; ground rule 9; S0-3 rebuilds `AXList` under the same pid after a display change (D2-4) |
| Y-7 | A | §4.9 pacing and SCK stills; S0-19, and the quieter path is preferred (§5, D2-23) |
| Y-8 | A | §4.8 Stage Manager rule; S0-11; M20 (the pressure cut candidate isn't taken) |
| Y-9 | A | §9 |
| Y-10 | A | §4.4 Minimize All button; Close All in the header's right-click menu; M17 |
| Y-11 | A | §1.1 reason recorded; K3 case (§6.1, D2-19) |
| Y-12 | M | §4.3, §1.1. Medium 280 pt, the 16:10 letterboxed frame, one row or two columns, and K2 tests, as proposed (§6.1, D2-7). Overflow drops a size then scrolls, instead of "+N more" (P-21) |
| Y-13 | A | §4.18; §4.23 (both modules) |
| Y-14 | M | §4.1 rule 6, §4.2, ground rule 1, as proposed. The fade is 0.15 s and stays under Reduce Motion, because nothing moves (§4.7, G-11). K3 names the timing rows (§6.1, D2-19) |
| Y-15 | A | §4.11 resolver (mouse-down state, mouse-up on the same item within 0.5 s, the 100 ms wait; Restore-all decided at mouse-down); K3 cases (D2-20, D2-19) |
| Y-16 | M | §4.3; S0-10, S0-2. Instances as proposed (with X-28). Native tabs stay filtered as the switcher does today, so both modules agree; S0-10 records the tab behaviour for a later change in both |
| Y-17 | M | §4.3 display badge in both modules. The Space number is §9: it needs a new Space-index symbol |
| Y-18 | A | §4.4 (`appTerminated`; in-place removal); §2.4; K3 |
| Y-19 | A | §4.23; What 0.5 adds; the switcher's exclusions in §9 |

---

## R2. Dispositions of the r2 reviews

Same legend as §R1. No r2 row is P or R. No finding reopens Q1–Q7.

**Where reviewers disagreed**, one answer is used everywhere:

| Topic | Followed | Not followed, and why |
|---|---|---|
| Crash marker | X2-4: one file marker per symbol, written synchronously before the call | P2-1's per-feature key: two symbols of one feature can be in flight at once |
| Safe Mode | G2-2, D2-2, P2-2's option B: registered, starts paused | P2-2's option A ("not registered"): `dock status` would answer "Unknown command" for a module that is on |
| Engagement window | D2-3: 1.5 s, with X2-5's 4 pt and 250 ms | X2-5's 3 s: 1.5 s is r1's X-3 value, and the 4 pt and 250 ms already stop the 1-pixel drift |
| Probe thread | X2-6: off main on a serial queue; only the window orders front on main | P2-15's all-on-main: a stalled AX call would block main |
| Result rule | X2-1's classes: shape failures poison; empty answers and timeouts don't | P2-14's success rule: it counts normal no-answers as failures |
| OS gate | X2-2's split: read-only symbols probe on 14 and 26; writers stay unavailable (replaced by X3-1, §R3) | P2-16's "15 and 27 only": it drops the switcher's read-only lookups on two supported releases |
| Row 5 pause | G2-12: pausing works in row 5 | P2-25's refusal: the user can't pause a module that is waiting for the Dock |
| "Don't show previews for" | G2-4: kept, renamed "Apps hidden from Dock previews" | D2-24's delete: it's the only per-app opt-out the Dock module has |

### Adversarial (X2)

| ID | Disposition | Where / why |
|---|---|---|
| X2-1 | A | §4.12 step 5: results sort into "no answer" (AX errors, NULL or empty for a gone window, a raise error), which never counts, and "impossible" (the table's last column). Two impossible results in a row poison. Answers an app controls never count; §6.1; §8 |
| X2-2 | A | §4.12 table: secure input is public API, exempt from the gate. When it can't be read it is **unknown**: the switcher doesn't take ⌘⇥ and nothing is cancelled, so it never closes; H3; K3; §6.1 |
| X2-3 | M | H3 step 3b runs `CrashGuard.atLaunch` before step 4, and the give-back has its own marker (`inflight/symbolicHotKeys.giveBack`); the signal handler makes no write (D2-11). The saved list is kept, not removed, so Try Again or a macOS update can still give ⌘⇥ back |
| X2-4 | A | §4.12 step 6: one file marker per symbol in `inflight/`, written with `write(2)` before the call. After 20 successes only the read-only symbols stop writing markers; the capture, the raise trio and the setter keep theirs; §8; §6.1 `CrashGuardTests` |
| X2-5 | M | §4.5: 4 pt and a 250 ms ring, autorepeat and the 300 ms reflow swallowed, key-ups swallowed. The window is 1.5 s (D2-3), not 3 s |
| X2-6 | A | §4.12 step 4: the probe runs once per process at the first acquire, off main on one serial queue; the probe window is named and ordered on main; each probe has a check that can fail; a caller before the probe ends gets the fallback |
| X2-7 | A | §4.12 step 1 Image column: `_AXUIElementGetWindow` from HIServices, `GetProcessForPID` from HIServices (corrected by P3-10), `RTLD_DEFAULT` lookups named |
| X2-8 | A | §4.9 content check: a low-variance capture is only suspect; after three suspects from two windows the probe-window capture runs again, and a pass accepts those windows as plain |
| X2-9 | A | §2.3 Edges: each need starts and stops on its own edge. The Dock's idle lease registers notification-centre observers only, with no thread, timer or AX observer (ground rule 1) |
| X2-10 | A | §4.1 rule 5 hit band: the item's frame grown by half the gap to each neighbour and stretched to the screen edge; K2 cases (2 pt outside, magnified icon before its frame grows) |
| X2-11 | A | §2.3: an `update` that drops `.thumbnails` purges that client at once, and a client without it gets no thumbnail; §4.23; §6.1 |
| X2-12 | A | §2.3, §2.5: `release` and `purge(client:)` bump the client's generation first, so a late capture fails the stamp check; the calls wait for nothing |
| X2-13 | A | §2.5: a timer set for `ThumbnailIndex.nextExpiry` enforces retention whether or not a panel shows |
| X2-14 | A | §4.9: Screen Recording is checked before each private-path capture, and once per batch for SCK, which enforces consent itself |
| X2-15 | A | §2.4 `switcherClosed`; §4.1 holds back while the switcher is open; K3 |
| X2-16 | A | §4.8: within 2 minutes of login the ladder adds 5 s and 10 s steps; the 30 s health check keeps running, and a read that succeeds leaves state 5; §4.17 |
| X2-17 | A | §4.11: the mouse-up item is `DockObserver`'s latest selection checked against the hit band, with no AX call in the tap; a new window is growth in the pid's layer-0 window count between mouse-up and +100 ms |
| X2-18 | A | §4.13: Safe Mode skips only the capture and the raise trio, so the layout pair still runs and ISO keyboards keep the key above Tab (D2-10) |
| X2-19 | A | M38 records whether a minimized window's thumbnail appears in a share, so it can fail; §4.10 screen sharing says what Known limitations then say |
| X2-20 | A | §4.7: a window no screen holds captures at the largest `backingScaleFactor` among the current screens |
| X2-21 | A | M1 points to §4.23 for thumbnails; §4.23 lists the switcher's only visible changes |
| X2-22 | A | §4.12 step 2: 14 and 26 stay unverified unless STEP0-NOTES records S0-4, S0-5 and S0-17 legs on them (the reviewer's second option) |
| X2-23 | A | §4.2 swap intent: the swap waits while the pointer still heads in, is checked again on each `pointerMoved`, and runs once it stops heading in; K3 |
| X2-24 | A | §4.17: one crash-guard template with the `WindowFeature` display-name table |

### Grill (G2)

| ID | Disposition | Where / why |
|---|---|---|
| G2-1 | A | §4.5 table (five keys always swallowed while engaged), §4.4, §4.1 rule 6; H9 lists the keys' help text |
| G2-2 | A | §4.13 (starts paused, verbs registered), §4.17 row 3, §4.21; M31, M33 |
| G2-3 | A | §4.10: Restore Defaults never touches the protected apps, on either page or sheet; both messages say so; H9 (`SettingsView.swift:100–121`) |
| G2-4 | A | §4.18: "Apps hidden from Dock previews" sits outside the Privacy section, with help that says it hides the panel and leaves the switcher alone; §4.8; §4.10 |
| G2-5 | A | §4.16 (the selection drives the panel; labels; M22), §4.2, §4.17 row 7 ("Dock click actions still work" when one is on) |
| G2-6 | M | §4.17 "Around the row", Starting, kill switches, §4.14 and Input Monitoring as proposed. The crash-guard rows use one template and the display-name table (X2-24), not one sentence per feature |
| G2-7 | A | H1 and §4.19: the default menu presence is `.inSnapticMenu`; K1 |
| G2-8 | A | §4.18: a Dock click actions section with its footer; "Apps with no open windows" takes the switcher's label |
| G2-9 | A | §4.19, §4.17: menu rows reuse the page strings; Open Settings shows in row 4 only; Pause in row 9 only, Resume in row 8 only |
| G2-10 | A | §4.15: when the footnote shows, which tool it names, and where |
| G2-11 | A | §4.20: the onboarding row matches the page summary |
| G2-12 | A | §4.21: a pause never shortens one running; replies in ISO UTC; the verb × state table (pause works in row 5); the `status` format with `keys` |
| G2-13 | A | §4.24 canonical strings, and the curly-quote pass over §4 |
| G2-14 | A | H9 rows for README, GUIDE and `SettingsView.swift` |
| G2-15 | A | §4.16: labels for private and small cards |

### Pressure (P2)

| ID | Disposition | Where / why |
|---|---|---|
| P2-1 | M | §4.12 step 6: a per-symbol file marker written synchronously (X2-4), not a per-feature key; the give-back has its own guard (X2-3); §8 |
| P2-2 | M | §4.13, §4.21: option B (registered, starts paused). Option A would make `dock status` answer "Unknown command" for a module that is on |
| P2-3 | A | §2.1 Kit `ThumbnailIndex`; §2.5; §6 A1b and A2a test it in `SnapticKitTests` |
| P2-4 | A | §6.1 holds the K lists inline; Appendix B is no longer cited |
| P2-5 | A | §6 Needs column; done-whens moved to the item that has the UI |
| P2-6 | A | §6: B1a and A1a cite M1 and M4 only |
| P2-7 | A | §4.12 selftest: DEBUG `forcePoisonForSelfTest()` poisons every symbol, calls none, and prints `windows poison path ok|failed`; debug step only |
| P2-8 | A | §2.1 `WindowSymbol` struct; H8 Rule 10 |
| P2-9 | A | §4.10 says where the list is stored (0.4's switcher keys); H10 drops the "slice" |
| P2-10 | A | H8 L14 row |
| P2-11 | A | H8 L20 row |
| P2-12 | A | H3 caller table (takers and givers, `HostHeartbeat` included) |
| P2-13 | A | §4.12 Image column |
| P2-14 | M | §4.12 per-symbol "Impossible result" column, using X2-1's classes; a success rule would count normal no-answers; §6.1 |
| P2-15 | M | §4.12 step 4: the probe window is named; probes run off main on a serial queue at launch, and only the window orders front on main (X2-6) |
| P2-16 | M | §4.12 step 2, §5: X2-2's split. Read-only symbols probe on 14 and 26; writers stay unavailable |
| P2-17 | A | H6: read once per batch |
| P2-18 | A | §4.12 selftest: every step sets the expect variable |
| P2-19 | A | §5 gates table |
| P2-20 | A | §5 "If it fails" column; S0-4 states its numbers (p50, p95, peak memory under 150 MB) |
| P2-21 | A | §6 critical path |
| P2-22 | A | H1, H10: A6a and A6b |
| P2-23 | A | H1: the pinned grep with its hit count at `7dd972c`; `SettingsRootID` is a grep step checked by `SettingsShellRulesTests` |
| P2-24 | A | §2.1, §9: Hidden Icons keeps `IconsCrashGuard` in 0.5 |
| P2-25 | M | §4.21 duration grammar, the extend rule and the verb × state replies, as proposed, except that pausing works in row 5 (G2-12) |

### Dispositions audit (D2)

| ID | Disposition | Where / why |
|---|---|---|
| D2-1 | A | §4.10: the list stays in 0.4's `protectPrivateWindows` and `privateBundleIDs`, read by both modules; import unions; a downgrade keeps working; neither Restore Defaults clears it; §2.3; H7; H10; K1 `KitBackupTests`; M30, M34 |
| D2-2 | A | §4.13, §4.17 row 3, §4.21; M33 |
| D2-3 | A | §4.5 (1.5 s, a click engages); K3 engagement cases |
| D2-4 | A | §4.8: wake, unlock, session-active and display change rebuild the observer; S0-3 |
| D2-5 | A | §2.3 `.freshness(pid)` shares `FocusTracker`'s observer; M32 counts |
| D2-6 | A | Ground rule 4 names Awake's `ActivitySimulator`; H8 L2; S0-8 runs after 10 min idle |
| D2-7 | A | §6.1 is the K authority |
| D2-8 | M | §5 gates moved; §6 uses the Needs column and P2-21's path instead of one linear path |
| D2-9 | M | §4.17 crash row, M33, M35 widened. The row uses the display-name table (X2-24), not the "Used for" text |
| D2-10 | A | §4.13: only the capture and raise symbols are skipped |
| D2-11 | A | H3: the signal handler makes no crash-guard write |
| D2-12 | A | §4.12 selftest: one line per symbol, from `WindowSymbolContract.launchLines` |
| D2-13 | A | §4.12 connection-id check; §6.1 injected-result cases |
| D2-14 | A | H1 call-site grep; §6.1 `ThumbnailIndexTests` (client isolation, last release empties, switcher open keeps last-seen). The test lives in Kit (P2-3) |
| D2-15 | A | H6; §4.11: read on each mouse-up the resolver would act on |
| D2-16 | A | §4.8 `windows(for pid:budget:allowUntitled:)` on `ObserverThread`; S0-14 |
| D2-17 | A | §4.3, §4.8 "More windows…"; M19 adds a 100-window app |
| D2-18 | A | §2.3 per-window cap; §R1 X-9 |
| D2-19 | A | §6.1 K3 named cases |
| D2-20 | A | §4.11 mouse-down sampling and the ambiguous case; K3 |
| D2-21 | A | S0-2, S0-10, S0-13 |
| D2-22 | A | §2.3, §2.6: A1a keeps 0.4's limits until A2a; §4.23; D2 release notes |
| D2-23 | A | §5 contingency: the quieter path is preferred |
| D2-24 | M | Kept and renamed "Apps hidden from Dock previews" (G2-4); §9 and §R1 Y-3 now agree; K4 case. Not deleted |
| D2-25 | A | §4.4: a card without an AX element offers only Bring Forward |
| D2-26 | A | M49, M50 baselines |
| D2-27 | A | §4.21 refusals (pause and resume only); A9 `dockCases` |
| D2-28 | A | D2 done-when: no `docs/design/0.5.0/` |
| D2-29 | A | H1; §4.15; §4.18; §4.19; K1 |
| D2-30 | A | H1; H6; §4.11; §4.20; S0-32; A8; D1 |
| D2-31 | A | §4.3, §4.7: Increase Contrast borders; scroll direction |
| D2-32 | A | §7 B and V marks |
| D2-33 | A | §R1 legend and rows rewritten |

## R3. Round-3 dispositions

Same legend as §R1. No r3 row is P or R. No finding reopens Q1–Q7. Changes made during implementation go in §R4.

**Where reviewers disagreed**, one answer is used everywhere:

| Topic | Followed | Not followed, and why |
|---|---|---|
| OS gate on majors newer than the verified ones | The no-regression rule with X3-1's split: 0.4's symbols run on every major from 14 up, 28+ included, under the rest of the contract; only what's new in 0.5 waits for a verified major | X3-1's "writers and capture `unavailable` on 28+": it would take ⌘⇥ and the raise away on a release where 0.4 still does them |
| Marker races | X3-8 and P3-6 together: one lock per symbol over the count and the file call, never the private call | — (they agree; one rule) |
| A6a's Safe Mode check | P3-2's split (state and diagnostics at A6a, verbs at A9) with G3-5's DEBUG state hook | G3-5's moving the whole check to A9: A6a still needs a Safe Mode check of its own |
| Oversize skip | 16 MB, as §4.9 says (P3-5, X3-10) | §2.3's 96 MB, and r3's "as in 0.4": 0.4's `ThumbnailStore` has no per-entry byte cap |

### Adversarial (X3)

| ID | Disposition | Where / why |
|---|---|---|
| X3-1 | M | §4.12 step 2, H6, §5 legs, M4, M16, R. 0.4's symbols (raise trio, symbolic-hotkey pair, Spaces, `_AXUIElementGetWindow`, layout pair) run on every major from 14 up under the rest of the contract; only `CGSHWCaptureWindowList` and new 0.5 uses need a verified major. The give-back is exempt from the gate, the image check and poisoning. Modified: 28+ isn't gated either (see the table above) |
| X3-2 | A | §4.12 step 6 (`Windows.pendingGiveBack`, no writer in `apply`/`restore`/`recoverFromPreviousRun`, no take while disabled, key removed after the give-back returns); H3 launch order; H6; §4.17 row; `CrashGuardTests`; M35 |
| X3-3 | M | §4.12 step 4: the capture probe runs only before the first capture that passes every §4.9 gate; §4.13; M1, M33. Modified: every symbol probes lazily at its first use, and a pass is cached per OS build (`Windows.probedBuild.<symbol>`) |
| X3-4 | A | §4.5 Held keys and the tap's enable rule; ground rule 1; K3 `DockKeyRules`; M23 |
| X3-5 | A | §4.5: engagement is 4 pt of movement within 1.5 s plus 250 ms inside the panel since `panelEntered`; the ring follows engagement. `selectionRingShown` removed from §2.4; K3 cases rewritten |
| X3-6 | A | §4.12 step 4 (`'????'` is no answer; a no-answer probe isn't a failure, retried at most once a minute), step 5, the impossible column (`CGSIsSymbolicHotKeyEnabled` has none; layout values listed; pixel limit from the window's bounds at the largest screen scale); §4.9 Shape; `WindowSymbolContractTests` |
| X3-7 | A | H3 layout row: `WindowServices.layout(for:)` caches by keyboard type; the tap does no I/O |
| X3-8 | A | §4.12 step 6: 0700 directory, per-symbol lock, `O_NOFOLLOW`/`O_CLOEXEC`, `markerWriteFailed`, markers ignored after a clean quit (`AppDelegate.swift:134`); `CrashGuardTests` |
| X3-9 | A | §4.9 content check: a shape-only probe pass accepts nothing; §4.12 step 4 |
| X3-10 | A | §2.3 (16 MB, the 2400-pixel note), §2.5 (60 s leeway), ground rule 1 (the retention timer) |
| X3-11 | A | §6.1 K3: the Dock's menu hides with `dockMenu` and sets the latch |
| X3-12 | A | §4.8 (trigger after one window, loaded windows kept, timeout defined, last cell), §4.3; K2; M19 |

### Grill (G3)

| ID | Disposition | Where / why |
|---|---|---|
| G3-1 | A | §4.17 held-pause row; §4.19 items 1 and 3; §4.21 replies, `resume` cells and pause paragraph; K3 `DockPageRules`; K5; M43 |
| G3-2 | A | §4.17 "⌘⇥ not given back" row: two strings by S0-5's logout result, help text, shown whatever the switcher's state, Try Again scoped to the give-back; §4.12 step 6; M35 |
| G3-3 | A | §4.9: the hidden list blocks Dock Previews captures only; K4 |
| G3-4 | A | §4.17 attention mark and §4.19 presence: no tab bar, no mark, the row-4 status item is the signal; M44 |
| G3-5 | M | §6 A6a and A9. Merged with P3-2: A6a reads the Safe Mode state through a DEBUG hook; the verbs move to A9 |
| G3-6 | A | §4.17 Around the row and §4.18 Footer: (?) always; Restore Defaults… and Advanced… only while the module is on |
| G3-7 | A | One name, “Thumbnails of minimized windows and windows on other Spaces”, in §4.12's table and §4.13 |
| G3-8 | A | The guide holds “Switching from DockDoor”: §5 S0-32, §6 D1 |
| G3-9 | A | §4.1 rule 5, §4.16 Known limitation, M42 |
| G3-10 | A | §4.18: the sheet's own question and `RestoreDefaults(title:question:message:button:destructive:)` |

### Pressure (P3)

| ID | Disposition | Where / why |
|---|---|---|
| P3-1 | A | §4.24: whole-literal check, source-form interpolations; K5 creates the test, A4a to A7 and A8 append; README, GUIDE and site strings go to D1 and D3 |
| P3-2 | A | §4.22 Kit `DockLive`, added at A6a and fed by A3, A4a and A5; §6 A6a and A9; `DockLiveTests` |
| P3-3 | A | §6 Needs: B1b + A1a, A4a + B1b, A7 + A2b; done-whens of A2b, A4b, A5, A6b and A7 split by item; critical-path note |
| P3-4 | A | §5 gates (D1: S0-32; R: S0-31); §6 S0 done-when excludes S0-31; R runs the soak |
| P3-5 | M | §2.3: 16 MB, with the 2400-pixel note. Modified: "as in 0.4" isn't claimed, because 0.4 has no per-entry cap |
| P3-6 | A | §4.12 step 6, with X3-8 |
| P3-7 | A | §2.1 (`AwakeCountdown.unit(_:_:_:)` moves unchanged), §6.1 K1, §4.18 (the delay value isn't a unit count) |
| P3-8 | A | §6.1 K1: `testSanitizeOwnIconFallsBackToInSnapticMenu` |
| P3-9 | A | H7 and §6 A8: `IconsControlsTests.swift:196–197` |
| P3-10 | A | §R2 X2-7 row corrected to HIServices, matching §4.12's table |
| P3-11 | A | §6.1 K4: retention is `ThumbnailIndexTests` only |

## R4. Implementation changes

Each change made during implementation, and each S0 "If it fails" answer taken, gets one row here: the item, what
changed, and why.

| Item | Change | Why |
|---|---|---|
| S0-4, PC-1 | §4.12 step 4: the capture probe uses a second 64 × 64 window that is never ordered in, framed inside the main screen's visible frame, `sharingType = .readOnly`, drawn with the same pattern, and checked against the pattern. The Spaces and AX probes keep the ordered-in, off-screen `.none` window. On 27.2 the probe passes with the pattern check, so §4.9's shape-only branch isn't reached there | On 27.2 a window wholly off screen captures NULL with every option, so the planned probe would never answer and private capture would never turn on. S0-5a (owner) confirms the new window never shows in Mission Control |
| S0-4, PC-2 | §4.12 step 5: NULL for a window whose frame is on no display joins *no answer*. Cards size from the captured image, never from the window's aspect ratio | A partly off-screen window captures only its visible part (32 × 64 for a 64 × 64 window half off screen) |
| S0-1 | §4.8 / K2: a Dock item maps to a running app only when `AXIsApplicationRunning` = 1, then by URL as planned. The Dock's hit area is the union of item frames, not the `AXList` frame | Two tiles that weren't running matched a running app's URL; item frames reach 5 pt below the list frame |
| S0-15 | K1: `KnownDockTools` ships bundle ids only (DockDoor, DockDoor Pro, HyperDock, Dock Mate, DockView 2). Team ids are added at R from `codesign -dv` | No team id could be read without downloading and inspecting the apps |
| S0-26 | The row's "If it fails" answer is taken for `kAXWindowMiniaturizedNotification` and `kAXWindowDeminiaturizedNotification` only: while the panel is up, the 1 s tick re-reads the hovered app. Created, title changed and destroyed pass. PC-3 (count from the end of the animation) stays open for the owner after the other-app leg | Those two arrive when the minimize animation ends, about 0.55 s after the call |
| S0 | Every macOS 15 leg is an owner check before R, as §5 allows. The disruptive rows and legs are carried to an owner session (`STEP0-NOTES.md`, Carried forward and Owner session). Items gated by a carried row start, and the row must pass before that item's done-when is claimed | No macOS 15 VM exists on the build host, and the owner was using the Mac |
| K1 | The inert shell stays `.stopped` (0.4's shell reported running). Its `[.accessibility]` means turning Dock Previews on before A6a asks for Accessibility and does nothing else, and its menu section is empty until A7 | H1 says the shell's `start()` and `stop()` do nothing; "stopped" is the honest state |
| K1 | The `MenuLayout.ownIconIDs` guard against `.dockPreviews`, and the `dock` alias on `module disable`, land at K1 rather than K5 and A6a | The existing menu-layout fuzz fails without the guard once the case exists; the alias is one line in the same switch |
| K1 | `AwakeCountdown.unit` moved to `SentenceText.unit` unchanged (12 files). `DockConfig` is stored under `SnapticDockV1`. `dockPresence` is left for K5 | §2.1 names the move; the plan names no store key, so it follows 0.4's `SnapticIconsV1` |
| K1 | L20 now covers `Switcher/`, so `WindowGatherer`'s log line is the fixed string "Gathered windows" | H8: no interpolated values in log lines in the widened scope |
| K1 | KitBackup: the switcher section's privacy fields are now safety paths, so one existing test flips from false to true. 0.4.0 replaces the protected-apps list on import rather than merging; recorded in `H1-SITES.md` as the downgrade result | §4.10 union import |
| K4 | Kit gains `DockRect` (in `DockModel.swift`), a Foundation-only rect for catalog and screen scopes. `CatalogWindow` also carries `kind`, `alpha`, `windowless`, `inStageStrip` and a stored `onOtherSpace` | The rules need them and Kit can't use `CGRect` on Linux |
| K4 | With Spaces data unavailable, the switcher drops other-Space windows (their app still counts as having a window). The switcher keeps its 40 pt minimum and its untitled-dialog rule; the Dock path uses §4.8's 100 pt. Finder's desktop-window rule also applies to windows read through AX. An empty bundle id matches no protected-app entry | P-19 and §4.8, applied through the shared rules; the old app copies were deleted, not kept |
| K4 | The 2 s freshness linger lives in `WindowLeaseLedger`. `CaptureGate.switcherList` leaves the per-capture consent, owner and protected-list checks in `ThumbnailStore` until A2a | One owner per rule; A2a moves capture into `WindowCapture` |
| B1a | `ObserverThread` was cut from a switcher file into `Windows/ObserverThread.swift` (an add, not a rename) and went from `private` to `internal`. The enum is `PrivateWindowAPI`. `THIRD_PARTY_NOTICES.md`'s path to the moved file is updated | The plan moves it at B1a; another module can't use a `private` type |
| B1a | L2 also scans the shims and bans the `postToPSN` variants; rule 11 limits `dlsym`/`dlopen` in shim `.m` files to the named shims (`SNWindowServer` included for B1b). `SLPSPostEventRecordTo` may be named only in `PrivateWindowAPI.swift`, string literals included, so B1b's selftest lines take the name from there | The C names are callable from the shims, so the ban has to reach them |
| A1a | The §2.5 purge observers run only while some lease holds `.thumbnails`, not from the first lease. `acquire` takes an `onPurge` closure, so the switcher still closes on lock. The will-sleep trigger is added at A2a with the other purge triggers | With thumbnails off nothing is stored, so there is nothing to purge, and the switcher registers what 0.4 did (§4.23, M1) |
| A1a | `reset()` keeping the privacy fields and `resetPrivacy()` (§4.10) move to A2b, next to its Restore Defaults message | Changing reset at A1a would alter behaviour before the message that explains it exists |
| A1b | The switcher keeps the last image of any window that isn't refused, so minimized, hidden and other-Space windows keep it (a restored window can show it briefly until the new capture lands). A thumbnail belongs to the client that captured it last; lookups don't change eviction order. Ages use a clock that runs through sleep, as in 0.4 | §2.3 and D2-14 (last-seen) |
| A1b | The capturable-window list stays in `ThumbnailStore` until A2a. `captureForPreview` doesn't need `.thumbnails`, so the switcher's preview works with thumbnails off. `acquire` takes an optional `onWindowsChanged:`, reported at most once per 0.3 s; "window destroyed" is registered for the windows of the observer's own latest read until the Dock's read lands at A4a | Capture state is A2a's; the preview is 0.4 behaviour |
| A2a | 96 MB and 16 MB are decimal (10⁶ bytes). "Dirty" means focus: the window moved to, the one left, and the focused window when the switcher opens. The 150 ms pacing applies to the switcher too, so a ⌘⇥ released before the panel shows captures nothing. Full-size previews up to 16 MB are now cached (2400 px bucket). The retention timer pauses in sleep, which purges anyway | §4.9 leaves these open; they follow its pacing and budget rules |
| A2a | A Screen Recording revoke purges without calling `onPurge`, so an open switcher carries on with text. The switcher's permission observer catches the revoke (there is no 2 s Settings poll to reuse) | "Purges, then shows text, with no prompt" |
| A6a | In Safe Mode, `start()` sets the paused state and returns without registering the three `dock` verbs. A9 adds them with the rest of `DockCLI` | P3-2 moves the CLI to A9 |
| A6a | Turning the module on goes through the host's `requestPermissions(for:)`, which can ask for Screen Recording because thumbnails are on by default. The switcher already works this way. A7 and A8 re-check this against §4.14 (only onboarding or the page row ask) | Keeps one permission path. §4.14's wording is checked when the page exists |
| A6a | `--selftest-launch` on a DEBUG build starts Dock Previews once, with a Safe Mode context, after the `dock live` line. That start creates nothing. It prints `selftest-launch: dock safe mode state=paused observer=no leases=0 captures=0` | G3-5 asks for the Safe Mode state through a DEBUG hook. §4.22 says the selftest starts no module, and the `dock live` line still reads before the probe |
| A6a | `WindowCapture` has no per-client count, so the "Captures" diagnostic is the module's own tally (0 until A4a). "Cache entries" and "Cache bytes" are the shared store's totals | Keeps the diagnostics free of a second count in A2a's code |
| A6a | `SafeMode.skipped` lists "Thumbnails of minimized windows and windows on other Spaces" before A2b's private capture path exists | The Safe Mode sheet is written once, for 0.5 as shipped |
| K2 | One `DockRect` and one `DockPoint` (Codable, Hashable) in `DockModel.swift`, with fields `width` and `height`. K4's call sites were renamed from `w` and `h`. `contains(_:)` includes every edge and serves geometry. K4's `contains(x:y:)` keeps `CGRect`'s half-open rule for the catalog's screen scope | K4, K2 and K3 each defined the type in parallel |
| K2 | Cards that don't fit drop exactly one size, then the panel scrolls | §4.3 "drop one size", read as one step |
| K2 | A side Dock's panel puts the header in a strip across the top | A side strip can't fit the name and the buttons. §4.3 doesn't say |
| K2 | The hit band also runs 24 pt past the item's inner side. Neighbours split the gap between them | Covers the magnified icon before its frame grows (X2-10), like the zone's 24 pt |
| K2 | Panel padding is 12 pt, card spacing 12 pt and the header 32 pt | §4.3 gives no values. The owner can tune them at M19 |
| K2 | On the Dock's side the panel sits 6 pt off the Dock, with no 8 pt margin added. The 8 pt margin applies at the other three edges | §4.3's 6 pt gap and 8 pt margin would otherwise apply to the same edge |
| K2 | A scrolled panel loads thumbnails for the visible cards plus one card past each edge | §4.9 asks for visible cards only; one card hides the pop-in while scrolling |
| K3 | Two new policy events. `panelPlaced` carries the panel's frame, which the corridor and the heading-in check need. `moduleStopped` sends the `stopped` hide reason | §2.4 names the reason but no event for it |
| K3 | The policy takes its geometry through `DockPolicyGeometry` closures. Its built-in `plain…` defaults are for tests only, and A4a passes `DockGeometry`'s edge, zone and hit band | K2 and K3 were built in parallel. The hit band must be K2's (X2-10, with K2's 24 pt row) |
| K3 | `appTerminated` applies the 8 pt lockout and clears the selection. `dragStarted` hides with `clickOutside`. `raised` sets the latch, so the panel doesn't come back under the pointer | Covers the reflow and hovered-app-quits races (S0-22). §2.4 has no drag reason |
| K3 | "Starting" is the page state when rows 1–4 don't apply and row 5 doesn't yet. "Advanced…" is two actions, because rows 6 and 7 open the sheet at different places | Row order in §4.15; one action couldn't scroll to both places |
| K3 | Kit takes time as `Double` seconds passed in; the app converts from `mach_absolute_time`. Crash-guard and poisoned rows take display names as strings | Kit is Foundation-only, Linux-tested, and can't look up bundles |
| K3 | The pointer monitor stays on during the 8 pt lockout and while latched, so it sees the move that ends them. Engagement counts only real movement | Without the monitor the lockout could never end on a still pointer |
| K3 | A stale selection is judged by when it arrived, plus the pointer-agrees rule. So A4a must send one `pointerMoved` when it starts watching | §4.1 rule 4 needs a pointer time to compare with |
| K3 | A held swap runs 0.12 s after the pointer last headed into the panel | X2-23 gives the rule but not the timer start |
| K5 | The verb × state table is keyed by K3's `DockPageRow`, which also carries each row's §4.21 number, `state`, `reason` and whether the verbs are registered. `DockCLIState` and `DockCLIReason` are defined once, in `DockCommandGrammar`, and `DockPageRules.cli` reads them from the row. The table keeps §4.21's order; `DockPageRow` keeps §4.17's precedence order | K3 and K5 each defined the rows and the CLI enums in parallel |
| K5 | `status --json` puts the live counters under `"live"` | A top-level `keys` counter would clash with the `keys` feature field |
| K5 | The usage string lives in Kit. The Accessibility pane name comes in through a `paneName` closure | Kit can't read the app's pane names. Awake and Hidden Icons keep their usage strings in the app |
| K5 | `dock pause` has the off-only policy, like `awake pause`, and help shows "(off only)" | §4.21 names no policy. Pausing only turns things off |
| K5 | Kill-switch lock rows are one row per feature, adding `dock.page.clickActionsLock` | One lock per kill switch reads as a list |
| K5 | The Advanced sheet repeats the two shared privacy rows under Dock ids, so their search titles match the switcher's. Neither Restore Defaults button touches the privacy keys | The privacy settings are shared (§4.10) and owned by the switcher's store |
| K5 | `menubar.page.dockPresence` sits in a controls table whose view has no Dock row until A7. Lint lists it in `L15_PENDING_IDS`, which A7 empties | Keeps the K5 tables complete without drawing UI early |
| A3 | The health check reads the pointer with `CGEvent(source: nil)` on the observer's thread, not `NSEvent.mouseLocation` on main | The check runs off main and must not wait on main |
| A3 | "Login" for the attach ladder is loginwindow's start time, or Snaptic's launch when loginwindow can't be read | Snaptic can launch long after login; the ladder's window is about the Dock coming up |
| A3 | Re-attaches count only a new Dock pid. An `AXList` rebuild under the same pid is counted on its own (Observer rebuilds) | Keeps the `killall Dock` check (10 kills → 10 re-attaches) exact |
| A3 | `AXSpacerDockItem` maps to `separator` | It's the Dock's spacer tile; it never shows a panel |
| A3 | When an app's AX read times out before its first window, its on-screen `CGWindowList` windows are listed too, titles only | Otherwise a stalled app shows an empty panel while its windows are visible |
| A3 | Every Dock event tries one attach before the back-off ladder | A Dock that came back between ladder steps is picked up on the next hover |
| A3 | After a list rebuild the `AXList` is checked again at 0.5 s and 1.5 s, and its destroyed notification is watched (S0-3) | The Dock can rebuild the list twice in a row when items are added |
| A3 | A window-list read that times out is retried once within the per-app budget | One slow first call is common right after an app launches |
| A3 | The 2 s cache keeps the full read and applies `allowUntitled` per call | Two callers with different settings share one read |
| A3 | DEBUG builds time `windows(for:)` on each selection that would show a panel (Window reads: n, p95, last count) | S0-23 and the AX stall check need a number before A4a's panel exists |
| B1b | The `Windows.*` kill-switch domain is read the way `ConfigStore` names it, copied into `PrivateWindowAPI` | `ConfigStore` has no shared accessor, and adding one would touch every store |
| B1b | `KBGetLayoutType` runs on the probe queue and is cached per keyboard type. The first key press on a new keyboard type uses the last layout seen (ANSI until one is known) | The probe must never run inside the event tap |
| B1b | On a new OS build, the first use of a symbol takes the 0.4 path until the background probe finishes; the six presence-only symbols don't wait | No probe on the key or open path |
| B1b | When several states apply, poisoned outranks disabled, and disabled outranks unavailable | The plan gave no order; the most severe state is the one to report |
| B1b | 0.4 behaviour kept: `isOnAnySpace` returns false on NULL; the raise fallback is `app.activate()`; the window-ID title-and-frame fallback isn't wired | No switcher regressions in the item that adds the contract |
| B1b | The give-back runs even if its marker write fails, and the signal handler's give-back is a bare call | Giving ⌘⇥ back matters more than the marker; signal handlers must stay simple |
| B1b | Secure input `unknown` pauses the ⌘⇥ takeover and doesn't cancel an open switcher (X2-2) | As planned; recorded because it's the visible behaviour |
| B1b | The DEBUG poison path traps with `abort()`. An unreadable OS build number turns the crash markers off | Markers keyed to an unknown build can't be matched later |
| B1b | Merged after A3: `windows(for:)` reads the kill switches once per read, as `loadWindows` does | The Dock read path uses the same private symbols as the switcher (H6) |
| A4a | Placement, which cards show, event mapping and the move throttle live in a new Kit file, `DockPreviewRules`, with tests | Kit holds the logic that needs unit tests (P2-3) |
| A4a | The 1 s tick forces a real re-read, skipping the 2 s cache, unless the app's last read timed out | S0-26 says the tick re-reads; a stalled app isn't asked every second |
| A4a | When the plan is empty or there's no room to place the panel, the policy counts it as shown but no panel appears; the next tick can place it | Avoids a show/hide loop |
| A4a | The anchor is the settled item frame, falling back to the selection's frame after 0.25 s | Never places against a frame that is still magnifying (M11) |
| A4a | The panel's level is `.statusBar`: above the Dock, below the Dock's menu | M36 |
| A4a | Dock-menu open and close come from the Dock observer's AX notifications, best effort | The Dock exposes no other signal |
| A4a | Workspace observers and mouse monitors exist only while the pointer is watched; the panel is created per show and released after the fade | Ground rule: nothing is held while idle or hidden |
| A4a | Dock auto-hide is read with `CFPreferences`, read-only, each time watching starts | Picks up changes without writing settings |
| A4a | `DockWindowRead` gains `zOrder` | The card sort needs the stacking order |
| A4a | The small (windowless) card is 240 × 64 pt | The plan gives no size |
| A4a | A read that timed out and found nothing shows "Windows can’t be read right now" | M10 |
| A4a | Policy events go through one queue, so a command that sends an event can't re-enter the policy | Keeps the K3 machine's single-step semantics |
| A4a | A selection that arrives while a mouse button is down drops its app | No previews during drags and clicks |
| A4a | `.freshness(pid)` is held only while a preview is shown | M32: one observer at rest, two while shown |
| A4a | Pointer-in-panel is reconciled from the tracking area, the local monitor and the tick | One enter or exit per crossing |
| A4a | A small AppKit view catches middle-clicks on cards | SwiftUI taps don't report the middle button |
| A4a | Card badges use §4.3's words ("Full screen", "On another Space"), which differ from the switcher's | They are the plan's words |
| A4a | Captures are requested only for targets not already requested | `WindowCapture.refresh` cancels the batch in flight |
| A4a | "Shows / last hover-to-show" and "Dismissals by reason" are release diagnostics lines; latency runs from the policy's show to the panel appearing | §4.22's lines; counts and enums only |
| A4a | The controller's clock is `systemUptime` | Monotonic, like the rest of the Dock code |
| A4b | The panel menu enum is `DockPanelMenuItem` | K3 already uses `DockMenuItem` |
| A4b | No tooltip or menu shows a key until A5 reports the keys tap available (`keysAvailable`) | §4.5 ties key hints to keys actually working |
| A4b | A card's VoiceOver label carries one state at most: minimized, then hidden, then full screen, then other Space | Same order as the badges |
| A4b | A minimized card's yellow hover button reads "Restore" ("Restore (⌘M)"); Show takes "(⌘H)" like Hide | It restores rather than minimizes; it's the same key |
| A4b | The header menu reads Minimize All, Close All, a separator, Hide/Show, Quit | Mirrors the card menu's layout |
| A4b | Minimize All and Close All act only on listed windows that still exist; Close All skips cards without an AX element | §4.8 and D2-25 |
| A4b | Before each action the window's owner pid is checked with `CGWindowListCreateDescriptionFromArray` | §4.8's re-check without blocking on AX |
| A4b | After a window action the app is read again at 0.3 s; app hide and unhide refresh the shown panel | The AX change lands after the policy's immediate refresh; keeps Hide/Show right (G2-1) |
| A4b | `WindowManager.reopen` is internal, and `close(_:)`/`minimize(_:)` run their AX calls in one detached task each | Reuse instead of A4a's copy; AX stays off main |
| A4b | Full Screen raises the window, waits 250 ms, then toggles | The switcher's pattern |
| A4b | Snaptic quitting itself runs `NSApp.terminate` on the next main-loop pass, which reaches `markCleanQuit` in `applicationWillTerminate` | The panel's hide and any open menu finish first (X-29) |
| A4b | The header sits at the top of the panel for every Dock edge, not on the edge away from the Dock | K2's layout puts it there; for a side Dock a top header reads better than a vertical strip |
| A4b | The "· 2 instances" header text isn't built yet | It depends on S0-2's two-copies result, which is carried to the owner session; add it before R if S0-2 shows the Dock merges copies |
| A4b | VoiceOver: the announcement goes through `VoiceOverAnnouncer` once per show or swap; focus is bound per element and on the scroll area, and leaving counts after 0.15 s; hover buttons are hidden in favour of named actions | Existing precedent; SwiftUI passes through nil between elements; one element per card |
| A4b | New VoiceOver labels "Windows can’t be read right now, ‹app›" and "Window on another Space, ‹app›" | §4.16 doesn't cover these cards |
| A4b | Increase Contrast and Reduce Transparency are read from the SwiftUI environment; `allowsToolTipsWhenApplicationIsInactive` is on | Existing precedent (Toast); tooltips must show while another app is active |
| A4b | Card callbacks take window ids, not indices; `perform(key:)` sends `.keyHandled` for every key | Ids survive a refresh; the policy acts only on Esc |
| A6b | The pause decision, EventLog lines, diagnostics lines and `dock status` values live in a new Kit file, `DockPauseRules`; the sources (known tool launch/quit, VoiceOver, the command pause's end timer) in `Dock/DockPauseSources.swift` | Kit holds the logic that needs tests (P2-3) |
| A6b | The effective pause is `DockPauseRules.effective`, which doesn't wait for a Dock read | A Dock that becomes readable while another tool runs never flashes a preview |
| A6b | A pause takes down the lease, observer and controller, except the VoiceOver pause while click actions or Restore All are on | Ground rule 1; click actions still need the observer's selection |
| A6b | While the engine is down for a pause, the Dock read counts as attached for the page rules | The pause's own row shows instead of Starting or "Dock unreadable" |
| A6b | The module's state stays `.running` while paused | Hidden Icons precedent; the pause shows in its row, menu, diagnostics and status |
| A6b | EventLog lines are `dock.started`, `dock.stopped`, `dock.paused reason=<enum>` and `dock.resumed`; Safe Mode logs no pause line | Enums only (§4.22); Safe Mode isn't a change |
| A6b | The switcher hook is `WindowServices.setSwitcherSessionActive(_:)`, set from `SwitcherController.active`, with an `observeSwitcherSession` registry | The plan named the events but no mechanism (X2-15) |
| A6b | Symbol states in diagnostics read the `Windows.probedBuild.<symbol>` defaults through `CrashGuard.probedKey`, so a probe with no answer also reads `notProbed`; the lines are in the Dock section only | No accessor existed; A6b stayed out of A2b's files |
| A6b | `clickActions=`/`keys=` precedence in status is disabled > off > stopped > paused > on; `clickActions` counts as on when the pop-up isn't Do Nothing or Restore All is on | The plan gives no precedence |
| A6b | A held command pause is in memory only and is dropped when the module stops; its end timer counts in `timers` | §4.21 |
| A6b | `status --json` reports `leases` as `WindowServices.liveLeases` (all clients) | Matches the selftest's `dock live` line |
| A6b | Known tools are matched by exact bundle id only | Clean room; `KnownDockTools` is the only input |
| A6b | In Safe Mode the kill switches aren't read, so `clickActions` reads `paused`, not `disabled` | Nothing is read in Safe Mode (§4.13) |
| A6b | DEBUG builds register `dock status [--json]` until A9 registers the real verbs; the selftest's Safe Mode probe also checks `Pause reason` and `hwCapture` read `safeMode` | The done-when needs `dock status` before A9 |
| A2b | A suspect capture of a window already proven plain is accepted and doesn't count; a nil or empty sample counts as suspect; the brightness sample is taken from the scaled image with medium smoothing | Plain windows don't trigger rechecks; suspect is the safe default; cheaper and steadier than the full image |
| A2b | A pattern recheck checks only that run's windows and only after the probe passed: a failure clears the plain list, a pass marks those windows plain and leaves health alone, no answer changes nothing | A recheck never overlaps the probe and never blames other windows |
| A2b | Gone windows are pruned from the plain list at the start of a private batch; a reused window number proves itself again | The list can't grow without bound or vouch for a different window |
| A2b | One `PrivateWindowAPI.hwCapture()` choke point for every `CGSHWCaptureWindowList` call, the probe included; Safe Mode is a flag set from `AppDelegate`, and the capture counter includes the probe and rechecks | §4.13: one place to refuse, one count to read |
| A2b | Private captures run one at a time in a lane both clients share (probe and rechecks inside it), each also taking one of the 4 SCK slots and counting toward 8 per second; every gate is checked again after the lane and slot are taken | No two private calls overlap, and the pacing stays one budget |
| A2b | Private captures are taken at 1x and scaled to the client's pixel limit, using the window server's bounds and the largest screen scale | Nothing is upscaled on Retina |
| A2b | The switcher's full-size preview stays on ScreenCaptureKit; `captureForPreview` takes the private path only for minimized and other-Space windows and then needs `.thumbnails` | The preview is drawn where the window is; §4.9's lease rule holds for every private capture |
| A2b | The switcher page's stopped rows (crash guard, give-back) show in the blocked, off and on states and refresh on `stopsChanged`; the give-back text says ⌘⇥ doesn't come back at logout | S0-5b isn't settled |
| A2b | About › Diagnostics gains a "Windows" section after Dock Previews, always shown | The private path is shared by both window modules |
| A2b | ScreenCaptureKit captures use the backing scale of the display the window's centre is on, not the main display's (merge fix) | M13: mixed Retina and non-Retina displays |
| A2b | Gap: the raise calls aren't skipped in Safe Mode | `bringToFront` is outside A2b's files; checked at R |
| A5 | The key hold lasts the longer of 1 s and "Delay until repeat" plus 0.2 s (`DockKeyRules(repeatDelay:)`, read from `NSEvent.keyRepeatDelay` when the tap is made) | With Long (about 1.8 s), a fixed 1 s cap ended before ⌘Q's first repeat, which then reached the app that came forward |
| A5 | ⌘Q needs a card under the pointer; over the header or a gap it does nothing (K3's rule and test changed) | M23 says ⌘Q over the header or a gap does nothing |
| A5 | `WindowServices.switcherSessionActive` is set at once, and its handlers run on the next main turn; the module's handler calls `controller.switcher(open:)`, which also re-syncs the keys tap (merge: A5's and A6b's copies made one, A5's timing kept) | The switcher sets it from inside its own tap callback; one registration per client |
| A5 | The keys callback reads the pointer from `event.location`; letters come from `charactersIgnoringModifiers` only when ⌘ is the sole modifier, with ANSI key codes as the fallback | No read outside the event in the callback; follows the keyboard layout as the switcher does |
| A5 | The breakers are counted in the callbacks and trust is re-checked on the next main turn; both breakers are static and last until relaunch, and the click breaker counts in `clicksWork` and the page facts | The callbacks do no I/O; §4.17 |
| A5 | The click tap is listen-only and appended last, and its callback only records the time and place | A Dock click is never lost or delayed |
| A5 | The on-screen window count is read at mouse-down only when the clicked app is active; Restore all's counts come from an async read started at mouse-down that a quicker mouse-up waits for | No window read in the callback, and none the rule can't use |
| A5 | Minimize acts only on current-Space, non-full-screen windows with an AX element | The only ones it can minimize |
| A5 | The activation history starts with the frontmost app at time 0 | Otherwise the first click after start has no active app |
| A5 | Hidden, Finder and secure input are read at show and at engage; the key target is captured at key-down and the action runs on that card | No I/O at key time; the action hits the card the rules saw |
| A5 | Keys act through A4b's `perform(_:on:)`, the same path as the menus (merge: A5's own close, minimize, hide and quit copies dropped); every close or minimize, from a key or a click, starts the 0.3 s reflow | One action path; the cards move either way |
| A5 | `keysAvailable` is true while the tap is made, keys can run and secure input isn't on, so tooltips and menus show keys only then | A4b's hook; the tap is made at the first show |
| A5 | The click tap takes the module's pause and the VoiceOver pause doesn't stop it; it starts and stops with `startEngine`/`stopEngine` (merge) | §4.16; A6b's engine split |
| A5 | `DockLive.keys` counts from the first show with keys on until the module stops | The tap is kept, disabled, between shows |
| A5 | Diagnostics add "Keys breaker", "Click tap", "Click actions" and "Click skips", counts and enums only; Kit `DockPanelHit` gives the key target | §4.22; the key target needs pure tests |
| A7 | No `Permission.inputMonitoring` on the Permissions page; Dock Previews is listed under Accessibility only | §4.14 makes Input Monitoring conditional on S0-9, which hasn't run; A5's click tap needs Accessibility |
| A7 | The switcher half of §4.10 (`reset()` keeps the privacy fields, `resetPrivacy()`, the switcher's footer, list help and restore message) and the §4.18 Window thumbnails detail land in A7 | A2b didn't take them, and the Dock sheet's restore text depends on the switcher keeping privacy |
| A7 | The canonical list also holds the ⌘⇥ give-back rows and the generic " (⌘\(keyIndex))" sidebar tooltip; "Dock Previews (⌘n)" has no literal of its own | They are §4.17 and §4.19 strings; `MenuLayout` builds the tooltip generically |
| A7 | The Delay slider steps through positions labelled by `delayLabels`; "0.1 s" is the locale's decimal separator plus `L(" s")` | Locale-correct labels without one string per position |
| A7 | `DockObserver` gains `onReadChanged`, `retry`, `reattach` and `ladderEndedAt`; it re-attaches when Accessibility is granted | Row 5's 2-minute attention wait and Try Again need them; row 4 clears without a relaunch |
| A7 | DEBUG `SNAPTIC_DEBUG_DOCK_UNREADABLE=1` makes every attach fail; Try Again clears it for the run | M47 needs a way to reach row 5 on a working Dock |
| A7 | The controller reports `onKeysBreakerTripped` to the module | The breaker row and the attention mark need it |
| A7 | `everythingHiddenWithoutShortcuts` adds a Dock-only "Everything hidden" warning with no Show Snaptic Menu button | That button never moves Dock, so it would do nothing |
| A7 | The host asks for Accessibility with "Dock Previews needs it to read the Dock." and never asks for Screen Recording for Dock | §4.14 and G-7: Screen Recording comes only from onboarding or the page's row |
| A7 | Row 1 (kill switch) shows only the lock row, without highlights | The module can't be turned on, so the highlights would sell nothing |
| A7 | `syncPause` refreshes Settings every time | Rows 6–8 name a tool or a clock that can change while the pause stays the same |
| A7 | The keys lock row under the toggle is unanchored; the same key's Diagnostics row keeps the anchor | One anchor per key |
| A7 | Menu Bar help for Dock shows only while it's on Don't Show | Matches `MenuPlacement.help(.hidden, .dockPreviews)` |
| A7 | Gap: §4.10's "`--selftest-controls` checks both on values" is left to A9's `dockCases` | It belongs with the CLI self-test cases |
| A8 | Most of A8 was already in place: `dockCard.v1`, `insertingDockCard` and its tests (A6a/K1), the card's title, text and button (A1a/B1a), and the onboarding summary (A7). A8 wires `insertingDockCard` into `runMigrations` after the icons card, adds `host.dock` to onboarding's `needed` loop, and changes the welcome text | Only the wiring and the one string were left |
| A8 | `IconsControlsTests`' welcome entry now holds the 0.5 text | The 0.4 string no longer exists, so the Icons canonical test would fail (H7; P3-9) |
| A9 | `--selftest-controls` reaches each exit-5 refusal and every §4.21 table row through a stand-in `DockCLITarget` fed by Kit `DockPageFacts.reaching(row)`, not DEBUG hooks; the real module is exercised in Safe Mode | §4.22: the selftest starts no engine, so the rows can't be reached on the real module there |
| A9 | Kit `DockCommandGrammar.step(_:facts:)` holds the verb × state table as one function, with `DockResumeCell.clearsPause` | The CLI and the selftest apply the same step |
| A9 | `statusFacts` passes the breaker flags | Otherwise `clickActions=stopped` and `keys=stopped` could never show |
| A9 | `PermissionFlow.state` and `refresh` honour `readsGrants: false` | R5.5: a self-test never asks macOS about permissions |
| A9 | Each `dock` command writes one `.control` EventLog line (verb and exit code only) | `KitControl.counterKey` counts only Awake's verbs |
| A9 | `Config.restoringDefaults()` keeps the two privacy fields; `AppSettings.reset()` and the selftest's §4.10 check both use it | Closes A7's gap: `--selftest-controls` checks both on values survive both Restore Defaults |
| A9 | A6b's DEBUG `dock status` is gone; `DockCLI` registers on both start paths, Safe Mode included, and ends with the module | §4.21: registered in Starting and rows 3–9, never in rows 1 and 2 |
