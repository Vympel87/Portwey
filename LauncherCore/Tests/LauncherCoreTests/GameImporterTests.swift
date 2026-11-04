import Foundation
import Testing
@testable import LauncherCore

@Suite("Finding executables")
struct GameImporterTests {
    @Test("Finds the game's .exe and ignores other files")
    func findsGame() throws {
        let folder = try makeTemporaryFolder()
        try touch("My Game/Game.exe", in: folder)
        try touch("My Game/readme.txt", in: folder)
        try touch("My Game/data/level1.dat", in: folder)

        let found = GameImporter.findExecutables(in: folder)

        #expect(found.contains { $0.lastPathComponent == "Game.exe" })
        #expect(found.allSatisfy { $0.pathExtension.lowercased() == "exe" })
    }

    @Test("Doesn't dig deeper than the limit")
    func respectsDepth() throws {
        let folder = try makeTemporaryFolder()
        try touch("a/b/c/d/e/f/g/Deep.exe", in: folder)

        let found = GameImporter.findExecutables(in: folder, maxDepth: 2)

        #expect(!found.contains { $0.lastPathComponent == "Deep.exe" })
    }

    @Test("An empty folder has no executables")
    func emptyFolder() throws {
        let folder = try makeTemporaryFolder()
        #expect(GameImporter.findExecutables(in: folder).isEmpty)
    }
}
