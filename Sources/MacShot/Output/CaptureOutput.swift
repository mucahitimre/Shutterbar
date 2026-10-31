import AppKit
import MacShotCore

/// After-capture task'larının gerçek uygulaması.
@MainActor
final class CaptureOutput: AfterCaptureActions {
    private let namer = FileNamer()
    private let preferences: Preferences
    private let notifier = Notifier()
    private var warnedNoTasks = false

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
    }

    /// Enter / Space / ~ / son bölge: seçili task'lar. Task yoksa uyarı.
    func deliver(_ images: [CGImage]) {
        guard let report = AfterCaptureRunner.run(preferences.afterCaptureTasks, images: images, actions: self) else {
            Log.output.info("Hiçbir after-capture task seçili değil; görüntü atıldı")
            warnNoTasksOnce()
            return
        }
        if report.skipped.contains(.revealInFinder) {
            Log.output.info("Finder'da göster atlandı: kayıtlı dosya yok")
        }
    }

    /// ⌘C: yalnız pano; hata olursa bildirim.
    func copyOnly(_ images: [CGImage]) {
        AfterCaptureRunner.run(.copyToClipboard, images: images, actions: self)
    }

    // MARK: AfterCaptureActions

    func save(_ images: [CGImage]) throws -> [URL] {
        do {
            return try SaveFolder.withRoot(bookmark: preferences.saveFolderBookmark) { try write(images, in: $0) }
        } catch let error as SaveFolder.FolderError {
            // R2.4: seçili klasör erişilemezse varsayılana dön ve kullanıcıyı uyar.
            Log.output.error("Kayıt klasörü çözülemedi; varsayılana dönülüyor")
            preferences.saveFolderBookmark = nil
            notifier.post(title: AppInfo.name, body: error.localizedDescription, file: nil)
            return try write(images, in: SaveFolder.defaultRoot)
        }
    }

    private func write(_ images: [CGImage], in root: URL) throws -> [URL] {
        let date = Date()
        var written: [URL] = []
        for image in images {
            let url = namer.fileURL(in: root, date: date) { url in
                FileManager.default.fileExists(atPath: url.path) || written.contains(url)
            }
            do {
                try PNGEncoder.write(image, to: url)
            } catch {
                Log.output.error("Kaydedilemedi: \(url.path, privacy: .public) — \(error.localizedDescription, privacy: .public)")
                throw error
            }
            written.append(url)
            Log.output.info("Kaydedildi: \(url.path, privacy: .public) (\(image.width)×\(image.height) px)")
        }
        return written
    }

    func copy(_ images: [CGImage]) throws {
        try Clipboard.write(images)
        Log.output.info("Panoya kopyalandı: \(images.count) görüntü")
    }

    func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func notify(_ report: AfterCaptureReport) {
        let title = report.failures.isEmpty ? "\(AppInfo.name): yakalandı" : "\(AppInfo.name): bazı işler başarısız"
        notifier.post(title: title, body: report.summary, file: report.savedURLs.first)
    }

    /// R2.8: uyarı oturum başına bir kez; ayarlar penceresinde kalıcı uyarı da var.
    private func warnNoTasksOnce() {
        guard !warnedNoTasks else { return }
        warnedNoTasks = true
        let alert = NSAlert()
        alert.messageText = "Hiçbir after-capture task seçili değil"
        alert.informativeText = "Görüntü hiçbir yere gitmedi. Menüdeki After capture'dan ya da ayarlardan en az bir task seç."
        NSApp.activate()
        alert.runModal()
    }
}
