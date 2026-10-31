import AppKit
import MacShotCore

/// Where the region goes: Enter → after-capture tasks, ⌘C → clipboard only.
enum CaptureIntent {
    case afterCapture
    case clipboardOnly
}

enum OverlayResult {
    /// `isWindow`: an unmodified window picked by clicking; not stored as the last region.
    case region(DisplaySnapshot, CGRect, CaptureIntent, isWindow: Bool)
    case screens([DisplaySnapshot])
    case cancelled
}

/// Opens an overlay panel for each screen and waits for the user's selection.
@MainActor
final class OverlayController: OverlayViewDelegate {
    private var panels: [OverlayPanel] = []
    private var views: [OverlayView] = []
    private var continuation: CheckedContinuation<OverlayResult, Never>?
    private var previousApp: NSRunningApplication?

    var isPresented: Bool { continuation != nil }

    /// Magnifier size changed with the mouse wheel; the caller listens to persist it.
    var onMagnifierPixelCountChange: ((Int) -> Void)?

    /// - Parameter preview: which display (displayID) and rect the last region is on.
    func run(
        snapshots: [DisplaySnapshot],
        quickCapture: Bool,
        magnifierPixelCount: Int?,
        preview: (displayID: CGDirectDisplayID, rect: CGRect)?,
        windows: [WindowSnap.Window] = [],
        hud: String? = nil,
        onPresented: @escaping () -> Void
    ) async -> OverlayResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present(
                snapshots: snapshots, quickCapture: quickCapture, magnifierPixelCount: magnifierPixelCount,
                preview: preview, windows: windows, hud: hud
            )
            onPresented()
        }
    }

    private func present(
        snapshots: [DisplaySnapshot],
        quickCapture: Bool,
        magnifierPixelCount: Int?,
        preview: (displayID: CGDirectDisplayID, rect: CGRect)?,
        windows: [WindowSnap.Window],
        hud: String?
    ) {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front

        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for snapshot in snapshots {
            guard let screen = screens.first(where: { $0.displayID == snapshot.displayID }) else { continue }
            let panel = OverlayPanel(screen: screen)
            let previewRect = preview?.displayID == snapshot.displayID ? preview?.rect : nil
            let view = OverlayView(snapshot: snapshot, quickCapture: quickCapture, magnifierPixelCount: magnifierPixelCount, preview: previewRect)
            view.delegate = self
            view.setWindowRects(WindowSnap.localRects(
                windows, excludingPID: ownPID, displayFrame: snapshot.frame, primaryScreenHeight: primaryHeight
            ))
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
            finish(.region(view.snapshot, rect, .afterCapture, isWindow: view.machine.selectionIsWindow))
        case .copy(let rect):
            finish(.region(view.snapshot, rect, .clipboardOnly, isWindow: view.machine.selectionIsWindow))
        case .cancel:
            finish(.cancelled)
        case .captureAllScreens:
            finish(.screens(views.map(\.snapshot)))
        case .captureActiveScreen:
            let mouse = NSEvent.mouseLocation
            let snapshot = views.first { $0.snapshot.frame.contains(mouse) }?.snapshot ?? view.snapshot
            finish(.screens([snapshot]))
        case .captureScreen(let index):
            let screens = NSScreen.screens
            guard index < screens.count,
                  let snapshot = views.first(where: { $0.snapshot.displayID == screens[index].displayID })?.snapshot
            else {
                NSSound.beep()
                return
            }
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

    func overlayView(_ view: OverlayView, didChangeMagnifierPixelCount count: Int) {
        for view in views {
            view.setMagnifierPixelCount(count)
        }
        onMagnifierPixelCountChange?(count)
    }

    func overlayViewMouseEntered(_ view: OverlayView) {
        // Don't change the key window during a drag; the selection stays on the screen where it started.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        makeKey(view)
    }
}
