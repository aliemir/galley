import SwiftUI

/// A curated reading theme. Colours are hex strings so the same values feed
/// the SwiftUI chrome and the page's CSS variables.
nonisolated struct Theme: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isDark: Bool

    let paper: String
    let ink: String
    let inkSecondary: String
    let inkTertiary: String
    let accent: String
    let rule: String
    let codeBackground: String
    let sidebar: String
    let selection: String
    /// Margin change bars and the "changed" badge.
    let change: String
    /// Background wash behind added blocks.
    let changeWash: String
    /// Inserted words inside a modified block.
    let insert: String
    /// `==marked==` text: the document's own emphasis, the highlighter's yellow.
    let mark: String
    /// The reader's highlights: the feedback purple, washed, so they never
    /// read as the agent's changes (amber) or as something new (blue).
    let highlight: String
    let unread: String

    let codeKeyword: String
    let codeString: String
    let codeNumber: String
    let codeType: String
    let codeFunction: String

    var cssVariables: [String: String] {
        [
            "--paper": paper, "--ink": ink, "--ink-2": inkSecondary, "--ink-3": inkTertiary,
            "--accent": accent, "--rule": rule, "--code-bg": codeBackground, "--selection": selection,
            "--change": change, "--change-wash": changeWash, "--insert": insert, "--mark": mark, "--hl": highlight,
            "--code-keyword": codeKeyword, "--code-string": codeString, "--code-number": codeNumber,
            "--code-type": codeType, "--code-function": codeFunction,
        ]
    }
}

extension Theme {
    static let paper = Theme(
        id: "paper", name: "Paper", isDark: false,
        paper: "#FCFBF8", ink: "#1E1D1A", inkSecondary: "#6B665D", inkTertiary: "#A29C92",
        accent: "#2C5E91", rule: "#E7E3DB", codeBackground: "#F4F1EA", sidebar: "#F3F0E9",
        selection: "rgba(44, 94, 145, 0.18)",
        change: "#D3802A", changeWash: "rgba(237, 178, 72, 0.13)", insert: "rgba(237, 178, 72, 0.34)",
        mark: "rgba(255, 214, 79, 0.55)", highlight: "rgba(146, 98, 222, 0.26)", unread: "#2C6FD1",
        codeKeyword: "#A3366E", codeString: "#3F7A3A", codeNumber: "#B05B12", codeType: "#6A44A8", codeFunction: "#2C5E91"
    )

    static let snow = Theme(
        id: "snow", name: "Snow", isDark: false,
        paper: "#FFFFFF", ink: "#1D1D1F", inkSecondary: "#6E6E73", inkTertiary: "#A1A1A6",
        accent: "#0A63D2", rule: "#E5E5EA", codeBackground: "#F5F5F7", sidebar: "#F2F2F4",
        selection: "rgba(10, 99, 210, 0.16)",
        change: "#0A84FF", changeWash: "rgba(10, 132, 255, 0.07)", insert: "rgba(10, 132, 255, 0.2)",
        mark: "rgba(255, 214, 10, 0.5)", highlight: "rgba(146, 98, 222, 0.24)", unread: "#0A84FF",
        codeKeyword: "#AD3DA4", codeString: "#C41A16", codeNumber: "#1C00CF", codeType: "#5C2699", codeFunction: "#326D74"
    )

    static let sepia = Theme(
        id: "sepia", name: "Sepia", isDark: false,
        paper: "#F6EFE1", ink: "#3A2F24", inkSecondary: "#7A6A57", inkTertiary: "#AE9E89",
        accent: "#9A4A1F", rule: "#E4D8C2", codeBackground: "#EEE4D0", sidebar: "#EEE5D3",
        selection: "rgba(154, 74, 31, 0.16)",
        change: "#B8661A", changeWash: "rgba(196, 128, 46, 0.12)", insert: "rgba(196, 128, 46, 0.3)",
        mark: "rgba(240, 196, 76, 0.5)", highlight: "rgba(140, 92, 200, 0.26)", unread: "#B5521F",
        codeKeyword: "#9A3A5C", codeString: "#5B6E24", codeNumber: "#A2541A", codeType: "#6B4A8A", codeFunction: "#2F5E7A"
    )

    static let graphite = Theme(
        id: "graphite", name: "Graphite", isDark: true,
        paper: "#1D1D1F", ink: "#E6E4E0", inkSecondary: "#9C9A95", inkTertiary: "#6B6966",
        accent: "#8DB6F7", rule: "#303033", codeBackground: "#262628", sidebar: "#18181A",
        selection: "rgba(141, 182, 247, 0.26)",
        change: "#E3A64E", changeWash: "rgba(227, 166, 78, 0.10)", insert: "rgba(227, 166, 78, 0.28)",
        mark: "rgba(227, 186, 60, 0.38)", highlight: "rgba(184, 153, 242, 0.34)", unread: "#5EA0FF",
        codeKeyword: "#F08DC0", codeString: "#A6D189", codeNumber: "#F2B482", codeType: "#C3A6F2", codeFunction: "#8DB6F7"
    )

    static let ink = Theme(
        id: "ink", name: "Ink", isDark: true,
        paper: "#111419", ink: "#D7DBE2", inkSecondary: "#8C94A2", inkTertiary: "#5B6271",
        accent: "#82B1FF", rule: "#232833", codeBackground: "#181C23", sidebar: "#0C0F13",
        selection: "rgba(130, 177, 255, 0.24)",
        change: "#F0BF4F", changeWash: "rgba(240, 191, 79, 0.08)", insert: "rgba(240, 191, 79, 0.26)",
        mark: "rgba(240, 191, 79, 0.34)", highlight: "rgba(184, 153, 242, 0.32)", unread: "#6AA5FF",
        codeKeyword: "#C792EA", codeString: "#A5D6A7", codeNumber: "#F7A072", codeType: "#82AAFF", codeFunction: "#89DDFF"
    )

    static let lamplight = Theme(
        id: "lamplight", name: "Lamplight", isDark: true,
        paper: "#201B16", ink: "#E8DCCB", inkSecondary: "#AA9B8A", inkTertiary: "#76695D",
        accent: "#E2A86E", rule: "#322A22", codeBackground: "#29221C", sidebar: "#1A1612",
        selection: "rgba(226, 168, 110, 0.24)",
        change: "#E9B44F", changeWash: "rgba(233, 180, 79, 0.09)", insert: "rgba(233, 180, 79, 0.27)",
        mark: "rgba(233, 180, 79, 0.36)", highlight: "rgba(196, 160, 236, 0.32)", unread: "#E9934F",
        codeKeyword: "#E59A86", codeString: "#B7C78A", codeNumber: "#E9B44F", codeType: "#C9A3D9", codeFunction: "#E2A86E"
    )

    static let all: [Theme] = [.paper, .snow, .sepia, .graphite, .ink, .lamplight]
    static let light = all.filter { !$0.isDark }
    static let dark = all.filter(\.isDark)

    static func named(_ id: String, fallback: Theme) -> Theme {
        all.first { $0.id == id } ?? fallback
    }
}

extension Color {
    /// `#RRGGBB` or `rgba(r, g, b, a)`.
    init(css: String) {
        let value = css.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#"), let number = UInt32(value.dropFirst(), radix: 16) {
            self.init(
                .sRGB,
                red: Double((number >> 16) & 0xFF) / 255,
                green: Double((number >> 8) & 0xFF) / 255,
                blue: Double(number & 0xFF) / 255
            )
            return
        }
        let parts = value
            .drop(while: { $0 != "(" }).dropFirst()
            .prefix(while: { $0 != ")" })
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count >= 3 {
            self.init(.sRGB, red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255,
                      opacity: parts.count > 3 ? parts[3] : 1)
        } else {
            self = .primary
        }
    }
}

/// SwiftUI-side palette, read from the environment by every panel.
struct Palette {
    let theme: Theme

    var paper: Color { Color(css: theme.paper) }
    var ink: Color { Color(css: theme.ink) }
    var ink2: Color { Color(css: theme.inkSecondary) }
    var ink3: Color { Color(css: theme.inkTertiary) }
    var accent: Color { Color(css: theme.accent) }
    var rule: Color { Color(css: theme.rule) }
    var sidebar: Color { Color(css: theme.sidebar) }
    var change: Color { Color(css: theme.change) }
    var unread: Color { Color(css: theme.unread) }
    /// Feedback, in the chrome (dots, counts, the copy buttons) and on the
    /// page (highlights, notes): a purple of its own, apart from new (blue)
    /// and changed (amber) on every theme.
    var feedback: Color { theme.isDark ? Color(red: 0.72, green: 0.60, blue: 0.95) : Color(red: 0.50, green: 0.33, blue: 0.78) }
    var feedbackWash: Color { feedback.opacity(theme.isDark ? 0.2 : 0.13) }
    /// Row selection: the ink at low opacity reads as a pencil shade on any paper.
    var selection: Color { ink.opacity(theme.isDark ? 0.12 : 0.075) }
    var hover: Color { ink.opacity(theme.isDark ? 0.06 : 0.04) }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(theme: .paper)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
