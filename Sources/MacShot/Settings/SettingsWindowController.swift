import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let hotkeys: HotkeyManager
    private let preferences: Preferences
    private let openOnboarding: () -> Void

    init(hotkeys: HotkeyManager, preferences: Preferences, openOnboarding: @escaping () -> Void) {
        self.hotkeys = hotkeys
        self.preferences = preferences
        self.openOnboarding = openOnboarding
    }

    func show() {
        if window == nil {
            let view = SettingsView(hotkeys: hotkeys, preferences: preferences, openOnboarding: openOnboarding)
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
