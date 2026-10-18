# Post-implementation review, round 1: fixes by team (lead)

Four fresh reviews (security, correctness, parity, integration) of feature/displays @93f35cc.
The lead already landed (feature/displays @e8b2653):
- `DisplayActionRegistry.perform` refuses actions whose feature isn't effective (toast).
- `DisplaySelectorResolver` (Registries/): **the** CLI display selector. Bare N = Identify/menu
  number (1-based, hidden included), `id:N` raw display id, 32-hex key, `main`/`mouse`/`focus`/`all`,
  name: exact match, then unique prefix, else `.ambiguous` (exit 2). `resolveForCLI(_:_:)` returns
  `(target, error)`. Every team replaces its own selector parsing with it.
- FeatureGraph: `osdBroadcast` uses `[.osd]`; `layouts` no longer uses `.brightness`.
- `DisplaysRuntimeState.reset()` clears the panic latch; new `sleepPreventionActive` flag.
- Self-test can't hang CI anymore; page titles "DDC & Monitor Controls", "Virtual Screens & HiDPI".

CLI exit codes everywhere must come from `ControlExit` (0 ok, 2 usage, 3 not found, 4 refused,
5 unavailable, 6 cancelled). Never 64/1 from a verb handler.

## A (host, CLI, backup, automation)
0. **The helper self-test hangs on the macOS runner** (even with scripts/selftest-helpers.sh bounded to
   ~18 s, the step hits its 2-minute timeout with no output; it passed earlier inside an XCTest). It is
   disabled in build.yml (`if: false`) — diagnose it on your branch (e.g. echo progress to stderr with
   `::error::` lines so it shows in annotations, run each phase separately), fix the real cause, and
   re-enable both steps in your branch (you may edit build.yml for this one change).
1. **Security M: helper parent check.** `HelperPrologue` must verify the parent against the helper's
   *own* designated requirement (`SNProcess.designatedRequirementOfSelf()`); drop `--requirement`
   from argv (HelperSpawner) or require byte equality with our own. Self-test and guard must still pass.
2. **Security M: backup import.** Switch `KitBackup` to an allowlist of importable paths (or add):
   `displays.management.autoDisconnectWithoutDDC`, `perDisplay.*.management.preventSleep`,
   `perDisplay.*.management.ignoreForAutoDisconnect`, `displays.color.allowGammaWithCustomProfile`,
   anything with "allow" in the key; `displays.pip.protectedBundlePrefixes` only ever union-merges.
   The preview lists every safety-related change first and in full. Tests.
3. **Security L: hook spawns.** While the hook child is suspended, refuse it if it satisfies our own
   requirement or carries our signing identifier; compare `proc_pidpath` vs the bundle with realpath
   + case folding; fail closed when the identifier can't be read.
4. **Security L: ControlServer** counts a slot in flight until the handler returns; client EOF cancels
   the handler's Task.
5. **Security L:** `ConfigStore.init` applies the same size cap as external changes; `KitControl`
   protected list adds `sleepprevention`/`preventsleep`.
6. **Security L (lead file, you may edit):** `HelperPipeWriter` — non-blocking fd, cap queued bytes
   (e.g. 1 MB), hitting the cap = broken pipe.
7. **Correctness:** `HelperSpawner.spawn` must not run `computeIdentity()` (canary + SecCode) on main:
   start `prepare()` at launch and make spawns before it finishes fail fast or wait asynchronously.
   Toasts bound to the host's app-long lifetime must not leak `onEnd` handlers (remove on dismiss).
8. **Parity:** MenuCustomizationPage gets a "Layout" section: compact/expanded, main first, badges,
   section order, display order (MenuConfig API; Display Names keeps its own order view or links here).
9. CLI host verbs: keep; make sure `list` numbers displays exactly like `DisplaySelectorResolver.ordered`.

## B (registry, transactions, guard, panic, session)
1. **Major: revert requested during settle is lost.** Add `revertRequested` to the pending trial; check it
   in the settle loop and before `panel.present`; treat as `.revert` (run `revertStaged`). Panic during
   settle must never end with the change kept. A new user request must not wait the old trial's 15 s.
2. **Major: restore journals never cleared** → replayed at next launch. Journal a `.restore` only when
   `long` is non-empty; clear when `updateLongArm` finds nothing to arm (and no trial), and in `deactivate()`.
3. **Major: user reconnects classified as trials.** Visibility-restoring changes (`.enabled(_, true)`,
   `.mirror(_, nil)`) are `.low` in `RiskClassifier` (Kit test).
4. **Major: guard trial deadline** starts before the staged apply. Call `guardClient.extend(id, seconds:)`
   right before `panel.present` so it becomes now + panel + 10.
5. **Minor:** `deactivate()` re-enables Snaptic-disabled displays synchronously (don't rely on a Task
   that `submit` refuses after deactivation). Guard-start timeout per waiter. Guard spawn + SecCode and
   the 500 ms `flush` must not block main except on quit. Hold
   `ProcessInfo.beginActivity(.userInitiatedAllowingIdleSystemSleep)` while a trial or long-armed state
   exists (App Nap could otherwise starve HostHeartbeat → guard thinks we hung).
6. **Security L:** SessionGate auth-window pid→path cache keyed on (pid, start time), or drop pids absent
   from the current window list.
7. Delete unused `PerDisplayIdentity.menuOrder`/`hiddenInMenu` (MenuConfig owns those). Panic CLI exit
   codes → `ControlExit`. Use `DisplaySelectorResolver` where you parse displays.

## C (brightness, DDC, keys, OSD)
1. `DDCController.setInput` / `setPower` guard `effective.contains(.ddcInput / .ddcPower)`.
2. `GammaService.deactivate()` must not drop BrightnessService's callbacks: lifetime-bound observer lists.
3. Remove OSDController's `attachedPresenter` workaround (graph now gives osdBroadcast the osd service).
4. `XDRController.availability`: static facts only (Apple silicon / XDR-capable model); keep the per-display
   EDR check where it runs.
5. **Security L:** `SNDDC.m` backstop denies 0xE0–0xFF unless the caller passes an unlocked flag; restrict
   0x8D and power values to the policy's.
6. CLI: aliases `toggle nightShift` (keep `night-shift`), generic `get` for brightness/contrast/volume/
   input/xdr where sensible; exit codes → `ControlExit`; selectors → `DisplaySelectorResolver`.
7. KeysController: action ids from constants (`DisplayActionID.dMirrorToggle`, shared C constants for
   volume/mute), not substrings. Avoid a double toast when `actions.perform` refuses (registry already toasts).

## D (resolution, arrangement, power, layouts, virtual)
1. LayoutsController DDC volume/input via `ctx.ddc.controller?.setFraction` / `setInput`, and capture both.
2. Quick menu: own id/descriptor `d.connectAll.quick`.
3. Remove ResolutionController's dead panic mode revert (B's queue does it); keep clearing `persisted`.
4. Parity: Tools "Arrange…" item (opens Arrangement page via `ctx.openSettings("displays.arrangement")`);
   underscan items in PanelPropsController's submenu; `PowerController.panicRestore` releases the sleep
   assertion and it isn't re-taken while latched; set `ctx.runtime.sleepPreventionActive`;
   `disconnect` labeled Experimental on Intel (availability text or a flag F can show).
5. CLI: `reconnect-all` alias for `connect all`; `toggle smartHiDPI` alias; selectors →
   `DisplaySelectorResolver`; exit codes → `ControlExit`.

## E (PIP)
1. Selectors → `DisplaySelectorResolver`. 2. Drop PIPController's own `screenIsLocked` observation
   (it's a SessionParticipant). 3. Exit codes → `ControlExit` (yours already match; verify).

## F (UI shell)
1. **Major:** panel/Overview resolution via D's `ctx.connectPlanner.resolution` (`modes(for:)`, `label`,
   `currentMode`, `apply(_:to:label:)`, `step`, slider helpers). Delete raw mode listing + `.mode` submit;
   keep `static systemModes` for onboarding. Drop F's outcome toasts (D shows its own).
2. **Major:** panel DDC via C's `ctx.ddc.controller?` (`setFraction(VCPPolicy.volume,…)`, `toggleMute`,
   `inputList`/`inputName`/`setInput`, `setPower`); delete F's own DDC reads/writes; rely on C filling
   `DisplayRuntime`.
3. **Major:** display rename + icon: `DisplayNameFields` → `PerDisplayIdentity.customName/.symbol/
   .lastKnownName`, `isSupported = true`, curated SF Symbol picker, `DisplayMenuBlock.symbol(for:)` prefers
   `identity.symbol`, offline displays show `customName ?? lastKnownName`.
4. **Major (parity):** EDID view per display (decoded summary via Kit `EDIDInfo.parse`, hex/Base64 copy,
   "Export .bin…" via save panel). Never in the copied diagnostics report. Bytes from B's
   `IORegistryDisplays` (read its API).
5. "Unprotected" banner: `ctx.guardClient.isUnprotected || ctx.helpers.unavailable != nil` (not `!isAlive`).
   Panic banner from `ctx.panic.isLatched`; drop F's duplicate "Resume" action (B's Tools item stays).
6. `DisplayMenuBlock.openSettings` → `ctx.openSettings(page)`. Badge for `ctx.runtime.sleepPreventionActive`.
   Overview/Diagnostics CLI exit codes → `ControlExit`.
