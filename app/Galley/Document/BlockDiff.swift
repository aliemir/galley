import Foundation

/// What changed in a document since the version the reader last read.
nonisolated struct DocumentChanges: Equatable {
    enum Change: Equatable {
        case added
        /// The unit replaced an older one; `oldHTML` is that unit's inner
        /// HTML so the page can mark the inserted words.
        case modified(oldHTML: String)
    }

    /// Keyed by the new document's unit index.
    var units: [Int: Change] = [:]
    var removed = 0

    var isEmpty: Bool { units.isEmpty && removed == 0 }
    var added: Int { units.values.filter { $0 == .added }.count }
    var modified: Int { units.count - added }

    static let none = DocumentChanges()
}

nonisolated enum BlockDiff {
    /// Compares two documents unit by unit. Removed and inserted units that
    /// sit in the same gap between unchanged units, and share enough words,
    /// count as one modified unit instead of a removal plus an addition.
    static func changes(from old: [DiffUnit], to new: [DiffUnit]) -> DocumentChanges {
        let difference = new.map(\.key).difference(from: old.map(\.key))
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }

        var result = DocumentChanges()
        var i = 0
        var j = 0
        while i < old.count || j < new.count {
            var gapRemoved: [Int] = []
            var gapInserted: [Int] = []
            while i < old.count, removed.contains(i) { gapRemoved.append(i); i += 1 }
            while j < new.count, inserted.contains(j) { gapInserted.append(j); j += 1 }

            if gapRemoved.isEmpty, gapInserted.isEmpty {
                // An unchanged unit present in both.
                i += 1
                j += 1
                continue
            }

            var unpairedOld = gapRemoved
            for newIndex in gapInserted {
                if let best = unpairedOld.enumerated().max(by: {
                    similarity(old[$0.element].key, new[newIndex].key) < similarity(old[$1.element].key, new[newIndex].key)
                }), similarity(old[best.element].key, new[newIndex].key) >= 0.3 {
                    result.units[newIndex] = .modified(oldHTML: old[best.element].html)
                    unpairedOld.remove(at: best.offset)
                } else {
                    result.units[newIndex] = .added
                }
            }
            result.removed += unpairedOld.count
        }
        return result
    }

    /// Word-set overlap, 0…1.
    static func similarity(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }))
        let wordsB = Set(b.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }))
        let union = wordsA.union(wordsB).count
        guard union > 0 else { return a == b ? 1 : 0 }
        return Double(wordsA.intersection(wordsB).count) / Double(union)
    }
}
