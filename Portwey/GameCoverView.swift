import SwiftUI
import AppKit
import LauncherCore

/// Shows the custom cover, else the .exe icon on a blurred backdrop, else a colored placeholder.
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
        } else if let url = game.iconURL, let icon = NSImage(contentsOf: url) {
            ZStack {
                LinearGradient(colors: game.coverColors, startPoint: .topLeading, endPoint: .bottomTrailing)

                // A soft, blurred copy of the icon as the background.
                Color.clear
                    .overlay {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 28)
                            .opacity(0.7)
                    }
                    .clipped()

                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: iconSize * 1.8, height: iconSize * 1.8)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
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
