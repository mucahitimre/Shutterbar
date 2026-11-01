#!/usr/bin/env bash
# Points the Homebrew cask (mucahitimre/homebrew-tap, Casks/<app>.rb) at a PUBLISHED release.
#
#   scripts/update-cask.sh 0.4.1
#
# Run it after the draft release from scripts/release.sh is published: it downloads the DMG from GitHub, checks it
# against SHA256SUMS.txt from the same release, rewrites `version` and `sha256`, runs `brew style`/`brew audit` when
# the tap is installed, and pushes one commit to the tap. Pre-releases are refused (the cask follows stable releases).
set -euo pipefail

VERSION="${1:-}"
TAP_REPO="${TAP_REPO:-mucahitimre/homebrew-tap}"

die() { echo "error: $*" >&2; exit 1; }
step() { echo "==> $*"; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: scripts/update-cask.sh <x.y.z> (stable versions only)"
command -v gh >/dev/null || die "gh CLI is required"

cd "$(dirname "$0")/.."
APP_NAME="$(sed -nE 's/^ *APP_NAME: *([A-Za-z0-9]+).*/\1/p' project.yml | head -1)"
TOKEN="$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
TAG="v$VERSION"
DMG="$APP_NAME-$VERSION.dmg"

step "Checking release $TAG"
STATE="$(gh release view "$TAG" -R "$REPO" --json isDraft,isPrerelease -q '"\(.isDraft) \(.isPrerelease)"')" \
    || die "release $TAG not found"
[[ "$STATE" == "false false" ]] || die "release $TAG is a draft or a pre-release (isDraft isPrerelease: $STATE)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

step "Downloading $DMG"
curl -fsSL -o "$WORK/$DMG" "https://github.com/$REPO/releases/download/$TAG/$DMG"
curl -fsSL -o "$WORK/SHA256SUMS.txt" "https://github.com/$REPO/releases/download/$TAG/SHA256SUMS.txt"
SHA="$(shasum -a 256 "$WORK/$DMG" | cut -d' ' -f1)"
grep -q "^$SHA  $DMG\$" "$WORK/SHA256SUMS.txt" || die "downloaded $DMG does not match SHA256SUMS.txt"

step "Updating Casks/$TOKEN.rb in $TAP_REPO"
gh repo clone "$TAP_REPO" "$WORK/tap" -- --quiet
CASK="$WORK/tap/Casks/$TOKEN.rb"
[[ -f "$CASK" ]] || die "$TAP_REPO has no Casks/$TOKEN.rb"
sed -i '' -E "s/^  version \"[^\"]+\"/  version \"$VERSION\"/; s/^  sha256 \"[0-9a-f]+\"/  sha256 \"$SHA\"/" "$CASK"
grep -q "^  version \"$VERSION\"" "$CASK" && grep -q "^  sha256 \"$SHA\"" "$CASK" || die "could not rewrite $CASK"
if git -C "$WORK/tap" diff --quiet; then
    step "Cask already points at $VERSION"
    exit 0
fi

# Public repo: commits must not carry a real e-mail address.
EMAIL="$(git -C "$WORK/tap" config user.email || true)"
[[ "$EMAIL" == *@users.noreply.github.com ]] || die "git user.email is '$EMAIL'; use your GitHub noreply address"

TAP_NAME="${TAP_REPO/homebrew-/}"
if command -v brew >/dev/null && brew tap | grep -qx "$TAP_NAME"; then
    step "brew style / audit"
    TAP_DIR="$(brew --repository "$TAP_NAME")"
    cp "$CASK" "$TAP_DIR/Casks/$TOKEN.rb"
    trap 'git -C "$TAP_DIR" checkout --quiet -- "Casks/$TOKEN.rb"; rm -rf "$WORK"' EXIT
    brew style --cask "$TAP_NAME/$TOKEN"
    brew audit --cask --online "$TAP_NAME/$TOKEN"
fi

git -C "$WORK/tap" commit --quiet -am "$TOKEN $VERSION"
git -C "$WORK/tap" push --quiet origin HEAD
step "Cask updated: brew upgrade --cask $TOKEN"
