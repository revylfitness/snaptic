# Snaptic 0.4 plan: Hidden Icons (r2, final)

> **Status: final, pending owner approval.** On "approved", implementation runs through §6 in order until every
> item's done-when holds. History: `PLAN-draft.md` (r1), plus four r1 reviews: `review-r1-pressure.md` (P-n),
> `review-r1-grill.md` (G-n), `review-r1-adversarial.md` (X-n) and `review-r1-parity.md` (Y-n). Every finding has a
> disposition in §R1.

## What 0.4 adds

0.4 adds a fourth module, **Hidden Icons**. It does what [Hidden Bar](https://github.com/dwarvesf/hidden) does
(MIT; this plan follows v1.11.1, commit `47937b9`), plus fixes for that app's top complaints.

- An arrow in the menu bar hides and shows the icons to its left: the **Hidden** section.
- An optional **Always Hidden** section stays hidden until you ⌥-click the arrow or choose **Show All Hidden Icons**.
- Icons can hide again automatically, a global shortcut toggles them, and the Snaptic menu lists hidden and
  notch-covered icons, so you can open one without showing them all.
- On macOS 27 and later, per-app **Always Show** / **Always Hide** choices, and a policy for icons from newly seen
  apps.

It is off by default, ships in **0.4.0 (CFBundleVersion 400)**, and gets a "New: Hidden Icons" card plus an opt-in
onboarding step. The new Onyx Latch app icon ships in the same release as its own commit.

## Owner decisions (2026-11-07; not reopened)

| Q | Decision |
|---|---|
| Q1 | **Two engines.** The **Native** engine (private `MenuBarClientCore` `MBAssessmentModeAssertion`) on macOS 27 and later. The **Length** engine (an inflated separator) on macOS 14–26. |
| Q2 | **Full Hidden Bar parity plus fixes**, including "use the full menu bar on expand" and hover-to-expand. |
| Q3 | **⌘-drag plus a Settings Sections list** on every macOS. Per-app Always Show / Always Hide on Native only. |
| Q4 | **A fourth module, "Hidden Icons"**: tab "Icons", CLI `snaptic icons …`, `ModuleID.hiddenIcons`. |
| Q5 | **The private API is handled like Snaptic's other private APIs**: resolved at runtime, checked for the expected signature, behind kill switches, failing safe (icons shown). It's listed in the README and needs no extra opt-in. |
| Q6 | **0.4.0 (CFBundleVersion 400), off by default**, with a New card and an onboarding opt-in. The uncommitted Onyx Latch icon work ships in 0.4.0 as its own commit. |

## Ground rules (carried over from 0.3 / 0.3.1)

- **While off, the module costs nothing.** It has no status items, timers, monitors, observers or permission prompts.
  `IconsModule.init` creates nothing; everything is made in `start()`.
- **Pure logic lives in SnapticKit** (Foundation only, Linux-tested). The app holds only AppKit, AX and shim
  adapters.
- **Every private symbol** is resolved at runtime and checked for the expected type encoding before use. Any
  exception poisons it for the life of the process. Each has a kill switch. A failure always fails safe: **icons
  shown**. The plan says "fails safe (icons shown)" throughout, never "fail open" (G-18).
- **No synthetic events.** Snaptic never moves another app's icon. The user arranges with ⌘-drag.
- **No bundle ids or app names** in logs, EventLog, error text or diagnostics. Counts only (§4.15).
- **Every new file** adds its `scripts/stubs.tsv` row in the same commit. Each work item ends with
  `scripts/lint.sh --strict` clean, `swift build` and `swift test` green (§6).
- **We write our own code.** We reuse Hidden Bar's design: the engine split, the layout resolver, the order in which
  the assertion is swapped. The design is credited in `THIRD_PARTY_NOTICES.md`. No file is copied.

---

## 1. What the source teaches (survey, corrected after r1)

| Hidden Bar part | How it works | Snaptic decision |
|---|---|---|
| Three `NSStatusItem`s: arrow, separator `\|`, always-hidden separator | The user ⌘-drags to arrange, and the item positions define the sections | Same model. Autosave names `Snaptic.icons.toggle`, `Snaptic.icons.separator`, `Snaptic.icons.alwaysHidden`. On Native, `\|` is zero-length and **the arrow is the boundary** (§4.2) |
| `LegacyLengthEngine` (≤ 26) | Collapse sets `\|` to `L = max(500, min(2 × widest screen, 10 000))` (1728 with no screen), so everything to its left goes off-screen. Expand sets 20. `isArrangementValid`: `\|` on the hidden side of the arrow. State is derived from the live length (`> 20`). `verifyHideMechanismIfNeeded` checks on the next tick that the inflated width took. **macOS caps `NSStatusItem.length` at 10 000 pt** (HB PR #354) | **Length engine**, macOS 14–26 only. Same formula and guards. AH inflates `⋮` (§4.2.4) |
| `NativeVisibilityEngine` (27) | `MBAssessmentModeConfiguration initWithAllowedSystemItems:(0..<64) allowedBundleIdentifiers:` (an `NSArray`, not an `NSSet`), then `MBAssessmentModeAssertion activateWithConfiguration:completionHandler:`. Activate N+1, then invalidate N. Expand invalidates. The restriction dies with the process. While restricted, the layout comes from a cache. HB logs bundle lists (L181) and `error.localizedDescription` (L207) | **Native engine**, through a SnapticShims ObjC shim (§4.2.2). Verified present on this Mac (27.2, 26B123), with the five encodings in §4.2.2. We **don't** copy the logging |
| `AccessibilityMenuBarInventory` | Walks `AXExtrasMenuBar` for every running `.app`. About 1 s on a background queue, 0.1 s AX timeout | Ported with explicit budgets and per-app results (§4.2.6). Required by Native, the hidden list and Sections. **The Length engine hides without it**, so 14–26 needs no permission for basic hiding |
| `MenuBarLayoutResolver` | Assigns each item a section by midX against the boundaries, mirrored for RTL. The most visible section wins per bundle. Skips system owners and its own bundle | Kit, pure, with Hidden Bar's 6 resolver cases plus new ones (§6 K2). The skip requires a verified bundle path (X-22) |
| `StatusBarController` | Auto-collapse 10 s (5/10/15/30/60 s menu); re-arms while the pointer is in the band or Preferences is visible; restarts the timer on any pref change; 0.3 s debounce (click and hotkey); collapse 1 s after launch; ⌥-click toggles a *persisted* "separators hidden / AH shown" mode; hover (default off, 0.5 s dwell); full bar (activation policy `.regular`); forces `isVisible = true` at start; refuses collapse with an invalid arrangement and re-arms | Kit `IconsPolicy` and `IconsIntentQueue` (§4.3–§4.6). ⌥ becomes one-shot (§4.3, Y-8) |
| `ExpandCollapseAction` | nil / left → toggle; ⌥ with any button → mode; right → menu; other button → separators | Remapped in §4.3 (6 cases ported) |
| `NotchOverflowController` | Splits the extras on `NSScreen.main` at `auxiliaryTopRightArea.minX` (fallback 972): x < boundary is "behind the notch". Lists **both** sections, one row per extra (AX title), and AXPress opens one | The **hidden list** (§4.8): per extra, Hidden plus Behind the Notch, per screen (X-19) |
| Menu | Show Notch Items, Preferences…, Enable/Disable Auto Collapse, Quit. Clicking `\|` also opens it | §4.3 menu, minus Quit (the Snaptic menu has it) |
| Known issues | New icons land in Hidden; AH is reliable only with separators hidden; auto-collapse fires while another app's menu is open; a copy outside `/Applications` hides its own arrow; RTL detection follows the app's localization | Fixed by design: §4.5, §4.2.4, §4.6, §4.2.2 identity check, §4.1 direction |

**macOS 27 notes** (`docs/design/macos27.md` §Menu bar):

- The bar is one window, so the Length engine breaks on 27 (an inflated item is ejected; HB #360).
- Right-click and local event monitors on status items are unreliable. Use a stock `button` with
  `sendAction(on: [.leftMouseUp, .rightMouseUp])`, and read modifiers from `NSApp.currentEvent`.
- `button.highlight` doesn't render, so state is carried in the glyph.
- System Settings › Menu Bar can hide any item, including the arrow, and hidden items are absent from the AX tree.
  Documented as a limitation; recovery is in §4.1.

---

## 2. Architecture and file homes

```
SnapticKit (Foundation only, Linux-tested; flat, module-prefixed, P-14)
  IconsModel.swift            IconsSection, IconsItemRole, IconsRect, IconsExtra (pid, bundle, index, frame, title?),
                              IconsInventory (+ per-app result), IconsEngineState, IconsFailSafeReason, IconsFeature
  IconsLayout.swift           resolver (LTR/RTL, x only, screen-clipped), most-visible-wins, skip rules, notch split,
                              arrangement guards, own-items guard inputs
  IconsEngineCore.swift       state machine over ports: IconsItemsPort, IconsVisibilityPort, IconsInventoryPort,
                              ClockNow; generation tokens, activation timeout, request joining, Length truth table
  IconsIntentQueue.swift      the single intent queue (§4.4), debounce, suppression windows
  IconsPolicy.swift           click resolver, auto-collapse re-arm, hover dwell, launch-collapse gate, stable-inventory
                              gate, new-icon rules, ownItemsGuard, other-hider pause, exam guard, AX state table
  IconsActivationRule.swift   H9 rule (activation policy and focus)
  IconsCommandGrammar.swift   `icons` verbs, help, errors, --json shape
  KnownMenuBarHiders.swift    bundle ids (verified in S0)
  Config/ConfigIcons.swift    IconsConfig (settings) + IconsAppsState (bundle-id data), sanitize, defaults, backup
  Controls/IconsPageControls.swift, IconsAdvancedSheetControls.swift, IconsSectionsPageControls.swift,
           IconsMenuRowsControls.swift, IconsItemsControls.swift          (one per view/builder, lint L15)
SnapticShims
  include/SNMenuBarVisibility.h, SNMenuBarVisibility.m   (+ import in include/SnapticShims.h)
Snaptic (app)
  Icons/IconsModule.swift         SnapticModule: start/stop, state, menuSection(tabbed:), requiredPermissions
  Icons/IconsItems.swift          the three items (implements IconsItemsPort), autosave, seeding, glyphs, VO, clicks
  Icons/PrivateMenuBarAPI.swift   encoding checks (KitEncoding.Requirement), kill switch reads, token bookkeeping
  Icons/NativeBackend.swift       IconsVisibilityPort → SNMenuBarVisibility
  Icons/LengthBackend.swift       IconsVisibilityPort → separator lengths, verify-on-next-tick, screen re-apply
  Icons/AXInventory.swift         IconsInventoryPort (background queue, budgets, own-pid skip), AXPress
  Icons/IconsMonitors.swift       timers (.common modes), hover, workspace, screen, session/wake, MenuBarAgent watch,
                                  menu-open guard (CGWindowList bounds only)
  Icons/IconsWatchdog.swift       heartbeat thread (§4.11)
  Icons/IconsCLI.swift            ControlCommandRegistry verbs
  Icons/UI/IconsPage.swift, IconsSectionsPage.swift, IconsAdvancedSheet.swift, IconsArrangeSheet.swift,
           IconsMenuRows.swift (Snaptic-menu section, the arrow's menu, the hidden list)
  Core/ActivationPolicyController.swift   H9
```

The Kit core never sees an `NSStatusItem`. It talks to `IconsItemsPort` (`frame(of:) -> IconsRect?`,
`setLength(_:for:)`, `length(of:)`, `isVisible(_:)`) and records commands, so the tests assert on recorded lengths
(P-3). Hidden Bar's tests port as behaviour, not line for line. Sources: `HiddenBarTests/MenuBarEngineTests.swift`
(6 resolver + 10 Native + 1 Length) and `HiddenBarTests/ExpandCollapseActionTests.swift` (6).

---

## 3. Host changes

- **H1. `ModuleID.hiddenIcons`** (raw `hiddenIcons`), last in start order. Before the change, the implementer runs
  `grep -rnE '\.(windowSwitcher|displays|awake)\b|ModuleID\.allCases' Sources Tests` and records each hit with a
  disposition in `docs/design/0.4/H1-SITES.md`. The compiler covers switches without `default:`. Every `==`/`!=`
  comparison, every `default:` switch and every hard-coded list is checked by hand. There is **no** lint
  exhaustiveness rule. The known lists:
  - `SettingsRootID.groups`, plus the alias `icons` (so `open-settings icons` works);
  - the `module disable` help string and alias;
  - `SelfTestLaunch` module count;
  - `MenuLayout.shortTitle` ("Icons");
  - `SentenceText.properNames` ("Hidden Icons");
  - `EventCategory.icons` (counts only; exported in diagnostics: yes, L9-checked);
  - the `KillSwitches` doc;
  - `ModuleContext.moduleDiagnostics`, generalized from Awake-only;
  - `Onboarding` / `GeneralPages` / `MenuBarPage` `allCases` loops, with the layout checked for four.

- **H2. Menu presence and the Snaptic menu.** Design: P-2 and G-1, resolved.
  - `MenuPresence.allowed(for: .hiddenIcons) == [.inSnapticMenu, .hidden]`. The default is
    `(enabled: false, presence: .inSnapticMenu)`. `sanitized()` maps any other value to `.inSnapticMenu`. The arrow
    always shows while the module runs. Presence decides only whether the Snaptic menu carries a Hidden Icons
    section.
  - `IconsItems` owns its three items. It isn't a `StatusItemProvider`, so `ownIconIDs` and `custom` exclude
    `.hiddenIcons`.
  - `statusItemPlan`: `shared` admits `.hiddenIcons` when it is live and its presence is `.inSnapticMenu`, in start
    order, outside the Awake compact rules.
    - If Hidden Icons is the only shared module, the Snaptic item shows with the Hidden Icons section, a header,
      and the shared footer. That is the 0.3 single-module layout.
    - `everythingHidden` is false while Hidden Icons runs, because the arrow is in the bar.
    - The arrow's own menu never carries the shared footer.
  - The Snaptic item stays shown even when the hidden list is empty ("No Hidden Icons"), because it is the recovery
    path (G-1's "never show when empty" is rejected).
  - **Tabs** are unchanged and positional: ⌘n is the tab's position. Add a test with four shared modules
    (`keyIndex`, `barHelp(tabCount: 4)`, `labelStyle` and `shortFit` with four labels). The accessible-tab item is
    **Show Hidden Icons Tab**. A remembered `hiddenIcons` tab (`snapticMenuTab`) falls back to the first tab without
    being overwritten.
  - **Menu Bar page** (strings in §4.17):
    - one row **Hidden Icons**, with a pop-up of module-specific titles: **Arrow and Snaptic Menu** /
      **Arrow Only**;
    - dimmed with "Off" while the module is off;
    - new summary, footer, Restore message and 27 footer (G-11).
  - **Fuzz invariants** (`MenuLayoutTests`):
    - `.hiddenIcons` is never in `ownIcon` or `custom`;
    - it is in `shared` iff it is live and `.inSnapticMenu`;
    - `everythingHidden` is false whenever it is live;
    - tab count is `shared.count` when ≥ 2.

- **H3. Kill switches.** `Modules.disable.hiddenIcons` turns off the whole module. A new Kit
  `IconsFeature: String, CaseIterable` (`native, length, inventory, hover, axpress`) gives the
  `Icons.disable.<feature>` keys, read through `KillSwitches.read`.
  - All are read at start.
  - `Icons.disable.native` and `.length` are also observed live (`DefaultsKeyObserver`). Setting one expands at
    once (invalidate first), and the module then shows "unavailable".
  - `.native` is also re-read before each activation and each collapse (X-15).
  - Each switch shows as a `DefaultsLockRow` in Advanced › Diagnostics.
  - README Hidden kill switches lists each one with a one-sentence effect (G-30).

- **H4. Permissions.** `requiredPermissions` is constant per OS: `[.accessibility]` on 27 and later (Native can't
  collapse without it), `[]` on 14–26. On 14–26 the Sections list and the hidden list ask on demand, through the
  existing request path. Turning them on never revokes anything (P-19). The Permissions page derives its row from
  this. The row is "Hidden Icons", with the needed-for text from §4.17. On 27 the relaunch hint applies (macos27.md
  §Recommendations 1: prompt once, always open the pane, show the app path, poll). The 27 state table is in §4.12.

- **H5. Onboarding.**
  - The modules step gains a fourth row, **Hidden Icons**, off by default.
  - New welcome text.
  - A new `OnboardingStep.arrange` ("Arrange your icons"), shown only when Hidden Icons was turned on in the
    modules step.
  - On 27, the permissions step lists Device Control and Data Access for Hidden Icons.
  - The extra Done line.
  - Checked at the largest text size. If the form clips, it scrolls on that step only.
  - An unknown step decodes as `.done` on 0.3.4 (lossy), so a downgrade mid-onboarding is safe.
  - Strings are in §4.16.

- **H6. Stop, quit, Safe Mode, Sparkle relaunch, Restore, Reset.**
  - `stop()` expands first, without waiting: it invalidates every token with no completion wait, or sets the
    lengths back. It then removes the items. It never blocks termination (X-23). An `EmergencyActions` entry covers
    SIGTERM.
  - **Safe Mode skips Hidden Icons**: the module doesn't start (X-2).
  - Reset All Settings clears both stores, the `NSStatusItem Preferred Position Snaptic.icons.*` and
    `NSStatusItem Visible Snaptic.icons.*` keys, and `arranged` (Y-10, G-16).
  - Hidden Icons Restore Defaults: §4.9.

- **H7. Backup.** A new `icons` section in `KitBackup.sections` with an `allowedPaths` allowlist (as for Awake).
  - **Exported:** the settings in `SnapticIconsV1` except `arranged`.
  - **Never exported:** `SnapticIconsAppsV1` (bundle ids), positions, `arranged`.
  - Import sanitizes and keeps this Mac's apps store. `Backup.swift` export and import list the section.
  - README backup list: "Hidden Icons’ per-app choices, new-icon list, and icon positions".

- **H8. SelfTest.** `--selftest-launch` prints
  `selftest-launch: icons shim available|unavailable|poisoned`. It fails on `poisoned`, or on an encoding mismatch
  while available. On CI (macOS 15, Xcode 16.4) it must print `unavailable`. A local 27.2 run must print
  `available` (recorded in STEP0-NOTES). It never activates an assertion and never touches AX (lint rule 9). It
  still reports four modules and none running.

- **H9. One activation-policy owner.** `Core/ActivationPolicyController.swift` with reasons and tokens, backed by
  Kit `IconsActivationRule`:

  ```
  regular ⇔ settingsOpen ∨ onboardingOpen ∨ (fullBarOnExpand ∧ expanded ∧ expandCause ≠ hover ∧ ¬switcherPanelOpen)
  ```

  - It replaces the four `setActivationPolicy` sites: `SettingsWindowHost` show and willClose, `Onboarding` show and
    willClose. `SnapticEntry`'s launch default and refusal alert stay.
  - All 13 bare `NSApp.activate()` sites move to `controller.activate(reason:)`: Backup ×3, PermissionFlow,
    AppDelegate ×2, UpdaterController, Relauncher, SafeModeLeave, ConfirmPanel ×2, PreConfirmPresenter,
    SystemColorsController, PIPWindow, CustomSessionPanel. That's the measured list; the implementer re-greps.
  - When the full-bar reason ends, the controller drops to `.accessory` only if no reason is held **and** no Snaptic
    window is visible or key. It reactivates the remembered app only if no other app activated since the expand.
  - Activation is skipped while the Window Switcher panel is open (a `ModuleHost` query).
  - A new lint rule bans bare `setActivationPolicy`/`NSApp.activate` outside the controller and `SnapticEntry`.
  - Kit truth table, including `snapticWindowVisible`, `expandCause` and `switcherPanelOpen`.

- **H10. Stores.**
  - **`SnapticIconsV1`** is `ConfigStore<IconsConfig>`: settings plus `arranged`.
  - **`SnapticIconsAppsV1`** is `ConfigStore<IconsAppsState>`, which holds everything that contains a bundle id:
    - the layout cache with `readAt`;
    - `knownBundles` (bundle → last section, firstSeen, lastSeen; cap 512, LRU);
    - `newShown` (cap 64, LRU);
    - `choices` (bundle → alwaysShow | alwaysHide);
    - the per-app daily toast ledger.

    It is excluded from backup and diagnostics. Reset clears it, and Restore Defaults clears `choices` and
    `newShown`.
  - Both stores are wired into `ModuleHost.init`, `runMigrations` (forced save), `shutdown` (flush),
    `resetAllSettings` and Safe Mode's store list.
  - `ModulesConfig.defaultPreferences(.hiddenIcons)` is off. An absent entry already reads as the default.
  - Ledger marker `iconsCard.v1` adds `NewModuleCard.hiddenIcons` once, for upgraders only (not during first-run
    onboarding). `setEnabled(.hiddenIcons, true)` clears the card.
  - Pinned tests to update: `KitModulesTests:40`, `ConfigModulesTests:15/283/500`, `SettingsShellRulesTests:12`,
    `ConfigFixtures:96` (+ `fullIcons()`), `MenuLayoutTests` fuzz.

- **H11. Lint and stubs.**
  - Every new file gets its stubs.tsv row in its own commit: kind `L`, owner `lead`; `K4` for the shim header.
  - `lint03.py`:
    - add `"Icons/UI/"` to `SETTINGS_VIEWS` (L7);
    - add `Icons/UI/IconsMenuRows.swift` to L13;
    - add `under(p, "Icons/")` to L14 (`.common` run-loop modes);
    - add a new rule: no `NSLog`/`print`/`os_log` with interpolation under `Icons/`, and no bundle id or app name
      into `EventLog` (§4.15);
    - add the H9 rule.
  - Menu rows are built only through MenuKit (L6). Timer and observer closures use `MainActor.assumeIsolated`
    (rule2).

- **H12. EventLog and diagnostics.**
  - `EventCategory.icons` counters, counts only:
    - `icons.started`, `icons.collapse`, `icons.expand`;
    - `icons.failSafe.<reason>`, `icons.hangExpand`, `icons.activateTimeout`, `icons.dupCompletion`;
    - `icons.agentRestart`, `icons.systemItemHidden`, `icons.pressNoop`, `icons.inventoryTimeout`.
  - General › Diagnostics report:
    - engine; shim `available|unavailable|poisoned`; the six encodings matched (y/n);
    - kill switches; `disabledBuild`;
    - layout age;
    - the last fail-safe reason and time;
    - section counts.
  - No bundle ids.

---

## 4. Behaviour

### 4.0 First run (G-2)

- `IconsConfig.arranged` defaults to false. Reset All Settings and Reset Arrow Position… clear it. It isn't
  exported.
- **While `arranged` is false, nothing hides on its own.** There is no launch collapse and no auto-collapse. Only a
  click, the shortcut, the menu or the CLI collapses. The status row reads **“Arrange your icons, then click the
  arrow to hide them.”** with [**How to Arrange…**].
- The first collapse the user asks for sets `arranged = true`.
- Turning the module on (page switch, onboarding, New card) opens the Hidden Icons page and presents the How to
  Arrange sheet.
- **On 27**, when the visible section would hold no third-party bundle on that first collapse, Snaptic asks once:
  - **“Hide all other apps’ icons?”**
  - **“No icons are to the right of the arrow yet, so every other app’s icon will be hidden. ⌘-drag the icons you
    want to keep to the right of the arrow first.”**
  - [**Hide Icons**] [**Cancel**] (default **Cancel**).

### 4.1 The items

- **Order (LTR):** `[⋮] … [|] … [‹] [Snaptic items] [system items]`. Mirrored in RTL. On Native, `|` is
  zero-length and the arrow is the Hidden boundary.
- **Created in `start()`** with `behavior = []`, so they can't be ⌘-dragged out of the bar (P-9). `isVisible =
  true` on the arrow at every start, on `⋮` when Always Hidden is on, and on `|` on Length (Y-10).
- **First-run seeding:**
  - Before the first creation, `IconsItems` writes `NSStatusItem Preferred Position` for the arrow and `|` so they
    sit just left of the existing Snaptic items. Positions are distances from the right edge.
  - On Length, before any *other* Snaptic status item is first created while Hidden Icons runs, its position is
    seeded between the arrow and the system items (P-10).
  - S0's VM leg verifies both. If seeding doesn't work, README Known limitations says: **“On macOS 14–26, a Snaptic
    icon that first appears while icons are hidden can land in the hidden section. ⌘-drag it to the right of the
    arrow once.”** The own-items guard (§4.2.5) then still protects Awake.
- **Turning Always Hidden on** creates `⋮` at 20 pt, expands if needed, and shows the arrange hint once (Y-4).
  Turning it off removes `⋮` and its autosave position.
- **Losing the arrow (G-4).** `isVisible` can still turn false: 27's System Settings › Menu Bar, or a stale
  `Visible` key. When it does, the engine expands at once and stays expanded. The status row reads **“The arrow
  isn’t in the menu bar, so icons stay shown.”** with [**Show Arrow**], which sets `isVisible = true`. The same
  applies to `|` and `⋮` ([**Show Divider**]). These recovery paths work whatever the arrow's state:
  - the page's [**Show Icons**] / [**Hide Icons**] button;
  - the Snaptic-menu section;
  - the shortcut;
  - `snaptic icons show`;
  - opening Snaptic again, which shows Settings and, on the Hidden Icons page, expands.
- **Look (G-15 over Y-13):**
  - **Arrow:** SF Symbol `chevron.compact.left` collapsed and `chevron.compact.right` expanded, mirrored in RTL,
    template. A refused or failed collapse keeps the expanded glyph.
  - **Separators:** `|` is the title `|`; `⋮` is the title U+22EE `⋮` at normal alpha, so it differs from `|`
    without relying on alpha.
- **Direction (Y-6).** The menu bar's direction, not the app's (Snaptic is English-only). It is
  `Locale.Language(identifier: Locale.preferredLanguages.first).characterDirection == .rightToLeft`, computed before
  any item is created and on `NSLocale.currentLocaleDidChangeNotification`. Geometry isn't used, because on 14–26
  it would need Accessibility. M-check with Arabic as the primary language.

### 4.2 Engines

#### 4.2.1 Factory

| Condition | Engine |
|---|---|
| macOS 14–26, `Icons.disable.length` clear | **Length** |
| macOS ≥ 27, shim available and verified, `Icons.disable.native` clear, `Icons.native.disabledBuild ≠ current OS build`, identity check passes | **Native** |
| otherwise | **Unavailable**: items still show, nothing hides, the status row explains (§4.17) |

**Identity check (Y-5).** Native refuses when `PermissionFlow.isTranslocated`, or when
`NSWorkspace.urlForApplication(withBundleIdentifier: Bundle.main.bundleIdentifier)` ≠ `Bundle.main.bundleURL`. The
status row then reads **“Move Snaptic to Applications to hide icons.”** It is checked at start and before each
activation. (R2-7: the earlier 500 ms on-screen frame check is dropped. S0 showed that a restriction leaves the
in-process frame unchanged, and that a macOS-overflowed item legitimately sits off-screen.)

#### 4.2.2 Native engine

**Shim** `SNMenuBarVisibility` follows the `SNMonitorPanel` contract (P-7):

- API: `isAvailable`, `isPoisoned`, `rawEncodingForClass:selector:`, `markVerified:`,
  `activateWithSystemItems:bundles:token:completion:`, `invalidateToken:`, `invalidateAll`.
- `dlopen(RTLD_LAZY|RTLD_LOCAL)` and `NSClassFromString` happen only inside the `.m` (lint rule 11 unchanged).
- Any `@catch` poisons the shim for the life of the process. Allow-lists are `NSArray`.
- **Tokens are shim-owned.** A completion is delivered at most once, on the main queue. A completion for a token
  that is no longer current is dropped, and its assertion invalidated at once. Duplicates count
  `icons.dupCompletion`.
- An error-code enum, never `NSError` text, crosses into Swift (§4.15).
- Swift `PrivateMenuBarAPI` checks the encodings with `KitEncoding.Requirement` before `markVerified`. On 27.2:

  | Class | Selector | Encoding |
  |---|---|---|
  | `MBAssessmentModeConfiguration` | `initWithAllowedSystemItems:allowedBundleIdentifiers:` | `@32@0:8@16@24` |
  | `MBAssessmentModeConfiguration` | `initWithUnrestrictedMenuBarItems` | `@16@0:8` |
  | `MBAssessmentModeAssertion` | `init` | `@16@0:8` |
  | `MBAssessmentModeAssertion` | `activateWithConfiguration:completionHandler:` | `v32@0:8@16@?24` |
  | `MBAssessmentModeAssertion` | `invalidate` | `v16@0:8` |

  Any mismatch means unavailable. There is no compile flag: the CI SDK (macOS 15) builds the shim unchanged.

**Collapse:**

1. Gates: kill switch, identity, exam guard (§4.11), other-hider pause (§4.10), stable inventory (§4.5),
   Accessibility (§4.12).
2. Read the inventory (unrestricted bar), or use the cache while restricted.
3. Resolve the layout.
4. Allow:
   - system items: the full range S0 records, default `0..<64`;
   - every system owner's bundle that the inventory skips (§4.2.6) other than `com.apple.MenuBarAgent`, e.g.
     `com.apple.TextInputMenuAgent` (R2-1);
   - visible-section bundles;
   - `Bundle.main.bundleIdentifier`;
   - `newShown`;
   - Always Show choices.

   Remove Always Hide choices.
5. Activate token N+1, then invalidate N once N+1 completes. S0-4 showed the server unions every active assertion,
   so the overlap shows old ∪ new for one frame at most and never hides an item that should show (R2-2).

- **Activation timeout: 3 s** (X-3). On expiry the core bumps the generation, fails safe
  (`icons.activateTimeout`), and invalidates any late success. Two timeouts in a row make Native unavailable until
  relaunch.
- **Expand:**
  - A plain expand with Always Hidden on keeps a **restricted** assertion: system + visible + hidden + own +
    `newShown`, minus the AH bundles.
  - A plain expand with AH off, a ⌥ expand, fail-safe and `stop()` all invalidate, leaving the bar unrestricted.
  - After every expand that invalidates, the token is released, so the framework holds nothing it could re-acquire
    (X-5).
- **Layout refresh (Y-2 + X-8):**
  - The cache is replaced only by an unrestricted read. That happens at module start (before the first collapse),
    on every expand that invalidates, on a ⌥ expand, on fail-safe, and on Sections › **Show All Icons and Refresh**.
  - During a restricted plain expand, the on-screen items (visible + hidden) are re-read on each collapse and only
    those bundles are re-sectioned. AH bundles keep their cached section. Only frames of bundles in the assertion's
    allow-list are trusted: S0-10 showed that hidden third-party items stay in AX at stale frames (R2-5).
  - The cache stores `readAt`. When it is over 24 h old and AH is on, the status row adds **“Icon positions were
    last read 3 days ago. Option-click the arrow to refresh them.”**
  - Diagnostics show the layout age.
- **System-item runtime check (X-6, revised by R2-1).** After each collapse, the engine reads MenuBarAgent's extras
  (`/System/Library/CoreServices/MenuBarAgent.app`), keyed by the first child's `AXIdentifier`
  (`com.apple.menuextra.*`). Hidden MenuBarAgent items leave AX, so presence is a valid signal here. If an
  identifier that was present before the collapse is missing, and it isn't `com.apple.menuextra.now-playing` (the
  known casualty: hidden under any restriction), the engine expands, counts `icons.systemItemHidden`, and sets
  `Icons.native.disabledBuild` to the current OS build.

#### 4.2.3 Length engine

- `L = max(500, min(2 × widest screen width, 10 000))`, or 1728 with no screen. **10 000 is the macOS hard cap**, so
  X-18's 20 000 is rejected.
- Collapse sets `|` to L. Expand sets 20, or 0 with dividers off.
- State is derived from the live length (`length(of: .separator) > 20`).
- `verifyHideMechanismIfNeeded`: on the next run-loop tick after a collapse, the separator's window width must be ≥
  L − 1. Otherwise the engine expands and fails safe (`icons.failSafe.lengthRejected`).
- **Screen-change re-apply** goes to whichever items are inflated. It is coalesced to 250 ms after the last
  `didChangeScreenParameters`, skipped while a Displays resolution trial is pending, and run once when the trial
  ends (X-18).

#### 4.2.4 Always Hidden lengths (P-1 = Y-1)

`L` as above. "dividers" = the Section dividers setting.

| State | Length: `\|` | Length: `⋮` (AH on) | Native: `\|` | Native: `⋮` (AH on) | Native assertion |
|---|---|---|---|---|---|
| Collapsed | L | 0 (Hidden's L already covers it) | 0 | 0 | system + visible + own + newShown |
| Expanded, plain | 20, or 0 if dividers off | **L** (AH stays off-screen) | 0 | 20, or 0 if dividers off | restricted: + hidden, minus AH |
| Expanded, ⌥ | 20, or 0 if dividers off | 20, or 0 if dividers off | 0 | 20, or 0 if dividers off | none (invalidated) |
| AH off | as above | removed | 0 | removed | as above, without the AH split |

- Writes **widen before they narrow**, so nothing flashes:
  - collapse → plain: `⋮`=L, then `|`=20;
  - plain → ⌥: `⋮`=20;
  - any → collapse: `|`=L, then `⋮`=0.
- On Native, `|` is length 0, not `isVisible = false`, so macOS keeps its position across an OS downgrade.
- K3 has the full truth table (state × AH × dividers × engine → lengths and write order).

#### 4.2.5 Guards (P-9, Y-4, G-3 = X-11)

- **`arrangementValid`.** Length: `|` is on the hidden side of the arrow. Native: always true. When false:
  - collapse is refused and the arrow keeps the expanded glyph;
  - the status row says **“Drag the | divider to the left of the arrow (hold ⌘).”**;
  - the CLI exits 2 with that text;
  - auto-collapse re-arms, so it retries.

  It is re-checked before every inflate, including screen re-apply.
- **`alwaysHiddenPlaced`.** `⋮` is on the hidden side of `|` (Length) or of the arrow (Native). Off-screen frames
  count as not placed. When false, AH acts as part of Hidden, and the row says **“Drag the ⋮ divider to the left of
  the | divider (hold ⌘).”** (on Native: "…to the left of the arrow…").
- **`IconsPolicy.ownItemsGuard` (Length).** It runs before every collapse and whenever a Snaptic status item
  appears, comparing in-process window frames. No Accessibility is needed.
  - **Arrow left of `|`:** collapse is refused. Row: **“The arrow is in the hidden area. ⌘-drag it to the right of
    the | divider.”**
  - **A Snaptic or Awake item left of `|` while Awake keeps the Mac awake or lid-closed mode is on:** collapse is
    refused, and the bar expands at once if collapsed, until the session ends. Row: **“Awake’s icon is in the hidden
    area, so icons stay shown while your Mac is kept awake. ⌘-drag it to the right of the arrow.”** This keeps the
    README guarantee "A running Awake session is never invisible".
  - **Any other Snaptic item left of `|`:** warning row **“Some Snaptic icons are in the hidden area. ⌘-drag them to
    the right of the arrow.”**
  - **A Snaptic item appearing for the first time while collapsed:** the bar expands, so the item gets a position.
  - Native needs no own-items guard (the own bundle is allowed). The identity check (§4.2.1) covers a wrong bundle.
- **Advanced › Reset Arrow Position…** confirms with **“Put the arrow back next to the Snaptic icon?”** /
  **“The arrow and dividers move back next to the Snaptic icon, and your icons are shown. You’ll arrange your icons
  again.”** / [**Reset Position**] [**Cancel**]. It then:
  1. expands;
  2. removes the items;
  3. clears the position and visibility keys;
  4. re-seeds;
  5. recreates the items;
  6. sets `arranged = false`.

#### 4.2.6 Inventory (X-9, P-18, X-22)

- AX on a background queue.
  - **Budgets:** 0.15 s per AX call, 0.5 s per app, 1.2 s total, 50 extras per app.
  - **Per-app result:** `.ok`, `.timedOut`, `.noExtras` or `.denied`.
  - An app with no `.ok` result **is never hidden by that read**: it keeps its last known section, or counts as
    visible.
- **An inventory that is empty, failed, or has no third-party items while the last good read had some never
  produces a collapse.** The engine expands and keeps the last good layout.
- **Coordinates.** The resolver compares x only. The app normalizes both inputs to the screen holding the arrow's
  window, and drops extras outside that screen's `minX…maxX`.
- **Skips.** Own pid, plus system owners whose `bundleURL` is under `/System/`. Own means `bundleURL ==
  Bundle.main.bundleURL`. A spoofed id is treated as a normal app.
- **When it runs.** Only while the module runs and the engine needs it: Native always; Length only for the hidden
  list, Sections or a new-icon toast. `Icons.disable.inventory` turns it off. On 27, Native is then unavailable.

### 4.3 Clicks and the arrow's menu (Y-8, Y-9, P-20)

| Input | Collapsed | Expanded (plain) | Expanded (⌥) |
|---|---|---|---|
| Left click, VoiceOver press (nil event), shortcut, CLI `toggle` | Expand (plain) | Collapse | Collapse |
| ⌥ + any button, CLI `show --all`, menu **Show All Hidden Icons** | Expand (⌥) | Expand (⌥) | Collapse (click) / no-op (`show --all`) |
| Right-click, ⌃-click, other mouse button | Menu | Menu | Menu |

- The ⌥ state isn't persisted; launch always starts plain. Hidden Bar's persisted mode is unnecessary because AH
  works on plain expand. This goes in the Switching table.
- Wiring: `sendAction(on: [.leftMouseUp, .rightMouseUp])`, and the menu opens with
  `menu.popUp(positioning:at:in:)` at the button's bottom edge. **Never call `performClick` from the button's own
  action** (Hidden Bar's recursion crash).
- On Length with dividers shown, clicking `|` opens the same menu. On 27, right-click may not arrive. Nothing
  depends on it.
- **The arrow's menu**, built fresh on each open:
  1. **Show Hidden Icons** / **Hide Icons Again**;
  2. **Show All Hidden Icons** (the ⌥ alternate; a plain item while VoiceOver, Switch Control or Full Keyboard
     Access is on);
  3. the hidden list (§4.8);
  4. a separator;
  5. **Hide Icons Automatically** (checkmark);
  6. **Hidden Icons Settings…**.

  There's no Quit, because the Snaptic menu and Settings have it. It is built only through MenuKit.

### 4.4 Intents (X-14, Y-14)

- One Kit `IconsIntentQueue` serializes every source: click, shortcut, CLI, menu, hidden-list press, hover, timer,
  launch, settings change, monitors (wake, agent restart, hider, exam).
- `toggle` is resolved against the **target** state after queued intents, not the current one.
- `stop` and fail-safe preempt everything.
- **Debounce 0.3 s** on click and shortcut only. The CLI and the list aren't debounced, because the queue already
  resolves their toggles.
- **Suppression windows:**
  - hover is ignored for 1 s after a click-collapse and for 1 s after a Space change;
  - the timer is ignored for 60 s after a hidden-list press;
  - launch collapse is cancelled by any user intent.
- Collapse requests during `.calibrating` **join** the in-flight request and get its result. Every CLI verb replies
  after queueing, within 1 s. `status` reads the current state directly.
- Race-matrix test (K3): every pair of intents × every engine state.

### 4.5 New icons (G-8 + Y-3 + X-10)

- **"New" means not in `knownBundles`.** Every unrestricted read updates `knownBundles`. Detection is diff-based. A
  launch of a known bundle re-applies its last section and is never "new" (no login-item burst).
- **Watch.** `didLaunchApplication` while any assertion is active (Native) or while collapsed (Length). Re-reads at
  +2, +10 and +30 s, because macOS adds extras late. A bundle is dropped from `knownBundles` only after 3
  unrestricted reads in a row that don't see it.
- **Stable-inventory gate**, for the first collapse after start: two matching reads 2 s apart, system uptime > 60 s,
  capped at 30 s. If the gate doesn't pass by then, launch collapse is skipped this time.
- **Native, Advanced pop-up “New apps’ icons”: Show (default) / Hide.**
  - **Show:** a new bundle joins `newShown` and stays shown until the next unrestricted read records its section,
    the user picks it in Sections, or 30 days pass unseen. G-8's movement rule is dropped: positions aren't
    observable while restricted.
  - **Hide:** Hidden Bar's behaviour. The icon is hidden and listed in the hidden list.
  - Help: **“Show keeps a new app’s icon visible until you next show all icons or choose where it goes.”** Dimmed
    without Device Control and Data Access.
- **Length** (the row is absent; icons can't be moved). Once per app per day, and only when an Accessibility
  inventory exists, a toast: **“A new icon may be hidden. ⌘-drag it to the right of the arrow to keep it shown.”**
  [**Show Icons**]. The app name is shown only in the hidden list's "New" line, never logged.

### 4.6 Auto-collapse, launch collapse, hover

- **Auto-collapse:** default on, 10 s, range **5–300 s** (a value field with a stepper; sanitize clamps). Timers use
  `.common` modes.
- **The timer re-arms while** (Y-11, X-13, P-8, G-15):
  - the pointer is in the menu-bar band of any screen. The band is `frame.maxY − NSStatusBar.system.thickness …
    frame.maxY`, so an auto-hidden bar still counts. It doesn't count in full screen.
  - any Snaptic window is visible: Settings, onboarding, confirm and pre-confirm panels, save and open panels,
    Sparkle, custom session, PIP editor;
  - a menu is open: a window at layer `kCGPopUpMenuWindowLevel` (101), or a `SystemUIServer`/`ControlCenter` window
    at layer 25, touching the band (CGWindowList bounds only; no Screen Recording);
  - a popover or panel at layer ≥ 25, or a floating window owned by a pid that owns an extra, lies within 40 pt of
    the band;
  - it is within 60 s of a hidden-list press;
  - the VoiceOver cursor is on a menu bar extra (read only while VO runs);
  - the Snaptic menu or the arrow's menu is open.
- **Limits.** The window-based reasons (menu, popover, panel) stop after 120 s in a row. Changing any Hidden Icons
  setting restarts the timer. A refused or failed collapse re-arms it.
- **Launch collapse (“Hide icons when Snaptic opens”, default on).** Once per process start, never on reopen
  (`applicationShouldHandleReopen`). It needs `arranged` and the stable-inventory gate. It is skipped on the first
  launch after a Snaptic version change or an OS build change, and after an unstable launch (crash guard or Safe
  Mode marker, §4.11).
- **Hover (“Show icons on hover”, Advanced, default off).**
  - A global `.mouseMoved` monitor exists only while the setting is on and the bar is collapsed.
  - The handler returns at once, with no allocation, unless the pointer is in the band of the screen under it.
  - Dwell 0.5 s. `Icons.disable.hover` turns it off.
  - A hover expand never uses the full menu bar (H9).

### 4.7 Use the full menu bar while icons are shown (G-9, X-12, P-8, P-24)

- Advanced toggle, default off. Label **“Use the full menu bar while icons are shown”**.
  - Help: **“Snaptic becomes the active app while icons are shown, so the current app loses focus.”**
  - Footnote: **“Snaptic also appears in the Dock and the app switcher until the icons are hidden.”**
- Expanding by click, shortcut, menu or CLI takes an H9 reason. Collapsing releases it. A failed collapse keeps it
  (Hidden Bar's `didFailToCollapseMenuBar`).
- The app menu shown is Snaptic's main menu. It must not show empty Edit or Window menus (A4 checks).

### 4.8 The hidden list and the Snaptic-menu section (Y-7 + G-15 + G-17 + X-17 + X-19)

```
┌──────────────────────────────────────────┐
│ [Switcher | Displays | Awake | Icons]    │   (tabs only with ≥ 2 shared modules)
│ Show Hidden Icons                        │   (Hide Icons Again while shown)
│ Show All Hidden Icons            (⌥ alt) │
│ ──────────────                           │
│ HIDDEN (3)                               │
│ [■] Docker                               │
│ [■] iStat Menus — CPU                    │
│ [■] iStat Menus — Memory                 │
│ BEHIND THE NOTCH (1)                     │
│ [■] Dropbox                              │
│ Shown Icons                           ›  │   (submenu, same row format)
│ ──────────────                           │
│ Hidden Icons Settings…                   │
└──────────────────────────────────────────┘
```

- **One row per extra.** The title is the app name, or **“App — Title”** when an app has several extras (the AX
  title, falling back to "Icon n").
  - Each row shows the app's icon at 16 pt, through a DS exception (G-21; a generic app icon when none).
  - Rows are ordered nearest the boundary first. Zero-size extras are dropped.
  - The section headers carry the meaning, so it doesn't rely on colour.
  - VO: the label is the title, the image is decorative, and the hint is **“Opens its menu.”**
- **Behind the Notch** appears only for a notched screen that shows a menu bar. It is computed per screen, from the
  `NSScreen` holding the extra's midX, using that screen's `auxiliaryTopRightArea` (fallback 972). It covers the
  display the pointer was last on, or the main display.
- **macOS 27 overflow.** Listed under Behind the Notch only if AX reports such items with off-bar frames (S0
  records which). Otherwise Known limitations says so.
- **Empty and permission states:**
  - **No Hidden Icons** (disabled).
  - 14–26 without Accessibility: **Allow Accessibility to List Icons…**, which opens Permissions. The menu never
    prompts.
  - 27 without it: **Needs Permission** (disabled).
  - Paused or unavailable: the reason, disabled.
- **Choosing a row:**
  1. Expand first, plain or ⌥ as needed.
  2. Off the main thread: wait ≤ 300 ms, polling every 30 ms, for the extra's AX frame to be on screen.
  3. Re-resolve the target by pid, bundle and `launchDate`, matching by index and frame within 4 pt.
  4. AXPress.
  5. Hop to main and suppress auto-collapse for 60 s.

  On mismatch the row does nothing, and the next open re-reads. A press that opens no window within 500 ms counts
  `icons.pressNoop`. `Icons.disable.axpress` turns presses off (rows still show, disabled).
- The list is read lazily when the menu opens, from the cache plus a background refresh. It's identical in the
  Snaptic-menu section and the arrow's menu.

### 4.9 Settings › Hidden Icons (G-19, G-6, G-7, G-16)

Sidebar: **Hidden Icons**, `eye.slash.fill`, `.teal`, after Awake and before Permissions. README "eight pages".

**Off state:** the header with the switch **Use Hidden Icons**, the summary, and three highlights: **“Hide the
icons you don’t need”**, **“Keep some icons hidden even when shown”**, **“Open hidden icons from the Snaptic
menu”**.

**On state, main page (8 controls):**

```
[eye.slash] Hidden Icons                          [Use Hidden Icons ●]
Keep your menu bar tidy: click the arrow to hide the icons to its left, and click again to show them.
┌───────────────────────────────────────────────────────────────┐
│ Hiding 7 icons                                  [Show Icons]  │
│ Hide icons automatically after [ 10 ] seconds            [●]  │
│ Hide icons when Snaptic opens                            [●]  │
│ Always Hidden section                                    [ ]  │
│ Section dividers                                         [●]  │
│ Show or hide icons                      [ Record Shortcut ]   │
│ Sections                              7 hidden · 2 choices ›  │
│ How to Arrange…                                               │
└───────────────────────────────────────────────────────────────┘
[Restore Defaults…]                               [Advanced…] (?)
```

- The status row carries the engine state (§4.17) and, after a fail-safe, the reason line (X-25). Its button is
  [**Show Icons**] / [**Hide Icons**], or the state's own action: [**Open Privacy Settings**], [**Relaunch
  Snaptic**], [**Show Arrow**], [**Try Again**] (clears `disabledBuild`).
- **Section dividers** is hidden on 27 while Always Hidden is off. On 27 its help is the 27 variant (G-27).
- **Sections ›** value: "7 hidden", plus "· 2 choices" when per-app choices exist (X-21: planted choices are
  visible).
- **How to Arrange…** opens the sheet. The text and diagram are per engine (§4.17).

**Sections sub-page** (`NavigationRow`, like Awake's Drives ›):

| | macOS 14–26 (Length) | macOS 27 (Native) |
|---|---|---|
| Without Accessibility | “Allow Accessibility to see which icons are in each section. Hiding works without it.” [**Open Privacy Settings**] | “Hidden Icons needs Device Control and Data Access to see where your icons are.” [**Open Privacy Settings**] |
| Expanded | Live list; updates within 2 s of launch, quit and drags | Live list |
| Collapsed | Live list (hidden items are off-screen, still readable) | The cached list. Footer **“As of the last time your icons were shown.”** |
| Per row | Read-only. Footer **“⌘-drag icons in the menu bar to move them between sections.”** | Pop-up **Where It Is** / **Always Show** / **Always Hide** |
| Refresh | **Refresh** | **Refresh** while unrestricted. Otherwise **Show All Icons and Refresh**, which expands with ⌥, reads, and leaves the icons shown (auto-collapse re-arms) |

- Headers: **Shown**, **Hidden**, **Always Hidden**. An empty section reads **No icons**. A new app has a secondary
  line **New**.
- Footer on both: **“Icons that macOS hides in System Settings › Menu Bar aren’t listed.”**
- **Per-app choices (27, G-7):**
  - A choice beats position, and applies to all of an app's icons.
  - **Always Hide** hides the app whenever Hidden is hidden. It never puts the app in Always Hidden; only a ⌘-drag
    does that.
  - An app with a choice lists under the section the choice puts it in.
  - Help: **“Always Show and Always Hide apply to all of an app’s icons and win over where you drag them.”**
  - Choices are stored in `SnapticIconsAppsV1` and never exported. On 14–26 they're kept but unused.
  - The CLI never edits them (X-21).
  - System items and privacy indicators can't take a choice.

**Advanced… sheet:**

- **Show icons on hover**, with help **“Shows hidden icons when the pointer rests on the menu bar.”**
- **New apps’ icons** (27 only).
- **When another menu bar app hides icons**: **Pause Hidden Icons** / **Run Both Anyway** (§4.10).
- **Use the full menu bar while icons are shown** (§4.7).
- **Reset Arrow Position…** (§4.2.5).
- **Diagnostics:** engine, shim, layout age, last fail-safe, and the kill-switch `DefaultsLockRow`s (read-only).
- The sheet's own Restore Defaults resets only its rows.

**Page Restore Defaults…:**

- **“Restore Hidden Icons settings to their defaults?”**
- **“Automatic hiding, Always Hidden, dividers, the shortcut, hover, new apps’ icons, the full menu bar, and every
  app’s Always Show or Always Hide choice go back to their defaults. Where your icons are in the menu bar stays as
  it is.”**
- [**Restore Defaults**] [**Cancel**]

It clears `choices` and `newShown`, and keeps `arranged`.

**Reset All Settings** confirmation adds: **“Hidden Icons’ arrow and dividers go back next to the Snaptic icon, so
you’ll arrange your icons again.”**

### 4.10 Other menu bar hiders (G-14 + P-15 + X-4)

- Kit `KnownMenuBarHiders`. The draft ids, all verified in S0:
  - `com.dwarvesv.minimalbar` (Hidden Bar);
  - `com.surteesstudios.Bartender`;
  - `com.jordanbaird.Ice`;
  - Thaw.
- A second watcher in `OtherAppsMonitor`, running only while Hidden Icons runs, matches the bundle id plus its
  code-signing team.
- **Pause Hidden Icons** (default). While a listed app runs, the module expands and pauses. A click opens the page.
  Status row **“Paused while Hidden Bar runs”**, menu row **Paused While Hidden Bar Runs** (the existing
  `pauseReason` pattern). It resumes when the app quits.
- **Run Both Anyway.** Offered on every OS. S0-4(3) showed that MenuBarClientCore unions the allow-lists, so on 27
  an icon hides only when both apps hide it. The option's footnote says so: **“On macOS 27, an icon stays shown
  unless both apps hide it.”** (R2-2)
- README **“Switching from Hidden Bar”**, after the Hidden Icons section:
  - Quit Hidden Bar and remove it from Login Items.
  - Positions don't carry over, so ⌘-drag the arrow once.
  - The mapping table:

| Hidden Bar | Snaptic Hidden Icons |
|---|---|
| Start Hidden Bar when I log in | General › Open at login |
| Show preferences on launch | Opening Snaptic again always shows Settings |
| Automatically hide icon after | Hide icons automatically after … seconds |
| Enable always hidden section | Always Hidden section |
| Use the full MenuBar on expanding | Advanced… › Use the full menu bar while icons are shown |
| Global Shortcut | Show or Hide Hidden Icons (Settings › Hidden Icons) |
| ⌥-click to hide the separators | Section dividers (⌥-click now shows Always Hidden) |
| Right-click ‹ for Notch Overflow | The Snaptic menu's Hidden Icons section, or right-click the arrow |
| `defaults write … hoverToExpand` | Advanced… › Show icons on hover |

### 4.11 Safety

- **Hang watchdog (X-1).** `IconsWatchdog` is a dedicated `Thread`. A main-queue timer stamps a heartbeat every
  500 ms. If `mainAgeMillis` > 3000 while a restriction is held, the watchdog calls the shim's `invalidateAll` off
  main and counts `icons.hangExpand`. `EmergencyActions` gains an entry for the same.
  - **S0 verifies that off-main `invalidate` is safe.** If it isn't, the fallback is a tiny helper process that
    holds the assertion and dies with a pipe EOF.
  - Length can't change a length off main (`NSStatusItem` is main-only). README: **“If Snaptic stops responding
    while icons are hidden on macOS 14–26, force quit it (⌥⌘⎋). The icons come back as soon as it quits.”**
- **Crash guard (X-2).**
  - Before each activation, write `Icons.native.inFlight = <OS build>`; clear it on completion or timeout.
  - At start, a leftover `inFlight` means the last activation crashed. Set `Icons.native.disabledBuild = <OS
    build>`, so Native is unavailable on that build, with status row **“Hidden Icons stopped using the macOS 27
    method after a problem, so your icons stay shown.”** [**Try Again**].
  - Safe Mode skips the module (H6). Launch collapse is skipped after a version change, an OS change, or an
    unstable launch.
- **MenuBarAgent restart (X-5).** Watch `com.apple.MenuBarAgent` launch and terminate, with the path under
  `/System/Library/CoreServices/`. S0-6 showed that a held restriction survives the restart. The engine still
  invalidates on terminate, so it never holds an assertion it can't re-read for, and AX may switch displays (R2-3).
  - On terminate: invalidate and release every token, `.expanded(reason: agentRestart)`, `icons.agentRestart`.
  - On launch +2 s: re-collapse only if the last intent was "hidden".
  - S0 runs `killall MenuBarAgent` while collapsed and while expanded.
- **Session (X-20).** On `sessionDidResignActive`, `sessionDidBecomeActive`, `didWake` and screen lock/unlock: the
  engine invalidates, re-reads after 2 s, and re-collapses if the intent is hidden. The manual checks cover lock,
  FUS, sleep, display connect/disconnect, and a full-screen reveal.
- **Privacy indicators (X-6). Hard rule: Hidden Icons never hides a privacy indicator.** S0 gate:
  - camera (FaceTime), mic (Voice Memos), screen recording, location;
  - each with its owning app in Hidden, while collapsed.

  If any disappears, the design changes before A2. Native then always allows every app holding an active capture
  session (public `AVCaptureDevice` in-use queries where available), or limits Native accordingly. The README states
  the result.
- **Exam sessions (X-7, revised by R2-4).** `assessmentagent` runs with no exam open, so it isn't the signal. The
  guard treats the system as in an exam while `NSApp.currentSystemPresentationOptions` contains
  `.disableProcessSwitching`, `.disableForceQuit` or `.disableSessionTermination`, set by a process other than
  Snaptic (we never set them). It is checked before every activation and on
  `NSApplication.didChangeScreenParametersNotification` + a 1 s poll while Native holds an assertion. While it
  holds, Native invalidates, makes no activation calls, and shows **“Paused during an exam session”**. Because
  allow-lists union (S0-4), any assertion of ours during an exam would show icons the exam hid, so this guard is
  mandatory. S0-9 confirms the signal against a real exam before A3. The S0 side-effect checklist (§5) decides any Known limitations.
- **Kill switches:** H3.

### 4.12 Accessibility on macOS 27 (G-5)

| State | Arrow click | Status row | Snaptic menu | `icons status` |
|---|---|---|---|---|
| Granted, inventory read | Toggles | “Hiding 7 icons” / “Showing all icons” | Show/Hide + list | `state=collapsed …` |
| Not granted | Opens Settings › Hidden Icons; nothing hides | “Hidden Icons needs Device Control and Data Access to see where your icons are.” [**Open Privacy Settings**] | **Needs Permission** + **Hidden Icons Settings…** | `state=needsPermission` |
| Granted, not effective (`AXIsProcessTrusted()` false for 5 s after the pane closes) | as Not granted | “macOS may need Snaptic to reopen before the permission takes effect.” [**Relaunch Snaptic**] | as Not granted | `state=needsPermission` |
| Revoked while collapsed (a read fails, or 2 reads with no third-party items after a good one) | Expands, then as Not granted | as Not granted | as Not granted | `state=needsPermission` |

The tab's attention mark shows for needs-permission, unavailable and paused. On 14–26, permission affects only the
list and Sections (§4.8, §4.9).

### 4.13 Keyboard and VoiceOver (G-15)

- **Arrow:** accessibility label **“Hidden Icons”**, value **“Hiding 7 icons”** / **“Showing all icons”**, help
  (tooltip and VO hint) **“Click to show or hide icons. Option-click to include Always Hidden.”**
- **Separators:** `|` is **“Hidden Icons divider”** and `⋮` is **“Always Hidden divider”**. Both have help **“Hold
  Command and drag icons across this divider to hide or show them.”**
- **The keyboard path to Always Hidden:** **Show All Hidden Icons** (the ⌥ alternate, or a plain item under
  VO/Switch Control/FKA), and `snaptic icons show --all`.
- **Tab:** short title **Icons**, accessibility label **Hidden Icons**, tooltip **“Hidden Icons (⌘n)”** by position.
  The accessible-tab item is **Show Hidden Icons Tab**.

### 4.14 Shortcut and CLI (P-17, G-29, X-21)

- **Shortcut:** **Show or Hide Hidden Icons**, unset by default. It goes through `GlobalHotkeys` and its existing
  conflict rules, and toggles (§4.3).
- **CLI**, Kit `IconsCommandGrammar`:

  ```
  snaptic icons show [--all]      Show hidden icons (--all includes Always Hidden)
  snaptic icons hide              Hide icons again
  snaptic icons toggle [--all]    Show or hide icons
  snaptic icons status [--json]   Engine, state and icon counts (never names)
  ```

  - **Policies:** `status` is `.read`; the others are `.low`. `offOnly: false`, `cliAllowed: true`.
  - **Off module:** the verb isn't registered, so it answers the existing "Unknown command. Run “snaptic help” for
    the list." (G-29's gated message is rejected; that's the house behaviour for every module).
  - **`status`:** `engine=native|length|unavailable state=collapsed|expanded|needsPermission|paused|unavailable
    hidden=<n> alwaysHidden=<n> shown=<n>`.
  - **`--json`:** `{engine, state, hidden, alwaysHidden, shown, layoutAgeSeconds}`.
  - **Exit 2** with one line:
    - paused: **“Hidden Icons is paused while another menu bar app hides icons.”**
    - needs permission (27): **“Hidden Icons needs Device Control and Data Access. Open Snaptic Settings ›
      Permissions.”**
    - unavailable: **“Hidden Icons isn’t available on this version of macOS.”**
    - invalid arrangement: the §4.2.5 text.
  - `--all` is valid only with `show` and `toggle`; otherwise usage, exit 64.
  - The CLI never edits choices or sections. README's "never from the command line" list gains "Hidden Icons’
    per-app choices".
  - **No bundle blocklist** (recorded decision, X-21). Any process running as the user can already hide items
    through the same service, so the CLI adds no new ability.

### 4.15 Privacy (X-16)

- Bundle ids exist only in `SnapticIconsAppsV1` and in memory. App names exist only in UI.
- No `NSLog`/`os_log`/`print` under `Icons/` carries a bundle id, name, AX title or `NSError` text. The shim
  returns error codes. Lint enforces this (H11).
- EventLog: counts and reason codes only. Diagnostics: counts, engine and shim state.
- README "On disk" gains: **“Hidden Icons’ per-app choices, known apps, and new-icon list (app bundle identifiers,
  never names), stored apart from your other settings and never exported.”**

### 4.16 Upgrading and onboarding (G-12, G-13)

- **New card** (upgraders with Hidden Icons off; never during first-run onboarding):
  - title **New: Hidden Icons**;
  - body **“Hide the menu bar icons you don’t need behind an arrow, and open them from the Snaptic menu.”**;
  - [**Turn On Hidden Icons**] [**Not Now**].

  Turn On opens the page with the How to Arrange sheet.
- **Onboarding:**
  - Welcome: **“A window switcher, display controls, Keep Awake, and hidden menu bar icons, in your menu bar. Turn on
    only what you want; everything else stays off.”**
  - Step **Arrange your icons**: the per-engine diagram, then **“Nothing hides until you click the arrow for the
    first time.”** [**Continue**].
  - Extra Done line: **“Click the arrow ‹ to hide icons once they’re arranged.”**
- **Downgrade to 0.3.4:**
  - `ModulesConfig.modules` is a `LossyMap`, which keeps unknown keys, so `hiddenIcons` prefs survive.
  - `newModuleCards` is lossy, so 0.3.4 drops the card.
  - `snapticMenuTab = hiddenIcons` falls back to the first tab.
  - The `Icons.*` keys and both stores are ignored.

  K1 adds a decode test of a 0.4 config with the 0.3.4 types. README: **“Going back to 0.3.4: your other settings
  stay, and Hidden Icons’ settings are kept for when you return. Quit 0.4 first so your icons are shown.”**
- **`prevent-sleep` is removed in 0.4**, as README l.466 promised.
  - The `KitControl.swift:359` retired-verb entry goes, so the verb is unknown.
  - `ConfigManagement.preventSleep` and AwakeMigration stay, because migration still needs them.
  - README Upgrading: **“0.3.4 → 0.4.0. Snaptic updates itself, and no setting is lost. Hidden Icons starts off.
    `snaptic prevent-sleep` is gone (it has answered ‘Moved to Awake’ since 0.3).”**
  - README top: **“Upgrading from 0.3.x: Snaptic updates itself and nothing changes until you turn on Hidden Icons
    (a “New: Hidden Icons” card in General). The app has a new icon.”**
- **Release notes** mention the new app icon.

### 4.17 Canonical strings (G-10, G-11, G-27, G-28)

Strings not listed here are in the section that uses them. Every string passes lint03's sentence and title-case
checks.

| Where | String |
|---|---|
| Module title, sidebar, Permissions row | **Hidden Icons** |
| Short title (tabs) | **Icons** |
| Page switch | **Use Hidden Icons** |
| ModuleSwitchRow summary (General, onboarding) | **“Hide the menu bar icons you don’t need behind an arrow.”** |
| Page summary | **“Keep your menu bar tidy: click the arrow to hide the icons to its left, and click again to show them.”** |
| Permissions needed-for (27) | **“Hidden Icons uses it to see where your menu bar icons are, so it can hide the right ones.”** |
| Permissions needed-for (14–26, on demand) | **“Hidden Icons uses it to list your hidden icons. Hiding works without it.”** |
| Status: collapsed | **“Hiding 7 icons”** / **“Hiding 1 icon”**; 14–26 without Accessibility: **“Icons are hidden”** |
| Status: expanded | **“Showing all icons”** |
| Status: first run | **“Arrange your icons, then click the arrow to hide them.”** [**How to Arrange…**] |
| Status: unavailable (OS, shim, encodings) | **“Hidden Icons isn’t available on this version of macOS. Your icons stay shown.”** |
| Status: turned off by a kill switch | **“Hidden Icons is turned off on this Mac, so your icons stay shown.”** |
| Status: needs permission (27) | §4.12 |
| Status: identity | **“Move Snaptic to Applications to hide icons.”** |
| Status: crash guard | **“Hidden Icons stopped using the macOS 27 method after a problem, so your icons stay shown.”** [**Try Again**] |
| Status: paused (hider) | **“Paused while Hidden Bar runs”** (the app's name from `KnownMenuBarHiders`, a fixed table, not the running app) |
| Status: paused (exam) | **“Paused during an exam session”** |
| Status: arrow missing | §4.1 |
| Status: arrangement | §4.2.5 |
| Status: fail-safe reason line (X-25) | **“Icons were shown at 9:41 because Snaptic couldn’t confirm they were hidden safely.”** Cleared by the next successful collapse |
| Status: stale layout | §4.2.2 |
| Fail-safe toast (once per launch) | **“Snaptic couldn’t hide icons, so they’re shown. Details are in Hidden Icons settings.”** [**Open Settings**] |
| Status buttons | **Show Icons** / **Hide Icons** |
| Auto-collapse | **“Hide icons automatically after [10] seconds”** (5–300) |
| Launch | **“Hide icons when Snaptic opens”**; help **“Reopening Snaptic to show Settings doesn’t hide them.”** |
| Always Hidden | **“Always Hidden section”**; help **“Icons left of the ⋮ divider stay hidden until you Option-click the arrow.”** |
| Dividers (14–26) | **“Section dividers”**; help **“Shows the | and ⋮ dividers while icons are shown.”** |
| Dividers (27) | help **“Shows the ⋮ divider while icons are shown. On this version of macOS the arrow marks the edge of the hidden icons.”** Hidden while Always Hidden is off |
| Shortcut row | **“Show or hide icons”** (shortcut name **Show or Hide Hidden Icons**) |
| Sections row | **Sections** ›, value **“7 hidden”**, **“7 hidden · 2 choices”** |
| Menu items | **Show Hidden Icons** / **Hide Icons Again** / **Show All Hidden Icons** / **Hide Icons Automatically** / **Hidden Icons Settings…** |
| Snaptic menu, empty list | **No Hidden Icons** (disabled) |
| Snaptic menu, no permission | **Allow Accessibility to List Icons…** (14–26) / **Needs Permission** (27) |

**Menu Bar page (G-11, adapted to the pop-up):**

```
Where each module appears
  Window Switcher                         Always Show in Menu Bar ▾
  Displays                                Show When Active ▾
  Awake                                   Show When Active ▾
  Hidden Icons                            Arrow and Snaptic Menu ▾    (Arrow Only)
```

- Pop-up help: **“The arrow is always in the menu bar. Arrow and Snaptic Menu also lists hidden icons in the
  Snaptic menu, so you can open one without showing them all.”** Dimmed with **“Off”** while the module is off.
- Summary: **“Choose where each module appears in the menu bar.”**
- Footer: **“The Snaptic icon appears when a module is set to Show in Snaptic Menu, or Hidden Icons to Arrow and
  Snaptic Menu. With two or more, the Snaptic menu shows a tab for each; while it’s open, press ⌘1, ⌘2, and so on
  to switch tabs.”**
- Restore message: **“Where each module appears, their icons, and the Displays menu go back to their defaults.
  Your other Snaptic settings stay as they are.”** (Hidden Icons' presence is one of the "where each module
  appears" values.)
- 27 footer: **“macOS can also hide icons, including the Hidden Icons arrow, in System Settings › Menu Bar.
  Opening Snaptic again always shows Settings.”**
- README l.45–64 updated to match; l.56 becomes “⌘1–⌘4 choose a tab (one key per tab, by position)”.

**How to Arrange sheet** (also the onboarding step and the README):

```
┌ How to Arrange Your Icons ─────────────────────────────┐   macOS 14–26
│   ⋮  [A] [B]  |  [C] [D]  ‹  [E] [S]  ◷ 9:41           │
│   └always┘   └─hidden─┘     └shown─┘                    │
│ Hold ⌘ and drag icons in the menu bar:                 │
│ • To the right of the arrow ‹: always shown.           │
│ • Between | and ‹: hidden when you click the arrow.    │
│ • Left of ⋮: hidden until you Option-click the arrow.  │
│ New apps’ icons appear at the far left, so they start  │
│ hidden.                                                │
│                                            [Done]      │
└────────────────────────────────────────────────────────┘

┌ How to Arrange Your Icons ─────────────────────────────┐   macOS 27
│   ⋮  [A] [B]  [C] [D]  ‹  [E] [S]  ◷ 9:41              │
│   └always┘   └hidden─┘     └shown─┘                     │
│ Hold ⌘ and drag icons in the menu bar:                 │
│ • To the right of the arrow ‹: always shown.           │
│ • To the left of the arrow ‹: hidden when you click it.│
│ • Left of ⋮: hidden until you Option-click the arrow.  │
│ You can also choose Always Show or Always Hide for an  │
│ app in Settings › Hidden Icons › Sections.             │
│                                            [Done]      │
└────────────────────────────────────────────────────────┘
```

Lines about ⋮ appear only while Always Hidden is on. The diagram is a static drawing (`Image` built from SF
Symbols), not a screenshot.

---

## 5. S0: the gate before any app code (macOS 27.2 host + a macOS 15 VM)

S0 is a throwaway harness under `/tmp/s0-icons/` (never committed), plus `docs/design/0.4/STEP0-NOTES.md`
(committed), recording each result with the OS build. **Any failed Blocker row changes the plan before A2 starts**;
the change is recorded in STEP0-NOTES and in a §R2 note at the end of this file.

| # | Check | Pass | Blocker |
|---|---|---|---|
| S0-1 | The five encodings (§4.2.2) on 27.2 | Match | yes |
| S0-2 | Allow `[]` + system `0..<64` for 5 s, then invalidate | Third-party items hide; system items stay; all return | yes |
| S0-3 | Highest system index in use (try `0..<64`, `0..<128`) | Record the range; default stays `0..<64` unless items are missing | no |
| S0-4 (X-4) | (1) A then B then invalidate A; (2) A then B, invalidate B; (3) two processes | Record replace / reject / union / last-writer-wins; pick the §4.2.2 step 5 strategy | yes |
| S0-5 (X-1) | `invalidate` called from a background thread while main is blocked 5 s | Items return within 1 s; no crash. Fail → helper-process design | yes |
| S0-6 (X-5) | `killall MenuBarAgent` while collapsed and while expanded | Record whether items return; our watch fires | yes |
| S0-7 (X-6) | Camera, mic, screen recording, location indicators with their apps hidden | Every indicator stays visible | yes |
| S0-8 (X-7) | Side-effect checklist (a)–(g): ⌘-drag allowed item and the arrow; System Settings › Menu Bar; Clock timer and FaceTime Live Activity; a banner; Control Center and Notification Center; Spotlight, screenshots, Dock; the overflow indicator | Record each; any loss → Known limitations or a design change | (a), (c) yes |
| S0-9 (X-7) | A real `AEAssessmentSession` (test app if the entitlement is obtainable, else Safari AAC page), then our collapse and expand | The exam's restriction is never lifted or replaced; record exam detection signals | yes |
| S0-10 (Y-2) | AX read of on-screen items while a restricted assertion is held | Visible + allowed items readable; record whether hidden items are absent | yes |
| S0-11 (X-19) | AX frames of 27 overflow items | Record; decides §4.8's 27 overflow rows | no |
| S0-12 | Process exit (SIGKILL) while restricted | Items return | yes |
| S0-13 (P-10) | 15 VM: `Preferred Position` seeding for the arrow and a new item | Lands where seeded; else the README fallback | no |
| S0-14 | 15 VM: Length collapse with L = 10 000 on a 5K display; verify-on-next-tick | Works; widths ≥ L − 1 | yes |
| S0-15 (G-14) | Bundle ids and team ids of Hidden Bar, Bartender, Ice, Thaw | Recorded in `KnownMenuBarHiders` | no |
| S0-16 | Hidden Bar 1.11.1 running beside the harness on 27 | Record the X-4(3) behaviour with a real hider | no |

---

## 6. Work items (in order)

**Every item:** its new files' `stubs.tsv` rows; `scripts/lint.sh --strict` clean; `swift build` and `swift test`
green; one commit or more on the branch, each ending with the Co-Authored-By line. Kit items add Linux-safe tests
only. App items run `--selftest-launch` and `--selftest-controls` locally.

| ID | Work | Done when |
|---|---|---|
| **S0** | §5 harness and STEP0-NOTES | Every Blocker row has a recorded result; any plan change is in §R2 |
| **C0** | Commit the Onyx Latch app icon (`Resources/AppIcon.*`, `Info.plist`, `build-app.sh`, `build-icon.sh`, `docs/design/icon-exploration/`) as its own commit | `scripts/build-app.sh` builds with the new icon; stubs/lint pass for `build-icon.sh` |
| **K1** | `ModuleID.hiddenIcons` + `H1-SITES.md`; `MenuPresence.allowed`; `NewModuleCard.hiddenIcons`; `IconsConfig` + `IconsAppsState` (sanitize, defaults, backup allowlist); `IconsFeature`; `KnownMenuBarHiders`; EventCategory; pinned tests (H10 list); lint scope additions (H11); downgrade decode test | Every H1 site has a disposition; the pinned tests and a new `ConfigIconsTests` pass; a 0.4 config decodes with the 0.3.4 types |
| **K2** | `IconsModel` + `IconsLayout`: resolver (6 HB cases + RTL + clipping + multi-screen x-normalization), most-visible-wins, skips (path-verified), notch split (4 classifier + 4 geometry, per screen), arrangement guards, own-items guard inputs, inventory decisions (per-app results, empty/failed never collapses) | `IconsLayoutTests` pass |
| **K3** | `IconsEngineCore` over the ports: Length truth table (§4.2.4 incl. write order), Native allow-list composition, 10 HB Native + 1 Length cases (behaviour), generation tokens, 3 s timeout, at-most-once completion, request joining, kill-switch preemption, `stop()` without waiting, fail-safe reasons, crash-guard markers, race matrix | `IconsEngineCoreTests` pass, including every truth-table row and race pair |
| **K4** | `IconsPolicy` (6 click cases remapped, re-arm reasons + 120 s cap, hover dwell, launch-collapse gate, stable-inventory gate, new-icon rules incl. LRU/30-day, ownItemsGuard, hider pause, exam guard, AX state table) + `IconsIntentQueue` + `IconsActivationRule` | `IconsPolicyTests`, `IconsIntentQueueTests`, `IconsActivationRuleTests` pass |
| **K5** | Controls tables (`IconsPage`, `IconsAdvancedSheet`, `IconsSectionsPage`, `IconsMenuRows`, `IconsItems`) + `IconsCommandGrammar` + `MenuLayout` changes (H2) + four-tab tests + fuzz invariants | `ControlsTests` and `MenuLayoutTests` pass; L15 passes |
| **B1** | `SNMenuBarVisibility.h/.m` + `PrivateMenuBarAPI.swift` + `--selftest-launch` line (H8) | CI prints `unavailable`; local 27.2 prints `available`; poison path covered by a forced-exception debug flag in selftest |
| **A1** | `IconsItems`: creation in `start()`, `behavior = []`, `isVisible` forcing and watch, autosave names, seeding, glyphs, RTL, VO, click wiring, `|` click menu | `IconsModule.init` creates no item (selftest); manual M1–M4 |
| **A2** | `NativeBackend`, `LengthBackend`, `AXInventory`, `IconsWatchdog`, identity check, system-item check | Kit ports satisfied; manual M5–M12 on 27.2 |
| **A3** | `IconsMonitors`: timers, hover, workspace, screen (coalesced, trial skip), session/wake, MenuBarAgent watch, menu-open guard, hider watch, exam watch | Manual M13–M20 |
| **A4** | `ActivationPolicyController` (H9) + migration of the 4 + 13 sites + lint rule + `--selftest-launch` still 4 modules / 0 running | Lint rule catches a planted bare call; manual M21–M22; no empty Edit/Window menu |
| **A5** | `IconsModule` + host wiring (stores, migrations, shutdown, reset, Safe Mode skip, kill-switch observers, EmergencyActions, diagnostics, EventLog) | Module on/off cycles 20× with no leaked item, timer or monitor (EventLog `icons.started` matches; Instruments leaks clean) |
| **A6** | Snaptic-menu section, arrow menu, hidden list (rows, icons, notch, press path) | Manual M23–M27 |
| **A7** | Settings page, Sections, Advanced, How to Arrange sheet, Menu Bar page, Permissions row, sidebar | Every §4.17 string matches the code (grep test in `ControlsTests`); M28–M30 |
| **A8** | Onboarding (4th row, `.arrange` step, texts) + New card + `iconsCard.v1` | Fresh-install and upgrade paths in M31–M32 |
| **A9** | `IconsCLI` + shortcut + `iconsCases` + `prevent-sleep` removal | `--selftest-controls` passes `iconsCases`; `snaptic prevent-sleep` answers "Unknown command" |
| **D1** | README: Hidden Icons section, Switching table, Known limitations, kill switches, Upgrading, On disk, backup list, CLI table, "eight pages", fails-safe wording (G-18), Menu Bar text | `scripts/lint.sh --strict` README rules pass; every §4.17 string the README quotes matches |
| **D2** | `THIRD_PARTY_NOTICES.md` (Hidden Bar design credit, MIT), release notes (incl. new icon), `CFBundleShortVersionString` 0.4.0, `CFBundleVersion` 400 | Version checked by `scripts/build-app.sh` |
| **D3** | Site/docs page if the repo publishes one | Updated or recorded as none |
| **D4** | DESIGN-SYSTEM.md exception for app icons in hidden-icon rows (G-21) | Text added |
| **R** | Code review of the branch; manual checks M1–M36 on 27.2; the Length subset on the 15 VM (`MANUAL-CHECKS.md`); PR with CI green | Every Blocker check passes; PR open with CI green, linked |

---

## 7. Manual checks (recorded in `docs/design/0.4/MANUAL-CHECKS.md`)

**B** = Blocker for release. **L** = also run on the macOS 15 VM (Length).

| # | Check | B | L |
|---|---|---|---|
| M1 | Turn on: items appear left of the Snaptic icon; How to Arrange opens; nothing hides | B | L |
| M2 | ⌘-drag arrow, `|`, `⋮`; positions survive relaunch | B | L |
| M3 | Items can't be ⌘-dragged out of the bar | | L |
| M4 | Arabic as primary language: order and glyphs mirror | | L |
| M5 | First collapse; 27 confirmation when nothing is shown | B | L |
| M6 | Collapse / expand / ⌥ expand with AH on and off, dividers on and off: every §4.2.4 row | B | L |
| M7 | Invalid arrangement refuses collapse with the row text | B | L |
| M8 | Awake session with Awake's icon left of `|`: collapse refused | B | L |
| M9 | Translocated copy (27): refuses with the identity text | B | |
| M10 | Kill switch `Icons.disable.native` while collapsed: expands at once | B | |
| M11 | Privacy indicators stay visible while their app is hidden | B | |
| M12 | Forced main-thread hang (DEBUG-only defaults key `Debug.icons.hangMainSeconds`, added in A2): icons return within 4 s (27) | B | |
| M13 | Auto-collapse waits while the pointer is in the band, a menu is open, a popover is open, Settings is open | B | L |
| M14 | Auto-collapse resumes after 120 s of a stuck popover | | L |
| M15 | Hover expands after 0.5 s; never activates Snaptic | | L |
| M16 | New app launch (27, Show): its icon stays shown; Hide: it's hidden and listed | B | |
| M17 | Length new-icon toast once per day | | L |
| M18 | Sleep/wake, lock/unlock, FUS, display connect/disconnect: state correct | B | L |
| M19 | `killall MenuBarAgent` while collapsed: icons return and re-collapse | B | |
| M20 | Hidden Bar running: Snaptic pauses with the row text; resumes on quit | B | L |
| M21 | Full menu bar on: Snaptic active while shown; focus returns on collapse; Dock icon goes | | L |
| M22 | Full bar + open Settings + collapse: Snaptic stays active | B | L |
| M23 | Hidden list rows: names, "App — Title", icons, VO labels | | L |
| M24 | Choosing a row opens that app's menu; auto-collapse waits 60 s | B | L |
| M25 | Behind the Notch on a notched Mac; absent on an external-only setup | | |
| M26 | Four tabs with ⌘1–⌘4; Icons tab only with Arrow and Snaptic Menu | B | L |
| M27 | Hidden Icons as the only shared module: Snaptic menu shows its section and footer | | L |
| M28 | Settings page, Sections (both engines), Advanced, Restore, Reset Arrow Position | B | L |
| M29 | Arrow hidden in System Settings › Menu Bar (27): icons expand; Show Arrow recovers | B | |
| M30 | 27 permission states (§4.12), incl. relaunch hint | B | |
| M31 | Fresh install onboarding with Hidden Icons on: `.arrange` step; nothing hides | B | L |
| M32 | Upgrade from 0.3.4: New card; Turn On flow; downgrade back to 0.3.4 keeps settings | B | L |
| M33 | `snaptic icons show/hide/toggle/status --json` and every exit-2 text | B | L |
| M34 | Quit while collapsed: icons return (both engines) | B | L |
| M35 | Safe Mode: Hidden Icons doesn't start | B | L |
| M36 | Module off: no items, timers, monitors, or prompts (Activity Monitor + EventLog) | B | L |

---

## 8. Risks

| Risk | Likelihood | Effect | Mitigation |
|---|---|---|---|
| Apple changes or removes `MBAssessmentModeAssertion` in a 27.x update | Medium | Native stops hiding | Encoding check → unavailable, icons shown; kill switch; selftest line |
| Swift trap inside the framework | Low | Crash loop at launch | Crash guard `inFlight` → `disabledBuild`; no launch collapse after an unstable launch; Safe Mode skips the module |
| Main-thread hang while restricted | Low | Icons stuck hidden | Watchdog invalidates off main (or helper process per S0-5) |
| Interaction with exam software | Low | Integrity problem | Exam guard; S0-9 gate |
| Privacy indicator hidden | Low | Serious trust problem | Hard rule; S0-7 gate; runtime system-item check |
| Two hiders fight | Medium | Flicker, lost icons | Pause by default; mandatory pause under last-writer-wins |
| Length engine on unusual displays | Low | Collapse fails | Verify-on-next-tick fails safe; coalesced re-apply |
| AX slow or hung apps | Medium | Stale list | Budgets; never hide on a failed read |
| Activation-policy refactor regresses existing windows | Medium | Focus bugs elsewhere | One controller, Kit truth table, lint rule, M21–M22 |
| Scope (Q2 full parity) | High | Long branch | Ordered items with done-when; Kit-first so most logic is tested before AppKit |

## 9. Not included (recorded)

- Hidden Bar's "Show preferences on launch" (opening Snaptic again shows Settings), its login item (General's),
  single-instance guard (the host has one), About tab (Snaptic's About), 10 localizations (English-only), and
  importing its settings (positions live in its own defaults domain; users arrange once) (Y-16).
- A persisted ⌥ mode (Y-8). AH works on plain expand.
- A CLI to edit sections or choices, and any bundle blocklist (X-21).
- "Never show the Snaptic icon when the list is empty" (G-1; it's the recovery path).
- Moving other apps' icons programmatically (no synthetic events).
- A Quit item in the arrow's menu (Y-9).
- Per-app choices on 14–26 (Q3).
- Lengths above 10 000 pt (X-18; the macOS cap).

---

## R1. Dispositions of the r1 reviews

**A** = accepted as proposed. **M** = accepted with the modification noted. **P** = partly accepted. **R** = rejected,
with the reason. Where a finding is accepted, the plan section that carries it is named.

### Pressure (P)

| ID | Disposition | Where / why |
|---|---|---|
| P-1 | A | §4.2.4 (with Y-1) |
| P-2 | A | H2 (presence model) |
| P-3 | A | §2 ports, §6 K3 |
| P-4 | A | §2 Controls, K5 |
| P-5 | M | H10: two stores; bundle-id data in `SnapticIconsAppsV1`, excluded from backup and diagnostics |
| P-6 | A | H1 with `H1-SITES.md`; no lint exhaustiveness rule |
| P-7 | M | §4.2.2 shim contract, plus the 3 s activation timeout (X-3) |
| P-8 | A | H9, §4.6, §4.7 |
| P-9 | A | §4.1 `behavior = []`, §4.2.5, §4.4 joining |
| P-10 | A | §4.1 seeding, S0-13, README fallback |
| P-11 | A | H11, §6 "Every item" |
| P-12 | A | §6 B1/A4/A9 done-when, §7 numbering, Length VM gate |
| P-13 | A | H3 |
| P-14 | A | §2 flat Kit names |
| P-15 | A | §4.10 second watcher |
| P-16 | A | H2 positional tabs |
| P-17 | M | §4.14: keeps the house "Unknown command" for an off module; policies as proposed |
| P-18 | A | §4.2.6 coordinates |
| P-19 | M | H4: constant per OS (`[.accessibility]` on 27, `[]` on 14–26), on-demand asks on 14–26 |
| P-20 | A | §4.3 wiring |
| P-21 | P | Hygiene fixes applied; `ModuleID.hiddenIcons` stays (Q4) |
| P-22 | M | H10 caps; removal follows Y-3 (3 absent reads, 30 days) |
| P-23 | A | §4.8 press path off main |
| P-24 | A | H9 `switcherPanelOpen` query |

### Grill (G)

| ID | Disposition | Where / why |
|---|---|---|
| G-1 | M | H2: the presence pop-up replaces a separate switch. "Never show the Snaptic icon when empty" is rejected: it's the recovery path |
| G-2 | A | §4.0 |
| G-3 | A | §4.2.5 own-items guard |
| G-4 | A | §4.1 losing the arrow |
| G-5 | A | §4.12 |
| G-6 | M | §4.9 Sections; **Show All Icons and Refresh** leaves the icons shown (auto-collapse re-arms) instead of re-collapsing |
| G-7 | A | §4.9 per-app choices |
| G-8 | M | §4.5: strings accepted; the "until I move it" rule is dropped (positions aren't observable while restricted); `newShown` lifetime instead |
| G-9 | A | §4.7 |
| G-10 | A | §4.17 (range 5–300 per G-31) |
| G-11 | M | §4.17: a pop-up (Arrow and Snaptic Menu / Arrow Only) instead of a fixed value row and a switch; strings adapted |
| G-12 | A | H5, §4.16 |
| G-13 | A | §4.16 |
| G-14 | A | §4.10 |
| G-15 | M | §4.13, §4.8: one row per extra instead of per-app submenus; glyphs and labels as proposed |
| G-16 | A | §4.9, H6, H7 |
| G-17 | A | §4.8 per-screen rules |
| G-18 | A | Ground rules, D1 |
| G-19 | A | §4.9 |
| G-20 | A | §4.3, §4.14, §4.17 |
| G-21 | A | D4 |
| G-22 | A | Removed |
| G-23 | A | §4 renumbered |
| G-24 | A | §7 M1–M36 |
| G-25 | A | "Onboarding step" throughout |
| G-26 | A | §4.10 Switching table |
| G-27 | A | §4.17 |
| G-28 | A | §4.6 |
| G-29 | P | §4.14 error texts and exit codes accepted; the off-module gated message is rejected (house "Unknown command") |
| G-30 | A | H3, D1 |
| G-31 | A | §4.6 (5–300 s, stepper) |

### Adversarial (X)

| ID | Disposition | Where / why |
|---|---|---|
| X-1 | A | §4.11 watchdog, S0-5 |
| X-2 | A | §4.11 crash guard, H6 Safe Mode skip |
| X-3 | A | §4.2.2 timeout and at-most-once |
| X-4 | A | S0-4, §4.2.2 step 5, §4.10 mandatory pause |
| X-5 | A | §4.11 MenuBarAgent watch, S0-6 |
| X-6 | A | §4.11 hard rule, S0-7, §4.2.2 system-item check |
| X-7 | A | S0-8, S0-9, §4.11 exam guard |
| X-8 | M | Merged with Y-2: §4.2.2 layout refresh (restricted re-read of on-screen items, refresh points, 24 h notice) |
| X-9 | A | §4.2.6 |
| X-10 | A | §4.5 stable gate, §4.6 launch rules |
| X-11 | A | §4.2.5 (with G-3) |
| X-12 | A | H9, §4.7 |
| X-13 | M | §4.6, bounded by Y-11 (layer rules, 40 pt, 120 s cap) |
| X-14 | A | §4.4 |
| X-15 | A | H3 |
| X-16 | A | §4.15, H11 lint |
| X-17 | A | §4.8 press path |
| X-18 | P | Coalescing and the trial skip accepted (§4.2.3); the 20 000 length is rejected (macOS caps at 10 000) |
| X-19 | A | §4.8, S0-11 |
| X-20 | A | §4.11 session, §4.4 Space suppression |
| X-21 | M | Planted choices are visible (Sections value); no blocklist, recorded in §4.14 and §9 |
| X-22 | A | §4.2.6 skips |
| X-23 | A | H6 |
| X-24 | A | H8, S0 |
| X-25 | A | §4.17 fail-safe reason line |
| X-26 | M | §4.6: the global monitor stays the baseline, with the cheap path and existence only while on and collapsed |

### Parity (Y)

| ID | Disposition | Where / why |
|---|---|---|
| Y-1 | A | §4.2.4 |
| Y-2 | A | §4.2.2 layout refresh (with X-8) |
| Y-3 | A | §4.5 |
| Y-4 | A | §4.2.5, §4.1 |
| Y-5 | A | §4.2.1 identity check |
| Y-6 | M | §4.1: the locale's direction only (no geometry, which needs AX on 14–26) |
| Y-7 | A | §4.8 |
| Y-8 | A | §4.3 |
| Y-9 | M | §4.3: menu specified, `|` click opens it; no Quit (the Snaptic menu has it) |
| Y-10 | A | §4.1, H6 |
| Y-11 | A | §4.6 |
| Y-12 | M | §4.6: 5–300 s range; the Settings guard becomes "any Snaptic window visible"; settings change restarts the timer |
| Y-13 | M | §4.1 and §4.13 use G-15's glyphs and labels |
| Y-14 | P | Debounce on click and shortcut only; the intent queue covers the rest (§4.4); failed collapse re-arms; hover off by default |
| Y-15 | A | §1, §4.2.2, K2, K3 |
| Y-16 | A | §9, H2 (one control), §4.17 per-engine sheet |

## R2. Changes from S0 (2026-11-07, macOS 27.2 26B123)

Results are in `STEP0-NOTES.md`. No Blocker row failed. These changes follow from what S0 measured.

| ID | Finding | Change |
|---|---|---|
| R2-1 | Now Playing (`com.apple.menuextra.now-playing`) hides under any restriction and can't be allowed. Text Input (`com.apple.TextInputMenuAgent`, under `/System/`) hides unless allow-listed. | §4.2.2 allow-list adds skipped system owners' bundles. The X-6 check is keyed on `AXIdentifier` and excludes now-playing. README Known limitations (D1): **“On macOS 27, the Now Playing icon is hidden while icons are hidden.”** M-checks add Text Input staying visible. |
| R2-2 | Allow-lists **union** across assertions and processes. | §4.2.2 step 5 is activate-then-invalidate with no replace/reject branches. §4.10 offers Run Both Anyway on 27 with the union footnote. K3's race matrix tests the order only. |
| R2-3 | A held restriction survives a MenuBarAgent restart, and AX may then report another display. | §4.11 keeps invalidate-on-terminate (fails safe) and re-reads before re-collapsing. |
| R2-4 | `assessmentagent` always runs. | The exam guard uses `currentSystemPresentationOptions` (§4.11). K4's exam-guard inputs become a presentation-options set. S0-9 is carried to before A3. |
| R2-5 | Hidden third-party items stay in AX at stale frames; allowed ones refresh. | §4.2.2 trusts only allow-listed bundles' frames. K2's inventory decision takes the allow-list as an input. |
| R2-6 | On a crowded display, overflowed extras are absent from AX, and MenuBarAgent adds “Show Hidden Menu Bar Items”. AX and in-process frames describe the same display. | That item is a system owner (skipped). An absent app keeps its last section (§4.2.6, already). §4.8 adds no 27 overflow rows. The arrow's frame sitting outside every screen counts as an unstable inventory: no re-section, no collapse. |
| R2-7 | A restriction doesn't change the in-process status-item frame. | The Y-5 on-screen frame check is dropped (§4.2.1); the identity check stays. `icons.failSafe.ownHidden` is removed. |
| R2-8 | The completion arrives on a background thread; off-main `invalidate` is safe (S0-5). | No change: the shim hops to main, and the watchdog calls `invalidateAll` off main. |
| R2-9 | Rows carried forward: S0-7 camera/mic/location and S0-8 (a)/(c) before A2; S0-9 before A3; S0-13/14 and Bartender's team id at R. | Listed in `STEP0-NOTES.md` › Carried forward. |

## R3. Implementation changes (K5, B1, A1, A2, A3, A4, A5, A6, A7, A8, 2026-11-07)

Where the code departs from the text above, the code and this table win.

| ID | Where | Change |
|---|---|---|
| R3-1 | §4.2.5, §4.14, M33 | Exit codes are the house `ControlExit` values: refusals (paused, needs permission, unavailable, invalid arrangement) exit **5** (`unavailable`), not 2; usage errors exit **2** (`usage`), not 64. Read "exit 2" above as exit 5 and "exit 64" as exit 2. |
| R3-2 | §4.14 | The CLI grammar type is `IconsCLICommand`; `IconsCommand` stays K4's queue command. `IconsCLICommand.command` maps one to the other (`status` → nil). |
| R3-3 | §4.14 | `snaptic icons …` lines count as ordinary `.control` verbs. `KitControl.counterKey` stays Awake-only; the icons rules live in `KitControl.iconsVerbRules` (status `.read`, the rest `.low`). |
| R3-4 | §4.3, A7 | The Menu Bar page row for Hidden Icons lands with A7 (it needs the page's view). K5 adds only the Kit tables and the H2 `MenuLayout` rules (`effectivePresence`). |
| R3-5 | K5, lint | Lint L15 carries `L15_PENDING` for the five Icons tables until their A-item views alias them; it fails once a pending table gains an alias, so the set empties itself by A7. |
| R3-6 | §4.2.2, B1 | The shim's activate call is `activateWithSystemItemsFrom:to:bundles:token:completion:` and returns a BOOL: on NO (poisoned, unverified, bounds 0 ≤ lower < upper ≤ 256, more than 1024 bundles or one outside 1–255 units, token 0 or already held) the completion is never called and `lastRefusal` says why. The shim also has `isPresent`, `heldCount`, `takeDuplicateCompletions` and `simulateExceptionForSelfTest` (the debug selftest's poison path). |
| R3-7 | §4.2.2, H8, B1 | The encoding table, the shim state and the self-test verdict live in Kit (`IconsShimContract`, Linux-tested); `PrivateMenuBarAPI` only reads the raw encodings and marks the shim verified (all five or none). |
| R3-8 | H8, CI | `SNAPTIC_SELFTEST_EXPECT_ICONS_SHIM` (`available` or `unavailable`) turns the launch line into a check; CI sets `unavailable` on both launch runs. |
| R3-9 | H12 | Diagnostics show the shim state plus **five** encoding rows (the table has five selectors), not six. |
| R3-10 | B1 done-when | The local 27.2 `--selftest-launch` run that prints `available` is an owner check at R (it needs Snaptic quit); B1 verified the shim on 27.2 with a standalone probe (all five encodings match, refusals, poison). |
| R3-11 | §4.3, A1 | Both dividers open the arrow's menu on any click (§4.3 named `|` on Length; `⋮` now does the same rather than nothing). The items listen for `.otherMouseUp` too, so the table's "other mouse button" row reaches `IconsClicks`. |
| R3-12 | §2, A1, A2 | `IconsItemsPort.frame(of:)` returns the item's window frame in AppKit's global space; `AXInventory` (A2) converts Accessibility's y to match. |
| R3-13 | §4.1, A1 | Seeding lives in Kit (`IconsSeeding`, step 1 pt): the arrow just left of the leftmost Snaptic item, `|` left of it, `⋮` left of `|`; nothing is seeded without an anchor or over a placed item. P-10 runs through `IconsItems.seedOwnItem(autosaveName:)`, which `StatusMenu` and Awake's indicator call before creating an item. |
| R3-14 | A1 done-when | `--selftest-launch` prints `icons items 0` and fails on any other count. M1–M4 run at R: the items go live when A5 wires `IconsModule`. |
| R3-15 | §2, A2 | `LengthBackend` isn't a visibility port: K3 put the lengths, verify-on-next-tick and the 250 ms screen re-apply in the core over `IconsItemsPort`. A2's `LengthBackend` is the AppKit glue the core still needs: `NSScreen` → `IconsScreen` (a notch's `auxiliaryTopRightArea` read as global, local if outside the screen) and the primary height for `AXInventory`. The `.common`-mode `IconsScheduler` (both engines; A3's monitors reuse it) lives in the same file. |
| R3-16 | §4.2.2, A2 | `NativeBackend` answers a refused `activate` (NO) once, on the next main turn, with `lastRefusal` mapped (`Poisoned` → `.poisoned`, anything else → `.failed`; never a success). After every completion it drains `takeDuplicateCompletions` into `icons.dupCompletion`. The mappings live in Kit (`IconsShimResult`). |
| R3-17 | §4.2.6, A2 | `AXInventory` reads every running app whatever the scope (the resolver decides which frames it trusts) and never asks its own pid. Apps that had extras last time are read first, so a read the 1.2 s total cuts short still has them; an app past the total is `.timedOut` without a call. A read fails as a whole when Accessibility is off or no app answered `.ok`/`.noExtras`. `cannotComplete` (the messaging timeout) is `.timedOut`; `noValue`, `attributeUnsupported` and an app that quit are `.noExtras`; the rest `.denied`. MenuBarAgent counts only by id **and** path. One `icons.inventoryTimeout` per read that ran out of budget. AXPress (A6) lives here too. Verified on 27.2 with a standalone probe: the `AXExtrasMenuBar` children, the first-child `com.apple.menuextra.*` ids and the y flip. |
| R3-18 | §4.11, §4.2.1, A2 | `IconsWatchdog` polls every 250 ms and releases once per hang (a fresh beat re-arms it); `onRelease` runs on main once it beats again (A5: `failSafe(.hang)` + `icons.hangExpand`). It adds and removes the `EmergencyActions` entry with its own start/stop. `Debug.icons.hangMainSeconds` (DEBUG only, M12) blocks main once, after the next successful activation, capped at 10 s, and the key is removed. The identity check compares symlink-resolved paths and needs an `.app` path (`IconsIdentityCheck`). M5–M12 run at R, once A5 wires the module. |
| R3-19 | §4.6, A3 | The band is `frame.maxY − h` with `h = max(NSStatusBar.system.thickness, safeAreaInsets.top, frame.maxY − visibleFrame.maxY)` (`IconsBand`): on 27.2 `thickness` is 22 while the bar is 30 pt (33 on the notched screen), so `thickness` alone missed the bar's lower 8 pt. An auto-hidden bar leaves no inset and keeps the `thickness` band. |
| R3-20 | §4.6, Y-11, A3 | Window guards (`IconsWindowGuard`), from a live window-list probe: a window counts only when visible (alpha > 0.01, at least 2 × 2 pt) and not Snaptic's; "touching the band" means hanging from it (top within 2 pt of the band's bottom edge, reaching below it), so a status item's own window inside the band never counts, and it applies to layer 101 too. Popovers are layers 25…101 (overlays above 101, such as notch apps, the cursor and the screen saver, never count) or a layer-3 window of an app with an extra. Full screen needs both `currentSystemPresentationOptions.fullScreen` and a front-app layer-0 window covering the pointer's screen. "Any Snaptic window" means a visible titled window; the PIP picture, the OSD and toasts are untitled and don't hold the timer. |
| R3-21 | §4.6, A3 | The VoiceOver fact is read off main, only while VoiceOver runs and Accessibility is granted: the cursor is on an extra when one of the system focused element's four nearest ancestors is its app's `AXExtrasMenuBar`. The answer waits at most 0.5 s (then "not on an extra"), so `rearmFacts` is asynchronous. The system-wide element's messaging timeout is never set, since that sets the whole app's. |
| R3-22 | §4.5, §4.2.3, §4.11, A3 | `IconsMonitors` callbacks, wired at A5: another app's launch restarts the +2/+10/+30 s re-read series (the newest launch gets the full series); MenuBarAgent's launch and quit go to `onRecovery` and are never counted as a new app. The Displays trial is pulled (`displayTrialPending`), reported to the core on each screen change before it coalesces, and polled each second until it ends, since Keep posts no screen change. Lock/unlock are the `com.apple.screenIsLocked`/`Unlocked` distributed notifications. |
| R3-23 | §4.10, P-15, A3 | `MenuBarHiderWatcher` is a second class in `OtherAppsMonitor.swift`, not a mode of `OtherAppsMonitor`. It reads a team only for a listed bundle id (`KnownMenuBarHiders.candidate`), from the running process (`SecCodeCopyGuestWithAttributes` + `SecCodeCheckValidity`, off main; about 5–20 ms on 27.2), so an invalid or unsigned copy has no team. M13–M20 run at R, once A5 wires the module. |
| R3-24 | H9, A4 | The re-grep found 14 bare activations, not 13: ConfirmPanel has one now (not two), and Backup has three (two save/open panels, one alert). All 14 and the four policy sites go through `ActivationPolicyController.shared`; the five sites that forced activation (`ignoringOtherApps: true`: ConfirmPanel, PreConfirmPresenter, SystemColorsController, PIPWindow, CustomSessionPanel) keep it as a parameter. Settings and onboarding take a `hold(…)` token while open, and release it in `windowWillClose`. The deferred demotion the two `async` blocks did is now the controller's: while windows or a reason hold it, it re-checks every 0.25 s, and only then. An `activate(…)` holds a demotion for 1 s (`otherReasonHeld`), so a panel shown right after it isn't demoted under it. |
| R3-25 | H9, §4.7, P-24, A4 | The full-bar reason is decided once, at the expand, with the Switcher panel's state at that moment, and kept until the collapse. A Switcher opened later neither demotes nor re-promotes and re-activates Snaptic over the app just switched to. Hidden Icons reports `iconsShown(_:cause:fullBarOnExpand:)` (wired at A5); a full-bar expand forces activation, as Hidden Bar does. On the collapse, focus goes back to the app that was frontmost at the expand before the demotion, and only while Snaptic is still active. Any other app's activation since the expand cancels it. |
| R3-26 | H9, §4.6, A4 | "A Snaptic window is visible" (demotion, and A3's rearm fact) is one test, `ActivationPolicyController.snapticWindowVisible()`: visible, titled, not minimized, and not an `ActivationNeutralWindow`. PIP windows are neutral, titled or not, because a picture can stay up for hours and needs no menu bar; one still holds while it's key (cropping). "Key" is any key Snaptic window. The main menu's Edit and Window menus have items (AppDelegate), so the full menu bar never shows an empty one. Lint L21 bans `.setActivationPolicy(` and `NSApp`/`NSApplication.shared`/`NSRunningApplication.current` `.activate(` outside the controller and `SnapticEntry`; a planted bare `NSApp.activate()` in Backup.swift failed lint. M21–M22 and `--selftest-launch` (blocked by the running Snaptic) run at R. |
| R3-27 | §4.6, A5 | The stable-inventory gate holds launch collapse only. `collapseRefusal` passes `gate.status` when the collapse being run came from `.launch`; a click, shortcut, CLI, menu or timer collapse isn't held by it. |
| R3-28 | §4.6, A5 | While launch collapse waits, the module drives the gate from its 1 s tick: a `refreshLayout()` every 2 s (`IconsStableGate.spacing`) until it passes or its 30 s cap runs out. No refresh while Native is restricted or collapsed (the read would expand). Length without Accessibility, or with the `inventory` kill switch on, feeds the gate an empty read (`[:]`): it has nothing to read, so the bar is as stable as it can be known. |
| R3-29 | §4.2, H3, A5 | Length gets an `AXInventory` too, unless the `inventory` kill switch is on, for Sections, new-icon sightings and the gate. Without it Length still collapses and expands by length. |
| R3-30 | H3, A5 | Kill switches are read at start and polled every 1 s, not observed: `DefaultsKeyObserver` refuses dotted keys (`Icons.disable.native`). A newly set switch that applies to the running engine (`native` or `inventory` on Native, `length` on Length) calls `killSwitchTurnedOn()`; `killSwitchOn(engine:)` re-reads them before every collapse. |
| R3-31 | H3, A5 | EmergencyActions' `icons.invalidateAll` is registered by `IconsWatchdog.start()` (Native only), not by the module. Length has nothing to invalidate: removing the items on stop or quit restores the bar. |
| R3-32 | §4.6, A5 | `unstableLaunch` is "the crash guard tripped at this start" (the last activation didn't finish). The version and OS-build checks compare with one marker, `Icons.launch.seen` = `"<CFBundleVersion>|<OS build>"`, read once per process and written at the first start; a missing marker counts as changed. Reset removes it. |
| R3-33 | §4.6, A5 | Launch collapse is decided once per process (the first start that has an engine). Turning the module off and on later doesn't collapse at "launch" again. |
| R3-34 | §4.2.5, A5 | Length's own-items guard reads Snaptic's other items through `StatusMenu.iconsOwnItems` (the shared item, module items, provider items such as Awake's indicator, by autosave name, window frames only) and re-checks every 1 s. A new id since the last check is `appeared`. |
| R3-35 | H12, A5 | `HostReport.sections` takes `icons:` lines after Awake's, under "Hidden Icons", shown while the module is enabled (as Awake's are). The lines carry the engine, unavailable reason, state, shim rows, kill switches, disabled build, layout age, section counts, last fail-safe with its time, last refusal and Accessibility state; no bundle ids. |
| R3-36 | §4.17, A5 | The fail-safe toast shows once per launch and never for `session` or `agentRestart` (the system's doing, recovered without the person). Every fail-safe still sets the "last fail-safe" row. |
| R3-37 | §4.0, H4, A5 | When the factory says unavailable the items still show (by OS: Native on 27+, Length below), and clicking the arrow opens Hidden Icons settings, where the reason is shown. On Native, the arrow also opens Settings while Accessibility isn't effective (`arrowOpensSettings`), unless icons are hidden. |
| R3-38 | §4.5, A5 | Native's re-reads while restricted (after a launch) read the held bundles only (`read(scope: .restricted(allowed:))`) and feed `IconsSighting(inventory:skip:)` to `restrictedRead`; the core's own restricted reads use an empty placed map. |
| R3-39 | A5 | The "20 on/off cycles, no leak" check isn't in a self-test: `--selftest-*` may not call AX or TCC (lint rule 9) and the module's start does. It's manual at R (EventLog `icons.started` against cycles, Instruments Leaks). `icons.started` counts only when a core starts, so an unavailable or Safe Mode start doesn't count. |
| R3-40 | H6, A5 | In Safe Mode the module reports `degraded("Paused in Safe Mode")` and creates nothing (no items, monitors or timers); "Hiding menu bar icons" is in Safe Mode's skipped list. |
| R3-41 | §4.5, A5 | Length's new-icon toast ("A new icon may be hidden. ⌘-drag it to the right of the arrow to keep it shown." [Show Icons]) fires only while collapsed, once per app per day (`toastDue`/`toasted`); expanded, a new icon is plainly visible. |
| R3-42 | H6, A5 | Reset clears both stores (`arranged` with them), every `NSStatusItem Preferred Position Snaptic.icons.*` and `NSStatusItem Visible Snaptic.icons.*` key, and `Icons.launch.seen`. The crash-guard keys stay: they are about the OS build, not settings. Both stores are force-saved in the migration pass before the ledger, and flushed at quit and reset. |
| R3-43 | §4.8, A6 | The headers read "Hidden (n)" and "Behind the Notch (n)" in title case; the header style draws them small. |
| R3-44 | §4.8, A6 | Hidden lists both Hidden and Always Hidden, nearest the arrow first. Behind the Notch lists shown icons a notch covers (`IconsNotch.split`). |
| R3-45 | §4.8, A6 | On Length while collapsed, a fresh read finds hidden icons off the screen. They're listed after the placed ones under their app's section, in bar order from the boundary, and match at press time by size only (`frameKnown` false). |
| R3-46 | §4.8, A6 | Opening a menu asks for a background re-read through the new `IconsEngineCore.listOpened()`, at most once per 5 s. It never expands, and the open menu keeps the rows it was built with. |
| R3-47 | §4.3, A6 | While the engine is unavailable, Show, Hide and Show All are left out. The reason row explains why; the arrow menu still has the reason and Settings. |
| R3-48 | §4.8, A6 | Length with `Icons.disable.inventory` shows no list slot at all: hiding still works, but nothing can be listed. |
| R3-49 | §4.3, A6 | "Hidden Icons Settings…" has no ⌘, key equivalent: ⌘, belongs to Snaptic Settings. |
| R3-50 | §4.8, A6 | `icons.pressNoop` counts when no new on-screen window for the app's pid appears within 0.5 s (CGWindowList before and after). |
| R3-51 | §4.8, A6 | `hiddenListPressed()` is called before the expand and again after a successful press, so the auto-collapse timer doesn't run out under the opened menu. |
| R3-52 | §4.13, A6 | A row's hint "Opens its menu." is set through `toolTip`. Its app icon has an empty `accessibilityDescription`, so it's decorative and the title names the app. |
| R3-53 | §4.8, A6 | An AX title that only repeats the app name falls back to "Icon n"; a missing app name reads "App". Every extra the read found counts toward "several", including off-screen ones. |
| R3-54 | A6 | `StatusMenu.assistiveInputInUse()` (static) is internal so the Show All row can use it. `AXInventory.press(pid:index:)` is replaced by `press(_:screen:completion:)`, which re-reads, waits for the icon to be on the arrow's screen, matches it and returns `PressOutcome`. |
| R3-55 | §4.9, §4.17, A7 | The status row takes the first of: unavailable (Try Again only for the crash guard; stopped reads "Starting…"), paused, permission (27), arrow missing, `\|` missing (Length), `⋮` missing, arrangement (Length), identity refusal, an own-items row other than Some Hidden, then the engine state. Calibrating reads "Hiding icons…". Notes follow in order: Some Hidden, `⋮` misplaced, the fail-safe line (not for session or agent restart), stale; a note equal to the main line is dropped, and an unavailable engine has none. The rules are `IconsPageRules.status` over `IconsPageFacts` (the CLI already had `IconsStatusFacts`). |
| R3-56 | §4.6, A7 | `IconsIntentQueue`'s user sources include `.settings`, so the status row's Show Icons and Hide Icons count as asked for. |
| R3-57 | §4.0, A7 | The Native first-collapse confirm (`IconsPageRules.asksBeforeFirstCollapse`) runs in `submit` before a collapse asked for from the arrow, the menu, the shortcut or Settings (not the CLI or hover), at most once per process and again after Reset Arrow Position…. Cancel is the default button and leaves icons shown. |
| R3-58 | §4.9, G-31, A7 | Auto-collapse is a switch titled with the current seconds plus an indented stepper (5–300, step 5) while it's on, instead of an inline field. |
| R3-59 | §4.1, A7 | Show Arrow and both Show Divider buttons share `icons.page.showArrow` and call `showMissingItems()`, which makes every missing own item visible. |
| R3-60 | §4.2.5, A7 | Reset Arrow Position… stops the engine, removes the items' position and visibility keys, clears `arranged`, then starts it again. It's an alert, since the Advanced sheet never presents another. |
| R3-61 | §4.12, A7 | Open Privacy Settings watches for the pane closing by polling the frontmost app; Trusted still false 5 s later is `notEffective` (Relaunch Snaptic). |
| R3-62 | §4.9, A7 | General › Reset All Settings… adds `IconsPageRules.resetAllNote` only while Hidden Icons is on or arranged. |
| R3-63 | §4.9, A7 | Sections names come from the running apps (`NSRunningApplication.localizedName`), falling back to the bundle id. The page's summary ("Which apps’ icons are shown, hidden, and always hidden."), its off state ("Turn on Hidden Icons to see its sections.") and an empty section's "No icons" aren't in §4.17. |
| R3-64 | §4.17, G-11, A7 | The Menu Bar page's "Off" for Hidden Icons is the pop-up's help while the module is off; the pop-up is dimmed as for the other modules. The spec is `menubar.page.iconsPresence`. |
| R3-65 | §4.9, A7 | Reset Arrow Position… has the help "Puts the arrow and dividers back next to the Snaptic icon if you can’t find them." The Advanced sheet's Diagnostics section lists `diagnosticsLines()` above the kill switches. |
| R3-66 | §4.12, A7 | The Permissions page lists Hidden Icons under Accessibility's "Needed by" on 14–26 while it runs, and on 27 adds the relaunch note (Relaunch Snaptic) when the grant isn't effective. |
| R3-67 | §4.17, D1, A7 | The README's Menu Bar text, "eight pages" and the ⌘1–⌘4 line stay for D1. The §4.17 check is `IconsControlsTests.testEveryCanonicalStringIsInTheSources` (whole literals, counts and times as interpolations). `L15_PENDING` is empty. |
| R3-68 | H5, §4.16, A8 | `OnboardingStep.arrange` sits between Displays and Permissions. Its heading is title case, "Arrange Your Icons", like the other steps. It shows How to Arrange's content (the diagram, "Hold ⌘ and drag…", the bullets and the closing line; shared as `IconsArrangeGuide`), then "Nothing hides until you click the arrow for the first time." For onboarding, this step is the "turning it on presents How to Arrange" path. |
| R3-69 | H5, A8 | `resumeStep`: a saved step that no longer applies moves on to the next step that does (it was always the step after Modules, which could go back to Displays). |
| R3-70 | H5, A8 | The modules step no longer disables scrolling: four rows fit at the default text size, and the grouped form scrolls when it doesn't. The other steps are unchanged. The largest-text check is M31's. |
| R3-71 | H4, H5, A8 | The permissions step adds Hidden Icons' `requiredPermissions` while it's on (Accessibility on 27, shown with its 27 pane name; nothing on 14–26). The Done line shows while Hidden Icons is on and not turned off by `Modules.disable.hiddenIcons`. |
| R3-72 | H10, §4.16, A8 | `insertingIconsCard(upgrader:ledger:)` runs after the 0.3.1 welcome and before M1. It records `iconsCard.v1` whatever it decides, and adds the card only for an upgrader (`isV031Upgrader`, so 0.1 users on `upgradeDefaults` too) whose onboarding is done, with Hidden Icons off and the card not stored. Turn On Hidden Icons presents How to Arrange on the next main-queue turn after `go(to:)`, which clears the open sheet. |
| R3-73 | §4.16, A8 | The §4.16 strings joined `IconsControlsTests.canonical`. |
