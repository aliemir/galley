import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

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
    var highlights: [Highlight] = []
    /// Highlights whose text is no longer in the document.
    var orphans: Set<String> = []

    var id: String { "\(workspaceID.uuidString)/\(file.id)" }
}

/// A tab in the page column: one document in one workspace. A file is open
/// in at most one tab, so going to a file that has a tab goes to that tab.
struct ReaderTab: Identifiable, Hashable {
    let id: UUID
    var workspaceID: UUID
    /// nil while the workspace has nothing to show yet.
    var fileID: String?

    init(id: UUID = UUID(), workspaceID: UUID, fileID: String?) {
        self.id = id
        self.workspaceID = workspaceID
        self.fileID = fileID
    }
}

/// A column beside the page. Each has a fixed place (`arrangement`); the
/// reader's order (Settings → Reading) is only the order swipes reveal them.
enum PanelColumn: String, CaseIterable, Identifiable {
    case outline, files, workspaces

    var id: String { rawValue }

    /// Where the columns sit, left to right, whatever the reveal order.
    static let arrangement: [PanelColumn] = [.workspaces, .files, .outline]

    /// The swipe order until the reader sets one: the file list first.
    static let defaultOrder: [PanelColumn] = [.files, .outline, .workspaces]

    /// The fixed levels before columns had an order: what a stored level
    /// number counted through.
    static let legacyOrder: [PanelColumn] = [.outline, .files, .workspaces]

    var shortcutAction: ShortcutAction {
        switch self {
        case .outline: .toggleContents
        case .files: .toggleFiles
        case .workspaces: .toggleWorkspaces
        }
    }

    var title: String {
        switch self {
        case .outline: "Contents"
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
    /// The page's tabs, left to right; the bar shows from two.
    private(set) var tabs: [ReaderTab] = []
    private(set) var activeTabID: UUID?

    /// The columns showing; each toggles on its own, swipes follow the order.
    private(set) var visibleColumns: Set<PanelColumn> = [.outline, .files]
    /// -1…1 while a horizontal swipe is in flight: positive reveals the next
    /// column, negative hides the outermost one.
    var swipeProgress: Double = 0

    var isQuickOpenVisible = false
    /// ⇧⌘F opens the palette searching file text only.
    var quickOpenSearchesText = false
    /// ⌘T opens the palette to choose what the new tab shows.
    var quickOpenOpensTab = false
    /// File text for the palette's search, kept between searches.
    @ObservationIgnored let textIndex = TextIndex()
    /// Text the palette opens with: "#" jumps straight to sections.
    var quickOpenSeed = ""
    var isFindVisible = false
    var isAppearanceVisible = false
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
    /// What the panel button brings back.
    @ObservationIgnored private var lastVisibleColumns: Set<PanelColumn> = [.outline, .files]
    @ObservationIgnored private var pendingRestore: String?
    @ObservationIgnored private var readerAtBottom = false
    @ObservationIgnored private var readerAtTop = true

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
        // Older libraries kept a depth into the default order as a 1-based level.
        let byLevel = { (level: Int) in Set(PanelColumn.legacyOrder.prefix(max(0, level - 1))) }
        visibleColumns = state.visibleColumns.map { Set($0.compactMap(PanelColumn.init(rawValue:))) } ?? byLevel(state.level)
        lastVisibleColumns = state.lastVisibleColumns.map { Set($0.compactMap(PanelColumn.init(rawValue:))) } ?? byLevel(state.lastPanelLevel)
        for record in state.workspaces {
            attach(Workspace(record: record, library: library), baseline: false)
        }
        tabs = (state.tabs ?? []).compactMap { record in
            workspaces.contains { $0.id == record.workspace } ? ReaderTab(workspaceID: record.workspace, fileID: record.file) : nil
        }
        let active = state.activeTab.flatMap { tabs.indices.contains($0) ? tabs[$0] : nil } ?? tabs.first
        activeTabID = active?.id
        selectedWorkspaceID = active?.workspaceID ?? state.selectedWorkspace ?? workspaces.first?.id
        pendingRestore = active?.fileID ?? selectedWorkspace?.record?.selectedFile

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

    /// Saves everything; called when the app is about to quit. Quitting
    /// mid-page keeps the page unread unless the reader reached its end.
    func prepareToQuit() {
        leaveCurrent(markingRead: current?.reachedEnd == true)
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
        observeAppearance()
        observeNaming()
    }

    /// Each tracker re-arms only itself; re-arming both from either would
    /// stack observers on every change.
    private func observeAppearance() {
        withObservationTracking {
            _ = settings.appearance; _ = settings.lightTheme; _ = settings.darkTheme
            _ = settings.font; _ = settings.fontSize; _ = settings.lineSpacing; _ = settings.lineWidth
            _ = settings.showChanges
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.configureReader()
                self?.observeAppearance()
            }
        }
    }

    private func observeNaming() {
        withObservationTracking {
            _ = settings.nameStyle; _ = settings.continueOrder
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshPage(transition: "none", keepPosition: true)
                self?.observeNaming()
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

    /// ⌘O: a folder to watch as a workspace, or Markdown files to read.
    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.folder, .markdown]
        panel.allowsMultipleSelection = true
        panel.prompt = "Open"
        panel.message = "Choose a folder your agents write Markdown into, or Markdown files to read."
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    /// Whatever was opened from outside — Finder, the Dock, ⌘O, a drop:
    /// folders become workspaces; a Markdown file inside a workspace opens
    /// there, and any other joins Opened Files. Each file gets a tab.
    func open(_ urls: [URL]) {
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                addWorkspace(url)
            } else if WorkspaceScanner.isMarkdown(url) {
                openFile(url)
            }
        }
    }

    private func openFile(_ url: URL) {
        if let workspace = workspaces.first(where: { !$0.isOpenedFiles && $0.contains(url) }) {
            let relative = String(url.standardizedFileURL.path.dropFirst(workspace.root.standardizedFileURL.path.count + 1))
            if workspace.hasScanned, let file = workspace.file(relative) {
                openInNewTab(file, in: workspace)
            } else {
                pendingRestore = relative
                selectWorkspace(workspace.id)
            }
            return
        }
        let group = openedFiles ?? makeOpenedFiles()
        guard let file = group.addDocument(url) else { NSSound.beep(); return }
        openInNewTab(file, in: group)
    }

    /// The workspace that holds files opened one at a time, if there is one.
    var openedFiles: Workspace? { workspaces.first { $0.isOpenedFiles } }

    private func makeOpenedFiles() -> Workspace {
        var record = WorkspaceRecord(id: UUID(), bookmark: nil, path: "", addedAt: Date())
        record.kind = "files"
        record.icon = WorkspaceIcon.Kind.symbol("doc.on.doc").stored
        library.update { $0.workspaces.append(record) }
        let workspace = Workspace(record: record, library: library)
        attach(workspace, baseline: false)
        return workspace
    }

    /// "Remove from Opened Files": the file leaves the list (and its tab
    /// closes); the file itself is untouched. An empty list goes away.
    func removeOpenedFile(_ file: DocumentFile) {
        guard let group = openedFiles else { return }
        let showing = current?.workspaceID == group.id && current?.file.id == file.id
        if let tab = tab(showing: file.id, in: group.id), tabs.count > 1 {
            closeTab(tab.id)
        }
        group.removeDocument(file.id)
        if group.files.isEmpty {
            removeWorkspace(group.id)
        } else if showing, current?.file.id == file.id, let next = group.files.first {
            // It was the only tab: the next opened file takes its place.
            open(next, in: group)
        }
    }

    /// A file opened on its own, promoted: its folder becomes a workspace
    /// (the sandbox needs the reader to grant it), and the file opens there.
    func addFolder(of file: DocumentFile) {
        let folder = file.url.deletingLastPathComponent()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = folder
        panel.prompt = "Add Workspace"
        panel.message = "Allow Galley to read “\(folder.lastPathComponent)” to watch every Markdown file in it."
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        let url = file.url
        removeOpenedFile(file)
        addWorkspace(chosen)
        if let workspace = workspaces.first(where: { !$0.isOpenedFiles && $0.contains(url) }) {
            pendingRestore = String(url.standardizedFileURL.path.dropFirst(workspace.root.standardizedFileURL.path.count + 1))
            if workspace.hasScanned, let path = pendingRestore, let file = workspace.file(path) {
                pendingRestore = nil
                open(file, in: workspace)
            }
        }
    }

    func addWorkspace(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        var folder = isDirectory.boolValue ? url : url.deletingLastPathComponent()

        // A dropped file is already inside a workspace: just open it.
        if !isDirectory.boolValue, let existing = workspaces.first(where: { !$0.isOpenedFiles && $0.contains(url) }) {
            let relative = String(url.standardizedFileURL.path.dropFirst(existing.root.standardizedFileURL.path.count + 1))
            if existing.hasScanned, let file = existing.file(relative) {
                open(file, in: existing)
            } else {
                pendingRestore = relative
                selectWorkspace(existing.id)
            }
            return
        }
        // The sandbox grants a dropped file, not its folder: ask for the folder.
        if !isDirectory.boolValue, (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) == nil {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.directoryURL = folder
            panel.prompt = "Allow"
            panel.message = "Galley reads whole folders. Allow it to read “\(folder.lastPathComponent)” to show “\(url.lastPathComponent)” with the files beside it."
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            folder = chosen
        }
        if let existing = workspaces.first(where: { !$0.isOpenedFiles && $0.root.standardizedFileURL == folder.standardizedFileURL }) {
            selectWorkspace(existing.id)
            return
        }
        let bookmark = try? folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
        let record = WorkspaceRecord(id: UUID(), bookmark: bookmark, path: folder.path, addedAt: Date())
        library.update { $0.workspaces.append(record) }
        let workspace = Workspace(record: record, library: library)
        attach(workspace, baseline: true)
        if !isDirectory.boolValue, workspace.contains(url) {
            pendingRestore = String(url.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count + 1))
        }
        selectWorkspace(workspace.id)
        reveal(.files)
    }

    /// Names and icons live in the library only; the folder is untouched.
    func setWorkspaceName(_ name: String?, for id: UUID) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        library.updateWorkspace(id) { $0.customName = trimmed?.isEmpty == false ? trimmed : nil }
        workspaces.first { $0.id == id }?.touch()
        refreshPage(transition: "none", keepPosition: true)
    }

    func setWorkspaceColor(_ name: String?, for id: UUID) {
        library.updateWorkspace(id) { $0.color = name }
        workspaces.first { $0.id == id }?.touch()
    }

    func setWorkspaceIcon(_ icon: WorkspaceIcon.Kind, for id: UUID) {
        library.updateWorkspace(id) { $0.icon = icon.stored }
        workspaces.first { $0.id == id }?.touch()
    }

    /// The workspace whose name-and-icon editor is open.
    var customizingWorkspace: UUID?

    /// The file type-to-select landed on in the Files column, before Return
    /// opens it; nil when the selection is simply the open file.
    var filesCursor: String?
    /// Bumped to move keyboard focus into the Files column.
    var filesFocusRequest = 0

    /// The workspace being dragged in the list, for the drop indicator.
    var draggedWorkspace: UUID?

    /// Drag-to-reorder: `id` takes `target`'s place in the list, and the
    /// library keeps the same order.
    func moveWorkspace(_ id: UUID, to target: UUID) {
        guard id != target,
              let from = workspaces.firstIndex(where: { $0.id == id }),
              let to = workspaces.firstIndex(where: { $0.id == target }) else { return }
        withAnimation(.snappy(duration: 0.22)) {
            workspaces.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        let order = workspaces.map(\.id)
        library.update { state in
            state.workspaces.sort { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
        }
    }

    func removeWorkspace(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        if current?.workspaceID == id {
            leaveCurrent()
            current = nil
        }
        // Its tabs go with it; the page moves to the nearest tab left.
        let activeIndex = tabs.firstIndex { $0.id == activeTabID }
        let closesActive = activeIndex.map { tabs[$0].workspaceID == id } ?? false
        tabs.removeAll { $0.workspaceID == id }
        if closesActive { activeTabID = nil }
        workspace.close()
        workspaces.removeAll { $0.id == id }
        library.update { state in
            state.workspaces.removeAll { $0.id == id }
            if state.selectedWorkspace == id { state.selectedWorkspace = nil }
        }
        library.removeSnapshots(workspace: id)
        if closesActive, !tabs.isEmpty {
            activateTab(tabs[min(activeIndex ?? 0, tabs.count - 1)].id)
        } else if selectedWorkspaceID == id {
            selectedWorkspaceID = nil
            if let first = workspaces.first { selectWorkspace(first.id) }
        }
        saveTabs()
    }

    func selectWorkspace(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        selectedWorkspaceID = id
        library.update { $0.selectedWorkspace = id }
        if current?.workspaceID == id { return }
        let remembered = pendingRestore ?? workspace.record?.selectedFile
        pendingRestore = nil
        if workspace.hasScanned, let file = remembered.flatMap(workspace.file) ?? workspace.files.first {
            open(file, transition: "none")
            return
        }
        // Nothing to show yet: the page must not keep another workspace's file.
        leaveCurrent()
        current = nil
        syncActiveTab(workspace.id, nil)
        if !workspace.hasScanned { pendingRestore = remembered ?? "" }
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
        // A file that vanished and came back (a branch switch) is not
        // reported as changed: compare what is shown with what is on disk.
        if let current, current.workspaceID == workspace.id,
           let hash = workspace.currentHash(current.file.id), hash != WorkspaceScanner.hash(current.source),
           let file = workspace.file(current.file.id), let source = WorkspaceScanner.read(file.url) {
            load(file, in: workspace, source: source, transition: nil)
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

    /// Opens a file in any workspace, switching to it first.
    func open(_ file: DocumentFile, in workspace: Workspace) {
        if selectedWorkspaceID != workspace.id {
            leaveCurrent()
            current = nil
            selectedWorkspaceID = workspace.id
            library.update { $0.selectedWorkspace = workspace.id }
        }
        open(file, transition: "none")
    }

    /// Opens `file`; with `heading`, at that section instead of the saved place.
    /// `landingAtEnd` opens the file scrolled to its end — pulling back into
    /// the previous document continues upward through it.
    func open(_ file: DocumentFile, transition: String = "none", heading: String? = nil, landingAtEnd: Bool = false) {
        guard let workspace = selectedWorkspace ?? workspaces.first(where: { $0.file(file.id) != nil }) else { return }
        if current?.file.id == file.id, current?.workspaceID == workspace.id {
            if let heading { reader.scrollToHeading(heading) }
            return
        }
        guard let source = WorkspaceScanner.read(file.url) else { return }
        filesCursor = nil
        leaveCurrent()
        // Open in another tab already: go there rather than show it twice.
        if let other = tab(showing: file.id, in: workspace.id), other.id != activeTabID {
            activeTabID = other.id
        }
        load(file, in: workspace, source: source, transition: transition, heading: heading, landingAtEnd: landingAtEnd)
        library.updateWorkspace(workspace.id) { $0.selectedFile = file.id }
    }

    /// Renders `source` and shows it. A nil transition means the same file
    /// changed on disk: the page updates in place, keeping the reader's spot.
    private func load(_ file: DocumentFile, in workspace: Workspace, source: String, transition: String?, heading: String? = nil, landingAtEnd: Bool = false) {
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
        } else if let heading {
            anchor = ScrollAnchor(unit: -1, offset: 0, heading: heading)
        } else if landingAtEnd {
            anchor = .end
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
            folded: isUpdate ? (current?.folded ?? []) : Set(record?.folded ?? []),
            highlights: record?.highlights ?? [],
            orphans: isUpdate ? (current?.orphans ?? []) : []
        )
        if !isUpdate {
            currentHeading = nil
            readerAtBottom = false
            readerAtTop = false
            syncActiveTab(workspace.id, file.id)
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
            // A page transition renders after its fade-out; search the new page.
            let delay = transition == "none" ? 0 : 520
            Task {
                try? await Task.sleep(for: .milliseconds(delay))
                await runFind(direction: 0)
            }
        }
    }

    private func makePayload(_ document: OpenDocument, in workspace: Workspace, transition: String) -> PagePayload {
        var meta: [String] = []
        let folder = document.file.folder
        if workspace.isOpenedFiles {
            // Opened on its own: where it lives says more than the group.
            meta.append(settings.displayFolderName((folder as NSString).lastPathComponent))
        } else {
            meta.append(folder.isEmpty ? workspace.name : workspace.name + " / " + settings.displayFolderPath(folder))
        }
        meta.append(Self.relativeDate(document.file.modified))
        meta.append("\(document.rendered.readingMinutes) min read")

        var badge: String?
        var badgeKind: String?
        let isGone = workspace.hasScanned && workspace.file(document.file.id) == nil
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
        if isGone {
            badge = "No longer on disk"
            badgeKind = nil
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

        let previous = previousFile(before: document.file, in: workspace).map {
            PagePayload.Next(title: settings.displayName(for: $0), label: "Previous", why: nil)
        }

        return PagePayload(
            id: document.id,
            html: document.rendered.html,
            base: ResourceURL.file(for: document.file.url.deletingLastPathComponent().path + "/", relativeTo: nil),
            header: .init(
                meta: meta,
                badge: badge,
                badgeKind: badgeKind,
                title: document.rendered.title == nil ? settings.displayName(for: document.file) : nil
            ),
            changes: changes,
            folded: Array(document.folded),
            highlights: document.highlights,
            scroll: document.anchor,
            next: nextPayload,
            previous: previous,
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
    private func leaveCurrent(markingRead: Bool? = nil) {
        guard let current, let workspace = currentWorkspace else { return }
        // A real look: reached the end, or stayed long enough to read some.
        // "Mark as Unread" pushes `openedAt` into the future to opt out.
        let lookedAtIt = current.reachedEnd || Date().timeIntervalSince(current.openedAt) > 2.5
        if markingRead ?? lookedAtIt, workspace.file(current.file.id) != nil {
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

    func goToPrevious(landingAtEnd: Bool = false) {
        guard let current, let workspace = currentWorkspace,
              let previous = previousFile(before: current.file, in: workspace) else { NSSound.beep(); return }
        open(previous, transition: "down", landingAtEnd: landingAtEnd)
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
            self.current?.changes = .none
        }
        if var document = self.current {
            document.status = workspace.status(of: document.file)
            self.current = document
        }
        refreshPage(transition: "none", keepPosition: true)
    }

    func togglePin(_ file: DocumentFile, in workspace: Workspace) {
        let pin = !workspace.isPinned(file.id)
        library.updateWorkspace(workspace.id) { record in
            record.pinned.removeAll { $0 == file.id }
            if pin { record.pinned.append(file.id) }
        }
        workspace.touch()
    }

    /// The pinned file being dragged, for the drop indicator.
    var draggedPin: String?

    /// Drag-to-reorder in the Pinned section: `id` takes `target`'s place.
    func movePin(_ id: String, to target: String, in workspace: Workspace) {
        guard id != target else { return }
        withAnimation(.snappy(duration: 0.22)) {
            library.updateWorkspace(workspace.id) { record in
                guard let from = record.pinned.firstIndex(of: id), let to = record.pinned.firstIndex(of: target) else { return }
                record.pinned.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
            workspace.touch()
        }
    }

    /// A file dropped on the Pinned section: pinned in `target`'s place, or
    /// at the end when dropped on the section itself.
    func pin(_ id: String, at target: String?, in workspace: Workspace) {
        withAnimation(.snappy(duration: 0.22)) {
            library.updateWorkspace(workspace.id) { record in
                record.pinned.removeAll { $0 == id }
                if let target, let index = record.pinned.firstIndex(of: target) {
                    record.pinned.insert(id, at: index)
                } else {
                    record.pinned.append(id)
                }
            }
            workspace.touch()
        }
    }

    /// ⌥⌘P: pins or unpins the open document.
    func togglePinCurrent() {
        guard let current, let workspace = currentWorkspace else { return }
        togglePin(current.file, in: workspace)
    }

    var isCurrentPinned: Bool {
        guard let current, let workspace = currentWorkspace else { return false }
        return workspace.isPinned(current.file.id)
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

    // MARK: Tabs
    //
    // Tab changes are never wrapped in `withAnimation`: an animated insert
    // drew the new tab before it was made active, and SwiftUI did not draw
    // it again. The bar animates its own changes instead.

    var activeTab: ReaderTab? { tabs.first { $0.id == activeTabID } }

    func tab(showing fileID: String, in workspaceID: UUID) -> ReaderTab? {
        tabs.first { $0.workspaceID == workspaceID && $0.fileID == fileID }
    }

    /// The front tab follows what the page shows; the first document opened
    /// makes the first tab.
    private func syncActiveTab(_ workspaceID: UUID, _ fileID: String?) {
        if let index = tabs.firstIndex(where: { $0.id == activeTabID }) {
            guard tabs[index].workspaceID != workspaceID || tabs[index].fileID != fileID else { return }
            tabs[index].workspaceID = workspaceID
            tabs[index].fileID = fileID
        } else {
            let tab = ReaderTab(workspaceID: workspaceID, fileID: fileID)
            tabs.append(tab)
            activeTabID = tab.id
        }
        // One tab per file, whatever path led here.
        if fileID != nil {
            tabs.removeAll { $0.id != activeTabID && $0.workspaceID == workspaceID && $0.fileID == fileID }
        }
        saveTabs()
    }

    private func saveTabs() {
        let records = tabs.map { TabRecord(workspace: $0.workspaceID, file: $0.fileID) }
        let active = tabs.firstIndex { $0.id == activeTabID }
        library.update {
            $0.tabs = records
            $0.activeTab = active
        }
    }

    /// Opens `file` in a tab of its own beside the current one, or goes to
    /// its tab when it has one.
    func openInNewTab(_ file: DocumentFile, in workspace: Workspace, heading: String? = nil) {
        if let existing = tab(showing: file.id, in: workspace.id) {
            activateTab(existing.id, heading: heading)
            return
        }
        // Nothing on the page yet: this is the first tab, not a second.
        guard current != nil, activeTab?.fileID != nil else {
            open(file, in: workspace)
            return
        }
        let tab = ReaderTab(workspaceID: workspace.id, fileID: file.id)
        let index = tabs.firstIndex { $0.id == activeTabID }.map { $0 + 1 } ?? tabs.count
        tabs.insert(tab, at: index)
        activateTab(tab.id, heading: heading)
    }

    /// Brings a tab to the front: its workspace, and its file where the
    /// reader left it.
    func activateTab(_ id: UUID, heading: String? = nil) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        guard let workspace = workspaces.first(where: { $0.id == tab.workspaceID }) else {
            tabs.removeAll { $0.id == id }
            saveTabs()
            return
        }
        if id == activeTabID, current?.workspaceID == tab.workspaceID, current?.file.id == tab.fileID {
            if let heading { reader.scrollToHeading(heading) }
            return
        }
        // A file deleted while its tab was in the back: the tab goes too.
        if workspace.hasScanned, let fileID = tab.fileID, workspace.file(fileID) == nil {
            NSSound.beep()
            tabs.removeAll { $0.id == id }
            saveTabs()
            return
        }
        leaveCurrent()
        filesCursor = nil
        activeTabID = id
        if selectedWorkspaceID != workspace.id {
            selectedWorkspaceID = workspace.id
            library.update { $0.selectedWorkspace = workspace.id }
        }
        guard let fileID = tab.fileID, workspace.hasScanned,
              let file = workspace.file(fileID), let source = WorkspaceScanner.read(file.url) else {
            current = nil
            // A tab that was waiting for files, and they have come.
            if workspace.hasScanned, let first = workspace.files.first {
                open(first, transition: "none")
                return
            }
            // Not scanned yet: the rescan opens it.
            pendingRestore = tab.fileID
            saveTabs()
            return
        }
        load(file, in: workspace, source: source, transition: "none", heading: heading)
        library.updateWorkspace(workspace.id) { $0.selectedFile = file.id }
        saveTabs()
    }

    /// The tab `offset` places from the front one, wrapping around.
    func showTab(offset: Int) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { NSSound.beep(); return }
        activateTab(tabs[(index + offset + tabs.count) % tabs.count].id)
    }

    /// Closes a tab; the one to its right, or else its left, comes forward.
    /// The last tab stays: closing it is closing the window.
    func closeTab(_ id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = id == activeTabID
        tabs.remove(at: index)
        if wasActive {
            activeTabID = nil
            activateTab(tabs[min(index, tabs.count - 1)].id)
        }
        saveTabs()
    }

    func closeOtherTabs(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        if id != activeTabID { activateTab(id) }
        tabs.removeAll { $0.id != id }
        saveTabs()
    }

    /// ⌘W: the front tab, or the window when it is the last one (or when
    /// another window, such as Settings, is in front).
    func closeTabOrWindow() {
        guard let key = NSApp.keyWindow ?? reader.webView.window else { return }
        if key == reader.webView.window, tabs.count > 1, let id = activeTabID {
            closeTab(id)
        } else {
            key.performClose(nil)
        }
    }

    /// The tab being dragged in the bar, for the drop indicator.
    var draggedTab: UUID?

    /// Drag-to-reorder: `id` takes `target`'s place.
    func moveTab(_ id: UUID, to target: UUID) {
        guard id != target, let from = tabs.firstIndex(where: { $0.id == id }),
              let to = tabs.firstIndex(where: { $0.id == target }) else { return }
        tabs.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        saveTabs()
    }

    // MARK: Panels

    /// The order swipes go through, without the columns they pass over.
    var columns: [PanelColumn] {
        settings.columnOrder.filter { !settings.swipeSkips.contains($0) }
    }

    func isShowing(_ column: PanelColumn) -> Bool { visibleColumns.contains(column) }

    /// What a swipe right brings in: the first hidden column in the order.
    var nextToReveal: PanelColumn? { columns.first { !visibleColumns.contains($0) } }

    /// What a swipe left takes away: the last showing column in the order.
    var nextToHide: PanelColumn? { columns.last { visibleColumns.contains($0) } }

    func setVisibleColumns(_ newValue: Set<PanelColumn>, animated: Bool = true) {
        let apply = {
            self.visibleColumns = newValue
            self.swipeProgress = 0
        }
        if animated, newValue != visibleColumns {
            beginPanelMotion()
            withAnimation(.galleyPanel, completionCriteria: .logicallyComplete) { apply() } completion: {
                self.endPanelMotion()
            }
        } else {
            apply()
        }
        if !newValue.isEmpty { lastVisibleColumns = newValue }
        library.update {
            $0.visibleColumns = newValue.map(\.rawValue).sorted()
            $0.lastVisibleColumns = self.lastVisibleColumns.map(\.rawValue).sorted()
        }
    }

    func setColumn(_ column: PanelColumn, visible: Bool) {
        var columns = visibleColumns
        if visible { columns.insert(column) } else { columns.remove(column) }
        setVisibleColumns(columns)
    }

    func toggleColumn(_ column: PanelColumn) {
        setColumn(column, visible: !isShowing(column))
    }

    func reveal(_ column: PanelColumn) {
        if !isShowing(column) { setColumn(column, visible: true) }
    }

    // MARK: Panel motion

    @ObservationIgnored private var panelMotions = 0
    @ObservationIgnored private var panelMotionWatchdog: Task<Void, Never>?

    /// Columns are moving (a swipe, or a level change animating): the page
    /// hides its scrollbar until the last motion ends. Motions nest.
    func beginPanelMotion() {
        panelMotions += 1
        if panelMotions == 1 { reader.setPanelsMoving(true) }
        // Never leave the scrollbar hidden if an animation's completion is lost.
        panelMotionWatchdog?.cancel()
        panelMotionWatchdog = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled, let self else { return }
                if self.swipeProgress == 0 { break }
            }
            guard let self, self.panelMotions > 0 else { return }
            self.panelMotions = 0
            self.reader.setPanelsMoving(false)
        }
    }

    func endPanelMotion() {
        guard panelMotions > 0 else { return }
        panelMotions -= 1
        if panelMotions == 0 {
            panelMotionWatchdog?.cancel()
            reader.setPanelsMoving(false)
        }
    }

    /// ⌘] and ⌘[: a swipe's worth, through the order.
    func stepLevel(_ delta: Int) {
        guard let column = delta > 0 ? nextToReveal : nextToHide else { NSSound.beep(); return }
        setColumn(column, visible: delta > 0)
    }

    // MARK: Columns

    /// Whether swipes and ⌘] / ⌘[ pass over a column.
    func setSwipeSkips(_ column: PanelColumn, _ skips: Bool) {
        if skips { settings.swipeSkips.insert(column) } else { settings.swipeSkips.remove(column) }
    }

    func moveColumns(from source: IndexSet, to destination: Int) {
        settings.columnOrder.move(fromOffsets: source, toOffset: destination)
    }

    static let columnLimits: [PanelColumn: ClosedRange<CGFloat>] = [
        .workspaces: 150...340, .files: 200...460, .outline: 180...400,
    ]
    static let defaultColumnWidths: [PanelColumn: CGFloat] = [.workspaces: 208, .files: 284, .outline: 244]
    static let railWidth: CGFloat = 60

    private static func widthKey(_ column: PanelColumn) -> String { column.rawValue }

    /// A column's width: the reader's own, or the default.
    func columnWidth(_ column: PanelColumn) -> CGFloat {
        if column == .workspaces, settings.workspacesAsIcons { return Self.railWidth }
        if let stored = settings.columnWidths[Self.widthKey(column)] { return CGFloat(stored) }
        return Self.defaultColumnWidths[column] ?? 240
    }

    /// Dragged narrower than this, the workspace list folds into the rail.
    static let foldBelow: CGFloat = 105
    /// Dragged wider than this, the rail opens back into the list. The gap
    /// between the two keeps it from flapping at one point.
    static let unfoldAbove: CGFloat = 130

    /// A column's edge dragged to `requested` points wide. Workspaces fold
    /// into the icon rail past the narrow end and back out past the wide
    /// one, as Finder's sidebar does.
    func dragColumnEdge(_ column: PanelColumn, to requested: CGFloat) {
        guard column == .workspaces else {
            setColumnWidth(column, requested)
            return
        }
        if settings.workspacesAsIcons {
            guard requested > Self.unfoldAbove else { return }
            foldWorkspaces(false)
            setColumnWidth(column, requested)
        } else if requested < Self.foldBelow {
            foldWorkspaces(true)
        } else {
            setColumnWidth(column, requested)
        }
    }

    private func foldWorkspaces(_ toRail: Bool) {
        withAnimation(.snappy(duration: 0.22)) { settings.workspacesAsIcons = toRail }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func setColumnWidth(_ column: PanelColumn, _ width: CGFloat?) {
        guard let width else {
            settings.columnWidths[Self.widthKey(column)] = nil
            return
        }
        let limits = Self.columnLimits[column] ?? 150...460
        settings.columnWidths[Self.widthKey(column)] = Double(min(limits.upperBound, max(limits.lowerBound, width)).rounded())
    }

    /// The toolbar button: page alone, or back to the panels you had.
    func togglePanels() {
        setVisibleColumns(visibleColumns.isEmpty ? (lastVisibleColumns.isEmpty ? [.files] : lastVisibleColumns) : [])
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
            readerAtTop = report.atTop
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
        case let .highlight(text, prefix, suffix, replaces, id):
            var highlight = Highlight(text: text, prefix: prefix, suffix: suffix)
            if let id { highlight.id = id }
            // Notes on the passages it grew over carry over to it.
            let notes = current?.highlights.filter { replaces.contains($0.id) }.compactMap(\.note) ?? []
            if !notes.isEmpty { highlight.note = notes.joined(separator: "\n\n") }
            addHighlight(highlight, replacing: replaces)
        case let .note(id, text):
            setNote(text, for: id)
        case .unhighlight(let id):
            removeHighlight(id)
        case .orphans(let ids):
            if current?.orphans != Set(ids) { current?.orphans = Set(ids) }
        }
    }

    var isReaderAtBottom: Bool { readerAtBottom }
    var isReaderAtTop: Bool { readerAtTop }

    /// Moves keyboard focus into the page, so arrows and Space scroll it.
    func focusPage() {
        let webView = reader.webView
        webView.window?.makeFirstResponder(webView)
    }

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

    // MARK: Highlights

    func highlightSelection() {
        Task {
            guard let anchor = await reader.selectionAnchor() else { NSSound.beep(); return }
            addHighlight(Highlight(text: anchor.text, prefix: anchor.prefix, suffix: anchor.suffix), replacing: anchor.replaces)
        }
    }

    /// Adds a highlight; one that grew over existing highlights replaces them.
    private func addHighlight(_ highlight: Highlight, replacing: [String] = []) {
        guard current != nil else { return }
        current?.highlights.removeAll { replacing.contains($0.id) }
        current?.highlights.append(highlight)
        saveHighlights()
    }

    func removeHighlight(_ id: String) {
        current?.highlights.removeAll { $0.id == id }
        current?.orphans.remove(id)
        saveHighlights()
    }

    func scrollToHighlight(_ id: String) {
        reader.scrollToHighlight(id)
    }

    private func saveHighlights() {
        guard let current, let workspace = currentWorkspace else { return }
        library.updateWorkspace(workspace.id) { record in
            record.files[current.file.id, default: FileRecord()].highlights = current.highlights.isEmpty ? nil : current.highlights
        }
        workspace.touch() // the file list's feedback marks
        reader.setHighlights(current.highlights)
    }

    func setNote(_ text: String, for id: String) {
        guard let index = current?.highlights.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        current?.highlights[index].note = trimmed.isEmpty ? nil : trimmed
        saveHighlights()
    }

    /// ⌃⌘N: highlights the selection and opens a note on it.
    func noteSelection() {
        Task {
            if await reader.noteSelection() != true { NSSound.beep() }
        }
    }

    /// Opens the note editor on a highlight in the page.
    func editNote(_ id: String) {
        reader.editNote(id)
    }

    // MARK: Feedback

    /// Whether the open document, or any file in the selected workspace,
    /// has highlights or notes.
    var hasFeedback: Bool { !(current?.highlights.isEmpty ?? true) }

    var workspaceHasFeedback: Bool {
        guard let workspace = selectedWorkspace else { return false }
        return workspace.record?.files.values.contains { !($0.highlights ?? []).isEmpty } ?? false
    }

    /// The open document's feedback, for pasting to an agent. Passages no
    /// longer in the text are left out: the agent has dealt with them.
    func copyFeedback() {
        guard let current else { NSSound.beep(); return }
        let items = current.highlights
            .filter { !current.orphans.contains($0.id) }
            .map { Feedback.Item(text: $0.text, note: $0.note) }
        copy(Feedback.format([Feedback.File(path: current.file.url.path, items: items)]))
    }

    /// Every file's feedback in the selected workspace, in reading order.
    func copyWorkspaceFeedback() {
        guard let workspace = selectedWorkspace, let record = workspace.record else { NSSound.beep(); return }
        let files: [Feedback.File] = workspace.tree.readingOrder.compactMap { file in
            guard let highlights = record.files[file.id]?.highlights, !highlights.isEmpty else { return nil }
            let source = WorkspaceScanner.read(file.url) ?? ""
            let items = highlights
                .filter { Feedback.isStillPresent($0.text, in: source) }
                .map { Feedback.Item(text: $0.text, note: $0.note) }
            return Feedback.File(path: file.url.path, items: items)
        }
        copy(Feedback.format(files))
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Removes the open document's highlights and notes, after asking.
    func clearFeedback() {
        guard let current, !current.highlights.isEmpty else { return }
        let notes = current.highlights.filter { $0.note != nil }.count
        confirm(
            title: "Clear feedback on “\(settings.displayName(for: current.file))”?",
            detail: Self.feedbackSummary(highlights: current.highlights.count, notes: notes)
        ) { [weak self] in
            self?.current?.highlights = []
            self?.current?.orphans = []
            self?.saveHighlights()
        }
    }

    /// Removes every highlight and note in the selected workspace, after asking.
    func clearWorkspaceFeedback() {
        guard let workspace = selectedWorkspace, let record = workspace.record else { return }
        let all = record.files.values.flatMap { $0.highlights ?? [] }
        guard !all.isEmpty else { return }
        let files = record.files.values.filter { !($0.highlights ?? []).isEmpty }.count
        confirm(
            title: "Clear all feedback in \(workspace.name)?",
            detail: Self.feedbackSummary(highlights: all.count, notes: all.filter { $0.note != nil }.count) + " in \(files == 1 ? "1 file" : "\(files) files")"
        ) { [weak self] in
            guard let self else { return }
            self.library.updateWorkspace(workspace.id) { record in
                for key in record.files.keys { record.files[key]?.highlights = nil }
            }
            workspace.touch()
            if self.current?.workspaceID == workspace.id {
                self.current?.highlights = []
                self.current?.orphans = []
                self.reader.setHighlights([])
            }
        }
    }

    static func feedbackSummary(highlights: Int, notes: Int) -> String {
        let marks = highlights == 1 ? "1 highlight" : "\(highlights) highlights"
        guard notes > 0 else { return marks.prefix(1).uppercased() + marks.dropFirst() }
        return (marks.prefix(1).uppercased() + marks.dropFirst()) + (notes == 1 ? ", 1 with a note" : ", \(notes) with notes")
    }

    private func confirm(title: String, detail: String, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail + ". This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            if alert.runModal() == .alertFirstButtonReturn { action() }
            return
        }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { action() }
        }
    }

    // MARK: Links

    private func followLink(_ href: String) {
        guard let current, let workspace = currentWorkspace else { return }
        if href.hasPrefix("wiki:") {
            let target = String(href.dropFirst(5))
            let parts = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let heading = parts.count > 1 && !parts[1].isEmpty ? Slug.make(parts[1]) : nil
            // `[[#Section]]` points into this page.
            if name.isEmpty {
                if let heading { reader.scrollToHeading(heading) } else { NSSound.beep() }
                return
            }
            let match = workspace.files.first {
                ($0.filename as NSString).deletingPathExtension.lowercased() == name
                    || $0.filename.lowercased() == name
                    || $0.relativePath.lowercased() == name
                    || ($0.relativePath as NSString).deletingPathExtension.lowercased() == name
                    || $0.heading?.lowercased() == name
            }
            guard let match else { NSSound.beep(); return }
            if NSEvent.modifierFlags.contains(.command) {
                openInNewTab(match, in: workspace, heading: heading)
            } else {
                open(match, transition: "none", heading: heading)
            }
            return
        }
        guard let url = URL(string: href) ?? URL(string: href.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "") else { return }
        if let scheme = url.scheme?.lowercased(), scheme != "file" {
            openExternal(url, scheme: scheme)
            return
        }
        let path = (url.path.isEmpty ? href : url.path).removingPercentEncoding ?? url.path
        let target = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : current.file.url.deletingLastPathComponent().appendingPathComponent(path)
        let standardized = target.standardizedFileURL
        let fragment = url.fragment.map { $0.removingPercentEncoding ?? $0 }
        if WorkspaceScanner.isMarkdown(standardized), workspace.contains(standardized) {
            let relative = String(standardized.path.dropFirst(workspace.root.standardizedFileURL.path.count + 1))
            if let file = workspace.file(relative) {
                // ⌘-click, as in a browser: a tab of its own.
                if NSEvent.modifierFlags.contains(.command) {
                    openInNewTab(file, in: workspace, heading: fragment)
                } else {
                    open(file, transition: "none", heading: fragment)
                }
                return
            }
        }
        // Other local files are shown, never launched: a link in an agent's
        // Markdown must not be able to run an app or a script with one click.
        if FileManager.default.fileExists(atPath: standardized.path) {
            NSWorkspace.shared.activateFileViewerSelecting([standardized])
        } else {
            NSSound.beep()
        }
    }

    /// Web and mail links open directly; anything that would hand the link
    /// to another app asks first.
    private func openExternal(_ url: URL, scheme: String) {
        if ["http", "https", "mailto"].contains(scheme) {
            NSWorkspace.shared.open(url)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Open this link in another app?"
        alert.informativeText = url.absoluteString
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
    }

    func printPage() {
        guard current != nil, let window = reader.webView.window else { NSSound.beep(); return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 54; info.bottomMargin = 54; info.leftMargin = 60; info.rightMargin = 60
        info.isVerticallyCentered = false
        let operation = reader.webView.printOperation(with: info)
        operation.view?.frame = reader.webView.bounds
        operation.jobTitle = current.map { settings.displayName(for: $0.file) } ?? "Galley"
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: Files

    func revealInFinder(_ file: DocumentFile? = nil) {
        if let url = file?.url ?? current?.file.url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if let workspace = selectedWorkspace {
            NSWorkspace.shared.activateFileViewerSelecting(workspace.revealURLs)
        }
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

    /// A search result chosen in the palette: open the file and light up
    /// `term` in it with find, so ⌘G steps through the rest.
    func openSearchResult(_ file: DocumentFile, in workspace: Workspace, term: String, inNewTab: Bool = false) {
        findQuery = term
        isFindVisible = true
        if current?.file.id == file.id, current?.workspaceID == workspace.id {
            Task { await runFind(direction: 0) }
        } else if inNewTab {
            openInNewTab(file, in: workspace)
        } else {
            open(file, in: workspace)
        }
    }

    /// Every file in every workspace, for the text index.
    var textIndexEntries: [TextIndex.Entry] {
        workspaces.flatMap { workspace in
            workspace.files.map { file in
                TextIndex.Entry(key: workspace.id.uuidString + "/" + file.id, title: settings.displayName(for: file), url: file.url, modified: file.modified)
            }
        }
    }

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

extension UTType {
    /// Markdown, as the system declares it (and `app/Info.plist` imports it).
    static let markdown = UTType("net.daringfireball.markdown") ?? .plainText
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
