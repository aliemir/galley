import AppKit
import Observation
import SwiftUI
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

/// A column beside the page. Each has a fixed place (`arrangement`); the
/// reader's order (Settings → Reading) is only the order swipes reveal them.
enum PanelColumn: String, CaseIterable, Identifiable {
    case outline, files, workspaces

    var id: String { rawValue }

    /// Where the columns sit, left to right, whatever the reveal order.
    static let arrangement: [PanelColumn] = [.workspaces, .files, .outline]

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

    /// The columns showing; each toggles on its own, swipes follow the order.
    private(set) var visibleColumns: Set<PanelColumn> = [.outline, .files]
    /// -1…1 while a horizontal swipe is in flight: positive reveals the next
    /// column, negative hides the outermost one.
    var swipeProgress: Double = 0

    var isQuickOpenVisible = false
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
        let byLevel = { (level: Int) in Set(PanelColumn.allCases.prefix(max(0, level - 1))) }
        visibleColumns = state.visibleColumns.map { Set($0.compactMap(PanelColumn.init(rawValue:))) } ?? byLevel(state.level)
        lastVisibleColumns = state.lastVisibleColumns.map { Set($0.compactMap(PanelColumn.init(rawValue:))) } ?? byLevel(state.lastPanelLevel)
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
        var folder = isDirectory.boolValue ? url : url.deletingLastPathComponent()

        // A dropped file is already inside a workspace: just open it.
        if !isDirectory.boolValue, let existing = workspaces.first(where: { $0.contains(url) }) {
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
        if let existing = workspaces.first(where: { $0.root.standardizedFileURL == folder.standardizedFileURL }) {
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
        if workspace.hasScanned, let file = remembered.flatMap(workspace.file) ?? workspace.files.first {
            open(file, transition: "none")
            return
        }
        // Nothing to show yet: the page must not keep another workspace's file.
        leaveCurrent()
        current = nil
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
        meta.append(folder.isEmpty ? workspace.name : workspace.name + " / " + settings.displayFolderPath(folder))
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
        case let .highlight(text, prefix, suffix, replaces):
            addHighlight(Highlight(text: text, prefix: prefix, suffix: suffix), replacing: replaces)
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
        reader.setHighlights(current.highlights)
    }

    /// The open document's highlights as Markdown quotes, for pasting.
    func copyHighlights() {
        guard let current, !current.highlights.isEmpty else { NSSound.beep(); return }
        let quotes = current.highlights.map { "> " + $0.text.replacingOccurrences(of: "\n", with: "\n> ") }
        let text = "Highlights from \(current.file.relativePath):\n\n" + quotes.joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
            open(match, transition: "none", heading: heading)
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
                open(file, transition: "none", heading: fragment)
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
