import AppKit
import MacShotCore
@preconcurrency import UserNotifications

/// Yakalama bildirimleri. Bildirime tıklanınca kayıtlı dosya Finder'da seçilir.
@MainActor
final class Notifier: NSObject {
    nonisolated private static let pathKey = "path"
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func post(title: String, body: String, file: URL?, thumbnail: CGImage? = nil) {
        // Ek dosyası sistem tarafından taşınır; kayıtlı dosya yerine geçici küçük kopya verilir.
        let attachmentURL = thumbnail.flatMap(Self.writeThumbnail)
        Task {
            do {
                // İlk çağrıda izin sorulur; sonra sistem ayarındaki karar döner.
                guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                    Log.output.info("Bildirim izni yok; bildirim atlandı")
                    return
                }
            } catch {
                Log.output.error("Bildirim izni alınamadı: \(error.localizedDescription, privacy: .public)")
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
                Log.output.error("Bildirim gönderilemedi: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension Notifier {
    static let thumbnailMaxSide = 480

    /// Uzun kenarı en çok `thumbnailMaxSide` piksel PNG; geçici klasöre.
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
            Log.output.error("Bildirim küçük resmi yazılamadı: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Menu bar uygulaması overlay sonrası aktif kalabilir; bildirim yine görünsün.
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
