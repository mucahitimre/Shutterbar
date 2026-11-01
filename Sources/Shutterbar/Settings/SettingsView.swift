import AppKit
import KeyboardShortcuts
import ShutterbarCore
import SwiftUI

/// Layout shared by every settings pane: a grouped form with a fixed width whose height fits its content,
/// pinned to the top so it does not drift while the window animates to a new pane's height.
enum SettingsPane {
    static let width: CGFloat = 520
}

private extension View {
    func settingsPane() -> some View {
        formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: SettingsPane.width)
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - General

struct GeneralSettingsPane: View {
    @ObservedObject var preferences: Preferences
    @StateObject private var loginItem = LoginItem()
    @State private var hasScreenRecordingAccess = PermissionService.hasScreenCaptureAccess
    @State private var hasAccessibilityAccess = AutoScrollPermission.isGranted
    let openOnboarding: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                if loginItem.status == .requiresApproval {
                    LabeledContent {
                        Button("Open System Settings…") { loginItem.openSystemSettings() }
                    } label: {
                        WarningLabel("Waiting for approval in System Settings > General > Login Items.")
                    }
                }
                if let error = loginItem.lastError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Play sound", isOn: $preferences.playSound)
                Toggle(isOn: $preferences.showFloatingThumbnail) {
                    Text("Show floating thumbnail")
                    Text("A preview of the capture appears in the corner of the screen.")
                }
            }

            Section("Permissions") {
                LabeledContent {
                    Button("Open Onboarding…", action: openOnboarding)
                } label: {
                    Text("Screen Recording")
                    PermissionStatus(granted: hasScreenRecordingAccess)
                }
                if AutoScrollPermission.isAvailable {
                    LabeledContent {
                        if !hasAccessibilityAccess {
                            Button("Allow…") { AutoScrollPermission.request() }
                        }
                    } label: {
                        Text("Accessibility")
                        Text("Optional: lets scrolling capture scroll by itself.")
                        PermissionStatus(granted: hasAccessibilityAccess)
                    }
                }
            }
        }
        .settingsPane()
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            loginItem.refresh()
            hasScreenRecordingAccess = PermissionService.hasScreenCaptureAccess
            hasAccessibilityAccess = AutoScrollPermission.isGranted
        }
    }
}

private struct PermissionStatus: View {
    let granted: Bool

    var body: some View {
        Label {
            Text(granted ? "Allowed" : "Not allowed")
        } icon: {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
        }
    }
}

// MARK: - Capture

struct CaptureSettingsPane: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Picker("Default mode", selection: $preferences.captureMode) {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                Picker("Self-timer", selection: $preferences.captureTimer) {
                    ForEach(CaptureTimer.allCases, id: \.self) { timer in
                        Text(timer.title).tag(timer)
                    }
                }
            }

            Section {
                Toggle(isOn: $preferences.quickCapture) {
                    Text("Quick capture")
                    Text(preferences.quickCapture
                         ? "After-capture tasks run as soon as you release the mouse."
                         : "Move or resize the selection, then press Return to run after-capture tasks or ⌘C to copy only.")
                }
                Toggle(isOn: $preferences.windowSnap) {
                    Text("Window detection")
                    Text("Highlights the window under the pointer; click to select it.")
                }
                Toggle(isOn: $preferences.rememberLastSelection) {
                    Text("Remember last selection")
                    Text("Shows the previous region when the overlay opens.")
                }
                Toggle(isOn: $preferences.magnifier) {
                    Text("Magnifier")
                    Text("Scroll in the overlay to change its size.")
                }
            }

            if AutoScrollPermission.isAvailable {
                Section {
                    Toggle(isOn: $preferences.autoScroll) {
                        Text("Scroll automatically")
                        Text(AutoScrollPermission.isGranted
                             ? "Scrolling capture scrolls the page by itself and stops at the end."
                             : "Needs the Accessibility permission (General › Permissions). Without it you scroll yourself.")
                    }
                } header: {
                    Text("Scrolling Capture")
                }
            }
        }
        .settingsPane()
    }
}

// MARK: - After Capture

struct AfterCaptureSettingsPane: View {
    @ObservedObject var preferences: Preferences

    private var canIncludeFileURL: Bool {
        preferences.afterCaptureTasks.contains(.saveToFile) && preferences.afterCaptureTasks.contains(.copyToClipboard)
    }

    var body: some View {
        Form {
            Section {
                ForEach(AfterCaptureTask.ordered, id: \.rawValue) { task in
                    Toggle(task.title, isOn: Binding(
                        get: { preferences.afterCaptureTasks.contains(task) },
                        set: { _ in preferences.toggle(task) }
                    ))
                }
            } header: {
                Text("After a capture")
            } footer: {
                if preferences.afterCaptureTasks.isEmpty {
                    WarningLabel("No task selected; captured images are not sent anywhere.")
                        .font(.callout)
                }
            }

            Section {
                Toggle(isOn: $preferences.clipboardIncludesFileURL) {
                    Text("Also put the file URL on the clipboard")
                    Text("Requires “Save to file” and “Copy to clipboard”.")
                }
                .disabled(!canIncludeFileURL)
            }

            Section("Save Location") {
                LabeledContent {
                    HStack {
                        if preferences.saveFolderBookmark != nil {
                            Button("Reset to Default") { preferences.saveFolderBookmark = nil }
                        }
                        Button("Change…") {
                            let current = SaveFolder.displayURL(bookmark: preferences.saveFolderBookmark)
                            if let bookmark = SaveFolder.choose(current: current) {
                                preferences.saveFolderBookmark = bookmark
                            }
                        }
                    }
                } label: {
                    Text("Folder")
                    Text(SaveFolder.displayURL(bookmark: preferences.saveFolderBookmark).path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(SaveFolder.displayURL(bookmark: preferences.saveFolderBookmark).path)
                }
            }
        }
        .settingsPane()
    }
}

// MARK: - Shortcuts

struct ShortcutsSettingsPane: View {
    @ObservedObject var hotkeys: HotkeyManager

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    KeyboardShortcuts.Recorder(action.title, name: action.name)
                    if hotkeys.failures.contains(action) {
                        LabeledContent {
                            Button("Use Fallback (\(action.fallback.description))") {
                                hotkeys.useFallback(for: action)
                            }
                        } label: {
                            WarningLabel("This shortcut could not be registered with the system.")
                        }
                    }
                }
            } footer: {
                Text("Shortcuts work in any app while \(AppInfo.name) is running.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPane()
    }
}

// MARK: - Shared

/// The system warning glyph (multicolor, like System Settings) followed by text.
private struct WarningLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
        }
    }
}
