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

    public func update(_ game: Game) {
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index] = game
        sortGames()
        save()
    }

    public func remove(_ game: Game) {
        deleteCoverFile(named: game.coverFileName)
        games.removeAll { $0.id == game.id }
        save()
    }

    public func setGraphicsBackend(_ backend: GraphicsBackend, for gameID: UUID) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[index].graphicsBackend = backend
        save()
    }

    // MARK: - Covers

    /// Copies the image into Portwey's data folder, so the cover survives even if the original is deleted.
    public func setCover(from source: URL, for gameID: UUID) throws {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        try AppPaths.ensureDirectories()

        let fileExtension = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        // A new file name each time, so views never show a stale image.
        let fileName = "\(gameID.uuidString)-\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
        let destination = AppPaths.covers.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: source, to: destination)

        deleteCoverFile(named: games[index].coverFileName)
        games[index].coverFileName = fileName
        save()
    }

    public func removeCover(for gameID: UUID) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        deleteCoverFile(named: games[index].coverFileName)
        games[index].coverFileName = nil
        save()
    }

    private func deleteCoverFile(named fileName: String?) {
        guard let fileName else { return }
        try? FileManager.default.removeItem(at: AppPaths.covers.appendingPathComponent(fileName))
    }

    // MARK: - Sessions

    public func recordSession(gameID: UUID, duration: TimeInterval) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[index].lastPlayedAt = Date()
        games[index].playtimeSeconds += max(0, duration)
        save()
    }

    // MARK: - Persistence

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
