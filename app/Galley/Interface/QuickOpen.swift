import SwiftUI

/// Subsequence matching with bonuses for word starts and runs, so "amp"
/// finds "Auth migration plan" and "rl" finds "rate limits".
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
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var isFocused: Bool

    private enum Result: Identifiable {
        case file(Workspace, DocumentFile)
        case heading(OutlineItem)

        var id: String {
            switch self {
            case let .file(workspace, file): "f/\(workspace.id)/\(file.id)"
            case let .heading(item): "h/\(item.id)"
            }
        }
    }

    private var results: [Result] {
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
        return scored.sorted { $0.1 > $1.1 }.prefix(40).map(\.0)
    }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: query.hasPrefix("#") ? "number" : "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.ink3)
                    .frame(width: 18)
                TextField("Go to file — type # for sections", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundStyle(palette.ink)
                    .focused($isFocused)
                    .onSubmit { choose(results) }
                    .onKeyPress(.downArrow) { move(1, count: results.count); return .handled }
                    .onKeyPress(.upArrow) { move(-1, count: results.count); return .handled }
                    .onKeyPress(.escape) { model.isQuickOpenVisible = false; return .handled }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            if !results.isEmpty {
                Rectangle().fill(palette.rule).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
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
                    .frame(height: min(372, CGFloat(results.count) * (query.hasPrefix("#") ? 34 : 49) + 12))
                    .onChange(of: selection) { _, index in proxy.scrollTo(index) }
                }
            } else if !query.isEmpty {
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
            query = model.quickOpenSeed
            model.quickOpenSeed = ""
        }
        .onChange(of: query) { _, _ in selection = 0 }
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

    private func choose(_ results: [Result]) {
        guard results.indices.contains(selection) else { return }
        model.isQuickOpenVisible = false
        switch results[selection] {
        case let .file(workspace, file): model.open(file, in: workspace)
        case let .heading(item): model.scrollToHeading(item.id)
        }
    }
}
