<div align="center">

<img src="Resources/AppIcon.png" width="128" height="128" alt="Snaptic app icon">

# Snaptic

**A free, open-source menu bar toolkit for macOS.**

Switch between windows, not apps · Take charge of every display · Keep your Mac awake · Tidy up the menu bar

[![Latest release](https://img.shields.io/github/v/release/revylfitness/snaptic?label=release&color=0a84ff)](https://github.com/revylfitness/snaptic/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)](#install)
[![License: MIT](https://img.shields.io/badge/license-MIT-34c759)](LICENSE)
[![Downloads](https://img.shields.io/github/downloads/revylfitness/snaptic/total?color=8e8e93)](https://github.com/revylfitness/snaptic/releases)

[**Download**](https://github.com/revylfitness/snaptic/releases/latest/download/Snaptic.dmg) · [Website](https://snaptic.dev) · [Guide](docs/guide.md) · [What’s new in 0.4](docs/design/0.4/RELEASE-NOTES-0.4.0.md)

</div>

<br>

Snaptic puts four everyday Mac utilities into one small, native app. Each one is optional: turn on only what you want, and a module that’s off runs nothing at all. No event taps, no timers, no permission prompts.

| Module | What it does |
|---|---|
| **[Window Switcher](#window-switcher)** | Hold **⌥ Option**, tap **Tab**, and pick any window, not just any app. |
| **[Displays](#displays)** | Brightness and volume for external displays, resolutions and HiDPI, color, arrangement, virtual displays, Picture in Picture, and more. |
| **[Awake](#awake)** | Keeps your Mac awake for a while, until a time, while an app runs, or until downloads finish. No administrator password. |
| **[Hidden Icons](#hidden-icons)** | Tucks the menu bar icons you don’t need behind an arrow. |

Everything is included and nothing is behind a paywall. No accounts, telemetry, or analytics.

## Install

1. Download **[Snaptic.dmg](https://github.com/revylfitness/snaptic/releases/latest/download/Snaptic.dmg)** from the [latest release](https://github.com/revylfitness/snaptic/releases/latest).
2. Drag Snaptic into Applications, and open it from there.
3. Choose the modules you want. Snaptic asks only for the permissions those modules need.

Snaptic runs on **macOS 14 Sonoma or later**, on Apple silicon and Intel. Releases are signed with a Developer ID and notarized by Apple, and they keep themselves up to date with [Sparkle](https://sparkle-project.org), but only if you allow it.

> [!NOTE]
> On 0.3.1 or earlier, download the latest release by hand once: 0.3.0 and earlier can’t update themselves, and 0.3.1 doesn’t start. Snaptic updates itself after that, and macOS asks you to allow Accessibility and Screen Recording again one time. See [Upgrading and downgrading](docs/guide.md#upgrading-and-downgrading).

## Window Switcher

A Windows-style switcher that shows every window, not just every app.

- **Every window gets a tile.** That includes several windows of one app, minimized and hidden windows, and windows on other Spaces, in the order you last used them. A quick ⌥⇥ goes back to the previous window.
- **Thumbnails, icons, or a list.** Choose live thumbnails with a full-size preview, app icons, or a compact list of titles.
- **Search.** Press **S** or **/** and type to filter by window title or app name.
- **Window actions.** Press **W** to close, **M** to minimize, **F** for full screen, **Q** to quit, and **H** to hide.
- **Up to 9 shortcuts.** Each has its own style and filters: this app, this screen, this Space, or one entry per app. You can also take over ⌘⇥, and Snaptic gives it back whenever it quits.

| Default shortcut | Shows |
|---|---|
| ⌥ ⇥ | All windows, as thumbnails |
| ⌥ key above Tab | Windows of the app you’re in |

[Read more in the Window Switcher guide →](docs/guide.md#window-switcher)

## Displays

Controls for every display you connect, laid out like the Displays page in Settings. Features that depend on your hardware are marked Beta, and risky changes always ask **“Keep this change?”** first (see [Safety](#safety)).

### The Displays page

A card for each display shows its brightness, resolution, and refresh rate. From here you can pick resolutions and HiDPI modes, including ones macOS hides, set the arrangement and mirroring, disconnect a display without unplugging it, match text size across displays, and open Display Tools. [More →](docs/guide.md#the-displays-page)

### Brightness and Dimming

One slider per display, whatever the method: Apple’s own brightness, the display’s own backlight over DDC, or software dimming beyond the hardware minimum. Snaptic can also sync brightness across displays, dim when the screen locks, and go past SDR brightness on XDR displays. [More →](docs/guide.md#brightness-and-dimming)

### Color

Software contrast, gamma, temperature, and black and white levels, per display or for all of them, plus an ICC profile picker. [More →](docs/guide.md#color)

### Hardware Controls

Brightness, contrast, and volume on the display itself, over DDC. Input switching, power control, and custom VCP codes are opt-in. Commands that could blank the picture ask first. [More →](docs/guide.md#hardware-controls)

### Keyboard

Your keyboard’s brightness and volume keys can drive external displays and their speakers, with a brightness HUD in your choice of style. You can also set global shortcuts for any display action. [More →](docs/guide.md#keyboard)

### Saved Layouts

Save an arrangement and apply it by hand or when the same displays connect. **Protect arrangement** puts it back if something else changes it. [More →](docs/guide.md#saved-layouts)

### Virtual Displays

Displays that exist only in software: headless, recording, teleprompter, and portrait templates, plus Smart HiDPI for sharp text at any size. [More →](docs/guide.md#virtual-displays)

### Picture in Picture

Show a live copy of a display or window in a floating window, or stream one display full screen onto another, with filters and `.cube` LUTs. [More →](docs/guide.md#picture-in-picture)

### Automations

Run your own programs when a display connects or disconnects, or when the Mac sleeps or wakes. Put custom actions in the menu, on shortcuts, or on the command line. [More →](docs/guide.md#automations)

### Display Information

A live report on your displays for bug reports, with names and serial numbers left out. It also shows the safety helper’s status, EDID export, and the displays and resolutions Snaptic remembers. [More →](docs/guide.md#display-information)

## Awake

Keeps your Mac awake while you want it awake, using the same public power assertion as `caffeinate`. It needs no password, installs nothing, and leaves nothing behind. If Snaptic quits or crashes, macOS releases the assertion at once.

- **Sessions.** Until you turn it off, for a while, until a time, while an app is running, or **until downloads and tasks finish**. You choose whether the display stays on, and you can add time while a session runs.
- **Rules.** Start automatically while conditions you choose are met: an app is open, a display is connected, you’re on power, a schedule, CPU, audio, network, USB, VPN, and more. None of them needs a permission.
- **Guards.** Awake never drains your battery or cooks your Mac. Sessions always end below 5% battery or when your Mac gets very hot, and you can also end them on low battery, when the adapter is unplugged, or in Low Power Mode.
- **Appear active.** Opt-in options tell macOS you’re still there, for apps that mark you away when you don’t touch the Mac.
- **History.** Today and the past 7 days, kept on your Mac only.
- **From scripts.** `snaptic awake hold` keeps your Mac awake while a command runs (see [Command line](#command-line)).

[Read more in the Awake guide →](docs/guide.md#awake) · [Switching from Amphetamine or Insomnia →](docs/guide.md#switching-from-amphetamine-or-insomnia)

### Drive Alive

Keeps external drives from spinning down, so opening and saving files doesn’t pause. Every couple of minutes, Snaptic rewrites a hidden 8-byte `.snaptic-keepalive` file on each drive you turn on. Nothing else on the drive is read or changed, and turning a drive off removes the file. Only external, local, writable drives qualify. [More →](docs/guide.md#drive-alive)

### Keeping awake with the lid closed

A MacBook goes to sleep when you close its lid, whatever an app asks for. There are two ways around that:

- **Closed-display mode** is built into macOS and needs no password. Connect power, an external display, and a keyboard or mouse, then close the lid.
- **Lid-closed mode** is opt-in, on Macs with a battery. It keeps a MacBook awake with its lid closed, even on battery with no external display. macOS allows that only with root, so Snaptic asks for an administrator password **each time** you turn it on. Nothing is installed and nothing lasting is granted: no helper, no launch agent, and no sudoers rule.

> [!WARNING]
> **Use it on a hard surface, not in a bag.** While lid-closed mode is on, your Mac can’t sleep for low battery or heat, so Snaptic and its watchdog both watch for those.

**Turning it on.** Turn on **Awake › Lid closed › Keep awake with the lid closed**. Then choose **Keep Awake with the Lid Closed ›** and a session in the Awake menu, and enter an administrator password. Only you can turn it on, in Snaptic’s own menus and Settings. The command line, rules, shortcuts, and imported backups never can.

**It won’t start** on battery below your battery limit plus 5%, while your Mac is hot, or while Snaptic runs from a temporary location.

**It turns itself off** at your battery limit (at least 10%) or when your Mac gets hot. It also turns off after 24 hours, when the session ends, and when Snaptic quits, stops responding, or crashes. If the lid is closed then, your Mac goes to sleep. Turning it off never asks for a password.

[Full details: limits, what you see, and known limits →](docs/guide.md#keeping-awake-with-the-lid-closed)

#### If sleep stays off

`SleepDisabled` survives a restart. Sleep stays off until you decide if your Mac loses power or restarts while lid-closed mode is on, or if turning sleep back on fails. At the next launch, even with Awake off or in Safe Mode, Snaptic shows **Sleep Is Turned Off** at the top of every Snaptic menu and on the Awake page:

- **Turn Sleep Back On…** asks for an administrator password and runs only `pmset -a disablesleep 0`.
- **Keep Sleep Off** leaves it off without a password. It’s only in Settings, because undoing it needs Terminal.
- **Not Now** hides the rows until Snaptic next starts.

Snaptic never changes a `SleepDisabled` that it didn’t set itself. A value another app left is reported, never changed. You can always check and fix it yourself:

```bash
pmset -g | grep SleepDisabled      # 1 means sleep is turned off for the whole Mac
sudo pmset -a disablesleep 0       # turn system sleep back on
```

#### Your password and what runs as root

- **What runs as root.** Snaptic runs a short shell script as root, but only while lid-closed mode is on or when you choose Turn Sleep Back On…. Its full text is in [`Sources/SnapticKit/LidWatchdog.swift`](Sources/SnapticKit/LidWatchdog.swift). It changes only `SleepDisabled` (`pmset -a disablesleep 1`, then `0`). It may also run `pmset sleepnow` when sleep is back on, the lid is closed, and your Mac isn’t shutting down. It turns sleep back on when the session ends, when Snaptic quits or stops responding (it checks every 5 seconds), at the battery limit, when your Mac gets hot, after 24 hours, or if the script itself fails. It never reads, writes, or deletes the contents of your files. It only checks a few small files Snaptic keeps in your temporary folder: a heartbeat, a stop file, and a halt file when your Mac is shutting down or logging out.
- **How it starts.** `/usr/bin/osascript` asks macOS for an administrator password, then starts the script, which keeps running as a watchdog after the dialog closes. The script gets a minimal environment and calls every program by its full path.
- **The dialog names osascript, not Snaptic.** Any app can show this dialog with any text. Only enter your password right after you choose **Keep Awake with the Lid Closed**, **Turn Sleep Back On…**, or **Install and Relaunch** (in Snaptic’s About page or Sparkle’s update window).
- **If your account can change Snaptic**, which is the default after you drag it to Applications, that advice isn’t enough. A program running as you could change Snaptic so that its own prompt runs something else as root. Snaptic says so under the setting. To close that gap, install Snaptic owned by root: build with `INSTALL=1`, or for a downloaded copy run `sudo chown -R root:wheel /Applications/Snaptic.app`. Each update then asks for an administrator password (see [Updates](docs/guide.md#updates)). Snaptic warns rather than refuses, because the same program could show the identical dialog without touching Snaptic, and refusing would remove the feature from the default install. A translocated copy is refused.
- **What a program running as you can do:**
  - Turn sleep back on, by creating the watchdog’s stop file or deleting its heartbeat file.
  - Stop the watchdog from putting your Mac to sleep when lid-closed mode ends with the lid closed, by creating its halt file.
  - Keep lid-closed mode going while Snaptic is hung, but only while Snaptic’s process is still running. The 24-hour limit, the battery limit, and heat still end it, and the watchdog enforces those on its own.

  It can’t turn lid-closed mode on without you typing a password into a dialog.
- **Power loss or a restart while it’s on:** sleep stays off until you choose Turn Sleep Back On… or Keep Sleep Off (see [If sleep stays off](#if-sleep-stays-off)).
- **Security software** may flag “osascript with administrator privileges”. Release builds are signed with a Developer ID, which removes one of the conditions such rules look for.

## Hidden Icons

Click the arrow **‹** to hide the menu bar icons to its left, and click it again to show them. Hidden Icons is off until you turn it on, and nothing hides until you click the arrow for the first time.

Snaptic never moves another app’s icon. You arrange icons yourself by holding **⌘** and dragging them in the menu bar:

```
macOS 14–26                                      macOS 27
  ⋮  [A] [B]  |  [C] [D]  ‹  [E] [S]  ◷ 9:41       ⋮  [A] [B]  [C] [D]  ‹  [E] [S]  ◷ 9:41
  └always┘   └─hidden─┘     └shown─┘               └always┘   └hidden─┘     └shown─┘
```

- **Open a hidden icon without showing them all**, from the list in the Snaptic menu.
- **Hide automatically** after a few seconds, show on hover, use an **Always Hidden** section (Option-click the arrow), or set a shortcut.
- **Always Show or Always Hide** an app’s icons, on macOS 27.
- **It fails safe.** Whenever Snaptic can’t be sure hiding is safe, your icons are shown. If Snaptic quits, crashes, or is force quit, they come back within about 2 seconds.
- **Camera and microphone dots stay visible.** On macOS 27, your icons are shown while an app uses the camera or microphone, then hidden again afterwards.

On macOS 27, Snaptic asks macOS itself to hide icons and needs Accessibility. On macOS 14–26, it widens a divider to push hidden icons off the screen, and hiding needs no permission. While Hidden Bar, Bartender, Ice, or Thaw runs, Hidden Icons pauses.

[Read more in the Hidden Icons guide →](docs/guide.md#hidden-icons) · [Switching from Hidden Bar →](docs/guide.md#switching-from-hidden-bar)

## Settings

Settings has a page for each module, plus General, Menu Bar, Permissions, and About. The search field finds any setting, even the ones tucked into **Advanced…** sheets. Every slider has a value field, and each page’s **Restore Defaults…** resets only that page. [More →](docs/guide.md#settings)

### General

A switch for each module, Open at login, command-line control, and export and import of your settings. **Advanced…** has Restart in Safe Mode… and Reset All Settings…. [More →](docs/guide.md#general)

### Menu Bar

For each module, choose whether it’s always in the menu bar, shown only while it’s active, kept in the Snaptic menu, or hidden. You can also choose each icon. With two or more modules in the Snaptic menu, each one gets its own tab (⌘1–⌘4). [More →](docs/guide.md#menu-bar)

## Permissions

Snaptic asks only for what the features you turned on need, and only when you turn them on. The Permissions page shows each permission’s status.

| Permission | Needed for |
|---|---|
| **Accessibility** (Device Control and Data Access on macOS 27) | The window switcher, brightness and volume keys, Awake’s pointer movement, and Hidden Icons on macOS 27 (on 14–26, only its hidden-icon list). |
| **Screen Recording** | Switcher thumbnails and preview, and Picture in Picture. |
| **Removable Volumes** | Drive Alive, the first time it writes to a drive. |

Most Displays features need no permission at all, and Awake needs none for sessions, rules, or guards. Lid-closed mode asks for an administrator password each time instead. [More →](docs/guide.md#permissions)

## Safety

Display changes can leave you without a usable screen. Snaptic is built so that never sticks.

- **“Keep this change?”** Risky changes show a countdown on every display, and revert unless you confirm.
- **A separate safety helper** undoes a change if Snaptic hangs, crashes, or is killed.
- **Never the last screen.** Snaptic refuses any change that would leave you with no visible display.
- **Restore All Displays: ⌃⌥⌘⎋.** This undoes recent resolution changes, reconnects displays, and removes dimming and color changes.
- **Safe Mode:** hold **⇧** while Snaptic starts.
- **Awake can’t drain your battery or overheat your Mac**, and **Hidden Icons shows your icons** whenever it can’t be sure.

[Read more about safety →](docs/guide.md#safety)

## Privacy

- **No telemetry, analytics, or crash uploads.** The only network traffic is the update check, once a day and only if you allow it. GitHub sees your IP address, Snaptic’s version, and your macOS version.
- **Window pixels, window titles, app names, and key presses never leave the process.** They stay out of logs, diagnostics, and the command line.
- **The command line is private.** It’s a socket only your account can reach, and Snaptic never listens on the network.

[Read more about privacy and security →](docs/guide.md#privacy-and-security)

## Command line

Turn on **Settings › General › Command-line control**, and you can run Snaptic from scripts, Stream Deck, or Raycast:

```bash
snaptic set brightness +10 mouse        # brighter, on the display under the pointer
snaptic input "HDMI 1" 2                # switch display 2's input
snaptic layout apply Office             # apply a saved layout
snaptic awake start 2h                  # keep awake for two hours
snaptic awake hold --pid $$             # keep awake while this script runs
snaptic icons toggle                    # show or hide menu bar icons
```

`snaptic help` lists the commands available right now, and `--json` gives machine-readable output. [Full command reference →](docs/guide.md#command-line)

## Build from source

You need Xcode 16.4 or later, or its Command Line Tools.

```bash
git clone https://github.com/revylfitness/snaptic.git
cd snaptic
INSTALL=1 ./scripts/build-app.sh      # builds and installs Snaptic.app to /Applications, owned by root
open /Applications/Snaptic.app
```

Leave out `INSTALL=1` to build only (`build/Snaptic.app`). Run the unit tests with `swift test`, which also works on Linux. A build from source has no updater. [Signing and permissions for local builds →](docs/guide.md#signing-and-permissions)

## Documentation

The **[Guide](docs/guide.md)** covers every setting, command, and safety rule. Good places to start:

- [Troubleshooting](docs/guide.md#troubleshooting) · [Known limitations](docs/guide.md#known-limitations) · [Not included](docs/guide.md#not-included)
- [Updates](docs/guide.md#updates) · [Upgrading and downgrading](docs/guide.md#upgrading-and-downgrading) · [Hidden kill switches](docs/guide.md#hidden-kill-switches)
- [How it works](docs/guide.md#how-it-works) · [Undocumented APIs](docs/guide.md#undocumented-apis) · [If a release key leaks](docs/guide.md#if-a-release-key-leaks)
- Release notes: [0.4.0](docs/design/0.4/RELEASE-NOTES-0.4.0.md) · [0.3.1](docs/design/0.3.1/RELEASE-NOTES-0.3.1.md) · [0.3](docs/design/0.3/RELEASE-NOTES-0.3.md)

Found a bug? Copy the report from **Displays › Display Information** (or run `snaptic diagnostics`) and [open an issue](https://github.com/revylfitness/snaptic/issues). The report leaves out window titles, app names, and serial numbers.

## Credits and license

Snaptic is written from scratch in Swift by revyl fitness technology, Inc. It isn’t affiliated with or derived from AltTab, BetterDisplay, MonitorControl, Lunar, Amphetamine, or Insomnia; it’s an independent take on the same ideas. Hidden Icons follows the design of [Hidden Bar](https://github.com/dwarvesf/hidden) (MIT) in its own code, and isn’t affiliated with it either. Third-party credits are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Released under the [MIT License](LICENSE).
