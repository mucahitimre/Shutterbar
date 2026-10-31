import AppKit

/// Root save folder: the default `~/Pictures/<AppName>` or a folder the user chose (security-scoped bookmark).
@MainActor
enum SaveFolder {
    enum FolderError: LocalizedError {
        case bookmarkStale

        var errorDescription: String? {
            "Could not access the chosen save folder; reverted to the default folder"
        }
    }

    /// The real `~/Pictures/<AppName>`; read from passwd because in the sandbox `NSHomeDirectory()` points to the container.
    static var defaultRoot: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent(AppInfo.name, isDirectory: true)
    }

    /// Path to show in Settings.
    static func displayURL(bookmark: Data?) -> URL {
        guard let bookmark, let url = try? resolve(bookmark).url else { return defaultRoot }
        return url
    }

    /// Runs in the root folder; for a chosen folder, starts access and stops it when done.
    /// Throws `FolderError.bookmarkStale` if the bookmark cannot be resolved; the caller falls back to the default.
    static func withRoot<T>(bookmark: Data?, _ body: (URL) throws -> T) throws -> T {
        guard let bookmark else { return try body(defaultRoot) }
        let url: URL, stale: Bool
        do {
            (url, stale) = try resolve(bookmark)
        } catch {
            throw FolderError.bookmarkStale
        }
        // Outside the sandbox no access grant is needed; inside it, failing to start access means the folder is gone.
        let accessing = url.startAccessingSecurityScopedResource()
        guard accessing || !Channel.isSandboxed else { throw FolderError.bookmarkStale }
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if stale {
            Preferences.shared.saveFolderBookmark = try? makeBookmark(for: url)
        }
        return try body(url)
    }

    /// Folder picker; `nil` if cancelled.
    static func choose(current: URL) -> Data? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = current
        panel.prompt = "Choose"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            return try makeBookmark(for: url)
        } catch {
            Log.output.error("Could not create bookmark: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private static func resolve(_ bookmark: Data) throws -> (url: URL, stale: Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }
}
