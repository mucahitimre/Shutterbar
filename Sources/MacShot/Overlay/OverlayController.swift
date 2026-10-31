import AppKit
import MacShotCore

/// Bölgenin nereye gideceği: Enter → after-capture task'ları, ⌘C → yalnız pano.
enum CaptureIntent {
    case afterCapture
    case clipboardOnly
}

enum OverlayResult {
    case region(DisplaySnapshot, CGRect, CaptureIntent)
    case screens([DisplaySnapshot])
    case cancelled
}

/// Her ekran için bir overlay paneli açar ve kullanıcının seçimini bekler.
@MainActor
final class OverlayController: OverlayViewDelegate {
    private var panels: [OverlayPanel] = []
    private var views: [OverlayView] = []
    private var continuation: CheckedContinuation<OverlayResult, Never>?
    private var previousApp: NSRunningApplication?

    var isPresented: Bool { continuation != nil }

    /// - Parameter preview: son bölgenin hangi ekranda (displayID) hangi rect olduğu.
    func run(
        snapshots: [DisplaySnapshot],
        quickCapture: Bool,
        preview: (displayID: CGDirectDisplayID, rect: CGRect)?,
        hud: String? = nil,
        onPresented: @escaping () -> Void
    ) async -> OverlayResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present(snapshots: snapshots, quickCapture: quickCapture, preview: preview, hud: hud)
            onPresented()
        }
    }

    private func present(
        snapshots: [DisplaySnapshot],
        quickCapture: Bool,
        preview: (displayID: CGDirectDisplayID, rect: CGRect)?,
        hud: String?
    ) {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front

        let screens = NSScreen.screens
        for snapshot in snapshots {
            guard let screen = screens.first(where: { $0.displayID == snapshot.displayID }) else { continue }
            let panel = OverlayPanel(screen: screen)
            let previewRect = preview?.displayID == snapshot.displayID ? preview?.rect : nil
            let view = OverlayView(snapshot: snapshot, quickCapture: quickCapture, preview: previewRect)
            view.delegate = self
            panel.contentView = view
            panel.orderFrontRegardless()
            panels.append(panel)
            views.append(view)
        }

        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        let active = views.first { $0.snapshot.frame.contains(mouse) } ?? views.first
        if let active {
            makeKey(active)
            active.updateCursor(fromGlobal: mouse)
            if let hud { active.showHUD(hud) }
        }
        NSCursor.crosshair.set()
        CATransaction.flush()
    }

    private func makeKey(_ view: OverlayView) {
        view.window?.makeKey()
        view.window?.makeFirstResponder(view)
    }

    private func finish(_ result: OverlayResult) {
        guard let continuation else { return }
        self.continuation = nil
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels.removeAll()
        views.removeAll()
        NSCursor.arrow.set()
        previousApp?.activate()
        previousApp = nil
        continuation.resume(returning: result)
    }

    // MARK: OverlayViewDelegate

    func overlayView(_ view: OverlayView, didProduce output: SelectionStateMachine.Output) {
        switch output {
        case .none:
            break
        case .capture(let rect):
            finish(.region(view.snapshot, rect, .afterCapture))
        case .copy(let rect):
            finish(.region(view.snapshot, rect, .clipboardOnly))
        case .cancel:
            finish(.cancelled)
        case .captureAllScreens:
            finish(.screens(views.map(\.snapshot)))
        case .captureActiveScreen:
            let mouse = NSEvent.mouseLocation
            let snapshot = views.first { $0.snapshot.frame.contains(mouse) }?.snapshot ?? view.snapshot
            finish(.screens([snapshot]))
        case .warpCursor(let point):
            let primaryHeight = NSScreen.screens.first?.frame.height ?? view.snapshot.frame.height
            CGWarpMouseCursorPosition(CaptureGeometry.toQuartzGlobal(point, displayFrame: view.snapshot.frame, primaryScreenHeight: primaryHeight))
        }
    }

    func overlayViewDidBeginSelection(_ view: OverlayView) {
        for other in views where other !== view {
            other.resetSelection()
        }
    }

    func overlayViewMouseEntered(_ view: OverlayView) {
        // Sürükleme sürerken anahtar pencereyi değiştirme; seçim başladığı ekranda kalır.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        makeKey(view)
    }
}
