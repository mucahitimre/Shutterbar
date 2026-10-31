import AppKit
import MacShotCore

/// The real implementation of the after-capture tasks.
@MainActor
final class CaptureOutput: AfterCaptureActions {
    private let namer = FileNamer()
    private let preferences: Preferences
    private let notifier = Notifier()
    private var warnedNoTasks = false
    /// Open editors; retained until they close.
    private var editors: [EditorWindowController] = []

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
    }

    /// Enter / Space / ~ / last region: the selected tasks. If the editor is selected, it opens first (single image only).
    func deliver(_ images: [CGImage], tasks: AfterCaptureTask? = nil) {
        let tasks = tasks ?? preferences.afterCaptureTasks
        guard tasks.contains(.annotate) else {
            run(tasks, images: images)
            return
        }
        guard images.count == 1, let image = images.first else {
            Log.output.info("Editor skipped: \(images.count) images (only a single image can be edited)")
            run(tasks, images: images)
            return
        }
        let editor = EditorWindowController(image: image)
        editors.append(editor)
        Task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-MacShotEditorSelfTest") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    editor.runSelfTest(snapshotTo: SaveFolder.defaultRoot.appendingPathComponent("debug-editor-window.png"))
                }
            }
            #endif
            let result = await editor.run()
            editors.removeAll { $0 === editor }
            switch result {
            case .done(let edited):
                run(tasks, images: [edited])
            case .copyOnly(let edited):
                copyOnly([edited])
            case .cancelled:
                Log.output.info("Editor cancelled; image discarded")
            }
        }
    }

    private func run(_ tasks: AfterCaptureTask, images: [CGImage]) {
        guard let report = AfterCaptureRunner.run(tasks, images: images, actions: self) else {
            Log.output.info("No after-capture task selected; image discarded")
            warnNoTasksOnce()
            return
        }
        if report.skipped.contains(.revealInFinder) {
            Log.output.info("Show in Finder skipped: no saved file")
        }
    }

    /// ⌘C: clipboard only; notifies on failure.
    func copyOnly(_ images: [CGImage]) {
        AfterCaptureRunner.run(.copyToClipboard, images: images, actions: self)
    }

    // MARK: AfterCaptureActions

    func save(_ images: [CGImage]) throws -> [URL] {
        do {
            return try SaveFolder.withRoot(bookmark: preferences.saveFolderBookmark) { try write(images, in: $0) }
        } catch let error as SaveFolder.FolderError {
            // R2.4: if the chosen folder is inaccessible, fall back to the default and warn the user.
            Log.output.error("Could not resolve save folder; falling back to default")
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
                Log.output.error("Could not save: \(url.path, privacy: .public) — \(error.localizedDescription, privacy: .public)")
                throw error
            }
            written.append(url)
            Log.output.info("Saved: \(url.path, privacy: .public) (\(image.width)×\(image.height) px)")
        }
        return written
    }

    func copy(_ images: [CGImage], savedURLs: [URL]) throws {
        try Clipboard.write(images, fileURLs: preferences.clipboardIncludesFileURL ? savedURLs : [])
        Log.output.info("Copied to clipboard: \(images.count) image(s)")
    }

    func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func notify(_ report: AfterCaptureReport, thumbnail: CGImage?) {
        let title = report.failures.isEmpty ? "\(AppInfo.name): captured" : "\(AppInfo.name): some tasks failed"
        notifier.post(title: title, body: report.summary, file: report.savedURLs.first, thumbnail: thumbnail)
    }

    /// R2.8: warn once per session; the settings window also shows a persistent warning.
    private func warnNoTasksOnce() {
        guard !warnedNoTasks else { return }
        warnedNoTasks = true
        let alert = NSAlert()
        alert.messageText = "No after-capture task selected"
        alert.informativeText = "The image was not sent anywhere. Select at least one task under After capture in the menu or in Settings."
        NSApp.activate()
        alert.runModal()
    }
}
