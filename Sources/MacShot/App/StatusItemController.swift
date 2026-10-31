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

    private static let repositoryURL = URL(string: "https://github.com/mucahitimre/MacShot")

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

        let region = item("Capture Region", symbol: "camera.viewfinder", action: #selector(captureRegion))
        region.setShortcut(for: .captureRegion)
        menu.addItem(region)

        let last = item("Capture Last Region",
                        symbol: "arrow.counterclockwise.rectangle", "clock.arrow.circlepath",
                        action: #selector(captureLastRegion))
        last.setShortcut(for: .captureLastRegion)
        menu.addItem(last)

        for task in AfterCaptureTask.ordered {
            let taskItem = NSMenuItem(title: Self.menuTitle(for: task), action: #selector(toggleTask(_:)), keyEquivalent: "")
            taskItem.target = self
            taskItem.tag = task.rawValue
            afterCaptureMenu.addItem(taskItem)
        }
        afterCaptureMenu.delegate = self
        let afterCapture = NSMenuItem(title: "After Capture", action: nil, keyEquivalent: "")
        afterCapture.image = Self.symbol("square.and.arrow.down")
        afterCapture.submenu = afterCaptureMenu
        menu.addItem(afterCapture)

        menu.addItem(.separator())

        menu.addItem(item("About \(AppInfo.name)", symbol: "info.circle", action: #selector(showAbout)))
        menu.addItem(item("Settings…", symbol: "gearshape", action: #selector(openSettings), key: ","))

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = Self.symbol("power")
        menu.addItem(quit)
        return menu
    }

    private func item(_ title: String, symbol names: String..., action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = names.lazy.compactMap { Self.symbol($0) }.first
        return item
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    /// Menu items use title-style capitalization (HIG); the core titles are sentence-style for settings.
    private static func menuTitle(for task: AfterCaptureTask) -> String {
        switch task {
        case .annotate: "Open Annotation Editor"
        case .saveToFile: "Save to File"
        case .copyToClipboard: "Copy to Clipboard"
        case .revealInFinder: "Show in Finder"
        case .showNotification: "Show Notification"
        default: task.title
        }
    }

    @objc private func captureRegion() { actions.captureRegion() }
    @objc private func captureLastRegion() { actions.captureLastRegion() }
    @objc private func openSettings() { actions.openSettings() }

    @objc private func showAbout() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(string: "Region capture for macOS, inspired by ShareX.\n", attributes: attributes)
        if let url = Self.repositoryURL {
            var link = attributes
            link[.link] = url
            credits.append(NSAttributedString(string: "github.com/mucahitimre/MacShot", attributes: link))
        }

        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

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
