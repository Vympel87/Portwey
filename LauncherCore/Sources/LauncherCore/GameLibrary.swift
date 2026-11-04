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

    /// Removes the game from the library.
    /// With `deleteGameFiles`, also deletes its folder if Portwey extracted it (from a .zip) into its games folder.
    /// A game's own bottle is deleted too once no other game uses it.
    public func remove(_ game: Game, deleteGameFiles: Bool = false) {
        if deleteGameFiles, let folder = managedFolder(for: game) {
            try? FileManager.default.removeItem(at: folder)
        }

        deleteImageFile(named: game.coverFileName)
        deleteImageFile(named: game.iconFileName)
        games.removeAll { $0.id == game.id }

        if game.bottleName != BottleManager.defaultBottleName,
           !games.contains(where: { $0.bottleName == game.bottleName }) {
            try? FileManager.default.removeItem(at: BottleManager.bottleURL(named: game.bottleName))
        }
        save()
    }

    public func setGraphicsBackend(_ backend: GraphicsBackend, for gameID: UUID) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[index].graphicsBackend = backend
        save()
    }

    // MARK: - Queries

    /// True when the game's files live in Portwey's own games folder (imported from a .zip).
    public func isManagedByPortwey(_ game: Game) -> Bool {
        managedFolder(for: game) != nil
    }

    public func games(usingBottle name: String) -> [Game] {
        games.filter { $0.bottleName == name }
    }

    /// The top-level folder inside Portwey's games folder that holds this game.
    private func managedFolder(for game: Game) -> URL? {
        let root = AppPaths.games.path + "/"
        guard game.executablePath.hasPrefix(root) else { return nil }
        let relative = game.executablePath.dropFirst(root.count)
        guard let first = relative.split(separator: "/").first else { return nil }
        return AppPaths.games.appendingPathComponent(String(first), isDirectory: true)
    }

    // MARK: - Engine detection

    /// Detects the engine and picks the best way to run the game.
    private func detectEngine(at index: Int) {
        let executable = games[index].executableURL
        let engine = GameEngineDetector.detect(executable: executable)
        games[index].engine = engine

        switch engine.nativeLaunchMethod {
        case .nwjs:
            games[index].launchMethod = .nwjs
        case .godot:
            // Only go native when the game has no encrypted data, .NET code or Windows plugins.
            if GodotService.nativeSupport(for: executable).isSupported {
                games[index].launchMethod = .godot
            }
        default:
            break
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
