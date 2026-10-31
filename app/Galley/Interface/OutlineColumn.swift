import SwiftUI

struct OutlineColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeader(title: "Contents", subtitle: subtitle) {
                if model.current?.rendered.outline.isEmpty == false {
                    foldMenu
                }
            }
            if let current = model.current, !current.rendered.outline.isEmpty {
                OutlineList(document: current)
            } else {
                Text(model.current == nil ? "" : "No headings")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.ink3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var subtitle: String? {
        guard let current = model.current else { return nil }
        let changed = current.changes.units.count
        return changed > 0 ? "\(changed) change\(changed == 1 ? "" : "s")" : nil
    }

    private var foldMenu: some View {
        Menu {
            Button("Fold All Sections") { model.foldAll(true) }
            Button("Unfold All Sections") { model.foldAll(false) }
            if model.current?.changes.isEmpty == false {
                Divider()
                Button("Next Change") { model.jumpToChange(1) }
                Button("Previous Change") { model.jumpToChange(-1) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.ink3)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct OutlineList: View {
    let document: OpenDocument
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = document.rendered.outline
        let minLevel = items.map(\.level).min() ?? 1
        let changed = changedSections(items)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleItems(items).enumerated()), id: \.element.item.id) { _, entry in
                        OutlineRow(
                            item: entry.item,
                            depth: min(entry.item.level - minLevel, 4),
                            hasChildren: entry.hasChildren,
                            isFolded: document.folded.contains(entry.item.id),
                            isCurrent: model.currentHeading == entry.item.id,
                            hasChange: changed.contains(entry.item.id)
                        )
                        .id(entry.item.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onChange(of: model.currentHeading) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    /// Items not hidden inside a folded section.
    private func visibleItems(_ items: [OutlineItem]) -> [(item: OutlineItem, hasChildren: Bool)] {
        var result: [(OutlineItem, Bool)] = []
        var hiddenBelow: Int?
        for (index, item) in items.enumerated() {
            if let level = hiddenBelow {
                if item.level > level { continue }
                hiddenBelow = nil
            }
            let hasChildren = index + 1 < items.count && items[index + 1].level > item.level
            result.append((item, hasChildren))
            if document.folded.contains(item.id) { hiddenBelow = item.level }
        }
        return result
    }

    /// Headings with a change in their own text (up to the next heading of
    /// any level), or — when folded — anywhere in the section they hide.
    private func changedSections(_ items: [OutlineItem]) -> Set<String> {
        let units = document.changes.units.keys.sorted()
        guard !units.isEmpty else { return [] }
        var result = Set<String>()
        for (index, item) in items.enumerated() {
            let directEnd = index + 1 < items.count ? items[index + 1].unit : Int.max
            let sectionEnd = items[(index + 1)...].first { $0.level <= item.level }?.unit ?? Int.max
            let end = document.folded.contains(item.id) ? sectionEnd : directEnd
            if units.contains(where: { $0 >= item.unit && $0 < end }) { result.insert(item.id) }
        }
        return result
    }
}

private struct OutlineRow: View {
    let item: OutlineItem
    let depth: Int
    let hasChildren: Bool
    let isFolded: Bool
    let isCurrent: Bool
    let hasChange: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if hasChildren {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { model.setFolded(item.id, !isFolded) }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(palette.ink3)
                            .rotationEffect(.degrees(isFolded ? 0 : 90))
                            .frame(width: 14, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered || isFolded ? 1 : 0.35)
                    .help(isFolded ? "Unfold section" : "Fold section")
                } else {
                    Color.clear.frame(width: 14)
                }
            }
            Text(item.title)
                .font(.system(size: depth == 0 ? 12.5 : 12, weight: depth == 0 ? .semibold : .regular))
                .foregroundStyle(isCurrent ? palette.ink : (depth == 0 ? palette.ink : palette.ink2))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 2)
            if hasChange {
                Circle().fill(palette.change).frame(width: 5, height: 5)
            }
        }
        .padding(.leading, 2 + CGFloat(depth) * 12)
        .padding(.trailing, 8)
        .padding(.vertical, 4.5)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isCurrent ? palette.selection : (isHovered ? palette.hover : .clear))
                if isCurrent {
                    Capsule().fill(palette.accent).frame(width: 2.5).padding(.vertical, 5)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.scrollToHeading(item.id) }
        .onHover { isHovered = $0 }
        .padding(.top, depth == 0 ? 3 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
