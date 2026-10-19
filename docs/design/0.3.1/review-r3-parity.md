# Review r3: feature parity and product (0.3.1 PLAN r3, 8059eeb)

**Totals: 0 Blockers, 3 Majors, 9 Minors.**

All 11 of my r2 findings and all three cuts are fixed. Parts A and B are now in good product shape. The Majors are all in the new Part E.

---

## r2 findings: fixed or not fixed

| r2 | Finding | Status | Where in r3 / note |
|---|---|---|---|
| M1 | External display dimmed while the lid is shut | **Fixed** | B3.3 l.581: `lidShut` requires no external display and is re-evaluated on screen changes. HW-30 (c). |
| M2 | No keep-off answer for a leftover | **Fixed** | B3.4 l.648-657: Keep Sleep Off; Not Now hides the rows everywhere until next launch; B2 leftover refusal text. The new placement brings two small issues: m1 and m2. |
| m1 | No warning before the cap | **Fixed** | B1 l.318: a 5-minute toast. |
| m2 | No feedback while verifying | **Fixed** | B0 per-state pending text; B1 "Turning on lid-closed mode…" toast after 2 s. I also suggested a dimmed indicator; it wasn't adopted, and the toast is enough. |
| m3 | Writable-bundle warning shown to everyone | **Fixed** | B1: secondary help text, only while the toggle is on, with the chown fix. Part E changes what that fix costs; see M3. |
| m4 | "Paused" attention mark would be permanent | **Fixed** | A1: other-app pauses excluded. |
| m5 | A pending lid request could replace a new start | **Fixed** | B1 l.270-271, B3.0. |
| m6 | Users weren't told where to use the option | **Fixed** | Toggle help text, plus the `lidRoute` variants. |
| m7 | HW-30 lacked the external-display case | **Fixed** | HW-30 (c). |
| m8 | The submenu's note row read like a command | **Fixed** | Removed; the presets carry "…". |
| m9 | The "Snaptic quit" line showed after a restart | **Fixed** | B2: left out when the leftover rows explain it. |
| cuts 1-3 | Cap picker, History detail, CLI field | **Done** | Fixed 24 h cap; History keeps only the flag; the CLI change is JSON only. |

---

## Majors (all Part E)

### M1. Update alerts from a menu-bar app go unseen: E4 doesn't implement Sparkle's gentle reminders
**Evidence**
- Snaptic is `LSUIElement` (dockless).
- Sparkle's docs say a scheduled alert from a dockless app "won't take focus from another app or window, so it appears behind other windows. Users of these apps may never notice an update". They also say dockless apps "may log a warning" unless they implement at least `supportsGentleScheduledUpdateReminders` (https://sparkle-project.github.io/documentation/gentle-reminders/).
- E4 wraps `SPUStandardUpdaterController` with no `SPUStandardUserDriverDelegate`.
- The same applies to the impatient alert. When an update is downloaded but the app never quits, which is normal for a menu-bar app, Sparkle notifies only after `SUScheduledImpatientCheckInterval` (1 week), again behind other windows.

**Why it matters:** with auto-install off (E1 default; see M2), the "Update found" window in E1 is the only way an update gets installed, and it will often sit unseen behind the frontmost app. This defeats the owner's goal of "in-app updates instead of redownloading".

**Fix (E4 text)**
- `UpdaterController` adopts `SPUStandardUserDriverDelegate` and returns `supportsGentleScheduledUpdateReminders = true`.
- In `standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)`, return `immediateFocus`.
- Otherwise, `standardUserDriverWillHandleShowingUpdate` sets `updateAvailable` (version string). This drives two things:
  - a footer row in the Snaptic menu (and in own and custom menus when the shared item is absent): "Update Available: Snaptic 0.3.2…", which calls `checkForUpdates()` to bring Sparkle's window forward with focus;
  - the same line in Settings › About, with an "Update Available" status.
- `standardUserDriverDidReceiveUserAttentionForUpdate` and `standardUserDriverWillFinishUpdateSession` clear it.
- No Dock badge, no activation-policy flip, and no notifications: Snaptic has no Notification Center use, and the footer row is enough.
- Add to E7: control `menu.snaptic.updateAvailable` (`.menuItem`).
- Add to HW-36: "a scheduled update with Safari frontmost shows the footer row, and choosing it brings the Sparkle window forward".

### M2. Consent timing and the auto-install default don't fit a menu-bar app, or what the owner chose
**Evidence**
- E1 leaves `SUEnableAutomaticChecks` unset, so Sparkle asks on the **second launch**.
- Snaptic usually starts at login and runs for days, so the second launch is often the next reboot.
- That permission alert is a dockless window too, with the same focus problem as M1.
- E4 also leaves `SUAutomaticallyUpdate` unset (default NO), but the owner "chose Sparkle auto-install". With auto-install off, every update needs the user to find and click an alert.
- Comparable apps either keep themselves current without asking per update (Raycast; Amphetamine through the App Store's automatic updates) or use Sparkle's defaults with an in-app check item (Rectangle, MonitorControl, AltTab, Ice). I did not verify each one's current default for this review.

**Fix (E1 text)**
- Ask in Snaptic's own UI, then set `updater.automaticallyChecksForUpdates` from the answer. Setting it suppresses Sparkle's second-launch prompt.
  - **New installs:** onboarding gains a final "Updates" choice with "Check for updates automatically" (on) and "Download and install them automatically" (on). It includes the E5 sentence: "Snaptic contacts github.com once a day and sends nothing else."
  - **0.3.0 upgraders:** the same two toggles go in the one-time 0.3.1 card that already explains the permission re-grant (E2). They see that card anyway.
- `SUAutomaticallyUpdate` defaults to **on** once checks are allowed (`automaticallyDownloadsUpdates = true` when the user keeps the default). That matches the owner's choice and still respects consent: no check, and therefore no download, ever happens without the first toggle.
- Keep the General › Updates toggles as the place to change both later.

### M3. Root-owned copies have no silent updates, and B1's advice now pushes users into that path
**Evidence**
- E1: "Root-owned copies … macOS asks for an administrator password to install."
- Sparkle doesn't install silently when authorization is needed; it shows an alert instead (Sparkle gentle-reminders page: "Alerts also appear when the user must authorize installation…").
- B1's writable-bundle help and README tell lid-mode users to `sudo chown -R root:wheel /Applications/Snaptic.app`, and `INSTALL=1` does the same.
- So the users who follow Snaptic's own security advice lose auto-install. Every update then becomes an alert (unseen, per M1) plus a password prompt, and E1's "Download and install updates automatically" toggle silently does nothing for them.

**Fix**
- E1: when the bundle is not writable by the user, the auto-install toggle shows the help "Snaptic is installed by an administrator, so each update asks for an administrator password." The status row says "Updates need an administrator password".
- Remove the chown advice from B1's help text and README. Keep only "Install Snaptic in /Applications". E8 already says a same-user attacker can show the same dialog, and Sparkle's EdDSA plus Developer ID checks now protect the bundle's update path. If the owner wants to keep root-owned installs, state the trade-off in README's "Updating" section.

---

## Minors

### m1. (Part B) "Keep Sleep Off" sits one click away in every menu, with no undo
**Evidence**
- B3.4 l.647: every Snaptic menu shows "Keep Sleep Off".
- After a click, the value is "another app or command" (l.656). Snaptic then never offers Turn Sleep Back On… again, so the only way back is Terminal.

**Fix:** in menus, use "Keep Sleep Off…" with an alert: "Your Mac won’t sleep until you run `sudo pmset -a disablesleep 0` in Terminal." with **Keep Sleep Off** / **Cancel**. Or leave it out of menus and keep it on the Awake page and in Advanced › Other Apps only. Menus would then show the status row, Turn Sleep Back On…, and a "Not Now" that hides the rows.

### m2. (Part B) A leftover toast can't hold three buttons
**Evidence**
- B3.4 l.649: when Awake isn't running, "A toast with the same text, and the same three buttons".
- Toasts allow up to 2 actions (ToastPresenter.swift:85-89, R5-1).

**Fix:** the toast offers **Turn Sleep Back On…** and **Options…**, which opens Settings › Awake › Advanced › Other Apps with all three choices. Its dismissal means Not Now.

### m3. (Part E) There is no "Check for Updates…" menu item, but E1 and E7 say there is
**Evidence**
- E1 says "**Snaptic › Check for Updates…** (the existing item)", and E7 says "Menu table (existing 'Check for Updates…' item)".
- The only existing control is the Settings › About button (AboutPage.swift:36, `AboutPageControls`, whose help text is "Opens the Snaptic releases page in your browser.").
- E1 also adds a separate Updates section in General, so update controls end up split across two pages.

**Fix**
- E7: name `AboutPageControls`' existing id, and update its help text.
- Put the E1 toggles and status row on **About** under the version, which is where Rectangle and Ice keep them, instead of General.
- Don't add a permanent menu item. M1's footer row appears only when an update exists.

### m4. (Part E) Release notes link to the full GitHub page
**Evidence:** E3 sets `sparkle:releaseNotesLink` to the release's HTML URL.

**Why it matters:**
- Sparkle's window renders the whole github.com page, including its navigation, sign-in banner and scripts, inside a small web view.
- Only the newest item's link is shown, so someone skipping from 0.3.1 to 0.3.3 misses 0.3.2's notes.
- E5's promise "downloads `appcast.xml`, and an update" becomes untrue, because the full GitHub page also loads.

**Fix:**
- The `release` job writes each item's `<description><![CDATA[…]]></description>` as minimal HTML converted from `docs/design/<ver>/RELEASE-NOTES-<ver>.md`; a short markdown-to-HTML step for headings and lists is enough.
- Add `sparkle:fullReleaseNotesLink` set to the Releases page.
- Sparkle then shows clean notes for every version newer than the installed one.

### m5. (Part E) Deferring a user's own "Install and Relaunch" has no visible message
**Evidence:**
- E4 postpones relaunch while lid-closed mode is on, while a display trial is pending, or while CLI holds are active (up to 1 h).
- The message "Will install when lid-closed mode ends." appears only in the General Updates row.

**Why it matters:** a user who clicks Install and Relaunch sees Sparkle's window close and nothing happen.

**Fix:**
- When the postpone delegate fires for a user-initiated install, show a toast with the reason: "Snaptic will update when lid-closed mode ends." Use the same text family for a display trial ("…after you keep or revert the display change") and for holds ("…when command-line holds end, or within an hour").
- Use M1's footer row to show "Update Ready: Installs When Lid-Closed Mode Ends".

### m6. (Part E) After a silent install, nothing says Snaptic changed
**Evidence:** with auto-install, Sparkle replaces the app at quit. On the next launch, nothing in E says what changed. Raycast, for example, tells the user after it updates itself.

**Fix:** on launch, when `CFBundleVersion` is greater than the stored last-run version, show one toast: "Snaptic was updated to 0.3.2." with **What’s New**, which opens the release notes page. Keep the stored version as a plain `UserDefaults` key, like `settingsLastRoute`.

### m7. (Part E) The one-time permission reset should cover Screen Recording, and its steps should come first in the 0.3.1 notes
**Evidence:**
- E2 relies on the launched-before heuristic. That heuristic is Accessibility-only (KitHostUI.swift:24-30, `permission == .accessibility`).
- The Developer ID switch also resets Screen Recording (Switcher thumbnails).
- After the switch, macOS often shows the old Snaptic entry still toggled **on** while the new binary isn't trusted. Users report "it's on but doesn't work" when an app changes its signing.

**Fix:**
- Extend `showsReAddStepsAtOnce` to `.screenRecording`.
- The 0.3.1 card and release notes open with: "This is the last time you download Snaptic by hand. macOS will ask you to allow Accessibility and Screen Recording again once: remove the old Snaptic from each list with −, then turn on the new one."

### m8. (Part E) 0.3.0 users: the Releases-page button is enough, but the release itself has to say it
**Evidence:**
- 0.3.0 makes no network connections, so it can't learn that 0.3.1 exists.
- Its About › Check for Updates… opens the Releases page, and that is the only path.

**Verdict:** this is enough; nothing else is possible without network code in 0.3.0. The 0.3.1 GitHub release body, README "Updating", and the site should still lead with the m7 text, and add: "Quit Snaptic, then replace it in Applications." This is also worth stating once in the release title, for example "0.3.1: in-app updates (one last manual download)".

### m9. (Part E) Homebrew
**Evidence:** README has no Homebrew instructions, and no official cask is mentioned.

**Fix:** none needed for 0.3.1. Add one line to E8 or README: if a cask is ever published, it must set `auto_updates true`, so that `brew upgrade` doesn't fight Sparkle or downgrade.

---

## Over-engineering in Part E (no action required, owner's call)

- **Hand-rolled EdDSA signing (`openssl pkeyutl`) and a heredoc appcast** instead of Sparkle's own `sign_update` / `generate_appcast`.
  - It avoids running third-party binaries in the release job, which is reasonable.
  - But it is a second implementation the update path depends on.
  - Keep it only if E3's byte-identity test against `sign_update` runs in CI for each Sparkle version bump.
- **Deferring for CLI holds** ("waits up to 1 h, then installs at quit") is hard to explain. A hold only keeps the Mac awake; a relaunch re-arms `--pid` holds on restore, and only connection holds are lost.
  - Simpler rule: defer for lid-closed mode and pending display trials only.
- **Everything else in E is proportionate:** consent toggles, versioned enclosures, a `latest` feed URL, environment-scoped secrets, and weak linking for ad-hoc builds.

---

## Checked and fine

- **Part A r3:**
  - The labels' equal-width fallback order is right.
  - "More Display Features…" stays in the footer; it exists only while Displays is off, so my r1 m9 premise was wrong, and r3 handles it correctly.
  - No active image on the Awake segment is fine, since the indicator and N11 already show the session.
- **Part B r3:**
  - The fixed 24 h cap appears in the footer and the prompt.
  - "Replaced the running session." covers hotkey, CLI and launch sessions.
  - A hotkey replacement now ends the mode, which is consistent with the gate.
  - Display sleep runs as the user only while `lidShut` is true.
  - Low Power Mode is not a refusal.
- **Part E:**
  - Deferring the update while lid-closed mode is on is required: a relaunch would end the mode mid-session. It works.
  - Ad-hoc and source builds fall back to the Releases page with a clear line.
  - The `latest` feed never serves prereleases.
  - `SUEnableSystemProfiling = NO`, and the E5 wording is honest, apart from m4.
  - Team-ID designated requirements make grants survive future updates, which is the biggest user-visible win.
  - The Gatekeeper "Open Anyway" steps disappear for release builds.
