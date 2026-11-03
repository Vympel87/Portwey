import SwiftUI
import AppKit
import LauncherCore

/// Shows the game's custom cover, or a colored placeholder if it has none.
struct GameCoverView: View {
    let game: Game
    var iconSize: CGFloat = 40
    var iconOpacity: Double = 0.85

    var body: some View {
        if let url = game.coverURL, let image = NSImage(contentsOf: url) {
            // Color.clear + overlay keeps the frame fixed while the image fills and gets cropped.
            Color.clear
                .overlay {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else {
            ZStack {
                LinearGradient(colors: game.coverColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(.white.opacity(iconOpacity))
            }
        }
    }
}
