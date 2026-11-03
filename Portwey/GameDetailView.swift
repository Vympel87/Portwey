import SwiftUI
import AppKit
import LauncherCore

enum DetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case settings = "Settings"
    case logs = "Logs"

    var id: String { rawValue }
}

struct GameDetailView: View {
    let gameID: UUID

    @Environment(GameLibrary.self) private var library
    @Environment(GameRunner.self) private var runner
    @Environment(SetupManager.self) private var setup
    @Environment(\.dismiss) private var dismiss

    @State private var tab: DetailTab = .overview
    @State private var isConfirmingRemoval = false

    private var game: Game? {
        library.games.first { $0.id == gameID }
    }

    var body: some View {
        if let game {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero(for: game)

                    Picker("", selection: $tab) {
                        ForEach(DetailTab.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 320)

                    switch tab {
                    case .overview:
                        overview(for: game)
                    case .settings:
                        GameSettingsView(game: game)
                            .id(game.id)
                    case .logs:
                        LogPanel(lines: runner.logs)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(game.title)
            .confirmationDialog(
                "Remove \(game.title) from your library?",
                isPresented: $isConfirmingRemoval
            ) {
                Button("Remove", role: .destructive) {
                    library.remove(game)
                    dismiss()
                }
            } message: {
                Text("The game files stay on your Mac.")
            }
        } else {
            ContentUnavailableView("Game not found", systemImage: "questionmark.square.dashed")
        }
    }

    // MARK: - Hero

    private func hero(for game: Game) -> some View {
        let status = GameStatus(game: game, runner: runner)

        return ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: game.coverColors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 140))
                .foregroundStyle(.white.opacity(0.12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 40)

            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 12) {
                Text(game.title)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 8, height: 8)
                    Text("\(status.label) · \(game.graphicsBackend.shortName)")
                        .foregroundStyle(.white.opacity(0.85))
                }
                .font(.callout)

                HStack(spacing: 12) {
                    primaryButton(for: game)
                    moreMenu(for: game)
                }

                if let error = runner.lastError, runner.activeGameID == nil {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.red.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                        .lineLimit(3)
                }
            }
            .padding(28)
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func primaryButton(for game: Game) -> some View {
        if runner.isRunning(game.id) {
            Button(role: .destructive) {
                Task { await runner.stop() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.extraLarge)
        } else if runner.isPreparing(game.id) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Preparing…")
                    .foregroundStyle(.white)
            }
            .frame(minWidth: 130, minHeight: 36)
        } else {
            Button {
                playGame(game, runner: runner, setup: setup)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .disabled(runner.isBusy || !game.executableExists || setup.runtime == nil)
        }
    }

    private func moreMenu(for game: Game) -> some View {
        Menu {
            Button("Show Game in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([game.executableURL])
            }
            Button("Open C: Drive") {
                let driveC = BottleManager.bottleURL(named: game.bottleName)
                    .appendingPathComponent("drive_c", isDirectory: true)
                NSWorkspace.shared.open(driveC)
            }
            Divider()
            Button("Remove from Library…", role: .destructive) {
                isConfirmingRemoval = true
            }
            .disabled(runner.activeGameID == game.id)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(10)
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Overview

    private func overview(for game: Game) -> some View {
        let rows: [(String, String)] = [
            ("Playtime", game.playtimeText),
            ("Last played", game.lastPlayedText),
            ("Added", game.addedAt.formatted(date: .abbreviated, time: .omitted)),
            ("Graphics", game.graphicsBackend.displayName),
            ("Bottle", game.bottleName),
            ("Executable", game.executablePath)
        ]

        return Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Text(row.1)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
}
