import Foundation

/// Galley ran in the App Sandbox until 2026-11-01, so a reader's library and
/// settings may still sit in the app's old container. The first launch
/// without the sandbox copies them out — copies, so the container keeps its
/// own until the reader deletes it.
nonisolated enum SandboxMigration {
    static let container = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Containers/com.aliemir.galley/Data/Library", isDirectory: true)

    /// Only the installed app's own data is migrated. The container is the
    /// release's (`com.aliemir.galley`); a Debug build is its own Galley and
    /// starts empty rather than with a copy of the reader's old library.
    static var applies: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    /// Settings: every key the container had and the new place lacks.
    static func defaults(_ defaults: UserDefaults = .standard) {
        guard applies else { return }
        guard !defaults.bool(forKey: "migratedFromSandbox") else { return }
        let plist = container.appendingPathComponent("Preferences/com.aliemir.galley.plist")
        let data: Data
        do {
            data = try Data(contentsOf: plist)
        } catch CocoaError.fileReadNoSuchFile {
            // Never sandboxed here: nothing to bring over.
            defaults.set(true, forKey: "migratedFromSandbox")
            return
        } catch {
            debugLog("[migration] settings unreadable: \(error)")
            // Unreadable for now (macOS guards app containers from other
            // processes, such as a terminal that started Galley): try again
            // on the next launch rather than give up on the settings.
            return
        }
        guard let old = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: "migratedFromSandbox")
    }

    /// The library and its snapshots, into `directory`, unless it already
    /// has a library of its own.
    static func library(into directory: URL) {
        guard applies else { return }
        let fileManager = FileManager.default
        let source = container.appendingPathComponent("Application Support/Galley", isDirectory: true)
        guard !fileManager.fileExists(atPath: directory.appendingPathComponent("library.json").path),
              fileManager.fileExists(atPath: source.appendingPathComponent("library.json").path) else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for item in (try? fileManager.contentsOfDirectory(atPath: source.path)) ?? [] {
            let target = directory.appendingPathComponent(item)
            // An empty folder (Snapshots, made before the copy) is filled.
            if (try? fileManager.contentsOfDirectory(atPath: target.path))?.isEmpty == true {
                try? fileManager.removeItem(at: target)
            }
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            try? fileManager.copyItem(at: source.appendingPathComponent(item), to: target)
        }
    }
}
