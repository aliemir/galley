import SwiftUI

struct OutlineColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeader(title: "Contents", subtitle: subtitle) {
                foldMenu
            }
            if let current = model.current, !current.rendered.outline.isEmpty || !current.highlights.isEmpty {
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
            if model.current?.rendered.outline.isEmpty == false {
                Button("Fold All Sections") { model.foldAll(true) }
                Button("Unfold All Sections") { model.foldAll(false) }
            }
            if model.current?.changes.isEmpty == false {
                Divider()
                Button("Next Change") { model.jumpToChange(1) }
                Button("Previous Change") { model.jumpToChange(-1) }
            }
            Divider()
            Button("Hide Contents (⌘3)") { model.setColumn(.outline, visible: false) }
                .keyboardShortcut("2", modifiers: [.command, .option])
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
    @Environment(\.palette) private var palette

    /// Copy or clear the feedback, for this document or the workspace.
    private var feedbackMenu: some View {
        Menu {
            Button("Copy Feedback (⇧⌘C)") { model.copyFeedback() }
            Button("Copy Feedback for Workspace") { model.copyWorkspaceFeedback() }
            Divider()
            Button("Clear Feedback…") { model.clearFeedback() }
            Button("Clear All Feedback in Workspace…") { model.clearWorkspaceFeedback() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.ink3)
                .frame(width: 24, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Copy or clear feedback")
    }

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
                    if !document.highlights.isEmpty {
                        HStack(spacing: 0) {
                            SectionLabel(title: "Feedback", count: document.highlights.count)
                            feedbackMenu
                                .padding(.top, 10)
                                .padding(.trailing, 4)
                        }
                        .padding(.horizontal, -8)
                        .padding(.top, items.isEmpty ? -8 : 10)
                        ForEach(document.highlights) { highlight in
                            HighlightRow(highlight: highlight, isOrphan: document.orphans.contains(highlight.id))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                // Room past the last row, so the end of the list can be
                // scrolled up off the window's bottom edge.
                .padding(.bottom, MainView.listTail)
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
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isCurrent ? palette.selection : (isHovered ? palette.hover : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { model.scrollToHeading(item.id) }
        .onHover { isHovered = $0 }
        .padding(.top, depth == 0 ? 3 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// A highlight in the outline column. Orphans — whose text the agent has
/// since removed — stay listed, quieter, until the reader lets them go.
private struct HighlightRow: View {
    let highlight: Highlight
    let isOrphan: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isOrphan ? palette.ink3.opacity(0.5) : palette.feedback.opacity(0.75))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(highlight.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(isOrphan ? palette.ink3 : palette.ink2)
                    .lineLimit(3)
                    .strikethrough(isOrphan, color: palette.ink3.opacity(0.6))
                if let note = highlight.note {
                    Label(note, systemImage: "text.bubble")
                        .font(.system(size: 11.5))
                        .foregroundStyle(isOrphan ? palette.ink3 : palette.ink)
                        .lineLimit(4)
                        .labelStyle(NoteLabelStyle())
                }
                if isOrphan {
                    Text(highlight.note == nil ? "No longer in the text" : "Passage gone — likely addressed")
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.ink3)
                }
            }
            Spacer(minLength: 0)
            if isHovered || isOrphan {
                Button {
                    model.removeHighlight(highlight.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.ink3)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove highlight")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isHovered ? palette.hover : .clear))
        .contentShape(Rectangle())
        .onTapGesture { if !isOrphan { model.scrollToHighlight(highlight.id) } }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Copy Text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(highlight.text, forType: .string)
            }
            if !isOrphan {
                Button(highlight.note == nil ? "Add Note" : "Edit Note") { model.editNote(highlight.id) }
            }
            Button("Remove Highlight", role: .destructive) { model.removeHighlight(highlight.id) }
        }
    }
}

/// A note in the Contents column: a small speech mark, then the words.
private struct NoteLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon.font(.system(size: 9.5)).foregroundStyle(.secondary)
            configuration.title
        }
    }
}
