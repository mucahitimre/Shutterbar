import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var hotkeys: HotkeyManager
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

            Section("İzin") {
                HStack {
                    PermissionStatusLabel()
                    Spacer()
                    Button("Onboarding'i aç", action: openOnboarding)
                }
            }
        }
        .formStyle(.grouped)
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
