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
        case ready
        case failed(message: String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var logs: [String] = []
    public private(set) var runtime: RuntimeInfo?

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
    }

    public func start() async {
        guard !isBusy else { return }
        logs.removeAll()

        do {
            try AppPaths.ensureDirectories()
            log("Data folder: \(AppPaths.root.path)")

            phase = .checkingRosetta
            if await RosettaService.isInstalled() {
                log("Rosetta 2 is installed ✓")
            } else {
                log("Rosetta 2 not found, requesting permission to install…")
                phase = .installingRosetta
                try await RosettaService.install()
                log("Rosetta 2 installed successfully ✓")
            }

            if let existing = WineRuntimeService.installedRuntime() {
                runtime = existing
                log("Wine is already installed: \(existing.version) ✓")
            } else {
                runtime = try await installWine()
            }

            phase = .ready
            log("Setup complete, ready to play 🎮")
        } catch {
            phase = .failed(message: error.localizedDescription)
            log("❌ \(error.localizedDescription)")
        }
    }

    private func installWine() async throws -> RuntimeInfo {
        phase = .fetchingRelease
        log("Checking GitHub for the latest Wine release…")
        let release = try await WineRuntimeService.fetchLatestRelease()
        let asset = try WineRuntimeService.pickAsset(from: release)
        let size = ByteCountFormatter.string(fromByteCount: Int64(asset.size), countStyle: .file)
        log("Release \(release.tagName), file \(asset.name) (\(size))")

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

    private func log(_ message: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        let line = "[\(time)] \(message)"
        logs.append(line)
        print(line)
    }
}
