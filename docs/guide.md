# Snaptic Guide

The complete manual for Snaptic: every setting, command, safety rule, and limitation. For a quick overview, see the [README](../README.md).

A free, open-source menu bar toolkit for macOS: a Windows-style **window switcher**, a set of **display utilities**, **Awake**, which keeps your Mac awake when you want it to, **Hidden Icons**, which tucks the menu bar icons you don’t need behind an arrow, and **Dock Previews**, which shows an app’s windows when you point at it in the Dock. Turn on only the parts you want; everything else stays off and costs nothing.

**Website:** [snaptic.dev](https://snaptic.dev)

Snaptic is MIT-licensed and written from scratch in Swift by revyl fitness technology, Inc. It isn’t affiliated with or derived from AltTab, BetterDisplay, MonitorControl, Lunar, Amphetamine, or Insomnia; it’s an independent take on the same ideas, with everything included and nothing behind a paywall. Hidden Icons follows the design of [Hidden Bar](https://github.com/dwarvesf/hidden) (MIT) in its own code, and isn’t affiliated with it either. Dock Previews follows ideas from [DockDoor](https://github.com/ejbills/DockDoor) (GPL-3.0) in its own code; it shares no code with it and isn’t affiliated with it. Third-party credits are in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). What changed is in the release notes for [0.5.0](design/0.5/RELEASE-NOTES-0.5.0.md), [0.4.0](design/0.4/RELEASE-NOTES-0.4.0.md), [0.3.1](design/0.3.1/RELEASE-NOTES-0.3.1.md), and [0.3](design/0.3/RELEASE-NOTES-0.3.md).

- [Modules](#modules) · [Settings](#settings) · [Window Switcher](#window-switcher) · [Displays](#displays) · [Awake](#awake) · [Hidden Icons](#hidden-icons) · [Dock Previews](#dock-previews) · [Safety](#safety)
- [Permissions](#permissions) · [Command line](#command-line) · [Hidden kill switches](#hidden-kill-switches) · [Install and build](#install-and-build) · [Updates](#updates)
- [Privacy and security](#privacy-and-security) · [Upgrading and downgrading](#upgrading-and-downgrading) · [Troubleshooting](#troubleshooting) · [Known limitations](#known-limitations) · [Not included](#not-included) · [How it works](#how-it-works)

## Modules

| Module | What it does |
|---|---|
| **Window Switcher** | Hold **⌥ Option**, tap **Tab**, and pick any window, not just any app. |
| **Displays** | Brightness and volume for external displays, resolutions and HiDPI, color, arrangement, virtual displays, Picture in Picture, and more. |
| **Awake** | Keeps your Mac awake for a while, until a time, while an app runs, until downloads and tasks finish, or automatically when conditions you choose are met. A free replacement for Amphetamine and Insomnia that needs no administrator password, except for opt-in lid-closed mode, which asks for one each time. |
| **Hidden Icons** | Hide the menu bar icons you don’t need behind an arrow. Click the arrow to hide the icons to its left, click again to show them, or open one from the Snaptic menu without showing them all. A free replacement for Hidden Bar. |
| **Dock Previews** | Point at an app in the Dock to see its windows, including minimized and hidden ones, and click one to bring it forward. Close, minimize, hide, or quit from the preview, with the pointer or with ⌘W, ⌘M, ⌘H, and ⌘Q. |

Each module can be turned on or off on its own: in **Settings › General › Choose what Snaptic does**, or with the switch at the top of the module’s own page (“Use Window Switcher”, “Use Displays”, “Use Awake”, “Use Hidden Icons”, “Use Dock Previews”). A module that is off runs nothing: no event taps, timers, observers, IOKit handles, power assertions, private-API calls, helper processes, or permission prompts. Inside Displays and Awake, each feature has its own switch where the feature is used, and anything that’s off costs nothing either.

- **First launch:** onboarding asks which modules you want, then asks only for the permissions those need, and whether Snaptic should keep itself up to date (**Check Automatically** or **Not Now**). It picks up where it left off if macOS makes Snaptic relaunch.
- **Upgrading from 0.3.2 or later:** Snaptic updates itself, and none of your settings change. You’ll see Dock Previews as a new, off module. A “New: Dock Previews” card in General offers **Turn On Dock Previews**; coming from 0.3.x, a “New: Hidden Icons” card shows too, and the app has a new icon. The Window Switcher now also shows thumbnails of minimized windows and windows on other Spaces where macOS allows it (see [Upgrading and downgrading](#upgrading-and-downgrading)).
- **Upgrading from 0.3.1 or earlier:** download the latest release by hand one last time (0.3.0 and earlier have no updater, and 0.3.1 doesn’t start); from then on Snaptic updates itself. Because releases from 0.3.1 on are signed by their developer, macOS asks you to allow Accessibility and Screen Recording again once, and a “Welcome to Snaptic 0.3.1” card in General walks you through it (see [Upgrading and downgrading](#upgrading-and-downgrading)).
- **Upgrading from 0.2:** Window Switcher and Displays stay as they were. Awake starts off, with a “New: Awake” card in General, unless you used Displays’ display sleep prevention in 0.2; then Awake is on and keeps doing that job (see [Upgrading and downgrading](#upgrading-and-downgrading)). As for 0.3.0, it’s one last manual download, and the “Welcome to Snaptic 0.3.1” card shows too.
- **Upgrading from 0.1:** the switcher stays on; Displays and Awake start off, each with its own card. As for 0.3.0, it’s one last manual download, and the “Welcome to Snaptic 0.3.1” card shows too.

## Settings

Settings has nine pages in its sidebar: [General](#general), [Menu Bar](#menu-bar), [Window Switcher](#window-switcher), [Displays](#displays) (with its own sub-pages), [Awake](#awake), [Hidden Icons](#hidden-icons), [Dock Previews](#dock-previews), [Permissions](#permissions), and About. The search field at the top of the sidebar finds any setting, including the ones in **Advanced…** sheets, and highlights it on its page. Every page that has a (?) button links to its section of the README, which links on to the matching section here.

Most pages show the settings people change often and keep the rest in an **Advanced…** sheet at the bottom. Every slider has a value field you can type into, and a reset button when it has a default. **Restore Defaults…** on a page or sheet resets only that page’s settings.

## General

- **Choose what Snaptic does:** a switch per module, with a line on what each does.
- **Open at login.** If macOS needs you to allow Snaptic in Login Items, the page says so and opens the right pane.
- **Command-line control:** lets scripts and other apps control Snaptic with the `snaptic` command (off by default). **Copy Install Command** copies the Terminal command that installs it; see [Command line](#command-line).
- **Backup:** **Export Settings…** and **Import Settings…** (see [Privacy and security](#privacy-and-security) for what an export leaves out).
- **Advanced…:** “Commands can skip confirmation” (a display change sent with `--yes` applies without asking first), the exit codes the `snaptic` command uses, **Restart in Safe Mode…**, and **Reset All Settings…**.
- New-module cards (“New: Dock Previews”, “New: Hidden Icons”, “New: Awake”, “New: Displays”) and the “Welcome to Snaptic 0.3.1” card appear here once after an upgrade.

## Menu Bar

Everything about Snaptic’s menu bar icons lives on this page.

- **Where each module appears:** one pop-up per module with the same choices Control Center uses: **Always Show in Menu Bar**, **Show When Active**, **Show in Snaptic Menu**, and **Don’t Show**. Window Switcher has no “Show When Active”. For Displays it means “while an external display is connected”; for Awake, “while your Mac is being kept awake” (Awake’s default). Hidden Icons has its own two choices, **Arrow and Snaptic Menu** (default) and **Arrow Only**: “The arrow is always in the menu bar. Arrow and Snaptic Menu also lists hidden icons in the Snaptic menu, so you can open one without showing them all.” Its pop-up is dimmed with “Off” while Hidden Icons is off. Dock Previews has only **Show in Snaptic Menu** (default) and **Don’t Show**; with **Don’t Show**, its help reads “Previews show when you point at the Dock. Change them in Settings.”
- **Icons:** a choice of icon for each module that has its own item and for the Snaptic icon.
- **Awake time:** **Don’t Show** (default), **Time Remaining**, or **End Time** next to Awake’s icon, in your system’s 12- or 24-hour setting, with seconds only in the last minute.
- **Show Keep Awake with the Lid Closed in the Awake menu** (Macs with a battery; dimmed while Awake is off): lets you turn on [lid-closed mode](#keeping-awake-with-the-lid-closed) from the Awake menu, which asks for an administrator password each time. It’s the same switch as on the Awake page, and like that one it’s locked while lid-closed mode is on.
- **Displays menu:** **Standard** or **Compact** style (one slider per display), “Scroll over a slider to adjust it”, and **Customize Displays Menu…**, where every optional menu item can be shown, moved into a submenu, or hidden.
- **Restore Menu Bar Defaults…** resets where each module appears (Hidden Icons’ choice too), the icons, Awake’s time, and the Displays menu. The lid-closed switch is Awake’s setting, so it stays; **Awake › Advanced… › Restore Awake Defaults…** resets it (not while lid-closed mode is on; it then stays on and Snaptic says so).

**Tabs in the Snaptic menu.** The Snaptic icon appears when a module is set to Show in Snaptic Menu, or Hidden Icons to Arrow and Snaptic Menu. With two or more, the Snaptic menu shows a tab for each, in the order Window Switcher, Displays, Awake, Icons, Dock (the first three out of the box; Icons once Hidden Icons is on, and Dock once Dock Previews is on), and only the selected module’s items below the tabs. With one module the menu has no tabs and shows that module’s section as before.

- **Switching:** click a tab, or, while the menu is open, ⌘1, ⌘2, and so on choose a tab (one key per tab, by position). A keyboard choice closes the menu, and the next open shows that tab. Each tab’s tooltip names its shortcut.
- **Remembered:** the menu opens on the tab you last chose, also after a relaunch. If that module isn’t in the menu right now, the first tab shows, and your choice comes back when the module does. No reset clears it.
- **Nothing hidden:** Safe Mode and “Sleep Is Turned Off” rows stay above the tabs, whichever tab is showing. A tab whose module needs attention (Displays is degraded, paused after Restore All Displays, or unprotected, or Window Switcher is missing Accessibility; “Paused while … runs” doesn’t count, except for Hidden Icons, whose tab is marked while it needs permission, is unavailable, or is paused; Dock Previews’ tab is marked while it needs Accessibility, after it couldn’t read the Dock for 2 minutes, or after macOS turned off its Dock click actions or keyboard shortcuts) shows a small exclamation mark, and VoiceOver adds “needs attention”. While Awake keeps your Mac awake, VoiceOver reads its tab as “Awake, on”.
- **Awake’s tab** has the full Awake menu rows except Awake Settings…. The compact Awake section is used only when Awake is the only module in the Snaptic menu.
- **Keyboard and VoiceOver:** the tabs are one segmented control, so VoiceOver users reach it and pick a segment with VO-Space. While VoiceOver, Switch Control, or Full Keyboard Access is on, the menu also lists **Show Window Switcher Tab**, **Show Displays Tab**, **Show Awake Tab**, **Show Hidden Icons Tab**, and **Show Dock Previews Tab** above Snaptic Settings…, with the same shortcuts. Type-select reaches only the visible tab.
- **Size:** the menu is as wide as its widest tab from the start, so a tab never moves under the pointer; its height changes when you switch.
- The footer is unchanged: More Display Features… (while Displays is off), Recent Notices, an update row when one is waiting (see [Updates](#updates)), Snaptic Settings… (⌘,), and Quit Snaptic (⌘Q).

A running Awake session is never invisible: whenever Awake keeps your Mac awake, the Snaptic icon shows its active look, and if no Snaptic icon is shown, Awake’s own icon appears for the session. With every icon hidden, open Snaptic again from Finder or Spotlight to get to Settings; shortcuts keep working. macOS can also hide menu bar icons, including the Hidden Icons arrow (System Settings › Menu Bar, and the overflow on notched Macs), so every menu action is also available in Settings or as a shortcut. Opening Snaptic again always shows Settings.

## Window Switcher

| | |
|---|---|
| **Every window** | Each window gets its own tile: several windows of one app, minimized and hidden windows, and windows on other Spaces, each with a badge. Optionally, apps with no open windows too. |
| **Recently used order** | The window you’re in comes first, then windows in the order you last used them, so a quick ⌥⇥ goes back to the previous window. |
| **Thumbnails** | Previews of each window, captured with ScreenCaptureKit each time the switcher opens. Minimized windows and windows on other Spaces get them too, when macOS allows it; otherwise they show the last one Snaptic saw, then the app icon. The switcher opens with the thumbnails from the last 30 minutes and refreshes them in place. |
| **Full-size preview** | The selected window is shown at its real size and position while you choose. |
| **Three styles** | Thumbnails, app icons, or a compact list of titles. |
| **Search** | Press S (or /) while the switcher is open, then type to filter by window title or app name. |
| **Auto-size** | Thumbnails are as large as fits on screen; with many windows the panel scrolls. |
| **Up to 9 shortcuts** | Each with its own keys, style, and filters: all windows, active app, or this screen; all Spaces, current, or others; minimized and hidden windows; apps without windows; and one entry per app (like ⌘⇥). |
| **Window actions** | W closes the selected window, M minimizes or restores it, F switches to it and toggles full screen, Q quits its app (Finder only if its Quit menu item is enabled), and H hides or shows its app. W, M, and F work on windows on the current Space. Hovering a tile shows close, minimize, and full-screen buttons too. |
| **Gather windows** | Moves every window onto the display under the pointer, from the menu or a shortcut (a shortcut asks first). |
| **From the menu** | “Switch Windows” opens the switcher and keeps it open until you press Return or Esc or click. |
| **Mouse and keyboard** | Arrows move in the grid, ⇧ goes backwards, Return switches, Esc clears the search or cancels, and a click picks. Selecting by hovering is optional. |
| **Exceptions** | Hide apps from the switcher, and let virtual machines and remote desktops keep the shortcut (by default only while they’re full screen). Entries match by prefix, so `com.parallels` covers every Parallels app. |
| **Multiple displays** | Opens on the screen with the active window, or the one with the pointer. |
| **Accessible** | Selection changes are announced to VoiceOver. |

| Default shortcut | What it does |
|---|---|
| ⌥ ⇥ | All windows, thumbnails |
| ⌥ (key above Tab) | Windows of the app you’re in |

The Window Switcher page has the main shortcut, **More Shortcuts…**, “Switch when you release the keys”, what to show, the style, the preview, thumbnail size, minimized and hidden windows, and which Spaces and screens to list. Its **Advanced…** sheet has the rest: thumbnails on or off, where the switcher opens, apps without windows, one window per app, search, the window action keys, hover buttons, selecting on hover, ⌘⇥ takeover, apps that keep the shortcut, hidden apps, and the Privacy section it shares with Dock Previews (see [Private windows](#private-windows)). **Window thumbnails** is the switcher’s own setting, separate from Dock Previews’ one: with it off, every shortcut shows app icons and no live preview, and the Window Switcher never asks for Screen Recording.

“Key above Tab” is detected for both US (ANSI) and European (ISO) keyboards. You can add ⌘⇥ to replace the built-in macOS switcher. Snaptic gives it back whenever it quits, whenever it can’t see key presses, and on the next launch if Snaptic ever crashed. If you had already turned that shortcut off yourself, Snaptic leaves it off.

### Private windows

The Window Switcher and Dock Previews share one **Privacy** section, in each one’s **Advanced…** sheet: a change on one sheet shows on the other.

- **Protect private windows** (on by default): “Password managers and private browsing windows show their app icon instead.”
- **Never show thumbnails for** (shown while **Protect private windows** is on): “These apps show their icon and name instead of a picture or window title, in the Window Switcher and Dock Previews.”
- **The footer** in the switcher’s sheet: “Thumbnails stay in memory and are never saved. They’re cleared after 30 minutes, and when your Mac locks or sleeps. These settings also apply to Dock Previews.” Dock Previews’ sheet ends with “These settings also apply to the Window Switcher.”
- **Restore Defaults… leaves them alone**, on either sheet: “Window Switcher settings go back to their defaults. Protect private windows and its app list stay as they are, because Dock Previews uses them too.” Only **General › Advanced… › Reset All Settings…** resets them. Importing settings can add apps to the list, but never removes one.
- **In Dock Previews**, a private browsing window’s card shows its app icon and “Private window”, and a protected app’s card shows its icon and name. Neither has a title or a thumbnail, and neither is captured or kept.
- **Hidden apps are separate:** **Apps hidden from the switcher** and **Apps hidden from Dock previews** each affect only their own module. The second says “Pointing at these apps in the Dock shows nothing. The Window Switcher isn’t affected.”

### When a window feature stops

The Window Switcher and Dock Previews share a few private macOS functions (see [Undocumented APIs](#undocumented-apis)). If one of them makes Snaptic crash, Snaptic stops using it on that macOS version and falls back, and the page names the feature: “… stopped after a problem in macOS. Snaptic tries again after a macOS update.”, with **Try Again**. If macOS answers in a way Snaptic didn’t expect, it says “… stopped because macOS answered in a way Snaptic didn’t expect. Quit and reopen Snaptic to try again.”, with no button.

| Feature | Without it |
|---|---|
| Thumbnails of minimized windows and windows on other Spaces | The last thumbnail Snaptic saw, then the app icon |
| Matching cards to their windows | Cards are matched by title and position; a card without a match offers only **Bring Forward** |
| Bringing windows forward from other Spaces | Windows are raised with Accessibility; a window on another Space only switches to its app |
| Showing windows on other Spaces | Windows on other Spaces aren’t listed |
| Using ⌘⇥ for the Window Switcher | macOS keeps ⌘⇥ (Window Switcher only) |
| Reading the keyboard layout | The key above Tab is found as on a US (ANSI) keyboard (Window Switcher only) |

To turn one of these off yourself, see [Hidden kill switches](#hidden-kill-switches).

## Displays

Grouped like the Displays page and its sub-pages. **On** = on by default once Displays is on; **Opt-in** = off until you turn it on; **Beta** = depends on hardware behavior not yet verified on every Mac; **Experimental** = off by default and labeled so. Each feature’s switch sits where the feature is used: at the top of its sub-page, at the top of its section, or in **Displays › Advanced… › Use Snaptic for**.

### The Displays page

- **One card per display:** brightness, resolution, and refresh rate, live while you watch. **Display Details…** has the display’s name and icon, whether it shows in the menu, Copy Settings From, Forget This Display, connection (disconnect, and turning the built-in display off when an external one connects), Match Text Size, and menu bar overlays.
- **Resolution (On):** modes and refresh rates, HiDPI on or off, native, default, or half native, undo and redo, favorites, notch-aware modes, and remembering the mode you chose. New modes ask before they stick. Show all resolutions (Experimental) also lists modes macOS hides.
- **Arrangement (On):** set the main display, arrange (canvas, plus a Position and Align form in **Arrange…**), and mirror or stop mirroring. Rotation (Opt-in, Beta); Underscan and the HDR switch (Experimental).
- **Disconnect displays (Opt-in, Beta; Experimental on Intel):** turn a display off without unplugging it. Turning the built-in display off automatically (Opt-in) when an external one connects is refused unless the external display answers DDC with power on (or is an Apple display), and isn’t available on iMacs and some base M3 models.
- **Match Text Size (Opt-in):** makes text the same size on two displays (preview, then confirm).
- **Display Tools:** Identify Displays, Redetect Displays, Connect All Displays, Disconnect All But Main, Match Text Size…, Show Displays Panel (with an optional shortcut; it opens the same controls at the pointer, even when the menu bar icon is hidden in the overflow), and Restore All Displays.
- **Sub-pages:** [Brightness and Dimming](#brightness-and-dimming), [Color](#color), [Hardware Controls](#hardware-controls), [Keyboard](#keyboard), [Saved Layouts](#saved-layouts), [Virtual Displays](#virtual-displays), [Picture in Picture](#picture-in-picture), [Automations](#automations), and [Display Information](#display-information).

### Brightness and Dimming

- **Brightness control (On):** one slider per display, whatever the method. Methods (all On; at least one is needed, in **Advanced…**): Apple native brightness (Apple displays and built-in screens), hardware brightness (DDC, the display’s own backlight), color table dimming, and overlay dimming. Below a switchover level the hardware stays at its minimum and software dims further.
- **Restore brightness at login and wake (On),** never below 15%; smooth transitions.
- **Sync brightness (Opt-in):** other displays follow a sync source, at the same level or by the same change, with an offset.
- **Opt-in:** Dim when the screen locks, Dim all the way to black (only while another display stays visible; otherwise software dimming stops at 8%), and Show brightness in nits.
- **Extra brightness (Opt-in, Beta):** goes past the SDR maximum on XDR and HDR displays; pauses when the Mac is hot, in Low Power Mode, below a battery level, and while locked.

### Color

- **Color adjustments (Opt-in):** software contrast, gamma, temperature, black and white levels, and invert colors, per display or for all; each slider resets on its own. **Advanced…** has gain and per-channel gamma, shortcut steps, and “Pause adjustments on all displays”.
- **Color profiles (Opt-in):** pick an ICC profile per display, here or from the menu.
- **Experimental:** Night Shift on or off and its warmth (schedules stay in System Settings), and Apple display presets.

Adjustments show in screenshots and don’t reach AirPlay, DisplayLink, or Sidecar displays. Restore All Displays resets them.

### Hardware Controls

- **Hardware controls (On):** brightness, contrast, and volume (with mute) on the display itself, read from its capabilities, with per-control range tuning and optional readback. The page shows whether each display answers.
- **Opt-in, in Advanced…:** Input switching (named inputs, LG alternate inputs), Power control (standby and wake), and Custom hardware controls (your own VCP codes, raw get and set), plus timing options for displays that miss changes.
- Commands that can switch the picture away or change power ask first. Manufacturer codes E0–FF must be unlocked per display. Reset and factory codes are never sent.

### Keyboard

- **Brightness keys and Volume keys (Opt-in, need Accessibility):** the keyboard’s keys drive external displays and their speakers (only displays that report a volume control). Hold ⌥⇧ for fine steps; more modifier combinations are in **Advanced…**.
- **Brightness and volume indicator (On):** a HUD for changes, in “Rounded” or “Classic” style, at a position you choose, or the system’s own indicator.
- **Keyboard Shortcuts… (On):** global shortcuts for any display action, including input slots and the Restore All Displays shortcut. They work without Accessibility, also in password fields.
- **Brightness broadcast (Opt-in, in Displays › Advanced…):** lets other apps draw their own indicator from Snaptic’s changes (see [Privacy and security](#privacy-and-security)).

### Saved Layouts

- **Saved layouts (Opt-in):** save and apply layouts, optionally automatically when the same displays connect. **Protect arrangement (Opt-in)** puts the arrangement back when something else changes it (for example the macOS 27.2 arrangement-restore bug).

### Virtual Displays

- **Virtual displays (Opt-in, Beta):** displays that exist only in software, with templates (Headless, Recording 16:9, Teleprompter, Portrait) and associations with real displays. Sharper text (Smart HiDPI, Opt-in, Beta) gives sharp text at any size on external displays; HDR virtual modes are Experimental.

### Picture in Picture

- **Picture in Picture (Opt-in, needs Screen Recording):** a live copy of a display or a window in a floating window (crop, click-through, orientation), or a display streamed full screen onto another. Filters (Opt-in): built-in Core Image filters and imported 3D `.cube` LUTs.

### Automations

- **Automations:** event hooks (Opt-in) run a program when a display connects or disconnects, or when the Mac sleeps or wakes; custom actions (Opt-in) put your own programs in the menu, on shortcuts, and (if you mark them) on the command line.

### Display Information

- **Report:** a live report about your displays, with **Copy Report** and **Export…**. It has no display names, serial numbers, window titles, or app names, and identifiers are masked. It lists private-API availability, kill switches, helpers, and recent events.
- **Safety helper** and **undo journal** status, with **Restart Snaptic** (which restarts the helper) when it stopped.
- **EDID:** export the data a display reports about itself (Export EDID…).
- **Remembered displays** (forget one, or all that aren’t connected) and **remembered resolutions**.

### Displays Advanced Settings

**Use Snaptic for** turns whole areas on or off: brightness control, resolution control, arrangement and mirroring, rotation, keyboard shortcuts for displays, the brightness indicator, and disconnecting displays. **Experimental** has the High Dynamic Range switch, underscan, built-in auto-brightness, brightness broadcast, and showing all resolutions. The sheet also has **Confirm display changes** (see [Safety](#safety)) and **Other display apps**: if BetterDisplay, MonitorControl, or Lunar is running, Snaptic pauses its overlapping features by default (“Paused while MonitorControl runs”) or runs both if you choose. **Resolution filters** choose which modes the Resolution pop-up, the menu, and the slider offer (HiDPI or standard sizes, widths, refresh rate).

## Awake

Awake keeps your Mac from going to sleep while you want it awake, with the same public macOS power assertion `caffeinate` uses. Its sessions need no administrator password, install nothing, and leave nothing behind: if Snaptic quits or crashes, macOS releases the assertion at once and your Mac sleeps normally again. (Snaptic as a whole installs nothing either, except Sparkle’s update cache in release builds; see [Updates](#updates).) The one exception is opt-in [lid-closed mode](#keeping-awake-with-the-lid-closed), which asks for an administrator password each time you turn it on and turns sleep back on when it ends.

Turn it on with **Use Awake** at the top of the Awake page. The page has a status row (**Keep Awake ▾** while nothing runs, **Options ▾** and **Turn Off** while a session or rule runs, **Keep Awake ▾** and **Turn Off** while only command-line holds run, and **Pause Rules ▾** or **Resume** whenever you have rules), Sessions, End sessions automatically, Lid closed (Macs with a battery), Start automatically, Keyboard, Drives ›, History ›, and **Advanced…**.

### Sessions

A session keeps your Mac awake until it ends. Start one from the Awake menu (**Keep Awake**, or **Start Session ›** and **While an App Is Running ›**), from the status row on the Awake page, with a shortcut, or from the command line.

| Kind | Ends |
|---|---|
| **Until Turned Off** | When you turn it off. After 8 hours a reminder asks whether to keep going. |
| **For a while** (30 min, 1 h, 2 h, 5 h, or **Custom…**) | When the time is up. Time keeps counting while the Mac sleeps and isn’t affected by clock changes. |
| **Until a time** | At that clock time. |
| **While an app is running** | When the last copy of the app quits; optionally “At most” a number of hours. |
| **Until Downloads and Tasks Finish** | After 5 minutes with no activity, and never in its first 10 minutes. Activity means one of your processes using at least half a core, 3 or more new processes in 5 seconds (build steps), total CPU at least 15%, disk at least 1 MB/s, or network at least 50 KB/s. Optionally “At most” a number of hours. |
| **Command-line hold** | When the command or process it’s tied to ends (see [Awake commands](#awake-commands)). Holds run beside any session. |

- **Keep the display on** (default on): when off, your Mac stays awake but the display can turn off. Each session can keep the display on, let it turn off, or keep it on until you’ve been idle for a number of minutes; change it mid-session with **Keep Display On** in the menu or **Options ▾**.
- **Add time:** **Add 15 Minutes**, **Add 1 Hour**, and **Add Time…** for sessions with an end. No session runs longer than 30 days, extensions included.
- **5 minutes left:** a reminder with **Add 1 Hour**.
- **Default session:** what Keep Awake and its shortcut start (Until Turned Off out of the box).
- **Sessions in the menu** (session types): up to 12 named sessions in your order, each with its own kind and, if you want, its own display and activity options. The first four can have shortcuts.
- Starting a new session replaces the running one. A session continues after Snaptic restarts (within the same boot) unless you turn that off in **Advanced…**, and a restart of the Mac ends every session.
- When a session ended on its own, the menu says why for 12 hours (“Ended because the battery is below 20%.”).

### Rules and conditions

**Start automatically** keeps your Mac awake while the conditions you choose are met. **Add Rule…** creates a rule; each rule has up to 8 conditions, matched when **all** or **any** apply, and each condition can be **is** or **is not**. Up to 32 rules; higher in the list wins. Each rule has its own display and activity options, a wait before starting and before ending, and “After I turn it off” (resume when the conditions are next met, or after a number of minutes).

| Condition | Applies while |
|---|---|
| **App** | An app is open, or open and in front. |
| **Display** | Any external display is connected (the built-in one is ignored), a specific display is connected, or displays are mirrored. |
| **Power** | On the power adapter, on battery, charging, or the battery is at least a level. |
| **Schedule** | Chosen weekdays between two times (overnight works). |
| **CPU use** | Total CPU is above a percentage, averaged over 10 seconds. |
| **Audio** | Sound is playing, or the microphone is in use by any app (Awake never listens). |
| **Idle time** | You haven’t used the keyboard, mouse, or trackpad for a number of minutes. |
| **Drive** | A drive is mounted. |
| **USB device** | A USB device is connected. |
| **IP address**, **Connected to this network**, **VPN** | Your Mac has an address in a subnet, is connected to a network you saved (by its router), or a VPN is connected. |
| **Network activity** | Network traffic is at least a number of KB/s. |
| **Bluetooth audio** (Beta) | A Bluetooth audio device, or a Bluetooth keyboard, mouse, or trackpad you saved, is connected. |

None of these needs a permission. **Pause Rules** (for 1 hour or until tomorrow) is in the Awake menu’s **Rules ›**, the status row, the **Pause or Resume Rules** shortcut, and `snaptic awake pause`. A session you start yourself always takes precedence over rules, and command-line holds come last.

### Guards

Guards end sessions so Awake never drains your battery or keeps a hot Mac running.

- **5% battery floor (always on, no setting, no kill switch):** below 5%, every session, hold, and Drive Alive ends whenever the battery is discharging, also on a power adapter too weak to keep up (the battery fell within the last 10 minutes).
- **When the battery is low** (laptops; default on at 20%, 5–50%): ends sessions below your level. Rules don’t start again until the battery is 5% above the level or charging.
- **When the power adapter is disconnected** (laptops; off by default).
- **When Low Power Mode turns on** (Advanced; off by default). Otherwise Awake keeps running and says so once.
- **Heat:** when your Mac gets very hot (critical thermal state), every session and hold ends, Drive Alive stops, and rules stay paused while it’s hot and for 10 minutes after it cools down. This can’t be turned off. A serious (lower) thermal state shows a one-time notice.
- **Unreadable battery:** if a laptop’s battery can’t be read twice in a row, Awake stops appearing active and keeping drives awake (it treats the battery as empty) but keeps the session, and says so.
- **Start Anyway:** when the low-battery guard or Low Power Mode refuses a session you started in Snaptic, the notice offers **Start Anyway** for that one session. It never overrides the 5% floor or heat, and never applies to the command line.
- **Advanced…** also has: end sessions when your Mac sleeps (when you choose Sleep or close the lid, not in lid-closed mode), when you switch users (immediately, after 1 hour, or never), and after the screen has been locked for 1, 4, or 12 hours; keep the display on while locked (off: the display may sleep on the lock screen while your Mac stays awake).

### Appear active and pointer movement

Some apps mark you as away when you don’t touch the Mac. Two opt-in options in **Awake › Advanced… › Activity** help with that:

- **Appear active:** while a session runs, the screen is unlocked, and you haven’t typed or clicked for 60 seconds, Awake tells macOS every 60 seconds that someone is using the Mac (`IOPMAssertionDeclareUserActivity`). No permission, no events.
- **Move the pointer slightly (Experimental, needs Accessibility):** also moves the pointer 1 point and back. Safety rules that no setting can change:
  - only for a session you started yourself in Snaptic’s menu or Settings in the running copy of Snaptic; a session started with a shortcut asks “Move the pointer to keep apps active?” first and moves nothing until you click **Allow**;
  - never for command-line sessions or holds, rules, a session started when Snaptic opens, or a session restored or resumed after a restart;
  - never while the screen is locked, in the screen saver, while another user is using the Mac, while the window switcher is open, or within 2 points of a display edge;
  - only mouse-moved events: never clicks, keys, or scrolling;
  - the menu says “Moving the pointer” while it does, and the first move shows “Awake is moving the pointer slightly.” with **Stop**.
- **Stop appearing active after** (default 1 hour, up to 8 hours): both options stop after this long, counted on Snaptic’s own clock from when they first acted and carried across back-to-back sessions, so your Mac can still lock itself when you walk away. Starting a session yourself in Snaptic starts the count again.

Accessibility is asked for only when you turn pointer movement on. To revoke it, turn Snaptic off in System Settings › Privacy & Security › Accessibility.

### Drive Alive

**Awake › Drives ›** keeps external drives from spinning down, so opening and saving files doesn’t pause. Turn on **Keep drives awake**, then each drive you want. Every 2 minutes (30 seconds to 10 minutes, “Check drives every”) Snaptic rewrites a hidden 8-byte file named `.snaptic-keepalive` at the top of each drive that’s on. Nothing else on the drive is read or changed, and turning a drive off removes the file.

- Drives stay awake only during sessions you started in Snaptic or that rules started, unless you turn on **Also when no session is running**. Command-line sessions and holds never keep drives awake.
- Only external, local, writable drives qualify: never the startup disk, disk images, network volumes, Time Machine, or read-only drives. At most 16.
- The 5% battery floor, the low-battery guard (when it’s on), a battery that can’t be read twice in a row, and the heat guard stop Drive Alive in every mode.
- macOS asks once for access to removable volumes, the first time Snaptic writes to a drive.

### History

**Awake › History ›** shows today’s and the last 7 days’ time kept awake and the past sessions, with **Start Again** for sessions you started (not for command-line, process, or automatic ones) and **Clear History…**. A session that used lid-closed mode at any point says “Lid closed” under its name. History stays on this Mac for 90 days (at most 500 sessions) and never goes into exports, logs, diagnostics, or the command line.

### In the menu bar

By default Awake’s icon appears only while your Mac is being kept awake (Show When Active), next to the Snaptic icon; change that on the [Menu Bar](#menu-bar) page, along with the icon (cup, eye, or light bulb, filled while active) and the time shown next to it. The Awake menu, Awake’s tab in the Snaptic menu, and the compact Awake section (when Awake is the only module in the Snaptic menu) have the same rows: the **Keep Awake** switch with what’s keeping your Mac awake (“Held by Terminal (2)” for command-line holds), **Turn Off Keep Awake**, the Add Time items, **Keep Display On**, **End Command-Line Holds**, **Start Session ›**, **While an App Is Running ›**, and **Rules ›**. With “Keep awake with the lid closed” turned on (on the Awake page or the Menu Bar page), they also have **Keep Awake with the Lid Closed** (see [Keeping awake with the lid closed](#keeping-awake-with-the-lid-closed)). On a laptop running on battery or without an external display, the menu reminds you that closing the lid puts your Mac to sleep, unless lid-closed mode is on.

### Keyboard shortcuts

**Awake › Keyboard Shortcuts…** has, all unbound by default: **Keep Awake** (starts your default session, or turns Keep Awake off), **Keep Display On**, **Start “…”** for the first four sessions in Sessions in the menu, and **Pause or Resume Rules** (pauses rules for 1 hour, or resumes them). Shortcuts work in any app while Awake is on.

### Other apps keeping your Mac awake

**Awake › Advanced…** lists other apps that are keeping your Mac awake right now, with what each prevents, updated every few seconds. If sleep is turned off for the whole Mac (`SleepDisabled`, left by `pmset disablesleep`, Amphetamine Power Protect, or Insomnia), it says so: “Sleep is turned off for this Mac by another app or command. Snaptic leaves it as it is.” Snaptic changes that setting only for its own lid-closed mode; if an earlier lid-closed session left it off, the page says so and offers to turn sleep back on (see [If sleep stays off](#if-sleep-stays-off)). See also [Switching from Amphetamine or Insomnia](#switching-from-amphetamine-or-insomnia).

### Keeping awake with the lid closed

A MacBook goes to sleep when you close its lid, whatever power assertion an app holds. There are two ways around that:

- **Closed-display mode** (macOS’s own, no password): connect power and an external display (and a keyboard or mouse), then close the lid.
- **Lid-closed mode** (opt-in, on Macs with a battery): keeps a MacBook awake with its lid closed, also on battery with no external display. macOS allows that only with root, so Snaptic asks for an administrator password **each time** you turn it on. Nothing is installed and nothing persistent is granted: no helper, no launch agent, no sudoers rule.

**Use it on a hard surface, not in a bag.** While lid-closed mode is on, your Mac can’t sleep for low battery or heat, so Snaptic and a watchdog it starts both watch for those (see the limits below).

#### Turning it on

1. Turn on **Awake › Lid closed › Keep awake with the lid closed** (or, on the Menu Bar page, **Show Keep Awake with the Lid Closed in the Awake menu**: the same switch). This only adds the menu item and asks for nothing. While lid-closed mode is on, both switches are locked: “Lid-closed mode is on. Turn it off first, in the Awake menu or in Options on the Awake page.”
2. In the Awake menu (or Awake’s tab in the Snaptic menu), choose **Keep Awake with the Lid Closed ›** and a session. Each one ends in “…” because it asks for your password; **Custom…** opens the session panel with “Keep awake with the lid closed” turned on, and its button reads **Start…**. The session starts only once lid-closed mode is on, so Cancel starts nothing.
3. Enter an administrator password in macOS’s dialog. It reads: “Snaptic wants to keep your Mac awake with the lid closed for up to 24 hours. Sleep turns back on when the session ends, when Snaptic quits, at 20% battery, or if your Mac gets hot. Enter an administrator password to allow this.” It names your battery limit. Touch ID may work there.

While a session you started from the menu or Settings is running, the menu shows **Keep Awake with the Lid Closed…** under Keep Display On instead, which adds lid-closed mode to that session. The Awake page’s **Keep Awake ▾** and **Options ▾** menus have the same items. While a request is under way the items read “Waiting for Password…”, “Turning On…”, or “Turning Off…”, and if turning on takes more than 2 seconds a notice says “Turning on lid-closed mode…”.

**Only you, in Snaptic, can turn it on:** a menu click, the Custom… panel, or the Awake page. Never the command line, rules, holds, keyboard shortcuts (including session shortcuts), a session started when Snaptic opens, a session restored or resumed after a restart, History’s Start Again, or an imported backup. If something other than the Snaptic menu or Settings replaces the session (a shortcut, the command line, a rule), lid-closed mode ends. Choosing another session from the Snaptic menu or Settings keeps it, within the same 24 hours.

**It won’t turn on** (a notice says why, and there is no Start Anyway):
- on battery below your battery limit plus 5% (“Lid-closed mode needs at least 25% battery, or connect power.”);
- while your Mac is hot;
- in a Start Anyway session;
- when Snaptic runs from a temporary location (“translocated”): move it to Applications first;
- while an earlier lid-closed session is still finishing, or while sleep is still turned off from one (see [If sleep stays off](#if-sleep-stays-off)).

If sleep is already turned off for this Mac by another app or command, Snaptic doesn’t touch it: your Mac already stays awake with the lid closed, and the session starts without lid-closed mode. Low Power Mode doesn’t block lid-closed mode and is a good idea with the lid closed; the session’s own “When Low Power Mode turns on” setting still applies.

**Turning it off:** choose **✓ Keep Awake with the Lid Closed**, turn Keep Awake off, let the session end, or quit Snaptic. Turning lid-closed mode off never asks for a password.

#### Limits

Lid-closed mode turns off by itself:

- **at your battery limit:** Awake’s low-battery level, but at least 10%; 20% when “When the battery is low” is off;
- **when your Mac gets hot** (a serious thermal state or worse);
- **after 24 hours**, counted from when you first turned it on. Five minutes before, a notice says “Lid-closed mode turns off in 5 minutes. If the lid is closed then, your Mac goes to sleep.” With the lid open, the session continues: “Lid-closed mode turned off after 24 hours. Awake is still on; your Mac sleeps if you close the lid.”;
- when the session ends, Awake or the feature is turned off, Safe Mode starts, or Snaptic quits, stops responding, or crashes;
- if another app turns sleep back on.

When it turns off for any of these reasons while the lid is closed, your Mac goes to sleep. If the session was still running, it ends too: “Awake ended: lid-closed mode turned off while the lid was closed.”

**The screen.** While the lid is closed and no external display is connected, Snaptic lets the built-in display sleep, even in a Keep Display On session, and runs `pmset displaysleepnow` as you to turn it off. With an external display connected, your Keep Display On choice stands.

#### What you see

- Awake’s icon uses a lid-closed look while the mode is on, and its tooltip and VoiceOver label add “even with the lid closed”. VoiceOver says “Keeping your Mac awake with the lid closed.” when it turns on and “Lid-closed mode turned off.” when it ends.
- The menu and the Awake page say “Stays awake with the lid closed”, or “Stays awake with the lid closed until 6:40 PM” when the 24-hour limit comes first.
- After it ends, for 12 hours: “Lid-closed mode ended at 3:12 AM: battery at 20%.” (or “your Mac got hot”, “time limit reached”, “another app turned sleep back on”, “Snaptic quit”, “it stopped unexpectedly”).
- History marks the session “Lid closed”, and `snaptic awake status --json` has `"lidClosed": true`.
- An update never relaunches Snaptic while lid-closed mode is on (see [Updates](#updates)).
- `Awake.disable.lidClosed` turns the feature off for this Mac (see [Hidden kill switches](#hidden-kill-switches)).

Known limits: another app’s display assertion (for example `caffeinate -d`, listed in Other apps keeping your Mac awake) can keep the built-in display lit, and the keyboard backlight may stay on, because there’s no public way to turn it off.

#### If sleep stays off

`SleepDisabled` survives a restart. If your Mac loses power or restarts while lid-closed mode is on, or turning sleep back on fails, sleep stays off until you decide. At the next launch, even with Awake turned off or in Safe Mode, Snaptic shows:

- **in every Snaptic menu**, above everything else (and above the tabs): “Sleep Is Turned Off” and **Turn Sleep Back On…**;
- **on the Awake page and in Awake › Advanced… › Other apps keeping your Mac awake:** “Your Mac can’t sleep. This may be from an earlier lid-closed session that didn’t finish.” with **Turn Sleep Back On…**, **Keep Sleep Off**, and **Not Now**;
- a notice with **Turn Sleep Back On…** and **Open Awake Settings…** when Awake isn’t running.

**Turn Sleep Back On…** asks for an administrator password (“Snaptic wants to turn sleep back on. It may have been left off by an earlier lid-closed session. Enter an administrator password to allow this.”) and runs only `pmset -a disablesleep 0`. **Keep Sleep Off** leaves it off without a password and removes the rows (Other apps then says sleep is turned off by another app or command); it’s only in Settings, because undoing it needs Terminal. **Not Now** hides the rows until Snaptic next starts. Snaptic never changes `SleepDisabled` when it didn’t set it itself: a value another app left is reported, never changed. You can always check and fix it yourself:

```bash
pmset -g | grep SleepDisabled      # 1 means sleep is turned off for the whole Mac
sudo pmset -a disablesleep 0       # turn system sleep back on
```

#### Your password and what runs as root

- **What runs as root.** Only while lid-closed mode is on, or when you choose Turn Sleep Back On…, Snaptic runs a short shell script as root. Its full text is in [`Sources/SnapticKit/LidWatchdog.swift`](../Sources/SnapticKit/LidWatchdog.swift). It changes only `SleepDisabled` (`pmset -a disablesleep 1`, then `0`), and may run `pmset sleepnow` when sleep is back on, the lid is closed, and your Mac isn’t shutting down. It turns sleep back on when the session ends, when Snaptic quits or stops responding (it checks every 5 seconds), when the battery reaches the limit, when your Mac gets hot, after 24 hours, or if the script itself fails. It never writes, deletes, or reads the contents of your files; it only checks a few small files Snaptic keeps in your temporary folder (a heartbeat, a stop file, and, when your Mac is shutting down or logging out, a halt file).
- **How it starts.** `/usr/bin/osascript` asks macOS for an administrator password, then starts the script, which keeps running as a watchdog after the dialog closes. It gets a minimal environment and calls every program by its full path.
- **The dialog names osascript, not Snaptic.** Any app can show this dialog with any text. Only enter your password right after you choose **Keep Awake with the Lid Closed**, **Turn Sleep Back On…**, or **Install and Relaunch** (in Snaptic’s About page or in Sparkle’s update window).
- **If your account can change Snaptic** (the default after you drag it to Applications), that advice isn’t enough: a program running as you could change Snaptic so that its own prompt runs something else as root. Snaptic says so under the setting. To close that gap, install Snaptic owned by root: build with `INSTALL=1`, or for a downloaded copy run `sudo chown -R root:wheel /Applications/Snaptic.app`. (Each update then asks for an administrator password; see [Updates](#updates).) Snaptic warns rather than refuses, because the same program could show the identical dialog without touching Snaptic, and refusing would remove the feature from the default install. A translocated copy is refused.
- **What a program running as you can do:** turn sleep back on (by creating the watchdog’s stop file or deleting its heartbeat file), stop it from putting your Mac to sleep when lid-closed mode ends with the lid closed (by creating its halt file), or, while Snaptic is hung, keep lid-closed mode going, but only while Snaptic’s process is still running and only until the 24-hour limit, the battery limit, or heat ends it, which the watchdog enforces on its own. It can’t turn lid-closed mode on without you typing a password into a dialog.
- **Power loss or a restart while it’s on:** sleep stays off until you choose Turn Sleep Back On… or Keep Sleep Off (see [If sleep stays off](#if-sleep-stays-off)).
- **Security software** may flag “osascript with administrator privileges”. Release builds are signed with a Developer ID, which removes one of the conditions such rules look for.

### Switching from Amphetamine or Insomnia

| Amphetamine or Insomnia | Snaptic Awake |
|---|---|
| Indefinite, duration, until a time, extend | Sessions: Until Turned Off, For a while, Until a time, Add Time |
| While an app is running, while downloading | While an app is running; Until Downloads and Tasks Finish |
| Allow display sleep | Keep the display on, per session and mid-session |
| Triggers and their criteria | Rules and conditions (no Wi-Fi network name or DNS server; use **Connected to this network**, IP address, or VPN) |
| Move cursor periodically | Appear active, plus pointer movement (Experimental) |
| Battery, adapter, and heat endings | Guards |
| Drive Alive | Drive Alive |
| Statistics | History |
| AppleScript | The `snaptic awake` command |
| Closed-display mode on battery | Lid-closed mode, with an administrator password each time; see [Keeping awake with the lid closed](#keeping-awake-with-the-lid-closed) |
| Power Protect (a sudoers rule, no password) | Not offered: Snaptic installs no sudoers rule and keeps no lasting permission |

Quit the other app and remove it from Login Items first, so two apps don’t keep your Mac awake. Their closed-lid features can leave two things behind: a **sudoers rule** that lets programs run `pmset` without a password, and the system-wide **`SleepDisabled`** setting. Snaptic never touches another app’s sudoers rule, and never changes a `SleepDisabled` it didn’t set itself in lid-closed mode. The commands below are for you to run in Terminal; Snaptic never runs them for you. Prefer the other app’s own uninstaller first (Amphetamine: Feedback & Support › Uninstall Scripts…).

```bash
# Inspect (no changes)
pmset -g | grep -i -E 'SleepDisabled|lowpowermode'   # SleepDisabled 1 means sleep is turned off for the whole Mac
ls -l /etc/sudoers.d/                                 # look for amphetamine_powerProtect or insomnia
sudo cat /etc/sudoers.d/amphetamine_powerProtect      # read a rule before removing it
ls ~/Library/LaunchAgents | grep -i -E 'amphetamine|insomnia'

# Revert (you run these; each asks for your password)
sudo pmset -a disablesleep 0                          # turn system sleep back on
sudo rm /etc/sudoers.d/amphetamine_powerProtect       # Amphetamine Power Protect's rule
sudo rm /etc/sudoers.d/insomnia                       # Insomnia's rule
sudo visudo -c                                        # check the remaining sudoers files are valid
rm -f ~/Library/Application\ Scripts/com.if.Amphetamine/powerProtect.scpt
```

Insomnia can also turn Low Power Mode on while it runs; if `lowpowermode 1` shows and you don’t want it, turn it off in System Settings › Battery. Remove any leftover launch agent the listing shows the same way you’d remove any other: unload it with `launchctl bootout gui/$(id -u) <path>`, then delete the file.

## Hidden Icons

Hidden Icons keeps your menu bar tidy: click the arrow ‹ to hide the icons to its left, and click again to show them. It is off until you turn it on with **Use Hidden Icons** at the top of its page (or in General, or the “New: Hidden Icons” card). Turning it on opens **How to Arrange Your Icons**, and nothing hides until you click the arrow for the first time.

It works differently on the two halves of Snaptic’s supported range:

- **macOS 27 and later:** Snaptic asks macOS itself to hide other apps’ icons, with the mechanism macOS uses for exam sessions (see [Undocumented APIs](#undocumented-apis)). It needs **Device Control and Data Access** (Accessibility), to see where your icons are and so hide the right ones. The arrow marks the edge of the hidden icons, and you can choose **Always Show** or **Always Hide** for an app.
- **macOS 14–26:** a | divider sits left of the arrow. To hide, Snaptic makes the divider very wide, so the icons to its left move off the screen; to show them, it makes it narrow again. Hiding needs no permission. Accessibility is asked for only when you open the hidden-icon list or Sections.

### Arranging your icons

Snaptic never moves another app’s icon: you arrange them yourself by holding ⌘ and dragging them in the menu bar. **How to Arrange…** on the page (also an onboarding step) shows this for your macOS:

```
macOS 14–26                                      macOS 27
  ⋮  [A] [B]  |  [C] [D]  ‹  [E] [S]  ◷ 9:41       ⋮  [A] [B]  [C] [D]  ‹  [E] [S]  ◷ 9:41
  └always┘   └─hidden─┘     └shown─┘               └always┘   └hidden─┘     └shown─┘
```

Hold ⌘ and drag icons in the menu bar:

- To the right of the arrow ‹: always shown.
- Between | and ‹ (macOS 14–26), or to the left of the arrow ‹ (macOS 27): hidden when you click the arrow.
- Left of ⋮: hidden until you Option-click the arrow (only while **Always Hidden section** is on).

On macOS 14–26, new apps’ icons appear at the far left, so they start hidden. On macOS 27, a new app’s icon stays shown until you next show all icons or choose where it goes (**New apps’ icons** in **Advanced…**), and you can also choose Always Show or Always Hide for an app in Settings › Hidden Icons › Sections. The dividers say what they are to VoiceOver (“Hidden Icons divider”, “Always Hidden divider”).

The first time you hide icons on macOS 27 with no other app’s icon to the right of the arrow, Snaptic asks “Hide all other apps’ icons?” (Cancel is the default).

### Showing and hiding

- **The arrow:** click to show or hide icons; Option-click to include Always Hidden. Right-click it for the same menu as the Snaptic menu’s Hidden Icons section.
- **The Snaptic menu** (with **Arrow and Snaptic Menu**, the default): **Show Hidden Icons** or **Hide Icons Again**, **Show All Hidden Icons** (Option, or a plain item under VoiceOver, Switch Control, and Full Keyboard Access), **Hide Icons Automatically**, the list of hidden icons, and **Hidden Icons Settings…**. Choose a hidden icon to open its menu without showing them all. On notched Macs with macOS 14–26, icons pushed behind the notch are listed too. With nothing hidden it says **No Hidden Icons**. On macOS 14–26 the list needs Accessibility (**Allow Accessibility to List Icons…**).
- **Hide icons automatically after 10 seconds** (5–300; on by default). It waits while the pointer is over the menu bar, a menu is open, or a Snaptic window is open.
- **Hide icons when Snaptic opens** (on by default): “Reopening Snaptic to show Settings doesn’t hide them.”
- **Shortcut:** **Show or Hide Hidden Icons**, unset by default.
- **Command line:** `snaptic icons show`, `hide`, `toggle`, and `status` (see [Hidden Icons commands](#hidden-icons-commands)).

### The Hidden Icons page

- **Status:** “Hiding 7 icons” or “Showing all icons” (“Icons are hidden” on macOS 14–26 without Accessibility), with **Show Icons** or **Hide Icons**. Before your first hide it says “Arrange your icons, then click the arrow to hide them.” with **How to Arrange…**. When something stops hiding, the row says why and offers the fix (see [When icons stay shown](#when-icons-stay-shown)).
- **Hide icons automatically after … seconds**, **Hide icons when Snaptic opens**, **Always Hidden section** (“Icons left of the ⋮ divider stay hidden until you Option-click the arrow.”), **Section dividers** (shows the dividers while icons are shown), and the **Show or hide icons** shortcut.
- **Sections ›** lists which apps’ icons are shown, hidden, and always hidden (“7 hidden · 2 choices”), as of the last time your icons were shown. On macOS 27 each app has **Where It Is**, **Always Show**, or **Always Hide**: “Always Show and Always Hide apply to all of an app’s icons and win over where you drag them.” macOS’s own icons and privacy indicators can’t take a choice, and icons that macOS hides in System Settings › Menu Bar aren’t listed.
- **How to Arrange…**, **Advanced…**, and **Restore Defaults…**.
- **Advanced…:** **Show icons on hover** (“Shows hidden icons when the pointer rests on the menu bar.”), **New apps’ icons** (macOS 27: **Show** or **Hide**), **When another menu bar app hides icons** (see below), **Keep camera and microphone dots visible** (macOS 27, on by default: “Shows your icons while an app uses the camera or microphone, so its dot stays visible, then hides them again.”), **Use the full menu bar while icons are shown** (“Snaptic becomes the active app while icons are shown, so the current app loses focus.” Snaptic also appears in the Dock and the app switcher until the icons are hidden), **Reset Arrow Position…** (puts the arrow and dividers back next to the Snaptic icon if you can’t find them), and **Diagnostics** (the method in use, the last time icons were shown to stay safe, and the kill switches).
- **Restore Defaults…:** automatic hiding, Always Hidden, dividers, the shortcut, hover, new apps’ icons, the full menu bar, and every app’s Always Show or Always Hide choice go back to their defaults. Where your icons are in the menu bar stays as it is. **Reset All Settings…** also puts the arrow and dividers back next to the Snaptic icon, so you’ll arrange your icons again.

### When icons stay shown

Hidden Icons fails safe: whenever Snaptic can’t be sure hiding is safe, your icons are shown. Nothing it does can leave an icon hidden after Snaptic is gone.

- **Snaptic quits, crashes, or is force quit:** every icon comes back within about 2 seconds, because macOS ties the hiding to Snaptic’s process (macOS 27) or the wide divider is Snaptic’s own item (macOS 14–26).
- **Snaptic stops responding:** on macOS 27 a watchdog shows your icons after 3 seconds. If Snaptic stops responding while icons are hidden on macOS 14–26, force quit it (⌥⌘⎋). The icons come back as soon as it quits.
- **The arrow or a divider is missing**, for example after macOS hid it in System Settings › Menu Bar: “The arrow isn’t in the menu bar, so icons stay shown.”, with **Show Arrow** (or **Show Divider**). The page’s button, the Snaptic menu, the shortcut, `snaptic icons show`, and opening Snaptic again still show icons.
- **The arrangement doesn’t work** (for example the | divider is right of the arrow): the row says which item to ⌘-drag where. On macOS 14–26, if the arrow is left of |, icons stay shown (“The arrow is in the hidden area. ⌘-drag it to the right of the | divider.”). If Awake’s icon is in the hidden area, icons stay shown while Awake keeps your Mac awake. Other Snaptic icons there get a warning (“Some Snaptic icons are in the hidden area. ⌘-drag them to the right of the arrow.”), and a new Snaptic icon that appears while icons are hidden makes them show.
- **Sleep, wake, locking, switching users, displays changing, or macOS restarting its menu bar:** icons are shown, then hidden again a moment later if you had hidden them.
- **An exam session** (Safari’s or an app’s assessment mode): “Paused during an exam session”. Snaptic never adds to what an exam shows or hides.
- **A problem with the macOS 27 method:** if hiding ever crashed Snaptic, or a macOS icon (other than Now Playing) disappeared, Snaptic stops using the method on that macOS version: “Hidden Icons stopped using the macOS 27 method after a problem, so your icons stay shown.” with **Try Again**.
- **Snaptic couldn’t confirm a hide:** the icons are shown, the page says “Icons were shown at 9:41 because Snaptic couldn’t confirm they were hidden safely.”, and the first time per launch a notice says “Snaptic couldn’t hide icons, so they’re shown. Details are in Hidden Icons settings.”
- **Not from Applications:** “Move Snaptic to Applications to hide icons.”
- **Safe Mode:** Hidden Icons doesn’t start, so your icons are shown.

**Camera and microphone dots.** On macOS 14–26 the privacy indicators sit at the far right and are never hidden. On macOS 27, hiding icons also hides the camera and microphone dots, so while an app uses the camera or microphone Hidden Icons shows your icons (the page says “Paused while the camera or microphone is on”) and hides them again about 2 seconds after it stops. Snaptic only asks macOS whether a camera or microphone is running; it never opens one, so nothing prompts and nothing is recorded. Turn off **Keep camera and microphone dots visible** in **Advanced…** to keep icons hidden during calls; the dots are then hidden with them. On macOS 27.2 the screen recording indicator stayed visible with its app hidden; the location indicator is listed under [Needs testing on hardware](#needs-testing-on-hardware).

### Other menu bar hiders

While Hidden Bar, Bartender, Ice, or Thaw runs, Hidden Icons shows your icons and pauses (“Paused while Hidden Bar runs”), and resumes when the other app quits. **Advanced… › When another menu bar app hides icons** can instead **Run Both Anyway**. On macOS 27, an icon stays shown unless both apps hide it.

### Switching from Hidden Bar

Quit Hidden Bar and remove it from Login Items (System Settings › General › Login Items), so the two don’t take turns. Icon positions don’t carry over: turn on Hidden Icons and ⌘-drag its arrow once to where Hidden Bar’s was.

| Hidden Bar | Snaptic Hidden Icons |
|---|---|
| Start Hidden Bar when I log in | General › Open at login |
| Show preferences on launch | Opening Snaptic again always shows Settings |
| Automatically hide icon after | Hide icons automatically after … seconds |
| Enable always hidden section | Always Hidden section |
| Use the full MenuBar on expanding | Advanced… › Use the full menu bar while icons are shown |
| Global Shortcut | Show or Hide Hidden Icons (Settings › Hidden Icons) |
| ⌥-click to hide the separators | Section dividers (⌥-click now shows Always Hidden) |
| Right-click ‹ for Notch Overflow | The Snaptic menu’s Hidden Icons section, or right-click the arrow |
| `defaults write … hoverToExpand` | Advanced… › Show icons on hover |

## Dock Previews

Point at an app in the Dock, and its windows appear next to the Dock, including minimized and hidden ones. Click a window to bring it forward. Dock Previews is off until you turn it on with **Use Dock Previews** at the top of its page (or in General, or the “New: Dock Previews” card). It works with the Dock at the bottom, left, or right, magnified or hidden automatically, on any display.

**Permissions.** Dock Previews needs **Accessibility** (**Device Control and Data Access** on macOS 27) to read the Dock. Turning it on without it opens the permission window once (“Dock Previews needs it to read the Dock.”); until you allow it, the page says “Dock Previews needs Accessibility to read the Dock.”, with **Open Privacy Settings…**. **Window thumbnails** also need **Screen Recording**, which Snaptic asks for only in onboarding or on the Permissions page, never when you point at the Dock. Until you allow it, previews show window titles, and the page says “Window thumbnails need Screen Recording. Until then, previews show window titles.”, with **Open Privacy Settings…**. With **Window thumbnails** off, previews show titles only and Screen Recording isn’t needed.

### Showing and hiding previews

- **Showing:** point at a running app in the Dock. **Show previews after** (“How long you point at an app before its windows appear.”) is 0.2 seconds by default, from “Immediately” to 1 second. Moving to another app swaps the preview at once, unless the pointer is on its way into the preview.
- **Nothing shows** for a folder, the Trash, a stack, a separator, a minimized window’s own Dock tile, an app that isn’t running, or an app on **Advanced… › Apps hidden from Dock previews**. An app with no open windows shows a small card instead (see [Cards and actions](#cards-and-actions)). Moving the pointer away from the Dock, or pressing the mouse button on the Dock, before the preview appears cancels it.
- **Hiding:** the preview stays while the pointer moves from the icon into it, and hides a quarter second after the pointer leaves the icon and the preview; once the pointer is outside the Dock and the preview, it always hides within a second. A click outside the preview or on the app’s Dock icon, the Dock’s own menu opening, or starting a drag hides it too, and so do switching apps, changing Spaces or displays, locking the screen, sleep, switching users, and the app quitting. Previews never show while the Window Switcher is open.
- **After a preview is dismissed** by a click, Esc, Hide, or Quit, the same app’s preview doesn’t show again until you point at another item or move the pointer away from the Dock and back. After **Hide** or **Quit**, the next preview waits until the pointer moves a little, and the header ignores clicks for 0.3 seconds after a preview shows or swaps, so a double click can’t land on the next app’s **Quit**.
- **Menus:** while a card’s or the header’s menu is open, the preview stays.
- **Placement:** the preview appears 6 points from the Dock and doesn’t follow the Dock’s magnification. It fades in and out in 0.15 seconds and never slides. With Increase Contrast, cards and the preview get 1-point borders and the header a separator line; with Reduce Transparency, the preview is opaque.
- **A Dock that hides automatically:** Snaptic never keeps it shown. If the Dock hides while the pointer is in the preview, the preview stays until you dismiss it; otherwise it hides with the Dock.
- **Command line:** `snaptic dock pause` and `snaptic dock resume` (see [Dock Previews commands](#dock-previews-commands)).

### Cards and actions

- **Cards:** one per window, with its thumbnail and title. **Card size** is **Small**, **Medium** (default), or **Large**: 200, 280, or 360 points wide, with each thumbnail letterboxed in a fixed 16:10 frame. Cards sit in one row for a Dock at the bottom and in two columns for a Dock at the left or right. With more windows than fit, cards get smaller (down to Small), then the preview scrolls. If an app is slow to list its windows, the preview shows the ones it has and a “More windows…” row that lists the rest.
- **Badges:** “Minimized”, “Full screen”, “On another Space”, or, with more than one display, the name of the window’s display, at most one per card, in that order. A hidden app says “Hidden” once, in the preview’s header.
- **What’s listed:** standard windows and titled dialogs. Floating panels, system dialogs, notification-style pop-ups, windows smaller than 100 × 100 points, and Finder’s desktop are left out. **Include minimized and hidden windows** (“Lists windows that are minimized or belong to hidden apps.”) and **Windows on other Spaces** (“Off: only windows on the current Space are shown.”) are both on by default. **Advanced… › Sort windows by** offers **Recently Used** (default), **Minimized and Hidden Last**, and **Title**.
- **Small cards:** an app with no open windows shows “No open windows”; click it to switch to the app. When your settings leave out all of an app’s windows, it shows “No windows shown”, with the tooltip “Its windows are minimized, hidden, or on other Spaces.” Turn off **Advanced… › Apps with no open windows** (“Pointing at the app shows a small card instead of nothing.”) to show nothing for these apps. If an app doesn’t answer in time and Screen Recording is off, the preview says “Windows can’t be read right now”, and Snaptic tries that app again 30 seconds later.
- **Click** a card to bring its window forward, whether it’s minimized, hidden, full screen, or on another Space. **Middle-click** closes it. Hovering a card shows **Close**, **Minimize**, and **Enter Full Screen** buttons at its top left (“Close (⌘W)”, “Minimize (⌘M)”).
- **The card’s menu** (right-click): **Close Window**, **Minimize Window** (or **Restore Window**), **Enter Full Screen** (or **Exit Full Screen**), **Hide Safari** (or **Show Safari**), and **Quit Safari** (never for Finder), named for the app.
- **The header** shows the app’s icon and name, its window count (“1 window”, “3 windows”), and **Minimize All**, **Hide** (**Show Safari** while the app is hidden), and **Quit** (never for Finder). The header’s menu adds **Close All**.
- **Quit** asks the app to quit, like ⌘Q, and never force quits it.
- **After an action:** bringing a window forward, Hide, and Quit hide the preview; Close and Minimize update it in place.
- **Cards that offer only Bring Forward:** when Snaptic can’t match a card to its window through Accessibility (for example some windows on other Spaces), the card offers only **Bring Forward**. An untitled one reads “Window on another Space”.
- **Thumbnails** of windows on screen come from ScreenCaptureKit. For minimized windows and windows on other Spaces, Snaptic uses a private macOS capture, only on macOS versions it has been checked on; otherwise the card shows the last thumbnail Snaptic saw, then the app icon. Thumbnails are taken only for the cards in view, once the preview has been up for 0.15 seconds, at most 8 a second, and for each window at most once every 30 seconds unless it changed. In Stage Manager, a window in the side strip gets a picture of the window itself, never of its strip tile. The page notes: “macOS may show its screen-recording indicator or a reminder while thumbnails are taken.”

### Keys in previews

A preview is in use once you’ve moved the pointer at least 4 points inside it within the last 1.5 seconds and kept it there for a quarter second, or clicked in it. A 2-point ring in your accent color shows the card under the pointer, and these keys work on it:

- **⌘W** closes the window, **⌘M** minimizes it (or restores it), and **⌘H** hides its app (or shows it).
- **⌘Q** quits what’s under the pointer. It never quits Finder.
- **Esc** dismisses the preview.

While a preview is in use, these five keys always go to the preview, even with nothing under the pointer, so they never reach the app you’re in. Holding a key acts once, and the keys do nothing for 0.3 seconds after a close or minimize, while the cards move. Every other key, arrows, Return, and letters included, goes to the app you’re in. The keys are off while secure input is on (for example in a password field).

- **Advanced… › Keyboard shortcuts in previews** (on by default): “Press ⌘W to close, ⌘M to minimize, ⌘H to hide, or ⌘Q to quit what’s under the pointer. Esc dismisses the preview.”
- If macOS turns the keys off 3 times within a minute, they stop until you relaunch Snaptic: “Keyboard shortcuts in previews stopped because macOS turned them off 3 times. Relaunch Snaptic to use them again.”, with **Relaunch Snaptic**.
- Snaptic watches the keyboard only while a preview is in use.

### Dock click actions

Two optional actions on the Dock Previews page, both off by default:

- **When you click the active app in the Dock:** **Do Nothing** (default), **Hide the App**, or **Minimize Its Windows**. “Hide works like pressing ⌘H. Minimize sends each of its windows to the Dock.”
- **Restore all minimized windows:** “When all of an app’s windows are minimized, clicking its Dock icon brings them all back.” When every window of the app is minimized, this wins over Hide and Minimize.
- **When a click counts:** the app was already active before you pressed the button (for at least 0.15 seconds), and you release the button on the same icon within half a second. Hide and Minimize also need one of the app’s windows visible on the current Space. The action runs 0.1 seconds after you release the button, and Hide is skipped if the click opened a new window. If another app becomes active in the meantime, the click does nothing.
- **The Dock stays in charge:** “Snaptic only watches Dock clicks. The Dock still handles every click as usual.” Snaptic never changes the Dock’s preferences, and watches Dock clicks only while one of these actions is on.
- If macOS turns off Snaptic’s watching 3 times within a minute, the actions stop until you relaunch Snaptic: “Dock click actions stopped because macOS turned them off 3 times. Relaunch Snaptic to use them again.”, with **Relaunch Snaptic**.
- The actions keep working while previews are paused for VoiceOver. Any other pause stops them too.

### The Dock Previews page

- **Status:** shown only when something needs attention (see [When previews pause](#when-previews-pause)), and “Starting…” while Snaptic first reads the Dock.
- **Previews:** **Show previews after**, **Card size**, **Window thumbnails** (“Pictures of your windows. Off: titles only, and no Screen Recording needed.”), **Include minimized and hidden windows**, and **Windows on other Spaces**.
- **Dock click actions:** the two settings above, with the footer “Snaptic only watches Dock clicks. The Dock still handles every click as usual.”
- **Restore Defaults…** and **Advanced…** (both while Dock Previews is on), and (?).
- **Advanced…** (“Dock Previews Advanced Settings”): **Sort windows by**, **Keyboard shortcuts in previews**, **Apps with no open windows**, **When another app shows Dock previews** (see [Other Dock preview apps](#other-dock-preview-apps)), **Show previews while VoiceOver is on**, the **Privacy** section it shares with the Window Switcher (see [Private windows](#private-windows)), **Apps hidden from Dock previews**, and **Diagnostics** when a Dock or window kill switch is set (see [Hidden kill switches](#hidden-kill-switches)).
- **Restore Defaults…** on the page asks “Restore Dock Previews settings to their defaults?”: “Preview, Dock click, and Advanced settings go back to their defaults. Dock Previews stays on. Protect private windows and its app list stay as they are, because the Window Switcher uses them too.” The Advanced sheet’s own asks “Restore Dock Previews’ Advanced settings to their defaults?”: “Advanced settings go back to their defaults. Protect private windows and its app list stay as they are, because the Window Switcher uses them too.”
- **The Snaptic menu:** Dock Previews’ section (the Dock tab) shows its status when it isn’t working, “Open Accessibility Settings…” while it needs permission, **Pause Dock Previews for 1 Hour** (or **Resume Dock Previews**), and **Dock Previews Settings…**. It’s in the Snaptic menu by default (see [Menu Bar](#menu-bar)).

### When previews pause

The page’s status row and the Snaptic menu say why previews don’t show:

- **Safe Mode:** “Paused in Safe Mode” (see [Safety](#safety)).
- **No Accessibility:** “Dock Previews needs Accessibility to read the Dock.”, with **Open Privacy Settings…**; the menu says “Needs Permission”.
- **The Dock can’t be read:** “Dock Previews can’t read the Dock. It tries again when the Dock restarts.”, with **Try Again**; the menu says “Can’t read the Dock”.
- **Another Dock preview app:** “Paused while DockDoor runs”, with **Advanced…** (see [Other Dock preview apps](#other-dock-preview-apps)).
- **VoiceOver:** “Paused while VoiceOver is on”, with **Advanced…**, or, while a Dock click action is on, “Previews are paused while VoiceOver is on. Dock click actions still work.” (see [VoiceOver and the keyboard](#voiceover-and-the-keyboard)).
- **Paused by you:** “Paused until …”, with **Resume**, after **Pause Dock Previews for 1 Hour** in the menu or `snaptic dock pause`. A pause isn’t kept when Snaptic quits.

Below the status row, the page can also show that Window thumbnails need Screen Recording (see above), that Dock click actions or keyboard shortcuts stopped (see [Dock click actions](#dock-click-actions) and [Keys in previews](#keys-in-previews)), or that a window feature stopped (see [When a window feature stops](#when-a-window-feature-stops)). Dock Previews’ tab in the Snaptic menu is marked while it needs Accessibility, after it couldn’t read the Dock for 2 minutes, or after macOS turned off its Dock click actions or keyboard shortcuts.

### Other Dock preview apps

While DockDoor, HyperDock, or another Dock preview app runs, Dock Previews pauses (“Paused while DockDoor runs”), so the two don’t show previews on top of each other. The pause covers previews, their keys, and Dock click actions. **Advanced… › When another app shows Dock previews** is **Pause Dock Previews** by default, or **Run Both Anyway**: “Both apps show a preview when you point at the Dock, and the previews may cover each other.”

### VoiceOver and the keyboard

- **VoiceOver:** while it’s on, previews are paused by default; Dock click actions keep working. **Advanced… › Show previews while VoiceOver is on** (off by default): “Previews appear as VoiceOver moves through the Dock.”
- **What VoiceOver says:** a preview is announced with the app and its window count (“Safari, 3 windows”), and its cards are one group (“Safari windows”). Each card reads its title, then its app, and its state, such as minimized. A private card reads “Private window, Safari”, never its title.
- **The keyboard alone:** moving through the Dock with ⌃F3 or Full Keyboard Access never shows a preview, unless VoiceOver and **Show previews while VoiceOver is on** are both on. Use the Window Switcher instead.

### Switching from DockDoor

This table compares how DockDoor and Dock Previews behave, with DockDoor at its default settings. While DockDoor runs, Dock Previews pauses (see [Other Dock preview apps](#other-dock-preview-apps)).

| DockDoor | Snaptic Dock Previews |
|---|---|
| A short hover delay you can change | **Show previews after**: 0.2 seconds by default, from “Immediately” to 1 second |
| Moving to another app’s icon swaps the preview after a delay | Swaps at once, unless the pointer is on its way into the preview |
| Cards 300 × 187.5, with dynamic sizing off | **Card size**: **Small**, **Medium** (default, 280 points wide), or **Large**, letterboxed in a fixed 16:10 frame |
| One row for a Dock at the bottom, two columns for a Dock at the side | The same; with many windows, cards get smaller (down to Small), then the preview scrolls |
| A 0.4-second fade | A 0.15-second fade; nothing slides |
| An app with no open windows shows nothing | A small “No open windows” card that switches to the app (**Advanced… › Apps with no open windows**, on by default) |
| Restoring all minimized windows on a Dock click is on | **Restore all minimized windows**: off by default |
| Hiding the app on a Dock click is off | **When you click the active app in the Dock**: **Do Nothing** (default), **Hide the App**, or **Minimize Its Windows** |
| Middle-click closes a window, and can be changed | Middle-click always closes a window |
| ⌘W, ⌘M, and ⌘Q while the pointer is over a preview | ⌘W, ⌘M, ⌘H, ⌘Q, and Esc once you’ve moved the pointer in the preview or clicked in it (see [Keys in previews](#keys-in-previews)) |
| Traffic-light buttons on each card | **Close**, **Minimize**, and **Enter Full Screen** buttons at the top left of each card |
| A right-click menu with window snapping and bringing a window to this Space | Close, Minimize, Full Screen, Hide, and Quit; no snapping or moving windows between Spaces |
| Card swipe gestures (on) | No gestures |
| ⌘-right-click on a Dock icon quits the app (on) | Not included; use **Quit** or ⌘Q in the preview |
| Shift-click on a Dock icon opens a new window | Not included |
| Takes over Dock clicks and scrolls | Snaptic only watches Dock clicks; the Dock handles every click as usual |
| “Prevent dock hide” (on) | Nothing keeps a Dock that hides automatically shown; with the pointer in the preview, the preview stays until you dismiss it |
| Watches the keyboard all the time | Only while a preview is in use |
| Folder previews (off) | Not included |
| Window previews in the macOS ⌘⇥ switcher (off) | Not included; the Window Switcher can take over ⌘⇥ |
| Media and Calendar widgets | Not included |
| A text-only mode without Screen Recording | The same, and Snaptic never asks for Screen Recording when you point at the Dock |

**Done differently on purpose.** Snaptic never posts clicks or key presses of its own, never takes over the Dock’s clicks, and watches the keyboard only while a preview is in use. Private windows show their app icon (see [Private windows](#private-windows)). If a private macOS function misbehaves, Snaptic stops using it and falls back (see [When a window feature stops](#when-a-window-feature-stops)). Without Screen Recording, it never takes a picture of a window.

Quit DockDoor and remove it from Login Items (System Settings › General › Login Items), then turn on Dock Previews. Snaptic doesn’t import DockDoor’s settings.

## Safety

Display changes can leave you without a usable screen. Snaptic is built so that never sticks.

- **“Keep this change?”** Risky changes (new resolutions, mirroring, disconnecting, rotation, HDR, first-time Smart HiDPI) show a panel on every visible display with a countdown, 15 seconds by default (10–60 in Displays › Advanced… › Confirm display changes). Return or ⌘K keeps; Esc, Revert, or no answer puts things back. Keys work after one second, so a stray keypress can’t confirm. Dimmed displays are raised to at least 30% while the panel shows.
- **A separate safety helper.** Before a risky change, Snaptic arms a small helper process. If Snaptic hangs, crashes, or is killed, the helper reverts the change on its own, re-enables displays Snaptic turned off, and restores color. If the helper isn’t running, risky changes are refused; anything already applied is badged “Unprotected — restart Snaptic”.
- **Never the last screen.** Changes that would leave no visible display are refused. Dimming to black, disconnecting, and mirroring always keep at least one display you can see.
- **Restore All Displays: ⌃⌥⌘⎋** (⌃⌥⌘⇧⎋ if the first is taken; also in Display Tools and as `snaptic panic`). It undoes resolution changes from the last minute, reconnects displays Snaptic turned off, removes dimming and overlays, resets color tables, stops virtual displays and streams, and pauses automation (layouts, protection, hooks, re-creation) until you choose Resume. Rotation and HDR aren’t touched; they always go through the confirm panel. The shortcut can’t be turned off while a display is disconnected, mirrored to a virtual display, or dimmed to black. Awake isn’t affected: keeping your Mac awake isn’t a display hazard.
- **Safe Mode: hold ⇧ while Snaptic starts** (or start it with `--safe-mode`, or choose General › Advanced… › Restart in Safe Mode…). It also starts automatically after two launches in a row that ended within a minute. Safe Mode skips brightness and color restore, virtual displays and Smart HiDPI, protection, layouts, remembered resolutions, hooks, automatic DDC writes, XDR, and reconnection planning. In Awake it pauses rules, appear active, pointer movement, and Drive Alive; sessions you start, holds, and guards still work. Hidden Icons doesn’t start in Safe Mode, so your icons are shown. Dock Previews starts paused (“Paused in Safe Mode”), and the Window Switcher’s minimized windows and windows on other Spaces show their last thumbnail or the app icon. It still undoes unfinished display changes from the last run, and the switcher and your shortcuts keep working. **Leave Safe Mode…** relaunches normally.
- **Journals.** Before a risky change Snaptic writes what it would take to undo it. If the Mac or Snaptic goes down mid-change, the next launch puts things back (and says so).
- **Awake can’t drain your battery or cook your Mac:** the 5% floor and the heat guard have no setting and no kill switch (see [Guards](#guards)). Lid-closed mode adds its own battery limit (at least 10%), heat cutoff, and 24-hour limit, enforced both by Snaptic and by its root watchdog, and turns sleep back on if Snaptic stops responding (see [Keeping awake with the lid closed](#keeping-awake-with-the-lid-closed)).
- **Hidden Icons fails safe:** whenever Snaptic can’t be sure hiding is safe, or it quits, crashes, or is force quit, your menu bar icons are shown (see [When icons stay shown](#when-icons-stay-shown)).
- **Dock Previews never takes over the Dock:** Snaptic only watches Dock clicks, so the Dock handles every click as usual, its preferences are never changed, and preview keys work only while you use a preview (see [Dock Previews](#dock-previews)).

## Permissions

Snaptic asks only for what the features you turned on need, and only when you turn them on. The Permissions page shows each one’s status, what needs it, and who signed the running copy (“ad-hoc” or “Developer ID …”).

| Permission | Asked for when | Used for |
|---|---|---|
| **Accessibility** (called **Device Control and Data Access** on macOS 27) | Window Switcher is on; Brightness keys or Volume keys; Gather windows on first use; Awake’s pointer movement; Hidden Icons is on (macOS 27), or its hidden-icon list or Sections (macOS 14–26); Dock Previews is on | Seeing the switcher shortcut and media keys, listing and focusing windows, moving the pointer 1 point, seeing where menu bar icons are and opening a hidden icon’s menu, and reading the Dock. |
| **Screen Recording** (Screen & System Audio Recording) | Switcher thumbnails or preview; Dock Previews’ Window thumbnails (only in onboarding or on the Permissions page); Picture in Picture | Switcher and Dock Previews thumbnails, the switcher’s full-size preview, titles of windows on other Spaces, and Picture in Picture captures. |
| **Removable Volumes** (Files & Folders) | The first time Drive Alive writes to a drive | Rewriting `.snaptic-keepalive` on the drives you chose. |

Accessibility and Screen Recording are in **System Settings › Privacy & Security**. The permission window shows the exact app path, with “Show Snaptic in Finder” so you add *this* copy. On macOS 27 a grant often takes effect only after a relaunch; Snaptic offers **Relaunch Snaptic**. Without Accessibility the switcher stays idle, Awake only appears active instead of moving the pointer, and Hidden Icons shows your icons on macOS 27 (on macOS 14–26 it still hides them, without the list), and Dock Previews waits (“Dock Previews needs Accessibility to read the Dock.”). Without Screen Recording the switcher shows app icons and only windows on the current Space, and Dock Previews shows window titles; it never asks for the permission when you point at the Dock. macOS Sequoia and later re-confirm Screen Recording about once a month; that prompt comes from macOS.

Most Displays features need no permission at all. Awake needs none for sessions, rules, guards, holds, appear active, history, or the menu bar: its conditions read only system state that macOS gives any app without asking (no Location, Bluetooth, Microphone, Input Monitoring, Local Network, or Downloads folder access). Lid-closed mode needs no permission either; instead it asks for an administrator password each time you turn it on.

Release builds are signed with a Developer ID, so permissions you grant survive updates. Going from 0.3.0 or earlier (ad hoc) to 0.3.2 or later (Developer ID) resets Accessibility and Screen Recording once: remove the old Snaptic with − in each list, then turn on the new one.

## Command line

Off by default. Turn it on in **Settings › General › Command-line control**.

**Install.** **Copy Install Command** copies the command that links `snaptic` into `/usr/local/bin` (it asks for your password):

```bash
sudo ln -sf '/Applications/Snaptic.app/Contents/MacOS/Snaptic' /usr/local/bin/snaptic
```

Without installing: `/Applications/Snaptic.app/Contents/MacOS/Snaptic cli help`.

**Usage.** `snaptic [--json] [--yes] <command> [arguments]`. `snaptic help` lists the commands available right now (a command appears only while its feature is on); `snaptic help <command>` narrows it, for example `snaptic help awake`, `snaptic help icons`, or `snaptic help dock`. `--` ends options, so `-10` is read as a value.

- `--json`: machine-readable output. Lists and `get`, `set`, `ddc`, `mode`, `layout`, `virtual`, `pip list`, `awake status`, and `dock status` print JSON arrays or objects; any other command prints `{"ok": true}` (with `"output"` when it has text). Errors, including the client’s own (an unknown option, Snaptic not running), print `{"exitCode": …, "error": …}`.
- `--yes`: skips the “Keep this change?” panel, but only if you also turned on “Commands can skip confirmation” (General › Advanced…). The change is then kept right after the displays settle; the safety helper and the undo journal protect it exactly as they protect a confirmed change. Otherwise the panel shows and the command waits for your answer.
- Commands that change displays (`mode …`, `match-ui`, `mirror`, `rotate`, `disconnect`, `layout apply`) wait for the outcome: exit 0 when the change was applied or kept, 6 when it was declined in the panel or timed out.
- Values can be absolute (`60`), relative (`+10`, `-5`), or percentages (`50%`, `+10%`).

**Choosing a display.** `main`, `mouse` (or `pointer`), `focus`, `all`; a number from `snaptic list` (the same numbers Identify shows); `id:N` (a CoreGraphics display id); a 32-character display key; or a name (an exact match first, then a unique prefix, case-insensitive). A prefix that matches several displays exits with 2 and lists them. Commands that take an optional display default to the main one; `get …` defaults to all.

### Snaptic and Displays commands

| Command | Feature | Notes |
|---|---|---|
| `version`, `modules`, `safe-mode` | — | Always available |
| `module disable <windowSwitcher\|displays\|awake\|hiddenIcons\|dockPreviews>` | — | Off only |
| `open-settings [page]` | — | Optionally at a page id, e.g. `displays.brightness` or `awake` |
| `list`, `features` | Displays | Displays: number, key, name, size, state. Features: on or off |
| `feature disable <feature>` | Displays | Off only |
| `identify`, `redetect`, `diagnostics` | Displays | Diagnostics has identifiers masked |
| `panic`, `resume` | Displays | Restore All Displays; resume automation |
| `mode list\|up\|down\|hidpi\|native\|default\|halved\|undo\|redo\|notch [display]`, `mode set <display> WxH[@Hz] [hidpi\|lodpi]`, `mode favorite N [display]` | Resolution | Confirms new modes; e.g. `snaptic mode favorite 2 mouse` |
| `match-ui` | Match Text Size | Confirms |
| `set brightness <value> [display]`, `get brightness [display]` | Brightness control | |
| `toggle xdr [display]`, `get xdr [display]` | Extra brightness | |
| `toggle sync` | Sync brightness | Pauses or resumes |
| `set gamma\|temperature\|software-contrast <value> [display]`, `color reset\|invert\|suspend [display]` | Color adjustments | Gamma 0.5–2, temperature 1900–10000 K, contrast 0.5–1.5 |
| `toggle night-shift` | Night Shift | |
| `set volume\|contrast <value> [display]`, `get volume\|contrast\|input [display]` | Hardware controls | |
| `input <name\|hex> [display]` | Input switching | Asks on screen first unless allowed without asking |
| `ddc get <code>\|set <code> <value>\|caps [display]` | Hardware controls, power control, custom controls | `set` asks first for codes that need it |
| `main <display>` | Set main display | |
| `arrange <display> <x> <y>`, `arrange <display> <placement> <reference>` | Arrangement | |
| `mirror <display> <source>\|off` | Mirroring | Confirms |
| `rotate <display> 0\|90\|180\|270` | Rotation | Confirms |
| `disconnect <display>` | Disconnect displays | Confirms |
| `connect all\|<display>`, `reconnect-all` | Disconnect displays | |
| `protect off`, `toggle protection` | Protect arrangement | Off only |
| `layout list\|apply <name\|number>\|capture <name>` | Saved layouts | Apply confirms trial content |
| `virtual list\|connect <name>\|disconnect <name>` | Virtual displays | |
| `smart-hidpi off [display\|all]`, `toggle smart-hidpi [display\|all]` | Smart HiDPI | Off only |
| `pip list\|start <name\|id>\|stop <name\|id>\|stop-all\|hide-all\|show-all\|pause-all\|resume-all`, `pip start\|stop --display <display>` (or `-d`) | Picture in Picture | Saved display configurations only; starts only while unlocked. `--display` picks configurations by source display (`stop` also matches the target), e.g. `snaptic pip start --display 2` |
| `action list`, `action run <name>` | Custom actions | Only actions marked for the command line |

Verbs are case-insensitive, so `toggle nightShift` and `toggle smartHiDPI` work too.

**`prevent-sleep` is gone.** Display sleep prevention moved to Awake in 0.3 (your 0.2 setting became a rule; see [Upgrading and downgrading](#upgrading-and-downgrading)), and 0.4 removed the old verb: it is now an unknown command (exit 2). Use `snaptic awake start`, `snaptic awake hold`, or a rule instead.

**Never from the command line:** turning on anything off-only, and changing hooks, actions, command-line settings, disconnect, auto-disconnect, dim to black, DDC unlocks, “allow without asking” choices, layout trust, or any Awake setting (rules, sessions in the menu, guards, Drive Alive, appear active, pointer movement), Hidden Icons’ settings and per-app choices, Dock Previews’ settings and app lists, and turning on lid-closed mode. Accessibility-using actions (Gather windows, pointer movement) are never command-line actions.

### Awake commands

Available while Awake is on and command-line control is on (otherwise `snaptic` answers “Unknown command.”, exit 2, or exits 5 if Snaptic isn’t running).

| Command | What it does |
|---|---|
| `snaptic awake status [--json]` | `inactive`, or a tab-separated line: `active`, the source (`manual`, `automatic`, or `holds`), the kind (`indefinite`, `duration`, `until`, `app`, `idle`, `process`, or `automatic`), the display policy (`keepOn`, `maySleep`, or `keepOnWhileActive`), the end time in UTC ISO 8601 or `-`, the seconds remaining or `-`, and the number of holds. `--json` prints one object with `active`, `source`, `kind`, `display`, `end`, `remaining`, `rule` (the rule’s number), `holds`, `pids`, and `lidClosed` (whether lid-closed mode is on). No app, rule, or process names. |
| `snaptic awake start [<duration>] [--display-may-sleep]` | Starts a session. No argument means 1 hour. Durations: `90` (minutes), `90m`, `2h`, `1.5h`, `1h30m`, `1h 30m`, `3d`, `until 17:30`, `until 5:30pm`, or `idle` (Until Downloads and Tasks Finish, at most 12 hours). Between 1 minute and 30 days. `indefinite` and `forever` are refused (exit 4): use the menu or `awake hold`. |
| `snaptic awake hold [--pid N] [--max <duration>]` | Keeps your Mac awake while this command runs, or while process N runs, at most 12 hours, or `--max` up to 24 hours. See below. |
| `snaptic awake preset <number\|name>` | Starts one of Sessions in the menu by its position (1 is the first) or its name. Until Turned Off sessions are refused. |
| `snaptic awake extend <duration>` | Adds time to the running session (sessions with an end only; holds have `--max` instead). Refused while lid-closed mode is on (exit 4): “Lid-closed sessions can’t be extended from the command line. Use Add 1 Hour in the menu.” |
| `snaptic awake stop` | Ends the running session, and lid-closed mode with it; a rule’s session counts as turned off by you. Holds end with their own commands. |
| `snaptic awake pause [<duration>]` | Pauses rules for 1 hour, or for up to 24 hours. |

- **Your sessions come first.** `start` and `preset` are refused (exit 4) while a session you started in Snaptic runs: stop it first with `snaptic awake stop`, or use `awake hold`, which never replaces anything.
- **Guards apply** to every command-line session and hold, with no Start Anyway (exit 4 with the reason).
- **Never** pointer movement or Drive Alive for command-line sessions and holds. A notice says “Awake was started from the command line.” at most once every 10 minutes, and the menu shows it.
- **Rate limit:** `start`, `hold`, `preset`, `extend`, and `stop` together are limited to 1 request per second (on top of 20 requests per second for all commands). A request over the limit exits 5 with “Too many Awake requests; wait a second and try again.”

#### `awake hold`

A hold keeps your Mac awake beside whatever else runs: up to 8 holds at a time, next to your own session and rules. Snaptic never runs your command; a hold only watches a process. The menu says “Held by Terminal” (or the app that started it, with a count).

- **`snaptic awake hold`** holds for as long as this `snaptic` process runs. It prints “Holding until this command ends (at most 12 h). Press Control-C to stop.” and keeps running. The hold ends when the command exits or is killed, its terminal closes, you press Control-C, time is up, you choose **End Command-Line Holds** in Snaptic (or turn Keep Awake off while holds are what keeps it awake), a guard ends it, or command-line control or Awake is turned off. It then prints why (“Awake hold ended: time is up.”) and exits 0, or exits 5 if Snaptic quit.
- **`snaptic awake hold --pid N`** holds while process N runs (one of your own processes; N > 1). It prints “Holding while process N runs (at most 12 h).” and exits at once. The hold survives a Snaptic relaunch.
- A ninth hold is refused: “Snaptic is already holding for 8 commands.” (exit 4).

```sh
# In a script: hold for as long as this script's shell runs
snaptic awake hold --pid $$
rsync -a ~/Projects/ /Volumes/Backup/Projects/

# Around one command in an interactive shell: a subshell, so the trap doesn't stay in your shell
( snaptic awake hold & hold=$!; trap 'kill $hold 2>/dev/null' EXIT INT TERM; make release )
```

**Control-C.** In a script or recipe, a background `snaptic awake hold &` stops on Control-C like the work beside it (Snaptic resets the Control-C signal a background job inherits ignored), and the `trap` in these examples ends the hold whenever the shell is interrupted or exits early, so it never outlives the work.

**The parent-shell pitfall.** `make` recipe lines, `npm run` steps, CI step runners, and AI agents’ tool calls run each line in a fresh `sh -c` that exits as soon as the line ends. There, `--pid $$` names a shell that exits at once, so the hold ends within milliseconds (a notice says so), and a backgrounded `hold &` left behind by one line keeps holding after the work is done, until its cap. Put the hold, the work, and the `kill` in **one** shell: one recipe line joined with `;` or `&&`, `.ONESHELL:` in a Makefile, or a script file. Or pass `--pid` of a process that lives as long as the work, or use `snaptic awake start 2h`. On CI machines, `caffeinate -w <pid>` remains a fine choice.

```make
# Makefile: one recipe line, so the hold, the work, and the kill share one shell
release:
	snaptic awake hold & hold=$$!; trap 'kill $$hold 2>/dev/null' EXIT INT TERM; ./build.sh && ./upload.sh
```

### Hidden Icons commands

Available while Hidden Icons is on and command-line control is on (otherwise `snaptic` answers “Unknown command.”, exit 2, or exits 5 if Snaptic isn’t running).

| Command | What it does |
|---|---|
| `snaptic icons show [--all]` | Shows hidden icons; `--all` includes Always Hidden. |
| `snaptic icons hide` | Hides icons again. |
| `snaptic icons toggle [--all]` | Shows or hides icons. |
| `snaptic icons status [--json]` | One line: `engine=<native\|length\|unavailable> state=<collapsed\|expanded\|needsPermission\|paused\|unavailable> hidden=<n> alwaysHidden=<n> shown=<n>`. The counts are apps, as of the last time your icons were read (Snaptic itself left out). `--json` prints one object with `engine`, `state`, `hidden`, `alwaysHidden`, `shown`, and `layoutAgeSeconds` (seconds since that read, at most a week, or `null`). No app names or bundle identifiers. |

- **Never asks first.** `hide` and `toggle` never show the “Hide all other apps’ icons?” question (macOS 27); they hide what the arrangement says.
- **Refusals exit 5** with one line, for example “Hidden Icons is paused while another menu bar app hides icons.”, “Hidden Icons needs Device Control and Data Access. Open Snaptic Settings › Permissions.”, “Hidden Icons isn’t available on this version of macOS.”, or “Drag the | divider to the left of the arrow (hold ⌘).” Any other reason a hide didn’t happen answers with the Hidden Icons page’s status row. Showing hidden icons is never refused.
- Anything else, such as `snaptic icons hide --all` or an unknown flag, is a usage error: “Usage error. Run “snaptic help icons”.” (exit 2).
- The commands do only what the arrow does: nothing moves an icon, changes a setting, or names an app.

### Dock Previews commands

Available while Dock Previews is on and command-line control is on, including in Safe Mode, while it needs permission, and while it’s paused (otherwise `snaptic` answers “Unknown command.”, exit 2, or exits 5 if Snaptic isn’t running).

| Command | What it does |
|---|---|
| `snaptic dock status [--json]` | One line: `state=<…> reason=<…\|-> until=<ISO\|-> thumbnails=<…> clickActions=<…> keys=<…> cacheEntries=<n> cacheBytes=<n>`. `--json` prints one object with the same keys in the same order, then `observerAttached` and live counters; a missing value is `null`. Always exits 0. |
| `snaptic dock pause [duration]` | Pauses Dock Previews and its Dock click actions, for 1 hour if you give no time. |
| `snaptic dock resume` | Resumes Dock Previews and its Dock click actions. |

- **Values:** `state` is `on`, `starting`, `paused`, `needsPermission`, or `unavailable`; `reason` is `safeMode`, `otherTool`, `voiceOver`, `command`, or `dockUnreadable`; `thumbnails` is `on`, `off`, or `noPermission`; `clickActions` and `keys` are `on`, `off`, `paused`, `stopped` (macOS turned them off 3 times), or `disabled` (a kill switch), each as it applies right now. `until` and the reply times are UTC ISO 8601.
- **Durations:** `30m`, `2h`, `1h30m`, or `90` (minutes), from 1 minute to 24 hours. `forever`, `idle`, `until …`, `0`, and anything over 24 hours are usage errors.
- **A pause never gets shorter:** pausing again keeps the later end. A pause isn’t saved, so relaunching Snaptic resumes.
- **Replies:** “Dock Previews is paused until ….” with the end, and for `resume` “Dock Previews is on again.”, “Dock Previews’ pause is cleared.”, or “Dock Previews isn’t paused.” (exit 0).
- **Refusals exit 5**, for `pause` and `resume` only: “Dock Previews is paused in Safe Mode.”, “Dock Previews needs Accessibility. Open Snaptic Settings › Permissions.” (`pause` only), “Dock Previews is paused while another Dock preview app runs. Choose Run Both Anyway in Dock Previews’ Advanced settings to use both.”, or “Dock Previews is paused while VoiceOver is on.”
- Anything else is a usage error: “Usage error. Run “snaptic help dock”.” (exit 2).
- The commands never change a setting or name an app or window.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (also when a hold ends normally) |
| 2 | Usage error, unknown command, or a name that matches several displays or items |
| 3 | Nothing matched (display, action, layout, configuration, Awake session in the menu) |
| 4 | Refused by policy: off-only, a protected setting, the safety rules, or an Awake refusal (a guard, a session you started in Snaptic is running, 8 holds, a session without an end, extending a lid-closed session, a caller Snaptic couldn’t identify) |
| 5 | Unavailable: Snaptic isn’t running or quit, command-line control is off, the feature is off or unsupported, too many Awake requests, a Hidden Icons refusal (paused, needs permission, unavailable, or the arrangement), or a Dock Previews refusal (Safe Mode, needs permission, another Dock preview app, or VoiceOver) |
| 6 | Cancelled or timed out (the confirmation was declined or expired; the client waits up to 90 s: the longest panel plus 30 s) |

**Recipes.** A Stream Deck “Run shell” or Raycast script command can call `snaptic set brightness +10 mouse`, `snaptic input "HDMI 1" 2`, `snaptic layout apply Office`, `snaptic awake start 2h`, `snaptic icons toggle`, or `snaptic dock pause 30m`.

## Hidden kill switches

Kill switches turn a module or a feature off for this Mac, whatever Settings says. They are Boolean keys in Snaptic’s own preferences (`app.snaptic.Snaptic`), they only ever turn things off, and pages show what they turned off as “Turned off for this Mac by an administrator or a Terminal command.” with the command that undoes it. Quit and reopen Snaptic to apply a change (Hidden Icons’, Dock Previews’, and window feature switches also apply while it runs, see below). The Diagnostics Report lists the Displays, Awake, and Hidden Icons feature switches that are set, and Dock Previews’ **Advanced…** sheet lists the Dock and window feature switches that are set; a module turned off this way says so on its page, and a turned-off private API shows as unavailable.

```bash
defaults write app.snaptic.Snaptic Modules.disable.awake -bool true                # a whole module
defaults write app.snaptic.Snaptic Modules.disable.hiddenIcons -bool true          # Hidden Icons, icons shown
defaults write app.snaptic.Snaptic Awake.disable.pointerNudge -bool true           # one Awake feature
defaults write app.snaptic.Snaptic Displays.disable.xdr -bool true                 # one Displays feature
defaults write app.snaptic.Snaptic Displays.disable.symbol.MPDisplay -bool true    # one private API
defaults write app.snaptic.Snaptic Modules.disable.dockPreviews -bool true         # Dock Previews, at the next launch
defaults write app.snaptic.Snaptic Dock.disable.keys -bool true                    # one Dock Previews feature
defaults write app.snaptic.Snaptic Windows.disable.hwCapture -bool true            # one window feature
defaults delete app.snaptic.Snaptic Awake.disable.pointerNudge                     # undo
```

- **Modules:** `Modules.disable.windowSwitcher`, `Modules.disable.displays`, `Modules.disable.awake`, `Modules.disable.hiddenIcons`, `Modules.disable.dockPreviews`. A module turned off this way never starts, its page shows why with its switch disabled, Awake also releases its assertion and doesn’t resume a session at the next launch, Hidden Icons shows your icons, and Dock Previews stays off.
- **Awake features:** `presets` (sessions in the menu), `triggers` (rules), `activity` (appear active, and so pointer movement), `pointerNudge` (pointer movement), `driveAlive`, `history`, `shortcuts`, `commandLine` (the `snaptic awake` commands), and `lidClosed` (lid-closed mode). `sessions`, `batteryGuard`, `thermalGuard`, and `indicator` are ignored, so the guards and a visible indicator always stay; use `Modules.disable.awake` to turn Awake off entirely.
- **Displays features** (ids as in `snaptic features`): `resolution`, `hiddenModes`, `scaleMatch`, `brightness`, `brightnessApple`, `brightnessDDC`, `brightnessGamma`, `brightnessOverlay`, `brightnessRestore`, `dimToBlack`, `dimOnLock`, `nits`, `xdr`, `sync`, `autoBrightness`, `color`, `colorProfiles`, `nightShift`, `applePresets`, `ddcControls`, `ddcInput`, `ddcPower`, `ddcCustom`, `brightnessKeys`, `volumeKeys`, `shortcuts`, `osd`, `osdBroadcast`, `mainDisplay`, `arrangement`, `mirroring`, `rotation`, `underscan`, `hdrToggle`, `disconnect`, `autoDisconnectBuiltin`, `protection`, `layouts`, `virtualScreens`, `smartHiDPI`, `hdrVirtual`, `pip`, `pipFilters`, `menuBarOverlays`, `hooks`, and `customActions`. `Displays.disable.symbol.<name>` turns off one private API.
- **Hidden Icons features** (`Icons.disable.<id>`): `native` (the macOS 27 method, so Hidden Icons is unavailable there), `length` (the macOS 14–26 method, likewise), `inventory` (reading where menu bar icons are: on macOS 27 Hidden Icons is then unavailable; on 14–26 hiding still works, without the hidden-icon list, Sections, or new-icon notices), `hover` (Show icons on hover), and `axpress` (opening a hidden icon’s menu from the list; the rows stay, dimmed). Snaptic reads these every second, and turning on the switch for the method in use shows your icons at once.
- **Dock Previews and window features** (`Dock.disable.<id>` and `Windows.disable.<id>`): Snaptic reads these each time it uses the feature, so they apply while it runs. Window feature switches affect the Window Switcher and Dock Previews, except `symbolicHotKeys` and `layoutType`, which affect only the Window Switcher.

| Switch | Effect |
|---|---|
| `Dock.disable.clickActions` | Dock clicks are left entirely to the Dock. |
| `Dock.disable.keys` | Keys pass through to the active app; the pointer still works in previews. |
| `Windows.disable.hwCapture` | Minimized windows and windows on other Spaces show the last thumbnail Snaptic saw, then the app icon. |
| `Windows.disable.axWindowID` | Cards are matched to their windows by title and position; a card without a match offers only **Bring Forward**. |
| `Windows.disable.raise` | Windows are raised with Accessibility; a window on another Space only switches to its app. |
| `Windows.disable.spaces` | Windows on other Spaces aren’t listed. |
| `Windows.disable.symbolicHotKeys` | macOS keeps ⌘⇥; the Window Switcher can’t take it over. Giving ⌘⇥ back always works. |
| `Windows.disable.layoutType` | The key above Tab is found as on a US (ANSI) keyboard. |

### Deploying kill switches in an organization

Snaptic reads only the user’s own preferences, never managed (forced) preferences, so a profile payload that *forces* a key has no effect. To deploy kill switches, write them into each user’s own `app.snaptic.Snaptic` domain:

- **With a configuration profile:** a Custom Settings (`com.apple.ManagedClient.preferences`) payload whose keys are applied **Set-Once**, so macOS writes them into the user’s preferences rather than forcing them. Install it as a user-scope profile. Where macOS puts Set-Once values isn’t documented, so the sample below is untested: check on a test Mac that Settings shows the feature as turned off. That check is the one that counts, because Settings uses the same reader as the feature (`defaults read app.snaptic.Snaptic Awake.disable.pointerNudge` may print `1` for a managed value Snaptic ignores). If Settings doesn’t show it, your macOS version applies the payload as managed; use the script below.
- **With a script** your management tool runs as the user (or with `sudo -u <user>`): the `defaults write` lines above.

A key written this way is a default the user can delete again, not an enforcement; Snaptic’s hard limits (the 5% battery floor, the heat guard, pointer movement only for sessions you start in Snaptic) don’t depend on it.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadDisplayName</key>
  <string>Snaptic kill switches</string>
  <key>PayloadIdentifier</key>
  <string>com.example.snaptic.killswitches</string>
  <key>PayloadScope</key>
  <string>User</string>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>00000000-0000-4000-8000-000000000001</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadType</key>
      <string>com.apple.ManagedClient.preferences</string>
      <key>PayloadIdentifier</key>
      <string>com.example.snaptic.killswitches.preferences</string>
      <key>PayloadUUID</key>
      <string>00000000-0000-4000-8000-000000000002</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>PayloadContent</key>
      <dict>
        <key>app.snaptic.Snaptic</key>
        <dict>
          <key>Set-Once</key>
          <array>
            <dict>
              <key>mcx_preference_settings</key>
              <dict>
                <key>Awake.disable.pointerNudge</key>
                <true/>
                <key>Awake.disable.driveAlive</key>
                <true/>
              </dict>
            </dict>
          </array>
        </dict>
      </dict>
    </dict>
  </array>
</dict>
</plist>
```

Replace the identifiers and the two UUIDs with your own (`uuidgen`), and list the keys you want.

## Install and build

### Requirements

- macOS 14 Sonoma or later (Apple silicon or Intel); supported on 14, 15, 26, and 27
- To build: Xcode 16.4 or later (the version CI uses), or its Command Line Tools

### Download

Grab `Snaptic.dmg` from the [latest release](https://github.com/revylfitness/snaptic/releases/latest), open it, and drag Snaptic onto the Applications folder next to it. `Snaptic.zip` holds the same app if you’d rather unzip it. Releases are built by GitHub Actions from the tagged commit.

From 0.3.1 on, releases are signed with the Developer ID of Snaptic’s developer, Sean Frasure, and notarized by Apple, so macOS opens them without an **Open Anyway** step. Run Snaptic from Applications: if macOS starts it from a temporary “translocated” location, Snaptic tells you to move it first (lid-closed mode refuses to run from there).

**Coming from 0.3.1 or earlier?** 0.3.0 and earlier can’t update themselves, and 0.3.1 doesn’t start, so download the latest release one last time and replace the old copy in Applications. After that, Snaptic can keep itself up to date (see [Updates](#updates)), and macOS asks you to allow Accessibility and Screen Recording once more (see [Upgrading and downgrading](#upgrading-and-downgrading)).

To check a download yourself:

```bash
codesign -dv --verbose=2 /Applications/Snaptic.app 2>&1 | grep Authority   # Developer ID Application: Sean Frasure (7TFS5G4532)
spctl -a -t exec -vv /Applications/Snaptic.app                             # accepted, source=Notarized Developer ID
```

### Build and run

```bash
git clone https://github.com/revylfitness/snaptic.git
cd snaptic
INSTALL=1 ./scripts/build-app.sh      # builds and installs Snaptic.app to /Applications, owned by root
open /Applications/Snaptic.app
```

Leave out `INSTALL=1` to build only (`build/Snaptic.app`). For a universal Apple silicon and Intel build, which needs full Xcode, add `ARCHS="arm64 x86_64"`. The unit tests in `Tests/` run with `swift test`, also on Linux.

`INSTALL=1` installs the app owned by root (it runs `sudo ditto` and `chown -R root:wheel`, so it asks for your password). That way your account, and any program running as you, can’t replace the binary that holds Snaptic’s permissions. Snaptic warns before you grant a permission if its bundle is writable by you. A root-owned copy also makes the administrator password prompts of [lid-closed mode](#your-password-and-what-runs-as-root) safer to trust, and each update of it asks for an administrator password (see [Updates](#updates)). Awake runs nothing as root except while you use lid-closed mode, after you type your password; the `INSTALL=1` password is only for installing.

GitHub Actions compiles every push and pull request, without any signing secrets. Every push also rehearses a release without secrets: it signs the release bundle ad hoc, makes the disk image, runs the self-tests with Sparkle loaded, and builds and checks a signed feed with a throwaway update key, so a release tag adds only the Developer ID signature, notarization and the real keys. Pushes to `main` also upload an ad-hoc signed `Snaptic-adhoc` build as a workflow artifact; it doesn’t contain Sparkle, so it can’t update itself, and macOS will warn before opening it. To make the disk image from a local build, run `./scripts/make-dmg.sh` after `build-app.sh`. Pull requests and manual runs never publish a downloadable app.

**Releases** are built only from a version tag (`vX.Y.Z`) on `main`. The same compiled app gets Sparkle added, is signed with the Developer ID certificate and the hardened runtime (no entitlements), and is notarized and stapled, both as `Snaptic.zip` and as `Snaptic.dmg`. Signing and publishing run in two separate GitHub environments, each limited to version tags and each needing the owner’s approval for every run. A separate job adds a build-provenance attestation to the signed zip and disk image. Verify that a download came from this workflow at its release tag:

```bash
gh attestation verify Snaptic.zip --repo revylfitness/snaptic \
  --signer-workflow revylfitness/snaptic/.github/workflows/build.yml --source-ref refs/tags/v0.3.1
```

### Signing and permissions

The build script always signs with the **hardened runtime** and refuses to finish if it’s missing. This stops other programs from injecting code into Snaptic to borrow its permissions. By default it signs ad hoc, and macOS ties permissions to that exact build, so after a rebuild you’ll need to grant Accessibility again. Do that cleanly:

```bash
tccutil reset Accessibility app.snaptic.Snaptic
codesign -dv /Applications/Snaptic.app      # check it's the build you just made, then grant access
```

Signing with your free Apple Development certificate keeps permissions across rebuilds:

```bash
security find-identity -v -p codesigning
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" INSTALL=1 ./scripts/build-app.sh
```

A stably signed build inherits its permissions automatically, so only rebuild from code you’ve reviewed. Anything that can use that certificate’s key in your login keychain could also sign a replacement that inherits Snaptic’s permissions, so keep the key’s access restricted.

With a `SIGN_IDENTITY="Developer ID Application: …"` identity, `build-app.sh` also embeds and signs Sparkle, the update framework. A build without `SIGN_IDENTITY` contains no Sparkle: About says “This copy was built from source, so it can’t update itself.” and **Check for Updates…** opens the Releases page.

**Why release builds use a Developer ID.** Snaptic’s helpers (the safety helper and virtual-display hosts) check that they were started by Snaptic, and Snaptic checks each helper, by code signature. With an ad-hoc build that signature is the exact build, so permissions are lost on every update and, after updating in place, helpers are refused until you restart Snaptic (“Restart Snaptic to finish updating”). A Developer ID signature (team plus identifier) survives updates and can be notarized, so from 0.3.1 on every release is signed with Sean Frasure’s Developer ID (team `7TFS5G4532`) and notarized. The trade-off: macOS accepts **any** Snaptic build signed by that team under the same permissions, including older releases. That’s why only tagged releases are ever signed with it; `main` and pull-request builds stay ad hoc.

## Updates

From 0.3.1 on, release builds update themselves with [Sparkle](https://sparkle-project.org) 2, from a signed feed on GitHub Releases. Snaptic checks only if you allow it.

**Asking first.** Snaptic asks in its own window, never with Sparkle’s prompt: new users see a “Keep Snaptic Up to Date” step in onboarding (“Snaptic can check GitHub once a day and install updates when you quit it. GitHub sees your IP address and macOS version, nothing more.”), and people upgrading from an earlier version see the same choice on the “Welcome to Snaptic 0.3.1” card. **Check Automatically** turns on checks and automatic installs; **Not Now** turns both off. Until you choose, Snaptic never checks.

**Settings › About › Updates**
- **Check for Updates…** checks now (in a build without Sparkle, it opens the Releases page).
- **Check for updates automatically:** once a day, Snaptic checks GitHub for a newer version.
- **Download and install updates automatically** (shown while checks are on): updates download in the background and install the next time Snaptic quits.
- A status line: when it last checked, “Checking…”, “Version 0.3.2 is available.” or “Version 0.3.2 is ready to install.” with **Install and Relaunch…**, or “Automatic checks are off.”

**When an update is found,** Snaptic doesn’t pop up a window that could land behind others. Instead the Snaptic menu shows **Update Available: Snaptic 0.3.2…** above Snaptic Settings… (**Restart to Update Snaptic…** once it has downloaded and installs automatically), and the About page shows it too. Either brings Sparkle’s update window forward, with the release notes, which come inside the signed feed. After an update, Snaptic says “Snaptic was updated to 0.3.2.” once, with **What’s New**.

**When updates wait.** An update never relaunches Snaptic while lid-closed mode is on (or is turning on or off) or while a display change is waiting for “Keep this change?”. A downloaded update that installs at quit then waits for you, and the status line says so (“Version 0.3.2 will install when you quit or restart Snaptic after lid-closed mode ends.”). If you chose **Install and Relaunch** in Sparkle’s window, Snaptic says “Snaptic will restart and install version 0.3.2 when lid-closed mode ends.”, keeps that line in About and the menu, and restarts by itself once the mode ends. Quitting Snaptic, which ends both, may install a downloaded update. When Snaptic restarts itself while a downloaded update waits, the update installs and the new version opens if Sparkle can still hand it over; otherwise, and always for **Restart in Safe Mode…** (which never installs it), Snaptic asks you to quit it first and then open it again (holding ⇧ for Safe Mode). In Safe Mode scheduled checks pause, and Sparkle’s window never appears during onboarding or in Safe Mode; **Check for Updates…** still works, so a broken release can always be replaced.

**Copies owned by root** (installed with `INSTALL=1`, or after `sudo chown -R root:wheel`): each update asks for an administrator password through Sparkle’s installer, so updates install only when you choose **Install and Relaunch**, and About says “Only an administrator can change this copy of Snaptic, so each update asks for an administrator password.” instead of offering automatic installs.

**Builds from source** have no Sparkle and can’t update themselves (see [Signing and permissions](#signing-and-permissions)). A future Homebrew cask would set `auto_updates true`, so Homebrew leaves updates to Snaptic.

**How an update is checked.** The feed is signed with Snaptic’s update key (EdDSA), and so is every download; the download’s signature is checked before anything is unpacked. The feed address is fixed in the app and can’t be changed through preferences. So that a lost key can be replaced, Sparkle also accepts a download that carries Snaptic’s Developer ID signature instead (a signed disk image from the same team, whose app brings a new update key). In practice:
- **The update key alone** can sign a feed and an update that Snaptic installs.
- **The Developer ID certificate alone** can’t sign the feed. Sparkle uses a feed it can’t verify only after its checks have failed for 20 days in a row, and then shows the update without release notes and never installs it by itself.
- **A signed feed carries no date.** Someone who controls the release or the connection can keep serving an older signed feed, which holds copies at that version (Sparkle never installs an older one), and a program running as you can start the 20-day period early by editing Snaptic’s preferences.

The two secrets live in separate GitHub environments that run only for version tags and only after the owner approves each run, and the owner reviews a tag’s changes, including `.github/`, before approving. That protects against one leaked secret, not against the owner’s GitHub account: whoever controls it (a signed-in browser, or a token with `repo` scope, such as the one `gh auth login` stores) can push a tag and approve both environments, and so publish a signed, notarized update on their own, without either secret. Everything therefore rests on that account’s own protection: two-factor sign-in with a passkey or hardware key, and no long-lived token that can approve deployments on the Mac it’s used from.

**Processes.** Sparkle runs its own `Autoupdate` and `Updater.app` (inside Snaptic’s bundle) to install an update, and asks for an administrator password through macOS for a root-owned copy. Snaptic’s helper and command-line processes load Sparkle in a release build but never use it.

### If a release key leaks

The release workflow keeps the update key’s public half in `.github/workflows/build.yml`: `SU_PUBLIC_ED_KEY` (the key installed copies trust; the `appcast` secret must be its seed), `SU_NEXT_PUBLIC_ED_KEY` and `SU_NEXT_KEY_TAG` (empty except during a rotation), and `SPARKLE_ARCHIVE` (`Snaptic.zip`, or `Snaptic.dmg` after a rotation). Sparkle’s `generate_keys` is in `bin/` of [Sparkle-2.10.0.tar.xz](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0).

**The update key leaks, and you still have it.** One release carries the new key but is still signed with the old one. Sparkle checks a download only against the key of the copy it updates, so every copy accepts it.
1. Make a new key on your Mac: `./bin/generate_keys --account snaptic-2` prints its public key, and `./bin/generate_keys --account snaptic-2 -x new-key.txt` exports its seed. Keep `new-key.txt` private.
2. In one pull request, set `SUPublicEDKey` in `Resources/Info.plist` to the new public key, set `SU_NEXT_PUBLIC_ED_KEY` to the same key and `SU_NEXT_KEY_TAG` to the new release’s tag (for example `v0.3.2`), and bump the version as for any release. Leave `SU_PUBLIC_ED_KEY` and the `appcast` secret on the old key.
3. Merge, push the tag, and approve both deployments. CI refuses the tag unless the app carries exactly the next key, then signs the feed and the zip with the old key and checks both against it. (Sparkle’s `generate_appcast` leaves the zip unsigned when the app’s key isn’t the signing key, so the workflow signs it with `sign_update`; every push rehearses this case with a throwaway key.)
4. Once the release is published, replace the secret (`gh secret set SPARKLE_ED_PRIVATE_KEY --env appcast < new-key.txt`, then delete `new-key.txt`), and in a pull request set `SU_PUBLIC_ED_KEY` to the new key, empty `SU_NEXT_PUBLIC_ED_KEY` and `SU_NEXT_KEY_TAG`, and set `SPARKLE_ARCHIVE` to `Snaptic.dmg`. CI refuses any other tag until the rotation is finished, and refuses a secret that doesn’t match `SU_PUBLIC_ED_KEY`.
5. Ship the next release within a few days: until then, copies already on the new key report that the check failed, because the published feed is still signed with the old one.
6. Delete the old key from your keychain (the old account’s “Private key for signing Sparkle updates” in Keychain Access) and wherever else it was kept.

Copies that skipped the rotation release still trust the old key, so they can’t verify later feeds. Their checks fail for 20 days; then Sparkle shows the newest update anyway (without release notes, never automatically), and it installs because the download is the Developer ID-signed disk image, signed with the new key. Or download Snaptic again by hand.

**The update key is lost.** No release can be signed with a key that installed copies trust.
1. Make a new key as in step 1 above, and store its seed in the `appcast` environment (`gh secret set SPARKLE_ED_PRIVATE_KEY --env appcast < new-key.txt`).
2. In one pull request, set `SUPublicEDKey` in `Resources/Info.plist` and `SU_PUBLIC_ED_KEY` to the new public key, and `SPARKLE_ARCHIVE` to `Snaptic.dmg`. Release as usual.
3. Installed copies can’t verify the new feed: they report failed checks for 20 days, then show the update and install the signed disk image when the user chooses to. Ask users, here and on the Releases page, to download the new version by hand instead of waiting.
4. Keep `SPARKLE_ARCHIVE` on `Snaptic.dmg` from then on, so copies that come back later can still update.

**The Developer ID certificate leaks.** Revoke it in the Apple developer account (revoking can make Gatekeeper reject earlier downloads signed with it; contact Apple Developer Technical Support if older builds must stay valid), create a new one for the same team, replace `DEVELOPER_ID_P12_BASE64` and `DEVELOPER_ID_P12_PASSWORD` in the `release` environment, and release as usual. The update key signs that release, so every copy accepts it, and the team is unchanged, so permissions carry over.

In every case, a note goes in the README and on the Releases page.

## Privacy and security

**Network: only for updates, and only if you allow it.** If you allow it, Snaptic contacts GitHub (github.com and its download host) once a day, and when you choose **Check for Updates…**. It downloads the signed update feed, and an update when you install one. GitHub sees your IP address, a Sparkle User-Agent with the app version, and your macOS version; Sparkle’s system profiling is off. The feed and every update are signed with Snaptic’s update key; a download signed with Snaptic’s Developer ID is accepted only so that a lost key can be replaced (see [Updates](#updates)). Nothing else connects: no telemetry, no analytics, no crash upload, and a lint check still rejects networking APIs in Snaptic’s own code.

**What never leaves the process.** Window pixels, window titles, app names, and key presses. The command line, hooks, diagnostics, and the event log never carry them. Diagnostics mask serial numbers; display keys are salted per Mac and the salt is never exported.

**What leaves on purpose.**
- *Brightness broadcast* (opt-in) posts a system-wide notification `app.snaptic.osd` with only the kind (brightness, volume, …), the value, and the maximum, at most 10 per second, and nothing while the screen is locked.
- *Hooks and custom actions* (opt-in) run programs you chose, with a minimal environment (`SNAPTIC_EVENT`, `SNAPTIC_DISPLAY_NAME`, `SNAPTIC_DISPLAY_KEY`), without Snaptic’s permissions, stopped after 30 seconds. Programs must be absolute paths owned by you or root and not writable by others. Never in Safe Mode or while automation is paused.
- *Awake’s power assertion* is visible to every app (`pmset -g assertions`), as all assertions are. Its name is always “Snaptic: keeping your Mac awake” and its details only say `manual` or `automatic`: never an app, rule, or condition.

**On disk.** Settings (in Snaptic’s preferences), and under `~/Library/Application Support/Snaptic/` (0700): the single-instance lock, the command-line socket, undo journals for display changes, copies of imported LUTs, and, while lid-closed mode is on or its recovery is pending, a small journal (`awake/lid.json`, 0600). Lid-closed mode also keeps two empty files in a private folder (0700) of your temporary folder for its watchdog. The remembered Snaptic menu tab is a plain preference. Release builds add Sparkle’s update cache, `~/Library/Caches/app.snaptic.Snaptic/org.sparkle-project.Sparkle`, and Sparkle’s `SU…` keys in Snaptic’s preferences; **Reset All Settings…** clears those keys. Drive Alive’s only trace is the 8-byte `.snaptic-keepalive` file on drives you turned on. Hidden Icons’ per-app choices, known apps, and new-icon list (app bundle identifiers, never names) are stored apart from your other settings and never exported. Backup export leaves out hooks, actions, command-line settings, the salts, DDC unlocks, “allow without asking” choices, layout trust, sensitive switches (disconnect, auto-disconnect, dim to black), Awake’s history, Drive Alive drives, pointer movement, lid-closed mode (import keeps this Mac’s choice), the update settings, the remembered menu tab, the apps you used recently, and Hidden Icons’ per-app choices, new-icon list, and icon positions; Awake rules are included only if you tick “Include automatic-session rules”. Dock Previews’ settings, “Apps hidden from Dock previews” included, are exported. Import strips the same things even if present, can only make Awake’s guards stricter, and can only add apps to “Never show thumbnails for”, never remove one.

**Hidden Icons.** To know which icons are where, Snaptic reads other apps’ menu bar icon positions and app identities with Accessibility; on macOS 14–26 it does so only for the hidden-icon list and Sections. App names and bundle identifiers never go into the event log, diagnostics (which keep counts only), or the command line. Snaptic never moves, clicks, or changes another app’s icon, except opening one’s menu when you choose it in the hidden-icon list.

**Dock Previews.** To show previews, Snaptic reads the Dock’s items and other apps’ windows with Accessibility. App names, window titles, and bundle identifiers never go into the event log, diagnostics, or the command line (`snaptic dock status` gives states and counts only). Thumbnails stay in memory. Snaptic never changes the Dock’s preferences and never posts clicks or key presses: it watches Dock clicks only while a Dock click action is on, and the keyboard only while a preview is in use.

**Command line.** Only your user account can connect, through a private socket (directory 0700, socket 0600); Snaptic never listens on the network. Requests are size-, rate-, and time-limited. See [Command line](#command-line) for what it can never change.

**Helpers and other processes.** The safety helper and virtual-display hosts are copies of Snaptic’s own executable, started with an empty environment and their own process responsibility, so they hold none of Snaptic’s permissions. Each side checks the other’s code signature. Only for lid-closed mode, Snaptic also starts Apple’s `/usr/bin/osascript` (which asks for your password and starts the root watchdog; see [Your password and what runs as root](#your-password-and-what-runs-as-root)) and `/usr/bin/pmset displaysleepnow` as you; before either runs, Snaptic checks that it’s signed by Apple, and it starts with a minimal environment. Release builds also contain Sparkle’s `Autoupdate` and `Updater.app`, which run only to install an update, and Sparkle’s installer asks for an administrator password when the copy is owned by root.

**Picture in Picture.** Display captures never include Snaptic itself, Notification Center, or apps on the protected list; browser windows marked private (Firefox, Edge, Chrome’s Incognito title) and untitled browser windows are left out. Locking or sleeping the Mac stops captures and clears their last frame. Snaptic never starts a capture by itself.

**Overlays vs password prompts.** While a password or authentication window is on screen, Snaptic orders out full-screen dimming overlays and raises dim-to-black to at least 30%. This is best effort.

**Window Switcher.**
- **Keys.** Snaptic’s keyboard tap reacts only to its own shortcuts. While the switcher is open it also reads the keys you press there (to search and for the action keys); search text is cleared when the switcher closes. Password fields use macOS Secure Event Input, which Snaptic can’t see; while it’s active, or whenever Snaptic’s tap is off, ⌘⇥ goes back to macOS. If Snaptic ever hangs, a background guard hands ⌘⇥ back within about two seconds, and quitting Snaptic by any normal means or signal restores it.
- **Never stuck.** The switcher closes if you click elsewhere, switch apps, or change Spaces, and switches as soon as the modifier key is up even if Snaptic missed the release. If it stays open after release (searching, or “switch on release” turned off), it closes after 30 seconds without input. If the window list takes more than 2 seconds to load, it gives up.
- **Slow or hostile apps.** Accessibility requests to other apps time out after 0.15 seconds, each app gets at most half a second and 100 windows, and listing gives up on stragglers after 1.2 seconds. Window titles and app names from other apps are length-limited and stripped of control and text-direction characters.
- **Thumbnails** are kept in memory only and never saved: at most 120 thumbnails and 96 MB, for at most 30 minutes, shared by the Window Switcher and Dock Previews. They’re taken only while the switcher or a preview is showing, and cleared when the Mac sleeps, locks, or switches user, when Screen Recording is turned off, and when neither module needs them any more. Snaptic’s panels ask macOS to keep them out of screen sharing and screenshots, though some capture methods may not honor that.
- **Sensitive windows.** Windows of apps on the “Never show thumbnails for” list (by default 1Password, Bitwarden, Apple Passwords, Tor Browser, and others) are never captured and show their app icon and name instead of their title, in the Window Switcher and Dock Previews (see [Private windows](#private-windows)). Safari and Chrome don’t mark private windows, so add them to the list if you don’t want any of their windows captured.
- **No hijacking ⌘.** ⌘ can’t be combined with letters or digits, so Snaptic can never take over ⌘C, ⌘V, ⌘Q, and the like.
- **App identity.** App lists match bundle identifiers, which apps declare themselves. An app could pretend to be on the “keep the shortcut” list; at worst it would receive your switcher shortcut while it’s in front.

### What Awake reads and keeps

Nothing Awake reads leaves your Mac, and none of it needs a permission.

- **What it reads, only while a session, rule, or page needs it:** the battery and power adapter state, the thermal state, Low Power Mode, whether the screen is locked and whose session is on screen, the list of running apps, connected displays, mounted drives, connected USB devices, whether audio is playing or the microphone is in use (never the audio itself), how long since you last used the keyboard or mouse, your Mac’s network addresses and its router’s hardware address, network and disk byte counters, CPU use of your own processes (as numbers only, never their names), Bluetooth audio and input devices’ properties (never opened), which other apps hold power assertions, and whether sleep is turned off for the Mac (`SleepDisabled`, from the power preferences and the kernel) and the lid is closed.
- **What it keeps:** your rules and sessions in the menu (with the app, device, and network names you chose) in Snaptic’s preferences; routers and USB serial numbers only as salted hashes; recently used apps for the menu (at most 5); and History (90 days). Other programs running as you can read Snaptic’s preferences, as with any app.
- **What it never does:** send anything anywhere, log app, device, network, or process names (its log keeps only counts and error codes), put names in diagnostics or the command line (the CLI shows process numbers only), or store a timeline in logs. CPU and disk samples stay in memory for the running Until Downloads and Tasks Finish session only.
- **What it runs:** Awake runs a program only while you use lid-closed mode: `/usr/bin/osascript` asks macOS for an administrator password, then starts a short shell script as root that runs `pmset` and turns sleep back on when the session ends, Snaptic quits or stops responding, the battery reaches your limit, your Mac gets hot, or 24 hours pass. While the lid is closed, Snaptic also runs `pmset displaysleepnow` as you to keep the screen dark.
- **What it can’t be made to do:** type, click, or scroll, or use Snaptic’s permissions for anyone else, and nothing but you, in Snaptic’s own windows and menus, can turn on lid-closed mode. A program running as you can already hold the same power assertion with `caffeinate`, so the command line grants nothing new; command-line sessions are visible in the menu bar and bounded in time.

**Startup checks.** Snaptic accepts only its own launch arguments, refuses to start with code-injection-style environment variables (`DYLD_*`, `OBJC_*`, `NS*`, `CF*`, `Malloc*`, and similar) or a `HOME` that isn’t your account’s, reads settings only from its own preferences (not command-line or managed overrides), and runs one copy at a time.

## Upgrading and downgrading

**0.4.0 → 0.5.0.** Snaptic updates itself, and no setting is lost. Dock Previews starts off: a “New: Dock Previews” card in General offers **Turn On Dock Previews** or **Not Now**.

- **Window Switcher:** minimized windows and windows on other Spaces get thumbnails too, where macOS allows it; otherwise they show the last one Snaptic saw, then the app icon. Thumbnails now stay in memory for up to 30 minutes, so the switcher opens with them and refreshes them in place. Its **Advanced…** sheet has the new Privacy footer and list help, and **Window thumbnails** says what turning it off does.
- **Privacy:** **Protect private windows** and “Never show thumbnails for” now apply to Dock Previews too, and **Restore Defaults…** leaves them as they are (see [Private windows](#private-windows)).
- **Going back to 0.4.0:** every setting stays, including your protected apps.

**0.3.4 → 0.4.0.** Snaptic updates itself, and no setting is lost. Hidden Icons starts off (a “New: Hidden Icons” card in General). The app has a new icon. `snaptic prevent-sleep` is gone (it has answered “Moved to Awake” since 0.3).

- **Going back to 0.3.4:** your other settings stay, and Hidden Icons’ settings are kept for when you return. Quit 0.4 first so your icons are shown.

**0.3.3 → 0.3.4.** Snaptic updates itself, and no setting is lost. Lid-closed mode turns on again on macOS 27, where every attempt used to fail.

**0.3.2 → 0.3.3.** Snaptic updates itself, and no setting is lost. Lid-closed mode’s opt-in moved from **Awake › Advanced…** to the Awake page’s **Lid closed** section and the Menu Bar page; if it was on, it stays on.

**0.3 → 0.3.1.** No setting is lost, and nothing about your modules, sessions, or rules changes. Coming from 0.2 or 0.1, the steps below apply too; from 0.2, the 0.2 → 0.3 steps further down run first.

- **One last manual download.** 0.3.0 and earlier have no updater, so download the [latest release](https://github.com/revylfitness/snaptic/releases/latest) and replace the copy in Applications. 0.3.1 itself doesn’t start (it says it couldn’t look up your home folder), so it can’t update either: replace it the same way. From 0.3.2 on, Snaptic updates itself.
- **Permissions, once.** 0.3.1 is the first release signed by its developer, so macOS treats it as a new app for Accessibility and Screen Recording. Settings opens on General with a “Welcome to Snaptic 0.3.1” card: “Snaptic is now signed by its developer, so macOS asks you to allow it again once. After this, updates keep your permissions.” For each permission you had granted, it says “Remove the old Snaptic with −, then turn on the new one.” with **Open System Settings…**.
- **Updates:** the card asks whether to keep Snaptic up to date (**Check Automatically** or **Not Now**), and **Done** hides it. It also hides itself once you’ve chosen and the permissions work again.
- **Open at login:** if Snaptic doesn’t open at login after the change of signature, or Login Items lists it twice, turn Open at login off and on again in General.
- **Going back to 0.3.0** works like any older copy: it ignores the remembered menu tab, lid-closed mode, and the update settings, and its ad-hoc signature needs the permissions granted again. Turn lid-closed mode off before you go back.

**0.2 → 0.3.** No setting is lost; every 0.2 setting, button, and menu item has a home in 0.3, and Settings search finds it.

- **Display sleep prevention moved to Awake.** If it was on in 0.2 (Displays on, the feature on, and at least one display set to prevent sleep), 0.3 turns Awake on with a rule “While a display is connected” for those displays (up to 8 per rule), keeping the display on. General shows “Your display sleep setting moved to Awake.”, and the first time the rule applies, a one-time notice says so. If it wasn’t in use, Awake starts off with a “New: Awake” card.
- **Its shortcut** moves to Awake’s **Pause or Resume Rules** if a rule was created and that shortcut isn’t set yet; otherwise it’s removed, and Recent Notices says “Your display sleep shortcut was removed. Set Awake shortcuts in Settings › Awake › Keyboard Shortcuts.”
- **Menu bar placement** (shared, own icon, hidden, and Displays’ “hide when no external display is connected”) becomes the new per-module pop-up on the Menu Bar page.
- **`snaptic prevent-sleep`** was retired, and 0.4 removed it; see [Command line](#command-line).
- Each upgrade step runs once and records that it ran, so a later change you make isn’t undone at the next launch.

**0.3 → 0.2 → 0.3.** You can go back to 0.2 and forward again:

- **What 0.2 reads back:** 0.3 keeps writing the 0.2 fields, so 0.2 finds your Window Switcher and Displays settings, the menu bar placement you chose in 0.3 (Awake’s “Show When Active” reads as an own icon), and its display sleep prevention settings and shortcut exactly as they were when you upgraded. 0.2’s own sleep prevention works again while you run 0.2.
- **What 0.2 ignores:** everything about Awake. Its settings, history, and state stay untouched in their own keys.
- **Back on 0.3:** the upgrade steps don’t run again, so a change you made to display sleep prevention while on 0.2 isn’t carried into Awake (adjust the rule yourself). Menu bar placement you changed in 0.2 is read again. Awake continues as you left it.

## Troubleshooting

- **A display went black or the picture is wrong.** Wait 15 seconds without pressing anything; unconfirmed changes revert. Otherwise press **⌃⌥⌘⎋** (or ⌃⌥⌘⇧⎋). If Snaptic won’t start cleanly, hold **⇧** while opening it for Safe Mode.
- **Permission is on but Snaptic still asks.** Remove Snaptic from the list with −, add it again with + (use “Show Snaptic in Finder” to pick the right copy), then relaunch. This is expected once after upgrading from 0.3.0 or earlier (see [Upgrading and downgrading](#upgrading-and-downgrading)). After rebuilding an ad-hoc build, run `tccutil reset Accessibility app.snaptic.Snaptic` first.
- **“Restart Snaptic to finish updating” or “Unprotected”.** Snaptic was replaced while running, so its helpers are refused. Quit and reopen it.
- **A display doesn’t respond to brightness or volume.** Many TVs, DisplayLink adapters, some docks, and the HDMI port on some Macs don’t pass DDC; Snaptic dims those in software instead. Hardware Controls shows whether each display answers.
- **A feature shows “Paused while … runs”.** Another display app is running. Quit it, or choose “Run both” in Displays › Advanced… › Other display apps.
- **No menu bar icon.** macOS may hide it in the overflow or in System Settings › Menu Bar. Open Snaptic again from Finder or Spotlight to get Settings, or use the “Show Displays Panel” shortcut if you set one.
- **My Mac still went to sleep during a session.** Choosing Sleep always sleeps a Mac, and so does closing the lid unless lid-closed mode is on or you use closed-display mode; see [Keeping awake with the lid closed](#keeping-awake-with-the-lid-closed). If lid-closed mode was on, the menu says why it ended for 12 hours (“Lid-closed mode ended at …”). Otherwise the menu says why the session ended for 12 hours: a guard (battery, adapter, Low Power Mode, heat), “End sessions when your Mac sleeps”, switching users, or a locked screen (Awake › Advanced…).
- **My Mac doesn’t sleep and Awake is off.** Look at Awake › Advanced… › Other apps keeping your Mac awake, or run `pmset -g assertions`. If it says sleep is turned off for this Mac, see [If sleep stays off](#if-sleep-stays-off) when an earlier lid-closed session left it off, or [Switching from Amphetamine or Insomnia](#switching-from-amphetamine-or-insomnia).
- **The display turns off during a session.** Turn on “Keep the display on” for the session (Keep Display On in the menu). On the lock screen, the display may sleep unless “Keep the display on while locked” is on.
- **`awake hold` ended at once, or kept holding after the work.** See [the parent-shell pitfall](#awake-hold).
- **Hidden icons came back by themselves.** That’s Hidden Icons failing safe; the status row on its page says why and offers the fix (see [When icons stay shown](#when-icons-stay-shown)).
- **I can’t find the arrow.** The page offers **Show Arrow** when macOS hid it; otherwise use **Advanced… › Reset Arrow Position…**, which puts the arrow and dividers back next to the Snaptic icon.
- **No Dock preview appears.** Look at the status row on the Dock Previews page: it says when previews are paused or need Accessibility (see [When previews pause](#when-previews-pause)). Nothing shows for folders, the Trash, apps that aren’t running, or apps on **Apps hidden from Dock previews**, and after you dismiss a preview the same app’s doesn’t show again until you point at another item.
- **Previews show titles instead of pictures.** Turn on **Window thumbnails** on the Dock Previews page and allow Screen Recording on the Permissions page. Private windows always show their app icon.
- **“Paused while DockDoor runs”.** Quit the other app, or choose **Run Both Anyway** in **Dock Previews › Advanced… › When another app shows Dock previews**.
- **⌘W or ⌘Q went to the app instead of the preview.** The keys work once the preview is in use: move the pointer a little inside it, or click in it (see [Keys in previews](#keys-in-previews)).
- **`snaptic` says it isn’t running, or doesn’t know `awake`, `icons`, or `dock`.** Turn on Settings › General › Command-line control, and make sure Awake, Hidden Icons, or Dock Previews is on. Exit code 5 means Snaptic isn’t running, control is off, the feature is off, or you sent Awake requests faster than once a second.
- **Lid-closed mode won’t turn on.** The notice says why: battery too low (connect power), too hot, a Start Anyway session, Snaptic running from a temporary location (move it to Applications), or sleep still turned off from an earlier session. If the password dialog doesn’t appear, check whether security software blocks `osascript`.
- **No update arrives.** Look at Settings › About › Updates: automatic checks may be off, the copy may be built from source, or an update may be waiting for lid-closed mode or a display change to finish. **Check for Updates…** checks now.
- **Filing an issue.** Copy the report from Displays › Display Information (or `snaptic diagnostics`). It has no window titles, app names, or serial numbers; Awake contributes only counts.

## Known limitations

- **Switcher:** minimized windows and windows on other Spaces get a thumbnail only where macOS allows it, otherwise the last one Snaptic saw, then the app icon. Windows on other Spaces say “Other Space” rather than which Space, and can’t be closed or minimized from the switcher. Each shortcut uses one modifier (⌥, ⌘, or ⌃) plus one key. If you close a window that asks to save first, or quit an app that asks to confirm, it disappears from the switcher until the next time you open it. Windows of hidden apps show the last thumbnail Snaptic saw, or the app icon. Minimized and hidden windows share one toggle, and “switch on release” is global.
- **Displays:** EDID-based display names are read on Intel Macs only. The panic confirmation is a notice, not a full HUD. A display “captured” by another app (a full-screen game) refuses changes and the confirm panel. Brightness sync notices changes made with a display’s own buttons only when readback is on. Auto-disconnect reads the lid state when it plans, and can’t detect a display in standby or on another input. “Disconnect on lock” ignores the screen saver. Virtual-display primaries come from EDID only (no ICC fallback). “Stream onto” associations ask rather than start. On macOS 27 the system’s own HUD also shows at the top right, so the two indicators can overlap; Snaptic’s defaults to top center there.
- **Picture in Picture:** Safari doesn’t mark private windows (add Safari to the protected apps). Window sources are picked in the system picker each time, so they can’t start automatically or from the command line. Imported LUTs aren’t included in Backup. The cursor can’t be excluded from streams, and filters can’t be applied to a stream of the display itself.
- **Awake:**
  - A MacBook with its lid closed sleeps unless lid-closed mode or closed-display mode is on, and choosing Sleep always sleeps the Mac.
  - Lid-closed mode asks for an administrator password every time, and macOS’s dialog names `osascript`, not Snaptic. Another app’s display assertion can keep the built-in display lit with the lid closed, and the keyboard backlight may stay on. It is off by default and only on Macs with a battery.
  - **Bluetooth audio** conditions are Beta and cover only Bluetooth audio devices and Bluetooth keyboards, mice, and trackpads; other Bluetooth devices can’t be detected without the Bluetooth permission.
  - No Wi-Fi network name (it needs Location access) or DNS-server condition; **Connected to this network** recognizes a network by its router instead.
  - Until Downloads and Tasks Finish can’t see other users’ processes (such as Spotlight or Time Machine running as root), but their disk activity counts, so a session may run on while they work.
  - Clicking Awake’s icon always opens its menu; there’s no ⌘-click quick start (use the Keep Awake shortcut).
  - Appear active keeps macOS from idling, but chat apps may still mark you away; pointer movement is Experimental and limited by its safety rules.
  - History, rules, and recently used apps are plain preferences that other programs running as you can read.
  - Starting a session at login needs “Open at login” and **Start a session when Snaptic opens**.
- **Hidden Icons:**
  - On macOS 14–26, a Snaptic icon that first appears while icons are hidden can land in the hidden section. ⌘-drag it to the right of the arrow once.
  - On macOS 27, the Now Playing icon is hidden while icons are hidden.
  - Always Show and Always Hide work on macOS 27 only; on 14–26 they’re kept but unused.
  - On macOS 27 the list has no behind-the-notch rows.
  - On macOS 27, with **Run Both Anyway**, an icon stays shown unless both apps hide it.
- **Dock Previews:**
  - Dock Previews works with the pointer, or with VoiceOver when “Show previews while VoiceOver is on” is on. With the keyboard alone, use the Window Switcher.
  - Moving through the Dock with ⌃F3 or Full Keyboard Access never shows a preview.
  - A Dock click while another app is becoming active, or one held longer than half a second, does nothing.
  - Where Snaptic can’t bring a window forward from another Space, it switches to the app instead.
  - Some cards offer only **Bring Forward** (see [Cards and actions](#cards-and-actions)).
  - The preview doesn’t follow the Dock’s magnification.
  - An app that doesn’t answer in time shows window titles only, for 30 seconds.
- **General:** English only (all text is ready for translation, but no translations exist yet) and no trackpad gesture. Updates need a release build: copies built from source don’t update themselves, and 0.3.1 and earlier need one manual download to reach the latest release.

### Needs testing on hardware

0.2, 0.3, and 0.3.1 were built without hardware testing (0.3.1’s checks are HW-24 to HW-38 in its [plan](design/0.3.1/PLAN.md#part-c-hardware-checks)). These depend on hardware behavior and are marked Beta or checked at runtime (a wrong guess turns the feature off rather than misbehaving). Beta labels are updated once they’re checked.

- **Awake power:** both assertion types and how `pmset -g assertions` shows them on macOS 14, 15, 26, and 27, Intel and Apple silicon; switching between them without the display dimming; the screen saver and the lock screen with each type; lid close on battery, on power, and in closed-display mode.
- **Awake guards:** power notifications on desktops and laptops; an underpowered USB-C charger counted as discharging; thermal states; the clock across sleep.
- **Appear active and pointer movement:** whether declaring activity or a 1-point move keeps chat apps active; the edge and Accessibility-denied paths; the 1-hour cap letting the Mac lock.
- **Conditions:** no microphone indicator or prompt for the audio condition; no Input Monitoring for Bluetooth input devices; no Local Network prompt for the router check; network counters at 10 GbE.
- **Drive Alive:** the Removable Volumes prompt; keeping a USB hard drive spinning; ejecting not blocked; disk images and startup volumes refused.
- **Until Downloads and Tasks Finish:** the thresholds on 10-core Apple silicon and Intel Macs during compiles, links, large copies, downloads, and archive extraction.
- **`awake hold`:** ending within a second when the client is killed, interrupted, or its terminal closes; `--pid $$` in scripts and `make`; PID reuse; 8 holds beside a session; a 12-hour idle hold.
- **Menu bar and Settings:** status item placement and hiding on 14–27 (including notched Macs with many items and Show When Active); the custom menu rows (alignment, keyboard, VoiceOver, live values while the menu is open); sidebar search and scrolling, number fields, and switch sizes on macOS 14; the tallest single tab of the Snaptic menu staying within 24 lines in the default setup.
- **Menu tabs (0.3.1):** switching tabs in an open menu on 14, 15, 26, and 27 (resizing, highlight, with a submenu open, light and dark, Increase Contrast, Reduce Transparency, the largest text size on a 13″ display with three external displays); VoiceOver, Switch Control, and Full Keyboard Access reaching the tabs and hearing “needs attention” and “on”; ⌘1–⌘3 in an open menu while ⌘, and ⌘Q still work; sliders and switch rows in a newly shown tab.
- **Lid-closed mode (0.3.1):** the password dialog from Developer ID and ad-hoc builds (its title, icon, text, Touch ID, Cancel); the output of `pmset`, `ioreg`, and `notifyutil` on Apple silicon and Intel, macOS 14 to 27; the lid closed on battery with and without an external display and with `caffeinate -d` running (staying awake, the built-in display going dark, Sleep grayed out, waking on lid open, the keyboard backlight, the icon); the watchdog surviving the dialog and restoring sleep after a quit, `kill -9`, a stopped Snaptic, the stop file, the 24-hour limit, a deleted heartbeat, a script error, and `sudo kill`; a restart while it’s on and both recovery buttons; the battery limit while Snaptic is stopped; the Mac sleeping within 30 seconds after each limit with the lid closed; the watchdog’s wakeups.
- **Updates (0.3.1):** Sparkle loading in a Developer ID build; updating from a user-owned and a root-owned copy; permissions and Open at login surviving; no Gatekeeper prompt after relaunch; refusing a wrong signature, a non-Developer-ID build, and an edited feed; a root-owned copy staying `root:wheel`; waiting while lid-closed mode or a display change is pending; the menu row; no Sparkle window during onboarding or Safe Mode; a manual check in Safe Mode; installing at quit; the 0.3.0 → 0.3.1 permission re-grant; an ad-hoc build without Sparkle opening the Releases page.
- **Hidden Icons (0.4):** icons showing while the camera or microphone is on and hiding again after, and the location indicator, on macOS 27; ⌘-dragging icons while hidden; Live Activities and other macOS 27 system items; an exam session in Safari or an assessment app; seeding the dividers on a fresh macOS 15 account and the 10 000-point divider on the widest displays; running beside Hidden Bar, Bartender, Ice, and Thaw.
- **Dock Previews (0.5):** the Dock at the bottom, left, and right, hidden automatically and magnified, on several displays; Stage Manager; sleep, wake, and Dock restarts; running beside DockDoor and HyperDock; VoiceOver; thumbnails of minimized windows and windows on other Spaces, and the screen-recording indicator; Dock click actions.
- **Hidden-config abuse:** pointer movement, Drive Alive, a battery floor of zero, and forged session state written with `defaults` while Snaptic is quit, stopped, and running: none of them may move the pointer, skip the 5% floor, or write to ineligible drives.
- **From 0.2:** confirmed changes persisting across quit, relaunch, and reboot; the safety helper reverting after `kill -9` with virtual displays and a pending change; rotation and HDR reverts after a reboot; XDR extra brightness on M1–M5 XDR panels; gamma on virtual displays on M5; DDC over Apple silicon USB-C and HDMI, MCDP adapters, and Intel, and standby and wake through DDC; brightness and volume keys on Apple silicon laptops on macOS 26 and 27, and global shortcuts while a password field is focused; virtual displays and Smart HiDPI (HiDPI at creation, live mode changes, lock, sleep, Fast User Switching, lid closed with no external display, EDID colors on Apple silicon); Picture in Picture capture filters, window crop orientation, and the content-sharing picker on 14, 15, and 26; helper signature checks with ad-hoc and Developer ID builds and after an in-place update; Accessibility grants and relaunch on macOS 27; detecting password windows on macOS 26 without Screen Recording; Identify labels over full-screen apps and AirPlay.

## Not included

**Deferred** (may come later):
- **Displays:** system display overrides (scaled resolutions, display names, TV roles), connection color mode and direct XDR control, framebuffer grayscale and invert and keyboard-backlight keys, 3D LUTs on displays and compositor filters, HDMI-CEC, network TVs and receivers, DisplayLink control, HTTP-based Stream Deck plugins, True Tone and Dark Mode control, nits-normalized sync, SDR/HDR automatic profile switching, ranged custom controls with readback, Picture in Picture tabs and magnification above 100%, virtual-display identity editing, swapping identical displays, Sidecar management, and detachable menus.
- **Awake:** a “while a file is downloading” condition that watches the Downloads folder (Until Downloads and Tasks Finish and Network activity cover it), other Bluetooth devices, locking the screen after inactivity, screen saver control and exceptions, sounds, a condition on background processes by name (`awake hold` covers scripts), and `awake hold -- <command>` (Snaptic never runs commands).
- **Dock Previews:** moving a window to the current Space, live and pinned previews, card swipe gestures, showing previews only while ⌥ is held, leaving single windows out of a preview, pausing while the screen is shared, and a Space number badge.
- **Window Switcher:** Vim keys, mouse follows focus, and a swipe to open the switcher.
- **Everywhere:** App Intents and Shortcuts actions, AppleScript, Control Center and widget controls (the command line covers Shortcuts), localization, and opening a Settings page from outside Snaptic.

**Excluded by design:**
- **Displays:** EDID writing or overrides (can brick or blank a display); reinitializing displays, VMM7100 resets, forced HDR, dithering, and similar private framebuffer tricks (blank screens); NVRAM resets and factory profile removal (destructive, need root); model-specific adaptations.
- **Awake:** keeping a closed laptop awake without asking each time (sudoers rules, Power Protect, an installed privileged helper, or undocumented clamshell calls: lasting root that any program running as you could use; lid-closed mode asks for a password each time instead); launch agents; turning Low Power Mode on or off (needs root); a Wi-Fi network name condition (Location access); a DNS-server condition; brand-specific VPN conditions; spawning `caffeinate`; synthetic key presses or clicks of any kind; Insomnia’s lid-close extras (freezing apps, muting, writing other apps’ settings, hotspot failover, typing into terminals, relaunching browsers); macOS notifications (Snaptic uses its own notices); custom menu bar images.
- **Dock Previews:** media and calendar widgets; window previews in the macOS ⌘⇥ switcher; window snapping; Dock clicks and gestures that would need Snaptic to take over the Dock or post input (⌘-right-click to quit, Shift-click for a new window, scrolling on Dock icons or title bars, locking the Dock); an active-app indicator; click or modifier-click to preview; hover actions; quitting an app when its last window closes; opening a new window for an app with none; folder previews; “Only this display” and “Only this Space” filters; importing DockDoor’s settings; Liquid Glass styling.
- **Everywhere:** a `snaptic://` URL scheme (any web page could fire it), an HTTP server or distributed-notification commands (unauthenticated), telemetry, analytics, crash upload, licensing, and any network connection other than the update checks you allow.

## How it works

| Path | Responsibility |
|---|---|
| `Sources/SnapticKit/` | Pure logic with unit tests that also run on Linux: the feature graphs, configuration and migrations, safety invariants, DDC and EDID parsing, the command-line protocol, Awake’s sessions, guards, rules, clock, and command grammar, Hidden Icons’ layout, engine, and command logic, Dock Previews’ hover, layout, key, click, and command rules, the window catalog, capture, and privacy rules both window modules share, the private-API crash guard, and the control tables that map every 0.2 setting to its 0.3 home. |
| `Sources/SnapticShims/` | Small Objective-C wrappers for private display, menu bar, and window server APIs, each checked before use. |
| `Sources/Snaptic/Core/` | The host: modules, menus, permissions, onboarding, Safe Mode, the command-line server and client, helper spawning, and the General, Menu Bar, Permissions, and About pages. |
| `Sources/Snaptic/SettingsUI/` | The shared Settings components (rows, sliders with value fields, sheets, search). |
| `Sources/Snaptic/Switcher/` | The window switcher (event tap, window list, thumbnails, switcher UI), using the window services it shares with Dock Previews. |
| `Sources/Snaptic/Windows/` | The window services the switcher and Dock Previews share: reading windows, thumbnails and their cache, and window actions. |
| `Sources/Snaptic/Dock/` | The Dock Previews module: reading the Dock, the preview panel, its keys, Dock click actions, the command-line verbs, its menu section, and its pages. |
| `Sources/Snaptic/Displays/` | The Displays module: services, one controller per feature group, the safety helper, transactions and journals, settings pages. |
| `Sources/Snaptic/Awake/` | The Awake module: the assertion, sessions, guards, rules, activity, Drive Alive, history, the command-line verbs, the condition sources, its menu, and its pages. |
| `Sources/Snaptic/Icons/` | The Hidden Icons module: the two engines (macOS 27 and 14–26), the arrow and dividers, the icon inventory and hidden-icon list, the command-line verbs, its menu section, and its pages. |
| `site/` | The project website at [snaptic.dev](https://snaptic.dev), deployed by Vercel on every push to `main`. |
| `Sources/Snaptic/Core/UpdaterController.swift` | The only file that uses Sparkle; in a build without Sparkle it’s never reached. |
| `docs/design/` | The 0.2, 0.3, 0.3.1, 0.4, and 0.5 plans, their release notes, and platform research. |

### How Awake keeps your Mac awake

- **One named IOKit power assertion.** Awake holds at most one sleep assertion at a time, created with `IOPMAssertionCreateWithProperties` and named “Snaptic: keeping your Mac awake”: `PreventUserIdleDisplaySleep` when the display stays on, `PreventUserIdleSystemSleep` when it may sleep. Changing the type, details, or end creates the new assertion first and then releases the old one, so there’s never a gap.
- **Backstops.** A session with an end also gets a timeout with `TimeoutActionRelease`, so macOS releases the assertion even if Snaptic were stuck; Snaptic ends sessions itself on its own continuous clock (which counts sleep and ignores clock changes).
- **No root for sessions, nothing left behind.** Sessions use no `pmset`, no `caffeinate` process, no helper, no launch agent, and no sudoers rule. macOS releases a process’s assertions when it exits, so a crash can’t leave your Mac unable to sleep.
- **Lid-closed mode** is the one exception. After you enter an administrator password, a short root shell script (in `LidWatchdog.swift`, started through `osascript`) sets `pmset -a disablesleep 1` and stays as a watchdog: every 5 seconds it checks Snaptic’s process, a heartbeat file Snaptic touches, the battery, the heat, and its 24-hour limit, and its exit always sets `disablesleep 0` again, then puts a Mac with a closed lid to sleep (unless the Mac is shutting down). Snaptic writes a journal before sleep is turned off, so a restart or power loss in between is caught at the next launch (see [If sleep stays off](#if-sleep-stays-off)).
- **Drive Alive** adds a separate `PreventDiskIdle` assertion while it writes; **Appear active** uses `IOPMAssertionDeclareUserActivity`; **pointer movement** posts mouse-moved events from a private event source (the only code in Snaptic that posts mouse events).
- **Rules** read system state with public APIs: `NSWorkspace` notifications, CoreGraphics display callbacks, IOKit power-source notifications and USB matching, CoreAudio device properties, `SCDynamicStore`, `sysctl` routing and interface counters, `host_statistics`, `proc_pid_rusage`, and IORegistry disk counters.
- **Holds** watch the client process with a kqueue `EVFILT_PROC` source and identify it through the command-line socket; they never signal, spawn, or wrap a command.

### Undocumented APIs

Snaptic uses private macOS functions where no public one exists. Every one is looked up at runtime (never linked), checked for the expected signature, behind a kill switch, and fails safe: if Apple removes or changes one, the feature that needs it becomes unavailable instead of crashing (for Hidden Icons, your icons are shown). This also means Snaptic can’t be sold through the Mac App Store.

- **Switcher and Dock Previews:** `_AXUIElementGetWindow`, `_SLPSSetFrontProcessWithOptions` and `SLPSPostEventRecordTo`, `SLSMainConnectionID` and `SLSCopySpacesForWindows` (or `CGSMainConnectionID` and `CGSCopySpacesForWindows`), `SLSSetSymbolicHotKeyEnabled` and `SLSIsSymbolicHotKeyEnabled` (or their `CGS` names), `CGSHWCaptureWindowList` for thumbnails of minimized windows and windows on other Spaces (only on macOS versions it has been checked on), `KBGetLayoutType` and `LMGetKbdType` for the keyboard layout, and the deprecated `GetProcessForPID`. If one of them makes Snaptic crash, Snaptic stops using it on that macOS version (see [When a window feature stops](#when-a-window-feature-stops)). The focusing technique follows public reverse-engineering documented by [yabai](https://github.com/koekeishiya/yabai) (MIT).
- **Displays:** DisplayServices (Apple brightness, auto-brightness), CoreBrightness (Night Shift), MonitorPanel (rotation, underscan, HDR, Apple presets), CoreGraphics `CGS…` calls (hidden modes, disconnect, HDR state), `CGVirtualDisplay` (virtual displays), `IOAVService` (DDC on Apple silicon), CoreDisplay (display info), the OSD framework, and libsystem’s process-responsibility calls for helpers.
- **Hidden Icons:** on macOS 27, MenuBarClientCore’s `MBAssessmentModeConfiguration` and `MBAssessmentModeAssertion` (the mechanism macOS uses for exam sessions), through a small wrapper in `SnapticShims` that checks the classes and method encodings first; on macOS 14–26, only public `NSStatusItem` lengths.
- **Awake:** no private functions. It reads undocumented keys with public calls: `CGSSessionScreenIsLocked` from `CGSessionCopyCurrentDictionary`, to know whether the screen is locked; the `SleepDisabled` power setting (`SystemPowerSettings` in the `com.apple.PowerManagement` preferences, through `CFPreferencesCopyValue`) and the kernel’s `SleepDisabled` and `AppleClamshellState` properties on `IOPMrootDomain` (through IOKit), to tell you when sleep is turned off and whether the lid is closed. It changes `SleepDisabled` only in lid-closed mode, and only through `pmset` after you enter an administrator password.

## License

MIT. See [LICENSE](../LICENSE) and [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
