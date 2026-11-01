import Foundation
import os

enum AppInfo {
    /// `APP_NAME` from project.yml; read via Info.plist.
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Shutterbar"
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.mucahitimre.shutterbar"
}

enum Log {
    static let app = Logger(subsystem: AppInfo.bundleID, category: "app")
    static let capture = Logger(subsystem: AppInfo.bundleID, category: "capture")
    static let hotkey = Logger(subsystem: AppInfo.bundleID, category: "hotkey")
    static let output = Logger(subsystem: AppInfo.bundleID, category: "output")
}
