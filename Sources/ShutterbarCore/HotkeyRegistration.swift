import Foundation

/// Interpretation of the Carbon `RegisterEventHotKey` result.
///
/// KeyboardShortcuts swallows registration errors, so the app tries the same combination separately.
/// `eventHotKeyExistsErr` means the combination is already registered in this process (i.e. it works).
public enum HotkeyRegistration {
    public static let noErr: Int32 = 0
    /// `eventHotKeyExistsErr`
    public static let alreadyRegistered: Int32 = -9878
    /// `eventInternalErr`, returned in the macOS 15.0–15.1 sandbox only for ⌥ / ⌥⇧ shortcuts.
    public static let sequoiaOptionRestriction: Int32 = -9868

    public static func isUsable(status: Int32) -> Bool {
        status == noErr || status == alreadyRegistered
    }
}
