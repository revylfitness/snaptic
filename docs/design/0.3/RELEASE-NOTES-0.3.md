# Snaptic 0.3 release notes

Snaptic 0.3 adds **Awake**, a free keep-awake module that replaces Amphetamine and Insomnia without an administrator password, and redesigns Settings and the menu bar. Every 0.2 setting, button, and menu item has a home in 0.3. Details are in the [README](../../../README.md).

## New: Awake

- **Sessions:** Until Turned Off, for a while (30 minutes to 30 days, or Custom…), until a time, while an app is running, and Until Downloads and Tasks Finish (ends after 5 minutes without CPU, disk, or network activity). Add time from the menu, keep the display on or let it sleep, mid-session too, and get a reminder 5 minutes before the end and after 8 hours without one.
- **Sessions in the menu:** up to 12 named session types in your order, with your default for Keep Awake and its shortcut.
- **Rules:** start Awake automatically while conditions are met: an app is open or in front, a display is connected or mirrored, power or battery state, a schedule, CPU use, audio playing or the microphone in use, idle time, a drive mounted, a USB device, an IP address, a saved network (by its router), a VPN, network activity, and Bluetooth audio or input devices (Beta). Up to 32 rules with 8 conditions each, all or any, is or is not, priorities, and waits. **Pause Rules** for an hour or until tomorrow. None of them needs a permission.
- **Guards:** end sessions when the battery is low (default 20%), when the power adapter is disconnected, or when Low Power Mode turns on. A fixed 5% battery floor and a critical-heat end always apply and can’t be turned off.
- **Appear active** (opt-in) keeps apps from marking you away, and **Move the pointer slightly** (Experimental, needs Accessibility) moves it 1 point, only for sessions you start yourself in Snaptic and never for more than the time you set (default 1 hour).
- **Drive Alive:** keeps the external drives you choose from spinning down.
- **History:** today’s and the last 7 days’ time kept awake, past sessions, and Start Again, kept on your Mac for 90 days.
- **Menu bar:** Awake’s own icon (cup, eye, or light bulb) appears while your Mac is kept awake, optionally with the time remaining or the end time. The Awake menu and the compact section in the Snaptic menu show what’s keeping your Mac awake.
- **Keyboard shortcuts:** Keep Awake, Keep Display On, the first four sessions, and Pause or Resume Rules.
- **Command line:** `snaptic awake status|start|hold|preset|extend|stop|pause`. `snaptic awake hold` keeps your Mac awake while a command or a process runs, up to 8 holds beside your own session.
- **Other apps keeping your Mac awake:** Awake › Advanced… lists other apps’ power assertions and warns when another tool left system sleep turned off.
- **For organizations:** hidden kill switches `Modules.disable.awake` and `Awake.disable.<feature>`, deployable with a configuration profile.

## Changes

- **Settings redesign.** Seven sidebar pages instead of 31: General, Menu Bar, Window Switcher, Displays, Awake, Permissions, and About. Displays’ pages are now sub-pages of one Displays page. Pages show the settings people change most; the rest are in **Advanced…** sheets. Every option says what it does, sliders have value fields you can type into, search finds every setting, including those in Advanced… sheets, and settings update live while you change them elsewhere.
- **Feature switches where features are used.** The 47-switch Display Features page is gone; each feature’s switch is at the top of its sub-page, its section, or in Displays › Advanced… › Use Snaptic for.
- **Menu bar redesign.** One pop-up per module on the new Menu Bar page, with Control Center’s choices (Always Show in Menu Bar, Show When Active, Show in Snaptic Menu, Don’t Show). Displays’ “hide when no external display is connected” is now Show When Active. Menus use one style, sliders and values update while a menu is open, there are no sliders in submenus, and Settings… and Quit are always last. Every 0.2 optional menu item keeps a place and a show or hide choice in Customize Displays Menu….
- **The right-click quick menu is gone** (macOS 27 no longer delivers right-clicks to menu bar items); its items are in Display Tools.
- **Window Switcher:** a “Switch Windows” menu item opens the switcher and keeps it open until you choose.
- **Diagnostics** moved to Displays › Display Information, and About has a Diagnostics Report.
- **Wording:** Apple’s terms throughout (display, virtual display, Picture in Picture, brightness indicator, Keep Awake).
- **`snaptic module disable awake`** and `snaptic open-settings awake` work.

## Removed, and what replaces it

- **Displays’ display sleep prevention moved to Awake.** If you used it in 0.2, 0.3 turns Awake on with a rule “While a display is connected” for the same displays, keeping the display on, and tells you once. Its shortcut moves to Awake’s Pause or Resume Rules when it can; otherwise it’s removed, with a note in Recent Notices.
- **`snaptic prevent-sleep` is retired.** It answers “Moved to Awake: use “snaptic awake …”.” with exit code 2, isn’t listed in help, and will be removed in 0.4. Use `snaptic awake start`, `snaptic awake hold`, or a rule.
- Settings that appeared in two places in 0.2 now appear in one.

## Upgrading and downgrading

- From 0.2, nothing is lost. Awake starts off with a “New: Awake” card unless your display sleep prevention moved to it. Each upgrade step runs once.
- Going back to 0.2 works: 0.2 reads your Window Switcher and Displays settings, your menu bar placement, and its own display sleep prevention as it was before the upgrade. It ignores Awake. Coming back to 0.3 doesn’t run the upgrade again, so changes made to display sleep prevention while on 0.2 aren’t carried into Awake.

## Known limitations

- Awake can’t keep a MacBook awake with its lid closed on battery, by design (it would need root). Use closed-display mode with power and an external display.
- Bluetooth conditions are Beta and see only Bluetooth audio devices and Bluetooth keyboards, mice, and trackpads. There is no Wi-Fi network name or DNS-server condition.
- Until Downloads and Tasks Finish can’t see other users’ processes, but their disk activity counts, so Spotlight or Time Machine can make a session run longer.
- Pointer movement is Experimental, and appear active may not keep every chat app from marking you away.
- Snaptic is English only.
- Not notarized yet: the first launch needs System Settings › Privacy & Security › Open Anyway.

## Hardware checks pending

0.3 was built without hardware testing. Before Beta labels change, these need a first hardware session (README, “Needs testing on hardware”):

- both assertion types, assertion swaps, the screen saver, and the lock screen on macOS 14, 15, 26, and 27, Intel and Apple silicon; lid close on battery, on power, and in closed-display mode;
- power notifications, an underpowered USB-C charger, thermal states, and the clock across sleep;
- appear active and pointer movement against chat apps and the idle lock;
- no permission prompts or indicators from the audio, Bluetooth, and router conditions;
- Drive Alive with a USB hard drive, the Removable Volumes prompt, and refused volumes;
- Until Downloads and Tasks Finish thresholds during real compiles, copies, and downloads;
- `awake hold` ending within a second of its client’s exit, in scripts and `make`, with 8 holds;
- the menu bar items, custom menu rows, and Settings on each macOS version, including notched Macs;
- hidden-configuration abuse: settings written with `defaults` must never move the pointer, skip the 5% floor, or write to ineligible drives;
- the 0.2 checks that are still open.
