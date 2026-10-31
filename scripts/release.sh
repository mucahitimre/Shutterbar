#!/usr/bin/env bash
# Builds, signs, notarizes and packages a MacShot release, then creates a DRAFT GitHub release.
#
#   scripts/release.sh 0.2.0            full release (Developer ID + notarization + draft release)
#   scripts/release.sh 0.2.0 --local    local dry run: Release build + DMG/ZIP, no notarization, no tag, no upload
#   scripts/release.sh 0.3.0 --no-notarize
#                                       published PRE-RELEASE signed with the Apple Development identity (no Developer ID
#                                       yet): Gatekeeper asks once on first launch; the notes say so
#
# Requirements for a full release (see RELEASING.md):
#   - "Developer ID Application" certificate in the login keychain
#   - notarytool keychain profile (default name: macshot-notary, override with NOTARY_PROFILE)
#   - gh CLI logged in; clean `main` that matches origin; CHANGELOG.md has a "## [x.y.z]" section
set -euo pipefail

VERSION="${1:-}"
MODE="${2:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-macshot-notary}"

die() { echo "error: $*" >&2; exit 1; }
step() { echo "==> $*"; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || die "usage: scripts/release.sh <x.y.z[-pre]> [--local]"
[[ -z "$MODE" || "$MODE" == "--local" || "$MODE" == "--no-notarize" ]] || die "unknown option: $MODE"
LOCAL=false
NOTARIZE=true
[[ "$MODE" == "--local" ]] && LOCAL=true && NOTARIZE=false
[[ "$MODE" == "--no-notarize" ]] && NOTARIZE=false

cd "$(dirname "$0")/.."
APP_NAME="$(sed -nE 's/^ *APP_NAME: *([A-Za-z0-9]+).*/\1/p' project.yml | head -1)"
PROJECT_VERSION="$(sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"?.*/\1/p' project.yml | head -1)"
TAG="v$VERSION"
OUT="build/release/$VERSION"

[[ "$PROJECT_VERSION" == "$VERSION" ]] || die "project.yml MARKETING_VERSION is $PROJECT_VERSION, not $VERSION"

if ! $LOCAL; then
    step "Checking repository state"
    [[ -z "$(git status --porcelain)" ]] || die "working tree is not clean"
    [[ "$(git branch --show-current)" == "main" ]] || die "releases are cut from main"
    git fetch --quiet origin main --tags
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "main is not in sync with origin/main"
    ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || die "tag $TAG already exists"
    grep -q "^## \[$VERSION\]" CHANGELOG.md || die "CHANGELOG.md has no section for $VERSION"
    if $NOTARIZE; then
        security find-identity -v -p codesigning | grep -q "Developer ID Application" \
            || die "no 'Developer ID Application' certificate in the keychain (see RELEASING.md)"
    fi
    command -v gh >/dev/null || die "gh CLI is required"
fi

rm -rf "$OUT"
mkdir -p "$OUT"
BUILD_NUMBER="$(git rev-list --count HEAD)"

step "Archiving $APP_NAME $VERSION ($BUILD_NUMBER)"
xcodegen generate --quiet
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
    -derivedDataPath build/release/DD -archivePath "$OUT/$APP_NAME.xcarchive" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive -quiet

if ! $NOTARIZE; then
    # Development-signed app straight from the archive (local dry run, or a pre-release without Developer ID).
    mkdir -p "$OUT/export"
    ditto "$OUT/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app" "$OUT/export/$APP_NAME.app"
else
    step "Exporting with Developer ID"
    TEAM_ID="$(xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release -showBuildSettings 2>/dev/null \
        | sed -nE 's/^ *DEVELOPMENT_TEAM = (.+)$/\1/p' | head -1)"
    [[ -n "$TEAM_ID" ]] || die "DEVELOPMENT_TEAM is empty; set it in Config/Local.xcconfig"
    cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
    xcodebuild -exportArchive -archivePath "$OUT/$APP_NAME.xcarchive" -exportPath "$OUT/export" \
        -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates -quiet
fi

APP="$OUT/export/$APP_NAME.app"
step "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
SHORT_VERSION="$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)"
[[ "$SHORT_VERSION" == "$VERSION" ]] || die "app reports version $SHORT_VERSION"

if $NOTARIZE; then
    step "Notarizing app"
    ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
    xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
    rm "$OUT/notarize.zip"
fi

step "Packaging"
ZIP="$OUT/$APP_NAME-$VERSION.zip"
DMG="$OUT/$APP_NAME-$VERSION.dmg"
ditto -c -k --keepParent "$APP" "$ZIP"
STAGING="$OUT/dmg"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

if $NOTARIZE; then
    step "Signing and notarizing DMG"
    IDENTITY="$(security find-identity -v -p codesigning | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' | head -1)"
    codesign --sign "$IDENTITY" --timestamp "$DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > SHA256SUMS.txt)

# Release notes: the CHANGELOG section for this version.
awk -v v="$VERSION" '
    $0 ~ "^## \\[" v "\\]" { on = 1; next }
    on && /^## \[/ { exit }
    on && /^\[[^]]+\]: / { exit }
    on { print }
' CHANGELOG.md > "$OUT/NOTES.md"

if $LOCAL; then
    step "Local package ready (not notarized): $OUT"
    ls -1 "$OUT"
    exit 0
fi

step "Tagging $TAG and creating a draft GitHub release"
git tag -a "$TAG" -m "$APP_NAME $VERSION"
git push origin "$TAG"
if $NOTARIZE; then
    PRERELEASE=()
    [[ "$VERSION" == *-* ]] && PRERELEASE=(--prerelease)
    gh release create "$TAG" "$DMG" "$ZIP" "$OUT/SHA256SUMS.txt" \
        --draft ${PRERELEASE[@]+"${PRERELEASE[@]}"} --title "$APP_NAME $VERSION" --notes-file "$OUT/NOTES.md"
    step "Draft release created. Review it on GitHub and publish."
else
    {
        echo "> **Pre-release, not notarized.** On first launch macOS refuses to open it: right-click MacShot in"
        echo "> Applications → **Open** → **Open**, once. Notarized releases will follow once Developer ID signing is set up."
        echo
        cat "$OUT/NOTES.md"
    } > "$OUT/NOTES-prerelease.md"
    gh release create "$TAG" "$DMG" "$ZIP" "$OUT/SHA256SUMS.txt" \
        --prerelease --title "$APP_NAME $VERSION (pre-release)" --notes-file "$OUT/NOTES-prerelease.md"
    step "Pre-release published."
fi
