//
//  LauncherError 2.swift
//  LauncherCore
//
//  Created by Yudhistira Rafazaky Bandono on 04/11/26.
//


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
        }
    }
}
