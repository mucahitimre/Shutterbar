import AppKit
import ApplicationServices
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
    /// Time for the target app's smooth scrolling to settle after a synthetic scroll.
    private static let settleInterval: Duration = .milliseconds(260)

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
        hud.onEnableAutoScroll = { AutoScrollPermission.request() }
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

        var counts: [String: Int] = [:]
        defer {
            Log.capture.info("Scrolling session frames: \(counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "), privacy: .public)")
        }

        let automatic = Preferences.shared.autoScroll && AutoScrollPermission.isAvailable && AutoScrollPermission.isGranted
        hud.showsEnableAutoScroll = Preferences.shared.autoScroll && AutoScrollPermission.isAvailable && !automatic
        Log.capture.info("Scrolling session: \(automatic ? "automatic" : "manual", privacy: .public)")
        let scroller = automatic ? AutoScroller(regionCenter: CGPoint(x: globalRect.midX, y: globalRect.midY), regionHeight: rect.height) : nil
        scroller?.moveCursorIntoRegion()
        var unchangedInARow = 0

        while finishRequested == nil {
            let frame = try await capturer.capture()
            let result = stitch.add(frame)
            counts[Self.name(result), default: 0] += 1
            switch result {
            case .first:
                hud.update(status: automatic ? "Scrolling automatically…" : "Scroll down slowly inside the frame", height: stitch.height)
            case .appended:
                unchangedInARow = 0
                hud.update(status: automatic ? "Scrolling automatically — click Done to stop" : "Capturing — keep scrolling, then click Done",
                           height: stitch.height)
            case .unchanged:
                unchangedInARow += 1
                // Nothing moved twice after scrolling: the end of the page.
                if automatic, unchangedInARow >= 2, counts["appended", default: 0] > 0 {
                    hud.update(status: "Reached the end of the page", height: stitch.height)
                    finishRequested = true
                }
            case .lost:
                scroller?.slowDown()
                hud.update(status: automatic ? "Adjusting scroll speed…" : "Scrolled too far at once — scroll back up a little",
                           height: stitch.height, warning: !automatic)
            case .full:
                hud.update(status: "Maximum height reached", height: stitch.height)
                finishRequested = true
            }
            guard finishRequested == nil else { break }
            if let scroller {
                scroller.scrollDown()
                try? await Task.sleep(for: Self.settleInterval)
            } else {
                try? await Task.sleep(for: Self.frameInterval)
            }
        }

        guard finishRequested == true, let image = stitch.makeImage() else { return .cancelled }
        if stitch.height == image.height, counts["appended", default: 0] == 0 {
            Log.capture.notice("Scrolling capture: no scroll was detected; the result is a single frame")
        }
        Log.capture.info("Scrolling capture: \(image.width)×\(image.height) px")
        return .done(image)
    }

    private static func name(_ result: ScrollingCapture.AddResult) -> String {
        switch result {
        case .first: "first"
        case .appended: "appended"
        case .unchanged: "unchanged"
        case .lost: "lost"
        case .full: "full"
        }
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
    var onEnableAutoScroll: (() -> Void)?
    var showsEnableAutoScroll = false {
        didSet {
            enableButton.isHidden = !showsEnableAutoScroll
            setContentSize(contentView?.fittingSize ?? frame.size)
        }
    }
    private let enableButton = NSButton()

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

        enableButton.title = "Scroll for Me…"
        enableButton.bezelStyle = .rounded
        enableButton.target = self
        enableButton.action = #selector(enableClicked)
        enableButton.toolTip = "Let MacShot scroll automatically (needs the Accessibility permission)"
        enableButton.isHidden = true

        let row = NSStackView(views: [icon, text, enableButton, cancel, done])
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
    @objc private func enableClicked() { onEnableAutoScroll?() }
    @objc private func doneClicked() { onDone?() }
}

/// Accessibility permission for automatic scrolling (GitHub build only; a sandboxed app cannot be granted it).
@MainActor
enum AutoScrollPermission {
    static var isAvailable: Bool { Channel.supportsAutoScroll }
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt and opens the settings pane where MacShot can be turned on.
    static func request() {
        // Key of kAXTrustedCheckOptionPrompt (the global is not concurrency-safe in Swift 6).
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

/// Posts synthetic scroll-down events at the region's center. The step starts at about a third of the region
/// so consecutive frames always overlap, and halves when a frame cannot be matched.
@MainActor
private final class AutoScroller {
    private let center: CGPoint // Quartz global (top-left origin)
    private var step: Int32

    init(regionCenter appKitPoint: CGPoint, regionHeight: CGFloat) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        center = CGPoint(x: appKitPoint.x, y: primaryHeight - appKitPoint.y)
        step = Int32(max(40, regionHeight * 0.35))
    }

    /// Scroll events go to the window under the cursor.
    func moveCursorIntoRegion() {
        CGWarpMouseCursorPosition(center)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    func scrollDown() {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -step, wheel2: 0, wheel3: 0) else { return }
        event.location = center
        event.post(tap: .cghidEventTap)
    }

    func slowDown() {
        step = max(20, step / 2)
    }
}
