import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let hotkeys: HotkeyManager
    private let openOnboarding: () -> Void

    init(hotkeys: HotkeyManager, openOnboarding: @escaping () -> Void) {
        self.hotkeys = hotkeys
        self.openOnboarding = openOnboarding
    }

    func show() {
        if window == nil {
            let view = SettingsView(hotkeys: hotkeys, openOnboarding: openOnboarding)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "\(AppInfo.name) Ayarları"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        hotkeys.verify()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
