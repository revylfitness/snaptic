# Snaptic 0.4.0

**New: Hidden Icons.** Click an arrow ‹ in the menu bar to hide the icons to its left, and click again to show them. It is off until you turn it on, and when Snaptic can’t be sure hiding is safe, your icons are shown. Snaptic also has a new app icon. Details are in the [README](https://github.com/revylfitness/snaptic/blob/main/README.md#hidden-icons).

## New: Hidden Icons

- **Off by default.** Turn it on with **Use Hidden Icons** on its page in Settings, in General, or on the “New: Hidden Icons” card. Turning it on opens **How to Arrange Your Icons**, and nothing hides until you click the arrow for the first time. New users also see an **Arrange Your Icons** step in onboarding.
- **Two methods, one arrow.**
  - **macOS 27 and later:** Snaptic asks macOS itself to hide other apps’ icons. It needs **Device Control and Data Access** (Accessibility). You can choose **Always Show** or **Always Hide** for an app in **Sections**, and choose whether new apps’ icons start shown or hidden.
  - **macOS 14–26:** a | divider sits left of the arrow, and Snaptic hides by making it very wide. Hiding needs no permission; Accessibility is asked for only for the hidden-icon list and Sections.
- **You arrange your icons** by holding ⌘ and dragging them in the menu bar. Snaptic never moves another app’s icon. An optional **Always Hidden section** (left of a ⋮ divider) stays hidden until you Option-click the arrow.
- **Showing and hiding:** click the arrow, use the Snaptic menu’s new **Icons** tab, the **Show or Hide Hidden Icons** shortcut (unset by default), or `snaptic icons show`, `hide`, `toggle`, and `status`. Icons hide again automatically after 10 seconds (5–300, on by default), and when Snaptic opens.
- **The hidden-icon list:** choose a hidden icon in the Snaptic menu to open its menu without showing them all. On notched Macs with macOS 14–26, icons pushed behind the notch are listed too.
- **Fails safe.** Icons come back within about 2 seconds if Snaptic quits, crashes, or is force quit. They’re shown on sleep, wake, locking, display changes, during exam sessions, in Safe Mode, when the arrow or a divider is missing, and whenever a hide can’t be confirmed; the page says why and offers the fix. Privacy indicators are never hidden.
- **Other menu bar hiders.** While Hidden Bar, Bartender, Ice, or Thaw runs, Hidden Icons shows your icons and pauses, unless you choose **Run Both Anyway** in **Advanced…**.
- **Switching from Hidden Bar:** quit it and remove it from Login Items, then ⌘-drag Snaptic’s arrow once to where Hidden Bar’s was. The README maps each Hidden Bar setting to its Snaptic one. Hidden Icons follows Hidden Bar’s design in Snaptic’s own code; it includes none of Hidden Bar’s code (see [THIRD_PARTY_NOTICES.md](https://github.com/revylfitness/snaptic/blob/main/THIRD_PARTY_NOTICES.md)).
- **Privacy:** the command line reports a method, a state, and counts, never an app’s name. Per-app choices are stored by bundle identifier, apart from your other settings, and never exported.

## Changed

- **A new app icon.**
- **Settings has eight pages:** Hidden Icons sits between Awake and Permissions. The Menu Bar and Permissions pages have Hidden Icons rows.
- **The Snaptic menu** can show four tabs; ⌘1–⌘4 choose one while it’s open, and VoiceOver, Switch Control, and Full Keyboard Access users also get **Show Hidden Icons Tab**.
- **Backup** includes Hidden Icons’ settings. It leaves out per-app choices, the new-icon list, and icon positions, and an import keeps this Mac’s arrangement.
- **`snaptic prevent-sleep` is gone.** It has answered “Moved to Awake” since 0.3; it is now an unknown command (exit 2). Use `snaptic awake start`, `snaptic awake hold`, or a rule.
- **Kill switches:** `Modules.disable.hiddenIcons` turns Hidden Icons off for a Mac, and `Icons.disable.<id>` (`native`, `length`, `inventory`, `hover`, `axpress`) turns off one part of it. Turning off the method in use shows your icons at once.

## Upgrading

- **From 0.3.2, 0.3.3, or 0.3.4:** Snaptic updates itself. No setting is lost, and Hidden Icons starts off.
- **From 0.3.1, 0.3.0 or earlier:** download 0.4.0 and replace the copy in Applications; see the [0.3.2 notes](https://github.com/revylfitness/snaptic/blob/main/docs/design/0.3/RELEASE-NOTES-0.3.2.md).
- **Going back to 0.3.4:** quit 0.4 first so your icons are shown. Your other settings stay, and Hidden Icons’ settings are kept for when you return.

## Known limitations

- On macOS 14–26, a Snaptic icon that first appears while icons are hidden can land in the hidden section. ⌘-drag it to the right of the arrow once.
- On macOS 27, the Now Playing icon is hidden while icons are hidden, and the list has no behind-the-notch rows.
- Always Show and Always Hide work on macOS 27 only; on 14–26 they’re kept but unused.
- If Snaptic stops responding while icons are hidden on macOS 14–26, force quit it (⌥⌘⎋) to show them. On macOS 27 a watchdog shows them after 3 seconds.
- Snaptic is English only.

## Hardware checks pending

Hidden Icons was tested on macOS 27.2. These checks (the manual checks in the [0.4 plan](https://github.com/revylfitness/snaptic/blob/main/docs/design/0.4/PLAN.md)) still need a hardware session:

- The camera, microphone, and location indicators staying visible while their apps are hidden on macOS 27, and an exam session in Safari or an assessment app.
- ⌘-dragging icons while hidden, and Live Activities and other macOS 27 system items.
- Seeding the dividers on a fresh macOS 15 account, and the 10 000-point divider on the widest displays.
- Running beside Hidden Bar, Bartender, Ice, and Thaw.
