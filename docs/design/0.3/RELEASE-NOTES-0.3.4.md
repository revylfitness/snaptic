# Snaptic 0.3.4

**Lid-closed mode works again on macOS 27.** On macOS 27, choosing **Keep Awake with the Lid Closed** asked for your password, waited about 10 seconds, and then said “Snaptic couldn’t turn on lid-closed mode. Try again.” every time. The small script that keeps sleep off was started through `nohup`, which on macOS 27 quits at once when it runs from the password prompt, so the script never started and sleep never turned off. Snaptic now starts it without `nohup`, ignoring the same hangup signal `nohup` protected it from.

## Fixed

- **Lid-closed mode turns on.** After the password, sleep turns off within a few seconds, as it did before macOS 27. Nothing else about lid-closed mode changed: it still asks for an administrator password each time, and still turns off at your battery limit, on heat, and after 24 hours.

## Changed

- **A failed attempt says why.** Instead of one message for every failure, it names the step: for example, the password dialog didn’t finish in time, the helper stopped before sleep turned off, or sleep didn’t turn off within 10 seconds.
- **A failed attempt ends sooner.** If the helper stops while Snaptic waits for sleep to turn off, Snaptic says so at once instead of after 10 seconds.
- **Diagnostics count lid-closed failures.** The diagnostics report now counts each kind of failed lid-closed attempt, and each time Snaptic cleans up a helper left over from an earlier session. As with the rest of Awake, these are counts only, with no times.

## Upgrading

- **From 0.3.2 or 0.3.3:** Snaptic updates itself. Your settings are untouched.
- **From 0.3.1, 0.3.0 or earlier:** download 0.3.4 and replace the copy in Applications; see the [0.3.2 notes](https://github.com/revylfitness/snaptic/blob/main/docs/design/0.3/RELEASE-NOTES-0.3.2.md).
