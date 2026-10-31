#if DEBUG
import AppKit
import WebKit

/// Debug builds only: drives the app from outside with distributed
/// notifications named `com.aliemir.galley.debug.<command>`, for development
/// and the screenshot script (`tools/galley-debug.swift`). Name-only
/// notifications are all a sandboxed app may receive, so arguments are part
/// of the name: `level.3`, `theme.sepia`, `open.2`, `scroll.1200`.
///
/// `snapshot` writes the window — chrome and page composited, no screen
/// recording permission needed — to `/private/tmp/galley-debug/snapshot.png`
/// (a Debug-only sandbox exception, `Galley-Debug.entitlements`).
@MainActor
final class DebugAutomation {
    static let prefix = "com.aliemir.galley.debug."
    static let commands = [
        "snapshot", "probe", "reload", "reset", "next", "previous", "fold", "unfold", "change", "find.close", "resize.small", "resize.large",
        "scroll.top", "scroll.bottom", "dark", "light", "system",
    ] + (1...4).map { "level.\($0)" }
        + Theme.all.map { "theme.\($0.id)" }
        + (0..<30).map { "open.\($0)" }
        + stride(from: 200, through: 6000, by: 200).map { "scroll.\($0)" }
        + ReadingFont.allCases.map { "font.\($0.rawValue)" }

    private let model: AppModel
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel) {
        self.model = model
        let center = DistributedNotificationCenter.default()
        for command in Self.commands {
            observers.append(center.addObserver(forName: .init(Self.prefix + command), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.run(command) }
            })
        }
    }

    private func run(_ command: String) {
        let parts = command.split(separator: ".", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "snapshot": Task { await snapshot() }
        case "probe":
            let web = model.reader.webView
            debugLog("[probe] url=\(web.url?.absoluteString ?? "nil") loading=\(web.isLoading) progress=\(web.estimatedProgress) window=\(web.window != nil) frame=\(web.frame)")
            web.evaluateJavaScript("document.readyState + ' ' + typeof window.Reader + ' ' + document.body.innerHTML.length") { result, error in
                debugLog("[probe] js=\(String(describing: result)) error=\(String(describing: error))")
            }
        case "reset":
            for workspace in model.workspaces { model.removeWorkspace(workspace.id) }
        case "reload": model.reader.webView.load(URLRequest(url: URL(string: "galley://app/reader.html")!))
        case "next": model.goToNext()
        case "previous": model.goToPrevious()
        case "fold": model.foldAll(true)
        case "unfold": model.foldAll(false)
        case "change": model.jumpToChange(1)
        case "level": if let level = PanelLevel(rawValue: Int(argument) ?? 0) { model.setLevel(level) }
        case "theme":
            let theme = Theme.named(argument, fallback: .paper)
            if theme.isDark { model.settings.darkTheme = theme.id; model.settings.appearance = .dark } else {
                model.settings.lightTheme = theme.id; model.settings.appearance = .light
            }
        case "dark": model.settings.appearance = .dark
        case "light": model.settings.appearance = .light
        case "system": model.settings.appearance = .system
        case "font": if let font = ReadingFont(rawValue: argument) { model.settings.font = font }
        case "open":
            if let workspace = model.selectedWorkspace, let index = Int(argument), index < workspace.files.count {
                model.open(workspace.files[index])
            }
        case "scroll":
            let script = switch argument {
            case "top": "window.scrollTo(0, 0)"
            case "bottom": "window.scrollTo(0, document.documentElement.scrollHeight)"
            default: "window.scrollTo(0, \(Int(argument) ?? 0))"
            }
            model.reader.webView.evaluateJavaScript(script)
        case "resize":
            guard let window = mainWindow else { return }
            let size = argument == "small" ? NSSize(width: 900, height: 640) : NSSize(width: 1440, height: 900)
            window.setFrame(NSRect(origin: window.frame.origin, size: size), display: true, animate: false)
        case "find": model.hideFind()
        default: break
        }
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) }
    }

    /// The whole window as it looks: AppKit draws the chrome, and the web
    /// view (which `cacheDisplay` cannot see into) is snapshotted and laid
    /// over its frame.
    private func snapshot() async {
        guard let window = mainWindow, let frameView = window.contentView?.superview else { return }
        let bounds = frameView.bounds
        let scale = window.backingScaleFactor
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = bounds.size

        let webView = model.reader.webView
        let page = webView.window === window && model.current != nil
            ? try? await webView.takeSnapshot(configuration: nil)
            : nil

        // Put the page's pixels into the view tree, under SwiftUI's overlays,
        // so one `cacheDisplay` captures everything in the right order.
        var stand: NSImageView?
        if let page, let container = webView.superview {
            let imageView = NSImageView(frame: webView.frame)
            imageView.image = page
            imageView.imageScaling = .scaleAxesIndependently
            container.addSubview(imageView, positioned: .above, relativeTo: webView)
            stand = imageView
        }
        frameView.layoutSubtreeIfNeeded()
        if let composed = frameView.bitmapImageRepForCachingDisplay(in: bounds) {
            frameView.cacheDisplay(in: bounds, to: composed)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            composed.draw(in: bounds)
            NSGraphicsContext.restoreGraphicsState()
        }
        stand?.removeFromSuperview()

        let directory = URL(fileURLWithPath: "/private/tmp/galley-debug", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("snapshot.png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        debugLog("[debug] snapshot → \(url.path)")
    }
}
#endif

/// Debug logging to stderr, which is unbuffered even when not a terminal.
nonisolated func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    FileHandle.standardError.write(Data((message() + "\n").utf8))
    #endif
}
