import Foundation

/// Full-text search over a workspace's Markdown: every word of the query
/// must appear somewhere in the file (case and accents ignored), and each
/// hit carries a line or two to show where.
nonisolated enum TextSearch {
    struct Document: Sendable {
        /// Identifies the file to the caller (workspace and path).
        var key: String
        var title: String
        var text: String
        var modified: Date
    }

    struct Snippet: Equatable, Sendable {
        struct Part: Equatable, Sendable {
            var text: String
            var isMatch: Bool
        }
        var parts: [Part]
        var plain: String { parts.map(\.text).joined() }
    }

    struct Hit: Sendable {
        var key: String
        var snippets: [Snippet]
        /// What to look for once the file is open: the whole query when it
        /// appears as a phrase, else its longest word.
        var findTerm: String
        var score: Int
    }

    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The first place `term` starts a word in `text` — "rate" finds "rate"
    /// and "Rate-limit", not "separate" — from `start` on.
    static func wordMatch(_ term: String, in text: String, from start: String.Index? = nil) -> Range<String.Index>? {
        var cursor = start ?? text.startIndex
        while cursor < text.endIndex, let range = text.range(of: term, options: options, range: cursor..<text.endIndex) {
            if range.lowerBound == text.startIndex { return range }
            let before = text[text.index(before: range.lowerBound)]
            // A word starts after anything that is not a letter or digit, or
            // at a camelCase hump.
            let first = text[range.lowerBound]
            if !(before.isLetter || before.isNumber) || (before.isLowercase && first.isUppercase) { return range }
            cursor = text.index(after: range.lowerBound)
        }
        return nil
    }

    static func terms(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func search(_ query: String, in documents: [Document], limit: Int = 60) -> [Hit] {
        let terms = terms(query)
        guard !terms.isEmpty else { return [] }
        let phrase = terms.joined(separator: " ")
        var hits: [(Hit, Date)] = []
        for document in documents {
            guard terms.allSatisfy({ wordMatch($0, in: document.text) != nil }) else { continue }
            var score = 0
            let inTitle = terms.filter { wordMatch($0, in: document.title) != nil }.count
            score += inTitle == terms.count ? 1000 : inTitle * 300
            let hasPhrase = terms.count > 1 && wordMatch(phrase, in: document.text) != nil
            if hasPhrase { score += 200 }
            score += min(30, occurrences(of: terms[0], in: document.text)) * 10
            let findTerm = terms.count == 1 || hasPhrase ? phrase : terms.max { $0.count < $1.count } ?? phrase
            hits.append((Hit(key: document.key, snippets: snippets(for: terms, in: document.text), findTerm: findTerm, score: score), document.modified))
        }
        return hits
            .sorted { $0.0.score != $1.0.score ? $0.0.score > $1.0.score : $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    static func occurrences(of term: String, in text: String) -> Int {
        var count = 0
        var start = text.startIndex
        while count < 100, let range = wordMatch(term, in: text, from: start) {
            count += 1
            start = range.upperBound
        }
        return count
    }

    /// Up to two lines that say the most: those with the most query words,
    /// earliest first, cleaned of Markdown and clipped around the match.
    static func snippets(for terms: [String], in text: String, maximum: Int = 2, width: Int = 110) -> [Snippet] {
        var candidates: [(line: String, found: Int, order: Int)] = []
        for (order, raw) in text.split(whereSeparator: \.isNewline).enumerated() {
            let line = clean(String(raw))
            guard !line.isEmpty else { continue }
            let found = terms.filter { wordMatch($0, in: line) != nil }.count
            if found > 0 { candidates.append((line, found, order)) }
        }
        return candidates
            .sorted { $0.found != $1.found ? $0.found > $1.found : $0.order < $1.order }
            .prefix(maximum)
            .sorted { $0.order < $1.order }
            .map { snippet(clip($0.line, around: terms, width: width), terms: terms) }
    }

    /// A line as it reads, not as it is written: no heading hashes, list
    /// marks, quote bars, link targets, emphasis or table pipes.
    static func clean(_ line: String) -> String {
        var text = line
        let rules: [(String, String)] = [
            (#"^\s*(#{1,6}\s+|>\s*|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+)"#, ""),
            (#"!?\[([^\]]*)\]\([^)]*\)"#, "$1"),
            (#"\*\*|__|`|~~|==|<[^>]+>"#, ""),
            (#"\s*\|\s*"#, " · "),
            (#"\s+"#, " "),
        ]
        for (pattern, template) in rules {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " ·"))
    }

    static func clip(_ line: String, around terms: [String], width: Int) -> String {
        guard line.count > width,
              let first = terms.compactMap({ wordMatch($0, in: line) }).min(by: { $0.lowerBound < $1.lowerBound })
        else { return line.count > width ? String(line.prefix(width)) + "…" : line }
        let offset = line.distance(from: line.startIndex, to: first.lowerBound)
        let start = max(0, min(offset - width / 3, line.count - width))
        let from = line.index(line.startIndex, offsetBy: start)
        let to = line.index(from, offsetBy: min(width, line.count - start))
        return (start > 0 ? "…" : "") + line[from..<to] + (to < line.endIndex ? "…" : "")
    }

    static func snippet(_ text: String, terms: [String]) -> Snippet {
        var ranges: [Range<String.Index>] = []
        for term in terms {
            var start = text.startIndex
            while let range = wordMatch(term, in: text, from: start) {
                ranges.append(range)
                start = range.upperBound
            }
        }
        ranges.sort { $0.lowerBound < $1.lowerBound }
        var parts: [Snippet.Part] = []
        var cursor = text.startIndex
        for range in ranges where range.lowerBound >= cursor {
            if cursor < range.lowerBound { parts.append(.init(text: String(text[cursor..<range.lowerBound]), isMatch: false)) }
            parts.append(.init(text: String(text[range]), isMatch: true))
            cursor = range.upperBound
        }
        if cursor < text.endIndex { parts.append(.init(text: String(text[cursor...]), isMatch: false)) }
        return Snippet(parts: parts)
    }
}

/// The text of every file searched, kept between searches and re-read only
/// when a file's modification date moves.
actor TextIndex {
    struct Entry: Sendable {
        var key: String
        var title: String
        var url: URL
        var modified: Date
    }

    private var cache: [String: (modified: Date, text: String)] = [:]

    func documents(_ entries: [Entry]) -> [TextSearch.Document] {
        var documents: [TextSearch.Document] = []
        var keep = Set<String>()
        for entry in entries {
            if Task.isCancelled { return [] }
            keep.insert(entry.key)
            let text: String
            if let cached = cache[entry.key], cached.modified == entry.modified {
                text = cached.text
            } else {
                text = (try? String(contentsOf: entry.url, encoding: .utf8)) ?? ""
                cache[entry.key] = (entry.modified, text)
            }
            documents.append(.init(key: entry.key, title: entry.title, text: text, modified: entry.modified))
        }
        // Files gone from every workspace leave the cache too.
        if keep.count < cache.count { cache = cache.filter { keep.contains($0.key) } }
        return documents
    }
}
