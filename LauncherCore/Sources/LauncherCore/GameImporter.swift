import Foundation

public enum GameImporter {
    /// .exe names that are almost never the game itself.
    private static let ignoredNameFragments = [
        "unitycrashhandler", "crashhandler", "crashpad", "crashreport",
        "unins", "uninstall", "setup", "install", "redist", "vcredist", "vc_redist",
        "dxsetup", "dxwebsetup", "directx", "dotnet", "prereq",
        "notification_helper", "updater", "easyanticheat", "battleye"
    ]

    /// Folders that only contain helper executables.
    private static let ignoredFolderNames = ["monobleedingedge", "redist", "_commonredist", "directx"]

    /// Finds .exe files in a game folder, best guess first.
    public static func findExecutables(in folder: URL, maxDepth: Int = 4) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [(url: URL, score: Int)] = []
        while let url = enumerator.nextObject() as? URL {
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if ignoredFolderNames.contains(url.lastPathComponent.lowercased()) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard url.pathExtension.lowercased() == "exe" else { continue }
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            if ignoredNameFragments.contains(where: { name.contains($0) }) { continue }

            found.append((url, score(for: url, root: folder, depth: enumerator.level)))
        }

        return found.sorted { $0.score > $1.score }.map(\.url)
    }

    private static func score(for exe: URL, root: URL, depth: Int) -> Int {
        let name = exe.deletingPathExtension().lastPathComponent
        let folder = exe.deletingLastPathComponent()
        let rootName = root.lastPathComponent
        var score = 0

        // Unity games ship "<Name>_Data" right next to "<Name>.exe".
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(name)_Data").path) {
            score += 100
        }
        // The exe often shares its name with the game folder.
        if rootName.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains(rootName) {
            score += 40
        }
        // Prefer files closer to the top of the folder.
        score -= depth * 10
        // Bigger executables are more likely to be the actual game.
        if let size = try? exe.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            score += min(size / 1_000_000, 30)
        }
        return score
    }

    /// Extracts a .zip into Portwey's games folder and returns the new folder.
    public static func extractZip(_ zip: URL) async throws -> URL {
        try AppPaths.ensureDirectories()

        let baseName = zip.deletingPathExtension().lastPathComponent
        var destination = AppPaths.games.appendingPathComponent(baseName, isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = AppPaths.games.appendingPathComponent("\(baseName) \(counter)", isDirectory: true)
            counter += 1
        }

        // ditto handles zips from both macOS and Windows (including non-English file names).
        try await Shell.runChecked("/usr/bin/ditto", ["-x", "-k", zip.path, destination.path])
        _ = try? await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])
        return destination
    }
}
