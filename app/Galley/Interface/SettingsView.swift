import SwiftUI

struct SettingsView: View {
    @AppStorage("settingsTab", store: Preferences.store) private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            TypographySettings()
                .tabItem { Label("Reading", systemImage: "textformat") }
                .tag("reading")
            ThemeGallery()
                .tabItem { Label("Themes", systemImage: "swatchpalette") }
                .tag("themes")
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "command") }
                .tag("shortcuts")
            AppIconSettings()
                .tabItem { Label("App Icon", systemImage: "app.badge.checkmark") }
                .tag("icon")
            AgentSetupView(place: .settings)
                .tabItem { Label("Agents", systemImage: "terminal") }
                .tag("agents")
        }
        .frame(width: SettingsView.width)
    }

    static let width: CGFloat = 580
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    /// A shortcut as the reader has it, for the explanation below the columns.
    private func key(_ action: ShortcutAction) -> String {
        Shortcuts.shared[action]?.display ?? "its shortcut"
    }

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                Picker(selection: $settings.nameStyle) {
                    ForEach(NameStyle.allCases) { Text($0.label).tag($0) }
                } label: {
                    Text("Show files by")
                    Text("“2026-10-30_auth-migrationPlan.md” reads as “Auth Migration Plan”, and folders are tidied the same way unless you pick file names. The real name is always in the tooltip.")
                }
                Picker("Continue to", selection: $settings.continueOrder) {
                    ForEach(ContinueOrder.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Pull past the top or end of a page for the previous or next one", isOn: $settings.pullToContinue)
                Toggle("Mark what changed since I last read a file", isOn: $settings.showChanges)
                Toggle(isOn: $settings.showComments) {
                    Text("Show hidden comments")
                    Text("HTML comments (<!-- … -->) are invisible in a rendered page but plain to an agent reading the file.")
                }
                Toggle("Show the number of files to read on the Dock icon", isOn: $settings.dockBadge)
            }

            Section {
                Toggle(isOn: $settings.draftFeedback) {
                    Text("Keep highlights and notes as drafts until I save them")
                    Text("Agents see your feedback once you save it, with Save Feedback or \(key(.saveFeedback)), so they can wait for it with `galley feedback --wait`. Drafts are dashed on the page. Off, agents see each mark as you make it.")
                }
            } header: {
                Text("Feedback")
            }

            Section {
                @Bindable var updates = Updates.shared
                Toggle(isOn: $updates.checksAutomatically) {
                    Text("Check for updates automatically")
                    Text("Once a day, from Galley's releases on GitHub. Nothing about you or your files is sent.")
                }
                .disabled(!Updates.isAvailable)
                Button("Check Now…") { Updates.shared.checkNow() }
                    .disabled(!Updates.isAvailable)
            } header: {
                Text("Updates")
            }

            Section {
                Toggle("Find", isOn: $settings.showFindButton)
                Toggle("Appearance", isOn: $settings.showAppearanceButton)
            } header: {
                Text("Buttons at the top right")
            } footer: {
                Text("Find still opens with \(key(.find)), and its button shows while the bar is open. Everything in Appearance is also under Reading and Themes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ColumnOrderList()
                Toggle("Show workspaces as icons only", isOn: $settings.workspacesAsIcons)
            } header: {
                Text("Columns")
            } footer: {
                Text("Swiping right brings them in from the top down, and swiping left takes them away in reverse; \(key(.showNextPanel)) and \(key(.hideLastPanel)) do the same. Drag to reorder; switch one off and swipes pass over it. Each column keeps its place, and \(key(.toggleWorkspaces)), \(key(.toggleFiles)) and \(key(.toggleContents)) show or hide Workspaces, Files and Contents on their own; \(key(.togglePanels)) hides them all.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Typeface, size and the shape of the column.
private struct TypographySettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Typeface") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(ReadingFont.allCases) { font in
                        FontCard(font: font, isSelected: settings.font == font) { settings.font = font }
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                LabeledContent("Size") {
                    HStack(spacing: 10) {
                        Slider(value: $settings.fontSize, in: ReaderSettings.fontSizes, step: 1)
                            .frame(width: 220)
                        Text("\(Int(settings.fontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                    }
                }
                LabeledContent("Line spacing") {
                    Segments(title: "Line spacing", options: LineSpacing.allCases, selection: $settings.lineSpacing) { $0.label }
                        .frame(width: 274)
                }
                LabeledContent("Line width") {
                    Segments(title: "Line width", options: LineWidth.allCases, selection: $settings.lineWidth) { $0.label }
                        .frame(width: 274)
                }
            } footer: {
                HStack {
                    Spacer()
                    Button("Restore Defaults") { settings.restoreTypography() }
                        .disabled(settings.typographyIsDefault)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A typeface shown in itself: a large "Aa" and its name.
private struct FontCard: View {
    let font: ReadingFont
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("Aa")
                    .font(font.font(size: 26))
                    // Faces sit at different heights: a fixed frame keeps the cards even.
                    .frame(height: 36)
                Text(font.label)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(font.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Every theme as a small page of itself: its paper and inks, a change, a
/// highlight, a link and a line of code, as the reader will see them.
struct ThemeGallery: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        VStack(spacing: 0) {
            HStack {
                Text("Appearance")
                Segments(title: "Appearance", options: AppearanceMode.allCases, selection: $settings.appearance) {
                    $0 == .system ? "Auto" : $0.label
                }
                .frame(width: 240)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    section("Light", Theme.light, footnote: settings.appearance == .system ? "Used while macOS is in Light Mode." : nil)
                    section("Dark", Theme.dark, footnote: settings.appearance == .system ? "Used while macOS is in Dark Mode." : nil)
                }
                .padding(20)
            }
            .frame(height: 520)
        }
    }

    private func section(_ title: String, _ themes: [Theme], footnote: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                if let footnote { Text(footnote).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(.top, title == "Light" ? 0 : 12)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(themes) { ThemeCard(theme: $0) }
            }
        }
    }
}

private struct ThemeCard: View {
    let theme: Theme
    @Environment(AppModel.self) private var model
    @State private var isHovered = false

    private var isActive: Bool { model.theme.id == theme.id }
    private var isChosen: Bool {
        theme.isDark ? model.settings.darkTheme == theme.id : model.settings.lightTheme == theme.id
    }

    var body: some View {
        let ink = Color(css: theme.ink)
        Button { ThemeChoice.choose(theme, model: model) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(theme.name)
                        .font(model.settings.font.font(size: 17).weight(.bold))
                        .foregroundStyle(ink)
                    Spacer()
                    if isChosen {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(css: theme.accent))
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    // The margin bar a change gets on the page.
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(css: theme.change))
                        .frame(width: 3)
                    Text(sample)
                        .font(model.settings.font.font(size: 13.5))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(css: theme.codeBackground)))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(css: theme.paper)))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor : Color.primary.opacity(isHovered ? 0.25 : 0.12),
                                  lineWidth: isActive ? 2.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(theme.name) theme")
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private var sample: AttributedString {
        func run(_ text: String, _ configure: (inout AttributedString) -> Void = { _ in }) -> AttributedString {
            var part = AttributedString(text)
            part.foregroundColor = Color(css: theme.ink)
            configure(&part)
            return part
        }
        return run("The agent ")
            + run("rewrote the plan") { $0.backgroundColor = Color(css: theme.insert) }
            + run(" overnight; you ")
            + run("marked a step") { $0.backgroundColor = Color(css: theme.highlight) }
            + run(" and ")
            + run("the next file") { $0.foregroundColor = Color(css: theme.accent); $0.underlineStyle = .single }
            + run(" waits.") { $0.foregroundColor = Color(css: theme.inkSecondary) }
    }

    private var code: AttributedString {
        func run(_ text: String, _ hex: String) -> AttributedString {
            var part = AttributedString(text)
            part.foregroundColor = Color(css: hex)
            return part
        }
        return run("func ", theme.codeKeyword) + run("read", theme.codeFunction) + run("(", theme.ink)
            + run("\"plan.md\"", theme.codeString) + run(", ", theme.ink) + run("2", theme.codeNumber) + run(")", theme.ink)
    }
}

/// Choosing a theme: it becomes the light or dark one, and when the page is
/// showing the other kind, the appearance follows so the choice is seen.
enum ThemeChoice {
    @MainActor
    static func choose(_ theme: Theme, model: AppModel) {
        let settings = model.settings
        if theme.isDark {
            settings.darkTheme = theme.id
            if !model.isDark { settings.appearance = .dark }
        } else {
            settings.lightTheme = theme.id
            if model.isDark { settings.appearance = .light }
        }
    }
}

/// The columns in swipe order, dragged to reorder, each with its switch.
private struct ColumnOrderList: View {
    @Environment(AppModel.self) private var model
    @State private var dropTarget: PanelColumn?

    var body: some View {
        let settings = model.settings
        ForEach(Array(settings.columnOrder.enumerated()), id: \.element) { index, column in
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                Text("\(index + 1)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Toggle(column.title, isOn: Binding(
                    get: { !settings.swipeSkips.contains(column) },
                    set: { model.setSwipeSkips(column, !$0) }
                ))
                .help("Off: swipes pass over \(column.title); its shortcut still shows it")
            }
            .padding(.vertical, 1)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if dropTarget == column {
                    Rectangle().fill(Color.accentColor).frame(height: 2).offset(y: -6)
                }
            }
            .draggable(column.rawValue) {
                Label(column.title, systemImage: "line.3.horizontal")
                    .padding(6)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let dragged = items.first.flatMap(PanelColumn.init(rawValue:)),
                      let from = settings.columnOrder.firstIndex(of: dragged),
                      let to = settings.columnOrder.firstIndex(of: column) else { return false }
                withAnimation(.snappy(duration: 0.2)) {
                    // Dropped on a row: take that row's place.
                    model.moveColumns(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
                }
                return true
            } isTargeted: { targeted in
                dropTarget = targeted ? column : (dropTarget == column ? nil : dropTarget)
            }
            .accessibilityAction(named: "Move Up") {
                if index > 0 { model.moveColumns(from: IndexSet(integer: index), to: index - 1) }
            }
            .accessibilityAction(named: "Move Down") {
                if index < settings.columnOrder.count - 1 { model.moveColumns(from: IndexSet(integer: index), to: index + 2) }
            }
        }
    }
}

/// Galley's icon in other colours, for the Dock.
private struct AppIconSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 18) {
                ForEach(AppIcon.variants, id: \.id) { variant in
                    let isChosen = model.settings.appIcon == variant.id
                    Button { model.settings.appIcon = variant.id } label: {
                        VStack(spacing: 6) {
                            Group {
                                if let image = AppIcon.image(variant.id) {
                                    Image(nsImage: image).resizable().interpolation(.high)
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(width: 76, height: 76)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(isChosen ? Color.accentColor.opacity(0.16) : .clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(isChosen ? Color.accentColor : .clear, lineWidth: 2)
                            )
                            Text(variant.name)
                                .font(.system(size: 11.5, weight: isChosen ? .semibold : .regular))
                                .foregroundStyle(isChosen ? .primary : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(variant.name) icon")
                    .accessibilityAddTraits(isChosen ? .isSelected : [])
                }
            }
            Text("Shown in the Dock while Galley is open. Finder keeps the standard icon.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}
