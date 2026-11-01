import CoreGraphics
import Foundation
import ShutterbarCore
import Testing

private struct Boom: LocalizedError {
    var errorDescription: String? { "boom" }
}

@MainActor
private final class MockActions: AfterCaptureActions {
    var calls: [String] = []
    var failSave = false
    var failCopy = false
    var notified: AfterCaptureReport?
    var copiedWithURLs: [URL] = []
    var thumbnail: CGImage?

    func save(_ images: [CGImage]) throws -> [URL] {
        calls.append("save")
        if failSave { throw Boom() }
        return images.indices.map { URL(fileURLWithPath: "/tmp/shot\($0).png") }
    }

    func copy(_ images: [CGImage], savedURLs: [URL]) throws {
        calls.append("copy")
        copiedWithURLs = savedURLs
        if failCopy { throw Boom() }
    }

    func reveal(_ urls: [URL]) {
        calls.append("reveal")
    }

    func notify(_ report: AfterCaptureReport, thumbnail: CGImage?) {
        calls.append("notify")
        notified = report
        self.thumbnail = thumbnail
    }
}

@MainActor
struct AfterCaptureRunnerTests {
    let image: CGImage = {
        let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }()

    @Test func defaultsAreSaveAndCopy() {
        #expect(AfterCaptureTask.defaults == [.saveToFile, .copyToClipboard])
    }

    @Test func runsInFixedOrder() {
        let mock = MockActions()
        let all: AfterCaptureTask = [.showNotification, .revealInFinder, .copyToClipboard, .saveToFile]
        let report = AfterCaptureRunner.run(all, images: [image], actions: mock)
        #expect(mock.calls == ["save", "copy", "reveal", "notify"])
        #expect(report?.failures.isEmpty == true)
        #expect(report?.copied == true)
    }

    @Test func emptyTasksReturnsNil() {
        let mock = MockActions()
        #expect(AfterCaptureRunner.run([], images: [image], actions: mock) == nil)
        #expect(mock.calls.isEmpty)
    }

    @Test func saveFailureDoesNotStopClipboard() {
        let mock = MockActions()
        mock.failSave = true
        let report = AfterCaptureRunner.run([.saveToFile, .copyToClipboard, .revealInFinder], images: [image], actions: mock)
        #expect(mock.calls == ["save", "copy", "notify"])
        #expect(report?.copied == true)
        #expect(report?.failures.map(\.task) == [.saveToFile])
        #expect(report?.skipped == .revealInFinder)
    }

    @Test func revealSkippedWhenSaveOff() {
        let mock = MockActions()
        let report = AfterCaptureRunner.run([.copyToClipboard, .revealInFinder], images: [image], actions: mock)
        #expect(mock.calls == ["copy"])
        #expect(report?.skipped == .revealInFinder)
        #expect(report?.failures.isEmpty == true)
    }

    @Test func failureNotifiesOnceEvenWhenNotificationOff() {
        let mock = MockActions()
        mock.failCopy = true
        _ = AfterCaptureRunner.run([.copyToClipboard], images: [image], actions: mock)
        #expect(mock.calls.filter { $0 == "notify" }.count == 1)
        #expect(mock.notified?.summary == "Copy to clipboard failed: boom")
    }

    @Test func noNotificationWhenSuccessfulAndOff() {
        let mock = MockActions()
        _ = AfterCaptureRunner.run(.defaults, images: [image], actions: mock)
        #expect(mock.calls == ["save", "copy"])
    }

    @Test func summaryListsSavedAndCopied() {
        let mock = MockActions()
        let report = AfterCaptureRunner.run([.saveToFile, .copyToClipboard, .showNotification], images: [image, image], actions: mock)
        #expect(report?.summary == "Saved 2 files\nCopied to clipboard")
    }

    @Test func copyReceivesSavedURLs() {
        let mock = MockActions()
        _ = AfterCaptureRunner.run(.defaults, images: [image], actions: mock)
        #expect(mock.copiedWithURLs == [URL(fileURLWithPath: "/tmp/shot0.png")])
    }

    @Test func notificationGetsThumbnail() {
        let mock = MockActions()
        _ = AfterCaptureRunner.run(.showNotification, images: [image], actions: mock)
        #expect(mock.thumbnail === image)
    }

    @Test func runnerIgnoresAnnotate() {
        let mock = MockActions()
        #expect(AfterCaptureRunner.run(.annotate, images: [image], actions: mock) == nil)
        let report = AfterCaptureRunner.run([.annotate, .copyToClipboard], images: [image], actions: mock)
        #expect(mock.calls == ["copy"])
        #expect(report?.tasks == .copyToClipboard)
    }

    @Test func annotateIsFirstInOrder() {
        #expect(AfterCaptureTask.ordered.first == .annotate)
    }
}
