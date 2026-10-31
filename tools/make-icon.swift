// Draws Galley's placeholder app icon — a sheet of paper with ruled lines,
// one of them washed and flagged by a change bar in the margin — and writes
// every size the macOS asset catalog needs.
// Usage: swift tools/make-icon.swift app/Galley/Assets.xcassets/AppIcon.appiconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(in ctx: CGContext) {
    // Apple's macOS grid: an 824 pt squircle centred on a 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.28))
    ctx.addPath(shape)
    ctx.setFillColor(color(0xF3EEE3))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let paper = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [color(0xFFFDF8), color(0xEEE7D8)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(paper, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Ruled text: a title, then body lines of varied length.
    let ink = color(0x26231F, 0.9)
    let left: CGFloat = 268
    func line(_ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ fill: CGColor) {
        let rect = CGRect(x: left, y: y - height / 2, width: width, height: height)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil))
        ctx.setFillColor(fill)
        ctx.fillPath()
    }
    line(728, 330, 50, ink)
    let body: [(CGFloat, CGFloat)] = [(612, 488), (544, 452), (476, 488), (408, 396), (340, 470), (272, 300)]
    // The changed passage: a highlighter wash under two lines.
    let wash = CGRect(x: left - 22, y: 476 - 40, width: 488 + 44, height: 544 - 476 + 80)
    ctx.addPath(CGPath(roundedRect: wash, cornerWidth: 18, cornerHeight: 18, transform: nil))
    ctx.setFillColor(color(0xF2B94A, 0.32))
    ctx.fillPath()
    for (y, width) in body { line(y, width, 26, color(0x26231F, 0.55)) }
    // The change bar in the margin.
    let bar = CGRect(x: 188, y: 476 - 40, width: 18, height: 544 - 476 + 80)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 9, cornerHeight: 9, transform: nil))
    ctx.setFillColor(color(0xD3802A))
    ctx.fillPath()
    ctx.restoreGState()

    // A hairline edge so the tile holds its shape on light backgrounds.
    ctx.addPath(shape)
    ctx.setStrokeColor(color(0x000000, 0.08))
    ctx.setLineWidth(2)
    ctx.strokePath()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = context.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    ctx.interpolationQuality = .high
    drawIcon(in: ctx)
    return rep.representation(using: .png, properties: [:])!
}

var images: [String] = []
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try! render(pixels: points * scale).write(to: output.appendingPathComponent(name))
    images.append("""
        { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(points)x\(points)" }
    """)
}
let contents = "{\n  \"images\" : [\n\(images.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try! contents.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(images.count) icons to \(output.path)")
