import CoreGraphics

/// Overlay'de imlecin altındaki pencereyi bulur (ShareX "DetectWindows").
public enum WindowSnap {
    /// Dondurma anındaki pencere bilgisi. `frame` Quartz global.
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

    /// Normal pencereler ve floating / modal paneller. Dock (20) tüm ekranı kaplayan şeffaf bir pencere tuttuğu,
    /// menü çubuğu (24+) da istenmediği için hariç.
    public static let maxLayer = 19
    public static let minimumSide: CGFloat = 20

    /// Önden arkaya sıralı pencerelerden bu ekrana düşenleri display-local rect olarak verir (sıra korunur).
    /// Kendi pencerelerimiz, çok küçükler ve menü çubuğu katmanı elenir; rect ekran sınırına kırpılır.
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

    /// İlk (en öndeki) içeren rect.
    public static func window(at point: CGPoint, in rects: [CGRect]) -> CGRect? {
        rects.first { $0.contains(point) }
    }
}
