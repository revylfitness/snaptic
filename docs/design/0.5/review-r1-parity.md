# 0.5 Dock Previews, review round 1: PARITY

Reviewer: parity. Reviewed `PLAN-draft.md` (r1, 425 lines) against DockDoor 1.42.4 (GPL-3.0; tag `1.42.4`,
commit 1daaef1, tagged 2026-11-08; deployment target 14.5).

**Sources.**

- DockDoor's defaults (`consts.swift`) and its settings search catalog (217 entries).
- The README, docs, `CHANGELOG.md`, dockdoor.net and dockdoor.net/CHANGELOG.html.
- The issue tracker, read-only with `gh`:
  - the top 100 issues by comments and the top 100 by reactions, all states;
  - every open issue;
  - 20 focus searches (macOS 26/27, Tahoe, multiple monitors, auto-hide, Stage Manager, full screen, Spaces, CPU,
    memory, "stops working", "won't close").
- In all, 177 unique issues. They are ranked by comments + 2 × positive reactions, and 48 threads were read in full.

**Counts:** 1 Blocker, 7 Majors, 11 Minors (19 findings).

**Clean room.** This review describes behaviour, defaults, setting labels and Apple API names only. DockDoor file
paths and line numbers are there so the plan's author can check a claim. Implementers work from the plan and
should not open them.

Every DockDoor behaviour below gets one of these statuses:

- **Included (§)**: the plan carries it. The row says whether our default matches DockDoor's.
- **CHANGED (y/n)**: the plan does it differently. "y" means the plan records why.
- **EXCLUDED §9**: deliberately left out. The row says whether §9's reason holds.
- **MISSED**: DockDoor does it, and the plan neither includes it nor records it in §9.
- **N/A**: not about previews, or not needed by our design.

MISSED, CHANGED (n), and EXCLUDED with no reason or a wrong reason are findings.

## Evidence key

| Short | Path in `/tmp/dockdoor-src` |
|---|---|
| CON | `DockDoor/consts.swift` (defaults) |
| CAT | `DockDoor/Views/Settings/Search/SettingsSearchCatalog.swift` (labels) |
| DO | `DockDoor/Utilities/DockObserver.swift` |
| DU | `DockDoor/Utilities/DockUtils.swift` |
| SPC | `DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift` |
| WDC | `DockDoor/Views/Hover Window/WindowPreview Supporting/WindowDismissalContainer.swift` |
| WU | `DockDoor/Utilities/Window Management/WindowUtil.swift` |
| WDS | `DockDoor/Utilities/Window Management/WindowDiscoveryShared.swift` |
| LWC | `DockDoor/Utilities/Window Management/LiveWindowCapture.swift` |
| KH | `DockDoor/Utilities/KeybindHelper.swift` |
| PA | `DockDoor/Utilities/PrivateApis.swift` |
| GES | `DockDoor/Utilities/Window Gestures/WindowGestureController.swift`, `DockDoor/Utilities/TrackpadSwipeTrigger.swift` |
| LOCK | `DockDoor/Utilities/DockLocker.swift` |
| MR | `DockDoor/Utilities/Media/MediaRemoteService.swift` |
| CL | `CHANGELOG.md` |
| SW | Snaptic `Sources/Snaptic/Switcher/` (`SwitcherController.swift`, `WindowManager.swift`, `ThumbnailStore.swift`, `Settings.swift`, `HotkeyTap.swift`) |
| PIPK | Snaptic `Sources/SnapticKit/Config/ConfigPIP.swift` |

---

## 1. Feature catalogue

### A. Trigger and timing (DockDoor: Dock Previews › Dock Interaction)

| # | DockDoor behaviour (setting label) | DockDoor default | Plan status | Finding |
|---|---|---|---|---|
| A1 | Hovering a Dock app icon shows its windows. The trigger is the Dock list's AX selection (DO) | on | Included §4.1 (PLAN:l.166–172) | — |
| A2 | "Trigger": hover, middle-click or modifier-click on the icon, with a "Modifier" (⌥) (CON L120–121) | hover | **MISSED**, and not in §9. The click modes need a tap that swallows clicks, which is outside our rules. "Show only while a modifier is held" needs no tap | Y-9 |
| A3 | "Open Delay" (CON L35) | 0.2 s | Included PLAN:l.166, l.278. Same default | — |
| A4 | "Only delay initial open". While it's off, moving to the next app waits for the delay again (CON L36) | off | CHANGED (n): swaps are always instant (PLAN:l.168). That is DockDoor with this option on | Y-14 |
| A5 | "Fade Out Duration" (CON L87) | 0.4 s | CHANGED (n): the plan gives no fade time; Reduce Motion drops the fade (PLAN:l.184) | Y-14 |
| A6 | "Inactivity Timer": hide after the pointer leaves (CON L89) | 0.2 s | Included as a 0.25 s grace (PLAN:l.203–204), plus a 1 s safety net (l.205) | — |
| A7 | "Prevent reappearance during fade-out" (CON L88) | off | Included in spirit through the K3 race table (PLAN:l.335) | Y-14 |
| A8 | "Hover Action" on a card: none, bring forward, or full-size preview. Comes with a 1.5 s "Hover Action Delay" and "Keep preview open after hover activation" (CON L86, L90–91) | none | **MISSED**, and not in §9 (#32, #248) | Y-9 |
| A9 | Hover counts only while the pointer is in a band above the Dock (about 220 pt, with 8 pt slop) (DO L809–842) | built in | CHANGED (y): our corridor and safety net (PLAN:l.203–205) | — |

### B. Which windows are listed (Window Display, Filters, Advanced)

| # | DockDoor behaviour (setting label) | DockDoor default | Plan status | Finding |
|---|---|---|---|---|
| B1 | Window sources, in turn: CGWindowList, SCK shareable content, AX windows, then a private remote-token AX lookup for other Spaces. Per-app quirks follow (WU L296–298, WDS L229–345) | — | CHANGED (y): reuse `WindowGatherer`, with no brute-force lookup (PLAN:l.71) | Y-6 |
| B2 | "Show windows from current Space only" (CON L122) | off | **MISSED** | Y-3 |
| B3 | "Show windows from current monitor only" (CON L123) | off | **MISSED** | Y-3 |
| B4 | Sort order: recently used, creation, screen position (1.42.0), title, app name (CON L124) | recently used | Included PLAN:l.178 (Recent / Title). Same default; three orders missing | Y-13 |
| B5 | "Sort minimized/hidden to end" (CON L131) | off | **MISSED** | Y-13 |
| B6 | Include hidden and minimized windows (CON L155) | on | Included PLAN:l.280. Same | — |
| B7 | "Show apps with no windows" in Dock previews (CON L159) | off | CHANGED (n): our default shows a "No open windows" card (PLAN:l.183, l.280) | Y-11 |
| B8 | Quit button on a windowless app's card (CON L147) | on | Included through the header's Quit (PLAN:l.180) | — |
| B9 | "Open new window for windowless apps" on click (CON L161) | off | **MISSED**, and not in §9. It needs a synthetic ⌘N or an Apple event, so it is out | Y-9 |
| B10 | "Keep preview when app terminates" (CON L138) | off (the preview closes) | **MISSED**: the dismissal list (PLAN:l.208–209) has no "app quit" reason | Y-18 |
| B11 | "Group app instances": two copies of one app under one icon. Instances map by Dock order (CON L164; DO L610–730) | on | Partly: S0-2 resolves the pid (PLAN:l.70, l.306), but the plan never says whether copies are grouped | Y-16 |
| B12 | "Collapse native tabs" (CON L165) | off | **MISSED** (#1405, #1034) | Y-16 |
| B13 | "Ignore apps with one window" (CON L162) | off | **MISSED**. Low value; leave it out | — |
| B14 | "Show small windows (under 100px)" (CAT L1821–1824) | off: windows under 100 px are hidden | **MISSED** | Y-3 |
| B15 | "Application Filters", which exclude apps (CON L281) | empty | **MISSED**. The switcher already has `excludedBundleIDs` | Y-3 |
| B16 | "Window Title Filters" (CON L282) | empty | **MISSED** | Y-3 |
| B17 | Notification-style pop-ups, such as a meeting reminder, are never listed (CL L420, 1.40.0) | built in | **MISSED** | Y-3 |
| B18 | "Custom App Directories": find apps installed in unusual folders | empty | N/A: we resolve apps from `kAXURLAttribute` (PLAN:l.70) | — |
| B19 | Discovery: windows seen once stay known while minimized or on another Space | built in | Included through the last-seen cache (PLAN:l.72, l.226) | — |
| B20 | Private-window protection | none | **MISSED**: the Snaptic switcher protects private windows, and the plan doesn't carry that to the Dock or the shared cache | Y-1 |

### C. Cards and layout (Dock Preview Appearance, Appearance)

| # | DockDoor behaviour (setting label) | DockDoor default | Plan status | Finding |
|---|---|---|---|---|
| C1 | Preview "Width" and "Height" (CON L30–31) | 300 × 187.5 pt | CHANGED (n): Small / Medium / Large (200 / 280 / 360 pt), with no default named (PLAN:l.179) | Y-12 |
| C2 | "Lock aspect ratio" at 16:10, and "Dynamic sizing" (CON L32) | locked; dynamic off | CHANGED (n): "height follows the thumbnail's aspect, capped" is dynamic sizing | Y-12 |
| C3 | "Max Rows (Bottom)" (CON L256) | 1 | CHANGED (n): a bottom Dock wraps into more rows (PLAN:l.181) | Y-12 |
| C4 | "Max Columns (Left/Right)" | 2 | Partly: "side Docks: columns", with no count (PLAN:l.181) | Y-12 |
| C5 | App header with icon and name ("App Header Style") | on | Included PLAN:l.180 | — |
| C6 | "Show Close All and Minimize All" header buttons (CON L111) | on | **MISSED**: our header has Hide and Quit only | Y-10 |
| C7 | Card buttons: quit, close, minimize, full screen. Shown "dimmed on preview hover", top-left (CON L218) | dimmed; 4 buttons | Included PLAN:l.192 (close, minimize, full screen) | — |
| C8 | Window title on the card; font size; long-title overflow | on | Included PLAN:l.176 | — |
| C9 | "Distinguish minimized/hidden" labels | on | Included PLAN:l.176–177 (badges) | — |
| C10 | "Show Space number" (CON L224) | off | **MISSED**: we have an "Other Space" badge only | Y-17 |
| C11 | Compact mode (titles only) past N windows, the "Dock threshold" (CON L151) | 0 (never) | Partly: text-only appears only without Screen Recording or with Thumbnails off (PLAN:l.81, l.281) | — |
| C12 | "Unselected Content Opacity" (CON L181) | 0.75 | Not specified; styling | — |
| C13 | "Active window border" (CON L193) | off | Not included; harmless | — |
| C14 | Animations, and a "Reduce motion" setting (CON L115) | on | Included PLAN:l.184, which follows the system setting | — |
| C15 | Background style, material, opacity, corner radius (20), glass tuning (CON L197) | Liquid Glass | EXCLUDED §9 PLAN:l.425. The reason is correct (see Y-9) | — |
| C16 | Theme, colours, gradients, blur, spacing scale; hide card and container backgrounds | — | Not included; we use the existing design system (PLAN:l.425) | — |
| C17 | Overflow: the cards scroll inside the panel | — | CHANGED (y): a "+N more" card opens the switcher (PLAN:l.181–182) | — |

### D. Card actions and keys

| # | DockDoor behaviour (setting label) | DockDoor default | Plan status | Finding |
|---|---|---|---|---|
| D1 | Click raises the window | — | Included PLAN:l.190; reuses `WindowManager.focus` (l.76) | — |
| D2 | Middle-click action (CON L337) | close | Included PLAN:l.191. Same, not configurable | — |
| D3 | "Window Preview Keyboard Shortcuts": ⌘W, ⌘M, ⌘Q, ⌘H, with configurable keys. Dock previews need ⌘. Since 1.42.1 the switcher's own modifier also works while the switcher is open (KH L1418; CL L80–95) | ⌘ + key | CHANGED (n): bare W, M and Q (PLAN:l.194) | **Y-2** |
| D4 | Right-click menu: close, minimize, full screen, hide, quit, maximize, halves and quarters, bring to the current Space | — | Included PLAN:l.193, without snapping and Space moves | — |
| D5 | Snapping: fill halves and quarters, maximize | — | EXCLUDED §9 PLAN:l.418. The reason holds | — |
| D6 | Bring the window to the current Space (PA L175) | — | EXCLUDED §9 PLAN:l.419. **The reason is out of date** | Y-9 |
| D7 | "Quit app when closing last window", with lists of apps to quit or never quit (CON L46–49) | off | **MISSED**, and not in §9 (#1257, #1598) | Y-9 |
| D8 | Dock preview gestures: swipe on a card toward or away from the Dock to minimize, close and so on (CON L310) | on | EXCLUDED §9 PLAN:l.421 ("trackpad gestures"), with no reason | Y-9 |
| D9 | "Aero Shake" (CON L92) | none | EXCLUDED §9 PLAN:l.422, with no reason | Y-9 |

### E. Panel and placement

| # | DockDoor behaviour (setting label) | DockDoor default | Plan status | Finding |
|---|---|---|---|---|
| E1 | Panel level: status bar while "Show preview above app labels" is on, floating otherwise (CON L169; SPC L105) | on (status bar) | Included as S0-6 (PLAN:l.217, l.310) | Y-4, Y-6 |
| E2 | "Anchor preview position": placement is fixed from the icon at show time (CON L37; SPC L606–607) | on | CHANGED (n): the frame "is read live" (PLAN:l.215–216) | **Y-5** |
| E3 | "Window Buffer from Dock" (CON L33) | −20; −25 with magnification; −18 for a right Dock | CHANGED (n): a fixed 6 pt (PLAN:l.97, l.215) | Y-5 |
| E4 | Dock edge, magnification and auto-hide come from private CoreDock calls (DU) | — | CHANGED (y): from AX frames (PLAN:l.52–53, l.74) | — |
| E5 | "Prevent dock hide" while the preview is hovered. DockDoor listens to the Dock process and posts mouse-moved events to it. It does this only when auto-hide is on and it may post events (CON L38; SPC L195–238) | on | CHANGED (y): the Dock is not kept revealed (PLAN:l.218–219). This is right (#1137, #1222, #1247, #391) | — |
| E6 | The preview appears on the Dock's display | — | Included S0-12, M13 | — |
| E7 | "Lock Dock to Screen" (LOCK, an active tap) | off | EXCLUDED §9 PLAN:l.422, with no reason | Y-9 |
| E8 | "Space for a Custom Dock" (screen reservation) | off | N/A | — |

### F. Capture and data (Advanced › Preview Quality, Performance Tuning, Live Preview)

| # | DockDoor behaviour (setting label) | DockDoor default | Plan status | Finding |
|---|---|---|---|---|
| F1 | Every still thumbnail comes from `CGSHWCaptureWindowList`, on-screen windows included, and has since v1.5 (2024-12-30). There is no `SCScreenshotManager` path. SCK is used only to list windows and for live streams (WU L505–560; LWC L233) | — | CHANGED (y, Q3): private capture for minimized and other-Space windows, SCK for the rest (PLAN:l.112, l.340) | Y-6, Y-7 |
| F2 | "Capture quality": nominal or best (CON L71) | nominal | Not specified | — |
| F3 | "Resolution scale" (CON L70) | 1 | Not specified | — |
| F4 | "Cache lifespan", a setting (CON L68) | 30 s | Included as a fixed 30 s (PLAN:l.226) | Y-7 |
| F5 | Window-change debounce | 0.3 s | Included PLAN:l.73 | — |
| F6 | At most 4 captures at once, with a 10 s timeout | 4 | Included: a cap of 4 (PLAN:l.112) and a 0.15 s AX budget (l.224) | — |
| F7 | Live preview in the Dock and the switcher, with stream keep-alive (CON L73) | off | EXCLUDED §9 PLAN:l.420. The reason holds | — |

### G. Dock clicks and Dock-icon gestures

| # | DockDoor behaviour (setting label) | DockDoor default | Plan status | Finding |
|---|---|---|---|---|
| G1 | "Dock Click Action": a click on the frontmost app's icon hides or minimizes it (CON L42–43; DO L1023–1108) | off (action: hide) | Included §4.9 (PLAN:l.242). Same default | Y-15 |
| G2 | "Restore all minimized" on click (CON L44) | on | Included PLAN:l.243. Same | — |
| G3 | "CMD+Right Click" quits the app; ⌥ forces it. The click is swallowed by an active tap (CON L45; DO L844–944, L1206) | on | EXCLUDED §9 PLAN:l.421, with no reason | Y-9 |
| G4 | Shift-click opens a new window. The click is swallowed and the app gets a synthetic new-window command (DO L1110) | always on, no setting | EXCLUDED §9 PLAN:l.421, with no reason | Y-9 |
| G5 | Dock icon scroll: activate or hide, media volume. The scroll is swallowed (CON L50, L63–64; DO L1216–1284) | off | EXCLUDED §9 PLAN:l.421, with no reason | Y-9 |
| G6 | Title-bar scroll gestures, through a global active scroll tap (CON L51–57; GES L98–107) | off | EXCLUDED §9 PLAN:l.421–422, with no reason | Y-9 |
| G7 | Trackpad swipe to open the switcher (GES) | off | EXCLUDED §9 PLAN:l.421 | Y-9 |
| G8 | Active-app indicator drawn over the Dock | off | EXCLUDED §9 PLAN:l.422, with no reason | Y-9 |

### H. Widgets and other surfaces

| # | DockDoor behaviour (setting label) | DockDoor default | Plan status | Finding |
|---|---|---|---|---|
| H1 | Media widget: Music and Spotify, other players through an adapter (CON L95; MR; CL L1753) | on | EXCLUDED §9 PLAN:l.414–416. The reason is correct; add the detail in Y-9 | Y-9 |
| H2 | Calendar widget, using EventKit (CON L97) | on | EXCLUDED. The reason is correct (a new permission) | — |
| H3 | Folder previews for Dock folders and stacks: sort, remember sort, hidden files (CON L98–103) | off | **MISSED** from both §1 (PLAN:l.80) and §9 | Y-9 |
| H4 | Cmd+Tab overlay | off | EXCLUDED §9 PLAN:l.417. The reason holds | — |

### I. App level

| # | DockDoor behaviour | Plan status | Finding |
|---|---|---|---|
| I1 | Backup & Restore | Included M34 | — |
| I2 | Permissions page (Accessibility, Screen Recording) | Included §4.7, H5 | — |
| I3 | Debug logging to a file | Included as counts-only diagnostics (PLAN:l.54, §4.15) | — |
| I4 | Import of another app's settings | EXCLUDED §9 PLAN:l.424 | — |
| I5 | AppleScript dictionary | EXCLUDED §9 PLAN:l.423 | — |
| I6 | Launch at login, menu bar icon, update channel, settings search and descriptions, support and Pro links | N/A (host level, or not about previews) | — |

---

## 2. Issue tracker

Ranked by comments + 2 × positive reactions. Skipped as not about previews: #257 (docs), #65 (icon), #89 and #133
(translation), #35 (Homebrew), #463 (hide at startup), #302 (a broken release), #448 (Windows-like defaults),
#111, #677 and #1103 (styling).

### Top issues by rank

| Issue | c / r | Topic | Plan coverage | Finding |
|---|---|---|---|---|
| #1254 | 8 / 17 | Switcher: a modifier for the alternate shortcut | Covered: the Snaptic switcher already has per-shortcut modifiers | — |
| #243 | 40 / 0 | Previews unstable | Partly: S0-3, M8–M9 and the 30 s health check cover lifecycle events, but nothing covers long runs | Y-4 |
| #297 | 38 / 0 | A sped-up Dock animation hides the preview early | Gap: S0-7 doesn't vary the auto-hide timing | Y-5 |
| #688 | 7 / 14 | Backup settings | Covered (M34) | — |
| #472 | 10 / 12 | The preview stays open after a fast move | Covered §4.4 (corridor and safety net) | — |
| #140 | 17 / 6 | The Dock's own app-name label overlaps the preview | Gap: S0-6 doesn't record the label | Y-4 |
| #967 | 28 / 0 | AppleScript crash (music widget) | Excluded with the widgets (§9) | — |
| #1001 | 22 / 3 | Frequent restarts needed | Partly (S0-3); no soak test | Y-4 |
| #9 | 25 / 0 | Apps on another Space have no previews | Covered (WindowGatherer and badges) | — |
| #21 | 23 / 0 | No preview for VS Code, Calendar, Finder | Partly (S0-1, S0-10); no named odd-app set | Y-4 |
| #895 | 16 / 3 | Teams shows an empty window | Gap | Y-3, Y-4 |
| #238 | 16 / 2 | Minimized windows show nothing unless previewed once | Covered by Q3's private capture and the last-seen cache | — |
| #382 | 13 / 3 | Calendar and Music previews | Excluded (§9) | — |
| #32 | 14 / 2 | Full-size preview when hovering a card | Not included, and not recorded | Y-9 |
| #31 | 17 / 0 | Minimized and hidden window previews | Covered (Q3) | — |
| #74 | 10 / 3 | A click sometimes fails to raise the window | Covered (`WindowManager.focus`, M16) | — |
| #625 | 16 / 0 | Switcher recency wrong within one app | N/A (DockDoor switcher) | — |
| #1054 | 16 / 0 | An empty placeholder remains after a window closes | Gap: no check before showing | Y-3 |
| #54 | 11 / 2 | A delay before previewing the next app | Gap: the plan swaps at once (PLAN:l.168) | Y-14 |
| #163 | 15 / 0 | Calculator and Photos not recognised | Partly (S0-1) | Y-4 |
| #248 | 11 / 2 | Bring the window forward while hovering its card | Not recorded | Y-9 |
| #277 | 15 / 0 | Preview on the wrong monitor | Covered: placement uses the item's frame (S0-12, M13) | — |
| #444 | 7 / 4 | Limit previews to the current Space | Gap | Y-3 |
| #483 | 13 / 1 | Wrong position after a fast hover | Partly (§4.1(4)); no settled frame | Y-5 |
| #932 | 15 / 0 | A Dock click minimizes a new window when the app had none | Gap | Y-15 |
| #1270 | 15 / 0 | Inconsistent preview sizes | Gap | Y-12 |
| #1374 | 3 / 6 | A delay before a Dock click minimizes | Gap | Y-15 |
| #354 | 8 / 3 | Keep the Dock from hiding while the preview is hovered | Deliberately not done (PLAN:l.219); the reason is right | — |
| #464 | 4 / 5 | Click an icon to hide or minimize | Covered §4.9 | — |
| #1222 | 2 / 6 | Keeping the Dock revealed resizes windows | Supports PLAN:l.219 | — |
| #580 | 13 / 0 | The last preview remains over a windowless app | Gap | Y-11 |
| #595 | 13 / 0 | Can't hide after several icon clicks | Gap | Y-15 |
| #779 | 11 / 1 | Minimized windows forgotten after inactivity | Gap: purging on sleep (PLAN:l.55) is right, but nothing re-captures minimized windows after wake | Y-4 |
| #1061 | 13 / 0 | Previews stop after a while | Gap: no soak test | Y-4 |
| #1288 | 3 / 5 | Keys W, Q, M, H in previews (shipped with ⌘) | Changed: the plan uses bare letters | Y-2 |
| #1394 | 7 / 3 | Apps that have quit remain listed | Gap | Y-3, Y-18 |
| #1405 | 3 / 5 | One entry for all tabs | Gap | Y-16 |
| #190 | 12 / 0 | Watching every mouse movement costs performance | Partly: the plan never says when pointer-moved events are watched | Y-14 |
| #355 | 12 / 0 | Pop-ups shouldn't be captured | Gap | Y-3 |
| #1377 | 12 / 0 | NoMachine: thumbnails multiply without end | Gap | Y-3, Y-4 |
| #1038, #399 | 12 / 0, 10 / 1 | Silent stops and crashes: after a Teams screen share, after going full screen on 26.0 | Gap | Y-4 |
| #17 | 11 / 0 | A preview appears after the pointer already left | Partly (§4.1(4)) | Y-14 |
| #299 | 11 / 0 | Poor behaviour with Stage Manager | Recorded only (S0-11, M20) | Y-8 |
| #506 | 7 / 2 | Previews appear under the Dock when it auto-hides | Gap | Y-5 |
| #520 | 11 / 0 | Previews stop appearing after a while | Gap | Y-4 |
| #660 | 5 / 3 | A default preview for windowless apps | Covered: our default (PLAN:l.183) | Y-11 |
| #714 | 5 / 3 | Sorting options, including creation time | Partly (Recent / Title) | Y-13 |
| #1024 | 11 / 0 | Teams leaves blank space in the preview | Gap | Y-4 |
| #1034 | 11 / 0 | Ghostty tabs listed as separate windows | Gap | Y-16 |
| #1071 | 9 / 1 | "Current Space only" didn't apply to the Dock | Gap | Y-3 |
| #550 | 10 / 0 | A left Dock sometimes fails | Covered (S0-2 includes left and right) | — |
| #702 | 8 / 1 | Previews on click, as on Windows | Not recorded | Y-9 |
| #934 | 10 / 0 | A swipe on a card hides instead of minimizing | Excluded (gestures) | — |
| #485 | 4 / 4 | A fast move up leaves the preview open | Covered §4.4 | — |
| #855 | 8 / 2 | Drag a card to another Space | Excluded (Space moves) | Y-9 |
| #991 | 16 / 0 | Finder freezes when it has several windows | Covered: AX budget and back-off (PLAN:l.224) | — |
| #813 | 14 / 0 | Illustrator lags with spacebar panning while DockDoor runs | Covered: our taps exist only while needed (PLAN:l.196–197, l.244) | — |
| #335 | 10 / 0 | No preview when the app is minimized | Covered (Q3) | — |

### Focus areas

| Area | Issues | Plan coverage | Finding |
|---|---|---|---|
| macOS 26/27, taps and input | #1589 (clicks stop working system-wide), #1655 (all input blocked until restart on 27.0.1: WindowServer refuses the app's event posting, and every event through its active taps is dropped), #1637 (crash in the event tap on 27.0.1), #800 (keyboard monitoring blocked on 26) | Gap: only the listen-only click tap is covered (PLAN:l.408). The active key tap is not | Y-4 |
| macOS 26/27, synthetic events | #1634, #1648 (posted user activity every ~8 s kept the display awake) | Covered: no synthetic events (PLAN:l.50–51), S0-8, M21 | — |
| macOS 26/27, other | #993 (previews broken on 26.2), #1609 (Dock indicator geometry on 27), 1.40.1 hotfix (clicks inside previews ignored on 26.3+) | Gap: first-click delivery | Y-4 |
| Multi-display | #277, #706, #1174, #77, #496 (open: monitor number), #1715 (open: Sidecar) | Covered (S0-12, M13), except Sidecar and display badges | Y-4, Y-17 |
| Auto-hide Dock | #506, #297, #200 (preview not clickable with auto-hide), #136 (preview half behind the Dock), #364, #388, #1137, #1247 | Partly | Y-5 |
| Stage Manager | #299, #459, #593, #609 (tilted thumbnails), #768, #772, #807, #1067, #1348 | Recorded only | Y-8 |
| Full screen | #425, #756, #1720 (open) (Chrome in full screen split, stretched or with a black bar), #491, #1147 (the preview comes back after clicking a full-screen app's icon) | Partly (S0-4, S0-6, M14) | Y-4 |
| Spaces | #9, #444, #466, #767, #834, #884, #1071, #1525 (open: windows vanish on a Space change), #1699 (open: highlight rather than hide) | Partly | Y-3, Y-17 |
| Performance and memory | #190, #1404 (50 % CPU while idle), #991, #813 | Covered (S0-14, LRU budget, scoped taps) | — |
| Won't dismiss / re-opens | #472, #485, #538, #612, #1199, #1147 | Partly | Y-14 |
| Previews die | #243, #230, #397, #399, #520, #1001, #1061, #1111 (after sleep or a light/dark switch), #1184 | Partly | Y-4 |
| Privacy indicator | #245 (prompts again on 15), #795 (purple dot while using it; the maintainer's only fix is a longer cache), #1120 (dot in full screen; reply "disable screen recording"), #1385 (open: capture icon inside the previews with live preview on) | Gap | Y-7 |
| Odd windows | #330 (ghosts), #355, #426, #467 (panels and layers), #557 (Finder desktop window), #961 (open: non-standard layers), #75 (Chrome PWAs), #247 (iOS apps) | Gap | Y-3, Y-4 |
| Open requests | #1225 (⌘⇥ while hovering), #1406 (switcher open delay), #1554 (app blocklist), #1562 (modifier-click minimizes all), #1563 (always show mass-action buttons), #1593 (preview on click), #1598 (quit on last window), #972 (oldest-first sort) | Mixed | Y-2, Y-3, Y-9, Y-10, Y-13, Y-15 |

---

## 3. Window Switcher comparison (§4.11)

| DockDoor switcher feature | Snaptic switcher today | Recommendation |
|---|---|---|
| Release to select | `releaseToSwitch` | Have |
| Open delay; a quick tap switches without drawing | Fixed 70 ms; a quick tap switches (SW `SwitcherController.swift` L241–246) | Have. DockDoor #1406 asks for an adjustable delay; not needed |
| Several shortcuts, each with its own scope and modifier (DockDoor 1.42.0) | Up to 9 shortcuts; scopes `allWindows`, `activeApp`, `currentScreen`; Spaces all, current or others | Have |
| Search, with a search key | Fuzzy search (S or /) | Have |
| Hover selects | `selectOnHover` | Have |
| Windowless apps | `includeWindowlessApps` | Have |
| Close, minimize, full screen, hide, quit keys | W, M, F, H, Q while the switcher is open | Have. Bare letters are fine here: the user opened the switcher and holds the modifier |
| Full-screen app blocklist | `passthroughBundleIDs`, `passthroughOnlyWhenFullscreen` | Have |
| Replace ⌘⇥ | `commandTabTakeover` | Have |
| Private windows | `protectPrivateWindows`, `privateBundleIDs` | Have (DockDoor has none). Must carry over to the Dock (Y-1) |
| Thumbnails of minimized and other-Space windows | App icon | **Add** (already in the plan, PLAN:l.258–259) |
| Cached thumbnails across openings | No | **Add** (already in the plan, PLAN:l.260) |
| "Sort minimized/hidden to end" | No | **Add**: one rule in `WindowCatalogRules`, shared by both modules (Y-13) |
| Small-window, pop-up and title filters | `excludedBundleIDs` only | **Add**: the inclusion rules from Y-3, shared. The K4 "current inclusion cases still hold" test (PLAN:l.336) guards the switcher |
| Display badge on multi-display setups (DockDoor #496, open) | No | **Add if cheap**: public `NSScreen` data. Leave the Space number for later (it needs a new Space-index symbol) |
| Sort by creation, screen position, title, app name | Recency only | Leave out of 0.5; recency is the switcher's model |
| Vim keys (h j k l) | No | Leave out: H already means Hide |
| Mouse follows focus (warps the pointer) | No | Leave out: moving the pointer for the user goes against the no-synthetic-input rule |
| Trackpad swipe to open | No | Leave out: needs a gesture tap (GES) |
| Placement offset, icon size, monochrome icons, scroll direction, "ignore screen limit" | Partly (`showOnScreen`, `autoSize`, `thumbnailSize`) | Leave out (styling) |
| Live previews, snapping, Space moves, Cmd+Tab overlay | No | Leave out (§9) |

---

## 4. Findings

### Blockers

### Y-1 · Blocker · §2, §4.2, §4.6, §4.10 · Private windows leak into Dock cards and the shared cache

**Finding.**

- The switcher protects private windows, but only inside its own list-building code:
  - windows of apps in `privateBundleIDs` are never captured and show no title;
  - private-browsing windows show "Private window";
  - a browser window whose title can't be read is treated as private.
- The plan moves capture and the thumbnail cache into the shared `WindowServices` (PLAN:l.108, l.226–227).
- But `WindowCatalogRules` covers only "which windows count, recency merge, badge state, cache freshness, LRU
  budget" (PLAN:l.104), and the plan never mentions private windows.

As drafted, Dock cards would capture and show a private-browsing window or a protected app. They would also show
its title (PLAN:l.176) and read it to VoiceOver (PLAN:l.253). The capture would then sit in the cache the switcher
reads. That is a privacy regression of a shipped behaviour. DockDoor has no such protection, so parity with
DockDoor doesn't excuse it.

**Evidence.**

- The switcher marks private windows only while building its own list (SW `SwitcherController.swift` L251, L320–335).
- `isPrivate` blocks capture (SW `WindowManager.swift` L24, L34).
- `ThumbnailStore` captures through SCK (SW `ThumbnailStore.swift` L150).
- The Kit already has the window rule, `PIPPrivacy.isPrivateWindow`, and the app rule, `isCaptureAllowed`
  (PIPK L556–566).
- PLAN:l.104, l.108–112, l.176, l.226–227, l.253, l.336.

**Proposal.**

1. Move the private-window marking into `WindowCatalogRules` (Kit), reusing `PIPPrivacy.isPrivateWindow` and
   `Config.bundleID(_:matchesAny:)`. Apply it in `WindowServices` before any capture or cache write, so both modules
   share one rule.
2. A private item in a Dock card is never captured. It shows the app icon and "Private window" (or the app name for
   a protected app). Its VoiceOver label carries no title.
3. The cache refuses private ids, and it drops an entry when its window turns private (for example, a title change
   to a private marker).
4. Dock Previews follows the switcher's "Protect private windows" setting and app list. Say so on the Dock Previews
   page.
5. Add K4 cases and a Blocker manual check: a Safari or Chrome private window on hover shows the icon and "Private
   window", and no cache entry appears in `dock status --json`.

### Majors

### Y-2 · Major · §4.3 · Bare W, M and Q can close windows or quit apps while the user types

**Finding.** In the plan, bare W closes a window, M minimizes and Q quits the app while the pointer is in the panel
(PLAN:l.194), with the keys on by default (l.197). The keys are armed by pointer position alone.

This is a real hazard. A user who leaves the pointer resting over a preview and goes on typing in the frontmost
app loses those letters, and a "q" quits the hovered app. Return and the arrows are swallowed the same way.

DockDoor needs ⌘ in Dock previews. §1 records this correctly (PLAN:l.77), and §4.3 departs from it without a reason.
The switcher's bare letters are a different case: there the user opened the switcher on purpose and holds its
modifier.

**Evidence.** KH L1418. CL L80–95: 1.42.1 notes that in Dock previews only ⌘ worked, and it added the switcher's
modifier for use inside the switcher only. Issue #1288 (a request for W, Q, M, H), shipped with ⌘. Open #1225: a
request to let ⌘⇥ work while hovering. PLAN:l.77, l.194–197, l.383 (M23 tests bare letters).

**Proposal.**

1. Destructive keys need ⌘: ⌘W closes, ⌘M minimizes, ⌘H hides, ⌘Q quits the app. This matches macOS and DockDoor.
2. Esc, the arrows and Return work only after the pointer has moved inside the panel since it appeared.
3. Every other key, plain letters included, passes through untouched, and ⌘⇥ always passes through.
4. Update M23 to match, and add "typing with the pointer parked over the panel reaches the frontmost app".

### Y-3 · Major · §4.2, K4 · Which windows count is undefined, and DockDoor's filters and fixes are missing

**Finding.** K4's "inclusion" (PLAN:l.104, l.336) is never spelled out. DockDoor's catalogue and its bug history
show the rules a Dock preview needs.

Rules the plan has none of:

- a current-Space or current-display filter;
- app or title exclusions;
- a minimum window size (DockDoor hides windows under 100 px);
- notification-style pop-ups and panels kept out of the list.

The plan also doesn't check entries before showing them. Without that check, a window that closed or an app that
quit still shows a card ("ghosts").

**Evidence.**

- CON L122–123, L281–282.
- CAT L1821–1824.
- CL L420 (1.40.0, meeting-reminder pop-ups).
- WDS L229–345 (per-app quirks).
- Issues:
  - filters: #444, #1071, #767, #1699 (open), #1554 (open);
  - pop-ups and panels: #355, #467, #961 (open);
  - Finder's desktop window: #557;
  - ghosts: #330, #1054, #1394, #1377;
  - Teams: #895.
- SW `Settings.swift` (`excludedBundleIDs`, scope, Spaces).

**Proposal.**

1. Write the rules into K4. Count only standard windows and titled dialogs. Leave out:
   - floating panels, system dialogs and notification-style pop-ups;
   - windows smaller than 100 × 100 pt;
   - Finder's desktop window;
   - windows whose id or pid is gone.
2. Re-check the shown list against live window ids when the panel opens and on each refresh, and drop dead
   entries in place.
3. Add Settings "Only this Space" and "Only this display" (both off, as in DockDoor), and an "Apps to leave out"
   list (Advanced).
4. Keep the switcher's existing cases green (the K4 "Done when" already says so), and let it pick up the size and
   pop-up rules.

### Y-4 · Major · §5 · S0 misses the failure modes behind DockDoor's worst bugs

**Finding.** S0 covers lifecycle events and idle sleep well, but six things that broke DockDoor in 2026 have no row.

1. **An active tap while event posting is refused (26/27).** On 27.0.1, WindowServer refused DockDoor's event
   posting, and every event that passed through its active taps was dropped. Input was dead system-wide until a
   restart. Snaptic's `HotkeyTap` is an active tap (SW `HotkeyTap.swift` L60–63), and `DockKeys` uses it. The plan's
   risk row covers only the listen-only click tap (PLAN:l.408). Also unknown: whether the raise path's
   `SLPSPostEventRecordTo` (PLAN:l.268) triggers the refusal.
2. **First click in a non-activating panel on 26.3+.** DockDoor 1.40.1 was a hotfix because clicks inside previews
   were ignored. Our panel is non-activating and never key (PLAN:l.74).
3. **Long runs.** Previews died after sleep plus a hung app (1.40.5), after a light/dark switch (#1111), after
   another app's screen share (#397), after full screen on 26.0 (#399), or "after a while" (#1061, #520, #1001,
   #1184).
4. **The Dock's app-name label** drawn over the panel (#140). DockDoor raised its level to the status bar to clear it.
5. **Odd apps and windows:** Teams (#895, #1024), NoMachine phantom windows (#1377), non-standard layers (#961),
   Finder's desktop window (#557), Chrome full screen (#425, #756, #1720), PWAs and iOS apps (#75, #247),
   Calculator and Photos (#163), Sidecar as a display (#1715).
6. **The preview returning after a click on a full-screen app's icon** (#1147). Also, minimized windows forgotten
   after sleep (#779). Purging on sleep (PLAN:l.55) is right, but S0 should record whether a minimized window can be
   recaptured after wake.

**Evidence.** Issues #1589, #1655, #1637, #800. CL L367–372 (1.40.1), L241–276 (1.40.5), L409 (1.40.0). The 1.40.1
compare touches WDC and the card grid view. The issues are listed in the items above. PLAN:l.303–320, l.408.

**Proposal.** Add these rows:

| New row | Check | Blocker |
|---|---|---|
| S0-17 | 27.2: refuse Snaptic's event posting (or revoke Accessibility) while `HotkeyTap` and the `DockKeys` tap are on. Record that input still flows, how fast the tap is dropped, and whether `SLPSPostEventRecordTo` triggers "prohibited from synthesizing events" | yes |
| S0-18 | 26.3+ and 27.2: the first click on a card in the non-activating panel acts at once | yes |
| S0-19 | An 8-hour soak with sleep and wake, a light/dark switch, a display change, another app's screen share, full-screen enter and exit, and an app hung across sleep. Counters for re-attach and hover-to-show | yes |

Extend existing rows:

- **S0-6:** record whether the Dock's name label draws over the panel at each level.
- **S0-10:** add the odd-app set above, and recapture of minimized windows after wake.
- **S0-13:** add "click a full-screen app's icon while hovering".

### Y-5 · Major · §4.5, S0-7, M12 · Placement reads a live, magnified frame, and auto-hide timing goes untested

**Finding.** "Magnification is handled because the frame is read live" (PLAN:l.215–216) is the wrong way round.
With magnification on, the hovered item's AX frame grows and moves while the pointer is on it, then shrinks as the
pointer moves toward the panel. Live reads make the panel jump, and the corridor (l.203–204) moves under the
pointer.

DockDoor fixes the position from the icon at show time ("Anchor preview position", on by default). It also widens
its gap from the Dock when magnification is on, and changes it for a right Dock.

Its top auto-hide bugs come from Dock animation timing:

- a sped-up animation (`autohide-time-modifier`) hid previews early (#297, 38 comments);
- previews appeared under the Dock (#506) or half behind it (#136);
- previews weren't clickable (#200);
- a fast hover put the panel in the wrong place (#483).

S0-7 (PLAN:l.311) tests only "pointer from the Dock into the panel", at default timing.

**Evidence.** CON L33, L37. SPC L606–607. Issues #297, #506, #136, #200, #483, #364. PLAN:l.96–97, l.203–204,
l.215–219, l.311, l.372. The plan is right not to keep the Dock revealed (PLAN:l.218–219): DockDoor's version
resized windows and broke full screen (#391, #1137, #1222, #1247).

**Proposal.**

1. Compute placement once, from a settled frame: two equal reads 1–2 frames apart, or the at-rest frame recorded
   before magnification. Keep it, and keep the corridor on it, until a swap.
2. Derive the gap from the at-rest Dock thickness, so a magnified icon never covers the panel.
3. S0-7 adds:
   - `autohide-delay` 0;
   - `autohide-time-modifier` 0 and 0.15;
   - magnification on with a large size;
   - recording the `AXList` and item frames at rest and magnified.
4. M11 and M12 add "magnified: the panel doesn't move while the pointer crosses into it".

### Y-6 · Major · §1 · §1 misdescribes DockDoor in eight places

**Finding.** §1 is the implementers' only view of DockDoor. These rows are wrong or incomplete.

| PLAN line | Plan says | DockDoor 1.42.4 does |
|---|---|---|
| l.69 | The 5 s health check re-attaches when the Dock's pid changes | It also re-checks that the `AXList` element is still valid, and re-enables its Dock event tap (DO). S0-3 should cover an `AXList` rebuilt under the same pid, for example after a display change |
| l.71 | "ScreenCaptureKit, then AX, then a brute-force private AX lookup" | CGWindowList, SCK shareable content and AX, then the remote-token lookup, then per-app quirks (WU L296–298; WDS L229–345) |
| l.72 | Private capture for minimized and other-Space windows | `CGSHWCaptureWindowList` is its only still-capture path, for every window, and has been since v1.5 (2024-12-30). SCK only lists windows and runs live streams (WU L505–560; LWC L233). The purple indicator still shows (#795) |
| l.74 | "Status-bar level" | Status bar only while "Show preview above app labels" is on (the default); floating otherwise (SPC L105). The full-size preview sits just below floating |
| l.77 | Card actions | Right about ⌘. It leaves out that middle-click is configurable, and that card swipe gestures are on by default (CON L310, L337) |
| l.78 | "⌘-right-click quits, Shift-click opens a new window, click restores minimized windows; scroll gestures off" | Its Dock tap is an **active** tap that swallows clicks and scrolls (DO L844–944). ⌘-right-click quit is on by default (⌥ forces). Shift-click is always on and sends a synthetic new-window command. Dock-click hide is off by default; restore-all is on |
| l.80 | Widgets: Media and Calendar | Also Folder previews (off by default). For players other than Music and Spotify, Media uses an adapter that runs `/usr/bin/perl` with a bundled framework to get around MediaRemote's entitlement check (MR; CL L1753) |
| l.84–86 | "Never post synthetic events; tear taps down completely" (lessons) | Fair lessons, but say DockDoor breaks them. It posted a periodic activity canary (#1634, #1648). It posts mouse-moved events to the Dock for "Prevent dock hide" (on by default; SPC L195–238). Its key tap is a session-wide active tap that is always on (KH L573–575). Users saw input lag (#813) and input loss (#1655) |

**Evidence.** As in the table.

**Proposal.**

- Correct those rows in place.
- Add a §1 row for "Panel level" and one for "Dock preview gestures".
- State in the lessons that DockDoor posts synthetic events and keeps active taps. That way implementers read the
  plan's rules as deliberate differences, not as parity.

### Y-7 · Major · §4.6, §4.7, S0-4 · The screen-recording indicator and capture pacing are not addressed

**Finding.** Every capture can light the purple screen-recording indicator, and DockDoor users complained about it
repeatedly. When DockDoor moved to private capture (v1.5), the indicator kept appearing (#795, macOS 15, 2025-10).
The maintainer's only remedy was a longer cache lifespan, and DockDoor exposes the cache lifespan as a setting.

The plan uses SCK for on-screen windows (PLAN:l.112, l.340), refreshes entries older than 30 s whenever they're
shown (l.226), and never mentions the indicator. On 15, a Screen Recording grant can also re-prompt (#245).

**Evidence.** Issues #245, #795, #1120, #1385 (open), and the #238 thread (a branch built to test private capture
against "the purple warning"). CON L68. WU L505–560. SW `ThumbnailStore.swift` L150. PLAN:l.112, l.226, l.308, l.314.

**Proposal.**

1. **S0-4 / S0-10:** record, on 27.2 and 15, whether the indicator lights for:
   - SCK `SCScreenshotManager` stills;
   - `CGSHWCaptureWindowList` stills;
   - `SCShareableContent` listing alone.
2. Prefer the quieter path within the 0.4 rules, since Q3 already allows the private one.
3. Capture only on a window-change event or a stale entry, never on every hover. Rate-limit refreshes per window,
   for example at most once per 30 s, plus once after an AX change.
4. Add a "Known limitations" line in D1: "macOS shows the screen-recording indicator while thumbnails refresh; turn
   off Thumbnails to avoid it."

### Y-8 · Major · S0-11, M20 · Stage Manager has no defined behaviour

**Finding.** Stage Manager is one of DockDoor's most repeated complaints (nine issues): previews break, render
oddly or go missing, and windows in the strip come out tilted. The plan only records it (S0-11, not a Blocker;
PLAN:l.315), and M20 accepts "usable or recorded as a limitation" (l.380). Nothing says what a card shows for a
window that isn't in the active stage, or whether hover still works.

**Evidence.** #299, #459, #593, #609 (tilted thumbnails), #768, #772, #807 (26: no previews in Dock or switcher),
#1067, #1348.

**Proposal.**

1. Make S0-11 decide the behaviour.
2. Record, for windows in the strip and in other stages:
   - the AX frames;
   - the `CGWindowList` bounds;
   - what each capture path returns (an upright full-size image, or the tilted strip tile).
3. Write the rule into K4. Show an upright capture if one exists, else the last-seen thumbnail, else the app icon.
   Never show a tilted or tiny strip tile.
4. Raise M20 to B, with "previews readable or text-only, never stuck".

### Minors

### Y-9 · Minor · §9 · One reason is wrong, eight are missing, and five exclusions aren't recorded

**Finding and evidence.**

- **Space moves (PLAN:l.419), "calls that recent macOS restricts": partly out of date.**
  - On 14.5 the direct `SLSMoveWindowsToManagedSpace` was restricted. A compat-id workaround existed (Amethyst
    #1643, Hammerspoon #3636, yabai #2240).
  - On 15 the calls became no-ops; yabai needs SIP off (yabai 7.1.2 changelog, #2324, #2331, #2484; Amethyst #1662).
  - On 26, an undocumented ObjC class is reported to work with SIP on (Hammerspoon PR #3889, open, tested on 26.5).
    DockDoor uses the bridged class (PA L175).
  - 27 is unverified.
  - Reword: "Works only through an undocumented ObjC class on 26+, not on 15, and that class can't get the 0.4
    encoding check as a C symbol. Candidate for later."
- **Media (PLAN:l.414–416): correct.** mediaremoted has checked entitlements since 15.4 (CL L1753). Add: "DockDoor
  gets around this for other players by running `/usr/bin/perl` with a bundled framework, which is outside
  Snaptic's rules."
- **Liquid Glass (PLAN:l.425): correct.** `NSGlassEffectView` is macOS 26.0+ and needs the 26 SDK. Builds against
  the 15 SDK keep the earlier look.
- **No reason given (PLAN:l.421–422):**
  - ⌘-right-click Quit, Shift-click New Window and Dock icon scroll need a tap that swallows the Dock's click or
    scroll. Shift-click also needs a synthetic ⌘N.
  - Title-bar scroll and Aero Shake need a global active tap and move other apps' windows.
  - Dock locking needs an active tap and synthetic events (LOCK).
  - The active-app indicator draws over the Dock and depends on Dock geometry that broke on 27 (#1609).
  - Trackpad gestures, meaning the swipe to open the switcher, need a gesture tap (GES).
  - Card swipe gestures (D8) would fit our rules if read from the panel's own scroll events. Record them as scope,
    not as a rule.
- **Not recorded anywhere (add to §9):**
  - Click or modifier-click to preview (A2; #702, #1593 open). Click modes need a swallowing tap. "Only while ⌥ is
    held" fits the rules; record it as a later candidate.
  - Hover actions: full-size preview, or bring forward on card hover (A8; #32, #248).
  - Quit the app when its last window closes (D7; #1257, #1598).
  - Open a new window for windowless apps (B9): needs a synthetic ⌘N.
  - Folder previews (H3): reading the contents of Downloads, Documents or Desktop needs a new folder permission.

**Proposal.** Update §9 with the reasons above, and mirror the folder-preview row in §1 (Y-6).

### Y-10 · Minor · §4.2 · Header lacks Minimize All and Close All

**Finding.** DockDoor's header shows "Close All" and "Minimize All" by default, and users ask for them to always
show. Ours has Hide and Quit (PLAN:l.180). Minimize All is one AX loop over windows we already hold.

**Evidence.** CON L111. Issues #1563 (open), #1562 (open, modifier-click to minimize all).

**Proposal.** Add a Minimize All header button. Put Close All in the header's right-click menu, so a stray click
can't close everything. Add both to M17.

### Y-11 · Minor · §4.2 · The windowless-app default differs from DockDoor without a reason

**Finding.** DockDoor's Dock previews hide windowless apps by default. Ours show a "No open windows" card
(PLAN:l.183, l.280). Ours is the better default (#660 asked for it), but the plan gives no reason. DockDoor's bug
#580 shows the failure to test: the previous app's preview stayed over a windowless app.

**Evidence.** CON L159, L147. Issues #580, #660.

**Proposal.** Record the reason. Add a K3 case: hovering a windowless app swaps to its compact card and never keeps
the previous app's cards.

### Y-12 · Minor · §4.2 · Card size, aspect and rows are underspecified

**Finding.**

- No default card size is named (PLAN:l.179); DockDoor's is 300 × 187.5.
- "Height follows the thumbnail's aspect, capped" is DockDoor's "Dynamic sizing", which is off there by default.
  Mixed heights caused #1270 and #1587, and tiny windows caused #110.
- A bottom Dock wraps into more rows (l.181), while DockDoor keeps one row by default. Users asked to get one row
  back (#1118); #84 asked for a row width cap.
- Side Docks have no column count; DockDoor uses 2.

**Evidence.** CON L30–32, L256. Issues #1270, #1587, #110, #1118, #84.

**Proposal.**

1. Medium (280 pt) is the default.
2. Cards are a fixed 16:10 frame, with the thumbnail letterboxed inside.
3. A bottom Dock gets one row, then "+N more". Side Docks get 2 columns.
4. Add these to K2's tests.

### Y-13 · Minor · §4.2 · Sort options: no "minimized and hidden last"

**Finding.** Ours sorts by Recent or Title (PLAN:l.178). DockDoor adds creation, screen position and app name, and
has "Sort minimized/hidden to end". Of these, minimized-last is the one users miss most, and it is one rule in
`WindowCatalogRules`.

**Evidence.** CON L124, L131. Issues #714, #972 (open).

**Proposal.** Add "Minimized and hidden last" (off) for both modules. Leave the other orders out.

### Y-14 · Minor · §4.1, §4.4, K3 · Hover timing rows that DockDoor needed fixes for

**Finding.**

- The K3 race table (PLAN:l.335) doesn't list the timing bugs DockDoor fixed:
  - a pending show firing after the pointer left (#17);
  - a Dock click not resetting the hover timer (#1199);
  - the preview staying or re-opening after an icon click (#538, #612, #1147).
- The instant swap (l.168) is the opposite of #54 (a delay before the next app) and of DockDoor's default. Say why.
- §4.4 doesn't say that pointer-moved monitoring exists only while the panel is shown or a show is pending. #190:
  watching every mouse movement cost DockDoor performance.
- The fade time is unspecified; DockDoor's is 0.4 s.

**Evidence.** CON L35–36, L87–89. Issues #17, #54, #190, #538, #612, #1147, #1199.

**Proposal.**

1. Add K3 rows:
   - a pending show is cancelled when the pointer leaves the Dock's frame;
   - a mouse-down on the Dock cancels the pending show and resets the timer;
   - no re-show for the same item until the selection changes or the pointer leaves and re-enters.
2. Give the swap's reason ("moving along the Dock shouldn't wait"), and keep it.
3. State that the pointer monitor's lifetime matches the panel's.
4. Fade 0.15–0.2 s, none with Reduce Motion.

### Y-15 · Minor · §4.9 · Dock click rules miss DockDoor's bug fixes

**Finding.** DockDoor's Dock-click feature needed fixes for:

- minimizing a new window that the Dock click itself had just opened (#932);
- hiding failing after several clicks (#595);
- clashes with windows the user minimized or closed by hand (#828);
- a preview click minimizing all windows (#1046).

DockDoor's rule acts only when the app was frontmost at hover time and had windows (DO L1023–1108). Users also asked
for a minimize delay (#1374). The plan's resolver (PLAN:l.100, l.242–243) states none of these conditions.

**Evidence.** CON L42–44. DO L1023–1108. Issues #932, #595, #828, #1046, #1374, #1562 (open).

**Proposal.**

1. The Dock click resolver acts only if:
   - the app was frontmost at mouse-down, sampled before the Dock acts;
   - it had at least one visible window at mouse-down;
   - the mouse-up lands on the same item.
2. Restore-all acts only when every window was minimized at mouse-down.
3. Add K3 cases for each.

### Y-16 · Minor · §4.2, S0-2, S0-10 · Native tabs and app instances

**Finding.** In some apps every tab is its own AX window. Ghostty tabs showed as separate windows (#1034), and users
asked for one entry per tab group (#1405, shipped as "Collapse native tabs", off). DockDoor also groups several
instances of one app under one icon by default. The plan resolves the pid (S0-2) but doesn't say what a duplicate
app's icon shows.

**Evidence.** CON L164–165. DO L610–730. Issues #1034, #1405.

**Proposal.**

- S0-10 records the tab-window behaviour of Ghostty, Finder and Terminal.
- K4 states the rule. Default: one card per window, as macOS's Window menu lists them.
- S0-2 decides whether a duplicate app's icon shows only its own instance's windows. That is better than
  DockDoor's grouping, because the Dock shows separate icons.

### Y-17 · Minor · §4.2 · No display badge or Space number

**Finding.** Our only Space marker is "Other Space". DockDoor offers a Space number (off), and open requests ask for
the monitor number (#496) and for highlighting the current Space's windows instead of hiding the others (#1699).

**Evidence.** CON L224. Issues #496 (open), #884, #1699 (open).

**Proposal.** On setups with more than one display, add a display badge (public `NSScreen` name) to both modules.
Record the Space number as later, since it needs a new Space-index symbol.

### Y-18 · Minor · §4.4 · Dismissal when the hovered app quits or its window closes elsewhere

**Finding.** DockDoor closes the preview when the app terminates ("Keep preview when app terminates" is off by
default). Our dismissal list (PLAN:l.208–209) has no "hovered app quit" reason, and nothing says that a window
closed elsewhere leaves the panel. Leftover cards for apps that have quit were a DockDoor bug (#1394).

**Evidence.** CON L138. Issue #1394.

**Proposal.** Add the dismiss reason "hovered app terminated". When a window closes elsewhere, its card is removed
in place, and the panel hides or shows the windowless card when the last one goes. Add K3 cases.

### Y-19 · Minor · §4.11 · Switcher: take the cheap shared wins, and record what's left out

**Finding.** The shared service makes three DockDoor switcher features nearly free:

- the inclusion rules (Y-3);
- minimized-last sorting (Y-13);
- a display badge (Y-17).

The plan lists only thumbnails and the cache (PLAN:l.257–260). Section 3 above shows the rest of DockDoor's switcher
is already matched or deliberately not wanted.

**Evidence.** Section 3. PLAN:l.20–24, l.257–260.

**Proposal.**

1. Add the three shared rules to §4.11, with the K4 guard that the switcher's current inclusion cases still hold.
2. Record in §9:
   - Vim keys (H conflicts);
   - mouse follows focus (it moves the pointer for the user);
   - the trackpad swipe trigger;
   - extra sort orders.
