import Foundation

public enum GraphicsBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case dxvk
    case dxmt
    case wined3d

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dxvk: return "DXVK (DirectX 10/11 → Vulkan → Metal)"
        case .dxmt: return "DXMT (DirectX 11 → Metal, experimental)"
        case .wined3d: return "WineD3D (OpenGL)"
        }
    }

    public var shortName: String {
        switch self {
        case .dxvk: return "DXVK"
        case .dxmt: return "DXMT"
        case .wined3d: return "WineD3D"
        }
    }
}

public struct Game: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public var title: String
    public var executablePath: String
    public var arguments: [String]
    public var environment: [String: String]
    public var bottleName: String
    public var graphicsBackend: GraphicsBackend
    public var engine: GameEngine?
    public var launchMethod: LaunchMethod
    public var coverFileName: String?
    public var iconFileName: String?
    /// The preset applied to this game, if any.
    public var presetID: String?
    /// Set for games installed through Steam; Steam launches them.
    public var steamAppID: Int?
    public var addedAt: Date
    public var lastPlayedAt: Date?
    public var playtimeSeconds: TimeInterval

    public init(
        id: UUID = UUID(),
        title: String,
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        bottleName: String = BottleManager.defaultBottleName,
        graphicsBackend: GraphicsBackend = .dxvk,
        engine: GameEngine? = nil,
        launchMethod: LaunchMethod = .wine,
        coverFileName: String? = nil,
        iconFileName: String? = nil,
        presetID: String? = nil,
        steamAppID: Int? = nil,
        addedAt: Date = Date(),
        lastPlayedAt: Date? = nil,
        playtimeSeconds: TimeInterval = 0
    ) {
        self.id = id
        self.title = title
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.bottleName = bottleName
        self.graphicsBackend = graphicsBackend
        self.engine = engine
        self.launchMethod = launchMethod
        self.coverFileName = coverFileName
        self.iconFileName = iconFileName
        self.presetID = presetID
        self.steamAppID = steamAppID
        self.addedAt = addedAt
        self.lastPlayedAt = lastPlayedAt
        self.playtimeSeconds = playtimeSeconds
    }

    // MARK: - Codable (tolerant of older library.json files)

    private enum CodingKeys: String, CodingKey {
        case id, title, executablePath, arguments, environment, bottleName, graphicsBackend
        case engine, launchMethod, coverFileName, iconFileName, presetID, steamAppID
        case addedAt, lastPlayedAt, playtimeSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        executablePath = try container.decode(String.self, forKey: .executablePath)
        arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        bottleName = try container.decodeIfPresent(String.self, forKey: .bottleName) ?? BottleManager.defaultBottleName
        graphicsBackend = try container.decodeIfPresent(GraphicsBackend.self, forKey: .graphicsBackend) ?? .dxvk
        engine = try container.decodeIfPresent(GameEngine.self, forKey: .engine)
        launchMethod = try container.decodeIfPresent(LaunchMethod.self, forKey: .launchMethod) ?? .wine
        coverFileName = try container.decodeIfPresent(String.self, forKey: .coverFileName)
        iconFileName = try container.decodeIfPresent(String.self, forKey: .iconFileName)
        presetID = try container.decodeIfPresent(String.self, forKey: .presetID)
        steamAppID = try container.decodeIfPresent(Int.self, forKey: .steamAppID)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        playtimeSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .playtimeSeconds) ?? 0
    }

    // MARK: - Helpers

    public var executableURL: URL { URL(fileURLWithPath: executablePath) }

    /// Games usually load their assets relative to the .exe folder.
    public var workingDirectoryURL: URL { executableURL.deletingLastPathComponent() }

    public var executableExists: Bool {
        FileManager.default.fileExists(atPath: executablePath)
    }

    public var isSteamGame: Bool { steamAppID != nil }

    /// Custom cover picked by the user.
    public var coverURL: URL? {
        coverFileName.map { AppPaths.covers.appendingPathComponent($0) }
    }

    /// Icon extracted automatically from the .exe.
    public var iconURL: URL? {
        iconFileName.map { AppPaths.covers.appendingPathComponent($0) }
    }

    /// Uses the .exe name as the title, or the folder name if the .exe name is too generic.
    public static func suggestedTitle(for executable: URL) -> String {
        let name = executable.deletingPathExtension().lastPathComponent
        let genericNames = ["game", "start", "launcher", "play", "main", "app"]
        if genericNames.contains(name.lowercased()) {
            return executable.deletingLastPathComponent().lastPathComponent
        }
        return name
    }
}
