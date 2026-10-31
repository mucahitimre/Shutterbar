import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "\(AppInfo.name) — Ekran Kaydı izni"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct OnboardingView: View {
    @State private var requested = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ekran görüntüsü alabilmek için izin gerekiyor")
                .font(.headline)
            Text("\(AppInfo.name), seçim yaparken ekranı dondurmak için tüm ekranların görüntüsünü bir kez alır. Bunun için Sistem Ayarları → Gizlilik ve Güvenlik → Ekran ve Sistem Sesi Kaydı listesinde \(AppInfo.name) açık olmalı.")
                .fixedSize(horizontal: false, vertical: true)
            Text("İzni verdikten sonra uygulamayı yeniden başlatın; macOS izni çalışan uygulamaya bazen yeniden başlatılana kadar yansıtmaz.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("1. İzin iste") {
                    PermissionService.requestScreenCaptureAccess()
                    requested = true
                }
                Button("2. Sistem Ayarları'nı aç") {
                    PermissionService.openSystemSettings()
                }
                Button("3. Uygulamayı yeniden başlat") {
                    PermissionService.relaunch()
                }
                .keyboardShortcut(.defaultAction)
            }
            if requested {
                Text("İzin penceresi çıkmadıysa daha önce reddedilmiş olabilir; Sistem Ayarları'ndan açın.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
