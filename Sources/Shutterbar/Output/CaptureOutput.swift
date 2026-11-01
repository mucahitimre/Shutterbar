import AppKit
import ShutterbarCore

/// The real implementation of the after-capture tasks.
@MainActor
final class CaptureOutput: AfterCaptureActions {
    private let namer = FileNamer()
    private let preferences: Preferences
    private let notifier = Notifier()
    private var warnedNoTasks = false
    /// Open editors; retained until they close.
    private var editors: [EditorWindowController] = []
    private var thumbnail: ThumbnailPanel?

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
        openEditor(image) { [weak self] result in
            switch result {
            case .done(let edited): self?.run(tasks, images: [edited])
            case .copyOnly(let edited): self?.copyOnly([edited])
            case .cancelled: Log.output.info("Editor cancelled; image discarded")
            }
        }
    }

    private func openEditor(_ image: CGImage, completion: @escaping (EditorWindowController.Result) -> Void) {
        let editor = EditorWindowController(image: image)
        editors.append(editor)
        Task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ShutterbarEditorSelfTest") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    editor.runSelfTest(snapshotTo: SaveFolder.defaultRoot.appendingPathComponent("debug-editor-window.png"))
                }
            }
            #endif
            let result = await editor.run()
            editors.removeAll { $0 === editor }
            completion(result)
        }
    }

    private func run(_ tasks: AfterCaptureTask, images: [CGImage]) {
        let report = AfterCaptureRunner.run(tasks, images: images, actions: self)
        if report == nil {
            Log.output.info("No after-capture task selected; only the thumbnail is shown")
            warnNoTasksOnce()
        } else if report?.skipped.contains(.revealInFinder) == true {
            Log.output.info("Show in Finder skipped: no saved file")
        }
        if let image = images.last {
            showThumbnail(image, fileURL: report?.savedURLs.last, tasks: tasks)
        }
    }

    /// ⌘C: clipboard only; notifies on failure.
    func copyOnly(_ images: [CGImage]) {
        AfterCaptureRunner.run(.copyToClipboard, images: images, actions: self)
        if let image = images.last {
            showThumbnail(image, fileURL: nil, tasks: .copyToClipboard)
        }
    }

    // MARK: Floating thumbnail

    private func showThumbnail(_ image: CGImage, fileURL: URL?, tasks: AfterCaptureTask) {
        guard preferences.showFloatingThumbnail else { return }
        thumbnail?.dismiss()
        let panel = ThumbnailPanel(image: image, fileURL: fileURL, actions: .init(
            edit: { [weak self] in self?.reedit(image, fileURL: fileURL, tasks: tasks) },
            showInFinder: fileURL.map { url in { NSWorkspace.shared.activateFileViewerSelecting([url]) } },
            copy: { [weak self] in
                guard let self else { return }
                try? Clipboard.write([image], fileURLs: self.preferences.clipboardIncludesFileURL ? (fileURL.map { [$0] } ?? []) : [])
                Log.output.info("Thumbnail copied to clipboard")
            }
        ))
        thumbnail = panel
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        panel.present(on: screen) { [weak self, weak panel] in
            if self?.thumbnail === panel { self?.thumbnail = nil }
        }
    }

    /// Editing from the thumbnail: the saved file is replaced, the clipboard / notification run again.
    private func reedit(_ image: CGImage, fileURL: URL?, tasks: AfterCaptureTask) {
        openEditor(image) { [weak self] result in
            guard let self else { return }
            switch result {
            case .done(let edited):
                if let fileURL {
                    do {
                        try PNGEncoder.write(edited, to: fileURL, overwrite: true)
                        Log.output.info("Replaced with edited image: \(fileURL.path, privacy: .public)")
                    } catch {
                        Log.output.error("Could not replace \(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                }
                AfterCaptureRunner.run(tasks.intersection([.copyToClipboard, .showNotification]), images: [edited], actions: self)
            case .copyOnly(let edited):
                AfterCaptureRunner.run(.copyToClipboard, images: [edited], actions: self)
            case .cancelled:
                break
            }
        }
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
