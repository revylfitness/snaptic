# Snaptic 0.3.1 plan (r5, final)

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
- **r3 → r4:** round 3 found 2 Blockers, 11 Majors and 45 Minors, recorded in `review-r3-*.md`:
  - `ksd` treated an absent kernel property as unreadable;
  - the plan misstated Sparkle's trust model.

  The owner's account setup (E0) was also done during this revision.
- **r4 → r5 (final):** round 4 found no Blockers and 4 Majors, all fixed by text changes. Design and product said "ready"; code and security said "not ready" pending those Majors.
- Every finding is handled in the revision that follows it. Dispositions are in §R (r1), §R2 (r2), §R3 (r3) and §R4 (r4) at the end.

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
- At build, StatusMenu measures every tab's section in a scratch `NSMenu` together with the host safety rows and the shared footer (including the Show … Tab items in the visibility they'll have, so the key column counts; r1 U1) (`menu.size.width` after adding the items) and sets `minimumWidth = max(MenuKit.width, widest)`. Switching then never widens the open menu, and the segment never moves under the pointer.
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
  - Keyboard navigation (`NSApp.isFullKeyboardAccessEnabled`);
  - Accessibility › Full Keyboard Access, which has no public API: `FullKeyboardAccessEnabled` in `com.apple.Accessibility` (r1 U2; HW-25 confirms the key). Unreadable counts as off.

  Neither posts a change notification, so `menuNeedsUpdate` sets the items' `isHidden` on **every** open that has tabs, even when the slot isn't dirty, reading the preferences at most once per open (r2 U2-2). It's a property change, not a rebuild.
- `StatusMenu.menuHasKeyEquivalent` returns true with that item's target and action when `openMenus > 0` and the event is ⌘1–⌘n. Otherwise it returns false, as today.
- The item's action stores the choice and sets `shared.dirty = true`. It never changes the menu in place.
- The expected result is that **the menu closes and the next open shows the chosen tab**. If HW-26 finds that tracking continues, the action switches in place instead.

**Discoverability**
- The segment tooltips, the control's accessibility help, and the Menu Bar page footer, which replaces MenuBarPage.swift:100's line: "The Snaptic icon appears when a module is set to Show in Snaptic Menu. With two or more, the Snaptic menu shows a tab for each; while it’s open, press ⌘1, ⌘2, or ⌘3 to switch tabs."
- The README says "⌘1–⌘3 choose a tab (⌘1–⌘2 with two tabs)".

**VoiceOver**
- The tab bar view is the accessibility container: role tab group, label "Menu tabs", with one element per segment as its children and tabs (title plus ", on" / ", needs attention"; help "Command-n", r1 U3). The segmented control and its cell (`MenuTabSegmentedCell`, which draws nothing of its own) are ignored, so AppKit's own segment elements never reach VoiceOver (r1 U8). VoiceOver users choose a segment with VO-Space, and `.layoutChanged` refreshes the menu's children (HW-25).

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

> **0.3.3 amendment (owner).** The opt-in moves out of Advanced; its behaviour is unchanged. The "Lid closed" section below (the toggle, the writable-bundle note, the translocated row, the footer and its Learn More…) is now a section of the **main Awake page**, after "End sessions automatically", and Advanced no longer has it. The **Menu Bar page** gets a second switch for the same `features[.lidClosed]`, under Awake's rows: "Show Keep Awake with the Lid Closed in the Awake menu" (help: see review round 1 (c) below). It shows and locks as the Awake page's switch does (see (b) below: Safe Mode's disabled reason, the kill switch's `DefaultsLockRow`, the lid mode's reason). The B3.4 leftover rows stay at the top of the Awake page and under Advanced › Other Apps. The `lidRoute` "Feature off" text below becomes "…or turn on lid-closed mode in Awake settings." Ids: see the B7 amendment.
>
> **0.3.3 review round 1.** (a) *Locked while on (P1-1).* While `runtime.lidMode` is on, authorizing, verifying or stopping, both switches are disabled with `AwakeLidText.turnOffFirst`: "Lid-closed mode is on. Turn it off first, in the Awake menu or in Options on the Awake page." (r2 P2-4: Options ▾ on the Awake page has the item, and with Awake on Don't Show there is no Awake menu) (turning either off used to end the mode silently, `endToast(.featureOff)` being nil, and sleep a shut Mac). (b) *One predicate.* `AwakeLidOptIn.of(battery:awakeRunning:translocated:killSwitches:safeMode:lidMode:)` (Kit, tested) decides both pages: no battery → no row; translocated → the translocated row in place of the switch; Awake not running → the switch shown disabled (Menu Bar only; the Awake page has no section then); kill switch → disabled with `DefaultsLockRow`; Safe Mode → its reason; lid mode on → the reason above; otherwise usable. (c) *Menu Bar parity (P1-2, P1-3).* The Menu Bar switch shows the writable-bundle note with its own Learn More… (`menubar.page.awakeLidBundleLearnMore`), and on a translocated copy the translocated row carries the `menubar.page.awakeLidClosed` anchor. Its help becomes "Adds Keep Awake with the Lid Closed to the Awake menu, the same switch as on the Awake page. Choosing it asks for an administrator password each time. Use it on a hard surface, not in a bag." (P1-4: the switch doesn't turn the mode on). (d) *Restore (S1-1).* Restore Menu Bar Defaults… leaves `features.lidClosed` alone: it is Awake's setting, reset by Restore Awake Defaults…, as `indicator` is the Menu Bar page's and Awake's restore keeps it.
>
> **0.3.3 review round 2.** (e) *Restore Awake Defaults… (P2-1).* While `runtime.lidMode.locksOptIn` (on or pending, read at the click), `AwakeConfig.restoringDefaults(keepingLidClosed: true)` keeps `features.lidClosed`, as it keeps `features.triggers`; clearing it would end the mode silently, as the switches did before (a). It is never kept silently: `AwakeLidText.restoreNotice` gives the toast "Lid-closed mode is on, so it stays allowed. Turn it off, then restore again to reset it." whenever the kept value is on. Reset All Settings… is unchanged (it stops every module first and its alert says so). (f) The Awake page's translocated row carries the `awake.page.lidClosed` anchor, as the Menu Bar page's does (P2-2).

- **The toggle.** `ToggleSetting(L("Keep awake with the lid closed"), help: L("Choose Keep Awake with the Lid Closed in the Awake menu. Asks for an administrator password each time."))`.
  - It is backed by `features[.lidClosed]`, which is opt-in and off by default.
  - It shows only on Macs with a battery (`when: .hardware(.battery)`).
- **Writable-bundle note.** Shown only while the toggle is on and Snaptic's bundle is writable by your account: `SettingsRowNote(L("Your account can change this copy of Snaptic, so another app could change it and misuse the password prompt."), fix: StatusAction(title: L("Learn More…"), control: ControlID("awake.advanced.lidBundleLearnMore")))`. This is the same component as the Accessibility note under "Move the pointer slightly".
  - The string lives in Kit next to the Permissions copy.
  - Learn More… opens README › "Your password and what runs as root". That section gives the release-zip fix: `sudo chown -R root:wheel /Applications/Snaptic.app` (the same advice the Permissions page links to).
- **Footer.** "While lid-closed mode is on, your Mac can’t sleep for low battery or heat. Awake turns it off at the Awake page’s battery level (at least 10%), when your Mac gets hot, or after 24 hours. Use it on a hard surface, not in a bag. Learn More…"
- **One battery limit.** Lid-closed mode turns off at `max(10, Awake’s battery floor)`. When Awake's battery floor is turned off, the limit is 20%.
- **One fixed time limit of 24 hours.** There's no picker: the idle submenu already makes you pick the session's length, so the cap only matters for Until Turned Off and task-bound sessions (parity r2 cut 1).
- **Translocated copy.** Lid-closed mode is unavailable. This row shows instead: "Snaptic is running from a temporary location. Move it to Applications to use lid-closed mode." (a Kit sibling of PermissionsPage.swift:80).

#### The main Awake page

The `lidRoute` line depends on state. All three variants live in Kit, with a test:
- **Feature off:** "To keep it awake with the lid closed, connect power and an external display, or turn on lid-closed mode in Awake › Advanced."
- **Feature on and available:** "…or choose Keep Awake with the Lid Closed in the Awake menu."
- **Unavailable** (translocated, no lid, no battery, kill switch, or Safe Mode): the 0.3 text, unchanged. In the last three the Advanced toggle is missing or locked, so "Feature off" would point at a control the user can't use.

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
- **While an earlier session's journal is still pending** (B3.4), the lid row shows "Finishing Earlier Session…", disabled.
- **Superseding a pending request.** Any manual start or Turn Off while `authorizing` or `verifying` an idle start supersedes the lid request (B3.0).

#### Custom… panel

In Start mode only (not in Add Time…):
- `ToggleSetting(L("Keep awake with the lid closed"), help: L("Start… asks for an administrator password."))`.
- While it is on, the button reads "Start…".
- Start… never closes the panel silently (r1 A4, r2 A2-2). While another lid request is under way, a toast says so in a sentence ("Lid-closed mode is turning off. Try again in a moment.", and likewise for the password and turning on), and the panel stays open. If the feature stopped being effective while the panel was open (turned off, the kill switch, Safe Mode, or the request is refused without a toast), the toast is "Lid-closed mode isn’t available right now. To start without it, turn off “Keep awake with the lid closed”." and the panel stays open. After a B2 refusal (low battery, heat, a leftover, a request still finishing, translocated) the panel stays open too, behind the refusal's toast, so the user can turn the toggle off or plug in and start without setting the session up again (r3 U3-6, `AwakeLidRequestResult.closesCustomPanel`).

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
  - "…: it stopped unexpectedly." (the watchdog exited for a reason the app's own facts don't show, r2 A2-1)

  It is cleared at the next turn-on.
- **Cap warning.** When the cap will end before the session, a toast shows 5 minutes ahead: "Lid-closed mode turns off in 5 minutes. If the lid is closed then, your Mac goes to sleep."
- **History.** Entries gain `lidClosed` (true if the mode was on at any point), shown as the subtitle suffix " · Lid closed".
  - A session that resumes after a quit or crash keeps it: the runtime snapshot carries `lidSession`, the manual session's id while it has had the mode. Only History reads it (never the N19 gate), and the mode itself is never restored. After a real gap, the entry for the part before the gap has it; a session that continues its segment has it in its one entry (r1 A5).
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
  - restore or resume. The header then says "Lid-closed mode ended at …: Snaptic quit." That line shows only when an earlier run's journal was found and the resumed session is the snapshot's `lidSession` (a journal also survives a quit during a failed request's wait, r2 A2-4), and is left out when the B3.4 leftover rows already explain the state.

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
| Journal pending (B3.4), or an earlier request's osascript isn't reaped yet (checked before any journal or beacon work, so a superseded request's stop file outlives it, r2 A2-3) | "Snaptic is finishing an earlier lid-closed session. Try again in a minute." |
| Leftover (B3.4) | "Turn sleep back on first. It may have been left off by an earlier lid-closed session." with **Turn Sleep Back On…** and **Open Awake Settings…** |

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
  3. **if a watchdog may have run**, keep the journal until IORegistry `SleepDisabled` reads 0. If it still reads 1 after 30 s, the leftover rows show (B3.4).

  This covers timeout, error, a failed verify, and being superseded once osascript was started (`AwakeLidPolicy.abandonWatches`). When root provably changed nothing, step 3 is instead "remove the journal, if one was written, and leave the recovery alone": the preflight (no journal yet, including an unreadable kernel), any failure before osascript runs, Cancel (no password), and `check`'s exit 3 or 64 (the `run` line never executes after `|| exit $?`). A `SleepDisabled` of 1 then stays someone else's setting (B3.1 step 1, B3.4 "nothing"); it never becomes Snaptic's leftover (r1 S1).
- **App Nap.** While the state isn't `off`, the controller holds `ProcessInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Snaptic lid-closed mode")`.

#### B3.1 Turning on (LidClosedController)

1. **Preflight.**
   - Check the gate, the feature, the B2 refusals and lid presence.
     - Lid presence comes from feature availability: `availability(of: .lidClosed)` reads `AppleClamshellState` from IORegistry **synchronously**, not from the published value (which arrives after module start), and is recomputed on `.didWake`.
     - Without a lid it is `.unavailable("No lid")`.
   - Read `SleepDisabled` from IORegistry (the kernel) and from the preference (`OtherAssertionsReader.sleepDisabledPreference()`). If the root domain is found but has no `SleepDisabled` property, that reads as 0, which is the state on every Mac that has never set it. Only a failed `IOServiceGetMatchingService` reads as unreadable.
   - If either is on, Snaptic doesn't touch it. The toast says "Sleep is already turned off for this Mac by another app or command, so it stays awake with the lid closed." The session starts or continues without lid-closed mode.
2. **Journal.** One slot: `~/Library/Application Support/Snaptic/awake/lid.json`, mode 0600, written atomically.
   - Contents: `{token, bootSessionUUID, startedAt (wall + continuous), pid: nil, instanceID: nil, floor}`.
   - `token` is 128 random bits, written as 32 lowercase hex characters.
3. **Beacon directory.**
   - `D = confstr(_CS_DARWIN_USER_TEMP_DIR)` with its trailing `/` trimmed, plus `/snaptic-lid`. Both sides use this exact string, never a realpath.
   - Create `D` with mode 0700. `lstat` must show a directory owned by our uid with mode 0700. If not, show "Snaptic couldn’t turn on lid-closed mode. Try again." and log stage `beacon`.
   - Remove old `beat-*` and `halt-*` files, and `stop-*` files at least 3 minutes old (`AwakeLidPolicy.clearsBeaconFile`, by their `lstat` mtime). A younger stop file may belong to a superseded or timed-out request whose root `run` hasn't reached its own stop-file check yet; that watchdog sets only within 5 s of its start, and it starts at most 125 s after its spawn, so keeping the file closes that window whatever the timing (r3 S3-1, r2 A2-3).
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
   - **Timeout.** After 120 s, SIGTERM to **osascript's pid only**. That counts as a timeout (B3.0 exit). If osascript hasn't exited 5 s later, SIGKILL (pid only, start time checked), so a stuck one can't hold the admin spawn's single flight, and with it Turn Sleep Back On…, for the rest of the run (r1 S5).
   - **Its own process group** (`POSIX_SPAWN_SETPGROUP`), which osascript's root shell and the watchdog inherit: when Snaptic runs from a terminal, the terminal's ^Z, ^\ and ^C go only to the foreground group, so they never reach the root side (r1 S4).
   - `spawnAdminScript` does **not** require helper identity or `unavailableReason == nil`.
5. **Result.** `LidWatchdog.parseResult(stdout)` accepts only `^ok [0-9]+$` with `1 < pid < 100000` → `.launched(pid)`, or `^err -?[0-9]+$` → `.canceled` (−128) or `.failed(code)`. Anything else is `.failed(-1)`. The AppleScript wraps the call in `try … on error number n`.
   - **Canceled:** silent.
   - **3:** the "already turned off" toast.
   - **64:** stage `args`.
   - **Otherwise:** "Snaptic couldn’t turn on lid-closed mode. Try again."
6. **Verify.**
   - Record `pid` and `SNProcess.instanceID(for: pid)`. It uses `sysctl(KERN_PROC_PID)`, which answers for root processes, unlike `PROC_PIDTBSDINFO`.
   - A new `SNProcess.realUID(for:)` reads `kp_eproc.e_pcred.p_ruid` from the same `kinfo_proc`.
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
umask 077; trap '' HUP INT QUIT TSTP TTIN TTOU      # as started (& ignores INT, QUIT): no terminal ends or stops it
MODE=$1; U=$2; P=$3; T=$4; C=$5; F=$6; D=$7
case "$MODE" in check|run) ;; *) exit 64;; esac
num() { case "$1" in ''|*[!0-9]*) return 1;; esac; }
num "$U" && num "$P" && num "$C" && num "$F" || exit 64
case "$T" in *[!0-9a-f]*|'') exit 64;; esac; [ ${#T} -eq 32 ] || exit 64
case "$D" in /var/folders/*/snaptic-lid) ;; *) exit 64;; esac
case "$D" in *..*|*[!A-Za-z0-9_/+.-]*) exit 64;; esac
[ "$F" -ge 10 ] && [ "$F" -le 50 ] && [ "$C" -ge 3600 ] && [ "$C" -le 86400 ] || exit 64
C=$((C+60))
[ "$MODE" = run ] && A=$(/bin/date +%s)          # the 5 s start limit counts from here (r3 S3-1)
# Stored preference: the "System-wide power settings:" block only, first match; 1, 0 (absent) or ? (odd/unreadable)
sd() { O=$(/usr/bin/pmset -g 2>/dev/null) || { echo '?'; return; }
  printf '%s\n' "$O" | /usr/bin/awk '/^System-wide power settings:/{s=1;next} s&&/^[^ \t]/{s=0}
    s&&$1=="SleepDisabled"&&!d{v=$2;d=1} END{if(!d)print 0; else if(v=="0"||v=="1")print v; else print "?"}'; }
rd() { /usr/sbin/ioreg -r -n IOPMrootDomain -d 1 2>/dev/null; }
# Kernel value on IOPMrootDomain: 1, 0 (root domain present, property absent: powerd creates it only once
# SystemPowerSettings exists), or ? (no root domain output at all)
ksd() { rd | /usr/bin/awk '/IOPMrootDomain/{r=1} /"SleepDisabled" = /{f=1; v=($NF=="Yes")?1:0}
                          END{if(f)print v; else if(r)print 0; else print "?"}'; }
key() { rd | /usr/bin/awk -v k="\"$1\" = " 'index($0,k){print $NF; exit}'; }
# A regular file owned by U; stat without -L reads the name itself (lstat), so no link is followed
owned() { [ "$(/usr/bin/stat -f '%HT %u' "$1" 2>/dev/null)" = "Regular File $U" ]; }
[ "$(sd)" = 0 ] && [ "$(ksd)" = 0 ] || exit 3      # someone else holds it, or unreadable: never take it
[ "$MODE" = check ] && exit 0
# D, entered once: U's own 0700 directory on the volume of /var/folders (no network or user mount). Every later
# lookup is one name inside it, so replacing D or a parent of it can't redirect one
V=$(/usr/bin/stat -f %d /var/folders) && cd -P "$D" &&
  [ "$(/usr/bin/stat -f '%HT %u %Lp %d' .)" = "Directory $U 700 $V" ] || exit 0
owned "stop-$T" && exit 0                            # stopped before we started (late password)
# Over 5 s to get here (a stalled lookup): Snaptic's 10 s verify has given up and may have dropped its journal
N=$(/bin/date +%s); num "$A" && num "$N" && [ $((N-A)) -le 5 ] || exit 0
WESET=0; HALT=0
cleanup() {
  trap '' TERM
  [ "$WESET" = 1 ] || return
  i=0; while [ $i -lt 3 ]; do [ "$(sd)" = 0 ] && break
    /usr/bin/pmset -a disablesleep 0; /bin/sleep 1; i=$((i+1)); done
  { [ "$HALT" = 1 ] || owned "halt-$T"; } && return  # shutting down (TERM, or Snaptic saw it first): never sleepnow
  i=0; while [ $i -lt 5 ] && [ "$(ksd)" != 0 ]; do /bin/sleep 1; i=$((i+1)); done   # powerd → kernel
  j=0; while [ $j -lt 3 ]; do
    [ "$(key AppleClamshellState)" = Yes ] || return
    [ "$(key AppleClamshellCausesSleep)" = Yes ] && { /usr/bin/pmset sleepnow; return; }
    /bin/sleep 1; j=$((j+1)); done
}
trap 'cleanup' EXIT; trap 'HALT=1; exit 0' TERM
WESET=1; /usr/bin/pmset -a disablesleep 1          # WESET first: a TERM during the set still restores
i=0; until [ "$(sd)" = 1 ] && [ "$(ksd)" = 1 ]; do       # post-set check, up to 3 s
  i=$((i+1)); [ $i -ge 6 ] && exit 0; /bin/sleep 0.5; done
# The beacon, read in a child each lap: a lookup that stalls holds the child, never the cap, battery or heat checks
beacon() { owned "stop-$T" && return 1                  # asked to stop
  owned "beat-$T" || return 1                           # beacon gone
  M=$(/usr/bin/stat -f %m "beat-$T" 2>/dev/null); num "$M" || return 1
  [ $((N-M)) -le 20 ]; }                                # Snaptic hung: the beacon is the real bound
START=$(/bin/date +%s); Z=0; Q=0; LB=0; H=0
while :; do
  /bin/sleep 5 & wait $!                               # traps run without waiting out the sleep
  N=$(/bin/date +%s); num "$N" || exit 0
  [ $((N-START)) -ge "$C" ] && exit 0                  # hard cap
  /bin/kill -0 "$P" 2>/dev/null || exit 0              # liveness hint only (any pid answers root)
  beacon & W=$!
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
  if num "$TP"; then H=0; [ "$TP" -ge 2 ] && exit 0    # heavy or worse (= ProcessInfo .serious)
  else H=$((H+1)); [ $H -ge 2 ] && exit 0; fi          # unreadable twice: restore
  # Still reading 5 s later (a stalled lookup): as if gone. The shell's own kill, for its own child; foreground
  # sleeps keep it $!, so the shell keeps its status, and wait runs only once it has exited, so it returns at once
  i=0; while kill -0 "$W" 2>/dev/null; do i=$((i+1)); [ $i -ge 10 ] && exit 0; /bin/sleep 0.5; done
  wait "$W" || exit 0                                  # asked to stop, beacon gone or stale
done
```

**What root does**
- It writes only through `pmset -a disablesleep 0|1` and `pmset sleepnow`.
- **`sleepnow`.** It runs only in `cleanup`, and only if all of these hold:
  - the system isn't shutting down;
  - the kernel shows sleep re-enabled (powerd applies the preference asynchronously; while the kernel bit is set, `sleepnow` is refused);
  - the lid is shut, and closing it would sleep the Mac.

  It is needed because the kernel doesn't re-check a closed lid when `SleepDisabled` clears (xnu IOPMrootDomain.cpp:8386-8389).
- It never writes, deletes, follows symlinks in, or reads the contents of user-controlled files. It only `stat`s them (`lstat`) for owner, type and mtime.
- **User paths can't stall it** (r1 S3). `D` is entered once, before anything is set, and only if it is a 0700 directory owned by `U` on the same volume as `/var/folders` (so not a network or user mount). After that every lookup is a single name inside that directory, so renaming or replacing `D` or one of its parents can't redirect it. Each lap reads the stop file and the beacon in a child process; the cap, battery, heat and `SleepDisabled` checks run in the main shell meanwhile. A child still reading 5 s after those checks (for example, a name replaced by a stalled mount) counts as "beacon gone", so the stop file is still seen within one lap. `cleanup` touches one, `halt-$T`, only after sleep is restored, so a stall there can only skip `sleepnow`.
- **Nor delay it past the app's verify** (r2 S2-3, r3 S3-1). The reads before the set (the preference and kernel check, entering `D`, its `stat`, the first stop-file check) run in the main shell, and `A` is read before all of them. If getting through them took more than 5 s from the start of `run`, the app's 10 s verify (which starts when osascript prints `ok`, after `run` started) has already given up and may have dropped the journal, so the watchdog exits without setting anything. Otherwise the set lands inside the verify window, and the journal is kept.

**Every exit restores.**
- The EXIT trap runs `cleanup`. TERM exits through it. `cleanup` ignores a further TERM, so a second one can't cut it short.
- `WESET=1` comes just before `pmset -a disablesleep 1`, not after it (r2 S2-1). A shell runs a trap only once the foreground command returns, so a TERM during that pmset is handled after `SleepDisabled 1` is stored; `cleanup` then still restores. Setting it first is safe: the check just read 0, and `cleanup` runs pmset only while the preference isn't 0.
- Every arithmetic operand is checked with `num`.
- An unreadable value or a disagreement between the preference and the kernel counts toward a restore, and so do an unreadable battery level and an unreadable heat level (each twice in a row).
- The one deliberate non-restoring exit clears `WESET` first. It needs both the preference and the kernel to read 0, twice.

**SIGTERM is treated as shutdown.** `HALT` is set by any SIGTERM, whether from shutdown or from security software or an administrator signalling the watchdog. Either way, `cleanup` restores sleep but skips `sleepnow`. A `halt-<token>` file counts the same (r2 A2-5): Snaptic's quit after `NSWorkspace.willPowerOffNotification` (restart, shut down, log out) writes it before the stop file, because the quit usually reaches the watchdog before launchd's TERM. If Snaptic is also gone and the lid is shut, the Mac keeps running until the lid opens. This is accepted: someone with root who stops the watchdog has taken responsibility for it.

**Ownership.** Both `check` and the start require the preference **and** the kernel to read 0 (`exit 3`). The restore runs only when `WESET = 1`.

**Late password.** The stop file is written on every failure exit in the app (B3.0) and checked before anything is set.

**Detachment**
- `nohup` and `&`, with all three standard streams redirected.
- osascript's own process group (B3.1 step 4), and the script ignores TSTP, TTIN and TTOU, so a terminal can't stop the watchdog. Stock macOS has no `setsid(1)` and `set -m` needs a terminal, so the script can't leave the group itself. `&` already starts it with INT and QUIT ignored (POSIX, for a shell without job control), and a signal ignored on entry can't be trapped. The script ignores both itself too, so a direct run (as in the shell test) behaves like the real launch: neither ends it (r2 S2-2).
- The app signals only osascript's pid.
- HW-31 checks:
  - osascript returns within 1 s of the password;
  - `ps -p <pid> -o comm,ruid,uid` shows `sh 0 0`;
  - the watchdog survives osascript's exit and a SIGTERM to osascript.

  If the real uid isn't 0, the user could kill the watchdog. The app's liveness check (B3.3) is then the guarantee, and B6 says so.

**Cost.** About 10 forks every 5 s. HW-35 measures wakeups. If they're significant, the period becomes 10 s and staleness 30 s.

**Shell test (CI).** `LidWatchdog.script(tools:period:stale:)` takes a table of **every** absolute tool path the script uses, plus the loop period and the staleness limit. It defaults to the macOS paths, 5 s and 20 s (golden-tested). The test stubs every tool, including `kill`, `sleep`, `date`, `stat`, `awk`, `sed` and `nohup`, uses a 0.2 s period, kills its own leftover processes, and also runs in the macOS `build` job, the only place with bash 3.2. Lint rules 7 and 12 scan only `Sources/`, so the test needs no exemption. On `kit-linux` it runs the generated **command** under `/bin/sh` (dash) and `bash --posix`; on macOS it runs under bash 3.2. The stub tools record their calls. The test asserts:
- a `check` exit of 3 or 64 becomes the command's exit status;
- `$!` is the `run` process's pid;
- the command returns at once;
- the EXIT trap restores sleep after these exits: stop file, missing beacon, stale beacon, induced arithmetic error, TERM (also one that arrives while `pmset -a disablesleep 1` runs), unreadable heat twice, a beacon lookup that never returns;
- INT and QUIT don't end it, whether the generated command starts it or it runs directly, and TSTP doesn't stop it; the stop file still restores afterwards;
- a `D` that isn't U's own 0700 directory on `/var/folders`'s volume is never taken, and nothing is set when the first stop-file check stalls for more than 5 s, or the first preference read does;
- `sleepnow` runs only under its conditions, and never after a quit that wrote the halt file;
- `WESET=0` only on a double agreement of the preference and the kernel.



#### B3.3 App side while on

**Heartbeat**
- A `DispatchSourceTimer` on a private serial queue fires every 5 s with 0.5 s leeway.
- Each tick touches the beacon (`futimens` on the open `O_NOFOLLOW` fd) **only if** `HostHeartbeat.shared.mainAgeMillis() < 10_000`.
- The fd is closed in the timer's cancel handler on the same queue, so a reused fd number is never touched.
- **Liveness.** Each tick runs `kill(pid, 0)`, where ESRCH means gone, and compares `SNProcess.instanceID(for: pid)` with the value recorded at verify. It also reads IORegistry `SleepDisabled`.
- State changes hop to main with `DispatchQueue.main.async { MainActor.assumeIsolated … }` (rule 2).
- **Gone, or 0 twice:** the mode ends (`watchdogLost` or `otherApp`). The watchdog ends on its own at the floor, on heat and at its cap, often a lap before the app sees the same fact, so a lost watchdog is named by the app's own facts when they explain it (`AwakeLidPolicy.lostReason`: heat, battery, then the cap) and is `watchdogLost` otherwise, which has its own toast ("Lid-closed mode stopped unexpectedly. Awake is still on.") and Last end phrase (r2 A2-1). The toast doesn't promise that the Mac sleeps when the lid closes: nothing has checked yet that sleep is back on (r3 U3-1). Root also exits, without restoring, after reading another app's 0 twice; when the app read a 0 while the watchdog was still alive, the end is `otherApp` (r3 A3-1). A lost watchdog gets the same 15 s turn-off wait as any other end, because powerd may apply its restore a moment after it exits; if `SleepDisabled` still reads 1 after that, the leftover rows show (B3.4, r1 A3).

**Display while the lid is shut**
- **`lidShut`.** `AwakeArbiterInput.lidShut`, which defaults to `false`, is true only while the mode is on, the lid is closed (`SystemEventsMonitor.lidClosed == true`, now published as `AwakeRuntimeState.lidClosed`) **and no external display is attached**. It is re-evaluated on screen changes.
  - While it's true, the session's effective display policy is `maySleep`, so Snaptic's own assertion doesn't cancel display sleep.
  - With an external display attached, the user's Keep Display On choice stands.
- **Display sleep, as the user.** While `lidShut` is true and the built-in display isn't asleep (`CGDisplayIsAsleep`), the app runs `HelperSpawner.spawnTool(LidWatchdog.displaySleepArgv)` = `/usr/bin/pmset displaysleepnow`. This needs no root. At most every 10 s, because powerd defers the request for about 30 s after a wake.
  - Apple silicon has no `IODisplayWrangler`, and `pmset` uses the private SkyLight call there, so this is the route that works on both architectures (NM2).
  - `spawnTool` accepts only a fixed `ToolCommand` created in `LidWatchdog.swift`.
  - It applies the same checks as `spawnAdminScript`: before SIGCONT the child must satisfy `anchor apple`; the environment is minimal; the child is disclaimed.
  - It is single-flight: there is no new spawn while the previous one is still running.
  - If the built-in display isn't in `CGGetOnlineDisplayList` (which can happen with the lid shut), its state counts as unknown, and `displaysleepnow` still runs, rate-limited.
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
- toast: "Awake ended: lid-closed mode turned off while the lid was closed." (the standard `AwakeEndText.toast` path);
- phrase: "lid-closed mode turned off while the lid was closed";
- `AwakeEndText` gets a test for it.

The watchdog's `sleepnow` covers a hung app.

**Quit**
- `applicationWillTerminate` writes the stop file synchronously. After `NSWorkspace.willPowerOffNotification` (restart, shut down, log out) it first writes `halt-<token>` the same way (`AwakeLidPolicy.writesHalt`), so the watchdog restores without `sleepnow` (B3.2, r2 A2-5).
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
| **Every Snaptic menu** (shared, own and Awake's custom one) | First group, above the tab bar: a status row "Sleep Is Turned Off", then "Turn Sleep Back On…". `IndicatorController` calls a static `StatusMenu.leftoverItems(host:)` each time its menu opens (`menuNeedsUpdate` rebuilds it on every open), because a menu item can belong to only one menu; `CustomItemRow` carries no flag for it. **Keep Sleep Off** has no undo except Terminal, so it never appears in a menu. |
| **Awake page and Advanced › Other Apps** | "Your Mac can’t sleep. This may be from an earlier lid-closed session that didn’t finish." with **Turn Sleep Back On…**, **Keep Sleep Off** and **Not Now** |
| **When Awake isn't running** | A toast with the same text. Toasts allow at most two buttons, so it has **Turn Sleep Back On…** and **Open Awake Settings…**. The leftover rows show on the Awake page **even while Awake is turned off**, because they come from the host's `LidRecovery`, not from the module. |

What the buttons do:
- **Turn Sleep Back On…** runs `LidWatchdog.restoreScript`. It is fixed, takes no arguments, and only runs `/usr/bin/pmset -a disablesleep 0`.
  - It goes through the same spawner and wrapper.
  - Its prompt is "Snaptic wants to turn sleep back on. It may have been left off by an earlier lid-closed session. Enter an administrator password to allow this."
  - Afterwards the app re-reads `SleepDisabled` and clears the journal.
  - If it can't run (the spawner refuses, say because another password dialog is still open) or its script reports an error, a toast says "Snaptic couldn’t turn sleep back on. Try again." and the rows stay. Cancel is silent (r1 C4).
  - While it waits for its password, the menus' row reads "Waiting for Password…" and is disabled, like the Awake page's buttons (r1 U7).
- **Keep Sleep Off** clears the journal and removes the rows everywhere. No prompt, no root. From then on Other Apps says: "Sleep is turned off for this Mac by another app or command. Snaptic leaves it as it is." That text replaces 0.3's "Snaptic can’t change this." everywhere.
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
- Script and command: `script(tools:period:stale:)` (default `script`), `command(args)`, `appleScript(command:prompt:)`, `startScript(args, prompt:)`.
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
- **The password advice applies to three choices.** Only enter your password right after you choose Keep Awake with the Lid Closed, Turn Sleep Back On…, or Install and Relaunch (in Snaptic's About page or in Sparkle's update window).
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
| `AwakeMenuRowsControls` | `menu.awake.lidClosed` | `.menuItem` | `when: [.awakeFeature(.lidClosed)]`; `menu: awakeMenu`. The ✓ title while on is a note, not a `when:` condition. |
| | `menu.awake.lidSubmenu` | `.menuSubmenu` | `when: [.awakeFeature(.lidClosed)]`; `menu: awakeMenu` |
| | `menu.awake.lidPreset` | `.menuItem` | `[.awakeFeature(.lidClosed), .perItem("preset")]`; `menu: lidSubmenu = MenuPlacementSpec("Keep Awake with the Lid Closed submenu", customize: .none)` |
| | `menu.awake.lidCustom` | `.menuItem` | `when: [.awakeFeature(.lidClosed)]`; `menu: lidSubmenu` |
| `StatusMenuControls` | `menu.snaptic.tabs` | `.menuTabBar` | — |
| | `menu.snaptic.showTab` | `.menuItem` | `.perItem("module")` |
| | `menu.snaptic.lidLeftover` (status), `.lidRestore` | `.menuItem` | `when: [.state(.lidLeftover)]`. Placements: "Snaptic menu", "own menus" and `MenuPlacementSpec("Awake menu", customize: .none)`. There's no Keep Sleep Off in menus. |
| `CustomSessionPanelControls` | `awake.custom.lidClosed` | `.setting` | `when: [.awakeFeature(.lidClosed)]`. The `awake.custom` surface is exempt from search. |

New `ControlState` cases: `lidModeOn`, `lidLeftover` and `bundleWritable`. All three are used above.

> **0.3.3 amendment (owner; see B1).** `awake.advanced.lidClosed` and `awake.advanced.lidBundleLearnMore` move to `AwakePageControls` as `awake.page.lidClosed` (same kind, keys, conditions and search title; no `sheet:`) and `awake.page.lidBundleLearnMore` (`.parentOn(ControlID("awake.page.lidClosed"))`). `MenuBarPageControls` adds `menubar.page.awakeLidClosed` (`.setting`, `keys: ["features.lidClosed"]`, `when: [.module(.awake), .hardware(.battery)]`, its own search entry "Keep Awake with the Lid Closed in the Awake menu"), following the precedent of one setting with a control on each page that shows it (`displays.automations.actionShowInMenu` and `menubar.customize.actions`). `replaces:` is not used: it names frozen 0.2 ids only (ControlRegistryTests), and 0.3 ids are not stored anywhere, so nothing needs mapping. The three `awake.advanced.lid*` leftover rows stay. Review round 1 adds `menubar.page.awakeLidBundleLearnMore` (`.statusAction`, `when: [.module(.awake), .hardware(.battery), .parentOn(ControlID("menubar.page.awakeLidClosed")), .state(.bundleWritable)]`), the Menu Bar copy of `awake.page.lidBundleLearnMore`.

---

## Part C: Hardware checks

These are numbered after 0.3's HW-23. The list lives here and in README's testing section.

| ID | Check |
|---|---|
| HW-24 | Tab switching in an open menu on macOS 14, 15, 26 and 27:<br>• resize and highlight;<br>• a switch with a submenu open (no `cancelTracking`);<br>• `isEnabled = false` clicks;<br>• hover look in light, dark, Increase Contrast and Reduce Transparency;<br>• a 13″ display at the largest text size, on the Displays tab with 3 external displays: switch away and back, with no stuck scroll arrows;<br>• the tab bar draws and animates the selection exactly like a stock `NSSegmentedControl` (custom cell class), in light, dark and Increase Contrast;<br>• switching tabs never changes the open menu's width (footer key column included).<br>• arrow keys over the tab-bar row (r1): highlight moves past it, and keyboard selection still reaches the section |
| HW-25 | VoiceOver, Switch Control and Full Keyboard Access:<br>• the segments are reachable;<br>• ", needs attention" and ", on" are read;<br>• VO-Down after a switch reaches the new section;<br>• the Show … Tab items appear without a relaunch;<br>• the tab row with `isEnabled = false` vs `true`;<br>• toggle Keyboard navigation alone, then Accessibility › Full Keyboard Access alone: the Show … Tab items appear for each (confirms the `com.apple.Accessibility` key);<br>• Accessibility Inspector shows the bar as a tab group "Menu tabs" with one child per segment, and no `NSSegmentedControl` or AppKit segment elements;<br>• VO-Space on a segment switches the tab. |
| HW-26 | ⌘1–⌘3 in an open menu: does tracking end, and does the next open show the chosen tab? ⌘, and ⌘Q still fire. |
| HW-27 | Sliders and switch headers in a newly shown tab work without reopening. |
| HW-28 | The osascript admin dialog from a Developer ID-signed **and** an ad-hoc Snaptic, each disclaimed and not:<br>• requester name, icon and title;<br>• prompt text;<br>• Touch ID;<br>• Cancel → `err -128`;<br>• no Automation consent;<br>• Displays' dimming overlays move behind it.<br>• osascript ignoring SIGTERM while the password dialog is up, and the SIGKILL 5 s later (r1 S5)<br>• the password dialog comes to the front when lid-closed mode or Turn Sleep Back On… is chosen from the menu (r1 U7) |
| HW-29 | Captured output of `notifyutil -g com.apple.system.thermalpressurelevel`, `pmset -g batt`, `pmset -g` and `ioreg -r -n IOPMrootDomain -d 1`, on Apple silicon and Intel, macOS 14, 15, 26 and 27. These are golden fixtures for the parsers. |
| HW-30 | Lid closed on battery:<br>(a) a Keep Display On session with no external display;<br>(b) `caffeinate -d` running in another app;<br>(c) one external display with Keep Display On.<br>Check that:<br>• the Mac stays awake;<br>• the built-in panel goes dark within 35 s in (a), and the external display stays on in (c);<br>• Apple menu › Sleep is greyed out;<br>• the panel wakes on lid open;<br>• the keyboard backlight is recorded;<br>• the indicator's lid glyph is recorded. |
| HW-31 | Watchdog behaviour:<br>• osascript returns within 1 s;<br>• `ps -p <pid> -o comm,ruid,uid` shows `sh 0 0`;<br>• it survives osascript's exit and a SIGTERM to osascript;<br>• `ps -o pgid` of the watchdog is osascript's pid, not Snaptic's group, and ^Z in the terminal that started a debug build doesn't stop it;<br>• `/usr/bin/stat -f '%HT %u'` prints `Regular File <uid>` for the beacon, and `stat -f %d` of `/var/folders` and of `D` match (else the mode never turns on).<br>Each of these restores sleep (`pmset -g`):<br>• quit;<br>• `kill -9` of Snaptic;<br>• SIGSTOP of Snaptic for 30 s;<br>• the stop file;<br>• the cap;<br>• deleting the beacon in a tight loop (within 10 s);<br>• an induced script error;<br>• `sudo kill -TERM` of the watchdog.<br>Restart with the lid shut (Apple menu › Restart… over Screen Sharing, mode on): the Mac restarts and doesn't go to sleep on the way. Snaptic's quit writes the stop file before launchd's SIGTERM, so the watchdog may take its normal exit; the `halt-<token>` file written at that quit (after `NSWorkspace.willPowerOffNotification`) makes `cleanup` skip `sleepnow` (r2 A2-5, fixed in r3). This row confirms it, and Log Out… with the lid shut likewise doesn't sleep the Mac.<br>• the A2-3 residual: a new request within ~0.1 s of a superseded password acceptance ends with sleep back on (r3)<br>• `/bin/sh` pointed at zsh (`sudo ln -sf /bin/zsh /private/var/select/sh`, test machine only; put it back to bash afterwards): the watchdog still restores sleep on every exit (r3 security)<br>• a restart or log out cancelled by another app after `willPowerOff`, then a quit with the lid shut: record whether `sleepnow` is skipped (r4 C4-4, accepted for 0.3.1) |
| HW-32 | Restart while on: `SleepDisabled` persists; the leftover rows appear in every menu with Awake turned off; Turn Sleep Back On… and Keep Sleep Off both work. |
| HW-33 | The battery floor restores sleep while Snaptic is SIGSTOPped. |
| HW-34 | The cap, the battery floor and heat, each ending with the lid closed on battery and no display: the Mac is asleep within 30 s (`pmset -g log`), including right after a cap end. |
| HW-35 | Watchdog cost: `powermetrics` wakeups at a 5 s period. |
| HW-36 | Updates (Part E):<br>• Sparkle loads in a Developer ID build;<br>• update 0.3.1 → 0.3.2 from a user-owned and from a root-owned copy;<br>• Accessibility and Screen Recording survive;<br>• no Gatekeeper prompt after relaunch;<br>• an update is refused with a wrong EdDSA signature and with a non-Developer-ID build;<br>• deferral works while lid-closed mode is on and while a display trial is pending. |
| HW-37 | An ad-hoc local build (`build-app.sh` without an identity) launches without Sparkle, and Check for Updates… opens the Releases page. CI covers part of this with `--selftest-launch`, and `rehearse` launches an ad hoc copy of the release bundle with Sparkle loaded (r3 C3-3). |
| HW-38 | Updates, continued:<br>• Open at Login across the ad-hoc → Developer ID switch (no stale or duplicate Login Items entry);<br>• a tampered `appcast.xml` (edited release asset) is rejected by the client;<br>• a root-owned copy stays `root:wheel` after an update;<br>• record the authorization right Sparkle registers for root-owned installs;<br>• gentle reminders: the menu row appears and brings Sparkle's window forward;<br>• no Sparkle window during onboarding or Safe Mode;<br>• a manual check works in Safe Mode;<br>• Relauncher with a pending install-on-quit installs and relaunches once; record how often Sparkle's install block is already gone at relaunch time (then the quit-first toast shows);<br>• the 0.3.0 → 0.3.1 re-grant for Accessibility and Screen Recording;<br>• with an install waiting (Restart to Update Snaptic…), open Sparkle's window from the row and choose Skip This Version: the row goes away and Restart in Safe Mode… then Leave Safe Mode relaunch normally (r2 C2-4); repeat with Install on Quit: the row stays and the relaunch asks to quit first;<br>• with lid-closed mode on, choose Install and Relaunch in Sparkle's window (r3 U3-4): record what Sparkle's window shows while the relaunch is held; Snaptic's toast, menu row and About say "Snaptic will restart and install version … when lid-closed mode ends."; when the mode ends Snaptic restarts into the new version within about 5 s;<br>• with a downloaded update waiting and lid-closed mode on, the line reads "…will install when you quit or restart Snaptic after lid-closed mode ends." and, after the mode ends, Restart to Update Snaptic… installs it (r3 A3-2);<br>• a new user who first ran an ad hoc build sees the 0.3.1 card's update question on the first signed build (r3 C3-5).<br>• the resumed `.installing` reminder path keeps its menu row (r1 C1)<br>• cancelling a resumed install or its authorization; Sparkle errors 4007 and 4008 clear the wait (r2 C2-4) |

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
   - **Cross-team menu hooks** (code r4 M2):
     - `static StatusMenu.leftoverItems(host:) -> [NSMenuItem]` and `static StatusMenu.updateItems(host:) -> [NSMenuItem]`, which T-lid-app's `IndicatorController` calls from `menuNeedsUpdate` on every open (`CustomItemRow`'s `leftover` and `updateAvailable` flags were removed in f618aa6: nothing needs them);
     - `ModuleHost.lidRecovery` and `ModuleHost.updater` are declared by the lead in Step 0. After that, T-lid-app fills in the recovery and T-update fills in the updater.
   - **Self-test:** the `--selftest-launch` flag (`KitArgs`, `SnapticEntry`, `SelfTest`) and its token gate.
4. **Every A6, B7 and E7 control**, each with a stub use. The `ControlRegistry` changes (`ControlKind.menuTabBar` and the new `ControlState`s), `SettingsIndex`, every `Controls/*` table and `ControlRegistryTests` are the lead's in Step 0, then frozen.
5. **Lint changes,** all of them owned by the lead: rule 12, L16, L18, L19, and the workflow rules (E6, plus "only `publish` runs `gh release`"). After Step 0, `scripts/lint*` is frozen; teams request changes from the lead.
6. **`CODEOWNERS`** (`* @frasurebuilds`).

### Step 1 (in parallel; one owner per file)

| Team | Owns |
|---|---|
| **T-menu** | `StatusMenu.swift`, `MenuKit.swift`, `MenuTabBar.swift`, `MenuLayout.swift` and its tests, `ModuleContracts.swift`, Window Switcher's and Displays' `menuAttention` and `menuSection(tabbed:)` (in their module files), `MenuBarPage.swift` |
| **T-lid-kit** | `LidWatchdog.swift`, `AwakeLidGate.swift`, `AwakeLidPolicy.swift` and their tests; `AwakePresentation.swift` and its tests (including the `tab` style: T-menu sends requests); `AwakeSession.swift`, `AwakeSessionPolicy.swift`, `AwakeCommandGrammar.swift`, `AwakeHistory.swift`, `AwakeLogEvent.swift`, `AwakeArbiter.swift` and its tests, `ConfigAwake*.swift`, `KitBackup.swift`, `AwakeFeatureGraph.swift`, `OtherAssertions.swift`, `ConfigFixtures.swift`, and the Kit tests for all of these |
| **T-lid-app** | `LidClosedController.swift`, `LidRecovery.swift`, `HelperSpawner.swift`, `SNProcess.*` / `SNSpawn.*` (if needed), `SessionController.swift`, `AwakeAutomation.swift`, `AwakeMenuRows.swift`, `IndicatorController.swift`, `AwakeModule.swift` (including `menuSection(tabbed:)`), `AwakeRuntimeState.swift`, `AwakeContext.swift` / `AwakeContracts.swift`, `AwakeAdvancedSheet.swift`, `AwakeStatusSection.swift`, `AwakePage.swift`, `CustomSessionPanel.swift`, `OtherAssertionsReader.swift`, `OtherAssertionsSection.swift`, `SystemEventsMonitor.swift`, `ActivitySimulator.swift` (only if HW-30 needs it), `HistoryController.swift`, `AwakeHistoryPage.swift`, `AwakeDiagnostics.swift`, `AppDelegate.swift` (except the Part E hunk), `EmergencyActions.swift`, and the Kit Permissions copy file (the bundle strings) |
| **T-update** | Part E:<br>• new files: `UpdaterController.swift`, `UpdatePolicy.swift` with `UpdateStatusText` and `UpdateDefaultsKeys`, and their tests;<br>• build and release: `Package.swift` with `Package.resolved`, `scripts/build-app.sh`, `scripts/make-dmg.sh` (an optional app-path argument already exists), `.github/workflows/build.yml`, `Resources/Info.plist`, and the self-test implementations behind `--selftest-launch` (`SelfTest*.swift`);<br>• app: `AboutPage.swift` and `AboutPageControls.swift`, `Relauncher.swift`, `ModuleHost.swift` (all of it after Step 0: `updater`, Reset of the `SU*` keys, `SnapticLastRunVersion`), the Part E hunk of `AppDelegate.swift` (landed as a stub call in Step 0), the onboarding updates step, the 0.3.1 welcome card (`GeneralPages.swift`, `ConfigMigrations.swift`), and the Screen Recording re-grant (`KitHostUI.swift`, `PermissionFlow.swift`, `PermissionsPage.swift`) |
| **T-docs** | `README.md`, `site/index.html`, `THIRD_PARTY_NOTICES.md`, the design-spec amendments, and the release notes |

### Step 2

1. Merge, then CI and `lint --strict`.
2. At least four adversarial review rounds on the code: security (lid **and** updates), Awake correctness, menu UX and accessibility, and code and consistency. Each round is followed by fixes.
3. 0.3.1 in Info.plist, open a PR into main for the owner, no tags.
4. The owner adds the `release` environment secrets (E3). The first signed release is cut by the owner's tag.

---

## Part E: In-app updates (Sparkle 2, Developer ID)

### E0. What the owner has already set up (2026-10-19, 09:45–10:15)

**Certificate and notarization key**
- **Signing certificate:** "Developer ID Application: Sean Frasure (7TFS5G4532)", created in Xcode under team "Sean Frasure". It expires **2027-02-01**.
  - Apps signed with secure timestamps before then stay valid.
  - Releases after that date need a renewed certificate.
  - The release notes and README name the developer as "Sean Frasure".
- **Notarization key:** App Store Connect Team Key "Snaptic notarization", **Developer** role, Key ID `BP28BZAFK8`.

**GitHub environments.** Each environment allows deployments only from `v*` tags and requires the owner (`frasurebuilds`) to approve every run; administrators can't bypass that approval.

| Environment | Secrets |
|---|---|
| `release` | `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_P8` |
| `appcast` | `SPARKLE_ED_PRIVATE_KEY` (a 32-byte Ed25519 seed, base64) |

**Tag ruleset "Release tags".** Only repository admins can create, update or delete `v*` tags, and force pushes are blocked.

**EdDSA public key** (`SUPublicEDKey`): `P/QyXVQX6nBYXfuNXlR8trb8+r8A5zyYAQEVyYucW4k=`.

**Still pending on the owner's side**
- Accept the Apple Developer Program License Agreement. Notarization fails until it's accepted.
- Optionally, add a `main` branch ruleset that blocks force pushes and deletion and requires pull requests.
- **The owner's GitHub account alone can publish a release** (fix round r3 S3-3): `frasurebuilds` is the only reviewer of both environments, the only role that may create `v*` tags, and may bypass the `main` ruleset, and deployment approval works through the REST API with the reviewer's own token. So:
  - passkey or hardware-key two-factor sign-in on `frasurebuilds`;
  - no classic PAT and no `gh` token with `repo` scope stored on the Mac used for development (fine-grained tokens without Administration or Deployments, or `gh auth logout` when not releasing);
  - email notifications for tag pushes and deployment reviews;
  - optionally, a wait timer on `appcast` (for example 15 minutes), so a rogue approval can still be cancelled.

### E1. What the user sees

**Settings › About › Updates** (a new section on the About page, under the version)
- **Check for Updates…** keeps its existing button, `about.page.checkUpdates`. It now calls `updater.checkForUpdates()` when Sparkle is present, and opens the Releases page otherwise.
- `ToggleSetting(L("Check for updates automatically"), help: L("Once a day, Snaptic checks GitHub for a newer version. GitHub sees your IP address and macOS version, nothing more."))`
- `ToggleSetting(L("Download and install updates automatically"), help: L("Updates download in the background and install the next time Snaptic quits."))`
  - It's a dependent row, shown while checks are on.
  - It's hidden for root-owned copies. Those copies always ask for an administrator password through Sparkle's installer, so installing only follows an explicit **Install and Relaunch**. The row explains this instead: "Only an administrator can change this copy of Snaptic, so each update asks for an administrator password."
- **Status row** (Kit `UpdateStatusText`), one of:
  - "Last checked today at 9:12 AM", "…yesterday at 9:12 AM" or "…on Oct 12" (hand-formatted, N12);
  - "Not checked yet";
  - "Checking…";
  - "Snaptic couldn’t check for updates. Check your connection and try again.";
  - "Version 0.3.2 is available." (found, not downloaded) with **Install and Relaunch…**;
  - "Version 0.3.2 is ready to install." with **Install and Relaunch…**;
  - "Automatic checks are off." (after Not Now);
  - a deferral line (E4).
- **Builds from source** (no Sparkle): both toggles are hidden, and the row says "This copy was built from source, so it can’t update itself. Download Snaptic from GitHub Releases to get updates."

**Consent, in Snaptic's own UI.** Snaptic never shows Sparkle's own permission prompt: Snaptic sets `updater.automaticallyChecksForUpdates` before Sparkle would ask.
- **New users** see an onboarding step, "Keep Snaptic up to date", with **Check Automatically** and **Not Now**.
- **People upgrading from 0.3.0 or earlier** (0.2 and 0.1 too; fix round r2 C2-1) see the 0.3.1 welcome card (E1a). For all of them 0.3.1 is one last manual download (fix round r3 U3-5).

**Update alerts.** A menu-bar app's alerts can appear behind other windows, so Snaptic uses Sparkle's **gentle reminders**: `SPUStandardUserDriverDelegate.supportsGentleScheduledUpdateReminders = true`.
- When an update is found, a footer row shows **"Update Available: Snaptic 0.3.2…"**. Once it has downloaded and automatic install is on, the row becomes **"Restart to Update Snaptic…"**.
  - **Where:** the shared footer, directly above Snaptic Settings…. In own-icon and Awake menus it shows only where they already carry the shared footer.
  - **Order in the first group:** Safe Mode rows, then the leftover rows. The update row is footer-only.
  - **Gate:** `.state(.updateAvailable)`.
- That row and the About status row bring Sparkle's window forward with `NSApp.activate`.
- The window never appears while onboarding is showing or while in Safe Mode.

**After any Sparkle install,** a toast appears once per version on the next launch: "Snaptic was updated to 0.3.2." with **What’s New**, which opens the release notes in the browser. Sparkle's `updater(_:didFinishInstallingUpdate:)` path records the version. A manual install shows nothing.

**Deferral texts** (Kit `UpdatePolicy.text`, tested; the one wait rule is `UpdatePolicy.decide(.installNow, …)`, and only a downloaded update waits: one that isn't downloaded still reads "Version 0.3.2 is available." with Install and Relaunch…, which opens Sparkle's window; fix round r2 C2-3). Nothing runs the install block when the wait ends: the update installs at the next quit, or when the user restarts Snaptic or chooses "Restart to Update Snaptic…" again, so the text says so (fix round r3 A3-2):
- "Version 0.3.2 will install when you quit or restart Snaptic after lid-closed mode ends."
- "…when you quit or restart Snaptic after the display change is kept or undone."
- "Updates are paused in Safe Mode. Choose Check for Updates… to update anyway."

**A held relaunch** (`UpdatePolicy.relaunchText`; fix round r3 U3-4): after Install and Relaunch in Sparkle's own window, `shouldPostponeRelaunchForUpdate` holds the relaunch (E4), and this one does go ahead by itself once the wait ends. A toast says so once, and the menu row and About keep the update (`UpdateSession.relaunchHeld`, which Sparkle's window closing doesn't clear) with the same line:
- "Snaptic will restart and install version 0.3.2 when lid-closed mode ends."
- "…when the display change is kept or undone."

**A feed version that isn't plain** (`UpdatePolicy.isVersion` fails, e.g. "0.4" or "0.3.2-b1"; fix round r1 U5): the texts drop the version instead of saying "a new version" mid-sentence: "Update Available: Snaptic…", "A new version is available.", "A new version is ready to install.", "The update will install when you quit or restart Snaptic after lid-closed mode ends." (and "…after the display change is kept or undone."), "Snaptic will restart and install the update when lid-closed mode ends."

If the user clicks Install and Relaunch while something defers it, a toast gives the same reason.

**Release notes** are embedded in the appcast as Markdown (`sparkle:format="markdown"`) from `docs/design/<version>/RELEASE-NOTES-<version>.md`. Sparkle shows them in its window, and nothing is fetched from github.com to render them. A **Full Release Notes** link (`sparkle:fullReleaseNotesLink`) opens the browser.

### E1a. The 0.3.1 welcome card and onboarding step (round-4 parity M1, design R4-m2)

**Detecting an upgrader.** 0.3.0 stores no last-run version.
- A new migration marker, `MigrationID.v031Welcome`, is recorded the first time 0.3.1 runs.
- The user counts as an **upgrader** when the `SnapticModulesV1` defaults key already existed before that marker, or `SnapticDidLaunchBefore` is set (a 0.1 or 0.2 user: their upgrade defaults skip onboarding, so the card is where they're asked; Kit `MigrationLedger.isV031Upgrader`, fix round r2 C2-1). Otherwise they are a **new user**.
- A new user is done with the card at once only in a build whose updater gate is open, where onboarding asks them. A new user whose first 0.3.1 was an ad hoc or source build keeps the card due, so their first signed build shows it in General (Kit `recordV031Welcome(upgrader:canAsk:)`; fix round r3 C3-5).
- From 0.3.1 on, a `SnapticLastRunVersion` key (`CFBundleVersion`) is written at every launch, so later versions can tell upgrades apart directly. It is navigation state: not backed up and not cleared by Reset.

**Upgraders, first launch of 0.3.1**
- Settings opens on General with a card at the top. This is the existing card component used for "New: Awake", and the card's controls use ids `general.page.card.v031.*`.
- **Title:** "Welcome to Snaptic 0.3.1"
- **Body:** "Snaptic is now signed by its developer, so macOS asks you to allow it again once. After this, updates keep your permissions."
- **Rows:**
  - A row for each permission the user had granted before: Accessibility and Screen Recording (KitHostUI's launched-before heuristic). Each row says "Remove the old Snaptic with −, then turn on the new one." and has **Open System Settings…** (`general.page.card.v031.openAccessibility`, `general.page.card.v031.openScreenRecording`).
  - "Keep Snaptic up to date" with **Check Automatically** (`general.page.card.v031.autoCheck`) and **Not Now** (`…notNow`), and under it onboarding's sentence, "Snaptic can check GitHub once a day and install updates when you quit it. GitHub sees your IP address and macOS version, nothing more." (`UpdatePolicy.consentDetail`, shared with onboarding; fix round r3 U3-3). Check Automatically also turns on automatic install, except for root-owned copies.
  - One line of what's new: "New in 0.3.1: tabs in the Snaptic menu, keeping awake with the lid closed, and automatic updates."
- **Dismissing:** **Done** (`…done`) hides the card. It also hides itself once the update choice is made and the permissions are working again.

**New users.** Onboarding gains a step, **"Keep Snaptic Up to Date"**:
- **Body:** "Snaptic can check GitHub once a day and install updates when you quit it. GitHub sees your IP address and macOS version, nothing more."
- **Buttons:** **Check Automatically** turns on checks and automatic install (not for root-owned copies). **Not Now** turns both off. Either button advances to the next step, like the existing permission steps' buttons. There is no separate Continue.
- **Controls:** `onboarding.updates.check` and `onboarding.updates.notNow` in `OnboardingControls`.
- **When it shows** (Kit `OnboardingUpdatesPage`; fix rounds r1 U6, r2 C2-1): in builds that update themselves, while the user hasn't answered. A first launch opens the window inside `bootstrap()`, before `startUpdater()` creates the updater, so the page joins the run when the updater starts (`Onboarding.updaterDidStart`) and at every Continue. Once in, it stays in for the run, so answering doesn't renumber Done. `--selftest-launch` checks this on the signed app.

**After Not Now,** About's status row says "Automatic checks are off.", not "Not checked yet".

### E2. Signing, notarization and the trust model

**Release builds** (`v*` tags only):
- Signed with the Developer ID certificate, the hardened runtime and secure timestamps. **No entitlements** (CI asserts this).
- Library validation stays on: Sparkle and Snaptic share the Team ID.
- Notarized and stapled, for both the `.app` and the `.dmg`.

**The designated requirement becomes Team-ID based,** so Accessibility and Screen Recording grants **survive updates**.
- `HelperSpawner` derives its child requirement from `designatedRequirementOfSelf()` (HelperSpawner.swift:456), so it is unchanged.
- **One-time reset.** 0.3.0 (ad hoc) → 0.3.1 (Developer ID) resets those grants once, because the requirement changes.
  - The 0.3.1 card guides the re-grant for **both** Accessibility and Screen Recording: "Remove the old Snaptic with − in each list, then turn on the new one."
  - The existing launched-before heuristic (KitHostUI.swift:28-30) is extended to Screen Recording.
- **Trade-off (README).** Any Snaptic build signed by this team is accepted by macOS under the same grants, including old releases. That's why only tag builds are ever signed.

**Builds that are never signed:**
- `main` and pull-request builds stay ad hoc and **don't contain Sparkle**.
- Local `build-app.sh` without `SIGN_IDENTITY` is the same.
- With `SIGN_IDENTITY="Developer ID Application: …"`, `build-app.sh` embeds and signs Sparkle.

**Trust model.** It is stated exactly as Sparkle 2.10.0 implements it (`SUUpdateValidator.m`, `SUAppcastDriver.m`, `AppInstaller.m`, `SUCodeSigningVerifier.m`; fix round r1 S2 corrected the earlier "either secret alone" wording).
- **The feed.** With `SURequireSignedFeed`, the feed must verify against the installed copy's `SUPublicEDKey`. A feed that doesn't verify is rejected, except in Sparkle's **degraded mode**: once checks have failed for `SUSignedFeedFailureExpirationInterval` (default 20 days, counted from `SUInitialFailedFeedSigningValidationDate` in Snaptic's defaults), Sparkle uses the unverified feed, drops its release notes and links, and never installs from it automatically.
- **The download** (`SUVerifyUpdateBeforeExtraction = YES`) is checked before extraction against the installed copy's key. If that fails, Sparkle's key-rotation fallback accepts an archive that is itself Developer ID-signed by the same team, which only a signed **disk image** can be (a zip has no code signature). After extraction the new app must then carry an update key that verifies the archive's EdDSA signature.
- **What each secret can do alone:**
  - The **EdDSA key** can sign a feed and an archive that every installed copy accepts.
  - The **Developer ID certificate** can't sign a feed. An update signed only with it is used only in degraded mode: after 20 days of failed checks, and only when the user installs it.
  - Sparkle doesn't check notarization, and it removes the quarantine flag.
- **What the feed signature doesn't cover.** A signed feed carries no date, so someone who controls the release or the connection can replay an older signed feed and hold copies at that version (Sparkle never installs an older one). A same-user process can backdate `SUInitialFailedFeedSigningValidationDate` and enter degraded mode at once. Snaptic keeps the 20-day default anyway: setting the interval to 0 would close that path but leave a lost key with no recovery at all.
- **The defense is custody and review.** The two secrets live in **separate** environments (E0), so one compromised environment never holds both. Both environments are tag-only and need the owner's approval for every run.
  - That protects against one leaked secret, **not against the owner's GitHub account** (fix round r3 S3-3): its browser session or a token with `repo` scope can push a tag and approve both deployments, through the REST API too, and so ship a signed, notarized, EdDSA-signed update without either secret or any `.github/` change. This is inherent to a single-owner repository; the account's protection (E0, "Still pending") is the real boundary, and the README says so.
  - Splitting the secrets doesn't stop a malicious workflow at a tag the owner approves. Also required:
    - a `main` ruleset that blocks force pushes and deletion and requires pull requests, with admins allowed to bypass so a solo owner can merge;
    - a `CODEOWNERS` file (`* @frasurebuilds`) in this PR;
    - before approving a deployment, the owner looks at the tag's diff to the previous release, including `.github/`.
- **Feed pinning.** `feedURLString(for:)` returns the constant URL, and `clearFeedURLFromUserDefaults()` runs at launch, so a `SUFeedURL` written into the defaults domain can't redirect checks.
- **Compromise runbook** (README › "If a release key leaks"; fix round r1 S2). The workflow keeps the public half of the key at its top level: `SU_PUBLIC_ED_KEY` (what installed copies trust; the `appcast` secret must be its seed, and publish verifies the feed and archive against it), `SU_NEXT_PUBLIC_ED_KEY` + `SU_NEXT_KEY_TAG` (empty except for the one rotation release), and `SPARKLE_ARCHIVE` (`Snaptic.zip` or `Snaptic.dmg`).
  - **EdDSA key leaks (still in hand).** The rotation release is EdDSA-signed with the **old** key and carries the new `SUPublicEDKey`. Sparkle prevalidates it with the old app's key and puts no condition on the new key in that path, so the zip is fine. `generate_appcast` signs an archive only when the app's `SUPublicEDKey` is the secret's key (Appcast.swift:199-209), so publish signs the archive with `sign_update` itself (fix round r3 C3-1), and `rehearse` runs this exact case on every push with a throwaway current key (E3).
    1. Generate a new key (`generate_keys --account …`, export with `-x`).
    2. One PR: Info.plist `SUPublicEDKey` and `SU_NEXT_PUBLIC_ED_KEY` = new key, `SU_NEXT_KEY_TAG` = the tag. `SU_PUBLIC_ED_KEY` and the secret stay old. `sign` refuses the tag unless the plist carries exactly the next key; any other tag fails while a rotation is set up.
    3. After it's published: the secret becomes the new seed; one PR sets `SU_PUBLIC_ED_KEY` = new, clears the next fields and sets `SPARKLE_ARCHIVE: Snaptic.dmg`. A secret that doesn't match the pin fails publish's verification.
    4. Release again within days: copies already on the new key can't verify the rotation release's feed (still signed with the old key).
    5. Copies that skipped the rotation release fail the feed check for 20 days, then (degraded mode) install the Developer ID-signed DMG, which carries an EdDSA signature by the new key. Or they reinstall by hand.
  - **EdDSA key lost.** A new key goes into Info.plist, `SU_PUBLIC_ED_KEY` and the secret at once, with `SPARKLE_ARCHIVE: Snaptic.dmg`, and stays on the DMG from then on. Every installed copy recovers only through degraded mode (20 days, user-confirmed) or a manual download, which the README and the Releases page ask for.
  - **Certificate leaks:**
    1. Revoke it in the developer account. Revoking can make Gatekeeper reject earlier downloads signed with it. Apple's revocation date rules apply, so contact Apple DTS if older builds must stay valid.
    2. Create a new one for the same team and replace the `release` secrets.
    3. Ship a release as usual: it is EdDSA-signed, so every copy accepts it, and the team is unchanged, so grants survive.
  - In every case, publish a note in the README and on the Releases page.

### E3. Release pipeline (`.github/workflows/build.yml`)

**What protects the secrets:** the environments' required owner approval and tag-only policies, together with the tag ruleset. "Never runs repository code" is only a hygiene rule, because the workflow YAML itself is repository content at the tag.

**Hygiene rules**
- `set -x` is never used.
- Every `${{ }}` value passes through `env:`; lint rejects `${{` anywhere inside a `run:` script (fix round r1 S6).
- Secrets are decoded into `$RUNNER_TEMP` with `umask 077` and removed in an `always()` step, and any derived encoding is masked with `::add-mask::`.
- No `actions/cache` in `build` (it makes the bundle `sign` signs), `sign`, `publish`, or any job they need (lint; fix round r1 S6), and no `cache` input of any spelling there (fix round r3 S3-2).
- Those jobs use only `actions/checkout`, `actions/upload-artifact`, `actions/download-artifact` and `actions/attest-build-provenance`, pinned to full SHAs; no job calls a reusable workflow or a local action; no `${{` in a `docker://` action's inputs; no `SHELLOPTS`, `BASHOPTS`, `BASH_ENV` or `ENV` in any `env:` (lint; fix round r3 S3-2: forbid what isn't used rather than analyse it).
- `pull_request_target` and `workflow_run` are forbidden (lint).
- `actionlint` runs in `kit-linux`, which `sign` needs (fix round r3 C3-2). The macOS lint installs PyYAML (one pinned release, by its wheels' hashes) and requires it, so the workflow rules never skip there either.
- The tag is validated with `^v[0-9]+\.[0-9]+\.[0-9]+$` before any use.

**Jobs.** These replace PR #2's `release` job and the old `attest` dependency. Only `publish` may create, upload to, or edit a GitHub release; a workflow lint rejects `gh release` anywhere else.

1. **`build`** runs on every push and PR, with no secrets. It compiles once and produces **two bundles**.
   - **`build/Snaptic.app`** is ad hoc, **without** Sparkle.
     - All tests, self-tests and lints run on this bundle.
     - On pushes to `main` **only**, it is uploaded as artifact `Snaptic-adhoc`, as today.
   - **Checks on every push.**
     - `otool -l` must show `LC_LOAD_WEAK_DYLIB @rpath/Sparkle.framework/…`.
     - A token-gated `--selftest-launch` starts the ad-hoc app without Sparkle far enough to build `ModuleHost` and the updater gate.
     - The B3.2 shell test runs under bash 3.2.
   - **`build/release/Snaptic.app`** is built on every push (fix round r3 C3-3). It is the same binary, and is never run or signed in `build`.
     - `ditto` copies in Sparkle from the SwiftPM binary target (`exact: "2.10.0"`).
     - Both `Versions/B/XPCServices` and the top-level `XPCServices` symlink are removed.
     - `install_name_tool -add_rpath @executable_path/../Frameworks` is applied, then `otool` asserts the result.
     - It is uploaded as `Snaptic-unsigned`.
   - **`rehearse`** (every push, no secrets, `needs: build`; fix round r3 C3-3) runs the release path without secrets, so the first tag finds nothing new but Developer ID signing, notarization and the real keys. It checks the Info.plist as the Guards do, runs `sign`'s "Check the bundle and Sparkle" and "Build the disk image", signs ad hoc in `sign`'s inside-out order (without the hardened runtime, whose library validation refuses ad hoc code), runs the helper, controls and launch self-tests with Sparkle loaded (the updater must start, r3 C3-4), and runs `publish`'s "Release notes", "Sparkle tools", "Generate the appcast" and "Verify the appcast" with a throwaway Ed25519 key as `SU_PUBLIC_ED_KEY` and the pinned key as the next key: the rotation case. Lint requires those scripts to be byte-identical to `sign`'s and `publish`'s. `sign` doesn't wait for it; `publish` does.
2. **`sign`** runs on macos-15 in environment `release`, on tags only, with `needs: [kit-linux, build]` (fix round r3 C3-2: the workflow lint, actionlint and the Linux tests gate the release too). The checkout uses `fetch-depth: 0`.
   1. **Guards.**
      - The tag must match `^v[0-9]+\.[0-9]+\.[0-9]+$`, and its commit must be an ancestor of `origin/main`.
      - The tag must equal `CFBundleShortVersionString`.
      - `CFBundleVersion` must equal major·10000 + minor·100 + patch (E4), and be greater than every `sparkle:version` in the `appcast.xml` of every published release (read with `gh api`, read-only). No published release with an appcast means the first signed release; any failed read stops the tag (fix round r1 S8: "latest" alone answered 404 for a release published by hand, which let any build number through).
      - `SUPublicEDKey` must be `SU_PUBLIC_ED_KEY`, or, in the one tag named by `SU_NEXT_KEY_TAG`, `SU_NEXT_PUBLIC_ED_KEY` (E2 runbook). While a rotation is set up, any other tag fails.
   2. **Sparkle check.** The SHA-256 hashes of `Sparkle.framework/Versions/B/{Sparkle, Autoupdate, Updater.app/Contents/MacOS/Updater}` must equal the hashes pinned in the workflow. The pins are taken from the **SwiftPM artifact zip** for 2.10.0 (checksum `17e28312…`), not the tarball.
   3. **Code signing.**
      - Create a temporary keychain and import the p12.
      - Sign inside out with `codesign -f -o runtime --timestamp -s "$IDENTITY"`: Autoupdate, then `Updater.app`, then the framework, then the app.
      - Run `codesign --verify --strict --deep` and check that the app has no entitlements.
      - **Keychain teardown.** Delete the keychain before any network step.
   4. **Notarize and staple the app** (fix round r1 S7: before the disk image, so the copy inside it carries its ticket): `notarytool submit --wait` on a zip of the app, then `stapler staple` the app, then `spctl -a -t exec -vv`, then re-zip as `Snaptic.zip`.
   5. **Disk image.** Build the DMG with **inline fixed `hdiutil` commands** from the stapled app with an Applications symlink (the same steps as `make-dmg.sh`; a step of its own, which `rehearse` runs too), then a second temporary keychain, for one step, `codesign --timestamp -s` the DMG; the keychain is deleted before the next network step. No repository script runs in `sign`.
   6. **Notarize and staple the DMG**, then `spctl -a -t open --context context:primary-signature -vv`.
   7. **Outputs.** `zip_sha256` and `dmg_sha256` become job outputs. Upload the artifact **`Snaptic-signed`**.
3. **`verify`** runs on macos-15 with no secrets, `needs: sign`.
   - Download `Snaptic-signed` and check its hashes against the outputs.
   - Check the DMG's signature and ticket, and `stapler validate` the app inside the mounted DMG.
   - Run `selftest-helpers.sh`, `--selftest-controls` and `--selftest-launch` (the updater gate must be open) on the signed app with Sparkle loaded.
4. **`attest`** runs on tags only, with `needs: sign`. It checks the hashes against the outputs, then attests the signed zip and dmg.
5. **`publish`** runs on macos-15 in environment **`appcast`**, with `needs: [sign, verify, attest, rehearse]`.
   1. **Re-check the files.** Download `Snaptic-signed`, recompute the hashes against `sign`'s outputs, and run `gh attestation verify` on both files.
   2. **Release notes and state.** Find the one notes file and its title (a step of its own, which `rehearse` runs too). If no release exists for the tag, create a **draft**. If one exists, draft or published, reuse it.
   3. **Sparkle tools.** Download the official `Sparkle-2.10.0.tar.xz` and check its pinned SHA-256. This provides Sparkle's own `generate_appcast`.
   4. **Fresh appcast.** Build the feed **from scratch for each release**, from a folder that holds only the archive named by `SPARKLE_ARCHIVE` (`Snaptic.zip`, or `Snaptic.dmg` after a key rotation, E2) and `Snaptic.md` (copied from the release notes). The previous appcast is **never** reused, so a tampered asset from an earlier release can't be re-signed into a new one. The feed lists only the current version: Sparkle needs only the newest item, and no delta updates are produced.
   5. **Generate and verify.**
      - Run `generate_appcast --ed-key-file - --download-url-prefix "https://github.com/revylfitness/snaptic/releases/download/$TAG/" --embed-release-notes --full-release-notes-url "https://github.com/revylfitness/snaptic/releases/tag/$TAG" --link https://github.com/revylfitness/snaptic <dir>`, with the seed on stdin (no key file).
      - Because the app's Info.plist sets `SURequireSignedFeed`, `generate_appcast` signs the feed.
      - `sign_update -p` signs the archive with the same seed (fix round r3 C3-1): `generate_appcast` leaves it unsigned when the app's key isn't the secret's (the rotation release). A signature `generate_appcast` did write must be identical (Ed25519 is deterministic); a missing one is added to the one enclosure and the feed is signed again with `sign_update`.
      - Verify the feed and archive signatures against `SU_PUBLIC_ED_KEY` before uploading, and check that the app carries the expected `SUPublicEDKey` (the next key in a rotation release).
   6. **Upload and publish.**
      - Upload `Snaptic.zip`, `Snaptic.dmg` and `appcast.xml` to the draft.
      - Run `gh release edit --draft=false --latest` **last**. An explicit `--latest` means a hand-made release can't take over "latest".

**Owner's release steps**
1. Merge the PR that sets the version, then run one command:

   ```
   git fetch origin && git tag vX.Y.Z origin/main && git push origin vX.Y.Z
   ```

   (A draft release on GitHub doesn't create its tag, so a draft alone triggers nothing.)
2. Approve the `release` deployment, then the `appcast` deployment, when GitHub asks.
3. CI creates the draft, attaches everything, and publishes it as latest.

Publishing a release in GitHub's UI, as for 0.3.0, also works. CI attaches the files and sets it as latest afterwards, but the website's Download link returns 404 until both approvals are done. That's why the tag push is the documented path. The build-number guard reads every published release's feed, so a hand-published "latest" without an appcast doesn't weaken it.

**Feed.** `SUFeedURL = https://github.com/revylfitness/snaptic/releases/latest/download/appcast.xml`. "latest" is the newest non-prerelease.

### E4. App integration

**`Core/UpdaterController.swift`** (the only file allowed to `import Sparkle`) wraps `SPUStandardUpdaterController`.
- **Optional at run time.** Sparkle is weak-linked with `-weak_framework Sparkle`, and CI checks the load command (E3). Every Sparkle symbol is reached only after `Bundle(identifier: "org.sparkle-project.Sparkle") != nil`. That is true only when dyld actually loaded the framework, and the check is lint-safe. Otherwise `ModuleHost.updater = nil`, and nothing calls into Sparkle.
- **The updater gate** (Kit `UpdatePolicy.gate`; fix round r1 C8): Sparkle loaded, **and** an `.app` bundle, **and** a valid 32-byte `SUPublicEDKey`. An unbundled debug run (`swift run`) can find Sparkle next to its binary but would only get Sparkle's "Unable to Check For Updates" alert, so it gets no updater. `--selftest-launch` checks the gate itself and runs `startUpdater()`: with the gate closed it must make no updater (fix round r1 C6); on the signed app it must make one whose Sparkle updater started (`UpdaterController.started`, read from `canCheckForUpdates`, because `SPUStandardUpdaterController.startUpdater()` only logs a configuration error and shows an alert a second later; fix round r3 C3-4), and an onboarding run begun before it, with the question unanswered, must then include the updates page (fix round r2 C2-1). The self-test exits before the main queue runs, so Sparkle's first update cycle (dispatched there) never starts.
- **Created only in GUI mode.** It is created in `AppDelegate`. Helper and CLI processes return before AppKit starts (SnapticEntry.swift:13-19). In a release build those processes **load** Sparkle but never use it; the README says so.

**Info.plist**
- `SUFeedURL`, `SUPublicEDKey`, `SUVerifyUpdateBeforeExtraction = YES`, `SURequireSignedFeed = YES`, `SUEnableSystemProfiling = NO`, `SUScheduledCheckInterval = 86400`.
- `SUEnableAutomaticChecks` is **not** set; Snaptic sets it at run time from the user's consent (E1).
- `CFBundleVersion` becomes an increasing integer, major·10000 + minor·100 + patch: 0.3.1 = 301 (`sign` checks it; minor and patch stay below 100).

**Delegate**
- **`feedURLString(for:)`** returns the constant URL.
- **`updater(_:mayPerform:) throws`** throws for **scheduled** checks while Safe Mode is on, and allows checks the user starts, so a crash-looping release can still be fixed.
- **`updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)`** holds the block while `UpdatePolicy` (pure Kit) says wait:
  - lid-closed mode is on, or turning on or off (`authorizing`, `verifying`, `stopping`; `UpdatePolicy.holdsUpdates`, fix round r1 C7);
  - a display trial is pending (`DisplayTransactionQueue.hasPendingTrial`), or the queue is busy.

  When the condition clears, it invokes the block. Meanwhile a toast, the menu row and About say "Snaptic will restart and install version 0.3.2 when lid-closed mode ends." (E1; fix round r3 U3-4).
- **`updaterShouldRelaunchApplication`** always returns true.
- **`updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)`** returns **YES** and keeps the block as `installBlock` while `UpdateSession.hasInstallBlock` says it is alive. Returning YES means Snaptic owns the prompt and Sparkle stops checking until quit; that is expected. The "Restart to Update Snaptic…" row runs the block, but only after `UpdatePolicy` allows it (no lid-closed mode, no display trial); if it isn't allowed, the row shows the wait text instead. With no live block, the row brings Sparkle's window forward.
  - **The session** (Kit `UpdateSession`; fix round r1 C2, S9) tracks the offer, whether an install waits for quit, and whether the stored block is still alive. Sparkle's automatic driver captures itself **weakly** in that block, so the block dies when that driver's update cycle ends (`updater(_:didFinishUpdateCycleFor:error:)`) or after it ran once. A gentle reminder in the `installing` stage marks the install as waiting, and a ready offer is never downgraded while it waits, so "Restart to Update Snaptic…" isn't lost. With no live block, the row brings Sparkle's window forward, which resumes the waiting installer. There, **Skip This Version** cancels the installer and the cycle ends without an error, so `updater(_:userDidMake:forUpdate:state:)` reports it (`UpdateSession.Event.userChose`) and the wait ends; **Install on Quit** leaves it waiting (fix round r2 C2-4).
  - **`Relauncher`** (which opens the new copy before the old one quits) asks `UpdatePolicy.relaunchRoute` (fix round r1 C3, S9):
    - nothing waits → relaunch as today;
    - an install waits, a live block, not Safe Mode → run the block: Sparkle installs and opens the new version. If Snaptic is still running 10 s later, Relauncher takes the relaunch back (`inFlight` clears) and routes again;
    - an install waits and it's a Safe Mode relaunch, or the block is gone → **nothing relaunches**, and a toast says "Quit Snaptic to finish installing the update first, then hold Shift while you open it to start in Safe Mode." (or "…, then open it again."). Sparkle's installer waits for this process's pid and then replaces the bundle, so a new instance opened first would run from the copy being replaced, and a Safe Mode relaunch must never install the update.
  - Installing at quit can't be postponed. That's acceptable, because quitting ends lid-closed mode and display trials anyway.
- **Gentle reminders and consent.** Implement `standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)` (return false; Snaptic shows its rows), `standardUserDriverWillHandleShowingUpdate(_:forUpdate:state:)` (set `updateAvailable`), and `standardUserDriverDidReceiveUserAttention(forUpdate:)` / `standardUserDriverWillFinishUpdateSession`, which clear it. `updaterShouldPromptForPermissionToCheck(forUpdates:)` returns **false**, so Sparkle's consent prompt never appears.
- **Matrix test.** `UpdatePolicyTests` covers the whole matrix as `UpdatePolicy.Event`s, as a hand-written table with count anchors (fix round r1 C9), plus the session, the relaunch routes and the gate.
- **B4's wording** becomes: "An update never *relaunches* while lid-closed mode is on. Quitting Snaptic, which also ends the mode, may install a downloaded update." 

**Shutdown before an update.** Snaptic's normal `applicationWillTerminate` runs:
- Awake sessions end (the snapshot is kept for resume);
- display trials revert;
- helpers stop;
- lid-closed mode writes its stop file.

**Defaults and caches**
- **Reset and backup.** General › Reset clears Snaptic's `SU*` keys; the key names live in one Kit enum, `UpdateDefaultsKeys`. Backups exclude them.
- **README.** "What Snaptic stores" lists the cache folder `~/Library/Caches/app.snaptic.Snaptic/org.sparkle-project.Sparkle` and the `SU*` keys.
- **Authorization right.** HW-36 records the authorization right that Sparkle registers for root-owned installs.

### E5. Network and privacy promise

**README heading** (l.576): "**Network: only for updates, and only if you allow it.**"

The README body says:
- If you allow it, Snaptic contacts GitHub (github.com and its download host) once a day, and when you choose Check for Updates….
- It downloads the signed update feed, and an update when you install one.
- GitHub sees your IP address, a Sparkle User-Agent with the app version, and your macOS version. Sparkle's system profiling is off.
- Every update must carry either a valid signature from Snaptic's update key or Snaptic's Developer ID signature, and the feed itself is signed.
- Nothing else connects, and a lint check still rejects networking APIs in Snaptic's own code.

**Other changes**
- **About footer** (AboutPage.swift:56): "Free and open source under the MIT License. Snaptic connects only to GitHub to check for updates, and only if you allow it. No analytics."
- **Site:**
  - l.502: "No tracking. Network only for updates you allow."
  - l.736 and the "Open Anyway" steps are dropped for release builds.
- **README:**
  - l.660 and 687 change;
  - l.155 gains "except Sparkle’s update cache";
  - the process list names Sparkle's `Autoupdate`, `Updater.app` and its installer password prompt.
- **THIRD_PARTY_NOTICES** (T-docs) adds Sparkle (MIT) with its copyright.
- **B6's password advice** names all three choices, as B6 now does.

### E6. Lint

**Unchanged:** the banned networking patterns.

**L19**
- `import Sparkle`, and identifiers matching `\b(SPU|SU)[A-Z]\w*` **outside string literals**, are allowed only in `Core/UpdaterController.swift`.
- `SU*` key strings are allowed only in Kit's `UpdateDefaultsKeys`.
- `Package.swift` declares exactly one dependency, `sparkle-project/Sparkle` with `exact:`, under `#if os(macOS)`.
- `Package.resolved` is committed.

**Workflow lint:** no `pull_request_target`, no `workflow_run`, no `set -x`, no cache in `build`, `sign`, `publish` or any job they need (transitively, by `needs:`): no action named for one (owner and repository compared without case), no `cache…` input that isn't `false`, and `actions/setup-go` only with `cache: false`. No `${{` inside a `run:` script or in `actions/github-script`'s inputs (fix round r1 S6). The rules read the parsed YAML (PyYAML), so a block-scalar header such as `|2-`, a multi-line plain or quoted scalar, a flow-style step or a quoted key reads as GitHub reads it; anchors, aliases, merge keys, explicit tags, repeated keys and more than one document are refused outright (fix round r2 S2-4). kit-linux installs `python3-yaml` and sets `LINT_REQUIRE_YAML=1`; a lint run without PyYAML elsewhere skips these rules with a warning. The lint's self-check pins each rule on cases it must report and cases it must let pass.

### E7. Controls

| Table | Id | Kind | Notes |
|---|---|---|---|
| `AboutPageControls` | `about.page.checkUpdates` | (exists) | Its help text changes. Its action is `updater?.checkForUpdates() ?? openReleasesPage()`. |
| | `about.page.autoCheck` | `.setting` | `when: [.state(.updaterAvailable)]`. No `keys`: stored outside Snaptic's config, like `general.page.openAtLogin`. `SearchSpec("Check for updates automatically", keywords: ["updates", "sparkle", "update"])` |
| | `about.page.autoInstall` | `.setting` | `when: [.state(.updaterAvailable), .parentOn(ControlID("about.page.autoCheck")), .state(.bundleWritable)]`. Search: "Download and install updates automatically". |
| | `about.page.installUpdate` | `.statusAction` | `when: [.state(.updateAvailable)]` |
| `StatusMenuControls` | `menu.snaptic.updateAvailable` | `.menuItem` | `when: [.state(.updateAvailable)]`. Placements: the Snaptic menu's footer, and own and Awake menus when they carry the shared footer (`StatusMenu.updateItems(host:)`, which Awake's `IndicatorController` calls on every menu open). |
| `GeneralPageControls` | `general.page.card.v031.openAccessibility`, `.openScreenRecording`, `.autoCheck`, `.notNow`, `.done` | `.button` | `when: [.state(.v031Welcome)]` |
| `OnboardingControls` | `onboarding.updates.check`, `onboarding.updates.notNow` | `.button` | |

New `ControlState` cases: `updaterAvailable`, `updateAvailable` and `v031Welcome`. B7's `bundleWritable` is shared with E7; there is no separate `userWritableBundle`.

### E8. Risks the owner accepts

- **The EdDSA key alone can publish an update; the Developer ID certificate alone only through Sparkle's 20-day degraded mode** (E2). Mitigations: separate environments, owner approval on every run, tag-only, and the ruleset.
- **Signed feeds carry no date**, so a replayed older feed can hold copies at that version, and a same-user process can start degraded mode early (E2). Accepted: the 20-day window is the only recovery from a lost key.
- **After a key rotation, copies that skipped the rotation release** recover only through degraded mode (20 days, then the DMG) or a manual download (E2 runbook).
- **Developer ID certificate expiry on 2027-02-01.** Renewing it with the same team keeps the designated requirement, so grants survive.
- **Every Team-signed Snaptic build is TCC-equivalent.** That's why only tags are signed.
- **Updating a root-owned copy needs an administrator password every time**, by Sparkle's design.
- **Helper and CLI processes load Sparkle (idle).** Loading it lazily with `dlopen` would need a rule-11 exemption; it's revisited only if HW-36 shows a cost.

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
| code nm9 (second TERM) | `cleanup` ignores a further TERM (INT and QUIT are ignored throughout, r2 S2-2) |
| code nm10 (lid availability) | Synchronous IORegistry read; recomputed on wake |

---

## §R3. r3 findings and their disposition

| Finding | Disposition |
|---|---|
| code NB1 (absent `SleepDisabled` property → `?` → exit 3) | `ksd` reads present-but-absent as 0; the app side matches; added to the shell test and the HW-29 fixtures |
| sec B1 (Sparkle accepts EdDSA **or** code signing) | E2 trust model rewritten; secrets split across `release` and `appcast` (done, E0); `SUVerifyUpdateBeforeExtraction`; compromise runbook |
| sec M1 (environment access) | E0: tag-only environments with mandatory owner approval and no admin bypass; tag ruleset (done); ancestor-of-main guard in `sign` |
| sec M2 (unsigned feed, web release notes) | Signed feed via `generate_appcast` with `SURequireSignedFeed`; embedded Markdown notes; feed URL pinned through the delegate and defaults cleared |
| sec M3 (blind job hand-off) | Pinned Sparkle hashes before signing; hashes as job outputs; `publish` needs `verify` and `attest`, and runs `gh attestation verify`; tags only; no caches |
| code NM1 (weak linking) | `Bundle(identifier:)` gate on every call; CI checks the load command; `--selftest-launch` |
| code NM2 (ad-hoc builds embedding Sparkle) | Two bundles from one compile; Sparkle only in `build/release`; new `verify` job runs the signed app |
| code NM3 (`sign` job order and paths) | Order fixed: XPCServices removed at both paths, rpath added, DMG signed, `spctl` after notarization, tag checks on tags only; `make-dmg.sh` merged |
| code NM4 (deferral APIs) | `pendingQuitInstall` via `immediateInstallationBlock` in Relauncher; postpone the relaunch only; `mayPerform` for Safe Mode; CLI-hold deferral dropped |
| parity M1 (unseen alerts) | Gentle reminders; Update Available row in menus and About |
| parity M2 (consent timing, auto-install default) | Consent asked in Snaptic's own UI (onboarding and the 0.3.1 card); auto-install on by default once allowed |
| parity M3 (root-owned copies) | Auto-install hidden for root-owned copies, with an explanation row |
| design R3-M1 (controls on About) | E7 on the About page; `about.page.*` ids; search entries; no `keys` |
| design R3-m1 (B7 gaps) | B7 rows fixed |
| design R3-m2 (four-line help) | `SettingsRowNote` |
| design R3-m3 (footer) | Footer split |
| design R3-m4 ("can’t change this") | "Snaptic leaves it as it is." |
| design R3-m5 (refusal hedge) | Hedged |
| design R3-m6 (`.lidEnded` toast) | Standard pattern |
| design R3-m7 (wait texts) | Three texts in `UpdatePolicy.waitText` |
| design R3-m8 (status row) | `UpdateStatusText` states |
| design R3-m9 (help texts) | Rewritten |
| design R3-m10 (source builds) | Toggles hidden; explanatory row |
| design R3-m11 (network copy) | E5 heading, body, About footer and site |
| design R3-m12, sec m8 (password advice) | Install and Relaunch added |
| design R3-m13 (General summary) | Moot: updates live on About |
| design R3-m14 (first-run window) | No Sparkle prompt; Snaptic asks; Sparkle's window is suppressed during onboarding and Safe Mode |
| design R3-m15 (pending row) | "Finishing Earlier Session…" |
| parity m1 (Keep Sleep Off without undo) | Settings only, not menus |
| parity m2 (toast button limit) | Two buttons |
| parity m3, code m7 (no menu item) | About button; Update Available row |
| parity m4 (web release notes) | Embedded Markdown |
| parity m5 (deferral feedback) | Toast with the reason |
| parity m6 (silent update) | "Snaptic was updated" toast |
| parity m7 (Screen Recording re-grant) | Covered in the 0.3.1 card |
| parity m8 (0.3.0 users) | Release title and notes say "one last manual download" (T-docs) |
| parity m9 (Homebrew) | README note: a future cask sets `auto_updates true` |
| sec m1 (lost key) | E2 runbook |
| sec m2 (workflow hygiene) | E3 hygiene rules; `actionlint` |
| sec m3 (seed handling) | E3 hygiene rules |
| sec m4 (Sparkle in helper processes) | Stated in E4; accepted |
| sec m5 (Team-ID TCC equivalence) | E2 and E8; tags only |
| sec m6 (key role) | Developer role (done) |
| sec m7 (Safe Mode blocks fixes) | `mayPerform` allows user-started checks |
| sec m9 (`spawnTool`) | Same checks; single flight |
| sec m10 (root-owned after update) | HW-38 |
| sec m11 (any TERM sets `HALT`) | Accepted and stated in B3.2 |
| code m1 (uid API) | `SNProcess.realUID` |
| code m2 (leftover rows as instances) | Flag plus a StatusMenu factory |
| code m3 (Full Keyboard Access) | Checked on every open |
| code m4 (shell test) | Every tool stubbed; configurable period; also on macOS |
| code m5 (built-in panel offline) | Treated as unknown; still runs |
| code m6 (L19 and strings) | Identifiers outside string literals only; `UpdateDefaultsKeys` |
| code m8 (ownership) | Part D updated |
| code m9 (appcast gap, heredoc) | Draft release published last; `generate_appcast` replaces the heredoc and python |
| code m10 (reviewers on `main`) | Tags only |

---

## §R4. r4 findings and their disposition

| Finding | Disposition |
|---|---|
| sec M (reused appcast re-signed) | The appcast is generated fresh each release from only the new archive; the old feed is never reused |
| code M1 (old jobs collide) | E3 job list rewritten: `Snaptic-adhoc` on main only, `Snaptic-unsigned`/`Snaptic-signed` on tags; PR #2's `release` job removed; `attest` needs `sign`; only `publish` runs `gh release` |
| code M2 (Step 0 gaps, owners) | Cross-team menu hooks, host properties and `--selftest-launch` in Step 0; lint scripts owned by the lead; permission and self-test files assigned to T-update |
| parity M1 (0.3.1 card) | E1a written: detection, trigger, text, controls, last-run version key |
| sec m1 (runbook archive) | The rotation release ships the signed DMG as its enclosure |
| sec m2 (revocation) | Noted in the runbook |
| sec m3 (repo script while the keychain is unlocked) | DMG built with inline commands; keychain deleted before notarization |
| sec m4 (feed signing wording) | Corrected; the feed signature is verified against the pinned key; `--full-release-notes-url` added |
| sec m5 (malicious workflow at an approved tag) | `main` ruleset and CODEOWNERS required; owner reviews the tag diff before approving |
| sec m6 (attest hashes) | `attest` checks hashes first |
| sec m7 (seed on disk) | `--ed-key-file -` (stdin) |
| sec m8 ("latest") | `--latest` set explicitly |
| code m1 (weak-load check on tags only) | Runs on every push |
| code m2 (DMG path, fetch depth) | Inline `hdiutil` on the signed app; `fetch-depth: 0` |
| code m3 (`willInstallUpdateOnQuit` semantics) | Returns YES; gated by `UpdatePolicy`; B4 wording fixed |
| code m4 (full release notes link) | Flag added |
| code m5 (gentle-reminder delegates, consent prompt) | Named in E4; Sparkle's consent prompt suppressed |
| code m6 (shell-test text, B5 signature) | Fixed |
| code m7 (hash source) | Hashes from the SwiftPM artifact |
| design R4-m1 (duplicate state) | One `bundleWritable` |
| design R4-m2 (onboarding and card copy) | E1a |
| design R4-m3 (available vs ready) | `updateAvailable` state and text |
| design R4-m4 (footer placement) | E1 |
| design R4-m5 (button title) | "Open Awake Settings…" |
| design R4-m6 (search title) | Matches the label |
| design R4-m7 (Install and Relaunch naming) | The advice names both places |
| design R4-m8 (when the updated toast shows) | Defined |
| design R4-m9 (root-owned wording) | Rewritten |
| parity m1 (Open at Login across the signing switch) | HW-38 |
| parity m2 (onboarding auto-install) | E1a |
| parity m3 (chown trade-off) | README: root-owned copies need a password per update (E1 and E8) |
| parity m4 ("Restart to Update") | E1 |
| parity m5 (Settings reachable while Awake is off) | Leftover rows show regardless of module state |
| parity m6 ("checks are off" text) | E1 and E1a |
| parity m7 (row order) | E1 |

