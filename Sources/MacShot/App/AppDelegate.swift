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
        // The delegate that handles notification clicks must be set up at launch.
        _ = capture

        let hotkeys = HotkeyManager { [weak self] action in
            self?.handle(action)
        }
        hotkeys.start()
        self.hotkeys = hotkeys

        settings = SettingsWindowController(hotkeys: hotkeys, preferences: .shared) { [weak self] in
            self?.onboarding.show()
        }

        statusItem = StatusItemController(actions: .init(
            captureRegion: { [weak self] in self?.handle(.region) },
            captureLastRegion: { [weak self] in self?.handle(.lastRegion) },
            openSettings: { [weak self] in self?.settings?.show() }
        ), preferences: .shared)

        #if DEBUG
        // Development: `open MacShot.app --args -MacShotEditorSample` opens the editor with a sample image (no capture needed).
        if ProcessInfo.processInfo.arguments.contains("-MacShotEditorSample") {
            capture.openEditorSample()
            return
        }
        #endif

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
        Log.app.info("Triggered: \(action.title, privacy: .public)")
        switch action {
        case .region: capture.captureRegion()
        case .lastRegion: capture.captureLastRegion()
        }
    }
}
