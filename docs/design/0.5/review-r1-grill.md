# 0.5 plan review r1: Grill (product, scope, UX)

Reviewer: Grill (product / UX). Plan under review: `docs/design/0.5/PLAN-draft.md` (draft r1, 426 lines).
Grounding: README.md, `docs/guide.md`, `site/index.html`, `docs/design/0.3/design-spec.md` (DS),
`docs/design/0.4/review-r1-grill.md` (format model), and the Snaptic sources. Everything said here about DockDoor's
behaviour comes from the plan's §1 survey. No DockDoor source was opened for this review, and nothing below quotes
it.

The owner decisions Q1–Q7 are settled, and nothing below reopens them. Each finding is about how a decision is
*carried out*: states the plan leaves out, conflicts with Snaptic's existing rules, defaults it doesn't make clear,
and user-visible strings that aren't final yet.

**Counts:** 2 Blockers (G-1, G-2), 11 Majors (G-3 to G-13), 11 Minors (G-14 to G-24).

Citation conventions:

- `PLAN:l.N` is a line of PLAN-draft.md.
- `DS:l.N` is a line of design-spec.md.
- `README:l.N`, `GUIDE:l.N` and `SITE:l.N` are lines of README.md, `docs/guide.md` and `site/index.html`.
- Code is cited as `path:line` under `Sources/`.

---

## Blockers

### G-1 · Blocker · §4.3, §4.2 header · Single-letter keys and the header's Quit button act on a panel that doesn't have keyboard focus

**Finding.** The panel is non-activating (PLAN:l.74), so the frontmost app keeps keyboard focus the whole time the
panel is up. §4.3 installs a key tap while the pointer is in the panel and handles keys with **no modifier**:

- W closes a window.
- M minimizes it.
- Q quits the app.
- Return raises a window.
- The arrow keys move the selection.
- Esc hides the panel.

A pointer resting over the panel is a normal state. People often leave the pointer near the Dock, and §4.4 keeps the
panel up for as long as the pointer stays in it. Someone who goes on typing in their document with the pointer
resting there:

- loses every "w", "m" and "q" they type. M23 even asserts that "no key reaches the frontmost app while handled".
- closes one window per "w", and **quits the hovered app with a single "q"**.
- has Return (sending a message, confirming a dialog) turned into "raise a window".
- loses Esc and the arrow keys in the app they're actually using, such as vim in Terminal or a spreadsheet.

The switcher's single-letter keys are safe only because the switcher holds the keyboard while it's open
(`SnapticKit/Config/ConfigSwitcherFeatures.swift:79–89`). DockDoor uses ⌘W, ⌘M and ⌘Q here (PLAN:l.77). The plan
drops the modifier and doesn't say why.

The header has the same problem with the pointer. The panel swaps "at once" when the Dock's selection moves
(PLAN:l.168), so the header's **Quit** button can switch to another app while the pointer is moving. A click aimed
at a card can then land on Quit for an app the user never meant to quit. The plan also doesn't cover:

- what Quit does to an app with unsaved documents;
- apps that shouldn't be quit from here, such as Finder.

**Evidence.**
- PLAN:l.74, l.77, l.168, l.180, l.193–197, l.383 (M23), l.384 (M24).
- `SnapticKit/Config/ConfigSwitcherFeatures.swift:79–89` and `:100–104`: the switcher's keys work only while it's
  open.
- DS:l.666 (destructive buttons name what they do) and DS:l.671 ("click" for the pointer, "press" for keys).

**Proposed plan text (§4.3: replaces the keys row and the paragraph after the table).**

> | Keys while the pointer is in the panel | ⌘W closes the window under the pointer (or the selected card), ⌘M minimizes it, ⌘H hides the app, and ⌘Q quits the app. Esc hides the panel. ←/→ (↑/↓ on side Docks) and Return work only in keyboard mode (below). |
>
> **Keys need intent.** The tap handles a key only when the pointer is in the panel **and** has moved inside it
> since the panel appeared, or since the last key the tap let through.
>
> - A key the tap doesn't handle (typing) passes through untouched, and key handling stops until the pointer moves
>   again.
> - Letters with no modifier are never handled.
> - Keyboard mode starts with the first arrow key pressed under this rule, and ends when the pointer moves. While
>   it's on, Return raises the selected card.
>
> This is `DockPreviewPolicy` logic in Kit, with a test table.
>
> **Quit** uses `NSRunningApplication.terminate()`, never `forceTerminate()`, so the app asks about unsaved
> documents itself; Snaptic doesn't wait for the answer. Finder has no Quit: the header button, the right-click item
> and ⌘Q are all left out for it. ⌘Q acts only on the app being previewed, never on the frontmost app.
>
> Feature switch: **“Keyboard shortcuts in previews”** (default on). Help: **“Press ⌘W to close, ⌘M to minimize, ⌘H
> to hide, or ⌘Q to quit what’s under the pointer.”**

**Proposed plan text (§4.2: the header bullet).**

> A header with the app's icon and name, the window count (G-24), and two buttons, **Hide** and **Quit**. The
> buttons have the tooltips “Hide Safari” and “Quit Safari”, using the app's name. The header sits on the edge of
> the panel **away from the Dock**, so the pointer doesn't cross it on the way in. Hide and Quit ignore a click that
> comes within 0.3 s of the panel appearing or switching apps (a Kit rule, with a test), so a click aimed at the
> previous app never lands on the new one.

**Proposed plan text (§7).**

> M23 becomes: “Keys in previews: ⌘W, ⌘M, ⌘H, ⌘Q, Esc, the arrow keys and Return. Typing with the pointer resting in
> the panel reaches the frontmost app unchanged, including W, M, Q, Return, Esc and the arrow keys.”
>
> New check: “Quit from the header an app that has an unsaved document: the app asks to save it.”

---

### G-2 · Blocker · §4.7, §4.8, §4.9, §4.10, §4.14, §8 · A module that's on can do nothing and never say why: there's no state table for Settings, the Snaptic menu and the CLI

**Finding.** Dock Previews has more ways of not working than any earlier module, and the plan mentions most of them
only in passing:

| State | Where the plan mentions it | What it says the user sees |
|---|---|---|
| No Accessibility | §4.7 (PLAN:l.231) | "Needs Accessibility", "starts nothing" |
| No Screen Recording | §4.7 (l.232–233) | "Allow Screen Recording to see thumbnails" |
| Another Dock tool is running | §4.8 (l.237) | "Paused while DockDoor runs" |
| VoiceOver is on | §4.10 (l.251) | Nothing; it "pauses" |
| Paused from the CLI | §4.14 (l.288) | Nothing |
| Safe Mode | M33 (l.393) | "doesn't start" |
| Kill switch | H6 (l.151) | Nothing |
| Dock not readable | §8 (l.402) | "reports 'Dock not readable' and does nothing" |
| Click tap tripped its breaker | §4.9 (l.245) | "with a row text", but no text is given |
| An app's AX calls stall | §4.6 (l.224) | Titles only |

In three of these states (Dock not readable, VoiceOver, CLI pause) the switch stays on, nothing happens when the user
points at the Dock, and no row anywhere says why. Other states have strings that break DS rules:

- "Needs Accessibility" uses the pane's name from before macOS 27.
- "Allow Screen Recording to …" is the form DS:l.669 forbids.

The rest have no string at all.

"Starts nothing" also conflicts with how Snaptic reports a missing permission. The Permissions page names only modules
that are *running* (`Snaptic/Core/PermissionsPage.swift:117–123`). A Dock Previews that never starts is never
"Needed by" anything, so the Permissions page gives the user no way back to it.

Hidden Icons, the newest module, solves this with:

- one status function that picks the single most important row (`IconsPageRules.status`);
- a CLI `state` that matches it (`SnapticKit/IconsCommandGrammar.swift:32`).

Dock Previews needs the same, settled before A4–A9.

**Evidence.**
- PLAN:l.151, l.224, l.231–233, l.237, l.245, l.251, l.288, l.393, l.402.
- `Snaptic/Core/PermissionsPage.swift:117–123`.
- `Snaptic/Icons/IconsModule.swift:169`: Safe Mode is `ModuleState.degraded("Paused in Safe Mode")`, and the module
  still counts as running.
- `Snaptic/Switcher/SwitcherPages.swift:106–129`: the switcher's two permission rows, each with
  [Open Privacy Settings…].
- `Snaptic/Core/PermissionFlow.swift:264–270`: `paneName`, which is "Device Control and Data Access" on 27.
- `Snaptic/Core/ModuleContracts.swift:113–116`: the attention mark ignores steady pauses.
- `SnapticKit/IconsCommandGrammar.swift:32` and `:61`: the CLI's "paused while another menu bar app hides icons"
  names no app.
- DS:l.640–647, l.669, l.672.

**Proposed plan text (new §4.16 "States": one `DockPageRules.status` function in Kit, where the first row that
applies wins).**

> | # | State | Module | Settings row (top of page) | Snaptic-menu section | `snaptic dock status` |
> |---|---|---|---|---|---|
> | 1 | Kill switch `Modules.disable.dockPreviews` | Not started | The existing `DefaultsLockRow(module:)` | — | The house “Unknown command” (G-14) |
> | 2 | Off | Not started | `FeatureHighlights` (G-5) | — | The house “Unknown command” |
> | 3 | Safe Mode | Running, `.degraded`; creates nothing | **“Paused in Safe Mode”** | “Paused in Safe Mode” (disabled item) | `state: paused`, `reason: safeMode` |
> | 4 | No Accessibility | Running, `.degraded`; creates nothing but the permission watch | **“Dock Previews needs \(paneName(.accessibility)) to read the Dock.”** [**Open Privacy Settings…**] (warning) | **Open \(paneName) Settings…** (attention mark) | `needsPermission` |
> | 5 | Dock not readable (S0-1's tree is missing, or 3 re-attaches in a row fail) | Running, `.degraded`; the observer is retried on every Dock relaunch | **“Dock Previews can’t read the Dock. It tries again when the Dock restarts.”** [**Try Again**] (warning) | “Can’t Read the Dock” (disabled; attention mark) | `unavailable`, `reason: dockUnreadable` |
> | 6 | A known Dock tool is running and Run Both is off | Running, paused | **“Paused while DockDoor runs”** (the tool's name comes from `KnownDockTools`) [**Advanced…**] | “Paused While DockDoor Runs” | `paused`, `reason: otherApp` |
> | 7 | VoiceOver is on and “Show previews while VoiceOver is on” is off | Running, paused | **“Paused while VoiceOver is on”** [**Advanced…**] | “Paused While VoiceOver Is On” | `paused`, `reason: voiceOver` |
> | 8 | Paused from the menu or the CLI | Running, paused | **“Paused until 3:45 PM”** [**Resume**] | “Paused Until 3:45 PM”, then **Resume Dock Previews** | `paused`, `reason: command`, `until` |
> | 9 | Working | Running | None | The section in G-3 | `on` |
>
> The following rows are *added* below the status row while they apply; they never replace it.
>
> - **Thumbnails on, but no Screen Recording.** **“Thumbnails need Screen Recording. Until then, previews show window
>   titles.”** [**Open Privacy Settings…**] (warning). The CLI reports `thumbnails: false`. Pointing at the Dock
>   never brings up a prompt.
> - **The click tap tripped its breaker.** **“Dock click actions stopped because macOS turned them off 3 times.
>   Relaunch Snaptic to use them again.”** [**Relaunch Snaptic**] (warning; attention mark in the menu). The CLI
>   reports `clickActions: stopped`.
> - **An app's windows couldn't be read in time.** No row. That app's cards show titles (§4.6), and diagnostics
>   count it.
>
> The menu's attention mark (`menuAttention`) is on only for rows 4 and 5 and for the breaker. Pauses are steady
> states and don't count.
>
> In row 4 the module is *running* as far as the host is concerned, so the Permissions page names it (“Needed by
> Dock Previews”) and its re-add steps apply.
>
> `snaptic dock status --json` fields: `state`, `reason`, `until`, `observerAttached`, `thumbnails`,
> `clickActions`, `cacheEntries`, `cacheBytes`. These are counts and booleans only (§4.15). They never include an
> app's name, so the `otherApp` reason doesn't name the tool.
>
> M27 checks each row. M33 becomes: “Safe Mode: the page reads Paused in Safe Mode; there is no observer, tap or
> panel.”

---

## Majors

### G-3 · Major · H1, Menu Bar page, Snaptic menu · `[.inSnapticMenu, .hidden]` with default `.hidden` is right, but the fallback, the only-module case and the menu section aren't specified

**Finding.** The allowed set and the `.hidden` default are right. Dock Previews works from the Dock, so a new menu
bar icon would only add clutter, and most people who turn it on already have a Snaptic icon. Four things around that
choice are either missing or wrong today.

1. **Fallback.** `MenuPresence.fallback(for:)` returns `.ownIcon` for every module except Hidden Icons
   (`SnapticKit/KitModules.swift:110–114`).
   - `sanitized()` would turn a bad stored value into `.ownIcon`. Dock Previews doesn't allow that, and has no
     status item for it.
   - `ownIconIDs` would then treat it as an own icon (`MenuLayout.swift:322–333`: "anywhere else it is an
     unsanitized value and means an own icon").
2. **Only Dock Previews on.** A new user who picks only Dock Previews in onboarding gets `everythingHidden`
   (`MenuLayout.swift:314–315`), which means no Snaptic icon at all.
   - Onboarding's last step then says "Snaptic is in the menu bar. To change settings later, choose Snaptic
     Settings… from its menu" (`Snaptic/Core/Onboarding.swift:353`). That's false.
   - The Menu Bar page's warning says "shortcuts keep working" (`Snaptic/Core/MenuBarPage.swift:285`). Dock Previews
     has no shortcuts.
3. **Help.** The Menu Bar page's help for Don't Show is "Use the keyboard shortcut or Settings to reach it."
   (`Snaptic/Core/MenuPlacement.swift:36`). Dock Previews has no shortcut.
4. **The section.** H1 gives the module a presence in the Snaptic menu, but the plan doesn't say what's in its
   section: no rows and no attention rule. ⌘n goes by position (DS:l.557), so a Dock Previews tab is ⌘5 only when
   every module is a tab.

**Evidence.**
- PLAN:l.140–142.
- `SnapticKit/KitModules.swift:100–114`.
- `SnapticKit/MenuLayout.swift:99–106`, `:314–315`, `:322–333`.
- `Snaptic/Core/MenuPlacement.swift:30–38`.
- `Snaptic/Core/MenuBarPage.swift:283–290`.
- `Snaptic/Core/Onboarding.swift:351–361`.
- `Snaptic/Switcher/WindowSwitcherModule.swift:106–148`.
- `Snaptic/Icons/IconsMenuRows.swift:59`.
- DS:l.556–560, l.586, l.633 ("Every action must also be available from Settings or a keyboard shortcut").

**Proposed plan text (new sub-bullets under H1).**

> - `MenuPresence.allowed(for: .dockPreviews) == [.inSnapticMenu, .hidden]`, default `.hidden`.
>   `fallback(for: .dockPreviews)` is `.hidden`, and `ownIconIDs` leaves out `.dockPreviews` the same way it leaves
>   out `.hiddenIcons`. Kit tests: a stored `.ownIcon` sanitizes to `.hidden`, and `ownIconIDs` never contains
>   `.dockPreviews`.
> - **Only module.** When onboarding finishes with Dock Previews as the only module on, onboarding stores
>   `.inSnapticMenu` for it. The Snaptic icon then shows, and the last step's text stays true. Turning Dock Previews
>   on later never changes its presence.
> - The Menu Bar page's help for Dock Previews, whatever its presence: **“Previews show when you point at the Dock.
>   Change them in Settings.”**
> - When no running module has a shortcut set, the everything-hidden warning drops “; shortcuts keep working” and
>   reads **“No Snaptic icon is shown. Open Snaptic again to come back to Settings.”**
> - **Snaptic-menu section** (`DockPreviewsModule.menuSection`), in this order:
>   1. the G-2 status item, only when previews aren't working (disabled; Title Case);
>   2. **Open \(paneName) Settings…**, only while Accessibility is missing;
>   3. **Pause for 1 Hour** while previews are working, or **Resume Dock Previews** while they're paused. This is
>      one item whose label changes (DS:l.586). It gives the CLI's pause a counterpart in the app (DS:l.633).
>   4. **Dock Previews Settings…**
> - **Attention mark:** as in G-2. **Short title:** stays “Dock”. The segment's accessibility label is
>   “Dock Previews”, and its tooltip is “Dock Previews (⌘n)” (DS:l.556).
> - The docs say “⌘1, ⌘2, and so on”, never a fixed ⌘5.

---

### G-4 · Major · §4.11, §4.13, §4.6 · Dock Previews repeats switcher settings under different names, and the shared window service makes two switcher promises untrue

**Finding.** Five Dock Previews settings match settings the switcher already has, and §4.13 names them differently:

| Switcher (shipped) | Dock Previews draft |
|---|---|
| "Include minimized and hidden windows": one switch (`SwitcherPages.swift:187`) | "Minimized windows ✓, Hidden apps ✓": two switches |
| "Windows from": All Spaces / Current Space / Other Spaces (`:191`) | "Windows on other Spaces ✓" |
| "Apps with no open windows" (`ConfigSwitcherFeatures.swift:98`) | "Apps with no windows ✓" |
| "Window thumbnails" (`:95`) | "Thumbnails ✓" |
| "Window buttons on hover" (`:105`) | The switcher's hover-button style, with no setting (PLAN:l.192) |

Two switcher promises also become untrue once the window service is shared:

- **Screen Recording.** The switcher's Thumbnails detail says "Off: … Snaptic then never asks for Screen
  Recording." (`ConfigSwitcherFeatures.swift:115`). With Dock Previews' thumbnails on, Snaptic does ask.
- **The shared cache.** §4.6 shares the thumbnail cache with the switcher, which "now opens with cached thumbnails"
  (PLAN:l.226). Someone who turned the switcher's thumbnails off mustn't start seeing them because Dock Previews
  filled the cache. The plan doesn't say which module's setting wins.

The plan also doesn't say whether these settings are shared or separate. Sharing them would mean a change on one page
quietly changes the other module.

**Evidence.**
- PLAN:l.192, l.226, l.255–260, l.279–281.
- `SnapticKit/Config/ConfigSwitcherFeatures.swift:93–118`.
- `Snaptic/Switcher/SwitcherPages.swift:185–193`.
- DS:l.114 (search results show as "Title / Pane").

**Proposed plan text (§4.11: new bullets).**

> - **Each module has its own settings.** Dock Previews keeps its own copies, and nothing on one page changes the
>   other. Where both modules have a setting, Dock Previews uses the switcher's wording, so search shows the same
>   title with a different pane (“Include minimized and hidden windows / Dock Previews”).
> - **The cache never overrides a setting.** A module shows thumbnails only while its own Thumbnails setting is on
>   *and* Screen Recording is allowed. The cache is an implementation detail. Kit test: with the switcher's
>   thumbnails off and Dock Previews on, the switcher's cards have no thumbnails.
> - **Hover buttons** always show in Dock Previews; there's no setting for them there. The switcher's “Window
>   buttons on hover” switch affects only the switcher.
> - The switcher's Thumbnails detail becomes **“Off: every shortcut shows app icons, with no live preview. The
>   Window Switcher then never asks for Screen Recording.”**

---

### G-5 · Major · §4.13 · The main page has about 12 controls where DS allows about 8, and its strings, header, highlights, search and footer aren't given

**Finding.** §4.13 lists 11 controls plus the module switch, against "at most about 8 controls before Advanced…"
(DS:l.11):

- the delay;
- card size;
- order;
- four Show switches;
- Thumbnails;
- keys;
- the Dock-click pop-up;
- restore-all.

The draft strings aren't final either:

- "Show previews after: slider 0–1 s (0.2 s)" gives no format for the value text.
- "Order: Recent / Title": pop-up options are Title Case, and should name the order ("Recently Used").
- "Hidden apps" sits in a list of *windows*.
- The page has no summary, sidebar symbol, tint, off-state highlights (DS §1.2 shows 2–3), search keywords, or (?)
  link.
- "Restore Defaults" is listed under Advanced. DS puts the page's Restore Defaults… in the footer (DS:l.57), and
  every module page does that (`Snaptic/Icons/IconsPage.swift:98–101`).

**Evidence.**
- PLAN:l.275–284.
- DS:l.11, l.28–49, l.57, l.111–118, l.133, l.640–647, l.670.
- `Snaptic/Icons/IconsPage.swift:14–29`, `:72–101`, `:213–222`.
- `Snaptic/Icons/IconsPageRules.swift:245–246` and `:444–446`.
- `Snaptic/Icons/IconsPageControls.swift:17`.
- `Snaptic/Switcher/SwitcherPages.swift:187–188`.

**Proposed plan text (§4.13: replaces the list).**

> **Header.** Title **Dock Previews**. Summary **“See an app’s windows when you point at it in the Dock.”**
> Symbol and tint: G-22.
>
> **Off state** (`FeatureHighlights`, 3 rows):
>
> - **“Point at an app in the Dock”**: **“Its windows appear above the Dock, including minimized and hidden ones.”**
> - **“Click a window to bring it forward”**: **“Or close, minimize, or quit from the preview.”**
> - **“Works without Screen Recording”**: **“Without it, previews show window titles instead of pictures.”**
>
> **Status rows:** G-2.
>
> **Main section (7 controls):**
>
> | Control | Kind | Default | Help |
> |---|---|---|---|
> | **Show previews after** | Slider, 0–1 s in steps of 0.1 s. Value text “0.2 s”, or “Immediately” at 0 | 0.2 s | “How long you point at an app before its windows appear.” |
> | **Card size** | Segmented: **Small** / **Medium** / **Large** | Medium | — |
> | **Thumbnails** | Switch | On | “Shows a picture of each window. Off: titles only, and no Screen Recording needed.” |
> | **Include minimized and hidden windows** | Switch | On | “Lists windows that are minimized or belong to hidden apps.” (the switcher's wording) |
> | **Windows on other Spaces** | Switch | On | “Off: only windows on the current Space are shown.” |
> | **When you click the active app in the Dock** | Pop-up | Do Nothing | G-9 |
> | **Restore all minimized windows** | Switch | Off | G-9 |
>
> **Advanced…** (G-6): the sort order, keyboard shortcuts in previews, apps with no open windows, other Dock apps,
> VoiceOver, and Diagnostics.
>
> **Footer.**
>
> - Leading edge: **Restore Defaults…**, shown only while the module is on.
> - Trailing edge: **Advanced…** and (?). The (?) opens README `#dock-previews`.
> - The confirmation: **“Restore Dock Previews settings to their defaults?”** / **“Your preview, Dock click, and
>   Advanced settings go back to how they were when you installed Snaptic. Dock Previews stays on.”** /
>   [**Restore Defaults**] [**Cancel**].
>
> **Search.** `SearchSpec("Use Dock Previews", keywords: ["dockdoor", "hyperdock", "dock preview", "hover",
> "window preview", "thumbnail"])`. Every control above and in Advanced gets its own entry.

---

### G-6 · Major · §4.13 Advanced, §4.8, §4.10 · The Advanced sheet's rows have no strings, Restore Defaults is in the wrong place, and "grace time" shouldn't be a setting

**Finding.** The sheet is given as "grace time, Run Both, Show with VoiceOver, Restore Defaults" (PLAN:l.284).

- **Run Both.** Snaptic's other-app choices are a labelled pop-up whose options say what each one does. Hidden Icons
  uses "When another menu bar app hides icons" with Pause Hidden Icons / Run Both Anyway, plus a footnote while Run
  Both is chosen (`Snaptic/Icons/UI/IconsAdvancedSheet.swift:63–71`). A bare "Run Both" doesn't fit that pattern.
- **Show with VoiceOver.** The label doesn't say what is shown, and it has no help text.
- **Grace time.** It's a 0.25 s constant that §4.4's state machine and its race table depend on (K3). If the user
  can change it, the M15 "never stuck" guarantee becomes a matter of how they've set it. No one can judge a value
  measured in hundreds of milliseconds anyway.
- **Restore Defaults.** It belongs in the page footer (G-5). A sheet's own Restore Defaults resets only that sheet
  (`IconsAdvancedSheet.swift:112`).
- **Sort order, keys and no-window apps.** These move here from the main page (G-5) and need strings.

**Evidence.**
- PLAN:l.199–209, l.237, l.251, l.284, l.375 (M15).
- `Snaptic/Icons/UI/IconsAdvancedSheet.swift:21`, `:63–71`, `:94–98`, `:112`.
- `Snaptic/Displays/UI/DisplaysAdvancedSheet.swift:106–115`.
- DS:l.57, l.640–647, l.669.

**Proposed plan text (§4.13 Advanced).**

> Sheet title: **“Dock Previews Advanced Settings”**.
>
> - **Sort windows by**: a pop-up with **Recently Used** (default) and **Title**.
> - **Keyboard shortcuts in previews**: a switch, default on. Help as in G-1.
> - **Show when an app has no open windows**: a switch, default on. Help: **“Pointing at the app shows a small card
>   instead of nothing.”**
> - **When another app shows Dock previews**: a pop-up with **Pause Dock Previews** (default) and **Run Both
>   Anyway**. While Run Both Anyway is chosen, a footnote reads **“Both apps show a preview when you point at the
>   Dock, and the previews may cover each other.”**
> - **Show previews while VoiceOver is on**: a switch, default off. Help: **“Previews appear as VoiceOver moves
>   through the Dock.”**
> - **Diagnostics**: a `DefaultsLockRow(key:)` for each of `Dock.disable.clickActions` and `Dock.disable.keys`
>   while it's set (the `IconsAdvancedSheet` pattern).
> - The sheet's own `RestoreDefaults(scopeName: L("Dock Previews"))` resets only these rows.
>
> The grace time (0.25 s) and the safety net (1 s) are constants in `DockPreviewPolicy`, with no setting.

---

### G-7 · Major · H5, §4.7, onboarding · Permissions: when Snaptic asks, what the rows say, what onboarding lists, and a rule for private capture

**Finding.**

- **Onboarding.** H5 makes Screen Recording "required only while thumbnails are on", and Thumbnails defaults on. A
  user who turns Dock Previews on in onboarding should therefore be asked for both permissions, the same as for the
  switcher (`Snaptic/Switcher/WindowSwitcherModule.swift:36–40`). But onboarding's `needed` loops only over
  `[host.switcher, host.icons]` (`Snaptic/Core/Onboarding.swift:293`), so Dock Previews' permissions would be
  skipped without a word. H1's grep doesn't catch this line, because the line lists module *objects*, not
  `ModuleID` cases.
- **Pane name.** "Needs Accessibility" (PLAN:l.231) uses the name from before macOS 27. On 27 the pane is "Device
  Control and Data Access" (`Snaptic/Core/PermissionFlow.swift:264–270`).
- **"Starts nothing"** hides the module from the Permissions page (G-2).
- **"Allow Screen Recording to see thumbnails"** is the "Allow X to Y" form DS:l.669 forbids. G-2 replaces it.
- **When Snaptic asks.** The plan says only "never a prompt on hover". It doesn't say what happens when the user
  turns the module on with the page switch or the New card, or turns Thumbnails on.
- **Private capture.** S0-4 records "without Screen Recording" results for `CGSHWCaptureWindowList`. If the
  private call returns pictures without the permission, showing them would get around the user's choice in Privacy
  & Security, and the row "Thumbnails need Screen Recording" would be untrue.

**Evidence.**
- PLAN:l.16, l.150, l.231–233, l.308 (S0-4).
- `Snaptic/Core/Onboarding.swift:290–298`.
- `Snaptic/Core/PermissionsPage.swift:117–123`.
- `Snaptic/Switcher/WindowSwitcherModule.swift:36–40`, `:112`, `:140` (the guides' reason strings).
- README:l.206 ("Snaptic asks only for what the features you turned on need, and only when you turn them on").

**Proposed plan text (§4.7: replaces both bullets).**

> - `requiredPermissions` is Accessibility, plus Screen Recording while Thumbnails is on.
> - Onboarding's `needed` loops over every module with `requiredPermissions`, not a fixed list. Add this line to
>   `H1-SITES.md`. A Kit or selftest check confirms that choosing Dock Previews in onboarding lists both
>   permissions.
> - Turning the module on (switch, New card or onboarding) presents the Accessibility guide once. Its reason is
>   **“Dock Previews needs it to read the Dock.”**
> - Screen Recording is asked for only from onboarding's permission step or from the page's row. Its reason is
>   **“Pictures of your windows in Dock previews.”** Pointing at the Dock, turning the module on, and turning
>   Thumbnails on never bring up a prompt.
> - **Pictures only with permission.** Snaptic shows a window's picture only while Screen Recording is allowed for
>   Snaptic, whichever capture path S0-4 finds works. Without the permission, every card shows its title.
> - The page rows, menu rows and CLI states are in §4.16 (G-2). The Permissions page lists Dock Previews under
>   “Needed by” whenever the module is running and needs the permission.

---

### G-8 · Major · Q7, A8 · The onboarding row, the welcome text, the New card and the upgrade notes aren't written

**Finding.** Q7 asks for "a 'New: Dock Previews' card plus an opt-in onboarding row", but the plan gives no text
for either:

- The onboarding row needs a `ModuleSwitchRow.summary` case. That `switch` is exhaustive
  (`Snaptic/SettingsUI/ModuleSwitchRow.swift:23–30`), so the compiler will catch it, but the copy is missing.
- The modules step was sized for four rows: "four rows fit at the default text size"
  (`Snaptic/Core/Onboarding.swift:253`).
- The welcome text lists four things "in your menu bar" (`Onboarding.swift:227`). Dock previews aren't in the menu
  bar.
- The card needs a title, a body, buttons, a `GeneralCardRules.module(of:)` case, a `visible` rule, and an
  `act(on:)` result.
- The guide's Upgrading entries (GUIDE:l.26–30) need a 0.4 → 0.5 entry, and the 0.3.2 entry now leads to two
  cards.

**Evidence.**
- PLAN:l.26–27, l.39, l.346 (A8), l.389–390 (M29–M30).
- `Snaptic/Core/Onboarding.swift:227`, `:238–253`.
- `Snaptic/SettingsUI/ModuleSwitchRow.swift:23–30`.
- `SnapticKit/SettingsPageRules.swift:9–31`.
- `Snaptic/Core/GeneralPages.swift:117–129`, `:251–276`.
- GUIDE:l.26–30.

**Proposed plan text (A8 and D1).**

> - Onboarding and General module row, `ModuleSwitchRow.summary(.dockPreviews)`: **“Preview an app’s windows when
>   you point at it in the Dock.”**
> - Welcome text: **“A window switcher, display controls, Keep Awake, hidden menu bar icons, and Dock previews. Turn
>   on only what you want; everything else stays off.”**
> - Modules step: M29 checks that five rows fit at the default text size. At larger sizes the form scrolls, as it
>   does today. Update the code comment at `Onboarding.swift:253`.
> - Card, General page:
>   - Title **“New: Dock Previews”**.
>   - Body **“See an app’s windows when you point at it in the Dock, and click one to bring it forward.”**
>   - Buttons [**Turn On Dock Previews**] [**Not Now**].
>   - `GeneralCardRules.module(of: .dockPreviews) == .dockPreviews`, and the card is visible while the module is
>     off.
>   - Turn On opens the Dock Previews page, which then shows whatever G-2 row applies, such as the
>     “Paused while DockDoor runs” row.
>   - The card is added only to configs written by 0.4.x or earlier (the `dockCard.v1` marker). A fresh install
>     whose onboarding offered the row never gets it.
> - GUIDE Upgrading, a new first entry: **“Upgrading from 0.4: Snaptic updates itself and nothing changes until you
>   turn on Dock Previews (a “New: Dock Previews” card in General). Window Switcher thumbnails now include
>   minimized windows and windows on other Spaces when macOS allows it.”** The 0.3.2 entry gains: **“You’ll see
>   both the Hidden Icons and Dock Previews cards.”**

---

### G-9 · Major · §4.9, Q4 · Dock click actions: what users read, the default, and the cases that decide whether a click hides an app

**Finding.**

- **Wording.** "Click the frontmost app's icon" is engineering wording. The user-facing term is "the active app".
- **Default.** §4.9 says "Hide the app (default)", while §4.13 says the pop-up is "**Off** / Hide / Minimize".
  Those can't both be the default.
- **Ambiguous clicks.** The plan doesn't decide the cases where a click on the active app's icon means something
  else:
  - The app has no window on this Space, so the Dock switches Space.
  - The app has no windows at all, so the Dock asks it to open one.
  - Every window is minimized, so restore-all applies.
  - The click is the one that made the app active.
  Hiding in any of these cases would undo what the user just asked for.
- **Breaker.** The breaker's row text isn't given (PLAN:l.245).
- **Pauses.** The plan doesn't say whether the click tap pauses with the module while DockDoor runs (G-10), or
  while VoiceOver is on.

**Evidence.**
- PLAN:l.17–18, l.36, l.240–247, l.283, l.313 (S0-9), l.385–386 (M25–M26).
- DS:l.640–647 (pop-up options are Title Case), l.670 (help is one sentence of about 90 characters at most).

**Proposed plan text (§4.9).**

> - **When you click the active app in the Dock**: a pop-up with **Do Nothing** (default), **Hide the App**, and
>   **Minimize Its Windows**. Help: **“Hide works like pressing ⌘H. Minimize sends each of its windows to the
>   Dock.”** If S0-9 fails, **Hide the App** is removed and the pop-up keeps the other two options.
> - **Restore all minimized windows**: a switch, default off. Help: **“When all of an app’s windows are minimized,
>   clicking its Dock icon brings them all back.”**
> - **Resolver** (`DockPreviewPolicy`, tested with a table). It looks at the state just *before* the mouse-down:
>   - Hide or Minimize applies only if the app was already active **and** had a visible, non-minimized window on
>     the current Space.
>   - Restore-all applies only if every window the app has is minimized. It wins over Hide and Minimize.
>   - In every other case Snaptic does nothing and leaves the click to the Dock.
> - The click tap pauses with the module (G-2 rows 3–8), except for the VoiceOver pause. VoiceOver presses Dock
>   items without a mouse event, so the tap never sees those presses.
> - The breaker's row text is in G-2.
> - Snaptic never changes the Dock's own preferences (ground rules). README says so next to this setting.

---

### G-10 · Major · §4.8, S0-15 · Other Dock tools: what's detected, what the pause covers, and the "Switching from DockDoor" docs

**Finding.**

- `KnownDockTools` has no defined shape and no documented list. Hidden Icons' `KnownMenuBarHiders` stores a name, a
  bundle id, a prefix and a team id, and README and THIRD_PARTY_NOTICES name each tool (THIRD_PARTY_NOTICES.md:218).
- The pause's scope isn't stated. DockDoor also acts on Dock clicks (PLAN:l.78), so pausing only the panel would
  leave two tools reacting to the same click.
- The plan asks for no "Switching from DockDoor" page. Hidden Icons has one for Hidden Bar (GUIDE:l.453–467), and
  people moving from DockDoor will look for the same.
- Run Both has no wording (G-6).

**Evidence.**
- PLAN:l.78, l.103, l.235–238, l.319 (S0-15), l.388 (M28), l.410.
- `SnapticKit/KnownMenuBarHiders.swift`.
- `Snaptic/Icons/IconsHiddenList.swift:108`.
- `Snaptic/Displays/OtherDisplayApps.swift:66–73`.
- GUIDE:l.449, l.453–467.
- THIRD_PARTY_NOTICES.md:185–189 and :218.

**Proposed plan text (§4.8).**

> - `KnownDockTools` has the same shape as `KnownMenuBarHiders`: a name, a bundle id, an optional prefix, and a team
>   id where known. It starts with the S0-15 results. The Settings row and the menu item name the tool. CLI text,
>   logs and diagnostics never name it.
> - While Dock Previews is paused for another tool, previews, keys **and** Dock click actions are all off.
> - D1 adds two things to the guide:
>   - **“Other Dock preview apps”**, which lists the detected tools.
>   - **“Switching from DockDoor”**, a table of behaviour only (no code, no screenshots of its UI). Rows: hover
>     delay, card size, the keys in previews (⌘W, ⌘M, ⌘H, ⌘Q in both), middle-click to close, right-click menu, Dock
>     clicks (Snaptic: hide, minimize, restore all, opt-in), and the ⌘⇥ overlay and widgets (not in Snaptic; use the
>     Window Switcher's ⌘⇥ takeover). It ends: **“Quit DockDoor, or remove it from Login Items, then turn on Dock
>     Previews. Snaptic doesn’t import DockDoor’s settings.”**

---

### G-11 · Major · §4.10, §4.2, §4.4, §4.1 · VoiceOver, Full Keyboard Access, Reduce Motion, Increase Contrast and Reduce Transparency

**Finding.**

- **Keyboard users.** VoiceOver isn't the only thing that moves the Dock's selection without the pointer. ⌃F3 and
  Full Keyboard Access move it too. §4.1 rule 4 only checks how old the selection is, so a keyboard user moving
  through the Dock with the arrow keys would get previews popping up whenever the pointer happens to sit over the
  Dock.
- **Reaching the panel.** "The panel is reachable with VoiceOver when it's shown" (PLAN:l.253) doesn't say how. A
  non-activating panel isn't where VoiceOver's cursor goes by default. S0-16 records only selection events.
- **Labels.** The format "Title, App, Minimized" mixes Title Case into spoken text. The hover buttons and header
  buttons have no labels at all.
- **Reduce Motion.** "Reduce Motion: no fade" (PLAN:l.184) is stricter than DS. DS keeps short fades with Reduce
  Motion on (DS:l.219, l.715) and removes movement. The plan doesn't say whether the panel slides in, which is the
  part Reduce Motion should remove.
- **Reduce Transparency** isn't mentioned. DS requires an opaque background then (DS:l.709).

**Evidence.**
- PLAN:l.164–172, l.184, l.249–253, l.320 (S0-16), l.382 (M22).
- DS:l.138, l.219, l.513, l.557, l.709, l.715.

**Proposed plan text (§4.1 rule 5, and a new §4.10).**

> §4.1, new rule 5: previews show only while the pointer is inside the Dock's frame **and** inside the frame of the
> selected item. A selection that moves while the pointer is elsewhere (VoiceOver, ⌃F3, Full Keyboard Access) never
> shows a panel, unless “Show previews while VoiceOver is on” is on and VoiceOver is running.
>
> §4.10:
>
> - Default: paused while VoiceOver is on (G-2 row 7).
> - With the switch on:
>   - The panel posts an accessibility announcement, **“Safari, 3 windows”**.
>   - The panel is an accessibility group labelled **“Safari windows”**.
>   - S0-16 also records how a VoiceOver user moves from the Dock into the panel and back. If there's no reliable
>     way, the switch's help says so and M22 records it as a limitation.
> - Card label: **“\(title), \(app)”**, followed by **“, minimized”**, **“, hidden”**, **“, on another Space”** or
>   **“, full screen”**, all lowercase.
> - Hover buttons are labelled **“Close”**, **“Minimize”** and **“Enter Full Screen”**. Header buttons are labelled
>   **“Hide Safari”** and **“Quit Safari”**. Each label equals its tooltip (DS:l.138).
> - Reduce Motion: the panel fades in and out over 0.15 s and never slides or scales. Swaps between apps are
>   instant.
> - Increase Contrast: a 1 pt border on cards and around the panel, and a separator under the header.
> - Reduce Transparency: an opaque `windowBackgroundColor` panel.
> - README's Known limitations: **“Dock Previews works with the pointer. With the keyboard, use the Window
>   Switcher.”**

---

### G-12 · Major · §4.2, K2, M19 · "+N more" hands off to the Window Switcher, which may be off, and to a filter it doesn't have

**Finding.** Once the cards no longer fit on the screen, "a '+N more' card opens the Window Switcher filtered to that
app" (PLAN:l.181–182). Several things go wrong with that:

- The switcher may be off, stopped by its kill switch, or waiting for permission. Dock Previews has its own
  Accessibility path and doesn't depend on the switcher.
- "Filtered to that app" isn't a filter the switcher has. Its app filter is the *active* app, and the app being
  previewed isn't active.
- Opening the switcher from a mouse click also breaks its model of holding ⌥.

"+N more" isn't among Q2's items, so this can change without reopening a decision.

**Evidence.**
- PLAN:l.34, l.181–182, l.334 (K2), l.379 (M19).
- README:l.52 and l.57 ("Windows of the app you're in").

**Proposed plan text (§4.2: replaces the "+N more" sentence).**

> Past the screen's edge, cards first drop to the next smaller size. If they still don't fit, the panel scrolls:
> horizontally for a bottom Dock, vertically for side Docks, with the scroll wheel or trackpad. Every window stays
> in the panel. There's no hand-off to the Window Switcher.
>
> K2 tests the drop in size and the scroll extent. M19 becomes: “An app with 40 windows: every window is reachable
> by scrolling; apps with no open windows show their card.”

---

### G-13 · Major · H9, D1–D3 · The docs that count modules and pages go beyond H9's list, and the README section has no outline

**Finding.** H9 lists four places: "⌘1–⌘4", "eight pages", "Eight pages" and "4 modules". These also count modules,
describe Snaptic as four things, or link to 0.4:

| Where | Text now | Change |
|---|---|---|
| README:l.9 | Tagline with four phrases | Add “· Preview windows from the Dock” |
| README:l.16 | "What’s new in 0.4" | “What’s new in 0.5” → `docs/design/0.5/RELEASE-NOTES-0.5.0.md` |
| README:l.22 | "four everyday Mac utilities" | “five” |
| README:l.24–29 | A four-row module table | New row: **Dock Previews**: “Point at an app in the Dock to see its windows, and click one to bring it forward.” |
| README:l.48 | Switcher tiles | Add: “Minimized windows and windows on other Spaces get thumbnails too, when macOS allows it.” |
| README:l.202 | "(⌘1–⌘4)" | “(⌘1, ⌘2, and so on)” |
| README:l.210–211 | Permissions table | Accessibility: add “Dock Previews”. Screen Recording: “Switcher and Dock Previews thumbnails, the switcher’s preview, and Picture in Picture.” |
| README:l.241–248 | CLI examples | Add `snaptic dock pause 30m   # no Dock previews for half an hour` |
| README:l.278 | Credits | Add: “Dock Previews follows ideas from [DockDoor](https://github.com/ejbills/DockDoor) (GPL-3.0) in its own code; it shares no code with it and isn’t affiliated with it.” |
| GUIDE:l.5, l.15–24 | Module list and table | Add Dock Previews |
| GUIDE:l.24 | The “Use …” switch list | Add “Use Dock Previews” |
| GUIDE:l.34 | "eight pages" | “nine pages”, with a Dock Previews link |
| GUIDE:l.51 | Menu Bar choices | Note that Dock Previews offers only Show in Snaptic Menu and Don’t Show |
| SITE:l.702 | "8 / Eight pages." | “9 / Nine pages.” |
| SITE:l.723–750 | Four module cards | Fifth card: **Dock Previews**: “Shows an app’s windows when you point at it in the Dock. Off until you turn it on.” |
| `SettingsShell.swift:69`, `Onboarding.swift:253` | Comments: “eight roots”, “four rows” | Update (not user-visible, but stale) |

README:l.22's "No event taps, no timers, no permission prompts" describes modules that are off, so it stays true.

**Evidence.**
- PLAN:l.157–158, l.348–350.
- The lines in the table.
- README:l.170–190 (the Hidden Icons section, used as the model).

**Proposed plan text (D1: a README "Dock Previews" section after Hidden Icons, using that section's shape).**

> 1. One paragraph: “Point at an app in the Dock and its windows appear above it. Click one to bring it forward.
>    Dock Previews is off until you turn it on.”
> 2. Bullets:
>    - **Minimized, hidden, and other-Space windows**, marked on their cards.
>    - **Close, minimize, or quit from the preview**: hover buttons, a right-click menu, middle-click, and ⌘W, ⌘M,
>      ⌘H, ⌘Q.
>    - **Works without Screen Recording**: titles instead of pictures.
>    - **Optional Dock clicks**: hide or minimize the active app; bring back all minimized windows.
>    - **Never changes the Dock**: no Dock settings are touched, and thumbnails stay in memory.
> 3. A permissions sentence.
> 4. Links: **“Read more in the Dock Previews guide →”** · **“Switching from DockDoor →”**.
>
> The guide gets the full section: every setting, the states table from G-2, the CLI, the kill switches (G-20), and
> Known limitations (Stage Manager from S0-11, auto-hidden Dock from S0-7, VoiceOver from S0-16, keyboard use).

---

## Minors

### G-14 · Minor · §4.14 · CLI: the off answer, the pause duration, help lines and refusals

**Finding.** "Exit 2 with text when the module is off" matches what Hidden Icons does: its verbs are registered only
while the module runs, so an off module answers the house "Unknown command. Run “snaptic help” for the list.", exit 2
(`Snaptic/Icons/IconsCLI.swift:6`, `Snaptic/Core/SelfTest.swift:341–345`). The plan should say that this is the
text, rather than "with text". M31's "every exit-2 text" implies there are several.

`--minutes N` invents a second duration syntax. `snaptic awake pause` already takes Awake's duration words, defaults
to 1 h, and stops at 24 h (`SnapticKit/AwakeCommandGrammar.swift:49–50`, `SnapticKit/AwakeClock.swift:223–226`).

The plan gives no help lines and no text for refusals. A refusal that named the other tool would break the "no app
names" ground rule (PLAN:l.54). The Icons CLI avoids that with "another menu bar app" (`IconsCommandGrammar.swift:61`).

**Proposed plan text (§4.14).**

> `snaptic dock status [--json]`, `snaptic dock pause [duration]`, `snaptic dock resume`.
>
> - **Off, or blocked by the kill switch:** the verbs aren't registered, so the answer is the house “Unknown
>   command”, exit 2, as for Hidden Icons.
> - **pause:** uses `AwakeDurationGrammar` (“30m”, “2h”, “until 17:30”). The default is 1 h and the most is 24 h.
>   The pause isn't saved, so relaunching resumes previews. Reply: **“Dock Previews is paused until 3:45 PM.”**,
>   exit 0.
> - **resume:** **“Dock Previews is on again.”** If nothing was paused: **“Dock Previews isn’t paused.”**, exit 0.
>   If the pause is for another reason: **“Dock Previews is paused while another Dock preview app runs.”** /
>   **“… while VoiceOver is on.”** / **“… in Safe Mode.”**, exit 4.
> - Help lines:
>   - `status`: **“State, pause reason and cache counts (never names)”**
>   - `pause`: **“Pause previews for a while (1 h if no time is given)”**
>   - `resume`: **“Resume previews”**

### G-15 · Minor · whole plan · "Dock" isn't in `SentenceText.properNames`

**Finding.** `SentenceText.inSentence` lowercases a label's first letter unless the label starts with a proper name
(`SnapticKit/KitModules.swift:32–48`). The list has "Hidden Icons" and "Window Switcher" but not "Dock". Apple
always capitalizes the Dock, so a sentence built from "Dock click actions" would read "dock click actions".

**Proposed plan text (K1).** Add **“Dock”** to `properNames`; the prefix match also covers “Dock Previews”. Add a
Kit test: `inSentence("Dock click actions") == "Dock click actions"`.

### G-16 · Minor · §4.3 · The right-click menu items aren't final

**Finding.** "Close, Minimize / Restore, Full Screen, Hide App, Quit App" (PLAN:l.193) are labels, not menu items.
Menu items are Title Case and name what they do. An item whose action depends on state changes its label (DS:l.586).
The app menu's own items name the app ("Hide Safari").

**Proposed plan text (§4.3, right-click row).** The items are:

> - **Close Window**
> - **Minimize Window**, or **Restore Window** when the window is minimized
> - **Enter Full Screen**, or **Exit Full Screen**
> - a separator
> - **Hide Safari**, or **Show Safari** when the app is hidden
> - **Quit Safari**, left out for Finder (G-1)

### G-17 · Minor · §4.2 · Badge text and the "Hidden" badge

**Finding.** The badges "Minimized", "Hidden", "Other Space" and "Full Screen" have no stated case. "Full Screen" in
Title Case doesn't match the switcher's sentence case ("Full screen (F)"). When an app is hidden, every one of its
cards would show "Hidden", which is the same fact repeated on each card.

**Proposed plan text (§4.2).** Badges are status text in sentence case: **“Minimized”**, **“On another Space”** and
**“Full screen”**. For a hidden app, the header shows **“Hidden”** once, after the app's name, and the cards don't
repeat it. The badges' VoiceOver suffixes are in G-11.

### G-18 · Minor · §4.2 · The "No open windows" card has no behaviour, and the case where settings hide every window isn't covered

**Finding.** The plan doesn't say what a click on the compact "No open windows" card does. It also doesn't cover an
app that *has* windows, all of them hidden by the user's settings: all on other Spaces with that setting off, or all
minimized with minimized windows excluded. In that case "No open windows" would be wrong.

**Proposed plan text (§4.2).**

> - **“No open windows”** (sentence case): the app has no windows. Clicking the card activates the app, as a Dock
>   click would.
> - **“No windows shown”**, with the tooltip **“Its windows are minimized, hidden, or on other Spaces.”**: the app
>   has windows, but the settings hide all of them.
>
> Both follow the Advanced switch “Show when an app has no open windows” (G-6).

### G-19 · Minor · §1, §4.1, §4.13 · Defaults compared with DockDoor aren't recorded

**Finding.** §1 records how DockDoor behaves, but not what it does by default. People switching from DockDoor will
compare the defaults first: hover delay, card size, which keys and clicks are on, and whether the Dock-click
behaviours are on. Without those facts, the plan can't say whether Snaptic's choices are deliberate differences or
oversights. Snaptic's choices are 0.2 s, Medium, Thumbnails on, keys on, Dock clicks off, and minimized, hidden and
other-Space windows included.

**Proposed plan text (§5).** New row **S0-17**: “DockDoor's shipped defaults, read from its Settings window on a
fresh install (behaviour only; its source isn't opened): hover delay, preview size, keys, middle-click, and Dock-click
behaviours. Recorded in STEP0-NOTES. Each difference from Snaptic's defaults is listed in Switching from DockDoor
(G-10).” Not a Blocker.

### G-20 · Minor · H6, §4.12 · Kill switches need README and guide rows, and an effect for each

**Finding.** H6 adds `Modules.disable.dockPreviews`, `Dock.disable.clickActions`, `Dock.disable.keys` and five
`Windows.disable.*` switches. The `Windows.*` switches change the switcher too. The README and guide list each
existing kill switch with what it does. The plan gives no lines for the new ones, and doesn't say on which page's
Diagnostics the `Windows.*` switches appear.

**Proposed plan text (D1).** One line per switch, each with a one-sentence effect:

> - `Modules.disable.dockPreviews`: “Dock Previews stays off.”
> - `Dock.disable.clickActions`: “Dock clicks are left entirely to the Dock.”
> - `Dock.disable.keys`: “Keys pass through to the active app; the pointer still works in previews.”
> - Each `Windows.disable.*` switch: its fallback from §4.12, in one sentence, and the note **“Affects the Window
>   Switcher and Dock Previews.”**
>
> The `Windows.*` lock rows show in both modules' Diagnostics.

### G-21 · Minor · §7 · No manual checks for several new states and rules

**Proposed plan text (§7, new rows).**

> | # | Check | B | V |
> |---|---|---|---|
> | M35 | Typing with the pointer resting in the panel: every key reaches the frontmost app (G-1) | B | V |
> | M36 | Quit from the header an app with an unsaved document: the app asks to save; Finder offers no Quit | B | |
> | M37 | ⌃F3 and Full Keyboard Access through the Dock: no previews (G-11) | B | V |
> | M38 | `snaptic dock pause 5m`: the page row, menu item and Resume all agree; relaunching resumes | B | V |
> | M39 | Only Dock Previews chosen in onboarding: the Snaptic icon shows, and the last step's text is true (G-3) | B | V |
> | M40 | Switcher thumbnails off, Dock Previews on: the switcher never shows a thumbnail (G-4) | B | V |
> | M41 | Increase Contrast, Reduce Transparency and Reduce Motion: borders, opaque panel, fade only | B | |
> | M42 | The Dock-not-readable row, forced with a test hook: row text, Try Again, CLI `unavailable` | B | |

### G-22 · Minor · H4 · The sidebar entry has no symbol or tint

**Finding.** H4 places the page between Hidden Icons and Permissions but doesn't give it a symbol or a tint. The
sidebar roots use gray, graphite, indigo, blue, orange and teal (`Snaptic/SettingsUI/SettingsShell.swift:58–67`). No
root uses green, purple or red. Red reads as a warning.

**Proposed plan text (H4).** Symbol `dock.rectangle` (available on macOS 14). Tint `.green`; Picture in Picture uses
green one level down, under Displays, so no other root does. `SettingsShellRulesTests` pins nine roots.

### G-23 · Minor · §0 vs §4.3 · "zoom" vs "full screen"

**Finding.** §0 says "Close, minimize or zoom it from the card" (PLAN:l.14). §4.3's hover buttons are "Close,
minimize, full screen". On a Mac, zoom and full screen are different actions.

**Proposed plan text (§0).** “Close it, minimize it, or make it full screen from the card.”

### G-24 · Minor · §4.2 header · The window count needs a singular and a plural

**Finding.** The header shows a "window count", but the plan doesn't give the string. "1 windows" is the usual bug.
Kit already has a helper for this (`SnapticKit/AwakeClock.swift:210`, `AwakeCountdown.unit`).

**Proposed plan text (§4.2).** **“1 window”** / **“3 windows”**, built with a shared Kit counter (move `unit` to
`SentenceText`), and spoken the same way by VoiceOver (G-11).

---

## Not found to be a problem

- **Naming.** "Dock Previews", `snaptic dock`, the alias `dock`, and the short title "Dock" all fit Snaptic's
  terms. The full title is the tab's accessibility label (DS:l.556).
- **Off by default, and nothing runs while off** (PLAN:l.26, l.43–44). This matches README:l.22, and M32 checks it.
- **A listen-only tap for Dock clicks** (PLAN:l.243). The Dock always gets the click first, and a failed tap never
  swallows one. The breaker and the trust re-check cover macOS 27.2's freeze risk.
- **Text-only mode.** Without Screen Recording, cards show titles and pointing at the Dock never prompts (PLAN:l.16,
  l.81). Thumbnails off gives the same mode on purpose. Q2's "text-only mode" needs no separate setting.
- **The VoiceOver default.** Pausing while VoiceOver is on, with an opt-in to show previews (PLAN:l.251), is the
  right default. G-11 adds only the keyboard case and how to reach the panel.
- **The same title on two pages.** Titles such as "Include minimized and hidden windows" can appear on both the
  switcher's and Dock Previews' pages. Search shows "Title / Pane" (DS:l.114), so they don't collide, as long as G-4's
  wording rule holds.
- **The §9 exclusions** match Q2 and the clean-room rule. Not importing DockDoor's settings is stated, and G-10's
  table tells users so.
- **"Menu bar toolkit"** (README:l.7) stays accurate. Snaptic still lives in the menu bar, even though one module
  works from the Dock.
- **Privacy.** Thumbnails stay in memory and are purged on lock, sleep, fast user switching and `stop()` (PLAN:l.55).
  This matches README:l.232.
