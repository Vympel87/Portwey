import SwiftUI
import LauncherCore

enum SidebarItem: Hashable {
    case library
    case bottles
    case runtimes
}

struct MainView: View {
    @State private var selection: SidebarItem? = .library

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Portwey") {
                    Label("Library", systemImage: "square.grid.2x2")
                        .tag(SidebarItem.library)
                    Label("Bottles", systemImage: "shippingbox")
                        .tag(SidebarItem.bottles)
                    Label("Runtimes", systemImage: "cpu")
                        .tag(SidebarItem.runtimes)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                NowPlayingView()
                    .padding(12)
            }
        } detail: {
            switch selection ?? .library {
            case .library:
                LibraryView()
            case .bottles:
                BottlesView()
            case .runtimes:
                RuntimesView()
            }
        }
    }
}

// MARK: - Now playing

private struct NowPlayingView: View {
    @Environment(GameRunner.self) private var runner
    @Environment(GameLibrary.self) private var library

    var body: some View {
        if let id = runner.activeGameID, let game = library.games.first(where: { $0.id == id }) {
            HStack(spacing: 10) {
                GameCoverView(game: game, iconSize: 10)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(runner.isRunning(id) ? "Now playing" : "Starting…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(game.title)
                        .font(.callout.bold())
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if runner.isRunning(id) {
                    Button {
                        Task { await runner.stop() }
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Stop")
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
