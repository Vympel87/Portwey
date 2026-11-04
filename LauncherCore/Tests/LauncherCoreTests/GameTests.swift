import Foundation
import Testing
@testable import LauncherCore

@Suite("Game model")
struct GameTests {
    /// A library.json entry from an older version, without the newer optional fields.
    private let olderEntry = """
    {
        "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
        "title": "Starmaker Story",
        "executablePath": "/Games/Starmaker Story/Starmaker Story.exe",
        "arguments": ["-windowed"],
        "environment": { "DXVK_HUD": "fps" },
        "bottleName": "default",
        "graphicsBackend": "dxvk",
        "engine": "unity",
        "launchMethod": "wine",
        "addedAt": 800000000,
        "playtimeSeconds": 3600
    }
    """

    private func decodeOlderEntry() throws -> Game {
        try JSONDecoder().decode(Game.self, from: Data(olderEntry.utf8))
    }

    @Test("Older library entries still load")
    func olderEntriesLoad() throws {
        let game = try decodeOlderEntry()

        #expect(game.title == "Starmaker Story")
        #expect(game.graphicsBackend == .dxvk)
        #expect(game.engine == .unity)
        #expect(game.launchMethod == .wine)
        #expect(game.arguments == ["-windowed"])
        #expect(game.environment["DXVK_HUD"] == "fps")
        #expect(game.steamAppID == nil)
        #expect(game.presetID == nil)
        #expect(game.lastPlayedAt == nil)
    }

    @Test("Saving and loading gives back the same game")
    func roundTrip() throws {
        var game = try decodeOlderEntry()
        game.steamAppID = 1_234_560
        game.lastPlayedAt = Date(timeIntervalSinceReferenceDate: 810_000_000)

        let data = try JSONEncoder().encode(game)
        let loaded = try JSONDecoder().decode(Game.self, from: data)

        #expect(loaded == game)
    }

    @Test("Paths and Steam flag")
    func derivedValues() throws {
        var game = try decodeOlderEntry()

        #expect(game.workingDirectoryURL.path == "/Games/Starmaker Story")
        #expect(game.executableURL.lastPathComponent == "Starmaker Story.exe")
        #expect(game.isSteamGame == false)

        game.steamAppID = 1_234_560
        #expect(game.isSteamGame == true)
    }

    @Test("Suggested titles don't keep the .exe extension")
    func suggestedTitle() {
        let title = Game.suggestedTitle(for: URL(fileURLWithPath: "/Games/Starmaker Story/Starmaker Story.exe"))

        #expect(!title.isEmpty)
        #expect(!title.lowercased().hasSuffix(".exe"))
    }
}
