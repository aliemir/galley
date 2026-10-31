import Foundation
import Markdown

/// A heading in the document's outline.
nonisolated struct OutlineItem: Identifiable, Hashable, Codable {
    /// The heading's anchor id in the rendered page.
    let id: String
    let level: Int
    let title: String
    /// Index of the heading's diff unit, so changed sections can be found.
    let unit: Int
}

/// The smallest piece of a document that change tracking compares: a
/// paragraph, heading, code block, table row, list item's paragraph.
nonisolated struct DiffUnit: Hashable {
    /// Normalised markdown source. Two units with the same key are the same.
    let key: String
    /// The unit's rendered inner HTML, used for word-level diffs.
    let html: String
}

nonisolated struct RenderedDocument {
    var html: String
    /// Plain text of the first level-1 heading, if the document has one.
    var title: String?
    var outline: [OutlineItem]
    var units: [DiffUnit]
    var wordCount: Int

    var readingMinutes: Int { max(1, Int((Double(wordCount) / 230).rounded())) }
}

/// Turns markdown into the HTML fragment the reader page displays.
///
/// Every diff unit carries `data-b="<index>"`, headings carry GitHub-style
/// anchor ids, and image paths are rewritten to the `galley://` scheme so the
/// web view can load files from the workspace.
nonisolated struct MarkdownRenderer {
    /// Directory relative paths in the document resolve against.
    var baseURL: URL?

    func render(_ source: String) -> RenderedDocument {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let (frontMatter, body) = FrontMatter.split(normalized)
        var preprocessor = Preprocessor()
        let processed = preprocessor.process(body)
        let document = Document(parsing: processed)
        let builder = HTMLBuilder(baseURL: baseURL, preprocessor: preprocessor)
        var html = ""
        if let frontMatter { html += builder.frontMatter(frontMatter) }
        html += builder.sections(document.children)
        html += builder.footnoteSection()
        return RenderedDocument(
            html: html,
            title: builder.firstTitle,
            outline: builder.outline,
            units: builder.units,
            wordCount: builder.wordCount
        )
    }
}

// MARK: - Front matter

nonisolated enum FrontMatter {
    /// Splits a leading `---` YAML block from the body. The block is returned
    /// without its fences.
    static func split(_ source: String) -> (frontMatter: String?, body: String) {
        guard source.hasPrefix("---\n") || source.hasPrefix("---\r\n") else { return (nil, source) }
        let lines = source.components(separatedBy: "\n")
        for index in 1..<lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces.union(.newlines))
            if line == "---" || line == "..." {
                let front = lines[1..<index].joined(separator: "\n")
                let body = lines[(index + 1)...].joined(separator: "\n")
                return (front, body)
            }
        }
        return (nil, source)
    }

    /// `key: value` pairs, with indented continuation lines folded into the
    /// previous value. Nil when the block is not simple enough to show as a list.
    static func pairs(_ text: String) -> [(String, String)]? {
        var result: [(String, String)] = []
        for line in text.components(separatedBy: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            if let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t"), !line.hasPrefix("-") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                    value = String(value.dropFirst().dropLast())
                }
                guard !key.isEmpty, !key.contains(" ") || key.count < 30 else { return nil }
                result.append((key, value))
            } else if !result.isEmpty {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let joined = result[result.count - 1].1.isEmpty ? trimmed : result[result.count - 1].1 + " " + trimmed
                result[result.count - 1].1 = joined
            } else {
                return nil
            }
        }
        return result.isEmpty ? nil : result
    }
}

// MARK: - HTML

nonisolated private final class HTMLBuilder {
    let baseURL: URL?
    let preprocessor: Preprocessor
    var units: [DiffUnit] = []
    var outline: [OutlineItem] = []
    var firstTitle: String?
    var wordCount = 0
    private var slugs: [String: Int] = [:]

    init(baseURL: URL?, preprocessor: Preprocessor) {
        self.baseURL = baseURL
        self.preprocessor = preprocessor
    }

    func blocks(_ children: MarkupChildren) -> String {
        children.map { block($0) }.joined(separator: "\n")
    }

    /// Top-level blocks, with each heading opening a `<section>` that runs
    /// until the next heading of the same or a higher level, so sections can
    /// fold in the page.
    func sections(_ children: MarkupChildren) -> String {
        var html = ""
        var open: [Int] = []
        for child in children {
            if let heading = child as? Heading {
                while let last = open.last, last >= heading.level {
                    html += "</div></section>\n"
                    open.removeLast()
                }
                let rendered = block(heading)
                let id = outline.last?.id ?? ""
                html += "<section class=\"sec\" data-level=\"\(heading.level)\" data-sec=\"\(HTML.attribute(id))\">\(rendered)<div class=\"sec-body\">\n"
                open.append(heading.level)
            } else {
                html += block(child) + "\n"
            }
        }
        html += String(repeating: "</div></section>\n", count: open.count)
        return html
    }

    /// Registers a diff unit and returns its index.
    private func unit(key: String, html: String) -> Int {
        units.append(DiffUnit(key: preprocessor.restore(key), html: html))
        return units.count - 1
    }

    func frontMatter(_ text: String) -> String {
        let index = unit(key: "---\n" + text, html: HTML.escape(text))
        guard let pairs = FrontMatter.pairs(text) else {
            return "<pre class=\"front-matter raw\" data-b=\"\(index)\"><code>\(HTML.escape(text))</code></pre>"
        }
        let rows = pairs.map { "<dt>\(HTML.escape($0.0))</dt><dd>\(HTML.escape($0.1))</dd>" }.joined()
        return "<dl class=\"front-matter\" data-b=\"\(index)\">\(rows)</dl>"
    }

    private func block(_ markup: Markup) -> String {
        switch markup {
        case let heading as Heading:
            let inner = inlines(heading.children)
            let title = preprocessor.restore(heading.plainText).trimmingCharacters(in: .whitespaces)
            let id = slug(for: title)
            let index = unit(key: heading.format(), html: inner)
            if heading.level == 1, firstTitle == nil { firstTitle = title }
            outline.append(OutlineItem(id: id, level: heading.level, title: title, unit: index))
            return "<h\(heading.level) id=\"\(HTML.attribute(id))\" data-b=\"\(index)\">\(inner)</h\(heading.level)>"

        case let paragraph as Paragraph:
            let raw = paragraph.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.range(of: #"^GALLEYMD(\d+)Z$"#, options: .regularExpression) != nil,
               let number = Int(raw.dropFirst(8).dropLast()), number < preprocessor.math.count {
                let tex = HTML.escape(preprocessor.math[number].tex)
                let index = unit(key: paragraph.format(), html: tex)
                return "<div class=\"math display\" data-b=\"\(index)\">\(tex)</div>"
            }
            let inner = inlines(paragraph.children)
            let index = unit(key: paragraph.format(), html: inner)
            return "<p data-b=\"\(index)\">\(inner)</p>"

        case let quote as BlockQuote:
            if let alert = alert(quote) { return alert }
            return "<blockquote>\n\(blocks(quote.children))\n</blockquote>"

        case let list as UnorderedList:
            return "<ul\(listClass(list))>\n\(list.listItems.map(listItem).joined(separator: "\n"))\n</ul>"

        case let list as OrderedList:
            let start = list.startIndex == 1 ? "" : " start=\"\(list.startIndex)\""
            return "<ol\(start)\(listClass(list))>\n\(list.listItems.map(listItem).joined(separator: "\n"))\n</ol>"

        case let code as CodeBlock:
            let language = code.language?.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
            let escaped = HTML.escape(code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code)
            let index = unit(key: code.format(), html: escaped)
            if language == "math" || language == "latex" || language == "tex" || language == "katex" {
                return "<div class=\"math display\" data-b=\"\(index)\">\(escaped)</div>"
            }
            if language == "mermaid" {
                return "<figure class=\"mermaid\" data-b=\"\(index)\"><pre class=\"mermaid-source\">\(escaped)</pre></figure>"
            }
            let languageAttribute = language.isEmpty ? "" : " data-lang=\"\(HTML.attribute(language))\""
            let codeClass = language.isEmpty ? "" : " class=\"language-\(HTML.attribute(language))\""
            return "<pre data-b=\"\(index)\"\(languageAttribute)><code\(codeClass)>\(escaped)</code></pre>"

        case let html as HTMLBlock:
            return html.rawHTML

        case is ThematicBreak:
            return "<hr>"

        case let table as Table:
            return self.table(table)

        default:
            return blocks(markup.children)
        }
    }

    private func listClass(_ list: ListItemContainer) -> String {
        var classes: [String] = []
        if list.listItems.contains(where: { $0.checkbox != nil }) { classes.append("tasks") }
        if isTight(list) { classes.append("tight") }
        return classes.isEmpty ? "" : " class=\"\(classes.joined(separator: " "))\""
    }

    /// A list is tight when no item has blank lines between its blocks, which
    /// cmark reports as items whose paragraphs sit on consecutive lines.
    private func isTight(_ list: ListItemContainer) -> Bool {
        var previousEnd: Int?
        for item in list.listItems {
            if let start = item.range?.lowerBound.line, let end = previousEnd, start > end + 1 { return false }
            previousEnd = item.range?.upperBound.line
            let children = Array(item.children)
            for (a, b) in zip(children, children.dropFirst()) {
                if let aEnd = a.range?.upperBound.line, let bStart = b.range?.lowerBound.line, bStart > aEnd + 1 {
                    return false
                }
            }
        }
        return true
    }

    private func listItem(_ item: ListItem) -> String {
        let body = blocks(item.children)
        switch item.checkbox {
        case .checked:
            return "<li class=\"task done\"><span class=\"check\" aria-hidden=\"true\"></span>\(body)</li>"
        case .unchecked:
            return "<li class=\"task\"><span class=\"check\" aria-hidden=\"true\"></span>\(body)</li>"
        case nil:
            return "<li>\(body)</li>"
        }
    }

    /// GitHub alerts (`> [!NOTE]`) and Obsidian callouts (`> [!tip] Title`,
    /// `> [!faq]- Folded`, `> [!example]+ Open`).
    private func alert(_ quote: BlockQuote) -> String? {
        guard let first = quote.child(at: 0) as? Paragraph else { return nil }
        let firstLine = first.plainText.components(separatedBy: "\n")[0]
        guard let match = firstLine.range(of: #"^\[!([A-Za-z-]+)\]([+-]?)"#, options: .regularExpression) else { return nil }
        let marker = String(firstLine[match])
        let type = marker.dropFirst(2).prefix(while: { $0 != "]" }).lowercased()
        let fold = marker.last == "-" ? "closed" : marker.last == "+" ? "open" : nil
        let family = Callout.family(of: type)

        var inner = inlines(first.children)
        if let range = inner.range(of: marker) { inner.removeSubrange(inner.startIndex..<range.upperBound) }
        // The rest of the first line is a custom title; what follows is body.
        var title = ""
        if let newline = inner.firstIndex(of: "\n") {
            title = String(inner[..<newline])
            inner = String(inner[inner.index(after: newline)...])
        } else {
            title = inner
            inner = ""
        }
        title = title.trimmingCharacters(in: .whitespaces)
        if title.isEmpty { title = HTML.escape(Callout.defaultTitle(of: type)) }
        inner = inner.replacingOccurrences(of: #"^(\s|<br>)+"#, with: "", options: .regularExpression)

        var body = ""
        if !inner.isEmpty {
            let index = unit(key: first.format(), html: inner)
            body += "<p data-b=\"\(index)\">\(inner)</p>\n"
        } else {
            _ = unit(key: first.format(), html: title)
        }
        body += quote.children.dropFirst().map { block($0) }.joined(separator: "\n")

        let classes = "callout \(family)"
        let titleHTML = "<span class=\"callout-icon\" aria-hidden=\"true\"></span><span class=\"callout-label\">\(title)</span>"
        if let fold {
            return "<details class=\"\(classes)\"\(fold == "open" ? " open" : "")><summary class=\"callout-title\">\(titleHTML)</summary><div class=\"callout-body\">\n\(body)\n</div></details>"
        }
        let bodyHTML = body.isEmpty ? "" : "<div class=\"callout-body\">\n\(body)\n</div>"
        return "<aside class=\"\(classes)\"><p class=\"callout-title\">\(titleHTML)</p>\(bodyHTML)</aside>"
    }

    private func table(_ table: Table) -> String {
        let alignments = table.columnAlignments
        func style(_ column: Int) -> String {
            guard column < alignments.count, let alignment = alignments[column] else { return "" }
            switch alignment {
            case .left: return " style=\"text-align:left\""
            case .center: return " style=\"text-align:center\""
            case .right: return " style=\"text-align:right\""
            }
        }
        let head = table.head.cells.enumerated().map { column, cell in
            "<th\(style(column))>\(inlines(cell.children))</th>"
        }.joined()
        // `format()` asserts on table parts outside their table, so key on text.
        let headKey = "| " + table.head.cells.map(\.plainText).joined(separator: " | ") + " |"
        let headIndex = unit(key: headKey, html: head)

        var rows: [String] = []
        for row in table.body.rows {
            let cells = row.cells.enumerated().map { column, cell in
                "<td\(style(column))>\(inlines(cell.children))</td>"
            }.joined()
            let key = row.cells.map(\.plainText).joined(separator: " | ")
            let index = unit(key: "| " + key + " |", html: cells)
            rows.append("<tr data-b=\"\(index)\">\(cells)</tr>")
        }
        return """
        <div class="table"><table>
        <thead><tr data-b="\(headIndex)">\(head)</tr></thead>
        <tbody>\(rows.joined(separator: "\n"))</tbody>
        </table></div>
        """
    }

    func footnoteSection() -> String {
        guard !preprocessor.footnotes.isEmpty else { return "" }
        let items = preprocessor.footnotes.enumerated().map { number, note -> String in
            let rendered = blocks(Document(parsing: note.text).children)
            let index = unit(key: "[^\(note.label)]: \(note.text)", html: rendered)
            let back = "<a class=\"footnote-back\" href=\"#fnref-\(number + 1)\" aria-label=\"Back to text\">↩</a>"
            return "<li id=\"fn-\(number + 1)\" data-b=\"\(index)\">\(rendered)\(back)</li>"
        }
        return "\n<section class=\"footnotes\"><ol>\n\(items.joined(separator: "\n"))\n</ol></section>"
    }

    // MARK: Inline

    private func inlines(_ children: MarkupChildren) -> String {
        children.map { inline($0) }.joined()
    }

    private func inline(_ markup: Markup) -> String {
        switch markup {
        case let text as Markdown.Text:
            return self.text(text.string)
        case let emphasis as Emphasis:
            return "<em>\(inlines(emphasis.children))</em>"
        case let strong as Strong:
            return "<strong>\(inlines(strong.children))</strong>"
        case let strike as Strikethrough:
            return "<del>\(inlines(strike.children))</del>"
        case let code as InlineCode:
            wordCount += 1
            return "<code>\(HTML.escape(code.code))</code>"
        case is SoftBreak:
            return "\n"
        case is LineBreak:
            return "<br>"
        case let link as Markdown.Link:
            let destination = link.destination ?? ""
            let title = link.title.map { " title=\"\(HTML.attribute($0))\"" } ?? ""
            let wiki = destination.hasPrefix("wiki:") ? " class=\"wikilink\"" : ""
            return "<a href=\"\(HTML.attribute(destination))\"\(title)\(wiki)>\(inlines(link.children))</a>"
        case let image as Markdown.Image:
            return self.image(image)
        case let html as InlineHTML:
            return html.rawHTML
        case let symbol as SymbolLink:
            return "<code>\(HTML.escape(symbol.destination ?? ""))</code>"
        default:
            return inlines(markup.children)
        }
    }

    /// Plain text plus the inline extensions that live inside a text run:
    /// math and footnote tokens, `==highlights==` and `:emoji:` shortcodes.
    private func text(_ string: String) -> String {
        wordCount += preprocessor.restore(string).split(whereSeparator: { $0.isWhitespace }).count
        var html = HTML.escape(string)
        if html.contains("GALLEY") {
            html = Preprocessor.replaceTokens(in: html) { kind, index in
                switch kind {
                case "MI", "MD":
                    guard index < preprocessor.math.count else { return nil }
                    let display = kind == "MD" ? " display" : ""
                    return "<span class=\"math\(display)\">\(HTML.escape(preprocessor.math[index].tex))</span>"
                case "FN":
                    return "<sup class=\"footnote-ref\"><a href=\"#fn-\(index + 1)\" id=\"fnref-\(index + 1)\">\(index + 1)</a></sup>"
                default:
                    return nil
                }
            }
        }
        if html.contains("==") {
            html = html.replacingOccurrences(of: #"==(?=\S)(.+?)(?<=\S)=="#, with: "<mark>$1</mark>", options: .regularExpression)
        }
        if html.contains(":") {
            html = Emoji.replaceShortcodes(in: html)
        }
        return html
    }

    private func image(_ image: Markdown.Image) -> String {
        let alt = HTML.attribute(image.plainText)
        let source = image.source ?? ""
        let title = image.title.map { " title=\"\(HTML.attribute($0))\"" } ?? ""
        if source.hasPrefix("data:") {
            return "<img src=\"\(HTML.attribute(source))\" alt=\"\(alt)\"\(title)>"
        }
        if let url = URL(string: source), let scheme = url.scheme, scheme == "http" || scheme == "https" {
            // No network: show where the image lives instead of a broken frame.
            let label = image.plainText.isEmpty ? (url.host ?? source) : image.plainText
            return "<a class=\"remote-image\" href=\"\(HTML.attribute(source))\">\(HTML.escape(label))</a>"
        }
        guard let resolved = ResourceURL.file(for: source, relativeTo: baseURL) else {
            return "<span class=\"remote-image\">\(HTML.escape(image.plainText))</span>"
        }
        return "<img src=\"\(HTML.attribute(resolved))\" alt=\"\(alt)\"\(title) loading=\"lazy\">"
    }

    /// GitHub's anchor rules: lowercase, punctuation dropped, spaces to
    /// hyphens, `-1`, `-2` … for repeats.
    private func slug(for title: String) -> String {
        let base = Slug.make(title)
        let count = slugs[base, default: 0]
        slugs[base] = count + 1
        return count == 0 ? base : "\(base)-\(count)"
    }
}

nonisolated enum Slug {
    static func make(_ title: String) -> String {
        let lowered = title.lowercased()
        var result = ""
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                result.unicodeScalars.append(scalar)
            } else if scalar == " " {
                result.append("-")
            }
        }
        return result.isEmpty ? "section" : result
    }
}

/// URLs for files inside the page, served by `ResourceSchemeHandler`.
nonisolated enum ResourceURL {
    static let scheme = "galley"

    /// `galley://file/<absolute path>` for a relative or absolute file path.
    static func file(for path: String, relativeTo base: URL?) -> String? {
        let decoded = path.removingPercentEncoding ?? path
        let url: URL
        if decoded.hasPrefix("/") {
            url = URL(fileURLWithPath: decoded)
        } else if let base {
            url = base.appendingPathComponent(decoded)
        } else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "file"
        components.path = url.standardizedFileURL.path
        return components.string
    }
}

nonisolated enum HTML {
    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.append(character)
            }
        }
        return result
    }

    static func attribute(_ text: String) -> String {
        escape(text).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
