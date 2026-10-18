# Review round 2: fixes by team (lead)

Two fresh reviews of feature/displays @8819e85: a state/security re-review (findings N1–N11) and a
first-launch walkthrough (W1–W19). Round-1 items were verified fixed except where noted.
Lead already landed: N9 (identical exact names → ambiguous), DisplaysModule recomputes availability and
re-resolves when `ctx.permissions.observe` reports a change, "Not built yet" fallback text removed.

Each fix needs a test where the logic can live in Kit. The app target has no unit tests, so move
pure logic (state machines, correlation, mappings) into Kit and test it there.

## B
- **N1 BLOCKER: no trial can ever arm.** DisplayGuardClient `sendAndWait` waits for an ack keyed by a
  fresh `nextID`, but `armTrial`/`commitIntentAndWait` send the trial id and the guard acks the message
  id = trial id → every arm times out, every confirm-required change fails "Safety helper unavailable".
  Fix the correlation (ack key = the id actually sent, or a distinct message id echoed by the guard) and
  put the request/ack correlation in a Kit type with tests (fake transport: arm/ack, timeout, late ack,
  duplicate ack, guard restart).
- **N2 Major:** stale guard exit tears down the new guard. Spawn generation captured in `onExit`/`onLine`;
  ignore old generations; `terminate()` kills a stale handle after a short grace.
- **N3 Major:** auth-window cache now fails open for other-user processes (`PROC_PIDTBSDINFO` = 0). Key the
  cache on `PROC_PIDUNIQIDENTIFIERINFO` `p_uniqueid` (add to SNProcess, B may edit for this), or look the
  path up uncached when the start time is 0. Never skip a window just because identity can't be read.
- **N4:** panic/guard revert during Keep's `afterKeep` must re-apply the undo `.permanently` for modes,
  origins, main when Keep batches already went out.
- **N5:** write the journal + `setLong` for the predicted long-arm state before `commit` (no crash window).
- **N6:** stopping Displays during Keep: either finish Keep properly (`rememberKept`, persist) or revert —
  pick one, consistently, and document.
- **N8:** extend the guard deadline after each apply stage (HDR, rotation, settle), not just before the panel.
- **N10 (lead file, you may edit):** HelperPipeWriter signals waiting `flush` calls in `markBrokenLocked`.
- **W8a:** ConfirmPanel remembers `NSWorkspace.frontmostApplication` and re-activates it after Keep/Revert.
- **W9:** readable text for every guard/helper spawn error (no enum dumps); the "Safety helper unavailable"
  toast gets a "Restart Snaptic" action (`ctx.relauncher`).

## A
- **W1 BLOCKER:** a new user who quits at Welcome becomes an "upgrader". ModuleHost writes a value equal to
  `init()` so nothing is saved. Add `ConfigStore.save(force:)` (writes when nothing was ever written) and
  use it for the first-run ModulesConfig.
- **W2:** user-initiated "Grant…"/"Turn on" buttons call `presentGuide(_:reason:)` (always shows the guide),
  not the once-per-launch quiet `request`. Callers in F's FeaturesPage and C's KeysPage: edit them too.
- **W5:** when `launchedBefore && !AXIsProcessTrusted()`, show the remove/re-add guidance immediately.
- **W6:** the "New: Displays" card's button opens F's `DisplaysOnboardingStep` in a sheet (chips), and the
  card text is accurate.
- **W12:** remove `GlobalHotkeys.RegisterError.notBuilt` and every "isn't available yet" string (callers in
  F's OverviewController and C's BrightnessController: edit them).
- **W14:** a refused environment shows an NSAlert before exiting (only in app mode); narrow prefixes: `CF_`,
  `CFFIXED_`, `NSZombie`, `NSDebug`, `NSObjCMessageLogging`, `NSDeallocateZombies` etc. (keep DYLD, OBJC_,
  Malloc, LIBDISPATCH, SWIFT_, OS_ACTIVITY). KitArgs tests.
- **W15:** "Finish Later" closes the onboarding window itself; `finish()` calls `requestLaunchPermissions()`.
- **W16:** `hasVisibleItem` can't rely on `isVisible` on macOS 27 (use the item's window occlusion/frame or
  treat 27 as "maybe hidden" and keep the reopen + floating panel fallback); warn on the Menu page when no
  icon can show (Switcher hidden + Displays "Hide without external display").
- **W18:** if the selected Settings page disappears, fall back to `displays.features` (or General).
- **N7:** CLI client timeout = max confirm seconds (60) + apply/settle margin (30), or the server sends the
  effective deadline. Kit test.
- Do **not** touch HelperSpawner's verification path (another agent is moving it off main right now).

## C
- **W4:** KeysController observes `ctx.permissions.observe` and retries the tap on an Accessibility grant;
  one-time toast "Brightness keys need Accessibility" on the first ignored press while not trusted.
- **W11:** `osdNative` only honored when `osMajor < 26`.
- **W17b:** external display brightness slider shows a disabled "Reading brightness…" row until the first read.

## D
- **W8b:** menu slider changes cancel menu tracking before submitting a trial (so Return/Esc reach the panel).
- **W10:** no hard-coded "15 seconds" (ResolutionPage, ArrangementPage): interpolate `safety.confirmSeconds`.
- **N11:** VirtualHostsService maps spawn errors to accurate text ("still starting" ≠ "restart to update").

## E
- **W3:** PIP availability must not depend on Screen Recording being granted: availability = static facts;
  the permission shows as "Needs Screen Recording" with a Grant button (`presentGuide`), and the feature
  can be turned on before granting (the lead now recomputes availability on permission changes).

## F
- **W7:** turning a feature off with "Also turns off: …" clears the dependents' raw flags too (or reword to
  "Also stops" and keep raw flags) — choose clearing, it matches the text.
- **W17a:** clicking a display's name in the menu doesn't collapse the block; use a dedicated disclosure control.
