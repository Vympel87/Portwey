import Foundation
import Testing
@testable import LauncherCore

@Suite("Game engines")
struct GameEngineTests {
    @Test("Engines that can run natively")
    func nativeLaunchMethods() {
        #expect(GameEngine.rpgMakerMV.nativeLaunchMethod == .nwjs)
        #expect(GameEngine.rpgMakerMZ.nativeLaunchMethod == .nwjs)
        #expect(GameEngine.godot.nativeLaunchMethod == .godot)
        #expect(GameEngine.unity.nativeLaunchMethod == nil)
        #expect(GameEngine.unknown.nativeLaunchMethod == nil)
    }

    @Test("Only Wine isn't native")
    func launchMethods() {
        #expect(LaunchMethod.wine.isNative == false)
        #expect(LaunchMethod.nwjs.isNative == true)
        #expect(LaunchMethod.godot.isNative == true)
    }

    @Test("Every engine has a name", arguments: GameEngine.allCases)
    func displayNames(engine: GameEngine) {
        #expect(!engine.displayName.isEmpty)
    }

    // MARK: - Detection

    @Test("Detects Unity")
    func unity() throws {
        let folder = try makeTemporaryFolder()
        let exe = try touch("Starmaker Story.exe", in: folder)
        try touch("UnityPlayer.dll", in: folder)
        try makeFolder("Starmaker Story_Data", in: folder)

        #expect(GameEngineDetector.detect(executable: exe) == .unity)
    }

    @Test("Detects RPG Maker MV")
    func rpgMakerMV() throws {
        let folder = try makeTemporaryFolder()
        let exe = try touch("Game.exe", in: folder)
        try touch("package.json", in: folder)
        try touch("www/js/rpg_core.js", in: folder)

        #expect(GameEngineDetector.detect(executable: exe) == .rpgMakerMV)
    }

    @Test("Detects RPG Maker MV with renamed scripts")
    func rpgMakerMVRenamedScripts() throws {
        let folder = try makeTemporaryFolder()
        let exe = try touch("Game.exe", in: folder)
        try touch("package.json", in: folder)
        try touch("nw.dll", in: folder)
        try makeFolder("www", in: folder)

        #expect(GameEngineDetector.detect(executable: exe) == .rpgMakerMV)
    }

    @Test("Detects RPG Maker MZ")
    func rpgMakerMZ() throws {
        let folder = try makeTemporaryFolder()
        let exe = try touch("Game.exe", in: folder)
        try touch("package.json", in: folder)
        try touch("js/rmmz_core.js", in: folder)

        #expect(GameEngineDetector.detect(executable: exe) == .rpgMakerMZ)
    }

    @Test("RPG Maker scripts without package.json aren't enough")
    func rpgMakerNeedsPackageJSON() throws {
        let folder = try makeTemporaryFolder()
        let exe = try touch("Game.exe", in: folder)
        try touch("www/js/rpg_core.js", in: folder)

        #expect(GameEngineDetector.detect(executable: exe) == .unknown)
    }

    @Test("Detects RPG Maker VX Ace")
    func rpgMakerVXAce() throws {
        let folder = try makeTemporaryFolder()
        let exe = try touch("Game.exe", in: folder)
        try touch("Game.rgss3a", in: folder)

        #expect(GameEngineDetector.detect(executable: exe) == .rpgMakerVXAce)
    }

    @Test("Detects Godot from a .pck next to the .exe")
    func godot() throws {
        let folder = try makeTemporaryFolder()
        let exe = try touch("Game.exe", in: folder)
        try touch("Game.pck", in: folder)

        #expect(GameEngineDetector.detect(executable: exe) == .godot)
    }

    @Test("Detects GameMaker")
    func gameMaker() throws {
        let folder = try makeTemporaryFolder()
        let exe = try touch("Game.exe", in: folder)
        try touch("data.win", in: folder)

        #expect(GameEngineDetector.detect(executable: exe) == .gameMaker)
    }

    @Test("Detects Ren'Py")
    func renpy() throws {
        let folder = try makeTemporaryFolder()
        let exe = try touch("Game.exe", in: folder)
        try makeFolder("renpy", in: folder)
        try makeFolder("lib", in: folder)

        #expect(GameEngineDetector.detect(executable: exe) == .renpy)
    }

    @Test("Detects Unreal")
    func unreal() throws {
        let folder = try makeTemporaryFolder()
        let exe = try touch("MyGame.exe", in: folder)
        try makeFolder("Engine", in: folder)
        try makeFolder("MyGame/Binaries", in: folder)

        #expect(GameEngineDetector.detect(executable: exe) == .unreal)
    }

    @Test("Falls back to unknown")
    func unknown() throws {
        let folder = try makeTemporaryFolder()
        let exe = try touch("Game.exe", in: folder)

        #expect(GameEngineDetector.detect(executable: exe) == .unknown)
    }
}
