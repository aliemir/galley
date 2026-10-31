import Foundation

/// What the app remembers about one file. Never anything about the file's
/// content beyond a hash — the content itself lives in `Snapshots`.
nonisolated struct FileRecord: Codable, Hashable, Sendable {
    /// Hash of the version the reader last read; nil when never read.
    var readHash: String?
    var readAt: Date?
    /// Set by "Mark as Unread"; cleared when the file is read again.
    var markedUnread: Bool?
    var scroll: ScrollAnchor?
    var folded: [String]?
}

nonisolated struct WorkspaceRecord: Codable, Identifiable, Sendable {
    let id: UUID
    var bookmark: Data?
    var path: String
    var addedAt: Date
    var selectedFile: String?
    var collapsedFolders: [String] = []
    var files: [String: FileRecord] = [:]
}

nonisolated struct LibraryState: Codable, Sendable {
    var workspaces: [WorkspaceRecord] = []
    var selectedWorkspace: UUID?
    var level: Int = 3
    var lastPanelLevel: Int = 3
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
        if let data = try? Data(contentsOf: directory.appendingPathComponent("library.json")),
           let decoded = try? JSONDecoder.library.decode(LibraryState.self, from: data) {
            state = decoded
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
