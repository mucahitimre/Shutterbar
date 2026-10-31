import CoreGraphics
import Foundation
import MacShotCore
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

    func save(_ images: [CGImage]) throws -> [URL] {
        calls.append("save")
        if failSave { throw Boom() }
        return images.indices.map { URL(fileURLWithPath: "/tmp/shot\($0).png") }
    }

    func copy(_ images: [CGImage]) throws {
        calls.append("copy")
        if failCopy { throw Boom() }
    }

    func reveal(_ urls: [URL]) {
        calls.append("reveal")
    }

    func notify(_ report: AfterCaptureReport) {
        calls.append("notify")
        notified = report
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
        #expect(report?.failures.map(\.task) == [.saveToFile, .revealInFinder])
    }

    @Test func failureNotifiesOnceEvenWhenNotificationOff() {
        let mock = MockActions()
        mock.failCopy = true
        _ = AfterCaptureRunner.run([.copyToClipboard], images: [image], actions: mock)
        #expect(mock.calls.filter { $0 == "notify" }.count == 1)
        #expect(mock.notified?.summary == "Panoya kopyala başarısız: boom")
    }

    @Test func noNotificationWhenSuccessfulAndOff() {
        let mock = MockActions()
        _ = AfterCaptureRunner.run(.defaults, images: [image], actions: mock)
        #expect(mock.calls == ["save", "copy"])
    }

    @Test func summaryListsSavedAndCopied() {
        let mock = MockActions()
        let report = AfterCaptureRunner.run([.saveToFile, .copyToClipboard, .showNotification], images: [image, image], actions: mock)
        #expect(report?.summary == "2 dosya kaydedildi\nPanoya kopyalandı")
    }
}
