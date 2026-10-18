# How team agents work (lead-owned)

Read this, then `docs/design/0.3/PLAN.md` (0.3; the R5 amendments at the top win) and, for
everything 0.3 doesn't touch, `docs/design/PLAN.md` (0.2), then the sections your brief names.
`docs/design/0.3/STEP0-NOTES.md` lists where the step-0 code deviates from the plan text: the
code on `feature/v03` is the contract (R5 rule carried forward).
`docs/design/parity-catalog.md` describes the BetterDisplay features we match;
`macos-display-apis.md` and `macos27.md` hold the platform research.

## Ground truth

- The Swift on `feature/v03` is the contract. Contract files (lead-owned, do not
  edit): `Sources/SnapticKit/{KitModules,FeatureGraph,LineSplitter,KitLossy,AwakeFeatureGraph}.swift`,
  `Sources/SnapticKit/Controls/{ControlRegistry,ControlLegacy,ControlRemovals}.swift`,
  `Sources/SnapticKit/Config/{ConfigModel,ConfigDisplays,ConfigModules,ConfigMigrations,ConfigAwake}.swift`,
  `Sources/Snaptic/Core/{ModuleContracts,ModuleHost,ModuleContext,ToastPresenter,HostSignals,
  ConfigSlice}.swift`, `Sources/Snaptic/Awake/{AwakeModule,AwakeContext,AwakeContracts,
  AwakeRuntimeState}.swift`, `Sources/Snaptic/Displays/{DisplaysModule,
  DisplaysContext,DisplaysContracts,DisplaysRuntimeState,SharedExtensions}.swift`,
  `Sources/Snaptic/Displays/Registries/*`, `Sources/Snaptic/Displays/Platform/{CallbackTarget,
  HelperPipeWriter}.swift`, `Tests/SnapticKitTests/{KitModulesTests,KitLossyTests,ConfigModulesTests,
  ConfigDisplaysTests,ConfigMigrationsTests,ConfigAwakeTests,AwakeFeatureGraphTests,
  ControlRegistryTests}.swift`, `Tests/SnapticKitTests/Support/ConfigFixtures.swift`, `Package.swift`,
  `Resources/Info.plist`, `.github/**`, `scripts/**` (exceptions below).
- `scripts/stubs.tsv` lists every file and its owner. **Edit only files your team owns.**
  If you truly need a contract change, stop and write the exact diff you need in your
  final report; the lead applies it.
- Stubs show the API other teams already call. You may **add** members freely. Keep
  existing signatures unless your brief allows a change; if you must change one, grep
  every caller first (callers in other teams' files are a blocker: report it).
- New files: you may add files under your own directories. Report each new path with
  owner and kind so the lead adds it to `scripts/stubs.tsv` (lint fails until then:
  add the line yourself in your branch, and say so in the report).
- **Exceptions to "`scripts/**` and the contract files are the lead's"** (0.3):
  - `scripts/stubs.tsv`: add rows for your own new files (above).
  - `scripts/lint-legacy.tsv` (the ratchet): only the three permanent rows remain (`AppDelegate.swift`
    L6, `PIPWindow.swift` L6, `ArrangementCanvas.swift` L5), and **strict mode is on**: CI runs
    `lint.sh --strict`, which also fails when a row's count went down. Never raise a count or add a
    row; a new violation is fixed, not ratcheted. Run `./scripts/lint.sh --strict` before you push.
  - Control tables (PLAN 0.3 §4.8.2, R5-13): each `Sources/SnapticKit/Controls/<Type>Controls.swift`
    belongs to the owner of `<Type>` (see `stubs.tsv`); fill `controls` as your views and
    builders land. A table you add needs a `stubs.tsv` row for its file and **one appended
    line** in `ControlRegistry.tables`; that line is the only edit you may make to
    `ControlRegistry.swift`.
- Lint (0.3 §6.3): `./scripts/lint.sh` runs the 0.2 rules plus L1–L17 (`scripts/lint03.py`).
  Pass ids to views and MenuKit only as `ControlID("literal")`, and declare the table with
  `typealias Controls = <Type>Controls` in that file (L15).

## Toolchain facts

- There is no Swift compiler in the agent container. **CI is the compiler.** Push and
  read the results with the helper:
  `/tmp/claude-0/-home-claude/d64e05c1-6336-52a5-bd62-2efc57ca1f12/scratchpad/ci/ci.sh <FULL sha> 40`
  (run it in the background; it prints job results and error lines; logs land next to
  the script in `logs-<sha>/`). Each round takes about 3–6 minutes.
- Run `./scripts/lint.sh --strict` locally before every push (python3 is available).
- macOS 14 deployment target, Xcode 16.4 (Swift 6.1 compiler in Swift 5 language mode),
  universal binary. No macOS 15+/26/27 SDK symbols without `#available` (and prefer none).
- SnapticKit builds and tests on Linux (swift 5.10): Foundation only, `package` on every
  top-level declaration, explicit `package init`. Put all pure logic in Kit and test it
  there. Tests: XCTest, deterministic (use `SeededGenerator` from
  `Tests/SnapticKitTests/FeatureGraphTests.swift` for fuzzing; do not redeclare it).

## Git

- Work in your own worktree: `git -C /home/claude/snaptic fetch -q origin && git -C
  /home/claude/snaptic worktree add /home/claude/wt/<branch> -b feature/<branch> origin/feature/v03`.
- Branch names start with `feature/` so pushes build in CI. Commit often; every commit
  message ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01UYoMQ4vFKCFBrwcdgSAmUg
  ```
- Push your branch only. Never push to `feature/v03`, `feature/displays` or `main`, never force-push
  anything but your own branch, never push tags. If a push is refused by policy (403),
  report it; do not retry or route around it.
- Rebase on `origin/feature/v03` before your final push if it moved.

## Rules (PLAN §14.3, condensed)

1. macOS 14 APIs or `#available`. No Swift 6-only syntax, no macros except `@Published`,
   `@objc`, `@MainActor`, `@ViewBuilder`. No `@_silgen_name`, extern private symbols,
   `#if arch`, `resources:`. Private symbols only via `PrivateDisplayAPI` (dlsym /
   `NSClassFromString`), private ObjC only inside SnapticShims `.m` files with
   `@try` and selector encoding checks.
2. Isolation: controllers, services, UI `@MainActor`; `DDCService`/`AppleBrightnessIO`
   `@unchecked Sendable` with lifecycle in an extension. C callbacks use
   `CallbackTarget`; closures passed to `asyncAfter`, NotificationCenter, Timer, KVO wrap
   `MainActor.assumeIsolated` (linted: `scripts/lint03.py` rule 2). Never `DispatchQueue.main.sync`. Main thread ≤ 50 ms.
3. No `static let shared` in Displays or Awake (Awake also: observers with `queue: .main`, timers added in
   `.common` modes, lint L10/L14). No `print`/`NSLog` (use `EventLog.shared.record`,
   never with titles, app names, serials, EDID bytes or key codes).
4. Never `FileHandle` writes, `readLine`, `waitUntilExit`, `waitpid(-1, …)`, `Process`.
   Helpers go through `HelperSpawner`; pipes through `HelperPipeWriter` + `LineSplitter`.
5. Extensions of types declared in another file are `fileprivate` (except
   `extension PrivateSymbol { static let … }`).
6. Strings through `L()`. Every user-visible feature: availability, kill switch,
   idempotent start/stop, `configDidChange`, Panic/Session participation where relevant,
   Safe Mode behavior, diagnostics rows, menu items + actions + CLI verbs per the R5.4
   exposure table.
7. Persisted or cross-process ids are `DisplayKey`, never `CGDirectDisplayID`.
8. Stubs return safe values (`nil`/`false`/`[]`/`.unavailable(L("Not built yet"))`);
   never `fatalError` (nor `preconditionFailure` or `try!`; linted). Real code may not trap on user data or system state either.
9. Settings: every config field has a default, a lossy decode (`c.lossy(.key, default)`),
   and clamping in `sanitized()`.

## Done for a team step

- Everything in your brief is implemented for real (no "TODO", no stubs left in files you
  own unless the brief defers them to a later step), reachable in UI (and CLI where
  listed), and wired to availability, kill switch, Safe Mode, panic, session gate and
  diagnostics.
- Kit logic has meaningful unit tests (edge cases, fuzzing for parsers).
- `./scripts/lint.sh --strict` passes and the CI run for your final commit is green on all jobs.
- Final report: branch name, final full SHA, CI run result, files added (with owner and
  kind), any contract changes you need from the lead, hardware assumptions to verify
  (Appendix D), and known limitations. Keep it under 400 words.
