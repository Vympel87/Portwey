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
        if let index = games.indices.last {
            detectEngine(at: index)
            extractIcon(at: index)
        }
        sortGames()
        save()
        return games.first { $0.id == game.id } ?? game
    }

    public func update(_ game: Game) {
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index] = game
        sortGames()
        save()
    }

    public func remove(_ game: Game) {
        deleteImageFile(named: game.coverFileName)
        deleteImageFile(named: game.iconFileName)
        games.removeAll { $0.id == game.id }
        save()
    }

    public func setGraphicsBackend(_ backend: GraphicsBackend, for gameID: UUID) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[index].graphicsBackend = backend
        save()
    }

    // MARK: - Engine detection

    /// Detects the engine and picks the best way to run the game.
    private func detectEngine(at index: Int) {
        let engine = GameEngineDetector.detect(executable: games[index].executableURL)
        games[index].engine = engine
        if engine.supportsNativeNWJS {
            games[index].launchMethod = .nwjs
        }
    }

    // MARK: - Covers & icons

    /// Copies the image into Portwey's data folder, so the cover survives even if the original is deleted.
    public func setCover(from source: URL, for gameID: UUID) throws {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        try AppPaths.ensureDirectories()

        let fileExtension = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        // A new file name each time, so views never show a stale image.
        let fileName = "\(gameID.uuidString)-\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
        let destination = AppPaths.covers.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: source, to: destination)

        deleteImageFile(named: games[index].coverFileName)
        games[index].coverFileName = fileName
        save()
    }

    public func removeCover(for gameID: UUID) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        deleteImageFile(named: games[index].coverFileName)
        games[index].coverFileName = nil
        save()
    }

    /// Pulls the icon out of the game's .exe. Returns true if one was found.
    @discardableResult
    private func extractIcon(at index: Int) -> Bool {
        let game = games[index]
        guard game.executableExists, let png = ExeIconExtractor.extractPNG(from: game.executableURL) else {
            return false
        }
        do {
            try AppPaths.ensureDirectories()
            let fileName = "\(game.id.uuidString)-icon.png"
            try png.write(to: AppPaths.covers.appendingPathComponent(fileName), options: .atomic)
            games[index].iconFileName = fileName
            return true
        } catch {
            print("Failed to save icon for \(game.title): \(error)")
            return false
        }
    }

    private func deleteImageFile(named fileName: String?) {
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
            return
        }

        // Fill in things older library entries don't have yet.
        var changed = false
        for index in games.indices where games[index].executableExists {
            if games[index].engine == nil {
                detectEngine(at: index)
                changed = true
            }
            if games[index].iconFileName == nil, extractIcon(at: index) {
                changed = true
            }
        }
        if changed {
            save()
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
