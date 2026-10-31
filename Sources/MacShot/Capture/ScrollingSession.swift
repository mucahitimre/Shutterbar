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
    /// After a synthetic scroll, frames are taken this often until two in a row are the same (smooth scrolling
    /// has settled), at most `settleAttempts` times.
    private static let settleInterval: Duration = .milliseconds(80)
    private static let settleAttempts = 9

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
        // Whole points: a fractional edge would pull a sliver of our outline into the capture.
        let rect = rect.integral
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
        // The first frame after our windows appear can still contain them (exclusion applies a moment later).
        try? await Task.sleep(for: .milliseconds(150))
        _ = try await capturer.capture()
        defer {
            frameWindow.orderOut(nil)
            hud.orderOut(nil)
        }

        var counts: [String: Int] = [:]
        defer {
            Log.capture.info("Scrolling session frames: \(counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "), privacy: .public)")
        }

        var automatic = Preferences.shared.autoScroll && AutoScrollPermission.isAvailable && AutoScrollPermission.isGranted
        hud.showsEnableAutoScroll = Preferences.shared.autoScroll && AutoScrollPermission.isAvailable && !automatic
        Log.capture.info("Scrolling session: \(automatic ? "automatic" : "manual", privacy: .public)")
        let scroller = AutoScroller(regionHeight: rect.height)
        var policy = AutoScrollPolicy()
        let input = InputMonitor()
        defer { input.stop() }
        let clock = ContinuousClock()
        let started = clock.now

        var pending: CGImage? // a settled frame taken right after scrolling
        var expectedShift: Int? // pixels the content should have moved, known after our own scroll
        while finishRequested == nil {
            if input.escapePressed {
                finishRequested = false
                break
            }
            let frame: CGImage
            if let settled = pending {
                frame = settled
                pending = nil
            } else {
                frame = try await capturer.capture()
            }
            #if DEBUG
            FrameDump.write(frame)
            #endif
            let result = stitch.add(frame, expectedShift: expectedShift)
            expectedShift = nil
            counts[Self.name(result), default: 0] += 1
            if automatic { policy.record(result) }
            switch result {
            case .first:
                hud.update(status: automatic ? "Scrolling automatically — move the mouse or press Esc to stop"
                                             : "Scroll down slowly inside the frame", height: stitch.height)
            case .appended:
                if !automatic { hud.update(status: "Capturing — keep scrolling, then click Done", height: stitch.height) }
                else { hud.update(status: "Scrolling automatically — move the mouse or press Esc to stop", height: stitch.height) }
            case .unchanged:
                break
            case .lost:
                if automatic { scroller.slowDown() }
                else { hud.update(status: "Scrolled too far at once — scroll back up a little", height: stitch.height, warning: true) }
            case .full:
                hud.update(status: "Maximum height reached", height: stitch.height)
                finishRequested = true
            }
            guard finishRequested == nil else { break }

            guard automatic else {
                try? await Task.sleep(for: Self.frameInterval)
                continue
            }
            let elapsed = (clock.now - started) / .seconds(1)
            switch policy.decide(elapsed: elapsed, userActivity: input.takeActivity(), pointerInside: globalRect.contains(NSEvent.mouseLocation)) {
            case .scroll:
                scroller.scrollDown()
                expectedShift = Int((CGFloat(scroller.step) * capturer.pixelScale).rounded())
                pending = try await settledFrame(capturer)
            case .pause:
                hud.update(status: "Paused — move the pointer back into the frame", height: stitch.height, warning: true)
                try? await Task.sleep(for: Self.frameInterval)
            case .stop(.endOfContent):
                hud.update(status: "Reached the end", height: stitch.height)
                finishRequested = true
            case .stop(let reason):
                // Never keep control: hand over to manual scrolling; the user finishes with Done.
                automatic = false
                Log.capture.info("Automatic scrolling stopped: \(String(describing: reason), privacy: .public)")
                hud.update(status: Self.stopMessage(reason), height: stitch.height)
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

    /// Captures until two consecutive frames match, so the page has stopped moving.
    private func settledFrame(_ capturer: RegionCapturer) async throws -> CGImage {
        try? await Task.sleep(for: Self.settleInterval)
        var previous = try await capturer.capture()
        for _ in 1..<Self.settleAttempts {
            try? await Task.sleep(for: Self.settleInterval)
            let next = try await capturer.capture()
            if ScrollStitcher.isSameFrame(previous, next) { return next }
            previous = next
        }
        return previous
    }

    private static func stopMessage(_ reason: AutoScrollPolicy.StopReason) -> String {
        switch reason {
        case .userTookOver: "You took over — scroll yourself, then click Done"
        case .timeLimit: "Stopped after the time limit — click Done or keep scrolling yourself"
        case .frameLimit: "Stopped after the frame limit — click Done or keep scrolling yourself"
        case .lostTrack: "Lost track of the page — scroll yourself or click Done"
        case .endOfContent: "Reached the end"
        }
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
        // The outline sits a few points outside the region so it can never touch captured pixels.
        let inset: CGFloat = -6
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

#if DEBUG
/// Debug self-test only: keeps the first frames of a session for offline inspection.
@MainActor
enum FrameDump {
    static var enabled = false
    private static var index = 0
    static let folder = SaveFolder.defaultRoot.appendingPathComponent("selftest-frames", isDirectory: true)

    static func write(_ image: CGImage) {
        guard enabled, index < 16 else { return }
        index += 1
        try? PNGEncoder.write(image, to: folder.appendingPathComponent(String(format: "frame-%02d.png", index)), overwrite: true)
    }
}
#endif

/// Posts synthetic scroll-down events where the pointer is (it never moves the pointer). The step starts at about
/// a third of the region so consecutive frames always overlap, and halves when a frame cannot be matched.
@MainActor
private final class AutoScroller {
    /// Marks our own events so `InputMonitor` can tell them from the user's.
    static let marker: Int64 = 0x4D53_5343 // 'MSSC'
    /// Points per synthetic scroll.
    private(set) var step: Int32

    init(regionHeight: CGFloat) {
        step = Int32(max(40, regionHeight * 0.25))
    }

    func scrollDown() {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -step, wheel2: 0, wheel3: 0) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: .cghidEventTap)
    }

    func slowDown() {
        step = max(20, step / 2)
    }
}

/// Watches the user's mouse and keyboard during a scrolling session (global monitors work with the Accessibility
/// permission; local ones cover our own windows). Our synthetic scroll events are ignored by their marker.
@MainActor
private final class InputMonitor {
    private(set) var escapePressed = false
    private var activity = false
    private var monitors: [Any] = []

    init() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .scrollWheel, .keyDown]
        let handle: (NSEvent) -> Void = { [weak self] event in
            if event.type == .scrollWheel,
               event.cgEvent?.getIntegerValueField(.eventSourceUserData) == AutoScroller.marker { return }
            MainActor.assumeIsolated {
                if event.type == .keyDown, event.keyCode == 53 { self?.escapePressed = true }
                self?.activity = true
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handle) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { handle($0); return $0 }) { monitors.append(local) }
    }

    /// Whether there was user input since the last call.
    func takeActivity() -> Bool {
        defer { activity = false }
        return activity
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}
