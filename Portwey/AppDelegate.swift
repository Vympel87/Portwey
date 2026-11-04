import AppKit
import LauncherCore

/// Handles things SwiftUI doesn't cover yet, like the Dock menu.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var library: GameLibrary?
    private weak var runner: GameRunner?
    private weak var setup: SetupManager?

    func connect(library: GameLibrary, runner: GameRunner, setup: SetupManager) {
        self.library = library
        self.runner = runner
        self.setup = setup
    }

    /// Right-clicking Portwey in the Dock shows the running game and recently played games.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let library, let runner else { return nil }

        let menu = NSMenu()
        menu.autoenablesItems = false

        if let id = runner.activeGameID, let game = library.games.first(where: { $0.id == id }) {
            let stop = NSMenuItem(title: "Stop \(game.title)", action: #selector(stopGame), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
            menu.addItem(.separator())
        }

        for game in recentGames(in: library) {
            let item = NSMenuItem(title: game.title, action: #selector(playFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = game.id.uuidString
            item.isEnabled = !runner.isBusy && game.executableExists
            menu.addItem(item)
        }

        return menu.items.isEmpty ? nil : menu
    }

    private func recentGames(in library: GameLibrary) -> [Game] {
        let played = library.games
            .filter { $0.lastPlayedAt != nil }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        return Array((played.isEmpty ? library.games : played).prefix(5))
    }

    @objc private func playFromMenu(_ sender: NSMenuItem) {
        guard
            let idString = sender.representedObject as? String,
            let id = UUID(uuidString: idString),
            let library, let runner, let setup,
            let game = library.games.first(where: { $0.id == id })
        else { return }
        playGame(game, runner: runner, setup: setup)
    }

    @objc private func stopGame() {
        Task { await runner?.stop() }
    }
}
