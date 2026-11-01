import SwiftUI

struct SettingsView: View {
    @AppStorage("settingsTab") private var tab = "reading"

    var body: some View {
        TabView(selection: $tab) {
            ReadingSettings()
                .tabItem { Label("Reading", systemImage: "book") }
                .tag("reading")
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "textformat.size") }
                .tag("appearance")
        }
        .frame(width: 460)
    }
}

private struct ReadingSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Picker(selection: $settings.nameStyle) {
                ForEach(NameStyle.allCases) { Text($0.label).tag($0) }
            } label: {
                Text("Show files by")
                Text("“2026-10-30_auth-migrationPlan.md” reads as “Auth migration plan”, and folders are tidied the same way unless you pick file names. The real name is always in the tooltip.")
            }

            Picker("Continue to", selection: $settings.continueOrder) {
                ForEach(ContinueOrder.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Pull past the top or end of a page for the previous or next one", isOn: $settings.pullToContinue)
            Toggle("Mark what changed since I last read a file", isOn: $settings.showChanges)

            Section {
                ColumnOrderList()
                Toggle("Show workspaces as icons only", isOn: $settings.workspacesAsIcons)
            } header: {
                Text("Columns")
            } footer: {
                Text("Swiping right reveals them from the top down, and swiping left puts them away in reverse; ⌘] and ⌘[ do the same. Each keeps its place on screen. Drag to reorder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AppearanceSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                ThemePicker()
                    .padding(.vertical, 4)
            }
            Section {
                Picker("Typeface", selection: $settings.font) {
                    ForEach(ReadingFont.allCases) { font in
                        Text(font.label).font(font.font(size: 13)).tag(font)
                    }
                }
                LabeledContent("Size") {
                    HStack(spacing: 6) {
                        Text("\(Int(settings.fontSize)) pt").monospacedDigit()
                        Stepper("Size", value: $settings.fontSize, in: ReaderSettings.fontSizes, step: 1)
                            .labelsHidden()
                    }
                }
                Picker("Line spacing", selection: $settings.lineSpacing) {
                    ForEach(LineSpacing.allCases) { Text($0.label).tag($0) }
                }
                Picker("Line width", selection: $settings.lineWidth) {
                    ForEach(LineWidth.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
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
                    get: { !settings.hiddenColumns.contains(column) },
                    set: { model.setColumnHidden(column, !$0) }
                ))
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
