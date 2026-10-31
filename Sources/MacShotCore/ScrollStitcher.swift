import CoreGraphics
import Foundation

/// RGBA8 pixels of one frame, top row first.
public struct PixelBuffer: Sendable {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8]

    public init?(image: CGImage) {
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
        self.width = width
        self.height = height
        bytes = buffer
    }

    /// Color with the low bits dropped, so tiny rendering differences don't count as changes.
    @inline(__always)
    func quantized(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
        let i = (y * width + x) * 4
        return (bytes[i] >> 3, bytes[i + 1] >> 3, bytes[i + 2] >> 3)
    }
}

/// Per-row fingerprints of one frame over a column band. Rows are top to bottom.
public struct RowSignatures: Equatable, Sendable {
    public let hashes: [UInt64]
    /// Rows with visible content (not a single flat color). Flat rows match anywhere, so they are ignored when matching.
    public let informative: [Bool]

    public var count: Int { hashes.count }

    public init(hashes: [UInt64], informative: [Bool]) {
        self.hashes = hashes
        self.informative = informative
    }

    public init(buffer: PixelBuffer, columns: Range<Int>) {
        let columns = columns.clamped(to: 0..<buffer.width)
        var hashes = [UInt64](repeating: 0, count: buffer.height)
        var informative = [Bool](repeating: false, count: buffer.height)
        for y in 0..<buffer.height {
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            let first = columns.isEmpty ? (0, 0, 0) : buffer.quantized(columns.lowerBound, y)
            var flat = true
            for x in columns {
                let (r, g, b) = buffer.quantized(x, y)
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

    /// - Parameter excludingTrailing: pixels ignored at the right edge (the overlay scroll bar appears there while scrolling).
    public init?(image: CGImage, excludingTrailing: Int = 0) {
        guard let buffer = PixelBuffer(image: image) else { return nil }
        self.init(buffer: buffer, columns: 0..<max(1, buffer.width - max(0, excludingTrailing)))
    }
}

public enum ScrollStitcher {
    /// The columns that scroll: the longest run of columns that are not *static content* (identical in both frames
    /// and not a flat color — e.g. a fixed sidebar). Flat columns (page margins) stay in, since they may hold wider
    /// content further down. Falls back to the full width when the run would be implausibly narrow.
    public static func scrollingColumns(_ a: PixelBuffer, _ b: PixelBuffer, minimumFraction: Double = 0.2) -> Range<Int> {
        let full = 0..<a.width
        guard a.width == b.width, a.height == b.height else { return full }
        var bestStart = 0, bestLength = 0, runStart = 0
        for x in 0...a.width {
            let isStatic: Bool
            if x == a.width {
                isStatic = true
            } else {
                var identical = true, flat = true
                let top = a.quantized(x, 0)
                for y in 0..<a.height {
                    let pa = a.quantized(x, y)
                    if identical, pa != b.quantized(x, y) { identical = false }
                    if flat, pa != top { flat = false }
                    if !identical, !flat { break }
                }
                isStatic = identical && !flat
            }
            if isStatic {
                if x - runStart > bestLength { bestStart = runStart; bestLength = x - runStart }
                runStart = x + 1
            }
        }
        guard Double(bestLength) >= Double(a.width) * minimumFraction else { return full }
        return bestStart..<(bestStart + bestLength)
    }

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
    private var lastBuffer: PixelBuffer?
    /// Fixed from the first pair of frames that differ.
    private var columns: Range<Int>?
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

    /// Columns used for matching: the scrolling band minus the scroll-bar strip at its right edge.
    private func matchColumns(_ band: Range<Int>) -> Range<Int> {
        let trimmed = band.lowerBound..<max(band.lowerBound + 1, band.upperBound - excludedTrailingColumns)
        return trimmed
    }

    public mutating func add(_ frame: CGImage) -> AddResult {
        guard let buffer = PixelBuffer(image: frame) else { return .lost }
        guard let previous = lastBuffer, let first = firstFrame else {
            firstFrame = frame
            lastFrame = frame
            lastBuffer = buffer
            pieces = [Piece(image: frame, rows: 0..<frame.height)]
            contentHeight = frame.height
            return .first
        }
        guard frame.width == first.width, frame.height == first.height else { return .lost }
        if height >= maximumHeight { return .full }

        let band = columns ?? ScrollStitcher.scrollingColumns(previous, buffer)
        let previousSignatures = RowSignatures(buffer: previous, columns: matchColumns(band))
        let signatures = RowSignatures(buffer: buffer, columns: matchColumns(band))
        let bands = self.bands ?? ScrollStitcher.staticBands(previousSignatures, signatures)
        guard let dy = ScrollStitcher.offset(from: previousSignatures, to: signatures, top: bands.top, bottom: bands.bottom) else {
            return .lost
        }
        guard dy > 0 else { return .unchanged }

        if self.bands == nil {
            // First real scroll: fix the column band and sticky bands, trim the first frame to the scrolling content.
            columns = band
            self.bands = bands
            pieces = [Piece(image: first, rows: bands.top..<(first.height - bands.bottom))]
            contentHeight = first.height - bands.top - bands.bottom
        }
        let end = frame.height - bands.bottom
        pieces.append(Piece(image: frame, rows: (end - dy)..<end))
        contentHeight += dy
        lastFrame = frame
        lastBuffer = buffer
        return .appended(dy)
    }

    /// Header from the first frame + scrolled content + footer from the last frame, cropped to the scrolling columns
    /// (a fixed sidebar would otherwise repeat down the image).
    public func makeImage() -> CGImage? {
        guard let first = firstFrame, let last = lastFrame else { return nil }
        guard let bands, let columns else { return first }
        let width = columns.count
        let total = bands.top + contentHeight + bands.bottom
        guard let context = CGContext(
            data: nil, width: width, height: total, bitsPerComponent: 8, bytesPerRow: 0,
            space: first.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        var y = 0 // top-left based destination row
        func draw(_ image: CGImage, rows: Range<Int>) {
            let source = CGRect(x: columns.lowerBound, y: rows.lowerBound, width: width, height: rows.count)
            guard !rows.isEmpty, let slice = image.cropping(to: source) else { return }
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
