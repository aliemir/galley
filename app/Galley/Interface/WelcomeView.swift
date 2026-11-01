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
                Text("Read what your\nagents write.")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(palette.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Each file is set like a page in a book. When an agent changes something you have already read, the change is marked. Highlight a passage, add a note, and hand it back as feedback.")
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
                    Text("or drop a folder or file here")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.ink3)
                }
                Button("New here? Read the guide →") { model.openGuide() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.accent)
                .padding(.top, 6)
            }
            .frame(maxWidth: 440, alignment: .leading)
            Spacer()
            HStack(spacing: 22) {
                hint("arrow.down.circle", "Pull past the end for the next file")
                hint("highlighter", "Highlight to leave feedback")
                hint("lock", "Read-only: your files are never changed")
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
