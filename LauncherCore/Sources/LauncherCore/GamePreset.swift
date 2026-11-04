import Foundation

/// Settings known to work for a specific game.
/// Community presets come from presets.json in the Portwey repo; "my presets" are saved on this Mac.
public struct GamePreset: Codable, Sendable, Identifiable, Hashable {
    public struct Match: Codable, Sendable, Hashable {
        /// Exact .exe file name, e.g. "Starmaker Story.exe" (case-insensitive).
        public var executable: String?
        /// Text found in the game's title or folder name, for games with generic .exe names like "Game.exe".
        public var titleContains: String?
        public var engine: GameEngine?

        public init(executable: String? = nil, titleContains: String? = nil, engine: GameEngine? = nil) {
            self.executable = executable
            self.titleContains = titleContains
            self.engine = engine
        }
    }

    public struct Settings: Codable, Sendable, Hashable {
        public var launchMethod: LaunchMethod?
        public var graphicsBackend: GraphicsBackend?
        public var arguments: [String]?
        public var environment: [String: String]?
        public var ownBottle: Bool?

        public init(
            launchMethod: LaunchMethod? = nil,
            graphicsBackend: GraphicsBackend? = nil,
            arguments: [String]? = nil,
            environment: [String: String]? = nil,
            ownBottle: Bool? = nil
        ) {
            self.launchMethod = launchMethod
            self.graphicsBackend = graphicsBackend
            self.arguments = arguments
            self.environment = environment
            self.ownBottle = ownBottle
        }
    }

    public enum Status: String, Codable, Sendable, CaseIterable, Identifiable {
        case works
        case playable
        case broken

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .works: return "Works"
            case .playable: return "Playable"
            case .broken: return "Broken"
            }
        }
    }

    public var id: String
    public var title: String
    public var match: Match
    public var settings: Settings
    public var status: Status?
    public var notes: String?

    public init(
        id: String,
        title: String,
        match: Match,
        settings: Settings,
        status: Status? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.match = match
        self.settings = settings
        self.status = status
        self.notes = notes
    }

    /// How well this preset fits a game. 0 means it doesn't apply.
    public func matchScore(for game: Game) -> Int {
        var score = 0

        if let executable = match.executable {
            guard executable.caseInsensitiveCompare(game.executableURL.lastPathComponent) == .orderedSame else {
                return 0
            }
            score += 10
        }
        if let text = match.titleContains {
            let haystack = game.title + " " + game.workingDirectoryURL.lastPathComponent
            guard haystack.localizedCaseInsensitiveContains(text) else { return 0 }
            score += 5
        }
        if let engine = match.engine {
            guard game.engine == engine else { return 0 }
            score += 1
        }

        // An engine on its own is far too vague to identify a game.
        return score > 1 ? score : 0
    }

    // MARK: - Readable summaries

    public var matchSummary: String {
        var parts: [String] = []
        if let executable = match.executable { parts.append(executable) }
        if let text = match.titleContains { parts.append("title contains “\(text)”") }
        if let engine = match.engine { parts.append(engine.displayName) }
        return parts.isEmpty ? "Matches nothing" : parts.joined(separator: " · ")
    }

    public var settingsSummary: String {
        var parts: [String] = []
        if let launchMethod = settings.launchMethod { parts.append(launchMethod.displayName) }
        if let backend = settings.graphicsBackend { parts.append(backend.shortName) }
        if settings.ownBottle == true { parts.append("Own bottle") }
        if let arguments = settings.arguments, !arguments.isEmpty {
            parts.append("Args: " + arguments.joined(separator: " "))
        }
        if let environment = settings.environment, !environment.isEmpty {
            parts.append("Env: " + environment.keys.sorted().joined(separator: ", "))
        }
        return parts.isEmpty ? "No changes" : parts.joined(separator: " · ")
    }
}

/// The presets.json file. Entries that can't be read (for example from a newer Portwey) are skipped
/// instead of breaking the whole file.
public struct PresetFile: Codable, Sendable {
    public var version: Int
    public var presets: [GamePreset]

    private enum CodingKeys: String, CodingKey {
        case version, presets
    }

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?

        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    public init(version: Int = 1, presets: [GamePreset]) {
        self.version = version
        self.presets = presets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        presets = try container.decode([Lossy<GamePreset>].self, forKey: .presets).compactMap(\.value)
    }
}

public enum PresetService {
    public static let repositoryURL = URL(string: "https://github.com/Vympel87/Portwey")!
    public static let remoteURL = URL(string: "https://raw.githubusercontent.com/Vympel87/Portwey/main/presets.json")!

    static var cacheFile: URL { AppPaths.root.appendingPathComponent("presets-cache.json") }
    static var myPresetsFile: URL { AppPaths.root.appendingPathComponent("my-presets.json") }

    // MARK: - Community presets

    /// Presets from the last successful download, so they also work offline.
    public static func cachedPresets() -> [GamePreset] {
        readFile(cacheFile)
    }

    /// Downloads the latest presets.json and updates the cache.
    public static func fetchPresets() async throws -> [GamePreset] {
        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Portwey", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LauncherError.invalidResponse
        }

        let file = try JSONDecoder().decode(PresetFile.self, from: data)
        try? AppPaths.ensureDirectories()
        try? data.write(to: cacheFile, options: .atomic)
        return file.presets
    }

    // MARK: - My presets

    public static func loadMyPresets() -> [GamePreset] {
        readFile(myPresetsFile)
    }

    public static func saveMyPresets(_ presets: [GamePreset]) throws {
        try AppPaths.ensureDirectories()
        try encode(PresetFile(presets: presets)).write(to: myPresetsFile, options: .atomic)
    }

    // MARK: - Matching

    /// Your own presets win over community ones.
    public static func bestMatch(for game: Game, mine: [GamePreset], community: [GamePreset]) -> GamePreset? {
        bestMatch(for: game, in: mine) ?? bestMatch(for: game, in: community)
    }

    public static func bestMatch(for game: Game, in presets: [GamePreset]) -> GamePreset? {
        presets
            .map { (preset: $0, score: $0.matchScore(for: game)) }
            .filter { $0.score > 0 }
            .max { $0.score < $1.score }?
            .preset
    }

    // MARK: - Creating, sharing and exporting

    /// Turns a game's current settings into a preset.
    public static func makePreset(from game: Game) -> GamePreset {
        let genericNames = ["game.exe", "start.exe", "launcher.exe", "play.exe", "main.exe", "app.exe"]
        let executable = game.executableURL.lastPathComponent
        let needsTitle = genericNames.contains(executable.lowercased())

        return GamePreset(
            id: slug(game.title),
            title: game.title,
            match: GamePreset.Match(
                executable: executable,
                titleContains: needsTitle ? game.title : nil,
                engine: game.engine == .unknown ? nil : game.engine
            ),
            settings: settings(from: game),
            status: .works
        )
    }

    public static func settings(from game: Game) -> GamePreset.Settings {
        GamePreset.Settings(
            launchMethod: game.launchMethod,
            graphicsBackend: game.launchMethod == .wine ? game.graphicsBackend : nil,
            arguments: game.arguments.isEmpty ? nil : game.arguments,
            environment: game.environment.isEmpty ? nil : game.environment,
            ownBottle: game.bottleName == BottleManager.defaultBottleName ? nil : true
        )
    }

    public static func json(for preset: GamePreset) -> String {
        guard let data = try? encode(preset) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// A pre-filled "new issue" page on GitHub, so anyone can share a preset without a token.
    public static func shareURL(for preset: GamePreset) -> URL? {
        let body = """
        **Game:** \(preset.title)
        **Status:** \(preset.status?.label ?? "Unknown")
        **Matches:** \(preset.matchSummary)
        **Settings:** \(preset.settingsSummary)

        \(preset.notes ?? "")

        ```json
        \(json(for: preset))
        ```

        _Shared from Portwey._
        """

        var components = URLComponents(
            url: repositoryURL.appendingPathComponent("issues/new"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "title", value: "Preset: \(preset.title)"),
            URLQueryItem(name: "body", value: body)
        ]
        return components?.url
    }

    /// A complete presets.json: community presets plus yours (yours replace community ones with the same id).
    public static func exportData(community: [GamePreset], mine: [GamePreset]) throws -> Data {
        var byID: [String: GamePreset] = [:]
        for preset in community { byID[preset.id] = preset }
        for preset in mine { byID[preset.id] = preset }

        let merged = byID.values.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        return try encode(PresetFile(presets: merged))
    }

    // MARK: - Helpers

    private static func readFile(_ url: URL) -> [GamePreset] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode(PresetFile.self, from: data))?.presets ?? []
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func slug(_ value: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let lowered = value.lowercased().replacingOccurrences(of: " ", with: "-")
        let cleaned = String(lowered.filter { allowed.contains($0) })
        return cleaned.isEmpty ? "game" : cleaned
    }
}
