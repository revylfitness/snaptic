# How team agents work (lead-owned)

Read this, then `docs/design/PLAN.md` (the R5 amendments at the top win), then the
sections and normative snippets your brief names (`R2C.md`, `R3C.md`, `R4C.md`).
`docs/design/parity-catalog.md` describes the BetterDisplay features we match;
`macos-display-apis.md` and `macos27.md` hold the platform research.

## Ground truth

- The Swift on `feature/displays` is the contract. Contract files (lead-owned, do not
  edit): `Sources/SnapticKit/{KitModules,FeatureGraph,LineSplitter}.swift`,
  `Sources/SnapticKit/Config/{ConfigModel,ConfigDisplays}.swift`,
  `Sources/Snaptic/Core/ModuleContracts.swift`, `Sources/Snaptic/Displays/{DisplaysModule,
  DisplaysContext,DisplaysContracts,DisplaysRuntimeState,SharedExtensions}.swift`,
  `Sources/Snaptic/Displays/Registries/*`, `Sources/Snaptic/Displays/Platform/{CallbackTarget,
  HelperPipeWriter}.swift`, `Package.swift`, `.github/**`, `scripts/**`.
- `scripts/stubs.tsv` lists every file and its owner. **Edit only files your team owns.**
  If you truly need a contract change, stop and write the exact diff you need in your
  final report; the lead applies it.
- Stubs show the API other teams already call. You may **add** members freely. Keep
  existing signatures unless your brief allows a change; if you must change one, grep
  every caller first (callers in other teams' files are a blocker: report it).
- New files: you may add files under your own directories. Report each new path with
  owner and kind so the lead adds it to `scripts/stubs.tsv` (lint fails until then:
  add the line yourself in your branch, and say so in the report).

## Toolchain facts

- There is no Swift compiler in the agent container. **CI is the compiler.** Push and
  read the results with the helper:
  `/tmp/claude-0/-home-claude/d64e05c1-6336-52a5-bd62-2efc57ca1f12/scratchpad/ci/ci.sh <FULL sha> 40`
  (run it in the background; it prints job results and error lines; logs land next to
  the script in `logs-<sha>/`). Each round takes about 3–6 minutes.
- Run `./scripts/lint.sh` locally before every push (python3 is available).
- macOS 14 deployment target, Xcode 16.4 (Swift 6.1 compiler in Swift 5 language mode),
  universal binary. No macOS 15+/26/27 SDK symbols without `#available` (and prefer none).
- SnapticKit builds and tests on Linux (swift 5.10): Foundation only, `package` on every
  top-level declaration, explicit `package init`. Put all pure logic in Kit and test it
  there. Tests: XCTest, deterministic (use `SeededGenerator` from
  `Tests/SnapticKitTests/FeatureGraphTests.swift` for fuzzing; do not redeclare it).

## Git

- Work in your own worktree: `git -C /home/claude/snaptic fetch -q origin && git -C
  /home/claude/snaptic worktree add /home/claude/wt/<branch> -b feature/<branch> origin/feature/displays`.
- Branch names start with `feature/` so pushes build in CI. Commit often; every commit
  message ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01UYoMQ4vFKCFBrwcdgSAmUg
  ```
- Push your branch only. Never push to `feature/displays` or `main`, never force-push
  anything but your own branch, never push tags. If a push is refused by policy (403),
  report it; do not retry or route around it.
- Rebase on `origin/feature/displays` before your final push if it moved.

## Rules (PLAN §14.3, condensed)

1. macOS 14 APIs or `#available`. No Swift 6-only syntax, no macros except `@Published`,
   `@objc`, `@MainActor`, `@ViewBuilder`. No `@_silgen_name`, extern private symbols,
   `#if arch`, `resources:`. Private symbols only via `PrivateDisplayAPI` (dlsym /
   `NSClassFromString`), private ObjC only inside SnapticShims `.m` files with
   `@try` and selector encoding checks.
2. Isolation: controllers, services, UI `@MainActor`; `DDCService`/`AppleBrightnessIO`
   `@unchecked Sendable` with lifecycle in an extension. C callbacks use
   `CallbackTarget`; closures passed to `asyncAfter`, NotificationCenter, Timer, KVO wrap
   `MainActor.assumeIsolated`. Never `DispatchQueue.main.sync`. Main thread ≤ 50 ms.
3. No `static let shared` in Displays. No `print`/`NSLog` (use `EventLog.shared.record`,
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
   never `fatalError`. Real code may not trap on user data or system state either.
9. Settings: every config field has a default, a lossy decode (`c.lossy(.key, default)`),
   and clamping in `sanitized()`.

## Done for a team step

- Everything in your brief is implemented for real (no "TODO", no stubs left in files you
  own unless the brief defers them to a later step), reachable in UI (and CLI where
  listed), and wired to availability, kill switch, Safe Mode, panic, session gate and
  diagnostics.
- Kit logic has meaningful unit tests (edge cases, fuzzing for parsers).
- `./scripts/lint.sh` passes and the CI run for your final commit is green on all jobs.
- Final report: branch name, final full SHA, CI run result, files added (with owner and
  kind), any contract changes you need from the lead, hardware assumptions to verify
  (Appendix D), and known limitations. Keep it under 400 words.
