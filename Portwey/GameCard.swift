import SwiftUI
import LauncherCore

struct GameCard<MenuContent: View>: View {
    let game: Game
    let status: GameStatus
    let canPlay: Bool
    let onPlay: () -> Void
    @ViewBuilder let menuContent: () -> MenuContent

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                GameCoverView(game: game)

                if isHovering && canPlay {
                    Color.black.opacity(0.35)
                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Play")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Always-visible "more" button, so people don't have to discover right-click.
                Menu {
                    menuContent()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(8)
                .help("More options")
            }
            .frame(height: 140)
            .clipped()

            VStack(alignment: .leading, spacing: 10) {
                Text(game.title)
                    .font(.headline)
                    .lineLimit(2, reservesSpace: true)

                HStack(spacing: 6) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 7, height: 7)
                    Text(status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isHovering ? Color.accentColor.opacity(0.8) : .clear, lineWidth: 2)
        )
        .scaleEffect(isHovering ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onHover { isHovering = $0 }
    }
}
