# Snaptic 0.3 plan: Awake module, Settings redesign, Menu bar redesign

Status: **r3** (planning architect, after review round 2; r2 kept as `PLAN-r2.md`, r1 as `PLAN-r1.md`). Base: `feature/displays` == `main` @ 871c10b.
Normative like `docs/design/PLAN.md` (0.2): where this plan and 0.2 disagree, **this plan wins** for 0.3 scope; everything 0.2 says that this plan does not touch (safety framework, helpers, guard, transactions, R5 amendments) stays in force. Swift signatures in this document are the contract the lead writes as compiling stubs in step 0; once on the branch, the code wins over prose (R5 rule carried forward).

Inputs: `docs/design/0.3/{awake-parity.md, power-apis.md, ui-audit.md, design-spec.md}` (cited as [AP], [PA], [UA], [DS] with section numbers).

## r3 changes

Resolves review round 2 (`review-r2-{parity,security,code,design,consistency}.md`) and applies the lead's r3 decisions. Totals: **parity** 1 B + 6 M + 12 m resolved, 0 rejected; **security** 1 H + 5 M + 5 L resolved (M4, M5 partly rejected), 1 L rejected (L6, moot); **code** 12 signature rows + 11 M + 13 m resolved (R2-M5, R2-M11 and two signature rows retired with the mechanism they fixed), 0 rejected; **design** 7 M + 14 m resolved (m2, m13 partly rejected), 0 rejected; **consistency** 1 B + 7 M + 14 m resolved (M6, m11 retired), 0 rejected.

**Lead decisions (normative)**

| Id | Resolution | Sections |
|---|---|---|
| lead-1 consent | Keychain consent, `AwakeConsent`, `AwakeConsentStore`, `ConfigStore(admit:)`, L11 and HW-22 withdrawn. Pointer movement only for sessions started by a direct UI action in this process (`uiStartedInProcess`, never persisted), never CLI/rule/launch/restored/resumed, never locked/off console, capped 1–8 h on Snaptic's continuous clock; Drive Alive volumes chosen in the UI, stored by UUID; outside config changes take effect; fixed 5% hard floor + critical heat; residual risk table; CLI `extend` no longer needs r2's nudge refusal (extending a session never extends the activity cap) | N10, §1.1, §2.3, §2.6, §2.9, §2.14, §3.2, §3.3, §6.5, HW-19 |
| lead-2 MDM | No managed preferences (0.2 rule); `Awake.disable.<feature>` + new `Modules.disable.<id>` from the persistent domain; deployable by a configuration profile; managed screen-lock detection dropped | N14, §1.2, §2.2, §2.12, §6.4 step 5 |
| lead-3 hold | `awake hold`: client holds its own connection (EOF or peer-pid exit ends it), `--pid N` binds a same-uid pid (kqueue NOTE_EXIT armed first, start time re-verified), cap 12 h / `--max` ≤ 24 h; no command wrapping; usage + parent-shell pitfall; `ControlPeer`/`ControlHold`/`ControlContext` in ControlServer (A, step 1) | N1, §2.3 `HoldBinding`, §2.5, §2.8 `ProcessWatch`, §2.10, §3.1, §6.2, §6.4, HW-21 |
| lead-4 untilIdle | Busy = top same-user process ≥ 50% of one core OR total CPU ≥ 15% OR disk ≥ 1 MB/s (IOBlockStorageDriver) OR network ≥ 50 KB/s; ends after 5 quiet min; `TaskQuiet`, `CPUMath`/`DiskMath`/`NetworkMath` | N9, §2.3, §2.5, §2.8, §6.6, HW-23, OQ-8 |
| lead-5 run loop | Timers in `.common` mode, `DispatchQueue.main` coalescing, lint L14 | N15, §2.1, §2.5, §4.5, §5.1, §5.3, §6.3 |
| lead-6 Awake menu | One `AwakeMenuRows` for both surfaces; "Keep Awake" header; Until Turned Off first-level; Start Session ›; Keep Display On while active; idle 6 rows, active 10 | §5.3, §5.4 |
| lead-7 menu parity | Every 0.2 `DisplayMenuItemID` (46) has a 0.3 location or a reason; Customize Displays Menu shows/hides each; `ControlID` registry (`ControlCatalog`, `MenuItemCatalog`, frozen `ControlMapLegacy`), `--selftest-controls` for Switcher keys, DEBUG `ControlCoverage` | N16, §4.3 Menu Bar, §4.8, §5.2, §6.4, §6.5 |

**Parity**

| Finding | Resolution | Sections |
|---|---|---|
| B1 | lead-7: full menu table; Saved Layouts ›, Virtual Displays ›, Picture in Picture ›, Actions ›, Display Tools additions, per-display toggles/headers | §4.8, §5.2 |
| M1 | lead-7 tables + Switcher mirror checked by self-test + DEBUG coverage gating step 3 | §4.8, §6.4 |
| M2 | lead-4 | §2.5, §2.8 |
| M3 | lead-3; reply names the pid; < 2 s exit toast; `status --json` `pid`; README recipes | §2.5, §2.10 |
| M4 | ✓ Keep Display On in both menus and the status row's Options ▾; page toggle applies to a running default-options session | §2.14, §4.3, §5.3, §5.4 |
| M5 | `sharedActiveGlyph = governing && showShared`; sessions never remove an at-rest item; HW-14 notch case | N11, §5.2, §5.5 |
| M6 | Header switch X; migration M10; dimmed disconnected device row with Connect | §4.6, §4.8, §5.2 |
| m1 | Displays root status rows (automation paused, Safe Mode, helper) + map row | §4.3, §4.8 |
| m2 | `PerDisplayPicker` on Brightness and Dimming | §4.3 |
| m3 | Switcher Screen Recording row, onboarding chips, card target, footer rows mapped | §4.3, §4.7, §4.8 |
| m4 | Displays Advanced › Permissions group | §4.3, §4.8 |
| m5 | Rule editor: conditions list +/− ≤ 8, is/is not, After I turn it off | §4.3 |
| m6 | "At most" for untilIdle presets and app sessions | §2.14, §4.3 |
| m7 | CLI untilIdle presets get the 12 h cap | §2.5, §2.10 |
| m8 | "Awake Settings… ⌘," is the only Settings item in the Awake menu | §5.2, §5.3 |
| m9 | Keep Display On only while active; page help line | §4.3, §5.3 |
| m10 | Pause moved to menu/hotkey; status row shows paused | §4.3 |
| m11 | `.hidden` falls back to Show When Active with a toast | §5.2 |
| m12 | Start Again hidden for process and automatic entries | §1.1, §4.3 |

**Security**

| Finding | Resolution | Sections |
|---|---|---|
| H1 | lead-1 (mechanism withdrawn; facts in §3.2) | N10, §3.2 |
| M1 | Superseded: nothing is id-bound any more; pointer movement needs a live UI start; residual stated | §3.2 |
| M2 | Cap on Snaptic's clock; idle never `anyInput`, per-type counters, declaration echoes excluded; HW-5 | §1.1, §2.8, §2.9 |
| M3 | `.awake` events counted only (errors in the ring); `eventLines()` filters by `isExportedInDiagnostics` | §3.6 |
| M4 | **Partly rejected**: lead-3 uses `LOCAL_PEERPID` + start time (lead decision; the peer is alive and blocked when read, and a connection hold ends on EOF anyway) rather than `LOCAL_PEERTOKEN`; adopted: read before the request, never from the request, arm-then-verify, pid ≤ 1 refused, same uid | §2.5, §2.8, §2.10 |
| M5 | **Partly rejected**: no managed-pref reading (0.2 rule, lead-2); adopted: a module-level kill switch (`Modules.disable.awake`) and unkillable applies per feature | N14, §2.2 |
| L1 | `source` kept through restore (no `.restored`); Drive Alive ignores CLI sources incl. restored | §2.3, §2.9 |
| L2 | Snapshot read once at start; guard holds recomputed | §2.5, §2.6 |
| L3 | `MNT_LOCAL`/`MNT_RDONLY`/`MNT_ROOTFS` + `f_mntfromname` = eligible BSD name | §2.8, §2.9, §3.4 |
| L4 | §3.1 says UX not boundary; didstart hint ≤ 10 s; CLI never replaces a UI session (`.uiSessionRunning`) | §2.3, §2.5, §2.8, §3.1 |
| L5 | `importable` after `KitBackup.merge`; hostile-backup test | §2.14, §6.6 |
| L6 | **Rejected (moot)**: consent read/record failures no longer exist | — |

**Code**

| Finding | Resolution | Sections |
|---|---|---|
| sig overrideGuards | `= false` + explicit `CodingKeys` (also `uiStartedInProcess`, `activitySince`) | §2.3 |
| sig facts init | `package init` on DisplayFact/USBFact/NetworkFacts/BluetoothFact | §2.7 |
| sig static lets | `specs`, `activationOrder`, ControlMap tables are computed `{ get }`; `AwakeConsent.empty` gone | §2.2, §4.8 |
| sig defaults | `recentNudges`/`recentDeclarations`/`volumes` `= []` + `init()` | §2.9 |
| sig observedSections | Requirement in the protocol body + extension default | §4.5 |
| sig ActivityDecision | `.skip` | §2.9 |
| sig lossy | Hand-written lossy decoders for GuardMemory, AwakeBehavior, TriggerSuppression, DriveAliveVolume | §2.6, §2.7, §2.14 |
| sig criterion entry | `{"criterion":{…},"negated":…}`; nested enums under `"condition"`/`"match"` | §2.7 |
| sig StatusItemPlan | One declaration (lead, ConfigModules) with defaulted fields | §5.2 |
| sig ModulePreferences | Both inits until step 3 | §4.6, §5.2 |
| sig record → Bool | Retired with the consent store | — |
| sig 1,000 inputs | Assert `needsSwap == false` | §2.4, §6.6 |
| R2-M1 | Occurrence counts, warn-then-`--strict`, TEAMS.md owner exception, L5 lookbehind | §6.3 |
| R2-M2 | Extension defaults + `settingsPages()` kept; forwarding removed at step-3 exit; lead declares `MenuPresence`/`StatusItemPlan`; `case .awake`, stub module | §2.11, §4.1, §4.5, §6.4 |
| R2-M3 | Snapshot `bootSession`; drop `until` suppressions, reset guard memory | §2.6, §2.7, §2.14 |
| R2-M4 | Never create past the deadline; `max(1, ceil(…))`; verify after expiry + arbitrate | §2.4 |
| R2-M5 | Retired (lead-1) | §3.2 |
| R2-M6 | `applyStatusItem(CustomItemRow)`, `requestStatusPlan`, `setPresence` | §2.11, §5.2, §5.3 |
| R2-M7 | lead-5 | N15 |
| R2-M8 | Kit `sanitized(now:)` + `SessionController.restore(_:)` | §2.5, §2.14 |
| R2-M9 | lead-3 (owner A, server-side peer, refuse ≤ 1, re-verify after arming, reply names pid, recipes) | §2.10 |
| R2-M10 | lead-4 (top process instead of busiest core, per lead), loopback/tunnel rule, wake reset | §2.5, §2.8 |
| R2-M11 | Retired: no admission hook in `ConfigStore` | §2.14 |
| m1 | PreventDiskIdle separate, no timeout; `takeRetainedValue` | §2.4 |
| m2 | 14.0–14.3 subtitle in the title | §5.1 |
| m3 | Highlight drawing, AX label, fixed header height, slider phase order | §5.1 |
| m4 | L10 bans selector observers and unreceived publishers | §2.1, §6.3 |
| m5 | Only `EventLog.swift` names `.awake`; L9 | §3.6, §6.3 |
| m6 | `ConfigSlice` as `@StateObject` | §4.5 |
| m7 | Optimistic `.live` target, 1 s readback ignore | §4.5 |
| m8 | `upgradeDefaults()` inserts Awake disabled | §2.13 |
| m9 | Round-trip note, Awake presence-absent mapping, save order, deterministic ids | §4.6 |
| m10 | Hand-formatted ISO time in `AwakeCommandGrammar` | §2.10 |
| m11 | `actions: [ToastAction]` | §2.5 |
| m12 | `CGSSessionScreenIsLocked` in HW-1; DiskArbitration off main | §2.8 |
| m13 | One `ChangeFanout` per K16 instance; onboarding step dropped (design m11) | §4.7, §6.3 |

**Design**

| Finding | Resolution | Sections |
|---|---|---|
| M1 | `AwakeMenuRows`; header "Keep Awake"; Start Session › | §5.3, §5.4 |
| M2 | lead-6 (6 idle / 10 active; Custom…; subtitle for rules) | §5.3 |
| M3 | Toast at first activation, state-dependent card, "New" sidebar badge | C7, §4.2, §4.3, §4.6 |
| M4 | No section switch; rule rows → editor sheet with On + Delete Rule…; rule/condition terms; Pause in menu/hotkey | §2.7, §4.3, §4.4 #17 |
| M5 | Control Center wording, one option order, Show When Active for Displays, Snaptic icon last, Time default Don't Show, Style help | C2, §4.3, §4.6 M2 |
| M6 | Mockup C, Brightness and Dimming, height 720, Undo/Redo in Quick Changes + ⌘Z, "Extended display" | §4.2, §4.3 |
| M7 | Mockup D (no Menu bar icon › row, idle copy, Battery level, no source noise) | §4.3 |
| m1 | Serial comma rule | §4.2, §4.3 |
| m2 | **Partly rejected**: every string adopted except "Stop when inactive for" → "Stop appearing active after" (the cap no longer measures inactivity, lead-1) | §2.3, §4.3 |
| m3 | Mute in the Turn Off Display group | §5.2 |
| m4 | Awake Settings… only | §5.3 |
| m5 | Lid line only on battery or without an external display | §2.12, §5.3 |
| m6 | EDID Export → Display Information; LUT import → PIP page; Export Settings panel after its sheet | §4.3 |
| m7 | Field width from the widest value; discrete snap | §4.1 |
| m8 | Reset glyph only off-default; nil default keeps the slot | §4.1 |
| m9 | Empty-state copy | §4.3 |
| m10 | Glyph tiles radio group; list row actions; end announcement only | §4.1, §5.3 |
| m11 | Awake onboarding step dropped; icon line in Choose Modules | §4.7 |
| m12 | Behavior merged into Shortcut; More Shortcuts…; Spaces disabled with reason | §4.3 |
| m13 | **Partly rejected**: picker counting stated, Main display first merged; "Header row with one display" kept (a 0.2 setting; no setting lost) | §4.2, §4.3 |
| m14 | Display Tools ▾ in the Display section header; "Display Information…" in About | §4.3 |
| note | [DS] §1.4 "mini switches" is superseded by §4.1 (row switches at the form's default size) | §4.1 |

**Consistency**

| Finding | Resolution | Sections |
|---|---|---|
| B1 | `MenuPresence` in KitModules, `StatusItemPlan` stays in ConfigModules (lead); M owns the plan function; S rule covers §2, §4.1, §4.5, §4.8, §5.2 | §2.2, §5.2, §6.2, §6.3 |
| M1 | lead-3, owner A, step 1 | §2.10, §6.2, §6.4 |
| M2 | Activity switch rule + `effectiveOptions` clamp | §2.14 |
| M3 | "or no module is enabled"; everything Don't Show → no item | §5.2, §6.6 |
| M4 | `DisplayActionID.fShowPanel/.fIdentify` in Kit | §2.2, §4.6 |
| M5 | M6 restated (no data migration), B step 2, SafetyConfig test | §4.3, §4.6, §6.4 |
| M6 | Retired (no consent) | — |
| M7 | Signatures: `AwakeCommandGrammar`, `CPUMath`, `NetworkMath`, `DiskMath`, `AwakeMigrationResult`, `DisplaysConfigSection`, `DisplaysRestoreScope` | §2.8, §2.10, §4.5, §4.6 |
| m1 | 7 sidebar rows everywhere | §0, §4.2, §6.4 |
| m2 | Own-menu footer rule | §5.2, §5.3 |
| m3 | `.skip` | §2.9 |
| m4 | "Add 1 Hour" everywhere | §1.4, §2.5 |
| m5 | One confirmation text in §4.3 | §2.12, §4.3 |
| m6 | Per-kind "Default (…)" label | §2.14, §4.3 |
| m7 | "Exp" vs "X" | §4.8 |
| m8 | `perDisplayKeys`, `perDisplayPIP` | §4.5 |
| m9 | ConfigModulesTests line 16; `upgradeDefaults()` | §2.13 |
| m10 | ⇢ marks for MenuCustomizationPage, MenuSliderItem; ManagedMenuItem deletion; EventLog overload | §6.2 |
| m11 | Retired (onboarding step dropped) | §4.7 |
| m12 | ToastPresenter changes in lead step 2 | §6.4 |
| m13 | AwakeBehavior home; openSettings adapter; `MenuSwitchHeaderView` | §2.6, §2.11, §5.1 |
| m14 | Wireframes and counts aligned with defaults | §4.2, §4.3 |

## r2 changes (shortened; the full table is in `PLAN-r2.md`)

Resolved review round 1 (`review-r1-{parity,security,code,design}.md`): parity 2 B + 7 M + 14 m + 3 extra notes; security 2 H + 7 M + 6 L; code 3 B + 14 M + 13 m (1 m partly rejected: persisting "Start Anyway"); design 2 B + 10 M + 9 m (1 M partly rejected: `DateComponentsFormatter` in Kit). Main r2 results still in force: task kinds (`untilIdle`, CLI hold) and the 1 h CLI default; the §4.8 control map; `MenuPresence` as the only icon control; native "Turn Off Keep Awake"; per-session display policy defaults; guards unkillable, critical heat evaluated directly, `allowsBackgroundWork`; session-dictionary truth instead of notifications; verified-dirfd Drive Alive writes; closed `AwakeLogEvent`; typed export/import; lint ratchet; one coordinated `sleepPrevention` removal; `StatusItemProvider`; absolute assertion deadlines; in-memory hysteresis; migration markers; upgrader insertion; `queue: .main` observers; multicast sources; N12 hand formatting; per-id `ControllerRevision`, `ConfigSlice`, `DisplayLiveControlling`; step-0 feasibility; budgets; AppKit-only menu rows. **Superseded in r3**: the Keychain consent record and `ConfigStore` admission (security H1/H2, code M5 rows; now N10 and §3.2), "Own Icon When Active" wording (now Show When Active), `whilePID`/`--parent` (now `hold`), the 13/16-row Awake menu (now §5.3), and the managed-preference kill-switch reading (now N14).

---

## 0. Summary and decisions

Snaptic 0.3 does three things:

1. **Awake** (new module, `ModuleID.awake`): a free, MIT, public-API-only replacement for Amphetamine and Insomnia. Manual sessions (indefinite, duration, until a time, while an app runs, until downloads and tasks finish, while a command-line hold lasts), user-defined session types (presets), automatic sessions (rules with 12 TCC-free condition kinds, priorities, per-rule options), battery/thermal/Low Power Mode guards with a fixed 5% battery floor and a thermal end that nothing can weaken, activity simulation (pointer movement only for sessions the user started in Snaptic's UI), Drive Alive, its own menu bar indicator (shown while active by default) with optional countdown, hotkeys and `snaptic awake …` CLI (including `awake hold` for scripts). One named IOKit power assertion, swapped by type, with absolute-deadline `TimeoutActionRelease` backstops. Displays' `sleepPrevention` moves here.
2. **Settings redesign**: one SwiftUI component library (`Sources/Snaptic/SettingsUI/`), a new information architecture (sidebar 31 rows → 7; default visible settings controls ~245 → ~60, §4.3 counts), every option explained, every 0.2 setting, button, action and menu item mapped to a 0.3 home and checked by a `ControlID` registry test (§4.8), the 14 duplicates removed, expert options behind **Advanced…**, settings search, and the live-update root causes fixed in the architecture (observable per-display runtime, controller revisions, drag-local slider state, throttled commits, per-section config observation and fan-out).
3. **Menu bar redesign**: one menu item factory (`MenuKit`), one header style, AppKit-only custom rows (sliders, switch headers) with live values that update while the menu is open (`.common` run-loop mode), no sliders in submenus, one level of submenus, "Settings…" then "Quit" last, one presence pop-up per module with Control Center wording; every 0.2 opt-in menu item keeps a 0.3 location and a show/hide control; an Awake status item (shown while active by default) and one Awake row set (`AwakeMenuRows`) used by both the Awake menu and the compact Awake section of the Snaptic menu.

Priorities (0.2 order kept, Awake rows added): (1) never leave the user without a usable display, keyboard or way back; (2) nothing Snaptic does lets another process use Snaptic's permissions or see data obtained with them; (3) never damage a monitor **or drain a battery to shutdown** (Awake's critical-heat end and its fixed 5% battery floor have no setting and no kill switch); (4) parity; (5) polish.

### 0.1 Decisions taken here (normative)

| # | Decision | Why |
|---|---|---|
| N1 | CLI **may start** Awake sessions: closed grammar, guards apply, never pointer movement (N10), never Drive Alive (strict, OQ-1 settled; the session's `source` survives restore), never an unbounded session (`awake start` with no argument = 1 h; `awake hold` lasts while its own connection and process live, or while a named pid lives, and at most 12 h by default, 24 h with `--max`), never replaces a session the user started in the UI | §3.1: a same-user process can already hold the same assertion with `caffeinate`; nothing that uses Snaptic's TCC grants is reachable |
| N2 | Duration sessions run on the **continuous clock** (`CLOCK_MONOTONIC_RAW`, counts sleep, immune to clock changes); "Until" sessions are absolute wall instants; a reboot ends every session; trigger hysteresis is in-memory continuous-clock state and is never persisted | Predictable; matches Amphetamine; no recovery machinery; no defaults write per engine step |
| N3 | One **governing** source at a time: the manual session if any, else the highest-priority active trigger | Amphetamine's priority model; one assertion; one indicator reason |
| N4 | Every Settings slider gets a typed value field and a reset glyph; the field **is** the live value (no separate value label) | Explicit requirement; [DS] layout in §4.1 |
| N5 | All modules always appear in the sidebar; each module page has a header switch (Wi-Fi pattern) whose accessibility label and tooltip are "Use <Module>"; session-level actions are **buttons**, never a second switch | [DS] §1.2; design B1, parity M7 |
| N6 | Displays' 16 sidebar pages become **one** sidebar row with sub-pages in a `NavigationStack` | [DS] §1.1, [UA] §2.1 |
| N7 | Everything about the menu bar (presence per module, icons, countdown, Displays menu customization) lives **only** on the Menu Bar page | Removes duplicates 4, 13 and the Awake split |
| N8 | Displays feature switches live where the feature is used (sub-page header switch, section switch or Advanced › Use Snaptic for); the 47-switch Features page is deleted | [UA] §2.5 #4 |
| N9 | Two task-bound session kinds: **Until Downloads and Tasks Finish** (`untilIdle`: ends after 5 min with no busy signal; busy = top process ≥ 50% of one core, or total CPU ≥ 15%, or disk I/O ≥ 1 MB/s, or network ≥ 50 KB/s) and **command-line hold** (`hold`, CLI `awake hold`) | Parity B1, M2, M3; code R2-M10 |
| N10 | **No consent record** (r2's Keychain record is withdrawn: forgeable under the legacy file keychain that ad-hoc builds use, and lost on every ad-hoc update). Instead: (a) **pointer movement** acts only for a session started by a direct user action in Snaptic's own UI in this process (menu click, Settings button, Snaptic hotkey), never for CLI, trigger, restored or resumed sessions, never while the screen is locked or the session is off console, and at most `activity.stopAfterHours` (default 1 h, max 8 h) measured on Snaptic's own continuous clock, never on system idle time (Snaptic's own declarations reset idle); (b) **Drive Alive** volumes are chosen in the UI and stored by volume UUID; (c) a fixed 5% battery floor and the critical-heat end apply whatever the config says. Config changes made outside Snaptic take effect like any setting; the residual same-user risk is stated in §3.2 | Lead r3; security H1/M1/M2, code R2-M5 |
| N11 | A running Awake session is never invisible: whenever Awake governs and the Snaptic item exists, the Snaptic icon shows its active variant (whether or not an Awake icon exists); if no Snaptic icon exists, the Awake icon appears for the session; a session never removes an item that was shown at rest | Parity M2, M5 |
| N12 | SnapticKit formats user-visible numbers, durations and clock times **by hand** from explicit inputs (`AwakeTextContext`), never through Foundation formatters | Code M11: corelibs 5.10 and macOS ICU disagree; Kit tests run on both |
| N13 | Lint rules land in step 0 with a **ratchet** (`scripts/lint-legacy.tsv`) of known violations; a deleted file or symbol is removed only at the step-3 exit after a caller grep | Code B1, M10 |
| N14 | Snaptic does **not** read managed preferences (0.2 rule). Organizations use documented hidden defaults read from Snaptic's persistent domain: `Modules.disable.awake` (whole module), `Awake.disable.<feature>` (per feature; `sessions`, `batteryGuard`, `thermalGuard` ignored, use the module key instead). An admin can deploy them with a configuration profile that writes Snaptic's user domain | Lead r3; security M5 |
| N15 | Everything that must update while a menu is open (countdown, live rows, slider binds, `ControllerRevision` coalescing) runs in `.common` run-loop modes: timers via `RunLoop.main.add(_:forMode: .common)`, coalescing via `DispatchQueue.main.async`; `Timer.scheduledTimer` and `RunLoop.main` schedulers are banned in menu and Awake code (lint L14) | Lead r3; code R2-M7 |
| N16 | Every 0.2 setting, button/action and menu item has a declared 0.3 `ControlID` (or a removal reason) in Kit tables that a test checks against frozen 0.2 lists; every 0.2 opt-in menu item keeps a menu location and a show/hide control in Customize Displays Menu | Lead r3; parity B1, M1 |

### 0.2 Decisions to confirm (lead)

| # | Proposal (r2 wording) | Default if not confirmed |
|---|---|---|
| C1 | While the screen is locked, a `keepOn` session downgrades to system-only (display may sleep, Mac stays awake); Advanced option "Keep the display on while locked" | Adopt |
| C2 | Replace `MenuPlacementChoice` (shared / own / hidden) with `MenuPresence`, one pop-up per module, Control Center wording and one option order for every module: **Always Show in Menu Bar / Show When Active / Show in Snaptic Menu / ─ / Don't Show** (`ownIcon / ownIconWhenActive / inSnapticMenu / hidden`); *Show When Active* exists for Awake (a session runs) and Displays (an external display is connected; replaces "Hide when no external display is connected"); `placement` keeps being written for 0.2 downgrades | Adopt (migration M2, §4.6; design M5) |
| C3 | Drop the right-click "quick menu" (right-click is not delivered on macOS 27 [PA] §8); its items move into **Display Tools ▸** | Adopt |
| C4 | Menu slider rows show a live value but no typed field or reset; every slider action and every Awake action also exists as a **native** menu item, shortcut or Settings control | Adopt |
| C5 | "Network activity above N KB/s" criterion (interface byte counters via `sysctl NET_RT_IFLIST2`, loopback excluded, tunnels counted only when no physical interface moved bytes; no connections, no TCC) replaces the TCC-gated Downloads-folder criterion; the same counters, plus CPU and IOKit block-storage counters, drive `untilIdle` | Adopt |
| C6 | Bluetooth criterion limited to Bluetooth **audio** devices (CoreAudio transport type) and Bluetooth **input** devices (IORegistry `IOHIDDevice` `Transport` property, never opened); Beta | Adopt |
| C7 | 0.1/0.2 → 0.3 upgraders get Awake **off** (ModuleHost and `upgradeDefaults()` insert it disabled before M1 runs) unless M1 produced an enabled rule from **effective** 0.2 sleep prevention. Upgrade experience (design M3): a state-dependent General card (Awake off: "New: Awake" [Turn On Awake] [Not Now]; migrated: "Your display sleep setting moved to Awake." [Show Awake] [OK]), a one-time toast at a migrated user's first activation, and a "New" sidebar badge on Awake until the page is first visited | Adopt |
| C8 | Menu item "Switch Windows ⌥⇥" opens the switcher in sticky mode (stays open until Return/Esc/click); new small Switcher capability (A) | Adopt; fallback: omit the item |
| C9 | Drive Alive runs only while an Awake session whose `source` is not `.commandLine` is active (restored sessions keep their source), unless the user turns on "Also when no session is running"; the battery floors and thermal guard gate it in **every** mode | Adopt |
| C10 | Default session from the UI (status-row button, menu, hotkey) = the default preset, **Until Turned Off** out of the box; from the CLI, `awake start` without an argument = 1 h | Adopt (Amphetamine parity for the UI; no unbounded CLI sessions) |
| C11 | Default Awake presence = **Show When Active** (`ownIconWhenActive`; fresh installs and upgraders whose M1 rule is on): one Snaptic icon at rest, the Awake icon beside it during a session | Adopt (design M3, parity M2) |

**Lead (r1):** C1–C10 adopted as proposed. **Lead (r2):** C2, C5, C7, C9, C10 re-worded and C11 added. **Lead (r3):** N10, N14–N16 and the `awake hold`, `untilIdle` and Awake-menu shapes are lead decisions; C2, C5, C7, C9, C11 re-worded after review round 2; adopted unless the lead objects. OQ-1 is settled (strict); OQ-2…OQ-8 take their stated defaults until hardware testing says otherwise.

Open questions (need hardware or product input) are marked **[OQ-n]** and collected in §6.8.

---

## 1. Scope

Legend: **Def** = A always on with the module, S standard (on), O opt-in, X experimental, B beta tag. Amphetamine references are [AP] §1.x, Insomnia [AP] §2.x.

### 1.1 Awake: In

`AwakeFeature` (Kit, persisted raw values) and what each covers.

| Feature id | Covers | Def | Requires | Parity |
|---|---|---|---|---|
| `sessions` | Manual sessions: indefinite; duration (presets + custom h/m); until a clock time; while an app runs (picked from running apps, by bundle id, ends when its last instance quits; optional "At most" cap); **until downloads and tasks finish** (`untilIdle`: ends after 5 min with no busy signal, §2.5; 1 min start grace; optional "At most" cap); **command-line hold** (`hold`, CLI only, §2.10); extend (+15 min / +1 h / Add Time… for timed kinds and capped task kinds; no-op items are not shown); end; replace; display policy per session (keep on / can turn off / keep on until idle for N min), changeable mid-session ("Keep Display On" in the menu and the status row's Options ▾); end on sleep (opt), end on user switch (immediately / after 1 h / never), end after the screen has been locked for N h (opt); resume after Snaptic relaunch within the same boot; start a session at launch (opt); "why is my Mac awake" lid notice (on battery or without an external display); 5-minute reminder; **8-hour reminder** for indefinite sessions; last non-user end shown for 12 h | A | — | Amph 1.2 (incl. "while downloading" via `untilIdle`), 1.3 display sleep incl. mid-session toggle, 1.4 manual-sleep / FUS ends, 1.8 reason text; Insomnia 2.2 timed sessions, chips, 30-day cap; `caffeinate -w` (CLI `hold --pid`) |
| `presets` | Session types: up to 12 named presets (kind + optional options, nil = "Use default"; task kinds with an optional "At most" cap), shown in the Awake menu's Start Session › in order; default preset; last custom value remembered | A | sessions | Amph "default duration", "Other Time" memory (1.2); Insomnia preset chips |
| `batteryGuard` | End below N% on battery (5–50%, default 20%; the user floor can be turned off); **independently, a fixed 5% floor** (`AwakeGuards.hardFloorPercent`, no setting, no kill switch) always ends sessions and Drive Alive on battery; end on adapter disconnect (opt); end on Low Power Mode (opt); two unreadable battery reads on battery → end; rule restarts suppressed until cleared (+5% hysteresis or AC) | A | — | Amph 1.4; Insomnia 2.5 floor and unreadable rule |
| `thermalGuard` | `.critical` → end all sessions and stop Drive Alive, pause automatic sessions 10 min; `.serious` → one-time toast (no setting) | A | — | Insomnia 2.5 |
| `indicator` | Internal capability (kill switch only, not a user feature): Awake's own status item; **Time: Don't Show / Time Remaining / End Time** (default Don't Show); glyph family cup / eye / lightbulb (outline idle, `.fill` active); seconds only in the last minute; VoiceOver label and tooltip refreshed at every countdown change. Whether the item exists is `MenuPresence` alone (§5.3) | A | — | Amph 1.8 (no custom images); Insomnia 2.6 countdown |
| `triggers` | Automatic sessions ("rules", each with **conditions**): ≤ 32 rules, each ≤ 8 conditions, All/Any, "is / is not" per condition, order = priority, per-rule session options, start delay, end delay (hysteresis), "After I turn it off: resume when the conditions are next met / after N min", "Pause automatic sessions for 1 h / until tomorrow" (menu and hotkey). Turned on implicitly by the first **Add Rule…** (no section switch, design M4) | O | sessions | Amph 1.5 (all criteria except SSID and the Cisco VPN brand; DNS servers covered by subnet + router) |
| `activity` | "Appear active": `IOPMAssertionDeclareUserActivity` every 60 s while a session runs, the screen is unlocked and on console (read from the session dictionary, §2.9), the user hasn't typed or clicked for ≥ 60 s, and the displays are awake; it stops `stopAfterHours` (default 1 h, 1–8 h) after it first acted in the session, **measured on Snaptic's continuous clock** (N10), until the user starts or restarts a session in the UI | O | sessions | Amph 5.0 cursor movement (closest TCC-free equivalent) |
| `pointerNudge` | "Move the pointer slightly": a 1-pt mouse-moved event and back, posted from a private event source with `CGEvent`, only with Accessibility, same conditions as `activity`, **only for sessions started by a direct user action in Snaptic's UI in this process** (N10), never within 2 pt of a display edge, never keyboard or clicks; while it acts, the menu and status row say "Moving the pointer" | X | activity | Amph 5.0 "Move the mouse cursor periodically" |
| `driveAlive` | Per external volume opt-in, chosen in the UI and stored by volume UUID; tiny periodic write + `F_FULLFSYNC` to `/<volume>/.snaptic-keepalive` via a verified directory fd (§2.9); every 30–600 s (default 120); `PreventDiskIdle` while active; only during sessions whose source isn't the CLI unless "Also when no session is running"; battery floors and thermal guard apply in every mode | O | — | Amph 1.6 |
| `history` | Local history (≤ 500 entries, 90 days; entries < 60 s that ended `.replaced` are merged), today/7-day totals, "Start Again" (app sessions keep their bundle id locally; not offered for command-line and automatic entries), clear; never exported, never in diagnostics | S | — | Amph 1.10 statistics |
| `shortcuts` | Global hotkeys: Keep Awake on/off (default preset), Keep Display On (toggle), Start “<preset 1–4 name>”, Pause automatic sessions; all unbound by default | S | — | Amph 1.10 |
| `commandLine` | `snaptic awake status|start|hold|stop|extend|preset|pause` (§2.10); needs the host CLI switch (General) | S | — | Amph AppleScript 4 commands (equivalent surface); `caffeinate -w` |

Always present (not flags): **Other apps keeping your Mac awake** — an inline live section in Awake › Advanced (`IOPMCopyAssertionsByProcess`, plus a warning when the system-wide `SleepDisabled` setting is on, read with `IOPMCopySystemPowerSettings`, the trace left by Amphetamine Power Protect, Insomnia or `pmset disablesleep`; never in logs, diagnostics or CLI); "Closing the lid will put your Mac to sleep" line in the Awake menu when a session is active on a laptop not in desktop mode (`AppleClamshellCausesSleep`).

**Criterion kinds** (`AwakeCriterionKind`; availability per kind, no feature flags):

| Kind | Source (J) | API | TCC | Parity |
|---|---|---|---|---|
| `app` (running / frontmost) | AppMonitor | `NSWorkspace` launch/terminate/activate notifications | none | Amph 4.0 |
| `display` (any external, ignore built-in; a specific display; mirroring on) | DisplayPresence | `CGDisplayRegisterReconfigurationCallback`, `CGGetOnlineDisplayList`, `CGDisplayIsBuiltin`, `CGDisplayIsInMirrorSet`; specific display by salted `FingerprintRecord` matched with B's `Fingerprint.matches` | none | Amph 4.2, 4.1.5; replaces Displays `sleepPrevention` |
| `power` (on adapter / on battery / charging / battery ≥ N%) | PowerMonitor | `IOPSCopyPowerSourcesInfo`, `notify_register_dispatch(kIOPSNotifyPowerSource / PercentChange)` (`import notify`) | none | Amph 5.0 |
| `schedule` (weekdays × start–end, overnight allowed) | Ticker (G) | wall clock; boundary dates from `Calendar.autoupdatingCurrent.nextDate`, Ticker capped at 15 min; wake, clock and time-zone notifications | none | Amph 1.5/3.0 |
| `cpu` (system CPU ≥ N%, 10 s average) | CPUSampler | `host_statistics(HOST_CPU_LOAD_INFO)` tick deltas, cached `mach_host_self()`, 5 s period while used | none | Amph 4.1.4 |
| `audio` (output playing / microphone in use) | AudioMonitor | `kAudioDevicePropertyDeviceIsRunningSomewhere` on default output / input, property listeners on a private queue | none (no mic access, property only) [HW-9] | Amph 4.0 audio output |
| `idle` (no input for ≥ N min) | IdleSampler | `CGEventSourceSecondsSinceLastEventType(.hidSystemState, t)` per input type (key down, flags changed, mouse down ×3, scroll wheel, mouse moved), minimum taken, mouse-moved resets within Snaptic's nudge echo window ignored; never `anyInput` (security M2; §2.9), 10 s period while used | none | Amph 4.1.5 |
| `volume` (a volume is mounted) | VolumeMonitor | `NSWorkspace.didMount/didUnmount`, `volumeUUIDStringKey` | none (listing only) | Amph 4.0 |
| `usb` (a USB device is connected) | USBWatcher | `IOServiceAddMatchingNotification(IOUSBHostDevice)` first-match + terminated, iterators drained | none | Amph 4.0 |
| `network` (IP in subnet; **connected to this network** = remembered router; VPN connected) | NetworkMonitor | `SCDynamicStore` `State:/Network/Global/IPv4`, `State:/Network/Interface/*/IPv4`; router MAC from the routing table (`sysctl NET_RT_FLAGS`), salted hash only [HW-11]; VPN = `utun*/ipsec*/ppp*` with an address and primary | none | Amph IP, IPv6, VPN (5.0, 4.1); the router criterion is the SSID substitute |
| `networkActivity` (C5) | NetworkMonitor | `sysctl NET_RT_IFLIST2` `if_data64` byte deltas (64-bit counters), 5 s period while used | none | Replaces "while downloading" as a rule; `untilIdle` covers the one-off case |
| `bluetooth` (C6, Beta) | BluetoothPresence | CoreAudio device list with transport Bluetooth/BLE; IORegistry `IOHIDDevice` with `Transport == "Bluetooth"` (properties only, never opened) | none [HW-10] | Amph 4.0 Bluetooth (partial) |

### 1.2 Awake: Deferred (feasible later without breaking the rules)

| Item | Reason |
|---|---|
| "While a file is downloading" via the Downloads folder | Downloads-folder TCC under Snaptic's identity; `untilIdle` and C5 cover the use case |
| General Bluetooth devices via IOBluetooth | Bluetooth TCC and possible kill without a usage string |
| Lock the screen after inactivity | `NSWorkspace.openApplication(ScreenSaverEngine)` is public and spawns nothing, but it locks only when "require password" is immediate, and Snaptic can't verify that setting ([PA] §7) |
| Screen-saver exceptions, per-trigger screen-saver delay | Needs measured behavior of assertions vs screen saver [HW-4] first |
| Sounds on start/end | Low value; adds options |
| App Intents / Shortcuts, AppleScript `sdef` | SwiftPM build can't process App Intents metadata; `sdef` needs bundle resources (`resources:` is banned) |
| Control Center / menu bar `ControlWidget` | Needs an app extension (entitlements, 26 SDK) |
| `expandedInterfaceDelegate` custom panel on 27 | 27 SDK only |
| Process-name criterion for faceless processes (`proc_listallpids`) | `hold` (`awake hold`) covers the agent and build case for 0.3; a standing rule needs a polling budget and would store process names |
| `awake hold -- <command>` (wrap a command) | Snaptic never runs commands (rule 12); scripts background `hold` or pass `--pid` (§2.10) |
| Reading managed preferences (MDM-forced keys, managed screen-lock detection) | 0.2 rule: Snaptic reads only its persistent domain; admins deploy the hidden kill switches (N14) |

### 1.3 Awake: Excluded (by design)

| Item | Reason |
|---|---|
| Closed-lid on battery (`pmset disablesleep`, sudoers rules, Power Protect, unprivileged clamshell SPI) | Root or SPI, persists after a crash, same-user exploitable, heat risk ([AP] §1.7, §3.3; [PA] §2). Awake › Advanced reports a leftover `SleepDisabled`; the README explains cleanup |
| Privileged helper, root, admin prompts, LaunchAgents/Daemons | Constraint |
| Turning Low Power Mode on/off | Needs root (`pmset -b lowpowermode`) |
| Wi-Fi SSID criterion | Location TCC + hardened-runtime location entitlement ([PA] §4); "Connected to this network" (router) is the substitute |
| DNS-server criterion | Not brand-specific and `State:/Network/Global/DNS` is TCC-free, but subnet + router already identify a network; one fewer editor |
| Cisco-AnyConnect-specific VPN criterion | Brand-specific; generic VPN covers it |
| Hold-to-end (Insomnia [AP] §3.1.5) | Stopping already takes two deliberate clicks or a shortcut |
| macOS notifications (`UNUserNotificationCenter`) | Snaptic uses ToastPresenter + menu state (0.2 §3.3) |
| `snaptic://` URL scheme | Any web page could fire it |
| Custom menu bar images, emoji icons | Curated template SF Symbols only |
| Insomnia lid-close actions (SIGSTOP apps, mute, keyboard backlight, App Nap writes into other apps' prefs), hotspot failover, tmux nudge, browser relaunch, `docker ps` | Invasive, run or inject code, network ([AP] §3.3) |
| Spawning `/usr/bin/caffeinate` | In-process assertions die with the process; spawning is banned outside HelperSpawner |
| Synthetic key events of any kind | Could type into the focused app |
| Options cut in r2: "different icon for automatic sessions", "show seconds", "also end on serious heat", activity interval | Low value per option ([DS] budget); seconds show in the last minute, serious heat keeps its toast, critical heat always ends, interval fixed at 60 s |

### 1.4 Parity map (Amphetamine → Snaptic Awake)

| Amphetamine | Snaptic |
|---|---|
| Indefinite / duration / until time / extend / default-duration quick start | `sessions` + `presets`; quick start = status-row button, menu, hotkey, `awake start` |
| While app running (sandbox-limited) | `sessions` (whileApp) and `app` criterion; not sandboxed, so all regular apps |
| While file downloading | `untilIdle` session ("Until Downloads and Tasks Finish") for one-offs; C5 `networkActivity` criterion for rules; `awake hold` for scripts |
| Allow display sleep; toggle mid-session by hotkey | `AwakeDisplayPolicy`; "Keep Display On" toggle in the Awake menu, the compact section and the status row's Options ▾ while active; hotkey |
| Screen saver / screen-saver delay | Deferred ([HW-4]) |
| Closed-Display Mode | Excluded; menu explains the native route (external display + power) |
| Move cursor periodically | `activity` (default, no TCC) + `pointerNudge` (X, Accessibility) |
| Lock screen after inactivity | Deferred |
| End on low battery / adapter disconnect / manual sleep / FUS | `batteryGuard`, `sessions` behavior options |
| Triggers: unlimited, priority, names, AND/OR | `triggers` (≤ 32, order = priority, All/Any + per-criterion negation) |
| Criteria: displays, USB, Bluetooth, app, battery/power, IP, SSID, DNS, VPN, audio, drive, CPU, idle, schedule | All except SSID (router substitute) and DNS (subnet + router); Bluetooth partial (C6) |
| Re-activate a manually ended trigger session after a time | `resumeAfterManualEndMinutes` ("After I turn it off" in the rule editor) |
| Drive Alive per drive + interval | `driveAlive` |
| Menu bar icon styles, active/inactive images, time remaining, 12/24 h, seconds | `indicator` (curated families, outline vs fill, time remaining or end time in the system's 12/24 h setting, seconds in the last minute) + presence "Show When Active" |
| ⌘-click quick start | Hotkey + status-row button (status item clicks always open the menu on 14–27) |
| Notifications, sounds, reminders | Toasts ("5 minutes left", "8 hours", "ended: battery low") + menu state + Recent Notices; no sounds |
| AppleScript, statistics, debug mode | CLI; `history`; Awake diagnostics in the shared report (counts only) |

Insomnia → Snaptic: timed sessions and chips (`presets`), 30-day cap (same), battery/thermal floors (`batteryGuard`, `thermalGuard`), countdown in the bar (`indicator`), "extend" reminder (toast at 5 min left with **Add 1 Hour**), soft reminder for indefinite sessions (toast after 8 h with **Turn Off** / **Keep Going**), sleep-disabled-by-another-process detection → "Other apps keeping your Mac awake" (+ `SleepDisabled`). Everything pmset/journal/backstop-based is unnecessary: assertions die with the process ([PA] §1.2).

### 1.5 Settings and menu redesign scope

| In | Deferred | Excluded |
|---|---|---|
| SettingsUI component library (§4.1) used by every page | String Catalog localization (strings keep going through `L()`) | Custom window chrome, fake glass, custom title bars |
| New IA for General, Menu Bar, Window Switcher, Displays (+ sub-pages), Awake, Permissions, About (§4.2–4.4) | Liquid Glass APIs, `preferredImageVisibility` (26 SDK) | Tabs inside pages, nested sheets |
| Search (`.searchable(placement: .sidebar)`, static index, scroll-to-anchor highlight; covers Advanced sheets) | Settings deep links from outside (no URL scheme) | Popover/panel menus for status items |
| Live-update fixes A1–A11, B1–B3, C1–C2, M1 ([UA] §1) | | |
| Config migration with no setting lost (§4.6) and the complete 0.2 → 0.3 control map (§4.8) | | |
| Menu redesign for all modules (§5), MenuKit, AppKit-only custom rows (MenuSliderRow, MenuSwitchHeader), one presence pop-up per module | | |
| Onboarding update: modules step adds Awake; one primary button location | | |
| Floating Displays panel restyled with the same row components | | |

---

## 2. Awake architecture

### 2.1 Shape (mirrors Displays, smaller)

```
AwakeModule (lead)            SnapticModule + StatusItemProvider; owns AwakeConfig store, snapshot and history stores
 └─ AwakeContext (lead)       services + controllers + AwakeHost; built per start; services hold it weakly
     Services (refcounted by need, AwakeServiceID; J unless noted)
       assertions  AssertionManager (G)   the ONLY IOPMAssertionCreate*/Release caller for sleep assertions (lint L1)
       power       PowerMonitor           IOPS notify, LPM, thermal, battery facts (multicast observers)
       system      SystemEventsMonitor    sleep/wake, screens sleep/wake, session facts (CGSession dictionary), screensaver hints, FUS, clock, TZ, day change, lid
       apps        AppMonitor             running/frontmost bundle ids, app list for pickers
       displays    DisplayPresence        online displays as FingerprintRecords, mirroring
       usb         USBWatcher             IOUSBHostDevice matching
       volumes     VolumeMonitor          mounted volumes (uuid, name, Drive Alive eligibility via DiskArbitration)
       audio       AudioMonitor           output/input running-somewhere (HAL calls on a private queue)
       cpu         CPUSampler             total CPU 10 s average; top same-user process (% of one core) while untilIdle runs
       disk        DiskIOSampler          IOBlockStorageDriver Statistics byte deltas (untilIdle only)
       idle        IdleSampler            per-type HID idle, nudge echoes excluded (IdleMath), last real input
       network     NetworkMonitor         IPv4/IPv6 addresses, router hash, VPN, 64-bit throughput (loopback excluded)
       bluetooth   BluetoothPresence      BT audio + BT HID presence (Beta)
       activity    ActivitySimulator      DeclareUserActivity / pointer nudge
       driveAlive  DriveAliveService      keep-alive writes on a private serial queue
       process     ProcessWatch           kqueue EVFILT_PROC/NOTE_EXIT + proc_pidinfo start time for `hold`
     Controllers (one per AwakeControllerID; G unless noted)
       sessions    SessionController      manual session lifecycle, presets, task kinds, arbitrate(), assertion plan
       guards      GuardsController       battery/thermal/LPM/sleep/FUS/lock policies
       triggers    TriggerController      criterion facts → TriggerEngine.step → cached top trigger
       activity    ActivityController (J) drives ActivitySimulator from runtime state
       driveAlive  DriveAliveController (J)
       indicator   IndicatorController    own status item (via AwakeModule's StatusItemProvider), countdown, glyphs; menus from AwakeMenuRows
       history     HistoryController      records ends, totals
       automation  AwakeAutomation        hotkeys + CLI verbs
```

Everything is `@MainActor` except `DriveAliveService`'s I/O queue, `AudioMonitor`'s HAL queue and the C callbacks (IOKit, CoreAudio, SCDynamicStore, CG reconfiguration), which use `CallbackTarget` and hop with `MainActor.assumeIsolated` from main-queue delivery (`IONotificationPortSetDispatchQueue(port, .main)`, `SCDynamicStoreSetDispatchQueue(store, .main)`, `notify_register_dispatch(…, .main)`); CoreAudio listeners run on AudioMonitor's serial queue and publish with `DispatchQueue.main.async`. **Every `NotificationCenter`/`DistributedNotificationCenter`/`NSWorkspace` observer in Awake passes `queue: .main`** (lint L10: `queue: nil`, selector-based `addObserver(self, selector:` and `publisher(for:)` without `.receive(on: DispatchQueue.main)` banned under `Awake/`; `thermalStateDidChangeNotification` and `NSProcessInfoPowerStateDidChange` post on arbitrary queues). Timers are created unscheduled and added with `RunLoop.main.add(t, forMode: .common)` with ≥ 10% tolerance, so they fire while a menu is open (N15); `Timer` doesn't count sleep, so wake re-checks stay. No `static let shared` and no `passUnretained` outside `CallbackTarget` in Awake (lint rules 7 and 10 extended to `Awake/`). EventLog category `.awake` (lead adds), written only through `EventLog.record(_ event: AwakeLogEvent)` (§3.6).

**Apply order** (same as Displays §3.6): resolve effective features → required services = `AwakeFeatureGraph.requiredServices(effective:criteria:dynamic:)` (features ∪ criterion kinds used by enabled triggers ∪ `dynamic` needs: `apps` while a whileApp session runs or a picker is open, `idle` while `keepOnWhileActive` governs, `taskQuiet` (cpu + disk + network) while an `untilIdle` session runs, `process` while a `hold` session runs) → stop emptied controllers → deactivate unneeded services (reverse) → activate needed services (in order) → start new controllers → notify the rest. A criterion source that isn't needed costs nothing: no notification ports, timers or listeners.

### 2.2 Kit ids and feature graph (lead, `SnapticKit/AwakeFeatureGraph.swift`)

```swift
package enum AwakeFeature: String, Codable, CaseIterable, Sendable {
    case sessions, presets, batteryGuard, thermalGuard, indicator
    case triggers, activity, pointerNudge, driveAlive, history, shortcuts, commandLine
}
package enum AwakeControllerID: String, Codable, CaseIterable, Sendable {
    case sessions, guards, triggers, activity, driveAlive, indicator, history, automation
}
package enum AwakeServiceID: String, Codable, CaseIterable, Sendable {
    case assertions, power, system, apps, displays, usb, volumes, audio, cpu, disk, idle, network, bluetooth
    case activity, driveAlive, process
}
/// Services a running session or open UI needs beyond features and trigger criteria (code M7).
package struct AwakeDynamicNeeds: OptionSet, Hashable, Sendable {
    package let rawValue: UInt8
    package init(rawValue: UInt8) { self.rawValue = rawValue }
    package static let apps = AwakeDynamicNeeds(rawValue: 1 << 0)       // whileApp session, app picker open
    package static let idle = AwakeDynamicNeeds(rawValue: 1 << 1)       // keepOnWhileActive governs
    package static let taskQuiet = AwakeDynamicNeeds(rawValue: 1 << 2)  // untilIdle session: cpu + disk + network
    package static let process = AwakeDynamicNeeds(rawValue: 1 << 3)    // hold session: ProcessWatch
}

package struct AwakeFeatureSpec: Sendable {
    package let defaultState: FeatureDefault           // reuses Displays' enum
    package let beta: Bool
    package let requiresAll: [AwakeFeature]
    package let uses: Set<AwakeServiceID>
    package let controller: AwakeControllerID
    package let permissions: Set<Permission>
    package init(_ d: FeatureDefault, beta: Bool = false, all: [AwakeFeature] = [], uses: Set<AwakeServiceID> = [],
                 controller: AwakeControllerID, permissions: Set<Permission> = [])
}

package enum AwakeFeatureGraph {
    package static var specs: [AwakeFeature: AwakeFeatureSpec] { get }   // table below; total (tested); computed (code sig)
    package static func spec(_ f: AwakeFeature) -> AwakeFeatureSpec
    package static func rawState(_ f: AwakeFeature, in raw: [AwakeFeature: Bool]) -> Bool
    /// Per-feature kill switches never remove these (tested with every kill switch set); `Modules.disable.awake`
    /// stops the whole module instead (N14).
    package static let unkillable: Set<AwakeFeature> = [.sessions, .batteryGuard, .thermalGuard]
    /// raw − (kill switches − unkillable) − unavailable − Safe Mode removals, closed over requirements.
    package static func resolve(raw: [AwakeFeature: Bool], killSwitches: Set<AwakeFeature>, safeMode: Bool,
                                unavailable: Set<AwakeFeature>) -> Set<AwakeFeature>
    /// nil when `f` or one of its requirements is unavailable or killed (code minor 9).
    package static func enabling(_ f: AwakeFeature, raw: [AwakeFeature: Bool],
                                 available: Set<AwakeFeature>) -> [AwakeFeature: Bool]?
    package static let safeModeRemoves: Set<AwakeFeature> = [.triggers, .pointerNudge, .driveAlive, .activity]
    package static func services(of kind: AwakeCriterionKind) -> Set<AwakeServiceID>
    package static func services(of needs: AwakeDynamicNeeds) -> Set<AwakeServiceID>
    package static func requiredServices(effective: Set<AwakeFeature>, criteria: Set<AwakeCriterionKind>,
                                         dynamic: AwakeDynamicNeeds) -> Set<AwakeServiceID>
    /// assertions, power, system, then sources (apps … bluetooth, process), activity, driveAlive.
    package static var activationOrder: [AwakeServiceID] { get }
}
```

| Feature | Def | Requires | Uses | Controller | Permission |
|---|---|---|---|---|---|
| sessions | always | — | assertions, power, system | sessions | — |
| presets | always | sessions | — | sessions | — |
| batteryGuard | always (the floor's on/off is a protected setting, not a feature) | — | power | guards | — |
| thermalGuard | always | — | power | guards | — |
| indicator | always (internal; kill switch only) | — | — | indicator | — |
| triggers | optIn | sessions | (per criterion) | triggers | — |
| activity | optIn | sessions | activity, idle, system | activity | — |
| pointerNudge | experimental | activity | activity | activity | accessibility |
| driveAlive | optIn | — | volumes, driveAlive, power | driveAlive | — (Removable Volumes TCC prompt on first write; not a `Permission` case) |
| history | standard | sessions | — | history | — |
| shortcuts | standard | sessions | — | automation | — |
| commandLine | standard | sessions | process | automation | — |

Kill switches (N14): Bool keys `Awake.disable.<feature>` read once per start from Snaptic's **persistent domain only** (Displays R5.4 rule; managed preferences are not read). `unkillable` features ignore them. `Modules.disable.<moduleID>` (lead, `ModuleHost`, read at launch from the persistent domain, honored for every module; new in 0.3 for Awake) makes that module unavailable: it never starts, its page shows "Turned off by a defaults setting." with the header switch disabled, its assertions are released, and nothing restores at the next launch. An organization deploys these keys with a configuration profile that writes Snaptic's user domain (README, step 5). Safe Mode keeps manual sessions and guards (they are safe), removes triggers, activity, nudge, Drive Alive. r2's managed screen-lock detection is withdrawn (0.2 rule); the Snaptic-clock activity cap (N10) bounds how long Snaptic can delay an idle lock.

`KitModules.swift` (lead) additions: `ModuleID.awake` (start order: windowSwitcher, displays, awake), `EventCategory.awake`, `AwakeActionID: RawRepresentable` (open, like `DisplayActionID`), `MenuPresence` (§5.2, beside `MenuPlacementChoice`; consistency B1), `DisplayActionID.fShowPanel = "f.showPanel"` and `.fIdentify = "f.identify"` (used by migration M4 and by `OverviewController`, which drops its private copies; consistency M4), `ControlID` (§4.8), `AwakeCriterionKind` (here so the graph can reference it):

```swift
package enum AwakeCriterionKind: String, Codable, CaseIterable, Sendable {
    case app, display, power, schedule, cpu, audio, idle, volume, usb, network, networkActivity, bluetooth
}
```

### 2.3 Session model (G, `SnapticKit/AwakeSession.swift`)

```swift
package enum AwakeDisplayPolicy: String, Codable, CaseIterable, Sendable {
    case keepOn            // PreventUserIdleDisplaySleep                         UI "Keep on"
    case maySleep          // PreventUserIdleSystemSleep; display follows System Settings   UI "Can turn off"
    case keepOnWhileActive // keepOn until real idle ≥ displayIdleMinutes, then maySleep   UI "Keep on until idle for [n min]"
}
package enum AwakeActivityMode: String, Codable, CaseIterable, Sendable { case off, declare, nudge }

package struct AwakeSessionOptions: Codable, Equatable, Sendable {
    package var display: AwakeDisplayPolicy        // .keepOn
    package var displayIdleMinutes: Int            // 1...240, default 30
    package var activity: AwakeActivityMode        // .off; .nudge acts only per N10 (else it degrades to .declare)
    package init(display: AwakeDisplayPolicy = .keepOn, displayIdleMinutes: Int = 30, activity: AwakeActivityMode = .off)
    package init(from decoder: Decoder) throws     // lossy per field
    package func sanitized() -> AwakeSessionOptions
}

/// "Until Downloads and Tasks Finish" (N9, lead r3). Busy = ANY signal at or above its threshold in a 5 s sample;
/// the session ends after `quietSeconds` with no busy sample, never before `graceSeconds` from start.
package struct UntilIdleSpec: Codable, Equatable, Sendable {
    package var topProcessPercent: Int     // 50 = half of one core; 10...800 (busiest same-user process)
    package var totalCPUPercent: Int       // 15; 1...90 (all cores, HOST_CPU_LOAD_INFO)
    package var diskKBps: Int              // 1_024; 64...1_000_000 (read + write, IOBlockStorageDriver Statistics)
    package var networkKBps: Int           // 50; 1...100_000 (in + out, non-loopback, §2.8)
    package var quietSeconds: Int          // 300; 60...3_600
    package var graceSeconds: Int          // 60; 0...600 (not shown in the UI)
    package init(topProcessPercent: Int = 50, totalCPUPercent: Int = 15, diskKBps: Int = 1_024, networkKBps: Int = 50,
                 quietSeconds: Int = 300, graceSeconds: Int = 60)
    package init(from decoder: Decoder) throws     // lossy per field; r2 keys (cpuBelowPercent, networkBelowKBps) never shipped
    package func sanitized() -> UntilIdleSpec
}
/// One untilIdle sample (Kit, J; nil fields = unknown, which counts as busy so an unknown never ends a session).
package struct TaskActivitySample: Equatable, Sendable {
    package var topProcessPercent: Double?; package var totalCPUPercent: Double?
    package var diskKBps: Double?; package var networkKBps: Double?
    package init(topProcessPercent: Double?, totalCPUPercent: Double?, diskKBps: Double?, networkKBps: Double?)
}
package enum TaskQuiet {   // Kit, G, tested
    package static func isBusy(_ s: TaskActivitySample, spec: UntilIdleSpec) -> Bool
    /// quietSince: continuous instant of the first quiet sample in the current run (nil while busy).
    /// A wake or a missing sample resets it (code R2-M10).
    package static func step(quietSince: Double?, sample: TaskActivitySample, now: Double, spec: UntilIdleSpec)
        -> (quietSince: Double?, finished: Bool)
}

/// What a command-line hold is bound to (lead r3). The server resolves both; neither comes from the request.
package enum HoldBinding: Equatable, Sendable {
    /// Default: the `snaptic` client's own connection and process (peer pid from LOCAL_PEERPID).
    /// Ends on EOF of that connection or exit of that pid. Never persisted (a relaunch closes the connection).
    case connection(pid: Int32, startTime: UInt64)
    /// `--pid N`: a same-user process the caller names; ends when it exits. Persisted; re-verified at restore.
    case process(pid: Int32, startTime: UInt64)
    package var pid: Int32 { get }
    package var startTime: UInt64 { get }        // proc start in µs (pbi_start_tvsec·10⁶ + pbi_start_tvusec)
}

package enum AwakeSessionKind: Equatable, Sendable {
    case indefinite
    case duration(seconds: Int)                               // 60 ... AwakeClock.maxSessionSeconds
    case until(unixTime: Double)                              // absolute wall instant
    case whileApp(bundleID: String, maxSeconds: Int?)         // validated reverse-DNS, ≤ 255 bytes; optional cap
    case untilIdle(UntilIdleSpec, maxSeconds: Int?)           // ends after quietSeconds with no busy sample
    case hold(HoldBinding, maxSeconds: Int)                   // CLI only; cap required, ≤ AwakeClock.holdMaxCapSeconds
    package var isTimed: Bool { get }              // duration, until
    package var cap: Int? { get }                  // whileApp/untilIdle/hold cap
    package var isTaskBound: Bool { get }          // whileApp, untilIdle, hold
}
extension AwakeSessionKind: Codable {              // hand-written, type-tagged: {"type":"duration","seconds":5400}
    package init(from decoder: Decoder) throws     // unknown type, or hold(.connection) → throws → session dropped
    package func encode(to encoder: Encoder) throws
}
extension HoldBinding: Codable { package init(from decoder: Decoder) throws; package func encode(to encoder: Encoder) throws }

/// Persisted and kept through restore (security L1: a restored CLI session stays `.commandLine`).
package enum AwakeSessionSource: String, Codable, Sendable {
    case menu, hotkey, settings, commandLine, launch
    /// menu, hotkey, settings: a direct user action in Snaptic's own UI (N10).
    package var isDirectUserAction: Bool { get }
}

package struct AwakeSession: Codable, Equatable, Sendable, Identifiable {
    package var id: StableID
    package var kind: AwakeSessionKind
    package var options: AwakeSessionOptions      // resolved at start: preset ?? kind default ?? defaultOptions (§2.14)
    package var presetID: StableID?
    package var source: AwakeSessionSource
    package var startedAt: Double                 // wall, display and history only
    package var startedContinuous: Double         // continuous clock at start
    package var deadline: Double?                 // continuous-clock instant: duration end or task cap; nil = none
    package var bootSession: String               // kern.bootsessionuuid at start; mismatch = expired
    /// One-shot "Start Anyway"; not in CodingKeys, never persisted (security H2).
    package var overrideGuards: Bool = false
    /// True only for a session started by a direct user action in this process; not in CodingKeys, so a restored or
    /// resumed session is always false (N10: pointer movement needs it).
    package var uiStartedInProcess: Bool = false
    /// When activity first acted in this session (continuous); not persisted. The cap (N10) counts from here.
    package var activitySince: Double? = nil
    private enum CodingKeys: String, CodingKey {   // explicit (code sig): the three runtime fields above are excluded
        case id, kind, options, presetID, source, startedAt, startedContinuous, deadline, bootSession
    }
    package init(id: StableID, kind: AwakeSessionKind, options: AwakeSessionOptions, presetID: StableID?,
                 source: AwakeSessionSource, startedAt: Double, startedContinuous: Double, deadline: Double?,
                 bootSession: String, overrideGuards: Bool = false, uiStartedInProcess: Bool = false)
    package init(from decoder: Decoder) throws    // lossy per field; kind failure throws (session dropped)
    package func encode(to encoder: Encoder) throws
    package func sanitized(now: ClockNow) -> AwakeSession?   // nil if expired, other boot, or kind out of range
}

package enum AwakeEndReason: String, Codable, CaseIterable, Sendable {
    case user, timeUp, appQuit, processExited, tasksFinished, replaced, triggerEnded, batteryLow, batteryUnreadable,
         adapterDisconnected, lowPowerMode, thermal, systemSleep, userSwitch, lockedTooLong, moduleStopped, safeMode,
         reboot, assertionFailed
}

package struct TriggerTop: Equatable, Sendable {
    package var id: StableID; package var index: Int; package var options: AwakeSessionOptions; package var since: Double
    package init(id: StableID, index: Int, options: AwakeSessionOptions, since: Double)
}
/// What the indicator, menu, Settings status row and CLI show (no app names in logs or CLI).
package enum AwakeGoverning: Equatable, Sendable {
    case inactive
    case manual(AwakeSession)
    case trigger(TriggerTop)
}

package enum AwakeUnavailableReason: String, Codable, Sendable { case featureOff, safeMode, turnedOffByDefaults }
/// Kit (code M13), so CLI exit mapping and UI copy are tested.
package enum AwakeRefusal: Error, Equatable, Sendable {
    case guardActive(AwakeEndReason)   // UI: toast with "Start Anyway" (battery/LPM above the hard floor only; never
                                       // thermal, never the 5% floor, never CLI/trigger)
    case unavailable(AwakeUnavailableReason)
    case invalid                       // bad duration, app not running, pid ≤ 1, gone, not ours or already exited
    case notAllowedFromCLI             // nudge preset, indefinite or Until Turned Off from CLI
    case uiSessionRunning              // CLI start/hold/preset while a UI-started manual session runs (security L4)
    case rateLimited                   // CLI start/hold/stop/extend > 1/s
    package var exitCode: Int32 { get }  // 4 for every refusal (0.2 CLI table), message from `text`
    package var text: String { get }     // uiSessionRunning: "A session started in Snaptic is running. Stop it first with “snaptic awake stop”."
}
```

**Time** (G, `SnapticKit/AwakeClock.swift`):

```swift
package struct ClockNow: Equatable, Sendable {
    package var wall: Double; package var continuous: Double; package var bootSession: String
    package init(wall: Double, continuous: Double, bootSession: String)
}
package enum AwakeClock {
    package static let maxSessionSeconds = 30 * 86_400          // Insomnia's cap; extensions included
    package static let cliDefaultSeconds = 3_600                // `awake start` with no argument (C10)
    package static let holdDefaultCapSeconds = 12 * 3_600       // `awake hold` without --max; also CLI untilIdle caps
    package static let holdMaxCapSeconds = 24 * 3_600           // `awake hold --max` upper bound (lead r3)
    package static func start(_ kind: AwakeSessionKind, options: AwakeSessionOptions, presetID: StableID?,
                              source: AwakeSessionSource, now: ClockNow, id: StableID) -> AwakeSession
    /// nil = no limit; ≤ 0 = expired. Duration and caps use the continuous deadline; until uses wall time.
    package static func remaining(_ s: AwakeSession, now: ClockNow) -> Double?
    /// wall + remaining (code minor 2): the end time to show, correct after a clock change.
    package static func endWall(_ s: AwakeSession, now: ClockNow) -> Double?
    package static func isExpired(_ s: AwakeSession, now: ClockNow) -> Bool   // also true when bootSession differs
    /// The session's end as a continuous instant: `deadline`, or for until-kinds continuous + (unixTime − wall).
    /// Recomputed on clock change; the arbiter re-arms only if it moved > 5 s.
    package static func continuousEnd(_ s: AwakeSession, now: ClockNow) -> Double?
    package static func canExtend(_ s: AwakeSession) -> Bool                   // timed kinds and capped task kinds
    /// nil when !canExtend; the result never exceeds maxSessionSeconds from start.
    package static func extended(_ s: AwakeSession, by seconds: Int, now: ClockNow) -> AwakeSession?
}
/// Hand-formatted text (N12). The app passes `uses24Hour` once, derived from the system locale.
package enum AwakeCountdown {
    /// ≥ 1 h "1h 42m" ("2h" on the hour), 1–59 min "42m" (rounded up), < 1 min "42s".
    package static func short(_ remaining: Double) -> String
    /// "1 hour 42 minutes remaining", "42 seconds remaining" (VoiceOver, tooltip).
    package static func spoken(_ remaining: Double) -> String
    /// "5:00 PM" or "17:00" from local hour and minute (the app converts the instant with Calendar).
    package static func clock(hour: Int, minute: Int, uses24Hour: Bool) -> String
    /// Seconds until `short` changes (minute boundary, or 1 s in the last minute); never 0.
    package static func nextChange(_ remaining: Double) -> Double
}
/// CLI and the "Custom…" panel. "until 17:30" stays a clock request; the app resolves it with
/// `Calendar.autoupdatingCurrent.nextDate(after:matching:matchingPolicy: .nextTime)` (DST-correct, not Kit).
package enum AwakeDurationRequest: Equatable, Sendable {
    case indefinite, untilIdle
    case duration(seconds: Int)
    case untilClock(hour: Int, minute: Int)
}
package enum AwakeDurationGrammar {
    package static let maxDigits = 7, maxDecimals = 2
    /// "90", "90m", "1h30m", "2h", "1.5h", "until 17:30", "until 5:30pm", "indefinite", "forever", "idle".
    /// Numbers: ≤ 7 digits, ≤ 2 decimals, finite, range-checked as Double before any Int conversion;
    /// products use multipliedReportingOverflow (security L4). Never traps (seeded fuzz).
    package static func parse(_ words: [String]) -> AwakeDurationRequest?
}
```

Clock rules (normative):
- Continuous time is `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)` (equals `mach_continuous_time`, counts sleep, system-wide per boot, so it is safe to persist with `bootsessionuuid`). `ContinuousClock` is not used: its `Instant` is opaque and can't be persisted.
- Duration: `deadline = continuous + seconds`. Wall-clock changes don't move it; time asleep counts (N2). The end time shown is `endWall` (wall + remaining).
- Until: an absolute instant chosen in the current zone; a time-zone change keeps the instant and re-renders "Until 5:00 PM" in the new zone (`NSTimeZone.resetSystemTimeZone()`, `Calendar.autoupdatingCurrent`); `NSSystemClockDidChange` re-evaluates expiry immediately.
- After a reboot (`kern.bootsessionuuid` differs) every persisted session is expired with reason `.reboot`; triggers re-evaluate from scratch.

### 2.4 Assertions and arbitration (G)

**Kit** (`SnapticKit/AwakeArbiter.swift`):

```swift
package enum AwakeAssertionType: String, Sendable { case off, system, display }
package enum AwakeAssertionDetails: String, Sendable { case manual, automatic }   // the only Details values (security M6)
package struct AwakeAssertionPlan: Equatable, Sendable {
    package static let name = "Snaptic: keeping your Mac awake"   // fixed vocabulary
    package static let inactive = AwakeAssertionPlan(type: .off, details: .manual, deadline: nil, preventDiskIdle: false)
    package var type: AwakeAssertionType
    package var details: AwakeAssertionDetails
    package var deadline: Double?        // continuous instant; TimeoutSeconds is derived only at create (code M1)
    package var preventDiskIdle: Bool    // Drive Alive writing
    package init(type: AwakeAssertionType, details: AwakeAssertionDetails, deadline: Double?, preventDiskIdle: Bool)
}
package struct AwakeArbiterInput: Equatable, Sendable {
    package var governing: AwakeGoverning
    package var screenLocked: Bool               // session dictionary, read at arbitration (security M2)
    package var consoleActive: Bool              // session dictionary kCGSSessionOnConsoleKey
    package var realIdleSeconds: Double?         // only sampled while keepOnWhileActive governs
    package var keepDisplayOnWhileLocked: Bool   // C1 Advanced option
    package var driveAliveWriting: Bool
    package var guardsHold: Bool
    package var sessionEnd: Double?              // AwakeClock.continuousEnd of the governing manual session
    package init(governing: AwakeGoverning, screenLocked: Bool, consoleActive: Bool, realIdleSeconds: Double?,
                 keepDisplayOnWhileLocked: Bool, driveAliveWriting: Bool, guardsHold: Bool, sessionEnd: Double?)
}
package enum AwakeArbiter {
    package static let timeoutGraceSeconds: Double = 15
    package static let rearmThresholdSeconds: Double = 5
    package static func plan(_ input: AwakeArbiterInput) -> AwakeAssertionPlan
    /// manual > highest-priority active trigger > inactive (N3).
    package static func governing(manual: AwakeSession?, top: TriggerTop?) -> AwakeGoverning
    /// true when the live assertion must be swapped: type or details changed, or the deadline appeared,
    /// disappeared or moved by more than rearmThresholdSeconds.
    package static func needsSwap(current: AwakeAssertionPlan, next: AwakeAssertionPlan) -> Bool
}
```

Plan rules (tested): inactive → `.off`; `.keepOn` → `.display`, downgraded to `.system` when `screenLocked && !keepDisplayOnWhileLocked` (C1) or `!consoleActive`; `.maySleep` → `.system`; `.keepOnWhileActive` → `.display` while `realIdleSeconds < displayIdleMinutes·60`, else `.system`; `deadline = sessionEnd + timeoutGraceSeconds` for manual sessions with an end (duration, until, caps), nil otherwise (trigger sessions have no backstop timeout: they end by condition); `preventDiskIdle` = `driveAliveWriting`; the plan contains no relative times, so it is **stable while nothing changes** (tested: 1,000 identical inputs at advancing times give `needsSwap(current:next:) == false` after the first, code sig: until-session deadlines differ by microseconds, so the test never compares plans with `==`).

**AssertionManager** (G, `Awake/Core/AssertionManager.swift`) holds at most one sleep assertion and, separately, at most one `PreventDiskIdle` assertion (code minor 1: no timeout, never swapped, created and released only when `preventDiskIdle` flips):

```swift
@MainActor final class AssertionManager: AwakeServiceLifecycle {
    private(set) var current: AwakeAssertionPlan = .inactive
    private(set) var lastError: Int32?
    init()
    /// Idempotent. When AwakeArbiter.needsSwap: create the new assertion first, then release the old one: no gap,
    /// no IOPMAssertionSetProperty (HW-2 moot). With a deadline: never creates when deadline ≤ now (returns false,
    /// the caller ends the session `.timeUp`); TimeoutSeconds = max(1, ceil(deadline − now)) (0 would mean "none").
    @discardableResult func apply(_ plan: AwakeAssertionPlan, now: ClockNow) -> Bool
    func releaseAll()
    /// Checks our assertion still exists with IOPMAssertionCopyProperties(id) (`takeRetainedValue()`, code minor 1):
    /// on wake, on `com.apple.system.powermanagement.assertions.timeout`, and every 5 min while active. The caller
    /// first runs the expiry check and `arbitrate()`; verify re-creates a vanished assertion only for an active plan
    /// whose deadline is nil or in the future, once; only a failed re-create returns false (code R2-M4).
    func verify(now: ClockNow) -> Bool
    func activate(_ context: AwakeContext, lifetime: Lifetime)
    func deactivate()
}
```
Creation uses `IOPMAssertionCreateWithProperties` with `AssertType`, `AssertName`, `Details`, `AssertLevel = 255`, and when a deadline exists `TimeoutSeconds` + `TimeoutAction = "TimeoutActionRelease"` ([PA] §1.2, §1.5). String literals, no CFSTR macros. An expired backstop never resurrects a session: `SessionController` handles the timeout notification by checking expiry first (`AwakeClock.isExpired` → end `.timeUp`), then arbitrating, then `verify`. A failed create (or failed re-create in `verify`) ends a manual session with `.assertionFailed` and toast "Snaptic couldn't keep your Mac awake. Try again, or restart Snaptic."; for a trigger session it sets an **assertion hold** in `GuardMemory` with backoff 30 s → 2 min → 10 min (one toast per hold, cleared by a successful create or a user start), so a failing create can't loop. The timeout is a **backstop** only: the app ends sessions itself at `remaining == 0`, 15 s before powerd would.

### 2.5 Session lifecycle (G, `SessionController`)

```swift
@MainActor final class SessionController: AwakeFeatureController {
    static var id: AwakeControllerID { .sessions }
    init()
    func start(_ kind: AwakeSessionKind, options: AwakeSessionOptions?, presetID: StableID?,
               source: AwakeSessionSource, overrideGuards: Bool) -> Result<AwakeSession, AwakeRefusal>
    func startPreset(_ id: StableID, source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal>
    func startDefault(source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal>
    /// CLI `awake hold`: the binding was resolved and verified server-side by AwakeAutomation (§2.10); ProcessWatch is
    /// armed here. `.connection` sessions also end when AwakeAutomation reports the connection closed.
    func hold(_ binding: HoldBinding, capSeconds: Int) -> Result<AwakeSession, AwakeRefusal>
    func extend(by seconds: Int, source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal>
    /// Mid-session display toggle (menu, compact section, status row Options ▾, hotkey): sets the governing session's
    /// `options.display` (`.keepOn` ↔ `.maySleep`); for a trigger session it lasts until that session ends.
    func setKeepDisplayOn(_ on: Bool)
    func end(_ reason: AwakeEndReason)         // manual session; trigger session → TriggerController.manualEnd
    func toggleDefault(source: AwakeSessionSource)  // hotkey; status-row/menu buttons call start/end directly
    /// Called once from `start(_:lifetime:effective:)` before the first `arbitrate()` (code R2-M8): drops a session
    /// from another boot; for `hold(.process)` re-verifies pid, start time and uid with ProcessWatch; evaluates
    /// AwakeGuards with live PowerFacts (a restored session on battery below a floor ends `.batteryLow`); keeps
    /// `source`; `uiStartedInProcess` stays false. The snapshot is read only here: outside writes while Awake runs
    /// are ignored (security L2).
    func restore(_ snapshot: AwakeRuntimeSnapshot)
    /// Every manual-session end, after history and before arbitration (AwakeAutomation closes a held connection).
    func observeEnds(_ lifetime: Lifetime, _ handler: @escaping @MainActor (AwakeSession, AwakeEndReason) -> Void)
    /// Synchronous: reads the cached trigger top, guard memory, session facts and idle, computes
    /// governing + plan, applies it. Called by every path that changes an input (code M7).
    func arbitrate()
    // AwakeFeatureController members (§2.11)
}
```
Starting from a menu item, a Settings button or a Snaptic hotkey passes `source: .menu/.settings/.hotkey` and sets `uiStartedInProcess = true`; every other start (CLI, `launch`, restore) leaves it false (N10).

Rules:
- At most one manual session. Starting a new one replaces the old (history entry `.replaced`); choosing the running preset again restarts its timer. Replacing a **task-bound** session shows the toast "Replaced “While Xcode is running”." (local UI only). A CLI `start`, `hold` or `preset` never replaces a session whose `source.isDirectUserAction` (refusal `.uiSessionRunning`, exit 4; security L4); it may replace a CLI or `launch` session. Starting while a trigger governs makes the manual session govern; when it ends, the trigger (if still active) governs again with no gap, because `end` calls `arbitrate()` in the same turn and `TriggerController` coalesces only `step`, never arbitration.
- A tick (`Timer` added with `RunLoop.main.add(_:forMode: .common)`, N15; fires at `AwakeCountdown.nextChange` or at expiry, whichever is earlier, tolerance 10%) recomputes `remaining`; at ≤ 0 the session ends `.timeUp`. Ticks never drive correctness alone: expiry is also checked on wake, clock change, unlock, menu open and every arbitration.
- **untilIdle** (N9): while it runs, `taskQuiet` keeps CPUSampler (total and top same-user process), DiskIOSampler and NetworkMonitor throughput active at 5 s. Each sample goes through `TaskQuiet.step`: the session ends `.tasksFinished` once `quietSeconds` (default 5 min) have passed with **no** busy sample (busy = any of top process ≥ `topProcessPercent` of one core, total CPU ≥ `totalCPUPercent`, disk ≥ `diskKBps`, network ≥ `networkKBps`), never before `graceSeconds` from start; an unknown sample and every wake reset the quiet window, and the first delta after a wake is discarded. Default display policy `maySleep`. Optional cap ("At most", §4.3). Toast: "Awake ended: downloads and tasks finished."
- **hold** (§2.10): `ProcessWatch` (J) arms a kqueue `EVFILT_PROC`/`NOTE_EXIT` on the bound pid **first**, then re-reads `proc_pidinfo(pid, PROC_PIDTBSDINFO)`: the start time must equal the binding's and `pbi_uid == getuid()`; `kevent` returning `ESRCH`, a changed start time or another uid → refuse `.invalid` at start, end `.processExited` at restore. Exit → end `.processExited`. `.connection` bindings also end when the held CLI connection closes (EOF, error, server stop). No process is spawned or signalled (lint rule 12 holds). Shown as "While a command-line hold lasts" (no process name anywhere). If the bound process ends within 2 s of the start, the toast says "Awake stopped: the process it was holding for already ended." (parity M3).
- whileApp: ends `.appQuit` when no running application has the bundle id (checked on terminate notifications and every arbitration); refuses to start if the app isn't running.
- Caps: task-bound kinds end `.timeUp` at their `deadline`; "Add 1 Hour" extends the cap (§5.3) but never past `holdMaxCapSeconds` for `hold`. `hold` always has a cap (default 12 h). A CLI `untilIdle` start or an `awake preset` of an uncapped untilIdle preset gets `holdDefaultCapSeconds` (parity minor 7).
- **Reminders and toasts**: 5-minute reminder when a timed session that ran ≥ 15 min reaches 5 min left, "Awake ends in 5 minutes." with **Add 1 Hour** (consistency m4: one label everywhere); **8-hour reminder** once per indefinite manual session, "Awake has kept your Mac awake for 8 hours." with **Turn Off** / **Keep Going** (`ToastPresenter` gains `actions: [ToastAction]`, ≤ 2, code minor 11); an end toast for every non-user end ("Awake ended: battery is below 20%." / "…: Xcode quit."; app names only in local UI); guard refusals from the UI show a toast "Battery is below 20%." with **Start Anyway** (battery/LPM above the 5% hard floor only; never from a menu item click, which closes the menu); "Awake was started from the command line." at most once per 10 minutes. Toasts are suppressed while locked, while the screensaver runs, off console, and while **presenting** (any display in a mirror set, or the frontmost app has a window covering a whole display — `CGWindowListCopyWindowInfo` bounds and owner PID only); a `screensaver.didstart` hint suppresses for at most 10 s unless ScreenSaverEngine is frontmost (security L4); suppressed toasts go to Recent Notices. ToastPresenter changes are lead-owned (§6.2, step 2).
- **Last end**: after a non-user end, `runtime.lastEnd` shows "Ended at 3:12 AM: battery below 20%." in the Awake menu and Settings status row for 12 h (also a Recent Notices entry).
- **Persistence**: the manual session (without `overrideGuards`, `uiStartedInProcess`, `activitySince`; `hold(.connection)` never), rule suppressions, `pausedUntil` and guard memory are written to `SnapticAwakeStateV1` (`ConfigStore<AwakeRuntimeSnapshot>`, no admission hook) **on change only** (never per engine step). Loading: `AwakeRuntimeSnapshot.sanitized(now:)` (Kit: kinds clamped, deadline ≤ start + 30 days, other-boot sessions and `until` suppressions dropped via the snapshot's `bootSession`, code R2-M3) and then `SessionController.restore(_:)` (pid, uid, guards with live facts; code R2-M8). On start (launch, relaunch, update, re-enable), `resumeAfterRestart` (default on) restores the session if not expired in the same boot. A crash therefore loses nothing but the time Snaptic was down (assertions die with the process; [PA] §1.2).
- **Start at launch** (Advanced, default None): a preset id started once per process; the flag is `HostSignals.launchSessionStarted` (not a static), so re-enabling the module doesn't start it again.
- **Module stop / quit**: `stop()` releases all assertions synchronously and ends the session in history as `.moduleStopped`. It keeps the snapshot when `HostSignals.isTerminating` is true (set by `ModuleHost.shutdown()` before any module stops) so a relaunch resumes; otherwise (disable, Safe Mode) it clears the snapshot. Reset All Settings clears all three Awake stores with `isTerminating == false`.

### 2.6 Guards (G, Kit `SnapticKit/AwakeGuards.swift`, `GuardsController`)

```swift
package enum ThermalLevel: Int, Codable, Sendable, Comparable {
    case nominal, fair, serious, critical
    package static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }   // not synthesized for raw-value enums
}
package struct PowerFacts: Equatable, Sendable {
    package var hasBattery: Bool
    package var onAC: Bool
    package var percent: Int?            // nil = unreadable
    package var charging: Bool
    package var lowPowerMode: Bool
    package var thermal: ThermalLevel
    package init(hasBattery: Bool, onAC: Bool, percent: Int?, charging: Bool, lowPowerMode: Bool, thermal: ThermalLevel)
}
package struct AwakeGuardsConfig: ConfigModel {
    package var batteryFloorEnabled: Bool        // true ("When the battery is low"); off leaves the 5% hard floor
    package var batteryFloor: Int                // 20; 5...50, step 5
    package var endOnAdapterDisconnect: Bool     // false
    package var endOnLowPowerMode: Bool          // false
    package init()
    package func sanitized() -> AwakeGuardsConfig
    /// Import rule (security M7): every field may only become stricter than `current`.
    package func monotonic(over current: AwakeGuardsConfig) -> AwakeGuardsConfig
}
package struct GuardMemory: Codable, Equatable, Sendable {      // persisted in the snapshot (same boot only)
    package var unreadableReads: Int = 0
    package var holding: AwakeEndReason? = nil         // blocks trigger starts until cleared
    package var heldSince: Double? = nil               // continuous clock
    package var warnedSerious: Bool = false
    package var assertionHoldUntil: Double? = nil      // continuous; §2.4 backoff
    package var assertionFailures: Int = 0
    package init()
    package init(from decoder: Decoder) throws         // lossy per field (rule 9, code sig)
    /// At load (security L2, code R2-M3): `holding`/`heldSince` are recomputed from live PowerFacts by the next
    /// `evaluate`, not trusted; on a boot mismatch everything except `warnedSerious` resets.
    package func reloaded(sameBoot: Bool) -> GuardMemory
}
package enum AwakeGuardVerdict: Equatable, Sendable { case allow, end(AwakeEndReason), warn(AwakeEndReason) }
package enum AwakeGuards {
    /// Fixed floor (N10, lead r3): on battery below this, every session and Drive Alive end, whatever the config,
    /// override or feature state says. Not stored, not exported, no kill switch.
    package static let hardFloorPercent = 5
    package static let hysteresisPercent = 5
    package static let thermalCooldownSeconds: Double = 600
    package static func evaluate(_ now: PowerFacts, previous: PowerFacts?, config: AwakeGuardsConfig,
                                 memory: GuardMemory, time: Double, active: Bool,
                                 overrideBattery: Bool) -> (verdict: AwakeGuardVerdict, memory: GuardMemory)
    /// Drive Alive and activity may run only if this is true, in every mode (security M1).
    package static func allowsBackgroundWork(_ now: PowerFacts, config: AwakeGuardsConfig) -> Bool
}
```
Rules: desktops (`!hasBattery`) skip battery rules; on AC battery rules don't apply; `percent < hardFloorPercent` on battery → end `.batteryLow` always (no override, not even Start Anyway); `percent < floor` on battery with the floor enabled → end `.batteryLow`; two consecutive unreadable reads on battery → `.batteryUnreadable`; AC → battery transition with `endOnAdapterDisconnect` → `.adapterDisconnected`; LPM on with `endOnLowPowerMode` → `.lowPowerMode`; `.critical` → end `.thermal` regardless of settings or features and hold for 10 min (evaluated in `SessionController` and `DriveAliveController` directly from `PowerMonitor`, not only through `GuardsController`, so no feature state can skip it); `.serious` → warn once per episode (no end option). Holding clears when battery ≥ floor + 5 or AC, LPM off, thermal ≤ fair for 10 min. **Guards apply to every source** (manual, trigger, CLI, restored). `overrideBattery` is the session's one-shot **Start Anyway** (UI only, never CLI/trigger, never persisted, never below the hard floor); thermal critical is never overridable. `allowsBackgroundWork` is false below the hard floor on battery, below the user floor on battery (floor enabled), with unreadable battery on battery, and at `.critical`.

System behavior options (Kit `AwakeBehavior`, part of `AwakeSessionsConfig`; declared in `Config/ConfigAwakeSessions.swift`, G; consistency m13):

```swift
package enum UserSwitchEnd: String, Codable, CaseIterable, Sendable { case immediately, afterHour, never }
package struct AwakeBehavior: Codable, Equatable, Sendable {
    package var endOnSystemSleep: Bool          // false; any sleep while our assertion holds is lid/Apple-menu/low-battery/thermal
    package var userSwitchEnd: UserSwitchEnd    // .afterHour: off console > 1 h ends `.userSwitch` (security L5)
    package var endAfterLockedHours: Int?       // nil = Never; 1, 4, 12 → ends `.lockedTooLong` (security L5, OQ-7)
    package var keepDisplayOnWhileLocked: Bool  // false (C1)
    package var resumeAfterRestart: Bool        // true
    package var startAtLaunch: StableID?        // nil
    package init()
    package init(from decoder: Decoder) throws  // lossy per field (rule 9, code sig)
}
```

### 2.7 Triggers (G engine + Kit; J sources)

**Terms** (design M4): the UI says **rule** (a trigger) and **condition** (a criterion) everywhere ("Add Rule…", "Edit Rules…", "Delete Rule…", "All/Any of these conditions", "is / is not"); "automatic session" names the session a rule starts. Code keeps `AwakeTrigger`/`AwakeCriterion`.

**Kit model** (`SnapticKit/AwakeTriggers.swift`). Every enum with associated values below gets a **hand-written, type-tagged Codable** (`{"type":"subnet","cidr":"10.0.0.0/8"}`) in the same file; synthesized enum Codable is not used because its shape can't drop unknown kinds per entry. Nested enums are never flattened into their parent (code sig): a parent puts the child's whole object under the key `"condition"` (or `"match"` for `DisplayMatch`/`BluetoothMatch`), so every object has exactly one `"type"` key at its own level.

```swift
package enum TriggerMatch: String, Codable, CaseIterable, Sendable { case all, any }
package struct WeekdaySet: OptionSet, Codable, Hashable, Sendable {   // bit 0 = Sunday
    package let rawValue: UInt8
    package init(rawValue: UInt8) { self.rawValue = rawValue & 0x7F }
    package static let everyDay = WeekdaySet(rawValue: 0x7F)
}
package enum DisplayMatch: Equatable, Sendable {
    case anyExternal                                        // ≥ 1 online non-built-in display
    case specific(record: FingerprintRecord, name: String)  // salted tiers only; name sanitized ≤ 64
    case mirroring
}
package enum PowerCondition: Equatable, Sendable { case onAdapter, onBattery, charging, batteryAtLeast(Int) }
package enum AudioCondition: String, Codable, Sendable { case outputActive, microphoneActive }
package enum NetworkCondition: Equatable, Sendable {
    case subnet(cidr: String)                          // IPv4 or IPv6, validated
    case router(hash: String, label: String)           // "Connected to this network": salted SHA-256 of the router MAC
    case vpnConnected
}
package enum BluetoothMatch: Equatable, Sendable { case audio(uidHash: String, name: String), input(hash: String, name: String), anyAudio }
package enum AwakeCriterion: Equatable, Sendable {
    case app(bundleID: String, name: String, frontmost: Bool)
    case display(DisplayMatch)
    case power(PowerCondition)
    case schedule(days: WeekdaySet, startMinute: Int, endMinute: Int)   // minutes since midnight; end ≤ start = overnight
    case cpuAbove(percent: Int)                                          // 5...100
    case audio(AudioCondition)
    case idle(atLeastMinutes: Int)                                       // 1...480
    case volumeMounted(uuid: String, name: String)
    case usbDevice(vendor: Int, product: Int, serialHash: String?, name: String)
    case network(NetworkCondition)
    case networkActivity(atLeastKBps: Int)                               // 10...1_000_000
    case bluetooth(BluetoothMatch)
    package var kind: AwakeCriterionKind { get }
}
extension DisplayMatch: Codable { package init(from decoder: Decoder) throws; package func encode(to encoder: Encoder) throws }
extension PowerCondition: Codable { package init(from decoder: Decoder) throws; package func encode(to encoder: Encoder) throws }
extension NetworkCondition: Codable { package init(from decoder: Decoder) throws; package func encode(to encoder: Encoder) throws }
extension BluetoothMatch: Codable { package init(from decoder: Decoder) throws; package func encode(to encoder: Encoder) throws }
extension AwakeCriterion: Codable { package init(from decoder: Decoder) throws; package func encode(to encoder: Encoder) throws }

package struct AwakeCriterionEntry: Codable, Equatable, Sendable {
    package var criterion: AwakeCriterion; package var negated: Bool
    package init(_ criterion: AwakeCriterion, negated: Bool = false)
    package init(from decoder: Decoder) throws     // keys "criterion" (throws → entry dropped) and "negated" (lossy, false)
    package func encode(to encoder: Encoder) throws
}   // JSON {"criterion":{"type":"network","condition":{"type":"subnet","cidr":"10.0.0.0/8"}},"negated":false}
    // AwakeCriterion's own object: {"type":"app","bundleID":…,"name":…,"frontmost":false}; unknown type → dropped

package struct AwakeTrigger: Codable, Equatable, Sendable, Identifiable {
    package var id: StableID
    package var name: String                     // ≤ 64 scalars, TextSanitizer; empty → generated summary
    package var enabled: Bool
    package var match: TriggerMatch
    package var criteria: [AwakeCriterionEntry]  // 1...8; a trigger with 0 valid criteria is disabled by sanitized()
    package var options: AwakeSessionOptions     // sanitized(): `nudge` on a trigger with an idle criterion → `declare` (code M8)
    package var startDelaySeconds: Int           // 0...3600; cpu/networkActivity default 60
    package var endDelaySeconds: Int             // 0...3600; default 30 (hysteresis)
    package var resumeAfterManualEndMinutes: Int?   // nil = when the condition next becomes true
    package static let maxTriggers = 32, maxCriteria = 8
    package init(id: StableID, name: String, criteria: [AwakeCriterionEntry])
}
package struct AwakeTriggersConfig: ConfigModel {
    package var triggers: [AwakeTrigger]         // order = priority; pausedUntil is runtime state (snapshot), not config
    package init()
    package func sanitized() -> AwakeTriggersConfig
}
```

**Facts and evaluation** (`SnapticKit/AwakeTriggerEngine.swift`):

```swift
// Each fact type has an explicit package init (code sig: J's app sources build them; memberwise inits are internal).
package struct DisplayFact: Equatable, Sendable {
    package var record: FingerprintRecord; package var isBuiltin: Bool
    package init(record: FingerprintRecord, isBuiltin: Bool)
}
package struct USBFact: Equatable, Sendable {
    package var vendor: Int; package var product: Int; package var serialHash: String?
    package init(vendor: Int, product: Int, serialHash: String?)
}
package struct NetworkFacts: Equatable, Sendable {
    package var addresses: [String]; package var routerHashes: Set<String>; package var vpn: Bool
    package init(addresses: [String], routerHashes: Set<String>, vpn: Bool)
}
package struct BluetoothFact: Equatable, Sendable {
    package var audioUIDHashes: Set<String>; package var inputHashes: Set<String>
    package init(audioUIDHashes: Set<String>, inputHashes: Set<String>)
}
/// nil = the source isn't running or hasn't produced a value yet ("unknown").
package struct CriterionFacts: Equatable, Sendable {
    package var runningApps: Set<String>?; package var frontmostApp: String??
    package var displays: [DisplayFact]?; package var mirroring: Bool?
    package var power: PowerFacts?
    package var minuteOfWeek: Int?               // 0..<10080, local time, computed by the app with Calendar.autoupdatingCurrent
    package var cpuPercent: Double?; package var audioOutput: Bool?; package var microphone: Bool?
    package var realIdleSeconds: Double?; package var volumes: Set<String>?; package var usb: [USBFact]?
    package var network: NetworkFacts?; package var throughputKBps: Double?; package var bluetooth: BluetoothFact?
    package init()
}
/// In memory only, continuous clock (code M2).
package struct TriggerHysteresis: Equatable, Sendable {
    package var trueSince: Double?; package var falseSince: Double?; package var active: Bool
    package init()
}
/// Persisted in the snapshot (continuous clock, same boot only: `until` entries are dropped on a boot mismatch,
/// `untilFalse` ones kept; code R2-M3).
package struct TriggerSuppression: Codable, Equatable, Sendable {
    package var until: Double?; package var untilFalse: Bool
    package init(until: Double?, untilFalse: Bool)
    package init(from decoder: Decoder) throws     // lossy per field (rule 9, code sig)
}
package struct TriggerStepResult: Equatable, Sendable {
    package var hysteresis: [StableID: TriggerHysteresis]
    package var suppressions: [StableID: TriggerSuppression]   // expired ones removed
    package var top: TriggerTop?
    package var nextDeadline: Double?                           // continuous instant of the next delay expiry
}
package enum TriggerEngine {
    /// true / false / nil (unknown). Negation of unknown stays unknown.
    package static func holds(_ entry: AwakeCriterionEntry, facts: CriterionFacts) -> Bool?
    /// all: every entry true (unknown → false). any: some entry true (unknowns ignored).
    package static func condition(_ t: AwakeTrigger, facts: CriterionFacts) -> Bool
    /// Advances hysteresis for every trigger and returns the governing candidate (first active in order).
    package static func step(_ triggers: [AwakeTrigger], facts: CriterionFacts, now: Double,
                             hysteresis: [StableID: TriggerHysteresis], suppressions: [StableID: TriggerSuppression],
                             paused: Bool, guardsHold: Bool) -> TriggerStepResult
    /// The user ended a trigger session: suppress per resumeAfterManualEndMinutes.
    package static func manualEnd(_ t: AwakeTrigger, now: Double) -> TriggerSuppression
    package static func requiredKinds(_ triggers: [AwakeTrigger]) -> Set<AwakeCriterionKind>
    /// Minutes of week (0..<10080) where some enabled schedule criterion flips. The app's Ticker turns each into a
    /// Date with Calendar.autoupdatingCurrent.nextDate (DST-correct) and wakes at the earliest, capped at 15 min.
    package static func scheduleBoundaries(_ triggers: [AwakeTrigger]) -> Set<Int>
    /// Sentence for list rows and the menu: "When Xcode is open and the power adapter is connected".
    package static func summary(_ t: AwakeTrigger) -> String
}
```

Engine rules (tested, normative): a trigger becomes active when its condition has held for `startDelaySeconds` and inactive when false for `endDelaySeconds`; disabled, suppressed, paused or guard-held triggers are never active (their hysteresis still advances so they resume correctly); the governing trigger is the first active one in list order (priority); a priority change takes effect at the next step without ending the session if the top stays active; `step` runs on every source change, **coalesced to one run per main-queue turn**, plus the Ticker (schedule boundaries, `nextDeadline`); after each step `TriggerController` caches `top` and calls `SessionController.arbitrate()` synchronously; a wake runs `step` only after a 5 s settle so displays, power and network sources reread. `pausedUntil` (wall time, "Pause for 1 Hour" / "Pause Until Tomorrow") lives in the snapshot; a clock change re-evaluates it.

**Specific display matching** (replaces Displays' per-display `preventSleep`): `DisplayPresence` builds a `FingerprintRecord` per online display via B's `DisplayIdentity.record(for:salt:)` from CG facts (vendor, model, serial, UUID via `CGDisplayCreateUUIDFromDisplayID`, built-in) — tiers t2, t3, t5 — and compares stored records with a new pure Kit helper `Fingerprint.matches(_ stored: FingerprintRecord, _ live: FingerprintRecord) -> Bool` (B; higher stored tiers that we can't compute don't conflict; `Fingerprint.match` needs a `DisplayKey` map Awake doesn't have). Awake therefore works with the Displays module off. The display picker in the trigger editor shows `NSScreen.localizedName` (or the Displays custom name when Displays runs, read-only from `DisplaysConfig.perDisplay[key].identity.customName`).

**Router and USB hashes**: SHA-256(`SnapticAwakeSalt` ‖ normalized value), salt = 32 random bytes in its own persistent-domain key, created on first use, never exported (same rules as `SnapticDisplaySalt`, R5.7). Labels ("Home", "Desk dock") are user-typed.

### 2.8 Criterion sources (J)

Each source conforms to:

```swift
@MainActor protocol AwakeServiceLifecycle: AnyObject {
    func activate(_ context: AwakeContext, lifetime: Lifetime)   // idempotent
    func deactivate()                                            // idempotent; releases ports, listeners, timers
}
@MainActor protocol CriterionSource: AwakeServiceLifecycle {
    static var kinds: Set<AwakeCriterionKind> { get }
    /// Writes this source's fields into the facts (nil while not ready).
    func contribute(to facts: inout CriterionFacts)
    /// Multicast (code M7): PowerMonitor, SystemEventsMonitor and IdleSampler have several consumers.
    /// The handler is dropped when `lifetime` ends.
    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void)
}
/// Lead, `Awake/AwakeContracts.swift`: the one fan-out implementation every source uses.
@MainActor final class ChangeFanout {
    init()
    func add(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void)
    func fire()
}
/// J, read synchronously by SystemEventsMonitor from CGSessionCopyCurrentDictionary() (security M2).
struct SessionFacts: Equatable, Sendable { var locked: Bool; var onConsole: Bool }

/// J (app, `Awake/Sources/ProcessWatch.swift`): the only user of EVFILT_PROC and proc_pidinfo in Awake.
@MainActor final class ProcessWatch: AwakeServiceLifecycle {
    init()
    /// proc_pidinfo(PROC_PIDTBSDINFO): nil when the pid is gone or unreadable.
    func facts(_ pid: Int32) -> (uid: uid_t, startTime: UInt64)?
    /// Arms kqueue EV_ADD EVFILT_PROC NOTE_EXIT (a DispatchSourceRead on the kq fd, main queue) FIRST, then re-reads
    /// facts: nil (refuse) on ESRCH, start-time mismatch or another uid. The handler runs once; `lifetime` ends it.
    func watch(pid: Int32, startTime: UInt64, lifetime: Lifetime, onExit: @escaping @MainActor () -> Void) -> Bool
    func activate(_ context: AwakeContext, lifetime: Lifetime)
    func deactivate()
}
```

Kit math (J, consistency M7; `SnapticKit/CPUMath.swift`, `SnapticKit/NetworkMath.swift`, both tested):

```swift
package struct CPUTicks: Equatable, Sendable {      // host_statistics HOST_CPU_LOAD_INFO, UInt32 tick counters
    package var user, system, idle, nice: UInt32
    package init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)
}
package enum CPUMath {
    /// Busy share of all cores, 0...100; wrapping UInt32 subtraction; nil when no ticks elapsed.
    package static func load(prev: CPUTicks, now: CPUTicks) -> Double?
    /// One process's CPU as % of one core (100 = one core) from rusage time deltas (ns) over a wall delta (s).
    package static func processPercent(prevNanos: UInt64, nowNanos: UInt64, seconds: Double) -> Double?
    /// The busiest value; nil for an empty sample.
    package static func top(_ percents: [Double]) -> Double?
}
package struct InterfaceCounters: Equatable, Sendable {   // one if_msghdr2 row (NET_RT_IFLIST2, if_data64)
    package var name: String; package var bytesIn: UInt64; package var bytesOut: UInt64
    package init(name: String, bytesIn: UInt64, bytesOut: UInt64)
}
package enum NetworkMath {
    package static func parseCIDR(_ s: String) -> (address: [UInt8], prefix: Int)?      // IPv4 or IPv6
    package static func cidrContains(_ cidr: String, address: String) -> Bool
    package static func normalizeMAC(_ s: String) -> String?                           // "aa:bb:…" lowercase
    /// 64-bit counter delta; nil on a reset (now < prev).
    package static func byteDelta(prev: UInt64, now: UInt64) -> UInt64?
    /// KB/s over all non-loopback interfaces (`lo*` excluded); tunnels (`utun*`, `ipsec*`, `ppp*`) count only when no
    /// physical interface moved bytes in the window, so VPN traffic isn't counted twice (code R2-M10, parity M2).
    package static func throughputKBps(prev: [InterfaceCounters], now: [InterfaceCounters], seconds: Double) -> Double?
}
package enum DiskMath {   // J, `SnapticKit/DiskMath.swift`
    /// KB/s from summed IOBlockStorageDriver "Bytes (Read)" + "Bytes (Write)"; nil on a reset or a driver set change.
    package static func throughputKBps(prevBytes: UInt64, nowBytes: UInt64, seconds: Double) -> Double?
}
```

**Notifications are hints, never truth** (security M2): `com.apple.screenIsLocked/Unlocked` and `com.apple.screensaver.didstart/didstop` are distributed notifications any process can post. They only cause a re-read. `SystemEventsMonitor.sessionFacts()` reads `CGSSessionScreenIsLocked` (an undocumented dictionary key: HW-1 confirms it on 14–27; code minor 12) and `kCGSSessionOnConsoleKey` from `CGSessionCopyCurrentDictionary()` at the moment of use, and `SessionController.arbitrate()` and `ActivityController` call it before every arbitration and every activity action. Screensaver: a `didstart` hint only suppresses (fail-safe) and expires after 10 s; "running" holds while `NSWorkspace.frontmostApplication?.bundleIdentifier == "com.apple.ScreenSaver.Engine"`, which a notification can't fake (security L4).

| Source | Period / events | Budget | Notes |
|---|---|---|---|
| PowerMonitor | `kIOPSNotifyPowerSource`, `kIOPSNotifyPercentChange` (`import notify`), `NSProcessInfoPowerStateDidChange`, `thermalStateDidChangeNotification` (both `queue: .main`) | events only | Always active with `sessions` (guards need it). `@Published var facts: PowerFacts` + `observe` |
| SystemEventsMonitor | `NSWorkspace` will/didSleep, screensDidSleep/Wake, sessionDidResign/BecomeActive; distributed lock/screensaver hints; `NSSystemClockDidChange`, `NSSystemTimeZoneDidChange` (→ `NSTimeZone.resetSystemTimeZone()`), `NSCalendarDayChanged`; lid via `IOPMrootDomain` interest (`AppleClamshellState`, `AppleClamshellCausesSleep`, [PA] §2) | events only | `sessionFacts()` reads the session dictionary on demand |
| AppMonitor | launch/terminate/activate notifications | events only | Regular + accessory apps; bundle ids only; picker list sorted by name, Snaptic excluded |
| DisplayPresence | `CGDisplayRegisterReconfigurationCallback` (CallbackTarget), debounced 1 s | events only | Removes callback in `deactivate` |
| USBWatcher | first-match + terminated notifications on `IOUSBHostDevice` | events only | Iterators drained at arm; serial hashed immediately, raw never stored |
| VolumeMonitor | didMount / didUnmount / willUnmount; DiskArbitration description per mount (`DASessionCreate`, `DADiskCreateFromVolumePath`, `DADiskCopyDescription`, synchronous IPC: run on a private utility queue, results hop to main; code minor 12) | events only | Builds `DriveAlivePolicy.VolumeFacts` (§2.9), including the BSD name (`kDADiskDescriptionMediaBSDNameKey`) the write path re-checks |
| AudioMonitor | property listeners on default output/input `DeviceIsRunningSomewhere` + default-device change | events only | HAL calls and listeners on a private serial queue (they can block > 50 ms); each listener stored as a typed `AudioObjectPropertyListenerBlock` so Remove gets the same block, `[weak self]`; moves its listener when the default device changes; publishes on main. No input stream is ever opened |
| CPUSampler | 5 s timer; 10 s window average (total); top process only while `taskQuiet` | ~10 µs/sample total; ≤ 5 ms with top process | `host_statistics` tick deltas → `CPUMath.load`; count = `MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride` (the macro isn't imported); cached host port. Top process (N9): `proc_listallpids` + `proc_pid_rusage(RUSAGE_INFO_V2)` user + system time deltas → `CPUMath.processPercent`/`top`; processes of other users aren't readable and are skipped (so root's `mds_stores`/`kernel_task` bursts don't count); only the maximum is kept, never a pid, name or list (§3.6); no TCC |
| DiskIOSampler | 5 s timer only while `taskQuiet` | ~50 µs/sample | `IOServiceGetMatchingServices(IOBlockStorageDriver)`, each driver's `Statistics` dictionary "Bytes (Read)" + "Bytes (Write)" summed → `DiskMath`; read-only registry properties, no device opened, no TCC; parity M2 |
| IdleSampler | 10 s timer (5 s while `keepOnWhileActive`, activity or `idle` criteria run) | trivial | per-type `.hidSystemState` seconds (key down, flags changed, left/right/other mouse down, scroll wheel, mouse moved; never `anyInput`), minimum taken, turned into **last real input** by `IdleMath` (§2.9) so Snaptic's own nudges and declarations never count |
| NetworkMonitor | `SCDynamicStore` notifications for IPv4/IPv6 global + interface keys; router hash re-read on change; throughput 5 s timer only when `networkActivity` or `taskQuiet` is needed | events + 5 s | `sysctl NET_RT_IFLIST2` with `if_data64` (32-bit `if_data` wraps within seconds at multi-gigabit) → `NetworkMath.throughputKBps` (loopback excluded, tunnels not double-counted); read-only; no sockets; ARP/route via `sysctl` [HW-11] |
| ProcessWatch | kqueue `EVFILT_PROC`/`NOTE_EXIT` per held pid | events only | §2.5 hold; one source per hold session |
| BluetoothPresence (Beta) | CoreAudio device-list listener (AudioMonitor's queue); `IOServiceAddMatchingNotification(IOHIDDevice)` filtered by `Transport` | events only | Never opens a HID device (Input Monitoring) [HW-10] |

### 2.9 Activity simulation and Drive Alive (J)

**ActivitySimulator** (`Awake/Sources/ActivitySimulator.swift`): the only file allowed to call `IOPMAssertionDeclareUserActivity`, to release that declaration's id, and to post `CGEvent`s (lint L1/L2).

```swift
package enum ActivityDecision: Equatable, Sendable { case skip, declare, nudge }   // `.skip`, not `.none` (code sig)
package struct ActivityInputs: Equatable, Sendable {      // Kit (code M13)
    package var mode: AwakeActivityMode         // governing session's effective mode (.off when none)
    /// pointerNudge effective ∧ Accessibility preflight ∧ the governing session is manual with
    /// `source.isDirectUserAction && uiStartedInProcess` (N10: never CLI, trigger, launch, restored or resumed).
    package var nudgeAllowed: Bool
    package var screenLocked: Bool              // session dictionary, read now
    package var onConsole: Bool                 // session dictionary, read now
    package var screensaverRunning: Bool        // ScreenSaverEngine frontmost, or a didstart hint < 10 s old
    package var displaysAsleep: Bool            // CGDisplayIsAsleep(main)
    package var switcherVisible: Bool           // HostSignals
    package var secondsSinceUserInput: Double   // IdleMath over key/click/scroll types; only skips while the user works
    /// Snaptic's continuous clock: now − session.activitySince (0 before the first action). Never system idle,
    /// which Snaptic's own declarations reset (security M2, N10).
    package var activityElapsedSeconds: Double
    package var stopAfterSeconds: Double        // AwakeActivityConfig.stopAfterHours · 3600, 1...8 h
    package var pointerEdgeDistance: Double?    // points to the nearest display edge (nudge only)
    package init(mode: AwakeActivityMode, nudgeAllowed: Bool, screenLocked: Bool, onConsole: Bool,
                 screensaverRunning: Bool, displaysAsleep: Bool, switcherVisible: Bool, secondsSinceUserInput: Double,
                 activityElapsedSeconds: Double, stopAfterSeconds: Double, pointerEdgeDistance: Double?)
}
package enum ActivityPolicy {   // Kit, J, tested truth table
    package static let intervalSeconds: Double = 60       // fixed (parity minor 14)
    package static let edgeMarginPoints: Double = 2       // security L1: hot corners, Dock, full-screen menu bar
    /// skip unless: mode ≠ off, unlocked, on console, no screensaver, displays awake, switcher hidden,
    /// secondsSinceUserInput ≥ interval, activityElapsed < stopAfter. nudge additionally needs nudgeAllowed and
    /// edge distance > margin; otherwise a nudge request degrades to declare.
    package static func decide(_ i: ActivityInputs) -> ActivityDecision
}
package enum IdleMath {         // Kit, J
    package static let echoSeconds: Double = 1
    /// HID idle resets of the mouse-moved type within echoSeconds after one of our nudges, and any reset within
    /// echoSeconds after one of our declarations, are not real input (security L1/M2, code M8).
    package static func lastRealInput(previous: Double, now: Double, hidIdleSeconds: Double,
                                      nudgeTimes: [Double], declareTimes: [Double]) -> Double
}

@MainActor final class ActivitySimulator: AwakeServiceLifecycle {
    init()
    func perform(_ decision: ActivityDecision)          // ActivityController calls it once per interval
    func stop()                                         // releases the DeclareUserActivity id
    private(set) var recentNudges: [Double] = []        // continuous times, last 10, for IdleMath
    private(set) var recentDeclarations: [Double] = []  // continuous times, last 10, for IdleMath
    func activate(_ context: AwakeContext, lifetime: Lifetime)
    func deactivate()
}
```
`declare` calls `IOPMAssertionDeclareUserActivity("Snaptic: activity", kIOPMUserActiveLocal, &id)` reusing `id` and releases it on `stop()`. It turns the display on ([PA] §1.4), so it never runs while the displays are asleep. `nudge` posts one `mouseMoved` of +1 pt then −1 pt at the current location from `CGEventSource(stateID: .privateState)` via `.cghidEventTap`, with `eventSourceUserData = 0x534E5054` ('SNPT') so Snaptic's own taps (switcher hover-select) ignore it; `CGPreflightPostEventAccess()` before every post; never posts key, click or scroll events. Whether a private-state source or a declaration resets `.hidSystemState` idle is HW-5/HW-6; correctness is independent of the answer because the cap runs on Snaptic's clock.

**The cap** (N10, security M2): `ActivityController` sets `session.activitySince` (continuous) the first time it acts for the governing session; activity stops (the session continues) once `activityElapsedSeconds ≥ stopAfterSeconds` (default 1 h, Advanced 1–8 h), so an unattended unlocked Mac reaches its idle lock. Only a new direct user action in Snaptic's UI (starting a session, or choosing the running preset again, which restarts it) clears `activitySince`; once the cap is reached the detail text says "Stopped appearing active after 1 hour."; real input does not reset it (it can't be told apart from our own declarations on every OS). A trigger session's activity (declare only) caps the same way, counted from the moment the rule's session first acted; the counter resets when that automatic session ends. While activity acts, detail text says "Appearing active" / "Moving the pointer" in the Awake menu and the Settings status row. Copy (Settings): "Appear active — Keeps apps from marking you as away while a session runs." / "Move the pointer slightly — Moves the pointer 1 point and back. Only for sessions you start in Snaptic. Needs Accessibility."

**DriveAliveService** (`Awake/Sources/DriveAliveService.swift`):

```swift
@MainActor final class DriveAliveService: AwakeServiceLifecycle {
    struct VolumeState: Equatable { let uuid: VolumeUUIDKey; let name: String; var lastWrite: Date?; var lastError: DriveAliveError? }
    @Published private(set) var volumes: [VolumeState] = []   // code sig: default + init()
    init()
    /// Writes start/stop per volume; at most one write in flight per volume (the first open() may block on the
    /// Removable Volumes prompt; queued ticks coalesce).
    func setTargets(_ uuids: Set<VolumeUUIDKey>, interval: TimeInterval)
    func removeKeepAliveFile(_ uuid: VolumeUUIDKey)     // when the user turns a volume off
    func activate(_ context: AwakeContext, lifetime: Lifetime)
    func deactivate()
}
package enum DriveAliveError: String, Codable, Sendable { case notEligible, mountChanged, notOurFile, ioError, denied }
package enum DriveAlivePolicy {   // Kit, J, tested
    package struct VolumeFacts: Equatable, Sendable {
        package var isInternal, isRootFileSystem, isReadOnly, isLocal, isDiskImage, isTimeMachine, isBrowsable: Bool
        package var inBootContainer: Bool
        package var fileSystem: String          // f_fstypename
        package var bsdName: String             // "disk4s1" from DiskArbitration; the write path compares f_mntfromname
        package init(isInternal: Bool, isRootFileSystem: Bool, isReadOnly: Bool, isLocal: Bool, isDiskImage: Bool,
                     isTimeMachine: Bool, isBrowsable: Bool, inBootContainer: Bool, fileSystem: String, bsdName: String)
    }
    package static let allowedFileSystems: Set<String> = ["apfs", "hfs", "exfat", "msdos"]   // allowlist (security M5)
    package static func isEligible(_ v: VolumeFacts) -> Bool
    package static let fileName = ".snaptic-keepalive"
    package static let fileSize = 8
    package static let intervalRange: ClosedRange<Int> = 30...600
    /// C9 + N1 + security M1/L1: never for sessions whose (restore-preserved) source is `.commandLine`, never when
    /// guards forbid background work (hard floor, user floor, unreadable battery, critical heat).
    package static func shouldWrite(sessionActive: Bool, sessionSource: AwakeSessionSource?, evenWithoutSession: Bool,
                                    backgroundWorkAllowed: Bool, uiConfirmedFirstWrite: Bool) -> Bool
}
```
Eligibility facts come from the live mount and DiskArbitration: `isDiskImage` = `kDADiskDescriptionDeviceModelKey == "Disk Image"` or an `IOHDIXController` ancestor; `inBootContainer` = the volume's APFS container is the boot volume's container (every volume in it is excluded); `isLocal` from `statfs` `MNT_LOCAL`, and the file-system allowlist excludes FSKit/macFUSE/network types. Write procedure on a private serial `DispatchQueue(label: "snaptic.drivealive", qos: .utility)` (security M5):
1. Resolve the root from the current mount list by UUID (never from config).
2. `dirfd = open(root, O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)`.
3. `fstatfs(dirfd)`: `f_mntonname == root`, `f_fstypename ∈ allowedFileSystems`, `f_flags` has `MNT_LOCAL` and has neither `MNT_RDONLY` nor `MNT_ROOTFS`, and `f_mntfromname` equals `/dev/` + the `bsdName` whose DiskArbitration description was judged eligible (a crafted image that clones a UUID has another BSD name; a remount re-runs DiskArbitration; security L3); `fgetattrlist(dirfd, ATTR_VOL_UUID)` equals the configured key. Any mismatch → `.mountChanged`, skip.
4. `fd = openat(dirfd, fileName, O_WRONLY|O_CREAT|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK, 0600)`; `fstat(fd)`: regular file, owner `getuid()`, `st_nlink == 1`, size ≤ 64, `st_dev` equal to the directory's `st_dev`.
5. Write 8 bytes (UInt64 timestamp) at offset 0, `ftruncate(8)`, `fcntl(F_FULLFSYNC)`, close both fds; the result hops to main.

Any check failure → that volume is skipped and the Drives row shows "Can't keep this drive awake" with the reason; no retry until remount. Stop on `willUnmount` (before eject). `removeKeepAliveFile` uses the same steps 1–3, then `fstatat` + `unlinkat(dirfd, fileName, 0)` only if the file passes step 4's checks and is exactly 8 bytes. The **first** write to a volume happens only right after the user turns that volume on in Drives (so the Removable Volumes prompt follows a UI action, security M3); that write sets `DriveAliveVolume.firstWriteDone`, and until it is set `uiConfirmedFirstWrite` is false and the volume waits. Volumes are chosen in the UI and stored by UUID only (lead r3). A config change made outside Snaptic still takes effect, including `firstWriteDone`; the worst case is an unprompted Removable Volumes dialog the user can decline (§3.2 residual). Info.plist gets `NSRemovableVolumesUsageDescription` = "Snaptic writes a tiny hidden file to the drives you choose so they don't spin down." (lead). Package.swift links DiskArbitration (lead).

### 2.10 Automation (G, `AwakeAutomation`)

Hotkeys (`AwakeActionID`, owner "Awake", via `GlobalHotkeys`, all unbound by default): `awake.toggle` (Keep Awake on/off with the default preset), `awake.keepDisplayOn`, `awake.preset1…4`, `awake.pauseAutomatic`.

CLI verbs (registered only while `commandLine` is effective and the host CLI is on). `start`, `hold`, `stop` and `extend` share a 1 request/s limit (security L3), on top of the global 20/s. Arguments go through `AwakeCommandGrammar` (G, Kit, consistency M7):

```swift
package enum AwakeCommand: Equatable, Sendable {
    case status(json: Bool)
    case start(AwakeDurationRequest?, displayMaySleep: Bool)     // nil = 1 h (C10)
    case hold(pid: Int32?, maxSeconds: Int?)                     // --pid N (> 1), --max <duration> (≤ 24 h)
    case preset(PresetSelector)
    case extend(seconds: Int)
    case stop
    case pause(seconds: Int?)                                    // ≤ 24 h, nil = 1 h
}
package enum PresetSelector: Equatable, Sendable { case index(Int), name(String) }   // 1-based; name ≤ 64 scalars
package enum AwakeCommandGrammar {
    /// verb is the word after "awake"; flags "--pid", "--max", "display-may-sleep"; numbers via AwakeDurationGrammar
    /// limits (≤ 7 digits, no sign, no exponent). nil = usage error (exit 2). Never traps (seeded fuzz).
    package static func parse(verb: String, args: [String]) -> AwakeCommand?
    /// `awake status` line; ISO end time hand-formatted from explicit UTC components (N12, code minor 10).
    package static func statusLine(_ s: AwakeStatusFacts) -> String
    package static func statusJSON(_ s: AwakeStatusFacts) -> String
}
package struct AwakeStatusFacts: Equatable, Sendable {
    package var active: Bool; package var automatic: Bool; package var kind: AwakeHistoryKind?
    package var display: AwakeDisplayPolicy?; package var endUnix: Double?; package var remaining: Double?
    package var triggerNumber: Int?; package var holdPID: Int32?
    package init(active: Bool, automatic: Bool, kind: AwakeHistoryKind?, display: AwakeDisplayPolicy?, endUnix: Double?,
                 remaining: Double?, triggerNumber: Int?, holdPID: Int32?)
}
```

| Verb | Policy | offOnly | Behavior |
|---|---|---|---|
| `awake status` | read | — | `inactive` or `active\tmanual|automatic\t<kind>\t<display policy>\t<ISO end or ->\t<remaining s>`; kinds `indefinite|duration|until|app|idle|process|automatic`; `--json` object adds `"pid"` for a hold (a number, never a name; parity M3); no app names, no process names, rule *numbers* only |
| `awake start [<duration grammar>] [display-may-sleep]` | low | false | `AwakeDurationGrammar`; **no argument = 1 h**; `indefinite`/`forever` refused (exit 4, "Use the menu or `awake hold`"); `idle` = Until Downloads and Tasks Finish (cap 12 h); refused if the resulting options use `nudge`; refused while a UI-started session runs (`.uiSessionRunning`); guards apply (exit 4 with reason) |
| `awake hold [--pid N] [--max <duration>]` | low | false | `hold` session (below); cap = `--max` (≤ 24 h) or 12 h; refused while a UI-started session runs |
| `awake preset <n|name>` | low | false | Refused if the preset uses `nudge` or is Until Turned Off, or while a UI-started session runs; an uncapped untilIdle preset gets the 12 h cap |
| `awake extend <duration>` | low | false | Manual timed or capped sessions only; a hold never past 24 h |
| `awake stop` | low | true | Ends the manual session; a trigger session is suppressed as a manual end |
| `awake pause [<duration>]` | low | true | Pauses automatic sessions (default 1 h, ≤ 24 h) |

**`awake hold`** (lead r3; parity M3, security M4, code R2-M9, consistency M1). Snaptic never runs the caller's command. Two forms:
- **Default (no `--pid`)**: the `snaptic` client itself is the hold. The server binds the session to `HoldBinding.connection(pid: peer.pid, startTime:)`, where `peer` is the connection's `ControlPeer` (below), replies with the first line "Holding until this command ends (at most 12 h). Press Control-C to stop." and **keeps the connection open**. The client keeps reading and never exits on its own; the session ends when the client's connection reaches EOF (the client exits, is killed or its terminal closes; the kernel closes the socket), when `ProcessWatch` sees the peer pid exit (a forked child that inherited the fd doesn't keep it alive), at the cap, or when the user ends it. When the server ends it (cap, user, guard, Snaptic quits), it writes a final line ("Awake hold ended: time is up." etc.) and closes; the client prints it and exits 0 (or 5 when Snaptic quit).
- **`--pid N`**: binds to `HoldBinding.process(pid: N, …)`; the server checks N > 1, `pbi_uid == getuid()` and reads N's start time, arms `ProcessWatch` first and re-verifies (security M4), replies "Holding while process N runs (at most 12 h)." and closes; the client exits 0 immediately. The session survives a Snaptic relaunch (pid + start time re-verified at restore).
- Server-side limits: a held connection doesn't count toward the 4 concurrent request slots; at most one held connection exists (a new hold replaces the old one, whose client gets "Replaced by another hold." and exits 0); a hold never replaces a UI-started session.

Usage (README, step 5), with the parent-shell pitfall explained:
```sh
# In a script: hold for as long as this script's shell runs
snaptic awake hold --pid $$
# Around one command in an interactive or single shell
snaptic awake hold & HOLD=$!; make release; kill $HOLD
```
Pitfall: `make` recipe lines, `npm run` steps, CI step runners and agent tool calls run each line in a fresh `sh -c` that exits as soon as the line ends. There, `--pid $$` names a shell that exits at once (the session ends within milliseconds; the toast and the reply say so), and a backgrounded `hold &` left behind by one line keeps holding after the work is done, until its cap. Put start, work and `kill` in **one** shell (one recipe line joined with `&&`, `.ONESHELL:`, or a script file), pass `--pid` of a process that lives as long as the work, or use `snaptic awake start 2h`. CI keeps `caffeinate -w` as before.

**ControlServer contract change** (A, step 1; `Core/ControlServer.swift`, `Core/ControlCommandRegistry.swift`, `Core/CLIClient.swift`, Kit `KitControl.swift`; consistency M1, code R2-M9):
```swift
/// Read by the server on the accepted fd right after getpeereid, before the request line is read (the peer is
/// alive and waiting for its reply): getsockopt(SOL_LOCAL, LOCAL_PEERPID) + proc_pidinfo start time. Never from the
/// request, which a client writes; ControlRequest gains no field.
struct ControlPeer: Equatable, Sendable { let pid: pid_t; let uid: uid_t; let startTime: UInt64? }
/// A connection kept open after its first reply (only for verbs registered with `holds: true`).
final class ControlHold: @unchecked Sendable {
    func onClose(_ handler: @escaping @MainActor () -> Void)   // EOF, read error, server stop; called once, on main
    func finish(_ final: ControlResponse)                      // writes one more line, closes; idempotent
}
struct ControlContext { let peer: ControlPeer; let hold: ControlHold? }   // hold non-nil only for holds: true verbs
// ControlCommandRegistry.Handler becomes  @MainActor (ControlRequest, ControlContext) async -> ControlResponse
// register(_:policy:offOnly:cliAllowed:holds: Bool = false, summary:lifetime:_:); existing call sites keep compiling
// through an overload that takes the old one-argument handler (removed at the step-3 exit).
// ControlListener.Handler becomes (ControlRequest, ControlPeer, ControlCancellation, ControlHold?, Reply) -> Void.
// KitControl: ControlResponse gains `holding: Bool` (lossy, default false); CLIClient keeps reading without a timeout
// after a `holding` reply until EOF or the final line. maxHeldConnections = 1.
```
A handler that returns a `holding` response keeps the connection; any other response closes it as today. `getpeereid` keeps its uid check; a peer whose pid or start time can't be read gets "Snaptic couldn't identify the caller." (exit 5) for `holds` verbs only.

Never via CLI: editing triggers, presets, guards, Drive Alive volumes, activity mode, resuming automatic sessions, turning features on, Start Anyway. `KitControl.protectedSettings` replaces `"sleepprevention", "preventsleep"` with `"awake", "nudge", "pointernudge", "drivealive", "activity", "guards", "batteryguard", "thermalguard"`; `feature disable` stays limited to Displays; `module disable` help text lists Awake.

### 2.11 Runtime state, contracts, module (lead)

```swift
// Awake/AwakeRuntimeState.swift (lead)
struct AwakeLastEnd: Equatable { let reason: AwakeEndReason; let at: Date }
@MainActor final class AwakeRuntimeState: ObservableObject {
    @Published var moduleState: ModuleState = .stopped
    @Published var effectiveFeatures: Set<AwakeFeature> = []
    @Published var availability: [AwakeFeature: FeatureAvailability] = [:]
    @Published var governing: AwakeGoverning = .inactive
    @Published var remaining: Double?            // updated at AwakeCountdown.nextChange only
    @Published var assertion: AwakeAssertionType = .off
    @Published var power: PowerFacts?
    @Published var guardHold: AwakeEndReason?
    @Published var lastEnd: AwakeLastEnd?        // shown for 12 h after a non-user end
    @Published var activeTriggerIDs: [StableID] = []
    @Published var waitingTriggerIDs: [StableID] = []   // enabled, condition true, start delay running
    @Published var pausedUntil: Date?
    @Published var activity: AwakeActivityMode = .off   // what acted at the last interval ("Appearing active" / "Moving the pointer")
    @Published var activityCapped = false                // "Stopped appearing active after 1 hour."
    @Published var drives: [DriveAliveService.VolumeState] = []
    @Published var lidWillSleep: Bool?          // nil = no lid
    @Published var indicatorVisible = false     // our status item exists and isVisible
    func isEffective(_ f: AwakeFeature) -> Bool
    func reset()
}

// Awake/AwakeContracts.swift (lead): protocols + ChangeFanout (§2.8)
@MainActor protocol AwakeFeatureController: AnyObject {
    static var id: AwakeControllerID { get }
    init()
    func availability(of feature: AwakeFeature, context: AwakeContext) -> FeatureAvailability
    func start(_ context: AwakeContext, lifetime: Lifetime, effective: Set<AwakeFeature>)
    func effectiveFeaturesDidChange(_ effective: Set<AwakeFeature>)
    func configDidChange(from old: AwakeConfig, to new: AwakeConfig)
    func stop()
}

// Core/ModuleContracts.swift (lead): the host owns status-item slots; a module with a custom item provides it (code B3).
// The Kit plan decides; the provider only executes (code R2-M6): it creates and removes its item ONLY inside
// applyStatusItem, so Kit's plan and the item can't diverge for a turn.
struct CustomItemRow: Equatable {
    let exists: Bool                 // StatusItemPlan.custom contains the module
    let presence: MenuPresence
    let footer: Bool                 // StatusItemPlan.sharedFooterInOwnMenus: add Recent Notices ›, Quit Snaptic
    let recentNotices: Bool          // notices exist (with footer)
}
@MainActor protocol StatusItemProvider: AnyObject {
    var statusItem: NSStatusItem? { get }                      // nil while the item doesn't exist
    func applyStatusItem(_ row: CustomItemRow)                 // called from StatusMenu.applyPlan, same turn as the plan
}

// Awake/AwakeContext.swift (lead)
@MainActor final class AwakeHost {           // explicit host services (code B3: "statusItems" had no definition)
    let safeMode: SafeModeState
    let signals: HostSignals
    let hotkeys: GlobalHotkeys
    let commands: ControlCommandRegistry
    let toasts: ToastPresenter
    let permissions: PermissionFlow
    let requestMenuRebuild: @MainActor () -> Void
    /// Re-plans now (StatusMenu.applyPlan in this turn): called whenever `governing` changes active ↔ inactive.
    let requestStatusPlan: @MainActor () -> Void
    /// ⌘-drag removal and the "Don't Show" fallback write presence through the host (ModulesConfig is the host's).
    let setPresence: @MainActor (MenuPresence) -> Void
    /// Adapter (consistency m13): calls ModuleContext.openSettings(route?.id); the host parses "<root>.<route>".
    let openSettings: @MainActor (SettingsRoute?) -> Void
    init(_ module: ModuleContext)
}
@MainActor final class AwakeContext {
    let assertions: AssertionManager, power: PowerMonitor, system: SystemEventsMonitor, apps: AppMonitor
    let displays: DisplayPresence, usb: USBWatcher, volumes: VolumeMonitor, audio: AudioMonitor
    let cpu: CPUSampler, idle: IdleSampler, network: NetworkMonitor, bluetooth: BluetoothPresence
    let activity: ActivitySimulator, driveAlive: DriveAliveService, disk: DiskIOSampler, process: ProcessWatch
    let config: ConfigStore<AwakeConfig>, state: ConfigStore<AwakeRuntimeSnapshot>, history: ConfigStore<AwakeHistory>
    let runtime: AwakeRuntimeState
    let host: AwakeHost
    let sessions: SessionController, triggers: TriggerController   // controllers other controllers call
    func service(_ id: AwakeServiceID) -> any AwakeServiceLifecycle
    func source(for kind: AwakeCriterionKind) -> any CriterionSource
    init(host: AwakeHost, config: ConfigStore<AwakeConfig>, state: ConfigStore<AwakeRuntimeSnapshot>,
         history: ConfigStore<AwakeHistory>, runtime: AwakeRuntimeState)
}

// Core/HostSignals.swift (lead, new): host facts modules read
@MainActor final class HostSignals: ObservableObject {
    @Published var switcherVisible = false      // A sets it
    var isTerminating = false                   // ModuleHost.shutdown() sets it before stopping modules (code M9)
    var launchSessionStarted = false            // per process (code M9)
    init()
}
```
`AwakeModule` (lead) follows `DisplaysModule` line by line (resolve, apply order, kill switches, config sink with one main-queue hop, `stop()` sync and idempotent: controllers reverse, services reverse, `assertions.releaseAll()` last-resort, flush stores, held CLI connections finished) and adopts `StatusItemProvider` by forwarding to `IndicatorController` (G owns the item; StatusMenu never builds an Awake slot). r2's admission hooks and consent store are withdrawn (N10): the three stores are plain `ConfigStore`s.

`SnapticModule` additions (§4.1: `tint`, `highlights`, `settingsRoot()`, `settingsDestination(_:)`, `settingsIndex()`) get **protocol-extension defaults** in `ModuleContracts.swift` (gray tint, no highlights, a root that renders the module's existing `settingsPages()` content, nil, `[]`), and `settingsPages()` stays until the step-3 exit, so A's `WindowSwitcherModule` and H's `SettingsWindowHost.swift` compile at step 0 (code R2-M2a).

### 2.12 Behavior across system events (normative)

| Event | Behavior |
|---|---|
| Snaptic crash / force quit | powerd releases the assertion on process exit ([PA] §1.2). Nothing else to undo (Drive Alive leaves an 8-byte hidden file). Relaunch in the same boot resumes the admitted manual session. |
| System sleep (lid, Apple menu, low battery, thermal) | Assertions don't prevent it. `willSleep`: if `endOnSystemSleep`, end `.systemSleep`; stop activity and Drive Alive writes. `didWake`: recompute remaining (continuous clock), end expired sessions, re-arbitrate, verify the assertion, triggers step after 5 s settle. |
| Lid closed on battery, not desktop mode | Mac sleeps. When a session is active **and** the Mac is on battery or has no external display (design m5), the Awake menu shows "Closing the lid will put your Mac to sleep. To keep it awake with the lid closed, connect power and an external display." |
| Clock change | Until-sessions and `pausedUntil` re-evaluated now (re-arm if the end moved > 5 s); duration sessions unaffected; schedules re-evaluated. |
| Time-zone change | `NSTimeZone.resetSystemTimeZone()`; until instants kept, labels re-rendered; schedules use the new zone at the next step. |
| Screen lock / screensaver (session dictionary) | Session continues; plan downgrades display→system (C1 default); activity paused; Drive Alive continues (guards permitting); toasts suppressed. With `endAfterLockedHours`, a lock lasting that long ends `.lockedTooLong`. |
| Fast user switching (session dictionary: not on console) | Plan downgrades to system; activity paused; `userSwitchEnd` ends `.userSwitch` immediately or after 1 h off console (default). Becoming active again re-applies. |
| Low Power Mode on | Toast once "Low Power Mode is on. Awake keeps running." unless `endOnLowPowerMode`. |
| Thermal serious / critical | §2.6 (critical also stops Drive Alive). |
| Safe Mode | Manual sessions, guards, indicator, history, shortcuts, CLI work; triggers, activity, nudge, Drive Alive are removed. |
| Displays panic ("Restore All Displays") | Not an Awake participant: keep-awake is not a display hazard. (0.2's "sleep prevention released" row goes with the feature in step 3.) |
| Module turned off from Settings | The §4.3 confirmation first when a session or enabled rule exists (one text, defined only in §4.3; consistency m5); then `stop()` with `isTerminating == false`: assertion released, session ended, snapshot cleared, status item removed, a held CLI connection finished ("Awake was turned off."). |
| `Modules.disable.awake` set | Module never starts (N14); a snapshot left from earlier is cleared at launch. |
| Quit | `isTerminating = true`, then `stop()`: assertion released, snapshot kept for resume (`hold(.connection)` excluded), held CLI connections finished ("Snaptic quit."; client exit 5). |

### 2.13 Interaction with Displays and the Switcher

- **Displays**: `sleepPrevention` is removed **in step 3**, in one coordinated merge by D and F with the lead's lines and A's Kit rows (code B2): `DisplayFeature.sleepPrevention` and its spec, `PerDisplayManagement.preventSleep` (kept decodable and encoded until 0.4, ignored), PowerController's assertion code, `ManagementIDs.dSleepPrevention*`, `DisplaysRuntimeState.sleepPreventionActive`, the Arrangement-page section, the menu badge, the CLI `prevent-sleep` verb, the KitBackup/KitControl/DisplaysUIModel/Diagnostics rows and their tests. Until then the enum case, spec and runtime property stay and compile; M1 reads raw JSON either way, so it doesn't depend on the case. The ratchet (§6.3) lists `PowerController.swift` for L1 until that merge. Awake never calls Displays code except B's pure `DisplayIdentity`/`Fingerprint.matches` helpers and a read-only look at `DisplaysConfig` custom names.
- **Switcher**: no functional coupling. Pointer nudges are tagged and suppressed while the switcher panel is visible (`HostSignals.switcherVisible`, set by A). Hotkey conflicts across modules are reported by `GlobalHotkeys` with the owning module's name.
- **Host**: `ModuleHost` gains `awake: AwakeModule`, `awakeStore`, `awakeStateStore`, `awakeHistoryStore` (one store per key: `SnapticAwakeV1`, `SnapticAwakeStateV1`, `SnapticAwakeHistoryV1`), `case .awake` in `module(_:)`, the `Modules.disable.<id>` read (N14), flushes the stores on quit, and includes them in Reset All Settings (history and state cleared too; `restoringDefaults` turns nudge and Drive Alive off).
- **Upgraders** (code M4, C7, code minor 8): in `ModuleHost.init`, when module settings existed before this launch and `modules[.awake] == nil`, the host inserts `ModulePreferences(enabled: false, presence: .ownIconWhenActive)` for Awake **before** M1 runs; `ModulesConfig.upgradeDefaults()` (0.1 users, where `modulesExisted` is false) inserts the same entry. M1 turns it on only if it produced an enabled rule. `ModulesConfig.defaultPreferences(_:)` becomes per id (fresh installs: Awake enabled, `.ownIconWhenActive`); `ConfigModulesTests` lines 15, 16 (`placement(id) == .shared` no longer holds for Awake) and 34 are updated (consistency m9).

### 2.14 Config models (Kit; lossy decode per field, `sanitized()` clamps everything)

```swift
// Config/ConfigAwake.swift (lead shell; G fills the functions in step 2, code M14)
package struct AwakeConfig: ConfigModel {
    package var features: LossyMap<AwakeFeature, Bool>
    package var sessions: AwakeSessionsConfig        // G
    package var guards: AwakeGuardsConfig            // G (§2.6)
    package var triggers: AwakeTriggersConfig        // G (§2.7)
    package var activity: AwakeActivityConfig        // J
    package var drives: DriveAliveConfig             // J
    package var indicator: AwakeIndicatorConfig      // G (edited on the Menu Bar page)
    package var shortcuts: LossyMap<AwakeActionID, HotkeyCombo>   // G
    package var migrations: [String]                 // ids of one-time migrations already run ("fromDisplays.v1")
    package init()
    package func sanitized() -> AwakeConfig
    /// Page Restore Defaults: everything back to defaults; pointerNudge off, nudge presets → declare, Drive Alive
    /// volumes cleared (safe direction, security L6).
    package func restoringDefaults() -> AwakeConfig
    /// Backup (security M7): nudge → declare, drops drives, features.pointerNudge, recentApps, startAtLaunch,
    /// salted hashes; rules only when `includeTriggers` (the user ticked the export checkbox).
    package func exportable(includeTriggers: Bool) -> AwakeConfig
    /// Import: same stripping, guards monotonic over `current`, pointerNudge and Drive Alive volumes kept from
    /// `current`. Applied by KitBackup AFTER its generic `merge`/`mergeByID`, as the last step (security L5).
    package func importable(current: AwakeConfig) -> AwakeConfig
}
// r2's AwakeConsent / ConfigAwakeConsent.swift / AwakeConsentStore are withdrawn (N10).

// Config/ConfigAwakeSessions.swift (G)
package enum AwakePresetKind: Equatable, Sendable {
    case indefinite, duration(seconds: Int), untilTime(hour: Int, minute: Int)
    case untilIdle(UntilIdleSpec, maxSeconds: Int?)   // "At most" pop-up in the editor (parity minor 6)
}
extension AwakePresetKind: Codable { package init(from decoder: Decoder) throws; package func encode(to encoder: Encoder) throws }
package struct AwakePreset: Codable, Equatable, Sendable, Identifiable {
    package var id: StableID
    package var name: String?                   // nil = generated ("For 1 Hour", "Until 5:00 PM", "Until Turned Off")
    package var kind: AwakePresetKind
    package var options: AwakeSessionOptions?   // nil = "Use default" (parity M5)
    package init(id: StableID, name: String?, kind: AwakePresetKind, options: AwakeSessionOptions?)
}
package struct AwakeSessionsConfig: ConfigModel {
    package var presets: [AwakePreset]          // ≤ 12; default: 30 min, 1 h, 2 h, 5 h, Until Turned Off, Until Downloads and Tasks Finish
    package var defaultPresetID: StableID?      // nil or unknown → Until Turned Off (C10)
    /// What "Keep the display on" (display) and the Advanced activity switches (activity) edit; used when a preset
    /// has nil options.
    package var defaultOptions: AwakeSessionOptions
    package var lastCustomSeconds: Int          // 5400
    package var behavior: AwakeBehavior         // §2.6
    package var recentApps: [String]            // ≤ 5 bundle ids; local only, never exported
    package init()
    package func sanitized() -> AwakeSessionsConfig
    /// preset.options ?? (task-bound kind ? defaultOptions with display = .maySleep : defaultOptions).
    /// Then activity is clamped to what is effective: `.nudge` → `.declare` unless pointerNudge is effective,
    /// anything → `.off` unless activity is effective (consistency M2).
    package func effectiveOptions(for kind: AwakeSessionKind, preset: AwakePreset?,
                                  effective: Set<AwakeFeature>) -> AwakeSessionOptions
    /// The per-kind default shown as "Default (…)" in the preset editor (consistency m6).
    package func defaultDisplayPolicy(for kind: AwakePresetKind) -> AwakeDisplayPolicy
}
```
**Activity switches** (consistency M2, normative; Kit test): Awake › Advanced "Appear active" on sets `features.activity = true` and `defaultOptions.activity = .declare`; off sets both off (`.off`). "Move the pointer slightly" on sets `features.pointerNudge = true` and `defaultOptions.activity = .nudge`; off sets `features.pointerNudge = false` and `defaultOptions.activity = .declare`. Presets with explicit options keep theirs; `effectiveOptions` clamps them to the effective features. Changing "Keep the display on" while a session that uses default options runs applies to that session at once (parity M4).
```swift

// Config/ConfigAwakeIndicator.swift (G)
/// Menu Bar page "Time" pop-up: Don't Show / Time Remaining / End Time (design M5).
package enum AwakeIndicatorStyle: String, Codable, CaseIterable, Sendable { case icon, iconAndTime, iconAndEndTime }
package enum AwakeGlyphFamily: String, Codable, CaseIterable, Sendable {
    case cup, eye, lightbulb                     // cup.and.saucer / eye / lightbulb, outline idle, .fill active (tested on 14)
    package var idle: String { get }
    package var active: String { get }
}
package struct AwakeIndicatorConfig: ConfigModel {
    package var style: AwakeIndicatorStyle          // .icon ("Show" pop-up on Menu Bar)
    package var glyph: AwakeGlyphFamily             // .cup
    package init()
    package func sanitized() -> AwakeIndicatorConfig   // unknown legacy glyph (mug, sun, bolt) → .cup
}

// Config/ConfigAwakeDevices.swift (J)
package struct VolumeUUIDKey: RawRepresentable, Hashable, Sendable, Codable {   // code M13
    package let rawValue: String                 // canonical uppercase UUID
    package init?(rawValue: String)              // nil unless UUID(uuidString:) parses
    package init(from decoder: Decoder) throws
    package func encode(to encoder: Encoder) throws
}
package struct AwakeActivityConfig: ConfigModel {
    package var stopAfterHours: Int              // 1; 1...8, Snaptic's continuous clock from the first action (N10)
    package init()
    package func sanitized() -> AwakeActivityConfig
}
package struct DriveAliveVolume: Codable, Equatable, Sendable {
    package var name: String; package var enabled: Bool
    package var firstWriteDone: Bool = false     // set by the first write after the UI turned the volume on (§2.9)
    package init(name: String, enabled: Bool, firstWriteDone: Bool = false)
    package init(from decoder: Decoder) throws   // lossy per field (rule 9, code sig)
}
package struct DriveAliveConfig: ConfigModel {
    package var volumes: LossyMap<VolumeUUIDKey, DriveAliveVolume>   // ≤ 16
    package var intervalSeconds: Int             // 120, 30...600 ("Check drives every")
    package var evenWithoutSession: Bool         // false (C9, "Also when no session is running")
    package init()
    package func sanitized() -> DriveAliveConfig
}

// SnapticKit/AwakeSnapshot.swift (G): key SnapticAwakeStateV1
package struct AwakeRuntimeSnapshot: ConfigModel {
    package var bootSession: String              // kern.bootsessionuuid when written (code R2-M3)
    package var manual: AwakeSession?
    package var suppressions: LossyMap<StableID, TriggerSuppression>
    package var pausedUntil: Double?             // wall time; "Pause automatic sessions" (only here, code M2)
    package var guardMemory: GuardMemory
    package init()
    package func sanitized() -> AwakeRuntimeSnapshot
    /// Load-time clamp (Kit half of code R2-M8): drops a manual session from another boot or out of range and
    /// `hold(.connection)`; on a boot mismatch drops `until` suppressions (keeps `untilFalse`) and resets guard memory
    /// except `warnedSerious`; keeps `source` (security L1). Pid checks and guards run in SessionController.restore.
    package func sanitized(now: ClockNow) -> AwakeRuntimeSnapshot
}

// SnapticKit/AwakeHistory.swift (G): key SnapticAwakeHistoryV1
package enum AwakeHistoryKind: String, Codable, Sendable { case indefinite, duration, until, app, idle, process, automatic }
package struct AwakeHistoryEntry: Codable, Equatable, Sendable {
    package var start: Double; package var end: Double
    package var kind: AwakeHistoryKind
    package var presetID: StableID?; package var triggerID: StableID?
    package var bundleID: String?                // app sessions, for Start Again; local only (security L6)
    package var endReason: AwakeEndReason
    package init(start: Double, end: Double, kind: AwakeHistoryKind, presetID: StableID?, triggerID: StableID?,
                 bundleID: String?, endReason: AwakeEndReason)
}
package struct AwakeHistory: ConfigModel {
    package var entries: [AwakeHistoryEntry]
    package init()
    package func sanitized() -> AwakeHistory
    package func appending(_ e: AwakeHistoryEntry, cap: Int) -> AwakeHistory   // cap 500; merges < 60 s `.replaced` runs
    package func pruned(now: Double, keepDays: Int) -> AwakeHistory            // 90
    /// Day boundaries come from the app (Calendar) as unix times: Kit stays ICU-free (N12).
    package func totals(todayStart: Double, weekStart: Double, now: Double) -> (today: Double, week: Double)
}
```

`AwakeActionID`'s raw values are `awake.*` (G registers them). `LossyMap<StableID, …>` works because `StableID` is `RawRepresentable` with `String` raw values.

**Outside changes** (N10, lead r3): `ConfigStore` is unchanged (no `admit:` hook; r2's hook, `revertedAtLoad`, `onAdmissionReverted` and the Keychain store are withdrawn, which also retires code R2-M5/M11 and consistency M6). A `defaults write` to `SnapticAwakeV1` takes effect like any setting through `onExternalChange`, after `sanitized()`. What keeps that safe is runtime policy that reads no config the attacker controls: pointer movement needs a live UI-started session (`uiStartedInProcess`, never persisted), the activity cap runs on Snaptic's clock, the hard floor and critical-heat end are constants, CLI sessions never drive Drive Alive (source kept through restore), and the snapshot is read once at start through `sanitized(now:)` + `restore(_:)`. §3.2 states the residual risk.

## 3. Security and privacy (additions to 0.2 §4.10)

Threat model unchanged: a same-user process can already hold power assertions (`caffeinate`), write our defaults and launch Snaptic. Snaptic must not let it borrow Snaptic's TCC grants (Accessibility, Removable Volumes), run code, or extract data Snaptic observes.

### 3.1 CLI may start sessions (N1)

Allowed because starting an Awake session grants nothing new: any same-user process can create the identical assertion itself (`caffeinate`). Constraints that keep it that way:
- The CLI server is off by default (General › Command line) and keeps its 0.2 socket rules (0700/0600, `getpeereid`, 20/s), plus 1/s for `start`, `hold`, `stop`, `extend` (security L3).
- CLI sessions are `source: .commandLine` (kept through restore, security L1), visible in the indicator and menu ("Started from the command line"), subject to every guard, no "Start Anyway"; a toast says so at most once per 10 minutes, so a hidden indicator (26/27) can't hide a script. These are **UX, not a boundary** (security L4): any same-user process can run `caffeinate` invisibly, so visibility and bounds only keep Snaptic from being the quieter tool.
- **Never** pointer movement or Drive Alive: presets or options with `nudge` are refused, pointer movement acts only for UI-started sessions (N10), and `DriveAlivePolicy.shouldWrite` ignores sessions whose source is `.commandLine` (OQ-1 settled strict). Drive Alive has no verbs, and its first write follows a UI action.
- **Never replaces a UI session**: `start`, `hold` and `preset` are refused (exit 4) while a session the user started in Snaptic runs (security L4).
- **Never unbounded**: no argument = 1 h; `indefinite` refused; `hold` lasts while its own connection and process live (or a named same-uid pid lives, verified by start time) and at most 12 h (24 h with `--max`); the peer is identified by the server (`LOCAL_PEERPID` on the accepted fd), never by the request.
- Closed grammar only (`AwakeCommandGrammar` over `AwakeDurationGrammar`, digit/decimal/overflow limits); max 30 days for `start`; no free-form strings reach the assertion or the log.

### 3.2 Settings that touch Snaptic's grants or safety floors (N10)

r2 tried to make some settings writable only from the UI with a Keychain consent record. That is withdrawn (lead r3): ad-hoc builds (`build-app.sh` defaults to `SIGN_IDENTITY=-`) can only use the legacy file keychain, where a same-user process can pre-create the item with an ACL that trusts Snaptic (`security add-generic-password -A …`; security H1, code R2-M5), and every ad-hoc update changes the cdhash, losing consent each time. A protection that is both forgeable and flaky is worse than an honest statement. Instead, **runtime rules that config can't change** carry the weight:

| Capability | What a same-user process can do by editing defaults | What still holds |
|---|---|---|
| Pointer movement (Accessibility grant) | Turn on `pointerNudge`, set a preset's or the default options' activity to `nudge` | Snaptic moves the pointer only while a session the user started by a direct action in Snaptic's own UI **in this process** governs (menu click, Settings button, Snaptic hotkey; `uiStartedInProcess` is never persisted), never for CLI, rule, `launch`, restored or resumed sessions, never while locked or off console, ±1 pt mouse-moved only (lint L2), at most `stopAfterHours` (≤ 8 h, clamped) on Snaptic's clock, and the menu says "Moving the pointer" while it does. Residual: if the user starts such a session, the attacker's setting makes Snaptic post 1-pt moves the user didn't choose, for ≤ 8 h; it can't click, type or scroll |
| Drive Alive (Removable Volumes grant) | Add an eligible volume UUID, enable it, set `firstWriteDone`, set "Also when no session is running" | Writes go only to eligible external volumes (DiskArbitration + fd checks, §2.9), only the fixed 8-byte `.snaptic-keepalive` file, never for CLI sessions. Drive Alive grants **no new capability**: a same-user process can write files to those volumes itself. Residual: an unprompted Removable Volumes dialog, which the user can decline |
| Battery floor | Turn the user floor off or set it to 5% | The fixed 5% hard floor and two-unreadable-reads rule always end sessions and Drive Alive on battery; critical heat always ends (§2.6). Residual: none beyond what `caffeinate` allows anyway |
| Snapshot (`SnapticAwakeStateV1`) | Write a session, clear guard memory | Read once at start: `sanitized(now:)` + `restore(_:)` keep the written `source` (a forged `.menu` source still never sets `uiStartedInProcess`), re-verify pids, evaluate guards with live facts and recompute guard holds; outside writes while Awake runs are ignored (security L2) |

- **Restore Defaults / Reset All Settings** turn pointer movement off and clear Drive Alive volumes (security L6).
- Import (`importable(current:)`, after KitBackup's merge) never brings in pointer movement or volumes and only tightens guards (security L5).
- Not a boundary against a process that drives Snaptic's UI with Accessibility or replaces a user-writable app bundle (0.2 R5.7).

### 3.3 Activity simulation

- Default `declare` uses no TCC and posts no events.
- `nudge` (experimental) is the only code path in Snaptic that posts mouse events: one file (`ActivitySimulator.swift`, lint L2), `mouseMoved` ±1 pt only from a private-state event source, tagged 'SNPT', never key/click/scroll, never within 2 pt of a display edge, never while locked, in the screensaver or off console (all read from the session dictionary and process state, never from notifications alone, security M2), never when the user typed or clicked within the interval, only for UI-started sessions of this process (N10); Accessibility is requested lazily, only when the user turns nudge on (through `PermissionFlow`), and the toggle explains how to revoke it.
- Both modes stop `stopAfterHours` (default 1 h, max 8 h) after they first acted in the session, **measured on Snaptic's continuous clock** (security M2: Snaptic's own declarations may reset system idle, so idle time can't bound them). Organizations can turn them off with `Awake.disable.activity` / `Awake.disable.pointerNudge` (N14).

### 3.4 Drive Alive writes

Fixed file name at the volume root; target derived from the live mount list by UUID and re-verified on a directory fd (`fstatfs` mount point, file-system allowlist, `MNT_LOCAL` set, `MNT_RDONLY`/`MNT_ROOTFS` clear, `f_mntfromname` equal to the eligible BSD name, `fgetattrlist` volume UUID, `openat` + `O_NOFOLLOW`, same `st_dev`), never from stored paths or user text; `fstat` checks (regular, ours, one link, ≤ 64 B); 8 bytes of timestamp; never internal, boot-container, system, read-only, non-local, disk-image (DiskArbitration) or Time Machine volumes (Kit `DriveAlivePolicy`, tested); removal via `unlinkat` only of an 8-byte file that passes the same checks; stop before unmount; battery floor and thermal guards apply in every mode; I/O off main with results hopping back. The Removable Volumes grant is Snaptic's own, used only for this file, first used right after a UI action.

### 3.5 No code execution, no network

Awake spawns nothing (lint rule 12 already bans `Process`, `posix_spawn`, `NSAppleScript`, `NSUserScriptTask`, `system(` outside HelperSpawner; r1's L3 duplicated it and is dropped); `hold` observes a process with a kqueue `EVFILT_PROC` source and `proc_pidinfo`, never signals, spawns or wraps a command; triggers have no actions besides starting a session; no URL scheme; no AppleScript. NetworkMonitor reads kernel/configd state only (`SCDynamicStore`, `sysctl NET_RT_IFLIST2`, routing-table `sysctl`); DiskIOSampler reads IORegistry properties only; CPUSampler reads `proc_pid_rusage` of same-user processes only; lint bans `URLSession`, `NWConnection`, `CFSocket`, `socket(`, `connect(` in Awake as elsewhere.

### 3.6 Privacy

- **Logs** (`EventLog`, `.awake`): written only as `EventLog.shared.record(_ event: AwakeLogEvent)` (A adds the overload in `Core/EventLog.swift`; it is the only code that names the `.awake` category; consistency m10, code minor 5), a closed Kit enum (G, `SnapticKit/AwakeLogEvent.swift`) with a fixed `text` per case. Cases are split: **counted only** (`sessionStarted(AwakeHistoryKind)`, `sessionEnded(AwakeEndReason)`, `triggerActive(index: Int)`, `activityCapped`) increment a per-case counter in `AwakeDiagnostics` and never enter the ring, so no activity timeline exists anywhere; **ring** cases are errors only (`assertionFailed`, `driveAliveError(DriveAliveError)`, `holdRefused`, `restoreDropped`). Lint L9 bans `record(.awake` and the token `EventCategory.awake` outside `Core/EventLog.swift` (security M6). No app names, bundle ids, process names, pids, volume names/UUIDs, USB names/serials, addresses, router data, criterion payloads or rule names can reach the log.
- **CPU and disk samples**: only aggregate numbers (the busiest same-user process's share, total CPU, summed disk bytes) are kept, in memory, for the running untilIdle session; no pid or process name is stored, shown, logged or exported.
- **Assertion properties** are world-readable (`pmset -g assertions`): name is fixed; `Details` is only `manual` or `automatic` (no criterion kinds).
- **CLI** `awake status`: kinds and trigger numbers only.
- **Stored identifiers**: router MACs and USB serials as salted hashes (`SnapticAwakeSalt`, never exported); display matches as salted fingerprint tiers (existing salt).
- **Backup** (`AwakeConfig.exportable/importable`, A wires them into KitBackup's new `awake` section): export includes presets (nudge rewritten to declare), guards, indicator, behavior; trigger definitions **only** when the user ticks "Include automatic-session rules (contains app, device and network names)" (off by default; salted hashes are stripped either way since they are useless on another Mac); omits history, runtime state, salts, `recentApps`, `startAtLaunch`, Drive Alive volumes, `pointerNudge`. Import: same stripping, guards monotonic (stricter only; `awake.guards` joins `safetyPaths`), protected fields always kept from the current config.
- **Diagnostics** (shared report): Awake section with effective features, governing kind, assertion type, guard state, source activity (running/idle), counts of rules/conditions by kind, Awake event **counts** per `AwakeLogEvent` case (from `AwakeDiagnostics`, no timestamps), Drive Alive volume count and last error codes. `DiagnosticsController.eventLines()` (F) keeps only entries whose `EventCategory.isExportedInDiagnostics` (lead, `KitModules.swift`; false for `.awake`, Kit-tested) holds (security M3). The "Other apps keeping your Mac awake" list never goes into diagnostics, logs or CLI.
- `settingsIndex()` entries are static strings (test: no entry title or keyword comes from config).

## 4. Settings redesign

### 4.1 SettingsUI component library (H, `Sources/Snaptic/SettingsUI/`)

All pages use these and nothing else for rows (lint L5: raw `Slider(`, `Stepper(` and `.font(.caption)` captions are banned outside `SettingsUI/`; L12: `.controlSize(.regular)` only in `SettingsPageHeader.swift`). Grouped `Form` (`.formStyle(.grouped)`), system text styles, semantic colors, 4-pt grid, 0.15 s crossfades only, Reduce Motion/Transparency honored ([DS] §5). **Row switches use the grouped form's default (small) size; only the page header switch is `.regular`** (design B2; System Settings precedent on 14–27). A subordinate row appears only while its parent is on and is indented 20 pt; it is never a smaller control.

```swift
// Core/ModuleContracts.swift (lead; code minor 12): types the shell contract references
enum SettingsTint: String { case gray, graphite, blue, indigo, orange, green, red, purple, teal; var color: Color { get } }
struct FeatureHighlight: Identifiable { let id: String; let symbol: String; let title: String; let text: String }

// SettingsUI (H)
struct SettingsIcon: View { init(_ symbol: String, tint: SettingsTint, size: CGFloat = 20) }   // rounded-square tile, a11y hidden

/// Top section of every page. `isOn` = master switch (module or feature group), `.regular` size;
/// `switchLabel` is its accessibility label and tooltip ("Use Awake", N5).
struct SettingsPageHeader: View {
    init(_ title: String, summary: String, symbol: String, tint: SettingsTint,
         isOn: Binding<Bool>? = nil, switchLabel: String? = nil, badge: SettingsBadge? = nil, status: String? = nil)
}
enum SettingsBadge: Equatable { case beta, experimental, new, paused(String), unavailable(String) }

/// Shown under the header while a module or feature group is off: 2–3 "what this does" rows.
struct FeatureHighlights: View { init(_ rows: [FeatureHighlight]) }

/// Title + optional one-line help (LabeledContent subtitle) + trailing control.
/// Reset: a glyph only for continuous values (`resetGlyph: true`, used by SliderSetting/StepperSetting/NumberField);
/// every row with `reset` also gets a context menu "Reset to Default" (design M6).
struct SettingRow<Control: View>: View {
    init(_ title: String, help: String? = nil, anchor: String? = nil, isDefault: Bool = true,
         reset: (() -> Void)? = nil, resetGlyph: Bool = false, resetLabel: String? = nil,
         @ViewBuilder control: () -> Control)
}
/// arrow.counterclockwise 11 pt, borderless, secondary; always reserves 16 pt; fades 0.15 s (instant with Reduce Motion);
/// tooltip "Reset to 50%", AX label "Reset Contrast to 50 percent". Visible only while value ≠ default
/// (`SliderMath.isDefault`); with `defaultValue: nil` (live Brightness) there is never a glyph, the slot stays (design m8).
struct ResetButton: View { init(visible: Bool, label: String, action: @escaping () -> Void) }

/// Precondition missing → the control is disabled, its help stays, and `disabledReason` + `fix` go to the
/// section footer ("Needs Accessibility." [Open Accessibility Settings…]). Hardware can't do it → the caller omits the row.
struct ToggleSetting: View {
    init(_ title: String, help: String? = nil, isOn: Binding<Bool>, subordinate: Bool = false,
         anchor: String? = nil, badge: SettingsBadge? = nil, disabledReason: String? = nil, fix: StatusAction? = nil)
}

/// Every slider in Settings (N4). Normative layout (design M6), trailing cluster after the title:
///   slider (min 140, ideal 200) · 8 · field (width = widest formatted value of the range for its ValueFormat,
///   min 48; "1512 × 982" and "6500 K" fit; design m7) · 4 · reset slot 16 (always reserved).
///   A discrete slider (resolution) snaps a typed value to the nearest position.
/// The field IS the live value (shows `drag ?? value`, unit inside the text: "70%", "60 Hz", "15 min");
/// `.roundedBorder`, `.controlSize(.small)`, monospaced digits, trailing-aligned; focus selects all; parses "70", "70 %", "70%".
/// ViewThatFits fallback: title row (field + reset trailing) above a full-width slider.
/// Tick marks when ≤ 11 positions; ←/→ and accessibilityAdjustableAction move one step (or 1% of the range).
struct SliderSetting: View {
    init(_ title: String, help: String? = nil, value: Binding<Double>, in range: ClosedRange<Double>,
         step: Double? = nil, defaultValue: Double?, format: ValueFormat,
         minSymbol: String? = nil, maxSymbol: String? = nil,
         commit: SliderCommit = .throttled(hz: 15), preview: (@MainActor (Double) -> Void)? = nil,
         anchor: String? = nil, subordinate: Bool = false, disabledReason: String? = nil)
}
enum SliderCommit: Equatable {
    case live                  // hardware value through DisplayLiveControlling (§4.5): latest-wins mailbox
    case throttled(hz: Double) // config-backed: writes at most hz/s during a drag, final value on release
    case onRelease             // expensive side effects; `preview` gives live feedback meanwhile
}
/// Units and scaling for display, typing and VoiceOver (Kit `ValueFormat` in SliderMath.swift, hand-formatted, N12).
// e.g. .percent(of: 1) shows 0…1 as 0–100%; .seconds; .minutes; .hertz; .points; .nits; .kelvin; .plain(digits:)

struct NumberField: View {      // commits on Return and blur; clamps + snaps to step; Esc reverts; unit inside the text
    /// width nil = derived from `SliderMath.widestText(range:step:format:)` (design m7).
    init(_ accessibilityTitle: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double?,
         format: ValueFormat, width: CGFloat? = nil)
}
struct StepperSetting: View {   // small integer ranges (≤ ~20 values): label + NumberField + Stepper + reset slot
    init(_ title: String, help: String? = nil, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
         defaultValue: Int?, format: ValueFormat, anchor: String? = nil)
}
enum PickerSettingStyle { case automatic, popUp, segmented, radio, pullDown }
struct PickerOption<V: Hashable>: Identifiable {         // code M13: Identifiable needs an id
    let value: V; let title: String; let help: String?; let symbol: String?; let enabled: Bool
    var id: V { value }
    init(_ value: V, _ title: String, help: String? = nil, symbol: String? = nil, enabled: Bool = true)
}
struct PickerSetting<V: Hashable>: View {   // pop-up (> 4 options), segmented (2–4 short), radio (2–5 with help)
    init(_ title: String, help: String? = nil, selection: Binding<V>, options: [PickerOption<V>],
         style: PickerSettingStyle = .automatic, defaultValue: V?, anchor: String? = nil, subordinate: Bool = false)
}
/// Glyph tiles (Snaptic/module/Awake icons, display icons): rendered symbols with `.isSelected` AX trait, never raw names.
/// A radio group: the row title is the group label, arrow keys move the selection (design m10).
struct GlyphTilePicker: View { init(_ title: String, symbols: [String], selection: Binding<String>, anchor: String? = nil) }
/// Pull-down button with actions (Display Tools ▾, Copy Settings From ▾, Options ▾).
struct ActionMenuButton: View { init(_ title: String, items: [ActionMenuItem]) }
struct ActionMenuItem: Identifiable { let id: String; let title: String; let enabled: Bool; let action: @MainActor () -> Void }

struct InfoButton: View { init(_ title: String, message: String) }            // (i) popover, 280 pt; never opens a sheet
struct NavigationRow: View {                                                   // icon tile + title + trailing value + chevron
    init(_ title: String, symbol: String, tint: SettingsTint, value: String? = nil, route: SettingsRoute, badge: SettingsBadge? = nil)
}
struct ButtonRow: View { init(_ title: String, symbol: String? = nil, action: @escaping @MainActor () -> Void) }  // "Keyboard Shortcuts…", "Display Details…"
struct StatusAction { let title: String; let action: @MainActor () -> Void }
enum StatusStyle { case info, warning, error }
struct StatusRow: View { init(_ text: String, symbol: String? = nil, style: StatusStyle = .info, actions: [StatusAction] = []) }
/// ≤ 4 displays: tiles; more: a pop-up. Hidden with one display. Group AX label "Display".
/// Selection is shared across pages through SettingsShell.selectedDisplay (design m9).
/// Budget: counts toward a page's total, not toward its settings (design m13).
struct PerDisplayPicker: View { init(_ displays: [DisplayTile], selection: Binding<DisplayKey?>) }
struct DisplayTile: Identifiable, Hashable { let id: DisplayKey; let name: String; let isBuiltin: Bool; let badges: [String] }
/// Page footer: trailing `Advanced…` and (?) only (design M5). `restoreDefaults` appears here (leading) only on
/// pages without an Advanced sheet.
struct PageFooterButtons: View { init(advanced: (() -> Void)?, help: SettingsRoute?, restoreDefaults: RestoreDefaults? = nil) }
struct RestoreDefaults { let scopeName: String; let destructive: Bool; let action: @MainActor () -> Void }   // confirmation names the scope
/// 520 wide, ≤ 25 controls, Done = Return trailing; Restore Defaults… leading in its footer. Never presents another sheet.
struct AdvancedSheet<Content: View>: View {
    init(_ title: String, restoreDefaults: RestoreDefaults?, @ViewBuilder content: () -> Content)
}
/// List .onMove + ▲▼ context menu for keyboard; each row exposes VoiceOver actions Edit (when `onEdit`), Delete,
/// Move Up, Move Down (design M4, m10).
struct ReorderableList<Item: Identifiable, Row: View>: View {
    init(_ items: Binding<[Item]>, onEdit: ((Item) -> Void)? = nil, onDelete: ((Item) -> Void)?,
         @ViewBuilder row: @escaping (Item) -> Row)   // code M13
}
struct AppListEditor: View { init(_ title: String, help: String?, bundleIDs: Binding<[String]>, anchor: String?) }   // moved from Switcher AppListSection; used by Switcher and PIP
struct ShortcutSetting: View { init(_ title: String, help: String? = nil, combo: Binding<HotkeyCombo?>, owner: String, anchor: String? = nil) }  // wraps ShortcutRecorder; shows conflicts by owner
/// Empty lists: ContentUnavailableView with the page's own copy (design m8).
struct EmptyListView: View { init(_ title: String, symbol: String, text: String?, action: StatusAction?) }
/// Each page's scroll scaffold owns its ScrollViewReader (code minor 3); anchors register here.
struct SettingsPageScaffold<Content: View>: View { init(route: SettingsRoute, @ViewBuilder content: () -> Content) }
extension View { func settingsAnchor(_ id: String) -> some View }   // id + search highlight (1.2 s tint; static with Reduce Motion)
```

Shell contracts (lead, `Core/ModuleContracts.swift`; replaces `settingsPages()`). `SettingsRoute` and `SettingsSearchEntry` are **Kit** types (H, `SnapticKit/SettingsIndex.swift`) so the search ranking, anchor uniqueness and the control map are tested on Linux (code minor 13); each module's `settingsIndex()` returns its Kit table (`SettingsIndexAwake.entries`, …):

```swift
// SnapticKit/SettingsIndex.swift (H)
package struct SettingsRoute: Hashable, Sendable { package let id: String; package init(_ id: String) }   // "displays.color"
package struct SettingsSearchEntry: Hashable, Sendable {
    package let id: String; package let title: String; package let keywords: [String]
    package let root: String                 // sidebar item id
    package let route: SettingsRoute?        // sub-page, nil = root page
    package let anchor: String               // settingsAnchor id
    package let sheet: String?               // Advanced/other sheet id to open first
    package init(id: String, title: String, keywords: [String] = [], root: String, route: SettingsRoute? = nil,
                 anchor: String, sheet: String? = nil)
}

// Core/ModuleContracts.swift (lead)
struct SettingsRoot: Identifiable, Hashable {
    let id: String; let title: String; let symbol: String; let tint: SettingsTint
    let makeView: @MainActor () -> AnyView
    static func == (a: SettingsRoot, b: SettingsRoot) -> Bool { a.id == b.id }   // code M13: closure property
    func hash(into h: inout Hasher) { h.combine(id) }
}
@MainActor protocol SnapticModule: AnyObject {
    // id, title, symbolName, summary, state, requiredPermissions, start, stop, menuSection, settingsPages()
    // — unchanged; settingsPages() is removed at the step-3 exit (code R2-M2a)
    var tint: SettingsTint { get }
    var highlights: [FeatureHighlight] { get }                       // off-state block
    func settingsRoot() -> SettingsRoot                               // rendered whether running or not
    func settingsDestination(_ route: SettingsRoute) -> AnyView?
    func settingsIndex() -> [SettingsSearchEntry]                     // static per module; computed once
}
extension SnapticModule {   // step-0 defaults so existing conformers compile (code R2-M2a)
    var tint: SettingsTint { .gray }
    var highlights: [FeatureHighlight] { [] }
    func settingsRoot() -> SettingsRoot           // wraps settingsPages() content
    func settingsDestination(_ route: SettingsRoute) -> AnyView? { nil }
    func settingsIndex() -> [SettingsSearchEntry] { [] }
}
```

`SettingsShell` (H, `SettingsUI/SettingsShell.swift`; code minor 12: H owns it, the lead owns only the protocol types above):

```swift
@MainActor final class SettingsShell: ObservableObject {
    @Published var root: String                         // sidebar selection
    @Published var paths: [String: [SettingsRoute]]     // one NavigationStack path per root
    @Published var openSheet: String?
    @Published var highlightedAnchor: String?
    @Published var selectedDisplay: DisplayKey?         // shared PerDisplayPicker selection
    func moduleEnabled(_ id: ModuleID) -> Binding<Bool>
    func push(_ route: SettingsRoute)
    func pop()
    /// Sets root now, pushes the route on the next main-queue turn (macOS 14 drops a push in the same
    /// transaction), opens the sheet, and highlights only after the sheet has appeared (code minor 3).
    func reveal(_ entry: SettingsSearchEntry)
    init()
}
```
Detail column: `NavigationStack(path: binding(for: root)) { … }.id(root)`. Last root + route restored from `@AppStorage("settingsLastRoute")` (no dots in the key).

Kit (H, tested): `SliderMath.swift` (`ValueFormat`, `clampSnap`, `isDefault(value:default:step:)` with half-step tolerance, hand-written `format(_:decimalSeparator:)` and `parse(_:decimalSeparator:)` accepting "70", "70 %", "70%", "1,5 s" when the separator is ",", `spoken` for VoiceOver; the app passes `Locale.current.decimalSeparator` once, N12); `SettingsIndex.swift` (`SettingsSearch.rank(entries:query:) -> [SettingsSearchEntry]`: hand-written ASCII/Latin-1 diacritic and case folding (table, not ICU), prefix-of-word match on title > keywords > synonyms table; synonyms: DDC↔monitor/hardware, caffeinate/insomnia/amphetamine/keep awake/sleep/prevent sleep/lid/clamshell/jiggle/screen saver↔Awake, alt-tab/⌥⇥↔Window Switcher, PIP↔picture in picture, OSD↔brightness indicator, HiDPI↔sharper text, XDR↔extra brightness).

### 4.2 Information architecture

**Window**: `NavigationSplitView`, sidebar 200–240 pt with `.searchable(placement: .sidebar)` at the top, detail `NavigationStack` per root (back button for sub-pages), `.toolbar(removing: .sidebarToggle)`, **fixed width 715 pt, vertical resize only** (min height 520, default 720 so the Displays root's first navigation group is above the fold; [DS] §1, design m6/M6), title = current page. While open the app is `.regular` (0.2 R5.8 kept).

**Sidebar** (fixed; 7 rows; groups separated by spacing; consistency m1). Awake shows a "New" badge (`SettingsBadge.new`) until its page is first shown (`@AppStorage("settingsSeenAwake")`; only for users who had no Awake before, design M3):

```
[Search]
General              gearshape                gray
Menu Bar             menubar.rectangle        graphite
—
Window Switcher      rectangle.on.rectangle   indigo    (master switch on page)
Displays             sun.max.fill             blue      (master switch on page)
Awake                cup.and.saucer.fill      orange    (master switch on page)
—
Permissions          hand.raised.fill         blue
About                info.circle.fill         gray
```
Search results replace the list with "Title — Page" rows; choosing one calls `SettingsShell.reveal`. No results → `ContentUnavailableView.search(text:)`.

**Copy rules** ([DS] §4, normative): sentence case for labels, help, section headers; Title Case for buttons, menu items, page titles; serial comma ("Startup, command line, backup, and Safe Mode."; design m1); labels name the thing or the on-state, no "Enable/Disable/Allow X to"; one help sentence ≤ 90 characters describing the on state; "Mac", "display", "click", "press"; never "monitor" in labels (use "display" or "hardware"); errors say what to do; real ellipsis; "20%", "60 Hz", "15 min" in values; Apple terms table [DS] §4.7 (Display, Virtual display, Picture in Picture, Brightness indicator, Saved layouts, Start automatically, Keep Awake, Display Information, Confirm display changes, Settings). Every visible control has help text or is self-evident by Apple precedent (review item: each `ToggleSetting`/`SliderSetting` without `help:` needs a reviewer note).

**States** (design m8, normative): hardware can't do it → the row is omitted; a precondition is missing → the control is disabled, its help stays, and the reason plus a fix button go in the section footer; empty lists → `EmptyListView` with page-specific copy (§4.3).

**Budget** (r2 definition, design M1): per page with default features and the 1 built-in + 1 DDC external setup, count every visible **setting** (switch, picker, slider, field, glyph tiles, including subordinate rows shown by default) and every **in-form button or navigation row**. Not counted: the page header switch, the status row's actions, the rows inside a list (a list counts as 1), the footer (`Advanced…`, (?)). `PerDisplayPicker` counts toward the total, not toward settings. Experimental and opt-in features are counted only when on by default (so the Displays root doesn't count "Automatically adjust brightness"). Limits: ≤ 8 settings and ≤ 12 counted elements in total; Advanced sheets ≤ 25 controls. Exception, stated in §4.3: the Displays root page is a hub (System Settings › Displays precedent) whose navigation rows exceed the total.

### 4.3 Pages (normative content; V = visible, A = Advanced sheet, S = sub-page, D = Display Details sheet, X = removed/merged)

Every page: `SettingsPageScaffold` → `SettingsPageHeader` → sections → `PageFooterButtons` (trailing `Advanced…` and (?) only). Restore Defaults… lives in the Advanced sheet's footer (leading), or in the page footer (leading) on pages without an Advanced sheet. Keyboard Shortcuts… is a `ButtonRow` in a "Keyboard" section, never a footer button (design M5). No sheet presents another sheet (§1.5); a "…" inside a sheet is a disclosure, a pull-down or a standard alert.

**General** (hero header, no master switch; was 9 pages / ~34 controls)

```
[⚙] General
    Startup, command line, backup, and Safe Mode.
─────────────────────────────────────────────────────
[New: Awake — Keep your Mac awake for a while.     [Turn On Awake] [Not Now]]   (Awake off; once)
[Your display sleep setting moved to Awake.          [Show Awake] [OK]]        (migrated users; once)
─────────────────────────────────────────────────────
Open at login                                       ( )
─────────────────────────────────────────────────────
Command-line control                                ( )
  Lets scripts and other apps control Snaptic with the `snaptic` command.
Copy Install Command
─────────────────────────────────────────────────────
Export Settings…                      Import Settings…
                                            Advanced…  (?)
```

| Section | Control | Where | From |
|---|---|---|---|
| Card | State-dependent (C7, design M3): Awake off → "New: Awake" **Turn On Awake** (turns the module on and opens the Awake page; no ellipsis) / **Not Now**; migrated by M1 → "Your display sleep setting moved to Awake." **Show Awake** (opens Awake) / **OK**; dismissal stored in generalized `newModuleCards` | V once | "New: Displays" card |
| Status row | "Safe Mode is on." [Leave Safe Mode…] while true | V when true | Overview banner |
| Startup | Open at login | V | Startup page (X: a page for one toggle) |
| Command line | Command-line control (help "Lets scripts and other apps control Snaptic with the `snaptic` command.") · Copy Install Command | V | CLI page |
| Backup | Export Settings… (sheet: "Include automatic-session rules (contains app, device and network names)" checkbox, off) · Import Settings… | V | Backup & Reset |
| Advanced | Commands can skip confirmation · exit codes ((i) popover) · Restart in Safe Mode… / Leave Safe Mode (with its explanation) · footer leading: **Reset All Settings…** (destructive, scope "all Snaptic settings"; parity minor 12) | A | CLI page, Safe Mode page (X), Backup & Reset |

The module navigation rows of r1 are removed (they repeated the sidebar; design M1). "Other display apps" moves to Displays › Advanced. About & Licenses → About.

**Menu Bar** (M; N7; graphite tile; was General › Menu with ~28 controls). No Advanced sheet.

```
Window Switcher                    [Show in Snaptic Menu ▾]
   (Always Show only) Icon          [▭] [◫] [⧉]
Displays                           [Show in Snaptic Menu ▾]
   (Always Show / When Active) Icon [▭] [◫] [☀]
Awake                              [Show When Active ▾]
   Time                            [Don't Show ▾]        Time Remaining / End Time
   Icon                            [cup] [eye] [bulb]
⚠ status rows, only when true
─────────────────────────────────────────────────────
Displays menu
Style                              [Standard | Compact]
    Compact shows one slider per display.
Scroll over a slider to adjust it                   (•)
Customize Displays Menu…
─────────────────────────────────────────────────────
Snaptic icon                       [◫] [◩] [◰]
                          Restore Defaults…     (?)
```

| Section | Controls | Where |
|---|---|---|
| Modules (no header, design M5) | One pop-up per module (C2), labelled with the module name, Control Center wording and **one option order for every module**: *Always Show in Menu Bar · Show When Active · Show in Snaptic Menu · ─ · Don't Show*. *Show When Active* is offered for Displays (an external display is connected) and Awake (a session runs), not for the Switcher. Help for Don't Show: "Use the keyboard shortcut or Settings to reach it." Awake's *Don't Show* is disabled until the Keep Awake shortcut is bound; the footer then reads "To hide Awake, first set a Keep Awake shortcut." (parity M2). Under a module with its own icon: its **Icon** glyph tiles (parity B2). Under Awake (Always Show or When Active): **Time** (*Don't Show / Time Remaining / End Time*, default Don't Show) and **Icon** tiles (cup, eye, lightbulb) | V |
| Warnings | 0.2's hidden-icon warnings kept as status rows ("No Snaptic icon is shown…", "The Displays icon only appears while an external display is connected.") | V when true |
| Displays menu | **Style**: Standard / Compact (help "Compact shows one slider per display.") · Scroll over a slider to adjust it · Customize Displays Menu… → sheet (below) | V + sheet |
| Snaptic icon | Glyph tiles (curated, rendered); last, the least-used control (design M5) | V |
| Footer | Restore Defaults… (scope "menu bar settings", leading) · (?) | V |

**Customize Displays Menu…** sheet (M; ≤ 25 controls with lists counted as 1; design m13): **Displays** — one reorderable list of displays with a checkbox each (visible in the menu) and a pinned "Main display" row that can be dragged (replaces "Main display first"), "Use the Default Order"; section order; status badges; header row with one display (kept: a 0.2 setting, design m13 partly rejected). **Menu items** — every item of the §4.8 "0.2 menu" table that has a 0.3 location, grouped by area (Per display, Displays section, Display Tools) with human titles ("Volume", "Input", "Turn Display On or Off", "Extra Brightness", "Rotation", "Saved Layouts", "Night Shift", …), each with a pop-up: *Show* (its §5.2 location) / *In Display Submenu* (per-display items only) / *Hide*; sliders Show/Hide only; custom actions appear under Displays section › Actions with their own rows (the same flag as Automations › "Show in menu"). Items whose feature is off are listed dimmed with "Turn on <feature> in Settings to use this." Footer leading Restore Defaults…. The 0.2 per-display "Header switch" is gone (migration M10, parity M6).

**Window Switcher** (H; header switch "Use Window Switcher"; was 6 pages / ~40 controls)

| Section | Controls | Where | Notes |
|---|---|---|---|
| Status | "Window thumbnails need Screen Recording." [Open Privacy Settings…] while thumbnails are on and the grant is missing (parity minor 3) | V when true | Features permission row |
| Shortcut | Primary shortcut (modifier + key recorder) · **More Shortcuts…** (`ButtonRow` directly under it → sheet: additional switcher shortcuts with their own options, Add/Delete, Gather Windows shortcut; design m12) · Switch when you release the keys (merged from Behavior, design m12) · Show: All windows / Active app / This display (pop-up) · Style: Thumbnails / Icons / List (segmented) · Preview the selected window (subordinate, Thumbnails only; `previewSelected`, parity B2) · Size thumbnails automatically (subordinate, Thumbnails only) + Thumbnail size (SliderSetting 100–300 pt, step 10, default 170, subordinate, shown when automatic is off; fixes C2) | V | primary shortcut's scope/style |
| Windows | Include minimized and hidden windows · Windows from: All Spaces / Current Space / Other Spaces (with Advanced "Windows on other Spaces" off, *Other Spaces* and *All Spaces* are disabled and the footer says "Turn on Windows on other Spaces in Advanced to choose this."; design m12) | V | per-shortcut options of the primary shortcut |
| Advanced | Window thumbnails (feature, Screen Recording footer) · Show on: Display with the active window / Display with the pointer · Window actions (Close, Minimize, Full Screen, Hide, Quit — one checkbox group) · Hover buttons · Select by hovering · Search · ⌘⇥ replaces the app switcher · Pass shortcuts through to apps (+ Only while full screen + app list) · Apps hidden from the switcher (AppListEditor) · Never show thumbnails for (password managers toggle + AppListEditor) · One entry per app · Include apps with no open windows · Windows on other Spaces and Windowless apps feature switches (help "Applies to every shortcut") · footer Restore Defaults… | A (21) | Features page (X), App Lists (X), Privacy (X) |

**Displays** root page (F composes; owners provide sections; header switch "Use Displays"; was 16 pages / ~170–330 controls)

```
[☀] Displays                                       (●)   "Use Displays"
    Brightness, resolution, and arrangement for every display.   2 displays
─────────────────────────────────────────────────────
⚠ status rows, only while true (automation paused · Safe Mode · safety helper stopped)
─────────────────────────────────────────────────────
Display                                      [Display Tools ▾]   section header, trailing (design m14)
[▭ Built-in Retina Display] [▭ DELL U2720Q]                       tiles (hidden with one display)
Brightness              ☀ ━━━━━━●━━━━ ☀  [ 70% ]      (no reset glyph: live value, no default)
─────────────────────────────────────────────────────
Resolution                       [Default — 1512 × 982 ▾]
Refresh rate                                [120 Hz ▾]
▸ Resolution options
    Resolution     ◦━━━━━●━━━━◦  [1512 × 982]         SliderSetting, discrete, onRelease
    [Quick Changes ▾]  [Add to Favorites]             Quick Changes ▾ includes Undo/Redo Resolution Change
    Favorites: 1280 × 800 [Apply] [−] …
─────────────────────────────────────────────────────
Use as                                [Extended display ▾]
Arrange Displays…
Saved Layouts                                    On  ›
─────────────────────────────────────────────────────
Brightness and Dimming                              ›
Color                                          Off  ›
Hardware Controls                               On  ›
Keyboard                                            ›
─────────────────────────────────────────────────────
Virtual Displays                               Off  ›
Picture in Picture                             Off  ›
Automations                                    Off  ›
─────────────────────────────────────────────────────
Display Details…
Display Information                                 ›
                                             Advanced…  (?)
```

| Section | Controls | Owner |
|---|---|---|
| Header | Displays switch; status line ("2 displays") | F |
| Status rows (parity minor 1) | "Display automation is paused." [Resume Display Automation] (B) · "Safe Mode is on." [Leave Safe Mode…] (host) · "The safety helper stopped." [Restart Snaptic] (B) — each only while true | F + B |
| Display | Section header with **Display Tools ▾** trailing (always there, also with one display; design m14): Identify Displays, Redetect Displays, Show Displays Panel, Match Text Size…, Connect All Displays (if `disconnect`), Disconnect All But Main (if `disconnect`), Restore All Displays · `PerDisplayPicker` (hidden with one display; pop-up with > 4) · Brightness (SliderSetting, ☀︎ symbols, full range incl. XDR, `.live`, `defaultValue: nil`; value in nits when Show nits is on) · Automatically adjust brightness (built-in, only when the Experimental `autoBrightness` is on) | F, C |
| Resolution (selected display) | Resolution pop-up (scaled modes, "Default for display" first, favorites marked; with `hiddenModes` a "Show All Resolutions" section) · Refresh rate (if > 1) · HDR (if supported and `hdrToggle`) · Rotation (if `rotation`) · **Resolution options** disclosure (collapsed): resolution slider (SliderSetting, discrete, `.onRelease`), **Quick Changes ▾** (Toggle HiDPI, Native, Default, Native ÷ 2 "Half of native, sharper", Toggle Notch, ─, Undo Resolution Change ⌘Z, Redo Resolution Change ⇧⌘Z; the same two are the Settings window's Edit › Undo/Redo while the Displays page is shown; design M6), Add to / Remove from Favorites, favorites list (Apply, −) | D |
| Arrangement | Use as: Main display / Extended display / Mirror for "X" (pop-up; Apple copy) · Arrange Displays… (sheet: canvas + Snap to edges + keyboard Position/Align form as a disclosure) · Saved Layouts › (with arrangement, design M6) | D |
| Navigation | Group 1: Brightness and Dimming › (renamed so VoiceOver doesn't read "Brightness" twice; design M6) · Color › · Hardware Controls › ("Volume, input, and power for displays that support them.") · Keyboard › — Group 2: Virtual Displays › · Picture in Picture › · Automations ›. Full-width grouped rows; a row shows On/Off only when its sub-page has a feature switch (Brightness and Dimming and Keyboard show none; consistency m14). Always present | F + owners |
| Details | Display Details… (`ButtonRow`) · Display Information › | F |
| Footer | Advanced… · (?) | F |

Height (design M6): about 1,000 pt with every section, so at the default 720 pt the first navigation group starts above the fold on a 14" display; the root page is a scrolling hub by design.

**Display Details…** sheet (per selected display; F + B + D; no nested sheets):

| Group | Controls |
|---|---|
| Identity | Name (field + Use the System Name) · Icon (glyph tiles) · **Customize Displays Menu…** link (design m2): closes the sheet and opens Menu Bar › Customize Displays Menu with this display selected (parity M6; per-display visibility lives only there) |
| Connection (D; design M9) | Disconnect / Connect (if `disconnect`) · Never disconnect automatically (built-in, if `autoDisconnectBuiltin`) · **This display doesn't support hardware controls** (allow auto-disconnect without a power reading; design m2) · Underscan (Experimental, SliderSetting `.onRelease` with the confirmation; replaces the draft + Apply) |
| Menu bar overlays (C) | Black strip behind the menu bar · Top / bottom corner radius (if `menuBarOverlays`) |
| Match text size (D; if `scaleMatch`) | Disclosure: Include this display · Reference display · Match tolerance · Preview / Apply |
| Manage | Copy Settings From ▾ (pull-down, design M4) · Forget Remembered Resolution · Forget This Display… (standard alert) |
| Information | Disclosure: transport, masked serial, EDID Copy Hex / Copy Base64 (EDID **Export…** lives on Display Information, so no file panel opens over this sheet; design m6) |

**Displays › Advanced** sheet (F composes; cross-cutting groups only, 25 controls, design M9):
1. **Use Snaptic for** (feature switches, plain words, only for features without their own sub-page switch): Brightness control, Resolution control, Arrangement and mirroring, Rotation, Keyboard shortcuts, Brightness indicator, Disconnect displays (Beta). (F; replaces Features page; Hardware controls, Color, Saved layouts, Virtual displays and Picture in Picture keep their switch on their sub-page only)
2. **Confirm display changes** (B; was Safety page): Confirm resolution changes (one picker, one label set), Revert after N s (StepperSetting 5–60), Tell me when displays were restored, Restore All Displays shortcut (one `ShortcutSetting` over two fields, consistency M5: recording sets `panicHotkey` (custom combo, tried first; the fixed default and fallback ⌃⌥⌘⇧⎋ stay behind it exactly as in 0.2); "Use Default" sets `panicHotkey = nil` and shows "Default (⌃⌥⌘⎋)"; Clear sets `panicHotkeyEnabled = false` with its 0.2 meaning (no shortcut at all, help warns); no data migration), Allowed without asking (the single list); Resume Automation as a status row action while paused.
3. **Other display apps** (A): Pause overlapping features / Run both (radio).
4. **Resolution filters** (D): Offer modes below 720p · Remember my choice · Only native aspect ratio on the slider · Show values as · Snap to favorites · "Filters for <display>" disclosure (DPI filter, width limits, refresh filters).
5. **Experimental** (F lists, owners implement): HDR switch, Underscan, Built-in auto-brightness, Brightness broadcast (`osdBroadcast`, + notification name), Show all resolutions (`hiddenModes`) — each with an Experimental badge and one help line.
6. **Permissions** (parity minor 4): the 0.2 Features-page permission rows become this group's footer status ("Some features need Accessibility." [Open Accessibility Settings…]) and the Permissions page rows. Night Shift and Apple display presets move to Color › Advanced, HDR virtual modes to Virtual Displays › Advanced (owners keep their switches next to their settings).
Footer: Restore Defaults… (scope "Displays settings") · Done.

Sub-pages (each: `SettingsPageHeader` with the feature-group switch where one exists, own Advanced… when needed):

| Sub-page | Switch (features) | Visible | Advanced / removed |
|---|---|---|---|
| Brightness and Dimming (C; route id `displays.brightness`) | — | `PerDisplayPicker` for the per-display rows (parity minor 2) · Restore brightness at login and wake (pop-up incl. Off = `brightnessRestore`) · Smooth transitions · Sync brightness (switch `sync`; source, follow, offset for the selected display as subordinate rows) · Extra brightness (switch `xdr`, Beta, XDR displays only; "Maximum extra brightness" for the selected display + "Pause below battery" SliderSettings subordinate) · Dim when the screen locks (switch `dimOnLock`; level slider subordinate) · Dim all the way to black (`dimToBlack`; design m2) · Show brightness in nits (`nits`; single field, duplicate 3) | A: **Brightness methods** (Apple native / DDC / Color table / Overlay checkboxes, per-display "Use" picker with "Now using …", custom switchover + slider, minimum hardware level, XDR method, color-table check "Ask Again"; moved from root Advanced, design M9), custom nits range fields, Stop at 100% detent, XDR default maximum, XDR "Pause in Low Power Mode", XDR Test, sync "Follow outside changes" |
| Color (C) | Color adjustments (`color`) | Display tiles · Software contrast, Gamma, Temperature, Black level, White level (5 SliderSettings) · Invert colors · Adjust this display (on = not suspended; design m2) · Color profile (pop-up, `colorProfiles`) · Apple display preset (pop-up, when `applePresets` is on) | A: Color profiles switch (`colorProfiles`), Gain, per-channel RGB gain and gamma (6), profile actions pull-down (Show in Finder, Open in ColorSync Utility, Restore Previous), keep color-table dimming with custom profiles, suspend on all displays, shortcut step sizes, **Night Shift** (Experimental switch + "Night Shift warmth"), **Apple display presets** (Experimental switch); footer Restore Defaults… asks "This display / All displays" (replaces "Reset This Display") |
| Hardware Controls (C) | Hardware controls (`ddcControls`) | External display tiles · Use hardware controls for this display · Volume (`.live`) + Mute · Hardware contrast (`.live`) · Input (pop-up, if `ddcInput`) · Turn Off / Turn On (if `ddcPower`) · custom control sliders (if any are defined) | A: Input switching (`ddcInput`) and Power control (`ddcPower`) switches, read back values + interval, re-send after wake, per-control tuning as **disclosure rows** (raw 0/100%, invert, show in menu, read-back interval; no per-control sheet), input list editor, standby value, custom controls editor (`ddcCustom`), raw VCP get/set + unlock (disclosure), timing (reply delay, retries, write twice, ignore checksums, Forget Learned Framing), "Hardware information" (status, connection, framing, writes today, model, MCCS, supported codes; Read Capabilities, Check Connection) |
| Keyboard (C) | — | Brightness keys (switch `brightnessKeys`; "Change: display under the pointer / main / all" pop-up) · Volume keys (switch `volumeKeys`; target pop-up) · Brightness and volume indicator (pop-up incl. "Use the system indicator" on 14/15; design m2) · Indicator position · Keyboard Shortcuts… (`ButtonRow` → sheet: **one grouped list** of all Displays actions — Brightness, Volume & contrast, Resolution (incl. favorites), Arrangement, Tools (Show Displays Panel, Identify, Redetect, Restore All Displays, Resume, Display Information, Stop Picture in Picture streams), custom actions — with filter field) | A: also let macOS handle brightness / volume / mute keys, steps / fine steps (StepperSetting), F14/F15, per-display "keys change this display", show volume indicator per display, sound output name, input slots, indicator "show on", show value, Preview Indicator; Modifiers reference → (i) popover |
| Saved Layouts (D) | Saved layouts (`layouts`) | Save Current Layout… · list (name, Matches badge, Apply, Details… sheet: apply automatically, priority, Trusted / Stop Trusting, Update to Current, Delete; drag or ▲▼ to reorder) · Protect the current arrangement (switch `protection`) | A: protected fields (5 checkboxes), Update Protected State to Current, Offer Undo after automatic apply, Forget All… |
| Virtual Displays (D) | Virtual displays (`virtualScreens`, Beta) | List (Connected switch, Details…) · New Virtual Display… (sheet with shape picker + recipes as tiles) · Sharper text on this display (Smart HiDPI, switch per display, Beta) | A: Sharper text switch (`smartHiDPI`, Beta), behavior toggles (3), "All Virtual Displays ▾" pull-down (Connect, Disconnect, Reconnect, Disassociate, Discard…), Smart HiDPI size and HDR (PQ), **HDR virtual modes** (Experimental switch); the Details sheet replaces the inline editor, "Sizes" becomes a table with + / − |
| Picture in Picture (E) | Picture in Picture (`pip`) | Screen Recording status row · Running list (Pause/Show/Stop; Crop in the row menu; Stop All in the section header) · Saved PIPs list (Start, Edit…) · New PIP… / New Stream… · Import Color Lookup Table… (`ButtonRow`, opens its file panel on the Settings window, never over a sheet; design m6) | Editor = sheet (name, show as, stream onto, window, capture, orientation, full screen, filters `pipFilters` sections); A: Filters switch (`pipFilters`), Never capture these apps (AppListEditor + Restore Defaults), pause covered PIPs, "⌃⌥⌘P stops streams" switch (shortcut in Keyboard Shortcuts) |
| Automations (A) | Section switches: Event hooks (`hooks`), Custom actions (`customActions`) | Hooks list (Enabled, When, Details… sheet) + Add Hook… · Actions list (Show in menu, Details… sheet with Run Now) + Add Action… | Sheets bind directly to config (fixes B2); action shortcuts also listed in Keyboard Shortcuts… |
| Display Information (F; design M4) | — | Live report (refreshes on change, no Refresh button) · Copy Report · Export… · EDID Export… for the selected display (moved from Display Details, design m6) · safety-helper status rows · pending confirmation · undo journal · **Unavailable on this Mac** (user titles, never camelCase) · **Remembered displays** (Forget… per row, Forget All…; parity B2) · Remembered resolutions (Forget per row) | — |

**Empty states** (design m9): Hardware Controls "Connect a display that supports hardware controls." · Saved Layouts "Save your current arrangement to restore it later." · Virtual Displays "Create a display that exists only in software." · Picture in Picture "Show a live view of any window or display." · Automations "Run a program when displays change." **File panels** are never presented on a sheet (design m6): Export Settings… closes its options sheet, then shows the save panel on the Settings window; Import Settings… is a page button.

**Awake** (G; header switch, AX label/tooltip "Use Awake"; no second help line in the header, the confirmation alert carries that text; design B1, M7, parity M7)

```
[☕] Awake                                           (●)   "Use Awake"
     Keep your Mac awake for a while, or automatically
     when certain conditions are met.
──────────────────────────────────────────────────
Your Mac can sleep as usual.                   [Keep Awake]
  active: Keeping your Mac awake until 3:45 PM   [Options ▾] [Turn Off]
          1h 12m left · Appearing active                   (detail; no "Started from the menu")
  after a non-user end (12 h): Ended at 3:12 AM: battery below 20%.
  paused: Automatic sessions are paused until 4:00 PM.     [Resume]
──────────────────────────────────────────────────
Default duration                       [Until Turned Off ▾]
Keep the display on                                   (•)
  When off, your Mac stays awake but the display can turn off.
Durations in the menu                              [Edit…]
──────────────────────────────────────────────────
End sessions automatically                                 (laptops only)
When the battery is low                               (•)
    Battery level       ━━━━●━━━━━  [ 20% ] ↺
When the power adapter is disconnected                ( )
──────────────────────────────────────────────────
Start automatically
Desk dock                                      Active  ›   rule rows (list)
  While “DELL U2720Q” is connected
[Add Rule…]
   none yet: "Keep your Mac awake automatically, for example while a display is connected."
──────────────────────────────────────────────────
Keyboard Shortcuts…
Drives                                            Off  ›
History                                  Today 2h 10m  ›
footer: Choose where Awake appears in Menu Bar settings.  (link)      Advanced…  (?)
```

| Section | Controls | Where |
|---|---|---|
| Status | Status row (reaches everything when the status item is hidden, 26/27). Idle: "Your Mac can sleep as usual." + **Keep Awake** (default preset; design M7). Active: "Keeping your Mac awake until 3:45 PM" / "…until downloads and tasks finish" / "…while a command-line hold lasts" / "…while “Desk dock” applies" + detail ("1h 12m left", plus "Appearing active" / "Moving the pointer" / "Stopped appearing active after 1 hour." while relevant) + **Options ▾** (Add 15 Minutes, Add 1 Hour, Add Time… for timed and capped kinds; ─; ✓ Keep Display On, always while active; parity M4) + **Turn Off**. Last non-user end for 12 h. While paused: "Automatic sessions are paused until 4:00 PM." [Resume] (design M4). Buttons only, no switch (N5) | V |
| Durations | Default duration (pop-up of presets; sets `defaultPresetID`) · Keep the display on (edits `defaultOptions.display`; a running session that uses default options follows it at once; help "When off, your Mac stays awake but the display can turn off." plus, for task kinds, "Download and app sessions let the display turn off unless set in Durations."; parity M4, M5, minor 9) · Durations in the menu: Edit… (preset sheet) | V |
| End sessions automatically | When the battery is low (switch) + Battery level (SliderSetting 5–50%, step 5, default 20, subordinate; design M7: "Below" was a fragment) · When the power adapter is disconnected; footer "Sessions always end below 5% battery or if your Mac gets very hot." | V (laptops only) |
| Start automatically (design M4) | No section switch: **Add Rule…** turns `triggers` on with the first rule. Rule rows (`ReorderableList`): name, `TriggerEngine.summary` subtitle, trailing "Active" / "Waiting" / "Off", chevron; click or Return opens `TriggerEditorSheet`; drag or VoiceOver Move Up/Down to reorder (help "Higher in the list wins."). Empty: the help line + Add Rule…. Pause lives in the menu and the hotkey only (parity minor 10) | V |
| Keyboard | Keyboard Shortcuts… (sheet: Keep Awake, Keep Display On, Start “<preset name>” ×4 (design m2), Pause automatic sessions) | V |
| Navigation | Drives › (J) · History › (G). r2's "Menu bar icon ›" row is gone (a chevron must push, design M7); the page footer carries "Choose where Awake appears in Menu Bar settings." as a link | V |
| Footer | link · Advanced… · (?) | V |
| Advanced (11) | Activity: **Appear active** (`activity`; switch semantics §2.14; help "Keeps apps from marking you as away while a session runs.") · **Move the pointer slightly** (Experimental `pointerNudge`; help "Moves the pointer 1 point and back. Only for sessions you start in Snaptic. Needs Accessibility."; Accessibility footer + fix button) · **Stop appearing active after** (1 / 2 / 4 / 8 hours, default 1 hour; help "Counts from when the session starts appearing active."; design m2 partly rejected: "when inactive" would describe system idle, which the cap no longer uses, N10). End sessions automatically: When your Mac sleeps · When you switch users (Immediately / After 1 Hour / Never) · When Low Power Mode turns on · After the screen has been locked for (Never / 1 / 4 / 12 hours). Display: Keep the display on while locked (C1). Restart: Continue sessions after Snaptic restarts · Start a session when Snaptic opens (pop-up of presets / None). **Other apps keeping your Mac awake** (inline live section, design M4: process names and assertion types, a warning row when system-wide `SleepDisabled` is on — "Sleep is turned off for this Mac by another app or command. Snaptic can't change this."; empty "No other apps are keeping your Mac awake."). Footer leading Restore Defaults… (scope "Awake settings"; keeps history; turns pointer movement and Drive Alive off) | A |

**Turn-off confirmation** (the only copy of this text; §2.12 refers here, consistency m5): turning the header switch off while a session or an enabled rule exists asks "Turn off Awake? This ends the current session and stops automatic sessions." [Turn Off] [Cancel] (parity M7).

Durations sheet (`PresetEditorSheet`): `ReorderableList` of presets with + / − and Edit/Delete/Move VoiceOver actions; each row has an **Options** disclosure: name, kind (Until turned off / For a duration (h, m NumberFields) / Until a time (time picker) / Until downloads and tasks finish, with **At most** (No limit / 1 / 2 / 4 / 8 / 12 hours; parity minor 6) and a "Thresholds" disclosure: top process, total CPU, disk, network, quiet for), Display (*Default (<per-kind default>)* via `defaultDisplayPolicy(for:)`, e.g. "Default (Keep on)" or "Default (Can turn off)"; consistency m6 / Keep on / Can turn off / Keep on until idle for [n min]), Activity (*Default* / Off / Appear active / Move the pointer slightly; only when `activity` is effective). The page pop-up chooses the default (no ★).

Custom session panel (`CustomSessionPanel`, menu "Custom…"): For | Until | While an App Is Running; h/m fields, a time picker or an app pop-up; **At most** pop-up for the app kind (parity minor 6); Return = Start; ⌥ "Add Time…" opens it in extend mode.

Rule editor sheet (`TriggerEditorSheet`, parity minor 5, design M4): **On** switch · Name · **Conditions**: "Start when [All ▾ / Any ▾] of these conditions are met" + a list of condition rows, each "[kind ▾] [is ▾ / is not ▾] [kind-specific fields]" with + / − (1…8 rows; + disabled at 8; the router kind is titled **"Connected to this network"**) · Session options (Display, Activity) · "Wait before starting" / "Wait before ending" (start/end delays) under a Timing disclosure · **After I turn it off**: [Resume when the conditions are next met ▾ / Resume after 15 min / 1 hour / 4 hours] (`resumeAfterManualEndMinutes`; Amphetamine re-activation parity) · footer leading **Delete Rule…** (standard alert) · Cancel / Done.

**Drives** (J, sub-page of Awake): header switch "Keep drives awake" (`driveAlive`) · eligible volumes list with switches (turning one on performs the first write, so the Removable Volumes prompt follows the click) and per-row status ("Can't keep this drive awake: …") · **Check drives every** (SliderSetting 30–600 s, default 120; design m2) · **Also when no session is running** (design m2). Empty: "Connect an external drive to keep it from spinning down."

**History** (G, sub-page): totals row (Today, Last 7 days) · list (Start Again in the row menu, hidden for `process` and `automatic` entries; parity minor 12; app sessions use their locally stored bundle id) · Clear History…. Empty: `ContentUnavailableView("No Sessions Yet", systemImage: "cup.and.saucer")`.

**Permissions** (H): Accessibility and Screen Recording rows (state, "Needed by …", Open Settings, Show Snaptic in Finder, relaunch), Removable Volumes info row when Drive Alive is on ("macOS asks the first time Snaptic writes to a drive"), signer line (R5.7).

**About** (H): app icon, version, Check for Updates…, Acknowledgements… (sheet with MIT text and credits), **Display Information…** when Displays runs (says where it goes, design m14) or **Diagnostics Report…** (a host report sheet) when it doesn't.

**Counts** (r3; rule in §4.2; 1 built-in + 1 DDC external, default features, built-in selected; display tiles count toward the total only; consistency m14):

| Page | Settings | Buttons + nav rows + tiles | Total | Notes |
|---|---|---|---|---|
| General | 2 | 3 | 5 | card not counted (one-time) |
| Menu Bar | 8 | 1 | 9 | 3 presence pop-ups, Awake Time + Icon, Style, scroll, Snaptic tiles; Customize… |
| Window Switcher | 8 | 1 | 9 | shortcut, release, show, style, preview, auto size, minimized, Spaces; More Shortcuts… |
| Displays root | 4 | 1 tiles + 3 + 9 nav | 17 | brightness, resolution, refresh, use as; Display Tools ▾, Arrange…, Display Details…; hub exception (without nav rows 8) |
| Brightness and Dimming | 7 | 1 tiles | 8 | restore, smooth, sync, xdr (XDR only; 6 without), dim on lock, dim to black, nits |
| Color | 8 | 1 tiles | 9 | |
| Hardware Controls | 5 | 1 tiles + 1 | 7 | external only |
| Keyboard | 6 | 1 | 7 | |
| Saved Layouts / Virtual / PIP / Automations | 1 / 1 / 0 / 2 | 2 / 2 / 5 / 4 | 3 / 3 / 5 / 6 | lists count 1 |
| Awake | 5 | 5 + 1 list | 11 | default duration, keep display on, battery low + level, adapter; Edit…, Add Rule…, Keyboard Shortcuts…, Drives, History, rule list; desktop: 2 settings, 8 total |
| Advanced sheets | — | — | General 4, Switcher 21, Displays 25, Brightness 20, Color 15, Hardware 18, Keyboard 14, Awake 11 | ≤ 25 each |

Default-visible settings across the five root pages ≈ 30, ≈ 60 including sub-pages (was ≈ 245).

### 4.4 Duplicates ([UA] §2.4) — one owner each

| # | Duplicate | Resolution |
|---|---|---|
| 1 | Confirm resolution changes (Resolution + Safety) | Displays › Advanced › Confirm display changes only; one label set |
| 2 | Allowed without asking (DDC + Safety) | Displays › Advanced › Confirm display changes only |
| 3 | Show nits (`brightness.showNits` + `keys.osdShowNits`) | One control `brightness.showNits` (migration M5) on Brightness |
| 4 | Display order/visibility (Names + Menu) | Menu Bar › Customize Displays Menu… only; Display Details has a "Customize Displays Menu…" link, not a control (parity M6) |
| 5 | Panel/Identify shortcuts (`menu.*Shortcut` + `keys.shortcuts`) | `keys.shortcuts` only (migration M4); Keyboard › Keyboard Shortcuts… |
| 6 | Feature on/off on two pages + 4 "is off" variants | Feature switch where used; one `SettingsPageHeader` switch / `ToggleSetting`; `FeatureHighlights` for off state |
| 7 | Live controls on 4 surfaces, different ranges | One `DisplayLiveControls` model (F) with the full range, used by root page, menu and panel; sub-pages keep only settings, never a second copy of a live slider |
| 8 | Contrast software vs hardware | Labels "Software contrast" (Color) and "Hardware contrast" (Hardware Controls) |
| 9 | Temperature vs Night Shift warmth | Night Shift in Color › Advanced (Experimental) with its own label "Night Shift warmth" |
| 10 | Capture privacy Switcher vs PIP | Kept separate (different scopes), renamed "Never show thumbnails for" / "Never capture these apps", both `AppListEditor` |
| 11 | Switcher per-shortcut vs feature switches | Primary shortcut options visible; feature switches in Advanced with help "Applies to every shortcut" |
| 12 | Volume OSD (Keys + OSD page) | Keyboard page only (OSD page X) |
| 13 | Menu settings inside Displays pages | All on Menu Bar page (N7) |
| 14 | Restore All Displays in 4 places, fixed shortcut | Menu Display Tools, panel, root page Display Tools ▾ (all actions); shortcut editable in one place (Displays › Advanced › Confirm display changes, mirrored in the Keyboard Shortcuts list) |
| 15 | Awake "on" twice (module switch vs session switch, parity M7 / design B1) | Header switch = module ("Use Awake"); sessions = buttons (Keep Awake / Options ▾ / Turn Off) in Settings, native items + a mouse switch in the menu |
| 16 | Awake icon off in three places (`indicator`, style `.hidden`, `ownItem`; parity M1) | `MenuPresence` only; `.hidden` style deleted; `indicator` is an internal capability |
| 17 | Rules on/off in three places (section switch, row switches, Pause; design M4) | One switch per rule, inside its editor sheet; Pause in the menu and hotkey; the status row shows a paused state with Resume |

### 4.5 Live-update architecture (fixes [UA] §1 at the source)

| Change | Owner | Fixes |
|---|---|---|
| `DisplayRuntime` gains `@Published brightnessPosition: Double?` (full range incl. XDR), `brightnessRange: ClosedRange<Double>`, `contrastRange`, `volumeRange`; BrightnessService/DDCController write only through these; pages never read `BrightnessService.states` | lead (type), C (writers) | A1, A2, overview 0…1 range |
| Per-display sections are subviews with `@ObservedObject var live: DisplayRuntime` (the `DisplayControlsCard` pattern) | page owners | A1, A2 |
| **Per-controller revision objects** (code M12): `DisplaysRuntimeState.revision(_ id: DisplayControllerID) -> ControllerRevision`, one `ObservableObject` per id with `@Published private(set) var count: UInt64`; `bump()` coalesced with `DispatchQueue.main.async` (runs during menu tracking, N15) to one publish per turn per id, ≤ 15 Hz **trailing-edge** (the last bump in a window always publishes; code R2-M7); a section observes only the ids it shows. Controllers bump when page-visible state changes (rotation/HDR/underscan, protection, layouts, virtual live/busy, Smart HiDPI pairs, undo/redo/favorites, Night Shift, guard status, capture sessions) | lead (type), B/C/D/E (bumps) | A4, A6–A11; delete the `objectWillChange.send()` pokes and Safety's 2 s timer (lint L7) |
| **Config slices** (code M12): `ConfigSlice<T, V>` (lead, `Core/ConfigSlice.swift`) publishes only when `store.value[keyPath:]` changes; a view owns it as `@StateObject` (or reads one cached in the environment), never creates it in `body` (code minor 6); every new section reads config through a slice of its own `DisplaysConfigSection`. `DisplaysPageEnvironment` keeps forwarding the config store's `objectWillChange` until the **step-3 exit**, so the 23 legacy page files still re-render on writes; the lead removes the forwarding (it then forwards only `displays`, `effectiveFeatures`, `availability`, `moduleState`, panic flags) once every page uses slices (code R2-M2b) | lead (type), page owners | a 15 Hz slider commit re-renders one section, not the whole Displays tree |
| **Live hardware path** (code M12): `DisplayLiveControlling` (lead protocol, C implements) is the only route from a `.live` slider to hardware; a latest-wins mailbox per (display, control), DDC writes ≤ 20 Hz, `phase: .ended` always delivered; the slider shows `drag ?? live value`; on `.ended` C sets `DisplayRuntime`'s value to the target optimistically and ignores readbacks that differ for 1 s, so the slider doesn't snap back (code minor 7) | lead, C, H | "laggy drags", fights between readback and drag |
| No `@State(initialValue:)` copies of model values; editors bind to the store or resync with `.onChange(of:)` | owners of ShortcutEditor (H), Hook/Action/CommandEditor (A), NameField (F), CustomSliderRow (C, seeded from `ddc.lastReading`) | A3, B1–B3 |
| `SliderSetting` drag-local state: `@State drag: Double?`; shows `drag ?? value`; commit per `SliderCommit`; final value on release; `preview` for live hardware feedback without config writes | H | C1 "laggy drags" |
| Config fan-out by section: Kit `DisplaysConfig.changedSections(old:new:) -> Set<DisplaysConfigSection>` (cases below, with `perDisplay` split per subsection incl. `perDisplayKeys` and `perDisplayPIP`; consistency m8); `DisplayFeatureController` gains `static var observedSections: Set<DisplaysConfigSection>` **declared in the protocol body** with a protocol-extension default of `allCases` (a requirement, so `type(of: c).observedSections` dispatches to a conformer's narrower set; an extension-only member would always return the default; code sig), so the ~21 conformers compile at step 0; `DisplaysModule.configChanged` notifies only controllers whose sections changed; `ColorController` re-applies gamma only for displays whose `perDisplay.color` changed | lead (+ every controller narrows its sections in step 2) | C1 fan-out, gamma reapply per tick |
| `ManagementBindings.perDisplay` and other binding helpers stop calling `sanitized()` per tick (ConfigStore sanitizes on load and external change; UI ranges are already clamped); binding helpers collapse to `SettingsBinding` (H) | H + D | C1 |
| Switcher `AppSettings` saves through a 250 ms debounce like `ConfigStore` | A | C2 |
| `MenuSliderRow` (M, AppKit) replaces `MenuSliderItem` for brightness, volume, contrast, custom DDC and (opt-in, top level only) resolution sliders: value label, `range` in init, `bind(to:)` so values follow live changes while the menu is open (subscribed with `.receive(on: DispatchQueue.main)`, never `RunLoop.main`, N15); never fights a drag. No slider is ever in a submenu | M (+ C, D contributors adopt) | M1 |

```swift
// Core/ConfigSlice.swift (lead)
@MainActor final class ConfigSlice<T: ConfigModel, V: Equatable>: ObservableObject {
    @Published private(set) var value: V
    init(_ store: ConfigStore<T>, _ keyPath: KeyPath<T, V>)
}
// Displays/DisplaysContracts.swift (lead)
@MainActor final class ControllerRevision: ObservableObject {
    @Published private(set) var count: UInt64 = 0
    func bump()                                    // coalesced per main-queue turn
}
enum LiveControl: Hashable { case brightness, contrast, volume, custom(UInt8) }
enum DragPhase { case began, changed, ended }
@MainActor protocol DisplayLiveControlling: AnyObject {
    func set(_ control: LiveControl, _ value: Double, for display: DisplayKey, phase: DragPhase)
}
// In `protocol DisplayFeatureController { … }` itself (requirement):  static var observedSections: Set<DisplaysConfigSection> { get }
extension DisplayFeatureController { static var observedSections: Set<DisplaysConfigSection> { Set(DisplaysConfigSection.allCases) } }

// SnapticKit/Config/ConfigDisplays.swift (lead; consistency M7): one case per DisplaysConfig field, per-display split
package enum DisplaysConfigSection: String, CaseIterable, Sendable {
    case features, brightness, ddc, keys, color, resolution, virtualScreens, management, layouts, pip, automation,
         safety, identity, menu, migrations
    case perDisplayBrightness, perDisplayDDC, perDisplayKeys, perDisplayColor, perDisplayResolution,
         perDisplayManagement, perDisplayIdentity, perDisplayPIP
}
/// Page Restore Defaults scopes (consistency M7). `.all` = Displays › Advanced; others = that sub-page's Advanced.
package enum DisplaysRestoreScope: Equatable, Sendable {
    case all, brightness, color(DisplayKey?), hardware, keyboard, layouts, virtualDisplays, pip, automations, confirm
}   // color(nil) = all displays, color(key) = "This display"
// DisplaysConfig: package func restoringDefaults(scope: DisplaysRestoreScope) -> DisplaysConfig
```

Rule (lint + review): a Settings view may read controller state only inside a view that observes the relevant `ControllerRevision` or `DisplayRuntime`.

### 4.6 Config migration (no setting lost)

All migrations are pure Kit functions with tests. **Each runs once**: the containing model gets a lossy `migrations: [String]` marker list (`DisplaysConfig`, `ModulesConfig`, `AwakeConfig`), a migration records its id after running, and never runs again (code M3; a later user "off" sticks). **Legacy fields stay declared, decoded and encoded until 0.4** (struct Codable drops undeclared keys; only `LossyMap` keeps unknown ones), so a downgrade to 0.2 still reads them. Old-key removal is a 0.4 task.

| # | From | To | Where |
|---|---|---|---|
| M1 | `DisplaysConfig.features.sleepPrevention` + `perDisplay.*.management.preventSleep` (+ that display's `identity.fingerprint`, `customName`/`lastKnownName`), read from raw JSON | Awake rules "While a display is connected" (`.any` over `display(.specific)`, options `.keepOn`), **at most 8 displays per rule** (more → "… (2)", "… (3)"), rule ids derived deterministically from the display keys (`StableID` = "m1." + SHA-256 prefix of the sorted keys; code minor 9) so a re-run can't duplicate; enabled iff 0.2 sleep prevention was **effective**: Displays module enabled ∧ feature on ∧ ≥ 1 display flagged (parity "Also"); if enabled, Awake module (presence `.ownIconWhenActive`) and `triggers` turned on, `newModuleCards` gains `"awake.migrated"` (the General card) and the first activation of a migrated rule shows the toast "Keeping your Mac awake while “DELL U2720Q” is connected is now part of Awake." [Show in Settings] once (then marker `fromDisplays.toast` is recorded; design M3); marker `fromDisplays.v1`; afterwards `save(force: true)` on the **modules store first and the Awake store last** (its marker is the commit point; code minor 9) | Kit `AwakeMigration.fromDisplays(rawJSON:modulesEnabled:) -> AwakeMigrationResult` (G), run by `ModuleHost` after the Awake-disabled insertion (§2.13) and before modules start (lead) |
| M2 | `ModulePreferences.placement` (`shared/ownIcon/hidden`) + Displays `hideWithoutExternalDisplay` | `presence: MenuPresence`: `shared` → `.inSnapticMenu`, `hidden` → `.hidden`, `ownIcon` → `.ownIcon`, except Displays `ownIcon` + `hideWithoutExternalDisplay` → `.ownIconWhenActive` (design M5). `placement` and `hideWithoutExternalDisplay` keep being **written** from presence (`.ownIconWhenActive` → `.ownIcon` + hide flag for Displays, `.ownIcon` for Awake) so 0.2 reads them. When `presence` is absent but `placement` exists (0.3 → 0.2 → 0.3 round trip), Awake's `.ownIcon` decodes as `.ownIconWhenActive`, its default (code minor 9). `ModulePreferences.init(enabled:placement:…)` stays beside the new `init(enabled:presence:…)` until the step-3 exit (code sig) | `ConfigModules` decode (lead) |
| M3 | `ModulesConfig.showNewDisplaysCard` | `newModuleCards: [String]` decoded as strings and filtered to known `ModuleID`s (a `Set<ModuleID>` would fail as a whole on one unknown id) | lead |
| M4 | `MenuConfig.showPanelShortcut`, `identifyShortcut` | `keys.shortcuts[DisplayActionID.fShowPanel]` (`"f.showPanel"`) and `[.fIdentify]` (`"f.identify"`), Kit constants in `KitModules.swift` (consistency M4), when those are unset; marker `menuShortcuts.v1`; legacy fields kept and encoded | `DisplaysConfig.init(from:)` post-decode (lead) |
| M5 | `keys.osdShowNits` (default false) | once: if `keys.osdShowNits` is true, set `brightness.showNits = true` (default true); otherwise leave it. r1 re-ran the OR on every decode, so a user's later "off" came back at the next launch (code M3); marker `showNits.v1` | `DisplaysConfig` post-decode (lead) |
| M6 | `SafetyConfig.panicHotkey` / `panicHotkeyEnabled` | **No data migration** (consistency M5): the UI edits the existing fields with their 0.2 meanings (§4.3 Confirm display changes); a `SafetyConfig` test pins that nil keeps "default + fallback" and `false` disables all | B (step 2) |
| M10 | Per-display `management.powerSwitch` (Header switch: None / Connect-Disconnect / DDC standby) | once: any display with `.connect` → `menu.itemVisibility[d.disconnectItem] = .visible` (top-level "Disconnect" under that display's row); any with `.ddcStandby` → `[c.ddc.power] = .visible`; the field stays decoded and encoded, unused (parity M6); marker `powerSwitch.v1` | `DisplaysConfig` post-decode (lead) |
| M7 | Switcher features `otherSpaces`/`windowlessApps` vs per-shortcut flags | unchanged storage; UI only | — |
| M8 | Raw feature flags of features without a switch in the new UI | unchanged; each still reachable (§4.8) | — |
| M9 | Awake indicator legacy values (r1 drafts never shipped) | none needed; `AwakeIndicatorConfig.sanitized()` maps unknown glyphs to `.cup` | — |

```swift
// SnapticKit/AwakeMigration.swift (G; consistency M7)
package struct AwakeMigrationResult: Equatable, Sendable {
    package var triggers: [AwakeTrigger]      // empty when nothing to migrate
    package var enableModule: Bool            // 0.2 sleep prevention was effective
    package var migratedDisplayNames: [String]   // ≤ 8, for the one-time toast; local UI only
    package init(triggers: [AwakeTrigger], enableModule: Bool, migratedDisplayNames: [String])
    package static let nothing: AwakeMigrationResult
        = AwakeMigrationResult(triggers: [], enableModule: false, migratedDisplayNames: [])
}
package enum AwakeMigration {
    package static func fromDisplays(rawJSON: Data?, modulesEnabled: Set<ModuleID>) -> AwakeMigrationResult
}
```
**Round trip 0.3 → 0.2 → 0.3** (code minor 9, documented in the README's downgrade note): 0.2 doesn't encode `migrations`, so the marker-guarded M4, M5 and M10 run again after an upgrade back; each is idempotent on unchanged data and only fills unset values, so a value the user changed in 0.2 wins. Awake's stores are untouched by 0.2 (it doesn't know the keys).

Page **Restore Defaults…** resets only that page's scope through Kit functions (`AwakeConfig.restoringDefaults()`, `DisplaysConfig.restoringDefaults(scope: DisplaysRestoreScope)`, `MenuConfig()` etc.), each tested to leave other scopes, salts and history untouched and to turn pointer movement and Drive Alive volumes **off** (security L6). `AwakeConfig.restoringDefaults()` is written by G in step 2 (it needs G's and J's fields; code M14); step 0 has a stub returning `AwakeConfig()`.

### 4.7 Onboarding (H)

Welcome → Choose modules (3 rows with switches and one-line descriptions; Awake preselected for fresh installs; the Awake row's description ends "Its icon appears while your Mac is being kept awake."; design m11) → Displays chips (existing; summary lists **user words**, not feature ids; chips are toggles; includes the 0.2 chips **"Hide the menu-bar icon"** → Displays presence Don't Show, and **"Turn on Sharper Text"** → `smartHiDPI`; parity minor 3) → Permissions (only what was chosen) → Done. r2's Awake quick-setup step is dropped (it repeated two page controls; design m11), so no `OnboardingStep.awake` case is added (code minor 13, consistency m11 moot). One primary button, always in the window footer ("Continue" / "Done"); the in-form "Use These Features" button is removed.

### 4.8 0.2 → 0.3 control map (normative; parity B2)

One row per 0.2 control in [UA] §2.2 and §3.2 (identical per-display or per-item controls share a row). Destinations: **V** visible on the named page, **A** that page's Advanced sheet, **S** sub-page, **D** Display Details sheet, **K** a Keyboard Shortcuts sheet, **C** Customize Displays Menu sheet, **I** Displays › Display Information, **M** menu, **X** removed (reason given), **Exp** the page's Experimental group (kept; consistency m7). Pages: Gen = General, MB = Menu Bar, Sw = Window Switcher, Root = Displays root, Br = Brightness and Dimming, Col = Color, HW = Hardware Controls, Kb = Keyboard, SL = Saved Layouts, VD = Virtual Displays, PIP, Aut = Automations, Aw = Awake.

**ControlID registry** (N16; parity B1, M1; lead r3). Reachability is checked against declarations, not prose:
```swift
// SnapticKit/KitModules.swift (lead)
package struct ControlID: RawRepresentable, Hashable, Codable, Sendable {   // "displays.root.brightness", "menu.display.hdr"
    package let rawValue: String
    package init(rawValue: String)
}
// SnapticKit/ControlMap.swift (H) — the 0.3 side, declared by the owners of each surface
package enum ControlCatalog {
    /// Every 0.3 control: settings rows (= SettingsSearchEntry.id of every SettingsIndex* table), buttons and pull-down
    /// items (`SettingsIndex*.actions`), menu items (`MenuItemCatalog.items`, M), shortcut rows (K sheets).
    package static func all() -> Set<ControlID>
}
package struct MenuItemSpec: Hashable, Sendable {          // M, `SnapticKit/MenuItemCatalog.swift`
    package let id: ControlID; package let location: String          // "display submenu", "Display Tools", …
    package let legacy: DisplayMenuItemID?                           // the 0.2 id it replaces, if any
    package let showHide: Bool                                       // has a pop-up in Customize Displays Menu
    package init(id: ControlID, location: String, legacy: DisplayMenuItemID?, showHide: Bool)
}
package enum MenuItemCatalog { package static var items: [MenuItemSpec] { get } }   // literal table (§4.8 "0.2 menu")
// SnapticKit/ControlMapLegacy.swift (lead, generated ONCE in step 0 from 871c10b by scripts/gen-controlmap.py, then
// frozen; consistency: the 0.2 side never changes)
package enum ControlMapLegacy {
    package static var settingKeyPaths: [String] { get }   // every Codable key path of DisplaysConfig + ModulesConfig ("all
                                                   // features on" fixture) + Switcher `Config` (mirrored, see below)
    package static var actions: [String] { get }   // every 0.2 DisplayActionID / AwakeActionID raw value, Switcher
                                                   // action, and named page button ("button.resolution.undo", …, [UA] §2.2)
    package static var menuItems: [String] { get }   // every 0.2 DisplayMenuItemID raw value (46 at 871c10b, incl.
                                                   // "a.custom.*" as one pattern) + fixed 0.2 menu rows ("menu.recentNotices", …)
}
package enum ControlMap {                          // H + owners: the mapping
    package enum Home: Hashable, Sendable { case control(ControlID), removed(reason: String) }
    package static var settings: [String: Home] { get }
    package static var actions: [String: Home] { get }
    package static var menuItems: [String: Home] { get }
}
```
Tests (`ControlMapTests`, Kit, Linux + macOS): every entry of each `ControlMapLegacy` list has a `ControlMap` home; every `.control` id is in `ControlCatalog.all()`; every `.removed` reason is non-empty; no `ControlMap` key is absent from the legacy lists; catalog ids are unique; every `MenuItemSpec` with a `legacy` id has `showHide == true` unless its row in the menu table says otherwise. The Switcher `Config` lives in the app target, so its keys are mirrored in Kit (`ControlMapLegacy.settingKeyPaths` prefix `switcher.`) and the macOS CI job runs `Snaptic --selftest-controls <token-file>` (A, `SelfTest.swift`, token-gated like `--selftest-helpers`, prints the recursive key paths of `JSONEncoder().encode(Config())`), compared by `scripts/selftest-controls.sh` (lead) with the mirror; a new Switcher key without a mapping fails CI. **Rendering** (parity M1): in DEBUG builds `.settingsAnchor(_:)` and MenuKit record every `ControlID` they render into `ControlCoverage` (H, app); the Debug menu's "Check Control Coverage" walks every root, route and sheet once and builds every menu with all items set to Show, then lists catalog ids that never rendered. The step-3 exit requires that list to be empty with all features on.

**General**

| 0.2 page | 0.2 control | 0.3 home |
|---|---|---|
| Modules | Window Switcher switch · Displays switch | Sw / Root header switches; Onboarding |
| Modules | "New: Displays" card (Turn On Displays…, Not Now) | Gen card, generalized (`newModuleCards`); its "Turn On Awake" targets the Awake module switch + page (parity minor 3) |
| Menu | Switcher **Show** · Displays **Show** | MB pop-ups |
| Menu | Switcher **Icon** · Displays **Icon** (own icon) | MB glyph tiles under the module (Always Show / Show When Active) |
| Menu | Displays "Hide the icon when no external display is connected" | MB Displays pop-up *Show When Active* (migration M2; design M5) |
| Menu | Snaptic **Icon** | MB Snaptic icon tiles |
| Menu | Scroll on a slider to adjust | MB V |
| Menu | Display blocks Expanded/Compact | MB "Display controls" |
| Menu | Main display first · Status badges · Header row with one display · Section order ▲▼ · Display order ▲▼ + Use the Default Order | C (Main display first = the pinned "Main display" row in the order list) |
| Menu | ≈ 46 Visible/In submenu/Hidden pickers | C (grouped, human titles, every item of the "0.2 menu" table below; sliders Show/Hide only; quick-menu items X → their Display Tools twin, C3) |
| Menu | Reset Menu Settings | C footer Restore Defaults… (and MB footer) |
| Menu | Hidden-icon warnings | MB status rows |
| Command-Line | Allow command-line control · Copy install command | Gen V |
| Command-Line | Let commands skip the confirmation panel · exit-code footer | Gen A |
| Startup | Launch Snaptic at login | Gen V "Open at login" |
| Permissions | Permission rows, Open Settings, Relaunch | Permissions page |
| Backup & Reset | Export… · Import… | Gen V |
| Backup & Reset | Reset All Settings… | Gen A footer (destructive) |
| Safe Mode | Restart in Safe Mode / Leave | Gen A; M status row "Leave Safe Mode" |
| Other Display Apps | Pause overlapping / Run both | Root A › Other display apps |
| About & Licenses | Check for Updates… · MIT text | About V · Acknowledgements… sheet |

**Window Switcher**

| 0.2 page | 0.2 control | 0.3 home |
|---|---|---|
| Features | Thumbnails | Sw A "Window thumbnails" (Style stays V) |
| Features | Preview (`previewSelected`) | Sw V "Preview the selected window" |
| Features | Other Spaces · Windowless apps | Sw A (help "Applies to every shortcut") |
| Features | Search · Close · Minimize · Fullscreen · Hide · Quit · Hover buttons · Hover select · ⌘⇥ takeover · Passthrough | Sw A (window actions as one checkbox group) |
| Features | Permission rows | Permissions page; Sw status row "Window thumbnails need Screen Recording." (§4.3 Window Switcher) |
| Shortcuts | Primary: Modifier, Key, Show, Style, Spaces, Include minimized and hidden | Sw V |
| Shortcuts | Primary: Include apps with no open windows · One entry per app | Sw A |
| Shortcuts | Other shortcuts (all options), Add shortcut, Delete | Sw K (More Shortcuts…) |
| Shortcuts | Gather windows recorder | Sw K (More Shortcuts…) |
| Behavior | Switch when the modifier key is released | Sw V (Shortcut section) |
| Behavior | Show the switcher on | Sw A |
| Thumbnails | Auto-size · Size slider | Sw V (subordinates of Style = Thumbnails) |
| App Lists | Hidden from the switcher · Apps that keep the shortcut · Only while full screen | Sw A |
| Privacy | Never capture password managers · Never capture these apps | Sw A "Never show thumbnails for" |

**Displays: feature switches** (0.2 Display Features page, 47 switches + 2 always on)

| Feature | 0.3 switch |
|---|---|
| `overview`, `diagnostics` | always on (no switch) |
| `resolution` · `brightness` · `shortcuts` · `osd` · `rotation` · `disconnect` (Beta) | Root A › Use Snaptic for |
| `mainDisplay`, `arrangement`, `mirroring` | Root A › Use Snaptic for "Arrangement and mirroring" (one switch writes all three; shows `arrangement`; mixed 0.2 values kept raw until touched) |
| `hiddenModes` · `autoBrightness` · `osdBroadcast` · `underscan` · `hdrToggle` | Root A › Exp |
| `scaleMatch` | D › Match text size (disclosure switch) |
| `menuBarOverlays` | D › Menu bar overlays (group switch) |
| `autoDisconnectBuiltin` (Beta) | D (built-in) › Connection |
| `brightnessApple`, `brightnessDDC`, `brightnessGamma`, `brightnessOverlay` | Br A › Brightness methods |
| `brightnessRestore` · `dimToBlack` · `dimOnLock` · `nits` · `xdr` · `sync` | Br V |
| `color` | Col header switch |
| `colorProfiles` · `nightShift` · `applePresets` | Col A · Col A › Exp · Col A › Exp |
| `ddcControls` | HW header switch |
| `ddcInput` · `ddcPower` · `ddcCustom` | HW A |
| `brightnessKeys` · `volumeKeys` | Kb V |
| `layouts` · `protection` | SL header switch · SL V |
| `virtualScreens` · `smartHiDPI` · `hdrVirtual` | VD header switch · VD A · VD A › Exp |
| `pip` · `pipFilters` | PIP header switch · PIP A |
| `hooks` · `customActions` | Aut section switches |
| `sleepPrevention` | X → Awake trigger (migration M1); removed in step 3 |

**Displays: per-page controls**

| 0.2 page | 0.2 control | 0.3 home |
|---|---|---|
| Overview | DDC power switch | HW V (Turn Off/On); M display submenu "Turn Off Display" |
| Overview | Brightness slider | Root V; M; panel |
| Overview | Volume slider + mute | HW V; M slider + submenu "Mute"; panel |
| Overview | Resolution slider | Root V › Resolution options |
| Overview | Resolution picker | Root V; M submenu; panel |
| Overview | Input picker | HW V; M submenu; panel |
| Overview | Identify · Redetect · Show Displays Panel | Root V Display Tools ▾; M Display Tools; panel footer |
| Overview | Displays panel shortcut · Identify shortcut | Kb K (Tools group; migration M4) |
| Overview | "Active features: n of 49" | X (developer statistic; I lists effective and unavailable features) |
| Overview | Banners: Resume Display Automation · Leave Safe Mode… · Restart Snaptic (helper) | Root V status rows (parity minor 1); Safe Mode also Gen V status row + Gen A; M status rows |
| Features (Displays) | Permission rows (Accessibility, Screen Recording) | Root A › Permissions footer status + fix button; Permissions page (parity minor 4) |
| Features | "X is off · Turn On" rows on other pages | X (FeatureHighlights + header/section switches) |
| Resolution | Confirm resolution changes | Root A › Confirm display changes |
| Resolution | Offer modes below 720p · Remember my choice · Show values as · Snap to favorites · Only native aspect ratio | Root A › Resolution filters |
| Resolution | Mode picker · Refresh rate | Root V |
| Resolution | Quick buttons (HiDPI, Native, Default, Native ÷ 2, Notch) | Root V › Resolution options › Quick Changes ▾; Kb K |
| Resolution | Undo / Redo | Root V › Resolution options › Quick Changes ▾ + Settings Edit menu ⌘Z/⇧⌘Z (design M6); M display submenu (when available); Kb K |
| Resolution | Add to Favorites · favorite rows (Apply/Remove) | Root V › Resolution options; favorites in the Resolution pop-up and M submenu |
| Resolution | Show (DPI filter) · Width limit Min–Max + Clear · refresh filter | Root A › Resolution filters › Filters for <display> |
| Resolution | Include in Match UI Size | D › Match text size |
| Resolution | Forget remembered | D "Forget Remembered Resolution"; I list |
| Resolution | Show all modes: display picker + Try list | Root V Resolution pop-up "Show All Resolutions" section (with `hiddenModes`) |
| Resolution | Match UI size: Reference display, Preview/Apply | D › Match text size |
| Resolution | Match tolerance slider | D › Match text size |
| Brightness | Display picker | Root tiles and Br tiles (`PerDisplayPicker` on both, shared selection; parity minor 2) |
| Brightness | Brightness slider · snap marks | Root V (slider ticks) |
| Brightness | Method (read-only) + reason · Use (method picker) · Custom switchover + Switchover slider · Minimum hardware level · Color-table status + Ask Again | Br A › Brightness methods |
| Brightness | Nits: Now | Root brightness value in nits |
| Brightness | Nits: Custom range · Minimum / Maximum (SDR) / Peak (HDR) | Br A |
| Brightness | Show nits in the menu and OSD | Br V "Show brightness in nits" |
| Brightness | XDR: Extra brightness on this display · Custom maximum + Maximum | Br V (per display "Maximum extra brightness") |
| Brightness | XDR Test · XDR global Maximum · XDR Method · Pause in Low Power Mode · Stop at 100% | Br A |
| Brightness | XDR Pause below battery | Br V (subordinate) |
| Brightness | Sync: on · Source · Follow · per display Follow + Offset | Br V (subordinates) |
| Brightness | Sync: Follow outside changes | Br A |
| Brightness | Restore · Smooth transitions · Allow dimming to black · Dim on lock + level | Br V |
| Color | Display picker · Suspend on this display · Contrast, Gamma, Temperature, Black level, White level · Invert | Col V |
| Color | Suspend on all displays · Gain · RGB gain ×3 · RGB gamma ×3 | Col A |
| Color | Reset This Display | Col A footer Restore Defaults… (This display / All displays); per-slider reset glyphs |
| Color | Color profile picker | Col V |
| Color | Show in Finder · Open in ColorSync Utility · Restore Previous | Col A profile actions ▾ |
| Color | Apple display preset picker | Col V (when `applePresets` on) |
| Color | Auto-brightness toggle | Root V "Automatically adjust brightness" |
| Color | Black strip behind the menu bar · corner radii | D › Menu bar overlays |
| Color | Keep color-table dimming with a custom profile | Col A |
| Color | Night Shift on + Warmth | Col A (Experimental, "Night Shift warmth") |
| DDC | Read values back · Every · Re-send after wake | HW A |
| DDC | Display picker · Use DDC with this display | HW V ("Use hardware controls for this display") |
| DDC | Status, Connection, Framing, Writes today, Model, MCCS, Supported codes · Read Capabilities · Check Connection | HW A › Hardware information |
| DDC | Volume · Contrast | HW V ("Hardware contrast"); M sliders |
| DDC | Per-VCP: Use, Raw 0%, Raw 100% + Reported, Invert, Show in menu, Read back every | HW A per-control disclosure rows |
| DDC | Inputs: name, Hide, ▲▼, Add Input, Reset List | HW A input list editor |
| DDC | Inputs: Switch | HW V Input pop-up; M submenu |
| DDC | Power: State, Turn On, Standby… | HW V |
| DDC | Power: Standby sends | HW A |
| DDC | Custom controls list + Name/Code/Kind/Value/Add | HW A editor; defined sliders HW V and M |
| DDC | Raw VCP Code/Value/Read/Send · unlock code · Unlock · Lock All | HW A › Raw commands (disclosure) |
| DDC | Reply delay · Retries · Write twice · Ignore checksums · Forget Learned Framing | HW A › Timing |
| DDC | Allowed without asking | Root A › Confirm display changes |
| Keys | Permission pane, Media keys status, Grant, Try Again | Kb status row + fix button; Permissions page |
| Keys | Brightness keys "Use them" · "Keys change" | Kb V (switch + "Change" pop-up) |
| Keys | Also let macOS handle brightness keys · Steps · Fine steps · F14/F15 | Kb A |
| Keys | Send volume to a monitor | Kb V (Volume keys target) |
| Keys | Also let macOS handle volume keys / mute key | Kb A |
| Keys | Per display: Keys change this display · Show the volume OSD · Sound output name | Kb A |
| Keys | Modifiers table | Kb (i) popover |
| Keys | Filter + ≈ 35 recorders | Kb K (grouped) |
| Keys | Input slots | Kb A |
| OSD | Style · Use the system OSD | Kb V "Indicator style" (system option inside) |
| OSD | Position | Kb V |
| OSD | Show on · Show the value · Preview | Kb A |
| OSD | Show nits | Br V (merged, M5) |
| OSD | Broadcast notification name | Root A › Experimental (with `osdBroadcast`) |
| Arrangement | Canvas · Snap to edges · Position/Align form | Root V Arrange Displays… sheet |
| Arrangement | Main display picker · Mirroring picker | Root V "Use as"; M submenu |
| Arrangement | Rotation · HDR | Root V (when available) |
| Arrangement | Underscan slider + Apply | D › Connection (SliderSetting on release, with confirmation) |
| Arrangement | Disconnect "Header switch" per display | X: no switch in 0.3 menu rows; migration M10 makes the Disconnect / Turn Off Display item top-level for affected displays; a disconnected display keeps a dimmed device row whose submenu offers Connect (parity M6) |
| Arrangement | Connect/Disconnect per display | D; M submenu |
| Arrangement | Connect All | Root Display Tools ▾; M Display Tools |
| Arrangement | My monitor has no DDC · Never auto-disconnect built-in | D › Connection ("This display doesn't support hardware controls") |
| Arrangement | Prevent display sleep while X is connected | Aw trigger (M1) |
| Protection & Layouts | Protect the current arrangement · Save Current Layout | SL V |
| Protection & Layouts | Save Current State as Protected · 5 field toggles · Forget All · Offer Undo after an automatic apply | SL A |
| Protection & Layouts | Per layout: name, status labels, Apply | SL V list |
| Protection & Layouts | Per layout: Apply automatically, Priority, Stop Trusting, Update to Current, Delete | SL Details… sheet |
| Protection & Layouts | Move Up/Down | SL list drag + ▲▼ context menu |
| Virtual & HiDPI | Per screen: Connected · Edit… | VD V list (Connected, Details…) |
| Virtual & HiDPI | Delete | VD Details… sheet |
| Virtual & HiDPI | Shape picker + Create · 4 recipes | VD New Virtual Display… sheet |
| Virtual & HiDPI | Connect/Disconnect/Reconnect/Disassociate/Discard All | VD A "All Virtual Displays ▾" |
| Virtual & HiDPI | Behavior toggles (3) | VD A |
| Virtual & HiDPI | Editor fields (Name, Aspect, Fill Sizes, Diagonal, HiDPI, Portrait, Reconnect at launch, HDR modes, Refresh rate, Sizes, Associations) | VD Details… sheet (Sizes as a table) |
| Virtual & HiDPI | Smart HiDPI per display toggle | VD V "Sharper text on this display" |
| Virtual & HiDPI | Smart HiDPI Size · HDR (PQ) | VD A |
| PIP | Intro + Got It | X (FeatureHighlights while off) |
| PIP | Screen Recording row · Running list (Pause/Show/Crop/Stop, bulk) · config rows (Start/Stop, Edit) · New PIP · New Full-Screen Stream · Windows section | PIP V (Crop in row menu; Windows → New PIP… window picker) |
| PIP | Editor (≈ 30 controls) | PIP editor sheet, all fields kept |
| PIP | Import .cube… · Privacy prefixes + Restore Defaults · Pause covered PIPs · ⌃⌥⌘P stops streams | PIP A (the shortcut also in Kb K) |
| Automation | Hook fields (Name, Enabled, When, Display, Delay, Program, Choose…, Arguments) | Aut list (Enabled, When) + Details… sheet |
| Automation | Action fields (Name, Show in menu, Allow from CLI, Shortcut, Program, Arguments, Run Now, Delete) | Aut list (Show in menu) + Details… sheet; shortcut also in Kb K |
| Display Names | Name · Use the System Name · Icon · Details disclosure · EDID Copy Hex/Base64 · Copy Settings From… | D |
| Display Names | EDID Export… | I (design m6: no file panel over the Details sheet) |
| Display Names | Show in the menu and the Displays panel · Menu order ▲▼ | C (D has a "Menu visibility…" link) |
| Display Names | Remembered: Forget… · Forget All… | I › Remembered displays |
| Safety | Confirm resolution changes · Revert after N s · Tell me when displays were restored · Restore All shortcut (now editable) · Allowed without asking | Root A › Confirm display changes |
| Safety | Restore All Displays Now | Root Display Tools ▾; M Display Tools (kept top-level in the Displays section while a confirmation is pending); panel |
| Safety | Resume | Root A status action; M status row |
| Safety | Helper status · Can revert rotation and HDR · Pending confirmation · Undo journal · Remembered resolutions · Unavailable on this Mac | I |
| Diagnostics | Copy Report · Export… · report + events | I (live) |
| Diagnostics | Refresh | X (I refreshes on change) |
| Onboarding | Module switches · Displays chips · Hide the menu-bar icon · Turn on Smart HiDPI | Onboarding Choose modules + Displays chips, incl. "Hide the menu-bar icon" and "Turn on Sharper Text" chips (§4.7; parity minor 3) |
| Onboarding | In-form "Use These Features" | X (one primary button in the footer) |

**0.2 menu** ([UA] §3.2 fixed rows, plus **every** 0.2 `DisplayMenuItemID`; parity B1, lead r3). "Default" is the 0.2 default visibility, kept; every row with a 0.3 location has a Show / (In Display Submenu) / Hide pop-up in Customize Displays Menu (C). Locations are those of §5.2.

*Fixed rows*

| 0.2 item | 0.3 home |
|---|---|
| Enable Thumbnails (Screen Recording)… | M Switcher section "Turn On Thumbnails…" action item (not a status row) |
| "Press ⌥⇥ to switch windows" | M "Switch Windows ⌥⇥" (C8) |
| Gather Windows on This Display | M Switcher section |
| Display header (bold, no action) | M device row with submenu |
| More ▸ › Resolution ▸ Favorites · modes | M display submenu (≤ 8 modes incl. favorites) + "More Resolutions…" |
| More ▸ › Mute | M display submenu "Mute", in the Turn Off Display group (design m3) |
| Tools › More Display Features… | X: "Display Settings…" in each display submenu and "Snaptic Settings…" cover it (parity minor 3) |
| Recent Notices ▸ (footer) | M footer "Recent Notices ›" (Snaptic menu; own menus when the Snaptic item is absent; parity minor 3) |
| Right-click quick menu | X (C3; every item has a Display Tools ▸ or footer twin) |
| Settings… · Quit Snaptic | M "Snaptic Settings…" · "Quit Snaptic" |
| Safe Mode status row | M status row "Safe Mode is on" + "Leave Safe Mode…" |

*Registered items* (`DisplayMenuItemID` raw value → 0.3 location)

| 0.2 id (title) | 0.3 location | C |
|---|---|---|
| `c.brightness.slider` (Brightness slider) | Displays section, top-level `MenuSliderRow` under the device row | Show/Hide |
| `c.brightness.method` (Brightness method) | X: expert choice, Br A › Brightness methods (no submenus in submenus) | — |
| `c.ddc.volume` (Volume slider) | top-level `MenuSliderRow` (VCP 0x62 displays) | Show/Hide |
| `c.ddc.mute` (Mute) | display submenu, Turn Off Display group | yes |
| `c.ddc.contrast` (Contrast slider) | top-level `MenuSliderRow` (default Hide) | Show/Hide |
| `c.ddc.input` (Input source) | display submenu "Input" header + checkable inputs | yes |
| `c.ddc.power` (Standby switch) | display submenu "Turn Off Display" / "Turn On Display"; top-level under the device row when Show (migration M10) | yes |
| `c.ddc.custom` (Custom DDC controls) | top-level `MenuSliderRow` per defined control | Show/Hide |
| `c.color.submenu` (Color adjustments) | display submenu ✓ "Adjust Colors" (on = not suspended) | yes |
| `c.color.profiles` (Color profile) | display submenu "Color Profile" header + current, previous and ≤ 3 recent profiles, then "More Color Profiles…" (opens Col) | yes |
| `c.color.applePresets` (Apple display preset) | display submenu "Preset" header + presets (Apple displays, `applePresets` on) | yes |
| `c.color.autoBrightness` (Auto-brightness) | display submenu ✓ "Automatically Adjust Brightness" (built-in) | yes |
| `c.menuBarStrip.toggle` (Menu-bar strip) | display submenu ✓ "Black Menu Bar Background" | yes |
| `c.xdr.toggle` (Extra brightness) | display submenu ✓ "Extra Brightness" (XDR displays) | yes |
| `c.sync.toggle` (Brightness sync) | Display Tools ✓ "Sync Brightness" | Show/Hide |
| `c.tools.nightShift` (Night Shift) | Display Tools ✓ "Night Shift" | Show/Hide |
| `d.resolutionSlider` (Resolution slider) | top-level discrete `MenuSliderRow` (commits on release; default Hide); never in a submenu | Show/Hide |
| `d.resolutionMenu` (Resolution modes) | display submenu modes | yes |
| `d.matchUI` (Match UI Size…) | Display Tools "Match Text Size…" (opens Display Details › Match text size) | Show/Hide |
| `d.setMain` (Set as Main Display) | display submenu "Use as Main Display" | yes |
| `d.mirrorMenu` (Mirroring) | display submenu "Mirror “X”" toggles | yes |
| `d.rotationMenu` (Rotation) | display submenu "Rotation" header + ✓ Standard / 90° / 180° / 270° | yes |
| `d.hdrToggle` (HDR) | display submenu ✓ "High Dynamic Range" | yes |
| `d.powerSwitch` (Header connect switch) | X: no switches in device rows (AppKit rows are native items); migration M10 promotes Disconnect / Turn Off Display (parity M6) | — |
| `d.disconnectItem` (Disconnect) | display submenu "Disconnect"; top-level when Show; a disconnected display keeps a dimmed device row whose submenu has "Connect" | yes |
| `d.connectAll` (Connect All Displays) | Display Tools | Show/Hide |
| `d.connectAll.quick` | X: quick menu (C3) → `d.connectAll` | — |
| `d.disconnectAllButMain` | Display Tools "Disconnect All But Main" | Show/Hide |
| `d.arrange` (Arrange…) | Displays section "Arrange Displays…" | Show/Hide |
| `d.underscanMenu` (Underscan) | display submenu "Underscan…" (opens Display Details › Connection; `underscan` on) | yes |
| `d.sleepPrevention` | X → Awake (migration M1); the Awake menu | — |
| `d.protection` (Protect Arrangement) | Displays section "Saved Layouts ›" ✓ "Protect Arrangement" | Show/Hide |
| `d.layoutsMenu` (Layouts) | Displays section "Saved Layouts ›": layouts (Apply; ✓ = matching), ─, Apply Matching Layout, Protect Arrangement, Save Current Layout… | Show/Hide |
| `d.layoutMatch` (Apply matching layout) | in Saved Layouts › | Show/Hide |
| `d.virtualMenu` (Virtual Screens) | Displays section "Virtual Displays ›": ✓ per virtual display (Connected), ─, Virtual Displays Settings… | Show/Hide |
| `d.smartHiDPI` (Smart HiDPI) | display submenu ✓ "Sharper Text" | yes |
| `b.restoreAll` (Restore All Displays) | Display Tools; top-level in the Displays section while a change awaits confirmation | Show/Hide (top-level copy always shown while pending) |
| `b.restoreAll.quick` | X: quick menu (C3) → `b.restoreAll` | — |
| `b.resumeAutomation` (Resume Display Automation) | Displays section status row "Display automation is paused" + action item, while paused | always while paused |
| `f.tools.identify` · `f.tools.redetect` · `f.tools.panel` | Display Tools | Show/Hide |
| `f.quick.redetect` | X: quick menu (C3) → `f.tools.redetect` | — |
| `e.pip.display` (Picture in Picture per display) | display submenu "Show in Picture in Picture" | yes |
| `e.pip.tools` (Picture in Picture) | Displays section "Picture in Picture ›": saved PIPs (✓ = running; click starts/stops), ─, Stop All | Show/Hide |
| `a.custom.<id>` (custom actions with "Show in the menu") | Displays section "Actions ›" (one item per action, Run on click); the per-action flag stays Automations › "Show in menu" and is mirrored in C | per action |
| More ▸ › Resolution slider, quick actions, Brightness Method ▸ | covered by `d.resolutionSlider`, Quick Changes (Root V, Kb K), `c.brightness.method` above | — |

## 5. Menu bar redesign (M owns the system; module owners own their sections)

### 5.1 MenuKit (M, `Core/MenuKit.swift`, `Core/MenuSliderRow.swift`, `Core/MenuSwitchHeader.swift`)

Custom rows are **AppKit only** (design M11, code minor 4): no `NSHostingView` in any menu (lint L13). They size immediately, keep the 26/27 menu material's vibrancy, and need no activating click. Everything that changes while a menu is open uses `.common`-mode timers and `DispatchQueue.main` delivery (N15).

```swift
@MainActor enum MenuKit {
    static let width: CGFloat = 300                          // menus containing custom rows
    static func header(_ title: String) -> NSMenuItem        // NSMenuItem.sectionHeader(title:) — the ONLY header style
    static func action(_ title: String, symbol: String? = nil, key: String = "",
                       modifiers: NSEvent.ModifierFlags = .command, enabled: Bool = true,
                       control: ControlID? = nil,
                       _ handler: @escaping @MainActor () -> Void) -> NSMenuItem
    static func toggle(_ title: String, isOn: Bool, symbol: String? = nil, enabled: Bool = true,
                       control: ControlID? = nil,
                       _ handler: @escaping @MainActor () -> Void) -> NSMenuItem      // checkmark
    static func alternate(of item: NSMenuItem, title: String,
                          _ handler: @escaping @MainActor () -> Void) -> NSMenuItem  // ⌥, isAlternate
    static func submenu(_ title: String, symbol: String? = nil, enabled: Bool = true, control: ControlID? = nil,
                        _ items: [NSMenuItem]) -> NSMenuItem   // one level only (asserted in debug)
    static func status(_ text: String, symbol: String? = nil) -> NSMenuItem          // disabled info row
    static func device(_ title: String, symbol: String, dimmed: Bool = false, submenu: [NSMenuItem]) -> NSMenuItem
    /// Secondary line under an item: `NSMenuItem.subtitle` on 14.4+ (`#available`). On 14.0–14.3 the subtitle is
    /// appended to the title ("Desk dock — Active") instead of a separate row, because an ⌥ alternate must directly
    /// follow its primary item (code minor 2).
    static func withSubtitle(_ item: NSMenuItem, _ subtitle: String?) -> NSMenuItem
    /// AppKit view row (`MenuSwitchHeaderView`, an NSView in MenuSwitchHeader.swift; consistency m13): bold title +
    /// NSSwitch (.small, as in the Wi-Fi menu) + up to two secondary lines (NSTextField, secondaryLabelColor).
    /// Height is fixed when the menu opens (26, 40 or 54) and kept while it is open; a line-count change is applied in
    /// `menuDidClose` (code minor 3). No fills. Mouse only: the same action always exists as a native item (parity M4).
    static func switchHeader(_ title: String, isOn: Bool, detail: [String], control: ControlID? = nil,
                             onToggle: @escaping @MainActor (Bool) -> Void) -> NSMenuItem
    static func settings(_ title: String, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem   // ⌘,
    static func quit() -> NSMenuItem                                                                     // "Quit Snaptic" ⌘Q
}
@MainActor final class MenuSliderRow: NSMenuItem {
    /// AppKit view 300×30: leading 16 pt template symbol in the image column, NSSlider (.regular) on the text
    /// column, trailing value label 40 pt (monospacedDigitSystemFont, secondaryLabelColor); measured per OS [HW-15].
    /// `discrete`: tick-snapped, commits on `.ended` only (resolution slider).
    init(title: String, symbol: String, value: Double?, range: ClosedRange<Double>, format: ValueFormat,
         discrete: Bool = false, control: ControlID? = nil,
         onChange: @escaping @MainActor (Double, DragPhase) -> Void)
    func bind(to publisher: AnyPublisher<Double?, Never>)   // live updates while open (.receive(on: DispatchQueue.main));
                                                            // ignored during a drag
    func setValue(_ v: Double?)                             // nil → slider disabled, value "—"
}
```

Custom-row behavior (code minor 3, normative): a view row draws its highlight from `enclosingMenuItem.isHighlighted` with an `NSVisualEffectView(material: .selection)` background so arrow-key navigation shows it, and sets `accessibilityLabel` (title + value); `MenuSliderRow` delivers `.began` on mouse down, `.changed` while tracking and `.ended` after `super.mouseDown` returns; each scroll-wheel step (with "Scroll over a slider to adjust it") delivers a `.changed` + `.ended` pair.

Item rules: Title Case; ellipsis only when more input follows; toggles use checkmarks or a changing title; submenus one level deep, ≤ ~12 items plus at most one "More…" that opens Settings. **Images: all items of a section or none** (design m1; 15-SDK builds show every attached image on 26/27, [DS] §3.3): the Displays section gives every top-level item a 16 pt template symbol (device rows, `rectangle.3.group` for Arrange Displays…, `square.stack.3d.up` for Saved Layouts ›, `display.2` for Virtual Displays ›, `pip` for Picture in Picture ›, `bolt` for Actions ›, `wrench.and.screwdriver` for Display Tools); the Switcher and Awake sections use none, except the app rows of "While an App Is Running ›", which is its own group (parity minor 11). Custom rows are never clickable themselves; every slider action and every switch-header action also has a native path (C4). Every item built through MenuKit passes its `ControlID` (§4.8) so DEBUG coverage can see it. `ClosureMenuItem`, `CMenu.item`, `ManagedMenuItem` (in D's `Displays/Management/ManagementSupport.swift`), `DisplayMenuBlock.actionItem`, `PanicMenuItem`, `MenuSliderItem` are deleted **at the step-3 exit** after a caller grep, tracked in the ratchet until then (code M10); contributors move to MenuKit during steps 1–3 (lint L6 bans `NSMenuItem(` outside the MenuKit files; permanent ratchet rows: `AppDelegate.swift` main menu, `PIPWindow.swift` context menu).

### 5.2 Snaptic icon menu (shared item)

**When it exists** (Kit `StatusItemPlan`, parity M3, consistency M3): the Snaptic item is shown iff some running module is *Show in Snaptic Menu*, or the compact Awake section is due (§5.4), or **no module is enabled** (then it says "No Modules Are On" + "Snaptic Settings…"). With every enabled module set to Don't Show there is no item at all (`everythingHidden`; relaunching Snaptic opens Settings). When it is absent, every own-icon and custom menu ends with **Recent Notices ›** (when there are notices) and **Quit Snaptic ⌘Q**, after its own "<Module> Settings…" item (not alternates; design m4). **Active variant** (N11, parity M5): `sharedActiveGlyph = awakeGoverning && showShared`, whether or not an Awake item exists: the Snaptic glyph switches to its `.fill`/badge-dot variant and its accessibility label appends ", keeping your Mac awake". **A session never removes an item that was shown at rest** (parity M5): if the Snaptic item exists at rest (even only for the compact section), it stays during the session, still showing the compact section.

Built in `menuNeedsUpdate` from the plan, in start order; sections separated by one separator; values update in place while open (N15).

```
[Safe Mode is on]                                    status row + "Leave Safe Mode…" (only in Safe Mode)
Window Switcher                                      header
  Switch Windows                              ⌥⇥    C8 (sticky switcher)
  Gather Windows on This Display
  Turn On Thumbnails…                                action item, only while Screen Recording is missing
───
Displays                                             header
  [!] Display automation is paused                   status row + "Resume Display Automation" (only while paused)
  [▭] Studio Display                          ›     device row; subtitle "Main"
  [☀] ━━━━━━━━●━━━━━  70%                            MenuSliderRow (brightness)
  [▭] DELL U2720Q                             ›
  [☀] ━━━━━●━━━━━━━━  45%
  [🔈] ━━━●━━━━━━━━━━  30%                            volume only if VCP 0x62
  [▭] LG HDR 4K (disconnected)                ›     dimmed device row; submenu "Connect" (parity M6)
  [↺] Restore All Displays                            top-level only while a change awaits confirmation
  [▦] Arrange Displays…
  [▤] Saved Layouts                           ›     only with `layouts` on and Show in C (default as 0.2)
  [▢] Virtual Displays                        ›     only with `virtualScreens` and ≥ 1 virtual display
  [⧉] Picture in Picture                      ›     only with `pip` and ≥ 1 saved PIP
  [ϟ] Actions                                 ›     only with custom actions marked "Show in menu"
  [🔧] Display Tools                           ›     Identify Displays · Redetect Displays · Show Displays Panel ·
                                                    Match Text Size… · Connect All Displays · Disconnect All But Main ·
                                                    Restore All Displays · ─ · ✓ Sync Brightness · ✓ Night Shift
───
Keep Awake                                   [●]    compact Awake section (§5.4): AwakeMenuRows minus rules, no header
  Until turned off
Turn Off Keep Awake
✓ Keep Display On
Until Turned Off
Start Session                                 ›
While an App Is Running                       ›
───
Recent Notices                                ›     only when there are some
Snaptic Settings…                            ⌘,
Quit Snaptic                                 ⌘Q
```

Display submenu (one level, ≤ ~12 items with the defaults; per-item visibility from C; design m2, m3):

```
✓ Default                                           subtitle "1512 × 982"; ≤ 8 modes: current, default, favorites, recommended
  Larger Text
  More Space
  More Resolutions…                                 opens Settings › Displays › Resolution options
  Undo Resolution Change / Redo Resolution Change   only when available (parity B2)
───
  Use as Main Display
  Mirror “Built-in Retina Display”                  one toggle per possible target, inline
───
  (opt-in, per C) ✓ High Dynamic Range · ✓ Extra Brightness · ✓ Sharper Text · ✓ Adjust Colors ·
  ✓ Automatically Adjust Brightness · ✓ Black Menu Bar Background · Underscan… · Show in Picture in Picture
  (opt-in) Rotation header + ✓ Standard / 90° / 180° / 270° · Color Profile header + ≤ 5 profiles + More Color Profiles…
  · Preset header + presets
───
Input                                               header (DDC, if `ddcInput`)
✓ USB-C
  HDMI 1
───
  Mute                                              if volume (design m3: with the power items)
  Turn Off Display                                  (if `ddcPower`) · Disconnect (if `disconnect`)
  Display Settings…
```
Color-adjustment sliders and the brightness-method choice are not in the menu (Settings only). Per-item visibility (Customize Displays Menu) applies to every registered item: "Show" places it at its location above (per-display toggles and headers in this submenu, Disconnect / Turn Off Display at top level under the device row, tools items in Display Tools, section submenus in the Displays section), "In Display Submenu" (per-display items only) keeps it in this submenu, "Hide" removes it; sliders can be Show or Hide only. With no modules enabled: "No Modules Are On" status row + "Snaptic Settings…" (design m2). With the **Compact** style: one slider per display, device rows without subtitles.

Kit (lead declares the types; M owns the plan logic; consistency B1, code R2-M2c):

```swift
// SnapticKit/KitModules.swift (lead), beside MenuPlacementChoice
package enum MenuPresence: String, Codable, CaseIterable, Sendable {
    case ownIcon, ownIconWhenActive, inSnapticMenu, hidden   // menu order (design M5); raw values persisted
    /// ownIconWhenActive only for .displays and .awake (sanitized → ownIcon elsewhere).
    package static func allowed(for id: ModuleID) -> [MenuPresence]
    package var legacyPlacement: MenuPlacementChoice { get }   // written for 0.2 downgrades (migration M2)
}
// SnapticKit/Config/ConfigModules.swift (lead; stays here, one declaration; code sig): new fields have defaults so
// the existing 7 call sites keep compiling
package struct StatusItemPlan: Equatable, Sendable {
    package var shared: [ModuleID]           // sections in the Snaptic item, in start order
    package var ownIcon: [ModuleID]          // host-built own items (Switcher, Displays; Displays when active)
    package var showShared: Bool
    package var noModulesEnabled: Bool
    package var everythingHidden: Bool
    package var custom: [ModuleID]           // provider-built items that should exist now (Awake)
    package var awakeCompactInShared: Bool
    package var sharedActiveGlyph: Bool      // N11: awakeGoverning && showShared
    package var sharedFooterInOwnMenus: Bool // Snaptic item absent → Recent Notices + Quit in every own/custom menu
    package init(shared: [ModuleID], ownIcon: [ModuleID], showShared: Bool, noModulesEnabled: Bool,
                 everythingHidden: Bool, custom: [ModuleID] = [], awakeCompactInShared: Bool = false,
                 sharedActiveGlyph: Bool = false, sharedFooterInOwnMenus: Bool = false)
}
// ModulePreferences gains `presence`; `placement` and `hideWithoutExternalDisplay` stay declared and are written from it
//   package var presence: MenuPresence
//   package init(enabled: Bool, placement: MenuPlacementChoice = .shared, symbol: String = "",
//                hideWithoutExternalDisplay: Bool = false)        // kept until the step-3 exit (code sig)
//   package init(enabled: Bool, presence: MenuPresence, symbol: String = "")
//   package static func defaultPreferences(_ id: ModuleID) -> ModulePreferences   // per id: .awake → (true, .ownIconWhenActive)
// The existing statusItemPlan(running:) stays and calls the new function with awakeActive: false,
// displaysActive: true, awakeShortcutBound: false until the step-3 exit.

// SnapticKit/MenuLayout.swift (M): the logic only
extension ModulesConfig {
    package func statusItemPlan(running: Set<ModuleID>, awakeActive: Bool, displaysActive: Bool,
                                awakeShortcutBound: Bool, sharedShownAtRest: Bool) -> StatusItemPlan
}
```
Plan rules (tested truth table, `MenuLayoutTests`): Awake `.ownIcon` → custom item always; `.ownIconWhenActive` → custom item while active, compact section in the Snaptic item while idle **and** while active if the Snaptic item was shown at rest (`sharedShownAtRest`, parity M5); `.inSnapticMenu` → compact section always; `.hidden` (only selectable with a bound shortcut) → nothing at rest; while active, the Snaptic item's active glyph if it exists, otherwise the custom item appears for the session (N11). If the Keep Awake shortcut becomes unbound or fails to register while presence is `.hidden`, the host sets presence to `.ownIconWhenActive` and shows "Awake is back in the menu bar because its keyboard shortcut is no longer set." (parity minor 11). Displays `.ownIconWhenActive` → own item only while an external display is connected (`displaysActive`). Every module Don't Show → no item (`everythingHidden`, consistency M3). `StatusMenu.hasVisibleItem` and `everythingHidden` count provider items through `StatusItemProvider.statusItem` (code B3). `StatusMenu.applyPlan` calls `applyStatusItem(_:)` on every provider in the same turn; `AwakeHost.requestStatusPlan()` re-plans whenever Awake's active state flips (code R2-M6).

### 5.3 Awake status item (G, `IndicatorController`, exposed through `AwakeModule: StatusItemProvider`)

`NSStatusItem(variableLength)`, `autosaveName = "SnapticAwake"`, `behavior = .removalAllowed`, created and removed only in `applyStatusItem` (code R2-M6). KVO on `isVisible` ignores changes made by Snaptic itself and during teardown (a flag around our own writes), and `isVisible = true` is set whenever the item is re-created, because the autosave name restores `false` after a removal (code minor 5). A user ⌘-drag removal calls `AwakeHost.setPresence(.inSnapticMenu)` with the toast "Awake's menu bar icon was removed. Awake is now in the Snaptic menu; change this in Settings › Menu Bar." With `.ownIconWhenActive`, the plan adds the item when a session starts and removes it when it ends (deferred while its menu is open).

Look (design M7 r1): template SF Symbol with `SymbolConfiguration(pointSize: 15, weight: .regular, scale: .medium)` (compared optically with Wi-Fi), outline when idle, `.fill` when active, same width; `imagePosition = .imageLeading`; text set with `button.title` and `button.font = .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)` — **never an `attributedTitle` with a color** (breaks the system's menu-bar text treatment on transparent 26/27 bars and under Increase Contrast). Text: Time *Time Remaining* → `AwakeCountdown.short` ("1h 42m", "42m", "42s") for timed and capped sessions; *End Time* → `AwakeCountdown.clock` ("5:00 PM", system 12/24 h); indefinite, uncapped task and automatic sessions show the glyph only. Redraw at `AwakeCountdown.nextChange` (minute boundaries; 1 s in the last minute) on a timer in `.common` mode, so the title and an open menu keep updating (N15). **Accessibility label and tooltip are refreshed at every `nextChange` tick**, also in icon-only style: "Awake, 1 hour 42 minutes remaining" / "Awake, until turned off" / "Awake, off" (design M8); the countdown never posts an announcement, a session end posts one ("Awake turned off.", design m10).

**One row set** (design M1, M2, lead r3): `AwakeMenuRows` (G, `Awake/UI/AwakeMenuRows.swift`, replaces r2's `AwakeMenuBuilder`) builds the rows for both the Awake menu and the compact section; the header is always "Keep Awake" (it names the session, the Settings switch names the module). Idle, Awake menu (6 rows):

```
Keep Awake                                 [○]   switchHeader (mouse): on → default preset, off → Turn Off
  Off                                            detail: "Off", or "Ended at 3:12 AM: battery below 20%." (12 h),
                                                 or "Ended because the battery is below 20%." (guard holding)
────
Until Turned Off                                 first-level native start item (lead r3; keyboard path to start)
Start Session                               ›    For 30 Minutes · ✓ For 1 Hour · For 2 Hours · For 5 Hours ·
                                                 Until Downloads and Tasks Finish · ─ · Custom…
                                                 (presets in order, minus Until Turned Off; ✓ = default or running)
While an App Is Running                     ›    running regular apps (recent first, ≤ 12, app icons; own group)
────
Automatic Sessions                          ›    subtitle "Waiting for Desk dock" / "Desk dock is active" /
                                                 "Paused until 4:00 PM"; rows read-only (subtitle "Active"/"Waiting";
                                                 click opens the rule in Settings; ⌥ alternate "Turn Off “Desk dock”");
                                                 active rules + ≤ 4 others; ─ Pause for 1 Hour · Pause Until Tomorrow
                                                 (or Resume Automatic Sessions) · Edit Rules…   (only with `triggers`)
────
Awake Settings…                           ⌘,     the only Settings item in this menu (design m4, parity minor 8)
```
Active timed session (10 rows): the detail reads "Until 3:45 PM · 1h 12m left" (plus "Appearing active" / "Moving the pointer" / "Stopped appearing active after 1 hour." and, on battery or without an external display, "Closing the lid will put your Mac to sleep."); **Turn Off Keep Awake** follows the header (native, keyboard/VoiceOver path, parity M4); then a group **Add 15 Minutes** · **Add 1 Hour** (⌥ **Add Time…**, opens the Custom panel in extend mode; timed and capped kinds only, parity minor 5) · **✓ Keep Display On** (mid-session toggle, `setKeepDisplayOn`; present only while active, design M2, parity minor 9); then Until Turned Off, Start Session ›, While an App Is Running ›, Automatic Sessions ›, Awake Settings…. Choosing an item in Start Session › while a session runs replaces it; choosing the running preset restarts its timer. When the Snaptic item is absent the menu also ends with Recent Notices › and Quit Snaptic (§5.2). Every common task takes ≤ 2 clicks and has a keyboard path. "Start Anyway" never appears in the menu: a refused start shows a toast with the button (parity minor 9).

### 5.4 Compact Awake section in the Snaptic menu

Shown when the plan's `awakeCompactInShared` is true (§5.2), with no section header (design m3): the same `AwakeMenuRows` minus Automatic Sessions › and minus Awake Settings… (the Snaptic menu's footer has Snaptic Settings…): switchHeader "Keep Awake" with detail · Turn Off Keep Awake (active) · Add 15 Minutes / Add 1 Hour (timed or capped) · **✓ Keep Display On** (active; parity M4) · Until Turned Off · Start Session › · While an App Is Running › (its own submenu; parity minor 11). Rules are reached from the Awake page or the Awake item.

### 5.5 macOS 26/27 hidden and overflow behavior

There is no API to learn that the system hid an item (26 "Allow in the Menu Bar", 27 overflow); occlusion is unreliable on 27 ([PA] §8). Therefore: every Awake and Displays function is reachable from Settings (Awake status row with Keep Awake / Options ▾ / Turn Off; Displays root live controls), hotkeys, the CLI, and the floating Displays panel; **opening Snaptic again always shows Settings** (0.2 rule restored; parity minor 13); the 0.2 hidden-icon warnings stay on the Menu Bar page; the Snaptic item and the Awake item have separate autosave names so the system and the user can place them independently; the Snaptic item shows its active variant whenever Awake governs (N11), so a session is visible even when a new Awake item lands behind the notch or in 27's overflow (parity M5; HW-14 adds a notched MacBook with 20 items and 27 overflow); the default `.ownIconWhenActive` costs no notch space at rest (C11); a CLI-started session announces itself with a toast (§3.1); no right-click, hover, programmatic highlight or occlusion dependence (C3).

### 5.6 Floating Displays panel

Restyled with the same `DisplayLiveControls` rows as the Displays root page (shared SwiftUI views from F; brightness, volume, resolution pop-up, input); the "⋯" button opens the display's submenu content as an `NSMenu` popped at the button (no mixed panel/menu blocks); footer buttons: Identify, Restore All Displays, Settings.

## 6. Files, ownership, CI, delivery

### 6.1 Teams

| Team | Owns |
|---|---|
| **Lead** | Contracts, stubs, CI, lint + ratchet, Info.plist, Package.swift, Awake module shell, host wiring (ModuleHost incl. `Modules.disable.<id>`, HostSignals, ToastPresenter changes), cross-section migrations, ConfigSlice/ControllerRevision types, `MenuPresence`/`StatusItemPlan`/`ControlID` types, the frozen `ControlMapLegacy` lists |
| **G — Awake core** | Awake Kit models and logic, sessions/assertions/guards/triggers/history/automation controllers, task sessions, indicator and `AwakeMenuRows`, Awake settings pages, Awake search index |
| **J — Awake sources** | Criterion sources, PowerMonitor, SystemEventsMonitor (session facts), CPU/disk samplers, ProcessWatch, activity simulation, Drive Alive (+ Drives page) |
| **H — Settings UI** | SettingsUI library, SettingsShell (sole owner) + search, Kit settings index types, `ControlMap`/`ControlCatalog` + DEBUG `ControlCoverage`, General/Permissions/About pages, Onboarding, Window Switcher page |
| **M — Menu system** | MenuKit, MenuSliderRow, MenuSwitchHeader, StatusMenu, Kit MenuLayout (plan logic) + `MenuItemCatalog`, Menu Bar page + Customize sheet, Displays menu builder/blocks, `ConfigMenu` |
| **A, B, C, D, E, F** (existing) | Their Displays controllers (observability, menu contributors on MenuKit) and the new pages/sections for their features (§4.3), per §6.2; A also Switcher runtime changes, **ControlServer peer credentials and held connections** (§2.10), `EventLog` Awake overload, `--selftest-controls`, KitBackup/KitControl; B also `Fingerprint.matches` |

### 6.2 Files (normative; every path goes into `scripts/stubs.tsv` with owner and kind in step 0; ⇢ = ownership moves; ✗ = deleted **at the step-3 exit** after a caller grep, tracked in the ratchet until then)

```
Lead:
  Package.swift (link CoreAudio, SystemConfiguration, DiskArbitration), Resources/Info.plist (0.3.0,
    NSRemovableVolumesUsageDescription), .github/workflows/build.yml (+ selftest-controls step),
    scripts/{lint.sh, lint-legacy.tsv (new), stubs.tsv, gen-stubs.py, gen-controlmap.py (new), selftest-controls.sh (new)}
  SnapticKit/KitModules.swift (ModuleID.awake, EventCategory.awake + isExportedInDiagnostics, AwakeActionID,
    AwakeCriterionKind, MenuPresence, ControlID, DisplayActionID.fShowPanel/.fIdentify;
    DisplayFeature.sleepPrevention removed in step 3 together with D/F/A), SnapticKit/AwakeFeatureGraph.swift (new),
    SnapticKit/FeatureGraph.swift (−sleepPrevention in step 3), SnapticKit/ControlMapLegacy.swift (new, generated once)
  SnapticKit/Config/ConfigAwake.swift (shell; G fills functions in step 2),
    Config/ConfigDisplays.swift (M4, M5, M10, migrations markers, DisplaysConfigSection, changedSections,
    DisplaysRestoreScope + restoringDefaults(scope:)),
    Config/ConfigModules.swift (⇢ from A; presence, newModuleCards, markers, per-id defaults, upgradeDefaults + Awake,
    StatusItemPlan (stays here, new defaulted fields), M2, M3)
  Snaptic/Core/{ModuleContracts (settings contracts §4.1 + extension defaults, SettingsTint, FeatureHighlight,
               StatusItemProvider + CustomItemRow, FeatureAvailability moved here), ModuleContext (⇢ from A; hostSignals),
               HostSignals (new), ConfigSlice (new), ToastPresenter (⇢ from A; presenting/screensaver suppression,
               Recent Notices routing, actions: [ToastAction]), ModuleHost (⇢ from A; Awake wiring, stores,
               Modules.disable.<id>, upgrader insertion, M1, isTerminating, Reset All)}.swift
               (ConfigStore.swift stays A's and unchanged: r2's admission hook is withdrawn)
  Snaptic/Awake/{AwakeModule, AwakeContext (+AwakeHost), AwakeContracts (+ChangeFanout), AwakeRuntimeState}.swift (new)
  Snaptic/Displays/{DisplaysModule (fan-out by section), DisplaysRuntimeState (ControllerRevision per id, DisplayRuntime
               fields, DisplaysPageEnvironment forwards no config; −sleepPreventionActive in step 3),
               DisplaysContracts (observedSections default, DisplayLiveControlling, LiveControl, DragPhase)}.swift

G (Kit, each with Tests/SnapticKitTests/<Name>Tests.swift):
  AwakeSession (+HoldBinding, UntilIdleSpec, TaskActivitySample, TaskQuiet), AwakeClock (+AwakeCountdown,
  AwakeDurationGrammar), AwakeArbiter, AwakeGuards, AwakeTriggers, AwakeTriggerEngine, AwakeHistory, AwakeSnapshot,
  AwakeMigration (+AwakeMigrationResult), AwakeCommandGrammar (+AwakeCommand, AwakeStatusFacts), AwakeLogEvent,
  Config/ConfigAwakeSessions (+AwakeBehavior, UserSwitchEnd), Config/ConfigAwakeIndicator, SettingsIndexAwake
G (app): Snaptic/Awake/Core/{AssertionManager, SessionController, TaskSessionMonitor (untilIdle + hold),
               GuardsController, TriggerController, Ticker, HistoryController, AwakeAutomation, AwakeDiagnostics}.swift
         Snaptic/Awake/UI/{IndicatorController, AwakeMenuRows, CustomSessionPanel, AwakePage, PresetEditorSheet,
               TriggerEditorSheet, CriterionEditors, AwakeAdvancedSheet, OtherAssertionsSection, AwakeHistoryPage}.swift

J (Kit): CPUMath (+CPUTicks), NetworkMath (+InterfaceCounters; CIDR/IPv6 parse + match, MAC normalize, throughput),
         DiskMath, ActivityPolicy (+IdleMath), DriveAlivePolicy, Config/ConfigAwakeDevices (+VolumeUUIDKey)
J (app): Snaptic/Awake/Sources/{PowerMonitor, SystemEventsMonitor, AppMonitor, DisplayPresence, USBWatcher, VolumeMonitor,
               AudioMonitor, CPUSampler, DiskIOSampler, IdleSampler, NetworkMonitor, BluetoothPresence, ActivitySimulator,
               DriveAliveService, OtherAssertionsReader (+SleepDisabled), ProcessWatch (kqueue, proc_pidinfo)}.swift
         Snaptic/Awake/Core/{ActivityController, DriveAliveController}.swift, Snaptic/Awake/UI/DrivesPage.swift

H (Kit): SliderMath, SettingsIndex (SettingsRoute, SettingsSearchEntry, SettingsSearch — Kit so search is tested on Linux),
         ControlMap (+ControlCatalog; §4.8), SettingsIndexGeneral, SettingsIndexSwitcher
H (app): Snaptic/SettingsUI/ControlCoverage.swift (DEBUG coverage recorder + "Check Control Coverage")
H (app): Snaptic/SettingsUI/{SettingsIcon, SettingsPageHeader, FeatureHighlights, SettingRow, ToggleSetting, SliderSetting,
               NumberField, StepperSetting, PickerSetting, GlyphTilePicker, ActionMenuButton, InfoButton, NavigationRow,
               ButtonRow, StatusRow, PerDisplayPicker, PageFooterButtons, AdvancedSheet, ReorderableList, AppListEditor,
               ShortcutSetting, EmptyListView, SettingsPageScaffold, SettingsAnchor, SettingsBinding, SettingsShell,
               SettingsSearchView}.swift
         Snaptic/Core/{SettingsWindowHost, GeneralPages, Onboarding}.swift (⇢ from A)
         Snaptic/Switcher/{SwitcherPages, SettingsView}.swift (⇢ from A)

M (Kit): MenuLayout (ModulesConfig.statusItemPlan logic only; MenuPresence and StatusItemPlan are the lead's,
         consistency B1), MenuItemCatalog, SettingsIndexMenuBar,
         Config/ConfigMenu (⇢ from F; legacy shortcut fields kept and encoded until 0.4)
M (app): Snaptic/Core/{MenuKit, MenuSliderRow, MenuSwitchHeader (MenuSwitchHeaderView), MenuBarPage,
               CustomizeMenuSheet}.swift (new),
         Snaptic/Core/{StatusMenu, MenuPlacement}.swift (⇢ from A), Core/MenuSliderItem.swift (⇢ from A, then ✗),
         Snaptic/Displays/UI/{DisplaysMenuBuilder, DisplayMenuBlock}.swift (⇢ from F),
         Displays/UI/MenuCustomizationPage.swift (⇢ from A, then ✗)
D: also `ManagedMenuItem` in Displays/Management/ManagementSupport.swift ✗ (symbol only, step-3 exit; consistency m10)

F: Displays/UI/{DisplaysPage, DisplayLiveControls, DisplayDetailsSheet, DisplaysAdvancedSheet, DisplaysFeatureGroups,
               DisplayInformationPage}.swift (new); DisplaysOverviewPage ✗, FeaturesPage ✗, DisplayIdentityPage ✗ (→ DetailsSheet),
               DiagnosticsPage ✗ (→ DisplayInformationPage); OverviewController (panel restyle), DisplaysOnboardingStep;
   Kit DisplaysUIModel (groups, user titles; −sleepPrevention in step 3), Kit SettingsIndexDisplays (rows from owners via F)
C: Displays/UI/{BrightnessSubpage, BrightnessSections, BrightnessAdvancedSheet, ColorPage, HardwareControlsPage,
               KeyboardPage}.swift; BrightnessPage ✗ (→ Subpage/Sections), DDCPage ✗ (→ HardwareControlsPage),
               KeysPage ✗ + OSDPage ✗ (→ KeyboardPage); BrightnessMenuItems, DDCMenuItems (MenuKit);
   Displays/Live/DisplayLiveController.swift (new; DisplayLiveControlling); controllers: runtime fields + revision bumps;
   Kit ConfigKeys (osdShowNits legacy, kept encoded)
D: Displays/UI/{ResolutionSections, ResolutionOptionsSection, MatchTextSizeSection, ArrangeSheet, ArrangementCanvas,
               SavedLayoutsPage, VirtualDisplaysPage, VirtualDisplayEditorSheet, ConnectionSection}.swift; ResolutionPage ✗,
               ArrangementPage ✗, ProtectionLayoutsPage ✗, VirtualScreensPage ✗, ManagementPageParts ✗ (→ SettingsUI);
   ResolutionMenuItems, VirtualMenuItems, LayoutsMenuItems (MenuKit); PowerController (−sleep prevention, step 3),
   Kit ManagementIDs (step 3), Config/ConfigManagement (preventSleep decode + encode, ignored)
E: Displays/UI/{PIPPage, PIPEditorSheet (new), PIPMenuItems}.swift
B: Displays/UI/ConfirmChangesSection.swift (new; SafetyPage ✗), PanicCoordinator (MenuKit items), Config/ConfigSafety (M6),
   Kit Fingerprint (+matches)
A: Displays/UI/{AutomationsPage, HookEditorSheet, ActionEditorSheet}.swift (AutomationPage ✗); Switcher/{SwitcherController
   (sticky mode C8, HostSignals.switcherVisible), Settings (250 ms debounce), WindowSwitcherModule (MenuKit)}.swift;
   Core/ControlServer (ControlPeer via LOCAL_PEERPID, ControlHold, held-connection slot), Core/ControlCommandRegistry
   (ControlContext handler + old-signature overload, `holds:`, protected list), Core/CLIClient (holding replies),
   Core/EventLog (`record(_ event: AwakeLogEvent)`), Core/SelfTest (`--selftest-controls`);
   Kit KitBackup (awake section via AwakeConfig.exportable/importable applied after merge, awake.guards in safetyPaths;
   −sleepPrevention rows in step 3), KitControl (ControlResponse.holding, maxHeldConnections, protected words;
   −sleepPrevention in step 3)
F: also Displays/UI/DiagnosticsController.swift (eventLines filter by EventCategory.isExportedInDiagnostics)
```

Unique basenames are kept (e.g. `PowerMonitor` (J) vs `PowerController` (D); `KeyboardPage` (C) vs no other). Lead adds `.awake` to the extension-placement lint allowlist (`SharedExtensions.swift` stays the only shared home). Ownership collisions resolved: `SettingsShell` is H's alone; `SettingsTint`, `FeatureHighlight` and `StatusItemProvider` are lead types in `ModuleContracts` (code minor 12, B3); `MenuPresence` (KitModules) and `StatusItemPlan` (ConfigModules) have one declaration each, by the lead, and M owns only the plan function (consistency B1).

### 6.3 CI, lint and ratchet (lead, step 0)

- Linux job: new Kit files/tests build and run with Swift 5.10 (Foundation only; no Foundation formatters in Kit code that tests compare, N12).
- macOS job unchanged (Xcode 16.4, Swift 5 language mode, debug + tests + universal + helper self-test); Awake adds no helper, so no new self-test.
- `FeatureAvailability` moves from `DisplaysContracts.swift` to `Core/ModuleContracts.swift` (lead, step 0) so Awake doesn't depend on a Displays file.

**Ratchet** (code B1, R2-M1): `scripts/lint-legacy.tsv`, one row per (rule, path): `rule ⇥ path ⇥ count ⇥ permanent|step`; counts are **occurrences**, not lines. `lint.sh` fails on any violation of L1–L14 not covered by a row (count exceeded or path missing). A non-permanent row whose actual count is now lower only **warns** during steps 1–3; `lint.sh --strict` (CI from the step-3 exit on) fails on it. TEAMS.md gains an exception like the one for `stubs.tsv` (lead, step 0): a team may lower or delete ratchet rows **for paths it owns** in its own branch; rows are sorted by path so parallel edits touch different lines. `lint.sh --write-ratchet` generates the initial file at 871c10b in step 0 (≈ 54 `Slider(`/`Stepper(`, ≈ 125 `.font(.caption)`, 18 `NSMenuItem(`, 4 `objectWillChange.send()`, 7 `State(initialValue:`, `PowerController.swift` for L1). Permanent rows: `AppDelegate.swift` (L6, the app's main menu that Settings text fields need for Edit), `PIPWindow.swift` (L6, context menu), `ArrangementCanvas.swift` (L5, custom drag canvas). Deleted files (✗) and symbols (`ClosureMenuItem`, `CMenu`, `ManagedMenuItem`, `MenuSliderItem`, `MenuSlot.quick`) stay until the step-3 exit, where owners remove them after `grep` shows no callers (code M10). **Step-3 exit: only permanent rows remain.**

Lint additions:
- L1 `IOPMAssertionCreate`/`IOPMAssertionCreateWithProperties` only in `Awake/Core/AssertionManager.swift`; `IOPMAssertionRelease` there and in `Awake/Sources/ActivitySimulator.swift` (its DeclareUserActivity id, code M8); `IOPMAssertionSetProperty` banned (the swap replaces it).
- L2 `IOPMAssertionDeclareUserActivity`, `.post(tap:`, `CGEvent(mouseEventSource` only in `ActivitySimulator.swift`; there, mouse event types other than `.mouseMoved` are banned; `keyboardEventSource`, `CGEvent(keyboardEvent`, `CGEvent(scrollWheelEvent` banned everywhere in Awake.
- L3 (r1) dropped: rule 12 already bans spawning outside HelperSpawner everywhere (code minor 13).
- L4 Banned everywhere: `UNUserNotificationCenter`, `import CoreWLAN`, `import IOBluetooth`, `CLLocationManager`, the string literals `"pmset"` and `"sudo"`.
- L5 `(?<![A-Za-z])Slider\(`, `(?<![A-Za-z])Stepper\(`, `.font(.caption)` only under `Sources/Snaptic/SettingsUI/` (ratchet for the rest; the lookbehind keeps `ScrollSlider(` and `MenuSliderRow(` out; code R2-M1).
- L6 `NSMenuItem(` only in `MenuKit.swift`, `MenuSliderRow.swift`, `MenuSwitchHeader.swift` (ratchet).
- L7 `objectWillChange.send()` banned in `Displays/UI/`, `Awake/UI/`, `SettingsUI/`; `State(initialValue:` banned in Settings views (ratchet).
- L8 (r1's python anchor scan) replaced by Kit tests: anchors unique across `SettingsIndex*` tables, every `ControlMap` id exists; plus a DEBUG assertion in `SettingsPageScaffold` when `reveal` targets an anchor that never registered (code minor 13).
- L9 `record\(\s*\.awake` and the token `EventCategory.awake` banned outside `Core/EventLog.swift` (only `AwakeLogEvent` cases may be logged, through A's overload; security M6, code minor 5). A variable holding the category can still slip through; review checks it.
- L10 under `Awake/`: `queue: nil`, `addObserver(self, selector:` and `.publisher(for:` not followed by `.receive(on: DispatchQueue.main)` in the same statement are banned (code M6, minor 4); the `static let shared` (rule 7) and `passUnretained` (rule 10) rules extend to `Awake/`.
- L11 (r2: consent writers) withdrawn with the consent record (N10).
- L12 `.controlSize(.regular)` only in `SettingsUI/SettingsPageHeader.swift` (design B2).
- L13 `NSHostingView` banned in `Core/Menu*.swift`, `Core/StatusMenu.swift`, `Displays/UI/*Menu*.swift`, `Awake/UI/AwakeMenuRows.swift`, `Awake/UI/IndicatorController.swift` (design M11).
- L14 (N15, code R2-M7) under `Awake/`, `Core/Menu*.swift`, `Core/StatusMenu.swift` and any `*Menu*.swift`: `Timer.scheduledTimer`, `.scheduledTimer(`, `RunLoop.main.perform`, `receive(on: RunLoop.main)` and `RunLoop.main` as a Combine scheduler are banned; timers are created unscheduled and added with `RunLoop.main.add(_:forMode: .common)`.

**Stub kinds** (code M14): `gen-stubs.py` gains K15 Awake service (`AwakeServiceLifecycle` class, `init()`, no-op activate/deactivate), K16 criterion source (K15 + `static var kinds`, no-op `contribute`, `observe` backed by **one `ChangeFanout` per instance**, a stored `let`, code minor 13), K17 Awake controller (`AwakeFeatureController`, `id` from the extra column, no-op members, `availability` returns available), K18 settings page (`struct T: View` rendering `SettingsPageScaffold` with the title), K19 sheet (`struct T: View` with `@Environment(\.dismiss)` and a Done button), K20 Kit settings index table (`package enum T { package static let entries: [SettingsSearchEntry] = [] }`). SettingsUI components, MenuKit, `ConfigSlice`, `ControlServer`'s new types, and **every Kit type in §2, §4.1, §4.5, §4.8 and §5.2** (incl. `SettingsRoute`, `SettingsSearchEntry`, `ValueFormat`, `DisplaysConfigSection`, `DisplaysRestoreScope`, `ControlID`, `ControlMap*`, `MenuItemCatalog`, `MenuPresence`, `StatusItemPlan`; consistency B1) are `S` (special, hand-written by the lead from this plan's signatures, so step 0 references no team-owned type that doesn't exist yet) or `L`. About 125 new rows.

### 6.4 Delivery order

**Step-0 feasibility** (what step 0 can and can't contain; code B1, B2, M14, R2-M2):

| Item | Step 0? | Why |
|---|---|---|
| Stubs for every §6.2 file (K15–K20, S) with safe returns and exhaustive protocol members; a full stub `AwakeModule` and `case .awake` in `ModuleHost.module(_:)` | yes | only lead types are referenced |
| `SnapticModule` additions with **extension defaults**; `settingsPages()` kept | yes | `WindowSwitcherModule` (A) and `SettingsWindowHost.swift` (H) keep compiling (code R2-M2a) |
| `AwakeFeatureGraph` + tests, `KitModules` additions (`MenuPresence` with a real `legacyPlacement`, `ControlID`, `DisplayActionID.fShowPanel/.fIdentify`, `EventCategory.isExportedInDiagnostics`) | yes | lead-owned Kit; M2 needs `MenuPresence` now (code R2-M2c) |
| `StatusItemPlan` new defaulted fields (in `ConfigModules.swift`); `MenuLayout.swift` S stub whose plan function reproduces 0.2 placement | yes | one declaration, lead (consistency B1); M fills the logic in step 1 |
| `ControlMapLegacy.swift` generated from 871c10b by `gen-controlmap.py`, then frozen; `ControlMap`/`MenuItemCatalog` S stubs (empty tables); `ControlMapTests` added **skipped** until step 3 | yes | the 0.2 side must be captured before anything is deleted |
| `AwakeConfig` shell with all sub-config types as G/J **stubs** (`init()`, `sanitized()` identity) | yes | G/J fill them in step 1 |
| `restoringDefaults`, `exportable`, `importable` | stub only (identity / `AwakeConfig()`) | need G's and J's fields; G implements in step 2 |
| Migrations M2–M5, M10 + markers + tests; per-id module defaults; upgrader insertion of Awake disabled (ModuleHost and `upgradeDefaults()`); `Modules.disable.<id>` read | yes | lead Kit / host |
| M1 | no: stub `AwakeMigration.fromDisplays` returns `.nothing`; G implements in step 1, lead wires the hook in step 2 | needs G's trigger model |
| `changedSections` with `DisplaysConfigSection` (all cases); `observedSections` requirement + default; `ControllerRevision` per id; `ConfigSlice`; `DisplayRuntime` fields; `DisplayLiveControlling` | yes | lead types; defaults keep the ~21 conformers compiling |
| `DisplaysPageEnvironment` stops forwarding config | **no** (step-3 exit) | 23 legacy pages need it until they use slices (code R2-M2b) |
| `HostSignals`, `StatusItemProvider` + `CustomItemRow` | yes | lead |
| ControlServer peer credentials / held connections | no (A, step 1) | A's files (consistency M1) |
| `sleepPrevention` removal, MenuKit migration of old factories, file deletions, `settingsPages()` removal, old `register` handler overload removal | **no** (step 3) | would break 11+ files owned by C/D/F/A (code B2, M10) |
| Lint L1–L14 + ratchet generated from 871c10b; TEAMS.md ratchet exception | yes | ratchet makes it green on day 0 |

| Step | Who (parallel) | Exit criterion |
|---|---|---|
| 0 | Lead | Everything marked "yes" above; Info.plist; Package.swift links; CI green on Linux and macOS with the ratchet |
| 1 | G (Kit only, incl. `AwakeMigration`, `AwakeCommandGrammar`, `TaskQuiet`) ∥ J (sources incl. CPU top process, DiskIOSampler, ProcessWatch; Kit math) ∥ H (library, shell, search, Kit index types, `ControlMap`/`ControlCatalog` skeleton) ∥ M (MenuKit, MenuSliderRow, MenuSwitchHeader, StatusMenu with `MenuPresence` and the plan, MenuLayout logic, `MenuItemCatalog`) ∥ A (Switcher debounce, sticky mode, `switcherVisible`; **ControlServer `ControlPeer` + `ControlHold` + `ControlContext` handler, CLIClient holding mode, KitControl `holding`**; `EventLog` Awake overload; `--selftest-controls`) ∥ B (`Fingerprint.matches`) | Kit tests for G/J/H/M; sources activate/deactivate cleanly; shell shows all 7 roots with stub pages; StatusMenu renders existing sections through MenuKit; a test verb with `holds: true` stays connected until the client exits; green, merged |
| 2 | G (controllers, assertion, sessions incl. task kinds and `restore`, guards, triggers, automation incl. `awake hold`, indicator + `AwakeMenuRows`, `restoringDefaults`/`exportable`/`importable`; lead wires M1) ∥ lead (ToastPresenter: presenting/screensaver suppression, Recent Notices routing, `actions: [ToastAction]`; consistency m12) ∥ H (General, Permissions, About, Onboarding, Switcher page) ∥ M (Displays menu builder/blocks with every §4.8 menu location, Menu Bar page, Customize sheet) ∥ B (observability + M6 UI + `SafetyConfig` test; consistency M5) ∥ C/D/E (controller observability + revision bumps + MenuKit contributors; C `DisplayLiveController`) ∥ F (Displays root page, live controls, Details sheet, panel; `eventLines` filter) ∥ A (KitBackup awake section after merge) | Awake works end to end from the menu, hotkeys and CLI (`hold` both forms); menus per §5 incl. every opt-in item; Displays root page live; green, merged |
| 3 | G (Awake page, editors, history, Advanced, other-assertions section) ∥ J (Drives page, nudge path, Bluetooth Beta) ∥ C/D/E/A/B/F (sub-pages and Advanced groups per §4.3; duplicates per §4.4) ∥ **one coordinated merge** D + F + A + lead removing `sleepPrevention` (§2.13) ∥ H (search index assembly, highlight, `ControlMapTests` un-skipped and green, `ControlCoverage` check) ∥ lead (`DisplaysPageEnvironment` forwarding removed, `settingsPages()` and the old handler overload removed) ∥ all owners delete ✗ files and old factories after a caller grep | Every §4.3 page meets its budget; every slider is a `SliderSetting`; search finds every entry; `ControlMapTests` green and "Check Control Coverage" lists nothing with all features on; **ratchet holds only permanent rows** and CI runs `lint.sh --strict`; green, merged |
| 4 | Review | Adversarial reviews: security (§3, outside changes, pointer-movement and Drive Alive rules, hold peer checks), correctness (clock, guards, triggers, assertion swaps, task kinds, migration), UX (copy rules, budgets, light/dark/Increase Contrast, VoiceOver incl. the Awake menu), consistency (contracts vs code); fixes |
| 5 | Lead | README (Awake, CLI verbs and exit codes, **`awake hold` usage and the parent-shell pitfall** (§2.10), the hidden kill switches and how an organization deploys them with a configuration profile (N14), privacy, "why not lid-closed on battery", switching from Amphetamine Power Protect / Insomnia and cleaning up their sudoers rules and `SleepDisabled`, the 0.3 → 0.2 → 0.3 note), website, THIRD_PARTY_NOTICES (Insomnia, KeepingYouAwake if logic is followed closely; no code from APSL sources such as `caffeinate.c` — behavior only), Appendix hardware session, merge |

### 6.5 Done means

- Every In row of §1.1 and §1.5 implemented, reachable in Settings (and menu, hotkey and CLI where listed), wired to availability, kill switch, Safe Mode, diagnostics and `configDidChange`; idempotent start/stop; no stubs left.
- **Every 0.2 setting, button/action and menu item reaches its §4.8 home** (`ControlMapTests` green over the frozen 0.2 lists, `--selftest-controls` green, "Check Control Coverage" empty; reviewer walk-through of the table); every 0.2 opt-in menu item renders at its §5.2 location and can be shown or hidden in Customize Displays Menu.
- Awake holds at most one sleep assertion at any time (assert in debug + test via `AssertionManager` counters); `pmset -g assertions` shows only fixed-vocabulary strings (`Details` = manual/automatic).
- Pointer movement never acts for a CLI, rule, `launch`, restored or resumed session, or while locked or off console, whatever the config says; activity stops after `stopAfterHours` on Snaptic's clock; the 5% hard floor and critical heat end sessions with every config (HW-19). `awake hold` ends within 1 s of its client's exit or kill, and at its cap.
- Every Settings slider is a `SliderSetting` with live value field and reset; every slider in the menu is a `MenuSliderRow` with a live value; no slider in a submenu; no `NSHostingView` in a menu.
- Page budgets of §4.3 met; the duplicates resolved as in §4.4; no developer titles, camelCase ids or raw SF Symbol names visible.
- Migrations M1–M5 and M10 tested, each runs once (markers), M6 pinned by its `SafetyConfig` test; a 0.2 settings fixture (all features on) loads with no setting lost and a 0.3 → 0.2 downgrade still reads every legacy field.
- Lint passes with only permanent ratchet rows; CI green on all jobs; hardware list §6.7 run and Beta labels updated.

### 6.6 Kit unit tests (new)

- `AwakeFeatureGraph`: spec totality, resolve (kill switches incl. `unkillable` ignored, Safe Mode, requirements), `enabling` refuses unavailable, `requiredServices` per criterion kind and per dynamic need, activation order respects dependencies.
- `AwakeSession`/`AwakeClock`: start for every kind; remaining with continuous vs wall; `endWall` after a clock jump; `continuousEnd` for until-kinds; reboot expiry; clock jumps ±1 day don't move duration sessions; extend caps at 30 days; `canExtend` per kind; task caps; type-tagged Codable round trips and unknown types dropped; `overrideGuards`, `uiStartedInProcess`, `activitySince` never encoded and false/nil after decode; `source` survives a round trip; `hold(.connection)` never decodes, `hold(.process)` does; `isDirectUserAction` per source.
- `AwakeCountdown`: every boundary (3600, 3599, 61, 60, 59, 1, 0), "2h" on the hour, rounding up, `nextChange` never 0, spoken strings, `clock` 12/24 h.
- `AwakeDurationGrammar` / `AwakeCommandGrammar`: valid and invalid inputs, 7-digit / 2-decimal limits, "1e300h", huge digit strings, overflow, `idle`, `--pid` (≤ 1, negative, non-numeric refused), `--max` > 24 h refused, preset by index and name, locale-independent parsing, seeded fuzz never traps; `statusLine`/`statusJSON` incl. `pid` and the hand-formatted ISO time.
- `AwakeArbiter`: governing precedence; every display policy × locked × console × idle; deadline grace; `needsSwap` thresholds; disk-idle flag; 1,000 inputs at advancing times → `needsSwap == false` after the first.
- `AwakeGuards`: desktop/no battery, AC, floor crossing, the 5% hard floor with the user floor off and with Start Anyway, `reloaded(sameBoot:)`, hysteresis +5, two unreadable reads, adapter disconnect, LPM, serious warn-once (no end), critical end + cooldown, override only for battery/LPM, `allowsBackgroundWork`, `monotonic(over:)`, assertion-hold backoff.
- `AwakeTriggers` decode: lossy per entry, unknown kinds dropped, the nested `"criterion"`/`"condition"` shape (one `type` key per object), limits (32/8), sanitize (names, CIDRs, bundle ids, minutes, nudge on idle triggers → declare).
- `TaskQuiet`: each busy signal alone keeps the session (top process 50%, total 15%, disk 1 MB/s, network 50 KB/s), all quiet for 5 min ends it, unknown sample and wake reset the window, grace respected; single-threaded load on 12 cores stays busy (parity M2).
- `TriggerEngine`: every criterion kind true/false/unknown; negation; all/any with unknowns; start/end delays on the continuous clock; priority order and reorder; pause; guard hold; manual end with and without `resumeAfterManualEndMinutes`; suppressions expire; overnight schedules and week wrap; `scheduleBoundaries`; `summary` wording; seeded fuzz deterministic.
- `AwakeHistory`: cap, merge of short `.replaced` runs, prune, totals across given day starts.
- `AwakeSnapshot.sanitized(now:)`: other-boot session dropped, `until` suppressions dropped and `untilFalse` kept on a boot mismatch, guard memory reset except `warnedSerious`, `source` kept, connection holds dropped, out-of-range kinds dropped.
- `AwakeConfig`: `restoringDefaults` (pointer movement and volumes off), `exportable` (nudge → declare, drops, rules opt-in, hashes stripped), `importable` applied after `KitBackup.merge` with a hostile backup (nudge in presets[]/triggers[], volumes, floor 5: none survive, guards only tighten; security L5); activity switches and `effectiveOptions` clamping (consistency M2); `defaultDisplayPolicy(for:)`.
- `AwakeMigration`: no Displays settings; feature off with flags; feature on but Displays module off (not effective → disabled trigger); 1, 3 and 9 displays (split at 8); missing fingerprints; corrupt JSON; marker prevents a second run.
- `NetworkMath`: IPv4/IPv6 CIDR parse/match, invalid input, MAC normalization and hashing input, 64-bit byte deltas and resets, throughput with `lo0` excluded and `utun` + `en0` not double-counted. `CPUMath`: tick deltas incl. UInt32 wraparound, `processPercent`, `top`. `DiskMath`: deltas, resets.
- `ActivityPolicy` truth table (nudgeAllowed false for every non-UI or restored session, edge margin, the Snaptic-clock cap at 1 h and 8 h independent of input, screensaver, console, lock); `IdleMath` (nudge and declaration echoes ignored, real input kept); `DriveAlivePolicy` eligibility table (allowlist, boot container, DMG, non-local, BSD name) and `shouldWrite` (CLI source incl. restored CLI sessions, guards, first write).
- `VolumeUUIDKey` validation; `WeekdaySet` masking.
- `SliderMath`: clamp/snap, isDefault tolerance, hand formats and spoken units, parse with units and both decimal separators.
- `SettingsIndex`: ranking, synonyms, diacritic table, empty query, anchors unique across all `SettingsIndex*` tables, no entry text from config. `ControlMapTests` (§4.8): every `ControlMapLegacy` setting, action and menu item has a home, every home exists in `ControlCatalog`, reasons non-empty, catalog ids unique, the 46 `DisplayMenuItemID`s all present.
- `MenuLayout`: presence × awake active × displays active × shortcut bound × shown at rest → plan (custom items, compact section, `sharedActiveGlyph = governing && showShared`, footer in own menus, Snaptic item existence incl. "no module enabled" → item and "everything Don't Show" → none); `.hidden` fallback when the shortcut is unbound; `MenuPresence.allowed(for:)`; `legacyPlacement`; slider never "inSubmenu"; ordering; compact mode. `MenuItemCatalog`: every legacy id maps to a spec with `showHide`.
- `DisplaysConfig`: `changedSections` per field incl. every per-display subsection, M4/M5/M10 run once, legacy fields still encoded, `restoringDefaults(scope:)` per `DisplaysRestoreScope` leaves other scopes; `ModulesConfig` M2 (incl. Displays hide flag → Show When Active and the presence-absent round trip), M3, per-id defaults, `upgradeDefaults()` has Awake disabled, `newModuleCards` with an unknown id. `SafetyConfig` M6 pin.
- `KitControl`: `ControlResponse.holding` lossy decode and encode; `maxHeldConnections`. `EventCategory.isExportedInDiagnostics` false for `.awake`.

### 6.7 Hardware checks (first session; Beta labels depend on them)

| # | Check |
|---|---|
| HW-1 | Both assertion types on 14/15/26/27, Intel + Apple silicon; `pmset -g assertions` rendering of name/details; `CGSSessionScreenIsLocked` present in the session dictionary on 14–27 |
| HW-2 | (informational since r2: no SetProperty) timeout behavior of `TimeoutSeconds` across system sleep |
| HW-3 | Assertion swap (create-then-release) leaves no gap (display doesn't dim at the swap), incl. deadline re-arm |
| HW-4 | Screen saver and "require password after screen saver" with each assertion type and with `declare` |
| HW-5 | `IOPMAssertionDeclareUserActivity` vs `CGEventSourceSecondsSinceLastEventType` per type (does a declaration reset any type? does Slack/Teams go Away?); in declare mode the cap ends activity after 1 h and the Mac then idle-locks |
| HW-6 | ±1-pt nudge from a `.privateState` source: does `.hidSystemState` idle reset? not visible; edge skip; Accessibility-denied path; tagged events ignored by switcher hover |
| HW-7 | `keepOnWhileActive` downgrade/upgrade timing with real idle; lock-screen downgrade (C1) actually lets the display sleep |
| HW-8 | Lid close on battery / AC / desktop mode; `AppleClamshellCausesSleep` values; wake path ends/continues sessions correctly |
| HW-9 | CoreAudio `DeviceIsRunningSomewhere` on input causes no microphone prompt or orange indicator; HAL queue never blocks main |
| HW-10 | IOHIDDevice registry reads for Bluetooth input devices need no Input Monitoring |
| HW-11 | Router MAC via routing-table `sysctl` on 15/26/27 triggers no Local Network prompt; `NET_RT_IFLIST2` counters at 10 GbE |
| HW-12 | Removable Volumes prompt text and denial path; Drive Alive keeps a USB HDD spinning; eject not blocked; DMG and boot-container volumes refused |
| HW-13 | IOPS notifications on desktop Macs (no battery) and on battery percent changes; LPM notification queue |
| HW-14 | Status item `autosaveName`, `isVisible` KVO after ⌘-drag on 14–27; create/remove with Show When Active; countdown width stability; 26 "Allow in the Menu Bar" off; 27 overflow; notched MacBook with 20 items: the Snaptic active glyph is visible when the Awake item lands behind the notch (parity M5) |
| HW-15 | AppKit menu rows (MenuSliderRow, MenuSwitchHeader): alignment with native items, slider keyboard behavior, highlight drawn on arrow-key navigation, vibrancy on 26/27 material, `sectionHeader` look on 14/15/26/27; Option alternates on 27 and on 14.0–14.3 with title subtitles; arrow-key and VoiceOver navigation reach "Turn Off Keep Awake"; countdown and live slider values update while the menu stays open (`.common` mode) |
| HW-16 | Settings: `.searchable(placement: .sidebar)` + `ScrollViewReader` scroll in grouped `Form` on 14; `NavigationStack(path:).id(root)` back button; next-turn push; `.toolbar(removing: .sidebarToggle)`; fixed 715 pt width |
| HW-17 | `NumberField` commit on blur inside `Form`; Esc revert; VoiceOver values with units; small row switch size matches System Settings on 14–27 |
| HW-18 | Thermal states (via a load generator) produce the toasts/ends; `CLOCK_MONOTONIC_RAW` advances across sleep |
| HW-19 | `defaults write` of pointerNudge + a nudge preset, a Drive Alive volume, floor off and a forged `.menu` snapshot, while Snaptic is quit, stopped and running: no pointer movement for CLI, rule, restored or resumed sessions; the 5% floor still ends a session; Drive Alive writes only to eligible volumes |
| HW-20 | `NSMenuItem.subtitle` with the 15.5 SDK on 14.4, 15, 26, 27; fallback rows on 14.0–14.3 |
| HW-21 | `awake hold`: kqueue `EVFILT_PROC`/`NOTE_EXIT` + `proc_pidinfo` start time; `LOCAL_PEERPID` on the CLI socket; client killed with SIGKILL / Control-C / terminal closed → session ends within 1 s; forked child holding the fd doesn't keep it; `--pid $$` in a script, in a `make` recipe line (ends at once, toast) and with `.ONESHELL`; PID reuse refused |
| HW-22 | (r2 Keychain check withdrawn with N10) |
| HW-23 | `untilIdle` defaults (top process 50%, total 15%, disk 1 MB/s, network 50 KB/s, 5 min) on a 10-core Mac: stays during a single-threaded build/link phase, a 20 GB copy to an external SSD, a large download and an archive extraction; ends after each; not kept alive by root Spotlight bursts; `proc_pid_rusage` of same-user processes needs no prompt and costs ≤ 5 ms per sample |

### 6.8 Open questions

- **OQ-1** Settled in r2: Drive Alive ignores CLI-started sessions (strict).
- **OQ-2** Default for `keepOnWhileActive` minutes (30) and whether it should be the default display policy instead of `keepOn` (battery-friendlier). Default: `keepOn` for timed/indefinite sessions; task-bound kinds default to `maySleep`.
- **OQ-3** History on by default (S) vs opt-in. Default: on, local only, 90 days.
- **OQ-4** Whether the Displays root page keeps a Refresh rate pop-up when Resolution's pop-up already lists rates per mode. Default: keep (Apple precedent).
- **OQ-5** Glyph families: confirm `cup.and.saucer`, `eye`, `lightbulb` and their `.fill` variants on macOS 14 (tested in Kit by name list; runtime fallback `cup`).
- **OQ-6** Sticky-switcher menu item (C8) interaction with `releaseToSwitch` users; fallback is to omit the item.
- **OQ-7** Default for "After the screen has been locked for…" (security L5). Default: Never; product may choose 12 h.
- **OQ-8** `untilIdle` thresholds after HW-23. Default: top process 50% of one core / total 15% / disk 1 MB/s / network 50 KB/s / 5 min.
