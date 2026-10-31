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

## Native design (unreleased)

- [ ] Capture toolbar appears at the bottom center of the screen under the mouse, dark HUD look; Close / Capture / modes work; Options menu items toggle and apply live
- [ ] Window mode: camera cursor, accent highlight, click captures the window; last region unchanged
- [ ] Screen mode: click captures that screen
- [ ] Selection look: no dim before selecting, thin border with shadow, round handles, pill size label below the selection
- [ ] Self-timer 5 / 10 s: countdown in the middle, Esc / click cancels, captured content is live
- [ ] Floating thumbnail: slides in, stays while hovered, click opens the editor and Done replaces the saved file, drag into Finder/Mail works, swipe right dismisses, right-click menu
- [ ] Sound plays and can be turned off
- [ ] Editor toolbar: tools group, color and width menus with checkmarks, undo/redo enablement, Share menu, Copy, Done (blue, Enter)
- [ ] Settings tabs resize smoothly; every setting works; light and dark mode
- [ ] Onboarding steps and checkmarks; About panel with link
- [ ] Reduce Motion: no slide / fade animations
- [x] No Auto Layout conflicts when opening the editor, Settings and onboarding (log check, Debug flags) — Claude, 2026-10-31
- [x] Settings 520×285 (General) and onboarding 460×451 content sizes measured in-app — Claude, 2026-10-31

## Scrolling capture (unreleased)

- [ ] Toolbar mode, menu item and an assigned shortcut open the overlay in scrolling mode
- [ ] Frame and HUD appear; scrolling inside the frame reaches the app below; height counter grows
- [ ] Long web page in Safari / Brave: result has the page content once, no duplicated or missing lines; sticky header appears once at the top
- [ ] Scrolling too fast shows the warning; scrolling back recovers
- [ ] Done delivers the image (thumbnail, save, clipboard); ⌘C in scrolling mode → clipboard only; Cancel discards
- [ ] Frame and HUD are not in the result
- [x] `-MacShotRegionSelfTest` (Debug): region capture matches the crop — same rect mean diff 0.0, 40 pt shifted 48.4 (first run hit a locked screen: ScreenCaptureKit returns no displays while locked) — Claude, 2026-10-31
- [x] Whole-window selection with a fixed sidebar (owner's first try returned a single frame): fixed by matching only the scrolling column band; replayed with frames built from the owner's Analytics screenshot — 7/7 frames appended, seamless 756×1200 result — Claude, 2026-10-31
- [ ] Owner re-test of the whole-window case (manual scrolling)
- [x] Auto-scroll probe: sandboxed build cannot be added to Accessibility on macOS 27; non-sandboxed can; once granted, synthetic scrolling moved the page 80 px — Claude + owner, 2026-10-31
- [x] Automatic scrolling self-test on a Cloudflare dashboard page: 5 frames appended, stopped at the end on its own, seamless 456×1101 result, fixed sidebar removed — Claude + owner, 2026-10-31 (earlier runs failed; causes fixed: bad first frame, re-rasterized text, hover effects, repeating rows, wide score peaks; an early version also trapped the pointer — fixed with AutoScrollPolicy)
- [ ] Automatic scrolling from the real overlay flow (Capture button / Enter), moving the mouse to take over, Esc to cancel
- [x] AppStore configuration: launches sandboxed with automatic scrolling unavailable (`Channel: sandboxed=true, autoScroll=false`), sandbox entitlements present; Debug: `sandboxed=false, autoScroll=true` — Claude, 2026-10-31
- [ ] AppStore configuration: manual scrolling session end to end
- [x] Preferences migrated from the sandboxed build: 6/6 keys readable afterwards (shortcuts, tasks, mode, last region, settings pane) — Claude, 2026-10-31
- [x] Stitching algorithm unit-tested with a synthetic page (sticky bands, scroll-bar noise, blank blocks, lost frames, maximum height) — Claude, 2026-10-31

## Release package (per release)

- [ ] DMG opens, drag-to-Applications works, app launches without a Gatekeeper warning (`spctl -a -vv` says "Notarized Developer ID")
- [ ] Screen Recording permission flow on a clean user account
- [ ] Version in About / Finder Get Info matches the tag

## Automated checks run by Claude

- [x] `xcodebuild build` and `test`: 98/98 tests green (native design branch), no warnings from our code
- [x] CI command run locally unsigned and without Local.xcconfig: green; GitHub Actions green on `main`
- [x] Signing: Apple Development (Team 4SFTG4T5YD); entitlements: app-sandbox, assets.pictures.read-write, files.user-selected.read-write, files.bookmarks.app-scope
- [x] Legacy capture API scan (`CGWindowListCreateImage`, `CGDisplayCreateImage`): no usage
- [x] Latency (hotkey → overlay visible), 1 display: first 160 ms, then 72 ms (target < 250 ms on 2 displays; 2 displays not measured)
