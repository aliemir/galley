import AppKit
import SwiftUI

/// Every shortcut, as the menus group them: click one and press the new
/// keys. A shortcut another action had moves over, and that is said.
struct ShortcutSettings: View {
    @State private var recording: ShortcutAction?
    @State private var notice: (action: ShortcutAction, text: String)?
    @State private var filter = ""

    private var shortcuts: Shortcuts { Shortcuts.shared }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Filter", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Spacer()
                Button("Restore All Defaults") {
                    recording = nil
                    notice = nil
                    shortcuts.resetAll()
                }
                .disabled(!shortcuts.hasCustom)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            Form {
                ForEach(ShortcutAction.groups, id: \.self) { group in
                    let actions = ShortcutAction.allCases.filter { $0.group == group && matches($0) }
                    if !actions.isEmpty {
                        Section(group) {
                            ForEach(actions) { row($0) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 520)
        }
    }

    private func matches(_ action: ShortcutAction) -> Bool {
        let text = filter.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return true }
        return action.title.localizedCaseInsensitiveContains(text)
            || (shortcuts[action]?.display.localizedCaseInsensitiveContains(text) ?? false)
    }

    private func row(_ action: ShortcutAction) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                if shortcuts.isCustom(action) {
                    Button {
                        shortcuts.reset(action)
                        notice = nil
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Back to \(action.defaultShortcut?.display ?? "none")")
                }
                ShortcutRecorder(
                    shortcut: shortcuts[action],
                    isRecording: recording == action,
                    start: {
                        recording = action
                        notice = nil
                    },
                    finish: { result in
                        recording = nil
                        apply(result, to: action)
                    }
                )
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                if let notice, notice.action == action {
                    Text(notice.text)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func apply(_ result: ShortcutRecorder.Result, to action: ShortcutAction) {
        switch result {
        case .cancelled:
            break
        case .cleared:
            shortcuts.set(nil, for: action)
        case .recorded(let shortcut):
            if Shortcuts.reserved.contains(shortcut) {
                notice = (action, "\(shortcut.display) belongs to macOS or to editing; pick another.")
                return
            }
            if shortcut.flags.intersection([.command, .control, .option]).isEmpty {
                notice = (action, "Add ⌘, ⌥ or ⌃: a bare key would fire while typing.")
                return
            }
            if let taken = shortcuts.set(shortcut, for: action) {
                notice = (action, "Moved from “\(taken.title)”, which has no shortcut now.")
            }
        }
    }
}

/// A shortcut shown as keycaps; clicked, it listens for the next key press.
/// Escape cancels, Delete clears.
struct ShortcutRecorder: View {
    enum Result { case recorded(KeyShortcut), cleared, cancelled }

    let shortcut: KeyShortcut?
    let isRecording: Bool
    let start: () -> Void
    let finish: (Result) -> Void
    @State private var monitor: Any?

    var body: some View {
        Button(action: { isRecording ? finish(.cancelled) : start() }) {
            Text(isRecording ? "Type shortcut…" : (shortcut?.display ?? "None"))
                .font(.system(size: 12, weight: isRecording ? .regular : .medium).monospacedDigit())
                .foregroundStyle(isRecording ? Color.accentColor : (shortcut == nil ? .secondary : .primary))
                .frame(width: 118, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isRecording ? 0.02 : 0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isRecording ? 1.5 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isRecording ? "Press the new keys · Esc cancels · Delete removes the shortcut" : "Click to change")
        .onChange(of: isRecording, initial: true) { _, recording in
            recording ? listen() : stopListening()
        }
        .onDisappear {
            stopListening()
            if isRecording { finish(.cancelled) }
        }
        .accessibilityLabel(shortcut?.display ?? "No shortcut")
    }

    /// Takes the next key press before the menus do, so recording ⌘W does
    /// not close the window.
    private func listen() {
        stopListening()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(KeyShortcut.relevant)
            if event.keyCode == 53, flags.isEmpty {
                finish(.cancelled)
            } else if event.keyCode == 51 || event.keyCode == 117, flags.isEmpty {
                finish(.cleared)
            } else if let shortcut = KeyShortcut(event: event) {
                finish(.recorded(shortcut))
            }
            return nil
        }
    }

    private func stopListening() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
