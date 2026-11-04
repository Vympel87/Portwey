import Foundation

public enum LauncherError: LocalizedError, Sendable {
    case commandFailed(command: String, exitCode: Int32, output: String)
    case rosettaInstallCancelled
    case rosettaUnavailable
    case noWineAssetFound
    case downloadFailed(String)
    case wineBinaryNotFound
    case invalidResponse
    case bottleCreationFailed
    case executableNotFound(String)
    case noDXVKAssetFound
    case dxvkLayoutNotFound
    case unexpectedRuntimeLayout(String)
    case nwjsUnavailable
    case nwjsAppNotFound
    case packageJSONMissing(String)
    case godotVersionUnavailable(String)
    case godotAppNotFound
    case godotNotSupported(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode, let output):
            return "Command failed (exit \(exitCode)): \(command)\n\(output)"
        case .rosettaInstallCancelled:
            return "Rosetta installation was cancelled. Rosetta is required to run Wine."
        case .rosettaUnavailable:
            return "Rosetta was installed but still can't be detected. Try restarting your Mac."
        case .noWineAssetFound:
            return "Couldn't find a macOS Wine build in the latest release."
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .wineBinaryNotFound:
            return "Wine was extracted, but the 'wine' binary couldn't be found."
        case .invalidResponse:
            return "Received an invalid response from GitHub. Check your internet connection."
        case .bottleCreationFailed:
            return "Couldn't create the Windows environment (bottle)."
        case .executableNotFound(let path):
            return "Game file not found: \(path)"
        case .noDXVKAssetFound:
            return "Couldn't find a DXVK-macOS package in the latest release."
        case .dxvkLayoutNotFound:
            return "DXVK was downloaded, but its x64 DLL folder couldn't be found."
        case .unexpectedRuntimeLayout(let path):
            return "The Wine runtime has an unexpected folder layout: \(path)"
        case .nwjsUnavailable:
            return "Couldn't find an NW.js build for this Mac. Check your internet connection."
        case .nwjsAppNotFound:
            return "NW.js was downloaded, but nwjs.app couldn't be found inside it."
        case .packageJSONMissing(let path):
            return "This game has no readable package.json, so it can't run natively: \(path)"
        case .godotVersionUnavailable(let version):
            return "Couldn't find a macOS download for Godot \(version). Try running the game with Wine instead."
        case .godotAppNotFound:
            return "Godot was downloaded, but Godot.app couldn't be found inside it."
        case .godotNotSupported(let reason):
            return "This game can't run natively: \(reason) Switch 'Runs with' to Wine in the game's settings."
        }
    }
}
