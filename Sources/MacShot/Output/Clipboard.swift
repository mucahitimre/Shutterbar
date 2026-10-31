import AppKit
import MacShotCore

/// Görüntüleri panoya PNG + TIFF olarak yazar; istenirse dosya URL'si de. Birden çok görüntü ayrı item olur.
@MainActor
enum Clipboard {
    enum ClipboardError: LocalizedError {
        case encodingFailed
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .encodingFailed: "görüntü kodlanamadı"
            case .writeFailed: "panoya yazılamadı"
            }
        }
    }

    /// - Parameter fileURLs: verilirse aynı item'a dosya URL'si de eklenir (Finder'a yapıştırınca dosya gelir).
    static func write(_ images: [CGImage], fileURLs: [URL] = [], to pasteboard: NSPasteboard = .general) throws {
        var items: [NSPasteboardItem] = []
        for (index, image) in images.enumerated() {
            let png = try PNGEncoder.data(from: image)
            guard let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation else {
                throw ClipboardError.encodingFailed
            }
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            item.setData(tiff, forType: .tiff)
            if index < fileURLs.count {
                item.setString(fileURLs[index].absoluteString, forType: .fileURL)
            }
            items.append(item)
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(items) else { throw ClipboardError.writeFailed }
    }
}
