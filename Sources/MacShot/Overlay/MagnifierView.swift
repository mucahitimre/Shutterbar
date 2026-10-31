import AppKit

/// İmleç çevresindeki pikselleri donmuş kareden büyütür (R1.9). Fare olaylarını yutmaz.
final class MagnifierView: NSView {
    static let pixelCount = 15
    static let pixelSize: CGFloat = 8
    static var side: CGFloat { CGFloat(pixelCount) * pixelSize }

    private let image: CGImage
    private let zoomLayer = CALayer()
    private let gridLayer = CAShapeLayer()
    private let centerLayer = CAShapeLayer()
    private let context: CGContext?

    init(image: CGImage) {
        self.image = image
        let count = Self.pixelCount
        context = CGContext(
            data: nil, width: count, height: count, bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.interpolationQuality = .none
        super.init(frame: CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
        wantsLayer = true
        layer?.borderColor = NSColor.white.cgColor
        layer?.borderWidth = 1
        layer?.masksToBounds = true

        zoomLayer.frame = bounds
        zoomLayer.magnificationFilter = .nearest
        zoomLayer.actions = ["contents": NSNull()]
        layer?.addSublayer(zoomLayer)

        let grid = CGMutablePath()
        for i in 1..<count {
            let offset = CGFloat(i) * Self.pixelSize
            grid.move(to: CGPoint(x: offset, y: 0))
            grid.addLine(to: CGPoint(x: offset, y: Self.side))
            grid.move(to: CGPoint(x: 0, y: offset))
            grid.addLine(to: CGPoint(x: Self.side, y: offset))
        }
        gridLayer.path = grid
        gridLayer.strokeColor = NSColor.black.withAlphaComponent(0.2).cgColor
        gridLayer.lineWidth = 0.5
        gridLayer.frame = bounds
        layer?.addSublayer(gridLayer)

        let center = CGFloat(count / 2) * Self.pixelSize
        centerLayer.path = CGPath(rect: CGRect(x: center, y: center, width: Self.pixelSize, height: Self.pixelSize), transform: nil)
        centerLayer.fillColor = nil
        centerLayer.strokeColor = NSColor.systemRed.cgColor
        centerLayer.lineWidth = 1.5
        centerLayer.frame = bounds
        layer?.addSublayer(centerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// - Parameter pixel: imlecin altındaki piksel (görüntü koordinatı, sol-üst orijin).
    func update(pixel: CGPoint) {
        guard let context else { return }
        let count = Self.pixelCount
        let half = count / 2
        let source = CGRect(x: Int(pixel.x) - half, y: Int(pixel.y) - half, width: count, height: count)
        let clipped = source.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))

        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: count, height: count))
        if !clipped.isNull, let piece = image.cropping(to: clipped) {
            // CGImage kırpması sol-üst, CGContext sol-alt orijinli.
            let x = clipped.minX - source.minX
            let y = CGFloat(count) - (clipped.minY - source.minY) - clipped.height
            context.draw(piece, in: CGRect(x: x, y: y, width: clipped.width, height: clipped.height))
        }
        zoomLayer.contents = context.makeImage()
    }
}
