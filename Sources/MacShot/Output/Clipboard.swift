import AppKit
import MacShotCore

/// Writes images to the clipboard as PNG + TIFF, plus the file URL if requested. Multiple images become separate items.
@MainActor
enum Clipboard {
    enum ClipboardError: LocalizedError {
        case encodingFailed
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .encodingFailed: "could not encode image"
            case .writeFailed: "could not write to clipboard"
            }
        }
    }

    /// - Parameter fileURLs: if given, the file URL is added to the same item too (pasting into Finder yields the file).
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
