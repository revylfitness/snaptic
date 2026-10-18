# 0.3 plan review r4: security, privacy, safety

Checked against PLAN r4, review-r3-security, 0.2 §4.10/R5.5/R5.7 and `Sources/`.
Counts: **Critical 0 · High 0 · Medium 1 · Low 6.**

## Round-3 status
- **M1** resolved (N10, §2.5 "Hotkey confirmation", §3.2 hotkey row, HW-19).
- **M2** resolved (§2.3 `AwakeActivityGate` truth table, §2.5 "Who sets the activity flags", lint L16). One carry gap remains (L1 below).
- **M3** partly resolved: the `batteryPresent` latch and the unreadable rule (§2.6) are sound, and keeping the plain assertion is justified by [PA] l.13/94. The "AC but falling" detection doesn't hold between percent steps (M1 below).
- **L1–L4, L6, L7** resolved (§2.3 `HoldBinding` comment, §2.5 `addHold`, §2.10 connection rules and tests, §2.3/§2.14 `sanitized(now:)`, §2.5 Persistence, §3.6, §2.14 `importable` + `removedPaths`).
- **L5** partial (L1 below). **L8** resolved for clicks, with a keyboard residual (L4 below).

## Medium

**M1. `falling` compares the last two readings, so "discharging" on a weak adapter flips off between percent steps (§2.6 `PowerFacts.falling`, `PowerMath`, holding-clear rule; lead-10).**
- PowerMonitor is event-driven (§2.8), and `kIOPSNotifyPowerSource` also fires for time-remaining and adapter updates, so most consecutive readings share a percent.
- On an underpowered USB-C charger at 4%, the 5→4 reading sets `falling` and ends the session.
- The next same-percent notification gives `falling = false`, so `discharging = false`. Then:
  - `allowsBackgroundWork` turns true again, so Drive Alive and activity resume.
  - "on AC and not falling" clears `holding`, so a rule restarts its session.
- At 4→3 everything ends again. The floor flaps once per percent, in the very case lead-10 targets.
- Fix:
  - Make `falling` sticky: the last *distinct* percent change was downward and IOPS hasn't reported `charging` since.
  - Or, preferably as an extra signal, use IOPS `kIOPSCurrentKey < 0` or AppleSmartBattery `InstantAmperage < 0` (signed, no TCC).
  - Clear `holding` only after a rise or `charging == true`, never on a single equal reading.
  - Kit test: 5,4,4,4 on AC stays `discharging` and keeps the hold.

## Low

**L1. `lastEnded` is set only when a *manual* session ends, so chained rules still reset the activity cap (§2.3 truth table: `ended`, `nothingGoverned`; §2.9 "The cap"; r3 L5).**
- In the r3 L5 scenario (adjacent schedule rules, no manual session), `lastEnded` is nil or hours old. The first arbitration with nothing governing therefore clears `activitySince`, and the next rule gets a fresh hour.
- Fix:
  - Emit `governingEnded(now)` from `arbitrate` whenever governing goes active → inactive, for any source.
  - When nothing governs and `lastEnded == nil`, set it to now instead of resetting.
  - Test: rule A ends, rule B starts 1 s later, cap carries.

**L2. The toasts can be clickjacked without TCC (§2.5 Hotkey confirmation, Start Anyway; `ToastPresenter.swift:160–206`).**
- Synthetic clicks and `AXPress` do need Accessibility, and `ToastPanel.canBecomeKey == false` means there is no keyboard path. So the R5.7 residual holds for *injected* input.
- Any app can still order a window above `screenSaver+1` with `ignoresMouseEvents = true` and draw a decoy over the 460×56 toast at its fixed top-centre spot (`acceptsFirstMouse` is true).
- The timing is predictable:
  - The hotkey session is visible in `pmset -g assertions`.
  - HID idle can be read without TCC.
  - The prompt appears at the first interval after 60 s idle.
- Payoff: r3 M1's (±1 pt moves, ≤ 8 h), or Start Anyway below the user floor.
- Fix:
  - Arm a toast's actions 0.5–1 s after it appears.
  - At click time, refuse if `CGWindowListCopyWindowInfo(.optionOnScreenAboveWindow, toastNumber)` shows another process's window intersecting the toast. Bounds and PID need no Screen Recording, and §2.5 already reads them.
  - Bind the toast's lifetime to the session id, so a stale Allow can't land on a later session.

**L3. Lossy lists don't define what happens with duplicate ids (§2.14 `LossyArray`, `AwakePreset`, `AwakeTrigger`, `AwakeHold`, suppressions).**
- A defaults writer can repeat an id. `Dictionary(uniqueKeysWithValues:)` is common in this codebase (`ModuleHost.swift:260`, `PowerController.swift:204`, `LayoutsController.swift:300`). Over a duplicate it traps at launch, which is a crash loop that also takes Displays down (priority 1).
- Fix: every `sanitized()` keeps the first element per id; Kit test per list.
- `StableID.derived` itself is fine:
  - The namespace ‖ 0x00 ‖ name framing is unambiguous.
  - Pre-planting a derived id gains nothing a direct write doesn't, because M1 replaces by id.

**L4. The 1 s focus guard covers clicks but not keystrokes (§2.5 Focus safety, §3.2; r3 L8).**
- Reopen brings Settings forward with no CLI involved. With "Keyboard navigation" on, a Space typed more than 1 s later activates the focused Start button or switch header, which counts as `.uiStart`.
- Fix: start handlers act only when `NSApp.currentEvent` is a mouse-up, or after a real mouse-down in the window since the external open. Otherwise they focus the control without acting.

**L5. Held-connection writes use `sendOnce`, which polls up to 2 s on the shared listener queue and ignores short writes (§2.10 Ping; `ControlServer.swift:316–333`).**
- A short ping interleaves with the next write, so CLIClient may print or misparse it; each stall delays every request.
- Fix: ping and final lines get one non-blocking attempt. EAGAIN or a short write closes the hold. Add a test with a client that never reads.

**L6. The confirmation toast must fail closed against `ToastPresenter` as it stands today (§2.5).**
- `show()` returns `Void`, drops silently when suppressed, always calls `remember` (so the prompt reaches Recent Notices, against §2.5), and has no dismiss callback.
- Fix:
  - `show` reports whether the toast was presented. `confirmAsked` is applied only after it was.
  - Expiry or close calls `confirmDeclined`.
  - `remember` is skipped for confirmation toasts.
  - Kit test: no event path except the Allow handler reaches `.allowed` from `askOnFirstUse`.

## Verified sound (r4 additions)
- **Gate.** Every `allowed` path is a real UI handler or Allow. `ActivityPolicy.nudgeAllowed` requires `.manual` governing, so holds and triggers never nudge. Restore, resume, CLI, `launch` and forged `.menu` snapshots map to `notAllowed`. Nothing is Codable, and L16 restricts who can assign.
- **Toasts.** Only real input or an Accessibility-holding process (which could move the pointer itself) can click Allow; the panel is never key.
- **Holds:**
  - The pool is bounded (8 held, separate from the 4 request slots), so holds can't starve the CLI.
  - Holds are capped at 24 h and never extended.
  - ProcessWatch is armed before verifying, with start time and uid checked.
  - EOF is authoritative and `SO_NOSIGPIPE` is already set.
  - A forged snapshot `--pid` hold works with the CLI off but grants nothing beyond `caffeinate`.
- **Battery.** The `batteryPresent` latch closes the desktop path. Unreadable → no background work.
- **Static control tables** and `--selftest-controls` (token-gated, in-memory) have no security surface.

**Verdict: Ready with fixes**
