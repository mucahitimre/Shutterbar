import AppKit
import SwiftUI

/// Welcome-style window that walks the user through granting Screen Recording access.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let view = OnboardingView { [weak self] in self?.window?.close() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Allow Screen Recording"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct OnboardingView: View {
    let close: () -> Void

    @State private var granted = PermissionService.hasScreenCaptureAccess
    @State private var requested = false
    @State private var openedSettings = false

    private enum Step: Int, CaseIterable {
        case request = 1, enable, relaunch
    }

    /// The step whose button is the default action: the first one still to do.
    private var nextStep: Step? {
        if granted { return nil }
        if !requested { return .request }
        if !openedSettings { return .enable }
        return .relaunch
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            Text("Allow Screen Recording")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 12)

            Text("\(AppInfo.name) captures your screens once to freeze the display while you make a selection. macOS asks for your permission first.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            GroupBox {
                VStack(spacing: 0) {
                    stepRow(.request,
                            title: "Request access",
                            detail: "macOS asks whether \(AppInfo.name) may record the screen.",
                            done: granted || requested) {
                        Button("Request Permission") {
                            PermissionService.requestScreenCaptureAccess()
                            requested = true
                            granted = PermissionService.hasScreenCaptureAccess
                        }
                        .disabled(granted)
                    }
                    Divider()
                    stepRow(.enable,
                            title: "Turn on \(AppInfo.name)",
                            detail: "Privacy & Security > Screen & System Audio Recording.",
                            done: granted) {
                        Button("Open System Settings") {
                            PermissionService.openSystemSettings()
                            openedSettings = true
                        }
                    }
                    Divider()
                    stepRow(.relaunch,
                            title: "Relaunch \(AppInfo.name)",
                            detail: "macOS applies the permission after the app relaunches.",
                            done: granted) {
                        Button("Relaunch \(AppInfo.name)") {
                            PermissionService.relaunch()
                        }
                    }
                }
            }
            .padding(.top, 20)

            footer
                .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 20)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            granted = PermissionService.hasScreenCaptureAccess
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            granted = PermissionService.hasScreenCaptureAccess
        }
    }

    @ViewBuilder
    private var footer: some View {
        if granted {
            HStack {
                Text("\(AppInfo.name) is ready to capture.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: close)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        } else if requested {
            Text("If no prompt appeared, access may have been denied before. Turn it on in System Settings, then relaunch.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepRow(_ step: Step, title: String, detail: String, done: Bool,
                         @ViewBuilder button: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(step.rawValue).circle")
                .font(.title2)
                .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .frame(width: 24)
                .accessibilityLabel(done ? "Step \(step.rawValue), done" : "Step \(step.rawValue)")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            button()
                .primary(step == nextStep)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

private extension View {
    /// The one prominent default button in the window.
    @ViewBuilder
    func primary(_ isPrimary: Bool) -> some View {
        if isPrimary {
            buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        } else {
            self
        }
    }
}
