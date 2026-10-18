# 0.3 plan review r2: security, privacy, safety

Checked against PLAN r2, review-r1-security, 0.2 §4.10/R5.5/R5.7 and `Sources/`.
Counts: **Critical 0 · High 1 · Medium 5 · Low 6.**

## Round-1 status
Resolved: H2, M1, M2, M3, M5, M7, L1–L6 (§2.2–§2.14, §3.1–§3.6), with residuals noted below. **Not fully resolved:** H1 (Keychain basis unproven, **H1**), M4 (cap may never fire, managed check incomplete, **M2/M5**), M6 (diagnostics tail, **M3**). New regressions: `sessions` unkillable (**M5**), `.restored` launders `.commandLine` (**L1**).

## High

**H1. The consent record rests on keychain semantics the plan misstates and never tests against an attacker (§2.14 "Keychain rules", §3.2, HW-22).**

- **Wrong keychain.**
  - `build-app.sh` signs without entitlements, and ad-hoc builds can't carry any. So the data-protection keychain (`kSecUseDataProtectionKeychain`, which needs `keychain-access-groups`/application-identifier and a provisioning profile) isn't available.
  - Snaptic therefore uses the legacy file-based login keychain, which ignores `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
  - Protection there comes only from the item's ACL and its partition list.
- **Plausible trivial bypass: pre-seeding.**
  - Most users never grant consent, so no item exists.
  - A same-user process runs `security add-generic-password -A -s "Snaptic Awake consent" -a <TeamID or cdhash> -w '<consent JSON>'`. Both account values are public (`codesign -dv`), and `-A` means "allow all applications".
  - `SecItemCopyMatching` then returns that item with no prompt, so `kSecUseAuthenticationUIFail` never comes into play.
  - Admission now trusts attacker consent: nudge using Snaptic's Accessibility grant, Drive Alive using the Removable Volumes grant, floor off. That is exactly r1 H1.
- **Unknowns.** Delete-then-recreate of an existing item, `-T /Applications/Snaptic.app` items, ad-hoc partition IDs, and whether `kSecUseAuthenticationUIFail` suppresses legacy ACL dialogs at all are all unverified.
- **Fix:**
  1. State in §2.14 that this is the legacy file keychain, and drop the accessibility-class claim.
  2. Check provenance on every read. Use `SecKeychainItemCopyAccess` with `SecAccessCopyACLList` and `SecACLCopyContents`. For `kSecACLAuthorizationDecrypt`, the trusted-application list must be non-nil (not "any application") and must match exactly Snaptic's designated requirement. The ACL description's partition IDs must be exactly `teamid:<ours>` (Developer ID) or our cdhash partition (ad-hoc). Anything else → treat consent as empty, log `consentUntrusted`, and delete and recreate the item on the next UI consent.
  3. If HW shows that an ad-hoc build can't get a distinguishing partition, ad-hoc builds keep consent **in memory only**: protected features turn off at quit. Settings says "Developer ID builds remember this."
  4. Extend HW-22 with adversarial cases, run from an unrelated ad-hoc binary and from `security(1)`: read, modify, delete, delete + recreate, pre-create with `-A`, and pre-create with `-T Snaptic.app`. Each must end in empty consent and no dialog.
  5. §3.2 residual: protects against defaults tampering only, not a process that drives Snaptic's UI or replaces a user-writable bundle (R5.7).

## Medium

**M1. Consent is bound to ids, not to content (§2.14 `AwakeConsent`, §2.5 snapshot admission).**

- `nudgePresets` and `nudgeTriggers` are sets of `StableID`, and ids are readable in defaults. An attacker keeps a consented id and rewrites everything else:
  - a preset's kind becomes `indefinite`;
  - a trigger's criteria become `power(onAdapter)`;
  - the snapshot gets `manual` = {presetID: consented P, kind: indefinite, activity: nudge}.
- Admission passes all three.
- Ids also stay consented after the preset or trigger is deleted, or after its activity changes from nudge. Volumes turned off stay in `driveAliveVolumes`.
- Fix:
  - Store `[StableID: SHA256]` over the canonical encoding of the protected-relevant content: preset kind and options; trigger match, criteria and options. Admission downgrades nudge → declare on any mismatch.
  - Snapshot admission additionally requires `kind` to match the preset's kind and `options == effectiveOptions(for:preset:)`.
  - `record` prunes entries when a preset or trigger is deleted, when its activity leaves nudge, or when a volume is turned off.

**M2. The 1-hour activity cap can be defeated by Snaptic's own declarations (§2.9 `IdleMath`, §3.3, HW-5).**
- `IdleMath` excludes echoes only of nudges.
- If `IOPMAssertionDeclareUserActivity` resets the `.hidSystemState` any-input counter (HW-5 asks exactly this), every 60 s declare resets "real idle". Then `realIdle < stopAfter` holds forever, and an unattended unlocked Mac never idle-locks: r1 M4 again.
- Fix:
  - Derive last real input from per-type counters: the minimum of `CGEventSourceSecondsSinceLastEventType(.hidSystemState, t)` for keyDown, flagsChanged, left/right/other mouse down, scrollWheel and mouseMoved, with mouseMoved filtered by the nudge-echo window.
  - Never use `anyInput`. Also pass declare times to `IdleMath`.
  - Add to HW-5: does the cap fire after 1 h in declare mode?

**M3. Diagnostics still export an activity timeline (§3.6 vs `DiagnosticsController.eventLines()`).**
- The report appends the EventLog tail for **all** categories as `HH:mm:ss.SSS [category] message`.
- `.awake` events such as `sessionStarted`, `triggerActive(index:)` and `sessionEnded(batteryLow)` would appear with timestamps. The "counts only" rule is implemented nowhere.
- Fix: `eventLines()` drops `EventCategory.awake`, covered by a test. Awake diagnostics read counts from a per-case counter in `AwakeDiagnostics`. Better still, activity-revealing cases increment counters and never enter the ring.

**M4. `awake hold` needs server-side peer credentials the CLI contract doesn't carry (§2.10, §6.2 ProcessFacts, HW-21; `ControlServer.swift:138`).**
- `ControlListener.Handler` receives only `(ControlRequest, ControlCancellation, Reply)`. Nothing says where `LOCAL_PEERPID` is read, or when.
- An implementation that serializes a pid into the request is "a pid the client claims".
- PID reuse is also open in two places: between the parent lookup and the start-time check, and between the check and arming the process source.
- Fix:
  - In `acceptAll`, right after `getpeereid`, read `LOCAL_PEERTOKEN`. Use the audit token's pid and pidversion, not `LOCAL_PEERPID`.
  - Read the peer's `pbi_ppid` and the parent's start time and uid **before** reading the request, while the peer is blocked waiting for the reply.
  - Pass a `PeerCredentials` value to the handler (lead-owned contract change in §6.2).
  - Refuse when ppid ≤ 1, the uid differs, or the parent's start time is later than the peer's (reparented).
  - Arm the `.exit` source first, then re-verify the start time. Re-verify on every arbitration as well.
  - `--pid N` gets the same checks.

**M5. Managed policy can't turn Awake off, and the managed-lock check is incomplete (§2.2 `unkillable`, kill-switch paragraph).**
- `unkillable = [.sessions, .batteryGuard, .thermalGuard]` ignores **forced** keys as well. An MDM admin who forces `Awake.disable.sessions` gets nothing, although killing sessions is the safe direction.
- `idleTime` and `askForPassword` are often delivered ByHost or via `askForPasswordDelay`. A plain `CFPreferencesAppValueIsForced` call misses those.
- Fix:
  - Apply `unkillable` to persistent-domain keys only.
  - A forced `Awake.disable.sessions` (or `Awake.disable`) stops the module: assertions are released and nothing restores at relaunch.
  - Guards remain unkillable by both kinds of key.
  - Check `idleTime`, `askForPassword` and `askForPasswordDelay` in both the any-host and current-host domains (`CFPreferencesCopyValue(…, kCFPreferencesCurrentHost)` plus `IsForced`).

## Low

**L1. Restore launders the CLI source (§2.5 "source forced to `.restored`", §2.9 `shouldWrite`).**
- A CLI session restored after relaunch becomes `.restored`, and so does any session written into the snapshot. Drive Alive then writes for it, which breaks the strict OQ-1 rule.
- Fix:
  - Keep `origin: AwakeSessionSource` through restore.
  - `shouldWrite` needs a session that is live and was UI-started in this process (`menu|hotkey|settings`). `.launch` and `.restored` don't count until the user acts again.

**L2. Outside snapshot changes while running are unspecified (§2.5, §2.14).**
- It isn't stated whether an outside write to `SnapticAwakeStateV1` at runtime starts or replaces a session.
- An attacker can also clear `GuardMemory.holding` and `unreadableReads` before launch.
- Fix: while Awake runs, the snapshot admit returns `current` (outside writes are ignored). At load, `guardMemory` holds are recomputed from live `PowerFacts`, not trusted.

**L3. The Drive Alive write doesn't re-check eligibility on the fd (§2.9 steps 3–4).**
- The volume UUID is metadata a crafted DMG can clone.
- Fix: in step 3, also require `f_flags` to have `MNT_LOCAL` set and `MNT_RDONLY`/`MNT_ROOTFS` clear, and require `f_mntfromname` to equal the BSD name whose DiskArbitration description was judged eligible. A remount re-runs DA.

**L4. The visibility claims are stronger than the mechanism (§3.1, §2.8, N11).**
- `presence = .dontShow` plus any shortcut is writable via defaults.
- Spoofed `screensaver.didstart` hints suppress the "started from the command line" toast.
- `awake start 30d` and `hold --pid <loginwindow> 30d` give 30-day CLI sessions despite "never unbounded".
- A CLI start or hold silently replaces a user's UI session.
- Fix:
  - §3.1 says that visibility and bounds are UX, not a boundary (`caffeinate` exists).
  - The didstart hint expires after 10 s unless ScreenSaverEngine is frontmost.
  - CLI start/hold doesn't replace a running UI-started session (refuse with exit 4, "A session started from the menu is running").

**L5. Import bypasses admission (§2.14 `importable`, KitBackup `merge`/`mergeByID`).**
- UI writes skip `admit`, and the order relative to `KitBackup.merge` is unstated.
- Fix: final value = `admitted(consent:)` of `importable(current:)` applied **after** `KitBackup.merge`; test with a hostile backup (nudge in presets[]/triggers[], volumes, floor 5).

**L6. Consent failures are handled silently or with misleading messages (§2.14, §3.2).**
- A transient read failure (keychain locked) strips protected fields, and the next unrelated save writes the stripped value permanently.
- A failed `record` reverts the user's toggle with the "changed outside Snaptic" toast.
- Fix:
  - Distinguish `readFailed` from `empty`. On `readFailed`, don't persist the protected-field changes that admission made, and show "Couldn't read Awake permissions; pointer movement and Drive Alive are off."
  - `record` returns `Bool`; on failure the UI shows an inline error and doesn't write the config.

## Verified sound
untilIdle (system-wide `host_statistics` + `NET_RT_IFLIST2` counters; no TCC, no per-process data, fixed log reason); lock/console from `CGSessionCopyCurrentDictionary` at use; critical heat evaluated directly; Start Anyway never persisted; `allowsBackgroundWork` in every mode; dirfd/`openat`/`st_dev`/`unlinkat`/fs allowlist; grammar bounds + fuzz; CLI 1/s; closed `AwakeLogEvent` + L9; `Details` manual/automatic; static search index with no-user-strings test; menu redesign adds no URL scheme, AppleScript or remote entry; presenting check uses bounds + owner PID only (no Screen Recording).
