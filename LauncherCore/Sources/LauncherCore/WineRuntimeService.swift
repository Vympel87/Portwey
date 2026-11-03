import Foundation

public struct RuntimeInfo: Codable, Sendable, Equatable {
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

    public var wineBinaryURL: URL { URL(fileURLWithPath: wineBinaryPath) }
}

public struct GitHubRelease: Decodable, Sendable {
    public let tagName: String
    public let assets: [Asset]

    public struct Asset: Decodable, Sendable {
        public let name: String
        public let browserDownloadUrl: URL
        public let size: Int
    }
}

public enum WineRuntimeService {
    static let releasesURL = URL(string: "https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases/latest")!
    static let preferredAssetPrefix = "wine-devel"

    /// Returns the installed runtime, if any, as long as its binary is still valid.
    public static func installedRuntime() -> RuntimeInfo? {
        guard
            let data = try? Data(contentsOf: AppPaths.runtimeInfoFile),
            let info = try? JSONDecoder().decode(RuntimeInfo.self, from: data),
            FileManager.default.isExecutableFile(atPath: info.wineBinaryPath)
        else { return nil }
        return info
    }

    public static func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Portwey", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LauncherError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    public static func pickAsset(from release: GitHubRelease) throws -> GitHubRelease.Asset {
        let tarballs = release.assets.filter {
            $0.name.hasSuffix(".tar.xz") && $0.name.contains("osx64")
        }
        if let preferred = tarballs.first(where: { $0.name.hasPrefix(preferredAssetPrefix) }) {
            return preferred
        }
        if let fallback = tarballs.first(where: { $0.name.hasPrefix("wine-") }) {
            return fallback
        }
        throw LauncherError.noWineAssetFound
    }

    public static func download(
        asset: GitHubRelease.Asset,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let downloader = FileDownloader(destination: destination, onProgress: progress)
        _ = try await downloader.download(from: asset.browserDownloadUrl)
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

    public static func save(_ info: RuntimeInfo) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(info)
        try data.write(to: AppPaths.runtimeInfoFile, options: .atomic)
    }
}
