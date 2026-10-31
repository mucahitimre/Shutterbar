import CoreGraphics
import MacShotCore
import Testing

/// RGBA8 pixel reader; (x, y) with top-left origin.
private struct Pixels {
    let width: Int, height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        bytes = buffer
    }

    /// In memory, row 0 is the top row.
    subscript(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2])
    }

    func isRed(_ x: Int, _ y: Int) -> Bool { let p = self[x, y]; return p.r > 180 && p.g < 120 && p.b < 120 }
    func isWhite(_ x: Int, _ y: Int) -> Bool { let p = self[x, y]; return p.r > 240 && p.g > 240 && p.b > 240 }
}

private func makeImage(width: Int = 100, height: Int = 100, fill: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    fill(ctx)
    return ctx.makeImage()!
}

private let white = makeImage { ctx in
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
}

struct AnnotationRendererTests {
    @Test func pixelReaderOrientationIsTopLeft() {
        // Validates the measuring tool: y=90..100 in CGContext (bottom-left origin) = the top 10 rows of the image.
        let image = makeImage { ctx in
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 90, width: 100, height: 10))
        }
        let px = Pixels(image)
        #expect(px.isRed(50, 5))
        #expect(px.isWhite(50, 95))
    }

    @Test func rectangleStrokesInsideRect() throws {
        let out = try #require(AnnotationRenderer.render([Annotation(.rectangle(CGRect(x: 10, y: 10, width: 50, height: 50)))], on: white))
        let px = Pixels(out)
        #expect(px.isRed(11, 30))
        #expect(px.isRed(30, 58))
        #expect(px.isWhite(35, 35))
        #expect(px.isWhite(5, 5))
        #expect(px.isWhite(65, 30))
    }

    @Test func arrowNearTopStaysAtTop() throws {
        let out = try #require(AnnotationRenderer.render([Annotation(.arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 10)))], on: white))
        let px = Pixels(out)
        #expect(px.isRed(40, 10))
        #expect(px.isWhite(40, 90))
    }

    @Test func pixelateMakesUniformBlocksAndKeepsOutside() throws {
        // 1 px checkerboard.
        let checker = makeImage { ctx in
            for y in 0..<100 { for x in 0..<100 {
                let on = (x + y) % 2 == 0
                ctx.setFillColor(CGColor(srgbRed: on ? 1 : 0, green: on ? 1 : 0, blue: on ? 1 : 0, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            } }
        }
        let out = try #require(AnnotationRenderer.render([Annotation(.pixelate(CGRect(x: 0, y: 0, width: 24, height: 24)))], on: checker))
        let before = Pixels(checker), after = Pixels(out)
        // Inside the region, each 12×12 block is a single color.
        #expect(after[1, 1] == after[10, 10])
        #expect(after[1, 1] == after[11, 0])
        #expect(before[1, 1] != before[2, 1])
        // Outside the region is unchanged.
        #expect(after[50, 50] == before[50, 50])
        #expect(after[30, 5] == before[30, 5])
    }

    @Test func textDrawsBelowOriginUpright() throws {
        let out = try #require(AnnotationRenderer.render([Annotation(.text("Hg", origin: CGPoint(x: 5, y: 5)), lineWidth: 4)], on: white))
        let px = Pixels(out)
        let size = AnnotationRenderer.textSize("Hg", fontSize: 24)
        var inked = 0, outside = 0
        for y in 0..<100 { for x in 0..<100 where !px.isWhite(x, y) {
            if y >= 3, y <= 5 + Int(size.height) + 2 { inked += 1 } else { outside += 1 }
        } }
        #expect(inked > 20)
        #expect(outside == 0)
    }

    @Test func numberBadgeFillsCircle() throws {
        let out = try #require(AnnotationRenderer.render([Annotation(.number(1, center: CGPoint(x: 50, y: 50)), lineWidth: 4)], on: white))
        let px = Pixels(out)
        #expect(px.isRed(50 - 12, 50))
        #expect(px.isWhite(50 - 20, 50))
    }
}

struct AnnotationDocumentTests {
    @Test func undoRedo() {
        var doc = AnnotationDocument()
        let a = Annotation(.rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)))
        let b = Annotation(.arrow(from: .zero, to: CGPoint(x: 5, y: 5)))
        doc.add(a)
        doc.add(b)
        doc.undo()
        #expect(doc.items == [a])
        #expect(doc.canRedo)
        doc.redo()
        #expect(doc.items == [a, b])
        doc.undo()
        doc.add(a)
        #expect(!doc.canRedo)
    }

    @Test func numbersIncrementAndFollowUndo() {
        var doc = AnnotationDocument()
        #expect(doc.nextNumber == 1)
        doc.add(Annotation(.number(1, center: .zero)))
        doc.add(Annotation(.number(2, center: .zero)))
        #expect(doc.nextNumber == 3)
        doc.undo()
        #expect(doc.nextNumber == 2)
    }

    @Test func removeAllIsUndoableViaRedo() {
        var doc = AnnotationDocument()
        let a = Annotation(.rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)))
        doc.add(a)
        doc.removeAll()
        #expect(doc.items.isEmpty)
        doc.redo()
        #expect(doc.items == [a])
    }
}
