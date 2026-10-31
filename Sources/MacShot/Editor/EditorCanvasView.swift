import AppKit
import Combine
import MacShotCore

@MainActor
protocol EditorCanvasDelegate: AnyObject {
    func canvasDidRequestDone(_ canvas: EditorCanvasView)
    func canvasDidRequestCopy(_ canvas: EditorCanvasView)
    func canvasDidRequestCancel(_ canvas: EditorCanvasView)
}

/// Görüntüyü pencereye sığdırıp çizer; annotation'lar `AnnotationRenderer` ile aynı yoldan çizilir.
/// Koordinatlar görünümde point, modelde görüntü pikseli (sol-üst orijin).
final class EditorCanvasView: NSView {
    weak var delegate: EditorCanvasDelegate?
    let image: CGImage
    private let model: EditorModel
    private var draft: Annotation?
    private var dragStart: CGPoint?
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero
    private var observation: AnyCancellable?

    init(image: CGImage, model: EditorModel) {
        self.image = image
        self.model = model
        super.init(frame: .zero)
        observation = model.objectWillChange.sink { [weak self] _ in
            // objectWillChange değişiklikten önce gelir; çizimi bir sonraki turda yap.
            DispatchQueue.main.async { self?.needsDisplay = true }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: model.tool == .text ? .iBeam : .crosshair)
    }

    /// Görüntü pikseli / görünüm point'i.
    private var pixelsPerPoint: CGFloat {
        bounds.width > 0 ? CGFloat(image.width) / bounds.width : 1
    }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let scale = pixelsPerPoint
        return CGPoint(
            x: min(max(p.x * scale, 0), CGFloat(image.width)),
            y: min(max(p.y * scale, 0), CGFloat(image.height))
        )
    }

    // MARK: Çizim

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // Flipped görünüm: önce görüntüyü düz çiz, sonra piksel ölçeğine geç.
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: bounds.size))
        context.restoreGState()

        context.saveGState()
        let scale = 1 / pixelsPerPoint
        context.scaleBy(x: scale, y: scale)
        var items = model.document.items
        if let draft { items.append(draft) }
        AnnotationRenderer.draw(items, base: image, in: context)
        context.restoreGState()
    }

    // MARK: Fare

    override func mouseDown(with event: NSEvent) {
        commitText()
        let point = imagePoint(event)
        switch model.tool {
        case .text:
            beginText(at: point)
        case .number:
            model.add(.number(model.document.nextNumber, center: point))
        case .arrow, .rectangle, .pixelate:
            dragStart = point
            draft = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = imagePoint(event)
        let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        let shape: Annotation.Shape? = switch model.tool {
        case .arrow: .arrow(from: start, to: point)
        case .rectangle: .rectangle(rect)
        case .pixelate: .pixelate(rect)
        case .text, .number: nil
        }
        draft = shape.map { Annotation($0, color: model.color, lineWidth: model.width.pixels) }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            draft = nil
            needsDisplay = true
        }
        guard let draft, AnnotationRenderer.bounds(of: draft).width > draft.lineWidth * 2 + 3 else { return }
        model.add(draft.shape)
    }

    // MARK: Metin

    private func beginText(at point: CGPoint) {
        textOrigin = point
        let field = NSTextField(string: "")
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        let fontSize = Annotation(.text("", origin: .zero), lineWidth: model.width.pixels).fontSize / pixelsPerPoint
        field.font = .systemFont(ofSize: fontSize)
        let c = model.color
        field.textColor = NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
        field.placeholderString = "Metin"
        field.target = self
        field.action = #selector(textFieldDidEnd(_:))
        field.sizeToFit()
        field.frame = CGRect(x: point.x / pixelsPerPoint, y: point.y / pixelsPerPoint,
                             width: max(200, field.frame.width), height: field.frame.height)
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    @objc private func textFieldDidEnd(_ sender: NSTextField) {
        commitText()
        window?.makeFirstResponder(self)
    }

    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        if !text.isEmpty {
            model.add(.text(text, origin: textOrigin))
        }
    }

    /// Metin alanı açıkken Esc yalnız metni iptal eder.
    override func cancelOperation(_ sender: Any?) {
        if let field = textField {
            textField = nil
            field.removeFromSuperview()
            window?.makeFirstResponder(self)
            return
        }
        delegate?.canvasDidRequestCancel(self)
    }

    // MARK: Klavye

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard textField == nil else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "z" where flags.contains(.shift): model.redo()
        case "z": model.undo()
        case "c": delegate?.canvasDidRequestCopy(self)
        case "s": delegate?.canvasDidRequestDone(self)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        if flags.isEmpty, let char = event.charactersIgnoringModifiers?.lowercased().first {
            if let tool = EditorModel.Tool.allCases.first(where: { $0.key == char }) {
                model.tool = tool
                window?.invalidateCursorRects(for: self)
                return
            }
        }
        switch event.keyCode {
        case 36, 76: delegate?.canvasDidRequestDone(self) // Return, keypad Enter
        case 53: delegate?.canvasDidRequestCancel(self) // Esc
        default: super.keyDown(with: event)
        }
    }

    /// Bitirmeden önce yazılmakta olan metni belgeye al.
    func finishEditing() {
        commitText()
    }
}
