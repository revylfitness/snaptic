# 0.3.1 step 0: what landed, and where the code refines the plan (lead)

Step 0 of `PLAN.md` (r5) Part D is on `feature/v031-step0`. Once stubs are on the branch **the code is the contract**
(the 0.3 rule carried forward): read this file together with the code. Every stub body returns a safe value (no
`fatalError`). Stubs that teams replace are marked "Step 0 stub" in their doc comment; the `step0Controls` lists exist
only so L15 sees each new control id used once; the owning team deletes its list when it wires the ids.

## New files (`scripts/stubs.tsv`, kind L)

| File | Owner | What the stub holds |
|---|---|---|
| `Sources/Snaptic/Core/MenuTabBar.swift` | T-menu | `MenuTabBarView: NSView` (empty) |
| `Tests/SnapticKitTests/MenuTabsTests.swift` | T-menu | placeholder test |
| `Sources/SnapticKit/LidWatchdog.swift` | T-lid-kit | `AdminScript`, `ToolCommand` (both `fileprivate init`), `LidWatchdog` API below |
| `Sources/SnapticKit/AwakeLidGate.swift` | T-lid-kit | `AwakeLidGate.Decision`, `.Event`, `decide(source:mayStart:event:)` → `.end` |
| `Sources/SnapticKit/AwakeLidPolicy.swift` | T-lid-kit | `AwakeLidMode`, `AwakeLidEnd`, `AwakeLidFailStage`, `AwakeLidJournal`, `AwakeLidRecovery`, `AwakeLidRefusal`, `AwakeLidPolicy` |
| `Tests/SnapticKitTests/{LidWatchdog,AwakeLidGate,AwakeLidPolicy}Tests.swift` | T-lid-kit | placeholder tests |
| `Sources/Snaptic/Awake/Core/LidClosedController.swift` | T-lid-app | `@MainActor final class LidClosedController { weak var context: AwakeContext? }` |
| `Sources/Snaptic/Core/LidRecovery.swift` | T-lid-app | `LidRecoveryState` (below) |
| `Sources/Snaptic/Core/UpdaterController.swift` | T-update | `protocol UpdaterControlling` (below), empty `UpdaterController` |
| `Sources/SnapticKit/UpdatePolicy.swift` | T-update | `UpdateOffer`, `UpdatePolicy.Facts` / `waitText(_:version:)` → nil, `UpdateStatusText` (empty), `UpdateDefaultsKeys.all = []` |
| `Tests/SnapticKitTests/UpdatePolicyTests.swift` | T-update | placeholder test |

## Signatures in shared files

**Kit**
- `AwakeFeatureGraph.swift`: `AwakeFeature.lidClosed` (`.optIn`, `all: [.sessions]`, `uses: [.power, .system]`,
  `controller: .sessions`), added to `safeModeRemoves`; its kill switch is `Awake.disable.lidClosed` by the existing
  rule. Needed in step 0 because the B7 specs say `.awakeFeature(.lidClosed)`. Backup handling (B5) is still T-lid-kit's.
- `AwakeSession.swift`: `AwakeSession.lidRequested: Bool = false` (not in CodingKeys; reset in `init(from:)` and
  `sanitized(now:)`; no init parameter, so only an assignment can set it, which L16 limits);
  `AwakeEndReason.lidEnded`; `AwakeRefusal.lidClosedSession` (exit 4, the B2 text).
- `AwakePresentation.swift`: `AwakeEndText.phrase(.lidEnded)` = "lid-closed mode turned off while the lid was closed"
  (`isInterruption` true; the toast is the standard "Awake ended: …." path; tested); `AwakeMenuRow.lidClosed(LidRowState)`
  and `.lidSubmenu([StableID])`; `LidRowState { off, on, authorizing, verifying, stopping, finishingEarlier }`;
  `AwakeMenuStyle { own, compact, tab }`; `AwakeMenuFacts.style` with a computed get/set `compact` and both inits
  (`style:` and the 0.3 `compact:`). `AwakeMenuModel.rows` doesn't emit the lid rows or treat `.tab` yet (`.tab` reads
  as `.own`).
- `AwakeArbiter.swift`: `AwakeArbiterInput.lidShut` (init parameter, default false). The arbiter ignores it until
  T-lid-kit lands.
- `AwakeCommandGrammar.swift`: `AwakeStatusFacts.lidClosed` (init parameter, default false); not in the JSON yet.
- `AwakeLogEvent.swift` (not in the plan's step-0 list; T-lid-app logs them): `lidOn`, `lidOff(AwakeLidEnd)` (counted),
  `lidFailed(AwakeLidFailStage)`, `lidLeftover` (ring).
- `KitArgs.swift`: `LaunchMode.selftestLaunch` for `--selftest-launch` (tested).
- Controls: `ControlKind.menuTabBar`; `ControlState.lidModeOn, lidLeftover, bundleWritable, updaterAvailable,
  updateAvailable, v031Welcome`; `SettingsIndexCoverage.requiresSearch` → false for `.menuTabBar`.

**LidWatchdog API** (all `package static`): `osascriptPath`, `osascriptRequirement`, `toolRequirement` ("anchor
apple"), `capSeconds = 86_400`, `displaySleepArgv: ToolCommand` (real values); `Outcome { launched(pid:), canceled,
failed(Int32) }`; `Arguments` (`uid: UInt32, pid: Int32, token, capSeconds, floor, dir`) with
`Arguments.validated(uid:pid:token:capSeconds:floor:dir:) -> Arguments?` → nil; `defaultTools: [String: String]` (empty);
`script(tools:period:stale:) -> String` → ""; `command(_:) -> String` → ""; `appleScript(command:prompt:) -> String?` →
nil; `startScript(_:prompt:) -> AdminScript?` → nil; `restoreScript(prompt:) -> AdminScript?` → nil;
`parseResult(_:) -> Outcome` → `.failed(-1)`; `promptText(floor:)` → ""; `restorePromptText` → "".

**AwakeLidPolicy API**: `floor(awakeGuards:) -> Int` → 50; `until(sessionEnd:capStart:) -> Double` → capStart;
`capWarningDue(until:sessionEnd:now:) -> Bool` → false; `endsSession(lidShut:lidWillSleep:reason:) -> Bool` → true;
`classify(journal:bootUUID:sleepDisabled:now:ownPID:) -> AwakeLidRecovery` → `.nothing`;
`startRefusal(batteryPercent:discharging:floor:thermalSerious:overrideGuards:translocated:recovery:) -> AwakeLidRefusal?`
→ nil. `AwakeLidMode` has `isOn`, `isPending`, `token`; its cases carry `token: String`, `pid: Int32`, `until: Double`
(continuous) and `failed(AwakeLidFailStage)`. `AwakeLidJournal` holds the B3.1 fields (`startedAtWall`,
`startedAtContinuous`, optional `pid` / `instanceID`). `AwakeLidRefusal.text` → "".

**App**
- `ModuleContracts.swift`: `SnapticModule.menuSection(tabbed:)` (default: `menuSection()`), `menuAttention` (default
  false); `CustomItemRow.leftover` and `.updateAvailable` (`var … = false`, so 0.3 call sites compile unchanged).
- `StatusMenu.swift`: `static func leftoverItems(host:) -> [NSMenuItem]` (built from `host.lidRecovery.showsRows`, with
  Turn Sleep Back On… calling `turnSleepBackOn()`; empty in step 0) and `static func updateItems(host:) ->
  [NSMenuItem]` (from `host.updater?.availableUpdate`; "Update Available: Snaptic 0.3.2…" or "Restart to Update
  Snaptic…", calling `installUpdate()`; empty in step 0). Neither is placed in a menu yet: T-menu places them, and
  T-lid-app's IndicatorController calls them for Awake's own menu.
- `ModuleHost.swift`: `let lidRecovery = LidRecoveryState()`; `private(set) var updater: (any UpdaterControlling)?`
  (nil); `func startUpdater()` (empty). `AppDelegate.swift`: the Part E hunk is one call, `host.startUpdater()` right
  after `host.bootstrap()`, so T-update never edits AppDelegate.
- `LidRecoveryState` (`@MainActor`, `ObservableObject`, parameterless init): `recovery: AwakeLidRecovery`, `dismissed`,
  `showsRows`, `blocksTurnOn`, `turnSleepBackOn()`, `keepSleepOff()` (stubs), `notNow()`.
- `UpdaterControlling` (`@MainActor`, `AnyObject`): `automaticallyChecksForUpdates`, `automaticallyDownloadsUpdates`
  (get set), `availableUpdate: UpdateOffer?`, `hasPendingQuitInstall`, `checkForUpdates()`, `installUpdate()`. How
  StatusMenu hears that `availableUpdate` changed is T-update's and T-menu's to agree (a publisher or a rebuild call).
- `AwakeModule.lidModeOn: Bool` (`runtime.lidMode.isOn`).
- `AwakeRuntimeState`: `lidClosed: Bool?` (reset to nil), `lidMode: AwakeLidMode = .off` (not reset: only
  LidClosedController assigns it), `lastLidEnd: AwakeLastLidEnd?` (survives reset, like `lastEnd`);
  `struct AwakeLastLidEnd { reason: AwakeLidEnd; at: Date }`.
- `HelperSpawner.swift`: `spawnAdminScript(_: AdminScript, onLine:onExit:) async throws -> HelperHandle` and
  `spawnTool(_: ToolCommand, onExit:) async throws -> HelperHandle`; both throw `.unavailable("Not built yet")`.
- `OtherAssertionsReader.sleepDisabledPreference() -> Bool` (nonisolated, IPC: call off main). Real: it wraps the
  existing preference read.
- `--selftest-launch <token-file>`: `KitArgs` mode, `SnapticEntry` dispatch, `SelfTest.runLaunch` with the token gate,
  then prints "selftest-launch: not built yet" and exits 0. It doesn't build `ModuleHost` yet: that init runs the
  migrations and writes the user's defaults, so T-update decides how a self-test builds it. CI doesn't run it yet.
- `AwakeMenuRows.items`: `case .lidClosed, .lidSubmenu: break`.

## Controls (A6, B7, E7, E1a)

All specs are in their tables as the plan states them; each id is used once in a `step0Controls` list (or a real
builder) in a file whose `typealias Controls` names the table: StatusMenu (`tabs`, `showTab` in the list;
`lidLeftover`, `lidRestore`, `updateAvailable` in the two static builders), AwakeMenuRows, AwakeAdvancedSheet,
AwakeStatusSection, CustomSessionPanel, AboutPage, GeneralPages and Onboarding.

## Plan ambiguities resolved

| Plan | Code | Why |
|---|---|---|
| `menu.snaptic.lidLeftover` / `lidRestore`: three placements; `updateAvailable`: footer, own and Awake menus | One `MenuPlacementSpec` each, naming all the places ("Snaptic menu, own menus and Awake menu"; "Snaptic menu footer, and own and Awake menus with the shared footer") | `ControlSpec` has one placement; 0.3 already writes "Awake menu and the compact Awake section" |
| `menu.snaptic.tabs`: placement "—" | `menu: snapticMenu` | Every StatusMenu spec has one |
| `awake.custom.lidClosed` is a `.setting` without search ("the surface is exempt") | `ControlRegistryTests`' "every setting has a search entry" now applies to Settings surfaces only (`SettingsIndexCoverage.isSettingsSurface`) | The test predates settings outside Settings |
| `general.page.card.v031.*` are `.button`s with only `.state(.v031Welcome)` | Listed in `SettingsIndexCoverage.unsearchable` with reasons | The coverage test requires an entry or an exclusion for buttons on a Settings page; the 0.3 cards avoid it with `.perItem("card")`, which the plan doesn't give these |
| `awake.advanced.lidBundleLearnMore`: `when: … + […]` | `awake + [.hardware(.battery), .parentOn(lidClosed), .state(.bundleWritable)]` | "…" read as the toggle's own conditions |
| `about.page.autoInstall`: "Search: 'Download and install updates automatically'" | That title, no keywords | Nothing more is stated |
| B7 leftover rows on the Awake page: `when: awake + [.state(.lidLeftover)]`, while B3.4 shows them "even while Awake is turned off" | B7's `when:` as written | Noted for T-lid-app: the view, not the spec, decides where the rows show |
| `ControlState.lidModeOn` "used above" | Declared, used by no spec | r5 made the ✓ title a note (review r3 design); kept because the task lists it |
| `AwakeHost.lidModeOn` | `AwakeModule.lidModeOn` | StatusMenu reaches Awake through `host.awake` (the module); `AwakeHost` is the host's services *for* Awake and isn't reachable from StatusMenu |
| B7 keyword "disablesleep" vs L18 ("disablesleep" only in LidWatchdog.swift) | L18 skips `SearchSpec(…)` calls in `SnapticKit/Controls/` | Search keywords are data the user types, never a command |
| Rule 12 gains the script-runner names | The regex grows; its HelperSpawner/SNSpawn exemption is unchanged | As written |
| "only `publish` runs `gh release`" must not fail today | The rule turns on by itself once a `publish:` job exists in a workflow; no ratchet row | Today's `release` job still publishes; T-update's rewrite adds `publish` and removes `release` in one change |
| L19 Package.swift rule must not fail before T-update | Checked once any source imports Sparkle (or Package.swift declares any `.package(`): exactly one dependency, Sparkle with `exact:`, under `#if os(macOS)`, and `Package.resolved` present | Self-activating, no lead follow-up |
| L19 "SU* key strings" | String literals matching `SU[A-Z][a-z]…` (`SUFeedURL`, not `SUPPORT`) outside `SnapticKit/UpdatePolicy.swift` | File-level stand-in for "only in UpdateDefaultsKeys" |
| B1 `lidRoute` "Unavailable (translocated, or no lid)" | `AwakeLidRoute.unavailable` also covers no battery, the kill switch and Safe Mode; B1 now reads "(translocated, no lid, no battery, kill switch, or Safe Mode)" | In those three the Advanced toggle is missing or locked, so "Feature off" would point at a control the user can't use (r1 A, question b) |
| History `lidClosed` (B5) and `MigrationID.v031Welcome` (E1a) | Not added | Each has a single owner (T-lid-kit with HistoryController's input agreed with T-lid-app; T-update), and adding a Codable field changes encoded JSON that tests pin |

## Lint (frozen after step 0; teams ask the lead)

`scripts/lint.sh` rule 12 and `scripts/lint03.py` (docstring lists everything): L16's lid clauses, L18, L19 and the
workflow rules, each pinned by self-check cases in `self_check_031()`. Workflow rules: no `pull_request_target`, no
`workflow_run`, no `set -x` / `-o xtrace` (also `bash -x`), no `actions/cache` in `sign` or `publish`, and `gh release`
only in `publish` (once it exists).

`.github/CODEOWNERS`: `* @frasurebuilds`.

## Lead decisions after step 0 (answers to the step-0 open questions)

1. **API ownership.** A team may change any API in a file it owns. A change to a cross-team shape (`UpdaterControlling`,
   `LidRecoveryState`, `StatusMenu.leftoverItems` / `updateItems`, `CustomItemRow` flags, `menuSection(tabbed:)`,
   `menuAttention`, `AwakeMenuStyle`, the Kit lid APIs T-lid-app calls) must stay source-compatible with the step-0
   signature (add, don't rename or remove), and is listed in the team's final report. The lead reconciles at merge.
2. **Leftover rows on the Awake page: B3.4 wins.** The rows show even while Awake is turned off (parity m5). T-lid-app
   makes the view do that; the B7 `when:` on the spec stays as written (the spec doesn't gate the view).
3. **Update changes reach StatusMenu through `ModuleHost.updaterChanged`** (a `PassthroughSubject<Void, Never>`, added
   here). T-update sends it on main after every change to `availableUpdate` or `hasPendingQuitInstall`; T-menu
   subscribes in StatusMenu's init and calls `requestRebuild()`, as for `lidRecovery.objectWillChange`.
