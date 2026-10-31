import CoreGraphics
import Foundation

/// Per-row fingerprints of one frame. Rows are top to bottom.
public struct RowSignatures: Equatable, Sendable {
    public let hashes: [UInt64]
    /// Rows with visible content (not a single flat color). Flat rows match anywhere, so they are ignored when matching.
    public let informative: [Bool]

    public var count: Int { hashes.count }

    public init(hashes: [UInt64], informative: [Bool]) {
        self.hashes = hashes
        self.informative = informative
    }

    /// - Parameter excludingTrailing: pixels ignored at the right edge (the overlay scroll bar appears there while scrolling).
    public init?(image: CGImage, excludingTrailing: Int = 0) {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        let columns = max(1, width - max(0, excludingTrailing))
        var hashes = [UInt64](repeating: 0, count: height)
        var informative = [Bool](repeating: false, count: height)
        for y in 0..<height {
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            let rowStart = y * width * 4
            // Drop the low bits so tiny rendering differences don't break a match.
            let first = (buffer[rowStart] >> 3, buffer[rowStart + 1] >> 3, buffer[rowStart + 2] >> 3)
            var flat = true
            for x in 0..<columns {
                let i = rowStart + x * 4
                let r = buffer[i] >> 3, g = buffer[i + 1] >> 3, b = buffer[i + 2] >> 3
                if flat, (r, g, b) != first { flat = false }
                for byte in [r, g, b] {
                    hash ^= UInt64(byte)
                    hash &*= 0x0000_0100_0000_01b3
                }
            }
            hashes[y] = hash
            informative[y] = !flat
        }
        self.hashes = hashes
        self.informative = informative
    }
}

public enum ScrollStitcher {
    /// Fixed bands at the top and bottom (sticky headers / footers): rows identical at the same position in both frames.
    /// Only counted while the middle still changes, so an unchanged frame doesn't become "all static".
    public static func staticBands(_ a: RowSignatures, _ b: RowSignatures) -> (top: Int, bottom: Int) {
        let n = min(a.count, b.count)
        var top = 0
        while top < n, a.hashes[top] == b.hashes[top] { top += 1 }
        guard top < n else { return (0, 0) }
        var bottom = 0
        while bottom < n - top, a.hashes[n - 1 - bottom] == b.hashes[n - 1 - bottom] { bottom += 1 }
        return (top, bottom)
    }

    /// How many rows the content moved up from `a` to `b` (scrolling down), looking only between the static bands.
    /// - Returns: 0 when nothing moved, nil when no reliable match was found (scrolled too far / too fast, or scrolled up).
    public static func offset(
        from a: RowSignatures,
        to b: RowSignatures,
        top: Int,
        bottom: Int,
        minimumOverlap: Double = 0.2,
        minimumMatchRatio: Double = 0.9,
        minimumInformativeRows: Int = 8
    ) -> Int? {
        let n = min(a.count, b.count)
        let start = top, end = n - bottom
        let span = end - start
        guard span > 0 else { return nil }
        if Array(a.hashes[start..<end]) == Array(b.hashes[start..<end]) { return 0 }

        let minOverlap = max(1, Int(Double(span) * minimumOverlap))
        // Smallest shift first: it has the largest overlap, so it is the most trustworthy match.
        for dy in 1...(span - minOverlap) {
            var compared = 0, matched = 0
            for i in 0..<(span - dy) {
                let rowA = start + dy + i, rowB = start + i
                guard a.informative[rowA] || b.informative[rowB] else { continue }
                compared += 1
                if a.hashes[rowA] == b.hashes[rowB] { matched += 1 }
            }
            if compared >= minimumInformativeRows, Double(matched) / Double(compared) >= minimumMatchRatio {
                return dy
            }
        }
        return nil
    }
}

/// Accumulates frames of the same region while the user scrolls and stitches them into one tall image.
public struct ScrollingCapture: Sendable {
    public enum AddResult: Equatable, Sendable {
        case first
        /// New rows were appended.
        case appended(Int)
        case unchanged
        /// The frame could not be matched to the previous one (scrolled too fast, or up); it was skipped.
        case lost
        /// The maximum height was reached; further frames are ignored.
        case full
    }

    public let maximumHeight: Int
    public let excludedTrailingColumns: Int

    private struct Piece: @unchecked Sendable {
        let image: CGImage
        /// Source rows taken from `image`.
        let rows: Range<Int>
    }

    private var firstFrame: CGImage?
    private var lastFrame: CGImage?
    private var lastSignatures: RowSignatures?
    private var bands: (top: Int, bottom: Int)?
    private var pieces: [Piece] = []
    public private(set) var contentHeight = 0

    public init(maximumHeight: Int = 30_000, excludedTrailingColumns: Int = 0) {
        self.maximumHeight = maximumHeight
        self.excludedTrailingColumns = excludedTrailingColumns
    }

    /// Height of the stitched image so far.
    public var height: Int {
        guard let bands else { return firstFrame?.height ?? 0 }
        return bands.top + contentHeight + bands.bottom
    }

    public mutating func add(_ frame: CGImage) -> AddResult {
        guard let signatures = RowSignatures(image: frame, excludingTrailing: excludedTrailingColumns) else { return .lost }
        guard let previous = lastSignatures, let first = firstFrame else {
            firstFrame = frame
            lastFrame = frame
            lastSignatures = signatures
            pieces = [Piece(image: frame, rows: 0..<frame.height)]
            contentHeight = frame.height
            return .first
        }
        guard frame.width == first.width, frame.height == first.height else { return .lost }
        if height >= maximumHeight { return .full }

        // Sticky bands are fixed from the first pair of frames that differ.
        let bands = self.bands ?? ScrollStitcher.staticBands(previous, signatures)
        guard let dy = ScrollStitcher.offset(from: previous, to: signatures, top: bands.top, bottom: bands.bottom) else {
            return .lost
        }
        guard dy > 0 else { return .unchanged }

        if self.bands == nil {
            // Trim the first frame to the scrolling content now that the bands are known.
            self.bands = bands
            pieces = [Piece(image: first, rows: bands.top..<(first.height - bands.bottom))]
            contentHeight = first.height - bands.top - bands.bottom
        }
        let end = frame.height - bands.bottom
        pieces.append(Piece(image: frame, rows: (end - dy)..<end))
        contentHeight += dy
        lastFrame = frame
        lastSignatures = signatures
        return .appended(dy)
    }

    /// Header from the first frame + scrolled content + footer from the last frame.
    public func makeImage() -> CGImage? {
        guard let first = firstFrame, let last = lastFrame else { return nil }
        guard let bands else { return first }
        let width = first.width
        let total = bands.top + contentHeight + bands.bottom
        guard let context = CGContext(
            data: nil, width: width, height: total, bitsPerComponent: 8, bytesPerRow: 0,
            space: first.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        var y = 0 // top-left based destination row
        func draw(_ image: CGImage, rows: Range<Int>) {
            guard !rows.isEmpty, let slice = image.cropping(to: CGRect(x: 0, y: rows.lowerBound, width: width, height: rows.count)) else { return }
            // CGContext is bottom-left based.
            context.draw(slice, in: CGRect(x: 0, y: total - y - rows.count, width: width, height: rows.count))
            y += rows.count
        }
        draw(first, rows: 0..<bands.top)
        for piece in pieces { draw(piece.image, rows: piece.rows) }
        draw(last, rows: (last.height - bands.bottom)..<last.height)
        return context.makeImage()
    }
}
