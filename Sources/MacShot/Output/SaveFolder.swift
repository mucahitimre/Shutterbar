import AppKit

/// Kayıt kök klasörü: varsayılan `~/Pictures/<AppName>` ya da kullanıcının seçtiği klasör (security-scoped bookmark).
@MainActor
enum SaveFolder {
    enum FolderError: LocalizedError {
        case bookmarkStale

        var errorDescription: String? {
            "Seçili kayıt klasörüne erişilemiyor; ayarlardan yeniden seç"
        }
    }

    /// Gerçek `~/Pictures/<AppName>`; sandbox'ta `NSHomeDirectory()` container'ı gösterdiği için passwd'den okunur.
    static var defaultRoot: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent(AppInfo.name, isDirectory: true)
    }

    /// Ayarlarda gösterilecek yol.
    static func displayURL(bookmark: Data?) -> URL {
        guard let bookmark, let url = try? resolve(bookmark).url else { return defaultRoot }
        return url
    }

    /// Kök klasörde çalışır; seçili klasör için erişimi açar ve iş bitince kapatır.
    static func withRoot<T>(bookmark: Data?, _ body: (URL) throws -> T) throws -> T {
        guard let bookmark else { return try body(defaultRoot) }
        let (url, stale) = try resolve(bookmark)
        guard url.startAccessingSecurityScopedResource() else { throw FolderError.bookmarkStale }
        defer { url.stopAccessingSecurityScopedResource() }
        if stale {
            Preferences.shared.saveFolderBookmark = try? makeBookmark(for: url)
        }
        return try body(url)
    }

    /// Klasör seçici; iptal edilirse `nil`.
    static func choose(current: URL) -> Data? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = current
        panel.prompt = "Seç"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            return try makeBookmark(for: url)
        } catch {
            Log.output.error("Bookmark oluşturulamadı: \(error.localizedDescription, privacy: .public)")
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
