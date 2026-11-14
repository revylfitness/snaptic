# 0.5 plan review r2: Adversarial (failure modes, races, private APIs, privacy)

Reviewer: adversarial subagent, round 2. Plan: `docs/design/0.5/PLAN.md` (r2, 1,349 lines). Grounding: the Snaptic
tree at `7dd972c` on `feature/v050-dock-previews` (Switcher, Icons, Core, SnapticKit), `docs/design/macos27.md`,
`.github/workflows/build.yml`, `Package.swift`, and `review-r1-adversarial.md` so this round doesn't repeat it.

One read-only fact comes from this Mac (macOS 27.2, 26B123). A throwaway C program called `dlsym` and `dladdr` on
each §4.12 symbol and printed the image path. It called none of the symbols, and it was deleted afterwards. Nothing
else was launched, signalled, tapped or captured. No defaults were written. No DockDoor or AltTab source was read.

The owner decisions Q1–Q7 stand. No finding reopens them. X2-2 changes how the OS gate behaves on an unverified major
and keeps the gate itself, so Q6 is untouched.

Citations: `PLAN:l.N` is a line of the r2 plan. `path:line` is a line of the tree, relative to `Sources/Snaptic/`
unless the path starts with `Sources/SnapticKit/`, `docs/`, `.github/` or `Package.swift`.

Severity counts: **2 Blockers, 8 Majors, 14 Minors.**

## Were r1's Blockers closed?

- **X-1 (C symbols have no encoding check): mostly closed.** §4.12 replaces the encoding check with presence, image,
  OS gate, prototype, probe, result checks and a crash guard. Three parts are still wrong:
  - the result-check rule poisons symbols on normal answers (X2-1);
  - the image rule names the wrong image for two symbols (X2-7);
  - several probes can't fail, or fail for the wrong reason (X2-6).
- **X-2 (a crash loops on every hover): narrowed, not closed.** Safe Mode now skips private capture (§4.13). But:
  - the in-flight marker is one shared key, written asynchronously, and it stops after 20 calls (X2-4);
  - the ⌘⇥ give-back path has no guard, and it runs before Safe Mode is decided (X2-3).
- **X-3 (bare letters quit apps): closed for bare letters.** They are never handled (PLAN:l.569, M40). ⌘W, ⌘H and ⌘Q
  still reach the previewed app after a 1-pixel drift, for up to 10 s, and autorepeat runs them over and over (X2-5).

## Facts this review relies on

- **The image rule doesn't match 27.2.** `dladdr` on this Mac puts these symbols here:
  - `_AXUIElementGetWindow` and `GetProcessForPID`: **HIServices**
    (`ApplicationServices.framework/Frameworks/HIServices.framework`);
  - `IsSecureEventInputEnabled`, `KBGetLayoutType` and `LMGetKbdType`: HIToolbox;
  - every `SLS*`, `CGS*` and `SLPS*` symbol in the table, including the `CGS` fallbacks: SkyLight.
- **Secure input fails open today.** A missing `IsSecureEventInputEnabled` reads as "off"
  (`Switcher/PrivateAPIs.swift:93–95`). While the check reads "on", the switcher is cancelled every 0.5 s and gives
  ⌘⇥ back (`Switcher/WindowSwitcherModule.swift:224–233`).
- **Launch order.** Step 4 gives ⌘⇥ back (`Core/AppDelegate.swift:57–58`). Launch stability and Safe Mode come after
  it, at steps 5 and 6 (`:59–61`). `recoverFromPreviousRun` removes its saved list and *then* calls the setter
  (`Switcher/PrivateAPIs.swift:153–161`). `apply` saves the list *before* it calls the setter (`:175–177`).
- **Launch stability can't see crashes that happen while hovering.** A launch counts as stable after 60 s
  (`Core/LaunchStability.swift:12–23`).
- **UserDefaults persists asynchronously.** Apple's `UserDefaults` reference says a set value "is changed synchronously
  within your process, and asynchronously to persistent storage and other processes". 0.4's marker uses a plain `set`
  (`Icons/IconsModule.swift:1152–1157`).
- **`WindowManager.start()` starts `FocusTracker`** (`Switcher/WindowManager.swift:188–207`). That starts its own
  thread and an AX observer for every running app (`:682–690`).
- **The target app answers `_AXUIElementGetWindow`.** The tree already distrusts it: "The window ID comes from the app
  itself, so only trust it if the window server agrees" (`Switcher/WindowManager.swift:376–380`).
- **An empty Spaces array is a normal answer, not an error.** The switcher uses it to drop inactive native tabs and
  helper windows (`Switcher/WindowManager.swift:283`, `:452`).
- **The deployment target is macOS 14** (`Package.swift:57`). S0 runs on 27.2 and a 15 VM only (PLAN:l.982).

---

## Blockers

### X2-1 · Blocker · §4.12 step 5, ground rule 3 · Result checks poison symbols on normal answers, and any app can trigger it

**Finding.** Step 5 says each result is checked "for its type's rule (non-null, in range, the right count). Two bad
results in a row poison the symbol for the process." Several normal answers break that rule:

- **`_AXUIElementGetWindow`** fails whenever an app is busy (the 0.15 s AX timeout), a window closes during a read, or
  `FocusTracker` sees an element that isn't a window. The target app answers the call, so a Java, Electron or hostile
  app can return 0 or another app's id on purpose.
- **`SLSCopySpacesForWindows`** returns an empty array for every inactive native tab. That is the signal the switcher
  relies on (`WindowManager.swift:283`, `:452`). It returns NULL for a window that closed after it was listed.
- **`CGSHWCaptureWindowList`** returns nothing for a window that closed between the list and the capture.
- **The raise trio** fails for a process that quit a moment before.

Scenario:

1. The user has a Finder window with three tabs and presses ⌥⇥.
2. The two background tabs give empty Spaces arrays one after the other. That is "the wrong count", twice in a row.
3. Spaces is poisoned until Snaptic quits, which for a menu-bar app can be weeks. Its fallback drops the switcher's
   other-Space list (PLAN:l.766).

The same happens to `_AXUIElementGetWindow` the first time two windows of a hung app time out. Its fallback leaves
"cards without a match" with Bring Forward only (PLAN:l.764). Nothing shows the user why. Poisoning appears only in
diagnostics (PLAN:l.963), and the §4.17 row covers the crash guard only (PLAN:l.854–855).

So a literal implementation quietly removes shipped switcher features within minutes of normal use. Any app can cause
it on purpose.

**Evidence.** PLAN:l.751–752, l.78, l.764, l.766, l.854–855, l.963. `Switcher/PrivateAPIs.swift:74–79` (a non-success
result already means "no id"), `:84–89` (an empty array means "on no Space"). `Switcher/WindowManager.swift:283`,
`:376–380`, `:452`, `:540`, `:588–589`.

**Proposal.** Replace PLAN:l.751–752:

> 5. **Result checks.** `WindowSymbolContract` sorts each symbol's results into two classes:
>    - **No answer** (normal; never counts toward poisoning). AX errors (`cannotComplete`, `invalidUIElement`,
>      `apiDisabled`, `notImplemented`, `attributeUnsupported`). NULL or an empty array for a window that has no
>      Space or no longer exists. NULL from a capture of a window that closed. A raise error for a process that quit.
>      The caller falls back for that one window.
>    - **Impossible** (counts). A result that no working symbol can return for any input: `SLSMainConnectionID`
>      returning 0; a Spaces result that isn't a `CFArray`, or holds something other than a `CFNumber`; a capture
>      result that isn't a `CFArray` of `CGImage`, or holds an image of zero width or more than 4× the requested
>      pixels.
>    - **Answers an app controls never count.** The target app answers `_AXUIElementGetWindow`
>      (`WindowManager.swift:376–380`). Its result is either "no answer", or an id checked against the window
>      server's owner list. A mismatch drops that one id, as today.
>    - Two impossible results in a row poison the symbol. A poisoned symbol is probed once more after 10 minutes. A
>      pass clears it. A second poisoning lasts until Snaptic quits, and shows the §4.17 row with that feature's
>      name.

Add Kit tests: ten "no answer" results in a row never poison; two impossible results do; an owner mismatch never
does.

### X2-2 · Blocker · §4.12 step 2 and the symbol table · On an unverified macOS, "secure input treated as on" breaks the switcher

**Finding.** Step 2 makes every symbol "`unavailable` until a release adds" a new major (PLAN:l.742). The table includes
`IsSecureEventInputEnabled`, with the fallback "Treated as on" (PLAN:l.769). Step 1 checks "the Carbon calls" against
HIToolbox (PLAN:l.741), so it is subject to the gate.

Scenario: the user installs the macOS 28 beta in June, or the 28 release in the autumn.

1. `IsSecureEventInputEnabled` is `unavailable`, so it reads "on".
2. `watchSecureInput` sees `blind` every 0.5 s. It calls `SystemHotkeys.setSuspended(true)` and `controller.cancel()`
   (`WindowSwitcherModule.swift:229–232`).
3. ⌥⇥ opens the switcher, and the switcher closes within 0.5 s. The Dock keys tap never enables (PLAN:l.577–578).

The Window Switcher is a shipped module that works on any macOS today, because a missing symbol reads as "off"
(`PrivateAPIs.swift:93–95`). Under r2 it stops working on the first day of the next major, and stays broken until
Snaptic ships an update.

The rest of the gate costs the switcher every other private feature at the same moment: window ids (thumbnail
matching), Spaces (the other-Space list), the raise path and ⌘⇥. r1 X-1 proposed that "on a newer major version, only
the probe runs until it passes". r2 made the gate stricter than that and gives no reason.

The same failure can happen sooner:

- if Apple moves the symbol's implementation to another image in a 27.x update, the image check fails (X2-7);
- if Safe Mode counts the symbol as private, Safe Mode calls nothing "except the symbolic-hotkey pair"
  (PLAN:l.788). Then the switcher that Safe Mode promises still runs is cancelled every 0.5 s.

**Evidence.** PLAN:l.741–742, l.769, l.577–578, l.787–789, l.82 ("A failure fails safe"). `PrivateAPIs.swift:57`,
`:93–95`. `WindowSwitcherModule.swift:224–233`. `review-r1-adversarial.md:85–86` (r1 X-1's gate wording).
`SnapticKit/IconsEngineCore.swift:140` (0.4's factory treats a newer major as known, `osMajor >= nativeMajor`).

**Proposal.** Replace PLAN:l.742:

> 2. **OS gate.** A major is *verified* when S0 has run on it (X2-22). On any other major:
>    - read-only symbols (`SLS`/`CGSMainConnectionID`, `SLS`/`CGSCopySpacesForWindows`, `_AXUIElementGetWindow`,
>      `SLS`/`CGSIsSymbolicHotKeyEnabled`) run their probes. A pass makes them available. Their crash guard is never
>      marked verified on that major, so the marker stays on;
>    - symbols that write or capture (`CGSHWCaptureWindowList`, the raise trio, the symbolic-hotkey setter) stay
>      `unavailable` until a release adds the major. Their fallbacks run;
>    - `IsSecureEventInputEnabled` is exempt (below).

Replace the table row at PLAN:l.769:

> | `IsSecureEventInputEnabled` | Secure input | none (public API in HIToolbox; exempt from the OS gate and the image
> check; called in Safe Mode) | **Unknown**: the switcher doesn't take ⌘⇥, so macOS keeps it. ⌥⇥ and the Dock keys
> tap keep working, and nothing is cancelled |

Add to A1 or H3: `watchSecureInput` keeps two states apart. "Secure input on" gives ⌘⇥ back and cancels, as today.
"Unknown" only gives ⌘⇥ back. Add a selftest line, `windows secureInput available|unknown`.

---

## Majors

### X2-3 · Major · H6, §4.12 step 6, §4.13 · The ⌘⇥ give-back path has no crash guard, and runs before Safe Mode is decided

**Finding.** H6 says "Giving it back always runs" (PLAN:l.379–381), and Safe Mode still calls the symbolic-hotkey pair
(PLAN:l.788). The plan never says at which launch step a crash marker is read (PLAN:l.755 says only "at launch").

Scenario: a 27.3 update changes `SLSSetSymbolicHotKeyEnabled` so that it crashes.

1. The switcher starts. `apply` saves `[1, 2]` and calls the setter (`PrivateAPIs.swift:175–184`). Snaptic crashes.
2. Next launch, step 4: `recoverFromPreviousRun` reads `[1, 2]`, removes the key and calls the setter
   (`:153–161`). Snaptic crashes again, before step 5 (`AppDelegate.swift:57–61`), so launch stability never records
   this launch.
3. The removal in step 2 is persisted asynchronously, so it can be lost in the crash. If it is lost, every launch
   repeats step 2. That is a crash loop at launch that launch stability can't see, Safe Mode can't stop, and the kill
   switch doesn't cover ("Giving it back always runs").
4. If the removal is kept, the next launch starts the switcher again. The switcher takes ⌘⇥ again and crashes again,
   unless the marker from step 1 was read before modules start. The plan doesn't say it is.

The only way out is `defaults delete` by hand.

**Evidence.** PLAN:l.379–381, l.753–757, l.788. `Core/AppDelegate.swift:57–61`. `Switcher/PrivateAPIs.swift:153–161`,
`:175–188`. `Core/LaunchStability.swift:12–23`.

**Proposal.** Add to H3:

> **Launch order.** A new step 3b, before step 4: `CrashGuard.atLaunch` reads every in-flight marker (X2-4) and records
> the disabled builds. Step 4 skips the give-back when the setter is disabled on this build, and logs EventLog
> `.safety`. `recoverFromPreviousRun` makes the removal of its saved list durable (the X2-4 marker store) before it
> calls the setter.

Replace "Giving it back always runs" in PLAN:l.379 and l.767:

> Giving it back always runs, except when the crash guard has disabled the setter on this OS build. Then the Switcher
> page shows: "macOS may keep ⌘⇥ off until you log out. Snaptic couldn't give it back." S0-5 records whether a disabled
> symbolic hotkey survives logout, and the text follows that result.

§4.13: "the symbolic-hotkey pair, unless the crash guard disabled it on this build".

### X2-4 · Major · §4.12 step 6, §8 · The crash marker is one shared key, written asynchronously, and it stops after 20 calls

**Finding.** Step 6 sets `Windows.inFlight = "<symbol>@<build>"` before each call and clears it after (PLAN:l.754).
There are three problems.

- **One key, many threads.** Private calls run at the same time on different threads:
  - `FocusTracker`'s callback thread (`WindowManager.swift:588–589`);
  - background enumeration (`:379`);
  - the raise path (`:536–540`);
  - capture (one at a time, PLAN:l.689–690);
  - the `HotkeyGuard` timer (`PrivateAPIs.swift:268–270`).

  Call A sets the key, call B sets it, A clears it, and B crashes with no marker. Or a crash in A is recorded as B.
- **The write may not survive the crash.** `UserDefaults` persists asynchronously. The crash comes microseconds after
  the write. Launch stability doesn't catch a crash that happens while hovering (60 s rule), so a lost marker means a
  crash on every hover. That is r1 X-2's scenario again.
- **Verification ends the guard.** After 20 successes on a build, `verifiedBuild` stops the marker writes
  (PLAN:l.756). Capture and raise crashes depend on the input: a particular window state, a backing format or a
  process state. Such a crash can first appear on call 21. It then crashes on every hover over that app, with no guard
  left.

The risk row says "one crash per OS build" (PLAN:l.1164). It is really one crash per symbol per build, and that holds
only before verification. M35 uses "a DEBUG forced marker at launch" (PLAN:l.1139), so it never tests whether a real
crash leaves a marker.

**Evidence.** PLAN:l.753–757, l.1077, l.1139, l.1164. `Icons/IconsModule.swift:1152–1157`.
`Switcher/WindowManager.swift:379`, `:536–540`, `:588–589`. `Switcher/PrivateAPIs.swift:268–281`.
`Core/LaunchStability.swift:17–18`.

**Proposal.** Replace PLAN:l.754–756:

> - **One marker per symbol**, in a file: `~/Library/Application Support/Snaptic/inflight/<symbol>`, holding the OS
>   build. An in-process atomic counter per symbol writes the file when it goes 0→1 (`open` plus `write(2)`) and
>   unlinks it when it goes 1→0. A completed `write(2)` survives a process crash; only a kernel panic can lose it.
>   UserDefaults keeps only `disabledBuild` and `verifiedBuild`.
> - **Verification** stops the marker only for the read-only calls (`_AXUIElementGetWindow`, Spaces,
>   `SLSMainConnectionID`, `IsSymbolicHotKeyEnabled`). `CGSHWCaptureWindowList`, the raise trio and the hotkey setter
>   keep their marker on every call. They are rare: at most 8 a second while a panel shows, and one per click.

Risk row PLAN:l.1164: "Crash guard: one crash per symbol per OS build (up to seven), then that symbol stays off until
Try Again or an OS update."

M35 adds a real crash. A DEBUG `SNAPTIC_DEBUG_TRAP_IN=<symbol>` traps between the marker write and the call. Relaunch:
the row shows. Kit test: two overlapping calls to different symbols; a crash in either leaves only its own marker.

### X2-5 · Major · §4.5 · ⌘W, ⌘H and ⌘Q still act on the previewed app after a 1-pixel drift, and autorepeat runs them again and again

**Finding.** "Engaged" means the pointer "is inside it and has moved since it entered" (PLAN:l.563–564). It lasts
until "10 s pass without movement" (PLAN:l.565). Any movement counts, including the 1-pixel drift of a resting mouse
or a palm on a trackpad.

Scenario:

1. In Safari, the user moves the pointer down to glance at the Dock. A Mail panel shows, and the pointer slides into
   it.
2. The user decides not to switch, and presses ⌘W to close the Safari tab, or ⌘Q to quit Safari.
3. ⌘W closes the Mail window under the pointer. ⌘Q quits Mail (PLAN:l.570: "acts only on the previewed app").
   Terminal and Chrome quit without asking.

Three more gaps:

- **⌘ itself.** Pressing ⌘ arrives as `flagsChanged`. If that counts as "a key that isn't in the table", it disengages
  the panel and ⌘W can never work. If it doesn't count, the plan should say so. It's unspecified.
- **Autorepeat.** Holding ⌘W repeats the key about every 33 ms after the initial delay. Each repeat closes the card
  under the pointer. Cards update in place (PLAN:l.556), so the next card slides under the pointer. A one-second hold
  closes every window of the app.
- **Key-up.** The tap swallows the ⌘W key-down. The key-up reaches the frontmost app on its own.
  `docs/design/macos27.md:53` records apps and Control Center misbehaving on orphan key-ups and autorepeats on 27.

**Evidence.** PLAN:l.563–570, l.556, l.492–493 (the header already has a 300 ms guard for double clicks), l.1144
(M40 tests bare letters only). `docs/design/macos27.md:53`.

**Proposal.** Replace PLAN:l.563–566:

> - **Engaged.** The pointer has moved at least 4 pt in total inside the panel within the last 3 s, and a card's
>   selection ring has been visible for at least 250 ms. A click in the panel also engages it.
>   - It disengages when the pointer leaves, the panel hides, 3 s pass without movement, or a key-down arrives that
>     isn't in the table. `flagsChanged` never disengages it.
>   - **Autorepeat** (`kCGKeyboardEventAutorepeat` = 1) of a table key is swallowed and does nothing.
>   - After a card closes or minimizes, keys do nothing for 300 ms while the cards reflow.
>   - The key-up of a handled key is swallowed too. The tap remembers the key code until its key-up arrives or 1 s
>     passes.

Kit tests: drift under 4 pt, then ⌘W: the key passes through. Hold ⌘W for 1 s: one window closes. M40 gains: "Move
into the panel, wait 4 s, press ⌘W: the frontmost app's tab closes."

### X2-6 · Major · §4.12 step 4, S0-17, contingencies · Several probes can't fail, or fail on a healthy Mac, and their timing isn't specified

**Finding.**

- **Spaces probe.** "`SLSCopySpacesForWindows` on our own panel returns a one-element array" (PLAN:l.746).
  - Both panels join all Spaces (`Switcher/SwitcherWindow.swift:36`; PLAN:l.611–612). For such a window, the call may
    return every Space or none. On a Mac with three desktops, "one element" can fail.
  - The probe runs "before first use". The first use is the first ⌥⇥, before the switcher panel is ordered in (it
    shows after 70 ms). A window that isn't ordered in has no Space.
  - Either way, the probe fails on a healthy Mac, and the switcher loses its other-Space list for the process.
- **AX window probe.** `_AXUIElementGetWindow` "returns our own window's `windowNumber`" (PLAN:l.747).
  - AppKit answers AX requests to Snaptic on Snaptic's main thread. A probe sent from main waits on itself until the
    timeout. One sent from a background thread needs main to be free.
  - The plan doesn't say which thread, which window, or whether Accessibility must already be granted.
- **Hotkey probe.** "`SLSIsSymbolicHotKeyEnabled` returns a Bool" (PLAN:l.749). Any C return value is a Bool once
  it's cast. The probe can't fail, and S0-17's "same result every time" (PLAN:l.1005) is trivially true.
- **Capture probe.** It captures "our own patterned window" (PLAN:l.748). That window must be ordered in somewhere: on
  screen it flashes, and off screen it may come back blank on 27 (`docs/design/macos27.md:38`). It also tests an
  on-screen window, while the private path is used only for minimized and other-Space windows (PLAN:l.677).
- **Contingency.** "S0-4 or S0-17 fails: no private capture" (PLAN:l.1043). S0-17 also covers the Spaces, AX window
  and hotkey probes. If those fail, the plan has no decided outcome.

**Evidence.** PLAN:l.744–750, l.611–612, l.677, l.1005, l.1043. `Switcher/SwitcherWindow.swift:36`.
`Switcher/PrivateAPIs.swift:84–89` (mask `0x7`; today's code tests `> 0`, not `== 1`). `docs/design/macos27.md:38`.

**Proposal.** Replace PLAN:l.744–750:

> 4. **Probe**, once per process, at the first `WindowServices.acquire`, off main, on one serial queue. A caller that
>    arrives before the probe finishes gets the fallback for that call.
>    - **Probe window.** A dedicated 64 × 64 borderless window: normal collection behaviour (not `canJoinAllSpaces`),
>      `sharingType = .none`, `.ignoresCycle`. It's ordered in at a frame outside every screen, drawn with a two-colour
>      pattern, and ordered out after the probes. S0-5 records that it never appears in Mission Control.
>    - `SLSCopySpacesForWindows` on the probe window returns a `CFArray` of at least one `CFNumber`.
>    - `_AXUIElementGetWindow` on the probe window's AX element, sent from the probe queue, returns its
>      `windowNumber`. Without Accessibility, the probe is deferred until it's granted.
>    - `CGSHWCaptureWindowList` on the probe window: S0-4 records whether an off-screen window of our own captures with
>      content on 15 and 27.2. If it does, the image must match the pattern. If not, this probe is presence-only, and
>      X2-8's re-probe rule guards the content.
>    - **Symbolic hotkeys:** presence only at the probe. At the first take, read back after the set. If
>      `IsSymbolicHotKeyEnabled` doesn't return false after `Set…(false)`, set it back to true and mark the take
>      unavailable for the process.

Contingency PLAN:l.1043: "S0-17 fails for a probe: that symbol ships `unavailable` and uses its §4.12 fallback. For
the capture symbol, minimized and other-Space cards use last-seen, then the icon."

### X2-7 · Major · §4.12 step 1 · The image rule names the wrong image for `_AXUIElementGetWindow` and `GetProcessForPID`

**Finding.** Step 1 expects "SkyLight for `SLS*`, `SLPS*` and `CGSHW*`; HIToolbox for `KB*` and the Carbon calls"
(PLAN:l.740–741). On this Mac (27.2, 26B123):

- `_AXUIElementGetWindow` lives in **HIServices**. The rule names no image for it.
- `GetProcessForPID`, a Carbon Process Manager call, lives in **HIServices**, not HIToolbox.
- The `CGS` fallbacks (`CGSMainConnectionID`, `CGSCopySpacesForWindows`, the `CGS…SymbolicHotKey…` pair) live in
  SkyLight, but the rule lists only `CGSHW*`.

A literal implementation marks the AX window id, the raise trio and every `CGS` fallback `unavailable` on every OS.
The `macos-15` CI expectation "Any other state fails the run" (PLAN:l.777–778) would catch it. The contract text is
still wrong, and B1b builds `WindowSymbolContract` from it.

An exact-image rule is also fragile. Apple moves implementations between images (the `CGS` calls moved into SkyLight
in the past). A 27.x update that moves a symbol would turn a feature off on a verified major, with no crash and no
fault.

**Evidence.** PLAN:l.740–741, l.761–769, l.777–778, l.993 (S0-5 records `dladdr`). The reviewer's `dladdr` output on
27.2, summarised under "Facts this review relies on".

**Proposal.** Replace PLAN:l.740–741:

> 1. **Presence and image.** `dlsym` finds it, and `dladdr` reports an image from that symbol's list in
>    `WindowSymbolContract.images`:
>    - SkyLight for `SLS*`, `SLPS*` and `CGS*`;
>    - HIServices for `_AXUIElementGetWindow` and `GetProcessForPID`;
>    - HIToolbox for `KBGetLayoutType` and `LMGetKbdType`.
>
>    S0-5 fills the list per OS. On a verified major, an image outside the list means `unavailable`, and diagnostics
>    say `imageMoved` so the next release can add it. `IsSecureEventInputEnabled` is exempt (X2-2).

### X2-8 · Major · §4.9 content check · Plain windows count as blank, and three of them turn the private path off for the process

**Finding.** "A capture whose 16 × 16 luma has a standard deviation under 2 is treated as blank … Three blanks in a
row turn the private path off for the process" (PLAN:l.679–681). Many real windows are that plain once they're
reduced to 16 × 16:

- an empty TextEdit or Pages document;
- an idle Terminal;
- a dark-mode window with little content;
- a paused black video.

Scenario: a user has three minimized empty documents. One hover over that app's Dock icon gives three blanks in a
row. The private path is off until Snaptic quits. Every minimized and other-Space card in both modules falls back to
last-seen or the icon, for days.

The check can't tell a grey failure on 27 (`docs/design/macos27.md:38`) from a grey window. A plain window never gets
a thumbnail at all: "the cache never replaces a real image with a blank one".

**Evidence.** PLAN:l.679–682, l.763. `docs/design/macos27.md:38`.

**Proposal.** Replace PLAN:l.679–681:

> - **Content check (X-5).** A capture whose 16 × 16 luma has a standard deviation under 2 is *suspect*. The card keeps
>   its last-seen thumbnail or the icon. After three suspects in a row, from at least two different windows, the
>   private path re-runs the probe-window capture (§4.12 step 4):
>   - **The probe passes:** the path works and those windows are plain. Suspects from this window are accepted from
>     now on, and the counter resets.
>   - **The probe fails:** the private path is off for the process.
>
>   Any non-suspect capture resets the counter.

Kit test: three plain windows, probe passes: the path stays on. Three grey results, probe fails: the path is off.

### X2-9 · Major · §2.3, ground rule 1 · The first lease starts `WindowManager`, which breaks the Dock's idle promise, and freshness has no thread

**Finding.** §2.3 says "The first lease starts `WindowManager`" (PLAN:l.255). `WindowManager.start()` starts
`FocusTracker` (`WindowManager.swift:188–207`), which starts a thread and puts an AX observer on every running app
(`:682–690`). The same section says the Dock's idle lease "registers notification-centre observers only: no thread,
timer or AX observer" (PLAN:l.262–263). Ground rule 1 says the same (PLAN:l.65).

Scenario: a user turns the switcher off and Dock Previews on. The Dock's lease is the first lease. Under l.255, an
idle Dock module holds an AX observer on every app and a tracking thread. Under l.262, it holds none. The plan says
both.

`.freshness(pid)` needs an AX observer on a run-loop thread (PLAN:l.248–250). With the switcher off, no
`FocusTracker` thread exists. The plan doesn't say where freshness runs.

M32 counts "running apps + 1 with the module on and a preview shown" (PLAN:l.1136). That assumes the switcher's
observers exist. There is no Dock-only row.

**Evidence.** PLAN:l.65, l.248–257, l.262–264, l.1136. `Switcher/WindowManager.swift:188–207`, `:635–690`.

**Proposal.** Replace PLAN:l.255–257:

> - **The first lease** sets the system-wide AX messaging timeout to 0.15 s and registers the purge observers.
>   `FocusTracker` starts with the first `.recency` need and stops with the last. **The last release** cancels
>   in-flight captures, purges the store and removes every observer.
> - **`.freshness(pid)`** runs on its own `ObserverThread`. The thread starts with the first freshness need and stops
>   2 s after the last. An idle lease never starts it.

Add to M32: "Switcher off, Dock Previews on: 0 AX observers while idle; 1 while a preview shows; 0 again 2 s after it
hides."

### X2-10 · Major · §4.1 rule 5 · The exact item-frame test misses shows at the screen edge and while icons magnify, and nothing tests again

**Finding.** A selection change shows only when the pointer is "inside the selected item's frame". When no monitor is
installed, the controller reads the pointer once (PLAN:l.460–462). No monitor exists until a show is pending
(PLAN:l.283). A selection that fails the test is never tested again.

- **The screen edge.** Users push the pointer against the bottom edge. The Dock still selects the item there. If
  S0-1's frames stop short of the edge, the test fails and nothing shows until the pointer leaves and comes back.
- **Magnification.** The selection lags the pointer "by a frame or two" (PLAN:l.458), and frames grow as icons
  magnify. Scenario: the pointer stops near the edge of icon B. B's selection arrives, but the frame read is from
  before B grew, so the pointer is outside it. The selection doesn't change again, so the panel never shows while the
  pointer rests on B.

The plan already grows the Dock zone by 24 pt for magnification (PLAN:l.476). The agreement test uses the bare frame.

**Evidence.** PLAN:l.283, l.458–462, l.473–478, l.606–607 (placement already waits for settled frames), l.989 (S0-1).

**Proposal.** Replace PLAN:l.460–462:

> 5. **The pointer must agree.** A selection change shows or swaps only when the pointer is inside the Dock zone and
>    inside the selected item's *hit band*. The band is the item's frame grown along the Dock by half the gap to each
>    neighbour, and stretched across the Dock to the screen edge. If the test fails, the show stays pending for up to
>    0.5 s. The pointer monitor is installed, and the test re-runs on each move and on the next settled frame read. If
>    it still fails after 0.5 s, the monitor is removed.

K2 test: a selection arrives with the pointer 2 pt outside the frame, then the frame grows. The panel shows.

---

## Minors

### X2-11 · Minor · §2.3, §2.5, §2.6 · Turning the switcher's Thumbnails off no longer purges its thumbnails, and the switcher can show the Dock's

**Finding.** Today, turning Thumbnails off calls `ThumbnailStore.shared.purge()` (`WindowSwitcherModule.swift:248–254`).
In r2, `purge(client:)` runs only on `release` (PLAN:l.270). The purge triggers cover all clients only (PLAN:l.313–320).
Dropping `.thumbnails` in `update(_:needs:)` purges nothing. §2.6 also says the switcher "shows thumbnails the Dock
captured" (PLAN:l.336), but doesn't say what happens when the switcher's own Thumbnails setting is off.

Scenario: Dock Previews is on with its Thumbnails on, so the "no live lease with `.thumbnails`" trigger
(PLAN:l.320) never fires. The user turns the switcher's Thumbnails off. ⌥⇥ still shows thumbnails, taken by the Dock
or kept from before.

**Evidence.** PLAN:l.251, l.270, l.313–320, l.336. `Switcher/WindowSwitcherModule.swift:248–254`.

**Proposal.** Add to PLAN:l.270: "`update(_:needs:)` that drops `.thumbnails` runs `purge(client:)` for that client at
once. A client without `.thumbnails` gets no thumbnails from any lookup, its own or another client's."

### X2-12 · Minor · §2.5 · `purge(client:)` doesn't make a capture that's still running stale, and "cancel synchronously" can't be done

**Finding.** Only `purgeAll()` bumps `epoch` (PLAN:l.323). `purge(client:)` bumps nothing. An SCK screenshot or a
private capture can't be stopped once started, so "`release` cancels that client's in-flight captures synchronously"
(PLAN:l.325) can only mean "makes them stale". As written, a capture that finishes after the switcher's `release`
lands in the store under a client that no longer exists. If the Dock still holds a lease, that entry stays for up to
30 minutes, and Dock lookups can read it.

**Evidence.** PLAN:l.268–270, l.323–325. `Switcher/ThumbnailStore.swift:68–88` (today's single `generation`).

**Proposal.** Replace PLAN:l.325: "`release` and `purge(client:)` first bump that client's `generation`, then drop its
entries. A capture that finishes later carries the old stamp and is dropped. The calls themselves run to the end."

### X2-13 · Minor · §2.5, ground rule 7 · Retention is checked only while a panel shows, so "kept at most 30 minutes" is false

**Finding.** Ground rule 7 says "an entry is kept at most 30 minutes" (PLAN:l.97). The README text says "Kept in memory
for at most 30 minutes" (PLAN:l.337). But the sweep "runs only while a client is showing (no idle timer)"
(PLAN:l.321–322). Scenario: a thumbnail of a minimized window is taken at 9:00. The Mac stays unlocked, and no panel
shows all day. The thumbnail is still in memory at 17:00.

**Evidence.** PLAN:l.97, l.321–322, l.337.

**Proposal.** Replace PLAN:l.321–322: "Every entry expires 30 minutes after its capture. One one-shot timer is set for
the earliest expiry while the store holds entries. It's re-armed after each sweep and cancelled when the store is
empty, so an empty store has no timer."

### X2-14 · Minor · §4.9 · Checking Screen Recording once per batch leaves the private path running after the user revokes it

**Finding.** "Every capture … needs" Screen Recording granted, "checked once per batch" (PLAN:l.665–667). SCK enforces
consent itself. The private path may not: S0-4 records its result "Without Screen Recording" (PLAN:l.992). A batch of
30 windows at 8 a second runs for about 4 s. Captures after a revocation in that time still run. The text also says
"every capture" but checks per batch.

**Evidence.** PLAN:l.665–667, l.689, l.992. `Switcher/ThumbnailStore.swift:67`, `:97`.

**Proposal.** Replace PLAN:l.667: "`CGPreflightScreenCaptureAccess()` is true. It's checked before each private-path
capture, and once per batch for SCK, which enforces consent itself."

### X2-15 · Minor · §2.4, §4.5 · No `switcherClosed` event, so the Dock can't hold back while the switcher is open, or know when to resume

**Finding.** The policy gets only `switcherOpened` (PLAN:l.292). Nothing stops a new show while the switcher is still
open. Scenario: the user holds ⌥ with the switcher open and moves the pointer across the Dock. A Dock panel shows next
to the switcher. Its keys tap stays off while `switcherSessionActive` (PLAN:l.573), so the panel ignores keys.

**Evidence.** PLAN:l.292, l.308, l.573.

**Proposal.** Add a row to PLAN:l.292: "`switcherClosed`: `switcherSessionActive` becoming false." Add to §4.1: "While
the switcher is open, selection changes never show or swap. The first selection change after it closes is handled
normally."

### X2-16 · Minor · §4.8, §4.17 · State 5 sticks for the whole session when the Dock is slow at login

**Finding.** The re-attach ladder ends after about 3.85 s. Then the module "does nothing until the Dock restarts or Try
Again" (PLAN:l.632–637). It shows a menu-bar attention mark (PLAN:l.857). Snaptic is a login item. If the Dock's
`AXList` isn't ready within those few seconds of login, previews are off all day and the attention mark is lit.

**Evidence.** PLAN:l.632–637, l.841, l.857.

**Proposal.** Add to PLAN:l.636–637: "In state 5, the 30 s health check keeps running and moves to state 9 on success.
Within 2 minutes of login, the ladder adds 5 s and 10 s steps. The attention mark shows only after state 5 has lasted
2 minutes."

### X2-17 · Minor · §4.11 · Click actions don't say how a new window is detected, or how a click maps to an item

**Finding.** "Hide is skipped if a window was created in that time" (PLAN:l.727). With no preview showing, no
freshness lease exists (PLAN:l.261), so there is no `kAXWindowCreatedNotification` to see. "Mouse-up lands on the same
item" (PLAN:l.725) needs an item for a point. An AX hit test from the tap callback could block. On 27.2, a blocked
tap can freeze the Mac (`docs/design/macos27.md:54`).

**Evidence.** PLAN:l.261, l.722–729. `docs/design/macos27.md:54`.

**Proposal.** Add to PLAN:l.722–728:

> - The item is `DockObserver`'s latest selection, checked with the §4.1 hit band. There is never an AX call in the
>   tap callback.
> - "A window was created" means the pid's count of on-screen layer-0 windows in `CGWindowListCopyWindowInfo` grew
>   between mouse-up and +100 ms.

### X2-18 · Minor · §4.13 · Safe Mode drops the ISO layout check, so the key above Tab is wrong for ISO keyboards

**Finding.** Safe Mode calls no private symbol "except the symbolic-hotkey pair" (PLAN:l.788). `KBGetLayoutType` and
`LMGetKbdType` then fall back to "The ANSI layout" (PLAN:l.768). The key above Tab has a different code on ISO
keyboards (`PrivateAPIs.swift:61–66`). So the switcher's "key above Tab" shortcut fails in Safe Mode for ISO users.

**Evidence.** PLAN:l.768, l.787–789. `Switcher/PrivateAPIs.swift:61–66`.

**Proposal.** Replace PLAN:l.788: "No private symbol is called except the symbolic-hotkey pair and the read-only layout
pair (`KBGetLayoutType`, `LMGetKbdType`). `IsSecureEventInputEnabled` is public and is always called."

### X2-19 · Minor · §7 M38, §4.10 · M38 can't fail, and it misses the real leak

**Finding.** M38 checks that "private windows never [are] visible" in a screen share (PLAN:l.1142). A private card
never holds a title or a thumbnail (PLAN:l.709–710), so that passes whatever the share does. The real exposure is
different. If S0-24 finds that SCK-based shares see the panel, then thumbnails of *minimized and other-Space* windows
appear in the share. The share would not otherwise show those windows.

**Evidence.** PLAN:l.709–713, l.1012, l.1142, l.1171.

**Proposal.** Replace M38: "Share the screen (QuickTime and a browser meeting). Point at an app with a minimized
window. Record whether its thumbnail appears in the share. If it does, Known limitations and the Thumbnails help say
so in those words."

### X2-20 · Minor · §4.7, §4.9 · The capture scale isn't defined for minimized windows

**Finding.** "The capture scale comes from the screen that holds the window" (PLAN:l.619–620). No screen holds a
minimized window. The private path also scales "to the largest card size × the screen's scale" (PLAN:l.689–690). Today
the code uses `NSScreen.main` (`ThumbnailStore.swift:70`, `:108`).

**Evidence.** PLAN:l.619–620, l.689–690. `Switcher/ThumbnailStore.swift:70`, `:108`.

**Proposal.** Add to PLAN:l.620: "For a window that no screen holds (minimized, or on a Space of a display that's gone),
use the largest `backingScaleFactor` among the current screens."

### X2-21 · Minor · §7 M1, §4.23 · M1 says the switcher's thumbnails are "unchanged", but §4.23 changes them

**Finding.** M1 expects thumbnails "unchanged" with Dock Previews off (PLAN:l.1105). §4.23 adds minimized and
other-Space thumbnails and a 30-minute cache, whatever the Dock setting (PLAN:l.968–970). So M1 can't pass as written.

**Evidence.** PLAN:l.335, l.967–970, l.1105.

**Proposal.** Replace M1: "Switcher with Dock Previews off: ⌥⇥, ⌥\`, search and actions unchanged. Thumbnails as §4.23
describes. Nothing registered beyond today's set (M32)."

### X2-22 · Minor · §4.12 step 2, §5 · The OS gate allows macOS 14 and 26, which S0 never tests

**Finding.** The gate allows majors 14, 15, 26 and 27 (PLAN:l.742). The deployment target is 14 (`Package.swift:57`).
S0 runs on a 27.2 host and a 15 VM only (PLAN:l.982, l.993). Users on 14 and 26 get every private call with no S0
evidence, and verification turns their crash guard off after 20 calls.

**Evidence.** PLAN:l.742, l.982, l.993, l.1005. `Package.swift:57`.

**Proposal.** Either add 14 and 26 legs to S0-4, S0-5 and S0-17, or list 14 and 26 as unverified majors under X2-2's
rule until those legs run. STEP0-NOTES says which.

### X2-23 · Minor · §4.2 swap intent · A dropped swap is never retried, so the panel can show one app while the pointer rests on another

**Finding.** "If the pointer is still heading in after 120 ms, the swap is dropped" (PLAN:l.484). Nothing re-checks
later. Scenario: the pointer heads toward the panel and stops over the neighbouring icon B, inside A's corridor
(PLAN:l.485). The selection stays B, so no new selection change arrives. The panel shows A's windows indefinitely
while the pointer rests on B.

**Evidence.** PLAN:l.482–486.

**Proposal.** Replace "the swap is dropped" with: "the swap waits. It's re-checked on each `pointerMoved`. It runs when
the pointer stops heading in for 120 ms while outside the panel, and it's dropped when the pointer enters the panel."

### X2-24 · Minor · §4.17 · The crash-guard row always says "Thumbnails", whichever symbol stopped

**Finding.** Every symbol has the crash guard, and "both pages show a 'stopped' row" (PLAN:l.757). The only row text is
"Thumbnails of minimized windows stopped after a problem in macOS" (PLAN:l.854–855). A raise or Spaces stop would show
a thumbnails message.

**Evidence.** PLAN:l.757, l.854–855, l.869.

**Proposal.** Replace PLAN:l.854–855: "A crash-guard stop (§4.12): '\(feature) stopped after a problem in macOS. Snaptic
tries again after a macOS update.' [Try Again]. `\(feature)` comes from `WindowFeature`'s display name, for example
'Thumbnails of minimized windows' or 'Raising windows on other Spaces'."
