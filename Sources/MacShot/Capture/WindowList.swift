import AppKit
import MacShotCore

/// Dondurma anındaki ekrandaki pencereler, önden arkaya. Yalnız sınır / katman / sahip okunur;
/// görüntü yakalama ScreenCaptureKit'tedir (bu bir capture API'si değildir).
enum WindowList {
    static func onScreen() -> [WindowSnap.Window] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { entry in
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict),
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32
            else { return nil }
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0 { return nil }
            return WindowSnap.Window(frame: frame, layer: layer, ownerPID: pid)
        }
    }
}
