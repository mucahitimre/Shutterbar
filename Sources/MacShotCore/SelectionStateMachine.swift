import CoreGraphics
import Foundation

/// Tek bir ekrandaki overlay seçiminin saf durum makinesi. Tüm koordinatlar display-local point.
public struct SelectionStateMachine: Sendable {
    public enum Handle: CaseIterable, Sendable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case drawing(anchor: CGPoint)
        case moving(grabOffset: CGVector)
        case resizing(Handle, original: CGRect)
    }

    public enum Key: Equatable, Sendable {
        case escape, enter, delete, space, activeScreen
        /// ⌘C: seçimi yalnız panoya al.
        case copy
        case arrow(dx: Int, dy: Int)
    }

    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// Shift: çizerken kare, okla 10 px.
        public static let shift = Modifiers(rawValue: 1 << 0)
        /// ⌥: çizerken seçimi taşı (ShareX'teki Ctrl).
        public static let move = Modifiers(rawValue: 1 << 1)
    }

    public enum Output: Equatable, Sendable {
        case none
        case capture(CGRect)
        /// ⌘C ile alınan bölge; after-capture task'ları yerine yalnız pano.
        case copy(CGRect)
        case cancel
        case captureAllScreens
        case captureActiveScreen
        /// Gerçek imleci bu display-local noktaya taşı.
        case warpCursor(CGPoint)
    }

    public static let handleHitRadius: CGFloat = 6

    public let bounds: CGSize
    /// Piksel / point; ok tuşu adımı piksel cinsindendir.
    public let pixelScale: CGFloat
    public var quickCapture: Bool

    public private(set) var selection: CGRect?
    /// Son bölgenin soluk ön çizimi; Enter ile kabul edilir.
    public private(set) var preview: CGRect?
    public private(set) var phase: Phase = .idle
    public private(set) var cursor: CGPoint = .zero

    private var lastPoint: CGPoint = .zero
    private var modifiers: Modifiers = []

    public init(bounds: CGSize, pixelScale: CGFloat, quickCapture: Bool, preview: CGRect? = nil) {
        self.bounds = bounds
        self.pixelScale = pixelScale > 0 ? pixelScale : 1
        self.quickCapture = quickCapture
        if let preview, CaptureGeometry.fits(preview, in: bounds) {
            // Quick capture kapalıyken ön çizim doğrudan düzenlenebilir seçim olarak gelir.
            if quickCapture {
                self.preview = preview
            } else {
                self.selection = preview
            }
        }
    }

    // MARK: Fare

    public mutating func mouseMoved(to point: CGPoint) {
        cursor = CaptureGeometry.clamp(point, to: bounds)
    }

    public mutating func mouseDown(at point: CGPoint, clickCount: Int = 1, modifiers: Modifiers = []) -> Output {
        let point = CaptureGeometry.clamp(point, to: bounds)
        cursor = point
        lastPoint = point
        self.modifiers = modifiers

        if !quickCapture, let selection {
            if clickCount >= 2, selection.contains(point) {
                return .capture(selection)
            }
            if let handle = handle(at: point) {
                phase = .resizing(handle, original: selection)
                return .none
            }
            if selection.contains(point) {
                phase = .moving(grabOffset: CGVector(dx: point.x - selection.minX, dy: point.y - selection.minY))
                return .none
            }
        }
        phase = .drawing(anchor: point)
        return .none
    }

    public mutating func mouseDragged(to point: CGPoint, modifiers: Modifiers = []) {
        let previous = lastPoint
        let point = CaptureGeometry.clamp(point, to: bounds)
        cursor = point
        lastPoint = point
        self.modifiers = modifiers

        switch phase {
        case .idle:
            break
        case .drawing(var anchor):
            if modifiers.contains(.move) {
                anchor = CaptureGeometry.clamp(
                    CGPoint(x: anchor.x + point.x - previous.x, y: anchor.y + point.y - previous.y),
                    to: bounds
                )
                phase = .drawing(anchor: anchor)
            }
            updateDrawing(anchor: anchor)
        case .moving(let offset):
            guard let selection else { return }
            let moved = CGRect(x: point.x - offset.dx, y: point.y - offset.dy, width: selection.width, height: selection.height)
            self.selection = CaptureGeometry.keepInside(moved, bounds: bounds)
        case .resizing(let handle, let original):
            selection = Self.resize(original, handle: handle, to: point)
        }
    }

    public mutating func mouseUp(at point: CGPoint) -> Output {
        mouseDragged(to: point, modifiers: modifiers)
        let finished = phase
        phase = .idle

        switch finished {
        case .drawing:
            guard let selection, !CaptureGeometry.isClick(selection) else {
                // Tıklama: yeni seçim yok; quick capture kapalıyken eski seçim de temizlenir.
                self.selection = nil
                return .none
            }
            return quickCapture ? .capture(selection) : .none
        case .moving, .resizing:
            if let selection, CaptureGeometry.isClick(selection) {
                self.selection = nil
            }
            return .none
        case .idle:
            return .none
        }
    }

    public mutating func rightMouseDown() -> Output {
        .cancel
    }

    /// Shift/⌥ çizim sırasında değişirse rect'i güncel imleçle yeniden hesapla.
    public mutating func modifiersChanged(_ modifiers: Modifiers) {
        self.modifiers = modifiers
        if case .drawing(let anchor) = phase {
            updateDrawing(anchor: anchor)
        }
    }

    // MARK: Klavye

    public mutating func key(_ key: Key, modifiers: Modifiers = []) -> Output {
        switch key {
        case .escape:
            return .cancel
        case .enter:
            return acceptedRect.map(Output.capture) ?? .none
        case .copy:
            return acceptedRect.map(Output.copy) ?? .none
        case .delete:
            selection = nil
            phase = .idle
            return .none
        case .space:
            return .captureAllScreens
        case .activeScreen:
            return .captureActiveScreen
        case .arrow(let dx, let dy):
            let step = (modifiers.contains(.shift) ? 10 : 1) / pixelScale
            let delta = CGVector(dx: CGFloat(dx) * step, dy: CGFloat(dy) * step)
            if phase == .idle, let selection {
                self.selection = CaptureGeometry.keepInside(selection.offsetBy(dx: delta.dx, dy: delta.dy), bounds: bounds)
                return .none
            }
            cursor = CaptureGeometry.clamp(CGPoint(x: cursor.x + delta.dx, y: cursor.y + delta.dy), to: bounds)
            lastPoint = cursor
            if case .drawing(let anchor) = phase {
                updateDrawing(anchor: anchor)
            }
            return .warpCursor(cursor)
        }
    }

    /// Diğer ekranda seçim başladığında bu ekranın seçimini sıfırlar.
    public mutating func reset() {
        selection = nil
        preview = nil
        phase = .idle
    }

    // MARK: Tutamaçlar

    public static func handlePoint(_ handle: Handle, of rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    public func handle(at point: CGPoint) -> Handle? {
        guard let selection else { return nil }
        return Handle.allCases.first { handle in
            let p = Self.handlePoint(handle, of: selection)
            return abs(p.x - point.x) <= Self.handleHitRadius && abs(p.y - point.y) <= Self.handleHitRadius
        }
    }

    static func resize(_ rect: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
        var x1 = rect.minX, x2 = rect.maxX, y1 = rect.minY, y2 = rect.maxY
        switch handle {
        case .topLeft: x1 = point.x; y1 = point.y
        case .top: y1 = point.y
        case .topRight: x2 = point.x; y1 = point.y
        case .right: x2 = point.x
        case .bottomRight: x2 = point.x; y2 = point.y
        case .bottom: y2 = point.y
        case .bottomLeft: x1 = point.x; y2 = point.y
        case .left: x1 = point.x
        }
        return CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
    }

    /// Enter / ⌘C'nin kabul edeceği rect: sürükleme bitmiş olmalı; seçim yoksa son bölge ön çizimi.
    private var acceptedRect: CGRect? {
        guard phase == .idle else { return nil }
        return selection ?? preview
    }

    private mutating func updateDrawing(anchor: CGPoint) {
        let rect = CaptureGeometry.rect(from: anchor, to: cursor, square: modifiers.contains(.shift), bounds: bounds)
        selection = rect
        preview = nil
    }
}
