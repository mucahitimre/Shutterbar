# MacShot v1: Minimum region capture plan from ShareX to Mac, and the Claude Code handoff block

_Original planning document for MacShot v1 (translated from Turkish). Some decisions changed during implementation — see README.md._

All four requests are feasible on macOS 14+ using ScreenCaptureKit and AppKit with the sandbox enabled. The key point: there is no separate API for "freezing" the screen. The moment the hotkey is pressed, a full image of every display is captured once, the selection is made on this frozen image, and the final PNG is cropped from this image rather than produced by a new capture. The only serious risk is the default hotkeys you asked for (⌥⇧4 and ⌥⇧5). In sandboxed apps, shortcuts using only Option+Shift did not work on macOS 15.0 and 15.1; this restriction was reverted in 15.2.\[1\]\[2\] For this reason the handoff block makes it mandatory to catch the registration failure and fall back to an alternative shortcut.

## TL;DR
- **Architecture:** Like ShareX's default region capture, freeze first, then select. Each display is captured with `SCScreenshotManager.captureImage(contentFilter:configuration:)` (macOS 14+). Our own windows are excluded with `SCContentFilter(display:excludingApplications:exceptingWindows:)`.\[3\]\[4\] For a sharp result on Retina displays, the output width is set to "point × `pointPixelScale`". Cropping is done on the frozen `CGImage`. `CGWindowListCreateImage` is "obsoleted" in the macOS 15 SDK, so it will not be used at all.\[5\]
- **Where we beat ShareX is "Last region":** In ShareX the last region is kept only in memory (an inference based on old source code) and is not pre-drawn on the overlay. In ours, the region will be stored persistently as a display UUID and a point rect, pre-drawn faintly on the overlay, and there will be a separate hotkey that captures without opening the overlay. This is a combination of macOS's Cmd+Shift+5 "Remember Last Selection", CleanShot X's "Capture Previous Area", and Shottr's "Repeat Area".\[6\]\[7\]
- **Scope M:** four phases plus a polish phase, doable sequentially in a single CC session; no subagent needed. CC first stops at API verification, scope assessment and open questions, and writes no code until GO arrives.

## A) Minimum behaviors to take from ShareX (per your four items)

**1. Region capture.** According to ShareX's official region capture documentation, the flow is as follows: a rectangle is drawn by dragging with the left button. With quick capture enabled, which is the default, the capture completes the moment the mouse is released. With quick capture disabled, the selection can be moved and resized from the corners; the capture is finished with Enter or by double-clicking inside the selection. This setting is under Task settings → Capture → Region capture.\[8\] The shortcuts we will adopt, from the table in the documentation:
- Esc: cancel.\[8\]
- Shift (while drawing): square selection.\[8\]
- Ctrl (after starting to draw): move the selection while drawing.\[8\] As the Mac equivalent, ⌃ or ⌥ is suggested instead of Space-drag; left as an open question.
- Arrow keys: move the cursor by 1 px; Shift+arrow moves it by 10 px.\[8\]
- Delete: clears the selection.\[8\]
- Space: capture all screens (fullscreen).\[8\]
- ~: capture the active monitor.\[8\]

The Keybinds page also lists changing the magnifier size with the mouse wheel and capturing a specific monitor with the 1…0 keys; both are out of the MVP.\[9\] In ShareX's source code, the `RegionCaptureOptions` class has `ShowMagnifier`, `MagnifierPixelCount` and `MagnifierPixelSize` options for the magnifier, and `DetectWindows` and `DetectControls` options for window and control detection.\[10\] Window/control detection (snapping to the window under the mouse) is out of v1 scope.

**2. After-capture tasks.** In ShareX this is a `[Flags]` enum (`AfterCaptureTasks`), so multiple tasks can be selected at the same time. In a 2019 copy of the source code, the values `CopyImageToClipboard = 1 << 4`, `SaveImageToFile = 1 << 6` and `ShowInExplorer = 1 << 12` are visible.\[11\] The selection is made from a checkbox "After capture tasks" menu in the main window and the tray menu. A separate set can also be assigned per hotkey via `TaskSettings` (`UseDefaultAfterCaptureJob`).\[12\] A sample config shows `"AfterCaptureJob": "CopyImageToClipboard, SaveImageToFile, ShowInExplorer"`.\[13\] Our v1 equivalent is a persistent, checkbox-based list: Save to file (PNG), Copy to clipboard, Show notification, and Reveal in Finder. This list will be shared across all hotkeys; a per-hotkey set is left to v2.

File name and folder: since ShareX 12.3.0, the default name pattern on new installs is `%pn_%ra{10}` (random). The older date-time pattern was `%pn_%y-%mo-%d_%h-%mi-%s`.\[14\] The subfolder pattern is `SaveImageSubFolderPattern = "%y-%mo"` in `ApplicationConfig.cs`, i.e. yyyy-MM.\[15\] We choose the date-time route because it is readable and sortable: `~/Pictures/<AppName>/yyyy-MM/Screenshot_yyyy-MM-dd_HH-mm-ss.png`.

**3. The screen must not change (freeze).** ShareX's default region mode works on a frozen screen. Indirect evidence for this is that ShareX also offers a "Region (Transparent)" mode; the README describes this mode as "Allows you to do rectangle capture from non frozen screen".\[16\]\[17\] The same method is used on the Mac side: capture every display as a single frame at hotkey time, make this frame the background of the overlay window, make the selection on it, and crop the PNG from this frame. Open-source references show this can be done quickly. Mio says it "freezes every display in under 80 ms".\[18\] Shotty's PR #21 (markusjura/shotty), dated 9 October 2026, describes freezing displays before windows: "Displays now freeze first and on their own, within about 100 ms of the shortcut, however many windows are open"; previously, with 22 windows open, this took more than a second.

**4. Last region.** In ShareX, "Capture → Last region" re-captures the same area.\[8\]\[19\] In 2015-era source, the last region is kept in the `public static GraphicsPath LastRegionFillPath` field, i.e. in process memory.\[20\] Based on this, we assume it is lost when the application restarts; this could not be confirmed in the current code. ShareX does not show the last region when the overlay opens; this feature has already been requested in issue #1663.\[21\] So ours will have three behaviors:
- The region will be stored persistently: display UUID and a rect in points.
- On the normal region hotkey, the last region will be drawn faintly on the overlay and can be accepted with Enter.
- A separate "Last region" hotkey will capture directly without opening the overlay.

Mac equivalents: the "Remember Last Selection" option in macOS Cmd+Shift+5, CleanShot X's "Capture Previous Area" command, and Shottr's customizable shortcut "Repeat Area" (`shottr://grab/repeat`). \[6\]\[7\]\[22\]\[23\]\[24\]

## B) Plan v1

**Scope estimate: M.** The code is a single application, roughly 15–25 Swift files and one external package. The hard parts are not algorithms but platform details: coordinate conversion (NSScreen's bottom-left-origin global coordinates versus CG/ScreenCaptureKit's top-left-origin coordinates), mixed Retina and non-Retina displays, TCC permissions, and getting the overlay above full-screen Spaces. If an annotation editor were added, the scope would be L.

**Subagent usage: not needed.** The phases depend on each other (overlay → crop → tasks → last region). Producing parallel work would create more context fragmentation than the gain it provides. Building, testing and committing sequentially in a single CC session is sufficient.

**Technical decisions**
- **Minimum target macOS 14.0.** `SCScreenshotManager.captureImage(contentFilter:configuration:)` and `SCContentFilter.pointPixelScale` arrive with 14.0. `SCScreenshotManager.captureImage(in:)`, i.e. capture by a display-independent point rect, requires macOS 15.2+\[25\]\[26\] and is not needed since the whole flow crops from the frozen frame.
- **Language and UI:** Swift 5.10+/6, AppKit overlay (borderless `NSPanel`, one per display), SwiftUI settings window, menu bar app (`LSUIElement = YES`, `NSStatusItem`).
- **Project generation with XcodeGen** (`project.yml`). The `.xcodeproj` is either not committed to the repo or committed in generated form; CC asks about this at the GO stage.
- **Sandbox enabled.** Entitlements: `com.apple.security.app-sandbox`, `com.apple.security.assets.pictures.read-write`, `com.apple.security.files.user-selected.read-write` and `com.apple.security.files.bookmarks.app-scope`.\[27\] If the user selects a folder outside Pictures, a security-scoped bookmark is stored. After the bookmark is resolved, `startAccessingSecurityScopedResource()` is called and balanced with stop; if the bookmark becomes stale, it is renewed.\[28\]\[29\]
- **Capture method:** `SCShareableContent` → for each `SCDisplay`, `SCContentFilter(display:excludingApplications:[our own app], exceptingWindows:[])`. `SCStreamConfiguration.width/height` = display point size × `filter.pointPixelScale`. The reason is that `SCDisplay.width` is in points while `SCStreamConfiguration.width` is in pixels; without the multiplication, Retina yields half resolution, and this bug has occurred in real projects (flutter-webrtc #2241).\[30\]\[31\]\[32\] `showsCursor = false`.
- **Overlay window:** `level = .screenSaver`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `isOpaque = false`, `hidesOnDeactivate = false`. An `NSPanel` subclass with `canBecomeKey = true` is used so it can receive key events. To appear in the separate Space of a full-screen app, `canJoinAllSpaces` and `fullScreenAuxiliary` are both required.\[33\]\[34\]\[35\]
- **`sindresorhus/KeyboardShortcuts` for global hotkeys.** The package is built on Carbon `RegisterEventHotKey` and, per the README, is "fully sandboxed and Mac App Store compatible"\[2\]\[36\] and does not require Accessibility or Input Monitoring permission. The Option+Shift issue must be handled during registration (see the Caveats section below).
- **Launch at login:** `SMAppService.mainApp.register()` / `unregister()` (macOS 13+). When registered, the system shows the user a "login item added" notification.\[37\]\[38\]
- **Persistent display identity:** `CGDisplayCreateUUIDFromDisplayID`. `CGDirectDisplayID` can change on reconnection (in one project a Sidecar display came back successively with IDs 6, 7 and 13, while the UUID stayed the same).\[39\] Another project reports that the UUID can also change after a reboot.\[40\] So the rule is simple: if the UUID is not found, the overlay opens.
- **Permission:** `CGPreflightScreenCaptureAccess()` and `CGRequestScreenCaptureAccess()`. In thread 732726 on the Apple Developer Forums, a developer reports that if preflight's first result is false, "it will continue to return false, even if the app has been given permission"; that is, it can keep returning false until the app is restarted. Onboarding must therefore include a "restart the app after granting permission" step. A fixed Apple Development signature must be used so that the TCC record is not lost on every build. According to CapSoftware/Cap issue #1722, on Sequoia "CGPreflightScreenCaptureAccess() always returns false for ad-hoc signed or unsigned binaries regardless of what permissions are granted in System Settings".

**Left out of the MVP:** annotation editor, window/control snapping, scrolling capture, video and GIF recording, upload, OCR, pin to screen, per-hotkey after-capture sets, monitor selection with the 1…0 keys, multi-region, JPEG/HEIC output.

**Phases**
- **F0 – Skeleton, permission, hotkey:** XcodeGen project, menu bar icon and menu (Capture region, Capture last region, Settings…, Quit). Entitlements, the KeyboardShortcuts SPM package, ⌥⇧4 registration and detection of registration failure. Permission onboarding window. Unit test target.
- **F1 – Freeze, overlay, select, crop, save:** Capture all displays in parallel with ScreenCaptureKit, open one overlay panel per display, select by dragging, show the size/coordinate label, cancel with Esc, crop and save as PNG (a fixed task for now). The selection is clamped to a single display. Pure math lives in the `CaptureGeometry` module and is tested.
- **F2 – After-capture tasks and settings:** `AfterCaptureTask` OptionSet, checkboxes in the menu and a SwiftUI settings window. File name generator, `_2`, `_3` suffixes on collision, folder picker and bookmark. Notification (UserNotifications), copy to clipboard (`NSPasteboard`, PNG and TIFF), reveal in Finder (`NSWorkspace.activateFileViewerSelecting`). Tasks run isolated from each other.
- **F3 – Last region:** `LastRegionStore` (JSON in UserDefaults: displayUUID, rect, saved time). Faint pre-drawing on the overlay and acceptance with Enter. Capture without opening the overlay via ⌥⇧5: only the relevant display is captured and cropped. If the display is missing or the rect is out of bounds, the overlay opens.
- **F4 – Polish:** magnifier (pixel-grid zoom around the cursor), 1/10 px movement with arrow keys, quick capture toggle (when off: move, resize, and finish with Enter/double-click), Space and ~ shortcuts, launch at login, running the manual test checklist.

## C) Claude Code handoff block

**What I am handing off:** I am handing CC the whole of a minimum ShareX alternative for macOS (region capture, after-capture tasks, freeze, last region), in phases. CC will first confirm the plan and the APIs and wait for GO, then finish the phases on its own with build, test and commit.

**Status:** (not sent)

```text
CC-MacShot-1

=== GOAL ===
Write a minimum alternative to Windows' ShareX for macOS. Working name "MacShot" (the final name is an open question; if it changes, the bundle id, folder name and product name must be derived from a single constant). v1 has only four things: (1) region screenshot, (2) preselected after-capture tasks, (3) the screen freezing during selection, (4) remembering the last region. It will be a menu bar app with no Dock icon.

=== ENVIRONMENT AND RULES ===
- Work in a new, empty git repo. The repo root should have README.md, project.yml (XcodeGen), Sources/, Tests/.
- At the end of each phase, commit if the build and tests are green. Message format: "F<n>: <short summary>". Intermediate commits within a phase are allowed.
- NO push, tag, release, notarization, App Store upload. Do not add a remote repo.
- Do NOT use CGWindowListCreateImage, CGDisplayCreateImage or any other legacy CoreGraphics capture API. Capture will be done only with ScreenCaptureKit. (CGWindowListCreateImage is "obsoleted" in the macOS 15 SDK.)
- The only permitted external dependency: sindresorhus/KeyboardShortcuts (SPM). Ask and write your rationale BEFORE adding any other package.
- Minimum deployment target: macOS 14.0. Swift 5.10+ (Swift 6 strict concurrency preferred; if it causes problems, stay in Swift 5 mode with a rationale).
- UI: overlay with AppKit (NSPanel/NSView), settings window with SwiftUI. LSUIElement = YES in Info.plist.
- Generate the project with XcodeGen. If xcodegen is not installed, ask before installing it (via Homebrew or via Mint?).
- App Sandbox ON. Entitlements: com.apple.security.app-sandbox, com.apple.security.assets.pictures.read-write, com.apple.security.files.user-selected.read-write, com.apple.security.files.bookmarks.app-scope. Ask if any other entitlement is needed.
- Signing: sign with a fixed "Apple Development" identity so the TCC (Screen Recording) permission is not lost on every build. Ask me for the DEVELOPMENT_TEAM value; do not continue with ad-hoc signing.
- License: ShareX is licensed under GPL v3. Do NOT copy code from it; use it only as a behavioral reference. Do not copy code from open-source Mac projects either (Mio is GPL-3.0; Screenshot Pro, shotty and ScreenCap are MIT); you may take ideas.

=== WORKFLOW ===
PHASE 0 – Verification and GO (DO NOT WRITE CODE):
1. Read this plan. Verify the signature and availability information of the following APIs in the current SDK, from Xcode's SDK headers or Apple documentation:
   SCShareableContent.excludingDesktopWindows(_:onScreenWindowsOnly:) or .current,
   SCContentFilter(display:excludingApplications:exceptingWindows:),
   SCContentFilter.pointPixelScale and contentRect,
   SCScreenshotManager.captureImage(contentFilter:configuration:),
   SCStreamConfiguration.width/height/showsCursor,
   CGPreflightScreenCaptureAccess / CGRequestScreenCaptureAccess,
   CGDisplayCreateUUIDFromDisplayID,
   SMAppService.mainApp,
   the latest version of KeyboardShortcuts and whether it reports registration failure.
2. Do a scope assessment (S/M/L/XL). My estimate is M; if you disagree, write why.
3. Write the open questions and your assumptions as a numbered list.
4. STOP and wait for "GO". Do not create files or write code until GO arrives.

AFTER GO:
- Complete phases F0 → F4 in order. For each phase: implementation → xcodebuild build → xcodebuild test → commit → short report.
- Phase report format (at most 10 lines): what was done, tests added and their results, known issues, what needs manual testing.
- Do not wait for approval between phases; stop only at a BLOCKER. The following count as BLOCKERs: a permission, signing or team is needed; a new package or entitlement is needed; a requirement is technically impossible or two requirements conflict; the build does not get fixed in 3 attempts.

=== FUNCTIONAL REQUIREMENTS ===

R1 – Region capture (with freeze)
R1.1 When the hotkey is pressed, first capture the image of ALL connected displays in parallel with ScreenCaptureKit (async let or TaskGroup), and show the overlay only after that. For each display:
     filter = SCContentFilter(display: d, excludingApplications: [our own SCRunningApplication; match by bundleIdentifier or processID], exceptingWindows: [])
     config.width  = Int((d.width  * filter.pointPixelScale).rounded())
     config.height = Int((d.height * filter.pointPixelScale).rounded())
     config.showsCursor = false
     image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
R1.2 Frozen image: on each display the overlay draws its own frozen CGImage as the background and darkens the area outside the selection semi-transparently. The result PNG is cropped from this frozen image; a second capture is NOT made.
R1.3 Our own windows (overlay, menu, settings, onboarding) must not get into the capture. excludingApplications in the filter is an additional safeguard; the real safeguard is that the overlay is not shown before the capture completes.
R1.4 Overlay window: one borderless NSPanel subclass (canBecomeKey = true) per NSScreen. level = .screenSaver; collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]; isOpaque = false; hidesOnDeactivate = false. The frame must be exactly screen.frame. While the overlay is open, the app should be activated (NSApp.activate) so that keyboard events arrive. When it closes, focus should return to the previous app.
R1.5 Pixel accuracy: the crop rect is computed by point → pixel conversion. pixelRect = (rectInDisplayPoints × scale), rounded to integers (origin floor, maxX/maxY ceil) and clamped to the image bounds. On mixed Retina (2x) and non-Retina (1x) monitors, each display uses its own scale value. The conversion between NSScreen (bottom-left origin, global) and display-local top-left origin is done in a SINGLE pure function and tested. The scale basis is filter.pointPixelScale (or image.width / display point width), not NSScreen.backingScaleFactor; log if the two disagree.
R1.6 Clamp to a single display: the selection is limited to the display where the drag started. If the mouse moves to another display, the rect is cut at the edge of that display. Multi-display combined capture is not in v1.
R1.7 Selection UI: 1 px white border and a dashed inner line; a "W × H" label (in pixels) next to the selection and the x,y coordinate next to the cursor. Crosshair cursor while drawing.
R1.8 Keyboard and mouse (ShareX behavior):
     - Drag with the left button: selection. If Quick capture is ON (default), capture on release.
     - If Quick capture is OFF: the selection can be moved (drag from inside) and resized with 8 handles. Capture with Enter or double-click inside the selection.
     - Esc or right-click: cancel (no file, no task).
     - Shift (while drawing): square.
     - Arrow keys: cursor or selection 1 px; Shift+arrow: 10 px (F4).
     - Delete: clear the current selection.
     - Space: fullscreen capture of all displays (in v1 each display is saved as a separate file; no merging).
     - ~ (and the ` key; by keyCode, independent of keyboard layout): capture the whole monitor the cursor is on.
     - A very small selection (< 3×3 pt) counts as a click and is ignored.
R1.9 Magnifier (F4): next to the cursor, an 8x magnified, gridded view of roughly 15×15 pixels around the cursor, with the center pixel highlighted. Can be turned off in settings.
R1.10 Performance target: from hotkey to overlay visible must take under 250 ms on 2 displays. Measure and write it in the phase report.

R2 – After-capture tasks
R2.1 OptionSet AfterCaptureTask: saveToFile, copyToClipboard, showNotification, revealInFinder. The selection is persistent (UserDefaults). It is shown as checkboxes in the "After capture" submenu of the menu bar menu, and the same exists in the settings window.
R2.2 Default: saveToFile + copyToClipboard (may change depending on the open question).
R2.3 saveToFile: PNG (ImageIO, CGImageDestination). Default path ~/Pictures/<AppName>/yyyy-MM/Screenshot_yyyy-MM-dd_HH-mm-ss.png. Create the subfolder if it does not exist. If the same name exists, a _2, _3, … suffix is added. Time is per the local time zone and in 24-hour format.
R2.4 The folder can be changed in settings (NSOpenPanel, canChooseDirectories). If a folder outside Pictures is chosen, a security-scoped bookmark is stored. On every write the bookmark is resolved, startAccessing/stopAccessing is balanced, and it is renewed if stale. If the bookmark cannot be resolved, fall back to the default and warn the user with a notification.
R2.5 copyToClipboard: write PNG data to NSPasteboard.general (and also add a TIFF representation). If saveToFile is also selected, the file URL may be added as well; ask this behavior as an open question.
R2.6 showNotification: UserNotifications. Permission is requested on first use. The notification text contains the file name or the "Copied to clipboard" information. Clicking the notification reveals the file in Finder.
R2.7 revealInFinder: NSWorkspace.shared.activateFileViewerSelecting([url]). If saveToFile is not selected, this task is skipped and this is logged.
R2.8 If no task is selected, the capture is still made, but the user is warned once ("No after-capture task is selected").
R2.9 Error isolation: each task runs in its own do/catch; if one fails, the others continue. Errors are logged with os.Logger and shown with a single summary notification.
R2.10 Order: saveToFile → copyToClipboard → revealInFinder → showNotification.

R3 – Remembering the last region
R3.1 After every successful region capture, the following are stored: displayUUID (string obtained via CGDisplayCreateUUIDFromDisplayID), rect (display-local, top-left origin, in points), display point size and a timestamp. Stored in UserDefaults as Codable JSON. Fullscreen captures made with Space and ~ do NOT update the last region.
R3.2 When the overlay opens on the normal region hotkey, if there is a last region and its display is connected, it is drawn faintly (about 40% opacity, dashed) on the relevant display. This rect is accepted with Enter and the capture is made. A new drag invalidates the pre-drawing. If Quick capture is off, the pre-drawing arrives directly as an editable selection.
R3.3 A separate "Capture last region" hotkey, default ⌥⇧5: WITHOUT opening the overlay, captures only the relevant display (same path as R1.1), crops the stored rect and runs the after-capture tasks. The same command is also in the menu.
R3.4 Fallback: if the display belonging to the UUID is not connected, or the rect falls outside the current display bounds (e.g. the resolution changed), a direct capture is NOT made. Instead, the normal overlay opens and a short HUD text is shown ("Last region is not valid in this display layout").
R3.5 If there is no last region, ⌥⇧5 opens the normal overlay.

R4 – Permission onboarding
R4.1 On first launch and before every capture attempt, CGPreflightScreenCaptureAccess() is checked. If false, the onboarding window opens: a text explaining why it is needed, and the buttons "Request permission" (CGRequestScreenCaptureAccess), "Open System Settings" (x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture) and "Restart the app". Since the preflight result may not change during the process lifetime, the relaunch step is REQUIRED.
R4.2 When there is no permission or the capture fails, an empty, black or wallpaper-only image is NOT saved and is not written to the clipboard either. The SCScreenshotManager error is caught and a clear message is shown to the user.
R4.3 On macOS Sequoia and later, the system may periodically ask for re-approval. This is not a bug. State it in the README.

R5 – Settings window (SwiftUI)
R5.1 Hotkeys: "Capture region" (default ⌥⇧4) and "Capture last region" (default ⌥⇧5) with KeyboardShortcuts.Recorder.
R5.2 Save folder: the current path, and "Change…" and "Restore default" buttons.
R5.3 After-capture checkboxes (same state as R2.1).
R5.4 Quick capture toggle (default on), Magnifier toggle (default on).
R5.5 Launch at login toggle: SMAppService.mainApp.register() / unregister(). The displayed state is read from SMAppService.mainApp.status; in the requiresApproval state, explain to the user.
R5.6 Permission status row and an "Open onboarding" button.

HOTKEY RISK (must be addressed):
On macOS 15.0–15.1, in sandboxed apps, RegisterEventHotKey registrations using only the Option or Option+Shift modifier did not work (error -9868). This restriction was reverted in 15.2. Such shortcuts may also not trigger while secure input is on. To do:
- Detect whether the shortcut was actually registered after registration. If KeyboardShortcuts does not report this, write a small helper that verifies the same combination at launch with a one-time RegisterEventHotKey/UnregisterEventHotKey attempt.
- If registration fails, show a warning in settings and switch with one click to the fallback shortcuts: ⌃⇧4 and ⌃⇧5.
- The conflict warning with the ⌘⇧3/4/5 system shortcuts comes from KeyboardShortcuts.Recorder; do not touch it.

=== ARCHITECTURE SUGGESTION (CC may change it, writing a rationale) ===
App/ (AppDelegate, StatusItemController, Hotkeys)
Capture/ (ScreenSnapshotService: gets a CGImage per display via SCK; DisplayInfo: id, uuid, frame, scale)
Overlay/ (OverlayPanel, OverlayView, SelectionStateMachine (pure, testable), MagnifierView)
Geometry/ (CaptureGeometry: coordinate conversion, clamp, pixel rounding; pure functions)
Output/ (FileNamer, ImageWriter, AfterCaptureRunner, ClipboardWriter, Notifier)
Persistence/ (SettingsStore, LastRegionStore, FolderBookmarkStore)
Settings/ (SwiftUI views)
Onboarding/

=== TEST REQUIREMENTS ===
Unit tests (XCTest or Swift Testing):
- Coordinate and scale conversion: global NSScreen rect ↔ display-local top-left point rect ↔ pixel rect. 1x, 2x and fractional scale (e.g. 1.5 or scaled modes); a secondary display with a negative origin (a monitor placed to the left or above); vertical arrangement.
- Crop math: rounding rule (floor/ceil), clamp to image bounds, rejection of zero or negative size, clamp to a single display (diagonal drag).
- Selection state machine: quick capture on/off; square with Shift; 1/10 px with arrow keys; Esc; Enter; Delete.
- File name generation: expected name and yyyy-MM folder with a fixed Date and TimeZone; _2, _3 on collision; year and month boundary.
- Region persistence: encode/decode; UUID match; fallback decision when the display is absent; fallback decision when the rect is out of bounds; a fullscreen capture not updating the last region.
- AfterCaptureRunner: the others running when one task fails (with mocks); revealInFinder being skipped when saveToFile is off.

Manual test checklist (create as docs/manual-test.md in the repo and fill it in at the end of F4):
[ ] Single Retina display: region, pixel accuracy of the crop (compare with the size of a known UI element)
[ ] Retina built-in display + 1x external display: capture on both displays, sharpness, correct size
[ ] External display placed to the left of/above the main display (negative coordinates)
[ ] Dragging between two displays → clamp to the starting display
[ ] Capture in a different Space
[ ] The overlay is visible and capture works over a full-screen app (Safari, a Keynote presentation)
[ ] An open menu (e.g. an app's File menu) and tooltip/hover state are captured in the frozen frame
[ ] The overlay, menu bar menu or settings window does not appear in the output
[ ] When cancelled with Esc, the file and clipboard do not change
[ ] Quick capture off: move, resize, Enter, double-click
[ ] Space and ~ shortcuts
[ ] ⌥⇧5: same region without opening the overlay; overlay fallback with the external display unplugged
[ ] The last region being preserved after the app is restarted
[ ] When permission is revoked, no empty image being saved and onboarding opening
[ ] Moving the folder outside Pictures, restarting the app, saving still working (bookmark)
[ ] Launch at login on/off, after reboot
[ ] Hotkey registration failure scenario (if a macOS 15.0/15.1 machine is available) and the fallback shortcut

=== DEFINITION OF DONE ===
- All of R1–R5 satisfied; F0–F4 in separate commits.
- xcodebuild build and test green without a flood of warnings; unit tests cover the list above.
- docs/manual-test.md created; items CC can run on its own machine are marked, those it cannot are listed as "awaiting manual".
- README: setup (xcodegen generate, team setting), permission flow, hotkey risk, known limitations, architecture summary.
- CGWindowListCreateImage or any legacy capture API is absent from the codebase (verify with grep and state it in the report).
- No dependencies other than KeyboardShortcuts.
- In the final report: what was done, the measured overlay latency, known issues, v2 suggestions (window snapping, per-hotkey task set, annotation).
```

## D) Open questions

1. **What should the application be named?** Options: (a) keep "MacShot"; (b) another name (write it); (c) "MacShot" for now, change it later. The bundle id will be `com.<your-domain>.<name>`; also write the domain.
2. **What is the distribution target?** (a) Personal use only: the sandbox stays on but there is no obligation to comply with App Store rules; (b) Mac App Store in the future: the sandbox is mandatory, no default hotkey is assigned, and the user picks one on first launch (the KeyboardShortcuts README recommends not assigning a default shortcut in published apps);\[36\] (c) notarized distribution outside the App Store: the option to turn off the sandbox opens up.
3. **What should the default hotkeys be?** (a) Region ⌥⇧4, last region ⌥⇧5; if it does not work on macOS 15.0–15.1, automatically fall back to ⌃⇧4 and ⌃⇧5; (b) ⌃⇧4 and ⌃⇧5 from the start (safe on every version); (c) turn off the system's ⌘⇧4 and use it (you would need to turn it off manually in system settings); (d) other (write it). Also: should the "move" modifier during selection, as the equivalent of ShareX's Ctrl, be ⌃ or ⌥?
4. **What should the default after-capture selection be?** (a) Save + copy to clipboard; (b) save only; (c) copy to clipboard only; (d) save + copy to clipboard + show notification. Additionally: when both save and copy are selected, should a file reference be added to the clipboard along with the image (yes/no)?
5. **Should CC wait for approval between phases?** (a) No, stop only at a blocker (the default in the block); (b) yes, report at the end of each phase and wait for GO; (c) stop only at the end of F1 (to verify freeze and crop manually), and finish the rest on its own.
6. **Should the Xcode project be committed to the repo?** (a) No, only `project.yml` is committed and `.xcodeproj` is added to .gitignore; (b) yes, the generated `.xcodeproj` is committed as well.
7. **Do you have an Apple Developer Team ID?** (a) Yes (give the value); (b) only a free Apple ID with a "Personal Team"; (c) none. At least (b) is needed so the TCC permission is not reset on every build.

## Caveats

- **Option+Shift hotkey restriction:** An Apple Frameworks engineer explained this restriction in thread 763878 on the Developer Forums as follows: "This was an intentional change in macOS Sequoia to limit the ability of key-logging malware to observe keys in other applications". The rationale is that Shift+Option can produce alternative characters such as Ø in passwords. The Feedback Assistant record (FB15168205) was closed as "Fixed". Matthias Gansrigler, in his updated post on the Eternal Storms blog, also says "option-based keyboard shortcuts are allowed again for sandboxed 3rd-party apps on macOS Sequoia 15.2". Developer fifafu, in sindresorhus/KeyboardShortcuts issue #176 (24.10.2024), reports: "While secure input mode is active even non-sandboxed apps can not make use of shortcuts that consist of single keys, opt+key or shift+opt+key anymore." For this reason the fallback shortcut logic was made mandatory.
- **TCC behavior:** Preflight returning false until relaunch is not stated in Apple's official reference. It is based on a developer report on the Developer Forums and independent 2026 GitHub tests.\[41\]\[42\] The periodic re-approval on Sequoia came monthly in 15.0. In 15.1, Apple relaxed it in the beta 6 release notes (as relayed by 9to5Mac on 07.10.2024): "Users will see fewer dialogs if they regularly use apps in which they have already acknowledged and accepted the risks." The exact interval has not been documented by Apple.
- **Persistence of ShareX's "Last region":** That the last region is kept only for the session is an inference based on a static field in 2015-era source.\[20\] The current `CaptureLastRegion.cs` could not be read. This does not affect the plan, since our requirement is persistent storage anyway.
- **Display UUID stability:** That the UUID can change after a reboot is the claim of a single third-party project.\[40\] The overlay fallback in R3.4 makes this risk harmless for the user.
- **Open-source references:** Screenshot Pro (MIT, ScreenCaptureKit, freeze-frame overlay, last region, SMAppService; macOS 15+), macshot (Swift + AppKit, freezes the screen with a hotkey), Mio (GPL-3.0, macOS 15+) and shotty (MIT, a single file of about 400 lines) are useful for architectural ideas.\[18\]\[43\]\[44\]\[45\] The rule not to copy GPL-licensed code was written into the block.
- **Shottr's freeze mode:** Shottr's freezing area capture is "experimental" according to its developer. Shottr is mainly built around a flow of taking the full screen and then cropping.\[46\]\[47\] So our freeze approach is a deliberate choice even compared with a commercial competitor, but measuring latency at the end of F1 is important.

## Sources

1. [Keyboard Shortcuts using Option and/or Shift Modifiers Only No Longer Allowed on macOS Sequoia \[Updated for macOS 15.2\]](https://blog.eternalstorms.at/2024/09/23/keyboard-shortcuts-using-option-and-or-shift-modifiers-only-no-longer-allowed-on-macos-sequoia/)
2. [FB15168205: Global keyboard shortcuts (RegisterEventHotKey) with only Option or Option+Shift as modifiers do not work on macOS 15 · Issue #552 · feedback-assistant/reports · GitHub](https://github.com/feedback-assistant/reports/issues/552)
3. [GitHub - Fidetro/CapturingScreenContentInMacOS: Capturing Screen Content In MacOS Apple sample code · GitHub](https://github.com/Fidetro/CapturingScreenContentInMacOS)
4. [developer.apple.com](<https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(display:excludingapplications:exceptingwindows:).md>)
5. [\[FIXED\] JUCE not compiling in sequoia 15.0 - MacOSX and iOS - JUCE](https://forum.juce.com/t/fixed-juce-not-compiling-in-sequoia-15-0/62868)
6. [Shottr](https://shottr.cc/)
7. [App to take repeated screen shots](https://forums.macrumors.com/threads/app-to-take-repeated-screen-shots.2413823/)
8. [Region Capture - ShareX](https://getsharex.com/docs/region-capture)
9. [Keybinds - ShareX](https://getsharex.com/docs/keybinds)
10. [Region Capture](https://deepwiki.com/ShareX/ShareX/3.1-region-capture)
11. [github.com](https://github.com/danielbisson56/ShareXBetterCodeHub/blob/master/Enums.cs)
12. [Feature request : Audio only capture · Issue #7816 · ShareX/ShareX · GitHub](https://github.com/ShareX/ShareX/issues/7816)
13. [gist.github.com](https://gist.github.com/AlanD20/64242de46e36c98b8f8d683190bd8669)
14. [request: date in file names · Issue #8143 · ShareX/ShareX · GitHub](https://github.com/ShareX/ShareX/issues/8143)
15. [ShareX/ShareX/ApplicationConfig.cs at master · ShareX/ShareX · GitHub](https://github.com/ShareX/ShareX/blob/master/ShareX/ApplicationConfig.cs)
16. [ShareX/README.md at master · Upload/ShareX · GitHub](https://github.com/Upload/ShareX/blob/master/README.md)
17. [Website: getsharex.com](https://github.com/k3d3/ShareX)
18. [GitHub - iSoldLeo/Mio: A native macOS screenshot tool that freezes every display in under 80 ms when you press the hotkey — pick a window, a region, or a whole screen from still frames. Window captures keep their transparent rounded corners. Built-in editor for annotations. Menu bar only, fully offline. · GitHub](https://github.com/iSoldLeo/Mio)
19. [github.com](https://github.com/banksymate/ShareX)
20. [ShareX/ShareX.ScreenCaptureLib/Forms/Surface.cs at master · Upload/ShareX · GitHub](https://github.com/Upload/ShareX/blob/master/ShareX.ScreenCaptureLib/Forms/Surface.cs)
21. [github.com](https://github.com/ShareX/ShareX/issues/1663)
22. [How to Screenshot on Mac Beyond Simply Holding ⇧, ⌘, 3 or 4](https://www.raycast.com/resources/how-to-screenshot-on-mac)
23. [Test on macOS: Record Screen picker (CleanShot-style) · Issue #55 · jsonify/skreener2 · GitHub](https://github.com/jsonify/skreener2/issues/55)
24. [URL Scheme (deeplinks)](https://shottr.cc/kb/urlschemes)
25. [developer.apple.com](<https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage(in:completionhandler:).md>)
26. [screencapturekit - Rust](https://doom-fish.github.io/screencapturekit-rs/screencapturekit/)
27. [github.com](https://github.com/vinceglb/FileKit/issues/590)
28. [stopAccessingSecurityScopedResource](https://developer.apple.com/forums/thread/84951)
29. [Understanding File System Access in macOS Sandboxed Applications](https://codebit-inc.com/blog/mastering-file-access-macos-sandboxed-apps/)
30. [\[macOS\] Screen capture is half resolution on Retina displays (ScreenCaptureKit is configured in points) · Issue #2241 · flutter-webrtc/flutter-webrtc · GitHub](https://github.com/flutter-webrtc/flutter-webrtc/issues/2241)
31. [fix(screenshot): Retina 屏幕下 ScreenCaptureKit 截图分辨率按逻辑点输出导致模糊 · Issue #8 · Danyhug/DH-TransShot · GitHub](https://github.com/Danyhug/DH-TransShot/issues/8)
32. [fix(macos): capture ScreenCaptureKit screens at their pixel size by FlyHubs · Pull Request #2242 · flutter-webrtc/flutter-webrtc · GitHub](https://github.com/flutter-webrtc/flutter-webrtc/pull/2242)
33. [fix(macos): keep the overlay visible over full-screen presentations by matteobaccan · Pull Request #10 · matteobaccan/Ritardometro · GitHub](https://github.com/matteobaccan/Ritardometro/pull/10)
34. [collectionbehavior swift.struct](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct.md)
35. [Overlay on macOS Full-Screen Apps with AppKit \[Fixed\]](https://www.technetexperts.com/macos-python-fullscreen-overlay-fix/)
36. [KeyboardShortcuts/readme.md at main · sindresorhus/KeyboardShortcuts · GitHub](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/readme.md)
37. [Add launch at login setting to a macOS app](https://nilcoalescing.com/blog/LaunchAtLoginSetting/)
38. [Manage login items and background tasks on Mac - Apple Support (GU)](https://support.apple.com/en-gu/guide/deployment/depdca572563/web)
39. [feat(M1-22): let Show on pick a connected display, Sidecar iPads included by taroj1205 · Pull Request #159 · taroj1205/mado · GitHub](https://github.com/taroj1205/mado/pull/159)
40. [GitHub - KevinLogan84/Window-Minder: Menu bar app that saves and restores window positions for each display setup. · GitHub](https://github.com/KevinLogan84/Window-Minder)
41. [feat: macOS capture, input and permission checks (#72) by mendsec · Pull Request #140 · barahn/remotekit · GitHub](https://github.com/barahn/remotekit/pull/140)
42. [Understanding CGRequestScreenCaptu…](https://developer.apple.com/forums/thread/732726)
43. [GitHub - CreativeLyons/screenshot-pro: Free, open source screenshot tool for macOS on Apple silicon: capture, annotate, share. · GitHub](https://github.com/CreativeLyons/screenshot-pro)
44. [GitHub - uuu4/shotty: Open source screenshot tool for macOS in 393 lines of Swift. Freeze the screen, select an area, draw on it before it is copied anywhere, and OCR it with the indentation intact. No dependencies, no account, no network calls. · GitHub](https://github.com/uuu4/shotty)
45. [github.com](https://github.com/sw33tLie/macshot)
46. [Shottr Mac Screenshot Tool: Fast, Free, Pixel-Perfect (2026)](https://www.bitdoze.com/shottr-mac-screenshot-tool/)
47. [Frequently Asked Questions](https://shottr.cc/kb/faq)
