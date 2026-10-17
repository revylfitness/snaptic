# Review r3: code review, architecture and buildability

Lens: does PLAN r3 plus the cited [R2C] snippets compile, can six teams fan out from step 0b without editing each other's files, and are the new r3 mechanisms (per-screen hosts, `busy`/`classification`, hook spawn, media-key thread, PermissionFlow, menu deferral) free of crash, deadlock and leak hazards.

**Evidence beyond the plan.** Step 0a is already committed on `feature/displays` (853e18b): conditional manifest, git mv into `Core/`/`Switcher/`, `SnapticEntry`, `KitLossy`, `KitProbe`, `SNEncoding`, `lint.sh` and the new workflow. CI run 39070391729 (push) passed: `kit-linux` in 39 s, macOS in 1 m 16 s, including the universal XCBuild and the `nm` check. So the toolchain questions from r2 (Linux manifest, `package` under XCBuild, ObjC ARC guard, umbrella header) are settled empirically, and **one CI round costs about 1.5 min, not 12–20.** From here on, the risk is unspecified contracts, not CI time.

Severity: **Blocker** = won't compile as specified, or forces teams to edit each other's files at 0b. **Major** = likely crash, leak, race or wasted rounds. **Minor** = cheap fix.

---

## Ranked summary

| # | Sev | Section | One line |
|---|---|---|---|
| 1 | Blocker | A.4, §3.5, A.1, §2.1 | Kit config models must key on and store types that r3 puts in the **app** (`DisplayMenuItemID`, `GlobalHotkeys.Combo`, action ids), and Kit `FeatureGraph.resolve` takes app types (`SafeModeState`, `FeatureAvailability`). That doesn't compile, and two teams will each invent a Kit hotkey type, which is a redeclaration on merge. |
| 2 | Blocker | A.2, §13 | Cross-team types that are named but never declared or owned: `PreConfirmToken`, `OverlayKind`/`OverlayToken`, `OSDKind`, `PrivateSymbol`, `DDCReading`, `Action`/`DisplayTarget`, `DisplayChange`, all per-team config and per-display struct names, the PermissionFlow and HostHeartbeat APIs. Seven of the 19 `DisplayServiceID`s have no object. The stub generator can't emit these, so teams will edit B's, C's and the lead's files. |
| 3 | Blocker | §2.1, §3.6, §13 | There's no feature→controller map. `mainDisplay`, `mirroring`, `underscan`, `hdrToggle`, `overview`, `diagnostics`, the brightness family, `xdr`, `osd` and `osdBroadcast` have no controller, and `hooks` maps to two controllers. `servedFeatures` stubs can't be generated, and the "exclusivity" test can't run Kit-only. |
| 4 | Major | A.2, A.6 | `DisplayServiceLifecycle` is `@MainActor`. Conforming on the primary declaration infers `@MainActor` for `DDCService`/`AppleBrightnessIO`, contradicting A.6 (nonisolated). Their queue code then fails to compile, or teams "fix" it by moving I²C waits onto main. |
| 5 | Major | §3.6 | Services hold the context `unowned`. A late DDC continuation, `CallbackTarget` hop or `Task` after module stop traps. |
| 6 | Major | §3.2, [R2C §4.1] | `HelperPipeWriter` doesn't own its fd. After a host or guard is removed, queued writes go to a **recycled fd number** (the journal temp file, the CLI socket, another helper's pipe). |
| 7 | Major | §3.2, §9.3 | Reply pipes read with `readabilityHandler` spin at 100% CPU on EOF unless cleared. With 8+N hosts this is the common path. Use a read source and cancel it on EOF. |
| 8 | Major | §3.2, §4.5, §9.3 | Many children plus pipes: if any pipe fd lacks `FD_CLOEXEC`, host *k* inherits the guard's stdin write end, so the **guard never sees EOF on parent death** and never reverts. NSTask's close-all behaviour is undocumented (R2C itself says not to rely on it). |
| 9 | Major | §1.1.1 | "Relaunch Snaptic" plus the fail-closed instance lock: the new instance starts while the old one holds the lock, steps aside, and the user is left with **no Snaptic**. |
| 10 | Major | §3.5 | Rebuilding in `menuDidClose` removes the chosen item before AppKit sends its action, so the click is lost whenever a rebuild is pending. |
| 11 | Major | §4.10.1 | Hook reaping: the process source must exist before `SIGCONT`, or a fast-exiting hook's kevent registration can miss NOTE_EXIT. Then you get a zombie, and a later `killpg` hits a recycled pgid. |
| 12 | Major | §8.1, §4.9 | `MediaKeyTap` stop/start race: a stop before the new thread creates its tap is lost (`CFRunLoopStop` before `CFRunLoopRun` is a no-op). The result is a live tap swallowing keys with no owner, or two taps double-stepping. |
| 13 | Major | §4.5 | `busy(seconds)` is uncapped and renewable, so a parent that is wedged in a long CG call keeps hang detection off indefinitely. |
| 14 | Major | §13, §14.3 | Fan-out redeclaration hazards that the basename lint doesn't catch: open `EventLog.Category` constants, internal extensions on system or shared types, same-named Kit helper types. Each one turns `feature/displays` red after two green PRs. |
| 15 | Major | §14.2 0b | Stub generator: it must be create-only and must not run in the `swift:5.10-jammy` container (python3 isn't guaranteed there). Use one template per conformance kind, with no default `stop()`. |
| 16+ | Minor | various | Listed in §6. |

---

## 1. Round-2 code findings → r3 status

| r2 # | Finding | r3 status | Remaining gap |
|---|---|---|---|
| 1 | Linux `swift test` builds AppKit | **Resolved** | Implemented; Linux is green. Pin `runs-on: ubuntu-24.04`: run annotation: "ubuntu-latest will migrate to Ubuntu 26 beginning October 19, 2026". |
| 2 | Step 0 collisions, missing owners | **Mostly** | git mv is done, and `AppDelegate`/`SnapticEntry`/`Lifetime`/`L()` have files. Still no file for `SnapticModule`, `ModuleState`, `SettingsPage`, `SafeModeState`, the A.2 protocols, `DisplayInfo`, `FeatureAvailability`, `PreConfirmToken`, `PermissionFlow` (#2). `KitProbe.swift` exists but isn't in §13. |
| 3 | Helper pipe crash and hang | **Partial** | The R2C writer, SIGPIPE handling and read-end close are adopted. New: fd ownership (#6), EOF spin (#7), CLOEXEC across many children (#8). |
| 4 | Appendix A doesn't compile, APIs missing | **Partial** | A now has a signature table and `DisplayInfo`, but references undeclared types (#2) and app types from Kit (#1). `VirtualHostClient.create(initialMode: ModeRef?)` can't work: a `ModeRef` carries an `ioModeID` that doesn't exist before the display does. Use a `VirtualMode {width, height, hiDPI, refreshMilliHz}` from `VirtualScreenSpec`. |
| 5 | Service refcount vs `let` | **Partial** | Eager construction and activation refcount are adopted. Seven IDs (`colorSync`, `nightShift`, `monitorPanel`, `mediaKeys`, `capture`, `spawner`, `hotkeys`) have no `DisplaysContext` property, type or file. `unowned` brings a new crash (#5), and isolation inference (#4). |
| 6 | Multi-feature controllers | **Partial** | The R2C §2.10 protocol is adopted. The feature→controller map is missing (#3). Label drift: §3.6 says `start(context:…)`, R2C says `start(_ context:…)`; A.2 cites R2C, so R2C wins. Say so. |
| 7 | Lossy dictionaries | **Resolved** | Implemented and tested on Linux. Residual minor: see m1 and m2. |
| 8 | KVO dotted keys, config in Kit | **Resolved** | Kill-switch keys `Displays.disable.<feature>` contain dots. That's fine only because they're never observed; state that kill switches apply at module start, or poll them. |
| 9 | UndoOp CAS | **Resolved** | `DisplayChange` is still not written as Swift (r1 §2 had one; r3 A.3 lists case names only). Write it in 0b. |
| 10 | Guard protocol races | **Resolved, with residue** | The `busy` cap (#13). The `classification` payload has no type. The heartbeat *sender* (a background timer reading `HostHeartbeat`'s stamp) has no API (#2). |
| 11 | Keep re-apply may not persist | **Resolved as a test** | Appendix D 1. |
| 12 | Non-CG order, prepare/afterRevert, preConfirm | **Resolved** | `PreConfirmToken` is undefined. `PreConfirmPresenter.confirm(display: UInt32)` mints for a CG id, but `DDCService.write(to: DisplayKey)` checks a key: the token can't be validated (#2). |
| 13 | Shim BOOL/CF/headers | **Resolved** | Implemented. `SNEncoding.m` normalizes in ObjC, while §13 also lists Kit `KitEncoding` (B) doing the same. Two implementations will drift: keep one (m3). |
| 14 | Refcon use-after-free | **Resolved** | `CallbackTarget` sits in B's Platform folder, which isn't filled until step 2, but A (Carbon) and C (IOKit) need it in step 2 too. The lead must write it for real in 0b. |
| 15 | Hook signal inheritance, reaping | **Resolved, with residue** | Ordering race (#11). |
| 16 | CI triggers, Xcode pin | **Resolved** | Implemented: Xcode 16.4 pinned, push on `feature/**`. Universal runs only on push, so a PR that breaks only the universal build lands red. Run it on PRs touching `Package.swift`, `Sources/SnapticShims/**`, `scripts/**` or `.github/**` (m6). |
| 17 | Ownership | **Mostly** | Residual items are in #2 and #3. |
| 18 | Foundation on Linux | **Resolved** | Lint implemented. |
| 19 | Scope | **Declined** | Unchanged. The only mitigation is that CI rounds are cheap now. |
| c10 | MediaKeyTap restart | **Partial** | A new `Thread` per start is adopted, but the stop/start race remains (#12). |
| c12 | Menu rebuild while tracking | **Regressed** | `menuDidClose` is the wrong hook (#10). |
| c15 | `terminationHandler`/`readabilityHandler` off main; never `waitUntilExit` on main | **Dropped** | It isn't in r3. Add it to rule 5 and to the lint (m5). |
| m3, m4 | `kern.bootsessionuuid` sizing; panic swallowed while the switcher is open | **Not addressed** | Still cheap. Document m4. |

---

## 2. Snippet and Appendix A consistency (task 2)

### 2.1 Kit must not reference app types (Blocker #1)

| Reference | Problem |
|---|---|
| `Config/ConfigDisplaysMenu` (Kit, F) stores per-item visibility keyed by `DisplayMenuItemID` | `DisplayMenuItemID` is in `Sources/Snaptic/Displays/` (app). `LossyMap<DisplayMenuItemID, …>` in Kit can't see it. |
| `ConfigKeys` (C), `ConfigAutomation` (A) and the switcher persist shortcuts | `GlobalHotkeys.Combo` is an app type. C and A will each add a Kit `KeyCombo`/`HotkeyCombo`, which is a redeclaration in one module the moment both merge. |
| Shortcut bindings keyed by action | `DisplayActionRegistry.Action.id` has no Kit type. |
| `FeatureGraph.resolve(raw:killSwitches:safeMode:availability:panicLatch:)` (Kit) | `SafeModeState` and `FeatureAvailability` are app types (A.1, A.2). |
| `ModulesConfig` (Kit, A) stores the menu placement | The placement enum's only listed home is `Core/MenuPlacement.swift` (app). |
| `PresetModel` (Kit, D): `adjustments?`, `brightness?` | These are C's Kit types (`ConfigColor`), so their names must be fixed in 0b. |

Fix: 0b puts these in `KitModules.swift` (lead) and pins the signature:

```swift
// Sources/SnapticKit/KitModules.swift (lead, 0b)
package struct HotkeyCombo: Codable, Hashable, Sendable {
    package var keyCode: UInt32; package var carbonModifiers: UInt32
    package init(keyCode: UInt32, carbonModifiers: UInt32) { self.keyCode = keyCode; self.carbonModifiers = carbonModifiers }
}
package struct DisplayActionID: RawRepresentable, Codable, Hashable, Sendable {
    package let rawValue: String
    package init(rawValue: String) { self.rawValue = rawValue }
}
package enum DisplayMenuItemID: String, CaseIterable, Codable, Sendable { case brightnessSlider /* …every id… */ }
package enum MenuPlacementChoice: String, Codable, CaseIterable, Sendable { case shared, ownIcon, hidden }

// Sources/SnapticKit/FeatureGraph.swift (lead)
package static func resolve(raw: [DisplayFeature: Bool], killSwitches: Set<DisplayFeature>, safeMode: Bool,
                            unavailable: Set<DisplayFeature>, panicLatch: Bool) -> Set<DisplayFeature>
```

In the app: `typealias Combo = HotkeyCombo` inside `GlobalHotkeys`. `DisplayMenuItemID.swift` leaves the app (update §13).

### 2.2 Named but undeclared or unowned (Blocker #2)

| Type | Used by | Proposed owner and file | Note |
|---|---|---|---|
| `PreConfirmToken` | B mints, C checks | B, `PreConfirmPresenter.swift` | Unforgeable via `fileprivate init`. Bind it to key + VCP + value + expiry. Change `confirm(display: UInt32)` to take `DisplayKey`, `vcp` and `value`. |
| `OverlayKind`, `OverlayToken` | C (dim, EDR, nudge), D (`MenuBarOverlays`: strip, corners), F (`IdentifyOverlay`?) | lead, 0b, every case | Otherwise D edits C's `OverlayService`. |
| `OSDKind` | C, and D if resolution/preset OSDs exist | C, `OSDPresenter.swift`; cases fixed in 0b | |
| `PrivateSymbol` | every team (DisplayServices, CoreDisplay, OSDManager, CBBlueLightClient, CGVirtualDisplay, MPDisplay, CGS modes, responsibility_*) | open struct (below) | A closed enum in B's file serializes everyone through B. |
| `DDCReading` | C, F diagnostics | C, `DDCService.swift` | `{current: UInt16, max: UInt16}` |
| `Action`, `DisplayTarget` | all teams, menu, CLI | lead, `DisplayActionRegistry.swift` (0b) | R2C row 9 shape plus `id: DisplayActionID`. |
| `DisplayChange` | B, D, F | B, `LayoutModel.swift` | Write the exact cases (Int32 origins, `ModeRef`, `mirror(of: UInt32?)`). |
| Per-team config structs (13) and per-display structs | `ConfigDisplays.swift` (lead/F) composes them | each team's `Config*.swift`; **names fixed in A.4** | e.g. `BrightnessConfig`, `PerDisplayBrightness`… Otherwise the composer can't be written in 0b. |
| `PermissionFlow` | A (switcher), C (keys), E (Screen Recording) | A, `Core/PermissionFlow.swift` | `request(_ p: Permission, reason: String, lifetime: Lifetime)`, coalesced per permission. |
| `HostHeartbeat.mainAgeMillis()` | B (`DisplayGuardClient` heartbeat timer) | A | nonisolated, lock-protected |
| `colorSync`, `nightShift`, `monitorPanel`, `mediaKeys`, `capture`, `spawner`, `hotkeys` services | `DisplaysModule` refcount | lead | Either give each a `DisplayServiceLifecycle` type, file and context property, or delete the id and fold the work into its controller. |
| `SnapticModule`, `ModuleState`, `SettingsPage`, `SafeModeState`; `DisplayFeatureController`, `DisplayServiceLifecycle`, `PanicParticipant`, `SessionParticipant`, `DiagnosticsContributor`, `DisplayMenuContributor`, `FeatureAvailability`, `DisplayInfo` | everyone | name the files: `Core/ModuleContracts.swift` (A, written by the lead in 0b) and `Displays/DisplaysContracts.swift` (lead) | Today the generator has to guess. |

```swift
// Displays/Platform/PrivateDisplayAPI.swift (B): open id, so teams declare their own symbols in their own files
struct PrivateSymbol: RawRepresentable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
}
@MainActor final class PrivateDisplayAPI {
    func register(_ s: PrivateSymbol, killSwitch: String, probe: @escaping @MainActor () -> Bool)
    func availability(of s: PrivateSymbol) -> FeatureAvailability
}
// C's file:  extension PrivateSymbol { static let dsGetBrightness = Self(rawValue: "C.DisplayServicesGetBrightness") }

// Displays/Platform/PreConfirmPresenter.swift (B)
struct PreConfirmToken: Sendable {
    let key: DisplayKey; let vcp: UInt8; let value: UInt16?; let expiresAtUptimeNs: UInt64
    fileprivate init(key: DisplayKey, vcp: UInt8, value: UInt16?, ttlSeconds: Double) { /* … */ }
    func authorizes(_ key: DisplayKey, _ vcp: UInt8, _ value: UInt16) -> Bool {
        self.key == key && self.vcp == vcp && (self.value ?? value) == value
            && DispatchTime.now().uptimeNanoseconds < expiresAtUptimeNs
    }
}
```

### 2.3 Feature→controller map (Blocker #3)

Add a "Controller" column to §2.1, and mirror it in Kit as data, so the exclusivity test runs on Linux:

```swift
package enum DisplayControllerID: String, CaseIterable, Sendable { case resolution, arrangement, mirroring, mainDisplay, rotation, … }
package extension FeatureGraph { static func controller(of f: DisplayFeature) -> DisplayControllerID }   // total; tested
```

The app asserts once, at module construction (DEBUG and release, logging instead of trapping in release), that `type(of: c).servedFeatures == Set(DisplayFeature.allCases.filter { FeatureGraph.controller(of: $0) == c.id })`.

Unassigned today:
- `overview` and `diagnostics` (F?);
- `mainDisplay` and `mirroring` (D: `ArrangementController`?);
- `underscan` and `hdrToggle` (D: `RotationController`?);
- `brightness`, the 4 methods, `brightnessRestore`, `dimToBlack`, `nits` and `xdr`: `BrightnessService` and `EDRBoost` are services, so which *controller* serves them?
- `osd` and `osdBroadcast`;
- `hooks`, which covers both `HooksController` and `ActionsController`: split it into `hooks` and `customActions`, or have one controller.

### 2.4 Isolation inference on services (Major #4)

[R2C §2.11] makes `DisplayServiceLifecycle` `@MainActor`. `final class DDCService: DisplayServiceLifecycle, @unchecked Sendable` on the primary declaration infers `@MainActor` for the whole class (SE-0316 conformance inference; R2C §2.9 states this rule itself). Its serial-queue closures then can't touch `self`'s state. Rule: nonisolated services conform **in an extension** with explicit `@MainActor` witnesses:

```swift
final class DDCService: @unchecked Sendable { /* queue, handles, coalescing: nonisolated */ }
extension DDCService: DisplayServiceLifecycle {
    @MainActor func activate(_ context: DisplaysContext) { self.context = context; queue.async { self.openGates() } }
    @MainActor func deactivate() { queue.sync { self.closeAndReleaseHandles() } }   // bounded (< 50 ms): no I²C in close
}
```

### 2.5 `unowned` context (Major #5)

Services are owned by `DisplaysContext`, which is rebuilt per module start, while queues, `Task`s and `CallbackTarget` hops outlive `stop()`. `unowned` traps on first use after deinit. Use `weak var context: DisplaysContext?`, read on main only, and guard with `guard let context else { return }`. The same applies to `DisplaysContext.init(module:)`: the context must not hold the module strongly.

### 2.6 `DisplayKey`, `LossyMap` and the rest

- `LossyMap` decodes keys through `Key(rawValue:)`, not through `Codable`. `DisplayKey`'s 32-hex validation must therefore live in **`init?(rawValue:)`**, not only in its explicit `init(from:)`. Otherwise a malformed key becomes a live entry.
- `DisplayInfo` with `CGRect`/`CGSize` is fine: it's app-side. `DisplayModeDescriptor` (Kit) must be `Equatable` for `DisplayInfo`'s synthesis.
- `LossyMap<DisplayFeature, Bool>` requires `DisplayFeature: String`. Say so in §2.1. The 0a probe proves the shape.
- `DisplaysConfig` (Kit) referencing per-team structs is fine inside one module, but only once the names are fixed (§2.2).

---

## 3. Ownership table (task 3)

- **Two teams on one file:** none found as written. Effective conflicts come from closed enums owned by one team that others must extend: `PrivateSymbol`, `OverlayKind`, `OSDKind`, `DisplayMenuItemID`, `DisplayServiceID`. Use open structs (`PrivateSymbol`) or a lead-frozen full list (the others).
- **Basenames.** SwiftPM rejects only duplicate *Swift* filenames within one target. Our lint is stricter: per target directory, extension stripped, `.swift` + `.m`, `.h` excluded. That's correct, because `SNDDC.h`/`SNDDC.m` must not collide. No duplicates across §13. Cross-target repeats are legal but none exist anyway.
- **What the lint can't see** (Major #14): duplicate *declarations* in one module.
  - `extension EventLog.Category { static let display = … }` written by two teams.
  - Two teams adding `extension CGDirectDisplayID { var isBuiltin: Bool }` or `extension NSScreen { var displayID: UInt32 }` (every team will want this one).
  - Two Kit `package struct KeyCombo`.

  Rules:
  1. Category constants are prefixed by team area (`.bDisplay`, `.cDDC`), or the lead predeclares all of them in 0b.
  2. Extensions on types you don't own are `private`/`fileprivate`. The shared ones (`NSScreen.displayID`, `CGDirectDisplayID` helpers) are written by the lead in 0b.
  3. Lint: `grep -nE '^(package |internal |)extension (NS|CG|CF|IO|Data|String|Array|Dictionary)' Sources/Snaptic/Displays` fails outside the lead's files.
- **Stub generator** (Major #15):
  - **Create-only.** Refuse to write any path that exists. `stubs.tsv` is history after 0b; a re-run must never clobber team code.
  - **Never in the Linux container.** Python 3 isn't a documented part of `swift:5.10-jammy`. The lead runs the generator once and commits the output. CI only checks that every §13 path exists, using a bash loop over the TSV in `lint.sh`.
  - **One template per kind** (Kit value type, service, controller, contributor, page, menu items, helper entry). Each template emits every protocol requirement explicitly.
    - No protocol-extension default for `stop()`, `deactivate()` or `panicRestore()`. A silent no-op there is a safety bug.
    - Defaults are allowed only for `effectiveFeaturesDidChange` and `configDidChange`.
  - **Stub content.**
    - Controllers: `@MainActor final class X: DisplayFeatureController { init() {} … }`. They're `final`, so the `init()` requirement needs no `required`.
    - Kit stubs: `package` on every member.
    - Helper entries: `static func run(_ a: [String]) -> Never { exit(64) }`.
    - Every Kit file gets a test file with one trivial test.
- **TextSanitizer move.** 0b adds Kit `package enum TextSanitizer` while `Switcher/Settings.swift` still declares it. The app's copy silently shadows Kit's (current-module lookup wins), so B and C compile against the wrong one. The lead deletes it from `Settings.swift` in 0b (one-time edit of A's file, by agreement) or names the Kit type differently.

---

## 4. Steps 0a and 0b (task 4)

### 4.1 0a: done, one round

As built (853e18b), against the criterion:

| Criterion | File(s) | Status |
|---|---|---|
| Conditional manifest | `Package.swift` (R2C §3.2 verbatim) | ✓ |
| git mv | `Core/{AppDelegate,Permissions}.swift`, 11 files → `Switcher/` | ✓ |
| Entry | `main.swift` → `SnapticEntry.run(CommandLine.arguments)`; `Core/SnapticEntry.swift`: nonisolated enum, `MainActor.assumeIsolated` around today's body | ✓ Correct choice: a `@MainActor` `SnapticEntry` would not be callable from top-level code. |
| Kit probe | `SnapticKit/KitLossy.swift` (`AnyCodingKey`, `LossyMap`, `KeyedDecodingContainer.lossy`), `SnapticKit/KitProbe.swift` | ✓ The probe runs **unconditionally**, not `#if DEBUG`, so the release universal build exercises it. Good. |
| Shim probe | `SnapticShims/include/{SnapticShims,SNEncoding}.h`, `SNEncoding.m` (ARC `#error`, `@try`, `NS_ASSUME_NONNULL`) | ✓ |
| Tests | `Tests/SnapticKitTests/KitProbeTests.swift` | ✓ (passes on Linux, including the `JSONSerialization` cast) |
| Lint | `scripts/lint.sh` (mode 755) | ✓ |
| CI | `.github/workflows/build.yml` | ✓ Green on Linux, native and universal, via push. |

Follow-ups to fold into 0b:
1. Add `KitProbe.swift` to §13 (lead), or delete it once real Kit code exists.
2. Choose one encoding normalizer (`SNEncoding.m` or Kit `KitEncoding`), not both.
3. Pin `ubuntu-24.04`.
4. Run universal on PRs that touch the build surface.
5. Lint additions (m5).

### 4.2 0b: achievable in 3–6 rounds only if #1–#3 are settled first

With roughly 1.5-minute rounds, compile errors aren't the constraint. The constraint is that 0b must freeze contracts that r3 leaves open. The precondition list for 0b:
1. Every type in §2.2 is declared, with its file.
2. The Kit-side ids from §2.1.
3. The feature→controller column (§2.3).
4. A decision on the 7 orphan service ids.
5. Per-team config struct names.
6. `DisplayChange` written out.
7. `CallbackTarget`, `HelperPipeWriter` (corrected, §5.1) and `LineSplitter` written for real by the lead, because three teams need them in step 2.
8. The isolation rule from §2.4 stated in rule 14.

Without these, expect each team's first PR to touch lead or other-team files, and each such touch to trigger a contract change and a rebase for everyone.

---

## 5. Crash, deadlock and leak risks in the r3 designs (task 5)

### 5.1 Per-screen virtual hosts: many children (Majors #6, #7, #8)

- **fd ownership** (#6). The R2C writer takes a raw `fd` but doesn't own it. When `VirtualHostClient` drops a host, its `Pipe`/`FileHandle` deallocs and closes the fd while writer-queue blocks are still pending. The next `open()`/`socket()` reuses the number, and the queued `create`/`heartbeat` JSON is written into it. Fix: the writer **owns a dup**, and closes it on its own queue after pending writes.

```swift
final class HelperPipeWriter: @unchecked Sendable {
    private let fd: Int32; private let queue = DispatchQueue(label: "app.snaptic.helper-writer")
    private let lock = NSLock(); private var closed = false, broken = false, heartbeatQueued = false
    private let onBroken: @Sendable () -> Void
    /// Takes its own CLOEXEC duplicate; the caller closes the original right away.
    init?(duplicating original: Int32, onBroken: @escaping @Sendable () -> Void) {
        let d = fcntl(original, F_DUPFD_CLOEXEC, 3); guard d >= 0 else { return nil }
        _ = fcntl(d, F_SETNOSIGPIPE, 1); fd = d; self.onBroken = onBroken
    }
    func close() {                                   // idempotent; pending writes drain first (serial queue)
        lock.lock(); let first = !closed; closed = true; lock.unlock()
        if first { queue.async { [fd] in _ = Darwin.close(fd) } }
    }
    func flush(timeout: DispatchTimeInterval) -> Bool {   // quit path, §4.5
        let s = DispatchSemaphore(value: 0); queue.async { s.signal() }; return s.wait(timeout: .now() + timeout) == .success
    }
    // send(_:isHeartbeat:) as in R2C §4.1, but bail if `closed || broken`
}
```

- **EOF spin** (#7). `FileHandle.readabilityHandler` is called repeatedly with empty `Data` at EOF until it's set to nil: 100% CPU per dead host. Use one read source per helper:

```swift
let src = DispatchSource.makeReadSource(fileDescriptor: rfd, queue: readerQueue)
var splitter = LineSplitter()
src.setEventHandler {
    var buf = [UInt8](repeating: 0, count: 16_384)
    let n = read(rfd, &buf, buf.count)
    if n < 0 && (errno == EINTR || errno == EAGAIN) { return }
    guard n > 0, let lines = splitter.feed(Data(buf[0..<n])) else { src.cancel(); return }   // EOF, error, overflow
    for l in lines { DispatchQueue.main.async { client.handle(l) } }
}
src.setCancelHandler { Darwin.close(rfd); DispatchQueue.main.async { client.helperGone() } }   // resume pending continuations once
src.resume()
```

- **Inheritance** (#8). Each later `Process.run()` may inherit earlier pipes unless every pipe fd is `FD_CLOEXEC`. If host *k* holds the guard's stdin write end, then **parent death produces no EOF at the guard**: no revert, no long-arm undo. And if the guard holds host *k*'s write end, virtual displays survive the app.
  - Fix:
    - set `FD_CLOEXEC` on both ends of every `Pipe` before `run()`;
    - in each helper's entry, before anything else, close every fd ≥ 3 except those named in argv. Loop `fcntl(F_GETFD)` up to `getdtablesize()`, or use `proc_pidinfo(PROC_PIDLISTFDS)` via `SNProcess`, and log what was closed.
  - Add Appendix D: "kill -9 Snaptic with 2 virtual screens and an armed trial: the guard reverts and both hosts exit within 3 s".
- **Process retention.**
  - Keep each `Process` in `[UUID: HostRecord]` until its `terminationHandler` fires. Hop to main and remove it there.
  - SIGKILL only `if process.isRunning`, using `process.processIdentifier`: never a stored pid after termination.
  - Never `waitUntilExit()` on main.
  - The host count is up to 8 virtual screens plus one per Smart HiDPI display, each about 30 MB with AppKit mapped. Show it on the Safety page.
- **Recreation loop.** A host that dies on `create` (broken CGVirtualDisplay on some 27.x) is "recreated if associated or Smart HiDPI". Make recreation an automatic action under `RateLimiter` (invariant 6). After 3 failures in 60 s, stop and show "Virtual display failed to start".

### 5.2 Guard `classification` and `busy` (Major #13)

- **`busy`.**
  - Cap each window at 10 s.
  - Ignore a `busy` that would extend a window that is already open while `mainAgeMillis` keeps growing. A wedged main can't send one, but the one sent just before the wedge must not cover it forever.
  - Log windows over 5 s.
- **`classification`.**
  - Give it a type: `struct GuardDisplayClass: Codable, Equatable, Sendable { id: UInt32; transport: Transport; strong: Bool; weak: Bool }`, sent as an array. A `[UInt32: …]` dictionary encodes as a flat alternating array (UInt32 isn't `CodingKeyRepresentable`). That round-trips, but it's obscure in logs.
  - The guard treats the last classification as advisory once the parent's heartbeat is more than 3 s stale. After parent death, every host exits on EOF anyway, so `snapticVirtual` entries vanish within quiescence.

### 5.3 Hook spawn via the shim (Major #11)

Required order:
1. `posix_spawn` (`START_SUSPENDED`, `SETPGROUP` 0).
2. Responsible-pid check; on failure `kill(pid, SIGKILL)`, then `waitpid(pid, …, 0)`. That wait is bounded: a suspended child dies immediately on SIGKILL.
3. **Create and resume** `DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit)`.
4. `kill(pid, SIGCONT)`.
5. Once, right away: `waitpid(pid, &st, WNOHANG)`, to catch an exit that raced the registration.

Keep `reaped: Bool` per hook. The timeout path runs `killpg(pid, SIGTERM)`/`SIGKILL` only while `!reaped`, because a reaped leader's pgid can be recycled.

### 5.4 Media-key tap thread restart (Major #12)

A stop before the thread runs `CFRunLoopRun()` is lost, and a stop that races tap creation leaks a live tap. Use a generation counter:
- the thread runs the loop in slices and exits when its generation is stale;
- the callback passes events through when stale;
- `stop()` never waits on main.

```swift
final class MediaKeyTap: @unchecked Sendable {
    private let lock = NSLock(); private var generation: UInt64 = 0
    private func current() -> UInt64 { lock.lock(); defer { lock.unlock() }; return generation }
    func start() {
        lock.lock(); generation &+= 1; let gen = generation; lock.unlock()
        let box = CallbackTarget(self)                                   // released when the thread exits
        Thread { [self] in
            let ref = Unmanaged.passRetained(box).toOpaque()
            defer { Unmanaged<CallbackTarget<MediaKeyTap>>.fromOpaque(ref).release() }
            guard let tap = makeTap(refcon: ref) else { return }          // tap callback: if gen is stale → pass through
            let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            while current() == gen { _ = CFRunLoopRunInMode(.defaultMode, 0.25, false) }
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes); CFMachPortInvalidate(tap)
        }.start()
    }
    func stop() { lock.lock(); generation &+= 1; lock.unlock() }        // the old thread exits within 0.25 s
}
```

The §1.1.2 trust check: in the callback, on `tapDisabledBy*`, if `!AXIsProcessTrusted()` bump the generation (self-stop) and `DispatchQueue.main.async { controller.trustLost() }`. Never invalidate the port inside its own callout. `trustLost()` hands off to PermissionFlow (§5.5) to re-arm. The same applies to `HotkeyTap` on main: defer teardown with `DispatchQueue.main.async`.

### 5.5 PermissionFlow polling (Major #9, plus a minor)

- **Relaunch versus the fail-closed lock** (#9). The new instance meets the held lock and exits. Fix:

```swift
// old instance
let cfg = NSWorkspace.OpenConfiguration()
cfg.createsNewApplicationInstance = true
cfg.arguments = ["--relaunch-from", String(getpid())]
NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, err in
    DispatchQueue.main.async { if err == nil { NSApp.terminate(nil) } }
}
// new instance: if CommandLine.arguments has --relaunch-from <pid>, retry flock(LOCK_EX|LOCK_NB) every 100 ms
// for up to 10 s before failing closed. The flag only lengthens the wait; it grants nothing.
```

- **Polling.**
  - One `PermissionFlow` per `Permission` (host service), coalescing callers.
  - Bind each request to a `Lifetime`.
  - Stop on grant, on lifetime end, or after 10 min, then show "Check again".
  - Call `AXIsProcessTrustedWithOptions(prompt)` once per flow, not per tick.
  - On 27, `AXIsProcessTrusted()` can stay false until relaunch, so show "Relaunch Snaptic" after the pane has been opened, not only "after a grant".

### 5.6 Menu rebuild deferral (Major #10)

AppKit calls `menuDidClose(_:)` **before** it dispatches the selected item's action. Removing or replacing items there drops the click. That's a long-standing AppKit behaviour; verify it in the first hardware session, but the fix costs nothing either way. Use a dirty flag and rebuild in `menuNeedsUpdate`. Never mutate in `menuDidClose`:

```swift
private var dirty = true
func requestRebuild() { dirty = true }                          // also update slider values in place if open
func menuNeedsUpdate(_ menu: NSMenu) { if dirty { rebuild(menu); dirty = false } }
func menuDidClose(_ menu: NSMenu) { /* nothing structural */ }
```

Also, menu actions must capture `DisplayKey`, not `desktopID`, and re-resolve at click time: the display may have gone, and its id may have been reused, while the menu was open.

---

## 6. Minor findings

| # | Section | Finding and fix |
|---|---|---|
| m1 | A.4 | `LossyMap.unknown` is private, so `sanitized()` can't enforce "64 remembered displays" on unknown-key entries (up to 256 `PerDisplayConfig`s persist forever). Add `package mutating func dropUnknown(keepingAtMost n: Int)`. |
| m2 | KitLossy | `allKeys.prefix(256)`: `allKeys` order follows the decoder's dictionary, so which entries survive is arbitrary. Sort the keys first (cheap). |
| m3 | §13 | One encoding normalizer. Recommended: the shim returns the raw `method_getTypeEncoding` string, and Kit `KitEncoding` compares (Linux-tested). Delete `encoding:matches:boolAware:` from the shim. |
| m4 | CI | The `nm` check: `if nm … \| grep …` treats an `nm` failure as "clean". Add `test -f "$BIN"` and run `nm` into a variable first. The warnings digest ignores the universal build's log: `tee` it too. |
| m5 | lint | Mechanical bans for the R2C crash rules, scoped to `Sources/Snaptic`: `fileHandleForWriting\.write\(` and `\.write\(Data`, `readLine\(`, `waitpid\(-1`, `\.waitUntilExit\(\)`, `DispatchQueue\.main\.sync`, `static let shared` under `Displays/`, `passUnretained\(self\)` under `Displays/`. Each costs one grep and saves a review round. |
| m6 | CI | Run the universal step on PRs whose diff touches `Package.swift`, `Sources/SnapticShims/**`, `scripts/**` or `.github/**`. That's an `if:` on a `git diff --name-only origin/${{ github.base_ref }}...` output; no third-party action is needed. |
| m7 | A.2 | `DisplaysRuntimeState`: `@Published [DisplayKey: Double]` republishes every display on every 60 Hz ramp step, re-rendering every open settings page and menu slider. Throttle publishing to 15 Hz, or publish per display. |
| m8 | §1.1.6 | Auth-window detection by `CGWindowListCopyWindowInfo`: specify the trigger (poll at 1 Hz only while a dim overlay is below 1.0; the call costs 5–20 ms on main). |
| m9 | §3.2 | State that the `SnapticEntry` helper branches run **before** `MainActor.assumeIsolated` and never touch `KitProbe`/`SNEncoding`, which are app-only self-checks, wasted work in 8+N hosts. |
| m10 | §4.2 / A.2 | `PreConfirmPresenter.confirm` and `OverlayService.add` take `UInt32` (`desktopID`), but DDC and presets key on `DisplayKey`. Pick one per API family and say which id each service uses: desktop for overlay, OSD and PIP; hardware/key for DDC, gamma and DisplayServices (§5). |
| m11 | r2 m3, m4 | Still open: `sysctlbyname` sizing for `kern.bootsessionuuid`; ⌃⌥⌘⎋ swallowed while the switcher is open (document it, or let `handleKeyWhileOpen` pass that combination through). |
