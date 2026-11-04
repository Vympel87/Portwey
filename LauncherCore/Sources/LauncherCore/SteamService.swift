import Foundation

public struct SteamApp: Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let installDirectory: URL
    public let isFullyInstalled: Bool
}

/// The Windows version of Steam, running in its own bottle.
public enum SteamService {
    public static let bottleName = "steam"
    static let installerURL = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!
    
    /// Steam's UI is a Chromium browser that can't draw through DXVK/MoltenVK, which leaves a black window.
    /// These make the UI render on the CPU while games keep using DXVK.
    public static let clientArguments = ["-cef-disable-gpu", "-cef-disable-gpu-compositing", "-cef-disable-d3d11"]

    /// Steamworks Common Redistributables: installed by Steam itself, not a game.
    private static let ignoredAppIDs: Set<Int> = [228980]

    public static var bottleURL: URL {
        BottleManager.bottleURL(named: bottleName)
    }

    public static var steamDirectory: URL {
        bottleURL.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
    }

    public static var steamExecutable: URL {
        steamDirectory.appendingPathComponent("steam.exe")
    }

    public static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: steamExecutable.path)
    }

    // MARK: - Install & run

    /// Creates the Steam bottle and runs Valve's installer silently.
    public static func install(runtime: RuntimeInfo, log: @escaping @Sendable (String) -> Void) async throws {
        _ = try await BottleManager.ensureBottle(named: bottleName, runtime: runtime, log: log)

        log("Downloading the Steam installer…")
        try AppPaths.ensureDirectories()
        let installer = AppPaths.downloads.appendingPathComponent("SteamSetup.exe")
        let asset = GitHubRelease.Asset(name: "SteamSetup.exe", browserDownloadUrl: installerURL, size: -1)
        try await WineRuntimeService.download(asset: asset, to: installer) { _ in }

        log("Installing Steam (this can take a minute)…")
        _ = try await runAndWait(
            runtime.wineBinaryURL,
            [installer.path, "/S"],
            environment: ["WINEPREFIX": bottleURL.path, "WINEDEBUG": "-all"]
        )
        try? FileManager.default.removeItem(at: installer)

        guard isInstalled else {
            throw LauncherError.steamInstallFailed
        }
        log("Steam is installed ✓")
    }

    /// Opens the Steam window so people can sign in and install games.
    /// Uses DXVK when it's available, so games started from Steam's own window get it too.
    public static func openClient(runtime: RuntimeInfo, log: @escaping @Sendable (String) -> Void) async throws {
        guard isInstalled else { throw LauncherError.steamNotInstalled }

        var launchRuntime = runtime
        var environment: [String: String] = [:]
        if let dxvk = DXVKService.installed() {
            launchRuntime = try await DXVKService.runtimeVariant(base: runtime, dxvk: dxvk, log: log)
            environment = DXVKService.environment(for: bottleURL)
        }

        let process = Process()
        process.executableURL = launchRuntime.wineBinaryURL
        process.arguments = [steamExecutable.path] + clientArguments
        process.currentDirectoryURL = steamDirectory
        process.environment = BottleManager.environment(for: bottleURL, extra: environment)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// Closes Steam and everything it started.
    public static func stop(runtime: RuntimeInfo) async {
        await BottleManager.killAll(in: bottleURL, runtime: runtime)
    }

    // MARK: - Installed games

    /// Games installed through Steam, read from its library and app manifest files.
    public static func installedApps() -> [SteamApp] {
        var libraries: [URL] = [steamDirectory]

        // libraryfolders.vdf lists every Steam library folder ("C:\Program Files (x86)\Steam", other drives…).
        let libraryFile = steamDirectory.appendingPathComponent("steamapps/libraryfolders.vdf")
        if let text = try? String(contentsOf: libraryFile, encoding: .utf8),
           let folders = VDFParser.parse(text)?["libraryfolders"]?.objectValue {
            for (_, folder) in folders {
                if let path = folder["path"]?.stringValue,
                   let url = hostURL(forWindowsPath: path),
                   !libraries.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                    libraries.append(url)
                }
            }
        }

        var apps: [SteamApp] = []
        for library in libraries {
            let steamapps = library.appendingPathComponent("steamapps", isDirectory: true)
            let manifests = (try? FileManager.default.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []

            for manifest in manifests where manifest.lastPathComponent.hasPrefix("appmanifest_") && manifest.pathExtension == "acf" {
                guard
                    let text = try? String(contentsOf: manifest, encoding: .utf8),
                    let state = VDFParser.parse(text)?["AppState"],
                    let id = state["appid"]?.stringValue.flatMap(Int.init),
                    !ignoredAppIDs.contains(id),
                    let name = state["name"]?.stringValue,
                    let folder = state["installdir"]?.stringValue
                else { continue }

                // StateFlags bit 4 means "fully installed".
                let flags = state["StateFlags"]?.stringValue.flatMap(Int.init) ?? 0
                apps.append(SteamApp(
                    id: id,
                    name: name,
                    installDirectory: steamapps.appendingPathComponent("common/\(folder)", isDirectory: true),
                    isFullyInstalled: flags & 4 != 0
                ))
            }
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Steam's store artwork for a game, used as its cover.
    public static func coverImageData(for appID: Int) async -> Data? {
        let candidates = [
            "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/\(appID)/header.jpg",
            "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/header.jpg"
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if let (data, response) = try? await URLSession.shared.data(from: url),
               let http = response as? HTTPURLResponse,
               http.statusCode == 200,
               !data.isEmpty {
                return data
            }
        }
        return nil
    }

    // MARK: - Helpers

    /// "C:\Program Files (x86)\Steam" → <bottle>/drive_c/Program Files (x86)/Steam
    static func hostURL(forWindowsPath path: String) -> URL? {
        let characters = Array(path)
        guard characters.count >= 2, characters[1] == ":" else { return nil }

        let drive = String(characters[0]).lowercased()
        let rest = String(characters.dropFirst(2)).replacingOccurrences(of: "\\", with: "/")
        let driveFolder = bottleURL
            .appendingPathComponent("dosdevices/\(drive):", isDirectory: true)
            .resolvingSymlinksInPath()
        return URL(fileURLWithPath: driveFolder.path + rest, isDirectory: true)
    }

    /// Runs a process and waits for it, without capturing output (installers can leave helper processes running).
    private static func runAndWait(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String]
    ) async throws -> Int32 {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }.value
    }
}
