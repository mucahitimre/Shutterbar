import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageCropper {
    /// Donmuş ekran görüntüsünden display-local point rect'ini keser. Ölçek görüntünün kendisinden hesaplanır.
    public static func crop(_ image: CGImage, pointRect: CGRect, displayPointSize: CGSize) -> CGImage? {
        let scale = CaptureGeometry.scale(imagePixelWidth: image.width, displayPointWidth: displayPointSize.width)
        guard let pixelRect = CaptureGeometry.pixelRect(
            forPointRect: pointRect,
            scale: scale,
            imageWidth: image.width,
            imageHeight: image.height
        ) else { return nil }
        return image.cropping(to: pixelRect)
    }
}

public enum PNGEncoder {
    public enum EncodeError: Error {
        case destinationFailed
        case finalizeFailed
    }

    public static func data(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw EncodeError.destinationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw EncodeError.finalizeFailed }
        return data as Data
    }

    /// Klasörü gerekirse oluşturup PNG yazar.
    public static func write(_ image: CGImage, to url: URL) throws {
        let data = try data(from: image)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .withoutOverwriting)
    }
}
