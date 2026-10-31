import AppKit
import KeyboardShortcuts

@MainActor
final class StatusItemController: NSObject {
    struct Actions {
        var captureRegion: () -> Void
        var captureLastRegion: () -> Void
        var openSettings: () -> Void
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: AppInfo.name)
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let region = NSMenuItem(title: HotkeyAction.region.title, action: #selector(captureRegion), keyEquivalent: "")
        region.target = self
        region.setShortcut(for: .captureRegion)
        menu.addItem(region)

        let last = NSMenuItem(title: HotkeyAction.lastRegion.title, action: #selector(captureLastRegion), keyEquivalent: "")
        last.target = self
        last.setShortcut(for: .captureLastRegion)
        menu.addItem(last)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func captureRegion() { actions.captureRegion() }
    @objc private func captureLastRegion() { actions.captureLastRegion() }
    @objc private func openSettings() { actions.openSettings() }
}
