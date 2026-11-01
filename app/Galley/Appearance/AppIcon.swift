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
        // nil puts the bundle's own icon back, at every Dock size.
        NSApp.applicationIconImage = id == standard ? nil : image(id)
    }
}
