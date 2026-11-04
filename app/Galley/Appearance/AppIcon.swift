import AppKit

/// Galley's icon in other palettes (drawn by `tools/make-icon.swift
/// --variants`). The pick is the Dock icon while Galley runs; a sandboxed
/// app cannot change the icon Finder shows, so Finder keeps the standard one.
enum AppIcon {
    static let standard = "paper"

    static let variants: [(id: String, name: String)] = [
        ("paper", "Paper"), ("snow", "Snow"), ("sepia", "Sepia"), ("lavender", "Lavender"), ("mint", "Mint"),
        ("solarized", "Solarized"), ("graphite", "Graphite"), ("midnight", "Midnight"), ("rose-pine", "Rosé Pine"), ("nord", "Nord"),
    ]

    static func image(_ id: String) -> NSImage? {
        NSImage(named: "AppIconVariant-\(id)")
    }

    @MainActor
    static func apply(_ id: String) {
        // nil puts the bundle's own icon back, at every Dock size. In a Debug
        // build that is AppIcon-Debug, already banded.
        #if DEBUG
        NSApp.applicationIconImage = id == standard ? nil : image(id).map(withDebugBand)
        #else
        NSApp.applicationIconImage = id == standard ? nil : image(id)
        #endif
    }

    #if DEBUG
    /// A variant with the band `tools/make-icon.swift --debug` draws on
    /// AppIcon-Debug, so a Debug build is told apart whichever icon it wears.
    /// Same geometry, on the icon's 1024 grid; keep the two alike.
    private static func withDebugBand(_ base: NSImage) -> NSImage {
        NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            let unit = rect.width / 1024
            let tile = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: tile, xRadius: 186 * unit, yRadius: 186 * unit).addClip()
            NSColor(srgbRed: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255, alpha: 1).setFill()
            NSRect(x: tile.minX, y: tile.minY, width: tile.width, height: 190 * unit).fill()
            NSGraphicsContext.restoreGraphicsState()
            let text = NSAttributedString(string: "DEBUG", attributes: [
                .font: NSFont.systemFont(ofSize: 112 * unit, weight: .heavy),
                .foregroundColor: NSColor.white,
                .kern: 10 * unit,
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: 512 * unit - size.width / 2, y: 195 * unit - size.height / 2))
            return true
        }
    }
    #endif
}
