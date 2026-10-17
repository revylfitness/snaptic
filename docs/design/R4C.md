# Review r4: code review, architecture and buildability

**Lens.** Does PLAN r4, with the [R2C]/[R3C] snippets, compile? Can the lead execute 0b mechanically, so that six teams fan out without editing each other's files? Are the new r4 mechanisms free of fd, lifetime and identity holes? These mechanisms are `HelperSpawner`/`SNSpawn`, SecCode checks, the debug-only self-test, `ConnectPlanner`, per-display runtime state, the menu dirty flag and `ToastPresenter`.

**Evidence.** Repo at 853e18b, plus one uncommitted change: `build.yml` pins `ubuntu-24.04`, which needs committing with 0b. There's no Swift toolchain or Docker daemon in this sandbox, and `download.swift.org` is blocked by the proxy, so compile claims below are reasoned from the language rules, not run. The Swift-level claims are conservative, and each has a cheap fix that is correct either way.

**Severity.**
- **Blocker:** won't compile as specified, or forces one team to edit another team's or the lead's frozen file.
- **Major:** a likely crash, leak, race, silent no-op or wasted rounds.
- **Minor:** a cheap fix.

---

## Ranked summary

| # | Sev | Section | One line |
|---|---|---|---|
| 1 | Blocker | A.1, A.2 vs §13 | ~14 classes have **two homes**. A.1 puts `GlobalHotkeys`, `ConfigStore`, `PermissionFlow`, `HelperSpawner`, `ToastPresenter`, `HostHeartbeat`, `ModuleContext`, `EmergencyActions`, `EventLog`, `Lifetime`… in the lead's `ModuleContracts.swift`, while §13 gives each its own A file. A.2 does the same for `DisplaysContext`, which sits in both `DisplaysContracts` and `DisplaysContext`. The result is either a redeclaration in 0b, or A editing the lead's frozen file. |
| 2 | Major | A.1, A.2 | r4 Appendix A shrank to names. The only Swift for `SnapticModule`, `ModuleContext.init`, `GlobalHotkeys`, `ControlCommandRegistry` and the `DisplaysContext` properties is in **PLAN-r3**, which isn't in the normative list, yet A.2 cites "the r3 A.2 table". The six context properties added since r3 have no names. |
| 3 | Major | §3.2 `HelperSpawner` | The spec never says the parent **closes its copies of the child's pipe ends** after `posix_spawn`. If it doesn't, a dead helper gives no EOF (`helperGone` never fires) and the writer blocks forever on a full pipe. R2C §4.1's close rule was written for `Process`, which r4 removed. |
| 4 | Major | §3.2 SecCode | "On-disk cdhash vs running code" written as `SecCodeCopySelf` → `SecCodeCopyStaticCode` resolves **the current file**, so the check always passes after a replacement. Verify the suspended, unreaped **child** against the designated requirement captured at launch instead. `Security` isn't linked. |
| 5 | Major | §3.2, §13, §14.2 | `SNProcess` (B, filled in step 2) holds the code-signing, start-time, stopped and path checks that A's `HelperSpawner` and self-test need in **step 1**. The shared helper prologue (close fds, signal reset, parent check, read source) has no owner file, so B, D and A each write their own. |
| 6 | Major | §3.2 step 13, §4.11, §13 | `ConnectPlanner` has no owner, constructor or trigger. `AppDelegate` (A) can't reach it, it's neither a service nor a controller, and it needs inputs from five controllers plus C's floors. The Kit `ConnectPlan` signature isn't given. |
| 7 | Major | §4.3, §4.11 | The planner re-triggers itself. Its own reconfiguration events settle after the **3 s quiet** window, which outlasts the **2.5 s** suppression, so it re-plans and burns `RateLimiter` budget. A real connect then gets rate-limited. |
| 8 | Major | A.2, [R2C §2.10] | `availability(of:context:)` is evaluated **before** services activate, so `brightnessDDC`/Req-any availability can't depend on them. Teams will either probe I/O there, or register `PrivateSymbol`s in `start()`, after availability was computed. The effective set then flaps on hot-plug. |
| 9 | Major | §3.4, §3.5, §13 | Config and page lifetime. The `DisplaysConfig` store lives per `DisplaysContext`, but General → Menu (A) and the open settings pages outlive module restarts. Two `ConfigStore`s on one key lose writes, and pages retain dead contexts. |
| 10 | Major | A.0, §3.5 | `DisplayMenuItemID` is "lead-frozen, every item", but no list exists, so every team edits `KitModules.swift` in steps 2–4. Make it an open id with contributor descriptors. |
| 11 | Major | A.1 `ToastPresenter` | `show(_:action:)` has no lifetime or expiry: "Undo" can run after the module stopped or after the state changed. The non-activating click, key-focus and level rules are unspecified. |
| 12+ | Minor | various | §6. |

**Verdict: ready with fixes.** #1, #2 and #10 are table and text edits. #3–#9 and #11 are a paragraph or snippet each, below. No new architectural rework is needed.

---

## 1. Round-3 code findings → r4 status

| r3 # | Finding | r4 status | Residue |
|---|---|---|---|
| 1 | Kit referencing app types | **Resolved** (A.0 `HotkeyCombo`, `DisplayActionID`, `MenuPlacementChoice`; `resolve(…unavailable:…)`) | `DisplayMenuItemID` is unenumerated (#10). `GlobalHotkeys.Combo = HotkeyCombo` renames r3's `modifiers` to `carbonModifiers`: say so, since A's step-1 code copies r3. |
| 2 | Undeclared/unowned types | **Mostly** | Every r3 row now has a file. New: double homes (#1), r3 Swift not normative (#2). |
| 3 | Feature→controller map | **Resolved** (§2.1 Ctl column, 21 ids, one class each) | `presets` → `LayoutsController` breaks the `<Id>Controller` naming. Put an explicit class column in `stubs.tsv` (m3). `servedFeatures` duplicates `FeatureGraph` (m4). |
| 4 | Service isolation inference | **Resolved** (§3.6, rule 14) | — |
| 5 | `unowned` context | **Resolved** (`weak`) | — |
| 6 | Writer fd ownership | **Resolved** (R3C §5.1) | With `posix_spawn` the parent-side closes are now unspecified (#3). |
| 7 | `readabilityHandler` EOF spin | **Resolved** (read source) | `HelperSpawner.spawn` must take the line and exit sinks *before* resuming (§4.1). |
| 8 | CLOEXEC across children | **Resolved** (`POSIX_SPAWN_CLOEXEC_DEFAULT` + close ≥ 3 in helpers) | Same-fd `dup2` edge if the app starts with fd 0–2 closed (m7). |
| 9 | Relaunch vs lock | **Resolved** | — |
| 10 | Menu rebuild in `menuDidClose` | **Resolved** (`menuNeedsUpdate`) | Per-status-item flags; cost bound (§4.6). |
| 11 | Hook spawn order | **Resolved** (§4.10 → R3C §5.3) | — |
| 12 | Tap stop/start race | **Resolved** (generation) | — |
| 13 | `busy` uncapped | **Resolved** (≤ 10 s, no extension while age grows) | — |
| 14 | Redeclaration hazards | **Resolved** (`SharedExtensions`, `fileprivate`, lint, lead categories) | The `EventCategory` names aren't listed (m10). |
| 15 | Stub generator | **Partial** | Create-only and not run in CI ✓. The templates, safe-return convention and TSV columns are unspecified (§3). |
| m1/m2 | `LossyMap` cap/order, `dropUnknown` | **Adopted** (§3.1) | "Sort then prefix(256)" lets junk keys that sort first evict real ones (m6). |
| m3 | One encoding normalizer | **Adopted** | `verifyClass:selector:expected:` uses `encoding:matches:` internally. Spell out its replacement (m11). |
| m4 | `nm` check | **0b** | — |
| m5 | Lint bans | **0b** | Add `Process(` and `NSTask` (no `Process` remains) and `posix_spawn(` outside `SNSpawn.m`. |
| m6 | Universal build on build-surface PRs | **0b** | The mechanism isn't given; `git diff` needs history (m14). |
| m7 | Runtime-state republish | **Adopted** (per display, 15 Hz) | API and timer mode (§4.5). |
| m8 | Auth-window poll | **Adopted** (2 Hz while dimmed) | Run it off main: `CGWindowListCopyWindowInfo` is thread-safe and costs 5–20 ms (m17). |
| m9 | Helper branches skip self-checks | **Adopted** | — |
| m10 | Id family per API | **Adopted** (A.2) | — |
| m11 | `bootsessionuuid`, panic passthrough | **Adopted** | — |
| §5.1 | `VirtualHostClient.create(initialMode: ModeRef?)` | **Resolved** (`create(spec:)`, single mode) | — |
| §5.2 | Typed classification | **Resolved** (`GuardDisplayClass`) | — |

---

## 2. Consistency: §13 × Appendix A × §2.1/§3.6 (task 2)

### 2.1 Every named type has exactly one file and owner — **no** (Blocker #1)

Swift has no header/implementation split, so a class is declared in exactly one file. A.1 and A.2 list these under a contracts file, while §13 gives them their own file:

| Type | A says | §13 says |
|---|---|---|
| `EmergencyActions`, `EventLog`, `Lifetime` | `Core/ModuleContracts.swift` (A.1 heading) | `Core/{EmergencyActions,EventLog,Lifetime}.swift` (A) |
| `ModuleContext`, `ConfigStore<T>`, `GlobalHotkeys`, `ControlCommandRegistry`, `PermissionFlow`, `Relauncher`, `HelperSpawner`, `ToastPresenter`, `HostHeartbeat` | `ModuleContracts.swift` (lead) | the same-named A files |
| `SafeModeState` | `ModuleContracts.swift` | `Core/SafeMode.swift` (A) is ambiguous |
| `DisplaysContext` | `Displays/DisplaysContracts.swift` | `Displays/DisplaysContext.swift` (both lead, still two homes) |
| `DisplayTarget` | `DisplaysContracts` (A.2) | R3C §2.2 says `DisplayActionRegistry.swift`. The plan wins, so state it. |
| `TransactionRequest`, `TransactionRisk`, `TransactionOutcome` | "App types" (A.3), no file | Implied `DisplayTransactionQueue.swift` (B), but D builds requests in step 3. Name the file. |
| `PerDisplayConfig`; the section protocol that every `*Config` conforms to | not named | Not in §13. Use `Config/ConfigDisplays.swift` and `Config/ConfigModel.swift` (lead). |
| `TrustStamp` (§9.7) | — | Not in §13; put it in `LayoutPreset` (D). |
| `HelperKind`, `HelperHandle` | A.1 bullet | Not in §13; put them in `HelperSpawner.swift` (A). |

**Fix (one rule plus the table above).** "`ModuleContracts.swift` and `DisplaysContracts.swift` contain only protocols, enums, value types and typealiases. Every class lives in its §13 file. The 0b stub of that file carries the exact A signature with safe bodies (§3.2)." With that rule:

- **`ModuleContracts`:** `SnapticModule`, `ModuleState`, `SettingsPage`, `SafeModeState`.
- **`DisplaysContracts`:**
  - the protocols: `DisplayFeatureController`, `DisplayServiceLifecycle`, `PanicParticipant`, `SessionParticipant`, `DiagnosticsContributor`, `DisplayMenuContributor`;
  - the value types: `FeatureAvailability`, `DisplayTarget`, `DisplayInfo`.

### 2.2 Appendix A lost its Swift (Major #2)

- **A.1 and A.2 are now name lists.** The real declarations (`SnapticModule` members, the `ModuleContext` init parameters, `GlobalHotkeys.register/unregister/owner`, `ControlCommandRegistry.Handler`, the `DisplaysContext` property list, `registerPanic`/`registerSession`) exist only in PLAN-r3 A.1/A.2.
- **PLAN-r3 isn't normative.** The precedence line names only R2C and R3C. A.2 says "the r3 A.2 table, with these fixes", which is a dangling normative reference.
- **Fix.** Add to the header: "PLAN-r3 Appendix A is normative where r4 A doesn't override it; r4 wins." Then write the deltas:
  - `cliAllowed:` on `ControlCommandRegistry.register`;
  - `VirtualHostClient` → `VirtualHostsService`;
  - `confirm(key:vcp:value:message:allowKey:)`;
  - the new context properties.

```swift
// DisplaysContext additions beyond r3 (names are load-bearing: 6 teams type them)
let colorSync: ColorSyncService; let monitorPanel: MonitorPanelService; let mediaKeys: MediaKeyService
let capture: CaptureService; let spawner: SpawnerService; let virtualHosts: VirtualHostsService   // was VirtualHostClient
let planner: ConnectPlanner                                                                       // #6
```

### 2.3 Every `DisplayControllerID` / `DisplayServiceID` has a class file — **yes**, with naming notes

- **Controllers:** all 21 ids have a class.
  - The only irregular one is `presets` → `LayoutsController`. Either rename the id to `layouts` or the class to `PresetsController`, or keep an explicit TSV class column.
- **Services:** §3.6 says "13 `DisplayServiceID`s" but lists **17**. All 17 have a class:
  - `registry` → `DisplayRegistry`
  - `sessionGate` → `SessionGate`
  - `guardProcess` → `DisplayGuardClient`
  - `transactions` → `DisplayTransactionQueue`
  - `appleBrightness` → `AppleBrightnessIO`
  - `ddc` → `DDCService`
  - `gamma` → `GammaService`
  - `overlays` → `OverlayService`
  - `edr` → `EDRBoost`
  - `brightness` → `BrightnessService`
  - `osd` → `OSDPresenter`
  - `colorSync` → `ColorSyncService`
  - `monitorPanel` → `MonitorPanelService`
  - `mediaKeys` → `MediaKeyService`
  - `virtualHosts` → `VirtualHostsService`
  - `capture` → `CaptureService`
  - `spawner` → `SpawnerService`

  Fix the count and put this map in `stubs.tsv`.
- `preConfirm` (`PreConfirmPresenter`) and `privateAPI` (`PrivateDisplayAPI`) are always-on context members, not service ids. Say so, so nobody adds ids for them.

### 2.4 `KitModules.swift` compiles in Kit — **yes**, with three must-dos

- **Foundation-only, no keywords.** All A.0 declarations are Foundation-only, and none of the case names is a keyword: `virtual`, `sync`, `power`, `protection`, `presets` and `layout` are all legal.
  - Lint rule 4 (top-level `package`) passes.
  - `package func L` is fine in Kit. Every app file that calls it, or names any Kit type, needs `import SnapticKit`.
- **The sketch lines aren't Swift.** `package init(keyCode:carbonModifiers:)` and `package init?(rawValue:)` have no bodies. 0b writes them.
- **`DisplayKey`: failable init plus `RawRepresentable` plus `Codable` compiles.** `RawRepresentable`'s requirement *is* `init?(rawValue:)`.
  - Whether `Codable` comes from the stdlib's `RawRepresentable where RawValue == String` default or from struct synthesis (synthesis would encode `{"rawValue":…}` and bypass validation on decode) is exactly the ambiguity [R2C §2.5] warned about.
  - Write it explicitly. Then it's correct regardless:

```swift
package struct DisplayKey: RawRepresentable, Codable, Hashable, Sendable {
    package let rawValue: String
    package init?(rawValue: String) {
        guard rawValue.utf8.count == 32, rawValue.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) })
        else { return nil }
        self.rawValue = rawValue
    }
    package init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let k = DisplayKey(rawValue: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad DisplayKey"))
        }
        self = k
    }
    package func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}
```

Witnesses for `Decodable`/`Encodable` on a `package` type must be `package` or more visible. The snippet above complies. A team copying the A.0 one-liner and adding `init(from:)` without `package` gets "must be declared package".

### 2.5 `LossyMap<DisplayKey, …>` with a failable init — **works**, with three gaps

- **It works.** `Key(rawValue:)` is already optional in `LossyMap`. Invalid keys land in `unknown` and are re-encoded.
  - For `DisplayKey` that's pointless: the format is fixed, so an invalid key never becomes valid.
  - `sanitized()` for `perDisplay` should call `dropUnknown(keepingAtMost: 0)`.
- **`Value: Codable & Equatable`.** `PerDisplayConfig`, and every nested `PerDisplay*` and `*Config`, must be `Equatable`. A.4 doesn't say so. Put it in the section protocol:
  `package protocol ConfigSection: Codable, Equatable, Sendable { init(); func sanitized() -> Self }`
  (lead, `ConfigModel.swift`).
- **`Sendable`.** `LossyMap` isn't declared `Sendable`. A `Sendable` config struct holding one gets a diagnostic, and `DDCService` reads per-display DDC config off main. Add:
  `extension LossyMap: Sendable where Key: Sendable, Value: Sendable {}`
- **UUID keys can't use `LossyMap`.** `UUID` isn't `RawRepresentable`, so these don't compile under the "keyed maps use `LossyMap`" rule:
  - `LayoutPreset.virtualScreens: [id: Bool]`;
  - virtual-screen configs keyed by spec id.

  As plain dictionaries they encode as flat arrays and throw as a whole. Add to Kit (D, `VirtualScreenSpec.swift`):
  `package struct VirtualSpecID: RawRepresentable, Codable, Hashable, Sendable { package let rawValue: String; package init?(rawValue:) /* UUID(uuidString:) != nil */ }`

---

## 3. Step 0b: executable? (task 3)

It's close, but not yet mechanical. Below are the stub kinds I would generate, then the ambiguities that would still collide.

### 3.1 `stubs.tsv` columns

`path  owner  kind  type  extra`
- `extra`:
  - the controller id or service id;
  - the page id/title/symbol;
  - for Kit config files, the struct names (`BrightnessConfig,PerDisplayBrightness`);
  - for shims, the class name.
- The generator refuses any existing path. The lint loop checks that every TSV path exists **and that every file under `Sources/` and `Tests/` appears in the TSV** (m13).

### 3.2 Kinds and templates

The safe-return convention:
- every non-Void method returns `nil`, `false`, `[]`, `.unavailable(L("Not built yet"))` or `0`;
- every `throws` method throws `StubError.notBuilt`;
- no `fatalError`.

`package enum StubError: Error { case notBuilt }` lives in `KitModules.swift`, so Kit stubs can use it too.

| Kind | Used for | Template |
|---|---|---|
| **K1 Kit logic** | GammaMath, Invariants, RateLimiter, KitArgs, … | `import Foundation` + `package enum X {}`, or `package struct X: Codable, Equatable, Sendable { package init() {} }` per TSV. Value types from A.3 / R2C §2.4 are written in full by the lead (`LayoutModel`, `GuardProtocol`, `DisplayChange`, `UndoOp`). |
| **K2 Kit config** | the 16 `Config/*.swift` files | One `package struct <Name>: ConfigSection { package init() {}; package func sanitized() -> Self { self } }` per name in `extra`. Codable is synthesized: an empty struct encodes `{}`, and teams add lossy `init(from:)` later. |
| **K3 Kit test** | one per K1/K2 | `import XCTest; @testable import SnapticKit; final class <Base>Tests: XCTestCase { func testBuilds() { XCTAssertTrue(true) } }` |
| **K4 shim pair** | the 10 shims | `include/SNx.h`: `NS_ASSUME_NONNULL_BEGIN @interface SNx : NSObject + (BOOL)isAvailable; @end NS_ASSUME_NONNULL_END`. `SNx.m`: ARC `#error` guard + `@implementation SNx + (BOOL)isAvailable { return NO; } @end`. The lead adds each `#import` to the umbrella header once. |
| **K5 host service (A)** | PermissionFlow, Relauncher, ToastPresenter, HelperSpawner, GlobalHotkeys, ControlCommandRegistry, … | `import AppKit; import SnapticKit` + `@MainActor final class X { init() {} <A.1 signatures with safe bodies> }`. Nonisolated ones (`EventLog`, `EmergencyActions`, the `HostHeartbeat` stamp) are written for real by the lead from R2C §2.3; they're too small to stub. |
| **K6 main-actor service** | Gamma, Overlay, EDR, Brightness, OSD, ColorSync, MonitorPanel, MediaKey, Capture, Spawner, VirtualHosts, Registry, SessionGate, TransactionQueue, GuardClient | `@MainActor final class X: DisplayServiceLifecycle { weak var context: DisplaysContext?; init() {}; func activate(_ context: DisplaysContext) { self.context = context }; func deactivate() { context = nil } <A.2 signatures> }` |
| **K7 nonisolated service** | DDCService, AppleBrightnessIO | `final class X: @unchecked Sendable { weak var context: DisplaysContext?; init() {} <sigs> }` + `extension X: DisplayServiceLifecycle { @MainActor func activate(_ context: DisplaysContext) { self.context = context }; @MainActor func deactivate() { context = nil } }` |
| **K8 controller** | the 21 controllers | `@MainActor final class X: DisplayFeatureController { static let id: DisplayControllerID = .<id>; init() {}; func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability { .unavailable(L("Not built yet")) }; func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {}; func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {}; func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {}; func stop() {} }`. No default for `stop`, so it's emitted explicitly. |
| **K9 menu contributor** | `*MenuItems` | `@MainActor final class X: DisplayMenuContributor { init(context: DisplaysContext) {}; func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] { [] } }`. Constructed and registered by the owning controller in `start` (state this). |
| **K10 settings page** | `*Page` | `import SwiftUI` + `struct X: View { @ObservedObject var env: DisplaysPageEnvironment; var body: some View { Text(L("<title>")) } }` (#9). The lead's `DisplaysModule.settingsPages()` emits every `SettingsPage(id:title:symbol:makeView:)` from the TSV. Pages never build themselves. |
| **K11 helper entry** | DisplayGuardMain, VirtualHostMain, CLIClient, SelfTest | `enum X { static func run(_ arguments: [String]) -> Never { exit(64) } }`. The lead edits A's `SnapticEntry.swift` once to add the dispatch table (by agreement, like `Settings.swift`). |
| **K12 AppKit object** | ConfirmPanel, OSDHUDWindow, PIPWindow, IdentifyOverlay, MenuSliderItem, DisplayMenuBlock | `@MainActor final class X: NSObject { override init() { super.init() } }`, or a SwiftUI `struct X: View` per TSV (`ArrangementCanvas`). `MenuSliderItem` (A) needs its real init signature in 0b because C and D call it in step 2. |
| **K13 nonisolated worker** | MediaKeyTap, FrameMailbox, StreamReceiver, LayoutReader | `final class X: @unchecked Sendable { init() {} }` |
| **K14 namespace** | CGConfig, IORegistryDisplays, DisplayModes, DisplayIdentity, Backup, ModifierConversion | `enum X {}` |
| **L (lead, real)** | the §13 lead list | Not generated. |

### 3.3 Remaining ambiguities that would make two teams collide

1. Double homes (#1) and r3 Swift non-normative (#2).
2. The `StubError` location and the safe-return convention. Without them, teams use `fatalError` or `nil` inconsistently, and the first `start()` traps.
3. The page constructor input and who builds the `SettingsPage` values. K10 needs a fixed `DisplaysPageEnvironment` (#9). Without it, F's shell and every page owner guess different initializers.
4. The menu contributor construction point, and the `DisplayMenuItemID` contents (#10).
5. The config section protocol name, the `PerDisplayConfig` file, and what `Config/ConfigSwitcherFeatures` holds: the switcher's `Config` is in the app's `Settings.swift`, so it's either `disabledFeatures` decoding or nothing.
6. `DisplaysContext` property names (§2.2) and the service id→class map (§2.3).
7. `ConnectPlanner` ownership (#6).
8. When `PrivateSymbol`s are registered (#8).
9. `SNProcess` owner and the helper prologue owner (#5).
10. `EventCategory` names (m10).
11. The file for the transaction app types (§2.1).
12. **Startup cross-calls into B.** A's `AppDelegate` calls B at startup step 7 (`RevertJournal.recoverAtLaunch`), even with Displays off. Give it an exact signature in A.2, for example `static func recoverAtLaunch(safeMode: SafeModeState, toast: ToastPresenter) -> JournalRecovery`. Remove startup step 13 (#6).
13. `SharedExtensions` contents: list them (`NSScreen.displayID`, `CGDirectDisplayID.isBuiltin`, `CGDirectDisplayID.vendor/model/serial`). Otherwise the first two teams that need one both write it `fileprivate`, which is legal but duplicated, or ask the lead mid-step.
14. New files after 0b: register them in `stubs.tsv` in the same PR, with an owner (m13).
15. **The `TextSanitizer` move touches two A files.** Besides deleting the `Settings.swift` copy, `Switcher/WindowManager.swift` needs `import SnapticKit`: it calls `TextSanitizer` at lines 366, 367, 443, 450 and 457. The move must carry the real implementation, not a stub.

---

## 4. New risks in the r4 designs (task 4)

### 4.1 `HelperSpawner` + `SNSpawn` (Majors #3, #5)

**ObjC shape.** It must import as `throws`. `BOOL` + `NSError**` imports as `throws`; a method returning `pid_t` with an `error:` parameter doesn't.

```objc
// include/SNSpawn.h (A)
typedef NS_OPTIONS(uint32_t, SNSpawnOptions) { SNSpawnOwnProcessGroup = 1 << 0, SNSpawnDisclaim = 1 << 1 };
@interface SNSpawn : NSObject
/// Suspended spawn. stdinFD/stdoutFD are dup2'd to 0/1 (-1 → /dev/null); 2 is /dev/null; envp is empty;
/// CLOEXEC_DEFAULT + SETSIGDEF(all) + SETSIGMASK(empty). responsibility_* are dlsym'd (rule 3); if
/// SNSpawnDisclaim is requested and the SPI is missing, fails with SNSpawnErrorDisclaimUnavailable.
+ (BOOL)spawnSuspended:(NSString *)path arguments:(NSArray<NSString *> *)argv stdinFD:(int)stdinFD
              stdoutFD:(int)stdoutFD options:(SNSpawnOptions)options pid:(pid_t *)outPID error:(NSError **)error;
+ (BOOL)isStopped:(pid_t)pid;                    // PROC_PIDTBSDINFO pbi_status == SSTOP
+ (pid_t)responsiblePIDForPID:(pid_t)pid;        // -1 if unavailable
@end
// Swift: try SNSpawn.spawnSuspended(exe, arguments: argv, stdinFD: a, stdoutFD: b, options: [.disclaim], pid: &pid)
```

**fd lifetimes (Major #3).** Every one of these must be explicit:

```swift
var req: [Int32] = [-1, -1], rep: [Int32] = [-1, -1]
guard pipe(&req) == 0 else { throw SpawnError.pipe(errno) }
guard pipe(&rep) == 0 else { close(req[0]); close(req[1]); throw SpawnError.pipe(errno) }
// Darwin has no pipe2: raise every end to >= 3 with CLOEXEC (also kills the dup2(fd, fd) edge, m7)
let f = [req[0], req[1], rep[0], rep[1]].map { fd -> Int32 in let d = fcntl(fd, F_DUPFD_CLOEXEC, 3); close(fd); return d }
let (childIn, parentOut, parentIn, childOut) = (f[0], f[1], f[2], f[3])
defer { close(childIn); close(childOut) }       // ALWAYS, success or failure: else no EOF ever reaches us
var pid: pid_t = 0
do { try SNSpawn.spawnSuspended(exe, arguments: argv, stdinFD: childIn, stdoutFD: childOut, options: [.disclaim], pid: &pid) }
catch { close(parentOut); close(parentIn); throw error }
// 1 stopped? 2 responsible == pid? 3 child code identity (4.2) — any failure: kill(pid, SIGKILL); waitpid(pid, nil, 0)
// 4 make + resume: read source (owns parentIn, closes it in its cancel handler), exit process source
// 5 writer = HelperPipeWriter(duplicating: parentOut); close(parentOut)
// 6 kill(pid, SIGCONT); then once: waitpid(pid, &st, WNOHANG)
```

**The A.1 signature can't be right as written.** `spawn(kind:args:) throws -> HelperHandle` returns *after* the read source is resumed, so a fast `ready` line has no sink. Take the sinks up front:

```swift
@MainActor final class HelperSpawner {
    enum Kind: String { case displayGuard, virtualHost, selftestChild }       // fixed in 0b
    func spawn(_ kind: Kind, arguments: [String],
               onLine: @escaping @MainActor (Data) -> Void,                    // via LineSplitter; overflow → terminate
               onExit: @escaping @MainActor (_ status: Int32) -> Void         // once, after waitpid
    ) throws -> HelperHandle
}
@MainActor final class HelperHandle {
    let pid: pid_t; let startTime: UInt64; let writer: HelperPipeWriter
    private(set) var reaped = false
    func terminate()      // SIGKILL iff !reaped && start time matches; idempotent. EOF on the reply pipe calls this.
}
```

**Two concrete failure modes if this is left unsaid:**
- **Writer blocks forever.** The writer's blocking `write` on a 64 KB-full pipe to a SIGSTOPped helper only fails once the child dies *and* nobody else holds the read end. If the parent never closed `childIn`, the parent itself holds it, so the write never fails, the writer queue blocks forever, and `close()`/`flush()` never complete.
- **Guard death goes unnoticed.** If the parent never closed `childOut`, a dead guard never produces EOF on the reply pipe. The "Guard unavailable → existing long-armed states badged" path never triggers.

**Ownership (Major #5).** The helper prologue: `signal(SIGPIPE, SIG_IGN)`, reset TERM/INT/HUP, close fds ≥ 3 except argv, parse `--parent/--protocol/--build/--journal-dir`, the parent identity check, and the stdin read source with EOF → exit.
- These are needed by B (guard, step 2), D (host, step 4) and A (self-test child, step 1). §13 has no file for them.
- **Fix:** add `Core/HelperPrologue.swift` (A, step 1, with the real code) exposing
  `static func run(_ args: [String], kind: HelperSpawner.Kind, onLine: @escaping (Data) -> Void) -> HelperArgs`.
- Move `SNProcess` to A, or have the lead write its code-signing, start-time and path functions for real in 0b. Otherwise A must fill B's shim in step 1.

### 4.2 SecCode (Major #4)

**Availability.** These are all public `Security.framework` APIs and Swift-importable on macOS 14:
- `SecCodeCopySelf`
- `SecStaticCodeCreateWithPath`
- `SecCodeCopyStaticCode`
- `SecCodeCopyDesignatedRequirement`
- `SecCodeCopyGuestWithAttributes` with `kSecGuestAttributePid`
- `SecCodeCheckValidity`
- `SecCodeCopySigningInformation`

They need no entitlement for same-uid processes, and they work under hardened runtime.

**Pitfalls:**
- `SecCode` and `SecStaticCode` are distinct Swift types. `SecCodeCopySigningInformation` takes `SecStaticCode`, so a `SecCode` must go through `SecCodeCopyStaticCode`.
- `SecCodeCopyStaticCode` resolves the code's **current on-disk path**. After an in-place update, "running cdhash" computed that way is the *new* file's, so the comparison always passes. That's the bug in §3.2 as worded.
- The shim target links only Foundation, CoreGraphics, IOKit and ColorSync. Add `.linkedFramework("Security")` in 0b (Package.swift is lead-frozen); don't rely on autolinking.

**Fix.** Capture identity at launch, and verify the **child**, whose pid can't be reused while it is suspended and unreaped:

```swift
// launch (before any helper), off main: the on-disk file is what we're running
var me: SecCode?; var meStatic: SecStaticCode?; var dr: SecRequirement?
guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
      SecCodeCopyStaticCode(me, [], &meStatic) == errSecSuccess, let meStatic,
      SecCodeCopyDesignatedRequirement(meStatic, [], &dr) == errSecSuccess, let dr else { helpersUnavailable(); return }
// Ad-hoc / linker-signed DR is `cdhash H"…"`, so a replaced bundle fails the child check below.

// after spawn, child suspended (step 3 of 4.1)
var child: SecCode?
let attrs = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
let ok = SecCodeCopyGuestWithAttributes(nil, attrs, [], &child) == errSecSuccess
      && child.map { SecCodeCheckValidity($0, [], dr) == errSecSuccess } == true
```

**The helper's parent check** uses the same pattern against the DR passed in argv: `--requirement <base64 of SecRequirementCopyData>`, which comes from the trusted parent. Re-check `getppid() == pid` **after** `SecCodeCheckValidity`. Lookup by pid is racy, and reparenting to launchd is what closes the race. Developer-ID updates pass the DR by design, and `--protocol`/`--build` then gate them.

### 4.3 `--selftest-helpers` only in debug builds (Minor m1)

- **Does the universal release build lack it?** Yes. `build-app.sh` builds with `-c release` through XCBuild, where `DEBUG` isn't defined, so the shipped binary rejects the flag through app-mode validation (exit 64). The PR job's `swift build --build-tests` does produce `.build/debug/Snaptic` (native arm64, linker-signed, **not** hardened), so the test can run there.
- **Gaps:**
  - The test never exercises the hardened, `codesign`ed, universal artifact. It misses disclaim under hardened runtime, the DR captured from a real bundle signature, and the x86_64 slice.
  - The test runs on PRs only if the step isn't gated on `push`.
- **Fix:** the self-test grants nothing (it spawns two of our own children and kills itself). Compile it unconditionally, keep it out of the help text, and run it twice: on the debug binary in the PR job, and on `build/Snaptic.app/Contents/MacOS/Snaptic` in the push job. Run it natively and with `arch -x86_64` if Rosetta is present.
- **The script contract:**
  - the self-test prints `child <pid> <startTime>` twice, flushes, then `kill(getpid(), SIGKILL)`;
  - the script runs `out=$(timeout 10 "$BIN" --selftest-helpers || true)`. Command substitution waits for EOF, so a child that inherited stdout also hangs this step, which is a free second assertion;
  - then poll `kill -0` for ≤ 3 s;
  - exit 137 from the self-test is expected.
- `--selftest-child` must go through `HelperPrologue` (4.1), or the test proves nothing about the real helpers.

### 4.4 `ConnectPlanner`, Kit vs runner (Majors #6, #7)

**Ownership:**
- Remove startup step 13. `AppDelegate` (A) can't name a Displays-internal type, and the module may be off.
- Make the planner a lead-constructed `DisplaysContext` member (`let planner: ConnectPlanner`, D's file).
- `DisplaysModule` calls `planner.run(.launch)` right after the first `apply(effective:)`.
- It subscribes to the registry, `SessionGate` and wake within the module lifetime.
- It is idle unless one of these is effective: `protection`, `presets`, `virtualScreens`, `smartHiDPI`, `autoDisconnectBuiltin`, `resolution` (persisted choice). Step 1 (visibility) is always allowed while Snaptic holds long-arm state.

**Inputs.** These come from five D controllers, plus C (floors) and B (re-enable). Use a contributor protocol so the runner doesn't reach into controller internals:

```swift
// Kit (D, ConnectPlan.swift)
package enum ConnectTrigger: String, Codable, Sendable { case launch, wake, unlock, reconfigured, sessionResume }
package struct ConnectInputs: Sendable { /* snapshot, effective, safeMode, panicLatch, kept pairs, layouts (+trust),
                                           protection desired, persisted choices, sinceWake/sinceUnlock seconds */ }
package struct ConnectPlan: Equatable, Sendable { package var steps: [ConnectStep]; package var isNoOp: Bool }
package enum ConnectPlanner { package static func build(_ inputs: ConnectInputs) -> ConnectPlan }   // pure, Linux-tested
// App (D): the runner. Kit name `ConnectPlanner` vs app file ConnectPlanner.swift → rename the Kit namespace
// `ConnectPlanning` to avoid a cross-module same-name type (legal, but `ConnectPlanner` would then need module
// qualification in D's own app file).
@MainActor protocol ConnectInputContributor: AnyObject { func contribute(to inputs: inout ConnectInputs) }  // DisplaysContracts
```

**The self-trigger (Major #7):**
- Keep sets "suppress automatic actions for 2.5 s".
- The planner coalesces until **3 s of reconfiguration quiet**, so the reconfiguration callbacks caused by its own apply always settle after the suppression has ended. Every plan therefore schedules another plan, and `RateLimiter` counts it (3 per display per 60 s). A real hot-plug 20 s later finds the per-display budget spent.
- **Fix:**
  - (a) A plan whose steps are all skip-equal is `isNoOp`: it isn't counted and isn't journaled.
  - (b) Suppression ends at "the end of the first quiet period after our last apply", not at a fixed 2.5 s.
  - (c) Add a Kit test: build(post-apply snapshot) == no-op for every step type.

### 4.5 `DisplaysRuntimeState` per-display objects (Minor m2)

- **The throttle belongs to the writer.** `@Published` can't throttle itself.
- **Lifetime.** Objects are created on first use, keyed by `DisplayKey`, and **never removed during a module run** (bounded: 64 + 8). A removed object strands views that hold it. On reconnect, the same object resumes.
- **Timer mode.** Use a `.common` timer, or menu sliders freeze during tracking.

```swift
@MainActor final class DisplaysRuntimeState { func display(_ key: DisplayKey) -> DisplayRuntime }
@MainActor final class DisplayRuntime: ObservableObject {
    @Published private(set) var brightness: Double?, contrast: Double?, volume: Double?, xdr: Double?, muted: Bool?
    func update(brightness v: Double)   // stores pending; one 66 ms .common timer per object, armed only while pending
}
```

Pages and menu sliders observe one `DisplayRuntime`, never the container.

### 4.6 Menu dirty-flag rebuild (Minor m3)

- **One flag per status item.** Shared, own-icon and quick menus are separate; `requestRebuild()` marks all of them.
- **Cost bound.** `menuNeedsUpdate` runs before `menuWillOpen`, which is good for slider sizing. Rebuild must stay ≤ 50 ms:
  - contributors read caches only (`DisplaysRuntimeState`, registry) and never do DDC/IOKit I/O;
  - implement `menuHasKeyEquivalent(_:for:target:action:) -> false`, so AppKit's key-equivalent scans don't trigger rebuilds.
- **The right-click quick-menu pattern** sets `statusItem.menu` and then `performClick`. Detaching `statusItem.menu = nil` in `menuDidClose` is fine. Removing or replacing items there is not. Keep the `NSMenu` objects strongly owned by `StatusMenu`.

### 4.7 `ToastPresenter` (Major #11)

**API:**
```swift
@MainActor final class ToastPresenter {
    func show(_ text: String, action: ToastAction? = nil, on desktopID: UInt32? = nil)
}
struct ToastAction { let title: String; let lifetime: Lifetime; let expires: TimeInterval /* ≤ 10 s */; let run: @MainActor () -> Void }
```
- The button disables itself when `lifetime.isEnded` or on expiry.
- Undo actions must be CAS (`UndoOp`): they re-snapshot, and if the state has moved they refuse with a toast. Otherwise a late "Undo" applies an old layout over a newer user change, or runs after `stop()` on a deactivated queue.

**Window:**
- an `NSPanel` with `.nonactivatingPanel`, where `canBecomeKey` returns false so Return/Esc stay with the confirm panel;
- the hosting view overrides `acceptsFirstMouse` → true, or "Undo" needs two clicks;
- level `.screenSaver + 1`, below the safety UI and OSD (`+2`), placed so it never overlaps the confirm panel;
- `sharingType = .none`.

**Behavior:**
- queue and coalesce, with at most one visible toast, and identical texts merged;
- suppressed off-console and while locked; the badge still updates;
- VoiceOver `announcementRequested`;
- it must exist before startup step 7 (journal-recovery toast).

---

## 5. Remaining Majors in detail

**#8 Availability vs activation.**
- **Rule:** `availability(of:context:)` must be computable with **every service inactive**, from static facts only:
  - OS version;
  - `PrivateDisplayAPI` probe results;
  - hardware class (`SoCCaps`, AS vs Intel);
  - the affected-models table.
- **Per-display availability** (no DDC on this monitor) is a UI/state concern inside the started controller. It never feeds `resolve(unavailable:)`, or the effective set and service activation flap on every hot-plug.
- **Registration time.** `PrivateSymbol`s are registered from static tables at module construction, not in `start()`:
  - each team declares `extension PrivateSymbol { static let … }` plus a static `[PrivateSymbolSpec]` in its own file;
  - the lead's `DisplaysModule` lists those tables (one line per team, in 0b).

**#9 Config and page lifetime.**
- **One store per key.** `ModuleHost` owns exactly one `ConfigStore` per defaults key (`SnapticModulesV1`, `SnapticDisplaysV1`) for the app's lifetime, and `DisplaysContext` borrows it.
  - Two instances on one key each debounce a full-struct write of their own copy, so the last writer silently reverts the other's edits.
  - The loop guard doesn't help across instances.
- **Page environment.** Pages get a host-lifetime environment:
  `@MainActor final class DisplaysPageEnvironment: ObservableObject { let config: ConfigStore<DisplaysConfig>; @Published private(set) var context: DisplaysContext? }`
  - It is set on start and cleared on stop.
  - Pages show "Displays is off" when `context` is nil.
  - This stops an open Settings window from keeping a stopped context, and all its services and IOKit handles, alive, and from calling into deactivated services.

**#10 `DisplayMenuItemID`.** Mirror `DisplayActionID`:

```swift
package struct DisplayMenuItemID: RawRepresentable, Codable, Hashable, Sendable { package let rawValue: String; package init(rawValue: String) { self.rawValue = rawValue } }
// team Kit file: extension DisplayMenuItemID { package static let brightnessSlider = Self(rawValue: "C.brightnessSlider") }
struct DisplayMenuItemDescriptor { let id: DisplayMenuItemID; let title: String; let defaultPlacement: MenuItemPlacement; let feature: DisplayFeature }
// DisplayMenuContributor gains: var descriptors: [DisplayMenuItemDescriptor] { get }  — General → Menu lists these
```

`LossyMap<DisplayMenuItemID, MenuItemPlacement>` keeps working: with a non-failable init, every key counts as known.

---

## 6. Minor findings

| # | Section | Finding and fix |
|---|---|---|
| m1 | §14.1 | Self-test is debug-only and never runs on the shipped artifact (§4.3). |
| m2 | §3.4 | `DisplaysRuntimeState` API, `.common` timer, objects never removed (§4.5). |
| m3 | §3.5 | Menu flags per status item; 50 ms bound; `menuHasKeyEquivalent` (§4.6). |
| m4 | A.2 | `servedFeatures` duplicates `FeatureGraph`. Make it derived (`static var servedFeatures: Set<DisplayFeature> { FeatureGraph.features(servedBy: id) }`), the one allowed protocol-extension default. Or drop it and keep only the module-construction assertion. |
| m5 | §3.6 | "13 `DisplayServiceID`s" → 17. `presets` vs `LayoutsController` naming (§2.3). |
| m6 | §3.1 `LossyMap` | Sort-then-cap lets 256 junk keys that sort first (`"!…"`) evict every real entry. Admit known keys first, up to the cap, then fill `unknown` with the remaining budget. For `DisplayKey` maps, `dropUnknown(keepingAtMost: 0)`. |
| m7 | §3.2 | If Snaptic is launched with fd 0, 1 or 2 closed, `pipe()` can return 0–2, and `dup2(fd, fd)` keeps CLOEXEC set. Either `F_DUPFD_CLOEXEC, 3` (§4.1), or `SnapticEntry` reopens any closed 0–2 on `/dev/null` first. |
| m8 | §3.2 | `responsibility_spawnattrs_setdisclaim` and `responsibility_get_pid_responsible_for_pid` are SPI: `dlsym` them in `SNSpawn.m` (rule 3). Decide the policy when they're missing. Fail-closed means no guard, so no trials anywhere. State whether that's intended. |
| m9 | §3.2 | Helpers reset SIGTERM to the default, so logout's or a user's `kill` ends a long-armed guard **without reverting**. Spawn helpers with `SNSpawnOwnProcessGroup`, so terminal and pgroup signals miss them. The guard installs a SIGTERM `DispatchSource` that runs the parent-death path, then exits. |
| m10 | §13 | "EventCategory names" are declared in `KitModules` but never listed, and R2C §2.3's open `EventLog.Category` struct still exists. Pick one: `package enum EventCategory: String, CaseIterable, Sendable { case module, switcher, displays, registry, transactions, guardProcess, journal, ddc, brightness, gamma, overlay, keys, osd, resolution, virtual, smartHiDPI, pip, automation, control, permissions }`, with `EventLog.record(_: EventCategory, _:)`. |
| m11 | §3.1 | Replace `+[SNEncoding verifyClass:selector:expected:classMethod:]`, which calls the removed `encoding:matches:`, with `+ (nullable NSString *)typeEncodingForClass:(NSString *)c selector:(NSString *)s classMethod:(BOOL)m;`. Update `SnapticEntry`'s probe call. |
| m12 | rule 15 vs A.3 | `DisplayChange`/`UndoOp` use `UInt32` display ids, and they cross processes (guard) and persist (journals). That contradicts rule 15. State the exemption: same boot, fingerprint-set-checked journal, CAS on apply. |
| m13 | §13 lint | The paths-exist check plus "every file under `Sources/` and `Tests/` is in `stubs.tsv` with an owner". Then a PR adding `Helpers.swift` in two teams' folders fails at the first PR, not on `feature/displays` after the second. |
| m14 | §14.1 | "Universal on build-surface PRs": the checkout is shallow, so `git diff origin/base...` fails. Use a second workflow with `on: pull_request: paths: [Package.swift, Sources/SnapticShims/**, scripts/**, .github/**]`; no third-party action is needed. Also commit the pending `ubuntu-24.04` change. `attest`/`release` still use `ubuntu-latest`, which migrates on Oct 19: pin them too. |
| m15 | lint | Ban `Process(`, `NSTask` and `posix_spawn(` outside `SNSpawn.m`, `waitpid(-1`, and `SecCodeCopyStaticCode(` outside the launch-identity function (§4.2). |
| m16 | §2.1 | `hdrVirtual` is served by `virtual`, but it applies to Smart HiDPI pairs too. State that it is a create-time flag read by `VirtualHostsService`, so `SmartHiDPIController` doesn't need the `virtual` controller started. |
| m17 | §4.10(10) | Run the 2 Hz `CGWindowListCopyWindowInfo` poll on a utility queue and hop the result to main. It costs 5–20 ms per call, which is up to 40 ms/s of main otherwise. |
| m18 | §13 | `MenuCustomizationPage` (A, a General page) sits under `Displays/UI/`. Move it to `Core/` next to `GeneralPages`: it's module-agnostic (one section per module, from descriptors, #10). |
