import SwiftUI

struct WorkspacesColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        if model.settings.workspacesAsIcons {
            WorkspaceRail()
        } else {
            list
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ColumnHeader(title: "Workspaces") {
                Menu {
                    Button("Show as Icons (⌥⌘4)") { model.settings.workspacesAsIcons = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.ink3)
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(model.workspaces) { workspace in
                        WorkspaceRow(workspace: workspace, isSelected: workspace.id == model.selectedWorkspaceID)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)
            }
            .scrollIndicators(.never)
            Button {
                model.openFolderPanel()
            } label: {
                Label("Open Folder…", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open a folder as a workspace (⌘O)")
        }
    }
}

private struct WorkspaceRow: View {
    let workspace: Workspace
    let isSelected: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 9) {
            WorkspaceIcon(workspace: workspace, size: 20, isSelected: isSelected)
            Text(workspace.name)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(workspace.isAvailable ? palette.ink : palette.ink3)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if workspace.unreadCount > 0 {
                Text("\(workspace.unreadCount)")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.unread)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(palette.unread.opacity(0.12)))
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? palette.selection : (isHovered ? palette.hover : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { model.selectWorkspace(workspace.id) }
        .onHover { isHovered = $0 }
        .help(workspace.root.path)
        .contextMenu { WorkspaceMenu(workspace: workspace) }
        .identityEditor(for: workspace, arrowEdge: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Workspaces as a column of icons: the same list, a sliver of the width.
private struct WorkspaceRail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: MainView.bandHeight + 10)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.workspaces) { workspace in
                        RailTile(workspace: workspace, isSelected: workspace.id == model.selectedWorkspaceID)
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            VStack(spacing: 2) {
                railButton("plus", help: "Open Folder… (⌘O)") { model.openFolderPanel() }
                railButton("sidebar.squares.left", help: "Show Workspace Names (⌥⌘4)") {
                    model.settings.workspacesAsIcons = false
                }
            }
            .padding(.bottom, 10)
        }
        .background(alignment: .top) { TitleBand() }
    }

    private func railButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.ink3)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct RailTile: View {
    let workspace: Workspace
    let isSelected: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var isHovered = false

    var body: some View {
        WorkspaceIcon(workspace: workspace, size: 34, isSelected: isSelected)
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? palette.accent.opacity(0.55) : (isHovered ? palette.rule : .clear), lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                if workspace.unreadCount > 0 {
                    Circle()
                        .fill(palette.unread)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(palette.sidebar, lineWidth: 1.5))
                        .offset(x: 1, y: -1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.selectWorkspace(workspace.id) }
            .onHover { isHovered = $0 }
            .help(workspace.unreadCount > 0 ? "\(workspace.name) — \(workspace.unreadCount) unread" : workspace.name)
            .contextMenu { WorkspaceMenu(workspace: workspace) }
            .identityEditor(for: workspace, arrowEdge: .trailing)
            .accessibilityElement()
            .accessibilityLabel(workspace.name)
            .accessibilityValue(workspace.unreadCount > 0 ? "\(workspace.unreadCount) unread" : "")
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { model.selectWorkspace(workspace.id) }
    }
}

private struct WorkspaceMenu: View {
    let workspace: Workspace
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Name and Icon…") { model.customizingWorkspace = workspace.id }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([workspace.root]) }
        Button("Mark All as Read") {
            model.selectWorkspace(workspace.id)
            model.markAllRead()
        }
        .disabled(workspace.unreadCount == 0)
        Divider()
        Button("Remove Workspace", role: .destructive) { model.removeWorkspace(workspace.id) }
    }
}

private extension View {
    /// The name-and-icon popover, opened from the workspace's context menu.
    func identityEditor(for workspace: Workspace, arrowEdge: Edge) -> some View {
        modifier(IdentityEditorPresenter(workspace: workspace, arrowEdge: arrowEdge))
    }
}

private struct IdentityEditorPresenter: ViewModifier {
    let workspace: Workspace
    let arrowEdge: Edge
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content.popover(
            isPresented: Binding(
                get: { model.customizingWorkspace == workspace.id },
                set: { if !$0, model.customizingWorkspace == workspace.id { model.customizingWorkspace = nil } }
            ),
            arrowEdge: arrowEdge
        ) {
            WorkspaceIdentityEditor(workspace: workspace)
                .environment(model)
                .environment(\.palette, palette)
        }
    }
}
