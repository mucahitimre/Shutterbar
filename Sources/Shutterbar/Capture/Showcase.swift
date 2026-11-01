#if DEBUG
import AppKit
@preconcurrency import ScreenCaptureKit
import ShutterbarCore

/// Development only (`-ShutterbarShowcase`): makes the README screenshots from whatever Safari window is frontmost
/// (open a neutral page first). Unlike normal captures it includes Shutterbar's own windows — that's the point.
/// Writes `~/Pictures/Shutterbar/showcase/overlay.png` and `editor.png`.
@MainActor
enum Showcase {
    static let folder = SaveFolder.defaultRoot.appendingPathComponent("showcase", isDirectory: true)

    static func run() {
        Task {
            do {
                try await makeScreenshots()
                Log.capture.info("SHOWCASE done: \(folder.path, privacy: .public)")
            } catch {
                Log.capture.error("SHOWCASE failed: \(error.localizedDescription, privacy: .public)")
            }
            NSApp.terminate(nil)
        }
    }

    private static func makeScreenshots() async throws {
        try? await Task.sleep(for: .seconds(1))
        guard let safari = safariWindowFrame() else { throw ShowcaseError.noSafariWindow }
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(safari) }), let displayID = screen.displayID else {
            throw ShowcaseError.noSafariWindow
        }
        let local = CaptureGeometry.toDisplayLocal(safari, displayFrame: screen.frame)
        // A selection over the page body, below the browser chrome.
        let selection = CGRect(x: local.minX + local.width * 0.16, y: local.minY + local.height * 0.3,
                               width: local.width * 0.52, height: local.height * 0.34).integral

        // 1. Overlay with the toolbar and an editable selection. The frozen frame holds only Safari's windows, so no
        //    other app (chat titles, mail…) can end up in the picture.
        let snapshots = [try await safariOnlySnapshot(displayID: displayID, screen: screen)]
        let overlay = OverlayController()
        OverlayView.hidesCursorInfo = true
        Preferences.shared.captureMode = .selection
        var toolbarFrame: CGRect?
        let presented = Task {
            _ = await overlay.run(snapshots: snapshots, quickCapture: false, magnifierPixelCount: nil,
                                  preview: (displayID, selection), windows: []) {}
        }
        try? await Task.sleep(for: .milliseconds(700))
        overlay.moveToolbarForShowcase(into: safari)
        try? await Task.sleep(for: .milliseconds(400))
        toolbarFrame = overlay.toolbarFrameForShowcase
        _ = toolbarFrame
        // Skip the window's top edge (Safari's title bar area is not part of the Safari-only frozen frame).
        let area = CGRect(x: local.minX, y: local.minY + 8, width: local.width, height: local.height - 8)
            .intersection(CGRect(origin: .zero, size: screen.frame.size)).integral
        let overlayImage = try await captureOwnWindows(displayID: displayID, rect: area)
        overlay.dismissForShowcase()
        _ = await presented.value
        OverlayView.hidesCursorInfo = false
        try PNGEncoder.write(overlayImage, to: folder.appendingPathComponent("overlay.png"), overwrite: true)

        // 2. Editor with a few annotations on the selected part of the page.
        guard let snapshot = snapshots.first(where: { $0.displayID == displayID }),
              let crop = ImageCropper.crop(snapshot.image, pointRect: selection, displayPointSize: snapshot.frame.size)
        else { throw ShowcaseError.cropFailed }
        let editor = EditorWindowController(image: crop)
        let editing = Task { _ = await editor.run() }
        try? await Task.sleep(for: .milliseconds(400))
        let windowNumber = editor.prepareShowcase()
        try? await Task.sleep(for: .milliseconds(700))
        let editorImage = try await captureWindow(number: windowNumber)
        editor.closeShowcase()
        _ = await editing.value
        try PNGEncoder.write(editorImage, to: folder.appendingPathComponent("editor.png"), overwrite: true)
    }

    /// AppKit-global frame of the largest on-screen Safari window.
    private static func safariWindowFrame() -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return info.compactMap { entry -> CGRect? in
            guard entry[kCGWindowOwnerName as String] as? String == "Safari",
                  entry[kCGWindowLayer as String] as? Int == 0,
                  let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let quartz = CGRect(dictionaryRepresentation: dict), quartz.width > 400
            else { return nil }
            return CGRect(x: quartz.minX, y: primaryHeight - quartz.maxY, width: quartz.width, height: quartz.height)
        }.max { $0.width * $0.height < $1.width * $1.height }
    }

    /// Frozen frame of the display with only Safari's windows in it.
    private static func safariOnlySnapshot(displayID: CGDirectDisplayID, screen: NSScreen) async throws -> DisplaySnapshot {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw ShowcaseError.noDisplay }
        let windows = content.windows.filter { $0.owningApplication?.bundleIdentifier == "com.apple.Safari" && $0.windowLayer == 0 }
        guard !windows.isEmpty else { throw ShowcaseError.noSafariWindow }
        let filter = SCContentFilter(display: display, including: windows)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return DisplaySnapshot(displayID: displayID, uuid: DisplayIdentity.uuid(for: displayID), frame: screen.frame, image: image)
    }

    /// Shutterbar's own windows only (overlay with the Safari-only frozen frame, toolbar).
    private static func captureOwnWindows(displayID: CGDirectDisplayID, rect: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw ShowcaseError.noDisplay }
        let pid = ProcessInfo.processInfo.processIdentifier
        let filter = SCContentFilter(display: display, including: content.windows.filter { $0.owningApplication?.processID == pid })
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.sourceRect = rect
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private static func captureWindow(number: Int) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { Int($0.windowID) == number }) else { throw ShowcaseError.noWindow }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    enum ShowcaseError: LocalizedError {
        case noSafariWindow, noDisplay, noWindow, cropFailed
        var errorDescription: String? {
            switch self {
            case .noSafariWindow: "Open a page in Safari first"
            case .noDisplay: "Display not found"
            case .noWindow: "Editor window not found"
            case .cropFailed: "Could not crop the page"
            }
        }
    }
}
#endif
