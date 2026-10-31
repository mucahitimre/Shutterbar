import AppKit
import MacShotCore

/// After-capture task'larının gerçek uygulaması.
@MainActor
final class CaptureOutput: AfterCaptureActions {
    private let namer = FileNamer()
    private let preferences: Preferences
    private let notifier = Notifier()

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
    }

    /// Enter / Space / ~ / son bölge: seçili task'lar. Task yoksa uyarı.
    func deliver(_ images: [CGImage]) {
        guard AfterCaptureRunner.run(preferences.afterCaptureTasks, images: images, actions: self) != nil else {
            Log.output.info("After-capture task'ı seçili değil; görüntü atıldı")
            warnNoTasks()
            return
        }
    }

    /// ⌘C: yalnız pano; hata olursa bildirim.
    func copyOnly(_ images: [CGImage]) {
        AfterCaptureRunner.run(.copyToClipboard, images: images, actions: self)
    }

    // MARK: AfterCaptureActions

    func save(_ images: [CGImage]) throws -> [URL] {
        let date = Date()
        return try SaveFolder.withRoot(bookmark: preferences.saveFolderBookmark) { root in
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

    private func warnNoTasks() {
        let alert = NSAlert()
        alert.messageText = "After-capture task'ı seçili değil"
        alert.informativeText = "Görüntü hiçbir yere kaydedilmedi. Menüden ya da ayarlardan en az bir task seç."
        NSApp.activate()
        alert.runModal()
    }
}
