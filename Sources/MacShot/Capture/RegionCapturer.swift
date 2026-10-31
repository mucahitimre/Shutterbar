import AppKit
@preconcurrency import ScreenCaptureKit

/// Repeatedly captures one region of one display (scrolling capture). The content filter is built once;
/// each frame asks ScreenCaptureKit for just the region via `sourceRect`. Our own windows are excluded.
@MainActor
final class RegionCapturer {
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration
    let pixelScale: CGFloat

    /// - Parameter rect: display-local, top-left origin, points.
    init(displayID: CGDirectDisplayID, rect: CGRect) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw SnapshotError.captureFailed(error)
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw SnapshotError.displayNotFound
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        filter = SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == pid },
                                 exceptingWindows: [])
        pixelScale = CGFloat(filter.pointPixelScale)
        configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        configuration.width = Int((rect.width * pixelScale).rounded())
        configuration.height = Int((rect.height * pixelScale).rounded())
        configuration.showsCursor = false
        configuration.captureResolution = .best
    }

    func capture() async throws -> CGImage {
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw SnapshotError.captureFailed(error)
        }
    }
}
