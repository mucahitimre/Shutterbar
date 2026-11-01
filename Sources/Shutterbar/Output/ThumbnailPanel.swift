import AppKit

/// Floating capture thumbnail in the bottom-right corner, like macOS's screenshot preview.
/// Click: edit · drag: drop the file/image into another app · swipe right: dismiss · right-click: more.
@MainActor
final class ThumbnailPanel: NSPanel {
    struct Actions {
        var edit: () -> Void
        var showInFinder: (() -> Void)?
        var copy: () -> Void
    }

    private static let maxSize = CGSize(width: 220, height: 150)
    private static let lifetime: TimeInterval = 5

    private let thumbnail: ThumbnailView
    private var dismissWork: DispatchWorkItem?
    private var onClose: (() -> Void)?

    init(image: CGImage, fileURL: URL?, actions: Actions) {
        let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
        var size = Self.maxSize
        if aspect > size.width / size.height { size.height = size.width / aspect } else { size.width = size.height * aspect }
        size = CGSize(width: max(size.width.rounded(), 60), height: max(size.height.rounded(), 40))

        thumbnail = ThumbnailView(image: image, fileURL: fileURL, actions: actions)
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = thumbnail
        thumbnail.dismiss = { [weak self] in self?.dismiss() }
        thumbnail.hoverChanged = { [weak self] hovering in
            hovering ? self?.dismissWork?.cancel() : self?.scheduleDismiss()
        }
    }

    override var canBecomeKey: Bool { false }

    func present(on screen: NSScreen, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let visible = screen.visibleFrame
        let target = CGPoint(x: visible.maxX - frame.width - 20, y: visible.minY + 20)
        setFrameOrigin(Motion.reduced ? target : CGPoint(x: visible.maxX + 10, y: target.y))
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.duration(0.25)
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrameOrigin(target)
        }
        scheduleDismiss()
    }

    func dismiss() {
        dismissWork?.cancel()
        guard isVisible else { return }
        let end = CGPoint(x: (screen?.visibleFrame.maxX ?? frame.maxX) + 10, y: frame.minY)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.duration(0.2)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if Motion.reduced { animator().alphaValue = 0 } else { animator().setFrameOrigin(end) }
        } completionHandler: {
            MainActor.assumeIsolated {
                self.orderOut(nil)
                self.onClose?()
                self.onClose = nil
            }
        }
    }

    private func scheduleDismiss() {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime, execute: work)
    }
}

private final class ThumbnailView: NSView, NSDraggingSource {
    var dismiss: (() -> Void)?
    var hoverChanged: ((Bool) -> Void)?

    private let image: CGImage
    private let fileURL: URL?
    private let actions: ThumbnailPanel.Actions
    private var mouseDownPoint: CGPoint?
    private var dragged = false
    private var scrollX: CGFloat = 0

    init(image: CGImage, fileURL: URL?, actions: ThumbnailPanel.Actions) {
        self.image = image
        self.fileURL = fileURL
        self.actions = actions
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.black.withAlphaComponent(0.25).cgColor
        layer?.contents = image
        layer?.contentsGravity = .resizeAspectFill
        toolTip = "Click to edit, drag to share, swipe right to dismiss"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Screenshot thumbnail")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { hoverChanged?(false) }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragged, let start = mouseDownPoint else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
        dragged = true
        let writer: NSPasteboardWriting = fileURL.map { $0 as NSURL } ?? NSImage(cgImage: image, size: .zero)
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(bounds, contents: NSImage(cgImage: image, size: bounds.size))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        guard !dragged else { return }
        dismiss?()
        actions.edit()
    }

    /// Two-finger swipe to the right dismisses, as in macOS.
    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }
        scrollX += event.scrollingDeltaX
        if scrollX > 40 { scrollX = 0; dismiss?() }
        if event.phase == .ended { scrollX = 0 }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem("Edit") { [weak self] in self?.dismiss?(); self?.actions.edit() })
        if let showInFinder = actions.showInFinder {
            menu.addItem(ActionMenuItem("Show in Finder") { [weak self] in self?.dismiss?(); showInFinder() })
        }
        menu.addItem(ActionMenuItem("Copy") { [weak self] in self?.actions.copy() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Close") { [weak self] in self?.dismiss?() })
        return menu
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] { dismiss?() }
    }
}
