# 0.5 plan review r1: engineering pressure test

Reviewer: pressure-test (R1). Input: `docs/design/0.5/PLAN-draft.md` (draft r1, 425 lines) and the Snaptic tree at
`7dd972c` on `feature/v050-dock-previews`. Apart from this file, `docs/design/0.5/` is untracked and I didn't touch
it. I didn't reopen the owner decisions (Q1 to Q7). Where a finding touches one, it says how to meet the decision, not
whether to keep it. I checked every claim against the code at `7dd972c`. I didn't build or launch anything, and no
finding depends on a build. Plan lines are cited as `PLAN:l.N`. Code paths are shortened: `App/` is
`Sources/Snaptic/`, `Kit/` is `Sources/SnapticKit/` and `Tests/` is `Tests/SnapticKitTests/`.

Summary: 3 Blockers, 15 Majors, 9 Minors.

---

## Blockers

### P-1 · Blocker · §1 (l.71–73), §2 (l.108–109, l.129–132), §4.2, §4.6, §4.11, A1, A2: the plan's picture of the switcher's window code is wrong in seven places it depends on

**Finding.** The Dock design reuses switcher parts for things they don't do. Each of these errors changes the size
or the design of A1, A2 or K4:

1. **No window-listing `WindowGatherer`.** `WindowGatherer` is "Gather windows here": it moves every window onto
   one display. Listing is done by `WindowManager.loadWindows(includeOtherSpaces:includeWindowless:excluded:)`, which
   walks every regular app. There is no call for one pid. The Dock needs one app's windows within a 0.2 s delay and a
   0.15 s AX budget.
2. **Text-only mode loses other-Space windows.** They come from `CGWindowListCopyWindowInfo`, and untitled entries
   are dropped. Without Screen Recording, `kCGWindowName` is empty, so in text-only mode (Q2, PLAN:l.232) every
   other-Space window disappears. The "Windows on other Spaces ✓" setting (l.280) then shows nothing, and so do
   windows whose app sets no title.
3. **Actions on other-Space cards do nothing.** Those items carry `axElement: nil`. Close, minimize and full screen
   all guard on `axElement`, so the hover buttons, middle-click, the right-click menu (l.193) and the W/M keys
   (l.194) silently do nothing on those cards.
4. **SLS doesn't drive the badge.** The "Other Space" badge comes from `!onScreen`. `SLSCopySpacesForWindows`
   (`PrivateAPIs.isOnAnySpace`) only filters out inactive native tabs and helper windows. P-19 covers what that does
   to the kill switch.
5. **`FocusTracker` can't drive freshness.** It is a `private` member of `WindowManager` and observes only
   `kAXFocusedWindowChangedNotification`. Nothing observes window created, destroyed, minimized or retitled. "One AX
   observer per app already exists" (l.73) is true, but it gives recency only, not freshness.
6. **`ThumbnailStore` can't serve the Dock.** It captures with ScreenCaptureKit and `onScreenWindowsOnly: true`, so
   it can't capture minimized or other-Space windows at all. It holds 40 entries for 5 minutes, counted by entry, not
   by bytes. Sharing it breaks in four ways:
   - One `generation` counter means `invalidate()` drops every capture in flight, so a Dock hover cancels a switcher
     capture and the reverse.
   - `prune(keeping:)` with the switcher's window set evicts the Dock's entries.
   - The switcher's `stop()` purges the store, and so does turning switcher thumbnails off.
   - Its privacy note says "nothing is captured once the switcher is dismissed". After A2 that is false.
7. **The switcher already opens with cached thumbnails.** "The switcher, which now opens with cached thumbnails"
   (l.226) describes current behaviour: the cache already survives between openings. What changes is that the
   switcher shows thumbnails the Dock captured, and P-4 shows why that needs a privacy rule.

**Evidence.**
- `App/Switcher/WindowGatherer.swift:5-9`: the "Gather windows here" doc and class.
- `App/Switcher/WindowManager.swift:245`: `loadWindows` over all apps.
- PLAN:l.71: "Reuse the switcher's `WindowGatherer` (already lists other Spaces …)".
- `WindowManager.swift:435-452`: other-Space windows come from `CGWindowListCopyWindowInfo`.
- `WindowManager.swift:456`: `guard let rawTitle …, !rawTitle.isEmpty else { continue }`.
- `WindowManager.swift:461`: `axElement: nil`.
- `WindowManager.swift:548-574`: close, minimize and full screen guard on `axElement`.
- `WindowManager.swift:297`: `isOnOtherSpace: !raw.isMinimized && !app.isHidden && !onScreen`.
- `WindowManager.swift:283` and `:451`: `isOnAnySpace` used only as a filter.
- `WindowManager.swift:181`: `private let focusTracker = FocusTracker()`.
- `WindowManager.swift:800`: `kAXFocusedWindowChangedNotification` is the only notification.
- `App/Switcher/ThumbnailStore.swift:21-22` (capacity 40, maxAge 5 min), `:27` (one `generation`), `:39`
  (`invalidate`), `:53` (`prune(keeping:)`), `:130` (`onScreenWindowsOnly: true`), `:8-15` (the privacy note).
- `App/Switcher/WindowSwitcherModule.swift:90-92`: `stop()` purges. `:245-247`: turning thumbnails off purges.
- PLAN:l.72-73, l.108-109, l.129-132, l.176-178, l.226-227, l.258-259.

**Proposal.**
> Replace the §1 rows "Window list", "Thumbnails" and "Freshness" (l.71–73), and add to §2:
>
> "**What the switcher has today, and what 0.5 adds.** Windows are listed by
> `WindowManager.loadWindows(includeOtherSpaces:includeWindowless:excluded:)` over every app. 0.5 adds
> `WindowManager.windows(of pid:, budget:)`. It uses the same AX path and the same `CGWindowList` path for
> other-Space windows, for one pid, and returns within the 0.15 s budget or with what it has.
>
> Other-Space windows come from `CGWindowList` with no AX element. Their cards offer **Raise only**: no close,
> minimize or full-screen button, no middle-click close, and the menu shows only 'Show Window', 'Hide App' and 'Quit
> App'. Without Screen Recording, an other-Space window has no title. In text-only mode it is shown as one 'N windows
> on other Spaces' row per app, which raises the app, not as a card.
>
> The 'Other Space' badge stays `!onScreen && !minimized && !hidden`. `SLSCopySpacesForWindows` only filters out
> native tabs and helper windows.
>
> Freshness: `FocusTracker` moves into `WindowServices`. It keeps one AX observer per app, now also for
> `kAXWindowCreatedNotification`, `kAXUIElementDestroyedNotification`, `kAXWindowMiniaturizedNotification`,
> `kAXWindowDeminiaturizedNotification` and `kAXTitleChangedNotification`, but only while Dock Previews holds a lease
> that asks for freshness. The switcher's lease asks for recency only, so with Dock Previews off it registers exactly
> what it does today.
>
> Thumbnails: `ThumbnailStore` keeps its SCK path for on-screen windows. `WindowCapture` adds the private path for
> minimized and other-Space windows (A2b, behind B1b). The store becomes client-aware: entries are tagged by client
> and keyed by `(windowID, pixel bucket)`, `generation` is per client, `prune(keeping:client:)` drops only that
> client's tag, and `purge(client:)` runs on a client's `stop()` while `purgeAll()` runs on lock, sleep and fast
> user switching."
>
> Rewrite `ThumbnailStore`'s privacy note (and the README privacy text, D1) to say what is true after A2:
> "captured only while the switcher or a Dock preview is showing; kept in memory for at most 5 minutes; purged on
> lock, sleep, fast user switching and when the last client stops."

### P-2 · Blocker · ground rules (l.47–49), H3, §4.12 (l.272–273), B1: there is no encoding check and no exception to catch for C functions

**Finding.** Every symbol in §4.12 is a C function found with `dlsym`. C functions have no runtime type encoding.
`KitEncoding` checks ObjC method encodings only (`method_getTypeEncoding` via `SNEncoding.m`). There is no
`KitEncoding.Requirement` that can be "verified in S0" for `CGSHWCaptureWindowList`, and none that H3 can attach to
each symbol.

A C function called with the wrong prototype doesn't throw. It returns garbage, corrupts memory or crashes. Swift
can't catch an ObjC exception without a shim either, and none of these calls raises one. So, as the plan is written:

- "Any exception poisons it" (l.48) can't happen.
- B1's done-when "forced-exception poison path covered" (l.338) has nothing to force.
- The mitigation for the riskiest new symbol (§8 l.403, "Encoding check, poison, kill switch") is two-thirds empty.

Q6 stands. It needs a concrete meaning for C symbols. The house already has the pieces:

- `PrivateSymbolResolver` for presence and kill switch: `PrivateDisplayAPI` resolves C symbols this way, with no
  encoding check.
- `IconsCrashGuard` for a call that may crash: an in-flight marker, then `disabledBuild`.
- `IconsShimContract` for selftest lines and a DEBUG forced poison.

**Evidence.**
- PLAN:l.47-49, l.146-148 ("Each symbol gets a `KitEncoding.Requirement`"), l.272-273, l.338, l.403.
- `Kit/KitEncoding.swift:4`, `:94`, and `Sources/SNEncoding/SNEncoding.m:41`, `:59`: ObjC method encodings only.
- `App/Switcher/PrivateAPIs.swift:17-20` (`dlsym`), `:28-38` (prototypes), `:40-55` (the lookups, with
  `SLS…`→`CGS…` fallbacks).
- `App/Displays/Platform/PrivateDisplayAPI.swift:12-51`, `:77-112`, `:116-125`: C symbols with presence and kill
  switch, no encoding.
- `Kit/IconsEngineCore.swift:154-172`: `IconsCrashGuard.atStart(inFlight:disabledBuild:currentBuild:)`.
- `Kit/IconsShimContract.swift:54-80`, `App/Core/SelfTestLaunch.swift:73-82`: the launch line, the expect variable
  and the DEBUG `forcePoisonForSelfTest`.

**Proposal.**
> Replace the ground rule's first two sentences (l.47–48):
>
> "**Every private symbol** is resolved at runtime through `PrivateSymbolResolver`, behind its kill switch. ObjC
> symbols are checked against a `KitEncoding.Requirement`. C functions (all of §4.12) have no runtime encoding, so
> each one has:
> (a) a prototype pinned in Kit `WindowSymbolContract`, recorded per OS in STEP0-NOTES (S0-5);
> (b) a result check: a result that fails it poisons the symbol for the life of the process;
> (c) for `CGSHWCaptureWindowList`, a crash guard.
> A poisoned or crash-disabled symbol logs once (no names) and its feature falls back as §4.12 lists."
>
> Add to §4.12:
>
> "Result checks (Kit `WindowSymbolContract.check…`, Linux-tested on recorded fixtures):
> `SLSCopySpacesForWindows` must return a `CFArray` (type id checked) with count ≤ the ids passed in.
> `CGSHWCaptureWindowList` must return a `CFArray` of `CGImage` with count ≤ the ids passed in, and every side in
> 1…16384. `_AXUIElementGetWindow` is accepted only with `.success` and an id ≠ 0. `GetProcessForPID` and
> `_SLPSSetFrontProcessWithOptions` are accepted only with `noErr`. A second failure in a row poisons. A single
> `kCGErrorFailure` on a window that just closed doesn't.
>
> Crash guard `WindowCaptureCrashGuard` (the `IconsCrashGuard` shape). It writes `Windows.hwCapture.inFlight =
> <OS build>` before each private capture and clears it after. A marker left over at launch for the same build sets
> `Windows.hwCapture.disabledBuild`. Capture then stays on the SCK and last-seen path until the OS build changes, and
> the Dock Previews and Window Switcher pages show 'Thumbnails of minimized windows are off after a problem. Try
> Again'. To keep a defaults write off the hot path, the marker is written only until 20 captures have finished on
> the current build (`Windows.hwCapture.verifiedBuild`). After that it isn't written.
>
> `PrivateWindowAPI.forcePoisonForSelfTest()` (DEBUG) poisons every symbol, and `--selftest-launch` checks that
> each one then reports `poisoned` and that its fallback answers."
>
> B1's done-when becomes P-8's.

### P-3 · Blocker · ground rules (l.50–51) vs §1 Raise (l.76) and §4.12 (l.268): "no synthetic events" contradicts the raise the plan reuses

**Finding.** The ground rule says "Snaptic never posts mouse or key events … Window actions use AX actions and
attributes only."

The raise the plan reuses (l.76, "Reuse the switcher's `WindowManager.focus` (same symbols, already shipped)") calls
`PrivateAPIs.bringToFront`. That function calls `_SLPSSetFrontProcessWithOptions` and then posts two `0xf8`-byte
**event records** (kinds `0x01`, `0x02`) to the target process with `SLPSPostEventRecordTo`, on every raise. §4.12
lists `SLPSPostEventRecordTo` as moved.

The rule is also false app-wide: Awake's `ActivitySimulator` posts events by design, and L2 allows that file to.
H8 says "L2 (synthetic events) is unchanged and must stay green". It will stay green, because L2 doesn't match
`SLPSPostEventRecordTo` at all, so the rule has no check.

DockDoor #1634, the reason for the rule, was a periodic synthetic event that kept displays awake. Nobody has
measured whether these window-server records count as user activity. S0-8 measures idle with the harness attached,
not after raises.

As written, the implementer must either break a ground rule or drop the raise on minimized and other-Space windows
(`kAXRaiseAction` can't reach other Spaces, P-25).

**Evidence.**
- PLAN:l.50-51, l.76, l.155-156, l.268, l.312 (S0-8).
- `App/Switcher/WindowManager.swift:501`: `if !PrivateAPIs.bringToFront(pid:windowID:) { app.activate() }`.
- `App/Switcher/PrivateAPIs.swift:8-10`: the comment "synthetic 'make key window' event record".
- `PrivateAPIs.swift:110-127`: `setFront(raw, windowID, 0x200)`, then two `postEvent(raw, buffer)` calls.
- `scripts/lint03.py:521-527`: L2 matches `IOPMAssertionDeclareUserActivity|\.post\(tap:|CGEvent\(mouseEventSource`
  outside `ActivitySimulator`, not `SLPSPostEventRecordTo`.
- `App/Awake/…/ActivitySimulator.swift:129-130`: the only `.post(tap:)`, allowed by L2.

**Proposal.**
> Replace the ground rule (l.50–51):
>
> "**No synthetic input.** Dock Previews and the window services never post HID or session events (`CGEventPost`,
> `CGEvent.post(tap:)`, `postToPid`, `IOHIDPostEvent`) and never run a periodic 'canary' (DockDoor #1634). Raising a
> window uses the switcher's shipped path: `_SLPSSetFrontProcessWithOptions` plus two `SLPSPostEventRecordTo` window
> records to the target process, then `kAXRaiseAction`. It runs only on a user's click or Return, never on a timer,
> and has the kill switch `Windows.disable.raise`. Awake's `ActivitySimulator` is the one place that posts input, by
> design, and is untouched."
>
> Extend S0-8:
>
> "…and after 50 raises through the harness's copy of `bringToFront`: `ioreg -c IOHIDSystem | grep HIDIdleTime`
> keeps growing from the last raise, the display sleeps on schedule, and `pmset -g assertions` lists nothing from
> the harness. If the records reset idle time, §4.12 changes before B1."
>
> H8 adds to L2: `CGEventPost\b|postToPid|IOHIDPostEvent` are banned outside `ActivitySimulator`, and
> `SLPSPostEventRecordTo` is allowed only in `Windows/PrivateWindowAPI.swift`.

---

## Majors

### P-4 · Major · §4.2, §4.10, §4.11, K4, A2: the switcher's "Protect private windows" rule is missing, so the Dock shows and captures what the switcher hides

**Finding.** The switcher has a privacy rule the plan never mentions. With **Protect private windows** on (the
default):

- windows of the apps in `privateBundleIDs` are never captured, and their titles are replaced by the app name;
- windows whose title marks private browsing are shown as "Private window";
- browser windows with an unreadable title are marked private.

`isCapturable` excludes private windows, and SCK capture double-checks the block list.

The Dock design shows titles on cards (l.176), puts them in VoiceOver labels (l.253), captures minimized and
other-Space windows with the private API (Q3), and shares the cache with the switcher (l.226). As planned, a
password manager's minimized vault or a private browsing window gets a thumbnail and a readable title on hover. A
Dock capture could then reach the switcher's grid, which today would never capture it.

The rule lives in `SwitcherController` (app layer, switcher config), so the Dock can't call it. It has to move to a
shared, testable place. The settings belong to the switcher's store, which isn't loaded while the switcher module
is off.

**Evidence.**
- `App/Switcher/SwitcherController.swift:320-336`: `markPrivacy`.
- `SwitcherController.swift:534-540`: `capturePermitted` and `blockedBundleIDs`.
- `App/Switcher/WindowManager.swift:24`: `isPrivate`. `:33-35`: `isCapturable` excludes private, minimized and
  other-Space windows.
- `App/Switcher/ThumbnailStore.swift:85`, `:105`: `isOwned(… blockedBundleIDs:)`.
- `App/Switcher/Settings.swift:255-256`: `privateBundleIDs = Config.defaultPrivateApps`,
  `protectPrivateWindows = true`.
- `Kit/Controls/SwitcherAdvancedSheetControls.swift:51-55`.
- PLAN:l.176-177, l.226-227, l.253, l.258-259. `grep -n -i 'private\|protect' PLAN-draft.md` finds no privacy rule.

**Proposal.**
> Add to §4.2:
>
> "**Private windows.** Dock Previews follows the switcher's **Protect private windows** setting and app list. A
> private window gets the app icon, never a thumbnail (not even a last-seen one), and its title is replaced exactly
> as in the switcher: the app name, or 'Private window'. VoiceOver reads the same replacement. The setting stays on
> the Window Switcher's Advanced sheet, and the Dock Previews page links to it."
>
> Add to K4: "`WindowCatalogRules.privacy(window:settings:)` (moved from `SwitcherController.markPrivacy`; the
> browser list and private-title markers move with it) and `capturePermitted(window:)`, used by both clients and by
> `WindowCapture` before either capture path."
>
> Add to A1b: "`WindowServices` reads the switcher's privacy settings from the switcher config store, which the host
> already loads whether or not the switcher runs (confirm in A1a; if not, the two keys move to a shared store), and
> applies them to every lease."
>
> Add a manual check: "M35: a protected app's minimized window and a private browsing window show the icon and the
> replacement title in the Dock and then in the switcher."

### P-5 · Major · H3, B1: `PrivateAPIs.swift` holds more than window symbols, and its users are outside the switcher

**Finding.** H3 moves "the private window API" to `Windows/PrivateWindowAPI.swift` and swaps rule 11's allowlist.
The file also holds:

- `SystemHotkeys` (the ⌘⇥ takeover, with crash recovery);
- `HotkeyGuard` (heartbeat and release on signal);
- the PSN struct;
- three **public** Carbon functions loaded dynamically: `IsSecureEventInputEnabled`, `LMGetKbdType` and
  `KBGetLayoutType`. They back `PrivateAPIs.isISOKeyboard` and the secure-input check.

`AppDelegate` uses these at launch, at quit and in the signal handler, and the switcher's `Settings.swift` uses them
for key names.

Moving the whole file puts switcher-only hotkey policy under `Windows/`. Splitting it without a plan either needs a
second rule-11 allowlist entry or leaves a `dlsym` in `Switcher/`. Q6's "kill switch and selftest line for every
symbol" shouldn't reach the Carbon functions, which are public API.

**Evidence.**
- `App/Switcher/PrivateAPIs.swift:56-59`: the Carbon lookups, commented "Public Carbon APIs, loaded dynamically".
- `PrivateAPIs.swift:142`: `enum SystemHotkeys`. `:228`: `HotkeyGuard`.
- `App/Core/AppDelegate.swift:58` (`recoverFromPreviousRun`), `:71`, `:73` (guard start and beat), `:131-132`
  (restore and releaseAll at quit), `:221` (`releaseAll` in the signal handler, off the main thread).
- `App/Switcher/Settings.swift:37`, `:135`: `PrivateAPIs.isISOKeyboard`.
- `scripts/lint.sh:142-146`: rule 11 allows `dlsym` only in `PrivateDisplayAPI.swift` and
  `Switcher/PrivateAPIs.swift`.
- `scripts/stubs.tsv:127`: the `PrivateAPIs.swift` row.
- PLAN:l.110-111, l.146-148, l.264-270.

**Proposal.**
> Replace H3:
>
> "**H3. Private window API.** `Switcher/PrivateAPIs.swift` splits in two (B1a, a move with no behaviour change):
> - `Windows/PrivateWindowAPI.swift` holds every `dlsym`: the §4.12 symbols with their `SLS…`→`CGS…` fallbacks, plus
>   the three public Carbon lookups. The Carbon lookups get no kill switch and no contract row; they are public API.
> - `Switcher/SystemHotkeys.swift` holds `SystemHotkeys` and `HotkeyGuard` (policy, timers, crash recovery). It
>   calls `PrivateWindowAPI.setSymbolicHotKey(_:enabled:)` and `.isSymbolicHotKeyEnabled(_:)`.
>
> Call sites change in `AppDelegate` (l.58, 71, 73, 131–132, 221) and `Switcher/Settings.swift` (l.37, 135).
> Rule 11's regex swaps `Switcher/PrivateAPIs` for `Windows/PrivateWindowAPI`. `stubs.tsv` drops the
> `Switcher/PrivateAPIs.swift` row (l.127) and adds rows for both new files in the same commit. The selftest prints
> which variant resolved (`SLS` or `CGS`) for each symbol."

### P-6 · Major · H2, §2 (l.108–109), A1: `WindowServices` has no contract, and A1 is bigger than "no behaviour change"

**Finding.** "`WindowServices` counts who holds them: the first `acquire` starts them, the last `release` stops and
purges them" (l.130-131) is all the plan says. Today:

- `WindowManager.shared` and `ThumbnailStore.shared` are used directly at **22** call sites: 15 in
  `SwitcherController`, 7 in `WindowSwitcherModule`.
- The AX messaging timeout is set globally by the switcher's `start()` (P-24).
- `start()` also starts `HotkeyTap`, applies `SystemHotkeys`, runs a secure-input timer and owns the privacy
  observers. Only the last of these is shared.
- Thumbnails come in two pixel sizes: 2400 for the large preview and 640 for the grid.

A1's done-when (M1–M4 plus "leaks nothing") can't tell whether the second client works. With one client, a broken
refcount, a cross-client purge or a wrong pixel-size key all pass.

**Evidence.**
- PLAN:l.108-109, l.129-132, l.143-144, l.339.
- `App/Switcher/WindowSwitcherModule.swift:52` (AX timeout), `:57` (HotkeyTap), `:65` (`WindowManager.shared.start()`),
  `:66` (privacy observers), `:90-92` (restore, stop, purge), `:219` (`SystemHotkeys.apply`), `:225` (secure-input
  timer), `:300` (observers).
- `App/Switcher/SwitcherController.swift:567` (`maxPixels` 2400) and `:584` (`maxPixels` 640).
- `grep -c 'WindowManager.shared\|ThumbnailStore.shared'`: `SwitcherController.swift` 15, `WindowSwitcherModule.swift`
  7.

**Proposal.**
> Add to §2:
>
> "**`WindowServices` contract.**
> - `acquire(_ client: ModuleID, needs: WindowNeeds) -> WindowLease` and `release(_:)`.
> - `WindowNeeds` is a set: `.recency` (MRU and focus tracking), `.freshness` (the extra AX notifications, P-1),
>   `.thumbnails`, `.otherSpaces`. Observers run for the union of live leases and are removed when no lease asks for
>   them.
> - The first lease starts `WindowManager`, sets the AX messaging timeout (P-24) and, if any lease asks for
>   thumbnails, the lock, sleep and fast-user-switching observers. The last release stops them and purges.
> - The cache is keyed by `(windowID, pixel bucket)`, with buckets 640 and 2400 for the switcher and the Dock's card
>   size. Entries are tagged by client, `generation` and `prune` are per client, `release` purges that client's
>   entries, and lock, sleep and fast user switching purge all.
> - `WindowServices.liveLeases` and `ThumbnailStore.liveEntries` are counters for selftests and diagnostics.
> - Stay in the switcher: `HotkeyTap`, `SystemHotkeys`, the secure-input timer, `WindowGatherer`.
> - The refcount and needs-union logic is a Kit value type, `WindowLeaseLedger`, tested on Linux."
>
> Split A1 (size **L** in total):
> - **A1a**: the switcher moves onto `WindowServices` as its only client. All 22 call sites go through the lease,
>   with no behaviour change. Done when M1–M4 pass, `--selftest-launch` prints `windows leases 0` after building the
>   modules, and `WindowLeaseLedgerTests` pass.
> - **A1b**: second-client semantics (client tags, per-client generation and prune, needs union). Done when
>   `ThumbnailStoreClientTests` pass. These are app-side unit tests behind a protocol seam, run on macOS CI: a
>   switcher purge leaves Dock entries, a Dock `invalidate` leaves a switcher capture in flight, and the last
>   release empties the store.

### P-7 · Major · H6 (l.151–152): kill switches can't be "read at start and observed while running"

**Finding.** In this codebase:

- `Modules.disable.*` is read **once at launch** (N14). A module's switch takes effect at the next launch, and the
  `module disable` verb says so.
- Feature switches are polled every 1 s, because `DefaultsKeyObserver` refuses dotted keys (0.4 R3-30).

"Observed" therefore can't be built. It also hides two hazards:

- **`Windows.disable.symbolicHotKeys` must never block giving ⌘⇥ back.** If the switch gates every call, a user who
  sets it while ⌘⇥ is taken over loses ⌘⇥ until the next login. That breaks `restore()` at stop,
  `recoverFromPreviousRun()` at launch, `HotkeyGuard`'s timer and `releaseAll()` in the signal handler. The signal
  handler runs **off the main thread**, so the switch state must be readable there: a lock-protected static, not a
  main-actor store.
- **Raise and capture run while switches change.** A 1 s poll that changes `hwCapture` mid-capture needs a defined
  outcome.

**Evidence.**
- PLAN:l.151-152.
- `App/Core/ModuleHost.swift:126`: `KillSwitches.read` once in `init`.
- `ModuleHost.swift:563-569`: the `module disable` help ("takes effect at the next launch").
- 0.4 `PLAN.md` R3-30.
- `App/Core/AppDelegate.swift:58`, `:73`, `:131-132`, `:214-226` (the signal source on
  `.global(qos: .userInitiated)`).
- `App/Switcher/WindowSwitcherModule.swift:90`: `SystemHotkeys.restore()` in `stop()`.

**Proposal.**
> Replace H6:
>
> "**H6. Kill switches.**
> - `Modules.disable.dockPreviews` is read at launch like the other four. Its text and `module disable dock` say
>   'takes effect at the next launch'.
> - `Dock.disable.*` and `Windows.disable.*` are polled every 1 s (R3-30) by one timer owned by `WindowServices`
>   while any lease exists, and read once at each `start()`. The result is published to `WindowKillSwitches.current`,
>   a lock-protected static that any thread may read. Each private call reads it on entry. A call already running
>   finishes; the next one falls back.
> - `Windows.disable.symbolicHotKeys` blocks only *taking* ⌘⇥. Giving it back (`restore`,
>   `recoverFromPreviousRun`, the `HotkeyGuard` timer and `releaseAll`) always runs. Turning the switch on while ⌘⇥
>   is taken calls `restore()` once.
> - Each switch that changes while running logs one EventLog line, `windows.killSwitch.<name> on|off`."

### P-8 · Major · B1 done-when (l.338), H3 (l.148): the selftest criterion is wrong on CI and can't run locally inside B1

**Finding.** B1's done-when has three problems:

- **CI won't print `unavailable`.** "CI prints `unavailable` where expected" fails because the CI runners are
  `macos-15`, where every SLS symbol exists.
- **The local run is an owner check.** "Local 27.2 prints `available`" needs Snaptic quit, because
  `--selftest-launch` takes the instance lock and refuses while Snaptic runs. That made it an owner check at R in
  0.4 (R3-10).
- **The self-test can't call AX.** Lint rule 9 bans `AXUIElement` in `SelfTestLaunch.swift`, so
  `_AXUIElementGetWindow` can only be checked for presence there, never called.

There's no expect variable like `SNAPTIC_SELFTEST_EXPECT_ICONS_SHIM`, so CI can't tell a regression (`unavailable`
on 15) from the expected state.

**Evidence.**
- PLAN:l.148, l.338.
- `App/Core/SelfTestLaunch.swift:40-43`: "Snaptic is running; quit it first".
- `SelfTestLaunch.swift:73-82`: the shim's launch line, expect variable and DEBUG poison.
- `scripts/lint.sh:102-110`: rule 9.
- `.github/workflows/build.yml:244`, `:299`: `SNAPTIC_SELFTEST_EXPECT_ICONS_SHIM=unavailable` on both selftest steps.
- 0.4 `PLAN.md` R3-10.

**Proposal.**
> Replace B1's done-when:
>
> "`--selftest-launch` prints one line per §4.12 symbol from Kit `WindowSymbolContract.launchLines`, in the form
> `selftest-launch: windows <name> available|unavailable|disabled|poisoned [SLS|CGS]`. The checks are presence and
> pinned prototype only: no call into AX or TCC (rule 9) and no capture.
>
> CI sets `SNAPTIC_SELFTEST_EXPECT_WINDOWS_API=available` on both steps (`build.yml:244`, `:299`), because
> `macos-15` has every symbol. Any other state fails the run.
>
> The DEBUG poison path (`forcePoisonForSelfTest`) runs in the same selftest and must report every symbol `poisoned`
> with its fallback answering.
>
> `--selftest-launch` on 27.2 with Snaptic quit is an owner check at R, as in R3-10. B1 itself records a standalone
> probe on 27.2 (S0-5's harness) in STEP0-NOTES."

### P-9 · Major · H8 (l.155–156), every item: the lint and stubs scope isn't exact

**Finding.** H8 names L13, L14, L17, L20 and `SETTINGS_VIEWS` but not what each must match. As written:

- **L13** (no `NSHostingView` in menus) uses an explicit path list, so `Dock/UI/DockMenuRows.swift` isn't covered
  unless it is added.
- **L14** (`.common` run-loop modes) covers `Awake/`, `Icons/` and any basename containing "Menu". The Dock's hover
  timer, safety net and grace timer in `Dock/` aren't covered. They matter: with a Dock context menu open, the run
  loop is in tracking mode.
- **L17** names Kit files by prefix (`Awake`, `Icons`, `KnownMenuBarHiders`, `ConfigAwake`, `ConfigIcons`).
- **L20** (no names in logs) checks `ICONS_DIR` only. The ground rule (l.54) covers Dock Previews and the window
  services. `Switcher/` has zero logging calls today, so extending L20 there costs nothing.
- **`L15_PENDING`** is the mechanism for control tables that land before their views (K5 before A7). The plan
  doesn't use it.
- **Rule 11** must change with H3 (P-5).
- **Rule 10** exempts `PrivateSymbol` extensions. The new `PrivateSymbol` ids for the window symbols rely on that
  exemption.
- **`stubs.tsv`** rows: the plan says "its new files' rows" but not the `PrivateAPIs.swift` removal.

**Evidence.**
- PLAN:l.56-57, l.155-156, l.326-328.
- `scripts/lint03.py:564-570` (L13 list), `:571-575` (L14 scope), `:494-495` (`is_menu_file`), `:498-500`
  (`SETTINGS_VIEWS`), `:588-597` (L17 prefixes), `:722-724` (L20 `ICONS_DIR`), `:1470-1474` (`L15_PENDING = set()`).
- `scripts/lint.sh:112-121` (rule 10, `exempt = {"PrivateSymbol"}`), `:142-146` (rule 11).
- `grep -nE '(NSLog|os_log|print|debugPrint|dump)\(' Sources/Snaptic/Switcher/*.swift` finds nothing.
- `scripts/stubs.tsv:127`.

**Proposal.**
> Replace H8 with this table. Each row lands in the item named.
>
> | Rule | Change | Item |
> |---|---|---|
> | L2 | P-3's extension (`CGEventPost`, `postToPid`, `IOHIDPostEvent` banned; `SLPSPostEventRecordTo` only in `Windows/PrivateWindowAPI.swift`) | B1a |
> | L13 | add `Sources/Snaptic/Dock/UI/DockMenuRows.swift` to the explicit list | K1 (rule), A7 (file) |
> | L14 | add `under(p, "Dock/") or under(p, "Windows/")` | K1 |
> | L15 | `L15_PENDING` gains `DockPageControls`, `DockAdvancedSheetControls`, `DockMenuRowsControls` | K5 (add), A7 (empty again) |
> | L17 | add `Dock/`, `Windows/`, Kit basenames starting `Dock`, `KnownDockTools`, `WindowCatalogRules`, `WindowSymbolContract`, `WindowLeaseLedger`, Config `ConfigDock` | K1 |
> | L20 | scope becomes `Icons/`, `Dock/`, `Windows/` and `Switcher/` (zero hits there today) | K1 |
> | `SETTINGS_VIEWS` | add `"Dock/UI/"` | K1 |
> | rule 11 | `Switcher/PrivateAPIs` → `Windows/PrivateWindowAPI` | B1a |
> | rule 10 | keep the `PrivateSymbol` exemption; the new symbol ids are `extension PrivateSymbol` in `PrivateWindowAPI.swift` | B1b |
> | stubs.tsv | B1a removes `Sources/Snaptic/Switcher/PrivateAPIs.swift` (l.127) and adds `Windows/PrivateWindowAPI.swift` and `Switcher/SystemHotkeys.swift`; every later item adds its rows in the commit that creates the file | each |

### P-10 · Major · H1 (l.138–142), K1, A6: the grep misses host wiring that 0.4 also missed, and three non-switch sites need a decision

**Finding.** The H1 grep finds 1177 hits in 192 files at `7dd972c`; Appendix A gives a disposition for each site. Most
hits are member accesses unrelated to `ModuleID`. The sites that matter most aren't hits:

- the `ModuleID` declaration itself (`KitModules.swift:19`) and `properNames` (`:31-34`);
- `EventCategory`;
- `SettingsRootID.groups` and the aliases;
- `KitBackup` sections and allowlist, plus `Backup.swift` export and import (missed in 0.4 until D1: R3-81);
- the store's `init`, `runMigrations`, shutdown flush, `resetAllSettings` and Safe Mode;
- `HostReport.sections(awake:icons:)`;
- `ModuleContext`;
- the Safe Mode details in General → Advanced;
- the General page search keywords.

Three hits aren't exhaustive switches, so the compiler won't flag them, and each is wrong for Dock Previews as-is:

- **`MenuPresence.fallback(for:)`** returns `.ownIcon` for every module except Hidden Icons. For `dockPreviews`
  (allowed `[.inSnapticMenu, .hidden]`), sanitizing a bad value gives `.ownIcon`: not allowed, and the module has no
  icon. It must return `.hidden`.
- **`MenuPlacement.help`** gives `.hidden` the text "Use the keyboard shortcut or Settings to reach it". Dock
  Previews has no shortcut.
- **`showSnapticMenu()`** moves every hidden module into the Snaptic menu except Awake. Dock Previews defaults to
  `.hidden`, so this would move it unasked. It should be excluded the way Awake is.

`ModuleHost.module(_:)` is an exhaustive switch that needs an object for every id from K1 on. The module class
doesn't exist until A6, so K1 needs an inert `DockPreviewsModule` shell.

**Evidence.**
- PLAN:l.138-142, l.333.
- `Kit/KitModules.swift:19`, `:31-34`, `:112-114` (`id == .hiddenIcons ? .inSnapticMenu : .ownIcon`), `:240-252`.
- `Kit/SettingsShellRules.swift:18` (groups), `:22-23` (aliases).
- `Kit/KitBackup.swift:36-63`, `:130-146`. `App/Core/Backup.swift:12`, `:52`, `:150-151`, `:191`.
- `Kit/SettingsPageRules.swift` ≈`:90-93` (`HostReport.sections(… awake: icons:)`).
- `App/Core/ModuleHost.swift:118-150` (stores), `:400-412` (shutdown flush), `:418-425` (`modules` and the
  exhaustive `module(_:)`), `:563-569` (`module disable` aliases and help).
- `App/Core/ModuleContext.swift:23`, `:27`. `App/Core/ModuleContracts.swift:98`.
- `App/Core/GeneralAdvancedSheet.swift:69-70`. `Kit/Controls/GeneralPageControls.swift:20` (keywords).
- `App/Core/MenuPlacement.swift:36`. `App/Core/MenuBarPage.swift:306-311`.
- 0.4 `PLAN.md` R3-81.

**Proposal.**
> Change H1's grep to the wider one in Appendix A. Make "every exhaustive `switch` over `ModuleID`, `NewModuleCard`
> or `SettingsRootID` is filled" a K1 compile step.
>
> Add three sentences to H1:
> - "`MenuPresence.fallback(for: .dockPreviews)` is `.hidden`."
> - "`MenuPlacement.help(.hidden, .dockPreviews)` is 'Open Dock Previews from Settings.'"
> - "`showSnapticMenu()` skips `.dockPreviews` as it skips Awake."
>
> Add **H10. Store and host wiring** (K1 for Kit, A6 for app):
> - `DockConfig` store in `ModuleHost.init`, `runMigrations`, the shutdown flush, `resetAllSettings` and Safe Mode.
> - `KitBackup` section `dock` and allowlist, and `Backup.swift` export and import (R3-81); M34 checks both.
> - `HostReport.sections(… dock:)`.
> - `EventCategory.dock` and `properNames["dockPreviews"] = "Dock Previews"`.
> - `SettingsRootID.dockPreviews` in groups, with alias `dock`.
> - The `module disable` alias `dock` and its help line.
> - `ModuleSwitchRow` text, `SettingsShell` icon, the General page card strings, `GeneralPageControls` keywords and
>   `MenuBarPageControls` `dockPresence`.
> - The Safe Mode details text.
>
> K1 adds an inert `Dock/DockPreviewsModule.swift`: `start()` and `stop()` do nothing, `state == .stopped`, and
> `requiredPermissions` is `[.accessibility]`. It fills `module(_:)` until A6.
>
> The Menu Bar page's per-module rows filter out `.dockPreviews` until A7.

### P-11 · Major · ground rules, A6 ("Safe Mode"), M33: Safe Mode doesn't protect against the new private capture

**Finding.** Safe Mode skips Displays restores, Awake rules and icon hiding. It keeps "The window switcher and your
shortcuts" running.

After A2, the switcher itself calls `CGSHWCaptureWindowList` for minimized and other-Space thumbnails (§4.11). Safe
Mode therefore still runs the one new crash-prone call. Safe Mode also triggers only on two launches that each end in
under 60 s. A crash on the first hover of a minimized window, minutes after launch, never triggers it.

M33 checks only that Dock Previews doesn't start in Safe Mode.

**Evidence.**
- `App/Core/SafeMode.swift:3-5` (the 60 s rule), `:19-29` (`skipped`), `:31-34` (`stillRuns` includes "The window
  switcher and your shortcuts").
- `App/Core/GeneralAdvancedSheet.swift:69-70`: the two lists shown to the user.
- `App/Icons/IconsModule.swift:167`: Hidden Icons checks Safe Mode itself, so the host doesn't skip modules
  generically.
- PLAN:l.255-260, l.344, l.393.

**Proposal.**
> Add to A6:
>
> "In Safe Mode, Dock Previews doesn't start and `WindowCapture` uses SCK and last-seen only: no
> `CGSHWCaptureWindowList` call, whatever the kill switch says. `SafeMode.skipped` gains 'Dock Previews' and
> 'Thumbnails of minimized and other-Space windows'. P-2's crash guard covers crashes after the first 60 s."
>
> Extend M33: "…and the switcher in Safe Mode shows minimized windows with the last-seen thumbnail or the icon.
> Diagnostics show 0 private captures."

### P-12 · Major · §5 (l.300–301), §6: the S0 gate comes after the items that need its results

**Finding.** "Any failed Blocker row changes the plan before A3 starts" (l.301). But K2, K3, K4, B1, A1 and A2 all
come before A3 and are built on S0 results:

- K2's geometry needs the Dock frames, coordinate spaces, magnification and secondary-display results (S0-1, S0-2,
  S0-12).
- K3's policy needs selection timing, auto-hide behaviour, Mission Control signals and VoiceOver events (S0-2,
  S0-7, S0-13, S0-16).
- K4 needs S0-10.
- B1 and A2 need S0-4 and S0-5.

A failed S0-2 (no selection notification on 15) would void K2, K3 and A3. Nothing maps rows to the items they
decide. The macOS 15 VM is assumed but not provided.

**Evidence.** PLAN:l.298-320 (rows), l.301 (gate), l.332-351 (order).

**Proposal.**
> Replace l.301:
>
> "Rows S0-1, S0-2, S0-4, S0-5, S0-10 and S0-12 have results before K2 starts. Every other row has a result before
> the item it decides:
>
> | Row | Decides |
> |---|---|
> | S0-1, S0-2, S0-12 | K2 |
> | S0-2, S0-7, S0-13, S0-16 | K3 |
> | S0-10 | K4 |
> | S0-15 | K1 (`KnownDockTools`) |
> | S0-4, S0-5 | B1, A2 |
> | S0-3, S0-14 | A3 |
> | S0-6, S0-11 | A4 |
> | S0-9 | A5 |
> | S0-8 | raise (P-3), A3 |
>
> A failed Blocker row stops the items it decides until §R2 records the change. If no macOS 15 VM is available, the
> 15 leg of each row is an owner check before R, and the row records it as pending."

### P-13 · Major · §2 (Kit), K1–K5 done-whens: the Kit items lack the value types their tests need, and "tests pass" verifies nothing

**Finding.** The Kit files can't take the types the app uses:

- `WindowItem` holds `AXUIElement` and `NSImage`.
- Frames are `CGRect` in AX (top-left) or Cocoa (bottom-left) coordinates. Lint rule 3 keeps AppKit and CG out of
  Kit. Hidden Icons uses `IconsRect` for the same reason.
- K3's "no wall clock" and its race table need time and scheduling as inputs.

None of these types is in §2. The done-whens "`DockGeometryTests` pass", "`DockPreviewPolicyTests` pass" and
"`WindowCatalogRulesTests` pass" are met by an empty test file.

**Evidence.**
- PLAN:l.92-105, l.125-127, l.334-337.
- `App/Switcher/WindowManager.swift:20-40` (`WindowItem`).
- `Tests/IconsLayoutTests.swift:408` (`IconsRect`).
- `scripts/lint.sh` rule 3.

**Proposal.**
> Add to §2's Kit block:
> - `DockModel.swift` also holds `DockRect` (Kit's own rect; AX top-left and Cocoa bottom-left conversion functions,
>   given the primary screen height) and `DockScreen` (frame, visible frame, scale).
> - `WindowCatalogRules.swift` takes `CatalogWindow`: id, pid, `hasTitle`, `minimized`, `hidden`, `onScreen`,
>   `spaceKnown: Bool?` (nil when the SLS symbol is off), `fullscreen`, `layer`, `bounds: DockRect`, `isPrivate`,
>   `hasAXElement`.
> - `DockPreviewPolicy` takes `now: TimeInterval` on every event and returns `schedule(after:token:)` commands. It
>   never reads a clock.
>
> Replace the K done-whens with "the named tests in Appendix B exist and pass on Linux CI". Appendix B lists them.

### P-14 · Major · §4.1 rule 4 (l.171–172), §4.4 (l.199–209), §2 events (l.125–127): the pointer, tick and Mission Control sources aren't specified

**Finding.** The policy takes `pointerMoved` and `tick` events, but nothing says where they come from or when they
exist. Three rules depend on them:

- §4.1 rule 4 needs the last pointer exit from the Dock's frame.
- The safety net ("outside … for 1 s") needs a pointer position and a clock.
- Mission Control is "detected by its window appearing" (l.208), with no named source.

DockDoor's lesson is "event-driven AX beats polling" (l.84). A global `mouseMoved` monitor left on would be a steady
cost while the module is on and idle. The ground rule says nothing about cost while on and idle.

The right-click menu runs a tracking loop. Without a rule, the safety net could hide the panel under an open menu, or
the timers could stall (P-9, L14).

**Evidence.**
- PLAN:l.84, l.125-127, l.164-172, l.199-209.
- `scripts/lint03.py:571-575` (L14: timers in `.common` modes for menus).

**Proposal.**
> Add to §4.4:
>
> "**Sources.**
> - `pointerMoved` comes from an `NSEvent` global and local `.mouseMoved` monitor. It is installed when the Dock's
>   selection becomes an app item and removed when the panel hides and no hover is pending.
> - `tick` comes from one 10 Hz `.common`-mode timer that exists only while the panel is shown or a show or hide is
>   pending.
> - Rule 4 uses `NSEvent.mouseLocation` read once when the selection changes.
> - Mission Control, App Exposé and Launchpad are detected by S0-13's signal. If S0-13 finds none, the safety net
>   covers them.
> - While the panel's context menu is open, the safety net and the grace timer are suspended. They restart when the
>   menu closes.
> - While the module is on and nothing is hovered, the only live source is the Dock AX observer."
>
> Add a manual check: "M36: on and idle for 10 minutes, Snaptic's idle wake-ups (`top -stats pid,idlew`) are within 1
> per second of the module being off."

### P-15 · Major · A1, A6, M32: "leaks nothing" has no measurement

**Finding.** A1 says "on/off 20× leaks nothing". A6 says "with no leaked observer, tap, panel or timer". M32 says
"Activity Monitor + EventLog". None names a counter.

0.4 settled this:

- A live counter checked by `--selftest-launch` after the modules are built (`IconsItems.liveCount`).
- The 20-cycle check is manual at R, because self-tests may not call AX or TCC and the module's `start()` does
  (R3-39).

**Evidence.**
- PLAN:l.339, l.344, l.392.
- `App/Core/SelfTestLaunch.swift:69-71` (the `icons items` line).
- `App/Icons/IconsItems.swift` (`liveCount`).
- 0.4 `PLAN.md` R3-39.

**Proposal.**
> Add to A6:
>
> "Live counters (counts only): `DockObserver.live`, `DockClickTap.live`, `DockKeys.live`, `DockPreviewPanel.live`,
> `DockPreviewController.timers`, `WindowServices.liveLeases`. `--selftest-launch` prints `selftest-launch: dock live
> <observer> <tap> <keys> <panel> <timers> <leases>` after building the modules, and all must be 0.
> `snaptic dock status --json` reports the same counters."
>
> Replace the A1 and A6 done-whens' "20×" with: "The 20 on/off cycles are manual at R (R3-39). EventLog
> `dock.started` and `dock.stopped` counts match the cycles, and `dock status --json` shows every counter at 0 after
> the last stop."

### P-16 · Major · §4.3 keys (l.194–197), A5, M23: bare W, M and Q swallow typing, and Q quits an app with no modifier

**Finding.** Keys are live while the panel is visible and the pointer is in it (l.196). The panel is non-activating,
so the user's keyboard focus stays in another app.

A user typing in a text field, with the pointer resting over a Dock preview, loses every `w`, `m` and `q` keystroke
to `HotkeyTap`. `HotkeyTap` is an active session tap that swallows what it handles. Each `q` **quits the hovered
app**. M23 ("no key reaches the frontmost app while handled") makes the swallowing the pass condition.

The plan doesn't say which keys are consumed, or what happens under Secure Event Input. The switcher has a
secure-input timer because a key tap goes deaf under Secure Event Input.

Creating a new `HotkeyTap` on every pointer entry also churns `CGEvent.tapCreate`, which has its own 27.2 freeze
history.

**Evidence.**
- PLAN:l.194, l.196-197, l.383.
- `App/Switcher/HotkeyTap.swift:5-12` (it "can swallow the ones that belong to Snaptic"; the 27.2 freeze note),
  `:60-64` (`.cgSessionEventTap`, `.defaultTap`).
- `App/Switcher/WindowSwitcherModule.swift:225` (the secure-input timer).

**Proposal.**
> Replace the §4.3 keys row:
>
> "Keys while the pointer is in the panel: Esc hides; ←/→ (↑/↓ on side Docks) move the selection; Return raises;
> **⌘W** closes; **⌘M** minimizes; **⌘H** hides the app; **⌘Q** quits it. Only those keys are consumed, and only
> while a card is selected. Every other key passes through untouched."
>
> Add to the paragraph after it:
>
> "One `HotkeyTap` is created at `start()` while 'Keyboard in previews' is on and enabled only while the panel is
> visible and the pointer is in it. K3 emits `installKeys` and `removeKeys`. Under Secure Event Input the keys do
> nothing and the panel shows no hint. 'Switcher opened' is a dismiss reason."
>
> M23's pass condition becomes: "the listed keys act and aren't delivered; a plain `w`, `m`, `q` typed into a text
> field with the pointer over the panel arrive unchanged."

### P-17 · Major · §4.14 (l.286–289), A9, M31: the CLI exit codes and off-module answer don't follow the house rules

**Finding.** "Exit 2 with text when the module is off" contradicts two settled rules:

- An off module's verbs aren't registered, so they get the house "Unknown command. Run 'snaptic help' …" with exit 2
  (`usage`) and no custom text (0.4 §4.14, G-29).
- Refusals exit **5** (`ControlExit.unavailable`), not 2 (0.4 R3-1).

The plan defines no refusals for `pause` and `resume`. Examples: `resume` while paused because DockDoor runs, `pause
--minutes 0`, or `pause` while paused. A9's `dockCases` has no case list.

**Evidence.**
- PLAN:l.286-289, l.347, l.391.
- `Kit/KitControl.swift:76-92` (`ControlExit`: usage 2, refused 4, unavailable 5).
- 0.4 `PLAN.md:838`, `:1043` (`iconsCases`, "Unknown command"), `:1272` (R3-1).
- `App/Core/SelfTest.swift:279` (`iconsCases`).

**Proposal.**
> Replace §4.14:
>
> "`snaptic dock status [--json]`, `snaptic dock pause [--minutes N]` (N 1…1440), `snaptic dock resume`.
> - Module off: the verbs aren't registered, so the house 'Unknown command' with exit 2.
> - Usage errors (`--minutes 0`, `--minutes x`, unknown flag) exit 2.
> - `resume` while paused because another Dock tool runs is refused with exit 5: 'Paused while another Dock preview
>   tool runs. Turn on Run Both in Settings to use both.'
> - `resume` while paused for VoiceOver is refused the same way, with its own text.
> - `pause` while paused exits 0 and extends the timer. `resume` while not paused exits 0.
> - Needs Accessibility: exit 5, 'Dock Previews needs Accessibility.'"
>
> A9 adds `dockCases` to `--selftest-controls`: status, status `--json` keys, pause, pause `--minutes 5`, pause
> `--minutes 0` (2), resume, resume when not paused (0), and an unknown flag (2). M31 reads "every exit-2 and exit-5
> text".

### P-18 · Major · H7 (l.153–154), K1 done-when: the downgrade test can't run in the tree, and two pinned rules are missing

**Finding.** "A 0.5 config decodes with the 0.4.0 types" can't be an in-tree test, because the tree's types *are*
the 0.5 types after K1. The in-tree evidence already exists in a different form. `testA04ModulesFileDecodesWithUnknownValues`
shows the modules decoder drops an unknown module id and an unknown card. 0.4.0's `KitBackup.parseDocument` keeps
only allowlisted sections, so it ignores `dock`.

What's missing is the 0.5 version of these tests, and a real check against the 0.4.0 binary types.

Second, `KitBackup` silently drops any key containing `salt`, `trust`, `unlock`, `allow`, `secret` or `token`. A
natural name for **Run Both** (`allowOtherTools`) or for a VoiceOver setting (`trustVoiceOver…`) would vanish from
backups with no error. Hidden Icons pinned this with `testFieldNamesAvoidTheSensitiveFragments`.

**Evidence.**
- PLAN:l.153-154, l.333.
- `Tests/ConfigIconsTests.swift:278-287` (`testA04…`), `:100-108` (the fragments test).
- `Kit/KitBackup.swift:145-146` (`sensitiveKeyFragments`).
- `Tests/KitModulesTests.swift:38-51`, `Tests/SettingsShellRulesTests.swift:8-14`.
- `Tests/ConfigModulesTests.swift:13`, `:345`, `:373`, `:608`, `:621`, `:653`.
- `Tests/Support/ConfigFixtures.swift:94-98`.

**Proposal.**
> Replace H7's last clause and K1's done-when:
>
> "Pinned tests updated in K1: `KitModulesTests` (`allCases`, `allowed`, `fallback`), `SettingsShellRulesTests`
> (9 roots, groups), and `ConfigModulesTests` `:13` (fresh defaults exclude `.dockPreviews` as they exclude
> `.hiddenIcons`), `:345`, `:373`, plus Dock versions of `:608`, `:621` and `:653`. `ConfigFixtures.fullModules()`
> passes unchanged (Dock gets `.inSnapticMenu`).
>
> New: `ConfigDockTests.testA05ModulesFileDecodesWithUnknownValues` and
> `ConfigDockTests.testFieldNamesAvoidTheSensitiveFragments`. **Run Both** is stored as `runAlongsideOtherTools`.
>
> Downgrade: in a throwaway `git worktree` at `v0.4.0`, a one-off test decodes the 0.5 fixtures (modules file with
> `dockPreviews` and the `dockPreviews` card, a backup with a `dock` section) with 0.4.0's types and passes. The
> command and result go in `H1-SITES.md`. The worktree is deleted."

---

## Minors

### P-19 · Minor · §4.12 (l.269): `Windows.disable.spaces` doesn't remove badges; it lets phantom windows in

**Finding.** The badge comes from `!onScreen` (P-1). `isOnAnySpace` only filters, and it returns nil when the symbol
is missing. Both filters let nil through: `== false` at `:283` and `!= false` at `:451`. With the switch on, inactive
native tabs and helper windows come back as "Other Space" cards.

**Evidence.** `App/Switcher/WindowManager.swift:283`, `:451`. `App/Switcher/PrivateAPIs.swift:84-89` (nil when
missing). PLAN:l.269.

**Proposal.**
> §4.12 row: "`SLSMainConnectionID`, `SLSCopySpacesForWindows`: filters inactive native tabs and helper windows out
> of the other-Space list. `Windows.disable.spaces`: the other-Space list is dropped (no `CGWindowList`-only windows),
> not shown unfiltered."

### P-20 · Minor · §4.6 (l.226–227): the cache budget needs byte accounting and one age

**Finding.** `NSImage` has no byte size, and the store counts entries only. A 2x card thumbnail is about
640×500×4 ≈ 1.3 MB, so 120 entries is about 156 MB and the 96 MB cap governs. One 2400-pixel switcher preview
(≈13 MB) is 13% of the budget.

"Older than 30 s refresh" sits beside the store's 5-minute `maxAge`, and the plan doesn't say which one the shared
store enforces.

**Evidence.** `App/Switcher/ThumbnailStore.swift:21-22`. `App/Switcher/SwitcherController.swift:567`, `:584`.
PLAN:l.226.

**Proposal.**
> "Entries store their `CGImage`'s `bytesPerRow × height`. The LRU evicts by count (120) and bytes (96 MB). Entries
> over 16 MB aren't cached. Every entry expires after 5 minutes. 'Older than 30 s' means 'refresh in the background
> when shown', per client."

### P-21 · Minor · §4.2 (l.181–182), M19: "+N more opens the Window Switcher filtered to that app" has no entry point

**Finding.** The switcher opens only from its shortcuts. Its scopes are all windows, active app and current screen,
and `.activeApp` filters on the frontmost pid. No API opens it for another app, and the switcher module may be off.

**Evidence.** `App/Switcher/SwitcherController.swift:261-266`. PLAN:l.181-182, l.379.

**Proposal.**
> "'+N more' calls `SwitcherController.open(scope: .app(pid))` (new, A4b) when the switcher runs. When it's off, the
> card raises the app and the panel hides." Owner may instead cut the card (see the ordering note).

### P-22 · Minor · D2 (l.349): the version check isn't in `build-app.sh`, and the release notes have a fixed path

**Finding.** `scripts/build-app.sh` doesn't check the version. `build.yml` does, with E4's scheme: 0.5.0 must be 500.
The release job needs exactly one `RELEASE-NOTES-0.5.0.md` under `docs/design/0.5/` or `docs/design/0.5.0/`.

**Evidence.** `.github/workflows/build.yml:391-397`, `:752-760` (version), `:543-546`, `:1255-1258` (notes).

**Proposal.**
> D2 done-when: "`build.yml`'s version checks pass for 0.5.0/500; `docs/design/0.5/RELEASE-NOTES-0.5.0.md` exists
> (and no `docs/design/0.5.0/` copy)."

### P-23 · Minor · A7 done-when (l.345): name the grep test

**Finding.** "Every §4.13 string matches the code (grep test)" was pinned in 0.4 as a named Kit test over whole
literals (R3-67). Use the same name pattern so R can find it.

**Evidence.** 0.4 `PLAN.md` R3-67. PLAN:l.275-284, l.345.

**Proposal.**
> "`DockControlsTests.testEveryCanonicalStringIsInTheSources` passes (whole literals; counts and times as
> interpolations)."

### P-24 · Minor · §4.6 (l.224), A1: the 0.15 s AX budget is a global set only by the switcher

**Finding.** `AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), …)` runs in the switcher's `start()`. It
changes the process-wide default. With the switcher off, Dock Previews' AX calls run at the system default (≈6 s).
That breaks S0-14's "never blocks over 50 ms" and the plan's "budgeted (0.15 s)".

**Evidence.** `App/Switcher/WindowSwitcherModule.swift:52`. `App/Switcher/WindowManager.swift:170`. PLAN:l.224,
l.318.

**Proposal.**
> "`WindowServices` sets the system-wide timeout on the first lease. `DockReader` also sets 0.15 s on each element it
> creates (`AXUIElementSetMessagingTimeout(element, 0.15)`), so the budget holds whatever else changes the global."

### P-25 · Minor · §4.12 raise fallback (l.268), M16: the fallback can't reach other-Space windows

**Finding.** With `Windows.disable.raise` on, the fallback is `kAXRaiseAction` plus `activate`. Other-Space items have
no AX element (P-1), so a click only activates the app, and macOS picks the Space.

**Evidence.** `App/Switcher/WindowManager.swift:461`, `:501`. PLAN:l.268, l.376.

**Proposal.**
> §4.12: "…falls back to `kAXRaiseAction` + `activate`; other-Space windows then only activate their app (Known
> limitation, D1)." Add an M16 variant with the switch on.

### P-26 · Minor · §4.9, S0-9, H5: the listen-only mouse tap's permission isn't recorded

**Finding.** The plan assumes Accessibility covers a `.listenOnly` mouse tap. The house `Permission` enum has two
cases, and nothing records which TCC service a listen-only mouse tap needs on 27.2 and 15.

**Evidence.** `Kit/KitModules.swift:21` (`Permission`). PLAN:l.150, l.244-247, l.313.

**Proposal.**
> S0-9 adds: "Record which TCC service the listen-only mouse tap needs on 27.2 and 15 (Accessibility, Input
> Monitoring or none). If it needs one the `Permission` enum doesn't have, §4.9 changes before A5."

### P-27 · Minor · H6, §4.12: kill-switch names should be typed and documented

**Finding.** The switches are spelled as strings across H6 and §4.12. 0.4's switches are Kit enums read through
`KillSwitches.read(_, prefix:, as:)`, all in one defaults domain.

**Evidence.** `Tests/KitModulesTests.swift:128-132`. PLAN:l.151-152, l.264-270.

**Proposal.**
> "Kit `WindowFeature` (`hwCapture`, `axWindowID`, `raise`, `spaces`, `symbolicHotKeys`) and `DockFeature`
> (`clickActions`, `keys`), read with `KillSwitches.read(domain, prefix: "Windows"|"Dock", as:)`. D1's README
> kill-switch table gives one `defaults write` example per prefix."

---

## Ordering, dependencies and size

The order S0 → K1…K5 → B1 → A1 … works with these changes:

1. **S0 (M)** runs first. Its rows gate the items that need them (P-12), not just A3.
2. **K1 (M)**:
   - `ModuleID`, the pinned tests and the lint rows (P-9, P-18);
   - the `fallback(for:)`, help and `showSnapticMenu` fixes (P-10);
   - the inert module shell;
   - `DockConfig` and `KnownDockTools` (S0-15).
3. **K4 (M–L)** comes next, because A1b and A2 need `WindowCatalogRules`. That includes the privacy rule (P-4) and
   `CatalogWindow` (P-13).
4. **B1a (S–M)**: the `PrivateAPIs` split and move, and the L2 and rule 11 edits (P-3, P-5). No behaviour change.
5. **A1a (M)**: the switcher onto `WindowServices` as the only client (P-6).
6. **B1b (M)**: `WindowSymbolContract`, result checks, crash guard, typed kill switches, polling, selftest lines and
   the CI expect variable (P-2, P-7, P-8, P-27).
7. **A1b (M)**: second-client semantics.
8. **A2a (M)**: `WindowCapture` with SCK, last-seen and the cap of 4, plus the byte budget (P-20). Then **A2b (M)**:
   the `CGSHWCaptureWindowList` path behind B1b, with the Safe Mode rule (P-11).
9. **K2 (M), K3 (L) and K5 (M)** run in parallel any time after S0's gate rows. K5 adds the `L15_PENDING` entries.
10. **A6 shell (S)** comes before A3: the real module with stores, Backup, Safe Mode, kill switches and live
    counters, still drawing nothing. A3 and A4 can then run in the app. The rest of A6 (pauses, diagnostics) stays
    at the end.
11. **A3 (M)**, then **A4a (L**: panel, placement, cards, dismissal, M11–M15), then **A4b (L**: actions, header,
    menu, VoiceOver, M16–M22), then **A5 (M)**.
12. **A7 (L)**, **A8 (S)** and **A9 (S–M)** come next, then **D1 (M)**, **D2 (S)** and **D3 (S)**, then **R**.

The plan sizes nothing. In total this is about two releases' worth of 0.4 work: three L items (K3, A4a, A4b, with A7
the same size) and a dozen M. The critical path is S0 → K1 → K4 → B1a → A1a → B1b → A1b → A2b → A3 → A4a → A4b →
A5 → A7 → R.

**Cut candidates (the owner's call; Q2 put everything in scope):**

- "+N more → the switcher filtered" (P-21) needs a new switcher entry point. A plain "+N more" that raises the app
  costs nothing.
- Stage Manager (S0-11, M20) can be a Known limitation from the start.

Neither changes the architecture.

**Done-when table (proposed replacements).**

| Item | Draft done-when | Proposed |
|---|---|---|
| S0 | Every Blocker row has a result | Every row has a result on 27.2, and on 15 or marked as an owner check; the gate rows (P-12) are done before K2 |
| K1 | Every H1 site has a disposition; tests pass; 0.5 config decodes with 0.4.0 types | `H1-SITES.md` covers the wider grep (Appendix A); Appendix B K1 tests pass; the downgrade worktree result is recorded (P-18); lint rows land (P-9) |
| K2 | `DockGeometryTests` pass | Appendix B K2 tests pass |
| K3 | `DockPreviewPolicyTests` pass, including a race table | Appendix B K3 tests pass, including the race table; the policy has no clock and no `Date()` (grep) |
| K4 | tests pass; the switcher's current inclusion cases still hold | Appendix B K4 tests pass; the switcher's cases run through `WindowCatalogRules` (moved from the app, not copied) |
| K5 | `ControlsTests`, `MenuLayoutTests` pass; L15 passes | Appendix B K5 tests pass; `L15_PENDING` holds the three Dock tables |
| B1a | (part of B1) | Move only; M1–M4 pass; rule 11 and `stubs.tsv` updated |
| B1b | CI prints `unavailable`; local prints `available`; poison path covered | P-8's text |
| A1a | M1–M4; on/off 20× leaks nothing | M1–M4; `windows leases 0` selftest line; `WindowLeaseLedgerTests` |
| A1b | (part of A1) | `ThumbnailStoreClientTests` (P-6) |
| A2a / A2b | M5–M6 | M5–M6; byte-budget tests; Safe Mode capture rule; crash guard trips on a forced marker (DEBUG) |
| A3–A5 | M7–M26 | Unchanged, plus M23's new pass condition (P-16) and M36 (P-14) |
| A6 | On/off 20× with no leak | Live-counter selftest line (P-15); 20× manual at R |
| A7 | strings match (grep test); M27–M28 | `DockControlsTests.testEveryCanonicalStringIsInTheSources`; `L15_PENDING` empty; M27–M28 |
| A9 | M31 | `dockCases` pass (P-17); M31 |
| D2 | version checked by `build-app.sh` | P-22's text |

---

## Appendix B · Test lists per K item

**K1 (`ConfigDockTests`, plus the pinned files)**
- `testIDOrderAndRawValue`: `.dockPreviews` is last, with raw `dockPreviews`.
- `testAllowedContainsFallbackForEveryID`: for every id, `allowed(for:)` contains `fallback(for:)`. This catches
  today's `.ownIcon` fallback.
- `testFreshDefaultsDockOffAndHidden`.
- `testSanitizeOwnIconBecomesHidden`.
- `testDockCardGoesToUpgradersOnce`, `testDockCardSkipsFreshInstallsAcrossLaunches`,
  `testDockCardReachesZeroOneUpgraders`, `testSetEnabledClearsDockCard`.
- `testIconsNeedExternalDisplayIgnoresDockHidden` and `…CountsDockInMenu`.
- `testDockConfigDefaults`.
- `testSanitizeClampsDelayAndGrace`: delay 0…1, NaN → 0.2, ±∞ clamped; grace 0.1…1.
- `testLossyEnumsFallBack`, `testEmptyObjectDecodesToDefaults`, `testRoundTrip`,
  `testFieldNamesAvoidTheSensitiveFragments`, `testBackupAllowlistRoundTrip`.
- `testA05ModulesFileDecodesWithUnknownValues`, `testUnknownModuleIDsKept` (passed through on re-encode if the
  store does that today; otherwise dropped, as `testA04` pins).
- `testEventCategoryDockExported`.
- `KnownDockToolsTests`: ids unique, exact match only, Snaptic's own id excluded.
- `SettingsShellRulesTests`: 9 roots, groups order, `dock.…` resolves through the alias, bare `dock` doesn't, and
  `properNames["dockPreviews"] == "Dock Previews"`.

**K2 (`DockGeometryTests`)**
- Edge from the item frame for bottom, left and right, including a Dock on a secondary screen with negative x and a
  screen arranged above the primary.
- AX→Cocoa conversion with the primary height, round trip.
- Placement centred on the item, clamped to the visible frame with an 8 pt margin and 6 pt gap, at each screen edge.
- Magnified item frames.
- Grid: rows for bottom, columns for sides; "+N more" when cards exceed the visible frame; the compact card; aspect
  cap on very wide and very tall windows; RTL mirroring.
- A fuzz invariant over 10,000 random screens, items and counts: the panel lies inside the visible frame and never
  overlaps the item.

**K3 (`DockPreviewPolicyTests`)**
- Delay: show after 0.2 s; a new selection inside the delay restarts it; delay 0 shows at once.
- Swap: no delay while shown.
- A stale selection (older than the last exit `pointerMoved`) never shows.
- Corridor: inside keeps the panel; outside for 0.24 s keeps it, for 0.25 s hides.
- Re-entry inside grace cancels the hide.
- Safety net: 1 s outside the Dock and the panel hides whatever AX says.
- Click outside; action done.
- Context menu open suspends the timers, and closing restarts them.
- Every dismiss reason, mapped one to one to `hide(reason)`: activation, Space, display, lock, sleep, fast user
  switching, Mission Control, stop, kill switch, switcher opened.
- Auto-hide Dock: S0-7's recorded order.
- Pause precedence: kill switch > Safe Mode > other tool (unless Run Both) > VoiceOver (unless on).
- Keys: `installKeys` only while visible and the pointer is inside; `removeKeys` on either ending.
- Card click resolver table: left, middle, right with ⌥, ⌘, ⇧, and other-Space cards (raise only).
- Dock click resolver table.
- Generation tokens: a stale `schedule` token is ignored.
- Race table: hover → leave → hover inside one tick; swap during hide; `refresh` arriving after hide.

**K4 (`WindowCatalogRulesTests`)**
- Inclusion: minimized, hidden, windowless and full screen each on and off.
- Other-Space with and without a title; `spaceKnown == nil` (symbol off) drops `CGWindowList`-only windows (P-19).
- Native tab filtered.
- Privacy: protected app → no capture and the app-name title; private marker → "Private window"; browser with an
  empty title → private (P-4).
- Recency merge: MRU first, then unknown windows by z-order; the Title sort is case- and diacritic-insensitive.
- Badge precedence (Minimized > Hidden > Full Screen > Other Space).
- Freshness at 29.9 and 30 s.
- LRU by count and by bytes; oversize entries skipped.
- Per-client generation, prune and purge.
- Capture path choice: on-screen → SCK; minimized or other-Space → private if available, else last-seen, else icon.
- Concurrency cap of 4.
- `hasAXElement == false` → only the raise action offered.
- The switcher's current inclusion cases, moved here from the app.

**K5 (`DockCommandGrammarTests`, `MenuLayoutTests`, `DockControlsTests`)**
- Grammar: `status`, `status --json`, `pause`, `pause --minutes 1`, `--minutes 1440`, `--minutes 0` / `1441` / `x`
  (usage), `resume`, help text, unknown flag.
- `MenuLayout`: short title "Dock"; `ownIconIDs` never contains `.dockPreviews`, even with an unsanitized `.ownIcon`;
  tabs with five modules; the existing fuzz passes with five.
- Controls: unique ids; all registered; `dockPresence` present; canonical strings; master switch for the
  `dockPreviews` root (`SettingsIndexTests:197` pattern).
- The verbs are registered only while the module runs.

---

## Appendix A · H1 grep at `7dd972c`

The plan's pattern (PLAN:l.139):

```
grep -rnE '\.(windowSwitcher|displays|awake|hiddenIcons)\b|ModuleID\.allCases' Sources Tests
```

It finds **1177** hits in **192** files (0.4's grep found 1045).

| Disposition | Meaning |
|---|---|
| **K1** | changed in K1 (compiler-forced or listed) |
| **auto** | correct for `dockPreviews` with no edit; K1's tests pin it |
| **n/a** | about one other module, or not a `ModuleID` at all |
| **K5 / A6 / A7 / A8** | deferred to that item, which names it |

### Summary

| Bucket | Files | Hits | Disposition |
|---|---:|---:|---|
| `Kit/Controls/*` (control-table gates `.module(.displays)` and similar, plus string ids) | 51 | 256 | n/a, except `MenuBarPageControls.swift:45` → K1 adds `dockPresence` (A7 wires it) |
| `App/Displays/**` and `App/Awake/**` (member accesses such as `config.displays`, `host.awake`) | 76 | 263 | n/a |
| Kit outside Controls | 17 | 112 | per site, below |
| App `Core/`, `SettingsUI/`, `Icons/`, `Switcher/` | 23 | 142 | per site, below |
| Tests | 25 | 404 | per file, below |
| **Total** | **192** | **1177** | |

### Kit (outside `Controls/`)

| Site | Hits | Disposition | Note |
|---|---:|---|---|
| `KitModules.swift:104-106` | 3 | K1 | `allowed(for:)` switch: `.dockPreviews: [.inSnapticMenu, .hidden]` (compiler) |
| `KitModules.swift:113` | 1 | K1 | `fallback(for:)`: not a switch; must give `.hidden` (P-10) |
| `KitModules.swift:252` | 1 | n/a | `isExportedInDiagnostics` (Awake only); `.dock` is exported |
| `SettingsPageRules.swift:11-13` | 3 | K1 | card → root switch |
| `SettingsPageRules.swift:25-28` | 3 | K1 | card visibility switch |
| `SettingsPageRules.swift:38` | 1 | n/a | legacy `showNewDisplaysCard` |
| `SettingsPageRules.swift:44` | 1 | auto | counts `allCases` |
| `SettingsShellRules.swift:10-13` | 4 | K1 | add `SettingsRootID.dockPreviews` (groups `:18` and aliases `:22-23` aren't hits) |
| `SettingsShellRules.swift:134-150` | 4 | K1 | proper names; Dock sub-page anchors at A7 |
| `MenuLayout.swift:101-104` | 4 | K1 / K5 | `shortTitle` switch: "Dock" (compiler at K1; K5 tests) |
| `MenuLayout.swift:91, 284-309, 331, 361` | 11 | n/a | Awake and Displays rules |
| `MenuLayout.swift:310` | 1 | auto | start order |
| `MenuLayout.swift:315` | 1 | auto | the Hidden Icons arrow; Dock has none |
| `MenuLayout.swift:328` | 1 | K5 | `ownIconIDs` guard: add `id != .dockPreviews` (belt and braces with P-10) |
| `KitControl.swift:474` | 1 | auto | module names from `allCases`; the `dock` alias is at `ModuleHost.swift:569` |
| `Config/ConfigModules.swift:187-189` | 2 | n/a | Awake probe |
| `Config/ConfigModules.swift:226-228` | 3 | K1 | per-id defaults switch: `ModulePreferences(enabled: false, presence: .hidden)` |
| `Config/ConfigModules.swift:239-243` | 4 | n/a | 0.2 upgrade preferences |
| `Config/ConfigModules.swift:266-267` | 2 | auto | `enabledModules` in start order (`:266` is a comment) |
| `Config/ConfigModules.swift:273-275` | 2 | n/a | Displays card |
| `Config/ConfigModules.swift:278` | 1 | K1 | `setEnabled` clears the card: add `.dockPreviews` |
| `Config/ConfigModules.swift:305` | 1 | auto | sanitize loop |
| `Config/ConfigModules.swift:328-329` | 2 | A8 | onboarding steps: decide whether Dock adds a step or only a row in `.modules` (plan says a row) |
| `Config/ConfigModules.swift:424-429` | 3 | auto | `iconsNeedExternalDisplay`; K1 tests pin it |
| `Config/ConfigModules.swift:444-472` | 5 | n/a | M3 and 0.3 migrations |
| `Config/ConfigModules.swift:484-488` | 2 | K1 | Icons upgrader card: add the Dock analog with ledger `dockCard.v1` |
| `LayoutPresetModel` 14, `ConnectPlan` 10, `ProtectionDiff` 9, `AwakeFeatureGraph` 3, `AwakeTriggerEngine` 2, `Config/ConfigManagement` 2, `MigrationNotices` 1, `IconsModel` 1, `AwakeSnapshot` 1, `AwakeMigration` 1, `AwakeLogEvent` 1 | 45 | n/a | not `ModuleID` or one module only |

### App (`Core/`, `SettingsUI/`, `Icons/`, `Switcher/`)

| Site | Hits | Disposition | Note |
|---|---:|---|---|
| `Core/ModuleHost.swift:418` | 1 | auto | `modules` over `allCases` (needs the K1 shell) |
| `Core/ModuleHost.swift:422-425` | 4 | K1 | exhaustive `module(_:)`: the inert shell until A6 |
| `Core/ModuleHost.swift:568-569` | 2 | K1 | `module disable` aliases: add `dock`; help line |
| `Core/ModuleHost.swift:403, 466, 698, 727` | 4 | auto | start and stop order |
| `Core/ModuleHost.swift:718` | 1 | n/a | Icons store |
| `Core/ModuleHost.swift:137, 166-172, 307, 512, 604, 635` | 9 | n/a | Awake and Displays |
| `SettingsUI/ModuleSwitchRow.swift:25-28` | 4 | K1 | description switch |
| `SettingsUI/SettingsShell.swift:61-64` | 4 | K1 | sidebar icon and colour (dictionary, not a switch) |
| `SettingsUI/SettingsShell.swift:84` | 1 | auto | switcher page routing; other modules use `module.page` |
| `SettingsUI/SettingsShell.swift:403, 442` | 2 | n/a | Awake "new" badge |
| `SettingsUI/PerDisplayPicker.swift:21` | 1 | n/a | |
| `Core/GeneralPages.swift:102` | 1 | auto | module switches over `allCases` |
| `Core/GeneralPages.swift:123` | 1 | A8 | card action |
| `Core/GeneralPages.swift:251-272` | 9 | K1 | card title, text and button switches (final strings at A8) |
| `Core/MenuBarPage.swift:61` | 1 | K1 | per-module rows: filter out `.dockPreviews` until A7 |
| `Core/MenuBarPage.swift:145` | 1 | A7 | off help |
| `Core/MenuBarPage.swift:222-225` | 4 | K1 | presence control id switch: `menubar.page.dockPresence` |
| `Core/MenuBarPage.swift:231-233` | 3 | K1 | icon control id switch: `nil` |
| `Core/MenuBarPage.swift:310` | 1 | A7 | `showSnapticMenu` skips `.dockPreviews` (P-10) |
| `Core/MenuBarPage.swift:321-323` | 3 | K1 | symbol choices switch: `[]` |
| `Core/MenuBarPage.swift:28, 134, 152, 298` | 4 | n/a | |
| `Core/MenuPlacement.swift:14, 32` | 2 | K1 | titles and help: Dock's `.hidden` help (P-10) |
| `Core/MenuPlacement.swift:34-35` | 2 | n/a | |
| `Core/StatusMenu.swift:210` | 1 | auto | own items exclude Icons; Dock has none |
| `Core/StatusMenu.swift:484` | 1 | A7 | Snaptic-menu section for Dock |
| `Core/StatusMenu.swift` (16 others: Awake runtime, Displays card) | 16 | n/a | |
| `Core/Onboarding.swift:242` | 1 | A8 | module rows over `allCases`: Dock's opt-in row |
| `Core/Onboarding.swift:357` | 1 | A8 | the "start Icons after onboarding" analog |
| `Core/Onboarding.swift:180, 259, 267-268, 404` | 5 | n/a | Displays step |
| `Core/PermissionsPage.swift:127-128` | 2 | A7 | Icons row → Dock row (H5) |
| `Core/PermissionsPage.swift:105` | 1 | n/a | Drive Alive |
| `Core/AboutPage.swift:140-153` | 4 | A6 | `HostReport.sections(… dock:)` |
| `Core/AboutPage.swift:55` | 1 | n/a | |
| `Core/SelfTestLaunch.swift:66` | 1 | auto | module count (prints 5) |
| `Core/AppDelegate.swift:94-97` | 3 | n/a | Awake wiring |
| `Core/EventLog.swift:33`, `Core/SelfTest.swift:230` | 2 | n/a | Awake |
| `Core/CustomizeMenuSheet.swift` | 12 | n/a | Displays sections |
| `Icons/IconsItems.swift:149` | 1 | auto | own-item autosave names; Dock's is never present |
| `Icons/IconsModule.swift` 5, `Icons/UI/IconsPage.swift` 8, `Icons/IconsMenuRows.swift:61`, `Icons/UI/IconsSectionsPage.swift:38` | 15 | n/a | |
| `Switcher/SwitcherPages.swift` 8, `Switcher/WindowSwitcherModule.swift:11, 159` | 10 | n/a | |

### Tests

| File | Hits | Disposition |
|---|---:|---|
| `KitModulesTests.swift:40-50` | 7 | K1 (pinned `allCases`, `allowed`) |
| `KitModulesTests.swift` (other 7: cards, EventCategory, KillSwitches) | 7 | auto |
| `ConfigModulesTests.swift` | 154 | auto, except `:13`, `:345`, `:373` (K1, pinned; P-18); K1 adds Dock versions of `:608`, `:621`, `:653` |
| `SettingsShellRulesTests.swift:14` (`:8-13` not a hit) | 1 | K1 |
| `SettingsShellRulesTests.swift:54` | 1 | n/a |
| `Support/ConfigFixtures.swift:96` | 1 | auto (`allowed.first` = `.inSnapticMenu`) |
| `ConfigIconsTests.swift:286-303` | 8 | auto (K1 copies `:100` and `:278` for Dock) |
| `SettingsIndexTests.swift:195-210` | 9 | auto (K5 adds the Dock master switch) |
| `KitBackupTests.swift:260, 432` | 2 | auto (K1 adds Dock section tests) |
| `MenuLayoutTests.swift` 81, `MenuTabsTests.swift` 30 | 111 | auto (K5 adds Dock cases) |
| `SettingsPageRulesTests.swift` | 30 | auto (K1 adds the Dock card case) |
| `ConfigMenuTests` 16, `ConnectPlanTests` 16, `LayoutPresetModelTests` 7, `MigrationNoticesTests` 6, `ControlRegistryTests` 4, `IconsControlsTests` 4, `AwakeTriggerEngineTests` 3, `ConfirmChangesSectionControlsTests` 3, `IconsLayoutTests` 3, `IconsPolicyTests` 3, `AwakeMigrationTests` 2, `DisplaysMenuPlanTests` 2, `KitControlTests` 2, `AwakeSnapshotTests` 1, `ProtectionDiffTests` 1 | 73 | n/a |

### Sites the grep misses

| Site | Disposition |
|---|---|
| `Kit/KitModules.swift:19` (`enum ModuleID` cases), `:31-34` (`properNames`), `:240-252` (`EventCategory`) | K1 |
| `Kit/SettingsShellRules.swift:18` (groups), `:22-23` (aliases) | K1 |
| `Kit/KitBackup.swift:36-63`, `:130-146` (sections, allowlist) | K1 |
| `App/Core/Backup.swift:12`, `:52`, `:150-151`, `:191` (export and import; R3-81) | A6 |
| `Kit/SettingsPageRules.swift` ≈`:90-93` (`HostReport.sections`) | K1 (signature), A6 (lines) |
| `App/Core/ModuleHost.swift:118-150` (stores), `:400-412` (shutdown flush), `resetAllSettings`, `runMigrations` | A6 (H10) |
| `App/Core/ModuleHost.swift:563-567` (`module disable` help text) | K1 |
| `App/Core/ModuleContext.swift:23`, `:27`; `App/Core/ModuleContracts.swift:98` (doc lists the modules) | K1 |
| `App/Core/GeneralAdvancedSheet.swift:69-70`, `App/Core/SafeMode.swift:19-29` | A6 (P-11) |
| `Kit/Controls/GeneralPageControls.swift:20` (search keywords) | K1 |
| `Kit/Controls/MenuBarPageControls.swift:45` (presence controls; a hit, listed here for the new id) | K1 |
| `App/Switcher/PrivateAPIs.swift` users (P-5), `scripts/lint.sh:142-146`, `scripts/stubs.tsv:127` | B1a |
| README, guide, site, `MANUAL-CHECKS` counts (H9) | D1, D3 |

**Recommended grep for `H1-SITES.md`** (run with the K1 compile step):

```
grep -rnE '\.(windowSwitcher|displays|awake|hiddenIcons)\b|ModuleID\b|NewModuleCard|SettingsRootID\.|EventCategory|KitBackup\.|KillSwitches|iconsStore|SnapticIconsV1' Sources Tests
```

### Per-file index (all 192 files)

**n/a, `Kit/Controls/` (51 files, 256 hits):** `AboutPageControls` 1, `ActionEditorSheetControls` 2,
`ArrangeSheetControls` 3, `AutomationsPageControls` 12, `AwakeAdvancedSheetControls` 2, `AwakeHistoryPageControls` 2,
`AwakeMenuRowsControls` 31, `AwakePageControls` 2, `BrightnessAdvancedSheetControls` 2, `BrightnessSubpageControls` 2,
`ColorPageControls` 8, `ConfirmChangesSectionControls` 1, `ConnectionSectionControls` 5, `ControlLegacy` 5,
`CustomizeMenuSheetControls` 1, `DDCMenuItemsControls` 1, `DisplayDetailsSheetControls` 2,
`DisplayInformationPageControls` 4, `DisplayLiveControlsControls` 5, `DisplayMenuBlockControls` 1,
`DisplaysAdvancedSheetControls` 1, `DisplaysMenuBuilderControls` 26, `DisplaysOnboardingStepControls` 2,
`DisplaysPageControls` 14, `DrivesPageControls` 9, `HardwareControlsPageControls` 7, `HookEditorSheetControls` 2,
`IconsAdvancedSheetControls` 2, `IconsItemsControls` 1, `IconsMenuRowsControls` 1, `IconsPageControls` 2,
`IconsSectionsPageControls` 2, `IndicatorControllerControls` 3, `KeyboardPageControls` 8,
`MatchTextSizeSectionControls` 2, `MenuBarOverlaysSectionControls` 2, **`MenuBarPageControls` 15 (`:45` K1)**,
`OnboardingControls` 1, `OverviewMenuItemsControls` 3, `PIPEditorSheetControls` 1, `PIPPageControls` 9,
`PresetEditorSheetControls` 3, `ResolutionMenuItemsControls` 1, `ResolutionSectionsControls` 13,
`SavedLayoutsPageControls` 14, `SwitcherAdvancedSheetControls` 1, `SwitcherPageControls` 1,
`SwitcherShortcutsSheetControls` 2, `TriggerEditorSheetControls` 3, `VirtualDisplayEditorSheetControls` 2,
`VirtualDisplaysPageControls` 11.

**n/a, `App/Awake/` (13 files, 58 hits):** `AwakeContext` 2, `AwakeModule` 2, `Core/HistoryController` 1,
`Core/LidClosedController` 3, `Sources/AudioMonitor` 1, `Sources/BluetoothPresence` 1, `Sources/DisplayPresence` 1,
`Sources/OtherAssertionsReader` 1, `Sources/VolumeMonitor` 1, `UI/AwakeMenuRows` 30, `UI/AwakePage` 13,
`UI/CriterionEditors` 1, `UI/IndicatorController` 1.

**n/a, `App/Displays/` (63 files, 205 hits):** `Automation/AutomationController` 1, `Brightness/AppleBrightnessIO` 1,
`Brightness/BrightnessController` 2, `Brightness/BrightnessService` 2, `Brightness/ColorController` 4,
`Brightness/ColorSyncService` 1, `Brightness/GammaService` 1, `Brightness/MenuBarOverlaysController` 1,
`Brightness/SyncController` 3, `Brightness/SystemColorsController` 2, `Brightness/XDRController` 4,
`DDC/DDCController` 5, `DDC/DDCService` 1, `DisplaysContext` 1, `DisplaysModule` 3, `Input/KeysController` 10,
`Input/OSDController` 1, `Management/ArrangementController` 6, `Management/ConnectPlanner` 3,
`Management/LayoutsController` 8, `Management/ManagementSupport` 7, `Management/PanelPropsController` 1,
`Management/PowerController` 6, `Management/ProtectionController` 1, `Management/ResolutionController` 5,
`Management/SmartHiDPIController` 5, `Management/VirtualController` 7, `PIP/CaptureService` 1, `PIP/PIPController` 5,
`UI/ArrangeSheet` 4, `UI/ArrangementCanvas` 1, `UI/AutomationsPage` 1, `UI/BrightnessAdvancedSheet` 1,
`UI/BrightnessSections` 1, `UI/BrightnessSubpage` 2, `UI/ColorPage` 3, `UI/ConfirmChangesSection` 2,
`UI/ConnectionSection` 2, `UI/DiagnosticsController` 1, `UI/DisplayDetailsSheet` 2, `UI/DisplayInformationPage` 3,
`UI/DisplayLiveControls` 2, `UI/DisplayPageSupport` 3, `UI/DisplaysMenuBuilder` 35, `UI/DisplaysOnboardingStep` 3,
`UI/DisplaysPage` 9, `UI/HardwareControlsPage` 4, `UI/HookEditorSheet` 2, `UI/KeyboardPage` 4,
`UI/KeyboardShortcutsSheet` 2, `UI/ManagementMenuItems` 1, `UI/MatchTextSizeSection` 2,
`UI/MenuBarOverlaysSection` 1, `UI/OverviewController` 1, `UI/PIPMenuItems` 1, `UI/PIPPage` 4,
`UI/ResolutionFiltersSection` 1, `UI/ResolutionMenuItems` 1, `UI/ResolutionOptionsSection` 1,
`UI/ResolutionSections` 3, `UI/SavedLayoutsPage` 1, `UI/VirtualDisplayEditorSheet` 2, `UI/VirtualDisplaysPage` 1.

**Kit outside Controls (17 files, 112 hits):** per-site table above. **K1**: `KitModules` 5, `SettingsPageRules` 8,
`SettingsShellRules` 8, `MenuLayout` 18, `Config/ConfigModules` 27, all mixed with auto and n/a lines. **auto**:
`KitControl` 1. **n/a**: `LayoutPresetModel` 14, `ConnectPlan` 10, `ProtectionDiff` 9, `AwakeFeatureGraph` 3,
`AwakeTriggerEngine` 2, `Config/ConfigManagement` 2, `MigrationNotices` 1, `IconsModel` 1, `AwakeSnapshot` 1,
`AwakeMigration` 1, `AwakeLogEvent` 1.

**App `Core/`, `SettingsUI/`, `Icons/`, `Switcher/` (23 files, 142 hits):** per-site table above. **Mixed (K1, A6, A7,
A8, auto)**: `Core/ModuleHost` 21, `Core/MenuBarPage` 17, `Core/StatusMenu` 18, `Core/GeneralPages` 11,
`Core/Onboarding` 7, `Core/AboutPage` 5, `Core/MenuPlacement` 4, `Core/PermissionsPage` 3,
`SettingsUI/SettingsShell` 7, `SettingsUI/ModuleSwitchRow` 4. **auto**: `Core/SelfTestLaunch` 1,
`Icons/IconsItems` 1. **n/a**: `Core/CustomizeMenuSheet` 12, `Core/AppDelegate` 3, `Core/EventLog` 1,
`Core/SelfTest` 1, `SettingsUI/PerDisplayPicker` 1, `Icons/IconsModule` 5, `Icons/UI/IconsPage` 8,
`Icons/IconsMenuRows` 1, `Icons/UI/IconsSectionsPage` 1, `Switcher/SwitcherPages` 8,
`Switcher/WindowSwitcherModule` 2.

**Tests (25 files, 404 hits):** per-file table above.
