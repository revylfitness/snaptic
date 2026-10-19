# Snaptic 0.3.1 (one last manual download)

**Coming from 0.3.0? This is one last manual download.** 0.3.0 can’t update itself, so download `Snaptic.dmg` or `Snaptic.zip` below and replace the copy in Applications. From 0.3.1 on, Snaptic can keep itself up to date.

Snaptic 0.3.1 adds **tabs in the Snaptic menu**, **keeping awake with the lid closed**, and **in-app updates**. It is also the first release signed by its developer, **Sean Frasure** (Developer ID), and notarized by Apple, so macOS opens it without an Open Anyway step. Details are in the [README](https://github.com/revylfitness/snaptic/blob/main/README.md).

## New: tabs in the Snaptic menu

- When two or more modules are set to Show in Snaptic Menu, the menu shows a tab for each (Window Switcher, Displays, Awake), and only the selected module’s items below. With one module, nothing changes.
- The menu remembers the last tab, also after a relaunch.
- While the menu is open, ⌘1–⌘3 choose a tab (⌘1–⌘2 with two tabs). VoiceOver, Switch Control, and Full Keyboard Access users also get **Show … Tab** items with the same shortcuts.
- Nothing gets hidden behind a tab: Safe Mode and “Sleep Is Turned Off” rows stay above the tabs, and a tab whose module needs attention shows a small mark (VoiceOver says “needs attention”).
- Awake’s tab has the full Awake menu rows.

## New: keeping awake with the lid closed

- **Lid-closed mode** (opt-in, Macs with a battery) keeps a MacBook awake with its lid closed, also on battery with no external display. Turn it on in **Awake › Advanced… › Lid closed**, then choose **Keep Awake with the Lid Closed** in the Awake menu.
- It asks for an administrator password **each time** it turns on, in macOS’s own dialog. Nothing is installed and nothing persistent is granted: no helper, no launch agent, no sudoers rule.
- It turns off by itself at your battery limit (Awake’s low-battery level, at least 10%), when your Mac gets hot, after 24 hours, or when the session ends or Snaptic quits or stops responding. A small watchdog running as root enforces the same limits even if Snaptic hangs, and puts a Mac with a closed lid to sleep when it ends.
- **Use it on a hard surface, not in a bag.** While it’s on, your Mac can’t sleep for low battery or heat on its own.
- With the lid closed and no external display, the built-in display goes dark.
- Only you can turn it on, from Snaptic’s menu or Settings: never the command line, rules, shortcuts, or a restored session.
- If your Mac loses power or restarts while it’s on, sleep stays off until you decide: every Snaptic menu shows **Turn Sleep Back On…**, and Awake’s page also offers **Keep Sleep Off** and **Not Now**, even with Awake turned off.
- What runs as root, and when to trust the password dialog, is explained in the README under “Your password and what runs as root”.

## New: in-app updates

- Release builds update themselves with Sparkle 2 from a signed feed on GitHub Releases, **only if you allow it**. New users choose in onboarding; people coming from 0.3.0 choose on the “Welcome to Snaptic 0.3.1” card.
- **Settings › About › Updates:** Check for Updates…, “Check for updates automatically” (once a day), and “Download and install updates automatically” (installs the next time Snaptic quits).
- When an update is found, the Snaptic menu shows **Update Available: Snaptic …** above Snaptic Settings…, instead of a window that could land behind others.
- Updates wait while lid-closed mode is on or a display change is waiting for “Keep this change?”, and scheduled checks pause in Safe Mode.
- Every update must carry a valid signature from Snaptic’s update key or its Developer ID signature, and the feed itself is signed.
- **Privacy:** Snaptic connects only to GitHub to check for updates, and only if you allow it. GitHub sees your IP address and macOS version, nothing more. No analytics.
- Copies owned by root ask for an administrator password for each update. Copies built from source don’t update themselves.

## Upgrading from 0.3.0

- No setting is lost.
- **Permissions, once more.** Because 0.3.1 is signed by its developer, macOS treats it as a new app for Accessibility and Screen Recording. Settings opens on General with a “Welcome to Snaptic 0.3.1” card: remove the old Snaptic with − in each list in System Settings, then turn on the new one. After this, updates keep your permissions.
- The card also asks whether to keep Snaptic up to date.

## Changes

- **Awake:** the menu reminder that closing the lid puts your Mac to sleep doesn’t show while lid-closed mode is on. “End sessions when your Mac sleeps” doesn’t apply to closing the lid in lid-closed mode. History marks sessions that used it, and `snaptic awake status --json` has a `lidClosed` key.
- **Command line:** `snaptic awake extend` is refused while lid-closed mode is on (exit 4); `snaptic awake stop` still ends it.
- **Other apps keeping your Mac awake** now says “Sleep is turned off for this Mac by another app or command. Snaptic leaves it as it is.”
- **Kill switch:** `Awake.disable.lidClosed` turns lid-closed mode off for a Mac.
- **Downloads** are signed and notarized, and carry a build-provenance attestation for their release tag.

## Known limitations

- Lid-closed mode asks for a password every time, and macOS’s dialog names `osascript`, not Snaptic. Another app’s display assertion (for example `caffeinate -d`) can keep the built-in display lit with the lid closed, and the keyboard backlight may stay on.
- Security software may flag “osascript with administrator privileges” when lid-closed mode turns on.
- Updates need a release build. 0.3.0 needs this one manual download.
- Snaptic is English only.

## Hardware checks pending

0.3.1 was built without hardware testing. These checks (HW-24 to HW-38 in the 0.3.1 plan) still need a hardware session:

- tab switching in an open menu on macOS 14, 15, 26, and 27, with VoiceOver, Switch Control, and Full Keyboard Access, and ⌘1–⌘3;
- the password dialog, Touch ID, and Cancel, from Developer ID and ad-hoc builds;
- lid-closed mode on battery with and without an external display: staying awake, the built-in display going dark, and the watchdog restoring sleep after a quit, a crash, a hang, the 24-hour limit, the battery limit, and heat;
- a restart while lid-closed mode is on, and both recovery choices;
- updating a user-owned and a root-owned copy, permissions surviving an update, refusing tampered updates and feeds, and the 0.3.0 → 0.3.1 permission re-grant.
