import Foundation
import Observation

@MainActor
@Observable
public final class SetupManager {
    public enum Phase: Equatable {
        case idle
        case checkingRosetta
        case installingRosetta
        case fetchingRelease
        case downloadingWine(progress: Double)
        case extractingWine
        case verifyingWine
        case fetchingDXVK
        case downloadingDXVK(progress: Double)
        case extractingDXVK
        case ready
        case failed(message: String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var logs: [String] = []
    public private(set) var runtime: RuntimeInfo?
    public private(set) var dxvk: DXVKInfo?

    public var isReady: Bool { phase == .ready }

    public var isBusy: Bool {
        switch phase {
        case .idle, .ready, .failed:
            return false
        default:
            return true
        }
    }

    public init() {
        runtime = WineRuntimeService.installedRuntime()
        dxvk = DXVKService.installed()
    }

    public func start() async {
        guard !isBusy else { return }
        logs.removeAll()

        // Keep macOS from throttling the app (App Nap) or idle-sleeping while we download and set up.
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Setting up Wine and DXVK"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }

        do {
            try AppPaths.ensureDirectories()
            log("Data folder: \(AppPaths.root.path)")

            // 1. Rosetta
            phase = .checkingRosetta
            if await RosettaService.isInstalled() {
                log("Rosetta 2 is installed ✓")
            } else {
                log("Rosetta 2 not found, requesting permission to install…")
                phase = .installingRosetta
                try await RosettaService.install()
                log("Rosetta 2 installed successfully ✓")
            }

            // 2. Wine
            if let existing = WineRuntimeService.installedRuntime() {
                runtime = existing
                log("Wine is already installed: \(existing.version) ✓")
            } else {
                runtime = try await installWine()
            }

            // 3. DXVK (optional: games fall back to WineD3D if this fails)
            if let existing = DXVKService.installed() {
                dxvk = existing
                log("DXVK is already installed: \(existing.tag) ✓")
            } else {
                do {
                    dxvk = try await installDXVK()
                } catch {
                    log("⚠️ Couldn't install DXVK, DirectX 11 games may not run: \(error.localizedDescription)")
                }
            }

            phase = .ready
            log("Setup complete, ready to play 🎮")
        } catch {
            phase = .failed(message: error.localizedDescription)
            log("❌ \(error.localizedDescription)")
        }
    }

    // MARK: - Wine

    private func installWine() async throws -> RuntimeInfo {
        phase = .fetchingRelease
        log("Checking GitHub for the latest Wine release…")
        let release = try await WineRuntimeService.fetchLatestRelease()
        let asset = try WineRuntimeService.pickAsset(from: release)
        log("Release \(release.tagName), file \(asset.name) (\(formattedSize(asset.size)))")

        phase = .downloadingWine(progress: 0)
        let archive = AppPaths.downloads.appendingPathComponent(asset.name)
        try await WineRuntimeService.download(asset: asset, to: archive) { [weak self] value in
            Task { @MainActor in
                guard let self, case .downloadingWine = self.phase else { return }
                self.phase = .downloadingWine(progress: value)
            }
        }
        log("Download complete ✓")

        phase = .extractingWine
        log("Extracting Wine…")
        let installDir = try await WineRuntimeService.extract(archive: archive, tag: release.tagName)
        try? FileManager.default.removeItem(at: archive)

        guard let wineBinary = WineRuntimeService.findWineBinary(in: installDir) else {
            throw LauncherError.wineBinaryNotFound
        }
        log("Wine binary: \(wineBinary.path)")

        phase = .verifyingWine
        log("Test-running Wine through Rosetta…")
        let version = try await WineRuntimeService.wineVersion(binary: wineBinary)
        log("Wine is working: \(version) ✓")

        let info = RuntimeInfo(
            tag: release.tagName,
            version: version,
            installPath: installDir.path,
            wineBinaryPath: wineBinary.path
        )
        try WineRuntimeService.save(info)
        return info
    }

    // MARK: - DXVK

    private func installDXVK() async throws -> DXVKInfo {
        phase = .fetchingDXVK
        log("Checking GitHub for DXVK-macOS releases…")
        let releases = try await GitHubClient.releases(owner: DXVKService.owner, repo: DXVKService.repo)

        // Pick the newest release that actually has a usable DXVK package.
        var picked: (release: GitHubRelease, asset: GitHubRelease.Asset)?
        for release in releases {
            if let asset = try? DXVKService.pickAsset(from: release) {
                picked = (release, asset)
                break
            }
        }
        guard let picked else {
            throw LauncherError.noDXVKAssetFound
        }
        let release = picked.release
        let asset = picked.asset
        log("DXVK release \(release.tagName), file \(asset.name) (\(formattedSize(asset.size)))")

        phase = .downloadingDXVK(progress: 0)
        let archive = AppPaths.downloads.appendingPathComponent(asset.name)
        try await WineRuntimeService.download(asset: asset, to: archive) { [weak self] value in
            Task { @MainActor in
                guard let self, case .downloadingDXVK = self.phase else { return }
                self.phase = .downloadingDXVK(progress: value)
            }
        }

        phase = .extractingDXVK
        log("Extracting DXVK…")
        let info = try await DXVKService.extract(archive: archive, tag: release.tagName)
        try? FileManager.default.removeItem(at: archive)
        try DXVKService.save(info)
        log("DXVK \(info.tag) is ready ✓ (\(info.dllNames.joined(separator: ", ")))")
        return info
    }

    // MARK: - Helpers

    private func formattedSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func log(_ message: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        let line = "[\(time)] \(message)"
        logs.append(line)
        print(line)
    }
}
