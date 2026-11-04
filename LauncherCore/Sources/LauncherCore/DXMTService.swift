import Foundation

public struct DXMTInfo: Codable, Sendable, Equatable {
    public let tag: String
    public let windowsPath: String
    public let unixPath: String

    public var windowsURL: URL { URL(fileURLWithPath: windowsPath) }
    public var unixURL: URL { URL(fileURLWithPath: unixPath) }
}

/// DXMT: Direct3D 11 translated straight to Metal. Downloaded the first time a game uses it.
public enum DXMTService {
    public static let owner = "3Shain"
    public static let repo = "dxmt"

    static var rootDirectory: URL { AppPaths.runtimes.appendingPathComponent("dxmt", isDirectory: true) }
    static var infoFile: URL { AppPaths.runtimes.appendingPathComponent("dxmt.json") }
    private static let bottleMarkerName = ".portwey-dxmt"

    // MARK: - Installed state

    public static func installed() -> DXMTInfo? {
        guard
            let data = try? Data(contentsOf: infoFile),
            let info = try? JSONDecoder().decode(DXMTInfo.self, from: data),
            FileManager.default.fileExists(atPath: info.unixURL.appendingPathComponent("winemetal.so").path)
        else { return nil }
        return info
    }

    /// Returns the installed DXMT, downloading it first if needed.
    public static func ensureInstalled(log: @escaping @Sendable (String) -> Void) async throws -> DXMTInfo {
        if let existing = installed() {
            return existing
        }

        try AppPaths.ensureDirectories()
        log("DXMT isn't installed yet, downloading it (one-time)…")

        let releases = try await GitHubClient.releases(owner: owner, repo: repo)
        var picked: (release: GitHubRelease, asset: GitHubRelease.Asset)?
        for release in releases {
            if let asset = pickAsset(from: release) {
                picked = (release, asset)
                break
            }
        }
        guard let picked else {
            throw LauncherError.dxmtUnavailable
        }
        let tag = picked.release.tagName
        log("DXMT \(tag): \(picked.asset.name)")

        let archive = AppPaths.downloads.appendingPathComponent(picked.asset.name)
        try await WineRuntimeService.download(asset: picked.asset, to: archive) { value in
            let percent = Int(value * 100)
            if percent % 25 == 0 {
                log("Downloading DXMT… \(percent)%")
            }
        }

        log("Extracting DXMT…")
        let destination = rootDirectory.appendingPathComponent(sanitize(tag), isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try await Shell.runChecked("/usr/bin/tar", ["-xf", archive.path, "-C", destination.path])
        _ = try? await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])
        try? FileManager.default.removeItem(at: archive)

        let info = try makeInfo(from: destination, tag: tag)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(info).write(to: infoFile, options: .atomic)
        log("DXMT \(tag) is ready ✓")
        return info
    }

    static func pickAsset(from release: GitHubRelease) -> GitHubRelease.Asset? {
        let archives = release.assets.filter { asset in
            let name = asset.name.lowercased()
            return name.hasSuffix(".tar.gz") || name.hasSuffix(".tar.xz") || name.hasSuffix(".zip")
        }
        return archives.first { $0.name.lowercased().contains("dxmt") } ?? archives.first
    }

    /// DXMT packages contain x86_64-windows (DLLs) and x86_64-unix (winemetal.so).
    static func makeInfo(from directory: URL, tag: String) throws -> DXMTInfo {
        let fm = FileManager.default
        guard
            let windows = findDirectory(named: "x86_64-windows", in: directory),
            fm.fileExists(atPath: windows.appendingPathComponent("d3d11.dll").path),
            let unix = findDirectory(named: "x86_64-unix", in: directory),
            fm.fileExists(atPath: unix.appendingPathComponent("winemetal.so").path)
        else {
            throw LauncherError.dxmtLayoutNotFound
        }
        return DXMTInfo(tag: tag, windowsPath: windows.path, unixPath: unix.path)
    }

    // MARK: - Using it

    /// A copy of Wine with DXMT placed in Wine's own library folders.
    public static func runtimeVariant(
        base: RuntimeInfo,
        dxmt: DXMTInfo,
        log: @Sendable (String) -> Void
    ) async throws -> RuntimeInfo {
        try await RuntimeVariant.make(
            base: base,
            suffix: "dxmt-\(sanitize(dxmt.tag))",
            label: "DXMT \(dxmt.tag)",
            log: log
        ) { wineLib in
            try RuntimeVariant.copyFiles(
                from: dxmt.windowsURL,
                to: wineLib.appendingPathComponent("x86_64-windows", isDirectory: true),
                extensions: ["dll"]
            )
            try RuntimeVariant.copyFiles(
                from: dxmt.unixURL,
                to: wineLib.appendingPathComponent("x86_64-unix", isDirectory: true),
                extensions: ["so"]
            )
        }
    }

    /// DXMT's DLLs also need to be inside the bottle's system32. Skips the copy if this version is already there.
    public static func install(_ info: DXMTInfo, into bottle: URL) throws {
        let marker = bottle.appendingPathComponent(bottleMarkerName)
        if let installedTag = try? String(contentsOf: marker, encoding: .utf8), installedTag == info.tag {
            return
        }
        let system32 = bottle.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        try RuntimeVariant.copyFiles(from: info.windowsURL, to: system32, extensions: ["dll"])
        try info.tag.write(to: marker, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "-")
    }

    private static func findDirectory(named name: String, in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return nil }

        while let url = enumerator.nextObject() as? URL {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory && url.lastPathComponent == name {
                return url
            }
        }
        return nil
    }
}
