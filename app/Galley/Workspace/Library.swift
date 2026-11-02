import Foundation

/// What the app remembers about one file. Never anything about the file's
/// content beyond a hash — the content itself lives in `Snapshots`.
/// A passage the reader marked. Anchored by its text and the text around
/// it, never by position, so it survives the file being rewritten.
nonisolated struct Highlight: Codable, Hashable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var text: String
    var prefix: String
    var suffix: String
    var created = Date()
    /// What the reader wants done about the passage.
    var note: String?
}

nonisolated struct FileRecord: Codable, Hashable, Sendable {
    /// Hash of the version the reader last read; nil when never read.
    var readHash: String?
    var readAt: Date?
    /// Set by "Mark as Unread"; cleared when the file is read again.
    var markedUnread: Bool?
    var scroll: ScrollAnchor?
    var folded: [String]?
    var highlights: [Highlight]?
}

nonisolated struct WorkspaceRecord: Codable, Identifiable, Sendable {
    let id: UUID
    var bookmark: Data?
    var path: String
    var addedAt: Date
    var selectedFile: String?
    var collapsedFolders: [String] = []
    var files: [String: FileRecord] = [:]
    /// The reader's own name for the workspace; the folder is never renamed.
    var customName: String?
    /// `symbol:<SF Symbol>` or `emoji:<character>`; nil shows a monogram.
    var icon: String?
    /// One of `WorkspaceIcon.colors` by name; nil picks one from the id.
    var color: String?
    /// Pinned files by relative path, in the order they were pinned.
    var pinned: [String] = []
    /// "files" for Opened Files: documents opened one at a time rather than
    /// a folder. Their ids are their absolute paths.
    var kind: String?
    /// Opened Files' documents, each with the bookmark that reopens it.
    var documents: [OpenedDocument] = []

    init(id: UUID, bookmark: Data?, path: String, addedAt: Date) {
        self.id = id
        self.bookmark = bookmark
        self.path = path
        self.addedAt = addedAt
    }

    // Every field but the identity is optional on disk, so adding a field
    // later can never make an older library unreadable.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        path = try c.decode(String.self, forKey: .path)
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        selectedFile = try c.decodeIfPresent(String.self, forKey: .selectedFile)
        collapsedFolders = try c.decodeIfPresent([String].self, forKey: .collapsedFolders) ?? []
        files = try c.decodeIfPresent([String: FileRecord].self, forKey: .files) ?? [:]
        customName = try c.decodeIfPresent(String.self, forKey: .customName)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        pinned = try c.decodeIfPresent([String].self, forKey: .pinned) ?? []
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        documents = try c.decodeIfPresent([OpenedDocument].self, forKey: .documents) ?? []
    }
}

/// A file opened on its own. The sandbox grants that file and nothing
/// beside it, so each keeps a bookmark of its own.
nonisolated struct OpenedDocument: Codable, Hashable, Sendable {
    var path: String
    var bookmark: Data?
}

nonisolated struct LibraryState: Codable, Sendable {
    var workspaces: [WorkspaceRecord] = []
    var selectedWorkspace: UUID?
    var level: Int = 3
    var lastPanelLevel: Int = 3
    /// The columns showing, and the set the panel button brings back. Older
    /// libraries have only `level`, a depth into the default order.
    var visibleColumns: [String]?
    var lastVisibleColumns: [String]?
    /// The page's tabs, left to right, and which one is in front.
    var tabs: [TabRecord]?
    var activeTab: Int?

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workspaces = try c.decodeIfPresent([WorkspaceRecord].self, forKey: .workspaces) ?? []
        selectedWorkspace = try c.decodeIfPresent(UUID.self, forKey: .selectedWorkspace)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 3
        lastPanelLevel = try c.decodeIfPresent(Int.self, forKey: .lastPanelLevel) ?? 3
        visibleColumns = try c.decodeIfPresent([String].self, forKey: .visibleColumns)
        lastVisibleColumns = try c.decodeIfPresent([String].self, forKey: .lastVisibleColumns)
        tabs = try c.decodeIfPresent([TabRecord].self, forKey: .tabs)
        activeTab = try c.decodeIfPresent(Int.self, forKey: .activeTab)
    }
}

/// A tab as saved: the workspace, and the file it shows (none yet when the
/// workspace had nothing to show).
nonisolated struct TabRecord: Codable, Hashable, Sendable {
    var workspace: UUID
    var file: String?
}

/// Reads and writes the library and the last-read snapshots under
/// Application Support. Writes are debounced; `flush()` forces one.
@MainActor
final class Library {
    private(set) var state: LibraryState
    private let directory: URL
    private var saveTask: Task<Void, Never>?

    init() {
        let directory = LibraryLocation.directory
        self.directory = directory
        if !LibraryLocation.isThrowaway { SandboxMigration.library(into: directory) }
        try? FileManager.default.createDirectory(at: directory.appendingPathComponent("Snapshots"), withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("library.json")
        if let data = try? Data(contentsOf: file) {
            if let decoded = try? JSONDecoder.library.decode(LibraryState.self, from: data) {
                state = decoded
            } else {
                // Never overwrite what could not be read: keep it beside the new one.
                let stamp = Int(Date().timeIntervalSince1970)
                try? FileManager.default.moveItem(at: file, to: directory.appendingPathComponent("library-unreadable-\(stamp).json"))
                state = LibraryState()
            }
        } else {
            state = LibraryState()
        }
    }

    func update(_ change: (inout LibraryState) -> Void) {
        change(&state)
        scheduleSave()
    }

    func updateWorkspace(_ id: UUID, _ change: (inout WorkspaceRecord) -> Void) {
        guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return }
        change(&state.workspaces[index])
        scheduleSave()
    }

    func record(_ id: UUID) -> WorkspaceRecord? {
        state.workspaces.first { $0.id == id }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        saveTask?.cancel()
        guard let data = try? JSONEncoder.library.encode(state) else { return }
        try? data.write(to: directory.appendingPathComponent("library.json"), options: .atomic)
    }

    // MARK: Snapshots

    private func snapshotURL(workspace: UUID, path: String) -> URL {
        let name = WorkspaceScanner.hash(path) + ".md"
        return directory.appendingPathComponent("Snapshots/\(workspace.uuidString)/\(name)")
    }

    func snapshot(workspace: UUID, path: String) -> String? {
        WorkspaceScanner.read(snapshotURL(workspace: workspace, path: path))
    }

    func saveSnapshot(_ text: String, workspace: UUID, path: String) {
        let url = snapshotURL(workspace: workspace, path: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url, options: .atomic)
    }

    func removeSnapshots(workspace: UUID) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("Snapshots/\(workspace.uuidString)"))
    }
}

/// Where the library lives, for the app and for the `galley` command.
nonisolated enum LibraryLocation {
    static var directory: URL {
        #if DEBUG
        // A throwaway library for scripted captures and tests: `-GalleyLibrary
        // <dir>` for the app, GALLEY_LIBRARY for the command.
        if let path = UserDefaults.standard.string(forKey: "GalleyLibrary") ?? ProcessInfo.processInfo.environment["GALLEY_LIBRARY"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Galley", isDirectory: true)
    }

    static var isThrowaway: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "GalleyLibrary") != nil || ProcessInfo.processInfo.environment["GALLEY_LIBRARY"] != nil
        #else
        false
        #endif
    }

    /// The library as the app last saved it (it saves within a second of
    /// any change), for reading from outside the app.
    static func read(from directory: URL = directory) throws -> LibraryState {
        let data = try Data(contentsOf: directory.appendingPathComponent("library.json"))
        return try JSONDecoder.library.decode(LibraryState.self, from: data)
    }

    /// For the `galley` command while the app is not running — when it is,
    /// it holds the library and is asked to make the change instead.
    static func write(_ state: LibraryState, to directory: URL = directory) throws {
        try JSONEncoder.library.encode(state).write(to: directory.appendingPathComponent("library.json"), options: .atomic)
    }
}

/// Clearing feedback by path, the same way in the app and in the command:
/// every file at or under one of `paths` loses its highlights and notes —
/// or, with `addressedOnly`, only those whose passage is no longer in it.
nonisolated enum FeedbackClearing {
    struct Result: Equatable { var highlights = 0, files = 0 }

    /// A file's absolute path from its workspace record.
    static func path(of id: String, in workspace: WorkspaceRecord) -> String {
        workspace.kind == "files" ? id : URL(fileURLWithPath: workspace.path).appendingPathComponent(id).standardizedFileURL.path
    }

    /// Whether `path` is one of `targets` or under one. Both sides with
    /// their symlinks resolved, so a workspace added through a symlink and
    /// a command run from the real folder (or the other way round) meet.
    static func matches(_ path: String, _ targets: [String]) -> Bool {
        let path = resolved(path)
        return targets.map(resolved).contains { target in
            path == target || path.hasPrefix(target.hasSuffix("/") ? target : target + "/")
        }
    }

    static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    @discardableResult
    static func apply(to state: inout LibraryState, paths: [String], addressedOnly: Bool) -> Result {
        var result = Result()
        for index in state.workspaces.indices {
            let workspace = state.workspaces[index]
            for (id, record) in workspace.files {
                guard let highlights = record.highlights, !highlights.isEmpty else { continue }
                let path = path(of: id, in: workspace)
                guard matches(path, paths) else { continue }
                var kept: [Highlight] = []
                if addressedOnly {
                    let source = WorkspaceScanner.read(URL(fileURLWithPath: path)) ?? ""
                    kept = highlights.filter { Feedback.isStillPresent($0.text, in: source) }
                }
                guard kept.count < highlights.count else { continue }
                result.highlights += highlights.count - kept.count
                result.files += 1
                state.workspaces[index].files[id]?.highlights = kept.isEmpty ? nil : kept
            }
        }
        return result
    }
}

extension JSONEncoder {
    nonisolated static var library: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    nonisolated static var library: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
