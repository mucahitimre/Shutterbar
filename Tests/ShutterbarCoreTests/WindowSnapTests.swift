import CoreGraphics
import ShutterbarCore
import Testing

struct WindowSnapTests {
    // Primary screen 1440×900 (AppKit 0,0); second screen to the left, AppKit (-1920,-980) 1920×1080 → top edge at AppKit y=100.
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let left = CGRect(x: -1920, y: -980, width: 1920, height: 1080)

    @Test func quartzRectToLocalOnPrimary() {
        let local = CaptureGeometry.toDisplayLocal(
            quartzRect: CGRect(x: 100, y: 50, width: 400, height: 300), displayFrame: primary, primaryScreenHeight: 900
        )
        #expect(local == CGRect(x: 100, y: 50, width: 400, height: 300))
    }

    @Test func quartzRectToLocalOnSecondary() {
        // Top-left of the left screen in Quartz: x = -1920, y = 900 - 100 = 800.
        let local = CaptureGeometry.toDisplayLocal(
            quartzRect: CGRect(x: -1900, y: 820, width: 500, height: 400), displayFrame: left, primaryScreenHeight: 900
        )
        #expect(local == CGRect(x: 20, y: 20, width: 500, height: 400))
    }

    @Test func localRectsFilterAndKeepOrder() {
        let windows = [
            WindowSnap.Window(frame: CGRect(x: 0, y: 0, width: 1440, height: 25), layer: 24, ownerPID: 1),   // menu bar
            WindowSnap.Window(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), layer: 20, ownerPID: 7),  // the Dock's full-screen window
            WindowSnap.Window(frame: CGRect(x: 100, y: 100, width: 300, height: 200), layer: 0, ownerPID: 99), // ourselves
            WindowSnap.Window(frame: CGRect(x: 200, y: 200, width: 400, height: 300), layer: 0, ownerPID: 2),  // front
            WindowSnap.Window(frame: CGRect(x: 10, y: 10, width: 10, height: 10), layer: 0, ownerPID: 3),      // too small
            WindowSnap.Window(frame: CGRect(x: 0, y: 40, width: 1000, height: 800), layer: 0, ownerPID: 4),    // behind
            WindowSnap.Window(frame: CGRect(x: -1800, y: 850, width: 300, height: 300), layer: 0, ownerPID: 5), // other screen
        ]
        let rects = WindowSnap.localRects(windows, excludingPID: 99, displayFrame: primary, primaryScreenHeight: 900)
        #expect(rects == [CGRect(x: 200, y: 200, width: 400, height: 300), CGRect(x: 0, y: 40, width: 1000, height: 800)])
    }

    @Test func partiallyOffscreenWindowIsClipped() {
        let windows = [WindowSnap.Window(frame: CGRect(x: 1300, y: 800, width: 400, height: 300), layer: 0, ownerPID: 2)]
        let rects = WindowSnap.localRects(windows, excludingPID: 99, displayFrame: primary, primaryScreenHeight: 900)
        #expect(rects == [CGRect(x: 1300, y: 800, width: 140, height: 100)])
    }

    @Test func frontmostWins() {
        let rects = [CGRect(x: 200, y: 200, width: 400, height: 300), CGRect(x: 0, y: 0, width: 1000, height: 800)]
        #expect(WindowSnap.window(at: CGPoint(x: 300, y: 300), in: rects) == rects[0])
        #expect(WindowSnap.window(at: CGPoint(x: 50, y: 50), in: rects) == rects[1])
        #expect(WindowSnap.window(at: CGPoint(x: 1200, y: 850), in: rects) == nil)
    }
}
