// Generates docs/images/social-preview.png (1280×640), the image GitHub shows when the repository link is shared.
// Upload it in the repository's Settings › General › Social preview (GitHub has no API for it).
// Run: swift scripts/make-social-preview.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let images = root.appendingPathComponent("docs/images")
guard let logo = NSImage(contentsOf: images.appendingPathComponent("logo.png")),
      let shot = NSImage(contentsOf: images.appendingPathComponent("screenshot.png")) else {
    fatalError("docs/images/logo.png or screenshot.png is missing")
}

let size = CGSize(width: 1280, height: 640)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Background: the icon's indigo-to-violet gradient, darkened so white text stays readable.
let colors = [CGColor(srgbRed: 0.10, green: 0.11, blue: 0.33, alpha: 1),
              CGColor(srgbRed: 0.28, green: 0.16, blue: 0.55, alpha: 1)] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])

// Left column: logo, name, tagline, three essentials.
logo.draw(in: CGRect(x: 72, y: 404, width: 150, height: 150))

func draw(_ text: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat = 1) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(white: 1, alpha: alpha),
    ]
    NSAttributedString(string: text, attributes: attributes).draw(at: point)
}
draw("Shutterbar", at: CGPoint(x: 72, y: 312), size: 68, weight: .bold)
draw("ShareX-style screenshots for the Mac", at: CGPoint(x: 74, y: 268), size: 27, weight: .medium, alpha: 0.9)
let essentials = ["⌘C — straight to the clipboard", "After-capture tasks, set once", "Capture the last region again"]
for (index, line) in essentials.enumerated() {
    draw(line, at: CGPoint(x: 74, y: 196 - CGFloat(index) * 42), size: 24, weight: .regular, alpha: 0.85)
}
draw("Free · open source · macOS 14+", at: CGPoint(x: 74, y: 56), size: 20, weight: .medium, alpha: 0.6)

// Right column: the README screenshot, cropped near its top (skipping the window edge) and framed like a window.
let frame = CGRect(x: 640, y: 56, width: 584, height: 528)
let path = CGPath(roundedRect: frame, cornerWidth: 18, cornerHeight: 18, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: CGColor(gray: 0, alpha: 0.5))
ctx.addPath(path)
ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let source = shot.size
let scale = frame.width / source.width
let cropHeight = frame.height / scale
shot.draw(in: frame, from: CGRect(x: 0, y: source.height - cropHeight - 16, width: source.width, height: cropHeight),
          operation: .sourceOver, fraction: 1)
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
let output = images.appendingPathComponent("social-preview.png")
try rep.representation(using: .png, properties: [:])!.write(to: output)
print("wrote \(output.path)")
