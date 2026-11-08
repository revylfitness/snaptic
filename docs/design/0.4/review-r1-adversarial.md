# 0.4 plan review r1: Adversarial (failure modes, races, security, privacy)

Reviewer: adversarial subagent. Input: `PLAN-draft.md` (r1, 321 lines), Hidden Bar source at `/tmp/hidden-src/repo`,
the Snaptic tree at `acbd102`, and a read-only runtime probe of `MenuBarClientCore` and `MenuBarAgent` on this Mac
(Darwin 27.2.0). The probe is in `/tmp/mbadv/` (`probe.m`, `probe.out`, `core_cstrings.txt`, `agent_strings.txt`,
`aa_strings.txt`). It only lists classes, ivars, selectors and strings. **No configuration or assertion object was
ever created, and nothing was activated.** The owner decisions Q1–Q6 are taken as settled. These findings are about
how the plan carries them out.

Severity counts: **2 Blockers, 14 Majors, 10 Minors.**

## What the probe shows about `MBAssessmentModeAssertion` (context for the findings)

- **A thin ObjC wrapper over a Swift client.** `MBAssessmentModeAssertion` has two ivars, `assertion` and
  `configuration`, and three activation selectors: `activateWithCompletionHandler:`, `activate:completion:` and
  `activateWithConfiguration:completionHandler:`. The work is done by the Swift class
  `MenuBarClientCore.VisibilityRestrictionAssertion`, which has the ivars `id`, `menuBarItems`, `serviceQueue` and
  `sessionState`. It conforms to `MBVisibilityRestrictionXPCClient` and implements
  `visibilityRestrictionsDidChange:` (probe.out 451–459). The framework's strings include
  `withServerThrowingContinuation(_:)`, `withActiveSession(timeout:clock:action:)` and
  `Invalid number of keys found, expected one.` (core_cstrings 20, 41). In other words, it's Swift concurrency over
  XPC. A Swift trap or a misused continuation inside the framework **can't be caught by the shim's
  `@try/@catch`**.
- **It talks to MenuBarAgent, not to the WindowServer.** The XPC service is `com.apple.MenuBarAgent.visibility-restriction`
  (core_cstrings 38). The server is `MenuBarCore.VisibilityRestrictionServer`, which rejects bad input with
  `Passed item identifiers should be strings, or both nil for unrestricted menu bar items` (agent_strings 7142). The
  agent's state model keeps `isInAssessmentMode`, `isUserSessionTransitioning`, `hasExternalRestrictions`,
  `hasAnyRestriction` and `assessmentMenuBarItems` alongside `liveActivities`, `systemBanners`,
  `presentedSystemBanners`, `presentationRoles` and `campo` (agent_strings 9360–9380). The restriction is one input
  to the pipeline that also routes Live Activities, system banners and Campo (⌘-drag), so it can affect them.
- **Snaptic isn't the only client.** `MBLockScreenMenuBarConfiguration` and `MBUserSessionTransitionAssertion`
  restrict the same bar (lock screen and fast user switching). The real exam daemon `/usr/libexec/assessmentagent`
  holds the same kind of assertion (`AEAMenuBarAssertionPrimitives`, `com.apple.assessment.menubar.restrict` /
  `.release`, `Activating MenuBar assertion:`; aa_strings 489–660, 768, 997, 3376). That daemon also locks down
  Siri, screenshots, the Dock, Spotlight, the share sheet, force quit, keyboard shortcuts and more, but those come
  from other primitives. **Snaptic would only take the menu-bar slice.**
- **No entitlement seems to be needed for this service.** The only client-side entitlement strings are for other
  services (`com.apple.private.menubar.can-hide-attached-av-module`, `com.apple.private.menubar.utilities`). The agent
  does have a generic `Connection missing entitlement` path, but Hidden Bar works as an ordinary signed app. **Any
  process running as the user can already hide anything.** Snaptic's CLI therefore gives a local attacker no new
  ability to hide items (X-21).
- **On 27, privacy indicators are drawn by MenuBarAgent, and the AV module attaches to an app's item.** The agent has
  the strings `PrivacyIndicator`, `privacyIndicators`, `privacyIndicatorTrailingInset`, `AVModuleAttachedKey`,
  `avModuleAssociatedBundleID(s)` and `com.apple.MenuBarAgent.hide-attached-av-module` (agent_strings 4681, 6528,
  6546, 7754; core_cstrings). Whether hiding an app's bundle also hides the AV/privacy module attached to it is
  **unverified**. X-6 makes it an S0 gate.
- **macOS 27 has its own overflow indicator.** The strings are `menu-bar-overflow-indicator` and
  `com.apple.ec.MenuBar.overflow.indicatorShown` (agent_strings 6161, 6550).
- **"interrupted" states exist.** The strings are `interrupted before collapse completed` and
  `interrupted before becoming visible` (agent_strings 6493–6495). Restrictions can be interrupted by something
  outside Snaptic.

---

## Blockers

### X-1 [Blocker] A hung main thread keeps the icons hidden with no way out except force quit

**Plan section:** Q5 ("failing open"), §1 table ("the restriction ends when the process dies"), §6 risk row 2, H6.

**Scenario:**
1. On macOS 27 the bar is collapsed, so Native holds assertion N.
2. Snaptic's main thread blocks: a slow AX call on main, a deadlocked display reconfiguration, a hung
   `NSAlert`/panel, or any of the hang classes that `HostHeartbeat` exists to detect.
3. The process is still alive, so MenuBarAgent keeps the restriction. The arrow can't respond because its action
   runs on main. The auto-collapse timer, the CLI (handlers run on main) and the hotkey are all dead.
4. **Result:** every hidden item stays unreachable until the user knows to force-quit Snaptic. Some of those items
   matter: VPN status, a backup tool's error badge, a security agent, Little Snitch alerts. "Fails open" only holds
   for process death, and a hang isn't death.

**Evidence:**
- Hidden Bar holds the assertion in-process with no watchdog (`NativeVisibilityEngine.swift`; `Handle.deinit` only
  runs on deallocation, `NativeVisibilityBridge.swift:57`).
- Snaptic already accepts that its main thread can hang. `HostHeartbeat` stamps every 0.5 s so helpers can read
  `mainAgeMillis()` from any thread (`Core/HostHeartbeat.swift:40–46`). `EmergencyActions` exists for "actions that
  must run even if the main thread is hung" (`Core/EmergencyActions.swift:3–4`), and lid-closed mode registers one
  (`Awake/Core/LidClosedController.swift:345`).
- The plan uses neither for Hidden Icons.

**Proposed fix (plan text, add to §4.1 and H6):**

> **Hang fail-open (Native).**
> - `NativeEngine` keeps the raw assertion in a lock-protected box that is reachable off-main.
> - A dedicated low-priority watchdog thread, which exists only while an assertion is held, reads
>   `HostHeartbeat.mainAgeMillis()` every 500 ms. If the age passes 3000 ms, it calls `invalidate` on the held
>   assertion from that thread, sets a `hangExpanded` flag, and counts `icons.hangExpand`.
> - When main recovers, the engine sees `hangExpanded`, moves to `.expanded` and doesn't re-collapse until the user
>   or the timer asks.
> - `NativeEngine` also registers `EmergencyActions.add("hidden icons")`, which invalidates the held assertion, so
>   the SIGTERM/signal path expands too.
> - **S0 must verify** that `-invalidate` is safe to call off-main and while main is blocked. The Swift object has
>   its own `serviceQueue`, which suggests it is. If it isn't, the assertion moves to a helper process instead
>   (`HelperKind.iconsHost`, the same executable as the other helpers). The helper drops the assertion and exits
>   when the parent's heartbeat stops for 3 s or the parent pid goes away.
> - **Length engine:** `NSStatusItem.length` is main-thread-only, so a hang can't be undone there. README Known
>   limitations: "If Snaptic stops responding while icons are hidden on macOS 14–26, force-quit it and they
>   return."
> - K2 adds a test: a fake clock drives the heartbeat age past 3 s and the fake visibility port sees `invalidate`
>   exactly once.

### X-2 [Blocker] A trap in the private framework at collapse-at-launch loops forever, and Safe Mode doesn't stop it

**Plan section:** §2 (`SNMenuBarVisibility … @try/@catch`), §4.5 "Collapse at launch: 1 s after the module starts",
H3, H6, §6 risk row 1, D1 (Undocumented APIs wording).

**Scenario:**
1. A 27.x update changes the Swift client. For example, `menuBarItems` decoding now enforces "expected one key",
   or a continuation is resumed twice, and it traps instead of returning an error.
2. Snaptic launches. One second after the module starts, it collapses and calls `activateWithConfiguration:` →
   `EXC_BREAKPOINT`. `@try` doesn't see Swift traps.
3. The user relaunches, and it crashes again. After 2 unstable launches, `LaunchStability` puts Snaptic in Safe
   Mode.
4. Safe Mode doesn't skip Hidden Icons: `SafeMode.skipped` (`Core/SafeMode.swift:19–28`) covers only Displays and
   Awake features. So the module starts in Safe Mode, collapses at 1 s and crashes again. **Result:** a permanent
   crash loop. The only escape is a `defaults write` of a kill switch the user doesn't know exists.
5. The same loop happens if `MenuBarAgent` crashes on our configuration and takes the menu bar down with it on
   each attempt.

**Evidence:**
- The framework is Swift with throwing continuations (core_cstrings 41).
- Hidden Bar's shim wraps only the ObjC send in `@try` (`HBNativeVisibilityShim.m:57–70`).
- The README promises that private APIs "fail closed: … the feature that needs it becomes unavailable instead of
  crashing" (README §Undocumented APIs, line 888). That holds for missing symbols, not for traps behind a symbol
  that resolves.
- §6 lists only "runtime resolve + selector check + `@try`" as the mitigation.

**Proposed fix (plan text, H6, §4.1, H3, D1):**

> **Activation crash guard.**
> - Before every `activate…` call, `NativeEngine` writes an in-flight marker:
>   `Icons.native.inFlight = "<OS build>"` in Snaptic's own defaults, flushed synchronously.
> - It clears the marker in the completion, or after the 3 s activation timeout (X-3).
> - At launch, a marker that is present and matches the current OS build means the last activation never returned.
>   Native is then disabled for this OS build (`Icons.native.disabledBuild = <build>`). The module shows "Hiding
>   isn't available on this macOS build. It stopped Snaptic last time." and gives one notice.
> - A new OS build clears `disabledBuild`, so the module tries again.
>
> **Safe Mode.**
> - `SafeMode.skipped` gains "Hiding menu bar icons". In Safe Mode the Hidden Icons module stays off. Its items
>   aren't created, and no assertion or length change is made.
> - The arrow doesn't appear, and the Safe Mode page lists the module.
>
> **Launch collapse** is skipped on the first launch after a Snaptic version change or an OS build change, and in
> any launch that `LaunchStability` marks as unstable.
>
> **D1 wording.** The Undocumented APIs paragraph gains: "Hidden Icons on macOS 27 fails *open*. If the system call
> is missing, fails, or stopped Snaptic last time, nothing is hidden."

---

## Majors

### X-3 [Major] Edge cases in the completion contract: never called, called twice, called after `invalidate`

**Plan section:** §2 (`NativeEngine … generation counter, activate-then-invalidate`), §4.1 Native steps, §4.7 CLI,
K2.

**Scenarios:**
- **(a) Never called.** MenuBarAgent is wedged, or the XPC lookup fails silently.
  - The state stays `calibrating` forever. Every later toggle is ignored or queued.
  - `snaptic icons hide` waits for the engine. If the handler only replies after completion, the connection holds
    one of the 4 `ControlServer` slots until the 2 s read timeout, or indefinitely if the reply is deferred. Four
    calls lock out every CLI verb, including `awake` and `displays`.
  - The assertion object exists only inside the in-flight block. No `Handle` exists yet, so nothing can invalidate
    it. If the server later activates it, the restriction is live and Snaptic doesn't know.
- **(b) Called twice**, for example an error and then success, or once per `visibilityRestrictionsDidChange`.
  - Hidden Bar's shim calls `finish` once per call (`HBNativeVisibilityShim.m:51, 69`). Each call creates a new
    `Handle` around the **same** raw object.
  - When the first handle is replaced and deallocates, `deinit → invalidate` drops the live restriction (in the
    "fail open" direction, but the state says collapsed). Or the generation check discards the second call and its
    `Handle` deinit invalidates the restriction that is in use.
- **(c) Completion after `invalidate`, or after `stop()`.**
  - Expand or `stop()` runs while activation N+1 is in flight. The generation check "drops" the stale completion.
  - Dropping the object without invalidating it relies on `dealloc` releasing the server assertion, which is
    unverified.
  - **Result:** icons are hidden after the user chose Show, or after Snaptic "expanded first" on quit (H6).
- **(d) Completion off-main.** The Swift client completes on its `serviceQueue`. Hidden Bar hops to main, and the
  plan doesn't say whether Snaptic does.

**Evidence:**
- `VisibilityRestrictionAssertion` has one `sessionState` and an `id`, and the server API takes an assertion ID
  (agent `acquireAssertionWithID:origin:…`). Hidden Bar's bridge creates a `Handle` per completion
  (`NativeVisibilityBridge.swift:45–60`).
- The plan says only "A stale completion (generation mismatch) is dropped."

**Proposed fix (plan text, §4.1 and B1):**

> **Shim contract (`SNMenuBarVisibility`).**
> - The shim owns every raw assertion from creation to invalidation, in a table keyed by a shim token (a
>   monotonically increasing `uint64`). Swift never holds the raw object.
> - Completion is delivered **at most once** per token. An atomic flag guards it, and extra calls are counted
>   (`icons.dupCompletion`) and ignored.
> - Completion is always delivered on main.
> - `SNMenuBarVisibilityActivate` returns the token synchronously, so a token that is in flight can be invalidated
>   at any time.
> - If a completion arrives for a token that is already invalidated or stale, the shim invalidates that raw object
>   **immediately** and never hands it to Swift. Dealloc is never relied on to release a restriction.
> - **Timeout:** with no completion after 3 s, the engine invalidates the token, moves to `.failed(timeout)`,
>   leaves the bar unrestricted, and counts `icons.activateTimeout`. After 2 timeouts in a row, Native is unavailable
>   until relaunch.
> - **CLI:** `icons show|hide|toggle` replies once the intent is queued, or after at most 1 s. It never holds a
>   connection while waiting for the framework.
> - K2 adds fake-port cases for: never completes; completes twice; completes after invalidate; completes after
>   `stop()`; completes with an error and then success.

### X-4 [Major] "Activate N+1, then invalidate N" is unverified, and two hiders (or exam software) may fight

**Plan section:** §4.1 step 4, §4.4 (allow-list grows while collapsed), §6 "Two hiders running".

**Scenario:**
1. While collapsed, a new app launches, so §4.4 adds it to the allow-list and re-activates with N+1.
2. If MenuBarAgent keeps **one** assessment-origin restriction per client or per origin (`isInAssessmentMode` is a
   single Bool and `assessmentMenuBarItems` a single list, agent_strings 9374–9379), one of three things happens:
   - (i) N+1 is rejected while N is held, so every reconfiguration fails;
   - (ii) N+1 replaces N, and invalidating N then clears the shared state, so everything reappears while Snaptic
     thinks it's collapsed;
   - (iii) the last writer wins between processes.
3. Under (iii), Hidden Bar or another hider that uses the same API and runs next to Snaptic makes the bar flip
   between two allow-lists. `OtherAppsMonitor` warns, but doesn't prevent it.

**Evidence:** The server state shape is above. The plan's S0 tests only "allow-list `[]` + `[Finder]` for 5 s". It
never tests a second activation while one is held.

**Proposed fix (plan text, S0 and §4.1):**

> **S0 adds:**
> - (1) Activate A (Finder allowed), then B (Finder + Safari allowed), then invalidate A. Safari is visible and
>   Finder stays visible.
> - (2) Activate A, then B. Invalidate B. Check whether A's restriction comes back or the bar is unrestricted.
> - (3) Two processes each hold one, then each releases. Record whether the effective set is the union, the
>   intersection, or last-writer-wins.
>
> The engine's reconfiguration strategy follows the result. If the server replaces N, the engine skips the separate
> `invalidate(N)` and only drops the token. If it rejects N+1, the engine invalidates N first and accepts a ≤1-frame
> flash.
>
> If test (3) shows last-writer-wins, Native refuses to collapse while a known MenuBarClientCore hider
> (`com.dwarvesv.minimalbar`, Ice/Thaw on 27) is running. The arrow shows "Another app is hiding icons".

### X-5 [Major] When MenuBarAgent restarts or the restriction is interrupted, Snaptic's state is wrong

**Plan section:** §4.1, §2 `IconsMonitors` (workspace launch/terminate only for apps).

**Scenario:**
1. MenuBarAgent crashes or is relaunched. This can happen on 27.x updates, after a crash caused by any app's
   configuration, or with `killall MenuBarAgent`.
2. The XPC connection is lost. Depending on the client:
   - (a) the restriction is dropped and Snaptic still shows collapsed. The arrow says ‹ and the auto-collapse timer
     doesn't run, so the bar stays full until the user clicks twice; or
   - (b) the Swift client silently re-acquires the restriction with its stored `menuBarItems` after Snaptic expanded,
     so icons are hidden while Snaptic says "shown".
3. Neither case is reported to Snaptic, because `visibilityRestrictionsDidChange:` isn't part of the ObjC
   assessment API.

**Evidence:**
- The client has `serviceQueue`, `sessionState` and `visibilityRestrictionsDidChange:` (probe.out 451–459).
- The agent has "interrupted before collapse completed" and "interrupted before becoming visible" (agent_strings
  6493–6495).

**Proposed fix (plan text, §4.1 and A3):**

> - `IconsMonitors` watches `com.apple.MenuBarAgent` through `NSWorkspace` didLaunch/didTerminate (bundle id match).
>   Bundle ids can be faked, so it also checks that the app's executable path is in `/System/Library/CoreServices/`.
> - On terminate, the engine invalidates every token and moves to `.expanded(reason: agentRestart)`.
> - On launch, after 2 s, it collapses again only if the user's last intent was "hidden" and the bar was collapsed
>   before the restart.
> - After every expand, the engine invalidates **and** releases the token, so the framework has nothing to
>   re-acquire.
> - S0: `killall MenuBarAgent` while collapsed and while expanded. Record whether the restriction survives and
>   whether it comes back after an expand.

### X-6 [Major] Privacy indicators and the AV module might be hidden along with their app, and the system-item range is assumed

**Plan section:** §1 table ("system items 0..<63"), §4.1 step 3, §6 risk row 3 ("Control Center, notifications").

**Scenario:**
1. The user puts Zoom in the hidden section and collapses.
2. On 27, the AV module (mic and camera in use) can attach to the app that uses it (`AVModuleAttachedKey`,
   `avModuleAssociatedBundleID`).
3. If MenuBarAgent hides the attached module along with its `us.zoom.xos` item, **the user loses the mic or camera
   indicator while the app records**. Snaptic's README positions it as a safety-first tool, so it can't make
   recording invisible.
4. Separately, `0..<63` is a number copied from Hidden Bar, not an enum Snaptic can check. If 27.x adds a system
   item with an ID ≥ 63, it is hidden for every user and nobody asked for it.

**Evidence:** The agent strings are listed above. The plan's §6 lists only "Control Center, notifications" as
side-effect checks.

**Proposed fix (plan text, S0, §4.1 and D1):**

> **Hard rule: Hidden Icons never hides a privacy indicator.**
>
> **S0 gate:** while the app that owns them is in the hidden section and the bar is collapsed, check:
> - the camera indicator (FaceTime);
> - the mic indicator (Voice Memos);
> - screen recording (`screencapture -v`);
> - location (Maps).
>
> **If any of them disappears**, the plan changes before K2: the Native allow-list always includes every running
> app that currently holds an AV or screen-capture session, found through the public `AVCaptureDevice` "in use by
> another app" query where available. Otherwise Native is limited to never hide apps in a user-maintained "may
> record" set. The README states the result either way.
>
> **System items.** Allow every value of the configuration's system-item domain. S0 records the real range by
> reading what the configuration's `allowedSystemItems` returns for `0..<256`, without activating, to see whether
> the init clamps or rejects values. The engine sends that full range.
>
> **Runtime check:** after each collapse, if any extra owned by a system owner (`com.apple.controlcenter`,
> `com.apple.systemuiserver`, `com.apple.MenuBarAgent`) that was visible before collapse is now missing from the
> inventory, the engine expands, records `icons.systemItemHidden`, and disables Native for this OS build.

### X-7 [Major] Assessment mode may restrict more than icons: ⌘-drag, Live Activities and banners, and real exam sessions

**Plan section:** §6 risk row 3, Q3 ("⌘-drag … arrange"), §4.4 ("stays shown until the user ⌘-drags it").

**Scenario:**
1. **⌘-drag.** The agent's state couples `isInAssessmentMode` with `campo` and `isCampoDraggingOut`. It has
   `com.apple.private.menubar.disable-user-hiding` and `allow-scene-disable-user-hiding`. If assessment mode turns
   off user rearranging, which is plausible because that is exactly what exam mode wants, then:
   - the user can't ⌘-drag while collapsed;
   - §4.4's "stays shown until the user ⌘-drags it into a section" is impossible until they expand;
   - with Always Hidden on (X-8), the bar is **never** unrestricted, so the user can never rearrange.
2. **Live Activities and system banners.** These are routed by the same pipeline (`RouteLiveActivitiesStep`,
   `SuppressForegroundAppLiveActivitiesStep`, `RouteSystemBannersStep`, agent_strings 3495–3509). Exam mode suppresses
   them. If the menu-bar slice does too, the user silently loses timers, calls and delivery Live Activities in the
   bar whenever the icons are hidden. Hidden icons are the *default* state.
3. **Real exam software.** A student starts an `AEAssessmentSession` exam (`assessmentagent`). If the server keeps one
   assessment restriction (X-4):
   - Snaptic's next collapse **replaces the exam's allow-list with Snaptic's**, so it un-hides items the exam hid;
     or
   - Snaptic's expand/`invalidate` **lifts the exam's restriction**.
   Either way Snaptic breaks a proctoring guarantee. That is an integrity problem and could become a support story.

**Evidence:** The agent and assessmentagent strings are cited in the context section. The plan's S0 checks only
reflow and recovery.

**Proposed fix (plan text, S0 and §4.1):**

> **S0 side-effect checklist, while collapsed with an allow-list that includes Finder:**
> - (a) ⌘-drag an allowed item, and ⌘-drag the arrow.
> - (b) System Settings › Menu Bar can still change items.
> - (c) Start a Clock timer and a FaceTime call, and check that their Live Activity or menu-bar module appears.
> - (d) A notification banner appears.
> - (e) Control Center and Notification Center open.
> - (f) Spotlight, screenshots and the Dock work.
> - (g) The overflow indicator still appears with many items.
>
> Each result goes in STEP0-NOTES. Any lost feature goes into README Known limitations, or changes the design.
>
> **Exam guard.** While the `assessmentagent` process is running *and* the frontmost app holds an assessment session
> (best effort: the process is present and `com.apple.assessment` is active), Native expands, makes no activation
> calls, and shows "Paused during an exam session". When the session ends, it resumes.
>
> S0 tests a real `AEAssessmentSession`, using a 30-line test app with the entitlement if obtainable, or Safari's
> AAC exam page, against a Snaptic collapse and expand.

### X-8 [Major] With Always Hidden on Native, the layout cache never refreshes

**Plan section:** §4.1 ("While something is collapsed, the layout comes from the cache, because only an
unrestricted bar can be read"; "Native excludes the always-hidden bundles even while the hidden section is
expanded").

**Scenario:**
1. The user turns on Always Hidden, so the bar is never unrestricted.
2. Every inventory read sees only the allowed items. Items the user ⌘-drags (if that's even possible, X-7) can't be
   observed. Apps that update and change their extras can't be observed either.
3. The cache freezes at the moment Always Hidden was turned on. New-icon handling and the hidden-icon list run on
   stale data, and positions drift.
4. This is Hidden Bar's always-hidden cluster: #171, #224, #242 (permanent icon loss) and #288 in `docs/BACKLOG.md`.

**Evidence:** In Hidden Bar's `NativeVisibilityEngine`, the expanded presentation with Always Hidden still activates
a restriction, so it never refreshes.

**Proposed fix (plan text, §4.1):**

> **Layout refresh points (Native).** The cache refreshes only from an unrestricted read, taken at these moments:
> - (1) ⌥-expand-all, which is unrestricted;
> - (2) Settings › Sections preview "Refresh", which expands all for up to 1.5 s, reads, then restores the previous
>   state;
> - (3) once at module start, before the first collapse.
>
> The cache records `readAt`. The Settings status row says "Positions last read 3 days ago — ⌥-click the arrow to
> refresh" once the cache is more than 24 h old and Always Hidden is on. The engine never infers positions from a
> restricted read.

### X-9 [Major] The AX inventory has no per-app or total budget, and unknown or timed-out apps are hidden

**Plan section:** §2 `AXInventory.swift` ("background queue, 0.1 s timeout"), §1, §4.1 step 1–3.

**Scenario:**
1. Hidden Bar sets the 0.1 s timeout on the **application element only** (`AccessibilityMenuBarInventory.swift:56`).
   It then reads `kAXChildrenAttribute` on the extras bar, and position and size on each child, through elements
   that keep the system default timeout of about 6 s.
2. A hung Electron app with 3 extras costs about 6 s per attribute, so collapse stalls for tens of seconds. Hidden
   Bar's own comment measured about 18 s before the fix (`:53–55`).
3. A hostile app can report thousands of `AXExtrasMenuBar` children, which makes the walk unbounded.
4. Any app that times out or fails is simply **missing**. Native hides everything not on the allow-list, so a hung
   app's icons, which the user placed **visible**, get hidden. That fails closed against the user's intent.
5. Hidden Bar keeps only `.app` bundles with non-nil ids. Menu-bar agents shipped as bare executables or
   `LSUIElement` helpers inside `.app/Contents/Library` are hidden without being listed. That is also how a malware
   persistence item would look, so hiding it is the wrong direction.

**Evidence:**
- Snaptic's switcher already solved this. It uses `axTimeout 0.15`, `perAppBudget 0.5`, `totalBudget 1.2` and
  `maxWindowsPerApp` (`Switcher/WindowManager.swift:170–176, 353–370`), and sets the timeout on **every** child
  (`:366–370`, `WindowGatherer.swift:86–89`).

**Proposed fix (plan text, §2 and A2):**

> `AXInventory` reuses the switcher's budgets:
> - 0.15 s messaging timeout set on the app, the extras bar **and each child**;
> - 0.5 s per app and 1.2 s in total;
> - at most 50 extras per app;
> - positions read with one `AXUIElementCopyMultipleAttributeValues` call per child.
>
> Every app gets a result: `.ok(items)`, `.timedOut`, `.noExtras`, `.denied`.
>
> When building the allow-list, an app that is `.timedOut` or unread keeps its **cached** section. If it has none,
> it is **allowed** (visible). A failed read never hides anything.
>
> Apps aren't filtered to `.app`. Every `NSRunningApplication` with a bundle id and an activation policy other than
> `.prohibited` is read, and processes without a bundle id can't be targeted by the API anyway, so they are listed
> as "not hideable".
>
> K1 tests: a timed-out app keeps its cached section; an unknown app stays visible; 51 extras are cut at 50.

### X-10 [Major] Collapsing at login, before the inventory is stable, hides icons the user placed visible

**Plan section:** §4.5 "Collapse at launch: 1 s after the module starts", §4.4 ("didLaunchApplication, observed only
while collapsed").

**Scenario:**
1. Snaptic is a login item. One second after the module starts, the inventory runs while half the login items are
   still starting, and the AX tree for `controlcenter` and the extras isn't populated yet.
2. Collapse builds the allow-list from that partial read, plus the cache.
3. Apps that were **already running** but create their extra 5–30 s later get hidden. This includes Dropbox,
   1Password, iStat and VPN clients. §4.4 only watches `didLaunchApplication`, which already fired before the
   module started.
4. With the "Show until I move them" policy, the user still sees their visible icons disappear at every login. This
   is the #1 complaint (icon drift) in a new form.

**Evidence:** The icon-drift cluster in Hidden Bar's `docs/BACKLOG.md`: #28, #156, #181, #230, #231, #239, #252,
#254, #275, #283, #321 and #334.

**Proposed fix (plan text, §4.4 and §4.5):**

> **Stable-inventory gate.** Launch collapse waits until two inventory reads 2 s apart return the same set of
> (bundle, count) pairs, and until the uptime is more than 60 s. It gives up after 30 s and collapses anyway.
>
> **New-icon detection** compares each inventory read against the known set, instead of relying on
> `didLaunchApplication`. Any bundle seen for the first time, whether from a new launch or a late extra from a
> running app, follows the new-icon policy.
>
> While collapsed, the engine re-reads at +2 s, +10 s and +30 s after launch or wake, and on each
> `didLaunchApplication`. A restricted read can still see the allowed items, and new allowed items show up through
> the re-read loop.
>
> A known visible bundle that is missing from a read is **kept** on the allow-list until it is absent from 3
> unrestricted reads. A transient absence never demotes it.

### X-11 [Major] The Length engine can hide Snaptic's own arrow and its Awake indicator

**Plan section:** §6 row "Snaptic's own items" ("the user can still ⌘-drag them left"), §4.1 Length engine, A1
order seeding.

**Scenario:**
1. On macOS 14–26, the user ⌘-drags the `SnapticAwake` indicator or a module icon left of the separator. A
   corrupted `NSStatusItem Preferred Position Snaptic.icons.*` value can also swap the arrow and separator: Hidden
   Bar's drift cluster and #242 show positions do get corrupted.
2. Collapse pushes everything left of the separator off-screen.
3. **Result A:** the Awake indicator disappears while lid-closed mode or a session runs. The README promises "the
   guards and a visible indicator always stay" (README line 542, `indicator` ignored as a kill switch).
4. **Result B:** if the arrow is left of the separator, collapse hides the arrow itself. The user can't expand by
   clicking. Only the Snaptic menu or CLI can, and with Hidden Icons alone in the menu bar it may be hidden too.

**Evidence:** README line 542. Autosave names are `SnapticAwake` and `Snaptic.<moduleID>`. Hidden Bar has the
icon-drift and permanent-loss issues.

**Proposed fix (plan text, §4.1 Length and A1):**

> **Own-item order check (both engines, before every collapse).**
> - Snaptic reads its own status-item windows' frames. Its own windows need no AX.
> - The order must be: always-hidden < separator < arrow.
> - If the order is wrong, collapse is refused and the menu shows "Hidden Icons can't hide: the arrow is on the
>   wrong side of the divider. ⌘-drag the arrow to the right of |."
> - **Length:** if any Snaptic item (`SnapticAwake`, `Snaptic.<id>`) has midX < separator.midX, collapse still
>   happens. But while Awake has an active session or lid-closed mode, collapse is refused, with the notice "Your
>   Awake indicator is in the hidden section. Move it right of the arrow so it stays visible."
> - Reset All Settings and "Restore positions" in Advanced re-seed the three positions.

### X-12 [Major] H9/§4.9: collapsing deactivates Snaptic and refocuses a remembered app, which steals focus from Snaptic's other windows and from the user

**Plan section:** H9 (3 call sites), §4.9.

**Scenario:**
- **(a) Snaptic's own windows lose focus.**
  1. Full bar on expand is on. The user expands, and the Displays "Keep this change?" `ConfirmPanel` appears with
     its 15 s revert countdown (`Displays/Safety/ConfirmPanel.swift:88`).
  2. Ten seconds later auto-collapse fires. §4.9 runs `NSApp.deactivate()` and reactivates the remembered app.
  3. The confirm panel loses key, and the user's Return goes to the other app. The display change reverts, or the
     user acts on the wrong window.
  4. The same happens to the Sparkle update dialog (`UpdaterController.swift:182`), Backup's open and save panels
     (`Backup.swift:30, 63, 177`), `PermissionFlow` (`:248`), `SafeModeLeave`, `PreConfirmPresenter`, `PIPWindow`
     and the Awake `CustomSessionPanel`.
  5. H9 knows about 3 of the roughly 13 `NSApp.activate()` sites.
- **(b) The wrong app is refocused.**
  1. The user expands with app A frontmost, so A is remembered. They ⌘⇥ to B, or pick B in Snaptic's switcher, which
     focuses through `_SLPSSetFrontProcessWithOptions`.
  2. On collapse, Snaptic reactivates **A** and takes B away from the user mid-typing.
- **(c) Hover activates Snaptic without a click.** With hover-to-expand plus full bar, moving the pointer to the top
  of the screen while typing makes Snaptic active. **Keystrokes go to Snaptic**, and the frontmost app's menus
  disappear under the pointer.

**Evidence:** `grep -rn "NSApp.activate()" Sources` finds 13 sites outside H9's 3. Hidden Bar unconditionally runs
`NSApp.deactivate()` (`StatusBarController.swift:283`).

**Proposed fix (plan text, H9 and §4.9):**

> **H9 reasons are a set, and any Snaptic window can hold one.** `ActivationPolicyController.hold(reason:)` returns a
> token. Settings, onboarding, the full bar, every panel or alert presenter that calls `NSApp.activate()` (all 13
> sites, migrated in A3b), Sparkle's UI and the Backup panels each hold one while visible. lint flags any bare
> `NSApp.activate()` or `setActivationPolicy` outside the controller.
>
> **Collapse with full bar:**
> - It drops only the full-bar reason.
> - It calls `NSApp.deactivate()` only if Snaptic is active **and** no other reason is held **and** no Snaptic
>   window is key.
> - It reactivates the remembered app only if **no `didActivateApplication` for another app happened since expand**.
>   The remembered app is cleared on any such notification.
>
> **Hover never triggers the full bar.** Hover-expand is a plain expand. The full bar applies only to a click,
> hotkey or CLI expand.
>
> **Auto-collapse re-arm** also covers "any Snaptic window or panel is visible".
>
> Kit truth-table cases: confirm panel open × collapse; ⌘⇥ to B × collapse; hover × fullBar.

### X-13 [Major] The menu-open guard misses popovers and status-level panels, so items opened from the hidden list collapse under the user

**Plan section:** §4.5 ("CGWindowList layer ≥ `kCGPopUpMenuWindowLevel` touching the band"), §4.6 ("presses, and the
auto-collapse timer re-arms").

**Scenario:**
1. The user picks "Bartender-like app X" in the hidden-icon list. Native expands, AXPress runs, and X opens an
   `NSPopover`, or an `NSPanel` at `.statusBar` level (25) or `.floating` (3). Many menu-bar apps do this: 1Password,
   iStat, Fantastical and Dropbox.
2. The pointer moves into the popover, below the band, so the "pointer in band" re-arm ends.
3. The popover's layer is below 101, so the "pop-up menu" re-arm doesn't fire.
4. Ten seconds later, auto-collapse hides X's item. **Result:** on 27 the popover is orphaned or closes mid-use, and
   the user is cut off while typing a password.

**Evidence:** NSPopover and status panels don't use `kCGPopUpMenuWindowLevel`. §4.5 lists only three re-arm reasons.

**Proposed fix (plan text, §4.5 and §4.6):**

> **Re-arm reasons** also include:
> - any on-screen window at layer ≥ `kCGStatusWindowLevel` (25), or a `.floating` window whose owner pid owns an
>   extra, whose top edge is within 40 pt of the menu-bar band on the same display;
> - for 60 s after a hidden-list AXPress, and for as long as any window owned by the pressed app's pid is on screen
>   at layer > 0 near the band.
>
> All of this uses bounds and owner pid only. No titles are read, so no Screen Recording is needed.
>
> K3 tests each reason.

### X-14 [Major] The intents (click, hotkey, CLI, hover, timer, launch, Settings) aren't serialized; the debounce covers clicks only

**Plan section:** §4.2 (0.3 s debounce), §4.5, §4.7, K3, H6.

**Scenarios:**
- **(a) Toggles race within the debounce.** A CLI `icons toggle` and a hotkey arrive within 0.3 s. Both read
  `.collapsed` and both expand, or one toggles twice. Scripts like `snaptic icons hide; snaptic icons status`
  report the wrong state.
- **(b) A pending collapse beats Settings.** Launch collapse (1 s) fires while onboarding or Settings › Sections
  preview is reading positions. The read returns a restricted layout, which is cached as the truth.
- **(c) `stop()` races calibration.** `stop()` (H6: quit, Safe Mode, kill) runs while activation N+1 is in flight.
  The bar expands, then N+1 completes, and X-3(c) applies.
- **(d) The timer beats an expand.** The auto-collapse timer fires during an expand in the hidden-list flow (the
  ≤ 300 ms reflow poll), so it collapses before the press.

**Proposed fix (plan text, K3 and §2):**

> **One intent queue in Kit (`IconsPolicy`).**
> - Every source (click, hotkey, CLI, hover, timer, launch, hidden-list, Settings refresh, `stop`, `agentRestart`,
>   `hang`) submits an `Intent` with a source and a target state (`.shown`/`.hidden`/`.toggle`/`.all`).
> - The queue resolves `toggle` against the **target** state of the last accepted intent, not the observed state.
> - The 0.3 s debounce applies only to click sources.
> - `stop` cancels everything queued and preempts.
> - While the engine is `calibrating`, later intents collapse to the newest one.
>
> **Suppression windows:** launch collapse and the auto-collapse timer are suppressed while Settings › Sections
> preview, onboarding, or a hidden-list press is in progress.
>
> K3 race-matrix test: every pair of sources × engine states {expanded, calibrating, collapsed, failed}.

### X-15 [Major] Kill switch timing is unclear, and turning Native off mid-collapse may leave a restriction held

**Plan section:** H3, B1 ("kill switch read before every resolve"), K2 ("kill switch mid-collapse").

**Scenario:**
1. Snaptic's convention is that kill switches are read once at launch ("Quit and reopen to apply";
   `Core/ModuleHost.swift`).
2. B1 reads `Icons.disable.native` before every resolve, but a held assertion isn't a resolve.
3. A support person tells the user to `defaults write … Icons.disable.native -bool YES` because the bar is broken.
   Nothing happens until relaunch, and the plan's K2 case suggests it should.
4. If it is read live, a resolve that is skipped mid-collapse must still **invalidate**, otherwise the held N stays
   hidden with no engine to expand it.

**Proposed fix (plan text, H3):**

> Hidden Icons kill switches follow the launch-read convention: they are read at module start, and "Quit and reopen
> to apply" is documented.
>
> **One exception:** `Icons.disable.native` is also checked when the app becomes active and before every collapse.
> If set, the engine **invalidates every token first** and then becomes unavailable.
>
> K2 tests "kill switch set while collapsed → invalidate called, state unavailable, bar unrestricted".
>
> README's kill-switch table lists the `Icons` prefix with this exception.

### X-16 [Major] Privacy: rules for bundle ids and app names are missing for logs, the event log, errors and prefs

**Plan section:** §4.7 (status never prints names), H7 (backup excludes bundle ids), §4.8 diagnostics ("last error
code"), D1.

**Scenario:**
1. A shim `NSError` from MenuBarAgent can carry the configuration in `localizedDescription` or `userInfo`. The server
   echoes "item identifiers" in its errors. Hidden Bar logs the full visible and hidden bundle lists on every
   collapse (`NativeVisibilityEngine.swift:181`) and `error.localizedDescription` (`:207`).
2. A straight port puts the user's app list into Console, sysdiagnose and Snaptic's diagnostics export. The README
   promises that app names never leave the process (README line 731).
3. Prefs gain bundle ids through the new-icon allow-list, the per-app overrides (Q3) and the layout cache. These
   aren't "leaving the process" in the README's sense, but they are new persistent app-usage data, and the README
   says nothing about them.

**Proposed fix (plan text, D1, B1, A2):**

> **Privacy rules for Hidden Icons.**
> - (1) No `NSLog`/`os_log` contains a bundle id, an app name, or an `NSError` description from the shim. Only the
>   numeric error code and the domain hash are recorded: `EventLog` stores the code only, and diagnostics store
>   counts and codes.
> - (2) The shim maps every error to an `SNMenuBarVisibilityErrorCode` enum before it reaches Swift and drops
>   `userInfo`.
> - (3) The layout cache, the new-icon allow-list and the overrides live in one prefs key,
>   `Icons.items`. Reset All Settings and turning the module off with "Forget arrangement" clear it, and it is
>   excluded from backup export (H7) and diagnostics.
> - (4) README Privacy gains: "Hidden Icons stores the bundle identifiers of apps with menu-bar icons in Snaptic's
>   preferences on this Mac, to remember which section they're in. They're never logged, exported, or sent
>   anywhere."
> - (5) lint adds a rule: no `NSLog` in `Sources/Snaptic/Icons/` and no string interpolation of
>   `bundleIdentifier` into `EventLog`.

---

## Minors

### X-17 [Minor] AXPress on a stale element, or after pid reuse

**Plan section:** §4.6.

**Scenario:** The hidden list is built from the cached inventory, which holds `AXUIElement` + pid. The app quits and
its pid is reused by another app before the user picks the row. AXPress then goes to whatever element the new
process exposes at that index. It could also be a no-op, which is the AXPress defect in Hidden Bar's RUNBOOK.

**Fix (plan text):**

> When a row is chosen, the engine re-resolves the target. It finds `NSRunningApplication(processIdentifier:)`, and
> requires the same bundle id and the same `launchDate` as when the row was built. It then re-reads that app's
> extras with the X-9 budgets and matches them by index and frame within 4 pt. On any mismatch the row shows "That
> icon changed. Open the list again." and nothing is pressed. If AXPress returns success but no window appears within
> 500 ms, the engine counts `icons.pressNoop` and doesn't retry.

### X-18 [Minor] Length engine: very wide or virtual displays, Snaptic's own display trials, Stage Manager, an auto-hiding menu bar

**Plan section:** §4.1 Length.

**Scenarios:**
- `min(2×widest, 10 000)` leaks icons on a mirrored virtual display or a 1:1 6K setup wider than 5000 pt × 2.
- Snaptic's own Displays module (virtual displays, resolution trials with a 15 s revert) fires
  `didChangeScreenParameters` several times a second during a trial. Each one re-applies the length, which can make
  `NSStatusBar` relayout loops flicker.
- With an auto-hiding menu bar and Stage Manager, re-applying while the bar is hidden can be a no-op until it is
  revealed.

**Fix (plan text):**

> - The length is `max(500, 2 × sum of all screens' widths)`, with no upper clamp below 20 000.
> - Re-apply is coalesced to 250 ms after the last screen-parameter change.
> - Re-apply is skipped while a Displays trial is pending, and done once when it ends.
> - The manual checklist adds: auto-hide menu bar, Stage Manager on, an external display connected and disconnected
>   while collapsed, and Hidden Bar #351 (external monitor on 26.4).

### X-19 [Minor] The 27 overflow indicator and the notch: hidden-list scope

**Plan section:** §4.6, §1 `NotchOverflowController`.

**Scenario:**
- Hidden Bar uses `NSScreen.main` (`NotchOverflowController.swift:89`), so a notch on a non-main display is
  ignored.
- On 27, MenuBarAgent has its own overflow group and indicator. Items in that group aren't "notch-covered" by
  midX, and the hidden list double-counts them or misses them.

**Fix (plan text):**

> - Notch-covered items are computed per display, from the `NSScreen` whose frame contains the item's midX, using
>   that screen's `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`.
> - On 27, items whose AX frame is zero-sized or off-screen are listed as "in macOS's overflow" and aren't counted
>   as hidden by Snaptic.
> - S0 records how overflowed items appear in AX.

### X-20 [Minor] Sleep and wake, lock, fast user switching, display changes and Spaces with a restriction held

**Plan section:** S0, §6.

**Scenario:** `MBUserSessionTransitionAssertion` and `MBLockScreenMenuBarConfiguration` restrict the same bar.
Possible failures:
- After FUS away and back, Snaptic's restriction isn't reinstated, and the arrow says collapsed (X-5 class).
- Snaptic's restriction leaks onto the lock screen's trailing area.
- A full-screen Space's auto-revealed bar shows the restricted set (expected), but the hover monitor fires on
  reveal.

**Fix (plan text):**

> - S0 and the manual checklist cover: lock and unlock, FUS away and back, sleep and wake, connecting and
>   disconnecting a display, and a full-screen app reveal, each while collapsed.
> - On `NSWorkspace.sessionDidBecomeActiveNotification` and `didWakeNotification`, the engine re-syncs. It
>   invalidates, re-reads after 2 s, and re-collapses if the intent is hidden.
> - The hover monitor ignores pointer events in the first 1 s after a Space change.

### X-21 [Minor] CLI threat model: no new hiding ability, but override planting and blocked bundles need a stance

**Plan section:** §4.7, Q3 overrides, H7.

**Analysis:**
- The visibility-restriction service seems to need no entitlement, so any process running as the user can hide any
  item directly. `snaptic icons hide` adds nothing to that. The `ControlServer` (0600 socket, uid check, rate
  limit) is enough for show/hide/toggle/status.
- The new risk is **persistence through Snaptic**. A local process writes `Icons.items` overrides ("Always Hide"
  `com.objective-see.lulu`, `com.crowdstrike.falcon`). From then on Snaptic keeps the security tool's alert icon
  hidden, with Snaptic's trusted signature on the action.

**Fix (plan text):**

> - The CLI never edits overrides or sections. There are no `icons set` verbs, and the "never from the command line"
>   list in the README gains "Hidden Icons per-app overrides".
> - Backup import drops overrides (H7 already drops bundle ids).
> - Overrides are shown with a count on the main page ("2 apps always hidden") so planted ones are visible.
> - Privacy indicators (X-6) and system items can never be overridden.
> - **No bundle blocklist by default.** A list of "security tools" would be incomplete and a maintenance burden.
>   This is recorded as a decision.

### X-22 [Minor] Spoofed bundle ids

**Plan section:** §1 `MenuBarLayoutResolver` ("System owners and its own bundle are skipped").

**Scenario:** Any unsigned app can set `CFBundleIdentifier = com.apple.controlcenter` or `app.snaptic.Snaptic`. The
resolver skips it as a "system or own" owner, so it stays always visible and never appears in the sections list.
Most-visible-wins means a spoofer can't **hide** others. A spoofer that takes a bundle id the user allowed only
inherits visibility. The impact is cosmetic.

**Fix (plan text):**

> The system or own skip requires that the bundle id matches **and** that `NSRunningApplication.bundleURL` is under
> `/System/` (for system owners) or equals `Bundle.main.bundleURL` (for own). Otherwise the app is treated as a
> normal app. This is the same rule as the README's "App identity" note.

### X-23 [Minor] Quit, Sparkle relaunch and SIGTERM ordering

**Plan section:** H6.

**Scenario:**
- Sparkle's installer terminates Snaptic. If termination takes the `applicationShouldTerminate` path, `stop()`
  expands, which is fine.
- If it's SIGTERM or SIGKILL, process death releases the assertion (S0 verifies this), but the Length engine's
  layout may persist through the autosave. On the next launch it collapses at 1 s, before the new version is stable
  (X-2/X-10).
- `stop()` that "expands first" must not block termination on a framework call that never returns.

**Fix (plan text):**

> `stop()` calls `invalidate` with no completion wait and returns right away. An `EmergencyActions` entry (X-1)
> covers SIGTERM. Launch collapse is skipped on the first launch after a version change (X-2).

### X-24 [Minor] SelfTest `icons.shim` is the only automated check of the private API

**Plan section:** H8, B1.

**Scenario:** "Configuration builds with empty arrays" passes even if `activateWithConfiguration:completionHandler:`
changed its block signature, for example adding a returned token. Calling it with the wrong block type is a crash
(X-2).

**Fix (plan text):**

> SelfTest also checks the method's type encoding through `method_getTypeEncoding`. It must be `v32@0:8@16@?24`, as
> on 27.2 (probe.out 487), and for `invalidate` it must be `v16@0:8`. Any mismatch means "unavailable", not "try".
> The shim runs the same check at resolve time, which is Snaptic's existing "checked for the expected signature"
> rule.

### X-25 [Minor] The diagnostics "last error code" and the status row can show stale or misleading state after fail-open

**Plan section:** §4.8 Advanced diagnostics, §4.1 "one notice per launch".

**Scenario:** After X-1, X-3 or X-5 fail open, the status row should say why the icons came back. Without that, the
user sees the arrow flip and files "random un-hide" bugs, like Hidden Bar's drift reports.

**Fix (plan text):**

> The engine state carries `lastFailOpen: {reason: hang|timeout|agentRestart|killSwitch|systemItemHidden|crashGuard,
> at: Date}`. The Settings status row shows "Icons were shown automatically 2 min ago because the system's menu bar
> service restarted." Diagnostics include the counters `icons.hangExpand`, `icons.activateTimeout`,
> `icons.agentRestart`, `icons.dupCompletion` and `icons.pressNoop`.

### X-26 [Minor] Hover monitor cost and scope

**Plan section:** §4.5 hover.

**Scenario:** A global `.mouseMoved` monitor delivers every mouse event to Snaptic's main thread while collapsed. That
can be 1000 Hz on gaming mice, and it adds main-thread load, which matters for X-1.

**Fix (plan text):**

> The hover handler returns right away unless `event.locationInWindow.y` is within the band of the screen under the
> pointer, and it uses no allocation on that path. As an alternative, use a 24 pt tall, transparent,
> `ignoresMouseEvents = false` tracking window over the band, with `NSTrackingArea`. That gives no global monitor,
> but the window needs care on 27, so the monitor stays the baseline. The hover kill switch is already planned.

---

## Summary table

| ID | Sev | Area | One line |
|---|---|---|---|
| X-1 | Blocker | Fail-open | A main-thread hang keeps icons hidden. Add a heartbeat watchdog that invalidates off-main, plus an EmergencyActions entry |
| X-2 | Blocker | Private API | Swift traps escape `@try`. A crash at launch collapse loops into Safe Mode, which doesn't skip Hidden Icons. Add an in-flight marker, a Safe Mode skip, and fix the "fail closed" wording |
| X-3 | Major | Private API | Define the completion contract: shim-owned tokens, at most once, on main, a 3 s timeout, invalidate stale results immediately, and a CLI that doesn't hold slots |
| X-4 | Major | Private API | "Activate N+1, then invalidate N" is unverified against a single server-side assessment state. Two hiders may fight |
| X-5 | Major | Private API | A MenuBarAgent restart or interruption desyncs state. Watch the agent and re-sync |
| X-6 | Major | Privacy/safety | The AV/privacy indicator may hide with its app; 0..<63 is assumed. Make it an S0 gate and a hard rule |
| X-7 | Major | Side effects | Assessment mode may block ⌘-drag, Live Activities and banners, and conflict with real exam sessions. Add an S0 checklist and an exam guard |
| X-8 | Major | Native | With Always Hidden, the bar is never unrestricted and the cache never refreshes. Define refresh points |
| X-9 | Major | AX | No per-child timeout or budgets; failed or unknown apps are hidden. Reuse the switcher budgets and keep failed reads visible |
| X-10 | Major | Boot | Launch collapse runs before the inventory is stable. Add a stable gate and diff-based new-icon detection |
| X-11 | Major | Length | The Length engine can hide the Awake indicator (a README promise) or its own arrow. Add an own-item order check |
| X-12 | Major | H9/§4.9 | Collapse deactivates or refocuses over Snaptic's 13 other activate sites and the user's ⌘⇥; hover takes focus |
| X-13 | Major | Auto-collapse | The guard misses popovers and status panels, so a hidden-list press collapses under the user |
| X-14 | Major | Races | Intents aren't serialized. One Kit intent queue and a race-matrix test |
| X-15 | Major | Kill switch | It is unclear when `Icons.disable.native` is read. If read live, it must invalidate the held assertion |
| X-16 | Major | Privacy | No rules on bundle ids and NSError text in logs, the event log and diagnostics; prefs storage is undocumented |
| X-17 | Minor | AX | AXPress on a stale element or reused pid |
| X-18 | Minor | Length | Very wide displays, Displays trials, auto-hide and Stage Manager |
| X-19 | Minor | Notch | `NSScreen.main` only; the 27 overflow group |
| X-20 | Minor | Session | Lock, FUS, sleep and Spaces with a restriction held |
| X-21 | Minor | CLI | No new ability; block override planting; no blocklist (recorded decision) |
| X-22 | Minor | Spoofing | The system or own skip should check the bundle path |
| X-23 | Minor | Quit | `stop()` must not wait on the framework; SIGTERM path |
| X-24 | Minor | SelfTest | Check method type encodings, not just existence |
| X-25 | Minor | UX/diag | Explain fail-open events in the status row and counters |
| X-26 | Minor | Hover | Global mouseMoved cost on main |
