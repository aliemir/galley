import SwiftUI

struct FilesColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @FocusState private var isFocused: Bool
    @AppStorage("filesSort") private var sort: FileSort = .folders

    enum FileSort: String { case folders, recent }

    var body: some View {
        VStack(spacing: 0) {
            if let workspace = model.selectedWorkspace {
                ColumnHeader(title: workspace.name, subtitle: subtitle(workspace)) {
                    menu(workspace)
                }
                content(workspace)
            } else {
                ColumnHeader(title: "Files") { EmptyView() }
                Spacer()
            }
        }
    }

    private func subtitle(_ workspace: Workspace) -> String {
        let count = workspace.files.count
        let files = count == 1 ? "1 file" : "\(count) files"
        let unread = workspace.unreadCount
        return unread > 0 ? "\(files) · \(unread) to read" : files
    }

    private func menu(_ workspace: Workspace) -> some View {
        Menu {
            Picker("Sort", selection: $sort) {
                Text("Folders").tag(FileSort.folders)
                Text("Recently Changed").tag(FileSort.recent)
            }
            .pickerStyle(.inline)
            Divider()
            Button("Mark All as Read") { model.markAllRead() }
                .disabled(workspace.unreadCount == 0)
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([workspace.root]) }
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
        .help("Sort and actions")
    }

    @ViewBuilder
    private func content(_ workspace: Workspace) -> some View {
        if workspace.hasScanned, workspace.files.isEmpty {
            VStack(spacing: 6) {
                Text("No Markdown here yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.ink2)
                Text("New files show up as soon as they are written.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.ink3)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        let feed = workspace.feed
                        if !feed.isEmpty, sort == .folders {
                            SectionLabel(title: "Unread", count: feed.count)
                                .padding(.horizontal, -8)
                            ForEach(feed) { file in
                                FileRow(file: file, workspace: workspace, depth: 0, showsLocation: true)
                                    .id("feed/" + file.id)
                            }
                            SectionLabel(title: "All files")
                                .padding(.horizontal, -8)
                        }
                        if sort == .folders {
                            FolderContents(folder: workspace.tree, workspace: workspace, depth: 0)
                        } else {
                            ForEach(workspace.files.sorted { $0.modified > $1.modified }) { file in
                                FileRow(file: file, workspace: workspace, depth: 0, showsLocation: true)
                                    .id(file.id)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.automatic)
                .onChange(of: model.current?.file.id) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: nil) }
                }
            }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .simultaneousGesture(TapGesture().onEnded { isFocused = true })
            .onKeyPress(.downArrow) { step(1, in: workspace); return .handled }
            .onKeyPress(.upArrow) { step(-1, in: workspace); return .handled }
            .onKeyPress(.rightArrow) { model.focusPage(); return .handled }
            .onKeyPress(.return) { model.focusPage(); return .handled }
            .onKeyPress(.space) { model.reader.scrollPage(1); return .handled }
        }
    }

    private func step(_ delta: Int, in workspace: Workspace) {
        let order = sort == .folders ? visibleFiles(workspace.tree, workspace: workspace) : workspace.files.sorted { $0.modified > $1.modified }
        guard !order.isEmpty else { return }
        let index = order.firstIndex { $0.id == model.current?.file.id } ?? -1
        let next = min(order.count - 1, max(0, index + delta))
        model.open(order[next])
    }

    private func visibleFiles(_ folder: FolderNode, workspace: Workspace) -> [DocumentFile] {
        let collapsed = Set(workspace.record?.collapsedFolders ?? [])
        if collapsed.contains(folder.id), !folder.id.isEmpty { return [] }
        return folder.files + folder.folders.flatMap { visibleFiles($0, workspace: workspace) }
    }
}

/// A folder's files, then its subfolders, as the tree shows them.
private struct FolderContents: View {
    let folder: FolderNode
    let workspace: Workspace
    let depth: Int

    var body: some View {
        ForEach(folder.files) { file in
            FileRow(file: file, workspace: workspace, depth: depth, showsLocation: false)
                .id(file.id)
        }
        ForEach(folder.folders) { child in
            FolderRow(folder: child, workspace: workspace, depth: depth)
        }
    }
}

private struct FolderRow: View {
    let folder: FolderNode
    let workspace: Workspace
    let depth: Int
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var isHovered = false

    private var isCollapsed: Bool {
        workspace.record?.collapsedFolders.contains(folder.id) ?? false
    }

    private var unread: Int {
        folder.readingOrder.filter { workspace.status(of: $0) != .read }.count
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.ink3)
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .frame(width: 12)
            Text(folder.name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(palette.ink2)
                .lineLimit(1)
            Spacer(minLength: 4)
            if isCollapsed, unread > 0 {
                Circle().fill(palette.unread).frame(width: 6, height: 6)
            }
            Text("\(folder.fileCount)")
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(palette.ink3)
        }
        .padding(.leading, 6 + CGFloat(depth) * 14)
        .padding(.trailing, 8)
        .frame(height: 27)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isHovered ? palette.hover : .clear))
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .onHover { isHovered = $0 }
        .padding(.top, depth == 0 ? 6 : 0)

        if !isCollapsed {
            FolderContents(folder: folder, workspace: workspace, depth: depth + 1)
        }
    }

    private func toggle() {
        withAnimation(.easeOut(duration: 0.18)) {
            model.toggleFolder(folder.id, in: workspace)
        }
    }
}

struct FileRow: View {
    let file: DocumentFile
    let workspace: Workspace
    let depth: Int
    let showsLocation: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var isHovered = false

    private var isSelected: Bool {
        model.current?.file.id == file.id && model.current?.workspaceID == workspace.id
    }

    var body: some View {
        let status = workspace.status(of: file)
        HStack(alignment: showsLocation ? .firstTextBaseline : .center, spacing: 7) {
            StatusDot(status: status)
                .frame(width: 8)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 1.5) {
                Text(model.settings.displayName(for: file))
                    .font(.system(size: 13, weight: status == .read ? .regular : .medium))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if showsLocation {
                    Text(location)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.ink3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 4 + CGFloat(depth) * 14)
        .padding(.trailing, 8)
        .padding(.vertical, showsLocation ? 6 : 0)
        .frame(minHeight: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? palette.selection : (isHovered ? palette.hover : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { model.open(file) }
        .onHover { isHovered = $0 }
        .help(file.relativePath)
        .contextMenu {
            Button(status == .read ? "Mark as Unread" : "Mark as Read") { model.toggleRead(file, in: workspace) }
            Divider()
            Button("Open in Default App") { model.openInEditor(file) }
            Button("Reveal in Finder") { model.revealInFinder(file) }
            Button("Copy Path") { model.copyPath(file) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.settings.displayName(for: file))\(status == .read ? "" : status == .changed ? ", changed" : ", unread")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var location: String {
        let folder = file.folder.isEmpty ? workspace.name : file.folder.replacingOccurrences(of: "/", with: " / ")
        return "\(folder) · \(AppModel.relativeDate(file.modified).lowercased())"
    }
}

/// Blue for never read, the change colour for changed since read.
struct StatusDot: View {
    let status: ReadStatus
    @Environment(\.palette) private var palette

    var body: some View {
        switch status {
        case .read:
            Color.clear.frame(width: 7, height: 7)
        case .unread:
            Circle().fill(palette.unread).frame(width: 7, height: 7)
        case .changed:
            Circle().fill(palette.change).frame(width: 7, height: 7)
        }
    }
}
