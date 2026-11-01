import SwiftUI

/// The page's tabs, in the strip above the page. Only drawn from two tabs:
/// with one, the page looks as it always has.
struct TabBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var available: CGFloat = 0

    static let spacing: CGFloat = 2
    static let inset: CGFloat = 2
    static let minimumWidth: CGFloat = 96
    static let maximumWidth: CGFloat = 210

    /// Tabs share the width, as Safari's do, between a floor that keeps a
    /// few words of the title and a ceiling that keeps them looking like tabs.
    private var tabWidth: CGFloat {
        let count = CGFloat(max(1, model.tabs.count))
        let share = (available - Self.inset * 2 - Self.spacing * (count - 1)) / count
        return min(Self.maximumWidth, max(Self.minimumWidth, share.rounded(.down)))
    }

    private var contentWidth: CGFloat {
        CGFloat(model.tabs.count) * (tabWidth + Self.spacing) - Self.spacing
    }

    var body: some View {
        let showsWorkspace = Set(model.tabs.map(\.workspaceID)).count > 1
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: 28)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
            .overlay(alignment: .leading) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: Self.spacing) {
                            ForEach(model.tabs) { tab in
                                TabItem(tab: tab, showsWorkspace: showsWorkspace)
                                    .frame(width: tabWidth)
                                    .id(tab.id)
                                    .transition(.opacity)
                            }
                        }
                        .padding(Self.inset)
                        .animation(.snappy(duration: 0.2), value: model.tabs)
                    }
                    .scrollIndicators(.never)
                    .scrollDisabled(contentWidth <= available)
                    // Only as wide as the tabs, so the empty strip beside them
                    // still drags the window.
                    .frame(width: max(0, min(contentWidth + Self.inset * 2, available)))
                    // A faint track holds the tabs together, as a segmented
                    // control's does; the front tab is the raised one.
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(palette.ink.opacity(palette.theme.isDark ? 0.045 : 0.05))
                    )
                    .onChange(of: model.activeTabID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) }
                    }
                }
            }
            .dropDestination(for: String.self) { items, _ in
                // A file dragged from the list opens in a tab of its own.
                guard let id = items.first.flatMap(FileDrag.fileID), let workspace = model.selectedWorkspace,
                      let file = workspace.file(id) else { return false }
                model.openInNewTab(file, in: workspace)
                return true
            }
    }
}

private struct TabItem: View {
    let tab: ReaderTab
    let showsWorkspace: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var isHovered = false
    @State private var isTargeted = false

    /// Read here rather than passed in: passed down, it went stale when a
    /// tab was inserted and made active in the same update.
    private var isActive: Bool { model.activeTabID == tab.id }

    private var workspace: Workspace? { model.workspaces.first { $0.id == tab.workspaceID } }
    private var file: DocumentFile? { tab.fileID.flatMap { workspace?.file($0) } }

    private var title: String {
        if let file { return model.settings.displayName(for: file) }
        // Before the first scan (or after the file went): the tidied filename.
        if let fileID = tab.fileID { return PrettyName.make(fromFilename: (fileID as NSString).lastPathComponent) }
        return workspace?.name ?? "Galley"
    }

    /// New or changed since read: an agent wrote to the file while its tab
    /// was in the back.
    private var status: ReadStatus {
        guard !isActive, let file, let workspace else { return .read }
        return workspace.status(of: file)
    }

    private var activeFill: Color {
        palette.theme.isDark ? palette.ink.opacity(0.11) : palette.paper
    }

    private var isGone: Bool {
        guard let workspace, workspace.hasScanned, tab.fileID != nil else { return false }
        return file == nil
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? palette.ink : (isHovered ? palette.ink2 : palette.ink3))
                .strikethrough(isGone, color: palette.ink3)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 24)
            HStack(spacing: 0) {
                leading.frame(width: 18, height: 18)
                Spacer(minLength: 0)
                StatusDot(status: status).frame(width: 8)
            }
            .padding(.horizontal, 5)
        }
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isActive ? activeFill : (isHovered ? palette.hover : .clear))
                // On light paper the front tab is a sheet of the paper itself.
                .shadow(color: .black.opacity(isActive && !palette.theme.isDark ? 0.09 : 0), radius: 1.5, y: 0.5)
        )
        .overlay(alignment: landsAfter ? .trailing : .leading) {
            if isTargeted, model.draggedTab != nil, model.draggedTab != tab.id {
                Capsule().fill(palette.accent).frame(width: 2, height: 18).offset(x: landsAfter ? 2 : -2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.activateTab(tab.id) }
        .onHover { isHovered = $0 }
        .help(file.map { (workspace?.name ?? "") + " / " + $0.relativePath } ?? title)
        .draggable(FileDrag.tab + tab.id.uuidString) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .onAppear { model.draggedTab = tab.id }
        }
        .dropDestination(for: String.self) { items, _ in
            defer { model.draggedTab = nil }
            guard let item = items.first else { return false }
            if item.hasPrefix(FileDrag.tab), let id = UUID(uuidString: String(item.dropFirst(FileDrag.tab.count))) {
                model.moveTab(id, to: tab.id)
                return true
            }
            if let id = FileDrag.fileID(item), let workspace = model.selectedWorkspace, let file = workspace.file(id) {
                model.openInNewTab(file, in: workspace)
                return true
            }
            return false
        } isTargeted: { isTargeted = $0 }
        .contextMenu {
            Button("Close Tab") { model.closeTab(tab.id) }
            Button("Close Other Tabs") { model.closeOtherTabs(tab.id) }
            if let file {
                Divider()
                Button("Reveal in Finder") { model.revealInFinder(file) }
                Button("Copy Path") { model.copyPath(file) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: "Close Tab") { model.closeTab(tab.id) }
    }

    /// Dragged rightwards, a tab lands after its target; leftwards, before.
    private var landsAfter: Bool {
        guard let dragged = model.draggedTab,
              let from = model.tabs.firstIndex(where: { $0.id == dragged }),
              let to = model.tabs.firstIndex(where: { $0.id == tab.id }) else { return false }
        return to > from
    }

    /// The close button on hover, as macOS's own tabs have it; otherwise the
    /// workspace's icon when the tabs come from more than one.
    @ViewBuilder
    private var leading: some View {
        if isHovered {
            CloseButton { model.closeTab(tab.id) }
        } else if showsWorkspace, let workspace {
            WorkspaceIcon(workspace: workspace, size: 14)
        }
    }
}

private struct CloseButton: View {
    let action: () -> Void
    @Environment(\.palette) private var palette
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(isHovered ? palette.ink : palette.ink3)
                .frame(width: 18, height: 18)
                .background(Circle().fill(isHovered ? palette.ink.opacity(0.1) : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Close Tab" + Shortcuts.shared.label(.closeTab))
        .accessibilityLabel("Close Tab")
    }
}

/// Show Next Tab and Show Previous Tab (⌃Tab and ⌃⇧Tab unless the reader
/// changed them), read here rather than left to the menu: a real ⇧Tab
/// arrives as a back-tab character, which the menu's ⌃⇧Tab never matched.
@MainActor
final class TabKeys {
    private weak var window: NSWindow?
    private var monitor: Any?

    init(window: NSWindow, model: AppModel) {
        self.window = window
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak model] event in
            MainActor.assumeIsolated {
                // With one tab, the keys keep their ordinary jobs (⌃Tab moves focus).
                guard let self, let model, model.tabs.count > 1, event.window === self.window else { return event }
                let shortcuts = Shortcuts.shared
                if shortcuts[.nextTab]?.matches(event) == true {
                    model.showTab(offset: 1)
                } else if shortcuts[.previousTab]?.matches(event) == true {
                    model.showTab(offset: -1)
                } else {
                    return event
                }
                return nil
            }
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
