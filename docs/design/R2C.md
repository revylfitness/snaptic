# Review r2: code review, architecture and buildability

Lens: will PLAN r2 compile within a few CI round-trips, can six agent teams fan out without editing each other's files, and are the process, transaction and lifetime mechanisms correct as written.

Inputs: `PLAN.md` (r2; §3, §4, §13, §14 and Appendix A in detail), `review-r1-code.md`, `macos-display-apis.md`, every file in `Sources/Snaptic/`, `Package.swift`, `scripts/build-app.sh`, `.github/workflows/*.yml`, and `Resources/Info.plist`.

**Verified from upstream sources, not from memory** (fetched over raw.githubusercontent.com):
- SwiftPM 5.10 `SwiftTestTool.swift:1163`: `let subset = testProduct.map(BuildSubset.product) ?? .allIncludingTests`. A plain `swift test` builds **every** target, including the AppKit executable and the ObjC shim.
- Swift stdlib 5.10 `Codable.swift:5695-5707`: decoding a `CodingKeyRepresentable` dictionary **throws** on the first key it can't convert and on the first value that fails.
- SwiftPM 5.10 `XCBuildSupport/PIFBuilder.swift` never passes `-package-name`. SwiftPM 6.0 does (`addCommonSwiftSettings` → `packageNameArgument`). So `package` access under `--arch arm64 --arch x86_64` (the XCBuild path) works only with Xcode 16's SwiftPM 6.x.
- SwiftPM native build passes `-fobjc-arc` on Darwin (`ClangTargetBuildDescription.swift:219`), and XCBuild sets `CLANG_ENABLE_OBJC_ARC = YES`. The `#error` ARC guard will hold.
- swift-corelibs-foundation 5.10 `Process.swift`: the parent closes its copy of the child's end of the stdin pipe, and **signal dispositions are not reset**: there's no `posix_spawnattr_setsigdefault`. Apple's NSTask is closed source, so don't rely on it either way.

Severity: **Blocker** = will not compile or go green as specified, crashes in normal use, or blocks the fan-out. **Major** = likely bug, race, leak, wasted CI rounds or a safety gap. **Minor** = a cheap fix.

---

## Ranked summary

| # | Sev | Section | One line |
|---|---|---|---|
| 1 | Blocker | §14.1, §3.1 | The Linux job can't pass. `swift test` builds `.allIncludingTests` (verified), which compiles AppKit and the ObjC shim on Linux. Use a conditional manifest. A separate package would break `package` access. |
| 2 | Blocker | §13, §14.2 step 0 | Step 0 can't be green as written. The `Core/Permissions.swift` stub collides with the existing `Sources/Snaptic/Permissions.swift` (duplicate basename) and with `enum Permissions`. `AppDelegate.swift`, `SnapticEntry`, `Lifetime`, the `L()` helper and the A.2 protocols have no file or owner. |
| 3 | Blocker | §3.2, §4.5 | The helper pipe path crashes or hangs the app. `FileHandle.write(_:)` raises an uncatchable ObjC exception on EPIPE. The guard idle-exits after 30 s while the heartbeat thread keeps writing, so a crash is likely in normal use. Two threads write lines over PIPE_BUF to one fd, so lines can interleave. Writes block on main. Helpers die of SIGPIPE when they reply after the parent has died. |
| 4 | Blocker | App. A | Appendix A doesn't compile as written: `Invariants` members lack `package`, `LayoutEntry {…}` and `static let shared;` aren't Swift, and the final classes have no `init`s. It also drops most of the r1 service API (registry, DDC, brightness, gamma, overlay, OSD, session gate, DisplayKey, DisplayInfo, FinalScope, InvariantViolation, ControlRequest/Response/Policy), so six teams will invent incompatible signatures. |
| 5 | Major | A.2 | Service refcounting contradicts `let ddc: DDCService` and the other non-optional services. There's no ServiceID or activation order. `registerPanic`/`registerSession` hold participants strongly, which creates a context↔controller cycle that leaks IOKit handles and keeps stopped controllers in panic. |
| 6 | Major | A.2 | `DisplayFeatureController` serving several features: there's no per-feature availability, no resolved/effective feature set (with kill switches and Safe Mode applied), no sub-feature toggle path, and no per-controller `Lifetime`. |
| 7 | Major | §3.4, A.4 | The claim "one bad entry drops only itself" is false (verified). With `CodingKeyRepresentable`, one unknown `DisplayFeature` key from a newer or older build wipes the whole `features` map. You need a `LossyDictionary`. |
| 8 | Major | §3.4 | KVO on `UserDefaults` with the keys `SnapticDisplays.v1` and `SnapticModules.v1` is broken, because a dot is a key-path separator. `ConfigStore` also isn't an NSObject. Config models live in the app, yet §14.4 says to unit-test them on SnapticKit only. |
| 9 | Major | A.3, §4.5 | `UndoOp` can't express re-mirror, restoring a previous mirror source, or disable. "Apply only undo ops that still differ" compares against the wrong value: it will stomp a user change. Each op needs a compare-and-swap with the expected current value. |
| 10 | Major | §4.3, §4.5 | Guard protocol: there's no ack before apply, the self-exit at 30 s races with a new `arm-trial`, `deadline`/`until` are absolute times in an unspecified clock, the heartbeat clock is unspecified (wall clock means a SIGKILL after wake), the per-state behaviour on parent death is undefined, the fixed 1 s wait isn't enough, and the guard and parent both react to "no visible display". |
| 11 | Major | §4.3 | Keep path: re-applying an *identical* config with `.permanently` after a `.forAppOnly` trial may be a no-op [U]. The kept change would then revert at quit. Add it to Appendix D as test 1b. |
| 12 | Major | §4.3, A.3 | Non-CG changes (rotation, HDR, underscan) have no defined order or settle step relative to the CG batch. Smart HiDPI (create the virtual display, then mirror) and DDC preConfirm can't be expressed as a `TransactionRequest`. |
| 13 | Major | §3.1, §1 | ObjC shim: the BOOL encoding normalization (`B` vs `c`) from r1 was dropped, so the x86_64 slice silently marks BOOL selectors unavailable. CF ownership of dlsym'd `Create`/`Copy` functions is unspecified. The single shim header owned by B serializes C, D and A behind B. |
| 14 | Major | §5, A.6 | C callback refcons are `passUnretained(self)` and then hop to main asynchronously, so a block already queued after removal is a use-after-free. Use a retained weak box. |
| 15 | Major | §4.10.1 | Hook spawn: children inherit the app's `SIG_IGN` for SIGTERM, SIGINT, SIGHUP (and SIGPIPE once added), so the timeout's SIGTERM is ignored. Use `POSIX_SPAWN_SETSIGDEF` and `SETSIGMASK`. Reap by pid through kqueue; never `waitpid(-1)`, which steals `Process` children. |
| 16 | Major | §14.1 | CI doesn't run on pushes to `feature/displays`, so semantic merge conflicts between green PRs go undetected. "Latest Xcode 16.x" isn't a pin. Universal release on every PR doubles the macOS time. |
| 17 | Major | §13, §14.2 | Ownership is inconsistent. Safe Mode is A's in §13 but B's in §14.2. F owns SafetyPage/DiagnosticsPage, but the data is B's and C's. The `<Area>` list isn't enumerated. `DisplayInfo.capabilities` is cross-team. There's no action registry for shortcuts. Several files are missing. B is the critical path. |
| 18 | Major | §3.1 | Foundation differences between Linux and macOS: `.formatted()`, `String(localized:)`, `Logger`, `URL(filePath:)` and `NSLock.withLock` are not reliably on corelibs 5.10. JSON bytes differ between corelibs and swift-foundation (macOS 15), so golden-byte tests flake. |
| 19 | Major | §0, §14 | r1 #15 (cut tiers) was explicitly rejected: "0.2 ships when every In-scope item is implemented". 47 features with no hardware testing remains the largest schedule risk. |
| 20+ | Minor | various | Listed in §8. |

---

## 1. Round-1 findings: resolved or not

| r1 # | Finding | r2 status | Evidence and remaining gap |
|---|---|---|---|
| 1 Blocker | FocusTracker restart crash | **Resolved (as a task)** | §14.2 step 1: "FocusTracker restartable, HotkeyTap.stop". The r1 fix (optional `thread`, `CFRunLoopStop`, retries through the optional) isn't copied into the plan. Hand it to team A verbatim. The same lesson applies to `MediaKeyTap`'s dedicated thread (§8.1): create a new `Thread` on every start. |
| 2 Blocker | Contracts too thin; paths disagree; duplicate basenames | **Partially** | §13 is normative and the basename lint is in §14.1. But Appendix A dropped most of the r1 §5.2 service APIs (`DisplayRegistry`, `DDCService`, `BrightnessService`, `GammaService`, `OverlayManager`, `OSDPresenter`, `SleepGate`, `DisplayKey`, `DisplayInfo`, `DisplayCapabilities`, `BrightnessMethod`, `FeatureAvailability`). Those types appear only as property types in `DisplaysContext`. See finding 4. |
| 3 Blocker | Closure-builder transaction can't be checked | **Resolved in shape** | A.3 has data `DisplayChange`, `Invariants.predict/violations/undo`. New gaps are in findings 9, 11 and 12. |
| 4 Blocker | `@MainActor emergencyRestore` on the signal path | **Resolved** | §3.3: "`EmergencyActions` (nonisolated, lock-protected) is run by the signal sources". A.1 has the class. The sketch's syntax is invalid (finding 4). |
| 5 Major | Pure logic untestable in the executable | **Resolved** | §3.1 `SnapticKit`, rule 6. The config structs are still in the app (finding 8). |
| 6 Major | Main-thread stalls freeze typing | **Resolved, with residue** | §4.9 "Main thread budget" and rule 9. CG configure on main still stalls every keystroke for 0.5–3 s while the switcher tap is on main. That's accepted, but say so in the release notes. |
| 7 Major | Apple Events entitlement | **Resolved** | Dark Mode and overrides are Deferred (§2.3). Inbound AppleScript needs no entitlement. |
| 8 Major | Guard races; posix_spawn from Swift | **Partially** | `commit-intent`, claim-by-rename and scoped diff are in §4.3–4.6, and helpers use `Process` (§3.2). New races are in finding 10, and the I/O hazards in finding 3. |
| 9 Major | ObjC shim API shape | **Partially** | §3.1: class methods with `NSError**`, `@try` never crosses, a poisoned flag. **Missing:** BOOL `B`≡`c` normalization, `NS_ASSUME_NONNULL`, and CF ownership for dlsym'd functions (finding 13). |
| 10 Major | No update path or lifetime token | **Partially** | `configDidChange` and `Lifetime` are in A.1/A.2. There's no per-controller lifetime, no reuse rule, and `track` grows without bound (findings 6 and 20). |
| 11 Major | Config: volatile values, debounce, flush, KVO loop, dictionary as array | **Partially** | §3.4 covers runtime state, the `DispatchQueue.main` debounce, flush and the data compare. The dictionary fix is wrong as stated (finding 7). KVO with dotted keys doesn't work (finding 8). |
| 12 Major | SystemHotkeys at host level; single `onChange` slot | **Resolved** | §3.2 steps 2 and 7; §3.3 host heartbeat; §3.4 Combine sink. |
| 13 Major | Callback isolation | **Mostly** | A.6. **Missing:** draining the IOKit notification iterator, and refcon lifetime (finding 14). |
| 14 Major | CI hygiene | **Partially** | §14.1 adds the basename and forbidden lints, a warnings digest and concurrency. Xcode isn't really pinned ("latest 16.x"), there's no CI on the integration branch, and the Linux commands are wrong (findings 1 and 16). |
| 15 Major | Scope; cut tiers; vertical slices | **Rejected / partially** | §0: "tiers in §14 are build order, not cut lines". Vertical slices are adopted (§13 `<Area>Page.swift`). |
| 16 Major | Protection sees our own changes | **Resolved** | §4.3 step 6, `suppressAutomaticUntil`, §9.6. |
| 17 Major | Async re-entrancy in transactions | **Resolved (statement)** | §4.3: "serialized by `DisplayTransactionQueue`. Automatic callers *drop*". Give team B the r1 §2.6 tail-task code. Also take the snapshot *inside* the serialized body, not in the caller. |
| 18 Minor | `@convention(c)` returns `Int32` | Resolved | Rule 10. |
| 19 | `CGDisplayCopyDisplayMode` nil for a new virtual display | Not mentioned | Add it to the VirtualHostClient notes. |
| 20 | Modes by ioModeID | Resolved | §5. See also Minor m10. |
| 21 | `NSSlider` in menus | Resolved | §3.5. |
| 22 | `SettingsPage` makeView is `@MainActor` | Resolved | A.1. |
| 23 | One Carbon handler | Resolved | §4.7, §8.2. |
| 24 | Carbon conflicts not detectable | Resolved | §8.2. |
| 25 | SCK `queueDepth`, drop frames | Resolved | §10. |
| 26 | Exclude own overlays from capture | Resolved | §4.10.4, §6.3. |
| 27 | Hooks via `Process` | Superseded | posix_spawn in the shim, for disclaim. Correct, but see finding 15. |
| 28 | `lstat` every path component | Resolved | §4.10.1. |
| 29 | Journal `O_EXCL`, fsync, rename | Resolved | §4.6. |
| 30 | Panic swallowed while the switcher is open | Not mentioned | Minor. Document it. |
| 31 | Gamma enforcer window flags | Resolved | §6.2. |
| 32 | `SnapticDidLaunchBefore` | Resolved | §3.4. |
| 33 | EventLog without serials | Resolved | §4.10.5. |
| 34 | CLI exit code 3 cases | Resolved | §11.4. |
| 35 | Info.plist 0.2.0 | Resolved | Step 6. |

---

## 2. Appendix A as written: compile errors and design flaws

### 2.1 Things that won't compile if copied (Blocker, part of finding 4)

Agents copy contract sketches literally. Each of these costs a round-trip for every team:

| Sketch | Problem |
|---|---|
| `package enum Invariants { static func predict(...) }` | Members default to `internal`. `package` on the enum doesn't propagate to members, so `Snaptic` can't call `Invariants.predict`. Every member of every SnapticKit type needs `package`, including stored properties (`package var`), computed properties, static funcs and the `RawRepresentable` `init(rawValue:)` witness. Write it into rule 6 as "every declaration, not just types". |
| `package struct LayoutEntry: … { id, transport, isActive, … ; package init(…) }` | Not Swift. Write the real declaration in step 0 (§2.4 below). |
| `static let shared;` in `EmergencyActions` and `EventLog` | Invalid. Use `static let shared = EmergencyActions()` plus a `private init()`. |
| `enum Category: String, Sendable { … }` | Every team needs a category, so this enum becomes a hotspot. See 2.3. |
| `@MainActor final class ModuleContext { let …; let … }` and the same for `DisplaysContext` | A class with uninitialized `let`s and no `init` is an error ("class has no initializers"). Classes get no memberwise init. |
| `EventLog.Entry`, `FinalScope`, `InvariantViolation`, `ControlRequest`, `ControlResponse`, `ControlPolicy` | Referenced but never declared. |
| `DisplayFeature.requiredPermissions` (implied by §2.1's Perm column) when `DisplayFeature` lives in SnapticKit `FeatureGraph.swift` | `Permission` is declared in the app (A.1), so SnapticKit can't see it. **Move `ModuleID` and `Permission` into SnapticKit** (`KitModules.swift`). |

### 2.2 `package` access (Major, part of finding 4)

- Tools 5.9 makes SwiftPM pass `-package-name` for the native build on both Linux 5.10 and macOS. **Under `--arch arm64 --arch x86_64` (XCBuild), SwiftPM 5.10's PIF builder does not pass it. 6.0 does** (verified). With Xcode 16 (SwiftPM 6.0/6.1) the universal build works. With an Xcode 15 image it would fail with "cannot find 'X' in scope" only in the universal step. Pin the exact Xcode (finding 16), and make the skeleton PR exercise one cross-module `package` symbol in the universal build.
- `package` doesn't cross package boundaries. **Never split SnapticKit into a separate package** to fix Linux CI (finding 1); that forces everything to `public`.
- Tests in the same package see `package` symbols without `@testable`. Good.

### 2.3 Corrected core sketches (A.1)

```swift
// Sources/SnapticKit/KitModules.swift  (lead)
package enum ModuleID: String, Codable, CaseIterable, Sendable { case windowSwitcher, displays }
package enum Permission: String, Codable, CaseIterable, Sendable { case accessibility, screenRecording }
package func L(_ s: String) -> String { s }          // rule 13, usable from Kit and the app

// Sources/Snaptic/Core/EmergencyActions.swift  (A)
final class EmergencyActions: @unchecked Sendable {
    static let shared = EmergencyActions()
    struct Token: Hashable, Sendable { fileprivate let id: UInt64 }
    private let lock = NSLock()
    private var actions: [(id: UInt64, name: String, run: @Sendable () -> Void)] = []
    private var next: UInt64 = 0
    private init() {}
    @discardableResult
    func add(_ name: String, _ run: @escaping @Sendable () -> Void) -> Token {
        lock.lock(); defer { lock.unlock() }
        next &+= 1; actions.append((next, name, run)); return Token(id: next)
    }
    func remove(_ t: Token) { lock.lock(); actions.removeAll { $0.id == t.id }; lock.unlock() }
    func runAll() { lock.lock(); let copy = actions; lock.unlock(); for a in copy.reversed() { a.run() } }
}

// Sources/Snaptic/Core/EventLog.swift  (A). The category is open, so teams declare their own constants.
final class EventLog: @unchecked Sendable {
    struct Category: RawRepresentable, Hashable, Sendable { let rawValue: String; init(rawValue: String) { self.rawValue = rawValue } }
    struct Entry: Sendable { let date: Date; let category: Category; let message: String }
    static let shared = EventLog()
    private let lock = NSLock(); private var ring: [Entry] = []; private let capacity = 500
    private init() {}
    func record(_ c: Category, _ message: String) {
        let e = Entry(date: Date(), category: c, message: String(message.prefix(512)))
        lock.lock(); ring.append(e); if ring.count > capacity { ring.removeFirst(ring.count - capacity) }; lock.unlock()
    }
    func recent(_ n: Int) -> [Entry] { lock.lock(); defer { lock.unlock() }; return Array(ring.suffix(n)) }
}
// In a team's own file:  extension EventLog.Category { static let ddc = Self(rawValue: "ddc") }

// Sources/Snaptic/Core/Lifetime.swift  (A). Bounded, can create children, and can't be revived.
@MainActor final class Lifetime {
    private(set) var isEnded = false
    private var tasks: [UInt64: Task<Void, Never>] = [:]
    private var children: [Lifetime] = []
    private var next: UInt64 = 0
    private var onEnd: [() -> Void] = []
    init() {}
    /// Starts work bound to this lifetime. The task removes itself when done, so the table can't grow without bound.
    @discardableResult
    func spawn(_ op: @escaping @MainActor () async -> Void) -> Task<Void, Never>? {
        guard !isEnded else { return nil }
        next &+= 1; let id = next
        let t = Task { @MainActor [weak self] in await op(); self?.tasks[id] = nil }
        tasks[id] = t          // runs before the task body: the body can't start until this main-actor job yields
        return t
    }
    func child() -> Lifetime {
        let c = Lifetime()
        if isEnded { c.end() } else { children.removeAll { $0.isEnded }; children.append(c) }
        return c
    }
    func onEnd(_ f: @escaping () -> Void) { if isEnded { f() } else { onEnd.append(f) } }
    func end() {
        guard !isEnded else { return }
        isEnded = true
        tasks.values.forEach { $0.cancel() }; tasks = [:]
        children.forEach { $0.end() }; children = []
        let fs = onEnd; onEnd = []; fs.reversed().forEach { $0() }
    }
}
```

Rule: **a new `Lifetime` per `start`**, never reused. `ModuleContext` and `DisplaysContext` are created per module start. Each controller gets `context.lifetime.child()`.

Hotkey registrations and panic or session participants should unregister through `lifetime.onEnd`. That removes a whole class of "stopped feature still reacts" bugs. Add `GlobalHotkeys.register(_:owner:lifetime:action:)`.

### 2.4 SnapticKit value types written out

```swift
// Sources/SnapticKit/LayoutModel.swift  (B)
package enum Transport: String, Codable, CaseIterable, Sendable { case builtin, wired, displayLink, airplay, sidecar, snapticVirtual, foreignVirtual }

package struct ModeRef: Codable, Hashable, Sendable {        // never resolve by ioModeID alone (Minor m10)
    package var ioModeID: Int32; package var pixelWidth: Int; package var pixelHeight: Int
    package var pointWidth: Int; package var refreshMilliHz: Int
    package init(ioModeID: Int32, pixelWidth: Int, pixelHeight: Int, pointWidth: Int, refreshMilliHz: Int) {
        self.ioModeID = ioModeID; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        self.pointWidth = pointWidth; self.refreshMilliHz = refreshMilliHz
    }
}

package struct LayoutEntry: Codable, Equatable, Sendable {
    package var id: UInt32
    package var fingerprint: String
    package var transport: Transport
    package var isOnline: Bool
    package var isActive: Bool
    package var mirrorOf: UInt32?
    package var x: Int32, y: Int32                 // CG origins are Int32 (CGConfigureDisplayOrigin)
    package var width: Int, height: Int            // points, after rotation
    package var rotation: Int
    package var mode: ModeRef?
    package var underscan: Double?
    package var hdrEnabled: Bool?
    package var softwareDim: Double                // 1.0 = none
    package init(id: UInt32, fingerprint: String, transport: Transport, isOnline: Bool, isActive: Bool,
                 mirrorOf: UInt32?, x: Int32, y: Int32, width: Int, height: Int, rotation: Int,
                 mode: ModeRef?, underscan: Double?, hdrEnabled: Bool?, softwareDim: Double) {
        self.id = id; self.fingerprint = fingerprint; self.transport = transport; self.isOnline = isOnline
        self.isActive = isActive; self.mirrorOf = mirrorOf; self.x = x; self.y = y; self.width = width
        self.height = height; self.rotation = rotation; self.mode = mode; self.underscan = underscan
        self.hdrEnabled = hdrEnabled; self.softwareDim = softwareDim
    }
}
package struct LayoutSnapshot: Codable, Equatable, Sendable {
    package var entries: [LayoutEntry]; package var mainID: UInt32
    package init(entries: [LayoutEntry], mainID: UInt32) { self.entries = entries; self.mainID = mainID }
}
package enum InvariantViolation: Codable, Equatable, Sendable {
    case noVisibleDisplay, noPanelHost, dimToBlackWithoutOtherVisible(UInt32), mainNotVisible(UInt32), guardNotArmed
}
package enum FinalScope: String, Codable, Sendable { case permanently, forSession }
```

The `DisplayChange` and `UndoOp` replacements are in §5.

### 2.5 `CodingKeyRepresentable` keys and the JSON shape (Major, finding 7)

- Shape: `DisplayFeature: String, CodingKeyRepresentable` and `DisplayKey: RawRepresentable<String>, CodingKeyRepresentable` both encode as JSON objects (`{"brightness":true}`). The stdlib default `codingKey`/`init?(codingKey:)` for String raw values applies, and the runtime path needs SwiftStdlib 5.6, which is macOS 12.3. That's correct.
- **Robustness is false.** Stdlib `Dictionary.init(from:)` (5.10, lines 5695–5707) does `guard let key = keyType.init(codingKey:) … else { throw DecodingError.dataCorruptedError(…"Could not convert key…") }` and then `try container.decode(Value.self…)`.
  - A config written by 0.3 with a new feature key, opened in 0.2 (or the reverse after a feature is removed), throws. With the `lossy(key, fallback)` helper, the *entire* `features` map resets to defaults: the user's opt-ins vanish, including `dimToBlack` and `disconnect`.
  - The same happens to `perDisplay` if one entry's value fails.
- Fix: one wrapper in SnapticKit, used for every keyed map:

```swift
// Sources/SnapticKit/KitLossy.swift  (A)
package struct AnyCodingKey: CodingKey {
    package var stringValue: String; package var intValue: Int? { nil }
    package init(_ s: String) { stringValue = s }
    package init?(stringValue: String) { self.stringValue = stringValue }
    package init?(intValue: Int) { return nil }
}
/// Unknown keys and undecodable values drop individually. Unknown raw entries are kept and re-encoded,
/// so a downgrade/upgrade round-trip doesn't lose them.
package struct LossyMap<Key: Hashable & RawRepresentable, Value: Codable & Equatable>: Codable, Equatable
where Key.RawValue == String {
    package var values: [Key: Value]
    private var unknown: [String: Value] = [:]
    package init(_ values: [Key: Value] = [:]) { self.values = values }
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        var v: [Key: Value] = [:]; var u: [String: Value] = [:]
        for k in c.allKeys.prefix(256) {                         // bounded
            guard let value = try? c.decode(Value.self, forKey: k) else { continue }
            if let key = Key(rawValue: k.stringValue) { v[key] = value } else { u[k.stringValue] = value }
        }
        values = v; unknown = u
    }
    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        for (k, value) in unknown where Key(rawValue: k) == nil { try c.encode(value, forKey: AnyCodingKey(k)) }
        for (k, value) in values { try c.encode(value, forKey: AnyCodingKey(k.rawValue)) }
    }
}
```

- `DisplayKey` must be in SnapticKit, because `PresetModel` and `ProtectionDiff` (team D, Kit) key on it. §13 doesn't list a file for it; put it in `Fingerprint.swift` (B). Write the `Codable` conformance explicitly as a single-value container and validate it (32 lowercase hex characters) in `init(from:)`. Don't rely on the stdlib's RawRepresentable default being picked over synthesis.
- A.5 tripwire: "canonical JSON" requires `encoder.outputFormatting = [.sortedKeys]`. Without it, dictionary order is random per process and the hash mismatches on every launch, so hooks and the CLI pause on every start.

### 2.6 `@MainActor` protocols with `AnyView` closures

`struct SettingsPage { let makeView: @MainActor () -> AnyView }` is fine in Swift 5 mode. A `ForEach`/`List` content closure inside a `View.body` inherits main-actor isolation, so calling `page.makeView()` there compiles.

Two rules:
- Never call `makeView` from `NSHostingController` construction off main.
- `SettingsPage` should be `Identifiable & Hashable` on `id` only, for `List(selection:)`. Add `static func == ` and `hash(into:)` over `id`, because closures aren't Hashable.

### 2.7 `ConfigStore<T>` generic `@Published` (Major, finding 8)

- `@MainActor final class ConfigStore<T: ConfigModel>: ObservableObject { @Published var value: T { didSet { scheduleSave() } } }` compiles. A synthesized `objectWillChange` works for generic classes, and `didSet` on `@Published` is allowed.
- **External-change KVO doesn't work as specified.**
  - `ConfigStore` isn't an NSObject, so it can't be a KVO observer.
  - Keypath KVO (`defaults.observe(\.x)`) needs an `@objc dynamic` property *named like the key*.
  - String KVO `addObserver(_:forKeyPath:)` treats `.` as a path separator. `"SnapticDisplays.v1"` observes key `SnapticDisplays`, then `v1` on its value, and never fires.
  - Fix: name the new stores without dots (`SnapticModulesV1`, `SnapticDisplaysV1`) and use a helper:

```swift
private final class DefaultsKeyObserver: NSObject, @unchecked Sendable {
    private let key: String; private let onChange: @Sendable () -> Void
    init(key: String, onChange: @escaping @Sendable () -> Void) {
        precondition(!key.contains("."), "KVO treats '.' as a key path separator")
        self.key = key; self.onChange = onChange; super.init()
        UserDefaults.standard.addObserver(self, forKeyPath: key, options: [], context: nil)
    }
    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        onChange()                                     // arbitrary thread; the closure hops to main
    }
    func invalidate() { UserDefaults.standard.removeObserver(self, forKeyPath: key) }
}
```

  - Keep the switcher on `SnapticConfig.v1` without KVO, as today (it has no tripwire fields).
- **Testability.** §14.4 says "config lossy decoding and sanitize for all stores", but A.4 puts every `*Settings` struct in the app target, and tests are SnapticKit-only. Move every config model (`DisplaysConfig`, `PerDisplayConfig`, `ModulesConfig` and every per-team `*Settings`/`PerDisplay*` struct) to `Sources/SnapticKit/Config/` with per-team basenames such as `ConfigBrightness.swift`. They're pure Codable with no AppKit, and it also forces Foundation-only types into config. Put `ConfigModel` there too. Only `ConfigStore` (UserDefaults, Combine) stays in the app.

### 2.8 Lifetime and `static let shared`

Covered in 2.3. Rule 7 is sound. Also say that `GlobalHotkeys`, `ControlCommandRegistry` and `ModuleHost` are host-lifetime instances created once by `AppDelegate`. Their Carbon `EventHandlerRef` is never removed in a `deinit`: in Swift 5 mode, touching main-actor state from the nonisolated `deinit` only warns, but it's wrong.

### 2.9 `Sendable` conformances

- **Must be `Sendable`, because they cross threads:**
  - `DisplayKey` (DDC queue);
  - `SafeModeState` (read by `DDCService`, plus emergency closures);
  - `ControlRequest`, `ControlResponse` (from the socket queue to main);
  - every guard and host protocol message;
  - `GlobalHotkeys.Combo` (done);
  - `ModeRef`.
- **Must not be `Sendable`:** `TransactionRequest` (main only, and it will hold closures, §5.3), `SettingsPage`, `DisplaysConfig` (optional).
- Mark every controller class `@MainActor` explicitly. Conforming to a `@MainActor` protocol infers isolation only when the conformance is on the primary declaration, not in an extension. Agents will put `PanicParticipant` in an extension.

### 2.10 `DisplayFeatureController` serving several features (Major, finding 6)

The A.2 protocol has `features` and one `availability`. Problems:
- The `BrightnessService` family serves `brightness`, `brightnessApple/DDC/Gamma/Overlay` and `dimToBlack`. `DisplayPowerController` serves `disconnect` and `autoDisconnectBuiltin`. `DDCControlsController` serves `ddc` and `ddcCustom`. When one served feature flips, should the module stop and restart the controller? That's r1 #10 again (flicker, destroyed virtual displays). Or rely on `configDidChange`? But `DisplaysConfig.features` is the **raw** map, not the resolved closure with requirements, kill switches, Safe Mode and availability applied. Each controller would re-resolve it differently.
- Availability is per feature (gamma unavailable on an affected M5, DDC available).

```swift
@MainActor protocol DisplayFeatureController: AnyObject {
    init()                                                     // side-effect free; the module constructs all controllers once
    static var servedFeatures: Set<DisplayFeature> { get }     // exclusive across controllers (unit test over the registered list)
    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability
    /// The first served feature became effective. `lifetime` is a child of the module lifetime; it ends right after stop().
    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>)
    /// The effective subset changed but stays non-empty. Never a restart.
    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>)
    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig)
    func stop()                                                // sync, idempotent, never shows UI
}
```

`DisplaysModule` keeps `effective = FeatureGraph.resolve(raw: config.features, killSwitches:, safeMode:, availability:)`, diffs per controller, and coalesces toggle storms the same way `ModuleHost` does.

### 2.11 Service reference counting (Major, finding 5)

A.2 says "a service is created when first needed and torn down after its last dependent stops", but `DisplaysContext` declares `let ddc: DDCService`, `let gamma: GammaService` and so on: non-optional and immutable. Both can't be true. The §2.1 "Uses" column names 19 services (appleBrightness, edr, colorsync, nightShiftShim, monitorPanel, mediaKeys, capture, spawner, control…), and only 11 are in the context. There's no service dependency order either: brightness needs ddc, gamma and overlays; transactions need the guard and the registry.

Fix: construct every service eagerly with a side-effect-free `init()`, and refcount **activation**.

```swift
// SnapticKit FeatureGraph.swift (lead): data and order, unit-tested
package enum DisplayServiceID: String, CaseIterable, Sendable {
    case registry, sessionGate, guardProcess, transactions, appleBrightness, ddc, gamma, overlays, edr,
         brightness, osd, colorSync, nightShift, monitorPanel, mediaKeys, virtualHost, capture, spawner, control
}
package enum FeatureGraph {
    package static func uses(_ f: DisplayFeature) -> Set<DisplayServiceID> { … }          // §2.1 "Uses"
    package static func dependencies(_ s: DisplayServiceID) -> Set<DisplayServiceID> { … } // e.g. transactions → [registry, guardProcess]
    package static let activationOrder: [DisplayServiceID] = [ … ]                        // topological; a test checks deps precede
    package static func requiredServices(effective: Set<DisplayFeature>) -> Set<DisplayServiceID> { … } // closure over dependencies
}

// App
@MainActor protocol DisplayServiceLifecycle: AnyObject {
    func activate(_ context: DisplaysContext)     // idempotent; the only place side effects begin
    func deactivate()                             // idempotent, sync; reverts this service's system state
}
```

`DisplaysModule.apply(effective:)` does five things in order:
1. Stop the controllers whose effective set became empty.
2. Deactivate services no longer required, in reverse `activationOrder`.
3. Activate newly required services, in `activationOrder`.
4. Start newly effective controllers.
5. Call `effectiveFeaturesDidChange` on the rest.

**Services must not hold the context strongly.** The context owns the services. Pass `unowned let context` or explicit dependencies in `activate`. Otherwise context↔service is a retain cycle that outlives `stop()` and keeps IOKit/IOAVService handles alive.

**Participant registration leaks and cycles.** `registerPanic(_ p:)` and `registerSession(_ p:)` with no unregister keep stopped controllers in the panic list (panic then calls into a stopped controller) and create context → controller → context cycles. Fix:

```swift
private struct WeakPanic { weak var value: (any PanicParticipant)? }
func registerPanic(_ p: any PanicParticipant, lifetime: Lifetime) {
    panic.append(WeakPanic(value: p))
    lifetime.onEnd { [weak self] in self?.panic.removeAll { $0.value == nil || $0.value === p } }
}
```

### 2.12 Missing contracts that every team needs in step 0 (Blocker, finding 4)

Write each of these as an exact Swift declaration in Appendix A (signatures only):

- `DisplayRegistry`: `displays`, `info(for: DisplayKey)`, `info(for id: UInt32)`, `changes` publisher, `snapshot() -> LayoutSnapshot`, `refresh()`.
- `DisplayInfo`, without the cross-team `capabilities` (C exposes `brightness.methods(for:)` instead).
- `DisplayKey`.
- `DDCService`: `write`, `read`, `capabilities`, `isAvailable`.
- `BrightnessService`: `value`, `set`, `step`, `changes`, `methods(for:)`.
- `GammaService`: `setAdjustments`, `setSoftwareBrightness`, `restoreAll`.
- `OverlayService`: `add(kind:on:) -> token`, `remove`, `removeAll`.
- `OSDPresenter`: `show(kind:value:on:)`.
- `SessionGate`: `isOpen`, `waitUntilOpen`.
- `PrivateDisplayAPI`: `availability(of: Symbol)`, `table`.
- `DisplayGuardClient`: `armTrial`, `extend`, `commitIntent`, `commit`, `disarm`, `setLong`, `isAlive`.
- `VirtualHostClient`: `create(spec) async throws -> UInt32`, `destroy`, `list`.
- `ControlRequest`, `ControlResponse`, `ControlPolicy`.
- `DisplayActionRegistry` (finding 17).
- `DisplayMenuContributor` (finding 17).
- `FeatureAvailability`.
- `DisplaysRuntimeState`: all fields up front.

---

## 3. SnapticKit on Linux with `swift:5.10` (Blocker, finding 1)

### 3.1 What fails

- `swift build --target SnapticKit` works: loading the graph with an ObjC target is fine on Linux, because `TargetSourcesBuilder` accepts `.m` everywhere and only compiling would fail.
- **`swift test` builds `.allIncludingTests`** (verified, SwiftPM 5.10 `SwiftTestTool.swift:1163`). That compiles `Snaptic` (AppKit, Carbon, ScreenCaptureKit) and `SnapticShims` (Foundation.h, ARC), and fails.
- `swift test --skip-build` after `--target` builds doesn't help: the `SnapticPackageTests` product (and on Linux the generated discovery runner) was never built.
- The hidden `swift test --test-product SnapticPackageTests` builds only that product and its dependencies. It works, but it's an undocumented flag. Keep it as a fallback only.

### 3.2 Fix: conditional manifest (recommended)

```swift
// swift-tools-version:5.9
import PackageDescription

var targets: [Target] = [
    .target(name: "SnapticKit", path: "Sources/SnapticKit"),
    .testTarget(name: "SnapticKitTests", dependencies: ["SnapticKit"], path: "Tests/SnapticKitTests"),
]
#if os(macOS)
targets += [
    .target(
        name: "SnapticShims",
        path: "Sources/SnapticShims",
        linkerSettings: [
            .linkedFramework("Foundation"), .linkedFramework("CoreGraphics"),
            .linkedFramework("IOKit"), .linkedFramework("ColorSync"),
        ]
    ),
    .executableTarget(name: "Snaptic", dependencies: ["SnapticKit", "SnapticShims"], path: "Sources/Snaptic"),
]
#endif

let package = Package(name: "Snaptic", platforms: [.macOS(.v14)], targets: targets)
```

- The manifest is compiled for the host, so `#if os(macOS)` is evaluated on the CI machine. On Linux the package has two targets, and plain `swift build --build-tests && swift test --skip-build` works.
- `package` access is unaffected (one package).
- The forbidden-pattern lint must allow the `#if os(macOS)` in `Package.swift` and still ban `#if arch`.
- XCTest discovery on Linux 5.10 is automatic: no `LinuxMain.swift`, and test classes must subclass `XCTestCase`. Avoid `XCTAttachment`, `XCTExpectFailure` and `XCTContext`, which aren't in Linux XCTest.
- Fuzz tests must use a **seeded** PRNG (a SplitMix64 written in the test file) so a Linux failure can be reproduced on macOS.

Linux job:

```yaml
linux:
  runs-on: ubuntu-latest
  container: swift:5.10-jammy
  steps:
    - uses: actions/checkout@<sha>
      with: { persist-credentials: false }
    - run: ./scripts/lint.sh            # basenames (per target dir), forbidden patterns, no-network
    - run: swift build --build-tests 2>&1 | tee build.log
    - run: swift test --skip-build --parallel
```

### 3.3 Foundation-only constraints (Major, finding 18)

- **OK on Linux 5.10:** `Data`, `JSONEncoder`/`JSONDecoder` (including `.sortedKeys`), `JSONSerialization`, `UUID`, `Date`, `CharacterSet`, `Scanner`, `NSRegularExpression`, Swift `Regex`, `ProcessInfo`, `Codable` synthesis for enums with associated values (SE-0295).
- **Not available or unreliable on corelibs 5.10:** `.formatted()` and `FormatStyle`, `String(localized:)`, `os`/`Logger`, `OSAllocatedUnfairLock`, `URL(filePath:)`/`appending(path:)`, `NSLock.withLock`, `AttributedString` niceties, `Bundle.module`. Agents reach for `.formatted()` constantly. Add them to the forbidden-pattern lint for `Sources/SnapticKit/` only.
- **No CryptoKit or CoreGraphics:** correct. `edidHash` and `DisplayKey` are computed in the app; Kit only stores strings.
- **JSON bytes differ:** macOS 15's `JSONEncoder` is swift-foundation, Linux 5.10's is corelibs. Float formatting, escaping of `/`, and key order without `.sortedKeys` can differ. Tests must compare **decoded values**, never encoded bytes. Golden files go through decode.
- **Swift version skew:** Linux runs the 5.10 compiler, macOS runs 6.0/6.1 in Swift 5 mode. Add a rule: no Swift 6.0-only syntax (typed `throws(E)`, `sending`, `@isolated(any)`, noncopyable generics). Otherwise Linux fails on code macOS accepts, or worse, Linux is the only job that catches it after the agent "fixed" macOS.

---

## 4. Process model (Blocker finding 3, Major findings 10 and 15)

### 4.1 `Process` for helpers, `posix_spawn` with disclaim for hooks

This split is right: `Process` can't disclaim responsibility. Fixes needed:

1. **Close the parent's copy of the child's stdin end and verify it.** corelibs does it (`Process.swift:690`). NSTask is undocumented. If the parent keeps the read end open, a dead guard never produces EPIPE: writes fill the 64 KB pipe and then **block forever**, on main if written there. After `run()`, call `try? pipe.fileHandleForReading.close()` (idempotent through `try?`).
2. **Never use `FileHandle.write(_ data:)`.** It raises `NSFileHandleOperationException` on EPIPE or EBADF. That's an ObjC exception through Swift, which crashes the app. Use `try handle.write(contentsOf:)` or raw `write(2)` on a dedicated serial queue:

```swift
/// One writer per helper. Never blocks main; heartbeats coalesce; EPIPE → `onBroken` once, on main.
final class HelperPipeWriter: @unchecked Sendable {
    private let fd: Int32
    private let queue = DispatchQueue(label: "app.snaptic.helper-writer")
    private let lock = NSLock()
    private var broken = false, heartbeatQueued = false
    private let onBroken: @Sendable () -> Void
    init(fd: Int32, onBroken: @escaping @Sendable () -> Void) {
        self.fd = fd; self.onBroken = onBroken
        _ = fcntl(fd, F_SETNOSIGPIPE, 1)
    }
    func send(_ line: Data, isHeartbeat: Bool = false) {
        lock.lock()
        if broken || (isHeartbeat && heartbeatQueued) { lock.unlock(); return }
        if isHeartbeat { heartbeatQueued = true }
        lock.unlock()
        queue.async { [self] in
            if isHeartbeat { lock.lock(); heartbeatQueued = false; lock.unlock() }
            let ok = line.withUnsafeBytes { raw -> Bool in
                guard let base = raw.baseAddress else { return true }
                var off = 0
                while off < raw.count {
                    let n = Darwin.write(fd, base + off, raw.count - off)
                    if n > 0 { off += n } else if n < 0 && errno == EINTR { continue } else { return false }
                }
                return true
            }
            if !ok {
                lock.lock(); let first = !broken; broken = true; lock.unlock()
                if first { DispatchQueue.main.async(execute: onBroken) }
            }
        }
    }
}
```

   With one writer queue, a 64 KB `arm-trial` can't be interleaved with a heartbeat. Two threads each calling `write()` with more than `PIPE_BUF` (512 bytes) can interleave, and §4.5 has exactly that: messages from main and a background heartbeat thread.
3. **SIGPIPE everywhere:**
   - **Helpers:** the first line of every helper entry is `signal(SIGPIPE, SIG_IGN)`. The guard replies on stdout. If it writes `reverted` after the parent has died, SIGPIPE kills it **in the middle of the revert**.
   - **App:** `signal(SIGPIPE, SIG_IGN)` at startup, plus `SO_NOSIGPIPE` on every accepted CLI socket. A CLI client that disconnects while Snaptic writes the reply otherwise kills Snaptic, along with the user's ⌘⇥ state and gamma.
4. **Inherited signal dispositions.** The app does `signal(SIGTERM/SIGINT/SIGHUP, SIG_IGN)` (AppDelegate). Ignored dispositions survive `exec`.
   - Helpers spawned with `Process` start with SIGTERM ignored (corelibs doesn't reset; NSTask is unknown). So `Process.terminate()` doesn't stop the virtual host. Helper entry: reset with `signal(SIGTERM, SIG_DFL)` and the same for SIGINT and SIGHUP, then install its own handling.
   - Hooks (shim): `posix_spawnattr_setsigdefault` with a full set and `posix_spawnattr_setsigmask` with an empty set, flags `POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT`. Otherwise the 30 s timeout's SIGTERM is ignored and every hook waits the full 2 s for SIGKILL.
5. **Reaping hooks.** Use `DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit)` plus `waitpid(pid, &st, WNOHANG)`. **Never `waitpid(-1)`**: it reaps `Process`'s children and their `terminationHandler` never fires. Only send SIGTERM or SIGKILL to a pid you haven't reaped yet (pid reuse).
6. **Empty environment.** With `environment = [:]` the helper has no `HOME`. Compute the journal directory with `getpwuid_r(getuid())`, not `NSHomeDirectory()` or `FileManager` (both behave differently with no `HOME`). Or pass `--journal-dir` in argv, which comes from a trusted parent.
7. **The parent check.** `proc_pidpath` lives in `<libproc.h>`. Its Swift import with the `PROC_PIDPATHINFO_MAXSIZE` macro is untested here, so put `+[SNProcess pathForPID:]` in the shim. Compare `realpath` of both sides: App Translocation and symlinks otherwise make the comparison fail and exit(64).
8. **Version handshake.** If the user replaces `/Applications/Snaptic.app` while it runs, a respawned guard is the *new* binary with possibly a different protocol. Pass `--protocol <N>`. The child exits 65 on mismatch, and the parent disables trial features with "Restart Snaptic to finish updating".
9. **Process names.** Helpers show up as "Snaptic" in Activity Monitor, and `killall -9 Snaptic` kills the guard together with the app. Journal recovery covers this; document it.

### 4.2 Helper modes in the same executable, AppKit linked but not initialized

OK. Linking AppKit runs its loaders but doesn't connect to WindowServer as an app. CG calls (`CGGetActiveDisplayList`, `CGBeginDisplayConfiguration`) open a CGS connection without NSApplication, as displayplacer and go-macos show.

Rules for helper code:
- No `NSScreen`, `NSWorkspace`, `NSApp`, `UserDefaults` or `DisplayRegistry`. The guard needs a **nonisolated CG-only layout reader**, `LayoutReader.swift` (B, Platform). It isn't in §13; add it. It must also classify transports without the parent's runtime state (vendor 0x5354 means ours).
- `MonitorPanel` (`MPDisplay`) inside a non-GUI helper is [U]. Add it to Appendix D. Until then, mark rotation, underscan and HDR as not guard-revertable when the shim's `MPDisplay` init fails in the helper. The guard reports that in `ready{capabilities}`, and the parent then refuses those trials when it can't arm.

### 4.3 CFRunLoop in the guard plus a stdin reader

- The main thread runs `CFRunLoopRun()` (or `dispatchMain()`) inside `MainActor.assumeIsolated`. `CGDisplayRegisterReconfigurationCallback` is delivered on that run loop. The main dispatch queue is drained by it too.
- **Never `readLine()`, and never `FileHandle.availableData` on main.** Both block the run loop, so reconfiguration callbacks and timers starve, and `readLine` has no length bound.
- Use `DispatchSource.makeReadSource(fileDescriptor: 0, queue: readerQueue)` with `O_NONBLOCK`, a framing splitter (64 KB cap; exit on overflow), then `DispatchQueue.main.async { handle(msg) }`. EOF (`read == 0`) means parent death.
- Put the splitter in SnapticKit and test it on Linux:

```swift
package struct LineSplitter: Sendable {
    package static let maxLine = 64 * 1024
    private var buffer = Data()
    package init() {}
    /// Returns complete lines (without "\n"). Returns nil on overflow; the caller must treat that as a fatal protocol error.
    package mutating func feed(_ chunk: Data) -> [Data]? {
        buffer.append(chunk)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer[buffer.startIndex..<nl]); buffer.removeSubrange(buffer.startIndex...nl)
        }
        return buffer.count > Self.maxLine ? nil : lines
    }
}
```

### 4.4 JSON-lines protocols

Make them typed enums in SnapticKit, with an `id` on every request and reply. The virtual host pipelines `create` and `destroy`, so replies need correlation. `Equatable` makes the Linux round-trip tests trivial.

```swift
package enum GuardMessage: Codable, Equatable, Sendable {
    case hello(protocolVersion: Int)
    case armTrial(id: UInt64, undo: [UndoOp], deadlineSeconds: Double)   // relative: no clock domain across processes
    case extend(id: UInt64, seconds: Double)
    case commitIntent(id: UInt64)
    case commit(id: UInt64)
    case disarm(id: UInt64)
    case long(undo: [UndoOp], restoreColorSync: Bool)
    case heartbeat(mainAgeMillis: UInt64)                               // age, not a timestamp
    case shutdown                                                       // parent-driven exit (§5.2)
}
package enum GuardReply: Codable, Equatable, Sendable {
    case ready(protocolVersion: Int, canMonitorPanel: Bool)
    case ack(id: UInt64)
    case reverted(trial: UInt64?, applied: Int, skipped: Int)
    case failed(String)
}
```

The parent reads replies with `readabilityHandler` on a background queue, then hops to main. On EOF, every pending reply continuation is resumed with `.helperGone`, exactly once (rule 11).

### 4.5 Heartbeat from a background thread reading a main-thread stamp

- **The clock must be `DispatchTime.now().uptimeNanoseconds` (mach_absolute_time) on both sides.** It pauses during system sleep. If anyone uses `Date()`, the first heartbeat after an 8-hour sleep reads as 8 hours stale. The guard then applies the long undo and, with dim-to-black active, **SIGKILLs the app on wake**.
- Send `mainAgeMillis = now − stamp`, computed by the sender. The guard keeps two things:
  - `lastAge`;
  - its own `lastHeartbeatReceivedAt`, so heartbeats that *stop arriving* (process stopped, writer starved) also count as a hang.
- The stamp is written by the 0.5 s `.common` host timer and read by the heartbeat thread. Use an `NSLock` or `OSAllocatedUnfairLock<UInt64>`. A plain `var` is a data race.
- Pair `ProcessInfo.beginActivity` with `endActivity` (store the token) when long-armed ends. A leaked token disables App Nap for the session.

---

## 5. Transactions (A.3) and the guard protocol (§4.5)

### 5.1 `UndoOp` and "apply only undo ops that still differ" (Major, finding 9)

**Missing cases.** `Invariants.undo` must produce an undo for every `DisplayChange`:

| Change | Undo needed | Exists? |
|---|---|---|
| `.enabled(id, false)` | re-enable | yes |
| `.enabled(id, true)` (reconnect is a trial in §4.3) | disable | **no** |
| `.mirror(a, of: b)` when `a` mirrored nothing | unmirror | yes |
| `.mirror(a, of: b)` when `a` mirrored `c` | re-mirror to `c` | **no** |
| `.mirror(a, of: nil)` (stop mirroring, a trial) | re-mirror to the previous source | **no** |
| `.main(x)` | `setMain(previous)` | yes |

**Wrong comparison.** "Still differs from the undo target" reverts *anything* that isn't the old value, including a value the user set in System Settings while the panel was up, or a value WindowServer's `.forAppOnly` revert landed on that isn't the snapshot (snapped origins). The correct rule is **compare-and-swap**: revert only if the live value equals what *we applied*.

```swift
package enum DisplayProperty: String, Codable, Sendable { case enabled, mirrorOf, mode, origin, main, rotation, underscan, hdr }
package enum PropertyValue: Codable, Equatable, Sendable {
    case bool(Bool), display(UInt32?), mode(ModeRef), point(x: Int32, y: Int32), degrees(Int), fraction(Double)
}
package struct UndoOp: Codable, Equatable, Sendable {
    package var displayID: UInt32
    package var fingerprint: String          // re-resolve the id if the display was replugged
    package var property: DisplayProperty
    package var restore: PropertyValue       // the value to put back
    package var expected: PropertyValue      // the value the transaction applied; revert only if live == expected
    package init(displayID: UInt32, fingerprint: String, property: DisplayProperty, restore: PropertyValue, expected: PropertyValue) {
        self.displayID = displayID; self.fingerprint = fingerprint; self.property = property
        self.restore = restore; self.expected = expected
    }
    /// §4.6 safe directions: enabling, un-mirroring and restoring ColorSync only.
    package var isSafeDirection: Bool {
        switch (property, restore) {
        case (.enabled, .bool(true)), (.mirrorOf, .display(nil)): return true
        default: return false
        }
    }
}
package enum UndoPlanner {
    package static func undo(for changes: [DisplayChange], before: LayoutSnapshot) -> [UndoOp]      // from the request, not a diff
    package static func pending(_ ops: [UndoOp], live: LayoutSnapshot) -> [UndoOp]                  // CAS filter
    package static func order(_ ops: [UndoOp]) -> [UndoOp]                                          // §5.4 reverse order
}
```

Derive the undo from the **request plus the before-snapshot**, not by diffing before against after. The after state contains WindowServer re-snapping of *other* displays' origins, which would turn into spurious `restoreOrigin` ops. `restoreColorSync` moves to the `long` message as a flag (it isn't per display).

### 5.2 Races and ordering (Major, finding 10)

1. **Arm without ack.** §4.3 step 3 sends `arm-trial` and step 4 applies, with no acknowledgement. If the guard isn't running yet (it's spawned on demand), crashed, or is the wrong version, the change goes out unprotected. Fix: send `arm-trial`, await `ack{id}` (timeout 1 s), and only then apply. No ack means refuse the trial ("Safety helper unavailable"). Fail closed.
2. **Guard self-exit races a new arm.** "Exits … 30 s after its last trial if not long-armed" while the parent can send `arm-trial` at 29.99 s. The message lands in a pipe whose reader is exiting, and the write may still succeed into the buffer. With the current I/O design this also feeds the EPIPE crash. Fix: **the parent alone decides the guard's lifetime** (`shutdown` or closing stdin). The guard never exits on its own except on EOF or a protocol error.
3. **Clock domains.** `deadline` and `until` are absolute times with no clock named. Send relative seconds; the guard computes a mach-time deadline. Wall-clock jumps from NTP or a manual change otherwise fire or suppress reverts.
4. **Parent death, per trial state** (undefined today):
   - `armed`: wait for quiescence, then revert with the CAS filter.
   - `committing` (after `commit-intent`): **do nothing**. The user pressed Keep. WindowServer's `.forAppOnly` revert may undo it anyway, and that's acceptable; the guard must not fight it.
   - `committed`: nothing.
   - The long set: re-enable and un-mirror with CAS.
5. **The fixed 1 s wait is too short.** A multi-display `.forAppOnly` revert re-modesets each display (0.5–3 s each, research §3). Reading the layout mid-revert and applying ops fights WindowServer. The guard already registers the reconfiguration callback, so wait for **quiescence** (no callback for 1.5 s, cap 8 s), then read.
6. **Both processes react to "no visible display".** The healthy parent (auto-disconnect re-enable, §9.6) and the guard both run `CGBeginDisplayConfiguration` on the same reconfiguration. That's two processes configuring at once, which flaps. Fix: the guard acts on no-visible only if the parent's heartbeat age is over 3 s, **or** the condition persists 5 s after debounce.
7. **The journal claim leaves orphans.** If a guard crashes after `rename(journal.json → journal.claimed.<pid>.json)`, the next launch never sees `journal.json`. Fix: at launch, also scan `journal.claimed.*.json`. If the pid is dead (`kill(pid, 0) == ESRCH`) or isn't a Snaptic helper, re-claim it by renaming to your own pid.
8. **The quit path.** `applicationWillTerminate` → `stop()` resolves as Revert, then `disarm`. The writer queue must be **flushed synchronously** (`queue.sync {}` with a 500 ms cap) before exit. Otherwise the guard sees EOF while armed and reverts a second time. That's harmless with CAS, but it shows the "restored after unexpected exit" notification.
9. **A user request while a confirm is pending.** "Automatic callers drop" is good. A *user* request queues behind a 15 s panel and then applies by surprise. Refuse it with "Keep or revert the pending change first", or have the queue resolve the pending trial as Revert and then run the new one.

### 5.3 `trialScope` and the Keep re-apply (Major, finding 11)

- The trial applies with `.forAppOnly`. On Keep, the same mode is re-applied with `.permanently`. **Whether `CGCompleteDisplayConfiguration` records a permanent configuration when nothing actually changes is [U].** If it short-circuits, the app-only revert record stays, and the user's kept resolution **reverts when Snaptic quits**. That's silent, and only found on hardware.
- Mitigation in code: after the Keep re-apply, nothing can verify persistence until quit, so make Appendix D test 1b explicit: "trial, Keep, quit Snaptic normally; the change must persist". Keep `trialScope` as the one-line switch to `.forSession` (which has no app-only record) as the fallback if 1b fails.
- The same question applies to disable (`.forAppOnly` trial → `.forSession` final).
- The guard's own reverts must use `.forSession`, never `.forAppOnly`, because the guard exits right after. §4.5 doesn't say this (§4.6 says it only for journal recovery).

### 5.4 Non-CG changes: prediction, apply, revert (Major, finding 12)

| Change | Predict | Apply | Revert |
|---|---|---|---|
| rotation | swap width/height for 90/270 | MPDisplay `setOrientation:`, then async poll of `CGDisplayRotation` (≤ 10 s) | `restore: .degrees` via the shim (app or guard) |
| HDR | none (layout) | MPDisplay `setPreferHDRModes:`, which re-modesets (1–3 s black) | same, via the shim |
| underscan | none | MPDisplay | same |

Required ordering within one transaction:
1. **HDR**, then wait for quiescence and re-read the modes (the HDR mode list differs).
2. **Rotation**, then poll and wait for quiescence, then re-read the modes (rotated modes swap dimensions; ioModeIDs may differ).
3. **Re-resolve every `ModeRef`** against the fresh list. If any no longer resolves, revert steps 1–2 and fail.
4. **The CG batch** (mode, origin, mirror, enabled, main) in one Begin/Complete.

Undo runs in reverse: CG first, then rotation, then HDR. "Re-apply with final scope" skips MonitorPanel changes; they have no scope.

**Requests the A.3 shape can't express:**
- **Smart HiDPI enable / virtual mirror.** The virtual display must exist (host IPC, then the registry sees it) *before* the snapshot and prediction, because `predict` can't reference an ID that doesn't exist yet. On revert or timeout it must be destroyed *after* the unmirror. Add the following, with the rule that `prepare` runs inside the serialized queue before the snapshot:

```swift
struct TransactionRequest {
    let label: String
    let risk: TransactionRisk
    let changes: [DisplayChange]
    let finalScope: FinalScope
    let automatic: Bool
    var prepare: (@MainActor () async throws -> Void)? = nil        // e.g. create the virtual display and wait until it's listed
    var afterRevert: (@MainActor () async -> Void)? = nil           // e.g. destroy it
    var afterKeep: (@MainActor () async -> Void)? = nil
}
```

- **DDC preConfirm** (input, KVM, standby). `TransactionRisk.preConfirm(message:)` exists, but `DisplayChange` has no DDC case, and these aren't layout transactions (there's no guard and no undo). Drop `preConfirm` from `TransactionRisk` and add `@MainActor protocol PreConfirmPresenter { func confirm(_ message: String, display: UInt32, dontAskKey: String?) async -> Bool }` in the context. `DDCService.write` for preConfirm codes requires a token minted by it.
- **Risk classification.** A caller passes `risk`, but the known-good rules (§4.3) belong to the queue. Have the queue compute `max(callerRisk, RiskClassifier.classify(changes, knownGood:, current:))`. Put `RiskClassifier` in SnapticKit (it's the §14.4 "known-good classification" test and has no file today).

---

## 6. Team plan (finding 2, finding 17)

### 6.1 Concrete conflicts and missing stubs

| # | Conflict | Fix |
|---|---|---|
| 1 | Step 0 stubs `Sources/Snaptic/Core/Permissions.swift`, but `Sources/Snaptic/Permissions.swift` exists. That's a duplicate basename, a hard error and a lint failure, and any `enum Permissions` stub is a duplicate type. | Step 0 (lead) **`git mv`s every existing file** with no content change: `Permissions.swift` → `Core/Permissions.swift`; the rest → `Switcher/`. A owns them from then on. |
| 2 | Step 0 stubs `Core/SettingsWindow.swift`, but `SettingsView.swift` already declares `SettingsWindowController`. A stub that declares the same class collides. | Stub with a new type name (`SettingsWindowHost`); A deletes the old class in step 1. |
| 3 | `AppDelegate.swift` isn't in §13. Startup steps 1–9 (§3.2) call B's `RevertJournal` (5), A's `SafeMode`/`LaunchStability` (3–4) and `HostHeartbeat` (7). | List it under A. In step 0 it calls every startup hook as a **stub**: `RevertJournal.recoverAtLaunch()` (B file), `LaunchStability.evaluate()`, and so on. B fills the body later without touching A's file. |
| 4 | `main.swift` (lead) calls `SnapticEntry.run()`, which has no file. Dispatch reaches `DisplayGuardMain` (B), `VirtualHostMain` (B) and `CLIClient` (A). | Add `Core/SnapticEntry.swift` (A). Step 0 stubs `enum DisplayGuardMain { static func run(_ args: [String]) -> Never }` and the others in their owners' files. |
| 5 | Safe Mode: §13 puts `SafeMode` and `LaunchStability` in Core (A); §14.2 step 2 gives "Safe Mode" to B. | A owns them. B only consumes `SafeModeState`. |
| 6 | `SafetyPage` and `DiagnosticsPage` belong to F but show B's guard state, kill switches, private-API table and journal, plus C's DDC caps. | Move `SafetyPage` to B. F keeps `DiagnosticsPage` and reads `DiagnosticsReport` (B), which pulls from `DiagnosticsContributor`s each team registers. |
| 7 | "`<Area>Page.swift` + `<Area>MenuItems.swift` owned by the area's team" never lists the areas. The stub list is undefined. | Enumerate them: `ResolutionPage`/`ResolutionMenuItems` (D), `VirtualScreensPage` (D), `BrightnessPage` (C), `ColorPage` (C), `DDCPage` (C), `KeysPage` (C), `OSDPage` (C), `ArrangementPage` (D), `ProtectionPresetsPage` (D), `PIPPage` (E), `AutomationPage` (A), `SafetyPage` (B), and the matching `*MenuItems`. |
| 8 | Menus: F's `DisplaysMenuBuilder`/`DisplayMenuBlock` must place items from C, D and E. `MenuCustomizationPage` (F) needs per-item visibility for *every* item, so it needs a shared item ID list. | Contract: `enum DisplayMenuItemID: String, CaseIterable` (written by the lead with all ids), and `@MainActor protocol DisplayMenuContributor { func items(for display: DisplayInfo, placement: …) -> [(DisplayMenuItemID, NSMenuItem)] }`, registered through the context. |
| 9 | Shortcuts (C, `DisplayShortcuts`) list actions from D (resolution, rotate, presets), E (PIP) and A (custom actions). The CLI and menu need the same actions. | Contract: `@MainActor final class DisplayActionRegistry { struct Action { id, title, feature, perform: @MainActor (DisplayTarget) -> Void }; register/unregister/all }`. Each team registers in `start`. |
| 10 | `DisplayInfo.capabilities` (B's type) includes "brightness methods available", which C computes. | Remove it from DisplayInfo. C exposes `brightness.methods(for:)`. |
| 11 | Missing files: `SafetySettings` (B), `DisplaysMenuSettings` (F), every `PerDisplay*` struct, `DisplayKey`, `L()`, `Lifetime`, the home of the A.2 protocols and `FeatureAvailability`, `LayoutReader` (guard), `RiskClassifier`, the journal model (the §14.4 "journal validation" test), `RateLimiter` (invariant 6), and `TextSanitizer` (now inside switcher `Settings.swift`, used by B, C and A). | Add them to §13 with owners (most go to SnapticKit; see 2.7). Move `TextSanitizer` to `SnapticKit/KitText.swift`. |
| 12 | `DisplaysModule.swift` and `DisplaysContext.swift` (lead, then F) must construct and wire every team's services and controllers. Any init-signature change means editing F's file. | Rule: services and controllers have `init()` and nothing else. The lead wires **all** of them in step 0. Teams never edit these two files. |
| 13 | A single shim header owned by B. C needs I²C/AVService, ColorSync, Night Shift and OSD. D needs MonitorPanel, CGS modes and the virtual display. A needs spawn/disclaim. All of them wait on B, who is already the critical path. | Use per-area headers under `include/` (`SNDDC.h`, `SNColorSync.h`, `SNNightShift.h`, `SNOSD.h`, `SNMonitorPanel.h`, `SNVirtualDisplay.h`, `SNSpawn.h`, `SNEncoding.h`, `SNProcess.h`) with matching `.m` files, each owned by its user team. Only `SnapticShims.h` (the umbrella; it must `#import` all of them or clang warns "umbrella header doesn't include") belongs to the lead. The step-0 stubs return "unavailable". |
| 14 | `DisplaysRuntimeState` fields are written by C (live brightness, contrast, volume) but the file is F's. | The lead writes every field in step 0. |
| 15 | `cli` and `appleScript` are Displays features (§2.1), yet §3.5 promises `snaptic cli open-settings` "with everything hidden", including when Displays is off. | Make the control server host-level (A), with a General switch. Displays registers its verbs only while running. |
| 16 | B's step-2 list is registry, identity, modes, private-API registry, **all shims**, transactions, confirm, journal, guard, panic, Safe Mode, session gate, diagnostics, plus the virtual host needed by D in step 4. That's at least 25 files on the critical path, and C blocks on the DDC shim. | Shims by area (row 13). Safe Mode to A (row 5). Diagnostics to F. VirtualHostMain and VirtualHostClient to D in step 4 (D already owns the consumers). |

**Can steps 0–4 run without editing each other's files?** Only after rows 1–14 are fixed. As written, steps 2 and 3 force edits to `AppDelegate`, `DisplaysModule`/`DisplaysContext`, the shim header, `DisplaysRuntimeState`, F's menu builder and C's shortcut file by other teams.

### 6.2 Minimal skeleton PR, split in two

**0a: toolchain proof** (2–4 CI rounds). Merge it before writing a single contract.
- `Package.swift` with the conditional (§3.2).
- `git mv` of the existing sources into `Core/` and `Switcher/` (row 1). `main.swift` calls `SnapticEntry.run(CommandLine.arguments)`, and `SnapticEntry` holds today's `main.swift` body.
- `Sources/SnapticKit/KitProbe.swift`: one `package struct` with a `package init`. It includes a `LossyMap` of `package enum` keys, round-tripped through JSON, to prove the shape on both platforms.
- `Sources/SnapticShims/include/SnapticShims.h` plus `SNEncoding.m`: the ARC `#error`, one `+ (BOOL)verifyClass:selector:expected:error:` with a normalized encoding compare, `@try/@catch`, `NS_ASSUME_NONNULL`.
- The app calls `KitProbe` and `SNEncoding` once (in a `#if DEBUG` self-check or at startup), so **universal XCBuild** exercises cross-module `package` access and ObjC bridging on both architectures.
- `Tests/SnapticKitTests/KitProbeTests.swift`.
- `scripts/lint.sh` (basenames per target directory, forbidden patterns, the Kit-only Foundation ban list).
- Workflow changes (§7).

**0b: contracts and stubs** (3–6 rounds). Generate the stubs with a script from one table (path, type, kind, conformances), not by hand: about 120 files, where one typo breaks every team. Contents: Appendix A as real Swift, the §2.12 APIs, the §6.1 rows, and `FeatureGraph` with its closure, order and exclusivity tests.

### 6.3 CI round estimate

- Swift reports many errors per module per run, so one round fixes several problems.
- Rough counts:
  - 0a: 2–4 rounds;
  - 0b: 3–6;
  - step 1 (switcher refactor): 4–8;
  - steps 2–4: about 20 team PRs × 4–8 rounds = 80–160;
  - step 5 fixes: 10–20.
- **Total: about 100–200 macOS runs.**
- At roughly 30k lines, debug build, tests and a universal release take 12–20 min per run. With the 5-concurrent macOS cap, peak fan-out queues to 30–60 min per round-trip. The Linux job (about 2 min) only covers SnapticKit, roughly 30% of new code.
- Reduce it:
  - PR runs do the native debug build and tests only;
  - the universal release runs on pushes to `feature/displays` and `main`. There's no `#if arch`, so arch-specific compile errors are essentially impossible; the arch risks are runtime (BOOL encoding).

---

## 7. CI (Major, finding 16)

- **Add `push: branches: [main, 'feature/**']`.** The current `build.yml` runs on push only for `main`. Two PRs can each be green against an older `feature/displays` and break it when combined (a type renamed in one, used in the other), and nothing reports it. Also require "branch up to date before merging" on `feature/displays`.
- **Pin an exact Xcode:** `sudo xcode-select -s /Applications/Xcode_16.4.app` (or whatever 16.x the image lists), failing loudly if it's missing. "Latest 16.x" changes under you. And because `package` under XCBuild needs SwiftPM ≥ 6.0 (§2.2), a fallback to an Xcode 15 image breaks the universal step only.
- The private-class check: `nm -u -arch all build/Snaptic.app/Contents/MacOS/Snaptic | grep -E '_OBJC_CLASS_\$_(CGVirtualDisplay|MPDisplay|OSDManager|CBBlueLightClient)' && exit 1 || true`. Note `-arch all` (it's a universal binary) and `-u` (undefined symbols only).
- Warnings digest: XCBuild output (universal) and native output differ in format. Grep `warning:` from both logs.
- macOS job: `swift build --build-tests 2>&1 | tee build.log` with `set -o pipefail` (the default `bash -e` shell on GitHub uses pipefail, but a custom `shell:` may not).

---

## 8. Crash, deadlock, retain cycle and leak list (finding 14 and others)

| # | Sev | Where | Hazard | Fix |
|---|---|---|---|---|
| c1 | Blocker | §3.2/§4.5 | `FileHandle.write` raises an ObjC exception on EPIPE, which crashes the app. | `HelperPipeWriter` (§4.1). |
| c2 | Major | §3.2 | The parent keeps the read end, so writes block forever on main. | Close it explicitly (§4.1). |
| c3 | Major | helpers, CLI | SIGPIPE kills the guard mid-revert, or kills the app on a CLI disconnect. | `SIG_IGN` plus `SO_NOSIGPIPE` (§4.1). |
| c4 | Major | §5, A.6 | **CG reconfig, IOKit and Carbon refcons** are `passUnretained(self)` plus an async hop. After `CGDisplayRemoveReconfigurationCallback`, blocks already queued dereference a freed registry. | A retained weak box, released after removal: see below. |
| c5 | Major | §5 | `IOServiceAddMatchingNotification`: if the returned iterator isn't drained right away, no further notifications ever fire. Every `io_object_t` from `IOIteratorNext` must be `IOObjectRelease`d. `IONotificationPortDestroy` on stop. | Write it into rule 5 and the shim template. |
| c6 | Major | shim | dlsym'd `IOAVServiceCreateWithService`, `CoreDisplay_DisplayCreateInfoDictionary` and `IOAVServiceCopyEDID` are **+1** (Create/Copy). In ObjC under ARC, a typedef returning `id` is treated as +0, so ARC over-releases and crashes. A typedef returning `CFTypeRef` isn't ARC-managed, so it leaks unless `CFRelease`d. | Typedef with `CFTypeRef` plus explicit `CFRelease`, or annotate the typedef with `CF_RETURNS_RETAINED` and bridge with `CFBridgingRelease`. In Swift, `@convention(c)` returns are `Unmanaged<…>?` with `takeRetainedValue()` for Create/Copy and `takeUnretainedValue()` for Get (the existing `copySpaces` already does this). Cache `IOAVService` per display and release it on display removal and service deactivate. |
| c7 | Major | §3.1 | BOOL encodings: `B` on arm64, `c` on x86_64. An expected table written from arm64 class-dumps marks every BOOL selector unavailable on Intel, silently. | Normalize: strip digits and treat `B`≡`c` where the declared type is BOOL. A Linux test covers the normalizer (it's pure string logic, so it belongs in Kit). |
| c8 | Major | A.2 | Strong participant registration creates context ↔ controller cycles. | Weak, plus `lifetime.onEnd` (§2.11). |
| c9 | Major | A.2 | Services holding the context strongly is a cycle. | `unowned` or explicit dependencies. |
| c10 | Minor | §8.1 | `MediaKeyTap` restart on the same `Thread` raises `NSInvalidArgumentException`, the same bug class as r1 #1. | A new `Thread` per start; on stop: `CGEvent.tapEnable(false)`, `CFMachPortInvalidate`, remove the source, `CFRunLoopStop`. The callback's refcon follows the c4 rule. |
| c11 | Minor | §10 | SCK: a stop during an in-flight `startCapture` await leaves a running stream. The `StreamReceiver` must not retain the controller. | Check `lifetime.isEnded` after every await and call `stopCapture` if ended. Give the receiver a weak or mailbox-only reference. Keep the `SCStream` strongly until `stopCapture` completes. |
| c12 | Minor | §3.5 | `requestMenuRebuild` while the menu is tracking: removing items whose `NSSlider` view is under the mouse makes the slider glitch or stop responding. | Defer the rebuild to `menuDidClose`; update slider values in place. |
| c13 | Minor | §4.9 | The `beginActivity` token isn't stored or ended. | Store it and end it when long-armed ends. |
| c14 | Minor | deadlocks | `DispatchQueue.main.sync` from the DDC or AppleBrightness queues while main does `queue.sync` (MonitorControl's DisplayServices pattern). | Rule: never `.sync` onto main; from main, `.sync` only onto queues whose work is bounded below 50 ms. |
| c15 | Minor | §11.1 | `Process.terminationHandler` and `readabilityHandler` run on background threads. | Hop to main. Never `waitUntilExit()` on main. |

The refcon box (c4):

```swift
final class CallbackTarget<T: AnyObject>: @unchecked Sendable {
    weak var target: T?                                  // read only on main
    init(_ target: T) { self.target = target }
}
// DisplayRegistry (@MainActor)
private var refcon: UnsafeMutableRawPointer?
private static let reconfigure: CGDisplayReconfigurationCallBack = { id, flags, refcon in
    guard let refcon else { return }
    let box = Unmanaged<CallbackTarget<DisplayRegistry>>.fromOpaque(refcon).takeUnretainedValue()
    DispatchQueue.main.async { box.target?.noteReconfigure(id, flags) }   // the block retains the box, not the registry
}
func startObserving() {
    guard refcon == nil else { return }
    let p = Unmanaged.passRetained(CallbackTarget(self)).toOpaque()
    CGDisplayRegisterReconfigurationCallback(Self.reconfigure, p); refcon = p
}
func stopObserving() {
    guard let p = refcon else { return }
    CGDisplayRemoveReconfigurationCallback(Self.reconfigure, p)
    Unmanaged<CallbackTarget<DisplayRegistry>>.fromOpaque(p).release()  // queued blocks still hold the box; target is weak
    refcon = nil
}
```

---

## 9. Other minor findings

| # | Section | Finding |
|---|---|---|
| m1 | §3.3 vs A.1 | §3.3 lists `menuPlacement` as a module property, but the A.1 protocol lacks it. Put it in `ModulesConfig` (user choice) and remove it from §3.3. |
| m2 | §4.5 | Undo ops reference `UInt32` display IDs. After a replug the id can change, and a different display could take an old id. Re-resolve through `fingerprint` (it's in the new `UndoOp`) and skip on mismatch. |
| m3 | §4.6 | `kern.bootsessionuuid` through `sysctlbyname` returns a C string. Buffer length: call once with `nil` to get the size. |
| m4 | §4.7 | ⌃⌥⌘⎋ while the switcher is open is swallowed by `handleKeyWhileOpen` (r1 #30, still undocumented). |
| m5 | A.1 | `GlobalHotkeys.Combo` UI conversion between `NSEvent.ModifierFlags` and Carbon modifiers belongs in one helper (A), not per team. |
| m6 | §11.4 | `Bundle.main` under the `/usr/local/bin/snaptic` symlink: CLI mode must compute paths with `getpwuid_r` (as in §4.1.6) and never read `Bundle.main.bundleIdentifier`. |
| m7 | §14.3 rule 5 | The compiler special-cases closures passed to `DispatchQueue.main.async` as main-actor isolated. Don't rely on that inference for other forms (`asyncAfter`, `NotificationCenter` `queue: .main`, `Timer` blocks). Wrap them in `MainActor.assumeIsolated { }`, as the existing code does. |
| m8 | §4.3 | Take the snapshot inside the serialized queue body. A caller-taken snapshot is stale by the time the queue runs. |
| m9 | §5 | `Invariants.violations` needs the panel-host set (r1 had `panelHostIDs`). Add `Invariants.requiredLongArm(_:) -> [UndoOp]`, so invariant 4 is computed, not hand-maintained by each team. |
| m10 | §5 | Resolve modes by the full `ModeRef` tuple (ioModeID, pixel size, point width, refresh), with ioModeID as a hint. With `kCGDisplayShowDuplicateLowResolutionModes`, IDs aren't guaranteed unique across the HiDPI and low-resolution duplicates. A wrong match is a black screen. |
| m11 | A.3 | `DisplayChange.origin(x: Double, y: Double)`: CG takes `Int32`. Use `Int32` to avoid rounding drift between predict and apply. |
| m12 | §3.1 | Add `NS_ASSUME_NONNULL_BEGIN/END` and explicit nullability to every shim header, or Swift imports implicitly unwrapped optionals everywhere. |
| m13 | §14.1 | Run the basename lint per target directory (`Sources/Snaptic`, `Sources/SnapticKit`, `Sources/SnapticShims`, `Tests/SnapticKitTests`) and also over `.m` files. Duplicate `.m` basenames collide as object files under XCBuild. |
| m14 | §1 | Ad-hoc signing: each CI build has a new cdhash, so TCC grants reset on every update (documented). Guard and host helpers need no TCC. |
| m15 | §2.1 | Add `.always` to the feature default enum (`overview` and `diagnostics` are "always", which isn't S, O or X). |
