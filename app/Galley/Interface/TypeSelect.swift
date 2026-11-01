import Foundation

/// Finder-style type-to-select: letters typed in quick succession build a
/// prefix, and the first name that starts with it is picked. A pause starts
/// over; the same letter typed again steps through the names that start
/// with it.
nonisolated struct TypeSelect {
    /// Seconds of quiet before the next key starts a new search.
    static let timeout: TimeInterval = 1.0

    private(set) var buffer = ""
    private var lastKey = Date.distantPast

    var isActive: Bool { !buffer.isEmpty }

    /// Adds `text` to the search, or starts a new one after a pause.
    mutating func type(_ text: String, at now: Date = Date()) -> String {
        if now.timeIntervalSince(lastKey) > Self.timeout { buffer = "" }
        buffer += text
        lastKey = now
        return buffer
    }

    /// True while a key typed now would extend the search.
    func continues(at now: Date = Date()) -> Bool {
        isActive && now.timeIntervalSince(lastKey) <= Self.timeout
    }

    mutating func reset() {
        buffer = ""
        lastKey = .distantPast
    }

    /// The index of the name `query` selects, starting the search from
    /// `current` when cycling. Case and accents do not matter.
    static func match(_ query: String, in names: [String], current: Int?) -> Int? {
        let key = fold(query)
        guard !key.isEmpty else { return nil }
        let folded = names.map(fold)

        // "sss": no name starts with it, so step through the names starting with "s".
        if key.count > 1, Set(key).count == 1, !folded.contains(where: { $0.hasPrefix(key) }) {
            let letter = String(key.prefix(1))
            let hits = folded.indices.filter { folded[$0].hasPrefix(letter) }
            guard !hits.isEmpty else { return nil }
            if let current, let next = hits.first(where: { $0 > current }) { return next }
            return hits.first
        }
        if let index = folded.firstIndex(where: { $0.hasPrefix(key) }) { return index }
        // Then the start of any word: "rate" finds "API rate limits".
        return folded.firstIndex { name in
            name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0.hasPrefix(key) }
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
