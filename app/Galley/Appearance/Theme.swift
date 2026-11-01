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

    // The well-known palettes, mapped onto the reader's roles: the page,
    // its inks, changes in the palette's amber, the reader's marks in its
    // purple. Palettes are MIT-licensed; see Acknowledgements.txt.

    /// Solarized, by Ethan Schoonover.
    static let solarizedLight = Theme(
        id: "solarized-light", name: "Solarized Light", isDark: false,
        paper: "#FDF6E3", ink: "#073642", inkSecondary: "#586E75", inkTertiary: "#93A1A1",
        accent: "#268BD2", rule: "#EEE8D5", codeBackground: "#EEE8D5", sidebar: "#F5EEDA",
        selection: "rgba(38, 139, 210, 0.16)",
        change: "#CB4B16", changeWash: "rgba(203, 75, 22, 0.09)", insert: "rgba(203, 75, 22, 0.22)",
        mark: "rgba(181, 137, 0, 0.32)", highlight: "rgba(108, 113, 196, 0.24)", unread: "#268BD2",
        codeKeyword: "#859900", codeString: "#2AA198", codeNumber: "#D33682", codeType: "#B58900", codeFunction: "#268BD2"
    )

    /// Rosé Pine Dawn, by the Rosé Pine project.
    static let roseDawn = Theme(
        id: "rose-pine-dawn", name: "Rosé Pine Dawn", isDark: false,
        paper: "#FAF4ED", ink: "#575279", inkSecondary: "#797593", inkTertiary: "#9893A5",
        accent: "#286983", rule: "#F2E9E1", codeBackground: "#F2E9E1", sidebar: "#F4EDE4",
        selection: "rgba(40, 105, 131, 0.14)",
        change: "#D7882A", changeWash: "rgba(234, 157, 52, 0.12)", insert: "rgba(234, 157, 52, 0.3)",
        mark: "rgba(246, 193, 119, 0.5)", highlight: "rgba(144, 122, 169, 0.26)", unread: "#286983",
        codeKeyword: "#286983", codeString: "#C9821F", codeNumber: "#D7827E", codeType: "#56949F", codeFunction: "#B4637A"
    )

    /// Catppuccin Latte, by the Catppuccin project.
    static let latte = Theme(
        id: "catppuccin-latte", name: "Catppuccin Latte", isDark: false,
        paper: "#EFF1F5", ink: "#4C4F69", inkSecondary: "#6C6F85", inkTertiary: "#8C8FA1",
        accent: "#1E66F5", rule: "#DCE0E8", codeBackground: "#E6E9EF", sidebar: "#E6E9EF",
        selection: "rgba(30, 102, 245, 0.14)",
        change: "#DF8E1D", changeWash: "rgba(223, 142, 29, 0.12)", insert: "rgba(223, 142, 29, 0.3)",
        mark: "rgba(250, 200, 80, 0.5)", highlight: "rgba(136, 57, 239, 0.18)", unread: "#1E66F5",
        codeKeyword: "#8839EF", codeString: "#40A02B", codeNumber: "#FE640B", codeType: "#C47A0F", codeFunction: "#1E66F5"
    )

    /// After GitHub’s Primer light colours.
    static let githubLight = Theme(
        id: "github-light", name: "GitHub Light", isDark: false,
        paper: "#FFFFFF", ink: "#1F2328", inkSecondary: "#59636E", inkTertiary: "#8C959F",
        accent: "#0969DA", rule: "#D1D9E0", codeBackground: "#F6F8FA", sidebar: "#F6F8FA",
        selection: "rgba(9, 105, 218, 0.14)",
        change: "#BF8700", changeWash: "rgba(212, 167, 44, 0.13)", insert: "rgba(212, 167, 44, 0.32)",
        mark: "rgba(255, 223, 93, 0.55)", highlight: "rgba(130, 80, 223, 0.18)", unread: "#0969DA",
        codeKeyword: "#CF222E", codeString: "#0A3069", codeNumber: "#0550AE", codeType: "#953800", codeFunction: "#8250DF"
    )

    /// Gruvbox, by Pavel Pertsev.
    static let gruvboxLight = Theme(
        id: "gruvbox-light", name: "Gruvbox Light", isDark: false,
        paper: "#FBF1C7", ink: "#3C3836", inkSecondary: "#665C54", inkTertiary: "#928374",
        accent: "#076678", rule: "#EBDBB2", codeBackground: "#F2E5BC", sidebar: "#F2E5BC",
        selection: "rgba(7, 102, 120, 0.14)",
        change: "#B57614", changeWash: "rgba(181, 118, 20, 0.12)", insert: "rgba(181, 118, 20, 0.28)",
        mark: "rgba(215, 153, 33, 0.38)", highlight: "rgba(143, 63, 113, 0.2)", unread: "#076678",
        codeKeyword: "#9D0006", codeString: "#79740E", codeNumber: "#8F3F71", codeType: "#B57614", codeFunction: "#427B58"
    )

    /// Solarized, by Ethan Schoonover.
    static let solarizedDark = Theme(
        id: "solarized-dark", name: "Solarized Dark", isDark: true,
        paper: "#002B36", ink: "#C9D1CD", inkSecondary: "#93A1A1", inkTertiary: "#657B83",
        accent: "#268BD2", rule: "#0E3A45", codeBackground: "#073642", sidebar: "#00252F",
        selection: "rgba(38, 139, 210, 0.26)",
        change: "#B58900", changeWash: "rgba(181, 137, 0, 0.12)", insert: "rgba(181, 137, 0, 0.3)",
        mark: "rgba(181, 137, 0, 0.4)", highlight: "rgba(108, 113, 196, 0.36)", unread: "#268BD2",
        codeKeyword: "#859900", codeString: "#2AA198", codeNumber: "#D33682", codeType: "#B58900", codeFunction: "#268BD2"
    )

    /// Nord, by Arctic Ice Studio.
    static let nord = Theme(
        id: "nord", name: "Nord", isDark: true,
        paper: "#2E3440", ink: "#E5E9F0", inkSecondary: "#AEB6C4", inkTertiary: "#6E7A8E",
        accent: "#88C0D0", rule: "#3B4252", codeBackground: "#3B4252", sidebar: "#2A2F3A",
        selection: "rgba(136, 192, 208, 0.24)",
        change: "#EBCB8B", changeWash: "rgba(235, 203, 139, 0.1)", insert: "rgba(235, 203, 139, 0.26)",
        mark: "rgba(235, 203, 139, 0.38)", highlight: "rgba(180, 142, 173, 0.36)", unread: "#81A1C1",
        codeKeyword: "#81A1C1", codeString: "#A3BE8C", codeNumber: "#B48EAD", codeType: "#8FBCBB", codeFunction: "#88C0D0"
    )

    /// Dracula, by Zeno Rocha and the Dracula team.
    static let dracula = Theme(
        id: "dracula", name: "Dracula", isDark: true,
        paper: "#282A36", ink: "#F8F8F2", inkSecondary: "#BFC0C9", inkTertiary: "#6272A4",
        accent: "#8BE9FD", rule: "#343746", codeBackground: "#21222C", sidebar: "#21222C",
        selection: "rgba(139, 233, 253, 0.2)",
        change: "#FFB86C", changeWash: "rgba(255, 184, 108, 0.1)", insert: "rgba(255, 184, 108, 0.26)",
        mark: "rgba(241, 250, 140, 0.32)", highlight: "rgba(189, 147, 249, 0.32)", unread: "#8BE9FD",
        codeKeyword: "#FF79C6", codeString: "#F1FA8C", codeNumber: "#BD93F9", codeType: "#8BE9FD", codeFunction: "#50FA7B"
    )

    /// Rosé Pine, by the Rosé Pine project.
    static let rosePine = Theme(
        id: "rose-pine", name: "Rosé Pine", isDark: true,
        paper: "#191724", ink: "#E0DEF4", inkSecondary: "#908CAA", inkTertiary: "#6E6A86",
        accent: "#9CCFD8", rule: "#26233A", codeBackground: "#1F1D2E", sidebar: "#16141F",
        selection: "rgba(156, 207, 216, 0.2)",
        change: "#F6C177", changeWash: "rgba(246, 193, 119, 0.09)", insert: "rgba(246, 193, 119, 0.25)",
        mark: "rgba(246, 193, 119, 0.35)", highlight: "rgba(196, 167, 231, 0.3)", unread: "#9CCFD8",
        codeKeyword: "#3E8FB0", codeString: "#F6C177", codeNumber: "#EBBCBA", codeType: "#9CCFD8", codeFunction: "#EBBCBA"
    )

    /// Catppuccin Mocha, by the Catppuccin project.
    static let mocha = Theme(
        id: "catppuccin-mocha", name: "Catppuccin Mocha", isDark: true,
        paper: "#1E1E2E", ink: "#CDD6F4", inkSecondary: "#A6ADC8", inkTertiary: "#7F849C",
        accent: "#89B4FA", rule: "#313244", codeBackground: "#181825", sidebar: "#181825",
        selection: "rgba(137, 180, 250, 0.24)",
        change: "#FAB387", changeWash: "rgba(250, 179, 135, 0.09)", insert: "rgba(250, 179, 135, 0.24)",
        mark: "rgba(249, 226, 175, 0.32)", highlight: "rgba(203, 166, 247, 0.3)", unread: "#89B4FA",
        codeKeyword: "#CBA6F7", codeString: "#A6E3A1", codeNumber: "#FAB387", codeType: "#F9E2AF", codeFunction: "#89B4FA"
    )

    /// Tokyo Night, by enkia.
    static let tokyoNight = Theme(
        id: "tokyo-night", name: "Tokyo Night", isDark: true,
        paper: "#1A1B26", ink: "#C0CAF5", inkSecondary: "#A9B1D6", inkTertiary: "#565F89",
        accent: "#7AA2F7", rule: "#292E42", codeBackground: "#16161E", sidebar: "#16161E",
        selection: "rgba(122, 162, 247, 0.24)",
        change: "#E0AF68", changeWash: "rgba(224, 175, 104, 0.09)", insert: "rgba(224, 175, 104, 0.25)",
        mark: "rgba(224, 175, 104, 0.35)", highlight: "rgba(187, 154, 247, 0.3)", unread: "#7AA2F7",
        codeKeyword: "#BB9AF7", codeString: "#9ECE6A", codeNumber: "#FF9E64", codeType: "#2AC3DE", codeFunction: "#7AA2F7"
    )

    /// Gruvbox, by Pavel Pertsev.
    static let gruvboxDark = Theme(
        id: "gruvbox-dark", name: "Gruvbox Dark", isDark: true,
        paper: "#282828", ink: "#EBDBB2", inkSecondary: "#BDAE93", inkTertiary: "#928374",
        accent: "#83A598", rule: "#3C3836", codeBackground: "#1D2021", sidebar: "#1D2021",
        selection: "rgba(131, 165, 152, 0.26)",
        change: "#FABD2F", changeWash: "rgba(250, 189, 47, 0.09)", insert: "rgba(250, 189, 47, 0.24)",
        mark: "rgba(250, 189, 47, 0.32)", highlight: "rgba(211, 134, 155, 0.3)", unread: "#83A598",
        codeKeyword: "#FB4934", codeString: "#B8BB26", codeNumber: "#D3869B", codeType: "#FABD2F", codeFunction: "#8EC07C"
    )

    /// After GitHub’s Primer dark colours.
    static let githubDark = Theme(
        id: "github-dark", name: "GitHub Dark", isDark: true,
        paper: "#0D1117", ink: "#E6EDF3", inkSecondary: "#9198A1", inkTertiary: "#6E7681",
        accent: "#4493F8", rule: "#30363D", codeBackground: "#161B22", sidebar: "#010409",
        selection: "rgba(68, 147, 248, 0.24)",
        change: "#D29922", changeWash: "rgba(210, 153, 34, 0.1)", insert: "rgba(210, 153, 34, 0.26)",
        mark: "rgba(210, 153, 34, 0.35)", highlight: "rgba(171, 125, 248, 0.3)", unread: "#4493F8",
        codeKeyword: "#FF7B72", codeString: "#A5D6FF", codeNumber: "#79C0FF", codeType: "#FFA657", codeFunction: "#D2A8FF"
    )

    /// Galley's own first, then the well-known ones.
    static let all: [Theme] = [
        .paper, .snow, .sepia, .solarizedLight, .roseDawn, .latte, .githubLight, .gruvboxLight,
        .graphite, .ink, .lamplight, .solarizedDark, .nord, .dracula, .rosePine, .mocha, .tokyoNight, .gruvboxDark, .githubDark,
    ]
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
