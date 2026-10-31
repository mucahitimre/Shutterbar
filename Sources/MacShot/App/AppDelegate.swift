import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var hotkeys: HotkeyManager?
    private var settings: SettingsWindowController?
    private let onboarding = OnboardingWindowController()
    private lazy var capture = CaptureCoordinator { [weak self] in
        self?.onboarding.show()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hotkeys = HotkeyManager { [weak self] action in
            self?.handle(action)
        }
        hotkeys.start()
        self.hotkeys = hotkeys

        settings = SettingsWindowController(hotkeys: hotkeys) { [weak self] in
            self?.onboarding.show()
        }

        statusItem = StatusItemController(actions: .init(
            captureRegion: { [weak self] in self?.handle(.region) },
            captureLastRegion: { [weak self] in self?.handle(.lastRegion) },
            openSettings: { [weak self] in self?.settings?.show() }
        ))

        if !PermissionService.hasScreenCaptureAccess {
            onboarding.show()
        }
        if !hotkeys.failures.isEmpty {
            settings?.show()
        }
    }

    private func handle(_ action: HotkeyAction) {
        guard PermissionService.hasScreenCaptureAccess else {
            onboarding.show()
            return
        }
        Log.app.info("Tetiklendi: \(action.title, privacy: .public)")
        switch action {
        case .region, .lastRegion:
            // F3'e kadar last region da overlay'i açar (R3.5).
            capture.captureRegion()
        }
    }
}
