import SwiftUI
import WebKit

/// The page: the reader web view, a top strip with the few controls a
/// reader needs, and the find bar.
struct PageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    @AppStorage("hideAgentButton", store: Preferences.store) private var hideAgentButton = false

    /// Where the page starts in the window: at the left edge, the tabs keep
    /// clear of the traffic lights and the panel button.
    @State private var pageMinX: CGFloat = 0
    /// Keeps the Save button up long enough to say it worked.
    @State private var saveButton = SaveButtonState()

    var body: some View {
        ZStack(alignment: .top) {
            ReaderSurface(controller: model.reader)
                .opacity(model.current == nil ? 0 : 1)
            if model.current == nil {
                PagePlaceholder()
            }
            topStrip
        }
        .background(palette.paper)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { pageMinX = $0 }
    }

    private var topStrip: some View {
        HStack(spacing: 4) {
            if model.tabs.count > 1 {
                TabBar()
                    .padding(.leading, max(0, 104 - pageMinX))
                    .padding(.trailing, 8)
                    .transition(.opacity)
            } else {
                Spacer()
            }
            if model.isFindVisible {
                FindBar()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let current = model.current, !current.highlights.isEmpty {
                FeedbackButton(
                    count: current.highlights.count,
                    help: "Copy this file's feedback for an agent" + Shortcuts.shared.label(.copyFeedback),
                    copy: model.copyFeedback,
                    menu: {
                        Button("Copy File Feedback") { model.copyFeedback() }
                        Divider()
                        Button("Clear File Feedback…") { model.clearFeedback() }
                    },
                    icon: { Image(systemName: "text.bubble").font(.system(size: 12.5)) }
                )
            }
            if let workspace = model.selectedWorkspace, workspace.feedbackCount > 0 {
                FeedbackButton(
                    count: workspace.feedbackCount,
                    help: "Copy all feedback in \(workspace.name) for an agent",
                    copy: model.copyWorkspaceFeedback,
                    menu: {
                        if workspace.draftCount > 0 {
                            Button("Save Feedback") { model.saveFeedback() }
                        }
                        Button("Copy Workspace Feedback") { model.copyWorkspaceFeedback() }
                        Divider()
                        Button("Clear All Feedback in \(workspace.name)…") { model.clearWorkspaceFeedback() }
                    },
                    icon: { WorkspaceIcon(workspace: workspace, size: 15) }
                )
            }
            if let workspace = model.selectedWorkspace, workspace.draftCount > 0 || saveButton.isConfirming {
                SaveFeedbackButton(count: workspace.draftCount, state: saveButton, workspace: workspace.name,
                                   waiting: model.watcher(for: workspace).map { $0.agent ?? "An agent" }) {
                    model.saveFeedback()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            if model.current?.changes.isEmpty == false {
                IconButton(systemName: "arrow.down.to.line.compact", help: "Next Change" + Shortcuts.shared.label(.nextChange)) {
                    model.jumpToChange(1)
                }
            }
            // Until agents are connected (or the reader says not to ask).
            if !model.agents.isComplete, !hideAgentButton {
                IconButton(systemName: "terminal", help: "Let your agents read your feedback", isActive: model.isAgentSetupVisible) {
                    model.isAgentSetupVisible.toggle()
                }
                .popover(isPresented: Bindable(model).isAgentSetupVisible, arrowEdge: .bottom) {
                    AgentSetupView(place: .panel)
                        .environment(model)
                }
            }
            // Either can be hidden in Settings; it still shows while its bar
            // or panel is open (the palette's actions open Appearance).
            if model.settings.showFindButton || model.isFindVisible {
                IconButton(systemName: "magnifyingglass", help: "Find" + Shortcuts.shared.label(.find), isActive: model.isFindVisible) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        if model.isFindVisible { model.hideFind() } else { model.showFind() }
                    }
                }
            }
            if model.settings.showAppearanceButton || model.isAppearanceVisible {
                IconButton(systemName: "textformat.size", help: "Appearance", isActive: model.isAppearanceVisible) {
                    model.isAppearanceVisible.toggle()
                }
                .popover(isPresented: Bindable(model).isAppearanceVisible, arrowEdge: .bottom) {
                    AppearancePopover()
                        .environment(model)
                        .environment(\.palette, palette)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: MainView.bandHeight)
        .padding(.top, 2)
        .animation(.snappy(duration: 0.2), value: model.tabs.count > 1)
        .animation(.snappy(duration: 0.2), value: (model.selectedWorkspace?.draftCount ?? 0) > 0 || saveButton.isConfirming)
        .background(alignment: .top) { TitleBand() }
        .background(alignment: .top) {
            // Lets text slide under the controls without colliding with them.
            LinearGradient(
                stops: [.init(color: palette.paper, location: 0), .init(color: palette.paper, location: 0.55), .init(color: palette.paper.opacity(0), location: 1)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: MainView.bandHeight + 18)
            .allowsHitTesting(false)
        }
    }
}

/// Hosts the controller's single web view; SwiftUI never recreates it.
private struct ReaderSurface: NSViewRepresentable {
    let controller: ReaderController

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let webView = controller.webView
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct PagePlaceholder: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 8) {
            if let workspace = model.selectedWorkspace, workspace.hasScanned, workspace.files.isEmpty {
                Text("Nothing to read yet")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(palette.ink)
                Text("Galley is watching \(workspace.name). Markdown files appear here the moment they are written.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            } else if model.selectedWorkspace == nil {
                Text("Choose a workspace")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.ink3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Find

private struct FindBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.ink3)
            TextField("Find in page", text: $model.findQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.ink)
                .focused($isFocused)
                .frame(width: 150)
                .onSubmit { Task { await model.runFind(direction: NSEvent.modifierFlags.contains(.shift) ? -1 : 1) } }
                .onChange(of: model.findQuery) { _, _ in
                    Task { await model.runFind(direction: 0) }
                }
                .onKeyPress(.escape) {
                    withAnimation(.easeOut(duration: 0.18)) { model.hideFind() }
                    return .handled
                }
            if !model.findQuery.isEmpty {
                Text(model.findResult.count == 0 ? "None" : "\(model.findResult.index + 1) of \(model.findResult.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(palette.ink3)
                    .fixedSize()
            }
            Button { Task { await model.runFind(direction: -1) } } label: {
                Image(systemName: "chevron.up").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.ink2)
            .disabled(model.findResult.count == 0)
            Button { Task { await model.runFind(direction: 1) } } label: {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.ink2)
            .disabled(model.findResult.count == 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.ink.opacity(palette.theme.isDark ? 0.09 : 0.05))
        )
        .onAppear { isFocused = true }
        .onChange(of: model.findFocusRequest) { _, _ in isFocused = true }
    }
}

/// Copy feedback in one click, with the rest a chevron away: the count and
/// what it is about on the left, a menu on the right, one shape around both.
@Observable
private final class SaveButtonState {
    var isConfirming = false
    var reset: Task<Void, Never>?
}

/// Saves the workspace's drafts, handing them to agents in one go. Drawn as
/// the feedback buttons beside it are; there only while drafts wait.
private struct SaveFeedbackButton: View {
    let count: Int
    let state: SaveButtonState
    let workspace: String
    /// The agent waiting for this round ("Claude Code"), if one is.
    let waiting: String?
    let save: () -> Void
    @Environment(\.palette) private var palette
    @State private var isHovered = false
    @State private var isPulsing = false

    private var isDone: Bool { state.isConfirming && count == 0 }

    var body: some View {
        Button {
            save()
            withAnimation(.snappy(duration: 0.15)) { state.isConfirming = true }
            state.reset?.cancel()
            state.reset = Task {
                try? await Task.sleep(for: .seconds(1.4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) { state.isConfirming = false }
            }
        } label: {
            HStack(spacing: 5) {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12.5))
                }
                Text(isDone ? "Saved" : "Save Feedback")
                    .font(.system(size: 11.5, weight: .semibold))
                if waiting != nil, !isDone {
                    // Someone is listening: saving reaches them at once.
                    Circle()
                        .fill(Color(nsColor: .systemGreen))
                        .frame(width: 6, height: 6)
                        .opacity(isPulsing ? 0.45 : 1)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: isPulsing)
                        .onAppear { isPulsing = true }
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .foregroundStyle(isHovered ? palette.ink : palette.ink2)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.feedbackWash.opacity(isHovered ? 1.6 : 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }

    private var help: String {
        let drafts = count == 1 ? "1 draft" : "\(count) drafts"
        let shortcut = Shortcuts.shared.label(.saveFeedback)
        if let waiting {
            return "\(waiting) is waiting for your feedback: save \(drafts) in \(workspace) and it gets them now" + shortcut
        }
        return "Save \(drafts) in \(workspace), for your agents" + shortcut
    }
}

private struct FeedbackButton<Icon: View, Items: View>: View {
    let count: Int
    let help: String
    let copy: () -> Void
    @ViewBuilder let menu: () -> Items
    @ViewBuilder let icon: () -> Icon
    @Environment(\.palette) private var palette
    @State private var isHovered = false
    @State private var copied = false
    @State private var reset: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            Button {
                copy()
                withAnimation(.snappy(duration: 0.15)) { copied = true }
                reset?.cancel()
                reset = Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.2)) { copied = false }
                }
            } label: {
                HStack(spacing: 5) {
                    if copied {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        icon()
                    }
                    Text(copied ? "Copied" : "\(count)")
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .foregroundStyle(isHovered ? palette.ink : palette.ink2)
                .padding(.leading, 8)
                .padding(.trailing, 5)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)

            Rectangle()
                .fill(palette.ink.opacity(isHovered ? 0.12 : 0))
                .frame(width: 1, height: 14)

            Menu { menu() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isHovered ? palette.ink2 : palette.ink3)
                    .frame(width: 18, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Copy or clear")
        }
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.feedbackWash.opacity(isHovered ? 1.6 : 1))
        )
        .onHover { isHovered = $0 }
    }
}
