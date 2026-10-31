import Foundation
import MacShotCore

/// User preferences stored in UserDefaults. The menu and settings share the same object.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let afterCaptureTasks = "afterCaptureTasks"
        static let saveFolderBookmark = "saveFolderBookmark"
        static let quickCapture = "quickCapture"
        static let magnifier = "magnifier"
        static let magnifierPixelCount = "magnifierPixelCount"
        static let clipboardIncludesFileURL = "clipboardIncludesFileURL"
        static let windowSnap = "windowSnap"
        static let captureMode = "captureMode"
        static let captureTimer = "captureTimer"
        static let showFloatingThumbnail = "showFloatingThumbnail"
        static let rememberLastSelection = "rememberLastSelection"
        static let playSound = "playSound"
    }

    private let defaults: UserDefaults

    @Published var afterCaptureTasks: AfterCaptureTask {
        didSet { defaults.set(afterCaptureTasks.rawValue, forKey: Key.afterCaptureTasks) }
    }

    /// Capture as soon as the mouse is released. When off, the selection can be edited until Enter / ⌘C.
    @Published var quickCapture: Bool {
        didSet { defaults.set(quickCapture, forKey: Key.quickCapture) }
    }

    @Published var magnifier: Bool {
        didSet { defaults.set(magnifier, forKey: Key.magnifier) }
    }

    /// Number of pixels along the magnifier's edge; changed with the mouse wheel in the overlay.
    @Published var magnifierPixelCount: Int {
        didSet { defaults.set(magnifierPixelCount, forKey: Key.magnifierPixelCount) }
    }

    /// Highlight the window under the cursor in the overlay; clicking selects that window.
    @Published var windowSnap: Bool {
        didSet { defaults.set(windowSnap, forKey: Key.windowSnap) }
    }

    /// Add the file URL to the clipboard when saving is also on (off by default: image only).
    @Published var clipboardIncludesFileURL: Bool {
        didSet { defaults.set(clipboardIncludesFileURL, forKey: Key.clipboardIncludesFileURL) }
    }

    /// Overlay mode chosen in the capture toolbar; remembered for the next capture.
    @Published var captureMode: CaptureMode {
        didSet { defaults.set(captureMode.rawValue, forKey: Key.captureMode) }
    }

    /// Delay between confirming a capture and taking it (the region is captured live after the countdown).
    @Published var captureTimer: CaptureTimer {
        didSet { defaults.set(captureTimer.rawValue, forKey: Key.captureTimer) }
    }

    /// Show the capture thumbnail in the corner of the screen afterwards.
    @Published var showFloatingThumbnail: Bool {
        didSet { defaults.set(showFloatingThumbnail, forKey: Key.showFloatingThumbnail) }
    }

    /// Preview the last region in the overlay (the ⌥⇧5 shortcut works regardless).
    @Published var rememberLastSelection: Bool {
        didSet { defaults.set(rememberLastSelection, forKey: Key.rememberLastSelection) }
    }

    /// Play the system screenshot sound.
    @Published var playSound: Bool {
        didSet { defaults.set(playSound, forKey: Key.playSound) }
    }

    /// Security-scoped bookmark of the folder the user chose; if nil, the default folder.
    @Published var saveFolderBookmark: Data? {
        didSet { defaults.set(saveFolderBookmark, forKey: Key.saveFolderBookmark) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.afterCaptureTasks: AfterCaptureTask.defaults.rawValue,
            Key.quickCapture: false,
            Key.magnifier: true,
            Key.magnifierPixelCount: 15,
            Key.clipboardIncludesFileURL: false,
            Key.windowSnap: true,
            Key.captureMode: CaptureMode.selection.rawValue,
            Key.captureTimer: CaptureTimer.none.rawValue,
            Key.showFloatingThumbnail: true,
            Key.rememberLastSelection: true,
            Key.playSound: true,
        ])
        afterCaptureTasks = AfterCaptureTask(rawValue: defaults.integer(forKey: Key.afterCaptureTasks))
        quickCapture = defaults.bool(forKey: Key.quickCapture)
        magnifier = defaults.bool(forKey: Key.magnifier)
        magnifierPixelCount = defaults.integer(forKey: Key.magnifierPixelCount)
        clipboardIncludesFileURL = defaults.bool(forKey: Key.clipboardIncludesFileURL)
        windowSnap = defaults.bool(forKey: Key.windowSnap)
        captureMode = defaults.string(forKey: Key.captureMode).flatMap(CaptureMode.init(rawValue:)) ?? .selection
        captureTimer = CaptureTimer(rawValue: defaults.integer(forKey: Key.captureTimer)) ?? .none
        showFloatingThumbnail = defaults.bool(forKey: Key.showFloatingThumbnail)
        rememberLastSelection = defaults.bool(forKey: Key.rememberLastSelection)
        playSound = defaults.bool(forKey: Key.playSound)
        saveFolderBookmark = defaults.data(forKey: Key.saveFolderBookmark)
    }

    func toggle(_ task: AfterCaptureTask) {
        if afterCaptureTasks.contains(task) {
            afterCaptureTasks.remove(task)
        } else {
            afterCaptureTasks.insert(task)
        }
    }
}
