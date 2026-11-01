import CoreGraphics
import Foundation

/// Tasks that run after a capture. The raw value is stored in UserDefaults; do not change the bits.
public struct AfterCaptureTask: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let saveToFile = AfterCaptureTask(rawValue: 1 << 0)
    public static let copyToClipboard = AfterCaptureTask(rawValue: 1 << 1)
    public static let showNotification = AfterCaptureTask(rawValue: 1 << 2)
    public static let revealInFinder = AfterCaptureTask(rawValue: 1 << 3)
    /// Opens the editor before the other tasks; they then run with the edited image. The runner does not run this one.
    public static let annotate = AfterCaptureTask(rawValue: 1 << 4)

    public static let defaults: AfterCaptureTask = [.saveToFile, .copyToClipboard]

    /// Run order: (editor) → save → clipboard → Finder → notification.
    public static let ordered: [AfterCaptureTask] = [.annotate, .saveToFile, .copyToClipboard, .revealInFinder, .showNotification]

    public var title: String {
        switch self {
        case .saveToFile: "Save to file"
        case .copyToClipboard: "Copy to clipboard"
        case .showNotification: "Show notification"
        case .revealInFinder: "Show in Finder"
        case .annotate: "Open annotation editor"
        default: "?"
        }
    }
}

/// Where the runner touches the outside world; the app provides the real one, tests provide a fake.
@MainActor
public protocol AfterCaptureActions {
    func save(_ images: [CGImage]) throws -> [URL]
    /// - Parameter savedURLs: files saved in the same run (empty if saving is off).
    func copy(_ images: [CGImage], savedURLs: [URL]) throws
    func reveal(_ urls: [URL])
    /// - Parameter thumbnail: the first image, shown in the notification.
    func notify(_ report: AfterCaptureReport, thumbnail: CGImage?)
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
    /// Tasks that did not run because their precondition was missing (e.g. Finder without a save); not counted as failures.
    public var skipped: AfterCaptureTask = []

    public init(tasks: AfterCaptureTask, imageCount: Int) {
        self.tasks = tasks
        self.imageCount = imageCount
    }

    /// Notification text: combines successes and failures into a single message.
    public var summary: String {
        var parts: [String] = []
        if let first = savedURLs.first {
            parts.append(savedURLs.count == 1 ? "Saved: \(first.lastPathComponent)" : "Saved \(savedURLs.count) files")
        }
        if copied { parts.append("Copied to clipboard") }
        for failure in failures {
            parts.append("\(failure.task.title) failed: \(failure.message)")
        }
        return parts.isEmpty ? "Captured" : parts.joined(separator: "\n")
    }
}

@MainActor
public enum AfterCaptureRunner {
    /// Each task catches its own error; if one fails, the next still runs.
    /// Even if notification is not selected, failures are notified once.
    /// Returns `nil` if no task is selected (the caller warns).
    @discardableResult
    public static func run(_ tasks: AfterCaptureTask, images: [CGImage], actions: some AfterCaptureActions) -> AfterCaptureReport? {
        let tasks = tasks.subtracting(.annotate)
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
                    try actions.copy(images, savedURLs: report.savedURLs)
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
            actions.notify(report, thumbnail: images.first)
        }
        return report
    }
}
