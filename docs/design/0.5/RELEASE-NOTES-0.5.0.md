# Snaptic 0.5.0

**New: Dock Previews.** Point at an app in the Dock, and its windows appear next to the Dock, including minimized and hidden ones. Click one to bring it forward. It is off until you turn it on, and without Screen Recording it shows window titles instead of pictures. The Window Switcher gets thumbnails of minimized windows and windows on other Spaces too. Details are in the [README](https://github.com/revylfitness/snaptic/blob/main/README.md#dock-previews).

## New: Dock Previews

- **Off by default.** Turn it on with **Use Dock Previews** on its page in Settings, in General, or on the “New: Dock Previews” card. New users can turn it on in onboarding.
- **A card for every window**, with its thumbnail and title, in one row for a Dock at the bottom and two columns for a Dock at the left or right. A badge marks a minimized, full-screen, or other-Space window, or, with more than one display, names the window’s display; a hidden app says so in the preview’s header. **Card size** is Small, Medium, or Large.
- **Where it works:** the Dock at the bottom, left, or right, magnified or hidden automatically, on any display.
- **Actions.** Click a card to bring its window forward, wherever it is. Middle-click closes it. Hovering a card shows **Close**, **Minimize**, and **Enter Full Screen**, and right-clicking it opens its menu. The header has **Minimize All**, **Hide**, and **Quit** (never for Finder), and its menu adds **Close All**. **Quit** asks the app to quit, like ⌘Q; it never force quits.
- **Keys in previews:** once you’ve moved the pointer in the preview or clicked in it, **⌘W**, **⌘M**, **⌘H**, and **⌘Q** act on what’s under the pointer, and **Esc** dismisses the preview. Every other key goes to the app you’re in, and Snaptic watches the keyboard only while a preview is in use (**Advanced… › Keyboard shortcuts in previews**, on by default).
- **Permissions.** Dock Previews needs **Accessibility** (**Device Control and Data Access** on macOS 27) to read the Dock. **Window thumbnails** also need **Screen Recording**, which Snaptic asks for only in onboarding or on the Permissions page, never when you point at the Dock; until you allow it, previews show window titles. macOS may show its screen-recording indicator or a reminder while thumbnails are taken.
- **Optional Dock click actions**, both off until you turn them on: **When you click the active app in the Dock** (**Do Nothing**, **Hide the App**, or **Minimize Its Windows**), and **Restore all minimized windows** when you click an app whose windows are all minimized. Snaptic watches Dock clicks only while one of them is on, never posts a click, and never changes the Dock’s preferences.
- **Private windows stay private.** **Protect private windows** and “Never show thumbnails for” apply to Dock Previews too, so password managers and private browsing windows show their app icon, and **Advanced… › Apps hidden from Dock previews** leaves an app out altogether. VoiceOver reads a private card as “Private window” and its app, never its title.
- **Other Dock preview apps.** While DockDoor, HyperDock, or another Dock preview app runs, Dock Previews pauses, unless you choose **Run Both Anyway** in **Advanced…**.
- **Switching from DockDoor:** quit it and remove it from Login Items, then turn on Dock Previews. The guide’s [Switching from DockDoor](https://github.com/revylfitness/snaptic/blob/main/docs/guide.md#switching-from-dockdoor) compares how the two behave. Dock Previews follows DockDoor’s design in Snaptic’s own code; it includes none of DockDoor’s code (see [THIRD_PARTY_NOTICES.md](https://github.com/revylfitness/snaptic/blob/main/THIRD_PARTY_NOTICES.md)).
- **VoiceOver:** previews pause while VoiceOver is on, unless you turn on **Advanced… › Show previews while VoiceOver is on**; Dock click actions keep working. A preview is announced with its app and window count.
- **Pausing:** **Pause Dock Previews for 1 Hour** in the Snaptic menu, or `snaptic dock pause [duration]`, `snaptic dock resume`, and `snaptic dock status`.
- **Privacy:** app names, window titles, and bundle identifiers never go into the event log, diagnostics, or the command line. Thumbnails stay in memory and are never saved.

## Window Switcher

- **Minimized windows and windows on other Spaces** get thumbnails too, where macOS allows it; otherwise they show the last one Snaptic saw, then the app icon.
- **Thumbnails stay in memory between openings,** so the switcher opens with them and refreshes them in place. The cache, shared with Dock Previews, now holds at most 120 thumbnails and 96 MB, each for at most 30 minutes (0.4 kept 40 for 5 minutes). It is cleared when your Mac sleeps, locks, or switches user, when Screen Recording is turned off, and when neither module needs it.
- Its **Advanced…** sheet has a new Privacy footer and list help, and **Window thumbnails** says what turning it off does.
- **Private macOS functions** the switcher shares with Dock Previews are checked before use. If one makes Snaptic crash, Snaptic stops using it on that macOS version and the page says so, with **Try Again** after a macOS update.

## Changed

- **Settings has nine pages:** Dock Previews sits between Hidden Icons and Permissions. The Menu Bar and Permissions pages have Dock Previews rows.
- **The Snaptic menu** can show five tabs; ⌘1–⌘5 choose one while it’s open, and VoiceOver, Switch Control, and Full Keyboard Access users also get **Show Dock Previews Tab**.
- **Restore Defaults…** on the Window Switcher and Dock Previews pages leaves **Protect private windows** and “Never show thumbnails for” as they are, since both modules use them.
- **Backup** includes Dock Previews’ settings, “Apps hidden from Dock previews” included.
- **Command line:** `snaptic dock status`, `pause`, and `resume`, with Command-line control on and Dock Previews on.
- **Kill switches:** `Modules.disable.dockPreviews` turns Dock Previews off for a Mac. `Dock.disable.<id>` (`clickActions`, `keys`) and `Windows.disable.<id>` (`hwCapture`, `axWindowID`, `raise`, `spaces`, `symbolicHotKeys`, `layoutType`) turn off one part and apply while Snaptic runs. Window switches affect both window modules, except `symbolicHotKeys` and `layoutType`, which affect only the Window Switcher.

## Upgrading

- **From 0.4.0:** Snaptic updates itself. No setting is lost, and Dock Previews starts off: a “New: Dock Previews” card in General offers **Turn On Dock Previews** or **Not Now**.
- **From 0.3.2, 0.3.3, or 0.3.4:** Snaptic updates itself, and a “New: Hidden Icons” card shows too; see the [0.4.0 notes](https://github.com/revylfitness/snaptic/blob/main/docs/design/0.4/RELEASE-NOTES-0.4.0.md).
- **From 0.3.1, 0.3.0 or earlier:** download 0.5.0 and replace the copy in Applications; see the [0.3.2 notes](https://github.com/revylfitness/snaptic/blob/main/docs/design/0.3/RELEASE-NOTES-0.3.2.md).
- **Going back to 0.4.0:** every setting stays, including your protected apps.

## Known limitations

- Dock Previews works with the pointer, or with VoiceOver when **Show previews while VoiceOver is on** is on. Moving through the Dock with ⌃F3 or Full Keyboard Access never shows a preview; use the Window Switcher.
- The preview doesn’t follow the Dock’s magnification.
- Where Snaptic can’t bring a window forward from another Space, it switches to the app instead, and a card it can’t match to its window offers only **Bring Forward**.
- A Dock click while another app is becoming active, or one held longer than half a second, does nothing.
- An app that doesn’t answer in time shows window titles only, for 30 seconds.
- Thumbnails of minimized and other-Space windows use a private macOS capture, only on macOS versions it has been checked on; elsewhere they show the last one Snaptic saw, then the app icon.
- Snaptic is English only.

## Hardware checks pending

Dock Previews was built and unit-tested on macOS 27.2. These checks (the manual checks in the [0.5 plan](https://github.com/revylfitness/snaptic/blob/main/docs/design/0.5/PLAN.md)) still need a hardware session:

- The Dock at the bottom, left, and right, hidden automatically and magnified, on several displays; Stage Manager.
- Sleep, wake, locking, and Dock restarts.
- Running beside DockDoor and HyperDock, and with VoiceOver.
- Thumbnails of minimized windows and windows on other Spaces, and the screen-recording indicator, on macOS 14, 15, 26, and 27.
- Keys in previews and Dock click actions.
