import Foundation
import Observation

@MainActor
@Observable
public final class GameLibrary {
    public private(set) var games: [Game] = []

    public init() {
        load()
    }

    @discardableResult
    public func addGame(executable: URL) -> Game {
        if let existing = games.first(where: { $0.executablePath == executable.path }) {
            return existing
        }
        let game = Game(
            title: Game.suggestedTitle(for: executable),
            executablePath: executable.path
        )
        games.append(game)
        sortGames()
        save()
        return game
    }

    public func remove(_ game: Game) {
        games.removeAll { $0.id == game.id }
        save()
    }

    public func setGraphicsBackend(_ backend: GraphicsBackend, for gameID: UUID) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[index].graphicsBackend = backend
        save()
    }

    public func recordSession(gameID: UUID, duration: TimeInterval) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[index].lastPlayedAt = Date()
        games[index].playtimeSeconds += max(0, duration)
        save()
    }

    private func sortGames() {
        games.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.libraryFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            games = try decoder.decode([Game].self, from: data)
            sortGames()
        } catch {
            print("Failed to load library: \(error)")
        }
    }

    private func save() {
        do {
            try AppPaths.ensureDirectories()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(games)
            try data.write(to: AppPaths.libraryFile, options: .atomic)
        } catch {
            print("Failed to save library: \(error)")
        }
    }
}
