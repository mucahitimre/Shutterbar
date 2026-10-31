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
    /// Scrolling mode: start a scrolling session for this region (frames are captured live while scrolling).
    case scrolling(DisplaySnapshot, CGRect, CaptureIntent, isWindow: Bool)
    case screens([DisplaySnapshot])
    case cancelled
}

/// Opens an overlay panel for each screen and waits for the user's selection.
@MainActor
final class OverlayController: OverlayViewDelegate {
    private let preferences: Preferences
    private var toolbar: CaptureToolbar?
    private var panels: [OverlayPanel] = []
    private var views: [OverlayView] = []
    private var continuation: CheckedContinuation<OverlayResult, Never>?
    private var previousApp: NSRunningApplication?

    var isPresented: Bool { continuation != nil }

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
    }

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

        applyPreferences()
        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        let active = views.first { $0.snapshot.frame.contains(mouse) } ?? views.first
        if let active {
            makeKey(active)
            active.updateCursor(fromGlobal: mouse)
            if let hud { active.showHUD(hud) }
        }
        CATransaction.flush()

        // The toolbar comes right after the frozen frame is on screen, on the screen under the mouse.
        let toolbar = CaptureToolbar(mode: preferences.captureMode, actions: .init(
            close: { [weak self] in self?.finish(.cancelled) },
            setMode: { [weak self] mode in
                self?.preferences.captureMode = mode
                self?.applyPreferences()
            },
            capture: { [weak self] in self?.activeView?.performCapture() },
            optionsMenu: { [weak self] in self?.makeOptionsMenu() ?? NSMenu() }
        ))
        if let screen = active.flatMap({ view in screens.first { $0.displayID == view.snapshot.displayID } }) ?? NSScreen.main {
            toolbar.present(on: screen)
        }
        self.toolbar = toolbar
    }

    /// The view the toolbar's Capture button acts on: the key overlay, else the one under the mouse.
    private var activeView: OverlayView? {
        views.first { $0.window?.isKeyWindow == true }
            ?? views.first { $0.snapshot.frame.contains(NSEvent.mouseLocation) }
    }

    /// Pushes mode and live options to every screen.
    private func applyPreferences() {
        for view in views {
            view.apply(
                mode: preferences.captureMode,
                quickCapture: preferences.quickCapture,
                snapsWindows: preferences.windowSnap,
                showsMagnifier: preferences.magnifier
            )
        }
    }

    private func makeOptionsMenu() -> NSMenu {
        CaptureOptionsMenu.make(
            preferences: preferences,
            chooseFolder: { [weak self] in self?.chooseFolder() },
            onChange: { [weak self] in self?.applyPreferences() }
        )
    }

    /// The open panel sits below the screen-saver level; lower the overlay while it is up.
    private func chooseFolder() {
        let windows: [NSWindow] = panels + [toolbar].compactMap { $0 }
        let levels = windows.map(\.level)
        windows.forEach { $0.level = .normal }
        let current = SaveFolder.displayURL(bookmark: preferences.saveFolderBookmark)
        if let bookmark = SaveFolder.choose(current: current) {
            preferences.saveFolderBookmark = bookmark
        }
        zip(windows, levels).forEach { $0.level = $1 }
        if let view = activeView { makeKey(view) }
    }

    private func makeKey(_ view: OverlayView) {
        view.window?.makeKey()
        view.window?.makeFirstResponder(view)
    }

    #if DEBUG
    /// Showcase screenshots: close the overlay without a result, and where the toolbar is.
    func dismissForShowcase() { finish(.cancelled) }
    var toolbarFrameForShowcase: CGRect? { toolbar?.frame }
    /// Places the toolbar at the bottom center of `frame` (AppKit global) instead of the screen.
    func moveToolbarForShowcase(into frame: CGRect) {
        guard let toolbar else { return }
        toolbar.setFrameOrigin(CGPoint(x: frame.midX - toolbar.frame.width / 2, y: frame.minY + 40))
    }
    #endif

    private func finish(_ result: OverlayResult) {
        guard let continuation else { return }
        self.continuation = nil
        // Fade out quickly; the frozen frame is already captured, so this costs nothing.
        let closing: [NSWindow] = panels + [toolbar].compactMap { $0 }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.duration(0.12)
            closing.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated {
                closing.forEach { window in
                    window.orderOut(nil)
                    window.contentView = nil
                }
            }
        }
        panels.removeAll()
        views.removeAll()
        toolbar = nil
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
            finish(regionResult(view, rect, .afterCapture))
        case .copy(let rect):
            finish(regionResult(view, rect, .clipboardOnly))
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

    private func regionResult(_ view: OverlayView, _ rect: CGRect, _ intent: CaptureIntent) -> OverlayResult {
        let isWindow = view.machine.selectionIsWindow
        return view.machine.mode == .scrolling
            ? .scrolling(view.snapshot, rect, intent, isWindow: isWindow)
            : .region(view.snapshot, rect, intent, isWindow: isWindow)
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
        preferences.magnifierPixelCount = count
    }

    func overlayViewMouseEntered(_ view: OverlayView) {
        // Don't change the key window during a drag; the selection stays on the screen where it started.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        makeKey(view)
    }
}
