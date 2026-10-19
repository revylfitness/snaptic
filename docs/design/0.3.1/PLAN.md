# Snaptic 0.3.1 plan (r2)

## What 0.3.1 adds

0.3.1 adds two things:

1. **Tabs in the Snaptic menu.** When two or more modules share the Snaptic menu, it shows a row of tabs at the top, one per module. Only the selected module's items show below the tabs.
2. **Keeping awake with the lid closed.** This is an opt-in Awake mode, "lid-closed mode", that keeps a MacBook awake with its lid closed, including on battery with no external display. It asks for an administrator password each time it turns on.

The owner made the following decisions on 2026-10-19, and they are not reopened here:

- The tabs are a segmented control inside the native `NSMenu`, not a popover, and the menu remembers the last tab.
- Lid-closed mode asks for an administrator password each time. Nothing is installed and nothing persistent is granted. The two rejected options were a one-time helper install and a sudoers rule.

## Review history

- **r1 → r2:** four reviews (security, code, parity, design), recorded in `review-r1-*.md`. They found 5 Blockers, 32 Majors and 51 Minors.
- Every finding is handled in this revision. The disposition table is §R at the end.

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
│ More Display Features…  (Displays tab │
│                          only)        │
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
- Labels are module titles. If the full titles don't fit with `.fillEqually`, the control tries `.fit` distribution. Only if that also fails do the labels fall back to `ModuleID.shortTitle` ("Switcher", "Displays", "Awake").
- Each segment's accessibility label is always the full title. The tooltip is "<Title> (⌘n)".

**Attention and active marks**
- A segment whose module has something that needs attention shows a 10 pt `exclamationmark.circle` image next to its label, and VoiceOver adds ", needs attention". Modules report this through a new `menuAttention: Bool` on the module contract (A4):
  - Displays: degraded, paused, or helper stopped;
  - Window Switcher: Accessibility missing;
  - Awake: none of its own, because the leftover row is host-level.
- While Awake governs, the Awake segment shows the active glyph and VoiceOver adds ", on".
- Without this, a user who stays on one tab would never see another module's warnings, which would be a regression from 0.3's stacked menu.

**Awake's tab**
- Awake's tab shows the full Awake rows, style `tab`: the own-menu rows minus "Awake Settings…".
- The compact rows are used only when Awake is the single shared module, as in 0.3 §5.4.

**Remembering the tab**
- The tab is remembered across opens and relaunches.
- If the remembered module isn't in the menu, the first tab shows. The stored choice is kept, so it comes back when that module returns.

**Footer**
- The footer's "Snaptic Settings… ⌘," is unchanged: it restores the last-viewed Settings pane (DS §1.1, HIG).
- "More Display Features…" moves from the footer to the end of the Displays tab, or to the single-module Displays menu.

### A2. Building and switching

**The tab bar**
- `MenuKit.tabBar(labels:selected:attention:active:control:onSelect:)` is a factory beside `MenuKit.switchHeader`, so L6 needs no new exemption. It returns an item whose view is `MenuTabBarView`, defined in the new file `Core/MenuTabBar.swift`.
- The view is an `NSView` subclass, **not** a `MenuRowView`, so it never draws the selection fill. It hosts an `NSSegmentedControl` (`.selectOne`, `controlSize = .small`, inset by `MenuKit.rowInset`). The row is 28 pt tall.
- The item is `isEnabled = false` so arrow keys skip it, if HW-24 confirms the control still takes clicks. Otherwise the item stays enabled and `highlightDidChange` is a no-op.
- Accessibility label: "Menu tabs". Help: "Press Command-1 to Command-3 to switch tabs." (The range follows the tab count.)

**`StatusMenu.build(shared)` with tabs** builds these groups:
1. The host safety group: Safe Mode rows, then the B3.4 leftover rows.
2. The tab bar.
3. The selected section, from `module.menuSection(tabbed: true)` with `header: false`.
4. The footer.

StatusMenu keeps three references: `tabBarItem`, `sectionItems: [NSMenuItem]` (exactly the items it inserted for the section) and `footerSeparator`.

**Switching tabs** runs synchronously in the control's action. That action fires at the end of the control's own tracking, the same cell path as the shipping `NSSwitch` and `NSSlider` rows.
1. Store the choice (A5).
2. Close any open submenu. MenuKit submenus get a tiny delegate that records whether they are open, and if one is, StatusMenu calls `cancelTracking()` on it first (HW-24 case).
3. Remove exactly `sectionItems`.
4. Insert the new section's items after the tab bar's separator, adding or removing the trailing separator so groups stay single-separated. If the new section is empty (a module stopped while the menu is open), show the status row "Nothing to Show".
5. Post `NSAccessibility.post(element: <menu's window>, notification: .layoutChanged)`.

The switch uses no timers and no `RunLoop.main.perform` (N15, L14). The removed items are never under the pointer, so R2C c12 doesn't apply.

**Width**
- At build, StatusMenu measures every tab's section in a scratch `NSMenu` (`menu.size.width` after adding the items) and sets `minimumWidth = max(MenuKit.width, widest)`. Switching then never widens the open menu, and the segment never moves under the pointer.
- The scratch items are discarded. `menuSection(tabbed:)` must be cheap and free of side effects, and each module confirms this in Step 0.

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
- They are hidden (`isHidden = true`, `allowsKeyEquivalentWhenHidden = true`) unless VoiceOver is on (`NSWorkspace.shared.isVoiceOverEnabled` at build). With VoiceOver on, they show, so VoiceOver has a native path whatever HW-25 finds.
- `StatusMenu.menuHasKeyEquivalent` returns true with that item's target and action when `openMenus > 0` and the event is ⌘1–⌘n. Otherwise it returns false, as today.
- The item's action stores the choice and sets `shared.dirty = true`. It never changes the menu in place.
- The expected result is that **the menu closes and the next open shows the chosen tab**. If HW-26 finds that tracking continues, the action switches in place instead.

**Discoverability**
- The segment tooltips, the control's accessibility help, and the Menu Bar page footer: "With two or more modules set to Show in Snaptic Menu, the menu shows a tab for each. While it’s open, press ⌘1, ⌘2, or ⌘3 to switch tabs."
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
- `labelStyle(fullWidths:fitWidths:available:) -> .fillEqually | .fit | .short`.
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
- `menu.snaptic.upgrade` moves to the Displays tab, with the same id.

**Lint**
- No L6 change: the item is built in MenuKit.
- `MenuTabBar.swift` falls under the existing L13/L14 `Core/Menu*` globs.

**Docs.** T-docs owns all README text; T-menu supplies wording in its PR description. Pages to change:
- README "Menu Bar" (l.42-52) and "In the menu bar" (l.242-244).
- DS §3.3: new sketch.
- DS §3.4: the resize exception.
- `MenuBarPage` summary line, plus the ⌘n footer from A3.
- HW-15's row budget, restated as "the tallest single tab ≤ 24 lines in the default setup".

---

## Part B: Keep awake with the lid closed

### B0. Names, used everywhere

Design-spec §4.7 gets a terminology row: "closed-lid, clamshell, disablesleep and Power Protect are all called **keep awake with the lid closed**; the noun is **lid-closed mode**."

| Where | Text |
|---|---|
| Menu action (off) | "Keep Awake with the Lid Closed…" |
| Menu state (on) | "✓ Keep Awake with the Lid Closed". No ellipsis, because turning it off asks nothing. |
| Idle submenu | "Keep Awake with the Lid Closed ›" |
| Setting | "Keep awake with the lid closed" |
| Notices and README | "lid-closed mode" |
| VoiceOver | "Keeping your Mac awake with the lid closed." and "Lid-closed mode turned off." |
| Status and accessibility suffix | ", even with the lid closed" |

### B1. What the user sees

**Settings › Awake › Advanced…** gets a new section, "Lid closed". It follows the experimental pointer-nudge pattern (DS §1.5 places the lid option in Advanced, "with a warning about heat").

- **`ToggleSetting(L("Keep awake with the lid closed"), help: L("Only in sessions you start in Snaptic. Asks for an administrator password each time."))`**
  - It is backed by `features[.lidClosed]` (opt-in, off by default).
  - It shows only on Macs with a battery (`when: .hardware(.battery)`).
- **Dependent row**, shown when the toggle is on: `PickerSetting(L("Turn off after"))`.
  - Options: 1, 2, 4, 8, 12, 24, 48, 72 Hours. The default is 8 Hours.
- **Footer (two sentences):** "Your Mac can’t sleep for low battery or heat while this is on, so Snaptic turns it off at your battery limit (at least 10%) or when your Mac gets hot. Use it on a hard surface, not in a bag." It ends with a **Learn More…** link to README "Keeping awake with the lid closed".
- **One battery limit.** Lid-closed mode turns off at `max(10, Awake’s battery floor)`, or at 20% when Awake's battery floor is turned off. There is no second picker. (Insomnia also has a single floor.)
- **Bundle checks** reuse the Permissions page's conditions and wording. Both strings live in Kit next to the Permissions copy.
  - **Translocated copy:** lid-closed mode is unavailable, and the existing row "Move Snaptic to Applications first" shows.
  - **Writable by your account:** a warning row reads "Your account can change this copy of Snaptic, so another app could change it and misuse the password prompt. Learn More…". Lid-closed mode stays available; §B6 gives the reasoning (warn, not refuse).
- **On the main Awake page,** the existing `lidRoute` line becomes:
  - feature off: "To keep it awake with the lid closed, connect power and an external display, or turn on lid-closed mode in Advanced."
  - feature on: "…or choose Keep Awake with the Lid Closed."

**The Awake menu.** New Kit row cases are `.lidClosed(LidRowState)` and `.lidSubmenu([presets])`. They appear in all three styles: own, compact and tab.

- **Idle**, when the feature is available: **"Keep Awake with the Lid Closed ›"** goes directly after the start-default row.
  - Its first row is the disabled note "Asks for an Administrator Password".
  - Then come the presets, in preset order.
  - Then a separator and "Custom…", which opens the panel with the lid checkbox ticked.
  - Choosing a preset asks for the password, and **starts the session only after lid-closed mode is verified on** (B3). Cancelling starts nothing.
- **Active, with a session you started in Snaptic** (source menu, settings or hotkey in this process): "Keep Awake with the Lid Closed…" goes directly after "✓ Keep Display On".
  - Choosing it asks for the password and adds the mode to the running session.
  - While the mode is on, the row reads "✓ Keep Awake with the Lid Closed". Choosing it turns the mode off with no password.
- **Active, with a session from the command line, at launch, or restored:** the idle submenu shows instead. Choosing a preset replaces that session once the mode is verified on, and the success toast says "Replaced the command-line session."
- **Holds or a rule governing:** the submenu shows. A new manual session takes over as usual.
- **While the password dialog is up:** every lid row shows "Waiting for Password…" and is disabled.

**Custom… panel** (only in Start mode, not in Add Time…):
- `ToggleSetting(L("Keep awake with the lid closed"), help: L("Asks for an administrator password when you click Start."))`.
- While it is on, the button reads "Start…".

**Awake status section (Settings):** the existing "Keep Awake" (idle) and "Options" (active) pull-downs gain the same items (B0 titles). There is no new button.

**The password dialog.** macOS's own authorization dialog shows, via `/usr/bin/osascript`. The requester is shown as osascript, not Snaptic (HW-28 records exactly what it shows). The prompt text is built in Kit by `LidWatchdog.promptText(floor:capHours:)`:

> Snaptic wants to keep your Mac awake with the lid closed for up to 8 hours. Sleep turns back on when the session ends, when Snaptic quits, at 20% battery, or if your Mac gets hot. Enter an administrator password to allow this.

Touch ID is likely to work, because osascript is signed by Apple (research §4); HW-28 checks.

**Status everywhere**
- **Menu header and Settings status row.**
  - While the mode is on, the lid line is the **first** extra.
  - It reads "Stays awake with the lid closed" when the session ends first. When the cap ends first, it reads "Stays awake with the lid closed until 6:40 PM".
- **Lid warning.** It becomes `lidWillSleep == true && !lidModeOn && (onBattery || !external)` (a Kit test covers it). It re-evaluates on `$lidWillSleep`, on screen changes, and on `$lidMode`.
- **Indicator.**
  - While the mode is on, the active glyph gets a small badge variant (`IndicatorController`), and the accessibility label and tooltip add ", even with the lid closed".
  - The shared Snaptic glyph's N11 label gets the same suffix.
- **The last lid end** shows in the header and status row for 12 h. Examples: "Lid-closed mode turned off at 20% battery at 3:12 AM." and "…because your Mac got hot at 3:12 AM." It is cleared at the next turn-on.
- **History.** Entries gain `lidClosed` (true if the mode was on at any point) and `lidEnd` (lossy). The row subtitle gets " · Lid closed". The Start Again tooltip says "Starts without lid-closed mode."
- **CLI.** `snaptic awake status` gets a last JSON key `lidClosed` (true/false), and the tab-separated line gets a last field: `lid` or `-`.

### B2. Who can turn it on: N19, the lid gate (extends N10)

**Who can request it.** Only a direct user action in Snaptic's UI, in this process. That means a menu click, the Custom… panel, or a Settings pull-down item (Settings starts check `SettingsShell.mayStart()`).

**What can never request it.** None of these: the CLI, the control socket, rules, holds, start-at-launch, restore or resume, History "Start Again", hotkeys (including preset slots), backups, presets, or `defaultOptions`. Lid-closed mode is not an `AwakeSessionOptions` field, so no persisted path can carry it.

**How it is stored and who owns it.** There are three names:

| Name | What it is | Owner |
|---|---|---|
| `AwakeSession.lidRequested: Bool` | The session's runtime flag. It is not in CodingKeys and is reset in `init(from:)` and `sanitized(now:)`, exactly like `overrideGuards`. | Set only by `SessionController`. L16 is extended with the pattern `\.lidRequested\s*=(?!=)` outside `SessionController.swift`. |
| `AwakeRuntimeState.lidMode: AwakeLidMode` | The state machine's published state (B3.0). | Assigned only in `LidClosedController.swift` (a second L16 clause). |
| `lidClosed` | The field name in the CLI JSON and in History. | — |

LidClosedController asks SessionController to set or clear `lidRequested` with `setLidRequested(_:for sessionID:)`, and gets a callback when the session ends.

**`AwakeLidGate` (Kit, pure, exhaustively tested)** is a truth table `(source, event) -> allowed | end | keep`:
- **Allowed** for `.menu` or `.settings` (with `mayStart`) on an idle Mac or a direct-UI session.
- **Keep** when the session is replaced by a direct UI start in this process (menu, Settings or hotkey). The watchdog is untouched, and `until` is recomputed as the earlier of the new session's end and the cap.
- **End** in all of these cases:
  - the session ends;
  - it is replaced by any other source;
  - a trigger or hold takes over;
  - the module stops, or Safe Mode starts;
  - the feature is turned off, or the kill switch `Awake.disable.lidClosed` is set;
  - restore or resume. The header then says "Lid-closed mode turned off when Snaptic quit."

**CLI.**
- `awake extend` is refused while lid-closed mode is on. The refusal is `.lidClosedSession` with exit code 4 and the text: "Lid-closed sessions can’t be extended from the command line. Use Add 1 Hour in the menu."
- `awake stop` works. Anything may turn sleep back **on**.

**Starting with guards in play.** Lid-closed mode refuses to start in these cases, each with a toast:

| Condition | Toast |
|---|---|
| Battery discharging and below `floor + 5` | "Lid-closed mode needs at least 25% battery." (the number is computed) |
| Thermal state `serious` or worse | "Your Mac is too warm for lid-closed mode right now." |
| The session is a Start Anyway session (`overrideGuards`) | "Lid-closed mode can’t start in a session started with Start Anyway." |
| The bundle is translocated | the B1 row's text |
| An earlier lid journal still exists (B3.4) | "Snaptic is finishing an earlier lid-closed session. Try again in a minute." |

Low Power Mode does **not** block lid-closed mode. It follows the session's `endOnLowPowerMode` like everything else, and the README recommends Low Power Mode with the lid closed. Lid-closed mode never offers Start Anyway.

### B3. Mechanism

**Components**

| Side | Files |
|---|---|
| App, user side | `Awake/Core/LidClosedController.swift`: the state machine, heartbeat, liveness checks and display handling. `Core/LidRecovery.swift`: host-level leftover recovery. |
| Spawning | `HelperSpawner.spawnAdminScript`. |
| Kit | `SnapticKit/LidWatchdog.swift`: script text, quoting, argument validation, result parsing and prompts. `AwakeLidGate.swift`. `AwakeLidPolicy.swift`: start refusals, floors, the cap clock, end classification and leftover classification. Presentation goes in `AwakePresentation.swift`. |
| Root side | A fixed `/bin/sh` script. Its only writes are `/usr/bin/pmset -a disablesleep 0|1` and `/usr/bin/pmset sleepnow`. |

#### B3.0 States (single flight)

`AwakeLidMode` has these states:
- `off`
- `authorizing(token)`
- `verifying(token, pid)`
- `on(token, pid, until)`
- `stopping(token)`
- `failed(reason)`, which shows for one toast and then returns to `off`.

How the state machine behaves:
- **One operation at a time.** In every state except `off` and `on`, all lid entry points are disabled and show "Waiting for Password…".
- **Token check after every await.** If the token has changed, or the session it belongs to has gone (unless the mode was keeping a session that hasn't started yet, see B3.1), the controller writes `stop-<token>` and moves to `stopping`.
- **Leaving `authorizing` or `verifying` other than into `on`** (cancel, timeout, error, verify failure, superseded) always does the same three things:
  1. writes `stop-<token>`;
  2. stops the heartbeat;
  3. keeps the journal until IORegistry `SleepDisabled` reads 0. If it still reads 1 after 30 s, the leftover row shows (B3.4).
- **App Nap.** While the state is anything other than `off`, the controller holds `ProcessInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Snaptic lid-closed mode")`.

#### B3.1 Turning on (LidClosedController)

1. **Preflight.**
   - Check the gate, the feature, the B2 refusals, and lid presence (feature availability: the sessions controller's `availability(of: .lidClosed)` is `.unavailable("No lid")` when `AppleClamshellState` is absent).
   - Read `SleepDisabled` from IORegistry (`IOPMrootDomain` property, the kernel's actual state) and from the preference (`OtherAssertionsReader.sleepDisabledPreference()`, a new synchronous accessor).
   - If either is already on, Snaptic doesn't touch it. The toast says "Sleep is already turned off for this Mac by another app or command, so it stays awake with the lid closed." The session starts or continues without lid-closed mode.
2. **Journal.** Single slot: `~/Library/Application Support/Snaptic/awake/lid.json`, mode 0600, written atomically, containing `{token, bootSessionUUID, startedAt (wall and continuous), pid: nil, capSeconds, floor}`. `token` is 128 random bits as 32 lowercase hex characters.
3. **Beacon directory.**
   - Path: `D = confstr(_CS_DARWIN_USER_TEMP_DIR)` with its trailing `/` trimmed, plus `/snaptic-lid`. Both sides use exactly this string; never a realpath.
   - Create `D` with mode 0700. Check with `lstat` that it is a directory, owned by our uid, mode 0700. If not, the toast is "Snaptic couldn’t turn on lid-closed mode. Try again." and the failure is logged as stage `beacon`.
   - Remove old `stop-*` and `beat-*` files.
   - Create `beat-<token>` with `open(O_CREAT|O_EXCL|O_NOFOLLOW|O_WRONLY, 0600)`.
4. **Spawn** with `HelperSpawner.spawnAdminScript(LidWatchdog.startScript(args, prompt:))`:
   - Suspended spawn of `LidWatchdog.osascriptPath` (`/usr/bin/osascript`) with `-e <source>`. Its stdout is a pipe (reusing `spawn`'s reply-pipe/`ReaderState` code with a 4 KB line cap). The environment is explicitly minimal: `PATH=/usr/bin:/bin`, `LANG=en_US.UTF-8`, nothing else.
   - Before SIGCONT, the child must satisfy `anchor apple and identifier "com.apple.osascript"` (`SNProcess.process(_:satisfies:)`).
   - Not disclaimed. Process exit is observed with a `DispatchSourceProcess` on main and `reapIfExited`, the house pattern; `waitUntilExit` stays banned.
   - After 120 s, the controller sends SIGTERM to **osascript's pid only**, never `signalGroup`, and treats the result as a timeout (B3.0 exit path).
   - `spawnAdminScript` does **not** require helper identity or `unavailableReason == nil`, because recovery must work while helpers are unavailable.
5. **Result.** `LidWatchdog.parseResult(stdout) -> .launched(pid) | .canceled | .failed(code)`. The AppleScript wraps the call in `try … on error number n` and always prints one line: `ok <pid>` or `err <n>`, where −128 means canceled.
   - Canceled: silent.
   - Code 3 from the `check` step: someone else holds sleep, so the "already turned off" toast shows.
   - Code 64: arguments, logged as stage `args`.
   - Anything else: "Snaptic couldn’t turn on lid-closed mode. Try again."
6. **Verify.** The controller records `pid` and its start time (`proc_pidinfo` `PROC_PIDTBSDINFO` `pbi_start_tvsec/usec`) in the journal. It then polls IORegistry `SleepDisabled` every 0.5 s for up to 10 s.
   - **If on:** the state becomes `on`.
     - For an idle start, the session starts now with `lidRequested = true` (source `.menu` or `.settings`).
     - If that start is refused (a guard), the controller goes straight to `stopping`, and the session's refusal toast shows.
     - VoiceOver hears "Keeping your Mac awake with the lid closed."
   - **If not on:** B3.0 exit path, with the failed toast.
7. **Five seconds later**, the controller re-reads `SleepDisabled`. If it reads 0 twice, the mode ends with `otherApp`: "Another app turned sleep back on, so lid-closed mode stopped." Insomnia saw a root daemon resetting the value every 2 s and does the same check.

#### B3.2 The root command and watchdog

**Command.** `LidWatchdog.command(args)` builds this line:

```
/bin/sh -c <Q(script)> snaptic-lid check <Q(a1)>…<Q(a6)> && /usr/bin/nohup /bin/sh -c <Q(script)> snaptic-lid run <Q(a1)>…<Q(a6)> </dev/null >/dev/null 2>&1 & echo $!
```

- `Q` is POSIX single-quoting: `'…'`, with each `'` written as `'\''`.
- `check` runs in the foreground, so argument and ownership failures surface as the exit code of `do shell script`.
- `appleScript(command:prompt:)` escapes `\` as `\\`, `"` as `\"`, and LF as `\n`, and refuses CR and every other control character.
- Arguments: `uid pid token capSeconds floor dir`, all validated in Kit by the same charset and range rules as the script.
  - `capSeconds` is 3,600…259,200 (72 h); the script adds 60 s.
  - `floor` is 10…50.

**Script** (`LidWatchdog.script`; T-lid-kit owns the exact text, and it is golden-tested):

```sh
IFS=' 	
'; PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH; unset ENV BASH_ENV CDPATH
umask 077; trap '' HUP
MODE=$1; U=$2; P=$3; T=$4; C=$5; F=$6; D=$7
num() { case "$1" in ''|*[!0-9]*) return 1;; esac; }
num "$U" && num "$P" && num "$C" && num "$F" || exit 64
case "$T" in *[!0-9a-f]*|'') exit 64;; esac; [ ${#T} -eq 32 ] || exit 64
case "$D" in /var/folders/*/snaptic-lid) ;; *) exit 64;; esac
case "$D" in *..*|*[!A-Za-z0-9_/+.-]*) exit 64;; esac
[ "$F" -ge 10 ] && [ "$F" -le 50 ] && [ "$C" -ge 3600 ] && [ "$C" -le 259200 ] || exit 64
C=$((C+60))
# sd: 1, 0 (line absent counts as 0), or ? (pmset failed); last match wins
sd() { O=$(/usr/bin/pmset -g 2>/dev/null) || { echo '?'; return; }
       printf '%s\n' "$O" | /usr/bin/awk '$1=="SleepDisabled"{v=$2} END{print (v==""?0:v)}'; }
owned() { [ -f "$1" ] && [ ! -L "$1" ] && [ "$(/usr/bin/stat -f %u "$1" 2>/dev/null)" = "$U" ]; }
lidshut() { /usr/sbin/ioreg -r -n IOPMrootDomain -d 1 | /usr/bin/awk '/"AppleClamshellState"/{print $NF; exit}'; }
lidsleeps() { /usr/sbin/ioreg -r -n IOPMrootDomain -d 1 | /usr/bin/awk '/"AppleClamshellCausesSleep"/{print $NF; exit}'; }
S=$(sd); [ "$S" = 0 ] || exit 3                         # someone else holds it, or unreadable: never take it
[ "$MODE" = check ] && exit 0
owned "$D/stop-$T" && exit 0                             # stopped before we started (late password)
WESET=0
cleanup() {
  [ "$WESET" = 1 ] || return
  i=0; while [ $i -lt 3 ]; do
    [ "$(sd)" = 0 ] && break
    /usr/bin/pmset -a disablesleep 0; /bin/sleep 1; i=$((i+1)); done
  [ "$(lidshut)" = Yes ] && [ "$(lidsleeps)" = Yes ] && /usr/bin/pmset sleepnow
}
trap 'cleanup' EXIT; trap 'exit 0' TERM INT
/usr/bin/pmset -a disablesleep 1; WESET=1
START=$(/bin/date +%s); Z=0; Q=0; LB=0
while :; do
  /bin/sleep 5
  N=$(/bin/date +%s); num "$N" || exit 0
  [ $((N-START)) -ge "$C" ] && exit 0                    # hard cap
  /bin/kill -0 "$P" 2>/dev/null || exit 0                # liveness hint only (any pid answers root)
  owned "$D/stop-$T" && exit 0                           # asked to stop
  owned "$D/beat-$T" || exit 0                           # beacon gone
  M=$(/usr/bin/stat -f %m "$D/beat-$T" 2>/dev/null); num "$M" || exit 0
  [ $((N-M)) -le 20 ] || exit 0                          # Snaptic hung: the beacon is the real bound
  S=$(sd)
  case "$S" in
    1) Z=0; Q=0;;
    0) Z=$((Z+1)); [ $Z -ge 2 ] && { WESET=0; exit 0; };;   # someone else reset it twice: not ours
    *) Q=$((Q+1)); [ $Q -ge 2 ] && exit 0;;
  esac
  B=$(/usr/bin/pmset -g batt 2>/dev/null)
  case "$B" in *discharging*)
    PC=$(printf '%s' "$B" | /usr/bin/sed -n 's/.*[^0-9]\([0-9][0-9]*\)%.*/\1/p' | /usr/bin/awk 'NR==1')
    if num "$PC"; then LB=0; [ "$PC" -le "$F" ] && exit 0
    else LB=$((LB+1)); [ $LB -ge 2 ] && exit 0; fi;; esac
  TP=$(/usr/bin/notifyutil -g com.apple.system.thermalpressurelevel 2>/dev/null | /usr/bin/awk '{print $2}')
  num "$TP" && [ "$TP" -ge 2 ] && exit 0                 # heavy or worse (= ProcessInfo .serious)
done
```

**What root does.**
- It writes only through `pmset -a disablesleep 0|1` and `pmset sleepnow`.
- The `sleepnow` runs only in `cleanup`, and only when the lid is shut and closing it would sleep the Mac. This is needed because the kernel doesn't re-check a closed lid when `SleepDisabled` clears (xnu IOPMrootDomain.cpp:8386-8389), so the Mac would otherwise keep running in the bag.
- It never writes, deletes, follows symlinks in, or reads the contents of user-controlled files. It only `stat`s them, checking owner, type and mtime.
- Root does no display work at all (B3.3).

**Every exit restores.**
- The EXIT trap runs `cleanup`, and TERM and INT exit through it.
- Every check that would otherwise trip an arithmetic error is guarded by `num`.
- Unreadable `pmset` output is never taken as "0": it counts toward a restore.
- The single deliberate non-restoring exit, "someone reset it twice", clears `WESET` first.

**Ownership.**
- `check` and the start both require `SleepDisabled = 0` (`exit 3` otherwise), so Snaptic never takes over another tool's setting.
- The restore runs only when `WESET = 1`.

**Late password.** If the user authenticates after the app's 120 s timeout, the app has already written `stop-<token>` (B3.0). The script checks for it before setting anything.

**Detachment.**
- `nohup` plus `&`, with stdin and stdout redirected.
- The app never signals osascript's process group.
- HW-31 checks:
  - the watchdog survives osascript's exit and a SIGTERM to osascript;
  - its real and effective uids are 0 and 0 (`ps -o ruid,uid`).
- If the real uid isn't 0, the user could kill it. Then the app-side liveness check (B3.3) is the guarantee, and the README threat model says so.

**Cost.** About 8 forks every 5 s. HW-31 measures wakeups with `powermetrics`. If they are significant, the period becomes 10 s and staleness 30 s.

#### B3.3 App side while on

**Heartbeat.**
- It runs on a private serial queue as a `DispatchSourceTimer` every 5 s with 0.5 s leeway. It is not on main, so App Nap's timer coalescing on main can't starve it.
- Each tick touches the beacon (`futimens` on an `O_NOFOLLOW` descriptor) **only if** `HostHeartbeat.shared.mainAgeMillis() < 10_000`. A hung main thread therefore still restores sleep within about 20 s, which is DisplayGuard's model (FIXES-R1 B5).
- Each tick also runs the liveness checks:
  - `kill(pid, 0)`: ESRCH means the watchdog is gone; EPERM or 0 means it is alive.
  - The process start time must match the one recorded at verify.
  - It reads IORegistry `SleepDisabled`.
- State changes hop to main with `DispatchQueue.main.async { MainActor.assumeIsolated … }` (rule 2).
- **Watchdog gone, or `SleepDisabled` reading 0 twice:** the mode ends (reason `watchdogLost` or `otherApp`). If `SleepDisabled` still reads 1 while the watchdog is gone, the leftover rows show (B3.4).

**Display while the lid is shut.**
- While the mode is on and the lid is closed (`SystemEventsMonitor.lidClosed == true`):
  - The session's **effective** display policy is `maySleep`, through a new `AwakeArbiterInput.lidShut`. Snaptic then holds no display assertion of its own; without this, Snaptic's own assertion would cancel the display sleep request.
  - On each heartbeat while the built-in panel is awake and no external display is attached, the app requests display sleep with `IORequestIdle` on `IODisplayWrangler`, app side with no root. It repeats every tick because powerd defers this request for about 30 s after a wake.
- When the lid opens, `AssertionManager.declareUserActivity()` wakes the panel. L1 keeps all assertions in AssertionManager.
- If Snaptic hangs with the lid shut, the panel may stay lit until the 20 s beacon restore puts the Mac to sleep.
- **Known limitations** (README):
  - Another app's display assertion (for example `caffeinate -d`) can keep the panel lit, and Other Apps lists it.
  - The keyboard backlight may stay on, because there is no public API to turn it off (Insomnia has the same limitation). HW-30 records both.

**Turning off** (any end path):
1. Create `stop-<token>` (`O_CREAT|O_NOFOLLOW`).
2. Stop the heartbeat.
3. Poll IORegistry `SleepDisabled` for up to 15 s.
   - It reads 0: clear the journal and go to `off`.
   - It still reads 1: show the leftover rows.

**Ends while the lid is shut.** When the mode ends for any reason other than the session's own end, while the lid is closed and `lidWillSleep == true`, the session ends too, with reason `.lidEnded`. The watchdog's `sleepnow` covers the hung-app case.

**Quit.**
- `applicationWillTerminate` writes the stop file synchronously.
- At turn-on, an `EmergencyActions` action is registered that captures the stop path as an immutable C string and does only `open(O_CREAT|O_EXCL|O_NOFOLLOW|O_WRONLY)` and `close`, which are async-signal-safe. It runs off main, on the signal source's global queue. It is removed at `off`.
- A crash or `kill -9` is caught by the watchdog's liveness checks and the beacon (5–20 s).

**Sleep and wake.** Sleep is blocked while the mode is on. If a wake happens anyway, `.didWake` re-reads `SleepDisabled` and runs the liveness checks.

**Cap.**
- Both sides enforce it. The app ends the mode at `until` (the earlier of the session's end and the cap) and keeps the session only if the lid is open. The toast is "Lid-closed mode turned off after 8 hours. Awake is still on; your Mac sleeps if you close the lid."
- The watchdog's cap is the same plus 60 s.

**Guards ahead of the session's own.**
- **Battery at or below `floor`** (B1) while discharging: the mode ends with "Lid-closed mode turned off at 20% battery."
- **Thermal at `serious` or worse:** "Lid-closed mode turned off because your Mac got hot."
- After either, the lid-shut rule above applies: if the lid is shut, the session ends too.
- The root side enforces the same floor and heat cut-off independently, so the app-side checks never depend on the root parsing succeeding, and vice versa.

#### B3.4 Leftovers and recovery (host level)

**When it runs.** `LidRecovery.atLaunch(safeMode:)` runs in `AppDelegate` step 7, next to `RevertJournal.recoverAtLaunch`. It runs whether or not Awake, the feature, or the kill switch is on, and also in Safe Mode.

**Classification.** It uses `AwakeLidPolicy.classify(journal:bootUUID:sleepDisabled:now:ownPID:)`:

| Journal | `SleepDisabled` | Result |
|---|---|---|
| none | — | nothing (today's behavior: someone else's setting is reported and never changed) |
| present | 0 | clear the journal |
| from another boot | 1 | **leftover** (the setting survives a reboot) |
| same boot | 1 | **pending**: an old watchdog may still be alive. Re-check after 30 s, then **leftover** if still 1. |

- While pending or leftover, turning lid-closed mode on is refused (B2). The journal is single-slot, so an old and a new watchdog never fight.
- A journal alone never triggers a prompt. The leftover rows show only while `SleepDisabled` actually reads 1.

**What the user sees for a leftover**
- **Every Snaptic menu** (shared, own and custom) gets these rows in its first group, above the tab bar:
  - status row "Sleep Is Turned Off";
  - "Turn Sleep Back On…".
- **Awake page and Advanced › Other Apps:** "Your Mac can’t sleep: an earlier lid-closed session didn’t finish." with "Turn Sleep Back On…" and "Not Now". "Not Now" hides the rows for this launch.
- **If Awake isn't running,** a toast shows instead, with "Turn Sleep Back On…".
- **"Turn Sleep Back On…"** runs `LidWatchdog.restoreScript` (fixed, with no arguments: `/usr/bin/pmset -a disablesleep 0`) through the same spawner and wrapper. Its prompt is: "Snaptic wants to turn sleep back on. An earlier lid-closed session didn’t finish. Enter an administrator password to allow this." Afterwards it re-reads `SleepDisabled` and clears the journal.
- **Advanced › Other Apps** never says "Snaptic can’t change this" while a Snaptic journal exists.

### B4. Interplay

- **Session guards** (battery floor, adapter, Low Power Mode, lock, user switch) are unchanged. They end the session, which ends the mode.
- **Fast user switching:** the mode follows the session, as decided by `userSwitchEnd`.
- **Pointer movement:** unchanged. N10 already requires an unlocked console session.
- **Drive Alive:** unaffected.
- **`endOnSystemSleep`:** the Advanced help becomes "When you choose Sleep or close the lid (not in lid-closed mode)."

### B5. Kit additions (all Linux-tested)

**`LidWatchdog`** (`AdminScript` is created only here; its init is `fileprivate`):
- `script`; `osascriptPath`;
- `Arguments.validated(...)`;
- `command(args)`, `appleScript(command:prompt:)`, `startScript(args, prompt:)`, `restoreScript(prompt:)`;
- `parseResult`, `promptText(floor:capHours:)`, `restorePromptText`.

Its tests:
- Golden script text.
- A round trip: shell-unquote(AppleScript-unescape(output)) equals the intended argv, checked with a small POSIX-quote parser in the test.
- A charset/range fuzz: nothing outside the allowed set validates, and cap 72 h validates.
- `parseResult` table: `ok 123`, `err -128`, `err 3`, `err 64`, garbage.

**`AwakeLidGate`:** the N19 truth table, tested exhaustively.

**`AwakeLidPolicy`:**
- start refusals;
- `floor(awakeGuards:)`, which is `max(10, floor)` or 20 when the battery floor is off;
- `until(sessionEnd:capStart:capHours:)`, on the continuous clock;
- `endsSession(lidShut:lidWillSleep:reason:)`;
- `classify(...)` (B3.4).

**`AwakeLidMode`, `AwakeLidEnd`, `AwakeLidFailStage`.**
- `AwakeLidEnd` cases: `user, sessionEnded, replaced, cap, battery, heat, otherApp, watchdogLost, quit, safeMode, featureOff, moduleStopped`.
- `AwakeLidFailStage` cases: `beacon, spawn, args, verify, timeout`.
- Both are closed `CaseIterable` enums, so log keys stay fixed.

**Config and features**
- **The feature is the toggle.** `AwakeFeature.lidClosed` gets `AwakeFeatureSpec(.optIn, all: [.sessions], uses: [.power, .system], controller: .sessions)`. It is added to `safeModeRemoves`, it is not unkillable, and its kill switch is `Awake.disable.lidClosed` (N14).
- **`AwakeLidConfig { capHours ∈ {1,2,4,8,12,24,48,72} = 8 }`** goes under the key `lid`. It decodes lossily, and `monotonic(over:)` only lowers the cap.
- **Backup:**
  - `KitBackup.allowedPaths[awake] += ["lid"]`;
  - `removedPaths += [awake, "features", "lidClosed"]`;
  - `importable` keeps `features[.lidClosed]` from the current Mac and applies `lid.monotonic(over: now.lid)`.
  - `KitBackupTests` cover both.
- **Fixtures:** `ConfigFixtures.fullAwake()` fills `lid`, and `awake.advanced.restore` keys gain `"lid"`.

**Text and logs**
- `AwakeLogEvent` cases: `lidOn`, `lidOff(AwakeLidEnd)`, `lidFailed(AwakeLidFailStage)`, `lidLeftover`.
- `AwakeRefusal.lidClosedSession`.
- `AwakeEndReason.lidEnded`, used when the mode's end ends the session (B3.3).
- `AwakeStatusFacts.lidClosed`.
- History gains `lidClosed` and `lidEnd`.
- All B0–B3 strings live in Kit, with tests for the header line priority and the warning rule.

### B6. Security model, lint and docs

**Threat model.** This goes in a new README section, "Keeping awake with the lid closed" › "Your password and what runs as root".

- **What runs as root.** Only while lid-closed mode is on, or during recovery, Snaptic runs a short shell script as root. Its text is in `LidWatchdog.swift`.
  - It changes only `SleepDisabled` and may run `pmset sleepnow`.
  - It turns sleep back on when any of these happen: the session ends, Snaptic quits or stops responding, the battery reaches the limit, the Mac gets hot, the time limit passes, or the script itself fails.
- **What a program running as you can do.**
  - Turn sleep back **on**: create the stop file, or delete the beacon.
  - While Snaptic is hung, keep touching the beacon. That keeps the mode alive only within the cap, the root-side battery floor and heat cut-off, and only while Snaptic's process is alive.
  - It can't start the mode without you typing a password into a dialog.
- **The password dialog names osascript, not Snaptic.** Any app can show this same dialog with any text. Only enter your password right after you choose Keep Awake with the Lid Closed in Snaptic.
- **Writable bundle: warn, not refuse.**
  - A program running as you that can change Snaptic could make Snaptic's prompt run something else as root.
  - But that same program can already show the identical osascript dialog with Snaptic's prompt text, without touching Snaptic at all. Refusing would add no protection against it and would remove the feature from the default drag-to-Applications install.
  - So Snaptic warns, and the README explains how to install it owned by root (`INSTALL=1`). A translocated copy is refused, because it can't be trusted to be the same app on the next run.
- **After a power loss or restart while the mode is on,** sleep stays off until you choose Turn Sleep Back On… (B3.4).
- **Security software may flag** "osascript with administrator privileges" started by an ad-hoc-signed app (Elastic rule, research §4).
- **The environment is minimal.** osascript gets only `PATH` and `LANG`. The script resets `IFS`, `PATH`, `ENV`, `BASH_ENV` and `CDPATH`, and calls every binary by absolute path.

**Lint**
- **Rule 12 (spawning).** The regex gains `NSAppleScript|NSUserScriptTask|OSAScript`.
- **New rule L18.**
  - These literals may appear in `Sources/` only in `SnapticKit/LidWatchdog.swift`: `with administrator privileges`, `disablesleep`, `/usr/bin/pmset`, `sleepnow`, `osascript`, `nohup`.
  - `AdminScript(` may appear only there.
  - `spawnAdminScript(` may be called only from `LidClosedController.swift` and `LidRecovery.swift`.
  - The lint03.py docstring lists L18.
- **L4** (`"pmset"`, `"sudo"`) is unchanged. It matches only the quoted bare words, and the script uses absolute paths.
- **L16** gets the two clauses described in B2.

**Docs and copy**
- **README lines to change:** 19, 155, 212, 252, 254–258, 273, 275, 318, 543, 589, 610–611, 639, 652, 666, 673, 686, 707 and 718.
  - The heading at 254 becomes "Keeping awake with the lid closed". Update the anchors at 273 and 639.
  - The "spawns nothing" claim becomes: "Awake runs a program only while you use lid-closed mode: `/usr/bin/osascript` asks macOS for an administrator password, then starts a short shell script as root that runs `pmset` and turns sleep back on when the session ends, Snaptic quits or stops responding, the battery reaches your limit, your Mac gets hot, or the time limit passes."
- **`site/index.html`** lines 401, 600 and 637. The lid card becomes: "Lid closed on battery? Turn on lid-closed mode with an administrator password. It stops at low battery, on heat, and after a time limit."
- **UI strings** (not comments): `AwakePresentation.swift:319` (the lid warning) and `:621` (`lidRoute`), `OtherAssertionsSection.swift:17`, and `AwakeAdvancedSheet.swift:108`.
- **Code comments:** `OtherAssertionsReader.swift:9` and `OtherAssertions.swift:6`.
- **THIRD_PARTY_NOTICES, Insomnia row:** add "reading SleepDisabled again 5 s after setting it; a recovery journal written before sleep is turned off; display sleep with the lid closed, honouring display assertions". These are ideas, not code.
- **Design-spec:** §1.5 (lid option, now available), §4.7 (terminology), and the §3.4 exception.
- **Release notes:** `docs/design/0.3.1/RELEASE-NOTES-0.3.1.md`.

### B7. Controls (Step 0 declares all of them, each with one stub use)

| Table | Ids |
|---|---|
| `AwakeAdvancedSheetControls` | `awake.advanced.lidClosed`: `.setting`, `keys: ["features.lidClosed"]`, `when: awake + [.hardware(.battery)]`, search keywords "lid", "clamshell", "closed display", "insomnia", "amphetamine", "disablesleep" |
| | `awake.advanced.lidCap`: `.setting`, `keys: ["lid.capHours"]`, `when: … + [.parentOn("awake.advanced.lidClosed")]` |
| | `awake.advanced.lidBundle`: status, conditional |
| | `awake.advanced.lidLeftover`: `.statusAction` |
| `AwakePageControls` | `awake.page.status.lidClosed` (pull-down item); `awake.page.status.lidLeftover` (`.statusAction`) |
| `AwakeMenuRowsControls` | `menu.awake.lidClosed`, `menu.awake.lidSubmenu`, `menu.awake.lidPreset` (`.perItem("preset")`), `menu.awake.lidCustom`, `menu.awake.lidNote` |
| `StatusMenuControls` | `menu.snaptic.tabs`, `menu.snaptic.showTab`, `menu.snaptic.lidLeftover`, `menu.snaptic.lidRestore` |
| `CustomSessionPanelControls` | `awake.custom.lidClosed` |

**New `ControlState` cases:** `lidModeOn` and `lidLeftover`.

---

## Part C: Hardware checks

These are numbered after 0.3's HW-23. The list lives here and in README's testing section; 0.3's PLAN is final and isn't edited.

| ID | Check |
|---|---|
| HW-24 | Switching tabs in an open menu on 14, 15, 26 and 27: the menu resizes correctly and the highlight lands right afterwards. Also check:<br>• a switch with a submenu open;<br>• whether the segmented control still takes clicks with `isEnabled = false`;<br>• hover look in light, dark, Increase Contrast and Reduce Transparency;<br>• a 13-inch Mac at the largest text size with the Displays tab and 3 external displays: switch away and back, with no stuck scroll arrows. |
| HW-25 | VoiceOver reaches the segments, hears ", needs attention" and ", on", and VO-Down after a switch reaches the new section's first item. With VoiceOver on, the Show … Tab items are visible. |
| HW-26 | ⌘1–⌘3 in an open menu: does tracking end, and does the next open show the chosen tab? ⌘, and ⌘Q still fire. |
| HW-27 | Sliders and switch headers in a newly shown tab work without reopening the menu. |
| HW-28 | The osascript admin dialog from an ad-hoc-signed, hardened-runtime Snaptic:<br>• the requester name, icon and title;<br>• the prompt text;<br>• Touch ID;<br>• Cancel returns `err -128`;<br>• no Automation consent is asked;<br>• Displays' dimming overlays move behind it. |
| HW-29 | Output of `notifyutil -g com.apple.system.thermalpressurelevel`, `pmset -g batt` and `pmset -g` on Apple silicon and Intel, macOS 14, 15, 26 and 27. |
| HW-30 | Lid closed on battery with no external display, with (a) a Keep Display On session and (b) `caffeinate -d` in another app. Check that:<br>• the Mac stays awake;<br>• the panel goes dark within 35 s;<br>• Apple menu › Sleep is greyed out;<br>• the panel wakes on lid open;<br>• the keyboard backlight's state is recorded. |
| HW-31 | The watchdog survives osascript's exit and a SIGTERM to osascript, and `ps -o ruid,uid` shows `0 0`. Each of these must restore sleep, checked with `pmset -g`:<br>• quit;<br>• `kill -9` of Snaptic;<br>• hanging Snaptic with SIGSTOP for 30 s;<br>• the stop file;<br>• the cap;<br>• deleting the beacon in a tight loop (restored within 10 s);<br>• an induced script error. |
| HW-32 | Restart while on: `SleepDisabled` persists, the leftover rows show in every menu even with Awake turned off, and Turn Sleep Back On… works. |
| HW-33 | The battery floor restores sleep with Snaptic stopped by SIGSTOP (the root-side floor). |
| HW-34 | The cap, battery floor and heat ends, each with the lid closed on battery: the Mac is asleep within 30 s (`pmset -g log`). |
| HW-35 | Watchdog cost: `powermetrics` wakeups at a 5 s period. |

## Part D: Teams, file ownership and order

### Step 0 (lead, on `feature/v031`)

Step 0 lands all of the following:
- This plan's final revision.
- `stubs.tsv` rows for every new source and test file:
  - `MenuTabBar`, `LidWatchdog`, `AwakeLidGate`, `AwakeLidPolicy`, `LidClosedController`, `LidRecovery`;
  - `LidWatchdogTests`, `AwakeLidGateTests`, `AwakeLidPolicyTests`, `MenuTabsTests` (or extending `MenuLayoutTests`).
- Every signature change in the shared files:
  - `AwakeMenuStyle`, `menuSection(tabbed:)`, `menuAttention`, and the new `AwakeMenuRow` cases;
  - `AwakeRefusal.lidClosedSession` and `AwakeEndReason.lidEnded`;
  - `AwakeLidMode`, `AwakeLidEnd` and `AwakeLidFailStage`;
  - `AwakeRuntimeState.lidMode` and `lastLidEnd`;
  - `AwakeSession.lidRequested`;
  - `AwakeStatusFacts.lidClosed`;
  - the `HelperSpawner.spawnAdminScript` signature;
  - `OtherAssertionsReader.sleepDisabledPreference()`.
- Every B7 and A6 control with a stub use, so L15 is green from Step 0.
- The lint changes (rule 12, L16 and L18).
- Kit type signatures, with `fatalError("Step 1")` bodies only where tests don't call them.

### Step 1 (in parallel; one owner per file)

| Team | Owns |
|---|---|
| **T-menu** | `StatusMenu.swift`, `MenuKit.swift`, `MenuTabBar.swift`, `MenuLayout.swift` and its tests, `ModuleContracts.swift`, Window Switcher's and Displays' `menuAttention` and `menuSection(tabbed:)` (in their module files), `DisplaysMenuBuilder` (the upgrade item move), `MenuBarPage.swift`. |
| **T-lid-kit** | `LidWatchdog.swift`, `AwakeLidGate.swift`, `AwakeLidPolicy.swift` and their tests. `AwakePresentation.swift` and its tests, including the `tab` style, so T-menu sends requests. `AwakeSession.swift`, `AwakeSessionPolicy.swift`, `AwakeCommandGrammar.swift`, `AwakeHistory.swift`, `AwakeLogEvent.swift`, `ConfigAwake*.swift`, `KitBackup.swift`, `AwakeFeatureGraph.swift`, `OtherAssertions.swift`, `ConfigFixtures.swift`, and the Kit test files for these. |
| **T-lid-app** | `LidClosedController.swift`, `LidRecovery.swift`, `HelperSpawner.swift`, `SessionController.swift`, `AwakeAutomation.swift`, `AwakeMenuRows.swift`, `IndicatorController.swift`, `AwakeModule.swift` (including `menuSection(tabbed:)`), `AwakeAdvancedSheet.swift`, `AwakeStatusSection.swift`, `AwakePage.swift`, `CustomSessionPanel.swift`, `OtherAssertionsReader.swift`, `OtherAssertionsSection.swift`, `SystemEventsMonitor.swift`, `AssertionManager.swift`, `HistoryController.swift`, `AwakeHistoryPage.swift`, `AwakeDiagnostics.swift`, `AppDelegate.swift`, `EmergencyActions.swift`, and the `SNSpawn` shims if needed. |
| **T-docs** | `README.md`, `site/index.html`, `THIRD_PARTY_NOTICES.md`, the design-spec amendments, and the release notes. |

### Step 2

1. Merge, then CI and `lint --strict`.
2. At least four adversarial review rounds on the code: security, Awake correctness, menu UX and accessibility, and code and consistency. Each round is followed by fixes.
3. Set Info.plist to 0.3.1 and open a PR into main for the owner. No tags.

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
