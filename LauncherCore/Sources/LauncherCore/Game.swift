import Foundation

public struct Game: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public var title: String
    public var executablePath: String
    public var arguments: [String]
    public var bottleName: String
    public var addedAt: Date
    public var lastPlayedAt: Date?
    public var playtimeSeconds: TimeInterval

    public init(
        id: UUID = UUID(),
        title: String,
        executablePath: String,
        arguments: [String] = [],
        bottleName: String = BottleManager.defaultBottleName,
        addedAt: Date = Date(),
        lastPlayedAt: Date? = nil,
        playtimeSeconds: TimeInterval = 0
    ) {
        self.id = id
        self.title = title
        self.executablePath = executablePath
        self.arguments = arguments
        self.bottleName = bottleName
        self.addedAt = addedAt
        self.lastPlayedAt = lastPlayedAt
        self.playtimeSeconds = playtimeSeconds
    }

    public var executableURL: URL { URL(fileURLWithPath: executablePath) }

    /// Games usually load their assets relative to the .exe folder.
    public var workingDirectoryURL: URL { executableURL.deletingLastPathComponent() }

    public var executableExists: Bool {
        FileManager.default.fileExists(atPath: executablePath)
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
