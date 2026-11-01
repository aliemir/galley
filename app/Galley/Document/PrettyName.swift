import Foundation

/// Turns `2026-10-30_auth-migrationPlan.md` into "Auth Migration Plan".
nonisolated enum PrettyName {
    /// Words kept in capitals wherever they appear.
    static let acronyms: Set<String> = [
        "API", "APIs", "AI", "CLI", "CI", "CD", "CSS", "CSV", "DB", "FAQ", "GPT", "HTML", "HTTP", "HTTPS",
        "ID", "IDs", "IO", "iOS", "JSON", "JWT", "LLM", "MCP", "MVP", "OKR", "OKRs", "PR", "PRD", "PRs",
        "QA", "README", "REST", "RFC", "SDK", "SDKs", "SEO", "SQL", "SSO", "TODO", "UI", "UX", "URL", "URLs",
        "UUID", "v1", "v2", "v3", "XML", "YAML", "CLAUDE", "AGENTS", "GEMINI", "CHANGELOG", "LICENSE",
        "macOS", "GitHub", "TestFlight", "OAuth",
    ]

    /// Short words left lowercase inside a title, as in a book's: "State of
    /// the Art Review". Never the first or last word.
    static let minorWords: Set<String> = [
        "a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "into", "nor", "of",
        "on", "or", "per", "the", "to", "via", "vs", "with",
    ]

    private static let acronymLookup: [String: String] = {
        var table: [String: String] = [:]
        for word in acronyms { table[word.lowercased()] = word }
        return table
    }()

    static func make(fromFilename filename: String) -> String {
        var name = filename
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            name = String(name[..<dot])
        }
        return tidy(name, original: filename)
    }

    /// `03-research_notes` → "Research Notes". Dots stay: a folder has no extension.
    static func make(fromFolderName folder: String) -> String {
        tidy(folder, original: folder)
    }

    private static func tidy(_ stem: String, original filename: String) -> String {
        let name = stripLeadingDateOrNumber(stem)

        // camelCase and digit boundaries become spaces.
        var spaced = ""
        var previous: Character?
        for character in name {
            if let previous {
                // "q3OKRs" → "q3 OKRs"; letters followed by digits stay together ("v2", "q3").
                let boundary = (previous.isLowercase && character.isUppercase)
                    || (previous.isNumber && character.isUppercase)
                if boundary { spaced.append(" ") }
            }
            spaced.append(character)
            previous = character
        }
        let words = spaced
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
        guard !words.isEmpty else { return filename }

        // An all-caps name is shouting by convention (README, CLAUDE): keep
        // known words as written, title-case the rest.
        var result: [String] = []
        for (index, word) in words.enumerated() {
            if let acronym = acronymLookup[word.lowercased()] {
                result.append(acronym)
            } else if word.count > 1, word == word.uppercased(), word.contains(where: \.isLetter), words.count > 1 {
                // An unknown all-caps word inside a phrase is likely an acronym.
                result.append(word)
            } else if index > 0, index < words.count - 1, minorWords.contains(word.lowercased()) {
                result.append(word.lowercased())
            } else {
                result.append(word.prefix(1).uppercased() + word.dropFirst().lowercased())
            }
        }
        return result.joined(separator: " ")
    }

    /// Drops `2026-10-30_`, `20261030-`, `2026_10_30 `, `03-`, `3.`, `001_` …
    /// but keeps a name that is nothing but a number.
    static func stripLeadingDateOrNumber(_ name: String) -> String {
        let patterns = [
            #"^\d{4}[-_.]\d{1,2}[-_.]\d{1,2}(?:[T_ -]\d{1,2}[-:.]?\d{2}(?:[-:.]?\d{2})?)?[\s_.-]+"#,
            #"^\d{8}(?:[T_-]?\d{4,6})?[\s_.-]+"#,
            #"^\d{1,4}[\s_.)-]+"#,
        ]
        for pattern in patterns {
            if let range = name.range(of: pattern, options: .regularExpression) {
                let rest = String(name[range.upperBound...])
                if rest.contains(where: \.isLetter) { return rest }
            }
        }
        return name
    }
}
