import Foundation

/// Rewrites the syntax CommonMark does not know before the parser sees it.
///
/// Math would otherwise be mangled (`$a_1 + b_2$` turns into emphasis) and
/// footnote definitions can parse as link reference definitions, so both are
/// swapped for opaque tokens that survive parsing untouched and are expanded
/// again while rendering. Wikilinks become ordinary links with a `wiki:`
/// destination. Fenced code and inline code spans are never touched.
nonisolated struct Preprocessor {
    struct Math: Hashable {
        let tex: String
        let display: Bool
    }

    struct Footnote {
        let label: String
        let text: String
    }

    private(set) var math: [Math] = []
    /// Definitions in the order their label is first referenced.
    private(set) var footnotes: [Footnote] = []
    private var definitions: [String: String] = [:]
    private var footnoteNumbers: [String: Int] = [:]

    static let tokenPattern = #"GALLEY(MI|MD|FN)(\d+)Z"#

    mutating func process(_ source: String) -> String {
        let lines = collectFootnoteDefinitions(source.components(separatedBy: "\n"))
        var output: [String] = []
        var fence: (character: Character, length: Int)?
        var display: (prefix: String, lines: [String])?

        for line in lines {
            let (prefix, content) = Self.splitQuotePrefix(line)
            let trimmed = content.trimmingCharacters(in: .whitespaces)

            if var open = display {
                if trimmed.hasSuffix("$$") {
                    open.lines.append(String(trimmed.dropLast(2)))
                    output.append(open.prefix + token("MD", appendMath(open.lines, display: true)))
                    display = nil
                } else {
                    open.lines.append(content)
                    display = open
                }
                continue
            }

            if let open = fence {
                output.append(line)
                let run = trimmed.prefix(while: { $0 == open.character })
                if run.count >= open.length, trimmed.dropFirst(run.count).allSatisfy(\.isWhitespace) { fence = nil }
                continue
            }
            if let first = trimmed.first, first == "`" || first == "~" {
                let run = trimmed.prefix(while: { $0 == first }).count
                if run >= 3 {
                    fence = (first, run)
                    output.append(line)
                    continue
                }
            }

            if trimmed.hasPrefix("$$") {
                let rest = trimmed.dropFirst(2)
                if rest.count >= 2, rest.hasSuffix("$$") {
                    output.append(prefix + token("MD", appendMath([String(rest.dropLast(2))], display: true)))
                } else {
                    display = (prefix, [String(rest)])
                }
                continue
            }

            output.append(prefix + inline(content))
        }

        if let open = display {
            // Unclosed $$: give the text back as it was written.
            output.append(open.prefix + "$$" + open.lines.joined(separator: "\n"))
        }
        return output.joined(separator: "\n")
    }

    /// Replaces tokens with what the author wrote, for diff keys that stay
    /// stable when an earlier math span or footnote shifts the numbering.
    func restore(_ text: String) -> String {
        guard text.contains("GALLEY") else { return text }
        return Self.replaceTokens(in: text) { kind, index in
            switch kind {
            case "MI": return index < math.count ? "$\(math[index].tex)$" : nil
            case "MD": return index < math.count ? "$$\(math[index].tex)$$" : nil
            case "FN": return index < footnotes.count ? "[^\(footnotes[index].label)]" : nil
            default: return nil
            }
        }
    }

    static func replaceTokens(in text: String, _ transform: (String, Int) -> String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: tokenPattern) else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let kind = ns.substring(with: match.range(at: 1))
            let index = Int(ns.substring(with: match.range(at: 2))) ?? -1
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += transform(kind, index) ?? ns.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    // MARK: - Pieces

    private func token(_ kind: String, _ index: Int) -> String { "GALLEY\(kind)\(index)Z" }

    private mutating func appendMath(_ lines: [String], display: Bool) -> Int {
        math.append(Math(tex: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), display: display))
        return math.count - 1
    }

    /// Leading whitespace and `>` markers, so math inside quotes and callouts
    /// is found too.
    private static func splitQuotePrefix(_ line: String) -> (String, String) {
        var index = line.startIndex
        var lastQuote: String.Index?
        while index < line.endIndex, line[index] == " " || line[index] == "\t" || line[index] == ">" {
            if line[index] == ">" { lastQuote = index }
            index = line.index(after: index)
        }
        guard let lastQuote else { return ("", line) }
        var end = line.index(after: lastQuote)
        if end < line.endIndex, line[end] == " " { end = line.index(after: end) }
        return (String(line[..<end]), String(line[end...]))
    }

    /// Pulls `[^label]: text` definitions (plus indented continuation lines)
    /// out of the source, outside fenced code.
    private mutating func collectFootnoteDefinitions(_ lines: [String]) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"^\[\^([^\]\s]+)\]:[ \t]?(.*)$"#) else { return lines }
        var kept: [String] = []
        var fence: Character?
        var current: String?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let first = trimmed.first, first == "`" || first == "~", trimmed.prefix(while: { $0 == first }).count >= 3 {
                fence = fence == nil ? first : (fence == first ? nil : fence)
            }
            if fence == nil, let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let label = Range(match.range(at: 1), in: line), let text = Range(match.range(at: 2), in: line) {
                current = String(line[label])
                definitions[String(line[label])] = String(line[text])
                continue
            }
            if let label = current, fence == nil, line.hasPrefix("    ") || line.hasPrefix("\t") {
                definitions[label, default: ""] += "\n" + trimmed
                continue
            }
            current = nil
            kept.append(line)
        }
        return kept
    }

    private mutating func footnoteIndex(_ label: String) -> Int? {
        guard let text = definitions[label] else { return nil }
        if let existing = footnoteNumbers[label] { return existing }
        footnotes.append(Footnote(label: label, text: text))
        footnoteNumbers[label] = footnotes.count - 1
        return footnotes.count - 1
    }

    /// Inline math, footnote references and wikilinks, skipping code spans
    /// and backslash escapes.
    private mutating func inline(_ line: String) -> String {
        guard line.contains("$") || line.contains("[^") || line.contains("[[") else { return line }
        let chars = Array(line)
        var out = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count {
                out.append(c)
                out.append(chars[i + 1])
                i += 2
                continue
            }
            if c == "`" {
                let end = Self.codeSpanEnd(chars, from: i)
                out += String(chars[i..<end])
                i = end
                continue
            }
            if c == "$", let (tex, display, end) = Self.mathSpan(chars, from: i) {
                out += token(display ? "MD" : "MI", appendMath([tex], display: display))
                i = end
                continue
            }
            if c == "[", i + 1 < chars.count, chars[i + 1] == "^",
               let close = chars[(i + 2)...].firstIndex(of: "]"), close > i + 2 {
                let label = String(chars[(i + 2)..<close])
                if !label.contains(" "), let index = footnoteIndex(label) {
                    out += token("FN", index)
                    i = close + 1
                    continue
                }
            }
            if c == "[", i + 1 < chars.count, chars[i + 1] == "[", let (link, end) = Self.wikilink(chars, from: i) {
                out += link
                i = end
                continue
            }
            out.append(c)
            i += 1
        }
        return out
    }

    /// Index just past a code span that opens at `start`, or past the
    /// backtick run when it never closes.
    private static func codeSpanEnd(_ chars: [Character], from start: Int) -> Int {
        var run = 0
        while start + run < chars.count, chars[start + run] == "`" { run += 1 }
        var j = start + run
        while j < chars.count {
            if chars[j] == "`" {
                var closing = 0
                while j + closing < chars.count, chars[j + closing] == "`" { closing += 1 }
                if closing == run { return j + closing }
                j += closing
            } else {
                j += 1
            }
        }
        return start + run
    }

    /// `$…$` (no space inside the delimiters, not followed by a digit, so
    /// "$5 and $10" stays text) or `$$…$$` within one line.
    private static func mathSpan(_ chars: [Character], from start: Int) -> (String, Bool, Int)? {
        let display = start + 1 < chars.count && chars[start + 1] == "$"
        let open = display ? 2 : 1
        let contentStart = start + open
        guard contentStart < chars.count, !chars[contentStart].isWhitespace, chars[contentStart] != "$" else { return nil }
        var j = contentStart
        while j < chars.count {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == "$" {
                if !display { break }
                if j + 1 < chars.count, chars[j + 1] == "$" { break }
            }
            j += 1
        }
        guard j < chars.count, j > contentStart else { return nil }
        if !display {
            if chars[j - 1].isWhitespace { return nil }
            if j + 1 < chars.count, chars[j + 1].isNumber { return nil }
        }
        return (String(chars[contentStart..<j]), display, j + open)
    }

    /// `[[Target]]`, `[[Target|Label]]`, `[[Target#Heading]]` and the
    /// embedded-image form `![[image.png]]` (the `!` is already in the output).
    private static func wikilink(_ chars: [Character], from start: Int) -> (String, Int)? {
        var j = start + 2
        while j + 1 < chars.count, !(chars[j] == "]" && chars[j + 1] == "]") {
            if chars[j] == "[" || chars[j] == "\n" { return nil }
            j += 1
        }
        guard j + 1 < chars.count, j > start + 2 else { return nil }
        let inner = String(chars[(start + 2)..<j])
        let parts = inner.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let target = parts[0]
        let label = parts.count > 1 ? parts[1] : target
        let escapedLabel = label.replacingOccurrences(of: "]", with: "\\]").replacingOccurrences(of: "[", with: "\\[")
        let escapedTarget = target.replacingOccurrences(of: ">", with: "%3E").replacingOccurrences(of: "<", with: "%3C")
        let isImage = start > 0 && chars[start - 1] == "!"
        return ("[\(escapedLabel)](<\(isImage ? "" : "wiki:")\(escapedTarget)>)", j + 2)
    }
}
