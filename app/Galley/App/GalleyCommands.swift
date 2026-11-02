import SwiftUI

/// Every action has a shortcut, and the panel shortcuts mirror the swipe.
/// The keys are the reader's own (Settings → Shortcuts), read from `Shortcuts`.
struct GalleyCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab…") {
                // The palette picks what the tab shows; Escape opens nothing.
                model.quickOpenSearchesText = false
                model.quickOpenOpensTab = true
                model.isQuickOpenVisible = true
            }
            .shortcut(.newTab)
            .disabled(model.workspaces.isEmpty)
            Button("Open…") { model.openFolderPanel() }
                .shortcut(.open)
            Button("Go to File…") {
                model.quickOpenSearchesText = false
                model.isQuickOpenVisible.toggle()
            }
                .shortcut(.goToFile)
                .disabled(model.workspaces.isEmpty)
            Button("Search All Files…") {
                model.quickOpenSearchesText = true
                model.isQuickOpenVisible = true
            }
            .shortcut(.searchAllFiles)
            .disabled(model.workspaces.isEmpty)
            Button("Go to Section…") {
                model.quickOpenSearchesText = false
                model.isQuickOpenVisible = true
                model.quickOpenSeed = "#"
            }
            .shortcut(.goToSection)
            .disabled(model.current == nil)
            Button("All Actions…") {
                model.quickOpenSearchesText = false
                model.quickOpenSeed = ">"
                model.isQuickOpenVisible = true
            }
            .shortcut(.allActions)
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Open in Default App") { model.openInEditor() }
                .shortcut(.openInDefaultApp)
                .disabled(model.current == nil)
            Button("Reveal in Finder") { model.revealInFinder() }
                .shortcut(.revealInFinder)
                .disabled(model.selectedWorkspace == nil)
            Button("Copy Path") { model.copyPath() }
                .shortcut(.copyPath)
                .disabled(model.current == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button(model.tabs.count > 1 ? "Close Tab" : "Close Window") { model.closeTabOrWindow() }
                .shortcut(.closeTab)
            Button("Close Other Tabs") { if let id = model.activeTabID { model.closeOtherTabs(id) } }
                .shortcut(.closeOtherTabs)
                .disabled(model.tabs.count < 2)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { model.printPage() }
                .shortcut(.print)
                .disabled(model.current == nil)
        }

        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") {
                model.showFind()
                model.findFocusRequest += 1
            }
            .shortcut(.find)
            .disabled(model.current == nil)
            Button("Find Next") { Task { await model.runFind(direction: 1) } }
                .shortcut(.findNext)
                .disabled(model.findQuery.isEmpty)
            Button("Find Previous") { Task { await model.runFind(direction: -1) } }
                .shortcut(.findPrevious)
                .disabled(model.findQuery.isEmpty)
        }

        CommandGroup(before: .toolbar) {
            // ⌘1–⌘3 by default, numbered by the columns' places.
            ForEach(PanelColumn.arrangement) { column in
                Toggle(column.title, isOn: Binding(
                    get: { model.isShowing(column) },
                    set: { model.setColumn(column, visible: $0) }
                ))
                .shortcut(column.shortcutAction)
            }
            Button(model.visibleColumns.isEmpty ? "Show Panels" : "Hide All Panels") { model.togglePanels() }
                .shortcut(.togglePanels)
            Button("Show Next Panel") { model.stepLevel(1) }
                .shortcut(.showNextPanel)
            Button("Hide Last Panel") { model.stepLevel(-1) }
                .shortcut(.hideLastPanel)
            Toggle("Workspaces as Icons", isOn: Binding(
                get: { model.settings.workspacesAsIcons },
                set: { value in withAnimation(.galleyPanel) { model.settings.workspacesAsIcons = value } }
            ))
            .shortcut(.workspacesAsIcons)
            Divider()
            Button("Bigger Text") { model.settings.adjustFontSize(by: 1) }
                .shortcut(.biggerText)
            Button("Smaller Text") { model.settings.adjustFontSize(by: -1) }
                .shortcut(.smallerText)
            Button("Actual Size") { model.settings.fontSize = 17 }
                .shortcut(.actualSize)
            Divider()
            Toggle("Mark Changes", isOn: Binding(
                get: { model.settings.showChanges },
                set: { model.settings.showChanges = $0 }
            ))
            .shortcut(.markChanges)
            Toggle("Show Hidden Comments", isOn: Binding(
                get: { model.settings.showComments },
                set: { model.settings.showComments = $0 }
            ))
            .shortcut(.showComments)
            Divider()
        }

        CommandGroup(before: .windowList) {
            Button("Show Next Tab") { model.showTab(offset: 1) }
                .shortcut(.nextTab)
                .disabled(model.tabs.count < 2)
            Button("Show Previous Tab") { model.showTab(offset: -1) }
                .shortcut(.previousTab)
                .disabled(model.tabs.count < 2)
            Divider()
        }

        CommandGroup(after: .appSettings) {
            Button("Install Command Line Tool…") { model.installCommandLineTool() }
            Button("Install Agent Skill") { model.installAgentSkill() }
        }

        CommandGroup(replacing: .help) {
            Button("Galley Guide") { model.openGuide() }
        }

        CommandMenu("Go") {
            Button("Next Document") { model.goToNext() }
                .shortcut(.nextDocument)
            Button("Previous Document") { model.goToPrevious() }
                .shortcut(.previousDocument)
            Button("Next Unread") { model.goToNextUnread() }
                .shortcut(.nextUnread)
            Divider()
            Button("Next Change") { model.jumpToChange(1) }
                .shortcut(.nextChange)
            Button("Previous Change") { model.jumpToChange(-1) }
                .shortcut(.previousChange)
        }

        CommandMenu("Document") {
            Button(model.current?.status == .read ? "Mark as Unread" : "Mark as Read") { model.toggleRead() }
                .shortcut(.toggleRead)
                .disabled(model.current == nil)
            Button(model.isCurrentPinned ? "Unpin" : "Pin") { model.togglePinCurrent() }
                .shortcut(.togglePin)
                .disabled(model.current == nil)
            Button("Mark All as Read") { model.markAllRead() }
                .shortcut(.markAllRead)
                .disabled((model.selectedWorkspace?.unreadCount ?? 0) == 0)
            Divider()
            Button("Highlight Selection") { model.highlightSelection() }
                .shortcut(.highlight)
                .disabled(model.current == nil)
            Button("Add Note to Selection") { model.noteSelection() }
                .shortcut(.addNote)
                .disabled(model.current == nil)
            Divider()
            Button("Copy File Feedback") { model.copyFeedback() }
                .shortcut(.copyFeedback)
                .disabled(!model.hasFeedback)
            Button("Clear File Feedback…") { model.clearFeedback() }
                .disabled(!model.hasFeedback)
            Divider()
            Button("Copy Workspace Feedback") { model.copyWorkspaceFeedback() }
                .disabled(!model.workspaceHasFeedback)
            Button("Clear Workspace Feedback…") { model.clearWorkspaceFeedback() }
                .disabled(!model.workspaceHasFeedback)
            Divider()
            Button("Fold All Sections") { model.foldAll(true) }
                .shortcut(.foldAll)
                .disabled(model.current == nil)
            Button("Unfold All Sections") { model.foldAll(false) }
                .shortcut(.unfoldAll)
                .disabled(model.current == nil)
        }
    }
}
