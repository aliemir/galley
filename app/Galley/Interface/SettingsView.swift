import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ReadingSettings()
                .tabItem { Label("Reading", systemImage: "book") }
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "textformat.size") }
        }
        .frame(width: 460)
    }
}

private struct ReadingSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Picker("Show files by", selection: $settings.nameStyle) {
                ForEach(NameStyle.allCases) { Text($0.label).tag($0) }
            }
            Text("“2026-10-30_auth-migrationPlan.md” reads as “Auth migration plan”. The real name is always in the tooltip.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Continue to", selection: $settings.continueOrder) {
                ForEach(ContinueOrder.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Pull past the end of a page to open the next one", isOn: $settings.pullToContinue)
            Toggle("Mark what changed since I last read a file", isOn: $settings.showChanges)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(height: 300)
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
                    Stepper(value: $settings.fontSize, in: ReaderSettings.fontSizes, step: 1) {
                        Text("\(Int(settings.fontSize)) pt").monospacedDigit()
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
        .frame(height: 420)
    }
}
