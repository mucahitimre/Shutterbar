import AppKit
import CoreGraphics

@MainActor
enum PermissionService {
    /// Note: if the preflight result is false, it may stay false even after permission is granted until the process is relaunched.
    static var hasScreenCaptureAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                Log.app.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
