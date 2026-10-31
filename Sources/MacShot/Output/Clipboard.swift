import AppKit
import MacShotCore

/// Görüntüleri panoya PNG + TIFF olarak yazar (dosya URL'si yok). Birden çok görüntü ayrı item olur.
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

    static func write(_ images: [CGImage], to pasteboard: NSPasteboard = .general) throws {
        var items: [NSPasteboardItem] = []
        for image in images {
            let png = try PNGEncoder.data(from: image)
            guard let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation else {
                throw ClipboardError.encodingFailed
            }
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            item.setData(tiff, forType: .tiff)
            items.append(item)
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(items) else { throw ClipboardError.writeFailed }
    }
}
