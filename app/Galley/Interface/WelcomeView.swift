import SwiftUI

/// First launch, or every workspace removed.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 18) {
                Text("GALLEY")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(palette.ink3)
                Text("A printed copy of\nwhat your agents wrote.")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(palette.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Open a folder your agents write Markdown into. Every file reads like a page, and whatever changes after you have read it is marked in the margin — like a proof back from the printer.")
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(palette.ink2)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button {
                        model.openFolderPanel()
                    } label: {
                        Text("Open Folder…")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.paper)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(palette.ink))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    Text("or drop one on this window")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.ink3)
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: 440, alignment: .leading)
            Spacer()
            HStack(spacing: 22) {
                hint("hand.draw", "Swipe sideways to show or hide panels")
                hint("arrow.down.circle", "Pull past the end to turn the page")
                hint("lock", "Read-only. Your files are never changed")
            }
            .padding(.bottom, 34)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.paper)
        .overlay(alignment: .top) { TitleBand() }
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11))
            .foregroundStyle(palette.ink3)
            .labelStyle(.titleAndIcon)
    }
}
