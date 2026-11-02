import AppKit
import Observation
import SwiftUI

/// A key and its modifiers, as stored and shown: `⌥⌘R`.
nonisolated struct KeyShortcut: Codable, Hashable, Sendable {
    /// A character ("r", "]", "+") or a named key ("up", "tab", "return"…).
    var key: String
    /// Command, option, control and shift, as `NSEvent.ModifierFlags` bits.
    var modifiers: UInt

    static let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(_ key: String, _ modifiers: NSEvent.ModifierFlags = .command) {
        self.key = key
        self.modifiers = modifiers.intersection(Self.relevant).rawValue
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// Named keys, with their key code, SwiftUI equivalent and glyph.
    static let named: [String: (code: UInt16, equivalent: KeyEquivalent, glyph: String)] = [
        "up": (126, .upArrow, "↑"), "down": (125, .downArrow, "↓"), "left": (123, .leftArrow, "←"), "right": (124, .rightArrow, "→"),
        "tab": (48, .tab, "⇥"), "return": (36, .return, "↩"), "space": (49, .space, "Space"),
        "delete": (51, .delete, "⌫"), "escape": (53, .escape, "⎋"), "home": (115, .home, "↖"), "end": (119, .end, "↘"),
        "pageup": (116, .pageUp, "⇞"), "pagedown": (121, .pageDown, "⇟"),
    ]

    var keyboardShortcut: KeyboardShortcut {
        var swiftUI: SwiftUI.EventModifiers = []
        if flags.contains(.command) { swiftUI.insert(.command) }
        if flags.contains(.option) { swiftUI.insert(.option) }
        if flags.contains(.control) { swiftUI.insert(.control) }
        if flags.contains(.shift) { swiftUI.insert(.shift) }
        let equivalent = Self.named[key]?.equivalent ?? KeyEquivalent(Character(key))
        return KeyboardShortcut(equivalent, modifiers: swiftUI)
    }

    /// In the order macOS menus use: ⌃⌥⇧⌘, then the key.
    var display: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + (Self.named[key]?.glyph ?? key.uppercased())
    }

    /// What a key press stands for; nil for a press of modifiers alone.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(Self.relevant)
        if let name = Self.named.first(where: { $0.value.code == event.keyCode })?.key {
            self.init(name, flags)
            return
        }
        // The key's own character on this layout, before shift or option
        // change it: ⇧⌘] is "]" with shift, not "}".
        guard let character = event.characters(byApplyingModifiers: [])?.lowercased(), !character.isEmpty,
              character.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        self.init(character, flags)
    }

    func matches(_ event: NSEvent) -> Bool {
        KeyShortcut(event: event) == self
    }
}

/// Everything with a shortcut, grouped as the menus are.
enum ShortcutAction: String, CaseIterable, Identifiable {
    case newTab, open, goToFile, searchAllFiles, goToSection, allActions, openInDefaultApp, revealInFinder, copyPath
    case closeTab, closeOtherTabs, print
    case find, findNext, findPrevious
    case toggleWorkspaces, toggleFiles, toggleContents, togglePanels, showNextPanel, hideLastPanel, workspacesAsIcons
    case biggerText, smallerText, actualSize, markChanges, showComments
    case nextTab, previousTab
    case nextDocument, previousDocument, nextUnread, nextChange, previousChange, markChangeRead
    case toggleRead, togglePin, markAllRead, highlight, addNote, saveFeedback, copyFeedback, foldAll, unfoldAll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newTab: "New Tab"
        case .open: "Open…"
        case .goToFile: "Go to File"
        case .searchAllFiles: "Search All Files"
        case .goToSection: "Go to Section"
        case .allActions: "All Actions"
        case .openInDefaultApp: "Open in Default App"
        case .revealInFinder: "Reveal in Finder"
        case .copyPath: "Copy Path"
        case .closeTab: "Close Tab"
        case .closeOtherTabs: "Close Other Tabs"
        case .print: "Print"
        case .find: "Find"
        case .findNext: "Find Next"
        case .findPrevious: "Find Previous"
        case .toggleWorkspaces: "Show or Hide Workspaces"
        case .toggleFiles: "Show or Hide Files"
        case .toggleContents: "Show or Hide Contents"
        case .togglePanels: "Hide All Panels / Show Them"
        case .showNextPanel: "Show Next Panel"
        case .hideLastPanel: "Hide Last Panel"
        case .workspacesAsIcons: "Workspaces as Icons"
        case .biggerText: "Bigger Text"
        case .smallerText: "Smaller Text"
        case .actualSize: "Actual Size"
        case .markChanges: "Mark Changes"
        case .showComments: "Show Hidden Comments"
        case .nextTab: "Show Next Tab"
        case .previousTab: "Show Previous Tab"
        case .nextDocument: "Next Document"
        case .previousDocument: "Previous Document"
        case .nextUnread: "Next Unread"
        case .nextChange: "Next Change"
        case .previousChange: "Previous Change"
        case .markChangeRead: "Mark Change as Read"
        case .toggleRead: "Mark as Read / Unread"
        case .togglePin: "Pin / Unpin"
        case .markAllRead: "Mark All as Read"
        case .highlight: "Highlight Selection"
        case .addNote: "Add Note to Selection"
        case .saveFeedback: "Save Feedback"
        case .copyFeedback: "Copy File Feedback"
        case .foldAll: "Fold All Sections"
        case .unfoldAll: "Unfold All Sections"
        }
    }

    var group: String {
        switch self {
        case .newTab, .open, .goToFile, .searchAllFiles, .goToSection, .allActions, .openInDefaultApp, .revealInFinder, .copyPath,
             .closeTab, .closeOtherTabs, .print: "File"
        case .find, .findNext, .findPrevious: "Find"
        case .toggleWorkspaces, .toggleFiles, .toggleContents, .togglePanels, .showNextPanel, .hideLastPanel, .workspacesAsIcons,
             .biggerText, .smallerText, .actualSize, .markChanges, .showComments: "View"
        case .nextTab, .previousTab: "Tabs"
        case .nextDocument, .previousDocument, .nextUnread, .nextChange, .previousChange, .markChangeRead: "Go"
        case .toggleRead, .togglePin, .markAllRead, .highlight, .addNote, .saveFeedback, .copyFeedback, .foldAll, .unfoldAll: "Document"
        }
    }

    static let groups = ["File", "Find", "View", "Tabs", "Go", "Document"]

    var defaultShortcut: KeyShortcut? {
        switch self {
        case .newTab: KeyShortcut("t")
        case .open: KeyShortcut("o")
        case .goToFile: KeyShortcut("k")
        case .searchAllFiles: KeyShortcut("f", [.command, .shift])
        case .goToSection: KeyShortcut("k", [.command, .shift])
        case .allActions: KeyShortcut("p", [.command, .shift])
        case .openInDefaultApp: KeyShortcut("e")
        case .revealInFinder: KeyShortcut("r", [.command, .option])
        case .copyPath: KeyShortcut("c", [.command, .option, .shift])
        case .closeTab: KeyShortcut("w")
        case .closeOtherTabs: KeyShortcut("w", [.command, .option])
        case .print: KeyShortcut("p")
        case .find: KeyShortcut("f")
        case .findNext: KeyShortcut("g")
        case .findPrevious: KeyShortcut("g", [.command, .shift])
        case .toggleWorkspaces: KeyShortcut("1")
        case .toggleFiles: KeyShortcut("2")
        case .toggleContents: KeyShortcut("3")
        case .togglePanels: KeyShortcut("\\")
        case .showNextPanel: KeyShortcut("]")
        case .hideLastPanel: KeyShortcut("[")
        case .workspacesAsIcons: KeyShortcut("4", [.command, .option])
        case .biggerText: KeyShortcut("+")
        case .smallerText: KeyShortcut("-")
        case .actualSize: KeyShortcut("0")
        case .markChanges: KeyShortcut("d", [.command, .shift])
        case .showComments: KeyShortcut("h", [.command, .shift])
        case .nextTab: KeyShortcut("tab", .control)
        case .previousTab: KeyShortcut("tab", [.control, .shift])
        case .nextDocument: KeyShortcut("down", [.command, .option])
        case .previousDocument: KeyShortcut("up", [.command, .option])
        case .nextUnread: KeyShortcut("u", [.command, .option])
        case .nextChange: KeyShortcut("j")
        case .previousChange: KeyShortcut("j", [.command, .shift])
        case .markChangeRead: KeyShortcut("j", [.command, .option])
        case .toggleRead: KeyShortcut("u", [.command, .shift])
        case .togglePin: KeyShortcut("p", [.command, .option])
        case .markAllRead: KeyShortcut("u", [.command, .option, .shift])
        case .highlight: KeyShortcut("h", [.command, .control])
        case .addNote: KeyShortcut("n", [.command, .control])
        case .saveFeedback: KeyShortcut("s")
        case .copyFeedback: KeyShortcut("c", [.command, .shift])
        case .foldAll: KeyShortcut("left", [.command, .option])
        case .unfoldAll: KeyShortcut("right", [.command, .option])
        }
    }
}

/// The reader's shortcuts: the defaults, with their own changes on top.
/// Menus, tooltips and the tab keys all read from here.
@MainActor
@Observable
final class Shortcuts {
    static let shared = Shortcuts()

    /// Changed actions only; an empty key means "no shortcut".
    private var overrides: [String: KeyShortcut]

    private init() {
        if let data = Preferences.store.data(forKey: "shortcuts"),
           let stored = try? JSONDecoder().decode([String: KeyShortcut].self, from: data) {
            overrides = stored
        } else {
            overrides = [:]
        }
    }

    private func save() {
        Preferences.store.set(try? JSONEncoder().encode(overrides), forKey: "shortcuts")
    }

    subscript(action: ShortcutAction) -> KeyShortcut? {
        guard let custom = overrides[action.rawValue] else { return action.defaultShortcut }
        return custom.key.isEmpty ? nil : custom
    }

    func isCustom(_ action: ShortcutAction) -> Bool { overrides[action.rawValue] != nil }

    var hasCustom: Bool { !overrides.isEmpty }

    /// " (⌘F)" for a tooltip or a menu title; nothing when unbound.
    func label(_ action: ShortcutAction) -> String {
        self[action].map { " (\($0.display))" } ?? ""
    }

    /// The action already using `shortcut`, other than `action`.
    func owner(of shortcut: KeyShortcut, except action: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != action && self[$0] == shortcut }
    }

    /// Gives `action` a shortcut (nil to clear it). A shortcut another action
    /// had moves here, and that action is left without one; it is returned
    /// so the change can be said.
    @discardableResult
    func set(_ shortcut: KeyShortcut?, for action: ShortcutAction) -> ShortcutAction? {
        var taken: ShortcutAction?
        if let shortcut, let owner = owner(of: shortcut, except: action) {
            overrides[owner.rawValue] = KeyShortcut("", [])
            taken = owner
        }
        if shortcut == action.defaultShortcut {
            overrides[action.rawValue] = nil
        } else {
            overrides[action.rawValue] = shortcut ?? KeyShortcut("", [])
        }
        save()
        return taken
    }

    func reset(_ action: ShortcutAction) {
        // Its default may have been handed to another action since.
        if let shortcut = action.defaultShortcut, let owner = owner(of: shortcut, except: action) {
            overrides[owner.rawValue] = KeyShortcut("", [])
        }
        overrides[action.rawValue] = nil
        save()
    }

    func resetAll() {
        overrides = [:]
        save()
    }

    /// Shortcuts the system or every Mac app keeps for itself.
    static let reserved: Set<KeyShortcut> = [
        KeyShortcut("q"), KeyShortcut("h"), KeyShortcut("h", [.command, .option]), KeyShortcut("m"),
        KeyShortcut(","), KeyShortcut("`"), KeyShortcut("tab"), KeyShortcut("space"),
        KeyShortcut("c"), KeyShortcut("v"), KeyShortcut("x"), KeyShortcut("a"), KeyShortcut("z"),
        KeyShortcut("z", [.command, .shift]),
    ]
}

extension View {
    /// The reader's shortcut for `action`, or none.
    func shortcut(_ action: ShortcutAction) -> some View {
        keyboardShortcut(Shortcuts.shared[action]?.keyboardShortcut)
    }
}
