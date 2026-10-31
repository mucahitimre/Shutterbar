import AppKit
import MacShotCore
import ScreenCaptureKit

/// Hotkey → dondur → overlay → kes → çıktı akışını yönetir.
@MainActor
final class CaptureCoordinator {
    private let snapshotter = ScreenSnapshotService()
    private let overlay = OverlayController()
    private let output: CaptureOutput
    private let preferences: Preferences
    private var isBusy = false
    private let onPermissionMissing: () -> Void

    init(preferences: Preferences = .shared, onPermissionMissing: @escaping () -> Void) {
        self.preferences = preferences
        self.output = CaptureOutput(preferences: preferences)
        self.onPermissionMissing = onPermissionMissing
    }

    func captureRegion() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            await runRegionCapture()
        }
    }

    private func runRegionCapture() async {
        let clock = ContinuousClock()
        let start = clock.now

        let snapshots: [DisplaySnapshot]
        do {
            snapshots = try await snapshotter.snapshotAll()
        } catch {
            report(error)
            return
        }
        let frozen = clock.now

        let result = await overlay.run(snapshots: snapshots, quickCapture: preferences.quickCapture, preview: nil) {
            let shown = clock.now
            Log.capture.info("Gecikme: dondurma \(Self.ms(frozen - start), privacy: .public) ms, overlay görünür \(Self.ms(shown - start), privacy: .public) ms, ekran sayısı \(snapshots.count)")
        }

        switch result {
        case .cancelled:
            Log.capture.info("İptal edildi")
        case .region(let snapshot, let rect, let intent):
            guard let image = ImageCropper.crop(snapshot.image, pointRect: rect, displayPointSize: snapshot.frame.size) else {
                Log.capture.error("Kesim boş: \(String(describing: rect), privacy: .public)")
                return
            }
            switch intent {
            case .afterCapture: output.deliver([image])
            case .clipboardOnly: output.copyOnly([image])
            }
        case .screens(let snapshots):
            output.deliver(snapshots.map(\.image))
        }
    }

    private func report(_ error: any Error) {
        Log.capture.error("Capture hatası: \(error.localizedDescription, privacy: .public)")
        if Self.isPermissionError(error) || !PermissionService.hasScreenCaptureAccess {
            onPermissionMissing()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Ekran görüntüsü alınamadı"
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }

    private static func isPermissionError(_ error: any Error) -> Bool {
        let underlying: any Error = if case SnapshotError.captureFailed(let inner) = error { inner } else { error }
        let ns = underlying as NSError
        return ns.domain == SCStreamErrorDomain && ns.code == SCStreamError.userDeclined.rawValue
    }

    private static func ms(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds * 1000 + attoseconds / 1_000_000_000_000_000)
    }
}
