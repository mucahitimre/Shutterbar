import AppKit
import MacShotCore

/// Kesilmiş görüntüleri çıktıya verir. F1: yalnız varsayılan klasöre PNG kaydı (sabit task).
@MainActor
final class CaptureOutput {
    private let namer = FileNamer()

    /// Gerçek `~/Pictures/<AppName>`; sandbox'ta `NSHomeDirectory()` container'ı gösterdiği için passwd'den okunur.
    static var defaultRoot: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent(AppInfo.name, isDirectory: true)
    }

    @discardableResult
    func deliver(_ images: [CGImage]) -> [URL] {
        let date = Date()
        var written: [URL] = []
        for image in images {
            let url = namer.fileURL(in: Self.defaultRoot, date: date) { url in
                FileManager.default.fileExists(atPath: url.path) || written.contains(url)
            }
            do {
                try PNGEncoder.write(image, to: url)
                written.append(url)
                Log.output.info("Kaydedildi: \(url.path, privacy: .public) (\(image.width)×\(image.height) px)")
            } catch {
                Log.output.error("Kaydedilemedi: \(url.path, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            }
        }
        return written
    }
}
