# Snaptic 0.2 plan: modules + Displays

Status: **r5** (= r4 + the R5 amendments below, which take precedence), revised after review rounds 1–3 and the macOS 27 research. Step 0a is merged and green: 853e18b on `feature/displays`, about 1.5 min per CI round. Appendix E maps every round-3 finding to its resolution.

**Normative code.** Snippets cited as **[R2C §x]** (`docs/design/R2C.md`) and **[R3C §x]** (`docs/design/R3C.md`) are binding; teams copy them. Where a snippet and this plan disagree, this plan wins; between two snippets, R3C wins.

**Precedence.** §13 (files), Appendix A (contracts)## R5 amendments (highest precedence; supersede anything in r4 they touch)

These amendments apply round 4: parity, security, code, platform and consistency, five verdicts of "ready with fixes".

**Appendix A is replaced by code.** From step 0b on, the Swift in `feature/displays` is the normative contract:
- `Sources/SnapticKit/KitModules.swift`, `FeatureGraph.swift`, `LayoutModel.swift`, `GuardProtocol.swift`, `VirtualHostProtocol.swift`, `Config/*`;
- `Core/ModuleContracts.swift`;
- `Displays/DisplaysContracts.swift`;
- `DisplaysContext.swift`.

Prose that disagrees with that code is wrong. Reviews of 0b check the code against this plan.

### R5.1 Contract placement (code B1, consistency B2/B3/M16)
- **Contracts files** (`ModuleContracts.swift`, `DisplaysContracts.swift`) hold **only protocols, enums and value types**. Every class lives in its own §13 file, created as a stub in 0b by the lead.
- **The r3 A.1/A.2 member lists are carried forward:**
  - `SnapticModule`: id, title, symbolName, summary, state, requiredPermissions, start, stop, menuSection, settingsPages.
  - `ModuleContext`, with an explicit init.
  - `SettingsPage`, `ConfigModel` (`init()`, `sanitized()`), `ControlPolicy` (`read`, `low`, `trial`, `preConfirm`).
  - `TransactionOutcome`.

  0b writes them out.
- **`StubError.notBuilt`** lives in Kit. Stub convention: safe returns (`nil` / `false` / `[]` / `.unavailable("Not built yet")` / 0), no `fatalError`, and every protocol requirement written explicitly. There are no default no-ops for `stop`, `deactivate` or `panicRestore`.
- **One `ConfigStore` per key, owned by the host for the app's lifetime.** Modules receive it; they never create stores.
- **Settings pages** are built only by the module through `SettingsPage(id:title:symbol:makeView:)`. Pages take a `DisplaysPageEnvironment` (context, config store, runtime state).
- **`DisplayMenuItemID` is an open `RawRepresentable` struct.** Contributors register descriptors `{id, title, defaultPlacement}`, and the Menu customization page lists the registered descriptors. Nothing needs freezing.
- **Ownership moves:**
  - `SNProcess` → A;
  - new `Core/HelperPrologue.swift` (A): signal resets, close fds ≥ 3, argument parse, parent check, stdin read source;
  - the transaction app types → `Displays/Safety/TransactionTypes.swift` (B);
  - `UndoOp`/`DisplayProperty`/`PropertyValue` → Kit `UndoPlanner.swift` (B);
  - `TrustStamp` → Kit `LayoutPresetModel.swift` (D);
  - `VirtualMode` → Kit `VirtualScreenSpec.swift` (D);
  - `HelperKind`/`HelperHandle` → `Core/HelperSpawner.swift` (A);
  - `DisplayTarget`/`Action` → `DisplayActionRegistry.swift` (lead);
  - OSD style/position → Kit `Config/ConfigKeys.swift` (C);
  - host CLI/General settings → Kit `Config/ConfigModules.swift` (A).
- **New files** after 0b are added to `scripts/stubs.tsv` in the same PR. Lint checks that the TSV and the tree match both ways.
- **The `TextSanitizer` move** carries the real implementation into Kit. `Switcher/*` gets `import SnapticKit`.

### R5.2 Guard and transactions (consistency B1/M1/M2/M3/M10/M11, platform M1/M3)
- **Trial deadline restored.** `armTrial(id:undo:deadlineSeconds:)` with deadline = 15 s panel + settle (≤ 5 s) + 10 s. The guard reverts a trial that has no `commitIntent` by its deadline. This works whether or not the app is long-armed or hung.
- **Hang actions** apply only to (a) armed trials and (b) long-armed states that impair visibility: displays Snaptic disabled, dim-to-black, overlay < 30%. **Healthy kept Smart HiDPI or association hosts are never killed for a hang.** The SIGKILL-parent rule is unchanged (≥ 30 s, plus dim condition, plus start time).
- **Trial apply** uses `trialScope` for every change and skips changes already equal to their target.
- **Keep** re-applies with the final scope and **never skips**: one `.permanently` batch (modes, origins, main) and one `.forSession` batch (mirrors, disable). Both run even if values are equal; that is the purpose of Keep.
- **One undo order** (`UndoPlanner.order`), used by both the guard and the app:
  1. enable;
  2. un-mirror;
  3. MonitorPanel steps in reverse (rotation before HDR);
  4. re-read modes;
  5. modes, origins, main.

  The undo sentence in [R2C §5.4] is superseded.
- **MonitorPanel unavailable:** if `ready.canMonitorPanel` is false, rotation, HDR and underscan trials are **refused** ("Safety helper can't revert this").
- **`DisplayGuardClient`:**
  - `ensureRunning()`, `armTrial(_:undo:deadlineSeconds:)`;
  - `extend`, `commitIntent`, `commit`, `disarm`;
  - `setLong(_ undo: [UndoOp], restoreColorSync: Bool)` (sends `.long`);
  - `busy(seconds:)`, `classification(_: [GuardDisplayClass])`;
  - `isAlive`.
- **Mirror membership counts both hardware and software mirrors** (`CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay`). Strongly visible covers a member of a set whose source is strongly visible or a live Snaptic virtual.
- **Unattended restore never modesets the only strongly visible display.** Any restore step that would change the mode of the only strongly visible display becomes a trial: shown at the next user presence, with toast "Restore 'Office'? Keep / Not now". Restore otherwise covers only origins, main, known-good modes, brightness and Smart HiDPI rebinds to the pair's own physical display (tier-1 fingerprint required). **Mirroring to other displays and auto-starting streams are never unattended**; they show a toast prompt.
- **`.permanently` while Snaptic virtuals are online:** protection and layout re-applies use `.forSession` (whether `.permanently` would persist the virtual mirrors is [U]; Appendix D 13). User Keep on physical modes stays `.permanently`.

### R5.3 ConnectPlanner (platform B1/M5, consistency M3/M4/M5/M6, code M6/M7)
- **Owner:** D (`Management/ConnectPlanner.swift`, runner). Kit `ConnectPlan.swift` (D) holds the pure planning function `plan(inputs: ConnectInputs) -> [PlanStep]`.
- **Trigger:** `DisplaysModule` calls `connectPlanner.trigger(.launch | .wake | .reconfigure | .sessionResume)`. Remove startup step 13 from `AppDelegate`.
- **Step 1, visibility restore:** **not coalesced**. It runs within 1 s of the registry event, and also in Safe Mode and while panic-latched. "Orphaned host" means the physical display is still missing **after the grace** (4 s; 30 s within 120 s of a wake or unlock). A host is killed at once only when no display is strongly or weakly visible and its 4 s grace has ended. "Kill host" is removed from the invariant-6 bypass list.
- **Guard coordination:** the guard acts on no-visible-display only when the parent heartbeat is more than 3 s stale. A healthy parent always handles it.
- **Steps 2–5** wait for 3 s of quiet (capped at 10 s). Rebinding a returning panel happens as soon as it appears.
- **Execution:**
  - Reconfigurations caused by the planner's own execution are ignored, for the duration of the run plus quiet + 1 s.
  - Plans run in two phases: create/rebind virtuals, re-snapshot, then compute the rest.
  - The rate limiter counts plans.
- **Safe Mode and panic latch** run step 1 only.
- **Panic** clears the persisted choice and known-good entry for every mode it reverts.
- **Persisted choice** learns from a non-Snaptic change only if it persists for 10 s and didn't happen within 15 s of a connect or wake (so it doesn't learn the 27.2 bug's mode).

### R5.4 Feature graph additions (consistency M7/M8/M9, parity M1/M2)
- **`FeatureGraph.permissions(_:)`:**
  - `brightnessKeys`, `volumeKeys` → accessibility;
  - `pip`, `pipFilters` → screenRecording;
  - the "Gather windows" action requests accessibility on use.
- **`resolve`** removes these features:
  - in Safe Mode: `xdr`, `sync`, `dimOnLock`, `sleepPrevention`, `protection`, `autoDisconnectBuiltin`, `hooks`, `customActions`;
  - while panic-latched: `protection`, `autoDisconnectBuiltin`, `hooks`.
- **Gated internally** (the feature stays effective):
  - Safe Mode: no virtual recreation, no Smart HiDPI re-establish, no layout auto-apply, no persisted choice, no automatic DDC writes (restore/sync). **User-initiated DDC writes are allowed in Safe Mode**, so keys keep working.
  - Panic latch: the same, until Resume.
- **Panic per feature:**

| Feature | Panic does |
|---|---|
| gamma / color / XDR B | ColorSync restore |
| overlays / XDR A / dim / menu-bar overlays | removed |
| Smart HiDPI / virtual mirrors | hosts shut down (unless headless-only) |
| disconnect | re-enable |
| rotation / HDR / underscan | **not touched** (needs a trial) |
| modes | revert the ones Snaptic set in the last 60 s |
| PIP / streams | stopped |
| sleep prevention | released |
| hooks | stopped |
| DDC | nothing |

  "Restore All Displays" = panic.
- **Kill switches:**
  - persistent-domain Bool keys `Displays.disable.<feature>`, read once at Displays start, not observed;
  - `PrivateDisplayAPI` maps each `PrivateSymbol` → the features that need it, and a missing symbol makes those features unavailable;
  - private symbols are registered when the module is constructed, and `availability(of:context:)` uses static facts only.
- **Exposure table:** each controller registers menu items, actions and CLI verbs.

| Feature | Menu | Action | CLI | Notes |
|---|---|---|---|---|
| resolution | slider + submenu | ±, HiDPI, native, default, halved, undo/redo, notch, favorites | `mode …` | |
| scaleMatch | Tools item "Match UI size…" | yes | `match-ui` | Applies once: preview, then a trial |
| brightness and methods | slider | ± | `set brightness` | |
| xdr | slider range, badge | toggle, ± | `toggle xdr` | |
| sync | toggle item | toggle | `toggle sync` | |
| color | submenu | ±, invert, reset, suspend | `set gamma` etc. | |
| colorProfiles | submenu | — | — | |
| nightShift | toggle | toggle, ± | `toggle nightShift` | |
| ddcControls | sliders | ± | `ddc`, `set volume` | Volume slider only if VCP 0x62 is supported |
| ddcInput | submenu | slots | `input` | |
| ddcPower | header switch | power | `ddc set d6` | |
| mainDisplay / arrangement / mirroring | items | set main, mirror | `main` / `arrange` / `mirror` | |
| rotation / underscan / hdrToggle | submenu | rotate, HDR | `rotate` | |
| disconnect | header switch | connect all, disconnect | `connect` / `disconnect` | |
| protection | toggle item "Protect arrangement" | toggle | `toggle protection` (off-only from CLI) | |
| layouts | Tools submenu | apply 1–9 | `layout …` | |
| virtualScreens | Tools submenu | toggles | `virtual …` | |
| smartHiDPI | per-display toggle | toggle | `toggle smartHiDPI` (off-only) | |
| pip | submenu | start/stop/hide/pause all | `pip …` | |
| menuBarOverlays | toggle | toggle | — | |
| sleepPrevention | toggle + badge | toggle | off-only | |
| hooks / customActions | actions list | per action | `cliAllowed` only | |

- **Naming:** the feature and controller id is **`layouts`**; page "Protection & Layouts"; Kit `LayoutPresetModel` (`SavedLayout`, `TrustStamp`); CLI `layout`. B's live types keep `LayoutEntry`/`LayoutSnapshot`.

### R5.5 Helpers and spawning (code M3/M4/M5, security R4-5/R4-6/R4-10)
- **`SNSpawn`** API per [R4C §4.1]: suspended spawn with stdin/stdout fds, disclaim option, `isStopped`, `responsiblePIDForPID`. `posix_spawnattr_setbinpref_np` is set to the running architecture (Rosetta).
- **The parent closes its copies of the child-side pipe ends** right after `posix_spawn`, on success or failure.
- **`HelperSpawner.spawn(_ kind:arguments:onLine:onExit:) throws -> HelperHandle`.** Sinks are attached before resume. The read source owns its fd.
- **Code identity:**
  - At launch: `SecCodeCopySelf` → static code → designated requirement, captured once.
  - Each spawned (suspended) child: `SecCodeCopyGuestWithAttributes(pid)` + `SecCodeCheckValidity` against that requirement.
  - Any mismatch → kill; helpers unavailable ("Restart Snaptic to finish updating").
  - Helpers check their parent with `SecCodeCheckValidity` against **their own** designated requirement. This fails after an update, which is acceptable and documented.
  - `Security.framework` is linked in Package.swift.
- **TCC API lint:** helper, CLI and self-test files (`DisplayGuardMain`, `VirtualHostMain`, `CLIClient`, `SelfTest`, `HelperPrologue`) may not reference `AXIsProcessTrusted*`, `CGRequestScreenCaptureAccess`, `CGPreflight*`, `SCShareableContent`, `SCStream`, `AXUIElement*`.
- **Self-test:**
  - built in all configurations;
  - requires `--selftest-helpers` **and** a parent check that the caller is the CI runner script (env `SNAPTIC_SELFTEST_TOKEN` equal to the contents of a token file the CI step created at a path passed in argv);
  - it never touches TCC;
  - the CI universal release job runs it too.

### R5.6 Smart HiDPI and virtual specifics (platform M4, minors)
- **Creation:** `maxPixels` = 2 × the largest mode, with the single initial mode. If the HiDPI check fails, recreate with `maxPixels` = 2 × the initial mode, and limit the slider to modes ≤ initial.
- **Removal:** a virtual whose mode changed is removed by `shutdown` → 1 s → SIGKILL. No "verify gone" wait.
- **Primaries** come from EDID chromaticity first, then ICC. **The physical's ICC profile is not set on the virtual by default** (that collides with the custom-profile safeguard and with a known black-on-wake problem on 27). Snaptic's own virtual identities are exempt from the safeguard.
- **API:** `VirtualHostsService.create(spec:initialMode: VirtualMode)`, `setModes(_:for:)`. The host protocol includes `setModes`.
- **Relaunch** recreates virtuals through the planner. The relaunch UI warns: "Virtual screens will briefly disconnect".

### R5.7 Security amendments (security R4-1..12)
- **Install:**
  - `INSTALL=1` installs root-owned: `sudo ditto` + `chown -R root:wheel`, with a prompt.
  - The README documents why, and recommends Developer ID builds.
  - `PermissionFlow` shows the running bundle's signer ("ad-hoc", or "Developer ID: …") and warns if the bundle path is user-writable before a grant.
- **App mode:**
  - Allowed arguments are exactly `--safe-mode`, `--relaunch-from <pid>`, `-psn_*`. Every other argument → exit 64, including `-NS*`/`-Apple*`.
  - The environment is refused (explain and exit) if it contains a variable with any of these prefixes: `CF`, `NS`, `OS_ACTIVITY`, `OBJC_`, `Malloc`, `LIBDISPATCH`, `SWIFT_`, `DYLD`, plus `CFFIXED_USER_HOME`. HOME must match `getpwuid_r`.
  - stdout and stderr are redirected to /dev/null at startup.
- **Logging rule:** no TCC-derived data, titles or app names in `print`/`NSLog`/`os_log`/`fatalError`/`precondition` messages. The lint bans `print(` and `NSLog(` outside `CLIClient`.
- **Trust stamps** give integrity, not authentication (documented). The match set is the displays the layout **references**, by tier 1; tier 2 (UUID) is allowed with a "no serial" warning. A missed toast leaves a menu item "Apply 'Office' (matches now)".
- **Lock-holder dialog:** "Quit the other copy" only if the holder pid passes our designated requirement.
- **Auto-disconnect built-in** requires the external display to be DDC-reachable with power "on", or Apple native. Otherwise it is refused, unless the user ticks "My monitor has no DDC". This prevents dummy-plug blackouts.
- **Gather windows** shows a confirmation toast before acting when triggered by a shortcut.
- **Auth windows:**
  - full-path matching;
  - zero-alpha and offscreen windows ignored;
  - `loginwindow` counts only while the session is locked;
  - while an auth window is present, order out **all** full-screen overlays **and raise any gamma dim-to-black to ≥ 30%**;
  - re-check every 2 s, at most 60 s per episode.
- **The DisplayKey salt** lives in persistent-domain key `SnapticDisplaySalt` and is never exported.

### R5.8 Parity/UX amendments (parity R4 B1, M1–M6, minors)
- **Built-in disconnect hazard table** (Kit `BuiltinDisconnectPolicy`): iMacs (all) and base-M3 models (`Mac15,3`, `Mac15,4`, `Mac15,5`, `Mac15,12`, `Mac15,13`, [U] list) → built-in disconnect and auto-disconnect **unavailable** ("Reconnecting may need a restart on this Mac"). Plus an Appendix D test.
- **macOS 27 control surface:**
  - The Displays Overview page has live controls per display (brightness, volume, resolution, input, power).
  - The "show menu" action opens a **floating Displays panel** at the pointer (the same controls), because a status item in overflow can't be opened.
  - While Settings is open the app becomes `.regular` (Dock and ⌘Tab), and returns to `.accessory` on close.
- **Overlays on non-wired transports** (DisplayLink, AirPlay, Sidecar, foreign virtual) use `sharingType = .readOnly`. Those drivers capture the screen, and `.none` would hide the dimming from the device.
- **Ledger corrections:**

| Item | Status |
|---|---|
| Periodic DDC readback | In (per-control interval) |
| LG alt input | In |
| Header "Screen Control" | = DDC standby |
| Streaming | **Partial** (no cursor exclusion) |
| Third-party OSD dispatch | **Partial** (Snaptic's own broadcast format) |
| Shortcut list | In per §8.2 |

- **OSD on 27** defaults to the **top-center** position (top-right stacks on the system HUD).
- **"More" chip** no longer includes `protection` or `osdBroadcast`.
- **Volume slider** only when VCP 0x62 is supported. CLI exit codes are listed in the README.
- **Sync:** an external DDC change is detected only when readback is on (documented).
- **Toasts:**
  - bound to a `Lifetime` with a 10 s expiry, so Undo can't run after `stop()`;
  - non-activating; clicks accepted;
  - VoiceOver announces them;
  - one at a time, queued.
- **VCP 0xD6 = 1** (power on) moves to **Safe**.

---

 and §14.3 (team rules) win over prose elsewhere.

---

## 0. Summary

Snaptic becomes a modular utility suite: one menu-bar app with independent modules.

1. **Window Switcher**: today's app, with per-feature switches.
2. **Displays**: a clean-room, MIT-licensed take on BetterDisplay + Pro.

Users choose modules, and features inside modules. A feature that is off costs nothing: no taps, timers, observers, IOKit handles, private-API calls, helper processes or permission prompts.

Priorities, highest first:
1. Never leave the user without a usable display, a working keyboard, or a way back.
2. Nothing Snaptic does may let another process use Snaptic's permissions, or see data obtained with them.
3. Never damage a monitor.
4. Parity.
5. Polish.

0.2 ships when every In-scope item in §2 is implemented and CI is green. §14's steps are build order, not cut lines.

## 1. Constraints

- **Package and toolchain.**
  - SwiftPM, tools 5.9, Swift 5 mode, macOS 14+, AppKit + SwiftUI (`ObservableObject`), no Xcode project.
  - Not sandboxed. Hardened runtime. **No entitlements.** Universal binary.
- **Compiler: GitHub Actions only.**
  - macOS: Xcode 16.4 (macOS 15 SDK).
  - Linux: `swift:5.10-jammy` on `ubuntu-24.04`, building SnapticKit only.
  - No Swift 6.0-only syntax.
- **No hardware testing before merge.** Every private API is:
  - resolved at runtime;
  - encoding-checked (Kit `KitEncoding`, BOOL `B`≡`c`);
  - behind a kill switch;
  - fail-closed.

  Hardware-dependent features are **Beta**. Appendix D is the first hardware session.
- **Supported macOS:** 14, 15, 26, 27.
- **License:**
  - All code is new.
  - MIT/BSD projects may be studied; logic followed closely is credited in `THIRD_PARTY_NOTICES.md`. Credits so far: MonitorControl, m1ddc, displayplacer, force-hidpi, Chromium.
  - GPL code is never read.
  - No BetterDisplay names, icons or identifiers.
- **Signing.** Ad-hoc builds lose TCC grants on every update; the docs say so. Developer ID signing and notarization are a release-process item, outside this plan's code scope; README "Security" documents both.

### 1.1 macOS 27 (`macos27.md`)

1. **Permissions.**
   - "Device Control and Data Access" is the renamed Accessibility pane [V/O]. `Permission` has two cases; the display name is OS-aware.
   - **`PermissionFlow`** (A, one per permission, coalescing callers, bound to a `Lifetime`), in this order:
     1. call `AXIsProcessTrustedWithOptions(prompt)` once per flow;
     2. always open the pane too; the text notes that the link may not navigate if System Settings is already open;
     3. show the exact app path, with "Show Snaptic in Finder" so the user drags *this* bundle (never a lookalike), plus "Click +";
     4. poll `AXIsProcessTrusted()` at 1.5 s while the window is open, and resume on app activation; stop on grant, on lifetime end, or after 10 min ("Check again");
     5. show **"I turned it on — Relaunch Snaptic"** as soon as the pane has been opened.
   - **Stale grants.** If the toggle is on but Snaptic is still untrusted after 30 s, show "Remove Snaptic with −, then add it again".
   - **Onboarding resumes** from a saved step after relaunch.
   - **Translocation.** If Snaptic runs from a translocated path (`/private/var/folders/…/AppTranslocation/`), tell the user to move it to Applications before granting.
2. **Event taps.**
   - On `tapDisabledBy*`, a tap re-enables only if `AXIsProcessTrusted()`. Otherwise it stops itself (deferred off the callout) and hands off to `PermissionFlow`. This applies to the switcher's `HotkeyTap` too.
   - `MediaKeyTap` decides once per press (on the initial key-down) and gives repeats the same verdict. Key-up always passes, and orphan repeats are ignored.
3. **OSD.** Our HUD is the default on 26+. Style ("Rounded 27" or "Classic") and position are separate settings. On 27 the default position is the top-right corner, because a hidden status item can't be detected [V].
4. **Menu bar.** Status items may be hidden by the system, so every function is reachable through:
   - Settings;
   - shortcuts (Carbon);
   - the CLI;
   - relaunching Snaptic (opens Settings).

   No 27-SDK APIs.
5. **Capture.** ScreenCaptureKit only.
6. **Gamma.** The M5 no-op bug is still open. The affected-models table has no upper OS bound.
7. **Displays.** 27.2 has an arrangement-restore bug; protection handles it (§9.6).
8. **Switcher hardening** (A, step 1):
   - full-screen and Mission Control detection ignores hidden or zero-alpha windows at system layers;
   - AX observer cleanup on app quit;
   - tap trust checks;
   - `CGWindowListCreateImage` never used.
9. **Toolchain.** Xcode 16.4 for 0.2.

## 2. Scope

### 2.1 Feature graph (Kit `FeatureGraph.swift`; `DisplayFeature: String`)

**Columns:**
- **Def:** `A` always on with the module, `S` standard (on), `O` opt-in, `X` experimental.
- **Req (all) / Req (any):** turning a feature on also turns these on. For Req (any), it picks the first entry that is available on this Mac, otherwise the first listed.
- **Uses:** services (§3.6).
- **Ctl:** the `DisplayControllerID` that serves the feature; Kit data, exclusive, tested.
- **Page:** the settings page.

| ID | Feature | Def | Req (all) | Req (any) | Uses | Ctl | Page |
|---|---|---|---|---|---|---|---|
| `overview` | Overview, identity (rename, icon, hide, order), identify, forget / transfer / forget-all | A | — | — | registry | overview | Overview |
| `diagnostics` | Report, EDID, API table (+ DDC caps when `ddc` active) | A | — | — | registry | diagnostics | Diagnostics |
| `resolution` | Modes, slider, refresh, HiDPI toggle, native/default/native-halved, undo/redo, favorites, range limit, notch, persisted choice | S | — | — | registry, transactions | resolution | Resolution |
| `hiddenModes` | Show all modes (CGS) | X | resolution | — | transactions | resolution | Resolution |
| `scaleMatch` | Match UI size | O | resolution | — | transactions | resolution | Resolution |
| `brightness` | Combined slider | S | — | brightnessApple, brightnessDDC, brightnessGamma, brightnessOverlay | brightness | brightness | Brightness |
| `brightnessApple` | Method: Apple native | S | — | — | appleBrightness | brightness | Brightness |
| `brightnessDDC` | Method: DDC | S | — | — | ddc | brightness | Brightness |
| `brightnessGamma` | Method: gamma | S | — | — | gamma | brightness | Brightness |
| `brightnessOverlay` | Method: overlay | S | — | — | overlays | brightness | Brightness |
| `brightnessRestore` | Restore on launch/wake (brightness / adjustments only / off) | S | brightness | — | — | brightness | Brightness |
| `dimToBlack` | Allow dimming to black | O | brightness | brightnessGamma, brightnessOverlay | guardProcess | brightness | Brightness |
| `dimOnLock` | Dim on lock/screensaver (gamma) | O | brightness, brightnessGamma | — | — | brightness | Brightness |
| `nits` | Nits display with ranges | O | brightness | — | — | brightness | Brightness |
| `xdr` | XDR extra brightness | O (Beta) | brightness | — | edr | xdr | Brightness |
| `sync` | Brightness sync | O | brightness | — | — | sync | Brightness |
| `autoBrightness` | Built-in auto-brightness toggle | X | — | — | appleBrightness | systemColors | Color |
| `color` | Software adjustments | O | — | — | gamma | color | Color |
| `colorProfiles` | Profile picker + actions | O | — | — | colorSync | systemColors | Color |
| `nightShift` | Night Shift | X | — | — | — | systemColors | Color |
| `applePresets` | Apple display presets (select) | X | — | — | monitorPanel | systemColors | Color |
| `ddcControls` | DDC controls, caps, per-control tuning | S | — | — | ddc | ddc | DDC |
| `ddcInput` | Input switching + input list | O | — | — | ddc | ddc | DDC |
| `ddcPower` | DDC standby / power-on | O | — | — | ddc | ddc | DDC |
| `ddcCustom` | Custom VCP controls, raw get/set | O | — | — | ddc | ddc | DDC |
| `brightnessKeys` | Brightness keys (externals, XDR) | O | brightness | — | mediaKeys | keys | Keys & Shortcuts |
| `volumeKeys` | Volume/mute keys → DDC | O | ddcControls | — | mediaKeys | keys | Keys & Shortcuts |
| `shortcuts` | Custom shortcuts | S | — | — | — | keys | Keys & Shortcuts |
| `osd` | On-screen display | S | — | — | osd | osd | OSD |
| `osdBroadcast` | OSD broadcast (output only) | O | — | — | — | osd | OSD |
| `mainDisplay` | Set main | S | — | — | transactions | arrangement | Arrangement |
| `arrangement` | Canvas + Position/Align | S | — | — | transactions | arrangement | Arrangement |
| `mirroring` | Mirror set/stop | S | — | — | transactions | arrangement | Arrangement |
| `rotation` | Rotation | O (Beta) | — | — | monitorPanel, transactions | panelProps | Arrangement |
| `underscan` | Underscan | X | — | — | monitorPanel, transactions | panelProps | Arrangement |
| `hdrToggle` | HDR on/off | X | — | — | monitorPanel, transactions | panelProps | Arrangement |
| `disconnect` | Soft disconnect, header power switch | O (Beta; X on Intel) | — | — | transactions, guardProcess | power | Arrangement |
| `autoDisconnectBuiltin` | Disconnect built-in when an external connects | O | disconnect | — | guardProcess | power | Arrangement |
| `protection` | Configuration protection | O | — | — | transactions | protection | Protection & Presets |
| `presets` | Display layouts (presets) + auto-apply | O | — | — | transactions, brightness | presets | Protection & Presets |
| `virtualScreens` | Virtual screens | O (Beta) | — | — | virtualHosts, transactions | virtual | Virtual Screens & HiDPI |
| `smartHiDPI` | Smart HiDPI | O (Beta) | — | — | virtualHosts, transactions, guardProcess | smartHiDPI | Virtual Screens & HiDPI |
| `hdrVirtual` | HDR virtual modes | X | — | virtualScreens, smartHiDPI | virtualHosts | virtual | Virtual Screens & HiDPI |
| `pip` | PIP + streams | O | — | — | capture | pip | PIP |
| `pipFilters` | Filters + LUTs | O | pip | — | capture | pip | PIP |
| `menuBarOverlays` | Menu-bar strip, rounded corners | O | — | — | overlays | menuBarOverlays | Color |
| `sleepPrevention` | Prevent display sleep | O | — | — | — | power | Arrangement |
| `hooks` | Event hooks | O | — | — | spawner | automation | Automation |
| `customActions` | Custom actions | O | — | — | spawner | automation | Automation |

**`DisplayControllerID`** (Kit):
- `overview`, `diagnostics`, `resolution`;
- `brightness`, `xdr`, `sync`, `color`, `systemColors`;
- `ddc`, `keys`, `osd`;
- `arrangement`, `panelProps`, `power`, `protection`, `presets`;
- `virtual`, `smartHiDPI`, `pip`, `menuBarOverlays`, `automation`.

There is one controller class per id. The table above is the controller map.

**Rules:**
- **Effective set:** `FeatureGraph.resolve(raw:killSwitches:safeMode:unavailable:panicLatch:)` (Kit types only, per [R3C §2.1]) computes it. Controllers see only effective features.
- **Turning on:** sets the raw flag, plus the raw flags it requires, with a notice. **Turning off:** clears only that raw flag. Dependents stay on in raw, drop out of the effective set, and their pages show "Needs X".
- **Brightness:** `brightness` with every method off is not effective ("Choose a brightness method"). XDR method B needs `brightnessGamma` effective; method A needs `brightnessOverlay`. With neither, XDR is unavailable, with the reason shown.
- **Per-display field gating:**
  - dim on lock is unavailable where the active method is overlay;
  - HDR and underscan trials are refused on the only strongly visible display;
  - presets and protection skip fields whose feature isn't effective, and show a note.
- **Tests:**
  - closure for every feature;
  - 10,000 seeded random subsets;
  - requirement neighborhoods;
  - controller exclusivity and totality;
  - start/stop idempotence on simulated services.

### 2.2 Window Switcher features

`Config.disabledFeatures: Set<SwitcherFeature>` (lossy). Stored settings are never rewritten.

The **Features page is the only place for on/off toggles.** The `previewSelected`, `selectOnHover` and `showOtherSpaces` toggles move out of Behavior and Thumbnails into Features (bound to the same keys), so nothing appears twice.

| Feature | Disabled means | Cost removed |
|---|---|---|
| `thumbnails` | All shortcuts render icons; no live preview | SCK, Screen Recording request, ThumbnailStore, privacy observers |
| `preview` (`previewSelected`) | No full-size preview | Preview overlay |
| `otherSpaces` (`showOtherSpaces`) | Current Space only | — |
| `windowlessApps` | Hidden everywhere (overrides per-shortcut) | — |
| `search` | S and `/` do nothing while the switcher is open (swallowed) | — |
| `actionClose` / `actionMinimize` / `actionFullscreen` / `actionHide` / `actionQuit` | Key does nothing while open (swallowed); hint line and buttons omit it | — |
| `hoverButtons` | Not drawn | — |
| `hoverSelect` (`selectOnHover`) | Off | — |
| `commandTabTakeover` | ⌘-shortcuts disabled with a note | SystemHotkeys untouched |
| `passthrough` | Exceptions ignored | — |

Keys pressed **while the switcher is open** are always swallowed (today's behavior). Disabled actions never reach the window behind.

Always on: VoiceOver and the secure-input watcher. Without Accessibility the module is `degraded` and only `PermissionFlow` runs.

### 2.3 Deferred

| Item | Re-entry criterion |
|---|---|
| System overrides (scale-resolutions, default res, name, TV role → Night Shift for TVs, flexible scaling via overrides) | Root installer with no temp files, marker-checked removal, UI-only start, security review |
| Connection color mode, direct XDR control | Research spike in step 5 (read-only DCP dump), owner D |
| Framebuffer grayscale/invert, e-book look, keyboard backlight keys, Night Shift/True Tone off in HDR | Private |
| 3D LUT on displays, compositor filters, Video Filter Window, self-stream with filters | 1D gamma only; private compositor |
| App Intents, AppleScript, URL scheme | Phishing/identity risks; the CLI covers Shortcuts |
| HDMI-CEC, network TVs/AVRs, DisplayLink controller, HTTP-based Stream Deck plugins | Protocols we can't test; no HTTP |
| Raw lux, True Tone, Dark Mode | Private or an entitlement |
| Nits-normalized sync, custom groups beyond layouts + sync | UI size |
| Console, refresh reporter, Intel color depth, link info | Low value or private |
| SDR/HDR auto profile switching, profile protection | Needs the HDR toggle validated |
| Ranged/toggle custom controls with value placeholders and readback | Value injection into executables; command actions ship |
| PIP tabs/merge, magnification > 100%, "bring to mouse screen" | UI size |
| Virtual-screen identity editing, step multiplier, "HDR modes only", follow orientation, 270° portrait, menu icon/ordering for virtuals | UI size |
| Localization | Translation effort; `L()` everywhere |
| Swap identical displays, Sidecar management | Identity risk; private |
| Sidebar/detachable menu presentations | UI size |

### 2.4 Excluded by design

| Item | Reason |
|---|---|
| EDID write/override | Can brick a monitor or blank it |
| Reinitialize, VMM7100 reset, forced HDR, mixed color modes, dithering, uniformity, forced underscan | Private; blanks screens |
| HTTP server, distributed-notification commands | Unauthenticated |
| NVRAM reset, factory profile removal | Destructive; needs root |
| Model adaptations | Hardware-specific |
| Telemetry, crash upload, licensing, network update checks | Snaptic never connects; "Check for updates" opens Releases |

Appendix C is the full ledger.

## 3. Architecture

### 3.1 Targets

- **Manifest:** the conditional manifest [R2C §3.2], as merged in 0a.
- **SnapticKit:** Foundation-only.
  - Contents: all pure logic, every config model, every protocol message, every shared id type (§A.0).
  - `package` on every declaration. The banned-API lint is in place.
  - `LossyMap` sorts its keys before the 256 cap, and has `dropUnknown(keepingAtMost:)` [R3C §6 m1–m2].
- **SnapticShims:** Objective-C (ARC guard). Per-area headers (§13).
  - `NS_ASSUME_NONNULL`, class methods with `NSError**`, `@try` only inside `.m`, sticky poison per area.
  - Create/Copy functions are typedef'd `CF_RETURNS_RETAINED` + `CFBridgingRelease`.
  - The shim returns raw type encodings; **Kit `KitEncoding` compares them** (Linux-tested). `SNEncoding encoding:matches:` is removed in 0b.
- **Snaptic:** the executable.
- **SnapticKitTests:** XCTest; seeded fuzzing; compare decoded values.

### 3.2 Process model

`main.swift` contains only `SnapticEntry.run(CommandLine.arguments)`. `SnapticEntry` (A) dispatches **before** `MainActor.assumeIsolated`, and the helper branches skip the app self-checks:

| `argv[1]` | Entry point | Owner |
|---|---|---|
| `--display-guard` | `DisplayGuardMain.run` | B |
| `--virtual-host` | `VirtualHostMain.run` | D |
| `cli`, or `basename(argv[0]) == "snaptic"` | `CLIClient.run` | A |
| (debug builds only) `--selftest-helpers`, `--selftest-child` | CI fd-inheritance test (§14.1) | A |
| anything else | app mode, after **argument and environment validation** | — |

**App-mode validation:**
- Allowed arguments: `--safe-mode`, `--relaunch-from <pid>`, `-psn_*`, and AppKit/LaunchServices `-NS*`/`-Apple*` pairs (ignored).
- Anything else → exit 64.
- If `CFFIXED_USER_HOME` is set, or `HOME` differs from `getpwuid_r(getuid())`'s home → explain and exit.
- Lock, config, journal and socket paths all derive from `getpwuid_r`.

**Helper launch.** Helpers (guard, virtual hosts) are launched by **`HelperSpawner`** (A, Swift) on top of `SNSpawn` (A, shim). There is no `Process`.

*Spawn attributes:*
- `posix_spawn` with `responsibility_spawnattrs_setdisclaim(attr, 1)`;
- `POSIX_SPAWN_CLOEXEC_DEFAULT` + `SETSIGDEF` + `SETSIGMASK`;
- explicit `dup2` file actions for stdin (request pipe), stdout (reply pipe) and stderr (/dev/null);
- an empty environment.

*Verification before the spawn:* `+[SNProcess executableMatchesRunningCode]` compares the on-disk executable's cdhash with our running code (`SecCodeCopySelf` vs `SecStaticCodeCreateWithPath`). On a mismatch (updated or replaced bundle), helpers are refused ("Restart Snaptic to finish updating").

*Verification after the spawn* (`START_SUSPENDED`):
1. confirm the child is still stopped (`proc_pidinfo` status);
2. `responsibility_get_pid_responsible_for_pid(child) == child`;
3. create the exit process source;
4. send `SIGCONT`.

Any failure → SIGKILL + `waitpid(pid, 0)`, and the feature becomes unavailable. A `/usr/bin/true` canary runs once per launch, before the first helper or hook.

*Reasoning:* helpers need no TCC, so disclaiming them means a replaced binary gains nothing.

**Helper rules** [R2C §4.1–4.3]:
- **On entry:**
  - `signal(SIGPIPE, SIG_IGN)`;
  - reset SIGTERM, SIGINT and SIGHUP to `SIG_DFL`;
  - **close every fd ≥ 3** except those named in argv.
- **Arguments:** `--parent <pid> --protocol <N> --build <uuid> --journal-dir <path>`.
- **Parent check:**
  - `getppid() == pid`;
  - the parent's **code-signing identity** via `+[SNProcess pidSatisfiesSnapticRequirement:]`: `SecCodeCopyGuestWithAttributes(pid)`, then `SecCodeCheckValidity` against a requirement built from our own identifier and team (or cdhash for ad-hoc). This survives updates [R3 platform M7].
  - Exit 64 on mismatch, 65 on a protocol mismatch.
- **Reading:** stdin through a `DispatchSource` read source plus `LineSplitter`. EOF means parent death.
- **What helpers may touch:** no NSApplication, NSScreen, NSWorkspace, UserDefaults or app singletons. Main runs `CFRunLoopRun`.
- **Writes:** `HelperPipeWriter` [R3C §5.1] (owns a CLOEXEC dup, idempotent close, flush). Reads use the read-source pattern [R3C §5.1]; never `readabilityHandler`. Every pipe end is `FD_CLOEXEC` at creation.
- **Lifetime:** the parent alone ends a helper (`shutdown`, or closing stdin). On a hang, killing a helper is checked against its start time.

**Startup order** (A owns `AppDelegate`):
1. `signal(SIGPIPE, SIG_IGN)`.
2. Argument/environment validation.
3. Instance lock, fail-closed, with `--relaunch-from <pid>` support: retry the lock every 100 ms for ≤ 10 s [R3C §5.5]. On failure, show who holds the lock (pid, path) and a "Quit the other copy" button.
4. `SystemHotkeys.recoverFromPreviousRun()`.
5. `LaunchStability.evaluate()`.
6. Safe Mode detection.
7. `RevertJournal.recoverAtLaunch()`, including the permanent-ops journal (§4.6).
8. Signal sources.
9. `HostHeartbeat.start()`.
10. `ControlServer` (if enabled).
11. `ModuleHost.bootstrap()`.
12. Status items.
13. `ConnectPlanner` runs once for "launch" (§4.11).

**Relaunch** (A, `Relauncher`):
1. `NSWorkspace.openApplication` with `createsNewApplicationInstance = true` and `["--relaunch-from", pid]`.
2. On success, terminate.
3. The new instance waits for the lock.

### 3.3 Modules (A.1)

- **`SnapticModule`**: `stop()` is sync and idempotent and never shows UI. A pending trial resolves as Revert. Session, overlay, gamma, virtual, capture and helper state is reverted; `.permanently` changes stay.
- **Menu placement** lives in `ModulesConfig` (Kit `MenuPlacementChoice`).
- **`ModuleHost`:**
  - collapses toggle storms;
  - one permission request per launch, through `PermissionFlow`;
  - flushes stores on quit;
  - stops modules in reverse order.
- **Host services** (A): `HotkeyGuard`, `SystemHotkeys` recovery, `HostHeartbeat`, `EmergencyActions`, `EventLog`, `GlobalHotkeys`, `PermissionFlow`, `Relauncher`, `HelperSpawner`, `ControlServer`/`ControlCommandRegistry`, `ToastPresenter`.
  - `HostHeartbeat`: a 0.5 s `.common` timer with tolerance; nonisolated `mainAgeMillis()`.
- **No system notifications.** All notices use `ToastPresenter`: a non-activating HUD with an optional action button (for example "Undo"), plus a menu badge. Snaptic never asks for notification permission.
- **Emergency path:** [R2C §2.3].

### 3.4 Configuration

- **Models** live in Kit (`Config/*`). Keyed maps use `LossyMap`. `DisplayKey` validates in `init?(rawValue:)`.
- **`ConfigStore`** (A):
  - 250 ms debounce on `DispatchQueue.main`, `flush()`;
  - `DefaultsKeyObserver`; keys without dots;
  - loop guard.
- **Reads come only from the persistent domain.** `NSArgumentDomain`, the volatile domain and managed preferences (MDM) are ignored and documented. The same applies to the switcher's `AppSettings` (A, step 1).
- **Keys:** `SnapticConfig.v1` (switcher), `SnapticModulesV1`, `SnapticDisplaysV1`.
- **`DisplaysRuntimeState`:** per-display `ObservableObject`s (no global dictionary republish), throttled to 15 Hz.
- **Limits:** 64 displays; 8 virtual screens; total virtual backing ≤ `SoCCaps.maxBackingBytes(ram:)`; 32 presets, 16 hooks, 16 actions; strings ≤ 256 scalars; paths ≤ 1024 bytes.
- **Upgrade:** if `SnapticDidLaunchBefore` is set and `SnapticModulesV1` is absent, the switcher is on, Displays is off, and a "New: Displays" card plus a "More display features…" menu item are shown.
- **External change notice:** a toast when hooks, actions, the CLI or trust fields change outside Snaptic while it runs. Informational only.
- **Backup.**
  - **Export** omits: hooks, actions, CLI settings, the salt, DDC unlocks, "Allow without asking" flags, preset trust, sensitive toggles (`disconnect`, `autoDisconnectBuiltin`, `dimToBlack`, `sleepPrevention`).
  - **Import** strips the same fields **even if present**. ≤ 1 MB; picked-file rules (§4.10.6); diff preview; apply.
- **Reset all settings:** available.

### 3.5 Menus

- **Placement per module:** shared / own icon / hidden.
  - With everything hidden, relaunching opens Settings, and so does the CLI `open-settings`.
  - With no modules on, the menu shows "No modules enabled — Open Settings…".
  - Right-click quick menu: Settings, Connect All, Redetect, Restore All Displays, Quit.
- **`DisplayMenuItemID`** (Kit, lead-frozen). Contributors register with `DisplayMenuRegistry` (lead).
- **Menu customization** lives **only** under General → Menu, with one section per module.
  - Icon (curated SF Symbols), hide icon, "hide when no external display is connected".
  - Per-item Visible / In submenu / Hidden.
  - First-level sliders.
  - Display order, main first, compact/expanded and collapsible blocks.
  - "Scroll on a slider to adjust".
  - Reset.
  - **Default:** brightness first-level, plus volume for DDC displays; the rest in submenus.
- **Display blocks:**
  - header: name, badges (Main, Virtual, Mirroring, Smart HiDPI, Disconnected, Safe Mode, Paused, Unprotected);
  - optional power switch;
  - `NSSlider` items (AppKit, accessible, sized in `menuWillOpen`);
  - a submenu with keyboard-reachable value items.
- **Rebuilds:** a dirty flag, rebuilt in `menuNeedsUpdate` [R3C §5.6]. Item actions capture the `DisplayKey` and re-resolve on click.
- **Tools:** layouts (presets), virtual screens, Connect All, Redetect, Arrange…, Identify, Restore All Displays, Resume display automation, Unprotected (restart).

### 3.6 Services and controllers (Displays)

**Services:** there are 13 `DisplayServiceID`s, and each is a real class with its own file:
- `registry`, `sessionGate`, `guardProcess`, `transactions`;
- `appleBrightness`, `ddc`, `gamma`, `overlays`, `edr`, `brightness`;
- `osd`, `colorSync`, `monitorPanel`, `mediaKeys`;
- `virtualHosts`, `capture`, `spawner`.

The r3 ids `nightShift` and `hotkeys` are folded into their controller and host. Dependency order is in Kit.
- **Activation:** each service is constructed eagerly by the lead with `init()`. `activate`/`deactivate` are reference-counted.
- **Isolation:** nonisolated services (`DDCService`, `AppleBrightnessIO`) conform to `DisplayServiceLifecycle` **in an extension** with `@MainActor` witnesses [R3C §2.4].
- **Context:** services hold `weak var context` [R3C §2.5]; the context does not hold the module.

**Controllers:** one per `DisplayControllerID` (§2.1), conforming to `DisplayFeatureController` [R2C §2.10], `@MainActor` on the primary declaration. The lead wires them all in 0b. Registrations (panic, session, menu, actions, diagnostics, verbs, hotkeys) are weak and end with the lifetime.

**Module apply order:**
1. stop emptied controllers;
2. deactivate services in reverse order;
3. activate services in order;
4. start new controllers;
5. notify the rest.

### 3.7 Settings and onboarding

`NavigationSplitView`, resizable, minimum 820×600.

- **General:**
  - modules;
  - Menu;
  - Command-line control;
  - Launch at login;
  - Permissions;
  - Backup & Reset;
  - Safe Mode;
  - Other display apps;
  - About & Licenses.
- **Window Switcher:** Features, Shortcuts, Behavior, Thumbnails, App lists, Privacy.
- **Displays:** Overview, Features, Resolution, Virtual Screens & HiDPI, Brightness, Color, DDC, Keys & Shortcuts, OSD, Arrangement, Protection & Presets, PIP, Automation, Diagnostics, Safety.

**Naming:**
- "Layouts" are display presets.
- "Favorites" are resolution favorites.
- "Apple display presets" are Apple's own.
- "Recipes" are virtual-screen templates.

**Onboarding chips** (multi-select; the union of the selected chips plus graph closure):

| Chip | Flags |
|---|---|
| Basics (preselected) | all 4 methods, `brightness`, `brightnessRestore`, `resolution`, `ddcControls`, `osd`, `shortcuts`, `mainDisplay`, `arrangement`, `mirroring` |
| Brightness & volume keys | Basics' brightness flags + `brightnessKeys`, `volumeKeys`, `ddcControls`, `osd`; offers "Hide the menu-bar icon" |
| Sharper text | `resolution`; per display, if no HiDPI mode near native exists, offers `smartHiDPI` (with HDR-loss and GPU notes) |
| Virtual screens | `virtualScreens` |
| Picture in picture | `pip` |
| Extra brightness | `xdr` + `brightnessKeys` (only if EDR potential > 1) |
| More (no Beta) | Basics + `color`, `nits`, `presets`, `protection`, `menuBarOverlays`, `osdBroadcast` |

Permissions are requested afterwards, only for what was chosen. The onboarding step is saved, and onboarding resumes after a relaunch.

**Accessibility:**
- every control is labeled;
- the Position/Align form gives 16 placements;
- **VoiceOver announcements of value changes are independent of `osd`**: on whenever VoiceOver is running;
- Reduce Motion is respected.

### 3.8 Other display apps

Snaptic detects BetterDisplay, MonitorControl and Lunar by bundle-ID prefix (Kit list), at Displays start and on app launch.

- Banner and choice: "Pause overlapping Snaptic features" (default) or "Run both anyway".
- Paused features show "Paused while MonitorControl runs" on their page and menu items.

## 4. Safety framework

### 4.1 Classification and visibility

- **`Transport`** (Kit): `builtin | wired | displayLink | airplay | sidecar | snapticVirtual | foreignVirtual`.
  - `snapticVirtual` = vendor 0xD354 plus live in our hosts.
  - AirPlay is identified via CoreDisplay.
  - Sidecar and DisplayLink labels are UI-only heuristics; safety logic treats them as `foreignVirtual`.
- **Enumeration:** **`CGGetOnlineDisplayList`**, with mirror membership from `CGDisplayMirrorsDisplay` and `CGDisplayIsInHWMirrorSet`. Hardware-mirror members aren't in the active list [V] (registry and guard both).
- **Strongly visible:** an online, awake `builtin|wired` display that either:
  - is active, shows its own framebuffer, and is not dimmed below the floor; or
  - is a hardware-mirror member of a set whose source is a live `snapticVirtual` or a strongly visible display.
- **Weakly visible:** an active `foreignVirtual|airplay|displayLink|sidecar` display showing its own framebuffer, or a `snapticVirtual` flagged **`headlessPrimary`** (only the Headless recipe sets it).
- **Not visible:**
  - other unmirrored Snaptic virtuals (for example a recording screen);
  - standby/other-input monitors, which can't be detected. Documented: auto-disconnect requires a recent DDC power read of "on" where DDC is available.

### 4.2 Hard invariants (Kit `Invariants`, unit-tested)

1. **Relative visibility.** If ≥ 1 display is strongly visible now, ≥ 1 stays strongly visible. Otherwise ≥ 1 stays strongly or weakly visible. Never ≥ 1 → 0.
2. **Panel hosts.** The panel shows on every visible display and on every mirror source. A change that leaves no panel host is refused.
3. **Dim to black** needs another strongly visible display. Floor 0.08 otherwise.
4. **Long-arm.** `Invariants.requiredLongArm` returns a non-empty set when Snaptic has disabled a display, when a physical display mirrors a Snaptic virtual, when dim to black is active, or when overlay dim is below 30%.
5. **DDC:** chip 0x37 (0xB7 for MCDP); VCP policy in Kit and in the shim.
6. **Automatic plans** are rate-limited by `RateLimiter`: per plan, not per change; 1 per 2 s globally, 3 per display per 60 s. **Visibility-restoring actions bypass limits and coalescing:**
   - re-enable;
   - raise the floor;
   - kill or un-mirror a host whose physical display left.
7. **Main** must be strongly visible while any display is. Otherwise it may be weakly visible.
8. **Panic** never removes the last visible display, and leaves a lone `headlessPrimary`.

### 4.3 Transactions (A.3)

**Changes are data.** Undo is computed from the request plus the before-snapshot, as compare-and-swap `UndoOp`s [R2C §5.1].

**Risk** = `max(caller risk, RiskClassifier)`:
- **low:** origins; main (target strongly visible); modes in the known-good set.
- **restore:** **unattended re-establishment of a state the user kept before.** Journaled, long-armed, invariant-checked, with no panel. Only `ConnectPlanner` uses it, for:
  - Smart HiDPI pairs and virtual-screen associations that were kept;
  - trusted layouts;
  - persisted choices.
- **trial:**
  - new modes, unconfirmed refresh rates, CGS modes;
  - mirroring, disconnect/reconnect;
  - rotation/underscan/HDR;
  - first-time Smart HiDPI;
  - untrusted layouts with trial content.

**Known-good set** (per display, by full `ModeRef`):
- native, default, and modes the user kept;
- on built-in panels, also every public `IsUsableForDesktopGUI` mode at the current refresh rate.

Setting: "Confirm resolution changes": New modes only (default) / Always / Never for public modes.

**Preconfirm DDC** is handled by `PreConfirmPresenter`, not a transaction. Its tokens are bound to key, VCP, value and expiry [R3C §2.2].

**Queue:** `DisplayTransactionQueue`.
- **Automatic requests are planned, not dropped:** `ConnectPlanner` builds one plan and enqueues it as one transaction sequence.
- A user request while a trial is pending first resolves the trial as Revert (with a toast).

**Flow:**
1. `prepare()`.
2. Snapshot inside the queue.
3. Predict, check invariants.
4. Compute the undo.
5. For trial and restore:
   1. write the journal (and the permanent-ops journal for MonitorPanel steps);
   2. `armTrial`/`setLong` → await `ack` (1 s). No ack → refuse ("Safety helper unavailable").
6. Apply in the [R2C §5.4] order: HDR → quiescence → rotation → quiescence → re-resolve modes → CG batch(es).
   - **Batches are split by final scope** into two transactions: `.permanently` for modes/origins/main, `.forSession` for mirrors/disable.
   - **Skip any step whose live value already equals its target**, so a TV doesn't modeset twice.
7. **Trial:** show the panel. The countdown starts after the target is active plus 2 s of settle time.
   - **Keep:**
     1. `commitIntent`, ack;
     2. update protection's desired state;
     3. re-apply with the final scope, skipping equal values;
     4. record the persisted choice and the pre-Keep mode;
     5. add to the known-good set;
     6. `commit`, `afterKeep`, clear the journals;
     7. suppress automatic actions for 2.5 s.
   - **Revert, timeout, `willSleep`, quit, session resign, or guard EOF:** apply the undo (CAS, reverse order), `afterRevert`, `disarm`, clear the journals, suppress.
8. **Restore:** apply, then hold the long-arm while the state persists. No panel.

`trialScope` defaults to `.forSession`, kept as one switchable constant.

### 4.4 Confirm panel

- `.screenSaver + 2`, `canJoinAllSpaces | fullScreenAuxiliary`.
- It is key only for UI-triggered changes.
- Keys work after 1 s: Return / ⌘K keep, Esc reverts.
- Host dimming is raised to ≥ 30% while it shows.
- Uptime clock, 15 s.
- VoiceOver announcement every 5 s.
- Refused when the target display is captured (`CGDisplayIsCaptured`); the change is refused too.

### 4.5 Guard

**Protocol** (Kit `GuardMessage`/`GuardReply`) [R2C §4.4], plus:
- `busy(seconds ≤ 10)`: not honored for modals, and a `busy` that would extend an open window while `mainAgeMillis` grows is ignored;
- `classification([GuardDisplayClass])`: id, transport, strong, weak, plus Smart HiDPI host pid and start time [R3C §5.2];
- `hello` carries `protocol` and `build`.

**Clocks:** relative, uptime. The guard ignores stalls for **15 s after a wake** (IOKit power notification).

**Off-console:** while `kCGSessionOnConsoleKey` is false, the guard does nothing and re-evaluates when back on console.

**Parent death:**
- `armed`: quiescence (1.5 s quiet, 8 s cap), then the CAS undo.
- `committing` / `committed`: nothing.
- **Long set:** re-enable plus un-mirror, CAS.

**Hang** (long-armed; no heartbeat for 10 s, or `mainAgeMillis` > 10 s outside `busy` and outside wake grace):
1. **SIGKILL the Smart HiDPI and association hosts** (start-time checked). Process exit removes the virtual displays, macOS breaks the mirrors, and main moves to a real panel.
2. Re-enable displays Snaptic disabled.
3. Restore ColorSync.
4. Un-mirror only for hosts that are already dead.
5. If still hung at 30 s *and* dim-to-black or overlay dim < 30% is active: SIGKILL the parent (start-time checked).

**No visible display:** the guard acts when the parent heartbeat is more than 3 s stale, or the condition persists after **2 s** (restore actions bypass coalescing). It re-enables Snaptic-disabled displays and kills hosts whose physical display is gone.

**Reverts:**
- staged (enable → un-mirror → MonitorPanel → modes/origins), each `.forSession`;
- failures are logged, and the next stage runs anyway;
- MonitorPanel steps only when `ready.canMonitorPanel`.

**Journals:** claimed by rename before reverting, deleted afterwards, orphans re-claimed.

**Activity:** `beginActivity(.userInitiatedAllowingIdleSystemSleep)` while long-armed; the token is stored and ended.

**Guard unavailable:**
- new trials and new long-arm states are refused;
- **existing** long-armed states are kept and badged **"Unprotected — restart Snaptic"**;
- a pending trial reverts.

**Quit:** `disarm`, then flush (500 ms).

### 4.6 Journals

- **Location:** `~/Library/Application Support/Snaptic/Displays/` (0700, `lstat`-checked). Atomic writes (temp file `O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC 0600`, fsync, rename, fsync the directory).
- **Session journal** `journal.json` `{version, bootSessionUUID, uid, createdAt, fingerprints, undo}`:
  - discarded on a boot, uid or fingerprint-set mismatch, or after 24 h;
  - otherwise claimed and filtered to safe directions (re-enable, un-mirror, ColorSync, public-list modes; CAS), then applied `.forSession` in stages, with a toast.
- **Permanent-ops journal** `permanent.json` `{uid, ops}` for MonitorPanel trial steps (HDR, underscan, rotation):
  - **not** discarded on reboot;
  - at launch, unconfirmed ops are reverted **even in Safe Mode**, and the file is cleared.

`kern.bootsessionuuid` is read with two-call sizing.

### 4.7 Panic

- **Triggers:** ⌃⌥⌘⎋ (fallback ⌃⌥⌘⇧⎋), the menu, the CLI. While the switcher is open, `handleKeyWhileOpen` passes this combination through.
- **Registered** while any geometry/gamma/overlay/virtual feature is effective; can't be disabled while long-armed.
- **What it does:**
  - runs the `PanicParticipant`s;
  - **reverts modes Snaptic set in the last 60 s**;
  - honors invariant 8;
  - shows a HUD;
  - sets `panicLatch`, which pauses all `ConnectPlanner` work, recreation, auto-disconnect, protection, layouts and hooks until "Resume display automation".
- **Never touches** foreign, AirPlay, DisplayLink or Sidecar displays.

### 4.8 Safe Mode and launch stability (A)

- **Triggers:** ⇧ held at launch, `--safe-mode`, or two consecutive launches that ended in under 60 s without a clean quit.
- **Skips:**
  - brightness/color restore;
  - virtual recreation, Smart HiDPI;
  - protection, layouts, **persisted choice**;
  - associations, hooks;
  - DDC writes;
  - XDR, sleep prevention;
  - `ConnectPlanner` entirely.
- **Still runs:** journal recovery and permanent-ops recovery.
- A banner shows; "Leave Safe Mode" relaunches.

### 4.9 Watchdogs and session rules

- **Gamma:**
  - Baselines are captured only after our own ColorSync restore. After each restore, re-apply to all managed displays **including Snaptic virtuals' base tables** (Smart HiDPI PQ correction).
  - ±1/256 tolerance.
  - 3 s zero-table watchdog while owned (10% tolerance; paused on sleep or an inactive session).
  - 3 fights in 60 s → stop on that display and suggest overlay.
- **Sleep/wake:**
  - `willSleep` reverts pending trials.
  - On `screensDidWake`, gamma and overlays apply immediately.
  - DDC and mode writes resume at wake + 3 s, with backoff to 15 s. DDC writes only if the read-back differs.
  - Writes also pause during reconfiguration.
- **Session resign:**
  - all controllers pause (SessionParticipant);
  - **non-headless virtual hosts shut down** (un-mirror first);
  - recreated through `ConnectPlanner` on resume.
- **Capture resume** requires `CGSessionCopyCurrentDictionary` (on console, not locked). Lock/unlock distributed notifications only *stop* things; **every** resume-like action re-checks the session dictionary (dim on lock, XDR resume, "disconnect on lock").
- **Main thread:**
  - ≤ 50 ms except CG configure, which is announced with `busy`;
  - async polls;
  - `MediaKeyTap` on its own thread with the generation pattern [R3C §5.4].

### 4.10 Security boundary

**Threat model:** a same-user process can already reconfigure displays, gamma and DDC, write defaults, and launch Snaptic. Snaptic must ensure:

**(1) No attacker-chosen code runs under Snaptic's TCC responsibility.**
- Helpers, hooks and actions are all disclaimed spawns with verification (§3.2).
- Hooks and actions refuse executables inside Snaptic's bundle or carrying Snaptic's signing identifier.
- Path checks: absolute path; `lstat` every component; owner is the user or root; not group/world-writable; regular executable.
- Fixed argv (≤ 8 args), minimal environment, own process group.
- Spawn order per [R3C §5.3]; the timeout `killpg` only while not yet reaped.
- 30 s timeout; one run per event per 10 s; off in Safe Mode and while panic-latched.
- App mode: argument/environment validation + lock + persistent-domain reads (§3.2, §3.4).

**(2) No TCC-derived data leaves the process.**
- The CLI, broadcast, hooks, diagnostics and EventLog never carry pixels, window titles, app names or key codes.
- `EventLog` is shared with the switcher and gets the same rule.
- The OSD broadcast is a documented exception that carries only `{kind ∈ closed enum, value, max}`, ≤ 10/s, not while locked.

**(3) Narrow automation.**
- **CLI:** socket dir 0700, socket 0600, CLOEXEC, `SO_NOSIGPIPE`, `getpeereid`, path length < 104; 64 KB; 4 concurrent; 20/s; one request per connection; 2 s read.
- **Off-only:** features can only be turned off. Protected settings are never touchable: hooks, actions, CLI, sleep prevention, disconnect, auto-disconnect, dim to black, unlocks, allow flags, trust.
- **Trials** show the panel unless "CLI may skip confirmation" is on (default off).
- **preConfirm DDC** works only for code + value pairs marked "Allow without asking" on that display.
- **PIP:** saved display configurations only, and only while on console and unlocked.
- **Actions:** only those flagged `cliAllowed`. Accessibility-using actions ("Gather windows here") are never CLI-allowed.

**(4) Device data.** EDID, DDC and capabilities parsing is bounded (EDID ≤ 1024 B / 7 extensions; capabilities ≤ 4096 B, 128 fragments, 2 s, nesting ≤ 8; fixed DDC lengths). Plus `CFGetTypeID` checks, sanitized names (Kit `TextSanitizer`, ≤ 64 scalars), and fuzz tests.

**(5) PIP privacy.**
- **Display filters exclude:** Snaptic; protected apps by bundle-ID prefix; `com.apple.notificationcenterui`.
- **Private windows:** excluded by `SCWindow` id, refreshed on app activation, window-created events and every 5 s.
- **Stops:** capture stops and the last frame clears on lock, sleep or resign.
- **Refused:** self-loops, and full-screen streams onto the last strongly visible display.
- **CoreImage:** built-in filters only, by allowlisted name. Plugins are never loaded.

**(6) Picked files:** `O_NONBLOCK|O_NOFOLLOW`, `fstat` regular file, size caps, read off main.

**(7) Diagnostics:** masked serials; salted `DisplayKey`. Virtual identities use an **unsalted** fingerprint hash, so ICC profiles stay stable.

**(8) Kill switches:** disable only; `stop()` still reverts.

**(9) No network:** lint.

**(10) Overlay vs authentication UI.**
- While dim-to-black or overlay alpha > 0.5 is active, poll `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` at 2 Hz, plus on app activation.
- Match `kCGWindowOwnerPID` → `proc_pidpath` against the Kit list of system auth processes: SecurityAgent, coreautha, UserNotificationCenter, universalAccessAuthWarn, CoreServicesUIAgent, AuthenticationServicesAgent, loginwindow.
- While one is on screen, **order out the dim overlays**. Never move the safety UI.
- Best effort; labeled in the UI.

### 4.11 ConnectPlanner (Kit planning + D runner)

Runs on launch, wake, connect/disconnect (coalesced until **3 s of reconfiguration quiet**) and session resume. It builds **one plan** in this order:

1. **Restore visibility:** re-enable, kill orphaned hosts, raise floors. Immediate, unlimited.
2. **Smart HiDPI / associations.** Rebind or re-establish kept pairs (`restore`).
   - **Grace before teardown:** 4 s normally, 30 s within 120 s of a wake or unlock. During the grace, if the virtual is main and a strongly visible display exists, set main to it.
   - **Rebind** the mirror to the returning panel instead of recreating it. Recreate only on an identity or size mismatch.
3. **Layout:** if a trusted layout matches (by priority, then most specific), apply it (`restore`) with an Undo toast, and skip protection. Otherwise apply protection (`restore` for previously kept states). An untrusted match shows a toast: "Apply 'Office'?"
4. **Persisted choice,** only for displays steps 2–3 didn't touch, and only when the current mode equals the recorded **pre-Keep** mode (the "`.permanently` didn't stick" case). An unattended mode change on an external applies only if another strongly visible display exists; otherwise it becomes a trial.
5. **Auto-disconnect built-in,** last.

Rules:
- Each step's changes are filtered by effective features.
- Rate limits count plans.
- Skipped entirely in Safe Mode or while panic-latched.
- A non-Snaptic mode change that the registry observes updates the stored persisted choice, so Snaptic never fights System Settings.

## 5. Displays core (B)

- **`DisplayRegistry`:**
  - online enumeration plus mirror membership (§4.1);
  - `CallbackTarget` boxes; the same static callback for register and remove;
  - IOKit iterators drained;
  - debounce until quiet;
  - publishes `[DisplayInfo]` and `snapshot()`.
- **Presented displays.** A Smart HiDPI pair is one `DisplayInfo`: `desktopID` = virtual, `hardwareID` = physical, `key` = the physical's key.
  - PIP configs, menus, actions and layouts key on **`DisplayKey`** (never `id`).
  - Layouts and protection store mirror relations between presented displays (including "TV mirrors my Smart HiDPI display").
  - Snaptic-virtual internals are never stored.
- **Fingerprint** (Kit):
  - tiers: (1) edidHash + alnumSerial, (2) uuid, (3) vendor/model/serial, (4) location;
  - `DisplayKey` = 32 lowercase hex characters (validated in `init?(rawValue:)`);
  - salted hashes are computed in the app (CryptoKit).
- **`LayoutReader`** (nonisolated): used by the guard and the app.
- **Modes:**
  - `DisplayModeDescriptor` (Kit, Equatable), `ModeRef`;
  - slider candidates in Kit;
  - CGS behind `hiddenModes`, sanity-checked.

## 6. Brightness & color (C)

### 6.1 Brightness service

**Method choice per display**, among effective methods:
1. Apple: built-in, or DisplayServices works. Excludes non-Apple HDR displays on 15+.
2. DDC: if a read succeeds.
3. Gamma: `builtin|wired`, not affected, not a mirror target. For a **Smart HiDPI pair**, gamma goes on the **virtual** [O force-hidpi], with a per-pair "Did it get darker?".
4. Overlay: everything else.

**Apple display presets:** a preset with fixed brightness disables Apple native brightness. The service detects it (a set/get mismatch) and falls back.

**Affected-models table** (Kit, no upper bound): defaults to overlay. "Did it get darker?" on first gamma use per display or pair.

**Custom-profile safeguard:**
- **Before** applying a profile, warn that gamma dimming and color adjustments will move to overlay or be unavailable on all displays (with an override).
- After it is applied, enforce that.

**Combined scale** (Kit):
- Defaults: switchover 25% for Apple native; **0% for DDC** (pure hardware; the user can extend below the hardware minimum with a switchover slider); 20% while XDR is on.
- Hardware-only and software-only cases.
- Per-display switchover and min-HW sliders; "Min HW" and "Max HW" snap marks on the slider.

**Transitions:** 150 ms ramps (none with Reduce Motion).

**Restore modes:** brightness / adjustments only / off. Floor 15%. DDC on read-back mismatch.

**Dim on lock:** gamma, 10% floor.

**Sync:** source → targets; absolute or delta; offsets; 2% deadband; DDC writes ≥ 3 s apart; pause 10 s after a manual change; ⇧ skips.

**Nits:** a per-model default table (Kit `NitsModel`): MacBook Pro XDR M1–M3 500 SDR, M4+ 1000 SDR; other built-ins 500; externals 300. All labeled "estimate", editable.

### 6.2 Gamma composer

- Baseline ∘ adjustments × brightness × `xdrScale` (method B).
- 1024 samples, floor-clamped.
- Kit `GammaMath`, property-tested.
- AS redraw-nudge window.
- Owns the PQ correction base table for `hdrVirtual` pairs.

### 6.3 Overlay service

`OverlayKind` (lead-frozen): `dim`, `edr`, `nudge`, `menuBarStrip`, `roundedCorners`, `identify`.

| Window | Level | Collection behavior |
|---|---|---|
| Dim / EDR / corners / nudge | `.screenSaver` | `canJoinAllSpaces`, `stationary`, `ignoresCycle`, `fullScreenAuxiliary` |
| Menu-bar strip | `mainMenu − 1` | **without** `fullScreenAuxiliary`; sized from the safe-area top / menu-bar height; hidden when the menu bar auto-hides |
| Safety UI | `.screenSaver + 2` | — |

- All overlays: `sharingType = .none`, click-through.
- Dim alpha ≤ 0.92 unless dim-to-black.
- On mirror sets, overlays go on the desktop display.

### 6.4 XDR (Beta)

- **Per display,** when EDR potential > 1.
- **Range** up to `min(user max, headroom × 100)`. The user max defaults to 160%, capped at 400%. An OSD detent at 100% with **hysteresis**: crossing it needs a second press within 1 s.
- **Keys:** with XDR enabled on the target, `brightnessKeys` intercepts **up at 100% and down while above 100%**, built-in included (the XDR exception). Shortcut actions XDR + and XDR −.
- **Auto-brightness drift:** while boosted, the boost factor stays relative to the current hardware level.
- **Methods:**
  - **A (overlay multiply):** needs the overlay method effective.
  - **B (EDR + gamma > 1, undocumented):** needs the gamma method effective.
  - k = min(target, headroom), polled at 1 Hz while active.
- **Calibration:** "Is it brighter?". If both methods fail, XDR is marked unavailable with the reason; no looping.
- **Auto-pause:**
  - thermal state ≥ serious, Low Power Mode, battery below the floor (20% hard minimum);
  - lock, sleep, resign.

  Resume conditions must hold for 60 s. The OSD shows a toast and the menu shows "XDR paused (reason)".
- **Warnings:** HDR video blowout, OLED, battery.

### 6.5 Profiles, Night Shift, Apple presets, auto-brightness

- **Profiles:** `SNColorSync` iterate/set. Restoring the previous profile uses `kCFNull` → factory.
- **Night Shift:** `SNNightShift`, 256-byte buffer.
- **Apple presets:** MonitorPanel (low risk).
- **Auto-brightness:** DisplayServices if resolved.

## 7. DDC (C)

- **`DDCService`** [R2C patterns]:
  - one serial queue; coalescing; ≤ 5 writes/s per display while interactive; skip-equal;
  - single write by default;
  - gates: session, sleep, reconfiguration;
  - daily write counter;
  - every read resumes exactly once;
  - cached `IOAVService`;
  - `PreConfirmToken` required for preConfirm codes.
  - `DDCReading { current: UInt16, max: UInt16 }`.
- **Transports** (`SNDDC`, C):
  - **AS:** `DCPAVServiceProxy` matching; MCDP 0xB7 (Beta).
  - **Intel:** I²C.
  - Both refuse any chip address outside {0x37, 0xB7} and buffers over 64 bytes, in C.
  - The address form for AS (7-bit 0x37, data address 0x51) vs Intel (8-bit 0x6E/0x6F) is documented in the header.
- **Framing:** field variant first, spec checksum on retry; remembered per display.
- **Timing:** 10 / 40 (50 for slow or MCDP) ms; 4 retries.
- **Capabilities:** bounded; read on first sight or on demand.
- **Per-control tuning;** inputs (rename, hide, reorder, "Allow without asking" per code + value).

### 7.4 VCP policy

| Tier | Codes | Rule |
|---|---|---|
| Safe | 0x10, 0x12, 0x13, 0x6B, 0x14 (values from caps or known list), 0x16, 0x18, 0x1A, 0x6C, 0x6E, 0x70, 0x62, 0x87, 0x8A, 0x8D (preConfirm if caps say screen-blank), 0xDC (values from caps) | Allowed |
| preConfirm | 0x60, 0xF4, 0xD6 ∈ {2, 3, 4}, 0xE7, 0xE8, 0xE9, 0xF3 | Modal before sending, unless the code + value is "Allow without asking" on that display. Never part of automatic plans. |
| Unlockable | Other 0xE0–0xFF | Typed per-display unlock, then preConfirm |
| Denied | 0x01, 0x04, 0x05, 0x06, 0x08, 0x0A, 0xB0, 0xCA, 0xCC, 0xD6 = 5, opcode 0x0C, anything else | Refused everywhere |

## 8. Keys, shortcuts, OSD (C; hotkey infrastructure A)

### 8.1 Media keys

- **Tap:** `MediaKeyTap`, mask `NX_SYSDEFINED` only; generation pattern; per-press decision; key-up passes; trust check.
- **F14/F15 alternates** are Carbon hotkeys, never in the tap.
- **Policy:** "only for displays macOS can't control" (with the XDR exception) or "always"; per key, "also let macOS handle it".
- **Target:** the display with the pointer (default), the focused window's display, or all. Pairs are presented displays.
- **Modifiers:** ⌥⇧ fine; ⇧ skip sync; ⌃ built-in only; ⌃⌘ externals only; ⇧⌘ other displays; ⌥ + brightness opens Settings → Brightness; ⌘ + brightness-down toggles mirroring of the target.
- **Steps:** 1/16 and 1/64, configurable.
- **Volume policy:**
  - "when the output device matches the display" (default);
  - "when the output device has no volume control" (USB DACs, HDMI audio);
  - "always".

### 8.2 Shortcuts

- **`GlobalHotkeys`** (A): Kit `HotkeyCombo`; `register(_:owner:lifetime:action:)`; one Carbon handler; conflict detection among Snaptic shortcuts.
- **`DisplayActionRegistry`** (lead): `Action { id: DisplayActionID, title, feature, cliAllowed, perform(DisplayTarget) }`. Each team registers its actions:
  - **C:** brightness, contrast, volume, gamma and temperature ± (fine variants); mute; invert; reset/suspend adjustments; XDR toggle and ±; sync toggle; Night Shift; input slots 1–10.
  - **D:** resolution ±, HiDPI, native, default, native-halved, undo/redo, notch, favorites 1–5; rotate; set main; mirror toggle; toggle built-in; connect all; disconnect; disconnect all but main; layouts 1–9; virtual toggles; Smart HiDPI toggle; HDR.
  - **E:** PIP start/stop/hide/pause all; exit click-through.
  - **A:** custom actions; redetect; show menu; panic (reserved).

### 8.3 OSD

- **Presenter:** our HUD on 26+, native (`SNOSD`) as an option on 14/15.
- **Style** (Classic, Rounded) and **position** are separate settings:
  - positions: under the icon, top-right, top center, center, bottom center;
  - defaults: under the icon on 14–26, top-right on 27;
  - the icon anchor uses `button.convert(bounds, to: nil)` → `convertToScreen`, and falls back to top-right when the result is implausible.
- **Window:** `.screenSaver + 2`, all Spaces, `sharingType = .none`, click-through, `NSVisualEffectView.state = .active`.
- **Content:** 16 segments, value, optional nits; fades after 1.2 s.
- **Which display:** affected (default), active, or main.
- **Broadcast:** §4.10(2).

## 9. Resolution, virtual screens, management (D)

### 9.1 Resolution

- Transactions with known-good rules.
- **Persisted choice:** recorded only on Keep and on low-risk changes, together with the pre-Keep mode; applied only by `ConnectPlanner` step 4; skipped in Safe Mode.
- Favorites (5, with actions); undo/redo (10).
- Native, default, HiDPI toggle, native-halved, notch toggle.
- Range limits, below-720p option.
- UI scale match.
- **Mode list:** filter tags (HiDPI/LoDPI, refresh, bit depth); current, default and native markers; "Show all" (CGS, X).
- **Slider:** % or W×H display; snapping to favorite, current, default and native (⌥ bypasses).

### 9.2 Virtual screen spec (Kit)

- `VirtualScreenSpec {id, name, aspect, sizeInches, hiDPI, resolutions[] (points), refreshRates[] (default [60]), portrait, recreateOnLaunch, headlessPrimary, primaries?, associations}`.
- Vendor 0xD354, product 0x0001.
- Serial = an unsalted hash of the spec id, or of the physical display's fingerprint for Smart HiDPI.
- **Backing:** `maxPixels` = 2 × the largest mode.
- **Caps** (`SoCCaps`): width 6144 for entry Apple silicon, 7680 for Pro/Max/Ultra (`^Apple M\d+ (Pro|Max|Ultra)$`), 8192 for Intel; plus a total-bytes cap derived from RAM.
- `recreateOnLaunch` defaults on only with an association or PIP.

### 9.3 Virtual hosts

- **One host per screen.** Each host is spawned by `HelperSpawner` and costs about 8–15 MB. The Safety page shows each host's memory and the estimated WindowServer surface memory.
- **Protocol** (Kit): `hello` → `ready`; `create(spec)` → `created(displayID)` / `failed`; `shutdown`.
- **Creation** uses a **single-mode list** (the initial mode) [R3 platform M2]. The parent verifies `pixelWidth == 2 × width` for HiDPI.
- **Mode changes:**
  - Additional modes are applied with `applySettings` by the host on request (`setModes`, Beta), then selected by the parent with a mode change.
  - A virtual whose mode changed is removed by `shutdown` → verify gone → SIGKILL, with no extra grace.
- **Host death:** the screen is marked disconnected. Recreation is an automatic action under `RateLimiter`; after 3 failures in 60 s, Snaptic stops and shows "Virtual display failed to start".

### 9.4 Virtual screens

**Creating and managing:**
- Presets or custom aspect.
- Edit: name, size, HiDPI, resolutions, refresh rates, portrait.
- Connect, disconnect.
- Bulk Connect / Disconnect / Reconnect / Discard / Disassociate all.

**Associations:**
- auto-connect while display X is present, or while X is absent;
- mirror onto X (Smart HiDPI path);
- auto-start a stream to X.

**Behavior:**
- **Reconnect after wake** uses rebind semantics (§4.11) and recreates only on mismatch.
- **Restore layout after connect.**
- **Disconnect on lock** (session-dictionary checked).

**Recipes:**

| Recipe | Spec |
|---|---|
| Headless | 16:9, 27", HiDPI, 2560×1440 and 1920×1080 points, recreate, `headlessPrimary` |
| Recording 16:9 | 1920×1080 LoDPI + PIP config; placed below-right of main, so the cursor doesn't drift into it |
| Teleprompter | Target aspect + flipped stream |
| Portrait | 9:16, 27", HiDPI |

"Supersample" is folded into Smart HiDPI (> 100%).

**Gather windows here** (A-owned action using the switcher's AX helpers through a small `WindowGatherer` API in `Switcher/`):
- requires Accessibility (`PermissionFlow`);
- never CLI-allowed.

### 9.5 Smart HiDPI (Beta)

- **Per physical display,** one host.
- **Modes:** 50–150% of native points within the caps, created single-mode at the HiDPI mode closest to the current UI size. Panels at 75 Hz and above are offered their native rate (with the GPU cost shown).
- **Primaries** are copied from the physical display, so wide-gamut content isn't clamped. The ICC profile is matched via ColorSync, with SkyLight as a fallback.
- **First enable:** trial. Re-establishment uses `restore` through `ConnectPlanner`. The guard stays long-armed.
- **Lifetime:** the grace and rebind rules in §4.11.
- **Slider:** a parent mode change, low risk on known-good.
- **Disable:** un-mirror → shutdown host.
- **Brightness:** gamma on the **virtual** (also a possible way around the M5 bug, [U]); DDC and DisplayServices on the physical; overlays on the virtual.
- **XDR:** B on the virtual with PQ base (`hdrVirtual`) or the physical [U]. Unavailable unless verified by calibration.
- **Shown limitations:** HDCP, HDR loss without `hdrVirtual`, cursor sampling, per-chip limits, GPU and memory.

### 9.6 Management

- **Main:** must be strongly visible (invariant 7).
- **Arrangement:** canvas plus the Position/Align form (16 placements). Low risk.
- **Mirroring:** trial.
- **Rotation, underscan, HDR:** trial; permanent-ops journal; refused on the only strongly visible display (HDR/underscan).
- **Disconnect:**
  - trial `.forSession`, long-armed;
  - reconnect-all on quit, panic, journals and guard;
  - X on Intel;
  - header power switch: connect/disconnect, DDC standby, or none.
- **Auto-disconnect built-in** (AS):
  - `kIOPMMessageClamshellStateChange` interest notification plus `AppleClamshellState`;
  - only if the lid is known open, an external display is strongly visible, and its DDC power reads "on" where readable;
  - re-enable is a visibility restore (immediate);
  - runs last in the plan.
- **Protection:**
  - desired state per presented-display set;
  - **applied `.permanently`** (which also repairs macOS's own store);
  - only through `ConnectPlanner`;
  - fight detection: our state overwritten by a non-Snaptic reconfiguration twice within 30 s → stop, toast "macOS keeps changing this arrangement";
  - never hidden modes;
  - `kCGErrorCannotComplete` suspends until the next app activation.
- **Sleep prevention:** an `IOPMAssertion` plus a badge. The UI states that it prevents the automatic screen lock too.
- **Menu-bar overlays:** §6.3.

### 9.7 Layouts (presets)

- **Model** (Kit):
  - `name`;
  - `displays: [DisplayKey: {mode?, origin?, main?, rotation?, mirrorOf?, brightness?, adjustments?, ddcInput?, volume?}]`;
  - `nightShift?`;
  - `virtualScreens: [id: Bool]`;
  - `autoApply` (`whenExactly` / `whenIncludes`);
  - `priority`;
  - **`trust: TrustStamp?`**.
- **Trust:**
  - **Trust** = SHA-256 (computed in the app) of the canonical layout content + the matched display set's tier-1 fingerprints (EDID hash + alphanumeric serial) + the OS major version.
  - It is cleared by any edit, import, fingerprint change or OS major update.
  - It is granted after a manual apply the user kept. That covers **layouts with only low-risk content** too: their first manual apply shows a "Keep for automatic use?" toast.
  - Modes in a trusted layout must be known-good.
- **Auto-apply:** §4.11 step 3. DDC input is never part of it.
- **Manual apply:** one transaction, plus brightness, adjustments and DDC (preConfirm unless allowed). Fields of features that aren't effective are skipped, with a note.
- **Other ways in:** "Capture current"; actions 1–9; menu; CLI.

## 10. PIP & streams (E)

- **Sources:**
  - **Display:** programmatic SCK with the §4.10(5) filters. The first-run sheet explains the Screen Recording and monthly prompts and the relaunch.
  - **Window:** `SCContentSharingPicker`, per session.
- **Pipeline:** `StreamReceiver` → `FrameMailbox` → CoreImage (allowlisted) or the IOSurface directly → `CALayer`.
  - `queueDepth` 3.
  - Pauses when occluded.
  - Lifetime checks after every await, with `stopCapture` if ended [R3C c11].
- **PIP window:**
  - **level:** normal / floating / above all (`.statusBar`); `.auxiliary` collection behavior;
  - **interaction:** click-through with exit hotkey ⌃⌥⌘P; opacity; lock; aspect; integer scaling; title bar; snap 25%;
  - **capture:** FPS 1–120 or display rate; crop by drawing on the source preview;
  - **cursor:** shown or hidden; warp on ⌘-click.
- **Full-screen stream:**
  - `.screenSaver − 1`;
  - fit / fill / 1:1 / integer, underscan, flip, rotate;
  - native mode while streaming (trial);
  - auto-stop when the source goes away; ⌃⌥⌘P or panic stops it;
  - refused for self-streams and onto the last strongly visible display.
- **Stop / hide / pause all;** configurations keyed by `DisplayKey`; "start when source connects".
- **Filters** (allowlist):
  - color: exposure, brightness, contrast, saturation, vibrance, gamma, hue, temperature, highlight/shadow;
  - looks: sepia, posterize, invert, monochrome, photo effects, thermal, X-ray, comic;
  - detail: sharpen, unsharp mask, gaussian/motion blur, noise reduction, median;
  - stylize: pixellate, hex pixellate, crystallize, pointillize, edges, edge work, vignette, bloom, gloom, halftones (dot, line, hatched, CMYK);
  - plus a `.cube` LUT (Kit parser).

## 11. Automation (A)

- **Hooks:** events per DisplayKey (soft/hard disconnect and connect, sleep, wake, wake + delay); `{executable, args[]}`; environment `SNAPTIC_EVENT`, `SNAPTIC_DISPLAY_NAME`, `SNAPTIC_DISPLAY_KEY`.
- **Custom actions:** named executables shown in the menu and as shortcuts.
- **Control server** (host-level):
  - verbs registered with policy plus `offOnly` and `cliAllowed`;
  - selectors (name prefix, key, id, `main`, `mouse`, `focus`, `all`);
  - relative values;
  - verbs: `list`, `features`, `get`, `set`, `toggle`, `mode …`, `main`, `mirror`, `rotate`, `arrange`, `connect`, `disconnect`, `reconnect-all`, `layout list|apply|capture`, `virtual list|connect|disconnect`, `pip start|stop|stop-all`, `ddc get|set`, `input`, `panic`, `open-settings`, `identify`.
- **CLI client:**
  - Settings shows the `ln -s` command to copy;
  - paths via `getpwuid_r`;
  - `--json` output;
  - exit codes 0 / 2 / 3 / 4 / 5 / 6;
  - client timeout = confirm + 15 s.
- **Recipes in the README:** Stream Deck "Run shell" and Raycast script commands.

## 12. Diagnostics (F + `DiagnosticsContributor`s)

The report covers:
- OS, model, chip;
- per display: transport, masked identifiers, modes, HDR/EDR, brightness method and reason, DDC transport/framing/caps/write counts;
- the private-API table, kill switches, helpers (pids, memory), Safe Mode reason, panic latch, "Unprotected" state;
- the last 200 EventLog entries.

EDID decoding is in Kit. The DDC caps section appears when `ddc` is active.

Export and copy.

## 13. Files and ownership (normative)

```
Lead (0b, then frozen unless the lead changes them):
  Package.swift, Sources/Snaptic/main.swift, Resources/Info.plist (0.2.0), .github/workflows/*, scripts/lint.sh,
  scripts/gen-stubs.py + scripts/stubs.tsv (create-only; run by the lead locally, never in CI),
  Sources/SnapticShims/include/SnapticShims.h,
  Sources/SnapticKit/{KitModules, FeatureGraph, KitProbe, OtherDisplayApps}.swift, Sources/SnapticKit/Config/{ConfigModel, ConfigDisplays}.swift,
  Sources/Snaptic/Core/ModuleContracts.swift,
  Sources/Snaptic/Displays/{DisplaysModule, DisplaysContext, DisplaysContracts, DisplaysRuntimeState, SharedExtensions}.swift,
  Sources/Snaptic/Displays/Registries/{DisplayActionRegistry, DisplayMenuRegistry, DiagnosticsRegistry}.swift,
  Sources/Snaptic/Displays/Platform/{CallbackTarget, HelperPipeWriter}.swift, Sources/SnapticKit/LineSplitter.swift   (written for real in 0b)

KitModules.swift (lead) declares: ModuleID, Permission, L(), HotkeyCombo, DisplayActionID, DisplayMenuItemID (all ids),
  MenuPlacementChoice, DisplayFeature, DisplayControllerID, DisplayServiceID, OverlayKind, OSDKind, EventCategory names,
  SwitcherFeature, DisplayKey (validated init?(rawValue:)).

Sources/SnapticKit/ (one test file per Kit file, Tests/SnapticKitTests/<Name>Tests.swift)
  A: KitLossy, KitText (TextSanitizer; lead deletes the copy in Switcher/Settings.swift in 0b), KitControl, KitHookPolicy,
     KitLaunchStability, KitArgs (app-mode argument validation), Config/ConfigModules, Config/ConfigAutomation, Config/ConfigSwitcherFeatures
  B: LayoutModel (Transport, ModeRef, LayoutEntry, LayoutSnapshot, DisplayChange, InvariantViolation, FinalScope, GuardDisplayClass),
     Invariants, UndoPlanner, RiskClassifier, Fingerprint, DisplayModeDescriptor, ModeCandidates, EDIDInfo, GuardProtocol,
     JournalModel, RateLimiter, KitEncoding, AuthProcesses, Config/ConfigSafety, Config/ConfigIdentity
  C: DDCPacket, DDCReply, DDCCapabilities, VCPPolicy, GammaMath, CombinedScale, AffectedModels, SyncMath, NitsModel,
     Config/ConfigBrightness, Config/ConfigDDC, Config/ConfigKeys, Config/ConfigColor
  D: SoCCaps, ScaleMatch, LayoutPreset, ProtectionDiff, VirtualScreenSpec, VirtualHostProtocol, Recipes, ConnectPlan,
     Config/ConfigResolution, Config/ConfigVirtual, Config/ConfigManagement, Config/ConfigLayouts
  E: CubeLUT, FilterSpec, Config/ConfigPIP
  F: Config/ConfigMenu

Sources/SnapticShims/ (.h in include/, .m beside)
  A: SNSpawn   B: SNEncoding, SNProcess, SNMonitorPanel, SNCGSModes   C: SNDDC, SNColorSync, SNNightShift, SNOSD   D: SNVirtualDisplay

Sources/Snaptic/Core/  A: AppDelegate, Permissions, SnapticEntry, ModuleHost, ModuleContext, Lifetime, ConfigStore,
     DefaultsKeyObserver, SafeMode, LaunchStability, EmergencyActions, EventLog, HostHeartbeat, GlobalHotkeys, ModifierConversion,
     ShortcutRecorder, PermissionFlow, Relauncher, HelperSpawner, ToastPresenter, Backup, Onboarding, SettingsWindowHost,
     GeneralPages, MenuPlacement, StatusMenu, MenuSliderItem, ControlServer, ControlCommandRegistry, CLIClient, OtherAppsMonitor, SelfTest
Sources/Snaptic/Switcher/  A: moved files + WindowSwitcherModule, SwitcherPages, WindowGatherer
Sources/Snaptic/Displays/Platform/  B: PrivateDisplayAPI (open PrivateSymbol), DisplayRegistry, DisplayIdentity, LayoutReader,
     DisplayModes, CGConfig, IORegistryDisplays, SessionGate, PreConfirmPresenter (PreConfirmToken)
Sources/Snaptic/Displays/Safety/  B: DisplayTransactionQueue, ConfirmPanel, RevertJournal, DisplayGuardClient, DisplayGuardMain, PanicCoordinator
Sources/Snaptic/Displays/Brightness/  C: BrightnessService, AppleBrightnessIO, GammaService, OverlayService (+ OverlayToken),
     EDRBoost, ColorSyncService, MonitorPanelService, MediaKeyService,
     BrightnessController, XDRController, SyncController, ColorController, SystemColorsController, MenuBarOverlaysController
Sources/Snaptic/Displays/DDC/  C: DDCService (+ DDCReading), DDCTransport, DDCController
Sources/Snaptic/Displays/Input/  C: MediaKeyTap, KeysController, OSDPresenter, OSDHUDWindow, OSDController
Sources/Snaptic/Displays/Management/  D: ResolutionController, ArrangementController, PanelPropsController, PowerController,
     ProtectionController, LayoutsController, ConnectPlanner, VirtualHostsService, VirtualHostMain, VirtualController, SmartHiDPIController
Sources/Snaptic/Displays/PIP/  E: CaptureService, PIPController, PIPWindow, StreamReceiver, FrameMailbox, FilterPipeline
Sources/Snaptic/Displays/Automation/  A: SpawnerService, AutomationController
Sources/Snaptic/Displays/UI/  F: OverviewController, DiagnosticsController, DisplaysOverviewPage, FeaturesPage, DisplaysMenuBuilder,
     DisplayMenuBlock, DisplayIdentityPage, DiagnosticsPage, DisplaysOnboardingStep, IdentifyOverlay
                              B: SafetyPage   C: BrightnessPage, BrightnessMenuItems, ColorPage, DDCPage, DDCMenuItems, KeysPage, OSDPage
                              D: ResolutionPage, ResolutionMenuItems, VirtualScreensPage, VirtualMenuItems, ArrangementPage, ArrangementCanvas,
                                 ProtectionLayoutsPage, LayoutsMenuItems
                              E: PIPPage, PIPMenuItems   A: AutomationPage, MenuCustomizationPage (General)
```

**Ownership notes:**
- `MonitorPanelService` (the C file) wraps B's `SNMonitorPanel` for the Apple-presets and panel-props features. D's `PanelPropsController` calls it through the context.
- `GuardDisplayClass` is in B's `LayoutModel`.

**Rules:**
- Unique basenames per target directory (`.swift` + `.m`).
- Edit only your own files.
- Extensions on types you don't own are `fileprivate`. Shared ones live in the lead's `SharedExtensions.swift` (lint).
- EventLog categories use the lead-declared names.
- No protocol-extension defaults for `stop`, `deactivate` or `panicRestore`.

## 14. Delivery & verification

### 14.1 CI

**Done in 0a.** The macOS jobs build universal on pushes.

**0b adds:**
- `ubuntu-24.04`;
- a universal build on PRs that touch `Package.swift`, `Sources/SnapticShims/**`, `scripts/**` or `.github/**`;
- the `nm` check reworked [R3C m4];
- lint additions [R3C m5] (FileHandle write, `readLine`, `waitpid(-1`, `waitUntilExit`, `main.sync`, Displays `static let shared`, `passUnretained(self)`, foreign extensions);
- a §13 paths-exist check;
- a **helper fd-inheritance self-test** on the macOS runner: the debug build runs `--selftest-helpers`, spawns two children through `HelperSpawner`, SIGKILLs itself, and a script asserts both children exit within 3 s.

### 14.2 Order

| Step | Who | Exit criterion |
|---|---|---|
| 0a | Lead | **Done** (853e18b). |
| 0b | Lead | Every A.0–A.6 contract as real Swift; `stubs.tsv` → every §13 file as a compiling stub (exhaustive protocol members, no default no-ops); `FeatureGraph` + controller map + tests; registries; `CallbackTarget`, `HelperPipeWriter`, `LineSplitter` for real; CI additions. Green. |
| 1 | A alone | Switcher → module (restartable FocusTracker, `HotkeyTap.stop` + trust check, `disabledFeatures`, persistent-domain reads, app-mode validation, fail-closed lock + relaunch, 27 hardening), host services (`PermissionFlow`, `Relauncher`, `ToastPresenter`, `HelperSpawner` + `SNSpawn`, `GlobalHotkeys`), `ModuleHost`, stores, settings shell, menus. Green, merged. |
| 2 | B ∥ C ∥ A | **B:** registry/identity/modes/LayoutReader/private API/shims, transactions, confirm, journals, guard, panic, session gate, Safety page. **C:** DDC, methods, gamma, overlays, combined, OSD, keys infrastructure, Brightness/DDC pages. **A:** control server, CLI, onboarding, backup, other apps, automation. |
| 3 | C ∥ D ∥ E ∥ F | **C:** keys, sync, XDR, color, nits, dim on lock, system colors, menu-bar overlays. **D:** resolution, arrangement, panel props, power, protection, layouts, `ConnectPlanner`. **E:** PIP. **F:** UI shell, diagnostics, overview. |
| 4 | D | Virtual hosts, virtual screens, Smart HiDPI, associations, recipes. |
| 5 | Review | Fresh adversarial code reviews (security, correctness, parity); fixes; the color-mode research spike (D, read-only). |
| 6 | Lead | README, THIRD_PARTY_NOTICES, website, merge. |

### 14.3 Team rules

1. macOS 14 SDK APIs or `#available`. No 26/27 SDK symbols. No Swift 6-only syntax.
2. Macros: only `@Published`, `@objc`, `@MainActor`, `@ViewBuilder`.
3. No `@_silgen_name`, extern private symbols, `#if arch` or `resources:`.
4. Unique basenames; own files only; foreign extensions `fileprivate`.
5. A.6 isolation:
   - `CallbackTarget` for C callbacks;
   - SCK delegates are separate nonisolated classes;
   - no `.sync` onto main;
   - closures given to `asyncAfter`, NotificationCenter, Timer and KVO wrap `MainActor.assumeIsolated`.
6. Kit: `package` on everything, explicit `package init`, Foundation-only.
7. No `static let shared` in Displays (except `EmergencyActions`, `EventLog`).
8. XCTest, Kit-only tests, seeded fuzzing, compare decoded values.
9. Main ≤ 50 ms except CG configure (`busy`).
10. C interop:
    - `@convention(c)` returns `Int32`;
    - `OpaquePointer` for config refs;
    - `Unmanaged` handled correctly;
    - CFSTR macros become `"…" as CFString`.
11. Continuations resume once; `io_object_t` released; IOKit iterators drained.
12. Every feature: availability, kill switch, idempotent start/stop, `configDidChange`, `PanicParticipant` / `SessionParticipant` as relevant, Safe Mode, diagnostics.
13. `L()` for strings.
14. Controllers `@MainActor` on the primary declaration. Nonisolated services conform to lifecycle protocols in extensions.
15. Ids used across processes or persisted are `DisplayKey`, never display ids.

### 14.4 Kit unit tests

Everything listed in r3 §14.4, plus:
- `ConnectPlan` ordering and filtering;
- the online-but-not-active mirror classification;
- `headlessPrimary`;
- the trust stamp;
- the permanent-ops journal;
- `KitArgs`;
- `AuthProcesses`;
- controller map totality.

### 14.5 Done means

Every In-scope row in §2.1 and §2.2 is:
- implemented;
- reachable in the UI (and in the CLI where listed);
- wired to availability, kill switch, Safe Mode, panic, the session gate and diagnostics;
- built green with tests passing.

Docs and site are updated.

## 15. Roadmap

Future modules implement the §3.3 contract plus the §14.3 rules. Candidates: window layouts, clipboard history, audio switching.

---

## Appendix A. Contracts (0b writes these as real Swift)

### A.0 Kit ids (`KitModules.swift`)

```swift
package enum ModuleID: String, Codable, CaseIterable, Sendable { case windowSwitcher, displays }
package enum Permission: String, Codable, CaseIterable, Sendable { case accessibility, screenRecording }
package func L(_ s: String) -> String { s }
package struct HotkeyCombo: Codable, Hashable, Sendable { package var keyCode: UInt32; package var carbonModifiers: UInt32; package init(keyCode: UInt32, carbonModifiers: UInt32) }
package struct DisplayActionID: RawRepresentable, Codable, Hashable, Sendable { package let rawValue: String; package init(rawValue: String) }
package enum MenuPlacementChoice: String, Codable, CaseIterable, Sendable { case shared, ownIcon, hidden }
package enum DisplayFeature: String, Codable, CaseIterable, Sendable { /* every §2.1 id */ }
package enum DisplayControllerID: String, Codable, CaseIterable, Sendable { /* §2.1 */ }
package enum DisplayServiceID: String, Codable, CaseIterable, Sendable { /* §3.6 */ }
package enum DisplayMenuItemID: String, Codable, CaseIterable, Sendable { /* every item; lead-frozen */ }
package enum OverlayKind: String, Codable, Sendable { case dim, edr, nudge, menuBarStrip, roundedCorners, identify }
package enum OSDKind: String, Codable, Sendable { case brightness, contrast, volume, mute, xdr, resolution, layout, nightShift, input }
package enum SwitcherFeature: String, Codable, CaseIterable, Sendable { /* §2.2 */ }
package struct DisplayKey: RawRepresentable, Codable, Hashable, Sendable { package let rawValue: String; package init?(rawValue: String) /* 32 lowercase hex */ }
```

### A.1 Core (`Core/ModuleContracts.swift`)

[R2C §2.3] `EmergencyActions`, `EventLog` (categories from Kit), `Lifetime`. Plus:

- `SnapticModule`, `ModuleState`, `SettingsPage` (Hashable by id), `ModuleContext` (with an explicit init), `SafeModeState`;
- `ConfigStore<T>`;
- `GlobalHotkeys` (`typealias Combo = HotkeyCombo`);
- `ControlCommandRegistry` (`register(_:policy:offOnly:cliAllowed:summary:lifetime:_:)`);
- `PermissionFlow`: `request(_:reason:lifetime:)`, `state(_:)`;
- `Relauncher`: `relaunch()`;
- `HelperSpawner`: `spawn(kind:args:) throws -> HelperHandle`, where `HelperHandle` has pid, start time, writer, reader source and terminate;
- `ToastPresenter`: `show(_:action:)`;
- `HostHeartbeat.mainAgeMillis()` (nonisolated).

### A.2 Displays (`Displays/DisplaysContracts.swift`)

- `DisplayFeatureController`: [R2C §2.10] plus `static var id: DisplayControllerID`.
- `DisplayServiceLifecycle`: [R2C §2.11].
- `PanicParticipant`, `SessionParticipant`, `DiagnosticsContributor`, `DisplayMenuContributor`, `FeatureAvailability`, `DisplayTarget`.
- `DisplayInfo`: r3 A.2 plus `isWeaklyVisible` limited by `headlessPrimary`.
- `DisplaysContext`, with an explicit `init`, every service in §3.6, the registries, config, runtime, safe mode, hotkeys, commands and lifetime.

Service signatures: the r3 A.2 table, with these fixes:
- `PreConfirmPresenter.confirm(key:vcp:value:message:allowKey:) async -> PreConfirmToken?`;
- overlay, OSD and PIP APIs take `desktopID`; DDC, gamma and DisplayServices take `DisplayKey` → hardware;
- `VirtualHostsService.create(spec:) async throws -> UInt32`, `setModes(_:for:)`, `destroy(specID:)`;
- `DisplayGuardClient`: adds `busy(seconds:)`, `classification(_:)`, `longArm(_:)`.

### A.3 Transactions

Kit types:
- `DisplayChange`: `mode(UInt32, ModeRef)`, `origin(UInt32, x: Int32, y: Int32)`, `mirror(UInt32, of: UInt32?)`, `enabled(UInt32, Bool)`, `main(UInt32)`, `rotation(UInt32, Int)`, `underscan(UInt32, Double)`, `hdr(UInt32, Bool)`;
- `UndoOp`, `UndoPlanner`, `RiskClassifier`, `Invariants`, `ConnectPlan`.

App types:
- `TransactionRequest` (with `prepare` / `afterRevert` / `afterKeep`);
- `TransactionRisk { low, restore, trial }`;
- `TransactionOutcome`.

### A.4 Config

`DisplaysConfig` (`Config/ConfigDisplays.swift`, lead) composes:
- `features: LossyMap<DisplayFeature, Bool>`;
- `perDisplay: LossyMap<DisplayKey, PerDisplayConfig>`;
- `brightness: BrightnessConfig`, `ddc: DDCConfig`, `keys: KeysConfig`, `color: ColorConfig`;
- `resolution: ResolutionConfig`, `virtualScreens: VirtualConfig`, `management: ManagementConfig`, `layouts: LayoutsConfig`;
- `pip: PIPConfig`, `automation: AutomationConfig`, `safety: SafetyConfig`, `identity: IdentityConfig`, `menu: MenuConfig`.

`PerDisplayConfig` composes `PerDisplayBrightness`, `PerDisplayDDC`, `PerDisplayKeys`, `PerDisplayColor`, `PerDisplayResolution`, `PerDisplayManagement`, `PerDisplayIdentity`, `PerDisplayPIP`. Each lives in its team's Config file.

### A.5 Removed

The tripwire and system notifications.

### A.6 Isolation map

| What | Isolation |
|---|---|
| Modules, host, registry, transactions, controllers, UI, overlays, gamma, presenters, `ConnectPlanner` runner | `@MainActor` |
| `DDCService`, `AppleBrightnessIO` | `@unchecked Sendable`; lifecycle in an extension |
| `EmergencyActions`, `EventLog`, `HotkeyGuard`, `HostHeartbeat` stamp, `SessionGate` flag, `MediaKeyTap`, `FrameMailbox`, `StreamReceiver`, `HelperPipeWriter`, `CallbackTarget` | Nonisolated |

## Appendix B. Hardware assumptions (Beta until tested)

- `.forSession` trial + `.permanently` on Keep persists.
- XDR A/B.
- Media keys on AS and 27.
- MCDP DDC.
- Single-mode virtual creation entering HiDPI.
- `applySettings` on a live virtual.
- Gamma on the virtual for pairs.
- MonitorPanel in the guard.
- Night Shift.
- Disclaim and the responsible-pid check.
- HDCP over mirrors.
- Clamshell notification.
- Virtual displays across Fast User Switching.
- AX trust on 27 without a relaunch.
- Code-signing parent check after an update.

## Appendix C. Parity ledger (self-contained)

Legend: In · Partial (substitute) · X · Deferred · Excluded · N/A.

| § | Item | Status |
|---|---|---|
| 2.1 | Mode menu: tags, markers, Show all | In (Show all = X); mirror-target mode changes Deferred |
| 2.2 | Slider: %/W×H, snapping, native aspect | In |
| 2.3 | HiDPI toggle | In |
| 2.4 | Flexible scaling | **Partial**: Smart HiDPI substitute (GPU, cursor, HDCP, HDR caveats); overrides Deferred |
| 2.5 | Custom scaled resolutions | **Partial**: virtual resolution lists; overrides Deferred |
| 2.6 | Model overrides (native, default, name, role) | Deferred |
| 2.7 | Favorites | In |
| 2.8 | Resolution shortcuts | In |
| 2.9 | Notch toggle | In |
| 2.10 | Range limit | In |
| 2.11 | <720p, >8K limits | In / >8K bounded by caps |
| 3.1 | Create virtual: presets, custom aspect | In |
| 3.1 | Virtual association at create | In |
| 3.2 | Name, aspect, resolutions, refresh, HiDPI, size, portrait | In |
| 3.2 | Identity edit, step multiplier, range, HDR-only, menu icon/order, 270° | Deferred |
| 3.2 | HDR virtual | X |
| 3.3 | Auto-connect present/absent, mirror, stream | In |
| 3.3 | Follow orientation | Deferred |
| 3.4 | Restore layout, reconnect after wake (sleep workaround), disconnect on lock, bulk incl. Disassociate All | In |
| 3.4 | "Reconnect remaining after one disconnects" | Deferred |
| 3.5 | Recipes: headless, recording, teleprompter, portrait | In |
| 3.5 | Salvage damaged screen, DisplayLink/Sidecar HiDPI | Deferred (manual: virtual + stream) |
| 3.6 | Virtual CLI | In |
| 4.1 | Methods: Apple, DDC, gamma, overlay | In |
| 4.1 | Metal dim overlay | Deferred (XDR A only) |
| 4.1 | Compositor filter | Excluded (private) |
| 4.1 | Overlays in screenshots | In (always excluded, best effort) |
| 4.1 | Lock-screen priority | Excluded |
| 4.2 | Combined, switchover, min HW, dim to black, snaps | In |
| 4.2 | HW/SW sub-sliders, "redefine 0%", gamma strength | Deferred |
| 4.3 | Nits (manual + model table) | In |
| 4.4 | Upscaling A/B + calibration + hysteresis | In (Beta) |
| 4.4 | Direct XDR | Deferred |
| 4.4 | Native legacy | Excluded |
| 4.5 | Restore: brightness / adjustments / off, floor | In |
| 4.6 | Dim on lock | **Partial** (gamma only; can't draw over the lock screen) |
| 4.7 | Sync basic | In |
| 4.7 | Nits-normalized | Deferred |
| 4.8 | Auto-brightness toggle | X |
| 4.8 | Lux | Deferred |
| 5.1 | Contrast, gamma (+RGB), gain (+RGB), temperature, black/white, invert | In |
| 5.1 | Highlight/shadow/saturation on displays, compositor effects | Deferred |
| 5.2 | LUTs on PIP/streams | In |
| 5.2 | LUTs on displays | Deferred |
| 5.3 | Framebuffer remap | Deferred |
| 5.4 | Dithering | Excluded |
| 5.5 | Uniformity | Excluded |
| 5.6 | Underscan (native) | X |
| 5.6 | Forced underscan | Excluded |
| 5.7 | Rounded corners | In |
| 5.8 | Profile picker + actions | In |
| 5.8 | Factory removal | Excluded |
| 5.8 | Auto SDR/HDR | Deferred |
| 5.8 | Custom-profile safeguard | In |
| 5.9 | Apple presets select | X |
| 5.10 | Night Shift + strength | X |
| 5.10 | Dark Mode, True Tone, keyboard backlight, off-in-HDR | Deferred |
| 5.11 | Night Shift for TVs | Deferred (overrides) |
| 5.12 | E-book | Deferred |
| 6.1 | DDC controls, caps, auto-config, tuning, inputs, custom codes, raw | In (4-tier policy) |
| 6.2 | CEC | Deferred |
| 6.3 | Network TVs/AVRs | Deferred |
| 6.4 | DisplayLink controller | Deferred |
| 6.5 | Volume (3 policies), mute, feedback | In |
| 6.6 | Custom controls | **Partial**: command actions In; ranged/toggle with placeholders Deferred |
| 6.7 | Header power switch | In |
| 7.1 | Soft disconnect + rules, auto-disconnect built-in | In (Beta; X on Intel) |
| 7.1 | Aggressive disconnect, Sidecar retention | Deferred |
| 7.2 | Mirroring | In |
| 7.3 | Groups | **Partial**: layouts (trust, auto-apply) + sync + protection; custom groups Deferred |
| 7.3 | UI scale matching | In |
| 7.4 | Arrange canvas + Position/Align (16) | In |
| 7.5 | Main | In |
| 7.6 | Protection: mode, refresh, main, mirror, rotation, position | In |
| 7.6 | Profiles, HDR, color mode | Deferred |
| 7.7 | Rotation | In (Beta) |
| 7.8 | Refresh (ordinary, VRR) | In |
| 7.8 | NTSC extras, reporter | Deferred |
| 7.9 | Color mode | Deferred (spike) |
| 7.10 | Intel depth | Deferred |
| 7.11 | HDR toggle | X |
| 7.11 | Forced HDR | Excluded |
| 7.12 | Redetect (re-enumerate + re-query) | In |
| 7.12 | Reinitialize, VMM7100 | Excluded |
| 7.13 | Swap | Deferred (Identify In) |
| 7.14 | Identification tiers, forget (90 days), transfer, offline list | In |
| 7.15 | Prevent sleep | In |
| 7.16 | Sidecar | Deferred |
| 7.17 | Adaptations | Excluded |
| 7.18 | System reset | Excluded |
| 7.18 | Forget all (app) | In |
| 8.1 | PIP: levels, click-through, opacity, lock, aspect, integer, crop, flip/rotate, FPS, cursor, warp, filters, auto-start | In |
| 8.1 | Tabs/merge, magnification > 100%, bring to mouse screen | Deferred |
| 8.2 | Streaming full set | In |
| 8.2 | Cursor exclusion, self-stream filters | Deferred |
| 8.3 | Teleprompter, portrait | In |
| 8.4 | Filter window | Deferred |
| 8.5 | Selected content (picker) | In |
| 8.6 | Filters (list §10) + LUT | In |
| 8.6 | Blend modes | Deferred |
| 8.7 | Stream/PIP shortcuts | In |
| 9.1–9.4 | Keys, policies, targets, steps | In |
| 9.5 | Shortcuts (full action list) | In |
| 9.6 | OSD styles/positions/targets | In |
| 9.6 | Third-party OSD dispatch | In (broadcast) |
| 10.1 | CLI | In (socket) |
| 10.2 | Console | Deferred |
| 10.3 | URL scheme | Deferred |
| 10.4 | HTTP | Excluded |
| 10.5 | DNC commands | Excluded |
| 10.6 | OSD broadcast | In |
| 10.7 | Shortcuts | via CLI; App Intents Deferred |
| 10.8 | AppleScript | Deferred (security) |
| 10.9 | Events → hooks | In |
| 10.10 | Stream Deck / Raycast | In (CLI recipes); HTTP plugins Excluded |
| 10.11 | Licensing | Excluded |
| 10.12 | Hidden defaults | N/A (pipAutoWarp → PIP "warp" setting; halo Deferred; sleep-prevention defaults N/A) |
| 11.1 | EDID read/export | In |
| 11.2–11.4 | EDID override/write | Excluded |
| 11.5 | Diagnostics report | In |
| 11.5 | Link info, DPCD, DSC | Deferred |
| 12 | Menu | In: per-item visibility, sliders, collapsible blocks, scroll-on-slider, main first, icon choice/hide/"hide when no externals", right-click quick menu, per-display name/icon/order/hide |
| 12 | Sidebar / detachable presentations | Deferred |
| 13 | Launch at login, Safe Mode, export/import, reset, toasts | In |
| 13 | Updates = Releases link | In |
| 13 | Dock-icon policy | N/A (LSUIElement) |
| 13 | Localization | Deferred |

## Appendix D. First hardware session

1. Trial → Keep → quit → relaunch → reboot: does the change persist? Mixed scope.
2. XDR A/B on M1–M5 XDR panels, on 26 and 27; gamma on a virtual on M5.
3. DDC: AS USB-C, HDMI, MCDP, Intel.
4. Virtual: single-mode HiDPI at creation; multi-mode default; `applySettings` live; remembered-mode override; kill.
5. Media keys on an AS laptop, 26 and 27; key-up behavior.
6. MonitorPanel in the guard; HDR revert after reboot via the permanent-ops journal.
7. Disclaim + responsible pid; the canary.
8. Clamshell notification; virtual + lid closed + no external → sleep?
9. `kill -9 Snaptic` with 2 virtual screens + an armed trial: the guard reverts and the hosts exit ≤ 3 s.
10. Fast User Switching with Smart HiDPI in both sessions.
11. In-place update while running: helpers refused, "Unprotected" badge.
12. Auth-window detection on 26 without Screen Recording.

## Appendix E. Round-3 findings → resolution

**Parity:**

| Finding | Resolution |
|---|---|
| B1 relaunch | §3.2 Relauncher + `--relaunch-from`, resumable onboarding |
| B2 trust | §9.7 trust stamp |
| M1 27 dead-ends | §1.1.1, §1.1.4, §8.3 |
| M2 auto-apply triggers | §4.11 (launch, wake, connect, resume) + `ToastPresenter` |
| M3 key leaks | §2.2 swallow |
| M4 duplicate toggles | §2.2 Features-only |
| M5 chips | §3.7 multi-select, "More (no Beta)" |
| M6 Req(any) availability | §2.1 |
| M7 controller and page map | §2.1 columns |
| M8 presets vs switches | §2.1 field gating, §9.7 |
| M9 XDR keys, drift, ±, hysteresis | §6.4 |
| M10 ledger | Appendix C |
| Minors | VoiceOver split, style vs position, profile warning, single Menu page, naming, `WindowGatherer`, volume policies, shortcut coverage, nits table, DDC 0% switchover, snaps, recipes, research spike owner, DDC caps in diagnostics |

**Security:**

| Finding | Resolution |
|---|---|
| R3-1 helpers | disclaimed + cdhash check + code-signing parent check |
| R3-2 canary and stopped-check | §3.2 |
| R3-3 import strip | §3.4 |
| R3-4 lookalike guidance | §1.1.1 path + Finder |
| R3-5 trust | stamp with tier-1 fingerprints + OS |
| R3-6 environment and argv | §3.2 |
| Lows | `busy` cap, `cliAllowed`, closed broadcast enum + rate, start-time-checked kills, order out (never lower), session-dictionary for all resumes, allow binds code+value, sleep-prevention text, CoreImage allowlist, EventLog rule, MDM documented |

**Code:**

| Finding | Resolution |
|---|---|
| B1 Kit vs app types | A.0 |
| B2 undeclared types | A.0–A.4, §13 |
| B3 controller map | §2.1 |
| M4 isolation | rule 14 |
| M5 weak context | §3.6 |
| M6–M8 writer, reader, CLOEXEC | §3.2 |
| M9 relaunch | §3.2 |
| M10 menu rebuild | §3.5 |
| M11 hook order | §4.10 |
| M12 tap generation | §8.1 |
| M13 `busy` | §4.5 |
| M14 extensions lint | §13 |
| M15 generator | §13, §14.1 |
| Minors | adopted |

**Platform:**

| Finding | Resolution |
|---|---|
| B1 pipeline | `ConnectPlanner` + `restore` risk |
| M1 HW mirror enumeration | §4.1 |
| M2 single-mode creation | §9.3 |
| M3 grace, rebind, primaries, gamma on virtual, PQ | §4.11, §9.5, §6.2 |
| M4 hang kills hosts | §4.5 |
| M5 persisted choice | §4.11 step 4, Safe Mode, panic 60 s |
| M6 auth windows by pid path | §4.10(10) |
| M7 update path, fd test | §3.2, §14.1 |
| M8 `headlessPrimary` | §4.1 |
| M9 permanent-ops journal | §4.6 |
| M10 FUS | §4.5, §4.9 |
| M11 restore bypass | inv. 6, §4.5 |
| M12 protection | §9.6 |
| Minors | strip flags, OSD anchor, per-press keys, F14/F15 Carbon, clamshell notification, XDR undocumented + fail-closed, split batches + skip-equal, wake grace, unsalted virtual identities, bytes cap, restored r2 minors, PIP refresh cadence |
