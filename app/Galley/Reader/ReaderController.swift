import AppKit
import SwiftUI
import WebKit

// MARK: - Payloads

/// Where the reader is in a document: the diff unit at the top of the
/// viewport and how far into it. Survives theme and font changes, unlike a
/// pixel offset.
nonisolated struct ScrollAnchor: Codable, Hashable, Sendable {
    var unit: Int
    var offset: Double
    var heading: String?

    /// The end of the document — where the previous document opens when the
    /// reader pulls back into it.
    static let end = ScrollAnchor(unit: -2, offset: 0)
}

struct PagePayload: Encodable {
    struct Header: Encodable {
        var meta: [String]
        var badge: String?
        var badgeKind: String?
        /// Shown only when the document has no H1 of its own.
        var title: String?
    }

    struct Change: Encodable {
        var kind: String
        var old: String?
    }

    struct Next: Encodable {
        var title: String
        var label: String
        var why: String?
    }

    var id: String
    var html: String
    /// `galley://file/…/` for the document's folder; raw HTML images resolve against it.
    var base: String?
    var header: Header
    var changes: [String: Change]
    var folded: [String]
    var highlights: [Highlight]
    var scroll: ScrollAnchor?
    var next: Next?
    var previous: Next?
    var endLabel: String?
    var transition: String
}

struct ReaderConfiguration: Encodable, Equatable {
    var vars: [String: String]
    var font: String
    var size: Double
    var leading: Double
    var measure: Double
    var top: Double
    var dark: Bool
    var showChanges: Bool
    var lang: String
}

struct ScrollReport: Equatable {
    var document: String
    var anchor: ScrollAnchor
    var atTop: Bool
    var atBottom: Bool
    var reachedEnd: Bool
    var progress: Double
}

enum ReaderEvent {
    case ready
    case scroll(ScrollReport)
    case link(String)
    case next
    case fold(id: String, folded: Bool)
    case folds([String])
    case copy(String)
    case highlight(text: String, prefix: String, suffix: String, replaces: [String])
    case unhighlight(String)
    case orphans([String])
}

// MARK: - Controller

/// Owns the one web view that draws every page, and the bridge to it.
@MainActor
final class ReaderController: NSObject {
    let webView: ReaderWebView
    let schemeHandler = ResourceSchemeHandler()
    var onEvent: (ReaderEvent) -> Void = { _ in }

    private var isReady = false
    private var queued: [String] = []
    private var lastConfiguration: ReaderConfiguration?
    private var lastPayload: PagePayload?
    private static let pageURL = URL(string: "galley://app/reader.html")!

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: ResourceURL.scheme)
        configuration.suppressesIncrementalRendering = true
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = ReaderWebView(frame: .zero, configuration: configuration)
        super.init()

        configuration.userContentController.add(WeakScriptHandler(self), name: "galley")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.alphaValue = 0
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.load(URLRequest(url: Self.pageURL))
    }

    func configure(_ configuration: ReaderConfiguration) {
        guard configuration != lastConfiguration else { return }
        lastConfiguration = configuration
        webView.underPageBackgroundColor = NSColor(css: configuration.vars["--paper"] ?? "#FFFFFF")
        call("configure", configuration)
    }

    func show(_ payload: PagePayload) {
        lastPayload = payload
        call("show", payload)
        if webView.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                webView.animator().alphaValue = 1
            }
        }
    }

    func update(_ payload: PagePayload) {
        lastPayload = payload
        call("update", payload)
    }

    func scrollToHeading(_ id: String) { run("Reader.scrollToHeading(\(Self.json(id)))") }
    /// Stretches the page `points` past its end (or, `atStart`, its top) and
    /// fills that edge's cue toward `threshold`. 0 springs it back.
    func setPull(_ points: Double, threshold: Double, atStart: Bool) {
        run("Reader.setPull(\(points), \(threshold), \(atStart))")
    }
    /// Hides the page's scrollbar while panels slide.
    func setPanelsMoving(_ moving: Bool) { run("Reader.setPanelsMoving(\(moving))") }
    /// Keeps WebKit's own bounce out of the way while a pull may start.
    func armPull(_ armed: Bool) { run("Reader.armPull(\(armed))") }
    func fold(_ id: String, folded: Bool) { run("Reader.fold(\(Self.json(id)), \(folded))") }
    func foldAll(_ folded: Bool) { run("Reader.foldAll(\(folded))") }
    func scrollPage(_ direction: Int) { run("Reader.scrollPage(\(direction))") }
    func endFind() { run("Reader.endFind()") }
    func setHighlights(_ highlights: [Highlight]) { call("setHighlights", highlights) }
    func scrollToHighlight(_ id: String) { run("Reader.scrollToHighlight(\(Self.json(id)))") }

    /// The current selection as a highlight anchor, if there is one.
    func selectionAnchor() async -> (text: String, prefix: String, suffix: String, replaces: [String])? {
        guard let result = try? await webView.callAsyncJavaScript(
            "return Reader.selectionAnchor()", contentWorld: .page
        ) as? [String: Any], let text = result["text"] as? String else { return nil }
        return (text, (result["prefix"] as? String) ?? "", (result["suffix"] as? String) ?? "", (result["replaces"] as? [String]) ?? [])
    }

    func jumpToChange(_ direction: Int) async -> Bool {
        (try? await webView.callAsyncJavaScript(
            "return Reader.jumpToChange(d)", arguments: ["d": direction], contentWorld: .page
        ) as? Bool) ?? false
    }

    /// Highlights every match and moves to the next (`direction` 1) or
    /// previous (-1) one; 0 re-runs the search in place.
    func find(_ query: String, direction: Int) async -> (count: Int, index: Int) {
        guard isReady else { return (0, -1) }
        let result = try? await webView.callAsyncJavaScript(
            "return Reader.find(q, d)", arguments: ["q": query, "d": direction], contentWorld: .page
        ) as? [String: Any]
        return ((result?["count"] as? Int) ?? 0, (result?["index"] as? Int) ?? -1)
    }

    func selectionText() async -> String {
        (try? await webView.callAsyncJavaScript("return Reader.selectionText()", contentWorld: .page) as? String) ?? ""
    }

    // MARK: Plumbing

    private func call(_ function: String, _ argument: some Encodable) {
        guard let data = try? JSONEncoder().encode(argument), let json = String(data: data, encoding: .utf8) else { return }
        run("Reader.\(function)(\(json))")
    }

    private func run(_ script: String) {
        guard isReady else {
            queued.append(script)
            return
        }
        webView.evaluateJavaScript(script) { _, error in
            #if DEBUG
            if let error { debugLog("[reader] \(error.localizedDescription) in \(script.prefix(80))") }
            #endif
        }
    }

    private static func json(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string) else { return "\"\"" }
        return String(decoding: data, as: UTF8.self)
    }

    fileprivate func receive(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "ready":
            #if DEBUG
            debugLog("[reader] ready, \(queued.count) queued")
            #endif
            isReady = true
            let pending = queued
            queued = []
            pending.forEach(run)
            onEvent(.ready)
        case "scroll":
            let anchor = ScrollAnchor(
                unit: (message["unit"] as? Int) ?? -1,
                offset: (message["offset"] as? Double) ?? 0,
                heading: message["heading"] as? String
            )
            onEvent(.scroll(ScrollReport(
                document: (message["doc"] as? String) ?? "",
                anchor: anchor,
                atTop: (message["atTop"] as? Bool) ?? false,
                atBottom: (message["atBottom"] as? Bool) ?? false,
                reachedEnd: (message["reachedEnd"] as? Bool) ?? false,
                progress: (message["progress"] as? Double) ?? 0
            )))
        case "link":
            if let href = message["href"] as? String { onEvent(.link(href)) }
        case "next":
            onEvent(.next)
        case "fold":
            if let id = message["id"] as? String { onEvent(.fold(id: id, folded: (message["folded"] as? Bool) ?? false)) }
        case "folds":
            onEvent(.folds((message["ids"] as? [String]) ?? []))
        case "copy":
            if let text = message["text"] as? String { onEvent(.copy(text)) }
        case "highlight":
            if let text = message["text"] as? String {
                onEvent(.highlight(
                    text: text,
                    prefix: (message["prefix"] as? String) ?? "",
                    suffix: (message["suffix"] as? String) ?? "",
                    replaces: (message["replaces"] as? [String]) ?? []
                ))
            }
        case "unhighlight":
            if let id = message["id"] as? String { onEvent(.unhighlight(id)) }
        case "orphans":
            onEvent(.orphans((message["ids"] as? [String]) ?? []))
        case "log":
            #if DEBUG
            debugLog("[page] \(message["message"] ?? "")")
            #endif
        default:
            break
        }
    }
}

extension ReaderController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        debugLog("[reader] policy for \(navigationAction.request.url?.absoluteString ?? "nil")")
        if navigationAction.request.url == Self.pageURL { return .allow }
        // Links are handled by the page script; anything that slips through
        // (a drop, a stray form) must not replace the reader.
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            onEvent(.link(url.absoluteString))
        }
        return .cancel
    }

    #if DEBUG
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        debugLog("[reader] page loaded")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        debugLog("[reader] page failed to load: \(error)")
    }
    #endif

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Recover from a crashed content process with the same page.
        isReady = false
        queued = []
        if let lastConfiguration { call("configure", lastConfiguration) }
        if var lastPayload {
            lastPayload.transition = "none"
            call("show", lastPayload)
        }
        webView.load(URLRequest(url: Self.pageURL))
    }
}

/// `WKUserContentController` retains its handlers; this breaks the cycle.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var controller: ReaderController?

    init(_ controller: ReaderController) {
        self.controller = controller
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        controller?.receive(message.body)
    }
}

// MARK: - Web view

/// The reader's web view: no navigation menu items, no drops (the window
/// takes folder drops), and a context menu with only what a reader needs.
final class ReaderWebView: WKWebView {
    /// Extra items for the context menu, e.g. "Copy Link to Section".
    var extraMenuItems: () -> [NSMenuItem] = { [] }

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        unregisterDraggedTypes()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        let unwanted = [
            "Reload", "GoBack", "GoForward", "OpenLink", "OpenImage", "DownloadImage", "DownloadLinkedFile",
            "OpenFrame", "OpenMedia", "DownloadMedia", "CopyImageURL", "OpenLinkInNewWindow",
        ]
        for item in menu.items {
            let id = item.identifier?.rawValue ?? ""
            if unwanted.contains(where: { id.contains($0) }) { menu.removeItem(item) }
        }
        let extras = extraMenuItems()
        if !extras.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            extras.forEach(menu.addItem)
        }
        while menu.items.first?.isSeparatorItem == true { menu.removeItem(at: 0) }
        while menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        super.willOpenMenu(menu, with: event)
    }
}

extension NSColor {
    convenience init(css: String) {
        self.init(Color(css: css))
    }
}
