# 0.3.1 plan review r3: security

**Plan:** `docs/design/0.3.1/PLAN.md` r3 (8059eeb).
**Lens:** security. That covers Part B as revised, and the new Part E: Sparkle 2, Developer ID, and the release pipeline.
**Checked against:**
- r2 findings, §R2 and `briefs/updates.md`;
- `.github/workflows/build.yml` (current);
- Sparkle `2.x` source: `Sparkle/SUUpdateValidator.m` and `SUConstants.m`;
- the Sparkle customization docs.

**Counts:** 1 Blocker, 3 Majors, 11 Minors.

## r2 findings: fixed or not fixed

| r2 | Topic | Status | Notes |
|---|---|---|---|
| B1 | `&` backgrounded the whole `check && run` list | **Fixed** | B3.2 now has three lines: `check … \|\| exit $?`, then `nohup … &`, then `echo $!`. Only the second line is async, and `$!` is nohup's pid, which execs `sh`. A CI shell test runs under dash and `bash --posix`, plus HW-31. |
| M1 | README advice vs a writable bundle | **Fixed** | The advice now applies only to root-owned installs, with a warning under the setting and the chown route. New caveat from Part E in m8. |
| M2 | Hotkey replacement kept the mode | **Fixed** | Keep applies only to `.menu`, and `.settings` with `mayStart`. A hotkey replacement ends the mode, and the gate test has hotkey rows. |
| M3 | Loose `sd` parse drove the non-restoring exit | **Fixed** | `sd` reads only the first match in the System-wide block and returns 0, 1 or `?`. `ksd` reads the kernel property on IOPMrootDomain. "Not ours" needs both sources to read 0, twice. Any disagreement restores. |
| m1 | EmergencyActions C-string lifetime | **Fixed** | `LidStopPath` class, never freed. |
| m2 | Beacon fd closed while the heartbeat used it | **Fixed** | Closed in the timer's cancel handler, on the same queue. |
| m3 | pid bounds | **Fixed** | `1 < pid < 100000`, plus uid 0 and a start time after the spawn (via `sysctl`). |
| m4 | TERM waited for the foreground sleep; `sleepnow` at shutdown | **Fixed** | `sleep & wait`, and a `HALT` flag. Residual in m11. |
| m5 | Stale clamshell key | **Fixed** | Waits for the kernel to read 0, then re-reads for up to 3 s. |
| m6 | `MODE` not validated | **Fixed** | |
| m7 | L18 gaps | **Fixed** | `do shell script` added, the requirement lives in Kit, and the definitions are exempt. |
| m8 | osascript not disclaimed | **Fixed** | Disclaimed by default. HW-28 decides otherwise. |
| m9 | Planted-journal wording | **Fixed** | "may be from …", and the README advice covers recovery. |
| m10 | Cap clock on replacement | **Fixed** | `capStart` never resets. |

---

## Blocker

### B1. E5 and E8 misstate Sparkle's trust model: either secret alone is enough to ship an update to every user

**Evidence: the plan's claims**
- E8 (PLAN:1004): "A leaked key plus a stolen Developer ID would be needed to push a malicious update. Either one alone isn't enough, because Sparkle requires the update to be Developer ID-signed by the same team once the host is."
- E5 (PLAN:972): "Every update is verified twice before installing: an Ed25519 signature from Snaptic's release key, and Apple's Developer ID and notarization."

**Evidence: what Sparkle actually does** (`SUUpdateValidator.m`, `validateUpdateForHost:`, branch `2.x`):
- `passedDSACheck`: the archive is verified against the **old** bundle's EdDSA key.
- `passedCodeSigning`: the new bundle is valid **and** satisfies the old bundle's designated requirement.
- The decision is `if (passedDSACheck || passedCodeSigning) { return YES; }`, with Sparkle's own comment: "Either DSA must be valid, or Apple Code Signing must be valid. We allow failure of one of them, because this allows key rotation."

**Case 1: EdDSA key alone.**
- When the EdDSA check passes, the new bundle only has to carry *some* valid code signature. The only rejections are "corrupted" and "signing removed" (`passesBasicUpdatePolicy…`).
- An ad-hoc signature passes.
- So the EdDSA seed alone is sufficient.

**Case 2: Developer ID alone.**
- With E2's Team-ID-based designated requirement, any app signed by the team with Snaptic's identifier passes `passedCodeSigning`.
- If `passedDSACheck` fails, Sparkle checks only the archive against the **new** bundle's own embedded key. That is a key the signer chooses.
- So the Developer ID certificate alone is also sufficient.

**Notarization is never checked by Sparkle.** It also removes quarantine from the new bundle (brief §2, `SUPlainInstaller.m:48-52`), so Gatekeeper never assesses the update either.

**Why it matters**
- The README and site would promise a two-key safeguard that doesn't exist.
- Both secrets sit in the same GitHub environment (E3 "Secrets"). One environment compromise therefore yields both, although either one is already enough.
- This is the trust anchor for code that runs with Accessibility and Screen Recording, and, on root-owned copies, behind an admin prompt.

**Fix**
- **E8.** Replace the risk text with: "Anyone who holds either the EdDSA release key or the Developer ID certificate can publish an update that Snaptic installs. Both are kept in the `release` environment; see E3."
- **E5.** Change to: "Every update must carry either a valid Ed25519 signature from Snaptic's release key, or Snaptic's Developer ID signature. Sparkle doesn't check notarization."
- **Custody.** Split the two secrets so that a single compromise doesn't hold both:
  - Preferred: sign the appcast enclosure with `sign_update` on the owner's Mac. The `release` job then only uploads a signature that the owner supplied, via a release-draft asset or a manual dispatch input.
  - Otherwise: keep `SPARKLE_ED_PRIVATE_KEY` in a **separate** environment, used only by the `release` job, with its own mandatory reviewer.
- **Sparkle settings.** Set `SUVerifyUpdateBeforeExtraction = YES`, so archives are verified before extraction (EdDSA required).
- **Compromise runbook.** Add a short runbook for a compromised key: rotate through a Developer ID-signed update that carries a new `SUPublicEDKey`, which Sparkle allows. Revoke the certificate if it's the certificate that leaked.

---

## Major

### M1. Release-environment access: tags on any commit and "optional" reviewers put both secrets one push away

**Evidence**
- E3 (PLAN:900): `sign` runs "under the `release` environment (only `main` and `v*`, with the owner's required reviewers optional)".
- No tag or branch ruleset is specified.
- The jobs run whatever the YAML at the triggering ref says.

**Why "never runs repository code" doesn't hold.** The inline steps are themselves repository content at the tagged commit. A `v*` tag pushed to any commit, for example one on a feature branch with an edited `build.yml`, satisfies an environment policy of "tags `v*`". Its jobs then receive the environment secrets. So does any push to `main`.

**Why it matters.** With B1, anyone with repo write access, or a leaked token or PAT with `contents: write`, can turn one tag push into a Developer ID-signed or EdDSA-signed update for every user, unless a human approval gate stands in the way.

**Fix (E3 and Part D Step 0, owner setup):**
- A **tag ruleset** on `refs/tags/v*`: only repository admins (the owner) may create, update or delete it.
- A **branch ruleset** on `main`: no force-push, no deletion, and changes go through PRs.
- The `release` environment:
  - deployment policy: **tags `v*` only**. Drop `main`, and sign only tag builds (see M3);
  - **required reviewers mandatory**, with the owner approving after reading the tag's diff to the previous release, including `.github/`;
  - "Allow administrators to bypass" turned off.
- In `sign`, an accident guard: fail unless the tag's commit is an ancestor of `origin/main` (`git merge-base --is-ancestor`). This is plain git metadata, not repository code.
- State in E3 that the approval gate, not "never runs repository code", is what protects the secrets.

### M2. The unsigned appcast and HTML release notes put remote content inside a TCC-privileged process

**Evidence**
- E3 `release` writes an unsigned `appcast.xml`. `SURequireSignedFeed` isn't used, though it's available from 2.9 (customization docs: "Set this to `YES` to make Sparkle validate appcasts and release notes are signed", which needs `SUVerifyUpdateBeforeExtraction`).
- `sparkle:releaseNotesLink` points at the release's **github.com HTML page**. Sparkle renders it in a WKWebView inside Snaptic, the process that holds Accessibility and Screen Recording. The brief flagged this (§4 item 11).
- The feed is `releases/latest/download/appcast.xml`. Anyone who can create or edit a non-prerelease release controls what every client fetches: any write user, or any workflow token with `contents: write`.

**What an unsigned feed allows.** Such a feed can't install code without the keys (B1). It can still:
- show arbitrary release notes and web content in Snaptic's update window;
- send "informational update" links that point users to a download page of the attacker's choosing;
- withhold updates (freeze).

**Fix (E3, E4)**
- Use **embedded plain or Markdown notes** (`<description>` with `sparkle:format="markdown"`), not a `releaseNotesLink` to github.com. Alternatively set `SUShowReleaseNotes = NO` and link out to the browser.
- Turn on `SUVerifyUpdateBeforeExtraction` and `SURequireSignedFeed`, and produce the feed signature with `sign_update` on the owner's Mac. That fits B1's custody fix. The brief notes the Linux format is unverified.
- Pin the feed: implement `feedURLStringForUpdater:` to return the constant, and call `clearFeedURLFromUserDefaults()` at launch, so a `SUFeedURL` written to the defaults domain can't redirect checks. [U: confirm that 2.10 still honors a defaults override.]

### M3. The `build` → `sign` → `release` hand-off: each later job blindly trusts the earlier job's bytes

**Evidence**
- `sign` code-signs whatever `Snaptic-unsigned` contains (E3 sign steps 1–5). That includes Sparkle's `Autoupdate` and `Updater.app`, which then carry Snaptic's Developer ID and can run as root on root-owned installs.
- `release` Ed-signs whatever the `Snaptic` artifact contains.
- `build` runs repository code: the build, tests and self-tests, all in the same job that produces the artifact.
- `sign` runs on every `main` push as well as on tags. That multiplies Team-signed, TCC-trusted, Sparkle-acceptable binaries (B1, m5).

**Fix (E3)**
- **Check Sparkle before signing.** In `sign`, before anything is signed, compare the SHA-256 of `Sparkle.framework/Versions/B/{Sparkle,Autoupdate,Updater.app/Contents/MacOS/Updater}` with hashes pinned in the workflow, taken from the official 2.10.0 SwiftPM zip (checksum `17e28312…`). Fail on any difference.
- **Pass the hash as a job output.** `sign` exports the SHA-256 of the signed `Snaptic.zip` and `.dmg` as a **job output**, which other jobs can't overwrite.
- **Verify in `release`.** `release` should `needs: [sign, attest]`, recompute the hash and compare it with that output, and run `gh attestation verify` on the zip, all before Ed-signing.
- **Sign tags only.** Run `sign` only for `v*` tags. `main` keeps its ad-hoc `Snaptic-unsigned` artifact for testing.
- **No caches into signed artifacts.** Never use `actions/cache` in the job whose output gets signed. State this as a rule.

---

## Minor

- **m1. E8 contradicts itself on a lost key.** "A lost key means users must download the next version by hand once" is false with Developer ID: `passedCodeSigning` lets a Team-signed update carry a new `SUPublicEDKey` (Sparkle's rotation path). Fix the text.
- **m2. Workflow injection hygiene for the new inline steps.**
  - Validate the tag with `^v[0-9]+\.[0-9]+\.[0-9]+$` before any use, because git ref names allow `$`, `(`, `<`, `"` and `&`.
  - Pass every `${{ … }}` through `env:` (the existing `release` job already does this).
  - Escape XML in the heredoc values.
  - Add `actionlint` or `zizmor` to CI.
  - Forbid `pull_request_target` and `workflow_run` in `build.yml`.
- **m3. Ed seed handling on ubuntu.**
  - GitHub masks the secret string but not derived forms: the DER or PEM file, or a re-encoded base64. Forbid `set -x`.
  - Build the key in `$RUNNER_TEMP` with `umask 077`, then remove it.
  - `::add-mask::` any derived encoding, and never `cat` it.
  - The same rules apply to `NOTARY_KEY_P8` and the p12 in `sign`.
- **m4. "Weak-linked, GUI mode only" isn't accurate** (E4). Weak linking only tolerates a missing framework. When it is present, dyld loads Sparkle into every process of the executable: DisplayGuard, the virtual hosts and the CLI. Either:
  - state that Sparkle is loaded but idle there; or
  - load it lazily with `dlopen` in GUI mode, with a rule 11 exemption for `UpdaterController.swift`.
- **m5. A Team-ID designated requirement makes every Team-signed Snaptic TCC-equivalent** (E2). That includes old releases with since-fixed bugs and any signed non-release build. A same-user process could drop an old signed copy and launch it with the user's Accessibility and Screen Recording grants. This is inherent to Developer ID. Keep the set small (sign tags only, M3) and say so in the README.
- **m6. Admin key scope.** Create the notarization App Store Connect API key with the **Developer** role, not Admin, and say so in Step 0. The p12 should hold only the Developer ID Application identity.
- **m7. Safe Mode blocks fixes** (E4: "updates are paused entirely"). A crash-looping release then can't be fixed through the updater. Block *scheduled* checks in Safe Mode (`mayPerformUpdateCheck`), but allow a manual Check for Updates… (brief §3 [U]).
- **m8. Sparkle's own admin prompt changes the lid-mode advice.**
  - Root-owned copies, the configuration B6 now recommends, get Sparkle's "Snaptic wants permission to update." prompt (E1). It may appear when the user didn't just ask for anything, such as an install at quit after an automatic check.
  - B6's rule "only enter your password right after you choose …" must also list **Install and Relaunch**.
  - For root-owned copies, the privileged install should only follow an explicit click. Don't offer automatic install there; Sparkle falls back to the UI driver anyway (brief §2).
  - [U] HW check: what rule the persistent authorization right `app.snaptic.Snaptic.sparkle2-auth` registers, and whether its credential is shared.
- **m9. `spawnTool` (B3.3) runs `/usr/bin/pmset displaysleepnow` every 10 s.**
  - Give it the same pre-SIGCONT `anchor apple` check and minimal environment as `spawnAdminScript`.
  - Disclaim it.
  - Rate-limit it so it doesn't respawn while a previous one is still running.
- **m10. "Root-owned is safe" now depends on the updater too** (B6 and E1). Sparkle preserves the owner on swap (brief §2), but it needs a HW check that a root-owned copy stays `root:wheel` after an update (HW list). Otherwise the B6 advice silently stops applying.
- **m11. `HALT` is set by any SIGTERM, not only by shutdown** (B3.2: `trap 'HALT=1; exit 0' TERM`). If security software or an admin sends TERM to the watchdog while the lid is shut, `cleanup` restores sleep but skips `sleepnow`. The Mac then keeps running in the bag until the app-side lid-shut rule ends the session, which never happens if Snaptic is gone too. Accept this and state it in B3.2, or decide `HALT` from a shutdown signal (for example `launchctl` showing a system shutdown in progress), not from TERM alone.

---

## Checked and found fine
- **B3.2.** The three-line command and its exit-code path (`|| exit $?` → `do shell script` error → `err n`). The raw-literal script and its no-control-bytes test. `unset IFS`, absolute paths, and validation of every argument and of `MODE`. The EXIT trap with `WESET` and `num` guards on every operand. The post-set check. `cleanup` ignores repeated TERM and INT, never runs `sleepnow` while shutting down, and waits for the kernel bit. `ksd` is scoped to IOPMrootDomain at `-d 1`, and inline dictionaries use `"k"=v`, so they don't match `" = "`.
- **B3.1 and B3.3.**
  - Spawn and check: the minimal environment; the pre-SIGCONT `anchor apple` requirement; disclaim by default; pid-only SIGTERM.
  - `parseResult` bounds, and the uid 0 plus start-time verify.
  - App side: the main-age-gated heartbeat, instance-ID liveness, and the stop file on every failure exit.
- **B2 and B3.4.** The hotkey ends the mode. `capStart` is fixed. A journal never prompts, and Keep Sleep Off needs no root.
- **E2.** No entitlements, and CI asserts it. Library validation stays on (same Team ID). Hardened runtime with timestamps. Inside-out signing without `--deep`. XPC services removed for a non-sandboxed app. Developer ID removes the "unsigned parent" condition of the Elastic rule (B6) and restores Team-ID XPC client validation for Sparkle's root installer (brief §2: CVE-2025-10016 class).
- **E3 and E4.**
  - Sparkle pinning: exact version ≥ 2.9.6 (2.10.0), the binary-target checksum, and `Package.resolved` committed. Actions are SHA-pinned.
  - Feed and versioning: versioned enclosure URLs; prereleases never become "latest"; Sparkle refuses downgrades by `CFBundleVersion`; the tag must equal the version.
  - Isolation: secrets are environment-scoped, so fork and same-repo PR runs (`refs/pull/*`) never get them. No CLI `update` verb (socket can't trigger installs). `SUEnableSystemProfiling = NO`. Automatic checks are opt-in.
- **E6.** The L19 limits on `import Sparkle` are fine. The networking ban still covers Snaptic's own code.
- **Part A.** No security-relevant change.
