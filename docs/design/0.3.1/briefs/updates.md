# Brief: in-app updates with Sparkle 2 for Snaptic 0.3.1

Repo `/home/claude/snaptic`, branch `feature/v031` at 8fd1b27. I only read the code; nothing was compiled.
Sparkle was read at tag `2.10.0` (repo and docs-site source, both cloned 2026-10-19).
**[C]** = confirmed, with its source. **[U]** = uncertain.

## 1. Repo facts

**Build and signing** (`scripts/build-app.sh`):
- [C] It creates only `Contents/MacOS` and `Contents/Resources` (:29) and copies the binary and Info.plist (:30-31). There is no `Frameworks` directory, no rpath step, and no nested signing.
- [C] Signing is `codesign --force --options runtime --sign "$IDENTITY" "$APP"`, ad hoc `-` by default (:33, :38). Then `--verify --strict` runs (:39), and the build fails if the runtime flag is missing (:42-46). There are no entitlements; the comment says "Never add entitlements that weaken it" (:35-37).
- [C] `INSTALL=1` (:48-57) runs pkill, `sudo ditto` and `chown -R root:wheel`. The bundle is root-owned so "another process running as you can't swap the binary" (:49-50; README:543).

**`Package.swift`** [C]:
- tools 5.9; `.macOS(.v14)` (:43); no `dependencies:` (:41-45).
- `SnapticKit` and its tests on every OS (:8-11). `SnapticShims` and the executable `Snaptic` only under `#if os(macOS)` (:13-39), linking system frameworks only (:18-24, :32-36).
- THIRD_PARTY_NOTICES.md:7 says "no … libraries, or binaries, and has no package dependencies".

**`Info.plist`** [C]:
- `app.snaptic.Snaptic` (:9-10); `CFBundleShortVersionString` **0.3.0** (:15-16); `CFBundleVersion` **"1"** (:17-18); LSMinimumSystemVersion 14.0; `LSUIElement`.
- Both versions are edited by hand. CI never derives them from the tag; the tag only feeds the release title (build.yml:219, 228).
- Display: `SettingsText.version` prints "Version 0.3.0 (1)" and hides the build when it equals the version (SettingsPageRules.swift:59-65). It is used by About (AboutPage.swift:64-68), the `version` CLI verb (ModuleHost.swift:385-389), Backup.swift:50 and Diagnostics (DiagnosticsController.swift:94-95).
- `CFBundleVersion` is also the helper-hello "build" (DisplayGuardClient.swift:197; VirtualHostsService.swift:270).

**The current "Check for Updates…"** [C]:
- It is a `ButtonRow` with `control: ControlID("about.page.checkUpdates")` and the help text "Opens the Snaptic releases page in your browser." It opens `…/revylfitness/snaptic/releases` (AboutPage.swift:14, 36-39). Its table entry is AboutPageControls.swift:8-10.
- The About footer says "Snaptic never connects to the network: no analytics and no automatic update checks." (AboutPage.swift:56).

**Claims that become false** [C]:
- README:576 "**No network.** … no update checks … A lint check rejects networking APIs."
- README:660 "no automatic updates".
- README:687, which lists "network update checks" under Not included.
- site/index.html:502 "No network. No tracking." and :736 "It makes no network connections."
- THIRD_PARTY_NOTICES.md:7.
- Adjacent: Awake "installs nothing, and leaves nothing behind" (README:155; site:600). README:528-530 (zip, drag to Applications, translocation warning). README:572 already says that with ad hoc builds "permissions are lost on every update".

**Lint rules Sparkle touches** (`scripts/lint.sh`) [C]:
- **Rule 2** bans `URLSession|NWConnection|import Network` in `Sources` and `Tests` only (:32-35). Snaptic's calls to `SPUStandardUpdaterController` pass; Sparkle's internal NSURLSession is never scanned. The *intent* breaks.
- The `resources:` ban (:36-39) doesn't apply, because Sparkle is a binaryTarget whose resources are inside the framework.
- **Rule 6:** every new `.swift` file needs a `scripts/stubs.tsv` row. AboutPage is at stubs.tsv:117 and AboutPageControls at :338.
- **Rule 11** (:143-146): `dlopen` is allowed only in PrivateDisplayAPI and PrivateAPIs, so lazy-loading Sparkle would need an exemption.
- **Rule 12** (:148-152): spawning is allowed only in HelperSpawner and SNSpawn, and only `Sources` is scanned. Sparkle submits Autoupdate and Updater through launchd `SMJobSubmit` (Sparkle InstallerLauncher/SUInstallerLauncher.m:98-100, 283-285), and Autoupdate runs `gktool` through NSTask (Autoupdate/SUPlainInstaller.m:106-115). The lint passes; the policy doesn't hold.
- **L15** (lint03.py): a new toggle needs a `ControlSpec` and must be used.

**HelperSpawner** [C]:
- It records its own designated requirement, executable path and executable UUID (HelperSpawner.swift:452-466; SNProcess.m:72-100), and checks children with `SecCodeCheckValidity` (HelperSpawner.swift:510-515; SNProcess.m:105-115).
- Helpers check their parent against their *own* requirement (HelperPrologue.swift:119-127). A mismatch sets "Restart Snaptic to finish updating" (HelperSpawner.swift:223-226).
- Sparkle's Autoupdate and Updater.app are launchd jobs, not children, so they're never checked. Sparkle replaces the bundle only after Snaptic has exited (Sparkle Documentation/Installation.md, "Finishing the Installation"), so the "replaced while running" state shouldn't arise.
- [U] Helpers and the CLI run `Contents/MacOS/Snaptic` itself. If Sparkle is linked into that executable, every helper and CLI process loads Sparkle.framework too.

**Permissions and TCC** [C]:
- PermissionFlow polls every 1.5 s for up to 10 min and shows a "remove with −, add with +" hint after 30 s (PermissionFlow.swift:15-17, 176-200, 429-431).
- The only lost-grant heuristic is `showsReAddStepsAtOnce`: accessibility, launched before, not granted (KitHostUI.swift:28-30; PermissionFlow.swift:105-110). It shows the text "macOS is holding on to an older copy…" (:389-392). `launchedBefore` comes from the `SnapticDidLaunchBefore` default (ModuleHost.swift:16, 83, 94, 212).
- **No previous build or cdhash is stored**, so an update can't be told apart from a revoke. Screen Recording has no re-add path.
- The writable-bundle and translocation checks are at PermissionFlow.swift:286-297, 386-388 and 426, and PermissionsPage.swift:80-85. "Relaunch Snaptic" is at PermissionsPage.swift:88-91.

**Settings conventions** [C]:
- General page controls are in GeneralPageControls.swift:5-34, with `keys:` paths into `ModulesConfig`, stored as the JSON default `SnapticModulesV1` (ModuleHost.swift:14; ConfigModules.swift:112-126).
- Backup's `removedPaths` strips CLI and onboarding settings (KitBackup.swift:68-93). The `modules` section isn't allowlisted, so a new field is exported unless it is listed there.
- Kill switches use `<Area>.disable.<id>` (README:440-454; ModuleHost.swift:22).
- Sparkle writes its own `SU*` keys (`SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`, `SUHasLaunchedBefore`, `SULastCheckTime`…) into the same domain, outside `SnapticModulesV1` and outside Backup (SUConstants.m; SPUUpdater.m:401-421).

**CI** (`.github/workflows/build.yml`) [C]:
- Triggers: main, `feature/**`, tags `v*` and pull requests (:4-6). Default permissions are `contents: read` (:11-12).
- `kit-linux` (:22-55) runs lint plus the Kit build and tests on swift:5.10.
- `build` (:58-178, macos-15, Xcode 16.4) runs lint, build, tests and self-tests. On pushes it runs `ARCHS="arm64 x86_64" ./scripts/build-app.sh` (:137-141), the private-class `nm` check (:143-150), `ditto -c -k --keepParent … Snaptic.zip` (:167-169), and uploads the artifact for main and tags (:171-177).
- `attest` (:181-200) attests `Snaptic.zip`.
- `release` (:205-230; ubuntu, `contents: write`, tags only) downloads the artifact, then runs `gh release upload --clobber` or `gh release create "$TAG" Snaptic.zip --title "Snaptic ${TAG#v}" --generate-notes`.
- On `feature/dmg` it also runs `make-dmg.sh` and uploads Snaptic.dmg (that branch's build.yml:173, 234-236).

## 2. Sparkle 2 facts

**Version and SwiftPM** [C]:
- The latest stable release is **2.10.0**: tag commit dated 2026-09-13, marked "Latest" on GitHub.
- 2.10 requires macOS 12 (Snaptic requires 14), drops CocoaPods, and recommends `sparkle:minimumSystemVersion` in items (CHANGELOG).
- Its Package.swift exposes product `Sparkle` as a **binaryTarget** zip (`Sparkle-for-Swift-Package-Manager.zip`, checksum `17e28312…d959`). I downloaded it and the checksum matched.
- It contains a universal **dynamic** `Sparkle.framework` (Versions/B) with:
  - `Sparkle`, `Autoupdate` (the installer) and `Updater.app` (the progress agent, which relaunches the app);
  - `XPCServices/{Installer,Downloader}.xpc`;
  - plus `bin/generate_keys`, `sign_update` and `generate_appcast`.

**Embedding without Xcode:**
- [C] The XPC services are for sandboxed apps. "If you do not sandbox your application … you may choose to remove these services" (`Versions/B/XPCServices` and the `XPCServices` symlink), then `codesign --force --sign … --preserve-metadata` the framework (docs sandboxing:100-138). Autoupdate and Updater.app are required.
- [C] Sign from the inside out, without `--deep`: `codesign -f -s ID -o runtime` on Autoupdate, then Updater.app, then the framework (docs sandboxing:71-94). Then sign the app as today.
- [C] Archives must keep the framework's symlinks (docs publishing:14). `ditto -c -k` does.
- [C] For non-Xcode builds the docs say to add `-Wl,-rpath,@loader_path/../Frameworks` (docs index.md:50).
- [U] It's untested whether `swift build`, especially with `--arch arm64 --arch x86_64`, copies the framework and which rpath it sets. Plan on `.unsafeFlags` linker settings or `install_name_tool -add_rpath` before signing, then check with `otool -l`.
- [U] `kit-linux`: declare the dependency under `#if os(macOS)` so Linux doesn't fetch it, and commit `Package.resolved`.

**Library validation: the blocker** [C]:
- Apple: the Hardened Runtime "prevents a program from loading frameworks … unless they're either signed by Apple or signed with the same Team ID as the main executable" (Apple docs, Disable Library Validation Entitlement).
- Quinn (DTS): "If you're ad-hoc signed then you have no Team ID and thus, if you have library validation enabled, you can only load platform libraries." His workaround is `com.apple.security.cs.disable-library-validation` (developer.apple.com/forums/thread/782645).
- Sparkle docs: "the system may not let your application load Sparkle if you … sign … via an ad-hoc signature" (docs index.md:55).
- So with today's signing (ad hoc plus `--options runtime`), linking Sparkle is expected to stop Snaptic from launching. The only ways out are:
  - (a) `disable-library-validation`. This contradicts build-app.sh:35-37, and Apple warns that Gatekeeper then runs extra checks.
  - (b) a Team ID (Developer ID or Apple Development).
  - (c) dropping the hardened runtime.
- [U] Still to confirm on macOS 14, 15, 26 and 27 hardware.

**EdDSA** [C]:
- `generate_keys` stores a **32-byte seed**, base64-encoded, in the login Keychain and prints `SUPublicEDKey` (generate_keys/main.swift:92-102, 273-276). `-x` exports it.
- `sign_update` runs `ed25519_sign` over the **whole archive file** and prints `sparkle:edSignature="<base64 of 64 bytes>" length="<bytes>"` (sign_update/main.swift:276-287; common_cli/Signing.swift:203-217). The verifier reads the whole file (SUSignatureVerifier.m:95, 175).
- **I tested this on Linux:** Sparkle's vendored C ed25519, Python `cryptography` (`Ed25519PrivateKey.from_private_bytes(seed).sign(data)`) and `openssl pkeyutl -sign -rawin` (with the seed wrapped in the PKCS#8 DER prefix `302e020100300506032b657004220420`) gave **byte-identical signatures** on a 1.5 MB file. The ubuntu release job can therefore sign `Snaptic.zip` from a secret seed.

**Appcast** [C] (docs publishing:76-150):
- Each item needs `sparkle:version` (compared against **CFBundleVersion**, which must increase), `sparkle:shortVersionString`, `pubDate` and `sparkle:minimumSystemVersion` (for example `14.0.0`).
- Release notes come from `sparkle:releaseNotesLink` or an embedded description.
- The enclosure needs `url`, `length`, `type="application/octet-stream"` and `sparkle:edSignature`.
- The installer refuses downgrades (Installation.md).
- [C] Signed feeds (`SURequireSignedFeed`, from 2.9) append a signature comment (Signing.swift:86-88). [U] Producing that on Linux means reproducing the format exactly.
- **Feed URL** [C, from the source]: Sparkle only checks that the feed URL is https (SPUUpdater.m:283) and has no redirect handler, so NSURLSession follows GitHub's 302s by default. A `releases/latest/download/appcast.xml` feed works.
- [U] The enclosure must use the **versioned** `releases/download/vX/Snaptic.zip`. The "latest" release is the newest non-prerelease.

**Info.plist and API** [C] (docs customization:20-30):
- `SUFeedURL`; `SUPublicEDKey`.
- `SUEnableAutomaticChecks`: unset means Sparkle asks on the second launch; YES or NO doesn't ask.
- `SUScheduledCheckInterval` (default 86400, minimum 1 h).
- `SUAutomaticallyUpdate` (default NO). The docs: "Updates may be downloaded but not installed automatically if authorization is required".
- `SUEnableSystemProfiling` (default NO).
- `SPUStandardUpdaterController` brings the standard UI. Dockless apps don't get focus-stealing alerts except at launch (docs gentle-reminders).
- Delegate hooks (SPUUpdaterDelegate.h): `mayPerformUpdateCheck` (:87), `willInstallUpdate` (:340), `shouldPostponeRelaunchForUpdate:untilInvokingBlock:` (:356), `updaterShouldRelaunchApplication` (:367), `updaterWillRelaunchApplication` (:374), and `willInstallUpdateOnQuit:immediateInstallationBlock:` (:440). The documentation for the last one says "Sparkle will always attempt to install the update when the app terminates."
- Termination uses an Apple quit event, which the app can delay. The install happens after the app exits, then Updater.app relaunches it (Installation.md).

**Root-owned bundle, quarantine, translocation** [C]:
- If the bundle or its parent isn't writable, Autoupdate is submitted as a **one-shot root launchd job** behind the admin prompt "**Snaptic wants permission to update.**" (SUInstallerLauncher.m:136-170, 340-374). The silent driver then falls back to the UI driver.
- Sparkle calls `AuthorizationRightSet` for `app.snaptic.Snaptic.sparkle2-auth` (:170-174), a persistent authorization-database right. [U] Whether it succeeds without admin rights is unknown.
- The new bundle gets the old bundle's owner and group.
- Quarantine is removed from the new bundle (SUPlainInstaller.m:48-52). `gktool scan` runs on 14.4 and later, and the atomic swap is allowed when there's no Team ID (:94-118, 347-366).
- [U] Expected: no Gatekeeper prompt after relaunch. Still to test on hardware: App Management (Ventura+) with an ad hoc updater on an ad hoc app.
- Sparkle silently skips updates for translocated or read-only copies (docs index.md:139).

**What goes over the network** [C]:
- User-Agent `"Snaptic/<shortVersion> Sparkle/2.10.0"` (SPUUserAgent+Private.m:18-22). The server also sees the IP address and the time.
- No system profile unless you opt in (SPUUpdater.m:1240-1270).
- HTML release notes render in WKWebView. Markdown notes work from 2.9 on macOS 12+. `SUShowReleaseNotes=NO` hides them.

**Ad hoc to ad hoc, and key rotation** [C] (SUUpdateValidator.m):
- An update is accepted if the archive verifies against the **old** bundle's EdDSA key, or if the code signatures match each other's designated requirement. An ad hoc designated requirement is a cdhash, so the code-signature path never matches: **the EdDSA key is the only trust anchor.**
- Rotation needs a Developer ID Team match (docs, "Rotating signing keys"), so **a lost or leaked key can't be rotated** under ad hoc signing.
- Updates are rejected if the EdDSA key is removed, or if the old app is signed but the new one isn't or is corrupted. Nested code has to be signed correctly.
- XPC client validation needs a host Team ID. **With none, it is skipped** (SUCodeSigningVerifier.m:448-451; AppInstaller.m:150-160).

**Advisories** [C]:
- CVE-2025-0509, fixed in 2.6.4: pkg signing bypass (cve.circl.lu).
- CVE-2025-10015 and CVE-2025-10016, fixed in 2.7.2: the Downloader XPC inherits TCC permissions; Autoupdate doesn't authenticate clients, giving root through a pkg (CERT Polska, 2025-09-16).
- Fixes in 2.9.2, 2.9.5 and 2.9.6 for symlink and race issues, some leading to root (Discussion #2838).
- **Minimum is 2.9.6; use 2.10.0.**
- [U] Because the 2.7.2 client-validation fix depends on a Team ID, what remains of the CVE-2025-10016 class for a root Autoupdate under ad hoc signing is unknown. The archive is still EdDSA-verified against the on-disk host key.

**License** [C]:
- Sparkle is MIT (Matuschak, Elgato, Lesiński, Pawashe, Betts, Petroules, Big Nerd Ranch). LICENSE:27-134 adds bsdiff (BSD), sais (MIT), ed25519 (zlib) and Mark Hamlin's component.
- THIRD_PARTY_NOTICES.md "Vendored code: None" and the Acknowledgements sheet (AboutPage.swift:120-133) must change.

## 3. Interactions specific to Snaptic

- **TCC** [C]: every ad hoc update has a new cdhash, so Accessibility and Screen Recording are lost (README:556, 572). After relaunch, only `reAddAtOnce` shows, and only when a guide opens. The switcher stays idle meanwhile.
  - [U] Proposal: store `lastRunBuild` (`CFBundleVersion` plus `SNProcess.executableUUID()`) and the previous grant set. When the build changed and a grant was lost, show "Snaptic was updated; allow it again (− then +)", for both permissions.
- **Displays** [C]:
  - Quit runs `host.shutdown()` → `DisplaysModule.stop()` (AppDelegate.swift:113-120; ModuleHost.swift:243-264; DisplaysModule.swift:155-190).
  - DisplayGuard reverts on parent EOF (DisplayGuardMain.swift:7-21). Virtual displays end with their hosts and return at the next launch, except in Safe Mode (SafeMode.swift:65-74).
  - A pending "Keep this change?" trial gets reverted. Gate on `DisplayTransactionQueue.isBusy` and `hasPendingTrial` (DisplayTransactionQueue.swift:83-84).
  - [U] Defer in `willInstallUpdateOnQuit` / `shouldPostponeRelaunch`, with `applicationShouldTerminate` `.terminateLater`, while a trial or confirm panel is open, or while a display is disconnected or mirrored to a virtual display.
- **Awake** [C]:
  - Quit keeps the snapshot, so sessions resume if `resumeAfterRestart` is on (AwakeModule.swift:122-123; SessionController.swift:1142-1146). `--pid` holds survive (README:405). `awake hold` clients exit 5 (README:404).
  - **Lid-closed mode (0.3.1 plan):** the root watchdog exits when the pid or beacon goes away, and its cleanup runs `pmset sleepnow` if the lid is shut (PLAN.md:420-438). The mode never resumes (PLAN.md:281, 302).
  - **An update-relaunch with the lid closed sleeps the Mac immediately.** [U] Refuse or defer the install while `AwakeLidMode != off`.
- **Relaunch race** [U]: Relauncher opens a new instance *before* the old one quits (Relauncher.swift:21-32), for permissions and Safe Mode. If an update is waiting to install on quit, Sparkle swaps the bundle while the new instance is starting (instance lock at AppDelegate.swift:29-46). When an update is pending, route the relaunch through `immediateInstallationBlock`.
- **Safe Mode** [C]: the quit is clean (LaunchStability.swift:32-37), so it doesn't count toward Safe Mode. A new build that crashes twice within 60 s still lands in Safe Mode, which is a good fallback. Holding ⇧ during the relaunch also triggers it (SafeMode.swift:55-57).
  - [U] In Safe Mode, block scheduled checks with `mayPerformUpdateCheck` but allow manual ones.
- **Control socket** [C]: unlinked at quit and recreated at launch (ControlServer.swift:6-7, 109-115, 393-394). The `/usr/local/bin/snaptic` symlink points at the bundle path (KitControl.swift:336-337) and survives an in-place swap. CLI calls during the swap get exit 5.
  - [U] Don't add an `update` verb, so the socket can't trigger privileged actions.
- **Installs** [C]: root-owned installs (`INSTALL=1`) need the admin password on every update, and Autoupdate runs briefly as root. User-owned installs update silently and already show the "writable" warning (PermissionsPage.swift:83-85).

## 4. Risks and open questions

1. **Blocker:** an ad hoc app with the hardened runtime can't load an ad hoc Sparkle.framework. The owner must choose a Team ID, `disable-library-validation`, or no hardened runtime before implementation starts.
2. Every ad hoc update loses the TCC grants. Automatic updates will regularly leave the switcher idle. Developer ID fixes this.
3. **EdDSA key custody:** no rotation under ad hoc signing. Keep it as a secret in a protected environment that only the `release` job can read. Losing it ends auto-update; a leak lets anyone push malicious updates.
4. The network promise changes: README:576/660/687, site:502/736, AboutPage.swift:36/56 and THIRD_PARTY_NOTICES.md:7 all need rewording, and the lint rationale needs restating. Is the automatic check on by default or opt-in (`SUEnableAutomaticChecks`)?
5. Release pipeline: read `CFBundleVersion` and `CFBundleShortVersionString` from the zip, check them against the tag (nothing enforces this today), sign with OpenSSL or Python, and write and upload `appcast.xml`. Should the script be inline in the workflow ("never runs repository code") or live in the repo?
6. Sparkle loads into every helper and CLI process. Accept it, or load it only in GUI mode (needs a lint-11 exemption)?
7. Sparkle runs processes outside HelperSpawner, plus caches in `~/Library/Caches/app.snaptic.Snaptic/org.sparkle-project.Sparkle`, `SU*` defaults and possibly an authorization-database right. This conflicts with "leaves nothing behind" (README:155).
8. Root Autoupdate with no Team-ID XPC validation: offer in-app updates only for user-owned installs, and keep the Releases-page button for root-owned ones?
9. Which deferral hooks to use for display trials, virtual-only or disconnected states, and lid-closed mode?
10. Hardware checks: App Management, gktool and Gatekeeper with an ad hoc to ad hoc swap on 14.4, 15, 26 and 27; the SwiftPM rpath; the universal build with a binaryTarget.
11. Appcast assets: zip only (it is attested), or the dmg from PR #2 too? Prefer Markdown or plain notes to avoid loading WebKit into a process with Screen Recording.
12. Settings: is the toggle a `ModulesConfig` field (then add it to Backup `removedPaths`) or Sparkle's own key? Add a kill switch such as `Updates.disable.check` (README:440 convention)?
13. `CFBundleVersion` is "1" today. Pick a monotonic scheme, for example 301 for 0.3.1, and decide how About shows it.
