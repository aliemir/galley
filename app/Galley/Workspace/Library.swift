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
    }
}

nonisolated struct LibraryState: Codable, Sendable {
    var workspaces: [WorkspaceRecord] = []
    var selectedWorkspace: UUID?
    var level: Int = 3
    var lastPanelLevel: Int = 3

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workspaces = try c.decodeIfPresent([WorkspaceRecord].self, forKey: .workspaces) ?? []
        selectedWorkspace = try c.decodeIfPresent(UUID.self, forKey: .selectedWorkspace)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 3
        lastPanelLevel = try c.decodeIfPresent(Int.self, forKey: .lastPanelLevel) ?? 3
    }
}

/// Reads and writes the library and the last-read snapshots under
/// Application Support. Writes are debounced; `flush()` forces one.
@MainActor
final class Library {
    private(set) var state: LibraryState
    private let directory: URL
    private var saveTask: Task<Void, Never>?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Galley", isDirectory: true)
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

private extension JSONEncoder {
    nonisolated static var library: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    nonisolated static var library: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
