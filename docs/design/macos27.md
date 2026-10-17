# macOS 27 "Golden Gate": impact on Snaptic (window switcher + Displays)

Research date: 2026-10-17. Shipping state: macOS 27.0 / 27.0.1 GA (build 26A428 cited in OSS reports); 27.2 is in beta (Beta 4 release notes published).
Legend: **[V]** verified with a primary/vendor source URL · **[O]** observed in an OSS repo/issue (third-party report, not Apple) · **[U]** unverified / inferred.

Context that matters for every item: Snaptic links against the **macOS 15 SDK (Xcode 16)**. AppKit "linked-on" behaviour changes gated on the 26 or 27 SDK do **not** apply to us, and new 27-only APIs (e.g. `NSStatusItem.expandedInterfaceDelegate`) are **not in our SDK**.

---

## 1. Privacy permissions on macOS 27

### 1a. "Device Control and Data Access" (DC&DA) is the **renamed Accessibility pane**
- It is not a new TCC service. Privacy & Security > "Accessibility" is now titled **"Device Control and Data Access"** on macOS 27; earlier versions still say "Accessibility". [V] Symless support article: https://support.symless.com/hc/en-us/articles/35743428145169 ; [V] BetterDisplay guide ("The permission route is Accessibility on earlier macOS versions and Device Control and Data Access on macOS 27 and later"): https://betterdisplay.pro/guide/interface-reference/settings/keyboard/native-keyboard-control/ ; [O] https://github.com/waydabber/BetterDisplay/issues/5766 , https://github.com/TheBoredTeam/boring.notch/issues/1561 , https://github.com/keymanapp/keyman/issues/16703 ; Jeff Johnson quoted at https://mjtsai.com/blog/2026/09/14/macos-27-golden-gate/
- Apple's own pane text, quoted in an OSS issue, begins: "Apps with this access can view and send email, edit contacts and photos, monitor your keyboard…". Apple's enterprise note describes the grant as letting an app "access their data, monitor their keyboard and websites, record their screen, and more". [O] https://github.com/appandflow/stim/issues/2494 ; [V] https://support.apple.com/en-us/148830
- **TCC service name:** unchanged, `kTCCServiceAccessibility`. `sudo tccutil reset Accessibility` still works on 27. [V] Symless article above. Apple's 27 enterprise notes call the PPPC `Accessibility` key "deprecated" for MDM silent grants. Users must now consent, and get a one-time notice per MDM-configured app. [V] https://support.apple.com/en-us/148830 ; [O] https://note.com/too_applebiz/n/n0eb8b45225eb
- **What triggers it (same as Accessibility before):** AX APIs against other processes (`AXUIElement*`), **active** `CGEventTap`s that filter keyboard events, and native brightness/volume key interception. BetterDisplay's guide says native key handling needs "Set up Device Control and Data Access…" on 27 and that "Permission changes may still require the restart". [V] BetterDisplay guide URL above. Window frame save/restore tools need it too. [O] https://www.designtech.so/support/screenplace-how-can-i-grant-the-device-control-and-data-access
- **Programmatic check:** `AXIsProcessTrusted()` still works as the silent check. [O] (it is used across all the projects above; no report of it breaking). **Change:** `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` **no longer reliably raises the system dialog or adds the app to the list on 27**. The Clipy and Shottr reports are from one machine. Grabbr-hops on 27.2 got no prompt and no row on a fresh install or after `tccutil reset`. [O] https://github.com/WhisKeySwitch/Switcher3way/pull/108 , https://github.com/WhisKeySwitch/Switcher3way/pull/112 , https://github.com/jtjones09/grabbr-hops/issues/243 . Espanso sees AX checks returning false despite a grant on 27 (MDM machine, unconfirmed). [O] https://github.com/espanso/espanso/issues/2813
  - Workarounds that OSS adopted: (1) still call the prompt variant once; (2) **also open the pane directly**; (3) tell users to add the app with **"+"** and show the app path; (4) poll `AXIsProcessTrusted()` and ask for a **restart after grant**. [O] same PRs; DockDoor 1.40.2: "asks you to restart once it detects the permission has been granted" https://dockdoor.net/CHANGELOG.html
  - Known limitation: the deep link does not navigate if System Settings is already open. [O] Switcher3way PR #108.
- **Opening the pane:** `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` still works and opens the DC&DA pane on 27. [O] https://github.com/appandflow/stim/issues/2494 . (The Ventura+ form `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility` was not re-checked on 27. [U])
- **Do not read TCC.db.** "Apps can no longer access the local TCC database directly." [V] https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes (TCC > Deprecations, 90775556). One blog measured that FDA-holding processes could still read the system DB on 26A428, but treat it as off-limits. [O] https://blakecrosley.com/blog/macos-27-release-notes
- New `tccutil list -s SERVICE` / `-b BUNDLE_ID` (managed devices) helps with diagnostics only. [V] https://support.apple.com/en-us/148830

### 1b. Input Monitoring (`kTCCServiceListenEvent`)
- **It is contested whether Input Monitoring is still a separate pane on 27.**
  - Evidence that it is still separate: Apple's current Mac User Guide (version list tops out at macOS 27) still documents Privacy & Security > Input Monitoring [V] https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac . The PPPC `ListenEvent` key "will continue to be managed via PPPC" (not among the 27 deprecations) [O] https://note.com/too_applebiz/n/n0eb8b45225eb . The Wacom macOS 27 guide still tells users to enable Input Monitoring [V vendor] https://support.wacom.com/hc/en-us/articles/43537850453527 . Grabbr-hops on 27.2 still calls `CGRequestListenEventAccess` separately [O] issue #243.
  - Counter-claim: one OSS dev says 27 "merged Accessibility and Input Monitoring into one list called Device Control and Data Access". [O] https://github.com/WhisKeySwitch/Switcher3way/pull/108 → treat as **[U]**. It is most likely a misreading, because DC&DA's description includes "monitor your keyboard".
- Long-standing semantics, unchanged as far as we found: a **listen-only** keyboard tap is allowed with Input Monitoring **or** Accessibility. An **active** (filtering) keyboard tap needs Accessibility (now DC&DA). Karabiner docs: Input Monitoring is "usually unnecessary" because "it is covered by the Accessibility setting". [O] https://karabiner-elements.pqrs.org/docs/manual/misc/required-macos-settings/ . Apple's CGEventTapCreate doc still only says key events need root or "access for assistive devices". [V] https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)
- Checks: `CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()` (10.15+) [V] https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess() ; `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` [U, not re-checked on 27]. Pane URL `…?Privacy_ListenEvent` [U on 27].

### 1c. PostEvent (`kTCCServicePostEvent`)
- Still a distinct TCC service on 27. Espanso shows `tccutil` reporting "PostEvent granted" on 27.0. [O] https://github.com/espanso/espanso/issues/2813 . `CGRequestPostEventAccess` produced no dialog and no row on 26.6 in one report. [O] https://github.com/joshedwards237/Amanuensis/pull/42 . This is only relevant if we synthesise key events (e.g. forwarding media keys).

### 1d. Screen Recording ("Screen & System Audio Recording") and a new "Remote Desktop" entry
- The pane is still called "Screen & System Audio Recording". `Privacy_ScreenCapture` deep link still valid. [O] https://github.com/appandflow/stim/issues/2494
- A new, **separate "Remote Desktop" entry** in Privacy & Security (27 beta 4+). `CGPreflightScreenCaptureAccess()` reflects only Screen & System Audio Recording, not Remote Desktop. `SCShareableContent` calls can raise a consent alert **on every call** (reported by a remote-control vendor with the `persistent-content-capture` entitlement). Apple DTS: "there's no API that specifically returns the state of that privilege" (FB24263354). Service name `kTCCServiceRemoteDesktop` comes only from TCC.db schema inspection. [V forum, Apple DTS reply] https://developer.apple.com/forums/thread/841530 . What it governs exactly is **[U]**. Our plain SCK thumbnail use has not been reported to hit it.
- The consent alert text says "'App' would like to record this computer's screen and audio" even for still screenshots. Per the SCK sample, after granting **you need to restart the app** before capture works. [V forum, Apple DTS] https://developer.apple.com/forums/thread/847998
- **`CGWindowListCreateImage` is broken on 27 (beta 4+): it returns a grey image, not nil.** Apple DTS: no way to restore the 26 behaviour. [V] https://developer.apple.com/forums/thread/847998 , https://developer.apple.com/forums/thread/849969 ; [O] menu-bar tools broke on it: https://www.publicspace.net/blog/macos-27-menu-bar/
- tccd cost per SCK capture is significant (AltTab measured about 1,350 authorization requests across 446 screenshots, about 23 ms of tccd CPU per thumbnail). This was on 26.6.2 and not reproduced on 27. [O] https://developer.apple.com/forums/thread/848165
- The Sequoia-era periodic "still wants to record" reminders were not reported as changed on 27. [U]

### 1e. Carbon `RegisterEventHotKey`
- No 27 change found. It still needs **no** TCC permission and still fires **under Secure Event Input**, when keyDown taps see nothing. The Sequoia "Option/Shift-only modifier hot keys rejected" restriction did not reproduce in one 27 test. [O] https://github.com/joaodavidsilva/brightboi/issues/99 . Background on the 15.0 restriction: [V] https://developer.apple.com/forums/thread/763878 , https://blog.eternalstorms.at/2024/09/23/keyboard-shortcuts-using-option-and-or-shift-modifiers-only-no-longer-allowed-on-macos-sequoia/ . Under 27, treat Option-only combos as risky. [U]

## 2. Do CGEventTaps for NX_SYSDEFINED and keyDown still work?
- **Yes**, on 27, with Accessibility (DC&DA):
  - An active session tap (`.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap`) with mask keyDown | systemDefined works on 27. [O] https://github.com/joaodavidsilva/brightboi/issues/100 , #99
  - A `.cghidEventTap` NX_SYSDEFINED tap works in OSS with Accessibility, not root. Apple's doc still claims HID-location taps need root; practice differs. [O] https://github.com/kelvintiger/KelvinXDR/issues/1 ; [V doc wording] CGEventTapCreate URL above.
  - BetterDisplay 5.1.1 (macOS 27.2-compatible) still intercepts brightness/volume keys behind the DC&DA permission. [V] https://github.com/waydabber/BetterDisplay/releases , guide URL above.
- Gotchas observed on 26/27:
  - **Secure Event Input** hides keyDown/keyUp from all taps, but NX_SYSDEFINED media-key events still arrive. [O] brightboi #99
  - **Tap ordering:** head-inserted session taps from MonitorControl, Lunar, BetterDisplay, BTT, Karabiner and others compete. The last created wins, and HID taps run before all session taps. Use `CGGetEventTapList` to detect competitors, and `CFMachPortInvalidate` on stop. [O] brightboi #100
  - **Control Center now owns the brightness/volume keys and the OSD.** If you consume a key-down but not the matching key-up, or start mid-autorepeat, Control Center and your app "fight" and brightness jumps to min/max. BetterDisplay fixed this in 5.1.1 by forwarding key-release events and ignoring orphan auto-repeats. [V] https://github.com/waydabber/BetterDisplay/releases (5.1.1: "Fixed brightness jumping to minimum or maximum and the macOS Control Center OSD remaining visible after wake on macOS 27"); [O] https://github.com/waydabber/BetterDisplay/issues/5846
  - **Revoking DC&DA while an active tap is installed can freeze the whole Mac** on 27.2 (repeated `kCGEventTapDisabledByTimeout`). Mitigation: never block in the callback; on timeout or user-input disable, re-check `AXIsProcessTrusted()` before re-enabling; add a circuit breaker; invalidate the tap if the permission is gone. [O] https://github.com/jtjones09/grabbr-hops/issues/240 ; related Apple forum thread https://developer.apple.com/forums/thread/844416 (fetch failed; title only). DockDoor 1.40.2: "When macOS refuses DockDoor's input access, DockDoor releases its keyboard and mouse monitoring." [O]
  - 27 no longer reads undocumented gesture fields in synthesised CGEvents (Mac Mouse Fix broke). This only matters if we post fake gesture events. [O, secondary] https://macworld.info/article/why-macos-27-broke-mac-utilities/

## 3. Subsystem changes

### Menu bar / NSStatusItem (biggest functional change)
- **The whole menu bar is now one window.** Status items are no longer per-item windows. When space runs short, items are hidden behind a system **overflow indicator**. The user, not the app, controls it. [V] https://support.apple.com/en-us/148830 ("Menu bar items are hidden and replaced with a compact overflow indicator"); [O] https://www.publicspace.net/blog/macos-27-menu-bar/ , https://badgeify.app/macos-27-golden-gate-menu-bar-changes/ , https://macworld.info/article/why-macos-27-broke-mac-utilities/ . The System Settings > Menu Bar pane has show/hide toggles for system and **third-party** items, and users can Cmd-drag items to remove them. [O] badgeify
- **New AppKit API (27 SDK):** `NSStatusItem.expandedInterfaceDelegate` (`NSStatusItemExpandedInterfaceDelegate`: `statusItem(_:didBegin:)`, `statusItemDidEndExpandedInterfaceSession(_:animated:)`) and `expandedInterfaceSession?.cancel()`. These are for status items that show a custom window or panel. [V] https://developer.apple.com/documentation/appkit/nsstatusitem.md ; WWDC26 session 289 "Modernize your AppKit app" (ch. "Keyboard navigation and status bar items") https://developer.apple.com/videos/play/wwdc2026/289/
- Regressions reported on 27 (Apple Developer Forums):
  - Custom popover-style items: left-click works only inside an expanded-interface session, right-click and second-click-to-close stop working, and drag-onto-item triggers Mission Control. An Apple engineer says local event monitors are "no longer the recommended way to scan for status item events"; use the stock `button` (not a subclass) or gesture recognizers. [V forum] https://developer.apple.com/forums/thread/832823 (FB23018381, FB22983198, FB23224071)
  - Hover events: fixed in beta 5. `button.highlight(true)` no longer shows a highlight (FB23330269, open). `button.window.occlusionState` no longer tells you whether the item is hidden (FB23349447, open). Taps outside a custom panel are not observable. [V forum] https://developer.apple.com/forums/thread/836113
  - `NSStatusItem.isVisible` reflects only the app's own request, not the user's hide or overflow state. [U]
- Menu item images: on 27, symbol images in menus are hidden by default **for apps linked on the 26+ SDK**. Linked-on-15 SDK apps (us) keep images. [V] macOS 27 release notes, AppKit (170477566, 179374305)
- Control Center controls (WidgetKit `ControlWidget`) arrived on macOS 26 for Control Center and the menu bar. This needs a 26+ SDK and an app extension. [U, not re-verified this session; doc index: https://developer.apple.com/documentation/widgetkit/controlcenter.md]

### OSD (OSDUIHelper / OSDManager)
- On 26/27 the brightness and volume HUD is drawn by **Control Center**, not OSDUIHelper. BetterDisplay: the API behind "Force system OSD" "is no longer there in macOS, so this option is hidden when the app is running on macOS 27". [O] https://github.com/waydabber/BetterDisplay/discussions/5587
- MonitorControl 4.4.0 on 27.0 still shows the **old square HUD**, so the legacy OSDManager path still renders but looks stale. Waydabber reverse-engineered a way to call the 27.0 Control Center OSD, but it "broke or changed in 27.2". [O] https://github.com/MonitorControl/MonitorControl/issues/1904 , https://github.com/waydabber/BetterDisplay/issues/5619
- **27.2 introduces a new rounded OSD with a segmented bar.** BetterDisplay ships a self-drawn imitation, on by default on 27.2. [V] https://github.com/waydabber/BetterDisplay/releases (5.1.0/5.1.1)
- Self-drawn OSD/overlay windows render washed-out on 27 unless they are tuned (Liquid Glass changes). [O] https://github.com/waydabber/BetterDisplay/discussions/5564

### Gamma tables / M5 bug (FB22273782)
- Bug: `CGSetDisplayTransferByTable`/`ByFormula` returns success and reads back correctly but has no visible effect on M5 Pro/Max and MacBook Neo. Apple reproduced it on M5 Max 26.3.1. [V forum] https://developer.apple.com/forums/thread/819331
- **Not fixed in 26.5** [O] https://github.com/waydabber/BetterDisplay/discussions/5217 (May 13 comment). It was still unresolved per Apple feedback as of Jun 18, 2026 [O] same discussion. On 27.0, BetterDisplay's maintainer still calls Color Table Control "unreliable on some M5 Pro and M5 Max systems, a known issue Apple has acknowledged" [O] https://github.com/waydabber/BetterDisplay/discussions/5814 . **No evidence it is fixed in 27.x** [U]. Not mentioned in the 27.0 or 27.2b4 release notes [V] (release notes URLs above).
- Separate older Tahoe bug: gamma tables are ignored while "Automatically adjust brightness" is on (fixed in 26 beta 5 per one report). [V forum] https://developer.apple.com/forums/thread/795074
- Gamma manipulation plus custom or malformed ICC profiles causes black screens on wake on 27 (MonitorControl). Workaround: "Avoid gamma table manipulation" or the factory profile. [O] https://github.com/MonitorControl/MonitorControl/issues/1912
- BetterDisplay's replacement for M5: a "compositor filter" overlay, or Metal. Side effect on 27: **full-screen compositor overlays block App Store/Touch ID secure UI** ("a security feature in macOS and works this way by design"). [O] https://github.com/waydabber/BetterDisplay/discussions/5814 , #5217

### EDR / XDR
- Lunar says "macOS 26.3 blocked the native XDR algorithm" and fell back to tone-mapping. Enhance Contrast was disabled because 26.3 blocked it. [V vendor changelog] https://lunar.fyi/changelog (v6.9.6). There is also a "macOS 27 crash fix" (v6.11.0), with no detail.
- BetterDisplay recommends "Direct brightness control and XDR upscaling" plus "Force EDR mode" on 27, rather than a color-table approach. [O] discussion #5814. One 27 beta 8 report: the built-in XDR display ignored app-driven HiDPI, XDR and headroom changes (M1 Pro, unresolved). [O] https://github.com/waydabber/BetterDisplay/issues/5761
- Apple release notes list no EDR API change. [V] 27.0 notes.

### Display configuration / CGVirtualDisplay / DisplayServices / MonitorPanel / DDC
- 27.2 b4 known issue: "When an external display is connected, display settings might not be restored correctly, and the display arrangement might change" (188643179). [V] https://developer.apple.com/documentation/macos-release-notes/macos-27_2-release-notes
- 27.0 fixed: with two identical displays (same model and serial), the second one might not light up (176292156). [V] 27.0 notes (Thunderbolt). This matters for our EDID/serial matching.
- New native ultrawide support and persistent arrangements. [O, press] https://www.macrumors.com/2026/06/09/macos-27-golden-gate-gains-ultrawide-support/ (via mjtsai)
- Soft-disconnect races: on 27, display IDs re-enumerate (an external came back as a new ID). A safety guard that counts "physical displays" can misfire when a third-party virtual display exists. Match on a stable identifier (EDID UUID) and debounce. [O] https://github.com/waydabber/BetterDisplay/issues/5823
- CGVirtualDisplay: no Apple note. BetterDisplay 5.0.5 lists "exclusive virtual-screen configurations more reliably" and 5.1.1 "Display corner rounding is fixed after app-initiated layout changes". There are no reports of the private class being removed. [O/V vendor] releases URL. **[U]** that it is unchanged.
- IOAVService DDC: no 27 break reported. BetterDisplay 5.0.6 added per-display command queues, and 4.3.6 fixed a DDC capability-read hang. [V vendor] releases URL. **[U]** that it is unchanged.
- DisplayServices / MonitorPanel / CBBlueLightClient: no 27-specific reports found. **[U]**
- MonitorControl's maintainer says its code "doesn't compile properly in Xcode 27 with legacy OS support intact". This is a warning for our toolchain jump. [O] issue #1904

### Window switcher: Cmd-Tab symbolic hotkeys, SkyLight, AX
- No reports that `SLSSetSymbolicHotKeyEnabled`/`CGSSetSymbolicHotKeyEnabled` or `_SLPSSetFrontProcessWithOptions` changed on 27. AltTab 11.7–11.8 still ships Cmd-Tab takeover on 27. The 11.7.0 note "The macOS force-quit shortcut (⌘⌥⇧⎋) could get disabled or re-enabled unexpectedly" points to symbolic-hotkey restore bugs. Restore every hotkey we disable on exit or crash. [O] https://newreleases.io/project/github/lwouis/alt-tab-macos/release/v11.7.0 . **[U]** that the SkyLight calls are unchanged.
- **Mission Control / App Exposé detection changed on 27.** A WindowManager window at layer 19 now exists **off-screen while a normal window is focused**. AltTab 11.7's "is Exposé active" heuristic treated it as the shield, so the switcher never appeared. This was fixed in 11.8.0 (#6076). Stage Manager with multiple stages also triggered it. [O] https://github.com/lwouis/alt-tab-macos/issues/6076 , https://newreleases.io/project/github/lwouis/alt-tab-macos/release/v11.8.0
- AX quirks on 27: apps launched through a LaunchServices launcher that `exec`s another binary (e.g. Emacs builds) expose **no AX windows**. Rectangle and AltTab can't see them. [O] https://github.com/caldwell/build-emacs/issues/157 . Apps can be misclassified as windowless and leak through the Visible-Spaces filter. [O] https://github.com/lwouis/alt-tab-macos/issues/6028
- AX observer leak under process churn (`isTerminated` lags 1–3 s), giving 100% CPU and 57k Mach ports on 27. Check liveness with `kill(pid,0)`/`proc_pidinfo`, not `NSRunningApplication.isTerminated`. [O] https://github.com/lwouis/alt-tab-macos/issues/6051
- Fixed in 27.0: "When you exit a window from fullscreen mode using Mission Control, the window might be lost" (177660206). [V] 27.0 notes, Window Management. Users still report Mission Control and multi-monitor black-screen bugs. [O] https://github.com/Gabarsolon/missioncontrol-fix , mjtsai roundup.
- New: `NSApplication.PresentationOptions.disableScreenCornerInteractions` (27 SDK) disables Hot Corners. [V] 27.0 notes.
- Window corners are less rounded on 27, so the switcher panel needs corner fixes (AltTab #5757, #6053). [O]

### ScreenCaptureKit thumbnails (window switcher)
- See 1d. Use SCK only, since `CGWindowListCreateImage` returns grey. Expect a restart after the first grant. A Remote Desktop prompt is possible in edge cases. Throttle captures: AltTab 11.8 "Thumbnails are captured less often when Spaces change or windows close". [V]/[O] URLs above.

## 4. OSS breakage on 27 and fixes (summary table)

| Project | What broke on 27 | Fix / status | Tag |
|---|---|---|---|
| BetterDisplay | Pane renamed; Force system OSD API gone; Control Center key fight after wake; 27.2 new OSD; touch/menu-bar | 5.0.x–5.1.1: DC&DA wording, self-drawn OSD (rounded on 27.2), forward key-ups / ignore orphan repeats, compositor filter for M5 | [V] releases, [O] #5587 #5846 #5619 |
| MonitorControl | Old-style HUD on 27; black screens on wake with gamma + custom profile; Xcode 27 build issues | Workaround: avoid gamma table; no 27 release | [O] #1904 #1912 |
| Lunar | 26.3 blocked native XDR and Enhance Contrast; 27 crash | Tone-mapping XDR fallback (6.9.6); crash fix (6.11.0) | [V] changelog |
| AltTab | Switcher hidden (layer-19 WindowManager window); windowless misclassification; CPU leak; corners | 11.7.0 / 11.8.0; PR #6063 | [O] |
| DockDoor | AX permission/restart flow; input-access refusal | 1.40.2: restart after grant, release taps when refused | [O] changelog |
| Bartender / Ice / Hidden Bar / etc. | Menu bar is one window, so hiding by moving item windows is impossible | Ice dead (fork: Thaw); Bartender has a separate GG build; BTT partial | [O] publicspace, badgeify |
| Switcher3way / grabbr-hops / espanso | AX prompt not raised; no row added; freeze on revoke | Open pane directly + "+" guidance; tap hardening | [O] |
| Mac Mouse Fix | Synthetic gesture fields ignored | New lower-level event type (pre-release) | [O, press] |
| Hammerspoon / Rectangle / Karabiner | No 27-specific issues found in public trackers/notes | — | [U] |

## 5. Actionable changes for the Snaptic plan
1. **Permission UX:** use a single "Accessibility / Device Control and Data Access" step, labelled by OS version (`ProcessInfo.operatingSystemVersion.majorVersion >= 27`). Call `AXIsProcessTrustedWithOptions(prompt:true)` once, **and always** open `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`, with "+"-add instructions and the app path. Poll `AXIsProcessTrusted()` and prompt for a relaunch after grant. Never read TCC.db.
2. **Event taps:** keep the session taps for keyDown/flagsChanged and NX_SYSDEFINED (DC&DA). Add a tap watchdog: on `kCGEventTapDisabledByTimeout`/`ByUserInput`, re-check trust before re-enabling. Use a breaker, keep the callback non-blocking, and invalidate on stop. For media keys, **forward key-up events and ignore orphan auto-repeats** so Control Center doesn't fight us. Use `CGGetEventTapList` to detect competing taps.
3. **Carbon hotkeys** stay permission-free and work under Secure Input. Prefer them for custom Display shortcuts. Avoid Option-only or Shift-only combos.
4. **OSD:** don't depend on OSDUIHelper/OSDManager. Ship a self-drawn OSD with a 27.2 "rounded segmented" style, and keep the legacy path only as a ≤26 option.
5. **Menu bar:** assume our item may be hidden in the overflow or by the user. Expose every function through the CLI socket, AppleScript, a global hotkey and a re-open-settings path. Don't rely on `button.highlight`, occlusionState or right-click on 27. Use the stock `button` plus `menu`, not a custom view or event monitors. Consider a 27 SDK build later for `expandedInterfaceDelegate` (runtime-guarded).
6. **Thumbnails:** SCK only (CGWindowListCreateImage returns grey). Expect a relaunch after the Screen Recording grant. Throttle captures.
7. **Gamma on M5 Pro/Max/Neo:** detect a no-op (set, then verify visually or via a heuristic). Fall back to an overlay or Metal dimming, and document that full-screen overlays block Touch ID / secure UI.
8. **Displays:** key display identity on EDID/UUID, not CGDirectDisplayID. Debounce reconfiguration callbacks (27.2 arrangement-restore bug).
9. **Window switcher:** audit any Mission Control/Exposé heuristic that uses WindowManager windows by layer (require on-screen bounds). Check process liveness with `kill(pid,0)`. Restore symbolic hotkeys on every exit path.

## Blocked / unfetched sources
- https://support.apple.com/guide/mac-help/mh43185/27/mac/27 and https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac (permission prompt timed out)
- https://mastodon.social/@lapcatsoftware/117275011730278878 (permission timed out; content quoted via mjtsai)
- https://developer.apple.com/forums/thread/844416 and https://github.com/deskflow/deskflow/issues/10204 (fetch errors)
- https://developer.apple.com/documentation/macos-release-notes/macos-27_1-release-notes.md (fetch error)
