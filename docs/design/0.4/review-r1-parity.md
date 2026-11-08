# 0.4 Hidden Icons, review round 1: PARITY

Reviewer: parity. Reviewed `PLAN-draft.md` (r1) against Hidden Bar v1.11.1 (MIT, commit 47937b9).

The goal is full Hidden Bar parity plus three fixes: the new-icon policy, the menu-open guard, and always-hidden
via zero length on both engines. Every Hidden Bar behaviour below gets one of four statuses:

- **Covered (§)**: the plan section that carries it.
- **MISSING**: Hidden Bar does it and the plan doesn't say.
- **CHANGED (reason y/n)**: the plan does it differently. "y" means the plan records why.
- **EXCLUDED (reason)**: it is deliberately left out.

MISSING, and CHANGED without a reason, are findings.

## Evidence key

| Short | Path in `/tmp/hidden-src/repo` |
|---|---|
| SBC | `hidden/Features/StatusBar/StatusBarController.swift` |
| MBE | `hidden/Features/StatusBar/Engine/MenuBarEngine.swift` |
| MEF | `hidden/Features/StatusBar/Engine/MenuBarEngineFactory.swift` |
| LLE | `hidden/Features/StatusBar/Engine/LegacyLengthEngine.swift` |
| NVE | `hidden/Features/StatusBar/Engine/NativeVisibilityEngine.swift` |
| SHIM | `hidden/Features/StatusBar/Engine/Native/HBNativeVisibilityShim.m` |
| ECA | `hidden/Features/StatusBar/ExpandCollapseAction.swift` |
| MBL | `hidden/Features/StatusBar/Layout/MenuBarLayout.swift` |
| AXI | `hidden/Features/StatusBar/Layout/AccessibilityMenuBarInventory.swift` |
| NOC | `hidden/Features/NotchOverflow/NotchOverflowController.swift` |
| AD | `hidden/AppDelegate.swift` |
| AS | `hidden/Common/Assets.swift` |
| PVC | `hidden/Features/Preferences/PreferencesViewController.swift` |
| SS | `hidden/Models/SelectedSecond.swift` |
| UDE | `hidden/Extensions/UserDefault+Extension.swift` |
| SB | `hidden/Base.lproj/Main.storyboard` |
| MAN / ARCH / BL | `docs/MANUAL.md`, `docs/ARCHITECTURE.md`, `docs/BACKLOG.md` |
| T-ENG | `HiddenBarTests/MenuBarEngineTests.swift` |

---

## 1. Parity matrix

### A. Status items and appearance

| # | Hidden Bar behaviour | Evidence | Status | Finding |
|---|---|---|---|---|
| A1 | Arrow item: `variableLength`, template image, autosave name | SBC L18, L157–158; AS L11–25 | Covered §4.1, A1 | — |
| A2 | Separator `\|` (`ic_line`); length 20 when expanded | SBC L19; LLE L16 | Covered §4.3 | — |
| A3 | Optional always-hidden (AH) separator is a translucent `\|` (`appearsDisabled = true`) | SBC L374–397 (L387) | CHANGED (n): drawn as `⋮` | Y-13 |
| A4 | Positions persist through autosave names | SBC L157–158, L389 | Covered H6, A1. First-run order seeding is new | — |
| A5 | At start, `restoreRemovedStatusItems` forces `isVisible = true` on every item | SBC L130–139 | **MISSING** | Y-10 |
| A6 | The arrow glyph swaps on collapse/expand and is flipped in RTL (`ic_expand`/`ic_collapse`) | AS L11–25; SBC L268–300 | **MISSING** | Y-13 |
| A7 | Order is always-hidden … separator … arrow, mirrored in RTL | MBE L47–56 | Covered §4.1 | — |
| A8 | Direction comes from `NSApp.userInterfaceLayoutDirection` (`detectLTRLang`) | AD L103–108; MBE L54 | **MISSING**: the plan doesn't say how direction is detected, and copying Hidden Bar's way breaks in an English-only app | Y-6 |

### B. Engine selection, state and toggling

| # | Hidden Bar behaviour | Evidence | Status | Finding |
|---|---|---|---|---|
| B1 | Factory: Native on ≥27 (direct build), Length otherwise. The App Store build uses Length on 27 | MEF L12–22 | CHANGED (y): no Length on 27, so the module is "unavailable" there. This is right, given #360 (NVE L10–11) | — |
| B2 | States: expanded / calibrating / collapsed / unavailable | MBE L35–40 | Covered §4.1, K2 | — |
| B3 | A collapse while calibrating issues no second request; the in-flight one answers | NVE L76–118 | Covered §4.1 (generation), K2 | — |
| B4 | Without AX: request, report unavailable, don't latch, retry on the next collapse | NVE L93–100; T-ENG L223 | CHANGED (y): prompt once, then auto-retry when the grant arrives | — |
| B5 | Collapse is gated by `isArrangementValid`: on Length the separator must be on the hidden side of the arrow | SBC L248–252; LLE L73–75 | **MISSING** | Y-4 |
| B6 | Hiding the AH section is gated by `isAlwaysHiddenSeparatorPlaced` | SBC L39–42, L227–228; LLE L77–79; NVE L226–228 | **MISSING** | Y-4 |
| B7 | A refused or failed collapse re-arms the auto-collapse timer, so the bar retries later | SBC L248–263 | **MISSING** | Y-14 |
| B8 | Collapse completion sets the image and the policy (`didCollapse` / `didFailToCollapse`) | SBC L268–285 | Covered §4.9 for the policy. The image is A6 | — |
| B9 | 0.3 s debounce on toggle | SBC L238–246 | Covered §4.2 | — |
| B10 | The global hotkey goes through the same debounced toggle | AD L23–25 | **MISSING** | Y-14 |

### C. Length engine (macOS 14–26)

| # | Hidden Bar behaviour | Evidence | Status | Finding |
|---|---|---|---|---|
| C1 | Collapsed length is `max(500, min(2×widest, 10 000))` | LLE L40–49 | Covered §4.1 | — |
| C2 | Falls back to 1728 when no screen is available | LLE L40–49 | **MISSING** | Y-15 |
| C3 | Expanded length 20; state is `length > 20` | LLE L16, L35–38 | Covered §4.1 | — |
| C4 | Re-applies the collapsed length on `didChangeScreenParameters` | SBC L120–128; LLE L81–84 | Covered §4.1 | — |
| C5 | Also re-applies the AH separator's inflated length on screen change | SBC L125–127 | **MISSING** | Y-1 |
| C6 | AH is kept hidden while the bar is expanded by **inflating** the AH separator to the collapsed length. 20 when shown, 0 when disabled | LLE L61–69; MAN L43 | CHANGED (n), and it contradicts the mechanism: the plan uses length 0 | **Y-1** |
| C7 | One-shot `HideMechanism` diagnostic log | LLE L86–111 | CHANGED (y): engine diagnostics row (§4.8) | — |

### D. Native engine (macOS 27)

| # | Hidden Bar behaviour | Evidence | Status | Finding |
|---|---|---|---|---|
| D1 | Shim: dlopen of the MenuBarClientCore path, `NSClassFromString`, `instancesRespondToSelector`, `@try`, completion on main | SHIM | Covered §1, B1, Risks | — |
| D2 | Allow-lists are passed as `NSArray`; `NSSet` is rejected | SHIM L58–59 | **MISSING** | Y-15 |
| D3 | System items kept: `0..<64` | NVE L37 | CHANGED (n): the plan says `0..<63` twice (§1 table, Risks) | Y-15 |
| D4 | Allowed = own bundle + visible-section bundles | NVE L189–212 | Covered §4.1 | — |
| D5 | Activate N+1, then invalidate N; generation counter; stale results dropped | NVE L189–212; T-ENG L295 | Covered §4.1 | — |
| D6 | Activation failure releases the assertion and fails open | NVE L189–212; T-ENG L238 | Covered §4.1 | — |
| D7 | The separator is taken out (`isVisible = false`); the arrow is the boundary | NVE L73, L216–219 | Covered §4.3 | — |
| D8 | AH separator at zero width, not `isVisible = false`, so it keeps its slot. macOS still leaves a gap | NVE L17–24, L216–219 | Covered §4.1. The gap isn't noted | Y-1 |
| D9 | Layout is read only from an unrestricted bar; cached while any assertion exists | NVE L139–143, L164–170; T-ENG L282 | Covered §4.1 | — |
| D10 | A plain expand with AH on **releases** the assertion unless the "separators hidden" mode is on | NVE L145–159; T-ENG L249, L260 | CHANGED (y: the fix), but its consequences aren't handled | **Y-2** |
| D11 | An app launched while collapsed stays hidden until the next collapse | NVE L30–33 | CHANGED (y: §4.4 fix). The detection is wrong | **Y-3** |
| D12 | NSLogs the bundle ids per section | NVE L181 | CHANGED (y): privacy (D1 "no names logged") | — |
| D13 | Must run from `/Applications`; "a copy elsewhere hides its own arrow" | MAN L28–29 | **MISSING** | **Y-5** |

### E. Inventory and layout resolver

| # | Hidden Bar behaviour | Evidence | Status | Finding |
|---|---|---|---|---|
| E1 | AX `AXExtrasMenuBar` on a background queue, messaging timeout 0.1 s | AXI L17, L44–47 | Covered §4.1, §4.6. S0 measures the time | — |
| E2 | AX prompt at most once per launch | AXI L27–32 | Covered §4.1 | — |
| E3 | Skips its own pid and non-`.app` owners | AXI L40–43 | Covered §1 | — |
| E4 | Skips system owners (MenuBarAgent, controlcenter, systemuiserver) and nil bundles | MBL L55, L63–75 | Covered §1, K1 | — |
| E5 | Section by midX; the most visible section wins per bundle; bundles sorted | MBL L46–48, L63–95 | Covered §1, K1 | — |
| E6 | Tests: 6 resolver + 10 Native + 1 Legacy, 6 click resolver, classifier/geometry/menu builder | T-ENG L102–322; `HiddenTests` | CHANGED (n): K2 says "all 8 of Hidden Bar's engine cases" | Y-15 |

### F. Clicks

| # | Hidden Bar behaviour | Evidence | Status | Finding |
|---|---|---|---|---|
| F1 | nil event (VoiceOver / AXPress) → toggle | ECA L22–30 | Covered §4.2 | — |
| F2 | Left mouse-up → toggle | ECA L22–30 | Covered §4.2 | — |
| F3 | Right mouse-up → context menu | ECA L22–30; SBC L149–155 | CHANGED (y): "if macOS delivers it" | — |
| F4 | ⌥-click → toggles a **persisted** "separators hidden / AH shown" mode, expanding if collapsed | ECA L22–30; SBC L212–236, L84 | CHANGED (n): a one-shot "expand including AH (or collapse all)" | Y-8 |
| F5 | Any other mouse button (middle) → toggleSeparators | ECA L28–29 | **MISSING** | Y-8 |
| F6 | ⌃-click arrives as left-up and toggles | ECA L22–30 | CHANGED (n): the plan opens the menu | Y-8 |
| F7 | Left- or right-clicking the separator `\|` opens the context menu | SBC L142–147; MAN L8 | **MISSING** | Y-9 |
| F8 | Menu built fresh and popped up at the button | SBC L188–210 | Covered §4.2 | — |

### G. Context menu

| # | Hidden Bar behaviour | Evidence | Status | Finding |
|---|---|---|---|---|
| G1 | "Show Notch Items" (notch Macs, setting on) | SBC L331–337 | CHANGED (y): the list is shown inline (§4.6) | — |
| G2 | "Preferences..." | SBC L339–341 | **MISSING**: the menu contents are unspecified | Y-9 |
| G3 | "Enable/Disable Auto Collapse" | SBC L343–346 | **MISSING** | Y-9 |
| G4 | "Quit" | SBC L349 | **MISSING** | Y-9 |

### H. Always-hidden section lifecycle

| # | Hidden Bar behaviour | Evidence | Status | Finding |
|---|---|---|---|---|
| H1 | Setting "Enable always hidden section", default off | SB; AD L84–92 | Covered §4.8 (the default isn't stated; it should be off) | — |
| H2 | Enabling creates the item visible (20, translucent) so the user can ⌘-drag it into place; disabling removes it | SBC L374–397 | **MISSING**: how the new ⋮ first appears and gets placed | Y-4 |
| H3 | `areSeparatorsHidden` is persisted and restored at launch | SBC L84, L212–216; UDE | CHANGED (n) | Y-8 |
| H4 | Help popover explaining AH | PVC L314–345 | Covered §4.8 ("How to arrange") | — |

### I. Auto-collapse

| # | Hidden Bar behaviour | Evidence | Status | Finding |
|---|---|---|---|---|
| I1 | On by default, 10 s | AD L84–92 | Covered §4.5 | — |
| I2 | Choices 5/10/15/30/60 s (any float through defaults) | SS; SB; MAN L69 | CHANGED (n): 2–300 s | Y-12 |
| I3 | One-shot timer started on expand | SBC L287–323 | Covered §4.5 | — |
| I4 | Re-armed while the pointer is in the menu-bar band of **any** screen | SBC L53–59, L302–323 | Covered §4.5 ("any screen" isn't stated) | Y-11 |
| I5 | The band test is false in full screen | SBC L53–59 | **MISSING** | Y-11 |
| I6 | Re-armed while the Preferences window is **visible** | SBC L67–70 | CHANGED (n): "key" | Y-12 |
| I7 | Re-armed (restarted) on any preference change | SBC L79, L354–356 | **MISSING** | Y-12 |
| I8 | Re-arming is unbounded; other apps' menus don't defer it (ARCH known limit) | SBC L302–323; ARCH | CHANGED (y): menu-open guard (§4.5) | Y-11 |

### J. Hover to expand

| # | Hidden Bar behaviour | Evidence | Status | Finding |
|---|---|---|---|---|
| J1 | Off by default (defaults-only in v1.11.1) | AD L84–92; MAN L66 | **MISSING**: the default isn't stated | Y-14 |
| J2 | Collapsed + pointer in the band + 0.5 s dwell | SBC L98–118 | Covered §4.5 | — |
| J3 | The monitor is installed only at launch if the pref is on | SBC L73–86 | CHANGED (y): live, exists only while on | — |

### K. Launch and app lifecycle

| # | Hidden Bar behaviour | Evidence | Status | Finding |
|---|---|---|---|---|
| K1 | Always collapses 1 s after launch | SBC L80–82 | CHANGED (y): gated by "Hide icons when Snaptic opens" (default on) | — |
| K2 | "Show preferences on launch" (default **true**) | AD L61–65, L84–92 | EXCLUDED (host onboarding + Settings). Reason not recorded | Y-16 |
| K3 | "Start Hidden Bar when I log in" (SMAppService) and its failure alert | AutoStart L27–40; PVC L76–88 | EXCLUDED (host's existing login item). Not recorded | Y-16 |
| K4 | Single-instance guard | AD L42–59 | EXCLUDED (host). Not recorded | Y-16 |
| K5 | Legacy `LauncherApplication` migration | AD L72–79 | EXCLUDED (n/a) | — |

### L. Use full menu bar on expand

| # | Hidden Bar behaviour | Evidence | Status | Finding |
|---|---|---|---|---|
| L1 | Expand → `.regular` + `activate(ignoringOtherApps:)` | SBC L287–300 | Covered §4.9, H9 | — |
| L2 | Collapse → `.accessory` + `deactivate` | SBC L277–285 | Covered §4.9 | — |
| L3 | A failed collapse keeps `.regular` | SBC L268–275 | Covered §4.9 | — |
| L4 | Default off | AD L84–92 | Covered §4.9 | — |

### M. Notch overflow → hidden-icon list

| # | Hidden Bar behaviour | Evidence | Status | Finding |
|---|---|---|---|---|
| M1 | Notch present when `safeAreaInsets.top > 0` | NOC L37–59 | **MISSING** | Y-7 |
| M2 | Boundary `auxiliaryTopRightArea.minX`, fallback 972. Hidden means `x < boundary` | NOC L37–59, L66–80 | CHANGED (n): §1 says "minX ≥", which is inverted; no fallback | **Y-7** |
| M3 | Screen used: `NSScreen.main` | NOC L88–106 | **MISSING**: no screen is named | Y-7 |
| M4 | Zero-size items dropped | NOC L66–80 | **MISSING** | Y-7 |
| M5 | Each list sorted by x descending (nearest the notch first) | NOC L66–80 | **MISSING** | Y-7 |
| M6 | Two sections, "Hidden Behind Notch (n)" and "Visible (n)", under a bold header | NOC L125–171 | CHANGED (n): no visible section | Y-7 |
| M7 | One row per **extra**, titled by its AX title (falling back to the app name) | NOC L188–213, L231–278 | CHANGED (n): one row per app with a count | **Y-7** |
| M8 | Hidden rows: ⚠️ glyph + bold (a cue that isn't colour), icon 18×18 at 50% alpha | NOC L188–213, L284–293 | **MISSING** | Y-7 |
| M9 | Empty state "No items found (grant Accessibility permission)", disabled | NOC L125–171 | **MISSING** | Y-7 |
| M10 | Without AX: prompt and show nothing | NOC L113–121 | **MISSING** | Y-7 |
| M11 | AXPress on the chosen element | NOC L215–218 | Covered §4.6 | — |
| M12 | Setting "Enable Notch Overflow" (default on), shown only on notch Macs | AD L84–92; PVC L61 | CHANGED (y): the tab toggle, since the list now covers hidden items too | Y-16 (duplicate toggle) |

### N. Shortcut

| # | Hidden Bar behaviour | Evidence | Status | Finding |
|---|---|---|---|---|
| N1 | One global shortcut, unset by default, toggles | AD L23–25; UDE | Covered §4.7 | — |
| N2 | Recorder, clear button, key names (F1–F20, ⏎ ⌫ ⎵) | PVC L116–156; GlobalKeybindingPreferences | Covered (host `GlobalHotkeys` / `KitHotkeys`) | — |

### O. Preferences UI

| # | Hidden Bar behaviour | Evidence | Status | Finding |
|---|---|---|---|---|
| O1 | Tutorial mock bar with "Hidden / Shown / Always Hidden" labels, rebuilt when AH is toggled | PVC L227–312 | Covered §4.8. Per-engine wording missing (BL L23–24) | Y-16 |
| O2 | About tab: version, links, MIT credit | AboutViewController; SB | EXCLUDED (host About; D2 credits). Not recorded | Y-16 |
| O3 | ⌘W closes Preferences except while recording | PreferencesWindowController L49–60 | EXCLUDED (host Settings window) | — |
| O4 | Pref changes apply live (`.prefsChanged`, `.alwayHideToggle`) | Preferences.swift | Covered (config observation) | — |

### P. Platform, docs and distribution

| # | Hidden Bar behaviour | Evidence | Status | Finding |
|---|---|---|---|---|
| P1 | 10 localizations | `*.lproj` | EXCLUDED (Snaptic is English-only, README:829). Not recorded, and it is why Y-6 matters | Y-16 |
| P2 | `AppleLanguages` override doc | MAN L84 | EXCLUDED (follows from P1) | — |
| P3 | macOS 13 floor | project | CHANGED (y): Snaptic's floor | — |
| P4 | App Store sandboxed build | entitlements | EXCLUDED (Snaptic is direct-only) | — |
| P5 | Without AX on 27 the bar stays expanded | MAN L24–25 | Covered §4.1 (fail-open) | — |
| P6 | Stuck items recovered by ⌘-drag; #242 permanent icon loss | MAN; BL L69–77 | Covered H6 (positions reset). Visibility keys missing | Y-10 |
| P7 | Hidden defaults (`hoverToExpand`, custom seconds) | MAN L66–69 | CHANGED (y): exposed in Advanced | — |
| P8 | Import of Hidden Bar's prefs and positions | — | EXCLUDED (positions live in another app's defaults domain). Not recorded | Y-16 |
| P9 | No Sparkle, no analytics | PRIVACY_POLICY | EXCLUDED (n/a; Snaptic has its own Sparkle and EventLog counts) | — |
| P10 | Two hiders conflict | — | Covered Risks (`OtherAppsMonitor`) | — |

**Counts:** 27 MISSING (A5, A6, A8, B5, B6, B7, B10, C2, C5, D2, D13, F5, F7, G2, G3, G4, H2, I5, I7, J1, M1, M3,
M4, M5, M8, M9, M10). 12 CHANGED without a reason (A3, C6, D3, E6, F4, F6, H3, I2, I6, M2, M6, M7). 7 EXCLUDED
items are not recorded in the plan.

---

## 2. Findings

### Y-1. Always Hidden at zero length does not hide anything on the Length engine

- **Severity:** Blocker
- **Plan:** §4.1 "Always Hidden", §1 Known issues row, §4.3, K2

**Finding.** The Length engine hides by pushing everything left of a wide item off-screen. A zero-length item hides
nothing. Say the hidden section is expanded (separator at 20) and the ⋮ separator is at 0. Then every always-hidden
icon is on screen, so the AH section isn't hidden at all.

Hidden Bar keeps AH hidden while expanded the only way the mechanism allows: it **inflates the AH separator** to the
collapsed length (LLE L61–69). Its "only reliable with separators hidden" problem isn't a reliability bug. AH is
simply only *on* in that mode (MAN L43). So the claimed fix inverts the mechanism.

Zero length is correct on **Native** only, where macOS removes the items (NVE L17–24).

Knock-on effects:

- §4.3 "Show section dividers off makes them zero-width when expanded" can't apply to ⋮ on Length. It must stay
  inflated.
- The inflated AH length must be re-applied on screen change (SBC L125–127; C5).
- Inflating ⋮ when it sits right of the separator or arrow would push the visible section and the arrow off-screen
  (see Y-4).

**Evidence.**

- LLE L61–69: `separatorHidden ? (enabled ? collapsedLength : 0) : (enabled ? 20 : 0)`.
- SBC L120–128 (re-apply on screen change).
- MAN L43 ("reliably pushed off-screen only when 'hide separators' is also on").
- NVE L17–24.

**Proposed plan text** (replace the §4.1 "Always Hidden" bullet):

> - **Always Hidden.** Lengths per engine, with `L = collapsedLength` (the Length engine's formula):
>
>   | State | Length engine: separator `\|` | Length engine: `⋮` | Native: `⋮` |
>   |---|---|---|---|
>   | Collapsed | L | 0 | 0 (assertion hides both sections) |
>   | Expanded (plain click) | 20, or 0 if dividers are off | **L** (AH stays pushed off-screen) | 0 (assertion keeps AH out, §4.1) |
>   | Expanded with ⌥ | 20, or 0 if dividers are off | 20, or 0 if dividers are off | 20, or 0; assertion released |
>
>   Transitions widen before they narrow, so nothing flashes. Collapse→plain expand sets `⋮` to L, then `\|` to 20.
>   Plain→⌥ sets `⋮` to 20 only. Any expand→collapse sets `\|` to L first, then `⋮` to 0.
>
>   `didChangeScreenParameters` re-applies L to whichever item is currently inflated. `⋮` is inflated only when
>   `isAlwaysHiddenSeparatorPlaced` holds (§4.1 guards). Otherwise the AH section behaves as part of Hidden and the
>   status row says "Always Hidden divider is out of place".
>
>   On Native, macOS keeps a small gap for the zero-width `⋮` (and for the removed `\|`). This is expected.
>
>   §1's "Known issues" row changes to: Always Hidden works without the ⌥ mode on both engines (Length by inflating
>   `⋮`, Native by keeping the assertion while expanded).

Add a K2 Length truth-table test: state × AH on/off × dividers on/off gives both lengths and the order of writes.

### Y-2. On Native, keeping AH hidden while expanded means the bar is never unrestricted, so the layout is never re-read

- **Severity:** Major
- **Plan:** §4.1 Native, §4.4, §4.6

**Finding.** Hidden Bar releases the assertion on a plain expand, so the bar is unrestricted. Every later collapse
then reads a fresh layout (NVE L145–159, L164–170; T-ENG L249). The plan keeps an assertion on plain expand (allowing
visible + hidden) so AH stays hidden. Because `withLayout` returns the cache whenever any assertion exists (NVE
L164–166; T-ENG L282 `testSectionsAreNotReadWhileSomethingIsHidden`), with AH on the layout is re-read **only after a
⌥-expand**. This has four effects:

1. A user who ⌘-drags an icon between Visible and Hidden while expanded sees no effect on the next collapse. The
   cache still has the old section.
2. Any app that was not running at the last unrestricted read is in no allow-list. It is hidden even while the bar
   is "expanded", so its icon never appears and can't be ⌘-dragged out.
3. §4.4 observes launches "only while collapsed". It misses launches during a restricted expand, which is now the
   common expanded state.
4. The §4.6 list can't classify such an app either.

**Evidence.** NVE L139–143 (`invalidateLayout` is a no-op while restricted), L145–170; T-ENG L260, L282.

**Proposed plan text** (add to §4.1 Native):

> - **Restricted expand (AH on).** A plain expand keeps an assertion that allows system + visible + hidden + own +
>   new-icon bundles. While it is active the cached layout stands, so:
>   - (a) The new-icon watch (§4.4) runs whenever *any* assertion is active, not only while collapsed. A newly
>     seen bundle is added and the assertion is re-activated (N+1, invalidate N).
>   - (b) The layout is refreshed every time the bar is unrestricted: ⌥-expand, fail-open, or stop(). The
>     "How to arrange" help says: "To move icons between sections, ⌥-click the arrow first; changes apply on the
>     next collapse."
>   - (c) The positions of *shown* items are re-read on each collapse from the restricted bar. Only bundles whose
>     AX frame is on screen are re-sectioned; hidden bundles keep their cached section. This catches drags
>     between Visible and Hidden made during a plain expand.
>   - (d) Diagnostics show "layout age" (time since the last unrestricted read).
>
> K2 gains a test: plain expand with AH on → drag simulated in the fake inventory → collapse uses the re-read
> sections for shown bundles.

### Y-3. The new-icon policy treats every launch as "new", and "until the user ⌘-drags it into a section" can't be detected

- **Severity:** Major
- **Plan:** §4.4, H7, K2

**Finding.** `didLaunchApplication` fires for every launch, including login items, relaunches after updates, and
apps the user deliberately put in Hidden. If every such bundle is added to the allow-list ("Show until I move them"),
then after a reboot every login-item icon is shown and Hidden empties. That regresses Hidden Bar, where an app's
section persists through its position (NVE L26–33).

"Until the user ⌘-drags it into a section, then follows its position" also isn't observable. macOS inserts new icons
at the far left (MAN "Why new icons start hidden"), so the icon *starts* in the hidden or AH zone. There's no
position change Snaptic could detect that means "the user chose this". And while an assertion is active,
positions are stale (Y-2).

**Evidence.** NVE L26–33; MAN L86–98 (new icons land far left, inside the hidden zone).

**Proposed plan text** (replace the first two §4.4 bullets):

> - **What "new" means.** IconsConfig keeps `knownBundles` (bundle id → last section and first-seen date). This is
>   local only, excluded from backup (H7), and cleared by Reset. Every unrestricted layout read updates it.
>   A bundle is **new** only if it isn't in `knownBundles`. A launch of a known bundle re-applies its last known
>   section and is never treated as new.
> - **Detection.** Watch `didLaunchApplication` whenever an assertion is active (collapsed *or* restricted expand),
>   plus an inventory re-read 2 s later (macOS adds the extra late). Apps without an extra are ignored.
> - **Native, "Show until I move them".** A new bundle goes into `newAllowed`. It stays shown until the next
>   unrestricted layout read (⌥-expand or a collapse from an unrestricted bar). That read records its section
>   from where the user left it. Because macOS inserts it far left, leaving it alone means Hidden. The one-time
>   notice says: "New icon from <App> is shown. ⌘-drag it right of the arrow to keep it visible; otherwise it will
>   be hidden from the next time you ⌥-click." The notice names the app only in UI, never in logs.
> - **Native, "Hide".** Hidden Bar's behaviour: not allow-listed; listed in the hidden-icon list.
>
> K2 gains tests for: a login-item burst of known bundles (no allow-list change), a new bundle shown and then
> sectioned on an unrestricted read, an update relaunch of a known bundle, and a terminated new bundle.

### Y-4. The arrangement guards (`isArrangementValid`, `isAlwaysHiddenSeparatorPlaced`) and AH placement on enable are missing

- **Severity:** Major
- **Plan:** §4.1, §4.8, A1, K2

**Finding.** On Length, Hidden Bar refuses to collapse unless the separator is on the hidden side of the arrow (SBC
L248–252, LLE L73–75). It refuses to hide AH unless ⋮ is on the hidden side of the separator (SBC L227–228, L39–42).

Without the first guard, a user who ⌘-drags `|` right of the arrow gets a 500–10 000 pt item that pushes the
**arrow** (and Snaptic's own icon, and possibly system items) off-screen. The only way back is to quit. The plan's
"Snaptic's own items sit right of the arrow by seeding" risk row assumes the order is intact.

Y-1's inflated ⋮ needs the same guard. On Native, Hidden Bar treats AH as placed only when it is on the hidden side
of the arrow (NVE L226–228).

Hidden Bar also creates a newly enabled ⋮ visible at 20, translucent (SBC L374–397), so the user can see it and
⌘-drag it into place. The plan doesn't say how a newly enabled ⋮ appears.

**Evidence.** SBC L39–42, L227–228, L248–263, L374–397; LLE L73–79; NVE L222–228.

**Proposed plan text** (add to §4.1):

> - **Arrangement guards** (both are pure Kit functions over item frames, tested in K2):
>   - `arrangementValid`. Length: `\|` is on the hidden side of the arrow. Native: always true.
>     - When it's false, collapse is refused, the arrow shows the collapse-failed state, and the status row says
>       "Move the divider left of the arrow (⌘-drag)". The auto-collapse timer re-arms, so it retries.
>     - It's re-checked before every inflate, including the screen-change re-apply.
>   - `alwaysHiddenPlaced`. `⋮` is on the hidden side of `\|` (Length) or of the arrow (Native). When false, AH is
>     treated as Hidden (Y-1) and the same status row hint shows.
>   - Frames off screen count as "not placed" (`MenuBarOrder` returns false), as in Hidden Bar.
> - **Turning Always Hidden on** creates `⋮` visible at 20, expands the bar if needed, and shows the "How to
>   arrange" hint once. Turning it off removes the item and its autosave position.

### Y-5. Native needs Snaptic to be the LaunchServices-registered copy, or it hides its own arrow

- **Severity:** Major
- **Plan:** §4.1 Native, S0, H4, Risks

**Finding.** The allow-list matches by bundle id. Hidden Bar documents that macOS only recognizes the
`/Applications` copy, so "a copy elsewhere hides its own arrow" (MAN L28–29). If that happens, the toggle disappears
while collapsed, and so do Snaptic's other items. The user can't expand except by shortcut, CLI, or quitting.
Translocated, DMG-mounted, and DerivedData copies (developer runs) all hit this. Snaptic already detects
translocation (`PermissionFlow.isTranslocated`, PermissionsPage).

**Evidence.** MAN L28–29; NVE L180, L192 (own bundle id added to the allow-list).

**Proposed plan text** (add to §4.1 Native, S0 and Risks):

> - **Identity check.** Native collapse is refused, with the status row "Move Snaptic to Applications to hide
>   icons" and the module failing open, when either:
>   - `PermissionFlow.isTranslocated`, or
>   - `NSWorkspace.shared.urlForApplication(withBundleIdentifier: "app.snaptic.Snaptic")` doesn't resolve to
>     `Bundle.main.bundleURL`.
>
>   This is checked at module start and before every activation.
> - **S0** also runs the spike from a second copy outside `/Applications` and records whether the arrow and
>   Snaptic's items survive.
> - **Safety net.** After every successful activation, the arrow's window frame is checked to be on screen within
>   500 ms. If it isn't, the assertion is released (fail open, one notice).

### Y-6. RTL detection can't use `userInterfaceLayoutDirection` in an English-only app

- **Severity:** Major
- **Plan:** §4.1 order, K1

**Finding.** Hidden Bar decides direction from `NSApp.userInterfaceLayoutDirection` (AD L103–108; MBE L54). That
reflects the *app's* localization. Snaptic ships English only (README:829), so the value is always LTR. But the menu
bar is mirrored whenever the *system* language is RTL (Arabic, Hebrew). Under such a system:

- the resolver puts every section on the wrong side;
- Length inflation pushes the visible side off-screen;
- the arrow glyph points the wrong way.

Hidden Bar also sets direction *after* creating its items (AD L17 vs L103; `Constant.isUsingLTRLanguage` defaults to
false, Constant.swift L14). So its first ~1 s of images and order is wrong. Don't port that.

**Evidence.** AD L17, L103–108; MBE L47–56; AS L11–25.

**Proposed plan text** (add to §4.1):

> - **Direction** is the menu bar's, not the app's. It is computed once at module start, before any item is
>   created, and on `NSLocale.currentLocaleDidChangeNotification`:
>   - **Primary:** geometry. If the system items' (clock / Control Center) AX frames are at the left end of the
>     menu-bar screen, the bar is RTL.
>   - **Fallback:** `Locale.Language(identifier: Locale.preferredLanguages.first).characterDirection ==
>     .rightToLeft`.
>
>   K1 tests both resolvers. M-checklist: run once with Arabic as the primary system language.

### Y-7. The hidden-icon list loses per-extra rows and the visible section, and §1 inverts the notch rule

- **Severity:** Major
- **Plan:** §1 table (NotchOverflowController row), §4.6, K1

**Finding.**

- **Inverted rule.** §1 says the controller "lists the extras whose minX ≥ auxiliaryTopRightArea.minX". In fact
  hidden means `position.x < boundary`. Hidden Bar lists *both* sections, Hidden Behind Notch (n) and Visible (n)
  (NOC L66–80, L125–171). Porting the §1 sentence would list exactly the wrong items.
- **Per-extra rows lost.** §4.6 changes rows to one per app "with a count". For an app with several extras (iStat
  Menus, Bartender-style suites, Docker), the user can't pick which extra to open. Hidden Bar lists each extra,
  titled by its AX title, and AXPresses that element (NOC L188–218, L231–278). §7's "per-icon hiding" exclusion
  covers *hiding*, not *opening*.
- **Unspecified details:**
  - notch detection (`safeAreaInsets.top > 0`);
  - which screen (Hidden Bar uses `NSScreen.main`, which is wrong when an external display holds the menu bar);
  - the fallback boundary 972;
  - dropping zero-size items;
  - nearest-first order;
  - the ⚠️ + bold cue that isn't colour, and the 50% icon;
  - the empty state;
  - behaviour without AX.
- **Length-hidden items.** On Length, hidden items sit off-screen. AXPress on them opens their menus off-screen. §4.6
  expands first only for Native.

**Evidence.** NOC L37–59, L66–80, L88–121, L125–218, L231–293; `HiddenTests` NotchOverflowMenuBuilder cases.

**Proposed plan text.**

Fix §1:

> "Splits the extras on the menu-bar screen at `auxiliaryTopRightArea.minX` (fallback 972): x < boundary is behind
> the notch, the rest visible. It lists both, and AXPress opens one."

Replace §4.6's first bullets:

> - Header "Show Hidden Icons" / "Hide Icons". Then sections:
>   - "Hidden (n)": hidden by the engine or behind the notch.
>   - "Shown (n)": optional, collapsed by default.
> - **One row per extra:**
>   - Title: the AX title, falling back to the app name. If an app has several extras, the rows are
>     "App — Title".
>   - Icon 18 pt.
>   - Hidden rows are bold with a "hidden" SF Symbol (a cue that isn't colour), with the icon at 50%.
> - Rows are ordered nearest the boundary first. Zero-size items are dropped.
> - **The notch** is computed on the screen that has the menu bar and `safeAreaInsets.top > 0`.
> - **Empty states:**
>   - "No hidden icons."
>   - Without Accessibility: "Allow Accessibility to list icons" (opens the Permissions row; no auto-prompt from
>     the menu).
> - **Choosing a row:** if the item is hidden by *either* engine, expand first (Length: set lengths, wait ≤ 300 ms
>   for the AX frame to be on screen), press, then re-arm auto-collapse.

K1 gains Hidden Bar's classifier (4) and geometry (4) cases. A5 gains the menu-builder cases: counts, empty state,
title fallback, hidden cue.

### Y-8. The ⌥-click, middle-click and ⌃-click semantics changed with no recorded reason

- **Severity:** Minor
- **Plan:** §4.2, K3

**Finding.**

- In Hidden Bar, ⌥-click toggles a **persisted** mode ("separators hidden / AH shown"), expanding if collapsed. The
  mode survives relaunch (SBC L84, L212–236). The plan makes it a one-shot, "expand including AH (or collapse
  all)". The "(or collapse all)" part is ambiguous: when does it collapse?
- In Hidden Bar, any other mouse button toggles separators (ECA L28–29). The plan doesn't map it.
- In Hidden Bar, ⌃-click arrives as left-up and toggles. The plan sends it to the menu.

The one-shot is a reasonable change once Y-1/Y-2 make AH work without the mode, but the plan should say so.

**Evidence.** ECA L22–30; SBC L84, L212–236; T `ExpandCollapseActionTests` (6).

**Proposed plan text** (replace the §4.2 table):

> | Input | Collapsed | Expanded (plain) | Expanded (⌥) |
> |---|---|---|---|
> | Left click, nil event, shortcut, CLI `toggle` | Expand (plain) | Collapse | Collapse |
> | ⌥-click, CLI `show --all` | Expand (⌥) | Expand (⌥) | Collapse |
> | Right-click, ⌃-click, other mouse button | Menu | Menu | Menu |
>
> The ⌥ state isn't persisted. Hidden Bar's persisted "separators hidden" mode is unnecessary because AH works on
> plain expand (§4.1), and launch always starts plain. K3 ports Hidden Bar's 6 `ExpandCollapseAction` cases with
> these mappings.

### Y-9. The context menu contents are unspecified, and the separator click is missing

- **Severity:** Minor
- **Plan:** §4.2, §4.6

**Finding.** Hidden Bar's menu (built fresh) holds:

- "Show Notch Items";
- "Preferences..." (P);
- "Enable/Disable Auto Collapse" (t);
- "Quit" (q).

Clicking the `|` separator (left or right) also opens it (SBC L142–147, MAN L8). The plan names only the hidden-icon
list. With the separator invisible on Native and zero-width when dividers are off, the separator click is moot
there. It still applies on Length with dividers on.

**Evidence.** SBC L142–147, L328–352.

**Proposed plan text** (add to §4.2):

> Module menu, top to bottom:
>
> 1. The hidden-icon list (§4.6).
> 2. A separator.
> 3. "Hide Icons Automatically" (a checkmark toggle).
> 4. "Hidden Icons Settings…".
> 5. "Quit Snaptic".
>
> On Length with dividers shown, clicking `\|` opens the same menu.

### Y-10. The status items aren't forced visible at start, and Reset leaves the visibility keys

- **Severity:** Minor
- **Plan:** A1, H6

**Finding.** Hidden Bar sets `isVisible = true` on every item at start (SBC L130–139). If the arrow ends up
not-visible (removed through macOS's Menu Bar settings, or a stale `NSStatusItem Visible` key), it comes back. The
plan's A1 doesn't do this.

H6 clears only the `Preferred Position` keys. A collapsed bar with an invisible arrow can only be recovered by
shortcut or CLI. #242 (permanent icon loss) is in this family (BL L69–77).

**Evidence.** SBC L130–139; BL L77.

**Proposed plan text.**

> A1: at module start, after creating the items, set `isVisible = true` on the arrow (and on `⋮` when enabled;
> never on the Native `\|`).

> H6: "Reset All Settings also clears the `NSStatusItem Preferred Position Snaptic.icons.*` and
> `NSStatusItem Visible Snaptic.icons.*` keys."

### Y-11. The menu-open guard is too broad and has no limit; the band rules aren't specified

- **Severity:** Minor
- **Plan:** §4.5

**Finding.** CGWindowList layer `≥ kCGPopUpMenuWindowLevel` (101) also matches:

- overlay and assistive windows (e.g. 1500);
- screen savers;
- notch utilities;
- some apps' always-on-top HUDs that touch the menu-bar band.

Any of these defers auto-collapse forever. Hidden Bar's re-arm is unbounded only for the pointer and Preferences
cases (SBC L302–323).

The band rules also need stating:

- Hidden Bar checks the band on **any** screen and returns false in full screen (SBC L53–59).
- When the menu bar auto-hides, `visibleFrame.maxY == frame.maxY`, so the band has zero height.

**Evidence.** SBC L53–59, L302–323; ARCH (known limit).

**Proposed plan text** (replace the third re-arm bullet in §4.5):

> - a menu is open: a window with layer **== `kCGPopUpMenuWindowLevel`** (or `kCGStatusWindowLevel` menus
>   owned by `SystemUIServer`/`ControlCenter`) whose bounds touch the menu-bar band of any screen. Re-arming for
>   this reason stops after 120 s in a row.
>
> The band is `frame.maxY − menuBarHeight … frame.maxY` per screen, with `menuBarHeight` from `NSStatusBar.system
> .thickness`, so an auto-hidden menu bar still counts. In full screen it doesn't count, as in Hidden Bar.

### Y-12. Delay range, the Settings guard and re-arm on settings change differ without reasons

- **Severity:** Minor
- **Plan:** §4.5, §4.8

**Finding.**

- Hidden Bar offers 5/10/15/30/60 s (SS). Unknown values show as "5 seconds".
- It re-arms while Preferences is **visible** (SBC L67–70), not key. Opening the Settings window behind another app
  shouldn't let the bar collapse while the user arranges icons.
- It restarts the timer on any pref change (SBC L79, L354–356).

The plan gives 2–300 s, "key", and no restart, all without reasons.

**Evidence.** SS; SBC L67–70, L79, L354–356.

**Proposed plan text.**

> - "(default on, 10 s; a stepper 2–300 s, wider than Hidden Bar's 5/10/15/30/60 menu because the Kit control table
>   uses steppers; sanitize clamps)".
> - Re-arm while "the Settings window is visible on the Hidden Icons page".
> - Add: "Changing any Hidden Icons setting while expanded restarts the timer."

### Y-13. The arrow's glyph states, the ⋮ look and accessibility aren't specified

- **Severity:** Minor
- **Plan:** §4.1, A1

**Finding.**

- Hidden Bar swaps the arrow glyph by state and flips it in RTL (AS L11–25). The plan names only "arrow ‹".
- AH was a translucent `|` (`appearsDisabled`, SBC L387). The plan uses `⋮` with no reason.
- Hidden Bar sets no accessibility label or tooltip. The plan relies on VoiceOver AXPress (§4.2), which needs one.

**Evidence.** AS L11–25; SBC L268–300, L387.

**Proposed plan text** (add to §4.1):

> **Item look.**
>
> - Arrow: SF Symbol `chevron.left` when collapsed (points toward the hidden icons) and `chevron.right` when
>   expanded. Mirrored in RTL (Y-6). Template image.
> - `accessibilityLabel`: "Show hidden icons" / "Hide icons". `toolTip` the same, plus the shortcut.
> - The collapse-failed state uses the expanded glyph.
> - `⋮` (`ellipsis` rotated, or the `\|` at 50% alpha as in Hidden Bar) is chosen so it reads as different from
>   `\|`. Its accessibility label is "Always Hidden divider".

### Y-14. Failed-collapse retry, hotkey debounce and the hover default

- **Severity:** Minor
- **Plan:** §4.2, §4.5, §4.9, K3

**Finding.**

- A refused or failed collapse re-arms the timer in Hidden Bar (SBC L248–263). Otherwise a Native collapse that
  waits for AX never retries until the next click.
- The hotkey goes through the same 0.3 s debounce (AD L23–25). The debounce's comment notes it prevents "icon show
  many in Dock" with the full bar on.
- Hover is off by default (AD L84–92). The plan doesn't state a default.

**Evidence.** SBC L238–263; AD L23–25, L84–92.

**Proposed plan text.**

> §4.2: "The debounce covers every toggle source: click, shortcut, CLI, list."

> §4.5: "Hover-to-expand … (default off)". Also: "A refused or failed collapse re-arms the auto-collapse timer, so
> it retries."

### Y-15. Factual slips in the survey and work items

- **Severity:** Minor
- **Plan:** §1, Risks, K2, B1

**Finding.**

- The system items are `0..<64`, not `0..<63` (NVE L37). It appears twice.
- Hidden Bar has 10 Native + 1 Legacy engine tests plus 6 resolver tests (T-ENG L102–322), not "8 engine cases".
  There are also 6 click-resolver tests and the notch classifier, geometry and menu-builder tests.
- The shim must pass `NSArray`, not `NSSet` (SHIM L58–59).
- The Length fallback width when there are no screens is 1728 (LLE L40–49).

**Proposed plan text.**

> - §1 and Risks: "system items 0..<64".
> - K2: "(Hidden Bar's 10 Native + 1 Legacy engine cases)".
> - K1: "(Hidden Bar's 6 resolver cases, 4 classifier and 4 notch-geometry cases, …)".
> - K3: "(Hidden Bar's 6 ExpandCollapseAction cases, remapped per §4.2)".
> - B1: "allow-lists are passed as `NSArray` (Hidden Bar: `NSSet` is rejected)".
> - §4.1 Length: "widest screen width, or 1728 when no screen is available".

### Y-16. Exclusions aren't recorded, the tab toggle is duplicated, and the tutorial isn't per engine

- **Severity:** Minor
- **Plan:** §7, H2, §4.8

**Finding.**

- Several Hidden Bar features are dropped without a recorded reason:
  - "Show preferences on launch" (default true);
  - "Start at login" and its failure alert;
  - the single-instance guard;
  - the About tab;
  - the 10 localizations;
  - import of Hidden Bar's settings.
- The tab toggle appears twice: H2 "Show Hidden Icons in the Snaptic menu" and Advanced "Show Hidden Icons tab in
  Snaptic menu".
- Hidden Bar's backlog flags that the tutorial text must differ per engine, because the arrow is the boundary on
  Native (BL L23–24).

**Evidence.** AD L42–65, L84–92; PVC L76–88, L227–312; BL L23–24.

**Proposed plan text.**

> §7 adds a "Hidden Bar features that the host already provides" list:
>
> - start at login (General's login item);
> - Settings on launch (onboarding);
> - single instance;
> - About and credits (About + D2);
> - localization (Snaptic is English-only);
> - importing Hidden Bar's settings (positions live in Hidden Bar's own defaults domain and can't be read safely;
>   users re-arrange once).

> H2/§4.8: one toggle, in H2's place, listed once in Advanced as a link.

> §4.8 "How to arrange": the diagram and text are per engine. On Length: "drag icons left of `\|` to hide". On
> Native: "drag icons left of the arrow to hide".
