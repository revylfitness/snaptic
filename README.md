# Snaptic

A free, open-source menu bar toolkit for macOS: a Windows-style **window switcher**, a set of **display utilities**, and **Awake**, which keeps your Mac awake when you want it to. Turn on only the parts you want; everything else stays off and costs nothing.

**Website:** [snaptic.dev](https://snaptic.dev)

Snaptic is MIT-licensed and written from scratch in Swift by revyl fitness technology, Inc. It isn’t affiliated with or derived from AltTab, BetterDisplay, MonitorControl, Lunar, Amphetamine, or Insomnia; it’s an independent take on the same ideas, with everything included and nothing behind a paywall. Third-party credits are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). What changed is in the release notes for [0.3.1](docs/design/0.3.1/RELEASE-NOTES-0.3.1.md) and [0.3](docs/design/0.3/RELEASE-NOTES-0.3.md).

- [Modules](#modules) · [Settings](#settings) · [Window Switcher](#window-switcher) · [Displays](#displays) · [Awake](#awake) · [Safety](#safety)
- [Permissions](#permissions) · [Command line](#command-line) · [Hidden kill switches](#hidden-kill-switches) · [Install and build](#install-and-build) · [Updates](#updates)
- [Privacy and security](#privacy-and-security) · [Upgrading and downgrading](#upgrading-and-downgrading) · [Troubleshooting](#troubleshooting) · [Known limitations](#known-limitations) · [Not included](#not-included) · [How it works](#how-it-works)

## Modules

| Module | What it does |
|---|---|
| **Window Switcher** | Hold **⌥ Option**, tap **Tab**, and pick any window, not just any app. |
| **Displays** | Brightness and volume for external displays, resolutions and HiDPI, color, arrangement, virtual displays, Picture in Picture, and more. |
| **Awake** | Keeps your Mac awake for a while, until a time, while an app runs, until downloads and tasks finish, or automatically when conditions you choose are met. A free replacement for Amphetamine and Insomnia that needs no administrator password, except for opt-in lid-closed mode, which asks for one each time. |

Each module can be turned on or off on its own: in **Settings › General › Choose what Snaptic does**, or with the switch at the top of the module’s own page (“Use Window Switcher”, “Use Displays”, “Use Awake”). A module that is off runs nothing: no event taps, timers, observers, IOKit handles, power assertions, private-API calls, helper processes, or permission prompts. Inside Displays and Awake, each feature has its own switch where the feature is used, and anything that’s off costs nothing either.

- **First launch:** onboarding asks which modules you want, then asks only for the permissions those need, and whether Snaptic should keep itself up to date (**Check Automatically** or **Not Now**). It picks up where it left off if macOS makes Snaptic relaunch.
- **Upgrading from 0.3.0 or earlier:** download 0.3.1 by hand one last time; from then on Snaptic can update itself. Because 0.3.1 is the first release signed by its developer, macOS asks you to allow Accessibility and Screen Recording again once, and a “Welcome to Snaptic 0.3.1” card in General walks you through it (see [Upgrading and downgrading](#upgrading-and-downgrading)).
- **Upgrading from 0.2:** Window Switcher and Displays stay as they were. Awake starts off, with a “New: Awake” card in General, unless you used Displays’ display sleep prevention in 0.2; then Awake is on and keeps doing that job (see [Upgrading and downgrading](#upgrading-and-downgrading)). As for 0.3.0, it’s one last manual download, and the “Welcome to Snaptic 0.3.1” card shows too.
- **Upgrading from 0.1:** the switcher stays on; Displays and Awake start off, each with its own card. As for 0.3.0, it’s one last manual download, and the “Welcome to Snaptic 0.3.1” card shows too.

## Settings

Settings has seven pages in its sidebar: [General](#general), [Menu Bar](#menu-bar), [Window Switcher](#window-switcher), [Displays](#displays) (with its own sub-pages), [Awake](#awake), [Permissions](#permissions), and About. The search field at the top of the sidebar finds any setting, including the ones in **Advanced…** sheets, and highlights it on its page. Every page that has a (?) button links to its section of this README.

Most pages show the settings people change often and keep the rest in an **Advanced…** sheet at the bottom. Every slider has a value field you can type into, and a reset button when it has a default. **Restore Defaults…** on a page or sheet resets only that page’s settings.

## General

- **Choose what Snaptic does:** a switch per module, with a line on what each does.
- **Open at login.** If macOS needs you to allow Snaptic in Login Items, the page says so and opens the right pane.
- **Command-line control:** lets scripts and other apps control Snaptic with the `snaptic` command (off by default). **Copy Install Command** copies the Terminal command that installs it; see [Command line](#command-line).
- **Backup:** **Export Settings…** and **Import Settings…** (see [Privacy and security](#privacy-and-security) for what an export leaves out).
- **Advanced…:** “Commands can skip confirmation” (a display change sent with `--yes` applies without asking first), the exit codes the `snaptic` command uses, **Restart in Safe Mode…**, and **Reset All Settings…**.
- New-module cards (“New: Awake”, “New: Displays”) and the “Welcome to Snaptic 0.3.1” card appear here once after an upgrade.

## Menu Bar

Everything about Snaptic’s menu bar icons lives on this page.

- **Where each module appears:** one pop-up per module with the same choices Control Center uses: **Always Show in Menu Bar**, **Show When Active**, **Show in Snaptic Menu**, and **Don’t Show**. Window Switcher has no “Show When Active”. For Displays it means “while an external display is connected”; for Awake, “while your Mac is being kept awake” (Awake’s default).
- **Icons:** a choice of icon for each module that has its own item and for the Snaptic icon.
- **Awake time:** **Don’t Show** (default), **Time Remaining**, or **End Time** next to Awake’s icon, in your system’s 12- or 24-hour setting, with seconds only in the last minute.
- **Displays menu:** **Standard** or **Compact** style (one slider per display), “Scroll over a slider to adjust it”, and **Customize Displays Menu…**, where every optional menu item can be shown, moved into a submenu, or hidden.
- **Restore Menu Bar Defaults…** resets only this page.

**Tabs in the Snaptic menu.** The Snaptic icon appears when a module is set to Show in Snaptic Menu. With two or more, the Snaptic menu shows a tab for each, in the order Window Switcher, Displays, Awake (all three out of the box), and only the selected module’s items below the tabs. With one module the menu has no tabs and shows that module’s section as before.

- **Switching:** click a tab, or, while the menu is open, ⌘1–⌘3 choose a tab (⌘1–⌘2 with two tabs). A keyboard choice closes the menu, and the next open shows that tab. Each tab’s tooltip names its shortcut.
- **Remembered:** the menu opens on the tab you last chose, also after a relaunch. If that module isn’t in the menu right now, the first tab shows, and your choice comes back when the module does. No reset clears it.
- **Nothing hidden:** Safe Mode and “Sleep Is Turned Off” rows stay above the tabs, whichever tab is showing. A tab whose module needs attention (Displays is degraded, paused after Restore All Displays, or unprotected, or Window Switcher is missing Accessibility; “Paused while … runs” doesn’t count) shows a small exclamation mark, and VoiceOver adds “needs attention”. While Awake keeps your Mac awake, VoiceOver reads its tab as “Awake, on”.
- **Awake’s tab** has the full Awake menu rows except Awake Settings…. The compact Awake section is used only when Awake is the only module in the Snaptic menu.
- **Keyboard and VoiceOver:** the tabs are one segmented control, so VoiceOver users reach it and pick a segment with VO-Space. While VoiceOver, Switch Control, or Full Keyboard Access is on, the menu also lists **Show Window Switcher Tab**, **Show Displays Tab**, and **Show Awake Tab** above Snaptic Settings…, with the same shortcuts. Type-select reaches only the visible tab.
- **Size:** the menu is as wide as its widest tab from the start, so a tab never moves under the pointer; its height changes when you switch.
- The footer is unchanged: More Display Features… (while Displays is off), Recent Notices, an update row when one is waiting (see [Updates](#updates)), Snaptic Settings… (⌘,), and Quit Snaptic (⌘Q).

A running Awake session is never invisible: whenever Awake keeps your Mac awake, the Snaptic icon shows its active look, and if no Snaptic icon is shown, Awake’s own icon appears for the session. With every icon hidden, open Snaptic again from Finder or Spotlight to get to Settings; shortcuts keep working. macOS can also hide menu bar icons (System Settings › Menu Bar, and the overflow on notched Macs), so every menu action is also available in Settings or as a shortcut.

## Window Switcher

| | |
|---|---|
| **Every window** | Each window gets its own tile: several windows of one app, minimized and hidden windows, and windows on other Spaces, each with a badge. Optionally, apps with no open windows too. |
| **Recently used order** | The window you’re in comes first, then windows in the order you last used them, so a quick ⌥⇥ goes back to the previous window. |
| **Thumbnails** | Previews of each window, captured with ScreenCaptureKit each time the switcher opens. |
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

The Window Switcher page has the main shortcut, **More Shortcuts…**, “Switch when you release the keys”, what to show, the style, the preview, thumbnail size, minimized and hidden windows, and which Spaces and screens to list. Its **Advanced…** sheet has the rest: thumbnails on or off, where the switcher opens, apps without windows, one window per app, search, the window action keys, hover buttons, selecting on hover, ⌘⇥ takeover, apps that keep the shortcut, hidden apps, and apps that are never captured.

“Key above Tab” is detected for both US (ANSI) and European (ISO) keyboards. You can add ⌘⇥ to replace the built-in macOS switcher. Snaptic gives it back whenever it quits, whenever it can’t see key presses, and on the next launch if Snaptic ever crashed. If you had already turned that shortcut off yourself, Snaptic leaves it off.

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

Turn it on with **Use Awake** at the top of the Awake page. The page has a status row (**Keep Awake ▾** while nothing runs, **Options ▾** and **Turn Off** while a session or rule runs, **Keep Awake ▾** and **Turn Off** while only command-line holds run, and **Pause Rules ▾** or **Resume** whenever you have rules), Sessions, End sessions automatically, Start automatically, Keyboard, Drives ›, History ›, and **Advanced…**.

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

By default Awake’s icon appears only while your Mac is being kept awake (Show When Active), next to the Snaptic icon; change that on the [Menu Bar](#menu-bar) page, along with the icon (cup, eye, or light bulb, filled while active) and the time shown next to it. The Awake menu, Awake’s tab in the Snaptic menu, and the compact Awake section (when Awake is the only module in the Snaptic menu) have the same rows: the **Keep Awake** switch with what’s keeping your Mac awake (“Held by Terminal (2)” for command-line holds), **Turn Off Keep Awake**, the Add Time items, **Keep Display On**, **End Command-Line Holds**, **Start Session ›**, **While an App Is Running ›**, and **Rules ›**. With lid-closed mode turned on in Advanced, they also have **Keep Awake with the Lid Closed** (see [Keeping awake with the lid closed](#keeping-awake-with-the-lid-closed)). On a laptop running on battery or without an external display, the menu reminds you that closing the lid puts your Mac to sleep, unless lid-closed mode is on.

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

1. Turn on **Awake › Advanced… › Lid closed › Keep awake with the lid closed**.
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

- **What runs as root.** Only while lid-closed mode is on, or when you choose Turn Sleep Back On…, Snaptic runs a short shell script as root. Its full text is in [`Sources/SnapticKit/LidWatchdog.swift`](Sources/SnapticKit/LidWatchdog.swift). It changes only `SleepDisabled` (`pmset -a disablesleep 1`, then `0`), and may run `pmset sleepnow` when sleep is back on, the lid is closed, and your Mac isn’t shutting down. It turns sleep back on when the session ends, when Snaptic quits or stops responding (it checks every 5 seconds), when the battery reaches the limit, when your Mac gets hot, after 24 hours, or if the script itself fails. It never writes, deletes, or reads the contents of your files; it only checks two files Snaptic keeps in your temporary folder.
- **How it starts.** `/usr/bin/osascript` asks macOS for an administrator password, then starts the script, which keeps running as a watchdog after the dialog closes. It gets a minimal environment and calls every program by its full path.
- **The dialog names osascript, not Snaptic.** Any app can show this dialog with any text. Only enter your password right after you choose **Keep Awake with the Lid Closed**, **Turn Sleep Back On…**, or **Install and Relaunch** (in Snaptic’s About page or in Sparkle’s update window).
- **If your account can change Snaptic** (the default after you drag it to Applications), that advice isn’t enough: a program running as you could change Snaptic so that its own prompt runs something else as root. Snaptic says so under the setting. To close that gap, install Snaptic owned by root: build with `INSTALL=1`, or for a downloaded copy run `sudo chown -R root:wheel /Applications/Snaptic.app`. (Each update then asks for an administrator password; see [Updates](#updates).) Snaptic warns rather than refuses, because the same program could show the identical dialog without touching Snaptic, and refusing would remove the feature from the default install. A translocated copy is refused.
- **What a program running as you can do:** turn sleep back on (by creating the watchdog’s stop file or deleting its heartbeat file), or, while Snaptic is hung, keep lid-closed mode going, but only while Snaptic’s process is still running and only until the 24-hour limit, the battery limit, or heat ends it, which the watchdog enforces on its own. It can’t turn lid-closed mode on without you typing a password into a dialog.
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

## Safety

Display changes can leave you without a usable screen. Snaptic is built so that never sticks.

- **“Keep this change?”** Risky changes (new resolutions, mirroring, disconnecting, rotation, HDR, first-time Smart HiDPI) show a panel on every visible display with a countdown, 15 seconds by default (10–60 in Displays › Advanced… › Confirm display changes). Return or ⌘K keeps; Esc, Revert, or no answer puts things back. Keys work after one second, so a stray keypress can’t confirm. Dimmed displays are raised to at least 30% while the panel shows.
- **A separate safety helper.** Before a risky change, Snaptic arms a small helper process. If Snaptic hangs, crashes, or is killed, the helper reverts the change on its own, re-enables displays Snaptic turned off, and restores color. If the helper isn’t running, risky changes are refused; anything already applied is badged “Unprotected — restart Snaptic”.
- **Never the last screen.** Changes that would leave no visible display are refused. Dimming to black, disconnecting, and mirroring always keep at least one display you can see.
- **Restore All Displays: ⌃⌥⌘⎋** (⌃⌥⌘⇧⎋ if the first is taken; also in Display Tools and as `snaptic panic`). It undoes resolution changes from the last minute, reconnects displays Snaptic turned off, removes dimming and overlays, resets color tables, stops virtual displays and streams, and pauses automation (layouts, protection, hooks, re-creation) until you choose Resume. Rotation and HDR aren’t touched; they always go through the confirm panel. The shortcut can’t be turned off while a display is disconnected, mirrored to a virtual display, or dimmed to black. Awake isn’t affected: keeping your Mac awake isn’t a display hazard.
- **Safe Mode: hold ⇧ while Snaptic starts** (or start it with `--safe-mode`, or choose General › Advanced… › Restart in Safe Mode…). It also starts automatically after two launches in a row that ended within a minute. Safe Mode skips brightness and color restore, virtual displays and Smart HiDPI, protection, layouts, remembered resolutions, hooks, automatic DDC writes, XDR, and reconnection planning. In Awake it pauses rules, appear active, pointer movement, and Drive Alive; sessions you start, holds, and guards still work. It still undoes unfinished display changes from the last run, and the switcher and your shortcuts keep working. **Leave Safe Mode…** relaunches normally.
- **Journals.** Before a risky change Snaptic writes what it would take to undo it. If the Mac or Snaptic goes down mid-change, the next launch puts things back (and says so).
- **Awake can’t drain your battery or cook your Mac:** the 5% floor and the heat guard have no setting and no kill switch (see [Guards](#guards)). Lid-closed mode adds its own battery limit (at least 10%), heat cutoff, and 24-hour limit, enforced both by Snaptic and by its root watchdog, and turns sleep back on if Snaptic stops responding (see [Keeping awake with the lid closed](#keeping-awake-with-the-lid-closed)).

## Permissions

Snaptic asks only for what the features you turned on need, and only when you turn them on. The Permissions page shows each one’s status, what needs it, and who signed the running copy (“ad-hoc” or “Developer ID …”).

| Permission | Asked for when | Used for |
|---|---|---|
| **Accessibility** (called **Device Control and Data Access** on macOS 27) | Window Switcher is on; Brightness keys or Volume keys; Gather windows on first use; Awake’s pointer movement | Seeing the switcher shortcut and media keys, listing and focusing windows, and moving the pointer 1 point. |
| **Screen Recording** (Screen & System Audio Recording) | Switcher thumbnails or preview; Picture in Picture | Thumbnails, the full-size preview, titles of windows on other Spaces, and Picture in Picture captures. |
| **Removable Volumes** (Files & Folders) | The first time Drive Alive writes to a drive | Rewriting `.snaptic-keepalive` on the drives you chose. |

Accessibility and Screen Recording are in **System Settings › Privacy & Security**. The permission window shows the exact app path, with “Show Snaptic in Finder” so you add *this* copy. On macOS 27 a grant often takes effect only after a relaunch; Snaptic offers **Relaunch Snaptic**. Without Accessibility the switcher stays idle and Awake only appears active instead of moving the pointer. Without Screen Recording the switcher shows app icons and only windows on the current Space. macOS Sequoia and later re-confirm Screen Recording about once a month; that prompt comes from macOS.

Most Displays features need no permission at all. Awake needs none for sessions, rules, guards, holds, appear active, history, or the menu bar: its conditions read only system state that macOS gives any app without asking (no Location, Bluetooth, Microphone, Input Monitoring, Local Network, or Downloads folder access). Lid-closed mode needs no permission either; instead it asks for an administrator password each time you turn it on.

Release builds are signed with a Developer ID, so permissions you grant survive updates. Going from 0.3.0 (ad hoc) to 0.3.1 (Developer ID) resets Accessibility and Screen Recording once: remove the old Snaptic with − in each list, then turn on the new one.

## Command line

Off by default. Turn it on in **Settings › General › Command-line control**.

**Install.** **Copy Install Command** copies the command that links `snaptic` into `/usr/local/bin` (it asks for your password):

```bash
sudo ln -sf '/Applications/Snaptic.app/Contents/MacOS/Snaptic' /usr/local/bin/snaptic
```

Without installing: `/Applications/Snaptic.app/Contents/MacOS/Snaptic cli help`.

**Usage.** `snaptic [--json] [--yes] <command> [arguments]`. `snaptic help` lists the commands available right now (a command appears only while its feature is on); `snaptic help <command>` narrows it, for example `snaptic help awake`. `--` ends options, so `-10` is read as a value.

- `--json`: machine-readable output. Lists and `get`, `set`, `ddc`, `mode`, `layout`, `virtual`, `pip list`, and `awake status` print JSON arrays or objects; any other command prints `{"ok": true}` (with `"output"` when it has text). Errors, including the client’s own (an unknown option, Snaptic not running), print `{"exitCode": …, "error": …}`.
- `--yes`: skips the “Keep this change?” panel, but only if you also turned on “Commands can skip confirmation” (General › Advanced…). The change is then kept right after the displays settle; the safety helper and the undo journal protect it exactly as they protect a confirmed change. Otherwise the panel shows and the command waits for your answer.
- Commands that change displays (`mode …`, `match-ui`, `mirror`, `rotate`, `disconnect`, `layout apply`) wait for the outcome: exit 0 when the change was applied or kept, 6 when it was declined in the panel or timed out.
- Values can be absolute (`60`), relative (`+10`, `-5`), or percentages (`50%`, `+10%`).

**Choosing a display.** `main`, `mouse` (or `pointer`), `focus`, `all`; a number from `snaptic list` (the same numbers Identify shows); `id:N` (a CoreGraphics display id); a 32-character display key; or a name (an exact match first, then a unique prefix, case-insensitive). A prefix that matches several displays exits with 2 and lists them. Commands that take an optional display default to the main one; `get …` defaults to all.

### Snaptic and Displays commands

| Command | Feature | Notes |
|---|---|---|
| `version`, `modules`, `safe-mode` | — | Always available |
| `module disable <windowSwitcher\|displays\|awake>` | — | Off only |
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

**`prevent-sleep` is retired.** Display sleep prevention moved to Awake (your 0.2 setting became a rule; see [Upgrading and downgrading](#upgrading-and-downgrading)). The old verb answers “Moved to Awake: use “snaptic awake …”.” with exit code 2 whatever is turned on, and isn’t listed in help. It will be removed in 0.4. Use `snaptic awake start`, `snaptic awake hold`, or a rule instead.

**Never from the command line:** turning on anything off-only, and changing hooks, actions, command-line settings, disconnect, auto-disconnect, dim to black, DDC unlocks, “allow without asking” choices, layout trust, or any Awake setting (rules, sessions in the menu, guards, Drive Alive, appear active, pointer movement), and turning on lid-closed mode. Accessibility-using actions (Gather windows, pointer movement) are never command-line actions.

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

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (also when a hold ends normally) |
| 2 | Usage error, unknown command, a retired command such as `prevent-sleep`, or a name that matches several displays or items |
| 3 | Nothing matched (display, action, layout, configuration, Awake session in the menu) |
| 4 | Refused by policy: off-only, a protected setting, the safety rules, or an Awake refusal (a guard, a session you started in Snaptic is running, 8 holds, a session without an end, extending a lid-closed session, a caller Snaptic couldn’t identify) |
| 5 | Unavailable: Snaptic isn’t running or quit, command-line control is off, the feature is off or unsupported, or too many Awake requests |
| 6 | Cancelled or timed out (the confirmation was declined or expired; the client waits up to 90 s: the longest panel plus 30 s) |

**Recipes.** A Stream Deck “Run shell” or Raycast script command can call `snaptic set brightness +10 mouse`, `snaptic input "HDMI 1" 2`, `snaptic layout apply Office`, or `snaptic awake start 2h`.

## Hidden kill switches

Kill switches turn a module or a feature off for this Mac, whatever Settings says. They are Boolean keys in Snaptic’s own preferences (`app.snaptic.Snaptic`), they only ever turn things off, and pages show what they turned off as “Turned off for this Mac by an administrator or a Terminal command.” with the command that undoes it. Quit and reopen Snaptic to apply a change. The Diagnostics Report lists the Displays and Awake feature switches that are set; a module turned off this way says so on its page, and a turned-off private API shows as unavailable.

```bash
defaults write app.snaptic.Snaptic Modules.disable.awake -bool true                # a whole module
defaults write app.snaptic.Snaptic Awake.disable.pointerNudge -bool true           # one Awake feature
defaults write app.snaptic.Snaptic Displays.disable.xdr -bool true                 # one Displays feature
defaults write app.snaptic.Snaptic Displays.disable.symbol.MPDisplay -bool true    # one private API
defaults delete app.snaptic.Snaptic Awake.disable.pointerNudge                     # undo
```

- **Modules:** `Modules.disable.windowSwitcher`, `Modules.disable.displays`, `Modules.disable.awake`. A module turned off this way never starts, its page shows why with its switch disabled, and Awake also releases its assertion and doesn’t resume a session at the next launch.
- **Awake features:** `presets` (sessions in the menu), `triggers` (rules), `activity` (appear active, and so pointer movement), `pointerNudge` (pointer movement), `driveAlive`, `history`, `shortcuts`, `commandLine` (the `snaptic awake` commands), and `lidClosed` (lid-closed mode). `sessions`, `batteryGuard`, `thermalGuard`, and `indicator` are ignored, so the guards and a visible indicator always stay; use `Modules.disable.awake` to turn Awake off entirely.
- **Displays features** (ids as in `snaptic features`): `resolution`, `hiddenModes`, `scaleMatch`, `brightness`, `brightnessApple`, `brightnessDDC`, `brightnessGamma`, `brightnessOverlay`, `brightnessRestore`, `dimToBlack`, `dimOnLock`, `nits`, `xdr`, `sync`, `autoBrightness`, `color`, `colorProfiles`, `nightShift`, `applePresets`, `ddcControls`, `ddcInput`, `ddcPower`, `ddcCustom`, `brightnessKeys`, `volumeKeys`, `shortcuts`, `osd`, `osdBroadcast`, `mainDisplay`, `arrangement`, `mirroring`, `rotation`, `underscan`, `hdrToggle`, `disconnect`, `autoDisconnectBuiltin`, `protection`, `layouts`, `virtualScreens`, `smartHiDPI`, `hdrVirtual`, `pip`, `pipFilters`, `menuBarOverlays`, `hooks`, and `customActions`. `Displays.disable.symbol.<name>` turns off one private API.

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

**Coming from 0.3.0 or earlier?** Those versions can’t update themselves, so download 0.3.1 one last time and replace the old copy in Applications. After that, Snaptic can keep itself up to date (see [Updates](#updates)), and macOS asks you to allow Accessibility and Screen Recording once more (see [Upgrading and downgrading](#upgrading-and-downgrading)).

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

In every case, a note goes in this README and on the Releases page.

## Privacy and security

**Network: only for updates, and only if you allow it.** If you allow it, Snaptic contacts GitHub (github.com and its download host) once a day, and when you choose **Check for Updates…**. It downloads the signed update feed, and an update when you install one. GitHub sees your IP address, a Sparkle User-Agent with the app version, and your macOS version; Sparkle’s system profiling is off. The feed and every update are signed with Snaptic’s update key; a download signed with Snaptic’s Developer ID is accepted only so that a lost key can be replaced (see [Updates](#updates)). Nothing else connects: no telemetry, no analytics, no crash upload, and a lint check still rejects networking APIs in Snaptic’s own code.

**What never leaves the process.** Window pixels, window titles, app names, and key presses. The command line, hooks, diagnostics, and the event log never carry them. Diagnostics mask serial numbers; display keys are salted per Mac and the salt is never exported.

**What leaves on purpose.**
- *Brightness broadcast* (opt-in) posts a system-wide notification `app.snaptic.osd` with only the kind (brightness, volume, …), the value, and the maximum, at most 10 per second, and nothing while the screen is locked.
- *Hooks and custom actions* (opt-in) run programs you chose, with a minimal environment (`SNAPTIC_EVENT`, `SNAPTIC_DISPLAY_NAME`, `SNAPTIC_DISPLAY_KEY`), without Snaptic’s permissions, stopped after 30 seconds. Programs must be absolute paths owned by you or root and not writable by others. Never in Safe Mode or while automation is paused.
- *Awake’s power assertion* is visible to every app (`pmset -g assertions`), as all assertions are. Its name is always “Snaptic: keeping your Mac awake” and its details only say `manual` or `automatic`: never an app, rule, or condition.

**On disk.** Settings (in Snaptic’s preferences), and under `~/Library/Application Support/Snaptic/` (0700): the single-instance lock, the command-line socket, undo journals for display changes, copies of imported LUTs, and, while lid-closed mode is on or its recovery is pending, a small journal (`awake/lid.json`, 0600). Lid-closed mode also keeps two empty files in a private folder (0700) of your temporary folder for its watchdog. The remembered Snaptic menu tab is a plain preference. Release builds add Sparkle’s update cache, `~/Library/Caches/app.snaptic.Snaptic/org.sparkle-project.Sparkle`, and Sparkle’s `SU…` keys in Snaptic’s preferences; **Reset All Settings…** clears those keys. Drive Alive’s only trace is the 8-byte `.snaptic-keepalive` file on drives you turned on. Backup export leaves out hooks, actions, command-line settings, the salts, DDC unlocks, “allow without asking” choices, layout trust, sensitive switches (disconnect, auto-disconnect, dim to black), Awake’s history, Drive Alive drives, pointer movement, lid-closed mode (import keeps this Mac’s choice), the update settings, the remembered menu tab, and the apps you used recently; Awake rules are included only if you tick “Include automatic-session rules”. Import strips the same things even if present, and can only make Awake’s guards stricter.

**Command line.** Only your user account can connect, through a private socket (directory 0700, socket 0600); Snaptic never listens on the network. Requests are size-, rate-, and time-limited. See [Command line](#command-line) for what it can never change.

**Helpers and other processes.** The safety helper and virtual-display hosts are copies of Snaptic’s own executable, started with an empty environment and their own process responsibility, so they hold none of Snaptic’s permissions. Each side checks the other’s code signature. Only for lid-closed mode, Snaptic also starts Apple’s `/usr/bin/osascript` (which asks for your password and starts the root watchdog; see [Your password and what runs as root](#your-password-and-what-runs-as-root)) and `/usr/bin/pmset displaysleepnow` as you; before either runs, Snaptic checks that it’s signed by Apple, and it starts with a minimal environment. Release builds also contain Sparkle’s `Autoupdate` and `Updater.app`, which run only to install an update, and Sparkle’s installer asks for an administrator password when the copy is owned by root.

**Picture in Picture.** Display captures never include Snaptic itself, Notification Center, or apps on the protected list; browser windows marked private (Firefox, Edge, Chrome’s Incognito title) and untitled browser windows are left out. Locking or sleeping the Mac stops captures and clears their last frame. Snaptic never starts a capture by itself.

**Overlays vs password prompts.** While a password or authentication window is on screen, Snaptic orders out full-screen dimming overlays and raises dim-to-black to at least 30%. This is best effort.

**Window Switcher.**
- **Keys.** Snaptic’s keyboard tap reacts only to its own shortcuts. While the switcher is open it also reads the keys you press there (to search and for the action keys); search text is cleared when the switcher closes. Password fields use macOS Secure Event Input, which Snaptic can’t see; while it’s active, or whenever Snaptic’s tap is off, ⌘⇥ goes back to macOS. If Snaptic ever hangs, a background guard hands ⌘⇥ back within about two seconds, and quitting Snaptic by any normal means or signal restores it.
- **Never stuck.** The switcher closes if you click elsewhere, switch apps, or change Spaces, and switches as soon as the modifier key is up even if Snaptic missed the release. If it stays open after release (searching, or “switch on release” turned off), it closes after 30 seconds without input. If the window list takes more than 2 seconds to load, it gives up.
- **Slow or hostile apps.** Accessibility requests to other apps time out after 0.15 seconds, each app gets at most half a second and 100 windows, and listing gives up on stragglers after 1.2 seconds. Window titles and app names from other apps are length-limited and stripped of control and text-direction characters.
- **Thumbnails** are kept in memory only (at most 40, for at most 5 minutes), never captured after the switcher closes, and cleared when the Mac sleeps, locks, or switches user. Snaptic’s panels ask macOS to keep them out of screen sharing and screenshots, though some capture methods may not honor that.
- **Sensitive windows.** Windows of apps on the “never capture” list (by default 1Password, Bitwarden, Apple Passwords, Tor Browser, and others) are never captured and show their app icon and name instead of their title. Safari and Chrome don’t mark private windows, so add them to the list if you don’t want any of their windows captured.
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

**0.3 → 0.3.1.** No setting is lost, and nothing about your modules, sessions, or rules changes. Coming from 0.2 or 0.1, the steps below apply too, after those versions’ own upgrade steps (further down).

- **One last manual download.** 0.3.0 and earlier have no updater, so download 0.3.1 from the [latest release](https://github.com/revylfitness/snaptic/releases/latest) and replace the copy in Applications. From 0.3.1 on, Snaptic can update itself.
- **Permissions, once.** 0.3.1 is the first release signed by its developer, so macOS treats it as a new app for Accessibility and Screen Recording. Settings opens on General with a “Welcome to Snaptic 0.3.1” card: “Snaptic is now signed by its developer, so macOS asks you to allow it again once. After this, updates keep your permissions.” For each permission you had granted, it says “Remove the old Snaptic with −, then turn on the new one.” with **Open System Settings…**.
- **Updates:** the card asks whether to keep Snaptic up to date (**Check Automatically** or **Not Now**), and **Done** hides it. It also hides itself once you’ve chosen and the permissions work again.
- **Open at login:** if Snaptic doesn’t open at login after the change of signature, or Login Items lists it twice, turn Open at login off and on again in General.
- **Going back to 0.3.0** works like any older copy: it ignores the remembered menu tab, lid-closed mode, and the update settings, and its ad-hoc signature needs the permissions granted again. Turn lid-closed mode off before you go back.

**0.2 → 0.3.** No setting is lost; every 0.2 setting, button, and menu item has a home in 0.3, and Settings search finds it.

- **Display sleep prevention moved to Awake.** If it was on in 0.2 (Displays on, the feature on, and at least one display set to prevent sleep), 0.3 turns Awake on with a rule “While a display is connected” for those displays (up to 8 per rule), keeping the display on. General shows “Your display sleep setting moved to Awake.”, and the first time the rule applies, a one-time notice says so. If it wasn’t in use, Awake starts off with a “New: Awake” card.
- **Its shortcut** moves to Awake’s **Pause or Resume Rules** if a rule was created and that shortcut isn’t set yet; otherwise it’s removed, and Recent Notices says “Your display sleep shortcut was removed. Set Awake shortcuts in Settings › Awake › Keyboard Shortcuts.”
- **Menu bar placement** (shared, own icon, hidden, and Displays’ “hide when no external display is connected”) becomes the new per-module pop-up on the Menu Bar page.
- **`snaptic prevent-sleep`** is retired; see [Command line](#command-line).
- Each upgrade step runs once and records that it ran, so a later change you make isn’t undone at the next launch.

**0.3 → 0.2 → 0.3.** You can go back to 0.2 and forward again:

- **What 0.2 reads back:** 0.3 keeps writing the 0.2 fields, so 0.2 finds your Window Switcher and Displays settings, the menu bar placement you chose in 0.3 (Awake’s “Show When Active” reads as an own icon), and its display sleep prevention settings and shortcut exactly as they were when you upgraded. 0.2’s own sleep prevention works again while you run 0.2.
- **What 0.2 ignores:** everything about Awake. Its settings, history, and state stay untouched in their own keys.
- **Back on 0.3:** the upgrade steps don’t run again, so a change you made to display sleep prevention while on 0.2 isn’t carried into Awake (adjust the rule yourself). Menu bar placement you changed in 0.2 is read again. Awake continues as you left it.

## Troubleshooting

- **A display went black or the picture is wrong.** Wait 15 seconds without pressing anything; unconfirmed changes revert. Otherwise press **⌃⌥⌘⎋** (or ⌃⌥⌘⇧⎋). If Snaptic won’t start cleanly, hold **⇧** while opening it for Safe Mode.
- **Permission is on but Snaptic still asks.** Remove Snaptic from the list with −, add it again with + (use “Show Snaptic in Finder” to pick the right copy), then relaunch. This is expected once after upgrading from 0.3.0 (see [Upgrading and downgrading](#upgrading-and-downgrading)). After rebuilding an ad-hoc build, run `tccutil reset Accessibility app.snaptic.Snaptic` first.
- **“Restart Snaptic to finish updating” or “Unprotected”.** Snaptic was replaced while running, so its helpers are refused. Quit and reopen it.
- **A display doesn’t respond to brightness or volume.** Many TVs, DisplayLink adapters, some docks, and the HDMI port on some Macs don’t pass DDC; Snaptic dims those in software instead. Hardware Controls shows whether each display answers.
- **A feature shows “Paused while … runs”.** Another display app is running. Quit it, or choose “Run both” in Displays › Advanced… › Other display apps.
- **No menu bar icon.** macOS may hide it in the overflow or in System Settings › Menu Bar. Open Snaptic again from Finder or Spotlight to get Settings, or use the “Show Displays Panel” shortcut if you set one.
- **My Mac still went to sleep during a session.** Choosing Sleep always sleeps a Mac, and so does closing the lid unless lid-closed mode is on or you use closed-display mode; see [Keeping awake with the lid closed](#keeping-awake-with-the-lid-closed). If lid-closed mode was on, the menu says why it ended for 12 hours (“Lid-closed mode ended at …”). Otherwise the menu says why the session ended for 12 hours: a guard (battery, adapter, Low Power Mode, heat), “End sessions when your Mac sleeps”, switching users, or a locked screen (Awake › Advanced…).
- **My Mac doesn’t sleep and Awake is off.** Look at Awake › Advanced… › Other apps keeping your Mac awake, or run `pmset -g assertions`. If it says sleep is turned off for this Mac, see [If sleep stays off](#if-sleep-stays-off) when an earlier lid-closed session left it off, or [Switching from Amphetamine or Insomnia](#switching-from-amphetamine-or-insomnia).
- **The display turns off during a session.** Turn on “Keep the display on” for the session (Keep Display On in the menu). On the lock screen, the display may sleep unless “Keep the display on while locked” is on.
- **`awake hold` ended at once, or kept holding after the work.** See [the parent-shell pitfall](#awake-hold).
- **`snaptic` says it isn’t running, or doesn’t know `awake`.** Turn on Settings › General › Command-line control, and make sure Awake is on. Exit code 5 means Snaptic isn’t running, control is off, the feature is off, or you sent Awake requests faster than once a second.
- **Lid-closed mode won’t turn on.** The notice says why: battery too low (connect power), too hot, a Start Anyway session, Snaptic running from a temporary location (move it to Applications), or sleep still turned off from an earlier session. If the password dialog doesn’t appear, check whether security software blocks `osascript`.
- **No update arrives.** Look at Settings › About › Updates: automatic checks may be off, the copy may be built from source, or an update may be waiting for lid-closed mode or a display change to finish. **Check for Updates…** checks now.
- **Filing an issue.** Copy the report from Displays › Display Information (or `snaptic diagnostics`). It has no window titles, app names, or serial numbers; Awake contributes only counts.

## Known limitations

- **Switcher:** windows on other Spaces show their app icon rather than a thumbnail, say “Other Space” rather than which Space, and can’t be closed or minimized from the switcher. Each shortcut uses one modifier (⌥, ⌘, or ⌃) plus one key. If you close a window that asks to save first, or quit an app that asks to confirm, it disappears from the switcher until the next time you open it. Minimized and hidden windows show their app icon. Minimized and hidden windows share one toggle, and “switch on release” is global.
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
- **General:** English only (all text is ready for translation, but no translations exist yet) and no trackpad gesture. Updates need a release build: copies built from source don’t update themselves, and 0.3.0 and earlier need one manual download to reach 0.3.1.

### Needs testing on hardware

0.2, 0.3, and 0.3.1 were built without hardware testing (0.3.1’s checks are HW-24 to HW-38 in its [plan](docs/design/0.3.1/PLAN.md#part-c-hardware-checks)). These depend on hardware behavior and are marked Beta or checked at runtime (a wrong guess turns the feature off rather than misbehaving). Beta labels are updated once they’re checked.

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
- **Hidden-config abuse:** pointer movement, Drive Alive, a battery floor of zero, and forged session state written with `defaults` while Snaptic is quit, stopped, and running: none of them may move the pointer, skip the 5% floor, or write to ineligible drives.
- **From 0.2:** confirmed changes persisting across quit, relaunch, and reboot; the safety helper reverting after `kill -9` with virtual displays and a pending change; rotation and HDR reverts after a reboot; XDR extra brightness on M1–M5 XDR panels; gamma on virtual displays on M5; DDC over Apple silicon USB-C and HDMI, MCDP adapters, and Intel, and standby and wake through DDC; brightness and volume keys on Apple silicon laptops on macOS 26 and 27, and global shortcuts while a password field is focused; virtual displays and Smart HiDPI (HiDPI at creation, live mode changes, lock, sleep, Fast User Switching, lid closed with no external display, EDID colors on Apple silicon); Picture in Picture capture filters, window crop orientation, and the content-sharing picker on 14, 15, and 26; helper signature checks with ad-hoc and Developer ID builds and after an in-place update; Accessibility grants and relaunch on macOS 27; detecting password windows on macOS 26 without Screen Recording; Identify labels over full-screen apps and AirPlay.

## Not included

**Deferred** (may come later):
- **Displays:** system display overrides (scaled resolutions, display names, TV roles), connection color mode and direct XDR control, framebuffer grayscale and invert and keyboard-backlight keys, 3D LUTs on displays and compositor filters, HDMI-CEC, network TVs and receivers, DisplayLink control, HTTP-based Stream Deck plugins, True Tone and Dark Mode control, nits-normalized sync, SDR/HDR automatic profile switching, ranged custom controls with readback, Picture in Picture tabs and magnification above 100%, virtual-display identity editing, swapping identical displays, Sidecar management, and detachable menus.
- **Awake:** a “while a file is downloading” condition that watches the Downloads folder (Until Downloads and Tasks Finish and Network activity cover it), other Bluetooth devices, locking the screen after inactivity, screen saver control and exceptions, sounds, a condition on background processes by name (`awake hold` covers scripts), and `awake hold -- <command>` (Snaptic never runs commands).
- **Everywhere:** App Intents and Shortcuts actions, AppleScript, Control Center and widget controls (the command line covers Shortcuts), localization, and opening a Settings page from outside Snaptic.

**Excluded by design:**
- **Displays:** EDID writing or overrides (can brick or blank a display); reinitializing displays, VMM7100 resets, forced HDR, dithering, and similar private framebuffer tricks (blank screens); NVRAM resets and factory profile removal (destructive, need root); model-specific adaptations.
- **Awake:** keeping a closed laptop awake without asking each time (sudoers rules, Power Protect, an installed privileged helper, or undocumented clamshell calls: lasting root that any program running as you could use; lid-closed mode asks for a password each time instead); launch agents; turning Low Power Mode on or off (needs root); a Wi-Fi network name condition (Location access); a DNS-server condition; brand-specific VPN conditions; spawning `caffeinate`; synthetic key presses or clicks of any kind; Insomnia’s lid-close extras (freezing apps, muting, writing other apps’ settings, hotspot failover, typing into terminals, relaunching browsers); macOS notifications (Snaptic uses its own notices); custom menu bar images.
- **Everywhere:** a `snaptic://` URL scheme (any web page could fire it), an HTTP server or distributed-notification commands (unauthenticated), telemetry, analytics, crash upload, licensing, and any network connection other than the update checks you allow.

## How it works

| Path | Responsibility |
|---|---|
| `Sources/SnapticKit/` | Pure logic with unit tests that also run on Linux: the feature graphs, configuration and migrations, safety invariants, DDC and EDID parsing, the command-line protocol, Awake’s sessions, guards, rules, clock, and command grammar, and the control tables that map every 0.2 setting to its 0.3 home. |
| `Sources/SnapticShims/` | Small Objective-C wrappers for private display APIs, each checked before use. |
| `Sources/Snaptic/Core/` | The host: modules, menus, permissions, onboarding, Safe Mode, the command-line server and client, helper spawning, and the General, Menu Bar, Permissions, and About pages. |
| `Sources/Snaptic/SettingsUI/` | The shared Settings components (rows, sliders with value fields, sheets, search). |
| `Sources/Snaptic/Switcher/` | The window switcher (event tap, window list, thumbnails, switcher UI). |
| `Sources/Snaptic/Displays/` | The Displays module: services, one controller per feature group, the safety helper, transactions and journals, settings pages. |
| `Sources/Snaptic/Awake/` | The Awake module: the assertion, sessions, guards, rules, activity, Drive Alive, history, the command-line verbs, the condition sources, its menu, and its pages. |
| `site/` | The project website at [snaptic.dev](https://snaptic.dev), deployed by Vercel on every push to `main`. |
| `Sources/Snaptic/Core/UpdaterController.swift` | The only file that uses Sparkle; in a build without Sparkle it’s never reached. |
| `docs/design/` | The 0.2, 0.3, and 0.3.1 plans, their release notes, and platform research. |

### How Awake keeps your Mac awake

- **One named IOKit power assertion.** Awake holds at most one sleep assertion at a time, created with `IOPMAssertionCreateWithProperties` and named “Snaptic: keeping your Mac awake”: `PreventUserIdleDisplaySleep` when the display stays on, `PreventUserIdleSystemSleep` when it may sleep. Changing the type, details, or end creates the new assertion first and then releases the old one, so there’s never a gap.
- **Backstops.** A session with an end also gets a timeout with `TimeoutActionRelease`, so macOS releases the assertion even if Snaptic were stuck; Snaptic ends sessions itself on its own continuous clock (which counts sleep and ignores clock changes).
- **No root for sessions, nothing left behind.** Sessions use no `pmset`, no `caffeinate` process, no helper, no launch agent, and no sudoers rule. macOS releases a process’s assertions when it exits, so a crash can’t leave your Mac unable to sleep.
- **Lid-closed mode** is the one exception. After you enter an administrator password, a short root shell script (in `LidWatchdog.swift`, started through `osascript`) sets `pmset -a disablesleep 1` and stays as a watchdog: every 5 seconds it checks Snaptic’s process, a heartbeat file Snaptic touches, the battery, the heat, and its 24-hour limit, and its exit always sets `disablesleep 0` again, then puts a Mac with a closed lid to sleep (unless the Mac is shutting down). Snaptic writes a journal before sleep is turned off, so a restart or power loss in between is caught at the next launch (see [If sleep stays off](#if-sleep-stays-off)).
- **Drive Alive** adds a separate `PreventDiskIdle` assertion while it writes; **Appear active** uses `IOPMAssertionDeclareUserActivity`; **pointer movement** posts mouse-moved events from a private event source (the only code in Snaptic that posts mouse events).
- **Rules** read system state with public APIs: `NSWorkspace` notifications, CoreGraphics display callbacks, IOKit power-source notifications and USB matching, CoreAudio device properties, `SCDynamicStore`, `sysctl` routing and interface counters, `host_statistics`, `proc_pid_rusage`, and IORegistry disk counters.
- **Holds** watch the client process with a kqueue `EVFILT_PROC` source and identify it through the command-line socket; they never signal, spawn, or wrap a command.

### Undocumented APIs

Snaptic uses private macOS functions where no public one exists. Every one is looked up at runtime (never linked), checked for the expected signature, behind a kill switch, and fails closed: if Apple removes or changes one, the feature that needs it becomes unavailable instead of crashing. This also means Snaptic can’t be sold through the Mac App Store.

- **Switcher:** `_AXUIElementGetWindow`, `_SLPSSetFrontProcessWithOptions` and `SLPSPostEventRecordTo`, `SLSMainConnectionID` and `SLSCopySpacesForWindows`, `SLSSetSymbolicHotKeyEnabled` and `SLSIsSymbolicHotKeyEnabled`, and the deprecated `GetProcessForPID`. The focusing technique follows public reverse-engineering documented by [yabai](https://github.com/koekeishiya/yabai) (MIT).
- **Displays:** DisplayServices (Apple brightness, auto-brightness), CoreBrightness (Night Shift), MonitorPanel (rotation, underscan, HDR, Apple presets), CoreGraphics `CGS…` calls (hidden modes, disconnect, HDR state), `CGVirtualDisplay` (virtual displays), `IOAVService` (DDC on Apple silicon), CoreDisplay (display info), the OSD framework, and libsystem’s process-responsibility calls for helpers.
- **Awake:** no private functions. It reads undocumented keys with public calls: `CGSSessionScreenIsLocked` from `CGSessionCopyCurrentDictionary`, to know whether the screen is locked; the `SleepDisabled` power setting (`SystemPowerSettings` in the `com.apple.PowerManagement` preferences, through `CFPreferencesCopyValue`) and the kernel’s `SleepDisabled` and `AppleClamshellState` properties on `IOPMrootDomain` (through IOKit), to tell you when sleep is turned off and whether the lid is closed. It changes `SleepDisabled` only in lid-closed mode, and only through `pmset` after you enter an administrator password.

## License

MIT. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
