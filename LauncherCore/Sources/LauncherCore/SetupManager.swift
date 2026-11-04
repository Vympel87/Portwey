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

    /// Progress of installing an extra Wine version from the Runtimes page.
    public enum RuntimeTask: Equatable {
        case downloading(name: String, progress: Double)
        case extracting(name: String)
        case verifying(name: String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var logs: [String] = []
    public private(set) var runtime: RuntimeInfo?
    public private(set) var dxvk: DXVKInfo?

    public private(set) var installedRuntimes: [RuntimeInfo] = []
    public private(set) var availableReleases: [WineRelease] = []
    public private(set) var isLoadingReleases = false
    public private(set) var runtimeTask: RuntimeTask?
    public private(set) var runtimeError: String?

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
        installedRuntimes = WineRuntimeService.installedRuntimes()
    }

    // MARK: - First-run setup

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
            refreshRuntimes()

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

    // MARK: - Wine versions (Runtimes page)

    public func refreshRuntimes() {
        installedRuntimes = WineRuntimeService.installedRuntimes()
    }

    public func loadAvailableReleases() async {
        isLoadingReleases = true
        runtimeError = nil
        defer { isLoadingReleases = false }
        do {
            availableReleases = try await WineRuntimeService.availableReleases()
        } catch {
            runtimeError = error.localizedDescription
        }
    }

    public func installRuntime(_ release: WineRelease) async {
        guard runtimeTask == nil else { return }
        runtimeError = nil
        let name = release.displayName
        runtimeTask = .downloading(name: name, progress: 0)

        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Installing \(name)"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }

        do {
            _ = try await WineRuntimeService.install(
                release,
                progress: { [weak self] value in
                    Task { @MainActor in
                        guard let self, case .downloading = self.runtimeTask else { return }
                        self.runtimeTask = .downloading(name: name, progress: value)
                    }
                },
                stage: { [weak self] stage in
                    Task { @MainActor in
                        guard let self else { return }
                        switch stage {
                        case .downloading: break
                        case .extracting: self.runtimeTask = .extracting(name: name)
                        case .verifying: self.runtimeTask = .verifying(name: name)
                        }
                    }
                }
            )
            refreshRuntimes()
        } catch {
            runtimeError = error.localizedDescription
        }
        runtimeTask = nil
    }

    public func makeDefault(_ info: RuntimeInfo) {
        do {
            try WineRuntimeService.save(info)
            runtime = info
        } catch {
            runtimeError = error.localizedDescription
        }
    }

    public func uninstallRuntime(_ info: RuntimeInfo) {
        guard info.installPath != runtime?.installPath else { return }
        do {
            try WineRuntimeService.uninstall(info)
            refreshRuntimes()
        } catch {
            runtimeError = error.localizedDescription
        }
    }

    // MARK: - Installing during setup

    private func installWine() async throws -> RuntimeInfo {
        phase = .fetchingRelease
        log("Checking GitHub for the latest Wine release…")
        let latest = try await WineRuntimeService.fetchLatestRelease()
        let release = WineRelease(tag: latest.tagName, asset: try WineRuntimeService.pickAsset(from: latest))
        log("\(release.displayName) (\(release.sizeText))")

        phase = .downloadingWine(progress: 0)
        let info = try await WineRuntimeService.install(
            release,
            progress: { [weak self] value in
                Task { @MainActor in
                    guard let self, case .downloadingWine = self.phase else { return }
                    self.phase = .downloadingWine(progress: value)
                }
            },
            stage: { [weak self] stage in
                Task { @MainActor in
                    guard let self else { return }
                    switch stage {
                    case .downloading: break
                    case .extracting:
                        self.phase = .extractingWine
                        self.log("Extracting Wine…")
                    case .verifying:
                        self.phase = .verifyingWine
                        self.log("Test-running Wine through Rosetta…")
                    }
                }
            }
        )

        try WineRuntimeService.save(info)
        log("Wine is working: \(info.version) ✓")
        return info
    }

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
