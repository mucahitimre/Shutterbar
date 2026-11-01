import AppKit
import SwiftUI

/// Settings window in the style of Apple's own apps: toolbar tabs, the window title follows the selected pane
/// and the window animates to each pane's height.
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
        hotkeys.verify()
        let isNew = window == nil
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        if isNew {
            // The tab view controller installs its toolbar when the window appears; fit again with it in place.
            (window.contentViewController as? SettingsTabViewController)?.fitWindowToSelectedPane(animated: false)
        }
    }

    private func makeWindow() -> NSWindow {
        let tabs = SettingsTabViewController()
        tabs.addPane(id: "general", title: "General", symbol: "gearshape",
                     GeneralSettingsPane(preferences: preferences, openOnboarding: openOnboarding))
        tabs.addPane(id: "capture", title: "Capture", symbol: "camera.viewfinder",
                     CaptureSettingsPane(preferences: preferences))
        tabs.addPane(id: "afterCapture", title: "After Capture", symbol: "square.and.arrow.down",
                     AfterCaptureSettingsPane(preferences: preferences))
        tabs.addPane(id: "shortcuts", title: "Shortcuts", symbol: "keyboard",
                     ShortcutsSettingsPane(hotkeys: hotkeys))
        tabs.restoreSelection()

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        tabs.fitWindowToSelectedPane(animated: false)
        window.center()
        window.setFrameAutosaveName("\(AppInfo.name)SettingsWindow")
        return window
    }
}

/// Toolbar-style tabs; each pane is a SwiftUI form hosted in its own `NSHostingController`.
@MainActor
final class SettingsTabViewController: NSTabViewController {
    private static let selectionKey = "settingsSelectedPane"
    private typealias Pane = NSHostingController<AnyView>

    init() {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = [.allowUserInteraction]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func addPane(id: String, title: String, symbol: String, _ content: some View) {
        let pane = Pane(rootView: AnyView(content))
        // Report the SwiftUI size as `preferredContentSize` instead of constraining the window,
        // so the window can animate between panes of different heights.
        pane.sizingOptions = [.preferredContentSize]
        pane.title = title

        let item = NSTabViewItem(viewController: pane)
        item.identifier = id
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }

    func restoreSelection() {
        guard let id = UserDefaults.standard.string(forKey: Self.selectionKey),
              let index = tabViewItems.firstIndex(where: { $0.identifier as? String == id }) else { return }
        selectedTabViewItemIndex = index
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let id = tabViewItem?.identifier as? String {
            UserDefaults.standard.set(id, forKey: Self.selectionKey)
        }
        fitWindowToSelectedPane(animated: view.window?.isVisible == true)
    }

    /// A pane's height changed (e.g. a warning row appeared).
    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        guard viewController === selectedPane else { return }
        fitWindowToSelectedPane(animated: view.window?.isVisible == true)
    }

    private var selectedPane: Pane? {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return nil }
        return tabViewItems[selectedTabViewItemIndex].viewController as? Pane
    }

    /// Resizes the window so its content fits the selected pane, keeping the top edge in place.
    func fitWindowToSelectedPane(animated: Bool) {
        guard let pane = selectedPane, let window = view.window, let contentView = window.contentView else { return }
        // Panes are fixed-size forms pinned to the top; a zero height proposal yields their ideal height.
        let size = pane.sizeThatFits(in: CGSize(width: SettingsPane.width, height: 0))
        guard size.width > 0, size.height > 0 else { return }

        var frame = window.frame
        let height = frame.height - contentView.frame.height + size.height
        let width = frame.width - contentView.frame.width + size.width
        frame.origin.y += frame.height - height
        frame.size = CGSize(width: width, height: height)
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true, animate: animated)
    }
}
