# Snaptic 0.3.3

**Lid-closed mode is easier to find.** Its one-time opt-in, “Keep awake with the lid closed”, used to be in **Awake › Advanced…**. It’s now on the Awake page itself, in its own **Lid closed** section, and on the **Menu Bar** page under Awake, as “Show Keep Awake with the Lid Closed in the Awake menu”. Both are the same switch, shown only on Macs with a battery. Nothing else about lid-closed mode changes: it still asks for an administrator password each time you turn it on, and it still turns off at your battery limit, on heat, and after 24 hours. If you had already turned it on, it stays on.

## Changed

- **The opt-in moved out of Advanced.** The Awake page’s **Lid closed** section has the switch, the note about who can change this copy of Snaptic, and the limits with **Learn More…**. The Awake page’s reminder that closing the lid sleeps your Mac now points there. If sleep was left off by an earlier lid-closed session, the rows to turn it back on stay where they were: at the top of the Awake page and in **Awake › Advanced… › Other apps keeping your Mac awake**.
- **A release no longer needs a manual re-run when Apple’s servers hiccup.** The release pipeline now retries stapling the notarization ticket to the app and the disk image, as it already did when checking them.

## Upgrading

- **From 0.3.2:** Snaptic updates itself. Your settings are untouched.
- **From 0.3.1, 0.3.0 or earlier:** download 0.3.3 and replace the copy in Applications; see the [0.3.2 notes](https://github.com/revylfitness/snaptic/blob/main/docs/design/0.3/RELEASE-NOTES-0.3.2.md).
