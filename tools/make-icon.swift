// Draws Galley's app icon — a sheet of paper with ruled lines,
// one of them washed and flagged by a change bar in the margin — and writes
// every size the macOS asset catalog needs.
// Usage: swift tools/make-icon.swift app/Galley/Assets.xcassets/AppIcon.appiconset
//        swift tools/make-icon.swift --debug app/Galley/Assets.xcassets/AppIcon-Debug.appiconset
//        swift tools/make-icon.swift --variants app/Galley/Assets.xcassets
// `--debug` adds a DEBUG band along the foot, for Debug builds, so a copy
// built here never looks like the installed one. `--variants` draws the
// same sheet in each palette below, as image sets (`AppIconVariant-<id>`)
// for Settings → App Icon; the Dock shows the pick.
import AppKit

/// One way to colour the sheet: paper top and bottom, ink, the changed
/// passage's wash and its margin bar.
struct Palette {
    let id: String
    let paperTop: UInt32, paperBottom: UInt32
    let ink: UInt32
    let wash: UInt32, washAlpha: CGFloat
    let bar: UInt32
    /// The tile under the paper, seen only at its shadowed edge.
    var tile: UInt32? = nil
}

let variants: [Palette] = [
    Palette(id: "paper", paperTop: 0xFFFDF8, paperBottom: 0xEEE7D8, ink: 0x26231F, wash: 0xF2B94A, washAlpha: 0.32, bar: 0xD3802A, tile: 0xF3EEE3),
    Palette(id: "snow", paperTop: 0xFFFFFF, paperBottom: 0xECEEF2, ink: 0x1D1D1F, wash: 0x0A84FF, washAlpha: 0.16, bar: 0x0A84FF),
    Palette(id: "sepia", paperTop: 0xF8F0DF, paperBottom: 0xE6D7BB, ink: 0x3A2F24, wash: 0xC4802E, washAlpha: 0.3, bar: 0xB8661A),
    Palette(id: "lavender", paperTop: 0xFBF8FF, paperBottom: 0xE9E0F7, ink: 0x2B2540, wash: 0x9262DE, washAlpha: 0.26, bar: 0x8A5AD6),
    Palette(id: "mint", paperTop: 0xF6FBF7, paperBottom: 0xDAEDE0, ink: 0x1F2B24, wash: 0x3FA36A, washAlpha: 0.24, bar: 0x2E8B57),
    Palette(id: "solarized", paperTop: 0xFDF6E3, paperBottom: 0xEDE6D1, ink: 0x073642, wash: 0x268BD2, washAlpha: 0.18, bar: 0xCB4B16),
    Palette(id: "graphite", paperTop: 0x3A3A3D, paperBottom: 0x1D1D1F, ink: 0xE6E4E0, wash: 0xE3A64E, washAlpha: 0.28, bar: 0xE3A64E),
    Palette(id: "midnight", paperTop: 0x232B3A, paperBottom: 0x111419, ink: 0xD7DBE2, wash: 0x82B1FF, washAlpha: 0.24, bar: 0xF0BF4F),
    Palette(id: "rose-pine", paperTop: 0x2A273F, paperBottom: 0x191724, ink: 0xE0DEF4, wash: 0xC4A7E7, washAlpha: 0.3, bar: 0xEBBCBA),
    Palette(id: "nord", paperTop: 0x434C5E, paperBottom: 0x2E3440, ink: 0xECEFF4, wash: 0x88C0D0, washAlpha: 0.26, bar: 0xEBCB8B),
]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(in ctx: CGContext, _ palette: Palette = variants[0]) {
    // Apple's macOS grid: an 824 pt squircle centred on a 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.28))
    ctx.addPath(shape)
    ctx.setFillColor(color(palette.tile ?? palette.paperBottom))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let paper = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [color(palette.paperTop), color(palette.paperBottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(paper, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Ruled text: a title, then body lines of varied length.
    let ink = color(palette.ink, 0.9)
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
    ctx.setFillColor(color(palette.wash, palette.washAlpha))
    ctx.fillPath()
    for (y, width) in body { line(y, width, 26, color(palette.ink, 0.55)) }
    // The change bar in the margin.
    let bar = CGRect(x: 188, y: 476 - 40, width: 18, height: 544 - 476 + 80)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 9, cornerHeight: 9, transform: nil))
    ctx.setFillColor(color(palette.bar))
    ctx.fillPath()
    ctx.restoreGState()

    if debugBand { drawDebugBand(in: ctx, clippedTo: shape) }

    // A hairline edge so the tile holds its shape on light backgrounds.
    ctx.addPath(shape)
    ctx.setStrokeColor(color(0x000000, 0.08))
    ctx.setLineWidth(2)
    ctx.strokePath()
}

/// Debug builds' mark: a red band across the foot of the tile, lettered
/// DEBUG. Mirrored for the colour variants in `AppIcon.swift`; keep the two
/// alike.
func drawDebugBand(in ctx: CGContext, clippedTo shape: CGPath) {
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.setFillColor(color(0xE5484D))
    ctx.fill(CGRect(x: 100, y: 100, width: 824, height: 190))
    ctx.restoreGState()

    let text = NSAttributedString(string: "DEBUG", attributes: [
        .font: NSFont.systemFont(ofSize: 112, weight: .heavy),
        .foregroundColor: NSColor.white,
        .kern: 10,
    ])
    let size = text.size()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    text.draw(at: CGPoint(x: 512 - size.width / 2, y: 195 - size.height / 2))
    NSGraphicsContext.restoreGraphicsState()
}

func render(pixels: Int, _ palette: Palette = variants[0]) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = context.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    ctx.interpolationQuality = .high
    drawIcon(in: ctx, palette)
    return rep.representation(using: .png, properties: [:])!
}

var arguments = Array(CommandLine.arguments.dropFirst())
let debugBand = arguments.first == "--debug"
if debugBand { arguments.removeFirst() }

if arguments.first == "--variants" {
    let catalog = URL(fileURLWithPath: arguments.dropFirst().first ?? ".")
    for palette in variants {
        let set = catalog.appendingPathComponent("AppIconVariant-\(palette.id).imageset")
        try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        try! render(pixels: 512, palette).write(to: set.appendingPathComponent("icon.png"))
        try! render(pixels: 1024, palette).write(to: set.appendingPathComponent("icon@2x.png"))
        let contents = """
        {
          "images" : [
            { "filename" : "icon.png", "idiom" : "mac", "scale" : "1x" },
            { "filename" : "icon@2x.png", "idiom" : "mac", "scale" : "2x" }
          ],
          "info" : { "author" : "xcode", "version" : 1 }
        }

        """
        try! contents.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    }
    print("wrote \(variants.count) icon variants to \(catalog.path)")
    exit(0)
}

let output = URL(fileURLWithPath: arguments.first ?? ".")
try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
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
