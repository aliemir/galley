import Foundation
import Observation
import SwiftUI

/// Where a file stands against the version the reader last read.
enum ReadStatus: Hashable {
    case read
    /// Never read (appeared after the workspace was added), or marked unread.
    case unread
    /// Read before, and different now.
    case changed
}

/// An open folder: its tree, live updates, and the read status of each file.
@MainActor
@Observable
final class Workspace: Identifiable {
    let id: UUID
    let root: URL
    private(set) var tree: FolderNode
    /// Every file in reading order.
    private(set) var files: [DocumentFile] = []
    private(set) var statuses: [String: ReadStatus] = [:]
    private(set) var hasScanned = false
    /// False when the folder is gone or no longer readable.
    private(set) var isAvailable = true

    /// Called with the relative paths whose content changed on disk.
    @ObservationIgnored var onContentChange: (Set<String>) -> Void = { _ in }
    /// Called after every rescan.
    @ObservationIgnored var onRescan: () -> Void = {}

    @ObservationIgnored private let library: Library
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var hashes: [String: (modified: Date, size: Int, hash: String)] = [:]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var accessing = false
    /// A new workspace's first full scan must record the baseline; a rescan
    /// that cancels it (an agent writing meanwhile) inherits the duty.
    @ObservationIgnored private var needsBaseline = false

    /// Bumped when library-backed state (collapsed folders) changes, so
    /// views reading `record` refresh.
    private(set) var revision = 0

    /// The folder's name on disk.
    var folderName: String { root.lastPathComponent }
    /// The name Galley shows: the reader's own, or the tidied folder name.
    var name: String {
        if let custom = record?.customName?.trimmingCharacters(in: .whitespaces), !custom.isEmpty { return custom }
        return defaultName
    }

    var defaultName: String { ReaderSettings.shared.displayFolderName(folderName) }

    var icon: WorkspaceIcon.Kind { WorkspaceIcon.Kind(stored: record?.icon) }

    /// The workspace's colour: the reader's pick, or one chosen from its id.
    var color: Color { WorkspaceIcon.color(named: record?.color) ?? WorkspaceIcon.automaticColor(for: id) }
    var record: WorkspaceRecord? {
        _ = revision
        return library.record(id)
    }

    func touch() { revision += 1 }

    var unreadCount: Int { statuses.values.filter { $0 != .read }.count }
    /// Never read.
    var newCount: Int { statuses.values.filter { $0 == .unread }.count }
    /// Changed since read.
    var changedCount: Int { statuses.values.filter { $0 == .changed }.count }

    /// Highlights (with or without a note) on one file, or the whole workspace.
    func feedbackCount(_ relativePath: String) -> Int {
        record?.files[relativePath]?.highlights?.count ?? 0
    }

    var feedbackCount: Int {
        record?.files.values.reduce(0) { $0 + ($1.highlights?.count ?? 0) } ?? 0
    }

    /// Unread and changed files, newest first — the "Changed" feed.
    var feed: [DocumentFile] {
        files.filter { (statuses[$0.id] ?? .read) != .read }.sorted { $0.modified > $1.modified }
    }

    init(record: WorkspaceRecord, library: Library) {
        id = record.id
        self.library = library
        var url = URL(fileURLWithPath: record.path, isDirectory: true)
        if let bookmark = record.bookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], bookmarkDataIsStale: &stale) {
                url = resolved
                if stale, let fresh = try? resolved.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]) {
                    library.updateWorkspace(record.id) { $0.bookmark = fresh }
                }
            }
        }
        root = url
        tree = FolderNode(id: "", name: url.lastPathComponent, folders: [], files: [])
        accessing = url.startAccessingSecurityScopedResource()
    }

    func start() {
        rescan()
        watcher = FolderWatcher(url: root) { [weak self] paths in
            self?.filesystemChanged(paths)
        }
    }

    func close() {
        watcher?.stop()
        watcher = nil
        scanTask?.cancel()
        if accessing { root.stopAccessingSecurityScopedResource() }
        accessing = false
    }

    func file(_ relativePath: String) -> DocumentFile? {
        files.first { $0.id == relativePath }
    }

    /// Pinned files that exist, in pin order. A pin outlives its file, so a
    /// file that is deleted and written again comes back pinned.
    var pinnedFiles: [DocumentFile] {
        (record?.pinned ?? []).compactMap(file)
    }

    func isPinned(_ relativePath: String) -> Bool {
        record?.pinned.contains(relativePath) ?? false
    }

    func status(of file: DocumentFile) -> ReadStatus {
        statuses[file.id] ?? .read
    }

    func contains(_ url: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    // MARK: Scanning

    private func filesystemChanged(_ paths: [String]) {
        let relevant = paths.contains { path in
            let url = URL(fileURLWithPath: path)
            return WorkspaceScanner.isMarkdown(url) || url.pathExtension.isEmpty || path == root.path
        }
        if relevant { rescan() }
    }

    /// Re-reads the tree in the background, then recomputes statuses and
    /// reports which files' content changed.
    func rescan(baseline requested: Bool = false) {
        scanTask?.cancel()
        if requested { needsBaseline = true }
        let baseline = needsBaseline
        let root = root
        let previous = hashes
        scanTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> (FolderNode, [String: (Date, Int, String)], [String: String]) in
                let tree = WorkspaceScanner.scan(root)
                var hashes: [String: (Date, Int, String)] = [:]
                var texts: [String: String] = [:]
                for file in tree.readingOrder {
                    if let old = previous[file.id], old.modified == file.modified, old.size == file.size, !baseline {
                        hashes[file.id] = old
                    } else if let text = WorkspaceScanner.read(file.url) {
                        hashes[file.id] = (file.modified, file.size, WorkspaceScanner.hash(text))
                        if baseline { texts[file.id] = text }
                    }
                }
                return (tree, hashes, texts)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.apply(tree: result.0, hashes: result.1, baselineTexts: baseline ? result.2 : nil)
        }
    }

    private func apply(tree: FolderNode, hashes newHashes: [String: (Date, Int, String)], baselineTexts: [String: String]?) {
        let exists = FileManager.default.fileExists(atPath: root.path)
        isAvailable = exists
        let changed = Set(newHashes.compactMap { path, value in
            hashes[path].map { $0.hash != value.2 ? path : nil } ?? nil
        })
        hashes = newHashes.mapValues { (modified: $0.0, size: $0.1, hash: $0.2) }
        self.tree = tree
        files = tree.readingOrder

        if let baselineTexts {
            needsBaseline = false
            // A new workspace: everything already there counts as read, so
            // only what agents write from now on lights up.
            let now = Date()
            library.updateWorkspace(id) { record in
                for (path, text) in baselineTexts where record.files[path]?.readHash == nil {
                    record.files[path, default: FileRecord()].readHash = WorkspaceScanner.hash(text)
                    record.files[path, default: FileRecord()].readAt = now
                }
            }
            for (path, text) in baselineTexts {
                library.saveSnapshot(text, workspace: id, path: path)
            }
        }
        recomputeStatuses()
        hasScanned = true
        if !changed.isEmpty { onContentChange(changed) }
        onRescan()
    }

    func recomputeStatuses() {
        let records = library.record(id)?.files ?? [:]
        var result: [String: ReadStatus] = [:]
        for file in files {
            let record = records[file.id]
            if record?.markedUnread == true || record?.readHash == nil {
                result[file.id] = .unread
            } else if let hash = hashes[file.id]?.hash, hash != record?.readHash {
                result[file.id] = .changed
            } else {
                result[file.id] = .read
            }
        }
        statuses = result
    }

    /// Records `text` as the version of `path` the reader has now read.
    func markRead(_ path: String, text: String) {
        let hash = WorkspaceScanner.hash(text)
        let alreadyRead = library.record(id)?.files[path].map { $0.readHash == hash && $0.markedUnread != true } ?? false
        guard !alreadyRead else { return }
        library.saveSnapshot(text, workspace: id, path: path)
        library.updateWorkspace(id) { record in
            record.files[path, default: FileRecord()].readHash = hash
            record.files[path, default: FileRecord()].readAt = Date()
            record.files[path, default: FileRecord()].markedUnread = nil
        }
        recomputeStatuses()
    }

    func markUnread(_ path: String) {
        library.updateWorkspace(id) { $0.files[path, default: FileRecord()].markedUnread = true }
        recomputeStatuses()
    }

    /// Marks every file read at its current content.
    func markAllRead() {
        let targets = files.filter { status(of: $0) != .read }
        for file in targets {
            if let text = WorkspaceScanner.read(file.url) { markRead(file.id, text: text) }
        }
    }

    func currentHash(_ path: String) -> String? { hashes[path]?.hash }
}
