# 0.3 plan review r3: security, privacy, safety

Checked against PLAN r3, review-r2-security, 0.2 §4.10/R5.5/R5.7 and `Sources/`.
Counts: **Critical 0 · High 0 · Medium 3 · Low 8.**

## Round-2 status
- **H1** resolved: the mechanism is withdrawn, and §3.2 states the legacy-keychain facts honestly.
- **M1** superseded: nothing is bound to an id any more.
- **M2** resolved: the cap runs on Snaptic's clock, idle never uses `anyInput`, and declaration times feed `IdleMath`.
- **M3** resolved: these events are counted only, and `isExportedInDiagnostics` filters them out.
- **M4** partial rejection accepted. No capability depends on the peer's identity, so a wrong binding only changes when a same-user hold ends (≤ 24 h). The stated reason is inaccurate, though (**L1**).
- **M5** partial rejection accepted: kill switches only disable, and the module switch covers the MDM case.
- **L1–L5** resolved, with residuals:
  - L1: a forged snapshot `source` still turns on Drive Alive. That's acceptable because §3.2 shows Drive Alive grants no new capability.
  - L2: `ConfigStore` still observes the snapshot key (**L4**).
- **L6** moot.

## Medium

**M1. Hotkeys count as a "direct user action", but their bindings are config-writable (N10, §2.5 "Starting from … a Snaptic hotkey", §2.10, §3.2 table).**
- `AwakeConfig.shortcuts` is applied live through `onExternalChange` (`ConfigStore.swift:56–69`).
- So a same-user process can use defaults to bind `awake.toggle` to a combo the user presses for other reasons, set `defaultOptions` to `nudge`, and turn on `pointerNudge` with `stopAfterHours = 8`.
- The user's next keystroke then gives `uiStartedInProcess = true` and up to 8 h of pointer posting under Snaptic's Accessibility grant.
- §3.2 concedes this only for "if the user starts such a session". A rebound key isn't the user choosing to start anything.
- 0.2 already treats this pattern as unsafe: R5.7 makes "Gather windows" (Accessibility) show a confirmation toast when a shortcut triggers it, for exactly this reason.
- The harm is small (±1 pt moves), but it is Snaptic's TCC grant acting on attacker intent, which breaks priority (2).
- Fix:
  - A hotkey-started session never nudges until the user confirms a toast: "Move the pointer while this session runs?" with **[Move Pointer] [Not Now]**. Until then it degrades to `declare`, matching R5.7.
  - Menu and Settings starts show a non-blocking toast at the first nudge: "Awake is moving the pointer slightly." **[Stop]**.
  - Add hotkeys to the §3.2 residual row and to HW-19.

**M2. `uiStartedInProcess` is the only gate, and its transitions aren't specified exhaustively (§2.3, §2.5 l.756, §2.9 "The cap").**
- The plan says when the flag is set, but not what other UI touches do: Add 1 Hour, Add Time…, **Keep Going**, Keep Display On, **Start Anyway**, **Start Again** (history has no `source`), a UI extend of a CLI or restored session, Safe Mode exit, `pointerNudge` coming back mid-session, and an outside write to the default options a running session uses (§2.14).
- If any of these sets the flag, or clears `activitySince`, a CLI, restored or long-running session becomes nudge-capable or uncapped.
- Fix: put the transitions in a Kit `AwakeActivityGate` (pure, tested) with this truth table:
  - Only `start`/`startPreset`/`startDefault` with a direct source, and restarting the running preset from the UI, set the flag and clear `activitySince`.
  - Extend, Keep Going, Keep Display On, option and feature changes, restore, replace-by-CLI and Start Anyway's re-start keep the current values. Start Anyway's new session gets the flag only because it is a fresh UI start.
- Lint: `uiStartedInProcess =` and `activitySince = nil` are allowed only in `SessionController.swift`.

**M3. The fixed 5% floor is skipped when the Mac reports AC power or no battery (§2.6 Rules, `allowsBackgroundWork`).**
- The rules say "desktops (`!hasBattery`) skip battery rules; on AC battery rules don't apply", and the hard floor applies "on battery".
- Two common cases defeat the floor that priority (3) says "nothing can weaken":
  1. **AC but discharging:** an underpowered USB-C charger or hub passthrough under load reports `AC Power` with `IsCharging = false` while the percentage falls.
  2. **No battery entry:** a transient or failed `IOPSCopyPowerSourcesInfo` read with no internal-battery entry makes `hasBattery == false`. That is the desktop path, so the floor never fires and the unreadable-reads rule never fires either.
- Fix:
  - Hard floor and `allowsBackgroundWork` use `batteryPresent && !charging && percent < 5`, whatever `onAC` says.
  - Latch `batteryPresent` for the process lifetime: from IORegistry `AppleSmartBattery`, or from the first internal-battery IOPS entry.
  - A latched laptop with no battery entry counts as an unreadable read.
  - Add Kit tests for both cases.

## Low

**L1. The `awake hold` peer-pid rationale is wrong (§2.10 `ControlPeer` comment, §3.1).**
- "The peer is alive and waiting" isn't guaranteed. A client can write its request and exit before `accept`, after which the pid may be reused.
- XNU's `LOCAL_PEERPID` reports the peer socket's last owner (`last_pid`), not necessarily the process that connected. Inherited fds and SCM_RIGHTS-passed fds change it.
- The impact is only the lifetime of a same-user CLI hold, so keep the design but reword the comment as "best effort, not identity".
- Refuse when `ProcessWatch.watch` fails on the peer pid.
- Add tests for a client that exits before accept, an inherited fd, and a half-close (CLIClient must never half-close).

**L2. Held connections don't fit the current `ControlConnection` (`ControlServer.swift:251–377`).**
- `readAvailable` ignores bytes after the request (l.297), so a held client can stream data and keep the control queue busy for 24 h. Any byte after the request on a held connection should end the hold.
- The slot count drops only in `onFinish` (l.239–242). The holding reply must release the slot exactly once, and finish must not release it again.
  - Assert `active >= 0`.
  - Test: hold, then 4 normal requests are accepted and a 5th gets "busy"; after EOF there's no double release.
- `onClose` runs once, on main, for every close path.

**L3. Snapshot bounds trust snapshot fields (§2.14 `sanitized(now:)`).**
- "deadline ≤ start + 30 days" uses the snapshot's own `startedContinuous`, so a future value makes the bound meaningless. A `hold` deadline isn't tied to its 24 h cap.
- Fix:
  - `startedContinuous ≤ now.continuous`;
  - `deadline ≤ startedContinuous + (hold ? holdMaxCapSeconds : maxSessionSeconds)`;
  - `maxSeconds` and `deadline` must be consistent, otherwise drop the session.

**L4. "Outside snapshot writes are ignored" depends on usage, not on the store (§2.5 `restore`, §3.2 last row).**
- `ConfigStore` installs a `DefaultsKeyObserver` for every key and replaces `value` (`ConfigStore.swift:50, 56–69`).
- State that `SessionController` never reads `stateStore.value` after `restore`, and always writes a whole snapshot built from runtime state.
- Add a test for it.

**L5. The activity cap resets per automatic session (§2.9 "the counter resets when that automatic session ends").**
- Adjacent schedule rules (≤ 32), written by the user or by a defaults writer, chain 1 h caps into continuous `declare`.
- Not an escalation (declaring needs no TCC). Carry `activitySince` across back-to-back governing sessions, or call the cap a UX bound in §3.3.

**L6. Privacy-at-rest claims are too strong (§3.6).**
- "No activity timeline exists anywhere" is false:
  - `SnapticAwakeHistoryV1` holds 90 days of start/end times and bundle ids.
  - `recentApps` and rule definitions (app, device and network names) are plaintext in a domain any unsandboxed same-user process can read.
- Router-MAC hashes keep `SnapticAwakeSalt` in the same domain. About 24 unknown bits per OUI makes them brute-forceable locally.
- Reword: "not in logs, diagnostics, CLI or exports; history is a local timeline (Clear, or turn History off)". Also state that salted hashes protect exports, not local readers.

**L7. Stale r2 wording and backup defense in depth (§2.2 table, §3.6 Import).**
- Two phrases still refer to a concept r3 removed: "the floor's on/off is a protected setting" (§2.2) and "protected fields always kept from the current config" (§3.6).
- Name the fields instead: `features.pointerNudge`, `drives.volumes`, guards monotonic.
- `KitBackup.sensitiveKeyFragments` doesn't match any Awake key. Add `removedPaths` entries `awake.drives`, `awake.features.pointerNudge`, `awake.sessions.startAtLaunch` and `awake.sessions.recentApps`, so the generic strip holds even if `exportable` regresses. 

**L8. Focus theft through reopen (`AppDelegate.swift:122`) and `open-settings`.**
- Any process can bring Settings, on a page it chose, forward while the user types. A stray Return on a default Start button becomes a UI start with attacker-chosen nudge.
- Fix: no `.defaultAction`/Return shortcut on session-start controls, and ignore start actions for 1 s after an externally requested `openSettings`.

## Verified sound
No outside route to a UI start: no URL scheme, sdef, Services or Apple Event handlers, and reopen only opens Settings. Synthetic input and `AXPress` need Accessibility in the sender, which could then move the pointer itself, so the R5.7 residual is correct. `uiStartedInProcess`, `activitySince` and `overrideGuards` aren't in `CodingKeys`, so restored, resumed and launch sessions never nudge. `--pid` arms before it verifies and checks the effective uid. At most one held connection exists. untilIdle reads IORegistry `Statistics`, same-uid `proc_pid_rusage` and `NET_RT_IFLIST2` aggregates with no TCC. `hardFloorPercent` is a constant, kill switches only disable, and `RevertJournal.recoverAtLaunch` (`AppDelegate.swift:62`) runs whatever the module switches say. Nothing is drawn on the lock screen or off console. `action run` never reaches an `AwakeActionID`.
