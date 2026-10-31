import AppKit
import Combine
import MacShotCore

/// Opens the captured image for annotation; returns the result asynchronously.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate, EditorCanvasDelegate {
    enum Result {
        /// Done: the selected after-capture tasks run with the edited image.
        case done(CGImage)
        /// ⌘C / Copy: clipboard only.
        case copyOnly(CGImage)
        case cancelled
    }

    private let model = EditorModel()
    private var observation: AnyCancellable?
    private weak var toolGroup: NSToolbarItemGroup?
    private weak var colorItem: NSMenuToolbarItem?
    private weak var widthItem: NSMenuToolbarItem?
    private let canvas: EditorCanvasView
    private let window: NSWindow
    private var continuation: CheckedContinuation<Result, Never>?

    init(image: CGImage) {
        canvas = EditorCanvasView(image: image, model: model)
        // Created at its final size: a zero-sized window makes the unified toolbar's title layout conflict.
        window = NSWindow(contentRect: CGRect(origin: .zero, size: Self.initialSize(for: image, margin: 20)),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.delegate = self
        canvas.wantsLayer = true
        canvas.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = CGSize(width: 0, height: -1)
            return shadow
        }()

        // Like Preview: the image sits on the under-page background with some breathing room.
        let content = UnderPageView()
        content.addSubview(canvas)
        let aspect = CGFloat(image.height) / CGFloat(max(image.width, 1))
        let margin: CGFloat = 20
        NSLayoutConstraint.activate([
            canvas.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            canvas.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            canvas.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: margin),
            canvas.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: margin),
            canvas.heightAnchor.constraint(equalTo: canvas.widthAnchor, multiplier: aspect),
            // Don't scale above 100%: small captures should not get blurry.
            canvas.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(image.width) / (NSScreen.main?.backingScaleFactor ?? 2)),
        ])
        // As the window grows, the canvas grows while keeping its aspect ratio. The priority is below the window's
        // size-keeping priority (500): the canvas does not grow the window, it fits the window.
        let fill = NSLayoutConstraint.Priority(rawValue: NSLayoutConstraint.Priority.windowSizeStayPut.rawValue - 10)
        let fillWidth = canvas.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -margin * 2)
        fillWidth.priority = fill
        let fillHeight = canvas.heightAnchor.constraint(equalTo: content.heightAnchor, constant: -margin * 2)
        fillHeight.priority = fill
        NSLayoutConstraint.activate([fillWidth, fillHeight])

        window.contentView = content
        window.title = "\(AppInfo.name) — Annotate"
        window.subtitle = "\(image.width) × \(image.height)"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        let toolbar = NSToolbar(identifier: "EditorToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.delegate = self
        window.toolbar = toolbar
        window.contentMinSize = CGSize(width: 640, height: 320)
        window.center()

        observation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.syncToolbar() }
        }
    }

    /// Shows the image at 100% (at screen scale); scales it down if it doesn't fit in 85% of the screen.
    private static func initialSize(for image: CGImage, margin: CGFloat) -> CGSize {
        let screen = NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2
        let visible = screen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        var size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let limit = CGSize(width: visible.width * 0.85 - margin * 2, height: visible.height * 0.8 - margin * 2)
        let fit = min(1, limit.width / size.width, limit.height / size.height)
        size = CGSize(width: size.width * fit, height: size.height * fit)
        // For an image narrower than the toolbar, the canvas is centered and the height follows the aspect ratio.
        return CGSize(width: max(size.width + margin * 2, 640), height: max(size.height + margin * 2, 320))
    }

    func run() async -> Result {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(canvas)
        }
    }

    #if DEBUG
    /// Self-test: adds one mark per tool, writes the window contents to `url`, then Done.
    func runSelfTest(snapshotTo url: URL) {
        let w = CGFloat(canvas.image.width), h = CGFloat(canvas.image.height)
        model.add(.arrow(from: CGPoint(x: w * 0.1, y: h * 0.1), to: CGPoint(x: w * 0.4, y: h * 0.35)))
        model.width = .thick
        model.color = .blue
        model.add(.rectangle(CGRect(x: w * 0.5, y: h * 0.3, width: w * 0.3, height: h * 0.3)))
        model.color = .black
        model.width = .medium
        model.add(.text("Hello MacShot", origin: CGPoint(x: w * 0.15, y: h * 0.45)))
        model.add(.pixelate(CGRect(x: w * 0.12, y: h * 0.62, width: w * 0.3, height: h * 0.15)))
        model.color = .red
        model.add(.number(model.document.nextNumber, center: CGPoint(x: w * 0.85, y: h * 0.15)))
        model.add(.number(model.document.nextNumber, center: CGPoint(x: w * 0.9, y: h * 0.15)))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            Log.output.info("Editor self-test image: \(url.path, privacy: .public)")
            finish(copy: false)
        }
    }
    #endif

    private func finish(copy: Bool) {
        canvas.finishEditing()
        guard let rendered = AnnotationRenderer.render(model.document.items, on: canvas.image) else {
            Log.output.error("Could not render annotations")
            close(with: .cancelled)
            return
        }
        close(with: copy ? .copyOnly(rendered) : .done(rendered))
    }

    private func close(with result: Result) {
        guard let continuation else { return }
        self.continuation = nil
        window.orderOut(nil)
        continuation.resume(returning: result)
    }

    // MARK: EditorCanvasDelegate

    func canvasDidRequestDone(_ canvas: EditorCanvasView) { finish(copy: false) }
    func canvasDidRequestCopy(_ canvas: EditorCanvasView) { finish(copy: true) }
    func canvasDidRequestCancel(_ canvas: EditorCanvasView) { close(with: .cancelled) }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        close(with: .cancelled)
    }
}

// MARK: - Native toolbar

private extension NSToolbarItem.Identifier {
    static let tools = Self("tools")
    static let color = Self("color")
    static let width = Self("width")
    static let undo = Self("undo")
    static let redo = Self("redo")
    static let share = Self("share")
    static let copy = Self("copy")
    static let done = Self("done")
}

extension EditorWindowController: NSToolbarDelegate, NSToolbarItemValidation, NSSharingServicePickerToolbarItemDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.tools, .space, .color, .width, .space, .undo, .redo, .flexibleSpace, .share, .copy, .done]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case .tools:
            let tools = EditorModel.Tool.allCases
            let group = NSToolbarItemGroup(
                itemIdentifier: id,
                images: tools.map { Self.symbol($0.symbol, $0.title) },
                selectionMode: .selectOne,
                labels: tools.map(\.title),
                target: self,
                action: #selector(toolChanged(_:))
            )
            group.label = "Tools"
            for (item, tool) in zip(group.subitems, tools) {
                item.toolTip = "\(tool.title) (\(String(tool.key).uppercased()))"
            }
            group.selectedIndex = tools.firstIndex(of: model.tool) ?? 0
            toolGroup = group
            return group
        case .color:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "Color"
            item.toolTip = "Color"
            item.showsIndicator = true
            colorItem = item
            syncColor()
            return item
        case .width:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "Line Width"
            item.toolTip = "Line width"
            item.image = Self.symbol("lineweight", "Line width")
            item.showsIndicator = true
            widthItem = item
            syncWidth()
            return item
        case .undo:
            return button(id, symbol: "arrow.uturn.backward", label: "Undo", help: "Undo (⌘Z)", action: #selector(undo))
        case .redo:
            return button(id, symbol: "arrow.uturn.forward", label: "Redo", help: "Redo (⇧⌘Z)", action: #selector(redo))
        case .share:
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: id)
            item.label = "Share"
            item.toolTip = "Share"
            item.delegate = self
            return item
        case .copy:
            return button(id, symbol: "doc.on.doc", label: "Copy", help: "Copy to clipboard only (⌘C)", action: #selector(copyClicked))
        case .done:
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = "Done"
            let button = NSButton(title: "Done", target: self, action: #selector(doneClicked))
            button.bezelStyle = .push
            button.keyEquivalent = "\r"
            button.toolTip = "Run after-capture tasks (Enter / ⌘S)"
            item.view = button
            return item
        default:
            return nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case .undo: model.document.canUndo
        case .redo: model.document.canRedo
        default: true
        }
    }

    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        canvas.finishEditing()
        guard let rendered = AnnotationRenderer.render(model.document.items, on: canvas.image) else { return [] }
        return [NSImage(cgImage: rendered, size: .zero)]
    }

    // MARK: Actions

    @objc private func toolChanged(_ sender: NSToolbarItemGroup) {
        let tools = EditorModel.Tool.allCases
        guard tools.indices.contains(sender.selectedIndex) else { return }
        model.tool = tools[sender.selectedIndex]
        window.invalidateCursorRects(for: canvas)
        window.makeFirstResponder(canvas)
    }

    @objc private func undo() { model.undo() }
    @objc private func redo() { model.redo() }
    @objc private func copyClicked() { finish(copy: true) }
    @objc private func doneClicked() { finish(copy: false) }

    // MARK: State

    /// Keeps the toolbar in step with keyboard shortcuts and menu choices.
    private func syncToolbar() {
        toolGroup?.selectedIndex = EditorModel.Tool.allCases.firstIndex(of: model.tool) ?? 0
        syncColor()
        syncWidth()
        window.toolbar?.validateVisibleItems()
    }

    private func syncColor() {
        guard let item = colorItem else { return }
        item.image = Self.swatch(model.color, diameter: 16)
        let menu = NSMenu()
        for (color, name) in zip(EditorModel.palette, ["Red", "Yellow", "Green", "Blue", "Black", "White"]) {
            let entry = ActionMenuItem(name, checked: color == model.color) { [weak self] in self?.model.color = color }
            entry.image = Self.swatch(color, diameter: 12)
            menu.addItem(entry)
        }
        item.menu = menu
    }

    private func syncWidth() {
        guard let item = widthItem else { return }
        let menu = NSMenu()
        for width in EditorModel.Width.allCases {
            menu.addItem(ActionMenuItem(width.title, checked: width == model.width) { [weak self] in self?.model.width = width })
        }
        item.menu = menu
    }

    private func button(_ id: NSToolbarItem.Identifier, symbol: String, label: String, help: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.toolTip = help
        item.image = Self.symbol(symbol, label)
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }

    private static func symbol(_ name: String, _ description: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
    }

    private static func swatch(_ color: Annotation.Color, diameter: CGFloat) -> NSImage {
        let image = NSImage(size: CGSize(width: diameter, height: diameter), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha).setFill()
            circle.fill()
            NSColor.separatorColor.setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// Preview-style gray backdrop behind the image.
private final class UnderPageView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
    }
}
