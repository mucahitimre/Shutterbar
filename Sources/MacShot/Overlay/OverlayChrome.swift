import AppKit

/// Short message at the top center of the overlay, on system HUD material.
final class HUDView: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        addSubview(label)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ text: String, in bounds: CGRect, duration: TimeInterval) {
        label.stringValue = text
        label.sizeToFit()
        let size = CGSize(width: label.frame.width + 32, height: label.frame.height + 16)
        frame = CGRect(x: (bounds.width - size.width) / 2, y: 64, width: size.width, height: size.height)
        label.frame = CGRect(x: 16, y: 8, width: label.frame.width, height: label.frame.height)
        alphaValue = 1
        isHidden = false
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.duration(0.3)
                self?.animator().alphaValue = 0
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}

extension NSCursor {
    /// Camera cursor used by macOS for window / screen capture, drawn from the "camera.fill" symbol.
    @MainActor static let camera: NSCursor = {
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return .crosshair }
        let size = CGSize(width: symbol.size.width + 4, height: symbol.size.height + 4)
        let image = NSImage(size: size, flipped: false) { rect in
            // White halo so the black camera reads on any background.
            for (dx, dy) in [(-1.0, 0.0), (1, 0), (0, -1), (0, 1)] {
                tinted(symbol, .white).draw(in: rect.insetBy(dx: 2, dy: 2).offsetBy(dx: dx, dy: dy))
            }
            tinted(symbol, .black).draw(in: rect.insetBy(dx: 2, dy: 2))
            return true
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: size.width / 2, y: size.height / 2))
    }()

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}

/// Animation durations that respect "Reduce motion".
enum Motion {
    @MainActor static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    @MainActor static func duration(_ value: TimeInterval) -> TimeInterval {
        reduced ? 0 : value
    }
}

/// The system screenshot sound.
@MainActor
enum ShutterSound {
    private static let sound = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        byReference: true
    )

    static func play() {
        guard Preferences.shared.playSound else { return }
        sound?.stop()
        sound?.play()
    }
}
