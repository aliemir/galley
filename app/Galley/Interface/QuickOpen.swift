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
        // "#" and ">" are modes, not part of the query: the icon shows them.
        let scope = Scope(prefix: seed.first)
        _scope = State(initialValue: scope)
        _query = State(initialValue: scope == .files ? seed : String(seed.dropFirst()))
    }

    /// What the palette goes through: file names (and, with Tab, their
    /// text), the open document's sections, or the app's actions.
    private enum Scope {
        case files, sections, actions

        init(prefix: Character?) {
            switch prefix {
            case "#": self = .sections
            case ">": self = .actions
            default: self = .files
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.openSettings) private var openSettings
    /// Starts with the seed ("#" for sections) rather than being set after
    /// appearing: a change during the palette's fade-in left the list stale.
    @State private var query: String
    /// Typing "#" or ">" at the start turns sections or actions on;
    /// Backspace in an empty field, or Tab, goes back to files.
    @State private var scope: Scope
    @State private var selection = 0
    @State private var textHits: [Result] = []
    @State private var isSearchingText = false
    /// The rows' measured height, which sizes the list to fit them.
    @State private var listHeight: CGFloat = 0
    @FocusState private var isFocused: Bool

    private enum Result: Identifiable {
        case file(Workspace, DocumentFile)
        case heading(OutlineItem)
        /// A file whose text has every word of the query.
        case text(Workspace, DocumentFile, TextSearch.Hit)
        case action(PaletteAction)

        var id: String {
            switch self {
            case let .file(workspace, file): "f/\(workspace.id)/\(file.id)"
            case let .heading(item): "h/\(item.id)"
            case let .text(workspace, file, _): "t/\(workspace.id)/\(file.id)"
            case let .action(action): "a/\(action.id)"
            }
        }

        var isText: Bool { if case .text = self { true } else { false } }
    }

    private var searchesText: Bool { model.quickOpenSearchesText }

    private var placeholder: String {
        switch scope {
        case .sections:
            return model.current.map { "Go to a section of “\(model.settings.displayName(for: $0.file))”" } ?? "Go to a section"
        case .actions:
            return "Run an action"
        case .files:
            if searchesText { return "Search the text of every file" }
            return model.quickOpenOpensTab ? "Open in a new tab — type a file name" : "Go to file — # for sections, > for actions"
        }
    }

    /// Text is searched from three characters in the file palette (names
    /// come first), from two when searching text alone.
    private var textQuery: String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard scope == .files, trimmed.count >= (searchesText ? 2 : 3) else { return nil }
        return trimmed
    }

    /// ⌘K finds files by name; only when no name matches does it show
    /// what is in the text instead, and says so. ⇧⌘F (or Tab) is text only.
    private var results: [Result] {
        if scope == .actions { return actionResults }
        if searchesText, scope == .files { return textHits }
        let names = nameResults
        guard names.isEmpty, scope == .files, textQuery != nil else { return names }
        return textHits
    }

    /// Everything the menus and the top bar do, plus the palette's own
    /// modes, best match first.
    private var actionResults: [Result] {
        let actions = paletteModes + model.paletteActions { pane in
            if let pane { UserDefaults.standard.set(pane, forKey: "settingsTab") }
            openSettings()
        }
        let text = query.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return actions.filter { !$0.onlyWhenSearched }.map(Result.action) }
        return actions
            .compactMap { action in
                let byTitle = Fuzzy.score(text, in: action.title).map { $0 + 200 }
                let byGroup = Fuzzy.score(text, in: action.group + " " + action.title)
                return [byTitle, byGroup].compactMap { $0 }.max().map { (action, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .prefix(30)
            .map { Result.action($0.0) }
    }

    /// Actions that switch what the palette goes through, so it stays open.
    private var paletteModes: [PaletteAction] {
        var modes: [PaletteAction] = []
        if !model.workspaces.isEmpty {
            modes.append(PaletteAction(id: "mode/files", title: "Go to File", group: "File", icon: "magnifyingglass", shortcut: .goToFile, staysOpen: true) {
                switchScope(to: .files, text: false)
            })
            modes.append(PaletteAction(id: "mode/text", title: "Search All Files", group: "File", icon: "text.magnifyingglass", shortcut: .searchAllFiles, staysOpen: true) {
                switchScope(to: .files, text: true)
            })
            modes.append(PaletteAction(id: "mode/tab", title: "New Tab", group: "File", icon: "plus.square.on.square", shortcut: .newTab, staysOpen: true) {
                model.quickOpenOpensTab = true
                switchScope(to: .files, text: false)
            })
        }
        if model.current != nil {
            modes.append(PaletteAction(id: "mode/sections", title: "Go to Section", group: "File", icon: "number", shortcut: .goToSection, staysOpen: true) {
                switchScope(to: .sections, text: false)
            })
        }
        return modes
    }

    private func switchScope(to newScope: Scope, text: Bool) {
        scope = newScope
        model.quickOpenSearchesText = text
        query = ""
        selection = 0
    }

    private var nameResults: [Result] {
        if scope == .sections {
            let text = query
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
        // Only names close to the best match: loose subsequence matches are
        // noise, and would keep the text fallback from ever showing.
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

    /// An estimate of the list's height, for the moment before the rows
    /// have been measured.
    private func height(of results: [Result]) -> CGFloat {
        let rows = results.reduce(CGFloat(0)) { total, result in
            switch result {
            case .heading: total + 34
            case .file: total + 49
            case let .text(_, _, hit): total + 40 + CGFloat(hit.snippets.count) * 18
            case .action: total + 34
            }
        }
        let label: CGFloat = !searchesText && results.first?.isText == true ? 26 : 0
        return min(420, rows + label + 12)
    }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: scopeIcon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.ink3)
                    .frame(width: 18)
                TextField(placeholder, text: $query)
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
                        // Tab switches between names and text; from sections
                        // (a corner of the name search) it goes back to names.
                        if scope != .files { scope = .files } else {
                            model.quickOpenSearchesText.toggle()
                        }
                        selection = 0
                        return .handled
                    }
                    .onKeyPress(phases: .down) { press in
                        // Backspace in an empty field leaves sections. Matched by
                        // its characters: the Mac's Backspace sends DEL (U+7F),
                        // which `KeyEquivalent.delete` (U+8) never matched.
                        guard scope != .files, query.isEmpty, ["\u{7F}", "\u{8}"].contains(press.characters) else { return .ignored }
                        scope = .files
                        selection = 0
                        return .handled
                    }
                if isSearchingText {
                    ProgressView().controlSize(.small)
                }
                // Where Tab goes: the key as a keycap, then the other mode.
                HStack(spacing: 5) {
                    Text("⇥")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(minWidth: 18, minHeight: 16)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(palette.ink.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(palette.rule))
                    Text(searchesText || scope != .files ? "Names" : "Text")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(palette.ink3)
                .help(searchesText || scope != .files ? "Tab: search file names" : "Tab: search the text of every file")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(searchesText || scope != .files ? "Tab searches file names" : "Tab searches the text")
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            if !results.isEmpty {
                Rectangle().fill(palette.rule).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        // Not lazy: at most a few dozen rows, and their real
                        // height is what sizes the list.
                        VStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                if !searchesText, result.isText, index == 0 {
                                    Text("NO FILE NAMES MATCH — IN THE TEXT")
                                        .font(.system(size: 10, weight: .semibold))
                                        .tracking(0.7)
                                        .foregroundStyle(palette.ink3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .padding(.top, 8)
                                        .padding(.bottom, 2)
                                }
                                row(result, isSelected: index == selection)
                                    // Known by the result alone: also keyed by position,
                                    // a text result swapped for a section in the same
                                    // place kept showing the old row.
                                    .id(result.id)
                                    .onTapGesture {
                                        selection = index
                                        choose(results)
                                    }
                            }
                        }
                        .padding(6)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                    }
                    // A ScrollView takes all the height it is offered; size it to its rows.
                    .frame(height: min(420, listHeight > 0 ? listHeight : height(of: results)))
                    .onChange(of: selection) { _, index in
                        if results.indices.contains(index) { proxy.scrollTo(results[index].id) }
                    }
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
        #if DEBUG
        // Where the palette is in the window, for the website's cut-outs.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.paletteFrame = $0 }
        #endif
        .onAppear {
            isFocused = true
            selection = 0
            model.quickOpenSeed = ""
        }
        // However the palette goes (Escape, a click outside), ⌘T's intent goes with it.
        .onDisappear { model.quickOpenOpensTab = false }
        .onChange(of: query) { _, value in
            selection = 0
            // "#" or ">" typed (or pasted) at the start switches to sections
            // or actions and leaves the field: the icon says it instead.
            let typed = Scope(prefix: value.first)
            if typed != .files {
                scope = typed
                model.quickOpenSearchesText = false
                query = String(value.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }
        .task(id: "\(searchesText)|\(scope)|\(query)") { await searchText() }
    }

    private var scopeIcon: String {
        switch scope {
        case .sections: "number"
        case .actions: "command"
        case .files: searchesText ? "text.magnifyingglass" : "magnifyingglass"
        }
    }

    @ViewBuilder
    private func row(_ result: Result, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            switch result {
            case let .file(workspace, file):
                StatusDot(status: workspace.status(of: file)).frame(width: 8)
                workspaceIcon(workspace)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.settings.displayName(for: file))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(palette.ink)
                    Text(location(of: file, in: workspace))
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
                // The icon beside the file name, not halfway down its lines.
                HStack(alignment: .top, spacing: 10) {
                    workspaceIcon(workspace)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(model.settings.displayName(for: file))
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(palette.ink)
                                .lineLimit(1)
                            Text(location(of: file, in: workspace))
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
                }
            case let .action(action):
                Image(systemName: action.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.ink3)
                    .frame(width: 18)
                Text(action.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Spacer()
                Text(action.group)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink3)
                if let key = action.shortcut.flatMap({ Shortcuts.shared[$0] }) {
                    Text(key.display)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.ink2)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 22, minHeight: 18)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(palette.ink.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(palette.rule))
                }
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

    /// Which workspace a result is in, when there is more than one: its
    /// icon, which also tells apart two workspaces with the same name.
    @ViewBuilder
    private func workspaceIcon(_ workspace: Workspace) -> some View {
        if model.workspaces.count > 1 {
            WorkspaceIcon(workspace: workspace, size: 18)
                .help(workspace.name)
        }
    }

    /// The file's path in its workspace; opened files show where they live.
    private func location(of file: DocumentFile, in workspace: Workspace) -> String {
        workspace.isOpenedFiles ? (file.relativePath as NSString).abbreviatingWithTildeInPath : file.relativePath
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
        if case let .action(action) = results[selection], action.staysOpen {
            action.run()
            return
        }
        let newTab = inNewTab || model.quickOpenOpensTab
        close()
        switch results[selection] {
        case let .file(workspace, file):
            if newTab { model.openInNewTab(file, in: workspace) } else { model.open(file, in: workspace) }
        case let .heading(item): model.scrollToHeading(item.id)
        case let .text(workspace, file, hit): model.openSearchResult(file, in: workspace, term: hit.findTerm, inNewTab: newTab)
        case let .action(action): action.run()
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
