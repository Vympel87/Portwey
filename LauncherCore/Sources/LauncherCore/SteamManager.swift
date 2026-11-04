import Foundation
import Observation

/// State for the Steam page: installing, opening, closing and syncing.
@MainActor
@Observable
public final class SteamManager {
    public private(set) var isInstalled = SteamService.isInstalled
    public private(set) var isWorking = false
    public private(set) var status: String?
    public private(set) var errorMessage: String?

    private let library: GameLibrary

    public init(library: GameLibrary) {
        self.library = library
    }

    public func refresh() {
        isInstalled = SteamService.isInstalled
    }

    public func install(runtime: RuntimeInfo) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Installing Steam"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }

        do {
            try await SteamService.install(runtime: runtime) { [weak self] line in
                Task { @MainActor in self?.status = line }
            }
            refresh()
            status = "Steam is installed. Open it to sign in and download games."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func openSteam(runtime: RuntimeInfo) async {
        errorMessage = nil
        status = "Opening Steam…"
        do {
            try await SteamService.openClient(runtime: runtime) { [weak self] line in
                Task { @MainActor in self?.status = line }
            }
            status = "Steam is opening. Sign in, install games, then press Sync Games."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func stopSteam(runtime: RuntimeInfo) async {
        await SteamService.stop(runtime: runtime)
        status = "Steam was closed."
    }

    public func syncGames() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        status = "Looking for installed Steam games…"
        defer { isWorking = false }

        let result = await library.syncSteamGames()
        switch (result.added, result.removed) {
        case (0, 0):
            status = "Your Steam games are up to date."
        default:
            status = "Added \(result.added) and removed \(result.removed) Steam game(s)."
        }
    }
}
