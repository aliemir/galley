import SwiftUI

/// Theme, typeface and layout — the "Aa" button.
struct AppearancePopover: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ThemePicker()
            Divider()
            FontPicker()
            Divider()
            LayoutControls()
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct ThemePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        VStack(alignment: .leading, spacing: 12) {
            Segments(title: "Appearance", options: AppearanceMode.allCases, selection: $settings.appearance) {
                $0 == .system ? "Auto" : $0.label
            }

            // The themes for what is on screen now; the rest are a click away.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                ForEach(model.isDark ? Theme.dark : Theme.light) { swatch($0) }
            }
            Button("All Themes…") {
                Preferences.store.set("themes", forKey: "settingsTab")
                model.isAppearanceVisible = false
                openSettings()
            }
            .buttonStyle(.link)
            .font(.system(size: 11.5))
        }
    }

    @Environment(\.openSettings) private var openSettings

    private func swatch(_ theme: Theme) -> some View {
        let settings = model.settings
        let isActive = model.theme.id == theme.id
        let isChosen = theme.isDark ? settings.darkTheme == theme.id : settings.lightTheme == theme.id
        return Button {
            ThemeChoice.choose(theme, model: model)
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(css: theme.paper))
                    Text("Aa")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(Color(css: theme.ink))
                }
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(css: theme.change))
                        .frame(width: 3, height: 14)
                        .padding(.leading, 13)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(isActive ? Color.accentColor : Color.primary.opacity(isChosen ? 0.35 : 0.12),
                                      lineWidth: isActive ? 2 : 1)
                )
                Text(theme.name)
                    .font(.system(size: 10.5, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.name) theme")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct FontPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(ReadingFont.allCases) { font in
                let isSelected = settings.font == font
                Button {
                    settings.font = font
                } label: {
                    Text(font.label)
                        .font(font.font(size: 14))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                        )
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct LayoutControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        // Labels in one column, controls filling the other, so every control
        // shares one left edge and one right edge.
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                label("Size")
                HStack(spacing: 0) {
                    Button { settings.adjustFontSize(by: -1) } label: {
                        Image(systemName: "textformat.size.smaller")
                            .frame(width: 44, height: 24)
                            .contentShape(Rectangle())
                    }
                    .disabled(settings.fontSize <= ReaderSettings.fontSizes.lowerBound)
                    .help("Smaller Text" + Shortcuts.shared.label(.smallerText))
                    Text("\(Int(settings.fontSize)) pt")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                    Button { settings.adjustFontSize(by: 1) } label: {
                        Image(systemName: "textformat.size.larger")
                            .frame(width: 44, height: 24)
                            .contentShape(Rectangle())
                    }
                    .disabled(settings.fontSize >= ReaderSettings.fontSizes.upperBound)
                    .help("Bigger Text" + Shortcuts.shared.label(.biggerText))
                }
                .buttonStyle(.plain)
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            GridRow {
                label("Spacing")
                Segments(title: "Spacing", options: LineSpacing.allCases, selection: $settings.lineSpacing) { $0.label }
            }
            GridRow {
                label("Width")
                Segments(title: "Width", options: LineWidth.allCases, selection: $settings.lineWidth) { $0.label }
            }
            GridRow {
                HStack {
                    Text("Mark changes since last read")
                    Spacer()
                    Toggle("Mark changes since last read", isOn: $settings.showChanges)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                .gridCellColumns(2)
            }
        }
        .font(.system(size: 12))
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.leading)
    }
}

/// A segmented choice whose segments share the full width equally. The
/// system segmented picker keeps its intrinsic width on macOS, so rows of
/// them never line up.
struct Segments<Value: Hashable & Identifiable>: View {
    let title: String
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button { selection = option } label: {
                    Text(label(option))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .foregroundStyle(isSelected ? Color.white : .primary)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.accentColor : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .font(.system(size: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
