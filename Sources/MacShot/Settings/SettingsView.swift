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
            Section("Shortcuts") {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    KeyboardShortcuts.Recorder(action.title + ":", name: action.name)
                    if hotkeys.failures.contains(action) {
                        HStack {
                            Label("This shortcut could not be registered with the system.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Use fallback (\(action.fallback.description))") {
                                hotkeys.useFallback(for: action)
                            }
                        }
                    }
                }
            }

            Section("Selection") {
                Toggle("Quick capture (capture as soon as the mouse is released)", isOn: $preferences.quickCapture)
                Text(preferences.quickCapture
                     ? "After-capture tasks run as soon as the selection is finished."
                     : "The selection can be moved / resized until Enter. Enter: after-capture tasks, ⌘C: clipboard only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Magnifier (size: mouse wheel in the overlay)", isOn: $preferences.magnifier)
                Toggle("Window detection: click a highlighted window to select it", isOn: $preferences.windowSnap)
            }

            Section("After capture") {
                ForEach(AfterCaptureTask.ordered, id: \.rawValue) { task in
                    Toggle(task.title, isOn: Binding(
                        get: { preferences.afterCaptureTasks.contains(task) },
                        set: { _ in preferences.toggle(task) }
                    ))
                }
                Toggle("Also put the file URL on the clipboard (when saving)", isOn: $preferences.clipboardIncludesFileURL)
                    .disabled(!preferences.afterCaptureTasks.contains(.saveToFile) || !preferences.afterCaptureTasks.contains(.copyToClipboard))
                if preferences.afterCaptureTasks.isEmpty {
                    Label("No task selected; captured images are not sent anywhere.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text("Save folder")
                        Text(SaveFolder.displayURL(bookmark: preferences.saveFolderBookmark).path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Change…") {
                        let current = SaveFolder.displayURL(bookmark: preferences.saveFolderBookmark)
                        if let bookmark = SaveFolder.choose(current: current) {
                            preferences.saveFolderBookmark = bookmark
                        }
                    }
                    if preferences.saveFolderBookmark != nil {
                        Button("Reset to default") { preferences.saveFolderBookmark = nil }
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                if loginItem.status == .requiresApproval {
                    HStack {
                        Label("Waiting for approval in System Settings > Login Items.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open") { loginItem.openSystemSettings() }
                    }
                }
                if let error = loginItem.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Permission") {
                HStack {
                    PermissionStatusLabel()
                    Spacer()
                    Button("Open onboarding", action: openOnboarding)
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
            Label("Screen Recording permission granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Label("Screen Recording permission missing", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
