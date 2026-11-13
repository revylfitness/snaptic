# 0.5 plan review r1: Adversarial (failure modes, races, private APIs, privacy)

Reviewer: adversarial subagent. Plan: `docs/design/0.5/PLAN-draft.md` (r1 draft, 425 lines). Grounding: the Snaptic
tree at `7dd972c` on `feature/v050-dock-previews` (Switcher, Icons, Core, SnapticKit, SnapticShims),
`docs/design/macos27.md`, the 0.4 adversarial review and `docs/design/0.4/PLAN.md` for precedent, `scripts/lint.sh`
and `scripts/lint03.py`, and one read-only fact from this Mac (macOS 27.2, 26B123): the Dock's `Info.plist`. Nothing
was launched, signalled, tapped or captured. No DockDoor or AltTab source was read; DockDoor appears here only
through the behaviour that the plan's §1 records. The owner decisions Q1–Q7 are settled. These findings are about
how the plan carries them out. Citations: `PLAN:l.N` is a line of the draft; `path:line` is a line of the tree.

Severity counts: **3 Blockers, 17 Majors, 13 Minors.**

## What the code already does (context for the findings)

- **Every switcher "private symbol" is a C function.** They are resolved with `dlsym` and `unsafeBitCast` to
  `@convention(c)` types (`Switcher/PrivateAPIs.swift:12–20,27–58`). There's no ObjC boundary, so there's no type
  encoding to read and no exception to catch. `KitEncoding` compares ObjC method encodings only
  (`SnapticKit/KitEncoding.swift:3–5`).
- **Safe Mode keeps the switcher running.** It runs "The window switcher and your shortcuts"
  (`Core/SafeMode.swift:31–34`) and triggers only after two launches that die within 60 s
  (`Core/LaunchStability.swift:10–23`). 0.4 added a separate in-flight crash guard for its private call
  (`IconsCrashGuard`, `SnapticKit/IconsEngineCore.swift:154–163`; `Icons/IconsModule.swift:32–33,178–186`).
- **`ThumbnailStore` is single-owner.**
  - One `generation` covers every capture (`Switcher/ThumbnailStore.swift:27`). It's bumped by every `refresh`
    (l.68) and by `invalidate`, which also drops `shareable` (l.39–42).
  - The store captures only through SCK, with an owner and blocked-bundle check (l.115–118), and only
    `onScreenWindowsOnly: true` (l.130).
  - It is pruned to `isCapturable` windows (`SwitcherController.swift:255`). That excludes minimized, hidden,
    other-Space, windowless and private windows (`WindowManager.swift:33–35`).
- **`FocusTracker` observes only `kAXFocusedWindowChangedNotification` per app** (`WindowManager.swift:800,817`),
  plus workspace launch, terminate and activate (l.691–706).
- **`HotkeyTap` is an active keyboard tap.** It's a `.defaultTap`, head-inserted, with its callback on the main
  thread (`Switcher/HotkeyTap.swift:44–66`). `start()` and `stop()` both clear the breaker history (l.78, l.94).
- **`SnapticPanel` can't become key** (`SwitcherWindow.swift:5–7`). Its level is `.popUpMenu` (l.28), it has
  `[.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]` (l.36) and `sharingType = .none` (l.38).
- **Lint rule 11 greps Swift under `Sources/Snaptic` only** (`scripts/lint.sh:142–147`). L2 bans `.post(tap:)`,
  `CGEvent(mouseEventSource…` and user-activity assertions outside `ActivitySimulator` (`scripts/lint03.py:521–527`).
- **The Dock is `LSUIElement = true`** on 27.2 (`/System/Library/CoreServices/Dock.app/Contents/Info.plist`).

---

## Blockers

### X-1 · Blocker · H3, §4.12, Ground rules, B1 · The 0.4 encoding check and exception poisoning can't apply to C symbols

**Finding.** The plan applies the 0.4 private-API rules unchanged to C functions:
- "Each symbol gets a `KitEncoding.Requirement`" (PLAN:l.147).
- "Each gets an encoding requirement verified in S0 on 27.2 and the 15 VM. A poisoned symbol logs once"
  (PLAN:l.272–273).
- "Any exception poisons it" (PLAN:l.48).
- B1 is done when the "forced-exception poison path [is] covered" (PLAN:l.338).

Every symbol in §4.12 is a plain C function found by `dlsym`, and so is `CGSHWCaptureWindowList`. A C function has no
runtime type encoding to compare. A wrong signature doesn't raise an ObjC exception: it corrupts memory or crashes
with `EXC_BAD_ACCESS`, which `@try` can't catch. So Q6 can't be carried out as written. B1 would ship a check that
compares nothing and a poison path that never fires in production. That is false assurance. The README's "fail
closed" promise would then cover symbols it can't protect.

**Evidence.**
- `KitEncoding.swift:3–5`: "shims return raw `method_getTypeEncoding` strings; Swift compares them here before a
  private selector is used."
- 0.4's working example checks `(className, selector)` pairs through `SNMenuBarVisibility.rawEncoding`
  (`Icons/PrivateMenuBarAPI.swift:30–37`).
- `Switcher/PrivateAPIs.swift:17–20` (`dlsym` + `unsafeBitCast`) and l.27–58 (the 14 lookups, all
  `@convention(c)`).

**Proposal.** Replace PLAN:l.147–148 and l.272–273. Ground rules l.47–49 say "for ObjC selectors"; for C symbols they
point here.
> **C symbols (§4.12).** A C symbol has no type encoding, so each gets four checks instead:
> 1. **Presence and image.** `dlsym` succeeds and `dladdr` reports the expected image: SkyLight for `SLS*`, `SLPS*`
>    and `CGSHW*`; HIToolbox for `KB*`. A symbol found in an unexpected image counts as missing.
> 2. **OS gate.** S0 records each symbol's probe result per OS build. Calls are allowed on the major versions S0
>    verified (14, 15, 26 and 27). On a newer major version, only the probe runs until it passes.
> 3. **Behavioural probe**, once per process, before first use, with no side effects:
>    - `SLSMainConnectionID` returns nonzero, and equals `CGSMainConnectionID` when both exist.
>    - `SLSCopySpacesForWindows`, given our own panel's window id, returns a one-element array of numbers.
>    - `_AXUIElementGetWindow`, given our own panel's AX element, returns its `windowNumber`.
>    - `CGSHWCaptureWindowList`, given our own off-screen probe window drawn with a known two-colour pattern, returns
>      one image of the expected size whose content passes the X-5 check.
>    - `SLSIsSymbolicHotKeyEnabled` returns a Bool for hotkey 1.
>    - The raise symbols get a presence check only (no safe probe exists).
>
>    A failed or wrong-shaped probe makes the symbol **unavailable** for the process.
> 4. **Crash guard** (X-2).
>
> "Poisoned" now means "unavailable for this process after a failed probe, or for this OS build after a crash".
> Neither `KitEncoding` nor an ObjC shim is involved. The decision rules live in Kit as `PrivateWindowContract`
> (pure functions over probe results, Linux-tested). The calls go through a new `SnapticShims/SNWindowServer.m`
> that takes caller-allocated, bounded buffers (the `SNCGSModes.m` pattern).
>
> B1 "Done when": `--selftest-launch` prints each symbol's probe result, and a test drives each probe's failure
> branch with an injected result.

### X-2 · Blocker · Q3, §4.12, A2, M33, §8 · A crash inside a private call loops on every hover, and Safe Mode now runs it through the switcher

**Finding.** Scenario:
1. A 27.x or 28 update changes `CGSHWCaptureWindowList`'s arguments, its options bits, or the ownership of the
   returned array. The name has no Copy or Create, so the ownership is a convention, not a rule.
2. The first hover over an app with a minimized window crashes Snaptic, and so does every later one.
3. `LaunchStability` counts only launches that die within 60 s. A user who hovers after a minute never reaches Safe
   Mode.
4. A user who does reach Safe Mode still gets the switcher. In 0.5 the switcher captures through the shared
   `WindowCapture`, so ⌥⇥ with a minimized window crashes Snaptic inside Safe Mode.

M33 checks only that Dock Previews doesn't start. The same holds for `SLPSPostEventRecordTo`, which sends a
hand-built byte record (`PrivateAPIs.swift:101–129`): a layout change is a bad write into WindowServer IPC. 0.4 hit
exactly this (0.4 X-2) and fixed it with `IconsCrashGuard`.

**Evidence.**
- `Core/SafeMode.swift:19–34` (skipped and still-running lists).
- `Core/LaunchStability.swift:10–23` (60 s survival).
- `IconsEngineCore.swift:154–163`.
- PLAN:l.393 (M33).
- PLAN:l.403. The mitigations it lists are "Encoding check, poison, kill switch, last-seen fallback". None of them
  survives a SIGSEGV.

**Proposal.** A new paragraph in §4.12, plus changes to the H6 and A6 rows and to M33.
> **Crash guard for private window calls.**
> - Before each call (or batch of calls) to `CGSHWCaptureWindowList`, `_SLPSSetFrontProcessWithOptions` or
>   `SLPSPostEventRecordTo`, write `Windows.inFlight = "<symbol>@<OS build>"` to Snaptic's defaults, and clear it on
>   return. These calls are short and rare.
> - At launch, a leftover marker means that call crashed last time. `WindowServices` then:
>   - sets `Windows.disabledBuild.<symbol> = <OS build>`;
>   - records `EventLog .safety` "A window service stopped Snaptic last time; it's off on this macOS build", with no
>     names;
>   - shows a row on the Switcher and Dock Previews pages with **Try Again**.
> - A new OS build clears the disable. `IconsCrashGuard`'s Kit rule is generalised to `CrashGuard(key:)` and
>   shared.
>
> **Safe Mode.**
> - `SafeMode.skipped` gains "Dock previews" and "Thumbnails of minimized and other-Space windows".
> - `stillRuns` keeps "The window switcher and your shortcuts".
> - In Safe Mode, `WindowCapture` uses SCK only and the raise path uses `kAXRaiseAction` plus activation.
>
> **Manual checks.**
> - M33 becomes: "Safe Mode: Dock Previews doesn't start; the switcher runs with no private capture (diagnostics
>   `hwCapture: safeMode`)."
> - New M35: "Write `Windows.inFlight` by hand, relaunch: the stopped row shows on both pages; Try Again clears it;
>   the next hover captures."

### X-3 · Blocker · §4.3, M23 · Bare W, M and Q close windows and quit apps while the pointer only rests on the panel

**Finding.** The keys tap is live whenever the panel is visible and the pointer is over it (PLAN:l.196). It swallows
bare W (close), M (minimize), Q (quit the app), Return (raise) and the arrows.

People park the pointer at the bottom of the screen. Scenario:
1. A user writing in Mail moves the pointer down, out of the way. It lands on the Mail icon, and the panel shows
   Mail's windows.
2. The pointer drifts up into the panel and stays there. Nothing dismisses the panel while the pointer is in it
   (§4.4), so it stays up indefinitely.
3. The user types "Quick question". The tap swallows Q and quits Mail. Later, a "w" closes the selected window, and
   Return raises a different window mid-sentence.

Chrome and Terminal sessions without running jobs quit on `terminate` without asking. DockDoor itself uses ⌘W, ⌘M
and ⌘Q (PLAN:l.77); the draft dropped the modifier. M23 checks that "no key reaches the frontmost app while
handled", which in this scenario is the bug.

**Evidence.**
- PLAN:l.194–197.
- PLAN:l.201–209: nothing hides the panel while the pointer is inside it.
- `HotkeyTap.swift:54–56`: a handled key is swallowed (`return nil`).

**Proposal.** Replace the last row of the §4.3 table and PLAN:l.196–197:
> | Keys while the panel is **engaged** | Esc hides; ←/→ (↑/↓ on side Docks) move the selection; Return raises; **⌘W** closes; **⌘M** minimizes; **⌘Q** quits the app |
>
> **When the panel is engaged.**
> - The panel is **engaged** when the pointer has *moved* inside it within the last 1.5 s, or after the user pressed
>   an arrow key that the panel handled.
> - A parked pointer disengages it.
> - A key the panel doesn't handle passes through and disengages the panel for 3 s.
> - Bare letters are never handled.
> - The selection ring is drawn only while the panel is engaged, so the user can see when keys go to it.
> - When the panel isn't engaged, ⌘Q goes to the frontmost app, as usual.
>
> **Tests.**
> - Kit (`DockPreviewPolicyTests`):
>   - A parked pointer, then "q": the key passes through.
>   - A moved pointer, then ⌘Q: the app quits.
>   - "a", then ⌘Q within 3 s: the key passes through.
> - M23 becomes: "Park the pointer on the panel for 3 s. Then type a sentence containing q, w, m and Return into the
>   frontmost app: every key arrives there. Move the pointer, then press ⌘W: the selected window closes."

---

## Majors

### X-4 · Major · §4.7, Q3, S0-4 · The private capture path must require Screen Recording consent and an owner check

**Finding.** S0-4 records `CGSHWCaptureWindowList` "without Screen Recording", as something that "decides Q3's path"
(PLAN:l.308). If the private call returns pixels without the grant, the plan never says not to use them. Using them
would mean three things:
- Snaptic captures window contents after the user declined Screen Recording. That breaks §4.7 ("Without it:
  text-only cards", PLAN:l.232) and the README's permission story.
- It skips the system capture indicator.
- It invites exactly the fix Apple tends to ship in a point release, which would then show up as grey images (X-5)
  or a crash (X-2).

Even with the grant, the private path has no owner check. SCK's `isOwned` confirms that the window id belongs to the
card's pid and that its bundle isn't blocked (`ThumbnailStore.swift:85,105,115–118`). `CGSHWCaptureWindowList`
takes a bare window id.

**Evidence.**
- PLAN:l.232–233 and l.308.
- `ThumbnailStore.swift:67,97`: the SCK path calls `CGPreflightScreenCaptureAccess()` first.

**Proposal.** A new §4.7 bullet, plus the `WindowCapture` spec.
> - Every capture path, SCK and private, runs only when **all** of these hold:
>   - `CGPreflightScreenCaptureAccess()` is true, checked per batch and not cached.
>   - The requesting module's Thumbnails setting is on.
>   - The window isn't private (X-7).
>   - The owner pid from `CGWindowListCopyWindowInfo(.optionIncludingWindow, id)` equals the card's pid.
>   - The owner's bundle isn't blocked.
> - S0 notes whether the private call works without Screen Recording. Snaptic never uses that.
> - When Screen Recording turns false while Snaptic runs, `WindowServices` purges every cached image (X-18).

### X-5 · Major · Q3, S0-4, §4.6 · On 27 the private capture may return a grey image rather than fail, and the last-seen cache would keep it

**Finding.** The project's macOS 27 notes say `CGWindowListCreateImage` "returns a grey image, not nil" from 27
beta 4, and recommend "SCK only" for thumbnails. `CGSHWCaptureWindowList` reaches the same WindowServer capture
service through SkyLight. If it degrades the same way, it **succeeds**:
- S0-4's pass criterion ("Recorded") never looks at pixels.
- The fallback chain (private → last-seen → icon) runs only on failure.
- A grey image would replace a good last-seen thumbnail in the shared LRU. Both modules would then show grey cards
  for every minimized window, which is worse than today's app icon.

**Evidence.**
- `docs/design/macos27.md:38`: Apple DTS says there's no way to restore the 26 behaviour.
- `macos27.md:107,129`: "SCK only".
- PLAN:l.226 (shared LRU) and l.258–259 (fallback order).

**Proposal.** Additions to the `WindowCapture` spec, plus new S0-4 pass text.
> - **Content check.**
>   - Every private capture is downscaled to 16×16. It's rejected if the luma standard deviation is below 2/255, or
>     if more than 95 % of its pixels are one colour.
>   - A rejection counts as a failure (`captures.rejected` in diagnostics).
>   - Three rejections in a row disable the private path for the process.
> - **The cache never downgrades.**
>   - Cache entries record their source (`sck` or `private`) and their age.
>   - A private capture replaces an SCK capture of the same window from the last 10 min only if it passes the
>     content check.
>
> **S0-4 pass.**
> - On 27.2 and on 15, the harness captures its own window (a known two-colour pattern) on-screen with SCK. It then
>   captures the same window minimized, and on another Space, with the private call. The 16×16 signatures must
>   match (mean absolute difference under 10 %).
> - Also record:
>   - image size and scale;
>   - p50 and p95 time per call;
>   - peak memory over 100 calls (X-19);
>   - leaks or zombies over 1,000 calls (who owns the returned array).

### X-6 · Major · §4.11, H2, A1–A2 · Sharing `ThumbnailStore` as is: each module cancels the other's captures, and the switcher's prune erases the last-seen fallback

**Finding.**
- **One generation for every caller.**
  - Every `refresh` bumps the shared `generation` (`ThumbnailStore.swift:68`).
  - `invalidate()` bumps it and drops `shareable` (l.39–42). The switcher calls `invalidate()` whenever it closes
    (`SwitcherController.swift:432`).
  - With two users:
    - A Dock hover refresh cancels the switcher's batch that's in flight.
    - Closing the switcher cancels the Dock panel's batch.
    - Each Dock swap cancels the switcher's batch as well as the previous app's.
- **The switcher's prune evicts what Q3 depends on.**
  - The switcher prunes the shared cache to `isCapturable` windows (`SwitcherController.swift:255`). That excludes
    minimized, hidden, other-Space and private windows, and also every window of an app the switcher excludes.
  - So each switcher open deletes the last-seen thumbnails that Q3's fallback depends on ("otherwise the last-seen
    thumbnail", PLAN:l.258), along with everything the Dock panel cached for windows outside the switcher's list.
- **A1 isn't neutral.** A1 claims to be "behaviour-neutral" (PLAN:l.406), but simply sharing the store changes both
  of these behaviours.

**Evidence.**
- As cited above.
- PLAN:l.129–132, l.226–227, l.339–340.

**Proposal.** Change §2 `WindowServices` and A1's "Done when":
> `ThumbnailStore` becomes **owner-scoped**:
> - `refresh(…, owner: ModuleID)` keeps one generation per owner. A new request cancels only that owner's previous
>   request.
> - `invalidate(owner:)` replaces `invalidate()`.
> - `shareable` is a 2 s shared cache (X-20), and `invalidate` doesn't drop it.
> - `prune(keeping:)` is removed. Entries leave the cache in four ways:
>   - by the LRU budget (§4.6);
>   - when the window dies: its id is absent from `CGWindowListCopyWindowInfo(.optionAll)` for 5 s;
>   - when the window becomes private (X-7);
>   - by purge (X-18).
> - **Last-seen entries.** A last-seen entry is the latest capture taken while the window was on-screen. It's kept
>   after the window is minimized or leaves the Space, until the retention limit (X-21).
>
> **Tests (Kit, in `WindowCatalogRulesTests`).**
> - Two owners interleave without cancelling each other.
> - Opening the switcher doesn't evict a minimized window's last-seen entry.

### X-7 · Major · §4.2, §4.13, Ground rules · The Dock panel has none of the switcher's privacy protections

**Finding.**
- **What the switcher protects.**
  - It never captures, shows, searches or reads aloud:
    - private-browsing windows;
    - the user's protected apps (`privateBundleIDs`, for example password managers);
    - browser windows whose title can't be read.

    See `markPrivacy`, `SwitcherController.swift:321–337`.
  - It skips blocked bundles at capture time (`isOwned`).
  - It captures only while the user deliberately holds ⌥⇥.
- **What the Dock panel lacks.**
  - It shows on a casual hover, including during screen sharing and presentations.
  - §2, §4.2 and §4.13 don't mention any of these protections.
  - The settings live in the **switcher's** Advanced sheet and config
    (`SnapticKit/Controls/SwitcherAdvancedSheetControls.swift:51–55`). With only Dock Previews on, nothing reads
    them.
- **Screen sharing.**
  - Our panel uses `sharingType = .none` (`SwitcherWindow.swift:38,104`).
  - Whether SCK-based sharing on 15 and later honours that is **[U]**.
  - If it doesn't, a Zoom or Meet share shows an incognito thumbnail the moment the presenter brushes the Dock.

**Evidence.**
- As cited above.
- PLAN:l.176–177 and l.280–281.

**Proposal.** A new bullet in §4.2, and changes to §2 and H5:
> - **Privacy.** Both modules use one Kit rule, `WindowCatalogRules.privacy(item:settings:)`, moved out of
>   `SwitcherController.markPrivacy`.
> - **Shared settings.** "Protect private windows", the protected apps list and the blocked bundles move to a
>   `WindowServices` config slice. The switcher's Advanced sheet and Dock Previews' Advanced sheet show the same
>   controls: one store, two views. A migration test and `KitBackup.sections` keep the 0.4 keys.
> - **What a private card shows.** The app icon, with "Private window" or the app name. It has no title, no
>   thumbnail and no title for VoiceOver, and its image is never cached.
> - **S0-24.** Record whether a `.none` panel appears in an SCK-based share on 15 and 27.2. If it does:
>   - README Known limitations says so.
>   - "Pause previews while sharing the screen" is recorded for 0.5.x. There's no public "being captured" signal,
>     so it's not built now.

### X-8 · Major · §1, §4.6, §4.7 · The window-list reuse claim is wrong, and the real path is too broad per hover and blind without Screen Recording

**Finding.**
- **Wrong reuse claim.**
  - `WindowGatherer` doesn't list windows. It moves them onto one display ("Gather windows here",
    `Switcher/WindowGatherer.swift`).
  - The lister is `WindowManager.loadWindows`. It walks **every** regular app, with a 1.2 s total budget
    (`WindowManager.swift:174–176,245–349,353–361`).
  - Calling it per hover makes each hover cost as much as opening the switcher. S0-14's 20 hovers in 2 s would mean
    20 scans of every app.
- **Other-Space windows vanish without Screen Recording.**
  - `windowsOnOtherSpaces` drops any window whose `kCGWindowName` is empty (`WindowManager.swift:456`). That name is
    empty without Screen Recording.
  - So in text-only mode, the plan's promise to users without the permission (PLAN:l.232), other-Space windows
    don't appear at all. The "Other Space" badge and M18 can't both hold.
- **Other-Space cards can't be acted on.**
  - Other-Space items have no `axElement`. `close`, `toggleMinimized` and `toggleFullscreen` need one
    (`WindowManager.swift:548–574`), and the switcher guards on it (`SwitcherController.swift:622–672`).
  - The Dock cards' hover buttons and menu items would silently do nothing.
- **The AX-timeout fallback has no titles either.** §4.6 falls back to "titles only" from `CGWindowList`
  (PLAN:l.224–225). Those titles also need Screen Recording.

**Evidence.** As cited above.

**Proposal.** Change the Snaptic decision in PLAN:l.71, plus §4.6 and §4.3:
> - **Per-app window list.**
>   - A new `WindowManager.windows(for pid:)` reuses `loadWindows`'s per-app reader (`perAppBudget` 0.5 s, the
>     window cap of X-29).
>   - Other Spaces come from `SLSCopySpacesForWindows`, filtered to that pid.
>   - The list is cached per pid for 2 s and marked dirty by X-9's observers.
> - **Untitled other-Space windows** are kept without Screen Recording, shown as "Window on another Space" with the
>   badge and the app icon. `windowsOnOtherSpaces` gains `allowUntitled:` for the Dock path only. The switcher's
>   behaviour is unchanged, so A1 stays neutral.
> - **Cards without an AX element** (other Space, untitled fallback) offer only **Bring Forward**, through `focus`.
>   The hover buttons and the Close, Minimize and Full Screen menu items are hidden, and VoiceOver says "On another
>   Space".
> - **After an AX timeout**, titles come from `CGWindowList` only with Screen Recording. Otherwise the panel shows
>   one compact card, "Windows can't be read right now".

### X-9 · Major · §1, §4.6 · `FocusTracker` only sees focus changes, so cached cards go stale

**Finding.**
- **The claim.** PLAN:l.73 says freshness comes "through the switcher's `FocusTracker` (one AX observer per app
  already exists)".
- **What the observer actually covers.** It registers only `kAXFocusedWindowChangedNotification`
  (`WindowManager.swift:800,817`). The only other inputs are the workspace launch, terminate and activate
  notifications (l.691–706).
- **What nothing reports.** The panel shows "the cached window list at once" (PLAN:l.223), but nothing tells the
  cache about any of these:
  - a window opened in the background;
  - a window closed;
  - a minimize or a restore;
  - a title change;
  - a move to another Space.
- **The result.**
  - A closed window keeps its card, and clicking that card fails silently.
  - The "Minimized" badge is wrong after ⌘M.
- **Why the switcher never noticed.** It re-reads everything each time it opens.

**Evidence.** As cited above.

**Proposal.** Changes to §4.6, plus the A3 and A4 "Done when" columns:
> - **More notifications.**
>   - On the app element, the per-app observer adds `kAXWindowCreatedNotification`,
>     `kAXWindowMiniaturizedNotification`, `kAXWindowDeminiaturizedNotification` and `kAXTitleChangedNotification`.
>   - Each window gets `kAXUIElementDestroyedNotification`, registered when the window is read and capped like the
>     read.
> - **When they're registered.** Only while some consumer wants freshness: Dock Previews is on, or the switcher is
>   open. With only the switcher on, the observer keeps today's single notification.
> - **What an event does.** It marks that pid's list dirty, debounced 0.3 s. A dirty list still shows at once, and
>   it refreshes before any action uses it.
> - **Actions check first.** Every action re-resolves its window by id. If the id is gone, the card is removed
>   instead of the action failing silently.
> - **Liveness** uses `kill(pid, 0)`, not `isTerminated` (`macos27.md:101`).
> - **S0-26** records delivery of these notifications for Safari, Chrome, an Electron app, Finder and Terminal,
>   and the per-app cost of registering them.

### X-10 · Major · §1, §4.1(4), §4.4 · The pointer source isn't specified and contradicts "no mouse polling"; "the Dock's frame" is undefined under magnification and auto-hide

**Finding.**
- **Where pointer positions come from is unstated.** The policy consumes `pointerMoved`, the corridor, "outside
  the Dock's frame" and "outside the panel" (PLAN:l.125–127, l.171–172, l.203–205). Each candidate source has a
  cost the plan doesn't state:
  - A global `.mouseMoved` monitor fires at the mouse's report rate, up to 1 kHz (0.4 X-26).
  - A timer is polling, which PLAN:l.69 rules out.
  - A global monitor doesn't see moves over our own panel.
- **"The Dock's frame" is never defined.**
  - With magnification, hovered icons rise above the resting `AXList` frame. A resting frame makes the 1 s safety
    net fire while the user is still on a magnified icon, so the panel flaps.
  - With auto-hide, the frame is off-screen half the time.
  - §4.1(4) relies on this frame to judge whether a selection is stale.

**Evidence.**
- As cited above.
- `docs/design/0.4/review-r1-adversarial.md:813` (0.4 X-26, hover monitor cost).

**Proposal.** A new "Inputs" paragraph in §4.4. PLAN:l.69's "No mouse polling" becomes "No pointer tracking while
nothing is shown or pending".
> **Inputs.** These exist only while a show is pending or the panel is up:
> - A global `.mouseMoved`/`.leftMouseDragged` monitor, coalesced to at most 60 Hz before the policy sees it.
> - An `NSTrackingArea` on the panel's content view (`.activeAlways`, `.mouseEnteredAndExited`, `.mouseMoved`).
> - A 0.1 s `tick` timer, only while the panel is up, for the grace and safety-net deadlines.
>
> All of them are removed on hide. M32 checks this.
>
> **Dock frame.**
> - At each selection change, read the `AXList` frame, in AppKit coordinates (X-27).
> - Grow it to include the hovered item's live frame, plus 24 pt on every side.
> - Take the union over the current hover session.
> - When the frame can't be read (the Dock is auto-hiding), use the last known value.
>
> **Kit tests.**
> - A magnified icon above the resting frame doesn't trip the safety net.
> - Leaving the union for 1 s does.

### X-11 · Major · §4.1(2), §4.3 · Instant swaps send the pointer to the wrong app, and a swap under a still pointer can make a second click quit a different app

**Finding.**
- **Diagonal travel (the mega-menu problem).**
  - The panel is centered on the item and is much wider than an icon (cards are 200–360 pt each).
  - To reach a far card, the user moves diagonally. With magnification the Dock row is 64–128 pt tall, so the
    pointer crosses one or two neighbouring icons before it leaves the Dock.
  - Swaps are instant (PLAN:l.168), so the panel swaps to a neighbour. The corridor (PLAN:l.203–204) only delays
    dismissal; it doesn't stop a swap.
- **A swap under a still pointer.** The user clicks **Quit** in the header (PLAN:l.180):
  1. The app quits. If it isn't kept in the Dock, its icon disappears.
  2. The icons slide, so the still pointer is now on the neighbour. The Dock reselects, and the panel swaps at once.
  3. A double-click, or an impatient second click, lands on the new app's **Quit**. The panel was supposed to hide
     "after the action completes" (PLAN:l.207), but `terminate` takes longer than the reflow.

  **Hide** does the same whenever nearby apps launch or quit and the Dock reflows.

**Evidence.** PLAN:l.168, l.180, l.203–204 and l.207.

**Proposal.** Changes to §4.1, §4.3 and K3:
> - **Swap intent.**
>   - While the panel is up, a selection change to another app is held back for 120 ms if the pointer's last 50 ms
>     of motion points into the triangle between the pointer and the panel's two near corners. For a side Dock,
>     the triangle uses the panel's near edge.
>   - If the pointer is still on the new item after that, or has stopped moving, the swap happens.
>   - The corridor becomes the convex hull of the item frame and the panel's near edge, so it still works when the
>     panel is clamped off-centre.
> - **After Quit or Hide** from the header or the menu:
>   - The panel hides at once, before the action finishes.
>   - It doesn't show again until the selection is empty or the pointer has moved at least 8 pt.
> - **Header buttons** ignore clicks for 300 ms after a show or a swap.
> - **K3's race table** adds three rows: a diagonal crossing, a reflow under a still pointer, and a click within
>   300 ms of a swap.

### X-12 · Major · §4.4 · A click on the hovered Dock icon, or the Dock's own menu, brings the panel back over the Dock's UI

**Finding.**
- **The right-click case.**
  - The Dock's menu opens directly above the icon, the same place as our panel.
  - The global mouse-down monitor hides the panel (PLAN:l.206). But the Dock's selection is still that app, so the
    policy shows it again after the delay.
  - Both windows are menu-level, so whichever was ordered front last wins.
  - A card refresh that re-orders the panel also puts it over the Dock menu.
  - This breaks "the Dock itself is never affected" (PLAN:l.49).
- **Other cases.** The same re-show happens after a left-click on an app that's already frontmost (no activation
  arrives to dismiss), and while dragging a file onto a Dock icon.

**Evidence.**
- PLAN:l.166–172, l.206 and l.217.
- `SwitcherWindow.swift:28` (`.popUpMenu`).

**Proposal.** New bullets in §4.4, plus S0-25:
> - **Dismiss latch.**
>   - Any of these latches "dismissed for item X":
>     - a mouse-down outside the panel;
>     - a Dock menu opening;
>     - a drag starting over the Dock.
>   - X doesn't show again until the Dock's selection leaves X (another item, or none), or the pointer leaves the
>     Dock frame.
> - **Dock menus.**
>   - `DockObserver` also watches `kAXMenuOpenedNotification` and `kAXMenuClosedNotification` on the Dock's
>     application element.
>   - While a Dock menu is open, the panel is hidden and nothing shows.
> - **Drags.** Drags come from X-10's `.leftMouseDragged` monitor. No new tap.
> - **S0-25.**
>   - With the panel up, test each of these: a right-click, a left-click on the frontmost app, a long press, and a
>     file dragged onto an icon.
>   - Record the AX notifications.
>   - Pass: the Dock menu is never covered.

### X-13 · Major · §4.9, S0-9 · "Click the frontmost app's icon: Hide" can hide the app the user just clicked

**Finding.** A listen-only tap delivers the click to the Dock and to us at the same time, and our callback runs on
the main run loop whenever the main thread is free. Scenario:
1. The user clicks a **background** app's icon, and the Dock activates it.
2. Our callback runs after the activation, or it reads `NSWorkspace.frontmostApplication` afterwards. Either way,
   it sees the clicked app as frontmost.
3. It hides the app the user just asked for.

Main-thread work (AX reads, captures) widens the window. The Dock also sends a reopen event when the clicked app is
already frontmost. Safari, Terminal and Finder open a new window when they have none, so the reopen races our hide.
S0-9 measures flicker, not the wrong-app outcome.

**Evidence.** PLAN:l.242–247 and l.313.

**Proposal.** Rewrite §4.9's first bullet, and the S0-9 pass:
> - **Frontmost at the click** comes from a history of `didActivateApplication` entries stamped with
>   `mach_absolute_time`.
>   - The click's frontmost app is the last entry at least 150 ms before the mouse-down's `CGEventGetTimestamp`.
>   - The click is ambiguous, and **nothing happens**, if an activation landed in the 150 ms before the mouse-down
>     or between mouse-down and mouse-up.
> - **The action runs on mouse-up**, and only when all of these hold:
>   - Mouse-down and mouse-up were on the same Dock item (the AX selection at both moments).
>   - That item's pid is the history's frontmost app.
>   - The mouse-up came within 0.5 s, so it wasn't a long press (which opens the Dock menu) or a drag.
> - **Hide or Minimize runs 100 ms after mouse-up.** If a window was created in that time (X-9), Hide is skipped.
> - **S0-9 pass.**
>   - 100 clicks on background apps and 100 on the frontmost app, with a synthetic main-thread load (a 50 ms busy
>     loop every 100 ms).
>   - Zero wrong-app hides.
>   - Record the reopen behaviour for Safari, Terminal and Finder with no windows.

### X-14 · Major · §4.3, §8, M24–M26 · The keys tap is an active keyboard tap, rebuilt on every pointer entry, which resets its own breaker; M26 tests the other tap

**Finding.**
- **The freeze case is untested for this tap.**
  - `HotkeyTap` is an **active** keyboard tap: `.defaultTap`, head-inserted, with its callback on the main thread
    (`HotkeyTap.swift:44–66`).
  - The 27.2 freeze when Accessibility is revoked is specifically an active-tap problem (`macos27.md:54`).
  - The plan's freeze mitigations and M26 cover only the listen-only *click* tap (PLAN:l.244–247, l.386, l.408).
- **Its breaker never trips.**
  - "Installed only while the panel is visible and the pointer is in it" means a `tapCreate` and
    `CFMachPortInvalidate` on every entry and exit.
  - `start()` and `stop()` both reset `reenables = []` (`HotkeyTap.swift:78,94`).
  - So a tap rebuilt on each entry never reaches its 5-in-10 s breaker, which is the protection against the
    27.2 freeze.
- **It shadows the switcher's tap.**
  - The newest tap runs first (`macos27.md:52`).
  - If the user presses ⌥⇥ while the pointer rests on the panel, the switcher opens, but the Dock tap still
    swallows ←, →, Return and Esc. Switcher navigation breaks.
- **It makes main-thread stalls stall typing.** While the tap is installed, any main-thread stall in the Dock
  module's AX or capture work stalls every keystroke system-wide until macOS disables the tap.

**Evidence.** As cited above.

**Proposal.** Changes to §4.3, §4.4, M24 and M26:
> - **One keys tap, created once.**
>   - `DockKeys` creates its tap in `start()` when "Keyboard in previews" is on.
>   - It enables and disables the tap with `CGEvent.tapEnable` as the panel engages and disengages (X-3).
>   - The breaker history persists across enables.
>   - The tap is invalidated only in `stop()`, by a kill switch, or when the breaker trips.
>   - M24 becomes: "With the panel not engaged, `CGGetEventTapList` shows the tap disabled; with the module off, the
>     tap is gone."
> - **Mutual exclusion with the switcher.**
>   - `WindowServices` publishes `switcherSessionActive`.
>   - When the switcher opens, the Dock panel hides and its keys tap is disabled.
>   - The panel doesn't show while the switcher is open.
> - **No main-thread blocking while the tap is enabled.**
>   - All AX and capture work runs off the main thread (X-15).
>   - The tap callback only looks up a table.
> - **M26** covers both taps: "Revoke Accessibility with the click tap on, then again with the panel engaged: no
>   freeze over 30 s; both features stop with their row text."
> - **S0-20 tests the tap-free alternative:**
>   - A `.nonactivatingPanel` that may become key gets keys without activating Snaptic.
>   - When it resigns key, focus returns to the previous app's key window.
>
>   If both hold, §4.3 takes keys through the key window and drops the tap.

### X-15 · Major · §2, §4.6, S0-14 · The Dock's AX reads have no thread, and the Dock is the process that draws Mission Control

**Finding.**
- The plan budgets Dock reads at "0.15 s per call" (PLAN:l.115) but doesn't say which thread they run on.
- One hover needs at least five AX calls to the Dock: the selected children, the subrole, `kAXURLAttribute`, the
  position and size, and the running state.
- On the main run loop, that's up to about 0.75 s of blocking per hover in the worst case.
- The Dock process renders Mission Control, App Exposé, launch bounces and magnification. Its AX latency spikes
  exactly when these signals fire.
- S0-14 tests a stalled *app*, not a stalled Dock (PLAN:l.318).
- A blocked main thread also stalls the keys tap (X-14) and the switcher's hotkeys.

**Evidence.**
- PLAN:l.114–115 and l.318.
- The precedent: `FocusSession` already runs its observers on its own `ObserverThread`
  (`WindowManager.swift:661–663`).

**Proposal.** Changes to §2 and S0-14:
> `DockObserver` works like `FocusSession`:
> - It runs its `AXObserver` on a dedicated `ObserverThread`.
> - It sets `AXUIElementSetMessagingTimeout(dockApp, 0.15)`.
> - On that thread it reads the hovered item's attributes in one `AXUIElementCopyMultipleAttributeValues` call and
>   posts a `DockHover` value to main.
> - Selection changes that arrive during a read are coalesced; the latest wins.
> - Three timeouts within 10 s make it back off for 1 s and report `dockSlow` in diagnostics.
>
> S0-14 adds: "Dock read p50, p95 and max during Mission Control, App Exposé, a launch bounce and magnification; Dock
> reads never block the main thread for more than 16 ms."

### X-16 · Major · §4.4, S0-13 · Detecting Mission Control by its window is the heuristic that broke AltTab on 27

**Finding.**
- **The detector misfires on 27.** A WindowManager window at layer 19 now exists **off-screen while a normal window
  is focused**. Stage Manager with several stages produces it too (`macos27.md:99`; AltTab #6076). A "Mission
  Control's window appeared" detector would misfire constantly: depending on the bug, the panel either never shows
  or hides at random.
- **It isn't needed.** The panel already has `.transient` (`SwitcherWindow.swift:36`), which AppKit documents as
  hidden by Exposé.

**Proposal.** Replace the last bullet of §4.4, and the S0-13 pass, which also becomes a Blocker row:
> - **No window-based detector** for Mission Control or App Exposé. The panel's `.transient` behaviour hides it
>   during Exposé.
> - **Afterwards,** the safety net (X-10) or an empty Dock selection ends the hover.
> - **If detection is ever needed,** any check by layer must require on-screen bounds that intersect a screen
>   (`macos27.md:132`).
>
> **S0-13 pass.** On 27.2 and 15, with the panel up, open Mission Control, App Exposé, the Apps view (Launchpad on
> 15) and Spotlight. The panel is never visible over any of them, and it's gone or correct within 1 s after they
> close.

### X-17 · Major · §1, §8, S0-3, M8 · Re-attaching after a Dock restart relies on unverified notifications and a single attempt

**Finding.**
- **The trigger may never fire.** Re-attach waits for `NSWorkspace`'s Dock launch and terminate notifications
  (PLAN:l.69). On 27.2 the Dock is `LSUIElement = true` (its `Info.plist`). Whether those notifications fire for it
  is **[U]**.
- **One attempt isn't enough.** Even when the notification fires, the new Dock's `AXList` doesn't exist for a
  moment, so a single attempt at launch fails.
- **The fallback is too slow.** Either failure falls back to the 30 s health check, but M8 requires previews to
  return "within 2 s".
- **The health check misses the real failure.** Its "one AX read" can't detect DockDoor's top complaint: an
  observer that stops delivering while the Dock's pid stays the same, for example after sleep and wake.
- **Process churn leaks AX observers on 27** (`macos27.md:101`).

**Proposal.** Changes to the §1 decision and to S0-3:
> - **Dock liveness.**
>   - KVO on `NSWorkspace.runningApplications`, filtered to `com.apple.dock`.
>   - `kill(dockPid, 0)` in the health check.
>   - Neither depends on launch notifications.
> - **Re-attach ladder.**
>   - Attempts at 0.1, 0.25, 0.5, 1 and 2 s, then the 30 s health check.
>   - Each attempt makes a fresh `AXObserver`; the old one is invalidated and its run-loop source removed.
>   - The ladder stops when `AXList` resolves.
> - **Wake, unlock and session-active** always rebuild the observer.
> - **Silent-death check.**
>   - At each health check, read `NSEvent.mouseLocation` once.
>   - If the pointer is in the last Dock frame, and AX reports a selected child different from the last one
>     notified, re-attach and count `observer.silentReattach`.
> - **S0-3 pass.**
>   - `killall Dock` 10 times: re-attached within 2 s every time.
>   - Record whether the NSWorkspace notifications fire for the Dock.

### X-18 · Major · §2, H2, §4.6, M3 · Purge, consent and teardown rules are tied to the switcher's old lifecycle

**Finding.**
- **Purge observers.**
  - Today they exist only while the switcher's thumbnails are on (`WindowSwitcherModule.swift:300–327`).
  - "Sleep" there means `screensDidSleepNotification` (the display going to sleep), not system sleep.
- **Gaps if they move as they are.** Moving them into `WindowServices` unchanged leaves no purge on:
  - system sleep;
  - Screen Recording being revoked;
  - the last consumer with thumbnails on turning them off while another consumer still holds the service.
- **Work in flight.** A capture or AX batch started before `release()` or a kill switch can complete after `purge()`
  and write into the fresh cache. `purge` bumps the global generation, but the per-owner generations from X-6 need
  their own check.
- **The cost of Dock Previews alone.**
  - `FocusTracker` adds an AX observer for every running app (`WindowManager.swift:188–217,635–829`).
  - With only Dock Previews on, that's a new cost.
  - "While off, costs nothing" still holds, but the cost while on should be stated and measured.

**Proposal.** A new paragraph in §2 `WindowServices`:
> - **Purge triggers.** `WindowServices` purges every image on:
>   - screen lock;
>   - display sleep;
>   - system sleep (`willSleepNotification`);
>   - session resign;
>   - the last `release`;
>   - Screen Recording turning false (checked on activation, on wake and before each capture batch);
>   - no acquired consumer having thumbnails on.
> - **Stale completions.**
>   - Every completion checks `(owner, generation)` and the service `epoch`, which purge bumps.
>   - Stale results are dropped, never cached.
>   - `release(owner:)` cancels that owner's requests synchronously.
> - **Manual checks.**
>   - M3 adds system sleep and the revoke case.
>   - M32 adds: "Dock Previews alone: AX observers = running regular apps + 1 (the Dock); after off, 0."

### X-19 · Major · §4.6, §8 · The 96 MB budget doesn't bound the private path's full-resolution captures

**Finding.**
- **Full-resolution images.**
  - SCK can be asked for a scaled image.
  - `CGSHWCaptureWindowList` returns the window's backing store at full resolution. A full-screen window on a
    5K display is about 5120 × 2880 × 4 bytes, or about 59 MB.
- **Peaks outside the budget.**
  - With "at most 4 captures at once" (PLAN:l.72), one hover over an app with four maximized windows peaks at about
    236 MB before downscaling.
  - That memory sits outside the 96 MB cache budget.
  - Fast hovers (S0-14) can chain these peaks.
- **The risk table.** It rates memory "Low" (PLAN:l.407), judging only the stored cache.

**Proposal.** Changes to §4.6 and S0-4:
> - **One private capture at a time.**
>   - The private path runs one capture at a time; SCK keeps 4.
>   - Each image is downscaled at once to the largest card width × the screen's scale.
>   - The full-size image is released before the next capture starts.
> - **What the budget counts.**
>   - The LRU budget counts the stored image's `bytesPerRow × height`.
>   - 96 MB is a hard cap: an insert that would exceed it evicts first.
> - **S0-4 records memory.**
>   - Measure peak resident memory over 100 private captures of a full-screen 5K window.
>   - Pass if the peak grows by less than 150 MB, and memory doesn't grow over 1,000 calls.

### X-20 · Major · §4.7, §4.6 · SCK on every hover can bring up system prompts and indicators, and each capture costs tccd time

**Finding.**
- **"Never a prompt on hover" (PLAN:l.233) holds only for our own prompts.**
  - On macOS 15 and later, the system shows a periodic "… is requesting to bypass the system private window picker"
    reminder to apps that capture without the picker. It appears at the first capture after it's due, which in
    Dock Previews is a hover.
  - On 27 beta 4 and later, `SCShareableContent` calls can raise a Remote Desktop consent alert "on every call" in
    some setups (`macos27.md:36`).
- **Each hover is expensive.**
  - `ThumbnailStore` fetches `SCShareableContent` on every `refresh` (`ThumbnailStore.swift:80,130`).
  - Each SCK capture costs about 23 ms of tccd CPU (`macos27.md:39`).
  - Sweeping the pointer along the Dock therefore makes one shareable-content call, plus N captures, per app.
- **Users read indicators as trust signals.** This is the 0.4 lesson (R3-90). If the capture indicator blinks on
  every hover, Snaptic looks like it's recording the screen.

**Proposal.** Changes to §4.7 and §4.6, plus a new S0-19:
> - **The promise becomes:** "Snaptic never asks for Screen Recording on hover. macOS may show its own periodic
>   Screen Recording reminder the first time a thumbnail is captured after it's due." The README's Known
>   limitations says the same.
> - **Capture throttle.**
>   - `SCShareableContent` is cached for 2 s and shared by both modules.
>   - A hover captures only after the panel has been visible for 150 ms, so sweeping across the Dock captures
>     nothing.
>   - Each window is captured at most once per 30 s while its card is visible.
>   - At most 8 captures per second overall.
> - **S0-19 (Blocker).**
>   - On 27.2 and 15, record whether SCK screenshots, and the private call, show the menu-bar capture indicator.
>   - Record whether the reminder or a Remote Desktop alert appears.
>   - Record tccd CPU over 50 hovers.
>   - Pass: no alert appears per call.
>   - If the indicator blinks on each hover, Dock Previews' Thumbnails setting defaults to off (text-only), with the
>     reason in the row.

---

## Minors

### X-21 · Minor · §4.6, A1 · The cache numbers diverge from the switcher's, and "fresh" is mixed up with "kept"

**Finding.** The switcher keeps 40 entries for 5 minutes (`ThumbnailStore.swift:21–22`). The plan specifies
120 entries, 96 MB and 30 s (PLAN:l.226). The 30 s figure is a freshness rule, but a last-seen entry for a minimized
window is old by definition. Under a 30 s rule it would always count as stale, and it would always start a private
capture.

**Proposal.** Keep two separate rules:
- **Freshness:** after 30 s, a capturable window is refreshed when shown.
- **Retention:** a last-seen entry is kept while the window exists, for up to 30 min, subject to X-18's purges.

A1 keeps 40 entries and 5 min. A2 moves both modules to the new rules, and the release notes list it as a switcher
behaviour change.

### X-22 · Minor · Ground rules, §1, §4.12 · "No synthetic events" contradicts the reused raise path

**Finding.** PLAN:l.50–51 says window actions use AX only. PLAN:l.76 and l.268 reuse `WindowManager.focus`. That
function posts what `PrivateAPIs.swift:8–9` itself calls "a synthetic 'make key window' event record", through
`SLPSPostEventRecordTo` (l.101–129). L2 doesn't catch it (`lint03.py:521–527`).

**Proposal.** Change the wording to: "No synthetic input events (mouse, keyboard, scroll or user activity). The one
exception is the switcher's existing window-activation record (`SLPSPostEventRecordTo`), behind
`Windows.disable.raise`." Add an L2 pattern: `SLPSPostEventRecordTo` may appear only in
`Windows/PrivateWindowAPI.swift` and the X-1 shim.

### X-23 · Minor · H3, lint rule 11 · Rule 11 doesn't cover the shims or the new private-API home

**Finding.** Rule 11 greps only Swift files under `Sources/Snaptic` and allows exactly two files
(`lint.sh:142–147`). Its comment says the shims are allowed, but nothing limits *which* shim files may look up
symbols. Any `.m` file can `dlsym` freely: `SNDDC.m`, `SNNightShift.m` and `SNOSD.m` already do. X-1 adds a shim
for the window-server calls, and §2 moves the switcher's lookups to a new Swift home, which today's allowlist would
reject. (`@_silgen_name` is already banned everywhere by rule 2, `lint.sh:32–35`, so a direct binding can't crash at
dyld load.)

**Proposal.** Rule 11:
- swaps `Switcher/PrivateAPIs.swift` for `Windows/PrivateWindowAPI.swift` in the allowlist, in the same commit that
  moves the file (A2);
- adds a second grep over `Sources/SnapticShims/*.m` for `dlsym(` and `dlopen(`, with the current shim files frozen
  as the allowlist plus `SNWindowServer.m`.

### X-24 · Minor · §4.12 · The private API table misses lookups

**Finding.** `PrivateAPIs.swift:57–59` also looks up three symbols:
- `KBGetLayoutType`: private HIToolbox. Q6 says "every switcher private symbol", so this needs a row and a kill
  switch.
- `IsSecureEventInputEnabled` and `LMGetKbdType`: public Carbon functions, loaded dynamically.

The table also folds separate symbols together. The four CGS fallbacks (`CGSSetSymbolicHotKeyEnabled`,
`CGSMainConnectionID`, `CGSCopySpacesForWindows` and `CGSIsSymbolicHotKeyEnabled`) are separate symbols, each
needing its own probe (X-1). The SkyLight `dlopen` (`PrivateAPIs.swift:15`) needs a selftest line of its own.

**Proposal.**
- Add a row: `KBGetLayoutType` → `Windows.disable.layoutType`, which falls back to the ANSI layout.
- List the public lookups as "public, dynamic, no kill switch".
- Give each fallback symbol its own selftest line.

### X-25 · Minor · §4.3, §4.4 · The right-click menu races the dismiss timers

**Finding.** While a card's context menu is open, the pointer is on the menu window, which is outside the panel and
outside the corridor. After the 0.25 s grace period (PLAN:l.204), the panel hides under the open menu, and the menu
then acts on a torn-down card. Our own actions also trigger activation and Space-change signals, which the switcher
filters out with `ignoreDismissSignalsUntil` (`SwitcherController.swift:51,626`).

**Proposal.**
- Add `menuOpened` and `menuClosed` policy events that pause every timer. A hide that comes due while the menu is
  open runs on `menuDidClose`.
- Give the policy an "own action" window (1.5 s, or 5 s for Quit) during which activation and Space-change signals
  don't count as dismiss reasons, so diagnostics record `actionCompleted` rather than `appActivated`.

### X-26 · Minor · §4.1, §4.10 · Selection without the pointer makes the panel flap

**Finding.** Keyboard Dock focus (⌃F3, Full Keyboard Access) and Switch Control move the Dock's selection just as
VoiceOver does. The panel shows after 0.2 s, the safety net hides it at 1 s, and the next arrow press shows it
again.

**Proposal.** Show the panel only if the pointer is inside the Dock frame when the selection changes. Read
`NSEvent.mouseLocation` once; this needs no monitor. A keyboard-driven selection never shows the panel unless "Show
with VoiceOver" is on.

### X-27 · Minor · §4.5, K2, M13 · Coordinates and capture scale

**Finding.**
- **Coordinates.** AX frames are global, top-left-origin and y-down from the primary display. The existing `Screens`
  helper converts them correctly (`WindowManager.swift:48–102`), but the plan doesn't name the convention that Kit
  receives.
- **Capture scale.** It comes from `NSScreen.main`, the screen of the key window (`ThumbnailStore.swift:70,108`). On
  mixed Retina setups, windows on the other display come out blurry or twice the size.

**Proposal.**
- `DockReader` converts every frame with `Screens.cocoaRect` before Kit sees it, and `DockGeometry` documents that it
  takes AppKit global coordinates.
- K2's tests include a display above the primary (negative y) and one to its left (negative x).
- The capture scale comes from the screen that contains the window.

### X-28 · Minor · §1, S0-2 · Matching a Dock item to a pid by URL misses common cases

**Finding.** Matching `kAXURLAttribute` to `NSRunningApplication.bundleURL` misses three cases:
- two copies of one app (the same URL);
- App Translocation (the Dock has the original path, the process runs from `/private/var/folders/…/AppTranslocation/`);
- apps updated in place.

**Proposal.**
- Match in order:
  1. the exact URL;
  2. the bundle id read from the URL's `Info.plist`;
  3. the item's `AXTitle` against `localizedName`.
- Read `AXIsApplicationRunning` from the item.
- When several pids match, show all their windows, grouped under an "N instances" header.
- S0-2 records each case.

### X-29 · Minor · §4.2 · Our own windows, "+N more" without the switcher, and 100-window apps

**Finding.**
- **Our own windows.** Hovering Snaptic's own Dock icon (shown while Settings is open) would list the preview panel
  itself.
- **"+N more"** opens the switcher, filtered to the app (PLAN:l.182). The switcher may be off.
- **Big apps.** An app with 100 windows means 100 AX window reads per hover.

**Proposal.**
- Exclude our panels by window number.
- Quitting Snaptic from the header goes through the normal quit path (`LaunchStability.markCleanQuit`).
- With the switcher off, "+N more" expands into compact title rows inside the panel.
- The Dock path reads only the windows that fit plus one, ordered by `CGWindowList` z-order (no AX). It reads the
  rest only for "+N more".

### X-30 · Minor · §4.5 · The Dock's name label sits in the panel's gap

**Finding.** The Dock draws the app's name label above the hovered icon, in the strip where a panel placed 6 pt off
the Dock would go (PLAN:l.215).

**Proposal.** S0-6 records whether the two overlap. If they do, measure the gap needed to clear the label (its frame
isn't in AX) and record it.

### X-31 · Minor · §4.12 · The raise kill switch's fallback may be declined

**Finding.** `Windows.disable.raise` falls back to `kAXRaiseAction` plus `activate`. From macOS 14, activation is
cooperative, so a request from an inactive app (Snaptic, behind a non-activating panel) may be declined **[U]**.

**Proposal.**
- S0-27 tests the fallback raise from the panel on 15 and 27.2.
- If it's declined, the fallback calls `yieldActivation(to:)` first.
- M16 adds a run with `Windows.disable.raise = 1`.

### X-32 · Minor · §4.3, §4.10 · Secure input and VoiceOver reach

**Finding.**
- **Secure input.** Under Secure Event Input the keys tap receives nothing, so keys in previews silently fail. The
  switcher already polls secure input (`WindowSwitcherModule.swift:224–239`).
- **VoiceOver.** "The panel is reachable with VoiceOver when it's shown" (PLAN:l.253) is unbacked:
  - The panel is a non-key `SnapticPanel` belonging to a background accessory app.
  - VoiceOver's cursor is in the Dock.
  - The switcher solves the same problem with announcements (`SwitcherController.swift:524–528`).

**Proposal.**
- **Secure input.**
  - The secure-input poll moves into `WindowServices`.
  - While secure input is on, the panel draws no selection ring and shows no key hints.
- **VoiceOver.**
  - With "Show with VoiceOver" on, announce "N windows: title, title, …", filtered for privacy (X-7), at high
    priority.
  - S0-16 records whether VoiceOver can move into the panel. §4.10 claims "reachable" only if it can.

### X-33 · Minor · §4.8, §4.15 · A pause reason must not leak a bundle id into diagnostics

**Finding.** "Paused while DockDoor runs" (PLAN:l.237–238) and "paused reason" in diagnostics (PLAN:l.293–294) could
put a third-party bundle id or app name into diagnostics or the EventLog. That would break PLAN:l.54.

**Proposal.**
- In diagnostics and the EventLog, the reason is an enum case: `otherTool`, `voiceOver`, `safeMode` or `killSwitch`.
- Only the Settings row and `dock status` (both local) show the tool's display name, taken from `KnownDockTools`.

---

## S0 gate coverage: revised and new rows

The current S0 rows don't test pixels, ownership, crash survival, tap coexistence, the indicator or reminder, the
Dock's own latency, or the wrong-app click. These rows close the gaps. They run on the 27.2 host and the 15 VM unless
noted otherwise.

| # | Check | Pass | Blocker | From |
|---|---|---|---|---|
| S0-3 (rev.) | `killall Dock` ×10; sleep/wake ×5; lock; FUS. Record whether `NSWorkspace` launch/terminate fire for `com.apple.dock` (LSUIElement) and how long `AXList` takes to appear | Re-attached within 2 s every time, by KVO + ladder | yes | X-17 |
| S0-4 (rev.) | `CGSHWCaptureWindowList` on the harness's own patterned window: on-screen (SCK reference), minimized, other Space, hidden, full screen. Image size and scale; p50/p95 time; peak memory over 100 calls on a 5K window; leaks and zombies over 1,000 calls. Result without Screen Recording is recorded only | 16×16 signature matches SCK within 10 %; peak growth under 150 MB; no leak. Otherwise Q3 = last-seen only on that OS | yes | X-4, X-5, X-19 |
| S0-5 (rev.) | Each §4.12 symbol, including the CGS fallbacks and `KBGetLayoutType`: `dlsym`, `dladdr` image, X-1 probe result | Each has a recorded image and probe, or is marked "presence only" | yes | X-1, X-24 |
| S0-9 (rev.) | Click actions: 100 background-app and 100 frontmost-app icon clicks under a synthetic main-thread load; reopen behaviour of Safari, Terminal and Finder with no windows | Zero wrong-app hides with the X-13 resolver | yes | X-13 |
| S0-13 (rev.) | Mission Control, App Exposé, the Apps view or Launchpad, Spotlight, Stage Manager with two stages, all with the panel up | `.transient` keeps the panel hidden; correct within 1 s after; no window-based detector needed | yes | X-16 |
| S0-14 (rev.) | Also: Dock AX read p50/p95/max during Mission Control, a launch bounce and magnification | Dock reads never block main for more than 16 ms | yes | X-15 |
| S0-16 (rev.) | VoiceOver: can it move into a non-key panel of a background app; are `.announcementRequested` posts spoken while its cursor is in the Dock | Recorded; §4.10 wording follows | no | X-32 |
| S0-17 | Each X-1 probe run 1,000× | Deterministic result; no side effect on window order, Spaces or symbolic hotkeys | yes | X-1 |
| S0-18 | Without Screen Recording: `CGWindowListCopyWindowInfo(.optionIncludingWindow)` owner pid for minimized and other-Space windows | Owner pid present (needed by the X-4 owner check) | yes | X-4 |
| S0-19 | Capture indicator, the "bypass the private window picker" reminder, Remote Desktop alerts, tccd CPU over 50 hovers (SCK and private) | No alert per call; indicator behaviour recorded and §4.7 default follows | yes | X-20 |
| S0-20 | Keys: (a) a `.nonactivatingPanel` that can become key gets keys without activating Snaptic, and focus returns on resign; (b) Dock keys tap plus switcher tap both installed: ⌥⇥ then arrows reach the switcher; (c) revoke Accessibility with the keys tap enabled on 27.2 | (a) recorded; (b) arrows reach the switcher; (c) no freeze over 30 s | yes | X-14 |
| S0-21 | 20 diagonal moves from an icon to the panel's far card, magnification on and off: record the sequence of selection changes | Data for the X-11 triangle: the swap-intent rule holds the original app in 20/20 | no | X-11 |
| S0-22 | Quit an unpinned app (from a script) while the pointer rests on its icon: record the reflow and when the selection changes | Recorded; the X-11 lockout covers it | no | X-11 |
| S0-23 | Per-pid window read: 1, 10, 50 and 100-window apps, with and without Screen Recording; other-Space windows without Screen Recording | p95 under 150 ms for 10 windows; untitled other-Space windows listed | yes | X-8, X-29 |
| S0-24 | Is a `sharingType = .none` panel visible in an SCK-based share (QuickTime, a browser meeting) on 15 and 27.2 | Recorded; Known limitations follows | no | X-7 |
| S0-25 | Panel up: right-click an icon, long-press, left-click the frontmost app, drag a file onto an icon. Record the Dock's `kAXMenuOpened`/`Closed` | The Dock menu is never covered; the panel doesn't return for the same item | yes | X-12 |
| S0-26 | `kAXWindowCreated`, `UIElementDestroyed`, `WindowMiniaturized`/`Deminiaturized`, `TitleChanged` for Safari, Chrome, an Electron app, Finder and Terminal; registration cost | Delivered within 0.5 s for each; cost recorded | yes | X-9 |
| S0-27 | Fallback raise (`kAXRaiseAction` + activate) from the non-activating panel | Raises in 10/10, or with `yieldActivation` first | no | X-31 |
| S0-28 | Pointer monitor cost while the panel is up, with a 1 kHz mouse | Under 2 % CPU on one core; nothing installed while hidden | no | X-10 |

**New manual checks.**
- **M35.** Crash-guard drill (X-2): forced `Windows.inFlight`, stopped row, Try Again; in Safe Mode the switcher has
  no private capture.
- **M36.** Right-click a Dock icon with the panel up: the Dock menu is never covered (X-12).
- **M37.** 50 background-app clicks with click action Hide: nothing is hidden (X-13).
- **M38.** Screen share while hovering: private windows are never visible (X-7).
- **M39.** Revoke Screen Recording while running: the cache is purged and cards are text-only by the next show
  (X-4, X-18).

These new M numbers apply to 0.5's `MANUAL-CHECKS.md`; they're unrelated to 0.4's M38.

---

## Summary table

| ID | Sev | Area | One line |
|---|---|---|---|
| X-1 | Blocker | H3, §4.12 | `KitEncoding` and exception poisoning can't apply to `dlsym`'d C functions; replace with image check, OS gate, behavioural probe, crash guard |
| X-2 | Blocker | Q3, §4.12, Safe Mode | A crash in `CGSHWCaptureWindowList`/raise loops on every hover; Safe Mode still runs the switcher, which now captures privately; needs a per-symbol in-flight crash guard |
| X-3 | Blocker | §4.3 | Bare W/M/Q/Return swallowed while the pointer rests on the panel: quits and closes apps mid-typing; use ⌘ and an "engaged" rule |
| X-4 | Major | §4.7, Q3 | Private capture must require Screen Recording and an owner check, never "works without it" |
| X-5 | Major | Q3, S0-4 | Private capture may return grey on 27 like `CGWindowListCreateImage`; content check; last-seen never downgrades |
| X-6 | Major | §4.11, A1 | Shared `ThumbnailStore`: one generation cancels the other module's captures; the switcher's prune erases last-seen entries |
| X-7 | Major | §4.2 privacy | Dock panel lacks `markPrivacy`, protected apps and blocked bundles; settings live in the switcher config |
| X-8 | Major | §1, §4.6 | `WindowGatherer` claim wrong; `loadWindows` is all-apps; other-Space windows vanish without Screen Recording and have no AX actions |
| X-9 | Major | §1, §4.6 | `FocusTracker` sees only focus changes; cached cards go stale; add window notifications and re-resolve before actions |
| X-10 | Major | §4.1, §4.4 | Pointer source unspecified (vs "no polling"); Dock frame undefined under magnification and auto-hide |
| X-11 | Major | §4.1, §4.3 | Instant swaps on diagonal travel; Dock reflow after Quit puts the next click on another app's Quit |
| X-12 | Major | §4.4 | Panel returns over the Dock's own menu after a click; dismiss latch plus Dock menu notifications |
| X-13 | Major | §4.9 | Click action can hide the app just clicked; frontmost-at-mouse-down history; act on mouse-up |
| X-14 | Major | §4.3, M26 | Keys tap is active, rebuilt per entry (breaker resets), shadows the switcher's tap; M26 tests the wrong tap |
| X-15 | Major | §2, S0-14 | Dock AX reads have no thread; the Dock draws Mission Control; move to an observer thread |
| X-16 | Major | §4.4 | Mission Control detection by window is the AltTab-on-27 bug; rely on `.transient` |
| X-17 | Major | §1, M8 | Dock re-attach relies on unverified LSUIElement notifications and one attempt; KVO, ladder, silent-death check |
| X-18 | Major | §2, M3 | Purge, consent revocation and in-flight teardown rules tied to the switcher's old lifecycle |
| X-19 | Major | §4.6 | Full-resolution private captures break the 96 MB budget (about 236 MB peaks) |
| X-20 | Major | §4.7 | SCK per hover: system reminder and Remote Desktop alerts, tccd cost, indicator blinking; throttle and reword |
| X-21 | Minor | §4.6 | Cache numbers diverge; split freshness from retention |
| X-22 | Minor | Ground rules | "No synthetic events" contradicts `SLPSPostEventRecordTo` raise; reword; L2 pattern |
| X-23 | Minor | Lint 11 | Rule 11 doesn't limit which shims may `dlsym`, and must follow the moved API file |
| X-24 | Minor | §4.12 | Table misses `KBGetLayoutType`, public dynamic lookups, CGS fallbacks |
| X-25 | Minor | §4.4 | Right-click menu races the grace timer; own-action signal window |
| X-26 | Minor | §4.1 | Keyboard and Switch Control Dock selection flaps the panel |
| X-27 | Minor | §4.5 | Coordinate convention unnamed; capture scale from `NSScreen.main` |
| X-28 | Minor | S0-2 | Dock item → pid by URL misses two copies and App Translocation |
| X-29 | Minor | §4.2 | Own panel in own list; "+N more" needs the switcher; 100-window reads |
| X-30 | Minor | §4.5 | The Dock's name label sits in the 6 pt gap |
| X-31 | Minor | §4.12 | Raise fallback activation may be declined (cooperative activation) |
| X-32 | Minor | §4.3, §4.10 | Secure input silences keys; VoiceOver reach unbacked; use announcements |
| X-33 | Minor | §4.15 | Pause reason must be an enum in diagnostics, no bundle id |
