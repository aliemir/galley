import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum ReadingFont: String, CaseIterable, Identifiable {
    case newYork, charter, iowan, palatino, sanFrancisco, avenir

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newYork: "New York"
        case .charter: "Charter"
        case .iowan: "Iowan"
        case .palatino: "Palatino"
        case .sanFrancisco: "San Francisco"
        case .avenir: "Avenir Next"
        }
    }

    var css: String {
        switch self {
        case .newYork: #"ui-serif, "New York", Georgia, serif"#
        case .charter: #"Charter, "Bitstream Charter", ui-serif, serif"#
        case .iowan: #""Iowan Old Style", ui-serif, serif"#
        case .palatino: #"Palatino, "Palatino Linotype", ui-serif, serif"#
        case .sanFrancisco: #"-apple-system, BlinkMacSystemFont, system-ui, sans-serif"#
        case .avenir: #""Avenir Next", Avenir, system-ui, sans-serif"#
        }
    }

    /// A sample of the face for pickers.
    func font(size: CGFloat) -> Font {
        switch self {
        case .newYork: .system(size: size, design: .serif)
        case .charter: .custom("Charter", size: size)
        case .iowan: .custom("Iowan Old Style", size: size)
        case .palatino: .custom("Palatino", size: size)
        case .sanFrancisco: .system(size: size)
        case .avenir: .custom("Avenir Next", size: size)
        }
    }

    /// Sans faces read best a touch tighter.
    var leadingAdjustment: Double {
        switch self {
        case .sanFrancisco, .avenir: -0.04
        default: 0
        }
    }
}

enum LineSpacing: String, CaseIterable, Identifiable {
    case compact, regular, airy
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var value: Double {
        switch self {
        case .compact: 1.46
        case .regular: 1.62
        case .airy: 1.8
        }
    }
}

enum LineWidth: String, CaseIterable, Identifiable {
    case narrow, regular, wide
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// Measure in ems: roughly 58, 66 and 80 characters.
    var ems: Double {
        switch self {
        case .narrow: 31
        case .regular: 36
        case .wide: 44
        }
    }
}

enum NameStyle: String, CaseIterable, Identifiable {
    case pretty, heading, filename
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pretty: "Tidied file name"
        case .heading: "First heading"
        case .filename: "File name"
        }
    }
}

enum ContinueOrder: String, CaseIterable, Identifiable {
    case folder, unread
    var id: String { rawValue }
    var label: String {
        switch self {
        case .folder: "Folder order"
        case .unread: "Unread and changed first"
        }
    }
}

/// Reader preferences, stored in `UserDefaults`.
@MainActor
@Observable
final class ReaderSettings {
    static let shared = ReaderSettings()

    var appearance: AppearanceMode { didSet { save(appearance.rawValue, "appearance") } }
    var lightTheme: String { didSet { save(lightTheme, "lightTheme") } }
    var darkTheme: String { didSet { save(darkTheme, "darkTheme") } }
    var font: ReadingFont { didSet { save(font.rawValue, "font") } }
    var fontSize: Double { didSet { save(fontSize, "fontSize") } }
    var lineSpacing: LineSpacing { didSet { save(lineSpacing.rawValue, "lineSpacing") } }
    var lineWidth: LineWidth { didSet { save(lineWidth.rawValue, "lineWidth") } }
    var showChanges: Bool { didSet { save(showChanges, "showChanges") } }
    var nameStyle: NameStyle { didSet { save(nameStyle.rawValue, "nameStyle") } }
    var continueOrder: ContinueOrder { didSet { save(continueOrder.rawValue, "continueOrder") } }
    var pullToContinue: Bool { didSet { save(pullToContinue, "pullToContinue") } }
    /// The order swipes reveal the columns in. Always all of them.
    var columnOrder: [PanelColumn] { didSet { save(columnOrder.map(\.rawValue), "columnOrder") } }
    /// Columns swipes pass over; their own shortcuts still show them.
    var swipeSkips: Set<PanelColumn> { didSet { save(swipeSkips.map(\.rawValue).sorted(), "hiddenColumns") } }
    /// Workspaces as a narrow rail of icons instead of a named list.
    var workspacesAsIcons: Bool { didSet { save(workspacesAsIcons, "workspacesAsIcons") } }
    /// Column widths the reader dragged, by column; absent means the default.
    var columnWidths: [String: Double] { didSet { save(columnWidths, "columnWidths") } }

    static let fontSizes: ClosedRange<Double> = 13...28

    private init() {
        let d = UserDefaults.standard
        appearance = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        lightTheme = d.string(forKey: "lightTheme") ?? Theme.paper.id
        darkTheme = d.string(forKey: "darkTheme") ?? Theme.graphite.id
        font = ReadingFont(rawValue: d.string(forKey: "font") ?? "") ?? .newYork
        let size = d.double(forKey: "fontSize")
        fontSize = size == 0 ? 17 : size
        lineSpacing = LineSpacing(rawValue: d.string(forKey: "lineSpacing") ?? "") ?? .regular
        lineWidth = LineWidth(rawValue: d.string(forKey: "lineWidth") ?? "") ?? .regular
        showChanges = d.object(forKey: "showChanges") as? Bool ?? true
        nameStyle = NameStyle(rawValue: d.string(forKey: "nameStyle") ?? "") ?? .pretty
        continueOrder = ContinueOrder(rawValue: d.string(forKey: "continueOrder") ?? "") ?? .folder
        pullToContinue = d.object(forKey: "pullToContinue") as? Bool ?? true
        var order = (d.stringArray(forKey: "columnOrder") ?? []).compactMap(PanelColumn.init(rawValue:))
        // The first default led with Contents; an order still equal to it
        // was never chosen, so it moves to the new default once.
        if order == PanelColumn.legacyOrder, !d.bool(forKey: "columnOrderMigrated") {
            order = PanelColumn.defaultOrder
            d.set(order.map(\.rawValue), forKey: "columnOrder")
        }
        d.set(true, forKey: "columnOrderMigrated")
        // Unknown or missing columns join at the end, so a new one is never lost.
        var seen = Set<PanelColumn>()
        columnOrder = (order + PanelColumn.defaultOrder).filter { seen.insert($0).inserted }
        swipeSkips = Set((d.stringArray(forKey: "hiddenColumns") ?? []).compactMap(PanelColumn.init(rawValue:)))
        // The rail by default: workspaces are switched between, not read.
        workspacesAsIcons = d.object(forKey: "workspacesAsIcons") as? Bool ?? true
        columnWidths = d.dictionary(forKey: "columnWidths") as? [String: Double] ?? [:]
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    func theme(isDark: Bool) -> Theme {
        isDark ? Theme.named(darkTheme, fallback: .graphite) : Theme.named(lightTheme, fallback: .paper)
    }

    func adjustFontSize(by delta: Double) {
        fontSize = min(Self.fontSizes.upperBound, max(Self.fontSizes.lowerBound, fontSize + delta))
    }

    /// Folder names follow the file names: tidied unless raw names were asked for.
    func displayFolderName(_ name: String) -> String {
        nameStyle == .filename ? name : PrettyName.make(fromFolderName: name)
    }

    /// `plans/q3-launch` → "Plans / Q3 launch".
    func displayFolderPath(_ path: String) -> String {
        path.split(separator: "/").map { displayFolderName(String($0)) }.joined(separator: " / ")
    }

    func displayName(for file: DocumentFile) -> String {
        switch nameStyle {
        case .pretty: file.prettyName
        case .heading: file.heading ?? file.prettyName
        case .filename: file.filename
        }
    }
}
