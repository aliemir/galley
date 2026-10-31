import SwiftUI

struct WorkspacesColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeader(title: "Workspaces") { EmptyView() }
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
            Image(systemName: workspace.isAvailable ? (isSelected ? "folder.fill" : "folder") : "folder.badge.questionmark")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? palette.accent : palette.ink3)
                .frame(width: 18)
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
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? palette.selection : (isHovered ? palette.hover : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { model.selectWorkspace(workspace.id) }
        .onHover { isHovered = $0 }
        .help(workspace.root.path)
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([workspace.root]) }
            Button("Mark All as Read") {
                model.selectWorkspace(workspace.id)
                model.markAllRead()
            }
            .disabled(workspace.unreadCount == 0)
            Divider()
            Button("Remove Workspace", role: .destructive) { model.removeWorkspace(workspace.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
