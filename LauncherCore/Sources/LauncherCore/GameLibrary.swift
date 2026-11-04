import Foundation
import Observation

@MainActor
@Observable
public final class GameLibrary {
    public private(set) var games: [Game] = []
    /// Presets from the Portwey repo (cached copy until a fresh one is downloaded).
    public private(set) var communityPresets: [GamePreset] = PresetService.cachedPresets()
    /// Presets saved on this Mac.
    public private(set) var myPresets: [GamePreset] = PresetService.loadMyPresets()

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
            if let preset = preset(for: games[index]) {
                applySettings(of: preset, at: index)
            }
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

    // MARK: - Presets

    /// Downloads the latest community presets. Games that were never played or configured by a preset pick one up.
    public func refreshPresets() async {
        do {
            communityPresets = try await PresetService.fetchPresets()
        } catch {
            print("Couldn't refresh presets: \(error.localizedDescription)")
            return
        }

        var changed = false
        for index in games.indices where games[index].presetID == nil && games[index].lastPlayedAt == nil {
            if let preset = preset(for: games[index]) {
                applySettings(of: preset, at: index)
                changed = true
            }
        }
        if changed {
            save()
        }
    }

    /// The best preset for a game. Your own presets win over community ones.
    public func preset(for game: Game) -> GamePreset? {
        PresetService.bestMatch(for: game, mine: myPresets, community: communityPresets)
    }

    public func isMyPreset(_ preset: GamePreset) -> Bool {
        myPresets.contains { $0.id == preset.id }
    }

    public func games(usingPreset preset: GamePreset) -> [Game] {
        games.filter { $0.presetID == preset.id }
    }

    public func applyPreset(_ preset: GamePreset, to gameID: UUID) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        applySettings(of: preset, at: index)
        save()
    }

    /// Adds or updates one of your presets. Pass `appliedTo` to mark a game as using it.
    public func saveMyPreset(_ preset: GamePreset, appliedTo gameID: UUID? = nil) {
        if let index = myPresets.firstIndex(where: { $0.id == preset.id }) {
            myPresets[index] = preset
        } else {
            myPresets.append(preset)
        }
        myPresets.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        persistMyPresets()

        if let gameID, let index = games.firstIndex(where: { $0.id == gameID }) {
            games[index].presetID = preset.id
            save()
        }
    }

    /// Deletes one of your presets. Games keep their settings; only the link to the preset goes.
    public func deleteMyPreset(_ preset: GamePreset) {
        myPresets.removeAll { $0.id == preset.id }
        persistMyPresets()

        for index in games.indices where games[index].presetID == preset.id {
            games[index].presetID = nil
        }
        save()
    }

    /// A complete presets.json for the repo: community presets plus yours.
    public func exportPresetsFile() throws -> Data {
        try PresetService.exportData(community: communityPresets, mine: myPresets)
    }

    private func applySettings(of preset: GamePreset, at index: Int) {
        let settings = preset.settings
        if let launchMethod = settings.launchMethod {
            games[index].launchMethod = launchMethod
        }
        if let backend = settings.graphicsBackend {
            games[index].graphicsBackend = backend
        }
        if let arguments = settings.arguments {
            games[index].arguments = arguments
        }
        if let environment = settings.environment {
            games[index].environment = environment
        }
        if let ownBottle = settings.ownBottle {
            games[index].bottleName = ownBottle
                ? BottleManager.ownBottleName(for: games[index].id)
                : BottleManager.defaultBottleName
        }
        games[index].presetID = preset.id
    }

    private func persistMyPresets() {
        do {
            try PresetService.saveMyPresets(myPresets)
        } catch {
            print("Failed to save my presets: \(error)")
        }
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
