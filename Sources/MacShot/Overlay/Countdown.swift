import AppKit

/// Self-timer countdown shown in the middle of the screen on HUD material. Esc or a click cancels.
@MainActor
enum Countdown {
    /// - Returns: false when the user cancelled.
    static func run(seconds: Int, on screen: NSScreen?) async -> Bool {
        let panel = CountdownPanel()
        if let screen {
            panel.setFrameOrigin(CGPoint(x: screen.frame.midX - panel.frame.width / 2, y: screen.frame.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }

        for remaining in stride(from: seconds, to: 0, by: -1) {
            panel.show(remaining)
            try? await Task.sleep(for: .seconds(1))
            if panel.isCancelled { return false }
        }
        // Let the panel disappear before the live capture.
        panel.orderOut(nil)
        try? await Task.sleep(for: .milliseconds(120))
        return true
    }
}

private final class CountdownPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private(set) var isCancelled = false
    private var monitor: Any?

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 140, height: 140), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)

        let background = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 140, height: 140))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 28
        background.layer?.cornerCurve = .continuous
        label.font = .monospacedDigitSystemFont(ofSize: 64, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.frame = background.bounds.insetBy(dx: 0, dy: 30)
        background.addSubview(label)
        contentView = background

        // The panel never becomes key; watch Esc / clicks globally and locally to allow cancelling.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            if event.type == .leftMouseDown || event.keyCode == 53 { self?.isCancelled = true }
            return event
        }
    }

    override func orderOut(_ sender: Any?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        super.orderOut(sender)
    }

    func show(_ value: Int) {
        label.stringValue = "\(value)"
    }
}
