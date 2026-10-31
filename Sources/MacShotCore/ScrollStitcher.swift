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
    /// Number of vertical strips each row is split into. A row matches when most strips match, so a narrow
    /// changing column (scroll bar thumb, caret, small animation) spoils one strip instead of the whole row.
    public static let stripCount = 16
    /// Largest difference in a strip's mean luminance (0–255) that still counts as equal. Browsers re-rasterize
    /// text antialiasing while scrolling, so exact pixel equality does not hold; averaging over a strip cancels it.
    public static let stripTolerance: Float = 4

    public let hashes: [UInt64]
    /// Rows with visible content (not a single flat color). Flat rows match anywhere, so they are ignored when matching.
    public let informative: [Bool]
    /// `stripCount` mean luminances per row, row-major.
    public let strips: [Float]

    public var count: Int { hashes.count }

    public init(hashes: [UInt64], informative: [Bool]) {
        self.hashes = hashes
        self.informative = informative
        strips = hashes.flatMap { Array(repeating: Float($0 % 256), count: Self.stripCount) }
    }

    /// Fraction of strips that are equal between row `a` of these signatures and row `b` of `other`.
    func stripMatch(_ a: Int, _ other: RowSignatures, _ b: Int) -> Double {
        let k = Self.stripCount
        var equal = 0
        for i in 0..<k where abs(strips[a * k + i] - other.strips[b * k + i]) <= Self.stripTolerance { equal += 1 }
        return Double(equal) / Double(k)
    }

    public init(buffer: PixelBuffer, columns: Range<Int>) {
        let columns = columns.clamped(to: 0..<buffer.width)
        let k = Self.stripCount
        var hashes = [UInt64](repeating: 0, count: buffer.height)
        var informative = [Bool](repeating: false, count: buffer.height)
        var strips = [Float](repeating: 0, count: buffer.height * k)
        var stripPixels = [Int](repeating: 0, count: k)
        let width = max(1, columns.count)
        for x in columns { stripPixels[(x - columns.lowerBound) * k / width] += 1 }
        for y in 0..<buffer.height {
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            var sums = [Int](repeating: 0, count: k)
            let first = columns.isEmpty ? (0, 0, 0) : buffer.quantized(columns.lowerBound, y)
            var flat = true
            let rowStart = y * buffer.width * 4
            for x in columns {
                let (r, g, b) = buffer.quantized(x, y)
                if flat, (r, g, b) != first { flat = false }
                for byte in [r, g, b] {
                    hash ^= UInt64(byte)
                    hash &*= 0x0000_0100_0000_01b3
                }
                let i = rowStart + x * 4
                // Rec. 601 luma ×1000, full precision (not quantized).
                sums[(x - columns.lowerBound) * k / width] += 299 * Int(buffer.bytes[i]) + 587 * Int(buffer.bytes[i + 1]) + 114 * Int(buffer.bytes[i + 2])
            }
            for i in 0..<k where stripPixels[i] > 0 {
                strips[y * k + i] = Float(sums[i]) / Float(stripPixels[i] * 1000)
            }
            hashes[y] = hash
            informative[y] = !flat
        }
        self.hashes = hashes
        self.informative = informative
        self.strips = strips
    }

    /// - Parameter excludingTrailing: pixels ignored at the right edge (the overlay scroll bar appears there while scrolling).
    public init?(image: CGImage, excludingTrailing: Int = 0) {
        guard let buffer = PixelBuffer(image: image) else { return nil }
        self.init(buffer: buffer, columns: 0..<max(1, buffer.width - max(0, excludingTrailing)))
    }
}

public enum ScrollStitcher {
    /// The two frames show the same content (within the strip tolerance): used to wait until smooth scrolling
    /// has settled before matching.
    public static func isSameFrame(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height,
              let sa = RowSignatures(image: a), let sb = RowSignatures(image: b) else { return false }
        // Same rule as matching: a row is equal when most strips are; nearly all rows must be equal.
        let equalRows = (0..<sa.count).filter { sa.stripMatch($0, sb, $0) >= 0.75 }.count
        return Double(equalRows) >= Double(sa.count) * 0.98
    }

    /// The columns that scroll: the longest run of columns that are not *static content* — columns whose content
    /// pixels (those differing from the column's dominant color) mostly stay put between the frames, e.g. a fixed
    /// sidebar, even if a hover or fading label changes a few of its rows. Columns with almost no content (page
    /// margins) stay in, since they may hold wider content further down. Falls back to the full width when the run
    /// would be implausibly narrow.
    public static func scrollingColumns(_ a: PixelBuffer, _ b: PixelBuffer, minimumFraction: Double = 0.2) -> Range<Int> {
        let full = 0..<a.width
        guard a.width == b.width, a.height == b.height else { return full }
        // Only rows that change count: a fixed header or footer would make every column through it look static.
        func rowEqual(_ y: Int) -> Bool { (0..<a.width).allSatisfy { a.quantized($0, y) == b.quantized($0, y) } }
        var top = 0
        while top < a.height, rowEqual(top) { top += 1 }
        var bottom = a.height
        while bottom > top, rowEqual(bottom - 1) { bottom -= 1 }
        guard bottom > top else { return full }
        let rows = top..<bottom

        var bestStart = 0, bestLength = 0, runStart = 0
        for x in 0...a.width {
            let isStatic = x < a.width && isStaticContentColumn(x, a, b, rows: rows)
            if isStatic || x == a.width {
                if x - runStart > bestLength { bestStart = runStart; bestLength = x - runStart }
                runStart = x + 1
            }
        }
        guard Double(bestLength) >= Double(a.width) * minimumFraction else { return full }
        return bestStart..<(bestStart + bestLength)
    }

    static func isStaticContentColumn(_ x: Int, _ a: PixelBuffer, _ b: PixelBuffer, rows: Range<Int>? = nil,
                                      minimumContent: Double = 0.02, minimumUnchanged: Double = 0.9) -> Bool {
        let rows = rows ?? 0..<a.height
        var counts: [Int: Int] = [:]
        for y in rows {
            let p = a.quantized(x, y)
            counts[Int(p.0) << 10 | Int(p.1) << 5 | Int(p.2), default: 0] += 1
        }
        guard let dominant = counts.max(by: { $0.value < $1.value })?.key else { return false }
        var content = 0, unchanged = 0, sameAsAbove = 0
        for y in rows {
            let p = a.quantized(x, y)
            guard Int(p.0) << 10 | Int(p.1) << 5 | Int(p.2) != dominant else { continue }
            content += 1
            if p == b.quantized(x, y) { unchanged += 1 }
            if y > rows.lowerBound, p == a.quantized(x, y - 1) { sameAsAbove += 1 }
        }
        guard Double(content) >= Double(rows.count) * minimumContent else { return false }
        // A vertical line (card border, divider) looks the same after any vertical shift: no evidence either way.
        guard Double(sameAsAbove) < Double(content) * 0.8 else { return false }
        return Double(unchanged) >= Double(content) * minimumUnchanged
    }

    /// Fixed bands at the top and bottom (sticky headers / footers): rows identical at the same position in both frames.
    /// Only counted while the middle still changes, so an unchanged frame doesn't become "all static".
    public static func staticBands(_ a: RowSignatures, _ b: RowSignatures) -> (top: Int, bottom: Int) {
        let n = min(a.count, b.count)
        func same(_ row: Int) -> Bool { a.stripMatch(row, b, row) == 1 }
        var top = 0
        while top < n, same(top) { top += 1 }
        guard top < n else { return (0, 0) }
        var bottom = 0
        while bottom < n - top, same(n - 1 - bottom) { bottom += 1 }
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
        minimumMatchRatio: Double = 0.75,
        minimumInformativeRows: Int = 8,
        minimumStripMatch: Double = 0.75,
        minimumLead: Double = 1.5,
        expected: Int? = nil
    ) -> Int? {
        let n = min(a.count, b.count)
        let start = top, end = n - bottom
        let span = end - start
        guard span > 0 else { return nil }
        // Unchanged: every row (mostly) the same in place.
        if (start..<end).allSatisfy({ a.stripMatch($0, b, $0) >= minimumStripMatch }) { return 0 }

        let minOverlap = max(1, Int(Double(span) * minimumOverlap))
        guard span - minOverlap >= 1 else { return nil }
        // When the scroll distance is known (automatic scrolling), only shifts near it are candidates: repetitive
        // layouts (list rows, dividers) can otherwise make a wrong shift look almost as good as the true one.
        var range = 1...(span - minOverlap)
        if let expected, expected > 0 {
            let low = max(1, expected / 4), high = min(span - minOverlap, expected * 2)
            guard low <= high else { return nil }
            range = low...high
        }
        // Score every shift by evidence: matched rows minus twice the mismatched ones. A ratio alone misleads —
        // a shift that compares only a few divider / blank-edge rows can score as high as the true one. Accept the
        // best shift if it matches well enough and clearly outscores every rival outside its own peak (±3 rows).
        // Hover effects or a caret cost the true shift a few rows; repetitive content gives no clear winner.
        var scores: [(dy: Int, ratio: Double, score: Double)] = []
        for dy in range {
            var compared = 0, matched = 0
            for i in 0..<(span - dy) {
                let rowA = start + dy + i, rowB = start + i
                guard a.informative[rowA] || b.informative[rowB] else { continue }
                compared += 1
                if a.stripMatch(rowA, b, rowB) >= minimumStripMatch { matched += 1 }
            }
            if compared >= minimumInformativeRows {
                let evidence = Double(matched - 2 * (compared - matched))
                // With a known distance, shifts far from it lose weight (half at a distance equal to the expected
                // shift), so a repeating layout cannot outvote the scroll we actually made.
                let weight = expected.map { max(0.1, 1 - 0.5 * Double(abs(dy - $0)) / Double($0)) } ?? 1
                scores.append((dy, Double(matched) / Double(compared), evidence * weight))
            }
        }
        guard let best = scores.max(by: { $0.score < $1.score }),
              best.ratio >= minimumMatchRatio, best.score >= Double(minimumInformativeRows)
        else { return nil }
        // The best shift's peak: the contiguous run of shifts around it scoring at least half of it (smooth content
        // gives wide peaks). A real rival — e.g. a repeating layout — sits beyond a valley, outside that run.
        guard let index = scores.firstIndex(where: { $0.dy == best.dy }) else { return nil }
        var low = index, high = index
        while low > 0, scores[low - 1].dy == scores[low].dy - 1, scores[low - 1].score >= best.score / 2 { low -= 1 }
        while high < scores.count - 1, scores[high + 1].dy == scores[high].dy + 1, scores[high + 1].score >= best.score / 2 { high += 1 }
        let rival = scores.indices.filter { $0 < low || $0 > high }.map { scores[$0].score }.max() ?? 0
        return best.score >= minimumLead * max(rival, 0) ? best.dy : nil
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

    /// - Parameter expectedShift: how far the content should have moved, in pixels, when known (automatic scrolling).
    public mutating func add(_ frame: CGImage, expectedShift: Int? = nil) -> AddResult {
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
        guard let dy = ScrollStitcher.offset(from: previousSignatures, to: signatures, top: bands.top, bottom: bands.bottom,
                                             expected: expectedShift) else {
            if self.bands == nil {
                // Nothing stitched yet: the starting frame may be bad (e.g. captured mid-change). Start over from
                // this frame instead of comparing every later frame with it. After stitching began this would
                // leave a gap, so then the frame is only skipped.
                firstFrame = frame
                lastFrame = frame
                lastBuffer = buffer
                pieces = [Piece(image: frame, rows: 0..<frame.height)]
                contentHeight = frame.height
            }
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
