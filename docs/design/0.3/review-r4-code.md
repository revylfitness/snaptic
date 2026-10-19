# PLAN 0.3 r4: adversarial review round 4 (code, buildability)

Checked against `feature/displays` @ 871c10b. Counts: **0 Blocker, 2 Major, 4 signature rows, 6 Minor**.

## 1. r3 code findings

| r3 | Status |
|---|---|
| sig StableID | Resolved (§2.14 `StableID.derived`, FNV-1a-128, version 8). No SHA-1 is needed. `UUID(uuid:)` plus `uuidString` (uppercase on corelibs too) gives a valid `StableID`. |
| sig lossy arrays | Partly resolved (§2.7, §2.14). The snapshot, history and sessions decoders are missing: **S2** |
| sig ControlResponse, AwakeHost.init, SettingsAnchor, M10 names, MenuSliderRow, legacy AwakeActionIDs, ControlListener.Handler | Resolved (§2.10, §2.11, §4.1, §2.2/§4.6, §5.1, §4.8.1) |
| B1 | Replaced by lead-8 (§4.8, §4.8.2, L15). Feasible. Residue: m1, m2, m3 |
| M1 | Resolved (§2.1 start order 1–6, §2.14 `dynamicNeeds`) |
| M2 | Timebase resolved (§2.8 `CPUTimebase`). The short-process replacement doesn't work: **M1** |
| M3 | Resolved (§2.10 connection rules). Residue: m5 |
| M4 | Resolved (§4.8.1 literal list: 588 ids, counts verified, no duplicates; Mirror cross-check; in-process `--selftest-controls`) |
| M5 | Resolved (§4.6 M1 derived ids, replace-by-id writer, two-run test) |
| M6 | Resolved for rules and presets. Holds and history: **S2** |
| m1–m14 | Resolved (§2.5, §2.8, §2.10, §2.11, §3.6, §4.1, §4.5, §4.6, §5.3, §6.2–§6.4) |

## 2. Signatures that won't compile or won't work

| § | Problem | Fix |
|---|---|---|
| S1 §2.5 `ToastAction` | 0.2 declares `struct ToastAction { let title; let perform }` (ToastPresenter.swift:7). Seven trailing-closure call sites use it: WindowGatherer:43, AppDelegate:92, ModuleHost:218, ProtectionController:170, PowerController:283, ResolutionController:420 and :475. The r4 shape `{title, isDefault, action}` removes `perform` and adds a `let` with no default, so the memberwise init breaks D's and A's files at step 0. | Keep `perform` and add `init(title:isDefault: Bool = false, perform:)` |
| S2 §2.14 | `AwakeRuntimeSnapshot`, `AwakeHistory` and `AwakeSessionsConfig` declare no `init(from:)`, but S stubs are written "from this plan's signatures". Synthesized decoding of `[AwakeHold]` is all-or-nothing. Because `.connection` bindings throw by design, one stray hold drops the whole snapshot, manual session included. | Declare `package init(from:)` on all three, using `lossyArray` per list and `lossy` per field (rule 9). Same for the other Awake sub-configs |
| S3 §4.8 | `ControlLegacy.switcherKeyPaths: [String: LegacyControlID]` can't map `disabledFeatures` to the 14 `l.sw.feature.*` ids | `[String: [LegacyControlID]]` |
| S4 §2.8 | `ProcessCPUSample.startTime` and `CPUMath.window(windowStart:)` have no unit or source. `proc_pidinfo` gives a µs wall clock, which is a second syscall per pid and jumps with clock changes. | Use `rusage_info_v2.ri_proc_start_abstime`, with `windowStart` as the previous sample's `mach_absolute_time()` (same call, monotonic). See also M1 |

Everything else type-checks in Swift 5 mode (5.10 Linux / 6.1). Checked in particular:
- `package private(set)` on the gate, and `[any ControlTable.Type]`.
- `ControlID`'s non-failable `init(rawValue:)` satisfying `RawRepresentable`.
- `LossyArray<HookSpec>()` through the defaulted init.
- The `register` overloads resolve by closure arity.
- `ControlHold` can hold a `private weak` reference to `ControlConnection`.
- `proc_pid_rusage` through `withMemoryRebound`, and `LOCAL_PEERPID` as an integer macro.
- FNV-128 through `multipliedFullWidth`.

## 3. Major

**M1. "Until Downloads and Tasks Finish" ends during a serial build (§2.8, N9, §6.6 TaskQuiet, HW-23).**
- Per-process sampling only sees processes alive at a sample instant. With `make -j1` and 1–3 s compiles (clang runs cc1 in-process), about one compiler is alive per 5 s sample.
- So `newProcesses` ≈ 1 (< 3), the first-seen compiler reads 0–40% of a core (< 50%), and total CPU on 10–12 cores is 8–12% (< 15%).
- Every sample is quiet, and the session ends after 5 min mid-build.
- The Kit test "a stream of 2 s processes stays busy through newProcesses" only passes because its fixture already has ≥ 3 new processes per window.
- Fix:
  - Count `ri_child_user_time + ri_child_system_time` (rusage_info_v1+, same Mach units, timebase-scaled) in each process's ticks. `make`, `npm`, `cargo` and shells live across samples, and their child-time delta carries every reaped child's CPU. Reaping is recursive.
  - A reap spike only reads as busy, which is fail-safe.
  - Rewrite the Kit test as "a long-lived parent whose child time grows by 5 s per 5 s window → about 100%".
  - Keep churn and total CPU as extra signals.

**M2. The §2.10 connection tests have no harness (§2.10 "tested on the macOS job", §6.4 step-1 exit).**
- `ControlServer` and `CLIClient` live in the executable target. Package.swift has only `SnapticKitTests`, and lint rule 12 bans `fork(` in Sources.
- None of the listed cases (busy 5th request, 9th hold, exit before accept, inherited fd, extra byte, ping at 300 s) has a runner.
- `ControlServer.start` takes its socket path from `getpwuid_r`, so a test can't isolate it.
- So A can't meet the step-1 exit as written.
- Fix:
  - A adds `Snaptic --selftest-control <token-file>`, token-gated like `--selftest-helpers`. It runs a ControlServer on a temp socket path (token mode only) with a test registry: verb `selftest hold` (`holds: true`), plus slow and normal verbs. In token mode `holdPingSeconds` is 1 s.
  - The lead adds `scripts/selftest-control.sh` (real `snaptic` clients: background, `kill -9`, an fd inherited through a subshell) and a step-1 `build.yml` step.
  - `CLIClient` gets the same token-mode path override.

## 4. Minor

1. **L15 attach points (§4.1, §5.1).**
   - `ActionMenuItem`, `StatusAction`, `PageFooterButtons`, `SettingsPageHeader`, `NavigationRow`, `ButtonRow` and `MenuKit.header/status/device/settings/quit/alternate` render declared controls but take no `ControlID`.
   - L15 can then only be met with a stray literal, which proves nothing. Add `control: ControlID? = nil` to each.
   - State that table ids are full plain string literals in `ControlSpec("…", …)` (the python lint parses them), that comments are stripped, and how a file with two `typealias Controls` is checked.
2. **Missing builder tables (§4.8.2).**
   - `OverviewController` (F: `f.tools.*`, `f.quick.redetect`) and `AutomationController` (A: `a.custom.*`, "Actions ›") are `DisplayMenuContributor`s with no table and no `*MenuItems` file to move into.
   - D's five controller contributors need a named target file.
   - Test 6 freezes the list, so owners can't add tables themselves.
3. **Registry test timing and the walker (§4.8 tests, §6.4).**
   - Running everything only at the step-3 exit puts all owners' failures in one merge. From step 1, run per-table checks: test 2, test 3, "replaces ⊆ legacy" and `parentOn`. Keep only totality and the key cross-check skipped.
   - Specify the Mirror walker: Swift property names (not CodingKeys), `LossyMap`/`Dictionary`/`Array` → `*`, Optional unwrapped, enum payloads by case name. Owners need it to spell `keys:`.
    - "All 46 `DisplayMenuItemID`s present" can't enumerate app-side ids (DDCMenuItems.swift:8 etc.) in Kit. Move that check into `--selftest-controls`.
4. **Confirmation toast dismissal (§2.5).** ToastPresenter has no dismiss or expiry callback (10 s expiry, merge, queue), so "dismissing counts as Not Now" can't be implemented. Add `show(…, actions:, remember: false, onDismiss:)`, and map expiry and dismissal to `.confirmDeclined`. Today the gate would stay `.asking` for good. That is safe, but untested and not what the plan says.
5. **Hold edge rules (§2.10).**
   - The listener-side "holding reply while `held == 8` → refusal" must also fire the `ControlHold`'s close, so SessionController ends the hold it just added.
   - Request bytes after the newline in the same first chunk count as "a byte after the request".
   - State the new `dispatch(_:peer:hold:skipConfirmationAllowed:)` signature.
6. **Doc conflicts.**
   - `StableID.derived` lives in KitLossy.swift (§2.14) or KitModules.swift (§6.2). Pick one.
   - §6.3 lists "ControlServer's new types" as lead S stubs, but §6.4 makes them A's step 1. Drop the stub; nothing calls them before step 2.
   - Scope L16's `AwakeActivityGate(` ban to `Sources/Snaptic/`: Kit's own `applying(.moduleStop)` and the tests construct it.

## 5. Mechanism verdicts

- **Control tables, L15 and the 588-id list.** Feasible in Kit and in python. The list is frozen, so maintenance falls on owners' `replaces:` and `keys:` (m1–m3).
- **LossyArray.** Compatible with the existing callers; the `SkipValue` advance works as in 0.2.
- **StableID.derived.** Its own hash (FNV-1a-128) is enough; it needs no SHA-1. Test vector: "a" = d228cb696f1a8caf78912b704e4a8964.
- **uiStartedInProcess gate.** Sound: `private(set)`, and nudges require manual ∧ uiStarted ∧ allowed. `takeover` is unreachable under N3 (harmless). Residue: m4.
- **Hold slot pool.** It fits ControlConnection: `active -= 1` moves to the holding transition, plus a `held` count and a ping timer on the listener queue. The queue's FIFO order keeps an end before the next hold. Residue: m5, M2.
- **proc_pid_rusage + timebase.** Correct, and other users' processes are refused. About 600 calls fit in 5 ms. Coverage: M1.
- **Step 0.** Feasible with S1 fixed. `ModuleID.awake` touches one exhaustive switch (ModuleHost.swift:139).
- **Ownership.** No collisions. Gaps: m2 and M2.

**Verdict: Ready with fixes** (M1, M2 and S1–S4 before step 0/1; the Minors can be fixed in the teams' briefs).
