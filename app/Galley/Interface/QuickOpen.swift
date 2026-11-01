import SwiftUI

/// Subsequence matching with bonuses for word starts and runs, so "amp"
/// finds "Auth Migration Plan" and "rl" finds "rate limits".
nonisolated enum Fuzzy {
    static func score(_ query: String, in text: String) -> Int? {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return 0 }
        let haystack = Array(text.lowercased())
        let original = Array(text)
        var score = 0
        var index = 0
        var previous = -2
        for character in needle {
            var found: Int?
            while index < haystack.count {
                if haystack[index] == character { found = index; break }
                index += 1
            }
            guard let position = found else { return nil }
            score += 10
            let atWordStart = position == 0 || !original[position - 1].isLetter
                || (original[position].isUppercase && original[position - 1].isLowercase)
            if atWordStart { score += 14 }
            if position == previous + 1 { score += 8 } else if previous >= 0 { score -= min(6, position - previous - 1) }
            previous = position
            index = position + 1
        }
        // Shorter texts with the same matches rank first.
        return score * 100 - haystack.count
    }
}

struct QuickOpenView: View {
    init(seed: String) {
        _query = State(initialValue: seed)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    /// Starts with the seed ("#" for sections) rather than being set after
    /// appearing: a change during the palette's fade-in left the list stale.
    @State private var query: String
    @State private var selection = 0
    @State private var textHits: [Result] = []
    @State private var isSearchingText = false
    @FocusState private var isFocused: Bool

    private enum Result: Identifiable {
        case file(Workspace, DocumentFile)
        case heading(OutlineItem)
        /// A file whose text has every word of the query.
        case text(Workspace, DocumentFile, TextSearch.Hit)

        var id: String {
            switch self {
            case let .file(workspace, file): "f/\(workspace.id)/\(file.id)"
            case let .heading(item): "h/\(item.id)"
            case let .text(workspace, file, _): "t/\(workspace.id)/\(file.id)"
            }
        }

        var isText: Bool { if case .text = self { true } else { false } }
    }

    private var searchesText: Bool { model.quickOpenSearchesText }

    /// Text is searched from three characters in the file palette (names
    /// come first), from two when searching text alone.
    private var textQuery: String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !query.hasPrefix("#"), trimmed.count >= (searchesText ? 2 : 3) else { return nil }
        return trimmed
    }

    private var results: [Result] {
        if searchesText { return textHits }
        return nameResults + (textQuery == nil ? [] : textHits)
    }

    private var nameResults: [Result] {
        if query.hasPrefix("#") {
            let text = String(query.dropFirst())
            let outline = model.current?.rendered.outline ?? []
            if text.trimmingCharacters(in: .whitespaces).isEmpty { return outline.map(Result.heading) }
            return outline
                .compactMap { item in Fuzzy.score(text, in: item.title).map { (item, $0) } }
                .sorted { $0.1 > $1.1 }
                .map { Result.heading($0.0) }
        }
        var scored: [(Result, Int)] = []
        for workspace in model.workspaces {
            for file in workspace.files {
                let name = model.settings.displayName(for: file)
                if query.isEmpty {
                    scored.append((.file(workspace, file), Int(file.modified.timeIntervalSince1970)))
                    continue
                }
                let byName = Fuzzy.score(query, in: name).map { $0 + 400 }
                let byPath = Fuzzy.score(query, in: workspace.name + "/" + file.relativePath)
                let byHeading = file.heading.flatMap { Fuzzy.score(query, in: $0) }
                if let best = [byName, byPath, byHeading].compactMap({ $0 }).max() {
                    scored.append((.file(workspace, file), best))
                }
            }
        }
        let sorted = scored.sorted { $0.1 > $1.1 }
        if query.isEmpty { return sorted.prefix(40).map(\.0) }
        // Only names close to the best match: loose subsequence matches
        // would push the text results out of sight.
        guard let best = sorted.first?.1 else { return [] }
        return sorted.prefix { $0.1 >= best - best / 4 }.prefix(8).map(\.0)
    }

    /// Runs off the main thread: file text comes from the index, which reads
    /// a file again only when it has changed.
    private func searchText() async {
        guard let text = textQuery else {
            textHits = []
            isSearchingText = false
            return
        }
        isSearchingText = true
        try? await Task.sleep(for: .milliseconds(110))
        guard !Task.isCancelled else { return }
        let entries = model.textIndexEntries
        let index = model.textIndex
        let hits = await Task.detached(priority: .userInitiated) {
            let documents = await index.documents(entries)
            return TextSearch.search(text, in: documents)
        }.value
        guard !Task.isCancelled else { return }
        var found: [Result] = []
        for hit in hits {
            let parts = hit.key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, let workspace = model.workspaces.first(where: { $0.id.uuidString == parts[0] }),
                  let file = workspace.file(parts[1]) else { continue }
            found.append(.text(workspace, file, hit))
        }
        textHits = found
        isSearchingText = false
    }

    /// An estimate of the list's height, so the palette fits its results.
    private func height(of results: [Result]) -> CGFloat {
        let rows = results.reduce(CGFloat(0)) { total, result in
            switch result {
            case .heading: total + 34
            case .file: total + 49
            case let .text(_, _, hit): total + 40 + CGFloat(hit.snippets.count) * 18
            }
        }
        let label: CGFloat = !searchesText && results.contains(where: \.isText) && results.contains(where: { !$0.isText }) ? 26 : 0
        return min(420, rows + label + 12)
    }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: query.hasPrefix("#") ? "number" : (searchesText ? "text.magnifyingglass" : "magnifyingglass"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.ink3)
                    .frame(width: 18)
                TextField(searchesText ? "Search the text of every file" : (model.quickOpenOpensTab ? "Open in a new tab — type a file name" : "Go to file — type # for sections"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundStyle(palette.ink)
                    .focused($isFocused)
                    .onSubmit { choose(results) }
                    .onKeyPress(.return, phases: .down) { press in
                        // ⌘Return: a tab of its own.
                        guard press.modifiers.contains(.command) else { return .ignored }
                        choose(results, inNewTab: true)
                        return .handled
                    }
                    .onKeyPress(.downArrow) { move(1, count: results.count); return .handled }
                    .onKeyPress(.upArrow) { move(-1, count: results.count); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
                    .onKeyPress(.tab) {
                        // Tab switches between names and text.
                        model.quickOpenSearchesText.toggle()
                        selection = 0
                        return .handled
                    }
                if isSearchingText {
                    ProgressView().controlSize(.small)
                }
                Text(searchesText ? "Tab: names" : "Tab: text")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.ink3)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(palette.rule))
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            if !results.isEmpty {
                Rectangle().fill(palette.rule).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                if !searchesText, result.isText, index > 0, !results[index - 1].isText {
                                    Text("IN THE TEXT")
                                        .font(.system(size: 10, weight: .semibold))
                                        .tracking(0.7)
                                        .foregroundStyle(palette.ink3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .padding(.top, 8)
                                        .padding(.bottom, 2)
                                }
                                row(result, isSelected: index == selection)
                                    .id(index)
                                    .onTapGesture {
                                        selection = index
                                        choose(results)
                                    }
                            }
                        }
                        .padding(6)
                    }
                    // A ScrollView takes all the height it is offered; size it to its rows.
                    .frame(height: height(of: results))
                    .onChange(of: selection) { _, index in proxy.scrollTo(index) }
                }
            } else if !query.isEmpty, !isSearchingText {
                Rectangle().fill(palette.rule).frame(height: 1)
                Text("Nothing matches")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.ink3)
                    .padding(18)
            }
        }
        .frame(width: 560)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.paper)
                .shadow(color: .black.opacity(palette.theme.isDark ? 0.5 : 0.18), radius: 30, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.rule, lineWidth: 1)
        )
        .onAppear {
            isFocused = true
            selection = 0
            model.quickOpenSeed = ""
        }
        // However the palette goes (Escape, a click outside), ⌘T's intent goes with it.
        .onDisappear { model.quickOpenOpensTab = false }
        .onChange(of: query) { _, _ in selection = 0 }
        .task(id: "\(searchesText)|\(query)") { await searchText() }
    }

    @ViewBuilder
    private func row(_ result: Result, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            switch result {
            case let .file(workspace, file):
                StatusDot(status: workspace.status(of: file)).frame(width: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.settings.displayName(for: file))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(palette.ink)
                    Text(model.workspaces.count > 1 ? "\(workspace.name)/\(file.relativePath)" : file.relativePath)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.ink3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(AppModel.relativeDate(file.modified))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink3)
            case let .text(workspace, file, hit):
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.settings.displayName(for: file))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Text(model.workspaces.count > 1 ? "\(workspace.name)/\(file.relativePath)" : file.relativePath)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.ink3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    ForEach(Array(hit.snippets.enumerated()), id: \.offset) { _, snippet in
                        snippetText(snippet)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            case let .heading(item):
                Text(item.title)
                    .font(.system(size: 13.5, weight: item.level <= 2 ? .medium : .regular))
                    .foregroundStyle(palette.ink)
                    .padding(.leading, CGFloat(max(0, item.level - 1)) * 14)
                Spacer()
                Text("H\(item.level)")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.ink3)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? palette.selection : .clear)
        )
        .contentShape(Rectangle())
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selection = min(count - 1, max(0, selection + delta))
    }

    private func close() {
        model.isQuickOpenVisible = false
        model.quickOpenOpensTab = false
    }

    /// Opens the chosen result: in a new tab after ⌘T or with ⌘Return.
    private func choose(_ results: [Result], inNewTab: Bool = false) {
        guard results.indices.contains(selection) else { return }
        let newTab = inNewTab || model.quickOpenOpensTab
        close()
        switch results[selection] {
        case let .file(workspace, file):
            if newTab { model.openInNewTab(file, in: workspace) } else { model.open(file, in: workspace) }
        case let .heading(item): model.scrollToHeading(item.id)
        case let .text(workspace, file, hit): model.openSearchResult(file, in: workspace, term: hit.findTerm, inNewTab: newTab)
        }
    }

    /// A line with the query's words in the ink, the rest a step quieter.
    private func snippetText(_ snippet: TextSearch.Snippet) -> Text {
        var line = AttributedString()
        for part in snippet.parts {
            var run = AttributedString(part.text)
            run.foregroundColor = part.isMatch ? palette.ink : palette.ink2
            if part.isMatch { run.font = .system(size: 12, weight: .semibold) }
            line += run
        }
        return Text(line)
    }
}
