import CoreGraphics
import MacShotCore
import Testing

struct CaptureGeometryTests {
    // Ana ekran 1512×982 (sol-alt 0,0). Harici ekran solda ve yukarıda: AppKit frame (-1920, 200, 1920, 1080).
    let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let leftExternal = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
    // Dikey yerleşim: ana ekranın üstünde.
    let aboveExternal = CGRect(x: 0, y: 982, width: 2560, height: 1440)

    @Test func primaryGlobalToLocalFlipsY() {
        let local = CaptureGeometry.toDisplayLocal(CGPoint(x: 100, y: 900), displayFrame: primary)
        #expect(local == CGPoint(x: 100, y: 82))
    }

    @Test func negativeOriginDisplayRoundTrip() {
        let global = CGRect(x: -1800, y: 1000, width: 300, height: 200)
        let local = CaptureGeometry.toDisplayLocal(global, displayFrame: leftExternal)
        // x: -1800 - (-1920) = 120; y: (200 + 1080) - (1000 + 200) = 80
        #expect(local == CGRect(x: 120, y: 80, width: 300, height: 200))
        #expect(CaptureGeometry.toGlobal(local, displayFrame: leftExternal) == global)
    }

    @Test func verticalLayoutDisplay() {
        let global = CGRect(x: 10, y: 2400, width: 50, height: 22)
        let local = CaptureGeometry.toDisplayLocal(global, displayFrame: aboveExternal)
        #expect(local == CGRect(x: 10, y: 0, width: 50, height: 22))
    }

    @Test func quartzGlobalForSecondaryDisplay() {
        // Harici ekranın sol-üst köşesi: AppKit y = 1280 → Quartz y = 982 - 1280 = -298
        let p = CaptureGeometry.toQuartzGlobal(.zero, displayFrame: leftExternal, primaryScreenHeight: 982)
        #expect(p == CGPoint(x: -1920, y: -298))
        let q = CaptureGeometry.toQuartzGlobal(CGPoint(x: 5, y: 7), displayFrame: primary, primaryScreenHeight: 982)
        #expect(q == CGPoint(x: 5, y: 7))
    }

    @Test(arguments: [(1.0, 10.0), (2.0, 20.0), (1.5, 15.0)])
    func pixelRectScales(scale: Double, expectedOrigin: Double) {
        let rect = CGRect(x: 10, y: 10, width: 100, height: 50)
        let px = CaptureGeometry.pixelRect(forPointRect: rect, scale: scale, imageWidth: 10_000, imageHeight: 10_000)
        #expect(px == CGRect(x: expectedOrigin, y: expectedOrigin, width: 100 * scale, height: 50 * scale))
    }

    @Test func pixelRectRoundsOutward() {
        // 1.5x: minX 10.3*1.5=15.45 → 15; maxX (10.3+20.1)*1.5=45.6 → 46
        let px = CaptureGeometry.pixelRect(
            forPointRect: CGRect(x: 10.3, y: 0.5, width: 20.1, height: 1.2),
            scale: 1.5, imageWidth: 1000, imageHeight: 1000
        )
        #expect(px == CGRect(x: 15, y: 0, width: 31, height: 3))
    }

    @Test func pixelRectClampsToImage() {
        let px = CaptureGeometry.pixelRect(
            forPointRect: CGRect(x: -5, y: 90, width: 30, height: 30),
            scale: 2, imageWidth: 200, imageHeight: 200
        )
        #expect(px == CGRect(x: 0, y: 180, width: 50, height: 20))
    }

    @Test func pixelRectRejectsEmptyAndOutside() {
        #expect(CaptureGeometry.pixelRect(forPointRect: .zero, scale: 2, imageWidth: 100, imageHeight: 100) == nil)
        #expect(CaptureGeometry.pixelRect(forPointRect: CGRect(x: 10, y: 10, width: -0, height: 5), scale: 2, imageWidth: 100, imageHeight: 100) == nil)
        #expect(CaptureGeometry.pixelRect(forPointRect: CGRect(x: 200, y: 0, width: 10, height: 10), scale: 1, imageWidth: 100, imageHeight: 100) == nil)
    }

    @Test func negativeSizeIsStandardized() {
        let px = CaptureGeometry.pixelRect(forPointRect: CGRect(x: 20, y: 20, width: -10, height: -10), scale: 1, imageWidth: 100, imageHeight: 100)
        #expect(px == CGRect(x: 10, y: 10, width: 10, height: 10))
    }

    @Test func dragAcrossScreenEdgeIsClampedToStartScreen() {
        let bounds = CGSize(width: 1512, height: 982)
        let rect = CaptureGeometry.rect(from: CGPoint(x: 1400, y: 900), to: CGPoint(x: 1700, y: 1200), square: false, bounds: bounds)
        #expect(rect == CGRect(x: 1400, y: 900, width: 112, height: 82))
        let leftward = CaptureGeometry.rect(from: CGPoint(x: 50, y: 50), to: CGPoint(x: -300, y: 10), square: false, bounds: bounds)
        #expect(leftward == CGRect(x: 0, y: 10, width: 50, height: 40))
    }

    @Test func squareUsesShortSideAndKeepsDirection() {
        let bounds = CGSize(width: 1000, height: 1000)
        let rect = CaptureGeometry.rect(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 400, y: 800), square: true, bounds: bounds)
        #expect(rect == CGRect(x: 400, y: 500, width: 100, height: 100))
    }

    @Test func clickThreshold() {
        #expect(CaptureGeometry.isClick(CGRect(x: 0, y: 0, width: 2.9, height: 100)))
        #expect(!CaptureGeometry.isClick(CGRect(x: 0, y: 0, width: 3, height: 3)))
    }

    @Test func keepInsideTranslates() {
        let r = CaptureGeometry.keepInside(CGRect(x: 950, y: -20, width: 100, height: 100), bounds: CGSize(width: 1000, height: 1000))
        #expect(r == CGRect(x: 900, y: 0, width: 100, height: 100))
    }

    @Test func fitsChecksBounds() {
        let bounds = CGSize(width: 100, height: 100)
        #expect(CaptureGeometry.fits(CGRect(x: 0, y: 0, width: 100, height: 100), in: bounds))
        #expect(!CaptureGeometry.fits(CGRect(x: 50, y: 50, width: 51, height: 10), in: bounds))
        #expect(!CaptureGeometry.fits(.zero, in: bounds))
    }

    @Test func scaleFromImage() {
        #expect(CaptureGeometry.scale(imagePixelWidth: 3024, displayPointWidth: 1512) == 2)
        #expect(CaptureGeometry.scale(imagePixelWidth: 1920, displayPointWidth: 1920) == 1)
    }
}
