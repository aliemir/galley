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
        "snapshot", "probe", "reload", "reset", "palette", "palette.close", "highlight", "next", "previous", "fold", "unfold", "change", "find.close", "resize.small", "resize.large",
        "scroll.top", "scroll.bottom", "dark", "light", "system",
        "appearance", "appearance.close", "settings", "settings.close", "settings.reading", "settings.appearance",
        "js", "note", "feedback.copy", "feedback.copyall", "pin", "movepin", "movews", "divider.narrow", "divider.wide", "toggle.outline", "toggle.files", "toggle.workspaces", "focusfiles", "type.api", "type.rate", "type.s", "type.sta", "key.return", "key.escape", "key.down", "columns.reset", "columns.filesfirst", "columns.nocontents", "rail", "rail.off", "identity", "identity.close", "icon.test", "icon.reset", "swipe.right", "swipe.left", "swipe.hold", "swipe.release", "swipe.wobble", "pull.hold", "pull.half", "pull.back", "pull.backhalf", "pull.release",
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
            debugLog("[probe] anchor=\(String(describing: model.current?.anchor)) file=\(model.current?.file.id ?? "-")")
            web.evaluateJavaScript("document.readyState + ' ' + typeof window.Reader + ' ' + document.body.innerHTML.length") { result, error in
                debugLog("[probe] js=\(String(describing: result)) error=\(String(describing: error))")
            }
        case "note":
            // Selects a phrase in the second paragraph and opens a note on it.
            model.reader.webView.evaluateJavaScript(Self.selectPhrase) { _, _ in
                MainActor.assumeIsolated { self.model.noteSelection() }
            }
        case "feedback":
            if argument == "copyall" { model.copyWorkspaceFeedback() } else { model.copyFeedback() }
        case "highlight":
            // Selects a phrase in the second paragraph, then highlights it.
            let select = Self.selectPhrase
            model.reader.webView.evaluateJavaScript(select) { _, _ in
                MainActor.assumeIsolated { self.model.highlightSelection() }
            }
        case "palette": model.isQuickOpenVisible = argument != "close"
        case "appearance": model.isAppearanceVisible = argument != "close"
        case "settings":
            if argument == "reading" || argument == "appearance" {
                UserDefaults.standard.set(argument, forKey: "settingsTab")
            }
            if argument == "close" {
                NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }?.close()
            } else if let menu = NSApp.mainMenu?.items.first?.submenu,
                      let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," }) {
                // The SwiftUI Settings scene opens only through its menu item.
                menu.performActionForItem(at: index)
            }
        case "reset":
            for workspace in model.workspaces { model.removeWorkspace(workspace.id) }
        case "reload": model.reader.webView.load(URLRequest(url: URL(string: "galley://app/reader.html")!))
        case "next": model.goToNext()
        case "previous": model.goToPrevious()
        case "fold": model.foldAll(true)
        case "unfold": model.foldAll(false)
        case "change": model.jumpToChange(1)
        case "level": if let level = Int(argument) { model.setVisibleColumns(Set(model.columns.prefix(max(0, level - 1)))) }
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
        case "rail": model.settings.workspacesAsIcons = argument != "off"
        case "identity": model.customizingWorkspace = argument == "close" ? nil : model.selectedWorkspaceID
        case "icon":
            guard let id = model.selectedWorkspaceID else { return }
            if argument == "test" {
                model.setWorkspaceIcon(.emoji("📐"), for: id)
                model.setWorkspaceColor("purple", for: id)
                model.setWorkspaceName("Design notes", for: id)
            } else {
                model.setWorkspaceIcon(.monogram, for: id)
                model.setWorkspaceName(nil, for: id)
                model.setWorkspaceColor(nil, for: id)
            }
        case "divider":
            // The steps a drag of the Workspaces edge makes, 150 pt either way.
            let start = model.columnWidth(.workspaces)
            let dx: CGFloat = argument == "narrow" ? -260 : 150
            Task {
                for step in 1...20 {
                    try? await Task.sleep(for: .milliseconds(12))
                    model.dragColumnEdge(.workspaces, to: start + dx * CGFloat(step) / 20)
                }
            }
        case "pin": model.togglePinCurrent()
        case "movepin":
            // The last pinned file to the top, as a drag onto the first would.
            if let workspace = model.selectedWorkspace, let last = workspace.record?.pinned.last, let first = workspace.record?.pinned.first {
                model.movePin(last, to: first, in: workspace)
            }
        case "movews":
            // The last workspace to the top, as a drag onto the first would.
            if let last = model.workspaces.last, let first = model.workspaces.first { model.moveWorkspace(last.id, to: first.id) }
        case "toggle": if let column = PanelColumn(rawValue: argument) { model.toggleColumn(column) }
        case "focusfiles": model.filesFocusRequest += 1
        case "type": for character in argument { postKey(String(character), keyCode: 0) }
        case "key":
            switch argument {
            case "return": postKey("\r", keyCode: 36)
            case "escape": postKey("\u{1b}", keyCode: 53)
            default: postKey(String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: 125)
            }
        case "columns":
            switch argument {
            case "filesfirst": model.settings.columnOrder = [.files, .outline, .workspaces]
            case "nocontents": model.setSwipeSkips(.outline, true)
            default:
                model.settings.columnOrder = PanelColumn.defaultOrder
                model.settings.swipeSkips = []
            }
        case "js":
            // Runs /private/tmp/galley-debug/eval.js in the page and logs the result.
            let path = "/private/tmp/galley-debug/eval.js"
            guard let script = try? String(contentsOfFile: path, encoding: .utf8) else { debugLog("[js] no \(path)"); return }
            model.reader.webView.evaluateJavaScript(script) { result, error in
                debugLog("[js] \(result.map { "\($0)" } ?? "nil") \(error.map { "error: \($0)" } ?? "")")
            }
        case "swipe":
            // Trackpad fingers: positive x is rightward, which reveals.
            switch argument {
            case "right": Task { await gesture(dx: 120, dy: 0, release: true) }
            case "left": Task { await gesture(dx: -120, dy: 0, release: true) }
            case "hold": Task { await gesture(dx: 100, dy: 0, release: false) }
            // A real hand: rightward, drifting down, with a vertical first sample.
            case "wobble": Task { await gesture(dx: 120, dy: 18, release: true, wobble: true) }
            default: postScroll(phase: .ended, dx: 0, dy: 0)
            }
        case "pull":
            // Classic scrolling: fingers moving down scroll toward the end.
            switch argument {
            case "hold": Task { await gesture(dx: 0, dy: 170, release: false) }
            case "back": Task { await gesture(dx: 0, dy: -170, release: false) }
            case "half": Task { await gesture(dx: 0, dy: 80, release: false) }
            case "backhalf": Task { await gesture(dx: 0, dy: -80, release: false) }
            default: postScroll(phase: .ended, dx: 0, dy: 0)
            }
        default: break
        }
    }

    /// A two-finger trackpad gesture as AppKit would deliver it: phased,
    /// precise scroll events over the page. `dx`/`dy` are finger travel
    /// (right and down positive). Built events report classic scrolling
    /// (`isDirectionInvertedFromDevice` false), where the scroll delta runs
    /// against the fingers, so the deltas are negated.
    private func gesture(dx: Double, dy: Double, release: Bool, wobble: Bool = false) async {
        let steps = 12
        postScroll(phase: .began, dx: 0, dy: wobble ? -3 : 0)
        for step in 0..<steps {
            try? await Task.sleep(for: .milliseconds(12))
            let jitter = wobble ? (step == 0 ? 4.0 : step.isMultiple(of: 2) ? 2 : -2) : 0
            postScroll(phase: .changed, dx: -dx / Double(steps), dy: -dy / Double(steps) - jitter)
        }
        if release {
            try? await Task.sleep(for: .milliseconds(12))
            postScroll(phase: .ended, dx: 0, dy: 0)
        }
    }

    private enum ScrollPhase: Int64 { case began = 1, changed = 2, ended = 4 }

    private func postScroll(phase: ScrollPhase, dx: Double, dy: Double) {
        guard let window = mainWindow, let screen = window.screen else { return }
        let webView = model.reader.webView
        let local = webView.convert(NSPoint(x: webView.bounds.midX, y: webView.bounds.midY), to: nil)
        let global = window.convertPoint(toScreen: local)
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else { return }
        event.location = CGPoint(x: global.x, y: screen.frame.maxY - global.y)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase.rawValue)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dx)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.windowNumber))
        guard let ns = NSEvent(cgEvent: event) else { return }
        debugLog("[swipe] phase=\(ns.phase.rawValue) dx=\(ns.scrollingDeltaX) dy=\(ns.scrollingDeltaY) inverted=\(ns.isDirectionInvertedFromDevice)")
        GestureMonitor.current?.inject(ns)
    }

    /// A key press as the keyboard would send it to the main window.
    private func postKey(_ characters: String, keyCode: UInt16) {
        guard let window = mainWindow else { return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            ) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
    }

    /// Selects a phrase in the second paragraph, for the highlight and note commands.
    static let selectPhrase = """
            (() => {
            const walker = document.createTreeWalker(document.getElementById('content'), NodeFilter.SHOW_TEXT);
            let node = walker.nextNode();
            while (node && (node.length < 60 || !node.parentElement.closest('p'))) node = walker.nextNode();
            const range = document.createRange();
            range.setStart(node, 4); range.setEnd(node, Math.min(node.length, 60));
            const s = window.getSelection(); s.removeAllRanges(); s.addRange(range);
            })();
            """

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
