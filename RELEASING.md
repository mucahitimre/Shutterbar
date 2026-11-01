# Releasing Shutterbar

Every **stable** version is tagged `vX.Y.Z` (annotated tag on `main`) and published on GitHub Releases as a signed, notarized `Shutterbar-X.Y.Z.dmg` and `Shutterbar-X.Y.Z.zip` with `SHA256SUMS.txt`. Pre-releases use `vX.Y.Z-beta.N` and are marked as pre-release.

Versioning follows [Semantic Versioning](https://semver.org/): `MAJOR` for breaking changes, `MINOR` for features, `PATCH` for fixes. The build number (`CFBundleVersion`) is the commit count at release time.

## One-time setup

1. **Developer ID certificate** (requires a paid Apple Developer Program membership; the Account Holder creates it): Xcode → Settings → Accounts → your team → Manage Certificates → **+** → *Developer ID Application*.
2. **Notarization credentials** in the keychain (uses an [app-specific password](https://support.apple.com/102654) for your Apple ID):
   ```bash
   xcrun notarytool store-credentials macshot-notary --apple-id "<apple id>" --team-id "<team id>"
   ```
   The profile name defaults to `macshot-notary`; override with `NOTARY_PROFILE=...`.
3. `Config/Local.xcconfig` with your `DEVELOPMENT_TEAM` (see README) and `gh auth login`.

## Cutting a release

1. Make sure the manual checks in [docs/manual-test.md](docs/manual-test.md) relevant to the changes have passed.
2. On a branch: set `MARKETING_VERSION` in `project.yml`, move the `[Unreleased]` entries in [CHANGELOG.md](CHANGELOG.md) under a new `## [X.Y.Z] - YYYY-MM-DD` heading and update the compare links. Merge to `main`.
3. Optional dry run (no notarization, no tag, no upload):
   ```bash
   scripts/release.sh X.Y.Z --local
   ```
4. Release from an up-to-date, clean `main`:
   ```bash
   scripts/release.sh X.Y.Z
   ```
   The script archives the Release build, exports it with Developer ID, notarizes and staples the app and the DMG, writes the checksums, creates and pushes the annotated tag, and creates a **draft** GitHub release with the changelog section as notes.
5. The tag triggers the **Release check** workflow (version/changelog match, Release build, tests). When it is green, review the draft release on GitHub and publish it.
6. Smoke test the published DMG on a clean account (see "Release package" in the manual checklist).
7. Point the Homebrew cask at the new version:
   ```bash
   scripts/update-cask.sh X.Y.Z
   ```
   It downloads the published DMG, checks it against `SHA256SUMS.txt`, updates `version` and `sha256` in [mucahitimre/homebrew-tap](https://github.com/mucahitimre/homebrew-tap) (`Casks/shutterbar.rb`), runs `brew style`/`brew audit` if the tap is installed, and pushes one commit. Pre-releases are skipped; the cask follows stable releases only.

## Pre-release without Developer ID

Until the Developer ID certificate exists, `scripts/release.sh X.Y.Z --no-notarize` publishes a **pre-release** signed with the Apple Development identity (same checks, tag, DMG/ZIP and checksums; no notarization). The release notes tell users to right-click → Open once. When Developer ID is set up, ship the next version normally.

## Branch protection

`main` should only change through pull requests with a green CI. GitHub offers branch protection for private repositories only on Pro; once the repository is public (or on Pro), apply the stored rules:

```bash
gh api -X PUT repos/mucahitimre/Shutterbar/branches/main/protection --input .github/branch-protection.json
```

## Fixing a bad release

Do not move or force-push a published tag. Ship a new patch version (`X.Y.Z+1`). A draft release that was never published can be deleted together with its tag.
