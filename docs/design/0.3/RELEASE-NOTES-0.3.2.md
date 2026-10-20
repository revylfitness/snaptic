# Snaptic 0.3.2 (fixes 0.3.1 not starting)

**0.3.1 doesn’t start.** It shows “Snaptic can’t start: Snaptic couldn’t look up your account’s home folder.” 0.3.2 fixes this. Because 0.3.1 never starts, it can’t update itself, so download `Snaptic.dmg` or `Snaptic.zip` below and replace the copy in Applications, as you would coming from 0.3.0 or earlier. From 0.3.2 on, Snaptic keeps itself up to date.

Everything 0.3.1 introduced is in 0.3.2: tabs in the Snaptic menu, keeping awake with the lid closed, and in-app updates. See the [0.3.1 release notes](https://github.com/revylfitness/snaptic/blob/main/docs/design/0.3.1/RELEASE-NOTES-0.3.1.md). Your settings are untouched.

## Fixed

- **Snaptic starts again.** At launch Snaptic asks macOS for your home folder. 0.3.1 read the answer from memory that the release build had already freed, so it saw garbage and refused to start. Snaptic now copies the answer while it’s still valid, and every part of the app uses that one lookup.
- **Release checks run the app’s own startup checks.** The automated checks that build every release now run the same startup checks as the app, on the release build, so a release that can’t start can’t be published again.
- **A network hiccup no longer fails a release.** The release pipeline retries Apple’s notarization check when the connection drops.

## Upgrading

- **From 0.3.1, 0.3.0 or earlier:** download 0.3.2 and replace the copy in Applications. Coming from 0.3.0 or earlier, see the 0.3.1 notes for the one-time permission reset (Accessibility and Screen Recording).
