# 0.5 plan review r3: Adversarial (failure modes, races, private APIs, privacy)

Reviewer: adversarial subagent, round 3 (final). Plan: `docs/design/0.5/PLAN.md` (r3, 2,023 lines). Grounding: the
Snaptic tree at `7dd972c` on `feature/v050-dock-previews` (Switcher, Core, SnapticKit), `docs/design/macos27.md`,
`docs/design/0.4/PLAN.md` for precedent, `Package.swift`, and `review-r2-adversarial.md` so this round doesn't repeat
it. This Mac runs macOS 27.2.

This round only read files. Nothing was launched, quit, signalled, tapped or captured, and no program was compiled or
run. No defaults were written. No DockDoor or AltTab source was read.

The owner decisions Q1–Q7 stand. No finding reopens them. X3-1 changes which symbols the OS gate covers and keeps the
gate itself, so Q6 is untouched.

Citations: `PLAN:l.N` is a line of the r3 plan. `path:line` is a line of the tree, relative to `Sources/Snaptic/`
unless the path starts with `Sources/SnapticKit/`, `docs/` or `Package.swift`.

Severity counts: **1 Blocker, 5 Majors, 6 Minors.**

## Were r2's Blockers closed?

- **X2-1 (normal answers poison symbols): mostly closed.** Step 5 now splits results into "no answer" and
  "impossible". Answers that an app controls never count, and a poisoned symbol is probed again after 10 minutes
  (PLAN:l.967–976). Four normal answers can still poison a symbol or fail its probe (X3-6):
  - an unknown keyboard layout;
  - a full-size Retina capture, if "requested pixels" means the card;
  - a probe that gets no answer;
  - and one rule (`IsSymbolicHotKeyEnabled`) can't be checked against the prototype.
- **X2-2 (secure input on an unverified macOS): closed for secure input.** `IsSecureEventInputEnabled` is exempt from
  the gate. An unknown answer keeps macOS's ⌘⇥ (PLAN:l.943–944, l.1010). But the gate's other half causes two new
  problems (X3-1):
  - it turns off the switcher's raise and its ⌘⇥ takeover on macOS 14 and 26;
  - it blocks the give-back on 28+.
- **D2-1 (privacy store migration): closed.** The plan:
  - keeps the store in 0.4's keys;
  - adds `[switcher, "privateBundleIDs"]` to `unionPaths`;
  - adds `protectPrivateWindows` to `safetyPaths`;
  - keeps both fields in `AppSettings.reset()`, while Reset All calls `resetPrivacy()` (PLAN:l.291, l.530–532,
    l.878–883).

  This matches the tree:
  - the import goes through `KitBackup.merge` (`Core/Backup.swift:135–138`, `Sources/SnapticKit/KitBackup.swift:100–102`,
    `:202–214`);
  - the switcher's settings are the shared `AppSettings` (`Core/ModuleHost.swift:40`);
  - Reset All calls `switcherSettings.reset()` (`Core/ModuleHost.swift:739`), which today is `config = Config()`
    (`Switcher/Settings.swift:380`). So `reset()` has to change, and the plan says it does.

  Nothing is left open.

## Facts this review relies on

- **0.4 calls every writer on every supported major.** The raise trio and the hotkey setter are looked up with
  `dlsym` and called with no OS check (`Switcher/PrivateAPIs.swift:101–129`, `:132–134`). The deployment target is
  macOS 14 (`Package.swift:57`).
- **macOS 14 made activation cooperative.** From 14 on, `activate` can be declined when the calling app isn't active.
  That's why the plan pairs the fallback raise with `yieldActivation` and tests it in S0-27 (PLAN:l.1006, l.1403).
  - S0 runs on 27.2 and 15.
  - Legs on 14 and 26 are optional, and S0-27 isn't among them (PLAN:l.1428–1431).
- **`apply` writes the saved ⌘⇥ list on every call, whatever the shortcuts are.**
  - It drops any id that reads as off and isn't in this run's set (`Switcher/PrivateAPIs.swift:173`).
  - It writes the union, then writes `wanted` (`:176–177`, `:188`).
  - `applySystemHotkeys` calls it at every start and every trust change. That includes the default ⌥⇥ and ⌥\`
    shortcuts (`Switcher/WindowSwitcherModule.swift:216–219`, `Switcher/Settings.swift:262–265`).
- **The switcher's tap calls the layout pair on every key-down system-wide.**
  - `matchingShortcut` tests each shortcut in turn, and the default ⌥\` shortcut reaches `KeyCode.matches`
    (`Switcher/SwitcherController.swift:111–114`).
  - `KeyCode.matches` calls `isISOKeyboard` (`Switcher/Settings.swift:35–38`), which calls the layout pair.
  - This runs in `handle`, on the main run loop (`Switcher/SwitcherController.swift:68–75`, `Switcher/HotkeyTap.swift:73`).
- **`IsSymbolicHotKeyEnabled` returns `Bool`** in the tree's prototype (`Switcher/PrivateAPIs.swift:36`).
- **`CGSHWCaptureWindowList` takes a window list and options, not a size.** The private path scales down after the
  capture (PLAN:l.852–853). S0-4 records the size and scale it returns (PLAN:l.1380).
- **The switcher acquires its lease in `start()`** (PLAN:l.285–286). The probe runs at the first acquire
  (PLAN:l.946).

---

## Blockers

### X3-1 · Blocker · §4.12 step 2, H6, §4.23 · The OS gate turns off the switcher's raise and ⌘⇥ on macOS 14 and 26, and blocks the give-back

**Finding.** Step 2 makes every symbol that writes or captures `unavailable` on an unverified major. In 0.5.0 that
means 14, 26 and 28+, because the 14 and 26 legs are optional (PLAN:l.1428–1431). The writers are the raise trio and
the hotkey setter, and 0.4 calls both on every major today. So on 14 and 26, upgrading to 0.5 does this:

- **Raise.** Every switcher raise uses `kAXRaiseAction` plus activate. Cooperative activation can decline that, and
  S0-27 doesn't run on 14 or 26.
  - Scenario: on macOS 26 the user presses ⌥⇥ and picks a Safari window. The window may come forward without Safari
    becoming active, so the keys still go to the old app.
  - Other-Space windows only activate the app.
- **⌘⇥ takeover.** The setter is unavailable, so "macOS keeps ⌘⇥". If the user's switcher shortcut is ⌘⇥, they get
  macOS's own switcher instead. No row says why.
- **Give-back.** H6 says giving ⌘⇥ back "always runs", except under its own crash guard (PLAN:l.457–460). The gate
  says the setter is unavailable. Both can't hold. If the gate wins, ⌘⇥ stays off in two cases:
  - 0.4 crashed while holding ⌘⇥ on 14 or 26, and the user then installed 0.5;
  - 0.5 took ⌘⇥ on 27, the user updated to 28, and S0-5 finds that a turned-off hotkey survives logout.

§4.23 says its list is the switcher's only visible changes, and none of these is on it (PLAN:l.1347–1353). R2's
dispositions rejected P2-16 because "it drops the switcher's read-only lookups on two supported releases"
(PLAN:l.1904). r3 drops the switcher's writers on the same two releases. M4 and M16 run only on 27 and 15.

**Evidence.** PLAN:l.938–944, l.457–460, l.1006, l.1008, l.1347–1353, l.1403, l.1428–1431, l.1641, l.1653, l.1904.
`Switcher/PrivateAPIs.swift:101–129`, `:132–134`, `:153–161`; `Switcher/WindowManager.swift:501`, `:531`;
`Package.swift:57`.

**Proposal.** Replace PLAN:l.938–944:

> 2. **OS gate (X2-2, X2-22, P2-16, X3-1).** A major is **verified** when S0 has run on it: 15 and 27 in 0.5.0.
>    - **Symbols 0.4 already calls** run on every major from 14 to the newest verified one, under the full contract:
>      the raise trio, the hotkey pair, Spaces, the AX window id and the layout pair. On a major that isn't verified
>      they're never marked verified, so their crash marker stays on for every call.
>    - **`CGSHWCaptureWindowList`**, new in 0.5, runs only on a verified major. Elsewhere it's `unavailable`, and its
>      fallback runs.
>    - **On a major newer than the newest verified one** (28+ in 0.5.0), the read-only symbols run their probes. The
>      writers and the capture stay `unavailable`.
>    - **The give-back is exempt from the gate and the image check.** It only turns on ids from Snaptic's saved list,
>      under its own crash guard (step 6). H6 holds on every major.
>    - `IsSecureEventInputEnabled` is exempt from the gate and the image check. It's public API, and it's called in
>      Safe Mode too.

Add to PLAN:l.1431: "M4 and M16 each get one owner leg on macOS 14 or 26 before R." If the owner would rather keep
the writers gated, the S0-4, S0-5, S0-17 and S0-27 legs on 14 and 26 become required (a VM), and §4.23 and the
release notes list what changes on those releases.

---

## Majors

### X3-2 · Major · §4.12 step 6, H3 · The kept ⌘⇥ list is overwritten at the next start

**Finding.** When the give-back is disabled on this build, step 4 skips it and "keeps the saved list". Then "a later
OS build or Try Again gives ⌘⇥ back" (PLAN:l.435–436, l.988–991). The list doesn't survive that same launch:

1. Run 1 takes ⌘⇥. Giving it back at quit crashes. The give-back marker and the saved list `[1, 2]` stay.
2. In run 2, step 3b disables the give-back on this build, and step 4 keeps the list.
3. The switcher starts and calls `apply` (`Switcher/WindowSwitcherModule.swift:219`).
   - In a new process, `disabledBySnaptic` is empty. ⌘⇥ reads as off, so `apply` decides the user switched it off
     and drops it (`Switcher/PrivateAPIs.swift:173`).
   - It then writes `[]` over the list (`:177`, `:188`). This happens with the default ⌥⇥ shortcuts too.
4. The list is gone, so neither Try Again nor the next OS build has anything to give back. If S0-5 finds that a
   turned-off hotkey survives logout, ⌘⇥ stays off for good. System Settings has no switch for it.

The take also isn't blocked. If ⌘⇥ comes back on after a logout and the user's shortcut is ⌘⇥, `apply` takes it
again, even though giving it back is disabled on this build. At quit the give-back guard skips `restore()`, and ⌘⇥ is
off again.

This becomes a Blocker if S0-5 finds that the off state survives logout.

**Evidence.** PLAN:l.419, l.426, l.435–436, l.988–993. `Switcher/PrivateAPIs.swift:153–161`, `:163–191`, `:202–209`,
`:212–221`; `Switcher/WindowSwitcherModule.swift:216–219`; `Switcher/Settings.swift:262–265`.

**Proposal.** Add after PLAN:l.993:

> - **The kept list (X3-2).** When the give-back is disabled, step 4 moves the saved list to
>   `Windows.pendingGiveBack` and removes `SnapticDisabledSystemHotkeys`. `apply`, `restore()` and
>   `recoverFromPreviousRun()` never write `Windows.pendingGiveBack`. `apply` treats its ids as Snaptic's own, so it
>   never reads them as switched off by the user.
> - **No take without a give-back.** While the give-back is disabled on this build, the take is blocked too. The
>   switcher leaves ⌘⇥ with macOS, as the kill switch does, and the Switcher page shows the give-back row.
> - **Try Again** on that row, or the first launch on a new OS build, runs the give-back for `Windows.pendingGiveBack`
>   at once, under its marker. The key is removed only after the give-back returns.

Add a B1b test: with the give-back disabled and a kept list, `apply` with the default shortcuts and with ⌘⇥ leaves
`Windows.pendingGiveBack` intact and calls no setter.

### X3-3 · Major · §4.12 step 4, §4.13, §4.9 · The launch probe makes a private capture at almost every launch, even in Safe Mode or with thumbnails off

**Finding.** The probe runs once per process, "at the first `WindowServices.acquire`" (PLAN:l.946). The switcher
acquires in `start()` (PLAN:l.285), so on 15 and 27 the probe runs at almost every launch. Its capture step calls
`CGSHWCaptureWindowList` on the probe window (PLAN:l.957–959). None of §4.9's gates apply to it: Screen Recording, a
`.thumbnails` lease, Safe Mode and the kill switch are all skipped.

- **Safe Mode.** §4.13 says the capture "isn't called", and that diagnostics show "0 private captures"
  (PLAN:l.1063, l.1067). A2b and M33 check that (PLAN:l.1476, l.1670). The probe calls the capture anyway.
- **The indicator.** The plan's own research says this path still shows the screen-recording indicator
  (PLAN:l.129). Take a user with Dock Previews off and the switcher's thumbnails off: they see the indicator at every
  login. "With Dock Previews off it registers exactly what it does today" no longer holds (PLAN:l.286, l.1347).
- **Permission.** Nobody knows whether the call prompts, or logs a TCC denial, when Screen Recording isn't granted.
  S0-4 doesn't record it.

**Evidence.** PLAN:l.129, l.285–286, l.823–828, l.946, l.957–959, l.1063, l.1067, l.1347, l.1476, l.1670.

**Proposal.** Replace the first line of PLAN:l.957 with:

> - `CGSHWCaptureWindowList` is probed **lazily**, just before the first private-path capture that passes every §4.9
>   gate: Screen Recording granted, a `.thumbnails` lease, not Safe Mode, no kill switch, and a verified major. That
>   capture waits for the probe. Until then, diagnostics show `hwCapture: notProbed`. On the probe window: if S0-4
>   records …

Add to M1 and M33: "A launch with thumbnails off, and a launch in Safe Mode, make no private capture, the probe
included. Diagnostics show `hwCapture: notProbed` or `safeMode`."

### X3-4 · Major · §4.5 · A held ⌘Q, ⌘H or ⌘W reaches the next app once the panel hides

**Finding.** The tap swallows autorepeats and the key-up only while it's enabled, and it's enabled only while the
panel is engaged (PLAN:l.692–697, l.709). Several handled keys end the engagement while the key is still down:

- ⌘Q and ⌘H hide the panel (`quitApp`, `hidApp`; PLAN:l.678). Esc hides it too.
- ⌘W on the last card hides the panel when the small-card switch is off (PLAN:l.679–680).
- 1.5 s without movement disengages it (PLAN:l.689), and holding a key with the pointer still does exactly that.

From then on the tap is disabled, so the rest of the autorepeats and the key-up go to the frontmost app.

- **Scenario.** A Chrome user is used to holding ⌘Q, because of Chrome's "Warn before quitting". Over a TextEdit
  card they hold ⌘Q. TextEdit quits and the panel hides. The repeats then reach Chrome, which quits too.
- **⌘H.** Holding it hides one app after another.
- **⌘W.** Holding it on a one-window app's card closes the frontmost app's tabs at the repeat rate.

This breaks "No handled key ever reaches the frontmost app" (PLAN:l.705). K3's own case, "a held ⌘W (autorepeat for
1 s) closes one window", fails on a one-window app (PLAN:l.1572). It's the orphan key-up and autorepeat pattern that
`docs/design/macos27.md` §2 warns about.

**Evidence.** PLAN:l.69–70, l.678–680, l.689–697, l.705, l.709, l.1572, l.1660. `docs/design/macos27.md:53`.

**Proposal.** Replace PLAN:l.696–697:

> - **Key-up and repeats (X3-4).** Once the tap swallows a table key-down, it stays enabled until that key's key-up,
>   even if the panel hides or disengages in the meantime. Until then it swallows only that key code's autorepeats
>   and its key-up, and every other event passes.
>   - The 1 s cap restarts at each autorepeat, so a long hold stays swallowed. A lost key-up still frees the tap 1 s
>     after the last repeat.
>   - Then the tap is disabled again, unless the panel is engaged.

In PLAN:l.69–70, change "it stays disabled except while a panel is engaged" to "it stays disabled except while a
panel is engaged or a key it swallowed is still down".

- Add to K3: "Hold ⌘Q over the last card: one quit. No repeat and no key-up passes after the panel hides. Hold ⌘W
  with the pointer still for 3 s: one close."
- Add to M23: "Hold ⌘Q over a card for 2 s: only the previewed app quits."

### X3-5 · Major · §4.5 · Engagement needs the ring, and the ring needs engagement

**Finding.** Engagement needs "a card's selection ring has been visible for at least 250 ms" (PLAN:l.686–687, l.326).
But the ring is drawn only "while engaged" (PLAN:l.719–720). Read literally, hovering never engages the panel, and
only a click does.

- So ⌘W after moving onto a card passes through to the frontmost app.
- K3's setup "moved with the ring up for 250 ms, then ⌘Q, quits the previewed app" can't happen (PLAN:l.1573–1574).
- An implementer who breaks the loop by showing the ring before engagement invents a ring state the plan doesn't
  describe.

Separately, "It engages again when the pointer moves" (PLAN:l.690) doesn't repeat the 4 pt rule. After the panel
disengages from 1.5 s without movement, a 1 px drift (a bumped desk) would engage it again at once. That reopens X2-5
for M40's second case (PLAN:l.1677).

**Evidence.** PLAN:l.326, l.686–690, l.719–720, l.1571, l.1573–1574, l.1677.

**Proposal.** Replace PLAN:l.686–688:

> - **Engaged (D2-3, X2-5, X3-5).** The pointer has moved at least 4 pt in total inside the panel within the last
>   1.5 s, and it has been inside the panel for at least 250 ms since it entered (`panelEntered`). A click in the
>   panel also engages it.

- In PLAN:l.690, change "It engages again when the pointer moves." to "It engages again only by the same rule."
- Replace PLAN:l.719–720 with: "**Selection ring.** The card under the pointer shows a 2 pt accent ring exactly
  while the panel is engaged. It tells the user which card ⌘W and ⌘M act on. Otherwise no card shows a ring."
- Remove "engagement needs it up for 250 ms" from the `selectionRingShown` row at PLAN:l.326.
- In K3, change PLAN:l.1571 to "drift under 4 pt passes ⌘W through".
- Change PLAN:l.1573–1574 to "moved 4 pt within 250 ms in the panel, then ⌘Q, quits the previewed app; after 1.5 s
  still, a 1 pt drift, then ⌘Q, passes through".

### X3-6 · Major · §4.12 steps 4–5, §4.9 · Four normal answers still poison a symbol

**Finding.**

- **(a) An unknown layout.** For a keyboard type it doesn't know, `KBGetLayoutType` returns `kKeyboardUnknown`
  (`'????'`), a value listed in HIToolbox's `Keyboards.h`. The probe needs "one of the three known layouts", and the
  table counts "a layout outside the three known ones" as impossible (PLAN:l.960, l.1024).
  - Scenario: the last keyboard used was a virtual HID keyboard (Karabiner, a KVM, Screen Sharing). The probe fails
    and poisons the layout pair.
  - Ten minutes later the re-probe fails too. The pair then shows the "stopped because macOS answered in a way
    Snaptic didn't expect" row until quit (PLAN:l.1179–1180).
  - 0.4 reads the same answer as ANSI (`Switcher/PrivateAPIs.swift:63–66`).
- **(b) "Requested pixels" isn't defined.** A capture is impossible when it has "more than 4× the requested pixels"
  (PLAN:l.843–844, l.1016). But the call takes no size, and the only size the plan names is the card's, after
  scaling (PLAN:l.852–853).
  - If "requested" means the card, consider a 1,440 × 900 pt window on a Retina display. Its full capture is
    2,880 × 1,800 px, about 26× a Medium card's 560 × 350 px. So every capture counts as impossible.
  - Two captures poison the path, and the second poisoning removes thumbnails for the session.
- **(c) A probe with no answer.** Step 5 says no answer "never counts" (PLAN:l.968). Step 4 says "A failed probe
  makes that symbol `poisoned`" (PLAN:l.965).
  - The AX probe asks our own process, from the probe queue, for the probe window's id (PLAN:l.955–956). Our main
    thread answers it.
  - At the first acquire, main is still starting modules, so the call can time out with `cannotComplete`.
  - If that counts as a failed probe, every slow launch poisons `axWindowID` for 10 minutes.
  - The Spaces probe can return an empty array the same way, for a window ordered in during a Space switch or at the
    lock screen.
- **(d) A rule that can't be checked.** The table's impossible result for `IsSymbolicHotKeyEnabled` is "a nonzero
  `CGError`" (PLAN:l.1022). The pinned prototype returns `Bool` (`Switcher/PrivateAPIs.swift:36`), so there's no error
  to check.

**Evidence.** PLAN:l.843–844, l.852–853, l.955–956, l.960, l.965, l.968, l.1016, l.1022, l.1024, l.1179–1180.
`Switcher/PrivateAPIs.swift:36`, `:63–66`.

**Proposal.**

- Replace PLAN:l.960:

  > - `KBGetLayoutType` returns a `UInt32`. `kKeyboardUnknown` (`'????'`) is **no answer**, and that call reads as
  >   ANSI, as in 0.4. Any other value outside `ANSI`, `ISO ` and `JIS ` fails.

  In PLAN:l.1024, the last cell becomes "a value other than `ANSI`, `ISO `, `JIS ` or `'????'`".
- Add after PLAN:l.965:

  > A probe that gets **no answer** (step 5's first class: a timeout, `cannotComplete`, an empty Spaces array) hasn't
  > failed. The symbol stays on its fallback, and the probe runs again at the next acquire, at most once a minute.
  > Only an impossible result fails a probe.

- In PLAN:l.843–844 and l.1016, replace "more than 4× the requested pixels" with "more than 4× the pixels of the
  window's `CGWindowList` bounds × the largest `backingScaleFactor` of any screen".
- In PLAN:l.1022, the last cell becomes "none: it returns a `Bool`".

---

## Minors

### X3-7 · Minor · H3, §4.12 · The layout pair runs on every key-down in the switcher's tap

**Finding.**
- **The cost.** The default ⌥\` shortcut makes `KeyCode.matches` call `isISOKeyboard`. That happens for every
  key-down system-wide, on the main run loop, inside the switcher's tap (`Switcher/Settings.swift:35–38`,
  `Switcher/SwitcherController.swift:111–114`).
- **Why it does I/O.** H3 puts that call under the full contract (PLAN:l.428). On a major that isn't verified, the
  read-only markers never stop (PLAN:l.940–941). So on 14 and 26, every keystroke does an `open`, a `write(2)` and an
  `unlink` inside a tap callback.
- **What the plan says.** It forbids I/O in the Dock tap (PLAN:l.713–714), and `docs/design/macos27.md` says never to
  block in a tap.
- **The result.** On a slow or full disk, typing lags and the tap can time out.

**Evidence.** PLAN:l.428, l.713–714, l.940–941. `Switcher/Settings.swift:35–38`, `:262–265`;
`Switcher/SwitcherController.swift:68–75`, `:111–114`; `docs/design/macos27.md:54`.

**Proposal.** The last cell of PLAN:l.428 becomes:

> full contract, once per keyboard type: `WindowServices.layout(for:)` caches `KBGetLayoutType` by keyboard type for
> the process. The tap reads the type from the event's public `keyboardEventKeyboardType` field and reads a cached
> `Bool`, so it does no I/O. For a type it hasn't seen, the lookup runs off main, and that key-down uses the last
> cached answer. Fallback ANSI.

### X3-8 · Minor · §4.12 step 6 · Marker races, and stale markers after a clean quit

**Finding.**

- **Unlink race.**
  1. Thread A takes the counter from 1 to 0 and is about to unlink.
  2. Thread B takes it from 0 to 1 and writes the file.
  3. A's unlink removes B's marker, so a crash in B's call leaves no marker.

  The AX id runs inside `concurrentPerform`, so it's the most exposed symbol (`Switcher/WindowManager.swift:354`,
  `:379`).
- **Write race.** B takes the counter from 1 to 2 and calls straight away, before A's `write(2)` has finished. A
  crash in B's call before the file exists leaves no marker.
- **Clean quit.** A quit can end the process while another thread has a call in flight, such as an AX read held up by
  a busy app. So can the signal handler's `exit(0)` after 3 s (`Core/AppDelegate.swift:224`). The marker stays, and
  step 3b counts it as a crash.
  - Quitting from Snaptic's own menu moves focus, so FocusTracker's AX callback reads a window id at that very moment
    (`Switcher/WindowManager.swift:589`).
- **Failures.** The plan doesn't say what happens when the directory can't be created or a write fails.

**Evidence.** PLAN:l.979–984. `Switcher/WindowManager.swift:354`, `:379`, `:589`; `Core/AppDelegate.swift:134`,
`:224`.

**Proposal.** Add after PLAN:l.982:

> The counter and the file operation share one lock per symbol, held from the transition through the `open` and
> `write(2)`, or the `unlink`. So the file exists before any caller's call, and only the last caller out removes it.
> The directory is created with mode 0700. Markers are opened with `O_WRONLY|O_CREAT|O_TRUNC|O_NOFOLLOW|O_CLOEXEC`. If
> a marker can't be written, that call takes the fallback (fail closed), and diagnostics count it.

Add to PLAN:l.983–984: "A marker counts only when the previous run didn't reach the clean-quit mark
(`AppDelegate.swift:134`). After a clean quit, markers are removed and have no effect."

### X3-9 · Minor · §4.9 content check · A shape-only probe accepts blank captures for good

**Finding.** If S0-4 finds that our off-screen window doesn't capture, the probe checks the result's shape only
(PLAN:l.958–959). After three suspect captures, the content check runs that probe again. A pass means "those windows
are plain", and from then on their suspect captures are accepted (PLAN:l.835–839).

A shape-only probe also passes when the path returns blank images. So if a macOS change blanks every private capture,
the blanks are accepted for good, and cards show grey rectangles instead of the last-seen thumbnail or the icon.

**Evidence.** PLAN:l.835–842, l.957–959.

**Proposal.** Add to PLAN:l.838–839: "Only a probe that checked the pattern can accept suspects. When the probe checks
shape only, suspects stay suspect: the card keeps the last-seen thumbnail or the icon, and the counter resets."

### X3-10 · Minor · §2.3, §4.9, §8, ground rule 1 · `ThumbnailIndex`'s cap and timer disagree across sections

**Finding.**
- **The per-entry cap.** §2.3 says "one image over 96 MB is skipped". §4.9 says "An entry over 16 MB is skipped", and
  §8 says "16 MB cap per entry" (PLAN:l.310, l.858, l.1701).
- **The retention timer.** It runs while the module is on and idle, as long as the store isn't empty
  (PLAN:l.365–367). Ground rule 1 lists only the Dock observer and the health check (PLAN:l.67).
- **The same timer with Dock Previews off.** The switcher's 30-minute cache from A2a runs the timer too, and 0.4
  doesn't have it (PLAN:l.286, l.1351).

**Evidence.** PLAN:l.67, l.286, l.310, l.365–367, l.858, l.1351, l.1701.

**Proposal.**
- In PLAN:l.310, change "one image over 96 MB is skipped" to "one entry over 16 MB is skipped".
- Replace PLAN:l.67 with: "**While on and idle**, it runs only the Dock observer (on its own thread), its 30 s health
  check, and, while the thumbnail store holds entries, one one-shot retention timer (§2.3)."
- Add "It has 60 s leeway." to PLAN:l.367.

### X3-11 · Minor · §6.1 K3 vs §4.2 · K3 says the Dock menu pauses the timers, but §4.2 says it hides the panel

**Finding.** §4.2 says the Dock's own menu sets the dismiss latch and hides the panel (`dockMenu`). Only our own
menus pause the timers (PLAN:l.602–608). K3 tests "Own menu and Dock menu pause the timers, and closing restarts
them" (PLAN:l.1554).

**Evidence.** PLAN:l.602–608, l.1554.

**Proposal.** Replace PLAN:l.1554: "Our own menus pause the timers, and closing restarts them. The Dock's menu hides
the panel with `dockMenu` and sets the latch."

### X3-12 · Minor · §4.8, §4.3 · "More windows…" has an unclear trigger and loses loaded rows

**Finding.**
- **Two outcomes overlap.** §4.8 has two outcomes for a slow app (PLAN:l.805–808):
  - the budget runs out: a partial list plus "More windows…";
  - the read times out: the app is skipped for 30 s and shown with titles only.

  It doesn't say which one applies when an AX call times out after some windows have been read. M19's 100-window
  app can end up in either.
- **Loaded rows disappear.** The read is cached for 2 s and marked dirty by the freshness lease (PLAN:l.803–804). The
  next read stops at the budget again, so the rows the user loaded with "More windows…" disappear on refresh.
- **No layout test.** K2 covers the grid and scrolling but not this row (PLAN:l.1527–1545).

**Evidence.** PLAN:l.626–627, l.803–808, l.1527–1545, l.1656.

**Proposal.**
- Add to PLAN:l.808: "A read **times out** only when its first window can't be read in time. Once any window has been
  read, running out of time is the budget case. A refresh of the same app keeps the windows loaded on demand until
  they close. The row stays only while some windows are still unread."
- Add to K2: "The “More windows…” row is the last cell, inside the scroll range, and VoiceOver reaches it."
