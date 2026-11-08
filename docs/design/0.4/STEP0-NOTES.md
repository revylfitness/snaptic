# 0.4 Hidden Icons — S0 results

Host: macOS 27.2 (26B123), Apple Silicon. Displays: an external 2560 × 1440 main display at 1 pt per px, plus
the built-in 1728 × 1117 notch display to its left. Snaptic 0.3.4 was running with Awake active, and no other menu
bar hider was running. The harness was a throwaway Objective-C tool in `/tmp/s0-icons/` (not committed). It
`dlopen`s MenuBarClientCore, drives `MBAssessmentModeAssertion`, reads the AX extras of every running app, and takes
screenshots of the menu bar. Visual results come from those screenshots, because AX misreports hidden items (S0-10).

Run on 2026-11-07. "Pending" means the row needs the owner's hands or hardware this host doesn't have. Each pending
row is listed under **Carried forward** at the end, with the point by which it must pass.

| # | Result | Verdict |
|---|---|---|
| S0-1 | All five encodings match §4.2.2 exactly. Other selectors seen: `activateWithCompletionHandler:`, `activate:completion:`, `allowedBundleIdentifiers`, `allowedSystemItems`. | **Pass** |
| S0-2 | Allow `[]` + system `0..<64`: every third-party item hides, and everything comes back on `invalidate`. Two system casualties: **Now Playing** (`com.apple.menuextra.now-playing`, from MenuBarAgent) is hidden under *any* restriction, and **Text Input** (`com.apple.TextInputMenuAgent`, its own process) hides like a third-party app unless its bundle id is allowed. Allowing it works. Sound, Wi-Fi, Battery, Control Center and Clock stay. | **Pass with plan change** (R2-1) |
| S0-3 | `0..<64`, `0..<128` and `0..<1024` behave the same. Now Playing stays hidden under every range, and also with `com.apple.controlcenter`, `com.apple.MenuBarAgent`, `com.apple.systemuiserver` or the media app's bundle allowed. | Default stays `0..<64` |
| S0-4 | (1) A, then B, then invalidate A: B's allow-list holds. (2) A, then B, then invalidate B: A's allow-list is back. (3) Two processes, P1 allowing Alcove and P2 allowing Monocle: **both** stay visible. Killing either process leaves the other's restriction in force. **The effective allow-list is the union of every active assertion, across processes. It is neither replace nor last-writer-wins.** | **Pass**: activate N+1, then invalidate N (R2-2) |
| S0-5 | `invalidate` from a background queue while main sleeps 5 s returns in under 1 ms, and every item is back within 1 s, before main unblocks. No crash. | **Pass**: no helper process needed |
| S0-6 | `killall MenuBarAgent` while restricted: the agent relaunches (new pid) and **the restriction survives**. Items stay hidden until the holder invalidates or exits. Afterwards, new activations work at once. While expanded, the restart is harmless. Side effect: AX and the in-process status-item frames then reported the built-in display instead of the main one (S0-11). | **Pass** (R2-3) |
| S0-7 | Screen recording: the purple indicator stays visible in every restricted screenshot. Camera, mic and location: pending. | Partial (carried) |
| S0-8 | (b) The macOS overflow chevron (“Show Hidden Menu Bar Items”) disappears while a restriction holds, because fewer items need the room. Other items are pending. | Partial (carried) |
| S0-9 | `/usr/libexec/assessmentagent` runs with **no** exam open, so the process alone is not a signal. Because of S0-4's union, any assertion of ours during an exam would *add* to the exam's allow-list, so the guard is mandatory. A real exam session is pending. | Pending (R2-4) |
| S0-10 | While restricted: allowed third-party items report fresh AX frames (Alcove moved from x −352 to −317). **Hidden third-party items stay in AX at their stale frames.** Hidden MenuBarAgent items (Now Playing) are removed from AX. So presence can't tell hidden from shown, and only allow-listed bundles' frames can be trusted. | **Pass**: this matches §4.2.2's re-read rule, which is clarified in R2-5 |
| S0-11 | On the crowded notch display, MenuBarAgent adds an AX item, “Show Hidden Menu Bar Items” (`com.apple.MenuBarAgent`), and the overflowed extras are **absent** from AX (9 extras reported there against 21 on the main display). An overflowed item's own `NSStatusBarWindow` frame sits left of the screen (x −1765 with the screen's minX −1728), and its `screen` is nil. AX and the in-process frames always described the same display. | Recorded (R2-6) |
| S0-12 | SIGKILL of the holder: every item is back within 2 s. | **Pass** |
| S0-13 | No macOS 15 VM on this host. | Not run (carried) |
| S0-14 | No macOS 15 VM on this host. | Not run (carried) |
| S0-15 | See the table below. | Recorded |
| S0-16 | Hidden Bar isn't installed. The two-harness run in S0-4(3) stands in for it: a second MenuBarClientCore hider unions with ours. | Recorded |

Also recorded:

- **Completion threading.** The completion handler runs on a background thread, 2–26 ms after activation, exactly
  once per activation, and with `err = nil` every time on this host. The shim must hop to main, as §4.2.2 already
  says.
- **Own items under a restriction.** An unbundled test process's status item was hidden by a restriction that
  didn't allow it. Its `NSStatusBarWindow` frame, `isVisible` and `occlusionState` were **unchanged**. In-process
  frames can't detect our own item being hidden (R2-7).
- **macOS 27 hosts status items in MenuBarAgent.** `CGWindowList` shows one MenuBarAgent bar window per display
  (layer 24) and no per-item windows, so the window list can't show what is hidden.
- **System extras' identity.** MenuBarAgent's AX children are `AXGroup`s whose first child carries
  `AXIdentifier = com.apple.menuextra.<name>` (now-playing, sound, wifi, battery, controlcenter, clock).

## S0-15: other hiders

| App | Bundle id | Team id | Source |
|---|---|---|---|
| Hidden Bar | `com.dwarvesv.minimalbar` | `W777S7V8TN` | dwarvesf/hidden `project.pbxproj` |
| Bartender 4/5/6 | `com.surteesstudios.Bartender` | pending: `codesign -dv` at R | third-party notes; not installed here |
| Ice | `com.jordanbaird.Ice` | `K2ATHQPJDP` | jordanbaird/Ice `project.pbxproj` |
| Thaw | `com.stonerl.Thaw`, plus an optional build suffix | `A7CKWF99ML` | thaw-app/Thaw `project.pbxproj` (it also lists Ice's team, inherited) |

Known forks with their own ids, such as `com.lxy1992.Ice` and `com.pnikolaidis.icemelt`, aren't listed. A match
needs the bundle id (Thaw: the prefix) **and** a matching team when one is known. A pending team means the match is
by bundle id only.

## Carried forward (owner or hardware)

| Row | What | Must pass before |
|---|---|---|
| S0-7 | Camera (FaceTime), mic (Voice Memos) and location indicators stay visible with their apps hidden | A2 |
| S0-8 | (a) ⌘-drag an allowed item and the arrow while restricted; (c) Clock timer and FaceTime Live Activity; plus (b) System Settings › Menu Bar, (d) a banner, (e) Control Center and Notification Center, (f) Spotlight, screenshots and the Dock | A2 for (a) and (c); R for the rest |
| S0-9 | A Safari AAC exam page (or an `AEAssessmentSession` test app): record `NSApp.currentSystemPresentationOptions` during it, and confirm our collapse and expand never lift the exam's restriction once the R2-4 guard is in | A3 |
| S0-13, S0-14 | macOS 15 VM: `Preferred Position` seeding, and Length at L = 10 000 | R (`MANUAL-CHECKS.md`, the L rows) |
| S0-15 | Bartender's team id | K1 ships the bundle id only; the team is added at R |
