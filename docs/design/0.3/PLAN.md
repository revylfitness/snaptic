# Snaptic 0.3 plan: Awake module, Settings redesign, Menu bar redesign

Status: **r5 (final)** (planning architect, after review round 4; r4 kept as `PLAN-r4.md`, r3 as `PLAN-r3.md`, r2 as `PLAN-r2.md`, r1 as `PLAN-r1.md`). Implementation starts from this revision; see "Implementation readiness" at the end. Base: `feature/displays` == `main` @ 871c10b.
Normative like `docs/design/PLAN.md` (0.2): where this plan and 0.2 disagree, **this plan wins** for 0.3 scope; everything 0.2 says that this plan does not touch (safety framework, helpers, guard, transactions, R5 amendments) stays in force. Swift signatures in this document are the contract the lead writes as compiling stubs in step 0; once on the branch, the code wins over prose (R5 rule carried forward).

## R5 amendments (highest precedence)

This section resolves review round 4 (`review-r4-{product,security,code,consistency}.md`, every verdict "Ready with fixes"). **Where this section and anything else in this plan disagree, this section wins.** Small local body edits that apply it are marked "(R5)". Naming: `R5-n`, with a hyphen, is an amendment in this section; 0.2's rules keep their dotted form (`0.2 R5.7`). Larger rewrites stay here only. Swift signatures below are step-0 contract text and compile in Swift 5 mode (Xcode 16.4, Swift 5.10 Linux).

Totals:
- **Product:** 1 M + 7 m resolved. m6 uses the reviewer's second option.
- **Security:** 1 M + 6 L resolved. L2's arm delay is 300 ms by lead decision, not 0.5–1 s.
- **Code:** 2 M + 4 signature rows + 6 m resolved.
- **Consistency:** 2 M + 10 m resolved. m5 is resolved by deriving search entries from control specs; m9a by ending holds when command-line control turns off.

Nothing is rejected outright. The traceability table is at the end of this section.

### R5-1 `ToastAction` / `ToastPresenter` (code S1, consistency M1, security L2 + L6, code m4)

`ToastAction` is **extended, not redeclared**. `perform` stays, so all 15 `ToastAction(title:perform:)` call sites and the trailing-closure forms keep compiling. Lead, `Core/ToastPresenter.swift`:

```swift
struct ToastAction {
    let title: String
    let perform: @MainActor () -> Void
    var isDefault: Bool = false                      // R5: bold default button; at most one per toast
    init(title: String, isDefault: Bool = false, perform: @escaping @MainActor () -> Void) {
        self.title = title; self.isDefault = isDefault; self.perform = perform
    }
}
enum ToastDismissal: Equatable, Sendable { case expired, closed, lifetimeEnded, evicted, dismissedAll }
/// Click arming for toasts whose action grants something (security L2).
struct ToastClickGuard: Equatable, Sendable {
    var armDelay: TimeInterval = 0.3                 // from the moment the panel shows THIS content (re-armed on every content change)
    var refuseWhenOverlapped: Bool = true
    static let confirmation = ToastClickGuard()
}
// Members of ToastPresenter. The existing `show(_:action:lifetime:)` is unchanged.
//   /// ≤ 2 actions. Returns false when nothing was presented or queued: suppressed, merged with an identical text,
//   /// empty, or lifetime already ended. With `remember: false` the toast never reaches Recent Notices.
//   /// `onDismiss` runs exactly once, on main, when the toast goes away without one of its actions having run.
//   @discardableResult
//   func show(_ message: String, actions: [ToastAction], lifetime: Lifetime? = nil, remember: Bool = true,
//             clickGuard: ToastClickGuard? = nil,
//             onDismiss: (@MainActor (ToastDismissal) -> Void)? = nil) -> Bool
```

**Rules (normative)**

**Guarded clicks.** On a guarded toast, a button click is **ignored**, not queued, in either of two cases:
- Less than `armDelay` (300 ms) has passed since the panel showed this content.
- `CGWindowListCopyWindowInfo(.optionOnScreenAboveWindow, CGWindowID(panel.windowNumber))` lists a window that intersects the panel's frame, has `kCGWindowAlpha` > 0 and a `kCGWindowOwnerPID` ≠ `getpid()`. The overlap is computed in CG global coordinates. Bounds and PID need no Screen Recording.

The panel stays non-key (`canBecomeKey == false`), so a guarded toast has no keyboard path.

**Confirmation toasts** are exactly two: the hotkey prompt "Move the pointer to keep apps active?" (Allow / Not Now) and the guard refusal toast (**Start Anyway**).
- Both use `remember: false` and `clickGuard: .confirmation`.
- The pointer prompt's lifetime is the manual session's lifetime. When it is shown, the toast captures the session id. Allow applies `.confirmAllowed` only if that id is still the governing manual session.
- Start Anyway's lifetime ends at the next start, `turnOff` or module stop.

**Gate wiring.**
- `.confirmAsked` is applied only when `show` returned true. Otherwise the gate stays `askOnFirstUse` and asks again at the next interval.
- `onDismiss` (any case) and Not Now apply `.confirmDeclined`.
- Kit test: from `askOnFirstUse`/`asking`, only `confirmAllowed` (from `asking`) or a new `uiStart` reaches `.allowed`; every other event sequence leaves `pointer != .allowed`.

**Step 0** gives these members as S stubs: a `show(…actions:…)` that forwards to the old path and returns true. The lead implements them in step 2 (§6.4).

### R5-2 Migrations run in `ModuleHost`, not in decoders (consistency M2 + m2; lead guidance)

M3, M4, M5 and M10 become pure Kit functions over **decoded** values and take the ledger. Decoders never migrate: they only decode, lossily.

M2 (placement → presence) stays in `ModulesConfig.init(from:)`. Two reasons it is idempotent: it is a pure mapping applied only while the new `presence` key is absent, and the same model writes `placement` back. It needs no marker.

```swift
// SnapticKit/Config/ConfigMigrations.swift (lead)
package enum MigrationID: String, CaseIterable, Sendable {
    case fromDisplays = "fromDisplays.v1", fromDisplaysToast = "fromDisplays.toast"
    case newModuleCards = "newModuleCards.v1", menuShortcuts = "menuShortcuts.v1"
    case showNits = "showNits.v1", powerSwitch = "powerSwitch.v1"
    case awakeUpgrade = "awakeUpgrade.v1"             // step-4 fix round 1: the §2.13 decision, made once
}
package struct MigrationLedger: ConfigModel {
    package var done: Set<String>                     // raw strings, so a 0.4 id survives a 0.3 load
    package init()
    package init(from decoder: Decoder) throws        // element-wise
    package func has(_ id: MigrationID) -> Bool
    package mutating func record(_ id: MigrationID)
    package func sanitized() -> MigrationLedger       // ≤ 256 ids
}
extension ModulesConfig {
    /// M3: `showNewDisplaysCard == true` → `newModuleCards` gains `.displays`; runs iff `newModuleCards.v1` is absent, then records it.
    package func migrated(ledger: inout MigrationLedger) -> ModulesConfig
    /// §2.13: runs iff `awakeUpgrade.v1` is absent, then records it; inserts Awake off + "New: Awake" only when
    /// `modulesExisted`, the ledger lacks `fromDisplays.v1` (no 0.3 build ran before; fix round 2) and `modules[.awake] == nil`.
    package func insertingAwakeForUpgrader(modulesExisted: Bool, ledger: inout MigrationLedger) -> ModulesConfig
}
extension DisplaysConfig {
    /// M4, then M5, then M10, each only when its marker is absent; records each marker it ran.
    package func migrated(ledger: inout MigrationLedger) -> DisplaysConfig
}
```

**Order in `ModuleHost.init` (lead, normative):**
1. Load the ledger.
2. `modules = modules.migrated(ledger:)`.
3. `displays = displays.migrated(ledger:)`.
4. Insert Awake disabled for upgraders, once (§2.13; `modules.insertingAwakeForUpgrader(modulesExisted:ledger:)`, marker `awakeUpgrade.v1`).
5. Run M1 (§4.6).
6. `save(force: true)` in this order: modules, displays, Awake, then the ledger last. Writing the ledger is the commit point.

A crash before the ledger save re-runs M3, M4, M5 and M10. Each is idempotent over the values written in that crashed run.

Two cleanups:
- §4.6's "Where" column for M3, M4, M5 and M10 now reads "`ModuleHost` via `migrated(ledger:)`" (R5).
- `DisplaysConfigSection.migrations` and §6.2's "migrations markers" in ConfigDisplays are dropped (consistency m2). `DisplaysConfigSection` has one case per `DisplaysConfig` field, with `perDisplay` split.

Kit tests:
- Each migration runs once.
- A recorded marker prevents a second run.
- A 0.2 round trip (legacy fields kept, ledger untouched) re-runs nothing.

### R5-3 Lossy lists everywhere; duplicate ids never crash (code S2, security L3; lead guidance)

```swift
// SnapticKit/KitLossy.swift (⇢ lead, with KitLossyTests.swift; consistency m1)
extension Array where Element: Identifiable {
    /// First element per id wins, order kept; never traps (security L3).
    package func uniquedByID() -> [Element]
}
extension Array where Element: Hashable {
    package func uniqued() -> [Element]               // first occurrence wins, order kept
}
extension KeyedDecodingContainer {
    package func lossyArray<T: Codable & Equatable>(_ key: Key, _ fallback: @autoclosure () -> [T]) -> [T]
    /// lossyArray, then uniquedByID: duplicate ids are dropped on decode.
    package func lossyUniqueArray<T: Codable & Equatable & Identifiable>(_ key: Key,
                                                                         _ fallback: @autoclosure () -> [T]) -> [T]
}
```

**Each of these types declares `package init(from decoder: Decoder) throws`.** Each decodes lossily per field (rule 9) and never decodes a list all-or-nothing. The S stubs are written with these decoders.

| Type | Lists / special fields |
|---|---|
| `AwakeConfig` | sub-configs via `c.lossy(…, default)` |
| `AwakeSessionsConfig` | `presets` via `lossyUniqueArray` (≤ 12); `recentApps` via `lossyArray` + `uniqued()` (≤ 5) |
| `AwakeTriggersConfig` | `triggers` via `lossyUniqueArray` (≤ 32) |
| `AwakeTrigger` | `criteria` via `lossyArray` (≤ 8) |
| `AwakeRuntimeSnapshot` | `manual` via `try? decodeIfPresent` (a bad session → nil, the rest kept); `holds` via `lossyUniqueArray` (≤ 8); `suppressions` `LossyMap`; `guardMemory` lossy |
| `AwakeHistory` | `entries` via `lossyArray` (≤ 500) |
| `AwakeGuardsConfig`, `AwakeIndicatorConfig`, `AwakeActivityConfig`, `DriveAliveConfig` | lossy per field (`volumes` is a `LossyMap`) |
| `ModulesConfig` | `newModuleCards` via `lossyArray` + `uniqued()` |
| `MigrationLedger` | `done` element-wise |

Rules:
- Every `sanitized()` also applies `uniquedByID()`, because a programmatic writer can produce duplicates too.
- **Lint L17 (R5):** `uniqueKeysWithValues` is banned under `Sources/Snaptic/Awake/` and in `SnapticKit/Awake*.swift` and `SnapticKit/Config/ConfigAwake*.swift`. Use `Dictionary(_:uniquingKeysWith: { first, _ in first })` instead.

Kit tests, per list:
- Two elements with the same id decode to one (the first), with no trap.
- A snapshot with one undecodable hold keeps the manual session and the other holds.
- One bad preset keeps the others, and the next save keeps them too.

### R5-4 "Until Downloads and Tasks Finish": child CPU time and a minimum hold (code M1 + S4; lead guidance)

**Problem.** Per-process sampling misses serial builds: with `make -j1`, about one compiler is alive at each sample. The fix is to count **child CPU time**. A long-lived parent's reaped-children counters carry every child's CPU, and reaping is recursive (cc1 → clang → make).

```swift
// SnapticKit/CPUMath.swift (J)
package struct ProcessCPUSample: Equatable, Sendable {
    package var pid: Int32
    /// rusage_info_v2.ri_proc_start_abstime: Mach absolute units (the mach_absolute_time base: monotonic, not
    /// timebase-scaled), from the same proc_pid_rusage call as the ticks (code S4). Identity = pid + startAbs.
    package var startAbs: UInt64
    /// ri_user_time + ri_system_time + ri_child_user_time + ri_child_system_time (Mach units; R5).
    package var cpuTicks: UInt64
    package init(pid: Int32, startAbs: UInt64, cpuTicks: UInt64)
}
extension CPUMath {
    /// `windowStartAbs` = mach_absolute_time() read right before the PREVIOUS sample's pid walk; `seconds` = the
    /// continuous-clock delta between the two samples. Same pid+startAbs in both → tick delta (a counter that went
    /// down → 0). First seen now with startAbs ≥ windowStartAbs → all its ticks, and it counts in `newProcesses`.
    /// First seen now with an older startAbs → nothing. `top` = the largest per-process share (100 = one core); a reap
    /// spike may exceed 100, which only reads as busy (fail-safe).
    package static func window(prev: [ProcessCPUSample], now: [ProcessCPUSample], windowStartAbs: UInt64,
                               seconds: Double, timebase: CPUTimebase) -> (top: Double?, newProcesses: Int)
}
// UntilIdleSpec: `graceSeconds` is replaced by
//   package var minimumHoldSeconds: Int     // 600; 0...3_600: the session never ends .tasksFinished before
//                                           // startedContinuous + minimumHoldSeconds (covers "start, then begin the job")
// (the key never shipped). TaskQuiet.step gains the start instant:
//   package static func step(quietSince: Double?, sample: TaskActivitySample, now: Double, started: Double,
//                            spec: UntilIdleSpec) -> (quietSince: Double?, finished: Bool)
```

Rules:
- CPUSampler calls `proc_pid_rusage(pid, RUSAGE_INFO_V2, …)` for every same-user pid, as before; `proc_pidinfo` is no longer used for start times.
- Churn (`newProcesses`) and total CPU stay as extra signals.
- A child's own ticks plus its parent's reap delta can count twice. `top` is a maximum, not a sum, so that can only make a sample read busy. Accepted.

The §6.6 test "a stream of 2 s processes stays busy through `newProcesses`" is replaced by:
- a long-lived parent whose child time grows 5 s per 5 s window reads ≈ 100% and stays busy;
- a `make -j1` fixture (no child alive at either sample instant, parent child time +2 s per window, 0 new processes seen) stays busy;
- the session ends only after `quietSeconds` with no growth, and never inside `minimumHoldSeconds`.

HW-23 adds `make -j1` with 1–3 s compiles (R5).

### R5-5 ControlServer: hold self-test, edge rules, held writes (code M2 + m5, security L5)

**Self-test (A, step 1; lead guidance).** `Snaptic --selftest-control-server <token-file>` is a new A mode:
- Mode and files: `KitArgs` adds `LaunchMode.selftestControlServer`, `SnapticEntry` dispatches it to `SelfTest.run`, and the code lives in `Core/SelfTest.swift`.
- Gating: it runs only when `SNAPTIC_SELFTEST_TOKEN` equals the token file's contents, exactly like `--selftest-helpers`. It is built in every configuration and kept out of help.
- It starts **no modules**, only a `ControlServer` with a test registry, on the path in `SNAPTIC_SELFTEST_SOCKET`. That path must be under the token file's directory and is checked with the 0.2 path rules (0700 directory, 0600 socket, < 104 bytes).
- Test registry verbs:
  - `selftest hold` (`holds: true`): replies `holding`, watches `peer.pid` with a `DispatchSource.makeProcessSource(.exit)` and finishes the hold when that pid exits;
  - `selftest slow` (3 s);
  - `selftest echo`.
- `holdPingInterval` is 1 s.
- Stdout: `held=<n> active=<n>` on every pool change, and `closed <eof|extra|ping|limit|server|pid>` per hold.
- It exits on SIGTERM or after 120 s.

```swift
// Core/ControlServer.swift (A)
func start(socketPath override: String? = nil)        // non-nil only from SelfTest in token mode
var holdPingInterval: TimeInterval = TimeInterval(KitControl.holdPingSeconds)   // 300; SelfTest sets 1
/// Held-connection writes (security L5): ONE non-blocking attempt (`send(fd, …, MSG_DONTWAIT)`; EINTR retried once).
/// Returns false on EAGAIN, a short write or an error; the caller then closes that hold. Never polls, never blocks
/// the listener queue. `sendOnce` stays for ordinary replies.
static func sendHeld(_ fd: Int32, _ response: ControlResponse) -> Bool
// Core/ControlCommandRegistry.swift (A): the new dispatch signature (code m5)
func dispatch(_ request: ControlRequest, peer: ControlPeer, hold: ControlHold,
              skipConfirmationAllowed: Bool) async -> ControlResponse
```

**Client path override.** `CLIClient` (A) connects to `SNAPTIC_SELFTEST_SOCKET` only when two conditions hold: `SNAPTIC_SELFTEST_TOKEN` is set, and it equals the contents of `SNAPTIC_SELFTEST_TOKEN_FILE`. This grants nothing, because a client choosing which socket to connect to has no capability; the gate keeps the override out of normal use.

**`scripts/selftest-control-server.sh <Snaptic executable>`** (lead) drives real `snaptic` clients, with `python3` for the raw-socket cases. It checks these cases:
1. One hold, then 4 `selftest slow` requests are accepted and a 5th gets "busy".
2. 8 holds; the 9th is refused with exit 4, `held=8` stays, and `closed limit` is logged.
3. `kill -9` of a holding client → `closed eof` within 1 s, and `held` decrements exactly once.
4. A client writes its request and closes before accept → no held leak.
5. `( snaptic … selftest hold & sleep 30 & )`: the fd is inherited by `sleep`. Killing the client gives `closed pid` and the server-side close, even though the fd stays open in `sleep`.
6. An extra byte after the request, including in the same first chunk → `closed extra`.
7. Ping lines arrive every 1 s and never reach the client's stdout.
8. A python client that never reads (small `SO_RCVBUF`) → `closed ping` once its buffer fills. Meanwhile a `selftest echo` is answered in < 100 ms (L5).
9. An idle hold stays open for 5 s, so there is no read timeout.

A step-1 `build.yml` macOS step runs the script after the helper self-test; its output goes to `selftest.log`, which `ci-annotate.sh` annotates. The lead lands the script and the CI step in A's step-1 merge. A's step-1 exit requires the script to be green, and it replaces "passes the §2.10 connection tests".

**Edge rules (code m5):**
- A `holding` reply while `held == 8` becomes the refusal **and** closes that connection's `ControlHold`. `onClose` fires, so SessionController ends the hold it just added (`.processExited`, no history entry, because it never held).
- For a connection whose reply is `holding`, any byte after the request's newline counts as "a byte after the request", including bytes in the same first read chunk.
- Pings and the final line use `sendHeld`.

### R5-6 Battery "falling" uses a time window (security M1; lead guidance)

```swift
// SnapticKit/AwakeGuards.swift: PowerMath (J), PowerFacts (G)
package struct BatteryReading: Equatable, Sendable {
    package var percent: Int; package var charging: Bool
    package var currentMilliamps: Int?          // IOPS kIOPSCurrentKey ("Current"), signed; < 0 = battery discharging
    package var at: Double                      // continuous clock
    package init(percent: Int, charging: Bool, currentMilliamps: Int?, at: Double)
}
package enum PowerMath {
    package static let fallingWindowSeconds: Double = 600
    /// Appends `r`, drops readings older than the window but keeps the newest older one as a baseline; ≤ 64 entries.
    /// In memory only (PowerMonitor), never persisted.
    package static func appending(_ r: BatteryReading, to history: [BatteryReading]) -> [BatteryReading]
    /// True iff some event inside the window (a percent decrease between two readings, or currentMilliamps < 0) has
    /// no later reading with `charging == true` or a higher percent. Equal consecutive readings never clear it.
    package static func falling(_ history: [BatteryReading], now: Double) -> Bool
    /// Continuous instant of the newest reading with `charging == true` or a percent rise; nil if none.
    package static func lastRecovery(_ history: [BatteryReading]) -> Double?
}
// PowerFacts gains `package var lastRecovery: Double?` (from PowerMath.lastRecovery); its init becomes
//   init(batteryPresent: Bool, onAC: Bool, percent: Int?, charging: Bool, falling: Bool, lastRecovery: Double?,
//        lowPowerMode: Bool, thermal: ThermalLevel)
// r4's `PowerMath.falling(previous:now:)` is gone.
```

Rules:
- PowerMonitor recomputes `falling` on every IOPS notification. While `falling` is true it also recomputes on a 60 s `.common`-mode timer, so the flag ages out.
- **The `holding` clear rule changes.** A battery `holding` clears only when `percent ≥ floor + 5`, or when `lastRecovery > heldSince` (a rise, or charging reported). It never clears on "AC and not falling", and never on one equal reading. This supersedes §2.6.
- Kit tests:
  - On AC, readings 5, 4, 4, 4 one minute apart stay `discharging` and keep the hold.
  - 4 followed by a `charging` reading clears both.
  - Equal readings for 11 minutes age `falling` out, but the hold stays until a recovery.
  - On AC with equal percents, `currentMilliamps < 0` sets `falling`.

### R5-7 The activity cap is per session chain (security L1; lead guidance)

`AwakeActivityGate.Event` changes:

```swift
case ended                          // the manual session ended: (false, notAllowed); activitySince and lastEnded kept
case governingEnded(now: Double)    // emitted by arbitrate() on EVERY active → inactive transition of governing,
                                    // whatever the source (manual, rule, holds): lastEnded = now
case nothingGoverned(now: Double)   // every arbitration with nothing governing: lastEnded == nil → lastEnded = now;
                                    // else now − lastEnded ≥ 900 → activitySince = nil
// r4's `ended(now:)` is replaced by `ended` + `governingEnded(now:)`.
```

What this means for hand-offs:
- A hand-off between rules, or between manual, rule and holds, that never passes through "inactive" emits no event, so the cap carries.
- A gap shorter than 15 min carries too.
- Only ≥ 900 s with nothing governing resets `activitySince`. So does `uiStart` / `confirmAllowed`, as before.

Kit tests:
- Rule A ends and rule B starts 1 s later: the cap carries.
- A → B with no inactive turn: the cap carries.
- 15 min with nothing governing resets the cap.
- Launch with nothing governing sets `lastEnded` without resetting the cap.

### R5-8 Focus safety covers keystrokes (security L4)

`SettingsShell` (H) gains `@Published private(set) var externalOpenPending = false` and `func mayStart() -> Bool`.
- `externalOpenPending` is set by every externally requested open (reopen from Dock or Finder, the `open-settings` verb).
- It is cleared by the first `.leftMouseDown` inside the Settings window (a local event monitor), or by an open from Snaptic's own menu or hotkey.
- `mayStart()` returns false while the 1 s guard runs. It also returns false while `externalOpenPending` is set and `NSApp.currentEvent?.type == .keyDown`.

Every session-start handler in Settings checks `mayStart()`. These are the Keep Awake button and its pull-down items (R5-9), Replace With, Start Again, and the guard toast's re-start. When `mayStart()` is false, the handler only keeps focus. VoiceOver and AX presses carry no keyDown, so they act.

### R5-9 Settings fallback starts any session (product M1)

The status row's idle **Keep Awake** becomes a pull-down with a primary action: SwiftUI `Menu(content:label:primaryAction:)`, as in Mail's toolbar.
- A **click** starts the default preset.
- **▾** lists the presets in order (their non-verb titles: "Until Turned Off", "For 1 Hour", …), then ─, then **While an App Is Running ▸** (a nested Menu of running regular apps, recent first, ≤ 12), then **Custom…**.

While active, **Options ▾** gains **Replace With ▸**, the same list; choosing an item replaces the session.
- Every item is a `.uiStart` and goes through `mayStart()` (R5-8).
- The status-action budget is unchanged: status actions are not counted (§4.2).
- Control ids: `awake.page.status.keepAwake` (primary), `awake.page.status.keepAwakeMenu` (`perItem("preset")`), `awake.page.status.replaceWith`. All go in `AwakePageControls` with `.statusAction`.

HW-14 adds a check (R5): with the Snaptic and Awake items hidden, start For 2 Hours, a While an App Is Running session and Until Downloads and Tasks Finish, all from Settings only. §5.5's "every function reachable from Settings" now holds.

### R5-10 Turn Off, holds and their toasts (product m1 + m3, consistency m10)

**Hold end conditions (§2.10)** add a user Turn Off while the hold stack governs: the switch header, Turn Off Keep Awake, the status-row Turn Off, or `awake.toggle`. Each client gets "Awake hold ended in Snaptic." and exits 0. When another source governs, Turn Off ends that source and leaves the holds running.

**Holds-only state.**
- The menus show **Turn Off Keep Awake** only, with no End Command-Line Holds.
- The status row shows "Held by Terminal (2)" + **Turn Off**.
- **End Command-Line Holds** appears only while holds exist under another governing source: in the active group of the Awake menu and the compact section, and in the status row's Options ▾.
- One name everywhere: r4's "End Holds" is retired.

**Turn Off toasts.**
- A rule now governs: "Rules can still keep your Mac awake." **[Turn Off “Desk dock”]** (default, `isDefault: true`; `TriggerController.manualEnd` of the rule that now governs, which respects its "After I turn it off") and **[Pause Rules]** (1 hour).
- Only holds remain: "Terminal is still keeping your Mac awake." **[End Command-Line Holds]**.
- Nothing remains: no toast.

**Start Anyway** is "never offered as a menu item": a refused menu start shows the toast that carries the button (consistency m10).

### R5-11 Defaults, display switch, paused state, Customize sheet (product m2, m4, m6, m7)

**Default preset order (m2):** Until Turned Off, 30 min, 1 h, 2 h, 5 h, Until Downloads and Tasks Finish. The derived ids are unchanged.

**Paused status row (m4).**
- The primary line follows the session, or reads "Your Mac can sleep as usual." when idle.
- "Rules are paused until 4:00 PM." becomes a detail line, and **Resume** replaces Pause Rules ▾ in the same slot.
- In the menus, Rules ›'s subtitle reads "Paused until 4:00 PM" whatever runs; the header detail follows the session.

**"Keep the display on" applies to every session that uses default options (m6, second option).**
- `effectiveOptions(for:preset:effective:)` = `(preset?.options ?? defaultOptions)`, then clamped as before.
- The per-kind `maySleep` default for whileApp and untilIdle is gone. `defaultDisplayPolicy(for:)` returns `defaultOptions.display` for every kind, and is kept for the "Default (…)" label.
- The help text keeps only "When off, your Mac stays awake but the display can turn off."
- OQ-2 is closed.

**Customize Displays Menu (m7).** Independent disclosure groups, no accordion: Per Display is expanded by default and the others collapsed. The filter expands every group that has a match. The `List` counts as 1 (§4.2), so the sheet is within ≤ 25.

### R5-12 0.2 sleep-prevention regressions (product m5)

**CLI.** `KitControl.retiredVerbs: [String: String]` (A) = `["prevent-sleep": "Moved to Awake: use “snaptic awake …”."]`.
- `ControlCommandRegistry.dispatch` answers a retired verb before lookup, with exit 2 and that text, whatever modules run.
- Help doesn't list it.
- A adds it in the step-3 coordinated merge that removes D's verb. It is removed in 0.4.

**Hotkey, as part of M1.** M1 checks whether raw `keys.shortcuts["d.sleepPreventionToggle"]` holds a combo:
- **M1 produced ≥ 1 rule and `awake.pauseAutomatic` is unbound:** the combo is bound there.
- **Otherwise:** it is dropped, with the Recent Notice "Your display sleep shortcut was removed. Set Awake shortcuts in Settings › Awake › Keyboard Shortcuts."
- Either way, the 0.2 entry stays in `keys.shortcuts` so a 0.2 downgrade still reads it.

```swift
package struct AwakeMigrationResult: Equatable, Sendable {
    package var triggers: [AwakeTrigger]
    package var enableModule: Bool
    package var migratedDisplayNames: [String]
    package var pauseRulesShortcut: HotkeyCombo?      // R5: bind to awake.pauseAutomatic
    package var droppedShortcut: Bool                 // R5: a 0.2 combo existed and was not moved → Recent Notice
    package init(triggers: [AwakeTrigger], enableModule: Bool, migratedDisplayNames: [String],
                 pauseRulesShortcut: HotkeyCombo? = nil, droppedShortcut: Bool = false)
    package static let nothing: AwakeMigrationResult
        = AwakeMigrationResult(triggers: [], enableModule: false, migratedDisplayNames: [])
}
package enum AwakeMigration {
    package static func fromDisplays(rawJSON: Data?, modulesEnabled: Set<ModuleID>,
                                     awakeShortcuts: LossyMap<AwakeActionID, HotkeyCombo>) -> AwakeMigrationResult
}
```

### R5-13 Control registry details (code S3, m1, m2, m3; consistency m5, m7)

**`ControlLegacy.switcherKeyPaths` (S3)** becomes `[String: [LegacyControlID]]`. `disabledFeatures` maps to all 14 `l.sw.feature.*` ids.

**Search entries are derived from specs (consistency m5).** This removes the shared index files.

```swift
// SnapticKit/Controls/ControlRegistry.swift (lead)
package struct SearchSpec: Hashable, Sendable {
    package let title: String; package let keywords: [String]
    package let root: String; package let route: SettingsRoute?; package let sheet: String?
    package init(_ title: String, keywords: [String] = [], root: String, route: SettingsRoute? = nil, sheet: String? = nil)
}
// ControlSpec gains `package let search: SearchSpec?`, init parameter `search: SearchSpec? = nil` after `menu:`.
// SnapticKit/SettingsIndex.swift (H)
extension SettingsSearchEntry { package init(_ spec: ControlSpec, search: SearchSpec) }   // id == anchor == spec.id.rawValue
package enum SettingsIndex {
    package static func entries(_ tables: [any ControlTable.Type], root: String) -> [SettingsSearchEntry]
}
```

- Each module's `settingsIndex()` returns `SettingsIndex.entries(ControlRegistry.tables, root: <its root id>)`.
- `SettingsIndexAwake`, `SettingsIndexGeneral`, `SettingsIndexSwitcher`, `SettingsIndexDisplays` and `SettingsIndexMenuBar` are **not created**, and stub kind K20 is unused.
- Test 3 becomes: every `setting` spec has `search != nil`, and entry ids are unique.

**Attach points (code m1).** These types gain `control: ControlID? = nil` as their last stored property or init parameter:
- `ActionMenuItem`, `StatusAction`, `NavigationRow`, `ButtonRow`, `SettingsPageHeader`;
- `PageFooterButtons` (`advancedControl:`, `restoreControl:`);
- `MenuKit.header`, `MenuKit.status`, `MenuKit.device`, `MenuKit.settings`, `MenuKit.quit`, `MenuKit.alternate`.

**L15 parsing rules (code m1):**
- A table id is the first argument of `ControlSpec(…)`, written as one plain `"…"` literal: no interpolation, concatenation or constants.
- The python lint strips `//` and `/* */` comments and string escapes before matching.
- A file may contain several `typealias Controls = X` only if they all name the same `X`; every literal in the file is checked against that table.

**Missing builder tables (code m2).**
- New tables `OverviewMenuItems` (F, `menu.display.f`, new file `Displays/UI/OverviewMenuItems.swift`), `AutomationMenuItems` (A, `menu.display.a`, new file `Displays/UI/AutomationMenuItems.swift`) and `ManagementMenuItems` (D, `menu.display.dm`, new file `Displays/UI/ManagementMenuItems.swift`).
- In step 2, D's Arrangement, PanelProps, Power, Protection and SmartHiDPI controllers move their menu items into `ManagementMenuItems`. C's Color, MenuBarOverlays, Sync, SystemColors and XDR controllers move theirs into `ColorMenuItems`.
- Test 6 no longer freezes a list. L15 checks that every `ControlTable` conformer is registered.
- An owner adds a table in its own merge with a `stubs.tsv` row for its file and one appended line in `ControlRegistry.tables`. TEAMS.md allows these append-only lines.

**Test timing (code m3).**
- From step 1, run tests 2 and 3, "every `replaces`/removal id ∈ `ControlLegacy.ids`" and `parentOn`, per table.
- Totality (test 1's "every legacy id has a home") and the key cross-check (test 5) stay skipped until the step-3 exit.

**Mirror walker (code m3).**
- Path segments are Swift stored-property names, not CodingKeys.
- `LossyMap` walks only `values` (its private `unknown` is skipped).
- `Dictionary`, `Array`, `Set` and `LossyArray` become `*`.
- `Optional` is unwrapped.
- An enum with a payload contributes its case name, then the payload labels: `kind.duration.seconds`.

**Moved checks (consistency m7, code m3).**
- "All 46 `DisplayMenuItemID`s present" moves into `--selftest-controls`, which can see the app-side ids.
- `statusJSON` is tested with `"pids"`.
- Assertion-hold backoff gets a Kit API: `AwakeGuards.assertionBackoffSeconds(failures: Int) -> Double` (1 → 30, 2 → 120, ≥ 3 → 600), `GuardMemory.recordingAssertionFailure(now: Double) -> GuardMemory` and `GuardMemory.clearingAssertionHold() -> GuardMemory`.

### R5-14 Files, sources, wording (code m6, consistency m1, m3, m4, m6, m8, m9, m10)

**One file per type (consistency m1, code m6).**

| Type | File |
|---|---|
| `LossyArray`, `lossyArray`, `lossyUniqueArray`, `uniquedByID`, `uniqued` | `KitLossy.swift` (⇢ lead, with `KitLossyTests.swift`) |
| `NameHash`, `StableID.derived` | `KitModules.swift`, beside `StableID` |
| `ControlID` | `Controls/ControlRegistry.swift` |
| `ControlServer`'s new types | not lead stubs; A writes them in step 1 (nothing calls them before step 2) |

**Store owner (consistency m3).** `ModuleHost` owns the three Awake stores; the §2.1 diagram is corrected (R5).

**Sources (consistency m4).** `AwakeSessionSource` gains `case rule` for history and policy only:
- A trigger session records `.rule`; a hold records `.commandLine`.
- `AwakeSession.sanitized(now:)` drops a manual session whose source is `.rule`.
- `isDirectUserAction` and `offersStartAgain` are false for `.rule`.
- `DriveAlivePolicy.shouldWrite(sessionSource:)` gets `.rule` for a trigger session, `.commandLine` for the holds-only state and nil when nothing governs.

**`AwakeTextContext` (consistency m6),** G, in `AwakeClock.swift`:

```swift
package struct AwakeTextContext: Equatable, Sendable {
    package var uses24Hour: Bool; package var decimalSeparator: String     // from the system locale, once (N12)
    package init(uses24Hour: Bool, decimalSeparator: String)
}
```

**Protected words (consistency m8).** Step 1 **adds** the Awake words to `KitControl.protectedSettings`. The step-3 coordinated merge **removes** `"sleepprevention"` and `"preventsleep"`.

**Undefined states (consistency m9).**
- (a) When `commandLine` stops being effective, or the host CLI is turned off, SessionController ends every hold of both forms with the new reason `AwakeEndReason.commandLineOff`; connection clients get "Command-line control was turned off." and exit 0. `process` is then no longer needed and deactivates. §2.1 step 6 is replaced by this rule (R5). `ProcessWatch.deactivate` running handlers stays as a defensive path only.
- (b) `indicator` joins `AwakeFeatureGraph.unkillable`, so N11 always holds.

**Wording (consistency m10).**
- N4: every Settings slider has a typed field and a reset glyph, except live hardware values with no default (live Brightness).
- The §4.1 anchor example becomes `ControlID("awake.page.batteryFloor")`.
- §2.13 cites `ConfigModulesTests` line 16 only.
- The holds and Start Anyway wording is as in R5-10.

**L16 (code m6)** applies only under `Sources/Snaptic/`; Kit and its tests construct `AwakeActivityGate` freely.

### R5 traceability

| Review | Finding | Resolution |
|---|---|---|
| product | M1 Settings fallback | R5-9 |
| product | m1 holds vs Turn Off | R5-10 (§2.10 end condition; holds-only shows Turn Off only) |
| product | m2 preset order | R5-11 |
| product | m3 toast action | R5-10 (Turn Off “Desk dock” default, Pause Rules second) |
| product | m4 paused precedence | R5-11 |
| product | m5 0.2 regressions | R5-12 |
| product | m6 Keep the display on | R5-11 (second option: follows the switch for every kind) |
| product | m7 accordion | R5-11 |
| security | M1 falling flaps | R5-6 (window + signed current; recovery-only clear) |
| security | L1 cap chains | R5-7 |
| security | L2 clickjacking | R5-1 (300 ms arm, overlap refusal, session-bound lifetime); **partly**: 300 ms instead of 0.5–1 s (lead: still longer than any reaction to a decoy redraw, and less obstructive) |
| security | L3 duplicate ids | R5-3 |
| security | L4 keystrokes | R5-8 |
| security | L5 `sendOnce` for holds | R5-5 `sendHeld` + self-test case 8 |
| security | L6 toast fail-closed | R5-1 |
| code | S1 `ToastAction` | R5-1 |
| code | S2 snapshot/history/sessions decoders | R5-3 |
| code | S3 `switcherKeyPaths` | R5-13 |
| code | S4 start time units | R5-4 |
| code | M1 serial builds | R5-4 (child CPU time + minimum hold) |
| code | M2 connection-test harness | R5-5 |
| code | m1 attach points, L15 rules | R5-13 |
| code | m2 builder tables | R5-13 |
| code | m3 test timing, walker, 46 ids | R5-13 |
| code | m4 toast dismissal | R5-1 |
| code | m5 hold edge rules, dispatch signature | R5-5 |
| code | m6 doc conflicts | R5-14 |
| consistency | M1 `ToastAction` | R5-1 |
| consistency | M2 migration ledger | R5-2 |
| consistency | m1 file ownership | R5-14 |
| consistency | m2 leftover `migrations` | R5-2 |
| consistency | m3 store owner | R5-14 |
| consistency | m4 trigger/hold source | R5-14 (`.rule`) |
| consistency | m5 search-index owners | R5-13 (derived from specs) |
| consistency | m6 `AwakeTextContext` | R5-14 |
| consistency | m7 tests without Kit API | R5-13 |
| consistency | m8 protected words timing | R5-14 |
| consistency | m9 undefined states | R5-14 (`.commandLineOff`; `indicator` unkillable) |
| consistency | m10 wording drift | R5-10, R5-14 |

Inputs: `docs/design/0.3/{awake-parity.md, power-apis.md, ui-audit.md, design-spec.md}` (cited as [AP], [PA], [UA], [DS] with section numbers).

## r4 changes

Resolves review round 3 (`review-r3-{product,security,code,consistency}.md`) and applies the lead's r4 decisions. Totals: **product** 5 M + 16 m resolved (M3 and M4 through lead decisions instead of the proposed mechanisms), 0 rejected; **security** 3 M + 8 L resolved, 0 rejected; **code** 9 signature rows + 1 B + 6 M + 14 m resolved (M2 partly rejected: the "sum of processes" comparison), B1's rendering fix replaced by lead-8; **consistency** 5 M + 16 m resolved, 0 rejected.

**Lead decisions (normative)**

| Id | Resolution | Sections |
|---|---|---|
| lead-8 control coverage | Static per-surface `ControlTable`s (ids, availability as data, `replaces:`), one lead `ControlRegistry`; Kit test against the **literal** frozen 0.2 list (588 ids) and a removals table; lint L15 pairs literals with tables both ways; no render walk, no DEBUG gate, step-3 manual gate dropped; `ControlCoverage`, `ControlMap`/`ControlCatalog`/`MenuItemCatalog`, `gen-controlmap.py` never created | N16, §4.8, §4.8.1, §4.8.2, §6.2–§6.6 |
| lead-9 hotkey pointer movement | Hotkey starts need "Move the pointer to keep apps active?" Allow / Not Now (0.2 R5.7); `AwakeActivityGate` (Kit, runtime only) defines who sets and clears `uiStartedInProcess`: only menu/Settings handlers and Allow set it; restore, resume, CLI/trigger takeover, replacement, module stop clear it | N10, §2.3, §2.5, §2.9, §3.2, HW-19 |
| lead-10 battery floor | `discharging = batteryPresent ∧ (¬onAC ∨ falling)`; `batteryPresent` latched; unreadable laptop battery → activity and Drive Alive stop (as at 0%), session assertion kept, toast; `batteryUnreadable` end removed | N10, §1.1, §2.6, §3.2, HW-13 |
| lead-11 lossy collections | `LossyArray` (Codable, mirrors `LossyMap`) for rules, criteria, presets, history, holds; hand-written element decoders; `StableID.derived` (Kit FNV-1a-128, name-based UUID) for M1 and default presets | N18, §2.7, §2.14, §4.6, §6.6 |
| lead-12 process CPU | `proc_pid_rusage` user+system deltas × `mach_timebase_info` for every pid every 5 s; short-lived processes via aggregate CPU + new-process churn (`newProcesses`, default 3) | N9, §2.3, §2.8, §3.6, HW-23, OQ-8 |
| lead-13 restore order | Snapshot sanitized → dynamic needs seeded → services activated → `restore` → arbitrate; re-apply if needs changed; `process` deactivation ends holds | §2.1, §2.5, §2.14 |
| lead-14 ControlServer holds | Own held-slot pool (8), never counts against the 4 request slots, ping every 300 s, EOF/extra-byte close, no read timeout after the handshake; A implements, step 1 | §2.10, §6.2, §6.4 |
| lead-15 product majors | First-level item "Keep Awake Until Turned Off" (default preset as verb, idle only), ✓ only on the running session; Pause Rules wherever rules exist (Rules › in both menus, status row Pause Rules ▾); Turn Off while a rule or holds remain → toast with Pause Rules / End Holds; holds stack beside UI sessions ("Held by Terminal (2)"); Customize Displays Menu in disclosure groups, ≤ 25 controls visible | N3, N17, §2.5, §2.10, §4.3, §5.2–§5.4 |

**Product (review-r3-product)**

| Finding | Resolution | Sections |
|---|---|---|
| M1 | lead-15: default preset as a verb phrase (`verbTitle`), idle only, Until Turned Off back in Start Session ›, ✓ = running only; idle 6 / active 9 rows; mockups drawn per state | §2.14, §5.2, §5.3, §5.4 |
| M2 | lead-15: Rules › in the compact section whenever a rule exists; status row Pause Rules ▾; "Rules are reached from…" sentence dropped | §1.1, §4.3, §4.4 #17, §5.3, §5.4 |
| M3 | lead-15 (toast instead of ending every rule): Turn Off ends what governs, then "Rules can still keep your Mac awake." [Pause Rules] / holds toast; detail "Then “Desk dock” keeps it awake." | §2.5, §4.3, §5.3 |
| M4 | lead-15/N17 (stacking instead of a standby slot): holds never refused for a UI session, ≤ 8 | N1, N17, §2.3, §2.5, §2.10, §3.1 |
| M5 | lead-15: disclosure-group accordion, filter, three-way only for per-display items, collapsed "items need features that are off" row; §4.8 rows corrected | §4.3, §4.8 |
| m1 | No ↺ at the default | §4.3 |
| m2 | Compact section drawn idle and active, no internal separators | §5.2, §5.4 |
| m3 | ⌥ "End “Desk dock” Session" (manualEnd) | §5.3 |
| m4 | No idle "Off" detail | §5.3 |
| m5 | Rule editor: one focused condition row, optional name with summary placeholder, "Keep your Mac awake while…", no is/is not for Power | §4.3 |
| m6 | "Default session", "Sessions in the menu", "Sessions" sheet | §2.14, §4.3 |
| m7 | Plain Keep Display On / Let Display Sleep button when Options ▾ would hold one item | §4.3 |
| m8 | Copy Install Command subordinate, with help | §4.3 |
| m9 | "When your Mac sleeps" help | §4.3 |
| m10 | Concrete modes; Larger Text / More Space as subtitles on the extremes | §5.2 |
| m11 | Display Details… under the tiles; Display Information last | §4.3 |
| m12 | `AwakeIndicatorStyle` comment says Time | §2.14 |
| m13 | "Restore <scope> Defaults…" titles | §4.1, §4.3, §4.6 |
| m14 | ⌘F / Edit › Find focus sidebar search | §4.2 |
| m15 | untilIdle detail "Ends after 5 min with no activity · quiet for 2 min" (`TaskQuiet.quietFor`) | §2.3, §2.5, §4.3, §5.3 |
| m16 | Show When Active help per module; `--display-may-sleep`; Snaptic menu row budget + HW-15 | §2.10, §4.3, §5.2, HW-15 |

**Security (review-r3-security)**

| Finding | Resolution | Sections |
|---|---|---|
| M1 | lead-9 (Allow / Not Now wording); first-nudge "Awake is moving the pointer slightly." [Stop] for UI starts; hotkey row in §3.2; HW-19 | N10, §2.5, §3.2, HW-19 |
| M2 | `AwakeActivityGate` truth table (Kit, tested, every `.unchanged` event listed); fields moved out of `AwakeSession`; lint L16 | §2.3, §2.5, §6.3, §6.6 |
| M3 | lead-10; Kit tests "AC but falling" and "entry missing after latch" | §2.6, §3.2, §6.6, HW-13 |
| L1 | Peer pid comment "best effort, not identity"; refuse when ProcessWatch can't arm; tests for exit-before-accept, inherited fd, no half-close (L16) | §2.3, §2.5, §2.10, §6.3 |
| L2 | lead-14 slot rules, extra byte ends the hold, `assert(active >= 0)`, `onClose` once on main | §2.10 |
| L3 | Bounds from Snaptic's clock (`startedContinuous ≤ now`, deadline ≤ start + cap, cap/deadline consistent) | §2.3, §2.14 |
| L4 | SessionController never reads the store after restore, writes whole snapshots; test | §2.5, §3.2 |
| L5 | Cap carried across back-to-back sessions, reset after 15 min with nothing governing; relaunch case stated as a UX bound | §2.3, §2.9, §3.3 |
| L6 | Privacy wording: history is a local timeline; salted hashes protect exports, not local readers | §3.6 |
| L7 | Named fields instead of "protected"; `KitBackup.removedPaths` entries | §2.2, §2.14, §3.2, §3.6 |
| L8 | No Return/default binding on start controls; 1 s ignore after an external `openSettings` | §2.5, §3.2, §4.3 |

**Code (review-r3-code)**

| Finding | Resolution | Sections |
|---|---|---|
| sig StableID "m1."+SHA | `StableID.derived` (FNV-1a-128 name-based UUID) | §2.14, §4.6 |
| sig all-or-nothing arrays | Hand-written element decoders + `LossyArray` | §2.7, §2.14 |
| sig ControlResponse | Hand-written Codable, `init(…, holding: Bool = false)`, `jsonReply` keeps it | §2.10 |
| sig AwakeHost.init | `ModuleContext` gains `requestStatusPlan`, `setPresence(ModuleID, MenuPresence)`, `hostSignals` | §2.11, §6.2 |
| sig settingsAnchor | `struct SettingsAnchor: ViewModifier` | §4.1 |
| sig M10 names | `menu.items[.dDisconnectItem]`, Kit `DisplayMenuItemID.cDDCPower` | §2.2, §4.6 |
| sig MenuSliderRow | `required init(coder:)`, no trap | §5.1 |
| sig legacy AwakeActionIDs | Gone (literal list has no Awake ids) | §4.8.1 |
| sig ControlListener.Handler | Listener always creates a `ControlHold`; dispatch exposes it only for `holds: true` | §2.10 |
| B1 | lead-8 (static declarations instead of the proposed CI render walk) | §4.8, §6.4, §6.5 |
| M1 | lead-13 | §2.1, §2.5 |
| M2 | lead-12; first-seen whole CPU time, pid+start time identity; **partly rejected**: "compare the sum of same-user processes" (idle background apps add up; churn + aggregate CPU cover short builds; OQ-8) | §2.8, OQ-8 |
| M3 | lead-14 plus every listed rule (slots once, ordering, early close, EOF branch, client remainder/fflush/exit 5, lifetime end, `SNProcess.startTime`) | §2.10 |
| M4 | Literal list (no generator), Mirror key cross-check over `ConfigFixtures`, in-process `--selftest-controls` | §4.8, §4.8.1 |
| M5 | Deterministic ids, replace-by-id writer, two-run test | §4.6, §6.6 |
| M6 | lead-11 | §2.7, §2.14 |
| m1 | = sig AwakeHost | §2.11 |
| m2 | = sig settingsAnchor | §4.1 |
| m3 | L5 in python | §6.3 |
| m4 | L14 allows `RunLoop.main.perform(inModes: [.default])` | §6.3 |
| m5 | = sig M10 | §4.6 |
| m6 | Per-driver disk deltas by registry entry id; HW-23 reworded | §2.8, HW-23 |
| m7 | Test files move with sources; step-0 stubs for `Fingerprint.matches`, `ToastPresenter` actions; CI step in step 1 | §6.2, §6.4 |
| m8 | = sig ControlResponse | §2.10 |
| m9 | Item kept while its menu is open, removed via `menuDidClose` → `applyStatusItem` | §5.3 |
| m10 | `state.value` assigned from memory only | §2.5 |
| m11 | Counters in `EventLog.shared.awakeCounts` | §3.6 |
| m12 | `ControlID == SettingsSearchEntry.id == anchor` (test) | §4.1, §4.8 |
| m13 | `MigrationLedger` in `SnapticMigrationsV1` | §2.14, §4.6 |
| m14 | DisplaysPageEnvironment wording | §6.2 |

**Consistency (review-r3-consistency)**

| Finding | Resolution | Sections |
|---|---|---|
| M1 | `menu.items`, `.disconnect`, Kit `cDDCPower` (C uses it) | §2.2, §4.6, §6.2 |
| M2 | `NewModuleCard` enum, lossy decode | §2.2, §4.6, §6.6 |
| M3 | CLI nudge refusal dropped; runtime gate only | §2.3, §2.10, §3.1 |
| M4 | `ActivityPolicy.nudgeAllowed(governing:gate:…)` in Kit | §2.9, §6.6 |
| M5 | `schedule` needs no service (`source(for:)` optional); `TaskSessionMonitor` dropped | §1.1, §2.1, §2.11, §6.2 |
| m1 | "persisted manual session" | §2.12 |
| m2 | "17 duplicates (14 + 3)" | §0 |
| m3 | `AwakeHistoryEntry.source`, `offersStartAgain` | §1.1, §2.14, §4.3 |
| m4 | §3.6 lists hold pids | §3.6 |
| m5 | Time / Style / Customize Displays Menu… / `EventLog.shared.record` / actual hold cap | §2.1, §2.10, §2.14, §4.8 |
| m6 | `ModulesConfig.firstRun(launchedBefore:)` | §2.13 |
| m7 | `sharedShownAtRest: true` | §5.2 |
| m8 | No ✓ on an idle default | §5.3 |
| m9 | `TaskActivitySample` declared by G | §2.3 |
| m10 | S rule covers §4.6 and §4.8; `ToastAction` declared; `SettingsIndex*.actions` superseded by control tables | §2.5, §6.3 |
| m11 | One owner each: test files, MenuPlacement titles, DisplaysOnboardingStep (F), per-owner control tables, stores (ModuleHost) | §2.11, §4.7, §4.8.2, §6.2 |
| m12 | Rules: Activity Off / Appear active only; every trigger nudge → declare | §2.7, §4.3 |
| m13 | J `OtherAssertionsReader` (step 2), A `protectedSettings` and F `OverviewController` (step 1), CI step in step 1 | §6.4 |
| m14 | = code sig legacy AwakeActionIDs | §4.8.1 |
| m15 | Tests named against Kit APIs; `AwakeRefusal`, `AwakeLogEvent` entries | §6.6 |
| m16 | "r1 security L6" citations; TEAMS.md contract list; `AwakeDiagnostics` wiring | §2.14, §3.2, §3.6, §6.3 |

## r3 changes (shortened; the full table is in `PLAN-r3.md`)

Resolved review round 2 (`review-r2-{parity,security,code,design,consistency}.md`): parity 1 B + 6 M + 12 m; security 1 H + 5 M + 5 L (M4, M5 partly rejected; L6 moot); code 12 signature rows + 11 M + 13 m; design 7 M + 14 m (m2, m13 partly rejected); consistency 1 B + 7 M + 14 m. Lead decisions lead-1…lead-7: consent record withdrawn (N10: pointer movement only for UI-started sessions, Snaptic-clock cap, fixed 5% floor); hidden kill switches instead of managed preferences (N14); `awake hold` with server-side peer and `--pid` (N1, §2.10); `untilIdle` busy signals (N9); `.common` run-loop mode (N15); one `AwakeMenuRows` (§5.3); every 0.2 menu item mapped (N16, §4.8). Still in force from r3: `MenuPresence` in KitModules and `StatusItemPlan` in ConfigModules (lead), `sanitized(now:)` + `restore(_:)`, snapshot `bootSession`, absolute assertion deadlines with `max(1, ceil(…))`, migration markers, Control Center presence wording, the Awake page and Display mockups (as amended in r4). **Superseded in r4**: the DEBUG `ControlCoverage` walk and the step-3 coverage gate (lead-8), `gen-controlmap.py` (lead-8), "a hold never coexists with a UI session" and `maxHeldConnections = 1` (lead-14, lead-15), the "two unreadable reads end the session" rule (lead-10), "Until Turned Off" as a first-level item (lead-15), r3's CLI nudge refusal (consistency M3).

## r2 changes (shortened; the full table is in `PLAN-r2.md`)

Resolved review round 1 (`review-r1-{parity,security,code,design}.md`): parity 2 B + 7 M + 14 m + 3 extra notes; security 2 H + 7 M + 6 L; code 3 B + 14 M + 13 m (1 m partly rejected: persisting "Start Anyway"); design 2 B + 10 M + 9 m (1 M partly rejected: `DateComponentsFormatter` in Kit). Main r2 results still in force: task kinds (`untilIdle`, CLI hold) and the 1 h CLI default; the §4.8 control map; `MenuPresence` as the only icon control; native "Turn Off Keep Awake"; per-session display policy defaults; guards unkillable, critical heat evaluated directly, `allowsBackgroundWork`; session-dictionary truth instead of notifications; verified-dirfd Drive Alive writes; closed `AwakeLogEvent`; typed export/import; lint ratchet; one coordinated `sleepPrevention` removal; `StatusItemProvider`; absolute assertion deadlines; in-memory hysteresis; migration markers; upgrader insertion; `queue: .main` observers; multicast sources; N12 hand formatting; per-id `ControllerRevision`, `ConfigSlice`, `DisplayLiveControlling`; step-0 feasibility; budgets; AppKit-only menu rows. **Superseded in r3**: the Keychain consent record and `ConfigStore` admission (security H1/H2, code M5 rows; now N10 and §3.2), "Own Icon When Active" wording (now Show When Active), `whilePID`/`--parent` (now `hold`), the 13/16-row Awake menu (now §5.3), and the managed-preference kill-switch reading (now N14).

---

## 0. Summary and decisions

Snaptic 0.3 does three things:

1. **Awake** (new module, `ModuleID.awake`): a free, MIT, public-API-only replacement for Amphetamine and Insomnia. Manual sessions (indefinite, duration, until a time, while an app runs, until downloads and tasks finish), command-line holds that stack beside them (`awake hold`, up to 8), user-defined session types (presets), automatic sessions (rules with 12 TCC-free condition kinds, priorities, per-rule options), battery/thermal/Low Power Mode guards with a fixed 5% battery floor (applied whenever the battery is discharging, whatever the adapter reports) and a thermal end that nothing can weaken, activity simulation (pointer movement only for sessions the user started in Snaptic's UI, and after a confirmation when the start came from a hotkey), Drive Alive, its own menu bar indicator (shown while active by default) with optional countdown, hotkeys and `snaptic awake …` CLI (including `awake hold` for scripts). One named IOKit power assertion, swapped by type, with absolute-deadline `TimeoutActionRelease` backstops. Displays' `sleepPrevention` moves here.
2. **Settings redesign**: one SwiftUI component library (`Sources/Snaptic/SettingsUI/`), a new information architecture (sidebar 31 rows → 7; default visible settings controls ~245 → ~60, §4.3 counts), every option explained, every 0.2 setting, button, action and menu item mapped to a 0.3 home: each page, sheet and menu builder declares its controls in a static table, and a Kit test checks the tables against a frozen literal 0.2 list (§4.8), the 17 duplicates removed (14 from [UA] plus 3 for Awake), expert options behind **Advanced…**, settings search, and the live-update root causes fixed in the architecture (observable per-display runtime, controller revisions, drag-local slider state, throttled commits, per-section config observation and fan-out).
3. **Menu bar redesign**: one menu item factory (`MenuKit`), one header style, AppKit-only custom rows (sliders, switch headers) with live values that update while the menu is open (`.common` run-loop mode), no sliders in submenus, one level of submenus, "Settings…" then "Quit" last, one presence pop-up per module with Control Center wording; every 0.2 opt-in menu item keeps a 0.3 location and a show/hide control; an Awake status item (shown while active by default) and one Awake row set (`AwakeMenuRows`) used by both the Awake menu and the compact Awake section of the Snaptic menu.

Priorities (0.2 order kept, Awake rows added): (1) never leave the user without a usable display, keyboard or way back; (2) nothing Snaptic does lets another process use Snaptic's permissions or see data obtained with them; (3) never damage a monitor **or drain a battery to shutdown** (Awake's critical-heat end and its fixed 5% battery floor have no setting and no kill switch); (4) parity; (5) polish.

### 0.1 Decisions taken here (normative)

| # | Decision | Why |
|---|---|---|
| N1 | CLI **may start** Awake sessions: closed grammar, guards apply, never pointer movement (N10), never Drive Alive (strict, OQ-1 settled; the session's `source` survives restore), never an unbounded session (`awake start` with no argument = 1 h; `awake hold` lasts while its own connection and process live, or while a named pid lives, and at most 12 h by default, 24 h with `--max`); `start` and `preset` never replace a session the user started in the UI, and `hold` never replaces anything: holds stack beside any session, at most 8 (N17) | §3.1: a same-user process can already hold the same assertion with `caffeinate`; nothing that uses Snaptic's TCC grants is reachable |
| N2 | Duration sessions run on the **continuous clock** (`CLOCK_MONOTONIC_RAW`, counts sleep, immune to clock changes); "Until" sessions are absolute wall instants; a reboot ends every session; trigger hysteresis is in-memory continuous-clock state and is never persisted | Predictable; matches Amphetamine; no recovery machinery; no defaults write per engine step |
| N3 | One **governing** source at a time: the manual session if any, else the highest-priority active trigger, else the command-line holds (one source, N17) | Amphetamine's priority model; one assertion; one indicator reason |
| N4 | Every Settings slider gets a typed value field and a reset glyph (except live hardware values with no default, e.g. live Brightness; R5); the field **is** the live value (no separate value label) | Explicit requirement; [DS] layout in §4.1 |
| N5 | All modules always appear in the sidebar; each module page has a header switch (Wi-Fi pattern) whose accessibility label and tooltip are "Use <Module>"; session-level actions are **buttons**, never a second switch | [DS] §1.2; design B1, parity M7 |
| N6 | Displays' 16 sidebar pages become **one** sidebar row with sub-pages in a `NavigationStack` | [DS] §1.1, [UA] §2.1 |
| N7 | Everything about the menu bar (presence per module, icons, countdown, Displays menu customization) lives **only** on the Menu Bar page | Removes duplicates 4, 13 and the Awake split |
| N8 | Displays feature switches live where the feature is used (sub-page header switch, section switch or Advanced › Use Snaptic for); the 47-switch Features page is deleted | [UA] §2.5 #4 |
| N9 | Two task-bound session kinds: **Until Downloads and Tasks Finish** (`untilIdle`: ends after 5 min with no busy signal, never within 10 min of its start (R5); busy = busiest same-user process (own plus reaped-children CPU, R5) ≥ 50% of one core, or ≥ 3 new same-user processes in a 5 s sample (short-lived build steps), or total CPU ≥ 15%, or disk I/O ≥ 1 MB/s, or network ≥ 50 KB/s; process CPU from `proc_pid_rusage` scaled by `mach_timebase_info`) and **command-line hold** (`hold`, CLI `awake hold`, N17) | Parity B1, M2, M3; code R2-M10, r3 code M2 |
| N10 | **No consent record** (r2's Keychain record is withdrawn: forgeable under the legacy file keychain that ad-hoc builds use, and lost on every ad-hoc update). Instead: (a) **pointer movement** acts only for a session started by a direct user action in Snaptic's own UI in this process (a menu click or a Settings button; a Snaptic hotkey only after the user clicks **Allow** on the confirmation toast "Move the pointer to keep apps active?", as 0.2 R5.7 does for Gather Windows), never for CLI, trigger, restored or resumed sessions; the flag that records this (`uiStartedInProcess`) is set only by those handlers and cleared on every restore, resume, CLI or trigger takeover, session replacement and module stop (§2.3 `AwakeActivityGate`), never while the screen is locked or the session is off console, and at most `activity.stopAfterHours` (default 1 h, max 8 h) measured on Snaptic's own continuous clock, never on system idle time (Snaptic's own declarations reset idle); (b) **Drive Alive** volumes are chosen in the UI and stored by volume UUID; (c) a fixed 5% battery floor and the critical-heat end apply whatever the config says; the floor applies whenever the battery is **discharging** (battery present and either not on AC or the battery falling within the last 10 minutes, R5-6), and a laptop whose battery can't be read is treated as at 0% for activity and Drive Alive (§2.6). Config changes made outside Snaptic take effect like any setting; the residual same-user risk is stated in §3.2 | Lead r3/r4; security H1/M1/M2, r3 security M1–M3 |
| N11 | A running Awake session is never invisible: whenever Awake governs and the Snaptic item exists, the Snaptic icon shows its active variant (whether or not an Awake icon exists); if no Snaptic icon exists, the Awake icon appears for the session; a session never removes an item that was shown at rest | Parity M2, M5 |
| N12 | SnapticKit formats user-visible numbers, durations and clock times **by hand** from explicit inputs (`AwakeTextContext`), never through Foundation formatters | Code M11: corelibs 5.10 and macOS ICU disagree; Kit tests run on both |
| N13 | Lint rules land in step 0 with a **ratchet** (`scripts/lint-legacy.tsv`) of known violations; a deleted file or symbol is removed only at the step-3 exit after a caller grep | Code B1, M10 |
| N14 | Snaptic does **not** read managed preferences (0.2 rule). Organizations use documented hidden defaults read from Snaptic's persistent domain: `Modules.disable.awake` (whole module), `Awake.disable.<feature>` (per feature; `sessions`, `batteryGuard`, `thermalGuard`, `indicator` (R5) ignored, use the module key instead). An admin can deploy them with a configuration profile that writes Snaptic's user domain | Lead r3; security M5 |
| N15 | Everything that must update while a menu is open (countdown, live rows, slider binds, `ControllerRevision` coalescing) runs in `.common` run-loop modes: timers via `RunLoop.main.add(_:forMode: .common)`, coalescing via `DispatchQueue.main.async`; `Timer.scheduledTimer` and `RunLoop.main` schedulers are banned in menu and Awake code (lint L14) | Lead r3; code R2-M7 |
| N16 | Every settings page, Advanced/other sheet and menu builder declares its controls in a static, compile-time table (Kit `ControlTable`: ids, availability conditions as data, the 0.2 ids it replaces), registered in one lead-owned `ControlRegistry` list. A Kit test checks the union against the frozen **literal** 0.2 list (§4.8.1) and the "removed with reason" table; lint checks that every `ControlID("…")` literal in a view or builder is in that type's table and vice versa. No runtime render walk, no debug gate; CI enforces it. Every 0.2 opt-in menu item keeps a menu location and a show/hide control in Customize Displays Menu | Lead r3/r4; parity B1, M1; r3 code B1, M4 |
| N17 | **Holds stack**: each `awake hold` adds a holder (≤ 8) beside whatever else runs; the Mac stays awake while any holder exists; holds never replace, and are never replaced by, a manual session; the menu and status row say "Held by Terminal (2)" (local UI only) | Lead r4; r3 product M4 |
| N18 | **Lossy collections**: rules, presets, history entries and Drive Alive volumes decode element by element (one bad element is dropped, the rest kept) through Kit `LossyArray`/`LossyMap`; every persisted id is a valid `StableID`; ids that must be reproducible (M1 rules, default presets) come from `StableID.derived(namespace:name:)`, a name-based UUID built from a Kit 128-bit FNV-1a hash | Lead r4; r3 code M5, M6, sig rows |

### 0.2 Decisions to confirm (lead)

| # | Proposal (r2 wording) | Default if not confirmed |
|---|---|---|
| C1 | While the screen is locked, a `keepOn` session downgrades to system-only (display may sleep, Mac stays awake); Advanced option "Keep the display on while locked" | Adopt |
| C2 | Replace `MenuPlacementChoice` (shared / own / hidden) with `MenuPresence`, one pop-up per module, Control Center wording and one option order for every module: **Always Show in Menu Bar / Show When Active / Show in Snaptic Menu / ─ / Don't Show** (`ownIcon / ownIconWhenActive / inSnapticMenu / hidden`); *Show When Active* exists for Awake (a session runs) and Displays (an external display is connected; replaces "Hide when no external display is connected"); `placement` keeps being written for 0.2 downgrades | Adopt (migration M2, §4.6; design M5) |
| C3 | Drop the right-click "quick menu" (right-click is not delivered on macOS 27 [PA] §8); its items move into **Display Tools ▸** | Adopt |
| C4 | Menu slider rows show a live value but no typed field or reset; every slider action and every Awake action also exists as a **native** menu item, shortcut or Settings control | Adopt |
| C5 | "Network activity above N KB/s" criterion (interface byte counters via `sysctl NET_RT_IFLIST2`, loopback excluded, tunnels counted only when no physical interface moved bytes; no connections, no TCC) replaces the TCC-gated Downloads-folder criterion; the same counters, plus CPU and IOKit block-storage counters, drive `untilIdle` | Adopt |
| C6 | Bluetooth criterion limited to Bluetooth **audio** devices (CoreAudio transport type) and Bluetooth **input** devices (IORegistry `IOHIDDevice` `Transport` property, never opened); Beta | Adopt |
| C7 | 0.1/0.2 → 0.3 upgraders get Awake **off** (ModuleHost and `upgradeDefaults()` insert it disabled before M1 runs) unless M1 produced an enabled rule from **effective** 0.2 sleep prevention. Upgrade experience (design M3): a state-dependent General card (Awake off: "New: Awake" [Turn On Awake] [Not Now]; migrated: "Your display sleep setting moved to Awake." [Show Awake] [OK]), a one-time toast at a migrated user's first activation, and a "New" sidebar badge on Awake until the page is first visited | Adopt |
| C8 | Menu item "Switch Windows ⌥⇥" opens the switcher in sticky mode (stays open until Return/Esc/click); new small Switcher capability (A) | Adopt; fallback: omit the item |
| C9 | Drive Alive runs only while an Awake session whose `source` is not `.commandLine` is active (restored sessions keep their source; holds count as `.commandLine`; trigger sessions pass `.rule`, R5-14), unless the user turns on "Also when no session is running"; the battery floors and thermal guard gate it in **every** mode | Adopt |
| C10 | Default session from the UI (status-row button, menu, hotkey) = the default preset, **Until Turned Off** out of the box; from the CLI, `awake start` without an argument = 1 h | Adopt (Amphetamine parity for the UI; no unbounded CLI sessions) |
| C11 | Default Awake presence = **Show When Active** (`ownIconWhenActive`; fresh installs and upgraders whose M1 rule is on): one Snaptic icon at rest, the Awake icon beside it during a session | Adopt (design M3, parity M2) |

**Lead (r1):** C1–C10 adopted as proposed. **Lead (r2):** C2, C5, C7, C9, C10 re-worded and C11 added. **Lead (r3):** N10, N14–N16 and the `awake hold`, `untilIdle` and Awake-menu shapes are lead decisions; C2, C5, C7, C9, C11 re-worded after review round 2; adopted unless the lead objects. **Lead (r4):** N10 and N16 re-worded, N17 and N18 new (lead-8…lead-15 in the r4 table). OQ-1 is settled (strict); OQ-2…OQ-8 take their stated defaults until hardware testing says otherwise.

Open questions (need hardware or product input) are marked **[OQ-n]** and collected in §6.8.

---

## 1. Scope

Legend: **Def** = A always on with the module, S standard (on), O opt-in, X experimental, B beta tag. Amphetamine references are [AP] §1.x, Insomnia [AP] §2.x.

### 1.1 Awake: In

`AwakeFeature` (Kit, persisted raw values) and what each covers.

| Feature id | Covers | Def | Requires | Parity |
|---|---|---|---|---|
| `sessions` | Manual sessions: indefinite; duration (presets + custom h/m); until a clock time; while an app runs (picked from running apps, by bundle id, ends when its last instance quits; optional "At most" cap); **until downloads and tasks finish** (`untilIdle`: ends after 5 min with no busy signal, §2.5; 10 min minimum hold (R5); optional "At most" cap); **command-line holds** (CLI only, stack beside any session, ≤ 8, N17, §2.10); extend (+15 min / +1 h / Add Time… for timed kinds and capped task kinds; no-op items are not shown); end; replace; display policy per session (keep on / can turn off / keep on until idle for N min), changeable mid-session ("Keep Display On" in the menu and the status row's Options ▾); end on sleep (opt), end on user switch (immediately / after 1 h / never), end after the screen has been locked for N h (opt); resume after Snaptic relaunch within the same boot; start a session at launch (opt); "why is my Mac awake" lid notice (on battery or without an external display); 5-minute reminder; **8-hour reminder** for indefinite sessions; last non-user end shown for 12 h | A | — | Amph 1.2 (incl. "while downloading" via `untilIdle`), 1.3 display sleep incl. mid-session toggle, 1.4 manual-sleep / FUS ends, 1.8 reason text; Insomnia 2.2 timed sessions, chips, 30-day cap; `caffeinate -w` (CLI `hold --pid`) |
| `presets` | Session types: up to 12 named presets (kind + optional options, nil = "Use default"; task kinds with an optional "At most" cap), shown in the Awake menu's Start Session › in order; default preset; last custom value remembered | A | sessions | Amph "default duration", "Other Time" memory (1.2); Insomnia preset chips |
| `batteryGuard` | End below N% on battery (5–50%, default 20%; the user floor can be turned off); **independently, a fixed 5% floor** (`AwakeGuards.hardFloorPercent`, no setting, no kill switch) always ends sessions and Drive Alive while the battery is **discharging** (present, and not on AC or falling within a 10-min window; §2.6, R5-6); end on adapter disconnect (opt); end on Low Power Mode (opt); a laptop whose battery can't be read twice in a row stops activity and Drive Alive (treated as 0%) and keeps the session's assertion with a toast; rule restarts suppressed until cleared (+5% hysteresis, or a rise or charging reported; R5-6) | A | — | Amph 1.4; Insomnia 2.5 floor and unreadable rule |
| `thermalGuard` | `.critical` → end all sessions and holds and stop Drive Alive, pause rules 10 min; `.serious` → one-time toast (no setting) | A | — | Insomnia 2.5 |
| `indicator` | Internal capability (unkillable since R5, not a user feature): Awake's own status item; **Time: Don't Show / Time Remaining / End Time** (default Don't Show); glyph family cup / eye / lightbulb (outline idle, `.fill` active); seconds only in the last minute; VoiceOver label and tooltip refreshed at every countdown change. Whether the item exists is `MenuPresence` alone (§5.3) | A | — | Amph 1.8 (no custom images); Insomnia 2.6 countdown |
| `triggers` | Automatic sessions ("rules", each with **conditions**): ≤ 32 rules, each ≤ 8 conditions, All/Any, "is / is not" per condition, order = priority, per-rule session options, start delay, end delay (hysteresis), "After I turn it off: resume when the conditions are next met / after N min", **Pause Rules** for 1 h / until tomorrow (Rules › in the Awake menu and the compact section whenever a rule exists, the status row's Pause Rules ▾, hotkey, CLI `awake pause`). Turned on implicitly by the first **Add Rule…** (no section switch, design M4) | O | sessions | Amph 1.5 (all criteria except SSID and the Cisco VPN brand; DNS servers covered by subnet + router) |
| `activity` | "Appear active": `IOPMAssertionDeclareUserActivity` every 60 s while a session runs, the screen is unlocked and on console (read from the session dictionary, §2.9), the user hasn't typed or clicked for ≥ 60 s, and the displays are awake; it stops `stopAfterHours` (default 1 h, 1–8 h) after it first acted, **measured on Snaptic's continuous clock** (N10) and carried across back-to-back sessions, until the user starts or restarts a session in the UI | O | sessions | Amph 5.0 cursor movement (closest TCC-free equivalent) |
| `pointerNudge` | "Move the pointer slightly": a 1-pt mouse-moved event and back, posted from a private event source with `CGEvent`, only with Accessibility, same conditions as `activity`, **only for sessions started by a direct user action in Snaptic's UI in this process** (N10; a hotkey start only after the user allows it in a confirmation toast), never within 2 pt of a display edge, never keyboard or clicks; while it acts, the menu and status row say "Moving the pointer" | X | activity | Amph 5.0 "Move the mouse cursor periodically" |
| `driveAlive` | Per external volume opt-in, chosen in the UI and stored by volume UUID; tiny periodic write + `F_FULLFSYNC` to `/<volume>/.snaptic-keepalive` via a verified directory fd (§2.9); every 30–600 s (default 120); `PreventDiskIdle` while active; only during sessions whose source isn't the CLI unless "Also when no session is running"; battery floors and thermal guard apply in every mode | O | — | Amph 1.6 |
| `history` | Local history (≤ 500 entries, 90 days; entries < 60 s that ended `.replaced` are merged), today/7-day totals, "Start Again" (app sessions keep their bundle id locally; entries record their `source`; not offered for command-line, process and automatic entries), clear; never exported, never in diagnostics | S | — | Amph 1.10 statistics |
| `shortcuts` | Global hotkeys: Keep Awake on/off (default preset), Keep Display On (toggle), Start “<preset 1–4 name>”, Pause Rules; all unbound by default | S | — | Amph 1.10 |
| `commandLine` | `snaptic awake status|start|hold|stop|extend|preset|pause` (§2.10); needs the host CLI switch (General) | S | — | Amph AppleScript 4 commands (equivalent surface); `caffeinate -w` |

Always present (not flags): **Other apps keeping your Mac awake** — an inline live section in Awake › Advanced (`IOPMCopyAssertionsByProcess`, plus a warning when the system-wide `SleepDisabled` setting is on, read with `IOPMCopySystemPowerSettings`, the trace left by Amphetamine Power Protect, Insomnia or `pmset disablesleep`; never in logs, diagnostics or CLI); "Closing the lid will put your Mac to sleep" line in the Awake menu when a session is active on a laptop not in desktop mode (`AppleClamshellCausesSleep`).

**Criterion kinds** (`AwakeCriterionKind`; availability per kind, no feature flags):

| Kind | Source (J) | API | TCC | Parity |
|---|---|---|---|---|
| `app` (running / frontmost) | AppMonitor | `NSWorkspace` launch/terminate/activate notifications | none | Amph 4.0 |
| `display` (any external, ignore built-in; a specific display; mirroring on) | DisplayPresence | `CGDisplayRegisterReconfigurationCallback`, `CGGetOnlineDisplayList`, `CGDisplayIsBuiltin`, `CGDisplayIsInMirrorSet`; specific display by salted `FingerprintRecord` matched with B's `Fingerprint.matches` | none | Amph 4.2, 4.1.5; replaces Displays `sleepPrevention` |
| `power` (on adapter / on battery / charging / battery ≥ N%) | PowerMonitor | `IOPSCopyPowerSourcesInfo`, `notify_register_dispatch(kIOPSNotifyPowerSource / PercentChange)` (`import notify`) | none | Amph 5.0 |
| `schedule` (weekdays × start–end, overnight allowed) | none: TriggerController's Ticker (G) (consistency M5: no service id, `services(of: .schedule) == []`) | wall clock; boundary dates from `Calendar.autoupdatingCurrent.nextDate`, Ticker capped at 15 min; wake, clock and time-zone notifications | none | Amph 1.5/3.0 |
| `cpu` (system CPU ≥ N%, 10 s average) | CPUSampler | `host_statistics(HOST_CPU_LOAD_INFO)` tick deltas, cached `mach_host_self()`, 5 s period while used | none | Amph 4.1.4 |
| `audio` (output playing / microphone in use) | AudioMonitor | `kAudioDevicePropertyDeviceIsRunningSomewhere` on default output / input, property listeners on a private queue | none (no mic access, property only) [HW-9] | Amph 4.0 audio output |
| `idle` (no input for ≥ N min) | IdleSampler | `CGEventSourceSecondsSinceLastEventType(.hidSystemState, t)` per input type (key down, flags changed, mouse down ×3, scroll wheel, mouse moved), minimum taken, mouse-moved resets within Snaptic's nudge echo window ignored; never `anyInput` (security M2; §2.9), 10 s period while used | none | Amph 4.1.5 |
| `volume` (a volume is mounted) | VolumeMonitor | `NSWorkspace.didMount/didUnmount`, `volumeUUIDStringKey` | none (listing only) | Amph 4.0 |
| `usb` (a USB device is connected) | USBWatcher | `IOServiceAddMatchingNotification(IOUSBHostDevice)` first-match + terminated, iterators drained | none | Amph 4.0 |
| `network` (IP in subnet; **connected to this network** = remembered router; VPN connected) | NetworkMonitor | `SCDynamicStore` `State:/Network/Global/IPv4`, `State:/Network/Interface/*/IPv4`; router MAC from the routing table (`sysctl NET_RT_FLAGS`), salted hash only [HW-11]; VPN = `utun*/ipsec*/ppp*` with an address and primary | none | Amph IP, IPv6, VPN (5.0, 4.1); the router criterion is the SSID substitute |
| `networkActivity` (C5) | NetworkMonitor | `sysctl NET_RT_IFLIST2` `if_data64` byte deltas (64-bit counters), 5 s period while used | none | Replaces "while downloading" as a rule; `untilIdle` covers the one-off case |
| `bluetooth` (C6, Beta) | BluetoothPresence | CoreAudio device list with transport Bluetooth/BLE; IORegistry `IOHIDDevice` with `Transport == "Bluetooth"` (properties only, never opened) | none [HW-10] | Amph 4.0 Bluetooth (partial) |

### 1.2 Awake: Deferred (feasible later without breaking the rules)

| Item | Reason |
|---|---|
| "While a file is downloading" via the Downloads folder | Downloads-folder TCC under Snaptic's identity; `untilIdle` and C5 cover the use case |
| General Bluetooth devices via IOBluetooth | Bluetooth TCC and possible kill without a usage string |
| Lock the screen after inactivity | `NSWorkspace.openApplication(ScreenSaverEngine)` is public and spawns nothing, but it locks only when "require password" is immediate, and Snaptic can't verify that setting ([PA] §7) |
| Screen-saver exceptions, per-trigger screen-saver delay | Needs measured behavior of assertions vs screen saver [HW-4] first |
| Sounds on start/end | Low value; adds options |
| App Intents / Shortcuts, AppleScript `sdef` | SwiftPM build can't process App Intents metadata; `sdef` needs bundle resources (`resources:` is banned) |
| Control Center / menu bar `ControlWidget` | Needs an app extension (entitlements, 26 SDK) |
| `expandedInterfaceDelegate` custom panel on 27 | 27 SDK only |
| Process-name criterion for faceless processes (`proc_listallpids`) | `hold` (`awake hold`) covers the agent and build case for 0.3; a standing rule needs a polling budget and would store process names |
| `awake hold -- <command>` (wrap a command) | Snaptic never runs commands (rule 12); scripts background `hold` or pass `--pid` (§2.10) |
| Reading managed preferences (MDM-forced keys, managed screen-lock detection) | 0.2 rule: Snaptic reads only its persistent domain; admins deploy the hidden kill switches (N14) |

### 1.3 Awake: Excluded (by design)

| Item | Reason |
|---|---|
| Closed-lid on battery (`pmset disablesleep`, sudoers rules, Power Protect, unprivileged clamshell SPI) | Root or SPI, persists after a crash, same-user exploitable, heat risk ([AP] §1.7, §3.3; [PA] §2). Awake › Advanced reports a leftover `SleepDisabled`; the README explains cleanup |
| Privileged helper, root, admin prompts, LaunchAgents/Daemons | Constraint |
| Turning Low Power Mode on/off | Needs root (`pmset -b lowpowermode`) |
| Wi-Fi SSID criterion | Location TCC + hardened-runtime location entitlement ([PA] §4); "Connected to this network" (router) is the substitute |
| DNS-server criterion | Not brand-specific and `State:/Network/Global/DNS` is TCC-free, but subnet + router already identify a network; one fewer editor |
| Cisco-AnyConnect-specific VPN criterion | Brand-specific; generic VPN covers it |
| Hold-to-end (Insomnia [AP] §3.1.5) | Stopping already takes two deliberate clicks or a shortcut |
| macOS notifications (`UNUserNotificationCenter`) | Snaptic uses ToastPresenter + menu state (0.2 §3.3) |
| `snaptic://` URL scheme | Any web page could fire it |
| Custom menu bar images, emoji icons | Curated template SF Symbols only |
| Insomnia lid-close actions (SIGSTOP apps, mute, keyboard backlight, App Nap writes into other apps' prefs), hotspot failover, tmux nudge, browser relaunch, `docker ps` | Invasive, run or inject code, network ([AP] §3.3) |
| Spawning `/usr/bin/caffeinate` | In-process assertions die with the process; spawning is banned outside HelperSpawner |
| Synthetic key events of any kind | Could type into the focused app |
| Options cut in r2: "different icon for automatic sessions", "show seconds", "also end on serious heat", activity interval | Low value per option ([DS] budget); seconds show in the last minute, serious heat keeps its toast, critical heat always ends, interval fixed at 60 s |

### 1.4 Parity map (Amphetamine → Snaptic Awake)

| Amphetamine | Snaptic |
|---|---|
| Indefinite / duration / until time / extend / default-duration quick start | `sessions` + `presets`; quick start = status-row button, menu, hotkey, `awake start` |
| While app running (sandbox-limited) | `sessions` (whileApp) and `app` criterion; not sandboxed, so all regular apps |
| While file downloading | `untilIdle` session ("Until Downloads and Tasks Finish") for one-offs; C5 `networkActivity` criterion for rules; `awake hold` for scripts |
| Allow display sleep; toggle mid-session by hotkey | `AwakeDisplayPolicy`; "Keep Display On" toggle in the Awake menu, the compact section and the status row's Options ▾ while active; hotkey |
| Screen saver / screen-saver delay | Deferred ([HW-4]) |
| Closed-Display Mode | Excluded; menu explains the native route (external display + power) |
| Move cursor periodically | `activity` (default, no TCC) + `pointerNudge` (X, Accessibility) |
| Lock screen after inactivity | Deferred |
| End on low battery / adapter disconnect / manual sleep / FUS | `batteryGuard`, `sessions` behavior options |
| Triggers: unlimited, priority, names, AND/OR | `triggers` (≤ 32, order = priority, All/Any + per-criterion negation) |
| Criteria: displays, USB, Bluetooth, app, battery/power, IP, SSID, DNS, VPN, audio, drive, CPU, idle, schedule | All except SSID (router substitute) and DNS (subnet + router); Bluetooth partial (C6) |
| Re-activate a manually ended trigger session after a time | `resumeAfterManualEndMinutes` ("After I turn it off" in the rule editor) |
| Drive Alive per drive + interval | `driveAlive` |
| Menu bar icon styles, active/inactive images, time remaining, 12/24 h, seconds | `indicator` (curated families, outline vs fill, time remaining or end time in the system's 12/24 h setting, seconds in the last minute) + presence "Show When Active" |
| ⌘-click quick start | Hotkey + status-row button (status item clicks always open the menu on 14–27) |
| Notifications, sounds, reminders | Toasts ("5 minutes left", "8 hours", "ended: battery low") + menu state + Recent Notices; no sounds |
| AppleScript, statistics, debug mode | CLI; `history`; Awake diagnostics in the shared report (counts only) |

Insomnia → Snaptic: timed sessions and chips (`presets`), 30-day cap (same), battery/thermal floors (`batteryGuard`, `thermalGuard`), countdown in the bar (`indicator`), "extend" reminder (toast at 5 min left with **Add 1 Hour**), soft reminder for indefinite sessions (toast after 8 h with **Turn Off** / **Keep Going**), sleep-disabled-by-another-process detection → "Other apps keeping your Mac awake" (+ `SleepDisabled`). Everything pmset/journal/backstop-based is unnecessary: assertions die with the process ([PA] §1.2).

### 1.5 Settings and menu redesign scope

| In | Deferred | Excluded |
|---|---|---|
| SettingsUI component library (§4.1) used by every page | String Catalog localization (strings keep going through `L()`) | Custom window chrome, fake glass, custom title bars |
| New IA for General, Menu Bar, Window Switcher, Displays (+ sub-pages), Awake, Permissions, About (§4.2–4.4) | Liquid Glass APIs, `preferredImageVisibility` (26 SDK) | Tabs inside pages, nested sheets |
| Search (`.searchable(placement: .sidebar)`, static index, scroll-to-anchor highlight; covers Advanced sheets) | Settings deep links from outside (no URL scheme) | Popover/panel menus for status items |
| Live-update fixes A1–A11, B1–B3, C1–C2, M1 ([UA] §1) | | |
| Config migration with no setting lost (§4.6) and the complete 0.2 → 0.3 control map (§4.8) | | |
| Menu redesign for all modules (§5), MenuKit, AppKit-only custom rows (MenuSliderRow, MenuSwitchHeader), one presence pop-up per module | | |
| Onboarding update: modules step adds Awake; one primary button location | | |
| Floating Displays panel restyled with the same row components | | |

---

## 2. Awake architecture

### 2.1 Shape (mirrors Displays, smaller)

```
AwakeModule (lead)            SnapticModule + StatusItemProvider; uses the config, snapshot and history stores ModuleHost owns (R5)
 └─ AwakeContext (lead)       services + controllers + AwakeHost; built per start; services hold it weakly
     Services (refcounted by need, AwakeServiceID; J unless noted)
       assertions  AssertionManager (G)   the ONLY IOPMAssertionCreate*/Release caller for sleep assertions (lint L1)
       power       PowerMonitor           IOPS notify, LPM, thermal, battery facts (multicast observers)
       system      SystemEventsMonitor    sleep/wake, screens sleep/wake, session facts (CGSession dictionary), screensaver hints, FUS, clock, TZ, day change, lid
       apps        AppMonitor             running/frontmost bundle ids, app list for pickers
       displays    DisplayPresence        online displays as FingerprintRecords, mirroring
       usb         USBWatcher             IOUSBHostDevice matching
       volumes     VolumeMonitor          mounted volumes (uuid, name, Drive Alive eligibility via DiskArbitration)
       audio       AudioMonitor           output/input running-somewhere (HAL calls on a private queue)
       cpu         CPUSampler             total CPU 10 s average; while untilIdle runs: every pid's rusage incl. reaped-children time (timebase-scaled; R5), busiest same-user process, new-process churn
       disk        DiskIOSampler          IOBlockStorageDriver Statistics byte deltas (untilIdle only)
       idle        IdleSampler            per-type HID idle, nudge echoes excluded (IdleMath), last real input
       network     NetworkMonitor         IPv4/IPv6 addresses, router hash, VPN, 64-bit throughput (loopback excluded)
       bluetooth   BluetoothPresence      BT audio + BT HID presence (Beta)
       activity    ActivitySimulator      DeclareUserActivity / pointer nudge
       driveAlive  DriveAliveService      keep-alive writes on a private serial queue
       process     ProcessWatch           kqueue EVFILT_PROC/NOTE_EXIT + proc_pidinfo start time for holds (peer or --pid)
     Controllers (one per AwakeControllerID; G unless noted)
       sessions    SessionController      manual session lifecycle, presets, task kinds, the hold stack (N17), arbitrate(), assertion plan
       guards      GuardsController       battery/thermal/LPM/sleep/FUS/lock policies
       triggers    TriggerController      criterion facts → TriggerEngine.step → cached top trigger
       activity    ActivityController (J) drives ActivitySimulator from runtime state
       driveAlive  DriveAliveController (J)
       indicator   IndicatorController    own status item (via AwakeModule's StatusItemProvider), countdown, glyphs; menus from AwakeMenuRows
       history     HistoryController      records ends, totals
       automation  AwakeAutomation        hotkeys + CLI verbs
```

Everything is `@MainActor` except `DriveAliveService`'s I/O queue, `AudioMonitor`'s HAL queue and the C callbacks (IOKit, CoreAudio, SCDynamicStore, CG reconfiguration), which use `CallbackTarget` and hop with `MainActor.assumeIsolated` from main-queue delivery (`IONotificationPortSetDispatchQueue(port, .main)`, `SCDynamicStoreSetDispatchQueue(store, .main)`, `notify_register_dispatch(…, .main)`); CoreAudio listeners run on AudioMonitor's serial queue and publish with `DispatchQueue.main.async`. **Every `NotificationCenter`/`DistributedNotificationCenter`/`NSWorkspace` observer in Awake passes `queue: .main`** (lint L10: `queue: nil`, selector-based `addObserver(self, selector:` and `publisher(for:)` without `.receive(on: DispatchQueue.main)` banned under `Awake/`; `thermalStateDidChangeNotification` and `NSProcessInfoPowerStateDidChange` post on arbitrary queues). Timers are created unscheduled and added with `RunLoop.main.add(t, forMode: .common)` with ≥ 10% tolerance, so they fire while a menu is open (N15); `Timer` doesn't count sleep, so wake re-checks stay. No `static let shared` and no `passUnretained` outside `CallbackTarget` in Awake (lint rules 7 and 10 extended to `Awake/`). EventLog category `.awake` (lead adds), written only through `EventLog.shared.record(_ event: AwakeLogEvent)` (§3.6; r3 consistency m5).

**Apply order** (same as Displays §3.6): resolve effective features → required services = `AwakeFeatureGraph.requiredServices(effective:criteria:dynamic:)` (features ∪ criterion kinds used by enabled triggers ∪ `dynamic` needs: `apps` while a whileApp session runs or a picker is open, `idle` while `keepOnWhileActive` governs, `taskQuiet` (cpu + disk + network) while an `untilIdle` session runs, `process` while any hold exists) → stop emptied controllers → deactivate unneeded services (reverse) → activate needed services (in order) → start new controllers → notify the rest. A criterion source that isn't needed costs nothing: no notification ports, timers or listeners. `schedule` has no source: TriggerController's Ticker reads the wall clock and SystemEventsMonitor's clock, time-zone and day notifications (`AwakeContext.source(for: .schedule)` is nil; consistency M5).

**Module start order** (normative; r3 code M1, lead r4): services start **before** sessions are restored.
1. `AwakeModule.start` reads `SnapticAwakeStateV1` once and runs `AwakeRuntimeSnapshot.sanitized(now:)`.
2. It seeds `AwakeDynamicNeeds` from the sanitized snapshot (`AwakeRuntimeSnapshot.dynamicNeeds`, Kit, G, tested): `taskQuiet` for an `untilIdle` manual session, `apps` for `whileApp`, `idle` for `keepOnWhileActive`, `process` when any persisted hold exists.
3. The first apply resolves features and activates every needed service in `activationOrder`, the seeded needs included.
4. Controllers start; `SessionController.start` calls `restore(_:)` with the sanitized snapshot only now, so ProcessWatch re-verifies `--pid` holds and TaskQuiet gets real samples; then the first `arbitrate()`.
5. `restore` recomputes the needs; if they differ from the seed, the module re-applies once in the same turn.
6. (R5) When `commandLine` stops being effective or the host CLI turns off, every hold ends `.commandLineOff` (R5-14); `process` is then no longer needed and deactivates. `taskQuiet` and `apps` can't be deactivated while their session runs, because the needs come from the session.

### 2.2 Kit ids and feature graph (lead, `SnapticKit/AwakeFeatureGraph.swift`)

```swift
package enum AwakeFeature: String, Codable, CaseIterable, Sendable {
    case sessions, presets, batteryGuard, thermalGuard, indicator
    case triggers, activity, pointerNudge, driveAlive, history, shortcuts, commandLine
}
package enum AwakeControllerID: String, Codable, CaseIterable, Sendable {
    case sessions, guards, triggers, activity, driveAlive, indicator, history, automation
}
package enum AwakeServiceID: String, Codable, CaseIterable, Sendable {
    case assertions, power, system, apps, displays, usb, volumes, audio, cpu, disk, idle, network, bluetooth
    case activity, driveAlive, process
}
/// Services a running session or open UI needs beyond features and trigger criteria (code M7).
package struct AwakeDynamicNeeds: OptionSet, Hashable, Sendable {
    package let rawValue: UInt8
    package init(rawValue: UInt8) { self.rawValue = rawValue }
    package static let apps = AwakeDynamicNeeds(rawValue: 1 << 0)       // whileApp session, app picker open
    package static let idle = AwakeDynamicNeeds(rawValue: 1 << 1)       // keepOnWhileActive governs
    package static let taskQuiet = AwakeDynamicNeeds(rawValue: 1 << 2)  // untilIdle session: cpu + disk + network
    package static let process = AwakeDynamicNeeds(rawValue: 1 << 3)    // any hold exists: ProcessWatch
}

package struct AwakeFeatureSpec: Sendable {
    package let defaultState: FeatureDefault           // reuses Displays' enum
    package let beta: Bool
    package let requiresAll: [AwakeFeature]
    package let uses: Set<AwakeServiceID>
    package let controller: AwakeControllerID
    package let permissions: Set<Permission>
    package init(_ d: FeatureDefault, beta: Bool = false, all: [AwakeFeature] = [], uses: Set<AwakeServiceID> = [],
                 controller: AwakeControllerID, permissions: Set<Permission> = [])
}

package enum AwakeFeatureGraph {
    package static var specs: [AwakeFeature: AwakeFeatureSpec] { get }   // table below; total (tested); computed (code sig)
    package static func spec(_ f: AwakeFeature) -> AwakeFeatureSpec
    package static func rawState(_ f: AwakeFeature, in raw: [AwakeFeature: Bool]) -> Bool
    /// Per-feature kill switches never remove these (tested with every kill switch set); `Modules.disable.awake`
    /// stops the whole module instead (N14).
    package static let unkillable: Set<AwakeFeature> = [.sessions, .batteryGuard, .thermalGuard, .indicator]   // .indicator: R5 (N11)
    /// raw − (kill switches − unkillable) − unavailable − Safe Mode removals, closed over requirements.
    package static func resolve(raw: [AwakeFeature: Bool], killSwitches: Set<AwakeFeature>, safeMode: Bool,
                                unavailable: Set<AwakeFeature>) -> Set<AwakeFeature>
    /// nil when `f` or one of its requirements is unavailable or killed (code minor 9).
    package static func enabling(_ f: AwakeFeature, raw: [AwakeFeature: Bool],
                                 available: Set<AwakeFeature>) -> [AwakeFeature: Bool]?
    package static let safeModeRemoves: Set<AwakeFeature> = [.triggers, .pointerNudge, .driveAlive, .activity]
    package static func services(of kind: AwakeCriterionKind) -> Set<AwakeServiceID>
    package static func services(of needs: AwakeDynamicNeeds) -> Set<AwakeServiceID>
    package static func requiredServices(effective: Set<AwakeFeature>, criteria: Set<AwakeCriterionKind>,
                                         dynamic: AwakeDynamicNeeds) -> Set<AwakeServiceID>
    /// assertions, power, system, then sources (apps … bluetooth, process), activity, driveAlive.
    package static var activationOrder: [AwakeServiceID] { get }
}
```

| Feature | Def | Requires | Uses | Controller | Permission |
|---|---|---|---|---|---|
| sessions | always | — | assertions, power, system | sessions | — |
| presets | always | sessions | — | sessions | — |
| batteryGuard | always (the user floor's on/off is `guards.batteryFloorEnabled`; the 5% hard floor has no setting; r3 security L7) | — | power | guards | — |
| thermalGuard | always | — | power | guards | — |
| indicator | always (internal; unkillable, R5) | — | — | indicator | — |
| triggers | optIn | sessions | (per criterion) | triggers | — |
| activity | optIn | sessions | activity, idle, system | activity | — |
| pointerNudge | experimental | activity | activity | activity | accessibility |
| driveAlive | optIn | — | volumes, driveAlive, power | driveAlive | — (Removable Volumes TCC prompt on first write; not a `Permission` case) |
| history | standard | sessions | — | history | — |
| shortcuts | standard | sessions | — | automation | — |
| commandLine | standard | sessions | process | automation | — |

Kill switches (N14): Bool keys `Awake.disable.<feature>` read once per start from Snaptic's **persistent domain only** (Displays R5.4 rule; managed preferences are not read). `unkillable` features ignore them. `Modules.disable.<moduleID>` (lead, `ModuleHost`, read at launch from the persistent domain, honored for every module; new in 0.3 for Awake) makes that module unavailable: it never starts, its page shows "Turned off by a defaults setting." with the header switch disabled, its assertions are released, and nothing restores at the next launch. An organization deploys these keys with a configuration profile that writes Snaptic's user domain (README, step 5). Safe Mode keeps manual sessions and guards (they are safe), removes triggers, activity, nudge, Drive Alive. r2's managed screen-lock detection is withdrawn (0.2 rule); the Snaptic-clock activity cap (N10) bounds how long Snaptic can delay an idle lock.

`KitModules.swift` (lead) additions: `ModuleID.awake` (start order: windowSwitcher, displays, awake), `EventCategory.awake`, `AwakeActionID: RawRepresentable` (open, like `DisplayActionID`), `MenuPresence` (§5.2, beside `MenuPlacementChoice`; consistency B1), `DisplayActionID.fShowPanel = "f.showPanel"` and `.fIdentify = "f.identify"` (used by migration M4 and by `OverviewController`, which drops its private copies; consistency M4), `DisplayMenuItemID.cDDCPower = "c.ddc.power"` (used by migration M10 and by C's `DDCMenuItems`, which drops its private `powerItem`; r3 consistency M1), `NewModuleCard` (below; r3 consistency M2), `AwakeCriterionKind` (here so the graph can reference it). `ControlID` and the registry live in `SnapticKit/Controls/` (§4.8, lead):

```swift
package enum AwakeCriterionKind: String, Codable, CaseIterable, Sendable {
    case app, display, power, schedule, cpu, audio, idle, volume, usb, network, networkActivity, bluetooth
}
/// One-time General cards (r3 consistency M2): a closed enum, so "awake.migrated" survives the M3 filter.
package enum NewModuleCard: String, Codable, CaseIterable, Sendable {
    case displays, awake, awakeMigrated = "awake.migrated"
}
```

### 2.3 Session model (G, `SnapticKit/AwakeSession.swift`)

```swift
package enum AwakeDisplayPolicy: String, Codable, CaseIterable, Sendable {
    case keepOn            // PreventUserIdleDisplaySleep                         UI "Keep on"
    case maySleep          // PreventUserIdleSystemSleep; display follows System Settings   UI "Can turn off"
    case keepOnWhileActive // keepOn until real idle ≥ displayIdleMinutes, then maySleep   UI "Keep on until idle for [n min]"
}
package enum AwakeActivityMode: String, Codable, CaseIterable, Sendable { case off, declare, nudge }

package struct AwakeSessionOptions: Codable, Equatable, Sendable {
    package var display: AwakeDisplayPolicy        // .keepOn
    package var displayIdleMinutes: Int            // 1...240, default 30
    package var activity: AwakeActivityMode        // .off; .nudge acts only per N10 (else it degrades to .declare)
    package init(display: AwakeDisplayPolicy = .keepOn, displayIdleMinutes: Int = 30, activity: AwakeActivityMode = .off)
    package init(from decoder: Decoder) throws     // lossy per field
    package func sanitized() -> AwakeSessionOptions
}

/// "Until Downloads and Tasks Finish" (N9, lead r3/r4). Busy = ANY signal at or above its threshold in a 5 s sample;
/// the session ends after `quietSeconds` with no busy sample, never before `minimumHoldSeconds` from start (R5).
package struct UntilIdleSpec: Codable, Equatable, Sendable {
    package var topProcessPercent: Int     // 50 = half of one core; 10...800 (busiest same-user process, timebase-scaled)
    package var newProcesses: Int          // 3; 1...50 same-user pids first seen in one 5 s sample (short-lived build steps)
    package var totalCPUPercent: Int       // 15; 1...90 (all cores, HOST_CPU_LOAD_INFO; also catches processes too short to sample)
    package var diskKBps: Int              // 1_024; 64...1_000_000 (read + write, IOBlockStorageDriver Statistics)
    package var networkKBps: Int           // 50; 1...100_000 (in + out, non-loopback, §2.8)
    package var quietSeconds: Int          // 300; 60...3_600
    package var minimumHoldSeconds: Int    // 600; 0...3_600 (R5-4; replaces graceSeconds, never shipped; not in the UI)
    package init(topProcessPercent: Int = 50, newProcesses: Int = 3, totalCPUPercent: Int = 15, diskKBps: Int = 1_024,
                 networkKBps: Int = 50, quietSeconds: Int = 300, minimumHoldSeconds: Int = 600)
    package init(from decoder: Decoder) throws     // lossy per field; r2 keys (cpuBelowPercent, networkBelowKBps) never shipped
    package func sanitized() -> UntilIdleSpec
}
/// One untilIdle sample (Kit, G declares it here; J's samplers fill it; r3 consistency m9). nil fields = unknown,
/// which counts as busy so an unknown never ends a session.
package struct TaskActivitySample: Equatable, Sendable {
    package var topProcessPercent: Double?; package var newProcesses: Int?; package var totalCPUPercent: Double?
    package var diskKBps: Double?; package var networkKBps: Double?
    package init(topProcessPercent: Double?, newProcesses: Int?, totalCPUPercent: Double?, diskKBps: Double?,
                 networkKBps: Double?)
}
package enum TaskQuiet {   // Kit, G, tested
    package static func isBusy(_ s: TaskActivitySample, spec: UntilIdleSpec) -> Bool
    /// quietSince: continuous instant of the first quiet sample in the current run (nil while busy).
    /// A wake or a missing sample resets it (code R2-M10).
    package static func step(quietSince: Double?, sample: TaskActivitySample, now: Double, started: Double,
                             spec: UntilIdleSpec)   // `started`: R5-4
        -> (quietSince: Double?, finished: Bool)
    /// Seconds of the current quiet run, for the detail line "Ends after 5 min with no activity · quiet for 2 min"
    /// (r3 product minor 15); nil while busy.
    package static func quietFor(quietSince: Double?, now: Double) -> Double?
}

/// What a command-line hold is bound to (lead r3). The server resolves both; neither comes from the request.
package enum HoldBinding: Equatable, Sendable {
    /// Default: the `snaptic` client's own connection and process (peer pid from LOCAL_PEERPID: best effort, not
    /// identity, r3 security L1; the connection's EOF is the authoritative end).
    /// Ends on EOF of that connection or exit of that pid. Never persisted (a relaunch closes the connection).
    case connection(pid: Int32, startTime: UInt64)
    /// `--pid N`: a same-user process the caller names; ends when it exits. Persisted; re-verified at restore.
    case process(pid: Int32, startTime: UInt64)
    package var pid: Int32 { get }
    package var startTime: UInt64 { get }        // proc start in µs (pbi_start_tvsec·10⁶ + pbi_start_tvusec)
}

package enum AwakeSessionKind: Equatable, Sendable {
    case indefinite
    case duration(seconds: Int)                               // 60 ... AwakeClock.maxSessionSeconds
    case until(unixTime: Double)                              // absolute wall instant
    case whileApp(bundleID: String, maxSeconds: Int?)         // validated reverse-DNS, ≤ 255 bytes; optional cap
    case untilIdle(UntilIdleSpec, maxSeconds: Int?)           // ends after quietSeconds with no busy sample
    // r3's `.hold` case is gone: holds are not manual sessions any more, they stack beside them (N17, AwakeHold)
    package var isTimed: Bool { get }              // duration, until
    package var cap: Int? { get }                  // whileApp/untilIdle cap
    package var isTaskBound: Bool { get }          // whileApp, untilIdle
}
extension AwakeSessionKind: Codable {              // hand-written, type-tagged: {"type":"duration","seconds":5400}
    package init(from decoder: Decoder) throws     // unknown type (incl. r3 drafts' "hold") → throws → session dropped
    package func encode(to encoder: Encoder) throws
}
extension HoldBinding: Codable {                   // `.connection` never decodes (throws → that hold is dropped)
    package init(from decoder: Decoder) throws; package func encode(to encoder: Encoder) throws
}

/// One command-line holder (N17, lead r4). SessionController keeps ≤ maxHolds; `.process` holds persist in the
/// snapshot (LossyArray), `.connection` holds never do.
package struct AwakeHold: Codable, Equatable, Sendable, Identifiable {
    package static let maxHolds = 8
    package var id: StableID
    package var binding: HoldBinding
    package var startedAt: Double                 // wall, display and history only
    package var startedContinuous: Double
    package var deadline: Double                  // continuous: start + cap (cap ≤ AwakeClock.holdMaxCapSeconds)
    package var bootSession: String
    package init(id: StableID, binding: HoldBinding, startedAt: Double, startedContinuous: Double, deadline: Double,
                 bootSession: String)
    package init(from decoder: Decoder) throws    // lossy per field; a binding that doesn't decode throws (dropped)
    package func encode(to encoder: Encoder) throws
    /// nil when expired, from another boot, `startedContinuous > now.continuous`, or deadline − start > holdMaxCap
    /// (r3 security L3).
    package func sanitized(now: ClockNow) -> AwakeHold?
}

/// Persisted and kept through restore (security L1: a restored CLI session stays `.commandLine`).
package enum AwakeSessionSource: String, Codable, Sendable {
    case menu, hotkey, settings, commandLine, launch
    case rule      // R5-14: history and policy only (trigger sessions); sanitized(now:) drops a manual session with it
    /// menu, hotkey, settings: a direct user action in Snaptic's own UI (N10). For pointer movement a hotkey start also
    /// needs the confirmation toast (AwakeActivityGate).
    package var isDirectUserAction: Bool { get }
}

package struct AwakeSession: Codable, Equatable, Sendable, Identifiable {
    package var id: StableID
    package var kind: AwakeSessionKind
    package var options: AwakeSessionOptions      // resolved at start: preset ?? kind default ?? defaultOptions (§2.14)
    package var presetID: StableID?
    package var source: AwakeSessionSource
    package var startedAt: Double                 // wall, display and history only
    package var startedContinuous: Double         // continuous clock at start
    package var deadline: Double?                 // continuous-clock instant: duration end or task cap; nil = none
    package var bootSession: String               // kern.bootsessionuuid at start; mismatch = expired
    /// One-shot "Start Anyway"; not in CodingKeys, never persisted (security H2).
    package var overrideGuards: Bool = false
    // r3's `uiStartedInProcess` and `activitySince` moved out of the session into SessionController's runtime
    // `AwakeActivityGate` (below; r3 security M2), so no session value, persisted or not, can carry them.
    private enum CodingKeys: String, CodingKey {   // explicit (code sig): overrideGuards is excluded
        case id, kind, options, presetID, source, startedAt, startedContinuous, deadline, bootSession
    }
    package init(id: StableID, kind: AwakeSessionKind, options: AwakeSessionOptions, presetID: StableID?,
                 source: AwakeSessionSource, startedAt: Double, startedContinuous: Double, deadline: Double?,
                 bootSession: String, overrideGuards: Bool = false)
    package init(from decoder: Decoder) throws    // lossy per field; kind failure throws (session dropped)
    package func encode(to encoder: Encoder) throws
    /// nil if expired, other boot, kind out of range, `startedContinuous > now.continuous`, or a deadline later than
    /// startedContinuous + (cap or maxSessionSeconds), or `maxSeconds` and `deadline` disagree (r3 security L3).
    package func sanitized(now: ClockNow) -> AwakeSession?
}

/// Runtime-only gate for activity simulation (r3 security M2, lead r4; Kit, G, `SnapticKit/AwakeActivityGate.swift`,
/// tested truth table). SessionController holds the only instance; lint L16 allows `activityGate =` only in
/// `SessionController.swift`. Nothing here is Codable.
package struct AwakeActivityGate: Equatable, Sendable {
    package enum Pointer: Equatable, Sendable {
        case notAllowed      // CLI, launch, restored, resumed, trigger or hold governs
        case askOnFirstUse   // hotkey start: the confirmation toast appears the first time pointer movement would act
        case asking          // toast shown; declare meanwhile
        case allowed         // menu/Settings start, or Allow clicked
        case declined        // Not Now / toast dismissed / Stop on the first-nudge toast: declare for this session
    }
    /// True only after a menu-click or Settings-button start handler, or the hotkey toast's Allow handler, in this
    /// process (N10). Never decoded, never derived from `source`.
    package private(set) var uiStartedInProcess: Bool = false
    package private(set) var pointer: Pointer = .notAllowed
    /// Continuous instant activity first acted; the cap counts from here. Carried across back-to-back governing
    /// sessions (r3 security L5); reset only by `uiStart`, `confirmAllowed`, or ≥ 15 min with nothing governing.
    package private(set) var activitySince: Double? = nil
    package private(set) var lastEnded: Double? = nil     // continuous; for `nothingGoverned`
    package init()
    package enum Event: Equatable, Sendable {
        case uiStart                 // menu item / switch header / Settings button / Start Again / Start Anyway after a UI
                                     // start / choosing the running preset again (restart)
        case hotkeyStart             // Snaptic hotkey (incl. Start Anyway after a hotkey start)
        case confirmAsked, confirmAllowed, confirmDeclined
        case otherStart              // CLI start/preset, launch preset
        case restore, resume         // a session read from the snapshot (launch, relaunch, update, re-enable)
        case takeover                // governing passed from the manual session to a trigger or the hold stack
        case replaced                // the manual session was replaced; the new session's own start event follows
        case ended                   // (R5-7) the manual session ended: pointer reset; activitySince, lastEnded kept
        case governingEnded(now: Double)   // (R5-7) any active → inactive transition of governing: lastEnded = now
        case moduleStop
        case acted(now: Double)      // activity acted: sets activitySince when nil
        case nothingGoverned(now: Double)   // (R5-7) every arbitration with nothing governing: lastEnded nil → now;
                                            // ≥ 900 s since lastEnded → activitySince = nil
        case unchanged               // extend, Add Time, Keep Going, Keep Display On, option/feature changes, Safe Mode
                                     // exit, outside writes to defaultOptions, a hold starting or ending
    }
    /// Truth table (normative): uiStart → (true, allowed, nil); hotkeyStart → (false, askOnFirstUse, kept);
    /// confirmAsked → asking; confirmAllowed (only from asking) → (true, allowed, nil); confirmDeclined → declined;
    /// otherStart, restore, resume, takeover, replaced, ended → (false, notAllowed, kept); governingEnded → lastEnded =
    /// now; nothingGoverned → lastEnded = now when nil, else activitySince = nil when now − lastEnded ≥ 900 (R5-7);
    /// moduleStop → init();
    /// acted → activitySince ?? now; unchanged → self.
    package func applying(_ event: Event) -> AwakeActivityGate
}

package enum AwakeEndReason: String, Codable, CaseIterable, Sendable {
    case user, timeUp, appQuit, processExited, tasksFinished, replaced, triggerEnded, batteryLow,
         adapterDisconnected, lowPowerMode, thermal, systemSleep, userSwitch, lockedTooLong, moduleStopped, safeMode,
         reboot, assertionFailed, commandLineOff   // commandLineOff: R5-14
    // r3's `batteryUnreadable` is gone (lead r4): an unreadable battery stops activity and Drive Alive, not sessions
}

package struct TriggerTop: Equatable, Sendable {
    package var id: StableID; package var index: Int; package var options: AwakeSessionOptions; package var since: Double
    package init(id: StableID, index: Int, options: AwakeSessionOptions, since: Double)
}
/// What the indicator, menu, Settings status row and CLI show (no app names in logs or CLI).
package enum AwakeGoverning: Equatable, Sendable {
    case inactive
    case manual(AwakeSession)
    case trigger(TriggerTop)
    case holds([AwakeHold])          // non-empty; only when no manual session and no active trigger (N3, N17)
}

package enum AwakeUnavailableReason: String, Codable, Sendable { case featureOff, safeMode, turnedOffByDefaults }
/// Kit (code M13), so CLI exit mapping and UI copy are tested.
package enum AwakeRefusal: Error, Equatable, Sendable {
    case guardActive(AwakeEndReason)   // UI: toast with "Start Anyway" (battery/LPM above the hard floor only; never
                                       // thermal, never the 5% floor, never CLI/trigger)
    case unavailable(AwakeUnavailableReason)
    case invalid                       // bad duration, app not running, pid ≤ 1, gone, not ours, already exited, or
                                       // ProcessWatch couldn't arm on the peer or --pid (r3 security L1)
    case notAllowedFromCLI             // indefinite or Until Turned Off from CLI (r3 consistency M3: no nudge refusal;
                                       // CLI sessions keep their options and ActivityPolicy never nudges for them)
    case uiSessionRunning              // CLI start/preset while a UI-started manual session runs (security L4); never
                                       // for `hold`, which stacks (N17)
    case holdLimit                     // AwakeHold.maxHolds holds exist: "Snaptic is already holding for 8 commands."
    case rateLimited                   // CLI start/hold/stop/extend > 1/s
    package var exitCode: Int32 { get }  // 4 for every refusal (0.2 CLI table), message from `text`
    package var text: String { get }     // uiSessionRunning: "A session started in Snaptic is running. Stop it first with “snaptic awake stop”, or use “snaptic awake hold”."
}
```

**Time** (G, `SnapticKit/AwakeClock.swift`):

```swift
package struct ClockNow: Equatable, Sendable {
    package var wall: Double; package var continuous: Double; package var bootSession: String
    package init(wall: Double, continuous: Double, bootSession: String)
}
package enum AwakeClock {
    package static let maxSessionSeconds = 30 * 86_400          // Insomnia's cap; extensions included
    package static let cliDefaultSeconds = 3_600                // `awake start` with no argument (C10)
    package static let holdDefaultCapSeconds = 12 * 3_600       // `awake hold` without --max; also CLI untilIdle caps
    package static let holdMaxCapSeconds = 24 * 3_600           // `awake hold --max` upper bound (lead r3)
    package static func start(_ kind: AwakeSessionKind, options: AwakeSessionOptions, presetID: StableID?,
                              source: AwakeSessionSource, now: ClockNow, id: StableID) -> AwakeSession
    package static func hold(_ binding: HoldBinding, capSeconds: Int, now: ClockNow, id: StableID) -> AwakeHold
    /// nil = no limit; ≤ 0 = expired. Duration and caps use the continuous deadline; until uses wall time.
    package static func remaining(_ s: AwakeSession, now: ClockNow) -> Double?
    /// wall + remaining (code minor 2): the end time to show, correct after a clock change.
    package static func endWall(_ s: AwakeSession, now: ClockNow) -> Double?
    package static func isExpired(_ s: AwakeSession, now: ClockNow) -> Bool   // also true when bootSession differs
    /// The session's end as a continuous instant: `deadline`, or for until-kinds continuous + (unixTime − wall).
    /// Recomputed on clock change; the arbiter re-arms only if it moved > 5 s.
    package static func continuousEnd(_ s: AwakeSession, now: ClockNow) -> Double?
    package static func canExtend(_ s: AwakeSession) -> Bool                   // timed kinds and capped task kinds
    /// nil when !canExtend; the result never exceeds maxSessionSeconds from start.
    package static func extended(_ s: AwakeSession, by seconds: Int, now: ClockNow) -> AwakeSession?
}
/// Hand-formatted text (N12). The app passes `uses24Hour` once, derived from the system locale.
package enum AwakeCountdown {
    /// ≥ 1 h "1h 42m" ("2h" on the hour), 1–59 min "42m" (rounded up), < 1 min "42s".
    package static func short(_ remaining: Double) -> String
    /// "1 hour 42 minutes remaining", "42 seconds remaining" (VoiceOver, tooltip).
    package static func spoken(_ remaining: Double) -> String
    /// "5:00 PM" or "17:00" from local hour and minute (the app converts the instant with Calendar).
    package static func clock(hour: Int, minute: Int, uses24Hour: Bool) -> String
    /// Seconds until `short` changes (minute boundary, or 1 s in the last minute); never 0.
    package static func nextChange(_ remaining: Double) -> Double
}
/// CLI and the "Custom…" panel. "until 17:30" stays a clock request; the app resolves it with
/// `Calendar.autoupdatingCurrent.nextDate(after:matching:matchingPolicy: .nextTime)` (DST-correct, not Kit).
package enum AwakeDurationRequest: Equatable, Sendable {
    case indefinite, untilIdle
    case duration(seconds: Int)
    case untilClock(hour: Int, minute: Int)
}
package enum AwakeDurationGrammar {
    package static let maxDigits = 7, maxDecimals = 2
    /// "90", "90m", "1h30m", "2h", "1.5h", "until 17:30", "until 5:30pm", "indefinite", "forever", "idle".
    /// Numbers: ≤ 7 digits, ≤ 2 decimals, finite, range-checked as Double before any Int conversion;
    /// products use multipliedReportingOverflow (security L4). Never traps (seeded fuzz).
    package static func parse(_ words: [String]) -> AwakeDurationRequest?
}
```

Clock rules (normative):
- Continuous time is `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)` (equals `mach_continuous_time`, counts sleep, system-wide per boot, so it is safe to persist with `bootsessionuuid`). `ContinuousClock` is not used: its `Instant` is opaque and can't be persisted.
- Duration: `deadline = continuous + seconds`. Wall-clock changes don't move it; time asleep counts (N2). The end time shown is `endWall` (wall + remaining).
- Until: an absolute instant chosen in the current zone; a time-zone change keeps the instant and re-renders "Until 5:00 PM" in the new zone (`NSTimeZone.resetSystemTimeZone()`, `Calendar.autoupdatingCurrent`); `NSSystemClockDidChange` re-evaluates expiry immediately.
- After a reboot (`kern.bootsessionuuid` differs) every persisted session is expired with reason `.reboot`; triggers re-evaluate from scratch.

### 2.4 Assertions and arbitration (G)

**Kit** (`SnapticKit/AwakeArbiter.swift`):

```swift
package enum AwakeAssertionType: String, Sendable { case off, system, display }
package enum AwakeAssertionDetails: String, Sendable { case manual, automatic }   // the only Details values (security M6)
package struct AwakeAssertionPlan: Equatable, Sendable {
    package static let name = "Snaptic: keeping your Mac awake"   // fixed vocabulary
    package static let inactive = AwakeAssertionPlan(type: .off, details: .manual, deadline: nil, preventDiskIdle: false)
    package var type: AwakeAssertionType
    package var details: AwakeAssertionDetails
    package var deadline: Double?        // continuous instant; TimeoutSeconds is derived only at create (code M1)
    package var preventDiskIdle: Bool    // Drive Alive writing
    package init(type: AwakeAssertionType, details: AwakeAssertionDetails, deadline: Double?, preventDiskIdle: Bool)
}
package struct AwakeArbiterInput: Equatable, Sendable {
    package var governing: AwakeGoverning
    package var screenLocked: Bool               // session dictionary, read at arbitration (security M2)
    package var consoleActive: Bool              // session dictionary kCGSSessionOnConsoleKey
    package var realIdleSeconds: Double?         // only sampled while keepOnWhileActive governs
    package var keepDisplayOnWhileLocked: Bool   // C1 Advanced option
    package var driveAliveWriting: Bool
    package var guardsHold: Bool
    package var sessionEnd: Double?              // AwakeClock.continuousEnd of the governing manual session, or the
                                                 // latest deadline of the hold stack when holds govern
    package init(governing: AwakeGoverning, screenLocked: Bool, consoleActive: Bool, realIdleSeconds: Double?,
                 keepDisplayOnWhileLocked: Bool, driveAliveWriting: Bool, guardsHold: Bool, sessionEnd: Double?)
}
package enum AwakeArbiter {
    package static let timeoutGraceSeconds: Double = 15
    package static let rearmThresholdSeconds: Double = 5
    package static func plan(_ input: AwakeArbiterInput) -> AwakeAssertionPlan
    /// manual > highest-priority active trigger > hold stack > inactive (N3, N17).
    package static func governing(manual: AwakeSession?, top: TriggerTop?, holds: [AwakeHold]) -> AwakeGoverning
    /// true when the live assertion must be swapped: type or details changed, or the deadline appeared,
    /// disappeared or moved by more than rearmThresholdSeconds.
    package static func needsSwap(current: AwakeAssertionPlan, next: AwakeAssertionPlan) -> Bool
}
```

Plan rules (tested): inactive → `.off`; `.keepOn` → `.display`, downgraded to `.system` when `screenLocked && !keepDisplayOnWhileLocked` (C1) or `!consoleActive`; `.maySleep` → `.system`; holds → `.system` (display may sleep; holds have no options); `.keepOnWhileActive` → `.display` while `realIdleSeconds < displayIdleMinutes·60`, else `.system`; `deadline = sessionEnd + timeoutGraceSeconds` for manual sessions with an end (duration, until, caps) and for the hold stack (its latest deadline), nil otherwise (trigger sessions have no backstop timeout: they end by condition); `preventDiskIdle` = `driveAliveWriting`; the plan contains no relative times, so it is **stable while nothing changes** (tested: 1,000 identical inputs at advancing times give `needsSwap(current:next:) == false` after the first, code sig: until-session deadlines differ by microseconds, so the test never compares plans with `==`).

**AssertionManager** (G, `Awake/Core/AssertionManager.swift`) holds at most one sleep assertion and, separately, at most one `PreventDiskIdle` assertion (code minor 1: no timeout, never swapped, created and released only when `preventDiskIdle` flips):

```swift
@MainActor final class AssertionManager: AwakeServiceLifecycle {
    private(set) var current: AwakeAssertionPlan = .inactive
    private(set) var lastError: Int32?
    init()
    /// Idempotent. When AwakeArbiter.needsSwap: create the new assertion first, then release the old one: no gap,
    /// no IOPMAssertionSetProperty (HW-2 moot). With a deadline: never creates when deadline ≤ now (returns false,
    /// the caller ends the session `.timeUp`); TimeoutSeconds = max(1, ceil(deadline − now)) (0 would mean "none").
    @discardableResult func apply(_ plan: AwakeAssertionPlan, now: ClockNow) -> Bool
    func releaseAll()
    /// Checks our assertion still exists with IOPMAssertionCopyProperties(id) (`takeRetainedValue()`, code minor 1):
    /// on wake, on `com.apple.system.powermanagement.assertions.timeout`, and every 5 min while active. The caller
    /// first runs the expiry check and `arbitrate()`; verify re-creates a vanished assertion only for an active plan
    /// whose deadline is nil or in the future, once; only a failed re-create returns false (code R2-M4).
    func verify(now: ClockNow) -> Bool
    func activate(_ context: AwakeContext, lifetime: Lifetime)
    func deactivate()
}
```
Creation uses `IOPMAssertionCreateWithProperties` with `AssertType`, `AssertName`, `Details`, `AssertLevel = 255`, and when a deadline exists `TimeoutSeconds` + `TimeoutAction = "TimeoutActionRelease"` ([PA] §1.2, §1.5). String literals, no CFSTR macros. An expired backstop never resurrects a session: `SessionController` handles the timeout notification by checking expiry first (`AwakeClock.isExpired` → end `.timeUp`), then arbitrating, then `verify`. A failed create (or failed re-create in `verify`) ends a manual session with `.assertionFailed` and toast "Snaptic couldn't keep your Mac awake. Try again, or restart Snaptic."; for a trigger session it sets an **assertion hold** in `GuardMemory` with backoff 30 s → 2 min → 10 min (one toast per hold, cleared by a successful create or a user start), so a failing create can't loop. The timeout is a **backstop** only: the app ends sessions itself at `remaining == 0`, 15 s before powerd would.

### 2.5 Session lifecycle (G, `SessionController`)

```swift
@MainActor final class SessionController: AwakeFeatureController {
    static var id: AwakeControllerID { .sessions }
    init()
    func start(_ kind: AwakeSessionKind, options: AwakeSessionOptions?, presetID: StableID?,
               source: AwakeSessionSource, overrideGuards: Bool) -> Result<AwakeSession, AwakeRefusal>
    func startPreset(_ id: StableID, source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal>
    func startDefault(source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal>
    /// CLI `awake hold` (N17): adds a holder beside whatever runs. The binding was resolved and verified server-side by
    /// AwakeAutomation (§2.10); ProcessWatch is armed here, and a failed arm refuses `.invalid` (r3 security L1).
    /// `.connection` holds also end when AwakeAutomation reports the connection closed. `.holdLimit` at 8.
    func addHold(_ binding: HoldBinding, capSeconds: Int) -> Result<AwakeHold, AwakeRefusal>
    func endHold(_ id: StableID, _ reason: AwakeEndReason)
    /// "End Command-Line Holds" (Awake menu, status row; only while another source governs, R5-10): each client gets
    /// "Awake hold ended in Snaptic." and exits 0.
    func endAllHolds(_ reason: AwakeEndReason)
    private(set) var holds: [AwakeHold]
    func extend(by seconds: Int, source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal>   // manual only
    /// Mid-session display toggle (menu, compact section, status row, hotkey): sets the governing session's
    /// `options.display` (`.keepOn` ↔ `.maySleep`); for a trigger session it lasts until that session ends.
    func setKeepDisplayOn(_ on: Bool)
    /// User Turn Off (switch header, Turn Off Keep Awake, status row, `awake.toggle`): ends what governs: the manual
    /// session, the governing rule's session (TriggerController.manualEnd), or, when only holds govern, the hold stack.
    /// If a rule or holds still keep the Mac awake afterwards, one toast says so (rules below; lead r4, r3 product M3).
    func turnOff(source: AwakeSessionSource)
    func end(_ reason: AwakeEndReason)         // manual session; trigger session → TriggerController.manualEnd
    func toggleDefault(source: AwakeSessionSource)  // hotkey; status-row/menu buttons call start/turnOff directly
    /// The runtime gate (§2.3). Only this file assigns it, always through `applying(_:)` (lint L16).
    private(set) var activityGate: AwakeActivityGate
    /// ActivityController: pointer movement would act now and the gate is `askOnFirstUse` → shows the confirmation toast.
    func requestPointerConfirmation()
    /// ActivityController: activity acted (applies `.acted(now:)`).
    func noteActivityActed(now: Double)
    /// Called once from `start(_:lifetime:effective:)`, after every needed service is active (§2.1 start order) and
    /// before the first `arbitrate()` (code R2-M8): drops sessions and holds from another boot; re-verifies each
    /// `.process` hold's pid, start time and uid with ProcessWatch; evaluates AwakeGuards with live PowerFacts (a
    /// restored session below a floor while discharging ends `.batteryLow`); keeps `source`; applies `.restore` to the
    /// gate. The snapshot is read only here (security L2, r3 security L4): afterwards SessionController never reads
    /// `state.value`; it always writes a whole snapshot built from its own runtime state.
    func restore(_ snapshot: AwakeRuntimeSnapshot)
    /// Every manual-session and hold end, after history and before arbitration (AwakeAutomation finishes a held
    /// connection with its final line).
    func observeEnds(_ lifetime: Lifetime, _ handler: @escaping @MainActor (AwakeEndedItem, AwakeEndReason) -> Void)
    /// Synchronous: reads the cached trigger top, the hold stack, guard memory, session facts and idle, computes
    /// governing + plan, applies it. Called by every path that changes an input (code M7).
    func arbitrate()
    // AwakeFeatureController members (§2.11)
}
enum AwakeEndedItem: Equatable { case session(AwakeSession), hold(AwakeHold) }
// Lead, Core/ToastPresenter.swift: the 0.2 type is EXTENDED, not redeclared (R5-1): `title`, `perform`,
// `var isDefault = false`, `init(title:isDefault:perform:)`; ≤ 2 per toast through `show(_:actions:…) -> Bool`.
```
**Who sets the activity flags** (normative; N10, lead r4, r3 security M1/M2): only the handlers of a menu item or switch header click and of a Settings button apply `.uiStart`; the hotkey handler applies `.hotkeyStart`; the Allow button of the confirmation toast applies `.confirmAllowed`. Every other start (CLI, `launch`, restore, resume) applies `.otherStart`/`.restore`/`.resume`; a replacement applies `.replaced` before the new start's event; governing passing to a rule or the hold stack applies `.takeover`; `stop()` applies `.moduleStop`. Everything in the `.unchanged` list (extend, Keep Going, Keep Display On, option and feature changes, an outside write to `defaultOptions`, Safe Mode exit, holds coming and going) leaves the gate alone; tested per row.

**Hotkey confirmation** (lead r4; 0.2 R5.7 precedent; toast mechanics in R5-1): when a hotkey-started session would move the pointer for the first time, ActivityController calls `requestPointerConfirmation()`; the toast "Move the pointer to keep apps active?" with **Allow** / **Not Now** appears (never in Recent Notices; while toasts are suppressed the gate stays `askOnFirstUse` and is asked at the next interval), and until Allow is clicked the session only declares activity. Dismissing the toast counts as Not Now for that session. (R5-1: `remember: false`, click guard, bound to the session id; `confirmAsked` only when `show` returns true; `onDismiss` → `confirmDeclined`.) Menu and Settings starts show a non-blocking toast at their first nudge: "Awake is moving the pointer slightly." **Stop** (Stop applies `.confirmDeclined`; r3 security M1).

**Focus safety** (r3 security L8): no session-start control in Settings has `.keyboardShortcut(.defaultAction)` or a Return binding, and start handlers ignore clicks for 1 s after an externally requested `openSettings` (reopen or `open-settings` verb), so a stray Return on a window another process brought forward starts nothing. (R5-8: they also ignore keyDown activation until the first real mouse-down in the window, `SettingsShell.mayStart()`.)

Rules:
- At most one manual session. Starting a new one replaces the old (history entry `.replaced`); choosing the running preset again restarts its timer. Replacing a **task-bound** session shows the toast "Replaced “While Xcode is running”." (local UI only). A CLI `start` or `preset` never replaces a session whose `source.isDirectUserAction` (refusal `.uiSessionRunning`, exit 4; security L4); it may replace a CLI or `launch` session. `awake hold` never replaces anything (N17). Starting while a trigger governs makes the manual session govern; when it ends, the trigger (if still active) governs again with no gap, because `end` calls `arbitrate()` in the same turn and `TriggerController` coalesces only `step`, never arbitration.
- **Turn Off with something else still keeping the Mac awake** (lead r4; r3 product M3): after `turnOff`, if a rule is active the toast says "Rules can still keep your Mac awake." with **Turn Off “Desk dock”** (default) and **Pause Rules** (1 hour; R5-10); if only holds remain, "Terminal is still keeping your Mac awake." (holder names as in N17) with **End Command-Line Holds** (R5-10). While a manual session overrides an active rule, the detail line adds "Then “Desk dock” keeps it awake."; while holds exist under any governing source, it adds "Held by Terminal (2)".
- A tick (`Timer` added with `RunLoop.main.add(_:forMode: .common)`, N15; fires at `AwakeCountdown.nextChange` or at the earliest expiry of the manual session or any hold, tolerance 10%) recomputes `remaining`; at ≤ 0 the session ends `.timeUp`, an expired hold ends `.timeUp`. Ticks never drive correctness alone: expiry is also checked on wake, clock change, unlock, menu open and every arbitration.
- **untilIdle** (N9): while it runs, `taskQuiet` keeps CPUSampler (total CPU, every pid's rusage), DiskIOSampler and NetworkMonitor throughput active at 5 s. Each sample goes through `TaskQuiet.step`: the session ends `.tasksFinished` once `quietSeconds` (default 5 min) have passed with **no** busy sample (busy = any of busiest same-user process (own plus reaped-children CPU, R5-4) ≥ `topProcessPercent` of one core, ≥ `newProcesses` same-user pids first seen in the sample, total CPU ≥ `totalCPUPercent`, disk ≥ `diskKBps`, network ≥ `networkKBps`), never before `minimumHoldSeconds` (10 min) from start (R5-4); an unknown sample and every wake reset the quiet window, and the first delta after a wake is discarded. Detail line "Ends after 5 min with no activity · quiet for 2 min" (`TaskQuiet.quietFor`; r3 product minor 15). Display policy: the default options, as for every kind (R5-11). Optional cap ("At most", §4.3). Toast: "Awake ended: downloads and tasks finished."
- **Holds** (N17, §2.10): `ProcessWatch` (J) arms a kqueue `EVFILT_PROC`/`NOTE_EXIT` on the bound pid **first**, then re-reads `proc_pidinfo(pid, PROC_PIDTBSDINFO)`: the start time must equal the binding's and `pbi_uid == getuid()`; `kevent` returning `ESRCH`, a changed start time or another uid → refuse `.invalid` at start, end `.processExited` at restore. Exit → end `.processExited`. `.connection` holds also end when their CLI connection closes (EOF, a byte after the request, error, server stop). No process is spawned or signalled (lint rule 12 holds). **Holder name** (local UI only, never persisted, logged, exported or sent over the CLI): walk `pbi_ppid` from the bound pid (≤ 16 hops, same uid only) to the first process that is a regular `NSRunningApplication` and use its `localizedName` ("Terminal", "iTerm", "Xcode"); otherwise "the command line". The menu and status row group by name: "Held by Terminal (2)", "Held by Terminal and Xcode". If the bound process ends within 2 s of the start, the toast says "Awake stopped: the process it was holding for already ended." (parity M3). Each hold ends in history as one `process` entry with source `.commandLine`.
- whileApp: ends `.appQuit` when no running application has the bundle id (checked on terminate notifications and every arbitration); refuses to start if the app isn't running.
- Caps: task-bound kinds end `.timeUp` at their `deadline`; "Add 1 Hour" extends the cap (§5.3). Every hold has a cap (default 12 h, `--max` ≤ 24 h) that nothing extends. A CLI `untilIdle` start or an `awake preset` of an uncapped untilIdle preset gets `holdDefaultCapSeconds` (parity minor 7).
- **Reminders and toasts**: 5-minute reminder when a timed session that ran ≥ 15 min reaches 5 min left, "Awake ends in 5 minutes." with **Add 1 Hour** (consistency m4: one label everywhere); **8-hour reminder** once per indefinite manual session, "Awake has kept your Mac awake for 8 hours." with **Turn Off** / **Keep Going** (`ToastPresenter` gains `actions: [ToastAction]`, ≤ 2, code minor 11); an end toast for every non-user end ("Awake ended: battery is below 20%." / "…: Xcode quit."; app names only in local UI); guard refusals from the UI show a toast "Battery is below 20%." with **Start Anyway** (battery/LPM above the 5% hard floor only; never offered as a menu item: a refused menu start shows this toast (R5-10); it re-starts with the original request's source and gate event); "Awake was started from the command line." at most once per 10 minutes (also for the first hold in 10 minutes). Toasts are suppressed while locked, while the screensaver runs, off console, and while **presenting** (any display in a mirror set, or the frontmost app has a window covering a whole display — `CGWindowListCopyWindowInfo` bounds and owner PID only); a `screensaver.didstart` hint suppresses for at most 10 s unless ScreenSaverEngine is frontmost (security L4); suppressed toasts go to Recent Notices (confirmation toasts excepted). ToastPresenter changes are lead-owned (§6.2; `actions:` stubbed in step 0, implemented in step 2).
- **Last end**: after a non-user end, `runtime.lastEnd` shows "Ended at 3:12 AM: battery below 20%." in the Awake menu and Settings status row for 12 h (also a Recent Notices entry).
- **Persistence**: the manual session (without `overrideGuards`), the `.process` holds, rule suppressions, `pausedUntil` and guard memory are written to `SnapticAwakeStateV1` (`ConfigStore<AwakeRuntimeSnapshot>`, no admission hook) **on change only** (never per engine step), always as `state.value = snapshot(fromRuntime)`, a whole value built from memory; SessionController never mutates or reads back the adopted value (r3 code minor 10, security L4; Kit-side test that a snapshot written by another process while running has no effect until the next start). Loading: `AwakeRuntimeSnapshot.sanitized(now:)` (Kit: kinds clamped, the r3 security L3 bounds, other-boot sessions, holds and `until` suppressions dropped via the snapshot's `bootSession`, code R2-M3) and then `SessionController.restore(_:)` (pid, uid, guards with live facts; code R2-M8). On start (launch, relaunch, update, re-enable), `resumeAfterRestart` (default on) restores the session if not expired in the same boot; `.process` holds are always restored (their client already exited 0). A crash therefore loses nothing but the time Snaptic was down (assertions die with the process; [PA] §1.2).
- **Start at launch** (Advanced, default None): a preset id started once per process; the flag is `HostSignals.launchSessionStarted` (not a static), so re-enabling the module doesn't start it again.
- **Module stop / quit**: `stop()` releases all assertions synchronously, ends the session and every hold in history as `.moduleStopped`, and finishes held connections. It keeps the snapshot when `HostSignals.isTerminating` is true (set by `ModuleHost.shutdown()` before any module stops) so a relaunch resumes; otherwise (disable, Safe Mode) it clears the snapshot. Reset All Settings clears all three Awake stores with `isTerminating == false`.

### 2.6 Guards (G, Kit `SnapticKit/AwakeGuards.swift`, `GuardsController`)

```swift
package enum ThermalLevel: Int, Codable, Sendable, Comparable {
    case nominal, fair, serious, critical
    package static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }   // not synthesized for raw-value enums
}
package struct PowerFacts: Equatable, Sendable {
    /// Latched for the process lifetime (r3 security M3): true once IORegistry `AppleSmartBattery` exists or any
    /// internal-battery IOPS entry was seen; a later read with no battery entry is an unreadable read, not a desktop.
    package var batteryPresent: Bool
    package var onAC: Bool
    package var percent: Int?            // nil = unreadable (no internal-battery entry or no capacity)
    package var charging: Bool
    package var falling: Bool            // R5-6: PowerMath.falling over a 10-min window (a drop or current < 0, not recovered)
    package var lastRecovery: Double?    // R5-6: newest reading with charging or a percent rise (continuous)
    package var lowPowerMode: Bool
    package var thermal: ThermalLevel
    /// Lead r4/R5-6: battery present AND (not on AC OR falling within the 10-min window). An underpowered USB-C
    /// charger or hub that reports AC while the battery drains counts as discharging.
    package var discharging: Bool { get }
    package init(batteryPresent: Bool, onAC: Bool, percent: Int?, charging: Bool, falling: Bool, lastRecovery: Double?,
                 lowPowerMode: Bool, thermal: ThermalLevel)   // R5-6
}
// R5-6: PowerMath (J) is BatteryReading + fallingWindowSeconds + appending(_:to:) + falling(_:now:) + lastRecovery(_:);
// r4's falling(previous:now:) is gone.
package struct AwakeGuardsConfig: ConfigModel {
    package var batteryFloorEnabled: Bool        // true ("When the battery is low"); off leaves the 5% hard floor
    package var batteryFloor: Int                // 20; 5...50, step 5
    package var endOnAdapterDisconnect: Bool     // false
    package var endOnLowPowerMode: Bool          // false
    package init()
    package func sanitized() -> AwakeGuardsConfig
    /// Import rule (security M7): every field may only become stricter than `current`.
    package func monotonic(over current: AwakeGuardsConfig) -> AwakeGuardsConfig
}
package struct GuardMemory: Codable, Equatable, Sendable {      // persisted in the snapshot (same boot only)
    package var unreadableReads: Int = 0               // ≥ 2 on a latched battery = unreadable (activity, Drive Alive off)
    package var holding: AwakeEndReason? = nil         // blocks trigger starts until cleared
    package var heldSince: Double? = nil               // continuous clock
    package var warnedSerious: Bool = false
    package var assertionHoldUntil: Double? = nil      // continuous; §2.4 backoff
    package var assertionFailures: Int = 0
    package init()
    package init(from decoder: Decoder) throws         // lossy per field (rule 9, code sig)
    /// At load (security L2, code R2-M3): `holding`/`heldSince` are recomputed from live PowerFacts by the next
    /// `evaluate`, not trusted; on a boot mismatch everything except `warnedSerious` resets.
    package func reloaded(sameBoot: Bool) -> GuardMemory
}
package enum AwakeGuardVerdict: Equatable, Sendable { case allow, end(AwakeEndReason), warn(AwakeEndReason) }
package enum AwakeGuards {
    /// Fixed floor (N10, lead r3): on battery below this, every session and Drive Alive end, whatever the config,
    /// override or feature state says. Not stored, not exported, no kill switch.
    package static let hardFloorPercent = 5
    package static let hysteresisPercent = 5
    package static let thermalCooldownSeconds: Double = 600
    package static func evaluate(_ now: PowerFacts, previous: PowerFacts?, config: AwakeGuardsConfig,
                                 memory: GuardMemory, time: Double, active: Bool,
                                 overrideBattery: Bool) -> (verdict: AwakeGuardVerdict, memory: GuardMemory)
    /// Drive Alive and activity (both modes) may run only if this is true, in every mode (security M1, lead r4).
    package static func allowsBackgroundWork(_ now: PowerFacts, config: AwakeGuardsConfig, memory: GuardMemory) -> Bool
}
```
Rules (lead r4, r3 security M3): Macs where `batteryPresent` never latched (desktops) skip battery rules; battery rules apply while `discharging`, whatever `onAC` says; `percent < hardFloorPercent` while discharging → end `.batteryLow` always (no override, not even Start Anyway); `percent < floor` while discharging with the floor enabled → end `.batteryLow`; two consecutive reads with `percent == nil` on a latched battery → **unreadable**: treated as 0% for activity and Drive Alive (`allowsBackgroundWork` false, both stop), while the session's plain assertion continues, because it is harmless (macOS still sleeps the Mac at critically low battery whatever assertions exist, [PA] §1), with one toast "Snaptic can't read the battery level, so it stopped appearing active and keeping drives awake."; one readable reading clears it; AC → battery transition with `endOnAdapterDisconnect` → `.adapterDisconnected`; LPM on with `endOnLowPowerMode` → `.lowPowerMode`; `.critical` → end `.thermal` regardless of settings or features and hold for 10 min (evaluated in `SessionController` and `DriveAliveController` directly from `PowerMonitor`, not only through `GuardsController`, so no feature state can skip it); `.serious` → warn once per episode (no end option). Holding clears when battery ≥ floor + 5, or when `lastRecovery > heldSince` (a rise or charging; never on equal readings; R5-6); LPM off; thermal ≤ fair for 10 min. **Guards apply to every source** (manual, trigger, hold, CLI, restored); a battery end also ends every hold. `overrideBattery` is the session's one-shot **Start Anyway** (UI only, never CLI/trigger, never persisted, never below the hard floor); thermal critical is never overridable. `allowsBackgroundWork` is false below the hard floor while discharging, below the user floor while discharging (floor enabled), while the battery is unreadable on a Mac with a latched battery, and at `.critical`. Kit tests cover "AC but falling" and "battery entry missing after it was seen" (r3 security M3).

System behavior options (Kit `AwakeBehavior`, part of `AwakeSessionsConfig`; declared in `Config/ConfigAwakeSessions.swift`, G; consistency m13):

```swift
package enum UserSwitchEnd: String, Codable, CaseIterable, Sendable { case immediately, afterHour, never }
package struct AwakeBehavior: Codable, Equatable, Sendable {
    package var endOnSystemSleep: Bool          // false; any sleep while our assertion holds is lid/Apple-menu/low-battery/thermal
    package var userSwitchEnd: UserSwitchEnd    // .afterHour: off console > 1 h ends `.userSwitch` (security L5)
    package var endAfterLockedHours: Int?       // nil = Never; 1, 4, 12 → ends `.lockedTooLong` (security L5, OQ-7)
    package var keepDisplayOnWhileLocked: Bool  // false (C1)
    package var resumeAfterRestart: Bool        // true
    package var startAtLaunch: StableID?        // nil
    package init()
    package init(from decoder: Decoder) throws  // lossy per field (rule 9, code sig)
}
```

### 2.7 Triggers (G engine + Kit; J sources)

**Terms** (design M4): the UI says **rule** (a trigger) and **condition** (a criterion) everywhere ("Add Rule…", "Edit Rules…", "Delete Rule…", "All/Any of these conditions", "is / is not"); "automatic session" names the session a rule starts. Code keeps `AwakeTrigger`/`AwakeCriterion`.

**Kit model** (`SnapticKit/AwakeTriggers.swift`). Every enum with associated values below gets a **hand-written, type-tagged Codable** (`{"type":"subnet","cidr":"10.0.0.0/8"}`) in the same file; synthesized enum Codable is not used because its shape can't drop unknown kinds per entry. Nested enums are never flattened into their parent (code sig): a parent puts the child's whole object under the key `"condition"` (or `"match"` for `DisplayMatch`/`BluetoothMatch`), so every object has exactly one `"type"` key at its own level.

```swift
package enum TriggerMatch: String, Codable, CaseIterable, Sendable { case all, any }
package struct WeekdaySet: OptionSet, Codable, Hashable, Sendable {   // bit 0 = Sunday
    package let rawValue: UInt8
    package init(rawValue: UInt8) { self.rawValue = rawValue & 0x7F }
    package static let everyDay = WeekdaySet(rawValue: 0x7F)
}
package enum DisplayMatch: Equatable, Sendable {
    case anyExternal                                        // ≥ 1 online non-built-in display
    case specific(record: FingerprintRecord, name: String)  // salted tiers only; name sanitized ≤ 64
    case mirroring
}
package enum PowerCondition: Equatable, Sendable { case onAdapter, onBattery, charging, batteryAtLeast(Int) }
package enum AudioCondition: String, Codable, Sendable { case outputActive, microphoneActive }
package enum NetworkCondition: Equatable, Sendable {
    case subnet(cidr: String)                          // IPv4 or IPv6, validated
    case router(hash: String, label: String)           // "Connected to this network": salted SHA-256 of the router MAC
    case vpnConnected
}
package enum BluetoothMatch: Equatable, Sendable { case audio(uidHash: String, name: String), input(hash: String, name: String), anyAudio }
package enum AwakeCriterion: Equatable, Sendable {
    case app(bundleID: String, name: String, frontmost: Bool)
    case display(DisplayMatch)
    case power(PowerCondition)
    case schedule(days: WeekdaySet, startMinute: Int, endMinute: Int)   // minutes since midnight; end ≤ start = overnight
    case cpuAbove(percent: Int)                                          // 5...100
    case audio(AudioCondition)
    case idle(atLeastMinutes: Int)                                       // 1...480
    case volumeMounted(uuid: String, name: String)
    case usbDevice(vendor: Int, product: Int, serialHash: String?, name: String)
    case network(NetworkCondition)
    case networkActivity(atLeastKBps: Int)                               // 10...1_000_000
    case bluetooth(BluetoothMatch)
    package var kind: AwakeCriterionKind { get }
}
extension DisplayMatch: Codable { package init(from decoder: Decoder) throws; package func encode(to encoder: Encoder) throws }
extension PowerCondition: Codable { package init(from decoder: Decoder) throws; package func encode(to encoder: Encoder) throws }
extension NetworkCondition: Codable { package init(from decoder: Decoder) throws; package func encode(to encoder: Encoder) throws }
extension BluetoothMatch: Codable { package init(from decoder: Decoder) throws; package func encode(to encoder: Encoder) throws }
extension AwakeCriterion: Codable { package init(from decoder: Decoder) throws; package func encode(to encoder: Encoder) throws }

package struct AwakeCriterionEntry: Codable, Equatable, Sendable {
    package var criterion: AwakeCriterion; package var negated: Bool
    package init(_ criterion: AwakeCriterion, negated: Bool = false)
    package init(from decoder: Decoder) throws     // keys "criterion" (throws → entry dropped) and "negated" (lossy, false)
    package func encode(to encoder: Encoder) throws
}   // JSON {"criterion":{"type":"network","condition":{"type":"subnet","cidr":"10.0.0.0/8"}},"negated":false}
    // AwakeCriterion's own object: {"type":"app","bundleID":…,"name":…,"frontmost":false}; unknown type → dropped

package struct AwakeTrigger: Codable, Equatable, Sendable, Identifiable {
    package var id: StableID
    package var name: String                     // ≤ 64 scalars, TextSanitizer; empty → generated summary
    package var enabled: Bool
    package var match: TriggerMatch
    package var criteria: [AwakeCriterionEntry]  // 1...8; a trigger with 0 valid criteria is disabled by sanitized()
    package var options: AwakeSessionOptions     // sanitized(): every `nudge` → `declare` (rules never move the pointer, N10;
                                                 // r3 consistency m12)
    package var startDelaySeconds: Int           // 0...3600; cpu/networkActivity default 60
    package var endDelaySeconds: Int             // 0...3600; default 30 (hysteresis)
    package var resumeAfterManualEndMinutes: Int?   // nil = when the condition next becomes true
    package static let maxTriggers = 32, maxCriteria = 8
    package init(id: StableID, name: String, criteria: [AwakeCriterionEntry])
    /// Hand-written (N18, r3 code M6): `id` must decode as a StableID (else the rule is dropped); `criteria` through
    /// `LossyArray<AwakeCriterionEntry>`; every other field lossy with its default.
    package init(from decoder: Decoder) throws
    package func encode(to encoder: Encoder) throws
}
package struct AwakeTriggersConfig: ConfigModel {
    package var triggers: [AwakeTrigger]         // order = priority; pausedUntil is runtime state (snapshot), not config
    package init()
    package init(from decoder: Decoder) throws   // `triggers` via LossyArray: one unknown 0.4 rule drops only itself
    package func sanitized() -> AwakeTriggersConfig
}
```

**Facts and evaluation** (`SnapticKit/AwakeTriggerEngine.swift`):

```swift
// Each fact type has an explicit package init (code sig: J's app sources build them; memberwise inits are internal).
package struct DisplayFact: Equatable, Sendable {
    package var record: FingerprintRecord; package var isBuiltin: Bool
    package init(record: FingerprintRecord, isBuiltin: Bool)
}
package struct USBFact: Equatable, Sendable {
    package var vendor: Int; package var product: Int; package var serialHash: String?
    package init(vendor: Int, product: Int, serialHash: String?)
}
package struct NetworkFacts: Equatable, Sendable {
    package var addresses: [String]; package var routerHashes: Set<String>; package var vpn: Bool
    package init(addresses: [String], routerHashes: Set<String>, vpn: Bool)
}
package struct BluetoothFact: Equatable, Sendable {
    package var audioUIDHashes: Set<String>; package var inputHashes: Set<String>
    package init(audioUIDHashes: Set<String>, inputHashes: Set<String>)
}
/// nil = the source isn't running or hasn't produced a value yet ("unknown").
package struct CriterionFacts: Equatable, Sendable {
    package var runningApps: Set<String>?; package var frontmostApp: String??
    package var displays: [DisplayFact]?; package var mirroring: Bool?
    package var power: PowerFacts?
    package var minuteOfWeek: Int?               // 0..<10080, local time, computed by the app with Calendar.autoupdatingCurrent
    package var cpuPercent: Double?; package var audioOutput: Bool?; package var microphone: Bool?
    package var realIdleSeconds: Double?; package var volumes: Set<String>?; package var usb: [USBFact]?
    package var network: NetworkFacts?; package var throughputKBps: Double?; package var bluetooth: BluetoothFact?
    package init()
}
/// In memory only, continuous clock (code M2).
package struct TriggerHysteresis: Equatable, Sendable {
    package var trueSince: Double?; package var falseSince: Double?; package var active: Bool
    package init()
}
/// Persisted in the snapshot (continuous clock, same boot only: `until` entries are dropped on a boot mismatch,
/// `untilFalse` ones kept; code R2-M3).
package struct TriggerSuppression: Codable, Equatable, Sendable {
    package var until: Double?; package var untilFalse: Bool
    package init(until: Double?, untilFalse: Bool)
    package init(from decoder: Decoder) throws     // lossy per field (rule 9, code sig)
}
package struct TriggerStepResult: Equatable, Sendable {
    package var hysteresis: [StableID: TriggerHysteresis]
    package var suppressions: [StableID: TriggerSuppression]   // expired ones removed
    package var top: TriggerTop?
    package var nextDeadline: Double?                           // continuous instant of the next delay expiry
}
package enum TriggerEngine {
    /// true / false / nil (unknown). Negation of unknown stays unknown.
    package static func holds(_ entry: AwakeCriterionEntry, facts: CriterionFacts) -> Bool?
    /// all: every entry true (unknown → false). any: some entry true (unknowns ignored).
    package static func condition(_ t: AwakeTrigger, facts: CriterionFacts) -> Bool
    /// Advances hysteresis for every trigger and returns the governing candidate (first active in order).
    package static func step(_ triggers: [AwakeTrigger], facts: CriterionFacts, now: Double,
                             hysteresis: [StableID: TriggerHysteresis], suppressions: [StableID: TriggerSuppression],
                             paused: Bool, guardsHold: Bool) -> TriggerStepResult
    /// The user ended a trigger session: suppress per resumeAfterManualEndMinutes.
    package static func manualEnd(_ t: AwakeTrigger, now: Double) -> TriggerSuppression
    package static func requiredKinds(_ triggers: [AwakeTrigger]) -> Set<AwakeCriterionKind>
    /// Minutes of week (0..<10080) where some enabled schedule criterion flips. The app's Ticker turns each into a
    /// Date with Calendar.autoupdatingCurrent.nextDate (DST-correct) and wakes at the earliest, capped at 15 min.
    package static func scheduleBoundaries(_ triggers: [AwakeTrigger]) -> Set<Int>
    /// Sentence for list rows and the menu: "When Xcode is open and the power adapter is connected".
    package static func summary(_ t: AwakeTrigger) -> String
}
```

Engine rules (tested, normative): a trigger becomes active when its condition has held for `startDelaySeconds` and inactive when false for `endDelaySeconds`; disabled, suppressed, paused or guard-held triggers are never active (their hysteresis still advances so they resume correctly); the governing trigger is the first active one in list order (priority); a priority change takes effect at the next step without ending the session if the top stays active; `step` runs on every source change, **coalesced to one run per main-queue turn**, plus the Ticker (schedule boundaries, `nextDeadline`); after each step `TriggerController` caches `top` and calls `SessionController.arbitrate()` synchronously; a wake runs `step` only after a 5 s settle so displays, power and network sources reread. `pausedUntil` (wall time, **Pause Rules** "for 1 Hour" / "Until Tomorrow") lives in the snapshot; a clock change re-evaluates it.

**Specific display matching** (replaces Displays' per-display `preventSleep`): `DisplayPresence` builds a `FingerprintRecord` per online display via B's `DisplayIdentity.record(for:salt:)` from CG facts (vendor, model, serial, UUID via `CGDisplayCreateUUIDFromDisplayID`, built-in) — tiers t2, t3, t5 — and compares stored records with a new pure Kit helper `Fingerprint.matches(_ stored: FingerprintRecord, _ live: FingerprintRecord) -> Bool` (B; higher stored tiers that we can't compute don't conflict; `Fingerprint.match` needs a `DisplayKey` map Awake doesn't have). Awake therefore works with the Displays module off. The display picker in the trigger editor shows `NSScreen.localizedName` (or the Displays custom name when Displays runs, read-only from `DisplaysConfig.perDisplay[key].identity.customName`).

**Router and USB hashes**: SHA-256(`SnapticAwakeSalt` ‖ normalized value), salt = 32 random bytes in its own persistent-domain key, created on first use, never exported (same rules as `SnapticDisplaySalt`, R5.7). Labels ("Home", "Desk dock") are user-typed.

### 2.8 Criterion sources (J)

Each source conforms to:

```swift
@MainActor protocol AwakeServiceLifecycle: AnyObject {
    func activate(_ context: AwakeContext, lifetime: Lifetime)   // idempotent
    func deactivate()                                            // idempotent; releases ports, listeners, timers
}
@MainActor protocol CriterionSource: AwakeServiceLifecycle {
    static var kinds: Set<AwakeCriterionKind> { get }
    /// Writes this source's fields into the facts (nil while not ready).
    func contribute(to facts: inout CriterionFacts)
    /// Multicast (code M7): PowerMonitor, SystemEventsMonitor and IdleSampler have several consumers.
    /// The handler is dropped when `lifetime` ends.
    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void)
}
/// Lead, `Awake/AwakeContracts.swift`: the one fan-out implementation every source uses.
@MainActor final class ChangeFanout {
    init()
    func add(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void)
    func fire()
}
/// J, read synchronously by SystemEventsMonitor from CGSessionCopyCurrentDictionary() (security M2).
struct SessionFacts: Equatable, Sendable { var locked: Bool; var onConsole: Bool }

/// J (app, `Awake/Sources/ProcessWatch.swift`): the only user of EVFILT_PROC and proc_pidinfo in Awake.
@MainActor final class ProcessWatch: AwakeServiceLifecycle {
    init()
    /// proc_pidinfo(PROC_PIDTBSDINFO): nil when the pid is gone or unreadable.
    func facts(_ pid: Int32) -> (uid: uid_t, startTime: UInt64)?
    /// Arms kqueue EV_ADD EVFILT_PROC NOTE_EXIT (a DispatchSourceRead on the kq fd, main queue) FIRST, then re-reads
    /// facts: nil (refuse) on ESRCH, start-time mismatch or another uid. The handler runs once; `lifetime` ends it.
    func watch(pid: Int32, startTime: UInt64, lifetime: Lifetime, onExit: @escaping @MainActor () -> Void) -> Bool
    /// N17 holder name: first regular-app ancestor via pbi_ppid (≤ 16 hops, same uid), `localizedName`; nil → "the
    /// command line". Local UI only; never stored.
    func holderName(for pid: Int32) -> String?
    func activate(_ context: AwakeContext, lifetime: Lifetime)
    func deactivate()                            // every watch's handler runs with .processExited (§2.1 start order)
}
```

Kit math (J, consistency M7; `SnapticKit/CPUMath.swift`, `SnapticKit/NetworkMath.swift`, both tested):

```swift
package struct CPUTicks: Equatable, Sendable {      // host_statistics HOST_CPU_LOAD_INFO, UInt32 tick counters
    package var user, system, idle, nice: UInt32
    package init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)
}
/// `mach_timebase_info` (r3 code M2): rusage_info_v2 ri_user_time/ri_system_time are Mach absolute-time units, which
/// on Apple silicon are 24 MHz ticks (numer 125, denom 3), not nanoseconds; Intel reports 1/1.
package struct CPUTimebase: Equatable, Sendable {
    package var numer: UInt32; package var denom: UInt32
    package init(numer: UInt32, denom: UInt32)
    package func nanos(_ ticks: UInt64) -> UInt64      // multipliedFullWidth, no overflow trap
}
/// One pid's counters at one sample (CPUSampler builds them from proc_listallpids + proc_pid_rusage).
package struct ProcessCPUSample: Equatable, Sendable {   // R5-4
    package var pid: Int32
    package var startAbs: UInt64     // ri_proc_start_abstime (Mach absolute units, same call)
    package var cpuTicks: UInt64     // user + system + child user + child system (Mach units)
    package init(pid: Int32, startAbs: UInt64, cpuTicks: UInt64)
}
package enum CPUMath {
    /// Busy share of all cores, 0...100; wrapping UInt32 subtraction; nil when no ticks elapsed.
    package static func load(prev: CPUTicks, now: CPUTicks) -> Double?
    /// One process's CPU as % of one core (100 = one core) from rusage tick deltas over a wall delta (s).
    package static func processPercent(prevTicks: UInt64, nowTicks: UInt64, seconds: Double,
                                       timebase: CPUTimebase) -> Double?
    /// The busiest same-user process and the churn over one window (pid + start time identify a process, so a reused
    /// pid is a new process). A process first seen in this sample that started inside the window counts its whole CPU
    /// time; one that started earlier (first sample of the session) is skipped. `newProcesses` counts first-seen
    /// processes that started inside the window.
    package static func window(prev: [ProcessCPUSample], now: [ProcessCPUSample], windowStartAbs: UInt64,   // R5-4
                               seconds: Double, timebase: CPUTimebase) -> (top: Double?, newProcesses: Int)
}
package struct InterfaceCounters: Equatable, Sendable {   // one if_msghdr2 row (NET_RT_IFLIST2, if_data64)
    package var name: String; package var bytesIn: UInt64; package var bytesOut: UInt64
    package init(name: String, bytesIn: UInt64, bytesOut: UInt64)
}
package enum NetworkMath {
    package static func parseCIDR(_ s: String) -> (address: [UInt8], prefix: Int)?      // IPv4 or IPv6
    package static func cidrContains(_ cidr: String, address: String) -> Bool
    package static func normalizeMAC(_ s: String) -> String?                           // "aa:bb:…" lowercase
    /// 64-bit counter delta; nil on a reset (now < prev).
    package static func byteDelta(prev: UInt64, now: UInt64) -> UInt64?
    /// KB/s over all non-loopback interfaces (`lo*` excluded); tunnels (`utun*`, `ipsec*`, `ppp*`) count only when no
    /// physical interface moved bytes in the window, so VPN traffic isn't counted twice (code R2-M10, parity M2).
    package static func throughputKBps(prev: [InterfaceCounters], now: [InterfaceCounters], seconds: Double) -> Double?
}
package enum DiskMath {   // J, `SnapticKit/DiskMath.swift`
    /// KB/s from per-driver "Bytes (Read)" + "Bytes (Write)" keyed by `IORegistryEntryGetRegistryEntryID` (r3 code
    /// minor 6): drivers present in both samples contribute their delta; a driver that appeared or vanished (hot-plug)
    /// contributes nothing, so it is neither a reset nor a spike; a counter that went down counts 0 for that driver.
    package static func throughputKBps(prev: [UInt64: UInt64], now: [UInt64: UInt64], seconds: Double) -> Double?
}
```

**Notifications are hints, never truth** (security M2): `com.apple.screenIsLocked/Unlocked` and `com.apple.screensaver.didstart/didstop` are distributed notifications any process can post. They only cause a re-read. `SystemEventsMonitor.sessionFacts()` reads `CGSSessionScreenIsLocked` (an undocumented dictionary key: HW-1 confirms it on 14–27; code minor 12) and `kCGSSessionOnConsoleKey` from `CGSessionCopyCurrentDictionary()` at the moment of use, and `SessionController.arbitrate()` and `ActivityController` call it before every arbitration and every activity action. Screensaver: a `didstart` hint only suppresses (fail-safe) and expires after 10 s; "running" holds while `NSWorkspace.frontmostApplication?.bundleIdentifier == "com.apple.ScreenSaver.Engine"`, which a notification can't fake (security L4).

| Source | Period / events | Budget | Notes |
|---|---|---|---|
| PowerMonitor | `kIOPSNotifyPowerSource`, `kIOPSNotifyPercentChange` (`import notify`), `NSProcessInfoPowerStateDidChange`, `thermalStateDidChangeNotification` (both `queue: .main`) | events only | Always active with `sessions` (guards need it). `@Published var facts: PowerFacts` + `observe` |
| SystemEventsMonitor | `NSWorkspace` will/didSleep, screensDidSleep/Wake, sessionDidResign/BecomeActive; distributed lock/screensaver hints; `NSSystemClockDidChange`, `NSSystemTimeZoneDidChange` (→ `NSTimeZone.resetSystemTimeZone()`), `NSCalendarDayChanged`; lid via `IOPMrootDomain` interest (`AppleClamshellState`, `AppleClamshellCausesSleep`, [PA] §2) | events only | `sessionFacts()` reads the session dictionary on demand |
| AppMonitor | launch/terminate/activate notifications | events only | Regular + accessory apps; bundle ids only; picker list sorted by name, Snaptic excluded |
| DisplayPresence | `CGDisplayRegisterReconfigurationCallback` (CallbackTarget), debounced 1 s | events only | Removes callback in `deactivate` |
| USBWatcher | first-match + terminated notifications on `IOUSBHostDevice` | events only | Iterators drained at arm; serial hashed immediately, raw never stored |
| VolumeMonitor | didMount / didUnmount / willUnmount; DiskArbitration description per mount (`DASessionCreate`, `DADiskCreateFromVolumePath`, `DADiskCopyDescription`, synchronous IPC: run on a private utility queue, results hop to main; code minor 12) | events only | Builds `DriveAlivePolicy.VolumeFacts` (§2.9), including the BSD name (`kDADiskDescriptionMediaBSDNameKey`) the write path re-checks |
| AudioMonitor | property listeners on default output/input `DeviceIsRunningSomewhere` + default-device change | events only | HAL calls and listeners on a private serial queue (they can block > 50 ms); each listener stored as a typed `AudioObjectPropertyListenerBlock` so Remove gets the same block, `[weak self]`; moves its listener when the default device changes; publishes on main. No input stream is ever opened |
| CPUSampler | 5 s timer; 10 s window average (total); per-process sampling only while `taskQuiet` | ~10 µs/sample total; ≤ 5 ms with every pid | `host_statistics` tick deltas → `CPUMath.load`; count = `MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride` (the macro isn't imported); cached host port. Per process (N9, lead r4, r3 code M2): every 5 s, `proc_listallpids` + `proc_pid_rusage(RUSAGE_INFO_V2)` for **every** pid; `ri_user_time + ri_system_time + ri_child_user_time + ri_child_system_time` deltas (R5-4: a long-lived `make` or shell carries its reaped children) converted with `mach_timebase_info` (`CPUTimebase`, read once) → `CPUMath.window` (busiest same-user process, new-process churn). Processes too short to appear in any sample (a `make -j1` stream of 1–3 s `clang`s) are counted through their parent's child time (R5-4), plus aggregate system CPU (`totalCPUPercent`) and process-count churn (`newProcesses`). Processes of other users aren't readable and are skipped (so root's `mds_stores`/`kernel_task` bursts don't count). The previous sample's pid → (start time, ticks) map is transient and in memory only, dropped when the session ends; nothing else is kept, never a name or list (§3.6); no TCC |
| DiskIOSampler | 5 s timer only while `taskQuiet` | ~50 µs/sample | `IOServiceGetMatchingServices(IOBlockStorageDriver)`, each driver's `Statistics` dictionary "Bytes (Read)" + "Bytes (Write)" keyed by registry entry ID → `DiskMath`; read-only registry properties, no device opened, no TCC; parity M2. The counters are system-wide, so root Spotlight and Time Machine I/O count as busy (stated in HW-23 and the help text; r3 code minor 6) |
| IdleSampler | 10 s timer (5 s while `keepOnWhileActive`, activity or `idle` criteria run) | trivial | per-type `.hidSystemState` seconds (key down, flags changed, left/right/other mouse down, scroll wheel, mouse moved; never `anyInput`), minimum taken, turned into **last real input** by `IdleMath` (§2.9) so Snaptic's own nudges and declarations never count |
| NetworkMonitor | `SCDynamicStore` notifications for IPv4/IPv6 global + interface keys; router hash re-read on change; throughput 5 s timer only when `networkActivity` or `taskQuiet` is needed | events + 5 s | `sysctl NET_RT_IFLIST2` with `if_data64` (32-bit `if_data` wraps within seconds at multi-gigabit) → `NetworkMath.throughputKBps` (loopback excluded, tunnels not double-counted); read-only; no sockets; ARP/route via `sysctl` [HW-11] |
| ProcessWatch | kqueue `EVFILT_PROC`/`NOTE_EXIT` per held pid | events only | §2.5 holds; one kqueue per hold (≤ 8), closed in the cancel handler |
| BluetoothPresence (Beta) | CoreAudio device-list listener (AudioMonitor's queue); `IOServiceAddMatchingNotification(IOHIDDevice)` filtered by `Transport` | events only | Never opens a HID device (Input Monitoring) [HW-10] |

### 2.9 Activity simulation and Drive Alive (J)

**ActivitySimulator** (`Awake/Sources/ActivitySimulator.swift`): the only file allowed to call `IOPMAssertionDeclareUserActivity`, to release that declaration's id, and to post `CGEvent`s (lint L1/L2).

```swift
package enum ActivityDecision: Equatable, Sendable { case skip, declare, nudge }   // `.skip`, not `.none` (code sig)
package struct ActivityInputs: Equatable, Sendable {      // Kit (code M13)
    package var mode: AwakeActivityMode         // governing session's effective mode (.off when none)
    /// `ActivityPolicy.nudgeAllowed(…)` below (r3 consistency M4): computed in Kit, never by the app.
    package var nudgeAllowed: Bool
    package var screenLocked: Bool              // session dictionary, read now
    package var onConsole: Bool                 // session dictionary, read now
    package var screensaverRunning: Bool        // ScreenSaverEngine frontmost, or a didstart hint < 10 s old
    package var displaysAsleep: Bool            // CGDisplayIsAsleep(main)
    package var switcherVisible: Bool           // HostSignals
    package var secondsSinceUserInput: Double   // IdleMath over key/click/scroll types; only skips while the user works
    /// Snaptic's continuous clock: now − gate.activitySince (0 before the first action). Never system idle,
    /// which Snaptic's own declarations reset (security M2, N10).
    package var activityElapsedSeconds: Double
    package var stopAfterSeconds: Double        // AwakeActivityConfig.stopAfterHours · 3600, 1...8 h
    package var pointerEdgeDistance: Double?    // points to the nearest display edge (nudge only)
    package init(mode: AwakeActivityMode, nudgeAllowed: Bool, screenLocked: Bool, onConsole: Bool,
                 screensaverRunning: Bool, displaysAsleep: Bool, switcherVisible: Bool, secondsSinceUserInput: Double,
                 activityElapsedSeconds: Double, stopAfterSeconds: Double, pointerEdgeDistance: Double?)
}
package enum ActivityPolicy {   // Kit, J, tested truth table
    package static let intervalSeconds: Double = 60       // fixed (parity minor 14)
    package static let edgeMarginPoints: Double = 2       // security L1: hot corners, Dock, full-screen menu bar
    /// skip unless: mode ≠ off, unlocked, on console, no screensaver, displays awake, switcher hidden,
    /// secondsSinceUserInput ≥ interval, activityElapsed < stopAfter. nudge additionally needs nudgeAllowed and
    /// edge distance > margin; otherwise a nudge request degrades to declare.
    package static func decide(_ i: ActivityInputs) -> ActivityDecision
    /// The N10 rule in one place (r3 consistency M4, lead r4): true only when pointerNudge is effective, Accessibility
    /// preflight passes, the governing source is a manual session, and `gate.uiStartedInProcess && gate.pointer ==
    /// .allowed`. False for trigger, hold, CLI, launch, restored and resumed sessions and for an unconfirmed hotkey start.
    package static func nudgeAllowed(governing: AwakeGoverning, gate: AwakeActivityGate, pointerNudgeEffective: Bool,
                                     accessibility: Bool) -> Bool
    /// True when a nudge would act except for the hotkey confirmation (gate `.askOnFirstUse`): ActivityController then
    /// calls `SessionController.requestPointerConfirmation()`.
    package static func needsPointerConfirmation(_ i: ActivityInputs, gate: AwakeActivityGate) -> Bool
}
package enum IdleMath {         // Kit, J
    package static let echoSeconds: Double = 1
    /// HID idle resets of the mouse-moved type within echoSeconds after one of our nudges, and any reset within
    /// echoSeconds after one of our declarations, are not real input (security L1/M2, code M8).
    package static func lastRealInput(previous: Double, now: Double, hidIdleSeconds: Double,
                                      nudgeTimes: [Double], declareTimes: [Double]) -> Double
}

@MainActor final class ActivitySimulator: AwakeServiceLifecycle {
    init()
    func perform(_ decision: ActivityDecision)          // ActivityController calls it once per interval
    func stop()                                         // releases the DeclareUserActivity id
    private(set) var recentNudges: [Double] = []        // continuous times, last 10, for IdleMath
    private(set) var recentDeclarations: [Double] = []  // continuous times, last 10, for IdleMath
    func activate(_ context: AwakeContext, lifetime: Lifetime)
    func deactivate()
}
```
`declare` calls `IOPMAssertionDeclareUserActivity("Snaptic: activity", kIOPMUserActiveLocal, &id)` reusing `id` and releases it on `stop()`. It turns the display on ([PA] §1.4), so it never runs while the displays are asleep. `nudge` posts one `mouseMoved` of +1 pt then −1 pt at the current location from `CGEventSource(stateID: .privateState)` via `.cghidEventTap`, with `eventSourceUserData = 0x534E5054` ('SNPT') so Snaptic's own taps (switcher hover-select) ignore it; `CGPreflightPostEventAccess()` before every post; never posts key, click or scroll events. Whether a private-state source or a declaration resets `.hidSystemState` idle is HW-5/HW-6; correctness is independent of the answer because the cap runs on Snaptic's clock.

**The cap** (N10, security M2): `ActivityController` calls `SessionController.noteActivityActed(now:)` the first time it acts, which sets the gate's `activitySince` (continuous); activity stops (the session continues) once `activityElapsedSeconds ≥ stopAfterSeconds` (default 1 h, Advanced 1–8 h), so an unattended unlocked Mac reaches its idle lock. Only a new direct UI start (`.uiStart`, incl. choosing the running preset again) or an allowed hotkey confirmation clears `activitySince`; once the cap is reached the detail text says "Stopped appearing active after 1 hour."; real input does not reset it (it can't be told apart from our own declarations on every OS). Trigger sessions (declare only) cap the same way, and the counter is **carried** across back-to-back governing sessions, so adjacent schedule rules can't chain 1 h caps; it resets only after 15 min with nothing governing, counted from the last time anything governed, whatever the source (R5-7; r3 security L5). A relaunch starts a new count (the gate isn't persisted); that bounds a no-TCC declaration, not a grant, and §3.3 calls the cap a UX bound for that case. While activity acts, detail text says "Appearing active" / "Moving the pointer" in the Awake menu and the Settings status row. Copy (Settings): "Appear active — Keeps apps from marking you as away while a session runs." / "Move the pointer slightly — Moves the pointer 1 point and back. Only for sessions you start in Snaptic. Needs Accessibility."

**DriveAliveService** (`Awake/Sources/DriveAliveService.swift`):

```swift
@MainActor final class DriveAliveService: AwakeServiceLifecycle {
    struct VolumeState: Equatable { let uuid: VolumeUUIDKey; let name: String; var lastWrite: Date?; var lastError: DriveAliveError? }
    @Published private(set) var volumes: [VolumeState] = []   // code sig: default + init()
    init()
    /// Writes start/stop per volume; at most one write in flight per volume (the first open() may block on the
    /// Removable Volumes prompt; queued ticks coalesce).
    func setTargets(_ uuids: Set<VolumeUUIDKey>, interval: TimeInterval)
    func removeKeepAliveFile(_ uuid: VolumeUUIDKey, completion: (@MainActor (DriveAliveError?) -> Void)? = nil)   // when the user turns a volume off
    func activate(_ context: AwakeContext, lifetime: Lifetime)
    func deactivate()
}
package enum DriveAliveError: String, Codable, Sendable, CaseIterable { case notEligible, mountChanged, notOurFile, ioError, denied, removingInTheWay }
package enum DriveAlivePolicy {   // Kit, J, tested
    package struct VolumeFacts: Equatable, Sendable {
        package var isInternal, isRootFileSystem, isReadOnly, isLocal, isDiskImage, isTimeMachine, isBrowsable: Bool
        package var inBootContainer: Bool
        package var fileSystem: String          // f_fstypename
        package var bsdName: String             // "disk4s1" from DiskArbitration; the write path compares f_mntfromname
        package init(isInternal: Bool, isRootFileSystem: Bool, isReadOnly: Bool, isLocal: Bool, isDiskImage: Bool,
                     isTimeMachine: Bool, isBrowsable: Bool, inBootContainer: Bool, fileSystem: String, bsdName: String)
    }
    package static let allowedFileSystems: Set<String> = ["apfs", "hfs", "exfat", "msdos"]   // allowlist (security M5)
    package static func isEligible(_ v: VolumeFacts) -> Bool
    package static let fileName = ".snaptic-keepalive"
    package static let fileSize = 8
    package static let intervalRange: ClosedRange<Int> = 30...600
    /// C9 + N1 + security M1/L1 (R5-14: a trigger session passes `.rule`, the holds-only state `.commandLine`, nothing
    /// governing nil): never for sessions whose (restore-preserved) source is `.commandLine`, never when
    /// guards forbid background work (hard floor, user floor, unreadable battery, critical heat).
    package static func shouldWrite(sessionActive: Bool, sessionSource: AwakeSessionSource?, evenWithoutSession: Bool,
                                    backgroundWorkAllowed: Bool, uiConfirmedFirstWrite: Bool) -> Bool
}
```
Eligibility facts come from the live mount and DiskArbitration: `isDiskImage` = `kDADiskDescriptionDeviceModelKey == "Disk Image"` or an `IOHDIXController` ancestor; `inBootContainer` = the volume's APFS container is the boot volume's container (every volume in it is excluded); `isLocal` from `statfs` `MNT_LOCAL`, and the file-system allowlist excludes FSKit/macFUSE/network types. Write procedure on a private serial `DispatchQueue(label: "snaptic.drivealive", qos: .utility)` (security M5):
1. Resolve the root from the current mount list by UUID (never from config).
2. `dirfd = open(root, O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)`.
3. `fstatfs(dirfd)`: `f_mntonname == root`, `f_fstypename ∈ allowedFileSystems`, `f_flags` has `MNT_LOCAL` and has neither `MNT_RDONLY` nor `MNT_ROOTFS`, and `f_mntfromname` equals `/dev/` + the `bsdName` whose DiskArbitration description was judged eligible (a crafted image that clones a UUID has another BSD name; a remount re-runs DiskArbitration; security L3); `fgetattrlist(dirfd, ATTR_VOL_UUID)` equals the configured key. Any mismatch → `.mountChanged`, skip.
4. `fd = openat(dirfd, fileName, O_WRONLY|O_CREAT|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK, 0600)`; `fstat(fd)`: regular file, owner `getuid()`, `st_nlink == 1`, size ≤ 64, `st_dev` equal to the directory's `st_dev`.
5. Write 8 bytes (UInt64 timestamp) at offset 0, `ftruncate(8)`, `fcntl(F_FULLFSYNC)`, close both fds; the result hops to main.

Any check failure → that volume is skipped and the Drives row shows "Can't keep this drive awake" with the reason; no retry until remount. Stop on `willUnmount` (before eject). `removeKeepAliveFile` uses the same steps 1–3, then `fstatat` + `unlinkat(dirfd, fileName, 0)` only if the file passes step 4's checks and is exactly 8 bytes. The **first** write to a volume happens only right after the user turns that volume on in Drives (so the Removable Volumes prompt follows a UI action, security M3); that write sets `DriveAliveVolume.firstWriteDone`, and until it is set `uiConfirmedFirstWrite` is false and the volume waits. Volumes are chosen in the UI and stored by UUID only (lead r3). A config change made outside Snaptic still takes effect, including `firstWriteDone`; the worst case is an unprompted Removable Volumes dialog the user can decline (§3.2 residual). Info.plist gets `NSRemovableVolumesUsageDescription` = "Snaptic writes a tiny hidden file to the drives you choose so they don't spin down." (lead). Package.swift links DiskArbitration (lead).

### 2.10 Automation (G, `AwakeAutomation`)

Hotkeys (`AwakeActionID`, owner "Awake", via `GlobalHotkeys`, all unbound by default): `awake.toggle` (Keep Awake on/off with the default preset; off = `turnOff`), `awake.keepDisplayOn`, `awake.preset1…4`, `awake.pauseAutomatic` (shortcut title "Pause or Resume Rules", since it does both; raw value kept). A hotkey start is `.hotkeyStart` for the activity gate (§2.3, §2.5).

CLI verbs (registered only while `commandLine` is effective and the host CLI is on). `start`, `hold`, `stop` and `extend` share a 1 request/s limit (security L3), on top of the global 20/s. Arguments go through `AwakeCommandGrammar` (G, Kit, consistency M7):

```swift
package enum AwakeCommand: Equatable, Sendable {
    case status(json: Bool)
    case start(AwakeDurationRequest?, displayMaySleep: Bool)     // nil = 1 h (C10)
    case hold(pid: Int32?, maxSeconds: Int?)                     // --pid N (> 1), --max <duration> (≤ 24 h)
    case preset(PresetSelector)
    case extend(seconds: Int)
    case stop
    case pause(seconds: Int?)                                    // ≤ 24 h, nil = 1 h
}
package enum PresetSelector: Equatable, Sendable { case index(Int), name(String) }   // 1-based; name ≤ 64 scalars
package enum AwakeCommandGrammar {
    /// verb is the word after "awake"; flags "--pid", "--max", "--display-may-sleep" (r3 product minor 16; every flag
    /// is a `--` word); numbers via AwakeDurationGrammar limits (≤ 7 digits, no sign, no exponent). nil = usage error
    /// (exit 2). Never traps (seeded fuzz).
    package static func parse(verb: String, args: [String]) -> AwakeCommand?
    /// `awake status` line; ISO end time hand-formatted from explicit UTC components (N12, code minor 10).
    package static func statusLine(_ s: AwakeStatusFacts) -> String
    package static func statusJSON(_ s: AwakeStatusFacts) -> String
    /// First reply line of a hold, with the actual cap ("at most 12 h", "at most 3 h"; r3 consistency m5).
    package static func holdReply(pid: Int32?, capSeconds: Int) -> String
}
package struct AwakeStatusFacts: Equatable, Sendable {
    package var active: Bool; package var source: AwakeStatusSource?; package var kind: AwakeHistoryKind?
    package var display: AwakeDisplayPolicy?; package var endUnix: Double?; package var remaining: Double?
    package var triggerNumber: Int?; package var holdPIDs: [Int32]
    package init(active: Bool, source: AwakeStatusSource?, kind: AwakeHistoryKind?, display: AwakeDisplayPolicy?,
                 endUnix: Double?, remaining: Double?, triggerNumber: Int?, holdPIDs: [Int32])
}
package enum AwakeStatusSource: String, Sendable { case manual, automatic, holds }
```

| Verb | Policy | offOnly | Behavior |
|---|---|---|---|
| `awake status` | read | — | `inactive` or `active\tmanual|automatic|holds\t<kind>\t<display policy>\t<ISO end or ->\t<remaining s>\t<hold count>`; kinds `indefinite|duration|until|app|idle|process|automatic`; `--json` object adds `"holds"` (count) and `"pids"` (numbers, never names; parity M3); no app names, no process or holder names, rule *numbers* only |
| `awake start [<duration grammar>] [--display-may-sleep]` | low | false | `AwakeDurationGrammar`; **no argument = 1 h**; `indefinite`/`forever` refused (exit 4, "Use the menu or `awake hold`"); `idle` = Until Downloads and Tasks Finish (cap 12 h); options are the configured defaults, and pointer movement never acts for a CLI session (N10; r3 consistency M3: no nudge refusal); refused while a UI-started session runs (`.uiSessionRunning`); guards apply (exit 4 with reason) |
| `awake hold [--pid N] [--max <duration>]` | low | false | Adds a holder (N17, below); cap = `--max` (≤ 24 h) or 12 h; never refused because a UI session runs; refused at 8 holds (`.holdLimit`, exit 4); guards apply |
| `awake preset <n|name>` | low | false | Refused if the preset is Until Turned Off, or while a UI-started session runs; an uncapped untilIdle preset gets the 12 h cap; a nudge preset runs and declares only (N10) |
| `awake extend <duration>` | low | false | Manual timed or capped sessions only (holds have `--max`; nothing extends a hold) |
| `awake stop` | low | true | Ends the manual session; a trigger session is suppressed as a manual end; holds end with their own clients |
| `awake pause [<duration>]` | low | true | Pauses rules (default 1 h, ≤ 24 h) |

**`awake hold`** (lead r3/r4; parity M3, security M4, code R2-M9, consistency M1, r3 product M4). Snaptic never runs the caller's command. Holds stack (N17): each one is a holder beside the manual session, rule sessions and other holds; the Mac stays awake while any holder exists; when nothing else governs, the hold stack governs (N3) with a system assertion. Two forms:
- **Default (no `--pid`)**: the `snaptic` client itself is the hold. The server binds the holder to `HoldBinding.connection(pid: peer.pid, startTime: peer.startTime)`, where `peer` is the connection's `ControlPeer` (below), arms ProcessWatch on that pid (failure → `.invalid`, "Snaptic couldn't identify the caller.", exit 4), replies with `holding: true` and the first line `holdReply` ("Holding until this command ends (at most 12 h). Press Control-C to stop.") and **keeps the connection open**. The client prints and flushes that line, keeps reading and never exits on its own; the hold ends when the connection reaches EOF (the client exits, is killed or its terminal closes; the kernel closes the socket), when any byte arrives after the request, when `ProcessWatch` sees the peer pid exit, at the cap, when the user chooses **End Command-Line Holds** or turns Keep Awake off while holds govern (R5-10), when a guard ends sessions, or when Snaptic stops. When the server ends it, it writes a final line ("Awake hold ended: time is up." etc.) and closes; the client prints it and exits 0 (5 when Snaptic quit, or on EOF without a final line).
- **`--pid N`**: binds to `HoldBinding.process(pid: N, …)`; the server checks N > 1, `pbi_uid == getuid()` and reads N's start time, arms `ProcessWatch` first and re-verifies (security M4), replies `holdReply(pid: N, …)` ("Holding while process N runs (at most 12 h).") and closes; the client exits 0 immediately. The holder survives a Snaptic relaunch (pid + start time re-verified at restore).
- Limits: at most `AwakeHold.maxHolds` (8) holders of both forms; held connections use their own slot pool (`maxHeldConnections = 8`) and never count against the 4 request slots; a hold never replaces anything. Besides its own end conditions, a user Turn Off while the hold stack governs ends it (the client prints "Awake hold ended in Snaptic." and exits 0), and so does `commandLineOff` (R5-10, R5-14). A Turn Off while another source governs leaves holds running and says so (§2.5).

Usage (README, step 5), with the parent-shell pitfall explained:
```sh
# In a script: hold for as long as this script's shell runs
snaptic awake hold --pid $$
# Around one command in an interactive shell (a subshell, so the trap doesn't stay)
( snaptic awake hold & hold=$!; trap 'kill $hold 2>/dev/null' EXIT INT TERM; make release )
```
Control-C (review7 awake M1): a background job in a shell without job control inherits SIGINT and SIGQUIT ignored, so
in holding mode the client resets both to default (selftest-control-server case 12), and the README examples add the
`trap`. Pitfall: `make` recipe lines, `npm run` steps, CI step runners and agent tool calls run each line in a fresh `sh -c` that exits as soon as the line ends. There, `--pid $$` names a shell that exits at once (the hold ends within milliseconds; the toast says so, the reply only says it holds), and a backgrounded `hold &` left behind by one line keeps holding after the work is done, until its cap. Put start, work and `kill` in **one** shell (one recipe line joined with `&&`, `.ONESHELL:`, or a script file), pass `--pid` of a process that lives as long as the work, or use `snaptic awake start 2h`. CI keeps `caffeinate -w` as before.

**ControlServer contract change** (A, step 1; `Core/ControlServer.swift`, `Core/ControlCommandRegistry.swift`, `Core/CLIClient.swift`, Kit `KitControl.swift`; consistency M1, code R2-M9, r3 code M3 and sig rows, r3 security L1/L2; lead r4):
```swift
/// Best effort, not identity (r3 security L1): LOCAL_PEERPID reports the socket's last owner, which an inherited or
/// SCM_RIGHTS-passed fd changes, and a client can write its request and exit before accept. Read on the accepted fd
/// right after getpeereid (uid from getpeereid), before the request line is read; start time from
/// SNProcess.startTime(for:) (same µs epoch as HoldBinding). Never from the request; ControlRequest gains no field.
/// A connection hold's authority is the connection itself: EOF ends it whatever the pid does.
struct ControlPeer: Equatable, Sendable { let pid: pid_t; let uid: uid_t; let startTime: UInt64? }
/// Created by the listener for EVERY connection (the listener can't know `holds`: the registry lives on main; r3 code
/// sig row). Dispatch passes it to the handler only when the entry has `holds: true`, and turns a `holding` reply
/// from any other verb into an ordinary close.
final class ControlHold: @unchecked Sendable {
    var isClosed: Bool { get }                                 // the handler checks it after arming ProcessWatch
    /// EOF, a byte after the request, read/write error, ping failure, server stop; called exactly once, on main.
    /// Registered after the close happened → fires on the next main-queue turn.
    func onClose(_ handler: @escaping @MainActor () -> Void)
    func finish(_ final: ControlResponse)                      // writes one more line, closes; idempotent
}
struct ControlContext { let peer: ControlPeer; let hold: ControlHold? }   // hold non-nil only for holds: true verbs
// ControlCommandRegistry.Handler becomes  @MainActor (ControlRequest, ControlContext) async -> ControlResponse
// register(_:policy:offOnly:cliAllowed:holds: Bool = false, summary:lifetime:_:); existing call sites keep compiling
// through an overload that takes the old one-argument handler (removed at the step-3 exit).
// ControlListener.Handler becomes (ControlRequest, ControlPeer, ControlCancellation, ControlHold, Reply) -> Void.
// R5-5: dispatch(_:peer:hold:skipConfirmationAllowed:), ControlServer.start(socketPath:), holdPingInterval, sendHeld(_:_:).
// KitControl: ControlResponse gets a hand-written Codable (`c.lossy(.holding, false)`; the synthesized one would make
// the new key required) and `init(…, holding: Bool = false)`; `jsonReply` keeps `holding`.
// KitControl: maxHeldConnections = 8, holdPingSeconds = 300.
```
Connection rules (normative, A; tested on the macOS job):
- **Slots.** The 4 request slots are released in `onFinish` as today. A `holding` reply moves the connection from the request pool to the held pool on the listener queue: `active -= 1` exactly once and `held += 1`; its later finish decrements `held` only (no double release); `assert(active >= 0 && held >= 0)`. The old request's finish and the hold registration are `queue.async`'d in that order. A holding reply while `held == 8` becomes the refusal "Snaptic is already holding for 8 commands." (exit 4) and closes that connection's `ControlHold`, so SessionController ends the hold it just added (R5-5).
- **After the handshake** there is no read timeout. `readAvailable` treats any byte after the request line as a close, including bytes after the newline in the first chunk (R5-5) (a held client can't stream data and keep the queue busy); the EOF branch (where `cancellation` is nil) calls the hold's close; write errors close.
- **Ping.** Every `holdPingSeconds` the server writes `{"ping":true}` plus a newline on each held connection; a write failure closes it. Pings and final lines use `sendHeld`: one non-blocking attempt, and EAGAIN or a short write closes the hold (R5-5). `CLIClient` ignores ping lines.
- **Client.** `CLIClient.readReply` keeps the bytes after the first newline (no drop), prints and `fflush`es each line, never writes after the request and never half-closes (`shutdown(SHUT_WR)` is banned in CLIClient); EOF without a final line exits 5.
- **CLI turned off / module stop.** The verb's `lifetime.onEnd` finishes every held connection ("Awake was turned off.").
- **Tests** (R5-5: run by `scripts/selftest-control-server.sh` against `--selftest-control-server` in CI): hold, then 4 normal requests accepted and a 5th gets "busy"; 8 holds, the 9th refused; EOF after the reply releases exactly once; a client that exits before accept gets `.invalid` or ends at once; a forked child with the inherited fd doesn't keep a hold whose peer exited; an extra byte ends the hold; ping lines don't reach stdout.

`getpeereid` keeps its uid check.

Never via CLI: editing triggers, presets, guards, Drive Alive volumes, activity mode, resuming rules, ending another client's hold, turning features on, Start Anyway. `KitControl.protectedSettings` adds `"awake", "nudge", "pointernudge", "drivealive", "activity", "guards", "batteryguard", "thermalguard"` in step 1 and drops `"sleepprevention", "preventsleep"` in the step-3 coordinated merge (R5-14); `feature disable` stays limited to Displays; `module disable` help text lists Awake.

### 2.11 Runtime state, contracts, module (lead)

```swift
// Awake/AwakeRuntimeState.swift (lead)
struct AwakeLastEnd: Equatable { let reason: AwakeEndReason; let at: Date }
@MainActor final class AwakeRuntimeState: ObservableObject {
    @Published var moduleState: ModuleState = .stopped
    @Published var effectiveFeatures: Set<AwakeFeature> = []
    @Published var availability: [AwakeFeature: FeatureAvailability] = [:]
    @Published var governing: AwakeGoverning = .inactive
    @Published var holds: [AwakeHold] = []       // the stack, also while another source governs (N17)
    @Published var holderSummary: String?        // "Held by Terminal (2)"; local UI only, recomputed when holds change
    @Published var pointerConfirmation = false   // the hotkey confirmation toast is showing (gate `.asking`)
    @Published var remaining: Double?            // updated at AwakeCountdown.nextChange only
    @Published var assertion: AwakeAssertionType = .off
    @Published var power: PowerFacts?
    @Published var guardHold: AwakeEndReason?
    @Published var lastEnd: AwakeLastEnd?        // shown for 12 h after a non-user end
    @Published var activeTriggerIDs: [StableID] = []
    @Published var waitingTriggerIDs: [StableID] = []   // enabled, condition true, start delay running
    @Published var pausedUntil: Date?
    @Published var activity: AwakeActivityMode = .off   // what acted at the last interval ("Appearing active" / "Moving the pointer")
    @Published var activityCapped = false                // "Stopped appearing active after 1 hour."
    @Published var drives: [DriveAliveService.VolumeState] = []
    @Published var lidWillSleep: Bool?          // nil = no lid
    @Published var indicatorVisible = false     // our status item exists and isVisible
    func isEffective(_ f: AwakeFeature) -> Bool
    func reset()
}

// Awake/AwakeContracts.swift (lead): protocols + ChangeFanout (§2.8)
@MainActor protocol AwakeFeatureController: AnyObject {
    static var id: AwakeControllerID { get }
    init()
    func availability(of feature: AwakeFeature, context: AwakeContext) -> FeatureAvailability
    func start(_ context: AwakeContext, lifetime: Lifetime, effective: Set<AwakeFeature>)
    func effectiveFeaturesDidChange(_ effective: Set<AwakeFeature>)
    func configDidChange(from old: AwakeConfig, to new: AwakeConfig)
    func stop()
}

// Core/ModuleContracts.swift (lead): the host owns status-item slots; a module with a custom item provides it (code B3).
// The Kit plan decides; the provider only executes (code R2-M6): it creates and removes its item ONLY inside
// applyStatusItem, so Kit's plan and the item can't diverge for a turn.
struct CustomItemRow: Equatable {
    let exists: Bool                 // StatusItemPlan.custom contains the module
    let presence: MenuPresence
    let footer: Bool                 // StatusItemPlan.sharedFooterInOwnMenus: add Recent Notices ›, Quit Snaptic
    let recentNotices: Bool          // notices exist (with footer)
}
@MainActor protocol StatusItemProvider: AnyObject {
    var statusItem: NSStatusItem? { get }                      // nil while the item doesn't exist
    func applyStatusItem(_ row: CustomItemRow)                 // called from StatusMenu.applyPlan, same turn as the plan
}

// Awake/AwakeContext.swift (lead)
@MainActor final class AwakeHost {           // explicit host services (code B3: "statusItems" had no definition)
    let safeMode: SafeModeState
    let signals: HostSignals
    let hotkeys: GlobalHotkeys
    let commands: ControlCommandRegistry
    let toasts: ToastPresenter
    let permissions: PermissionFlow
    let requestMenuRebuild: @MainActor () -> Void
    /// Re-plans now (StatusMenu.applyPlan in this turn): called whenever `governing` changes active ↔ inactive.
    let requestStatusPlan: @MainActor () -> Void
    /// ⌘-drag removal and the "Don't Show" fallback write presence through the host (ModulesConfig is the host's).
    let setPresence: @MainActor (MenuPresence) -> Void
    /// Adapter (consistency m13): calls ModuleContext.openSettings(route?.id); the host parses "<root>.<route>".
    let openSettings: @MainActor (SettingsRoute?) -> Void
    /// Built from ModuleContext (r3 code sig row, minor 1): `ModuleContext` (lead) gains
    /// `requestStatusPlan: @MainActor () -> Void`, `setPresence: @MainActor (ModuleID, MenuPresence) -> Void` and
    /// `hostSignals: HostSignals`; AwakeHost binds `setPresence` to `.awake`.
    init(_ module: ModuleContext)
}
@MainActor final class AwakeContext {
    let assertions: AssertionManager, power: PowerMonitor, system: SystemEventsMonitor, apps: AppMonitor
    let displays: DisplayPresence, usb: USBWatcher, volumes: VolumeMonitor, audio: AudioMonitor
    let cpu: CPUSampler, idle: IdleSampler, network: NetworkMonitor, bluetooth: BluetoothPresence
    let activity: ActivitySimulator, driveAlive: DriveAliveService, disk: DiskIOSampler, process: ProcessWatch
    let config: ConfigStore<AwakeConfig>, state: ConfigStore<AwakeRuntimeSnapshot>, history: ConfigStore<AwakeHistory>
    let runtime: AwakeRuntimeState
    let host: AwakeHost
    let sessions: SessionController, triggers: TriggerController   // controllers other controllers call
    func service(_ id: AwakeServiceID) -> any AwakeServiceLifecycle
    func source(for kind: AwakeCriterionKind) -> (any CriterionSource)?   // nil for .schedule (r3 consistency M5)
    init(host: AwakeHost, config: ConfigStore<AwakeConfig>, state: ConfigStore<AwakeRuntimeSnapshot>,
         history: ConfigStore<AwakeHistory>, runtime: AwakeRuntimeState)
}

// Core/HostSignals.swift (lead, new): host facts modules read
@MainActor final class HostSignals: ObservableObject {
    @Published var switcherVisible = false      // A sets it
    var isTerminating = false                   // ModuleHost.shutdown() sets it before stopping modules (code M9)
    var launchSessionStarted = false            // per process (code M9)
    init()
}
```
`AwakeModule` (lead) follows `DisplaysModule` line by line (resolve, apply order, the §2.1 start order, kill switches, config sink with one main-queue hop, `stop()` sync and idempotent: controllers reverse, services reverse, `assertions.releaseAll()` last-resort, flush stores, held CLI connections finished) and adopts `StatusItemProvider` by forwarding to `IndicatorController` (G owns the item; StatusMenu never builds an Awake slot). The three stores are created and owned by `ModuleHost` (§2.13) and passed to `AwakeModule` (r3 consistency m11: one owner); r2's admission hooks and consent store are withdrawn (N10): they are plain `ConfigStore`s.

`SnapticModule` additions (§4.1: `tint`, `highlights`, `settingsRoot()`, `settingsDestination(_:)`, `settingsIndex()`) get **protocol-extension defaults** in `ModuleContracts.swift` (gray tint, no highlights, a root that renders the module's existing `settingsPages()` content, nil, `[]`), and `settingsPages()` stays until the step-3 exit, so A's `WindowSwitcherModule` and H's `SettingsWindowHost.swift` compile at step 0 (code R2-M2a).

### 2.12 Behavior across system events (normative)

| Event | Behavior |
|---|---|
| Snaptic crash / force quit | powerd releases the assertion on process exit ([PA] §1.2). Nothing else to undo (Drive Alive leaves an 8-byte hidden file). Relaunch in the same boot resumes the persisted manual session and `--pid` holds (connection-hold clients see EOF and exit 5). |
| System sleep (lid, Apple menu, low battery, thermal) | Assertions don't prevent it. `willSleep`: if `endOnSystemSleep`, end `.systemSleep`; stop activity and Drive Alive writes. `didWake`: recompute remaining (continuous clock), end expired sessions, re-arbitrate, verify the assertion, triggers step after 5 s settle. |
| Lid closed on battery, not desktop mode | Mac sleeps. When a session is active **and** the Mac is on battery or has no external display (design m5), the Awake menu shows "Closing the lid will put your Mac to sleep. To keep it awake with the lid closed, connect power and an external display." |
| Clock change | Until-sessions and `pausedUntil` re-evaluated now (re-arm if the end moved > 5 s); duration sessions unaffected; schedules re-evaluated. |
| Time-zone change | `NSTimeZone.resetSystemTimeZone()`; until instants kept, labels re-rendered; schedules use the new zone at the next step. |
| Screen lock / screensaver (session dictionary) | Session continues; plan downgrades display→system (C1 default); activity paused; Drive Alive continues (guards permitting); toasts suppressed. With `endAfterLockedHours`, a lock lasting that long ends `.lockedTooLong`. |
| Fast user switching (session dictionary: not on console) | Plan downgrades to system; activity paused; `userSwitchEnd` ends `.userSwitch` immediately or after 1 h off console (default). Becoming active again re-applies. |
| Low Power Mode on | Toast once "Low Power Mode is on. Awake keeps running." unless `endOnLowPowerMode`. |
| Thermal serious / critical | §2.6 (critical also stops Drive Alive). |
| Safe Mode | Manual sessions, holds, guards, indicator, history, shortcuts, CLI work; triggers, activity, nudge, Drive Alive are removed. |
| Displays panic ("Restore All Displays") | Not an Awake participant: keep-awake is not a display hazard. (0.2's "sleep prevention released" row goes with the feature in step 3.) |
| Module turned off from Settings | The §4.3 confirmation first when a session or enabled rule exists (one text, defined only in §4.3; consistency m5); then `stop()` with `isTerminating == false`: assertion released, session ended, snapshot cleared, status item removed, held CLI connections finished ("Awake was turned off."). |
| `Modules.disable.awake` set | Module never starts (N14); a snapshot left from earlier is cleared at launch. |
| Quit | `isTerminating = true`, then `stop()`: assertion released, snapshot kept for resume (connection holds excluded), held CLI connections finished ("Snaptic quit."; client exit 5). |

### 2.13 Interaction with Displays and the Switcher

- **Displays**: `sleepPrevention` is removed **in step 3**, in one coordinated merge by D and F with the lead's lines and A's Kit rows (code B2): `DisplayFeature.sleepPrevention` and its spec, `PerDisplayManagement.preventSleep` (kept decodable and encoded until 0.4, ignored), PowerController's assertion code, `ManagementIDs.dSleepPrevention*`, `DisplaysRuntimeState.sleepPreventionActive`, the Arrangement-page section, the menu badge, the CLI `prevent-sleep` verb (replaced by a retired-verb stub, R5-12), the KitBackup/KitControl/DisplaysUIModel/Diagnostics rows and their tests. Until then the enum case, spec and runtime property stay and compile; M1 reads raw JSON either way, so it doesn't depend on the case. The ratchet (§6.3) lists `PowerController.swift` for L1 until that merge. Awake never calls Displays code except B's pure `DisplayIdentity`/`Fingerprint.matches` helpers and a read-only look at `DisplaysConfig` custom names.
- **Switcher**: no functional coupling. Pointer nudges are tagged and suppressed while the switcher panel is visible (`HostSignals.switcherVisible`, set by A). Hotkey conflicts across modules are reported by `GlobalHotkeys` with the owning module's name.
- **Host**: `ModuleHost` gains `awake: AwakeModule`, `awakeStore`, `awakeStateStore`, `awakeHistoryStore` (one store per key: `SnapticAwakeV1`, `SnapticAwakeStateV1`, `SnapticAwakeHistoryV1`), `case .awake` in `module(_:)`, the `Modules.disable.<id>` read (N14), flushes the stores on quit, and includes them in Reset All Settings (history and state cleared too; `restoringDefaults` turns nudge and Drive Alive off).
- **Upgraders** (code M4, C7, code minor 8; step-4 code F1): in `ModuleHost.init`, **once per install** (ledger marker `awakeUpgrade.v1`, recorded on the first 0.3 launch whatever was decided), when module settings existed before this launch and `modules[.awake] == nil`, the host inserts `ModulePreferences(enabled: false, presence: .ownIconWhenActive)` for Awake and the "New: Awake" card **before** M1 runs, unless the ledger already holds M1's marker `fromDisplays.v1` (a 0.3 build ran before, e.g. a tester's pre-marker 0.3 build; review5 ui N1) (Kit `ModulesConfig.insertingAwakeForUpgrader(modulesExisted:ledger:)`). Only a real 0.1/0.2 upgrader matches on that first launch: a fresh install never stores an Awake entry (it runs on the per-id default), so without the marker its second launch, and every launch after General › Reset (which keeps the ledger), would turn Awake off; `ModulesConfig.upgradeDefaults()` (reached through `ModulesConfig.firstRun(launchedBefore: true)` for 0.1 users, who have no module settings yet; r3 consistency m6) inserts the same entry. M1 turns it on only if it produced an enabled rule. `ModulesConfig.defaultPreferences(_:)` becomes per id (fresh installs: Awake enabled, `.ownIconWhenActive`); `ConfigModulesTests` line 16 (`placement(id) == .shared` no longer holds for Awake; R5) is updated by the lead, who owns that test file from step 0 (consistency m9, r3 code minor 7).

### 2.14 Config models (Kit; lossy decode per field, `sanitized()` clamps everything)

**Lossy collections and derived ids** (N18, lead r4; r3 code M5, M6 and the StableID sig row). Lead, `SnapticKit/KitLossy.swift` (⇢ lead; `NameHash` and `StableID.derived` live in `KitModules.swift` beside `StableID`, R5-14), step 0:

```swift
/// Mirrors LossyMap (r3 code M6): decodes element by element, a bad element is skipped and the rest kept; encodes all.
/// Replaces the Decodable-only `LossyArray` in ConfigAutomation.swift, which the lead moves here in step 0 (its
/// callers in ConfigAutomation keep compiling: same name, same `items`).
package struct LossyArray<Element: Codable & Equatable>: Codable, Equatable {
    package var items: [Element]
    package init(_ items: [Element] = [])
    package init(from decoder: Decoder) throws      // ≤ 1,024 elements read, as today
    package func encode(to encoder: Encoder) throws
}
extension KeyedDecodingContainer {
    /// `c.lossyArray(.presets, default)`: missing key → default; present → element-wise (never all-or-nothing).
    package func lossyArray<T: Codable & Equatable>(_ key: Key, _ fallback: @autoclosure () -> [T]) -> [T]
}
/// 128-bit FNV-1a (offset basis 0x6c62272e07bb014262b821756295c58d, prime 2^88 + 0x13b) over UTF-8, via
/// multipliedFullWidth; Kit has no SHA (CryptoKit is app-only), and these ids aren't secrets. Fixed test vectors.
package enum NameHash { package static func fnv1a128(_ bytes: [UInt8]) -> (hi: UInt64, lo: UInt64) }
extension StableID {
    /// Name-based, v5-shaped UUID: fnv1a128(namespace ‖ 0x00 ‖ name) with the RFC 9562 version nibble 8 ("custom",
    /// because the hash isn't SHA-1) and variant 10; always a valid StableID (it parses with UUID(uuidString:)).
    /// Same input → same id on every run and platform (M1 re-runs, default presets).
    package static func derived(namespace: String, name: String) -> StableID
}
```
Every Awake list decodes through it (R5-3: `lossyUniqueArray` for lists with ids, so a duplicate id keeps the first and never traps): `AwakeTriggersConfig.triggers`, `AwakeTrigger.criteria`, `AwakeSessionsConfig.presets`, `AwakeHistory.entries`, `AwakeRuntimeSnapshot.holds`; volumes are a `LossyMap` already. The element types (`AwakeTrigger`, `AwakePreset`, `AwakeHistoryEntry`, `AwakeHold`) get hand-written `init(from:)`: an invalid `id`, `kind` or `binding` throws (that element is dropped), every other field is lossy with its default. Kit tests: one unknown 0.4 element among three keeps the other two, and the next save keeps them.

```swift
// Config/ConfigAwake.swift (lead shell; G fills the functions in step 2, code M14)
package struct AwakeConfig: ConfigModel {
    package var features: LossyMap<AwakeFeature, Bool>
    package var sessions: AwakeSessionsConfig        // G
    package var guards: AwakeGuardsConfig            // G (§2.6)
    package var triggers: AwakeTriggersConfig        // G (§2.7)
    package var activity: AwakeActivityConfig        // J
    package var drives: DriveAliveConfig             // J
    package var indicator: AwakeIndicatorConfig      // G (edited on the Menu Bar page)
    package var shortcuts: LossyMap<AwakeActionID, HotkeyCombo>   // G
    // r3's `migrations: [String]` moved to the lead's MigrationLedger (key SnapticMigrationsV1, §4.6; r3 code m13)
    package init()
    package func sanitized() -> AwakeConfig
    /// Page Restore Defaults: everything back to defaults; pointerNudge off, nudge presets → declare, Drive Alive
    /// volumes cleared (safe direction, r1 security L6).
    package func restoringDefaults() -> AwakeConfig
    /// Backup (security M7): nudge → declare, drops `drives`, `features.pointerNudge`, `sessions.recentApps`,
    /// `sessions.behavior.startAtLaunch`, salted hashes; rules only when `includeTriggers` (the export checkbox).
    package func exportable(includeTriggers: Bool) -> AwakeConfig
    /// Import: same stripping; `guards` monotonic over `current`; `features.pointerNudge` and `drives.volumes` kept from
    /// `current` (r3 security L7: the fields are named, no "protected" concept). Applied by KitBackup AFTER its generic
    /// `merge`/`mergeByID`, as the last step (security L5). Defense in depth: KitBackup.removedPaths also lists
    /// `awake.drives`, `awake.features.pointerNudge`, `awake.sessions.behavior.startAtLaunch`, `awake.sessions.recentApps`.
    package func importable(current: AwakeConfig) -> AwakeConfig
}
// r2's AwakeConsent / ConfigAwakeConsent.swift / AwakeConsentStore are withdrawn (N10).

// Config/ConfigAwakeSessions.swift (G)
package enum AwakePresetKind: Equatable, Sendable {
    case indefinite, duration(seconds: Int), untilTime(hour: Int, minute: Int)
    case untilIdle(UntilIdleSpec, maxSeconds: Int?)   // "At most" pop-up in the editor (parity minor 6)
}
extension AwakePresetKind: Codable { package init(from decoder: Decoder) throws; package func encode(to encoder: Encoder) throws }
package struct AwakePreset: Codable, Equatable, Sendable, Identifiable {
    package var id: StableID
    package var name: String?                   // nil = generated ("For 1 Hour", "Until 5:00 PM", "Until Turned Off")
    package var kind: AwakePresetKind
    package var options: AwakeSessionOptions?   // nil = "Use default" (parity M5)
    package init(id: StableID, name: String?, kind: AwakePresetKind, options: AwakeSessionOptions?)
    package init(from decoder: Decoder) throws  // hand-written (N18): id and kind required, the rest lossy
    package func encode(to encoder: Encoder) throws
    /// Menu title as a verb phrase for the first-level item (r3 product M1): "Keep Awake Until Turned Off",
    /// "Keep Awake for 1 Hour", "Keep Awake Until 5:00 PM", "Keep Awake Until Downloads and Tasks Finish".
    package func verbTitle(_ text: AwakeTextContext) -> String
}
package struct AwakeSessionsConfig: ConfigModel {
    /// ≤ 12, via lossyUniqueArray (N18, R5-3). Defaults (R5-11 order): Until Turned Off, 30 min, 1 h, 2 h, 5 h,
    /// Until Downloads and Tasks Finish,
    /// with ids `StableID.derived(namespace: "awake.preset.default", name: "30m" | "1h" | "2h" | "5h" | "indefinite" |
    /// "idle")`, so `init()` and `restoringDefaults()` give the same ids every time.
    package var presets: [AwakePreset]
    package var defaultPresetID: StableID?      // nil or unknown → Until Turned Off (C10); UI "Default session"
    /// What "Keep the display on" (display) and the Advanced activity switches (activity) edit; used when a preset
    /// has nil options. `init(from:)` decodes `presets` with `lossyArray` (r3 code M6).
    package var defaultOptions: AwakeSessionOptions
    package var lastCustomSeconds: Int          // 5400
    package var behavior: AwakeBehavior         // §2.6
    package var recentApps: [String]            // ≤ 5 bundle ids; local only, never exported
    package init()
    package init(from decoder: Decoder) throws  // R5-3: lossy per field; presets lossyUniqueArray, recentApps uniqued
    package func sanitized() -> AwakeSessionsConfig
    /// preset.options ?? defaultOptions, for every kind (R5-11: no per-kind maySleep default).
    /// Then activity is clamped to what is effective: `.nudge` → `.declare` unless pointerNudge is effective,
    /// anything → `.off` unless activity is effective (consistency M2).
    package func effectiveOptions(for kind: AwakeSessionKind, preset: AwakePreset?,
                                  effective: Set<AwakeFeature>) -> AwakeSessionOptions
    /// The "Default (…)" label in the preset editor; R5-11: `defaultOptions.display` for every kind.
    package func defaultDisplayPolicy(for kind: AwakePresetKind) -> AwakeDisplayPolicy
}
```
**Activity switches** (consistency M2, normative; Kit test): Awake › Advanced "Appear active" on sets `features.activity = true` and `defaultOptions.activity = .declare`; off sets both off (`.off`). "Move the pointer slightly" on sets `features.pointerNudge = true` and `defaultOptions.activity = .nudge`; off sets `features.pointerNudge = false` and `defaultOptions.activity = .declare`. Presets with explicit options keep theirs; `effectiveOptions` clamps them to the effective features. Changing "Keep the display on" while a session that uses default options runs applies to that session at once (parity M4).
```swift

// Config/ConfigAwakeIndicator.swift (G)
/// Menu Bar page "Time" pop-up: Don't Show / Time Remaining / End Time (design M5; .icon = Don't Show).
package enum AwakeIndicatorStyle: String, Codable, CaseIterable, Sendable { case icon, iconAndTime, iconAndEndTime }
package enum AwakeGlyphFamily: String, Codable, CaseIterable, Sendable {
    case cup, eye, lightbulb                     // cup.and.saucer / eye / lightbulb, outline idle, .fill active (tested on 14)
    package var idle: String { get }
    package var active: String { get }
}
package struct AwakeIndicatorConfig: ConfigModel {
    package var style: AwakeIndicatorStyle          // .icon (the "Time" pop-up on Menu Bar; r3 product minor 12)
    package var glyph: AwakeGlyphFamily             // .cup
    package init()
    package func sanitized() -> AwakeIndicatorConfig   // unknown legacy glyph (mug, sun, bolt) → .cup
}

// Config/ConfigAwakeDevices.swift (J)
package struct VolumeUUIDKey: RawRepresentable, Hashable, Sendable, Codable {   // code M13
    package let rawValue: String                 // canonical uppercase UUID
    package init?(rawValue: String)              // nil unless UUID(uuidString:) parses
    package init(from decoder: Decoder) throws
    package func encode(to encoder: Encoder) throws
}
package struct AwakeActivityConfig: ConfigModel {
    package var stopAfterHours: Int              // 1; 1...8, Snaptic's continuous clock from the first action (N10)
    package init()
    package func sanitized() -> AwakeActivityConfig
}
package struct DriveAliveVolume: Codable, Equatable, Sendable {
    package var name: String; package var enabled: Bool
    package var firstWriteDone: Bool = false     // set by the first write after the UI turned the volume on (§2.9)
    package init(name: String, enabled: Bool, firstWriteDone: Bool = false)
    package init(from decoder: Decoder) throws   // lossy per field (rule 9, code sig)
}
package struct DriveAliveConfig: ConfigModel {
    package var volumes: LossyMap<VolumeUUIDKey, DriveAliveVolume>   // ≤ 16
    package var intervalSeconds: Int             // 120, 30...600 ("Check drives every")
    package var evenWithoutSession: Bool         // false (C9, "Also when no session is running")
    package init()
    package func sanitized() -> DriveAliveConfig
}

// SnapticKit/AwakeSnapshot.swift (G): key SnapticAwakeStateV1
package struct AwakeRuntimeSnapshot: ConfigModel {
    package var bootSession: String              // kern.bootsessionuuid when written (code R2-M3)
    package var manual: AwakeSession?
    package var holds: [AwakeHold]               // `.process` holds only, ≤ 8, lossyUniqueArray (N17, N18, R5-3)
    // R5-3: `package init(from decoder: Decoder) throws` declared; a bad `manual` decodes as nil, the rest is kept
    package var suppressions: LossyMap<StableID, TriggerSuppression>
    package var pausedUntil: Double?             // wall time; "Pause Rules" (only here, code M2)
    package var guardMemory: GuardMemory
    package init()
    package func sanitized() -> AwakeRuntimeSnapshot
    /// Load-time clamp (Kit half of code R2-M8): drops a manual session or hold from another boot or out of range
    /// (`AwakeSession.sanitized(now:)`, `AwakeHold.sanitized(now:)`: start not after now, deadline within the kind's
    /// cap of the start, cap and deadline consistent; r3 security L3); on a boot mismatch drops `until` suppressions
    /// (keeps `untilFalse`) and resets guard memory except `warnedSerious`; keeps `source` (security L1). Pid checks
    /// and guards run in SessionController.restore.
    package func sanitized(now: ClockNow) -> AwakeRuntimeSnapshot
    /// Services the restored state needs before restore runs (§2.1 start order; r3 code M1).
    package var dynamicNeeds: AwakeDynamicNeeds { get }
}

// SnapticKit/AwakeHistory.swift (G): key SnapticAwakeHistoryV1
package enum AwakeHistoryKind: String, Codable, Sendable { case indefinite, duration, until, app, idle, process, automatic }
package struct AwakeHistoryEntry: Codable, Equatable, Sendable {
    package var start: Double; package var end: Double
    package var kind: AwakeHistoryKind
    package var source: AwakeSessionSource       // r3 consistency m3: Start Again is hidden for .commandLine and .rule (R5-14)
    package var presetID: StableID?; package var triggerID: StableID?
    package var bundleID: String?                // app sessions, for Start Again; local only (r1 security L6)
    package var endReason: AwakeEndReason
    package init(start: Double, end: Double, kind: AwakeHistoryKind, source: AwakeSessionSource, presetID: StableID?,
                 triggerID: StableID?, bundleID: String?, endReason: AwakeEndReason)
    package init(from decoder: Decoder) throws   // hand-written (N18): unknown kind, source or endReason → entry dropped
    package var offersStartAgain: Bool { get }   // false for .commandLine source and for process/automatic kinds
}
package struct AwakeHistory: ConfigModel {
    package var entries: [AwakeHistoryEntry]     // lossyArray (N18); R5-3: `init(from:)` declared
    package init()
    package func sanitized() -> AwakeHistory
    package func appending(_ e: AwakeHistoryEntry, cap: Int) -> AwakeHistory   // cap 500; merges < 60 s `.replaced` runs
    package func pruned(now: Double, keepDays: Int) -> AwakeHistory            // 90
    /// Day boundaries come from the app (Calendar) as unix times: Kit stays ICU-free (N12).
    package func totals(todayStart: Double, weekStart: Double, now: Double) -> (today: Double, week: Double)
}
```

`AwakeActionID`'s raw values are `awake.*` (G registers them). `LossyMap<StableID, …>` works because `StableID` is `RawRepresentable` with `String` raw values.

**Outside changes** (N10, lead r3): `ConfigStore` is unchanged (no `admit:` hook; r2's hook, `revertedAtLoad`, `onAdmissionReverted` and the Keychain store are withdrawn, which also retires code R2-M5/M11 and consistency M6). A `defaults write` to `SnapticAwakeV1` takes effect like any setting through `onExternalChange`, after `sanitized()`. What keeps that safe is runtime policy that reads no config the attacker controls: pointer movement needs a live UI-started session (`AwakeActivityGate`, never persisted; a hotkey start, whose binding config can change, needs the confirmation click), the activity cap runs on Snaptic's clock, the hard floor and critical-heat end are constants, CLI sessions never drive Drive Alive (source kept through restore), and the snapshot is read once at start through `sanitized(now:)` + `restore(_:)`. §3.2 states the residual risk.

## 3. Security and privacy (additions to 0.2 §4.10)

Threat model unchanged: a same-user process can already hold power assertions (`caffeinate`), write our defaults and launch Snaptic. Snaptic must not let it borrow Snaptic's TCC grants (Accessibility, Removable Volumes), run code, or extract data Snaptic observes.

### 3.1 CLI may start sessions (N1)

Allowed because starting an Awake session grants nothing new: any same-user process can create the identical assertion itself (`caffeinate`). Constraints that keep it that way:
- The CLI server is off by default (General › Command line) and keeps its 0.2 socket rules (0700/0600, `getpeereid`, 20/s), plus 1/s for `start`, `hold`, `stop`, `extend` (security L3).
- CLI sessions are `source: .commandLine` (kept through restore, security L1), visible in the indicator and menu ("Started from the command line"), subject to every guard, no "Start Anyway"; a toast says so at most once per 10 minutes, so a hidden indicator (26/27) can't hide a script. These are **UX, not a boundary** (security L4): any same-user process can run `caffeinate` invisibly, so visibility and bounds only keep Snaptic from being the quieter tool.
- **Never** pointer movement or Drive Alive: CLI sessions keep their configured options, but `ActivityPolicy.nudgeAllowed` is false for every CLI session (N10; r3 consistency M3 dropped r2's nudge refusal, which refused every `start` once pointer movement was on), and `DriveAlivePolicy.shouldWrite` ignores sessions whose source is `.commandLine` (OQ-1 settled strict). Drive Alive has no verbs, and its first write follows a UI action.
- **Never replaces a UI session**: `start` and `preset` are refused (exit 4) while a session the user started in Snaptic runs (security L4); `hold` replaces nothing and stacks beside it (N17).
- **Never unbounded**: no argument = 1 h; `indefinite` refused; each hold lasts while its own connection and process live (or a named same-uid pid lives, verified by start time) and at most 12 h (24 h with `--max`), and at most 8 holds exist; the peer is identified by the server (`LOCAL_PEERPID` on the accepted fd, best effort, not identity; the connection's EOF is authoritative), never by the request.
- Closed grammar only (`AwakeCommandGrammar` over `AwakeDurationGrammar`, digit/decimal/overflow limits); max 30 days for `start`; no free-form strings reach the assertion or the log.

### 3.2 Settings that touch Snaptic's grants or safety floors (N10)

r2 tried to make some settings writable only from the UI with a Keychain consent record. That is withdrawn (lead r3): ad-hoc builds (`build-app.sh` defaults to `SIGN_IDENTITY=-`) can only use the legacy file keychain, where a same-user process can pre-create the item with an ACL that trusts Snaptic (`security add-generic-password -A …`; security H1, code R2-M5), and every ad-hoc update changes the cdhash, losing consent each time. A protection that is both forgeable and flaky is worse than an honest statement. Instead, **runtime rules that config can't change** carry the weight:

| Capability | What a same-user process can do by editing defaults | What still holds |
|---|---|---|
| Pointer movement (Accessibility grant) | Turn on `pointerNudge`, set a preset's or the default options' activity to `nudge` | Snaptic moves the pointer only while a session the user started by a direct action in Snaptic's own UI **in this process** governs (menu click or Settings button; `AwakeActivityGate` is never persisted), never for CLI, rule, hold, `launch`, restored or resumed sessions, never while locked or off console, ±1 pt mouse-moved only (lint L2), at most `stopAfterHours` (≤ 8 h, clamped) on Snaptic's clock, the menu says "Moving the pointer" while it does, and the first nudge shows "Awake is moving the pointer slightly." [Stop]. Residual: if the user starts such a session from the menu or Settings, the attacker's setting makes Snaptic post 1-pt moves the user didn't choose, for ≤ 8 h; it can't click, type or scroll |
| Hotkey bindings (`awake.shortcuts`, applied live) | Bind `awake.toggle` or a preset hotkey to a combo the user presses for other reasons, with nudge defaults (r3 security M1) | A hotkey start never moves the pointer until the user clicks **Allow** on "Move the pointer to keep apps active?" (lead r4; 0.2 R5.7 makes Gather Windows confirm the same way); until then it only declares activity. Residual: an unexpected keep-awake session, visible in the menu bar and ended with one click |
| Drive Alive (Removable Volumes grant) | Add an eligible volume UUID, enable it, set `firstWriteDone`, set "Also when no session is running" | Writes go only to eligible external volumes (DiskArbitration + fd checks, §2.9), only the fixed 8-byte `.snaptic-keepalive` file, never for CLI sessions. Drive Alive grants **no new capability**: a same-user process can write files to those volumes itself. Residual: an unprompted Removable Volumes dialog, which the user can decline |
| Battery floor | Turn the user floor off or set it to 5% | The fixed 5% hard floor ends sessions and Drive Alive whenever the battery is discharging, also on an AC adapter that can't keep up (10-min falling window, R5-6); `batteryPresent` is latched, so a missing battery entry on a laptop is an unreadable read (activity and Drive Alive stop), not a desktop; critical heat always ends (§2.6; r3 security M3). Residual: none beyond what `caffeinate` allows anyway |
| Snapshot (`SnapticAwakeStateV1`) | Write a session or holds, clear guard memory | Read once at start: `sanitized(now:)` (bounds from Snaptic's clock, not the snapshot's own fields; r3 security L3) + `restore(_:)` keep the written `source` (a forged `.menu` source never sets the activity gate), re-verify `--pid` holds, evaluate guards with live facts and recompute guard holds; afterwards SessionController never reads the store and always writes whole snapshots from memory, so outside writes while Awake runs have no effect (security L2, r3 security L4; tested) |

- **Restore Defaults / Reset All Settings** turn pointer movement off and clear Drive Alive volumes (r1 security L6).
- Import (`importable(current:)`, after KitBackup's merge) never brings in `features.pointerNudge` or `drives.volumes` and only tightens `guards` (security L5, r3 security L7).
- Focus: another process can bring Settings forward (reopen, `open-settings`); session-start controls have no Return binding, ignore clicks for 1 s after an external open (r3 security L8), and ignore keyDown activation until a real mouse-down in the window (R5-8). Confirmation toasts ignore clicks for 300 ms and while another process's window overlaps them (R5-1).
- Not a boundary against a process that drives Snaptic's UI with Accessibility or replaces a user-writable app bundle (0.2 R5.7).

### 3.3 Activity simulation

- Default `declare` uses no TCC and posts no events.
- `nudge` (experimental) is the only code path in Snaptic that posts mouse events: one file (`ActivitySimulator.swift`, lint L2), `mouseMoved` ±1 pt only from a private-state event source, tagged 'SNPT', never key/click/scroll, never within 2 pt of a display edge, never while locked, in the screensaver or off console (all read from the session dictionary and process state, never from notifications alone, security M2), never when the user typed or clicked within the interval, only for UI-started sessions of this process, and for hotkey starts only after the confirmation toast (N10); Accessibility is requested lazily, only when the user turns nudge on (through `PermissionFlow`), and the toggle explains how to revoke it.
- Both modes stop `stopAfterHours` (default 1 h, max 8 h) after they first acted, **measured on Snaptic's continuous clock** (security M2: Snaptic's own declarations may reset system idle, so idle time can't bound them) and carried across back-to-back sessions and rule hand-offs (r3 security L5, R5-7). Relaunching Snaptic starts a new count; for `declare`, which needs no TCC, the cap is a UX bound, not a boundary. Organizations can turn them off with `Awake.disable.activity` / `Awake.disable.pointerNudge` (N14).

### 3.4 Drive Alive writes

Fixed file name at the volume root; target derived from the live mount list by UUID and re-verified on a directory fd (`fstatfs` mount point, file-system allowlist, `MNT_LOCAL` set, `MNT_RDONLY`/`MNT_ROOTFS` clear, `f_mntfromname` equal to the eligible BSD name, `fgetattrlist` volume UUID, `openat` + `O_NOFOLLOW`, same `st_dev`), never from stored paths or user text; `fstat` checks (regular, ours, one link, ≤ 64 B); 8 bytes of timestamp; never internal, boot-container, system, read-only, non-local, disk-image (DiskArbitration) or Time Machine volumes (Kit `DriveAlivePolicy`, tested); removal via `unlinkat` only of an 8-byte file that passes the same checks; stop before unmount; battery floor and thermal guards apply in every mode; I/O off main with results hopping back. The Removable Volumes grant is Snaptic's own, used only for this file, first used right after a UI action.

### 3.5 No code execution, no network

Awake spawns nothing (lint rule 12 already bans `Process`, `posix_spawn`, `NSAppleScript`, `NSUserScriptTask`, `system(` outside HelperSpawner; r1's L3 duplicated it and is dropped); `hold` observes a process with a kqueue `EVFILT_PROC` source and `proc_pidinfo`, never signals, spawns or wraps a command; triggers have no actions besides starting a session; no URL scheme; no AppleScript. NetworkMonitor reads kernel/configd state only (`SCDynamicStore`, `sysctl NET_RT_IFLIST2`, routing-table `sysctl`); DiskIOSampler reads IORegistry properties only; CPUSampler reads `proc_pid_rusage` of same-user processes only; lint bans `URLSession`, `NWConnection`, `CFSocket`, `socket(`, `connect(` in Awake as elsewhere.

### 3.6 Privacy

- **Logs** (`EventLog`, `.awake`): written only as `EventLog.shared.record(_ event: AwakeLogEvent)` (A adds the overload in `Core/EventLog.swift`; it is the only code that names the `.awake` category; consistency m10, code minor 5), a closed Kit enum (G, `SnapticKit/AwakeLogEvent.swift`) with a fixed `text` per case. Cases are split: **counted only** (`sessionStarted(AwakeHistoryKind)`, `sessionEnded(AwakeEndReason)`, `holdStarted`, `triggerActive(index: Int)`, `activityCapped`) increment a per-case counter **kept in `EventLog` itself** (`EventLog.shared.awakeCounts: [String: Int]`, A; `AwakeDiagnostics` (G) reads it, because EventLog is a singleton and can't reach the per-context diagnostics; r3 code minor 11) and never enter the ring, so the log holds no activity timeline; **ring** cases are errors only (`assertionFailed`, `driveAliveError(DriveAliveError)`, `holdRefused`, `restoreDropped`). Lint L9 bans `record(.awake` and the token `EventCategory.awake` outside `Core/EventLog.swift` (security M6). No app names, bundle ids, process names, pids, volume names/UUIDs, USB names/serials, addresses, router data, criterion payloads or rule names can reach the log.
- **CPU and disk samples**: only aggregate numbers (the busiest same-user process's share, new-process churn, total CPU, summed disk bytes) are kept, in memory, for the running untilIdle session; the sampler's transient pid → (start time, CPU ticks) map from the previous sample is in memory only and dropped with the session (r3 code M2); no pid or process name is stored, shown, logged or exported.
- **Hold holders**: the holder name ("Terminal") is computed from the process tree when shown, only in the Awake menu, the Settings status row and toasts; never persisted, logged, exported, in diagnostics or over the CLI (which shows pids only).
- **History** is a local timeline: `SnapticAwakeHistoryV1` keeps 90 days of start/end times, kinds, sources and app bundle ids in a domain any unsandboxed same-user process can read; it never reaches logs, diagnostics, the CLI or exports, and the user can Clear History… or turn History off (r3 security L6). Rule definitions and `recentApps` (app, device and network names) are plaintext in the same domain for the same reason.
- **Assertion properties** are world-readable (`pmset -g assertions`): name is fixed; `Details` is only `manual` or `automatic` (no criterion kinds).
- **CLI** `awake status`: kinds, rule numbers, the hold count and, with `--json`, hold pids (numbers, never names; r3 consistency m4).
- **Stored identifiers**: router MACs and USB serials as salted hashes (`SnapticAwakeSalt`, never exported); display matches as salted fingerprint tiers (existing salt). The salts live in the same domain, and a router MAC leaves about 24 unknown bits per vendor prefix, so salted hashes protect **exports and diagnostics**, not a local same-user reader (r3 security L6).
- **Backup** (`AwakeConfig.exportable/importable`, A wires them into KitBackup's new `awake` section): export includes presets (nudge rewritten to declare), guards, indicator, behavior; trigger definitions **only** when the user ticks "Include automatic-session rules (contains app, device and network names)" (off by default; salted hashes are stripped either way since they are useless on another Mac); omits history, runtime state, salts, `recentApps`, `startAtLaunch`, Drive Alive volumes, `pointerNudge`. Import: same stripping, guards monotonic (stricter only; `awake.guards` joins `safetyPaths`), `features.pointerNudge` and `drives.volumes` always kept from the current config, and the `removedPaths` entries of §2.14 strip them generically too (r3 security L7).
- **Diagnostics** (shared report): Awake section with effective features, governing kind, assertion type, guard state, source activity (running/idle), counts of rules/conditions by kind, Awake event **counts** per `AwakeLogEvent` case (from `EventLog.shared.awakeCounts` via `AwakeDiagnostics`, no timestamps), Drive Alive volume count and last error codes. `DiagnosticsController.eventLines()` (F) keeps only entries whose `EventCategory.isExportedInDiagnostics` (lead, `KitModules.swift`; false for `.awake`, Kit-tested) holds (security M3). The "Other apps keeping your Mac awake" list never goes into diagnostics, logs or CLI.
- `settingsIndex()` entries are static strings (test: no entry title or keyword comes from config).

## 4. Settings redesign

### 4.1 SettingsUI component library (H, `Sources/Snaptic/SettingsUI/`)

All pages use these and nothing else for rows (lint L5: raw `Slider(`, `Stepper(` and `.font(.caption)` captions are banned outside `SettingsUI/`; L12: `.controlSize(.regular)` only in `SettingsPageHeader.swift`). Grouped `Form` (`.formStyle(.grouped)`), system text styles, semantic colors, 4-pt grid, 0.15 s crossfades only, Reduce Motion/Transparency honored ([DS] §5). **Row switches use the grouped form's default (small) size; only the page header switch is `.regular`** (design B2; System Settings precedent on 14–27). A subordinate row appears only while its parent is on and is indented 20 pt; it is never a smaller control.

```swift
// Core/ModuleContracts.swift (lead; code minor 12): types the shell contract references
enum SettingsTint: String { case gray, graphite, blue, indigo, orange, green, red, purple, teal; var color: Color { get } }
struct FeatureHighlight: Identifiable { let id: String; let symbol: String; let title: String; let text: String }

// SettingsUI (H)
struct SettingsIcon: View { init(_ symbol: String, tint: SettingsTint, size: CGFloat = 20) }   // rounded-square tile, a11y hidden

/// Top section of every page. `isOn` = master switch (module or feature group), `.regular` size;
/// `switchLabel` is its accessibility label and tooltip ("Use Awake", N5).
struct SettingsPageHeader: View {
    init(_ title: String, summary: String, symbol: String, tint: SettingsTint,
         isOn: Binding<Bool>? = nil, switchLabel: String? = nil, badge: SettingsBadge? = nil, status: String? = nil)
}
enum SettingsBadge: Equatable { case beta, experimental, new, paused(String), unavailable(String) }

/// Shown under the header while a module or feature group is off: 2–3 "what this does" rows.
struct FeatureHighlights: View { init(_ rows: [FeatureHighlight]) }

/// Title + optional one-line help (LabeledContent subtitle) + trailing control.
/// Reset: a glyph only for continuous values (`resetGlyph: true`, used by SliderSetting/StepperSetting/NumberField);
/// every row with `reset` also gets a context menu "Reset to Default" (design M6).
struct SettingRow<Control: View>: View {
    init(_ title: String, help: String? = nil, anchor: ControlID? = nil, isDefault: Bool = true,
         reset: (() -> Void)? = nil, resetGlyph: Bool = false, resetLabel: String? = nil,
         @ViewBuilder control: () -> Control)
}
/// arrow.counterclockwise 11 pt, borderless, secondary; always reserves 16 pt; fades 0.15 s (instant with Reduce Motion);
/// tooltip "Reset to 50%", AX label "Reset Contrast to 50 percent". Visible only while value ≠ default
/// (`SliderMath.isDefault`); with `defaultValue: nil` (live Brightness) there is never a glyph, the slot stays (design m8).
struct ResetButton: View { init(visible: Bool, label: String, action: @escaping () -> Void) }

/// Precondition missing → the control is disabled, its help stays, and `disabledReason` + `fix` go to the
/// section footer ("Needs Accessibility." [Open Accessibility Settings…]). Hardware can't do it → the caller omits the row.
struct ToggleSetting: View {
    init(_ title: String, help: String? = nil, isOn: Binding<Bool>, subordinate: Bool = false,
         anchor: ControlID? = nil, badge: SettingsBadge? = nil, disabledReason: String? = nil, fix: StatusAction? = nil)
}

/// Every slider in Settings (N4). Normative layout (design M6), trailing cluster after the title:
///   slider (min 140, ideal 200) · 8 · field (width = widest formatted value of the range for its ValueFormat,
///   min 48; "1512 × 982" and "6500 K" fit; design m7) · 4 · reset slot 16 (always reserved).
///   A discrete slider (resolution) snaps a typed value to the nearest position.
/// The field IS the live value (shows `drag ?? value`, unit inside the text: "70%", "60 Hz", "15 min");
/// `.roundedBorder`, `.controlSize(.small)`, monospaced digits, trailing-aligned; focus selects all; parses "70", "70 %", "70%".
/// ViewThatFits fallback: title row (field + reset trailing) above a full-width slider.
/// Tick marks when ≤ 11 positions; ←/→ and accessibilityAdjustableAction move one step (or 1% of the range).
struct SliderSetting: View {
    init(_ title: String, help: String? = nil, value: Binding<Double>, in range: ClosedRange<Double>,
         step: Double? = nil, defaultValue: Double?, format: ValueFormat,
         minSymbol: String? = nil, maxSymbol: String? = nil,
         commit: SliderCommit = .throttled(hz: 15), preview: (@MainActor (Double) -> Void)? = nil,
         anchor: ControlID? = nil, subordinate: Bool = false, disabledReason: String? = nil)
}
enum SliderCommit: Equatable {
    case live                  // hardware value through DisplayLiveControlling (§4.5): latest-wins mailbox
    case throttled(hz: Double) // config-backed: writes at most hz/s during a drag, final value on release
    case onRelease             // expensive side effects; `preview` gives live feedback meanwhile
}
/// Units and scaling for display, typing and VoiceOver (Kit `ValueFormat` in SliderMath.swift, hand-formatted, N12).
// e.g. .percent(of: 1) shows 0…1 as 0–100%; .seconds; .minutes; .hertz; .points; .nits; .kelvin; .plain(digits:)

struct NumberField: View {      // commits on Return and blur; clamps + snaps to step; Esc reverts; unit inside the text
    /// width nil = derived from `SliderMath.widestText(range:step:format:)` (design m7).
    init(_ accessibilityTitle: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double?,
         format: ValueFormat, width: CGFloat? = nil)
}
struct StepperSetting: View {   // small integer ranges (≤ ~20 values): label + NumberField + Stepper + reset slot
    init(_ title: String, help: String? = nil, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
         defaultValue: Int?, format: ValueFormat, anchor: ControlID? = nil)
}
enum PickerSettingStyle { case automatic, popUp, segmented, radio, pullDown }
struct PickerOption<V: Hashable>: Identifiable {         // code M13: Identifiable needs an id
    let value: V; let title: String; let help: String?; let symbol: String?; let enabled: Bool
    var id: V { value }
    init(_ value: V, _ title: String, help: String? = nil, symbol: String? = nil, enabled: Bool = true)
}
struct PickerSetting<V: Hashable>: View {   // pop-up (> 4 options), segmented (2–4 short), radio (2–5 with help)
    init(_ title: String, help: String? = nil, selection: Binding<V>, options: [PickerOption<V>],
         style: PickerSettingStyle = .automatic, defaultValue: V?, anchor: ControlID? = nil, subordinate: Bool = false)
}
/// Glyph tiles (Snaptic/module/Awake icons, display icons): rendered symbols with `.isSelected` AX trait, never raw names.
/// A radio group: the row title is the group label, arrow keys move the selection (design m10).
struct GlyphTilePicker: View { init(_ title: String, symbols: [String], selection: Binding<String>, anchor: ControlID? = nil) }
/// Pull-down button with actions (Display Tools ▾, Copy Settings From ▾, Options ▾).
struct ActionMenuButton: View { init(_ title: String, items: [ActionMenuItem]) }
struct ActionMenuItem: Identifiable { let id: String; let title: String; let enabled: Bool; let action: @MainActor () -> Void
                                     var control: ControlID? = nil }   // control: R5-13 (also StatusAction, NavigationRow, ButtonRow, SettingsPageHeader, PageFooterButtons)

struct InfoButton: View { init(_ title: String, message: String) }            // (i) popover, 280 pt; never opens a sheet
struct NavigationRow: View {                                                   // icon tile + title + trailing value + chevron
    init(_ title: String, symbol: String, tint: SettingsTint, value: String? = nil, route: SettingsRoute, badge: SettingsBadge? = nil)
}
struct ButtonRow: View { init(_ title: String, symbol: String? = nil, action: @escaping @MainActor () -> Void) }  // "Keyboard Shortcuts…", "Display Details…"
struct StatusAction { let title: String; let action: @MainActor () -> Void; var control: ControlID? = nil }   // control: R5-13
enum StatusStyle { case info, warning, error }
struct StatusRow: View { init(_ text: String, symbol: String? = nil, style: StatusStyle = .info, actions: [StatusAction] = []) }
/// ≤ 4 displays: tiles; more: a pop-up. Hidden with one display. Group AX label "Display".
/// Selection is shared across pages through SettingsShell.selectedDisplay (design m9).
/// Budget: counts toward a page's total, not toward its settings (design m13).
struct PerDisplayPicker: View { init(_ displays: [DisplayTile], selection: Binding<DisplayKey?>) }
struct DisplayTile: Identifiable, Hashable { let id: DisplayKey; let name: String; let isBuiltin: Bool; let badges: [String] }
/// Page footer: trailing `Advanced…` and (?) only (design M5). `restoreDefaults` appears here (leading) only on
/// pages without an Advanced sheet.
struct PageFooterButtons: View { init(advanced: (() -> Void)?, help: SettingsRoute?, restoreDefaults: RestoreDefaults? = nil) }
/// Button title "Restore <scope> Defaults…" ("Restore Awake Defaults…", "Restore Displays Defaults…"; r3 product
/// minor 13); the confirmation names the scope too. Reset All Settings… keeps its own title.
struct RestoreDefaults { let scopeName: String; let destructive: Bool; let action: @MainActor () -> Void; var title: String { get } }
/// 520 wide, ≤ 25 controls, Done = Return trailing; Restore Defaults… leading in its footer. Never presents another sheet.
struct AdvancedSheet<Content: View>: View {
    init(_ title: String, restoreDefaults: RestoreDefaults?, @ViewBuilder content: () -> Content)
}
/// List .onMove + ▲▼ context menu for keyboard; each row exposes VoiceOver actions Edit (when `onEdit`), Delete,
/// Move Up, Move Down (design M4, m10).
struct ReorderableList<Item: Identifiable, Row: View>: View {
    init(_ items: Binding<[Item]>, onEdit: ((Item) -> Void)? = nil, onDelete: ((Item) -> Void)?,
         @ViewBuilder row: @escaping (Item) -> Row)   // code M13
}
struct AppListEditor: View { init(_ title: String, help: String?, bundleIDs: Binding<[String]>, anchor: ControlID?) }   // moved from Switcher AppListSection; used by Switcher and PIP
struct ShortcutSetting: View { init(_ title: String, help: String? = nil, combo: Binding<HotkeyCombo?>, owner: String, anchor: ControlID? = nil) }  // wraps ShortcutRecorder; shows conflicts by owner
/// Empty lists: ContentUnavailableView with the page's own copy (design m8).
struct EmptyListView: View { init(_ title: String, symbol: String, text: String?, action: StatusAction?) }
/// Each page's scroll scaffold owns its ScrollViewReader (code minor 3); anchors register here.
struct SettingsPageScaffold<Content: View>: View { init(route: SettingsRoute, @ViewBuilder content: () -> Content) }
/// `.modifier(SettingsAnchor(ControlID("awake.page.batteryFloor")))` (R5): id + search highlight (1.2 s tint; static with Reduce
/// Motion). A ViewModifier, not a `View` extension, so lint rule 10 holds (r3 code sig row, minor 2). Rows that take
/// `anchor:` apply it themselves. The ControlID literal must be in the view's control table (lint L15, §4.8).
struct SettingsAnchor: ViewModifier { init(_ id: ControlID) }
```

Shell contracts (lead, `Core/ModuleContracts.swift`; replaces `settingsPages()`). `SettingsRoute` and `SettingsSearchEntry` are **Kit** types (H, `SnapticKit/SettingsIndex.swift`) so the search ranking, anchor uniqueness and the control map are tested on Linux (code minor 13); each module's `settingsIndex()` returns `SettingsIndex.entries(ControlRegistry.tables, root:)`, derived from the control specs' `search` (R5-13; no per-module index tables):

```swift
// SnapticKit/SettingsIndex.swift (H)
package struct SettingsRoute: Hashable, Sendable { package let id: String; package init(_ id: String) }   // "displays.color"
package struct SettingsSearchEntry: Hashable, Sendable {
    /// `id == anchor ==` the row's `ControlID.rawValue` (Kit test; r3 code minor 12).
    package let id: String; package let title: String; package let keywords: [String]
    package let root: String                 // sidebar item id
    package let route: SettingsRoute?        // sub-page, nil = root page
    package let anchor: String               // settingsAnchor id
    package let sheet: String?               // Advanced/other sheet id to open first
    package init(id: String, title: String, keywords: [String] = [], root: String, route: SettingsRoute? = nil,
                 anchor: String, sheet: String? = nil)
}

// Core/ModuleContracts.swift (lead)
struct SettingsRoot: Identifiable, Hashable {
    let id: String; let title: String; let symbol: String; let tint: SettingsTint
    let makeView: @MainActor () -> AnyView
    static func == (a: SettingsRoot, b: SettingsRoot) -> Bool { a.id == b.id }   // code M13: closure property
    func hash(into h: inout Hasher) { h.combine(id) }
}
@MainActor protocol SnapticModule: AnyObject {
    // id, title, symbolName, summary, state, requiredPermissions, start, stop, menuSection, settingsPages()
    // — unchanged; settingsPages() is removed at the step-3 exit (code R2-M2a)
    var tint: SettingsTint { get }
    var highlights: [FeatureHighlight] { get }                       // off-state block
    func settingsRoot() -> SettingsRoot                               // rendered whether running or not
    func settingsDestination(_ route: SettingsRoute) -> AnyView?
    func settingsIndex() -> [SettingsSearchEntry]                     // static per module; computed once
}
extension SnapticModule {   // step-0 defaults so existing conformers compile (code R2-M2a)
    var tint: SettingsTint { .gray }
    var highlights: [FeatureHighlight] { [] }
    func settingsRoot() -> SettingsRoot           // wraps settingsPages() content
    func settingsDestination(_ route: SettingsRoute) -> AnyView? { nil }
    func settingsIndex() -> [SettingsSearchEntry] { [] }
}
```

`SettingsShell` (H, `SettingsUI/SettingsShell.swift`; code minor 12: H owns it, the lead owns only the protocol types above):

```swift
@MainActor final class SettingsShell: ObservableObject {
    @Published var root: String                         // sidebar selection
    @Published var paths: [String: [SettingsRoute]]     // one NavigationStack path per root
    @Published var openSheet: String?
    @Published var highlightedAnchor: String?
    @Published var selectedDisplay: DisplayKey?         // shared PerDisplayPicker selection
    func moduleEnabled(_ id: ModuleID) -> Binding<Bool>
    func push(_ route: SettingsRoute)
    func pop()
    /// Sets root now, pushes the route on the next main-queue turn (macOS 14 drops a push in the same
    /// transaction), opens the sheet, and highlights only after the sheet has appeared (code minor 3).
    func reveal(_ entry: SettingsSearchEntry)
    init()
}
```
Detail column: `NavigationStack(path: binding(for: root)) { … }.id(root)`. Last root + route restored from `@AppStorage("settingsLastRoute")` (no dots in the key).

Kit (H, tested): `SliderMath.swift` (`ValueFormat`, `clampSnap`, `isDefault(value:default:step:)` with half-step tolerance, hand-written `format(_:decimalSeparator:)` and `parse(_:decimalSeparator:)` accepting "70", "70 %", "70%", "1,5 s" when the separator is ",", `spoken` for VoiceOver; the app passes `Locale.current.decimalSeparator` once, N12); `SettingsIndex.swift` (`SettingsSearch.rank(entries:query:) -> [SettingsSearchEntry]`: hand-written ASCII/Latin-1 diacritic and case folding (table, not ICU), prefix-of-word match on title > keywords > synonyms table; synonyms: DDC↔monitor/hardware, caffeinate/insomnia/amphetamine/keep awake/sleep/prevent sleep/lid/clamshell/jiggle/screen saver↔Awake, alt-tab/⌥⇥↔Window Switcher, PIP↔picture in picture, OSD↔brightness indicator, HiDPI↔sharper text, XDR↔extra brightness).

### 4.2 Information architecture

**Window**: `NavigationSplitView`, sidebar 200–240 pt with `.searchable(placement: .sidebar)` at the top, detail `NavigationStack` per root (back button for sub-pages), `.toolbar(removing: .sidebarToggle)`, **fixed width 715 pt, vertical resize only** (min height 520, default 720 so the Displays root's first navigation group is above the fold; [DS] §1, design m6/M6), title = current page. While open the app is `.regular` (0.2 R5.8 kept).

**Sidebar** (fixed; 7 rows; groups separated by spacing; consistency m1). Awake shows a "New" badge (`SettingsBadge.new`) until its page is first shown (`@AppStorage("settingsSeenAwake")`; only for users who had no Awake before, design M3):

```
[Search]
General              gearshape                gray
Menu Bar             menubar.rectangle        graphite
—
Window Switcher      rectangle.on.rectangle   indigo    (master switch on page)
Displays             sun.max.fill             blue      (master switch on page)
Awake                cup.and.saucer.fill      orange    (master switch on page)
—
Permissions          hand.raised.fill         blue
About                info.circle.fill         gray
```
Search results replace the list with "Title — Page" rows; choosing one calls `SettingsShell.reveal`. No results → `ContentUnavailableView.search(text:)`. ⌘F and Edit › Find focus the sidebar search field (System Settings precedent; r3 product minor 14).

**Copy rules** ([DS] §4, normative): sentence case for labels, help, section headers; Title Case for buttons, menu items, page titles; serial comma ("Startup, command line, backup, and Safe Mode."; design m1); labels name the thing or the on-state, no "Enable/Disable/Allow X to"; one help sentence ≤ 90 characters describing the on state; "Mac", "display", "click", "press"; never "monitor" in labels (use "display" or "hardware"); errors say what to do; real ellipsis; "20%", "60 Hz", "15 min" in values; Apple terms table [DS] §4.7 (Display, Virtual display, Picture in Picture, Brightness indicator, Saved layouts, Start automatically, Keep Awake, Display Information, Confirm display changes, Settings). Every visible control has help text or is self-evident by Apple precedent (review item: each `ToggleSetting`/`SliderSetting` without `help:` needs a reviewer note).

**States** (design m8, normative): hardware can't do it → the row is omitted; a precondition is missing → the control is disabled, its help stays, and the reason plus a fix button go in the section footer; empty lists → `EmptyListView` with page-specific copy (§4.3).

**Budget** (r2 definition, design M1): per page with default features and the 1 built-in + 1 DDC external setup, count every visible **setting** (switch, picker, slider, field, glyph tiles, including subordinate rows shown by default) and every **in-form button or navigation row**. Not counted: the page header switch, the status row's actions, the rows inside a list (a list counts as 1), the footer (`Advanced…`, (?)). `PerDisplayPicker` counts toward the total, not toward settings. Experimental and opt-in features are counted only when on by default (so the Displays root doesn't count "Automatically adjust brightness"). Limits: ≤ 8 settings and ≤ 12 counted elements in total; Advanced sheets ≤ 25 controls. Exception, stated in §4.3: the Displays root page is a hub (System Settings › Displays precedent) whose navigation rows exceed the total.

### 4.3 Pages (normative content; V = visible, A = Advanced sheet, S = sub-page, D = Display Details sheet, X = removed/merged)

Every page: `SettingsPageScaffold` → `SettingsPageHeader` → sections → `PageFooterButtons` (trailing `Advanced…` and (?) only). Restore Defaults… lives in the Advanced sheet's footer (leading), or in the page footer (leading) on pages without an Advanced sheet. Keyboard Shortcuts… is a `ButtonRow` in a "Keyboard" section, never a footer button (design M5). No sheet presents another sheet (§1.5); a "…" inside a sheet is a disclosure, a pull-down or a standard alert.

**General** (hero header, no master switch; was 9 pages / ~34 controls)

```
[⚙] General
    Startup, command line, backup, and Safe Mode.
─────────────────────────────────────────────────────
[New: Awake — Keep your Mac awake for a while.     [Turn On Awake] [Not Now]]   (Awake off; once)
[Your display sleep setting moved to Awake.          [Show Awake] [OK]]        (migrated users; once)
─────────────────────────────────────────────────────
Open at login                                       ( )
─────────────────────────────────────────────────────
Command-line control                                ( )
  Lets scripts and other apps control Snaptic with the `snaptic` command.
    Copy Install Command                                  subordinate, only while on
      Copies a Terminal command that installs `snaptic`.
─────────────────────────────────────────────────────
Export Settings…                      Import Settings…
                                            Advanced…  (?)
```

| Section | Control | Where | From |
|---|---|---|---|
| Card | State-dependent (C7, design M3): Awake off → "New: Awake" **Turn On Awake** (turns the module on and opens the Awake page; no ellipsis) / **Not Now**; migrated by M1 → "Your display sleep setting moved to Awake." **Show Awake** (opens Awake) / **OK**; dismissal stored in generalized `newModuleCards` | V once | "New: Displays" card |
| Status row | "Safe Mode is on." [Leave Safe Mode…] while true (every Leave Safe Mode… in Settings and the menus asks first with one shared confirmation, "Leave Safe Mode?" [Restart] [Cancel]; review5 ux N5) | V when true | Overview banner |
| Startup | Open at login | V | Startup page (X: a page for one toggle) |
| Command line | Command-line control (help "Lets scripts and other apps control Snaptic with the `snaptic` command.") · Copy Install Command (subordinate `ButtonRow`, only while Command-line control is on; help "Copies a Terminal command that installs `snaptic`."; r3 product minor 8) | V | CLI page |
| Backup | Export Settings… (sheet: "Include automatic-session rules (contains app, device and network names)" checkbox, off) · Import Settings… | V | Backup & Reset |
| Advanced | Commands can skip confirmation · exit codes ((i) popover) · Restart in Safe Mode… / Leave Safe Mode (with its explanation) · footer leading: **Reset All Settings…** (destructive, scope "all Snaptic settings"; parity minor 12) | A | CLI page, Safe Mode page (X), Backup & Reset |

The module navigation rows of r1 are removed (they repeated the sidebar; design M1). "Other display apps" moves to Displays › Advanced. About & Licenses → About.

**Menu Bar** (M; N7; graphite tile; was General › Menu with ~28 controls). No Advanced sheet.

```
Window Switcher                    [Show in Snaptic Menu ▾]
   (Always Show only) Icon          [▭] [◫] [⧉]
Displays                           [Show in Snaptic Menu ▾]
   (Always Show / When Active) Icon [▭] [◫] [☀]
Awake                              [Show When Active ▾]
   Time                            [Don't Show ▾]        Time Remaining / End Time
   Icon                            [cup] [eye] [bulb]
⚠ status rows, only when true
─────────────────────────────────────────────────────
Displays menu
Style                              [Standard | Compact]
    Compact shows one slider per display.
Scroll over a slider to adjust it                   (•)
Customize Displays Menu…
─────────────────────────────────────────────────────
Snaptic icon                       [◫] [◩] [◰]
              Restore Menu Bar Defaults…     (?)
```

| Section | Controls | Where |
|---|---|---|
| Modules (no header, design M5) | One pop-up per module (C2), labelled with the module name, Control Center wording and **one option order for every module**: *Always Show in Menu Bar · Show When Active · Show in Snaptic Menu · ─ · Don't Show*. *Show When Active* is offered for Displays (help "Shows the icon while an external display is connected.") and Awake (help "Shows the icon while your Mac is being kept awake."; r3 product minor 16), not for the Switcher. Help for Don't Show: "Use the keyboard shortcut or Settings to reach it." Awake's *Don't Show* is disabled until the Keep Awake shortcut is really registered (`AwakeRuntimeState`'s registered flag: bound, registered without failure, Keyboard Shortcuts feature effective, Awake on and not killed; review5 parity Q2 / code M1); the footer then reads "To hide Awake, first set a Keep Awake shortcut." (parity M2). Under a module with its own icon: its **Icon** glyph tiles (parity B2). Under Awake (Always Show or When Active): **Time** (*Don't Show / Time Remaining / End Time*, default Don't Show) and **Icon** tiles (cup, eye, lightbulb) | V |
| Warnings | 0.2's hidden-icon warnings kept as status rows ("No Snaptic icon is shown…", "The Displays icon only appears while an external display is connected.") | V when true |
| Displays menu | **Style**: Standard / Compact (help "Compact shows one slider per display.") · Scroll over a slider to adjust it · Customize Displays Menu… → sheet (below) | V + sheet |
| Snaptic icon | Glyph tiles (curated, rendered); last, the least-used control (design M5) | V |
| Footer | Restore Menu Bar Defaults… (scope "menu bar settings", leading) · (?) | V |

**Customize Displays Menu…** sheet (M; lead r4, r3 product M5, design m13): split per menu section into **independent disclosure groups** inside one grouped `List` (R5-11: no accordion; Per Display expanded by default, the others collapsed); the `List` counts as 1 under §4.2, so the sheet is within ≤ 25.
- Filter field at the top ("Filter menu items"): shows matching rows across all groups and expands their groups.
- **Displays** (collapsed by default): one reorderable list of displays with a checkbox each (visible in the menu) and a pinned "Main display" row that can be dragged (replaces "Main display first"), Use the Default Order; section order; status badges; header row with one display (kept: a 0.2 setting, design m13 partly rejected).
- **Per Display** (expanded by default): the per-display items of the §4.8 "0.2 menu" table with human titles ("Volume", "Input", "Turn Display On or Off", "Extra Brightness", "Rotation", …), each with the pop-up *Show* (its §5.2 location) / *In Display Submenu* / *Hide*; the per-display sliders (Brightness, Volume, Contrast, custom controls, Resolution) are checkboxes, because a slider is never in a submenu.
- **Displays Section** (collapsed): Arrange Displays…, Saved Layouts ›, Virtual Displays ›, Picture in Picture ›, Actions › with one checkbox per custom action (the same flag as Automations › "Show in menu"), each a checkbox (Show).
- **Display Tools** (collapsed): one checkbox per Display Tools item.
- In each group, items whose feature is off collapse into one dimmed row ("6 items need features that are off" ›, which lists them with "Turn On in Settings…"), instead of one dimmed row each.
- Footer leading **Restore Displays Menu Defaults…**. The 0.2 per-display "Header switch" is gone (migration M10, parity M6).

**Window Switcher** (H; header switch "Use Window Switcher"; was 6 pages / ~40 controls)

| Section | Controls | Where | Notes |
|---|---|---|---|
| Status | "Window thumbnails need Screen Recording." [Open Privacy Settings…] while thumbnails are on and the grant is missing (parity minor 3) | V when true | Features permission row |
| Shortcut | Primary shortcut (modifier + key recorder) · **More Shortcuts…** (`ButtonRow` directly under it → sheet: additional switcher shortcuts with their own options, Add/Delete, Gather Windows shortcut; design m12) · Switch when you release the keys (merged from Behavior, design m12) · Show: All windows / Active app / This display (pop-up) · Style: Thumbnails / Icons / List (segmented) · Preview the selected window (subordinate, Thumbnails only; `previewSelected`, parity B2) · Size thumbnails automatically (subordinate, Thumbnails only) + Thumbnail size (SliderSetting 100–300 pt, step 10, default 170, subordinate, shown when automatic is off; fixes C2) | V | primary shortcut's scope/style |
| Windows | Include minimized and hidden windows · Windows from: All Spaces / Current Space / Other Spaces (step-4 fix rounds, ux M3 + parity Q1: every choice is enabled, and the pop-up shows the effective value: Current Space while the global `otherSpaces` feature is off. Choosing All Spaces or Other Spaces turns that feature on, after first writing every other shortcut's currently effective value explicitly, so no other shortcut changes; replaces design m12's disabled choices and footer) | V | per-shortcut options of the primary shortcut |
| Advanced | Window thumbnails (feature, Screen Recording footer) · Show on: Display with the active window / Display with the pointer · Window actions (Close, Minimize, Full Screen, Hide, Quit — one checkbox group) · Hover buttons · Select by hovering · Search · ⌘⇥ replaces the app switcher · Pass shortcuts through to apps (+ Only while full screen + app list) · Apps hidden from the switcher (AppListEditor) · Never show thumbnails for (password managers toggle + AppListEditor) · One entry per app · Include apps with no open windows (both for the primary shortcut, and their help says so; other shortcuts have their own in More Shortcuts; ux N6. Include apps with no open windows reads on only while the global `windowlessApps` feature is on and turns it on the same way as Windows from) · footer Restore Defaults…. No feature switches for other Spaces or windowless apps (removed in step-4 fix round 1, ux M3: the per-shortcut choices are their only controls) | A (19) | Features page (X), App Lists (X), Privacy (X) |

**Displays** root page (F composes; owners provide sections; header switch "Use Displays"; was 16 pages / ~170–330 controls)

```
[☀] Displays                                       (●)   "Use Displays"
    Brightness, resolution, and arrangement for every display.   2 displays
─────────────────────────────────────────────────────
⚠ status rows, only while true (automation paused · Safe Mode · safety helper stopped)
─────────────────────────────────────────────────────
Display                                      [Display Tools ▾]   section header, trailing (design m14)
[▭ Built-in Retina Display] [▭ DELL U2720Q]                       tiles (hidden with one display)
Display Details…                                                  for the selected display (r3 product minor 11)
Brightness              ☀ ━━━━━━●━━━━ ☀  [ 70% ]      (no reset glyph: live value, no default)
─────────────────────────────────────────────────────
Resolution                       [Default — 1512 × 982 ▾]
Refresh rate                                [120 Hz ▾]
▸ Resolution options
    Resolution     ◦━━━━━●━━━━◦  [1512 × 982]         SliderSetting, discrete, onRelease
    [Quick Changes ▾]  [Add to Favorites]             Quick Changes ▾ includes Undo/Redo Resolution Change
    Favorites: 1280 × 800 [Apply] [−] …
─────────────────────────────────────────────────────
Use as                                [Extended display ▾]
Arrange Displays…
Saved Layouts                                    On  ›
─────────────────────────────────────────────────────
Brightness and Dimming                              ›
Color                                          Off  ›
Hardware Controls                               On  ›
Keyboard                                            ›
─────────────────────────────────────────────────────
Virtual Displays                               Off  ›
Picture in Picture                             Off  ›
Automations                                    Off  ›
─────────────────────────────────────────────────────
Display Information                                 ›
                                             Advanced…  (?)
```

| Section | Controls | Owner |
|---|---|---|
| Header | Displays switch; status line ("2 displays") | F |
| Status rows (parity minor 1) | "Display automation is paused." [Resume Display Automation] (B) · "Safe Mode is on." [Leave Safe Mode…] (host) · "The safety helper stopped." [Restart Snaptic] (B) — each only while true | F + B |
| Display | Section header with **Display Tools ▾** trailing (always there, also with one display; design m14): Identify Displays, Redetect Displays, Show Displays Panel, Match Text Size…, Connect All Displays (if `disconnect`), Disconnect All But Main (if `disconnect`), Restore All Displays · `PerDisplayPicker` (hidden with one display; pop-up with > 4) · **Display Details…** (`ButtonRow` for the selected display, directly under the tiles; r3 product minor 11) · Brightness (SliderSetting, ☀︎ symbols, full range incl. XDR, `.live`, `defaultValue: nil`; value in nits when Show nits is on) · Automatically adjust brightness (built-in, only when the Experimental `autoBrightness` is on) | F, C |
| Resolution (selected display) | Resolution pop-up (scaled modes, "Default for display" first, favorites marked; with `hiddenModes` a "Show All Resolutions" section) · Refresh rate (if > 1) · HDR (if supported and `hdrToggle`) · Rotation (if `rotation`) · **Resolution options** disclosure (collapsed): resolution slider (SliderSetting, discrete, `.onRelease`), **Quick Changes ▾** (Toggle HiDPI, Native, Default, Native ÷ 2 "Half of native, sharper", Toggle Notch, ─, Undo Resolution Change ⌘Z, Redo Resolution Change ⇧⌘Z; the same two are the Settings window's Edit › Undo/Redo while the Displays page is shown; design M6), Add to / Remove from Favorites, favorites list (Apply, −) | D |
| Arrangement | Use as: Main display / Extended display / Mirror for "X" (pop-up; Apple copy) · Arrange Displays… (sheet: canvas + Snap to edges + keyboard Position/Align form as a disclosure) · Saved Layouts › (with arrangement, design M6) | D |
| Navigation | Group 1: Brightness and Dimming › (renamed so VoiceOver doesn't read "Brightness" twice; design M6) · Color › · Hardware Controls › ("Volume, input, and power for displays that support them.") · Keyboard › — Group 2: Virtual Displays › · Picture in Picture › · Automations ›. Full-width grouped rows; a row shows On/Off only when its sub-page has a feature switch (Brightness and Dimming and Keyboard show none; consistency m14). Always present | F + owners |
| Details | Display Information › (last row; Display Details… moved under the tiles) | F |
| Footer | Advanced… · (?) | F |

Height (design M6): about 1,000 pt with every section, so at the default 720 pt the first navigation group starts above the fold on a 14" display; the root page is a scrolling hub by design.

**Display Details…** sheet (per selected display; F + B + D; no nested sheets):

| Group | Controls |
|---|---|
| Identity | Name (field + Use the System Name) · Icon (glyph tiles) · **Customize Displays Menu…** link (design m2): closes the sheet and opens Menu Bar › Customize Displays Menu with this display selected (parity M6; per-display visibility lives only there) |
| Connection (D; design M9) | Disconnect / Connect (if `disconnect`) · Never disconnect automatically (built-in, if `autoDisconnectBuiltin`) · **This display doesn't support hardware controls** (allow auto-disconnect without a power reading; design m2) · Underscan (Experimental, SliderSetting `.onRelease` with the confirmation; replaces the draft + Apply) |
| Menu bar overlays (C) | Black strip behind the menu bar · Top / bottom corner radius (if `menuBarOverlays`) |
| Match text size (D; if `scaleMatch`) | Disclosure: Include this display · Reference display · Match tolerance · Preview / Apply |
| Manage | Copy Settings From ▾ (pull-down, design M4) · Forget Remembered Resolution · Forget This Display… (standard alert). Copy Settings From is a copy, not 0.2's move (step 4): after a confirmation it replaces brightness, color, resolution, hardware control tuning, keys (with the audio device) and connection settings; this display keeps its name, icon, panel measurements (gamma/XDR answers, learned DDC framing), its own unlocked manufacturer codes (E0–FF, never copied) and Picture in Picture setups, and the remembered display stays. When only some setups fit, the checkbox says “Also move 2 of its 3 Picture in Picture setups”. The confirmation's "Also move its Picture in Picture setups" checkbox (off by default; review round 3 parity R1) moves the remembered display's setups here, ids and Keyboard Shortcuts unchanged, up to 8 (Kit `DisplaySettingsCopy`) |
| Information | Disclosure: transport, masked serial, EDID Copy Hex / Copy Base64 (EDID **Export…** lives on Display Information, so no file panel opens over this sheet; design m6) |

**Displays › Advanced** sheet (F composes; cross-cutting groups only, 25 controls, design M9):
1. **Use Snaptic for** (feature switches, plain words, only for features without their own sub-page switch): Brightness control, Resolution control, Arrangement and mirroring, Rotation, Keyboard shortcuts, Brightness indicator, Disconnect displays (Beta). (F; replaces Features page; Hardware controls, Color, Saved layouts, Virtual displays and Picture in Picture keep their switch on their sub-page only)
2. **Confirm display changes** (B; was Safety page): Confirm resolution changes (one picker, one label set), Revert after N s (StepperSetting 5–60), Tell me when displays were restored, Restore All Displays shortcut (one `ShortcutSetting` over two fields, consistency M5: recording sets `panicHotkey` (custom combo, tried first; the fixed default and fallback ⌃⌥⌘⇧⎋ stay behind it exactly as in 0.2); "Use Default" sets `panicHotkey = nil` and shows "Default (⌃⌥⌘⎋)"; Clear sets `panicHotkeyEnabled = false` with its 0.2 meaning (no shortcut at all, help warns); no data migration), Allowed without asking (the single list); Resume Automation as a status row action while paused.
3. **Other display apps** (A): Pause overlapping features / Run both (radio).
4. **Resolution filters** (D): Offer modes below 720p · Remember my choice · Only native aspect ratio on the slider · Show values as · Snap to favorites · "Filters for <display>" disclosure (DPI filter, width limits, refresh filters).
5. **Experimental** (F lists, owners implement): HDR switch, Underscan, Built-in auto-brightness, Brightness broadcast (`osdBroadcast`, + notification name), Show all resolutions (`hiddenModes`) — each with an Experimental badge and one help line.
6. **Permissions** (parity minor 4): the 0.2 Features-page permission rows become this group's footer status ("Some features need Accessibility." [Open Accessibility Settings…]) and the Permissions page rows. Night Shift and Apple display presets move to Color › Advanced, HDR virtual modes to Virtual Displays › Advanced (owners keep their switches next to their settings).
Footer: Restore Displays Defaults… (scope "Displays settings") · Done.

Sub-pages (each: `SettingsPageHeader` with the feature-group switch where one exists, own Advanced… when needed):

| Sub-page | Switch (features) | Visible | Advanced / removed |
|---|---|---|---|
| Brightness and Dimming (C; route id `displays.brightness`) | — | `PerDisplayPicker` for the per-display rows (parity minor 2) · Restore brightness at login and wake (pop-up incl. Off = `brightnessRestore`) · Smooth transitions · Sync brightness (switch `sync`; source, follow, offset for the selected display as subordinate rows) · Extra brightness (switch `xdr`, Beta, XDR displays only; "Maximum extra brightness" for the selected display + "Pause below battery" SliderSettings subordinate) · Dim when the screen locks (switch `dimOnLock`; level slider subordinate) · Dim all the way to black (`dimToBlack`; design m2) · Show brightness in nits (`nits`; single field, duplicate 3) | A: **Brightness methods** (Apple native / DDC / Color table / Overlay checkboxes, per-display "Use" picker with "Now using …", custom switchover + slider, minimum hardware level, XDR method, color-table check "Ask Again"; moved from root Advanced, design M9), custom nits range fields, Stop at 100% detent, XDR default maximum, XDR "Pause in Low Power Mode", XDR Test, sync "Follow outside changes" |
| Color (C) | Color adjustments (`color`) | Display tiles · Software contrast, Gamma, Temperature, Black level, White level (5 SliderSettings) · Invert colors · Adjust this display (on = not suspended; design m2) · Color profile (pop-up, `colorProfiles`) · Apple display preset (pop-up, when `applePresets` is on) | A: Color profiles switch (`colorProfiles`), Gain, per-channel RGB gain and gamma (6), profile actions pull-down (Show in Finder, Open in ColorSync Utility, Restore Previous), keep color-table dimming with custom profiles, suspend on all displays, shortcut step sizes, **Night Shift** (Experimental switch + "Night Shift warmth"), **Apple display presets** (Experimental switch); footer Restore Defaults… asks "This display / All displays" (replaces "Reset This Display") |
| Hardware Controls (C) | Hardware controls (`ddcControls`) | External display tiles · Use hardware controls for this display · Volume (`.live`) + Mute · Hardware contrast (`.live`) · Input (pop-up, if `ddcInput`) · Turn Off / Turn On (if `ddcPower`) · custom control sliders (if any are defined) | A: Input switching (`ddcInput`) and Power control (`ddcPower`) switches, read back values + interval, re-send after wake, per-control tuning as **disclosure rows** (raw 0/100%, invert, show in menu, read-back interval; no per-control sheet), input list editor, standby value, custom controls editor (`ddcCustom`), raw VCP get/set + unlock (disclosure), timing (reply delay, retries, write twice, ignore checksums, Forget Learned Framing), "Hardware information" (status, connection, framing, writes today, model, MCCS, supported codes; Read Capabilities, Check Connection) |
| Keyboard (C) | — | Brightness keys (switch `brightnessKeys`; "Change: display under the pointer / main / all" pop-up) · Volume keys (switch `volumeKeys`; target pop-up) · Brightness and volume indicator (pop-up incl. "Use the system indicator" on 14/15; design m2) · Indicator position · Keyboard Shortcuts… (`ButtonRow` → sheet: **one grouped list** of all Displays actions — Brightness, Volume & contrast, Resolution (incl. favorites), Arrangement, Tools (Show Displays Panel, Identify, Redetect, Restore All Displays, Resume, Display Information, Stop Picture in Picture streams), custom actions — with filter field) | A: also let macOS handle brightness / volume / mute keys, steps / fine steps (StepperSetting), F14/F15, per-display "keys change this display", show volume indicator per display, sound output name, input slots, indicator "show on", show value, Preview Indicator; Modifiers reference → (i) popover |
| Saved Layouts (D) | Saved layouts (`layouts`) | Save Current Layout… · list (name, Matches badge, Apply, Details… sheet: apply automatically, priority, Trusted / Stop Trusting, Update to Current, Delete; drag or ▲▼ to reorder) · Protect the current arrangement (switch `protection`) | A: protected fields (5 checkboxes), Update Protected State to Current, Offer Undo after automatic apply, Forget All… |
| Virtual Displays (D) | Virtual displays (`virtualScreens`, Beta) | List (Connected switch, Details…) · New Virtual Display… (sheet with shape picker + recipes as tiles) · Sharper text on this display (Smart HiDPI, switch per display, Beta) | A: Sharper text switch (`smartHiDPI`, Beta), behavior toggles (3), "All Virtual Displays ▾" pull-down (Connect, Disconnect, Reconnect, Disassociate, Discard…), Smart HiDPI size and HDR (PQ), **HDR virtual modes** (Experimental switch); the Details sheet replaces the inline editor, "Sizes" becomes a table with + / − |
| Picture in Picture (E) | Picture in Picture (`pip`) | Screen Recording status row · Running list (Pause/Show/Stop; Crop in the row menu; Stop All in the section header) · Saved PIPs list (Start, Edit…) · New PIP… / New Stream… · Import Color Lookup Table… (`ButtonRow`, opens its file panel on the Settings window, never over a sheet; design m6) | Editor = sheet (name, show as, stream onto, window, capture, orientation, full screen, filters `pipFilters` sections); A: Filters switch (`pipFilters`), Never capture these apps (AppListEditor + Restore Defaults), pause covered PIPs, "⌃⌥⌘P stops streams" switch (shortcut in Keyboard Shortcuts) |
| Automations (A) | Section switches: Event hooks (`hooks`), Custom actions (`customActions`) | Hooks list (Enabled, When, Details… sheet) + Add Hook… · Actions list (Show in menu, Details… sheet with Run Now) + Add Action… | Sheets bind directly to config (fixes B2); action shortcuts also listed in Keyboard Shortcuts… |
| Display Information (F; design M4) | — | Live report (refreshes on change, no Refresh button) · Copy Report · Export… · EDID Export… for the selected display (moved from Display Details, design m6) · safety-helper status rows · pending confirmation · undo journal · **Unavailable on this Mac** (user titles, never camelCase) · **Remembered displays** (Forget… per row, Forget All…; parity B2) · Remembered resolutions (Forget per row) | — |

**Empty states** (design m9): Hardware Controls "Connect a display that supports hardware controls." · Saved Layouts "Save your current arrangement to restore it later." · Virtual Displays "Create a display that exists only in software." · Picture in Picture "Show a live view of any window or display." · Automations "Run a program when displays change." **File panels** are never presented on a sheet (design m6): Export Settings… closes its options sheet, then shows the save panel on the Settings window; Import Settings… is a page button.

**Awake** (G; header switch, AX label/tooltip "Use Awake"; no second help line in the header, the confirmation alert carries that text; design B1, M7, parity M7)

```
[☕] Awake                                           (●)   "Use Awake"
     Keep your Mac awake for a while, or automatically
     when certain conditions are met.
──────────────────────────────────────────────────
Your Mac can sleep as usual.          [Pause Rules ▾] [Keep Awake ▾]  click = default session, ▾ = any (R5-9); Pause Rules ▾ only with rules
  active: Keeping your Mac awake until 3:45 PM   [Options ▾] [Turn Off]
          1h 12m left · Appearing active                   (detail; no "Started from the menu")
          Then “Desk dock” keeps it awake. · Held by Terminal (2)       (each only while true)
  untilIdle: …until downloads and tasks finish · Ends after 5 min with no activity · quiet for 2 min
  holds only: Held by Terminal (2)                         [Turn Off]   (R5-10)
  after a non-user end (12 h): Ended at 3:12 AM: battery below 20%.
  paused (R5-11): primary line follows the session; detail "Rules are paused until 4:00 PM."; [Resume] in Pause Rules ▾'s slot
──────────────────────────────────────────────────
Default session                        [Until Turned Off ▾]
Keep the display on                                   (•)
  When off, your Mac stays awake but the display can turn off.
Sessions in the menu                               [Edit…]
──────────────────────────────────────────────────
End sessions automatically                                 (laptops only)
When the battery is low                               (•)
    Battery level       ━━━━●━━━━━  [ 20% ]            (reset slot empty at the default; r3 product minor 1)
When the power adapter is disconnected                ( )
──────────────────────────────────────────────────
Start automatically
Desk dock                                      Active  ›   rule rows (list)
  While “DELL U2720Q” is connected
[Add Rule…]
   none yet: "Keep your Mac awake automatically, for example while a display is connected."
──────────────────────────────────────────────────
Keyboard Shortcuts…
Drives                                            Off  ›
History                                  Today 2h 10m  ›
footer: Choose where Awake appears in Menu Bar settings.  (link)      Advanced…  (?)
```

| Section | Controls | Where |
|---|---|---|
| Status | Status row (reaches everything when the status item is hidden, 26/27). Idle: "Your Mac can sleep as usual." + **Keep Awake** (R5-9: a pull-down with a primary action; click = default preset, ▾ = presets in order, While an App Is Running ▸, Custom…; design M7) and, whenever ≥ 1 rule exists and rules aren't paused, **Pause Rules ▾** (For 1 Hour / Until Tomorrow; lead r4, r3 product M2). Active: "Keeping your Mac awake until 3:45 PM" / "…until downloads and tasks finish" / "…while “Desk dock” applies" / "Held by Terminal (2)" (holds only) + detail ("1h 12m left", "Ends after 5 min with no activity · quiet for 2 min" for untilIdle, "Then “Desk dock” keeps it awake.", "Held by Terminal (2)" under another source, plus "Appearing active" / "Moving the pointer" / "Stopped appearing active after 1 hour." while relevant) + **Options ▾** (Add 15 Minutes, Add 1 Hour, Add Time… for timed and capped kinds; ─; ✓ Keep Display On, always while active; End Command-Line Holds while holds exist under another governing source (R5-10); Replace With ▸, the Keep Awake list (R5-9); parity M4) — or, when it would hold only Keep Display On (indefinite or uncapped session, no holds), a plain **Keep Display On** / **Let Display Sleep** button instead (r3 product minor 7) — + **Turn Off** (also in the holds-only state, where it ends the hold stack; R5-10). Pause Rules ▾ stays beside them while a rule exists. Last non-user end for 12 h. While paused: the primary line follows the session, "Rules are paused until 4:00 PM." is a detail line, and [Resume] takes Pause Rules ▾'s slot (R5-11; design M4). Buttons only, no switch (N5); none is a default button (r3 security L8) | V |
| Sessions (r3 product minor 6: one term) | **Default session** (pop-up of presets; sets `defaultPresetID`) · Keep the display on (edits `defaultOptions.display`; a running session that uses default options follows it at once; help "When off, your Mac stays awake but the display can turn off." (R5-11: it applies to every session using default options; the task-kind exception is gone); parity M4, M5, minor 9) · **Sessions in the menu**: Edit… (the "Sessions" sheet) | V |
| End sessions automatically | When the battery is low (switch) + Battery level (SliderSetting 5–50%, step 5, default 20, subordinate; design M7: "Below" was a fragment) · When the power adapter is disconnected; footer "Sessions always end below 5% battery or if your Mac gets very hot." | V (laptops only) |
| Start automatically (design M4) | No section switch: **Add Rule…** turns `triggers` on with the first rule. Rule rows (`ReorderableList`): name, `TriggerEngine.summary` subtitle, trailing "Active" / "Waiting" / "Off", chevron; click or Return opens `TriggerEditorSheet`; drag or VoiceOver Move Up/Down to reorder (help "Higher in the list wins."). Empty: the help line + Add Rule…. **Pause Rules** is reachable whenever a rule exists: the status row's Pause Rules ▾, Rules › in the Awake menu and in the compact section, the hotkey and `awake pause` (lead r4, r3 product M2; parity minor 10's menu-only rule is superseded) | V |
| Keyboard | Keyboard Shortcuts… (sheet: Keep Awake, Keep Display On, Start “<preset name>” ×4 (design m2), Pause Rules) | V |
| Navigation | Drives › (J) · History › (G). r2's "Menu bar icon ›" row is gone (a chevron must push, design M7); the page footer carries "Choose where Awake appears in Menu Bar settings." as a link | V |
| Footer | link · Advanced… · (?) | V |
| Advanced (11) | Activity: **Appear active** (`activity`; switch semantics §2.14; help "Keeps apps from marking you as away while a session runs.") · **Move the pointer slightly** (Experimental `pointerNudge`; help "Moves the pointer 1 point and back. Only for sessions you start in Snaptic. Needs Accessibility."; Accessibility footer + fix button) · **Stop appearing active after** (1 / 2 / 4 / 8 hours, default 1 hour; help "Counts from when Awake starts appearing active, also across back-to-back sessions."; design m2 partly rejected: "when inactive" would describe system idle, which the cap no longer uses, N10). End sessions automatically: When your Mac sleeps (help "When you choose Sleep or close the lid."; r3 product minor 9) · When you switch users (Immediately / After 1 Hour / Never) · When Low Power Mode turns on · After the screen has been locked for (Never / 1 / 4 / 12 hours). Display: Keep the display on while locked (C1). Restart: Continue sessions after Snaptic restarts · Start a session when Snaptic opens (pop-up of presets / None). **Other apps keeping your Mac awake** (inline live section, design M4: process names and assertion types, a warning row when system-wide `SleepDisabled` is on — "Sleep is turned off for this Mac by another app or command. Snaptic can't change this."; empty "No other apps are keeping your Mac awake."). Footer leading **Restore Awake Defaults…** (scope "Awake settings"; keeps history; turns pointer movement and Drive Alive off) | A |

**Turn-off confirmation** (the only copy of this text; §2.12 refers here, consistency m5): turning the header switch off while a session or an enabled rule exists asks "Turn off Awake? This ends the current session and stops automatic sessions." [Turn Off] [Cancel] (parity M7).

**Sessions** sheet (`PresetEditorSheet`, title "Sessions"; r3 product minor 6): `ReorderableList` of presets with + / − and Edit/Delete/Move VoiceOver actions; each row has an **Options** disclosure: name, kind (Until turned off / For a duration (h, m NumberFields) / Until a time (time picker) / Until downloads and tasks finish, with **At most** (No limit / 1 / 2 / 4 / 8 / 12 hours; parity minor 6) and a "Thresholds" disclosure: top process, new processes, total CPU, disk, network, quiet for; help "Disk activity counts every app, including Spotlight."), Display (*Default (<the page's Keep the display on>)* via `defaultDisplayPolicy(for:)`, the same for every kind (R5-11), e.g. "Default (Keep on)"; consistency m6 / Keep on / Can turn off / Keep on until idle for [n min]), Activity (*Default* / Off / Appear active / Move the pointer slightly; only when `activity` is effective). The page's Default session pop-up chooses the default (no ★).

Custom session panel (`CustomSessionPanel`, menu "Custom…"): For | Until | While an App Is Running; h/m fields, a time picker or an app pop-up; **At most** pop-up for the app kind (parity minor 6); Return = Start; ⌥ "Add Time…" opens it in extend mode.

Rule editor sheet (`TriggerEditorSheet`, parity minor 5, design M4, r3 product minor 5): **On** switch · Name (optional; placeholder = `TriggerEngine.summary` of the current conditions) · **Conditions**: "Keep your Mac awake while [all ▾ / any ▾] of these conditions are met" + a list of condition rows, each "[kind ▾] [is ▾ / is not ▾] [kind-specific fields]" with + / − (1…8 rows; + disabled at 8; the router kind is titled **"Connected to this network"**; no is / is not for Power, whose values include their inverses); a new rule opens with one condition row whose kind pop-up has focus (journey 7 ≈ 9 clicks) · Session options (Display; Activity *Off* / *Appear active* only, because rules never move the pointer; r3 consistency m12) · "Wait before starting" / "Wait before ending" (start/end delays) under a Timing disclosure · **After I turn it off**: [Resume when the conditions are next met ▾ / Resume after 15 min / 1 hour / 4 hours] (`resumeAfterManualEndMinutes`; Amphetamine re-activation parity) · footer leading **Delete Rule…** (standard alert) · Cancel / Done.

**Drives** (J, sub-page of Awake): header switch "Keep drives awake" (`driveAlive`) · eligible volumes list with switches (turning one on performs the first write, so the Removable Volumes prompt follows the click) and per-row status ("Can't keep this drive awake: …") · **Check drives every** (SliderSetting 30–600 s, default 120; design m2) · **Also when no session is running** (design m2). Empty: "Connect an external drive to keep it from spinning down."

**History** (G, sub-page): totals row (Today, Last 7 days) · list (Start Again in the row menu where `offersStartAgain`: hidden for command-line entries and for `process` and `automatic` kinds; parity minor 12, r3 consistency m3; app sessions use their locally stored bundle id; Start Again is a UI start) · Clear History…. Empty: `ContentUnavailableView("No Sessions Yet", systemImage: "cup.and.saucer")`.

**Permissions** (H): Accessibility and Screen Recording rows (state, "Needed by …", Open Settings, Show Snaptic in Finder, relaunch), Removable Volumes info row when Drive Alive is on ("macOS asks the first time Snaptic writes to a drive"), signer line (R5.7).

**About** (H): app icon, version, Check for Updates…, Acknowledgements… (sheet with MIT text and credits), **Display Information…** when Displays runs (says where it goes, design m14) or **Diagnostics Report…** (a host report sheet) when it doesn't.

**Counts** (r3; rule in §4.2; 1 built-in + 1 DDC external, default features, built-in selected; display tiles count toward the total only; consistency m14):

| Page | Settings | Buttons + nav rows + tiles | Total | Notes |
|---|---|---|---|---|
| General | 2 | 2 | 4 | card not counted (one-time); Copy Install Command appears only while Command-line control is on |
| Menu Bar | 8 | 1 | 9 | 3 presence pop-ups, Awake Time + Icon, Style, scroll, Snaptic tiles; Customize… |
| Window Switcher | 8 | 1 | 9 | shortcut, release, show, style, preview, auto size, minimized, Spaces; More Shortcuts… |
| Displays root | 4 | 1 tiles + 3 + 9 nav | 17 | brightness, resolution, refresh, use as; Display Tools ▾, Display Details… (under the tiles), Arrange…; hub exception (without nav rows 8) |
| Brightness and Dimming | 7 | 1 tiles | 8 | restore, smooth, sync, xdr (XDR only; 6 without), dim on lock, dim to black, nits |
| Color | 8 | 1 tiles | 9 | |
| Hardware Controls | 5 | 1 tiles + 1 | 7 | external only |
| Keyboard | 6 | 1 | 7 | |
| Saved Layouts / Virtual / PIP / Automations | 1 / 1 / 0 / 2 | 2 / 2 / 5 / 4 | 3 / 3 / 5 / 6 | lists count 1 |
| Awake | 5 | 5 + 1 list | 11 | default session, keep display on, battery low + level, adapter; Edit…, Add Rule…, Keyboard Shortcuts…, Drives, History, rule list; desktop: 2 settings, 8 total (status-row actions incl. Pause Rules ▾ not counted, §4.2) |
| Advanced sheets | — | — | General 4, Switcher 19, Displays 25, Brightness 20, Color 15, Hardware 18, Keyboard 14, Awake 11 | ≤ 25 each |

Default-visible settings across the five root pages ≈ 30, ≈ 60 including sub-pages (was ≈ 245).

### 4.4 Duplicates ([UA] §2.4) — one owner each

| # | Duplicate | Resolution |
|---|---|---|
| 1 | Confirm resolution changes (Resolution + Safety) | Displays › Advanced › Confirm display changes only; one label set |
| 2 | Allowed without asking (DDC + Safety) | Displays › Advanced › Confirm display changes only |
| 3 | Show nits (`brightness.showNits` + `keys.osdShowNits`) | One control `brightness.showNits` (migration M5) on Brightness |
| 4 | Display order/visibility (Names + Menu) | Menu Bar › Customize Displays Menu… only; Display Details has a "Customize Displays Menu…" link, not a control (parity M6) |
| 5 | Panel/Identify shortcuts (`menu.*Shortcut` + `keys.shortcuts`) | `keys.shortcuts` only (migration M4); Keyboard › Keyboard Shortcuts… |
| 6 | Feature on/off on two pages + 4 "is off" variants | Feature switch where used; one `SettingsPageHeader` switch / `ToggleSetting`; `FeatureHighlights` for off state |
| 7 | Live controls on 4 surfaces, different ranges | One `DisplayLiveControls` model (F) with the full range, used by root page, menu and panel; sub-pages keep only settings, never a second copy of a live slider |
| 8 | Contrast software vs hardware | Labels "Software contrast" (Color) and "Hardware contrast" (Hardware Controls) |
| 9 | Temperature vs Night Shift warmth | Night Shift in Color › Advanced (Experimental) with its own label "Night Shift warmth" |
| 10 | Capture privacy Switcher vs PIP | Kept separate (different scopes), renamed "Never show thumbnails for" / "Never capture these apps", both `AppListEditor` |
| 11 | Switcher per-shortcut vs feature switches | Primary shortcut options visible; no separate feature switches (step-4 fix round 1, ux M3): a per-shortcut choice that needs `otherSpaces`/`windowlessApps` turns the feature on and first writes every other shortcut's effective value, so the others don't change (parity Q1) |
| 12 | Volume OSD (Keys + OSD page) | Keyboard page only (OSD page X) |
| 13 | Menu settings inside Displays pages | All on Menu Bar page (N7) |
| 14 | Restore All Displays in 4 places, fixed shortcut | Menu Display Tools, panel, root page Display Tools ▾ (all actions); shortcut editable in one place (Displays › Advanced › Confirm display changes, mirrored in the Keyboard Shortcuts list) |
| 15 | Awake "on" twice (module switch vs session switch, parity M7 / design B1) | Header switch = module ("Use Awake"); sessions = buttons (Keep Awake / Options ▾ / Turn Off) in Settings, native items + a mouse switch in the menu |
| 16 | Awake icon off in three places (`indicator`, style `.hidden`, `ownItem`; parity M1) | `MenuPresence` only; `.hidden` style deleted; `indicator` is an internal capability |
| 17 | Rules on/off in three places (section switch, row switches, Pause; design M4) | One switch per rule, inside its editor sheet; **Pause Rules** (one action, several entry points: Rules › in both menus, the status row's Pause Rules ▾, hotkey, CLI); the status row shows a paused state with Resume |

### 4.5 Live-update architecture (fixes [UA] §1 at the source)

| Change | Owner | Fixes |
|---|---|---|
| `DisplayRuntime` gains `@Published brightnessPosition: Double?` (full range incl. XDR), `brightnessRange: ClosedRange<Double>`, `contrastRange`, `volumeRange`; BrightnessService/DDCController write only through these; pages never read `BrightnessService.states` | lead (type), C (writers) | A1, A2, overview 0…1 range |
| Per-display sections are subviews with `@ObservedObject var live: DisplayRuntime` (the `DisplayControlsCard` pattern) | page owners | A1, A2 |
| **Per-controller revision objects** (code M12): `DisplaysRuntimeState.revision(_ id: DisplayControllerID) -> ControllerRevision`, one `ObservableObject` per id with `@Published private(set) var count: UInt64`; `bump()` coalesced with `DispatchQueue.main.async` (runs during menu tracking, N15) to one publish per turn per id, ≤ 15 Hz **trailing-edge** (the last bump in a window always publishes; code R2-M7); a section observes only the ids it shows. Controllers bump when page-visible state changes (rotation/HDR/underscan, protection, layouts, virtual live/busy, Smart HiDPI pairs, undo/redo/favorites, Night Shift, guard status, capture sessions) | lead (type), B/C/D/E (bumps) | A4, A6–A11; delete the `objectWillChange.send()` pokes and Safety's 2 s timer (lint L7) |
| **Config slices** (code M12): `ConfigSlice<T, V>` (lead, `Core/ConfigSlice.swift`) publishes only when `store.value[keyPath:]` changes; a view owns it as `@StateObject` (or reads one cached in the environment), never creates it in `body` (code minor 6); every new section reads config through a slice of its own `DisplaysConfigSection`. `DisplaysPageEnvironment` keeps forwarding the config store's `objectWillChange` until the **step-3 exit**, so the 23 legacy page files still re-render on writes; the lead removes the forwarding (it then forwards only `displays`, `effectiveFeatures`, `availability`, `moduleState`, panic flags) once every page uses slices (code R2-M2b) | lead (type), page owners | a 15 Hz slider commit re-renders one section, not the whole Displays tree |
| **Live hardware path** (code M12): `DisplayLiveControlling` (lead protocol, C implements) is the only route from a `.live` slider to hardware; a latest-wins mailbox per (display, control), DDC writes ≤ 20 Hz, `phase: .ended` always delivered; the slider shows `drag ?? live value`; on `.ended` C sets `DisplayRuntime`'s value to the target optimistically and ignores readbacks that differ for 1 s, so the slider doesn't snap back (code minor 7) | lead, C, H | "laggy drags", fights between readback and drag |
| No `@State(initialValue:)` copies of model values; editors bind to the store or resync with `.onChange(of:)` | owners of ShortcutEditor (H), Hook/Action/CommandEditor (A), NameField (F), CustomSliderRow (C, seeded from `ddc.lastReading`) | A3, B1–B3 |
| `SliderSetting` drag-local state: `@State drag: Double?`; shows `drag ?? value`; commit per `SliderCommit`; final value on release; `preview` for live hardware feedback without config writes | H | C1 "laggy drags" |
| Config fan-out by section: Kit `DisplaysConfig.changedSections(old:new:) -> Set<DisplaysConfigSection>` (cases below, with `perDisplay` split per subsection incl. `perDisplayKeys` and `perDisplayPIP`; consistency m8); `DisplayFeatureController` gains `static var observedSections: Set<DisplaysConfigSection>` **declared in the protocol body** with a protocol-extension default of `allCases` (a requirement, so `type(of: c).observedSections` dispatches to a conformer's narrower set; an extension-only member would always return the default; code sig), so the ~21 conformers compile at step 0; `DisplaysModule.configChanged` notifies only controllers whose sections changed; `ColorController` re-applies gamma only for displays whose `perDisplay.color` changed | lead (+ every controller narrows its sections in step 2) | C1 fan-out, gamma reapply per tick |
| `ManagementBindings.perDisplay` and other binding helpers stop calling `sanitized()` per tick (ConfigStore sanitizes on load and external change; UI ranges are already clamped); binding helpers collapse to `SettingsBinding` (H) | H + D | C1 |
| Switcher `AppSettings` saves through a 250 ms debounce like `ConfigStore` | A | C2 |
| `MenuSliderRow` (M, AppKit) replaces `MenuSliderItem` for brightness, volume, contrast, custom DDC and (opt-in, top level only) resolution sliders: value label, `range` in init, `bind(to:)` so values follow live changes while the menu is open (subscribed with `.receive(on: DispatchQueue.main)`, never `RunLoop.main`, N15); never fights a drag. No slider is ever in a submenu | M (+ C, D contributors adopt) | M1 |

```swift
// Core/ConfigSlice.swift (lead)
@MainActor final class ConfigSlice<T: ConfigModel, V: Equatable>: ObservableObject {
    @Published private(set) var value: V
    init(_ store: ConfigStore<T>, _ keyPath: KeyPath<T, V>)
}
// Displays/DisplaysContracts.swift (lead)
@MainActor final class ControllerRevision: ObservableObject {
    @Published private(set) var count: UInt64 = 0
    func bump()                                    // coalesced per main-queue turn
}
enum LiveControl: Hashable { case brightness, contrast, volume, custom(UInt8) }
enum DragPhase { case began, changed, ended }
@MainActor protocol DisplayLiveControlling: AnyObject {
    func set(_ control: LiveControl, _ value: Double, for display: DisplayKey, phase: DragPhase)
}
// In `protocol DisplayFeatureController { … }` itself (requirement):  static var observedSections: Set<DisplaysConfigSection> { get }
extension DisplayFeatureController { static var observedSections: Set<DisplaysConfigSection> { Set(DisplaysConfigSection.allCases) } }

// SnapticKit/Config/ConfigDisplays.swift (lead; consistency M7): one case per DisplaysConfig field, per-display split
// (R5-2: no `migrations` case; DisplaysConfig has no such field)
package enum DisplaysConfigSection: String, CaseIterable, Sendable {
    case features, brightness, ddc, keys, color, resolution, virtualScreens, management, layouts, pip, automation,
         safety, identity, menu
    case perDisplayBrightness, perDisplayDDC, perDisplayKeys, perDisplayColor, perDisplayResolution,
         perDisplayManagement, perDisplayIdentity, perDisplayPIP
}
/// Page Restore Defaults scopes (consistency M7). `.all` = Displays › Advanced; others = that sub-page's Advanced.
package enum DisplaysRestoreScope: Equatable, Sendable {
    case all, brightness, color(DisplayKey?), hardware, keyboard, layouts, virtualDisplays, pip, automations, confirm
}   // color(nil) = all displays, color(key) = "This display"
// DisplaysConfig: package func restoringDefaults(scope: DisplaysRestoreScope) -> DisplaysConfig
```

Rule (lint + review): a Settings view may read controller state only inside a view that observes the relevant `ControllerRevision` or `DisplayRuntime`.

### 4.6 Config migration (no setting lost)

All migrations are pure Kit functions with tests. **Each runs once**: markers live in their own store, `MigrationLedger` (lead, Kit `SnapticKit/Config/ConfigMigrations.swift`, key `SnapticMigrationsV1`, `ConfigStore<MigrationLedger>` owned by `ModuleHost`: `package var done: Set<String>` decoded element-wise; R5-2: `MigrationID`, and every migration that needs a marker is a `migrated(ledger:)` function that `ModuleHost` runs, never a decoder), which 0.2 never reads or writes; a migration records its id after running and never runs again (code M3; a later user "off" sticks). Because 0.2 can't drop them, a 0.3 → 0.2 → 0.3 round trip doesn't re-run M5 or M10 over choices the user made in 0.3 (r3 code minor 13; r3's per-model `migrations` lists are not added). **Legacy fields stay declared, decoded and encoded until 0.4** (struct Codable drops undeclared keys; only `LossyMap` keeps unknown ones), so a downgrade to 0.2 still reads them. Old-key removal is a 0.4 task.

| # | From | To | Where |
|---|---|---|---|
| M1 | `DisplaysConfig.features.sleepPrevention` + `perDisplay.*.management.preventSleep` (+ that display's `identity.fingerprint`, `customName`/`lastKnownName`), read from raw JSON | Awake rules "While a display is connected" (`.any` over `display(.specific)`, options `.keepOn`), **at most 8 displays per rule** (more → "… (2)", "… (3)"), rule ids `StableID.derived(namespace: "awake.m1", name: "<chunk index>:" + the chunk's sorted display keys joined by ",")` (N18; valid UUIDs, no SHA in Kit; r3 code sig row, M5), and the writer **replaces rules by id** instead of appending, so a re-run after a crash between saves gives the same rules once (test: two runs over the same JSON give equal ids and one set of rules); enabled iff 0.2 sleep prevention was **effective**: Displays module enabled ∧ feature on ∧ ≥ 1 display flagged (parity "Also"); if enabled, Awake module (presence `.ownIconWhenActive`) and `triggers` turned on, `newModuleCards` gains `.awakeMigrated` (the General card; a `NewModuleCard` case, so M3's filter keeps it; r3 consistency M2) and the first activation of a migrated rule shows the toast "Keeping your Mac awake while “DELL U2720Q” is connected is now part of Awake." [Show in Settings] once (then marker `fromDisplays.toast` is recorded; design M3); marker `fromDisplays.v1`; afterwards `save(force: true)` on the **modules store, then the Awake store, then the ledger** (the ledger's marker is the commit point; code minor 9) | Kit `AwakeMigration.fromDisplays(rawJSON:modulesEnabled:awakeShortcuts:) -> AwakeMigrationResult` (G; R5-12 adds the 0.2 hotkey move), run by `ModuleHost` after the Awake-disabled insertion (§2.13) and before modules start (lead) |
| M2 | `ModulePreferences.placement` (`shared/ownIcon/hidden`) + Displays `hideWithoutExternalDisplay` | `presence: MenuPresence`: `shared` → `.inSnapticMenu`, `hidden` → `.hidden`, `ownIcon` → `.ownIcon`, except Displays `ownIcon` + `hideWithoutExternalDisplay` → `.ownIconWhenActive` (design M5). `placement` and `hideWithoutExternalDisplay` keep being **written** from presence (`.ownIconWhenActive` → `.ownIcon` + hide flag for Displays, `.ownIcon` for Awake) so 0.2 reads them. When `presence` is absent but `placement` exists (0.3 → 0.2 → 0.3 round trip), Awake's `.ownIcon` decodes as `.ownIconWhenActive`, its default (code minor 9). `ModulePreferences.init(enabled:placement:…)` stays beside the new `init(enabled:presence:…)` until the step-3 exit (code sig) | `ConfigModules` decode (lead) |
| M3 | `ModulesConfig.showNewDisplaysCard` | `newModuleCards: [NewModuleCard]` (Kit enum `displays`, `awake`, `awakeMigrated = "awake.migrated"`) decoded through `LossyArray`, so an unknown card id drops only itself (r3 consistency M2); `showNewDisplaysCard == true` → `.displays`; marker `newModuleCards.v1` (R5-2) | `ModulesConfig.migrated(ledger:)`, run by `ModuleHost` (lead; R5-2) |
| M4 | `MenuConfig.showPanelShortcut`, `identifyShortcut` | `keys.shortcuts[DisplayActionID.fShowPanel]` (`"f.showPanel"`) and `[.fIdentify]` (`"f.identify"`), Kit constants in `KitModules.swift` (consistency M4), when those are unset; marker `menuShortcuts.v1`; legacy fields kept and encoded | `DisplaysConfig.migrated(ledger:)`, run by `ModuleHost` (lead; R5-2) |
| M5 | `keys.osdShowNits` (default false) | once: if `keys.osdShowNits` is true, set `brightness.showNits = true` (default true); otherwise leave it. r1 re-ran the OR on every decode, so a user's later "off" came back at the next launch (code M3); marker `showNits.v1` | `DisplaysConfig.migrated(ledger:)`, run by `ModuleHost` (lead; R5-2) |
| M6 | `SafetyConfig.panicHotkey` / `panicHotkeyEnabled` | **No data migration** (consistency M5): the UI edits the existing fields with their 0.2 meanings (§4.3 Confirm display changes); a `SafetyConfig` test pins that nil keeps "default + fallback" and `false` disables all | B (step 2) |
| M10 | Per-display `management.powerSwitch` (`HeaderPowerSwitch`: `none` / `disconnect` / `ddcStandby`) | once: any display with `.disconnect` → `menu.items[.dDisconnectItem] = .visible` (top-level "Disconnect" under that display's row); any with `.ddcStandby` → `menu.items[.cDDCPower] = .visible` (Kit constant, §2.2); `MenuConfig.items` is the `LossyMap<DisplayMenuItemID, MenuItemVisibility>` (r3 consistency M1, code sig row); the field stays decoded and encoded, unused (parity M6); marker `powerSwitch.v1` | `DisplaysConfig.migrated(ledger:)`, run by `ModuleHost` (lead; R5-2) |
| M7 | Switcher features `otherSpaces`/`windowlessApps` vs per-shortcut flags | unchanged storage; UI only | — |
| M8 | Raw feature flags of features without a switch in the new UI | unchanged; each still reachable (§4.8) | — |
| M9 | Awake indicator legacy values (r1 drafts never shipped) | none needed; `AwakeIndicatorConfig.sanitized()` maps unknown glyphs to `.cup` | — |

```swift
// SnapticKit/AwakeMigration.swift (G; consistency M7)
package struct AwakeMigrationResult: Equatable, Sendable {
    package var triggers: [AwakeTrigger]      // empty when nothing to migrate
    package var enableModule: Bool            // 0.2 sleep prevention was effective
    package var migratedDisplayNames: [String]   // ≤ 8, for the one-time toast; local UI only
    package var pauseRulesShortcut: HotkeyCombo?   // R5-12: bind to awake.pauseAutomatic
    package var droppedShortcut: Bool              // R5-12: a 0.2 combo existed and wasn't moved → Recent Notice
    package init(triggers: [AwakeTrigger], enableModule: Bool, migratedDisplayNames: [String],
                 pauseRulesShortcut: HotkeyCombo? = nil, droppedShortcut: Bool = false)
    package static let nothing: AwakeMigrationResult
        = AwakeMigrationResult(triggers: [], enableModule: false, migratedDisplayNames: [])
}
package enum AwakeMigration {
    package static func fromDisplays(rawJSON: Data?, modulesEnabled: Set<ModuleID>,
                                     awakeShortcuts: LossyMap<AwakeActionID, HotkeyCombo>) -> AwakeMigrationResult   // R5-12
}
```
**Round trip 0.3 → 0.2 → 0.3** (code minor 9, r3 code minor 13, documented in the README's downgrade note): the ledger key is untouched by 0.2, so no migration runs twice; values the user changes in 0.2 (legacy fields 0.2 still reads) are read again by 0.3 only where 0.3 still mirrors them (`placement`, `hideWithoutExternalDisplay`, §4.6 M2). Awake's stores are untouched by 0.2 (it doesn't know the keys).

Page **Restore Defaults…** resets only that page's scope through Kit functions (`AwakeConfig.restoringDefaults()`, `DisplaysConfig.restoringDefaults(scope: DisplaysRestoreScope)`, `MenuConfig()` etc.), each tested to leave other scopes, salts and history untouched and to turn pointer movement and Drive Alive volumes **off** (r1 security L6). Button titles name the scope ("Restore Awake Defaults…", §4.1). `AwakeConfig.restoringDefaults()` is written by G in step 2 (it needs G's and J's fields; code M14); step 0 has a stub returning `AwakeConfig()`.

### 4.7 Onboarding (H)

Welcome → Choose modules (3 rows with switches and one-line descriptions; Awake preselected for fresh installs; the Awake row's description ends "Its icon appears while your Mac is being kept awake."; design m11) → Displays chips (F, `DisplaysOnboardingStep.swift`; H owns only `Onboarding.swift`; r3 consistency m11; existing; summary lists **user words**, not feature ids; chips are toggles; includes the 0.2 chips **"Hide the menu-bar icon"** → Displays presence Don't Show, and **"Turn on Sharper Text"** → `smartHiDPI`; parity minor 3) → Permissions (only what was chosen) → Done. r2's Awake quick-setup step is dropped (it repeated two page controls; design m11), so no `OnboardingStep.awake` case is added (code minor 13, consistency m11 moot). One primary button, always in the window footer ("Continue" / "Done"); the in-form "Use These Features" button is removed.

### 4.8 0.2 → 0.3 control map (normative; parity B2)

One row per 0.2 control in [UA] §2.2 and §3.2 (identical per-display or per-item controls share a row). Destinations: **V** visible on the named page, **A** that page's Advanced sheet, **S** sub-page, **D** Display Details sheet, **K** a Keyboard Shortcuts sheet, **C** Customize Displays Menu sheet, **I** Displays › Display Information, **M** menu, **X** removed (reason given), **Exp** the page's Experimental group (kept; consistency m7). Pages: Gen = General, MB = Menu Bar, Sw = Window Switcher, Root = Displays root, Br = Brightness and Dimming, Col = Color, HW = Hardware Controls, Kb = Keyboard, SL = Saved Layouts, VD = Virtual Displays, PIP, Aut = Automations, Aw = Awake.

**Control registry** (N16; parity B1, M1; lead r3/r4; replaces r3's `ControlCatalog`/`MenuItemCatalog`/`ControlMap`, the DEBUG `ControlCoverage` walk and `gen-controlmap.py`; r3 code B1, M4). Reachability is checked against static declarations, not renders: grouped `Form`s are lazy, hardware-gated and subordinate rows don't exist on every Mac, and menus build lazily, so no single Mac could render everything (r3 code B1). Instead every surface **declares** its controls at compile time and CI checks the declarations.

```swift
// SnapticKit/Controls/ControlRegistry.swift (lead, step 0)
package struct ControlID: RawRepresentable, Hashable, Codable, Sendable {   // "awake.page.batteryFloor"
    package let rawValue: String
    package init(rawValue: String)
    package init(_ rawValue: String)        // views and builders use only this form, with a string literal (lint L15)
}
package struct LegacyControlID: RawRepresentable, Hashable, Sendable {     // "l.gen.cli.enabled" (§4.8.1)
    package let rawValue: String
    package init(rawValue: String)
}
package enum HardwareCondition: String, Hashable, Sendable {
    case builtinDisplay, externalDisplay, twoDisplays, ddcDisplay, ddcVolume, xdrDisplay, appleDisplay, hdrDisplay,
         notch, battery
}
/// Closed allowlist of runtime states a control can depend on (r3 code B1's "state-gated ids").
package enum ControlState: String, Hashable, Sendable {
    case safeMode, automationPaused, helperStopped, pendingConfirmation, screenRecordingMissing, accessibilityMissing,
         awakeActive, awakeIdle, rulesExist, rulesPaused, holdsExist, notAtDefault, commandLineOn, hiddenIconWarning,
         disconnectedDisplay, timedOrCapped
}
/// Availability as data (the §4.2 States rules); every condition must hold for the control to exist.
package enum ControlCondition: Hashable, Sendable {
    case displayFeature(DisplayFeature), awakeFeature(AwakeFeature), switcherFeature(SwitcherFeature), module(ModuleID)
    case hardware(HardwareCondition)
    case parentOn(ControlID)              // subordinate rows: shown only while the parent is on
    case perItem(String)                  // one instance per list item: "display", "rule", "preset", "customAction", …
    case state(ControlState)
}
package enum ControlKind: String, Hashable, Sendable {
    case setting, button, navigation, list, statusAction, shortcut, menuItem, menuSlider, menuSubmenu, menuSwitchHeader
}
package enum MenuCustomize: String, Hashable, Sendable { case threeWay, checkbox, none }   // Customize Displays Menu row
package struct MenuPlacementSpec: Hashable, Sendable {
    package let location: String          // "display submenu", "Displays section", "Display Tools", "Awake menu", …
    package let customize: MenuCustomize
    package let legacyMenuID: DisplayMenuItemID?
    package init(_ location: String, customize: MenuCustomize, legacy: DisplayMenuItemID? = nil)
}
package struct ControlSpec: Hashable, Sendable {
    package let id: ControlID
    package let kind: ControlKind
    package let when: [ControlCondition]      // [] = always present
    package let replaces: [LegacyControlID]   // the frozen 0.2 controls this one is the home of
    package let keys: [String]                // config key paths it edits (key cross-check below); may be empty
    package let menu: MenuPlacementSpec?
    package let search: SearchSpec?           // R5-13: the search entry is derived from the spec
    package init(_ id: String, _ kind: ControlKind, when: [ControlCondition] = [], replaces: [String] = [],
                 keys: [String] = [], menu: MenuPlacementSpec? = nil, search: SearchSpec? = nil)
}
/// One table per settings page, sheet, page section file and menu builder (§4.8.2); `<TypeName>Controls`, in
/// `SnapticKit/Controls/<TypeName>Controls.swift`, owned by the owner of the view or builder.
package protocol ControlTable {
    static var surface: String { get }        // every id starts with surface + ".", e.g. "awake.page"
    static var controls: [ControlSpec] { get }
}
package enum ControlRegistry {               // lead: the one list of types (§4.8.2); adding a table = one line here
    package static var tables: [any ControlTable.Type] { get }
}
// SnapticKit/Controls/ControlLegacy.swift (lead, step 0; the literal §4.8.1 table, frozen at 871c10b)
package enum ControlLegacy {
    package static var ids: [LegacyControlID] { get }                 // §4.8.1 expanded (588 ids)
    package static var switcherKeyPaths: [String: [LegacyControlID]] { get }   // for `--selftest-controls` (A); R5-13
    package static var internalKeys: Set<String> { get }              // config keys that are state, not controls
}
// SnapticKit/Controls/ControlRemovals.swift (lead, step 0): the "removed with reason" table (§4.8.1, last table)
package enum ControlRemovals { package static var removed: [LegacyControlID: String] { get } }

// App, Core/ModuleContracts.swift (lead): every page, sheet, section view and menu builder names its table, which keeps
// the declaration "next to" the type by name while the data sits in Kit, where the Linux test can see it (the app
// target isn't importable from Kit tests).
@MainActor protocol ControlDeclaring { associatedtype Controls: ControlTable }
// struct AwakePage: View, ControlDeclaring { typealias Controls = AwakePageControls; … }
```

Rules:
- A view or builder passes ids only as literals: `SettingRow(…, anchor: ControlID("awake.page.batteryFloor"))`, `MenuKit.toggle(…, control: ControlID("menu.display.hdr"))`. Per-instance controls (one per display, rule, custom action) share one id; `perItem` says so.
- `ControlID == SettingsSearchEntry.id == anchor` for every searchable row (r3 code minor 12).

**Kit test** (`ControlRegistryTests`, Linux + macOS; R5-13: tests 2, 3, the `replaces` ⊆ legacy check and `parentOn` run per table from step 1; totality (test 1's home check) and the key cross-check (test 5) are skipped until the step-3 exit):
1. Every `ControlLegacy.ids` entry is in the `replaces` of at least one spec **or** a key of `ControlRemovals.removed` with a non-empty reason, never both; neither table names an id that isn't in `ControlLegacy.ids` (a trailing `*` matches the pattern ids).
2. Control ids are unique across all tables and start with their table's `surface`; `parentOn` targets exist in the same table.
3. (R5-13) Every `setting` spec has a `search` spec; the derived entry ids are unique.
4. Every `l.menu.*` id with a home is replaced by a spec whose `menu.customize != .none` unless §4.8 says otherwise ("always while paused"), and `CustomizeMenuSheetControls` has one row per such spec (N16's show/hide guarantee).
5. **Key cross-check** (r3 code M4): `ConfigFixtures.full()` (lead, Kit: every optional set, one `perDisplay` entry, all features on) for `DisplaysConfig`, `ModulesConfig` and `AwakeConfig`, walked with `Mirror` into dotted key paths (`perDisplay.*.color.suspended`; walker rules in R5-13); every path is in some spec's `keys` or in `ControlLegacy.internalKeys`. A new 0.3 setting without a declared control fails here; nothing depends on `JSONEncoder` dropping nil optionals.
6. (R5-13) No table type is listed twice; that every conformer is registered is checked by L15, not against a frozen list.

**Lint L15** (python, lead, step 0; ratchet-free, because the tables start empty and grow with the views):
- `ControlID(` with anything but one string literal is banned outside `SettingsUI/` and `Core/MenuKit.swift` (their internals forward a `ControlID` value).
- Every file under `Sources/Snaptic/` that uses a `ControlID("…")` literal declares the type's table (`typealias Controls = X`), and each literal is an id in `SnapticKit/Controls/X.swift` (several types may name one table, e.g. a page and its section views).
- Every id in a table is used as a literal by at least one type that names the table (declared ⇒ constructed in code).
- Every `ControlTable` conformer under `SnapticKit/Controls/` is listed in `ControlRegistry.swift`.

The Switcher `Config` lives in the app target, so its keys are checked by `Snaptic --selftest-controls <token-file>` (A, `SelfTest.swift`, token-gated like `--selftest-helpers`, run by the macOS CI job from step 1): in process it builds a `Config` with every optional set (`gatherShortcut`) and one shortcut, walks its key paths with `Mirror`, and exits nonzero unless every path is in `ControlLegacy.switcherKeyPaths` or in the `keys` of a Switcher table (a new Switcher key without a control fails CI), and every legacy path still exists or is removed (r3 code M4; no shell comparison script).


**General**

| 0.2 page | 0.2 control | 0.3 home |
|---|---|---|
| Modules | Window Switcher switch · Displays switch | Sw / Root header switches; Onboarding |
| Modules | "New: Displays" card (Turn On Displays…, Not Now) | Gen card, generalized (`newModuleCards`); its "Turn On Awake" targets the Awake module switch + page (parity minor 3) |
| Menu | Switcher **Show** · Displays **Show** | MB pop-ups |
| Menu | Switcher **Icon** · Displays **Icon** (own icon) | MB glyph tiles under the module (Always Show / Show When Active) |
| Menu | Displays "Hide the icon when no external display is connected" | MB Displays pop-up *Show When Active* (migration M2; design M5) |
| Menu | Snaptic **Icon** | MB Snaptic icon tiles |
| Menu | Scroll on a slider to adjust | MB V |
| Menu | Display blocks Expanded/Compact | MB **Style** (Standard / Compact; r3 consistency m5) |
| Menu | Main display first · Status badges · Header row with one display · Section order ▲▼ · Display order ▲▼ + Use the Default Order | C (Main display first = the pinned "Main display" row in the order list) |
| Menu | ≈ 46 Visible/In submenu/Hidden pickers | C (disclosure groups Per Display / Displays Section / Display Tools, human titles, every item of the "0.2 menu" table below; per-display items three-way, the rest checkboxes; quick-menu items X → their Display Tools twin, C3) |
| Menu | Reset Menu Settings | C footer Restore Defaults… (and MB footer) |
| Menu | Hidden-icon warnings | MB status rows |
| Command-Line | Allow command-line control · Copy install command | Gen V |
| Command-Line | Let commands skip the confirmation panel · exit-code footer | Gen A |
| Startup | Launch Snaptic at login | Gen V "Open at login" |
| Permissions | Permission rows, Open Settings, Relaunch | Permissions page |
| Backup & Reset | Export… · Import… | Gen V |
| Backup & Reset | Reset All Settings… | Gen A footer (destructive) |
| Safe Mode | Restart in Safe Mode / Leave | Gen A; M status row "Leave Safe Mode" |
| Other Display Apps | Pause overlapping / Run both | Root A › Other display apps |
| About & Licenses | Check for Updates… · MIT text | About V · Acknowledgements… sheet |

**Window Switcher**

| 0.2 page | 0.2 control | 0.3 home |
|---|---|---|
| Features | Thumbnails | Sw A "Window thumbnails" (Style stays V) |
| Features | Preview (`previewSelected`) | Sw V "Preview the selected window" |
| Features | Other Spaces · Windowless apps | the per-shortcut choices: Sw V "Windows from" (All/Other Spaces turn `otherSpaces` on), Sw A and More Shortcuts "Include apps with no open windows" (turns `windowlessApps` on); other shortcuts keep their effective value (step-4 fix rounds, ux M3, parity Q1) |
| Features | Search · Close · Minimize · Fullscreen · Hide · Quit · Hover buttons · Hover select · ⌘⇥ takeover · Passthrough | Sw A (window actions as one checkbox group) |
| Features | Permission rows | Permissions page; Sw status row "Window thumbnails need Screen Recording." (§4.3 Window Switcher) |
| Shortcuts | Primary: Modifier, Key, Show, Style, Spaces, Include minimized and hidden | Sw V |
| Shortcuts | Primary: Include apps with no open windows · One entry per app | Sw A |
| Shortcuts | Other shortcuts (all options), Add shortcut, Delete | Sw K (More Shortcuts…) |
| Shortcuts | Gather windows recorder | Sw K (More Shortcuts…) |
| Behavior | Switch when the modifier key is released | Sw V (Shortcut section) |
| Behavior | Show the switcher on | Sw A |
| Thumbnails | Auto-size · Size slider | Sw V (subordinates of Style = Thumbnails) |
| App Lists | Hidden from the switcher · Apps that keep the shortcut · Only while full screen | Sw A |
| Privacy | Never capture password managers · Never capture these apps | Sw A "Never show thumbnails for" |

**Displays: feature switches** (0.2 Display Features page, 47 switches + 2 always on)

| Feature | 0.3 switch |
|---|---|
| `overview`, `diagnostics` | always on (no switch) |
| `resolution` · `brightness` · `shortcuts` · `osd` · `rotation` · `disconnect` (Beta) | Root A › Use Snaptic for |
| `mainDisplay`, `arrangement`, `mirroring` | Root A › Use Snaptic for "Arrangement and mirroring" (one switch writes all three; shows `arrangement`; mixed 0.2 values kept raw until touched) |
| `hiddenModes` · `autoBrightness` · `osdBroadcast` · `underscan` · `hdrToggle` | Root A › Exp |
| `scaleMatch` | D › Match text size (disclosure switch) |
| `menuBarOverlays` | D › Menu bar overlays (group switch) |
| `autoDisconnectBuiltin` (Beta) | D (built-in) › Connection |
| `brightnessApple`, `brightnessDDC`, `brightnessGamma`, `brightnessOverlay` | Br A › Brightness methods |
| `brightnessRestore` · `dimToBlack` · `dimOnLock` · `nits` · `xdr` · `sync` | Br V |
| `color` | Col header switch |
| `colorProfiles` · `nightShift` · `applePresets` | Col A · Col A › Exp · Col A › Exp |
| `ddcControls` | HW header switch |
| `ddcInput` · `ddcPower` · `ddcCustom` | HW A |
| `brightnessKeys` · `volumeKeys` | Kb V |
| `layouts` · `protection` | SL header switch · SL V |
| `virtualScreens` · `smartHiDPI` · `hdrVirtual` | VD header switch · VD A · VD A › Exp |
| `pip` · `pipFilters` | PIP header switch · PIP A |
| `hooks` · `customActions` | Aut section switches |
| `sleepPrevention` | X → Awake trigger (migration M1); removed in step 3 |

**Displays: per-page controls**

| 0.2 page | 0.2 control | 0.3 home |
|---|---|---|
| Overview | DDC power switch | HW V (Turn Off/On); M display submenu "Turn Off Display" |
| Overview | Brightness slider | Root V; M; panel |
| Overview | Volume slider + mute | HW V; M slider + submenu "Mute"; panel |
| Overview | Resolution slider | Root V › Resolution options |
| Overview | Resolution picker | Root V; M submenu; panel |
| Overview | Input picker | HW V; M submenu; panel |
| Overview | Identify · Redetect · Show Displays Panel | Root V Display Tools ▾; M Display Tools; panel footer |
| Overview | Displays panel shortcut · Identify shortcut | Kb K (Tools group; migration M4) |
| Overview | "Active features: n of 49" | X (developer statistic; I lists effective and unavailable features) |
| Overview | Banners: Resume Display Automation · Leave Safe Mode… · Restart Snaptic (helper) | Root V status rows (parity minor 1); Safe Mode also Gen V status row + Gen A; M status rows |
| Features (Displays) | Permission rows (Accessibility, Screen Recording) | Root A › Permissions footer status + fix button; Permissions page (parity minor 4) |
| Features | "X is off · Turn On" rows on other pages | X (FeatureHighlights + header/section switches) |
| Resolution | Confirm resolution changes | Root A › Confirm display changes |
| Resolution | Offer modes below 720p · Remember my choice · Show values as · Snap to favorites · Only native aspect ratio | Root A › Resolution filters |
| Resolution | Mode picker · Refresh rate | Root V |
| Resolution | Quick buttons (HiDPI, Native, Default, Native ÷ 2, Notch) | Root V › Resolution options › Quick Changes ▾; Kb K |
| Resolution | Undo / Redo | Root V › Resolution options › Quick Changes ▾ + Settings Edit menu ⌘Z/⇧⌘Z (design M6); M display submenu (when available); Kb K |
| Resolution | Add to Favorites · favorite rows (Apply/Remove) | Root V › Resolution options; favorites in the Resolution pop-up and M submenu |
| Resolution | Show (DPI filter) · Width limit Min–Max + Clear · refresh filter | Root A › Resolution filters › Filters for <display> |
| Resolution | Include in Match UI Size | D › Match text size |
| Resolution | Forget remembered | D "Forget Remembered Resolution"; I list |
| Resolution | Show all modes: display picker + Try list | Root V Resolution pop-up "Show All Resolutions" section (with `hiddenModes`) |
| Resolution | Match UI size: Reference display, Preview/Apply | D › Match text size |
| Resolution | Match tolerance slider | D › Match text size |
| Brightness | Display picker | Root tiles and Br tiles (`PerDisplayPicker` on both, shared selection; parity minor 2) |
| Brightness | Brightness slider · snap marks | Root V (slider ticks) |
| Brightness | Method (read-only) + reason · Use (method picker) · Custom switchover + Switchover slider · Minimum hardware level · Color-table status + Ask Again | Br A › Brightness methods |
| Brightness | Nits: Now | Root brightness value in nits |
| Brightness | Nits: Custom range · Minimum / Maximum (SDR) / Peak (HDR) | Br A |
| Brightness | Show nits in the menu and OSD | Br V "Show brightness in nits" |
| Brightness | XDR: Extra brightness on this display · Custom maximum + Maximum | Br V (per display "Maximum extra brightness") |
| Brightness | XDR Test · XDR global Maximum · XDR Method · Pause in Low Power Mode · Stop at 100% | Br A |
| Brightness | XDR Pause below battery | Br V (subordinate) |
| Brightness | Sync: on · Source · Follow · per display Follow + Offset | Br V (subordinates) |
| Brightness | Sync: Follow outside changes | Br A |
| Brightness | Restore · Smooth transitions · Allow dimming to black · Dim on lock + level | Br V |
| Color | Display picker · Suspend on this display · Contrast, Gamma, Temperature, Black level, White level · Invert | Col V |
| Color | Suspend on all displays · Gain · RGB gain ×3 · RGB gamma ×3 | Col A |
| Color | Reset This Display | Col A footer Restore Defaults… (This display / All displays); per-slider reset glyphs |
| Color | Color profile picker | Col V |
| Color | Show in Finder · Open in ColorSync Utility · Restore Previous | Col A profile actions ▾ |
| Color | Apple display preset picker | Col V (when `applePresets` on) |
| Color | Auto-brightness toggle | Root V "Automatically adjust brightness" |
| Color | Black strip behind the menu bar · corner radii | D › Menu bar overlays |
| Color | Keep color-table dimming with a custom profile | Col A |
| Color | Night Shift on + Warmth | Col A (Experimental, "Night Shift warmth") |
| DDC | Read values back · Every · Re-send after wake | HW A |
| DDC | Display picker · Use DDC with this display | HW V ("Use hardware controls for this display") |
| DDC | Status, Connection, Framing, Writes today, Model, MCCS, Supported codes · Read Capabilities · Check Connection | HW A › Hardware information |
| DDC | Volume · Contrast | HW V ("Hardware contrast"); M sliders |
| DDC | Per-VCP: Use, Raw 0%, Raw 100% + Reported, Invert, Show in menu, Read back every | HW A per-control disclosure rows |
| DDC | Inputs: name, Hide, ▲▼, Add Input, Reset List | HW A input list editor |
| DDC | Inputs: Switch | HW V Input pop-up; M submenu |
| DDC | Power: State, Turn On, Standby… | HW V |
| DDC | Power: Standby sends | HW A |
| DDC | Custom controls list + Name/Code/Kind/Value/Add | HW A editor; defined sliders HW V and M |
| DDC | Raw VCP Code/Value/Read/Send · unlock code · Unlock · Lock All | HW A › Raw commands (disclosure) |
| DDC | Reply delay · Retries · Write twice · Ignore checksums · Forget Learned Framing | HW A › Timing |
| DDC | Allowed without asking | Root A › Confirm display changes |
| Keys | Permission pane, Media keys status, Grant, Try Again | Kb status row + fix button; Permissions page |
| Keys | Brightness keys "Use them" · "Keys change" | Kb V (switch + "Change" pop-up) |
| Keys | Also let macOS handle brightness keys · Steps · Fine steps · F14/F15 | Kb A |
| Keys | Send volume to a monitor | Kb V (Volume keys target) |
| Keys | Also let macOS handle volume keys / mute key | Kb A |
| Keys | Per display: Keys change this display · Show the volume OSD · Sound output name | Kb A |
| Keys | Modifiers table | Kb (i) popover |
| Keys | Filter + ≈ 35 recorders | Kb K (grouped) |
| Keys | Input slots | Kb A |
| OSD | Style · Use the system OSD | Kb V "Indicator style" (system option inside) |
| OSD | Position | Kb V |
| OSD | Show on · Show the value · Preview | Kb A |
| OSD | Show nits | Br V (merged, M5) |
| OSD | Broadcast notification name | Root A › Experimental (with `osdBroadcast`) |
| Arrangement | Canvas · Snap to edges · Position/Align form | Root V Arrange Displays… sheet |
| Arrangement | Main display picker · Mirroring picker | Root V "Use as"; M submenu |
| Arrangement | Rotation · HDR | Root V (when available) |
| Arrangement | Underscan slider + Apply | D › Connection (SliderSetting on release, with confirmation) |
| Arrangement | Disconnect "Header switch" per display | X: no switch in 0.3 menu rows; migration M10 makes the Disconnect / Turn Off Display item top-level for affected displays; a disconnected display keeps a dimmed device row whose submenu offers Connect (parity M6) |
| Arrangement | Connect/Disconnect per display | D; M submenu |
| Arrangement | Connect All | Root Display Tools ▾; M Display Tools |
| Arrangement | My monitor has no DDC · Never auto-disconnect built-in | D › Connection ("This display doesn't support hardware controls") |
| Arrangement | Prevent display sleep while X is connected | Aw trigger (M1) |
| Protection & Layouts | Protect the current arrangement · Save Current Layout | SL V |
| Protection & Layouts | Save Current State as Protected · 5 field toggles · Forget All · Offer Undo after an automatic apply | SL A |
| Protection & Layouts | Per layout: name, status labels, Apply | SL V list |
| Protection & Layouts | Per layout: Apply automatically, Priority, Stop Trusting, Update to Current, Delete | SL Details… sheet |
| Protection & Layouts | Move Up/Down | SL list drag + ▲▼ context menu |
| Virtual & HiDPI | Per screen: Connected · Edit… | VD V list (Connected, Details…) |
| Virtual & HiDPI | Delete | VD Details… sheet |
| Virtual & HiDPI | Shape picker + Create · 4 recipes | VD New Virtual Display… sheet |
| Virtual & HiDPI | Connect/Disconnect/Reconnect/Disassociate/Discard All | VD A "All Virtual Displays ▾" |
| Virtual & HiDPI | Behavior toggles (3) | VD A |
| Virtual & HiDPI | Editor fields (Name, Aspect, Fill Sizes, Diagonal, HiDPI, Portrait, Reconnect at launch, HDR modes, Refresh rate, Sizes, Associations) | VD Details… sheet (Sizes as a table) |
| Virtual & HiDPI | Smart HiDPI per display toggle | VD V "Sharper text on this display" |
| Virtual & HiDPI | Smart HiDPI Size · HDR (PQ) | VD A |
| PIP | Intro + Got It | X (FeatureHighlights while off) |
| PIP | Screen Recording row · Running list (Pause/Show/Crop/Stop, bulk) · config rows (Start/Stop, Edit) · New PIP · New Full-Screen Stream · Windows section | PIP V (Crop in row menu; Windows → New PIP… window picker) |
| PIP | Editor (≈ 30 controls) | PIP editor sheet, all fields kept |
| PIP | Import .cube… · Privacy prefixes + Restore Defaults · Pause covered PIPs · ⌃⌥⌘P stops streams | PIP A (the shortcut also in Kb K) |
| Automation | Hook fields (Name, Enabled, When, Display, Delay, Program, Choose…, Arguments) | Aut list (Enabled, When) + Details… sheet |
| Automation | Action fields (Name, Show in menu, Allow from CLI, Shortcut, Program, Arguments, Run Now, Delete) | Aut list (Show in menu) + Details… sheet; shortcut also in Kb K |
| Display Names | Name · Use the System Name · Icon · Details disclosure · EDID Copy Hex/Base64 · Copy Settings From… | D |
| Display Names | EDID Export… | I (design m6: no file panel over the Details sheet) |
| Display Names | Show in the menu and the Displays panel · Menu order ▲▼ | C (D has a **Customize Displays Menu…** link; r3 consistency m5) |
| Display Names | Remembered: Forget… · Forget All… | I › Remembered displays |
| Safety | Confirm resolution changes · Revert after N s · Tell me when displays were restored · Restore All shortcut (now editable) · Allowed without asking | Root A › Confirm display changes |
| Safety | Restore All Displays Now | Root Display Tools ▾; M Display Tools (kept top-level in the Displays section while a confirmation is pending); panel |
| Safety | Resume | Root A status action; M status row |
| Safety | Helper status · Can revert rotation and HDR · Pending confirmation · Undo journal · Remembered resolutions · Unavailable on this Mac | I |
| Diagnostics | Copy Report · Export… · report + events | I (live) |
| Diagnostics | Refresh | X (I refreshes on change) |
| Onboarding | Module switches · Displays chips · Hide the menu-bar icon · Turn on Smart HiDPI | Onboarding Choose modules + Displays chips, incl. "Hide the menu-bar icon" and "Turn on Sharper Text" chips (§4.7; parity minor 3) |
| Onboarding | In-form "Use These Features" | X (one primary button in the footer) |

**0.2 menu** ([UA] §3.2 fixed rows, plus **every** 0.2 `DisplayMenuItemID`; parity B1, lead r3). "Default" is the 0.2 default visibility, kept; every row with a 0.3 location has a row in Customize Displays Menu (C): a Show / In Display Submenu / Hide pop-up for per-display items, a checkbox for the rest (lead r4). Locations are those of §5.2.

*Fixed rows*

| 0.2 item | 0.3 home |
|---|---|
| Enable Thumbnails (Screen Recording)… | M Switcher section "Turn On Thumbnails…" action item (not a status row) |
| "Press ⌥⇥ to switch windows" | M "Switch Windows ⌥⇥" (C8) |
| Gather Windows on This Display | M Switcher section |
| Display header (bold, no action) | M device row with submenu |
| More ▸ › Resolution ▸ Favorites · modes | M display submenu (≤ 8 modes incl. favorites) + "More Resolutions…" |
| More ▸ › Mute | M display submenu "Mute", in the Turn Off Display group (design m3) |
| Tools › More Display Features… | X: "Display Settings…" in each display submenu and "Snaptic Settings…" cover it (parity minor 3) |
| Recent Notices ▸ (footer) | M footer "Recent Notices ›" (Snaptic menu; own menus when the Snaptic item is absent; parity minor 3) |
| Right-click quick menu | X (C3; every item has a Display Tools ▸ or footer twin) |
| Settings… · Quit Snaptic | M "Snaptic Settings…" · "Quit Snaptic" |
| Safe Mode status row | M status row "Safe Mode is on" + "Leave Safe Mode…" |

*Registered items* (`DisplayMenuItemID` raw value → 0.3 location)

| 0.2 id (title) | 0.3 location | C |
|---|---|---|
| `c.brightness.slider` (Brightness slider) | Displays section, top-level `MenuSliderRow` under the device row | Show/Hide |
| `c.brightness.method` (Brightness method) | X: expert choice, Br A › Brightness methods (no submenus in submenus) | — |
| `c.ddc.volume` (Volume slider) | top-level `MenuSliderRow` (VCP 0x62 displays) | Show/Hide |
| `c.ddc.mute` (Mute) | display submenu, Turn Off Display group | yes |
| `c.ddc.contrast` (Contrast slider) | top-level `MenuSliderRow` (default Hide) | Show/Hide |
| `c.ddc.input` (Input source) | display submenu "Input" header + checkable inputs | yes |
| `c.ddc.power` (Standby switch) | display submenu "Turn Off Display" / "Turn On Display"; top-level under the device row when Show (migration M10) | yes |
| `c.ddc.custom` (Custom DDC controls) | top-level `MenuSliderRow` per defined control | Show/Hide |
| `c.color.submenu` (Color adjustments) | display submenu ✓ "Adjust Colors" (on = not suspended) | yes |
| `c.color.profiles` (Color profile) | display submenu "Color Profile" header + current, previous and ≤ 3 recent profiles, then "More Color Profiles…" (opens Col) | yes |
| `c.color.applePresets` (Apple display preset) | display submenu "Preset" header + presets (Apple displays, `applePresets` on) | yes |
| `c.color.autoBrightness` (Auto-brightness) | display submenu ✓ "Automatically Adjust Brightness" (built-in) | yes |
| `c.menuBarStrip.toggle` (Menu-bar strip) | display submenu ✓ "Black Menu Bar Background" | yes |
| `c.xdr.toggle` (Extra brightness) | display submenu ✓ "Extra Brightness" (XDR displays) | yes |
| `c.sync.toggle` (Brightness sync) | Display Tools ✓ "Sync Brightness" | Show/Hide |
| `c.tools.nightShift` (Night Shift) | Display Tools ✓ "Night Shift" | Show/Hide |
| `d.resolutionSlider` (Resolution slider) | top-level discrete `MenuSliderRow` (commits on release; default Hide); never in a submenu | Show/Hide |
| `d.resolutionMenu` (Resolution modes) | display submenu modes | yes |
| `d.matchUI` (Match UI Size…) | Display Tools "Match Text Size…" (opens Display Details › Match text size) | Show/Hide |
| `d.setMain` (Set as Main Display) | display submenu "Use as Main Display" | yes |
| `d.mirrorMenu` (Mirroring) | display submenu "Mirror “X”" toggles | yes |
| `d.rotationMenu` (Rotation) | display submenu "Rotation" header + ✓ Standard / 90° / 180° / 270° | yes |
| `d.hdrToggle` (HDR) | display submenu ✓ "High Dynamic Range" | yes |
| `d.powerSwitch` (Header connect switch) | X: no switches in device rows (AppKit rows are native items); migration M10 promotes Disconnect / Turn Off Display (parity M6) | — |
| `d.disconnectItem` (Disconnect) | display submenu "Disconnect"; top-level when Show; a disconnected display keeps a dimmed device row whose submenu has "Connect" | yes |
| `d.connectAll` (Connect All Displays) | Display Tools | Show/Hide |
| `d.connectAll.quick` | X: quick menu (C3) → `d.connectAll` | — |
| `d.disconnectAllButMain` | Display Tools "Disconnect All But Main" | Show/Hide |
| `d.arrange` (Arrange…) | Displays section "Arrange Displays…" | Show/Hide |
| `d.underscanMenu` (Underscan) | display submenu "Underscan…" (opens Display Details › Connection; `underscan` on) | yes |
| `d.sleepPrevention` | X → Awake (migration M1); the Awake menu | — |
| `d.protection` (Protect Arrangement) | Displays section "Saved Layouts ›" ✓ "Protect Arrangement" | Show/Hide |
| `d.layoutsMenu` (Layouts) | Displays section "Saved Layouts ›": layouts (Apply; ✓ = matching), ─, Apply Matching Layout, Protect Arrangement, Save Current Layout… | Show/Hide |
| `d.layoutMatch` (Apply matching layout) | in Saved Layouts › | Show/Hide |
| `d.virtualMenu` (Virtual Screens) | Displays section "Virtual Displays ›": ✓ per virtual display (Connected), ─, Virtual Displays Settings… | Show/Hide |
| `d.smartHiDPI` (Smart HiDPI) | display submenu ✓ "Sharper Text" | yes |
| `b.restoreAll` (Restore All Displays) | Display Tools; top-level in the Displays section while a change awaits confirmation | Show/Hide (top-level copy always shown while pending) |
| `b.restoreAll.quick` | X: quick menu (C3) → `b.restoreAll` | — |
| `b.resumeAutomation` (Resume Display Automation) | Displays section status row "Display automation is paused" + action item, while paused | always while paused |
| `f.tools.identify` · `f.tools.redetect` · `f.tools.panel` | Display Tools | Show/Hide |
| `f.quick.redetect` | X: quick menu (C3) → `f.tools.redetect` | — |
| `e.pip.display` (Picture in Picture per display) | display submenu "Show in Picture in Picture" | yes |
| `e.pip.tools` (Picture in Picture) | Displays section "Picture in Picture ›": saved PIPs (✓ = running; click starts/stops), ─, Stop All | Show/Hide |
| `a.custom.<id>` (custom actions with "Show in the menu") | Displays section "Actions ›" (one item per action, Run on click); the per-action flag stays Automations › "Show in menu" and is mirrored in C | per action |
| More ▸ › Resolution slider, quick actions, Brightness Method ▸ | covered by `d.resolutionSlider`, Quick Changes (Root V, Kb K), `c.brightness.method` above | — |

### 4.8.1 Frozen 0.2 control list (literal; `ControlLegacy.ids`; lead r4)

The 0.2 side, written here once from [UA] §2.2/§3.2 and the 0.2 sources at 871c10b (page files, the Switcher `Config` keys, `SwitcherFeature`, `DisplayFeature`, the registered `DisplayActionID`s and `DisplayMenuItemID`s, `StatusMenu`/`DisplaysMenuBuilder` fixed rows). The lead copies it verbatim into `ControlLegacy.swift` in step 0; it never changes afterwards. A name ending in `*` is one id for a parameterized family (favorites 1–5, layouts 1–9, virtual displays 1–8, input slots, PIP configurations, custom actions). Identical per-display or per-item controls are one id. The 0.3 homes are the §4.8 tables above; the owners encode them as `replaces:` in their control tables.

| Prefix | Ids (each entry is prefix + name) | n |
|---|---|---|
| `l.gen.modules.` | switcher, displays, newDisplaysCard.turnOn, newDisplaysCard.notNow | 4 |
| `l.gen.menu.` | switcher.show, switcher.icon, displays.show, displays.icon, displays.hideWithoutExternal, snaptic.icon, scrollAdjustsSliders, compact, mainFirst, showBadges, headerForSingleDisplay, sectionOrder, displayOrder, useDefaultOrder, reset, hiddenIconWarnings | 16 |
| `l.gen.cli.` | enabled, maySkipConfirmation, copyInstall, exitCodes | 4 |
| `l.gen.startup.` | launchAtLogin | 1 |
| `l.gen.permissions.` | rows, openSettings, relaunch | 3 |
| `l.gen.backup.` | export, import, resetAll | 3 |
| `l.gen.safeMode.` | restart, leave | 2 |
| `l.gen.otherApps.` | policy | 1 |
| `l.gen.about.` | checkUpdates, licenses | 2 |
| `l.sw.shortcut.` | modifier, keyCode, scope, style, includeMinimized, includeWindowlessApps, spaces, oneWindowPerApp, add, delete | 10 |
| `l.sw.` | releaseToSwitch, previewSelected, showOtherSpaces, autoSize, thumbnailSize, showOnScreen, selectOnHover, passthroughOnlyWhenFullscreen, excludedBundleIDs, passthroughBundleIDs, privateBundleIDs, protectPrivateWindows, gatherShortcut, permissionRows | 14 |
| `l.sw.feature.` | thumbnails, preview, otherSpaces, windowlessApps, search, actionClose, actionMinimize, actionFullscreen, actionHide, actionQuit, hoverButtons, hoverSelect, commandTabTakeover, passthrough | 14 |
| `l.dfeat.` | overview, diagnostics, resolution, hiddenModes, scaleMatch, brightness, brightnessApple, brightnessDDC, brightnessGamma, brightnessOverlay, brightnessRestore, dimToBlack, dimOnLock, nits, xdr, sync, autoBrightness, color, colorProfiles, nightShift, applePresets, ddcControls, ddcInput, ddcPower, ddcCustom, brightnessKeys, volumeKeys, shortcuts, osd, osdBroadcast, mainDisplay, arrangement, mirroring, rotation, underscan, hdrToggle, disconnect, autoDisconnectBuiltin, protection, layouts, virtualScreens, smartHiDPI, hdrVirtual, pip, pipFilters, menuBarOverlays, sleepPrevention, hooks, customActions | 49 |
| `l.d.overview.` | ddcPower, brightness, volume, mute, resolutionSlider, resolutionPicker, input, identify, redetect, showPanel, showPanelShortcut, identifyShortcut, activeFeatures, banner.resume, banner.leaveSafeMode, banner.restartHelper | 16 |
| `l.d.features.` | permissionRows, featureOffRows | 2 |
| `l.d.resolution.` | confirm, allowBelow720p, persistedChoice, sliderLabel, sliderSnapping, sliderNativeAspectOnly, mode, refresh, quick.hiDPI, quick.native, quick.default, quick.nativeHalved, quick.notch, undo, redo, addFavorite, favorite.apply, favorite.remove, dpiFilter, widthMin, widthMax, widthClear, refreshFilter, matchUIScale, forgetRemembered, hiddenModes.display, hiddenModes.try, scaleMatch.reference, scaleMatch.tolerance, scaleMatch.preview, scaleMatch.apply | 31 |
| `l.d.brightness.` | display, slider, snapMarks, method, use, switchover, switchoverValue, minHardware, gammaStatus, gammaAskAgain, nits.now, nits.custom, nits.min, nits.max, nits.peak, showNits, xdr.enabled, xdr.customMax, xdr.max, xdr.test, xdr.globalMax, xdr.method, xdr.batteryFloor, xdr.pauseOnLowPower, xdr.detent, sync.enabled, sync.source, sync.mode, sync.follow, sync.offset, sync.externalChanges, restoreMode, smoothTransitions, dimToBlack, dimOnLockLevel, featureOffRows | 36 |
| `l.d.color.` | display, suspend, suspendAll, contrast, gamma, gain, temperature, blackLevel, whiteLevel, invert, rgbGain.red, rgbGain.green, rgbGain.blue, rgbGamma.red, rgbGamma.green, rgbGamma.blue, resetDisplay, profile, profile.showInFinder, profile.openColorSync, profile.restorePrevious, applePreset, autoBrightness, menuBarStrip, cornerRadiusTop, cornerRadiusBottom, allowGammaWithCustomProfile, nightShift, nightShiftWarmth | 29 |
| `l.d.ddc.` | readback, readbackInterval, restoreOnWake, display, enabled, info, readCapabilities, checkConnection, volume, contrast, vcp.use, vcp.min, vcp.max, vcp.invert, vcp.showInMenu, vcp.readbackInterval, input.name, input.hide, input.order, input.switch, input.add, input.resetList, power.state, power.on, power.standby, power.standbyValue, custom.list, custom.add, raw.code, raw.value, raw.read, raw.send, raw.unlockCode, raw.unlock, raw.lockAll, timing.replyDelay, timing.retries, timing.writeTwice, timing.ignoreChecksum, timing.forgetFraming, allowedWithoutAsking, featureOffRows | 42 |
| `l.d.keys.` | permission.pane, permission.status, permission.grant, permission.retry, brightnessPolicy, brightnessAlsoSystem, target, steps, fineSteps, alternateKeys, volumePolicy, volumeAlsoSystem, muteAlsoSystem, perDisplay.keysEnabled, perDisplay.showVolumeOSD, perDisplay.audioDeviceName, modifiers, shortcutFilter, inputSlots | 19 |
| `l.d.osd.` | style, position, target, showValue, showNits, native, preview, broadcastName | 8 |
| `l.d.arrangement.` | canvas, snap, positionForm, mainDisplay, mirroring, rotation, hdr, underscan, underscanApply, powerSwitch, connect, connectAll, autoDisconnectWithoutDDC, ignoreForAutoDisconnect, preventSleep, featureOffRows | 16 |
| `l.d.protection.` | protect, saveProtected, fields, forgetAll, undoToast, layout.name, layout.save, layout.status, layout.applyAutomatically, layout.priority, layout.apply, layout.stopTrusting, layout.update, layout.move, layout.delete | 15 |
| `l.d.virtual.` | connected, edit, delete, new.shape, new.create, recipes, bulk, behavior.restoreLayoutAfterConnect, behavior.reconnectAfterWake, behavior.disconnectOnLock, editor.name, editor.aspect, editor.fillSizes, editor.diagonal, editor.hiDPI, editor.portrait, editor.reconnect, editor.hdr, editor.refresh, editor.sizes, editor.associations, smartHiDPI.enabled, smartHiDPI.size, smartHiDPI.hdr | 24 |
| `l.d.pip.` | intro, screenRecording, running.pause, running.show, running.crop, running.stop, running.bulk, config.start, config.edit, new, newStream, windows, editor.name, editor.showAs, editor.target, editor.autoStart, editor.delete, editor.level, editor.opacity, editor.clickThrough, editor.lockPosition, editor.lockAspect, editor.integerScaling, editor.showTitleBar, editor.snapToQuarters, editor.shadow, editor.resetPosition, editor.matchRefresh, editor.fps, editor.showCursor, editor.warpOnCommandClick, editor.crop, editor.rotation, editor.flip, editor.scaling, editor.size, editor.nativeMode, editor.lut, editor.filters, importLUT, privacy.prefixes, privacy.restoreDefaults, pauseWhenOccluded, stopHotkeyEnabled | 44 |
| `l.d.automation.` | hook.name, hook.enabled, hook.event, hook.display, hook.delay, hook.program, hook.choose, hook.arguments, action.name, action.showInMenu, action.cliAllowed, action.shortcut, action.program, action.arguments, action.runNow, action.delete | 16 |
| `l.d.names.` | name, useSystemName, icon, showInMenu, menuOrder, details, edid.copyHex, edid.copyBase64, edid.export, copySettingsFrom, forget, forgetAll | 12 |
| `l.d.safety.` | confirm, confirmSeconds, announceRecovery, panicHotkey, restoreAllNow, resume, helper.status, helper.canRevert, pendingConfirmation, undoJournal, allowedWithoutAsking, keptModes.forget, unavailable | 13 |
| `l.d.diagnostics.` | copyReport, export, refresh, report | 4 |
| `l.onboarding.` | modules, displayChips, hideMenuIcon, smartHiDPI, useTheseFeatures | 5 |
| `l.action.` | c.brightnessUp, c.brightnessDown, c.brightnessUpFine, c.brightnessDownFine, c.volumeUp, c.volumeDown, c.volumeUpFine, c.volumeDownFine, c.mute, c.contrastUp, c.contrastDown, c.contrastUpFine, c.contrastDownFine, c.gammaUp, c.gammaDown, c.gammaUpFine, c.gammaDownFine, c.temperatureUp, c.temperatureDown, c.temperatureUpFine, c.temperatureDownFine, c.invert, c.colorReset, c.colorSuspend, c.menuBarStrip, c.nightShiftToggle, c.nightShiftUp, c.nightShiftDown, c.syncToggle, c.xdrToggle, c.xdrUp, c.xdrDown, c.ddcPowerOn, c.ddcStandby, c.inputSlot*, d.resolutionUp, d.resolutionDown, d.hiDPIToggle, d.nativeMode, d.defaultMode, d.nativeHalved, d.resolutionUndo, d.resolutionRedo, d.notchToggle, d.matchUI, d.rotate, d.hdrToggle, d.setMain, d.mirrorToggle, d.toggleBuiltin, d.connectAll, d.disconnect, d.disconnectAllButMain, d.sleepPreventionToggle, d.protectionToggle, d.smartHiDPIToggle, d.favorite*, d.layout*, d.virtualToggle*, e.pipToggle.*, e.pipToggleDisplay, e.pipPickWindow, e.pipPauseAll, e.pipHideAll, e.pipStopAll, f.showPanel, f.identify, f.redetect, f.copyDiagnostics, b.restoreAll, b.resumeAutomation, a.custom.* | 72 |
| `l.menu.` | c.brightness.slider, c.brightness.method, c.ddc.volume, c.ddc.mute, c.ddc.contrast, c.ddc.input, c.ddc.power, c.ddc.custom, c.color.submenu, c.color.profiles, c.color.applePresets, c.color.autoBrightness, c.menuBarStrip.toggle, c.xdr.toggle, c.sync.toggle, c.tools.nightShift, d.resolutionSlider, d.resolutionMenu, d.matchUI, d.setMain, d.mirrorMenu, d.rotationMenu, d.hdrToggle, d.powerSwitch, d.disconnectItem, d.connectAll, d.connectAll.quick, d.disconnectAllButMain, d.arrange, d.underscanMenu, d.sleepPrevention, d.protection, d.layoutsMenu, d.layoutMatch, d.virtualMenu, d.smartHiDPI, b.restoreAll, b.restoreAll.quick, b.resumeAutomation, f.tools.identify, f.tools.redetect, f.tools.panel, f.quick.redetect, e.pip.display, e.pip.tools, a.custom.* | 46 |
| `l.menu.fixed.` | switcher.enableThumbnails, switcher.pressHint, switcher.gather, displays.header, displays.more, displays.moreResolution, displays.moreMute, tools.header, tools.moreFeatures, recentNotices, quickMenu, settings, quit, safeModeRow, upgradeCard | 15 |
| | **Total** | **588** |

`ControlLegacy.switcherKeyPaths` maps the 0.2 `Config` key paths to these ids: `shortcuts.modifier` … `shortcuts.oneWindowPerApp` → `l.sw.shortcut.*`, the 13 top-level fields (`releaseToSwitch` … `gatherShortcut`) → `l.sw.<name>`, `disabledFeatures` → all 14 `l.sw.feature.*` ids (one key, many ids; R5-13); `shortcuts.id` is in `internalKeys`.

**Removed with reason** (`ControlRemovals.removed`, lead; every other id above has a home):

| Legacy id | Reason |
|---|---|
| `l.d.overview.activeFeatures` | Developer statistic; Display Information lists effective and unavailable features |
| `l.d.features.featureOffRows`, `l.d.brightness.featureOffRows`, `l.d.ddc.featureOffRows`, `l.d.arrangement.featureOffRows` | "X is off · Turn On" rows are replaced by `FeatureHighlights` and header/section switches (§4.4 #6) |
| `l.d.diagnostics.refresh` | Display Information refreshes on change |
| `l.d.pip.intro` | `FeatureHighlights` while Picture in Picture is off |
| `l.onboarding.useTheseFeatures` | One primary button, in the window footer (§4.7) |
| `l.d.arrangement.powerSwitch`, `l.menu.d.powerSwitch` | No switches in menu device rows; migration M10 promotes Disconnect / Turn Off Display (parity M6) |
| `l.menu.c.brightness.method` | Expert choice; Brightness › Advanced › Brightness methods (no submenus in submenus) |
| `l.menu.fixed.quickMenu`, `l.menu.d.connectAll.quick`, `l.menu.b.restoreAll.quick`, `l.menu.f.quick.redetect` | Right-click menu removed (C3); each item has a Display Tools twin |
| `l.menu.fixed.tools.moreFeatures` | "Display Settings…" in each display submenu and "Snaptic Settings…" cover it (parity minor 3) |
| `l.menu.d.sleepPrevention` | Moved to Awake: a rule keeps the Mac awake while a display is connected (migration M1) (step-4 parity P5) |

### 4.8.2 Control tables (`ControlRegistry.tables`)

One `<TypeName>Controls` table per §6.2 page, sheet, page-section file and menu-builder file; the lead creates each as an S stub (`surface` set, `controls = []`) in step 0 and lists it in `ControlRegistry.swift`; owners fill theirs with the views. Surfaces and owners:

| Owner | Tables (surface) |
|---|---|
| H | `GeneralPage` (general.page), `GeneralAdvancedSheet` (general.advanced), `PermissionsPage` (permissions.page), `AboutPage` (about.page), `Onboarding` (onboarding), `SwitcherPage` (switcher.page), `SwitcherAdvancedSheet` (switcher.advanced), `SwitcherShortcutsSheet` (switcher.shortcuts) |
| M | `MenuBarPage` (menubar.page), `CustomizeMenuSheet` (menubar.customize), `StatusMenu` (menu.snaptic: footer, status rows), `DisplaysMenuBuilder` (menu.displays), `DisplayMenuBlock` (menu.display) |
| F | `DisplaysPage` (displays.root), `DisplayDetailsSheet` (displays.details), `DisplaysAdvancedSheet` (displays.advanced), `DisplayInformationPage` (displays.info), `DisplayLiveControls` (displays.panel), `DisplaysOnboardingStep` (onboarding.displays), `OverviewMenuItems` (menu.display.f; R5-13) |
| C | `BrightnessSubpage` + `BrightnessSections` (displays.brightness), `BrightnessAdvancedSheet` (displays.brightness.advanced), `ColorPage` (displays.color), `HardwareControlsPage` (displays.hardware), `KeyboardPage` (displays.keyboard; its Keyboard Shortcuts sheet and Advanced sheet in the same table), `BrightnessMenuItems`, `DDCMenuItems`, `ColorMenuItems` (menu.display.c) |
| D | `ResolutionSections` + `ResolutionOptionsSection` (displays.resolution), `MatchTextSizeSection`, `ArrangeSheet`, `ConnectionSection`, `SavedLayoutsPage`, `VirtualDisplaysPage`, `VirtualDisplayEditorSheet`, `ResolutionMenuItems`, `VirtualMenuItems`, `LayoutsMenuItems` (menu.display.d), `ManagementMenuItems` (menu.display.dm; R5-13) |
| E | `PIPPage`, `PIPEditorSheet`, `PIPMenuItems` |
| A | `AutomationsPage`, `HookEditorSheet`, `ActionEditorSheet`, `WindowSwitcherModule` (menu.switcher), `AutomationMenuItems` (menu.display.a; R5-13) |
| B | `ConfirmChangesSection` (displays.advanced.confirm), `PanicCoordinator` (menu.display.b) |
| G | `AwakePage` (awake.page), `AwakeAdvancedSheet` (awake.advanced), `PresetEditorSheet` (awake.sessions), `TriggerEditorSheet` (awake.rule), `CustomSessionPanel` (awake.custom), `AwakeHistoryPage` (awake.history), `AwakeMenuRows` (menu.awake), `IndicatorController` (menu.awake.item) |
| J | `DrivesPage` (awake.drives) |

Display contributors that build menu items from a controller file (e.g. `XDRController`, `SyncController`, `SmartHiDPIController`; [UA] §3.1) move their item construction into their owner's `*MenuItems` file in step 2, so every builder is one of the files above (R5-13: D's Arrangement, PanelProps, Power, Protection, SmartHiDPI → `ManagementMenuItems`; C's Color, MenuBarOverlays, Sync, SystemColors, XDR → `ColorMenuItems`; `OverviewController` → `OverviewMenuItems`; `AutomationController` → `AutomationMenuItems`). An owner may add a table in its own merge: a `stubs.tsv` row plus one appended `ControlRegistry.tables` line (TEAMS.md exception, R5-13).

## 5. Menu bar redesign (M owns the system; module owners own their sections)

### 5.1 MenuKit (M, `Core/MenuKit.swift`, `Core/MenuSliderRow.swift`, `Core/MenuSwitchHeader.swift`)

Custom rows are **AppKit only** (design M11, code minor 4): no `NSHostingView` in any menu (lint L13). They size immediately, keep the 26/27 menu material's vibrancy, and need no activating click. Everything that changes while a menu is open uses `.common`-mode timers and `DispatchQueue.main` delivery (N15).

```swift
@MainActor enum MenuKit {
    static let width: CGFloat = 300                          // menus containing custom rows
    static func header(_ title: String) -> NSMenuItem        // NSMenuItem.sectionHeader(title:) — the ONLY header style
    static func action(_ title: String, symbol: String? = nil, key: String = "",
                       modifiers: NSEvent.ModifierFlags = .command, enabled: Bool = true,
                       control: ControlID? = nil,
                       _ handler: @escaping @MainActor () -> Void) -> NSMenuItem
    static func toggle(_ title: String, isOn: Bool, symbol: String? = nil, enabled: Bool = true,
                       control: ControlID? = nil,
                       _ handler: @escaping @MainActor () -> Void) -> NSMenuItem      // checkmark
    static func alternate(of item: NSMenuItem, title: String,
                          _ handler: @escaping @MainActor () -> Void) -> NSMenuItem  // ⌥, isAlternate
    static func submenu(_ title: String, symbol: String? = nil, enabled: Bool = true, control: ControlID? = nil,
                        _ items: [NSMenuItem]) -> NSMenuItem   // one level only (asserted in debug)
    static func status(_ text: String, symbol: String? = nil) -> NSMenuItem          // disabled info row
    static func device(_ title: String, symbol: String, dimmed: Bool = false, submenu: [NSMenuItem]) -> NSMenuItem
    /// Secondary line under an item: `NSMenuItem.subtitle` on 14.4+ (`#available`). On 14.0–14.3 the subtitle is
    /// appended to the title ("Desk dock — Active") instead of a separate row, because an ⌥ alternate must directly
    /// follow its primary item (code minor 2).
    static func withSubtitle(_ item: NSMenuItem, _ subtitle: String?) -> NSMenuItem
    /// AppKit view row (`MenuSwitchHeaderView`, an NSView in MenuSwitchHeader.swift; consistency m13): bold title +
    /// NSSwitch (.small, as in the Wi-Fi menu) + up to two secondary lines (NSTextField, secondaryLabelColor).
    /// Height is fixed when the menu opens (26, 40 or 54) and kept while it is open; a line-count change is applied in
    /// `menuDidClose` (code minor 3). No fills. Mouse only: the same action always exists as a native item (parity M4).
    static func switchHeader(_ title: String, isOn: Bool, detail: [String], control: ControlID? = nil,
                             onToggle: @escaping @MainActor (Bool) -> Void) -> NSMenuItem
    static func settings(_ title: String, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem   // ⌘,
    static func quit() -> NSMenuItem                                                                     // "Quit Snaptic" ⌘Q
}
@MainActor final class MenuSliderRow: NSMenuItem {
    /// NSMenuItem's `required init(coder:)` (r3 code sig row): calls `super.init(coder:)` and leaves a disabled row with
    /// no view and no handler; it never traps (menus are never decoded from nibs here, but a trap would be a crash path).
    required init(coder: NSCoder)
    /// AppKit view 300×30: leading 16 pt template symbol in the image column, NSSlider (.regular) on the text
    /// column, trailing value label 40 pt (monospacedDigitSystemFont, secondaryLabelColor); measured per OS [HW-15].
    /// `discrete`: tick-snapped, commits on `.ended` only (resolution slider).
    init(title: String, symbol: String, value: Double?, range: ClosedRange<Double>, format: ValueFormat,
         discrete: Bool = false, control: ControlID? = nil,
         onChange: @escaping @MainActor (Double, DragPhase) -> Void)
    func bind(to publisher: AnyPublisher<Double?, Never>)   // live updates while open (.receive(on: DispatchQueue.main));
                                                            // ignored during a drag
    func setValue(_ v: Double?)                             // nil → slider disabled, value "—"
}
```

Custom-row behavior (code minor 3, normative): a view row draws its highlight from `enclosingMenuItem.isHighlighted` with an `NSVisualEffectView(material: .selection)` background so arrow-key navigation shows it, and sets `accessibilityLabel` (title + value); `MenuSliderRow` delivers `.began` on mouse down, `.changed` while tracking and `.ended` after `super.mouseDown` returns; each scroll-wheel step (with "Scroll over a slider to adjust it") delivers a `.changed` + `.ended` pair.

Item rules: Title Case; ellipsis only when more input follows; toggles use checkmarks or a changing title; submenus one level deep, ≤ ~12 items plus at most one "More…" that opens Settings. **Images: all items of a section or none** (design m1; 15-SDK builds show every attached image on 26/27, [DS] §3.3): the Displays section gives every top-level item a 16 pt template symbol (device rows, `rectangle.3.group` for Arrange Displays…, `square.stack.3d.up` for Saved Layouts ›, `display.2` for Virtual Displays ›, `pip` for Picture in Picture ›, `bolt` for Actions ›, `wrench.and.screwdriver` for Display Tools); the Switcher and Awake sections use none, except the app rows of "While an App Is Running ›", which is its own group (parity minor 11). Custom rows are never clickable themselves; every slider action and every switch-header action also has a native path (C4). Every item built through MenuKit passes its `ControlID("…")` literal (§4.8), which lint L15 checks against the builder's control table. `ClosureMenuItem`, `CMenu.item`, `ManagedMenuItem` (in D's `Displays/Management/ManagementSupport.swift`), `DisplayMenuBlock.actionItem`, `PanicMenuItem`, `MenuSliderItem` are deleted **at the step-3 exit** after a caller grep, tracked in the ratchet until then (code M10); contributors move to MenuKit during steps 1–3 (lint L6 bans `NSMenuItem(` outside the MenuKit files; permanent ratchet rows: `AppDelegate.swift` main menu, `PIPWindow.swift` context menu).

### 5.2 Snaptic icon menu (shared item)

**When it exists** (Kit `StatusItemPlan`, parity M3, consistency M3): the Snaptic item is shown iff some running module is *Show in Snaptic Menu*, or the compact Awake section is due (§5.4), or **no module is enabled** (then it says "No Modules Are On" + "Snaptic Settings…"). With every enabled module set to Don't Show there is no item at all (`everythingHidden`; relaunching Snaptic opens Settings). When it is absent, every own-icon and custom menu ends with **Recent Notices ›** (when there are notices) and **Quit Snaptic ⌘Q**, after its own "<Module> Settings…" item (not alternates; design m4). **Active variant** (N11, parity M5): `sharedActiveGlyph = awakeGoverning && showShared`, whether or not an Awake item exists: the Snaptic glyph switches to its `.fill`/badge-dot variant and its accessibility label appends ", keeping your Mac awake". **A session never removes an item that was shown at rest** (parity M5): if the Snaptic item exists at rest (even only for the compact section), it stays during the session, still showing the compact section.

Built in `menuNeedsUpdate` from the plan, in start order; sections separated by one separator; values update in place while open (N15).

```
[Safe Mode is on]                                    status row + "Leave Safe Mode…" (only in Safe Mode)
Window Switcher                                      header
  Switch Windows                              ⌥⇥    C8 (sticky switcher)
  Gather Windows on This Display
  Turn On Thumbnails…                                action item, only while Screen Recording is missing
───
Displays                                             header
  [!] Display automation is paused                   status row + "Resume Display Automation" (only while paused)
  [▭] Studio Display                          ›     device row; subtitle "Main"
  [☀] ━━━━━━━━●━━━━━  70%                            MenuSliderRow (brightness)
  [▭] DELL U2720Q                             ›
  [☀] ━━━━━●━━━━━━━━  45%
  [🔈] ━━━●━━━━━━━━━━  30%                            volume only if VCP 0x62
  [▭] LG HDR 4K (disconnected)                ›     dimmed device row; submenu "Connect" (parity M6)
  [↺] Restore All Displays                            top-level only while a change awaits confirmation
  [▦] Arrange Displays…
  [▤] Saved Layouts                           ›     only with `layouts` on and Show in C (default as 0.2)
  [▢] Virtual Displays                        ›     only with `virtualScreens` and ≥ 1 virtual display
  [⧉] Picture in Picture                      ›     only with `pip` and ≥ 1 saved PIP
  [ϟ] Actions                                 ›     only with custom actions marked "Show in menu"
  [🔧] Display Tools                           ›     Identify Displays · Redetect Displays · Show Displays Panel ·
                                                    Match Text Size… · Connect All Displays · Disconnect All But Main ·
                                                    Restore All Displays · ─ · ✓ Sync Brightness · ✓ Night Shift
───
Keep Awake                                   [○]    compact Awake section, idle (§5.4); no section header, no internal
Keep Awake Until Turned Off                         separators (the switch header's height sets the group apart)
Start Session                                 ›
While an App Is Running                       ›
Rules                                         ›     only while ≥ 1 rule exists (lead r4)
───
Recent Notices                                ›     only when there are some
Snaptic Settings…                            ⌘,
Quit Snaptic                                 ⌘Q
```

The same section while a timed session runs (compact, active):

```
Keep Awake                                   [●]    detail: "Until 3:45 PM · 1h 12m left"
Turn Off Keep Awake
Add 15 Minutes
Add 1 Hour                                          ⌥ Add Time…
✓ Keep Display On
Start Session                                 ›
While an App Is Running                       ›
Rules                                         ›     only while ≥ 1 rule exists
```

**Row budget** (r3 product minor 16): the default setup (both modules shared, 1 built-in + 1 DDC external, Awake Show When Active and idle, Screen Recording granted) has 17 items + 3 separators ≈ 20 lines (Switcher 3, Displays header + 2 device rows + 3 sliders + Arrange Displays… + Display Tools ›, compact Awake 4, Snaptic Settings…, Quit); the budget is ≤ 24 lines in the default setup, checked in HW-15.

Display submenu (one level, ≤ ~12 items with the defaults; per-item visibility from C; design m2, m3):

```
✓ 1512 × 982                                        subtitle "Default"; ≤ 8 modes: current, default, favorites, recommended
  1800 × 1169                                       subtitle "More Space" on the largest listed scaled mode
  1280 × 832                                        subtitle "Larger Text" on the smallest (r3 product minor 10: concrete
                                                    modes; the two words are only subtitles on the extremes)
  More Resolutions…                                 opens Settings › Displays › Resolution options
  Undo Resolution Change / Redo Resolution Change   only when available (parity B2)
───
  Use as Main Display
  Mirror “Built-in Retina Display”                  one toggle per possible target, inline
───
  (opt-in, per C) ✓ High Dynamic Range · ✓ Extra Brightness · ✓ Sharper Text · ✓ Adjust Colors ·
  ✓ Automatically Adjust Brightness · ✓ Black Menu Bar Background · Underscan… · Show in Picture in Picture
  (opt-in) Rotation header + ✓ Standard / 90° / 180° / 270° · Color Profile header + ≤ 5 profiles + More Color Profiles…
  · Preset header + presets
───
Input                                               header (DDC, if `ddcInput`)
✓ USB-C
  HDMI 1
───
  Mute                                              if volume (design m3: with the power items)
  Turn Off Display                                  (if `ddcPower`) · Disconnect (if `disconnect`)
  Display Settings…
```
Color-adjustment sliders and the brightness-method choice are not in the menu (Settings only). Per-item visibility (Customize Displays Menu) applies to every registered item: "Show" places it at its location above (per-display toggles and headers in this submenu, Disconnect / Turn Off Display at top level under the device row, tools items in Display Tools, section submenus in the Displays section), "In Display Submenu" (per-display items only) keeps it in this submenu, "Hide" removes it; sliders can be Show or Hide only. With no modules enabled: "No Modules Are On" status row + "Snaptic Settings…" (design m2). With the **Compact** style: one slider per display, device rows without subtitles.

Kit (lead declares the types; M owns the plan logic; consistency B1, code R2-M2c):

```swift
// SnapticKit/KitModules.swift (lead), beside MenuPlacementChoice
package enum MenuPresence: String, Codable, CaseIterable, Sendable {
    case ownIcon, ownIconWhenActive, inSnapticMenu, hidden   // menu order (design M5); raw values persisted
    /// ownIconWhenActive only for .displays and .awake (sanitized → ownIcon elsewhere).
    package static func allowed(for id: ModuleID) -> [MenuPresence]
    package var legacyPlacement: MenuPlacementChoice { get }   // written for 0.2 downgrades (migration M2)
}
// SnapticKit/Config/ConfigModules.swift (lead; stays here, one declaration; code sig): new fields have defaults so
// the existing 7 call sites keep compiling
package struct StatusItemPlan: Equatable, Sendable {
    package var shared: [ModuleID]           // sections in the Snaptic item, in start order
    package var ownIcon: [ModuleID]          // host-built own items (Switcher, Displays; Displays when active)
    package var showShared: Bool
    package var noModulesEnabled: Bool
    package var everythingHidden: Bool
    package var custom: [ModuleID]           // provider-built items that should exist now (Awake)
    package var awakeCompactInShared: Bool
    package var sharedActiveGlyph: Bool      // N11: awakeGoverning && showShared
    package var sharedFooterInOwnMenus: Bool // Snaptic item absent → Recent Notices + Quit in every own/custom menu
    package init(shared: [ModuleID], ownIcon: [ModuleID], showShared: Bool, noModulesEnabled: Bool,
                 everythingHidden: Bool, custom: [ModuleID] = [], awakeCompactInShared: Bool = false,
                 sharedActiveGlyph: Bool = false, sharedFooterInOwnMenus: Bool = false)
}
// ModulePreferences gains `presence`; `placement` and `hideWithoutExternalDisplay` stay declared and are written from it
//   package var presence: MenuPresence
//   package init(enabled: Bool, placement: MenuPlacementChoice = .shared, symbol: String = "",
//                hideWithoutExternalDisplay: Bool = false)        // kept until the step-3 exit (code sig)
//   package init(enabled: Bool, presence: MenuPresence, symbol: String = "")
//   package static func defaultPreferences(_ id: ModuleID) -> ModulePreferences   // per id: .awake → (true, .ownIconWhenActive)
// The existing statusItemPlan(running:) stays and calls the new function with awakeActive: false,
// displaysActive: true, awakeShortcutBound: false, sharedShownAtRest: true until the step-3 exit (r3 consistency m7).

// SnapticKit/MenuLayout.swift (M): the logic only
extension ModulesConfig {
    package func statusItemPlan(running: Set<ModuleID>, awakeActive: Bool, displaysActive: Bool,
                                awakeShortcutBound: Bool, sharedShownAtRest: Bool) -> StatusItemPlan
}
```
Plan rules (tested truth table, `MenuLayoutTests`): Awake `.ownIcon` → custom item always; `.ownIconWhenActive` → custom item while active, compact section in the Snaptic item while idle **and** while active if the Snaptic item was shown at rest (`sharedShownAtRest`, parity M5); `.inSnapticMenu` → compact section always; `.hidden` (only selectable with a bound shortcut) → nothing at rest; while active, the Snaptic item's active glyph if it exists, otherwise the custom item appears for the session (N11). If the Keep Awake shortcut stops being registered while presence is `.hidden` (unbound, failed to register, or the `shortcuts` feature not effective, e.g. `Awake.disable.shortcuts`; G publishes the registered flag on `AwakeRuntimeState` and M's MenuLayout/StatusMenu/MenuBarPage read only that; review5 parity Q2, code M1), the host sets presence to `.ownIconWhenActive` and shows "Awake is back in the menu bar because its keyboard shortcut is no longer set." (parity minor 11; the text names the actual reason). The fallback and its toast never run while Awake is off or turned off by a defaults setting (review5 ui N3). Displays `.ownIconWhenActive` → own item only while an external display is connected (`displaysActive`). Every module Don't Show → no item (`everythingHidden`, consistency M3). `StatusMenu.hasVisibleItem` and `everythingHidden` count provider items through `StatusItemProvider.statusItem` (code B3). `StatusMenu.applyPlan` calls `applyStatusItem(_:)` on every provider in the same turn; `AwakeHost.requestStatusPlan()` re-plans whenever Awake's active state flips (code R2-M6).

### 5.3 Awake status item (G, `IndicatorController`, exposed through `AwakeModule: StatusItemProvider`)

`NSStatusItem(variableLength)`, `autosaveName = "SnapticAwake"`, `behavior = .removalAllowed`, created and removed only in `applyStatusItem` (code R2-M6). KVO on `isVisible` ignores changes made by Snaptic itself and during teardown (a flag around our own writes), and `isVisible = true` is set whenever the item is re-created, because the autosave name restores `false` after a removal (code minor 5). A user ⌘-drag removal calls `AwakeHost.setPresence(.inSnapticMenu)` with the toast "Awake's menu bar icon was removed. Awake is now in the Snaptic menu; change this in Settings › Menu Bar." With `.ownIconWhenActive`, the plan adds the item when a session starts and removes it when it ends. While the item's own menu is open the plan keeps it (`StatusItemPlan.custom` still contains Awake): IndicatorController keeps reporting it through `statusItem`, and `menuDidClose` calls `requestStatusPlan()`, whose `applyStatusItem` then removes it, so the item still changes only in `applyStatusItem` (r3 code minor 9).

Look (design M7 r1): template SF Symbol with `SymbolConfiguration(pointSize: 15, weight: .regular, scale: .medium)` (compared optically with Wi-Fi), outline when idle, `.fill` when active, same width; `imagePosition = .imageLeading`; text set with `button.title` and `button.font = .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)` — **never an `attributedTitle` with a color** (breaks the system's menu-bar text treatment on transparent 26/27 bars and under Increase Contrast). Text: Time *Time Remaining* → `AwakeCountdown.short` ("1h 42m", "42m", "42s") for timed and capped sessions; *End Time* → `AwakeCountdown.clock` ("5:00 PM", system 12/24 h); indefinite, uncapped task, automatic and hold-only states show the glyph only. Redraw at `AwakeCountdown.nextChange` (minute boundaries; 1 s in the last minute) on a timer in `.common` mode, so the title and an open menu keep updating (N15). **Accessibility label and tooltip are refreshed at every `nextChange` tick**, also in icon-only style: "Awake, 1 hour 42 minutes remaining" / "Awake, until turned off" / "Awake, held by Terminal" / "Awake, off" (design M8); the countdown never posts an announcement, a session end posts one ("Awake turned off.", design m10).

**One row set** (design M1, M2, lead r3/r4, r3 product M1): `AwakeMenuRows` (G, `Awake/UI/AwakeMenuRows.swift`, replaces r2's `AwakeMenuBuilder`) builds the rows for both the Awake menu and the compact section; the header is always "Keep Awake" (it names the session, the Settings switch names the module). The switch header and the first-level item start **the same session**: the default preset. ✓ marks only the running session's preset, never an idle default (Apple: ✓ = current state). Idle, Awake menu (6 rows with a rule, 5 without):

```
Keep Awake                                 [○]   switchHeader (mouse): on → default preset, off → Turn Off
                                                 no detail line at rest (r3 product minor 4); a detail only for
                                                 "Ended at 3:12 AM: battery below 20%." (12 h) or "Ended because the
                                                 battery is below 20%." (guard holding)
────
Keep Awake Until Turned Off                      the default preset as a verb phrase (`AwakePreset.verbTitle`):
                                                 "Keep Awake for 1 Hour" when that is the default; idle only (lead r4)
Start Session                               ›    Until Turned Off · For 30 Minutes · For 1 Hour · For 2 Hours ·
                                                 For 5 Hours · Until Downloads and Tasks Finish · ─ · Custom…
                                                 (all presets in order; ✓ only on the running one)
While an App Is Running                     ›    running regular apps (recent first, ≤ 12, app icons; own group)
────
Rules                                       ›    only while ≥ 1 rule exists and `triggers` is effective (lead r4,
                                                 r3 product M2); subtitle "Waiting for Desk dock" / "Desk dock is
                                                 active" / "Paused until 4:00 PM"; rule rows read-only (subtitle
                                                 "Active"/"Waiting"; click opens the rule in Settings; ⌥ alternate
                                                 **End “Desk dock” Session** on an active rule = manualEnd, never
                                                 disables it; r3 product minor 3); active rules + ≤ 4 others;
                                                 ─ Pause Rules for 1 Hour · Pause Rules Until Tomorrow (or Resume
                                                 Rules) · Edit Rules…
────
Awake Settings…                           ⌘,     the only Settings item in this menu (design m4, parity minor 8)
```
Active timed session (9 rows with a rule): the detail reads "Until 3:45 PM · 1h 12m left" (plus, each only while true, "Then “Desk dock” keeps it awake.", "Held by Terminal (2)", "Ends after 5 min with no activity · quiet for 2 min" for untilIdle, "Appearing active" / "Moving the pointer" / "Stopped appearing active after 1 hour." and, on battery or without an external display, "Closing the lid will put your Mac to sleep."); **Turn Off Keep Awake** takes the first-level item's slot right after the header (native, keyboard/VoiceOver path, parity M4); then a group **Add 15 Minutes** · **Add 1 Hour** (⌥ **Add Time…**, opens the Custom panel in extend mode; timed and capped kinds only, parity minor 5) · **✓ Keep Display On** (mid-session toggle, `setKeepDisplayOn`; present only while active, design M2, parity minor 9) · **End Command-Line Holds** (only while holds exist under another governing source; R5-10); then Start Session ›, While an App Is Running ›, Rules ›, Awake Settings…. While only holds keep the Mac awake, the header is on with detail "Held by Terminal (2)", Turn Off Keep Awake (and the switch) end the hold stack, because it is what governs (End Command-Line Holds isn't shown then; R5-10), and the default-preset item stays (starting it adds a manual session beside the holds). Choosing an item in Start Session › while a session runs replaces it; choosing the running preset restarts its timer. When the Snaptic item is absent the menu also ends with Recent Notices › and Quit Snaptic (§5.2). Every common task takes ≤ 2 clicks and has a keyboard path. "Start Anyway" never appears in the menu: a refused start shows a toast with the button (parity minor 9).

### 5.4 Compact Awake section in the Snaptic menu

Shown when the plan's `awakeCompactInShared` is true (§5.2), with no section header and no internal separators (design m3, r3 product minor 2): the same `AwakeMenuRows` minus Awake Settings… (the Snaptic menu's footer has Snaptic Settings…): switchHeader "Keep Awake" with detail · idle: the default-preset item · active: Turn Off Keep Awake, Add 15 Minutes / Add 1 Hour (timed or capped), **✓ Keep Display On** (parity M4), End Command-Line Holds (holds under another source; R5-10) · Start Session › · While an App Is Running › (its own submenu; parity minor 11) · **Rules ›** whenever ≥ 1 rule exists and `triggers` is effective, so Pause Rules is reachable at rest in the default configuration (lead r4, r3 product M2). Both states are drawn in §5.2.


### 5.5 macOS 26/27 hidden and overflow behavior

There is no API to learn that the system hid an item (26 "Allow in the Menu Bar", 27 overflow); occlusion is unreliable on 27 ([PA] §8). Therefore: every Awake and Displays function is reachable from Settings (Awake status row with the Keep Awake pull-down, which starts any session (R5-9), / Options ▾ incl. Replace With ▸ / Turn Off; Displays root live controls), hotkeys, the CLI, and the floating Displays panel; **opening Snaptic again always shows Settings** (0.2 rule restored; parity minor 13); the 0.2 hidden-icon warnings stay on the Menu Bar page; the Snaptic item and the Awake item have separate autosave names so the system and the user can place them independently; the Snaptic item shows its active variant whenever Awake governs (N11), so a session is visible even when a new Awake item lands behind the notch or in 27's overflow (parity M5; HW-14 adds a notched MacBook with 20 items and 27 overflow); the default `.ownIconWhenActive` costs no notch space at rest (C11); a CLI-started session announces itself with a toast (§3.1); no right-click, hover, programmatic highlight or occlusion dependence (C3).

### 5.6 Floating Displays panel

Restyled with the same `DisplayLiveControls` rows as the Displays root page (shared SwiftUI views from F; brightness, volume, resolution pop-up, input); the "⋯" button opens the display's submenu content as an `NSMenu` popped at the button (no mixed panel/menu blocks); footer buttons: Identify, Restore All Displays, Settings.

## 6. Files, ownership, CI, delivery

### 6.1 Teams

| Team | Owns |
|---|---|
| **Lead** | Contracts, stubs, CI, lint + ratchet, Info.plist, Package.swift, Awake module shell, host wiring (ModuleHost incl. `Modules.disable.<id>`, the three Awake stores, the migration ledger, HostSignals, ToastPresenter changes), cross-section migrations, ConfigSlice/ControllerRevision types, `MenuPresence`/`StatusItemPlan` types, `LossyArray`/`StableID.derived` (`KitLossy.swift` ⇢ lead, R5-14), `scripts/selftest-control-server.sh` + its CI step (R5-5), the control registry (`ControlRegistry`, the literal `ControlLegacy` list, `ControlRemovals`, `ConfigFixtures`, lint L15) and the S stubs of every control table |
| **G — Awake core** | Awake Kit models and logic (incl. `AwakeActivityGate`, `AwakeHold`), sessions/holds/assertions/guards/triggers/history/automation controllers, task sessions, indicator and `AwakeMenuRows`, Awake settings pages, Awake search index, G's control tables |
| **J — Awake sources** | Criterion sources, PowerMonitor (+ Kit `PowerMath`), SystemEventsMonitor (session facts), CPU/disk samplers, ProcessWatch (+ holder names), activity simulation, Drive Alive (+ Drives page and its control table) |
| **H — Settings UI** | SettingsUI library (incl. `SettingsAnchor`), SettingsShell (sole owner) + search, Kit settings index types, General/Permissions/About pages, Onboarding, Window Switcher page, H's control tables |
| **M — Menu system** | MenuKit, MenuSliderRow, MenuSwitchHeader, StatusMenu, Kit MenuLayout (plan logic), Menu Bar page + Customize sheet, Displays menu builder/blocks, `ConfigMenu` (+ `ConfigMenuTests`), M's control tables |
| **A, B, C, D, E, F** (existing) | Their Displays controllers (observability, menu contributors on MenuKit) and the new pages/sections for their features (§4.3), per §6.2; A also Switcher runtime changes, **ControlServer peer credentials and held connections** (§2.10, incl. the held-slot pool and ping), `EventLog` Awake overload and `awakeCounts`, in-process `--selftest-controls` and `--selftest-control-server` (R5-5), KitBackup/KitControl (incl. `retiredVerbs`, R5-12); B also `Fingerprint.matches`; every owner fills its own control tables (§4.8.2) |

### 6.2 Files (normative; every path goes into `scripts/stubs.tsv` with owner and kind in step 0; ⇢ = ownership moves; ✗ = deleted **at the step-3 exit** after a caller grep, tracked in the ratchet until then)

```
Lead:
  Package.swift (link CoreAudio, SystemConfiguration, DiskArbitration), Resources/Info.plist (0.3.0,
    NSRemovableVolumesUsageDescription), .github/workflows/build.yml (+ selftest-controls and selftest-control-server
    steps (R5-5), landed in step 1 with A's flags; r3 consistency m13, code minor 7),
    scripts/{lint.sh (+ L15, L16, L17 (R5-3); L5 in python), lint-legacy.tsv (new), stubs.tsv, gen-stubs.py,
    selftest-control-server.sh (new, R5-5; lands with A's step-1 merge)}
    (r3's gen-controlmap.py and selftest-controls.sh are not created: the list is literal, the self-test compares in process)
  SnapticKit/KitModules.swift (ModuleID.awake, EventCategory.awake + isExportedInDiagnostics, AwakeActionID,
    AwakeCriterionKind, MenuPresence, NewModuleCard, DisplayActionID.fShowPanel/.fIdentify, DisplayMenuItemID.cDDCPower,
    NameHash + StableID.derived; DisplayFeature.sleepPrevention removed in step 3 together with D/F/A),
    SnapticKit/KitLossy.swift (⇢ from A with Tests/SnapticKitTests/KitLossyTests.swift, R5-14; LossyArray moved here from
    ConfigAutomation.swift and made Codable + Equatable, lossyArray, lossyUniqueArray, uniquedByID, uniqued (R5-3)),
    SnapticKit/AwakeFeatureGraph.swift (new), SnapticKit/FeatureGraph.swift (−sleepPrevention in step 3),
    SnapticKit/Controls/{ControlRegistry, ControlLegacy (literal §4.8.1), ControlRemovals}.swift (new) and an S stub of
    every §4.8.2 table (ownership of each table file goes to its owner in stubs.tsv),
    SnapticKit/Config/ConfigMigrations.swift (new: MigrationLedger, MigrationID; R5-2), Tests/SnapticKitTests/Support/ConfigFixtures.swift (new),
    Tests/SnapticKitTests/ConfigModulesTests.swift (⇢ from A; r3 code minor 7)
  SnapticKit/Config/ConfigAwake.swift (shell; G fills functions in step 2),
    Config/ConfigDisplays.swift (`migrated(ledger:)` = M4, M5, M10 (R5-2), DisplaysConfigSection, changedSections,
    DisplaysRestoreScope + restoringDefaults(scope:)),
    Config/ConfigModules.swift (⇢ from A; presence, newModuleCards, markers, per-id defaults, upgradeDefaults + Awake,
    StatusItemPlan (stays here, new defaulted fields), M2 (in decode), M3 (`migrated(ledger:)`, R5-2))
  Snaptic/Core/{ModuleContracts (settings contracts §4.1 + extension defaults, SettingsTint, FeatureHighlight,
               StatusItemProvider + CustomItemRow, ControlDeclaring, FeatureAvailability moved here),
               ModuleContext (⇢ from A; requestStatusPlan, setPresence, hostSignals),
               HostSignals (new), ConfigSlice (new), ToastPresenter (⇢ from A; presenting/screensaver suppression,
               Recent Notices routing, ToastAction extended + ToastDismissal + ToastClickGuard + show(_:actions:…) -> Bool
               (R5-1; stub in step 0, step 2)), ModuleHost (⇢ from A; Awake wiring, the three Awake stores, the migration
               ledger store and the R5-2 `migrated(ledger:)` order, Modules.disable.<id>, upgrader insertion, M1,
               isTerminating, Reset All)}.swift
               (ConfigStore.swift stays A's and unchanged: r2's admission hook is withdrawn)
  Snaptic/Awake/{AwakeModule, AwakeContext (+AwakeHost), AwakeContracts (+ChangeFanout), AwakeRuntimeState}.swift (new)
  Snaptic/Displays/{DisplaysModule (fan-out by section), DisplaysRuntimeState (ControllerRevision per id, DisplayRuntime
               fields, DisplaysPageEnvironment stops forwarding config at the step-3 exit, r3 code minor 14;
               −sleepPreventionActive in step 3),
               DisplaysContracts (observedSections default, DisplayLiveControlling, LiveControl, DragPhase)}.swift

G (Kit, each with Tests/SnapticKitTests/<Name>Tests.swift):
  AwakeSession (+HoldBinding, AwakeHold, UntilIdleSpec, TaskActivitySample, TaskQuiet), AwakeActivityGate, AwakeClock (+AwakeCountdown,
  AwakeDurationGrammar), AwakeArbiter, AwakeGuards, AwakeTriggers, AwakeTriggerEngine, AwakeHistory, AwakeSnapshot,
  AwakeMigration (+AwakeMigrationResult), AwakeCommandGrammar (+AwakeCommand, AwakeStatusFacts), AwakeLogEvent,
  Config/ConfigAwakeSessions (+AwakeBehavior, UserSwitchEnd), Config/ConfigAwakeIndicator (SettingsIndexAwake is not created: R5-13)
G (app): Snaptic/Awake/Core/{AssertionManager, SessionController (manual session, untilIdle via TaskQuiet, the hold
               stack), GuardsController, TriggerController, Ticker (TriggerController's; no service id), HistoryController,
               AwakeAutomation, AwakeDiagnostics}.swift (r3's TaskSessionMonitor is dropped: consistency M5)
         Snaptic/Awake/UI/{IndicatorController, AwakeMenuRows, CustomSessionPanel, AwakePage, PresetEditorSheet,
               TriggerEditorSheet, CriterionEditors, AwakeAdvancedSheet, OtherAssertionsSection, AwakeHistoryPage}.swift

J (Kit): CPUMath (+CPUTicks, CPUTimebase, ProcessCPUSample), PowerMath, NetworkMath (+InterfaceCounters; CIDR/IPv6 parse + match, MAC normalize, throughput),
         DiskMath, ActivityPolicy (+IdleMath), DriveAlivePolicy, Config/ConfigAwakeDevices (+VolumeUUIDKey)
J (app): Snaptic/Awake/Sources/{PowerMonitor, SystemEventsMonitor, AppMonitor, DisplayPresence, USBWatcher, VolumeMonitor,
               AudioMonitor, CPUSampler, DiskIOSampler, IdleSampler, NetworkMonitor, BluetoothPresence, ActivitySimulator,
               DriveAliveService, OtherAssertionsReader (+SleepDisabled), ProcessWatch (kqueue, proc_pidinfo)}.swift
         Snaptic/Awake/Core/{ActivityController, DriveAliveController}.swift, Snaptic/Awake/UI/DrivesPage.swift

H (Kit): SliderMath, SettingsIndex (SettingsRoute, SettingsSearchEntry, SettingsSearch — Kit so search is tested on Linux),
         (R5-13: `SettingsIndex.entries` derives entries from control specs; SettingsIndexGeneral and SettingsIndexSwitcher
         are not created) (r3's ControlMap/ControlCatalog and the app's ControlCoverage are
         not created: lead-8)
H (app): Snaptic/SettingsUI/{SettingsIcon, SettingsPageHeader, FeatureHighlights, SettingRow, ToggleSetting, SliderSetting,
               NumberField, StepperSetting, PickerSetting, GlyphTilePicker, ActionMenuButton, InfoButton, NavigationRow,
               ButtonRow, StatusRow, PerDisplayPicker, PageFooterButtons, AdvancedSheet, ReorderableList, AppListEditor,
               ShortcutSetting, EmptyListView, SettingsPageScaffold, SettingsAnchor, SettingsBinding, SettingsShell,
               SettingsSearchView}.swift
         Snaptic/Core/{SettingsWindowHost, GeneralPages, Onboarding}.swift (⇢ from A)
         Snaptic/Switcher/{SwitcherPages, SettingsView}.swift (⇢ from A)

M (Kit): MenuLayout (ModulesConfig.statusItemPlan logic only; MenuPresence and StatusItemPlan are the lead's,
         consistency B1) (SettingsIndexMenuBar is not created, R5-13),
         Config/ConfigMenu (⇢ from F; legacy shortcut fields kept and encoded until 0.4), Tests ConfigMenuTests (⇢ from F)
M (app): Snaptic/Core/{MenuKit, MenuSliderRow, MenuSwitchHeader (MenuSwitchHeaderView), MenuBarPage,
               CustomizeMenuSheet}.swift (new),
         Snaptic/Core/StatusMenu.swift (⇢ from A), Core/MenuPlacement.swift (⇢ from A; its `MenuPlacementChoice` UI
         titles move to `MenuPresence` titles, the old titles ✗ at the step-3 exit; r3 consistency m11),
         Core/MenuSliderItem.swift (⇢ from A, then ✗),
         Snaptic/Displays/UI/{DisplaysMenuBuilder, DisplayMenuBlock}.swift (⇢ from F),
         Displays/UI/MenuCustomizationPage.swift (⇢ from A, then ✗)
D: also `ManagedMenuItem` in Displays/Management/ManagementSupport.swift ✗ (symbol only, step-3 exit; consistency m10)

F: Displays/UI/{DisplaysPage, DisplayLiveControls, DisplayDetailsSheet, DisplaysAdvancedSheet, DisplaysFeatureGroups,
               DisplayInformationPage}.swift (new); DisplaysOverviewPage ✗, FeaturesPage ✗, DisplayIdentityPage ✗ (→ DetailsSheet),
               DiagnosticsPage ✗ (→ DisplayInformationPage); OverviewController (panel restyle, Kit `fShowPanel`/`fIdentify`
               constants in step 1), DisplaysOnboardingStep (F makes the §4.7 chip changes; H owns Onboarding.swift);
   Kit DisplaysUIModel (groups, user titles; −sleepPrevention in step 3), Displays/UI/OverviewMenuItems.swift (new, R5-13; SettingsIndexDisplays is not created)
C: Displays/UI/{BrightnessSubpage, BrightnessSections, BrightnessAdvancedSheet, ColorPage, HardwareControlsPage,
               KeyboardPage}.swift; BrightnessPage ✗ (→ Subpage/Sections), DDCPage ✗ (→ HardwareControlsPage),
               KeysPage ✗ + OSDPage ✗ (→ KeyboardPage); BrightnessMenuItems, DDCMenuItems (MenuKit; `cDDCPower` from Kit),
               ColorMenuItems (new: the color, XDR, sync, Night Shift and menu-bar-strip items move here from their
               controllers);
   Displays/Live/DisplayLiveController.swift (new; DisplayLiveControlling); controllers: runtime fields + revision bumps;
   Kit ConfigKeys (osdShowNits legacy, kept encoded)
D: Displays/UI/{ResolutionSections, ResolutionOptionsSection, MatchTextSizeSection, ArrangeSheet, ArrangementCanvas,
               SavedLayoutsPage, VirtualDisplaysPage, VirtualDisplayEditorSheet, ConnectionSection}.swift; ResolutionPage ✗,
               ArrangementPage ✗, ProtectionLayoutsPage ✗, VirtualScreensPage ✗, ManagementPageParts ✗ (→ SettingsUI);
   ResolutionMenuItems, VirtualMenuItems, LayoutsMenuItems, ManagementMenuItems (new, R5-13) (MenuKit); PowerController (−sleep prevention, step 3),
   Kit ManagementIDs (step 3), Config/ConfigManagement (preventSleep decode + encode, ignored)
E: Displays/UI/{PIPPage, PIPEditorSheet (new), PIPMenuItems}.swift
B: Displays/UI/ConfirmChangesSection.swift (new; SafetyPage ✗), PanicCoordinator (MenuKit items), Config/ConfigSafety (M6),
   Kit Fingerprint (+matches)
A: Displays/UI/{AutomationsPage, HookEditorSheet, ActionEditorSheet, AutomationMenuItems (new, R5-13)}.swift (AutomationPage ✗); Switcher/{SwitcherController
   (sticky mode C8, HostSignals.switcherVisible), Settings (250 ms debounce), WindowSwitcherModule (MenuKit)}.swift;
   Core/ControlServer (ControlPeer via LOCAL_PEERPID, ControlHold, held-connection slot), Core/ControlCommandRegistry
   (ControlContext handler + old-signature overload, `holds:`, protected list), Core/CLIClient (holding replies; token-mode socket override, R5-5),
   Core/EventLog (`record(_ event: AwakeLogEvent)`, `awakeCounts`), Core/SelfTest (`--selftest-controls`, in process; `--selftest-control-server`, R5-5), Core/SnapticEntry + Kit KitArgs
   (the two self-test modes, R5-5), Core/ControlServer `sendHeld`/`start(socketPath:)`/`holdPingInterval` (R5-5);
   Kit Config/ConfigAutomation (its `LossyArray` moves to KitLossy in the lead's step 0);
   Kit KitBackup (awake section via AwakeConfig.exportable/importable applied after merge, awake.guards in safetyPaths;
   −sleepPrevention rows in step 3, removedPaths for Awake), KitControl (ControlResponse hand-written Codable +
   holding, maxHeldConnections = 8, holdPingSeconds, protected words (Awake words in step 1, old ones dropped in step 3,
   R5-14); `retiredVerbs` with `prevent-sleep` in step 3, R5-12; −sleepPrevention in step 3)
F: also Displays/UI/DiagnosticsController.swift (eventLines filter by EventCategory.isExportedInDiagnostics)
```

Unique basenames are kept (e.g. `PowerMonitor` (J) vs `PowerController` (D); `KeyboardPage` (C) vs no other). Lead adds `.awake` to the extension-placement lint allowlist (`SharedExtensions.swift` stays the only shared home). Ownership collisions resolved: `SettingsShell` is H's alone; `SettingsTint`, `FeatureHighlight` and `StatusItemProvider` are lead types in `ModuleContracts` (code minor 12, B3); `MenuPresence` (KitModules) and `StatusItemPlan` (ConfigModules) have one declaration each, by the lead, and M owns only the plan function (consistency B1); r3's "ControlMap: H + owners" is gone: each owner edits only its own `*Controls.swift` tables, and the shared registry, legacy list and removals are the lead's (r3 consistency m11); the Awake stores have one owner, `ModuleHost`.

### 6.3 CI, lint and ratchet (lead, step 0)

- Linux job: new Kit files/tests build and run with Swift 5.10 (Foundation only; no Foundation formatters in Kit code that tests compare, N12).
- macOS job unchanged (Xcode 16.4, Swift 5 language mode, debug + tests + universal + helper self-test); Awake adds no helper. (R5-5) From step 1 it also runs `scripts/selftest-control-server.sh` against the debug build.
- `FeatureAvailability` moves from `DisplaysContracts.swift` to `Core/ModuleContracts.swift` (lead, step 0) so Awake doesn't depend on a Displays file.

**Ratchet** (code B1, R2-M1): `scripts/lint-legacy.tsv`, one row per (rule, path): `rule ⇥ path ⇥ count ⇥ permanent|step`; counts are **occurrences**, not lines. `lint.sh` fails on any violation of L1–L14 not covered by a row (count exceeded or path missing). A non-permanent row whose actual count is now lower only **warns** during steps 1–3; `lint.sh --strict` (CI from the step-3 exit on) fails on it. TEAMS.md (lead, step 0) gains an exception like the one for `stubs.tsv`: a team may lower or delete ratchet rows **for paths it owns** in its own branch, and may append one `ControlRegistry.tables` line per table it adds (R5-13); its contract-file list adds the files that move to the lead (`ConfigModules.swift`, `ModuleHost.swift`, `ModuleContext.swift`, `ToastPresenter.swift`, `ConfigModulesTests.swift`) and the new lead files (`KitLossy.swift`, `Controls/{ControlRegistry, ControlLegacy, ControlRemovals}.swift`, `ConfigMigrations.swift`, `ConfigFixtures.swift`; r3 consistency m16); rows are sorted by path so parallel edits touch different lines. `lint.sh --write-ratchet` generates the initial file at 871c10b in step 0 (≈ 54 `Slider(`/`Stepper(`, ≈ 125 `.font(.caption)`, 18 `NSMenuItem(`, 4 `objectWillChange.send()`, 7 `State(initialValue:`, `PowerController.swift` for L1). Permanent rows: `AppDelegate.swift` (L6, the app's main menu that Settings text fields need for Edit), `PIPWindow.swift` (L6, context menu), `ArrangementCanvas.swift` (L5, custom drag canvas). Deleted files (✗) and symbols (`ClosureMenuItem`, `CMenu`, `ManagedMenuItem`, `MenuSliderItem`, `MenuSlot.quick`) stay until the step-3 exit, where owners remove them after `grep` shows no callers (code M10). **Step-3 exit: only permanent rows remain.**

Lint additions:
- L1 `IOPMAssertionCreate`/`IOPMAssertionCreateWithProperties` only in `Awake/Core/AssertionManager.swift`; `IOPMAssertionRelease` there and in `Awake/Sources/ActivitySimulator.swift` (its DeclareUserActivity id, code M8); `IOPMAssertionSetProperty` banned (the swap replaces it).
- L2 `IOPMAssertionDeclareUserActivity`, `.post(tap:`, `CGEvent(mouseEventSource` only in `ActivitySimulator.swift`; there, mouse event types other than `.mouseMoved` are banned; `keyboardEventSource`, `CGEvent(keyboardEvent`, `CGEvent(scrollWheelEvent` banned everywhere in Awake.
- L3 (r1) dropped: rule 12 already bans spawning outside HelperSpawner everywhere (code minor 13).
- L4 Banned everywhere: `UNUserNotificationCenter`, `import CoreWLAN`, `import IOBluetooth`, `CLLocationManager`, the string literals `"pmset"` and `"sudo"`.
- L5 `(?<![A-Za-z])Slider\(`, `(?<![A-Za-z])Stepper\(`, `.font(.caption)` only under `Sources/Snaptic/SettingsUI/` (ratchet for the rest; the lookbehind keeps `ScrollSlider(` and `MenuSliderRow(` out; code R2-M1). Implemented in python like rule 10, because BSD grep on macOS has neither lookbehind nor `-P` (r3 code minor 3).
- L6 `NSMenuItem(` only in `MenuKit.swift`, `MenuSliderRow.swift`, `MenuSwitchHeader.swift` (ratchet).
- L7 `objectWillChange.send()` banned in `Displays/UI/`, `Awake/UI/`, `SettingsUI/`; `State(initialValue:` banned in Settings views (ratchet).
- L8 (r1's python anchor scan) replaced by Kit tests: anchors unique across the derived search entries (R5-13), every searchable control is declared in a control table (`ControlRegistryTests` 3); plus a DEBUG assertion in `SettingsPageScaffold` when `reveal` targets an anchor that never registered (code minor 13).
- L9 `record\(\s*\.awake` and the token `EventCategory.awake` banned outside `Core/EventLog.swift` (only `AwakeLogEvent` cases may be logged, through A's overload; security M6, code minor 5). A variable holding the category can still slip through; review checks it.
- L10 under `Awake/`: `queue: nil`, `addObserver(self, selector:` and `.publisher(for:` not followed by `.receive(on: DispatchQueue.main)` in the same statement are banned (code M6, minor 4); the `static let shared` (rule 7) and `passUnretained` (rule 10) rules extend to `Awake/`.
- L11 (r2: consent writers) withdrawn with the consent record (N10).
- L12 `.controlSize(.regular)` only in `SettingsUI/SettingsPageHeader.swift` (design B2).
- L13 `NSHostingView` banned in `Core/Menu*.swift`, `Core/StatusMenu.swift`, `Displays/UI/*Menu*.swift`, `Awake/UI/AwakeMenuRows.swift`, `Awake/UI/IndicatorController.swift` (design M11).
- L14 (N15, code R2-M7) under `Awake/`, `Core/Menu*.swift`, `Core/StatusMenu.swift` and any `*Menu*.swift`: `Timer.scheduledTimer`, `.scheduledTimer(`, `RunLoop.main.perform` without an explicit mode list, `receive(on: RunLoop.main)` and `RunLoop.main` as a Combine scheduler are banned; timers are created unscheduled and added with `RunLoop.main.add(_:forMode: .common)`. `RunLoop.main.perform(inModes: [.default])` stays allowed: it deliberately defers work until menu tracking ends (`ResolutionMenuItems.swift:111`; r3 code minor 4).
- L15 (lead r4, §4.8): control-table pairing: `ControlID(` takes only a string literal outside `SettingsUI/` and `Core/MenuKit.swift`; every literal is in the using type's table; every table id is used by a literal; every table is registered.
- L16 (r3 security M2, L1): `activityGate =` and `AwakeActivityGate(` only in `Awake/Core/SessionController.swift` among the files under `Sources/Snaptic/` (Kit and its tests construct it freely; R5-14); `shutdown(` banned in `Core/CLIClient.swift` (the client never half-closes).
- L17 (R5-3, security L3): `uniqueKeysWithValues` banned under `Sources/Snaptic/Awake/`, in `SnapticKit/Awake*.swift` and in `SnapticKit/Config/ConfigAwake*.swift`; use `Dictionary(_:uniquingKeysWith: { first, _ in first })`.
- Added in the step-4 fix rounds (lead, unratcheted, `scripts/lint03.py`): TEAMS rule 2 (closures run by the main queue, a `queue: .main` observer, a timer or KVO wrap `MainActor.assumeIsolated` and use `self` only inside it; the main queue is also recognized on the line above `.asyncAfter` and through a name the file binds to `.main`); every `DisplayMenuContributor` conformer is listed in `DisplaysModule.menuContributorTypes` (whose `menuItemIDs` `--selftest-controls` checks against the frozen 0.2 menu ids, R5-13); `L()` text uses no 0.2 name from the §4.2 terms table (Smart HiDPI, virtual screen, Match UI Size, Menu-Bar Strip, Native-Halved, On-screen display, Recording screen; pending allowances only go down).

**Stub kinds** (code M14): `gen-stubs.py` gains K15 Awake service (`AwakeServiceLifecycle` class, `init()`, no-op activate/deactivate), K16 criterion source (K15 + `static var kinds`, no-op `contribute`, `observe` backed by **one `ChangeFanout` per instance**, a stored `let`, code minor 13), K17 Awake controller (`AwakeFeatureController`, `id` from the extra column, no-op members, `availability` returns available), K18 settings page (`struct T: View, ControlDeclaring` with `typealias Controls = TControls`, rendering `SettingsPageScaffold` with the title), K19 sheet (the same with `@Environment(\.dismiss)` and a Done button), K20 Kit settings index table (`package enum T { package static let entries: [SettingsSearchEntry] = [] }`) (unused since R5-13: search entries are derived from control specs), K21 Kit control table (`package enum TControls: ControlTable { package static let surface = "<extra column>"; package static let controls: [ControlSpec] = [] }`, lead r4). SettingsUI components, MenuKit, `ConfigSlice`, `ToastAction` (extended, R5-1; `ControlServer`'s new types are A's step-1 work, not lead stubs, R5-14), and **every Kit type in §2, §4.1, §4.5, §4.6, §4.8 and §5.2** (incl. `SettingsRoute`, `SettingsSearchEntry`, `ValueFormat`, `DisplaysConfigSection`, `DisplaysRestoreScope`, `AwakeMigration`/`AwakeMigrationResult` (`.nothing`), `MigrationLedger`, `ControlID`, `ControlSpec`, `ControlRegistry`, every `*Controls` table, `MenuPresence`, `StatusItemPlan`, `AwakeActivityGate`, `AwakeHold`, `LossyArray`; consistency B1, r3 consistency m10) are `S` (special, hand-written by the lead from this plan's signatures, so step 0 references no team-owned type that doesn't exist yet) or `L`. About 185 new rows (≈ 61 of them K21 control tables, §4.8.2; R5-13 adds three tables and drops the five K20 `SettingsIndex*` rows).

### 6.4 Delivery order

**Step-0 feasibility** (what step 0 can and can't contain; code B1, B2, M14, R2-M2):

| Item | Step 0? | Why |
|---|---|---|
| Stubs for every §6.2 file (K15–K20, S) with safe returns and exhaustive protocol members; a full stub `AwakeModule` and `case .awake` in `ModuleHost.module(_:)` | yes | only lead types are referenced |
| `SnapticModule` additions with **extension defaults**; `settingsPages()` kept | yes | `WindowSwitcherModule` (A) and `SettingsWindowHost.swift` (H) keep compiling (code R2-M2a) |
| `AwakeFeatureGraph` + tests, `KitModules` additions (`MenuPresence` with a real `legacyPlacement`, `DisplayActionID.fShowPanel/.fIdentify`, `EventCategory.isExportedInDiagnostics`) | yes | lead-owned Kit; M2 needs `MenuPresence` now (code R2-M2c) |
| `StatusItemPlan` new defaulted fields (in `ConfigModules.swift`); `MenuLayout.swift` S stub whose plan function reproduces 0.2 placement | yes | one declaration, lead (consistency B1); M fills the logic in step 1 |
| `Controls/`: `ControlRegistry`, the literal `ControlLegacy` list copied from §4.8.1, `ControlRemovals`, every §4.8.2 table as a K21 stub, `ConfigFixtures`; `ControlRegistryTests` added **skipped** until step 3; lint L15 on from day 0 (tables and literals both start empty, so it is green) | yes | the 0.2 side is fixed in this plan; nothing has to be generated or rendered (lead r4) |
| `LossyArray` moved to KitLossy (Codable) with `lossyUniqueArray`/`uniquedByID` (R5-3), `NameHash` + `StableID.derived` (KitModules, R5-14), `ControlID` (Controls/ControlRegistry.swift, R5-14), `MigrationLedger` + `MigrationID`, `NewModuleCard`, `DisplayMenuItemID.cDDCPower` | yes | lead Kit; M1, M3, M10 and every Awake list need them |
| S stubs for team types other teams call early: `Fingerprint.matches` (B fills it in step 1, G's step-1 `TriggerEngine` calls it), `AwakeActivityGate`, `AwakeHold`, `PowerMath`, `ToastAction` (extended, R5-1) + `ToastPresenter.show(_:actions:…) -> Bool` (lead fills it in step 2 while G's step-2 callers land) | yes | r3 code minor 7: parallel steps compile against stubs |
| `AwakeConfig` shell with all sub-config types as G/J **stubs** (`init()`, `sanitized()` identity) | yes | G/J fill them in step 1 |
| `restoringDefaults`, `exportable`, `importable` | stub only (identity / `AwakeConfig()`) | need G's and J's fields; G implements in step 2 |
| Migrations M2 (decode) and M3–M5, M10 as `migrated(ledger:)` run by ModuleHost (R5-2) + ledger markers + tests; per-id module defaults; upgrader insertion of Awake disabled (ModuleHost and `upgradeDefaults()`); `Modules.disable.<id>` read | yes | lead Kit / host |
| M1 | no: stub `AwakeMigration.fromDisplays` returns `.nothing`; G implements in step 1, lead wires the hook in step 2 | needs G's trigger model |
| `changedSections` with `DisplaysConfigSection` (all cases); `observedSections` requirement + default; `ControllerRevision` per id; `ConfigSlice`; `DisplayRuntime` fields; `DisplayLiveControlling` | yes | lead types; defaults keep the ~21 conformers compiling |
| `DisplaysPageEnvironment` stops forwarding config | **no** (step-3 exit) | 23 legacy pages need it until they use slices (code R2-M2b) |
| `HostSignals`, `StatusItemProvider` + `CustomItemRow` | yes | lead |
| ControlServer peer credentials / held connections | no (A, step 1) | A's files (consistency M1) |
| `sleepPrevention` removal, MenuKit migration of old factories, file deletions, `settingsPages()` removal, old `register` handler overload removal | **no** (step 3) | would break 11+ files owned by C/D/F/A (code B2, M10) |
| Lint L1–L16 + ratchet generated from 871c10b; TEAMS.md ratchet exception and contract-file list | yes | ratchet makes it green on day 0 |
| `build.yml` `--selftest-controls` and `--selftest-control-server` steps (R5-5) | **no** (step 1, with A's flags) | the flag doesn't exist before A's step-1 merge (r3 consistency m13, code minor 7) |

| Step | Who (parallel) | Exit criterion |
|---|---|---|
| 0 | Lead | Everything marked "yes" above; Info.plist; Package.swift links; CI green on Linux and macOS with the ratchet |
| 1 | G (Kit only, incl. `AwakeMigration`, `AwakeCommandGrammar`, `TaskQuiet`, `AwakeActivityGate`, `AwakeHold`, lossy list decoders) ∥ J (sources incl. per-process CPU with the timebase, DiskIOSampler, ProcessWatch; Kit math incl. `PowerMath`) ∥ H (library incl. `SettingsAnchor`, shell, search, Kit index types) ∥ M (MenuKit, MenuSliderRow, MenuSwitchHeader, StatusMenu with `MenuPresence` and the plan, MenuLayout logic) ∥ A (Switcher debounce, sticky mode, `switcherVisible`; **ControlServer `ControlPeer` + `ControlHold` + `ControlContext` handler, held-slot pool (8), ping, CLIClient holding mode, KitControl hand-written `ControlResponse` + `holding`**; `KitControl.protectedSettings` Awake words added (old words dropped in step 3, R5-14); `EventLog` Awake overload + `awakeCounts`; in-process `--selftest-controls` and `--selftest-control-server` with `sendHeld` and the CLIClient token-mode override (R5-5), with the lead's script and `build.yml` steps in the same merge) ∥ B (`Fingerprint.matches`) ∥ F (`OverviewController` switches to the Kit `fShowPanel`/`fIdentify` constants) | Kit tests for G/J/H/M (incl. `AwakeActivityGate`, `PowerMath`, `CPUMath.window`); sources activate/deactivate cleanly; shell shows all 7 roots with stub pages; StatusMenu renders existing sections through MenuKit; `scripts/selftest-control-server.sh` green in CI (R5-5: the §2.10 connection tests); `--selftest-controls` green in CI; per-table `ControlRegistryTests` (tests 2, 3, replaces ⊆ legacy, `parentOn`) green (R5-13); green, merged |
| 2 | G (controllers, assertion, sessions incl. task kinds, the hold stack and `restore` in the §2.1 start order, guards, triggers, automation incl. `awake hold`, hotkey confirmation, indicator + `AwakeMenuRows`, `restoringDefaults`/`exportable`/`importable`; lead wires M1) ∥ J (`OtherAssertionsReader` + `SleepDisabled`, holder names; r3 consistency m13) ∥ lead (ToastPresenter: presenting/screensaver suppression, Recent Notices routing, `actions: [ToastAction]`; consistency m12) ∥ H (General, Permissions, About, Onboarding, Switcher page) ∥ M (Displays menu builder/blocks with every §4.8 menu location, Menu Bar page, Customize sheet) ∥ B (observability + M6 UI + `SafetyConfig` test; consistency M5) ∥ C/D/E (controller observability + revision bumps + MenuKit contributors with their control tables; C `DisplayLiveController`, `ColorMenuItems`) ∥ F (Displays root page, live controls, Details sheet, panel; `eventLines` filter) ∥ A (KitBackup awake section after merge) | Awake works end to end from the menu, hotkeys and CLI (`hold` both forms); menus per §5 incl. every opt-in item; Displays root page live; green, merged |
| 3 | G (Awake page, editors, history, Advanced, other-assertions section) ∥ J (Drives page, nudge path, Bluetooth Beta) ∥ C/D/E/A/B/F (sub-pages and Advanced groups per §4.3; duplicates per §4.4) ∥ **one coordinated merge** D + F + A + lead removing `sleepPrevention` (§2.13; incl. the `prevent-sleep` retired-verb stub and dropping the old protected words, R5-12, R5-14) ∥ H (search index assembly, highlight) ∥ lead (`ControlRegistryTests` totality and key cross-check un-skipped, R5-13; every owner's tables filled with their pages) ∥ lead (`DisplaysPageEnvironment` forwarding removed, `settingsPages()` and the old handler overload removed) ∥ all owners delete ✗ files and old factories after a caller grep | Every §4.3 page meets its budget; every slider is a `SliderSetting`; search finds every entry; `ControlRegistryTests` green (every frozen 0.2 id has a declared home or a removal reason) and lint L15 green; no manual or rendering gate (lead r4); **ratchet holds only permanent rows** and CI runs `lint.sh --strict`; green, merged |
| 4 | Review | Adversarial reviews: security (§3, outside changes, pointer-movement and Drive Alive rules, hold peer checks), correctness (clock, guards, triggers, assertion swaps, task kinds, migration), UX (copy rules, budgets, light/dark/Increase Contrast, VoiceOver incl. the Awake menu), consistency (contracts vs code); fixes |
| 5 | Lead | README (Awake, CLI verbs and exit codes, **`awake hold` usage and the parent-shell pitfall** (§2.10), the hidden kill switches and how an organization deploys them with a configuration profile (N14), privacy, "why not lid-closed on battery", switching from Amphetamine Power Protect / Insomnia and cleaning up their sudoers rules and `SleepDisabled`, the 0.3 → 0.2 → 0.3 note), website, THIRD_PARTY_NOTICES (Insomnia, KeepingYouAwake if logic is followed closely; no code from APSL sources such as `caffeinate.c` — behavior only), Appendix hardware session, merge |

### 6.5 Done means

- Every In row of §1.1 and §1.5 implemented, reachable in Settings (and menu, hotkey and CLI where listed), wired to availability, kill switch, Safe Mode, diagnostics and `configDidChange`; idempotent start/stop; no stubs left.
- **Every 0.2 setting, button/action and menu item reaches its §4.8 home** (`ControlRegistryTests` green over the literal §4.8.1 list and the removals table, lint L15 green, `--selftest-controls` green; reviewer walk-through of the table); every 0.2 opt-in menu item has a declared §5.2 location and a row in Customize Displays Menu.
- Awake holds at most one sleep assertion at any time (assert in debug + test via `AssertionManager` counters); `pmset -g assertions` shows only fixed-vocabulary strings (`Details` = manual/automatic).
- Pointer movement never acts for a CLI, rule, hold, `launch`, restored or resumed session, for a hotkey start before Allow, or while locked or off console, whatever the config says; activity stops after `stopAfterHours` on Snaptic's clock; the 5% hard floor ends sessions whenever the battery is discharging (also on a weak adapter) and critical heat ends them with every config (HW-19). Each `awake hold` ends within 1 s of its client's exit or kill, and at its cap; up to 8 holds coexist with a UI session; `scripts/selftest-control-server.sh` green (R5-5). Every session kind can be started from Settings alone (R5-9).
- Every Settings slider is a `SliderSetting` with live value field and reset; every slider in the menu is a `MenuSliderRow` with a live value; no slider in a submenu; no `NSHostingView` in a menu.
- Page budgets of §4.3 met; the duplicates resolved as in §4.4; no developer titles, camelCase ids or raw SF Symbol names visible.
- Migrations M1–M5 and M10 tested, each runs once (ledger markers, also across a 0.2 round trip), M1 gives the same rule ids on every run, M6 pinned by its `SafetyConfig` test; Awake lists survive one undecodable element; a 0.2 settings fixture (all features on) loads with no setting lost and a 0.3 → 0.2 downgrade still reads every legacy field.
- Lint passes with only permanent ratchet rows; CI green on all jobs; hardware list §6.7 run and Beta labels updated.

### 6.6 Kit unit tests (new)

- `AwakeFeatureGraph`: spec totality, resolve (kill switches incl. `unkillable` ignored, Safe Mode, requirements), `enabling` refuses unavailable, `requiredServices` per criterion kind and per dynamic need, activation order respects dependencies.
- `AwakeSession`/`AwakeClock`: start for every kind; remaining with continuous vs wall; `endWall` after a clock jump; `continuousEnd` for until-kinds; reboot expiry; clock jumps ±1 day don't move duration sessions; extend caps at 30 days; `canExtend` per kind; task caps; type-tagged Codable round trips and unknown types (incl. r3's `"hold"`) dropped; `overrideGuards` never encoded and false after decode; `source` survives a round trip; `isDirectUserAction` per source; `sanitized(now:)` bounds (start after now, deadline beyond the cap from start, cap/deadline mismatch; r3 security L3). `AwakeHold`: `.connection` never decodes, `.process` does, `sanitized(now:)` bounds, `maxHolds`. `AwakeActivityGate`: the full truth table per event, every `.unchanged` event leaves the gate equal, a hotkey start is `askOnFirstUse` until `confirmAllowed`, Not Now/dismissal → `declined`, the carry across back-to-back sessions and the 15-min reset (r3 security M1, M2, L5); (R5-7) rule A → rule B 1 s apart and with no inactive turn carry, `nothingGoverned` with nil `lastEnded` sets it; (R5-1) only `confirmAllowed` (from `asking`) or `uiStart` reach `.allowed`.
- `AwakeCountdown`: every boundary (3600, 3599, 61, 60, 59, 1, 0), "2h" on the hour, rounding up, `nextChange` never 0, spoken strings, `clock` 12/24 h.
- `AwakeDurationGrammar` / `AwakeCommandGrammar`: valid and invalid inputs, 7-digit / 2-decimal limits, "1e300h", huge digit strings, overflow, `idle`, `--pid` (≤ 1, negative, non-numeric refused), `--max` > 24 h refused, preset by index and name, locale-independent parsing, seeded fuzz never traps; `statusLine`/`statusJSON` incl. `pids` (R5-13) and the hand-formatted ISO time.
- `AwakeArbiter`: governing precedence manual > trigger > holds > inactive (N3, N17); holds plan `.system` with the latest hold deadline; every display policy × locked × console × idle; deadline grace; `needsSwap` thresholds; disk-idle flag; 1,000 inputs at advancing times → `needsSwap == false` after the first.
- `AwakeGuards` + `PowerMath`: desktop (never latched), AC and not falling, **AC but falling** (weak charger: battery rules and the hard floor apply), (R5-6) the window cases (5, 4, 4, 4 on AC stays discharging and keeps the hold; charging clears; 11 min of equal readings ages `falling` out but keeps the hold; `currentMilliamps < 0` sets `falling`), latched battery with a missing entry (unreadable, not a desktop), floor crossing, the 5% hard floor with the user floor off and with Start Anyway, `reloaded(sameBoot:)`, hysteresis +5 and the recovery-only clear (R5-6), two unreadable reads → `allowsBackgroundWork` false and no session end, one readable read clears it, adapter disconnect, LPM, serious warn-once (no end), critical end + cooldown, override only for battery/LPM, `allowsBackgroundWork`, `monotonic(over:)`, assertion-hold backoff (`assertionBackoffSeconds`, `recordingAssertionFailure`, R5-13).
- `AwakeTriggers` decode: lossy per criterion entry **and per rule** (one unknown 0.4 rule among three keeps two, and they survive the next save; r3 code M6), invalid ids drop the rule, duplicate rule ids keep the first (R5-3), unknown kinds dropped, the nested `"criterion"`/`"condition"` shape (one `type` key per object), limits (32/8), sanitize (names, CIDRs, bundle ids, minutes, every nudge → declare).
- `TaskQuiet`: each busy signal alone keeps the session (top process 50%, 3 new processes, total 15%, disk 1 MB/s, network 50 KB/s), all quiet for 5 min ends it, unknown sample and wake reset the window, minimum hold respected (R5-4), `quietFor`; single-threaded load on 12 cores stays busy (parity M2); (R5-4) a long-lived parent whose child time grows 5 s per 5 s window reads ≈ 100% and stays busy, and a `make -j1` fixture with no child alive at either sample instant stays busy.
- `TriggerEngine`: every criterion kind true/false/unknown; negation; all/any with unknowns; start/end delays on the continuous clock; priority order and reorder; pause; guard hold; manual end with and without `resumeAfterManualEndMinutes`; suppressions expire; overnight schedules and week wrap; `scheduleBoundaries`; `summary` wording; seeded fuzz deterministic.
- `AwakeHistory`: cap, merge of short `.replaced` runs, prune, totals across given day starts, lossy per entry, `offersStartAgain` per source and kind (r3 consistency m3).
- `AwakeSnapshot.sanitized(now:)`: other-boot session and holds dropped, `until` suppressions dropped and `untilFalse` kept on a boot mismatch, guard memory reset except `warnedSerious`, `source` kept, connection holds dropped, out-of-range kinds dropped, a bad hold keeps the manual session and duplicate hold ids keep the first (R5-3), a `.rule` manual session dropped (R5-14); `dynamicNeeds` per restored state (r3 code M1).
- `AwakeConfig`: presets lossy per element and de-duplicated by id (R5-3); every sub-config's declared `init(from:)` (R5-3); default preset ids equal `StableID.derived` across `init()` and `restoringDefaults()`; `restoringDefaults` (pointer movement and volumes off), `exportable` (nudge → declare, drops, rules opt-in, hashes stripped), `importable` applied after `KitBackup.merge` with a hostile backup (nudge in presets[]/triggers[], volumes, floor 5: none survive, guards only tighten; security L5); activity switches and `effectiveOptions` clamping (consistency M2); `defaultDisplayPolicy(for:)`.
- `AwakeMigration`: no Displays settings; feature off with flags; feature on but Displays module off (not effective → disabled trigger); 1, 3 and 9 displays (split at 8); missing fingerprints; corrupt JSON; ledger marker prevents a second run; the 0.2 `d.sleepPreventionToggle` combo moves to `awake.pauseAutomatic` or is dropped with a notice (R5-12); two runs over the same JSON give equal ids and, written over each other, one set of rules (r3 code M5). `NameHash`/`StableID.derived`: fixed vectors, valid `StableID`, version 8 and variant bits. `LossyArray`: round trip, one bad element dropped, encode keeps the rest. `MigrationLedger`: element-wise decode.
- `NetworkMath`: IPv4/IPv6 CIDR parse/match, invalid input, MAC normalization and hashing input, 64-bit byte deltas and resets, throughput with `lo0` excluded and `utun` + `en0` not double-counted. `CPUMath`: tick deltas incl. UInt32 wraparound, `CPUTimebase` (125/3 and 1/1; a busy Apple-silicon process reads ≈ 100%, not ≈ 2.4%), `processPercent`, `window` (first-seen-in-window whole CPU time, pid reuse by `startAbs`, churn count, child-time deltas; R5-4). `DiskMath`: per-driver deltas, a driver appearing or vanishing contributes nothing, a counter going down counts 0.
- `ActivityPolicy` truth table and `nudgeAllowed(governing:gate:…)` (false for trigger, hold, CLI, launch, restored and resumed sessions and for an unconfirmed hotkey start; r3 consistency M4), `needsPointerConfirmation`, edge margin, the Snaptic-clock cap at 1 h and 8 h independent of input, screensaver, console, lock); `IdleMath` (nudge and declaration echoes ignored, real input kept); `DriveAlivePolicy` eligibility table (allowlist, boot container, DMG, non-local, BSD name) and `shouldWrite` (CLI source incl. restored CLI sessions, guards, first write).
- `VolumeUUIDKey` validation; `WeekdaySet` masking.
- `SliderMath`: clamp/snap, isDefault tolerance, hand formats and spoken units, parse with units and both decimal separators.
- `SettingsIndex`: ranking, synonyms, diacritic table, empty query, anchors unique across the entries derived from every control table (R5-13), `id == anchor`, no entry text from config. `ControlRegistryTests` (§4.8 tests 1–6): every one of the 588 frozen ids has a home or a removal reason, never both; unique ids with surface prefixes; settings ↔ search entries; menu show/hide rows; the `ConfigFixtures` key cross-check; the registry list; (the 46 `DisplayMenuItemID`s check moved to `--selftest-controls`, R5-13); `menuSlider` specs never located in a submenu and never three-way.
- `MenuLayout`: presence × awake active × displays active × shortcut bound × shown at rest → plan (custom items, compact section, `sharedActiveGlyph = governing && showShared`, footer in own menus, Snaptic item existence incl. "no module enabled" → item and "everything Don't Show" → none); `.hidden` fallback when the shortcut isn't registered (registered flag, not the stored combo); `MenuPresence.allowed(for:)`; `legacyPlacement`. (r3's "slider never inSubmenu" moved to `ControlRegistryTests`, section ordering is `MenuConfig.orderedSections` in `ConfigMenuTests` (M), and compact mode has no Kit logic; r3 consistency m15.)
- `DisplaysConfig`: `changedSections` per field incl. every per-display subsection, M4/M5/M10 run once through `migrated(ledger:)` (R5-2), legacy fields still encoded, `restoringDefaults(scope:)` per `DisplaysRestoreScope` leaves other scopes; `ModulesConfig` M2 (incl. Displays hide flag → Show When Active and the presence-absent round trip), M3 via `migrated(ledger:)` (R5-2), per-id defaults, `upgradeDefaults()` has Awake disabled, `newModuleCards` with an unknown id (dropped alone) and `.awakeMigrated` kept through decode and `sanitized()` (r3 consistency M2); M10 writes `menu.items[.dDisconnectItem]`/`[.cDDCPower]`. `SafetyConfig` M6 pin.
- `KitControl`: `ControlResponse` hand-written decode (an old reply without `holding` decodes, `holding` round-trips, `jsonReply` keeps it); `maxHeldConnections == 8`; `retiredVerbs["prevent-sleep"]` (R5-12). `EventCategory.isExportedInDiagnostics` false for `.awake`.
- `AwakeRefusal`: `exitCode` (4) and `text` per case, incl. `holdLimit` and the CLI-only cases (r3 consistency m15). `AwakeLogEvent`: fixed `text` per case, counted vs ring split, no case carries a name, pid or payload.

### 6.7 Hardware checks (first session; Beta labels depend on them)

| # | Check |
|---|---|
| HW-1 | Both assertion types on 14/15/26/27, Intel + Apple silicon; `pmset -g assertions` rendering of name/details; `CGSSessionScreenIsLocked` present in the session dictionary on 14–27 |
| HW-2 | (informational since r2: no SetProperty) timeout behavior of `TimeoutSeconds` across system sleep |
| HW-3 | Assertion swap (create-then-release) leaves no gap (display doesn't dim at the swap), incl. deadline re-arm |
| HW-4 | Screen saver and "require password after screen saver" with each assertion type and with `declare` |
| HW-5 | `IOPMAssertionDeclareUserActivity` vs `CGEventSourceSecondsSinceLastEventType` per type (does a declaration reset any type? does Slack/Teams go Away?); in declare mode the cap ends activity after 1 h and the Mac then idle-locks |
| HW-6 | ±1-pt nudge from a `.privateState` source: does `.hidSystemState` idle reset? not visible; edge skip; Accessibility-denied path; tagged events ignored by switcher hover |
| HW-7 | `keepOnWhileActive` downgrade/upgrade timing with real idle; lock-screen downgrade (C1) actually lets the display sleep |
| HW-8 | Lid close on battery / AC / desktop mode; `AppleClamshellCausesSleep` values; wake path ends/continues sessions correctly |
| HW-9 | CoreAudio `DeviceIsRunningSomewhere` on input causes no microphone prompt or orange indicator; HAL queue never blocks main |
| HW-10 | IOHIDDevice registry reads for Bluetooth input devices need no Input Monitoring |
| HW-11 | Router MAC via routing-table `sysctl` on 15/26/27 triggers no Local Network prompt; `NET_RT_IFLIST2` counters at 10 GbE |
| HW-12 | Removable Volumes prompt text and denial path; Drive Alive keeps a USB HDD spinning; eject not blocked; DMG and boot-container volumes refused; exFAT and FAT32 stick: switch on, switch off, `ls -la` the root shows neither `.snaptic-keepalive` nor `.snaptic-keepalive.removing`; RENAME_EXCL support on both |
| HW-13 | IOPS notifications on desktop Macs (no battery) and on battery percent changes; LPM notification queue; an underpowered USB-C charger/hub under load: `AC Power` with a falling percentage is treated as discharging (r3 security M3); `AppleSmartBattery` latch on every laptop model at hand; (R5-6) `falling` stays set between percent steps and IOPS `Current` is negative while the battery drains on that charger |
| HW-14 | Status item `autosaveName`, `isVisible` KVO after ⌘-drag on 14–27; create/remove with Show When Active; countdown width stability; 26 "Allow in the Menu Bar" off; (R5-9) with the Snaptic and Awake items hidden, start For 2 Hours, an app session and Until Downloads and Tasks Finish from Settings alone; 27 overflow; notched MacBook with 20 items: the Snaptic active glyph is visible when the Awake item lands behind the notch (parity M5) |
| HW-15 | AppKit menu rows (MenuSliderRow, MenuSwitchHeader): alignment with native items, slider keyboard behavior, highlight drawn on arrow-key navigation, vibrancy on 26/27 material, `sectionHeader` look on 14/15/26/27; Option alternates on 27 and on 14.0–14.3 with title subtitles; arrow-key and VoiceOver navigation reach "Turn Off Keep Awake"; countdown and live slider values update while the menu stays open (`.common` mode); the Snaptic menu in the default setup stays within the §5.2 row budget (≤ 24 lines; r3 product minor 16) |
| HW-16 | Settings: `.searchable(placement: .sidebar)` + `ScrollViewReader` scroll in grouped `Form` on 14; `NavigationStack(path:).id(root)` back button; next-turn push; `.toolbar(removing: .sidebarToggle)`; fixed 715 pt width |
| HW-17 | `NumberField` commit on blur inside `Form`; typed-field commit: type in a number field, click Done or + with the mouse: the typed value is used; Esc revert; VoiceOver values with units; small row switch size matches System Settings on 14–27 |
| HW-18 | Thermal states (via a load generator) produce the toasts/ends; `CLOCK_MONOTONIC_RAW` advances across sleep |
| HW-19 | `defaults write` of pointerNudge + a nudge preset, a Drive Alive volume, floor off, a forged `.menu` snapshot with `--pid` holds, and a rebound `awake.toggle` hotkey, while Snaptic is quit, stopped and running: no pointer movement for CLI, rule, hold, restored or resumed sessions, none for the hotkey start until Allow is clicked (and the toast appears once); the 5% floor still ends a session, also on a weak charger; Drive Alive writes only to eligible volumes; a snapshot written while running has no effect |
| HW-20 | `NSMenuItem.subtitle` with the 15.5 SDK on 14.4, 15, 26, 27; fallback rows on 14.0–14.3 |
| HW-21 | `awake hold`: kqueue `EVFILT_PROC`/`NOTE_EXIT` + `proc_pidinfo` start time; `LOCAL_PEERPID` on the CLI socket; client killed with SIGKILL / Control-C / terminal closed → its hold ends within 1 s; forked child holding the fd doesn't keep it; `--pid $$` in a script, in a `make` recipe line (ends at once, toast) and with `.ONESHELL`; PID reuse refused; a hold while a UI "For 2 Hours" session runs: both coexist, the Mac stays awake after the UI session ends, the menu says "Held by Terminal" (Terminal, iTerm, Xcode, VS Code terminal); 8 holds + normal CLI requests at the same time; a 9th hold refused; ping keeps an idle 12 h hold; no read timeout; Control-C during a `make` recipe running the README's `snaptic awake hold &` line ends the hold with the build |
| HW-22 | (r2 Keychain check withdrawn with N10) |
| HW-23 | `untilIdle` defaults (top process 50%, 3 new processes, total 15%, disk 1 MB/s, network 50 KB/s, 5 min) on a 10-core Apple-silicon Mac and an Intel Mac: the timebase-scaled rusage reads ≈ 100% for one busy core; stays during a `make -j1` compile phase of 1–3 s `clang`s (through `make`'s child time, R5-4), a single-threaded link phase, a 20 GB copy to an external SSD, a large download and an archive extraction; ends after each. Root Spotlight and Time Machine **CPU** doesn't count (other users' processes are unreadable), but their **disk** I/O does (the IOBlockStorageDriver counters are system-wide), so a session may run on while they index; record how long. `proc_pid_rusage` of every pid needs no prompt and costs ≤ 5 ms per sample |

### 6.8 Open questions

- **OQ-1** Settled in r2: Drive Alive ignores CLI-started sessions (strict).
- **OQ-2** Closed (R5-11): every kind uses the default options, so "Keep the display on" governs all sessions that don't set their own; `keepOnWhileActive` stays at 30 min.
- **OQ-3** History on by default (S) vs opt-in. Default: on, local only, 90 days.
- **OQ-4** Whether the Displays root page keeps a Refresh rate pop-up when Resolution's pop-up already lists rates per mode. Default: keep (Apple precedent).
- **OQ-5** Glyph families: confirm `cup.and.saucer`, `eye`, `lightbulb` and their `.fill` variants on macOS 14 (tested in Kit by name list; runtime fallback `cup`).
- **OQ-6** Sticky-switcher menu item (C8) interaction with `releaseToSwitch` users; fallback is to omit the item.
- **OQ-7** Default for "After the screen has been locked for…" (security L5). Default: Never; product may choose 12 h.
- **OQ-8** `untilIdle` thresholds after HW-23. Default: top process 50% of one core / 3 new processes per 5 s / total 15% / disk 1 MB/s / network 50 KB/s / 5 min. (r3 code M2 proposed comparing the **sum** of same-user processes; rejected for now because many idle background apps add up and would keep sessions alive; churn and aggregate CPU cover the short-lived case. HW-23 may revisit.)

## Implementation readiness

r5 is final. No design question blocks implementation:
- OQ-1 and OQ-2 are closed.
- OQ-3 to OQ-8 keep their stated defaults until the §6.7 hardware session.
- Every signature in §2, §4.1, §4.5, §4.6, §4.8, §5.2 and the R5 amendments is step-0 contract text. Once stubs are on the branch, the code wins over prose (R5 rule carried forward).

### Step 0: what the lead must produce, in order

1. **TEAMS.md**
   - Contract-file list: `ConfigModules.swift`, `ModuleHost.swift`, `ModuleContext.swift`, `ToastPresenter.swift`, `ConfigModulesTests.swift`, `KitLossy.swift` + `KitLossyTests.swift` (⇢ from A, R5-14), `Controls/{ControlRegistry, ControlLegacy, ControlRemovals}.swift`, `ConfigMigrations.swift` and `ConfigFixtures.swift`.
   - The ratchet exception.
   - The control-table registration exception: one appended `ControlRegistry.tables` line plus the `stubs.tsv` row, per owner-added table (R5-13).
2. **`scripts/stubs.tsv` and `gen-stubs.py`**
   - One row per §6.2 path with its owner and kind, including the R5 changes:
     - `OverviewMenuItems.swift` (F), `ManagementMenuItems.swift` (D) and `AutomationMenuItems.swift` (A) are new;
     - KitLossy moves to the lead;
     - no `SettingsIndex*` rows.
   - Stub kinds K15–K19 and K21; K20 is unused.
3. **Lead Kit code with its tests (real code, not stubs)**
   1. `KitModules.swift`: `ModuleID.awake`, `EventCategory.awake` + `isExportedInDiagnostics`, `AwakeActionID`, `AwakeCriterionKind`, `MenuPresence`, `NewModuleCard`, `DisplayActionID.fShowPanel`/`.fIdentify`, `DisplayMenuItemID.cDDCPower`, `NameHash` + `StableID.derived` (fixed vectors).
   2. `KitLossy.swift`: `LossyArray` (Codable), `lossyArray`, `lossyUniqueArray`, `uniquedByID`, `uniqued` (R5-3).
   3. `ConfigMigrations.swift`: `MigrationLedger` and `MigrationID` (R5-2).
   4. `ConfigModules.swift`:
      - `presence` + M2 in decode;
      - `newModuleCards` (lossy, uniqued);
      - per-id defaults, and `upgradeDefaults()` with Awake disabled;
      - the defaulted `StatusItemPlan` fields;
      - `migrated(ledger:)` (M3).
      `ConfigModulesTests` line 16 is updated.
   5. `ConfigDisplays.swift`: `DisplaysConfigSection` (no `migrations`), `changedSections`, `DisplaysRestoreScope` + `restoringDefaults(scope:)`, `migrated(ledger:)` (M4, M5, M10), and the run-once and round-trip tests.
   6. `AwakeFeatureGraph.swift` + tests (`indicator` unkillable).
   7. `Controls/`:
      - `ControlRegistry` (`ControlID`, `LegacyControlID`, conditions, `ControlSpec` with `search`, `SearchSpec`, `ControlTable`, `tables`);
      - `ControlLegacy` (the literal 588 ids, `switcherKeyPaths: [String: [LegacyControlID]]`, `internalKeys`);
      - `ControlRemovals`;
      - K21 stubs of every §4.8.2 table;
      - `ConfigFixtures`;
      - `ControlRegistryTests`: the per-table tests on; totality and the key cross-check skipped.
4. **S stubs of team Kit types**, hand-written from this plan as amended, with safe returns:
   - **G:**
     - `AwakeSession.swift`: `UntilIdleSpec.minimumHoldSeconds`, `TaskQuiet.step(…started:…)`, `AwakeSessionSource.rule`, `AwakeEndReason.commandLineOff`, `AwakeHold`;
     - `AwakeActivityGate` (R5-7 events);
     - `AwakeClock` + `AwakeTextContext` + `AwakeCountdown` + `AwakeDurationGrammar`;
     - `AwakeArbiter`;
     - `AwakeGuards`: the R5-6 `PowerFacts` init, and `GuardMemory` with the backoff API;
     - `AwakeTriggers`, `AwakeTriggerEngine`;
     - `AwakeHistory`, `AwakeSnapshot` (declared decoders);
     - `AwakeMigration`: the R5-12 signature, returning `.nothing`;
     - `AwakeCommandGrammar`, `AwakeLogEvent`;
     - the `ConfigAwake` shell + every sub-config with its declared `init(from:)` (R5-3).
   - **J:** `CPUMath` (R5-4), `PowerMath` + `BatteryReading` (R5-6), `NetworkMath`, `DiskMath`, `ActivityPolicy`/`IdleMath`, `DriveAlivePolicy`, `ConfigAwakeDevices`.
   - **H:** `SliderMath`/`ValueFormat`, `SettingsIndex` (`SettingsRoute`, `SettingsSearchEntry`, `SettingsIndex.entries`).
   - **M:** `MenuLayout` (reproduces 0.2 placement).
   - **B:** `Fingerprint.matches`.
5. **Lead app code**
   - `ModuleContracts`: the §4.1 contracts + extension defaults, `SettingsTint`, `FeatureHighlight`, `StatusItemProvider`, `CustomItemRow`, `ControlDeclaring`, `FeatureAvailability` (moved here).
   - `ModuleContext` additions, `HostSignals`, `ConfigSlice`.
   - `ToastPresenter`: `ToastAction` extended, `ToastDismissal`, `ToastClickGuard`, and `show(_:actions:…) -> Bool` as an S stub (R5-1).
   - `ModuleHost`: Awake wiring, the three stores, the ledger store and the R5-2 order, `Modules.disable.<id>`, upgrader insertion, the M1 hook calling the stub.
   - Awake shell: a full stub `AwakeModule`, `AwakeContext` + `AwakeHost`, `AwakeContracts` + `ChangeFanout`, `AwakeRuntimeState`.
   - Displays contracts: the `observedSections` requirement + default, `ControllerRevision`, `DisplayRuntime` fields, `DisplayLiveControlling`.
6. **App stubs**
   - K15–K19 for every team file in §6.2.
   - S stubs of the SettingsUI components and MenuKit, including the `control:` parameters (R5-13).
7. **Lint and ratchet**
   - L1–L17: L5 and L15 in python; L16 scoped to `Sources/Snaptic/`; L17 new.
   - `lint.sh --write-ratchet` at 871c10b, plus the three permanent rows.
8. **Build files**
   - `Package.swift` links CoreAudio, SystemConfiguration and DiskArbitration.
   - `Info.plist`: 0.3.0 and `NSRemovableVolumesUsageDescription`.
9. **Exit:** CI green on Linux (Swift 5.10) and macOS (Xcode 16.4, Swift 5 mode) with the ratchet, and no reference to a team-owned type that doesn't exist yet.

These stay **out of step 0**, unchanged from §6.4:
- `ControlServer`'s new types and both self-test CI steps: A and lead, step 1.
- M1's implementation: G in step 1; the lead wires it in step 2.
- The `sleepPrevention` removal, the `prevent-sleep` retired verb and dropping the old protected words: the step-3 coordinated merge.
- Removing `DisplaysPageEnvironment` forwarding, `settingsPages()` and the old handler overload: the step-3 exit.

### Teams and ownership (confirmed)

§6.1 stands, with these R5 deltas. Every file still has exactly one owner, and R5 adds no collision.

| Team | R5 deltas |
|---|---|
| Lead | Takes `KitLossy.swift` and its tests from A. Owns `MigrationID` and the `migrated(ledger:)` functions, `SearchSpec`, `ToastClickGuard`/`ToastDismissal`/`show(_:actions:…)`, `scripts/selftest-control-server.sh` + its CI step, and lint L17 |
| G | `AwakeSessionSource.rule`, `.commandLineOff`, the R5-7 gate, the Keep Awake pull-down and Replace With (R5-9), the R5-10 toasts and holds-only rows, default preset order, display defaults (R5-11), M1's hotkey move (R5-12) |
| J | Child CPU time and `minimumHoldSeconds` support in `CPUMath`/CPUSampler (R5-4); the windowed `PowerMath` and `BatteryReading` in PowerMonitor (R5-6) |
| H | `SettingsShell.mayStart()`/`externalOpenPending` (R5-8); `SettingsIndex.entries` (R5-13); `control:` parameters on the SettingsUI components |
| M | `control:` parameters on MenuKit; the Customize sheet without the accordion (R5-11) |
| A | `--selftest-control-server`, `sendHeld`, `start(socketPath:)`, the CLIClient token-mode override, the new `dispatch` signature (R5-5); `retiredVerbs` (R5-12); `AutomationMenuItems` |
| D | `ManagementMenuItems` (R5-13) |
| F | `OverviewMenuItems` (R5-13) |
| B, C, E | None beyond their R5-13 tables (C absorbs five contributors into `ColorMenuItems`) |

### Delivery order (confirmed)

Steps 0 → 1 → 2 → 3 → 4 (review) → 5 (README, release) as in §6.4. R5 adds these exit items and merge-order notes:

**Step 1**
- A's `scripts/selftest-control-server.sh` is green in CI.
- The per-table `ControlRegistryTests` are green.
- The Awake protected words are added.
- J's CPUSampler counts child time.
- H ships `SettingsShell.mayStart()`.

**Step 2**
- Within the step, the lead's real `ToastPresenter.show(_:actions:…)` (R5-1) merges **before** G's confirmation and Turn Off toasts.
- The lead wires M1, including the hotkey move.

**Step 3**
- The coordinated `sleepPrevention` merge includes the `prevent-sleep` retired verb and drops `"sleepprevention"`/`"preventsleep"`.
- `ControlRegistryTests` totality and the key cross-check are turned on.
- The ratchet keeps only permanent rows, and CI runs `lint.sh --strict`.

**Steps 4 and 5:** unchanged.
