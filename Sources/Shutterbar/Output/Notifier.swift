import AppKit
import ShutterbarCore
@preconcurrency import UserNotifications

/// Capture notifications. Clicking a notification selects the saved file in Finder.
@MainActor
final class Notifier: NSObject {
    nonisolated private static let pathKey = "path"
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func post(title: String, body: String, file: URL?, thumbnail: CGImage? = nil) {
        // The attachment file is moved by the system, so a small temporary copy is given instead of the saved file.
        let attachmentURL = thumbnail.flatMap(Self.writeThumbnail)
        Task {
            do {
                // Permission is requested on the first call; afterwards the decision from System Settings is returned.
                guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                    Log.output.info("No notification permission; notification skipped")
                    return
                }
            } catch {
                Log.output.error("Could not get notification permission: \(error.localizedDescription, privacy: .public)")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if let file {
                content.userInfo = [Self.pathKey: file.path]
            }
            if let attachmentURL,
               let attachment = try? UNNotificationAttachment(identifier: "thumbnail", url: attachmentURL) {
                content.attachments = [attachment]
            }
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            do {
                try await center.add(request)
            } catch {
                Log.output.error("Could not post notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension Notifier {
    static let thumbnailMaxSide = 480

    /// PNG with the long side at most `thumbnailMaxSide` pixels; in the temporary folder.
    static func writeThumbnail(_ image: CGImage) -> URL? {
        let scale = min(1, CGFloat(thumbnailMaxSide) / CGFloat(max(image.width, image.height)))
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = context.makeImage() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("thumb-\(UUID().uuidString).png")
        do {
            try PNGEncoder.write(small, to: url)
            return url
        } catch {
            Log.output.error("Could not write notification thumbnail: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // The menu bar app may stay active after the overlay; show the notification anyway.
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let path = response.notification.request.content.userInfo[Self.pathKey] as? String else { return }
        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }
}
