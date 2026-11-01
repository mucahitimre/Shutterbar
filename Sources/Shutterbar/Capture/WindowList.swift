import AppKit
import ShutterbarCore

/// On-screen windows at freeze time, front to back. Only bounds / layer / owner are read;
/// image capture is done by ScreenCaptureKit (this is not a capture API).
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
