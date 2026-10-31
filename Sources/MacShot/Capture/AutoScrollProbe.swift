#if DEBUG
import AppKit
import ApplicationServices
import MacShotCore

/// Development probe: can a sandboxed MacShot scroll another app with synthetic scroll events?
/// Launch with `-MacShotAutoScrollProbe`. Captures the area under the mouse, posts scroll-down events,
/// captures again and measures the content shift with `ScrollStitcher`. Logs and shows the result.
@MainActor
enum AutoScrollProbe {
    static func run() {
        Task {
            // Key of kAXTrustedCheckOptionPrompt (the global is not concurrency-safe in Swift 6).
            let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            Log.capture.info("AUTOSCROLL PROBE trusted=\(trusted) sandboxed=\(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)")
            guard trusted else {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                alert("Accessibility permission needed",
                      "Turn on MacShot in System Settings → Privacy & Security → Accessibility (use + to add it if it is not listed: \(Bundle.main.bundlePath)), then launch the probe again.")
                return
            }

            alert("Move the mouse over a scrollable page",
                  "After you click OK you have 5 seconds to put the mouse over a long web page (not at its end). MacShot will then try to scroll it down by itself.")
            try? await Task.sleep(for: .seconds(5))

            do {
                let mouse = NSEvent.mouseLocation
                guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }), let displayID = screen.displayID else { return }
                let local = CaptureGeometry.toDisplayLocal(mouse, displayFrame: screen.frame)
                let rect = CGRect(x: local.x - 200, y: local.y - 150, width: 400, height: 300)
                    .intersection(CGRect(origin: .zero, size: screen.frame.size))
                let capturer = try await RegionCapturer(displayID: displayID, rect: rect)

                let before = try await capturer.capture()
                let posted = postScroll(pixels: 120, steps: 3)
                try? await Task.sleep(for: .milliseconds(600))
                let after = try await capturer.capture()

                let shift = measureShift(before, after)
                let verdict = switch shift {
                case .some(let dy) where dy > 0: "WORKS — the page moved \(dy) px"
                case .some: "NO EFFECT — the page did not move"
                case .none: "UNCLEAR — frames changed but could not be matched (moving content?)"
                }
                Log.capture.info("AUTOSCROLL PROBE posted=\(posted) shift=\(shift.map(String.init) ?? "nil", privacy: .public) → \(verdict, privacy: .public)")
                alert("Auto-scroll probe", verdict)
            } catch {
                Log.capture.error("AUTOSCROLL PROBE failed: \(error.localizedDescription, privacy: .public)")
                alert("Auto-scroll probe failed", error.localizedDescription)
            }
        }
    }

    /// Posts pixel-based scroll-down events at the current mouse position. Returns how many events were created.
    static func postScroll(pixels: Int32, steps: Int) -> Int {
        var created = 0
        for _ in 0..<steps {
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -pixels, wheel2: 0, wheel3: 0) else { continue }
            event.post(tap: .cghidEventTap)
            created += 1
            usleep(30_000)
        }
        return created
    }

    /// Content shift between two frames (rows moved up), using the same matching as scrolling capture.
    static func measureShift(_ a: CGImage, _ b: CGImage) -> Int? {
        guard let pa = PixelBuffer(image: a), let pb = PixelBuffer(image: b) else { return nil }
        let columns = ScrollStitcher.scrollingColumns(pa, pb)
        let sa = RowSignatures(buffer: pa, columns: columns), sb = RowSignatures(buffer: pb, columns: columns)
        let bands = ScrollStitcher.staticBands(sa, sb)
        return ScrollStitcher.offset(from: sa, to: sb, top: bands.top, bottom: bands.bottom)
    }

    private static func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }
}
#endif
