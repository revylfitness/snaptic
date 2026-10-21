# Snaptic 0.3.3

**Lid-closed mode is easier to find.** Its one-time opt-in, “Keep awake with the lid closed”, used to be in **Awake › Advanced…**. It’s now on the Awake page itself, in its own **Lid closed** section, and on the **Menu Bar** page under Awake, as “Show Keep Awake with the Lid Closed in the Awake menu”. Both are the same switch, shown only on Macs with a battery. The switch only adds **Keep Awake with the Lid Closed** to the Awake menu; choosing that still asks for an administrator password each time, and lid-closed mode still turns off at your battery limit, on heat, and after 24 hours. If you had already turned the switch on, it stays on.

## Changed

- **The opt-in moved out of Advanced.** The Awake page’s **Lid closed** section has the switch, the note about who can change this copy of Snaptic, and the limits with **Learn More…**. The Menu Bar page’s switch has the same note and says to use it on a hard surface, not in a bag; from a copy macOS runs from a temporary location, it says to move Snaptic to Applications instead. The Awake page’s reminder that closing the lid sleeps your Mac now points to the **Lid closed** section. If sleep was left off by an earlier lid-closed session, the rows to turn it back on stay where they were: at the top of the Awake page and in **Awake › Advanced… › Other apps keeping your Mac awake**.
- **The switch can’t end lid-closed mode by accident.** While lid-closed mode is on (or turning on or off), both switches are locked: “Lid-closed mode is on. Turn it off first, in the Awake menu or in Options on the Awake page.” Turning the switch off used to end the mode without a word, and put your Mac to sleep if the lid was closed. **Restore Awake Defaults…** used to do the same; while lid-closed mode is on it now leaves the switch on and says so, and resets everything else.
- **A release no longer needs a manual re-run when Apple’s servers hiccup.** The release pipeline now retries stapling the notarization ticket to the app and the disk image, as it already did when checking them.

## Upgrading

- **From 0.3.2:** Snaptic updates itself. Your settings are untouched.
- **From 0.3.1, 0.3.0 or earlier:** download 0.3.3 and replace the copy in Applications; see the [0.3.2 notes](https://github.com/revylfitness/snaptic/blob/main/docs/design/0.3/RELEASE-NOTES-0.3.2.md).
