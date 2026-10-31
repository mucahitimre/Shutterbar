import AppKit
import MacShotCore
import ScreenCaptureKit

/// Runs the hotkey → freeze → overlay → crop → output flow.
@MainActor
final class CaptureCoordinator {
    static let lastRegionInvalidMessage = "Last region is not valid for this display layout"

    private let snapshotter = ScreenSnapshotService()
    private let overlay = OverlayController()
    private let output: CaptureOutput
    private let preferences: Preferences
    private let lastRegion = LastRegionStore()
    private var isBusy = false
    private let onPermissionMissing: () -> Void

    init(preferences: Preferences = .shared, onPermissionMissing: @escaping () -> Void) {
        self.preferences = preferences
        self.output = CaptureOutput(preferences: preferences)
        self.onPermissionMissing = onPermissionMissing
        overlay.onMagnifierPixelCountChange = { [preferences] in preferences.magnifierPixelCount = $0 }
    }

    func captureRegion() {
        run { await $0.runRegionCapture(hud: nil) }
    }

    /// R3.3–R3.5: last region without opening the overlay; if invalid, overlay + HUD; if there is none, a plain overlay.
    func captureLastRegion() {
        run { await $0.runLastRegionCapture() }
    }

    private func run(_ body: @escaping (CaptureCoordinator) async -> Void) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            await body(self)
        }
    }

    // MARK: Region (overlay)

    private func runRegionCapture(hud: String?) async {
        let clock = ContinuousClock()
        let start = clock.now

        // The window list is taken together with the freeze; once the overlay is open our own panels would be included too.
        let windows = preferences.windowSnap ? WindowList.onScreen() : []
        let snapshots: [DisplaySnapshot]
        do {
            snapshots = try await snapshotter.snapshotAll()
        } catch {
            report(error)
            return
        }
        let frozen = clock.now

        let result = await overlay.run(
            snapshots: snapshots,
            quickCapture: preferences.quickCapture,
            magnifierPixelCount: preferences.magnifier ? preferences.magnifierPixelCount : nil,
            preview: preview(for: snapshots),
            windows: windows,
            hud: hud
        ) {
            let shown = clock.now
            Log.capture.info("Latency: freeze \(Self.ms(frozen - start), privacy: .public) ms, overlay visible \(Self.ms(shown - start), privacy: .public) ms, screen count \(snapshots.count)")
        }

        switch result {
        case .cancelled:
            Log.capture.info("Cancelled")
        case .region(let snapshot, let rect, let intent, let isWindow):
            guard let image = ImageCropper.crop(snapshot.image, pointRect: rect, displayPointSize: snapshot.frame.size) else {
                Log.capture.error("Crop is empty: \(String(describing: rect), privacy: .public)")
                return
            }
            if isWindow {
                Log.capture.info("Window capture; last region unchanged")
            } else {
                remember(rect, on: snapshot)
            }
            switch intent {
            case .afterCapture: output.deliver([image])
            case .clipboardOnly: output.copyOnly([image])
            }
        case .screens(let snapshots):
            lastRegion.record(.fullScreen)
            output.deliver(snapshots.map(\.image))
        }
    }

    /// R3.2: if the last region's display is connected and the rect fits, a preview on that display.
    private func preview(for snapshots: [DisplaySnapshot]) -> (displayID: CGDirectDisplayID, rect: CGRect)? {
        guard let last = lastRegion.load() else { return nil }
        let displays = snapshots.compactMap { snapshot in
            snapshot.uuid.map { LastRegion.Display(uuid: $0, pointSize: snapshot.frame.size) }
        }
        guard case .valid = last.resolve(in: displays),
              let snapshot = snapshots.first(where: { $0.uuid == last.displayUUID })
        else { return nil }
        return (snapshot.displayID, last.rect)
    }

    // MARK: Last region (without overlay)

    private func runLastRegionCapture() async {
        guard let last = lastRegion.load() else {
            Log.capture.info("No last region; opening overlay")
            await runRegionCapture(hud: nil)
            return
        }

        let screens = NSScreen.screens.compactMap { screen -> (id: CGDirectDisplayID, display: LastRegion.Display)? in
            guard let id = screen.displayID, let uuid = DisplayIdentity.uuid(for: id) else { return nil }
            return (id, LastRegion.Display(uuid: uuid, pointSize: screen.frame.size))
        }
        guard case .valid(let display) = last.resolve(in: screens.map(\.display)),
              let displayID = screens.first(where: { $0.display == display })?.id
        else {
            Log.capture.info("Last region invalid; overlay + HUD")
            await runRegionCapture(hud: Self.lastRegionInvalidMessage)
            return
        }

        let snapshot: DisplaySnapshot
        do {
            snapshot = try await snapshotter.snapshot(displayID: displayID)
        } catch {
            report(error)
            return
        }
        guard let image = ImageCropper.crop(snapshot.image, pointRect: last.rect, displayPointSize: snapshot.frame.size) else {
            Log.capture.error("Last region crop is empty: \(String(describing: last.rect), privacy: .public)")
            await runRegionCapture(hud: Self.lastRegionInvalidMessage)
            return
        }
        Log.capture.info("Last region captured without overlay")
        remember(last.rect, on: snapshot)
        output.deliver([image])
    }

    private func remember(_ rect: CGRect, on snapshot: DisplaySnapshot) {
        guard let uuid = snapshot.uuid else {
            Log.capture.error("No display UUID; last region not stored")
            return
        }
        lastRegion.record(.region(LastRegion(displayUUID: uuid, rect: rect, displaySize: snapshot.frame.size, date: Date())))
    }

    #if DEBUG
    /// Opens the editor with a synthetic image; the result goes to the after-capture tasks.
    func openEditorSample() {
        let width = 1200, height = 760
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        for i in 0..<12 {
            let shade = 0.55 + CGFloat(i) * 0.035
            context.setFillColor(CGColor(srgbRed: shade, green: shade * 0.95, blue: 1, alpha: 1))
            context.fill(CGRect(x: i * 100, y: 0, width: 100, height: height))
        }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 150, y: 200, width: 900, height: 360))
        guard let image = context.makeImage() else { return }
        var tasks = preferences.afterCaptureTasks
        tasks.insert(.annotate)
        output.deliver([image], tasks: tasks)
    }
    #endif

    // MARK: Errors

    private func report(_ error: any Error) {
        Log.capture.error("Capture error: \(error.localizedDescription, privacy: .public)")
        if Self.isPermissionError(error) || !PermissionService.hasScreenCaptureAccess {
            onPermissionMissing()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Could not take screenshot"
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }

    private static func isPermissionError(_ error: any Error) -> Bool {
        let underlying: any Error = if case SnapshotError.captureFailed(let inner) = error { inner } else { error }
        let ns = underlying as NSError
        return ns.domain == SCStreamErrorDomain && ns.code == SCStreamError.userDeclined.rawValue
    }

    private static func ms(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds * 1000 + attoseconds / 1_000_000_000_000_000)
    }
}
