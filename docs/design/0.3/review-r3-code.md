# PLAN 0.3 r3: adversarial review round 3 (code, buildability)

Checked against `feature/displays` @ 871c10b. Counts: **1 Blocker, 6 Major, 14 Minor**.

## 1. r2 code findings

| r2 | Status |
|---|---|
| 12 signature rows | Resolved (§2.2–§2.9, §2.14, §4.5, §5.2). The same gap remains in other types: **M6** |
| R2-M1 ratchet | Resolved (§6.3). The lookbehind needs python: m3 |
| R2-M2 step-0 ripples | Resolved (§2.11, §4.5, §6.4). §6.2 wording conflicts: m14 |
| R2-M3 / R2-M4 | Resolved (§2.14 `bootSession`, §2.6 `reloaded`; §2.4) |
| R2-M5 / R2-M11 | Retired with consent (N10). Accepted |
| R2-M6 | Contract resolved (§2.11). Residue: m1, m9 |
| R2-M7 | Resolved (N15, L14). Residue: m4 |
| R2-M8 | Resolved (§2.5, §2.14). Activation order open: **M1** |
| R2-M9 | Replaced by lead-3 (§2.10). Mechanics underspecified: **M3** |
| R2-M10 | Partly resolved. Measurement wrong: **M2** |
| m1–m13 | Resolved. m9's round-trip claim is false: m13 |

## 2. Signatures that still won't compile or won't work

| § | Problem | Fix |
|---|---|---|
| §4.6 M1 | `StableID` "m1."+SHA-256: `StableID.init?(rawValue:)` requires a UUID string, so it returns nil. Kit has no SHA-256 (CryptoKit is app-only; `LayoutPresetModel` gets its digest from the app) | 16 bytes formatted as a UUID; bytes from an injected `digest:` closure or a 128-bit FNV over the sorted keys |
| §2.7, §2.14 | `AwakeTrigger`, `AwakePreset`, `AwakeHistoryEntry` have no `init(from:)`; their arrays decode all-or-nothing | **M6** |
| §2.10 | `ControlResponse` has synthesized Codable (KitControl.swift:35): a new `holding` key becomes required | Hand-written `c.lossy(.holding, false)`; `init(…, holding: Bool = false)`; `jsonReply` keeps `holding` |
| §2.11 | `AwakeHost.init(ModuleContext)`: ModuleContext has no `requestStatusPlan` or `setPresence` (§6.2 adds only `hostSignals`) | m1 |
| §4.1 | `extension View { settingsAnchor }` fails lint rule 10 (lint.sh:97–120) | `struct SettingsAnchor: ViewModifier`, or an exemption |
| §4.6 M10 | `menu.itemVisibility[d.disconnectItem]`: the field is `MenuConfig.items` and the id is `.dDisconnectItem` (ManagementIDs.swift:52). `c.ddc.power` exists only in the app (`DDCMenuItems.powerItem`) | `menu.items[.dDisconnectItem]` plus a Kit constant for `c.ddc.power` |
| §5.1 | `MenuSliderRow: NSMenuItem` | Add `required init(coder:)` (no trap) |
| §4.8 | `ControlMapLegacy.actions` lists AwakeActionIDs, which don't exist in 0.2 | Drop them |
| §2.10 | `ControlListener.Handler(…, ControlHold?, …)`: the listener can't know `holds`, because the registry is on main | The listener always creates a hold. `dispatch` exposes it only when `entry.holds`, and turns a `holding` reply from any other verb into an ordinary close |

Everything else in §2–§5.2 type-checks in Swift 5 mode (5.10 and 6.1). The old/new `register` overloads resolve by closure arity, so the 44 call sites keep compiling.

## 3. Blocker

**B1. The "Check Control Coverage empty" gate can't be met (§4.8, §6.4 step 3, §6.5).**
- It is a DEBUG menu walk on a Mac. Teams have only CI.
- No single Mac can pass it:
  - Grouped `Form` is list-backed and lazy, so off-screen rows never render.
  - Hardware-gated rows are omitted by design (§4.1): XDR, DDC VCPs, battery on a desktop, ≥ 2 displays.
  - Subordinate rows appear only while their parent is on.
  - `ActionMenuButton` items and lazily built submenus render only when opened.
- Fix:
  - A token-gated `--selftest-coverage` in macOS CI. It hosts each root, route and sheet off-screen with a DEBUG fixture (all hardware, features and parent toggles on) and `scrollTo`s each catalog anchor through the scaffold's ScrollViewReader.
  - MenuKit and `ActionMenuButton` record ids at construction, and the walker runs `menuNeedsUpdate` recursively.
  - A Kit allowlist of state-gated ids, checked in the HW session.

## 4. Major

**M1. A restored `hold`/`untilIdle` session runs without its services (§2.1, §2.5).**
- Dynamic needs are computed before controllers start, and `restore` runs inside `SessionController.start`. So `process`, `cpu`, `disk` and `network` are inactive.
- Unknown samples count as busy, so a restored uncapped UI `untilIdle` session never ends. The `hold(.process)` re-verify uses an inactive ProcessWatch.
- Fix:
  - `AwakeModule` seeds `AwakeDynamicNeeds` from `sanitized(now:)` before the first apply.
  - `restore` re-applies when needs change; services re-arm in `activate`.
  - Deactivating `process` ends the hold `.processExited`.
  - Kit test.

**M2. The top-process signal fails HW-23 (§2.8, N9).**
- On Apple silicon, `rusage_info_v2.ri_user_time` and `ri_system_time` are Mach ticks, not ns. Without `mach_timebase_info` scaling (×125/3), a busy process reads about 2.4%.
- Per-pid deltas never see a `make -j1` compile phase, which is many 1–3 s `clang`s. "Total ≥ 15%" doesn't catch it on 10–12 cores.
- Fix:
  - Scale by the timebase (Kit takes numer/denom).
  - First-seen pids that started inside the window count their whole CPU time.
  - Compare the **sum** over same-user processes with `topProcessPercent`.
  - Note the transient in-memory pid→counter map in §3.6.
  - Tests.

**M3. Held connections need rules ControlServer.swift doesn't have (§2.10).** Feasible:
- **Slots.** `active` is released only in `onFinish` (lines 239–242, 331–337). A holding reply releases the slot once and moves the connection to `held`, so `finish()` doesn't decrement twice.
- **One hold.** `maxHeldConnections` is enforced on the listener queue. Old `finish` and new reply are `queue.async`'d in that order.
- **Early close.** `onClose` registered after a close fires next turn. The handler checks `hold.isClosed` after arming ProcessWatch.
- **EOF after the reply.** `cancellation` is nil then, so the EOF branch (line 291) must call the hold's close.
- **Client.** `CLIClient.readReply` drops bytes after the first newline: keep the remainder. `fflush` the first line. EOF without a final line exits 5.
- **CLI turned off.** The verb's `lifetime.onEnd` finishes held connections.
- **Peer.** Reuse `SNProcess.startTime(for:)` (same µs epoch) and `getpeereid` for the uid. `SOL_LOCAL`/`LOCAL_PEERPID` import into Swift as-is.

**M4. Frozen 0.2 lists can't be captured as described (§4.8, §6.4).**
- `gen-controlmap.py` has no compiler to read Codable key paths from.
- `JSONEncoder` omits nil optionals: Switcher `gatherShortcut` (Settings.swift:317), `MenuConfig.showPanelShortcut`/`identifyShortcut`.
- "Frozen mirror" contradicts "a new Switcher key fails CI".
- Fix:
  - A Kit dump test (every optional set, one `perDisplay` entry, all features on, `Mirror` labels, `perDisplay.*` paths), run once in CI at 871c10b; the lead pastes its output into the frozen list.
  - `--selftest-controls` compares in-process (it links Kit): legacy ⊆ current ∪ removed, and current ⊆ legacy ∪ `ControlMap.newSwitcherKeys`. It exits nonzero itself.

**M5. M1 can't be idempotent (§4.6).** With invalid ids and no Kit SHA-256, a fallback to random ids duplicates rules when M1 re-runs (crash between saves, missing marker). Fix per §2. Test: two runs over the same JSON give equal ids.

**M6. One unknown entry empties whole Awake lists (rule 9; §2.7, §2.14).**
- A 0.4 criterion makes synthesized `AwakeTrigger` decoding throw. `[AwakeTrigger]` then throws too, `c.lossy` falls back to `[]`, and the next save persists the loss.
- The same happens to presets (`AwakePresetKind`) and history (`AwakeEndReason`).
- Fix:
  - Hand-written lossy decoders for those three types.
  - All four arrays through the existing `LossyArray` (ConfigAutomation.swift:212).
  - Tests.

## 5. Minor

1. **AwakeHost sources (§2.11).** `ModuleContext` (lead) gains `requestStatusPlan`, `setPresence: (ModuleID, MenuPresence)` and `hostSignals`.
2. **`settingsAnchor` lint (§4.1).** It fails rule 10; make it a ViewModifier.
3. **L5 lookbehind (§6.3).** lint.sh uses `grep -E`, and BSD grep on macOS has neither lookbehind nor `-P`. Implement L5 in python.
4. **L14 (§6.3) bans `ResolutionMenuItems.swift:111`.** Its `RunLoop.main.perform(inModes: [.default])` deliberately applies after tracking. Allow explicit `.default` deferral.
5. **M10 identifiers (§4.6).** Fix the names as in §2.
6. **DiskIOSampler (§2.8).**
   - Sum per driver, keyed by `IORegistryEntryGetRegistryEntryID`, so hot-plug isn't a reset or a spike.
   - Disk counters are system-wide, so root Spotlight and Time Machine I/O count as busy. Reword HW-23.
7. **Ownership and sequencing (§6.2, §6.4).**
   - `ConfigModulesTests` (A) and `ConfigMenuTests` (F) don't move with their sources.
   - `Fingerprint.matches` (B, step 1) is needed by G's step-1 `TriggerEngine`.
   - `ToastPresenter` `actions:` (lead, step 2) runs in parallel with G's step-2 callers.
   - Stub them in step 0.
   - The `selftest-controls` CI step (lead, step 0) precedes A's flag (step 1).
8. **`ControlResponse` decoder (§2.10).** Hand-written decoder, and `jsonReply` keeps `holding`.
9. **Deferred status item (§5.3).** "Deferred while open" contradicts "only in `applyStatusItem`". The provider keeps reporting the item through `statusItem` and re-applies in `menuDidClose`.
10. **Snapshot writes (§2.14).** "Outside writes ignored while running" needs SessionController to assign `state.value` from memory, never mutate the adopted value.
11. **Counted events (§3.6).** `EventLog` (A, a singleton) can't reach the per-context `AwakeDiagnostics` (G). Keep the counters in `EventLog`.
12. **Coverage ids (§4.8).** Coverage records anchors, but the catalog uses `SettingsSearchEntry.id`. Require `id == anchor` (Kit test).
13. **Round-trip markers (§4.6).** After 0.3 → 0.2 → 0.3, M5 and M10 override user choices. Keep the markers in their own key (`SnapticMigrationsV1`), which 0.2 never rewrites.
14. **§6.2 wording.** The lead row says DisplaysPageEnvironment "forwards no config", which conflicts with §6.4 (step-3 exit).

## 6. Mechanism verdicts

- **ControlServer peer and hold.** Fits the queue and connection design with the M3 rules.
- **ProcessWatch.** A kqueue fd plus `DispatchSourceRead` on main, `EV_ADD|EV_ONESHOT NOTE_EXIT`, then re-reading start time and uid, is race-free for pid reuse; `kevent` returns ESRCH synchronously. One kq per hold, closed in the cancel handler. Activation order: M1.
- **ControlID registry.** The Kit tables and tests are feasible on Linux (`XCTSkip` exists in corelibs). Capture: M4. Coverage: B1.
- **IOKit block-storage stats.** Unprivileged, no TCC, about 50 µs per sample (m6).
- **Menu timers in `.common`.** Correct. `.common` includes event tracking, and the main dispatch queue drains in common modes.
- **Step 0.** Feasible. The only exhaustive `ModuleID` switch is `ModuleHost.module(_:)` (lead). The ratchet is pure python.
- **Migrations.** Idempotent per marker after M5. The save order is sound. Downgrade keeps the legacy fields. Round trips: m13.
- **Ownership.** No symbol collisions; the remaining issues are in m7.
