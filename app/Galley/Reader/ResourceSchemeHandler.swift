import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves `galley://app/<name>` from the app bundle and
/// `galley://file/<absolute path>` from inside the open workspaces. Nothing
/// else reaches the page: it has no network access at all.
final class ResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    /// Decides whether a file may be served; only files inside a workspace are.
    var allowsFile: (URL) -> Bool = { _ in false }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        debugLog("[scheme] \(task.request.url?.absoluteString ?? "nil")")
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        switch url.host {
        case "app":
            guard let file = Self.bundleResource(named: url.lastPathComponent),
                  let data = try? Data(contentsOf: file) else {
                task.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            respond(task, url: url, data: data)

        case "file":
            let file = URL(fileURLWithPath: url.path).standardizedFileURL
            guard allowsFile(file), let data = try? Data(contentsOf: file, options: .mappedIfSafe) else {
                task.didFailWithError(URLError(.noPermissionsToReadFile))
                return
            }
            respond(task, url: url, data: data)

        default:
            task.didFailWithError(URLError(.unsupportedURL))
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func respond(_ task: any WKURLSchemeTask, url: URL, data: Data) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.mimeType(for: url.pathExtension),
                "Content-Length": String(data.count),
                "Cache-Control": "no-cache",
                // Lets the page see real error messages from its own scripts
                // (a custom scheme is an opaque origin to WebKit).
                "Access-Control-Allow-Origin": "*",
            ]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    /// Bundle resources are looked up by name alone, wherever the build put
    /// them (synchronized groups may flatten or keep the `Web/vendor` folders).
    static func bundleResource(named name: String) -> URL? {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        for subdirectory in [nil, "Web", "vendor", "fonts", "Reader/Web", "Reader/Web/vendor", "Reader/Web/vendor/fonts"] {
            if let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: subdirectory) { return url }
        }
        return nil
    }

    static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "json": return "application/json"
        case "woff2": return "font/woff2"
        case "svg": return "image/svg+xml"
        default:
            return UTType(filenameExtension: pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}
