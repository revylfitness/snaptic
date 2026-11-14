# 0.5 Dock Previews — S0 results

Host: macOS 27.2 (26B123), Apple Silicon (M4 Pro). Displays: an external 2560 × 1440 main display at 1 px per pt,
frame (0, 0), visible frame (0, 88, 2560 × 1322), plus the built-in 1728 × 1117 pt display at 2 px per pt to its
left, frame (−1728, 323). No 5K display. Dock: bottom, no auto-hide, no magnification, tile size 62. Spaces: one
desktop Space per display ("Displays have separate Spaces" is on), no full-screen Spaces, Stage Manager off.
Snaptic was running and wasn't touched. No other Dock preview tool was installed. The harness ran under the host
terminal app's grants: Accessibility trusted, Screen Recording preflight true.

The harness was a set of throwaway Objective-C tools in `/tmp/s0-dock/` (not committed), built with `clang`. They
read the Dock's AX tree, `CGWindowListCopyWindowInfo` and SCK, resolve the §4.12 symbols with `dlsym` and `dladdr`,
and draw the two-colour 4 × 4 pattern in windows of their own. S0-23 and S0-26 use child processes of the harness
as the target app. The harness never moved the pointer, posted events, installed a tap, wrote defaults, called a
setter, or touched another app's windows. Other apps' windows were captured only to record success, size, scale
and whether a 16 × 16 greyscale downsample is blank. No image was kept and no title was printed, and the results
below give app and window classes, not names.

Run on 2026-11-13, with the owner using the Mac, so only rows that don't disturb them ran. **No macOS 15 VM is
available, so the 15 leg of every row is an owner check before R (§5).** "Carried" means the row or leg needs the
owner's hands, their permission for a scripted change, or hardware. Each one is listed under **Carried forward**,
with the item it gates, and grouped under **Owner session**.

| # | Result | Verdict |
|---|---|---|
| S0-1 | Dock pid's AX app has one child, an `AXList` (`AXHorizontalOrientation`), frame (219, 1348, 2122 × 82) in AX coordinates. 35 items: 28 `AXApplicationDockItem`, 2 `AXSeparatorDockItem`, 4 `AXSpacerDockItem`, 1 `AXTrashDockItem`. While our window was minimized, an `AXMinimizedWindowDockItem` appeared 556 ms after `miniaturize:` (no `AXURL`; actions `AXPress`, `AXShowMenu`). All 28 app items carry a file `AXURL`. The 19 with `AXIsApplicationRunning` = 1 all resolve by URL, one to one, to the 19 running regular apps. Two tiles with `AXIsApplicationRunning` = 0 have a URL that matches a running app's bundle, so the match must require `AXIsApplicationRunning` = 1. Item frames are 66 × 82 at y 1353, so they reach 5 pt below the list's bottom edge: containment uses the union of item frames, not the list frame. `AXSelectedChildren` is readable and empty at rest. No folder or URL tiles were in the Dock. | **Pass** on 27.2. 15 leg and folder/URL tiles carried |
| S0-2 | Needs hover, orientations, magnification and auto-hide. | Carried |
| S0-3 | Needs `killall Dock`, sleep, lock, fast user switching and display changes. | Carried |
| S0-4 | Our patterned window: signature **0.00 %** on screen at 1x (128 × 128) and 2x (256 × 256), app hidden, ordered out without animation, and never ordered in; **0.30 %** minimized (titled, 256 × 256). **Off screen (frame outside every display): NULL** for every option, including after being on screen. `sharingType = .none`: NULL everywhere. Times (0x900, 100 calls): p50 0.45–0.55 ms, p95 6.5–7.6 ms on 128–256 pt windows; p50 4.7–5.3 ms, p95 8.6–9.4 ms at 7.7 MP (the built-in display's full frame at 2x, 3456 × 2234). Memory at 7.7 MP: bare captures, peak 0.0 MB above baseline over 100 calls, +0.14 MB over 1,000. Capture plus a 480 px thumbnail draw: peak +3.4 MB over 100 calls, then +2.5 MB over the next 1,000 and, in a second run, +2.8 MB over 2,000 (flattening), 0 leaks. Whole-process peak: 108.9 MB in the bare run (which holds its own 7.7 MP and larger test windows) and 31.4 MB in the thumbnail run, both under the 150 MB bound; the 5K leg is carried. Ownership: Create rule, details below. | **Pass with plan change PC-1** (the off-screen result is NULL). Other-Space, full-screen, 5K, no-Screen-Recording and 15 legs carried |
| S0-5 | Every §4.12 symbol is exported from its planned image (table below). Every probe passes 1,000 of 1,000 with the same result, on the plan's probe window, except the capture probe, which needs PC-1. | **Pass** on 27.2 (capture probe with PC-1). Mission Control, logout and 15 legs carried |
| S0-6 | Needs a test panel over the Dock and a full-screen app. | Carried |
| S0-7 | Needs Dock preference changes. | Carried |
| S0-8 | Needs 10 min idle and 50 raises, which call raise symbols. | Carried |
| S0-9 | Needs a mouse tap and clicks. | Carried |
| S0-10 | Present now: 19 regular apps in seven classes (Apple other 5, Native other 5, Electron 4, Chromium-based 2, Catalyst 1, Finder 1, Terminal 1). Their 18 on-screen standard windows: AX 18, SCK 18, `CGSHWCaptureWindowList` 18 of 18 non-blank at scales 1 and 2 (p50 14.2 ms, p95 25.7 ms), SCK still non-blank (196 ms). Every AX window matched a `CGWindowList` frame, with no AX errors. Also 24 layer-0 windows that are **not on screen, not in AX, and not minimized or hidden**, from six of the apps, with no other Space in existence: all 24 in SCK (`onScreen` 0), 20 untitled, private capture OK for 24 but blank for 21 (one has alpha 0). What they are wasn't examined, since titles aren't read; background tabs and helper windows fit. | **Recorded** for the classes present. Other classes carried |
| S0-11 | Needs Stage Manager. | Carried |
| S0-12 | The bottom Dock on the main display converts correctly: AX (219, 1348, 2122 × 82) to Cocoa y = 1440 − 1348 − 82 = 10, inside the main screen; item frames to y 5. | **Pass** for this arrangement. Secondary-display, display-above and Dock-on-2x legs carried |
| S0-13 | Needs Mission Control, App Exposé, Launchpad, Spotlight and Stage Manager while hovering. | Carried |
| S0-14 | At rest, off main, 500 reads: `AXSelectedChildren` p50 0.013 ms, p95 0.018–0.035 ms, max 0.131 ms. One item's six attributes in one call: p50 0.022 ms, p95 0.028–0.034 ms, max 0.15 ms. Full snapshot (children plus six attributes per item): p50 0.8 ms, p95 0.92–1.10 ms, max 1.39 ms. Cold attach: 16.9–36.4 ms. Main-thread heartbeat worst lateness about 1 ms. **Stalled app** (our child blocking its main thread 5 s): off-main reads return `kAXErrorCannotComplete` at the set timeout (0.15 s → 155 ms, 0.5 s → 502 ms, 1 s → 1001 ms; the global default returned at 1.5 s), and read normally (2.3 ms) after. Our main thread's worst lateness over the run: 3.4 ms. | **Pass** at rest and for the stall. Hover-20, Mission Control, App Exposé, launch bounce and magnification legs carried |
| S0-15 | See the table below. | **Recorded**. Team ids carried |
| S0-16 | Needs VoiceOver. | Carried |
| S0-17 | Every probe 1,000× in batches, off main, on our own windows. Before, between and after each batch: other apps' on-screen window order, the frontmost app, the probe window's Spaces, all 256 symbolic hotkey states (SLS and CGS), and SHA-256 of `com.apple.spaces.plist` and `com.apple.symbolichotkeys.plist`. **No change in any of them**, in any batch or over the run. Results identical in every call. | **Pass** on 27.2. 15 leg carried |
| S0-18 | Needs Screen Recording off. | Carried |
| S0-19 | Needs the owner to watch for indicators and alerts. | Carried |
| S0-20 | Needs keys, taps and an Accessibility revoke. | Carried |
| S0-21 | Needs pointer moves. | Carried |
| S0-22 | Needs the pointer resting on an icon. | Carried |
| S0-23 | Running apps have 0–2 AX windows each: per-pid read p95 0.2–6.5 ms, max 35 ms. Synthetic, our child process with N titled windows parked off screen, 20 reads off main (app element, `AXWindows`, seven attributes per window): **1: p95 0.29 ms; 10: p50 0.39, p95 2.6 ms; 50: p50 2.8, p95 7.5 ms; 100: p50 5.1, p95 8.6, max 32.6 ms.** Cold first read 9–59 ms. Every window seen and titled. The `CGWindowList` per-pid filter (copy all, filter by pid): p95 7.7–9.2 ms at every N. | **Pass** for 10 windows (p95 2.6 ms against 150 ms) and recorded for A3. Without-Screen-Recording and untitled other-Space legs carried, and a real 50–100-window app |
| S0-24 | Needs a screen share. | Carried |
| S0-25 | Needs clicks, long-press and drag with a panel up. | Carried |
| S0-26 | Our child's windows, one `AXObserver` on its own thread. Registration: `AXObserverCreate` under 0.1 ms; the first app-element add 8–34 ms, the other three under 0.4 ms; `kAXUIElementDestroyedNotification` per window, 100 windows 3.2 ms in total (max 1.2 ms for one). Delivery, 10 each: **created p95 5.8–6.8 ms, title changed p95 1.0–1.6 ms, destroyed p95 3.8–12.5 ms. Miniaturized 550–554 ms and deminiaturized 535–536 ms (3 each)**, which is when the Dock's minimize animation ends and the window's state changes. | **Partial (carried).** Own windows: created, title changed and destroyed pass. Miniaturized and deminiaturized **fail** by 35–55 ms, so the row's answer (a 1 s tick while the panel is up) applies to those two unless the owner takes PC-3. Other apps carried |
| S0-27 | Needs raises of other apps' windows. | Carried |
| S0-28 | Needs a 1 kHz mouse. | Carried |
| S0-29 | Needs taps and an Accessibility revoke. | Carried |
| S0-30 | Needs a click on a card; 26.3+ needs another Mac. | Carried |
| S0-31 | 8 h soak at R. | Carried |
| S0-32 | DockDoor run as a black box. | Carried |

**No §5 scope contingency fires.** S0-1 passes on 27.2. Its 15 leg, and S0-2 on both OSes, are still open, and
either can still take Dock Previews out of 0.5.0.

## Plan changes named (PLAN.md not edited)

- **PC-1 (S0-4; §4.12 step 4, "The probe window" and the `CGSHWCaptureWindowList` bullet; §4.9 content check).**
  On 27.2 a capture is clipped to the part of the window's frame that lies on a display. A window wholly off screen
  gives NULL, so the shape-only probe on the off-screen, `sharingType = .none` probe window would get "no answer" on
  every attempt, and private capture would never turn on. Change: the capture probe uses a second 64 × 64 window
  that is **never ordered in**, framed inside the main screen's visible frame, with `sharingType = .readOnly` and
  the same pattern. It isn't shown, isn't in `CGWindowList` and has no Space, so it shouldn't appear in Mission Control (S0-5a checks). It
  captures with signature 0.00 % (64 × 64, 1,000 of 1,000; p50 0.32 ms, p95 4.2 ms, max 16.8 ms). So on 27.2 the
  probe passes **with the pattern check**, and §4.9's shape-only branch isn't reached. The Spaces and AX probes keep
  the ordered-in, off-screen, `.none` window.
- **PC-2 (S0-4; §4.12 step 5 result classes; §4.9 shape).** Add "NULL for a window whose frame is on no display" to
  *no answer*, next to "a window that closed". A partly off-screen window gives an image of the visible part only
  (for example 32 × 64 for a 64 × 64 window half off screen). It passes the 4× shape rule; card layout must not
  assume the window's aspect ratio.
- **PC-3 (S0-26; proposed).** `kAXWindowMiniaturizedNotification` and `kAXWindowDeminiaturizedNotification` arrive
  when the minimize animation ends, about 0.54 s after the call with the Dock's current effect. Either the 0.5 s
  bound for these two counts from that moment (when the minimized state actually changes), or the row's answer (a 1
  s tick while the panel is up) applies to these two. The owner decides after the other-app leg.

## Also recorded

- **The ownership of `CGSHWCaptureWindowList`'s result** follows the Create rule: the array's retain count is 1 and it
  holds the image, so the caller releases it once (Swift: `takeRetainedValue()`). Fifty unreleased 4 MB captures
  grew our footprint by only 0.2 MB, so the pixels aren't in our heap (presumably memory shared with the window server).
- **Capture options.** 0x100 gives backing pixels (2x on the built-in display); 0x200 and 0xA00 give 1x there. No
  option (0x000, 0x100, 0x200, 0x800, 0x900, 0xA00) captures a window that is wholly off screen. A window captured during its order-out animation came back 126 × 126 and blank, while
  `animationBehavior = .none` gave the full pattern. Alpha 0 captures blank. A window below the desktop level
  captures normally.
- **The other-Space rule needs its Spaces filter (K4).** The 24 windows under S0-10 are `!minimized && !hidden &&
  !onScreen`, so the l.383 rule alone would list them all as "Window on another Space" (20 of them untitled, which
  the Dock path keeps). The plan already filters with `SLSCopySpacesForWindows` and drops the list when `spaces` is
  disabled (P-19). Whether that filter removes these windows wasn't tested, because the probes ran on our own windows
  only. That check is carried under S0-10, and 21 of the 24 would also be content-check suspects.
- **Spaces per display.** Our window on the built-in display reported Space 4011, and on the main display Space 1.
- **`dladdr`'s `dli_sname`** returns the SLS name for a CGS alias (same address), so the image check compares
  `dli_fname` only. `_CGSSetFrontProcessWithOptions` and `CGSPostEventRecordTo` aren't exported; the plan doesn't use
  them.
- **AX freshness.** Our child set its window title every 1 ms; an AX read off main saw a title 1.0 ms old at p95
  (max 7.6 ms), and the read took p50 0.03 ms. The Dock's AX tree showed our minimized window 556 ms after the call.
- **Programmatic `deminiaturize:` activates the app.** On our accessory-policy child, each of the three calls made
  it frontmost until it quit (about 3 s each). Focus went back to the owner's app when the child exited.
- **Symbolic hotkeys at the time of the run:** ids 1, 2 and 6 were enabled. SLS and CGS agreed on all 256 ids.

## S0-5: symbols, images and probes (27.2)

| Symbol | Image (`dli_fname`) | Probe, 1,000 × | Time |
|---|---|---|---|
| `CGSHWCaptureWindowList` (= `SLSHWCaptureWindowList`) | SkyLight | Plan's probe window: NULL, 100 of 100 (no answer). Capture-probe window (PC-1): one `CGImage` 64 × 64, signature 0.00 %. Closed or bogus id: NULL | p50 0.32 ms, p95 4.2 ms |
| `_AXUIElementGetWindow` | HIServices | The probe window is in our own `AXWindows` (subrole `AXUnknown`); returns its `windowNumber` | 0.001 ms |
| `GetProcessForPID` | HIServices | Presence only (raise) | — |
| `_SLPSSetFrontProcessWithOptions` | SkyLight | Presence only (raise) | — |
| `SLPSPostEventRecordTo` | SkyLight | Presence only (raise) | — |
| `SLSMainConnectionID`, `CGSMainConnectionID` | SkyLight (same address) | Nonzero and equal | — |
| `SLSCopySpacesForWindows`, `CGSCopySpacesForWindows` | SkyLight (same address) | `CFArray` of one `CFNumber` (1). Empty array for a never-ordered-in window, a closed one, id 0 and a bogus id (no answer) | p50 0.021 ms, p95 0.033 ms |
| `SLSSetSymbolicHotKeyEnabled`, `CGSSetSymbolicHotKeyEnabled` | SkyLight (same address) | Presence only (not called in this run) | — |
| `SLSIsSymbolicHotKeyEnabled`, `CGSIsSymbolicHotKeyEnabled` | SkyLight (same address) | `Bool`; ids 1, 2 and 6 true; SLS and CGS agree for 0–255 | p50 0.021 ms for three ids |
| `KBGetLayoutType` | HIToolbox | `'ANSI'` (one of the known values) | — |
| `LMGetKbdType` | HIToolbox | 109 | — |
| `IsSecureEventInputEnabled` | HIToolbox | 0 (public; exempt from the image check) | — |

All paths are `/System/Library/…/Versions/A/…`: SkyLight under PrivateFrameworks; HIServices under
ApplicationServices; HIToolbox under Carbon.

## S0-15: other Dock preview tools

| App | Bundle id | Team id | Source |
|---|---|---|---|
| DockDoor | `com.ethanbills.DockDoor` | pending: `codesign -dv` at R | Homebrew cask `dockdoor` 1.42.4 (`zap`) |
| DockDoor Pro | `com.ejbills.DockDoorPro` | pending | Homebrew cask `dockdoor-pro` 1.7.6 (`uninstall quit`) |
| HyperDock | `de.bahoom.HyperDock` | pending | An Info.plist listing for version 1.7 (old, not in Homebrew); unverified for current builds |
| Dock Mate | `com.macenhance.dockmate` | pending | Homebrew cask `dockmate` 0.8.7 (`zap`) |
| DockView 2 | `com.macplus-software.com.DockView-2` | pending | Homebrew cask `dockview` 2.6.4 (`zap`) |

Considered, not listed: Dock replacements that draw their own dock and don't preview the system Dock's items
(ActiveDock 2 `com.sergey-gerasimenko.ActiveDock-2`, uBar `ca.brawer.uBar`, DockFix `dk.FIrstForm.DockFix`, Taskbar
`com.fpfxtknjju.wbgcdolfev`, Tungsten Edge `com.caye.macosdockcc.v2`), and Dockside `com.hachipoo.Dockside` (a Dock
utility whose previews weren't confirmed; its app group suggests team `8T2DC9NRXS`). The ids come from public
Homebrew cask metadata. No tool's source was read. With every team pending, K1 matches by bundle id only.

## Carried forward (owner or hardware)

"Gates" is the item that row must pass before (§5). 15 legs gate R.

| Row | What the owner does | Gates | Blocker |
|---|---|---|---|
| S0-1 | (a) macOS 15: run `/tmp/s0-dock/dock -v` (rebuilt there) and record the list, subroles, `AXURL`, frames and running resolution. (b) 27.2: drag a folder and a web link into the Dock, run `dock -v`, and Block 3's restore removes them | K2 for (b); R for (a), as §5 allows | yes |
| S0-2 | Hover icons while the harness logs `kAXSelectedChildrenChangedNotification`: Dock bottom, left and right; magnification on; auto-hide on; two copies of one app (`open -n` on a harness test app); an app run from App Translocation (a quarantined download opened in place). 15 leg too | K2, K3; R for 15 | yes |
| S0-3 | `killall Dock` ×10 (scripted); sleep and wake; lock and unlock; fast user switching (needs a second account); arrangement change and resolution change in Displays. The harness logs re-attach time and `NSWorkspace` notifications | A3 | yes |
| S0-4 | Our window on a second desktop Space; our window full screen; a 5K display for the 100-call peak; a run without Screen Recording (result recorded, never used). 15 leg; 14 or 26 optional | B1b, A2b; R for 15 | yes |
| S0-5 | (a) With the probe and capture-probe windows up, open Mission Control and App Exposé and say whether a small black-and-white tile appears. (b) With permission, the harness turns off one symbolic hotkey; log out and back in; the harness reads it, turns it back on and confirms. 15 leg; 14 or 26 optional | B1b, A2b; R for 15 | yes |
| S0-6 | A harness test panel at candidate levels: hover icons (name label showing), then over a full-screen app's revealed Dock; on two Spaces; confirm focus never moves | A4a | yes |
| S0-7 | Scripted Dock settings: auto-hide with `autohide-delay` 0; `autohide-time-modifier` 0 and 0.15; magnification with `largesize` 128. Hover and leave; the harness logs frames and selection | K3 | yes |
| S0-8 | Leave the Mac idle 10 min with the harness attached (the display should sleep), then allow 50 scripted raises through the harness's copy of `bringToFront` (calls the raise trio). `pmset -g assertions` and `HIDIdleTime` are logged | B1b, A3 | yes |
| S0-9 | Allow a listen-only mouse tap; click Dock icons 100 times, then 100 more under the harness's load; type in a password field (Secure Event Input); click Safari's, Terminal's and Finder's icons with no windows open (reopen behaviour). The harness logs activation order and the TCC service | K3, A5 | no |
| S0-10 | Minimize one window and hide one app per present class; move one window per class to a second Space; one Chrome window full screen; Finder's desktop window; open Calculator, Photos, a PWA, an iOS app and a Java app if installed; tabbed windows in Finder, Terminal and Ghostty (if installed); recapture after wake; Sidecar needs an iPad. With permission, the harness calls `SLSCopySpacesForWindows` (read only) on the 24 not-on-screen windows' ids to confirm the filter drops them | K4 | yes |
| S0-11 | Turn on Stage Manager, make two stages, hover their apps; turn it off | K4 | no |
| S0-12 | Move the Dock to the built-in 2x display (rest the pointer at its bottom edge) and back; in Displays, put the built-in display above the main one, then restore the recorded arrangement | K2 | yes |
| S0-13 | While hovering an icon with the harness panel up: Mission Control, App Exposé, Launchpad (or Apps), Spotlight; Stage Manager with two stages; click a full-screen app's icon | K3 | yes |
| S0-14 | Hover across 20 icons in 2 s; Mission Control, App Exposé, a launch bounce (open an app) and magnification while the harness reads the Dock | A3 | yes |
| S0-15 | Team ids: download each tool's release into its own new, empty folder and run `codesign -dv --verbose=2` on the `.app` without opening it. Confirm HyperDock's current bundle id the same way | K1 ships bundle ids only; teams added at R | no |
| S0-16 | VoiceOver on (⌘F5): move through the Dock (VO-D), reach the harness panel, note announcements; VoiceOver off | K3 | no |
| S0-18 | Run the harness from a terminal app without Screen Recording (or turn it off for the host and back on): owner pid for minimized and other-Space windows | K4 | yes |
| S0-19 | Watch the menu bar and screen while the harness takes 50 captures per path of on-screen and minimized windows; report any indicator, "bypass the private window picker" reminder or Remote Desktop alert. tccd CPU is logged | A2a | yes |
| S0-20 | Allow taps: (a) type into a harness key panel and see focus return; (b) with both taps installed, press ⌥⇥ then arrows; (c) turn off Accessibility for the harness host with the tap on, wait 30 s, turn it back on | A5 | yes |
| S0-21 | 20 diagonal moves from an icon to the far card of the harness panel, magnification off, then on | K3 | no |
| S0-22 | Rest the pointer on a harness test app's Dock icon while the harness quits it | K3 | no |
| S0-23 | Without Screen Recording (as S0-18); an untitled window on another Space (Block 4); optionally a real app with 50–100 windows | K4, A3 | yes |
| S0-24 | Start a screen share (QuickTime screen recording or a browser meeting) and say whether the harness's `.none` panel appears in it. 15 leg too | A2a; R for 15 | no |
| S0-25 | With the harness panel up: right-click an icon, long-press, click the frontmost app's icon, drag a file onto an icon. The harness logs the Dock's menu notifications | K3 | yes |
| S0-26 | While the harness observes Safari, Chrome, an Electron app, Finder and Terminal: in each, open a window, change its title (switch tab), minimize, restore and close it. Then decide PC-3 | A1b | yes |
| S0-27 | Allow the harness to raise windows of other apps with `kAXRaiseAction` plus activate from its non-activating panel, 10 times, including one on another Space | A4b | no |
| S0-28 | A 1 kHz mouse moving over the harness panel while CPU is logged | A4a | no |
| S0-29 | With taps on: turn off Accessibility for the harness host (as S0-20c), and allow one `SLPSPostEventRecordTo` raise; report any "prohibited from synthesizing events" alert | A5 | yes |
| S0-30 | Click a card in the harness panel once, on 27.2 and on 26.3+ (needs a Mac on 26) | A4a | yes |
| S0-31 | 8 h soak of the R build: sleep and wake, a light/dark switch, a display change, another app's screen share, full screen in and out, an app hung across sleep | R | yes |
| S0-32 | Install DockDoor (best in a separate macOS account), read every setting's default from its Settings UI, quit and remove it. Its source is never opened | D1 | no |

The 15 legs (S0-1, S0-2, S0-4, S0-5, S0-17, S0-24) are owner checks before R. The 14 or 26 legs of S0-4, S0-5 and
S0-17 are optional, and M4 and M16 each get one owner leg on 14 or 26 at R. If the S0-1 or S0-2 15 leg fails, Dock
Previews comes out of 0.5.0 late, so run it as early as a 15 Mac or VM allows.

## Owner session

Each block runs with the harness attached and ends with its own restore. Marks: **[hands]** the owner acts;
**[permission]** the owner approves a scripted change, which the script reverts; **[hardware]** needs a device or
OS this host lacks. Blocks 1–6 run in order on this Mac, from least to most disruptive.

**Before Block 1:** record the state to restore: `defaults export com.apple.dock /tmp/s0-dock/dock-backup.plist`; a
screenshot of System Settings › Displays › Arrange; the Privacy grants for Accessibility and Screen Recording.

1. **Watch and hover, no settings changed (30 min).**
   - S0-19 [hands]: watch for indicators while 50 captures run per path (5 min).
   - S0-5a [hands]: Mission Control and App Exposé with the probe windows up (2 min).
   - S0-2 bottom, two copies; S0-14 hover-20, Mission Control, App Exposé, bounce [hands] (7 min).
   - S0-12 Dock on the 2x display and back [hands] (3 min).
   - S0-26 other apps [hands] (8 min).
   - S0-10 present classes: minimize, hide, tabs, odd apps; the Spaces read on the 24 windows [hands, permission]
     (5 min). Restore: unminimize, unhide, close the extra apps.
2. **Harness panel and taps (40 min).** S0-6 (Dock and label), S0-25, S0-21 (magnification off), S0-22, S0-30,
   S0-24 [hands]; S0-27 raises of other apps [permission]; S0-9 and S0-20 (a), (b) with taps [hands, permission];
   S0-28 [hardware: 1 kHz mouse]. Restore: the harness removes its taps and panels and exits.
3. **Dock preferences (20 min)** [permission, hands]. Scripted `defaults write com.apple.dock …` plus `killall Dock`
   for: S0-3 `killall Dock` ×10; S0-2 left, right, magnification, auto-hide; S0-7 `autohide-delay` 0,
   `autohide-time-modifier` 0 and 0.15, `largesize` 128; S0-14 and S0-21 with magnification on; S0-1b a folder
   and a link dragged into the Dock. Restore: `defaults import com.apple.dock /tmp/s0-dock/dock-backup.plist;
   killall Dock`, then check orientation bottom, autohide 0, magnification 0, tilesize 62, and the folder and link
   gone.
4. **Spaces, full screen, Stage Manager, displays, VoiceOver (35 min)** [hands].
   - Add Desktop 2 in Mission Control: S0-4, S0-10 and S0-23 other-Space legs (8 min).
   - Full screen: our window (S0-4), a Chrome window (S0-10), S0-6 over the full-screen Dock, and S0-13's click on
     its icon (6 min).
   - S0-13 Mission Control, App Exposé, Launchpad, Spotlight while hovering (3 min).
   - Stage Manager with two stages: S0-11, S0-13 (5 min).
   - Displays: built-in above (S0-12), then an arrangement and a resolution change (S0-3) (6 min).
   - VoiceOver: S0-16 (5 min).
   - Restore: windows back from Desktop 2, then remove it; exit full screen; Stage Manager off; the recorded
     arrangement and resolution; VoiceOver off.
5. **Permissions (15 min)** [hands]. S0-4, S0-18 and S0-23 without Screen Recording (an ungranted terminal, or the
   host's switch off); S0-20c and S0-29 with Accessibility off for 30 s [permission for the one
   `SLPSPostEventRecordTo` call]. Restore: both switches back on, and the harness confirms preflight and trust.
6. **Session events (30 min, 10 of them idle).** S0-8: 10 min away from the Mac, then 50 scripted raises
   [permission]. S0-3: sleep and wake, lock and unlock, fast user switching [hands; a second account, removed after if it
   was made for this]; S0-10 recapture after wake. Last, S0-5b: one symbolic hotkey off [permission], log out and in [hands], then the harness
   turns it back on and confirms all 256 ids match the record from before.
7. **Elsewhere, separate sittings** [hardware].
   - macOS 15 Mac or VM: S0-1, S0-2, S0-4, S0-5, S0-17, S0-24 (60 min).
   - Optional 14 or 26: S0-4, S0-5, S0-17 (30 min); S0-30 on 26.3+ (5 min).
   - A 5K display: the S0-4 peak (10 min).
   - An iPad: Sidecar for S0-10 (10 min).
   - S0-32 DockDoor black box, in a separate account (20 min).
   - S0-15 `codesign -dv` on downloads (10 min).
   - S0-31: 8 h soak of the R build, unattended.

**Time:** Blocks 1–6 take about 2 h 50 min on this Mac. Block 7 takes about 2 h 25 min, plus the 8 h soak at R.
