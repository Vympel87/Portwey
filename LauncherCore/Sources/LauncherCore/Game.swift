import Foundation

public enum GraphicsBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case dxvk
    case wined3d

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dxvk: return "DXVK (DirectX 10/11 → Metal)"
        case .wined3d: return "WineD3D (OpenGL)"
        }
    }

    public var shortName: String {
        switch self {
        case .dxvk: return "DXVK"
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
    public var coverFileName: String?
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
        coverFileName: String? = nil,
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
        self.coverFileName = coverFileName
        self.addedAt = addedAt
        self.lastPlayedAt = lastPlayedAt
        self.playtimeSeconds = playtimeSeconds
    }

    // MARK: - Codable (tolerant of older library.json files)

    private enum CodingKeys: String, CodingKey {
        case id, title, executablePath, arguments, environment, bottleName, graphicsBackend
        case coverFileName, addedAt, lastPlayedAt, playtimeSeconds
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
        coverFileName = try container.decodeIfPresent(String.self, forKey: .coverFileName)
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

    public var coverURL: URL? {
        coverFileName.map { AppPaths.covers.appendingPathComponent($0) }
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
