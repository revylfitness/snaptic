# Snaptic 0.3.1 plan (r3)

## What 0.3.1 adds

0.3.1 adds three things:

1. **Tabs in the Snaptic menu.** When two or more modules share the Snaptic menu, it shows a row of tabs at the top, one per module. Only the selected module's items show below the tabs.
2. **Keeping awake with the lid closed.** This is an opt-in Awake mode, "lid-closed mode", that keeps a MacBook awake with its lid closed, including on battery with no external display. It asks for an administrator password each time it turns on.
3. **In-app updates (Part E).** Release builds are signed with the owner's Developer ID and notarized, and they update themselves with Sparkle 2 from a signed feed on GitHub Releases.

The owner made the following decisions on 2026-10-19, and they are not reopened here:

- The tabs are a segmented control inside the native `NSMenu`, not a popover, and the menu remembers the last tab.
- Lid-closed mode asks for an administrator password each time. Nothing is installed and nothing persistent is granted. The two rejected options were a one-time helper install and a sudoers rule.
- In-app updates use Sparkle 2 with automatic install, ship in 0.3.1, and are signed with the owner's existing Developer ID (09:00–09:40). The rejected options were notify-only, Sparkle with `disable-library-validation`, and a home-made updater.

## Review history

- **r1 → r2:** four reviews (security, code, parity, design), recorded in `review-r1-*.md`. They found 5 Blockers, 32 Majors and 51 Minors.
- **r2 → r3:** the same four reviewers re-reviewed r2 (`review-r2-*.md`). They found 2 Blockers (the same `&` grammar bug, found twice), 12 Majors and 45 Minors. r3 also adds Part E, from `briefs/updates.md`.
- Every finding is handled in the revision that follows it. Dispositions are in §R (r1) and §R2 (r2) at the end.

## Inputs and conventions

- Inputs are `briefs/{menu,awake,research}.md`.
- "P03 §x" means `docs/design/0.3/PLAN.md`, and "DS" means `docs/design/0.3/design-spec.md`.
- Strings in this plan are canonical. They use ’ (curly apostrophes) so they can be pasted straight into `L()`.

## Ground rules carried over from 0.3

- SnapticKit is Foundation-only and tested on Linux. All pure logic lives there.
- CI is the only compiler. `lint.sh --strict` stays green, and no new ratchet rows are added.
- Every control lives in a `*Controls` table and is used. Every new file has a `stubs.tsv` row.

---

## Part A: Tabs in the Snaptic menu

### A1. What the user sees

```
┌──────────────────────────────────────┐
│ Safe Mode Is On / Leave Safe Mode…    │  first group, any tab (as today)
│ Sleep Is Turned Off                   │  host-level safety rows (B3.4), any tab
│ Turn Sleep Back On…                   │
├──────────────────────────────────────┤
│ [ Window Switcher | Displays | Awake ]│  tab bar: only with 2+ modules in the menu
├──────────────────────────────────────┤
│ …the selected module's items…         │  no section header (the tab names it)
├──────────────────────────────────────┤
│ More Display Features…  (as in 0.3)   │
│ Recent Notices         ›  (when any)  │
│ Snaptic Settings…               ⌘,    │  unchanged: restores the last Settings pane
│ Quit Snaptic                    ⌘Q    │
└──────────────────────────────────────┘
```

**Where tabs appear**
- Tabs appear only in the shared Snaptic item, and only when `plan.shared.count >= 2`.
- A fresh install puts Window Switcher, Displays and Awake in the shared menu, so it shows three tabs (MenuLayout.swift:126-145). That matches the owner's screenshot.

**One module, no modules, own-icon menus**
- With one module in the menu there is no tab bar, and the section keeps its 0.3 header (`menu.snaptic.sectionHeader` stays in use).
- With no modules, "No Modules Are On" shows as today.
- Own-icon menus don't change.

**Order and labels**
- Tabs follow `plan.shared` order: Window Switcher, Displays, Awake.
- Labels are module titles. The fallbacks keep HIG's equal segment widths in the common case. In order:
  1. `.fillEqually` with full titles;
  2. `.fillEqually` with `ModuleID.shortTitle` ("Switcher", "Displays", "Awake");
  3. `.fit` with short titles.

  Widths are measured including the attention image (below).
- Each segment's accessibility label is always the full title. The tooltip is "<Title> (⌘n)", or "Awake, on (⌘3)" while Awake governs.

**Attention marks**
- A segment whose module needs attention shows a 10 pt `exclamationmark.circle` image next to its label, and VoiceOver adds ", needs attention". Modules report this through a new `menuAttention: Bool` on the module contract (A4):
  - Displays: `degraded || panic.isLatched || unprotectedReason != nil`. Pauses caused by other apps (for example "Paused While MonitorControl Runs") don't count, because they are a steady state.
  - Window Switcher: Accessibility missing.
  - Awake: none of its own, because the leftover rows are host-level.
- Mixing text and an image in one segmented control goes against HIG ("prefer either text or images"). DS §3.3 records this as a deliberate safety exception: without the marks, a user who stays on one tab would never see another module's warnings, a regression from 0.3's stacked menu.
- **No active image.** While Awake governs, the Awake segment gets only the VoiceOver suffix ", on" and the tooltip. The N11 shared glyph and Awake's indicator already show that a session is on.

**Awake's tab**
- Awake's tab shows the full Awake rows, style `tab`: the own-menu rows minus "Awake Settings…".
- The compact rows are used only when Awake is the single shared module, as in 0.3 §5.4.

**Remembering the tab**
- The tab is remembered across opens and relaunches.
- If the remembered module isn't in the menu, the first tab shows. The stored choice is kept, so it comes back when that module returns.

**Footer**
- The footer is unchanged from 0.3.
  - "Snaptic Settings… ⌘," restores the last-viewed Settings pane (DS §1.1, HIG).
  - "More Display Features…" stays in the footer. It exists only while Displays is off, so it could never appear on a Displays tab.

### A2. Building and switching

**The tab bar**
- `MenuKit.tabBar(labels:selected:attention:active:control:onSelect:)` is a factory beside `MenuKit.switchHeader`, so L6 needs no new exemption. It returns an item whose view is `MenuTabBarView`, defined in the new file `Core/MenuTabBar.swift`.
- The view is an `NSView` subclass, **not** a `MenuRowView`, so it never draws the selection fill. It hosts an `NSSegmentedControl` (`.selectOne`, `controlSize = .small`, inset by `MenuKit.rowInset`). The row is 28 pt tall.
- Whether the item is `isEnabled = false` (so arrow keys skip it) is decided by HW-24 (clicks still work) **and** HW-25 (VoiceOver isn't told it's dimmed and can still enter it). Otherwise the item stays enabled and draws no highlight.
- Accessibility label: "Menu tabs". Help: "Press Command-1 to Command-3 to switch tabs." (The range follows the tab count.)

**`StatusMenu.build(shared)` with tabs** builds these groups:
1. The host safety group: Safe Mode rows, then the B3.4 leftover rows.
2. The tab bar.
3. The selected section, from `module.menuSection(tabbed: true)` with `header: false`.
4. The footer.

StatusMenu keeps three references: `tabBarItem`, `sectionItems: [NSMenuItem]` (exactly the items it inserted for the section) and `footerSeparator`.

**Switching tabs** runs synchronously in the control's action. That action fires at the end of the control's own tracking, the same cell path as the shipping `NSSwitch` and `NSSlider` rows.
1. Store the choice (A5).
2. Don't call `cancelTracking()`, which AppKit documents as ending **all** menu tracking. Removing the parent item closes its submenu. HW-24 checks that this doesn't glitch. If it does, a tab click is ignored while a submenu is open. A retained, shared submenu delegate records which submenus are open, because `NSMenu.delegate` is weak.
3. Remove exactly `sectionItems`.
4. Insert the new section's items after the tab bar's separator, adding or removing the trailing separator so groups stay single-separated. If the new section is empty (a module stopped while the menu is open), show the status row "Nothing to Show".
5. Post `NSAccessibility.post(element: tabBarView.window ?? tabBarView, notification: .layoutChanged)`. NSMenu has no public window accessor.

The switch uses no timers and no `RunLoop.main.perform` (N15, L14). The removed items are never under the pointer, so R2C c12 doesn't apply.

**Width**
- At build, StatusMenu measures every tab's section in a scratch `NSMenu` (`menu.size.width` after adding the items) and sets `minimumWidth = max(MenuKit.width, widest)`. Switching then never widens the open menu, and the segment never moves under the pointer.
- After reading the width, StatusMenu calls `scratch.removeAllItems()`. Otherwise Awake's header list would hold scratch items whose `menu` isn't nil, and would keep refreshing them.
- `menuSection(tabbed:)` must be cheap and free of side effects, and each module confirms this in Step 0. The selected section is built twice on each open (once to measure, once to show), which is accepted.

**Height**
- The menu grows or shrinks downward on a switch, and Quit and Settings move. This is accepted.
- DS §3.4's "doesn't flicker or resize while open" gets a 0.3.1 exception: a tab switch replaces the section and resizes the menu.

**Live rows**
- A switch builds fresh items, so Awake's header refresh (which prunes items where `menu == nil`) registers the new headers.
- A removed slider's sink is owned by its row item and dies when the item is deallocated. StatusMenu holds no other references.
- A rebuild requested while the menu is open still only marks it dirty.

### A3. Keyboard and VoiceOver

0.3 §5.1 C4 and parity M4 require a native path for every custom-row action. For tabs, the paths are:

**Keyboard**
- ⌘1…⌘n select tab n by **position**.
- Native items "Show Window Switcher Tab", "Show Displays Tab" and "Show Awake Tab" sit in the footer group, just before Snaptic Settings…. There are only as many as there are tabs, and each carries ⌘n for its position.
- They are hidden (`isHidden = true`, `allowsKeyEquivalentWhenHidden = true`) unless an assistive input is in use, in which case they show:
  - `NSWorkspace.shared.isVoiceOverEnabled`;
  - `isSwitchControlEnabled`;
  - Full Keyboard Access (`NSApp.isFullKeyboardAccessEnabled`).

  StatusMenu marks the shared slot dirty on `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` and on VoiceOver KVO (`.receive(on: DispatchQueue.main)`, L10), so the items appear without a relaunch.
- `StatusMenu.menuHasKeyEquivalent` returns true with that item's target and action when `openMenus > 0` and the event is ⌘1–⌘n. Otherwise it returns false, as today.
- The item's action stores the choice and sets `shared.dirty = true`. It never changes the menu in place.
- The expected result is that **the menu closes and the next open shows the chosen tab**. If HW-26 finds that tracking continues, the action switches in place instead.

**Discoverability**
- The segment tooltips, the control's accessibility help, and the Menu Bar page footer, which replaces MenuBarPage.swift:100's line: "The Snaptic icon appears when a module is set to Show in Snaptic Menu. With two or more, the Snaptic menu shows a tab for each; while it’s open, press ⌘1, ⌘2, or ⌘3 to switch tabs."
- The README says "⌘1–⌘3 choose a tab (⌘1–⌘2 with two tabs)".

**VoiceOver**
- The segmented control is an accessibility element. VoiceOver users reach it and choose a segment with VO-Space, and `.layoutChanged` refreshes the menu's children (HW-25).

**Other keys**
- Type-select reaches only the visible tab.
- The open menu's key equivalents are ⌘, ⌘Q and ⌘1–⌘n. No module defines others: Switch Windows' ⌥⇥ is drawn but never fires, as today.

### A4. Contracts and the Kit logic

**Module contract** (`Core/ModuleContracts.swift`):
- `func menuSection(tabbed: Bool) -> [NSMenuItem]`. Its default calls `menuSection()`, and Awake overrides it.
- `var menuAttention: Bool { false }`. Displays and Window Switcher override it.

**Awake** (Kit, `AwakePresentation.swift`): `AwakeMenuFacts.style: AwakeMenuStyle { own, compact, tab }` replaces `compact: Bool`. A computed `compact` stays for the existing tests.
- `tab` gives the `own` rows minus `.settings`.
- `AwakeModule.menuSection(tabbed: true)` builds `style: .tab`.

**`SnapticKit/MenuLayout.swift`** gets an `enum MenuTabs`:
- `tabs(plan:) -> [ModuleID]`: `plan.shared` when it has 2 or more modules, otherwise `[]`.
- `selected(stored:tabs:) -> ModuleID?`: lenient decode.
- `labelStyle(fullWidths:shortWidths:fitWidths:imageWidth:attention:available:) -> .fullEqual | .shortEqual | .shortFit`.
- `keyIndex(for:tabs:) -> Int?` and `tab(atKeyIndex:tabs:) -> ModuleID?`.
- `attention(_ flags: [ModuleID: Bool], tabs:) -> Set<ModuleID>`.

**Tests**
- Truth tables.
- The existing 5,000-case fuzz gains these invariants:
  - `tabs.isEmpty || tabs.count >= 2`;
  - `selected ∈ tabs` whenever tabs is non-empty;
  - key indices are a bijection onto `1...tabs.count`.

### A5. Persistence

- The selection is stored as a plain `UserDefaults.standard` string under `snapticMenuTab`, following the `settingsLastRoute` precedent. It is navigation state, so it is not in `ModulesConfig`, not in backups, and not in the key cross-check. **No reset clears it**, the same as the last Settings route.

### A6. Controls, lint and docs

**Controls**
- `StatusMenuControls` gains these specs:

  | ID | Kind | Notes |
  |---|---|---|
  | `menu.snaptic.tabs` | new `ControlKind.menuTabBar` | `SettingsIndex.requiresSearch` returns false for it |
  | `menu.snaptic.showTab` | `.menuItem` | `when: [.perItem("module")]` |

- `menu.snaptic.sectionHeader` stays: single-module menus use it.
- `menu.snaptic.upgrade` doesn't change.

**Lint**
- No L6 change: the item is built in MenuKit.
- `MenuTabBar.swift` falls under the existing L13/L14 `Core/Menu*` globs.

**Docs.** T-docs owns all README text; T-menu supplies wording in its PR description. Pages to change:
- README "Menu Bar" (l.42-52) and "In the menu bar" (l.242-244).
- DS §3.3: new sketch.
- DS §3.4: the resize exception.
- `MenuBarPage` footer (A3). The page summary doesn't change.
- HW-15's row budget, restated as "the tallest single tab ≤ 24 lines in the default setup".

---

## Part B: Keep awake with the lid closed

### B0. Names, used everywhere

Design-spec §4.7 gets a terminology row: "closed-lid, clamshell, disablesleep and Power Protect are all called **keep awake with the lid closed**; the noun is **lid-closed mode**."

| Where | Text |
|---|---|
| Menu action (off) | "Keep Awake with the Lid Closed…" |
| Menu state (on) | "✓ Keep Awake with the Lid Closed". No ellipsis, because turning it off asks nothing. |
| Idle submenu | "Keep Awake with the Lid Closed ›", whose presets carry "…" (each asks for a password) |
| Pending rows (disabled) | `authorizing`: "Waiting for Password…"; `verifying`: "Turning On…"; `stopping`: "Turning Off…" |
| Setting | "Keep awake with the lid closed" |
| Notices and README | "lid-closed mode" |
| VoiceOver | "Keeping your Mac awake with the lid closed." and "Lid-closed mode turned off." |
| Status and accessibility suffix | ", even with the lid closed" |

### B1. What the user sees

#### Settings › Awake › Advanced…

A new section, "Lid closed", follows the experimental pointer-nudge pattern. (DS §1.5 places the lid option in Advanced, "with a warning about heat".)

- **The toggle.** `ToggleSetting(L("Keep awake with the lid closed"), help: L("Choose Keep Awake with the Lid Closed in the Awake menu. Asks for an administrator password each time."))`.
  - It is backed by `features[.lidClosed]`, which is opt-in and off by default.
  - It shows only on Macs with a battery (`when: .hardware(.battery)`).
- **Writable-bundle help.** Shown only while the toggle is on and Snaptic's bundle is writable by your account, as the toggle's secondary help (not a warning row): "Your account can change this copy of Snaptic, so another app could change it and misuse the password prompt. Learn More…".
  - The string lives in Kit next to the Permissions copy.
  - Learn More… opens README › "Your password and what runs as root". That section gives the release-zip fix: `sudo chown -R root:wheel /Applications/Snaptic.app` (the same advice the Permissions page links to).
- **Footer.** "While lid-closed mode is on, your Mac can’t sleep for low battery or heat, so Awake turns it off at the battery level set on the Awake page (at least 10%), when your Mac gets hot, or after 24 hours. Use it on a hard surface, not in a bag. Learn More…"
- **One battery limit.** Lid-closed mode turns off at `max(10, Awake’s battery floor)`. When Awake's battery floor is turned off, the limit is 20%.
- **One fixed time limit of 24 hours.** There's no picker: the idle submenu already makes you pick the session's length, so the cap only matters for Until Turned Off and task-bound sessions (parity r2 cut 1).
- **Translocated copy.** Lid-closed mode is unavailable. This row shows instead: "Snaptic is running from a temporary location. Move it to Applications to use lid-closed mode." (a Kit sibling of PermissionsPage.swift:80).

#### The main Awake page

The `lidRoute` line depends on state. All three variants live in Kit, with a test:
- **Feature off:** "To keep it awake with the lid closed, connect power and an external display, or turn on lid-closed mode in Awake › Advanced."
- **Feature on and available:** "…or choose Keep Awake with the Lid Closed in the Awake menu."
- **Unavailable** (translocated, or no lid): the 0.3 text, unchanged.

#### The Awake menu

New Kit row cases are `.lidClosed(LidRowState)` and `.lidSubmenu([presets])`. They appear in all three styles: own, compact and tab.

- **Idle, feature available.** "Keep Awake with the Lid Closed ›" goes directly after the start-default row. The submenu holds:
  - every preset, in preset order, each titled `AwakePreset.title + "…"`;
  - a separator;
  - "Custom…", which opens the panel with **Keep awake with the lid closed** turned on.

  Choosing a preset asks for the password. **The session starts only after lid-closed mode is verified on** (B3.1), so Cancel starts nothing.
- **A session you started from the menu or Settings is running.** "Keep Awake with the Lid Closed…" goes directly after "✓ Keep Display On".
  - Choosing it asks for the password and adds the mode to the running session.
  - While the mode is on, the row reads "✓ Keep Awake with the Lid Closed". Choosing it turns the mode off without a password.
- **Any other governing state shows the idle submenu.** That covers hotkey, command-line, launch or restored sessions, holds, and rules. Choosing a preset replaces the running session once the mode is verified on. The success toast says "Replaced the running session."
- **While a lid request is pending,** every lid row shows the B0 pending text, disabled.
- **Superseding a pending request.** Any manual start or Turn Off while `authorizing` or `verifying` an idle start supersedes the lid request (B3.0).

#### Custom… panel

In Start mode only (not in Add Time…):
- `ToggleSetting(L("Keep awake with the lid closed"), help: L("Asks for an administrator password when you click Start."))`.
- While it is on, the button reads "Start…".

#### Awake status section (Settings)

The existing "Keep Awake" (idle) and "Options" (active) pull-downs gain the same items, with the B0 titles. The idle item has a per-preset child list. No new button.

#### The password dialog

macOS's own authorization dialog shows, through `/usr/bin/osascript`. It names osascript as the requester, not Snaptic; HW-28 records exactly what it shows. Kit builds the prompt text with `LidWatchdog.promptText(floor:)`. The time limit is the fixed 24 hours, written with `AwakeCountdown.unit`:

> Snaptic wants to keep your Mac awake with the lid closed for up to 24 hours. Sleep turns back on when the session ends, when Snaptic quits, at 20% battery, or if your Mac gets hot. Enter an administrator password to allow this.

Touch ID is likely to work, because osascript is Apple-signed (research §4); HW-28 checks.

#### Feedback while verifying

If verification takes longer than 2 s, a toast shows: "Turning on lid-closed mode…".

#### Status everywhere

- **Header and Settings status row.**
  - While the mode is on, the lid line is the **first** extra: "Stays awake with the lid closed" when the session ends first, or "Stays awake with the lid closed until 6:40 PM" when the cap ends first.
  - It is a Kit test for header priority.
- **Lid warning.** It shows when `lidWillSleep == true && !lidModeOn && (onBattery || !external)`, with a Kit test. It re-evaluates on `$lidWillSleep`, on screen changes, and on `$lidMode`.
- **Indicator.**
  - While the mode is on, the Awake indicator uses `AwakeGlyphFamily.lidActiveSymbol`, a per-family SF Symbol checked in the macOS 15 SDK. Where a family has none, it falls back to the family's active glyph composited with a short bar under it, as a template image tested at 15 pt.
  - It must be visibly different from N11's dot on the shared glyph.
  - The accessibility label and tooltip add ", even with the lid closed". The shared glyph's N11 label gets the same suffix.
  - HW-30 records how it looks.
- **Last end, kept for 12 h.** It uses the existing "Ended at …: …" pattern:
  - "Lid-closed mode ended at 3:12 AM: battery at 20%."
  - "…: your Mac got hot."
  - "…: time limit reached."
  - "…: another app turned sleep back on."
  - "…: Snaptic quit."

  It is cleared at the next turn-on.
- **Cap warning.** When the cap will end before the session, a toast shows 5 minutes ahead: "Lid-closed mode turns off in 5 minutes. If the lid is closed then, your Mac goes to sleep."
- **History.** Entries gain `lidClosed` (true if the mode was on at any point), shown as the subtitle suffix " · Lid closed".
- **CLI.** `snaptic awake status --json` gets a last key `lidClosed` (true/false). The tab-separated line doesn't change (parity r2 cut 3).

### B2. Who can turn it on: N19, the lid gate (extends N10)

- **Who can request it.** Only a direct user action in Snaptic's UI, in this process:
  - a menu click;
  - the Custom… panel;
  - a Settings pull-down item. Settings starts check `SettingsShell.mayStart()`.
- **What can never request it.** None of the following can: the CLI, the control socket, rules, holds, start-at-launch, restore or resume, History "Start Again", hotkeys (including preset slots), backups, presets, or `defaultOptions`. Lid-closed mode is not an `AwakeSessionOptions` field, so no persisted path can carry it.

**How it's stored and who owns it**

| Name | What it is | Owner |
|---|---|---|
| `AwakeSession.lidRequested: Bool` | The session's runtime flag. It is not in CodingKeys and is reset in `init(from:)` and `sanitized(now:)`, exactly like `overrideGuards`. | Only `SessionController` sets it. L16 is extended with `\.lidRequested\s*=(?!=)`, exempting `SessionController.swift` and `SnapticKit/AwakeSession.swift`. |
| `AwakeRuntimeState.lidMode: AwakeLidMode` | The state machine's published state (B3.0). | Assigned only in `LidClosedController.swift` (a second L16 clause). |
| `lidClosed` | The field name in the CLI JSON and in History. | — |

LidClosedController asks SessionController to set or clear `lidRequested` through `setLidRequested(_:for sessionID:)`, and gets a callback when the session ends.

**`AwakeLidGate`** is pure Kit and exhaustively tested. It is a truth table `(source, event) -> allowed | end | keep`:
- **Allowed** for `.menu`, and `.settings` with `mayStart`, either on an idle Mac or in a menu/Settings session.
- **Keep** when the session is replaced by a `.menu` start, or a `.settings` start with `mayStart`, in this process. The watchdog is untouched. `until` becomes the earlier of the new session's end and `capStart + 24 h`. `capStart` is the original turn-on (continuous clock) and never resets, so the app and the watchdog always agree on the cap.
- **End** in all other cases:
  - the session ends;
  - it is replaced by any other source, **including a hotkey**, whose bindings any same-user process can change;
  - a trigger or hold takes over;
  - the module stops, or Safe Mode starts;
  - the feature is turned off, or the kill switch `Awake.disable.lidClosed` is set;
  - restore or resume. The header then says "Lid-closed mode ended at …: Snaptic quit." That line is left out when the B3.4 leftover rows already explain the state.

**CLI**
- `awake extend` is refused while the mode is on. The refusal is `.lidClosedSession` with exit code 4 and the text "Lid-closed sessions can’t be extended from the command line. Use Add 1 Hour in the menu."
- `awake stop` works: anything may turn sleep back **on**.

**Starting with guards in play.** Each refusal shows a toast. The mode never offers Start Anyway.

| Condition | Toast |
|---|---|
| Battery discharging and below `floor + 5` | "Lid-closed mode needs at least 25% battery, or connect power." (the number is computed) |
| Thermal `serious` or worse | "Your Mac is too hot for lid-closed mode right now." |
| A Start Anyway session (`overrideGuards`) | "Lid-closed mode isn’t available in a Start Anyway session." |
| Translocated bundle | The B1 translocated row's text |
| Journal pending (B3.4) | "Snaptic is finishing an earlier lid-closed session. Try again in a minute." |
| Leftover (B3.4) | "Turn sleep back on first: an earlier lid-closed session didn’t finish." with **Turn Sleep Back On…** and **Keep Sleep Off** |

Low Power Mode does **not** block the mode. It follows the session's `endOnLowPowerMode` like everything else, and the README recommends Low Power Mode with the lid closed.

### B3. Mechanism

| Part | Files and responsibilities |
|---|---|
| App, user side | `Awake/Core/LidClosedController.swift`: the state machine, heartbeat, liveness checks and display handling. `Core/LidRecovery.swift`: host-level leftovers. |
| Spawning | `HelperSpawner.spawnAdminScript` (osascript) and `HelperSpawner.spawnTool` (fixed user-level `pmset displaysleepnow`). |
| Kit | `SnapticKit/LidWatchdog.swift`: script, command, quoting, validation, result parsing and prompts. `AwakeLidGate.swift`. `AwakeLidPolicy.swift`: refusals, floor, cap, end classification and leftovers. Presentation lives in `AwakePresentation.swift`. |
| Root side | A fixed `/bin/sh` script. Its only writes are `/usr/bin/pmset -a disablesleep 0|1` and `/usr/bin/pmset sleepnow`. |

#### B3.0 States (single flight)

`AwakeLidMode` has these states:
- `off`
- `authorizing(token)`
- `verifying(token, pid)`
- `on(token, pid, until)`
- `stopping(token)`
- `failed(reason)`, which shows one toast and then returns to `off`.

**Rules**
- **One operation at a time.** In every state except `off` and `on`, all lid entry points are disabled and show the B0 pending text.
- **Token check after every await.** If the token has changed, or the session the request belongs to is gone, the request is superseded. (A pending idle start has no session yet.)
- **Manual start or Turn Off while pending.** Either one supersedes a pending idle-start request, silently.
- **Every exit from `authorizing` or `verifying` other than into `on`** does three things:
  1. write `stop-<token>`;
  2. stop the heartbeat;
  3. keep the journal until IORegistry `SleepDisabled` reads 0. If it still reads 1 after 30 s, the leftover rows show (B3.4).

  This covers cancel, timeout, error, a failed verify, and being superseded.
- **App Nap.** While the state isn't `off`, the controller holds `ProcessInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Snaptic lid-closed mode")`.

#### B3.1 Turning on (LidClosedController)

1. **Preflight.**
   - Check the gate, the feature, the B2 refusals and lid presence.
     - Lid presence comes from feature availability: `availability(of: .lidClosed)` reads `AppleClamshellState` from IORegistry **synchronously**, not from the published value (which arrives after module start), and is recomputed on `.didWake`.
     - Without a lid it is `.unavailable("No lid")`.
   - Read `SleepDisabled` from IORegistry (the kernel) and from the preference (`OtherAssertionsReader.sleepDisabledPreference()`).
   - If either is on, Snaptic doesn't touch it. The toast says "Sleep is already turned off for this Mac by another app or command, so it stays awake with the lid closed." The session starts or continues without lid-closed mode.
2. **Journal.** One slot: `~/Library/Application Support/Snaptic/awake/lid.json`, mode 0600, written atomically.
   - Contents: `{token, bootSessionUUID, startedAt (wall + continuous), pid: nil, instanceID: nil, floor}`.
   - `token` is 128 random bits, written as 32 lowercase hex characters.
3. **Beacon directory.**
   - `D = confstr(_CS_DARWIN_USER_TEMP_DIR)` with its trailing `/` trimmed, plus `/snaptic-lid`. Both sides use this exact string, never a realpath.
   - Create `D` with mode 0700. `lstat` must show a directory owned by our uid with mode 0700. If not, show "Snaptic couldn’t turn on lid-closed mode. Try again." and log stage `beacon`.
   - Remove old `stop-*` and `beat-*` files.
   - Create `beat-<token>` with `open(O_CREAT|O_EXCL|O_NOFOLLOW|O_WRONLY, 0600)`. Keep the fd open for the heartbeat.
4. **Spawn** with `HelperSpawner.spawnAdminScript(LidWatchdog.startScript(args, prompt:))`.
   - **The process.** A suspended spawn of `LidWatchdog.osascriptPath` with `-e <source>`.
     - stdout is a pipe, reusing `spawn`'s reply pipe and `ReaderState` (its existing 64 KB line cap).
     - The environment is explicitly minimal: `PATH=/usr/bin:/bin` and `LANG=en_US.UTF-8`.
   - **Identity, before SIGCONT.** The child must satisfy `LidWatchdog.osascriptRequirement` = `anchor apple and identifier "com.apple.osascript"`.
     - It is compiled once by a `static let` using `SecRequirementCreateWithString` and `SecRequirementCopyData` (Security is already linked), then checked with `SNProcess.process(_:satisfies:)`.
     - `spawnAdminScript` checks only "stopped" and the requirement. It skips `spawn`'s responsibility check, because whether the child is disclaimed decides that.
   - **Disclaimed by default** (least privilege: osascript shouldn't run under Snaptic's Accessibility or Screen Recording grants). If HW-28 shows that disclaiming breaks or changes the dialog, the child isn't disclaimed and the reason is recorded in B6.
   - **Exit** is observed with a `DispatchSourceProcess` on main and `reapIfExited`.
   - **Timeout.** After 120 s, SIGTERM to **osascript's pid only**. That counts as a timeout (B3.0 exit).
   - `spawnAdminScript` does **not** require helper identity or `unavailableReason == nil`.
5. **Result.** `LidWatchdog.parseResult(stdout)` accepts only `^ok [0-9]+$` with `1 < pid < 100000` → `.launched(pid)`, or `^err -?[0-9]+$` → `.canceled` (−128) or `.failed(code)`. Anything else is `.failed(-1)`. The AppleScript wraps the call in `try … on error number n`.
   - **Canceled:** silent.
   - **3:** the "already turned off" toast.
   - **64:** stage `args`.
   - **Otherwise:** "Snaptic couldn’t turn on lid-closed mode. Try again."
6. **Verify.**
   - Record `pid` and `SNProcess.instanceID(for: pid)`. It uses `sysctl(KERN_PROC_PID)`, which answers for root processes, unlike `PROC_PIDTBSDINFO`.
   - It must report uid 0 and a start time after the spawn; otherwise stage `verify`.
   - Then poll IORegistry `SleepDisabled` every 0.5 s for up to 10 s.
   - **On:**
     - The state becomes `on`.
     - For an idle start, the session starts now with `lidRequested = true` (source `.menu` or `.settings`). If that start is refused, go straight to `stopping`, and the session's own refusal toast shows.
     - VoiceOver says "Keeping your Mac awake with the lid closed."
   - **Not on:** the B3.0 exit path, with the failed toast.
7. **Five seconds later**, the app checks again. If IORegistry `SleepDisabled` reads 0 twice, the mode ends with `otherApp`: "Another app turned sleep back on, so lid-closed mode stopped."

#### B3.2 The root command and watchdog

**Command.** `LidWatchdog.command(args)` builds three lines, joined with LF (which the AppleScript layer writes as `\n`):

```
/bin/sh -c <Q(script)> snaptic-lid check <Q(a1)>…<Q(a6)> </dev/null >/dev/null 2>&1 || exit $?
/usr/bin/nohup /bin/sh -c <Q(script)> snaptic-lid run <Q(a1)>…<Q(a6)> </dev/null >/dev/null 2>&1 &
echo $!
```

- `check` runs in the foreground. Its exit code becomes the `do shell script` error number (TN2065).
- Only the second line is backgrounded, and `$!` is `nohup`'s pid. `nohup` execs `/bin/sh`, so that is the watchdog's pid.
- All output is redirected, so `do shell script` returns at once.
- `Q` is POSIX single-quoting: `'…'`, with each `'` written as `'\''`.
- `appleScript(command:prompt:)` escapes `\` as `\\`, `"` as `\"` and LF as `\n`, and refuses every other control character.
- Arguments are `uid pid token capSeconds floor dir`, validated in Kit by the same rules as the script.
  - `capSeconds` is 86 400, fixed. The validation range is 3 600–86 400, and the script adds 60.
  - `floor` is 10–50.

**Script.** `LidWatchdog.script` is a raw literal (`#"""…"""#`), so `\(` and `\1` stay literal. A Kit test checks that it contains no byte below 0x20 other than LF. T-lid-kit owns the exact text and its golden test.

```sh
unset IFS; PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
umask 077; trap '' HUP
MODE=$1; U=$2; P=$3; T=$4; C=$5; F=$6; D=$7
case "$MODE" in check|run) ;; *) exit 64;; esac
num() { case "$1" in ''|*[!0-9]*) return 1;; esac; }
num "$U" && num "$P" && num "$C" && num "$F" || exit 64
case "$T" in *[!0-9a-f]*|'') exit 64;; esac; [ ${#T} -eq 32 ] || exit 64
case "$D" in /var/folders/*/snaptic-lid) ;; *) exit 64;; esac
case "$D" in *..*|*[!A-Za-z0-9_/+.-]*) exit 64;; esac
[ "$F" -ge 10 ] && [ "$F" -le 50 ] && [ "$C" -ge 3600 ] && [ "$C" -le 86400 ] || exit 64
C=$((C+60))
# Stored preference: the "System-wide power settings:" block only, first match; 1, 0 (absent) or ? (odd/unreadable)
sd() { O=$(/usr/bin/pmset -g 2>/dev/null) || { echo '?'; return; }
  printf '%s\n' "$O" | /usr/bin/awk '/^System-wide power settings:/{s=1;next} s&&/^[^ \t]/{s=0}
    s&&$1=="SleepDisabled"&&!d{v=$2;d=1} END{if(!d)print 0; else if(v=="0"||v=="1")print v; else print "?"}'; }
rd() { /usr/sbin/ioreg -r -n IOPMrootDomain -d 1 2>/dev/null; }
# Kernel value on IOPMrootDomain: 1, 0 or ? (no line)
ksd() { rd | /usr/bin/awk '/"SleepDisabled" = /{f=1; v=($NF=="Yes")?1:0} END{print f?v:"?"}'; }
key() { rd | /usr/bin/awk -v k="\"$1\" = " 'index($0,k){print $NF; exit}'; }
owned() { [ -f "$1" ] && [ ! -L "$1" ] && [ "$(/usr/bin/stat -f %u "$1" 2>/dev/null)" = "$U" ]; }
[ "$(sd)" = 0 ] && [ "$(ksd)" = 0 ] || exit 3      # someone else holds it, or unreadable: never take it
[ "$MODE" = check ] && exit 0
owned "$D/stop-$T" && exit 0                         # stopped before we started (late password)
WESET=0; HALT=0
cleanup() {
  trap '' TERM INT
  [ "$WESET" = 1 ] || return
  i=0; while [ $i -lt 3 ]; do [ "$(sd)" = 0 ] && break
    /usr/bin/pmset -a disablesleep 0; /bin/sleep 1; i=$((i+1)); done
  [ "$HALT" = 1 ] && return                          # shutting down: never sleepnow
  i=0; while [ $i -lt 5 ] && [ "$(ksd)" != 0 ]; do /bin/sleep 1; i=$((i+1)); done   # powerd → kernel
  j=0; while [ $j -lt 3 ]; do
    [ "$(key AppleClamshellState)" = Yes ] || return
    [ "$(key AppleClamshellCausesSleep)" = Yes ] && { /usr/bin/pmset sleepnow; return; }
    /bin/sleep 1; j=$((j+1)); done
}
trap 'cleanup' EXIT; trap 'HALT=1; exit 0' TERM; trap 'exit 0' INT
/usr/bin/pmset -a disablesleep 1; WESET=1
i=0; until [ "$(sd)" = 1 ] && [ "$(ksd)" = 1 ]; do       # post-set check, up to 3 s
  i=$((i+1)); [ $i -ge 6 ] && exit 0; /bin/sleep 0.5; done
START=$(/bin/date +%s); Z=0; Q=0; LB=0
while :; do
  /bin/sleep 5 & wait $!                               # traps run without waiting out the sleep
  N=$(/bin/date +%s); num "$N" || exit 0
  [ $((N-START)) -ge "$C" ] && exit 0                  # hard cap
  /bin/kill -0 "$P" 2>/dev/null || exit 0              # liveness hint only (any pid answers root)
  owned "$D/stop-$T" && exit 0                         # asked to stop
  owned "$D/beat-$T" || exit 0                         # beacon gone
  M=$(/usr/bin/stat -f %m "$D/beat-$T" 2>/dev/null); num "$M" || exit 0
  [ $((N-M)) -le 20 ] || exit 0                        # Snaptic hung: the beacon is the real bound
  S=$(sd); K=$(ksd)
  if [ "$S" = 1 ] && [ "$K" = 1 ]; then Z=0; Q=0
  elif [ "$S" = 0 ] && [ "$K" = 0 ]; then Z=$((Z+1)); [ $Z -ge 2 ] && { WESET=0; exit 0; }   # reset by someone else, both sources, twice: not ours
  else Q=$((Q+1)); [ $Q -ge 2 ] && exit 0; fi           # disagreement or unreadable: restore
  B=$(/usr/bin/pmset -g batt 2>/dev/null)
  case "$B" in *discharging*)
    PC=$(printf '%s' "$B" | /usr/bin/sed -n 's/.*[^0-9]\([0-9][0-9]*\)%.*/\1/p' | /usr/bin/awk 'NR==1')
    if num "$PC"; then LB=0; [ "$PC" -le "$F" ] && exit 0
    else LB=$((LB+1)); [ $LB -ge 2 ] && exit 0; fi;; esac
  TP=$(/usr/bin/notifyutil -g com.apple.system.thermalpressurelevel 2>/dev/null | /usr/bin/awk '{print $2}')
  num "$TP" && [ "$TP" -ge 2 ] && exit 0               # heavy or worse (= ProcessInfo .serious)
done
```

**What root does**
- It writes only through `pmset -a disablesleep 0|1` and `pmset sleepnow`.
- **`sleepnow`.** It runs only in `cleanup`, and only if all of these hold:
  - the system isn't shutting down;
  - the kernel shows sleep re-enabled (powerd applies the preference asynchronously; while the kernel bit is set, `sleepnow` is refused);
  - the lid is shut, and closing it would sleep the Mac.

  It is needed because the kernel doesn't re-check a closed lid when `SleepDisabled` clears (xnu IOPMrootDomain.cpp:8386-8389).
- It never writes, deletes, follows symlinks in, or reads the contents of user-controlled files. It only `stat`s them for owner, type and mtime.

**Every exit restores.**
- The EXIT trap runs `cleanup`. TERM and INT exit through it. `cleanup` ignores further TERM and INT, so a second signal can't cut it short.
- Every arithmetic operand is checked with `num`.
- An unreadable value or a disagreement between the preference and the kernel counts toward a restore.
- The one deliberate non-restoring exit clears `WESET` first. It needs both the preference and the kernel to read 0, twice.

**Ownership.** Both `check` and the start require the preference **and** the kernel to read 0 (`exit 3`). The restore runs only when `WESET = 1`.

**Late password.** The stop file is written on every failure exit in the app (B3.0) and checked before anything is set.

**Detachment**
- `nohup` and `&`, with all three standard streams redirected.
- The app signals only osascript's pid.
- HW-31 checks:
  - osascript returns within 1 s of the password;
  - `ps -p <pid> -o comm,ruid,uid` shows `sh 0 0`;
  - the watchdog survives osascript's exit and a SIGTERM to osascript.

  If the real uid isn't 0, the user could kill the watchdog. The app's liveness check (B3.3) is then the guarantee, and B6 says so.

**Cost.** About 9 forks every 5 s. HW-35 measures wakeups. If they're significant, the period becomes 10 s and staleness 30 s.

**Shell test (CI).** `LidWatchdog.script(tools:)` takes a tool-path table, defaulting to the absolute macOS paths (golden-tested). A Kit test on the `kit-linux` job runs the generated **command** under `/bin/sh` (dash) and, where present, `bash --posix`. It uses stub `pmset`, `ioreg`, `notifyutil` and `stat` tools that record calls, and asserts:
- a `check` exit of 3 or 64 becomes the command's exit status;
- `$!` is the `run` process's pid;
- the command returns at once;
- the EXIT trap restores sleep after these exits: stop file, missing beacon, stale beacon, induced arithmetic error, TERM;
- `sleepnow` runs only under its conditions;
- `WESET=0` only on a double agreement of the preference and the kernel.

If needed, lint rule 12 gets an exemption for that single test file.

#### B3.3 App side while on

**Heartbeat**
- A `DispatchSourceTimer` on a private serial queue fires every 5 s with 0.5 s leeway.
- Each tick touches the beacon (`futimens` on the open `O_NOFOLLOW` fd) **only if** `HostHeartbeat.shared.mainAgeMillis() < 10_000`.
- The fd is closed in the timer's cancel handler on the same queue, so a reused fd number is never touched.
- **Liveness.** Each tick runs `kill(pid, 0)`, where ESRCH means gone, and compares `SNProcess.instanceID(for: pid)` with the value recorded at verify. It also reads IORegistry `SleepDisabled`.
- State changes hop to main with `DispatchQueue.main.async { MainActor.assumeIsolated … }` (rule 2).
- **Gone, or 0 twice:** the mode ends (`watchdogLost` or `otherApp`). If `SleepDisabled` still reads 1 while the watchdog is gone, the leftover rows show (B3.4).

**Display while the lid is shut**
- **`lidShut`.** `AwakeArbiterInput.lidShut`, which defaults to `false`, is true only while the mode is on, the lid is closed (`SystemEventsMonitor.lidClosed == true`, now published as `AwakeRuntimeState.lidClosed`) **and no external display is attached**. It is re-evaluated on screen changes.
  - While it's true, the session's effective display policy is `maySleep`, so Snaptic's own assertion doesn't cancel display sleep.
  - With an external display attached, the user's Keep Display On choice stands.
- **Display sleep, as the user.** While `lidShut` is true and the built-in display isn't asleep (`CGDisplayIsAsleep`), the app runs `HelperSpawner.spawnTool(LidWatchdog.displaySleepArgv)` = `/usr/bin/pmset displaysleepnow`. This needs no root. At most every 10 s, because powerd defers the request for about 30 s after a wake.
  - Apple silicon has no `IODisplayWrangler`, and `pmset` uses the private SkyLight call there, so this is the route that works on both architectures (NM2).
  - `spawnTool` accepts only a fixed `ToolCommand` created in `LidWatchdog.swift`.
- **Lid open.** Opening the lid wakes the panel by itself (HW-30). If it doesn't, T-lid-app adds `ActivitySimulator.wakeDisplayOnce()`, which has no feature dependency and stays inside L2's file.
- **Known limitations** (README):
  - another app's display assertion (`caffeinate -d`) can keep the panel lit, and Other Apps lists it;
  - the keyboard backlight may stay on, because there's no public API to turn it off.

  HW-30 records both.

**Turning off** (any end path)
1. Create `stop-<token>` with `open(O_CREAT|O_NOFOLLOW|O_WRONLY, 0600)`.
2. Cancel the heartbeat.
3. Poll IORegistry `SleepDisabled` for up to 15 s.
   - Reads 0: clear the journal and go to `off`.
   - Still 1: show the leftover rows.

**Ends while the lid is shut.** Suppose the mode ends for a reason other than the session's own end, while the lid is closed and `lidWillSleep == true`. The session then ends too, with reason `.lidEnded`:
- toast: "Awake turned off: lid-closed mode ended with the lid closed.";
- phrase: "lid-closed mode ended with the lid closed";
- `AwakeEndText` gets a test for it.

The watchdog's `sleepnow` covers a hung app.

**Quit**
- `applicationWillTerminate` writes the stop file synchronously.
- At turn-on, an `EmergencyActions` action is registered. It captures an immutable `final class LidStopPath` that owns the C string and is never freed explicitly, and it does `open(…O_CREAT|O_EXCL|O_NOFOLLOW|O_WRONLY, 0600)` and `close`. It runs from the dispatch signal source's global queue (AppDelegate.swift:199-211) and is removed at `off`.
- A crash or `kill -9` is caught within 5–20 s by `kill -0` and the beacon.

**Sleep and wake.** Sleep is blocked while the mode is on. If a wake happens anyway, `.didWake` re-reads `SleepDisabled` and runs the liveness checks.

**Cap.** The app ends the mode at `until` and warns 5 minutes ahead (B1).
- If the lid is shut, the session ends too.
- If the lid is open, the session continues, and a toast says: "Lid-closed mode turned off after 24 hours. Awake is still on; your Mac sleeps if you close the lid."
- The watchdog's cap is 24 h + 60 s from its own start, which is never later than the app's `capStart + 24 h + 60 s`.

**Guards ahead of the session's own**
- Battery at or below the floor while discharging: "Lid-closed mode turned off at 20% battery."
- Thermal `serious` or worse: "Lid-closed mode turned off because your Mac got hot."
- Then the lid-shut rule applies.
- The root side enforces the same floor and heat cutoff independently.

#### B3.4 Leftovers and recovery (host level)

`LidRecovery.atLaunch(safeMode:)` runs in `AppDelegate` step 7, beside `RevertJournal.recoverAtLaunch`. It runs whatever the state of Awake, the feature or the kill switch, and also in Safe Mode.

**Classification.** `AwakeLidPolicy.classify(journal:bootUUID:sleepDisabled:now:ownPID:)`:

| Journal | `SleepDisabled` | Result |
|---|---|---|
| none | — | nothing (someone else's setting: reported, never changed) |
| present | 0 | clear it |
| from another boot | 1 | **leftover** (the value survives a reboot) |
| same boot | 1 | **pending**: re-check after 30 s, then **leftover** |

- While the result is pending or leftover, turning the mode on is refused (B2).
- The journal is single-slot.
- A journal alone never prompts. The leftover rows show only while `SleepDisabled` reads 1, and no journal field ever reaches root.

**What the user sees for a leftover**

| Where | Rows |
|---|---|
| **Every Snaptic menu** (shared, own and Awake's custom one) | First group, above the tab bar: a status row "Sleep Is Turned Off", then "Turn Sleep Back On…" and "Keep Sleep Off". The host builds these items, with `menu.snaptic.*` ids, in StatusMenu, and passes them to Awake's provider through `CustomItemRow`, the same path as the shared footer. |
| **Awake page and Advanced › Other Apps** | "Your Mac can’t sleep. This may be from an earlier lid-closed session that didn’t finish." with **Turn Sleep Back On…**, **Keep Sleep Off** and **Not Now** |
| **When Awake isn't running** | A toast with the same text, and the same three buttons |

What the buttons do:
- **Turn Sleep Back On…** runs `LidWatchdog.restoreScript`. It is fixed, takes no arguments, and only runs `/usr/bin/pmset -a disablesleep 0`.
  - It goes through the same spawner and wrapper.
  - Its prompt is "Snaptic wants to turn sleep back on. It may have been left off by an earlier lid-closed session. Enter an administrator password to allow this."
  - Afterwards the app re-reads `SleepDisabled` and clears the journal.
- **Keep Sleep Off** clears the journal and removes the rows everywhere. From then on the value is reported as "another app or command", as today. No prompt, no root.
- **Not Now** hides the rows everywhere until the next launch.

While a Snaptic journal exists, Advanced › Other Apps never says "Snaptic can’t change this".

### B4. Interplay

- **Session guards** (battery floor, adapter, Low Power Mode, lock, user switch) are unchanged. They end the session, which ends the mode.
- **Fast user switching:** the mode follows the session (`userSwitchEnd`).
- **Pointer movement:** unchanged (N10).
- **Drive Alive:** unaffected.
- **`endOnSystemSleep`:** the Advanced help becomes "When you choose Sleep or close the lid (not in lid-closed mode)."
- **Updates (Part E):** an update never installs or relaunches while the mode is on (E4).

### B5. Kit additions (all Linux-tested)

**`LidWatchdog`.** `AdminScript` and `ToolCommand` have `fileprivate` inits, so only this file can make them.
- Script and command: `script(tools:)` (default `script`), `command(args)`, `appleScript(command:prompt:)`, `startScript(args, prompt:)`.
- Fixed values: `restoreScript(prompt:)`, `displaySleepArgv`, `osascriptPath`, `osascriptRequirement`, `capSeconds = 86_400`.
- Parsing and validation: `Arguments.validated(...)`, `parseResult`.
- Prompts: `promptText(floor:)`, `restorePromptText`.
- Tests:
  - golden script text, with no control bytes except LF;
  - quoting round trip: shell-unquote(AppleScript-unescape(x)) equals the argv;
  - the command has three lines, and only the second ends in `&`;
  - charset and range fuzz;
  - a `parseResult` table, including pid bounds;
  - the B3.2 shell test.

**`AwakeLidGate`:** the N19 truth table, exhaustively tested (the hotkey rows included).

**`AwakeLidPolicy`:**
- start refusals (pending vs leftover text);
- `floor(awakeGuards:)`;
- `until(sessionEnd:capStart:)`;
- `capWarningDue`;
- `endsSession(lidShut:lidWillSleep:reason:)`;
- `classify(...)`.

**`AwakeLidMode`, `AwakeLidEnd`, `AwakeLidFailStage`.**
- `AwakeLidEnd`: `user, sessionEnded, replaced, cap, battery, heat, otherApp, watchdogLost, quit, safeMode, featureOff, moduleStopped`.
- `AwakeLidFailStage`: `beacon, spawn, args, verify, timeout`.
- Both are closed `CaseIterable` enums.

**Config, feature and backup.**
- `AwakeFeature.lidClosed`: `.optIn`, `all: [.sessions]`, `uses: [.power, .system]`, `controller: .sessions`. It's added to `safeModeRemoves`, it isn't unkillable, and its kill switch is `Awake.disable.lidClosed`.
- There is no lid config. The cap is fixed and the floor is derived.
- Backup: `removedPaths += [awake, "features", "lidClosed"]`. `importable` keeps `features[.lidClosed]` from the current Mac. `KitBackupTests` covers it.

**Text and logs**
- `AwakeLogEvent` gains `lidOn`, `lidOff(AwakeLidEnd)`, `lidFailed(AwakeLidFailStage)` and `lidLeftover`.
- New cases: `AwakeRefusal.lidClosedSession`; `AwakeEndReason.lidEnded`, with its `AwakeEndText`.
- New fields: `AwakeStatusFacts.lidClosed` (JSON only); History gets `lidClosed`.
- All B0–B3 strings live in Kit, with tests:
  - header priority, the warning rule, and the `lidRoute` variants;
  - "1 hour" vs "hours";
  - the "Ended at" lines.

### B6. Security model, lint and docs

**Threat model.** README › "Keeping awake with the lid closed" › "Your password and what runs as root".

- **What runs as root.**
  - Only while lid-closed mode is on, or during recovery, Snaptic runs a short shell script as root. Its text is in `LidWatchdog.swift`.
  - It changes only `SleepDisabled`, and may run `pmset sleepnow`.
  - It turns sleep back on in any of these cases:
    - the session ends;
    - Snaptic quits or stops responding;
    - the battery reaches the limit;
    - the Mac gets hot;
    - 24 hours pass;
    - the script itself fails.
- **What a program running as you can do.**
  - Turn sleep back **on**: create the stop file, or delete the beacon.
  - While Snaptic is hung, keep the beacon fresh. That's bounded by the cap, the root-side battery floor and heat cutoff, and by Snaptic's process being alive.
  - It can't start the mode without you typing a password into a dialog.
- **The dialog names osascript, not Snaptic.** Any app can show this dialog with any text. If Snaptic is installed owned by root (`INSTALL=1`, or `sudo chown -R root:wheel /Applications/Snaptic.app` for the release zip), only enter your password right after you choose Keep Awake with the Lid Closed or Turn Sleep Back On… in Snaptic.
- **If your account can change Snaptic** (the default after you drag it to Applications), that advice isn't enough: a program running as you can change Snaptic so that its own prompt runs something else as root. Snaptic shows this under the setting (B1).
  - **Why warn rather than refuse.** The same program could show the identical dialog without touching Snaptic, and refusing would remove the feature from the default install. The weaker protection is stated plainly here instead.
  - A translocated copy is refused.
- **Power loss or restart while on.** Sleep stays off until you choose Turn Sleep Back On… or Keep Sleep Off (B3.4).
- **Security software** may flag "osascript with administrator privileges" (Elastic rule, research §4). With Developer ID signing (Part E) the parent is no longer ad hoc, which removes one of that rule's conditions.
- **Environment.**
  - osascript gets only `PATH` and `LANG`, so the root shell starts from that.
  - The script unsets `IFS`, sets `PATH`, and calls every binary by absolute path.

**Lint**
- **Rule 12.** The regex gains `NSAppleScript|NSUserScriptTask|OSAScript`.
- **New rule L18.** These literals may appear in `Sources/` only in `SnapticKit/LidWatchdog.swift`: `with administrator privileges`, `do shell script`, `disablesleep`, `displaysleepnow`, `sleepnow`, `/usr/bin/pmset`, `osascript`, `nohup`.
  - `AdminScript(` and `ToolCommand(` may appear only there.
  - `spawnAdminScript(` and `spawnTool(` may be called only from `LidClosedController.swift` and `LidRecovery.swift`. Their definitions in `HelperSpawner.swift` are exempt.
  - The lint03.py docstring lists L18.
- **L4** (`"pmset"`, `"sudo"`) is unchanged.
- **L16** gets the B2 clauses.

**Docs and copy**
- **README lines to change:** 19, 155, 212, 252, 254–258, 273, 275, 318, 543, 589, 610–611, 639, 652, 666, 673, 686, 707 and 718.
  - The heading at 254 becomes "Keeping awake with the lid closed". Update the anchors at 273 and 639.
  - The "spawns nothing" claim becomes: "Awake runs a program only while you use lid-closed mode: `/usr/bin/osascript` asks macOS for an administrator password, then starts a short shell script as root that runs `pmset` and turns sleep back on when the session ends, Snaptic quits or stops responding, the battery reaches your limit, your Mac gets hot, or 24 hours pass. While the lid is closed, Snaptic also runs `pmset displaysleepnow` as you to keep the screen dark."
- **site/index.html** lines 401, 600 and 637. The lid card reads: "Lid closed on battery? Turn on lid-closed mode with an administrator password. It stops at low battery, on heat, and after 24 hours."
- **UI strings:**
  - `AwakePresentation.swift:319` (lid warning) and `:621` (`lidRoute`);
  - `OtherAssertionsSection.swift:17`;
  - `AwakeAdvancedSheet.swift:108`.
- **Comments:** `OtherAssertionsReader.swift:9` and `OtherAssertions.swift:6`.
- **THIRD_PARTY_NOTICES** Insomnia row: "reading SleepDisabled again 5 s after setting it; a recovery journal written before sleep is turned off; display sleep with the lid closed, honouring display assertions" (ideas, not code).
- **Design-spec:**
  - §1.5;
  - §3.3, the attention-mark exception;
  - §3.4, the resize exception;
  - §4.7, terminology.
- **Release notes:** `docs/design/0.3.1/RELEASE-NOTES-0.3.1.md`.

### B7. Controls (Step 0 declares all of them, each with one stub use)

| Table | Id | Kind | Conditions, search and notes |
|---|---|---|---|
| `AwakeAdvancedSheetControls` | `awake.advanced.lidClosed` | `.setting` | `keys: ["features.lidClosed"]`; `when: awake + [.hardware(.battery)]`. `SearchSpec("Keep awake with the lid closed", keywords: ["lid", "clamshell", "closed display", "insomnia", "amphetamine", "disablesleep"])`. |
| | `awake.advanced.lidBundleLearnMore` | `.statusAction` | `when: … + [.parentOn(ControlID("awake.advanced.lidClosed")), .state(.bundleWritable)]` |
| | `awake.advanced.lidRestore` | `.statusAction` | `when: awake + [.state(.lidLeftover)]` |
| | `awake.advanced.lidKeepOff` | `.statusAction` | same condition |
| | `awake.advanced.lidDismiss` | `.statusAction` | same condition |
| `AwakePageControls` | `awake.page.status.lidClosed` | `.statusAction` | `when: awake + [.awakeFeature(.lidClosed)]` |
| | `awake.page.status.lidPreset` | `.statusAction` | `+ [.perItem("preset")]` |
| | `awake.page.status.lidRestore`, `.lidKeepOff`, `.lidDismiss` | `.statusAction` | `when: awake + [.state(.lidLeftover)]` |
| `AwakeMenuRowsControls` | `menu.awake.lidClosed` | `.menuItem` | `when: [.awakeFeature(.lidClosed)]`; `.state(.lidModeOn)` for the ✓ title |
| | `menu.awake.lidSubmenu` | `.menuSubmenu` | — |
| | `menu.awake.lidPreset` | `.menuItem` | `[.awakeFeature(.lidClosed), .perItem("preset")]`; menu "lid submenu" |
| | `menu.awake.lidCustom` | `.menuItem` | — |
| `StatusMenuControls` | `menu.snaptic.tabs` | `.menuTabBar` | — |
| | `menu.snaptic.showTab` | `.menuItem` | `.perItem("module")` |
| | `menu.snaptic.lidLeftover` (status), `.lidRestore`, `.lidKeepOff` | `.menuItem` | Placements "Snaptic menu", "own menus" and `MenuPlacementSpec("Awake menu", customize: .none)` |
| `CustomSessionPanelControls` | `awake.custom.lidClosed` | `.setting` | The `awake.custom` surface is exempt from search. |

New `ControlState` cases: `lidModeOn`, `lidLeftover` and `bundleWritable`. All three are used above.

---

## Part C: Hardware checks

These are numbered after 0.3's HW-23. The list lives here and in README's testing section.

| ID | Check |
|---|---|
| HW-24 | Tab switching in an open menu on macOS 14, 15, 26 and 27:<br>• resize and highlight;<br>• a switch with a submenu open (no `cancelTracking`);<br>• `isEnabled = false` clicks;<br>• hover look in light, dark, Increase Contrast and Reduce Transparency;<br>• a 13″ display at the largest text size, on the Displays tab with 3 external displays: switch away and back, with no stuck scroll arrows. |
| HW-25 | VoiceOver, Switch Control and Full Keyboard Access:<br>• the segments are reachable;<br>• ", needs attention" and ", on" are read;<br>• VO-Down after a switch reaches the new section;<br>• the Show … Tab items appear without a relaunch;<br>• the tab row with `isEnabled = false` vs `true`. |
| HW-26 | ⌘1–⌘3 in an open menu: does tracking end, and does the next open show the chosen tab? ⌘, and ⌘Q still fire. |
| HW-27 | Sliders and switch headers in a newly shown tab work without reopening. |
| HW-28 | The osascript admin dialog from a Developer ID-signed **and** an ad-hoc Snaptic, each disclaimed and not:<br>• requester name, icon and title;<br>• prompt text;<br>• Touch ID;<br>• Cancel → `err -128`;<br>• no Automation consent;<br>• Displays' dimming overlays move behind it. |
| HW-29 | Captured output of `notifyutil -g com.apple.system.thermalpressurelevel`, `pmset -g batt`, `pmset -g` and `ioreg -r -n IOPMrootDomain -d 1`, on Apple silicon and Intel, macOS 14, 15, 26 and 27. These are golden fixtures for the parsers. |
| HW-30 | Lid closed on battery:<br>(a) a Keep Display On session with no external display;<br>(b) `caffeinate -d` running in another app;<br>(c) one external display with Keep Display On.<br>Check that:<br>• the Mac stays awake;<br>• the built-in panel goes dark within 35 s in (a), and the external display stays on in (c);<br>• Apple menu › Sleep is greyed out;<br>• the panel wakes on lid open;<br>• the keyboard backlight is recorded;<br>• the indicator's lid glyph is recorded. |
| HW-31 | Watchdog behaviour:<br>• osascript returns within 1 s;<br>• `ps -p <pid> -o comm,ruid,uid` shows `sh 0 0`;<br>• it survives osascript's exit and a SIGTERM to osascript.<br>Each of these restores sleep (`pmset -g`):<br>• quit;<br>• `kill -9` of Snaptic;<br>• SIGSTOP of Snaptic for 30 s;<br>• the stop file;<br>• the cap;<br>• deleting the beacon in a tight loop (within 10 s);<br>• an induced script error;<br>• `sudo kill -TERM` of the watchdog. |
| HW-32 | Restart while on: `SleepDisabled` persists; the leftover rows appear in every menu with Awake turned off; Turn Sleep Back On… and Keep Sleep Off both work. |
| HW-33 | The battery floor restores sleep while Snaptic is SIGSTOPped. |
| HW-34 | The cap, the battery floor and heat, each ending with the lid closed on battery and no display: the Mac is asleep within 30 s (`pmset -g log`), including right after a cap end. |
| HW-35 | Watchdog cost: `powermetrics` wakeups at a 5 s period. |
| HW-36 | Updates (Part E):<br>• Sparkle loads in a Developer ID build;<br>• update 0.3.1 → 0.3.2 from a user-owned and from a root-owned copy;<br>• Accessibility and Screen Recording survive;<br>• no Gatekeeper prompt after relaunch;<br>• an update is refused with a wrong EdDSA signature and with a non-Developer-ID build;<br>• deferral works while lid-closed mode is on and while a display trial is pending. |
| HW-37 | An ad-hoc local build (`build-app.sh` without an identity) launches without Sparkle, and Check for Updates… opens the Releases page. |

## Part D: Teams, file ownership and order

### Step 0 (lead, on `feature/v031`)

1. **This plan's final revision.**
2. **`stubs.tsv` rows for every new file:**
   - sources: `MenuTabBar`, `LidWatchdog`, `AwakeLidGate`, `AwakeLidPolicy`, `LidClosedController`, `LidRecovery`, `UpdaterController`, `UpdatePolicy`;
   - tests: `LidWatchdogTests`, `AwakeLidGateTests`, `AwakeLidPolicyTests`, `MenuTabsTests` (or `MenuLayoutTests`), `UpdatePolicyTests`.
3. **Every signature change in the shared files**, with safe-return stub bodies (`[]`, `nil`, `.off`, `false`, `StubError.notBuilt`). `fatalError` is banned by lint rule 13.
   - Menu: `AwakeMenuStyle`, `menuSection(tabbed:)`, `menuAttention`, and the new `AwakeMenuRow` cases.
   - Session model: `AwakeRefusal.lidClosedSession`, `AwakeEndReason.lidEnded`, `AwakeLidMode`, `AwakeLidEnd` and `AwakeLidFailStage`.
   - Runtime state:
     - `AwakeRuntimeState.lidMode`, `lastLidEnd` and `lidClosed`;
     - `AwakeSession.lidRequested`;
     - `AwakeArbiterInput.lidShut`, with the default `false`.
   - `AwakeStatusFacts.lidClosed`.
   - `HelperSpawner.spawnAdminScript` and `spawnTool`.
   - `OtherAssertionsReader.sleepDisabledPreference()`.
   - **Host interfaces** that StatusMenu reads:
     - `ModuleHost.lidRecovery: LidRecoveryState` (the leftover rows);
     - `AwakeHost.lidModeOn` (the N11 suffix);
     - `ModuleHost.updater: UpdaterControlling?` (Part E).
4. **Every A6, B7 and E7 control**, each with a stub use. The `ControlRegistry` changes (`ControlKind.menuTabBar` and the new `ControlState`s), `SettingsIndex`, every `Controls/*` table and `ControlRegistryTests` are the lead's in Step 0, then frozen.
5. **Lint changes:** rule 12, L16 and L18, plus the E6 rules.

### Step 1 (in parallel; one owner per file)

| Team | Owns |
|---|---|
| **T-menu** | `StatusMenu.swift`, `MenuKit.swift`, `MenuTabBar.swift`, `MenuLayout.swift` and its tests, `ModuleContracts.swift`, Window Switcher's and Displays' `menuAttention` and `menuSection(tabbed:)` (in their module files), `MenuBarPage.swift` |
| **T-lid-kit** | `LidWatchdog.swift`, `AwakeLidGate.swift`, `AwakeLidPolicy.swift` and their tests; `AwakePresentation.swift` and its tests (including the `tab` style: T-menu sends requests); `AwakeSession.swift`, `AwakeSessionPolicy.swift`, `AwakeCommandGrammar.swift`, `AwakeHistory.swift`, `AwakeLogEvent.swift`, `AwakeArbiter.swift` and its tests, `ConfigAwake*.swift`, `KitBackup.swift`, `AwakeFeatureGraph.swift`, `OtherAssertions.swift`, `ConfigFixtures.swift`, and the Kit tests for all of these |
| **T-lid-app** | `LidClosedController.swift`, `LidRecovery.swift`, `HelperSpawner.swift`, `SNProcess.*` / `SNSpawn.*` (if needed), `SessionController.swift`, `AwakeAutomation.swift`, `AwakeMenuRows.swift`, `IndicatorController.swift`, `AwakeModule.swift` (including `menuSection(tabbed:)`), `AwakeRuntimeState.swift`, `AwakeContext.swift` / `AwakeContracts.swift`, `AwakeAdvancedSheet.swift`, `AwakeStatusSection.swift`, `AwakePage.swift`, `CustomSessionPanel.swift`, `OtherAssertionsReader.swift`, `OtherAssertionsSection.swift`, `SystemEventsMonitor.swift`, `ActivitySimulator.swift` (only if HW-30 needs it), `HistoryController.swift`, `AwakeHistoryPage.swift`, `AwakeDiagnostics.swift`, `AppDelegate.swift`, `EmergencyActions.swift`, and the Kit Permissions copy file (the bundle strings) |
| **T-update** | Part E: `UpdaterController.swift`, `UpdatePolicy.swift` and its tests, `Package.swift`, `scripts/build-app.sh`, `scripts/make-dmg.sh`, `.github/workflows/build.yml`, `Resources/Info.plist`, `AboutPage.swift`, `GeneralPages.swift` (Updates section), `Relauncher.swift` (deferral hook) |
| **T-docs** | `README.md`, `site/index.html`, `THIRD_PARTY_NOTICES.md`, the design-spec amendments, and the release notes |

### Step 2

1. Merge, then CI and `lint --strict`.
2. At least four adversarial review rounds on the code: security (lid **and** updates), Awake correctness, menu UX and accessibility, and code and consistency. Each round is followed by fixes.
3. 0.3.1 in Info.plist, open a PR into main for the owner, no tags.
4. The owner adds the `release` environment secrets (E3). The first signed release is cut by the owner's tag.

---

## Part E: In-app updates (Sparkle 2, Developer ID)

### E1. What the user sees

- **Snaptic › Check for Updates…** (the existing item) and **Settings › General › Updates** (new section):
  - `ToggleSetting(L("Check for updates automatically"), help: L("Once a day, Snaptic asks GitHub whether a newer version is out. It sends nothing else."))`;
  - `ToggleSetting(L("Download and install updates automatically"), help: L("Updates install when you quit Snaptic, or when you choose Install and Relaunch."))`, a dependent row shown when the first is on;
  - a status row "Version 0.3.1 · Last checked today at 9:12 AM".
- **First run of 0.3.1.** Sparkle's standard permission request ("Check for updates automatically?") appears on the second launch. `SUEnableAutomaticChecks` is left unset, so the user chooses: network use needs consent.
- **Update found.** Sparkle's standard window shows the release notes (from the GitHub release) with **Install and Relaunch**, **Remind Me Later** and **Skip This Version**.
- **Root-owned copies** (`INSTALL=1`, or chown'd): macOS asks for an administrator password to install. That is Sparkle's own installer prompt.
- **Ad-hoc builds** (from source, no Developer ID): Sparkle isn't included. Check for Updates… opens the Releases page, as in 0.3, and the Updates section says "Updates are available in builds from GitHub Releases."

### E2. Signing, notarization and the one-time permission reset

**Release builds**
- They are signed with the owner's **Developer ID Application** certificate and the hardened runtime, with secure timestamps. No entitlements are added (library validation stays on: Sparkle and Snaptic share the Team ID).
- They are notarized with `notarytool` (App Store Connect API key), and both the `.app` and the `.dmg` are stapled.

**Designated requirement.** It becomes Team ID based, so Accessibility and Screen Recording grants **survive updates**.
- `HelperSpawner` already derives its child requirement from `designatedRequirementOfSelf()` (HelperSpawner.swift:456), so helpers keep working unchanged.
- **One-time reset.** 0.3.0 (ad hoc) → 0.3.1 (Developer ID) resets those grants once, because the requirement changes. The release notes and the Permissions page say so, and the existing launched-before heuristic (KitHostUI.swift:28-30) shows the re-grant guidance.

**Local builds**
- `build-app.sh` without `SIGN_IDENTITY` stays ad hoc and **doesn't embed Sparkle**, because library validation would refuse an ad-hoc framework.
- With `SIGN_IDENTITY="Developer ID Application: …"`, it embeds and signs Sparkle.

**Gatekeeper.** Release notes, the README and the site drop the "Open Anyway" steps for release builds. They stay for source builds.

### E3. Release pipeline (`.github/workflows/build.yml`)

**`build`** (unchanged trigger)
- It builds the universal app as today.
- New: it embeds `Sparkle.framework`, from the SwiftPM binary target at a pinned version ≥ 2.9.6 (2.10.0 at writing), in `Contents/Frameworks`.
  - The XPC services are removed, because Snaptic isn't sandboxed.
  - The rpath `@executable_path/../Frameworks` is checked with `otool -l`.
  - The framework keeps its symlinks.
- It signs ad hoc for tests.
- For pushes to main and tags, it uploads the **unsigned-for-release** bundle as artifact `Snaptic-unsigned`.
- The tests run with Sparkle present and ad-hoc signed only if they don't load it. Otherwise the test host is built without it (decided in Step 0, verified by CI).

**New `sign` job.** It runs on `macos-15` under the `release` environment (only `main` and `v*`, with the owner's required reviewers optional) and **never runs repository code**.

- **Inputs and order.** It downloads `Snaptic-unsigned` and creates a temporary keychain from `DEVELOPER_ID_P12_BASE64` and `DEVELOPER_ID_P12_PASSWORD`. Then it signs inside-out, each with `codesign --force --options runtime --timestamp --sign "$IDENTITY"`, all commands inline in the YAML:
  1. `Sparkle.framework/Versions/B/Autoupdate`
  2. `Updater.app`
  3. the framework
  4. Snaptic's own helpers, if any are separate (none today)
  5. the app
- **Checks after signing.** `codesign --verify --strict --deep` and `spctl -a -vv`.
- **Notarize and staple.** It notarizes the zip with `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` and `NOTARY_KEY_P8`, then staples the app and re-zips with `ditto -c -k --keepParent`. It builds the DMG with the same `hdiutil` steps as `make-dmg.sh`, inlined, then notarizes and staples the DMG.
- **Version check.**
  - It fails unless the tag `vX.Y.Z` equals `CFBundleShortVersionString`.
  - It fails unless `CFBundleVersion` is an integer greater than the previous release's.
  - It reads the previous release's from the last published `appcast.xml`, or uses 0 when there is none.
- **Output.** It uploads artifact `Snaptic` (signed zip + dmg).
- **Keychain.** The temporary keychain is deleted in an `always()` step.

**`attest`.** It now `needs: sign` and attests the **signed** `Snaptic.zip` and `Snaptic.dmg`.

**`release`** (ubuntu, `release` environment, never runs repository code)
- It downloads `Snaptic`.
- It computes the Ed25519 signature of `Snaptic.zip` with `openssl pkeyutl -sign -rawin` from the `SPARKLE_ED_PRIVATE_KEY` seed. The seed is wrapped in a PKCS#8 DER prefix, inline; this is byte-identical to Sparkle's `sign_update` (briefs/updates.md §EdDSA).
- It writes `appcast.xml` with an inline heredoc, one `<item>` per release, carrying:
  - `sparkle:version` = `CFBundleVersion`;
  - `sparkle:shortVersionString`;
  - `sparkle:minimumSystemVersion` = `14.0.0`;
  - `pubDate`;
  - `sparkle:releaseNotesLink` = the release's HTML URL;
  - an enclosure `url` = the **versioned** `releases/download/vX.Y.Z/Snaptic.zip`, with `length`, `type="application/octet-stream"` and `sparkle:edSignature`.

  The new item is prepended to the previous release's appcast, which is downloaded with `gh`, keeping the last 10 items.
- It uploads `Snaptic.zip`, `Snaptic.dmg` and `appcast.xml` (`--clobber`) to the release, which it creates or finds as today.

**Feed URL.** `SUFeedURL = https://github.com/revylfitness/snaptic/releases/latest/download/appcast.xml`. Sparkle follows GitHub's redirects. "latest" is the newest non-prerelease, so a prerelease never reaches users.

**Secrets.** They are environment secrets in `release`, never repository secrets:
- `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`;
- `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_P8`;
- `SPARKLE_ED_PRIVATE_KEY`.

The owner generates the EdDSA key on their Mac with Sparkle's `generate_keys`. Only the public key goes into Info.plist (`SUPublicEDKey`).

**PRs from forks** never see these secrets, and the `build` job that runs PR code never has them.

### E4. App integration

**`Core/UpdaterController.swift`** (T-update) wraps `SPUStandardUpdaterController`.
- It is created only in GUI mode, never in helper or CLI processes. `SnapticEntry` modes decide this.
- It is compiled under `#if canImport(Sparkle)`, and Sparkle is **weak-linked** (`-weak_framework Sparkle`). An ad-hoc build without the framework then runs, and `ModuleHost.updater` is nil.

**Info.plist:** `SUFeedURL`, `SUPublicEDKey`, `SUEnableSystemProfiling = NO` and `SUScheduledCheckInterval = 86400`. `SUEnableAutomaticChecks` and `SUAutomaticallyUpdate` are not set: they are user choices (E1). `CFBundleVersion` becomes an integer build number that increases with every release; 0.3.1 = 301.

**Deferring.** `UpdatePolicy` (Kit, pure) decides when an install or relaunch may happen. The delegate methods `updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)` and `updaterShouldRelaunchApplication` return true, or postpone, until it says go. An install waits while any of these is true:
- lid-closed mode is on (B4);
- a Displays change is waiting for "Keep this change?" (`DisplayTransactionQueue.hasPendingTrial`), or the queue is busy;
- Safe Mode is active, in which case updates are paused entirely;
- an Awake hold from the CLI is active, which waits up to 1 h, then installs at quit.

When it waits, the Updates row says "Will install when lid-closed mode ends."

**Relaunch.** Snaptic's own `Relauncher` (which opens the new copy before the old one quits) is **not** used for updates. Sparkle's `Updater.app` relaunches. `Relauncher` gains a guard: if `updater?.isInstalling`, it does nothing.

**Before quitting for an update,** Snaptic runs its normal shutdown: it ends Awake sessions (the snapshot is kept for resume), reverts pending display trials, and stops helpers. Sparkle quits the app through `NSApp.terminate`, so `applicationWillTerminate` runs as today.

**Caches and defaults.** `~/Library/Caches/app.snaptic.Snaptic/org.sparkle-project.Sparkle` and Sparkle's `SU*` defaults keys are listed in the README's "What Snaptic stores". General › Reset clears the `SU*` keys, and backups exclude them.

### E5. Network and privacy promise

The README's "No network" section (l.576) becomes "**One network connection, for updates.**":
- If you allow it, Snaptic contacts github.com once a day, and when you choose Check for Updates….
- It downloads `appcast.xml`, and an update when you install one.
- It sends no data of its own; Sparkle's system profiling is off. GitHub sees your IP address, a Sparkle User-Agent with the app version, and the macOS version.
- Every update is verified twice before installing: an Ed25519 signature from Snaptic's release key, and Apple's Developer ID and notarization.
- Nothing else connects, and a lint check still rejects networking APIs in Snaptic's own code (`URLSession`, `NWConnection`, `Network`). Sparkle's networking lives inside its framework.

Other places that change:
- README lines 576, 660 and 687;
- site lines 502 and 736;
- AboutPage.swift lines 36 and 56;
- THIRD_PARTY_NOTICES.md line 7, which also gains the Sparkle MIT license and copyright.

The "leaves nothing behind" line (README:155) gains "except Sparkle’s update cache".

### E6. Lint

- The banned networking patterns are unchanged. Sparkle is a binary dependency outside `Sources/`.
- A new rule, **L19**:
  - `import Sparkle` and `SPU`/`SU` symbols are allowed only in `Core/UpdaterController.swift`;
  - `Package.swift` may declare exactly one dependency, `sparkle-project/Sparkle`, pinned with `exact:`;
  - `Package.resolved` is committed;
  - `kit-linux` doesn't fetch it, because the dependency is declared under `#if os(macOS)`.
- `build-app.sh` keeps its "Never add entitlements that weaken it" check. CI asserts that the signed app has no entitlements: `codesign -d --entitlements - | grep -c key` is 0.

### E7. Controls

| Table | Id | Kind | Notes |
|---|---|---|---|
| `GeneralPageControls` | `general.updates.autoCheck` | `.setting` | `keys: ["SUEnableAutomaticChecks"]`, listed as external defaults in `ControlLegacy.internalKeys`; search "updates", "sparkle", "check for updates" |
| | `general.updates.autoInstall` | `.setting` | `.parentOn(ControlID("general.updates.autoCheck"))` |
| | `general.updates.checkNow` | `.button` | |
| Menu table (existing "Check for Updates…" item) | — | — | Keeps its id; its action becomes `updater?.checkForUpdates() ?? openReleasesPage()` |

### E8. Risks the owner accepts

- **The EdDSA key can't be rotated without a Developer ID.** With one, it can: Sparkle allows key rotation when the code signature matches. A leaked key plus a stolen Developer ID would be needed to push a malicious update. Either one alone isn't enough, because Sparkle requires the update to be Developer ID-signed by the same team once the host is.
- **A lost key** means users must download the next version by hand once.
- **Sparkle runs `Autoupdate` and `Updater.app` processes outside `HelperSpawner`.** For root-owned copies, its installer runs briefly as root after the admin prompt. The README's process list says so.

---

## §R. r1 findings and their disposition

| Finding | Disposition |
|---|---|
| sec B1, code B2 (no EXIT trap, `$((N-))`, `sd` fails to 0, no app liveness) | B3.2 EXIT trap with `WESET`; `num` guards; three-valued `sd` that never treats unreadable as 0; B3.3 liveness checks |
| code B1 (`$SCRIPT` undefined, two quoting layers) | B3.2 command built with `Q` plus AppleScript escaping; B5 round-trip test |
| parity B1 (`displaysleepnow` defeated by our own assertion) | B3.3 `maySleep` while the lid is shut, app-side `IORequestIdle` every tick, wake on open; root does no display work; HW-30 |
| parity B2 (Mac keeps running after the end with the lid shut) | B3.2 `cleanup` runs `sleepnow` when the lid is shut; B3.3 ends the session too; HW-34 |
| sec M1 (writable bundle → refuse) | Kept as a warning, with the reasoning in B6 (the same dialog is available to any same-user app). Translocated copies are refused. |
| sec M2 (absolute paths, L17 matches nothing) | Absolute paths throughout; L18 matches the real literals |
| sec M3 (environment) | Minimal environment for the spawn; the script resets `IFS`, `PATH`, `ENV`, `BASH_ENV` and `CDPATH` |
| sec M4 (dialog names osascript) | B1 and B6 say so; HW-28 |
| sec M5 (lint pins) | L18 also covers `osascript`, `nohup`, `AdminScript(`, and the callers of `spawnAdminScript` |
| code M1 (24 h cap fails validation) | Cap passed in seconds, up to 72 h; the script adds 60 s |
| code M2, sec m6 (no state machine, late password) | B3.0 states, single flight, token checks; the stop file is written on every failed exit and checked before the start |
| code M3 (Cancel vs failure, wait pattern) | `try … on error` wrapper, stdout result, `parseResult`, exit source, pid-only SIGTERM, identity check of osascript |
| code M4 (App Nap starves the heartbeat) | Background timer, `mainAgeMillis` gate, `beginActivity` |
| code M5, design M8 (recovery behind Awake; two watchdogs) | B3.4 host-level `LidRecovery`; single-slot journal; turning on refused while a journal is pending |
| code M6 (full rows in tabs not wired) | A4 `AwakeMenuStyle` and `menuSection(tabbed:)` |
| code M7, design M2 (⌘n path) | A3: positional, in the footer, `menuHasKeyEquivalent`, menu closes and the slot is marked dirty, shown when VoiceOver is on, discoverable |
| code M8, design M3, parity M5 (controls, config, feature, backup) | B5 config and feature rewrite; B7 control table; menu row cases in B1 |
| code M9 (team split) | Part D Step 0 and the file-ownership table |
| design M1 (⌘, changes) | Reverted: unchanged |
| design M4, M5 (placement, copy) | Moved to Advanced; sentence case; "an administrator password"; one floor |
| design M6, parity m8 (names) | B0 table and the checkmark state |
| design M7, parity M2 (Cancel leaves a session) | The session starts only after verify; a CLI session is replaced with a toast |
| design M9 (bundle warning wording) | Permissions-page wording and conditions |
| design M10 (README) | B6 line list, anchors, UI strings vs comments |
| design M11, code m2 (L16 naming) | Three names in B2 |
| parity M1 (Low Power Mode) | No longer blocks or ends the mode |
| parity M3 (indefinite + 8 h) | Idle submenu of presets plus Custom… |
| parity M4 (replacement drops the mode) | The gate keeps it for a direct-UI replacement |
| parity M6 (tabs hide warnings) | Attention marks, active mark, host-level leftover rows above the tabs |
| parity M7 (silent end) | `AwakeLidEnd`, a 12 h header line, History `lidEnd` |
| design m1 (single-module header) | Kept as in 0.3 |
| design m2 (labels) | `.fit` before short names; full accessibility labels |
| design m3 (highlight fill) | Not a `MenuRowView`; disabled if clicks still work |
| design m4–m6, m8 | A2 and A3 text; DS amendments |
| design m7 (reset) | No reset clears the tab |
| design m9, code m1 (L17 collision) | Renamed L18 |
| design m10 (N20) | Renamed N19 |
| design m11 (HW numbering) | HW-24…35 |
| design m12–m13, m21 (strings) | Canonical strings with ’ throughout B0–B3 |
| design m14 (button) | Pull-down items instead |
| design m15 (nullable lid read) | `.hardware(.battery)` for the controls; feature availability for the menu |
| design m16 (Custom… toggle) | B1 |
| design m17, parity m5 (header line priority) | The lid line is the first extra |
| design m18 (CLI line) | Appended field |
| design m19 (History) | B1 |
| design m20, parity m4 (visibility) | Indicator badge, N11 suffix |
| design m22 (scroll case) | HW-24 |
| parity m1 (opt-in hidden) | `lidRoute` points to Advanced |
| parity m2 (two floors) | One derived floor |
| parity m3 (72 h) | Cap options up to 72 h |
| parity m6 (`lidWillSleep` ignores SleepDisabled) | Warning rule includes `!lidModeOn` |
| parity m7 (resume) | The gate ends the mode on resume, with a header line |
| parity m9 (upgrade item, copy) | Moved to the Displays tab; Menu Bar copy says "set to Show in Snaptic Menu" |
| sec m1, m5 (parse fails toward off; non-integers) | `num` guards; three-valued `sd` |
| sec m2 (detach) | `nohup` with redirects, pid-only signals, HW-31 |
| sec m3 (fake journal prompts) | A prompt only while `SleepDisabled` reads 1; no journal field ever reaches root |
| sec m4 (`kill -0` as root) | Comment says it is a liveness hint; the beacon is the bound |
| code m3 (EmergencyActions runs off main) | B3.3 |
| code m4 (stale ⌘, page) | Moot: ⌘, is unchanged |
| code m5 (width) | Widest tab measured at build |
| code m6 (empty sections, marker range) | `sectionItems` and "Nothing to Show" |
| code m7 (submenu open) | Cancel tracking first; HW-24 |
| code m8 (`sectionHeader` unused) | Still used by single-module menus |
| code m9 (MenuKit factory) | `MenuKit.tabBar` |
| code m10 (silent validation) | Foreground `check` step |
| code m11 (`ioreg` cost) | `-n IOPMrootDomain -d 1`; HW-35 |
| code m12 (`displaysleepnow` hits externals) | App-side only, and only with no external display |
| code m13 (real uid) | HW-31 |
| code m14 (accuracy points) | Fixed in A2, B3.1 (preference accessor), B1 (History meaning) and B5 (enum payloads); the trailing slash is trimmed |

---

## §R2. r2 findings and their disposition

| Finding | Disposition |
|---|---|
| sec B1, code NB1 (`&` backgrounds the `&&` list) | B3.2: three-line command; CI shell test; HW-31 |
| code NM1 (Swift literal; tab in `IFS`) | Raw literal; `unset IFS`; no-control-bytes test |
| code NM2 (`IODisplayWrangler` missing on Apple silicon) | `pmset displaysleepnow` run as the user through `spawnTool` (B3.3) |
| code NM3 (`declareUserActivity`) | Dropped. Opening the lid wakes the panel; `ActivitySimulator.wakeDisplayOnce()` is the fallback |
| code NM4 (`proc_pidinfo` on a root pid) | `SNProcess.instanceID` |
| code NM5, sec M3 (preference only; `sleepnow` race; loose parse) | `ksd` kernel read; scoped `sd`; post-set check; "not ours" needs both sources twice; `cleanup` waits for the kernel |
| code NM6 (Step 0) | Safe-return stubs; ownership additions; host interfaces; `lidShut` default |
| sec M1 (bundle advice) | README advice is conditional on a root-owned install; a warning under the setting; the chown fix |
| sec M2 (hotkey keep) | Keep only for menu and Settings; a hotkey replacement ends the mode |
| parity M1 (external display dimmed) | `lidShut` requires no external display; HW-30 (c) |
| parity M2 (no keep-off) | Keep Sleep Off; Not Now hides everywhere until the next launch; leftover refusal text |
| design N1 (upgrade item unreachable) | Stays in the footer |
| design N2 (segment images) | DS exception for attention only; no active image; equal widths first |
| design N3 (control kinds) | B7 rewritten |
| design N4 (preset ellipses) | Presets carry "…"; the note row is gone |
| design N5, parity m2 (pending text, feedback) | Text per state; "Turning on…" toast after 2 s |
| design N6 (footer) | B1 footer rewritten |
| design N7 (refusals) | B2 table |
| design N8 (missing strings) | Leftover toast; `.lidEnded` text; Not Now scope |
| design N9 (replace toast) | "Replaced the running session." |
| design N10 (translocated text) | Kit sibling string |
| design N11 (indicator badge) | `lidActiveSymbol` per family, or a composited bar; HW-30 |
| design N12 (singular hours) | `AwakeCountdown.unit`; the cap is a fixed 24 h, but the rule stays |
| design N13 ("at … at") | "Ended at …: …" pattern |
| design N14 (`lidRoute`) | Three Kit variants |
| design N15 (Menu Bar copy) | A3 footer text; no summary change |
| design N16 ("checkbox") | Fixed |
| design N17 (FKA, Switch Control) | A3 shows the items for VoiceOver, Switch Control and FKA, with a live refresh |
| parity m1 (cap warning) | 5-minute toast |
| parity m3 (warning for everyone) | Help text shown only while on, with the chown fix |
| parity m4 (paused) | Attention excludes other-app pauses |
| parity m5 (supersede) | B3.0 |
| parity m6 (where to use it) | Toggle help text |
| parity m7 (HW external) | HW-30 (c) |
| parity m8 (note row) | Removed |
| parity m9 (quit line after restart) | Left out when the leftover rows explain it |
| parity cuts 1–3 | Fixed 24 h cap (no picker or config); History flag only; CLI JSON only |
| sec m1 (C-string lifetime) | `LidStopPath` class |
| sec m2 (fd race) | fd closed in the timer's cancel handler |
| sec m3 (pid bounds) | `parseResult` bounds; uid 0 and start-time check |
| sec m4 (TERM and the foreground sleep; shutdown `sleepnow`) | `sleep & wait`; `HALT` flag |
| sec m5 (stale clamshell key) | Wait for the kernel, then re-read up to 3 s |
| sec m6 (`MODE`) | Validated |
| sec m7 (L18 gaps) | `do shell script`, the requirement, and definition exemptions |
| sec m8 (disclaim) | Disclaimed by default; HW-28 |
| sec m9 (planted journal) | "may be from…" wording; README advice covers recovery |
| sec m10 (cap clock) | `capStart` never resets |
| code nm1 (`cancelTracking`) | Not called; HW-24 |
| code nm2 (scratch) | `removeAllItems`; cost stated |
| code nm3 (disabled item and VO) | Decided by HW-24 and HW-25 |
| code nm4 (`layoutChanged` element) | `tabBarView.window` |
| code nm5 (L16 self-hit) | `AwakeSession.swift` exempt |
| code nm6 ("status" kind) | B7 |
| code nm7 (requirement compile, responsibility, 4 KB) | B3.1 step 4 |
| code nm8 (VO state at build) | Live refresh |
| code nm9 (second TERM) | `cleanup` ignores TERM and INT |
| code nm10 (lid availability) | Synchronous IORegistry read; recomputed on wake |

