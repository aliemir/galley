import SwiftUI

/// Connecting agents to Galley: the command, the skill, and what to say.
/// The top strip's panel shows it until both are in (or the reader says
/// not to); Settings → Agents keeps it, with Remove.
struct AgentSetupView: View {
    enum Place { case panel, settings }

    let place: Place
    @Environment(AppModel.self) private var model
    @AppStorage("hideAgentButton", store: Preferences.store) private var hideButton = false
    @State private var problem: String?

    private var setup: AgentSetup { model.agents }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if place == .panel {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Let your agents read your feedback", systemImage: "terminal")
                        .font(.system(size: 14, weight: .semibold))
                    intro
                }
            } else {
                intro
            }

            step(
                number: 1,
                title: "The galley command",
                detail: commandDetail,
                done: { if case .installed = setup.command { true } else { false } }()
            ) {
                switch setup.command {
                case .missing:
                    Button("Install") { problem = setup.installCommand() }
                case .elsewhere:
                    Button("Point It Here") { problem = setup.installCommand() }
                case .installed:
                    if place == .settings {
                        Button("Remove") { problem = setup.removeCommand() }
                    }
                }
            }

            step(
                number: 2,
                title: "The agent skill, for all projects",
                detail: skillDetail,
                done: setup.skill == .installed
            ) {
                switch setup.skill {
                case .missing: Button("Install Globally") { problem = setup.installSkill() }
                case .outdated: Button("Update") { problem = setup.installSkill() }
                case .installed:
                    if place == .settings {
                        Button("Remove") { problem = setup.removeSkill() }
                    }
                }
            }

            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                caption("Then ask your agent")
                CopyField(text: "Address my feedback in Galley.", monospaced: false)
                caption("The skill for one project only (.agents and .claude), or its text for other agents")
                CopyField(text: "galley skill install --project")
                CopyField(text: "galley skill print")
            }

            if place == .panel {
                Divider()
                HStack {
                    Toggle("Don't show this button again", isOn: $hideButton)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))
                    Spacer()
                    Text("Always in Settings → Agents")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(place == .panel ? 18 : 22)
        .frame(width: place == .panel ? 400 : nil)
        .onAppear { setup.refresh() }
    }

    private var intro: some View {
        Text("With the `galley` command, an agent can read the passages you highlight and the notes you write — with the file and section of each — and clear them once it has dealt with them. Your Markdown files are never touched.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var commandDetail: String {
        switch setup.command {
        case .missing: "Puts `galley` in /usr/local/bin, like VS Code's `code`. Asks for your password if the folder needs it."
        case .installed(let path): "Installed at \(path)."
        case .elsewhere(let path): "\(path) opens another copy of Galley."
        }
    }

    private var skillDetail: String {
        let folder = (AgentSkill.globalFolder.path as NSString).abbreviatingWithTildeInPath
        let agents = setup.skillAgents.isEmpty ? "" : " For " + ListFormatter.localizedString(byJoining: setup.skillAgents) + "."
        switch setup.skill {
        case .missing:
            return "Teaches your agents how to read your feedback and clear what they finished. Goes in \(folder) for every project, linked for Claude Code and Gemini CLI. For one project only, use the command below."
        case .installed: return "Installed in \(folder).\(agents)"
        case .outdated: return "In \(folder), but older, or not linked for every agent here."
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private func step<Action: View>(number: Int, title: String, detail: String, done: Bool, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(done ? Color.green.opacity(0.18) : Color.primary.opacity(0.07))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
                } else {
                    Text("\(number)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(.init(detail))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action()
                .controlSize(.small)
        }
    }
}

/// A line to paste somewhere else, with a button that copies it.
struct CopyField: View {
    let text: String
    var monospaced = true
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(monospaced ? .system(size: 11.5, design: .monospaced) : .system(size: 12))
                .textSelection(.enabled)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                withAnimation(.snappy(duration: 0.15)) { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.3))
                    withAnimation(.easeOut(duration: 0.2)) { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(copied ? Color.green : .secondary)
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy")
            .accessibilityLabel("Copy \(text)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}
