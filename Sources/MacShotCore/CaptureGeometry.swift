import CoreGraphics
import Foundation

/// Koordinat sistemleri:
/// - **AppKit global**: `NSScreen.frame`; ana ekranın sol-alt köşesi orijin, y yukarı artar, point.
/// - **Display-local**: bir ekranın sol-üst köşesi orijin, y aşağı artar, point. Overlay görünümü (flipped) ve
///   saklanan son bölge bu sistemdedir.
/// - **Piksel**: display-local × ölçek; donmuş `CGImage` içindeki konum (sol-üst orijin).
/// - **Quartz global**: ana ekranın sol-üst köşesi orijin, y aşağı artar, point (`CGWarpMouseCursorPosition`).
public enum CaptureGeometry {
    /// Bu boyutun altındaki sürükleme tıklama sayılır.
    public static let minimumSelectionSize: CGFloat = 3

    // MARK: Global ↔ display-local

    public static func toDisplayLocal(_ point: CGPoint, displayFrame: CGRect) -> CGPoint {
        CGPoint(x: point.x - displayFrame.minX, y: displayFrame.maxY - point.y)
    }

    public static func toDisplayLocal(_ rect: CGRect, displayFrame: CGRect) -> CGRect {
        let rect = rect.standardized
        return CGRect(
            x: rect.minX - displayFrame.minX,
            y: displayFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    public static func toGlobal(_ rect: CGRect, displayFrame: CGRect) -> CGRect {
        let rect = rect.standardized
        return CGRect(
            x: displayFrame.minX + rect.minX,
            y: displayFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Display-local noktayı Quartz global koordinata çevirir. `primaryScreenHeight` = `NSScreen.screens[0].frame.height`.
    public static func toQuartzGlobal(_ point: CGPoint, displayFrame: CGRect, primaryScreenHeight: CGFloat) -> CGPoint {
        let appKitY = displayFrame.maxY - point.y
        return CGPoint(x: displayFrame.minX + point.x, y: primaryScreenHeight - appKitY)
    }

    /// Quartz global rect (ana ekranın sol-üstü orijin, y aşağı) → display-local rect. Ekran dışına taşan kısım kırpılmaz.
    public static func toDisplayLocal(quartzRect rect: CGRect, displayFrame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        let originY = primaryScreenHeight - displayFrame.maxY
        return rect.offsetBy(dx: -displayFrame.minX, dy: -originY)
    }

    // MARK: Ölçek ve piksel

    /// Donmuş görüntünün gerçek ölçeği (piksel / point).
    public static func scale(imagePixelWidth: Int, displayPointWidth: CGFloat) -> CGFloat {
        guard displayPointWidth > 0 else { return 1 }
        return CGFloat(imagePixelWidth) / displayPointWidth
    }

    /// Display-local point rect'ini görüntü piksel rect'ine çevirir.
    /// Origin aşağı (floor), maxX/maxY yukarı (ceil) yuvarlanır; sonuç görüntü sınırına kırpılır.
    /// Boş ya da tamamen sınır dışı rect için nil.
    public static func pixelRect(forPointRect rect: CGRect, scale: CGFloat, imageWidth: Int, imageHeight: Int) -> CGRect? {
        let rect = rect.standardized
        guard rect.width > 0, rect.height > 0, scale > 0, imageWidth > 0, imageHeight > 0 else { return nil }

        let minX = max(0, floor(rect.minX * scale))
        let minY = max(0, floor(rect.minY * scale))
        let maxX = min(CGFloat(imageWidth), ceil(rect.maxX * scale))
        let maxY = min(CGFloat(imageHeight), ceil(rect.maxY * scale))
        guard maxX > minX, maxY > minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: Seçim

    public static func clamp(_ point: CGPoint, to bounds: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    /// Rect'i boyutunu koruyarak sınırların içine kaydırır (taşıma için).
    public static func keepInside(_ rect: CGRect, bounds: CGSize) -> CGRect {
        var rect = rect.standardized
        rect.size.width = min(rect.width, bounds.width)
        rect.size.height = min(rect.height, bounds.height)
        rect.origin.x = min(max(rect.minX, 0), bounds.width - rect.width)
        rect.origin.y = min(max(rect.minY, 0), bounds.height - rect.height)
        return rect
    }

    /// Sürükleme başlangıcı ve güncel noktadan seçim rect'i. Nokta ekrana kırpılır (tek ekrana clamp);
    /// `square` açıkken kısa kenar esas alınır ki kare de ekranın içinde kalsın.
    public static func rect(from anchor: CGPoint, to current: CGPoint, square: Bool, bounds: CGSize) -> CGRect {
        let anchor = clamp(anchor, to: bounds)
        let current = clamp(current, to: bounds)
        var dx = current.x - anchor.x
        var dy = current.y - anchor.y
        if square {
            let side = min(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        return CGRect(x: anchor.x, y: anchor.y, width: dx, height: dy).standardized
    }

    public static func isClick(_ rect: CGRect) -> Bool {
        let rect = rect.standardized
        return rect.width < minimumSelectionSize || rect.height < minimumSelectionSize
    }

    /// Rect'in tamamı sınırların içinde mi (son bölge geçerliliği için).
    public static func fits(_ rect: CGRect, in bounds: CGSize) -> Bool {
        let rect = rect.standardized
        return rect.width > 0 && rect.height > 0
            && rect.minX >= 0 && rect.minY >= 0
            && rect.maxX <= bounds.width && rect.maxY <= bounds.height
    }
}
