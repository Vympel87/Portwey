import Foundation

public struct RuntimeInfo: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let tag: String
    public let version: String
    public let installPath: String
    public let wineBinaryPath: String

    public init(tag: String, version: String, installPath: String, wineBinaryPath: String) {
        self.tag = tag
        self.version = version
        self.installPath = installPath
        self.wineBinaryPath = wineBinaryPath
    }

    public var id: String { installPath }
    public var wineBinaryURL: URL { URL(fileURLWithPath: wineBinaryPath) }
}

public struct GitHubRelease: Decodable, Sendable {
    public let tagName: String
    public let assets: [Asset]

    public struct Asset: Decodable, Sendable, Hashable {
        public let name: String
        public let browserDownloadUrl: URL
        public let size: Int
    }
}

/// One downloadable Wine build (a release can offer several flavors: devel, staging, stable).
public struct WineRelease: Identifiable, Sendable, Hashable {
    public let tag: String
    public let asset: GitHubRelease.Asset

    public var id: String { asset.name }

    /// e.g. "wine-devel-11.21-osx64". Also used as the install folder name.
    public var folderName: String {
        asset.name.replacingOccurrences(of: ".tar.xz", with: "")
    }

    /// e.g. "Wine Devel 11.21"
    public var displayName: String {
        let trimmed = folderName
            .replacingOccurrences(of: "wine-", with: "")
            .replacingOccurrences(of: "-osx64", with: "")
        guard let dash = trimmed.firstIndex(of: "-") else { return folderName }
        let flavor = trimmed[..<dash].capitalized
        let version = trimmed[trimmed.index(after: dash)...]
        return "Wine \(flavor) \(version)"
    }

    public var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(asset.size), countStyle: .file)
    }
}

public enum WineInstallStage: Sendable {
    case downloading
    case extracting
    case verifying
}

public enum WineRuntimeService {
    static let owner = "Gcenx"
    static let repo = "macOS_Wine_builds"
    static let preferredAssetPrefix = "wine-devel"
    static var registryFile: URL { AppPaths.runtimes.appendingPathComponent("wine-runtimes.json") }

    // MARK: - Default runtime

    /// The default runtime, if any, as long as its binary is still valid.
    public static func installedRuntime() -> RuntimeInfo? {
        guard
            let data = try? Data(contentsOf: AppPaths.runtimeInfoFile),
            let info = try? JSONDecoder().decode(RuntimeInfo.self, from: data),
            FileManager.default.isExecutableFile(atPath: info.wineBinaryPath)
        else { return nil }
        return info
    }

    /// Makes this runtime the default.
    public static func save(_ info: RuntimeInfo) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(info)
        try data.write(to: AppPaths.runtimeInfoFile, options: .atomic)
    }

    // MARK: - All installed runtimes

    /// Every installed Wine runtime. The default one is always included.
    public static func installedRuntimes() -> [RuntimeInfo] {
        var list = loadRegistry().filter { FileManager.default.isExecutableFile(atPath: $0.wineBinaryPath) }
        if let current = installedRuntime(), !list.contains(where: { $0.installPath == current.installPath }) {
            list.insert(current, at: 0)
            saveRegistry(list)
        }
        return list
    }

    static func register(_ info: RuntimeInfo) {
        var list = installedRuntimes()
        list.removeAll { $0.installPath == info.installPath }
        list.append(info)
        saveRegistry(list)
    }

    static func unregister(_ info: RuntimeInfo) {
        var list = loadRegistry()
        list.removeAll { $0.installPath == info.installPath }
        saveRegistry(list)
    }

    private static func loadRegistry() -> [RuntimeInfo] {
        guard let data = try? Data(contentsOf: registryFile) else { return [] }
        return (try? JSONDecoder().decode([RuntimeInfo].self, from: data)) ?? []
    }

    private static func saveRegistry(_ list: [RuntimeInfo]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(list) else { return }
        try? AppPaths.ensureDirectories()
        try? data.write(to: registryFile, options: .atomic)
    }

    // MARK: - Available releases

    public static func fetchLatestRelease() async throws -> GitHubRelease {
        try await GitHubClient.latestRelease(owner: owner, repo: repo)
    }

    /// Wine builds from recent releases, newest first.
    public static func availableReleases() async throws -> [WineRelease] {
        let releases = try await GitHubClient.releases(owner: owner, repo: repo, perPage: 30)
        return releases.flatMap { release in
            release.assets
                .filter(isWineTarball)
                .map { WineRelease(tag: release.tagName, asset: $0) }
        }
    }

    static func isWineTarball(_ asset: GitHubRelease.Asset) -> Bool {
        asset.name.hasPrefix("wine-") && asset.name.contains("osx64") && asset.name.hasSuffix(".tar.xz")
    }

    public static func pickAsset(from release: GitHubRelease) throws -> GitHubRelease.Asset {
        let tarballs = release.assets.filter(isWineTarball)
        if let preferred = tarballs.first(where: { $0.name.hasPrefix(preferredAssetPrefix) }) {
            return preferred
        }
        if let fallback = tarballs.first {
            return fallback
        }
        throw LauncherError.noWineAssetFound
    }

    // MARK: - Install & uninstall

    /// Downloads, extracts and tests a Wine build, then adds it to the installed list.
    /// It does NOT make it the default; call `save` for that.
    public static func install(
        _ release: WineRelease,
        progress: @escaping @Sendable (Double) -> Void,
        stage: @escaping @Sendable (WineInstallStage) -> Void
    ) async throws -> RuntimeInfo {
        try AppPaths.ensureDirectories()

        stage(.downloading)
        let archive = AppPaths.downloads.appendingPathComponent(release.asset.name)
        try await download(asset: release.asset, to: archive, progress: progress)

        stage(.extracting)
        let installDir = try await extract(archive: archive, tag: release.folderName)
        try? FileManager.default.removeItem(at: archive)

        guard let wineBinary = findWineBinary(in: installDir) else {
            throw LauncherError.wineBinaryNotFound
        }

        stage(.verifying)
        let version = try await wineVersion(binary: wineBinary)

        let info = RuntimeInfo(
            tag: release.folderName,
            version: version,
            installPath: installDir.path,
            wineBinaryPath: wineBinary.path
        )
        register(info)
        return info
    }

    /// Deletes a Wine runtime and any DXVK copies made from it.
    public static func uninstall(_ info: RuntimeInfo) throws {
        let fm = FileManager.default
        let directory = URL(fileURLWithPath: info.installPath)

        let variantPrefix = directory.lastPathComponent + "-dxvk-"
        let siblings = (try? fm.contentsOfDirectory(at: AppPaths.runtimes, includingPropertiesForKeys: nil)) ?? []
        for item in siblings where item.lastPathComponent.hasPrefix(variantPrefix) {
            try? fm.removeItem(at: item)
        }

        if fm.fileExists(atPath: directory.path) {
            try fm.removeItem(at: directory)
        }
        unregister(info)
    }

    // MARK: - Building blocks

    /// Downloads a release asset, retrying a few times if the connection drops.
    /// Skips the download if the same file is already fully downloaded.
    public static func download(
        asset: GitHubRelease.Asset,
        to destination: URL,
        attempts: Int = 3,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path),
           let size = attributes[.size] as? Int,
           size == asset.size {
            progress(1)
            return
        }

        var lastError: Error?
        for attempt in 1...attempts {
            do {
                let downloader = FileDownloader(destination: destination, onProgress: progress)
                _ = try await downloader.download(from: asset.browserDownloadUrl)
                return
            } catch {
                lastError = error
                if attempt < attempts {
                    // Back off a little before retrying (2s, 4s, …).
                    try await Task.sleep(for: .seconds(Double(attempt) * 2))
                }
            }
        }
        throw lastError ?? LauncherError.downloadFailed("Unknown error")
    }

    public static func extract(archive: URL, tag: String) async throws -> URL {
        let safeTag = tag.replacingOccurrences(of: "/", with: "-")
        let destination = AppPaths.runtimes.appendingPathComponent(safeTag, isDirectory: true)
        let fm = FileManager.default

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        try await Shell.runChecked("/usr/bin/tar", ["-xf", archive.path, "-C", destination.path])
        // Remove the quarantine flag so Gatekeeper doesn't block the Wine binaries.
        _ = try? await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])

        return destination
    }

    /// Finds the `wine` binary inside the extracted folder
    /// (usually inside .app/Contents/Resources/wine/bin).
    public static func findWineBinary(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        var candidates: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            let parent = url.deletingLastPathComponent().lastPathComponent
            if (name == "wine" || name == "wine64") && parent == "bin" {
                candidates.append(url)
            }
        }
        return candidates.first(where: { $0.lastPathComponent == "wine" }) ?? candidates.first
    }

    public static func wineVersion(binary: URL) async throws -> String {
        let result = try await Shell.runChecked(binary.path, ["--version"])
        let lastLine = result.output.split(separator: "\n").last.map(String.init)
        return lastLine ?? result.output
    }
}
