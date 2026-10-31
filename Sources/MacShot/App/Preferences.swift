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
        ])
        afterCaptureTasks = AfterCaptureTask(rawValue: defaults.integer(forKey: Key.afterCaptureTasks))
        quickCapture = defaults.bool(forKey: Key.quickCapture)
        magnifier = defaults.bool(forKey: Key.magnifier)
        magnifierPixelCount = defaults.integer(forKey: Key.magnifierPixelCount)
        clipboardIncludesFileURL = defaults.bool(forKey: Key.clipboardIncludesFileURL)
        windowSnap = defaults.bool(forKey: Key.windowSnap)
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
