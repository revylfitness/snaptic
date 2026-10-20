# 0.3.1 plan r4 review: design, UX copy and consistency

Plan = `docs/design/0.3.1/PLAN.md` at 7b75ebe. DS = `docs/design/0.3/design-spec.md`. r3 = `review-r3-design.md`.

Result: 0 Blockers, 0 Majors, 9 Minors. All 16 r3 findings are fixed. The remaining items are copy and spec details that Step 0 can absorb.

## r3 findings: fixed or not fixed

| r3 | Topic | Status | Note |
|---|---|---|---|
| R3-M1 | Part E controls (home, ids, search, keys) | Fixed | Updates live on About; `about.page.*` ids; `about.page.checkUpdates` reused; search entries; no `keys`; new states `updaterAvailable`, `updateReady`, `userWritableBundle`. `OnboardingControls` is the real table (surface `onboarding`, so `onboarding.updates.*` passes the prefix test). Leftovers → R4-m1, R4-m2 |
| R3-m1 | B7 gaps | Fixed | ✓ title kept out of `when:`; `.awakeFeature(.lidClosed)` on all lid rows; `menu:` placements including the new `lidSubmenu` spec; `.state(.lidLeftover)` on the menu rows; `awake.custom.lidClosed` gated |
| R3-m2 | Four-line help | Fixed | `SettingsRowNote` plus Learn More… (`awake.advanced.lidBundleLearnMore`) |
| R3-m3 | Footer | Fixed | Split into short sentences; "the Awake page’s battery level" |
| R3-m4 | "Snaptic can’t change this." | Fixed | "Snaptic leaves it as it is." everywhere |
| R3-m5 | Leftover refusal hedge | Fixed | "Turn sleep back on first. It may have been left off by an earlier lid-closed session." Button title → R4-m5 |
| R3-m6 | `.lidEnded` toast | Fixed | Standard `AwakeEndText.toast` path; phrase "lid-closed mode turned off while the lid was closed" |
| R3-m7 | Wait texts | Fixed | Lid, display trial, Safe Mode. The CLI-hold deferral was dropped in E4, so three texts is right |
| R3-m8 | Status row states | Fixed | `UpdateStatusText`: last checked / not checked / checking / failed / ready / deferral. "Available but not downloaded" is missing → R4-m3 |
| R3-m9 | Toggle help | Fixed | Both rewritten and accurate |
| R3-m10 | Source builds | Fixed | Toggles hidden (`updaterAvailable`); explanatory row |
| R3-m11 | Network copy | Fixed | Heading, body ("github.com and its download host"), About footer, site l.502 |
| R3-m12 | Password advice | Fixed | Three choices, in B6 and E5 |
| R3-m13 | General summary | Moot | Updates live on About |
| R3-m14 | Sparkle first-run window | Fixed | Consent asked in Snaptic's own UI; Sparkle's window is suppressed during onboarding and in Safe Mode |
| R3-m15 | Pending row | Fixed | "Finishing Earlier Session…" |

---

## New findings (all Minor)

### R4-m1. Two `ControlState`s for the same fact
**Evidence.** B7 adds `.state(.bundleWritable)` (PLAN l.789, l.805) for the lid note. E7 adds `.state(.userWritableBundle)` (l.1110, l.1115) for the auto-install row. Both mean `PermissionFlow.bundleIsUserWritable` (PermissionFlow.swift:288). Two states that can't diverge invite a mismatch, and `ControlState` is a closed allowlist that Step 0 freezes.
**Fix.** Keep one state, `bundleWritable`, and use it in both tables. Drop `userWritableBundle` from E7's list.

### R4-m2. Missing copy for the 0.3.1 card and the onboarding step, plus one heading in the wrong case
**Evidence.**
- E1 l.919: the onboarding step heading is "Keep Snaptic up to date". The existing onboarding headings are Title Case: "Choose What Snaptic Does", "Allow Access", "You’re All Set" (Onboarding.swift:173, 217, 247).
- The step has no body text. It offers **Check Automatically** / **Not Now**, but the other steps move with Back / Continue (Onboarding.swift:278-281), and the plan doesn't say how the two fit together.
- E1 l.920 calls the 0.3.1 card "the one that already explains the one-time permission re-grant", but no such card exists. `GeneralPages.swift` has only `.displays`, `.awake` and `.awakeMigrated` (l.162-180). The card is new, and it has:
  - no title, body or button titles, except the re-grant sentence at l.948;
  - no id for its "Updates install automatically" toggle. `general.page.card.primary` / `.dismiss` (`perItem("card")`) cover only the two buttons.
- Onboarding steps normally get their own table with a sub-surface (`DisplaysOnboardingStepControls`, surface `onboarding.displays`). Putting the ids in `OnboardingControls` also passes, so this part is style only.

**Fix.**
- Step heading: "Keep Snaptic Up to Date".
- Step body: "Snaptic can check GitHub once a day for a newer version. GitHub sees your IP address and macOS version, nothing more."
- Step controls: a `ToggleSetting(L("Check for updates automatically"))`, on by default, with the step's Continue. This keeps one navigation pattern in onboarding and drops the two buttons. Alternatively, keep the two buttons and say that they replace Continue on this step.
- Card, as a new `GeneralCard` case:
  - title "New in 0.3.1";
  - body "Snaptic can now update itself. macOS may ask you to allow Accessibility and Screen Recording again: remove the old Snaptic with − in each list, then turn on the new one.";
  - primary "Check Automatically", dismiss "Not Now";
  - the toggle `general.page.card.autoInstall` (`.setting`, `when: [.perItem("card"), .state(.updaterAvailable), .state(.bundleWritable)]`, `SearchSpec` not required because of `perItem`), labelled "Install updates automatically".

### R4-m3. The status row has no "available but not downloaded" state, and the menu row's condition says "ready"
**Evidence.** E1 l.923: the menu row shows "When an update is found **or** ready", but `menu.snaptic.updateAvailable` and `about.page.installUpdate` are both `when: [.state(.updateReady)]` (l.1111-1112). `UpdateStatusText` has "Version 0.3.2 is ready to install." but no text for found-not-downloaded. That is the normal state with automatic install off, or for root-owned copies.
**Fix.**
- Rename the state `updateAvailable`, true when an update is found or downloaded.
- Add the status text "Version 0.3.2 is available." with **Install and Relaunch…**. That action brings Sparkle's window forward, where the download, password and relaunch happen; that is why the ellipsis is right.
- Keep "…is ready to install." for the downloaded case.

### R4-m4. The A1 footer note contradicts E1
**Evidence.** A1 l.99 says "The footer is unchanged from 0.3." E1 l.923 adds "Update Available: Snaptic 0.3.2…" to the Snaptic menu footer (and to own and Awake menus), but doesn't say where in the footer it goes.
**Fix.**
- A1: "The footer is unchanged from 0.3, except that **Update Available: Snaptic 0.3.2…** appears first in it while an update is available (E1)."
- Own and Awake menus: put the row in the same place as Recent Notices, and only when `plan.sharedFooterInOwnMenus`, so the row isn't repeated in every icon's menu while the Snaptic item already shows it.
- The title "Update Available: Snaptic 0.3.2…" passes the Title Case rule; the version number is skipped by `title_case_problem`.

### R4-m5. The toast button "Open Settings" breaks the house "Open … Settings…" pattern
**Evidence.** B2 leftover refusal and B3.4 toast: **Open Settings** (Awake › Advanced). Every existing "open settings" action names the place and ends in an ellipsis: "Open Accessibility Settings…", "Open Login Items Settings…", "Open Privacy Settings…" (GeneralPages.swift:201; Onboarding.swift:312), and the menu item "Awake Settings…".
**Fix.** "Open Awake Settings…", which opens Awake › Advanced.

### R4-m6. The auto-install search title differs from the label
**Evidence.** E7 l.1110: `about.page.autoInstall` search title "Install updates automatically", label "Download and install updates automatically" (E1). Every existing `SearchSpec` title matches its row label (for example "Appear active" and "Keep the display on while locked" in AwakeAdvancedSheetControls.swift). The search result then highlights a row with a different title.
**Fix.** `SearchSpec("Download and install updates automatically", keywords: ["auto install", "install updates", "sparkle"], root: SettingsRootID.about)`.

### R4-m7. "Install and Relaunch" with and without an ellipsis
**Evidence.**
- E1 status action: "Install and Relaunch…". It opens or brings forward Sparkle's window, which may ask for a password, so the ellipsis is right.
- The B6 and E5 advice says "Install and Relaunch", and Sparkle's own button is "Install and Relaunch".
- The root-owned explanation also refers to "an explicit **Install and Relaunch**".

**Fix.** In the advice text, name both: "…or Install and Relaunch (in Snaptic or Sparkle’s update window)". Leave the About action with its ellipsis.

### R4-m8. "Snaptic was updated to 0.3.2." toast
**Evidence.** E1 l.927. The text and the **What’s New** button (curly ’, no ellipsis because it opens a web page) are fine. Two things are unspecified:
- whether the toast also shows after an install the user started (Install and Relaunch), not only a silent one;
- that it must not show on the first launch after the 0.3.0 → 0.3.1 manual download, where the 0.3.1 card already covers it.

**Fix.** Add one line to E1: "Shown after any Sparkle install, once per version; not after a manual install (no Sparkle install marker)."

### R4-m9. The root-owned row's wording
**Evidence.** E1: "Snaptic is installed by an administrator, so each update asks for an administrator password." The condition is "the bundle isn't writable by your account" (`!bundleWritable`). That is also true when a non-admin user drags Snaptic into a folder they can't write, or when an admin dragged it in for another user. In those cases "installed by an administrator" may be untrue.
**Fix.** "Only an administrator can change this copy of Snaptic, so each update asks for an administrator password."

---

## Strings checked against lint03 and DS (no problems)

- **Title Case menu rows:**
  - "Update Available: Snaptic 0.3.2…" (ellipsis: Sparkle's window follows);
  - "Finishing Earlier Session…" (disabled; ellipsis means "in progress", like "Starting…");
  - "Sleep Is Turned Off", "Turn Sleep Back On…";
  - "Show Window Switcher Tab", "Show Displays Tab", "Show Awake Tab";
  - "Keep Awake with the Lid Closed…/›" and the ✓ form;
  - preset titles with "…".
- **Sentence-case labels:** the toggles "Check for updates automatically", "Download and install updates automatically" and "Keep awake with the lid closed"; the Advanced section "Lid closed"; the About section "Updates".
- **Toasts** are sentence case with curly apostrophes:
  - "Snaptic was updated to 0.3.2.";
  - "Awake ended: lid-closed mode turned off while the lid was closed.";
  - "Turning on lid-closed mode…";
  - "Replaced the running session.";
  - "Lid-closed mode turns off in 5 minutes. If the lid is closed then, your Mac goes to sleep.";
  - "Lid-closed mode turned off after 24 hours. Awake is still on; your Mac sleeps if you close the lid.";
  - the B2 refusals.
- **Status and wait texts** are full sentences:
  - "Version 0.3.2 will install when lid-closed mode ends.";
  - "Updates are paused in Safe Mode. Choose Check for Updates… to update anyway." (names the real button);
  - "Snaptic couldn’t check for updates. Check your connection and try again." (says what to do).
- **Help texts:** each sentence is at most about 90 characters; no "we"; "your" is used sparingly; "Mac", not "computer".
- **`SettingsRowNote`:** the writable-bundle text plus Learn More… follows the AwakeAdvancedSheet.swift:71 pattern.
- **"Keep Sleep Off"** is a Settings-only button, Title Case, with no ellipsis (no input). Other Apps then says "Snaptic leaves it as it is."
- **E7 kinds and conditions:**
  - `.setting` with `SearchSpec` on About (a Settings surface);
  - `.statusAction` for `installUpdate`, which needs no search;
  - `.button` for onboarding, which is exempt from search (`otherSurfaces` contains "onboarding");
  - `.parentOn(ControlID(…))`;
  - no `keys` for Sparkle defaults, like `general.page.openAtLogin`;
  - `menu.snaptic.updateAvailable` built by the same host factory as the leftover rows, so L15 holds in IndicatorController.
- **Numbering:** HW-36 to HW-38 continue the sequence, L19 is new, and N19 and L18 are unchanged.

---

## Verdict

**Ready to implement.**

No Blocker or Major remains in this lens. R4-m1 (the duplicate `ControlState`) and the R4-m2/R4-m3 control and state names should be settled in Step 0, because Step 0 freezes `ControlRegistry`. The rest is copy that T-update, T-lid-app and T-docs can take straight from this file.
