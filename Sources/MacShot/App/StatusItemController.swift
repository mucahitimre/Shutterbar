import AppKit
import KeyboardShortcuts
import MacShotCore

@MainActor
final class StatusItemController: NSObject {
    struct Actions {
        var captureRegion: () -> Void
        var captureLastRegion: () -> Void
        var openSettings: () -> Void
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let actions: Actions
    private let preferences: Preferences
    private let afterCaptureMenu = NSMenu()

    init(actions: Actions, preferences: Preferences) {
        self.actions = actions
        self.preferences = preferences
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

        let afterCapture = NSMenuItem(title: "After capture", action: nil, keyEquivalent: "")
        for task in AfterCaptureTask.ordered {
            let item = NSMenuItem(title: task.title, action: #selector(toggleTask(_:)), keyEquivalent: "")
            item.target = self
            item.tag = task.rawValue
            afterCaptureMenu.addItem(item)
        }
        afterCaptureMenu.delegate = self
        afterCapture.submenu = afterCaptureMenu
        menu.addItem(afterCapture)

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

    @objc private func toggleTask(_ sender: NSMenuItem) {
        preferences.toggle(AfterCaptureTask(rawValue: sender.tag))
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            item.state = preferences.afterCaptureTasks.contains(AfterCaptureTask(rawValue: item.tag)) ? .on : .off
        }
    }
}
