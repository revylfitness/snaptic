# Snaptic

A free, open-source menu-bar toolkit for macOS: a Windows-style **window switcher** and a set of **display utilities**. Turn on only the parts you want; everything else stays off and costs nothing.

**Website:** [snaptic.dev](https://snaptic.dev)

Snaptic is MIT-licensed and written from scratch in Swift by revyl fitness technology, Inc. It isn't affiliated with or derived from AltTab, BetterDisplay, MonitorControl or Lunar; it's an independent take on the same ideas, with everything included and nothing behind a paywall. Third-party credits are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

- [Modules](#modules) · [Window Switcher](#window-switcher) · [Displays](#displays) · [Safety](#safety)
- [Permissions](#permissions) · [Command line](#command-line) · [Install and build](#install-and-build)
- [Privacy and security](#privacy-and-security) · [Troubleshooting](#troubleshooting) · [Known limitations](#known-limitations) · [Not included](#not-included)

## Modules

| Module | What it does |
|---|---|
| **Window Switcher** | Hold **⌥ Option**, tap **Tab**, pick any window, not just any app. |
| **Displays** | Brightness and volume for external monitors, resolutions and HiDPI, color, arrangement, virtual screens, picture in picture, and more. |

**Turning things on and off**

- **Modules:** Settings → General → **Modules**. A module that is off runs nothing.
- **Displays features:** Settings → Displays → **Display Features**. Each feature has its own switch. Turning one on also turns on what it needs (with a note); turning one off says what else stops working.
- **Switcher features:** Settings → Window Switcher → **Switcher Features** (thumbnails, preview, other Spaces, search, each window action, hover buttons, ⌘⇥ takeover, exceptions).
- **First launch:** onboarding asks which tools you want and which display features to start with, then asks only for the permissions those need. It picks up where it left off if macOS makes Snaptic relaunch.
- **Upgrading from 0.1:** the switcher stays on, Displays starts off, and a "New: Displays" card points to it.

A feature that is off costs nothing: no event taps, timers, observers, IOKit handles, private-API calls, helper processes or permission prompts. Each module can share Snaptic's menu-bar icon, get its own, or be hidden (General → Menu). With every icon hidden, open Snaptic again from Finder or Spotlight to get to Settings.

## Window Switcher

| | |
|---|---|
| **Every window** | Each window gets its own tile: several windows of one app, minimized and hidden windows, and windows on other Spaces, each with a badge. Optionally, apps with no open windows too. |
| **Recently used order** | The window you're in comes first, then windows in the order you last used them, so a quick ⌥⇥ goes back to the previous window. |
| **Thumbnails** | Previews of each window, captured with ScreenCaptureKit each time the switcher opens. |
| **Full-size preview** | The selected window is shown at its real size and position while you choose. |
| **Three styles** | Thumbnails, app icons, or a compact list of titles. |
| **Search** | Press S (or /) while the switcher is open, then type to filter by window title or app name. |
| **Auto-size** | Thumbnails are as large as fits on screen; with many windows the panel scrolls. |
| **Up to 9 shortcuts** | Each with its own keys, style and filters: all windows / active app / this screen, all Spaces / current / others, minimized and hidden windows, apps without windows, and one entry per app (like ⌘⇥). |
| **Window actions** | W closes the selected window, M minimizes or restores it, F switches to it and toggles full screen, Q quits its app (Finder only if its Quit menu item is enabled), H hides or shows its app. W, M and F work on windows on the current Space. Hovering a tile shows close / minimize / full-screen buttons too. |
| **Gather windows** | Moves every window onto the display under the pointer, from the menu or a shortcut (a shortcut asks first). |
| **Mouse and keyboard** | Arrows move in the grid, ⇧ goes backwards, Return switches, Esc clears the search or cancels, click to pick. Selecting by hovering is optional. |
| **Exceptions** | Hide apps from the switcher, and let virtual machines and remote desktops keep the shortcut (by default only while they're full screen). Entries match by prefix, so `com.parallels` covers every Parallels app. |
| **Multiple displays** | Opens on the screen with the active window, or the one with the mouse pointer. |
| **Accessible** | Selection changes are announced to VoiceOver. |

| Default shortcut | What it does |
|---|---|
| ⌥ ⇥ | All windows, thumbnails |
| ⌥ (key above Tab) | Windows of the app you're in |

"Key above Tab" is detected for both US (ANSI) and European (ISO) keyboards. You can add ⌘⇥ to replace the built-in macOS switcher. Snaptic gives it back whenever it quits, whenever it can't see key presses, and on the next launch if Snaptic ever crashed. If you had already turned that shortcut off yourself, Snaptic leaves it off.

## Displays

Grouped like the settings pages. **On** = on by default once Displays is on; **Opt-in** = off until you turn it on; **Beta** = depends on hardware behavior not yet verified on every Mac; **Experimental** = off by default and labeled so.

**Always there**
- **Displays (Overview):** live controls per display (brightness, volume, resolution, input, power), Tools, and a "Show Displays Panel" action (with an optional shortcut) that opens the same controls at the pointer, even when the menu-bar icon is hidden in the overflow.
- **Display Names:** rename, pick an icon, hide from the menu, reorder; Identify (shows each display's number and name); EDID details (copy as hex or Base64); remembered displays (forget one, forget all disconnected, copy settings from another).
- **Safety:** confirmation settings, the Restore All Displays shortcut, the safety helper's status, DDC commands allowed without asking, remembered resolutions.
- **Diagnostics:** a copyable report with masked identifiers, private-API availability, kill switches, helpers and the last 200 events.

**Resolution**
- Resolution (On): modes and refresh rates, HiDPI on/off, native / default / half native, undo and redo, favorites, a menu slider with a width limit, notch-aware modes, and remembering the mode you chose.
- Show all modes (Experimental): also lists modes macOS hides.
- Match UI size (Opt-in): makes text the same size on two displays (preview, then confirm).

**Brightness**
- Brightness control (On): one slider per display, whatever the method. Methods (all On; at least one is needed): Apple native (Apple displays and built-in screens), DDC (the monitor's own backlight), software dimming with the color table (gamma), software dimming with an overlay.
- Combined range: below a switchover point the hardware stays at its minimum and software dims further.
- Restore brightness (On): after launch and wake, never below 15%.
- Opt-in: Allow dimming to black (only while another display stays visible; otherwise software dimming stops at 8%), Dim on lock, Brightness in nits, Brightness sync (other displays follow the built-in one).
- Extra brightness, XDR (Opt-in, Beta): goes past the SDR maximum on XDR and HDR displays; pauses when the Mac is hot, in Low Power Mode, on low battery and while locked.

**Color**
- Color adjustments (Opt-in): gamma, contrast, color temperature and invert in software; reset and suspend.
- Color profiles (Opt-in): pick an ICC profile per display.
- Menu-bar overlays (Opt-in): a menu-bar strip and rounded screen corners.
- Experimental: Night Shift toggle and strength (schedules stay in System Settings), Apple display presets, built-in auto-brightness toggle.

**DDC & Monitor Controls**
- Monitor controls (On): brightness, contrast and volume on the monitor itself, read from its capabilities, with per-control range tuning and optional readback.
- Opt-in: Input switching (named inputs, LG alternate inputs), Monitor power (standby / wake), Custom DDC controls (your own VCP codes, raw get and set).
- Commands that can switch the picture away or change power ask first. Manufacturer codes 0xE0–0xFF must be unlocked per display. Reset and factory codes are never sent.

**Keys & Shortcuts**
- Custom shortcuts (On): global shortcuts for any display action, including input slots. They work without Accessibility, also in password fields.
- Brightness keys and Volume keys (Opt-in, need Accessibility): the keyboard's keys drive external displays and the monitor's speakers (only monitors that report a volume control).

**On-Screen Display**
- On-screen display (On): a HUD for changes, in "Rounded" or "Classic" style, at a chosen position.
- OSD broadcast (Opt-in): lets other apps draw their own OSD from Snaptic's changes (see [Privacy](#privacy-and-security)).

**Arrangement**
- On: set the main display, arrange (canvas, plus a Position/Align form), mirror and stop mirroring.
- Rotation (Opt-in, Beta); Underscan and HDR on/off (Experimental).
- Disconnect displays (Opt-in, Beta; Experimental on Intel): turn a display off without unplugging it. Disconnect built-in display automatically (Opt-in) when an external one connects; refused unless the external monitor answers DDC with power on (or is an Apple display), and unavailable on iMacs and some base M3 models.
- Prevent display sleep (Opt-in).

**Protection & Layouts**
- Protect arrangement (Opt-in): puts the arrangement back when something else changes it (for example the macOS 27.2 arrangement-restore bug).
- Display layouts (Opt-in): save and apply layouts, optionally automatically when the same displays connect.

**Virtual Screens & HiDPI**
- Virtual screens (Opt-in, Beta): displays that exist only in software, with templates (Headless, Recording 16:9, Teleprompter, Portrait) and associations with real displays.
- Smart HiDPI (Opt-in, Beta): sharp text at any size on external displays.
- HDR virtual modes (Experimental).

**Picture in Picture**
- Picture in picture (Opt-in, needs Screen Recording): a live copy of a display or a window in a floating window (crop, click-through, orientation), or a display streamed full screen onto another.
- PIP filters (Opt-in): built-in Core Image filters and imported 3D `.cube` LUTs.

**Automation**
- Event hooks (Opt-in): run a program when a display connects or disconnects, or when the Mac sleeps or wakes.
- Custom actions (Opt-in): your own programs in the menu, as shortcuts, and (if you mark them) from the command line.

**Other display apps.** If BetterDisplay, MonitorControl or Lunar is running, Snaptic pauses its overlapping features by default ("Paused while MonitorControl runs") or runs both if you choose (General → Other Display Apps).

## Safety

Display changes can leave you without a usable screen. Snaptic is built so that never sticks.

- **"Keep this change?"** Risky changes (new resolutions, mirroring, disconnecting, rotation, HDR, first-time Smart HiDPI) show a panel on every visible display with a countdown, 15 seconds by default (10–60 in Safety). Return or ⌘K keeps; Esc, Revert or no answer puts things back. Keys work after one second, so a stray keypress can't confirm. Dimmed displays are raised to at least 30% while the panel shows.
- **A separate safety helper.** Before a risky change, Snaptic arms a small helper process. If Snaptic hangs, crashes or is killed, the helper reverts the change on its own, re-enables displays Snaptic turned off, and restores color. If the helper isn't running, risky changes are refused; anything already applied is badged "Unprotected — restart Snaptic".
- **Never the last screen.** Changes that would leave no visible display are refused. Dimming to black, disconnecting and mirroring always keep at least one display you can see.
- **Restore All Displays: ⌃⌥⌘⎋** (⌃⌥⌘⇧⎋ if the first is taken; also in the menu and as `snaptic panic`). It undoes resolution changes from the last minute, reconnects displays Snaptic turned off, removes dimming and overlays, resets color tables, stops virtual screens and streams, and pauses automation (layouts, protection, hooks, re-creation) until you choose Resume. Rotation and HDR aren't touched; they always go through the confirm panel. The shortcut can't be turned off while a display is disconnected, mirrored to a virtual screen or dimmed to black.
- **Safe Mode: hold ⇧ while Snaptic starts** (or start it with `--safe-mode`). It also starts automatically after two launches in a row that ended within a minute. Safe Mode skips brightness and color restore, virtual screens and Smart HiDPI, protection, layouts, remembered resolutions, hooks, automatic DDC writes, XDR, sleep prevention and reconnection planning. It still undoes unfinished display changes from the last run, and the switcher and your shortcuts keep working. "Leave Safe Mode" relaunches normally.
- **Journals.** Before a risky change Snaptic writes what it would take to undo it. If the Mac or Snaptic goes down mid-change, the next launch puts things back (and says so).

## Permissions

Snaptic asks only for what the features you turned on need, and only when you turn them on.

| Permission | Asked for when | Used for |
|---|---|---|
| **Accessibility** (called **Device Control and Data Access** on macOS 27) | Window Switcher is on; or Brightness keys / Volume keys; or Gather windows on first use | Seeing the switcher shortcut and media keys, listing and focusing windows. |
| **Screen Recording** (Screen & System Audio Recording) | Switcher thumbnails or preview; or Picture in Picture | Thumbnails, the full-size preview, titles of windows on other Spaces, and PIP captures. |

Both are in **System Settings → Privacy & Security**. Settings → General → Permissions shows their status and who signed the running copy ("ad-hoc" or "Developer ID …"). The permission window shows the exact app path, with "Show Snaptic in Finder" so you add *this* copy. On macOS 27 a grant often takes effect only after a relaunch; Snaptic offers "I turned it on — Relaunch Snaptic". Without Accessibility the switcher stays idle. Without Screen Recording the switcher shows app icons and only windows on the current Space. macOS Sequoia and later re-confirm Screen Recording about once a month; that prompt comes from macOS.

Most Displays features need no permission at all.

## Command line

Off by default. Turn it on in Settings → General → **Command-Line Control**.

**Install.** That page shows the command to copy, which links `snaptic` into `/usr/local/bin` (asks for your password):

```bash
sudo ln -sf '/Applications/Snaptic.app/Contents/MacOS/Snaptic' /usr/local/bin/snaptic
```

Without installing: `/Applications/Snaptic.app/Contents/MacOS/Snaptic cli help`.

**Usage.** `snaptic [--json] [--yes] <command> [arguments]`. `snaptic help` lists the commands available right now (a command appears only while its feature is on); `snaptic help <command>` narrows it. `--` ends options, so `-10` is read as a value.

- `--json`: machine-readable output (and errors as `{"exitCode": …, "error": …}`).
- `--yes`: skips the "Keep this change?" panel, but only if you also turned on "Let commands skip the confirmation panel". Otherwise the panel shows and the command waits for your answer.
- Values can be absolute (`60`), relative (`+10`, `-5`) or percentages (`50%`, `+10%`).

**Choosing a display.** `main`, `mouse` (or `pointer`), `focus`, `all`; a number from `snaptic list` (the same numbers Identify shows); `id:N` (a CoreGraphics display id); a 32-character display key; or a name (an exact match first, then a unique prefix, case-insensitive). A prefix that matches several displays exits with 2 and lists them. Commands that take an optional display default to the main one; `get …` defaults to all.

**Commands**

| Command | Feature | Notes |
|---|---|---|
| `version`, `modules`, `safe-mode` | — | Always available |
| `module disable <windowSwitcher\|displays>` | — | Off only |
| `open-settings [page]` | — | Optionally at a page id, e.g. `displays.brightness` |
| `list`, `features` | Displays | Displays: number, key, name, size, state. Features: on or off |
| `feature disable <feature>` | Displays | Off only |
| `identify`, `redetect`, `diagnostics` | Displays | Diagnostics has identifiers masked |
| `panic`, `resume` | Displays | Restore All Displays; resume automation |
| `mode list\|set\|up\|down\|hidpi\|native\|default\|halved\|undo\|redo\|notch\|favorite N <display> [WxH[@Hz] [hidpi]]` | Resolution | Confirms new modes |
| `match-ui` | Match UI size | Confirms |
| `set brightness <value> [display]`, `get brightness [display]` | Brightness control | |
| `toggle xdr [display]`, `get xdr [display]` | Extra brightness | |
| `toggle sync` | Brightness sync | Pauses or resumes |
| `set gamma\|temperature\|software-contrast <value> [display]`, `color reset\|invert\|suspend [display]` | Color adjustments | Gamma 0.5–2, temperature 1900–10000 K, contrast 0.5–1.5 |
| `toggle night-shift` | Night Shift | |
| `set volume\|contrast <value> [display]`, `get volume\|contrast\|input [display]` | Monitor controls | |
| `input <name\|hex> [display]` | Input switching | Asks on screen first unless allowed without asking |
| `ddc get <code>\|set <code> <value>\|caps [display]` | Monitor controls / power / custom | `set` asks first for codes that need it |
| `main <display>` | Set main display | |
| `arrange <display> <x> <y>`, `arrange <display> <placement> <reference>` | Arrangement | |
| `mirror <display> <source>\|off` | Mirroring | Confirms |
| `rotate <display> 0\|90\|180\|270` | Rotation | Confirms |
| `disconnect <display>` | Disconnect displays | Confirms |
| `connect all\|<display>`, `reconnect-all` | Disconnect displays | |
| `prevent-sleep off` | Prevent display sleep | Off only |
| `protect off`, `toggle protection` | Protect arrangement | Off only |
| `layout list\|apply <name\|number>\|capture <name>` | Display layouts | Apply confirms trial content |
| `virtual list\|connect <name>\|disconnect <name>` | Virtual screens | |
| `smart-hidpi off [display\|all]`, `toggle smart-hidpi [display\|all]` | Smart HiDPI | Off only |
| `pip list\|start <name\|id>\|stop <name\|id>\|stop-all\|hide-all\|show-all\|pause-all\|resume-all`, `pip start\|stop -d <display>` | Picture in picture | Saved display configurations only; starts only while unlocked. `-d` picks configurations by source display (`stop -d` also matches the target). Write `--display` only after `--`, e.g. `snaptic pip start -- --display 2` |
| `action list`, `action run <name>` | Custom actions | Only actions marked for the command line |

Verbs are case-insensitive, so `toggle nightShift` and `toggle smartHiDPI` work too.

**Never from the command line:** turning on anything off-only, and changing hooks, actions, command-line settings, sleep prevention, disconnect, auto-disconnect, dim to black, DDC unlocks, "allow without asking" choices or layout trust. Accessibility-using actions (Gather windows) are never command-line actions.

**Exit codes**

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Usage error, unknown command, or a name that matches several displays or items |
| 3 | Nothing matched (display, action, layout, configuration) |
| 4 | Refused by policy (off-only, protected setting, the safety rules) |
| 5 | Unavailable: Snaptic isn't running, command-line control is off, or the feature is off or unsupported |
| 6 | Cancelled or timed out (the confirmation was declined or expired; the client waits up to 30 s) |

**Recipes.** A Stream Deck "Run shell" or Raycast script command can call `snaptic set brightness +10 mouse`, `snaptic input "HDMI 1" 2` or `snaptic layout apply Office`.

## Install and build

### Requirements

- macOS 14 Sonoma or later (Apple silicon or Intel); supported on 14, 15, 26 and 27
- To build: Xcode 16.4 or later (the version CI uses), or its Command Line Tools

### Download

Grab `Snaptic.zip` from the [latest release](https://github.com/revylfitness/snaptic/releases/latest), unzip it, and drag Snaptic to Applications. Releases are built by GitHub Actions from the tagged commit.

Snaptic isn't notarized by Apple yet, so the first time you open it macOS will block it. Go to System Settings → Privacy & Security and click **Open Anyway**. Run it from Applications: if macOS starts it from a temporary "translocated" location, Snaptic tells you to move it first.

### Build and run

```bash
git clone https://github.com/revylfitness/snaptic.git
cd snaptic
INSTALL=1 ./scripts/build-app.sh      # builds and copies Snaptic.app to /Applications
open /Applications/Snaptic.app
```

Leave out `INSTALL=1` to build only (`build/Snaptic.app`). For a universal Apple silicon + Intel build, which needs full Xcode, add `ARCHS="arm64 x86_64"`.

`INSTALL=1` copies the app as your own user, so your account (and any program running as you) can replace it. Snaptic warns about that before you grant a permission. To install it owned by root instead:

```bash
./scripts/build-app.sh
sudo ditto build/Snaptic.app /Applications/Snaptic.app
sudo chown -R root:wheel /Applications/Snaptic.app
```

GitHub Actions compiles every push and pull request. Pushes to `main` and version tags also upload a universal `Snaptic.zip` as a workflow artifact. On public repositories a separate job, which never runs repository code, adds a build-provenance attestation. Verify that it came from this workflow on `main`:

```bash
gh attestation verify Snaptic.zip --repo revylfitness/snaptic \
  --signer-workflow revylfitness/snaptic/.github/workflows/build.yml --source-ref refs/heads/main
```

These CI builds are ad-hoc signed and not notarized, so macOS will warn before opening one. Building it yourself avoids that. Pull requests and manual runs never publish a downloadable app. Consider protecting `.github/workflows` with a branch ruleset so only reviewed workflows can attest builds.

### Signing and permissions

The build script always signs with the **hardened runtime** and refuses to finish if it's missing. This stops other programs from injecting code into Snaptic to borrow its permissions. By default it signs ad hoc, and macOS ties permissions to that exact build, so after a rebuild you'll need to grant Accessibility again. Do that cleanly:

```bash
tccutil reset Accessibility app.snaptic.Snaptic
codesign -dv /Applications/Snaptic.app      # check it's the build you just made, then grant access
```

Signing with your free Apple Development certificate keeps permissions across rebuilds:

```bash
security find-identity -v -p codesigning
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" INSTALL=1 ./scripts/build-app.sh
```

A stably signed build inherits its permissions automatically, so only rebuild from code you've reviewed. Anything that can use that certificate's key in your login keychain could also sign a replacement that inherits Snaptic's permissions, so keep the key's access restricted.

**Why Developer ID builds are recommended.** Snaptic's helpers (the safety helper and virtual-screen hosts) check that they were started by Snaptic, and Snaptic checks each helper, by code signature. With an ad-hoc build that signature is the exact build, so permissions are lost on every update and, after updating in place, helpers are refused until you restart Snaptic ("Restart Snaptic to finish updating"). A Developer ID signature (team plus identifier) survives updates and can be notarized. To share builds with other people, sign with a Developer ID certificate and notarize with `xcrun notarytool`.

## Privacy and security

**No network.** Snaptic never connects to the network: no telemetry, no crash upload, no update checks ("Check for Updates…" opens the Releases page in your browser). A lint check rejects networking APIs in the source.

**What never leaves the process.** Window pixels, window titles, app names and key presses. The command line, hooks, diagnostics and the event log never carry them. Diagnostics mask serial numbers; display keys are salted per Mac and the salt is never exported.

**What leaves on purpose.**
- *OSD broadcast* (opt-in) posts a system-wide notification `app.snaptic.osd` with only the kind (brightness, volume, …), the value and the maximum, at most 10 per second, and nothing while the screen is locked.
- *Hooks and custom actions* (opt-in) run programs you chose, with a minimal environment (`SNAPTIC_EVENT`, `SNAPTIC_DISPLAY_NAME`, `SNAPTIC_DISPLAY_KEY`), without Snaptic's permissions, stopped after 30 seconds. Programs must be absolute paths owned by you or root and not writable by others. Never in Safe Mode or while automation is paused.

**On disk.** Settings (in Snaptic's preferences), and under `~/Library/Application Support/Snaptic/` (0700): the single-instance lock, the command-line socket, undo journals for display changes, and copies of imported LUTs. Backup export leaves out hooks, actions, command-line settings, the salt, DDC unlocks, "allow without asking" choices, layout trust, and sensitive switches (disconnect, auto-disconnect, dim to black, sleep prevention); import strips them even if present.

**Command line.** Only your user account can connect, through a private socket (directory 0700, socket 0600); Snaptic never listens on the network. Requests are size-, rate- and time-limited. See [Command line](#command-line) for what it can never change.

**Helpers.** The safety helper and virtual-screen hosts are copies of Snaptic's own executable, started with an empty environment and their own process responsibility, so they hold none of Snaptic's permissions. Each side checks the other's code signature.

**Picture in Picture.** Display captures never include Snaptic itself, Notification Center or apps on the protected list; browser windows marked private (Firefox, Edge, Chrome's Incognito title) and untitled browser windows are left out. Locking or sleeping the Mac stops captures and clears their last frame. Snaptic never starts a capture by itself.

**Overlays vs password prompts.** While a password or authentication window is on screen, Snaptic orders out full-screen dimming overlays and raises dim-to-black to at least 30%. This is best effort.

**Window Switcher.**
- **Keys.** Snaptic's keyboard tap reacts only to its own shortcuts. While the switcher is open it also reads the keys you press there (to search and for the action keys); search text is cleared when the switcher closes. Password fields use macOS Secure Event Input, which Snaptic can't see; while it's active, or whenever Snaptic's tap is off, ⌘⇥ goes back to macOS. If Snaptic ever hangs, a background guard hands ⌘⇥ back within about two seconds, and quitting Snaptic by any normal means or signal restores it.
- **Never stuck.** The switcher closes if you click elsewhere, switch apps, or change Spaces, and switches as soon as the modifier key is up even if Snaptic missed the release. If it stays open after release (searching, or "switch on release" turned off), it closes after 30 seconds without input. If the window list takes more than 2 seconds to load, it gives up.
- **Slow or hostile apps.** Accessibility requests to other apps time out after 0.15 seconds, each app gets at most half a second and 100 windows, and listing gives up on stragglers after 1.2 seconds. Window titles and app names from other apps are length-limited and stripped of control and text-direction characters.
- **Thumbnails** are kept in memory only (at most 40, for at most 5 minutes), never captured after the switcher closes, and cleared when the Mac sleeps, locks or switches user. Snaptic's panels ask macOS to keep them out of screen sharing and screenshots, though some capture methods may not honor that.
- **Sensitive windows.** Windows of apps on the "never capture" list (by default 1Password, Bitwarden, Apple Passwords, Tor Browser and others) are never captured and show their app icon and name instead of their title. Safari and Chrome don't mark private windows, so add them to the list if you don't want any of their windows captured.
- **No hijacking ⌘.** ⌘ can't be combined with letters or digits, so Snaptic can never take over ⌘C, ⌘V, ⌘Q and the like.
- **App identity.** App lists match bundle identifiers, which apps declare themselves. An app could pretend to be on the "keep the shortcut" list; at worst it would receive your switcher shortcut while it's in front.

**Startup checks.** Snaptic accepts only its own launch arguments, refuses to start with code-injection-style environment variables (`DYLD_*`, `OBJC_*`, `NS*`, `CF*`, `Malloc*` and similar) or a `HOME` that isn't your account's, reads settings only from its own preferences (not command-line or managed overrides), and runs one copy at a time.

## Hidden kill switches

Every Displays feature can be force-disabled with a hidden default, read once when Displays starts. Use this if a feature misbehaves on your Mac and you can't reach Settings:

```bash
defaults write app.snaptic.Snaptic Displays.disable.xdr -bool true      # feature ids as in `snaptic features`
defaults write app.snaptic.Snaptic Displays.disable.symbol.MPDisplay -bool true   # one private API
defaults delete app.snaptic.Snaptic Displays.disable.xdr                # undo
```

Feature ids: `resolution`, `hiddenModes`, `scaleMatch`, `brightness`, `brightnessApple`, `brightnessDDC`, `brightnessGamma`, `brightnessOverlay`, `brightnessRestore`, `dimToBlack`, `dimOnLock`, `nits`, `xdr`, `sync`, `autoBrightness`, `color`, `colorProfiles`, `nightShift`, `applePresets`, `ddcControls`, `ddcInput`, `ddcPower`, `ddcCustom`, `brightnessKeys`, `volumeKeys`, `shortcuts`, `osd`, `osdBroadcast`, `mainDisplay`, `arrangement`, `mirroring`, `rotation`, `underscan`, `hdrToggle`, `disconnect`, `autoDisconnectBuiltin`, `sleepPrevention`, `protection`, `layouts`, `virtualScreens`, `smartHiDPI`, `hdrVirtual`, `pip`, `pipFilters`, `menuBarOverlays`, `hooks`, `customActions`. Kill switches only turn things off, restart Displays (or Snaptic) to apply them, and Diagnostics lists the ones that are set.

## Troubleshooting

- **A display went black or the picture is wrong.** Wait 15 seconds without pressing anything; unconfirmed changes revert. Otherwise press **⌃⌥⌘⎋** (or ⌃⌥⌘⇧⎋). If Snaptic won't start cleanly, hold **⇧** while opening it for Safe Mode.
- **Permission is on but Snaptic still asks.** Remove Snaptic from the list with −, add it again with + (use "Show Snaptic in Finder" to pick the right copy), then relaunch. After rebuilding an ad-hoc build, run `tccutil reset Accessibility app.snaptic.Snaptic` first.
- **"Restart Snaptic to finish updating" / "Unprotected".** Snaptic was replaced while running, so its helpers are refused. Quit and reopen it.
- **A monitor doesn't respond to brightness or volume.** Many TVs, DisplayLink adapters, some docks and the HDMI port on some Macs don't pass DDC; Snaptic dims those in software instead. DDC & Monitor Controls shows whether each display answers.
- **A feature shows "Paused while … runs".** Another display app is running. Quit it, or choose "Run both anyway" in General → Other Display Apps.
- **No menu-bar icon.** macOS may hide it in the overflow. Open Snaptic again from Finder or Spotlight to get Settings, or use the "Show Displays Panel" shortcut if you set one.
- **`snaptic` says it isn't running.** Turn on Settings → General → Command-Line Control (exit code 5 means Snaptic isn't running, control is off, or the feature is off).
- **Filing an issue.** Copy the report from Displays → Diagnostics (or `snaptic diagnostics`). It has no window titles, app names or serial numbers.

## Known limitations

- **Switcher:** windows on other Spaces show their app icon rather than a thumbnail, say "Other Space" rather than which Space, and can't be closed or minimized from the switcher. Each shortcut uses one modifier (⌥, ⌘ or ⌃) plus one key. If you close a window that asks to save first, or quit an app that asks to confirm, it disappears from the switcher until the next time you open it. Minimized and hidden windows show their app icon. Minimized and hidden windows share one toggle, and "switch on release" is global.
- **Displays:** EDID-based display names are read on Intel Macs only. The panic confirmation is a toast, not a full HUD. A display "captured" by another app (a full-screen game) refuses changes and the confirm panel. Brightness sync notices changes made with a monitor's own buttons only when DDC readback is on. Auto-disconnect reads the lid state when it plans, and can't detect a monitor in standby or on another input. "Disconnect on lock" ignores the screen saver. Virtual-screen primaries come from EDID only (no ICC fallback). "Stream onto" associations ask rather than start. On macOS 27 the system's own HUD also shows at the top right, so the two OSDs can overlap; the OSD defaults to top center there.
- **Picture in Picture:** Safari doesn't mark private windows (add Safari to the protected apps). Window sources are picked in the system picker each time, so they can't start automatically or from the command line. Imported LUTs aren't included in Backup. The cursor can't be excluded from streams, and filters can't be applied to a stream of the display itself.
- **General:** no translations yet, no trackpad gesture, no auto-updates.

### Needs testing on hardware

0.2 was built without hardware testing; these depend on hardware behavior and are marked Beta or verified at runtime (a wrong guess turns the feature off rather than misbehaving):

- Confirmed changes persisting across quit, relaunch and reboot; the safety helper reverting after `kill -9` with virtual screens and a pending change; rotation and HDR reverts after a reboot.
- XDR extra brightness on M1–M5 XDR panels; gamma on virtual screens on M5.
- DDC over Apple silicon USB-C and HDMI, MCDP adapters and Intel; standby and wake through DDC.
- Brightness and volume keys on Apple silicon laptops on macOS 26 and 27; global shortcuts while a password field is focused.
- Virtual screens and Smart HiDPI: HiDPI at creation, changing modes live, behavior after lock, sleep and Fast User Switching, lid closed with no external display, EDID colors on Apple silicon.
- Picture in Picture: capture filters, window crop orientation, the content-sharing picker on 14, 15 and 26.
- Helper signature checks with ad-hoc and Developer ID builds, and after an in-place update; Accessibility grants and relaunch on macOS 27.
- Detecting password windows on macOS 26 without Screen Recording; Identify labels over full-screen apps and AirPlay.

## Not included

**Deferred** (may come later): system display overrides (scaled resolutions, display names, TV roles), connection color mode and direct XDR control, framebuffer grayscale/invert and keyboard-backlight keys, 3D LUTs on displays and compositor filters, App Intents / AppleScript / URL scheme (the command line covers Shortcuts), HDMI-CEC, network TVs and receivers, DisplayLink control, HTTP-based Stream Deck plugins, True Tone and Dark Mode control, nits-normalized sync, SDR/HDR automatic profile switching, ranged custom controls with readback, PIP tabs and magnification above 100%, virtual-screen identity editing, localization, swapping identical displays, Sidecar management, sidebar and detachable menus.

**Excluded by design:** EDID writing or overrides (can brick or blank a monitor); reinitializing displays, VMM7100 resets, forced HDR, dithering and similar private framebuffer tricks (blank screens); an HTTP server or distributed-notification commands (unauthenticated); NVRAM resets and factory profile removal (destructive, need root); model-specific adaptations; telemetry, crash upload, licensing and network update checks.

## How it works

| Path | Responsibility |
|---|---|
| `Sources/SnapticKit/` | Pure logic with unit tests that also run on Linux: the feature graph, configuration, safety invariants, DDC and EDID parsing, the command-line protocol. |
| `Sources/SnapticShims/` | Small Objective-C wrappers for private display APIs, each checked before use. |
| `Sources/Snaptic/Core/` | The host: modules, settings, menus, permissions, onboarding, Safe Mode, the command-line server and client, helper spawning. |
| `Sources/Snaptic/Switcher/` | The window switcher (event tap, window list, thumbnails, switcher UI). |
| `Sources/Snaptic/Displays/` | The Displays module: services, one controller per feature group, the safety helper, transactions and journals, settings pages. |
| `site/` | The project website at [snaptic.dev](https://snaptic.dev). |
| `docs/design/` | The 0.2 plan and platform research. |

### Undocumented APIs

Snaptic uses private macOS functions where no public one exists. Every one is looked up at runtime (never linked), checked for the expected signature, behind a kill switch, and fails closed: if Apple removes or changes one, the feature that needs it becomes unavailable instead of crashing. This also means Snaptic can't be sold through the Mac App Store.

- **Switcher:** `_AXUIElementGetWindow`, `_SLPSSetFrontProcessWithOptions` / `SLPSPostEventRecordTo`, `SLSMainConnectionID` / `SLSCopySpacesForWindows`, `SLSSetSymbolicHotKeyEnabled` / `SLSIsSymbolicHotKeyEnabled`, and the deprecated `GetProcessForPID`. The focusing technique follows public reverse-engineering documented by [yabai](https://github.com/koekeishiya/yabai) (MIT).
- **Displays:** DisplayServices (Apple brightness, auto-brightness), CoreBrightness (Night Shift), MonitorPanel (rotation, underscan, HDR, Apple presets), CoreGraphics `CGS…` calls (hidden modes, disconnect, HDR state), `CGVirtualDisplay` (virtual screens), `IOAVService` (DDC on Apple silicon), CoreDisplay (display info), the OSD framework, and libsystem's process-responsibility calls for helpers.

## License

MIT. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
