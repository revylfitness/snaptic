# PLAN 0.3 r2: adversarial review round 2 (code, architecture, buildability)

Checked against `feature/displays` @ 871c10b. Counts: **0 Blocker, 11 Major, 13 Minor**.

## 1. Round-1 findings

| r1 | Status |
|---|---|
| B1 ratchet | Resolved (§6.3). Its mechanics conflict with file ownership: **R2-M1** |
| B2 sleepPrevention | Resolved (§2.13, §6.4) |
| B3 status item owner | Partly resolved (§2.11, §5.2). The contract lacks the plan row: **R2-M6** |
| M1 relative timeout | Resolved (§2.4). Clamp and backstop hole: **R2-M4** |
| M2 hysteresis | Resolved (§2.7). Persisted continuous values ignore reboots: **R2-M3** |
| M3 migrations | Resolved (§4.6). Round-trip residue: m9 |
| M4 upgraders | Resolved for 0.2 (§2.13). The 0.1 path is open: m8 |
| M5 protected while quit | Structurally resolved (§2.14, §3.2). The Keychain premise is weak: **R2-M5** |
| M6 queues | Resolved for block observers (L10). Selector and Combine observers are uncovered: m4 |
| M7–M11 | Resolved (§2.8, §2.9, §2.5, §6.3, N12) |
| M12 live updates | Design resolved (§4.5). Staging and dispatch are wrong: **R2-M2**, **R2-M7**, and see §2 below |
| M13 signatures | Mostly resolved. Residue in §2 below |
| M14 step-0 scope | Resolved for Awake (§6.4). Shell protocol staging is missing: **R2-M2** |
| Minors | Resolved, except m11: `ActivityDecision.none` remains (§2.9) |

## 2. Signatures: won't compile, or compile and misbehave

| § | Problem | Fix |
|---|---|---|
| §2.3 `AwakeSession.overrideGuards` | Left out of `CodingKeys` with no initial value, so synthesized `Decodable` fails | `package var overrideGuards: Bool = false`, plus explicit `CodingKeys` |
| §2.7 `DisplayFact`, `USBFact`, `NetworkFacts`, `BluetoothFact` | No `package init`: the memberwise init is internal, so J's app sources can't build facts | Add an explicit `package init` to each |
| §2.14 `AwakeConsent.empty`; §2.2 `specs`, `activationOrder` | `static let` without an initializer | `= AwakeConsent()`, or a computed `static var` |
| §2.9 `ActivitySimulator.recentNudges`, `DriveAliveService.volumes` | No default and no `init` | `= []` plus `init()` |
| §4.5 `extension DisplayFeatureController { static var observedSections }` | Extension member only, so `type(of: c).observedSections` always returns `allCases` and narrowing is silently ignored | Declare the requirement in the protocol body; keep the extension default |
| §2.9 `ActivityDecision.none` | "Assuming Optional.none" warnings | `.skip` |
| `GuardMemory`, `AwakeBehavior`, `TriggerSuppression`, `DriveAliveVolume` | Synthesized `Decodable` isn't lossy (rule 9) | Hand-written `c.lossy` decoders |
| §2.7 `AwakeCriterionEntry` | Flattened `"kind"` collides with the nested enums' `"type"` (`network(NetworkCondition)`); the payload key is unspecified | Nest payloads under `"condition"`. The entry decodes `AwakeCriterion(from: decoder)` and never asks the encoder for a second keyed container |
| §5.2 `StatusItemPlan` | Already declared with an explicit init in `ConfigModules.swift`; §6.2 moves it to M's `MenuLayout.swift`, and new fields break 7 call sites | One declaration (lead); new init parameters get defaults |
| §5.2 `ModulePreferences.init(…presence:)` | Replaces the `placement:` label | Keep both inits until step 3 |
| §2.14 `AwakeConsentStore.record` | Returns `Void`, so "UI-fail" can't be detected | Return `Bool` or `throws` |
| §2.4 "1,000 inputs → one plan" | `deadline: Double` differs by microseconds for until-sessions | Assert `needsSwap == false`, not `==` |

## 3. Major

**R2-M1. Teams can't keep the ratchet green (§6.3 vs TEAMS.md).**
- A row whose count dropped fails lint, but `scripts/**` is lead-owned. Every team that cleans a file goes red, and parallel row edits conflict.
- Fix:
  - Add a TEAMS.md exception like the one for `stubs.tsv`: a team may lower or delete rows for paths it owns.
  - Stale rows only warn in steps 1–3; `--strict` at the step-3 exit.
  - Count occurrences, not lines.
  - L5 regex `(?<![A-Za-z])Slider\(`. Today `ScrollSlider(` matches, so M's new MenuSliderRow would fail.

**R2-M2. The step-0 table misses three ripples (§6.4).**
- **(a)** The new `SnapticModule` requirements (`tint`, `highlights`, `settingsRoot`, `settingsDestination`, `settingsIndex`) and the removal of `settingsPages()` break A's `WindowSwitcherModule` and H's `SettingsWindowHost.swift:96` at step 0. Fix: extension defaults, and keep `settingsPages()` until the step-3 exit.
- **(b)** `DisplaysPageEnvironment` ending config forwarding (§4.5, lead, step 0) leaves 23 legacy page files unable to re-render on config writes, so toggles look stuck until steps 2–3. Fix: remove the forwarding at the step-3 exit.
- **(c)** M2 is "yes" in step 0, so `MenuPresence` (with a real `legacyPlacement`) must exist in step 0, yet §6.2 gives it to M. Fix: the lead declares `MenuPresence` and `StatusItemPlan`; M owns only `statusItemPlan(...)`.
- Also: `case .awake` in `ModuleHost.module(_:)` and a full stub `AwakeModule`.

**R2-M3. Persisted continuous instants survive a reboot (§2.14).**
- `TriggerSuppression.until`, `GuardMemory.heldSince` and `assertionHoldUntil` are continuous instants, and the snapshot has no `bootSession`.
- After a reboot, a suppression saved at 11 days of uptime blocks its trigger for about 11 days. `time − heldSince` goes negative, so holds never clear.
- Fix: a snapshot-level `bootSession`. On mismatch, drop `until` suppressions (keep `untilFalse`), reset `GuardMemory` except `warnedSerious`, and test it.

**R2-M4. The backstop can become unbounded or self-defeating (§2.4).**
- `TimeoutSeconds = deadline − now` with `deadline ≤ now` gives 0 or a negative value, and IOKit treats 0 as no timeout.
- `verify()` re-creates a "vanished" assertion even after `…assertions.timeout`, which resurrects an expired session.
- Fix:
  - Never create when `continuousEnd ≤ now`; end the session `.timeUp` instead.
  - Clamp `max(1, ceil(deadline − now))`.
  - `verify` runs the expiry check and `arbitrate()` first, and re-creates only an active plan with a future deadline.

**R2-M5. Keychain consent stops neither a same-user writer nor the loss on every update (§2.14, §3.2, HW-22).**
- Releases are ad-hoc signed (`build-app.sh` `SIGN_IDENTITY` defaults to `-`), so the account is a new cdhash each update. Each update reverts nudge, Drive Alive and floors with the wrong "changed outside Snaptic" toast, and leaves an orphan item behind.
- A same-user process can pre-create the file-keychain item under the computable account with a `SecAccess` that trusts Snaptic, and Snaptic then reads forged consent without a prompt. So "can write defaults but not this item" is false.
- `kSecAttrAccessible…ThisDeviceOnly` applies only to the data-protection keychain, which needs an entitlement and provisioning profile that ad-hoc builds can't have. `kSecUseAuthenticationUI` is deprecated (macOS 11) and may not suppress legacy ACL dialogs.
- Fix:
  - Soften §3.2/§6.5 and state the residual risk.
  - Use the data-protection keychain (`kSecUseDataProtectionKeychain` with a Team-prefixed access group) when entitled.
  - Add a distinct toast for "consent unreadable".
  - Use `SecItemUpdate`, falling back to add.
  - Note that a SecurityAgent prompt would block `ModuleHost.init`.

**R2-M6. `StatusItemProvider` lacks the plan row (§2.11, §5.2, §5.3).**
- IndicatorController decides item creation itself ("created when a session starts"), while `presenceDidChange(MenuPresence)` carries neither "exists", `sharedFooterInOwnMenus` nor Recent Notices.
- Kit's plan and G's code will diverge for one turn (double icons, or no Quit), and nothing re-plans when `awakeActive` changes (`requestMenuRebuild` isn't `applyPlan`).
- Fix:
  - `applyStatusItem(_ row: CustomItemRow{exists, presence, footer, recentNotices})`; the provider creates and removes only there.
  - `AwakeHost.requestStatusPlan()` re-plans in the same turn.
  - The ⌘-drag presence write goes through a host API.

**R2-M7. Live updates inside open menus depend on run-loop mode (§4.5, §5.1, §5.3).**
- An open NSMenu runs `NSEventTrackingRunLoopMode`. `Timer.scheduledTimer`, `RunLoop.main.perform` and Combine schedulers on `RunLoop.main` don't fire there. The plan doesn't say what `ControllerRevision.bump()` coalescing or `MenuSliderRow.bind` use.
- Fix (normative):
  - Coalesce with `DispatchQueue.main.async`.
  - Add timers with `RunLoop.main.add(t, forMode: .common)`.
  - Lint bans `scheduledTimer` and `RunLoop.main` schedulers under `Awake/`, `Core/Menu*` and `*Menu*` files.
  - The 15 Hz cap is trailing-edge.

**R2-M8. Snapshot admission can't do what §2.5 assigns it.**
- Kit `admitted(consent:now:)` runs in ModuleHost's store hook before any module starts. It can't call `proc_pidinfo` ("whilePID re-verified") and has no `PowerFacts` ("guards evaluated first").
- Fix:
  - Split it. Kit keeps source, override, nudge, kind and boot checks.
  - A named `SessionController.restore(_:)` verifies pid, start time and uid, and runs `AwakeGuards.evaluate` with live facts before the first `arbitrate()`.
  - Outside changes to the snapshot while running are ignored.

**R2-M9. `awake hold --parent` fails the journeys it was added for (§2.10, parity B1).**
- Make recipe lines, agent Bash tools (a fresh shell per command) and `$(…)` all have parents that exit within milliseconds, so the session ends `.processExited` at once. An orphaned client's `pbi_ppid` is 1.
- The plumbing has no owner: `LOCAL_PEERPID` has to be read on the accepted fd in A's `ControlServer.acceptAll`, and `ControlRequest` is Codable, so a client could supply the value itself.
- Fix:
  - A server-set, uncoded `peer: PeerInfo` (owner A, step 1).
  - Refuse targets ≤ 1.
  - Re-check `proc_pidinfo` after `resume()` (exit before kqueue registration).
  - The reply names the bound pid.
  - Honest README recipes: `--pid "$PPID"` / `$$PPID` in make, `--pid` of the agent process, or a duration.

**R2-M10. `untilIdle` "CPU < 15%" ends real work (§2.5, C5).**
- `HOST_CPU_LOAD_INFO` is normalized across all cores. A single-threaded compile, link or agent step on 12 cores reads about 8%, which counts as quiet.
- Summed throughput counts `lo0` and double-counts VPN (`utun` plus `en0`).
- The first delta after sleep looks idle.
- Fix:
  - Use `host_processor_info`: quiet = total < 15% **and** busiest core < 50%.
  - Count only non-loopback interfaces, and tunnels only when no physical interface carries traffic.
  - Reset the quiet timer on wake.
  - Pin all of it in `CPUMath`/`NetworkMath` tests.

**R2-M11. Admission on outside changes doesn't fit `ConfigStore.swift:57–70` (§2.14).**
- `guard new != value` returns early. A fully reverted tampered write has `admitted == value`, so `onAdmissionReverted` never fires.
- `lastWritten = data` keeps the bad bytes on disk and `applyingExternal` blocks saving, so every launch reverts and toasts again.
- Fix:
  - Compute `reverted` before the guard.
  - On revert, save the admitted value, at outside change and at load.
  - Order: decode → `sanitized()` → `admit` → assign.

## 4. Minor

1. **§2.4 PreventDiskIdle.** A separate assertion with no timeout and no swap. `IOPMAssertionCopyProperties` returns `Unmanaged`, so use `takeRetainedValue`.
2. **§5.1 alternates.** On 14.0–14.3 the subtitle fallback row breaks ⌥-alternate pairing, because an alternate must directly follow its primary (Automatic Sessions rows). Fall back to "Desk dock — Active" in the title.
3. **§5.1 custom rows.**
   - Arrow keys highlight view items: draw `enclosingMenuItem.isHighlighted` (`NSVisualEffectView(.selection)`) and set an accessibility label.
   - Keep switchHeader height fixed while the menu is open (a session end changes the line count), or defer relayout to `menuDidClose`.
   - MenuSliderRow sends `.ended` after `super.mouseDown` returns; each scroll step is a `.changed` + `.ended` pair.
4. **§2.1 L10.** Also ban selector-based `addObserver(self, selector:` and `publisher(for:)` without `.receive(on: DispatchQueue.main)` under `Awake/`.
5. **§3.6 L9.** Bypassable through a variable. Don't expose `EventCategory.awake`: `AwakeLogEvent` builds the category privately.
6. **§4.5 ConfigSlice.** A `@StateObject`, or cached in the environment, never created in `body`.
7. **§4.5 `.live` sliders.** On `.ended`, set `DisplayRuntime` to the target optimistically and ignore differing readbacks for about 1 s (otherwise the slider snaps back).
8. **§2.13 0.1 upgraders.** `upgradeDefaults()` must also insert Awake disabled: `modulesExisted` is false for 0.1 users, and `ConfigModulesTests:34` breaks otherwise.
9. **§4.6 round trip.**
   - 0.2 drops `migrations`, so M4 and M5 re-run after 0.3 → 0.2 → 0.3; document it.
   - 0.2 re-encodes Awake's preferences without `presence`: map legacy `.ownIcon` back to `.ownIconWhenActive` for Awake.
   - M1: save the modules store first and the Awake store (with its marker) last; use deterministic trigger ids.
10. **§2.10 `awake status`.** Hand-format the ISO time in Kit: `ISO8601DateFormatter` is ICU-backed on corelibs (N12).
11. **§2.5 toasts.** The 8-hour reminder has two buttons but `ToastAction` is single. Add `actions: [ToastAction]` to the lead's ToastPresenter list.
12. **§2.8 platform calls.** `CGSSessionScreenIsLocked` is undocumented: add it to HW-1. `DADiskCopyDescription` is synchronous IPC: keep it off main.
13. **§6.3 stubs.**
    - K16 keeps one `ChangeFanout` per instance.
    - A new `OnboardingStep.awake` breaks the exhaustive switch at `Onboarding.swift:110` (H), so it lands in step 1, not step 0.

## 5. Mechanism verdicts

- **Clock**: `CLOCK_MONOTONIC_RAW` is correct.
- **awake hold**: server-side `EVFILT_PROC` on a same-uid pid works with no persistent connection.
- **MenuKit rows**: feasible; the MenuSliderItem pattern is proven.
- **Migrations**: idempotent per marker.
- Everything else as ranked above.
