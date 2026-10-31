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
            captureScrolling: { [weak self] in self?.handle(.scrolling) },
            openSettings: { [weak self] in self?.settings?.show() }
        ), preferences: .shared)

        #if DEBUG
        // Development: `open MacShot.app --args -MacShotEditorSample` opens the editor with a sample image (no capture needed).
        if ProcessInfo.processInfo.arguments.contains("-MacShotEditorSample") {
            capture.openEditorSample()
            return
        }
        // Development: `-MacShotRegionSelfTest` checks that region capture matches a crop of a full snapshot.
        if ProcessInfo.processInfo.arguments.contains("-MacShotRegionSelfTest") {
            capture.runRegionSelfTest()
            return
        }
        // Development: `-MacShotAutoScrollProbe` tests whether synthetic scrolling works from the sandbox.
        if ProcessInfo.processInfo.arguments.contains("-MacShotAutoScrollProbe") {
            AutoScrollProbe.run()
            return
        }
        // Development: `-MacShotScrollingSelfTest` runs a scrolling session on the area under the mouse.
        if ProcessInfo.processInfo.arguments.contains("-MacShotScrollingSelfTest") {
            AutoScrollProbe.runSession()
            return
        }
        // Development: `-MacShotShowWindows` opens settings and onboarding (layout checks).
        if ProcessInfo.processInfo.arguments.contains("-MacShotShowWindows") {
            settings?.show()
            onboarding.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                for window in NSApp.windows where window.isVisible {
                    Log.app.info("Window '\(window.title, privacy: .public)' content \(NSStringFromSize(window.contentLayoutRect.size), privacy: .public)")
                }
            }
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
        case .scrolling: capture.captureScrolling()
        }
    }
}
