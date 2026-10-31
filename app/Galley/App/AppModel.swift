import AppKit
import Observation
import SwiftUI

/// The document on the page.
struct OpenDocument {
    let workspaceID: UUID
    let file: DocumentFile
    var source: String
    var rendered: RenderedDocument
    var changes: DocumentChanges
    var status: ReadStatus
    var openedAt: Date
    var anchor: ScrollAnchor?
    var reachedEnd = false
    var folded: Set<String>

    var id: String { "\(workspaceID.uuidString)/\(file.id)" }
}

/// Panels, from the page outwards. Each level adds a column to the left.
enum PanelLevel: Int, CaseIterable, Comparable {
    case page = 1, outline, files, workspaces

    static func < (a: PanelLevel, b: PanelLevel) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .page: "Page Only"
        case .outline: "Outline"
        case .files: "Files"
        case .workspaces: "Workspaces"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    // MARK: State

    private(set) var workspaces: [Workspace] = []
    private(set) var selectedWorkspaceID: UUID?
    private(set) var current: OpenDocument?
    private(set) var currentHeading: String?

    var level: PanelLevel = .files
    /// -1…1 while a horizontal swipe is in flight: positive reveals the next
    /// column, negative hides the outermost one.
    var swipeProgress: Double = 0

    var isFindVisible = false
    /// Bumped by ⌘F to refocus the field when the bar is already open.
    var findFocusRequest = 0
    var findQuery = ""
    private(set) var findResult: (count: Int, index: Int) = (0, -1)

    var colorScheme: ColorScheme = .light {
        didSet { if oldValue != colorScheme { configureReader() } }
    }

    let settings = ReaderSettings.shared
    let reader = ReaderController()
    @ObservationIgnored private let library = Library()
    @ObservationIgnored private var lastPanelLevel: PanelLevel = .files
    @ObservationIgnored private var pendingRestore: String?
    @ObservationIgnored private var readerAtBottom = false

    var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == selectedWorkspaceID }
    }

    var theme: Theme {
        settings.theme(isDark: isDark)
    }

    var isDark: Bool {
        switch settings.appearance {
        case .system: colorScheme == .dark
        case .light: false
        case .dark: true
        }
    }

    var palette: Palette { Palette(theme: theme) }

    // MARK: Lifecycle

    init() {
        let state = library.state
        level = PanelLevel(rawValue: state.level) ?? .files
        lastPanelLevel = PanelLevel(rawValue: state.lastPanelLevel) ?? .files
        for record in state.workspaces {
            attach(Workspace(record: record, library: library), baseline: false)
        }
        selectedWorkspaceID = state.selectedWorkspace ?? workspaces.first?.id
        pendingRestore = selectedWorkspace?.record?.selectedFile

        reader.onEvent = { [weak self] event in self?.handle(event) }
        reader.schemeHandler.allowsFile = { [weak self] url in
            MainActor.assumeIsolated { self?.workspaces.contains { $0.contains(url) } ?? false }
        }
        reader.webView.extraMenuItems = { [weak self] in self?.contextMenuItems() ?? [] }
        configureReader()
        observeSettings()

        #if DEBUG
        // `-GalleyOpen <folder>` adds a workspace without the open panel, for
        // development and the screenshot script.
        if let path = UserDefaults.standard.string(forKey: "GalleyOpen") {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            if let existing = workspaces.first(where: { $0.root.standardizedFileURL == url.standardizedFileURL }) {
                selectWorkspace(existing.id)
            } else {
                addWorkspace(url)
            }
        }
        #endif
    }

    private func attach(_ workspace: Workspace, baseline: Bool) {
        workspace.onContentChange = { [weak self, weak workspace] paths in
            guard let self, let workspace else { return }
            self.contentChanged(in: workspace, paths: paths)
        }
        workspace.onRescan = { [weak self, weak workspace] in
            guard let self, let workspace else { return }
            self.workspaceRescanned(workspace)
        }
        workspaces.append(workspace)
        workspace.start()
        if baseline { workspace.rescan(baseline: true) }
    }

    /// Saves everything; called when the app is about to quit.
    func prepareToQuit() {
        leaveCurrent()
        library.flush()
    }

    /// Saves the reading position without marking anything read.
    func saveState() {
        guard let current, let workspace = currentWorkspace else { return }
        library.updateWorkspace(workspace.id) { record in
            record.files[current.file.id, default: FileRecord()].scroll = current.anchor
            record.files[current.file.id, default: FileRecord()].folded = current.folded.isEmpty ? nil : Array(current.folded)
        }
        library.flush()
    }

    func toggleFolder(_ id: String, in workspace: Workspace) {
        library.updateWorkspace(workspace.id) { record in
            if let index = record.collapsedFolders.firstIndex(of: id) {
                record.collapsedFolders.remove(at: index)
            } else {
                record.collapsedFolders.append(id)
            }
        }
        // `record` is read through the library, which is not observable.
        workspace.touch()
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.appearance; _ = settings.lightTheme; _ = settings.darkTheme
            _ = settings.font; _ = settings.fontSize; _ = settings.lineSpacing; _ = settings.lineWidth
            _ = settings.showChanges
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.configureReader()
                self?.observeSettings()
            }
        }
        withObservationTracking {
            _ = settings.nameStyle; _ = settings.continueOrder
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshPage(transition: "none", keepPosition: true)
                self?.observeSettings()
            }
        }
    }

    func configureReader() {
        let theme = theme
        reader.configure(ReaderConfiguration(
            vars: theme.cssVariables,
            font: settings.font.css,
            size: settings.fontSize,
            leading: settings.lineSpacing.value + settings.font.leadingAdjustment,
            measure: settings.lineWidth.ems,
            top: 58,
            dark: theme.isDark,
            showChanges: settings.showChanges,
            lang: "en"
        ))
    }

    // MARK: Workspaces

    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Open"
        panel.message = "Choose a folder your agents write Markdown into."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addWorkspace(url) }
    }

    func addWorkspace(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        let folder = isDirectory.boolValue ? url : url.deletingLastPathComponent()
        if let existing = workspaces.first(where: { $0.root.standardizedFileURL == folder.standardizedFileURL }) {
            selectWorkspace(existing.id)
            if !isDirectory.boolValue { pendingRestore = String(url.path.dropFirst(existing.root.path.count + 1)) }
            return
        }
        let bookmark = try? folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
        let record = WorkspaceRecord(id: UUID(), bookmark: bookmark, path: folder.path, addedAt: Date())
        library.update { $0.workspaces.append(record) }
        let workspace = Workspace(record: record, library: library)
        attach(workspace, baseline: true)
        if !isDirectory.boolValue {
            pendingRestore = String(url.path.dropFirst(folder.path.count + 1))
        }
        selectWorkspace(workspace.id)
        if level < .files { setLevel(.files) }
    }

    func removeWorkspace(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        if current?.workspaceID == id {
            leaveCurrent()
            current = nil
        }
        workspace.close()
        workspaces.removeAll { $0.id == id }
        library.update { state in
            state.workspaces.removeAll { $0.id == id }
            if state.selectedWorkspace == id { state.selectedWorkspace = nil }
        }
        library.removeSnapshots(workspace: id)
        if selectedWorkspaceID == id {
            selectedWorkspaceID = nil
            if let first = workspaces.first { selectWorkspace(first.id) }
        }
    }

    func selectWorkspace(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        selectedWorkspaceID = id
        library.update { $0.selectedWorkspace = id }
        if current?.workspaceID == id { return }
        let remembered = pendingRestore ?? workspace.record?.selectedFile
        pendingRestore = nil
        if workspace.hasScanned {
            if let path = remembered, let file = workspace.file(path) {
                open(file, transition: "none")
            } else if let first = workspace.files.first {
                open(first, transition: "none")
            }
        } else {
            pendingRestore = remembered ?? ""
        }
    }

    private func workspaceRescanned(_ workspace: Workspace) {
        guard workspace.id == selectedWorkspaceID else { return }
        if let path = pendingRestore {
            pendingRestore = nil
            if let file = workspace.file(path) ?? workspace.files.first { open(file, transition: "none") }
            return
        }
        if current == nil, let first = workspace.files.first {
            open(first, transition: "none")
            return
        }
        // The open file was deleted or renamed: keep it on screen, but the
        // "next" footer must follow the new tree.
        refreshPage(transition: "none", keepPosition: true)
    }

    private func contentChanged(in workspace: Workspace, paths: Set<String>) {
        guard let current, current.workspaceID == workspace.id, paths.contains(current.file.id),
              let file = workspace.file(current.file.id),
              let source = WorkspaceScanner.read(file.url), source != current.source else { return }
        load(file, in: workspace, source: source, transition: nil)
    }

    // MARK: Opening

    var currentWorkspace: Workspace? {
        guard let current else { return nil }
        return workspaces.first { $0.id == current.workspaceID }
    }

    func open(_ file: DocumentFile, transition: String = "none") {
        guard let workspace = selectedWorkspace ?? workspaces.first(where: { $0.file(file.id) != nil }) else { return }
        if current?.file.id == file.id, current?.workspaceID == workspace.id { return }
        guard let source = WorkspaceScanner.read(file.url) else { return }
        leaveCurrent()
        load(file, in: workspace, source: source, transition: transition)
        library.updateWorkspace(workspace.id) { $0.selectedFile = file.id }
    }

    /// Renders `source` and shows it. A nil transition means the same file
    /// changed on disk: the page updates in place, keeping the reader's spot.
    private func load(_ file: DocumentFile, in workspace: Workspace, source: String, transition: String?) {
        let renderer = MarkdownRenderer(baseURL: file.url.deletingLastPathComponent())
        let rendered = renderer.render(source)
        let record = workspace.record?.files[file.id]
        let status: ReadStatus = record?.readHash == nil || record?.markedUnread == true
            ? .unread
            : (record?.readHash == WorkspaceScanner.hash(source) ? .read : .changed)

        var changes = DocumentChanges.none
        if record?.readHash != nil, record?.readHash != WorkspaceScanner.hash(source),
           let old = library.snapshot(workspace: workspace.id, path: file.id) {
            let oldRendered = MarkdownRenderer(baseURL: file.url.deletingLastPathComponent()).render(old)
            changes = BlockDiff.changes(from: oldRendered.units, to: rendered.units)
        }

        let isUpdate = transition == nil && current?.file.id == file.id
        let anchor: ScrollAnchor?
        if isUpdate {
            anchor = current?.anchor
        } else if status == .changed, let first = changes.units.keys.min() {
            // Coming back to a changed file: start at the first change.
            anchor = ScrollAnchor(unit: max(0, first), offset: 0)
        } else {
            anchor = record?.scroll
        }

        current = OpenDocument(
            workspaceID: workspace.id,
            file: workspace.file(file.id) ?? file,
            source: source,
            rendered: rendered,
            changes: changes,
            status: status,
            openedAt: isUpdate ? (current?.openedAt ?? Date()) : Date(),
            anchor: anchor,
            reachedEnd: isUpdate ? (current?.reachedEnd ?? false) : false,
            folded: isUpdate ? (current?.folded ?? []) : Set(record?.folded ?? [])
        )
        if !isUpdate {
            currentHeading = nil
            readerAtBottom = false
        }
        if isFindVisible, !isUpdate { findResult = (0, -1) }
        refreshPage(transition: transition, keepPosition: isUpdate)
    }

    /// Re-sends the current page, e.g. after a rescan or a settings change.
    private func refreshPage(transition: String?, keepPosition: Bool) {
        guard let current, let workspace = currentWorkspace else { return }
        let payload = makePayload(current, in: workspace, transition: transition ?? "none")
        if keepPosition || transition == nil {
            reader.update(payload)
        } else {
            reader.show(payload)
        }
        if isFindVisible, !findQuery.isEmpty, transition != nil, !keepPosition {
            Task { await runFind(direction: 0) }
        }
    }

    private func makePayload(_ document: OpenDocument, in workspace: Workspace, transition: String) -> PagePayload {
        var meta: [String] = []
        let folder = document.file.folder
        meta.append(folder.isEmpty ? workspace.name : ([workspace.name] + folder.split(separator: "/").map(String.init)).joined(separator: " / "))
        meta.append(Self.relativeDate(document.file.modified))
        meta.append("\(document.rendered.readingMinutes) min read")

        var badge: String?
        var badgeKind: String?
        switch document.status {
        case .unread:
            let record = workspace.record?.files[document.file.id]
            badge = record?.markedUnread == true ? "Unread" : "New"
            badgeKind = "new"
        case .changed:
            badge = Self.changeSummary(document.changes)
        case .read:
            break
        }

        var changes: [String: PagePayload.Change] = [:]
        for (index, change) in document.changes.units {
            switch change {
            case .added: changes[String(index)] = .init(kind: "added")
            case .modified(let old): changes[String(index)] = .init(kind: "modified", old: old)
            }
        }

        let next = nextFile(after: document.file, in: workspace)
        var nextPayload: PagePayload.Next?
        if let next {
            let status = workspace.status(of: next)
            let why: String? = switch (settings.continueOrder, status) {
            case (_, .changed): "Changed since you read it"
            case (_, .unread): "Not read yet"
            default: nil
            }
            nextPayload = .init(title: settings.displayName(for: next), label: "Next", why: why)
        }

        return PagePayload(
            id: document.id,
            html: document.rendered.html,
            header: .init(
                meta: meta,
                badge: badge,
                badgeKind: badgeKind,
                title: document.rendered.title == nil ? settings.displayName(for: document.file) : nil
            ),
            changes: changes,
            folded: Array(document.folded),
            scroll: document.anchor,
            next: nextPayload,
            endLabel: workspace.files.count > 1 ? "End of \(workspace.name)" : nil,
            transition: transition
        )
    }

    static func changeSummary(_ changes: DocumentChanges) -> String {
        var parts: [String] = []
        if changes.added > 0 { parts.append("\(changes.added) new") }
        if changes.modified > 0 { parts.append("\(changes.modified) edited") }
        if changes.removed > 0 { parts.append("\(changes.removed) removed") }
        return parts.isEmpty ? "Changed" : "Changed · " + parts.joined(separator: ", ")
    }

    static func relativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 45 { return "Just now" }
        if interval < 3600 * 24 * 6 {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: date, relativeTo: Date()).capitalizedFirst
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Records the open document as read if the reader actually looked at it,
    /// and saves where they were.
    private func leaveCurrent() {
        guard let current, let workspace = currentWorkspace else { return }
        let lookedAtIt = current.reachedEnd || Date().timeIntervalSince(current.openedAt) > 2.5
        let record = workspace.record?.files[current.file.id]
        if lookedAtIt, record?.markedUnread != true || Date().timeIntervalSince(current.openedAt) > 2.5 {
            workspace.markRead(current.file.id, text: current.source)
        }
        library.updateWorkspace(workspace.id) { record in
            record.files[current.file.id, default: FileRecord()].scroll = current.anchor
            record.files[current.file.id, default: FileRecord()].folded = current.folded.isEmpty ? nil : Array(current.folded)
        }
    }

    // MARK: Order

    func nextFile(after file: DocumentFile, in workspace: Workspace) -> DocumentFile? {
        let files = workspace.files
        guard let index = files.firstIndex(where: { $0.id == file.id }) else { return files.first }
        if settings.continueOrder == .unread {
            let rotated = files[(index + 1)...] + files[..<index]
            if let unread = rotated.first(where: { workspace.status(of: $0) != .read }) { return unread }
        }
        return index + 1 < files.count ? files[index + 1] : nil
    }

    func previousFile(before file: DocumentFile, in workspace: Workspace) -> DocumentFile? {
        let files = workspace.files
        guard let index = files.firstIndex(where: { $0.id == file.id }), index > 0 else { return nil }
        return files[index - 1]
    }

    func goToNext() {
        guard let current, let workspace = currentWorkspace,
              let next = nextFile(after: current.file, in: workspace) else { NSSound.beep(); return }
        if self.current != nil { self.current?.reachedEnd = true }
        open(next, transition: "up")
    }

    func goToPrevious() {
        guard let current, let workspace = currentWorkspace,
              let previous = previousFile(before: current.file, in: workspace) else { NSSound.beep(); return }
        open(previous, transition: "down")
    }

    func goToNextUnread() {
        guard let workspace = selectedWorkspace else { return }
        let files = workspace.files
        let start = current.flatMap { c in files.firstIndex { $0.id == c.file.id } } ?? -1
        let rotated = files[(start + 1)...] + files[..<max(0, start + 1)]
        guard let target = rotated.first(where: { workspace.status(of: $0) != .read && $0.id != current?.file.id }) else {
            NSSound.beep()
            return
        }
        open(target, transition: "up")
    }

    // MARK: Read state

    func toggleRead() {
        guard let current, let workspace = currentWorkspace else { return }
        if workspace.status(of: current.file) == .read {
            workspace.markUnread(current.file.id)
            // Stay on the page without it being re-marked read on leave.
            self.current?.openedAt = .distantFuture
            self.current?.reachedEnd = false
        } else {
            workspace.markRead(current.file.id, text: current.source)
        }
        if var document = self.current {
            document.status = workspace.status(of: document.file)
            self.current = document
        }
        refreshPage(transition: "none", keepPosition: true)
    }

    func toggleRead(_ file: DocumentFile, in workspace: Workspace) {
        if file.id == current?.file.id, workspace.id == current?.workspaceID { toggleRead(); return }
        if workspace.status(of: file) == .read {
            workspace.markUnread(file.id)
        } else if let text = WorkspaceScanner.read(file.url) {
            workspace.markRead(file.id, text: text)
        }
    }

    func markAllRead() {
        guard let workspace = selectedWorkspace else { return }
        workspace.markAllRead()
        if let current, current.workspaceID == workspace.id {
            self.current?.status = .read
            self.current?.changes = .none
            refreshPage(transition: "none", keepPosition: true)
        }
    }

    // MARK: Panels

    func setLevel(_ newLevel: PanelLevel, animated: Bool = true) {
        let apply = {
            self.level = newLevel
            self.swipeProgress = 0
        }
        if animated { withAnimation(.galleyPanel) { apply() } } else { apply() }
        if newLevel != .page { lastPanelLevel = newLevel }
        library.update {
            $0.level = newLevel.rawValue
            $0.lastPanelLevel = self.lastPanelLevel.rawValue
        }
    }

    func stepLevel(_ delta: Int) {
        let target = PanelLevel(rawValue: min(4, max(1, level.rawValue + delta))) ?? level
        if target == level { NSSound.beep(); return }
        setLevel(target)
    }

    /// The toolbar button: page alone, or back to the panels you had.
    func togglePanels() {
        setLevel(level == .page ? (lastPanelLevel == .page ? .files : lastPanelLevel) : .page)
    }

    // MARK: Reader events

    private func handle(_ event: ReaderEvent) {
        switch event {
        case .ready:
            configureReader()
            refreshPage(transition: "none", keepPosition: false)
        case .scroll(let report):
            guard report.document == current?.id else { return }
            current?.anchor = report.anchor
            if report.reachedEnd { current?.reachedEnd = true }
            readerAtBottom = report.atBottom
            if currentHeading != report.anchor.heading { currentHeading = report.anchor.heading }
        case .link(let href):
            followLink(href)
        case .next:
            goToNext()
        case .fold(let id, let folded):
            if folded { current?.folded.insert(id) } else { current?.folded.remove(id) }
        case .folds(let ids):
            current?.folded = Set(ids)
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    var isReaderAtBottom: Bool { readerAtBottom }

    func scrollToHeading(_ id: String) {
        reader.scrollToHeading(id)
    }

    func setFolded(_ id: String, _ folded: Bool) {
        if folded { current?.folded.insert(id) } else { current?.folded.remove(id) }
        reader.fold(id, folded: folded)
    }

    func foldAll(_ folded: Bool) {
        reader.foldAll(folded)
    }

    func jumpToChange(_ direction: Int) {
        Task {
            if await !reader.jumpToChange(direction) { NSSound.beep() }
        }
    }

    // MARK: Links

    private func followLink(_ href: String) {
        guard let current, let workspace = currentWorkspace else { return }
        if href.hasPrefix("wiki:") {
            let target = String(href.dropFirst(5))
            let parts = target.split(separator: "#", maxSplits: 1).map(String.init)
            let name = parts[0].lowercased()
            let match = workspace.files.first {
                ($0.filename as NSString).deletingPathExtension.lowercased() == name
                    || $0.filename.lowercased() == name
                    || $0.relativePath.lowercased() == name
                    || ($0.relativePath as NSString).deletingPathExtension.lowercased() == name
                    || $0.heading?.lowercased() == name
            }
            guard let match else { NSSound.beep(); return }
            open(match, transition: "none")
            if parts.count > 1 { scrollAfterOpen(to: Slug.make(parts[1])) }
            return
        }
        guard let url = URL(string: href) ?? URL(string: href.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "") else { return }
        if let scheme = url.scheme, scheme != "file" {
            NSWorkspace.shared.open(url)
            return
        }
        let path = (url.path.isEmpty ? href : url.path).removingPercentEncoding ?? url.path
        let target = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : current.file.url.deletingLastPathComponent().appendingPathComponent(path)
        let standardized = target.standardizedFileURL
        if WorkspaceScanner.isMarkdown(standardized), workspace.contains(standardized) {
            let relative = String(standardized.path.dropFirst(workspace.root.standardizedFileURL.path.count + 1))
            if let file = workspace.file(relative) {
                open(file, transition: "none")
                if let fragment = url.fragment { scrollAfterOpen(to: fragment) }
                return
            }
        }
        if FileManager.default.fileExists(atPath: standardized.path) {
            NSWorkspace.shared.open(standardized)
        } else {
            NSSound.beep()
        }
    }

    private func scrollAfterOpen(to heading: String) {
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            reader.scrollToHeading(heading)
        }
    }

    // MARK: Files

    func revealInFinder(_ file: DocumentFile? = nil) {
        guard let url = file?.url ?? current?.file.url ?? selectedWorkspace?.root else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openInEditor(_ file: DocumentFile? = nil) {
        guard let url = file?.url ?? current?.file.url else { return }
        NSWorkspace.shared.open(url)
    }

    func copyPath(_ file: DocumentFile? = nil) {
        guard let url = file?.url ?? current?.file.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    private func contextMenuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if let heading = currentHeading {
            let copyLink = MenuAction(title: "Copy Link to Section") { [weak self] in
                guard let self, let file = self.current?.file else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(file.relativePath)#\(heading)", forType: .string)
            }
            items.append(copyLink.item)
        }
        items.append(MenuAction(title: "Reveal in Finder") { [weak self] in self?.revealInFinder() }.item)
        return items
    }

    // MARK: Find

    func showFind() {
        if !isFindVisible { isFindVisible = true }
    }

    func hideFind() {
        isFindVisible = false
        findResult = (0, -1)
        reader.endFind()
    }

    func runFind(direction: Int) async {
        let query = findQuery
        guard !query.isEmpty else {
            reader.endFind()
            findResult = (0, -1)
            return
        }
        let result = await reader.find(query, direction: direction)
        if query == findQuery { findResult = result }
    }
}

extension Animation {
    static let galleyPanel = Animation.spring(response: 0.38, dampingFraction: 0.88)
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// An `NSMenuItem` that runs a closure.
final class MenuAction: NSObject {
    let item: NSMenuItem
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        super.init()
        item.target = self
        item.action = #selector(run)
        item.representedObject = self
    }

    @objc private func run() { handler() }
}
