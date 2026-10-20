# PLAN 0.3.1 r3: adversarial review, code and platform feasibility

Checked against `feature/v031` @ 8059eeb (read-only). Apple sources read for this round, all from `apple-oss-distributions` on GitHub (main):
- `PowerManagement/pmconfigd/PMSettings.m`
- `PowerManagement/pmset/pmset.m`
- `xnu/iokit/Kernel/IOPMrootDomain.cpp`

Counts: **1 Blocker, 4 Majors, 10 Minors** (new). Every r2 code finding is fixed; small residuals are listed.

## r2 findings: fixed / not fixed

| r2 | Status |
|---|---|
| NB1 `&` backgrounds the `&&` list | **Fixed.** The three-line command is right in bash 3.2 sh mode and dash:<br>• `check … || exit $?` puts check's status into `do shell script`'s error number;<br>• line 2 alone is async, so `$!` is `nohup`, which execs `sh`;<br>• every stream is redirected, so the call returns at once. |
| NM1 Swift literal, tab | **Fixed.** Raw `#"""…"""#` (the text has no `"""#` or `\#(`), `unset IFS`, and the control-byte test. |
| NM2 `IODisplayWrangler` | **Fixed.** `pmset displaysleepnow` runs as the user. It takes the SkyLight path where it exists (`pmset.m` `#if __has_include(<SkyLight/SLSDisplayManager.h>)`, l.72-77, 982-1006). Residual: **m5**. |
| NM3 `declareUserActivity` | Fixed (dropped; HW-30). |
| NM4 `proc_pidinfo` on a root pid | **Fixed** (`instanceID`). Residual: "must report uid 0" has no API yet (**m1**). |
| NM5 preference only, `sleepnow` race | **Fixed in design** (`ksd`, scoped `sd`, post-set check, both-sources-twice, kernel wait). But `ksd` turns an *absent* kernel property into `?`, which breaks the start: **NB1**. |
| NM6 Step 0 and ownership | Fixed (safe returns, table, host interfaces, `lidShut` default). Residual: **m8**. |
| nm1 `cancelTracking` | Fixed. |
| nm2 scratch menu | Fixed. |
| nm3 disabled item and VO | Fixed (decided by HW). |
| nm4 `layoutChanged` element | Fixed. |
| nm5 L16 self-hit | Fixed. |
| nm6 "status" kind | Fixed (`.statusAction`). |
| nm7 requirement, responsibility, 4 KB | Fixed. |
| nm8 VO state at build | **Mostly fixed.** Full Keyboard Access has no change notification: **m3**. |
| nm9 second TERM | Fixed (`trap '' TERM INT` first in `cleanup`). |
| nm10 lid availability | Fixed. |

### Script re-run (bash 3.2 sh mode and dash)

- **Signal traps.** `trap 'HALT=1; exit 0' TERM` with `trap 'cleanup' EXIT` works in both shells:
  - a TERM interrupts `wait $!` at once (POSIX: a trapped signal makes `wait` return > 128, then the trap runs);
  - `exit 0` runs the EXIT trap once;
  - `cleanup` ignores further TERM and INT;
  - with `HALT=1`, cleanup restores but skips `sleepnow`;
  - the orphaned `sleep 5` exits by itself.
- **Exit paths.** `exit 3`, `exit 64`, the early stop file and `check` all exit before the EXIT trap is installed, so they restore nothing, which is correct. `{ WESET=0; exit 0; }` skips the restore by design.
- **Unguarded arithmetic.** None remains. `START` isn't checked with `num`, but a null `START` evaluates to 0 and trips the cap at once, which is a safe exit.
- **The `sd` awk program.** `pmset -g` prints `System-wide power settings:` at column 0, then indented ` SleepDisabled<TAB><TAB>1`, then `Currently in use:` at column 0.
  - `/^[^ \t]/` ends the block. `\t` inside a bracket is understood by BSD awk and mawk.
  - The first match inside the block wins. An absent line gives 0, the same as the preference meaning.
- **The `ksd` and `key` patterns.** `ioreg -r -n IOPMrootDomain -d 1` prints the object line, `{`, then one property per line as `      "Key" = Value`, with booleans as `Yes`/`No`. Nested dictionaries print inline as `{"Key"=Value,…}` with **no** spaces around `=`, so `"SleepDisabled" = ` (with spaces) can't match inside them. `$NF` is the value.
- **`awk -v k="\"$1\" = "`** gives `"Key" = ` after shell quoting, with no backslashes left for `-v` to process. It survives the `Q` and AppleScript layers.
- **`/bin/sleep 0.5`.** macOS `sleep(1)` accepts fractional seconds, as does GNU `sleep` for the Linux test.

---

## Blocker

### NB1. `ksd` reports `?` when `IOPMrootDomain` has no `SleepDisabled` property, so `check` exits 3 on Macs that never set it (B3.2)

**Evidence**
- `ksd` prints `f?v:"?"`, and both `check` and `run` require `[ "$(ksd)" = 0 ]`, so `?` means `exit 3`.
- powerd writes the kernel property only from `PMActivateSystemPowerSettings()`:
  - `settings = IOPMCopySystemPowerSettings(); if (!settings) goto exit;`, then `IORegistryEntrySetCFProperty(rootdomain, kIOPMSleepDisabledKey, disable_sleep ? kCFBooleanTrue : kCFBooleanFalse)` (`PMSettings.m:1334-1347`);
  - the kernel stores the value only when it receives it (`IOPMrootDomain.cpp:2055-2058`, `setProperty(key, b)`).
- With no `SystemPowerSettings` dictionary in `com.apple.PowerManagement` (research §1 and §6: "On a Mac that never set it, the line is absent"), the property is never created.
- On those Macs the first lid-closed request ends in the toast "Sleep is already turned off for this Mac by another app or command…" and the feature can't work.
- The app preflight (B3.1 step 1) also reads the IORegistry value, and the plan doesn't say what *absent* means there.

**Fix (B3.2, B3.1):**
- `ksd` must tell "no root domain output" from "no property":
  ```
  ksd() { rd | /usr/bin/awk '/IOPMrootDomain/{r=1} /"SleepDisabled" = /{f=1; v=($NF=="Yes")?1:0}
                            END{if(f)print v; else if(r)print 0; else print "?"}'; }
  ```
- The app side reads an absent property as 0, and a failed `IOServiceGetMatchingService` as unreadable.
- Add the absent case to the Linux shell test (stub `ioreg` without the line) and to the HW-29 fixtures (a Mac with no `SystemPowerSettings`).

---

## Major

### NM1. Weak linking doesn't make Sparkle optional at run time as written (E4)

**Evidence**
- **`#if canImport(Sparkle)` is always true on macOS.** The dependency is declared for every macOS build (E6), so the ad-hoc build still compiles and links `UpdaterController`. The `#if` protects nothing; the run-time path does.
- **A missing class crashes.** With `LC_LOAD_WEAK_DYLIB` and no framework, the class references for `SPUStandardUpdaterController` and the rest bind to NULL. Swift's non-failable `SPUStandardUpdaterController(startingUpdater:…)` then calls `swift_getObjCClassMetadata(NULL)` or messages nil, and crashes.
- **No sanctioned way to probe.** `NSClassFromString`, `dlopen` and `dlsym` are banned outside two files (lint rule 11, lint.sh:143-146).
- **The weak flag may not stick.** `import Sparkle` autolinks `-framework Sparkle` (`LC_LINKER_OPTION`), and the SwiftPM binary target adds `-framework Sparkle` too. Whether an extra `-weak_framework Sparkle` (`.unsafeFlags`) wins is linker behavior (ld64 vs ld-prime in Xcode 16.4) that the plan doesn't check.
- **Present but ad-hoc signed.** An ad-hoc framework in an ad-hoc hardened-runtime app fails library validation. Whether dyld treats that as "weak, skip" or aborts launch is unverified; the brief calls it "expected to stop Snaptic from launching".

**Fix (E4, E6):**
- Gate **every** Sparkle symbol behind `Bundle(identifier: "org.sparkle-project.Sparkle") != nil`. That is non-nil only when dyld actually loaded the framework, and it's lint-safe. Create `UpdaterController` only then; otherwise `ModuleHost.updater = nil`.
- In CI's `build` job, assert `otool -l Snaptic | grep -A2 LC_LOAD_WEAK_DYLIB` names `@rpath/Sparkle.framework/…`.
- Launch the ad-hoc universal app **without** `Contents/Frameworks/Sparkle.framework` through a token-gated `--selftest-launch` that builds `ModuleHost`, including the updater gate, and exits. `--selftest-controls` returns before AppKit startup (SnapticEntry.swift:13-19), so it doesn't cover this. This makes HW-37 a CI check.
- Never produce an ad-hoc bundle that **contains** Sparkle (NM2).

### NM2. E2 and E3 contradict each other about embedding Sparkle in ad-hoc builds, and CI would self-test the unsafe combination (E2, E3)

**Evidence**
- E2: local ad-hoc builds "don't embed Sparkle, because library validation would refuse an ad-hoc framework".
- E3 `build`: "embeds `Sparkle.framework` … It signs ad hoc for tests", and the existing "Helper self-test (universal…)" step runs `build/Snaptic.app/Contents/MacOS/Snaptic` (build.yml:152-160).
- That is exactly the hardened-runtime, ad-hoc, embedded-ad-hoc-framework case from NM1. Every helper and CLI process loads the framework too, because it's linked into the one executable (brief §1 [U]).
- E3's "the tests run with Sparkle present and ad-hoc signed only if they don't load it" can't hold: dyld loads every linked dylib at launch, whether or not code calls it.

**Fix (E3):** `build` produces two bundles from one compile.
- **`build/Snaptic.app`**, ad-hoc signed without Sparkle (as today). The self-tests and the `nm` check run on it.
- **`build/release/Snaptic.app`**, the same binary with `Contents/Frameworks/Sparkle.framework`. It is never signed or run in `build`, and is uploaded as `Snaptic-unsigned`.
- Add a **`verify`** job (macos-15, no secrets, `needs: sign`). It downloads the signed artifact and runs `selftest-helpers.sh` and `--selftest-controls` on the Developer ID app with Sparkle loaded. That is the first time that combination executes, and `sign` stays code-free.

### NM3. The `sign` job as written fails or produces an incomplete signature (E3)

**Evidence**
- **The `spctl` check is in the wrong place.** "Checks after signing: … `spctl -a -vv`" comes before notarization. On macOS 10.15 and later, an unnotarized Developer ID app is rejected ("source=Unnotarized Developer ID", nonzero exit), so the job fails on every run.
- **Paths are incomplete.**
  - Step 2 says `Updater.app`; Sparkle's layout is `Sparkle.framework/Versions/B/Updater.app`.
  - Removing the XPC services means removing **both** `Versions/B/XPCServices` and the top-level `XPCServices` symlink, or the framework's seal still references them (Sparkle docs, sandboxing:100-138).
- **No step adds the rpath.** SwiftPM leaves `@loader_path` for the bin directory, while the app needs `@executable_path/../Frameworks` (Sparkle docs index:50). The plan only *checks* it with `otool`.
- **The DMG is notarized but never codesigned.** Gatekeeper on 14+ checks the disk image's own signature on first open.
- **`make-dmg.sh` doesn't exist on `feature/v031`.** It comes from PR #2 (`feature/dmg`), yet E3 inlines its steps and Part D gives T-update ownership of it.
- **Tag checks on `main` pushes.** "Fails unless the tag equals `CFBundleShortVersionString`" applies to `main` pushes too, and those have no tag.

**Fix (E3, in order):**
1. **In `build`, before upload:**
   - `ditto` the framework (keep symlinks);
   - `rm -rf Versions/B/XPCServices XPCServices`;
   - `install_name_tool -add_rpath @executable_path/../Frameworks Contents/MacOS/Snaptic`;
   - `otool -l` assert.
2. **In `sign`:**
   - `codesign -f -o runtime --timestamp -s ID` on `Sparkle.framework/Versions/B/Autoupdate`, then `…/Versions/B/Updater.app`, then `Sparkle.framework`, then the app;
   - `codesign --verify --strict --deep`;
   - zip;
   - `notarytool submit --wait`;
   - `stapler staple` the app;
   - **then** `spctl -a -t exec -vv`;
   - re-zip;
   - build the DMG, `codesign --timestamp -s ID` it, notarize, staple, then `spctl -a -t open --context context:primary-signature -vv`.
3. **Version checks.** Run the tag-equality check only for `refs/tags/v*`. On `main`, check only that `CFBundleVersion` is an integer.
4. **The DMG step.** Either Step 0 merges PR #2 first, or E3 inlines the full `hdiutil create … -format UDZO` call and drops `make-dmg.sh` from T-update.

### NM4. The deferral and relaunch rules use APIs that don't behave as described (E4)

**Evidence**
- **`isInstalling` doesn't exist.** `Relauncher` would check `updater?.isInstalling`; `SPUUpdater` has no such property (it has `sessionInProgress` and `canCheckForUpdates`).
- **The real hazard is an update already waiting to install on quit.** With automatic downloads, Sparkle calls `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` and installs when the app terminates ("Sparkle will always attempt to install the update when the app terminates", brief §2).
  - `Relauncher` opens the new instance **before** the old one quits (Relauncher.swift:20-32).
  - Sparkle then swaps the bundle under an instance that is already starting. The instance lock is AppDelegate.swift:29-46. That instance runs the old executable from a replaced bundle, and its helpers fail identity ("Restart Snaptic to finish updating").
- **`updaterShouldRelaunchApplication(_:)` isn't a postpone.** Returning false means "install, but don't relaunch". Only `updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)` defers.
- **Install-on-quit can't be postponed at all.** That's acceptable for lid-closed mode, because quitting ends it and there's no relaunch. But the E4 list ("an install waits while…") is wrong for that path.
- **Safe Mode.** "Updates are paused entirely" needs `updater(_:mayPerform:) throws` (`mayPerformUpdateCheck`, SPUUpdaterDelegate.h:87). The plan doesn't name it.

**Fix (E4):**
- `UpdaterController` keeps `pendingQuitInstall: (() -> Void)?` from `willInstallUpdateOnQuit` and exposes `hasPendingQuitInstall`.
- **Relauncher:**
  - if there is a pending quit install and the relaunch isn't a Safe Mode relaunch, call the stored `immediateInstallationBlock` (Sparkle installs and relaunches) instead of `openApplication`;
  - for a Safe Mode relaunch, skip the install and relaunch as today (Sparkle installs on a later quit).
- **Deferral:** `shouldPostponeRelaunchForUpdate` holds the block while `UpdatePolicy` says wait. `updaterShouldRelaunchApplication` always returns true.
- **Safe Mode:** `mayPerform` throws for scheduled checks in Safe Mode and allows user-initiated ones.
- Test the matrix in `UpdatePolicyTests` (pure Kit), with each Sparkle callback written as a `UpdatePolicy.Event`.

---

## Minor

### m1. The "uid 0" check at verify has no API (B3.1 step 6)
`SNProcess.instanceID(for:)` returns only the start time.
- **Fix:** add `SNProcess.realUID(for:)` from the same `sysctl(KERN_PROC_PID)` `kinfo_proc` (`kp_eproc.e_pcred.p_ruid`) in T-lid-app's shim. This also gives HW-31's ruid check a runtime equivalent.

### m2. Leftover rows can't be passed as item instances (B3.4)
`CustomItemRow` is an `Equatable` value (ModuleContracts.swift:77-85). Awake's custom menu rebuilds on every open (IndicatorController.swift:132-136). An `NSMenuItem` can sit in only one menu, and `section()`-style detaching would move rows out of the shared menu.
- **Fix:** add `leftover: Bool` to `CustomItemRow`, and a static `StatusMenu.leftoverItems(host:) -> [NSMenuItem]` (StatusMenu.swift aliases `StatusMenuControls`, so L15 holds) that IndicatorController calls on each build.

### m3. Full Keyboard Access changes aren't observed (A3)
Neither `accessibilityDisplayOptionsDidChangeNotification` nor the VoiceOver KVO fires when FKA is toggled.
- **Fix:** set the Show … Tab items' `isHidden` in `menuNeedsUpdate` on every open, even when the slot isn't dirty. It's a cheap property flip with no rebuild.

### m4. The Linux shell test needs more than four stubs (B3.2 "Shell test")
- **Paths.** The script calls `/bin/kill`, `/bin/sleep`, `/bin/date`, `/usr/bin/awk`, `/usr/bin/sed` and `/usr/bin/nohup` by absolute path.
  - In `swift:5.10-jammy`, `/bin/kill` comes from `procps`, which the image may not have.
  - GNU `stat -f %u` means "file system status", so stubbing `stat` is mandatory.
- **Duration.** The 5 s period makes every `run` case take at least 5 s.
- **Fix:**
  - `script(tools:)` covers every absolute path, plus `period` and `staleSeconds`.
  - The test kills its own leftover background processes.
  - The test also runs in the macOS `build` job, which is the only place with bash 3.2: Linux `bash --posix` is 5.x.
  - The "rule 12 exemption" isn't needed: rule 12 and rule 7 scan `Sources/` only, and Foundation `Process` works on Linux.

### m5. The built-in panel may be offline while the lid is shut (B3.3)
`CGDisplayIsAsleep` needs the built-in display's id. With the lid closed, the built-in can leave the online list, so the condition has nothing to test.
- **Fix:** if the built-in display isn't in `CGGetOnlineDisplayList`, treat it as "unknown" and still run `displaysleepnow` (rate-limited to 10 s). HW-30 records which case happens.

### m6. L19 would flag Sparkle's defaults keys used as strings outside `UpdaterController`
General › Reset clears `SU*` keys (ModuleHost) and E7's `keys: ["SUEnableAutomaticChecks"]` sits in a Kit controls table. Both are `SU`-prefixed literals.
- **Fix:** L19 matches `import Sparkle` and identifiers `\b(SPU|SU)[A-Z]\w*` **outside string literals**. Alternatively, keep the key names in one Kit `UpdateDefaultsKeys` enum listed as an exemption. The `ControlLegacy.internalKeys` entry is unnecessary, because the cross-check only walks config fields.

### m7. "The existing Check for Updates… item" isn't a menu item (E1, E7)
It is the About page's `ButtonRow` `about.page.checkUpdates` (AboutPage.swift:36-39; AboutPageControls.swift:8-10). The app menu (AppDelegate.swift:224-231) has no such item.
- **Fix:** E7 names `AboutPageControls` and that id, and E1 says "Settings › About › Check for Updates…". If a Snaptic-menu item is wanted, add a new id.

### m8. Part D ownership gaps for Part E
- `SnapticEntry` and `AppDelegate`, where `UpdaterController` is created, are T-lid-app's.
- `ModuleHost.swift` (`updater`, the Reset of `SU*`) has no owner.
- `AboutPage.swift`'s network sentence (l.56) and `THIRD_PARTY_NOTICES.md` are split between T-update and T-docs.
- **Fix:**
  - name `AppDelegate`'s Part E hunk as T-update's, landed as a Step 0 stub call;
  - give `ModuleHost.swift` to T-update;
  - give all of `THIRD_PARTY_NOTICES.md` to T-docs.

### m9. Release publishing has an appcast gap and a parsing risk (E3 `release`)
- **No appcast for a moment.** `gh release create` publishes at once. "latest" then points at a release with no `appcast.xml` until the upload finishes, and a scheduled check in that window gets a 404.
  - **Fix:** create as `--draft`, upload `Snaptic.zip`, `Snaptic.dmg` and `appcast.xml`, then `gh release edit --draft=false`. For a pre-existing release, upload the appcast **last**.
- **Parsing the old appcast in a heredoc** is fragile.
  - **Fix:** use inline `python3 - <<'PY'` with `xml.etree.ElementTree` (on the ubuntu runner, not repository code) to prepend the item, keep 10 and escape text.

### m10. `release` environment reviewers and `attest`
- If the owner turns on required reviewers for the `release` environment, every `main` push waits on `sign`, and `attest` (`needs: sign`) waits with it.
- **Fix:** run `sign` and `attest` for tags only, or document the wait. `main` artifacts can stay ad hoc as today.

---

## Part E items checked and found fine

- **SwiftPM manifest.**
  - `#if os(macOS)` dependency plus `exact: "2.10.0"` in a tools-5.9 manifest.
  - `kit-linux` never resolves Sparkle; a committed `Package.resolved` with an unused pin is tolerated on Linux.
  - `.unsafeFlags` is allowed in a root package.
- **Universal build.** `swift build --arch arm64 --arch x86_64` handles binary targets (XCBuild path). The framework appears in the `--show-bin-path` directory. NM3 adds the rpath and the copy.
- **Test host.** `SnapticKitTests` doesn't link Sparkle. The debug `Snaptic` (not hardened) loads it from `.build/debug` through SwiftPM's `@loader_path` rpath, so the debug self-tests are unaffected.
- **Re-signing.** Signing an ad-hoc-signed bundle with Developer ID via `codesign --force`, inside out, is clean (universal slices are re-signed together). Notarize the zip, then staple, then re-zip, then compute EdDSA over the **final** zip in `release`: the order is right, and `attest` attests the same bytes.
- **Delegate names.** `updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)` and `updaterShouldRelaunchApplication(_:)` are the 2.x names (semantics in NM4).
- **`CFBundleVersion` 301.** It is an integer and increasing. Sparkle compares it as `sparkle:version`. `SettingsText.version` will now show "0.3.1 (301)", because build ≠ version (SettingsPageRules.swift:59-65), which is fine.
- **GUI-only creation.** Helper and CLI modes return before AppKit (SnapticEntry.swift:13-19), so creating the updater in `AppDelegate` is GUI-only. Those processes still *load* the framework (NM2).
- **Lint.** L19's `Package.swift` and `import` checks are simple greps. Lint rule 2's network-API ban still scans only `Sources` and `Tests`, so Sparkle's internals are unaffected.
