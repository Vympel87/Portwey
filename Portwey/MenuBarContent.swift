import SwiftUI
import AppKit
import LauncherCore

/// The menu behind Portwey's icon in the macOS menu bar.
struct MenuBarContent: View {
    @Environment(GameLibrary.self) private var library
    @Environment(GameRunner.self) private var runner
    @Environment(SetupManager.self) private var setup
    @Environment(\.openWindow) private var openWindow

    private var recentGames: [Game] {
        let played = library.games
            .filter { $0.lastPlayedAt != nil }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        return Array((played.isEmpty ? library.games : played).prefix(5))
    }

    var body: some View {
        if let id = runner.activeGameID, let game = library.games.first(where: { $0.id == id }) {
            Text(runner.isRunning(id) ? "Now playing: \(game.title)" : "Starting \(game.title)…")
            Button("Stop \(game.title)") {
                Task { await runner.stop() }
            }
            Divider()
        }

        if library.games.isEmpty {
            Text("No games yet")
        } else {
            Section("Recent games") {
                ForEach(recentGames) { game in
                    Button(game.title) {
                        playGame(game, runner: runner, setup: setup)
                    }
                    .disabled(runner.isBusy || !game.executableExists || setup.runtime == nil)
                }
            }
        }

        Divider()

        Button("Open Portwey") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut("o")

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Portwey") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
