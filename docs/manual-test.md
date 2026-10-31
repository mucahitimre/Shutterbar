# Manual test checklist

Environment: macOS 27.0 (Darwin 27.0.0), single display 2048×1332 pt, `backingScaleFactor` 1.0 (1x; measured on 2026-10-31 — an earlier "Retina" note was wrong). Build: Debug, signed with Apple Development, sandbox on.
Marks: `[x]` run and passed · `[ ]` pending manual test · the note says who ran it and how.

- [x] Single display (1x): region capture works, file is saved — verified by the owner on 2026-10-31 (610×228 and 652×621 px PNG)
- [x] v0.1 build general use — owner said "works" on 2026-10-31 (overall, not item by item; the unchecked items below still need confirmation)
- [ ] Pixel accuracy of the crop (compare with a UI element of known size) — pending; unit tests cover 1x/2x/1.5x
- [ ] Capture and sharpness on a Retina (2x) display — no 2x display on this machine, pending
- [ ] Retina built-in + 1x external display: capture on both, sharpness, correct size — no external display, pending
- [ ] External display left of / above the main display (negative coordinates) — pending; covered by unit tests
- [ ] Dragging across two displays → clamped to the starting display — pending
- [ ] Capture on a different Space — pending
- [ ] Overlay and capture over a full-screen app (Safari, Keynote presentation) — pending
- [ ] An open menu and a tooltip/hover state are captured in the frozen frame — pending
- [ ] Overlay, menu bar menu and settings window do not appear in the output — pending
- [ ] Esc cancels: no file, clipboard unchanged — pending
- [ ] Quick capture off (default): move, resize, Enter, double-click — pending
- [ ] ⌘C: clipboard only, no file; last region is updated — pending
- [ ] Quick capture on: capture immediately on mouse up — pending
- [ ] Space and ~ shortcuts — pending
- [ ] Magnifier: 15×15 px, 8x, grid, red center pixel; flips at screen edges; can be turned off — pending
- [ ] After capture: menu checkboxes and settings show the same state; Show in Finder; notification and clicking it reveals the file — pending
- [ ] "No after-capture task selected" warning (once per session) — pending
- [ ] ⌥⇧5: same region without the overlay — pending
- [ ] ⌥⇧5: with the external display disconnected, overlay + HUD fallback — no external display, pending
- [ ] Last region survives an app relaunch — pending
- [ ] With permission revoked, no blank image is saved and onboarding opens — pending
- [ ] Save folder moved outside Pictures, app relaunched, saving still works (bookmark) — pending
- [ ] Launch at login on/off, after reboot — pending
- [ ] Hotkey registration failure and fallback shortcut — no macOS 15.0/15.1 machine, pending

## v0.2

- [ ] Mouse wheel / trackpad changes the magnifier size, kept after relaunch — pending
- [ ] 1…0: the whole screen with that number; beep for a missing screen — pending
- [ ] Notification shows a thumbnail — pending
- [ ] With "Also put the file URL on the clipboard" on, pasting into Finder gives the file; with it off, it does not — pending
- [ ] Window detection: highlight is on the frontmost window; click selects the window; dragging still draws a region; Dock / menu bar are not selected; can be turned off — pending
- [ ] Editor: drawing with all five tools by mouse, text input (Enter commits, Esc cancels), color/width, ⌘Z/⇧⌘Z, Done / Copy / cancel — pending
- [x] Editor self-test (debug, one annotation of each tool added through the model): window opens, Done saves the output; the saved PNG matches the canvas — Claude, 2026-10-31 (not mouse interaction)
- [ ] Editor toolbar appearance — could not be verified from an image because `cacheDisplay` does not draw the native segmented control; it is present in the view hierarchy (x 12–372). Pending

## Release package (per release)

- [ ] DMG opens, drag-to-Applications works, app launches without a Gatekeeper warning (`spctl -a -vv` says "Notarized Developer ID")
- [ ] Screen Recording permission flow on a clean user account
- [ ] Version in About / Finder Get Info matches the tag

## Automated checks run by Claude

- [x] `xcodebuild build` and `test`: 86/86 tests green (v0.2), no warnings from our code
- [x] CI command run locally unsigned and without Local.xcconfig: green; GitHub Actions green on `main`
- [x] Signing: Apple Development (Team 4SFTG4T5YD); entitlements: app-sandbox, assets.pictures.read-write, files.user-selected.read-write, files.bookmarks.app-scope
- [x] Legacy capture API scan (`CGWindowListCreateImage`, `CGDisplayCreateImage`): no usage
- [x] Latency (hotkey → overlay visible), 1 display: first 160 ms, then 72 ms (target < 250 ms on 2 displays; 2 displays not measured)
