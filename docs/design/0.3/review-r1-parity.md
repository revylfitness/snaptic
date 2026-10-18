# Review r1: feature parity and product (PLAN.md 0.3)

Counts: **2 Blocker, 7 Major, 14 Minor.**

Click counts (Awake own item, defaults): keep awake 1 h = 2 clicks; 90 min = 2 + typing; while app runs = 2 clicks + hover; **while a download/build runs = no manual path**; stop = 2 clicks, **no keyboard path**; extend = 2 (+15 min/+1 h only); display may sleep mid-session = 2. From the Snaptic menu's compact section, add one hover to each.

---

## Blockers

### B1. "Keep awake while this download/build/agent runs" has no simple path (§1.1, §1.2, §2.3, §2.10, §5.3)
**Problem.** The user named this journey explicitly. A download is covered only by the `networkActivity` *trigger* (C5): about 8 steps in Settings, and the result is a standing rule, not a one-off. For builds and agents, `whileApp` sees only NSWorkspace apps ("while Terminal runs" means forever), and the process criterion is Deferred. The CLI's `awake start` with no argument starts **Until Turned Off** (C10), so a crashed script leaves the Mac awake forever. Amphetamine treats "while downloading" as a session type, and `caffeinate -w` is the CI baseline.
**Fix.** Add two session kinds and one CLI verb in 0.3:
- `AwakeSessionKind.untilIdle(cpuBelow: Int, networkBelowKBps: Int, quietSeconds: Int, maxSeconds: Int?)`. Menu item **"Until Downloads and Tasks Finish"**. It ends when CPU < 15% and network < 50 KB/s for 3 min (defaults; editable in a preset), with display policy `maySleep`. It reuses CPUSampler and NetworkMonitor throughput, needs no TCC, and has a 1-minute start grace. Add the preset to the defaults list.
- `AwakeSessionKind.whilePID(pid: Int32, startTime: Double)`. The CLI is the only way to start it. It uses `DispatchSource.makeProcessSource(.exit)` (no spawning, so L3 still holds) and checks the process start time (`proc_pidinfo`) so a reused PID doesn't match. In `pmset`/CLI output it renders as kind "process" with no name.
- CLI: `snaptic awake hold [--pid N | --parent] [<duration>]`, bound by default to the CLI client's parent process, so the session ends with the script. `awake start` with no argument never starts an indefinite session from the CLI (cap it at 1 h). Add a README recipe for builds.
- Note in §1.2 that `whilePID` covers the agent case that the deferred process criterion was meant for.

### B2. "No 0.2 capability lost" is unproven, and several 0.2 controls map nowhere (§4.3, §4.6, §6.5)
**Problem.** §4.6 checks *data* ("fixture loads with no setting lost"), not *reachability*. Checking every [UA] §2.2 control against §4.3, these have no destination:
- Resolution: the quick actions (Toggle HiDPI, Native, Default, Native ÷ 2, Toggle Notch), **Undo/Redo**, **Add to/Remove from Favorites**, and Forget remembered resolution. The menu submenu (§5.2) lists only modes, so these are gone from the menu too.
- The **resolution slider** is gone from the root page and the menu (no sliders in submenus), yet "Only native aspect ratio on the slider", "Show values as" and "Snap to favorites" stay in Advanced, and §4.5 still names a resolution `MenuSliderRow`. That contradicts itself.
- **Remembered (disconnected) displays: Forget…, Forget All…** Display Details is per *connected* tile.
- **Own-icon glyph pickers** for the Switcher and Displays items (`GeneralPages.swift` MenuPage). Menu Bar shows glyph tiles only for Snaptic and Awake.
- Switcher **"Preview the selected window"** (`previewSelected` / feature `preview`).
- Smaller items: Identify/Redetect/Show Panel buttons; DDC Read Capabilities/Check Connection; Color "Reset This Display" and profile Restore Previous; indicator Preview; XDR Test; "Save Current State as Protected"; virtual Reconnect/Disassociate/Discard All; PIP "⌃⌥⌘P stops streams"; Remembered resolutions; the "Unavailable on this Mac" list; the Menu page hidden-icon warnings.

**Fix.** Add **§4.8 "0.2 → 0.3 control map"**: one row per 0.2 control (from [UA] §2.2) with destination V/A/S/sheet/menu-only/removed and a reason. Make it normative. Add a Kit test: every `Codable` key path in the 0.2 fixture maps to a `SettingsSearchEntry` id or to an entry in an explicit `removedSettings` table that carries a reason. Concrete placements:
- Resolution quick actions, Undo/Redo and Favorites go to a "Resolution ▸ More" disclosure on the root page under the pop-up. Undo/Redo also go into the display submenu.
- Decide the slider question. Recommended: keep the resolution slider on the Resolution sub-page/Advanced as a `SliderSetting`, and delete the slider-only options if the slider goes.
- Add a "Remembered Displays…" row in Displays › Advanced.
- Add a glyph-tile row under each module's "Own icon" switch.
- Add "Preview the selected window" to Switcher Behavior (V).

---

## Major

### M1. The Awake indicator has three overlapping off switches (§1.1 `indicator`, §2.14 `AwakeIndicatorStyle.hidden`, C2 `MenuPresence.ownItem`)
**Problem.** The `indicator` feature, `ownItem` and style `.hidden` each remove the Awake icon, so it is unclear which one wins.
**Fix.** Make `MenuPresence.ownItem` the only control. Remove `.hidden` from `AwakeIndicatorStyle` (style = `icon | iconAndTime`). Make `indicator` an always-on internal capability (kill switch only), not a user feature.

### M2. With Awake off the Snaptic icon and no own item, a running session is invisible. There is also no "only while active" option (§5.2–5.5, C2)
**Problem.** The user wants an indicator beside the Snaptic icon, and with 26/27 overflow every item costs notch space. The plan offers only "always" or "never". A user who chooses `inSnapticMenu` only gets no sign that the Mac is being kept awake.
**Fix.**
- Add `AwakeIndicatorVisibility { always, whileActive }`. The default for fresh installs is `whileActive` + `inSnapticMenu: true`: one icon at rest, and the Awake icon appears beside it during a session. Upgraders with the migrated trigger get the same.
- When `ownItem == false`, the Snaptic glyph switches to an active variant (badge dot or `.fill`) while Awake governs, and its accessibility label appends ", keeping your Mac awake".
- Don't allow `(ownItem: false, inSnapticMenu: false)` for Awake; show the help line "Awake needs a place in the menu bar or a shortcut" and refuse unless a shortcut is bound.

### M3. The Snaptic item's behavior is undefined when no module is in it; Quit hides behind ⌥ (§5.2, §5.3)
**Problem.** An Awake-only user gets a Snaptic item reading "No Modules Are On" although Awake runs, Quit only as an ⌥ alternate, and no way to reach Recent Notices.
**Fix.** Rule: the Snaptic item is shown only if some module has `inSnapticMenu` on, or no module has an own item. When it's absent, every own-item menu ends with native **Settings…** and **Quit Snaptic ⌘Q** items (not alternates), and Awake's menu gains Recent Notices ▸ when there are notices.

### M4. Stopping a session has no keyboard or VoiceOver path in the Awake menu (§5.3, C4)
**Problem.** Start/stop lives only in a hosting `switchHeader`, and the plan says hosting rows are never clickable or focusable. Every preset is native, but stopping isn't. That fails "Apple-quality" and [PA] §8 ("Make every menu action keyboard-reachable").
**Fix.** While a session is active, add a native **"Turn Off Keep Awake"** item right after the detail lines. Keep the switch for the mouse. Add VoiceOver and arrow-key navigation to HW-15.

### M5. "Display may sleep by default" silently edits one preset (§4.3 Awake)
**Problem.** The toggle looks global but changes only the default preset's policy. A user turns it on, picks "1 Hour" from the menu, and the display still stays on.
**Fix.** Add `AwakeSessionsConfig.defaultOptions: AwakeSessionOptions`. Change `AwakePreset.options` to `AwakeSessionOptions?` where nil means "Use default". The toggle edits `defaultOptions`. The preset editor shows "Display: Default (May sleep) / Keep on / May sleep / …". Kinds `whileApp` and `untilIdle` default to `maySleep` (also answers OQ-2 for the case where the user isn't looking at the screen).

### M6. Duplicate 4 comes back (§4.3 Display Details vs §4.4 #4)
**Problem.** Display Details lists "Show in the menu and the Displays panel", while §4.4 says per-display visibility lives "Menu Bar › Customize Displays Menu… only".
**Fix.** Remove it from Display Details. Put a NavigationRow-style link there: "Menu visibility… → Menu Bar › Customize Displays Menu", pre-selecting the display.

### M7. Two "Awake" switches mean different things (§4.3 Awake header, §5.3 Keep Awake switch)
**Problem.** At the top of Settings › Awake, a header switch labelled "Awake" turns the *module* on or off. In the menu, "Keep Awake" turns a *session* on or off. A normal user reads the Settings switch as "keep my Mac awake now", and turning it off removes the icon and every trigger.
**Fix.** Label the header switch "Use Awake" (help: "Off removes Awake from the menu bar and stops automatic sessions"). The status row beneath it gets a prominent **Keep Awake** / **Turn Off** button. Turning the module off while a session or enabled trigger exists asks for confirmation and names what stops.

---

## Minor

1. **§1.3 DNS exclusion reason is wrong.** DNS isn't brand-specific, and `State:/Network/Global/DNS` is TCC-free. Either add `network(.dnsServer)` or change the reason to "subnet + router cover it".
2. **§1.4 SSID.** Name the router criterion as the SSID substitute; label it **"Connected to this network"** in the editor.
3. **§1.2 Lock screen reason.** `NSWorkspace.openApplication(ScreenSaverEngine)` is public and doesn't spawn a process. Keep it Deferred, but the reason should be "locks only if 'require password' is immediate; can't verify the setting [PA] §7".
4. **§1.3 not listed.** Hold-to-end ([AP] §3.1.5) and the soft reminder for indefinite sessions ([AP] §3.1.1) are missing. Hold-to-end: Excluded, because a menu stop already takes two deliberate clicks. Reminder: In, as a one-time toast after 8 h, "Awake has kept your Mac awake for 8 hours", with **Turn Off** / **Keep Going**.
5. **§1.1 vs §5.3 Extend.** §1.1 promises +2 h and custom extend; the menu has +15 min/+1 h only. Show the Add items only for timed kinds (extending indefinite or whileApp is a no-op per `AwakeClock.extended`). Add an "Add…" item that opens the Custom panel in extend mode.
6. **§2.5 Replacing silently.** Starting "1 Hour" during "While Xcode is running" drops the app condition. Either let a whileApp/untilIdle session carry an optional cap ("…, at most 3 h") so Extend means something, or show "Replaces: While Xcode is running" as the detail line of the ✓ section.
7. **§5.3 Last end not shown.** Add a detail row, "Ended at 3:12 AM: battery below 20%", for 12 h after a non-user end, plus a Recent Notices entry. Anyone away during a download misses the toast.
8. **§2.5 Toasts while presenting.** On mirrored or full-screen displays, send the toasts to Recent Notices instead.
9. **§2.5 "Start Anyway" in a menu** is unspecified (a click closes the menu). Use a toast with a **Start Anyway** button.
10. **§5.3 Trigger rows.** A click **disables the trigger permanently** when the user probably means "not now". Make the rows read-only status with an ⌥ alternate "Turn Off 'Desk dock'". Show active triggers plus ≤ 4 others, then "Edit Conditions…".
11. **§5.1 vs §5.3/5.4.** App icons in "While an App Is Running" break the images rule; add app rows as an exception. The compact "Keep Awake For ›" with apps inline exceeds ~8 items; keep apps in their own submenu.
12. **§4.3 General footer.** "Restore Defaults…" there means Reset **All**; everywhere else it is page-scoped. Rename it **"Reset All Settings…"** (destructive style).
13. **§5.5 Relaunch rule regressed.** 0.2's rule is "opening Snaptic again always shows Settings"; "known visible" can't detect hiding on 26/27. Restore "always", and keep the 0.2 hidden-icon warnings on Menu Bar.
14. **Options to cut**: "Different icon for automatic sessions", "Show seconds" (show seconds in the last minute only), "Also end on serious heat" (keep the warning toast), and the activity interval (fix it at 60 s). Add a "Menu bar icon ›" link on the Awake page and the search synonyms lid, clamshell, jiggle, prevent sleep, screen saver.

Also: migration M1 should enable the trigger only if 0.2 sleep prevention was **effective** (Displays running + feature on + ≥ 1 display flagged), not merely raw-on. Sleep Status… should report a system-wide `SleepDisabled` flag left by Amphetamine Power Protect or Insomnia (`IOPMCopySystemPowerSettings`), plus a README note on switching from those apps and cleaning up sudoers. Keep "Restore All Displays" top-level while a confirmation is pending.

Journeys: first run, upgrade, battery and video calls are mostly fine once M1–M5 land. Presentations: Minor 8. Downloads/CI: B1.

