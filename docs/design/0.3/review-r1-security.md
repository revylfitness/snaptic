# 0.3 plan review r1: security, privacy, safety

Checked against [PA], [AP], 0.2 §3.4/§4.10/R5.7 and the existing code.
Counts: **Critical 0 · High 2 · Medium 7 · Low 6.**

## High

**H1. The "protected Awake settings" guarantee fails in two ways: changes made while Snaptic is not running are never checked, and changes made while it runs are reverted only after they have been applied (§3.2, §2.11, §2.14).**
- Scenario A: a same-user process runs `killall Snaptic; defaults write <bundle> SnapticAwakeV1 <features.pointerNudge=true, preset.activity=nudge>` and then `open -a Snaptic`.
  - `ConfigStore.init` decodes the stored value and sanitizes it. It never calls `onExternalChange`, so `protectedChanges` never runs.
  - Snaptic then posts events using an Accessibility grant that switcher users already have. The "requested lazily" note doesn't protect them. Drive Alive volumes enabled this way get writes under Snaptic's Removable Volumes grant.
- Scenario B (running): `storedValueChanged` publishes `value = new` before `onExternalChange`, so controllers act on the tampered value before the revert.
- Fix:
  1. Add `ConfigStore.admit: ((_ current: T?, _ incoming: T) -> T)?` and apply it **before** any assignment, both in `init` (current = nil) and in `storedValueChanged`.
  2. Store the protected opt-ins as a consent record in a Keychain generic-password item: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, default ACL limited to the creating app, holding the set {pointerNudge, preset/trigger ids allowed to nudge, Drive Alive UUIDs}. Only UI actions write it.
  3. `AwakeConfig.protectedChanges(consent:incoming:)` turns off every protected field that isn't in the consent record.
  4. If the Keychain read fails (ad-hoc rebuild), treat the consent as empty and turn the features off.

**H2. Protection doesn't cover the runtime snapshot (`SnapticAwakeStateV1`) (§2.5 Persistence, §2.14).**
- Scenario: an attacker writes `manual = {kind: indefinite, options.activity: nudge, source: menu, bootSession: <current, readable with sysctl>}`. `resumeAfterRestart` restores it on the next launch or relaunch.
- If the one-shot "Start Anyway" override is ever persisted, the same path turns the battery guard off.
- Fix:
  - Snapshot sessions store `presetID` and options. On restore, run them through the same `admit`/consent check (nudge → declare unless the preset is consented).
  - Re-run `AwakeGuards.evaluate` before restoring.
  - Never persist the override; restored sessions always have it cleared.
  - Force `source = .restored`; sanitize `kind` (≤ 30 days from `startedAt`).

## Medium

**M1. The guards can be turned off despite priority (3), "Awake guards are always on" (§0, §2.2, §2.6, C9).**
- `FeatureGraph.resolve` subtracts kill switches even from `always` features (`set.subtract(killSwitches)`). Writing `Awake.disable.thermalGuard` or `Awake.disable.batteryGuard` therefore removes the guards.
- `batteryFloorEnabled` can be set to false from outside, and import isn't blocked from doing the same.
- Drive Alive with "Even without a session" runs outside every guard: on battery, at critical heat, while locked.
- Fix:
  - Don't accept kill switches for `batteryGuard` or `thermalGuard` (tested). Evaluate thermal `.critical` unconditionally in SessionController and DriveAliveController.
  - Treat lowering or disabling the floor like a protected field: it applies from the UI only and is reverted when it arrives from outside or from an import.
  - Gate Drive Alive with the battery floor and thermal guards in every mode.

**M2. The safety gates trust distributed notifications that any process can spoof (§2.8 SystemEventsMonitor, §2.9 ActivityPolicy, §2.4 Arbiter).**
- Any same-user process can post `com.apple.screenIsUnlocked` or `com.apple.screensaver.didstop`. That makes `shouldAct` true while the screen is locked, so `DeclareUserActivity` lights the display at the lock screen and nudges get posted there. Spoofing the opposite notifications flips the C1 downgrade.
- Fix: treat these notifications as hints only. Before every activity action and every arbitration, read `CGSessionCopyCurrentDictionary()` (`CGSSessionScreenIsLocked`, `kCGSSessionOnConsoleKey`) the way `ToastPresenter.isSuppressed` already does. Read screensaver state from `NSWorkspace` screensDidSleep plus the session dictionary. 

**M3. The CLI can still prolong pointer movement, and N1 contradicts §3.1 (§0.1 N1, §2.10, §3.1, OQ-1).**
- `awake extend` works on any manual session, including one the user started with nudge. That gives the CLI up to 30 days of pointer movement.
- N1 says the CLI "never [causes] … Drive Alive", but §3.1 lets CLI sessions drive the writes.
- Fix:
  - Refuse `extend` (exit 4) when the governing session's effective activity is `.nudge`.
  - Settle OQ-1 as **strict**: DriveAliveController ignores sessions with `source == .commandLine`.
  - The first write (Removable Volumes prompt) happens only from a UI action.

**M4. Activity simulation can keep an unattended, unlocked Mac from ever idle-locking, and managed policy can't stop it (§2.9, §3.2, 0.2 §3.4).**
- With declare or nudge plus an indefinite session, an unlocked Mac the user walked away from never reaches the screensaver or idle lock. That defeats an MDM `idleTime`/`askForPassword` policy.
- 0.2 ignores managed preferences, so admins can't turn it off.
- Fix:
  - Stop activity simulation after a cap measured from the last **real** input: default 1 h, Advanced maximum 8 h. The session itself continues.
  - If `CFPreferencesAppValueIsForced` reports `idleTime` or `askForPassword` for `com.apple.screensaver`, set `activity` and `pointerNudge` unavailable, with the reason "Your organization manages screen lock."
  - Honor **forced** (managed, root-installed) `Awake.disable.*` keys, in the disable direction only.

**M5. Drive Alive resolves the volume path at each write and checks volume eligibility with a blocklist (§2.9, §3.3).**
- Between resolving `/Volumes/X` and calling `open`, the volume can unmount and a different one (a DMG, or a stale mount-point directory on the Data volume) can appear at the same path. `O_NOFOLLOW` covers only the last path component.
- The plan never says how `isDiskImage` is determined.
- `isLocal` passes FSKit and macFUSE volumes (sshfs, cloud-backed). Writing to those generates network I/O.
- Fix:
  - Write procedure:
    1. `dirfd = open(root, O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)`.
    2. `fstatfs(dirfd)`: check `f_mntonname == root` and `f_fstypename` ∈ {apfs, hfs, exfat, msdos} (an **allowlist**). Check that the volume UUID read with `fgetattrlist(ATTR_VOL_UUID)` equals the configured key.
    3. `openat(dirfd, name, O_WRONLY|O_CREAT|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK, 0600)` and require the file's `st_dev` to equal the directory's `st_dev`.
  - Determine `isDiskImage` from DiskArbitration (`kDADiskDescriptionDeviceModelKey == "Disk Image"`, or an IOHDIX ancestor).
  - Exclude every volume in the boot APFS container.
  - `removeKeepAliveFile` uses `unlinkat` with the same checks and only removes the file if it is 8 bytes.

**M6. The log and diagnostics rules are only a heuristic, and shared reports leak an activity timeline (§3.5, §6.3 L9).**
- L9 only catches variables named `name`, `bundleID` or `title`. An interpolation such as `"\(entry.criterion)"` prints the bundle id, volume name, USB product name and CIDR through the enum's `description`.
- Diagnostics include `EventLog.recent`, so lines like "trigger 3 active: audio/app" timestamp microphone use and app use in a report users share.
- Assertion `Details` (example: "trigger 2: display") are world-readable to every local user.
- Fix:
  - `.awake` lines go only through a closed `AwakeLogEvent` enum with a fixed `text`. Lint bans `record(.awake, "` with `\(`.
  - Diagnostics carry Awake event counts, not timestamps of trigger activations.
  - `Details` contain only "manual" or "automatic", never criterion kinds.
  - Keep the Sleep Status list (other processes' assertions) out of diagnostics, logs and CLI.

**M7. Backup can't do what the plan promises (§3.2, §3.5 Backup).**
- `KitBackup.remove` walks dictionaries only, and `*` matches dictionary keys. Fields inside arrays (`presets[].options.activity`, `triggers[].options.activity`) can't be stripped, and `mergeByID` would import them.
- Imports can lower or disable the battery guard, which breaks 0.2's rule that a file never flips a safety switch (FIXES-R1 A2).
- Exported trigger definitions carry bundle ids, app, drive, device and Bluetooth names, network CIDRs and router labels. Their salted hashes are useless on another Mac anyway.
- Fix:
  - Add an `awake` section. Add array-aware path wildcards (`[]`), or a typed Kit `AwakeConfig.exportable()` / `importable(current:)` that rewrites `nudge` → `declare` and drops `drives`, `features.pointerNudge`, `recentApps`, `startAtLaunch` and hashes.
  - Make `guards` monotonic on import: stricter only, and listed in `safetyPaths`.
  - Export triggers only when the user ticks "Include automatic-session rules (contains app, device and network names)", off by default.

## Low

**L1. The pointer nudge can hit screen edges, and Snaptic's own nudges defeat its idle logic (§2.9).**
- A nudge of ±1 pt at a screen edge or corner re-enters hot corners (including "Lock Screen" and "Start Screen Saver"), the auto-hidden Dock and the full-screen menu bar.
- Snaptic's own nudges reset `combinedSessionState` idle. As a result, `keepOnWhileActive` never downgrades and `idle` criteria never fire, so the display stays on and drains the battery.
- Fix: skip the nudge when the pointer is within 2 pt of any display edge. Compute "real idle" with nudge times excluded (keep the nudge timestamps, and ignore idle resets within 1 s of a nudge). Add both to HW-6.

**L2. Toasts at `screenSaver + 1` show over a screensaver that hasn't locked yet (`ToastPresenter.swift:161`).**
- During the screensaver's password delay `CGSSessionScreenIsLocked` is false, so "Awake ended: Xcode quit." appears to passers-by.
- Fix: also suppress toasts while the screensaver runs, and use the generic reason text when the session isn't on console.

**L3. Scripted start/stop churn and silent CLI sessions (§2.10, §3.1).**
- At the global limit of 20 requests per second, a script can wipe the 500-entry history and churn powerd assertions.
- When the indicator is hidden (by Snaptic or by macOS 26/27), the user never learns that a script is keeping the Mac awake.
- Fix: limit `awake start`, `stop` and `extend` to 1 per second. Merge history entries shorter than 60 s that ended `.replaced`. Show a toast "Awake was started from the command line." at most once per 10 minutes.

**L4. The duration grammar can crash Snaptic from the CLI (§2.3 `AwakeDurationGrammar`).**
- "1e300h" makes `Int(Double)` trap, and a long digit string overflows `seconds * 3600`. A trap crashes Snaptic, taking the switcher and Displays with it.
- Fix:
  - Accept at most 7 digits per number and at most 2 decimals.
  - Check finiteness and range on the `Double` before converting.
  - Use `multipliedReportingOverflow`.

**L5. Sessions can keep a locked, stolen or switched-away Mac awake indefinitely (§2.12, C1, C10).**
- An indefinite session keeps a locked Mac out of standby, which defeats `DestroyFVKeyOnStandby`-style policies and keeps a stolen open laptop running.
- A background fast-user-switching session keeps the Mac awake for the user on console, who can't see why.
- Fix: add an Advanced option "End sessions after the screen has been locked for…" (Never / 1 h / 4 h / 12 h; default Never, OQ). Off console for more than 1 h, end the session with `.userSwitch` (configurable). 

**L6. Smaller gaps.**
- Restore Defaults "leaves protected fields untouched" (§4.6). It should turn nudge and Drive Alive **off**, which is the safe direction.
- Replace `KitControl.protectedSettings` "sleepprevention" with "awake", "nudge", "pointernudge", "drivealive", "activity", "guards", "batteryguard", "thermalguard". Keep `feature disable` limited to Displays.
- "Start Again" needs a bundle id that `AwakeHistoryEntry` lacks: disable it for app sessions, or store the id locally (never exported).
- Test that `settingsIndex()` holds no user strings.

## Verified sound
Fixed-vocabulary assertion names; assertions die with the process; no spawn or network lint; CLI socket rules in code (0700/0600, `getpeereid`, 20/s); keep-alive file checks; nudges never post keys or clicks; C1; toasts suppressed while locked; `awake status` has no app names; N1's `caffeinate` premise holds.
