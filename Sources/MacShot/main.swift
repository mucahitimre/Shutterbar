import AppKit

// Before anything reads UserDefaults (Preferences, KeyboardShortcuts).
PreferencesMigration.runIfNeeded()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
