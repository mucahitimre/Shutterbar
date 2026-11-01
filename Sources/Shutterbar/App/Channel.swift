import Foundation

/// Distribution channel, read at run time: the GitHub build is not sandboxed, the App Store build is.
enum Channel {
    static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// Automatic scrolling needs the Accessibility permission, which a sandboxed app cannot be granted on macOS 27.
    static var supportsAutoScroll: Bool { !isSandboxed }
}

/// One-time move of preferences from the sandbox container (builds up to 0.2) to the regular defaults domain,
/// so shortcuts, after-capture tasks, the save folder and the last region survive leaving the sandbox.
enum PreferencesMigration {
    private static let doneKey = "migratedFromSandboxContainer"

    private static let renamedDoneKey = "migratedFromMacShot"

    static func runIfNeeded(defaults: UserDefaults = .standard) {
        migrateFromMacShotIfNeeded(defaults: defaults)
        guard !Channel.isSandboxed, !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }
        let id = AppInfo.bundleID
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(id)/Data/Library/Preferences/\(id).plist")
        guard let data = try? Data(contentsOf: url),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            Log.app.info("Preferences migration: no sandbox container preferences")
            return
        }
        // Container values win: the regular domain may only hold defaults written by a previous launch.
        for (key, value) in values where !key.hasPrefix("NS") && !key.hasPrefix("Apple") {
            defaults.set(value, forKey: key)
        }
        let moved = values.keys.filter { !$0.hasPrefix("NS") && !$0.hasPrefix("Apple") }.sorted()
        let readBack = moved.filter { defaults.object(forKey: $0) != nil }
        Log.app.info("Preferences migration: moved \(moved.joined(separator: ", "), privacy: .public); readable afterwards: \(readBack.count)/\(moved.count)")
    }

    /// One-time copy of the preferences of the app's former name (MacShot, up to 0.3.2): the bundle id changed with the
    /// rename, so without this shortcuts, after-capture tasks, the save folder and the last region would be lost.
    private static func migrateFromMacShotIfNeeded(defaults: UserDefaults) {
        guard !Channel.isSandboxed, !defaults.bool(forKey: renamedDoneKey) else { return }
        defer { defaults.set(true, forKey: renamedDoneKey) }
        var parts = AppInfo.bundleID.split(separator: ".").map(String.init)
        guard parts.count > 1 else { return }
        parts[parts.count - 1] = "macshot"
        let oldID = parts.joined(separator: ".")
        guard oldID != AppInfo.bundleID, let values = UserDefaults(suiteName: oldID)?.persistentDomain(forName: oldID), !values.isEmpty
        else {
            Log.app.info("Preferences migration: no MacShot preferences")
            return
        }
        let moved = values.filter { !$0.key.hasPrefix("NS") && !$0.key.hasPrefix("Apple") }
        for (key, value) in moved { defaults.set(value, forKey: key) }
        // The old domain already left the sandbox container, so the container migration must not run again.
        defaults.set(true, forKey: doneKey)
        Log.app.info("Preferences migration: copied \(moved.count) MacShot preferences")
    }
}
