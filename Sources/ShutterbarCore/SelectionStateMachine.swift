import CoreGraphics
import Foundation

/// Pure state machine for the overlay selection on a single screen. All coordinates are display-local points.
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
        /// ⌘C: copy the selection to the clipboard only.
        case copy
        /// 1…9, 0: the whole monitor at that position (0 = tenth). Zero-based index.
        case screen(Int)
        case arrow(dx: Int, dy: Int)
    }

    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// Shift: square while drawing, 10 px with arrow keys.
        public static let shift = Modifiers(rawValue: 1 << 0)
        /// ⌥: move the selection while drawing (Ctrl in ShareX).
        public static let move = Modifiers(rawValue: 1 << 1)
        /// ⌘: start a new selection even inside (or on a handle of) the current one.
        public static let newSelection = Modifiers(rawValue: 1 << 2)
    }

    public enum Output: Equatable, Sendable {
        case none
        case capture(CGRect)
        /// Region taken with ⌘C; clipboard only instead of the after-capture tasks.
        case copy(CGRect)
        case cancel
        case captureAllScreens
        case captureActiveScreen
        /// Zero-based index in `NSScreen.screens` order.
        case captureScreen(Int)
        /// Move the real cursor to this display-local point.
        case warpCursor(CGPoint)
    }

    public static let handleHitRadius: CGFloat = 6

    public let bounds: CGSize
    /// Pixels / point; the arrow key step is in pixels.
    public let pixelScale: CGFloat
    public var quickCapture: Bool

    public private(set) var selection: CGRect?
    /// Faint preview of the last region; accepted with Enter.
    public private(set) var preview: CGRect?
    public private(set) var phase: Phase = .idle
    public private(set) var cursor: CGPoint = .zero

    /// Windows at freeze time (display-local, front to back).
    public var windowRects: [CGRect] = [] {
        didSet { updateHover() }
    }
    /// In selection mode, highlight and pick windows too (the "Window detection" preference).
    public var snapsWindowsInSelection = true {
        didSet { updateHover() }
    }
    /// The overlay mode. Switching clears the selection.
    public var mode: CaptureMode = .selection {
        didSet {
            guard mode != oldValue else { return }
            selection = nil
            pickedWindow = nil
            phase = .idle
            if !mode.selectsRegion { preview = nil }
            updateHover()
        }
    }
    /// What a click would capture right now while there is no selection: a window (selection / window
    /// mode) or the whole screen (screen mode).
    public private(set) var hoveredWindow: CGRect?

    /// The selection is an unmodified window picked by clicking (not a drawn region). Such captures do not
    /// update the last region; moving, resizing or redrawing turns it into a region.
    public var selectionIsWindow: Bool {
        selection != nil && selection == pickedWindow
    }
    private var pickedWindow: CGRect?

    private var lastPoint: CGPoint = .zero
    /// Selection size when a move started; moving clips it to the screen without losing it.
    private var movingSize: CGSize = .zero
    private var modifiers: Modifiers = []

    public init(bounds: CGSize, pixelScale: CGFloat, quickCapture: Bool, preview: CGRect? = nil) {
        self.bounds = bounds
        self.pixelScale = pixelScale > 0 ? pixelScale : 1
        self.quickCapture = quickCapture
        if let preview, CaptureGeometry.fits(preview, in: bounds) {
            // With quick capture off, the preview comes in directly as an editable selection.
            if quickCapture {
                self.preview = preview
            } else {
                self.selection = preview
            }
        }
    }

    // MARK: Mouse

    public mutating func mouseMoved(to point: CGPoint) {
        cursor = CaptureGeometry.clamp(point, to: bounds)
        updateHover()
    }

    public mutating func mouseDown(at point: CGPoint, clickCount: Int = 1, modifiers: Modifiers = []) -> Output {
        let point = CaptureGeometry.clamp(point, to: bounds)
        cursor = point
        lastPoint = point
        self.modifiers = modifiers

        // Window and screen modes only react to clicks (on mouse up).
        guard mode.selectsRegion else { return .none }

        if !quickCapture, let selection, !modifiers.contains(.newSelection) {
            if clickCount >= 2, selection.contains(point) {
                return .capture(selection)
            }
            if let handle = handle(at: point) {
                phase = .resizing(handle, original: selection)
                return .none
            }
            if selection.contains(point) {
                phase = .moving(grabOffset: CGVector(dx: point.x - selection.minX, dy: point.y - selection.minY))
                movingSize = selection.size
                return .none
            }
        }
        phase = .drawing(anchor: point)
        return .none
    }

    public mutating func mouseDragged(to point: CGPoint, modifiers: Modifiers = []) {
        let previous = lastPoint
        let rawPoint = point
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
            guard selection != nil else { return }
            // Past the screen edge the selection is cut off instead of stopping, so a large selection can be pushed
            // out of the way (and fully off to remove it). Its size at grab time comes back when dragged back in.
            // The unclamped pointer is used so the selection can leave the screen entirely.
            let moved = CGRect(origin: CGPoint(x: rawPoint.x - offset.dx, y: rawPoint.y - offset.dy), size: movingSize)
            let visible = moved.intersection(CGRect(origin: .zero, size: bounds))
            self.selection = visible.isNull ? .zero : visible
        case .resizing(let handle, let original):
            selection = Self.resize(original, handle: handle, to: point)
        }
    }

    public mutating func mouseUp(at point: CGPoint) -> Output {
        switch mode {
        case .selection, .scrolling:
            break
        case .window:
            cursor = CaptureGeometry.clamp(point, to: bounds)
            guard let window = WindowSnap.window(at: cursor, in: windowRects) else { return .none }
            selection = window
            pickedWindow = window
            hoveredWindow = nil
            return .capture(window)
        case .screen:
            return .captureActiveScreen
        }

        mouseDragged(to: point, modifiers: modifiers)
        let finished = phase
        phase = .idle

        switch finished {
        case .drawing:
            guard let selection, !CaptureGeometry.isClick(selection) else {
                // Click: if there is a window under it, that window is selected; otherwise (with quick capture off) the old selection is cleared.
                if snapsWindowsInSelection, let window = WindowSnap.window(at: point, in: windowRects) {
                    self.selection = window
                    pickedWindow = window
                    hoveredWindow = nil
                    preview = nil
                    return quickCapture ? .capture(window) : .none
                }
                self.selection = nil
                updateHover()
                return .none
            }
            hoveredWindow = nil
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

    /// If Shift/⌥ changes while drawing, recompute the rect with the current cursor.
    public mutating func modifiersChanged(_ modifiers: Modifiers) {
        self.modifiers = modifiers
        if case .drawing(let anchor) = phase {
            updateDrawing(anchor: anchor)
        }
    }

    // MARK: Keyboard

    public mutating func key(_ key: Key, modifiers: Modifiers = []) -> Output {
        switch key {
        case .escape:
            return .cancel
        case .enter:
            if mode == .screen { return .captureActiveScreen }
            return acceptRect().map(Output.capture) ?? .none
        case .copy:
            return acceptRect().map(Output.copy) ?? .none
        case .delete:
            selection = nil
            phase = .idle
            updateHover()
            return .none
        case .space:
            return .captureAllScreens
        case .activeScreen:
            return .captureActiveScreen
        case .screen(let index):
            return index >= 0 ? .captureScreen(index) : .none
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

    /// Resets this screen's selection when a selection starts on another screen.
    public mutating func reset() {
        selection = nil
        pickedWindow = nil
        preview = nil
        phase = .idle
        hoveredWindow = nil
    }

    // MARK: Handles

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

    /// The rect Enter / ⌘C accepts: the drag must be finished; without a selection, the last region preview.
    private mutating func acceptRect() -> CGRect? {
        guard phase == .idle else { return nil }
        switch mode {
        case .selection, .scrolling:
            return selection ?? preview
        case .window, .screen:
            // Whole windows and screens are marked as picked so they don't replace the last region.
            guard let rect = mode == .window ? hoveredWindow : CGRect(origin: .zero, size: bounds) else { return nil }
            selection = rect
            pickedWindow = rect
            return rect
        }
    }

    private mutating func updateDrawing(anchor: CGPoint) {
        let rect = CaptureGeometry.rect(from: anchor, to: cursor, square: modifiers.contains(.shift), bounds: bounds)
        selection = rect
        preview = nil
        // The highlight goes away once a drag starts; it stays while the drag is small enough to count as a click.
        if !CaptureGeometry.isClick(rect) { hoveredWindow = nil }
    }

    /// Highlight only when there is no selection and the mouse is idle.
    private mutating func updateHover() {
        switch mode {
        case .selection, .scrolling:
            guard selection == nil, phase == .idle else { return }
            hoveredWindow = snapsWindowsInSelection ? WindowSnap.window(at: cursor, in: windowRects) : nil
        case .window:
            hoveredWindow = WindowSnap.window(at: cursor, in: windowRects)
        case .screen:
            hoveredWindow = CGRect(origin: .zero, size: bounds)
        }
    }
}
