import Foundation

/// Bare URLs in text become links, as GitHub's autolink extension makes
/// them (swift-markdown leaves that extension off): `https://…`, `http://…`
/// and `www.…`, starting a word or after `*`, `_`, `~`, `(` or a quote
/// (which GitHub does not, though quoted URLs are common in prose). Trailing
/// punctuation stays outside the link, as does a `)` without its `(`, so
/// "(see https://x.com/a)." links just the URL. Email addresses are left as
/// text. Runs on parsed text, so code, raw HTML and link text are never
/// touched.
nonisolated enum Autolink {
    struct Run: Equatable {
        var text: String
        /// Where the run links to; nil for plain text.
        var href: String?
    }

    /// `text` cut into runs of plain text and URLs, in order.
    static func runs(in text: String) -> [Run] {
        guard text.contains("://") || text.localizedCaseInsensitiveContains("www.") else { return [Run(text: text)] }
        let ns = text as NSString
        var runs: [Run] = []
        var cursor = 0
        for match in candidate.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let url = trimmed(ns.substring(with: match.range))
            guard isValid(url) else { continue }
            if match.range.location > cursor {
                runs.append(Run(text: ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            let isWWW = url.lowercased().hasPrefix("www.")
            runs.append(Run(text: url, href: isWWW ? "http://" + url : url))
            cursor = match.range.location + (url as NSString).length
        }
        if cursor < ns.length { runs.append(Run(text: ns.substring(from: cursor))) }
        return runs.isEmpty ? [Run(text: text)] : runs
    }

    private static let candidate = try! NSRegularExpression(
        pattern: #"(?<![^\s*_~("'“‘])(?:https?://|www\.)[^\s<]+"#, options: .caseInsensitive)

    /// GitHub's end of a link: no trailing `?!.,:*_~'"` or curly quote, no
    /// `)` beyond the ones it opened, no entity-like `&name;`.
    private static func trimmed(_ url: String) -> String {
        var url = Substring(url)
        while let last = url.last {
            if "?!.,:*_~'\"”’".contains(last) {
                url.removeLast()
            } else if last == ")", url.filter({ $0 == ")" }).count > url.filter({ $0 == "(" }).count {
                url.removeLast()
            } else if last == ";", let range = url.range(of: #"&[A-Za-z0-9]+;$"#, options: .regularExpression) {
                url.removeSubrange(range)
            } else {
                break
            }
        }
        return String(url)
    }

    /// A host after the scheme (or `www.` and more): letters, digits, `-`
    /// and `_` in dot-separated parts. `http://localhost:3000` counts; a
    /// lone `www.` or `https://` does not.
    private static func isValid(_ url: String) -> Bool {
        let lowered = url.lowercased()
        let rest: Substring
        if lowered.hasPrefix("www.") {
            rest = url.dropFirst(4)
        } else if let range = url.range(of: "://") {
            rest = url[range.upperBound...]
        } else {
            return false
        }
        let host = rest.prefix { !"/?#:".contains($0) }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, !parts.contains(where: \.isEmpty) else { return false }
        return parts.allSatisfy { part in part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }
    }
}
