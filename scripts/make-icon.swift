// Generates Sources/Shutterbar/Assets.xcassets/AppIcon.appiconset from code (no third-party artwork).
// Run: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconSet = root.appendingPathComponent("Sources/Shutterbar/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

/// Draws the icon on a 1024×1024 canvas, following the macOS icon grid (824 pt body, ~185 pt corner radius).
func drawIcon(in ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Background gradient: deep indigo to violet.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let colors = [CGColor(srgbRed: 0.20, green: 0.22, blue: 0.62, alpha: 1),
                  CGColor(srgbRed: 0.47, green: 0.29, blue: 0.86, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.minY), end: CGPoint(x: body.maxX, y: body.maxY), options: [])

    // Dimmed "frozen screen" with a bright selected region.
    let selection = CGRect(x: 330, y: 360, width: 364, height: 270)
    ctx.setFillColor(CGColor(gray: 0, alpha: 0.18))
    ctx.addRect(body)
    ctx.addRect(selection)
    ctx.fillPath(using: .evenOdd)
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.16))
    ctx.fill(selection)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
    ctx.setLineWidth(6)
    ctx.setLineDash(phase: 0, lengths: [22, 14])
    ctx.stroke(selection)
    ctx.setLineDash(phase: 0, lengths: [])

    // Viewfinder corner brackets.
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
    ctx.setLineWidth(46)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let inset: CGFloat = 215, arm: CGFloat = 150
    let minX = body.minX + inset - 60, maxX = body.maxX - inset + 60
    let minY = body.minY + inset - 60, maxY = body.maxY - inset + 60
    for (corner, dx, dy) in [(CGPoint(x: minX, y: minY), 1.0, 1.0), (CGPoint(x: maxX, y: minY), -1.0, 1.0),
                             (CGPoint(x: minX, y: maxY), 1.0, -1.0), (CGPoint(x: maxX, y: maxY), -1.0, -1.0)] {
        ctx.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        ctx.addLine(to: corner)
        ctx.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
    }
    ctx.strokePath()

    // Crosshair at the selection's corner (the cursor).
    let cursor = CGPoint(x: selection.maxX, y: selection.minY)
    ctx.setLineWidth(18)
    ctx.move(to: CGPoint(x: cursor.x - 44, y: cursor.y)); ctx.addLine(to: CGPoint(x: cursor.x + 44, y: cursor.y))
    ctx.move(to: CGPoint(x: cursor.x, y: cursor.y - 44)); ctx.addLine(to: CGPoint(x: cursor.x, y: cursor.y + 44))
    ctx.strokePath()
    ctx.restoreGState()
}

func render(pixels: Int) -> Data {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale)
    drawIcon(in: ctx)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: points * scale).write(to: iconSet.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appendingPathComponent("Contents.json"))
let catalog: [String: Any] = ["info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted])
    .write(to: iconSet.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(iconSet.path)")
