import AppKit
import CoreGraphics

@MainActor
enum PermissionService {
    /// Not: preflight sonucu false ise izin verildikten sonra da process yeniden başlayana kadar false kalabilir.
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
                Log.app.error("Yeniden başlatma başarısız: \(error.localizedDescription, privacy: .public)")
                return
            }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
