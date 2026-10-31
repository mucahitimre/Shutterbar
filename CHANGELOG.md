# Changelog

All notable changes to MacShot are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/). Release notes on GitHub are taken from this file.

## [Unreleased]

## [0.3.0] - 2026-10-31

### Added
- Scrolling capture: select an area, scroll through it, and MacShot stitches the frames into one tall image (sticky headers/footers kept once, fixed sidebars left out).
- Automatic scrolling for scrolling capture in the GitHub build (Accessibility permission): stops at the end, on any user input or Esc, with time and frame limits.
- Capture toolbar modeled on macOS's screenshot toolbar: close, entire screen / window / selection modes, Options menu, Capture.
- Window mode (hover + click) and screen mode, with the system camera cursor and an accent-colored highlight.
- Self-timer (5 / 10 seconds).
- Floating thumbnail after each capture: click to annotate, drag to share, swipe to dismiss.
- Optional system screenshot sound.

### Changed
- The GitHub build is no longer sandboxed (needed for automatic scrolling); an `AppStore` configuration keeps the sandbox. Preferences are migrated once.
- Overlay styled like the system UI: no dimming until a selection exists, thin shadowed border, round handles, pill-shaped labels, HUD messages.
- Native tabbed Settings window, onboarding redesign, status menu with symbols and an About panel.
- Annotation editor uses a native unified toolbar with color / width menus and Share.

## [0.2.0] - 2026-10-31

### Added
- Window detection: the window under the cursor is highlighted in the overlay; clicking selects it. Window captures do not replace the remembered last region.
- Annotation editor (optional after-capture task): arrow, rectangle, text, pixelate and number badge tools, color and line width, undo/redo; Done runs the other tasks, ⌘C copies only.
- Magnifier size can be changed with the mouse wheel and is remembered.
- 1…9, 0 in the overlay capture the screen with that number.
- Notifications show a thumbnail of the capture.
- Option to also put the saved file's URL on the clipboard.
- App icon, English user interface, signed and notarized release packages (DMG and ZIP).

### Changed
- The user interface, documentation and code comments are now in English.

## [0.1.0] - 2026-10-31

### Added
- Region capture with a frozen screen (ScreenCaptureKit), one overlay per display, pixel-accurate cropping.
- Selection editing until Enter (quick capture off by default), ⌘C to copy to the clipboard only, Shift for square, ⌥ to move while drawing, arrow keys, Space for all screens, ~ for the current screen.
- After-capture tasks: save to file, copy to clipboard, show in Finder, notification; failures isolated and summarized.
- Last region: remembered across relaunches, previewed in the overlay, captured directly with ⌥⇧5, with a fallback when the display layout changed.
- Magnifier, launch at login, permission onboarding, hotkey registration check with fallback shortcuts.

[Unreleased]: https://github.com/mucahitimre/MacShot/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/mucahitimre/MacShot/compare/e06bd42...v0.3.0
[0.2.0]: https://github.com/mucahitimre/MacShot/compare/fbe4b7a...e06bd42
[0.1.0]: https://github.com/mucahitimre/MacShot/tree/fbe4b7a
