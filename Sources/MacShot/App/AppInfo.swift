import Foundation
import os

enum AppInfo {
    /// project.yml'deki `APP_NAME`; Info.plist üzerinden okunur.
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MacShot"
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.mucahitimre.macshot"
}

enum Log {
    static let app = Logger(subsystem: AppInfo.bundleID, category: "app")
    static let capture = Logger(subsystem: AppInfo.bundleID, category: "capture")
    static let hotkey = Logger(subsystem: AppInfo.bundleID, category: "hotkey")
    static let output = Logger(subsystem: AppInfo.bundleID, category: "output")
}
