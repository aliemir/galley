import Foundation

/// The reader's highlights and notes as Markdown an agent can act on:
/// where each file is, what was marked, and what the reader said about it.
nonisolated enum Feedback {
    struct Item: Equatable {
        var text: String
        var note: String?
        /// The headings the passage sits under, outermost first, without the
        /// document's own title: where to find it at a glance.
        var section: [String] = []
        /// Not saved by the reader yet; listed only when asked for.
        var draft = false
        var saved: Date?
    }

    struct File: Equatable {
        /// Absolute, so an agent working anywhere can open it.
        var path: String
        var items: [Item]
    }

    static func format(_ files: [File]) -> String {
        let files = files.filter { !$0.items.isEmpty }
        guard !files.isEmpty else { return "" }
        var out = ["Feedback from reading \(files.count == 1 ? "this file" : "these files") in Galley. Each quote is a passage I marked; a note under it says what I want done about it."]
        for file in files {
            out.append("## \(file.path)")
            for (index, item) in file.items.enumerated() {
                let quote = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: .newlines)
                    .map { "   > " + $0 }
                    .joined(separator: "\n")
                let place = item.section.isEmpty ? "" : " in " + item.section.joined(separator: " › ")
                var entry = "\(index + 1). Marked\(place)\(item.draft ? " (draft, not saved yet)" : ""):\n" + quote
                if let note = item.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    entry += "\n\n   " + note.replacingOccurrences(of: "\n", with: "\n   ")
                }
                out.append(entry)
            }
        }
        return out.joined(separator: "\n\n") + "\n"
    }

    /// The feedback on one file as it reads now: passages no longer in the
    /// text are left out (the agent dealt with them), and each one left says
    /// which section it is in.
    static func items(_ highlights: [Highlight], in source: String) -> [Item] {
        let present = highlights.filter { isStillPresent($0.text, in: source) }
        guard !present.isEmpty else { return [] }
        let places = Sections(source)
        return present.map { Item(text: $0.text, note: $0.note, section: places.path(for: $0), draft: $0.isDraft, saved: $0.sent) }
    }

    /// Where passages sit in a file's headings. The file is rendered once;
    /// a passage is found by its letters, with the text before it to tell
    /// two copies of the same sentence apart.
    struct Sections {
        private let outline: [OutlineItem]
        private let joined: String
        /// Where each diff unit starts in `joined`.
        private let starts: [Int]
        private let skipsTitle: Bool

        init(_ source: String) {
            let rendered = MarkdownRenderer().render(source)
            outline = rendered.outline
            var joined = ""
            var starts: [Int] = []
            for unit in rendered.units {
                starts.append(joined.count)
                joined += Feedback.letters(Feedback.visible(unit.key))
            }
            self.joined = joined
            self.starts = starts
            // A lone level-1 heading at the top is the document's title.
            skipsTitle = outline.first?.level == 1 && outline.filter { $0.level == 1 }.count == 1
        }

        func path(for highlight: Highlight) -> [String] {
            let text = Feedback.letters(highlight.text)
            guard !text.isEmpty else { return [] }
            let context = String(Feedback.letters(highlight.prefix).suffix(40))
            var offset: Int?
            for (before, needle) in [(context, context + text), ("", text), ("", String(text.prefix(12)))] where !needle.isEmpty {
                if let range = joined.range(of: needle) {
                    offset = joined.distance(from: joined.startIndex, to: range.lowerBound) + before.count
                    break
                }
            }
            guard let offset, let unit = starts.lastIndex(where: { $0 <= offset }) else { return [] }
            var stack: [OutlineItem] = []
            for item in outline where item.unit <= unit {
                while let last = stack.last, last.level >= item.level { stack.removeLast() }
                stack.append(item)
            }
            if skipsTitle, stack.first?.id == outline.first?.id { stack.removeFirst() }
            return stack.map(\.title)
        }
    }

    /// Whether a highlight's text is still in a file's Markdown, comparing
    /// letters and digits only — the source has emphasis marks, link syntax
    /// and line breaks that the rendered text does not.
    static func isStillPresent(_ text: String, in source: String) -> Bool {
        let needle = letters(text)
        guard !needle.isEmpty else { return true }
        return letters(visible(source)).contains(needle)
    }

    /// Link targets and tags are in the source but never on the page.
    static func visible(_ source: String) -> String {
        source
            .replacingOccurrences(of: #"\]\([^)]*\)"#, with: "]", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    static func letters(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}
