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

    /// Muted hues that read on every theme. Stored by name, so the palette
    /// can be retuned without losing anyone's choice.
    static let colors: [(name: String, color: Color)] = [
        ("blue", Color(red: 0.36, green: 0.52, blue: 0.80)), ("teal", Color(red: 0.30, green: 0.62, blue: 0.55)),
        ("green", Color(red: 0.45, green: 0.60, blue: 0.32)), ("gold", Color(red: 0.72, green: 0.58, blue: 0.22)),
        ("orange", Color(red: 0.80, green: 0.50, blue: 0.26)), ("red", Color(red: 0.77, green: 0.36, blue: 0.38)),
        ("pink", Color(red: 0.80, green: 0.42, blue: 0.62)), ("purple", Color(red: 0.60, green: 0.43, blue: 0.75)),
        ("slate", Color(red: 0.42, green: 0.48, blue: 0.62)), ("graphite", Color(red: 0.45, green: 0.45, blue: 0.47)),
    ]

    static func color(named name: String?) -> Color? {
        colors.first { $0.name == name }?.color
    }

    /// A stable pick from the id, for workspaces without a chosen colour.
    static func automaticColor(for id: UUID) -> Color {
        let sum = id.uuidString.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        // The first eight: the greys are for choosing, not for chance.
        return colors[abs(sum) % 8].color
    }

    private var tint: Color { workspace.color }

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
                shape.fill(tint.opacity(isSelected ? 0.32 : 0.16))
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
                    Text(workspace.isOpenedFiles ? "Files opened one at a time" : "Folder on disk: \(workspace.folderName) — never renamed")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            colorRow

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
                    model.setWorkspaceIcon(workspace.isOpenedFiles ? .symbol("doc.on.doc") : .monogram, for: workspace.id)
                    model.setWorkspaceColor(nil, for: workspace.id)
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
    /// Automatic, then the palette: swatches as small circles, the chosen
    /// one ringed.
    private var colorRow: some View {
        let chosen = workspace.record?.color
        // 11 swatches of 22 pt and 4 pt gaps: 282 of the editor's 288 pt.
        return HStack(spacing: 4) {
            swatch(isChosen: chosen == nil, help: "Automatic") {
                model.setWorkspaceColor(nil, for: workspace.id)
            } fill: {
                Circle().fill(WorkspaceIcon.automaticColor(for: workspace.id).opacity(0.35))
                    .overlay(Image(systemName: "wand.and.stars").font(.system(size: 8, weight: .semibold)).foregroundStyle(.primary.opacity(0.7)))
            }
            ForEach(WorkspaceIcon.colors, id: \.name) { entry in
                swatch(isChosen: chosen == entry.name, help: entry.name.capitalized) {
                    model.setWorkspaceColor(entry.name, for: workspace.id)
                } fill: {
                    Circle().fill(entry.color)
                }
            }
        }
    }

    private func swatch<Fill: View>(isChosen: Bool, help: String, action: @escaping () -> Void, @ViewBuilder fill: () -> Fill) -> some View {
        Button(action: action) {
            fill()
                .frame(width: 16, height: 16)
                .padding(3)
                .overlay(Circle().strokeBorder(isChosen ? Color.primary.opacity(0.55) : .clear, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel("\(help) colour")
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

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
