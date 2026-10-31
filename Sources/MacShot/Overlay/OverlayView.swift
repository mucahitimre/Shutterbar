import AppKit
import Carbon.HIToolbox
import MacShotCore

@MainActor
protocol OverlayViewDelegate: AnyObject {
    func overlayView(_ view: OverlayView, didProduce output: SelectionStateMachine.Output)
    func overlayViewDidBeginSelection(_ view: OverlayView)
    func overlayViewMouseEntered(_ view: OverlayView)
    func overlayView(_ view: OverlayView, didChangeMagnifierPixelCount count: Int)
}

/// Shows the frozen frame, dims outside the selection, draws the selection border and labels.
/// The view is flipped: its coordinates are display-local points directly.
final class OverlayView: NSView {
    weak var delegate: OverlayViewDelegate?
    let snapshot: DisplaySnapshot
    private(set) var machine: SelectionStateMachine

    private let imageView = PassthroughImageView()
    private let dimLayer = CAShapeLayer()
    private let tintLayer = CAShapeLayer()
    private let previewLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let sizeLabel = OverlayView.makeLabel()
    private let cursorLabel = OverlayView.makeLabel()
    private let hud = HUDView()
    private let magnifier: MagnifierView?
    private var magnifierEnabled = true
    private var scrollAccumulator: CGFloat = 0

    init(snapshot: DisplaySnapshot, quickCapture: Bool, magnifierPixelCount: Int?, preview: CGRect?) {
        self.snapshot = snapshot
        self.machine = SelectionStateMachine(
            bounds: snapshot.frame.size,
            pixelScale: snapshot.scale,
            quickCapture: quickCapture,
            preview: preview
        )
        magnifier = magnifierPixelCount.map { MagnifierView(image: snapshot.image, pixelCount: $0) }
        super.init(frame: CGRect(origin: .zero, size: snapshot.frame.size))
        wantsLayer = true

        imageView.image = NSImage(cgImage: snapshot.image, size: snapshot.frame.size)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)

        // Styling follows macOS's own screenshot UI: no dimming until there is a selection, a thin white
        // border with a soft shadow, round handles, and an accent-colored tint for windows / screens.
        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.35).cgColor

        tintLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
        tintLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        tintLayer.lineWidth = 2

        previewLayer.fillColor = nil
        previewLayer.strokeColor = NSColor.white.withAlphaComponent(0.7).cgColor
        previewLayer.lineWidth = 1
        previewLayer.lineDashPattern = [5, 4]

        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.lineWidth = 1
        borderLayer.shadowColor = NSColor.black.cgColor
        borderLayer.shadowOpacity = 0.45
        borderLayer.shadowRadius = 1.5
        borderLayer.shadowOffset = .zero

        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.strokeColor = NSColor.black.withAlphaComponent(0.25).cgColor
        handlesLayer.lineWidth = 0.5
        handlesLayer.shadowColor = NSColor.black.cgColor
        handlesLayer.shadowOpacity = 0.35
        handlesLayer.shadowRadius = 1.5
        handlesLayer.shadowOffset = CGSize(width: 0, height: 0.5)

        let overlay = ShapeHostView(frame: bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        for sublayer in [dimLayer, tintLayer, previewLayer, borderLayer, handlesLayer] {
            sublayer.frame = bounds
            sublayer.actions = ["path": NSNull(), "hidden": NSNull()]
            overlay.layer?.addSublayer(sublayer)
        }
        addSubview(overlay)
        addSubview(sizeLabel)
        if let magnifier { addSubview(magnifier) }
        addSubview(cursorLabel)
        addSubview(hud)

        updateTrackingAreas()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self
        ))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: currentCursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        currentCursor.set()
    }

    /// Camera for window / screen mode (as in macOS), crosshair for selections.
    private var currentCursor: NSCursor {
        machine.mode == .selection ? .crosshair : .camera
    }

    // MARK: External

    func resetSelection() {
        machine.reset()
        refresh()
    }

    /// Short-lived info text at the top center of the screen (R3.4).
    func showHUD(_ text: String, duration: TimeInterval = 2.5) {
        hud.show(text, in: bounds, duration: duration)
    }

    /// Mode and live preference changes from the capture toolbar.
    func apply(mode: CaptureMode, quickCapture: Bool, snapsWindows: Bool, showsMagnifier: Bool) {
        machine.mode = mode
        machine.quickCapture = quickCapture
        machine.snapsWindowsInSelection = snapsWindows
        magnifierEnabled = showsMagnifier
        window?.invalidateCursorRects(for: self)
        currentCursor.set()
        refresh()
    }

    /// The toolbar's Capture button: same as Enter.
    func performCapture() {
        let output = machine.key(.enter)
        refresh()
        emit(output)
    }

    func setWindowRects(_ rects: [CGRect]) {
        machine.windowRects = rects
        refresh()
    }

    func setMagnifierPixelCount(_ count: Int) {
        magnifier?.setPixelCount(count)
        refresh()
    }

    func updateCursor(fromGlobal location: CGPoint) {
        machine.mouseMoved(to: CaptureGeometry.toDisplayLocal(location, displayFrame: snapshot.frame))
        refresh()
    }

    // MARK: Mouse

    override func mouseEntered(with event: NSEvent) {
        delegate?.overlayViewMouseEntered(self)
        currentCursor.set()
    }

    override func mouseMoved(with event: NSEvent) {
        machine.mouseMoved(to: location(of: event))
        refresh()
    }

    override func mouseDown(with event: NSEvent) {
        let output = machine.mouseDown(at: location(of: event), clickCount: event.clickCount, modifiers: modifiers(of: event))
        if case .drawing = machine.phase {
            delegate?.overlayViewDidBeginSelection(self)
        }
        refresh()
        emit(output)
    }

    override func mouseDragged(with event: NSEvent) {
        machine.mouseDragged(to: location(of: event), modifiers: modifiers(of: event))
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        let output = machine.mouseUp(at: location(of: event))
        refresh()
        emit(output)
    }

    /// Mouse wheel: magnifier size (up enlarges). Kept in sync across screens.
    override func scrollWheel(with event: NSEvent) {
        guard let magnifier, event.scrollingDeltaY != 0 else { return }
        // A trackpad produces many events per gesture; count one step once the delta accumulates.
        if event.hasPreciseScrollingDeltas {
            scrollAccumulator += event.scrollingDeltaY
            guard abs(scrollAccumulator) >= 12 else { return }
        } else {
            scrollAccumulator = event.scrollingDeltaY
        }
        let step = scrollAccumulator > 0 ? 2 : -2
        scrollAccumulator = 0
        let count = MagnifierView.normalized(magnifier.pixelCount + step)
        guard count != magnifier.pixelCount else { return }
        delegate?.overlayView(self, didChangeMagnifierPixelCount: count)
    }

    override func rightMouseDown(with event: NSEvent) {
        emit(machine.rightMouseDown())
    }

    override func flagsChanged(with event: NSEvent) {
        machine.modifiersChanged(modifiers(of: event))
        refresh()
    }

    // MARK: Keyboard

    /// ⌘ combinations arrive here before keyDown.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard Self.isCopy(event) else { return super.performKeyEquivalent(with: event) }
        emit(machine.key(.copy))
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard let key = Self.key(for: event) else {
            super.keyDown(with: event)
            return
        }
        let output = machine.key(key, modifiers: modifiers(of: event))
        refresh()
        emit(output)
    }

    static func isCopy(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else { return false }
        return event.keyCode == kVK_ANSI_C || event.charactersIgnoringModifiers?.lowercased() == "c"
    }

    static func key(for event: NSEvent) -> SelectionStateMachine.Key? {
        if isCopy(event) { return .copy }
        switch Int(event.keyCode) {
        case kVK_Escape: return .escape
        case kVK_Return, kVK_ANSI_KeypadEnter: return .enter
        case kVK_Delete, kVK_ForwardDelete: return .delete
        case kVK_Space: return .space
        // ~ / ` : Grave on ANSI; on ISO keyboards (including Turkish) the top-left key may arrive as Section.
        case kVK_ANSI_Grave, kVK_ISO_Section: return .activeScreen
        case kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
             kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0:
            let flags = event.modifierFlags.intersection([.command, .control, .option])
            guard flags.isEmpty else { return nil }
            return .screen(screenIndex(forDigitKey: Int(event.keyCode)))
        case kVK_LeftArrow: return .arrow(dx: -1, dy: 0)
        case kVK_RightArrow: return .arrow(dx: 1, dy: 0)
        case kVK_UpArrow: return .arrow(dx: 0, dy: -1)
        case kVK_DownArrow: return .arrow(dx: 0, dy: 1)
        default:
            if let chars = event.charactersIgnoringModifiers, chars == "~" || chars == "`" {
                return .activeScreen
            }
            return nil
        }
    }

    // MARK: Helpers

    /// 1 → 0, …, 9 → 8, 0 → 9 (keyCodes are not sequential).
    private static func screenIndex(forDigitKey keyCode: Int) -> Int {
        let order = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                     kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0]
        return order.firstIndex(of: keyCode) ?? -1
    }

    private func emit(_ output: SelectionStateMachine.Output) {
        guard output != .none else { return }
        delegate?.overlayView(self, didProduce: output)
    }

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func modifiers(of event: NSEvent) -> SelectionStateMachine.Modifiers {
        var result: SelectionStateMachine.Modifiers = []
        if event.modifierFlags.contains(.shift) { result.insert(.shift) }
        if event.modifierFlags.contains(.option) { result.insert(.move) }
        return result
    }

    private func refresh() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Without a selection, the window (or screen) a click would capture gets an accent tint.
        let hovered = machine.selection == nil ? machine.hoveredWindow : nil
        let selection = machine.selection.flatMap { $0.width >= 1 && $0.height >= 1 ? $0 : nil }

        if let hovered {
            let inset = hovered.size == bounds.size ? 1 : 0
            tintLayer.path = CGPath(rect: hovered.insetBy(dx: CGFloat(inset), dy: CGFloat(inset)), transform: nil)
            tintLayer.isHidden = false
        } else {
            tintLayer.isHidden = true
        }

        // Dim outside the selection (or the last-region preview); no dimming otherwise.
        if let cutout = selection ?? machine.preview {
            let dim = CGMutablePath()
            dim.addRect(bounds)
            dim.addRect(cutout)
            dimLayer.path = dim
            dimLayer.isHidden = false
        } else {
            dimLayer.isHidden = true
        }

        if let preview = machine.preview, selection == nil {
            previewLayer.path = CGPath(rect: preview.insetBy(dx: 0.5, dy: 0.5), transform: nil)
            previewLayer.isHidden = false
        } else {
            previewLayer.isHidden = true
        }

        if let selection {
            borderLayer.path = CGPath(rect: selection.insetBy(dx: -0.5, dy: -0.5), transform: nil)
            borderLayer.isHidden = false

            let showHandles = !machine.quickCapture && machine.phase == .idle && machine.mode == .selection
            if showHandles {
                let handles = CGMutablePath()
                for handle in SelectionStateMachine.Handle.allCases {
                    let p = SelectionStateMachine.handlePoint(handle, of: selection)
                    handles.addEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                }
                handlesLayer.path = handles
            }
            handlesLayer.isHidden = !showHandles
        } else {
            borderLayer.isHidden = true
            handlesLayer.isHidden = true
        }

        // Pixel size below the selection, centered (above it when there is no room).
        if let measured = selection ?? hovered, machine.mode == .selection || hovered != nil {
            let px = CaptureGeometry.pixelRect(
                forPointRect: measured,
                scale: snapshot.scale,
                imageWidth: snapshot.image.width,
                imageHeight: snapshot.image.height
            ) ?? .zero
            sizeLabel.stringValue = "\(Int(px.width)) × \(Int(px.height))"
            sizeLabel.sizeToFit()
            let size = sizeLabel.frame.size
            var origin = CGPoint(x: measured.midX - size.width / 2, y: measured.maxY + 8)
            if origin.y + size.height > bounds.height - 4 { origin.y = measured.minY - size.height - 8 }
            if origin.y < 4 { origin.y = measured.maxY - size.height - 8 }
            origin.x = min(max(origin.x, 4), bounds.width - size.width - 4)
            sizeLabel.setFrameOrigin(origin)
            sizeLabel.isHidden = false
        } else {
            sizeLabel.isHidden = true
        }

        let cursor = machine.cursor
        let pixel = CGPoint(x: floor(cursor.x * snapshot.scale), y: floor(cursor.y * snapshot.scale))
        cursorLabel.stringValue = "\(Int(pixel.x)), \(Int(pixel.y))"
        cursorLabel.sizeToFit()

        // Magnifier at the cursor's bottom-right with coordinates below it; flip left / up if it doesn't fit.
        let gap: CGFloat = 16
        let magnifierSize = magnifier.map { CGSize(width: $0.side, height: $0.side + 4) } ?? .zero
        let block = CGSize(
            width: max(magnifierSize.width, cursorLabel.frame.width),
            height: magnifierSize.height + cursorLabel.frame.height
        )
        var origin = CGPoint(x: cursor.x + gap, y: cursor.y + gap)
        if origin.x + block.width > bounds.width { origin.x = cursor.x - gap - block.width }
        if origin.y + block.height > bounds.height { origin.y = cursor.y - gap - block.height }
        let showsTools = machine.mode == .selection
        if let magnifier {
            let visible = showsTools && magnifierEnabled
            if visible {
                magnifier.update(pixel: pixel)
                magnifier.setFrameOrigin(origin)
            }
            magnifier.isHidden = !visible
        }
        let magnifierOffset = (magnifierEnabled && magnifier != nil) ? magnifierSize.height : 0
        cursorLabel.setFrameOrigin(CGPoint(x: origin.x, y: origin.y + magnifierOffset))
        cursorLabel.isHidden = !showsTools
    }

    private static func makeLabel(fontSize: CGFloat = 11) -> NSTextField {
        let label = PaddedLabel(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        label.textColor = .white
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        label.layer?.cornerCurve = .continuous
        label.isHidden = true
        return label
    }
}

/// Hosts the shape layers; since it is flipped, layer coordinates match display-local.
private final class ShapeHostView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class PaddedLabel: NSTextField {
    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 16, height: size.height + 6)
    }

    /// Pill shape: fully rounded ends.
    override func sizeToFit() {
        setFrameSize(intrinsicContentSize)
        layer?.cornerRadius = intrinsicContentSize.height / 2
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        // Center the text within the padding.
        let text = attributedStringValue
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
