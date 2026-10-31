import AppKit
import MacShotCore

/// Scrolling capture: while the user scrolls inside the selected region, frames are captured and stitched.
/// A click-through frame marks the region; a HUD below it shows progress with Cancel / Done.
/// Our own windows are excluded from capture, so neither appears in the result.
@MainActor
final class ScrollingSession {
    enum Result {
        case done(CGImage)
        case cancelled
    }

    private static let frameInterval: Duration = .milliseconds(100)

    private let displayID: CGDirectDisplayID
    private let rect: CGRect
    private let globalRect: CGRect
    private let frameWindow: RegionFrameWindow
    private let hud: ScrollingHUD
    private var finishRequested: Bool?

    /// - Parameters:
    ///   - rect: display-local, top-left origin, points.
    ///   - displayFrame: the display's AppKit frame.
    init(displayID: CGDirectDisplayID, rect: CGRect, displayFrame: CGRect) {
        self.displayID = displayID
        self.rect = rect
        globalRect = CaptureGeometry.toGlobal(rect, displayFrame: displayFrame)
        frameWindow = RegionFrameWindow(around: globalRect)
        hud = ScrollingHUD()
        hud.onCancel = { [weak self] in self?.finishRequested = false }
        hud.onDone = { [weak self] in self?.finishRequested = true }
        hud.place(near: globalRect, within: displayFrame)
    }

    func run() async throws -> Result {
        let capturer = try await RegionCapturer(displayID: displayID, rect: rect)
        var stitch = ScrollingCapture(excludedTrailingColumns: Int((16 * capturer.pixelScale).rounded()))

        frameWindow.orderFrontRegardless()
        hud.orderFrontRegardless()
        defer {
            frameWindow.orderOut(nil)
            hud.orderOut(nil)
        }

        while finishRequested == nil {
            let frame = try await capturer.capture()
            switch stitch.add(frame) {
            case .first:
                hud.update(status: "Scroll down slowly inside the frame", height: stitch.height)
            case .appended:
                hud.update(status: "Capturing — keep scrolling, then click Done", height: stitch.height)
            case .unchanged:
                break
            case .lost:
                hud.update(status: "Scrolled too far at once — scroll back up a little", height: stitch.height, warning: true)
            case .full:
                hud.update(status: "Maximum height reached", height: stitch.height)
                finishRequested = true
            }
            try? await Task.sleep(for: Self.frameInterval)
        }

        guard finishRequested == true, let image = stitch.makeImage() else { return .cancelled }
        Log.capture.info("Scrolling capture: \(image.width)×\(image.height) px")
        return .done(image)
    }
}

/// Dashed accent outline around the region; ignores the mouse so scrolling reaches the app below.
private final class RegionFrameWindow: NSPanel {
    init(around rect: CGRect) {
        let inset: CGFloat = -3
        super.init(contentRect: rect.insetBy(dx: inset, dy: inset), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        let outline = OutlineView(frame: CGRect(origin: .zero, size: frame.size))
        outline.autoresizingMask = [.width, .height]
        contentView = outline
    }

    override var canBecomeKey: Bool { false }

    private final class OutlineView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
            path.lineWidth = 2
            path.setLineDash([8, 5], count: 2, phase: 0)
            NSColor.controlAccentColor.setStroke()
            path.stroke()
        }
    }
}

/// Progress HUD: status line, stitched height, Cancel / Done. Dark like the capture toolbar.
private final class ScrollingHUD: NSPanel {
    var onCancel: (() -> Void)?
    var onDone: (() -> Void)?

    private let icon = NSImageView()
    private let status = NSTextField(labelWithString: "Starting…")
    private let height = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        appearance = NSAppearance(named: .darkAqua)

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.cornerCurve = .continuous

        icon.image = NSImage(systemSymbolName: "scroll", accessibilityDescription: "Scrolling capture")?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
        icon.contentTintColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 13, weight: .medium)
        status.textColor = .labelColor
        status.lineBreakMode = .byTruncatingTail
        height.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        height.textColor = .secondaryLabelColor

        let text = NSStackView(views: [status, height])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancel.bezelStyle = .rounded
        let done = NSButton(title: "Done", target: self, action: #selector(doneClicked))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"

        let row = NSStackView(views: [icon, text, cancel, done])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.setCustomSpacing(16, after: text)
        row.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            row.topAnchor.constraint(equalTo: background.topAnchor),
            row.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            status.widthAnchor.constraint(equalToConstant: 300),
        ])
        contentView = background
        setContentSize(row.fittingSize)
    }

    override var canBecomeKey: Bool { false }

    /// Below the region, else above it, else inside its bottom edge.
    func place(near region: CGRect, within screen: CGRect) {
        let size = frame.size
        let gap: CGFloat = 12
        var origin = CGPoint(x: region.midX - size.width / 2, y: region.minY - gap - size.height)
        if origin.y < screen.minY + 8 { origin.y = region.maxY + gap }
        if origin.y + size.height > screen.maxY - 8 { origin.y = region.minY + gap }
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        setFrameOrigin(origin)
    }

    func update(status text: String, height pixels: Int, warning: Bool = false) {
        status.stringValue = text
        status.textColor = warning ? .systemYellow : .labelColor
        height.stringValue = "\(pixels.formatted()) px tall"
    }

    @objc private func cancelClicked() { onCancel?() }
    @objc private func doneClicked() { onDone?() }
}
