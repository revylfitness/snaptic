# Snaptic

A free, open-source, Windows-style window switcher for macOS. Hold **⌥ Option**, tap **Tab**, and pick any window, not just any app.

**Website:** [snaptic.dev](https://snaptic.dev)

Snaptic is MIT-licensed and written from scratch in Swift. It isn't affiliated with or derived from AltTab; it's an independent take on the same idea, with everything included and nothing behind a paywall.

## Features

| | |
|---|---|
| **Every window** | Each window gets its own tile: several windows of one app, minimized and hidden windows, and windows on other Spaces, each with a badge. Optionally, apps with no open windows too. |
| **Recently used order** | The window you're in comes first, then windows in the order you last used them, so a quick ⌥⇥ goes back to the previous window. |
| **Thumbnails** | Previews of each window, captured with ScreenCaptureKit each time the switcher opens. |
| **Full-size preview** | The selected window is shown at its real size and position while you choose. |
| **Three styles** | Thumbnails, app icons, or a compact list of titles. |
| **Search** | Press S (or /) while the switcher is open, then type to filter by window title or app name. |
| **Auto-size** | Thumbnails are as large as fits on screen; with many windows the panel scrolls. |
| **Up to 9 shortcuts** | Each with its own keys, style and filters: all windows / active app / this screen, all Spaces / current / others, minimized and hidden windows, apps without windows, and one entry per app (like ⌘⇥). The global "Include windows on other Spaces" setting applies to shortcuts set to all Spaces. |
| **Window actions** | W closes the selected window, M minimizes or restores it, F switches to it and toggles full screen, Q quits its app (Finder only if its Quit menu item is enabled), H hides or shows its app. W, M and F work on windows on the current Space. Hovering a tile shows close / minimize / full-screen buttons too. |
| **Mouse and keyboard** | Arrows move in the grid, ⇧ goes backwards, Return switches, Esc clears the search or cancels, click to pick. Selecting by hovering is optional. |
| **Exceptions** | Hide apps from the switcher, and let virtual machines and remote desktops keep the shortcut (by default only while they're full screen). Entries match by prefix, so `com.parallels` covers every Parallels app. |
| **Multiple displays** | Opens on the screen with the active window, or the one with the mouse pointer. |
| **Light and dark** | A native translucent material that follows your system appearance. |
| **Accessible** | Selection changes are announced to VoiceOver. |
| **Private** | No network access, no telemetry, nothing written to disk except your settings and a lock file. |

### Default shortcuts

| Shortcut | What it does |
|---|---|
| ⌥ ⇥ | All windows, thumbnails |
| ⌥ (key above Tab) | Windows of the app you're in |

"Key above Tab" is detected for both US (ANSI) and European (ISO) keyboards. You can add ⌘⇥ to replace the built-in macOS switcher. Snaptic gives it back whenever it quits, whenever it can't see key presses, and on the next launch if Snaptic ever crashed. If you had already turned that shortcut off yourself, Snaptic leaves it off.

## Requirements

- macOS 14 Sonoma or later (Apple silicon or Intel)
- Xcode 15 or later, or the Xcode Command Line Tools, to build

## Download

Grab `Snaptic.zip` from the [latest release](https://github.com/revylfitness/snaptic/releases/latest), unzip it, and drag Snaptic to Applications. Releases are built by GitHub Actions from the tagged commit.

Snaptic isn't notarized by Apple yet, so the first time you open it macOS will block it. Go to System Settings → Privacy & Security and click **Open Anyway**.

## Build and run

```bash
git clone https://github.com/revylfitness/snaptic.git
cd snaptic
INSTALL=1 ./scripts/build-app.sh      # builds and copies Snaptic.app to /Applications
open /Applications/Snaptic.app
```

Leave out `INSTALL=1` to build only (`build/Snaptic.app`). For a universal Apple silicon + Intel build, which needs full Xcode, add `ARCHS="arm64 x86_64"`.

GitHub Actions compiles every push and pull request. Pushes to `main` and version tags also upload a universal `Snaptic.zip` as a workflow artifact. On public repositories a separate job, which never runs repository code, adds a build-provenance attestation. Verify that it came from this workflow on `main`:

```bash
gh attestation verify Snaptic.zip --repo revylfitness/snaptic \
  --signer-workflow revylfitness/snaptic/.github/workflows/build.yml --source-ref refs/heads/main
```

These CI builds are ad-hoc signed and not notarized, so macOS will warn before opening one. Building it yourself avoids that. Pull requests and manual runs never publish a downloadable app. Consider protecting `.github/workflows` with a branch ruleset so only reviewed workflows can attest builds.

## Permissions

On first launch macOS will ask for:

1. **Accessibility** (required). Lets Snaptic see the shortcut, list windows and bring them forward.
2. **Screen Recording** (optional). Needed for thumbnails, the full-size preview, and titles of windows on other Spaces. Without it, Snaptic shows app icons and lists only windows on the current Space.

Both are in **System Settings → Privacy & Security**. Snaptic's settings window shows their status and links to each one.

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

A stably signed build inherits its permissions automatically, so only rebuild from code you've reviewed. Anything that can use that certificate's key in your login keychain could also sign a replacement that inherits Snaptic's permissions, so keep the key's access restricted. To share builds with other people, sign with a Developer ID certificate and notarize with `xcrun notarytool`.

## Privacy and security

- **Keys.** Snaptic's keyboard tap reacts only to its own shortcuts. While the switcher is open it also reads the keys you press there (to search and for the action keys); search text is cleared when the switcher closes. Password fields use macOS Secure Event Input, which Snaptic can't see; while it's active, or whenever Snaptic's tap is off, ⌘⇥ goes back to macOS. If Snaptic ever hangs, a background guard hands ⌘⇥ back within about two seconds, and quitting Snaptic by any normal means or signal restores it.
- **Never stuck.** The switcher closes if you click elsewhere, switch apps, or change Spaces, and switches as soon as the modifier key is up even if Snaptic missed the release. If it stays open after release (searching, or "switch on release" turned off), it closes after 30 seconds without input. If the window list takes more than 2 seconds to load, it gives up. Once you've released the keys and Snaptic is only waiting for the list, other keys go straight to your app.
- **Slow or hostile apps.** Accessibility requests to other apps time out after 0.15 seconds, each app gets at most half a second and 100 windows, and listing gives up on stragglers after 1.2 seconds. None of it runs on the thread that handles the keyboard. Window titles and app names from other apps are length-limited and stripped of control and text-direction characters.
- **Thumbnails** are kept in memory only (at most 40, for at most 5 minutes). They're dropped for closed windows each time the switcher opens, never captured after it closes, and cleared when the Mac sleeps, locks or switches user. Before capturing, Snaptic checks with the window server that the window really belongs to the app it claims to. Snaptic's panels ask macOS to keep them out of screen sharing and screenshots, though some capture methods may not honor that.
- **Sensitive windows.** Windows of apps on the "never capture" list (by default 1Password, Bitwarden, Apple Passwords, Tor Browser and others) are never captured and show their app icon and name instead of their window title. You can edit the list. Private browsing is recognised only when the browser marks it in the window title, as Firefox does (in English and several other languages); those windows show "Private window" instead of their title. Safari and Chrome don't mark private windows, so add them to the list if you don't want any of their windows captured. A browser window whose title can't be read is never captured.
- **No hijacking ⌘.** ⌘ can't be combined with letters or digits, so Snaptic can never take over ⌘C, ⌘V, ⌘Q and the like. ⌥ and ⌃ can be combined with letters if you choose to. Settings edited outside the app are validated on load (shortcuts, sizes, and app identifiers, which must look like real bundle identifiers).
- **App identity.** App lists match bundle identifiers, which apps declare themselves. An app could pretend to be on the "keep the shortcut" list; at worst it would receive your switcher shortcut while it's in front.
- **One copy.** A file lock (which never follows symlinks) ensures only one copy of Snaptic runs at a time.

## How it works

| File | Responsibility |
|---|---|
| `HotkeyTap.swift` | A `CGEventTap` that watches key presses system-wide and swallows only the ones Snaptic handles. |
| `SwitcherController.swift` | The state machine: open, cycle, search, act, switch on release, and the safety nets. |
| `WindowManager.swift` | Lists windows via Accessibility (in the background) plus the window-server list, tracks window focus on its own thread for recently-used order, and focuses, closes, minimizes, hides and quits. |
| `ThumbnailStore.swift` | Captures and caches window images with ScreenCaptureKit. |
| `SwitcherModel.swift` | Filtering, fuzzy search, and the auto-size grid layout. |
| `SwitcherView.swift` / `SwitcherWindow.swift` | The SwiftUI switcher in a non-activating panel, and the full-size preview overlay. |
| `SettingsView.swift` / `Settings.swift` | Settings window and validated configuration. |
| `PrivateAPIs.swift` | The few undocumented macOS calls a switcher needs (see below). |
| `site/` | The project website at [snaptic.dev](https://snaptic.dev), deployed by Vercel on every push to `main`. |

### Undocumented APIs

Like every serious window switcher, Snaptic uses a few private macOS functions:

- `_AXUIElementGetWindow` matches Accessibility windows to window-server IDs.
- `_SLPSSetFrontProcessWithOptions` and `SLPSPostEventRecordTo` focus one specific window from a background app.
- `SLSMainConnectionID` and `SLSCopySpacesForWindows` tell real windows apart from inactive native tabs and hidden helper windows.
- `SLSSetSymbolicHotKeyEnabled` and `SLSIsSymbolicHotKeyEnabled` temporarily disable the built-in ⌘⇥ when you assign it to Snaptic.
- `GetProcessForPID` (deprecated but still present) is needed by the focusing technique.

Snaptic also loads three public Carbon functions at runtime rather than linking all of Carbon: `IsSecureEventInputEnabled`, and `LMGetKbdType` / `KBGetLayoutType` to tell ISO keyboards apart.

They're loaded at runtime from the system's SkyLight framework, so if Apple removes one, Snaptic falls back to public APIs instead of crashing. This also means Snaptic can't be sold through the Mac App Store. The focusing technique follows public reverse-engineering documented by [yabai](https://github.com/koekeishiya/yabai) (MIT).

## Known limitations

- Windows on other Spaces show their app icon rather than a thumbnail, say "Other Space" rather than which Space, and can't be closed or minimized from the switcher.
- Each shortcut uses one modifier (⌥, ⌘ or ⌃) plus one key.
- macOS Sequoia and later periodically re-confirm Screen Recording access for apps that use it. That prompt comes from macOS.
- If you close a window that asks to save first, or quit an app that asks to confirm, it disappears from the switcher until the next time you open it.
- Minimized and hidden windows show their app icon rather than a thumbnail, and thumbnails are only captured while the switcher is open.
- Show/hide filters are per shortcut for Spaces and windowless apps, but minimized and hidden windows share one toggle, and "switch on release" is global.
- No trackpad gesture, command-line tool, translations, theme override, other sort orders, title-based exceptions, or auto-updates yet.

## License

MIT. See [LICENSE](LICENSE).
