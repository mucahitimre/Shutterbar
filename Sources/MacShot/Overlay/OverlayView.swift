import AppKit
import Carbon.HIToolbox
import MacShotCore

@MainActor
protocol OverlayViewDelegate: AnyObject {
    func overlayView(_ view: OverlayView, didProduce output: SelectionStateMachine.Output)
    func overlayViewDidBeginSelection(_ view: OverlayView)
    func overlayViewMouseEntered(_ view: OverlayView)
}

/// Donmuş kareyi gösterir, seçim dışını karartır, seçim çerçevesini ve etiketleri çizer.
/// Görünüm flipped: koordinatları doğrudan display-local point.
final class OverlayView: NSView {
    weak var delegate: OverlayViewDelegate?
    let snapshot: DisplaySnapshot
    private(set) var machine: SelectionStateMachine

    private let imageView = PassthroughImageView()
    private let dimLayer = CAShapeLayer()
    private let previewLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let dashLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let sizeLabel = OverlayView.makeLabel()
    private let cursorLabel = OverlayView.makeLabel()

    init(snapshot: DisplaySnapshot, quickCapture: Bool, preview: CGRect?) {
        self.snapshot = snapshot
        self.machine = SelectionStateMachine(
            bounds: snapshot.frame.size,
            pixelScale: snapshot.scale,
            quickCapture: quickCapture,
            preview: preview
        )
        super.init(frame: CGRect(origin: .zero, size: snapshot.frame.size))
        wantsLayer = true

        imageView.image = NSImage(cgImage: snapshot.image, size: snapshot.frame.size)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.4).cgColor

        previewLayer.fillColor = nil
        previewLayer.strokeColor = NSColor.white.withAlphaComponent(0.4).cgColor
        previewLayer.lineWidth = 1
        previewLayer.lineDashPattern = [6, 4]

        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.lineWidth = 1

        dashLayer.fillColor = nil
        dashLayer.strokeColor = NSColor.black.withAlphaComponent(0.8).cgColor
        dashLayer.lineWidth = 1
        dashLayer.lineDashPattern = [4, 4]

        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.strokeColor = NSColor.black.withAlphaComponent(0.6).cgColor
        handlesLayer.lineWidth = 1

        let overlay = ShapeHostView(frame: bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        for sublayer in [dimLayer, previewLayer, borderLayer, dashLayer, handlesLayer] {
            sublayer.frame = bounds
            sublayer.actions = ["path": NSNull(), "hidden": NSNull()]
            overlay.layer?.addSublayer(sublayer)
        }
        addSubview(overlay)
        addSubview(sizeLabel)
        addSubview(cursorLabel)

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
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    // MARK: Dışarıdan

    func resetSelection() {
        machine.reset()
        refresh()
    }

    func updateCursor(fromGlobal location: CGPoint) {
        machine.mouseMoved(to: CaptureGeometry.toDisplayLocal(location, displayFrame: snapshot.frame))
        refresh()
    }

    // MARK: Fare

    override func mouseEntered(with event: NSEvent) {
        delegate?.overlayViewMouseEntered(self)
        NSCursor.crosshair.set()
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

    override func rightMouseDown(with event: NSEvent) {
        emit(machine.rightMouseDown())
    }

    override func flagsChanged(with event: NSEvent) {
        machine.modifiersChanged(modifiers(of: event))
        refresh()
    }

    // MARK: Klavye

    override func keyDown(with event: NSEvent) {
        guard let key = Self.key(for: event) else {
            super.keyDown(with: event)
            return
        }
        let output = machine.key(key, modifiers: modifiers(of: event))
        refresh()
        emit(output)
    }

    static func key(for event: NSEvent) -> SelectionStateMachine.Key? {
        switch Int(event.keyCode) {
        case kVK_Escape: return .escape
        case kVK_Return, kVK_ANSI_KeypadEnter: return .enter
        case kVK_Delete, kVK_ForwardDelete: return .delete
        case kVK_Space: return .space
        // ~ / ` : ANSI'de Grave, ISO klavyelerde (TR dahil) sol üst tuş Section olarak gelebilir.
        case kVK_ANSI_Grave, kVK_ISO_Section: return .activeScreen
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

    // MARK: Yardımcılar

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

        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let selection = machine.selection {
            dim.addRect(selection)
        }
        dimLayer.path = dim

        if let preview = machine.preview {
            previewLayer.path = CGPath(rect: preview.insetBy(dx: 0.5, dy: 0.5), transform: nil)
            previewLayer.isHidden = false
        } else {
            previewLayer.isHidden = true
        }

        if let selection = machine.selection, selection.width >= 1, selection.height >= 1 {
            borderLayer.path = CGPath(rect: selection.insetBy(dx: -0.5, dy: -0.5), transform: nil)
            dashLayer.path = CGPath(rect: selection.insetBy(dx: 0.5, dy: 0.5), transform: nil)
            borderLayer.isHidden = false
            dashLayer.isHidden = false

            let showHandles = !machine.quickCapture && machine.phase == .idle
            if showHandles {
                let handles = CGMutablePath()
                for handle in SelectionStateMachine.Handle.allCases {
                    let p = SelectionStateMachine.handlePoint(handle, of: selection)
                    handles.addRect(CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
                }
                handlesLayer.path = handles
            }
            handlesLayer.isHidden = !showHandles

            let px = CaptureGeometry.pixelRect(
                forPointRect: selection,
                scale: snapshot.scale,
                imageWidth: snapshot.image.width,
                imageHeight: snapshot.image.height
            ) ?? .zero
            sizeLabel.stringValue = "\(Int(px.width)) × \(Int(px.height))"
            sizeLabel.sizeToFit()
            var origin = CGPoint(x: selection.minX, y: selection.maxY + 6)
            if origin.y + sizeLabel.frame.height > bounds.height {
                origin.y = selection.minY - sizeLabel.frame.height - 6
            }
            if origin.y < 0 { origin.y = selection.minY + 6; origin.x = selection.minX + 6 }
            origin.x = min(max(origin.x, 0), bounds.width - sizeLabel.frame.width)
            sizeLabel.setFrameOrigin(origin)
            sizeLabel.isHidden = false
        } else {
            borderLayer.isHidden = true
            dashLayer.isHidden = true
            handlesLayer.isHidden = true
            sizeLabel.isHidden = true
        }

        let cursor = machine.cursor
        cursorLabel.stringValue = "\(Int(floor(cursor.x * snapshot.scale))), \(Int(floor(cursor.y * snapshot.scale)))"
        cursorLabel.sizeToFit()
        var labelOrigin = CGPoint(x: cursor.x + 16, y: cursor.y + 16)
        if labelOrigin.x + cursorLabel.frame.width > bounds.width { labelOrigin.x = cursor.x - 16 - cursorLabel.frame.width }
        if labelOrigin.y + cursorLabel.frame.height > bounds.height { labelOrigin.y = cursor.y - 16 - cursorLabel.frame.height }
        cursorLabel.setFrameOrigin(labelOrigin)
        cursorLabel.isHidden = false
    }

    private static func makeLabel() -> NSTextField {
        let label = PaddedLabel(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        label.layer?.cornerRadius = 4
        label.isHidden = true
        return label
    }
}

/// Şekil katmanlarını taşır; flipped olduğu için katman koordinatları display-local ile aynı.
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
        return NSSize(width: size.width + 10, height: size.height + 4)
    }

    override func sizeToFit() {
        setFrameSize(intrinsicContentSize)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        // Metni dolgu içinde ortala.
        let text = attributedStringValue
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
