import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "\(AppInfo.name) — Screen Recording Permission"
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
            Text("Permission is required to take screenshots")
                .font(.headline)
            Text("\(AppInfo.name) captures all screens once to freeze the display while you make a selection. For this, \(AppInfo.name) must be enabled under System Settings → Privacy & Security → Screen & System Audio Recording.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Relaunch the app after granting permission; macOS sometimes does not apply the permission to a running app until it is relaunched.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("1. Request permission") {
                    PermissionService.requestScreenCaptureAccess()
                    requested = true
                }
                Button("2. Open System Settings") {
                    PermissionService.openSystemSettings()
                }
                Button("3. Relaunch app") {
                    PermissionService.relaunch()
                }
                .keyboardShortcut(.defaultAction)
            }
            if requested {
                Text("If no permission prompt appeared, it may have been denied before; enable it in System Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
