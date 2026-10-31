import AppKit
import MacShotCore

/// Floating toolbar shown with the overlay, modeled on macOS's screenshot toolbar (⌘⇧5):
/// close · capture modes · Options · Capture. It never becomes key, so the overlay keeps the keyboard.
@MainActor
final class CaptureToolbar: NSPanel {
    struct Actions {
        var close: () -> Void
        var setMode: (CaptureMode) -> Void
        var capture: () -> Void
        /// Builds the Options menu each time it opens (reflects current preferences).
        var optionsMenu: () -> NSMenu
    }

    private let actions: Actions
    private var modeButtons: [CaptureMode: ToolbarToggleButton] = [:]
    private let optionsButton = NSButton()

    init(mode: CaptureMode, actions: Actions) {
        self.actions = actions
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        animationBehavior = .none
        // macOS's screenshot toolbar is always dark.
        appearance = NSAppearance(named: .darkAqua)

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: 12)

        let close = Self.iconButton(symbol: "xmark.circle.fill", size: 17, help: "Close (Esc)")
        close.contentTintColor = .secondaryLabelColor
        close.target = self
        close.action = #selector(closeClicked)

        var items: [NSView] = [close, Self.divider()]
        for mode in [CaptureMode.screen, .window, .selection] {
            let button = ToolbarToggleButton(symbol: mode.symbol, help: mode.title)
            button.target = self
            button.action = #selector(modeClicked(_:))
            button.tag = CaptureMode.allCases.firstIndex(of: mode) ?? 0
            modeButtons[mode] = button
            items.append(button)
        }
        items.append(Self.divider())

        optionsButton.title = "Options"
        optionsButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        optionsButton.imagePosition = .imageTrailing
        optionsButton.isBordered = false
        optionsButton.font = .systemFont(ofSize: 13)
        optionsButton.contentTintColor = .labelColor
        optionsButton.target = self
        optionsButton.action = #selector(optionsClicked)
        items.append(optionsButton)

        let capture = NSButton(title: "Capture", target: self, action: #selector(captureClicked))
        capture.bezelStyle = .rounded
        capture.controlSize = .regular
        capture.font = .systemFont(ofSize: 13)
        items.append(capture)

        let stack = NSStackView(views: items)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.setCustomSpacing(10, after: close)
        stack.setCustomSpacing(12, after: optionsButton)
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        contentView = background
        setContentSize(stack.fittingSize)
        select(mode)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Bottom center of the screen, like the system toolbar.
    func present(on screen: NSScreen) {
        let frame = screen.frame
        setFrameOrigin(CGPoint(x: frame.midX - self.frame.width / 2, y: frame.minY + 96))
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.duration(0.15)
            animator().alphaValue = 1
        }
    }

    func select(_ mode: CaptureMode) {
        for (candidate, button) in modeButtons {
            button.isSelectedMode = candidate == mode
        }
    }

    // MARK: Actions

    @objc private func closeClicked() { actions.close() }
    @objc private func captureClicked() { actions.capture() }

    @objc private func modeClicked(_ sender: NSButton) {
        let mode = CaptureMode.allCases[sender.tag]
        select(mode)
        actions.setMode(mode)
    }

    @objc private func optionsClicked() {
        let menu = actions.optionsMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: optionsButton.bounds.height + 6), in: optionsButton)
    }

    // MARK: Building blocks

    private static func iconButton(symbol: String, size: CGFloat, help: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.isBordered = false
        button.toolTip = help
        button.setAccessibilityLabel(help)
        return button
    }

    private static func divider() -> NSView {
        let line = NSBox()
        line.boxType = .custom
        line.borderWidth = 0
        line.fillColor = .separatorColor
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 22),
        ])
        return line
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: CGSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Icon button with a rounded highlight when its mode is selected (like the system toolbar).
final class ToolbarToggleButton: NSButton {
    var isSelectedMode = false {
        didSet {
            layer?.backgroundColor = isSelectedMode ? NSColor.white.withAlphaComponent(0.18).cgColor : nil
            contentTintColor = isSelectedMode ? .labelColor : .secondaryLabelColor
            setAccessibilityValue(isSelectedMode ? "selected" : nil)
        }
    }

    init(symbol: String, help: String) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
        imagePosition = .imageOnly
        isBordered = false
        toolTip = help
        setAccessibilityLabel(help)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        contentTintColor = .secondaryLabelColor
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 36),
            heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
