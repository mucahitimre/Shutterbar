import Foundation

/// Carbon `RegisterEventHotKey` sonucunun yorumu.
///
/// KeyboardShortcuts kayıt hatasını yutar; bu yüzden uygulama aynı kombinasyonu ayrıca dener.
/// `eventHotKeyExistsErr`, kombinasyonun bu process'te zaten kayıtlı (yani çalışıyor) olduğunu gösterir.
public enum HotkeyRegistration {
    public static let noErr: Int32 = 0
    /// `eventHotKeyExistsErr`
    public static let alreadyRegistered: Int32 = -9878
    /// macOS 15.0–15.1 sandbox'ta yalnız ⌥ / ⌥⇧ kısayollarında dönen `eventInternalErr`.
    public static let sequoiaOptionRestriction: Int32 = -9868

    public static func isUsable(status: Int32) -> Bool {
        status == noErr || status == alreadyRegistered
    }
}
