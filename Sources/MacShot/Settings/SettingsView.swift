import KeyboardShortcuts
import MacShotCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var hotkeys: HotkeyManager
    @ObservedObject var preferences: Preferences
    @StateObject private var loginItem = LoginItem()
    let openOnboarding: () -> Void

    var body: some View {
        Form {
            Section("Kısayollar") {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    KeyboardShortcuts.Recorder(action.title + ":", name: action.name)
                    if hotkeys.failures.contains(action) {
                        HStack {
                            Label("Bu kısayol sistemde kaydedilemedi.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Yedeğe geç (\(action.fallback.description))") {
                                hotkeys.useFallback(for: action)
                            }
                        }
                    }
                }
            }

            Section("Seçim") {
                Toggle("Fareyi bırakınca hemen yakala (quick capture)", isOn: $preferences.quickCapture)
                Text(preferences.quickCapture
                     ? "Seçim bittiği anda after-capture task'ları çalışır."
                     : "Seçim Enter'a kadar taşınabilir / boyutlandırılabilir. Enter: after-capture task'ları, ⌘C: yalnız pano.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Büyüteç (boyut: overlay'de fare tekerleği)", isOn: $preferences.magnifier)
                Toggle("Pencere algılama: üzerine gelinen pencereyi tıklayarak seç", isOn: $preferences.windowSnap)
            }

            Section("After capture") {
                ForEach(AfterCaptureTask.ordered, id: \.rawValue) { task in
                    Toggle(task.title, isOn: Binding(
                        get: { preferences.afterCaptureTasks.contains(task) },
                        set: { _ in preferences.toggle(task) }
                    ))
                }
                Toggle("Panoya dosya URL'sini de ekle (kayıt açıkken)", isOn: $preferences.clipboardIncludesFileURL)
                    .disabled(!preferences.afterCaptureTasks.contains(.saveToFile) || !preferences.afterCaptureTasks.contains(.copyToClipboard))
                if preferences.afterCaptureTasks.isEmpty {
                    Label("Hiç task seçili değil; yakalanan görüntü hiçbir yere gitmez.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text("Kayıt klasörü")
                        Text(SaveFolder.displayURL(bookmark: preferences.saveFolderBookmark).path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Değiştir…") {
                        let current = SaveFolder.displayURL(bookmark: preferences.saveFolderBookmark)
                        if let bookmark = SaveFolder.choose(current: current) {
                            preferences.saveFolderBookmark = bookmark
                        }
                    }
                    if preferences.saveFolderBookmark != nil {
                        Button("Varsayılana dön") { preferences.saveFolderBookmark = nil }
                    }
                }
            }

            Section("Genel") {
                Toggle("Oturum açılışında başlat", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                if loginItem.status == .requiresApproval {
                    HStack {
                        Label("Sistem Ayarları > Giriş Öğeleri'nde onay bekliyor.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Aç") { loginItem.openSystemSettings() }
                    }
                }
                if let error = loginItem.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("İzin") {
                HStack {
                    PermissionStatusLabel()
                    Spacer()
                    Button("Onboarding'i aç", action: openOnboarding)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            loginItem.refresh()
        }
        .frame(width: 500)
        .fixedSize()
    }
}

private struct PermissionStatusLabel: View {
    var body: some View {
        if PermissionService.hasScreenCaptureAccess {
            Label("Ekran kaydı izni var", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Label("Ekran kaydı izni yok", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
