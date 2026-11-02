import Darwin
import Foundation

/// Agents waiting for the reader's feedback: each `galley feedback --wait`
/// or `--watch` keeps a small file in the library's `Watchers` folder while
/// it runs — which folder it watches, and the agent that started it — and
/// the app reads them to say so on the Save Feedback button. The command
/// never touches `library.json` for this, and the app only reads.
nonisolated enum Watchers {
    struct Entry: Codable, Hashable, Sendable {
        var pid: Int32
        /// The folder or file the command watches, absolute.
        var path: String
        /// "Claude Code", "Codex"…; nil when the command was run some other way.
        var agent: String?
        var started: Date
    }

    /// A watcher is gone once its file has not been refreshed for this long
    /// (a command killed outright cannot remove its own file).
    static let staleAfter: TimeInterval = 15
    static let beatEvery: TimeInterval = 5

    static var folder: URL { LibraryLocation.directory.appendingPathComponent("Watchers", isDirectory: true) }

    static func file(for pid: Int32) -> URL { folder.appendingPathComponent("\(pid).json") }

    // MARK: The command's side

    /// Says this command is watching `path`, until `stop()` or the process
    /// is interrupted or terminated.
    final class Presence: @unchecked Sendable {
        private let entry: Entry
        private let url: URL
        private var lastBeat = Date.distantPast
        private var signals: [DispatchSourceSignal] = []

        init(path: String) {
            entry = Entry(pid: getpid(), path: path, agent: Watchers.agentName(), started: Date())
            url = Watchers.file(for: entry.pid)
            beat()
            // Stopped by a monitor or Ctrl-C: take the file away first.
            for number in [SIGINT, SIGTERM, SIGHUP] {
                signal(number, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
                let url = url
                source.setEventHandler {
                    try? FileManager.default.removeItem(at: url)
                    exit(128 + number)
                }
                source.resume()
                signals.append(source)
            }
        }

        /// Refreshes the file every few seconds; call it as often as you like.
        func beat() {
            guard Date().timeIntervalSince(lastBeat) >= Watchers.beatEvery else { return }
            lastBeat = Date()
            try? FileManager.default.createDirectory(at: Watchers.folder, withIntermediateDirectories: true)
            if let data = try? JSONEncoder.library.encode(entry) { try? data.write(to: url, options: .atomic) }
        }

        func stop() {
            signals.forEach { $0.cancel() }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// The agent this command runs under, from the processes above it: the
    /// first one whose name or path names a known agent.
    static func agentName() -> String? {
        let known: [(String, String)] = [
            ("claude", "Claude Code"), ("codex", "Codex"), ("gemini", "Gemini CLI"),
            ("cursor-agent", "Cursor"), ("cursor", "Cursor"), ("opencode", "opencode"), ("amp", "Amp"), ("aider", "Aider"),
        ]
        var pid = getppid()
        for _ in 0..<8 where pid > 1 {
            let names = processNames(pid)
            if let match = known.first(where: { names.contains($0.0) }) { return match.1 }
            pid = parent(of: pid)
        }
        return nil
    }

    /// A process's name and its executable's file name, lowercased — enough
    /// to tell a `claude` from a `zsh`. Whole names, so "sample" is not Amp.
    private static func processNames(_ pid: Int32) -> Set<String> {
        var name = [CChar](repeating: 0, count: 256)
        proc_name(pid, &name, UInt32(name.count))
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        proc_pidpath(pid, &path, UInt32(path.count))
        let nameText = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let pathText = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        // File names only: a folder named after an agent is not one. The
        // arguments too — Claude Code's executable is a version number
        // (…/claude/versions/2.1.316) named `claude` only in argv[0], and an
        // agent written in JavaScript is `node …/gemini`.
        let names = [nameText, pathText] + arguments(pid).prefix(2)
        return Set(names.map { ($0 as NSString).lastPathComponent.lowercased() }.filter { !$0.isEmpty })
    }

    /// A process's first arguments, from the kernel (KERN_PROCARGS2: argc,
    /// the executable's path, padding, then argv).
    private static func arguments(_ pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }   // the executable's path
        while index < size, buffer[index] == 0 { index += 1 }   // padding
        var result: [String] = []
        while index < size, result.count < 2 {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            result.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return result
    }

    private static func parent(of pid: Int32) -> Int32 {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return 0 }
        return Int32(info.pbi_ppid)
    }

    // MARK: The app's side

    /// The watchers that are still there: the process alive and its file
    /// fresh. Leftovers of killed commands are tidied away.
    static func live() -> [Entry] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var entries: [Entry] = []
        for url in files where url.pathExtension == "json" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            guard let data = try? Data(contentsOf: url), let entry = try? JSONDecoder.library.decode(Entry.self, from: data) else { continue }
            let alive = kill(entry.pid, 0) == 0 || errno == EPERM
            if alive, Date().timeIntervalSince(modified) < staleAfter {
                entries.append(entry)
            } else if Date().timeIntervalSince(modified) > staleAfter {
                try? fileManager.removeItem(at: url)
            }
        }
        return entries.sorted { $0.started < $1.started }
    }
}
