import AppKit
import ColorSync
import MacShotCore
@preconcurrency import ScreenCaptureKit

/// Bir ekranın donmuş karesi.
struct DisplaySnapshot {
    let displayID: CGDirectDisplayID
    let uuid: String?
    /// AppKit global frame (point).
    let frame: CGRect
    let image: CGImage

    /// Görüntünün gerçek ölçeği (piksel / point).
    var scale: CGFloat {
        CaptureGeometry.scale(imagePixelWidth: image.width, displayPointWidth: frame.width)
    }
}

enum SnapshotError: LocalizedError {
    case noDisplays
    case displayNotFound
    case captureFailed(any Error)

    var errorDescription: String? {
        switch self {
        case .noDisplays: "Yakalanacak ekran bulunamadı."
        case .displayNotFound: "Ekran artık bağlı değil."
        case .captureFailed(let error): "Ekran görüntüsü alınamadı: \(error.localizedDescription)"
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

enum DisplayIdentity {
    static func uuid(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}

/// ScreenCaptureKit ile ekran başına tek kare alır. Legacy CoreGraphics capture API'si kullanılmaz.
@MainActor
final class ScreenSnapshotService {
    private struct Target: @unchecked Sendable {
        let display: SCDisplay
        let frame: CGRect
    }

    /// Bağlı tüm ekranları paralel çeker.
    func snapshotAll() async throws -> [DisplaySnapshot] {
        try await snapshot(where: { _ in true })
    }

    /// Yalnız verilen ekranı çeker (last region için).
    func snapshot(displayID: CGDirectDisplayID) async throws -> DisplaySnapshot {
        guard let snapshot = try await snapshot(where: { $0 == displayID }).first else {
            throw SnapshotError.displayNotFound
        }
        return snapshot
    }

    private func snapshot(where include: (CGDirectDisplayID) -> Bool) async throws -> [DisplaySnapshot] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw SnapshotError.captureFailed(error)
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == pid }
        let screens = NSScreen.screens
        let targets: [Target] = content.displays.compactMap { display in
            guard include(display.displayID),
                  let screen = screens.first(where: { $0.displayID == display.displayID })
            else { return nil }
            return Target(display: display, frame: screen.frame)
        }
        guard !targets.isEmpty else { throw SnapshotError.noDisplays }

        let excluded = UncheckedBox(ownApps)
        let images = try await withThrowingTaskGroup(of: (Int, CGImage).self) { group in
            for (index, target) in targets.enumerated() {
                group.addTask {
                    (index, try await Self.capture(target.display, pointSize: target.frame.size, excluding: excluded.value))
                }
            }
            var result: [Int: CGImage] = [:]
            for try await (index, image) in group {
                result[index] = image
            }
            return result
        }

        return targets.enumerated().compactMap { index, target in
            guard let image = images[index] else { return nil }
            let snapshot = DisplaySnapshot(
                displayID: target.display.displayID,
                uuid: DisplayIdentity.uuid(for: target.display.displayID),
                frame: target.frame,
                image: image
            )
            let backing = screens.first { $0.displayID == snapshot.displayID }?.backingScaleFactor ?? 0
            if abs(snapshot.scale - backing) > 0.01 {
                Log.capture.notice("Ölçek farkı: görüntü \(snapshot.scale) / backingScaleFactor \(backing), display \(snapshot.displayID)")
            }
            return snapshot
        }
    }

    private nonisolated static func capture(_ display: SCDisplay, pointSize: CGSize, excluding apps: [SCRunningApplication]) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingApplications: apps, exceptingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        // SCDisplay.width point, SCStreamConfiguration.width piksel: çarpılmazsa Retina'da yarım çözünürlük.
        config.width = Int((CGFloat(display.width) * scale).rounded())
        config.height = Int((CGFloat(display.height) * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw SnapshotError.captureFailed(error)
        }
    }
}

/// SCK tipleri Sendable işaretli değil; değişmeden task'lara aktarılıyor.
struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
