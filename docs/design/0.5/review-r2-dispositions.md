# 0.5 Dock Previews: round-2 disposition audit

- **Plan audited:** `docs/design/0.5/PLAN.md` r2 (1,349 lines), §R1 tables at l.1220–1349.
- **Reviews:** `review-r1-pressure.md` (P), `review-r1-grill.md` (G), `review-r1-adversarial.md` (X),
  `review-r1-parity.md` (Y).
- **Date:** 2026-11-12.
- **Method:** for each of the 103 ids:
  - confirm the §R1 row;
  - open the body section it names;
  - compare the result with the reviewer's scenario and proposal, including appendix items (named tests, H1 sites,
    S0 and M rows).
- **Tree checks (read-only):** `KitControl.swift:76-92`, `Switcher/Settings.swift:255-256`, `KitBackup.swift:33-42`,
  `Icons/IconsModule.swift:164-171`, `Core/EventLog.swift:6-24`, `Awake/Sources/ActivitySimulator.swift:129-130`,
  `scripts/lint03.py:512-524`.
- **Ground rules:** Q1–Q7 were treated as settled. No source of any other app was opened.

## Counts

| | yes | partial | no |
|---|---|---|---|
| **Landed** | 95 | 8 | 0 |
| **Resolves** | 45 | 58 | 0 |

- **Coverage:** all 103 §R1 rows exist, and none is P or R. 45 rows are yes/yes. The other 58 resolve only partly,
  and 8 of those also landed only partly.
- **What most partials are:** a named test, S0 clause, M clause or string from the reviewer's proposal that didn't
  carry over. The rows themselves are sound.

| Severity | Count | Findings |
|---|---|---|
| Blocker | 1 | D2-1 |
| Major | 7 | D2-2 … D2-8 |
| Minor | 25 | D2-9 … D2-33 |

## Disposition table

| id | §R1 says | landed? | resolves? | note |
|---|---|---|---|---|
| P-1 | M: §2.6, §1, A1a/A1b; untitled other-Space cards, Bring Forward only | yes | partial | The card menu, middle-click and ⌘W on an untitled other-Space card are unstated (D2-25) |
| P-2 | A: §4.12 six checks; GR3; Q6 restated | yes | yes | §4.12 l.738–756 |
| P-3 | A: GR4 names the raise exception; H8 L2 | partial | partial | Exception named (l.86–88). The S0-8 raise/HIDIdleTime extension and the `ActivitySimulator` carve-out were dropped (D2-6) |
| P-4 | A: §4.10 (with Y-1, X-7); K4 | partial | partial | The rule moved to Kit (l.705). The keys moved to a new slice with no migration (D2-1) |
| P-5 | A: H3 split; B1a | yes | partial | Split at l.358–366. §2.2 l.223 says every Carbon lookup is under §4.12, but `IsSecureEventInputEnabled` isn't (D2-12) |
| P-6 | A: §2.3; A1a/A1b; `ThumbnailStoreClientTests` | yes | partial | Proposed test cases and the call-site count dropped (D2-14) |
| P-7 | M: H6, read at each use | yes | partial | `Dock.disable.clickActions` has no read point while running (D2-15) |
| P-8 | A: §4.12 selftest lines; B1b | yes | partial | One line per `WindowFeature`, not per symbol (D2-12) |
| P-9 | A: H8 rows name items; §6 | yes | yes | l.393–406 |
| P-10 | M: H1, H10; G-3 wording | yes | yes | l.343–355, l.431–441 |
| P-11 | A: §4.13 (with X-2); M35 | partial | partial | SCK-only Safe Mode landed (l.787–788). "Doesn't start" contradicts §4.17 and §4.21 (D2-2). The M33 extension was partly dropped (D2-9) |
| P-12 | A: §5 gates table; §6 order | yes | partial | Gates and done-whens point at the wrong items (D2-8) |
| P-13 | A: §2.1; GR2; §2.4; done-whens use Appendix B | yes | yes | Adopting Appendix B wholesale brings its own conflicts (D2-7) |
| P-14 | A: §2.4; GR1; §4.1 | yes | partial | M49 is an absolute ≤1/s, not a delta against the module off (D2-26) |
| P-15 | A: §4.22; A6a/A6b; M50 | yes | partial | M50 lacks the EventLog `dock.started`/`dock.stopped` counts (D2-26) |
| P-16 | M: §4.5, ⌘ keys while engaged | yes | yes | l.567–570 |
| P-17 | M: §4.21, K5, A9; `AwakeDurationGrammar` | yes | partial | Which verb refuses, the Run Both hint and the `dockCases` list are missing (D2-27) |
| P-18 | A: H7 downgrade worktree; K1 | yes | yes | l.390–392 (the privacy-key gap is D2-1) |
| P-19 | A: §2.6; §4.12 table | yes | yes | l.766 |
| P-20 | M: §4.9; two ages | yes | yes | Reason stated |
| P-21 | M: §4.3, drop a size then scroll | yes | yes | l.508–511 |
| P-22 | A: D2 done-when | yes | partial | "No `docs/design/0.5.0/` copy" dropped (D2-28) |
| P-23 | A: §4.24; A7 | yes | yes | l.1087 |
| P-24 | M: §2.3, §4.8; per-element 0.15 s | yes | yes | |
| P-25 | A: §4.12 raise fallback; S0-27; M16 | yes | yes | |
| P-26 | A: §4.11 TCC service; §4.14 | yes | yes | |
| P-27 | A: H6 typed enums; §4.12 | yes | yes | |
| G-1 | M: §4.5, §4.4; keys only while engaged | yes | yes | Reason stated |
| G-2 | A: §4.17 states table | yes | partial | Row 3 (`paused`, `safeMode`) contradicts §4.13's "doesn't start" (D2-2) |
| G-3 | A: H1 three sites; §4.19 | yes | partial | "Turning it on later never changes its presence" and the Menu Bar help text dropped (D2-29) |
| G-4 | M: §4.10, §4.18; M45; one shared privacy store | partial | partial | The shared store has no migration, backup or downgrade path (D2-1) |
| G-5 | A: §4.18 header … control count | yes | partial | Slider step (0.1 s) and footer layout dropped (D2-29) |
| G-6 | M: §4.18; grace and net are constants | yes | partial | The footnote no longer shows only while Run Both Anyway is chosen (D2-29) |
| G-7 | A: §4.14; onboarding loops over `requiredPermissions` (§4.20) | yes | partial | The `H1-SITES.md` line and the onboarding check dropped. §4.20 doesn't carry it (D2-30, D2-33) |
| G-8 | A: §4.20; A8 | yes | partial | M29 "five rows fit" and the 0.3.2 Upgrading line dropped (D2-30) |
| G-9 | M: §4.11; `DockClickRules` | yes | partial | "README says so next to this setting" dropped (D2-30) |
| G-10 | A: §4.15 | yes | partial | The "Switching from DockDoor" behaviour table isn't specified (D2-30) |
| G-11 | M: §4.16, §4.1, §4.7; fade only | yes | partial | Border "around the panel" dropped (D2-31) |
| G-12 | A: §4.3; K2 | yes | partial | Scroll direction and M19's second clause dropped (D2-31) |
| G-13 | A: H9; D1 README outline | partial | partial | H9 table landed. No README outline anywhere, D1 included (D2-30) |
| G-14 | M: §4.21; exit 5; `AwakeDurationGrammar` | yes | partial | The Safe Mode refusal can't be reached (D2-2). Refusal scope unstated (D2-27) |
| G-15 | A: §2.1; K1 `properNames` | yes | partial | The `inSentence("Dock click actions")` test isn't named (D2-29) |
| G-16 | A: §4.4 card menu | yes | yes | l.541–547 |
| G-17 | A: §4.3 badges | yes | yes | l.514 |
| G-18 | A: §4.3 small cards | yes | yes | |
| G-19 | M: §1.1; S0-32 | yes | partial | Differences aren't routed to "Switching from DockDoor" (D2-30) |
| G-20 | A: H6 rows; §4.17 effects | yes | partial | Which switcher page shows the `Windows.*` lock rows is unstated (D2-30) |
| G-21 | M: §7 M35–M50 merged | yes | partial | B/V markers and clauses lost in the merge (D2-32) |
| G-22 | A: H4; H7 | yes | yes | |
| G-23 | A: What 0.5 adds; §4.4 | yes | yes | |
| G-24 | A: §4.3 header count; `SentenceText.unit` | yes | yes | |
| X-1 | A: §4.12; GR3; Q6; B1b | yes | partial | The injected-result test and the connection-id equality check dropped (D2-13) |
| X-2 | A: §4.12, §4.13, §8, A2b, M35 | yes | partial | Safe Mode contradiction (D2-2). Crash row, M33 and M35 narrower than proposed (D2-9). §4.13 drops more symbols than asked (D2-10) |
| X-3 | M: §4.5 "engagement rule as proposed" | yes | partial | 10 s plus "clicked" replaces 1.5 s, with no reason given. Tests dropped (D2-3) |
| X-4 | A: §4.9 capture gate; S0-4 | yes | yes | |
| X-5 | M: §4.9 luma test only | yes | yes | Reason stated |
| X-6 | M: §2.3 per-owner generation, bucket keys | yes | partial | The "switcher open doesn't evict last-seen" test isn't named (D2-14) |
| X-7 | M: §4.10 one rule, one shared store | partial | partial | "A migration test and `KitBackup.sections` keep the 0.4 keys" was dropped (D2-1) |
| X-8 | A: §4.8; §2.6; S0-10 | yes | partial | "The window cap of X-29" dropped (D2-17) |
| X-9 | A: §2.3 `.freshness(pid)`; S0-10 | yes | partial | Per-window cap dropped. §R1 cites S0-10, not S0-26. S0-26 gates A2a, not A1b (D2-18, D2-8) |
| X-10 | A: GR1; §2.4; §4.1 Dock zone | yes | partial | Its two Kit tests aren't named (D2-19) |
| X-11 | A: §4.2 swap intent | yes | partial | The reflow and click-within race rows aren't named (D2-19) |
| X-12 | A: §2.4; §4.2 latch; M36 | yes | yes | |
| X-13 | A: §4.11 resolver; M37 | yes | partial | The "ambiguous → nothing happens" case dropped (D2-20) |
| X-14 | M: §4.5, §2.4; tap made at first show | yes | partial | No thread stated for the window read while the tap is enabled (D2-16) |
| X-15 | A: §4.8 `ObserverThread` | yes | partial | S0-14 measurements under Mission Control and the like dropped (D2-16) |
| X-16 | A: §2.4; §4.6; S0-13 | yes | partial | S0-13 "gone or correct within 1 s" dropped (D2-21) |
| X-17 | A: §4.8 liveness, ladder; S0-3; §8 | partial | partial | Silent-death check, fresh observer per attempt and display-change rebuild missing (D2-4) |
| X-18 | A: §2.3; §2.5 | yes | partial | M32's expected count contradicts §2.3 (D2-5) |
| X-19 | A: §4.9 one private capture at a time | yes | yes | |
| X-20 | A: §4.9; S0-19; D1 | yes | yes | |
| X-21 | A: §4.9 30 s / 30 min | yes | partial | The switcher's cache change isn't staged or listed in release notes (D2-22) |
| X-22 | A: GR4; H8 L2 | yes | yes | l.86–88 |
| X-23 | A: H3; H8 rule 11 | yes | yes | l.365–366 |
| X-24 | A: §4.12 table; "per-symbol selftest lines" | yes | partial | The body prints one line per `WindowFeature` (D2-12) |
| X-25 | A: §2.4 `menuOpened`/`menuClosed`; §4.2 | yes | yes | Body calls them `ownMenuOpened`/`ownMenuClosed` (D2-33) |
| X-26 | A: §4.1 rule 5 | yes | yes | |
| X-27 | A: §2.1 "takes AppKit global coordinates"; K2 | yes | yes | Body converts AX → Cocoa inside `DockGeometry` (l.193). §R1 text is stale (D2-33) |
| X-28 | M: §4.8, §4.3; "2 instances" | yes | partial | App Translocation dropped from S0-2 (D2-21) |
| X-29 | M: §4.3, §4.4; scroll, not title rows | yes | partial | "Read only what fits plus one" dropped. The 0.5 s budget can truncate the list that scrolling promises to show in full (D2-17) |
| X-30 | A: §4.7; S0-6 | yes | yes | |
| X-31 | A: §4.12 raise fallback; S0-27; M16 | yes | yes | |
| X-32 | M: §4.5, §4.16; read at show/engage | yes | yes | Reason stated |
| X-33 | M: §4.15, §4.21 | yes | yes | |
| Y-1 | A: §4.10; K4; M48 | yes | partial | Rule landed. The store move has no migration (D2-1) |
| Y-2 | M: §4.5 | yes | yes | |
| Y-3 | M: §4.8; "Apps to leave out" is §9 | yes | partial | Body adds "Don't show previews for" (l.658, l.902), which contradicts §9 l.1201 (D2-24) |
| Y-4 | M: S0-29..S0-31 added as proposed | partial | partial | S0-10's odd-app set is three of the proposed set (D2-21) |
| Y-5 | A: §4.7 settled frame; S0-7 | yes | yes | |
| Y-6 | A: §1; §1.1; GR9 | yes | partial | S0-3 lacks "`AXList` rebuilt under the same pid after a display change" (D2-4) |
| Y-7 | A: §4.9 pacing; S0-19 | yes | partial | "Prefer the quieter path" dropped (D2-23) |
| Y-8 | A: §4.8 Stage Manager; S0-11; M20 | yes | yes | |
| Y-9 | A: §9 | yes | yes | |
| Y-10 | A: §4.4; M17 | yes | yes | |
| Y-11 | A: §1.1; K3 case | yes | partial | The K3 case isn't named (D2-19) |
| Y-12 | M: §4.3, §1.1; K2 tests as proposed | yes | partial | K2 tests aren't named, and Appendix B's K2 list contradicts them (D2-7) |
| Y-13 | A: §4.18; §4.23 | yes | yes | |
| Y-14 | M: §4.1 rule 6, §4.2, GR1 | yes | partial | The K3 timing rows aren't named (D2-19) |
| Y-15 | A: §4.11 resolver | yes | partial | Restore-all lacks "at mouse-down". K3 cases aren't named (D2-20, D2-19) |
| Y-16 | M: §4.3; S0-10, S0-2 | yes | yes | |
| Y-17 | M: §4.3 display badge; Space number §9 | yes | yes | |
| Y-18 | A: §4.4; §2.4; K3 | yes | yes | |
| Y-19 | A: §4.23; What 0.5 adds; §9 | yes | yes | |

## Findings

### D2-1 · Blocker · X-7, G-4, P-4, Y-1 · Moving the privacy keys to a new slice loses a user's protected apps on upgrade, backup import and downgrade

**Finding.**

- **Where the keys live today.**
  - "Protect private windows" (`protectPrivateWindows`) and the protected apps (`privateBundleIDs`) are in the
    switcher's config (`Switcher/Settings.swift:255-256`).
  - `KitBackup` backs them up under its `switcher` section (`KitBackup.swift:33,42`).
  - 0.4.0 reads them from there.
- **What r2 does.** It moves both keys into "a `WindowServices` config slice" (l.707). It gives no migration, no
  backup section and no downgrade case.
  - H10 adds only a `dock` backup section (l.434).
  - H7's downgrade test decodes only the modules file and a `dock` backup (l.390–392).
- **Consequences if built literally:**
  - An upgrader's customised protected-apps list falls back to `Config.defaultPrivateApps`.
  - The apps the user added are then captured, cached and titled in both modules.
  - A 0.4 backup restores the keys into a store nobody reads.
  - A downgrade to 0.4.0 loses whatever the user changed in 0.5.
- **What the reviews asked.**
  - Adversarial asked for this exact protection ("A migration test and `KitBackup.sections` keep the 0.4 keys").
  - Pressure asked to keep the switcher store unless A1a proves it isn't loaded.
  - §R1 X-7 and G-4 say neither ask was dropped.

**Evidence.**
- PLAN:l.707–708, l.434, l.390–392; §R1 l.1265 (G-4), l.1297 (X-7), l.1226 (P-4).
- review-r1-adversarial.md:l.325.
- review-r1-pressure.md:l.259–260 ("reads the switcher's privacy settings from the switcher config store … confirm
  in A1a; if not, the two keys move to a shared store").

**Proposal.** Replace PLAN l.707–708 with:

> - **One store, two views (G-4).** "Protect private windows" and the protected apps stay where 0.4 keeps them, in
>   the switcher's config (`protectPrivateWindows`, `privateBundleIDs`). `WindowServices` reads them from there
>   whether or not the switcher runs. A1a confirms that the host loads that store with the switcher off (P-4).
>   - Both Advanced sheets show the same two controls, and a change on one shows on the other.
>   - They stay in `KitBackup`'s `switcher` section, so a 0.4 backup restores them and 0.4.0 reads them after a
>     downgrade.
>   - If A1a finds the store isn't loaded with the switcher off, the keys move to a `windows` section instead. In
>     that case:
>     - a `runMigrations` step copies them once from the switcher store and leaves the 0.4 copy in place;
>     - `KitBackup` gains a `windows` section whose import also accepts the 0.4 `switcher` keys;
>     - H7's downgrade test decodes a 0.5 profile with a customised list in 0.4.0 and finds the list.

Also make these changes:

- **A1a done-when:** add "`ConfigWindowsTests.testPrivacyKeysSurviveUpgradeBackupAndDowngrade` passes".
- **M34:** "Backup export and import include Dock Previews settings and the protected apps list".

### D2-2 · Major · G-2, X-2, P-11, G-14 · Safe Mode: "doesn't start" contradicts the paused state, the CLI refusal and verb registration

**Finding.** Five parts of the plan disagree about Safe Mode.

- **Doesn't start:** §4.13 says "Dock Previews doesn't start in Safe Mode" (l.790).
- **Paused:**
  - §4.17 row 3 reports `paused`, reason `safeMode` (l.839);
  - §4.15 lists `safeMode` as a pause reason (l.812);
  - §4.21 refuses with "Dock Previews is paused in Safe Mode." at exit 5 (l.951).
- **Verbs:** §4.21 registers verbs "only while the module runs" (l.938), so in Safe Mode every `dock` verb gets
  `Unknown command` (exit 2). The `safeMode` status and the exit-5 refusal can never be reached.
- **Appendix B:** pressure K3 orders pause precedence "kill switch > Safe Mode > …", and pressure K5 tests that
  verbs are registered only while the module runs. Both are adopted by the K done-whens.

The house pattern settles it. Hidden Icons starts in Safe Mode, sets `.degraded("Paused in Safe Mode")` and creates
nothing (`IconsModule.swift:164-171`). G-2's row 3 copies that pattern ("Running, `.degraded`; creates nothing").

**Evidence.**
- PLAN:l.790, l.812, l.839, l.938, l.951, l.1137 (M33).
- review-r1-grill.md:l.160.
- review-r1-pressure.md:l.571 ("doesn't start"), l.1042, l.1072.
- review-r1-adversarial.md:l.136.

**Proposal.** Replace PLAN l.790 with:

> - Dock Previews starts in Safe Mode the way Hidden Icons does (`IconsModule.swift:167`): `start()` sets
>   `.degraded("Paused in Safe Mode")` and creates nothing: no lease, observer, tap, panel or capture.
>   - Its verbs are registered, so `dock status` answers `paused`, reason `safeMode`, and `pause` and `resume`
>     refuse with exit 5 (§4.21).
>   - Its page row and menu row read "Paused in Safe Mode" (§4.17).

Also make these changes:

- **l.938:** "**Verbs**, registered while the module is started, including paused in Safe Mode:".
- **K5 done-when:** add "with 'registered while started, including Safe Mode' in place of Appendix B's 'only while
  the module runs'".
- **M33 (l.1137):** "Safe Mode: the page row reads 'Paused in Safe Mode'; `dock status` says paused (`safeMode`) and
  `dock resume` exits 5; the switcher shows minimized windows with the last-seen thumbnail or the icon; diagnostics
  show `hwCapture: safeMode`, 0 private captures and 0 Dock counters".

### D2-3 · Major · X-3 · The engagement rule is marked "as proposed", but 10 s plus "clicked" replaces 1.5 s, and the tests are gone

**Finding.**

- **What the review proposed** (r1 Blocker):
  - the panel is engaged when the pointer "has *moved* inside it within the last 1.5 s";
  - an unhandled key passes through and disengages it for 3 s;
  - three Kit tests and a parked-pointer M23.
- **What r2 says** (l.563–566):
  - engaged once the pointer "has moved since it entered, or the user clicked in it";
  - it disengages only after 10 s without movement.
- **The risk.** For up to 10 s after the pointer settles on the panel, ⌘W, ⌘M, ⌘H and ⌘Q act on the window under the
  pointer rather than the frontmost app. That is the exact parked-pointer scenario, now behind ⌘.
- **Missing pieces.**
  - §R1 l.1293 calls this "the engagement rule as proposed" and gives no reason for 10 s.
  - The K3 done-when (l.1079) names "engagement" but none of the three cases.
  - M23 and M40 (l.1127, l.1144) no longer include "park 3 s, then a ⌘ key".
- **What's fine.** Disengaging on an unhandled key until the pointer moves is at least as strong as the review's
  3 s rule.

**Evidence.**
- PLAN:l.563–566, l.1079, l.1127, l.1144; §R1 l.1293.
- review-r1-adversarial.md:l.167–170, l.175–181.

**Proposal.** Replace PLAN l.563–566 with:

> - **Engaged.** The panel is engaged while the pointer has moved inside it within the last 1.5 s, or the user
>   clicked in it within the last 1.5 s.
>   - It disengages when the pointer leaves, the panel hides, 1.5 s pass without movement or a click, or any key
>     arrives that isn't in the table. It engages again when the pointer moves.

Also make these changes:

- **K3 done-when:** add "`DockPreviewPolicyTests`: a parked pointer for 1.5 s, then ⌘Q, passes through; a moved
  pointer, then ⌘Q, quits the previewed app; 'a', then ⌘Q, passes through".
- **M40:** "Park the pointer on the panel for 3 s, then type a sentence and press ⌘W: every key, ⌘W included, reaches
  the frontmost app".
- **If 10 s is deliberate:** §R1 X-3 must say so and give the reason.

### D2-4 · Major · X-17, Y-6 · The silent-death check can't see a dead observer on a valid element, and nothing rebuilds after a display change

**Finding.** X-17's headline case is an observer that stops delivering while the Dock's pid and `AXList` are still
valid (DockDoor's top complaint). r2 misses it in three ways.

- **Wrong detector.** The health check only treats an *invalid* `AXList` as silent death (l.634–635). That can't
  detect a dead observer on a valid element.
- **Detector dropped.** The review's detector was dropped: read `NSEvent.mouseLocation`, and compare AX's selected
  child with the last one notified.
- **Fresh observer dropped.** "Each attempt makes a fresh `AXObserver`; the old one is invalidated" is gone, though
  the review cites the observer leak on 27.
- **No display-change rebuild.**
  - Rebuilds happen only on wake, unlock and session-active (l.633).
  - Parity Y-6 asks S0-3 to cover an `AXList` rebuilt under the same pid after a display change.
  - S0-3 (l.991) still lists only `killall`, sleep, lock and fast user switching.

**Evidence.**
- PLAN:l.630–636, l.991; §R1 l.1307 (X-17), l.1336 (Y-6).
- review-r1-adversarial.md:l.667, l.671–673.
- review-r1-parity.md:l.504.

**Proposal.** Replace PLAN l.633–635 with:

> - Wake, unlock, session-active and a display change (`NSApplication.didChangeScreenParametersNotification`)
>   always rebuild the observer, even when the pid is unchanged.
> - Each attempt creates a fresh `AXObserver`. The old one is invalidated and its run-loop source removed.
> - **The health check** reads the `AXList` and `NSEvent.mouseLocation` once.
>   - An invalid element is a silent death.
>   - So is a pointer inside the last Dock frame while AX reports a selected child different from the last one
>     notified.
>   - Either case re-attaches and counts `observer.silentReattach`.

**S0-3:** append "a display change (arrangement and resolution) | … and after the display change previews work
within 2 s without a pid change".

### D2-5 · Major · X-18 · M32 expects "running apps + 1", which r2's lease design can't produce

**Finding.**

- **Where the number came from.** The review's "running regular apps + 1" assumed that Dock Previews runs
  `FocusTracker`.
- **What r2 does instead.**
  - Dock Previews takes no `.recency` lease (l.259–260).
  - `.recency` is what runs `FocusTracker` on every regular app (l.247).
  - While a preview is up, the Dock adds only `.freshness(pid)` for one app (l.260–261).
- **The resulting count.** With Dock Previews alone, the AX observer count is about 2 (the Dock plus the hovered
  app), not "running apps + 1".
- **Why it matters.** M32 (l.1136) is a release Blocker.
  - A correct build fails it.
  - The obvious "fix" is to give the Dock a `.recency` lease, which brings back the per-app cost the lease design
    removed (ground rule 1).
- **Also unstated:** whether `.freshness(pid)` adds its notifications to an existing `FocusTracker` observer or
  creates its own. That decides the count with both modules on.

**Evidence.**
- PLAN:l.247, l.259–262, l.325, l.1136; §R1 l.1308.
- review-r1-adversarial.md:l.711.

**Proposal.** Add to PLAN §2.3 after l.248:

> `.freshness(pid)` adds its notifications to `FocusTracker`'s observer for that pid when a `.recency` lease is
> live, and otherwise creates one observer for that pid.

Replace M32 with:

> | M32 | AX observers (`FocusTracker.liveObservers` plus the Dock observer). Dock Previews alone: 1 at rest, 2 while a preview is up, 1 again within 3 s of the hide. With the switcher on too: the switcher's count + 1, unchanged by a preview. Module off: the switcher's count | B | V |

### D2-6 · Major · P-3 · The raise-records idle measurement was dropped, and ground rule 4 is false for Awake

**Finding.**

- **What P-3 was about** (r1 Blocker). Nobody has measured whether `SLPSPostEventRecordTo`'s window-server records
  reset HID idle time. Periodic input that keeps displays awake was the DockDoor bug behind the rule.
- **The measurement asked for.** Extend S0-8 with 50 raises and an `ioreg … HIDIdleTime` check, with "§4.12 changes
  before B1" if idle time resets.
- **What r2 has.** S0-8 (l.996) is still "10 min idle with the harness attached", and it gates A3, not B1b (l.1032).
- **The carve-out.** P-3 also asked ground rule 4 to name Awake's `ActivitySimulator`, which posts HID events by
  design (`ActivitySimulator.swift:129-130`, and `lint03.py:521-524` allows it). Ground rule 4 still says "Snaptic
  never posts a mouse or key event to any app" (l.84).
- **Lint.** H8's L2 row says "bans … everywhere" (l.397) and doesn't mention today's `.post(tap:` allowance.
- **§R1.** P-3 is marked A, and neither drop is mentioned.

**Evidence.**
- PLAN:l.84–88, l.397, l.996, l.1032; §R1 l.1226.
- review-r1-pressure.md:l.173, l.199–200, l.203–207.

**Proposal.**

- **Ground rule 4, l.84:** "Snaptic never posts a mouse or key event to any app or to the Dock, except Awake's
  `ActivitySimulator`, which posts by design only while the user's Awake rules ask for it (L2 already confines it):
  no canary, no event that keeps the Dock revealed, no synthetic ⌘N."
- **S0-8 row:**

  > | S0-8 | 10 min idle with the harness attached, then 50 raises through the harness's copy of `bringToFront` | The display sleeps; `pmset -g assertions` shows nothing from it; `ioreg -c IOHIDSystem \| grep HIDIdleTime` keeps growing from the last raise. If the records reset idle time, §4.12 changes before B1b | yes |

- **Gate table:** "S0-8 | B1b and A3".
- **H8 L2:** "Bans `CGEventPost`, `CGEventPostToPid`, `postToPid` and `IOHIDPostEvent` outside
  `Awake/Sources/ActivitySimulator.swift`, keeps today's `.post(tap:` rule, and allows `SLPSPostEventRecordTo` only
  in `Windows/PrivateWindowAPI.swift`".

### D2-7 · Major · P-13 (non-finding note), Y-12 · Pressure Appendix B, adopted wholesale as the K done-whens, contradicts r2

**Finding.**

- **How Appendix B got in.** The §R1 note (l.1252–1254) and the K done-whens (l.1070–1080) adopt pressure
  Appendix B's test lists wholesale.
- **The substitutions made:** only K1's `…DelayAndGrace`, K2's "+N more" and K5's `--minutes`.
- **Appendix B items that now contradict r2:**
  - **K2:** "the compact card; aspect cap on very wide and very tall windows". r2 has a fixed 16:10 letterboxed card
    (l.506–507), and Y-12's 16:10, one-row and two-column K2 tests appear nowhere.
  - **K3, dismiss reasons:** "Every dismiss reason … Mission Control, … kill switch". r2's `DockDismissReason` has
    neither, and says Mission Control "needs no reason" (l.307–309).
  - **K3, keys:** "`installKeys` only while visible and the pointer is inside; `removeKeys`". r2 uses `engageKeys`
    under the engagement rule (l.304, l.563).
  - **K3, card clicks:** "Card click resolver table: left, middle, right with ⌥, ⌘, ⇧". r2 defines no modifier
    clicks (l.538).
  - **K4, badges:** "Badge precedence (Minimized > Hidden > Full Screen > Other Space)". r2's order is Minimized >
    Full screen > On another Space > display, with Hidden only in the header (l.514).
    - The K4 done-when adds "the §4.3 badge order" with "plus", so both orders are required.
  - **K5:** "The verbs are registered only while the module runs". See D2-2.
- **Effect.** An implementer must write tests that fail against the spec, or decide which text wins.

**Evidence.**
- PLAN:l.304, l.307–309, l.506–514, l.538, l.1071, l.1078–1080, l.1252–1254; §R1 l.1342 (Y-12).
- review-r1-pressure.md:l.1025–1026, l.1039–1040, l.1043–1044, l.1056, l.1072.

**Proposal.** Replace the K2, K3 and K4 done-whens' first clause as follows.

- **K2:** "Appendix B's K2 tests pass with these substitutions:
  - 'shrink one size, then scroll' for '+N more';
  - the fixed 16:10 letterboxed card for 'the compact card' and 'aspect cap';
  - Y-12's cases: one row for a bottom Dock, two columns for side Docks, and the letterbox insets on very wide and
    very tall windows.

  Plus the 10,000-case fuzz invariant."
- **K3:** "Appendix B's K3 tests pass with these substitutions:
  - the dismiss reasons are `DockDismissReason`'s cases (§2.4), with no Mission Control or kill-switch reason;
  - `engageKeys` under §4.5's rule replaces `installKeys`/`removeKeys`;
  - the card click table is §4.4's (left raises, middle closes, right opens the menu; no modifier clicks);
  - pause precedence is kill switch > Safe Mode > other tool > VoiceOver > command."
- **K4:** "Appendix B's K4 tests pass, with §4.3's badge order in place of Appendix B's".

### D2-8 · Major · P-12, X-9 · Done-whens cite manual checks that need later items, and gates sit on the wrong items

**Finding.** Several items can't be closed in the §6 order, because their done-whens need work that comes later.

| Item | Done-when needs | Why it can't pass yet |
|---|---|---|
| B1a, A1a (l.1072–1073) | "M1–M4 pass" | M2 needs the Dock working; M3 needs Dock thumbnails (l.1106–1107). Both arrive in A4a or later |
| A2a (l.1076) | M39 | M39 is "with both modules on" (l.1143) |
| A6a (l.1081) | M33 | Runs before A3, but M33 checks the page row, and the page is A7 |
| A3 (l.1082) | M7–M10 and M32 | They need the panel (A4a) and "a preview shown" |

The gates and the critical path have similar problems.

- **S0-26** measures the freshness notifications that A1b builds, but it gates A2a (l.1031).
- **S0-8** gates A3, not the raise (D2-6).
- **S0-9** records the activation order that K3's `DockClickRules` window (150 ms) depends on, but it gates only A5
  (l.1034).
- **The critical path** (l.1065) skips A2a, though A2b builds on it (l.1062).

**Evidence.**
- PLAN:l.1031–1034, l.1062–1065, l.1072–1082, l.1106–1107, l.1137, l.1143.
- review-r1-pressure.md:l.578 (P-12).
- review-r1-adversarial.md:l.408.

**Proposal.**

- **B1a and A1a done-whens:** "M1 and M4 pass".
- **A2a:** "M5 passes on the last-seen path. With the switcher alone, revoking Screen Recording purges, then shows
  text, with no prompt."
- **A3:** "M21 passes. With the S0-3 harness, `killall Dock` ×10 re-attaches within 2 s (the diagnostics counter)."
- **A4a:** add "M2, M3, M7–M10, M32 and M39 pass".
- **A6a:** "M34 passes; in Safe Mode the `dock live` line is all zeros". M33 moves to A7.
- **Gate table:** "S0-26 | A1b", "S0-9 | K3 and A5", "S0-8 | B1b and A3".
- **Critical path:** "S0 → K1 → K4 → B1a → A1a → B1b → A1b → A2a → A2b → A3 → A4a → A4b → A5 → A7 → R".

### D2-9 · Minor · X-2, P-11 · The crash-guard row, M33 and M35 are narrower than proposed

**Finding.**

- **Crash-guard row.** It reads "Thumbnails of minimized windows stopped after a problem in macOS" (l.854–855). The
  guard covers every symbol in the table (l.753–757), so a stopped Spaces or `axWindowID` symbol shows the wrong
  text.
- **M35** (l.1139) drops X-2's "…and the next hover captures".
- **M33** lacks P-11's "the switcher in Safe Mode shows minimized windows with the last-seen thumbnail or the icon;
  diagnostics show 0 private captures".

**Evidence.** PLAN:l.753–757, l.854–855, l.1137, l.1139; review-r1-adversarial.md:l.136–137;
review-r1-pressure.md:l.575–576.

**Proposal.**

- **Crash-guard row:** "\(feature) stopped after a problem in macOS. Snaptic tries again after a macOS update."
  [Try Again], where `\(feature)` is the `WindowFeature`'s "Used for" text from §4.12.
- **M35:** append "; after Try Again the next hover captures".
- **M33:** as in D2-2.

### D2-10 · Minor · X-2 · Safe Mode now drops the Spaces, AX window id and layout lookups too, with no reason given

**Finding.**

- **What X-2 asked.** In Safe Mode, use SCK only and raise with `kAXRaiseAction`.
- **What §4.13 says** (l.788): "No private symbol is called except the symbolic-hotkey pair". That also turns off,
  for the switcher in Safe Mode:
  - other-Space windows;
  - AX window-id matching;
  - `KBGetLayoutType`, so non-ANSI keyboards fall back to ANSI.
- **Why it's a change.** These have shipped since 0.3 and still run in Safe Mode today. §R1 doesn't mention the
  broadening.

**Evidence.** PLAN:l.786–789, l.765–767; review-r1-adversarial.md:l.136.

**Proposal.** Replace l.787–789 with:

> - The switcher still runs (`SafeMode.stillRuns`), on SCK captures only, and raises with `kAXRaiseAction` plus
>   activate.
>   - The capture and raise symbols aren't called. Each falls back as §4.12's table says.
>   - The other §4.12 symbols run as in 0.4.
>   - Diagnostics report `hwCapture: safeMode`.

If dropping all of them is intended, add instead: "Spaces, window-id matching and the layout lookup also use their
§4.12 fallbacks, so the switcher in Safe Mode lists current-Space windows only and assumes ANSI."

### D2-11 · Minor · Ground rule 3, H3 · Crash-guard writes and the signal handler

**Finding.**

- **The conflict.**
  - Ground rule 3 says every private C symbol "is crash-guarded until it's verified" (l.80). The guard writes
    `Windows.inFlight` to `UserDefaults` around each call (l.754).
  - H3 calls the symbolic-hotkey pair from the signal handler through `HotkeyGuard.releaseAll()` (l.363–364).
  - A `UserDefaults` write isn't async-signal-safe.
- **What H3 covers.** It exempts that path from kill-switch reads only.

**Evidence.** PLAN:l.80, l.754, l.363–364.

**Proposal.** Add to H3 after l.364: "It also makes no crash-guard write: the signal-handler path calls the resolved
pointers bare."

### D2-12 · Minor · P-8, X-24, P-5 · Selftest lines are per feature, not per symbol, and the contract's coverage is overstated

**Finding.**

- **Per feature vs per symbol.**
  - P-8 proposed "one line per §4.12 symbol", and §R1 X-24 claims "per-symbol selftest lines".
  - §4.12 prints "one line per `WindowFeature`" (l.773).
  - Raise is three symbols and Spaces is two, so a missing `SLPSPostEventRecordTo` can't be told apart from a missing
    `GetProcessForPID`.
  - The DEBUG poison run needs "every symbol" to report `poisoned` (l.779), which per-feature lines can't show.
- **Overstated coverage.** §2.2 says the Carbon lookups are "each under the §4.12 contract" (l.223), but
  `IsSecureEventInputEnabled` has no switch and no line (l.769).

**Evidence.** PLAN:l.223, l.769, l.773, l.779; §R1 l.1314 (X-24), l.1231 (P-8); review-r1-pressure.md:l.427.

**Proposal.**

- **l.773:** "`selftest-launch: windows <symbol> available|unavailable|disabled|poisoned [SLS|CGS]`, one line per
  symbol in the table except `IsSecureEventInputEnabled`, from Kit `WindowSymbolContract.launchLines`".
- **l.223:** "Carbon lookups under the §4.12 contract, except the public `IsSecureEventInputEnabled`".

### D2-13 · Minor · X-1 · The injected-result test and the connection-id check were dropped

**Finding.**

- **Injected-result test.** X-1's B1 done-when asked for "a test drives each probe's failure branch with an injected
  result". B1b (l.1074) has only the DEBUG poison run, which forces the poisoned state and doesn't exercise each
  probe's failure branch.
- **Connection-id equality.** The probe dropped "equals `CGSMainConnectionID` when both exist" (l.745).

**Evidence.** PLAN:l.745, l.1074; review-r1-adversarial.md:l.75, l.92.

**Proposal.**

- **B1b done-when:** append "`WindowSymbolContractTests` drives each probe's failure branch with an injected
  result".
- **l.745:** "`SLSMainConnectionID` returns nonzero, and equals `CGSMainConnectionID` when both exist".

### D2-14 · Minor · P-6, X-6 · Client-store tests and the switcher-open eviction case aren't named

**Finding.**

- **A1b's test set** (l.1075) is narrower than proposed. It names only "one client's prune and invalidate never touch
  the other's entries", and leaves out:
  - "the last release empties the store";
  - "one client's purge leaves the other's entries";
  - X-6's "opening the switcher doesn't evict a minimized window's last-seen entry".
- **Call sites.** P-6's count of the store's call sites to update isn't carried into A1b.

**Evidence.** PLAN:l.1075, l.267–272; review-r1-pressure.md:l.309 (P-6); review-r1-adversarial.md:l.291.

**Proposal.** A1b done-when: "`ThumbnailStoreClientTests` pass:

- one client's prune, invalidate and purge never touch the other's entries;
- the last release empties the store;
- opening the switcher doesn't evict a minimized window's last-seen entry.

Every `ThumbnailStore` call site passes a client (grep in `H1-SITES.md`)."

### D2-15 · Minor · P-7 · `Dock.disable.clickActions` isn't read where it can take effect

**Finding.**

- **The read points.** H6 reads switches "before each private call, each tap enable and each capture batch"
  (l.375).
- **Why that misses this switch.** `DockClickTap` is listen-only and enabled for the module's life (l.729), so
  turning `Dock.disable.clickActions` on while running changes nothing until relaunch.
- **No conflict with "takes effect while running".** EventLog is lock-protected (`EventLog.swift:15,24`), so logging
  from any thread is fine.

**Evidence.** PLAN:l.375–377, l.729.

**Proposal.** Add to H6 after l.377: "`Dock.disable.clickActions` is also read on each mouse-up that the resolver
would act on."

### D2-16 · Minor · X-14, X-15 · The window read's thread and the S0-14 measurements

**Finding.**

- **Thread unstated.** X-14 required "all AX and capture work runs off the main thread" while the keys tap is
  enabled. §4.8's per-pid window read has a 0.5 s budget (l.648–649) and no thread. On main, it stalls typing for up
  to 0.5 s while the panel is engaged.
- **S0-14 narrowed.** S0-14 (l.1002) dropped X-15's "Dock read p50, p95 and max during Mission Control, App Exposé,
  a launch bounce and magnification".

**Evidence.** PLAN:l.648–649, l.1002; review-r1-adversarial.md:l.585–586, l.621–622.

**Proposal.**

- **l.648:** "`WindowManager.windows(for pid:budget:allowUntitled:)` runs on `ObserverThread` and reads one app …".
- **S0-14:** "Hover 20 apps in 2 s; an app that stalls AX for 5 s; Dock read p50, p95 and max during Mission
  Control, App Exposé, a launch bounce and magnification | Dock reads never block main over 16 ms".

### D2-17 · Minor · X-8, X-29 · The per-app window cap is gone, and the budget can truncate a list that scrolling promises to show in full

**Finding.**

- **Read cap dropped.**
  - X-8 reused "the window cap of X-29".
  - X-29 asked the Dock to read only the windows that fit plus one, by z-order, and the rest on demand.
  - r2 reads every window under a 0.5 s budget (l.648–649).
- **Truncation.** A 100-window app can hit the budget. §4.3 promises that "every window is reachable" by scrolling
  (l.511, M19).
- **§R1.** X-29's row explains the scroll, not the dropped read cap.

**Evidence.** PLAN:l.511, l.648–651, l.1123; review-r1-adversarial.md:l.360, l.900–901.

**Proposal.** Add to §4.8 after l.649: "When the budget runs out, the panel shows the windows read so far, then a
'More windows…' row that reads the rest on demand. M19 adds a 100-window app."

### D2-18 · Minor · X-9 · The per-window registration cap and the gate row

**Finding.**

- **Cap dropped.** X-9 registered `kAXUIElementDestroyedNotification` per window, "capped like the read". r2
  registers five notifications with no cap (l.248–250).
- **Wrong row cited.** §R1 X-9 cites S0-10, but the freshness row is S0-26. For the gate, see D2-8.

**Evidence.** PLAN:l.248–250, l.1014; §R1 l.1299; review-r1-adversarial.md:l.399–400, l.408–409.

**Proposal.**

- **l.250:** append "; per-window registrations are capped at the windows the last read returned".
- **§R1 X-9:** "§2.3 `.freshness(pid)`; S0-26".

### D2-19 · Minor · X-3, X-10, X-11, Y-11, Y-14, Y-15 · The reviewers' K3 and Kit cases aren't in any done-when

**Finding.** The K3 done-when (l.1079) names topics: swap intent, engagement, the latch, the Dock menu, the resolver
and `appTerminated`. It doesn't name these proposed cases:

- **X-10:** "a magnified icon above the resting frame doesn't trip the safety net; leaving the union for 1 s does";
- **X-11:** race rows for "a diagonal crossing, a reflow under a still pointer, and a click within …";
- **Y-11:** "hovering a windowless app swaps to its small card and never keeps the previous app's panel";
- **Y-14:** "a mouse-down on the Dock cancels the pending show and resets the timer", and the other timing rows;
- **Y-15:** a case for each mouse-down rule;
- **X-3:** see D2-3.

**Evidence.** PLAN:l.1079; review-r1-adversarial.md:l.444–446, l.479; review-r1-parity.md:l.624, l.675–678,
l.703–704.

**Proposal.** K3 done-when: append "and these named cases:

- X-10's magnified-frame and 1 s union cases;
- X-11's three race rows;
- Y-11's windowless swap;
- Y-14's mouse-down and timing rows;
- one case per Y-15 mouse-down rule;
- D2-3's three engagement cases."

### D2-20 · Minor · X-13, Y-15 · Resolver: when the state is sampled, and the ambiguous case

**Finding.**

- **Mouse-down sampling.** Y-15 asked that every resolver input be sampled at mouse-down, before the Dock acts. That
  covers "frontmost", "at least one visible window" and "every window minimized". §4.11 says "Restore-all needs
  every window minimized" (l.728) with no "at mouse-down".
- **Ambiguous case dropped.** X-13's rule was "the click is ambiguous, and nothing happens, if an activation landed
  in the 150 ms before the mouse-down".

**Evidence.** PLAN:l.722–728; review-r1-adversarial.md:l.537; review-r1-parity.md:l.699–702.

**Proposal.**

- **l.728:** "Restore-all needs every window minimized at mouse-down, and it wins over Hide and Minimize."
- **Add after l.728:** "An activation of any other app between 150 ms before mouse-down and the action makes the
  click ambiguous: Snaptic does nothing."

### D2-21 · Minor · X-16, X-28, Y-4 · Three S0 rows are narrower than proposed

**Finding.**

- **S0-13** (l.1001) passes on "`.transient` hides the panel in each". It dropped X-16's "gone or correct within 1 s
  after they close".
- **S0-2** (l.990) dropped X-28's App Translocation case.
- **S0-10** (l.998) lists the odd apps as "Electron, Java, Catalyst". Y-4's set was:
  - Finder's desktop window;
  - Chrome full screen;
  - PWAs and iOS apps;
  - Calculator and Photos;
  - Sidecar as a display.

  §R1 Y-4 says "as proposed".

**Evidence.** PLAN:l.990, l.998, l.1001; review-r1-adversarial.md:l.643, l.875; review-r1-parity.md:l.440–441.

**Proposal.**

- **S0-13 pass:** "`.transient` hides the panel in each, and it's gone or correct within 1 s after they close".
- **S0-2:** add "an app run from App Translocation".
- **S0-10:** "the odd-app set (Electron, Java, Catalyst, Finder's desktop window, Chrome full screen, PWAs, iOS apps,
  Calculator and Photos, Sidecar as a display)".

### D2-22 · Minor · X-21 · The switcher's cache change isn't staged or announced

**Finding.**

- **The change.** The switcher keeps 40 entries for 5 min today. r2 moves it to 120 entries / 96 MB, 30 s freshness
  and 30 min retention.
- **What X-21 asked.** A1 keeps the old numbers, A2 moves both modules, and the release notes list it as a switcher
  change.
- **What r2 has.** GUIDE Upgrading mentions the 30 minutes (l.932). The A-item split and the release-notes line are
  missing.

**Evidence.** PLAN:l.932, l.1073–1077; review-r1-adversarial.md:l.788–789.

**Proposal.**

- **A1a done-when:** append "The store keeps 0.4's 40 entries and 5 min until A2a".
- **D2 work column:** append "release notes list the switcher's new cache limits".

### D2-23 · Minor · Y-7 · "Prefer the quieter path" was dropped

**Finding.** Y-7 asked that, when S0-19 finds that one capture path lights the indicator or prompts and the other
doesn't, the plan prefer the quieter one. §4.9 keeps only "Thumbnails defaults off" as the contingency (l.1044).

**Evidence.** PLAN:l.1044; review-r1-parity.md:l.540.

**Proposal.** Add to §5 contingencies: "S0-19 finds one path quieter (no indicator, prompt or alert): that path is
preferred for both modules, within the 0.4 rules."

### D2-24 · Minor · Y-3 · "Don't show previews for" contradicts §9 and §R1

**Finding.**

- **What §R1 and §9 say.** §R1 Y-3 and §9 put "an 'Apps to leave out' list" in a later release, with the reason "the
  protected apps list covers the privacy case" (l.1201, l.1333).
- **What the body says.** The body adds "Don't show previews for (Advanced) lists apps whose Dock items never show a
  panel" (l.658, l.902). That list isn't in the r1 draft.
- **Effect.** It's either the deferred list under another name or a second list nobody reviewed, and it has no
  strings, default or K4 test.

**Evidence.** PLAN:l.658, l.902, l.1201, l.1333.

**Proposal.** Delete l.658 and the "Don't show previews for" bullet at l.902.

If it stays, then:

- §9 l.1201 becomes "An 'Apps to leave out' list for windows inside a panel is a later candidate; 'Don't show
  previews for' (§4.8) hides the whole panel for an app";
- K4 gains "an app in 'Don't show previews for' never produces `show`".

### D2-25 · Minor · P-1 · What an untitled other-Space card offers

**Finding.**

- **What P-1 decided.** Untitled other-Space windows are "Window on another Space" cards "with Bring Forward only".
- **What §4.4 says.** Middle-click closes and the card menu has Close, Minimize and Full Screen (l.538–547). It
  doesn't say these are absent on such cards, or what ⌘W does on one.

**Evidence.** PLAN:l.526, l.538–547, l.765; §R1 l.1224.

**Proposal.** Add to §4.4 after l.538: "A card without an AX element (an untitled other-Space window, or no window-id
match) offers only Bring Forward. Middle-click, the hover buttons, the card menu's window items and ⌘W/⌘M do
nothing on it."

### D2-26 · Minor · P-14, P-15 · M49 and M50 lost their baselines

**Finding.**

- **M49** (l.1153) is an absolute "at most 1 per second". P-14 asked for a delta: "within 1 per second of the module
  being off". Without a baseline, Awake or the switcher can make it fail.
- **M50** (l.1154) dropped P-15's "EventLog `dock.started` and `dock.stopped` counts match the cycles".

**Evidence.** PLAN:l.1153–1154; review-r1-pressure.md:l.680–681, l.708–709.

**Proposal.**

- **M49:** "Idle 10 min with the module on: Snaptic's idle wake-ups (`top -stats pid,idlew`) are within 1 per second
  of the module being off".
- **M50:** append "; EventLog `dock.started` and `dock.stopped` counts match the cycles".

### D2-27 · Minor · P-17, G-14 · CLI refusals: which verb, the Run Both hint, and `dockCases`

**Finding.**

- **Which verb.** §4.21 lists four refusal texts (l.949–952) but not which verbs give them. Does `status` refuse in
  Safe Mode? Does `pause`?
- **Run Both hint.** P-17's "Turn on Run Both in Settings to use both." was dropped.
- **`dockCases`.** A9's `dockCases` (l.1089) has no case list, which was P-17's other ask.

**Evidence.** PLAN:l.948–952, l.1089; review-r1-pressure.md:l.758, l.772–773, l.778.

**Proposal.** Replace the refusal list with:

> **Refusals** (`ControlExit.unavailable`, exit 5), for `pause` and `resume` only. `status` always answers.
> - "Dock Previews is paused while another Dock preview app runs. Choose Run Both Anyway in Dock Previews' Advanced
>   settings to use both."
> - …

**A9 done-when:** "`dockCases` pass:

- status;
- the `status --json` keys;
- pause, `pause 30m`, a second pause extends;
- resume, resume while not paused;
- each exit-5 refusal through its DEBUG hook."

### D2-28 · Minor · P-22 · "No `0.5.0/` copy" was dropped

**Finding.** P-22 asked that the release notes live only at `docs/design/0.5/RELEASE-NOTES-0.5.0.md`, with no
`docs/design/0.5.0/` copy. The D2 done-when (l.1091) checks the path but doesn't forbid the copy.

**Evidence.** PLAN:l.1091; review-r1-pressure.md:l.875.

**Proposal.** D2 done-when: append "There is no `docs/design/0.5.0/` directory".

### D2-29 · Minor · G-3, G-5, G-6, G-15 · Menu and page strings, and a Kit test, were dropped

**Finding.**

- **G-3.** §4.19 (l.919–920) lacks two items:
  - "Turning Dock Previews on later never changes its presence";
  - the Menu Bar page help "Previews show when you point at the Dock. Change them in Settings."
- **G-5.** Slider "in steps of 0.1 s" is missing. The footer (l.888) lost:
  - its layout: Restore Defaults leading, "shown only while the module is on"; Advanced… and (?) trailing.
- **G-6.** The footnote (l.814) lost "While Run Both Anyway is chosen", so it reads as always shown.
- **G-15.** K1 lacks the Kit test `inSentence("Dock click actions") == "Dock click actions"`.

**Evidence.** PLAN:l.814, l.879–880, l.888, l.919–920, l.1070; review-r1-grill.md:l.238–241, l.349, l.360–363,
l.403, l.751.

**Proposal.**

- **§4.19, after l.920:** "Turning Dock Previews on later never changes its presence. The Menu Bar page's help for
  Dock Previews: 'Previews show when you point at the Dock. Change them in Settings.'"
- **l.879:** "slider 0–1 s in steps of 0.1 s".
- **l.888:** "**Footer**: **Restore Defaults…** on the leading edge, shown only while the module is on; **Advanced…**
  and (?) on the trailing edge."
- **l.814:** "While Run Both Anyway is chosen, a footnote reads …".
- **K1 done-when:** append "`SentenceTextTests.testDockClickActionsInSentence` passes".

### D2-30 · Minor · G-7, G-8, G-9, G-10, G-13, G-19, G-20 · Docs and onboarding items were dropped

**Finding.**

- **G-7.** Two things were dropped:
  - the `H1-SITES.md` line for onboarding's `requiredPermissions` loop;
  - the "choosing Dock Previews in onboarding lists both permissions" check.

  §R1 cites §4.20, which has neither.
- **G-8.** Two things were dropped:
  - M29's "five rows fit at the default text size";
  - the 0.3.2 Upgrading entry's added line.
- **G-9.** "README says so next to this setting" (Snaptic never changes the Dock's own preferences) was dropped.
- **G-10.** "Switching from DockDoor" is named (l.815) without the proposed behaviour-only table.
- **G-13.** §R1 claims "D1 README outline", but none exists. G-13 proposed:
  - a paragraph;
  - five bullets;
  - a permissions sentence;
  - two links.
- **G-19.** S0-32's result isn't routed to the "Switching from DockDoor" differences list.
- **G-20.** It's unstated which switcher page shows the `Windows.*` lock rows (they change the switcher too).

**Evidence.** PLAN:l.815, l.903, l.924–934, l.1090, l.1133, l.1020; §R1 l.1268, l.1274;
review-r1-grill.md:l.444–447, l.490, l.502–506, l.546, l.578, l.700–707, l.803, l.811.

**Proposal.**

- **K1 work column:** add "the onboarding `requiredPermissions` line in `H1-SITES.md`".
- **A8 done-when:** append "A Kit check confirms that choosing Dock Previews lists Accessibility and Screen
  Recording".
- **M29:** "Fresh install onboarding with Dock Previews on; five module rows fit at the default text size".
- **§4.20:** add "The 0.3.2 Upgrading entry gains 'You'll see Dock Previews as a new, off module.'"
- **§4.11:** add "The README says, next to this setting, that Snaptic never changes the Dock's own preferences."
- **D1 work column:** add "the README section per G-13: one paragraph, five bullets, a permissions sentence, links to
  the guide and Switching from DockDoor; the guide's Switching from DockDoor is a behaviour-only table, including
  every S0-32 default that differs from Snaptic's".
- **H6:** add "The `Windows.*` lock rows show on both the Window Switcher's and Dock Previews' Advanced sheets."

### D2-31 · Minor · G-11, G-12 · The panel border and the scroll direction

**Finding.**

- **G-11.** Increase Contrast lost the border "around the panel" (l.617).
- **G-12.** Two items were lost:
  - "horizontally for a bottom Dock, vertically for side Docks, with the scroll wheel or trackpad" (l.510–511);
  - M19's "apps with no open windows show their card" (l.1123).

**Evidence.** PLAN:l.510–511, l.617, l.1123; review-r1-grill.md:l.627, l.653–658.

**Proposal.**

- **l.617:** "Increase Contrast: 1 pt borders on cards and around the panel, and a header separator."
- **l.510:** "If they still don't fit, the panel scrolls: horizontally for a bottom Dock, vertically for side Docks,
  with the scroll wheel or trackpad."
- **M19:** append "; apps with no open windows show their card".

### D2-32 · Minor · G-21 · B/V markers and clauses were lost when the M rows were merged

**Finding.** Merging G-21's rows changed five of them.

| Row (PLAN line) | Lost in the merge |
|---|---|
| M42 (l.1146) | V |
| M43 (l.1147) | V |
| M44 (l.1148) | V, and "the last step's text is true" |
| M46 (l.1150) | B (it was B) |
| M47 (l.1151) | "CLI `unavailable`" |

§R1 says overlaps are "kept once", not weakened.

**Evidence.** PLAN:l.1146–1151; review-r1-grill.md:l.829–836.

**Proposal.**

- **M42, M43:** add V.
- **M44:** "Onboarding with Dock Previews as the only module: menu presence `.inSnapticMenu`; the Snaptic icon shows
  and the last step's text is true | B | V".
- **M46:** add B.
- **M47:** append "; `dock status` reports `unavailable`, reason `dockUnreadable`".

### D2-33 · Minor · §R1 · Leftover §R1 text that disagrees with the body

**Finding.** Several §R1 rows name text or structure that isn't in the body.

| Where | §R1 says | The body says |
|---|---|---|
| Legend (l.1214) | Defines **P** (partly accepted) and **R** (rejected) | No row uses either |
| X-25 (l.1315) | `menuOpened`, `menuClosed` | `ownMenuOpened`, `ownMenuClosed` (l.288) |
| X-27 (l.1317) | `DockGeometry` "takes AppKit global coordinates" | `DockGeometry` does the AX → Cocoa conversion (l.193), as Appendix B K2 tests ("AX→Cocoa conversion … round trip") |
| X-9 (l.1299) | S0-10 | S0-26 (D2-18) |
| X-24 (l.1314) | "per-symbol selftest lines" | Per feature (D2-12) |
| G-7 (l.1268) | §4.20 | §4.20 has no onboarding-permission text |

**Evidence.** PLAN:l.193, l.288, l.1214, l.1268, l.1299, l.1314, l.1315, l.1317.

**Proposal.**

- **Legend:** drop "**P** = partly accepted. **R** = rejected, with the reason." (or keep it and say "none in r2").
- **X-25:** "§2.4 (`ownMenuOpened`, `ownMenuClosed`, own-action window 1.5 s / 5 s); §4.2".
- **X-27:** "M: §2.1 (`DockGeometry` converts AX frames with the `Screens.cocoaRect` rules, so Kit owns and tests
  the conversion); §4.7; K2 (Appendix B's negative-x and above-primary cases)".
- **X-9:** fixed in D2-18.
- **X-24:** fixed in D2-12.
- **G-7:** "§4.14; H1 (`requiredPermissions` loop); A8".
