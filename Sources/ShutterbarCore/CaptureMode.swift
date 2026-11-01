import Foundation

/// What a click or drag in the overlay captures, like the modes in macOS's screenshot toolbar.
public enum CaptureMode: String, CaseIterable, Sendable {
    /// Drag a region (clicking a detected window still selects it when window detection is on).
    case selection
    /// Hover highlights a window, click captures it.
    case window
    /// Hover highlights the whole screen, click captures it.
    case screen
    /// Select a region like `selection`; capturing starts a scrolling session that stitches frames while the user scrolls.
    case scrolling

    /// Modes where a region is dragged (or a window clicked) and edited before capturing.
    public var selectsRegion: Bool { self == .selection || self == .scrolling }

    public var title: String {
        switch self {
        case .selection: "Capture Selected Portion"
        case .window: "Capture Selected Window"
        case .screen: "Capture Entire Screen"
        case .scrolling: "Capture Scrolling Region"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .selection: "rectangle.dashed"
        case .window: "macwindow"
        case .screen: "rectangle.inset.filled"
        case .scrolling: "scroll"
        }
    }
}

/// Self-timer choices offered in the capture toolbar.
public enum CaptureTimer: Int, CaseIterable, Sendable {
    case none = 0
    case five = 5
    case ten = 10

    public var title: String {
        self == .none ? "None" : "\(rawValue) Seconds"
    }
}
