import CoreGraphics
import CoreText
import Foundation

/// Görüntü üstüne çizilen tek bir işaret. Koordinatlar görüntü pikseli, sol-üst orijin.
public struct Annotation: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        case arrow(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case text(String, origin: CGPoint)
        case pixelate(CGRect)
        /// Sıra numarası rozeti; `center` daire merkezi.
        case number(Int, center: CGPoint)
    }

    public struct Color: Hashable, Sendable {
        public var red, green, blue, alpha: CGFloat

        public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        public static let red = Color(red: 0.95, green: 0.23, blue: 0.19)
        public static let yellow = Color(red: 1, green: 0.8, blue: 0)
        public static let green = Color(red: 0.2, green: 0.78, blue: 0.35)
        public static let blue = Color(red: 0, green: 0.48, blue: 1)
        public static let black = Color(red: 0, green: 0, blue: 0)
        public static let white = Color(red: 1, green: 1, blue: 1)

        var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    }

    public var shape: Shape
    public var color: Color
    /// Çizgi kalınlığı (piksel). Metin boyutu, ok başı ve rozet buna göre ölçeklenir.
    public var lineWidth: CGFloat

    public init(_ shape: Shape, color: Color = .red, lineWidth: CGFloat = 4) {
        self.shape = shape
        self.color = color
        self.lineWidth = lineWidth
    }

    public var fontSize: CGFloat { max(12, lineWidth * 6) }
    public var badgeRadius: CGFloat { max(10, lineWidth * 4) }
    public static let pixelateBlock: CGFloat = 12
}

/// Annotation listesi + geri al / yinele. Saf değer tipi.
public struct AnnotationDocument: Equatable, Sendable {
    public private(set) var items: [Annotation] = []
    private var redoStack: [Annotation] = []

    public init() {}

    public var canUndo: Bool { !items.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Sıradaki numara rozeti: mevcut en büyük + 1 (geri alınca düşer).
    public var nextNumber: Int {
        let numbers = items.compactMap { item -> Int? in
            if case .number(let n, _) = item.shape { return n }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }

    public mutating func add(_ annotation: Annotation) {
        items.append(annotation)
        redoStack.removeAll()
    }

    public mutating func undo() {
        guard let last = items.popLast() else { return }
        redoStack.append(last)
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        items.append(next)
    }

    public mutating func removeAll() {
        guard !items.isEmpty else { return }
        redoStack = items.reversed()
        items.removeAll()
    }
}

public enum AnnotationRenderer {
    /// Annotation'ları taban görüntünün üstüne piksel boyutunda işler.
    public static func render(_ items: [Annotation], on base: CGImage) -> CGImage? {
        let width = base.width, height = base.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: base.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        flipToTopLeft(context, height: CGFloat(height))
        draw(items, base: base, in: context)
        return context.makeImage()
    }

    /// Sol-üst orijinli (y aşağı) bir context'e çizer. Ekrandaki canvas da aynı yolu kullanır.
    public static func draw(_ items: [Annotation], base: CGImage, in context: CGContext) {
        for item in items {
            context.saveGState()
            draw(item, base: base, in: context)
            context.restoreGState()
        }
    }

    public static func flipToTopLeft(_ context: CGContext, height: CGFloat) {
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
    }

    /// Bu noktaya en üstteki annotation'ın sınırı (silme / seçme için).
    public static func bounds(of item: Annotation) -> CGRect {
        let pad = item.lineWidth
        switch item.shape {
        case .arrow(let from, let to):
            return CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
                .insetBy(dx: -pad * 3, dy: -pad * 3)
        case .rectangle(let rect), .pixelate(let rect):
            return rect.standardized.insetBy(dx: -pad, dy: -pad)
        case .text(let string, let origin):
            let size = textSize(string, fontSize: item.fontSize)
            return CGRect(origin: origin, size: size)
        case .number(_, let center):
            let r = item.badgeRadius
            return CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        }
    }

    // MARK: Şekiller

    private static func draw(_ item: Annotation, base: CGImage, in context: CGContext) {
        let color = item.color.cgColor
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(item.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch item.shape {
        case .arrow(let from, let to):
            drawArrow(from: from, to: to, lineWidth: item.lineWidth, in: context)
        case .rectangle(let rect):
            context.stroke(rect.standardized.insetBy(dx: item.lineWidth / 2, dy: item.lineWidth / 2))
        case .text(let string, let origin):
            drawText(string, at: origin, fontSize: item.fontSize, color: color, in: context)
        case .pixelate(let rect):
            pixelate(rect.standardized, base: base, in: context)
        case .number(let n, let center):
            let r = item.badgeRadius
            context.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            let label = "\(n)"
            let fontSize = r * 1.1
            let size = textSize(label, fontSize: fontSize, bold: true)
            let textColor = item.color == .white || item.color == .yellow ? Annotation.Color.black.cgColor : Annotation.Color.white.cgColor
            drawText(label, at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
                     fontSize: fontSize, color: textColor, bold: true, in: context)
        }
    }

    private static func drawArrow(from: CGPoint, to: CGPoint, lineWidth: CGFloat, in context: CGContext) {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0 else { return }
        let headLength = min(length, max(12, lineWidth * 4))
        let angle = atan2(dy, dx)
        let spread: CGFloat = .pi / 7
        // Gövde ok başının içinde biter, uç sivri kalsın.
        let shaftEnd = CGPoint(x: to.x - cos(angle) * headLength * 0.8, y: to.y - sin(angle) * headLength * 0.8)
        context.move(to: from)
        context.addLine(to: shaftEnd)
        context.strokePath()

        context.move(to: to)
        context.addLine(to: CGPoint(x: to.x - cos(angle - spread) * headLength, y: to.y - sin(angle - spread) * headLength))
        context.addLine(to: CGPoint(x: to.x - cos(angle + spread) * headLength, y: to.y - sin(angle + spread) * headLength))
        context.closePath()
        context.fillPath()
    }

    /// Bölgeyi blok boyutuna küçültüp en yakın komşu ile geri büyütür; taban görüntüden okur.
    private static func pixelate(_ rect: CGRect, base: CGImage, in context: CGContext) {
        let imageBounds = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let region = rect.integral.intersection(imageBounds)
        guard !region.isNull, region.width >= 1, region.height >= 1, let piece = base.cropping(to: region) else { return }
        let block = Annotation.pixelateBlock
        let smallWidth = max(1, Int((region.width / block).rounded(.up)))
        let smallHeight = max(1, Int((region.height / block).rounded(.up)))
        guard let small = CGContext(
            data: nil, width: smallWidth, height: smallHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        small.interpolationQuality = .medium
        small.draw(piece, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        guard let reduced = small.makeImage() else { return }

        // Context sol-üst orijinli; görüntüyü ters çizmemek için bölgede yerel olarak geri çevir.
        context.interpolationQuality = .none
        context.clip(to: region)
        context.translateBy(x: region.minX, y: region.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(reduced, in: CGRect(x: 0, y: 0, width: CGFloat(smallWidth) * block, height: CGFloat(smallHeight) * block))
    }

    // MARK: Metin

    public static func textSize(_ string: String, fontSize: CGFloat, bold: Bool = false) -> CGSize {
        let line = makeLine(string, fontSize: fontSize, color: Annotation.Color.black.cgColor, bold: bold)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return CGSize(width: ceil(width), height: ceil(ascent + descent))
    }

    private static func drawText(_ string: String, at origin: CGPoint, fontSize: CGFloat, color: CGColor, bold: Bool = false, in context: CGContext) {
        let line = makeLine(string, fontSize: fontSize, color: color, bold: bold)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        // Context y aşağı; CoreText y yukarı bekler: metin matrisini çevir, taban çizgisini ascent kadar aşağı al.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: origin.x, y: origin.y + ascent)
        CTLineDraw(line, context)
    }

    private static func makeLine(_ string: String, fontSize: CGFloat, color: CGColor, bold: Bool) -> CTLine {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }
}
