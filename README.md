# Snaptic

A free, open-source menu bar toolkit for macOS: a Windows-style **window switcher**, a set of **display utilities**, and **Awake**, which keeps your Mac awake when you want it to. Turn on only the parts you want; everything else stays off and costs nothing.

**Website:** [snaptic.dev](https://snaptic.dev)

Snaptic is MIT-licensed and written from scratch in Swift by revyl fitness technology, Inc. It isn’t affiliated with or derived from AltTab, BetterDisplay, MonitorControl, Lunar, Amphetamine, or Insomnia; it’s an independent take on the same ideas, with everything included and nothing behind a paywall. Third-party credits are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). What changed in 0.3 is in the [release notes](docs/design/0.3/RELEASE-NOTES-0.3.md).

- [Modules](#modules) · [Settings](#settings) · [Window Switcher](#window-switcher) · [Displays](#displays) · [Awake](#awake) · [Safety](#safety)
- [Permissions](#permissions) · [Command line](#command-line) · [Hidden kill switches](#hidden-kill-switches) · [Install and build](#install-and-build)
- [Privacy and security](#privacy-and-security) · [Upgrading and downgrading](#upgrading-and-downgrading) · [Troubleshooting](#troubleshooting) · [Known limitations](#known-limitations) · [Not included](#not-included) · [How it works](#how-it-works)

## Modules

| Module | What it does |
|---|---|
| **Window Switcher** | Hold **⌥ Option**, tap **Tab**, and pick any window, not just any app. |
| **Displays** | Brightness and volume for external displays, resolutions and HiDPI, color, arrangement, virtual displays, Picture in Picture, and more. |
| **Awake** | Keeps your Mac awake for a while, until a time, while an app runs, until downloads and tasks finish, or automatically when conditions you choose are met. A free replacement for Amphetamine and Insomnia that needs no administrator password. |

Each module can be turned on or off on its own: in **Settings › General › Choose what Snaptic does**, or with the switch at the top of the module’s own page (“Use Window Switcher”, “Use Displays”, “Use Awake”). A module that is off runs nothing: no event taps, timers, observers, IOKit handles, power assertions, private-API calls, helper processes, or permission prompts. Inside Displays and Awake, each feature has its own switch where the feature is used, and anything that’s off costs nothing either.

- **First launch:** onboarding asks which modules you want, then asks only for the permissions those need. It picks up where it left off if macOS makes Snaptic relaunch.
- **Upgrading from 0.2:** Window Switcher and Displays stay as they were. Awake starts off, with a “New: Awake” card in General, unless you used Displays’ display sleep prevention in 0.2; then Awake is on and keeps doing that job (see [Upgrading and downgrading](#upgrading-and-downgrading)).
- **Upgrading from 0.1:** the switcher stays on; Displays and Awake start off, each with its own card.

## Settings

Settings has seven pages in its sidebar: [General](#general), [Menu Bar](#menu-bar), [Window Switcher](#window-switcher), [Displays](#displays) (with its own sub-pages), [Awake](#awake), [Permissions](#permissions), and About. The search field at the top of the sidebar finds any setting, including the ones in **Advanced…** sheets, and highlights it on its page. Every page that has a (?) button links to its section of this README.

Most pages show the settings people change often and keep the rest in an **Advanced…** sheet at the bottom. Every slider has a value field you can type into, and a reset button when it has a default. **Restore Defaults…** on a page or sheet resets only that page’s settings.

## General

- **Choose what Snaptic does:** a switch per module, with a line on what each does.
- **Open at login.** If macOS needs you to allow Snaptic in Login Items, the page says so and opens the right pane.
- **Command-line control:** lets scripts and other apps control Snaptic with the `snaptic` command (off by default). **Copy Install Command** copies the Terminal command that installs it; see [Command line](#command-line).
- **Backup:** **Export Settings…** and **Import Settings…** (see [Privacy and security](#privacy-and-security) for what an export leaves out).
- **Advanced…:** “Commands can skip confirmation” (a display change sent with `--yes` applies without asking first), the exit codes the `snaptic` command uses, **Restart in Safe Mode…**, and **Reset All Settings…**.
- New-module cards (“New: Awake”, “New: Displays”) appear here once after an upgrade.

## Menu Bar

Everything about Snaptic’s menu bar icons lives on this page.

- **Where each module appears:** one pop-up per module with the same choices Control Center uses: **Always Show in Menu Bar**, **Show When Active**, **Show in Snaptic Menu**, and **Don’t Show**. Window Switcher has no “Show When Active”. For Displays it means “while an external display is connected”; for Awake, “while your Mac is being kept awake” (Awake’s default).
- **Icons:** a choice of icon for each module that has its own item and for the Snaptic icon.
- **Awake time:** **Don’t Show** (default), **Time Remaining**, or **End Time** next to Awake’s icon, in your system’s 12- or 24-hour setting, with seconds only in the last minute.
- **Displays menu:** **Standard** or **Compact** style (one slider per display), “Scroll over a slider to adjust it”, and **Customize Displays Menu…**, where every optional menu item can be shown, moved into a submenu, or hidden.
- **Restore Menu Bar Defaults…** resets only this page.

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
- **Sub-pages:** [Brightness and Dimming](#brightness-and-dimming), [Color](#color), [Hardware Controls](#hardware-controls), [Keyboard](#keyboard), Saved Layouts, Virtual Displays, Picture in Picture, Automations, and [Display Information](#display-information).

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

### Saved Layouts, Virtual Displays, Picture in Picture, and Automations

- **Saved layouts (Opt-in):** save and apply layouts, optionally automatically when the same displays connect. **Protect arrangement (Opt-in)** puts the arrangement back when something else changes it (for example the macOS 27.2 arrangement-restore bug).
- **Virtual displays (Opt-in, Beta):** displays that exist only in software, with templates (Headless, Recording 16:9, Teleprompter, Portrait) and associations with real displays. Sharper text (Smart HiDPI, Opt-in, Beta) gives sharp text at any size on external displays; HDR virtual modes are Experimental.
- **Picture in Picture (Opt-in, needs Screen Recording):** a live copy of a display or a window in a floating window (crop, click-through, orientation), or a display streamed full screen onto another. Filters (Opt-in): built-in Core Image filters and imported 3D `.cube` LUTs.
- **Automations:** event hooks (Opt-in) run a program when a display connects or disconnects, or when the Mac sleeps or wakes; custom actions (Opt-in) put your own programs in the menu, on shortcuts, and (if you mark them) on the command line.

### Display Information

- **Report:** a live report about your displays, with **Copy Report** and **Export Report…**. It has no display names, serial numbers, window titles, or app names, and identifiers are masked. It lists private-API availability, kill switches, helpers, and recent events.
- **Safety helper** and **undo journal** status, with **Restart the safety helper** when it stopped.
- **EDID:** export the data a display reports about itself (Export EDID…).
- **Remembered displays** (forget one, or all that aren’t connected) and **remembered resolutions**.

### Displays Advanced Settings

**Use Snaptic for** turns whole areas on or off: brightness control, resolution control, arrangement and mirroring, rotation, keyboard shortcuts for displays, the brightness indicator, disconnecting displays, the HDR switch, underscan, built-in auto-brightness, brightness broadcast, and showing all resolutions. The sheet also has **Confirm display changes** (see [Safety](#safety)) and **Other display apps**: if BetterDisplay, MonitorControl, or Lunar is running, Snaptic pauses its overlapping features by default (“Paused while MonitorControl runs”) or runs both if you choose.

## Awake

Awake keeps your Mac from going to sleep while you want it awake, with the same public macOS power assertion `caffeinate` uses. It needs no administrator password, installs nothing, and leaves nothing behind: if Snaptic quits or crashes, macOS releases the assertion at once and your Mac sleeps normally again.

Turn it on with **Use Awake** at the top of the Awake page. The page has a status row (**Keep Awake ▾** while nothing runs; **Options ▾**, **Turn Off**, and **Pause Rules ▾** while something does), Sessions, End sessions automatically, Start automatically, Keyboard, Drives ›, History ›, and **Advanced…**.

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

None of these needs a permission. **Pause Rules** (for 1 hour or until tomorrow) is in the Awake menu’s **Rules ›**, the status row, a shortcut, and `snaptic awake pause`. A session you start yourself always takes precedence over rules, and command-line holds come last.

### Guards

Guards end sessions so Awake never drains your battery or keeps a hot Mac running.

- **5% battery floor (always on, no setting, no kill switch):** below 5%, every session, hold, and Drive Alive ends whenever the battery is discharging, also on a power adapter too weak to keep up (the battery fell within the last 10 minutes).
- **When the battery is low** (laptops; default on at 20%, 5–50%): ends sessions below your level. Rules don’t start again until the battery is 5% above the level or charging.
- **When the power adapter is disconnected** (laptops; off by default).
- **When Low Power Mode turns on** (Advanced; off by default). Otherwise Awake keeps running and says so once.
- **Heat:** when your Mac gets very hot (critical thermal state), every session and hold ends, Drive Alive stops, and rules pause for 10 minutes. This can’t be turned off. A serious (lower) thermal state shows a one-time notice.
- **Unreadable battery:** if a laptop’s battery can’t be read twice in a row, Awake stops appearing active and keeping drives awake (it treats the battery as empty) but keeps the session, and says so.
- **Start Anyway:** when the low-battery guard or Low Power Mode refuses a session you started in Snaptic, the notice offers **Start Anyway** for that one session. It never overrides the 5% floor or heat, and never applies to the command line.
- **Advanced…** also has: end sessions when your Mac sleeps (when you choose Sleep or close the lid), when you switch users (immediately, after 1 hour, or never), and after the screen has been locked for 1, 4, or 12 hours; keep the display on while locked (off: the display may sleep on the lock screen while your Mac stays awake).

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
- The 5% battery floor and the heat guard stop Drive Alive in every mode.
- macOS asks once for access to removable volumes, the first time Snaptic writes to a drive.

### History

**Awake › History ›** shows today’s and the last 7 days’ time kept awake and the past sessions, with **Start Again** for sessions you started (not for command-line, process, or automatic ones) and **Clear History…**. History stays on this Mac for 90 days (at most 500 sessions) and never goes into exports, logs, diagnostics, or the command line.

### In the menu bar

By default Awake’s icon appears only while your Mac is being kept awake (Show When Active), next to the Snaptic icon; change that on the [Menu Bar](#menu-bar) page, along with the icon (cup, eye, or light bulb, filled while active) and the time shown next to it. The Awake menu and the compact Awake section in the Snaptic menu have the same rows: the **Keep Awake** switch with what’s keeping your Mac awake (“Held by Terminal (2)” for command-line holds), **Turn Off Keep Awake**, the Add Time items, **Keep Display On**, **End Command-Line Holds**, **Start Session ›**, **While an App Is Running ›**, and **Rules ›**. On a laptop running on battery or without an external display, the menu reminds you that closing the lid puts your Mac to sleep.

### Keyboard shortcuts

**Awake › Keyboard Shortcuts…** has, all unbound by default: **Keep Awake** (starts your default session, or turns Keep Awake off), **Keep Display On**, **Start “…”** for the first four sessions in Sessions in the menu, and **Pause Rules** (for 1 hour, or resume). Shortcuts work in any app while Awake is on.

### Other apps keeping your Mac awake

**Awake › Advanced…** lists other apps that are keeping your Mac awake right now, with what each prevents, updated every few seconds. If sleep is turned off for the whole Mac (`SleepDisabled`, left by `pmset disablesleep`, Amphetamine Power Protect, or Insomnia), it says so; Snaptic can’t and won’t change that setting. See [Switching from Amphetamine or Insomnia](#switching-from-amphetamine-or-insomnia).

### Why not with the lid closed on battery?

Awake can’t keep a MacBook awake with its lid closed on battery, by design. macOS allows that only with root: `pmset disablesleep`, a sudoers rule that lets apps run it without a password (Amphetamine Power Protect, Insomnia), or an undocumented clamshell call. Those settings are system-wide, stay on after the app crashes, can be used by any program running as you, and a closed laptop in a bag can overheat. Awake uses only power assertions, which macOS drops as soon as Snaptic stops.

To keep a MacBook awake with the lid closed, use macOS’s own closed-display mode: connect power and an external display (and a keyboard or mouse), then close the lid.

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
| Closed-display mode on battery, Power Protect | Not offered; see [Why not with the lid closed on battery?](#why-not-with-the-lid-closed-on-battery) |

Quit the other app and remove it from Login Items first, so two apps don’t keep your Mac awake. Their closed-lid features can leave two things behind that Snaptic never touches: a **sudoers rule** that lets programs run `pmset` without a password, and the system-wide **`SleepDisabled`** setting. The commands below are for you to run in Terminal; Snaptic never runs them. Prefer the other app’s own uninstaller first (Amphetamine: Feedback & Support › Uninstall Scripts…).

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
- **Awake can’t drain your battery or cook your Mac:** the 5% floor and the heat guard have no setting and no kill switch (see [Guards](#guards)).

## Permissions

Snaptic asks only for what the features you turned on need, and only when you turn them on. The Permissions page shows each one’s status, what needs it, and who signed the running copy (“ad-hoc” or “Developer ID …”).

| Permission | Asked for when | Used for |
|---|---|---|
| **Accessibility** (called **Device Control and Data Access** on macOS 27) | Window Switcher is on; Brightness keys or Volume keys; Gather windows on first use; Awake’s pointer movement | Seeing the switcher shortcut and media keys, listing and focusing windows, and moving the pointer 1 point. |
| **Screen Recording** (Screen & System Audio Recording) | Switcher thumbnails or preview; Picture in Picture | Thumbnails, the full-size preview, titles of windows on other Spaces, and Picture in Picture captures. |
| **Removable Volumes** (Files & Folders) | The first time Drive Alive writes to a drive | Rewriting `.snaptic-keepalive` on the drives you chose. |

Accessibility and Screen Recording are in **System Settings › Privacy & Security**. The permission window shows the exact app path, with “Show Snaptic in Finder” so you add *this* copy. On macOS 27 a grant often takes effect only after a relaunch; Snaptic offers **Relaunch Snaptic**. Without Accessibility the switcher stays idle and Awake only appears active instead of moving the pointer. Without Screen Recording the switcher shows app icons and only windows on the current Space. macOS Sequoia and later re-confirm Screen Recording about once a month; that prompt comes from macOS.

Most Displays features need no permission at all. Awake needs none for sessions, rules, guards, holds, appear active, history, or the menu bar: its conditions read only system state that macOS gives any app without asking (no Location, Bluetooth, Microphone, Input Monitoring, Local Network, or Downloads folder access).

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

**Never from the command line:** turning on anything off-only, and changing hooks, actions, command-line settings, disconnect, auto-disconnect, dim to black, DDC unlocks, “allow without asking” choices, layout trust, or any Awake setting (rules, sessions in the menu, guards, Drive Alive, appear active, pointer movement). Accessibility-using actions (Gather windows, pointer movement) are never command-line actions.

### Awake commands

Available while Awake is on and command-line control is on (otherwise `snaptic` answers “Unknown command.”, exit 2, or exits 5 if Snaptic isn’t running).

| Command | What it does |
|---|---|
| `snaptic awake status [--json]` | `inactive`, or a tab-separated line: `active`, the source (`manual`, `automatic`, or `holds`), the kind (`indefinite`, `duration`, `until`, `app`, `idle`, `process`, or `automatic`), the display policy (`keepOn`, `maySleep`, or `keepOnWhileActive`), the end time in UTC ISO 8601 or `-`, the seconds remaining or `-`, and the number of holds. `--json` prints one object with `active`, `source`, `kind`, `display`, `end`, `remaining`, `rule` (the rule’s number), `holds`, and `pids`. No app, rule, or process names. |
| `snaptic awake start [<duration>] [--display-may-sleep]` | Starts a session. No argument means 1 hour. Durations: `90` (minutes), `90m`, `2h`, `1.5h`, `1h30m`, `1h 30m`, `3d`, `until 17:30`, `until 5:30pm`, or `idle` (Until Downloads and Tasks Finish, at most 12 hours). Between 1 minute and 30 days. `indefinite` and `forever` are refused (exit 4): use the menu or `awake hold`. |
| `snaptic awake hold [--pid N] [--max <duration>]` | Keeps your Mac awake while this command runs, or while process N runs, at most 12 hours, or `--max` up to 24 hours. See below. |
| `snaptic awake preset <number\|name>` | Starts one of Sessions in the menu by its position (1 is the first) or its name. Until Turned Off sessions are refused. |
| `snaptic awake extend <duration>` | Adds time to the running session (sessions with an end only; holds have `--max` instead). |
| `snaptic awake stop` | Ends the running session; a rule’s session counts as turned off by you. Holds end with their own commands. |
| `snaptic awake pause [<duration>]` | Pauses rules for 1 hour, or for up to 24 hours. |

- **Your sessions come first.** `start` and `preset` are refused (exit 4) while a session you started in Snaptic runs: stop it first with `snaptic awake stop`, or use `awake hold`, which never replaces anything.
- **Guards apply** to every command-line session and hold, with no Start Anyway (exit 4 with the reason).
- **Never** pointer movement or Drive Alive for command-line sessions and holds. A notice says “Awake was started from the command line.” at most once every 10 minutes, and the menu shows it.
- **Rate limit:** `start`, `hold`, `preset`, `extend`, and `stop` together are limited to 1 request per second (on top of 20 requests per second for all commands). A request over the limit exits 5 with “Too many Awake requests; wait a second and try again.”

#### `awake hold`

A hold keeps your Mac awake beside whatever else runs: up to 8 holds at a time, next to your own session and rules. Snaptic never runs your command; a hold only watches a process. The menu says “Held by Terminal” (or the app that started it, with a count).

- **`snaptic awake hold`** holds for as long as this `snaptic` process runs. It prints “Holding until this command ends (at most 12 h). Press Control-C to stop.” and keeps running. The hold ends when the command exits or is killed, its terminal closes, you press Control-C, time is up, you choose **End Command-Line Holds** or turn Keep Awake off in Snaptic, a guard ends it, or command-line control or Awake is turned off. It then prints why (“Awake hold ended: time is up.”) and exits 0, or exits 5 if Snaptic quit.
- **`snaptic awake hold --pid N`** holds while process N runs (one of your own processes; N > 1). It prints “Holding while process N runs (at most 12 h).” and exits at once. The hold survives a Snaptic relaunch.
- A ninth hold is refused: “Snaptic is already holding for 8 commands.” (exit 4).

```sh
# In a script: hold for as long as this script's shell runs
snaptic awake hold --pid $$
rsync -a ~/Projects/ /Volumes/Backup/Projects/

# Around one command in an interactive shell or a single script
snaptic awake hold & HOLD=$!; make release; kill $HOLD
```

**The parent-shell pitfall.** `make` recipe lines, `npm run` steps, CI step runners, and AI agents’ tool calls run each line in a fresh `sh -c` that exits as soon as the line ends. There, `--pid $$` names a shell that exits at once, so the hold ends within milliseconds (the reply and a notice say so), and a backgrounded `hold &` left behind by one line keeps holding after the work is done, until its cap. Put the hold, the work, and the `kill` in **one** shell: one recipe line joined with `;` or `&&`, `.ONESHELL:` in a Makefile, or a script file. Or pass `--pid` of a process that lives as long as the work, or use `snaptic awake start 2h`. On CI machines, `caffeinate -w <pid>` remains a fine choice.

```make
# Makefile: one recipe line, so the hold, the work, and the kill share one shell
release:
	snaptic awake hold & hold=$$!; ./build.sh && ./upload.sh; status=$$?; kill $$hold; exit $$status
```

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (also when a hold ends normally) |
| 2 | Usage error, unknown command, a retired command such as `prevent-sleep`, or a name that matches several displays or items |
| 3 | Nothing matched (display, action, layout, configuration, Awake session in the menu) |
| 4 | Refused by policy: off-only, a protected setting, the safety rules, or an Awake refusal (a guard, a session you started in Snaptic is running, 8 holds, a session without an end, a caller Snaptic couldn’t identify) |
| 5 | Unavailable: Snaptic isn’t running or quit, command-line control is off, the feature is off or unsupported, or too many Awake requests |
| 6 | Cancelled or timed out (the confirmation was declined or expired; the client waits up to 90 s: the longest panel plus 30 s) |

**Recipes.** A Stream Deck “Run shell” or Raycast script command can call `snaptic set brightness +10 mouse`, `snaptic input "HDMI 1" 2`, `snaptic layout apply Office`, or `snaptic awake start 2h`.

## Hidden kill switches

Kill switches turn a module or a feature off for this Mac, whatever Settings says. They are Boolean keys in Snaptic’s own preferences (`app.snaptic.Snaptic`), they only ever turn things off, and pages show what they turned off as “Turned off for this Mac by an administrator or a Terminal command.” with the command that undoes it. Quit and reopen Snaptic to apply a change. Diagnostics lists the ones that are set.

```bash
defaults write app.snaptic.Snaptic Modules.disable.awake -bool true                # a whole module
defaults write app.snaptic.Snaptic Awake.disable.pointerNudge -bool true           # one Awake feature
defaults write app.snaptic.Snaptic Displays.disable.xdr -bool true                 # one Displays feature
defaults write app.snaptic.Snaptic Displays.disable.symbol.MPDisplay -bool true    # one private API
defaults delete app.snaptic.Snaptic Awake.disable.pointerNudge                     # undo
```

- **Modules:** `Modules.disable.windowSwitcher`, `Modules.disable.displays`, `Modules.disable.awake`. A module turned off this way never starts, its page shows why with its switch disabled, and Awake also releases its assertion and doesn’t resume a session at the next launch.
- **Awake features:** `presets` (sessions in the menu), `triggers` (rules), `activity` (appear active, and so pointer movement), `pointerNudge` (pointer movement), `driveAlive`, `history`, `shortcuts`, and `commandLine` (the `snaptic awake` commands). `sessions`, `batteryGuard`, `thermalGuard`, and `indicator` are ignored, so the guards and a visible indicator always stay; use `Modules.disable.awake` to turn Awake off entirely.
- **Displays features** (ids as in `snaptic features`): `resolution`, `hiddenModes`, `scaleMatch`, `brightness`, `brightnessApple`, `brightnessDDC`, `brightnessGamma`, `brightnessOverlay`, `brightnessRestore`, `dimToBlack`, `dimOnLock`, `nits`, `xdr`, `sync`, `autoBrightness`, `color`, `colorProfiles`, `nightShift`, `applePresets`, `ddcControls`, `ddcInput`, `ddcPower`, `ddcCustom`, `brightnessKeys`, `volumeKeys`, `shortcuts`, `osd`, `osdBroadcast`, `mainDisplay`, `arrangement`, `mirroring`, `rotation`, `underscan`, `hdrToggle`, `disconnect`, `autoDisconnectBuiltin`, `protection`, `layouts`, `virtualScreens`, `smartHiDPI`, `hdrVirtual`, `pip`, `pipFilters`, `menuBarOverlays`, `hooks`, and `customActions`. `Displays.disable.symbol.<name>` turns off one private API.

### Deploying kill switches in an organization

Snaptic reads only the user’s own preferences, never managed (forced) preferences, so a profile payload that *forces* a key has no effect. To deploy kill switches, write them into each user’s own `app.snaptic.Snaptic` domain:

- **With a configuration profile:** a Custom Settings (`com.apple.ManagedClient.preferences`) payload whose keys are applied **Set-Once**, so macOS writes them into the user’s preferences rather than forcing them. Install it as a user-scope profile. Check on a test Mac that `defaults read app.snaptic.Snaptic Awake.disable.pointerNudge` prints `1` and that Settings shows the feature as turned off; if your macOS version applies the payload as managed instead, use the script below.
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

Grab `Snaptic.zip` from the [latest release](https://github.com/revylfitness/snaptic/releases/latest), unzip it, and drag Snaptic to Applications. Releases are built by GitHub Actions from the tagged commit.

Snaptic isn’t notarized by Apple yet, so the first time you open it macOS will block it. Go to System Settings › Privacy & Security and click **Open Anyway**. Run it from Applications: if macOS starts it from a temporary “translocated” location, Snaptic tells you to move it first.

### Build and run

```bash
git clone https://github.com/revylfitness/snaptic.git
cd snaptic
INSTALL=1 ./scripts/build-app.sh      # builds and installs Snaptic.app to /Applications, owned by root
open /Applications/Snaptic.app
```

Leave out `INSTALL=1` to build only (`build/Snaptic.app`). For a universal Apple silicon and Intel build, which needs full Xcode, add `ARCHS="arm64 x86_64"`. The unit tests in `Tests/` run with `swift test`, also on Linux.

`INSTALL=1` installs the app owned by root (it runs `sudo ditto` and `chown -R root:wheel`, so it asks for your password). That way your account, and any program running as you, can’t replace the binary that holds Snaptic’s permissions. Snaptic warns before you grant a permission if its bundle is writable by you. Awake needs no root at any time; the password is only for installing.

GitHub Actions compiles every push and pull request. Pushes to `main` and version tags also upload a universal `Snaptic.zip` as a workflow artifact. On public repositories a separate job, which never runs repository code, adds a build-provenance attestation. Verify that it came from this workflow on `main`:

```bash
gh attestation verify Snaptic.zip --repo revylfitness/snaptic \
  --signer-workflow revylfitness/snaptic/.github/workflows/build.yml --source-ref refs/heads/main
```

These CI builds are ad-hoc signed and not notarized, so macOS will warn before opening one. Building it yourself avoids that. Pull requests and manual runs never publish a downloadable app. Consider protecting `.github/workflows` with a branch ruleset so only reviewed workflows can attest builds.

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

**Why Developer ID builds are recommended.** Snaptic’s helpers (the safety helper and virtual-display hosts) check that they were started by Snaptic, and Snaptic checks each helper, by code signature. With an ad-hoc build that signature is the exact build, so permissions are lost on every update and, after updating in place, helpers are refused until you restart Snaptic (“Restart Snaptic to finish updating”). A Developer ID signature (team plus identifier) survives updates and can be notarized. To share builds with other people, sign with a Developer ID certificate and notarize with `xcrun notarytool`.

## Privacy and security

**No network.** Snaptic never connects to the network: no telemetry, no crash upload, no update checks (**Check for Updates…** opens the Releases page in your browser). A lint check rejects networking APIs in the source.

**What never leaves the process.** Window pixels, window titles, app names, and key presses. The command line, hooks, diagnostics, and the event log never carry them. Diagnostics mask serial numbers; display keys are salted per Mac and the salt is never exported.

**What leaves on purpose.**
- *Brightness broadcast* (opt-in) posts a system-wide notification `app.snaptic.osd` with only the kind (brightness, volume, …), the value, and the maximum, at most 10 per second, and nothing while the screen is locked.
- *Hooks and custom actions* (opt-in) run programs you chose, with a minimal environment (`SNAPTIC_EVENT`, `SNAPTIC_DISPLAY_NAME`, `SNAPTIC_DISPLAY_KEY`), without Snaptic’s permissions, stopped after 30 seconds. Programs must be absolute paths owned by you or root and not writable by others. Never in Safe Mode or while automation is paused.
- *Awake’s power assertion* is visible to every app (`pmset -g assertions`), as all assertions are. Its name is always “Snaptic: keeping your Mac awake” and its details only say `manual` or `automatic`: never an app, rule, or condition.

**On disk.** Settings (in Snaptic’s preferences), and under `~/Library/Application Support/Snaptic/` (0700): the single-instance lock, the command-line socket, undo journals for display changes, and copies of imported LUTs. Drive Alive’s only trace is the 8-byte `.snaptic-keepalive` file on drives you turned on. Backup export leaves out hooks, actions, command-line settings, the salts, DDC unlocks, “allow without asking” choices, layout trust, sensitive switches (disconnect, auto-disconnect, dim to black), Awake’s history, Drive Alive drives, pointer movement, and the apps you used recently; Awake rules are included only if you tick “Include automatic-session rules”. Import strips the same things even if present, and can only make Awake’s guards stricter.

**Command line.** Only your user account can connect, through a private socket (directory 0700, socket 0600); Snaptic never listens on the network. Requests are size-, rate-, and time-limited. See [Command line](#command-line) for what it can never change.

**Helpers.** The safety helper and virtual-display hosts are copies of Snaptic’s own executable, started with an empty environment and their own process responsibility, so they hold none of Snaptic’s permissions. Each side checks the other’s code signature.

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

- **What it reads, only while a session, rule, or page needs it:** the battery and power adapter state, the thermal state, Low Power Mode, whether the screen is locked and whose session is on screen, the list of running apps, connected displays, mounted drives, connected USB devices, whether audio is playing or the microphone is in use (never the audio itself), how long since you last used the keyboard or mouse, your Mac’s network addresses and its router’s hardware address, network and disk byte counters, CPU use of your own processes (as numbers only, never their names), Bluetooth audio and input devices’ properties (never opened), and which other apps hold power assertions.
- **What it keeps:** your rules and sessions in the menu (with the app, device, and network names you chose) in Snaptic’s preferences; routers and USB serial numbers only as salted hashes; recently used apps for the menu (at most 5); and History (90 days). Other programs running as you can read Snaptic’s preferences, as with any app.
- **What it never does:** send anything anywhere, log app, device, network, or process names (its log keeps only counts and error codes), put names in diagnostics or the command line (the CLI shows process numbers only), or store a timeline in logs. CPU and disk samples stay in memory for the running Until Downloads and Tasks Finish session only.
- **What it can’t be made to do:** run a program (Awake spawns nothing and has no actions besides keeping your Mac awake), type, click, or scroll, or use Snaptic’s permissions for anyone else. A program running as you can already hold the same power assertion with `caffeinate`, so the command line grants nothing new; command-line sessions are visible in the menu bar and bounded in time.

**Startup checks.** Snaptic accepts only its own launch arguments, refuses to start with code-injection-style environment variables (`DYLD_*`, `OBJC_*`, `NS*`, `CF*`, `Malloc*`, and similar) or a `HOME` that isn’t your account’s, reads settings only from its own preferences (not command-line or managed overrides), and runs one copy at a time.

## Upgrading and downgrading

**0.2 → 0.3.** No setting is lost; every 0.2 setting, button, and menu item has a home in 0.3 (Settings search finds them by their old names too).

- **Display sleep prevention moved to Awake.** If it was on in 0.2 (Displays on, the feature on, and at least one display set to prevent sleep), 0.3 turns Awake on with a rule “While a display is connected” for those displays (up to 8 per rule), keeping the display on. General shows “Your display sleep setting moved to Awake.”, and the first time the rule applies, a one-time notice says so. If it wasn’t in use, Awake starts off with a “New: Awake” card.
- **Its shortcut** moves to Awake’s **Pause Rules** if a rule was created and Pause Rules has no shortcut yet; otherwise it’s removed, and Recent Notices says “Your display sleep shortcut was removed. Set Awake shortcuts in Settings › Awake › Keyboard Shortcuts.”
- **Menu bar placement** (shared, own icon, hidden, and Displays’ “hide when no external display is connected”) becomes the new per-module pop-up on the Menu Bar page.
- **`snaptic prevent-sleep`** is retired; see [Command line](#command-line).
- Each upgrade step runs once and records that it ran, so a later change you make isn’t undone at the next launch.

**0.3 → 0.2 → 0.3.** You can go back to 0.2 and forward again:

- **What 0.2 reads back:** 0.3 keeps writing the 0.2 fields, so 0.2 finds your Window Switcher and Displays settings, the menu bar placement you chose in 0.3 (Awake’s “Show When Active” reads as an own icon), and its display sleep prevention settings and shortcut exactly as they were when you upgraded. 0.2’s own sleep prevention works again while you run 0.2.
- **What 0.2 ignores:** everything about Awake. Its settings, history, and state stay untouched in their own keys.
- **Back on 0.3:** the upgrade steps don’t run again, so a change you made to display sleep prevention while on 0.2 isn’t carried into Awake (adjust the rule yourself). Menu bar placement you changed in 0.2 is read again. Awake continues as you left it.

## Troubleshooting

- **A display went black or the picture is wrong.** Wait 15 seconds without pressing anything; unconfirmed changes revert. Otherwise press **⌃⌥⌘⎋** (or ⌃⌥⌘⇧⎋). If Snaptic won’t start cleanly, hold **⇧** while opening it for Safe Mode.
- **Permission is on but Snaptic still asks.** Remove Snaptic from the list with −, add it again with + (use “Show Snaptic in Finder” to pick the right copy), then relaunch. After rebuilding an ad-hoc build, run `tccutil reset Accessibility app.snaptic.Snaptic` first.
- **“Restart Snaptic to finish updating” or “Unprotected”.** Snaptic was replaced while running, so its helpers are refused. Quit and reopen it.
- **A display doesn’t respond to brightness or volume.** Many TVs, DisplayLink adapters, some docks, and the HDMI port on some Macs don’t pass DDC; Snaptic dims those in software instead. Hardware Controls shows whether each display answers.
- **A feature shows “Paused while … runs”.** Another display app is running. Quit it, or choose “Run both” in Displays › Advanced… › Other display apps.
- **No menu bar icon.** macOS may hide it in the overflow or in System Settings › Menu Bar. Open Snaptic again from Finder or Spotlight to get Settings, or use the “Show Displays Panel” shortcut if you set one.
- **My Mac still went to sleep during a session.** Closing the lid and choosing Sleep always sleep a Mac; see [Why not with the lid closed on battery?](#why-not-with-the-lid-closed-on-battery). Otherwise the menu says why the session ended for 12 hours: a guard (battery, adapter, Low Power Mode, heat), “End sessions when your Mac sleeps”, switching users, or a locked screen (Awake › Advanced…).
- **My Mac doesn’t sleep and Awake is off.** Look at Awake › Advanced… › Other apps keeping your Mac awake, or run `pmset -g assertions`. If it says sleep is turned off for this Mac, see [Switching from Amphetamine or Insomnia](#switching-from-amphetamine-or-insomnia).
- **The display turns off during a session.** Turn on “Keep the display on” for the session (Keep Display On in the menu). On the lock screen, the display may sleep unless “Keep the display on while locked” is on.
- **`awake hold` ended at once, or kept holding after the work.** See [the parent-shell pitfall](#awake-hold).
- **`snaptic` says it isn’t running, or doesn’t know `awake`.** Turn on Settings › General › Command-line control, and make sure Awake is on. Exit code 5 means Snaptic isn’t running, control is off, the feature is off, or you sent Awake requests faster than once a second.
- **Filing an issue.** Copy the report from Displays › Display Information (or `snaptic diagnostics`). It has no window titles, app names, or serial numbers; Awake contributes only counts.

## Known limitations

- **Switcher:** windows on other Spaces show their app icon rather than a thumbnail, say “Other Space” rather than which Space, and can’t be closed or minimized from the switcher. Each shortcut uses one modifier (⌥, ⌘, or ⌃) plus one key. If you close a window that asks to save first, or quit an app that asks to confirm, it disappears from the switcher until the next time you open it. Minimized and hidden windows show their app icon. Minimized and hidden windows share one toggle, and “switch on release” is global.
- **Displays:** EDID-based display names are read on Intel Macs only. The panic confirmation is a notice, not a full HUD. A display “captured” by another app (a full-screen game) refuses changes and the confirm panel. Brightness sync notices changes made with a display’s own buttons only when readback is on. Auto-disconnect reads the lid state when it plans, and can’t detect a display in standby or on another input. “Disconnect on lock” ignores the screen saver. Virtual-display primaries come from EDID only (no ICC fallback). “Stream onto” associations ask rather than start. On macOS 27 the system’s own HUD also shows at the top right, so the two indicators can overlap; Snaptic’s defaults to top center there.
- **Picture in Picture:** Safari doesn’t mark private windows (add Safari to the protected apps). Window sources are picked in the system picker each time, so they can’t start automatically or from the command line. Imported LUTs aren’t included in Backup. The cursor can’t be excluded from streams, and filters can’t be applied to a stream of the display itself.
- **Awake:**
  - A MacBook with its lid closed on battery sleeps, and choosing Sleep always sleeps the Mac (by design; see above).
  - **Bluetooth audio** conditions are Beta and cover only Bluetooth audio devices and Bluetooth keyboards, mice, and trackpads; other Bluetooth devices can’t be detected without the Bluetooth permission.
  - No Wi-Fi network name (it needs Location access) or DNS-server condition; **Connected to this network** recognizes a network by its router instead.
  - Until Downloads and Tasks Finish can’t see other users’ processes (such as Spotlight or Time Machine running as root), but their disk activity counts, so a session may run on while they work.
  - Clicking Awake’s icon always opens its menu; there’s no ⌘-click quick start (use the Keep Awake shortcut).
  - Appear active keeps macOS from idling, but chat apps may still mark you away; pointer movement is Experimental and limited by its safety rules.
  - History, rules, and recently used apps are plain preferences that other programs running as you can read.
  - Starting a session at login needs “Open at login” and **Start a session when Snaptic opens**.
- **General:** English only (all text is ready for translation, but no translations exist yet), no trackpad gesture, no automatic updates.

### Needs testing on hardware

0.2 and 0.3 were built without hardware testing. These depend on hardware behavior and are marked Beta or checked at runtime (a wrong guess turns the feature off rather than misbehaving). Beta labels are updated once they’re checked.

- **Awake power:** both assertion types and how `pmset -g assertions` shows them on macOS 14, 15, 26, and 27, Intel and Apple silicon; switching between them without the display dimming; the screen saver and the lock screen with each type; lid close on battery, on power, and in closed-display mode.
- **Awake guards:** power notifications on desktops and laptops; an underpowered USB-C charger counted as discharging; thermal states; the clock across sleep.
- **Appear active and pointer movement:** whether declaring activity or a 1-point move keeps chat apps active; the edge and Accessibility-denied paths; the 1-hour cap letting the Mac lock.
- **Conditions:** no microphone indicator or prompt for the audio condition; no Input Monitoring for Bluetooth input devices; no Local Network prompt for the router check; network counters at 10 GbE.
- **Drive Alive:** the Removable Volumes prompt; keeping a USB hard drive spinning; ejecting not blocked; disk images and startup volumes refused.
- **Until Downloads and Tasks Finish:** the thresholds on 10-core Apple silicon and Intel Macs during compiles, links, large copies, downloads, and archive extraction.
- **`awake hold`:** ending within a second when the client is killed, interrupted, or its terminal closes; `--pid $$` in scripts and `make`; PID reuse; 8 holds beside a session; a 12-hour idle hold.
- **Menu bar and Settings:** status item placement and hiding on 14–27 (including notched Macs with many items and Show When Active); the custom menu rows (alignment, keyboard, VoiceOver, live values while the menu is open); sidebar search and scrolling, number fields, and switch sizes on macOS 14.
- **Hidden-config abuse:** pointer movement, Drive Alive, a battery floor of zero, and forged session state written with `defaults` while Snaptic is quit, stopped, and running: none of them may move the pointer, skip the 5% floor, or write to ineligible drives.
- **From 0.2:** confirmed changes persisting across quit, relaunch, and reboot; the safety helper reverting after `kill -9` with virtual displays and a pending change; rotation and HDR reverts after a reboot; XDR extra brightness on M1–M5 XDR panels; gamma on virtual displays on M5; DDC over Apple silicon USB-C and HDMI, MCDP adapters, and Intel, and standby and wake through DDC; brightness and volume keys on Apple silicon laptops on macOS 26 and 27, and global shortcuts while a password field is focused; virtual displays and Smart HiDPI (HiDPI at creation, live mode changes, lock, sleep, Fast User Switching, lid closed with no external display, EDID colors on Apple silicon); Picture in Picture capture filters, window crop orientation, and the content-sharing picker on 14, 15, and 26; helper signature checks with ad-hoc and Developer ID builds and after an in-place update; Accessibility grants and relaunch on macOS 27; detecting password windows on macOS 26 without Screen Recording; Identify labels over full-screen apps and AirPlay.

## Not included

**Deferred** (may come later):
- **Displays:** system display overrides (scaled resolutions, display names, TV roles), connection color mode and direct XDR control, framebuffer grayscale and invert and keyboard-backlight keys, 3D LUTs on displays and compositor filters, HDMI-CEC, network TVs and receivers, DisplayLink control, HTTP-based Stream Deck plugins, True Tone and Dark Mode control, nits-normalized sync, SDR/HDR automatic profile switching, ranged custom controls with readback, Picture in Picture tabs and magnification above 100%, virtual-display identity editing, swapping identical displays, Sidecar management, and detachable menus.
- **Awake:** a “while a file is downloading” condition that watches the Downloads folder (Until Downloads and Tasks Finish and Network activity cover it), other Bluetooth devices, locking the screen after inactivity, screen saver control and exceptions, sounds, a condition on background processes by name (`awake hold` covers scripts), and `awake hold -- <command>` (Snaptic never runs commands).
- **Everywhere:** App Intents and Shortcuts actions, AppleScript, Control Center and widget controls (the command line covers Shortcuts), localization, and opening a Settings page from outside Snaptic.

**Excluded by design:**
- **Displays:** EDID writing or overrides (can brick or blank a display); reinitializing displays, VMM7100 resets, forced HDR, dithering, and similar private framebuffer tricks (blank screens); NVRAM resets and factory profile removal (destructive, need root); model-specific adaptations.
- **Awake:** keeping a closed laptop awake on battery (`pmset disablesleep`, sudoers rules, Power Protect, or undocumented clamshell calls: root, persists after a crash, and a heat risk); a privileged helper, admin prompts, or launch agents; turning Low Power Mode on or off (needs root); a Wi-Fi network name condition (Location access); a DNS-server condition; brand-specific VPN conditions; spawning `caffeinate`; synthetic key presses or clicks of any kind; Insomnia’s lid-close extras (freezing apps, muting, writing other apps’ settings, hotspot failover, typing into terminals, relaunching browsers); macOS notifications (Snaptic uses its own notices); custom menu bar images.
- **Everywhere:** a `snaptic://` URL scheme (any web page could fire it), an HTTP server or distributed-notification commands (unauthenticated), telemetry, crash upload, licensing, and network update checks.

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
| `docs/design/` | The 0.2 and 0.3 plans and platform research. |

### How Awake keeps your Mac awake

- **One named IOKit power assertion.** Awake holds at most one sleep assertion at a time, created with `IOPMAssertionCreateWithProperties` and named “Snaptic: keeping your Mac awake”: `PreventUserIdleDisplaySleep` when the display stays on, `PreventUserIdleSystemSleep` when it may sleep. Changing the type, details, or end creates the new assertion first and then releases the old one, so there’s never a gap.
- **Backstops.** A session with an end also gets a timeout with `TimeoutActionRelease`, so macOS releases the assertion even if Snaptic were stuck; Snaptic ends sessions itself on its own continuous clock (which counts sleep and ignores clock changes).
- **No root, nothing left behind.** No `pmset`, no `caffeinate` process, no helper, no launch agent, no sudoers rule. macOS releases a process’s assertions when it exits, so a crash can’t leave your Mac unable to sleep.
- **Drive Alive** adds a separate `PreventDiskIdle` assertion while it writes; **Appear active** uses `IOPMAssertionDeclareUserActivity`; **pointer movement** posts mouse-moved events from a private event source (the only code in Snaptic that posts mouse events).
- **Rules** read system state with public APIs: `NSWorkspace` notifications, CoreGraphics display callbacks, IOKit power-source notifications and USB matching, CoreAudio device properties, `SCDynamicStore`, `sysctl` routing and interface counters, `host_statistics`, `proc_pid_rusage`, and IORegistry disk counters.
- **Holds** watch the client process with a kqueue `EVFILT_PROC` source and identify it through the command-line socket; they never signal, spawn, or wrap a command.

### Undocumented APIs

Snaptic uses private macOS functions where no public one exists. Every one is looked up at runtime (never linked), checked for the expected signature, behind a kill switch, and fails closed: if Apple removes or changes one, the feature that needs it becomes unavailable instead of crashing. This also means Snaptic can’t be sold through the Mac App Store.

- **Switcher:** `_AXUIElementGetWindow`, `_SLPSSetFrontProcessWithOptions` and `SLPSPostEventRecordTo`, `SLSMainConnectionID` and `SLSCopySpacesForWindows`, `SLSSetSymbolicHotKeyEnabled` and `SLSIsSymbolicHotKeyEnabled`, and the deprecated `GetProcessForPID`. The focusing technique follows public reverse-engineering documented by [yabai](https://github.com/koekeishiya/yabai) (MIT).
- **Displays:** DisplayServices (Apple brightness, auto-brightness), CoreBrightness (Night Shift), MonitorPanel (rotation, underscan, HDR, Apple presets), CoreGraphics `CGS…` calls (hidden modes, disconnect, HDR state), `CGVirtualDisplay` (virtual displays), `IOAVService` (DDC on Apple silicon), CoreDisplay (display info), the OSD framework, and libsystem’s process-responsibility calls for helpers.
- **Awake:** no private functions. It reads one undocumented key, `CGSSessionScreenIsLocked`, from the public `CGSessionCopyCurrentDictionary` to know whether the screen is locked.

## License

MIT. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
