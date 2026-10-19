# Snaptic 0.3 plan: Awake module, Settings redesign, Menu bar redesign

Status: **r2** (planning architect, after review round 1; r1 kept as `PLAN-r1.md`). Base: `feature/displays` == `main` @ 871c10b.
Normative like `docs/design/PLAN.md` (0.2): where this plan and 0.2 disagree, **this plan wins** for 0.3 scope; everything 0.2 says that this plan does not touch (safety framework, helpers, guard, transactions, R5 amendments) stays in force. Swift signatures in this document are the contract the lead writes as compiling stubs in step 0; once on the branch, the code wins over prose (R5 rule carried forward).

Inputs: `scratchpad/plan2/{awake-parity.md, power-apis.md, ui-audit.md, design-spec.md}` (cited as [AP], [PA], [UA], [DS] with section numbers).

## r2 changes

Resolves review round 1 (`review-r1-{parity,security,code,design}.md`). Every Blocker/High and Major is resolved; every Minor/Medium/Low is accepted except the two partial rejections marked **(partly rejected)**, whose reasons are in the row. Totals: parity 2 B + 7 M + 14 m + 3 extra notes resolved; security 2 H + 7 M + 6 L resolved; code 3 B + 14 M + 13 m resolved, 1 m partly rejected; design 2 B + 10 M + 9 m resolved, 1 M partly rejected.

| Finding | Resolution | Sections |
|---|---|---|
| parity B1 | New session kinds `untilIdle` ("Until Downloads and Tasks Finish": CPU < 15%, network < 50 KB/s for 3 min) and `whilePID` (`snaptic awake hold`, bound to the caller's parent via `LOCAL_PEERPID`); `awake start` without argument = 1 h, `indefinite` refused from the CLI; default preset + menu item; README recipe | N9, C10, §1.1, §1.2, §1.4, §2.3, §2.5, §2.10, §3.1, §5.3, §6.4 |
| parity B2 | New normative §4.8 control map (every 0.2 control, all 49 feature switches, the 0.2 menu) + `ControlMapTests` over the 0.2 fixture; Resolution options disclosure (slider kept, Quick Changes, Undo/Redo, favorites); Undo/Redo in the display submenu; remembered displays on Display Information; glyph tiles per module; Preview the selected window visible | §4.3, §4.8, §5.2, §6.5, §6.6 |
| parity M1 | `MenuPresence` is the only way to hide the Awake icon; style `.hidden` deleted; `indicator` is an internal capability (kill switch only) | §1.1, §2.2, §2.14, §4.4 #16 |
| parity M2 | Default Awake presence Own Icon When Active (C11); Snaptic icon shows an active variant while Awake governs and no Awake icon is visible; a session is never invisible (N11); Don't Show only with a bound shortcut | N11, C11, §4.3 Menu Bar, §5.2 |
| parity M3 | Snaptic item exists only when needed (Kit plan rule); otherwise every own/custom menu ends with native Snaptic Settings… and Quit, and Awake's menu gains Recent Notices | §5.2, §5.3 |
| parity M4 | Native "Turn Off Keep Awake" item while active; arrow-key/VoiceOver check added to HW-15 | §5.1, §5.3, §6.7 |
| parity M5 | `AwakeSessionsConfig.defaultOptions`; `AwakePreset.options` optional ("Use default"); task-bound kinds default to May sleep | §2.14, §4.3 Awake, OQ-2 |
| parity M6 | "Show in the menu" removed from Display Details; "Menu visibility…" link to Customize Displays Menu | §4.3, §4.4 #4 |
| parity M7 | Header switch labelled "Use Awake" with help; session control is buttons only (Keep Awake / Extend ▾ / Turn Off); confirmation before turning the module off | N5, §2.12, §4.3, §4.4 #15 |
| parity m1 | No DNS criterion; reason corrected (TCC-free, but subnet + router already identify a network) | §1.3 |
| parity m2 | Router criterion titled "Connected to this network" and named the SSID substitute | §1.1, §1.3, §2.7, §4.3 |
| parity m3 | Lock-screen deferral reason corrected (public API exists; can't verify immediate password) | §1.2 |
| parity m4 | Hold-to-end Excluded; 8-hour reminder toast for indefinite sessions In | §1.3, §1.4, §2.5 |
| parity m5 | Add items only for timed and capped kinds; "Add Time…" (⌥ alternate, Settings Extend ▾); +2 h claim removed | §1.1, §4.3, §5.3 |
| parity m6 | Task-bound kinds carry an optional cap that Add extends; replacing one shows "Replaced “…”." | §2.3, §2.5 |
| parity m7 | "Ended at 3:12 AM: battery below 20%." in menu and Settings for 12 h, plus Recent Notices | §2.5, §2.11, §4.3, §5.3 |
| parity m8 | Toasts while presenting (mirroring or full-display window) go to Recent Notices | §2.5 |
| parity m9 | "Start Anyway" is a toast button, never a menu item | §2.5, §5.3 |
| parity m10 | Menu trigger rows read-only (click opens Settings, ⌥ "Turn Off …"), active + ≤ 4 others, then Edit… | §5.3 |
| parity m11 | App-icon rows are a stated exception (own group); compact section keeps apps in their own submenu | §5.1, §5.4 |
| parity m12 | General's reset is "Reset All Settings…" (destructive) in General › Advanced | §4.3 |
| parity m13 | Relaunch always shows Settings; hidden-icon warnings kept on Menu Bar | §4.3, §5.5 |
| parity m14 | Cut: automatic-session icon, show seconds (last minute only), end on serious heat (toast kept), activity interval (60 s); added "Menu bar icon ›" link and synonyms (lid, clamshell, jiggle, prevent sleep, screen saver) | §1.3, §4.1, §4.3 |
| parity extra | M1 migrates only **effective** sleep prevention; Advanced reports system-wide `SleepDisabled` + README cleanup note; Restore All Displays top-level while a confirmation is pending | §1.1, §4.3, §4.6, §5.2, §6.4 |
| security H1 | `ConfigStore(key:admit:)` admits before any assignment, at load and on outside change; Keychain consent record (`AwakeConsent`, UI-only writes, UI-fail, per signing identity); read failure → features off | N10, §2.11, §2.14, §3.2, HW-19, HW-22 |
| security H2 | Snapshot admitted too: source forced `.restored`, override never persisted, nudge → declare without consent, kind clamped, guards evaluated before restore | §2.3, §2.5, §2.14 |
| security M1 | `batteryGuard`/`thermalGuard` unkillable; floor lowering/off consent-protected and monotonic on import; critical heat evaluated directly; Drive Alive and activity gated by `allowsBackgroundWork` in every mode | §2.2, §2.6, §2.9, C9 |
| security M2 | Lock/screensaver notifications are hints; session dictionary read before every arbitration and activity action; ScreenSaverEngine frontmost check | §2.4, §2.8, §2.9, §3.3 |
| security M3 | `extend` refused while nudging; OQ-1 settled strict (Drive Alive ignores CLI sessions); first Drive Alive write only after a UI action | N1, §2.9, §2.10, §3.1 |
| security M4 | Activity stops 1 h (Advanced 1–8 h) after the last real input; unavailable under forced screen-lock prefs; forced `Awake.disable.*` keys honored (disable only) | §1.1, §2.2, §2.9, §3.3 |
| security M5 | Drive Alive write via verified dirfd (`fstatfs` mount + fs allowlist, `fgetattrlist` UUID, `openat`, same `st_dev`); DiskArbitration for disk images; boot container excluded; `unlinkat` of 8-byte file only | §2.9, §3.4 |
| security M6 | Closed `AwakeLogEvent` enum + lint L9; diagnostics carry counts, not timestamps; `Details` only manual/automatic; other-assertions list never in logs/diagnostics/CLI | §2.4, §3.6, §6.3 |
| security M7 | Typed `exportable`/`importable` (array fields handled), guards monotonic and in `safetyPaths`, trigger export opt-in checkbox | §2.14, §3.6, §4.3 General |
| security L1 | Nudge skipped within 2 pt of an edge; `IdleMath` excludes nudge echoes from real idle | §2.9 |
| security L2 | Toasts suppressed while the screensaver runs and off console | §2.5 |
| security L3 | 1/s limit for start/hold/stop/extend; short `.replaced` history runs merged; CLI-start toast ≤ 1 per 10 min | §2.5, §2.10, §2.14, §3.1 |
| security L4 | Grammar: ≤ 7 digits, ≤ 2 decimals, finite/range checks before conversion, overflow-checked math, fuzz | §2.3, §6.6 |
| security L5 | "After the screen has been locked for…" (default Never, OQ-7); user switch ends after 1 h off console by default | §2.6, §2.12, §4.3, §6.8 |
| security L6 | Restore Defaults/Reset turn protected features off; `protectedSettings` words; Start Again uses a local bundle id; index holds no user strings (test) | §2.10, §2.14, §3.2, §3.6, §4.6 |
| code B1 | Lint ratchet `scripts/lint-legacy.tsv` (fails on new violations and on stale rows); permanent rows listed; step-3 exit = permanent only | N13, §6.3, §6.4, §6.5 |
| code B2 | `sleepPrevention` stays until one coordinated step-3 merge (D + F + A + lead) | §2.13, §6.2, §6.4 |
| code B3 | `StatusItemProvider` + `StatusItemPlan.custom`; IndicatorController owns the Awake item; StatusMenu counts it; `AwakeHost` defines host services | §2.11, §5.2, §5.3 |
| code M1 | Plan carries an absolute continuous deadline; re-arm by create-then-release when it moves > 5 s (no SetProperty, HW-2 moot); `verify` via `IOPMAssertionCopyProperties` + one re-create; trigger assertion hold with backoff | §2.4, §2.6, §6.3 L1 |
| code M2 | Hysteresis in memory on the continuous clock; only suppressions, `pausedUntil` (snapshot only) and guard memory persisted, on change | N2, §2.7, §2.14 |
| code M3 | Migration markers; legacy fields declared and encoded until 0.4; `placement` written from presence; `newModuleCards` decoded as strings; M1 `save(force:)` and ≤ 8 displays per trigger; M5 semantics fixed | §4.6, §5.2 |
| code M4 | ModuleHost inserts Awake disabled for upgraders before M1; per-id defaults; tests updated | C7, §2.13, §4.6 |
| code M5 | Merged with security H1 (Keychain consent instead of an HMAC key; hook installed at store creation) | §2.14, §3.2 |
| code M6 | Every Awake observer uses `queue: .main` (lint L10); `NSTimeZone.resetSystemTimeZone()` + `Calendar.autoupdatingCurrent` | §2.1, §2.8, §2.12, §6.3 |
| code M7 | Multicast `observe(_:_:)` + `ChangeFanout`; `AwakeDynamicNeeds` (apps, idle, taskQuiet); synchronous `arbitrate()`, only `step` coalesced | §2.1, §2.2, §2.5, §2.7, §2.8 |
| code M8 | Nudges from a private-state source; idle from `.hidSystemState` via `IdleMath`; nudge rejected on idle triggers; ActivitySimulator may release its declaration | §2.7, §2.9, §6.3 L1 |
| code M9 | `HostSignals.isTerminating` (quit keeps the snapshot, disable clears) and `launchSessionStarted` | §2.5, §2.11, §2.12 |
| code M10 | Deletions only at the step-3 exit after a caller grep, tracked in the ratchet | §5.1, §6.2, §6.3 |
| code M11 | N12: Kit formats by hand from explicit inputs; calendars/DST resolved in the app (`untilClock`, schedule boundaries, history day starts) | N12, §2.3, §2.7, §2.14, §4.1 |
| code M12 | Per-id `ControllerRevision`, `ConfigSlice`, `DisplaysPageEnvironment` stops forwarding config, `DisplayLiveControlling` mailbox, per-display subsections, `observedSections` default | §4.5 |
| code M13 | Compile fixes: hand-written `<` and `WeekdaySet.init(rawValue:)`; hand-written type-tagged Codable for associated-value enums; `GuardMemory` Codable; snapshot/history are `ConfigModel`; `VolumeUUIDKey`, `ActivityInputs` defined; `SettingsRoot` `==`/`hash`; `PickerOption.id`; `@escaping` row; `step` returns `nextDeadline`; `AwakeRefusal` in Kit | §2.3, §2.6, §2.7, §2.9, §2.14, §4.1 |
| code M14 | Step-0 feasibility table; `admitted`/`restoringDefaults` move to G step 2; stub kinds K15–K20 | §4.6, §6.3, §6.4 |
| code m1–m2 | `CLOCK_MONOTONIC_RAW` stated, `ContinuousClock` avoided; end time shown as wall + remaining (`endWall`), stored `endsAt` removed | §2.3 |
| code m3 | `NavigationStack(path:).id(root)`, next-turn push, scaffold-owned `ScrollViewReader`, highlight after sheet presentation, `settingsLastRoute` key | §4.1 |
| code m4–m5 | AppKit switch header; `isVisible` KVO ignores own changes, re-created items set visible | §5.1, §5.3 |
| code m6–m7 | CoreAudio typed listener blocks on a private queue; `NET_RT_IFLIST2`/`if_data64` | §1.1, §2.8 |
| code m8–m9 | `Fingerprint.matches` (B); `enabling(…available:)` | §2.2, §2.7, §6.2 |
| code m10 | Kit returns schedule boundaries; app uses `Calendar.nextDate`; Ticker capped at 15 min | §1.1, §2.7 |
| code m11 | `.none` cases renamed (`.inactive`, `.off`) | §2.3, §2.4, §2.11 |
| code m12 | `SettingsShell` H only; `SettingsTint`, `FeatureHighlight` in `ModuleContracts` | §4.1, §6.2 |
| code m13 | L3 dropped (rule 12); rules 7/10 extended to Awake; L8 replaced by Kit tests; `import notify`; CPU count computed | §2.8, §6.3 |
| code m14 **(partly rejected)** | Drive Alive first-open coalescing and the `module disable` help text accepted. **Persisting "Start Anyway" rejected**: security H2 requires that a restored session re-checks guards; a relaunch on low battery ending the session is the safe outcome | §2.3, §2.5, §2.9, §2.10 |
| design B1 | "Use Awake" header switch; status row buttons only | N5, §4.3 |
| design B2 | Row switches at the form default size; only the header is `.regular` (lint L12); subordinate = 20 pt indent | §4.1, §6.3, HW-17 |
| design M1 | Budget rule defined (settings ≤ 8, total ≤ 12, sheets ≤ 25; hub exception) and honest per-page counts; General module rows removed | §4.2, §4.3 |
| design M2 | One presence pop-up per module; "both" removed; compact section automatic when Awake has no visible icon | C2, §4.3, §5.2 |
| design M3 | Default Own Icon When Active; onboarding line | C11, §4.7 |
| design M4 | Display Information is a sub-page; other-assertions list inline in Awake Advanced; Copy Settings From pull-down; Forget uses an alert; no sheet opens a sheet | §4.3 |
| design M5 | Footer = Advanced… + (?); Restore Defaults in the Advanced sheet footer; Keyboard Shortcuts… as a button row | §4.1, §4.3 |
| design M6 | Normative SliderSetting layout (field is the value, reset slot, ViewThatFits fallback, ticks, keyboard) | N4, §4.1 |
| design M7 **(partly rejected)** | "1h 42m"/"42m"/"42s", `button.title` + monospaced-digit font, no colored attributed title, symbol configuration all adopted. **`DateComponentsFormatter` rejected** for Kit (N12/code M11: ICU output differs between Linux corelibs and macOS); the hand formatter produces the same strings | §2.3, §5.3 |
| design M8 | Accessibility label and tooltip refreshed at every countdown change | §1.1, §5.3 |
| design M9 | Two navigation groups + Display Information; "Hardware Controls", "Hardware contrast", "Keyboard"; root Advanced cross-cutting only (25); Brightness methods → Brightness › Advanced; Connection and Match text size → Display Details; Display Details… button row | §4.3, §4.4, §4.8 |
| design M10 | Awake menu per mockup M3 (prepositions in titles, Keep Display On always present, triggers collapsed, guard wording, re-choosing restarts) | §5.3 |
| design M11 | AppKit-only custom rows (lint L13); `NSMenuItem.subtitle` with 14.0–14.3 fallback; HW-20 | §5.1, §6.3, §6.7 |
| design m1–m3 | Images all-or-none per section; display submenu ≤ ~12 without color toggles; no Awake header in the Snaptic menu, "Snaptic Settings…", "Turn On Thumbnails…" as an action | §5.1, §5.2 |
| design m4 | Quit visible when the Snaptic item is absent | §5.3 |
| design m5 | Glyphs cup / eye / lightbulb; one Show pop-up (Icon / Time Remaining / End Time) | §2.14, §4.3 |
| design m6 | Menu Bar graphite tile; window fixed 715 pt, vertical resize only | §4.1, §4.2 |
| design m7 | Copy adopted (Keep the display on, Appear active, Move the pointer slightly, End sessions automatically, CLI help without Raycast) | §2.9, §4.3 |
| design m8 | Unavailable/precondition/empty states specified | §4.1, §4.2, §4.3 |
| design m9 | PerDisplayPicker ≤ 4 tiles else pop-up, shared selection, AX label | §4.1 |

---

## 0. Summary and decisions

Snaptic 0.3 does three things:

1. **Awake** (new module, `ModuleID.awake`): a free, MIT, public-API-only replacement for Amphetamine and Insomnia. Manual sessions (indefinite, duration, until a time, while an app runs, until downloads and tasks finish, while a process runs), user-defined session types (presets), automatic sessions (triggers with 12 TCC-free criterion kinds, priorities, per-trigger options), battery/thermal/Low Power Mode guards that nothing outside the UI can weaken, activity simulation, Drive Alive, its own menu bar indicator (shown while active by default) with optional countdown, hotkeys and `snaptic awake …` CLI (including `awake hold` for scripts). One named IOKit power assertion, swapped by type, with absolute-deadline `TimeoutActionRelease` backstops. Displays' `sleepPrevention` moves here.
2. **Settings redesign**: one SwiftUI component library (`Sources/Snaptic/SettingsUI/`), a new information architecture (sidebar 31 rows → 8; default visible settings controls ~245 → ~60, §4.3 counts), every option explained, every 0.2 control mapped to a 0.3 home (§4.8), the 14 duplicates removed, expert options behind **Advanced…**, settings search, and the live-update root causes fixed in the architecture (observable per-display runtime, controller revisions, drag-local slider state, throttled commits, per-section config observation and fan-out).
3. **Menu bar redesign**: one menu item factory (`MenuKit`), one header style, AppKit-only custom rows (sliders, switch headers) with live values, no sliders in submenus, one level of submenus, "Settings…" last, one presence pop-up per module; an Awake status item (shown while active by default); the Snaptic menu shows a compact Awake section whenever Awake's icon isn't shown, unless Awake is set to Don't Show.

Priorities (0.2 order kept, Awake rows added): (1) never leave the user without a usable display, keyboard or way back; (2) nothing Snaptic does lets another process use Snaptic's permissions or see data obtained with them; (3) never damage a monitor **or drain a battery to shutdown** (Awake's thermal guard and battery floor have no kill switch and can be weakened only from the UI); (4) parity; (5) polish.

### 0.1 Decisions taken here (normative)

| # | Decision | Why |
|---|---|---|
| N1 | CLI **may start** Awake sessions: closed grammar, guards apply, never pointer movement, never Drive Alive (strict, OQ-1 settled), never an unbounded session (`awake start` with no argument = 1 h; `awake hold` is bound to a live process), `extend` refused while the governing session nudges | §3.1: a same-user process can already hold the same assertion with `caffeinate`; nothing that uses Snaptic's TCC grants is reachable |
| N2 | Duration sessions run on the **continuous clock** (`CLOCK_MONOTONIC_RAW`, counts sleep, immune to clock changes); "Until" sessions are absolute wall instants; a reboot ends every session; trigger hysteresis is in-memory continuous-clock state and is never persisted | Predictable; matches Amphetamine; no recovery machinery; no defaults write per engine step |
| N3 | One **governing** source at a time: the manual session if any, else the highest-priority active trigger | Amphetamine's priority model; one assertion; one indicator reason |
| N4 | Every Settings slider gets a typed value field and a reset glyph; the field **is** the live value (no separate value label) | Explicit requirement; [DS] layout in §4.1 |
| N5 | All modules always appear in the sidebar; each module page has a header switch (Wi-Fi pattern) whose accessibility label and tooltip are "Use <Module>"; session-level actions are **buttons**, never a second switch | [DS] §1.2; design B1, parity M7 |
| N6 | Displays' 16 sidebar pages become **one** sidebar row with sub-pages in a `NavigationStack` | [DS] §1.1, [UA] §2.1 |
| N7 | Everything about the menu bar (presence per module, icons, countdown, Displays menu customization) lives **only** on the Menu Bar page | Removes duplicates 4, 13 and the Awake split |
| N8 | Displays feature switches live where the feature is used (sub-page header switch, section switch or Advanced › Use Snaptic for); the 47-switch Features page is deleted | [UA] §2.5 #4 |
| N9 | Two task-bound session kinds: **Until Downloads and Tasks Finish** (`untilIdle`: CPU and network quiet for 3 min) and **while a process runs** (`whilePID`, CLI `awake hold`) | Parity B1: downloads, builds and agents are a named journey |
| N10 | Awake settings that use Snaptic's TCC grants or lower a safety floor are **admitted** only against a Keychain consent record written by UI actions; admission runs before any value is assigned, at load and on outside changes, for config and runtime snapshot alike | Security H1/H2, code M5 |
| N11 | A running Awake session is never invisible: if no Awake icon is visible, the Snaptic icon shows its active variant; if no Snaptic icon exists either, the Awake icon appears for the session | Parity M2 |
| N12 | SnapticKit formats user-visible numbers, durations and clock times **by hand** from explicit inputs (`AwakeTextContext`), never through Foundation formatters | Code M11: corelibs 5.10 and macOS ICU disagree; Kit tests run on both |
| N13 | Lint rules land in step 0 with a **ratchet** (`scripts/lint-legacy.tsv`) of known violations; a deleted file or symbol is removed only at the step-3 exit after a caller grep | Code B1, M10 |

### 0.2 Decisions to confirm (lead)

| # | Proposal (r2 wording) | Default if not confirmed |
|---|---|---|
| C1 | While the screen is locked, a `keepOn` session downgrades to system-only (display may sleep, Mac stays awake); Advanced option "Keep the display on while locked" | Adopt |
| C2 | Replace `MenuPlacementChoice` (shared / own / hidden) with `MenuPresence` = **In Snaptic Menu / Own Icon / Own Icon When Active (Awake only) / Don't Show**, one pop-up per module; `placement` keeps being written for 0.2 downgrades (r1's two-bool form is withdrawn: design M2) | Adopt (migration M2, §4.6) |
| C3 | Drop the right-click "quick menu" (right-click is not delivered on macOS 27 [PA] §8); its items move into **Display Tools ▸** | Adopt |
| C4 | Menu slider rows show a live value but no typed field or reset; every slider action and every Awake action also exists as a **native** menu item, shortcut or Settings control | Adopt |
| C5 | "Network activity above N KB/s" criterion (interface byte counters via `sysctl NET_RT_IFLIST2`, no connections, no TCC) replaces the TCC-gated Downloads-folder criterion; the same counters drive `untilIdle` | Adopt |
| C6 | Bluetooth criterion limited to Bluetooth **audio** devices (CoreAudio transport type) and Bluetooth **input** devices (IORegistry `IOHIDDevice` `Transport` property, never opened); Beta | Adopt |
| C7 | 0.2 → 0.3 upgraders get Awake **off** (ModuleHost inserts it disabled before M1 runs) unless M1 produced an enabled trigger from **effective** 0.2 sleep prevention; a one-time "New: Awake" card | Adopt |
| C8 | Menu item "Switch Windows ⌥⇥" opens the switcher in sticky mode (stays open until Return/Esc/click); new small Switcher capability (A) | Adopt; fallback: omit the item |
| C9 | Drive Alive runs only while an Awake session not started from the CLI is active, unless the user turns on "Even without a session"; battery floor and thermal guards gate it in **every** mode | Adopt |
| C10 | Default session from the UI (status-row button, menu, hotkey) = the default preset, **Until Turned Off** out of the box; from the CLI, `awake start` without an argument = 1 h | Adopt (Amphetamine parity for the UI; no unbounded CLI sessions) |
| C11 | Default Awake presence = **Own Icon When Active** (fresh installs and upgraders whose M1 trigger is on): one Snaptic icon at rest, the Awake icon beside it during a session | Adopt (design M3, parity M2) |

**Lead (r1):** C1–C10 adopted as proposed. **Lead (r2):** C2, C5, C7, C9, C10 re-worded as above and C11 added after review round 1; adopted unless the lead objects. OQ-1 is settled (strict); OQ-2…OQ-8 take their stated defaults until hardware testing says otherwise.

Open questions (need hardware or product input) are marked **[OQ-n]** and collected in §6.8.

---

## 1. Scope

Legend: **Def** = A always on with the module, S standard (on), O opt-in, X experimental, B beta tag. Amphetamine references are [AP] §1.x, Insomnia [AP] §2.x.

### 1.1 Awake: In

`AwakeFeature` (Kit, persisted raw values) and what each covers.

| Feature id | Covers | Def | Requires | Parity |
|---|---|---|---|---|
| `sessions` | Manual sessions: indefinite; duration (presets + custom h/m); until a clock time; while an app runs (picked from running apps, by bundle id, ends when its last instance quits; optional "at most" cap); **until downloads and tasks finish** (`untilIdle`: CPU < 15% and network < 50 KB/s for 3 min, 1 min start grace, optional cap); **while a process runs** (`whilePID`, CLI only); extend (+15 min / +1 h / Add Time… for timed kinds and capped task kinds; no-op items are not shown); end; replace; display policy per session (keep on / may sleep / keep on while I'm active, then may sleep after N min idle); end on sleep (opt), end on user switch (immediately / after 1 h / never), end after the screen has been locked for N h (opt); resume after Snaptic relaunch within the same boot; start a session at launch (opt); "why is my Mac awake" lid notice; 5-minute reminder; **8-hour reminder** for indefinite sessions; last non-user end shown for 12 h | A | — | Amph 1.2 (incl. "while downloading" via `untilIdle`), 1.3 display sleep, 1.4 manual-sleep / FUS ends, 1.8 reason text; Insomnia 2.2 timed sessions, chips, 30-day cap; `caffeinate -w` (CLI `hold`) |
| `presets` | Session types: up to 12 named presets (kind + optional options, nil = "Use default"), shown in the Awake menu in order; default preset; last custom value remembered | A | sessions | Amph "default duration", "Other Time" memory (1.2); Insomnia preset chips |
| `batteryGuard` | End below N% on battery (5–50%, default 20%); the floor can be lowered or turned off **only from the UI** (consent record, §3.2); end on adapter disconnect (opt); end on Low Power Mode (opt); two unreadable battery reads on battery → end; trigger restarts suppressed until cleared (+5% hysteresis or AC) | A | — | Amph 1.4; Insomnia 2.5 floor and unreadable rule |
| `thermalGuard` | `.critical` → end all sessions and stop Drive Alive, pause automatic sessions 10 min; `.serious` → one-time toast (no setting) | A | — | Insomnia 2.5 |
| `indicator` | Internal capability (kill switch only, not a user feature): Awake's own status item; **Show: Icon / Icon and Time Remaining / Icon and End Time**; glyph family cup / eye / lightbulb (outline idle, `.fill` active); seconds only in the last minute; VoiceOver label and tooltip refreshed at every countdown change. Whether the item exists is `MenuPresence` alone (§5.3) | A | — | Amph 1.8 (no custom images); Insomnia 2.6 countdown |
| `triggers` | Automatic sessions: ≤ 32 triggers, each ≤ 8 criteria, All/Any, negation, order = priority, per-trigger session options, start delay, end delay (hysteresis), re-activation after manual end, "Pause automatic sessions for 1 h / until tomorrow" | O | sessions | Amph 1.5 (all criteria except SSID and the Cisco VPN brand; DNS servers covered by subnet + router) |
| `activity` | "Appear active": `IOPMAssertionDeclareUserActivity` every 60 s while a session runs, the screen is unlocked and on console (read from the session dictionary, §2.9), the user has been idle ≥ 60 s, the displays are awake, and the last **real** input was < 1 h ago (Advanced: 1–8 h); unavailable when the organization forces screen-lock settings | O | sessions | Amph 5.0 cursor movement (closest TCC-free equivalent) |
| `pointerNudge` | "Move the pointer slightly": a 1-pt mouse-moved event and back, posted from a private event source with `CGEvent`, only with Accessibility, same conditions as `activity`, never within 2 pt of a display edge, never keyboard or clicks; consent-protected (§3.2) | X | activity | Amph 5.0 "Move the mouse cursor periodically" |
| `driveAlive` | Per external volume opt-in (consent-protected); tiny periodic write + `F_FULLFSYNC` to `/<volume>/.snaptic-keepalive` via a verified directory fd (§2.9); interval 30–600 s (default 120); `PreventDiskIdle` while active; only during non-CLI sessions unless "Even without a session"; battery floor and thermal guards apply in every mode | O | — | Amph 1.6 |
| `history` | Local history (≤ 500 entries, 90 days; entries < 60 s that ended `.replaced` are merged), today/7-day totals, "Start Again" (app sessions keep their bundle id locally), clear; never exported, never in diagnostics | S | — | Amph 1.10 statistics |
| `shortcuts` | Global hotkeys: Keep Awake on/off (default preset), Keep Display On (toggle), Start preset 1–4, Pause automatic sessions; all unbound by default | S | — | Amph 1.10 |
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
| `idle` (no input for ≥ N min) | IdleSampler | `CGEventSourceSecondsSinceLastEventType(.hidSystemState, anyInput)` with Snaptic's own nudges excluded (§2.9), 10 s period while used | none | Amph 4.1.5 |
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
| Process-name criterion for faceless processes (`proc_listallpids`) | `whilePID` (`awake hold`) covers the agent and build case for 0.3; a standing rule needs a polling budget |

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
| Allow display sleep; toggle mid-session by hotkey | `AwakeDisplayPolicy`; "Keep Display On" menu toggle; hotkey |
| Screen saver / screen-saver delay | Deferred ([HW-4]) |
| Closed-Display Mode | Excluded; menu explains the native route (external display + power) |
| Move cursor periodically | `activity` (default, no TCC) + `pointerNudge` (X, Accessibility) |
| Lock screen after inactivity | Deferred |
| End on low battery / adapter disconnect / manual sleep / FUS | `batteryGuard`, `sessions` behavior options |
| Triggers: unlimited, priority, names, AND/OR | `triggers` (≤ 32, order = priority, All/Any + per-criterion negation) |
| Criteria: displays, USB, Bluetooth, app, battery/power, IP, SSID, DNS, VPN, audio, drive, CPU, idle, schedule | All except SSID (router substitute) and DNS (subnet + router); Bluetooth partial (C6) |
| Re-activate a manually ended trigger session after a time | `resumeAfterManualEndMinutes` |
| Drive Alive per drive + interval | `driveAlive` |
| Menu bar icon styles, active/inactive images, time remaining, 12/24 h, seconds | `indicator` (curated families, outline vs fill, time remaining or end time in the system's 12/24 h setting, seconds in the last minute) + presence "Own Icon When Active" |
| ⌘-click quick start | Hotkey + status-row button (status item clicks always open the menu on 14–27) |
| Notifications, sounds, reminders | Toasts ("5 minutes left", "8 hours", "ended: battery low") + menu state + Recent Notices; no sounds |
| AppleScript, statistics, debug mode | CLI; `history`; Awake diagnostics in the shared report (counts only) |

Insomnia → Snaptic: timed sessions and chips (`presets`), 30-day cap (same), battery/thermal floors (`batteryGuard`, `thermalGuard`), countdown in the bar (`indicator`), "extend" reminder (toast at 5 min left with **Extend 1 Hour**), soft reminder for indefinite sessions (toast after 8 h with **Turn Off** / **Keep Going**), sleep-disabled-by-another-process detection → "Other apps keeping your Mac awake" (+ `SleepDisabled`). Everything pmset/journal/backstop-based is unnecessary: assertions die with the process ([PA] §1.2).

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
       cpu         CPUSampler             10 s average
       idle        IdleSampler            real (nudge-excluded) HID idle seconds, last real input
       network     NetworkMonitor         IPv4/IPv6 addresses, router hash, VPN, 64-bit throughput
       bluetooth   BluetoothPresence      BT audio + BT HID presence (Beta)
       activity    ActivitySimulator      DeclareUserActivity / pointer nudge
       driveAlive  DriveAliveService      keep-alive writes on a private serial queue
     Controllers (one per AwakeControllerID; G unless noted)
       sessions    SessionController      manual session lifecycle, presets, task kinds, arbitrate(), assertion plan
       guards      GuardsController       battery/thermal/LPM/sleep/FUS/lock policies
       triggers    TriggerController      criterion facts → TriggerEngine.step → cached top trigger
       activity    ActivityController (J) drives ActivitySimulator from runtime state
       driveAlive  DriveAliveController (J)
       indicator   IndicatorController    own status item (via AwakeModule's StatusItemProvider), countdown, glyphs, menu (AwakeMenuBuilder)
       history     HistoryController      records ends, totals
       automation  AwakeAutomation        hotkeys + CLI verbs
```

Everything is `@MainActor` except `DriveAliveService`'s I/O queue, `AudioMonitor`'s HAL queue and the C callbacks (IOKit, CoreAudio, SCDynamicStore, CG reconfiguration), which use `CallbackTarget` and hop with `MainActor.assumeIsolated` from main-queue delivery (`IONotificationPortSetDispatchQueue(port, .main)`, `SCDynamicStoreSetDispatchQueue(store, .main)`, `notify_register_dispatch(…, .main)`); CoreAudio listeners run on AudioMonitor's serial queue and publish with `DispatchQueue.main.async`. **Every `NotificationCenter`/`DistributedNotificationCenter`/`NSWorkspace` observer in Awake passes `queue: .main`** (lint L10: `queue: nil` banned under `Awake/`; `thermalStateDidChangeNotification` and `NSProcessInfoPowerStateDidChange` post on arbitrary queues). Timers are added in `.common` mode with ≥ 10% tolerance; `Timer` doesn't count sleep, so wake re-checks stay. No `static let shared` and no `passUnretained` outside `CallbackTarget` in Awake (lint rules 7 and 10 extended to `Awake/`). EventLog category `.awake` (lead adds), written only through `AwakeLogEvent` (§3.6).

**Apply order** (same as Displays §3.6): resolve effective features → required services = `AwakeFeatureGraph.requiredServices(effective:criteria:dynamic:)` (features ∪ criterion kinds used by enabled triggers ∪ `dynamic` needs: `apps` while a whileApp session runs or a picker is open, `idle` while `keepOnWhileActive` governs, `taskQuiet` (cpu + network) while an `untilIdle` session runs) → stop emptied controllers → deactivate unneeded services (reverse) → activate needed services (in order) → start new controllers → notify the rest. A criterion source that isn't needed costs nothing: no notification ports, timers or listeners.

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
    case assertions, power, system, apps, displays, usb, volumes, audio, cpu, idle, network, bluetooth, activity, driveAlive
}
/// Services a running session or open UI needs beyond features and trigger criteria (code M7).
package struct AwakeDynamicNeeds: OptionSet, Hashable, Sendable {
    package let rawValue: UInt8
    package init(rawValue: UInt8) { self.rawValue = rawValue }
    package static let apps = AwakeDynamicNeeds(rawValue: 1 << 0)       // whileApp session, app picker open
    package static let idle = AwakeDynamicNeeds(rawValue: 1 << 1)       // keepOnWhileActive governs
    package static let taskQuiet = AwakeDynamicNeeds(rawValue: 1 << 2)  // untilIdle session: cpu + network
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
    package static let specs: [AwakeFeature: AwakeFeatureSpec]   // table below; total (tested)
    package static func spec(_ f: AwakeFeature) -> AwakeFeatureSpec
    package static func rawState(_ f: AwakeFeature, in raw: [AwakeFeature: Bool]) -> Bool
    /// Kill switches never remove these (security M1; tested with every kill switch set).
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
    package static let activationOrder: [AwakeServiceID]  // assertions, power, system, then sources, activity, driveAlive
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
| commandLine | standard | sessions | — | automation | — |

Kill switches: Bool keys `Awake.disable.<feature>` read once per start from the persistent domain (Displays R5.4 rule) **and** from forced managed preferences (`CFPreferencesAppValueIsForced` + `CFPreferencesCopyAppValue`, disable direction only: a forced `false` never enables anything). `unkillable` features ignore both. Safe Mode keeps manual sessions and guards (they are safe), removes triggers, activity, nudge, Drive Alive. **Managed screen lock** (`CFPreferencesAppValueIsForced("idleTime" / "askForPassword", "com.apple.screensaver")`) makes `activity` and `pointerNudge` unavailable with the reason "Your organization manages screen lock." (security M4).

`KitModules.swift` (lead) additions: `ModuleID.awake` (start order: windowSwitcher, displays, awake), `EventCategory.awake`, `AwakeActionID: RawRepresentable` (open, like `DisplayActionID`), `AwakeCriterionKind` (here so the graph can reference it):

```swift
package enum AwakeCriterionKind: String, Codable, CaseIterable, Sendable {
    case app, display, power, schedule, cpu, audio, idle, volume, usb, network, networkActivity, bluetooth
}
```

### 2.3 Session model (G, `SnapticKit/AwakeSession.swift`)

```swift
package enum AwakeDisplayPolicy: String, Codable, CaseIterable, Sendable {
    case keepOn            // PreventUserIdleDisplaySleep
    case maySleep          // PreventUserIdleSystemSleep; display follows System Settings
    case keepOnWhileActive // keepOn until real idle ≥ displayIdleMinutes, then maySleep; back on input
}
package enum AwakeActivityMode: String, Codable, CaseIterable, Sendable { case off, declare, nudge }

package struct AwakeSessionOptions: Codable, Equatable, Sendable {
    package var display: AwakeDisplayPolicy        // .keepOn
    package var displayIdleMinutes: Int            // 1...240, default 30
    package var activity: AwakeActivityMode        // .off; .nudge acts only when consented + pointerNudge effective, else .declare
    package init(display: AwakeDisplayPolicy = .keepOn, displayIdleMinutes: Int = 30, activity: AwakeActivityMode = .off)
    package init(from decoder: Decoder) throws     // lossy per field
    package func sanitized() -> AwakeSessionOptions
}

/// "Until Downloads and Tasks Finish" thresholds (parity B1).
package struct UntilIdleSpec: Codable, Equatable, Sendable {
    package var cpuBelowPercent: Int       // 15; 1...90
    package var networkBelowKBps: Int      // 50; 1...100_000
    package var quietSeconds: Int          // 180; 60...3_600
    package var graceSeconds: Int          // 60; 0...600 (not shown in the UI)
    package init(cpuBelowPercent: Int = 15, networkBelowKBps: Int = 50, quietSeconds: Int = 180, graceSeconds: Int = 60)
    package func sanitized() -> UntilIdleSpec
}

package enum AwakeSessionKind: Equatable, Sendable {
    case indefinite
    case duration(seconds: Int)                               // 60 ... AwakeClock.maxSessionSeconds
    case until(unixTime: Double)                              // absolute wall instant
    case whileApp(bundleID: String, maxSeconds: Int?)         // validated reverse-DNS, ≤ 255 bytes; optional cap
    case untilIdle(UntilIdleSpec, maxSeconds: Int?)           // ends when CPU and network stay quiet
    case whilePID(pid: Int32, startTime: UInt64, maxSeconds: Int)  // CLI only; startTime = proc start in µs; cap required
    package var isTimed: Bool { get }              // duration, until
    package var cap: Int? { get }                  // whileApp/untilIdle/whilePID cap
    package var isTaskBound: Bool { get }          // whileApp, untilIdle, whilePID
}
extension AwakeSessionKind: Codable {              // hand-written, type-tagged: {"type":"duration","seconds":5400}
    package init(from decoder: Decoder) throws     // unknown type → throws → session dropped (lossy container)
    package func encode(to encoder: Encoder) throws
}

package enum AwakeSessionSource: String, Codable, Sendable { case menu, hotkey, commandLine, settings, launch, restored }

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
    package var overrideGuards: Bool              // one-shot "Start Anyway"; NOT in CodingKeys: never persisted (security H2)
    package init(id: StableID, kind: AwakeSessionKind, options: AwakeSessionOptions, presetID: StableID?,
                 source: AwakeSessionSource, startedAt: Double, startedContinuous: Double, deadline: Double?,
                 bootSession: String, overrideGuards: Bool = false)
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

package enum AwakeUnavailableReason: String, Codable, Sendable { case featureOff, safeMode, managedByOrganization, notConsented }
/// Kit (code M13), so CLI exit mapping and UI copy are tested.
package enum AwakeRefusal: Error, Equatable, Sendable {
    case guardActive(AwakeEndReason)   // UI: toast with "Start Anyway" (battery/LPM only, never thermal, never CLI/trigger)
    case unavailable(AwakeUnavailableReason)
    case invalid                       // bad duration, app not running, pid not found or not ours
    case notAllowedFromCLI             // nudge preset, extend of a nudging session, indefinite from CLI
    case rateLimited                   // CLI start/hold/stop/extend > 1/s
    package var exitCode: Int32 { get }  // 4 for every refusal (0.2 CLI table), message from `text`
    package var text: String { get }
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
    package static let holdDefaultCapSeconds = 12 * 3_600       // `awake hold` without a duration
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
/// CLI and the "Until a Time or Duration…" field. "until 17:30" stays a clock request; the app resolves it with
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

Plan rules (tested): inactive → `.off`; `.keepOn` → `.display`, downgraded to `.system` when `screenLocked && !keepDisplayOnWhileLocked` (C1) or `!consoleActive`; `.maySleep` → `.system`; `.keepOnWhileActive` → `.display` while `realIdleSeconds < displayIdleMinutes·60`, else `.system`; `deadline = sessionEnd + timeoutGraceSeconds` for manual sessions with an end (duration, until, caps), nil otherwise (trigger sessions have no backstop timeout: they end by condition); `preventDiskIdle` = `driveAliveWriting`; the plan contains no relative times, so it is **stable while nothing changes** (tested: 1,000 identical inputs at advancing times produce one plan).

**AssertionManager** (G, `Awake/Core/AssertionManager.swift`) holds at most one sleep assertion and one `PreventDiskIdle` assertion:

```swift
@MainActor final class AssertionManager: AwakeServiceLifecycle {
    private(set) var current: AwakeAssertionPlan = .inactive
    private(set) var lastError: Int32?
    /// Idempotent. When AwakeArbiter.needsSwap: create the new assertion first (TimeoutSeconds = deadline − now,
    /// TimeoutAction = TimeoutActionRelease), then release the old one: no gap, no IOPMAssertionSetProperty (HW-2 moot).
    @discardableResult func apply(_ plan: AwakeAssertionPlan, now: ClockNow) -> Bool
    func releaseAll()
    /// Checks our assertion still exists with IOPMAssertionCopyProperties(id) != nil: on wake, on
    /// `com.apple.system.powermanagement.assertions.timeout`, and every 5 min while active. A vanished
    /// assertion is re-created once; only a failed re-create returns false.
    func verify(now: ClockNow) -> Bool
    func activate(_ context: AwakeContext, lifetime: Lifetime)
    func deactivate()
}
```
Creation uses `IOPMAssertionCreateWithProperties` with `AssertType`, `AssertName`, `Details`, `AssertLevel = 255`, and when a deadline exists `TimeoutSeconds` + `TimeoutAction = "TimeoutActionRelease"` ([PA] §1.2, §1.5). String literals, no CFSTR macros. A failed create (or failed re-create in `verify`) ends a manual session with `.assertionFailed` and toast "Snaptic couldn't keep your Mac awake. Try again, or restart Snaptic."; for a trigger session it sets an **assertion hold** in `GuardMemory` with backoff 30 s → 2 min → 10 min (one toast per hold, cleared by a successful create or a user start), so a failing create can't loop. The timeout is a **backstop** only: the app ends sessions itself at `remaining == 0`, 15 s before powerd would.

### 2.5 Session lifecycle (G, `SessionController`)

```swift
@MainActor final class SessionController: AwakeFeatureController {
    static var id: AwakeControllerID { .sessions }
    init()
    func start(_ kind: AwakeSessionKind, options: AwakeSessionOptions?, presetID: StableID?,
               source: AwakeSessionSource, overrideGuards: Bool) -> Result<AwakeSession, AwakeRefusal>
    func startPreset(_ id: StableID, source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal>
    func startDefault(source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal>
    /// CLI `awake hold`: pid already resolved and uid-checked by AwakeAutomation.
    func hold(pid: Int32, startTime: UInt64, capSeconds: Int) -> Result<AwakeSession, AwakeRefusal>
    func extend(by seconds: Int, source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal>
    func setKeepDisplayOn(_ on: Bool)          // governing session; trigger sessions: until it ends
    func end(_ reason: AwakeEndReason)         // manual session; trigger session → TriggerController.manualEnd
    func toggleDefault(source: AwakeSessionSource)  // hotkey; status-row/menu buttons call start/end directly
    /// Synchronous: reads the cached trigger top, guard memory, session facts and idle, computes
    /// governing + plan, applies it. Called by every path that changes an input (code M7).
    func arbitrate()
    // AwakeFeatureController members (§2.11)
}
```

Rules:
- At most one manual session. Starting a new one replaces the old (history entry `.replaced`); choosing the running preset again restarts its timer. Replacing a **task-bound** session shows the toast "Replaced “While Xcode is running”." (local UI only). Starting while a trigger governs makes the manual session govern; when it ends, the trigger (if still active) governs again with no gap, because `end` calls `arbitrate()` in the same turn and `TriggerController` coalesces only `step`, never arbitration.
- A tick (`Timer`, `.common`, fires at `AwakeCountdown.nextChange` or at expiry, whichever is earlier, tolerance 10%) recomputes `remaining`; at ≤ 0 the session ends `.timeUp`. Ticks never drive correctness alone: expiry is also checked on wake, clock change, unlock, menu open and every arbitration.
- **untilIdle**: while it runs, `taskQuiet` keeps CPUSampler and NetworkMonitor throughput active (5 s). The session ends `.tasksFinished` once CPU < `cpuBelowPercent` **and** throughput < `networkBelowKBps` have held continuously for `quietSeconds`, never before `graceSeconds` from start; unknown samples reset the quiet timer. Default display policy `maySleep`. Toast: "Awake ended: downloads and tasks finished."
- **whilePID**: `DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)`; at start and at restore `proc_pidinfo(pid, PROC_PIDTBSDINFO)` must return the stored start time (`pbi_start_tvsec·10⁶ + pbi_start_tvusec`) and `pbi_uid == getuid()`, else refuse (`.invalid`) or end `.processExited`. No process is spawned (lint rule 12 holds). Shown as "While a script is running" (no process name anywhere).
- whileApp: ends `.appQuit` when no running application has the bundle id (checked on terminate notifications and every arbitration); refuses to start if the app isn't running.
- Caps: task-bound kinds end `.timeUp` at their `deadline`; "Add 1 Hour" extends the cap (§5.3). `whilePID` always has a cap (default 12 h).
- **Reminders and toasts**: 5-minute reminder when a timed session that ran ≥ 15 min reaches 5 min left, "Awake ends in 5 minutes." with **Extend 1 Hour**; **8-hour reminder** once per indefinite manual session, "Awake has kept your Mac awake for 8 hours." with **Turn Off** / **Keep Going**; an end toast for every non-user end ("Awake ended: battery is below 20%." / "…: Xcode quit."; app names only in local UI); guard refusals from the UI show a toast "Battery is below 20%." with **Start Anyway** (battery/LPM only; never from a menu item click, which closes the menu); "Awake was started from the command line." at most once per 10 minutes. Toasts are suppressed while locked, while the screensaver runs, off console, and while **presenting** (any display in a mirror set, or the frontmost app has a window covering a whole display — `CGWindowListCopyWindowInfo` bounds and owner PID only); suppressed toasts go to Recent Notices. ToastPresenter changes are lead-owned (§6.2).
- **Last end**: after a non-user end, `runtime.lastEnd` shows "Ended at 3:12 AM: battery below 20%." in the Awake menu and Settings status row for 12 h (also a Recent Notices entry).
- **Persistence**: the manual session (without `overrideGuards`), trigger suppressions, `pausedUntil` and guard memory are written to `SnapticAwakeStateV1` (`ConfigStore<AwakeRuntimeSnapshot>`) **on change only** (never per engine step). Loading goes through `AwakeRuntimeSnapshot.admitted(consent:now:)` before any value is assigned (N10): source forced to `.restored`, `nudge` → `declare` unless the preset is consented, kind sanitized (deadline ≤ start + 30 days; whilePID re-verified), guards evaluated first (a restored session on battery below the floor ends `.batteryLow`). On start (launch, relaunch, update, re-enable), `resumeAfterRestart` (default on) restores the admitted session if not expired in the same boot. A crash therefore loses nothing but the time Snaptic was down (assertions die with the process; [PA] §1.2).
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
    package var batteryFloorEnabled: Bool        // true; turning off is consent-protected (§3.2)
    package var batteryFloor: Int                // 20; 5...50, step 5; lowering is consent-protected
    package var endOnAdapterDisconnect: Bool     // false
    package var endOnLowPowerMode: Bool          // false
    package init()
    package func sanitized() -> AwakeGuardsConfig
    /// Import rule (security M7): every field may only become stricter than `current`.
    package func monotonic(over current: AwakeGuardsConfig) -> AwakeGuardsConfig
}
package struct GuardMemory: Codable, Equatable, Sendable {      // persisted in the snapshot
    package var unreadableReads: Int
    package var holding: AwakeEndReason?               // blocks trigger starts until cleared
    package var heldSince: Double?                     // continuous clock
    package var warnedSerious: Bool
    package var assertionHoldUntil: Double?            // continuous; §2.4 backoff
    package var assertionFailures: Int
    package init()
}
package enum AwakeGuardVerdict: Equatable, Sendable { case allow, end(AwakeEndReason), warn(AwakeEndReason) }
package enum AwakeGuards {
    package static let hysteresisPercent = 5
    package static let thermalCooldownSeconds: Double = 600
    package static func evaluate(_ now: PowerFacts, previous: PowerFacts?, config: AwakeGuardsConfig,
                                 memory: GuardMemory, time: Double, active: Bool,
                                 overrideBattery: Bool) -> (verdict: AwakeGuardVerdict, memory: GuardMemory)
    /// Drive Alive and activity may run only if this is true, in every mode (security M1).
    package static func allowsBackgroundWork(_ now: PowerFacts, config: AwakeGuardsConfig) -> Bool
}
```
Rules: desktops (`!hasBattery`) skip battery rules; on AC battery rules don't apply; `percent < floor` on battery → end `.batteryLow`; two consecutive unreadable reads on battery → `.batteryUnreadable`; AC → battery transition with `endOnAdapterDisconnect` → `.adapterDisconnected`; LPM on with `endOnLowPowerMode` → `.lowPowerMode`; `.critical` → end `.thermal` regardless of settings or features and hold for 10 min (evaluated in `SessionController` and `DriveAliveController` directly from `PowerMonitor`, not only through `GuardsController`, so no feature state can skip it); `.serious` → warn once per episode (no end option). Holding clears when battery ≥ floor + 5 or AC, LPM off, thermal ≤ fair for 10 min. **Guards apply to every source** (manual, trigger, CLI, restored). `overrideBattery` is the session's one-shot **Start Anyway** (UI only, never CLI/trigger, never persisted); thermal critical is never overridable. `allowsBackgroundWork` is false below the floor on battery (floor enabled), with unreadable battery on battery, and at `.critical`.

System behavior options (Kit `AwakeBehavior`, part of `AwakeSessionsConfig`):

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
}
```

### 2.7 Triggers (G engine + Kit; J sources)

**Kit model** (`SnapticKit/AwakeTriggers.swift`). Every enum with associated values below gets a **hand-written, type-tagged Codable** (`{"type":"subnet","cidr":"10.0.0.0/8"}`) in the same file; synthesized enum Codable is not used because its shape can't drop unknown kinds per entry.

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
}   // JSON {"kind":"app","negated":false,"bundleID":…}; unknown kind or bad payload → entry dropped (lossy array)

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
package struct DisplayFact: Equatable, Sendable { package var record: FingerprintRecord; package var isBuiltin: Bool }
package struct USBFact: Equatable, Sendable { package var vendor: Int; package var product: Int; package var serialHash: String? }
package struct NetworkFacts: Equatable, Sendable { package var addresses: [String]; package var routerHashes: Set<String>; package var vpn: Bool }
package struct BluetoothFact: Equatable, Sendable { package var audioUIDHashes: Set<String>; package var inputHashes: Set<String> }
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
/// Persisted in the snapshot (continuous clock, same boot only).
package struct TriggerSuppression: Codable, Equatable, Sendable {
    package var until: Double?; package var untilFalse: Bool
    package init(until: Double?, untilFalse: Bool)
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
```

**Notifications are hints, never truth** (security M2): `com.apple.screenIsLocked/Unlocked` and `com.apple.screensaver.didstart/didstop` are distributed notifications any process can post. They only cause a re-read. `SystemEventsMonitor.sessionFacts()` reads `CGSSessionScreenIsLocked` and `kCGSSessionOnConsoleKey` from `CGSessionCopyCurrentDictionary()` at the moment of use, and `SessionController.arbitrate()` and `ActivityController` call it before every arbitration and every activity action. Screensaver: a `didstart` hint only suppresses (fail-safe); "running" also holds while `NSWorkspace.frontmostApplication?.bundleIdentifier == "com.apple.ScreenSaver.Engine"`, which a notification can't fake.

| Source | Period / events | Budget | Notes |
|---|---|---|---|
| PowerMonitor | `kIOPSNotifyPowerSource`, `kIOPSNotifyPercentChange` (`import notify`), `NSProcessInfoPowerStateDidChange`, `thermalStateDidChangeNotification` (both `queue: .main`) | events only | Always active with `sessions` (guards need it). `@Published var facts: PowerFacts` + `observe` |
| SystemEventsMonitor | `NSWorkspace` will/didSleep, screensDidSleep/Wake, sessionDidResign/BecomeActive; distributed lock/screensaver hints; `NSSystemClockDidChange`, `NSSystemTimeZoneDidChange` (→ `NSTimeZone.resetSystemTimeZone()`), `NSCalendarDayChanged`; lid via `IOPMrootDomain` interest (`AppleClamshellState`, `AppleClamshellCausesSleep`, [PA] §2) | events only | `sessionFacts()` reads the session dictionary on demand |
| AppMonitor | launch/terminate/activate notifications | events only | Regular + accessory apps; bundle ids only; picker list sorted by name, Snaptic excluded |
| DisplayPresence | `CGDisplayRegisterReconfigurationCallback` (CallbackTarget), debounced 1 s | events only | Removes callback in `deactivate` |
| USBWatcher | first-match + terminated notifications on `IOUSBHostDevice` | events only | Iterators drained at arm; serial hashed immediately, raw never stored |
| VolumeMonitor | didMount / didUnmount / willUnmount; DiskArbitration description per mount (`DASessionCreate`, `DADiskCreateFromVolumePath`, `DADiskCopyDescription`) | events only | Builds `DriveAlivePolicy.VolumeFacts` (§2.9) |
| AudioMonitor | property listeners on default output/input `DeviceIsRunningSomewhere` + default-device change | events only | HAL calls and listeners on a private serial queue (they can block > 50 ms); each listener stored as a typed `AudioObjectPropertyListenerBlock` so Remove gets the same block, `[weak self]`; moves its listener when the default device changes; publishes on main. No input stream is ever opened |
| CPUSampler | 5 s timer; 10 s window average | ~10 µs/sample | `host_statistics` tick deltas; count = `MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride` (the macro isn't imported); cached host port |
| IdleSampler | 10 s timer (5 s while `keepOnWhileActive`, activity or `idle` criteria run) | trivial | `.hidSystemState` seconds, turned into **last real input** by `IdleMath` (§2.9) so Snaptic's own nudges never count |
| NetworkMonitor | `SCDynamicStore` notifications for IPv4/IPv6 global + interface keys; router hash re-read on change; throughput 5 s timer only when `networkActivity` or `taskQuiet` is needed | events + 5 s | `sysctl NET_RT_IFLIST2` with `if_data64` (32-bit `if_data` wraps within seconds at multi-gigabit); read-only; no sockets; ARP/route via `sysctl` [HW-11] |
| BluetoothPresence (Beta) | CoreAudio device-list listener (AudioMonitor's queue); `IOServiceAddMatchingNotification(IOHIDDevice)` filtered by `Transport` | events only | Never opens a HID device (Input Monitoring) [HW-10] |

### 2.9 Activity simulation and Drive Alive (J)

**ActivitySimulator** (`Awake/Sources/ActivitySimulator.swift`): the only file allowed to call `IOPMAssertionDeclareUserActivity`, to release that declaration's id, and to post `CGEvent`s (lint L1/L2).

```swift
package enum ActivityDecision: Equatable, Sendable { case none, declare, nudge }
package struct ActivityInputs: Equatable, Sendable {      // Kit (code M13)
    package var mode: AwakeActivityMode         // governing session's effective mode (.off when none)
    package var nudgeAllowed: Bool              // pointerNudge effective ∧ consented ∧ Accessibility preflight
    package var managedScreenLock: Bool         // CFPreferencesAppValueIsForced idleTime/askForPassword
    package var screenLocked: Bool              // session dictionary, read now
    package var onConsole: Bool                 // session dictionary, read now
    package var screensaverRunning: Bool        // hint or ScreenSaverEngine frontmost
    package var displaysAsleep: Bool            // CGDisplayIsAsleep(main)
    package var switcherVisible: Bool           // HostSignals
    package var realIdleSeconds: Double         // now − last real input
    package var stopAfterSeconds: Double        // AwakeActivityConfig.stopAfterHours · 3600 (security M4)
    package var pointerEdgeDistance: Double?    // points to the nearest display edge (nudge only)
    package init(mode: AwakeActivityMode, nudgeAllowed: Bool, managedScreenLock: Bool, screenLocked: Bool,
                 onConsole: Bool, screensaverRunning: Bool, displaysAsleep: Bool, switcherVisible: Bool,
                 realIdleSeconds: Double, stopAfterSeconds: Double, pointerEdgeDistance: Double?)
}
package enum ActivityPolicy {   // Kit, J, tested truth table
    package static let intervalSeconds: Double = 60       // fixed (parity minor 14)
    package static let edgeMarginPoints: Double = 2       // security L1: hot corners, Dock, full-screen menu bar
    /// none unless: mode ≠ off, !managedScreenLock, unlocked, on console, no screensaver, displays awake,
    /// switcher hidden, interval ≤ realIdle < stopAfter. nudge additionally needs nudgeAllowed and edge distance > margin;
    /// otherwise a nudge request degrades to declare.
    package static func decide(_ i: ActivityInputs) -> ActivityDecision
}
package enum IdleMath {         // Kit, J
    package static let nudgeEchoSeconds: Double = 1
    /// HID idle resets that fall within nudgeEchoSeconds after one of our nudges are not real input (security L1, code M8).
    package static func lastRealInput(previous: Double, now: Double, hidIdleSeconds: Double, nudgeTimes: [Double]) -> Double
}

@MainActor final class ActivitySimulator: AwakeServiceLifecycle {
    func perform(_ decision: ActivityDecision)          // ActivityController calls it once per interval
    func stop()                                         // releases the DeclareUserActivity id
    private(set) var recentNudges: [Double]             // continuous times, last 10, for IdleMath
    func activate(_ context: AwakeContext, lifetime: Lifetime)
    func deactivate()
}
```
`declare` calls `IOPMAssertionDeclareUserActivity("Snaptic: activity", kIOPMUserActiveLocal, &id)` reusing `id` and releases it on `stop()`. It turns the display on ([PA] §1.4), so it never runs while the displays are asleep. `nudge` posts one `mouseMoved` of +1 pt then −1 pt at the current location from `CGEventSource(stateID: .privateState)` via `.cghidEventTap`, with `eventSourceUserData = 0x534E5054` ('SNPT') so Snaptic's own taps (switcher hover-select) ignore it; `CGPreflightPostEventAccess()` before every post; never posts key, click or scroll events. Whether a private-state source keeps `.hidSystemState` idle untouched is HW-6; `IdleMath` makes correctness independent of the answer. Activity stops (the session continues) once the last real input is older than `stopAfterHours` (default 1 h, Advanced 1–8 h), so an unattended unlocked Mac reaches its idle lock (security M4). Copy (Settings): "Appear active — Keeps apps from marking you as away while a session runs." / "Move the pointer slightly — Moves the pointer 1 point and back. Needs Accessibility."

**DriveAliveService** (`Awake/Sources/DriveAliveService.swift`):

```swift
@MainActor final class DriveAliveService: AwakeServiceLifecycle {
    struct VolumeState: Equatable { let uuid: VolumeUUIDKey; let name: String; var lastWrite: Date?; var lastError: DriveAliveError? }
    @Published private(set) var volumes: [VolumeState]
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
        package init(isInternal: Bool, isRootFileSystem: Bool, isReadOnly: Bool, isLocal: Bool, isDiskImage: Bool,
                     isTimeMachine: Bool, isBrowsable: Bool, inBootContainer: Bool, fileSystem: String)
    }
    package static let allowedFileSystems: Set<String> = ["apfs", "hfs", "exfat", "msdos"]   // allowlist (security M5)
    package static func isEligible(_ v: VolumeFacts) -> Bool
    package static let fileName = ".snaptic-keepalive"
    package static let fileSize = 8
    package static let intervalRange: ClosedRange<Int> = 30...600
    /// C9 + N1 + security M1: never for CLI-only sessions, never when guards forbid background work.
    package static func shouldWrite(sessionActive: Bool, sessionFromCLI: Bool, evenWithoutSession: Bool,
                                    backgroundWorkAllowed: Bool, uiConfirmedFirstWrite: Bool) -> Bool
}
```
Eligibility facts come from the live mount and DiskArbitration: `isDiskImage` = `kDADiskDescriptionDeviceModelKey == "Disk Image"` or an `IOHDIXController` ancestor; `inBootContainer` = the volume's APFS container is the boot volume's container (every volume in it is excluded); `isLocal` from `statfs` `MNT_LOCAL`, and the file-system allowlist excludes FSKit/macFUSE/network types. Write procedure on a private serial `DispatchQueue(label: "snaptic.drivealive", qos: .utility)` (security M5):
1. Resolve the root from the current mount list by UUID (never from config).
2. `dirfd = open(root, O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)`.
3. `fstatfs(dirfd)`: `f_mntonname == root`, `f_fstypename ∈ allowedFileSystems`; `fgetattrlist(dirfd, ATTR_VOL_UUID)` equals the configured key. Any mismatch → `.mountChanged`, skip.
4. `fd = openat(dirfd, fileName, O_WRONLY|O_CREAT|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK, 0600)`; `fstat(fd)`: regular file, owner `getuid()`, `st_nlink == 1`, size ≤ 64, `st_dev` equal to the directory's `st_dev`.
5. Write 8 bytes (UInt64 timestamp) at offset 0, `ftruncate(8)`, `fcntl(F_FULLFSYNC)`, close both fds; the result hops to main.

Any check failure → that volume is skipped and the Drives row shows "Can't keep this drive awake" with the reason; no retry until remount. Stop on `willUnmount` (before eject). `removeKeepAliveFile` uses the same steps 1–3, then `fstatat` + `unlinkat(dirfd, fileName, 0)` only if the file passes step 4's checks and is exactly 8 bytes. The **first** write to a volume happens only right after the user turns that volume on in Drives (so the Removable Volumes prompt follows a UI action, security M3); until then `uiConfirmedFirstWrite` is false. Info.plist gets `NSRemovableVolumesUsageDescription` = "Snaptic writes a tiny hidden file to the drives you choose so they don't spin down." (lead). Package.swift links DiskArbitration (lead).

### 2.10 Automation (G, `AwakeAutomation`)

Hotkeys (`AwakeActionID`, owner "Awake", via `GlobalHotkeys`, all unbound by default): `awake.toggle` (Keep Awake on/off with the default preset), `awake.keepDisplayOn`, `awake.preset1…4`, `awake.pauseAutomatic`.

CLI verbs (registered only while `commandLine` is effective and the host CLI is on). `start`, `hold`, `stop` and `extend` share a 1 request/s limit (security L3), on top of the global 20/s.

| Verb | Policy | offOnly | Behavior |
|---|---|---|---|
| `awake status` | read | — | `inactive` or `active\tmanual|automatic\t<kind>\t<display policy>\t<ISO end or ->\t<remaining s>`; kinds `indefinite|duration|until|app|idle|process|automatic`; `--json` object; no app names, no process names, trigger *numbers* only |
| `awake start [<duration grammar>] [display-may-sleep]` | low | false | `AwakeDurationGrammar`; **no argument = 1 h**; `indefinite`/`forever` refused (exit 4, "Use the menu or `awake hold`"); `idle` = Until Downloads and Tasks Finish (cap 12 h); refused if the resulting options use `nudge`; guards apply (exit 4 with reason) |
| `awake hold [--pid N \| --parent] [<duration>]` | low | false | `whilePID` session. Default `--parent`: the server reads the client's pid with `getsockopt(LOCAL_PEERPID)` and its parent with `proc_pidinfo(PROC_PIDTBSDINFO).pbi_ppid` (never a pid the client claims); `--pid N` must belong to the peer's uid. Cap = duration (≤ 30 days) or 12 h. Ends when the process exits |
| `awake preset <n|name>` | low | false | Refused if the preset uses `nudge` or is Until Turned Off |
| `awake extend <duration>` | low | false | Manual timed or capped sessions only; refused (exit 4) when the governing session's effective activity is `nudge` (security M3) |
| `awake stop` | low | true | Ends the manual session; a trigger session is suppressed as a manual end |
| `awake pause [<duration>]` | low | true | Pauses automatic sessions (default 1 h, ≤ 24 h) |

README recipe (lead, step 5): `snaptic awake hold -- make release` is not offered (no spawning); scripts call `snaptic awake hold` once at the top and the session ends with the script; CI uses `caffeinate -w` as before.

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
    @Published var activityActive = false
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

// Core/ModuleContracts.swift (lead): the host owns status-item slots; a module with a custom item provides it (code B3)
@MainActor protocol StatusItemProvider: AnyObject {
    var statusItem: NSStatusItem? { get }                      // nil while the item doesn't exist
    func presenceDidChange(_ presence: MenuPresence)            // called from StatusMenu.applyPlan
}

// Awake/AwakeContext.swift (lead)
@MainActor final class AwakeHost {           // explicit host services (code B3: "statusItems" had no definition)
    let safeMode: SafeModeState
    let signals: HostSignals
    let hotkeys: GlobalHotkeys
    let commands: ControlCommandRegistry
    let toasts: ToastPresenter
    let permissions: PermissionFlow
    let consent: AwakeConsentStore
    let requestMenuRebuild: @MainActor () -> Void
    let openSettings: @MainActor (SettingsRoute?) -> Void
    init(_ module: ModuleContext, consent: AwakeConsentStore)
}
@MainActor final class AwakeContext {
    let assertions: AssertionManager, power: PowerMonitor, system: SystemEventsMonitor, apps: AppMonitor
    let displays: DisplayPresence, usb: USBWatcher, volumes: VolumeMonitor, audio: AudioMonitor
    let cpu: CPUSampler, idle: IdleSampler, network: NetworkMonitor, bluetooth: BluetoothPresence
    let activity: ActivitySimulator, driveAlive: DriveAliveService
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
`AwakeModule` (lead) follows `DisplaysModule` line by line (resolve, apply order, kill switches, config sink with one main-queue hop, `stop()` sync and idempotent: controllers reverse, services reverse, `assertions.releaseAll()` last-resort, flush stores) and adopts `StatusItemProvider` by forwarding to `IndicatorController` (G owns the item; StatusMenu never builds an Awake slot). The **admission hooks** (N10) are installed by `ModuleHost` when it creates the three stores, not by the module, so they run while Awake is stopped too.

### 2.12 Behavior across system events (normative)

| Event | Behavior |
|---|---|
| Snaptic crash / force quit | powerd releases the assertion on process exit ([PA] §1.2). Nothing else to undo (Drive Alive leaves an 8-byte hidden file). Relaunch in the same boot resumes the admitted manual session. |
| System sleep (lid, Apple menu, low battery, thermal) | Assertions don't prevent it. `willSleep`: if `endOnSystemSleep`, end `.systemSleep`; stop activity and Drive Alive writes. `didWake`: recompute remaining (continuous clock), end expired sessions, re-arbitrate, verify the assertion, triggers step after 5 s settle. |
| Lid closed on battery, not desktop mode | Mac sleeps. When a session is active the Awake menu shows "Closing the lid will put your Mac to sleep. To keep it awake with the lid closed, connect power and an external display." |
| Clock change | Until-sessions and `pausedUntil` re-evaluated now (re-arm if the end moved > 5 s); duration sessions unaffected; schedules re-evaluated. |
| Time-zone change | `NSTimeZone.resetSystemTimeZone()`; until instants kept, labels re-rendered; schedules use the new zone at the next step. |
| Screen lock / screensaver (session dictionary) | Session continues; plan downgrades display→system (C1 default); activity paused; Drive Alive continues (guards permitting); toasts suppressed. With `endAfterLockedHours`, a lock lasting that long ends `.lockedTooLong`. |
| Fast user switching (session dictionary: not on console) | Plan downgrades to system; activity paused; `userSwitchEnd` ends `.userSwitch` immediately or after 1 h off console (default). Becoming active again re-applies. |
| Low Power Mode on | Toast once "Low Power Mode is on. Awake keeps running." unless `endOnLowPowerMode`. |
| Thermal serious / critical | §2.6 (critical also stops Drive Alive). |
| Safe Mode | Manual sessions, guards, indicator, history, shortcuts, CLI work; triggers, activity, nudge, Drive Alive are removed. |
| Displays panic ("Restore All Displays") | Not an Awake participant: keep-awake is not a display hazard. (0.2's "sleep prevention released" row goes with the feature in step 3.) |
| Module turned off from Settings | Confirmation first when a session or enabled trigger exists ("Turning off Awake ends the current session and stops automatic sessions."); then `stop()` with `isTerminating == false`: assertion released, session ended, snapshot cleared, status item removed. |
| Quit | `isTerminating = true`, then `stop()`: assertion released, snapshot kept for resume. |

### 2.13 Interaction with Displays and the Switcher

- **Displays**: `sleepPrevention` is removed **in step 3**, in one coordinated merge by D and F with the lead's lines and A's Kit rows (code B2): `DisplayFeature.sleepPrevention` and its spec, `PerDisplayManagement.preventSleep` (kept decodable and encoded until 0.4, ignored), PowerController's assertion code, `ManagementIDs.dSleepPrevention*`, `DisplaysRuntimeState.sleepPreventionActive`, the Arrangement-page section, the menu badge, the CLI `prevent-sleep` verb, the KitBackup/KitControl/DisplaysUIModel/Diagnostics rows and their tests. Until then the enum case, spec and runtime property stay and compile; M1 reads raw JSON either way, so it doesn't depend on the case. The ratchet (§6.3) lists `PowerController.swift` for L1 until that merge. Awake never calls Displays code except B's pure `DisplayIdentity`/`Fingerprint.matches` helpers and a read-only look at `DisplaysConfig` custom names.
- **Switcher**: no functional coupling. Pointer nudges are tagged and suppressed while the switcher panel is visible (`HostSignals.switcherVisible`, set by A). Hotkey conflicts across modules are reported by `GlobalHotkeys` with the owning module's name.
- **Host**: `ModuleHost` gains `awake: AwakeModule`, `awakeStore`, `awakeStateStore`, `awakeHistoryStore` (one store per key: `SnapticAwakeV1`, `SnapticAwakeStateV1`, `SnapticAwakeHistoryV1`), the `AwakeConsentStore`, the admission hooks, flushes the stores on quit, and includes them in Reset All Settings (history and state cleared too; consent cleared, which turns nudge and Drive Alive off).
- **Upgraders** (code M4, C7): in `ModuleHost.init`, when module settings existed before this launch and `modules[.awake] == nil`, the host inserts `ModulePreferences(enabled: false, presence: .ownIconWhenActive)` for Awake **before** M1 runs; M1 turns it on only if it produced an enabled trigger. `ModulesConfig.defaultPreferences(_:)` becomes per id (fresh installs: Awake enabled, `.ownIconWhenActive`); `ConfigModulesTests` lines 15 and 34 are updated.

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
    /// N10: protected fields of `incoming` not covered by `consent` are turned off / raised (security H1).
    package func admitted(consent: AwakeConsent) -> AwakeConfig
    /// Page Restore Defaults: everything back to defaults; protected features OFF (safe direction, security L6).
    package func restoringDefaults() -> AwakeConfig
    /// Backup (security M7): nudge → declare, drops drives, features.pointerNudge, recentApps, startAtLaunch,
    /// salted hashes; triggers only when `includeTriggers` (the user ticked the export checkbox).
    package func exportable(includeTriggers: Bool) -> AwakeConfig
    /// Import: same stripping, guards monotonic over `current`, protected fields kept from `current`.
    package func importable(current: AwakeConfig) -> AwakeConfig
}

// Config/ConfigAwakeConsent.swift (lead): what the user turned on in the UI; stored in the Keychain, never in defaults
package struct AwakeConsent: Codable, Equatable, Sendable {
    package var pointerNudge: Bool
    package var nudgePresets: Set<StableID>
    package var nudgeTriggers: Set<StableID>
    package var driveAliveVolumes: Set<VolumeUUIDKey>
    package var lowestBatteryFloor: Int?     // nil = the floor may not go below the default (20)
    package var batteryFloorOffAllowed: Bool
    package static let empty: AwakeConsent
    package init()
}

// Config/ConfigAwakeSessions.swift (G)
package enum AwakePresetKind: Equatable, Sendable {
    case indefinite, duration(seconds: Int), untilTime(hour: Int, minute: Int), untilIdle(UntilIdleSpec)
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
    package var defaultOptions: AwakeSessionOptions   // what "Keep the display on" edits; used when a preset has nil
    package var lastCustomSeconds: Int          // 5400
    package var behavior: AwakeBehavior         // §2.6
    package var recentApps: [String]            // ≤ 5 bundle ids; local only, never exported
    package init()
    package func sanitized() -> AwakeSessionsConfig
    /// preset.options ?? (task-bound kind ? defaultOptions with display = .maySleep : defaultOptions)
    package func effectiveOptions(for kind: AwakeSessionKind, preset: AwakePreset?) -> AwakeSessionOptions
}

// Config/ConfigAwakeIndicator.swift (G)
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
    package var stopAfterHours: Int              // 1; 1...8 (security M4)
    package init()
    package func sanitized() -> AwakeActivityConfig
}
package struct DriveAliveVolume: Codable, Equatable, Sendable {
    package var name: String; package var enabled: Bool
    package init(name: String, enabled: Bool)
}
package struct DriveAliveConfig: ConfigModel {
    package var volumes: LossyMap<VolumeUUIDKey, DriveAliveVolume>   // ≤ 16
    package var intervalSeconds: Int             // 120, 30...600
    package var evenWithoutSession: Bool         // false (C9)
    package init()
    package func sanitized() -> DriveAliveConfig
}

// SnapticKit/AwakeSnapshot.swift (G): key SnapticAwakeStateV1
package struct AwakeRuntimeSnapshot: ConfigModel {
    package var manual: AwakeSession?
    package var suppressions: LossyMap<StableID, TriggerSuppression>
    package var pausedUntil: Double?             // wall time; "Pause automatic sessions" (only here, code M2)
    package var guardMemory: GuardMemory
    package init()
    package func sanitized() -> AwakeRuntimeSnapshot
    /// N10/security H2: source = .restored, override cleared, nudge → declare unless consented, kind clamped.
    package func admitted(consent: AwakeConsent, now: ClockNow) -> AwakeRuntimeSnapshot
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

**Admission and consent** (lead, app; security H1/H2, code M5):

```swift
// Core/ConfigStore.swift (lead): admission runs before any assignment
@MainActor final class ConfigStore<T: ConfigModel>: ObservableObject {
    /// `current` is nil at load. The result replaces `incoming` before `value` is set and before `onExternalChange`.
    typealias Admit = @MainActor (_ current: T?, _ incoming: T) -> T
    init(key: String, admit: Admit? = nil)
    /// true when admission changed the stored value at load (the module shows the toast once it starts).
    private(set) var revertedAtLoad: Bool
    var onAdmissionReverted: (@MainActor () -> Void)?    // outside change reverted while running
    // existing members unchanged
}

// Awake/AwakeConsentStore.swift (lead)
@MainActor final class AwakeConsentStore {
    /// Reads the Keychain generic-password item synchronously; any failure → .empty (features fall back to off).
    init(service: String = "Snaptic Awake consent")
    private(set) var consent: AwakeConsent
    /// UI actions only (lint L11: callers only under `Awake/UI/` and `SettingsUI/`).
    func record(_ change: (inout AwakeConsent) -> Void)
}
```
Keychain rules: generic password, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, default ACL (the creating app); every call passes `kSecUseAuthenticationUI: kSecUseAuthenticationUIFail`, so a mismatched ACL returns an error instead of a prompt; the account is the signing identity (`TeamIdentifier`, or the cdhash for ad-hoc builds, from `SecCodeCopySigningInformation`), so a rebuilt debug app starts with empty consent instead of prompting. Writes are delete-then-add under the same account. Admission flows: `ModuleHost` creates the Awake stores with `admit: { _, incoming in incoming.admitted(consent: consent.consent) }` (snapshot: `admitted(consent:now:)`); a revert logs `AwakeLogEvent.outsideChangeIgnored` and shows "An Awake setting changed outside Snaptic was ignored." UI writes that turn a protected field on call `consent.record` **before** writing the config, so the UI's own write is admitted.

## 3. Security and privacy (additions to 0.2 §4.10)

Threat model unchanged: a same-user process can already hold power assertions (`caffeinate`), write our defaults and launch Snaptic. Snaptic must not let it borrow Snaptic's TCC grants (Accessibility, Removable Volumes), run code, or extract data Snaptic observes.

### 3.1 CLI may start sessions (N1)

Allowed because starting an Awake session grants nothing new: any same-user process can create the identical assertion itself (`caffeinate`). Constraints that keep it that way:
- The CLI server is off by default (General › Command line) and keeps its 0.2 socket rules (0700/0600, `getpeereid`, 20/s), plus 1/s for `start`, `hold`, `stop`, `extend` (security L3).
- CLI sessions are `source: .commandLine`, visible in the indicator and menu ("Started from the command line"), subject to every guard, no "Start Anyway"; a toast says so at most once per 10 minutes, so a hidden indicator (26/27) can't hide a script.
- **Never** pointer movement or Drive Alive: presets or options with `nudge` are refused, `extend` is refused while the governing session nudges (security M3), and `DriveAlivePolicy.shouldWrite` ignores sessions whose source is `.commandLine` (OQ-1 settled strict). Drive Alive has no verbs, and its first write follows a UI action.
- **Never unbounded**: no argument = 1 h; `indefinite` refused; `hold` binds to a process the server resolves itself (`LOCAL_PEERPID`, same uid) and always has a cap.
- Closed grammar only (`AwakeDurationGrammar`, digit/decimal/overflow limits); max 30 days; no free-form strings reach the assertion or the log.

### 3.2 Protected Awake settings (N10)

Protected fields are those that use Snaptic's TCC grants or weaken a safety floor: `features.pointerNudge`; any preset or trigger whose activity is `nudge`; Drive Alive volumes (adding or enabling); `guards.batteryFloorEnabled = false`; `guards.batteryFloor` below the consented floor.
- **Consent record**: `AwakeConsent` in a Keychain item only Snaptic's code identity can read without a prompt (§2.14). Only UI actions write it (lint L11). A same-user process can write defaults but not this item.
- **Admission before assignment**: `ConfigStore(key:admit:)` runs `admitted(consent:)` in `init` (current = nil) and in `storedValueChanged` before `value` is set and before `onExternalChange`, so no controller ever sees a tampered value (security H1 scenario B). `ModuleHost` installs it at store creation, so values written while Snaptic was quit or Awake was stopped are admitted at the next load (scenario A, code M5).
- **Runtime snapshot** goes through the same admission plus guard evaluation (security H2, §2.5).
- **Failure is safe**: a Keychain read error (ad-hoc rebuild, locked keychain, ACL mismatch) yields empty consent, so the protected features are off until the user turns them on again in Settings.
- **Restore Defaults / Reset All Settings** turn protected features off and clear consent (security L6).
- Toast on revert: "An Awake setting changed outside Snaptic was ignored." (once per launch).

### 3.3 Activity simulation

- Default `declare` uses no TCC and posts no events.
- `nudge` (experimental) is the only code path in Snaptic that posts mouse events: one file (`ActivitySimulator.swift`, lint L2), `mouseMoved` ±1 pt only from a private-state event source, tagged 'SNPT', never key/click/scroll, never within 2 pt of a display edge, never while locked, in the screensaver or off console (all read from the session dictionary and process state, never from notifications alone, security M2), never when the user was active within the interval, never from the CLI; Accessibility is requested lazily, only when the user turns nudge on (through `PermissionFlow`), and the toggle explains how to revoke it.
- Both modes stop after `stopAfterHours` (default 1 h) without real input, and are unavailable when the organization forces screen-lock settings (security M4). Snaptic's own nudges never count as real input (`IdleMath`).

### 3.4 Drive Alive writes

Fixed file name at the volume root; target derived from the live mount list by UUID and re-verified on a directory fd (`fstatfs` mount point and file-system allowlist, `fgetattrlist` volume UUID, `openat` + `O_NOFOLLOW`, same `st_dev`), never from stored paths or user text; `fstat` checks (regular, ours, one link, ≤ 64 B); 8 bytes of timestamp; never internal, boot-container, system, read-only, non-local, disk-image (DiskArbitration) or Time Machine volumes (Kit `DriveAlivePolicy`, tested); removal via `unlinkat` only of an 8-byte file that passes the same checks; stop before unmount; battery floor and thermal guards apply in every mode; I/O off main with results hopping back. The Removable Volumes grant is Snaptic's own, used only for this file, first used right after a UI action.

### 3.5 No code execution, no network

Awake spawns nothing (lint rule 12 already bans `Process`, `posix_spawn`, `NSAppleScript`, `NSUserScriptTask`, `system(` outside HelperSpawner; r1's L3 duplicated it and is dropped); `whilePID` observes a process with a dispatch source and `proc_pidinfo`, never signals or spawns; triggers have no actions besides starting a session; no URL scheme; no AppleScript. NetworkMonitor reads kernel/configd state only (`SCDynamicStore`, `sysctl NET_RT_IFLIST2`, routing-table `sysctl`); lint bans `URLSession`, `NWConnection`, `CFSocket`, `socket(`, `connect(` in Awake as elsewhere.

### 3.6 Privacy

- **Logs** (`EventLog`, `.awake`): written only as `EventLog.shared.record(.awake, event: AwakeLogEvent)`, a closed enum with a fixed `text` per case (`sessionStarted(AwakeHistoryKind)`, `sessionEnded(AwakeEndReason)`, `triggerActive(index: Int)`, `assertion(AwakeAssertionType)`, `outsideChangeIgnored`, `driveAliveError(DriveAliveError)`, …); lint L9 bans `record(.awake, "` (string form) under `Awake/` (security M6). No app names, bundle ids, process names, volume names/UUIDs, USB names/serials, addresses, router data, criterion payloads or trigger names can reach the log.
- **Assertion properties** are world-readable (`pmset -g assertions`): name is fixed; `Details` is only `manual` or `automatic` (no criterion kinds).
- **CLI** `awake status`: kinds and trigger numbers only.
- **Stored identifiers**: router MACs and USB serials as salted hashes (`SnapticAwakeSalt`, never exported); display matches as salted fingerprint tiers (existing salt).
- **Backup** (`AwakeConfig.exportable/importable`, A wires them into KitBackup's new `awake` section): export includes presets (nudge rewritten to declare), guards, indicator, behavior; trigger definitions **only** when the user ticks "Include automatic-session rules (contains app, device and network names)" (off by default; salted hashes are stripped either way since they are useless on another Mac); omits history, runtime state, salts, `recentApps`, `startAtLaunch`, Drive Alive volumes, `pointerNudge`. Import: same stripping, guards monotonic (stricter only; `awake.guards` joins `safetyPaths`), protected fields always kept from the current config.
- **Diagnostics** (shared report): Awake section with effective features, governing kind, assertion type, guard state, source activity (running/idle), counts of triggers/criteria by kind, Awake event **counts** per `AwakeLogEvent` case (no timestamps, so no activity timeline), Drive Alive volume count and last error codes. The "Other apps keeping your Mac awake" list never goes into diagnostics, logs or CLI.
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
enum SettingsBadge: Equatable { case beta, experimental, paused(String), unavailable(String) }

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
/// tooltip "Reset to 50%", AX label "Reset Contrast to 50 percent".
struct ResetButton: View { init(visible: Bool, label: String, action: @escaping () -> Void) }

/// Precondition missing → the control is disabled, its help stays, and `disabledReason` + `fix` go to the
/// section footer ("Needs Accessibility." [Open Accessibility Settings…]). Hardware can't do it → the caller omits the row.
struct ToggleSetting: View {
    init(_ title: String, help: String? = nil, isOn: Binding<Bool>, subordinate: Bool = false,
         anchor: String? = nil, badge: SettingsBadge? = nil, disabledReason: String? = nil, fix: StatusAction? = nil)
}

/// Every slider in Settings (N4). Normative layout (design M6), trailing cluster after the title:
///   slider (min 140, ideal 200) · 8 · field 48 · 4 · reset slot 16 (always reserved)
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
    init(_ accessibilityTitle: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double?,
         format: ValueFormat, width: CGFloat = 48)
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
struct GlyphTilePicker: View { init(_ title: String, symbols: [String], selection: Binding<String>, anchor: String? = nil) }
/// Pull-down button with actions (Display Tools ▾, Copy Settings From ▾, Extend ▾).
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
struct ReorderableList<Item: Identifiable, Row: View>: View {   // List .onMove + ▲▼ context menu for keyboard
    init(_ items: Binding<[Item]>, onDelete: ((Item) -> Void)?, @ViewBuilder row: @escaping (Item) -> Row)   // code M13
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
    // id, title, symbolName, summary, state, requiredPermissions, start, stop, menuSection — unchanged
    var tint: SettingsTint { get }
    var highlights: [FeatureHighlight] { get }                       // off-state block
    func settingsRoot() -> SettingsRoot                               // rendered whether running or not
    func settingsDestination(_ route: SettingsRoute) -> AnyView?
    func settingsIndex() -> [SettingsSearchEntry]                     // static per module; computed once
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

**Window**: `NavigationSplitView`, sidebar 200–240 pt with `.searchable(placement: .sidebar)` at the top, detail `NavigationStack` per root (back button for sub-pages), `.toolbar(removing: .sidebarToggle)`, **fixed width 715 pt, vertical resize only** (min height 520, default 640; [DS] §1, design m6), title = current page. While open the app is `.regular` (0.2 R5.8 kept).

**Sidebar** (fixed; 8 rows; groups separated by spacing):

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

**Copy rules** ([DS] §4, normative): sentence case for labels, help, section headers; Title Case for buttons, menu items, page titles; labels name the thing or the on-state, no "Enable/Disable/Allow X to"; one help sentence ≤ 90 characters describing the on state; "Mac", "display", "click", "press"; never "monitor" in labels (use "display" or "hardware"); errors say what to do; real ellipsis; "20%", "60 Hz", "15 min" in values; Apple terms table [DS] §4.7 (Display, Virtual display, Picture in Picture, Brightness indicator, Saved layouts, Start automatically, Keep Awake, Display Information, Confirm display changes, Settings). Every visible control has help text or is self-evident by Apple precedent (review item: each `ToggleSetting`/`SliderSetting` without `help:` needs a reviewer note).

**States** (design m8, normative): hardware can't do it → the row is omitted; a precondition is missing → the control is disabled, its help stays, and the reason plus a fix button go in the section footer; empty lists → `EmptyListView` with page-specific copy (§4.3).

**Budget** (r2 definition, design M1): per page with default features and the 1 built-in + 1 DDC external setup, count every visible **setting** (switch, picker, slider, field, glyph tiles, including subordinate rows shown by default) and every **in-form button or navigation row**. Not counted: the page header switch, the status row's actions, the rows inside a list (a list counts as 1), the footer (`Advanced…`, (?)). Limits: ≤ 8 settings and ≤ 12 counted elements in total; Advanced sheets ≤ 25 controls. Exception, stated in §4.3: the Displays root page is a hub (System Settings › Displays precedent) whose navigation rows exceed the total.

### 4.3 Pages (normative content; V = visible, A = Advanced sheet, S = sub-page, D = Display Details sheet, X = removed/merged)

Every page: `SettingsPageScaffold` → `SettingsPageHeader` → sections → `PageFooterButtons` (trailing `Advanced…` and (?) only). Restore Defaults… lives in the Advanced sheet's footer (leading), or in the page footer (leading) on pages without an Advanced sheet. Keyboard Shortcuts… is a `ButtonRow` in a "Keyboard" section, never a footer button (design M5). No sheet presents another sheet (§1.5); a "…" inside a sheet is a disclosure, a pull-down or a standard alert.

**General** (hero header, no master switch; was 9 pages / ~34 controls)

```
[⚙] General
    Startup, command line, backup and safe mode.
─────────────────────────────────────────────────────
[New: Awake card — Keep your Mac awake. [Turn On Awake…] [Not Now]]   (once)
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
| Card | "New: Awake" (C7), dismissible; generalized `newModuleCards` | V once | "New: Displays" card |
| Startup | Open at login | V | Startup page (X: a page for one toggle) |
| Command line | Command-line control (help "Lets scripts and other apps control Snaptic with the `snaptic` command.") · Copy Install Command | V | CLI page |
| Backup | Export Settings… (sheet: "Include automatic-session rules (contains app, device and network names)" checkbox, off) · Import Settings… | V | Backup & Reset |
| Advanced | Commands can skip confirmation · exit codes ((i) popover) · Restart in Safe Mode… / Leave Safe Mode (with its explanation) · footer leading: **Reset All Settings…** (destructive, scope "all Snaptic settings"; parity minor 12) | A | CLI page, Safe Mode page (X), Backup & Reset |

The module navigation rows of r1 are removed (they repeated the sidebar; design M1). "Other display apps" moves to Displays › Advanced. About & Licenses → About.

**Menu Bar** (M; N7; graphite tile; was General › Menu with ~28 controls). No Advanced sheet.

```
Snaptic icon             [◫] [◩] [◰]                 (glyph tiles, .isSelected)
─────────────────────────────────────────────────────
Show in the menu bar
Window Switcher                     [In Snaptic Menu ▾]
Displays                            [In Snaptic Menu ▾]
   (Own Icon only) Icon             [▭] [◫] [☀]
   (Own Icon only) Hide when no external display is connected   ( )
Awake                               [Own Icon When Active ▾]
   Show                             [Icon and Time Remaining ▾]
   Icon                             [cup] [eye] [bulb]
⚠ No Snaptic icon is shown. Open Snaptic again to see Settings.   (status row, only when true)
─────────────────────────────────────────────────────
Displays menu
Display controls                    [Expanded | Compact]
Scroll over a slider to adjust it                   (•)
Customize Displays Menu…
                          Restore Defaults…     (?)
```

| Section | Controls | Where |
|---|---|---|
| Snaptic icon | Glyph tiles (curated, rendered) | V |
| Show in the menu bar | One pop-up per module (C2, design M2): Switcher and Displays *In Snaptic Menu / Own Icon / Don't Show*; Awake *Own Icon / Own Icon When Active / In Snaptic Menu / Don't Show*. Help for Don't Show: "Use the keyboard shortcut or Settings to reach it." Awake's *Don't Show* is disabled until the Keep Awake shortcut is bound (help says so, parity M2). Under a module set to Own Icon: its **Icon** glyph tiles (parity B2) and, for Displays, "Hide when no external display is connected". Under Awake (Own Icon or When Active): **Show** (*Icon / Icon and Time Remaining / Icon and End Time*) and **Icon** tiles (cup, eye, lightbulb) | V |
| Warnings | 0.2's hidden-icon warnings kept as status rows ("No Snaptic icon is shown…", "The Displays icon only appears while an external display is connected.") | V when true |
| Displays menu | Display controls: Expanded / Compact · Scroll over a slider to adjust it · Customize Displays Menu… → sheet: display order + visibility (one reorderable list with checkboxes; "Use the Default Order"), section order, main display first, status badges, header row with one display, header switch per display (was Arrangement "Header switch"), per-item visibility grouped by area with human titles ("Volume", "Input", "Turn Display On or Off"; sliders Visible/Hidden only), footer leading Restore Defaults… | V + sheet |
| Footer | Restore Defaults… (scope "menu bar settings", leading) · (?) | V |

**Window Switcher** (H; header switch "Use Window Switcher"; was 6 pages / ~40 controls)

| Section | Controls | Where | Notes |
|---|---|---|---|
| Shortcut | Primary shortcut (modifier + key recorder) · Show: All windows / Active app / This display (pop-up) · Style: Thumbnails / Icons / List (segmented) · Preview the selected window (subordinate, Thumbnails only; `previewSelected`, parity B2) · Size thumbnails automatically (subordinate, Thumbnails only) + Thumbnail size (SliderSetting 100–300 pt, step 10, default 170, subordinate, shown when automatic is off; fixes C2) | V | primary shortcut's scope/style |
| Windows | Include minimized and hidden windows · Windows from: All Spaces / Current Space / Other Spaces | V | per-shortcut options of the primary shortcut |
| Behavior | Switch when you release the keys | V | |
| Keyboard | Keyboard Shortcuts… (sheet: additional switcher shortcuts with their own options, Add/Delete, Gather Windows shortcut) | V | |
| Advanced | Window thumbnails (feature, Screen Recording footer) · Show on: Display with the active window / Display with the pointer · Window actions (Close, Minimize, Full Screen, Hide, Quit — one checkbox group) · Hover buttons · Select by hovering · Search · ⌘⇥ replaces the app switcher · Pass shortcuts through to apps (+ Only while full screen + app list) · Apps hidden from the switcher (AppListEditor) · Never show thumbnails for (password managers toggle + AppListEditor) · One entry per app · Include apps with no open windows · Windows on other Spaces and Windowless apps feature switches (help "Applies to every shortcut") · footer Restore Defaults… | A (21) | Features page (X), App Lists (X), Privacy (X) |

**Displays** root page (F composes; owners provide sections; header switch "Use Displays"; was 16 pages / ~170–330 controls)

```
[☀] Displays                                       (●)   "Use Displays"
    Brightness, resolution and arrangement for every display.   2 displays
─────────────────────────────────────────────────────
[▭ Built-in Retina Display] [▭ DELL U2720Q]            [Display Tools ▾]
─────────────────────────────────────────────────────
Brightness              ☀ ━━━━━━●━━━━ ☀  [ 70% ] ↺
Automatically adjust brightness                     (•)   built-in only
─────────────────────────────────────────────────────
Resolution                       [Default — 1512 × 982 ▾]
Refresh rate                                [120 Hz ▾]
▸ Resolution options
    Resolution     ◦━━━━━●━━━━◦  [1512 × 982]         SliderSetting, discrete, onRelease
    [Quick Changes ▾]  [Undo] [Redo]  [Add to Favorites]
    Favorites: 1280 × 800 [Apply] [−] …
─────────────────────────────────────────────────────
Use as                                   [Main display ▾]
Arrange Displays…
Display Details…
─────────────────────────────────────────────────────
[☀] Brightness ›   [◐] Color ›   [▣] Hardware Controls ›   [⌨] Keyboard ›
[▤] Saved Layouts ›   [▢] Virtual Displays ›   [⧉] Picture in Picture ›   [⚙] Automations ›
[i] Display Information ›
                                             Advanced…  (?)
```

| Section | Controls | Owner |
|---|---|---|
| Header | Displays switch; status line ("2 displays") | F |
| Display tiles | `PerDisplayPicker` (hidden with one display; pop-up with > 4) · **Display Tools ▾** pull-down: Identify Displays, Redetect Displays, Show Displays Panel, Connect All Displays (if `disconnect`), Restore All Displays | F |
| Brightness (selected display) | Brightness (SliderSetting, ☀︎ symbols, full range incl. XDR, `.live`; value in nits when Show nits is on) · Automatically adjust brightness (built-in, if `autoBrightness` available) | C |
| Resolution (selected display) | Resolution pop-up (scaled modes, "Default for display" first, favorites marked; with `hiddenModes` a "Show All Resolutions" section) · Refresh rate (if > 1) · HDR (if supported and `hdrToggle`) · Rotation (if `rotation`) · **Resolution options** disclosure (collapsed): resolution slider (SliderSetting, discrete, `.onRelease`), **Quick Changes ▾** (Toggle HiDPI, Native, Default, Native ÷ 2 "Half of native, sharper", Toggle Notch), Undo / Redo, Add to / Remove from Favorites, favorites list (Apply, −) | D |
| Arrangement | Use as: Main display / Extended / Mirror for "X" (pop-up) · Arrange Displays… (sheet: canvas + Snap to edges + keyboard Position/Align form as a disclosure) · Display Details… (`ButtonRow`, design M9: tiles carry no (i)) | D, F |
| Navigation | Group 1: Brightness › · Color › · Hardware Controls › ("Volume, input and power for displays that support them.") · Keyboard › — spacing — Group 2: Saved Layouts › · Virtual Displays › · Picture in Picture › · Automations › — spacing — Display Information › (design M4/M9). Each row shows On/Off and is always present | F + owners |
| Footer | Advanced… · (?) | F |

**Display Details…** sheet (per selected display; F + B + D; no nested sheets):

| Group | Controls |
|---|---|
| Identity | Name (field + Use the System Name) · Icon (glyph tiles) · **Menu visibility…** link: closes the sheet and opens Menu Bar › Customize Displays Menu with this display selected (parity M6; per-display visibility lives only there) |
| Connection (D; design M9) | Disconnect / Connect (if `disconnect`) · Never disconnect automatically (built-in, if `autoDisconnectBuiltin`) · My display has no DDC (allow auto-disconnect without a power reading) · Underscan (Experimental, SliderSetting `.onRelease` with the confirmation; replaces the draft + Apply) |
| Menu bar overlays (C) | Black strip behind the menu bar · Top / bottom corner radius (if `menuBarOverlays`) |
| Match text size (D; if `scaleMatch`) | Disclosure: Include this display · Reference display · Match tolerance · Preview / Apply |
| Manage | Copy Settings From ▾ (pull-down, design M4) · Forget Remembered Resolution · Forget This Display… (standard alert) |
| Information | Disclosure: transport, masked serial, EDID Copy Hex / Copy Base64 / Export… |

**Displays › Advanced** sheet (F composes; cross-cutting groups only, 25 controls, design M9):
1. **Use Snaptic for** (feature switches, plain words, only for features without their own sub-page switch): Brightness control, Resolution control, Arrangement and mirroring, Rotation, Keyboard shortcuts, Brightness indicator, Disconnect displays (Beta). (F; replaces Features page; Hardware controls, Color, Saved layouts, Virtual displays and Picture in Picture keep their switch on their sub-page only)
2. **Confirm display changes** (B; was Safety page): Confirm resolution changes (one picker, one label set), Revert after N s (StepperSetting 5–60), Tell me when displays were restored, Restore All Displays shortcut (`ShortcutSetting`, default ⌃⌥⌘⎋), Allowed without asking (the single list); Resume Automation as a status row action while paused.
3. **Other display apps** (A): Pause overlapping features / Run both (radio).
4. **Resolution filters** (D): Offer modes below 720p · Remember my choice · Only native aspect ratio on the slider · Show values as · Snap to favorites · "Filters for <display>" disclosure (DPI filter, width limits, refresh filters).
5. **Experimental** (F lists, owners implement): HDR switch, Underscan, Built-in auto-brightness, Brightness broadcast (`osdBroadcast`, + notification name), Show all resolutions (`hiddenModes`) — each with an Experimental badge and one help line. Night Shift and Apple display presets move to Color › Advanced, HDR virtual modes to Virtual Displays › Advanced (owners keep their switches next to their settings).
Footer: Restore Defaults… (scope "Displays settings") · Done.

Sub-pages (each: `SettingsPageHeader` with the feature-group switch where one exists, own Advanced… when needed):

| Sub-page | Switch (features) | Visible | Advanced / removed |
|---|---|---|---|
| Brightness (C) | — | Restore brightness at login and wake (pop-up incl. Off = `brightnessRestore`) · Smooth transitions · Sync brightness (switch `sync`; source, follow, offset per display as subordinate rows) · Extra brightness (switch `xdr`, Beta, XDR displays only; "Maximum extra brightness" per display + "Pause below battery" SliderSettings subordinate) · Dim when the screen locks (switch `dimOnLock`; level slider subordinate) · Allow dimming to black (`dimToBlack`) · Show brightness in nits (`nits`; single field, duplicate 3) | A: **Brightness methods** (Apple native / DDC / Color table / Overlay checkboxes, per-display "Use" picker with "Now using …", custom switchover + slider, minimum hardware level, XDR method, color-table check "Ask Again"; moved from root Advanced, design M9), custom nits range fields, Stop at 100% detent, XDR default maximum, XDR "Pause in Low Power Mode", XDR Test, sync "Follow outside changes" |
| Color (C) | Color adjustments (`color`) | Display tiles · Software contrast, Gamma, Temperature, Black level, White level (5 SliderSettings) · Invert colors · Suspend on this display · Color profile (pop-up, `colorProfiles`) · Apple display preset (pop-up, when `applePresets` is on) | A: Color profiles switch (`colorProfiles`), Gain, per-channel RGB gain and gamma (6), profile actions pull-down (Show in Finder, Open in ColorSync Utility, Restore Previous), keep color-table dimming with custom profiles, suspend on all displays, shortcut step sizes, **Night Shift** (Experimental switch + "Night Shift warmth"), **Apple display presets** (Experimental switch); footer Restore Defaults… asks "This display / All displays" (replaces "Reset This Display") |
| Hardware Controls (C) | Hardware controls (`ddcControls`) | External display tiles · Use hardware controls for this display · Volume (`.live`) + Mute · Hardware contrast (`.live`) · Input (pop-up, if `ddcInput`) · Turn Off / Turn On (if `ddcPower`) · custom control sliders (if any are defined) | A: Input switching (`ddcInput`) and Power control (`ddcPower`) switches, read back values + interval, re-send after wake, per-control tuning as **disclosure rows** (raw 0/100%, invert, show in menu, read-back interval; no per-control sheet), input list editor, standby value, custom controls editor (`ddcCustom`), raw VCP get/set + unlock (disclosure), timing (reply delay, retries, write twice, ignore checksums, Forget Learned Framing), "Hardware information" (status, connection, framing, writes today, model, MCCS, supported codes; Read Capabilities, Check Connection) |
| Keyboard (C) | — | Brightness keys (switch `brightnessKeys`; "Change: display under the pointer / main / all" pop-up) · Volume keys (switch `volumeKeys`; target pop-up) · Indicator style (pop-up incl. "Use the system indicator" on 14/15) · Indicator position · Keyboard Shortcuts… (`ButtonRow` → sheet: **one grouped list** of all Displays actions — Brightness, Volume & contrast, Resolution (incl. favorites), Arrangement, Tools (Show Displays Panel, Identify, Redetect, Restore All Displays, Resume, Display Information, Stop Picture in Picture streams), custom actions — with filter field) | A: also let macOS handle brightness / volume / mute keys, steps / fine steps (StepperSetting), F14/F15, per-display "keys change this display", show volume indicator per display, sound output name, input slots, indicator "show on", show value, Preview Indicator; Modifiers reference → (i) popover |
| Saved Layouts (D) | Saved layouts (`layouts`) | Save Current Layout… · list (name, Matches badge, Apply, Details… sheet: apply automatically, priority, Trusted / Stop Trusting, Update to Current, Delete; drag or ▲▼ to reorder) · Protect the current arrangement (switch `protection`) | A: protected fields (5 checkboxes), Update Protected State to Current, Offer Undo after automatic apply, Forget All… |
| Virtual Displays (D) | Virtual displays (`virtualScreens`, Beta) | List (Connected switch, Details…) · New Virtual Display… (sheet with shape picker + recipes as tiles) · Sharper text on this display (Smart HiDPI, switch per display, Beta) | A: Sharper text switch (`smartHiDPI`, Beta), behavior toggles (3), "All Virtual Displays ▾" pull-down (Connect, Disconnect, Reconnect, Disassociate, Discard…), Smart HiDPI size and HDR (PQ), **HDR virtual modes** (Experimental switch); the Details sheet replaces the inline editor, "Sizes" becomes a table with + / − |
| Picture in Picture (E) | Picture in Picture (`pip`) | Screen Recording status row · Running list (Pause/Show/Stop; Crop in the row menu; Stop All in the section header) · Saved PIPs list (Start, Edit…) · New PIP… / New Stream… | Editor = sheet (name, show as, stream onto, window, capture, orientation, full screen, filters `pipFilters` sections); A: Filters switch (`pipFilters`), Never capture these apps (AppListEditor + Restore Defaults), pause covered PIPs, "⌃⌥⌘P stops streams" switch (shortcut in Keyboard Shortcuts), LUT import |
| Automations (A) | Section switches: Event hooks (`hooks`), Custom actions (`customActions`) | Hooks list (Enabled, When, Details… sheet) + Add Hook… · Actions list (Show in menu, Details… sheet with Run Now) + Add Action… | Sheets bind directly to config (fixes B2); action shortcuts also listed in Keyboard Shortcuts… |
| Display Information (F; design M4) | — | Live report (refreshes on change, no Refresh button) · Copy Report · Export… · safety-helper status rows · pending confirmation · undo journal · **Unavailable on this Mac** (user titles, never camelCase) · **Remembered displays** (Forget… per row, Forget All…; parity B2) · Remembered resolutions (Forget per row) | — |

**Awake** (G; header switch, AX label/tooltip "Use Awake", help in the header: "Off removes Awake from the menu bar and stops automatic sessions."; design B1, parity M7)

```
[☕] Awake                                        (●)   "Use Awake"
     Keep your Mac awake for a while, or whenever
     certain conditions are met.
─────────────────────────────────────────────────────
Keeping your Mac awake until 3:45 PM      [Extend ▾] [Turn Off]
1h 12m left · Started from the menu
   idle:   Not keeping your Mac awake                [Keep Awake]
           Ended at 3:12 AM: battery below 20%.     (12 h after a non-user end)
─────────────────────────────────────────────────────
Default duration                     [Until Turned Off ▾]
Keep the display on                                 (•)
  When off, your Mac stays awake but the display can turn off to save energy.
Durations in the menu                          [Edit…]
─────────────────────────────────────────────────────
End sessions automatically                           (laptops only)
When battery is low                                 (•)
    Below                     ━━━━●━━━━━━  [ 20% ] ↺
When the power adapter is disconnected              ( )
─────────────────────────────────────────────────────
Start automatically                                 (•)   (shown once a condition exists)
  While a display is connected            Active   (i)
  [Add Condition…]                     [Pause for 1 Hour]
   none yet: Keep your Mac awake automatically, for example while a
             display is connected.        [Add Condition…]
─────────────────────────────────────────────────────
Keyboard Shortcuts…
Drives                                          Off  ›
History                               Today 2h 10m  ›
Menu bar icon                  Own Icon When Active  ›   (opens Menu Bar)
                                      Advanced…  (?)
```

| Section | Controls | Where |
|---|---|---|
| Status | Status row (reaches everything when the status item is hidden, 26/27). Idle: "Not keeping your Mac awake" + **Keep Awake** (default preset). Active: "Keeping your Mac awake until 3:45 PM" / "…until downloads and tasks finish" / "…while a script is running" + detail "1h 12m left · Started from the menu" + **Extend ▾** (Add 15 Minutes, Add 1 Hour, Add Time…; timed and capped kinds only) + **Turn Off**. Last non-user end for 12 h. Buttons only, no switch (N5) | V |
| Durations | Default duration (pop-up of presets; sets `defaultPresetID`) · Keep the display on (edits `defaultOptions.display`; parity M5) · Durations in the menu: Edit… (preset sheet) | V |
| End sessions automatically | When battery is low (switch; turning off is consent-protected) + Below (SliderSetting 5–50%, step 5, default 20, subordinate) · When the power adapter is disconnected | V (laptops only) |
| Start automatically | Empty: help text + Add Condition…. Otherwise: switch (`triggers`); trigger list (switch, name, `TriggerEngine.summary`, "Active"/"Waiting" badge, (i) for details), drag to reorder (help "Higher in the list wins.") · Add Condition… · Pause for 1 Hour / Resume | V |
| Keyboard | Keyboard Shortcuts… (sheet: Keep Awake, Keep Display On, Start preset 1–4, Pause automatic sessions) | V |
| Navigation | Drives › (J) · History › (G) · Menu bar icon › (jumps to Menu Bar, parity minor 14) | V |
| Footer | Advanced… · (?) | V |
| Advanced (11) | Activity: **Appear active** (`activity`; help "Keeps apps from marking you as away while a session runs.") · **Move the pointer slightly** (Experimental `pointerNudge`; help "Moves the pointer 1 point and back. Needs Accessibility."; Accessibility footer + fix button) · Stop after no input for (1–8 h pop-up, default 1 h). End sessions automatically: When your Mac sleeps · When you switch users (Immediately / After 1 Hour / Never) · When Low Power Mode turns on · After the screen has been locked for (Never / 1 / 4 / 12 hours); footer "Sessions always end if your Mac gets very hot." Display: Keep the display on while locked (C1). Restart: Continue sessions after Snaptic restarts · Start a session when Snaptic opens (pop-up of presets / None). **Other apps keeping your Mac awake** (inline live section, design M4: process names and assertion types, a warning row when system-wide `SleepDisabled` is on — "Sleep is turned off for this Mac by another app or command. Snaptic can't change this."; empty "No other apps are keeping your Mac awake."). Footer leading Restore Defaults… (scope "Awake settings"; keeps history; turns nudge and Drive Alive off) | A |

Turning the header switch off while a session or an enabled trigger exists asks first: "Turn off Awake? This ends the current session and stops automatic sessions." [Turn Off] [Cancel] (parity M7).

Durations sheet (`PresetEditorSheet`): `ReorderableList` of presets with + / −; each row has an **Options** disclosure: name, kind (Until turned off / For a duration (h, m NumberFields) / Until a time (time picker) / Until downloads and tasks finish (CPU below, network below, quiet for)), Display (*Default (Keep on)* / Keep on / May sleep / Keep on while I'm active + minutes), Activity (*Default* / Off / Appear active / Move the pointer slightly; only when `activity` is effective). The page pop-up chooses the default (no ★).

Trigger editor sheet (`TriggerEditorSheet`): kind picker as tiles → kind-specific fields (router kind titled **"Connected to this network"**); All / Any; session options; start/end delays under a disclosure; name.

**Drives** (J, sub-page of Awake): header switch "Keep drives awake" (`driveAlive`) · eligible volumes list with switches (turning one on records consent and triggers the first write) and per-row status ("Can't keep this drive awake: …") · Interval (SliderSetting 30–600 s, default 120) · Even without a session. Empty: "Connect an external drive to keep it from spinning down."

**History** (G, sub-page): totals row (Today, Last 7 days) · list (Start Again in the row menu; app sessions use their locally stored bundle id) · Clear History…. Empty: `ContentUnavailableView("No Sessions Yet", systemImage: "cup.and.saucer")`.

**Permissions** (H): Accessibility and Screen Recording rows (state, "Needed by …", Open Settings, Show Snaptic in Finder, relaunch), Removable Volumes info row when Drive Alive is on ("macOS asks the first time Snaptic writes to a drive"), signer line (R5.7).

**About** (H): app icon, version, Check for Updates…, Acknowledgements… (sheet with MIT text and credits), Diagnostics Report… (navigates to Displays › Display Information when Displays runs, else a host report sheet).

**Counts** (r2, design M1; rule in §4.2; 1 built-in + 1 DDC external, default features, built-in selected):

| Page | Settings | Buttons + nav rows | Total | Notes |
|---|---|---|---|---|
| General | 2 | 3 | 5 | card not counted (one-time) |
| Menu Bar | 8 | 1 | 9 | Snaptic tiles, 3 pop-ups, Awake Show + Icon, display controls, scroll |
| Window Switcher | 8 | 1 | 9 | shortcut, show, style, preview, auto size, minimized, Spaces, release |
| Displays root | 6 | 4 + 9 nav | 19 | hub exception; without nav rows 10 |
| Brightness | 6 | 0 | 6 | |
| Color | 8 | 0 | 9 | + display tiles |
| Hardware Controls | 5 | 1 | 7 | + display tiles (external only) |
| Keyboard | 6 | 1 | 7 | |
| Saved Layouts / Virtual / PIP / Automations | 1 / 1 / 0 / 2 | 2 / 2 / 4 / 4 | 3 / 3 / 4 / 6 | lists count 1 |
| Awake | 5 | 3 + 3 nav | 11 | default duration, keep display on, battery low + below, adapter; desktop: 2 settings, 8 total |
| Advanced sheets | — | — | General 4, Switcher 21, Displays 25, Brightness 20, Color 15, Hardware 18, Keyboard 14, Awake 11 | ≤ 25 each |

Default-visible settings across the five root pages ≈ 30, ≈ 60 including sub-pages (was ≈ 245).

### 4.4 Duplicates ([UA] §2.4) — one owner each

| # | Duplicate | Resolution |
|---|---|---|
| 1 | Confirm resolution changes (Resolution + Safety) | Displays › Advanced › Confirm display changes only; one label set |
| 2 | Allowed without asking (DDC + Safety) | Displays › Advanced › Confirm display changes only |
| 3 | Show nits (`brightness.showNits` + `keys.osdShowNits`) | One control `brightness.showNits` (migration M5) on Brightness |
| 4 | Display order/visibility (Names + Menu) | Menu Bar › Customize Displays Menu… only; Display Details has a "Menu visibility…" link, not a control (parity M6) |
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
| 15 | Awake "on" twice (module switch vs session switch, parity M7 / design B1) | Header switch = module ("Use Awake"); sessions = buttons (Keep Awake / Extend ▾ / Turn Off) in Settings, native items + a mouse switch in the menu |
| 16 | Awake icon off in three places (`indicator`, style `.hidden`, `ownItem`; parity M1) | `MenuPresence` only; `.hidden` style deleted; `indicator` is an internal capability |

### 4.5 Live-update architecture (fixes [UA] §1 at the source)

| Change | Owner | Fixes |
|---|---|---|
| `DisplayRuntime` gains `@Published brightnessPosition: Double?` (full range incl. XDR), `brightnessRange: ClosedRange<Double>`, `contrastRange`, `volumeRange`; BrightnessService/DDCController write only through these; pages never read `BrightnessService.states` | lead (type), C (writers) | A1, A2, overview 0…1 range |
| Per-display sections are subviews with `@ObservedObject var live: DisplayRuntime` (the `DisplayControlsCard` pattern) | page owners | A1, A2 |
| **Per-controller revision objects** (code M12): `DisplaysRuntimeState.revision(_ id: DisplayControllerID) -> ControllerRevision`, one `ObservableObject` per id with `@Published private(set) var count: UInt64`; `bump()` coalesced to one publish per main-queue turn per id, ≤ 15 Hz; a section observes only the ids it shows. Controllers bump when page-visible state changes (rotation/HDR/underscan, protection, layouts, virtual live/busy, Smart HiDPI pairs, undo/redo/favorites, Night Shift, guard status, capture sessions) | lead (type), B/C/D/E (bumps) | A4, A6–A11; delete the `objectWillChange.send()` pokes and Safety's 2 s timer (lint L7) |
| **Config slices** (code M12): `ConfigSlice<T, V>` (lead, `Core/ConfigSlice.swift`) publishes only when `store.value[keyPath:]` changes; `DisplaysPageEnvironment` stops forwarding the config store's `objectWillChange` (it forwards only `displays`, `effectiveFeatures`, `availability`, `moduleState`, panic flags); every section reads config through a slice of its own `DisplaysConfigSection` | lead (type), page owners | a 15 Hz slider commit re-renders one section, not the whole Displays tree |
| **Live hardware path** (code M12): `DisplayLiveControlling` (lead protocol, C implements) is the only route from a `.live` slider to hardware; a latest-wins mailbox per (display, control), DDC writes ≤ 20 Hz, `phase: .ended` always delivered; the slider shows `drag ?? live value` | lead, C, H | "laggy drags", fights between readback and drag |
| No `@State(initialValue:)` copies of model values; editors bind to the store or resync with `.onChange(of:)` | owners of ShortcutEditor (H), Hook/Action/CommandEditor (A), NameField (F), CustomSliderRow (C, seeded from `ddc.lastReading`) | A3, B1–B3 |
| `SliderSetting` drag-local state: `@State drag: Double?`; shows `drag ?? value`; commit per `SliderCommit`; final value on release; `preview` for live hardware feedback without config writes | H | C1 "laggy drags" |
| Config fan-out by section: Kit `DisplaysConfig.changedSections(old:new:) -> Set<DisplaysConfigSection>`, with `perDisplay` split into subsection cases (`perDisplayColor`, `perDisplayBrightness`, `perDisplayManagement`, `perDisplayDDC`, `perDisplayResolution`, `perDisplayIdentity`); `DisplayFeatureController` gains `static var observedSections: Set<DisplaysConfigSection>` with a **protocol-extension default of `allCases`** (so the ~21 conformers compile at step 0); `DisplaysModule.configChanged` notifies only controllers whose sections changed; `ColorController` re-applies gamma only for displays whose `perDisplay.color` changed | lead (+ every controller narrows its sections in step 2) | C1 fan-out, gamma reapply per tick |
| `ManagementBindings.perDisplay` and other binding helpers stop calling `sanitized()` per tick (ConfigStore sanitizes on load and external change; UI ranges are already clamped); binding helpers collapse to `SettingsBinding` (H) | H + D | C1 |
| Switcher `AppSettings` saves through a 250 ms debounce like `ConfigStore` | A | C2 |
| `MenuSliderRow` (M, AppKit) replaces `MenuSliderItem` for brightness, volume, contrast and custom DDC sliders: value label, `range` in init, `bind(to:)` so values follow live changes while the menu is open; never fights a drag. The resolution slider is not in the menu (no sliders in submenus; the root page keeps it in Resolution options) | M (+ C contributors adopt) | M1 |

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
extension DisplayFeatureController { static var observedSections: Set<DisplaysConfigSection> { Set(DisplaysConfigSection.allCases) } }
```

Rule (lint + review): a Settings view may read controller state only inside a view that observes the relevant `ControllerRevision` or `DisplayRuntime`.

### 4.6 Config migration (no setting lost)

All migrations are pure Kit functions with tests. **Each runs once**: the containing model gets a lossy `migrations: [String]` marker list (`DisplaysConfig`, `ModulesConfig`, `AwakeConfig`), a migration records its id after running, and never runs again (code M3; a later user "off" sticks). **Legacy fields stay declared, decoded and encoded until 0.4** (struct Codable drops undeclared keys; only `LossyMap` keeps unknown ones), so a downgrade to 0.2 still reads them. Old-key removal is a 0.4 task.

| # | From | To | Where |
|---|---|---|---|
| M1 | `DisplaysConfig.features.sleepPrevention` + `perDisplay.*.management.preventSleep` (+ that display's `identity.fingerprint`, `customName`/`lastKnownName`), read from raw JSON | Awake triggers "While a display is connected" (`.any` over `display(.specific)`, options `.keepOn`), **at most 8 displays per trigger** (more → "… (2)", "… (3)"); enabled iff 0.2 sleep prevention was **effective**: Displays module enabled ∧ feature on ∧ ≥ 1 display flagged (parity "Also"); if enabled, Awake module (presence `.ownIconWhenActive`) and `triggers` turned on; marker `fromDisplays.v1`; afterwards `save(force: true)` on both stores | Kit `AwakeMigration.fromDisplays(rawJSON:modulesEnabled:) -> AwakeMigrationResult` (G), run by `ModuleHost` after the Awake-disabled insertion (§2.13) and before modules start (lead) |
| M2 | `ModulePreferences.placement` (`shared/ownIcon/hidden`) | `presence: MenuPresence` (`.inSnapticMenu/.ownIcon/.hidden`); `placement` keeps being **written** from presence (`.ownIconWhenActive` → `.ownIcon`) so 0.2 reads it; Awake default `.ownIconWhenActive` | `ConfigModules` decode (lead) |
| M3 | `ModulesConfig.showNewDisplaysCard` | `newModuleCards: [String]` decoded as strings and filtered to known `ModuleID`s (a `Set<ModuleID>` would fail as a whole on one unknown id) | lead |
| M4 | `MenuConfig.showPanelShortcut`, `identifyShortcut` | `keys.shortcuts[showPanel]`, `[identify]` when those are unset; marker `menuShortcuts.v1`; legacy fields kept and encoded | `DisplaysConfig.init(from:)` post-decode (lead) |
| M5 | `keys.osdShowNits` (default false) | once: if `keys.osdShowNits` is true, set `brightness.showNits = true` (default true); otherwise leave it. r1 re-ran the OR on every decode, so a user's later "off" came back at the next launch (code M3); marker `showNits.v1` | `DisplaysConfig` post-decode (lead) |
| M6 | `SafetyConfig.panicHotkeyEnabled` + fixed combo | `panicHotkey` editable; enabled → default combo stored explicitly; marker `panicHotkey.v1`; legacy bool kept | B |
| M7 | Switcher features `otherSpaces`/`windowlessApps` vs per-shortcut flags | unchanged storage; UI only | — |
| M8 | Raw feature flags of features without a switch in the new UI | unchanged; each still reachable (§4.8) | — |
| M9 | Awake indicator legacy values (r1 drafts never shipped) | none needed; `AwakeIndicatorConfig.sanitized()` maps unknown glyphs to `.cup` | — |

Page **Restore Defaults…** resets only that page's scope through Kit functions (`AwakeConfig.restoringDefaults()`, `DisplaysConfig.restoringDefaults(scope:)`, `MenuConfig()` etc.), each tested to leave other scopes, salts and history untouched and to turn protected Awake features **off** (security L6). `AwakeConfig.restoringDefaults()` is written by G in step 2 (it needs G's and J's fields; code M14); step 0 has a stub returning `AwakeConfig()`.

### 4.7 Onboarding (H)

Welcome → Choose modules (3 rows with switches and one-line descriptions; Awake preselected for fresh installs) → Displays chips (existing; summary lists **user words**, not feature ids; chips are toggles) → Awake quick setup (default duration pop-up, battery switch, line "The Awake icon appears while your Mac is being kept awake."; skipped if Awake is off) → Permissions (only what was chosen) → Done. One primary button, always in the window footer ("Continue" / "Done"); the in-form "Use These Features" button is removed.

### 4.8 0.2 → 0.3 control map (normative; parity B2)

One row per 0.2 control in [UA] §2.2 and §3.2 (identical per-display or per-item controls share a row). Destinations: **V** visible on the named page, **A** that page's Advanced sheet, **S** sub-page, **D** Display Details sheet, **K** a Keyboard Shortcuts sheet, **C** Customize Displays Menu sheet, **I** Displays › Display Information, **M** menu, **X** removed (reason given). Pages: Gen = General, MB = Menu Bar, Sw = Window Switcher, Root = Displays root, Br = Brightness, Col = Color, HW = Hardware Controls, Kb = Keyboard, SL = Saved Layouts, VD = Virtual Displays, PIP, Aut = Automations, Aw = Awake. Kit test (H + owners, `ControlMapTests`): every `Codable` key path in the 0.2 "all features on" fixture maps to a `SettingsSearchEntry.id` or to `ControlMap.removedSettings` (a Kit table of key path → reason); both tables are checked for unknown ids.

**General**

| 0.2 page | 0.2 control | 0.3 home |
|---|---|---|
| Modules | Window Switcher switch · Displays switch | Sw / Root header switches; Onboarding |
| Modules | "New: Displays" card (Turn On Displays…, Not Now) | Gen card, generalized (`newModuleCards`) |
| Menu | Switcher **Show** · Displays **Show** | MB pop-ups |
| Menu | Switcher **Icon** · Displays **Icon** (own icon) | MB glyph tiles under the module (Own Icon) |
| Menu | Displays "Hide the icon when no external display is connected" | MB (subordinate, Own Icon) |
| Menu | Snaptic **Icon** | MB Snaptic icon tiles |
| Menu | Scroll on a slider to adjust | MB V |
| Menu | Display blocks Expanded/Compact | MB "Display controls" |
| Menu | Main display first · Status badges · Header row with one display · Section order ▲▼ · Display order ▲▼ + Use the Default Order | C |
| Menu | ≈ 20 Visible/In submenu/Hidden pickers | C (grouped, human titles; sliders Visible/Hidden only; right-click items X → Display Tools, C3) |
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
| Features | Permission rows | Permissions page; Sw status row when Screen Recording is missing |
| Shortcuts | Primary: Modifier, Key, Show, Style, Spaces, Include minimized and hidden | Sw V |
| Shortcuts | Primary: Include apps with no open windows · One entry per app | Sw A |
| Shortcuts | Other shortcuts (all options), Add shortcut, Delete | Sw K |
| Shortcuts | Gather windows recorder | Sw K |
| Behavior | Switch when the modifier key is released | Sw V |
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
| `hiddenModes` · `autoBrightness` · `osdBroadcast` · `underscan` · `hdrToggle` | Root A › Experimental |
| `scaleMatch` | D › Match text size (disclosure switch) |
| `menuBarOverlays` | D › Menu bar overlays (group switch) |
| `autoDisconnectBuiltin` (Beta) | D (built-in) › Connection |
| `brightnessApple`, `brightnessDDC`, `brightnessGamma`, `brightnessOverlay` | Br A › Brightness methods |
| `brightnessRestore` · `dimToBlack` · `dimOnLock` · `nits` · `xdr` · `sync` | Br V |
| `color` | Col header switch |
| `colorProfiles` · `nightShift` (X) · `applePresets` (X) | Col A |
| `ddcControls` | HW header switch |
| `ddcInput` · `ddcPower` · `ddcCustom` | HW A |
| `brightnessKeys` · `volumeKeys` | Kb V |
| `layouts` · `protection` | SL header switch · SL V |
| `virtualScreens` · `smartHiDPI` · `hdrVirtual` (X) | VD header switch · VD A · VD A |
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
| Features | "X is off · Turn On" rows on other pages | X (FeatureHighlights + header/section switches) |
| Resolution | Confirm resolution changes | Root A › Confirm display changes |
| Resolution | Offer modes below 720p · Remember my choice · Show values as · Snap to favorites · Only native aspect ratio | Root A › Resolution filters |
| Resolution | Mode picker · Refresh rate | Root V |
| Resolution | Quick buttons (HiDPI, Native, Default, Native ÷ 2, Notch) | Root V › Resolution options › Quick Changes ▾; Kb K |
| Resolution | Undo / Redo | Root V › Resolution options; M display submenu (when available); Kb K |
| Resolution | Add to Favorites · favorite rows (Apply/Remove) | Root V › Resolution options; favorites in the Resolution pop-up and M submenu |
| Resolution | Show (DPI filter) · Width limit Min–Max + Clear · refresh filter | Root A › Resolution filters › Filters for <display> |
| Resolution | Include in Match UI Size | D › Match text size |
| Resolution | Forget remembered | D "Forget Remembered Resolution"; I list |
| Resolution | Show all modes: display picker + Try list | Root V Resolution pop-up "Show All Resolutions" section (with `hiddenModes`) |
| Resolution | Match UI size: Reference display, Preview/Apply | D › Match text size |
| Resolution | Match tolerance slider | D › Match text size |
| Brightness | Display picker | Br/Root tiles (`PerDisplayPicker`) |
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
| Arrangement | Disconnect "Header switch" per display | C |
| Arrangement | Connect/Disconnect per display | D; M submenu |
| Arrangement | Connect All | Root Display Tools ▾; M Display Tools |
| Arrangement | My monitor has no DDC · Never auto-disconnect built-in | D › Connection |
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
| Display Names | Name · Use the System Name · Icon · Details disclosure · EDID Copy Hex/Base64/Export · Copy Settings From… | D |
| Display Names | Show in the menu and the Displays panel · Menu order ▲▼ | C (D has a "Menu visibility…" link) |
| Display Names | Remembered: Forget… · Forget All… | I › Remembered displays |
| Safety | Confirm resolution changes · Revert after N s · Tell me when displays were restored · Restore All shortcut (now editable) · Allowed without asking | Root A › Confirm display changes |
| Safety | Restore All Displays Now | Root Display Tools ▾; M Display Tools (kept top-level in the Displays section while a confirmation is pending); panel |
| Safety | Resume | Root A status action; M status row |
| Safety | Helper status · Can revert rotation and HDR · Pending confirmation · Undo journal · Remembered resolutions · Unavailable on this Mac | I |
| Diagnostics | Copy Report · Export… · report + events | I (live) |
| Diagnostics | Refresh | X (I refreshes on change) |
| Onboarding | Module switches · Displays chips · Hide the menu-bar icon · Turn on Smart HiDPI | Onboarding (chips as toggles; summary in user words) |
| Onboarding | In-form "Use These Features" | X (one primary button in the footer) |

**0.2 menu** ([UA] §3.2)

| 0.2 item | 0.3 home |
|---|---|
| Enable Thumbnails (Screen Recording)… | M "Turn On Thumbnails…" action item (not a status row) |
| "Press ⌥⇥ to switch windows" | M "Switch Windows ⌥⇥" (C8) |
| Gather Windows on This Display | M |
| Display header (bold, no action) | M device row with submenu |
| Brightness / volume sliders | M `MenuSliderRow` with live value |
| More ▸ › Resolution slider | X in the menu (no sliders in submenus); Root V › Resolution options |
| More ▸ › Resolution ▸ quick actions | X in the menu; Root V Quick Changes ▾; Kb K |
| More ▸ › Resolution ▸ Undo / Redo | M display submenu (when available) |
| More ▸ › Resolution ▸ Favorites · modes | M display submenu (≤ 8 modes incl. favorites) + "More Resolutions…" |
| More ▸ › Brightness Method ▸ | X in the menu (expert); Br A |
| More ▸ › Mirroring ▸ · Set as Main Display | M display submenu ("Use as Main Display", "Mirror “X”") |
| More ▸ › Mute | M display submenu "Mute" |
| More ▸ › Contrast slider | M top-level slider row when set Visible in C (default Hidden); HW V |
| Tools › Restore All · Identify · Redetect · Show Displays Panel | M Display Tools ▸ |
| Tools › Arrange… | M "Arrange Displays…" |
| Tools › More Display Features… | X (Settings › Displays) |
| Right-click quick menu | X (C3; items in Display Tools ▸ and the footer) |
| Settings… · Quit Snaptic | M "Snaptic Settings…" · "Quit Snaptic" |

## 5. Menu bar redesign (M owns the system; module owners own their sections)

### 5.1 MenuKit (M, `Core/MenuKit.swift`, `Core/MenuSliderRow.swift`, `Core/MenuSwitchHeader.swift`)

Custom rows are **AppKit only** (design M11, code minor 4): no `NSHostingView` in any menu (lint L13). They size immediately, keep the 26/27 menu material's vibrancy, and need no activating click.

```swift
@MainActor enum MenuKit {
    static let width: CGFloat = 300                          // menus containing custom rows
    static func header(_ title: String) -> NSMenuItem        // NSMenuItem.sectionHeader(title:) — the ONLY header style
    static func action(_ title: String, symbol: String? = nil, key: String = "",
                       modifiers: NSEvent.ModifierFlags = .command, enabled: Bool = true,
                       _ handler: @escaping @MainActor () -> Void) -> NSMenuItem
    static func toggle(_ title: String, isOn: Bool, symbol: String? = nil, enabled: Bool = true,
                       _ handler: @escaping @MainActor () -> Void) -> NSMenuItem      // checkmark
    static func alternate(of item: NSMenuItem, title: String,
                          _ handler: @escaping @MainActor () -> Void) -> NSMenuItem  // ⌥, isAlternate
    static func submenu(_ title: String, symbol: String? = nil, enabled: Bool = true,
                        _ items: [NSMenuItem]) -> NSMenuItem   // one level only (asserted in debug)
    static func status(_ text: String, symbol: String? = nil) -> NSMenuItem          // disabled info row
    static func device(_ title: String, symbol: String, submenu: [NSMenuItem]) -> NSMenuItem   // display rows
    /// Secondary line under an item: `NSMenuItem.subtitle` on 14.4+ (`#available`), else a disabled
    /// indented item after it (14.0–14.3). Used for "Main", "Active", the current resolution (design M11).
    static func withSubtitle(_ item: NSMenuItem, _ subtitle: String?) -> [NSMenuItem]
    /// AppKit view row: bold title + NSSwitch (.small, as in the Wi-Fi menu) + up to two secondary lines
    /// (NSTextField, secondaryLabelColor). 300×26, 300×40 or 300×54; no fills. Mouse only: the same action
    /// always exists as a native item (parity M4).
    static func switchHeader(_ title: String, isOn: Bool, detail: [String],
                             onToggle: @escaping @MainActor (Bool) -> Void) -> NSMenuItem
    static func settings(_ title: String, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem   // ⌘,
    static func quit() -> NSMenuItem                                                                     // "Quit Snaptic" ⌘Q
}
@MainActor final class MenuSliderRow: NSMenuItem {
    /// AppKit view 300×30: leading 16 pt template symbol in the image column, NSSlider (.regular) on the text
    /// column, trailing value label 40 pt (monospacedDigitSystemFont, secondaryLabelColor); measured per OS [HW-15].
    init(title: String, symbol: String, value: Double?, range: ClosedRange<Double>, format: ValueFormat,
         onChange: @escaping @MainActor (Double, DragPhase) -> Void)
    func bind(to publisher: AnyPublisher<Double?, Never>)   // live updates while open; ignored during a drag
    func setValue(_ v: Double?)                             // nil → slider disabled, value "—"
}
```

Item rules: Title Case; ellipsis only when more input follows; toggles use checkmarks or a changing title; submenus one level deep, ≤ ~10 items plus at most one "More…" that opens Settings. **Images: all items of a section or none** (design m1; 15-SDK builds show every attached image on 26/27, [DS] §3.3): the Displays section gives every item a 16 pt template symbol (device rows, `rectangle.3.group` for Arrange Displays…, `wrench.and.screwdriver` for Display Tools); the Switcher and Awake sections use none, except the app rows of "While an App Is Running ›", which is its own group (parity minor 11). Custom rows are never clickable themselves; every slider action and every switch-header action also has a native path (C4). `ClosureMenuItem`, `CMenu.item`, `ManagedMenuItem`, `DisplayMenuBlock.actionItem`, `PanicMenuItem`, `MenuSliderItem` are deleted **at the step-3 exit** after a caller grep, tracked in the ratchet until then (code M10); contributors move to MenuKit during steps 1–3 (lint L6 bans `NSMenuItem(` outside the MenuKit files; permanent ratchet rows: `AppDelegate.swift` main menu, `PIPWindow.swift` context menu).

### 5.2 Snaptic icon menu (shared item)

**When it exists** (Kit `StatusItemPlan`, parity M3): the Snaptic item is shown iff some running module is In Snaptic Menu, or the compact Awake section is due (§5.4), or no module has its own icon or custom item. When it is absent, every own-icon and custom menu ends with native **Snaptic Settings…** and **Quit Snaptic ⌘Q** items (not alternates), and Awake's menu adds **Recent Notices ›** when there are notices. **Active variant** (N11): while Awake governs and no Awake icon is visible, the Snaptic glyph switches to its `.fill`/badge-dot variant and its accessibility label appends ", keeping your Mac awake".

Built in `menuNeedsUpdate` from the plan, in start order; sections separated by one separator; values update in place while open.

```
[Safe Mode is on]                                    status row + "Leave Safe Mode" (only in Safe Mode)
Window Switcher                                      header
  Switch Windows                              ⌥⇥    C8 (sticky switcher)
  Gather Windows on This Display
  Turn On Thumbnails…                                action item, only while Screen Recording is missing
───
Displays                                             header
  [▭] Studio Display                          ›     device row; subtitle "Main"
  [☀] ━━━━━━━━●━━━━━  70%                            MenuSliderRow (brightness)
  [▭] DELL U2720Q                             ›
  [☀] ━━━━━●━━━━━━━━  45%
  [🔈] ━━━●━━━━━━━━━━  30%                            volume only if VCP 0x62
  [↺] Restore All Displays                            top-level only while a change awaits confirmation
  [▦] Arrange Displays…
  [🔧] Display Tools                           ›     Identify Displays · Redetect Displays · Show Displays Panel · Connect All Displays · Restore All Displays (C3)
───
Keep Awake                                   [●]    compact Awake section (§5.4), no section header (design m3)
  Until turned off
Turn Off Keep Awake
Keep Awake For                                ›
While an App Is Running                       ›
───
Recent Notices                                ›     only when there are some
Snaptic Settings…                            ⌘,
Quit Snaptic                                 ⌘Q
```

Display submenu (one level, ≤ ~12 items; design m2):

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
Input                                               header (DDC, if `ddcInput`)
✓ USB-C
  HDMI 1
  Mute                                              if volume
───
  Turn Off Display                                  (if `ddcPower`) · Disconnect (if `disconnect`)
  Display Settings…
```
Color toggles and the brightness-method choice are not in the menu (Settings only). Per-item visibility (Customize Displays Menu) still applies; "In submenu" means this display submenu; sliders can be Visible or Hidden only. With no modules enabled: "No Modules Are On" status row + "Open Settings…". With `Compact` display controls: one slider per display, device rows without subtitles.

Kit (M, `SnapticKit/MenuLayout.swift` + `Config/ConfigModules.swift`):

```swift
package enum MenuPresence: String, Codable, CaseIterable, Sendable {
    case inSnapticMenu, ownIcon, ownIconWhenActive, hidden     // ownIconWhenActive: Awake only (sanitized → ownIcon elsewhere)
    package var legacyPlacement: MenuPlacementChoice { get }   // written for 0.2 downgrades (migration M2)
}
package struct StatusItemPlan: Equatable, Sendable {
    package var shared: [ModuleID]           // sections in the Snaptic item, in start order
    package var ownIcon: [ModuleID]          // host-built own items
    package var custom: [ModuleID]           // provider-built items that should exist now (Awake); StatusMenu builds no slot
    package var awakeCompactInShared: Bool
    package var sharedActiveGlyph: Bool      // N11
    package var showShared: Bool
    package var sharedFooterInOwnMenus: Bool // Snaptic item absent → Settings… and Quit in every own/custom menu
    package var noModulesEnabled: Bool
    package var everythingHidden: Bool
}
extension ModulesConfig {
    package func statusItemPlan(running: Set<ModuleID>, awakeActive: Bool, awakeShortcutBound: Bool) -> StatusItemPlan
}
// Config/ConfigModules.swift (lead): ModulePreferences gains `presence`; `placement` stays declared and is written from it
//   package var presence: MenuPresence
//   package init(enabled: Bool, presence: MenuPresence = .inSnapticMenu, symbol: String = "", hideWithoutExternalDisplay: Bool = false)
//   package static func defaultPreferences(_ id: ModuleID) -> ModulePreferences   // per id: .awake → (true, .ownIconWhenActive)
```
Awake rows of the plan (tested truth table): `.ownIcon` → custom item always; `.ownIconWhenActive` → custom item while active, compact section in the Snaptic item while idle; `.inSnapticMenu` → compact section always, `sharedActiveGlyph` while active; `.hidden` (only selectable with a bound shortcut) → nothing at rest; while active `sharedActiveGlyph` if the Snaptic item exists, otherwise the custom item appears for the session (N11). `StatusMenu.hasVisibleItem` and `everythingHidden` count provider items through `StatusItemProvider.statusItem` (code B3).

### 5.3 Awake status item (G, `IndicatorController`, exposed through `AwakeModule: StatusItemProvider`)

`NSStatusItem(variableLength)`, `autosaveName = "SnapticAwake"`, `behavior = .removalAllowed`. KVO on `isVisible` ignores changes made by Snaptic itself and during teardown (a flag around our own writes), and `isVisible = true` is set whenever the item is re-created, because the autosave name restores `false` after a removal (code minor 5). A user ⌘-drag removal sets Awake's presence to In Snaptic Menu with the toast "Awake's menu bar icon was removed. Awake is now in the Snaptic menu; change this in Settings › Menu Bar." With `.ownIconWhenActive`, the item is created when a session starts and removed when it ends (deferred while its menu is open).

Look (design M7): template SF Symbol with `SymbolConfiguration(pointSize: 15, weight: .regular, scale: .medium)` (compared optically with Wi-Fi), outline when idle, `.fill` when active, same width; `imagePosition = .imageLeading`; text set with `button.title` and `button.font = .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)` — **never an `attributedTitle` with a color** (breaks the system's menu-bar text treatment on transparent 26/27 bars and under Increase Contrast). Text: *Icon and Time Remaining* → `AwakeCountdown.short` ("1h 42m", "42m", "42s") for timed and capped sessions; *Icon and End Time* → `AwakeCountdown.clock` ("5:00 PM", system 12/24 h); indefinite, uncapped task and automatic sessions show the glyph only. Redraw at `AwakeCountdown.nextChange` (minute boundaries; 1 s in the last minute), `.common` mode. **Accessibility label and tooltip are refreshed at every `nextChange` tick**, also in icon-only style: "Awake, 1 hour 42 minutes remaining" / "Awake, until turned off" / "Awake, off" (design M8).

Menu (plain `statusItem.menu`, identical on 14–27; design M3 mockup + parity M3/M4/minors 5, 7, 10):

```
Keep Awake                                   [●]   switchHeader (mouse): on → default preset, off → Turn Off
  Until 3:45 PM · 1h 12m left                      detail 1: "Until turned off" / "Until downloads and tasks finish" /
                                                   "While Xcode is running" / "While a script is running" / "Automatic: Desk dock";
                                                   idle: "Ended at 3:12 AM: battery below 20%." (12 h) or
                                                   "Ended because the battery is below 20%." (guard holding)
  Closing the lid will put your Mac to sleep.      detail 2: laptops not in desktop mode, only while active
Turn Off Keep Awake                                native item, only while active (keyboard/VoiceOver path, parity M4)
────
Add 15 Minutes                                     timed and capped sessions only (parity minor 5)
Add 1 Hour                          ⌥ Add Time…    alternate opens the Until a Time or Duration panel in extend mode
✓ Keep Display On                                  always present (menu never grows while open); idle: edits the default
────
  For 30 Minutes                                   presets in order; ✓ = running preset; choosing it again restarts the timer
✓ For 1 Hour
  For 2 Hours
  For 5 Hours
  Until Turned Off
  Until Downloads and Tasks Finish                 parity B1
  Until a Time or Duration…                        small titled panel: For | Until, h/m fields or a time picker, Return = Start
  While an App Is Running          ›               running regular apps (recent first, ≤ 12, app icons; own group)
────
Automatic: Desk dock (active)                      status line, only with `triggers`; "Automatic: waiting for Desk dock" / "Automatic sessions are paused until 4:00 PM"
Automatic Sessions                 ›               rows read-only (subtitle "Active"/"Waiting"; click opens the rule in Settings;
                                                   ⌥ alternate "Turn Off “Desk dock”"); active rules + ≤ 4 others;
                                                   ─ Pause for 1 Hour · Pause Until Tomorrow (or Resume Automatic Sessions) · Edit Automatic Sessions…
────
Recent Notices                     ›               only when the Snaptic item is absent and notices exist
Awake Settings…
Quit Snaptic                        ⌘Q             only when the Snaptic item is absent (parity M3, design m4)
```
Idle: 13 rows with triggers (11 without); active timed: 16. Every common task takes ≤ 2 clicks and has a keyboard path. "Start Anyway" never appears in the menu: a refused start shows a toast with the button (parity minor 9).

### 5.4 Compact Awake section in the Snaptic menu

Shown when the plan's `awakeCompactInShared` is true (§5.2), with no section header: switchHeader "Keep Awake" with detail · Turn Off Keep Awake (active) · Add 1 Hour (timed or capped) · Keep Awake For › (presets, Until Downloads and Tasks Finish, Until a Time or Duration…) · While an App Is Running › (its own submenu; parity minor 11). No triggers list (Settings and the Awake item have it).

### 5.5 macOS 26/27 hidden and overflow behavior

There is no API to learn that the system hid an item (26 "Allow in the Menu Bar", 27 overflow); occlusion is unreliable on 27 ([PA] §8). Therefore: every Awake and Displays function is reachable from Settings (Awake status row with Keep Awake/Extend/Turn Off; Displays root live controls), hotkeys, the CLI, and the floating Displays panel; **opening Snaptic again always shows Settings** (0.2 rule restored; parity minor 13); the 0.2 hidden-icon warnings stay on the Menu Bar page; the Snaptic item and the Awake item have separate autosave names so the system and the user can place them independently; the default `.ownIconWhenActive` costs no notch space at rest (C11); a CLI-started session announces itself with a toast (§3.1); no right-click, hover, programmatic highlight or occlusion dependence (C3).

### 5.6 Floating Displays panel

Restyled with the same `DisplayLiveControls` rows as the Displays root page (shared SwiftUI views from F; brightness, volume, resolution pop-up, input); the "⋯" button opens the display's submenu content as an `NSMenu` popped at the button (no mixed panel/menu blocks); footer buttons: Identify, Restore All Displays, Settings.

## 6. Files, ownership, CI, delivery

### 6.1 Teams

| Team | Owns |
|---|---|
| **Lead** | Contracts, stubs, CI, lint + ratchet, Info.plist, Package.swift, Awake module shell, host wiring (ModuleHost, HostSignals, ConfigStore admission, consent store, ToastPresenter changes), cross-section migrations, ConfigSlice/ControllerRevision types |
| **G — Awake core** | Awake Kit models and logic, sessions/assertions/guards/triggers/history/automation controllers, task sessions, indicator and Awake menu, Awake settings pages, Awake search index |
| **J — Awake sources** | Criterion sources, PowerMonitor, SystemEventsMonitor (session facts), process facts, activity simulation, Drive Alive (+ Drives page) |
| **H — Settings UI** | SettingsUI library, SettingsShell (sole owner) + search, Kit settings index types and control map, General/Permissions/About pages, Onboarding, Window Switcher page |
| **M — Menu system** | MenuKit, MenuSliderRow, MenuSwitchHeader, StatusMenu, Kit MenuLayout (MenuPresence, StatusItemPlan logic), Menu Bar page + Customize sheet, Displays menu builder/blocks, `ConfigMenu` |
| **A, B, C, D, E, F** (existing) | Their Displays controllers (observability, menu contributors on MenuKit) and the new pages/sections for their features (§4.3), per §6.2; A also Switcher runtime changes, KitBackup/KitControl; B also `Fingerprint.matches` |

### 6.2 Files (normative; every path goes into `scripts/stubs.tsv` with owner and kind in step 0; ⇢ = ownership moves; ✗ = deleted **at the step-3 exit** after a caller grep, tracked in the ratchet until then)

```
Lead:
  Package.swift (link CoreAudio, SystemConfiguration, DiskArbitration, Security), Resources/Info.plist (0.3.0,
    NSRemovableVolumesUsageDescription), .github/workflows/build.yml, scripts/{lint.sh, lint-legacy.tsv (new), stubs.tsv, gen-stubs.py}
  SnapticKit/KitModules.swift (ModuleID.awake, EventCategory.awake, AwakeActionID, AwakeCriterionKind;
    DisplayFeature.sleepPrevention removed in step 3 together with D/F/A), SnapticKit/AwakeFeatureGraph.swift (new),
    SnapticKit/FeatureGraph.swift (−sleepPrevention in step 3)
  SnapticKit/Config/{ConfigAwake (shell; G fills functions in step 2), ConfigAwakeConsent (new)}.swift,
    Config/ConfigDisplays.swift (M4, M5, migrations markers, changedSections + per-display subsections, restoringDefaults),
    Config/ConfigModules.swift (⇢ from A; presence, newModuleCards, markers, per-id defaults, M2, M3)
  Snaptic/Core/{ModuleContracts (settings contracts §4.1, SettingsTint, FeatureHighlight, StatusItemProvider,
               FeatureAvailability moved here), ModuleContext (⇢ from A; hostSignals), HostSignals (new),
               ConfigStore (⇢ from A; admit), ConfigSlice (new), ToastPresenter (⇢ from A; presenting/screensaver suppression,
               Recent Notices routing), ModuleHost (⇢ from A; Awake wiring, stores, consent, admission hooks,
               upgrader insertion, M1, isTerminating, Reset All)}.swift
  Snaptic/Awake/{AwakeModule, AwakeContext (+AwakeHost), AwakeContracts (+ChangeFanout), AwakeRuntimeState,
               AwakeConsentStore}.swift (new)
  Snaptic/Displays/{DisplaysModule (fan-out by section), DisplaysRuntimeState (ControllerRevision per id, DisplayRuntime
               fields, DisplaysPageEnvironment forwards no config; −sleepPreventionActive in step 3),
               DisplaysContracts (observedSections default, DisplayLiveControlling, LiveControl, DragPhase)}.swift

G (Kit, each with Tests/SnapticKitTests/<Name>Tests.swift):
  AwakeSession, AwakeClock (+AwakeCountdown, AwakeDurationGrammar), AwakeArbiter, AwakeGuards, AwakeTriggers,
  AwakeTriggerEngine, AwakeHistory, AwakeSnapshot, AwakeMigration, AwakeCommandGrammar, AwakeLogEvent,
  Config/ConfigAwakeSessions, Config/ConfigAwakeIndicator, SettingsIndexAwake
G (app): Snaptic/Awake/Core/{AssertionManager, SessionController, TaskSessionMonitor (untilIdle + whilePID),
               GuardsController, TriggerController, Ticker, HistoryController, AwakeAutomation, AwakeDiagnostics}.swift
         Snaptic/Awake/UI/{IndicatorController, AwakeMenuBuilder, CustomSessionPanel, AwakePage, PresetEditorSheet,
               TriggerEditorSheet, CriterionEditors, AwakeAdvancedSheet, OtherAssertionsSection, AwakeHistoryPage,
               AwakeOnboardingStep}.swift

J (Kit): CPUMath, NetworkMath (CIDR/IPv6 parse + match, MAC normalize), ActivityPolicy (+IdleMath), DriveAlivePolicy,
         Config/ConfigAwakeDevices (+VolumeUUIDKey)
J (app): Snaptic/Awake/Sources/{PowerMonitor, SystemEventsMonitor, AppMonitor, DisplayPresence, USBWatcher, VolumeMonitor,
               AudioMonitor, CPUSampler, IdleSampler, NetworkMonitor, BluetoothPresence, ActivitySimulator,
               DriveAliveService, OtherAssertionsReader (+SleepDisabled), ProcessFacts (proc_pidinfo, LOCAL_PEERPID)}.swift
         Snaptic/Awake/Core/{ActivityController, DriveAliveController}.swift, Snaptic/Awake/UI/DrivesPage.swift

H (Kit): SliderMath, SettingsIndex (SettingsRoute, SettingsSearchEntry, SettingsSearch — Kit so search is tested on Linux),
         ControlMap (§4.8 removedSettings + fixture check), SettingsIndexGeneral, SettingsIndexSwitcher
H (app): Snaptic/SettingsUI/{SettingsIcon, SettingsPageHeader, FeatureHighlights, SettingRow, ToggleSetting, SliderSetting,
               NumberField, StepperSetting, PickerSetting, GlyphTilePicker, ActionMenuButton, InfoButton, NavigationRow,
               ButtonRow, StatusRow, PerDisplayPicker, PageFooterButtons, AdvancedSheet, ReorderableList, AppListEditor,
               ShortcutSetting, EmptyListView, SettingsPageScaffold, SettingsAnchor, SettingsBinding, SettingsShell,
               SettingsSearchView}.swift
         Snaptic/Core/{SettingsWindowHost, GeneralPages, Onboarding}.swift (⇢ from A)
         Snaptic/Switcher/{SwitcherPages, SettingsView}.swift (⇢ from A)

M (Kit): MenuLayout (MenuPresence, StatusItemPlan, ModulesConfig.statusItemPlan), SettingsIndexMenuBar,
         Config/ConfigMenu (⇢ from F; legacy shortcut fields kept and encoded until 0.4)
M (app): Snaptic/Core/{MenuKit, MenuSliderRow, MenuSwitchHeader, MenuBarPage, CustomizeMenuSheet}.swift (new),
         Snaptic/Core/{StatusMenu, MenuPlacement}.swift (⇢ from A), Core/MenuSliderItem.swift ✗,
         Snaptic/Displays/UI/{DisplaysMenuBuilder, DisplayMenuBlock}.swift (⇢ from F), Displays/UI/MenuCustomizationPage.swift ✗

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
   Core/ControlCommandRegistry (protected list); Kit KitBackup (awake section via AwakeConfig.exportable/importable,
   awake.guards in safetyPaths; −sleepPrevention rows in step 3), KitControl (protected words; −sleepPrevention in step 3)
```

Unique basenames are kept (e.g. `PowerMonitor` (J) vs `PowerController` (D); `KeyboardPage` (C) vs no other). Lead adds `.awake` to the extension-placement lint allowlist (`SharedExtensions.swift` stays the only shared home). Ownership collisions of r1 resolved: `SettingsShell` is H's alone; `SettingsTint`, `FeatureHighlight` and `StatusItemProvider` are lead types in `ModuleContracts` (code minor 12, B3).

### 6.3 CI, lint and ratchet (lead, step 0)

- Linux job: new Kit files/tests build and run with Swift 5.10 (Foundation only; no Foundation formatters in Kit code that tests compare, N12).
- macOS job unchanged (Xcode 16.4, Swift 5 language mode, debug + tests + universal + helper self-test); Awake adds no helper, so no new self-test.
- `FeatureAvailability` moves from `DisplaysContracts.swift` to `Core/ModuleContracts.swift` (lead, step 0) so Awake doesn't depend on a Displays file.

**Ratchet** (code B1): `scripts/lint-legacy.tsv`, one row per (rule, path): `rule ⇥ path ⇥ count ⇥ permanent|step`. `lint.sh` fails on any violation of L1–L13 not covered by a row (count exceeded or path missing), **and** on any non-permanent row whose actual count is now lower (the row must be lowered or deleted in the same change). `lint.sh --write-ratchet` generates the initial file at 871c10b in step 0 (≈ 54 `Slider(`/`Stepper(`, ≈ 125 `.font(.caption)`, 18 `NSMenuItem(`, 4 `objectWillChange.send()`, 7 `State(initialValue:`, `PowerController.swift` for L1). Permanent rows: `AppDelegate.swift` (L6, the app's main menu that Settings text fields need for Edit), `PIPWindow.swift` (L6, context menu), `ArrangementCanvas.swift` (L5, custom drag canvas). Deleted files (✗) and symbols (`ClosureMenuItem`, `CMenu`, `ManagedMenuItem`, `MenuSliderItem`, `MenuSlot.quick`) stay until the step-3 exit, where owners remove them after `grep` shows no callers (code M10). **Step-3 exit: only permanent rows remain.**

Lint additions:
- L1 `IOPMAssertionCreate`/`IOPMAssertionCreateWithProperties` only in `Awake/Core/AssertionManager.swift`; `IOPMAssertionRelease` there and in `Awake/Sources/ActivitySimulator.swift` (its DeclareUserActivity id, code M8); `IOPMAssertionSetProperty` banned (the swap replaces it).
- L2 `IOPMAssertionDeclareUserActivity`, `.post(tap:`, `CGEvent(mouseEventSource` only in `ActivitySimulator.swift`; there, mouse event types other than `.mouseMoved` are banned; `keyboardEventSource`, `CGEvent(keyboardEvent`, `CGEvent(scrollWheelEvent` banned everywhere in Awake.
- L3 (r1) dropped: rule 12 already bans spawning outside HelperSpawner everywhere (code minor 13).
- L4 Banned everywhere: `UNUserNotificationCenter`, `import CoreWLAN`, `import IOBluetooth`, `CLLocationManager`, the string literals `"pmset"` and `"sudo"`.
- L5 `Slider(`, `Stepper(`, `.font(.caption)` only under `Sources/Snaptic/SettingsUI/` (ratchet for the rest).
- L6 `NSMenuItem(` only in `MenuKit.swift`, `MenuSliderRow.swift`, `MenuSwitchHeader.swift` (ratchet).
- L7 `objectWillChange.send()` banned in `Displays/UI/`, `Awake/UI/`, `SettingsUI/`; `State(initialValue:` banned in Settings views (ratchet).
- L8 (r1's python anchor scan) replaced by Kit tests: anchors unique across `SettingsIndex*` tables, every `ControlMap` id exists; plus a DEBUG assertion in `SettingsPageScaffold` when `reveal` targets an anchor that never registered (code minor 13).
- L9 `record(.awake, "` banned under `Awake/` (only `AwakeLogEvent` cases may be logged; security M6).
- L10 `queue: nil` banned under `Awake/` (code M6); the `static let shared` (rule 7) and `passUnretained` (rule 10) rules extend to `Awake/`.
- L11 `consent.record(` only under `Awake/UI/` and `SettingsUI/` (N10).
- L12 `.controlSize(.regular)` only in `SettingsUI/SettingsPageHeader.swift` (design B2).
- L13 `NSHostingView` banned in `Core/Menu*.swift`, `Core/StatusMenu.swift`, `Displays/UI/*Menu*.swift`, `Awake/UI/AwakeMenuBuilder.swift`, `Awake/UI/IndicatorController.swift` (design M11).

**Stub kinds** (code M14): `gen-stubs.py` gains K15 Awake service (`AwakeServiceLifecycle` class, no-op activate/deactivate), K16 criterion source (K15 + `static var kinds`, no-op `contribute`, `observe` backed by `ChangeFanout`), K17 Awake controller (`AwakeFeatureController`, `id` from the extra column, no-op members, `availability` returns available), K18 settings page (`struct T: View` rendering `SettingsPageScaffold` with the title), K19 sheet (`struct T: View` with `@Environment(\.dismiss)` and a Done button), K20 Kit settings index table (`package enum T { package static let entries: [SettingsSearchEntry] = [] }`). SettingsUI components, MenuKit, `ConfigStore`, `ConfigSlice`, `AwakeConsentStore` and every Kit type in §2 are `S` (special, hand-written by the lead from this plan's signatures) or `L`. About 120 new rows.

### 6.4 Delivery order

**Step-0 feasibility** (what step 0 can and can't contain; code B1, B2, M14):

| Item | Step 0? | Why |
|---|---|---|
| Stubs for every §6.2 file (K15–K20, S) with safe returns and exhaustive protocol members | yes | only lead types are referenced |
| `AwakeFeatureGraph` + tests, `KitModules` additions | yes | lead-owned Kit |
| `AwakeConfig` shell with all sub-config types as G/J **stubs** (`init()`, `sanitized()` identity) | yes | G/J fill them in step 1 |
| `admitted`, `restoringDefaults`, `exportable`, `importable` | stub only (identity / `AwakeConfig()`) | need G's and J's fields; G implements in step 2 |
| `ConfigStore(admit:)`, `AwakeConsentStore`, ModuleHost admission hooks with the identity function | yes | lead code; real admission arrives with G's `admitted` |
| Migrations M2–M5 + markers + tests; per-id module defaults; upgrader insertion of Awake disabled | yes | lead Kit |
| M1 | no: stub `AwakeMigration.fromDisplays` returns "nothing"; G implements in step 1, lead wires the hook in step 2 | needs G's trigger model |
| `changedSections` with per-display subsections; `observedSections` default; `ControllerRevision` per id; `ConfigSlice`; `DisplayRuntime` fields; `DisplayLiveControlling` | yes | lead types; defaults keep the ~21 conformers compiling |
| `HostSignals`, `StatusItemProvider`, `StatusItemPlan.custom` (empty) | yes | lead |
| `sleepPrevention` removal, MenuKit migration of old factories, file deletions | **no** (step 3) | would break 11 files owned by C/D/F/A (code B2, M10) |
| Lint L1–L13 + ratchet generated from 871c10b | yes | ratchet makes it green on day 0 |

| Step | Who (parallel) | Exit criterion |
|---|---|---|
| 0 | Lead | Everything marked "yes" above; Info.plist; Package.swift links; CI green on Linux and macOS with the ratchet |
| 1 | G (Kit only, incl. `AwakeMigration`) ∥ J (sources, Kit) ∥ H (library, shell, search, Kit index types, ControlMap skeleton) ∥ M (MenuKit, MenuSliderRow, MenuSwitchHeader, StatusMenu with `MenuPresence` and the plan, MenuLayout) ∥ A (Switcher debounce, sticky mode, `switcherVisible`) ∥ B (`Fingerprint.matches`) | Kit tests for G/J/H/M; sources activate/deactivate cleanly; shell shows all 8 roots with stub pages; StatusMenu renders existing sections through MenuKit; green, merged |
| 2 | G (controllers, assertion, sessions incl. task kinds, guards, triggers, automation, indicator + Awake menu, `admitted`/`restoringDefaults`/`exportable`/`importable`; lead wires M1 and real admission in ModuleHost) ∥ H (General, Permissions, About, Onboarding, Switcher page) ∥ M (Displays menu builder/blocks, Menu Bar page, Customize sheet) ∥ B/C/D/E (controller observability + revision bumps + MenuKit contributors; C `DisplayLiveController`) ∥ F (Displays root page, live controls, Details sheet, panel) ∥ A (KitBackup awake section) | Awake works end to end from the menu, hotkeys and CLI; menus per §5; Displays root page live; green, merged |
| 3 | G (Awake page, editors, history, Advanced, other-assertions section) ∥ J (Drives page, nudge path, Bluetooth Beta) ∥ C/D/E/A/B/F (sub-pages and Advanced groups per §4.3; duplicates per §4.4) ∥ **one coordinated merge** D + F + A + lead removing `sleepPrevention` (§2.13) ∥ H (search index assembly, highlight, ControlMap test green) ∥ all owners delete ✗ files and old factories after a caller grep | Every §4.3 page meets its budget; every slider is a `SliderSetting`; search finds every entry; `ControlMapTests` green; **ratchet holds only permanent rows**; green, merged |
| 4 | Review | Adversarial reviews: security (§3, admission while quit, Keychain failure paths), correctness (clock, guards, triggers, assertion swaps, task kinds, migration), UX (copy rules, budgets, light/dark/Increase Contrast, VoiceOver incl. the Awake menu), consistency (contracts vs code); fixes |
| 5 | Lead | README (Awake, CLI verbs and exit codes, `awake hold` recipe for builds and agents, privacy, "why not lid-closed on battery", switching from Amphetamine Power Protect / Insomnia and cleaning up their sudoers rules and `SleepDisabled`), website, THIRD_PARTY_NOTICES (Insomnia, KeepingYouAwake if logic is followed closely; no code from APSL sources such as `caffeinate.c` — behavior only), Appendix hardware session, merge |

### 6.5 Done means

- Every In row of §1.1 and §1.5 implemented, reachable in Settings (and menu, hotkey and CLI where listed), wired to availability, kill switch, Safe Mode, diagnostics and `configDidChange`; idempotent start/stop; no stubs left.
- **Every 0.2 control reaches its §4.8 home** (`ControlMapTests` green; reviewer walk-through of the table).
- Awake holds at most one sleep assertion at any time (assert in debug + test via `AssertionManager` counters); `pmset -g assertions` shows only fixed-vocabulary strings (`Details` = manual/automatic).
- Protected Awake settings written by `defaults write` while Snaptic is quit, stopped or running never take effect without consent (HW-19).
- Every Settings slider is a `SliderSetting` with live value field and reset; every slider in the menu is a `MenuSliderRow` with a live value; no slider in a submenu; no `NSHostingView` in a menu.
- Page budgets of §4.3 met; the duplicates resolved as in §4.4; no developer titles, camelCase ids or raw SF Symbol names visible.
- Migrations M1–M6 tested, each runs once (markers); a 0.2 settings fixture (all features on) loads with no setting lost and a 0.3 → 0.2 downgrade still reads every legacy field.
- Lint passes with only permanent ratchet rows; CI green on all jobs; hardware list §6.7 run and Beta labels updated.

### 6.6 Kit unit tests (new)

- `AwakeFeatureGraph`: spec totality, resolve (kill switches incl. `unkillable` ignored, Safe Mode, requirements, managed screen lock), `enabling` refuses unavailable, `requiredServices` per criterion kind and per dynamic need, activation order respects dependencies.
- `AwakeSession`/`AwakeClock`: start for every kind; remaining with continuous vs wall; `endWall` after a clock jump; `continuousEnd` for until-kinds; reboot expiry; clock jumps ±1 day don't move duration sessions; extend caps at 30 days; `canExtend` per kind; task caps; type-tagged Codable round trips and unknown types dropped; `overrideGuards` never encoded.
- `AwakeCountdown`: every boundary (3600, 3599, 61, 60, 59, 1, 0), "2h" on the hour, rounding up, `nextChange` never 0, spoken strings, `clock` 12/24 h.
- `AwakeDurationGrammar` / `AwakeCommandGrammar`: valid and invalid inputs, 7-digit / 2-decimal limits, "1e300h", huge digit strings, overflow, `idle`, locale-independent parsing, seeded fuzz never traps.
- `AwakeArbiter`: governing precedence; every display policy × locked × console × idle; deadline grace; `needsSwap` thresholds; disk-idle flag; plan stable when nothing changes (no relative times).
- `AwakeGuards`: desktop/no battery, AC, floor crossing, hysteresis +5, two unreadable reads, adapter disconnect, LPM, serious warn-once (no end), critical end + cooldown, override only for battery/LPM, `allowsBackgroundWork`, `monotonic(over:)`, assertion-hold backoff.
- `AwakeTriggers` decode: lossy per entry, unknown kinds dropped, limits (32/8), sanitize (names, CIDRs, bundle ids, minutes, nudge on idle triggers → declare).
- `TriggerEngine`: every criterion kind true/false/unknown; negation; all/any with unknowns; start/end delays on the continuous clock; priority order and reorder; pause; guard hold; manual end with and without `resumeAfterManualEndMinutes`; suppressions expire; overnight schedules and week wrap; `scheduleBoundaries`; `summary` wording; seeded fuzz deterministic.
- `AwakeHistory`: cap, merge of short `.replaced` runs, prune, totals across given day starts.
- `AwakeSnapshot.admitted`: source forced, override cleared, nudge → declare without consent, out-of-range kinds dropped.
- `AwakeConfig`: `admitted` (each protected field with and without consent; floor lowering/off), `restoringDefaults` (protected off), `exportable` (nudge → declare, drops, triggers opt-in, hashes stripped), `importable` (guards monotonic, protected kept from current).
- `AwakeMigration`: no Displays settings; feature off with flags; feature on but Displays module off (not effective → disabled trigger); 1, 3 and 9 displays (split at 8); missing fingerprints; corrupt JSON; marker prevents a second run.
- `NetworkMath`: IPv4/IPv6 CIDR parse/match, invalid input, MAC normalization and hashing input. `CPUMath`: tick deltas incl. wraparound; 64-bit byte deltas.
- `ActivityPolicy` truth table (managed lock, edge margin, stopAfter, screensaver, console); `IdleMath` (nudge echoes ignored, real input kept); `DriveAlivePolicy` eligibility table (allowlist, boot container, DMG, non-local) and `shouldWrite` (CLI sessions, guards, first write).
- `VolumeUUIDKey` validation; `WeekdaySet` masking.
- `SliderMath`: clamp/snap, isDefault tolerance, hand formats and spoken units, parse with units and both decimal separators.
- `SettingsIndex`: ranking, synonyms, diacritic table, empty query, anchors unique across all `SettingsIndex*` tables, no entry text from config. `ControlMap`: every key path of the 0.2 fixture mapped or listed as removed with a reason.
- `MenuLayout`: presence × awake active × shortcut bound → plan (custom items, compact section, active glyph, footer in own menus, Snaptic item existence); `legacyPlacement`; slider never "inSubmenu"; ordering; compact mode.
- `DisplaysConfig`: `changedSections` per field incl. per-display subsections, M4/M5 run once, legacy fields still encoded, `restoringDefaults(scope:)` leaves other scopes; `ModulesConfig` M2/M3, per-id defaults, `newModuleCards` with an unknown id.

### 6.7 Hardware checks (first session; Beta labels depend on them)

| # | Check |
|---|---|
| HW-1 | Both assertion types on 14/15/26/27, Intel + Apple silicon; `pmset -g assertions` rendering of name/details |
| HW-2 | (informational since r2: no SetProperty) timeout behavior of `TimeoutSeconds` across system sleep |
| HW-3 | Assertion swap (create-then-release) leaves no gap (display doesn't dim at the swap), incl. deadline re-arm |
| HW-4 | Screen saver and "require password after screen saver" with each assertion type and with `declare` |
| HW-5 | `IOPMAssertionDeclareUserActivity` vs `CGEventSourceSecondsSinceLastEventType` (does Slack/Teams go Away?) |
| HW-6 | ±1-pt nudge from a `.privateState` source: does `.hidSystemState` idle reset? not visible; edge skip; Accessibility-denied path; tagged events ignored by switcher hover |
| HW-7 | `keepOnWhileActive` downgrade/upgrade timing with real idle; lock-screen downgrade (C1) actually lets the display sleep |
| HW-8 | Lid close on battery / AC / desktop mode; `AppleClamshellCausesSleep` values; wake path ends/continues sessions correctly |
| HW-9 | CoreAudio `DeviceIsRunningSomewhere` on input causes no microphone prompt or orange indicator; HAL queue never blocks main |
| HW-10 | IOHIDDevice registry reads for Bluetooth input devices need no Input Monitoring |
| HW-11 | Router MAC via routing-table `sysctl` on 15/26/27 triggers no Local Network prompt; `NET_RT_IFLIST2` counters at 10 GbE |
| HW-12 | Removable Volumes prompt text and denial path; Drive Alive keeps a USB HDD spinning; eject not blocked; DMG and boot-container volumes refused |
| HW-13 | IOPS notifications on desktop Macs (no battery) and on battery percent changes; LPM notification queue |
| HW-14 | Status item `autosaveName`, `isVisible` KVO after ⌘-drag on 14–27; create/remove with Own Icon When Active; countdown width stability; 26 "Allow in the Menu Bar" off; 27 overflow |
| HW-15 | AppKit menu rows (MenuSliderRow, MenuSwitchHeader): alignment with native items, slider keyboard behavior, vibrancy on 26/27 material, `sectionHeader` look on 14/15/26/27; Option alternates on 27; arrow-key and VoiceOver navigation reach "Turn Off Keep Awake" |
| HW-16 | Settings: `.searchable(placement: .sidebar)` + `ScrollViewReader` scroll in grouped `Form` on 14; `NavigationStack(path:).id(root)` back button; next-turn push; `.toolbar(removing: .sidebarToggle)`; fixed 715 pt width |
| HW-17 | `NumberField` commit on blur inside `Form`; Esc revert; VoiceOver values with units; small row switch size matches System Settings on 14–27 |
| HW-18 | Thermal states (via a load generator) produce the toasts/ends; `CLOCK_MONOTONIC_RAW` advances across sleep |
| HW-19 | `defaults write` of nudge / Drive Alive / floor-off while Snaptic is quit, while Awake is stopped, and while running: none takes effect; toast once |
| HW-20 | `NSMenuItem.subtitle` with the 15.5 SDK on 14.4, 15, 26, 27; fallback rows on 14.0–14.3 |
| HW-21 | `DispatchSource.makeProcessSource(.exit)` + `proc_pidinfo` start time for `awake hold`; `LOCAL_PEERPID` on the CLI socket; PID reuse refused |
| HW-22 | Keychain consent with `kSecUseAuthenticationUIFail`: Developer ID update keeps consent; ad-hoc rebuild gets empty consent and no prompt |
| HW-23 | `untilIdle` defaults (15% CPU, 50 KB/s, 3 min) end correctly after a large download and a build, not during Spotlight indexing bursts |

### 6.8 Open questions

- **OQ-1** Settled in r2: Drive Alive ignores CLI-started sessions (strict).
- **OQ-2** Default for `keepOnWhileActive` minutes (30) and whether it should be the default display policy instead of `keepOn` (battery-friendlier). Default: `keepOn` for timed/indefinite sessions; task-bound kinds default to `maySleep`.
- **OQ-3** History on by default (S) vs opt-in. Default: on, local only, 90 days.
- **OQ-4** Whether the Displays root page keeps a Refresh rate pop-up when Resolution's pop-up already lists rates per mode. Default: keep (Apple precedent).
- **OQ-5** Glyph families: confirm `cup.and.saucer`, `eye`, `lightbulb` and their `.fill` variants on macOS 14 (tested in Kit by name list; runtime fallback `cup`).
- **OQ-6** Sticky-switcher menu item (C8) interaction with `releaseToSwitch` users; fallback is to omit the item.
- **OQ-7** Default for "After the screen has been locked for…" (security L5). Default: Never; product may choose 12 h.
- **OQ-8** `untilIdle` thresholds after HW-23. Default: 15% / 50 KB/s / 3 min.
