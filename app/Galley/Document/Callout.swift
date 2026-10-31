import Foundation

/// Callout types from GitHub alerts and Obsidian, folded into the few colour
/// families the stylesheet knows.
nonisolated enum Callout {
    private static let families: [String: String] = [
        "note": "note", "info": "note", "todo": "note",
        "abstract": "summary", "summary": "summary", "tldr": "summary",
        "tip": "tip", "hint": "tip",
        "important": "important",
        "success": "success", "check": "success", "done": "success",
        "question": "question", "help": "question", "faq": "question",
        "warning": "warning", "attention": "warning",
        "caution": "danger", "failure": "danger", "fail": "danger", "missing": "danger",
        "danger": "danger", "error": "danger", "bug": "danger",
        "example": "example",
        "quote": "quote", "cite": "quote",
    ]

    static func family(of type: String) -> String {
        families[type.lowercased()] ?? "note"
    }

    static func defaultTitle(of type: String) -> String {
        switch type.lowercased() {
        case "tldr": return "TL;DR"
        case "faq": return "FAQ"
        default: return type.prefix(1).uppercased() + type.dropFirst().lowercased()
        }
    }
}

/// `:shortcode:` → emoji, using GitHub's gemoji names (bundled `emoji.json`).
nonisolated enum Emoji {
    static let table: [String: String] = {
        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return table
    }()

    private static let pattern = try? NSRegularExpression(pattern: #":([a-z0-9_+\-]{1,40}):"#)

    static func replaceShortcodes(in text: String) -> String {
        guard let pattern else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let emoji = table[ns.substring(with: match.range(at: 1))] else { continue }
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)) + emoji
            cursor = match.range.location + match.range.length
        }
        return cursor == 0 ? text : result + ns.substring(from: cursor)
    }
}
