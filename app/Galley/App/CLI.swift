import AppKit
import Foundation

/// `galley`, the command: Galley's own binary run from a terminal, through
/// the symlink `galley install` puts on the PATH. It reads the library the
/// app saves, so an agent can pick up the reader's feedback itself.
nonisolated enum CLI {
    /// Run as a command when called `galley` (the symlink), or with `--cli`.
    static func arguments(_ argv: [String]) -> [String]? {
        if argv.dropFirst().first == "--cli" { return Array(argv.dropFirst(2)) }
        if let first = argv.first, URL(fileURLWithPath: first).lastPathComponent == "galley" { return Array(argv.dropFirst()) }
        return nil
    }

    static let usage = """
    galley — the command line for Galley, a reader for what your agents write.

    Usage:
      galley [path …]                  Open files or folders in Galley (no path: just open it)
      galley feedback [path] [--json]  Print the highlights and notes on a file, or on every
                                       file under a folder (default: the current folder)
      galley feedback clear path … [--addressed]
                                       Clear the feedback on files, or on every file under
                                       folders; --addressed clears only passages that are
                                       no longer in the text
      galley install [folder]          Put `galley` on the PATH (default: /usr/local/bin)
      galley skill install [--global | --project [folder] | --dir folder]
                                       Install the agent skill that teaches agents to read
                                       your feedback (default: --global, ~/.claude/skills)
      galley skill print               Print the skill, for agents that keep skills elsewhere
      galley help                      This text

    """

    static func run(_ arguments: [String]) -> Int32 {
        var arguments = arguments
        let command = arguments.first ?? ""
        if !arguments.isEmpty { arguments.removeFirst() }
        switch command {
        case "feedback": return feedback(arguments)
        case "install": return install(arguments.first)
        case "skill": return skill(arguments)
        case "open": return open(arguments)
        case "help", "-h", "--help": print(usage, terminator: ""); return 0
        case "--version", "version":
            // Through the symlink, Bundle.main is the link's folder: ask the app.
            print(Bundle(url: appURL)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
            return 0
        case "": return open([])
        default:
            if command.hasPrefix("-") { return fail("Unknown option \(command). See `galley help`.") }
            return open([command] + arguments)
        }
    }

    // MARK: Open

    static func open(_ paths: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appURL.path] + paths.map { absolute($0).path }
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return fail("Could not open Galley: \(error.localizedDescription)")
        }
    }

    // MARK: Feedback

    /// The feedback on `path` (a file, or every file under a folder) in the
    /// form Copy Feedback gives, minus passages no longer in the text.
    static func feedback(_ arguments: [String]) -> Int32 {
        if arguments.first == "clear" { return clear(Array(arguments.dropFirst())) }
        let json = arguments.contains("--json")
        let target = absolute(arguments.first { !$0.hasPrefix("-") } ?? ".")
        let state: LibraryState
        do {
            state = try LibraryLocation.read()
        } catch {
            return fail("Galley has no library yet: open a folder in Galley first.")
        }
        let files = collect(state, under: target)
        if json {
            let items = files.map { ["path": $0.path, "items": $0.items.map { ["text": $0.text, "note": $0.note ?? "", "section": $0.section] as [String: Any] }] as [String: Any] }
            let data = (try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])) ?? Data("[]".utf8)
            print(String(decoding: data, as: UTF8.self))
            return 0
        }
        guard !files.isEmpty else {
            FileHandle.standardError.write(Data("No feedback on \(target.path).\n".utf8))
            return 0
        }
        print(Feedback.format(files), terminator: "")
        return 0
    }

    static func collect(_ state: LibraryState, under target: URL) -> [Feedback.File] {
        let prefix = target.standardizedFileURL.path
        var files: [Feedback.File] = []
        for workspace in state.workspaces {
            for (id, record) in workspace.files {
                guard let highlights = record.highlights, !highlights.isEmpty else { continue }
                // Opened files are keyed by their absolute path.
                let path = workspace.kind == "files" ? id : URL(fileURLWithPath: workspace.path).appendingPathComponent(id).standardizedFileURL.path
                guard path == prefix || path.hasPrefix(prefix.hasSuffix("/") ? prefix : prefix + "/") else { continue }
                let source = WorkspaceScanner.read(URL(fileURLWithPath: path)) ?? ""
                let items = Feedback.items(highlights, in: source)
                if !items.isEmpty { files.append(Feedback.File(path: path, items: items)) }
            }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Clears feedback by path. Galley holds the library while it runs, so
    /// a running Galley is asked to do it (and shows the change at once);
    /// otherwise the library file is changed here.
    static func clear(_ arguments: [String]) -> Int32 {
        let addressedOnly = arguments.contains("--addressed")
        let paths = arguments.filter { !$0.hasPrefix("-") }.map { absolute($0).path }
        guard !paths.isEmpty else {
            return fail("Name the files or folders to clear, e.g. `galley feedback clear plan.md` or `galley feedback clear .`")
        }
        let result: FeedbackClearing.Result
        if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
            guard let answer = FeedbackRequest.send(paths: paths, addressedOnly: addressedOnly) else {
                return fail("Galley did not answer. Try again, or quit Galley and run this again.")
            }
            result = answer
        } else {
            do {
                var state = try LibraryLocation.read()
                result = FeedbackClearing.apply(to: &state, paths: paths, addressedOnly: addressedOnly)
                if result.highlights > 0 { try LibraryLocation.write(state) }
            } catch {
                return fail("Could not change Galley's library: \(error.localizedDescription)")
            }
        }
        if result.highlights == 0 {
            print(addressedOnly ? "Nothing addressed to clear." : "No feedback there to clear.")
        } else {
            let marks = result.highlights == 1 ? "1 highlight" : "\(result.highlights) highlights"
            print("Cleared \(marks) on \(result.files == 1 ? "1 file" : "\(result.files) files").")
        }
        return 0
    }

    static let bundleIdentifier = "com.aliemir.galley"

    // MARK: Install

    /// A symlink to this binary, named `galley`, in a folder on the PATH.
    static func install(_ folder: String?) -> Int32 {
        let directory = absolute(folder ?? "/usr/local/bin")
        let target = directory.appendingPathComponent("galley")
        switch link(at: target) {
        case .done:
            print("Installed \(target.path) → \(executableURL.path)")
            let path = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
            if !path.contains(directory.path) {
                print("\(directory.path) is not on your PATH; add it to your shell profile to run `galley` anywhere.")
            }
            return 0
        case .occupied:
            return fail("\(target.path) exists and is not a link to Galley; remove it first.")
        case .denied:
            return fail("""
            \(directory.path) needs administrator rights. Run:
              sudo "\(executableURL.path)" --cli install
            or install into a folder of your own:
              galley install ~/.local/bin
            """)
        }
    }

    enum LinkResult { case done, occupied, denied }

    static func link(at link: URL) -> LinkResult {
        let fileManager = FileManager.default
        if (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) != nil {
            // An older link (a moved or renamed app) is replaced.
            guard (try? fileManager.removeItem(at: link)) != nil else { return .denied }
        } else if fileManager.fileExists(atPath: link.path) {
            return .occupied
        }
        do {
            try fileManager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.createSymbolicLink(at: link, withDestinationURL: executableURL)
            return .done
        } catch {
            return .denied
        }
    }

    // MARK: Skill

    static func skill(_ arguments: [String]) -> Int32 {
        guard let action = arguments.first else { return fail("Usage: galley skill install [--global | --project [folder] | --dir folder], or galley skill print") }
        if action == "print" {
            print(AgentSkill.text, terminator: "")
            return 0
        }
        guard action == "install" else { return fail("Unknown skill command \(action). See `galley help`.") }
        let options = Array(arguments.dropFirst())
        let folder: URL
        if let index = options.firstIndex(of: "--dir"), index + 1 < options.count {
            folder = absolute(options[index + 1])
        } else if let index = options.firstIndex(of: "--project") {
            let next = index + 1 < options.count && !options[index + 1].hasPrefix("-") ? options[index + 1] : "."
            folder = AgentSkill.folder(in: absolute(next))
        } else {
            folder = AgentSkill.globalFolder
        }
        do {
            let file = try AgentSkill.install(into: folder)
            print("Installed the Galley skill: \(file.path)")
            return 0
        } catch {
            return fail("Could not write the skill into \(folder.path): \(error.localizedDescription)")
        }
    }

    // MARK: Helpers

    /// This binary, wherever the symlink that ran it points.
    static var executableURL: URL {
        (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
    }

    /// Galley.app, three levels up from Contents/MacOS/Galley.
    static var appURL: URL {
        executableURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func absolute(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return URL(fileURLWithPath: expanded, relativeTo: base).standardizedFileURL
    }

    @discardableResult
    static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data(("galley: " + message + "\n").utf8))
        return 1
    }
}

/// `galley feedback clear` asking a running Galley to clear: a distributed
/// notification with the paths, answered by one with the counts.
nonisolated enum FeedbackRequest {
    static let request = Notification.Name("com.aliemir.galley.clearFeedback")
    static let reply = Notification.Name("com.aliemir.galley.clearedFeedback")

    static func send(paths: [String], addressedOnly: Bool, timeout: TimeInterval = 4) -> FeedbackClearing.Result? {
        let id = UUID().uuidString
        let center = DistributedNotificationCenter.default()
        var answer: FeedbackClearing.Result?
        let observer = center.addObserver(forName: reply, object: id, queue: nil) { note in
            let info = note.userInfo ?? [:]
            answer = FeedbackClearing.Result(highlights: info["highlights"] as? Int ?? 0, files: info["files"] as? Int ?? 0)
        }
        defer { center.removeObserver(observer) }
        center.postNotificationName(request, object: id, userInfo: ["paths": paths, "addressedOnly": addressedOnly], deliverImmediately: true)
        let deadline = Date().addingTimeInterval(timeout)
        while answer == nil, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return answer
    }
}

/// The skill that teaches an agent to read the reader's feedback with
/// `galley feedback`. Installed by `galley skill install` or from the app.
nonisolated enum AgentSkill {
    static var globalFolder: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/skills/galley", isDirectory: true)
    }

    static func folder(in project: URL) -> URL {
        project.appendingPathComponent(".claude/skills/galley", isDirectory: true)
    }

    @discardableResult
    static func install(into folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("SKILL.md")
        try Data(text.utf8).write(to: file, options: .atomic)
        return file
    }

    static let text = """
    ---
    name: galley
    description: Read the user's feedback on Markdown files you wrote — passages they highlighted and notes they left in Galley, their Markdown reader. Use when the user says they left feedback, comments, notes or highlights in Galley, or asks you to address their feedback on a plan, spec or other Markdown file.
    ---

    # Galley feedback

    The user reads the Markdown you write in **Galley**, a read-only reader.
    While reading they mark it up: they highlight passages and often add a
    note saying what they want. Galley never changes the files — the feedback
    lives in Galley, and you read it with the `galley` command.

    ## Read it

    ```sh
    galley feedback path/to/file.md   # one file
    galley feedback path/to/folder    # every file under a folder
    galley feedback                   # the current folder
    galley feedback --json            # the same, as JSON
    ```

    The output is Markdown: for each file, its absolute path as a heading,
    then numbered items — where the passage is (`Marked in Rollout › Token
    shape`, the headings it sits under), the passage quoted, and under it
    the user's note when they wrote one. No output (and "No feedback on …" on
    stderr) means there is none.

    ## Act on it

    - Each item points at a passage in that file. Find it, and change the
      file to do what the note asks. A highlight without a note means "look
      at this again": reconsider the passage, and say what you did.
    - Work through every item, then tell the user briefly what you changed for
      each, by its number.
    - Passages you rewrite drop out of `galley feedback` by themselves (Galley
      shows them to the user as likely addressed), so running it again shows
      what is left.

    ## Clear it when you are done

    ```sh
    galley feedback clear path/to/file.md            # all feedback on a file
    galley feedback clear path/to/folder             # on every file under a folder
    galley feedback clear path/to/file.md --addressed  # only passages you rewrote
    ```

    Clear a file's feedback once you have dealt with every item on it, and
    only the files you worked on — clearing is not undoable. If you left an
    item open (a question back to the user, a change you disagreed with), use
    `--addressed`, or leave that file alone and say so. Never edit Galley's
    own data any other way.

    ## If `galley` is not found

    Ask the user to choose **Galley → Install Command Line Tool…**, or to run
    `/Applications/Galley.app/Contents/MacOS/Galley --cli install`.

    """
}
