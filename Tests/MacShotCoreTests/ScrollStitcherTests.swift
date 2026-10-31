import CoreGraphics
import Foundation
import MacShotCore
import Testing

/// A synthetic page: distinct rows, some flat blank blocks, plus a sticky header and footer added per frame.
fileprivate struct Page {
    static let width = 120
    let height: Int
    let header = 24, footer = 16, viewport = 200

    /// RGBA8 rows, top to bottom.
    func pixel(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
        if (300..<330).contains(y) || (610..<640).contains(y) || (900..<1000).contains(y) { return (250, 250, 250) } // flat blank blocks
        // Non-repeating rows (a periodic pattern would create false matches).
        let row = Page.mix(UInt64(y))
        let v = Page.mix(row &+ UInt64(x / 12))
        return (UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: row >> 16))
    }

    static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    func header(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) { (UInt8(40 + y), 20, UInt8(x % 200)) }
    func footer(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) { (10, UInt8(60 + y), UInt8((x * 2) % 200)) }

    /// The frame visible at scroll offset `s`. `noise` changes the trailing 8 columns (an overlay scroll bar).
    /// `sidebar`: a static column band on the left (navigation that doesn't scroll), as in a whole-window selection.
    /// `jitter`: per-frame noise of up to ±12 per channel on content pixels, like the antialiasing browsers
    /// re-rasterize while scrolling (frames are then never pixel-identical).
    func frame(at s: Int, noise: UInt8 = 0, sidebar: Int = 0, jitter: UInt64? = nil) -> CGImage {
        makeImage(width: Page.width + sidebar, height: viewport) { x, y in
            if x < sidebar { return (UInt8(30 + (y * 7) % 90), UInt8(x * 3), 90) }
            let x = x - sidebar
            if x >= Page.width - 8 { return (noise, noise, noise) }
            if y < header { return self.header(x, y) }
            if y >= viewport - footer { return self.footer(x, y - (viewport - footer)) }
            let p = pixel(x, s + y - header)
            guard let jitter, p != (250, 250, 250) else { return p }
            let n = Page.mix(jitter &* 1_000_003 &+ UInt64(y * 4096 + x))
            func shake(_ v: UInt8, _ shift: UInt64) -> UInt8 {
                UInt8(clamping: Int(v) + Int((n >> shift) % 25) - 12)
            }
            return (shake(p.0, 0), shake(p.1, 8), shake(p.2, 16))
        }
    }

    /// What the stitched result should be after scrolling to `s`.
    func expected(lastScroll s: Int) -> CGImage {
        let content = viewport - header - footer
        let total = header + s + content + footer
        return makeImage(width: Page.width, height: total) { x, y in
            if y < header { return self.header(x, y) }
            if y >= total - footer { return self.footer(x, y - (total - footer)) }
            return pixel(x, y - header)
        }
    }
}

private func makeImage(width: Int, height: Int, _ color: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let (r, g, b) = color(x, y)
            let i = (y * width + x) * 4
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b
        }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

private func rgba(_ image: CGImage) -> [UInt8] {
    var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
    buffer.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return buffer
}

/// Compares two images ignoring the trailing scroll-bar columns.
private func sameIgnoringTrailing(_ a: CGImage, _ b: CGImage, trailing: Int) -> Bool {
    guard a.width == b.width, a.height == b.height else { return false }
    let pa = rgba(a), pb = rgba(b)
    for y in 0..<a.height {
        for x in 0..<(a.width - trailing) {
            let i = (y * a.width + x) * 4
            if pa[i] != pb[i] || pa[i + 1] != pb[i + 1] || pa[i + 2] != pb[i + 2] { return false }
        }
    }
    return true
}

struct ScrollStitcherTests {
    fileprivate let page = Page(height: 1200)

    @Test func comparatorDetectsDifferences() {
        // Validate the measuring tool first.
        #expect(sameIgnoringTrailing(page.frame(at: 0), page.frame(at: 0, noise: 99), trailing: 8))
        #expect(!sameIgnoringTrailing(page.frame(at: 0), page.frame(at: 1), trailing: 8))
    }

    @Test func staticBandsFindHeaderAndFooter() throws {
        let a = try #require(RowSignatures(image: page.frame(at: 0), excludingTrailing: 8))
        let b = try #require(RowSignatures(image: page.frame(at: 50), excludingTrailing: 8))
        let bands = ScrollStitcher.staticBands(a, b)
        #expect(bands.top == page.header)
        #expect(bands.bottom == page.footer)
    }

    @Test func offsetMatchesScrollDistance() throws {
        let a = try #require(RowSignatures(image: page.frame(at: 100), excludingTrailing: 8))
        let b = try #require(RowSignatures(image: page.frame(at: 163), excludingTrailing: 8))
        #expect(ScrollStitcher.offset(from: a, to: b, top: page.header, bottom: page.footer) == 63)
        #expect(ScrollStitcher.offset(from: a, to: a, top: page.header, bottom: page.footer) == 0)
    }

    @Test func scrollingUpOrTooFarIsNotMatched() throws {
        let a = try #require(RowSignatures(image: page.frame(at: 400), excludingTrailing: 8))
        let up = try #require(RowSignatures(image: page.frame(at: 350), excludingTrailing: 8))
        let far = try #require(RowSignatures(image: page.frame(at: 560), excludingTrailing: 8))
        #expect(ScrollStitcher.offset(from: a, to: up, top: page.header, bottom: page.footer) == nil)
        #expect(ScrollStitcher.offset(from: a, to: far, top: page.header, bottom: page.footer) == nil)
    }

    @Test func stitchesFramesIntoThePage() throws {
        var capture = ScrollingCapture(excludedTrailingColumns: 8)
        let scrolls = [0, 40, 40, 95, 180, 290, 345, 420, 530, 640, 700]
        var results: [ScrollingCapture.AddResult] = []
        for (i, s) in scrolls.enumerated() {
            results.append(capture.add(page.frame(at: s, noise: UInt8(i * 20))))
        }
        #expect(results[0] == .first)
        #expect(results[2] == .unchanged)
        #expect(!results.contains(.lost))
        let image = try #require(capture.makeImage())
        #expect(image.height == page.header + 700 + (page.viewport - page.header - page.footer) + page.footer)
        #expect(sameIgnoringTrailing(image, page.expected(lastScroll: 700), trailing: 8))
    }

    @Test func lostFrameIsSkippedAndStitchingContinues() throws {
        var capture = ScrollingCapture(excludedTrailingColumns: 8)
        _ = capture.add(page.frame(at: 0))
        _ = capture.add(page.frame(at: 60))
        #expect(capture.add(page.frame(at: 400)) == .lost)
        #expect(capture.add(page.frame(at: 120)) == .appended(60))
        let image = try #require(capture.makeImage())
        #expect(sameIgnoringTrailing(image, page.expected(lastScroll: 120), trailing: 8))
    }

    @Test func singleFrameReturnsItself() throws {
        var capture = ScrollingCapture()
        let frame = page.frame(at: 0)
        _ = capture.add(frame)
        #expect(capture.height == frame.height)
        let image = try #require(capture.makeImage())
        #expect(sameIgnoringTrailing(image, frame, trailing: 0))
    }

    @Test func stopsAtMaximumHeight() {
        var capture = ScrollingCapture(maximumHeight: 300, excludedTrailingColumns: 8)
        _ = capture.add(page.frame(at: 0))
        _ = capture.add(page.frame(at: 100))
        #expect(capture.height >= 300)
        #expect(capture.add(page.frame(at: 150)) == .full)
    }

    @Test func overlapThatIsEntirelyBlankCannotBeMatched() throws {
        // Rows 900..<1000 are blank: from 840 to 950 the overlap (950..<1000) has no content, so the shift is unknowable.
        let a = try #require(RowSignatures(image: page.frame(at: 840), excludingTrailing: 8))
        let b = try #require(RowSignatures(image: page.frame(at: 950), excludingTrailing: 8))
        #expect(ScrollStitcher.offset(from: a, to: b, top: page.header, bottom: page.footer) == nil)
    }

    @Test func staticSidebarDoesNotBreakStitching() throws {
        // Reproduces a whole-window selection: a fixed sidebar on the left, only the content scrolls.
        var capture = ScrollingCapture(excludedTrailingColumns: 8)
        let sidebar = 40
        let scrolls = [0, 50, 120, 200, 260]
        var results: [ScrollingCapture.AddResult] = []
        for (i, s) in scrolls.enumerated() {
            results.append(capture.add(page.frame(at: s, noise: UInt8(i * 30), sidebar: sidebar)))
        }
        #expect(!results.contains(.lost))
        let image = try #require(capture.makeImage())
        // The output is the scrolling band only (the sidebar would otherwise repeat down the image).
        #expect(image.width == Page.width)
        #expect(sameIgnoringTrailing(image, page.expected(lastScroll: 260), trailing: 8))
    }

    @Test func flatMarginsStayInTheScrollingBand() throws {
        // A plain white margin does not change while scrolling, but it is not content: keep it (wider content may come).
        let a = try #require(PixelBuffer(image: makeImage(width: 100, height: 60) { x, y in
            x < 20 ? (255, 255, 255) : (UInt8((x * 7 + y * 13) % 251), UInt8(y % 251), 40)
        }))
        let b = try #require(PixelBuffer(image: makeImage(width: 100, height: 60) { x, y in
            x < 20 ? (255, 255, 255) : (UInt8((x * 7 + (y + 5) * 13) % 251), UInt8((y + 5) % 251), 40)
        }))
        #expect(ScrollStitcher.scrollingColumns(a, b) == 0..<100)
    }

    @Test func staticContentColumnsAreExcluded() throws {
        let sidebar: (Int, Int) -> (UInt8, UInt8, UInt8) = { x, y in (UInt8((x * 9 + y * 5) % 251), 10, 200) }
        let a = try #require(PixelBuffer(image: makeImage(width: 100, height: 60) { x, y in
            x < 30 ? sidebar(x, y) : (UInt8((x * 7 + y * 13) % 251), UInt8(y % 251), 40)
        }))
        let b = try #require(PixelBuffer(image: makeImage(width: 100, height: 60) { x, y in
            x < 30 ? sidebar(x, y) : (UInt8((x * 7 + (y + 5) * 13) % 251), UInt8((y + 5) % 251), 40)
        }))
        #expect(ScrollStitcher.scrollingColumns(a, b) == 30..<100)
    }

    @Test func antialiasingNoiseDoesNotBreakMatching() throws {
        // Real browsers redraw text slightly differently after every scroll; exact row hashes never match.
        var capture = ScrollingCapture(excludedTrailingColumns: 8)
        let scrolls = [0, 45, 110, 190, 260, 340]
        var results: [ScrollingCapture.AddResult] = []
        for (i, s) in scrolls.enumerated() {
            results.append(capture.add(page.frame(at: s, noise: UInt8(i * 40), jitter: UInt64(i + 1))))
        }
        #expect(results == [.first, .appended(45), .appended(65), .appended(80), .appended(70), .appended(80)])
        #expect(capture.height == page.header + 340 + (page.viewport - page.header - page.footer) + page.footer)
    }

    @Test func sameFrameDetection() {
        #expect(ScrollStitcher.isSameFrame(page.frame(at: 100), page.frame(at: 100)))
        // Re-rasterization noise is still "the same frame".
        #expect(ScrollStitcher.isSameFrame(page.frame(at: 100, jitter: 1), page.frame(at: 100, jitter: 2)))
        #expect(!ScrollStitcher.isSameFrame(page.frame(at: 100), page.frame(at: 103)))
    }

    @Test func recoversFromABadFirstFrame() throws {
        // The first frame can differ from the rest (e.g. our own outline captured before exclusion applied).
        var capture = ScrollingCapture(excludedTrailingColumns: 8)
        let bad = makeImage(width: Page.width, height: page.viewport) { x, y in (UInt8(x % 256), UInt8(y % 256), 77) }
        #expect(capture.add(bad) == .first)
        #expect(capture.add(page.frame(at: 0)) == .lost)
        #expect(capture.add(page.frame(at: 70)) == .appended(70))
        #expect(capture.add(page.frame(at: 150)) == .appended(80))
        let image = try #require(capture.makeImage())
        #expect(sameIgnoringTrailing(image, page.expected(lastScroll: 150), trailing: 8))
    }
}
