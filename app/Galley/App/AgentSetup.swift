import AppKit
import Observation

/// Whether the `galley` command and the agent skill are installed, and
/// putting them in or taking them out. Shared by the top strip's panel,
/// Settings → Agents and the Galley menu.
@MainActor
@Observable
final class AgentSetup {
    enum CommandStatus: Equatable {
        case missing
        /// A link to this copy of Galley.
        case installed(String)
        /// A link to another copy (a moved app, a development build).
        case elsewhere(String)
    }

    enum SkillStatus: Equatable { case missing, installed, outdated }

    private(set) var command: CommandStatus = .missing
    private(set) var skill: SkillStatus = .missing

    /// Where `galley install` and package managers put commands.
    static let folders = ["/usr/local/bin", "/opt/homebrew/bin", "~/.local/bin", "~/bin"]
        .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }

    var isComplete: Bool {
        if case .installed = command { return skill == .installed }
        return false
    }

    var skillFile: URL { AgentSkill.globalFolder.appendingPathComponent("SKILL.md") }

    func refresh() {
        let fileManager = FileManager.default
        var found = CommandStatus.missing
        for folder in Self.folders {
            let link = folder.appendingPathComponent("galley")
            guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: link.path) else { continue }
            let target = URL(fileURLWithPath: destination, relativeTo: folder).standardizedFileURL.resolvingSymlinksInPath()
            if target.path == CLI.executableURL.path {
                found = .installed(link.path)
                break
            }
            if target.path.contains(".app/Contents/MacOS/Galley"), found == .missing { found = .elsewhere(link.path) }
        }
        command = found
        if let text = try? String(contentsOf: skillFile, encoding: .utf8) {
            skill = text == AgentSkill.text ? .installed : .outdated
        } else {
            skill = .missing
        }
    }

    // MARK: The command

    /// Links `galley` into /usr/local/bin, asking for the administrator
    /// password when the folder needs it. Returns what went wrong, if
    /// anything; nil also when the reader cancelled the password.
    @discardableResult
    func installCommand() -> String? {
        defer { refresh() }
        // A link to another copy goes first, wherever it is.
        if case .elsewhere(let path) = command, let problem = remove(path) { return problem }
        let link = URL(fileURLWithPath: "/usr/local/bin/galley")
        switch CLI.link(at: link) {
        case .done:
            return nil
        case .occupied:
            return "/usr/local/bin/galley is another program; remove it first."
        case .denied:
            return Self.asAdministrator("mkdir -p /usr/local/bin && ln -sfn \(Self.quoted(CLI.executableURL.path)) \(Self.quoted(link.path))")
        }
    }

    @discardableResult
    func removeCommand() -> String? {
        defer { refresh() }
        switch command {
        case .installed(let path), .elsewhere(let path): return remove(path)
        case .missing: return nil
        }
    }

    /// Removes a `galley` link — never anything that is not a link.
    private func remove(_ path: String) -> String? {
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil else { return nil }
        if (try? FileManager.default.removeItem(atPath: path)) != nil { return nil }
        return Self.asAdministrator("rm -f \(Self.quoted(path))")
    }

    // MARK: The skill

    @discardableResult
    func installSkill() -> String? {
        defer { refresh() }
        do {
            try AgentSkill.install(into: AgentSkill.globalFolder)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @discardableResult
    func removeSkill() -> String? {
        defer { refresh() }
        // Only a folder that holds Galley's skill.
        guard let text = try? String(contentsOf: skillFile, encoding: .utf8), text.hasPrefix("---\nname: galley") else { return nil }
        do {
            try FileManager.default.removeItem(at: AgentSkill.globalFolder)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Administrator

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Runs a shell command with the administrator password prompt, as VS
    /// Code does for `code`. nil on success or when the prompt is cancelled.
    private static func asAdministrator(_ command: String) -> String? {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
        guard let error, (error[NSAppleScript.errorNumber] as? Int) != -128 else { return nil }
        return (error[NSAppleScript.errorMessage] as? String) ?? "Run `galley install ~/.local/bin` in Terminal instead."
    }
}
