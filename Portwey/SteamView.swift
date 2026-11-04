import SwiftUI
import AppKit
import LauncherCore

struct SteamView: View {
    @Environment(SetupManager.self) private var setup
    @Environment(SteamManager.self) private var steam
    @Environment(GameLibrary.self) private var library
    @Environment(GameRunner.self) private var runner

    private var steamGames: [Game] {
        library.games.filter(\.isSteamGame)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Steam")
                        .font(.system(size: 34, weight: .bold))
                    Text("Run the Windows version of Steam for games that don't have a Mac version.")
                        .foregroundStyle(.secondary)
                }

                if steam.isInstalled {
                    controls
                    gamesSection
                } else {
                    installCard
                }

                statusArea

                tips
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Steam")
        .task {
            steam.refresh()
        }
    }

    // MARK: - Install

    private var installCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Steam isn't installed yet", systemImage: "arrow.down.circle")
                .font(.headline)
            Text("Portwey downloads Valve's official Steam installer and sets Steam up in its own Windows environment. You sign in and download games inside the Steam window, just like on Windows.")
                .foregroundStyle(.secondary)

            Button {
                Task {
                    if let runtime = setup.runtime {
                        await steam.install(runtime: runtime)
                    }
                }
            } label: {
                Label("Install Steam", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(steam.isWorking || setup.runtime == nil)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    if let runtime = setup.runtime {
                        await steam.openSteam(runtime: runtime)
                    }
                }
            } label: {
                Label("Open Steam", systemImage: "macwindow")
            }
            .buttonStyle(.borderedProminent)
            .disabled(setup.runtime == nil)
            .help("Sign in, browse your library and download games")

            Button {
                Task { await steam.syncGames() }
            } label: {
                Label("Sync Games", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(steam.isWorking)
            .help("Add games you installed in Steam to your Portwey library")

            Button {
                Task {
                    if let runtime = setup.runtime {
                        await steam.stopSteam(runtime: runtime)
                    }
                }
            } label: {
                Label("Close Steam", systemImage: "xmark.circle")
            }
            .disabled(setup.runtime == nil)

            Spacer()

            Button {
                NSWorkspace.shared.open(SteamService.steamDirectory)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Show Steam's folder in Finder")
        }
        .controlSize(.large)
    }

    // MARK: - Games

    private var gamesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Steam games in your library")
                .font(.title3.bold())

            if steamGames.isEmpty {
                Text("None yet. Open Steam, sign in and install a game, then press Sync Games.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(steamGames) { game in
                    HStack(spacing: 12) {
                        GameCoverView(game: game, iconSize: 14)
                            .frame(width: 92, height: 43)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(game.title)
                                .font(.headline)
                            Text("App \(game.steamAppID.map(String.init) ?? "?") · \(game.engine?.displayName ?? "Unknown engine")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if runner.isRunning(game.id) {
                            Text("Running")
                                .foregroundStyle(.blue)
                        } else {
                            Button("Play") {
                                playGame(game, runner: runner, setup: setup)
                            }
                            .disabled(runner.isBusy)
                        }
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Status & tips

    @ViewBuilder
    private var statusArea: some View {
        if steam.isWorking {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(steam.status ?? "Working…")
                    .foregroundStyle(.secondary)
            }
        } else if let status = steam.status {
            Label(status, systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }

        if let error = steam.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var tips: some View {
        GroupBox("Good to know") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Experimental: with the standard Wine, Steam's window can stay black because its new interface needs patches that only CrossOver-based Wine builds have. Support improves once a compatible Wine is installed on the Runtimes page.", systemImage: "flask")
                    .foregroundStyle(.orange)
                Label("You sign in inside Steam's own window. Portwey never sees your password.", systemImage: "lock.shield")
                Label("Games with anti-cheat (EasyAntiCheat, BattlEye and similar) usually don't run.", systemImage: "exclamationmark.shield")
                Label("If Steam's window stays black the first time, close Steam and open it again; it often updates itself first.", systemImage: "arrow.clockwise")
                Label("Playtime for Steam games is tracked by Steam itself.", systemImage: "clock")
                Label("If a game has a Mac version, Steam for Mac runs it better.", systemImage: "apple.logo")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
