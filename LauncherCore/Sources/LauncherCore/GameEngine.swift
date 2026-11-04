import Foundation

public enum GameEngine: String, Codable, CaseIterable, Sendable {
    case unity
    case unreal
    case godot
    case gameMaker
    case rpgMakerMV
    case rpgMakerMZ
    case rpgMakerVXAce
    case renpy
    case unknown

    public var displayName: String {
        switch self {
        case .unity: return "Unity"
        case .unreal: return "Unreal"
        case .godot: return "Godot"
        case .gameMaker: return "GameMaker"
        case .rpgMakerMV: return "RPG Maker MV"
        case .rpgMakerMZ: return "RPG Maker MZ"
        case .rpgMakerVXAce: return "RPG Maker VX Ace"
        case .renpy: return "Ren'Py"
        case .unknown: return "Unknown"
        }
    }

    /// How this engine can run natively on macOS, if it can.
    public var nativeLaunchMethod: LaunchMethod? {
        switch self {
        case .rpgMakerMV, .rpgMakerMZ: return .nwjs
        case .godot: return .godot
        default: return nil
        }
    }
}

public enum LaunchMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case wine
    case nwjs
    case godot

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .wine: return "Wine (Windows version)"
        case .nwjs: return "Native (NW.js for macOS)"
        case .godot: return "Native (Godot for macOS)"
        }
    }

    public var shortName: String {
        isNative ? "Native" : "Wine"
    }

    public var isNative: Bool {
        self != .wine
    }
}

public enum GameEngineDetector {
    /// Guesses the engine from the files that sit next to the .exe.
    public static func detect(executable: URL) -> GameEngine {
        let folder = executable.deletingLastPathComponent()
        let name = executable.deletingPathExtension().lastPathComponent

        func exists(_ relativePath: String) -> Bool {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(relativePath).path)
        }

        if exists("package.json") {
            if exists("www/js/rpg_core.js") || exists("www/js/rpg_managers.js") { return .rpgMakerMV }
            if exists("js/rmmz_core.js") || exists("js/rmmz_managers.js") { return .rpgMakerMZ }
            // Some MV games rename or bundle their scripts, but keep the www folder.
            if exists("www") && exists("nw.dll") { return .rpgMakerMV }
        }
        if exists("\(name)_Data") || exists("UnityPlayer.dll") { return .unity }
        if exists("\(name).pck") || hasFile(withExtension: "pck", in: folder) { return .godot }
        if exists("data.win") { return .gameMaker }
        if exists("renpy") && exists("lib") { return .renpy }
        if exists("Game.rgss3a") || exists("System/RGSS301.dll") || exists("System/RGSS300.dll") { return .rpgMakerVXAce }
        if exists("Engine") || exists("\(name)/Binaries") { return .unreal }
        // Godot games exported as a single .exe carry their data at the end of the file.
        if GodotPackInfo.read(from: executable) != nil { return .godot }
        return .unknown
    }

    private static func hasFile(withExtension fileExtension: String, in folder: URL) -> Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return contents.contains { $0.pathExtension.lowercased() == fileExtension }
    }
}
