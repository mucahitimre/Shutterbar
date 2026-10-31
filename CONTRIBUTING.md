# Contributing to MacShot

Thanks for your interest! MacShot is a small macOS menu bar app that brings ShareX's region capture flow to the Mac. Issues and pull requests are welcome in English or Turkish.

## Setup

```bash
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig   # set your Team ID and bundle id prefix
xcodegen generate
xcodebuild -project MacShot.xcodeproj -scheme MacShot -derivedDataPath build/DD build
```

- macOS 14.0+, Xcode 16+ (Swift 6, strict concurrency).
- Sign with a stable **Apple Development** identity. Ad-hoc signed builds lose the Screen Recording permission on every rebuild.
- `MacShot.xcodeproj` is generated; commit `project.yml`, never the `.xcodeproj`.

## Before opening a pull request

```bash
xcodebuild -project MacShot.xcodeproj -scheme MacShot -derivedDataPath build/DD test
```

- Tests pass and the build has no new warnings.
- Pure logic (geometry, selection, file naming, after-capture runner, last region) lives in `MacShotCore` and gets unit tests (Swift Testing).
- UI-facing changes: run the relevant items in [docs/manual-test.md](docs/manual-test.md) and say which ones in the PR.
- Keep PRs focused; one change per PR.

## Ground rules

- **No legacy capture APIs** (`CGWindowListCreateImage`, `CGDisplayCreateImage`). Capture goes through ScreenCaptureKit.
- **Do not copy code** from ShareX (GPL-3.0) or other projects with incompatible licenses. Reading for ideas is fine; write your own implementation.
- New dependencies or entitlements need discussion in an issue first. The app currently depends only on [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) and uses four sandbox entitlements.
- Match the surrounding code style. Code comments are in Turkish; English is fine for new comments.

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
