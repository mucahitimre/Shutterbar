import AppKit

/// Magnifies the pixels around the cursor from the frozen frame (R1.9). Does not swallow mouse events.
/// The pixel count along the edge changes with the mouse wheel; always odd so there is a center pixel.
final class MagnifierView: NSView {
    static let defaultPixelCount = 15
    static let pixelCountRange = 7...31
    static let pixelSize: CGFloat = 8

    static func side(for pixelCount: Int) -> CGFloat { CGFloat(pixelCount) * pixelSize }

    /// Snaps to an odd number within the range.
    static func normalized(_ count: Int) -> Int {
        let odd = count % 2 == 0 ? count + 1 : count
        return min(max(odd, pixelCountRange.lowerBound), pixelCountRange.upperBound)
    }

    private(set) var pixelCount: Int
    var side: CGFloat { Self.side(for: pixelCount) }

    private let image: CGImage
    private let zoomLayer = CALayer()
    private let gridLayer = CAShapeLayer()
    private let centerLayer = CAShapeLayer()
    private var context: CGContext?
    private var lastPixel: CGPoint = .zero

    init(image: CGImage, pixelCount: Int = MagnifierView.defaultPixelCount) {
        self.image = image
        self.pixelCount = Self.normalized(pixelCount)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderColor = NSColor.white.cgColor
        layer?.borderWidth = 1
        layer?.masksToBounds = true

        zoomLayer.magnificationFilter = .nearest
        gridLayer.strokeColor = NSColor.black.withAlphaComponent(0.2).cgColor
        gridLayer.lineWidth = 0.5
        centerLayer.fillColor = nil
        centerLayer.strokeColor = NSColor.systemRed.cgColor
        centerLayer.lineWidth = 1.5
        for sublayer in [zoomLayer, gridLayer, centerLayer] {
            sublayer.actions = ["contents": NSNull(), "path": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer?.addSublayer(sublayer)
        }
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setPixelCount(_ count: Int) {
        let count = Self.normalized(count)
        guard count != pixelCount else { return }
        pixelCount = count
        rebuild()
        update(pixel: lastPixel)
    }

    private func rebuild() {
        let count = pixelCount
        context = CGContext(
            data: nil, width: count, height: count, bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.interpolationQuality = .none
        setFrameSize(CGSize(width: side, height: side))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for sublayer in [zoomLayer, gridLayer, centerLayer] {
            sublayer.frame = bounds
        }
        let grid = CGMutablePath()
        for i in 1..<count {
            let offset = CGFloat(i) * Self.pixelSize
            grid.move(to: CGPoint(x: offset, y: 0))
            grid.addLine(to: CGPoint(x: offset, y: side))
            grid.move(to: CGPoint(x: 0, y: offset))
            grid.addLine(to: CGPoint(x: side, y: offset))
        }
        gridLayer.path = grid
        let center = CGFloat(count / 2) * Self.pixelSize
        centerLayer.path = CGPath(rect: CGRect(x: center, y: center, width: Self.pixelSize, height: Self.pixelSize), transform: nil)
        CATransaction.commit()
    }

    /// - Parameter pixel: the pixel under the cursor (image coordinates, top-left origin).
    func update(pixel: CGPoint) {
        lastPixel = pixel
        guard let context else { return }
        let count = pixelCount
        let half = count / 2
        let source = CGRect(x: Int(pixel.x) - half, y: Int(pixel.y) - half, width: count, height: count)
        let clipped = source.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))

        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: count, height: count))
        if !clipped.isNull, let piece = image.cropping(to: clipped) {
            // CGImage cropping is top-left origin, CGContext is bottom-left origin.
            let x = clipped.minX - source.minX
            let y = CGFloat(count) - (clipped.minY - source.minY) - clipped.height
            context.draw(piece, in: CGRect(x: x, y: y, width: clipped.width, height: clipped.height))
        }
        zoomLayer.contents = context.makeImage()
    }
}
