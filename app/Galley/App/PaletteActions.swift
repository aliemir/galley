import SwiftUI

/// One thing the palette's actions mode (">" or ⇧⌘P) can do: what the menus
/// and the top bar do, under the names the menus give it.
struct PaletteAction: Identifiable {
    let id: String
    let title: String
    /// The menu it lives in, shown beside it.
    let group: String
    /// An SF Symbol.
    let icon: String
    var shortcut: ShortcutAction?
    /// Themes and appearances: offered once a query asks, not in the
    /// opening list, which they would swamp.
    var onlyWhenSearched = false
    /// Changes what the palette shows instead of closing it.
    var staysOpen = false
    let run: () -> Void
}

extension AppModel {
    /// The actions that make sense now; one that would do nothing (no file
    /// open, no feedback, a single tab) is left out rather than greyed.
    func paletteActions(openSettings: @escaping (_ pane: String?) -> Void) -> [PaletteAction] {
        var actions: [PaletteAction] = []
        func add(_ title: String, _ group: String, _ icon: String, _ shortcut: ShortcutAction? = nil,
                 when available: Bool = true, searched: Bool = false, _ run: @escaping () -> Void) {
            guard available else { return }
            actions.append(PaletteAction(id: group + "/" + title, title: title, group: group, icon: icon,
                                         shortcut: shortcut, onlyWhenSearched: searched, run: run))
        }
        let hasFile = current != nil

        add("Open…", "File", "folder.badge.plus", .open) { self.openFolderPanel() }
        add("Open in Default App", "File", "arrow.up.forward.app", .openInDefaultApp, when: hasFile) { self.openInEditor() }
        add("Reveal in Finder", "File", "folder", .revealInFinder, when: selectedWorkspace != nil) { self.revealInFinder() }
        add("Copy Path", "File", "doc.on.clipboard", .copyPath, when: hasFile) { self.copyPath() }
        add("Print…", "File", "printer", .print, when: hasFile) { self.printPage() }
        add(tabs.count > 1 ? "Close Tab" : "Close Window", "File", "xmark.square", .closeTab) { self.closeTabOrWindow() }
        add("Close Other Tabs", "File", "xmark.square.fill", .closeOtherTabs, when: tabs.count > 1) {
            if let id = self.activeTabID { self.closeOtherTabs(id) }
        }

        add("Find in Page", "Find", "magnifyingglass", .find, when: hasFile) {
            self.showFind()
            self.findFocusRequest += 1
        }

        for column in PanelColumn.arrangement {
            let showing = isShowing(column)
            add((showing ? "Hide " : "Show ") + column.title, "View", "sidebar.left", column.shortcutAction) {
                self.setColumn(column, visible: !showing)
            }
        }
        add(visibleColumns.isEmpty ? "Show Panels" : "Hide All Panels", "View", "rectangle.leadinghalf.inset.filled", .togglePanels) {
            self.togglePanels()
        }
        add(settings.workspacesAsIcons ? "Show Workspaces as a List" : "Show Workspaces as Icons", "View", "square.grid.2x2", .workspacesAsIcons) {
            withAnimation(.galleyPanel) { self.settings.workspacesAsIcons.toggle() }
        }
        add("Bigger Text", "View", "textformat.size.larger", .biggerText) { self.settings.adjustFontSize(by: 1) }
        add("Smaller Text", "View", "textformat.size.smaller", .smallerText) { self.settings.adjustFontSize(by: -1) }
        add("Actual Size", "View", "textformat.size", .actualSize) { self.settings.fontSize = 17 }
        add(settings.showChanges ? "Stop Marking Changes" : "Mark Changes", "View", "pencil.line", .markChanges) {
            self.settings.showChanges.toggle()
        }
        add(settings.showComments ? "Hide Hidden Comments" : "Show Hidden Comments", "View", "text.bubble", .showComments) {
            self.settings.showComments.toggle()
        }
        add("Appearance…", "View", "textformat.size") { self.isAppearanceVisible = true }
        for mode in AppearanceMode.allCases where mode != settings.appearance {
            add(mode == .system ? "Match System Appearance" : "\(mode.label) Appearance", "View",
                mode == .dark ? "moon" : (mode == .light ? "sun.max" : "circle.lefthalf.filled"), searched: true) {
                self.settings.appearance = mode
            }
        }
        for theme in Theme.all where theme.id != self.theme.id {
            add("Theme: \(theme.name)", "View", "paintpalette", searched: true) { ThemeChoice.choose(theme, model: self) }
        }

        add("Show Next Tab", "Window", "arrow.right.square", .nextTab, when: tabs.count > 1) { self.showTab(offset: 1) }
        add("Show Previous Tab", "Window", "arrow.left.square", .previousTab, when: tabs.count > 1) { self.showTab(offset: -1) }

        add("Next Document", "Go", "chevron.down", .nextDocument, when: hasFile) { self.goToNext() }
        add("Previous Document", "Go", "chevron.up", .previousDocument, when: hasFile) { self.goToPrevious() }
        add("Next Unread", "Go", "circle.fill", .nextUnread, when: (selectedWorkspace?.unreadCount ?? 0) > 0) { self.goToNextUnread() }
        let hasChanges = current?.changes.isEmpty == false
        add("Next Change", "Go", "arrow.down.to.line.compact", .nextChange, when: hasChanges) { self.jumpToChange(1) }
        add("Previous Change", "Go", "arrow.up.to.line.compact", .previousChange, when: hasChanges) { self.jumpToChange(-1) }

        add(current?.status == .read ? "Mark as Unread" : "Mark as Read", "Document", "checkmark.circle", .toggleRead, when: hasFile) {
            self.toggleRead()
        }
        add(isCurrentPinned ? "Unpin" : "Pin", "Document", isCurrentPinned ? "pin.slash" : "pin", .togglePin, when: hasFile) {
            self.togglePinCurrent()
        }
        add("Mark All as Read", "Document", "checkmark.circle.fill", .markAllRead, when: (selectedWorkspace?.unreadCount ?? 0) > 0) {
            self.markAllRead()
        }
        add("Highlight Selection", "Document", "highlighter", .highlight, when: hasFile) { self.highlightSelection() }
        add("Add Note to Selection", "Document", "note.text.badge.plus", .addNote, when: hasFile) { self.noteSelection() }
        add("Copy Feedback", "Document", "doc.on.doc", .copyFeedback, when: hasFeedback) { self.copyFeedback() }
        add("Copy Feedback for Workspace", "Document", "doc.on.doc", when: workspaceHasFeedback) { self.copyWorkspaceFeedback() }
        add("Clear Feedback…", "Document", "trash", when: hasFeedback) { self.clearFeedback() }
        add("Clear All Feedback in Workspace…", "Document", "trash", when: workspaceHasFeedback) { self.clearWorkspaceFeedback() }
        add("Fold All Sections", "Document", "chevron.right.2", .foldAll, when: hasFile) { self.foldAll(true) }
        add("Unfold All Sections", "Document", "chevron.down.2", .unfoldAll, when: hasFile) { self.foldAll(false) }

        add("Settings…", "Galley", "gearshape") { openSettings(nil) }
        add("Customize Shortcuts…", "Galley", "command") { openSettings("shortcuts") }
        add("Set Up Agents…", "Galley", "terminal") { openSettings("agents") }
        add("Install Command Line Tool…", "Galley", "terminal") { self.installCommandLineTool() }
        add("Install Agent Skill", "Galley", "sparkles") { self.installAgentSkill() }
        add("Galley Guide", "Help", "book") { self.openGuide() }
        return actions
    }
}
