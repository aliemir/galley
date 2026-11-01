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
            Toggle("Pull past the end of a page to open the next one", isOn: $settings.pullToContinue)
            Toggle("Mark what changed since I last read a file", isOn: $settings.showChanges)
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
