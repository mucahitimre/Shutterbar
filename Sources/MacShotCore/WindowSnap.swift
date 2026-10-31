import CoreGraphics

/// Finds the window under the cursor in the overlay (ShareX "DetectWindows").
public enum WindowSnap {
    /// Window info at freeze time. `frame` is Quartz global.
    public struct Window: Equatable, Sendable {
        public var frame: CGRect
        public var layer: Int
        public var ownerPID: Int32

        public init(frame: CGRect, layer: Int, ownerPID: Int32) {
            self.frame = frame
            self.layer = layer
            self.ownerPID = ownerPID
        }
    }

    /// Normal windows and floating / modal panels. The Dock (20) is excluded because it keeps a transparent full-screen window,
    /// and the menu bar (24+) because it is not wanted.
    public static let maxLayer = 19
    public static let minimumSide: CGFloat = 20

    /// From windows ordered front to back, returns those on this screen as display-local rects (order is kept).
    /// Our own windows, tiny ones and the menu bar layer are filtered out; rects are clipped to the screen bounds.
    public static func localRects(
        _ windows: [Window],
        excludingPID: Int32,
        displayFrame: CGRect,
        primaryScreenHeight: CGFloat
    ) -> [CGRect] {
        let bounds = CGRect(origin: .zero, size: displayFrame.size)
        return windows.compactMap { window in
            guard window.ownerPID != excludingPID,
                  window.layer >= 0, window.layer <= maxLayer,
                  window.frame.width >= minimumSide, window.frame.height >= minimumSide
            else { return nil }
            let local = CaptureGeometry.toDisplayLocal(
                quartzRect: window.frame, displayFrame: displayFrame, primaryScreenHeight: primaryScreenHeight
            ).intersection(bounds)
            guard !local.isNull, local.width >= minimumSide, local.height >= minimumSide else { return nil }
            return local
        }
    }

    /// The first (frontmost) rect containing the point.
    public static func window(at point: CGPoint, in rects: [CGRect]) -> CGRect? {
        rects.first { $0.contains(point) }
    }
}
