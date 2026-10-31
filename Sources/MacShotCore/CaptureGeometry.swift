import CoreGraphics
import Foundation

/// Coordinate systems:
/// - **AppKit global**: `NSScreen.frame`; origin at the bottom-left of the primary screen, y increases upward, points.
/// - **Display-local**: origin at the top-left of a screen, y increases downward, points. The overlay view (flipped) and
///   the stored last region use this system.
/// - **Pixel**: display-local × scale; position within the frozen `CGImage` (top-left origin).
/// - **Quartz global**: origin at the top-left of the primary screen, y increases downward, points (`CGWarpMouseCursorPosition`).
public enum CaptureGeometry {
    /// A drag smaller than this counts as a click.
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

    /// Converts a display-local point to Quartz global coordinates. `primaryScreenHeight` = `NSScreen.screens[0].frame.height`.
    public static func toQuartzGlobal(_ point: CGPoint, displayFrame: CGRect, primaryScreenHeight: CGFloat) -> CGPoint {
        let appKitY = displayFrame.maxY - point.y
        return CGPoint(x: displayFrame.minX + point.x, y: primaryScreenHeight - appKitY)
    }

    /// Quartz global rect (origin at the primary screen's top-left, y down) → display-local rect. Parts outside the screen are not clipped.
    public static func toDisplayLocal(quartzRect rect: CGRect, displayFrame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        let originY = primaryScreenHeight - displayFrame.maxY
        return rect.offsetBy(dx: -displayFrame.minX, dy: -originY)
    }

    // MARK: Scale and pixels

    /// Actual scale of the frozen image (pixels / point).
    public static func scale(imagePixelWidth: Int, displayPointWidth: CGFloat) -> CGFloat {
        guard displayPointWidth > 0 else { return 1 }
        return CGFloat(imagePixelWidth) / displayPointWidth
    }

    /// Converts a display-local point rect to an image pixel rect.
    /// The origin is rounded down (floor), maxX/maxY up (ceil); the result is clipped to the image bounds.
    /// nil for an empty or fully out-of-bounds rect.
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

    // MARK: Selection

    public static func clamp(_ point: CGPoint, to bounds: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    /// Shifts the rect inside the bounds while keeping its size (for moving).
    public static func keepInside(_ rect: CGRect, bounds: CGSize) -> CGRect {
        var rect = rect.standardized
        rect.size.width = min(rect.width, bounds.width)
        rect.size.height = min(rect.height, bounds.height)
        rect.origin.x = min(max(rect.minX, 0), bounds.width - rect.width)
        rect.origin.y = min(max(rect.minY, 0), bounds.height - rect.height)
        return rect
    }

    /// Selection rect from the drag start and the current point. The point is clamped to the screen (single-screen clamp);
    /// with `square` on, the shorter side is used so the square also stays on screen.
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

    /// Whether the whole rect is inside the bounds (for last region validity).
    public static func fits(_ rect: CGRect, in bounds: CGSize) -> Bool {
        let rect = rect.standardized
        return rect.width > 0 && rect.height > 0
            && rect.minX >= 0 && rect.minY >= 0
            && rect.maxX <= bounds.width && rect.maxY <= bounds.height
    }
}
