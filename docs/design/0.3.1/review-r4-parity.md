# Review r4 (final): feature parity and product (0.3.1 PLAN r4, 7b75ebe)

**Totals: 0 Blockers, 1 Major, 7 Minors.**
**Verdict: Ready to implement**, provided Step 0 writes the one missing spec in M1 (the 0.3.1 upgrade card). Nothing else blocks.

---

## r3 findings: fixed or not fixed

| r3 | Finding | Status | Where in r4 / note |
|---|---|---|---|
| M1 | Unseen update alerts | **Fixed** | E1 "Update alerts": `supportsGentleScheduledUpdateReminders`, an "Update Available: Snaptic 0.3.2…" row in every menu footer and on About, brought forward with `NSApp.activate`; HW-38. |
| M2 | Consent timing; auto-install default | **Fixed, one gap** | E1 "Consent": Snaptic asks in onboarding and in the 0.3.1 card, and never shows Sparkle's prompt. Auto-install is on by default in the card. The gap: the card itself is unspecified (new M1). The new-user default is unstated (m2). |
| M3 | Root-owned copies | **Fixed (alternative)** | E1: the auto-install row is hidden for root-owned copies, with an explanation; E8. The chown advice stays, but without its update cost (m3). |
| m1 | Keep Sleep Off in menus | **Fixed** | B3.4 l.661: Settings only. |
| m2 | A toast with three buttons | **Fixed** | B3.4: Turn Sleep Back On… plus Open Settings. Check that the target exists (m5). |
| m3 | No menu item; controls split | **Fixed** | E1/E7: everything is on About; `about.page.*` ids; the Update Available row. |
| m4 | Web release notes | **Fixed** | Embedded Markdown (`--embed-release-notes`, `sparkle:format="markdown"`), plus `fullReleaseNotesLink`. Nothing loads from github.com to render them. |
| m5 | No deferral feedback | **Fixed** | `UpdatePolicy.waitText`, plus a toast when the user clicks Install and Relaunch. |
| m6 | Silent update | **Fixed** | "Snaptic was updated to 0.3.2." with What’s New. |
| m7 | Screen Recording re-grant | **Fixed** | E2: the card covers both permissions; the heuristic is extended. |
| m8 | 0.3.0 users | **Fixed** | Release title and notes say "one last manual download" (T-docs). |
| m9 | Homebrew | **Fixed** | README note: a future cask sets `auto_updates true`. |
| over-eng. | Hand-rolled signing; CLI-hold deferral | **Resolved** | Sparkle's own pinned `generate_appcast`/`sign_update`; CLI-hold deferral dropped. |

---

## Major

### M1. The "0.3.1 card" is the whole upgrade experience, and it isn't specified
**Evidence**
- E1 (l.920) and E2 (l.948) depend on "a one-time 0.3.1 card, the one that already explains the one-time permission re-grant". No such card exists:
  - 0.3.0's cards are General-page cards (`newModuleCards`, GeneralPages.swift:36; `MigrationNotices`). They show only when the user opens Settings.
  - No section of r4 defines the 0.3.1 card's trigger, where it appears, its text, its controls or its dismissal.
- E7 lists only the `onboarding.updates.*` ids; the card has no ids at all.
- Upgrader detection is unstated. 0.3.0 stores no last-run version, so E1's post-update toast logic (`CFBundleVersion` greater than the stored value) can't tell a 0.3.0 upgrader from a fresh install either.

**Why it matters:** every existing user, the owner included, gets three things only through this card:
- the update consent (without it, updates never turn on);
- the Accessibility and Screen Recording re-grant steps, without which the Window Switcher and thumbnails silently stop working;
- the news about tabs and lid-closed mode.

If it is a General card, a user who never opens Settings sees none of it.

**Fix: add E1a, "The 0.3.1 upgrade card", in Step 0.**
- **Trigger:** a new `MigrationID.v031` recorded in `MigrationLedger`. It applies when `SnapticModulesV1` exists (an upgrader) and the ledger doesn't have the marker yet.
- **Where:** at the first launch, Settings opens on General with the card at the top, as onboarding does for new users. The card also stays until dismissed.
- **Content:**
  1. "Allow Accessibility and Screen Recording again", with the "remove the old Snaptic with −" steps and an Open System Settings button for each permission that is missing.
  2. "Keep Snaptic up to date": **Check Automatically** (with "Updates install automatically" on, hidden for root-owned copies) and **Not Now**.
  3. One line on what's new: "The Snaptic menu now has a tab for each module. New: keep awake with the lid closed (Awake › Advanced)."
- **Controls:** `general.card.v031.*` in `GeneralPageControls`.
- **Stored version:** start storing the last-run version now (`snapticLastRunVersion`, a plain UserDefaults key), so later post-update toasts work.

---

## Minors

### m1. Open at Login across the signing change is untested
**Evidence:** `OpenAtLoginRow` uses `SMAppService.mainApp` (GeneralPages.swift:187-225). Background Task Management records the app's code signing identity. Going from ad hoc to Developer ID may leave a stale login item, show "Login Item Added", or turn the item off. Insomnia's spec documents the login item being dropped across re-signing (docs/spec.md §10).

**Fix:**
- Add to HW-38: "0.3.0 with Open at Login on → 0.3.1: does Snaptic open at the next login? What does System Settings › Login Items show?"
- If the item drops, the card (M1) re-registers it once, when 0.3.0 had it on. This can be detected because the item is gone while the config says the user enabled it.

### m2. The new-user auto-install default is unstated
**Evidence:** the onboarding step offers only **Check Automatically** / **Not Now** (E1 l.919). §R3 says "auto-install on by default once allowed", but E1 spells that out only for the 0.3.1 card.

**Fix:** E1: "Check Automatically also sets `automaticallyDownloadsUpdates = true`, except for root-owned copies; the About toggle changes it." Mention it on the step: "Updates install when Snaptic quits."

### m3. The chown advice doesn't mention what it costs for updates
**Evidence:** B1 l.252 and B6 l.746 still recommend `sudo chown -R root:wheel /Applications/Snaptic.app`. E8 says a root-owned copy "needs an administrator password every time" to update, and E1 hides auto-install for it.

**Fix:** add one sentence where the advice appears in README: "Snaptic then asks for your administrator password for each update, and can't install updates automatically."

### m4. The Update Available row reads the same whether there is anything to do
**Evidence:** E1 shows "Update Available: Snaptic 0.3.2…" both when an update is *found* and when it is *downloaded and ready*. With auto-install on, a ready update needs nothing from the user: it installs at quit.

**Fix:**
- Found, with auto-install off: "Update Available: Snaptic 0.3.2…".
- Ready, with auto-install on: "Restart to Update Snaptic (0.3.2)". Choosing it calls the stored `immediateInstallationBlock`.
- Both strings live in `UpdateStatusText`.

### m5. The leftover toast's Open Settings may lead nowhere when Awake is off
**Evidence:** B3.4: when Awake isn't running, the toast's second button opens "Awake › Advanced". Advanced is a sheet hosted by the Awake page, and its Other Apps section reads Awake's runtime (OtherAssertionsReader). With the module off, the page may show only its enable state. [U]

**Fix:** state that the leftover block (text plus the three buttons) renders on the Awake page's top level, whether or not Awake runs, and that the toast opens `SettingsRoute("awake")`. Add it to HW-32 ("with Awake turned off").

### m6. A "Not Now" on onboarding updates is final, and About doesn't say why
**Evidence:**
- After **Not Now**, nothing asks again. That is right for consent.
- The About status row then reads "Not checked yet" (E1), which suggests a check is coming.

**Fix:** with automatic checks off, the status row reads "Automatic checks are off. Choose Check for Updates… or turn them on above."

### m7. Tabs and the gentle-reminder row
**Evidence:** the Update Available row sits in the footer, so it shows under every tab. That is good. The leftover rows sit above the tab bar. The plan doesn't define the order when both a leftover and an update exist.

**Fix:** state it in A1's sketch: safety group (Safe Mode, then leftover), tab bar, section, then the footer with Update Available first.

---

## Owner's-perspective check

**(a) "A tab for each enabled module": delivered.**
- Fresh and existing default setups show **Window Switcher | Displays | Awake** as segments (MenuLayout.swift:126-145). Only the selected section shows below them.
- The tab is remembered, with ⌘1–⌘3.
- Attention marks keep warnings visible.
- Modules set to their own icon or to Don't Show have no tab; the Menu Bar footer explains this.

**(b) Lid-closed keep-awake "just like Insomnia": delivered, with the owner's chosen differences.**
- **Enable once:** Awake › Advanced › "Keep awake with the lid closed".
- **Each use:** Awake menu → "Keep Awake with the Lid Closed ›" → choose a length → Touch ID or password. That is 2 clicks plus a hover; Insomnia is click, type, Enter.
- **Like Insomnia:**
  - timed sessions with a 24 h ceiling;
  - battery floor at least 10% (one setting);
  - heat cutoff;
  - display dark with the lid shut;
  - read-back after 5 s;
  - a recovery journal and leftover recovery;
  - Low Power Mode allowed.
- **Better than Insomnia:**
  - nothing is installed, and no sudoers rule;
  - turning off needs no password;
  - root-side floor and heat checks while Snaptic hangs;
  - `sleepnow` after an end with the lid shut.
- **Not included, deliberately:** Insomnia's app freezing, muting, keyboard-backlight control and Wi-Fi extras.

**(c) In-app updates instead of redownloading: delivered from 0.3.1 onward.**
- Signed, notarized and EdDSA-verified Sparkle updates, installed at quit by default once allowed.
- Gentle reminders in the menu.
- Deferral while lid-closed mode or a display trial is active.
- Builds from source keep the Releases-page fallback.

**The owner's first experience, installing 0.3.1 by hand from 0.3.0** (with M1 and m1 fixed):
1. **Get it.** Settings › About › Check for Updates… in 0.3.0 opens the Releases page. Download the DMG; it is notarized, so there are no "Open Anyway" steps. Quit 0.3.0 and drag the new copy over the old one. If 0.3.0 was root-owned (`INSTALL=1`), Finder asks for a password.
2. **First launch.** There is no Gatekeeper warning. Settings, presets, rules and display profiles carry over, because the bundle id and defaults domain are unchanged.
3. **Permissions.** macOS treats the app as new, so Accessibility and Screen Recording look **on** in System Settings but don't work.
   - The Window Switcher tab shows the attention mark.
   - The 0.3.1 card (M1) walks through remove-and-re-add for both permissions.
   - The same card asks about updates: Check Automatically, with auto-install on.
   - Without M1 specified, this step is the risk: a silent Switcher failure and no update consent.
4. **Menu.** Three tabs, opening on Window Switcher (nothing is stored yet); the Awake tab shows the full rows.
5. **Lid-closed mode.** Off until enabled in Awake › Advanced. The card's what's-new line points there.
6. **Login.** Open at Login should survive the re-signing; HW-38 confirms (m1).
7. **0.3.2 onward.** No more downloads. Updates install at quit, a "Snaptic was updated" toast follows, and grants persist because the requirement is now based on the Team ID.

---

## Checked and fine

- **E0:** the release setup is recorded, with split environments, tag-only rules and owner approval, and the certificate expiry is noted in E8. The pending license-agreement step is called out.
- **E3:** a draft release is published last, so `latest` never lacks an appcast; the `verify` job runs the signed app with Sparkle loaded.
- **Safe Mode:** scheduled checks stop, but a check the user starts still works, so a crash-looping release can still be fixed.
- **Relauncher:** with an install pending at quit, it installs once.
- **E5 network copy:** honest and specific.
- **Part B r4:** "Finishing Earlier Session…" is a pending state; there is no Keep Sleep Off in menus; the "Snaptic leaves it as it is." wording is consistent.
- **Part A r4:** unchanged from r3, apart from wording; nothing new found.
