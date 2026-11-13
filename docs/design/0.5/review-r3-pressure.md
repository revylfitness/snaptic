# Snaptic 0.5 plan, round 3: pressure review

- **Reviewer:** pressure (round 3).
- **Plan:** `docs/design/0.5/PLAN.md` r3 (2,023 lines).
- **Grounding:** commit `7dd972c` on `feature/v050-dock-previews`. I read the plan in full, `review-r2-pressure.md`, `scripts/lint.sh`, `scripts/lint03.py`, `scripts/stubs.tsv` and `.github/workflows/build.yml`, and I grepped the tree. Every `path:line` below is at that commit. I didn't run `swift build`.
- **Scope:** I don't repeat r2's P2-1 to P2-25, and I don't reopen owner decisions Q1 to Q7.
- **Counts:** 1 Blocker, 3 Major, 7 Minor.

**What holds.**

- **H1.** The pinned grep gives 1574 hits in 215 files, as stated.
- **H3.** The caller table matches the tree.
- **Lint.** The L2, L14, L17 and L20 claims are true at `lint03.py:521–527`, `:571–575`, `:590–595` and `:720–765`, and `L15_PENDING` is empty at `:1474`.
- **CI.** Every `build.yml` line the plan cites is a `--selftest-launch` step on `macos-15`.
- **SettingsShellRules.** A bare `dock` doesn't resolve (`SettingsShellRules.swift:72–81`).

**r2's Majors.**

- **Closed:** P2-1, P2-3, P2-4, P2-6, P2-7, P2-8 and P2-9.
- **P2-2:** closed in §4.13, but its fix landed in A6a's done-when, where it can't be checked (P3-2).
- **P2-5:** closed for A3 and A6b. It's open again for A6a (P3-2) and partly open for A2b (P3-3).

---

## Blocker

### P3-1 · Blocker · §4.24, K5, A7 · The canonical-strings test can't pass at A7, or ever, as written

**Finding.** §4.24 says every quoted string in §4 is in the Dock controls tables, `DockCommandGrammar` or the views, and a test greps `Sources/` for each one. A7's done-when is that this test passes. Read literally, it can't, for three reasons:

- **Documentation strings.** Some quoted strings in §4 are README or GUIDE text and will never be in `Sources/`:
  - the Guide headings “Other Dock preview apps” and “Switching from DockDoor”, and its closing sentence (§4.15);
  - the Known limitation (§4.16);
  - the GUIDE "Upgrading" sentence (§4.20).
- **Examples with an app name.** “Safari, 3 windows”, “Private window, Safari”, “No open windows, Safari” and “Show Safari” are examples. The source holds the template, not these strings. 0.4's test checks for a whole quoted literal, and it writes interpolations as their source form.
- **A8 strings.** The onboarding row, the welcome text and the New card (§4.20) land in A8, after A7.

K5's test list also names "canonical strings" (l.1608). At K5 no view exists, and every item must pass `swift test`.

**Evidence.**
- PLAN:l.1361–1363 (§4.24) and l.1486 (A7 done-when).
- PLAN:l.1107–1109 (Guide), l.1131 (Known limitation), l.1276–1279 (GUIDE Upgrading).
- PLAN:l.1118 and l.1126 (examples with an app name).
- PLAN:l.1267–1275 (A8 strings) and l.1608 (K5).
- `Tests/SnapticKitTests/IconsControlsTests.swift:153` (`#"\(hidden) hidden"#`), `:192` ("the New card and onboarding (A8)", appended by 0.4's A8) and `:216` (the whole-literal check).

**Proposal.** Replace PLAN:l.1361–1363 with:

> - Every quoted Settings, menu, panel, VoiceOver and CLI string in §4 is a whole literal in `Sources/`. Interpolated strings are listed in their source form, as 0.4 lists `#"\(hidden) hidden"#`. Examples that name an app (“Safari, 3 windows”) are checked through their template.
> - `DockControlsTests.testEveryCanonicalStringIsInTheSources` reads its list from the test file and greps `Sources/` for each entry (P-23). K5 creates the test with the strings in K5's tables. A4a, A4b, A6b and A7 append the strings they add. A8 appends §4.20's onboarding row, welcome text and New card.
> - Strings that appear only in the README, GUIDE or site (§4.15 Guide, §4.16 Known limitation, §4.20 GUIDE "Upgrading") aren't in this list. D1 checks them.
> - A change to a string changes this plan in the same commit.

Then make these changes:
- **K5 test list.** At l.1608, change "canonical strings" to "`testEveryCanonicalStringIsInTheSources` over the strings in K5's tables".
- **A7 done-when.** Change it to "`testEveryCanonicalStringIsInTheSources` passes with every §4 UI string except §4.20's".
- **A8 done-when.** Add "§4.20's strings are in `testEveryCanonicalStringIsInTheSources`, and it passes".
- **D1 done-when.** Add "Every §4.15, §4.16 and §4.20 string marked for the README or GUIDE appears there word for word".

---

## Major

### P3-2 · Major · §6 A6a, §4.22 · A6a's Safe Mode check needs A9 and K5, and its counter check can't fail

**Finding.** A6a's done-when has three problems.

- **"It registers its verbs."** The verbs are A9's `DockCLI`, built on K5's `DockCommandGrammar`. A6a needs only K1 and A1a.
  - This is r2's P2-5 coming back. P2-5 set A6a's check to "In Safe Mode the module doesn't start". P2-2 then changed §4.13 to "registers its three `dock` verbs", and the merged text put that into A6a.
- **"`dock live` stays zero in Safe Mode."** `dock live` is a selftest line, and §4.22 says "every value is 0 in the selftest, because no module starts there". It can't tell a Safe Mode start from any other. The check can't fail, so it proves nothing.
- **"`dock live` prints all zeros."** Five of its six counters are statics on types that A3, A4a and A5 create: `DockObserver.live`, `DockClickTap.live`, `DockKeys.live`, `DockPreviewPanel.live` and `DockPreviewController.timers`. The plan doesn't say what A6a prints for types that don't exist yet.

**Evidence.**
- PLAN:l.1480 (A6a) and l.1488 (A9).
- PLAN:l.1055–1060 (§4.13) and l.1332–1335 (§4.22).
- PLAN:l.1610 ("Registered while the module runs, paused included" is an A9 check).
- `review-r2-pressure.md:143` (P2-5).

**Proposal.**

§4.22 counters. Replace the first bullet (l.1332–1333) with:

> **Live counters**: Kit `DockLive` has one counter each for observer, clickTap, keys, panel and timers. A6a adds it and the selftest line. A3 (observer), A4a (panel, timers) and A5 (clickTap, keys) increment and decrement them from their types. `WindowServices.liveLeases` stays where it is.

A6a done-when. Replace it with:

> The `selftest-launch: dock live …` line prints, all zeros. M34 passes. Launched in Safe Mode, the page's module state is `.degraded("Paused in Safe Mode")`, and `diagnosticsLines()` shows the observer not attached, 0 leases and 0 captures. Verb registration in Safe Mode is checked in A9's `dockCases`.

A9 done-when. Add:

> a module built in Safe Mode registers the three verbs, `status` answers `state=paused reason=safeMode`, and `pause` and `resume` exit 5.

### P3-3 · Major · §6 Needs and done-whens · Seven checks or work steps depend on items outside the item's Needs

**Finding.** l.1456 says "a done-when names only checks that the item and the items it needs can run", and l.1459 says the Needs column is the rule. Seven entries break that.

Only the S0 → … → R order hides these gaps. Anyone who works from the Needs column, or runs two items at once, will start an item before what it needs.

Taking each item's Needs, and then their Needs:

- **B1b:**
  - its probes run "at the first `WindowServices.acquire`", and `WindowServices` is A1a;
  - B1b needs only B1a.
- **A4b:**
  - **M16** checks `Windows.disable.raise`, which is B1b's typed kill switch. B1b isn't among A4b's Needs. The same goes for A4a's and A6b's use of each symbol's state (§4.22 diagnostics).
  - **M22** checks "paused by default". The VoiceOver pause is A6b's work, and A6b isn't among A4b's Needs.
  - **M38** checks "Known limitations and the Window thumbnails help say so". Known limitations is D1, and the help is A7.
- **A5, M26:** "the feature stops with its row". The page rows are A7.
- **A7:**
  - **M33** checks that the switcher shows last-seen thumbnails in Safe Mode and that diagnostics show 0 private captures. That is A2b's Safe Mode rule.
  - **M35 (Dock page)** checks the crash guard, which is B1b.
  - Neither A2b nor B1b is among A7's Needs.
- **A2b, M35:** "Try Again clears it, and the next hover captures". There is no hover until A4a.

**Evidence.**
- PLAN:l.946 (probe at the first `acquire`).
- PLAN:l.1456 and l.1459 (the rules).
- PLAN:l.1473, l.1476, l.1482–1486 (Needs and done-whens).
- PLAN:l.1653, l.1659, l.1663, l.1670, l.1672 and l.1675 (M16, M22, M26, M33, M35, M38).
- PLAN:l.1340 (diagnostics list each symbol's state).

**Proposal.**

Needs changes (the critical path at l.1463 doesn't change, because A1b → A2a is longer than B1b, and A4a → A4b is longer than A2b):
- **B1b:** `B1a, A1a`.
- **A4a:** `A3, A2a, B1b, K2, K3`.
- **A7:** `A4b, A5, A6b, A2b, K5`.

Done-when changes:
- **A2b:** "M5 and M6 pass. M35 passes on the switcher page, reading 'the next switcher open captures' for 'the next hover captures'. Safe Mode makes no private capture."
- **A4b:** "M16–M18, M20, M41, M46 and M48 pass. M22 passes from 'With the switch on'. M38's share result is recorded in STEP0-NOTES."
- **A5:** "M23–M25, M37, M40 and M42 pass. M26 passes up to 'no freeze over 30 s', with diagnostics showing the tap stopped."
- **A6b:** add "M22's 'paused by default' passes."
- **A7:** "… M26's row half, M27, M28, M33, M35 (Dock page) and M47 pass."
- **D1:** add "If M38 recorded thumbnails in a share, Known limitations says so in M38's words."

### P3-4 · Major · §5 gates, §6 S0 and D1 · S0 can't finish as written, and D1 needs S0-32, which is gated at R

**Finding.** Two statements disagree.

- **S0's done-when:** "Every row has a result on 27.2". But §5 gates S0-31 and S0-32 at R.
  - S0-31 is an 8-hour soak of working previews. It can only run once the module is built, so S0 can't finish as written.
- **D1's work:** "the Switching from DockDoor table … with every S0-32 default that differs". But S0-32 is gated at R, after D1.
  - If S0-32 runs at R, D1's table can't be written and its done-when ("Every H9 README and GUIDE row is done") can't be checked.
  - If S0-32 runs at S0, the gate table is wrong.

S0-32 only reads DockDoor's Settings window. It can run at any time.

**Evidence.**
- PLAN:l.1468 (S0 done-when).
- PLAN:l.1407–1408 (S0-31 and S0-32).
- PLAN:l.1426 (`| R | S0-31, S0-32 |`).
- PLAN:l.1489 (D1).
- PLAN:l.1108 (§4.15).

**Proposal.**
- **§5 gate table.** Replace l.1426 with two rows: `| D1 | S0-32 |` and `| R | S0-31 |`.
- **S0's done-when.** Replace it with: "Every row except S0-31 has a result on 27.2, and on 15 or marked as an owner check. S0-31 runs at R. Each gate row is done before its item (§5 gates). Any **If it fails** answer taken is in STEP0-NOTES."

---

## Minor

### P3-5 · Minor · §2.3 · The oversize skip is 96 MB in one place and 16 MB in three, and 16 MB drops most 2400-pixel previews

**Finding.** §2.3 says "one image over 96 MB is skipped". §4.9, §8 and P-20 say 16 MB. An image over 96 MB can't fit the budget anyway, so l.310 is almost certainly a typo for 16 MB.

The 16 MB cap has a cost the plan doesn't state. The switcher's 2400 bucket caps the longest side at 2400 pixels (`SwitcherController.swift:567`, `ThumbnailStore.swift:141`). Any window squarer than about 3:2 is over 16 MB at 4 bytes a pixel: 2400 × 1800 × 4 is 17.3 MB, and a square window is 23 MB. So those previews are never cached. `ThumbnailIndexTests`' "oversize skip" case needs one number.

**Evidence.**
- PLAN:l.310, l.858, l.861, l.1701 and l.1780.
- `Sources/Snaptic/Switcher/SwitcherController.swift:567` and `Sources/Snaptic/Switcher/ThumbnailStore.swift:141`.

**Proposal.** Replace PLAN:l.310 with:

> LRU eviction by 120 entries and 96 MB; one image over 16 MB is skipped, not stored (§4.9). A 2400-pixel switcher preview of a window squarer than about 3:2 is over 16 MB, so it's shown but not cached, as in 0.4.

### P3-6 · Minor · §4.12 step 6 · The per-symbol counter can unlink a marker that another call has just written

**Finding.** The counter is atomic, but the file operations aren't ordered with it. This sequence leaves no marker:

1. Call A takes the count 1→0.
2. Call B takes it 0→1 and writes the file.
3. Call A unlinks the file.

B is now in the private call without a marker, so a crash there isn't caught.

Calls to one symbol do overlap:
- the capture keeps its marker on every call and runs up to 4 at once;
- `_AXUIElementGetWindow` runs inside `concurrentPerform` until it's verified.

**Evidence.**
- PLAN:l.979–982, l.986–987, l.1475 (the cap of 4) and l.430.
- `Sources/Snaptic/Switcher/WindowManager.swift:354` and `:379`.

**Proposal.** Replace the second sentence of PLAN:l.980 with:

> A per-symbol `os_unfair_lock` covers the count and the file: under it, a 0→1 opens the file and calls `write(2)`, and a 1→0 unlinks it. The lock is held for the count change and the file call only, never across the private call. The signal handler takes no lock and writes no marker.

Add to `CrashGuardTests` (l.1619): "a 1→0 and a 0→1 on one symbol, interleaved, leave the marker in place."

### P3-7 · Minor · §2.1, §6.1 K1, §4.18 · `SentenceText.unit` has two parameters in the plan and three in the code, and one use passes a fraction

**Finding.** The plan moves `unit(_:_:)` with two arguments and tests `unit(3, "window") == "3 windows"`. The function being moved is `AwakeCountdown.unit(_ n: Int, _ one: String, _ many: String)`. Its callers pass both forms, and two pass `L("min"), L("min")`.

A two-argument version would have to build the plural itself:
- it would print "3 mins";
- it would break those Awake strings.

§4.18 also says the delay value "0.1 s" comes from `SentenceText.unit`, which takes an `Int`.

**Evidence.**
- PLAN:l.228, l.1208 and l.1523.
- `Sources/SnapticKit/AwakeClock.swift:210`.
- `Sources/SnapticKit/AwakePresentation.swift:311` and `:314`.

**Proposal.**
- **l.228.** Replace with: "`AwakeCountdown.unit(_:_:_:)` moves from `AwakeClock.swift:210` into `SentenceText` unchanged, so "1 window" and "3 windows" share Awake's plural rule (G-24). Its callers change only the type name."
- **l.1523.** Replace with: "`SentenceText.unit(1, "window", "windows") == "1 window"` and `unit(3, "window", "windows") == "3 windows`"".
- **l.1208.** Change "(`SentenceText.unit`)" to "(one decimal, then `L(" s")`)".

### P3-8 · Minor · §6.1 K1 · `testSanitizeOwnIconBecomesHidden` contradicts H1's fallback

**Finding.** H1 sets `fallback(for: .dockPreviews)` to `.inSnapticMenu`, and `sanitized()` replaces a presence the module doesn't allow with that fallback. So `.ownIcon` becomes `.inSnapticMenu`, not `.hidden`. A test written to its name fails.

**Evidence.**
- PLAN:l.399–401 and l.1502.
- `Sources/SnapticKit/Config/ConfigModules.swift:209`.
- `Sources/SnapticKit/KitModules.swift:112–114`.

**Proposal.** At l.1502, rename the test to `testSanitizeOwnIconFallsBackToInSnapticMenu`, which asserts that `.ownIcon` on `.dockPreviews` sanitizes to `.inSnapticMenu`.

### P3-9 · Minor · H7, A8 · A8's welcome text breaks a pinned 0.4 test that H7 doesn't list

**Finding.** `IconsControlsTests.canonical` pins 0.4's welcome sentence as a whole literal. A8 replaces that sentence in `Onboarding.swift`, so the 0.4 test fails at A8. Neither H7 nor A8 says to update it.

**Evidence.**
- PLAN:l.464–476 (H7), l.1271–1272 and l.1487.
- `Tests/SnapticKitTests/IconsControlsTests.swift:196–197`.
- `Sources/Snaptic/Core/Onboarding.swift:227`.

**Proposal.**
- **H7.** After l.465, add: "Updated in A8: `IconsControlsTests.swift:196–197`, the welcome text, which becomes §4.20's sentence."
- **A8 done-when.** Add: "`IconsControlsTests.testEveryCanonicalStringIsInTheSources` passes with the new welcome text."

### P3-10 · Minor · §4.12 step 1, R2 X2-7 · `GetProcessForPID`'s image disagrees

**Finding.** The step 1 table says HIServices. The X2-7 row says HIToolbox. The SDK declares it in `HIServices.framework/Headers/Processes.h`.

**Evidence.** PLAN:l.1018 and l.1918.

**Proposal.** At l.1918, change "`GetProcessForPID` from HIToolbox" to "`GetProcessForPID` from HIServices".

### P3-11 · Minor · §6.1 K4 · K4 tests a 30-minute retention that belongs to `ThumbnailIndex`, and A1a keeps 5 minutes

**Finding.** §2.1 puts the 30-minute expiry in `ThumbnailIndex`, and `ThumbnailIndexTests` test it at A2a. A1a keeps 0.4's 5 minutes until A2a.

K4's `WindowCatalogRulesTests` also test "Retention at 30 min". That forces a second retention constant in `WindowCatalogRules`, two items before A1a keeps 5 minutes.

**Evidence.** PLAN:l.212, l.215, l.310–311, l.1593 and l.1626–1628.

**Proposal.** Replace PLAN:l.1593 with "Freshness at 29.9 and 30 s." Retention is tested only in `ThumbnailIndexTests` (A2a).
