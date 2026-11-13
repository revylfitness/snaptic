# Snaptic 0.5 plan, round 2: pressure review

- **Reviewer:** pressure (round 2).
- **Plan:** `docs/design/0.5/PLAN.md` r2 (1349 lines).
- **Grounding:** commit `7dd972c` on `feature/v050-dock-previews`. I read the tree, `scripts/lint.sh`, `scripts/lint03.py`, `scripts/stubs.tsv`, `.github/workflows/build.yml`, `Package.swift` and `docs/design/0.4/PLAN.md`. Every `path:line` below is at that commit.
- **Scope:** I don't repeat r1's P-1 to P-27 (`review-r1-pressure.md`), and I don't reopen owner decisions Q1 to Q7.
- **Counts:** 0 Blocker, 9 Major, 16 Minor.

**Verdict.** The architecture holds. An implementer could build it in this order once the Majors are fixed. The Majors fall into four groups:

- **Done-whens that can't be checked when their item finishes:** P2-3, P2-4, P2-5, P2-6.
- **Rules that contradict each other:** P2-2.
- **A safety rule that races its own callers:** P2-1.
- **Contracts the plan names but never defines:** P2-7, P2-8, P2-9.

None of them changes the module's design.

---

## Major

### P2-1 · Major · §4.12 step 6 · One `Windows.inFlight` key can't serve concurrent callers, and giving ⌘⇥ back isn't exempt

**Finding.** The crash guard keeps one key, `Windows.inFlight = "<symbol>@<build>"`. It is set before each call and cleared after. The guarded symbols are called from several threads at once:

- `windowID(of:)` runs inside `DispatchQueue.concurrentPerform`.
- The AX observer callback runs on `ObserverThread`.
- `HotkeyGuard.check()` runs on a global-queue timer.
- Capture runs off main.

With one key, two failures follow:

- Call B clears A's marker while A is still running, so a crash in A leaves no marker.
- A's write replaces B's symbol, so the wrong symbol gets disabled.

There are three more gaps:

- **Giving ⌘⇥ back.** These calls give ⌘⇥ back: `recoverFromPreviousRun`, `restore`, `apply`'s give-back loop, `setSuspended(true)`, `HotkeyGuard.check` and `releaseAll` (the last one runs in the signal handler). Under step 6 they would also write the marker. A crash there would set `disabledBuild.symbolicHotKeys`, and H6 says giving back must never be blocked. A signal handler also can't write `UserDefaults` safely.
- **Launch order.** The plan doesn't say when the launch check runs. `recoverFromPreviousRun` calls the symbol first thing (`AppDelegate.swift:58`).
- **The 20 successes.** The plan doesn't say whether they're counted per process or persisted. `IconsCrashGuard` has no such count.

**Evidence.**
- Plan: PLAN:l.753–757 (step 6), PLAN:l.751–752 (poison counter), PLAN:l.375–378 (H6, giving back always runs).
- Concurrent callers:
  - `Sources/Snaptic/Switcher/WindowManager.swift:354` (`concurrentPerform`) and `:379` (`PrivateAPIs.windowID` inside it);
  - `:589` (observer callback; the thread is declared at `:600`);
  - `Sources/Snaptic/Switcher/PrivateAPIs.swift` `HotkeyGuard.start` (a `DispatchSource` timer on `.global`) and `check()`.
- Giving back: `PrivateAPIs.swift:159`, `:180`, `:206`, `:216`, `:270`, `:280` (`setSymbolicHotKey(…, enabled: true)` or `value`).
- Signal handler: `Sources/Snaptic/Core/AppDelegate.swift:221`. Launch: `AppDelegate.swift:58`.
- `IconsCrashGuard`: `Sources/SnapticKit/IconsEngineCore.swift:154–176` (one marker, no verified count).

**Proposal.** Replace step 6 (PLAN:l.753–757) with:

> 6. **Crash guard** (`CrashGuard`, generalised from `IconsCrashGuard`; one guard per `WindowFeature`):
>    - Each feature has its own key, `Windows.inFlight.<feature> = "<OS build>"`. An atomic count of that feature's calls in flight writes the key on 0 → 1 and removes it on 1 → 0. Concurrent calls (`concurrentPerform`, the observer thread, `HotkeyGuard.check`, capture) share one marker and never clear each other's.
>    - Successes are counted in memory per process. At 20 on this OS build, `Windows.verifiedBuild.<feature>` is written once, and marker writes for that feature stop.
>    - At launch, before `SystemHotkeys.recoverFromPreviousRun()` (`AppDelegate.swift:58`), each `Windows.inFlight.*` key found sets `Windows.disabledBuild.<feature>`, logs EventLog `.safety` and is removed.
>    - **Giving ⌘⇥ back is never guarded.** `setSymbolicHotKey(_, enabled: true)` writes no marker and ignores `disabledBuild` and the kill switch. That covers its calls from `recoverFromPreviousRun`, `restore`, `apply`'s give-back loop, `setSuspended(true)`, `HotkeyGuard.check` and `releaseAll`. Only taking ⌘⇥ (`enabled: false`) and `IsSymbolicHotKeyEnabled` are guarded.
>    - The step-5 poison counter is a per-feature count behind a lock.
>    - Both pages show a "stopped" row with **Try Again**, which clears the disabled build.

Apply the same `<symbol>` → `<feature>` rename in §4.17's crash-guard row text and in M35.

### P2-2 · Major · §4.13, §4.17 row 3, §4.21 · The Safe Mode CLI answer contradicts "registered only while the module runs"

**Finding.**
- Dock Previews "doesn't start in Safe Mode", and the verbs are "registered only while the module runs". So in Safe Mode, `snaptic dock status` gets the house `Unknown command` (exit 2), the same as Hidden Icons does today.
- But row 3 says `paused`, reason `safeMode`, and §4.21 lists a Safe Mode refusal (exit 5). M31 checks "every exit-2 and exit-5 text", so it can't pass whichever way A9 implements it.
- The same contradiction makes two of §4.15's pause reasons unreachable:
  - `killSwitch`: row 1 is "Unknown command".
  - `safeMode`: the module isn't running.

**Evidence.**
- PLAN:l.790, PLAN:l.938, PLAN:l.839 (row 3), PLAN:l.836 (row 1), PLAN:l.950 (refusal), PLAN:l.811–812 (pause reasons), PLAN:l.1134 (M31).
- The Hidden Icons precedent: `Sources/Snaptic/Icons/IconsModule.swift:167–170` returns before `cli.start` at `:219`.

**Proposal (A: follow Hidden Icons).**
- §4.17 row 3, `dock status` cell: "`Unknown command` (exit 2), as Hidden Icons answers in Safe Mode".
- §4.21: replace "**Off or killed**" with "**Off, killed or in Safe Mode**". Delete the refusal "Dock Previews is paused in Safe Mode."
- §4.15 l.811–812: "The other pause reasons are `voiceOver` and `command`. Safe Mode and the kill switches are `DockPageRules` inputs (rows 1 and 3), not pause reasons."
- §2.4 `DockPauseReason`: `otherTool`, `voiceOver`, `command`.

**Alternative (B).** Register the verbs inert in Safe Mode. `status` answers `paused safeMode`, and `pause` and `resume` refuse with exit 5. This costs a Safe Mode branch in `DockCLI`, and Hidden Icons would then behave differently.

### P2-3 · Major · §6 A1b, A2a · Done-whens name app-side unit tests that have no test target

**Finding.**
- A1b is done when "`ThumbnailStoreClientTests` pass", and A2a when "Byte-budget tests pass". Both test the app-side `Windows/ThumbnailStore.swift`.
- The package has one test target, `SnapticKitTests`. It depends only on `SnapticKit` and runs on Linux. No test can import the `Snaptic` executable target.
- r1 P-6 proposed "app-side unit tests behind a protocol seam, run on macOS CI". The plan adopted the test name but added no target, seam or CI step.
- §2.1 also gives "the cache budget" to Kit `WindowCatalogRules` (r1 K4 lists "LRU by count and by bytes" and "Per-client generation, prune and purge"). So the same logic now has two homes.

**Evidence.**
- PLAN:l.1075, PLAN:l.1076, PLAN:l.204 (cache budget in Kit), PLAN:l.264–271 (store semantics), PLAN:l.1059 ("Kit items add Linux-safe tests only").
- `Package.swift:9–10` (the only test target); `.github/workflows/build.yml:111`, `:182` (`swift test`).
- `docs/design/0.5/review-r1-pressure.md:355`, `:1058–1059`.

**Proposal.** Put the store's bookkeeping in Kit, in the house style (P-13: every test asserts on plain data).
- §2.1 adds:
  > `ThumbnailIndex.swift`: the store's bookkeeping, without images:
  > - keys `(windowID, pixel bucket)`, client tags, and per-client `generation`;
  > - `invalidate(client:)`, `prune(keeping:client:)`, `purge(client:)`, and `purgeAll()` with its epoch;
  > - the stamp check `(client, generation, epoch)`;
  > - LRU by count (120) and bytes (96 MB), the oversize skip and 30-minute retention;
  > - the nearest-bucket lookup.
  >
  > `ThumbnailStore` keeps the images in a dictionary keyed by the index's entries and drops what the index evicts.
- §2.1 `WindowCatalogRules`: drop "the cache budget".
- A1b done-when: "`ThumbnailIndexTests` pass (Kit): one client's prune, invalidate and purge never touch the other's entries; a stale stamp is refused; the last release empties the index. `ThumbnailStore` holds no bookkeeping of its own."
- A2a done-when: replace "Byte-budget tests pass" with "`ThumbnailIndexTests`' budget cases pass (120 entries, 96 MB, an oversize entry skipped)".
- H8: L17 adds `ThumbnailIndex`; A1b adds its `stubs.tsv` row.
- K4: r1's K4 lines l.1058–1059 move to `ThumbnailIndexTests` (Appendix A).

The other option is a macOS-only `SnapticTests` target with `@testable import Snaptic`. That needs a `Package.swift` change inside `#if os(macOS)` and a CI step, and the plan would have to say so.

### P2-4 · Major · §6 K1–K5 · The K done-whens defer to r1 Appendix B, which r2 has made stale

**Finding.** K1 to K5 are done when "Appendix B's K*n* tests pass", with one or two patches each. r2 changed the design under several of those lists, and the patches miss most of the changes. An implementer would write tests for behaviour the plan has removed.

- **K1:**
  - `properNames["dockPreviews"]` indexes what is actually a `[String]`, under the wrong suite.
  - `testFreshDefaultsDockOffAndHidden` contradicts H7 ("the Dock gets `.inSnapticMenu`").
  - `testUnknownModuleIDsKept` is conditional, but `testUnknownModulesSurviveARoundTrip` already pins the answer.
- **K2:** "+N more", "the compact card" and "aspect cap" have been replaced by "shrink one size, then scroll" and a fixed 16:10 letterbox. Only "+N more" is patched.
- **K3:**
  - The dismiss list has "Mission Control" and "kill switch", which r2 removed (Mission Control is `.transient`). It lacks `safetyNet`, `dockMenu`, `raised`, `hidApp`, `quitApp`, `appTerminated`, `paused` and `noItem`.
  - "Pause precedence" is a 4-level chain; r2 has a 9-row table in `DockPageRules`.
  - `installKeys`/`removeKeys` are now `engageKeys(Bool)`, with an engagement rule.
  - The card-click resolver has ⌥/⌘/⇧ variants; r2 has left raises and middle closes only.
- **K4:**
  - The badge order is "Minimized > Hidden > Full Screen > Other Space"; r2 has "Minimized > Full screen > On another Space > display name", with Hidden in the header.
  - "Concurrency cap of 4" is A2a's `WindowCapture`.
  - "Per-client generation" is A1b's (P2-3).
- **K5:** the `--minutes 1…1440` grammar has been replaced by `AwakeDurationGrammar`. The K5 patch covers this one.

**Evidence.**
- Plan: PLAN:l.1070–1071, PLAN:l.1078–1080; PLAN:l.386–387 (H7); PLAN:l.506–514 (cards, badges); PLAN:l.307–309 (dismiss reasons); PLAN:l.833–845 (states); PLAN:l.299 (`engageKeys`); PLAN:l.538 (card clicks).
- r1: `review-r1-pressure.md:1003`, `:1012–1013`, `:1016–1017`, `:1025–1026`, `:1039–1040`, `:1042–1044`, `:1056`, `:1059`, `:1061`, `:1066–1067`.
- Tree: `Sources/SnapticKit/KitModules.swift:29–34` (`SentenceText.properNames` is an array); `Tests/SnapticKitTests/ConfigModulesTests.swift:80`.

**Proposal.** Put the corrected lists in the plan as §6.1, "K test lists". Appendix A below gives them in full. In each K done-when, replace "Appendix B's K*n* tests pass" with "§6.1's K*n* tests pass".

### P2-5 · Major · §6 A3, A6a, A6b, A2b · Done-whens need UI from later items, and `windows(for pid:)` has no item

**Finding.** Several checks named as done-whens need something a later item builds:

| Item | Check | Needs | Built in |
|---|---|---|---|
| A3 | M7 | "hover shows previews" | A4a (panel) |
| A3 | M8, M9 | "previews work again" | A4a |
| A3 | M10 | "that app shows titles" | A4a |
| A3 | M32 | "a preview shown" | A4a |
| A6a | M33 | a page row | A7 |
| A6a | M33 | diagnostics | A6b |
| A6b | M28 | the row text and Run Both Anyway (the Advanced sheet) | A7 |
| A2b | M35 | the stopped row on both pages | A7 (Dock page); nobody builds the switcher page's row |

Separately, `WindowManager.windows(for pid:budget:allowUntitled:)` (0.5 s budget, 2 s cache, the 30 s skip) has no owning item. S0-23 gates it but is listed only before K4.

**Evidence.**
- Items: PLAN:l.1077 (A2b), PLAN:l.1081–1082 (A6a, A3), PLAN:l.1086 (A6b).
- Checks: PLAN:l.1110–1113 (M7–M10), PLAN:l.1131 (M28), PLAN:l.1135–1138 (M32, M33, M35).
- `windows(for pid:)`: PLAN:l.220, PLAN:l.649–652. S0 gates: PLAN:l.1029.

**Proposal.**
- **A3 done-when:** "With the module on in a DEBUG build, and no panel yet:
  - diagnostics count selections and show the last `DockItemKind`, for a bottom, left and right Dock;
  - `killall Dock` ×10 gives `observer attached` and a re-attach count of 10;
  - a 5 s AX stall in one app keeps main under 16 ms (the S0-14 harness);
  - M21 passes;
  - `windows(for:budget:allowUntitled:)` meets S0-23's p95 for 10 windows."
- **§4.22 diagnostics** add "selection count and the last selection's `DockItemKind`".
- **A3 work column** adds "`WindowManager.windows(for pid:budget:allowUntitled:)` (§4.8)".
- **S0 gates:** S0-23 is listed before "K4 and A3".
- **A4a done-when:** "M7–M15, M19, M32 and M36 pass".
- **A6a done-when:** "`dock live` prints all zeros. M34 passes. In Safe Mode the module doesn't start and `dock live` stays zero."
- **A6b done-when:**
  - "With DockDoor running, `dock status` (DEBUG hook until A9) reports `otherTool` and no preview shows.
  - The diagnostics half of M33 passes.
  - M49 passes."
- **A2b work column** adds "the switcher page's stopped row with Try Again". Its done-when: "M5 and M6 pass. M35 passes on the switcher page."
- **A7 done-when** adds "M28, M33 and M35 (Dock page) pass".

### P2-6 · Major · §6 B1a, A1a · "M1–M4 pass" can't be checked at B1a or A1a

**Finding.**
- M2 needs "Dock Previews on", and the module is still the inert K1 shell.
- M3 needs Dock thumbnails to purge.
- M4's second half needs `Windows.disable.symbolicHotKeys`, which B1b adds.

Of M1–M4, only M1 and M4's first sentence can run at B1a and A1a. Separately, A1a's `selftest-launch: windows leases 0` duplicates A6a's `dock live … leases=0`.

**Evidence.**
- PLAN:l.1072–1074 (B1a, A1a, B1b), PLAN:l.1104–1107 (M1–M4), PLAN:l.958 (`dock live`).

**Proposal.**
- **B1a done-when:** "A move only, with no behaviour change. M1 passes, and ⌘⇥ takeover still works (M4, first sentence). Rule 11, L2 and `stubs.tsv` are updated."
- **A1a done-when:** "M1 and M4's first sentence pass. The `selftest-launch: windows leases 0` line prints, and A6a later folds it into `dock live`. `WindowLeaseLedgerTests` pass."
- **B1b done-when** adds "M4 passes in full".
- **A4a done-when** adds "M2 and M3 pass".

### P2-7 · Major · §4.12 selftest, B1b · "Every symbol `poisoned`, with its fallback answering" can't run in the selftest

**Finding.**
- The selftest can't exercise the fallbacks:
  - lint rule 9 bans AX calls in `SelfTestLaunch.swift`, which rules out the axWindowID and raise fallbacks;
  - a raise would move windows;
  - the capture fallback needs the store and a window.
- The plan doesn't say where the poison run sits in `run()`. The icons run (`SelfTestLaunch.swift:79–84`) comes after the availability check and leaves the shim poisoned for the rest of the process. The window run has to come after the window availability lines, or they print `poisoned`.
- `--selftest-launch` is DEBUG-gated only at `:244`. The plan's "both steps" applies only to the expect variable.

**Evidence.**
- PLAN:l.779–780, PLAN:l.775–776, PLAN:l.1074 (B1b).
- `Sources/Snaptic/Core/SelfTestLaunch.swift:73–84`.
- `scripts/lint.sh:102–110` (rule 9 regex includes `AXUIElement`).
- `.github/workflows/build.yml:244`, `:299`.

**Proposal.** Replace PLAN:l.779–780 with:

> - The DEBUG-only `PrivateWindowAPI.forcePoisonForSelfTest()` runs right after the window lines, as the icons poison run does (`SelfTestLaunch.swift:79–84`). It poisons every `WindowFeature`, calls no symbol, and prints `selftest-launch: windows poison path ok|failed`. The result is `ok` when every feature then reports `poisoned` and none reports `available`. Nothing after it uses a window symbol.
> - Each feature's fallback is a Kit table, `WindowSymbolContract.fallback(for:)`, tested in `WindowSymbolContractTests`. The fallbacks themselves run in M6, M16 and the S0 harness.
> - The poison run exists only in DEBUG builds, so only the debug selftest step (`build.yml:244`) runs it.

B1b done-when: "The window lines print. CI expects `available` at `build.yml:244` and `:299`. The debug step prints `windows poison path ok`. `WindowSymbolContractTests` pass."

### P2-8 · Major · H8 Rule 10, B1b · `extension PrivateSymbol` doesn't fit the window symbols

**Finding.** H8 says the window ids are `extension PrivateSymbol` in `PrivateWindowAPI.swift`, but `PrivateSymbol` is built for Displays:

- `features: Set<DisplayFeature>`.
- Function symbols require a framework path, but `_AXUIElementGetWindow`, `GetProcessForPID`, the CGS fallbacks, `IsSecureEventInputEnabled`, `LMGetKbdType` and `KBGetLayoutType` are looked up in `RTLD_DEFAULT` today.
- A built-in `killSwitchKey` of `Displays.disable.symbol.<name>`. That would give each window symbol a second, Displays-prefixed kill switch next to `Windows.disable.<feature>`.

Widening `PrivateSymbol` would touch the Displays code and its kill switches.

**Evidence.**
- PLAN:l.405 (Rule 10 row), PLAN:l.738, PLAN:l.761–769.
- `Sources/Snaptic/Displays/Platform/PrivateDisplayAPI.swift:12–51` (fields, `init(function:framework:features:)`, `killSwitchKey`).
- `Sources/Snaptic/Switcher/PrivateAPIs.swift:40–59` (`dlsym(nil, …)` lookups).
- `scripts/lint.sh:112–138` (`exempt = {"PrivateSymbol"}`).

**Proposal.** H8 Rule 10 row: "| Rule 10 | No change. The window symbols are a new `WindowSymbol` struct declared in `PrivateWindowAPI.swift`: `name`, `image` (nil = `RTLD_DEFAULT`, else a framework path), `feature: WindowFeature`. Its kill switch is `KillSwitches.key(prefix: "Windows", id: feature.rawValue)`. No extension crosses a file. | B1b |". In §4.12 step 1 (l.740), add "`WindowSymbol` (app) mirrors `WindowSymbolContract` (Kit)."

### P2-9 · Major · §4.10, H10 · The "WindowServices config slice" and the `dock` backup section are undefined

**Finding.**
- **The privacy slice.** "Protect private windows" and the protected apps "live in a `WindowServices` config slice", but no store, key, migration or backup path is given. Today they are switcher `Config` fields, backed up whole in the `switcher` section and read there by 0.4.0 after a downgrade.
  - A new store would need a migration, a backup path and a downgrade story.
  - A view onto the switcher's fields needs none of these.
- **The protected-app list can shrink on import.** That list is not in `unionPaths`, so an import can shrink it today. That breaks KitBackup's own rule ("a backup can't unprotect an app from captures"), and in 0.5 the list protects both modules.
- **Restore Defaults.** The Dock page's Restore Defaults resets "Advanced settings". The shared privacy controls are on that sheet, so as written it would reset the switcher's privacy too.
- **The `dock` section.** H10 names the section but gives no allowlist, `safetyPaths` or union rule. H7 adds only a field-name test.

**Evidence.**
- PLAN:l.707–708, PLAN:l.434, PLAN:l.888–890 (Restore Defaults text), PLAN:l.901–902 (Advanced rows).
- `Sources/Snaptic/Switcher/Settings.swift:254–256`; `Sources/Snaptic/Core/Backup.swift:46`, `:137–138`.
- `Sources/SnapticKit/KitBackup.swift:42` (`sections`), `:47–61` (`allowedPaths`), `:97–102` (`unionPaths` and its rule), `:106–139` (`safetyPaths`).
- `Sources/SnapticKit/Config/ConfigIcons.swift:81` (`exportedKeys` pattern).

**Proposal.** Replace PLAN:l.707–708 with:

> - **One store, two views (G-4).** "Protect private windows" and the protected apps stay the switcher `Config` fields `protectPrivateWindows` and `privateBundleIDs` (`Switcher/Settings.swift:254–256`). `WindowServices` reads them, and both Advanced sheets bind to them, so a change on one shows on the other. There's no new key, no migration and no backup change, and 0.4.0 reads them unchanged after a downgrade.
> - `KitBackup.unionPaths` gains `[switcher, "privateBundleIDs"]`, and `safetyPaths` gains `[switcher, "protectPrivateWindows"]`.
> - Neither Dock Restore Defaults touches these two. The confirmation adds "Private window protection doesn't change."

H10's `dock` bullet becomes:

> - `KitBackup`:
>   - `dockSection = "dock"` in `sections`;
>   - `allowedPaths[dock] = DockConfig.exportedKeys.map { [$0] }`, where `exportedKeys` is every `CodingKey`, the "Don't show previews for" list included, as the switcher exports `excludedBundleIDs`;
>   - `safetyPaths` gains `[dock, "clickActions"]`, `[dock, "keys"]`, `[dock, "runAlongsideOtherTools"]` and `[dock, "showWithVoiceOver"]`.
> - `Backup.swift` exports and imports the section (0.4 R3-81). M34 checks both.
> - K1 adds `testDockBackupSafetyPathsListedFirst` and `testDockExportedKeysAreEveryCodingKey`.

---

## Minor

### P2-10 · Minor · H8 L14, B1a · `ObserverThread` breaks L14 once `WindowManager` is under `Windows/`, and `DockObserver` can't reach it

**Finding.**
- L14 is unratcheted for new paths. It matches `forMode: .default`, and `ObserverThread` has exactly that at `WindowManager.swift:608`. K1 adds `Windows/` to L14's scope and B1a moves the file there, so `lint.sh --strict` fails at B1a.
- `ObserverThread` is also `private` to `WindowManager.swift`. §4.8 has `DockObserver` "on its own `ObserverThread`", and A1a moves `FocusTracker`, which uses it, into `WindowServices`.

**Evidence.**
- PLAN:l.399 (L14 row), PLAN:l.626, PLAN:l.1072.
- `Sources/Snaptic/Switcher/WindowManager.swift:600`, `:608`.
- `scripts/lint03.py:571–575` (L14); `scripts/lint-legacy.tsv` has no `Windows/` row.

**Proposal.**
- B1a's work column adds "extract `ObserverThread` to `Windows/ObserverThread.swift` (internal, unchanged)".
- H8 adds this row: "| L14 | Exempts `Windows/ObserverThread.swift`, whose run loop is its own thread's, kept alive by a port; no `.default` timer on main | B1a |".
- B1a adds a `stubs.tsv` row for the new file.

### P2-11 · Minor · H8 L20 · "Zero hits in `Switcher/` today" is wrong

**Finding.** L20 is unratcheted. It allows only `X.rawValue` interpolation in `.record(`. `WindowGatherer.swift:70` interpolates `moved`, so K1's scope change fails `--strict`. The L20 message also says "under Icons/".

**Evidence.**
- PLAN:l.402.
- `Sources/Snaptic/Switcher/WindowGatherer.swift:70` (`EventLog.shared.record(.switcher, "Gathered \(moved) windows")`).
- `scripts/lint03.py:723–763`.

**Proposal.** H8's L20 row:

> | L20 | Scope becomes `Icons/`, `Dock/`, `Windows/` and `Switcher/`. The message says "under Icons/, Dock/, Windows/ or Switcher/". K1 also changes `WindowGatherer.swift:70` to `record(.switcher, "Gathered windows", count: moved)`, or to a fixed string if `record` has no count field. That is the one hit today. | K1 |

### P2-12 · Minor · H3 · The caller list misses 13 sites and doesn't separate takers from givers

**Finding.**
- H3 lists `AppDelegate` and `Settings.swift` only. Thirteen sites are missing: nine `PrivateAPIs.` sites in `WindowManager.swift` and four calls in `WindowSwitcherModule.swift`.
- H6 needs to know which calls *take* ⌘⇥ (`apply`, `reassert`, `setSuspended(false)`) and which give it back. H3 doesn't say.
- H6 also misnames the heartbeat. The one that calls `reassert()` is `HostHeartbeat` on main (`AppDelegate.swift:72–74`), not a `HotkeyGuard` timer. That call needs a behaviour edit, a kill-switch check, which B1a's "move only" forbids.

**Evidence.**
- PLAN:l.361–362, PLAN:l.379–381.
- `WindowManager.swift:283`, `:379`, `:401`, `:452`, `:501`, `:531`, `:540`, `:589`, `:826`.
- `WindowSwitcherModule.swift:90`, `:219`, `:229`, `:231`.
- `AppDelegate.swift:72–74`; `Sources/Snaptic/Core/HostHeartbeat.swift:17–29`.

**Proposal.**
- Replace PLAN:l.361–362 with "Callers are updated: Appendix B's table."
- In H6 (l.379–381), change "the `HotkeyGuard` heartbeat" to "the `HostHeartbeat` tick at `AppDelegate.swift:72–74`". Add "B1b, not B1a, adds the switch check there."

### P2-13 · Minor · §4.12 step 1 · The image list misses HIServices and the `RTLD_DEFAULT` lookups

**Finding.** Step 1 names SkyLight and HIToolbox only. That leaves several symbols without an image:

- `_AXUIElementGetWindow` and `GetProcessForPID` live in HIServices or ApplicationServices.
- The CGS fallbacks are in SkyLight or CoreGraphics, depending on the OS.
- `IsSecureEventInputEnabled` and `LMGetKbdType` are found through `RTLD_DEFAULT` today.

With "`dladdr` says it lives in the expected image", these symbols have no expected image.

**Evidence.**
- PLAN:l.740–741.
- `Sources/Snaptic/Switcher/PrivateAPIs.swift:40–59`.

**Proposal.** Give the §4.12 table an **Image** column, filled from S0-5's `dladdr` results on 27.2 and 15, with this note: "An image that differs between 15 and 27 is listed with both. A lookup in `RTLD_DEFAULT` checks the image `dladdr` reports against this column."

### P2-14 · Minor · §4.12 steps 4–5 · No per-symbol result rule, a vacuous probe, and no state for a failed probe

**Finding.**
- Step 5 says results are checked "for its type's rule", but no rule is given per symbol.
- "`SLSIsSymbolicHotKeyEnabled` returns a Bool" is always true for a `Bool` return type, so the probe checks nothing.
- `setSymbolicHotKey` throws away its `CGError` today.
- The plan doesn't say whether a failed probe means `poisoned` or `unavailable`.

**Evidence.**
- PLAN:l.744–752.
- `Sources/Snaptic/Switcher/PrivateAPIs.swift:132–133`.

**Proposal.** Add a **Result rule** column to the §4.12 table:

| Symbol | Result rule |
|---|---|
| `CGSHWCaptureWindowList` | non-null, 1 image, size within 2 px of the bounds × scale |
| `_AXUIElementGetWindow` | `.success` and a nonzero id |
| raise symbols | `noErr` |
| `SLSMainConnectionID` | nonzero |
| `SLSCopySpacesForWindows` | non-null array |
| `Set`/`IsSymbolicHotKeyEnabled` | `CGError == 0` |
| `KBGetLayoutType` | one of the three known values |

Rewrite the probe line as "`SLSIsSymbolicHotKeyEnabled` for ⌘⇥ (id 1) agrees with `com.apple.symbolichotkeys` read from defaults". Add: "A failed probe sets the feature to `poisoned` for the process. `unavailable` means absent, wrong image or OS gate only."

### P2-15 · Minor · §4.12 step 4 · The probe window is unnamed, and "before first use" lands inside hot paths

**Finding.**
- The probes need "our own panel" or "our own patterned window", ordered in. No item creates such a window, and in the switcher-only setup there may be no panel at all.
- "Once per process, before first use" makes the first `windowID(of:)` call, inside `concurrentPerform` or the observer callback, run the probes.

**Evidence.**
- PLAN:l.744–750.
- `WindowManager.swift:354`, `:379`, `:589`.

**Proposal.** Replace PLAN:l.744 with:

> 4. **Probe**, once per process, on `WindowServices`' first acquire, on main. `PrivateWindowAPI` orders in a 64 × 64 borderless window with a fixed pattern at alpha 0.01 below the menu bar, runs the probes, and orders it out. Until the probes finish, every feature answers with its fallback.

B1b's work column adds "the probe window".

### P2-16 · Minor · §4.12 step 2, §5 · The OS gate admits 14 and 26, which S0 never runs

**Finding.** The gate admits macOS 14, 15, 26 and 27, but S0 runs on 27.2 and a 15 VM only. On 14 and 26, every symbol would be `available` with no recorded prototype or image.

**Evidence.**
- PLAN:l.742, PLAN:l.984 (S0 hosts), PLAN:l.990 (S0-5).

**Proposal.** Replace PLAN:l.742 with:

> 2. **OS gate.** The major version is one that S0-5 recorded (15 and 27 in 0.5.0). On 14 and 26, a feature is `available` only if an owner check runs S0-5's harness there before R and STEP0-NOTES records it. Otherwise it is `unavailable`.

The other choice is to add 14 and 26 legs to S0-5 and S0-17.

### P2-17 · Minor · H6 · "Read at each use" copies the persistent domain once per window

**Finding.**
- `KillSwitches.read` takes a `[String: Any]?` domain. Getting one means calling `UserDefaults.persistentDomain(forName:)`, which copies Snaptic's whole domain, every module's config included.
- "Before each private call" means one copy per window inside `concurrentPerform` and one per observer callback.
- The `KillSwitches` doc comment still lists four prefixes.

**Evidence.**
- PLAN:l.373–375.
- `Sources/SnapticKit/KitModules.swift:5–17`; `WindowManager.swift:354`, `:589`.

**Proposal.**
- Replace "before each private call, each tap enable and each capture batch" with: "once per batch: each window enumeration (`windows()`, `windows(for:)`), each capture batch, each raise, each tap enable and each ⌘⇥ take. A call inside a batch uses the batch's read."
- K1 updates the doc comment at `KitModules.swift:5–6` to list `Modules`, `Displays`, `Awake`, `Icons`, `Dock` and `Windows`.

### P2-18 · Minor · §4.12 selftest · Three other selftest steps don't set the expect variable

**Finding.** `--selftest-launch` also runs at `build.yml:316` (ASAN, on pushes), `:507–508` and `:1174–1175` (the signed app). The plan doesn't say what an unset `SNAPTIC_SELFTEST_EXPECT_WINDOWS_API` does. The house precedent for `SPARKLE` is that unset means report only.

**Evidence.**
- PLAN:l.777–778.
- `.github/workflows/build.yml:244`, `:299`, `:316`, `:507`, `:1174`.
- `Sources/Snaptic/Core/SelfTestLaunch.swift:13–15`.

**Proposal.** Add to PLAN:l.778: "Unset, the lines are only reported. The signed-app steps (`:507`, `:1174`) also set `=available`, because the shipped binary is the one that must find them."

### P2-19 · Minor · §5 gates · Three S0 rows gate the wrong item

**Finding.**
- S0-26 (freshness notifications) is gated before A2a, but A1b builds `.freshness(pid)`.
- S0-28 (pointer monitor cost) is gated before A5, but A4a installs the pointer monitor (§2.4).
- S0-23 gates K4 only, but the per-pid read it measures is app code (P2-5).

**Evidence.** PLAN:l.1024–1036, PLAN:l.1075, PLAN:l.283, PLAN:l.287.

**Proposal.** Use the gates table in Appendix C.

### P2-20 · Minor · §5 table · Most Blocker rows have no fallback, two can't fail, and S0-4's threshold is undefined

**Finding.**
- 20 Blocker rows have no decided fallback: S0-3, 5, 6, 7, 8, 10, 12, 13, 14, 17 (beyond capture), 18, 20(b), 20(c), 23, 25, 26, 29, 30 and 31.
- Without one, a failure stops the work while the plan is rewritten.
- S0-5 and S0-10 pass on "Recorded", so they can't fail.
- S0-4's "signature within 10 %" has no defined measure.

**Evidence.** PLAN:l.987–1020, PLAN:l.1041–1048.

**Proposal.** Add a **If it fails** column to the §5 table, using Appendix C. Define S0-4's signature as "the mean absolute difference of a 16 × 16 greyscale downsample against the drawn pattern, under 10 % of full scale".

### P2-21 · Minor · §6 · The stated critical path is wrong

**Finding.** The stated path runs B1b → A1b → A2b → A3 → A4a. But A3 doesn't need A2b, and A4a needs A2a's SCK path, not the private path. Then:

- A3 needs the real module (A6a), which the path skips.
- A2a, which A4a needs, is missing.
- A7 → A9 → D1 sits between A7 and R, and the path jumps from A7 to R.

**Evidence.** PLAN:l.1062–1065, PLAN:l.1072–1093.

**Proposal.** Add a **Needs** column (Appendix D) and replace PLAN:l.1065 with:

> **Critical path:** S0 → K1 → K4 → B1a → A1a → A1b → A2a → A4a → A4b → A7 → A9 → D1 → R. A6a → A3 and K3 join at A4a, and A5 and A6b join at A7.

### P2-22 · Minor · H1, H10 · Stale "A6" after the A6a/A6b split

**Finding.** H1 says the inert shell fills `ModuleHost.module(_:)` "until A6", and H10 says "A6 for the app". r1 Appendix A also assigns several dispositions to "A6".

**Evidence.**
- PLAN:l.354, PLAN:l.431.
- `review-r1-pressure.md` Appendix A ("Sites the grep misses").

**Proposal.**
- PLAN:l.354: "until A6a".
- PLAN:l.431: "K1 for Kit, A6a for the app; the Safe Mode details text in A6a, the page and menu strings in A7".
- K1's `H1-SITES.md` maps r1's "A6" to A6a.

### P2-23 · Minor · H1 · The "wider grep" isn't pinned, and `SettingsRootID` isn't a compile step

**Finding.**
- r1 Appendix A dispositions the narrow grep (1177 hits in 192 files at `7dd972c`) and recommends a wider one. That wider grep finds 1574 hits in 215 files, and the plan doesn't say which one K1 uses.
- `SettingsRootID` is a case-less `enum` of `static let`s. Adding a root breaks no exhaustive `switch`, so "filling … `SettingsRootID` is a K1 compile step" doesn't hold. Its groups and aliases need a grep step.

**Evidence.**
- PLAN:l.344–346.
- `review-r1-pressure.md:1081` (narrow), `:1219` (wide).
- `Sources/SnapticKit/SettingsShellRules.swift:7–24`.

**Proposal.** Replace PLAN:l.344–346 with:

> K1 creates `H1-SITES.md` from r1 Appendix A's recommended wide grep (pinned command; 1574 hits in 215 files at `7dd972c`; re-run at K1's base) and gives every hit a disposition. Filling every exhaustive `switch` over `ModuleID` and `NewModuleCard` is a compile step. `SettingsRootID`'s root list, groups and aliases (`SettingsShellRules.swift:7–24`) are a grep step, checked by `SettingsShellRulesTests`.

### P2-24 · Minor · §2.1 `CrashGuard` · The plan doesn't say whether Hidden Icons migrates to it

**Finding.** `CrashGuard` is "generalised from `IconsCrashGuard`". The plan doesn't say whether Hidden Icons moves to it, or whether `IconsCrashGuard` stays a separate type or becomes a typealias. A rename would touch `IconsModule.swift` and pinned 0.4 tests, and the plan doesn't list either.

**Evidence.**
- PLAN:l.207, PLAN:l.753.
- `Sources/SnapticKit/IconsEngineCore.swift:154–176`; `Sources/Snaptic/Icons/IconsModule.swift:32`, `:178`, `:1152–1156`; `Tests/SnapticKitTests/IconsEngineCoreTests.swift` (the `IconsCrashGuard` cases).

**Proposal.** Add to §2.1's `CrashGuard` line: "Hidden Icons keeps `IconsCrashGuard` unchanged in 0.5. `CrashGuard` is new, with its own tests. Merging them is §9."

### P2-25 · Minor · §4.21 · The duration grammar, "a second pause extends" and the verb × state replies are underspecified

**Finding.**
- **The parser.** `AwakeDurationGrammar.parse` also accepts `indefinite`/`forever`, `idle` and `until 17:30`, plus bare minutes and days, so "uses `AwakeDurationGrammar`" doesn't say which forms are allowed. Only `durationSeconds(_:)` limits it to durations.
- **"Extends."** "A second pause extends the first" could mean "adds to" or "replaces".
- **Unspecified replies.** These have no reply:
  - `pause` and `resume` in rows 4 (no Accessibility) and 5 (Dock not readable);
  - `resume` while VoiceOver also pauses;
  - `status` in each row.

**Evidence.**
- PLAN:l.939–952, PLAN:l.1080.
- `Sources/SnapticKit/AwakeClock.swift:220` onward (`AwakeDurationGrammar.parse`, `durationSeconds`).

**Proposal.** Replace the pause bullet with:

> `snaptic dock pause [duration]`: the duration is `AwakeDurationGrammar.durationSeconds` (`30m`, `2h`, `1h30m`, `90` = minutes), from 1 minute to 24 h. `forever`, `idle`, `until …`, `0` and over `24h` are usage errors (exit 2). A pause while paused by command sets the end to the later of the current end and now + duration.

Add a verb × state table to §4.21:

| Row | `status` | `pause` | `resume` |
|---|---|---|---|
| 1, 2, 3 (P2-2) | exit 2 | exit 2 | exit 2 |
| 4 | `needsPermission`, exit 0 | exit 5 "needs Accessibility" | exit 0 "isn't paused" |
| 5 | `unavailable dockUnreadable`, exit 0 | exit 5 "Dock Previews can't read the Dock." | exit 0 "isn't paused" |
| 6 | `paused otherTool`, exit 0 | exit 5 | exit 5 |
| 7 | `paused voiceOver`, exit 0 | exit 5 | exit 5 |
| 8 | `paused command until`, exit 0 | exit 0, extends | exit 0, then the next row that applies |
| 9 | `on`, exit 0 | exit 0 | exit 0 "isn't paused" |

---

## Appendix A · Corrected K test lists (for §6.1)

**K1** (`ConfigDockTests`, plus the pinned files of H7):
- `testIDOrderAndRawValue`, `testAllowedContainsFallbackForEveryID`, `testSanitizeOwnIconBecomesHidden`.
- `testFreshDefaultsDockOffInSnapticMenu`: off, `presence == .inSnapticMenu` (H7).
- `testDockCardGoesToUpgradersOnce`, `testDockCardSkipsFreshInstallsAcrossLaunches`, `testDockCardReachesZeroOneUpgraders`, `testSetEnabledClearsDockCard`.
- `testIconsNeedExternalDisplayIgnoresDockHidden`, `…CountsDockInMenu`.
- `testDockConfigDefaults`, `testSanitizeClampsDelay` (0…1; NaN → 0.2; ±∞ clamped).
- `testLossyEnumsFallBack`, `testEmptyObjectDecodesToDefaults`, `testRoundTrip`, `testFieldNamesAvoidTheSensitiveFragments`, `testBackupAllowlistRoundTrip`, `testDockExportedKeysAreEveryCodingKey`, `testDockBackupSafetyPathsListedFirst` (P2-9).
- `testA05ModulesFileDecodesWithUnknownValues`. Unknown module ids are already pinned by `ConfigModulesTests.testUnknownModulesSurviveARoundTrip` (`:80`), so there is no new test.
- `testEventCategoryDockExported`.
- `KnownDockToolsTests`: ids unique, exact match only, Snaptic's own id excluded.
- `SettingsShellRulesTests`: 9 roots, group order, `dock.…` resolves through the alias, bare `dock` doesn't.
- `KitModulesTests` (`SentenceText`):
  - `properNames.contains("Dock Previews")` and `.contains("Dock")`;
  - `inSentence("Dock Previews settings")` is unchanged;
  - `SentenceText.unit(1, "window") == "1 window"` and `unit(3, "window") == "3 windows"`.

**K2** (`DockGeometryTests`):
- Edge from the settled item frame for bottom, left and right, including a Dock on a secondary screen with negative x and a screen arranged above.
- AX → Cocoa round trip.
- Placement centred on the item, clamped with an 8 pt margin and a 6 pt gap, at each screen edge.
- The Dock zone and the corridor hull.
- Magnified frames: the panel doesn't move.
- Grid: one row for a bottom Dock, two columns for a side Dock.
- Cards that don't fit drop one size (Large → Medium → Small), then the panel scrolls. There is no "+N more".
- A fixed 16:10 card with the thumbnail letterboxed, checked for very wide and very tall windows.
- RTL mirroring.
- Fuzz over 10,000 cases: the panel is inside the visible frame, never overlaps the item, and every card is reachable by scrolling.

**K3** (`DockPreviewPolicyTests`, `DockClickRulesTests`):
- Delay 0.2 s; a new selection restarts it; delay 0 shows at once; no delay while shown (swap).
- Swap intent (S0-21's 20 diagonals as a table). A stale selection never shows.
- Corridor; grace 0.25 s (0.24 keeps, 0.25 hides); re-entry inside grace cancels the hide.
- Safety net 1 s.
- The latch: `mouseDownOutside`, `mouseDownOnItem`, `dragStarted`.
- Own menu and Dock menu suspend the timers, and closing restarts them.
- Every `DockDismissReason` of §2.4, one to one, and nothing for Mission Control (`.transient`).
- Auto-hide: S0-7's recorded order.
- Pause input: `pauseChanged(reason)` hides with `paused`. The state precedence itself is `DockPageRulesTests` (the 9 rows of §4.17, first applying row wins, one test per adjacent pair).
- Keys: `engageKeys(true)` only once engaged (inside and moved since entering, or clicked); `engageKeys(false)` on leave, hide, 10 s still, an unhandled key, or `switcherOpened`.
- Card clicks: left raises, middle closes. A card without an AX element offers only raise.
- `appTerminated(pid)` for the hovered app hides with `appTerminated`.
- Generation tokens: a stale `fired(token)` is ignored.
- Races: hover → leave → hover in one tick; swap during hide; `refresh` after hide.
- `DockClickRules`: the activation-history resolver table (§4.11).
- `grep -n 'Date()'` on both files is empty.

**K4** (`WindowCatalogRulesTests`, `WindowLeaseLedgerTests`):
- Inclusion (Y-3): minimized, hidden, windowless and full screen each on and off; floating panels, system dialogs and anything under 100 × 100 pt are left out.
- Other-Space with and without a title. `spaceKnown == nil` drops `CGWindowList`-only windows.
- Native tabs filtered. Stage Manager per §4.8.
- Privacy: protected app; private marker; browser with an empty title.
- Recency merge, and the Title sort (case- and diacritic-insensitive).
- Badges: Minimized > Full screen > On another Space > display name (only with more than one display). Hidden is a header flag, not a card badge.
- Freshness at 29.9 and 30 s. Retention at 30 min.
- Capture path choice: on-screen → SCK; minimized or other-Space → private if available, else last-seen, else icon.
- `hasAXElement == false` → raise only.
- The switcher's current inclusion cases, moved here.
- `WindowLeaseLedger`: union of needs, first-acquire and last-release edges, `.freshness(pid)` dropped 2 s after hide.
- LRU, budget and per-client cases move to `ThumbnailIndexTests` (A1b, P2-3). The capture cap of 4 is A2a's.

**K5** (`DockCommandGrammarTests`, `MenuLayoutTests`, `DockControlsTests`):
- Grammar:
  - `status`, `status --json`, `pause`, `pause 30m`, `pause 1h30m`, `pause 90`, `pause 24h` and `resume` parse.
  - `pause 25h`, `pause 0`, `pause x`, `pause forever`, `pause idle`, `pause until 17:30` and an unknown flag are usage errors (exit 2).
  - Help text.
- The §4.21 verb × state table (P2-25), as data.
- `MenuLayout`: short title "Dock"; `ownIconIDs` never contains `.dockPreviews`, even unsanitized; tabs with five modules; the existing fuzz passes with five.
- Controls: unique ids; all registered; `dockPresence` present; canonical strings; master switch for the `dockPreviews` root.
- "Registered only while the module runs" is an A9 `dockCases` check, not a Kit test.

## Appendix B · H3 callers (replaces PLAN:l.361–362)

| Site | Call | Feature | Takes or gives back ⌘⇥ |
|---|---|---|---|
| `AppDelegate.swift:58` | `SystemHotkeys.recoverFromPreviousRun()` | symbolicHotKeys | gives back (unguarded) |
| `AppDelegate.swift:71` | `HotkeyGuard.shared.start()` | none | starts the give-back timer |
| `AppDelegate.swift:72–74` | `HostHeartbeat` tick → `SystemHotkeys.reassert()` | symbolicHotKeys | **takes**; B1b adds the switch check and one `restore()` on the change |
| `AppDelegate.swift:131` | `SystemHotkeys.restore()` | symbolicHotKeys | gives back |
| `AppDelegate.swift:132` | `HotkeyGuard.shared.releaseAll()` | symbolicHotKeys | gives back |
| `AppDelegate.swift:221` | `releaseAll()` in the signal handler, off main | symbolicHotKeys | gives back; pre-resolved pointers, no defaults |
| `WindowSwitcherModule.swift:90` | `SystemHotkeys.restore()` | symbolicHotKeys | gives back |
| `WindowSwitcherModule.swift:219` | `SystemHotkeys.apply(…)` | symbolicHotKeys | **takes**, and gives back what is no longer wanted |
| `WindowSwitcherModule.swift:229` | `isSecureInputEnabled` | none (public) | none |
| `WindowSwitcherModule.swift:231` | `SystemHotkeys.setSuspended(blind)` | symbolicHotKeys | `true` gives back, `false` **takes** |
| `PrivateAPIs.swift` `HotkeyGuard.check()` | global-queue timer | symbolicHotKeys | gives back |
| `Settings.swift:37`, `:135` | `isISOKeyboard` | layoutType | none |
| `WindowManager.swift:283`, `:452` | `isOnAnySpace` | spaces | none |
| `WindowManager.swift:379` | `windowID(of:)` in `concurrentPerform` (`:354`) | axWindowID | none |
| `WindowManager.swift:401`, `:540`, `:826` | `windowID(of:)` | axWindowID | none |
| `WindowManager.swift:589` | `windowID(of:)` in the AX callback (`ObserverThread`) | axWindowID | none |
| `WindowManager.swift:501`, `:531` | `bringToFront` | raise | none |

## Appendix C · S0 fallbacks and gates

**If it fails** (Blocker rows without a decided contingency):

| Row | If it fails |
|---|---|
| S0-3 | The 30 s health check (§4.8) is the backstop. Known limitations names the event that needs it. |
| S0-5 | Pass becomes "every symbol is found in the §4.12 image on both OSes". A symbol missing on one OS is `unavailable` there, with its §4.12 fallback. |
| S0-6 | A level per context (Dock, full-screen Dock), chosen at show. If none clears a full-screen app's Dock, there are no previews over full screen (Known limitation) and M14 is dropped. |
| S0-7 | With auto-hide, show only after the Dock's frame has been unchanged for 0.1 s. The 1 s safety net covers a selection that doesn't clear. |
| S0-8, S0-12, S0-14, S0-31 | Must pass. A failure is a bug fixed before the gated item starts (S0-31: before R). |
| S0-10 | Pass becomes "every window class has a recorded source". A class with no source isn't listed (Known limitation). |
| S0-13 | The 1 s safety net and the `activation` and `space` hides cover it. Known limitations lists what's left. |
| S0-17 | A probe with a side effect becomes presence-only, like raise. A capture failure keeps the existing contingency. |
| S0-18 | Without Screen Recording, windows found only in `CGWindowList` (minimized, other Space) are dropped. AX-listed windows stay. |
| S0-20(b) | The Dock keys tap is never enabled while the switcher's tap is installed. If arrows still don't reach the switcher, Keys ships off. |
| S0-20(c) | Keys is removed from 0.5.0. |
| S0-23 | Show the `CGWindowList` list at once (titles, or the app name), then fill in AX rows within the 0.5 s budget. |
| S0-25 | A right mouse-down, or a 0.5 s press on an item, hides and latches for that item. Known limitation if the Dock's menu notification never arrives. |
| S0-26 | While the panel is up, a 1 s tick re-reads the hovered app. Nothing runs while it's hidden. |
| S0-29 | "Input keeps flowing; the tap is dropped" must pass. If `SLPSPostEventRecordTo` triggers the alert, the raise skips it on 27 (front process, then `kAXRaiseAction`). |
| S0-30 | `acceptsFirstMouse` on the card view. If it still takes two clicks, Known limitation. |

**Gates** (replaces PLAN:l.1024–1036):

| Rows | Before |
|---|---|
| S0-15 | K1 |
| S0-1, S0-2, S0-12 | K2 |
| S0-2, S0-7, S0-13, S0-16, S0-21, S0-22, S0-25 | K3 |
| S0-10, S0-11, S0-18, S0-23 | K4 |
| S0-4, S0-5, S0-17 | B1b and A2b |
| S0-26 | A1b |
| S0-19, S0-24 | A2a |
| S0-3, S0-8, S0-14, S0-23 | A3 |
| S0-6, S0-28, S0-30 | A4a |
| S0-27 | A4b |
| S0-9, S0-20, S0-29 | A5 |
| S0-31, S0-32 | R |

## Appendix D · Needs column for §6

| Item | Needs |
|---|---|
| K1 | S0-15 |
| K4 | K1 |
| B1a | K1 (the L14 and L20 rows) |
| A1a | B1a, K4 (`WindowLeaseLedger`) |
| B1b | B1a |
| A1b | A1a |
| A2a | A1b |
| A2b | A2a, B1b |
| K2, K3, K5 | K1 |
| A6a | K1, A1a |
| A3 | A6a |
| A4a | A3, A2a, K2, K3 |
| A4b | A4a |
| A5 | A4a, K3 |
| A6b | A4a, K5 |
| A7 | A4b, A5, A6b, K5 |
| A8 | A7 |
| A9 | A7, K5 |
| D1 | A9 |
| D2, D3 | D1 |
| R | all |

The critical path, with sizes: S0 → K1 (M) → K4 (M–L) → B1a (S–M) → A1a (M) → A1b (M) → A2a (M) → A4a (L) → A4b (L) → A7 (L) → A9 (S–M) → D1 (M) → R. K3 (L) has slack only while K4 → A2a is running.
