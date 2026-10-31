import CoreGraphics
import Foundation
import ImageIO
import MacShotCore
import Testing

struct ImageCropperTests {
    /// Sol yarısı kırmızı, sağ yarısı mavi; `width`×`height` piksel.
    func makeImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return ctx.makeImage()!
    }

    @Test func retinaCropUsesImageScale() throws {
        let image = makeImage(width: 400, height: 200) // 200×100 pt @2x
        let cropped = try #require(ImageCropper.crop(image, pointRect: CGRect(x: 10, y: 10, width: 50, height: 20), displayPointSize: CGSize(width: 200, height: 100)))
        #expect(cropped.width == 100)
        #expect(cropped.height == 40)
    }

    @Test func nonRetinaCrop() throws {
        let image = makeImage(width: 200, height: 100)
        let cropped = try #require(ImageCropper.crop(image, pointRect: CGRect(x: 0, y: 0, width: 300, height: 30), displayPointSize: CGSize(width: 200, height: 100)))
        #expect(cropped.width == 200) // sınıra kırpıldı
        #expect(cropped.height == 30)
    }

    @Test func emptyCropIsNil() {
        let image = makeImage(width: 20, height: 20)
        #expect(ImageCropper.crop(image, pointRect: .zero, displayPointSize: CGSize(width: 20, height: 20)) == nil)
    }

    @Test func pngRoundTrip() throws {
        let image = makeImage(width: 31, height: 17)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("nested/out.png")
        try PNGEncoder.write(image, to: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 31)
        #expect(decoded.height == 17)
        #expect(throws: (any Error).self) { try PNGEncoder.write(image, to: url) } // üzerine yazmaz
    }
}
