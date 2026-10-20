# PLAN 0.3.1 r4: adversarial review, code and platform feasibility (final planning round)

Checked against `feature/v031` @ 7b75ebe (read-only; PR #2's `scripts/make-dmg.sh` and build.yml changes are merged).

Sparkle API names were checked against the **2.10.0** tag sources: `Sparkle/SPUUpdaterDelegate.h`, `SPUStandardUserDriverDelegate.h`, `SPUUpdater.h`, `SUConstants.m` and `generate_appcast/{main,ArchiveItem,FeedXML}.swift`, fetched from `raw.githubusercontent.com/sparkle-project/Sparkle/2.10.0/`.

Counts: **0 Blockers, 2 Majors, 7 Minors**. All r3 code findings are fixed.

## r3 findings: fixed / not fixed

| r3 | Status |
|---|---|
| NB1 absent `SleepDisabled` property → `?` → exit 3 | **Fixed.** `ksd` sets `r` on the `+-o IOPMrootDomain` object line, prints 0 when the root domain is present and the property absent, and `?` only when there's no output. The app side matches, and the shell test and HW-29 fixtures cover it. |
| NM1 weak linking | **Fixed.** `Bundle(identifier: "org.sparkle-project.Sparkle")` gates every call. It returns non-nil for a framework dyld loaded at launch. `UpdaterController` adopts Sparkle's ObjC protocols, whose copies live in the client image, and subclasses no Sparkle class, so nothing binds to a missing class at load time. CI checks `LC_LOAD_WEAK_DYLIB`, and `--selftest-launch` runs the gate. Residual: **m1**. |
| NM2 two bundles | **Fixed.** `build/Snaptic.app` (ad hoc, no Sparkle) is the only bundle run in `build`. `build/release` is never run before signing, and `verify` runs the signed app with no secrets. Residual: artifact naming, **M1**. |
| NM3 `sign` order and paths | **Fixed.** Pinned hashes are checked before signing. Signing is inside out: `Versions/B/Autoupdate`, `Versions/B/Updater.app`, the framework, then the app. Both `XPCServices` paths are removed and the rpath is added. Then notarize, staple, `spctl` after stapling, sign, notarize and staple the DMG, with tag checks only on tags. `make-dmg.sh`'s `codesign --verify --strict "$APP"` passes on a stapled Developer ID app: the stapled ticket doesn't break the seal. Residual: **m2**. |
| NM4 deferral APIs | **Fixed.** All the names exist in 2.10.0 (see below). Residuals: the return value and the B4 wording, **m3**. |
| m1 uid API | Fixed (`SNProcess.realUID`). |
| m2 leftover rows as instances | Fixed (`CustomItemRow.leftover` plus `StatusMenu.leftoverItems(host:)`). Step 0 doesn't list the signature: **M2**. |
| m3 Full Keyboard Access | Fixed (checked on every open). |
| m4 shell test | Fixed. The text still contradicts itself: **m6**. |
| m5 panel offline | Fixed. |
| m6 L19 and strings | Fixed (`UpdateDefaultsKeys`, identifiers outside literals). |
| m7 no menu item | Fixed (About button, Update Available row). |
| m8 ownership | Partly fixed: **M2**. |
| m9 appcast gap, heredoc | Fixed (draft published last, `generate_appcast`). Residual: **m4**. |
| m10 reviewers on `main` | Fixed (tag-only environments, E0). |

### Sparkle 2.10.0 API check

| Plan name | 2.10.0 declaration | Result |
|---|---|---|
| `feedURLString(for:)` | `- (nullable NSString *)feedURLStringForUpdater:(SPUUpdater *)updater;` (SPUUpdaterDelegate.h:123) | ✓ |
| `updater(_:mayPerform:) throws` | `- (BOOL)updater:mayPerformUpdateCheck:(SPUUpdateCheck)updateCheck error:` (:87). Scheduled checks arrive as `.updatesInBackground`. | ✓ |
| `updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)` | :356 | ✓ |
| `updaterShouldRelaunchApplication(_:)` | :367 | ✓ |
| `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` | `- (BOOL)…` (:440). The handler "can only be used if YES is returned". YES "stalls the current update cycle and prevents future update cycles". | ✓, see **m3** |
| `supportsGentleScheduledUpdateReminders` | `@property (readonly) BOOL` on `SPUStandardUserDriverDelegate` (:102). It works only together with `standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)` (:134) and/or `standardUserDriverWillHandleShowingUpdate(_:forUpdate:state:)` (:161). | ✓, see **m5** |
| `clearFeedURLFromUserDefaults()` | `SPUUpdater.h:320` | ✓ |
| Info.plist keys | `SUFeedURL`, `SUPublicEDKey`, `SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction`, `SUEnableSystemProfiling`, `SUScheduledCheckInterval` (SUConstants.m:22-40) | ✓ |
| `generate_appcast --ed-key-file` | main.swift:83 | ✓ (takes the base64 seed that `generate_keys -x` exports) |
| `--download-url-prefix` | :105 | ✓ |
| `--embed-release-notes` | :111 | ✓ |
| `--link` | :117 | ✓ |
| `--maximum-versions` | :123 | ✓ |
| `Snaptic.md` next to `Snaptic.zip` | ArchiveItem.swift:434-460: picked up and given `format = "markdown"` | ✓ |
| Feed signing | Automatic when the archived app's Info.plist has `SURequireSignedFeed` (ArchiveItem.swift:247) | ✓ |
| `sparkle:fullReleaseNotesLink` | Written only with `--full-release-notes-url` (main.swift:114; FeedXML.swift:395-398), which E3's command doesn't pass | **m4** |

---

## Major

### M1. Existing CI jobs and artifact names collide with the new pipeline on the first tag (E3)

**Evidence** (build.yml as merged from PR #2):
- **The artifact name.** `build`'s "Upload app" uploads artifact **`Snaptic`** (ad-hoc zip and dmg) when `github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/v')`. E3's `sign` uploads its signed output under the same name, `Snaptic`, in the same run. upload-artifact v4 and later refuse a second artifact with an existing name in a run (409 conflict), so `sign` fails on every tag. If it didn't, `verify`, `attest` and `publish` would download an ambiguous name.
- **The old `attest` job** has `needs: build` and attests the downloaded `Snaptic` (the ad-hoc files).
- **The old `release` job** (tags, `needs: build`) runs `gh release create "$TAG" Snaptic.zip Snaptic.dmg … --generate-notes`. That publishes a **non-draft** release with the **ad-hoc** zip and dmg as soon as `build` finishes, long before `sign` or the owner's approval. "latest" then serves ad-hoc downloads with no appcast. E3's `publish` step "reuse the existing draft" would find a published release instead.
- E3 lists the new jobs but never says to delete or change these three.

**Fix (E3, plan text):**
- `build` uploads `Snaptic` (ad hoc) **only for `main`**, and only `Snaptic-unsigned` for tags. Rename `sign`'s output `Snaptic-signed`, and have `verify`, `attest` and `publish` download that name.
- **Delete** the old `release` job.
- Change the old `attest` job to `needs: sign`, tags only, and point it at `Snaptic-signed`.
- `publish` creates the draft itself; when a non-draft release for the tag already exists, it fails instead of reusing it.
- Add a workflow lint (E6): exactly one job runs `gh release create|upload`, and it's `publish`.

### M2. Step 0 still misses cross-team signatures, and two shared files have the wrong owner (Part D)

**Evidence.** These are needed by one Step 1 team but live in another team's file, and none of them is in Step 0's list:
- **`CustomItemRow.leftover: Bool`** (ModuleContracts.swift, T-menu) and **`static StatusMenu.leftoverItems(host:)`** (StatusMenu.swift, T-menu). IndicatorController (T-lid-app) calls both. E7's **Update Available** row uses "the same host factory", which adds a third signature.
- **`ModuleHost.lidRecovery`.** It is listed as a host interface, but `ModuleHost.swift` is now **T-update's** (E4 Reset of `SU*`). T-lid-app must also wire `LidRecovery` there.
- **`--selftest-launch`.** It needs a `KitArgs` mode (`SnapticKit/KitArgs.swift`), dispatch in `SnapticEntry.swift` and a body in `SelfTest.swift`. None of the three has an owner.
- **The re-grant guidance** (E2: "launched-before heuristic extended to Screen Recording"): `SnapticKit/KitHostUI.swift`, `PermissionFlow.swift` and `PermissionsPage.swift` have no owner. T-lid-app's "Kit Permissions copy file" is a different file.
- **`scripts/lint*`** is listed under both Step 0 ("plus the E6 rules") and T-update.

**Fix (Part D):**
- Add these to Step 0, item 3:
  - `CustomItemRow.leftover` and `updateAvailable`;
  - `StatusMenu.leftoverItems(host:)` and `StatusMenu.updateItems(host:)`;
  - `KitArgs.Mode.selftestLaunch` with its dispatch;
  - `KitHostUI` re-grant inputs.
- Ownership:
  - `ModuleHost.swift` is co-owned by hunk, like AppDelegate: T-update owns `updater` and Reset; T-lid-app owns `lidRecovery`. Both are landed as Step 0 stubs.
  - `KitArgs`, `SnapticEntry` and `SelfTest` go to T-update.
  - `KitHostUI`, `PermissionFlow` and `PermissionsPage` go to T-update (the re-grant is Part E's).
  - `scripts/lint*` is Step 0 only, frozen after.

---

## Minor

### m1. The weak-load check runs only on tags
The `LC_LOAD_WEAK_DYLIB` assertion sits in the tag-only `build/release` step. The binary is the same on every push, and a linker change (Xcode bump, ld-prime) would first show on a release tag.
- **Fix:** run the `otool -l` assertion on `build/Snaptic.app`'s binary in every push build.

### m2. `make-dmg.sh` isn't "a fixed script, no inputs" in `sign`
- With no arguments it packages `build/Snaptic.app`, the ad-hoc path, not the downloaded and signed `build/release` app.
- It `cd`s to the repo root, so `sign` needs `actions/checkout`. The checkout must have `fetch-depth: 0` for `git merge-base --is-ancestor … origin/main`.
- **Fix:** call `./scripts/make-dmg.sh "$SIGNED_APP" "$RUNNER_TEMP/Snaptic.dmg"`, and state the checkout and its depth.

### m3. `willInstallUpdateOnQuit` must return YES, and Relauncher bypasses `UpdatePolicy`; B4 overstates (E4, B4)
- The stored `immediateInstallationBlock` is usable only if the delegate returns **YES**. YES also stops further update cycles until quit.
  - **Fix:** E4 says "returns YES; no further checks run until Snaptic quits or the block is used; the About row shows *ready to install*".
- Relauncher calls the block without asking `UpdatePolicy`, so a permissions relaunch while lid-closed mode is on installs and relaunches anyway.
- B4 says "an update never installs or relaunches while the mode is on", which contradicts E4's "installing at quit can't be postponed".
  - **Fix:** Relauncher consults `UpdatePolicy` and falls back to its own relaunch when the policy says wait. B4 becomes "an update never **relaunches** Snaptic while the mode is on; installing at quit still happens, and quitting ends the mode".

### m4. `sparkle:fullReleaseNotesLink` needs a flag (E1, E3)
E1 promises a Full Release Notes link, but `generate_appcast` writes it only with `--full-release-notes-url`.
- **Fix:** add `--full-release-notes-url "https://github.com/revylfitness/snaptic/releases/tag/$TAG"` to E3's command.

### m5. Gentle reminders need two more delegate methods and a consent backstop (E1)
`supportsGentleScheduledUpdateReminders` alone changes nothing visible.
- **Fix:** E4 lists the delegate methods:
  - `standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)` returns false while onboarding is up or in Safe Mode, so the footer row shows instead;
  - `standardUserDriverWillHandleShowingUpdate(_:forUpdate:state:)` sets `updateReady`;
  - `standardUserDriverDidReceiveUserAttention(forUpdate:)` and `standardUserDriverWillFinishUpdateSession()` clear it.
- Implement `updaterShouldPromptForPermissionToCheck(forUpdates:)` (SPUUpdaterDelegate.h:149) returning false. Sparkle's own consent prompt then never appears, even if the user dismisses onboarding without choosing.

### m6. The B3.2 shell-test paragraph contradicts itself, and B5 has a stale signature
- The paragraph first says every tool is stubbed, then says "It uses stub `pmset`, `ioreg`, `notifyutil` and `stat`" (the r3 text, left in).
- B5 still lists `script(tools:)`, while B3.2 says `script(tools:period:stale:)`.
- **Fix:** delete the stale sentence, and align B5 to `script(tools:period:stale:)`.

### m7. Pinned Sparkle hashes must come from the SwiftPM artifact
`sign` pins the hashes "for the official 2.10.0 build". The files it checks come from the **SwiftPM binary-target zip** (already checksum-pinned by SwiftPM: `17e28312…`, brief §2), not from `Sparkle-2.10.0.tar.xz`, which `publish` uses. The two distributions aren't guaranteed byte-identical.
- **Fix:** record the hashes from the SPM xcframework's macOS slice. `publish` pins the tar.xz hash separately.

---

## Checked and found fine

- **B3.2 script.** `ksd`'s three-state logic, the `key()` matcher, the post-set check and the kernel-wait before `sleepnow` were rechecked with the absent-property case under bash 3.2 sh mode and dash. Both `check` and `run` accept a never-set Mac; after `disablesleep 1`, powerd creates the property (`PMSettings.m:1334-1347`), so the post-set check sees Yes.
- **Re-signing.** `--force` inside-out re-signs the ad-hoc universal bundle with Developer ID. `install_name_tool -add_rpath` on the fat binary before signing is fine (`sign` re-signs). Order: notarize the zip, staple, `spctl -t exec`, re-zip; sign the DMG, notarize, staple, then `spctl -t open --context context:primary-signature`.
- **`generate_appcast` in `publish`.** It keeps existing items from the previous `appcast.xml` in the folder, adds the new item with the `$TAG` prefix URL, trims to 10, embeds Markdown from `Snaptic.md`, and signs the feed because the app's Info.plist sets `SURequireSignedFeed`. It needs macOS (`publish` is macos-15).
- **App-side Sparkle wiring.**
  - The `Bundle(identifier:)` gate works for a launch-loaded framework.
  - `feedURLString(for:)` plus `clearFeedURLFromUserDefaults()` pins the feed.
  - `mayPerform` with `.updatesInBackground` distinguishes scheduled from user checks.
- **Info.plist keys** are all valid 2.10 keys. `SUEnableAutomaticChecks` is left unset as intended.
- **`verify`.** The downloaded artifacts aren't quarantined, so the helper self-test and `--selftest-controls` can run on the Developer ID app.
- **Parts A and B (r4 changes).** No new feasibility problems in my lens.

## Verdict

**Not ready** until two plan-text changes land. Both are edits to E3 and Part D; no redesign is needed:
1. **M1:** rename and gate the CI artifacts, delete the old `release` job, and repoint `attest`. As written, the first tag either fails at `sign` or publishes ad-hoc builds as "latest".
2. **M2:** complete Step 0's cross-team signatures (`CustomItemRow.leftover` and `updateAvailable`, `StatusMenu.leftoverItems` and `updateItems`, `--selftest-launch` plumbing, `KitHostUI` re-grant) and fix the `ModuleHost.swift` and `scripts/lint*` ownership.

Once those two are applied, Parts A, B and E are feasible to implement as specified. The Minors can be folded in during Step 1.
