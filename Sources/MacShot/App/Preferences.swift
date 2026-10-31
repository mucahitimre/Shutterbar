import Foundation
import MacShotCore

/// UserDefaults'ta tutulan kullanıcı tercihleri. Menü ve ayarlar aynı nesneyi paylaşır.
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

    /// Fareyi bırakınca hemen yakala. Kapalıyken seçim Enter / ⌘C'ye kadar düzenlenebilir.
    @Published var quickCapture: Bool {
        didSet { defaults.set(quickCapture, forKey: Key.quickCapture) }
    }

    @Published var magnifier: Bool {
        didSet { defaults.set(magnifier, forKey: Key.magnifier) }
    }

    /// Büyütecin kenarındaki piksel sayısı; overlay'de tekerlekle değişir.
    @Published var magnifierPixelCount: Int {
        didSet { defaults.set(magnifierPixelCount, forKey: Key.magnifierPixelCount) }
    }

    /// Overlay'de imlecin altındaki pencereyi vurgula; tıklayınca o pencereyi seç.
    @Published var windowSnap: Bool {
        didSet { defaults.set(windowSnap, forKey: Key.windowSnap) }
    }

    /// Kayıt da açıksa panoya dosya URL'si ekle (varsayılan kapalı: yalnız görüntü).
    @Published var clipboardIncludesFileURL: Bool {
        didSet { defaults.set(clipboardIncludesFileURL, forKey: Key.clipboardIncludesFileURL) }
    }

    /// Kullanıcının seçtiği klasörün security-scoped bookmark'ı; yoksa varsayılan klasör.
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
