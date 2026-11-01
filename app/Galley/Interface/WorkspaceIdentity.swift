import SwiftUI

/// A workspace's icon: the reader's symbol or emoji, or a monogram of its
/// name on a tint of its own, so workspaces tell apart at a glance.
struct WorkspaceIcon: View {
    enum Kind: Equatable {
        case monogram
        case symbol(String)
        case emoji(String)

        init(stored: String?) {
            guard let stored else { self = .monogram; return }
            if stored.hasPrefix("symbol:") { self = .symbol(String(stored.dropFirst(7))) }
            else if stored.hasPrefix("emoji:"), stored.count > 6 { self = .emoji(String(stored.dropFirst(6))) }
            else { self = .monogram }
        }

        var stored: String? {
            switch self {
            case .monogram: nil
            case .symbol(let name): "symbol:" + name
            case .emoji(let character): "emoji:" + character
            }
        }
    }

    let workspace: Workspace
    var size: CGFloat = 18
    var isSelected = false
    @Environment(\.palette) private var palette

    /// Muted hues that read on every theme, picked by a stable hash of the id.
    private static let tints: [Color] = [
        Color(red: 0.36, green: 0.52, blue: 0.80), Color(red: 0.30, green: 0.62, blue: 0.55),
        Color(red: 0.78, green: 0.50, blue: 0.27), Color(red: 0.64, green: 0.42, blue: 0.72),
        Color(red: 0.75, green: 0.38, blue: 0.42), Color(red: 0.45, green: 0.58, blue: 0.32),
        Color(red: 0.42, green: 0.48, blue: 0.62), Color(red: 0.70, green: 0.58, blue: 0.25),
    ]

    private var tint: Color {
        let sum = workspace.id.uuidString.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return Self.tints[abs(sum) % Self.tints.count]
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        ZStack {
            switch workspace.icon {
            case .monogram:
                shape.fill(tint.opacity(isSelected ? 0.9 : 0.22))
                Text(monogram)
                    .font(.system(size: size * 0.52, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : tint)
            case .symbol(let name):
                shape.fill(tint.opacity(isSelected ? 0.9 : 0.16))
                Image(systemName: name)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : tint)
            case .emoji(let character):
                shape.fill(palette.ink.opacity(isSelected ? 0.12 : 0.05))
                Text(character)
                    .font(.system(size: size * 0.62))
            }
        }
        .frame(width: size, height: size)
        .opacity(workspace.isAvailable ? 1 : 0.45)
        .accessibilityHidden(true)
    }

    private var monogram: String {
        let letter = workspace.name.first { $0.isLetter || $0.isNumber }
        return letter.map { String($0).uppercased() } ?? "•"
    }
}

/// Name and icon for a workspace. Galley's own: the folder keeps its name.
struct WorkspaceIdentityEditor: View {
    let workspace: Workspace
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var loadedName = ""
    @State private var emoji = ""

    private static let symbols = [
        "folder", "doc.text", "book", "books.vertical", "bookmark", "star", "flag", "tag",
        "tray", "archivebox", "briefcase", "hammer", "wrench.and.screwdriver", "gearshape",
        "terminal", "chevron.left.forwardslash.chevron.right", "cpu", "server.rack", "globe", "sparkles",
        "lightbulb", "brain", "graduationcap", "person.2", "chart.bar", "paintbrush",
        "camera", "music.note", "leaf", "flame", "bolt", "heart",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                WorkspaceIcon(workspace: workspace, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    TextField(workspace.defaultName, text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .onSubmit { commitName() }
                    Text("Folder on disk: \(workspace.folderName) — never renamed")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 8), spacing: 4) {
                choice(.monogram) {
                    Text(String(workspace.defaultName.first ?? "A").uppercased())
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .help("Monogram")
                ForEach(Self.symbols, id: \.self) { symbol in
                    choice(.symbol(symbol)) {
                        Image(systemName: symbol).font(.system(size: 13))
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Or type an emoji", text: $emoji)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                    .onChange(of: emoji) { _, value in
                        // One character: the last one typed or picked.
                        guard let last = value.last else { return }
                        let character = String(last)
                        if value != character { emoji = character }
                        if last.unicodeScalars.first?.properties.isEmoji == true, !last.isNumber {
                            model.setWorkspaceIcon(.emoji(character), for: workspace.id)
                        }
                    }
                Button("Emoji & Symbols") { NSApp.orderFrontCharacterPalette(nil) }
                    .controlSize(.small)
                Spacer()
                Button("Reset") {
                    name = ""
                    loadedName = ""
                    emoji = ""
                    model.setWorkspaceName(nil, for: workspace.id)
                    model.setWorkspaceIcon(.monogram, for: workspace.id)
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            name = workspace.record?.customName ?? ""
            loadedName = name
            if case .emoji(let character) = workspace.icon { emoji = character }
        }
        .onDisappear { commitName() }
    }

    /// Saves the name only if it was edited here, so closing the editor
    /// never overwrites a name set elsewhere meanwhile.
    private func commitName() {
        guard name != loadedName else { return }
        model.setWorkspaceName(name, for: workspace.id)
        loadedName = name
    }

    private func choice<Label: View>(_ kind: WorkspaceIcon.Kind, @ViewBuilder label: () -> Label) -> some View {
        let isChosen = workspace.icon == kind
        return Button {
            emoji = ""
            model.setWorkspaceIcon(kind, for: workspace.id)
        } label: {
            label()
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isChosen ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isChosen ? Color.accentColor : .clear, lineWidth: 1.5)
                )
                .foregroundStyle(isChosen ? Color.accentColor : .primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
