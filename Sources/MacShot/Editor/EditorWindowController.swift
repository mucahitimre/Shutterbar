import AppKit
import MacShotCore
import SwiftUI

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
    private let canvas: EditorCanvasView
    private let window: NSWindow
    private var continuation: CheckedContinuation<Result, Never>?

    init(image: CGImage) {
        canvas = EditorCanvasView(image: image, model: model)
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()

        let toolbar = NSHostingView(rootView: EditorToolbar(
            model: model,
            onCopy: { [weak self] in self?.finish(copy: true) },
            onDone: { [weak self] in self?.finish(copy: false) }
        ))
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.delegate = self

        let content = NSView()
        content.addSubview(toolbar)
        content.addSubview(canvas)
        let aspect = CGFloat(image.height) / CGFloat(max(image.width, 1))
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            canvas.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor),
            canvas.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            canvas.heightAnchor.constraint(equalTo: canvas.widthAnchor, multiplier: aspect),
            // Don't scale above 100%: small captures should not get blurry.
            canvas.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(image.width) / (NSScreen.main?.backingScaleFactor ?? 2)),
        ])
        // As the window grows, the canvas grows while keeping its aspect ratio. The priority is below the window's
        // size-keeping priority (500): the canvas does not grow the window, it fits the window.
        let fill = NSLayoutConstraint.Priority(rawValue: NSLayoutConstraint.Priority.windowSizeStayPut.rawValue - 10)
        let fillWidth = canvas.widthAnchor.constraint(equalTo: content.widthAnchor)
        fillWidth.priority = fill
        let fillHeight = canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        fillHeight.priority = fill
        NSLayoutConstraint.activate([fillWidth, fillHeight])

        window.contentView = content
        window.title = "\(AppInfo.name) — Annotate"
        window.delegate = self
        window.isReleasedWhenClosed = false
        let toolbarSize = toolbar.fittingSize
        window.setContentSize(Self.initialSize(for: image, toolbar: toolbarSize))
        window.contentMinSize = CGSize(width: toolbarSize.width, height: toolbarSize.height + 160)
        window.center()
    }

    /// Shows the image at 100% (at screen scale); scales it down if it doesn't fit in 85% of the screen.
    private static func initialSize(for image: CGImage, toolbar: CGSize) -> CGSize {
        let toolbarHeight = toolbar.height
        let screen = NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2
        let visible = screen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        var size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let limit = CGSize(width: visible.width * 0.85, height: visible.height * 0.85 - toolbarHeight)
        let fit = min(1, limit.width / size.width, limit.height / size.height)
        size = CGSize(width: size.width * fit, height: size.height * fit)
        // For an image narrower than the toolbar, the canvas is centered and the height follows the aspect ratio.
        return CGSize(width: max(size.width, toolbar.width), height: size.height + toolbarHeight)
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

private struct EditorToolbar: View {
    @ObservedObject var model: EditorModel
    let onCopy: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Picker("Tool", selection: $model.tool) {
                ForEach(EditorModel.Tool.allCases) { tool in
                    Label(tool.title, systemImage: tool.symbol)
                        .labelStyle(.iconOnly)
                        .help("\(tool.title) (\(String(tool.key).uppercased()))")
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            HStack(spacing: 4) {
                ForEach(EditorModel.palette, id: \.self) { color in
                    Button {
                        model.color = color
                    } label: {
                        Circle()
                            .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                            .overlay(Circle().stroke(Color.primary.opacity(model.color == color ? 0.9 : 0.25),
                                                     lineWidth: model.color == color ? 2 : 1))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker("Width", selection: $model.width) {
                ForEach(EditorModel.Width.allCases) { width in
                    Text(width.title).tag(width)
                }
            }
            .labelsHidden()
            .fixedSize()

            Spacer()

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.document.canUndo)
                .help("Undo (⌘Z)")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.document.canRedo)
                .help("Redo (⇧⌘Z)")
            Button("Clear") { model.clear() }
                .disabled(!model.document.canUndo)
            Button("Copy", action: onCopy)
                .help("Copy to clipboard only (⌘C)")
            Button("Done", action: onDone)
                .keyboardShortcut(.defaultAction)
                .help("Run after-capture tasks (Enter / ⌘S)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
