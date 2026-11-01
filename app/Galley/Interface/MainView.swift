import SwiftUI
import UniformTypeIdentifiers

/// The one window: Workspaces · Files · Outline · Page, left to right.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var systemScheme
    @State private var gestures: GestureMonitor?
    @State private var isDropTargeted = false

    /// The empty strip at the top of every column, where the traffic lights sit.
    static let bandHeight: CGFloat = 40

    var body: some View {
        let palette = model.palette
        Group {
            if model.workspaces.isEmpty {
                WelcomeView()
            } else {
                ColumnStack()
            }
        }
        .environment(\.palette, palette)
        .frame(minWidth: 560, minHeight: 420)
        .background(palette.paper)
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            if !model.workspaces.isEmpty { PanelToggle().ignoresSafeArea() }
        }
        .overlay { if isDropTargeted { DropHighlight() } }
        .overlay(alignment: .top) {
            if model.isQuickOpenVisible {
                ZStack(alignment: .top) {
                    palette.paper.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { model.isQuickOpenVisible = false }
                    QuickOpenView()
                        .padding(.top, 86)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.14), value: model.isQuickOpenVisible)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .preferredColorScheme(preferredScheme)
        .onChange(of: systemScheme, initial: true) { _, scheme in
            // With a forced appearance the environment reports the forced
            // scheme; only the system setting should drive "Match System".
            if model.settings.appearance == .system { model.colorScheme = scheme }
        }
        .background(WindowAccessor { window in
            configure(window)
        })
        .navigationTitle(windowTitle)
        .tint(palette.accent)
    }

    private var preferredScheme: ColorScheme? {
        switch model.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var windowTitle: String {
        guard let current = model.current else { return "Galley" }
        return model.settings.displayName(for: current.file)
    }

    private func configure(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.tabbingMode = .disallowed
        if gestures == nil { gestures = GestureMonitor(window: window, model: model) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.addWorkspace(url) }
            }
        }
        return handled
    }
}

// MARK: - Columns

private struct ColumnStack: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    private static let minimumPage: CGFloat = 420

    var body: some View {
        GeometryReader { geometry in
            let fit = fitting(available: geometry.size.width)
            HStack(spacing: 0) {
                // Places are fixed; the reader's order only decides which
                // column a swipe brings in next.
                ForEach(PanelColumn.arrangement) { column in
                    self.column(column, scale: fit.scale, fitting: fit.columns)
                }
                PageView()
                    .frame(minWidth: 280, maxWidth: .infinity)
                    .layoutPriority(1)
            }
        }
    }

    private static let minimumScale: CGFloat = 0.72

    /// Columns give up some width before the page does; when even narrowed
    /// columns do not fit, the ones latest in the reader's order step aside
    /// (without being hidden, so they return when the window grows).
    private func fitting(available: CGFloat) -> (scale: CGFloat, columns: Set<PanelColumn>) {
        // While a swipe is revealing a column, fit it too, or it would be
        // over the limit and stay hidden.
        var wanted = model.visibleColumns
        if model.swipeProgress > 0, let incoming = model.nextToReveal { wanted.insert(incoming) }
        var ranked = model.settings.columnOrder.filter(wanted.contains)
        while !ranked.isEmpty {
            let needed = ranked.reduce(0) { $0 + model.columnWidth($1) }
            let scale = min(1, (available - Self.minimumPage) / needed)
            if scale >= Self.minimumScale { return (scale, Set(ranked)) }
            ranked.removeLast()
        }
        return (1, [])
    }

    /// How much of a column shows: 1 when it is in, 0 when out, and in
    /// between while a swipe is moving it.
    private func fraction(_ column: PanelColumn, fitting: Set<PanelColumn>) -> CGFloat {
        guard fitting.contains(column) else { return 0 }
        let progress = model.swipeProgress
        if progress > 0, column == model.nextToReveal { return progress }
        if progress < 0, column == model.nextToHide { return 1 + progress }
        return model.isShowing(column) ? 1 : 0
    }

    @ViewBuilder
    private func content(_ column: PanelColumn) -> some View {
        switch column {
        case .outline: OutlineColumn()
        case .files: FilesColumn()
        case .workspaces: WorkspacesColumn()
        }
    }

    private func column(_ column: PanelColumn, scale: CGFloat, fitting: Set<PanelColumn>) -> some View {
        let isRail = column == .workspaces && model.settings.workspacesAsIcons
        let width = model.columnWidth(column) * (isRail ? 1 : scale)
        let fraction = fraction(column, fitting: fitting)
        return content(column)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background(palette.sidebar)
            .overlay(alignment: .trailing) {
                ColumnDivider(column: column, scale: isRail ? 1 : scale)
            }
            .frame(width: width * fraction, alignment: .trailing)
            .clipped()
            .opacity(fraction > 0.02 ? 1 : 0)
            .allowsHitTesting(fraction > 0.98)
            .accessibilityHidden(fraction < 0.5)
    }
}

/// A column's right edge: the hairline, and a wider invisible grip that
/// drags the width. Double-click puts the default width back.
///
/// Workspaces fold into the icon rail when dragged narrow enough, and the
/// rail opens back into the list when dragged wide again, as Finder's
/// sidebar does; the gap between the two thresholds keeps it from flapping.
private struct ColumnDivider: View {
    let column: PanelColumn
    let scale: CGFloat
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var startWidth: CGFloat?
    @State private var startScale: CGFloat = 1
    @State private var dividerHeight: CGFloat = 800
    @State private var isHovered = false

    private var isRail: Bool { column == .workspaces && model.settings.workspacesAsIcons }

    var body: some View {
        ZStack(alignment: .trailing) {
            Rectangle()
                .fill(startWidth != nil || isHovered ? palette.accent.opacity(0.55) : palette.rule)
                .frame(width: startWidth != nil || isHovered ? 2 : 1)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                // The title band is one clean strip: the line fades in below
                // it, so it never runs through the traffic lights.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: MainView.bandHeight / max(1, dividerHeight)),
                            .init(color: .black, location: (MainView.bandHeight + 16) / max(1, dividerHeight)),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            Color.clear
                .frame(width: 9)
                .contentShape(Rectangle())
                .offset(x: 4)
                .pointerStyle(.columnResize)
                .onHover { isHovered = $0 }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            if startWidth == nil {
                                startWidth = model.columnWidth(column)
                                startScale = max(scale, 0.5)
                                model.beginPanelMotion()
                            }
                            // The scale the drag began with, so folding mid-drag
                            // does not shift where the thresholds are.
                            model.dragColumnEdge(column, to: (startWidth ?? 0) + drag.translation.width / startScale)
                        }
                        .onEnded { _ in
                            startWidth = nil
                            model.endPanelMotion()
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.galleyPanel) {
                        if isRail { model.settings.workspacesAsIcons = false }
                        model.setColumnWidth(column, nil)
                    }
                }
                .help(isRail
                    ? "Drag wider to show names · double-click for the list"
                    : column == .workspaces
                        ? "Drag to resize, or narrow to icons · double-click for the default width"
                        : "Drag to resize · double-click for the default width")
        }
        .frame(maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { dividerHeight = $0 }
    }
}

/// The button beside the traffic lights: page alone, or the panels back.
private struct PanelToggle: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        IconButton(systemName: "sidebar.left", help: model.visibleColumns.isEmpty ? "Show Panels (⌘\\)" : "Focus on the Page (⌘\\)") {
            model.togglePanels()
        }
        .padding(.leading, 80)
        .padding(.top, 8)
    }
}

/// A quiet toolbar-style icon button drawn in the theme's ink.
struct IconButton: View {
    let systemName: String
    let help: String
    var isActive = false
    let action: () -> Void
    @Environment(\.palette) private var palette
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isActive ? palette.accent : (isHovered ? palette.ink2 : palette.ink3))
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovered || isActive ? palette.hover.opacity(2) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct DropHighlight: View {
    @Environment(\.palette) private var palette

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(palette.accent.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            .background(palette.accent.opacity(0.04))
            .padding(10)
            .overlay {
                Label("Drop to add as a workspace", systemImage: "folder.badge.plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(palette.paper))
            }
            .allowsHitTesting(false)
    }
}

/// Hands the hosting `NSWindow` to SwiftUI code once it exists.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Column chrome

/// The title row every column starts with, just below the title-bar band
/// (which holds the traffic lights and stays empty and draggable).
struct ColumnHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.ink3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            accessory()
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 40)
        .padding(.top, MainView.bandHeight)
        .background(alignment: .top) { TitleBand() }
    }
}

/// The empty strip under the traffic lights: drags the window, and a
/// double-click zooms it, as a title bar would.
struct TitleBand: View {
    var body: some View {
        Color.clear
            .frame(height: MainView.bandHeight)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .onTapGesture(count: 2) { NSApp.keyWindow?.performZoom(nil) }
            .allowsWindowActivationEvents(true)
    }
}

/// Small caps section label inside a column.
struct SectionLabel: View {
    let title: String
    var count: Int?
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(palette.ink3)
            if let count {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.ink3)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}

/// A count in a small capsule, tinted for what it counts.
struct CountBadge: View {
    enum Kind { case new, changed, feedback }

    let count: Int
    let kind: Kind
    @Environment(\.palette) private var palette

    var body: some View {
        Text("\(count)")
            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(foreground)
            .padding(.horizontal, 5.5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(background))
            .help(help)
    }

    private var foreground: Color {
        switch kind {
        case .new: palette.unread
        case .changed: palette.change
        case .feedback: palette.feedback
        }
    }

    private var background: Color {
        switch kind {
        case .new: palette.unread.opacity(0.12)
        case .changed: palette.change.opacity(0.13)
        case .feedback: palette.feedbackWash
        }
    }

    private var help: String {
        switch kind {
        case .new: count == 1 ? "1 file not read yet" : "\(count) files not read yet"
        case .changed: count == 1 ? "1 file changed since read" : "\(count) files changed since read"
        case .feedback: count == 1 ? "1 highlight or note" : "\(count) highlights and notes"
        }
    }
}

/// Everything a workspace has waiting: new, changed, feedback — each only
/// when there is some.
struct WorkspaceBadges: View {
    let workspace: Workspace

    var body: some View {
        HStack(spacing: 3) {
            if workspace.newCount > 0 { CountBadge(count: workspace.newCount, kind: .new) }
            if workspace.changedCount > 0 { CountBadge(count: workspace.changedCount, kind: .changed) }
            if workspace.feedbackCount > 0 { CountBadge(count: workspace.feedbackCount, kind: .feedback) }
        }
        // Counts keep their size; the name beside them truncates instead.
        .fixedSize()
        .layoutPriority(1)
    }
}

extension Workspace {
    /// "2 new, 1 changed, 4 feedback" for tooltips and VoiceOver.
    var badgeSummary: String {
        var parts: [String] = []
        if newCount > 0 { parts.append("\(newCount) new") }
        if changedCount > 0 { parts.append("\(changedCount) changed") }
        if feedbackCount > 0 { parts.append("\(feedbackCount) feedback") }
        return parts.joined(separator: ", ")
    }
}
