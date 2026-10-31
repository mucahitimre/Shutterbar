import AppKit
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

    func post(title: String, body: String, file: URL?) {
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
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            do {
                try await center.add(request)
            } catch {
                Log.output.error("Bildirim gönderilemedi: \(error.localizedDescription, privacy: .public)")
            }
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
