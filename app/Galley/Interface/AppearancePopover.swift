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
            Picker("Appearance", selection: $settings.appearance) {
                Text("Auto").tag(AppearanceMode.system)
                Text("Light").tag(AppearanceMode.light)
                Text("Dark").tag(AppearanceMode.dark)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 10) {
                ForEach(Theme.light) { swatch($0) }
            }
            HStack(spacing: 10) {
                ForEach(Theme.dark) { swatch($0) }
            }
        }
    }

    private func swatch(_ theme: Theme) -> some View {
        let settings = model.settings
        let isActive = model.theme.id == theme.id
        let isChosen = theme.isDark ? settings.darkTheme == theme.id : settings.lightTheme == theme.id
        return Button {
            if theme.isDark {
                settings.darkTheme = theme.id
                if !model.isDark { settings.appearance = .dark }
            } else {
                settings.lightTheme = theme.id
                if model.isDark { settings.appearance = .light }
            }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(css: theme.paper))
                    Text("Aa")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(Color(css: theme.ink))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(css: theme.change))
                        .frame(width: 3, height: 14)
                        .offset(x: -24)
                }
                .frame(width: 78, height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(isActive ? Color.accentColor : Color.primary.opacity(isChosen ? 0.35 : 0.12),
                                      lineWidth: isActive ? 2 : 1)
                )
                Text(theme.name)
                    .font(.system(size: 10.5, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Size")
                    .foregroundStyle(.secondary)
                Spacer()
                Button { settings.adjustFontSize(by: -1) } label: {
                    Image(systemName: "textformat.size.smaller").frame(width: 26, height: 20)
                }
                .disabled(settings.fontSize <= ReaderSettings.fontSizes.lowerBound)
                Text("\(Int(settings.fontSize)) pt")
                    .monospacedDigit()
                    .frame(width: 42)
                Button { settings.adjustFontSize(by: 1) } label: {
                    Image(systemName: "textformat.size.larger").frame(width: 26, height: 20)
                }
                .disabled(settings.fontSize >= ReaderSettings.fontSizes.upperBound)
            }
            .buttonStyle(.borderless)
            row("Spacing") {
                Picker("Spacing", selection: $settings.lineSpacing) {
                    ForEach(LineSpacing.allCases) { Text($0.label).tag($0) }
                }
            }
            row("Width") {
                Picker("Width", selection: $settings.lineWidth) {
                    ForEach(LineWidth.allCases) { Text($0.label).tag($0) }
                }
            }
            Toggle("Mark changes since last read", isOn: $settings.showChanges)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .font(.system(size: 12))
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            content()
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
        }
    }
}
