import Foundation

/// The reader's highlights and notes as Markdown an agent can act on:
/// where each file is, what was marked, and what the reader said about it.
nonisolated enum Feedback {
    struct Item: Equatable {
        var text: String
        var note: String?
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
                var entry = "\(index + 1). Marked:\n" + quote
                if let note = item.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    entry += "\n\n   " + note.replacingOccurrences(of: "\n", with: "\n   ")
                }
                out.append(entry)
            }
        }
        return out.joined(separator: "\n\n") + "\n"
    }

    /// Whether a highlight's text is still in a file's Markdown, comparing
    /// letters and digits only — the source has emphasis marks, link syntax
    /// and line breaks that the rendered text does not.
    static func isStillPresent(_ text: String, in source: String) -> Bool {
        let needle = letters(text)
        guard !needle.isEmpty else { return true }
        // Link targets and tags are in the source but never on the page.
        let visible = source
            .replacingOccurrences(of: #"\]\([^)]*\)"#, with: "]", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return letters(visible).contains(needle)
    }

    private static func letters(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}
