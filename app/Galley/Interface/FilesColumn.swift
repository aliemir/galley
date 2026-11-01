import SwiftUI

struct FilesColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @FocusState private var isFocused: Bool
    @AppStorage("filesSort") private var sort: FileSort = .folders
    @State private var typeSelect = TypeSelect()
    @State private var typedBubble = ""
    @State private var bubbleFade: Task<Void, Never>?

    enum FileSort: String { case folders, recent }

    var body: some View {
        VStack(spacing: 0) {
            if let workspace = model.selectedWorkspace {
                ColumnHeader(title: workspace.name, subtitle: subtitle(workspace)) {
                    menu(workspace)
                }
                .modifier(PinDropZone(workspace: workspace))
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
        let feedback = workspace.feedbackCount
        var parts = [files]
        if unread > 0 { parts.append("\(unread) to read") }
        if feedback > 0 { parts.append("\(feedback) feedback") }
        return parts.joined(separator: " · ")
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
                        let pinned = workspace.pinnedFiles
                        if !pinned.isEmpty {
                            SectionLabel(title: "Pinned", count: pinned.count)
                                .padding(.horizontal, -8)
                                .modifier(PinDropZone(workspace: workspace))
                            ForEach(pinned) { file in
                                FileRow(file: file, workspace: workspace, depth: 0, showsLocation: true, marksPin: false)
                                    .modifier(PinReorder(file: file, workspace: workspace))
                                    .id("pin/" + file.id)
                            }
                        }
                        let feed = workspace.feed
                        if !feed.isEmpty, sort == .folders {
                            SectionLabel(title: "Unread", count: feed.count)
                                .padding(.horizontal, -8)
                            ForEach(feed) { file in
                                FileRow(file: file, workspace: workspace, depth: 0, showsLocation: true)
                                    .id("feed/" + file.id)
                            }
                        }
                        if !pinned.isEmpty || (!feed.isEmpty && sort == .folders) {
                            SectionLabel(title: "All files")
                                .padding(.horizontal, -8)
                        }
                        if sort == .folders {
                            FolderContents(folder: workspace.tree, workspace: workspace, depth: 0)
                        } else {
                            // Pinned files are listed once, above.
                            ForEach(workspace.files.filter { !workspace.isPinned($0.id) }.sorted { $0.modified > $1.modified }) { file in
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
                .onChange(of: model.filesCursor) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.16)) { proxy.scrollTo(id, anchor: nil) }
                }
            }
            .overlay(alignment: .bottom) { bubble }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .simultaneousGesture(TapGesture().onEnded { isFocused = true })
            .onChange(of: isFocused) { _, focused in if !focused { endTypeSelect() } }
            .onChange(of: model.filesFocusRequest) { isFocused = true }
            .onKeyPress(.downArrow) { step(1, in: workspace); return .handled }
            .onKeyPress(.upArrow) { step(-1, in: workspace); return .handled }
            .onKeyPress(.rightArrow) { model.focusPage(); return .handled }
            .onKeyPress(.return) { openCursor(in: workspace); return .handled }
            .onKeyPress(.escape) {
                guard model.filesCursor != nil || typeSelect.isActive else { return .ignored }
                endTypeSelect()
                return .handled
            }
            .onKeyPress(phases: .down) { press in typeToSelect(press, in: workspace) }
        }
    }

    /// The files in the order the column shows them: pinned first, then the
    /// tree or the recent list, each file once.
    private func order(_ workspace: Workspace) -> [DocumentFile] {
        let pinned = workspace.pinnedFiles
        let rest = sort == .folders ? visibleFiles(workspace.tree, workspace: workspace) : workspace.files.sorted { $0.modified > $1.modified }
        return pinned + rest.filter { !workspace.isPinned($0.id) }
    }

    /// Arrows open as they go, starting from wherever typing landed.
    private func step(_ delta: Int, in workspace: Workspace) {
        let order = order(workspace)
        guard !order.isEmpty else { return }
        let from = model.filesCursor ?? model.current?.file.id
        let index = order.firstIndex { $0.id == from } ?? -1
        let next = min(order.count - 1, max(0, index + delta))
        endTypeSelect()
        model.open(order[next])
    }

    /// Return opens the file typing landed on; on the open file it moves
    /// into the page, as before.
    private func openCursor(in workspace: Workspace) {
        if let id = model.filesCursor, id != model.current?.file.id, let file = workspace.file(id) {
            endTypeSelect()
            model.open(file)
        } else {
            endTypeSelect()
            model.focusPage()
        }
    }

    private func typeToSelect(_ press: KeyPress, in workspace: Workspace) -> KeyPress.Result {
        guard press.modifiers.isSubset(of: [.shift]), let character = press.characters.first,
              press.characters.count == 1 else { return .ignored }
        // Space adds to a search under way; otherwise it pages the reader.
        if character == " " {
            guard typeSelect.continues() else { model.reader.scrollPage(1); return .handled }
        } else if !(character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol) {
            return .ignored
        }
        let query = typeSelect.type(String(character))
        showBubble(query)
        let files = order(workspace)
        let names = files.map { model.settings.displayName(for: $0) }
        let from = files.firstIndex { $0.id == (model.filesCursor ?? model.current?.file.id) }
        if let index = TypeSelect.match(query, in: names, current: from) {
            model.filesCursor = files[index].id == model.current?.file.id ? nil : files[index].id
        }
        return .handled
    }

    private func endTypeSelect() {
        typeSelect.reset()
        model.filesCursor = nil
        bubbleFade?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { typedBubble = "" }
    }

    private func showBubble(_ text: String) {
        withAnimation(.easeOut(duration: 0.12)) { typedBubble = text }
        bubbleFade?.cancel()
        bubbleFade = Task {
            try? await Task.sleep(for: .seconds(TypeSelect.timeout + 0.3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { typedBubble = "" }
        }
    }

    /// What has been typed, briefly, at the foot of the column.
    @ViewBuilder
    private var bubble: some View {
        if !typedBubble.isEmpty {
            Text(typedBubble)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().strokeBorder(palette.rule))
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
            Text(model.settings.displayFolderName(folder.name))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(palette.ink2)
                .lineLimit(1)
                .help(folder.name)
            Spacer(minLength: 4)
            if isCollapsed, unread > 0 {
                Circle().fill(palette.unread).frame(width: 6, height: 6)
            }
            if isCollapsed, folder.readingOrder.contains(where: { workspace.feedbackCount($0.id) > 0 }) {
                Circle().fill(palette.feedback).frame(width: 6, height: 6)
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
    /// The pin mark, left off in the Pinned section where it says nothing.
    var marksPin = true
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var isHovered = false

    private var isSelected: Bool {
        model.current?.file.id == file.id && model.current?.workspaceID == workspace.id
    }

    /// Where typing landed: Return opens it.
    private var isCursor: Bool {
        model.filesCursor == file.id && model.selectedWorkspaceID == workspace.id
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
            let feedback = workspace.feedbackCount(file.id)
            if feedback > 0 {
                FeedbackMark(count: feedback, expanded: isHovered)
            }
            if marksPin, workspace.isPinned(file.id) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8.5))
                    .foregroundStyle(palette.ink3)
                    .rotationEffect(.degrees(45))
                    .accessibilityLabel("Pinned")
            }
        }
        .padding(.leading, 4 + CGFloat(depth) * 14)
        .padding(.trailing, 8)
        .padding(.vertical, showsLocation ? 6 : 0)
        .frame(minHeight: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? palette.selection : (isCursor ? palette.accent.opacity(0.1) : (isHovered ? palette.hover : .clear)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(palette.accent.opacity(isCursor ? 0.7 : 0), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // ⌘-click, as in a browser: a tab of its own.
            if NSEvent.modifierFlags.contains(.command) { model.openInNewTab(file, in: workspace) } else { model.open(file) }
        }
        .onHover { isHovered = $0 }
        .help(file.relativePath)
        .modifier(DragToPin(file: file, enabled: marksPin))
        .contextMenu {
            Button("Open in New Tab") { model.openInNewTab(file, in: workspace) }
            Divider()
            Button(workspace.isPinned(file.id) ? "Unpin" : "Pin") {
                withAnimation(.snappy(duration: 0.2)) { model.togglePin(file, in: workspace) }
            }
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
        let folder = file.folder.isEmpty ? workspace.name : model.settings.displayFolderPath(file.folder)
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

/// Drag a pinned file onto another to take its place, with a line where it
/// lands — the same gesture as reordering workspaces.
private struct PinReorder: ViewModifier {
    let file: DocumentFile
    let workspace: Workspace
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var isTargeted = false


    private var landsBelow: Bool {
        // Dragged down the list, a file lands below its target; up, above.
        let pinned = workspace.record?.pinned ?? []
        guard let dragged = model.draggedPin,
              let from = pinned.firstIndex(of: dragged),
              let to = pinned.firstIndex(of: file.id) else { return false }
        return to > from
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: landsBelow ? .bottom : .top) {
                if isTargeted, model.draggedPin != file.id {
                    Capsule()
                        .fill(palette.accent)
                        .frame(height: 2)
                        .padding(.horizontal, 4)
                        .offset(y: landsBelow ? 2 : -2)
                        .allowsHitTesting(false)
                }
            }
            .draggable(FileDrag.pinned + file.id) {
                Text(model.settings.displayName(for: file))
                    .font(.system(size: 12, weight: .medium))
                    .padding(6)
                    .onAppear { model.draggedPin = file.id }
            }
            .dropDestination(for: String.self) { items, _ in
                defer { model.draggedPin = nil }
                guard let item = items.first else { return false }
                if item.hasPrefix(FileDrag.pinned) {
                    model.movePin(String(item.dropFirst(FileDrag.pinned.count)), to: file.id, in: workspace)
                } else if item.hasPrefix(FileDrag.file) {
                    // A file from the list: pinned in this one's place.
                    model.pin(String(item.dropFirst(FileDrag.file.count)), at: file.id, in: workspace)
                } else {
                    return false
                }
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

/// What a drag carries: a pinned file being reordered, a file from the list
/// on its way to being pinned (or to a tab of its own), or a tab.
enum FileDrag {
    static let pinned = "galley-pin:"
    static let file = "galley-file:"
    static let tab = "galley-tab:"

    /// The file a dragged list row or pinned row stands for.
    static func fileID(_ item: String) -> String? {
        for prefix in [pinned, file] where item.hasPrefix(prefix) { return String(item.dropFirst(prefix.count)) }
        return nil
    }
}

/// Any file in the list can be dragged to the Pinned section.
private struct DragToPin: ViewModifier {
    let file: DocumentFile
    let enabled: Bool
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        if enabled {
            content.draggable(FileDrag.file + file.id) {
                Label(model.settings.displayName(for: file), systemImage: "pin")
                    .font(.system(size: 12, weight: .medium))
                    .padding(6)
            }
        } else {
            content
        }
    }
}

/// The Pinned label, and the column's header (the only place to drop on
/// before anything is pinned): a file dropped here is pinned at the end.
private struct PinDropZone: ViewModifier {
    let workspace: Workspace
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.accent.opacity(0.1))
                        .strokeBorder(palette.accent.opacity(0.6), lineWidth: 1.5)
                        .overlay(
                            Label("Drop to pin", systemImage: "pin.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.accent)
                        )
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let item = items.first else { return false }
                let prefix = item.hasPrefix(FileDrag.file) ? FileDrag.file : item.hasPrefix(FileDrag.pinned) ? FileDrag.pinned : nil
                guard let prefix else { return false }
                model.pin(String(item.dropFirst(prefix.count)), at: nil, in: workspace)
                model.draggedPin = nil
                return true
            } isTargeted: { targeted in
                withAnimation(.easeOut(duration: 0.12)) { isTargeted = targeted }
            }
    }
}

/// Feedback on a file: a purple dot that grows, on hover, into the count —
/// the change dot's quieter sibling at the other end of the row.
struct FeedbackMark: View {
    let count: Int
    let expanded: Bool

    var body: some View {
        GrowingBadge(count: count, kind: .feedback, expanded: expanded, icon: "text.bubble.fill")
            .help(count == 1 ? "1 highlight or note" : "\(count) highlights and notes")
            .accessibilityLabel(count == 1 ? "1 highlight or note" : "\(count) highlights and notes")
    }
}

/// A dot that becomes its count: small while at rest, readable on hover.
struct GrowingBadge: View {
    let count: Int
    let kind: CountBadge.Kind
    let expanded: Bool
    var icon: String?
    var dotSize: CGFloat = 6
    @Environment(\.palette) private var palette

    private var color: Color {
        switch kind {
        case .new: palette.unread
        case .changed: palette.change
        case .feedback: palette.feedback
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon).font(.system(size: 8.5))
            }
            Text("\(count)")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5.5)
        .padding(.vertical, 1.5)
        .opacity(expanded ? 1 : 0)
        .fixedSize()
        .frame(width: expanded ? nil : dotSize, height: expanded ? nil : dotSize)
        .background(Capsule().fill(expanded ? color.opacity(palette.theme.isDark ? 0.24 : 0.15) : color))
        .clipShape(Capsule())
        .animation(.snappy(duration: 0.2), value: expanded)
    }
}
