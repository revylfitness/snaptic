# 0.3.1 plan review r4: security (final planning round)

**Plan:** `docs/design/0.3.1/PLAN.md` r4 (7b75ebe).
**Lens:** security, covering Part B as revised and Part E as revised, including E0.

**Checked against:**
- r3 findings and §R3;
- the r4 diff of `build.yml` and `scripts/make-dmg.sh`;
- Sparkle sources on the **`2.x` branch** (the `2.10.0` tag path wasn't fetchable here; the behavior is assumed identical, and HW-36 confirms it):
  - `Sparkle/SUUpdateValidator.m`, `SPUUpdaterDelegate.h`, `SPUUpdater.h`;
  - `generate_appcast/{main,FeedXML,ArchiveItem}.swift`, `common_cli/Signing.swift`;
  - the customization docs.

**Counts:** 0 Blockers, 1 Major, 8 Minors. **Verdict: Not ready.** One Major (M1) needs a short E3 text change first. See the end.

## r3 findings: fixed / not fixed

| r3 | Topic | Status | Notes |
|---|---|---|---|
| B1 | Sparkle accepts EdDSA **or** code signing | **Fixed** | E2 now states the trust model exactly as `SUUpdateValidator.m` implements it. The secrets are split into the `release` and `appcast` environments, both set up (E0). `SUVerifyUpdateBeforeExtraction` is on, and there's a runbook. One runbook gap remains (m1). |
| M1 | Access to the release environments | **Fixed** | E0 has tag-only environments with mandatory owner approval and no admin bypass, plus an admin-only `v*` tag ruleset; `sign` checks the tag is an ancestor of main. Residual: the `main` ruleset is still optional (m5). |
| M2 | Unsigned feed, web release notes, feed pinning | **Fixed, with a new hole** | Signed feed (`SURequireSignedFeed`), embedded Markdown notes, and delegate pinning are in place. The delegate API names are verified below. But reusing the previous appcast can launder unsigned edits into the next signed feed (new **M1**). |
| M3 | Blind hand-off between jobs | **Fixed** | Pinned Sparkle hashes before signing; hashes passed as job outputs; `verify` has no secrets; `publish` needs `[sign, verify, attest]` and runs `gh attestation verify`; tags only; no caches. Residuals in m3 and m6. |
| m1 | Lost key | **Fixed** | Runbook added; it has the DMG gap in m1 below. |
| m2 | Workflow hygiene | **Fixed** | Tag regex, every `${{ }}` through `env:`, actionlint, and `pull_request_target`/`workflow_run` banned by lint. |
| m3 | Seed handling | **Fixed** | `$RUNNER_TEMP`, `umask 077`, `::add-mask::`, removed in `always()`, never `set -x`. See also m7. |
| m4 | Sparkle loaded in helpers | **Fixed** | Stated honestly (E4, E8). |
| m5 | Team-ID TCC equivalence | **Fixed** | Only tags are signed; E2 and E8 say why. |
| m6 | API key role | **Fixed** | The ASC key has the Developer role (E0). |
| m7 | Safe Mode blocks fixes | **Fixed** | `updater(_:mayPerform:) throws` refuses only scheduled checks. |
| m8 | Sparkle admin prompt vs the password advice | **Fixed** | The advice now includes Install and Relaunch, and auto-install is hidden for root-owned copies. |
| m9 | `spawnTool` | **Fixed** | Same identity check, environment and disclaim as `spawnAdminScript`; single flight. |
| m10 | Root ownership after an update | **Fixed** | HW-38. |
| m11 | `HALT` set on any TERM | **Accepted** | Stated in B3.2. |

## Facts verified for this round (Sparkle source)

- **`--ed-key-file` exists** (`generate_appcast/main.swift:83`). It takes a path, or `-` to read the key from stdin.
- **`generate_appcast` signs the feed only when `requiresSignedAppcast` is true** (`FeedXML.swift:295–313, 650–653`).
  - That is true when the previous appcast was already signed, or when any archive's `Info.plist` has `SURequireSignedFeed = YES` (`ArchiveItem.swift:246–250`).
  - Snaptic's `Info.plist` sets that key (E4), so the feed does get signed. E3's stated reason, "signs the feed itself when an EdDSA key is given", is inaccurate (m4).
  - The comment written is `<!-- sparkle-signatures:\nedSignature: …\nlength: …\n-->` (`Signing.swift:85–88`).
- **`--embed-release-notes` works with Markdown.** A `.md` (or `.markdown`) file whose basename matches the archive is used, with format `markdown` (`ArchiveItem.swift:435–461`; usage text at `main.swift:192–194`). So `Snaptic.md` next to `Snaptic.zip` is right.
- **Delegate names are correct:**
  - `feedURLStringForUpdater:` (`SPUUpdaterDelegate.h:123`) is Swift `feedURLString(for:)`, and it takes precedence over a defaults-stored URL (`SPUUpdater.h:267–273`).
  - `clearFeedURLFromUserDefaults` exists (`SPUUpdater.h:287`).
  - `updater:mayPerformUpdateCheck:error:` (`SPUUpdaterDelegate.h:87`) is Swift `updater(_:mayPerform:) throws`.
- **The pre-extraction fallback needs a signed archive.** With `SUVerifyUpdateBeforeExtraction = YES`, a download that fails the old EdDSA key is accepted only if the **downloaded archive itself** is code-signed with the host's Developer ID team (`SUUpdateValidator.m:60–113`, `codeSignatureIsValidAtDownloadURL:andMatchesDeveloperIDTeamFromOldBundleURL:`). A zip carries no code signature; a signed DMG does. This bears on m1.

---

## Major

### M1. Reusing the previous `appcast.xml` launders unsigned edits into the next signed feed
**Evidence**
- E3 `publish` step 3 puts "the previous `appcast.xml`, if any, from the latest release" into the folder.
- Step 4 runs `generate_appcast`. That tool keeps existing items from the old XML (only new archives get new items), strips any old signature to decide `appcastWasPreviouslySigned` (`FeedXML.swift:218–239`), and then signs the whole output with the release key (`:650–653`).
- Nothing in it verifies the old signature.
- Release assets on the current "latest" release can be replaced by anyone with repository write access, or by any token with `contents: write`. No approval gate covers that.

**Why it matters.** `SURequireSignedFeed` exists to stop exactly this (r3 M2). Today an edited asset is rejected by clients. After the next release, the edit is re-published under the owner's key. Examples:
- an informational-update link pointing elsewhere;
- changed notes;
- a changed `minimumSystemVersion` that hides updates.

It can't install code, because each enclosure still needs EdDSA or Team signing. It can redirect users and freeze updates, under Snaptic's own signature.

**Fix (E3 `publish`, before step 4):**
- Verify the downloaded previous appcast's `sparkle-signatures` comment against `SUPublicEDKey` (the E0 value, pinned in the workflow). Strip the trailing comment, then check the Ed25519 signature over the remaining bytes, either with `openssl pkeyutl -verify -rawin -pubin` or with a small Swift snippet run inline.
- If it doesn't verify, fail the job. Don't silently drop the file: a missing appcast would also drop the history.
- Add to HW-36: tamper with a published appcast and check that the next `publish` fails.

---

## Minor

**m1. The EdDSA-leak runbook won't work with a zip enclosure.** E2's runbook says to "ship a Developer ID-signed update carrying the new `SUPublicEDKey`".
- With `SUVerifyUpdateBeforeExtraction = YES`, an archive that fails the old key falls back only to a code signature **on the archive itself**. A zip has none, so the rotation update would be rejected and users stranded.
- Fix: write the step as "publish that update with the **Developer ID-signed, notarized `Snaptic.dmg`** as the enclosure (signed with the new EdDSA key)". `sign` already produces that DMG.
- Add to E2 that the same path is what a leaked certificate alone would use, so the trust model is unchanged.

**m2. Revoking a leaked certificate has side effects.** Revoking a Developer ID Application certificate can make Gatekeeper refuse to launch earlier downloads that were signed with it.
- Add to the runbook: coordinate the invalidity date with Apple Developer Support, then re-sign and re-publish current downloads with the new certificate.
- The same team keeps the designated requirement, so TCC grants survive.

**m3. `sign` runs repository code while the Developer ID keychain is unlocked.** Step 6 runs `./scripts/make-dmg.sh`. It is the only repository script that runs in a job holding the p12 and notary secrets, and a change to `scripts/` is easier to miss in an approval review than a change to `.github/`.
- Inline the `hdiutil` steps in the YAML (r3's text did this). Alternatively, lock and delete the keychain and clear the secret variables before running the script, then re-import for the DMG `codesign`.

**m4. Feed-signing wording and check.**
- **Wording.** E3 step 4 should say the feed is signed "because the app's `Info.plist` sets `SURequireSignedFeed`".
- **Check.** "The resulting comment is checked" should mean the signature is **verified** against the pinned public key, not just found (the same code as M1).
- **Full notes link.** E1 promises `sparkle:fullReleaseNotesLink`, but the E3 command has no `--full-release-notes-url`; `--link` is the product link (`main.swift:114–117`). Add the flag.

**m5. Two environments don't separate custody against a malicious workflow at an approved tag.**
- Both jobs run the YAML from the same tag and are approved by the same person. A workflow change merged to `main` and then tagged gets both secrets after two clicks.
- E2's "one compromised environment never holds both" is true for secret leaks, not for workflow changes.
- **Make the `main` ruleset mandatory** before the first signed release. It is "optional" in E0. It should require PRs, block force pushes, and add CODEOWNERS on `.github/**`, `scripts/**` and `Package.*`.
- Add an approval checklist to the README's release section: review the diff since the previous tag in those paths.

**m6. `attest` attests whatever it downloads.** It `needs: sign`, but it runs in parallel with `verify`, which runs repository code and has the run's artifact token.
- `publish` catches a swapped artifact, but a provenance attestation for the wrong bytes could still be published.
- Give `attest` the same hash check against `sign`'s job outputs before it attests.

**m7. The seed can stay off disk.** `generate_appcast --ed-key-file -` reads the key from stdin (`main.swift:83`).
- Pipe `SPARKLE_ED_PRIVATE_KEY` in from `env:` instead of writing `$KEYFILE`. That removes one file from the seed-handling surface.

**m8. Set "latest" explicitly.** `SUFeedURL` follows GitHub's "latest" release.
- A non-draft release created by hand for an existing tag, with no `appcast.xml`, can become "latest". Every client then gets a 404, and updates stop.
- In `publish`, use `gh release edit --draft=false --latest`.
- In the README's release section: never create releases by hand.

---

## Part B (r4 changes)
No new issues.
- `ksd` now tells apart "no root-domain output" (`?`, which counts toward a restore) from "property absent" (0, as powerd's behavior explains). The "not ours" exit still needs both sources to read 0 twice, so an `ioreg` failure can't produce it.
- The shell test also runs under bash 3.2 in `build`.

## Checked and found fine
- **Signing and notarization (E2 and E3 `sign`):**
  - inside-out `codesign` with `--timestamp` and runtime, then `--verify --strict --deep`;
  - an assertion that there are no entitlements; library validation stays on;
  - `spctl` after stapling, for both the app and the DMG;
  - tag checks, including that the version is higher than the last published one, which refuses re-publishing an old tag.
- **Build separation:** two bundles from one compile; Sparkle only in the unsigned `build/release` bundle; `main` and PR builds stay ad hoc with no Sparkle.
- **Tool pinning:** pinned SHA-256 for both the framework binaries and the `Sparkle-2.10.0.tar.xz` tools.
- **Publishing:** the draft-first sequence (published last); hashes compared with job outputs, plus `gh attestation verify`, before anything is signed.
- **App side (E4):**
  - the `Bundle(identifier:)` gate for weak-linked Sparkle;
  - GUI-only creation;
  - `mayPerform` lets manual checks run in Safe Mode;
  - `feedURLString(for:)` plus `clearFeedURLFromUserDefaults()`.
- **Install timing:** install-on-quit through the stored `immediateInstallationBlock` in Relauncher; auto-install hidden for root-owned copies; consent asked in Snaptic's UI, with no Sparkle prompt.
- **Docs and lint:** the E5 network text matches the real trust model; the B6 advice covers Install and Relaunch; L19 restricts Sparkle identifiers to one file.
- **Part A:** no security change.

---

## Verdict: **Not ready**, pending one Major (M1)

There are no Blockers. **M1 must change first.** In E3 `publish`, verify the previous appcast's EdDSA signature against the pinned `SUPublicEDKey`, and fail if it doesn't verify, before `generate_appcast` re-signs it. Add a HW-36 tamper check.

This is a paragraph of plan text. With it applied, the plan is ready to implement from a security standpoint. Fold m1 (DMG enclosure for key rotation), m3 (no repository script while the keychain is unlocked) and m5 (mandatory `main` ruleset with CODEOWNERS) into Step 0; they are cheap and close the remaining custody gaps.
