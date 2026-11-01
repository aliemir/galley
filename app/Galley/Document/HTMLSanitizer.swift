import Foundation

/// Raw HTML in a Markdown file, made safe to show. Agents write a little of
/// it — `<details>`, `<kbd>`, `<br>`, an `<img>` with a width — and that is
/// kept; anything that could run, load, restyle the page or pass for
/// Galley's own marks (a `class="chg-added"`, a `style="display:none"`) is
/// not. The page's content security policy already stops scripts; this
/// stops a file from changing what the reader sees.
///
/// Comments are kept as hidden elements: an agent reads them, so the reader
/// can ask to see them too (View → Show Hidden Comments).
nonisolated enum HTMLSanitizer {
    /// Tags kept, as GitHub keeps them, with only the attributes below.
    static let allowedTags: Set<String> = [
        "a", "abbr", "b", "bdi", "bdo", "blockquote", "br", "caption", "center", "cite", "code", "col", "colgroup",
        "dd", "del", "details", "dfn", "div", "dl", "dt", "em", "figcaption", "figure", "h1", "h2", "h3", "h4",
        "h5", "h6", "hr", "i", "img", "ins", "kbd", "li", "mark", "ol", "p", "picture", "pre", "q", "rp", "rt",
        "ruby", "s", "samp", "small", "source", "span", "strike", "strong", "sub", "summary", "sup", "table",
        "tbody", "td", "tfoot", "th", "thead", "time", "tr", "tt", "u", "ul", "var", "wbr",
    ]

    /// Tags dropped together with everything inside them.
    static let droppedWithContent: Set<String> = [
        "script", "style", "iframe", "frame", "frameset", "object", "embed", "applet", "form", "input",
        "button", "select", "textarea", "option", "link", "meta", "base", "template", "noscript", "title",
        "head", "svg", "math", "canvas", "audio", "video", "dialog",
    ]

    static let allowedAttributes: Set<String> = [
        "href", "src", "srcset", "alt", "title", "width", "height", "align", "valign", "colspan", "rowspan",
        "open", "start", "reversed", "type", "cite", "datetime", "lang", "dir", "media", "abbr", "scope",
    ]

    /// The cleaned HTML, and how many comments it holds.
    static func clean(_ raw: String, inline: Bool) -> (html: String, comments: Int) {
        var output = ""
        var comments = 0
        var dropping: String?
        var rest = Substring(raw)
        while !rest.isEmpty {
            guard let open = rest.firstIndex(of: "<") else {
                if dropping == nil { output += rest }
                break
            }
            if dropping == nil { output += rest[..<open] }
            rest = rest[open...]

            if rest.hasPrefix("<!--") {
                let end = rest.range(of: "-->")
                let body = rest[rest.index(rest.startIndex, offsetBy: 4)..<(end?.lowerBound ?? rest.endIndex)]
                rest = end.map { rest[$0.upperBound...] } ?? ""
                guard dropping == nil else { continue }
                let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                comments += 1
                let tag = inline ? "span" : "div"
                output += "<\(tag) class=\"html-comment\" title=\"Hidden in the file\">\(HTML.escape(text))</\(tag)>"
                continue
            }

            guard let tag = Tag(rest) else {
                // A "<" that starts no tag ("a < b") is text.
                if dropping == nil { output += "&lt;" }
                rest = rest.dropFirst()
                continue
            }
            rest = rest[tag.end...]

            if let dropped = dropping {
                if tag.isClosing, tag.name == dropped { dropping = nil }
                continue
            }
            if droppedWithContent.contains(tag.name) {
                if !tag.isClosing, !tag.isSelfClosing, !Tag.void.contains(tag.name) { dropping = tag.name }
                continue
            }
            // Unknown tags go; what they hold stays.
            guard allowedTags.contains(tag.name) else { continue }
            output += tag.isClosing ? "</\(tag.name)>" : "<\(tag.name)\(attributes(tag))\(tag.isSelfClosing ? " /" : "")>"
        }
        return (output, comments)
    }

    private static func attributes(_ tag: Tag) -> String {
        var kept = ""
        for (name, value) in tag.attributes where allowedAttributes.contains(name) {
            guard let value else {
                kept += " \(name)"
                continue
            }
            if name == "href" || name == "src" || name == "cite", !isSafeURL(value, image: name == "src") { continue }
            if name == "srcset", value.split(separator: ",").contains(where: { !isSafeURL(String($0.split(separator: " ").first ?? ""), image: true) }) {
                continue
            }
            kept += " \(name)=\"\(HTML.attribute(value))\""
        }
        return kept
    }

    /// Web, mail and in-page links, and paths relative to the file; images
    /// may also be inline data. Never `javascript:` or another app's scheme.
    static func isSafeURL(_ value: String, image: Bool) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .filter { !$0.isWhitespace && $0 != "\u{0}" }
        guard let colon = trimmed.firstIndex(of: ":") else { return true }
        // A colon after a slash, "?" or "#" belongs to a path, not a scheme.
        if let separator = trimmed.firstIndex(where: { "/?#".contains($0) }), separator < colon { return true }
        let scheme = trimmed[..<colon]
        if ["http", "https", "mailto"].contains(scheme) { return true }
        return image && trimmed.hasPrefix("data:image/") && !trimmed.hasPrefix("data:image/svg")
    }

    /// One tag: its name, whether it closes or closes itself, its attributes.
    private struct Tag {
        static let void: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"]

        let name: String
        let isClosing: Bool
        let isSelfClosing: Bool
        let attributes: [(String, String?)]
        let end: Substring.Index

        private static let pattern = try! NSRegularExpression(
            pattern: #"^<(/?)([A-Za-z][A-Za-z0-9-]*)((?:\s+[^\s"'>/=]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*)\s*(/?)>"#
        )
        private static let attribute = try! NSRegularExpression(
            pattern: #"([^\s"'>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?"#
        )

        init?(_ text: Substring) {
            // A tag is short: look no further than this into the rest.
            let string = String(text.prefix(4096))
            let range = NSRange(string.startIndex..., in: string)
            guard let match = Self.pattern.firstMatch(in: string, range: range),
                  let nameRange = Range(match.range(at: 2), in: string),
                  let whole = Range(match.range, in: string) else { return nil }
            name = string[nameRange].lowercased()
            isClosing = Range(match.range(at: 1), in: string).map { !string[$0].isEmpty } ?? false
            isSelfClosing = Range(match.range(at: 4), in: string).map { !string[$0].isEmpty } ?? false
            end = text.index(text.startIndex, offsetBy: string.distance(from: string.startIndex, to: whole.upperBound))
            var found: [(String, String?)] = []
            if let attributesRange = Range(match.range(at: 3), in: string) {
                let source = String(string[attributesRange])
                for item in Self.attribute.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                    guard let key = Range(item.range(at: 1), in: source) else { continue }
                    let value = (2...4).lazy.compactMap { Range(item.range(at: $0), in: source) }.first.map { String(source[$0]) }
                    found.append((source[key].lowercased(), value.map(Self.decodeEntities)))
                }
            }
            attributes = found
        }

        /// Attribute values arrive as HTML: `&amp;` is "&" before it is checked
        /// and escaped again. Numeric entities too, so `&#106;avascript:`
        /// cannot slip past the scheme check.
        static func decodeEntities(_ value: String) -> String {
            var result = value
            for (entity, character) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">")] {
                result = result.replacingOccurrences(of: entity, with: character)
            }
            let numeric = try! NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);?"#)
            for match in numeric.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let whole = Range(match.range, in: result), let digits = Range(match.range(at: 2), in: result) else { continue }
                let isHex = Range(match.range(at: 1), in: result).map { !result[$0].isEmpty } ?? false
                guard let code = UInt32(result[digits], radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) else { continue }
                result.replaceSubrange(whole, with: String(Character(scalar)))
            }
            return result.replacingOccurrences(of: "&amp;", with: "&")
        }
    }
}
