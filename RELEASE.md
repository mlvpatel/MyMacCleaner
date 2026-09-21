# MyMacCleaner Release Guide

Releases are Developer ID signed, notarized, and published as a **draft** GitHub release.
The app has no update channel: users install new versions manually from the release page.
Release status claims (signed, notarized, Gatekeeper) belong in
[docs/RELEASE-RUNBOOK.md](docs/RELEASE-RUNBOOK.md) and need recorded evidence.

## One-time setup

1. **Signing identity.** Find the SHA-1 of your "Developer ID Application" certificate:

   ```bash
   security find-identity -v -p codesigning
   ```

2. **`.env` in the repository root** (gitignored). The script reads these keys without
   exporting them to child processes:

   | Key | Meaning |
   |-----|---------|
   | `APPLE_TEAM_ID` | 10-character Team ID |
   | `MACOS_CERTIFICATE_SHA1` | 40-character SHA-1 from step 1 |
   | `NOTARY_PROFILE` | Optional keychain profile name (default `notary-profile`) |

   Older `.env` files may still contain `SPARKLE_*` or `APPLE_APP_SPECIFIC_PASSWORD` entries;
   they are no longer read and can be deleted.

3. **Notarization credentials in the keychain** (never in `.env`):

   ```bash
   xcrun notarytool store-credentials "notary-profile" --apple-id "you@example.com" --team-id "YOUR_TEAM_ID"
   ```

4. **GitHub CLI:** `gh auth login`.

For local Developer ID builds in Xcode, also copy `Config/Signing.local.xcconfig.example` to
`Config/Signing.local.xcconfig` (gitignored).

## Cutting a release

Start from an up-to-date `main` with no uncommitted **or untracked** files.

```bash
./scripts/release.sh 0.2.0 --dry-run
./scripts/release.sh 0.2.0 --notes release-notes.md
```

`--dry-run` runs every check, archives and verifies the signed app, then restores the project
file. It does not notarize, push, or create a release. Without `--notes`, GitHub generates notes.

### What the script does

1. Refuses to run off `main`, when `main` differs from `origin/main`, with a dirty or untracked
   tree, or when the tag, release branch, or GitHub release already exists.
2. Runs the unit tests and every verifier (`verify-safety-contract.sh`, `verify-cleanercore.sh`,
   `verify-cleanercore-contract.sh`, and the Adaptive Experience verifiers).
3. Bumps `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Any later failure restores the project file.
4. Archives and exports with Developer ID, then checks `codesign --verify --deep --strict`, the
   hardened runtime flag, the team identifier, the shipped architectures, and that no Sparkle
   framework is bundled.
5. Notarizes the app, staples it, and checks it with `spctl --assess --type execute`. Then builds
   the DMG, signs it, notarizes and staples it, and checks it with `spctl --type open`. Any
   notarization result other than `Accepted` stops the release.
6. Writes a ZIP of the stapled app and `SHA256SUMS`.
7. Commits the version on `release/v<version>`, pushes **that branch only**, and creates a draft
   release with the DMG, ZIP and checksums. Nothing is pushed to `main`.

Artifacts and logs stay in `build/release-v<version>/`.

### After the script

1. Open a pull request from `release/v<version>` and let CI pass.
2. Download the draft assets, compare them against `SHA256SUMS`, and run
   `spctl --assess --type execute --verbose=2 MyMacCleaner.app` on a clean machine.
3. Merge the pull request, then publish the draft release.
4. Record the evidence (notary IDs, `spctl` output, CI run) in `docs/RELEASE-RUNBOOK.md`.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `working tree is not clean` | `git status --untracked-files=all`; build output belongs in the ignored `build/` folder |
| `signing identity ... is not in the keychain` | The SHA-1 in `.env` matches `security find-identity -v -p codesigning` |
| `notarization ... was not accepted` | `build/release-v<version>/notary-*.json`, then `xcrun notarytool log <id> --keychain-profile notary-profile` |
| `spctl` rejects the app | The app was re-signed after stapling, or the ticket is missing; rerun from a clean tree |
| `hardened runtime is not enabled` | `ENABLE_HARDENED_RUNTIME = YES` in the app target |

To remove a draft created by mistake: `gh release delete v<version> --yes` and
`git push origin --delete release/v<version>`.
