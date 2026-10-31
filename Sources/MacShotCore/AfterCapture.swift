import CoreGraphics
import Foundation

/// Yakalamadan sonra çalışacak işler. Ham değer UserDefaults'ta saklanır; bitleri değiştirme.
public struct AfterCaptureTask: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let saveToFile = AfterCaptureTask(rawValue: 1 << 0)
    public static let copyToClipboard = AfterCaptureTask(rawValue: 1 << 1)
    public static let showNotification = AfterCaptureTask(rawValue: 1 << 2)
    public static let revealInFinder = AfterCaptureTask(rawValue: 1 << 3)

    public static let defaults: AfterCaptureTask = [.saveToFile, .copyToClipboard]

    /// Çalışma sırası: kaydet → pano → Finder → bildirim.
    public static let ordered: [AfterCaptureTask] = [.saveToFile, .copyToClipboard, .revealInFinder, .showNotification]

    public var title: String {
        switch self {
        case .saveToFile: "Dosyaya kaydet"
        case .copyToClipboard: "Panoya kopyala"
        case .showNotification: "Bildirim göster"
        case .revealInFinder: "Finder'da göster"
        default: "?"
        }
    }
}

/// Runner'ın dış dünyaya dokunduğu yerler; uygulama gerçeğini, testler sahtesini verir.
@MainActor
public protocol AfterCaptureActions {
    func save(_ images: [CGImage]) throws -> [URL]
    func copy(_ images: [CGImage]) throws
    func reveal(_ urls: [URL])
    func notify(_ report: AfterCaptureReport)
}

public struct AfterCaptureFailure: Equatable, Sendable {
    public let task: AfterCaptureTask
    public let message: String

    public init(task: AfterCaptureTask, message: String) {
        self.task = task
        self.message = message
    }
}

public struct AfterCaptureReport: Equatable, Sendable {
    public var tasks: AfterCaptureTask
    public var imageCount: Int
    public var savedURLs: [URL] = []
    public var copied = false
    public var failures: [AfterCaptureFailure] = []
    /// Ön koşulu olmadığı için çalışmayan task'lar (ör. kayıt yokken Finder); hata sayılmaz.
    public var skipped: AfterCaptureTask = []

    public init(tasks: AfterCaptureTask, imageCount: Int) {
        self.tasks = tasks
        self.imageCount = imageCount
    }

    /// Bildirim metni: başarıları ve hataları tek mesajda toplar.
    public var summary: String {
        var parts: [String] = []
        if let first = savedURLs.first {
            parts.append(savedURLs.count == 1 ? "Kaydedildi: \(first.lastPathComponent)" : "\(savedURLs.count) dosya kaydedildi")
        }
        if copied { parts.append("Panoya kopyalandı") }
        for failure in failures {
            parts.append("\(failure.task.title) başarısız: \(failure.message)")
        }
        return parts.isEmpty ? "Yakalandı" : parts.joined(separator: "\n")
    }
}

@MainActor
public enum AfterCaptureRunner {
    /// Her task kendi hatasını yakalar; biri düşse de sıradaki çalışır.
    /// Bildirim seçili değilse bile hata varsa bir kez bildirilir.
    /// Seçili task yoksa `nil` döner (çağıran uyarır).
    @discardableResult
    public static func run(_ tasks: AfterCaptureTask, images: [CGImage], actions: some AfterCaptureActions) -> AfterCaptureReport? {
        guard !tasks.isEmpty else { return nil }
        var report = AfterCaptureReport(tasks: tasks, imageCount: images.count)

        for task in AfterCaptureTask.ordered where tasks.contains(task) {
            switch task {
            case .saveToFile:
                do {
                    report.savedURLs = try actions.save(images)
                } catch {
                    report.failures.append(.init(task: task, message: error.localizedDescription))
                }
            case .copyToClipboard:
                do {
                    try actions.copy(images)
                    report.copied = true
                } catch {
                    report.failures.append(.init(task: task, message: error.localizedDescription))
                }
            case .revealInFinder:
                if report.savedURLs.isEmpty {
                    report.skipped.insert(task)
                } else {
                    actions.reveal(report.savedURLs)
                }
            default:
                break
            }
        }

        if tasks.contains(.showNotification) || !report.failures.isEmpty {
            actions.notify(report)
        }
        return report
    }
}
