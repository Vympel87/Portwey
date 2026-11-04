import Foundation

public struct GodotRuntime: Codable, Sendable, Equatable, Identifiable {
    public let version: String
    public let appPath: String

    public var id: String { version }

    public var executableURL: URL {
        URL(fileURLWithPath: appPath).appendingPathComponent("Contents/MacOS/Godot")
    }
}

public enum GodotNativeSupport: Sendable {
    case supported(GodotPackInfo)
    case unsupported(String)

    public var isSupported: Bool {
        if case .supported = self { return true }
        return false
    }

    public var reason: String? {
        if case .unsupported(let reason) = self { return reason }
        return nil
    }
}

public enum GodotService {
    static var rootDirectory: URL { AppPaths.runtimes.appendingPathComponent("godot", isDirectory: true) }
    static var registryFile: URL { AppPaths.runtimes.appendingPathComponent("godot.json") }

    /// godot-builds keeps every release (including old ones); the main repo is a fallback.
    static let repositories: [(owner: String, repo: String)] = [
        ("godotengine", "godot-builds"),
        ("godotengine", "godot")
    ]

    // MARK: - Checking a game

    /// Finds the game's data pack: "<Name>.pck", any other .pck next to the .exe, or one embedded in the .exe.
    public static func findPack(for executable: URL) -> GodotPackInfo? {
        let folder = executable.deletingLastPathComponent()
        let name = executable.deletingPathExtension().lastPathComponent

        if let info = GodotPackInfo.read(from: folder.appendingPathComponent("\(name).pck")) {
            return info
        }
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for pack in contents where pack.pathExtension.lowercased() == "pck" {
            if let info = GodotPackInfo.read(from: pack) {
                return info
            }
        }
        return GodotPackInfo.read(from: executable)
    }

    /// Whether the game can run on the macOS build of Godot, and why not if it can't.
    public static func nativeSupport(for executable: URL) -> GodotNativeSupport {
        guard let pack = findPack(for: executable) else {
            return .unsupported("Couldn't find this game's Godot data (.pck).")
        }
        if pack.isEncrypted {
            return .unsupported("The game's data is encrypted, so only its own Windows build can read it.")
        }
        if pack.major < 3 {
            return .unsupported("Godot \(pack.version) is too old to run natively.")
        }

        let folder = executable.deletingLastPathComponent()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []

        let hasDotNetData = contents.contains { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDirectory && url.lastPathComponent.hasPrefix("data_")
        }
        if hasDotNetData {
            return .unsupported("This is a C# (.NET) Godot game, which needs a special Godot build.")
        }
        if contents.contains(where: { $0.pathExtension.lowercased() == "dll" }) {
            return .unsupported("The game ships Windows-only plugins (.dll files) that can't run natively.")
        }
        return .supported(pack)
    }

    // MARK: - Installed versions

    public static func installedRuntimes() -> [GodotRuntime] {
        guard let data = try? Data(contentsOf: registryFile) else { return [] }
        let list = (try? JSONDecoder().decode([GodotRuntime].self, from: data)) ?? []
        return list.filter { FileManager.default.isExecutableFile(atPath: $0.executableURL.path) }
    }

    public static func installed(version: String) -> GodotRuntime? {
        installedRuntimes().first { $0.version == version }
    }

    private static func register(_ runtime: GodotRuntime) {
        var list = installedRuntimes()
        list.removeAll { $0.version == runtime.version }
        list.append(runtime)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(list) {
            try? data.write(to: registryFile, options: .atomic)
        }
    }

    // MARK: - Download

    /// Returns the macOS build of this exact Godot version, downloading it first if needed.
    public static func ensureInstalled(
        version: String,
        log: @escaping @Sendable (String) -> Void
    ) async throws -> GodotRuntime {
        if let existing = installed(version: version) {
            return existing
        }

        try AppPaths.ensureDirectories()
        log("Godot \(version) for macOS isn't installed yet, downloading it (one-time)…")

        let tag = "\(version)-stable"
        var found: GitHubRelease.Asset?
        for source in repositories {
            if let release = try? await GitHubClient.release(owner: source.owner, repo: source.repo, tag: tag),
               let asset = pickAsset(from: release) {
                found = asset
                break
            }
        }
        guard let asset = found else {
            throw LauncherError.godotVersionUnavailable(version)
        }
        log("Godot \(version): \(asset.name)")

        let archive = AppPaths.downloads.appendingPathComponent(asset.name)
        try await WineRuntimeService.download(asset: asset, to: archive) { value in
            let percent = Int(value * 100)
            if percent % 10 == 0 {
                log("Downloading Godot… \(percent)%")
            }
        }

        log("Extracting Godot…")
        let destination = rootDirectory.appendingPathComponent(version, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try await Shell.runChecked("/usr/bin/ditto", ["-x", "-k", archive.path, destination.path])
        _ = try? await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])
        try? FileManager.default.removeItem(at: archive)

        guard let app = findApp(in: destination) else {
            throw LauncherError.godotAppNotFound
        }

        let runtime = GodotRuntime(version: version, appPath: app.path)
        register(runtime)
        log("Godot \(version) is ready ✓")
        return runtime
    }

    /// The standard (non-.NET) macOS download. Godot 4 uses "macos.universal", Godot 3 "osx.universal" or "osx.64".
    static func pickAsset(from release: GitHubRelease) -> GitHubRelease.Asset? {
        let zips = release.assets.filter { asset in
            let name = asset.name.lowercased()
            return name.hasSuffix(".zip") && !name.contains("mono") && !name.contains("export_templates")
        }
        for marker in ["macos.universal", "osx.universal", "osx.64", "osx64"] {
            if let match = zips.first(where: { $0.name.lowercased().contains(marker) }) {
                return match
            }
        }
        return nil
    }

    private static func findApp(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension == "app" && url.lastPathComponent.hasPrefix("Godot") {
                return url
            }
        }
        return nil
    }
}
