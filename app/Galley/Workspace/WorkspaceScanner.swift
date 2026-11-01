import CryptoKit
import Foundation

/// A markdown file inside a workspace.
nonisolated struct DocumentFile: Identifiable, Hashable, Sendable {
    /// Path relative to the workspace root, e.g. `notes/plan.md`.
    var id: String { relativePath }
    let url: URL
    let relativePath: String
    let modified: Date
    let size: Int
    /// The first `# Heading`, when the file has one near the top.
    let heading: String?

    var filename: String { url.lastPathComponent }
    /// Relative folder, "" at the root.
    var folder: String { (relativePath as NSString).deletingLastPathComponent }
    var prettyName: String { PrettyName.make(fromFilename: filename) }
}

nonisolated struct FolderNode: Identifiable, Hashable, Sendable {
    /// Relative path, "" for the root.
    let id: String
    let name: String
    var folders: [FolderNode]
    var files: [DocumentFile]

    var fileCount: Int { files.count + folders.reduce(0) { $0 + $1.fileCount } }

    /// Files top to bottom as the tree shows them: a folder's own files
    /// first, then its subfolders. This is the reading order.
    var readingOrder: [DocumentFile] {
        files + folders.flatMap(\.readingOrder)
    }
}

nonisolated enum WorkspaceScanner {
    static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdx", "mdtext"]
    /// Folders that hold dependencies or build output, never agent writing.
    static let skippedFolders: Set<String> = [
        "node_modules", "DerivedData", "build", "Build", "Pods", "Carthage", "dist", "vendor",
        "__pycache__", "venv", "target", "out", "coverage", "SourcePackages",
    ]
    static let fileLimit = 5000

    static func isMarkdown(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    /// Walks the folder. Hidden items, packages and dependency folders are
    /// skipped; folders without any markdown are dropped from the tree.
    static func scan(_ root: URL) -> FolderNode {
        var count = 0
        return scanFolder(root, relative: "", name: root.lastPathComponent, count: &count) ?? FolderNode(
            id: "", name: root.lastPathComponent, folders: [], files: []
        )
    }

    private static func scanFolder(_ url: URL, relative: String, name: String, count: inout Int) -> FolderNode? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey, .isPackageKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var folders: [FolderNode] = []
        var files: [DocumentFile] = []
        let sorted = entries.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for entry in sorted {
            guard count < fileLimit else { break }
            let values = try? entry.resourceValues(forKeys: Set(keys))
            let childRelative = relative.isEmpty ? entry.lastPathComponent : relative + "/" + entry.lastPathComponent
            if values?.isDirectory == true {
                if values?.isPackage == true || skippedFolders.contains(entry.lastPathComponent) { continue }
                if let folder = scanFolder(entry, relative: childRelative, name: entry.lastPathComponent, count: &count),
                   folder.fileCount > 0 {
                    folders.append(folder)
                }
            } else if isMarkdown(entry) {
                count += 1
                files.append(DocumentFile(
                    url: entry,
                    relativePath: childRelative,
                    modified: values?.contentModificationDate ?? .distantPast,
                    size: values?.fileSize ?? 0,
                    heading: firstHeading(of: entry)
                ))
            }
        }
        return FolderNode(id: relative, name: name, folders: folders, files: files)
    }

    /// Files opened one at a time, as one flat folder. Their ids are their
    /// absolute paths; files that are gone are left out.
    /// Keyed by the path each was opened at, which stays its id even when
    /// its bookmark resolves through a different spelling of the path.
    static func scanFiles(_ documents: [String: URL]) -> FolderNode {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        let files = documents.compactMap { path, kept -> DocumentFile? in
            // A fresh URL: one kept between scans caches its dates and sizes.
            let url = URL(fileURLWithPath: kept.path)
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return DocumentFile(
                url: url,
                relativePath: path,
                modified: values.contentModificationDate ?? .distantPast,
                size: values.fileSize ?? 0,
                heading: firstHeading(of: url)
            )
        }
        .sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        return FolderNode(id: "", name: "", folders: [], files: files)
    }

    /// The first ATX `# Heading` in the opening few kilobytes, past front matter.
    static func firstHeading(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4096) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        let body = FrontMatter.split(text).body
        var inFence = false
        for line in body.split(separator: "\n", omittingEmptySubsequences: false).prefix(60) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle() }
            if !inFence, trimmed.hasPrefix("# ") {
                let title = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: #"[*_`]"#, with: "", options: .regularExpression)
                return title.isEmpty ? nil : title
            }
        }
        return nil
    }

    static func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
