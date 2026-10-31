import SwiftUI

/// Every action has a shortcut, and the panel shortcuts mirror the swipe.
struct GalleyCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") { model.openFolderPanel() }
                .keyboardShortcut("o")
            Button("Go to File…") { model.isQuickOpenVisible.toggle() }
                .keyboardShortcut("k")
                .disabled(model.workspaces.isEmpty)
            Button("Go to Section…") {
                model.isQuickOpenVisible = true
                model.quickOpenSeed = "#"
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(model.current == nil)
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Open in Default App") { model.openInEditor() }
                .keyboardShortcut("e")
                .disabled(model.current == nil)
            Button("Reveal in Finder") { model.revealInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(model.selectedWorkspace == nil)
            Button("Copy Path") { model.copyPath() }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                .disabled(model.current == nil)
        }
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .printItem) {}

        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") {
                model.showFind()
                model.findFocusRequest += 1
            }
            .keyboardShortcut("f")
            .disabled(model.current == nil)
            Button("Find Next") { Task { await model.runFind(direction: 1) } }
                .keyboardShortcut("g")
                .disabled(model.findQuery.isEmpty)
            Button("Find Previous") { Task { await model.runFind(direction: -1) } }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(model.findQuery.isEmpty)
        }

        CommandGroup(before: .toolbar) {
            ForEach(PanelLevel.allCases, id: \.self) { level in
                Button(level.label) { model.setLevel(level) }
                    .keyboardShortcut(KeyEquivalent(Character("\(level.rawValue)")))
            }
            Button("Show More Panels") { model.stepLevel(1) }
                .keyboardShortcut("]")
            Button("Show Fewer Panels") { model.stepLevel(-1) }
                .keyboardShortcut("[")
            Divider()
            Button("Bigger Text") { model.settings.adjustFontSize(by: 1) }
                .keyboardShortcut("+")
            Button("Smaller Text") { model.settings.adjustFontSize(by: -1) }
                .keyboardShortcut("-")
            Button("Actual Size") { model.settings.fontSize = 17 }
                .keyboardShortcut("0")
            Divider()
            Toggle("Mark Changes", isOn: Binding(
                get: { model.settings.showChanges },
                set: { model.settings.showChanges = $0 }
            ))
            .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
        }

        CommandMenu("Go") {
            Button("Next Document") { model.goToNext() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Previous Document") { model.goToPrevious() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Next Unread") { model.goToNextUnread() }
                .keyboardShortcut("u", modifiers: [.command, .option])
            Divider()
            Button("Next Change") { model.jumpToChange(1) }
                .keyboardShortcut("j")
            Button("Previous Change") { model.jumpToChange(-1) }
                .keyboardShortcut("j", modifiers: [.command, .shift])
        }

        CommandMenu("Document") {
            Button(model.current?.status == .read ? "Mark as Unread" : "Mark as Read") { model.toggleRead() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(model.current == nil)
            Button("Mark All as Read") { model.markAllRead() }
                .keyboardShortcut("u", modifiers: [.command, .option, .shift])
                .disabled((model.selectedWorkspace?.unreadCount ?? 0) == 0)
            Divider()
            Button("Fold All Sections") { model.foldAll(true) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(model.current == nil)
            Button("Unfold All Sections") { model.foldAll(false) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(model.current == nil)
        }
    }
}
