import SwiftUI
import WebKit

/// The page: the reader web view, a top strip with the few controls a
/// reader needs, and the find bar.
struct PageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

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
    }

    private var topStrip: some View {
        HStack(spacing: 4) {
            Spacer()
            if model.isFindVisible {
                FindBar()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if model.current?.changes.isEmpty == false {
                IconButton(systemName: "arrow.down.to.line.compact", help: "Next Change (⌘J)") {
                    model.jumpToChange(1)
                }
            }
            IconButton(systemName: "magnifyingglass", help: "Find (⌘F)", isActive: model.isFindVisible) {
                withAnimation(.easeOut(duration: 0.18)) {
                    if model.isFindVisible { model.hideFind() } else { model.showFind() }
                }
            }
            IconButton(systemName: "textformat.size", help: "Appearance", isActive: model.isAppearanceVisible) {
                model.isAppearanceVisible.toggle()
            }
            .popover(isPresented: Bindable(model).isAppearanceVisible, arrowEdge: .bottom) {
                AppearancePopover()
                    .environment(model)
                    .environment(\.palette, palette)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: MainView.bandHeight)
        .padding(.top, 2)
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
