import AppKit
import MacShotCore
import ScreenCaptureKit

/// Hotkey → dondur → overlay → kes → çıktı akışını yönetir.
@MainActor
final class CaptureCoordinator {
    static let lastRegionInvalidMessage = "Son bölge bu ekran düzeninde geçerli değil"

    private let snapshotter = ScreenSnapshotService()
    private let overlay = OverlayController()
    private let output: CaptureOutput
    private let preferences: Preferences
    private let lastRegion = LastRegionStore()
    private var isBusy = false
    private let onPermissionMissing: () -> Void

    init(preferences: Preferences = .shared, onPermissionMissing: @escaping () -> Void) {
        self.preferences = preferences
        self.output = CaptureOutput(preferences: preferences)
        self.onPermissionMissing = onPermissionMissing
        overlay.onMagnifierPixelCountChange = { [preferences] in preferences.magnifierPixelCount = $0 }
    }

    func captureRegion() {
        run { await $0.runRegionCapture(hud: nil) }
    }

    /// R3.3–R3.5: overlay açmadan son bölge; geçersizse overlay + HUD, hiç yoksa düz overlay.
    func captureLastRegion() {
        run { await $0.runLastRegionCapture() }
    }

    private func run(_ body: @escaping (CaptureCoordinator) async -> Void) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            await body(self)
        }
    }

    // MARK: Region (overlay)

    private func runRegionCapture(hud: String?) async {
        let clock = ContinuousClock()
        let start = clock.now

        // Pencere listesi dondurmayla aynı anda alınır; overlay açılınca kendi panellerimiz de girerdi.
        let windows = preferences.windowSnap ? WindowList.onScreen() : []
        let snapshots: [DisplaySnapshot]
        do {
            snapshots = try await snapshotter.snapshotAll()
        } catch {
            report(error)
            return
        }
        let frozen = clock.now

        let result = await overlay.run(
            snapshots: snapshots,
            quickCapture: preferences.quickCapture,
            magnifierPixelCount: preferences.magnifier ? preferences.magnifierPixelCount : nil,
            preview: preview(for: snapshots),
            windows: windows,
            hud: hud
        ) {
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
            remember(rect, on: snapshot)
            switch intent {
            case .afterCapture: output.deliver([image])
            case .clipboardOnly: output.copyOnly([image])
            }
        case .screens(let snapshots):
            lastRegion.record(.fullScreen)
            output.deliver(snapshots.map(\.image))
        }
    }

    /// R3.2: son bölgenin ekranı bağlı ve rect sığıyorsa o ekranda ön çizim.
    private func preview(for snapshots: [DisplaySnapshot]) -> (displayID: CGDirectDisplayID, rect: CGRect)? {
        guard let last = lastRegion.load() else { return nil }
        let displays = snapshots.compactMap { snapshot in
            snapshot.uuid.map { LastRegion.Display(uuid: $0, pointSize: snapshot.frame.size) }
        }
        guard case .valid = last.resolve(in: displays),
              let snapshot = snapshots.first(where: { $0.uuid == last.displayUUID })
        else { return nil }
        return (snapshot.displayID, last.rect)
    }

    // MARK: Last region (overlay'siz)

    private func runLastRegionCapture() async {
        guard let last = lastRegion.load() else {
            Log.capture.info("Son bölge yok; overlay açılıyor")
            await runRegionCapture(hud: nil)
            return
        }

        let screens = NSScreen.screens.compactMap { screen -> (id: CGDirectDisplayID, display: LastRegion.Display)? in
            guard let id = screen.displayID, let uuid = DisplayIdentity.uuid(for: id) else { return nil }
            return (id, LastRegion.Display(uuid: uuid, pointSize: screen.frame.size))
        }
        guard case .valid(let display) = last.resolve(in: screens.map(\.display)),
              let displayID = screens.first(where: { $0.display == display })?.id
        else {
            Log.capture.info("Son bölge geçersiz; overlay + HUD")
            await runRegionCapture(hud: Self.lastRegionInvalidMessage)
            return
        }

        let snapshot: DisplaySnapshot
        do {
            snapshot = try await snapshotter.snapshot(displayID: displayID)
        } catch {
            report(error)
            return
        }
        guard let image = ImageCropper.crop(snapshot.image, pointRect: last.rect, displayPointSize: snapshot.frame.size) else {
            Log.capture.error("Son bölge kesimi boş: \(String(describing: last.rect), privacy: .public)")
            await runRegionCapture(hud: Self.lastRegionInvalidMessage)
            return
        }
        Log.capture.info("Son bölge overlay'siz alındı")
        remember(last.rect, on: snapshot)
        output.deliver([image])
    }

    private func remember(_ rect: CGRect, on snapshot: DisplaySnapshot) {
        guard let uuid = snapshot.uuid else {
            Log.capture.error("Ekran UUID'si yok; son bölge saklanmadı")
            return
        }
        lastRegion.record(.region(LastRegion(displayUUID: uuid, rect: rect, displaySize: snapshot.frame.size, date: Date())))
    }

    #if DEBUG
    /// Editörü sentetik bir görüntüyle açar; sonuç after-capture task'larına gider.
    func openEditorSample() {
        let width = 1200, height = 760
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        for i in 0..<12 {
            let shade = 0.55 + CGFloat(i) * 0.035
            context.setFillColor(CGColor(srgbRed: shade, green: shade * 0.95, blue: 1, alpha: 1))
            context.fill(CGRect(x: i * 100, y: 0, width: 100, height: height))
        }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 150, y: 200, width: 900, height: 360))
        guard let image = context.makeImage() else { return }
        var tasks = preferences.afterCaptureTasks
        tasks.insert(.annotate)
        output.deliver([image], tasks: tasks)
    }
    #endif

    // MARK: Hata

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
