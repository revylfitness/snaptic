# Snaptic 0.4 plan: Hidden Icons module (DRAFT r1)

> **Status: draft r1. The owner's scoping answers are folded in; the review rounds in §R are still to come.**
> Those reviews turn this draft into `PLAN.md`.

## Owner decisions (2026-11-07; not reopened)

| Q | Decision |
|---|---|
| Q1 | **Two engines.** The Native engine (private `MenuBarClientCore` assertion) on macOS 27 and later. The Length engine (an inflated separator) on macOS 14–26. |
| Q2 | **Full Hidden Bar parity**, plus the three fixes (§4.3–§4.5). This includes **"Use full menu bar on expand"** (§4.9) and hover-to-expand. |
| Q3 | **⌘-drag and a Settings list.** The live sections list is shown on every macOS. Per-app "Always Show" / "Always Hide" overrides exist on Native only. |
| Q4 | **A fourth module named "Hidden Icons".** Its tab is called "Icons" (⌘4), and its CLI is `snaptic icons …`. |
| Q5 | **The private API is handled like Snaptic's other private APIs**: resolved at runtime, checked before use, behind a kill switch, failing open. It ships with no extra opt-in and is listed in the README's Undocumented APIs. |
| Q6 | **Released as 0.4.0 (CFBundleVersion 400), off by default.** It gets a "New: Hidden Icons" card and an opt-in onboarding step. The uncommitted "Onyx Latch" app icon (`Resources/AppIcon.*`, `scripts/build-icon.sh`, the Info.plist and build-app.sh changes) ships in 0.4.0 as its own commit. |

## 0. What 0.4 adds

0.4 adds a fourth module, **Hidden Icons**, that does what [Hidden Bar](https://github.com/dwarvesf/hidden)
does. Hidden Bar is MIT-licensed; this plan is based on v1.11.1, commit `47937b9`.

1. An arrow icon in the menu bar collapses or expands a **Hidden** section of other apps' icons.
2. An optional **Always Hidden** section appears only while you hold ⌥ and click, or choose it from the menu.
3. Auto-collapse after a delay, a global shortcut, and a list in the Snaptic menu of icons that are hidden or
   covered by the notch, where clicking one opens it.

The module follows every Snaptic module rule:

- It has its own on/off switch, and while it is off it costs nothing: no status items, timers, monitors, or
  permission prompts.
- It has its own Settings page with an Advanced… sheet, search, Restore Defaults, and an onboarding card.
- It has kill switches, `snaptic` CLI verbs, and EventLog counters (counts only, never app names).
- Its pure logic lives in SnapticKit and is tested on Linux.

We write our own code. We reuse Hidden Bar's *design* (the engine split, the layout resolver, the order in which
the assertion is swapped) and credit it in `THIRD_PARTY_NOTICES.md`. No file is copied verbatim.

## 1. What the source teaches (survey summary)

| Hidden Bar part | How it works | Snaptic decision |
|---|---|---|
| Three `NSStatusItem`s: arrow, separator `\|`, always-hidden separator | Section boundaries come from the positions of the items, which the user arranges with ⌘-drag | Same model. Autosave names: `Snaptic.icons.toggle`, `Snaptic.icons.separator`, `Snaptic.icons.alwaysHidden` (no clash with `Snaptic.<moduleID>` or `SnapticAwake`) |
| `LegacyLengthEngine` (macOS ≤ 26) | Collapsing sets the separator length to `max(500, min(2×widest screen, 10 000))` so it pushes everything to its left off-screen. The length is re-applied when screen parameters change | Port it as the **Length engine**, used only on macOS 14–26 **[Q1]** |
| `NativeVisibilityEngine` (macOS 27) | The private `MenuBarClientCore` `MBAssessmentModeAssertion` (the API behind exam mode) is given an allow-list: system items 0..<63, the bundle ids of apps in the visible section, and its own bundle. macOS hides everything else, and the restriction ends when the process dies | Port it as the **Native engine** through a SnapticShims ObjC shim **[Q1][Q5]**. **Verified on this Mac (27.2, 26B123):** both classes and every selector Hidden Bar uses are present (`initWithAllowedSystemItems:allowedBundleIdentifiers:`, `activateWithConfiguration:completionHandler:`, `invalidate`), plus `initWithUnrestrictedMenuBarItems` |
| `AccessibilityMenuBarInventory` | Walks `AXExtrasMenuBar` for every running `.app`: about 1 s on a background queue, 0.1 s AX timeout | Port it. It is needed by the Native engine and by the hidden-icon list. The Length engine works without it, so 14–26 needs **no permission** for basic hiding |
| `MenuBarLayoutResolver` | Assigns each item a section by its midX against the boundaries, mirrored for RTL. The most visible section wins per bundle. System owners and its own bundle are skipped | Port it to Kit as pure logic, with Hidden Bar's test cases plus new ones |
| `StatusBarController` | Auto-collapse timer (10 s), hover-to-expand (global `mouseMoved` with a 0.5 s dwell), a 0.3 s debounce, collapse 1 s after launch, ⌥-click, and "use full menu bar" (activation policy `.regular`) | The policy goes to Kit (`IconsPolicy`), the wiring to the app. Hover and full menu bar depend on **[Q2]** |
| `NotchOverflowController` | Lists the extras whose minX ≥ `auxiliaryTopRightArea.minX`, and AXPress opens one | It becomes the hidden-icon list (hidden **and** notch-covered) in the module's Snaptic-menu tab **[Q2]** |
| Known issues | New icons appear in the hidden zone. Always Hidden is reliable only with the separators hidden. Auto-collapse can fire while another app's menu is open | Fixed by design: §4.4 (new-icon policy), §4.3 (zero-length always-hidden separator on every engine), §4.5 (menu-open guard) |

Notes for macOS 27 (from `docs/design/macos27.md` §Menu bar):

- The whole menu bar is one window, so moving item windows is impossible. That is why the Length engine breaks on
  27 (an inflated item is ejected from the bar; Hidden Bar issue #360).
- Right-click and local event monitors on status items are unreliable on 27. Use a stock `button` with
  `sendAction(on:)`, and `NSApp.currentEvent` only to read the modifier flags.
- macOS's own System Settings › Menu Bar can hide items. Items it has hidden are not in the AX tree, so we can't
  list them. This is documented as a limitation.

## 2. Architecture

```
SnapticKit (Foundation-only, Linux-tested)
  Icons/IconsModel.swift        section enum, item snapshot, Rect, boundaries, engine state
  Icons/IconsLayout.swift       layout resolver (LTR/RTL, most-visible-wins, skip lists, notch-covered)
  Icons/IconsEngineCore.swift   engine state machine over protocols (Visibility, Inventory, Items, Clock)
  Icons/IconsPolicy.swift       click resolver, debounce, auto-collapse + hover + menu-open + new-icon decisions
  Icons/IconsConfig.swift       config slice, sanitize, defaults, migration, backup filter
  Icons/IconsControls.swift     *Controls table, settings index, CLI grammar ("icons" verbs)
SnapticShims
  SNMenuBarVisibility.h/.m      dlopen + NSClassFromString + respondsToSelector + @try/@catch; no linking
Snaptic (app)
  Icons/IconsModule.swift       SnapticModule conformance, start/stop, menuSection(tabbed:)
  Icons/IconsItems.swift        the three NSStatusItems, autosave, first-run order seeding, click wiring
  Icons/NativeEngine.swift      Visibility port → SNMenuBarVisibility (generation counter, activate-then-invalidate)
  Icons/LengthEngine.swift      Visibility port → separator length
  Icons/AXInventory.swift       Inventory port (background queue, 0.1 s timeout, own-pid skip)
  Icons/IconsMonitors.swift     auto-collapse timer, hover monitor, workspace launch/terminate, screen params
  Icons/IconsCLI.swift          ControlCommandRegistry verbs
  Icons/UI/IconsPage.swift, IconsAdvancedSheet.swift, IconsMenuRows.swift, HiddenListMenu.swift
```

The engine state machine is in Kit, written against small protocols. Hidden Bar's
`MenuBarEngineTests` (FakeItems / FakeInventory / FakeVisibility) port almost line for line, and they run on Linux.

## 3. Host changes (each one touches a closed enum, so there are many sites)

- **H1. `ModuleID`** gains `.hiddenIcons` (raw value `hiddenIcons`), last in start order. All 84 switch sites over
  `ModuleID` / `case .windowSwitcher` (31 files) are updated. lint's exhaustiveness rule catches any that are
  missed.
- **H2. Menu presence.**
  - The arrow is the module's own icon and always shows while the module is on, so
    `MenuPresence.allowed(for: .hiddenIcons) == [.ownIcon]`.
  - The Menu Bar page shows a fixed row, "Hidden Icons: the arrow shows while Hidden Icons is on", instead of a
    pop-up.
  - Its Snaptic-menu tab is opt-in: "Show Hidden Icons in the Snaptic menu" (default on).
  - The tab shortcuts grow to ⌘1–⌘4, and `MenuTabs.keyIndex` / `barHelp` are tested with 4 tabs.
- **H3. Kill switches.**
  - `Modules.disable.hiddenIcons` turns the whole module off.
  - New prefix `Icons`: `Icons.disable.native`, `Icons.disable.length`, `Icons.disable.inventory`,
    `Icons.disable.hover`, `Icons.disable.axpress`.
- **H4. Permissions.**
  - `requiredPermissions` is `[.accessibility]` only when the Native engine is used, the hidden-icon list is on,
    or the new-icon policy needs the inventory. Otherwise it is `[]`.
  - A Permissions page row: "Hidden Icons (macOS 27, or the hidden-icon list)".
  - On 27 the relaunch hint shows, because grants often need a relaunch.
- **H5. Onboarding** gets a "Hidden Icons" card. Turning it on asks for Accessibility only if H4 says so. A
  "New: Hidden Icons" card goes in General (`NewModuleCard.hiddenIcons`).
- **H6. Safe Mode / quit / Sparkle relaunch / Restore Defaults / Reset All Settings.**
  - Each of these calls `stop()`, which **expands first**: it invalidates the assertion or sets the length back
    to 20.
  - Reset All Settings also clears the three `NSStatusItem Preferred Position Snaptic.icons.*` keys.
- **H7. Backup.** Export includes the module's settings but leaves out item positions and anything containing
  bundle ids (the new-icon allow-list, §4.4). Import sanitizes.
- **H8. SelfTest** gains `icons.shim`: the shim resolves, and the configuration object builds with empty arrays.
  It never activates an assertion.
- **H9. One activation-policy owner.** Today three places switch the policy: `SettingsWindowHost.show` and
  `windowWillClose`, `Onboarding`, and `SnapticEntry`. They become one host `ActivationPolicyController`, backed
  by a Kit rule:

  ```
  regular ⇔ settingsOpen ∨ onboardingOpen ∨ (icons.fullBarOnExpand ∧ icons.expanded)
  ```

  Each place then reports a reason instead of setting the policy directly. This means closing Settings while the
  icons are expanded with the full bar can't drop Snaptic back to accessory, and collapsing the icons can't hide
  an open Settings window. The rule gets a Kit truth-table test.

## 4. Behaviour

### 4.1 Sections and engines

- Order, left to right in LTR: `[always-hidden ⋮] … [separator |] … [arrow ‹] [Snaptic + system items]`.
  Visible items are to the right of the arrow. Mirrored in RTL.
- `IconsEngineFactory`:
  - macOS ≥ 27 uses Native when the shim resolves and the kill switch is clear. Otherwise the module shows
    "unavailable".
  - macOS 14–26 uses Length.
  - **[Q1]** decides whether 14–26 is supported at all.
- **Native engine.** Collapse works like this:
  1. Read the inventory.
  2. Resolve the layout.
  3. Allow the system items, the visible-section bundles, `app.snaptic.Snaptic`, and the new-icon allow-list.
  4. Activate assertion N+1, then invalidate N.
  - A stale completion (generation mismatch) is dropped.
  - Expand invalidates.
  - While something is collapsed, the layout comes from the cache, because only an unrestricted bar can be read.
  - If the API is unavailable the bar fails open, with one notice per launch.
  - When Accessibility is missing, it prompts once, then retries when the grant arrives.
- **Length engine.** Collapse sets the separator length to `max(500, min(2×widest, 10 000))`. Expand sets it to
  20. The length is re-applied on `didChangeScreenParameters`.
- **Always Hidden.** Collapsed, the separator length is 0. Expanded with ⌥, it is 20 and its section shows. This
  works on both engines and fixes Hidden Bar's "only reliable with separators hidden" problem. Native excludes
  the always-hidden bundles even while the hidden section is expanded.

### 4.2 Clicks (stock button, no event monitors on the item)

| Input | Action |
|---|---|
| Left click / VoiceOver AXPress (nil event) | Toggle Hidden |
| ⌥-click | Expand including Always Hidden (or collapse all) |
| ⌃-click / right-click | Open the module menu if macOS delivers it. Not relied on: everything is also in the Snaptic-menu tab and Settings |

There is a 0.3 s debounce. The menu is built fresh on each open.

### 4.3 Separators

The setting "Show section dividers" (default on) makes the `|` and `⋮` visible when expanded. Off makes them
zero-width when expanded. On Native the separator is always invisible, because the arrow is the boundary, as in
Hidden Bar.

### 4.4 New icons (fixes Hidden Bar's #1 complaint)

- The workspace `didLaunchApplication` notification, observed only while collapsed, plus an inventory re-read
  after 2 s.
- **Native:** a newly appearing bundle is added to the allow-list (the policy setting "New icons: Show until I move
  them / Hide"). It stays shown until the user ⌘-drags it into a section, then follows its position.
- **Length:** new icons appear at the far left, which is in the hidden zone. Snaptic can't move them, because that
  would need synthetic ⌘-drags, which Snaptic excludes by design. A one-time notice explains this, and the
  hidden-icon list shows the icon.

### 4.5 Auto-collapse and hover

- **Auto-collapse** (default on, 10 s, 2–300 s). The timer is re-armed while:
  - the pointer is in the menu-bar band;
  - the Settings window is key;
  - **a pop-up menu window is on screen** (CGWindowList layer ≥ `kCGPopUpMenuWindowLevel` touching the menu-bar
    band; bounds only, so no Screen Recording is needed).

  This fixes "collapses while another app's menu is open".
- **Hover-to-expand** **[Q2]**: a global `.mouseMoved` monitor that exists only while the setting is on and the
  bar is collapsed. Dwell 0.5 s. The `Icons.disable.hover` kill switch turns it off.
- **Collapse at launch:** 1 s after the module starts, if "Hide icons when Snaptic opens" is on (default on).

### 4.9 Use full menu bar on expand (Q2 parity; Advanced, default off)

When this is on, expanding makes Snaptic the active app through H9 (policy `.regular`, then `activate()`).
Snaptic's short app menu then replaces the frontmost app's long menus, which leaves more room for icons.

- Collapsing removes the reason. The policy goes back to `.accessory` only if no other reason holds, then
  `NSApp.deactivate()` runs.
- A failed collapse (the engine is unavailable or waiting for a permission) keeps the reason, as Hidden Bar's
  `didFailToCollapseMenuBar` does.
- A Dock icon appears while the bar is expanded. The help text says so: “While icons are shown, Snaptic becomes
  the active app so its short menu leaves more room. Its icon appears in the Dock until the icons are hidden
  again.”
- The previously frontmost app is remembered (`NSWorkspace.frontmostApplication`, held weakly) and reactivated on
  collapse if it still exists.
- This is not offered while the Window Switcher is mid-switch, because the switcher's own focus handling wins.

### 4.6 The hidden-icon list (Snaptic-menu tab and ⌃-click menu)

- "Show Hidden Icons" / "Hide Icons", then a list of icons that are hidden or covered by the notch: app icon, app
  name, and a count when an app has several icons.
- Choosing one performs AXPress on that extra. When the item is hidden by Native, it first expands, waits for
  reflow (≤ 300 ms, polling the AX position), presses, and the auto-collapse timer re-arms.
- It is read lazily when the menu opens, from the cached inventory plus a background refresh.

### 4.7 Shortcut and CLI

- One global shortcut, "Show or Hide Icons" (unset by default), through `GlobalHotkeys` with the `KitHotkeys`
  conflict rules.
- CLI:
  - `snaptic icons show|hide|toggle|status [--all]`.
  - `status` prints the engine, the state, and the counts per section. It never prints names.
  - The verb is gated off while the module is off, with the same message as the other modules.

### 4.8 Settings page (Hidden Icons)

- **Switch row and highlights** (off state):
  - "Hide the icons you don’t need"
  - "Keep some icons hidden even when expanded"
  - "Open hidden icons from the Snaptic menu"
- **Main page:**
  - Status row: the engine, the state, and how many icons are hidden.
  - "Hide icons automatically after [10] seconds".
  - "Hide icons when Snaptic opens".
  - "Always Hidden section" toggle.
  - "Show section dividers".
  - Shortcut.
  - A "How to arrange" help panel (⌘-drag), with a small diagram.
- **Sections preview** (needs Accessibility): a read-only list per section, each icon with its app name, plus a
  "Refresh" button. On Native only, each row has "Always Show" / "Always Hide" per-app overrides **[Q3]**.
- **Advanced… sheet:**
  - Hover to expand.
  - New-icons policy.
  - "Show Hidden Icons tab in Snaptic menu".
  - Engine diagnostics: engine name, shim availability, the last error code.
  - Restore Defaults.

## 5. Work items (lettered; implemented in this order)

| ID | Item | Where | Done when |
|---|---|---|---|
| **S0** | Step 0 spike. A throwaway CLI in `/tmp` uses the shim against the real framework on 27.2. It activates an allow-list `[]` + `[Finder]` for 5 s and checks that it reflows and recovers on exit and on SIGKILL. It measures the AX inventory time. It checks that `NSStatusItem Preferred Position` seeding sets the first-run order | `/tmp` and `STEP0-NOTES.md` | Notes written. Fail-open on crash confirmed |
| **K1** | `IconsModel` + `IconsLayout` + tests (Hidden Bar's resolver cases, plus notch-covered, multi-display, RTL, empty inventory) | Kit | Linux tests green |
| **K2** | `IconsEngineCore` state machine + fakes + tests (all 8 of Hidden Bar's engine cases, plus the new-icon allow-list, kill switch mid-collapse, stop() always expands) | Kit | Green |
| **K3** | `IconsPolicy`: click resolver, debounce, auto-collapse re-arm reasons, hover dwell, launch collapse | Kit | Green |
| **K4** | `IconsConfig` slice, defaults, sanitize, backup filter, `ModuleID` / `NewModuleCard` / `MenuPresence.allowed` | Kit + host enums | Green, plus migration test (0.3.4 config → 0.4 adds the slice, off) |
| **K5** | `IconsControls` table, settings index, CLI grammar + tests; MenuTabs at 4 tabs | Kit | Green; lint control-table check |
| **B1** | `SNMenuBarVisibility` shim + `IconsVisibilityBridge` (kill switch read before every resolve) | Shims + app | Builds in CI; SelfTest `icons.shim` passes on 27 |
| **A1** | `IconsItems`: three items, autosave, order seeding, click wiring | App | Manual checklist M1–M4 |
| **A2** | `LengthEngine`, `NativeEngine`, `AXInventory`, factory | App | Manual M5–M10 |
| **A3** | `IconsMonitors`: timer, hover, workspace, screen, menu-open guard | App | Manual M11–M14 |
| **A3b** | H9 `ActivationPolicyController` + Kit rule + migration of the 3 call sites; full-bar-on-expand (§4.9) | Core + Kit | Kit truth table green; manual M23–M25 (Settings open/close × expand/collapse) |
| **A4** | `IconsModule` (start/stop/zero-cost-off/state/requiredPermissions), host wiring H1–H8 | App + Core | Off-state audit: no items, timers, or monitors (EventLog counter `icons.started` = 0) |
| **A5** | Snaptic-menu tab + hidden-icon list + AXPress open | App | Manual M15–M17 |
| **A6** | Settings page, Advanced sheet, search, onboarding card, New card, Permissions row | App | Manual M18–M22; `stubs.tsv` rows |
| **A7** | CLI verbs + shortcut | App | `selftest-control-server.sh` case added |
| **D1** | README: module section, Permissions table row, Undocumented APIs (MenuBarClientCore), Known limitations, Not included (synthetic drags, per-icon hiding within one app, macOS-hidden items), Privacy (no names logged), How it works table | Docs | `lint.sh --strict` |
| **D2** | `THIRD_PARTY_NOTICES.md` Hidden Bar (MIT) design credit; release notes; version 0.4.0 (CFBundleVersion 400) **[Q6]** | Docs | — |
| **D3** | Site feature list (`site/`) | Site | Vercel preview |
| **R** | Review rounds until no Blockers/Majors; CI green; release through the existing build, sign, verify, attest, publish pipeline | — | Owner approves the release |

The manual checklist (M1–M22) goes in `docs/design/0.4/MANUAL-CHECKS.md`. It is run on macOS 27.2 (this Mac). On
macOS 14–26 **[Q1]** it needs a second machine or VM. CI can build but can't see a menu bar.

## 6. Risks

| Risk | Mitigation |
|---|---|
| Apple changes or removes `MBAssessmentMode*` in 27.x / 28 | Runtime resolve + selector check + `@try`; fail open; the kill switch; one notice; the module shows "unavailable on this macOS" instead of crashing |
| The assertion leaks visible-but-hidden state after a crash | The assertion is tied to the process. S0 verifies SIGKILL recovery. Length items vanish with the process |
| The exam-mode assertion has side effects (Control Center, notifications) | S0 checks them. The allow-list includes all system items 0..<63, as in Hidden Bar |
| Two hiders running (Hidden Bar, Bartender, Ice/Thaw) | `OtherAppsMonitor` warns when a known hider is running. Off by default, so no surprise |
| Accessibility prompt fatigue | Asked for only when needed (H4). The Length path needs none |
| Snaptic's own items | Always visible on Native (own bundle). On Length, Snaptic's items sit right of the arrow by seeding; the user can still ⌘-drag them left |
| The 4-tab Snaptic menu gets wide | MenuTabs already has short labels ("Icons") and `shortFit` |
| Notarization / hardened runtime | dlopen of a system private framework needs no entitlement (same as the existing shims) |

## 7. Not included (proposed)

- Moving other apps' icons programmatically (synthetic ⌘-drag): excluded by Snaptic's "no synthetic events"
  rule.
- Per-icon hiding inside one app that has several icons (macOS 27 hides per bundle).
- Showing items that macOS's own Menu Bar settings have hidden.
- Custom spacing or icon tinting (Bartender/Ice extras).
- A second menu bar or a floating "bar below the bar".

## Q. Scoping questions for the owner

Q1 Mechanism and OS coverage · Q2 Feature scope · Q3 How users choose what's hidden · Q4 Product shape and name ·
Q5 Private-API posture on macOS 27 · Q6 Release vehicle and default state. (The options and scores are in the
chat.)

## R. Review plan (after answers)

Parallel subagents, each given this plan, the Hidden Bar source at `/tmp/hidden-src/repo`, and the Snaptic tree:

1. **Pressure-test (engineering feasibility):** every work item against the real Snaptic code (ModuleID sites,
   StatusMenu plan, ControlServer, lint rules, stubs.tsv) and against Hidden Bar's engines. Missing steps,
   wrong file homes, untestable claims.
2. **Grill (product, scope and UX):** against README conventions, design-spec wording, module rules, and macOS
   27 HIG. Every string, default, and edge case.
3. **Adversarial (failure modes and security):** private API, crash or fail-open, AX timeouts, races (generation
   counter, launch collapse vs Settings), Sparkle relaunch, Safe Mode, privacy of bundle ids in logs, backup, and
   the CLI.
4. **Parity:** a feature-by-feature diff against Hidden Bar v1.11.1 (including BACKLOG and issues), so nothing
   is lost without a recorded reason.

Every finding gets a disposition in §R1 of the final plan.
