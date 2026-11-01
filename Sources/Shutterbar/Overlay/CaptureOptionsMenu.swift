import AppKit
import ShutterbarCore

/// The capture toolbar's Options menu: save location, after-capture tasks, timer and overlay options.
/// Changes go straight to `Preferences`; `onChange` lets the overlay apply live ones.
@MainActor
enum CaptureOptionsMenu {
    static func make(preferences: Preferences, chooseFolder: @escaping () -> Void, onChange: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(.sectionHeader(title: "Save to"))
        let defaultName = "\(AppInfo.name) Folder in Pictures"
        menu.addItem(ActionMenuItem(defaultName, checked: preferences.saveFolderBookmark == nil) {
            preferences.saveFolderBookmark = nil
        })
        if preferences.saveFolderBookmark != nil {
            let custom = SaveFolder.displayURL(bookmark: preferences.saveFolderBookmark).lastPathComponent
            menu.addItem(ActionMenuItem(custom, checked: true) {})
        }
        menu.addItem(ActionMenuItem("Other Location…", action: chooseFolder))

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "After Capture"))
        for task in AfterCaptureTask.ordered {
            menu.addItem(ActionMenuItem(task.title, checked: preferences.afterCaptureTasks.contains(task)) {
                preferences.toggle(task)
            })
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Timer"))
        for timer in CaptureTimer.allCases {
            menu.addItem(ActionMenuItem(timer.title, checked: preferences.captureTimer == timer) {
                preferences.captureTimer = timer
            })
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Options"))
        let toggles: [(String, ReferenceWritableKeyPath<Preferences, Bool>)] = [
            ("Show Floating Thumbnail", \.showFloatingThumbnail),
            ("Remember Last Selection", \.rememberLastSelection),
            ("Show Magnifier", \.magnifier),
            ("Quick Capture", \.quickCapture),
            ("Detect Windows in Selection Mode", \.windowSnap),
            ("Play Sound", \.playSound),
        ] + (AutoScrollPermission.isAvailable ? [("Scroll Automatically in Scrolling Capture", \Preferences.autoScroll)] : [])
        for (title, keyPath) in toggles {
            menu.addItem(ActionMenuItem(title, checked: preferences[keyPath: keyPath]) {
                preferences[keyPath: keyPath].toggle()
                onChange()
            })
        }
        return menu
    }
}

/// Menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}
