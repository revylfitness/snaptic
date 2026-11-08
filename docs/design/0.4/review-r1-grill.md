# 0.4 plan review r1: Grill (product, scope, UX)

Reviewer: Grill (product / UX). Plan under review: `docs/design/0.4/PLAN-draft.md` (draft r1, 321 lines).
Grounding: README.md, `docs/design/0.3/design-spec.md` (DS), `docs/design/0.3.1/PLAN.md` (format model),
`docs/design/macos27.md`, the Snaptic UI sources, and Hidden Bar v1.11.1 at `/tmp/hidden-src/repo`.

The owner decisions Q1–Q6 are taken as settled. Nothing below reopens them. Each finding is about how a decision
is *realized*: missing states, contradictions with Snaptic's existing rules, and strings that aren't canonical yet.

**Counts:** 4 Blockers (G-1 to G-4), 15 Majors (G-5 to G-19), 12 Minors (G-20 to G-31).

Citation conventions: `PLAN:l.N` is a line of PLAN-draft.md. `README:l.N` is a line of README.md. `DS:l.N` is a line
of design-spec.md. `HB MANUAL` is `/tmp/hidden-src/repo/docs/MANUAL.md`.

---

## Blockers

### G-1 · Blocker · H2, §4.6, §4.8 Advanced · The Icons tab can't exist under the tab model, and its switch is in two places

**Finding.** H2 makes Hidden Icons own-icon only (`MenuPresence.allowed(for: .hiddenIcons) == [.ownIcon]`) and
also gives it a Snaptic-menu tab. In Snaptic, tabs are *exactly* the modules whose presence is Show in Snaptic Menu.
A module limited to `.ownIcon` is never in `plan.shared`, so it can never be a tab. The plan doesn't say what new
rule replaces that one. It also leaves these cases open:

- **Nothing set to Show in Snaptic Menu.** If no module uses Show in Snaptic Menu, there is no Snaptic icon at all.
  Where does the Icons tab live then?
- **One module plus Icons.** If exactly one module is shared, does Icons make it two tabs? Or does the 0.3 compact
  section stay, with Icons below it?
- **⌘4 by position.** Q4 says "⌘4", but ⌘n is positional (README:l.56). With Awake as the only other tab, Icons
  would be ⌘2.
- **Remembered tab.** What happens to a remembered tab of `hiddenIcons` while the module is off?

This matters most on macOS 27. There, ⌃-click and right-click on the arrow are "not relied on" (PLAN:l.162;
macos27.md l.63). So the Snaptic-menu tab is the **only** menu home for the hidden-icon and notch-covered list
(PLAN:l.48, l.211). A user with every module on its own icon (a common setup) would have no way to open a
notch-covered icon on 27.

The switch for the tab is also specified twice, with two wordings:

- H2 (Menu Bar page): "Show Hidden Icons in the Snaptic menu"
- §4.8 Advanced: "Show Hidden Icons tab in Snaptic menu"

Placement belongs only on the Menu Bar page (DS §3.3; `MenuBarPage.swift` owns every presence control).

**Evidence.**
- `SnapticKit/MenuLayout.swift` `MenuTabs.tabs(plan:)`: "one tab per module in the Snaptic item, in `plan.shared`
  order, only with two or more".
- `SnapticKit/KitModules.swift:100` `allowed(for:)`.
- README:l.47, l.56, l.60, l.256 ("the compact Awake section (when Awake is the only module in the Snaptic menu)").
- PLAN:l.92–97, l.247.

**Proposed plan text (H2, replacing the current bullets).**

> **H2. Menu presence.** Hidden Icons is not a `MenuPresence` module: `allowed(for: .hiddenIcons) == [.ownIcon]`.
> The arrow is its icon, and the Menu Bar page shows it as a fixed row (G-11). Separately, one Menu Bar page
> switch, **“Hidden icons in the Snaptic menu”** (default on; Menu Bar Restore Defaults resets it), adds a
> **Hidden Icons** entry to the Snaptic menu. It is a new Kit input to `StatusItemPlan`, not a presence:
>
> | Modules set to Show in Snaptic Menu | Switch on, Hidden Icons on | Result |
> |---|---|---|
> | 0 | yes | The Snaptic icon appears. Its menu shows the Hidden Icons section with a header and no tab bar (like 0.3's single-module header). |
> | 1 | yes | Two tabs: that module, then **Icons**. |
> | 2–3 | yes | Tabs in `ModuleID` order with **Icons** last. Its key is its position (⌘4 when all four modules are tabs; Q4's “⌘4”). |
> | any | no, or module off | No Icons tab. A remembered `hiddenIcons` tab falls back to the first tab without being overwritten (existing A5 rule). |
>
> The Snaptic icon is never shown *only* because of the Icons entry while its menu would have nothing else and the
> hidden list is empty. In that case the section reads “No Hidden Icons” (see G-10).
> `MenuTabs.tabs(plan:)` becomes `plan.shared + (plan.iconsEntry ? [.hiddenIcons] : [])`, keeping the
> “two or more” rule. §4.8 Advanced loses its “Show Hidden Icons tab in Snaptic menu” row.

---

### G-2 · Blocker · §4.1, §4.5 "Collapse at launch", H5 · First enable hides every third-party icon before the user has arranged anything

**Finding.** First-run seeding puts the arrow and separator right next to Snaptic (PLAN:l.74, l.133). So on first
turn-on, every third-party icon is left of the separator, in **Hidden**. "Hide icons when Snaptic opens" (default
on) collapses 1 s after the module *starts* (PLAN:l.193), and turning the module on is a start. After that,
auto-collapse (default on, 10 s) re-hides them.

The result: the first thing a new user sees is all their menu-bar apps vanishing. That includes VPN, password
manager and recording indicators. The user hasn't been taught ⌘-drag, and has no shortcut, because it is unset by
default (PLAN:l.221).

On 27 with Accessibility granted it is worse. The allow-list is "visible-section bundles" (PLAN:l.143), which is
empty, so every third-party item disappears. Hidden Bar's own install instructions put the arrange step *first*:
"Launch Hidden and drag the icon in your menu bar (hold CMD) to the right so it is between some other icons." Its
manual's top troubleshooting row is "Icons I want visible got hidden after an update".

The plan never answers the brief's question: what happens if the user never arranges anything?

**Evidence.**
- PLAN:l.74, l.133, l.143, l.184, l.193, l.221.
- `/tmp/hidden-src/repo/README.md` "Manual download" step 3.
- HB MANUAL §Troubleshooting.
- DS:l.633 ("Never depend on an item being visible").

**Proposed plan text (new §4.0 "First run").**

> **§4.0 First run.** The module has an *arranged* flag (`Icons.arranged`, default false; cleared by Reset All
> Settings and by Hidden Icons Restore Defaults; not exported).
>
> - While `arranged` is false, nothing hides on its own. There is no launch collapse and no auto-collapse; only a
>   click on the arrow, the shortcut, the menu or the CLI collapses. The Settings status row reads
>   **“Arrange your icons, then click the arrow to hide them.”**, with the **How to Arrange…** button (G-10).
> - The first collapse the user asks for sets `arranged = true`. From then on the launch and auto-collapse settings
>   apply.
> - Turning the module on (switch, onboarding, New card) always opens the Hidden Icons page with the arrange panel
>   expanded.
> - On 27, if the visible section would contain no third-party bundles on that first collapse, Snaptic asks once:
>   **“Hide all other apps’ icons?”** / **“No icons are to the right of the arrow yet, so every other app’s icon will
>   be hidden. ⌘-drag the icons you want to keep to the right of the arrow first.”** / [**Hide Icons**] [**Cancel**]
>   (Cancel is the default).
>
> Manual checks: M-new “fresh enable on 14 and 27: nothing hides until the first click”.

---

### G-3 · Blocker · §6 "Snaptic's own items", §4.4 · On the Length engine, Awake's icon can land in the hidden zone, which breaks "A running Awake session is never invisible"

**Finding.** README:l.64 is a product guarantee: "A running Awake session is never invisible … if no Snaptic icon
is shown, Awake’s own icon appears for the session". On 14–26 the plan admits the user "can still ⌘-drag them
left" (PLAN:l.287).

It's worse than a user mistake. Awake's "Show When Active" icon and Displays' "Show When Active" icon appear and
disappear at runtime. A status item macOS hasn't placed before (no Preferred Position yet) is inserted at the far
left. That is exactly the hidden zone, as PLAN:l.178 says for third-party icons and the HB MANUAL explains in "Why
new icons start hidden". So the first-ever Awake session after Hidden Icons is turned on can start invisibly.

The same applies to lid-closed mode, whose visibility is a safety property (README:l.391). It also applies to the
arrow itself: dragged left of the separator, it gets pushed off-screen with the rest.

Snaptic doesn't need Accessibility to see its *own* items. Their button windows' frames are readable in-process
(on 14–26, where items are still per-item windows).

**Evidence.**
- README:l.64, l.256, l.391.
- PLAN:l.178, l.287.
- HB MANUAL "Why new icons start hidden".
- macos27.md l.60 (per-item windows only before 27).

**Proposed plan text (§4.1 Length engine, new bullet; and §6 row rewritten).**

> - **Snaptic's own items (Length).** Before every collapse, and whenever a Snaptic status item appears, the engine
>   compares each Snaptic item's window frame with the separator's. No Accessibility is needed.
>   - **Arrow left of the separator:** collapse is refused, the bar stays expanded, and the page status row reads
>     **“The arrow is in the hidden area. ⌘-drag it to the right of the | divider.”**
>   - **The Snaptic icon or a module icon left of the separator while Awake keeps the Mac awake or lid-closed mode
>     is on:** collapse is refused (expanding at once if collapsed) until the session ends. The page shows
>     **“Awake’s icon is in the hidden area, so icons stay shown while your Mac is kept awake. ⌘-drag it to the
>     right of the arrow.”**
>   - **Any other Snaptic item left of the separator:** a warning row
>     **“Some Snaptic icons are in the hidden area. ⌘-drag them to the right of the arrow.”**
>   - When a Snaptic item appears for the first time while collapsed, the bar expands, so the item gets a position
>     right of the arrow before the next collapse.
>   - Kit owns the decision (`IconsPolicy.ownItemsGuard`) and has a test for each row.
>
> §6 row: “Snaptic's own items | Native: own bundle always allowed. Length: the own-items guard above; the README
> guarantee ‘A running Awake session is never invisible’ holds on every engine (manual M-new).”

---

### G-4 · Blocker · §4.2, §4.1, H6 · No recovery when the arrow is removed, overflowed, or hidden by macOS while icons are collapsed

**Finding.** Snaptic's status items use `behavior = .removalAllowed`, so ⌘-dragging the arrow out of the bar removes
it (DS:l.633). On 27 the arrow can also:

- sit in the system overflow (macos27.md l.60);
- be switched off in System Settings › Menu Bar.

In none of those cases can Snaptic tell from `isVisible` (macos27.md l.65).

If any of this happens while collapsed, the Hidden section stays hidden with no visible way back:

- the shortcut is unset by default;
- the Snaptic-menu entry may not exist (G-1);
- the plan's §4.8 status row has no Show button.

Hidden Bar calls this out as a fixed bug: "Self-repair: if the arrow or separator was ⌘-dragged off the bar (which
used to make the app unreachable forever), they come back on next launch." The plan doesn't mention self-repair at
all.

**Evidence.**
- DS:l.633 ("Every action must also be available from Settings or a keyboard shortcut").
- macos27.md l.60, l.65, l.128.
- HB MANUAL "Behaviors you get for free".
- PLAN:l.221, l.235.

**Proposed plan text (§4.2, new paragraph).**

> **Losing the arrow.**
> - When the arrow's `isVisible` turns false (the user ⌘-dragged it out), the engine expands at once and stays
>   expanded. The page status row reads **“The arrow was removed from the menu bar, so icons stay shown.”** with
>   [**Show Arrow**].
> - The same happens to the separators. Removing `|` or `⋮` expands, and its row offers [**Show Divider**].
> - On next start, removed items come back (Hidden Bar parity), with `isVisible = true` and their last position.
> - Because 27 can hide the arrow without telling Snaptic, these always work whatever the arrow's state:
>   - the page status row's [**Show Icons**] / [**Hide Icons**] button;
>   - the Snaptic-menu entry;
>   - `snaptic icons show`;
>   - opening Snaptic again, which shows Settings (README:l.64). On the Hidden Icons page it also expands.
> - The 27 footer under the page reads: **“macOS can hide the arrow in System Settings › Menu Bar or behind its
>   overflow. If you can’t see it, use Show Icons here or set a shortcut.”**

---

## Majors

### G-5 · Major · §4.1 Native, H4 · Accessibility on 27 has no state table, and the prompt plan contradicts macos27.md

**Finding.** The Native engine can't collapse without Accessibility. PLAN:l.149 says it "prompts once, then retries
when the grant arrives". macos27.md says the 27 prompt "no longer reliably raises the system dialog or adds the app
to the list", and that grants often need a relaunch. Its recommendation is to open the pane directly, add with "+",
poll, and offer a relaunch (macos27.md l.17–18, l.124).

Missing from the plan:

- what clicking the arrow does while permission is missing;
- what happens when permission is **revoked mid-session**. The inventory comes back empty, and an empty visible
  section means "hide every third-party app". That must fail open, not hide everything;
- what the user sees when permission is granted but not yet effective (needs a relaunch);
- what the Permissions row says.

The pane's name on 27 is **Device Control and Data Access** (README:l.399).

**Evidence.**
- PLAN:l.103–106, l.149.
- macos27.md l.12–18, l.124.
- README:l.399, l.401.
- `PermissionsPage.swift:88` (“Relaunch Snaptic”).
- HB MANUAL: "Without it the bar stays expanded."

**Proposed plan text (§4.1, new table "Native engine and Accessibility").**

> | State | Arrow click | Page status row | Snaptic menu row | `snaptic icons status` | Attention mark |
> |---|---|---|---|---|---|
> | Granted, inventory read | Toggles | “Hiding 7 icons” / “Showing all icons” | Show/Hide item | `engine=native state=collapsed hidden=7 alwaysHidden=2 shown=5` | none |
> | Not granted | Opens Settings › Hidden Icons; nothing hides | “Hidden Icons needs Device Control and Data Access to see where your icons are.” [**Open Privacy Settings**] | “Needs Permission” (disabled) + **Hidden Icons Settings…** | `engine=native state=needsPermission` | yes |
> | Granted, not yet effective (polling `AXIsProcessTrusted()` false for 5 s after the pane closes) | Same as not granted | “macOS may need Snaptic to reopen before the permission takes effect.” [**Relaunch Snaptic**] | same | same | yes |
> | Revoked while collapsed (inventory read fails or returns zero third-party items on two reads) | Expands, then as “Not granted” | as “Not granted” | as “Not granted” | `state=needsPermission` | yes |
>
> - An inventory that fails, or that returns no third-party items while the last good read had some, **never**
>   produces a collapse. The engine expands and keeps the last good layout (Kit test).
> - Asking for permission follows macos27.md §Recommendations 1: call the prompt variant once, **always** open the
>   pane, show the app path with “Show Snaptic in Finder”, and poll.
> - The Permissions page row is **Hidden Icons**. Its "needed for" text is **“Seeing where your icons are (macOS 27),
>   and the hidden-icon list”**.
> - README Permissions table, "Asked for when" column: “Hidden Icons is on (macOS 27); the hidden-icon list or the
>   Sections list on any macOS”.

---

### G-6 · Major · §4.8 Sections preview, §1 inventory row · "Live sections list on every macOS" (Q3) is realized only with Accessibility, and "14–26 needs no permission" is half true

**Finding.** Q3 says the live sections list is shown on every macOS. §4.8 makes it "needs Accessibility". §1 says
"14–26 needs **no permission** for basic hiding". Both can be true, but the plan never says what a 14–26 user
without Accessibility sees on the page. Nor does it say:

- how the list differs between 14–26 and 27;
- what "Refresh" does on Native while collapsed. Only an unrestricted bar can be read (PLAN:l.147), so Refresh
  would have to expand briefly, visibly. Does it?
- what the section headers are called;
- what an empty section says.

**Evidence.** PLAN:l.13, l.45, l.147, l.242–243.

**Proposed plan text (§4.8 Sections, replaced, with mockups).**

> **Sections ›** is a sub-page (NavigationRow, like Awake's Drives › and History ›, `AwakePage.swift:550`). It keeps
> the main page within DS's ~8 controls (G-19).
>
> | | macOS 14–26 (Length) | macOS 27 (Native) |
> |---|---|---|
> | Without Accessibility | “Allow Accessibility to see which icons are in each section. Hiding works without it.” [**Open Privacy Settings**] | “Hidden Icons needs Device Control and Data Access to see where your icons are.” [**Open Privacy Settings**] |
> | Expanded | Live list. Updates on app launch and quit, and after ⌘-drags, within 2 s | Live list |
> | Collapsed | Live list (Length can read hidden items: they're off-screen, not removed) | Last list read while expanded. Footer: “As of the last time your icons were shown.” |
> | Per-row control | none (read-only; footer: “⌘-drag icons in the menu bar to move them between sections.”) | pop-up: **Where It Is** / **Always Show** / **Always Hide** (G-7) |
> | Refresh | **Refresh** re-reads | **Refresh** re-reads only while expanded. While collapsed it reads **Show Icons and Refresh**, which expands, reads, and leaves the icons shown (auto-collapse re-arms). |
>
> Section headers: **Shown**, **Hidden**, **Always Hidden** (Hidden Bar's own labels: “Shown”, “Hidden”,
> “⭐️Always Hidden” in `Main.storyboard`). Empty section: **“No icons”**. Footer on both:
> **“Icons that macOS hides in System Settings › Menu Bar aren’t listed.”**
>
> ```
> ┌ Sections ─────────────────────────────────────────┐
> │ SHOWN                                             │
> │   [■] Dropbox                     Where It Is ▾   │
> │   [■] 1Password                   Always Show ▾   │
> │ HIDDEN                                            │
> │   [■] Docker                      Where It Is ▾   │
> │   [■] Zoom (2 icons)              Where It Is ▾   │
> │ ALWAYS HIDDEN                                     │
> │   No icons                                        │
> │                                                   │
> │ As of the last time your icons were shown.        │
> │                       [Show Icons and Refresh]    │
> └───────────────────────────────────────────────────┘
>   (macOS 27. On 14–26 the pop-ups are absent and the
>    footer says “⌘-drag icons … between sections.”)
> ```

---

### G-7 · Major · §4.8, Q3 · "Always Show" / "Always Hide" have no rules for precedence, scope, reset, or backup

**Finding.** The plan never says:

- whether an override beats the ⌘-drag position, or the reverse;
- whether "Always Hide" means the Hidden section (shown on expand) or Always Hidden (shown only with ⌥). The names
  invite the second reading, and "Always Hidden section" is a separate toggle;
- what happens to "Always Hide" when the Always Hidden section is off;
- how the user sees that an override is in effect, and how to undo it;
- what Restore Defaults does to overrides;
- that backup drops them. Backup leaves out "anything containing bundle ids" (H7), so they're silently lost on
  import;
- how overrides interact with the new-icon policy (G-8).

macOS 27 hides per bundle (PLAN §7), so an app with several icons gets one choice.

**Evidence.** PLAN:l.12, l.113–114, l.154, l.176–177, l.243, l.295.

**Proposed plan text (§4.8, new "Per-app choices (macOS 27)").**

> - Each app in Sections has one pop-up: **Where It Is** (default; follows its ⌘-drag position), **Always Show**,
>   **Always Hide**. The options are Title Case (DS:l.643).
> - A choice beats position. **Always Show** keeps the app shown even when collapsed. **Always Hide** keeps it hidden
>   whenever the Hidden section is hidden, and it shows on expand like any hidden icon. It never puts an app in
>   Always Hidden; only a ⌘-drag does that.
> - An app with a choice lists under the section the choice puts it in, with the pop-up showing the choice. An app
>   with several icons shows “(2 icons)”, and the choice applies to all of them.
> - Help under the list: **“Always Show and Always Hide apply to all of an app’s icons and win over where you drag
>   them.”**
> - Hidden Icons **Restore Defaults…** clears every choice and the new-icon list (G-16).
> - Backup leaves choices out, because they name apps. README backup list: “Hidden Icons’ per-app choices and new-icon
>   list”. Import keeps this Mac's choices.
> - On disk the choices are bundle ids in Snaptic's preferences. README “On disk” gains: “Hidden Icons’ per-app
>   choices and new-icon list (app bundle identifiers, never names).”
> - On 14–26 Sections shows no pop-ups, and any choices stored on 27 are kept but unused.

---

### G-8 · Major · §4.4 New icons · The policy's strings and the "until I move them" rule are undefined, and the Length notice has no text

**Finding.**

- **Option strings.** "New icons: Show until I move them / Hide" is neither a canonical label nor a Title Case
  pop-up option.
- **"Until I move them" is not detectable as written.** A new icon appears at the far left, which is already "in a
  section" (Hidden). PLAN:l.177 says it "stays shown until the user ⌘-drags it into a section", but it is always in
  one. So what counts as moving it?
- **No Length notice.** On Length the "one-time notice" has no string, no surface (toast? page row?), and no "once
  per what" (per app, or once ever).
- **Unstated permission.** The policy needs the inventory, hence Accessibility (H4), and the setting must say so.

**Evidence.**
- PLAN:l.104, l.172–180, l.246.
- HB MANUAL "Why new icons start hidden".
- DS:l.643 (pop-up options in Title Case); DS:l.669–670.

**Proposed plan text (§4.4, replaced).**

> - Advanced… row: PickerSetting **“New apps’ icons”**, options **Show** / **Hide**. Default **Show** on 27, where
>   it works; on 14–26 the row is absent (Length can't move icons). Help: **“Show keeps an app’s icon visible the
>   first time it appears, until you drag it or choose where it goes.”** Needs Device Control and Data Access; without
>   it the row is dimmed with “Needs Device Control and Data Access.”
> - **Rule (Kit, tested):** an unknown bundle seen in the Hidden section while “Show” is on joins the new-icon list
>   with the x-position where it first appeared. It leaves the list, and follows its position from then on, when:
>   - its x-position changes by more than its own width relative to the arrow (a ⌘-drag);
>   - the user picks anything in its Sections pop-up;
>   - it hasn't appeared for 30 days.
>
>   In Sections it shows under Shown, with a pop-up reading **Where It Is** and a secondary line **“New”**.
> - **Length notice:** once per app, at most once a day, a toast:
>   **“A new icon may be hidden. ⌘-drag it to the right of the arrow to keep it shown.”** [**Show Icons**]. It also
>   appears in the hidden-icon list with a “New” line. The page's How to Arrange… panel explains the same thing.

---

### G-9 · Major · §4.9 Full menu bar on expand · The help text isn't honest about focus, ⌘-Tab, and hover, and breaks DS length

**Finding.** The proposed help says Snaptic "becomes the active app" and shows a Dock icon. That understates what
users notice:

- The frontmost app **loses keyboard focus**. Typing stops going to the document, and on collapse focus returns
  after the auto-collapse delay (10 s), possibly mid-word.
- Snaptic appears in **⌘-Tab**.
- The Dock icon bounces in and out on **every** expand.
- With **hover to expand** on, merely moving the pointer to the menu bar steals focus.

The plan doesn't say which menus Snaptic's "short app menu" contains, and doesn't define the hover interaction. At
two sentences and about 170 characters it also breaks DS:l.670 ("one sentence of at most about 90 characters").
"Not offered while the Window Switcher is mid-switch" (PLAN:l.209) reads like a UI rule but is a runtime guard.

**Evidence.** PLAN:l.195–209, l.191–192; DS:l.670; H9 rule PLAN:l.122.

**Proposed plan text (§4.9).**

> - Label **“Use the full menu bar while icons are shown”** (sentence case of Hidden Bar's “Use the full MenuBar on
>   expanding”).
> - Help, one sentence: **“Snaptic becomes the active app while icons are shown, so the current app loses focus.”**
> - A footnote under the Advanced group: **“Snaptic also appears in the Dock and the app switcher until the icons are
>   hidden.”**
> - Hover to expand never activates Snaptic. With both on, hover shows the icons without the full menu bar, and only
>   a click, the shortcut or the menu activates. (Kit truth table: `fullBarOnExpand ∧ expanded ∧ expandCause ≠
>   hover`.)
> - The app menu while active is Snaptic's existing main menu (list its menus here). It must not show an empty Edit
>   or Window menu.
> - Runtime guard (not UI): “Activation is skipped while the Window Switcher panel is open.”

---

### G-10 · Major · whole plan · Canonical strings, ASCII mockups and state tables are missing

**Finding.** The format model (0.3.1 PLAN Part A) fixes every user-visible string, gives an ASCII mockup of each
menu and page, and has state tables. The draft has a handful of quoted labels and no mockups. Missing:

- status-row states and the "unavailable" text;
- the How to Arrange text;
- the onboarding step and the New card body and button;
- the notices: Length new icon, fail-open, conflict;
- menu items, tooltips, VO labels, CLI output and errors, and confirmations.

Implementers will invent these, and lint03's sentence and title-case checks can't catch meaning drift.

**Evidence.** `docs/design/0.3.1/PLAN.md` Part A (canonical strings, ASCII menu sketch, A3 keyboard and VO);
PLAN:l.228–249.

**Proposed plan text (new §4.10 "Canonical strings", in addition to the strings in G-1 to G-9 and G-11 to G-19).**

> | Where | String |
> |---|---|
> | Module title / sidebar | **Hidden Icons** |
> | Short title (tabs) | **Icons** |
> | Page switch | **Use Hidden Icons** |
> | ModuleSwitchRow summary (General, onboarding) | **“Hide the menu bar icons you don’t need behind an arrow. Its icon is the arrow.”** |
> | Page summary | **“Keep your menu bar tidy: click the arrow to hide the icons to its left, and click again to show them.”** |
> | Status row, collapsed | **“Hiding 7 icons”** (“Hiding 1 icon”); 14–26 without Accessibility: **“Icons are hidden”** |
> | Status row, expanded | **“Showing all icons”** |
> | Status row, unavailable (27, shim missing or kill switch) | **“Hidden Icons isn’t available on this version of macOS. Your icons stay shown.”** |
> | Status buttons | **Hide Icons** / **Show Icons** |
> | Auto-collapse | **“Hide icons automatically after [10] seconds”** (range 2–300, value field) |
> | Launch | **“Hide icons when Snaptic opens”**; help **“Reopening Snaptic to show Settings doesn’t hide them.”** |
> | Always Hidden | **“Always Hidden section”**; help **“Icons left of the ⋮ divider stay hidden until you Option-click the arrow.”** |
> | Dividers | **“Section dividers”**; help **“Shows | and ⋮ while icons are shown.”** (27: G-27) |
> | Shortcut row | **“Show or hide icons”** (shortcut name **Show or Hide Hidden Icons**, G-20) |
> | Arrange button | **How to Arrange…** (opens the sheet below) |
> | Fail-open notice (once per launch, toast) | **“Snaptic couldn’t hide icons, so they’re shown. Details are in Hidden Icons settings.”** |
> | CLI, module off | the existing gated message with `Hidden Icons` in it (quote the exact template) |
> | CLI status | `engine=<native\|length\|unavailable> state=<collapsed\|expanded\|needsPermission\|unavailable> hidden=<n> alwaysHidden=<n> shown=<n>`; never names |
> | Snaptic menu, empty list | **No Hidden Icons** (disabled) |
>
> **How to Arrange sheet** (also onboarding step G-12, and README):
>
> ```
> ┌ How to Arrange Your Icons ─────────────────────────────┐
> │                                                        │
> │   ⋮  [A] [B]  |  [C] [D]  ‹  [E] [S]  ◷ 9:41           │
> │   └always┘   └─hidden─┘     └shown─┘                    │
> │                                                        │
> │ Hold ⌘ and drag icons in the menu bar:                 │
> │ • To the right of the arrow ‹: always shown.           │
> │ • Between | and ‹: hidden when you click the arrow.    │
> │ • Left of ⋮: hidden until you Option-click the arrow.  │
> │ New apps’ icons appear at the far left.                │
> │                                            [Done]      │
> └────────────────────────────────────────────────────────┘
>  (macOS 27 variant: no |, so the arrow is the edge:
>   “To the left of the arrow ‹: hidden when you click it.”)
> ```
>
> **Page mockup (on, 14–26):**
>
> ```
> [eye.slash] Hidden Icons                          [Use Hidden Icons ●]
> Keep your menu bar tidy: click the arrow …
> ┌───────────────────────────────────────────────────────────────┐
> │ Hiding 7 icons                                  [Show Icons]  │
> │ Hide icons automatically after [ 10 ] seconds            [●]  │
> │ Hide icons when Snaptic opens                            [●]  │
> │ Always Hidden section                                    [ ]  │
> │ Section dividers                                         [●]  │
> │ Show or hide icons                      [ Record Shortcut ]   │
> │ Sections                                         7 hidden  ›  │
> │ How to Arrange…                                               │
> └───────────────────────────────────────────────────────────────┘
> [Restore Defaults…]                               [Advanced…] (?)
> ```
>
> Also required: the off-state mockup (header plus highlights), the Snaptic-menu Hidden Icons section (G-15), the
> Menu Bar page row (G-11), the onboarding step (G-12) and the New card (G-13).

---

### G-11 · Major · H2 · The Menu Bar page's fixed row, summary, footer and Restore message are wrong or unchanged

**Finding.**

- **Fixed row.** “Hidden Icons: the arrow shows while Hidden Icons is on” is a colon label with prose. Every other
  row on that page is a module name with a pop-up.
- **Summary, footer and Restore message.** These all enumerate three modules and ⌘1–⌘3 and must change:
  - summary (`MenuBarPage.swift:56`): "Choose where Window Switcher, Displays, and Awake appear in the menu bar.";
  - footer (`MenuBarPage.swift:103`): "…press ⌘1, ⌘2, or ⌘3 to switch tabs.";
  - Restore message (`MenuBarPage.swift:109`).
- **27 footer.** The 27 footer (l.268) should mention the arrow, because System Settings › Menu Bar can hide it.
- **Missing pieces.** The plan has no row for the new "Hidden icons in the Snaptic menu" switch (G-1), and doesn't
  say whether Menu Bar Restore Defaults resets it.

**Evidence.** `MenuBarPage.swift:56, 103, 109, 268, 280`; README:l.45–64; PLAN:l.94–95.

**Proposed plan text (H2, Menu Bar page strings).**

> ```
> Where each module appears
>   Window Switcher                         Always Show in Menu Bar ▾
>   Displays                                Show When Active ▾
>   Awake                                   Show When Active ▾
>   Hidden Icons                            Arrow in Menu Bar        (value text, no pop-up)
>   Hidden icons in the Snaptic menu                                  [●]
> ```
>
> - Hidden Icons row: label **Hidden Icons**, trailing secondary text **Arrow in Menu Bar**. Accessibility value
>   “Arrow in menu bar, while Hidden Icons is on”. While the module is off the row is dimmed with
>   **“Off”**.
> - Switch help: **“Lists hidden icons in the Snaptic menu, so you can open one without showing them all.”**
> - Summary: **“Choose where each module appears in the menu bar.”**
> - Footer: **“The Snaptic icon appears when a module is set to Show in Snaptic Menu, or for the hidden-icon list.
>   With two or more, the Snaptic menu shows a tab for each; while it’s open, press ⌘1, ⌘2, and so on to switch
>   tabs.”**
> - Restore message: **“Where each module appears, their icons, the Displays menu, and the hidden-icon list in the
>   Snaptic menu go back to their defaults. Your other Snaptic settings stay as they are.”**
> - 27 footer: **“macOS can also hide icons, including the Hidden Icons arrow, in System Settings › Menu Bar.
>   Opening Snaptic again always shows Settings.”**
> - README:l.45–64 updated to match. README:l.56 becomes “⌘1–⌘4 choose a tab (one key per tab, by position)”.

---

### G-12 · Major · Q6, H5, onboarding · "Step" vs "card"; the modules step overflows; welcome and permissions text are three-module

**Finding.**

- **Step or card.** Q6 says "an opt-in onboarding **step**". H5 and §0 say "card" (PLAN:l.31, l.107). Pick one.
- **Overflow.** The modules step lists `ModuleID.allCases` in a scroll-disabled Form inside a fixed 600×580 window
  (`Onboarding.swift:19, 252`). A fourth row with a two-line summary risks clipping at larger text sizes, and
  README:l.843 already tests "the largest text size".
- **Welcome text.** It says "A window switcher, display controls, and Keep Awake" (`Onboarding.swift:226`).
- **Permissions.** The `needed` set in the permissions step must include Accessibility when Hidden Icons is on and
  the Mac is on 27.
- **No arrange step.** Nothing teaches ⌘-drag, which is the whole learning curve (G-2).

**Evidence.** `Onboarding.swift:19, 226, 252, 298, 332`; PLAN:l.15, l.31, l.107; README:l.843.

**Proposed plan text (H5, replaced).**

> - **Modules step** gains a fourth row, **Hidden Icons**, off by default, with the G-10 summary. Verify at the
>   largest text size. If it doesn't fit, the Form scrolls (drop `scrollDisabled` on this step only).
> - **Welcome text:** **“A window switcher, display controls, Keep Awake, and hidden menu bar icons, in your menu
>   bar. Turn on only what you want; everything else stays off.”**
> - **New step “Arrange your icons”** after the modules step, shown only if Hidden Icons was turned on there. Body:
>   the How to Arrange diagram (G-10), then **“Nothing hides until you click the arrow for the first time.”** Buttons
>   [**Continue**]. On 27 the permissions step that follows lists Device Control and Data Access for Hidden Icons.
> - **Done text:** unchanged, plus, when Hidden Icons is on: **“Click the arrow ‹ to hide icons once they’re
>   arranged.”**
> - **New card** in General: see G-13. The onboarding step is for first launch only. Existing users get the card.

---

### G-13 · Major · Q6, D1, D2 · The 0.3.4 → 0.4.0 path isn't specified (card strings, README Upgrading, downgrade, a 0.4 promise)

**Finding.**

- **New card.** "New: Hidden Icons" has no body or button strings. The existing pattern is title, one-line body,
  [Turn On X] [Not Now], and opens the page (`GeneralPages.swift:211–265`).
- **README Upgrading.** It has no "0.3.4 → 0.4.0" entry, and the top-of-README upgrade bullets (l.23–26) don't
  mention 0.4.
- **Downgrade.** The plan doesn't say what 0.3.4 does with:
  - `hiddenIcons` in ModulesConfig;
  - `snapticMenuTab = hiddenIcons`;
  - the `Icons.*` keys;
  - the three `NSStatusItem Preferred Position Snaptic.icons.*` keys.

  Does 0.3.4 decode an unknown `ModuleID` leniently, or reset settings? README Upgrading lists "What 0.2 reads back"
  for 0.3, so 0.4 owes the same.
- **A forgotten promise.** README:l.466 promises "`prevent-sleep` … will be removed in 0.4". The plan doesn't list
  removing it, or keeping it with a new date.
- **App icon.** The new app icon ships in 0.4.0 (Q6) and deserves a line in the release notes.

**Evidence.** `GeneralPages.swift:211–265`; README:l.23–26, l.466, l.769–795; PLAN:l.15, l.259.

**Proposed plan text (new §4.11 "Upgrading").**

> - **New card** (shown once to anyone upgrading from 0.3.x with Hidden Icons off):
>   - title **New: Hidden Icons**;
>   - body **“Hide the menu bar icons you don’t need behind an arrow, and open them from the Snaptic menu.”**;
>   - buttons [**Turn On Hidden Icons**] [**Not Now**].
>
>   Turn On opens the page with the How to Arrange… sheet. Not shown during first-run onboarding.
> - README top: **“Upgrading from 0.3.x: Snaptic updates itself and nothing changes until you turn on Hidden Icons
>   (a “New: Hidden Icons” card in General). The app has a new icon.”**
> - README Upgrading: **“0.3.4 → 0.4.0.** Snaptic updates itself, and no setting is lost. Hidden Icons starts off.
>   `snaptic prevent-sleep` is gone (it answered ‘Moved to Awake’ since 0.3).”** (Or a dated reprieve, if removal is
>   dropped.)
> - Downgrade (K4 adds a test): 0.3.4 must read a 0.4 config without losing settings. State the result in README:
>   **“Going back to 0.3.4: your other settings stay. Hidden Icons’ settings are kept for when you return. Quit 0.4
>   first so the icons are shown.”** If 0.3.4 can't decode `hiddenIcons`, 0.4 must keep the module's on/off outside
>   the decoded `ModuleID` set.
> - Work item D1 gains: remove `prevent-sleep` (README:l.466) or re-date it.

---

### G-14 · Major · §6 "Two hiders", §7 · The conflict plan relies on a monitor that doesn't know hiders; there are no conflict strings and no "Switching from Hidden Bar"

**Finding.** §6 says "`OtherAppsMonitor` warns when a known hider is running". It doesn't.
`OtherAppsMonitor.swift:4` watches only BetterDisplay, MonitorControl and Lunar, and its policy ("Pause overlapping
Snaptic features") is Displays-specific. The plan needs to define:

- **The hider list:** Hidden Bar (`com.dwarvesv.minimalbar`, from HB MANUAL), Bartender (including its separate 27
  build), Ice, Thaw and others, with bundle ids verified in S0.
- **What Snaptic does.** Two inflated separators on 14–26 fight. On 27, Hidden Bar uses the *same* exam-mode
  assertion, so two allow-lists intersect and icons vanish. Warn, pause, or both?
- **The strings.**
- **A migration guide for Hidden Bar users**, the obvious audience. Snaptic does this for Amphetamine and Insomnia
  (README:l.346).

macOS 27's own System Settings › Menu Bar hiding also isn't covered in the user-facing text (PLAN:l.57 mentions it
only as a limitation).

**Evidence.** `OtherAppsMonitor.swift:1–30`; README:l.264, l.346–362; macos27.md l.118; PLAN:l.285; HB MANUAL
§Hidden settings (bundle id).

**Proposed plan text (§6 row and new §4.12 "Other menu bar apps").**

> - New Kit table `OtherMenuBarApps` (bundle ids from S0) and a second watcher in OtherAppsMonitor that runs only
>   while Hidden Icons is on.
> - While a listed app runs, Hidden Icons **pauses**: it expands and the arrow stays (click does nothing but open the
>   page). Status row: **“Paused while Hidden Bar runs”**. Menu row: **“Paused While Hidden Bar Runs”** (the
>   existing `pauseReason` / `menuPauseReason` pattern). Advanced row: PickerSetting **“When another menu bar app
>   hides icons”**, options **Pause Hidden Icons** (default) / **Run Both Anyway**.
> - README **“Switching from Hidden Bar”** (after the Hidden Icons section): quit Hidden Bar and remove it from Login
>   Items; positions don't carry over (macOS keeps them per app), so ⌘-drag the arrow once; then a table:
>
>   | Hidden Bar | Snaptic Hidden Icons |
>   |---|---|
>   | Start Hidden Bar when I log in | General › Open at login |
>   | Show preferences on launch | Opening Snaptic again always shows Settings |
>   | Automatically hide icon after | Hide icons automatically after … seconds |
>   | Enable always hidden section | Always Hidden section |
>   | Use the full MenuBar on expanding | Advanced… › Use the full menu bar while icons are shown |
>   | Global Shortcut | Show or Hide Hidden Icons (Settings › Hidden Icons) |
>   | Option-click to hide the separators | Section dividers (Option-click now shows Always Hidden) |
>   | Right-click ‹ for Notch Overflow | the Snaptic menu's Icons tab |
>   | `defaults write … hoverToExpand` | Advanced… › Show icons on hover |
>
> - Known limitations: **“Icons you hide in System Settings › Menu Bar aren’t listed or shown by Hidden Icons; turn
>   them back on there.”**

---

### G-15 · Major · §4.2, §4.6, H2 · VoiceOver and keyboard access aren't specified

**Finding.** The plan gives AXPress → toggle, and nothing else. Missing:

- the arrow's accessibility label, value and help;
- whether `|` and `⋮` are exposed to VO. They should be labeled or hidden, since a lone "|" button is noise;
- the names of the accessible-tab items. README:l.60 lists "Show Window Switcher Tab…" etc., so Icons needs "Show
  Icons Tab" or "Show Hidden Icons Tab";
- the tab tooltip and attention conditions;
- the hidden-list rows' labels (an icon image plus name);
- **a keyboard path to ⌥-click** (Always Hidden), which has none;
- auto-collapse while VoiceOver's cursor is in the menu bar. The pointer isn't there, so the re-arm rule
  "pointer in the menu-bar band" misses VO users;
- the arrow's look on 27, where `button.highlight` doesn't render (macos27.md l.64). The state must be in the glyph.

**Evidence.** README:l.56–60; DS:l.556–560 (tabs, attention marks, tooltips); macos27.md l.64; PLAN:l.160–164,
l.184–188; 0.3.1 PLAN A3.

**Proposed plan text (new §4.13 "Keyboard and VoiceOver").**

> - **Arrow:** stock button, image only.
>   - Glyphs: SF Symbol `chevron.compact.left` when collapsed (points at the hidden icons) and
>     `chevron.compact.right` when expanded, mirrored in RTL. Template image.
>   - Accessibility label **“Hidden Icons”**. Value **“Hiding 7 icons”** / **“Showing all icons”**.
>   - Help (tooltip and VO hint) **“Click to show or hide icons. Option-click to include Always Hidden.”**
> - **Separators:** `|` label **“Hidden Icons divider”**, `⋮` label **“Always Hidden divider”**. Each has the help
>   **“Hold Command and drag icons across this divider to hide or show them.”**
> - **Snaptic menu, Hidden Icons section:**
>
>   ```
>   ┌──────────────────────────────────────────┐
>   │ [Switcher | Displays | Awake | Icons]    │
>   │ Show Hidden Icons                        │
>   │ Show All Hidden Icons        (⌥ alt)     │
>   │ ──────────────                           │
>   │ HIDDEN                                   │
>   │ [■] Docker                               │
>   │ [■] Zoom                    2 icons  ›   │
>   │ COVERED BY THE NOTCH                     │
>   │ [■] Dropbox                              │
>   │ ──────────────                           │
>   │ Hidden Icons Settings…                   │
>   └──────────────────────────────────────────┘
>   ```
>
>   - **Show All Hidden Icons** is the keyboard path to Always Hidden: an alternate item with ⌥, plus a separate
>     plain item while VoiceOver, Switch Control, or Full Keyboard Access is on.
>   - Rows: label is the app name, the image is decorative (`accessibilityHidden` on the image), and the hint is
>     **“Opens its menu.”**
>   - An app with several icons is a submenu of its icons, labeled **“Icon 1”**, **“Icon 2”** (no titles exist).
> - **Tab:** short title **Icons**. Accessibility label **Hidden Icons**. Tooltip **“Hidden Icons (⌘4)”** (by
>   position). The attention mark shows when the status row is “needs permission”, “unavailable” or “paused”.
>   Accessible-tab item: **Show Hidden Icons Tab**.
> - **Auto-collapse** also re-arms while VoiceOver's cursor is on a menu bar extra (`NSWorkspace` VO running plus the
>   AX focused element in `AXExtrasMenuBar`, read only when VO is on), and while the Snaptic menu is open.

---

### G-16 · Major · H6, H7, §4.8 Advanced · Restore Defaults, Reset All Settings and backup scopes aren't named

**Finding.** DS requires a Restore confirmation that names its scope (DS:l.133), and Restore Defaults lives in the
page footer (DS:l.57; README:l.32). The plan puts it in the Advanced sheet and never lists:

- what it resets;
- whether it touches positions (it can't; macOS owns them), per-app choices, the new-icon list, the arranged flag
  (G-2), or the shortcut.

Reset All Settings clearing the position keys re-seeds the arrow next to Snaptic. That silently undoes the user's
whole arrangement, and with the old behaviour it would hide everything on next start (G-2). README's Reset All
warning should say so.

**Evidence.** DS:l.57, l.133; README:l.32, l.40, l.738; PLAN:l.109–114, l.249.

**Proposed plan text (H6/H7).**

> - Page footer **Restore Defaults…**: **“Restore Hidden Icons settings to their defaults?”** /
>   **“Automatic hiding, Always Hidden, dividers, the shortcut, hover, new apps’ icons, the full menu bar, and every
>   app’s Always Show or Always Hide choice go back to their defaults. Where your icons are in the menu bar stays as
>   it is.”** / [**Restore Defaults**] [**Cancel**]. It sets `arranged` to true when positions exist (the arrangement
>   is kept), so nothing re-enters first-run mode.
> - The Advanced sheet's own Restore Defaults resets only the sheet's rows (README:l.32), with the same pattern.
> - Reset All Settings confirmation adds: **“Hidden Icons’ arrow and dividers go back next to the Snaptic icon, so
>   you’ll arrange your icons again.”** It clears `arranged`.
> - Backup export leaves out positions, per-app choices, the new-icon list and `arranged` (README:l.738 list gains
>   **“Hidden Icons’ per-app choices, new-icon list, and icon positions”**). Import keeps this Mac's.

---

### G-17 · Major · §4.6, §4.1 Length, K1 · Notch and multi-display behaviour is undefined for users

**Finding.** "Covered by the notch" uses `auxiliaryTopRightArea`, which is per screen and exists only on the
built-in display. The plan doesn't say:

- **which bar the list describes** when the built-in display is mirrored, closed, or secondary, or when
  "Displays have separate Spaces" puts a bar on every display;
- **whether an icon covered on the built-in is listed** while it's plainly visible on the external display the user
  is looking at;
- **whether macOS 27's own overflow items** (the compact indicator) are listed, or whether they're absent from the
  AX tree too.

Length's length uses "2×widest screen". With a wide external display and the built-in as main, the hidden zone is
very wide. Fine, but M-checks should name it. K1 tests "multi-display", but no user-facing rule exists to test
against.

**Evidence.** PLAN:l.43, l.48, l.211–217, l.256; macos27.md l.60; README:l.842 (existing notched-Mac checks).

**Proposed plan text (§4.6, new bullets).**

> - “Covered by the notch” lists an icon only if it's covered on the display whose menu bar the pointer was last on
>   (or the main display), and only when that display has a notch. On other displays that section is absent.
> - Icons in macOS 27's overflow are listed under **Covered by the notch** if AX reports them with an off-bar frame.
>   Otherwise they aren't listed. S0 records which, and Known limitations says so.
> - Manual checks: notched built-in plus external, “Displays have separate Spaces” on and off, built-in closed
>   (clamshell), and the pointer on each display while the list opens.

---

### G-18 · Major · Q5 wording, D1 · README's "fails closed" and "isn't derived from" become inaccurate

**Finding.**

- **"Fails closed".** README:l.888 says every private API "fails closed: if Apple removes or changes one, the
  feature that needs it becomes unavailable". Q5 and the plan say "failing open". The outcome is the same in spirit
  (the feature becomes unavailable and icons are shown), but the README term will now contradict a release that
  says "fails open". Readers will think one of them is wrong.
- **"Derived from".** README:l.7 says Snaptic "isn’t affiliated with or derived from AltTab, BetterDisplay…". 0.4
  explicitly reuses Hidden Bar's *design* (PLAN:l.35–36) and credits it. The intro must not imply independence from
  Hidden Bar, and must not list Hidden Bar among "not derived from".
- **Intro and modules table.** Both still say three modules (README:l.3, l.15–21), including the "Use X" switches
  list.

**Evidence.** README:l.3, l.7, l.15–21, l.888; PLAN:l.14, l.35–36, l.148.

**Proposed plan text (D1 additions).**

> - README:l.888 sentence becomes: **“…behind a kill switch, and fails safe: if Apple removes or changes one, the
>   feature that needs it becomes unavailable instead of crashing (for Hidden Icons, that means your icons stay
>   shown).”** The plan uses “fails safe (icons shown)” instead of “fail open” throughout.
> - README:l.7 adds: **“Hidden Icons follows the design of Hidden Bar by Dwarves Foundation (MIT), credited in
>   THIRD_PARTY_NOTICES.md; its code is Snaptic’s own.”** Hidden Bar stays out of the “isn’t … derived from” list.
> - README:l.3 intro, the Modules table (new row), l.21 “(“Use Window Switcher”, “Use Displays”, “Use Awake”, “Use
>   Hidden Icons”)”, l.30 “eight pages”, and the CLI table (`module disable <windowSwitcher|displays|awake|hiddenIcons>`,
>   README:l.435; new `icons` rows; the `Icons.disable.*` kill switches under Hidden kill switches).

---

### G-19 · Major · §4.8 · The main page exceeds DS's ~8-control budget, and the sidebar entry is unspecified

**Finding.** §4.8's main page has:

- a status row with buttons;
- an auto-hide toggle and field;
- launch hide;
- Always Hidden;
- dividers;
- the shortcut;
- an inline How to arrange panel with a diagram;
- the full Sections list, with N rows of pop-ups and Refresh.

That's well over "at most about 8 controls before Advanced…" (DS:l.11).

The sidebar style table is a fixed dictionary of seven roots (`SettingsShell.swift:58–68`, "The seven roots"). The
plan gives no symbol or tint for Hidden Icons, and no position in the order. The "Hover to expand" Advanced row has
no exact label.

**Evidence.** DS:l.11, l.26, l.43, l.57; `SettingsShell.swift:58–68`; `AwakePage.swift:550–554` (NavigationRow
sub-pages); README:l.30.

**Proposed plan text (§4.8).**

> - Main page, exactly: status row, “Hide icons automatically after [10] seconds”, “Hide icons when Snaptic opens”,
>   “Always Hidden section”, “Section dividers”, “Show or hide icons” (shortcut), **Sections ›** (NavigationRow, value
>   “7 hidden”), **How to Arrange…** (ButtonRow, opens a sheet). That's 8. Footer: Restore Defaults… | Advanced… (?).
> - Advanced…:
>   - **“Show icons on hover”** (help **“Shows hidden icons when the pointer rests on the menu bar.”**);
>   - “New apps’ icons” (27);
>   - “When another menu bar app hides icons”;
>   - “Use the full menu bar while icons are shown”;
>   - a **Diagnostics** group (engine, shim, last error code; read-only text, also in General › Diagnostics'
>     report).
> - Sidebar: after Awake, before Permissions. `SettingsRootID.hiddenIcons: ("eye.slash.fill", .teal)`. teal is an
>   existing unused `SettingsTint` case, and the arrow symbol is too close to Menu Bar's `menubar.rectangle`. The
>   doc comment and README:l.30 become “eight”.

---

## Minors

### G-20 · Minor · §4.6, §4.7 · "Hide Icons" is ambiguous, and the shortcut name doesn't follow the menu item

**Finding.** The menu pair "Show Hidden Icons" / "Hide Icons" makes "Hide Icons" read as "hide all icons". The
shortcut "Show or Hide Icons" uses a different noun from the module ("Hidden Icons"). DS naming derives the shortcut
name from the menu item (DS:l.662).

**Proposed plan text.** Use these names:

- menu items **Show Hidden Icons** / **Hide Icons Again**;
- ⌥ alternate **Show All Hidden Icons**;
- shortcut **Show or Hide Hidden Icons**;
- page buttons **Show Icons** / **Hide Icons** (the context makes them clear).

The CLI is unchanged.

### G-21 · Minor · §4.6 · App icons in menu rows need a DS exception

**Finding.** DS:l.718 allows no menu images except device rows and tab attention marks. DS:l.589 adds that the
15-SDK build shows every attached image.

**Proposed plan text.** “DS §5 gains a third exception: hidden-icon rows show the app's icon (16 pt), because the
icon is how people recognize a menu bar item. All rows in the group have one (a generic app icon when none).” Add
this to D1.

### G-22 · Minor · §4.1 · Stale "[Q1] decides whether 14–26 is supported at all"

**Finding.** Q1 is settled (two engines). PLAN:l.139 and the "[Q1]" in PLAN:l.276 are stale.

**Proposed plan text.** Delete l.139. l.276 becomes “On macOS 14–26 it needs a second machine or VM.”

### G-23 · Minor · §4 numbering · §4.9 sits between §4.5 and §4.6

**Proposed plan text.** Renumber full-bar as §4.6 and shift the rest, or move it after §4.8.

### G-24 · Minor · §5 · The manual-check range is inconsistent

**Finding.** A3b cites M23–M25, but PLAN:l.275 says "M1–M22". The new checks from G-2, G-3, G-4, G-14, G-15 and
G-17 also need numbers.

**Proposed plan text.** “The manual checklist (M1–M3n) …”. Renumber after R1, and give each Blocker a named check.

### G-25 · Minor · §0, H5 · "an onboarding card" vs Q6's "step"

**Finding.** PLAN:l.31 and l.107 say "card".

**Proposed plan text.** Use “onboarding step (‘Arrange your icons’)”, per G-12.

### G-26 · Minor · §4.2 · ⌥-click changes meaning for Hidden Bar users

**Finding.** In Hidden Bar, ⌥-click shows or hides the separators and the always-hidden area *without expanding*
(HB MANUAL §Basics). The plan repurposes it as "expand including Always Hidden". That's fine (dividers become a
setting), but it is a muscle-memory change.

**Proposed plan text.** Add it to the Switching table (G-14), already included there.

### G-27 · Minor · §4.3 · "Section dividers" does nothing for `|` on 27

**Finding.** On Native the `|` separator is always invisible (PLAN:l.169), so the toggle only affects `⋮`.

**Proposed plan text.** On 27, the help reads **“Shows the ⋮ divider while icons are shown. On this version of
macOS the arrow marks the edge of the hidden icons.”** Hide the row when Always Hidden is off on 27.

### G-28 · Minor · §4.5 · "Hide icons when Snaptic opens" vs reopening Snaptic to show Settings

**Finding.** README:l.64 tells users to "open Snaptic again" to reach Settings. The plan must say that a reopen
doesn't collapse. The help string is in G-10.

**Proposed plan text.** “Launch collapse runs once per process start, never on `applicationShouldHandleReopen`.”

### G-29 · Minor · §4.7 · CLI help and errors aren't canonical

**Finding.** The plan doesn't give the exact `snaptic icons` help lines or the error texts for these states:

- needs permission;
- paused;
- unavailable.

It also doesn't give the exit codes.

**Proposed plan text.**

- `icons show` while paused exits with code 2 and prints **“Hidden Icons is paused while another menu bar app hides
  icons.”**
- Needs permission: **“Hidden Icons needs Device Control and Data Access. Open Snaptic Settings › Permissions.”**
  (the 14–26 text says Accessibility).
- Unavailable: **“Hidden Icons isn’t available on this version of macOS.”**
- `--all` is valid only with `show` and `toggle`.

Add the rows to README's CLI table.

### G-30 · Minor · H8, D1 · Diagnostics report and kill switches need README rows

**Finding.** README's General › Diagnostics report "lists private-API availability, kill switches" (README:l.156).
`icons.shim` and `Icons.disable.*` need entries there, and in Hidden kill switches (README:l.529).

**Proposed plan text.**

```
defaults write app.snaptic.Snaptic Icons.disable.native -bool true   # Hidden Icons on macOS 27
```

Add one line per switch, with a one-sentence effect each, for example “icons stay shown”.

### G-31 · Minor · §4.5 · Default delay and range wording

**Finding.** Hidden Bar's picker offers 5 s, 10 s, 15 s, 30 s, and 1 minute (`Main.storyboard`). The plan's 2–300 s
value field is fine, but the 2 s floor will collapse while the user is still reading.

**Proposed plan text.** Use a 5–300 s range. Keep “seconds” in the label, and use a value field with a stepper (the
existing number-field pattern).

---

## Not found to be a problem

- **Q4 naming.** "Hidden Icons" / "Icons" / `snaptic icons` fits DS terminology. "Icons" fits the short-title
  fallback (`MenuLayout.swift` `shortTitle`).
- **Autosave names.** `Snaptic.icons.*` doesn't clash with existing items.
- **Off state.** "Off by default, costs nothing when off" matches README:l.21. A4's off-state audit is the right
  check.
