import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LauncherCore

struct LibraryView: View {
    @Environment(GameLibrary.self) private var library
    @Environment(GameRunner.self) private var runner
    @Environment(SetupManager.self) private var setup

    @State private var selectedID: UUID?
    @State private var searchText = ""
    @State private var isImporting = false
    @State private var showLogs = false

    private let exeType = UTType(filenameExtension: "exe") ?? .item
    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 20)]

    private var filteredGames: [Game] {
        guard !searchText.isEmpty else { return library.games }
        return library.games.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var selectedGame: Game? {
        library.games.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if library.games.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(filteredGames) { game in
                            GameCard(game: game, status: status(for: game), isSelected: game.id == selectedID)
                                .onTapGesture(count: 2) {
                                    selectedID = game.id
                                    launch(game)
                                }
                                .onTapGesture {
                                    selectedID = game.id
                                }
                                .contextMenu { contextMenu(for: game) }
                        }
                    }
                    .padding(4)
                }
            }

            if let game = selectedGame {
                playBar(for: game)
            }

            if showLogs {
                LogPanel(lines: runner.logs)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [exeType], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                let game = library.addGame(executable: url)
                selectedID = game.id
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your games")
                    .font(.system(size: 34, weight: .bold))
                Text("Play your Windows games on Apple Silicon")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search games", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(width: 220)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

                Button {
                    isImporting = true
                } label: {
                    Label("Add game", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No games yet")
                .font(.title2.bold())
            Text("Add a Windows .exe to get started.")
                .foregroundStyle(.secondary)
            Button {
                isImporting = true
            } label: {
                Label("Add game", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Play bar

    private func playBar(for game: Game) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
                    .font(.title3.bold())
                Text(subtitle(for: game))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let error = runner.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button {
                showLogs.toggle()
            } label: {
                Label(showLogs ? "Hide Logs" : "Logs", systemImage: "text.alignleft")
            }
            .controlSize(.large)

            primaryButton(for: game)
        }
        .padding(20)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func primaryButton(for game: Game) -> some View {
        if runner.isRunning(game.id) {
            Button(role: .destructive) {
                Task { await runner.stop() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .frame(minWidth: 90)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
        } else if runner.isPreparing(game.id) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Preparing…")
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 120)
        } else {
            Button {
                launch(game)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .frame(minWidth: 90)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(runner.isBusy || !game.executableExists)
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for game: Game) -> some View {
        Button("Play") {
            selectedID = game.id
            launch(game)
        }
        .disabled(runner.isBusy)

        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([game.executableURL])
        }

        Divider()

        Button("Remove from Library", role: .destructive) {
            if selectedID == game.id { selectedID = nil }
            library.remove(game)
        }
        .disabled(runner.isRunning(game.id) || runner.isPreparing(game.id))
    }

    // MARK: - Helpers

    private func launch(_ game: Game) {
        guard let runtime = setup.runtime, !runner.isBusy else { return }
        Task { await runner.launch(game, runtime: runtime) }
    }

    private func status(for game: Game) -> GameStatus {
        if runner.isRunning(game.id) { return .running }
        if runner.isPreparing(game.id) { return .preparing }
        if !game.executableExists { return .missing }
        return .ready
    }

    private func subtitle(for game: Game) -> String {
        let playtime = Duration.seconds(game.playtimeSeconds)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        if let lastPlayed = game.lastPlayedAt {
            return "Played \(playtime) · Last played \(lastPlayed.formatted(.relative(presentation: .named)))"
        }
        return "Never played"
    }
}

// MARK: - Game status

private enum GameStatus {
    case ready, preparing, running, missing

    var label: String {
        switch self {
        case .ready: return "Ready to play"
        case .preparing: return "Preparing…"
        case .running: return "Running"
        case .missing: return "File missing"
        }
    }

    var color: Color {
        switch self {
        case .ready: return .green
        case .preparing: return .orange
        case .running: return .blue
        case .missing: return .red
        }
    }
}

// MARK: - Game card

private struct GameCard: View {
    let game: Game
    let status: GameStatus
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(colors: coverColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(height: 130)

            VStack(alignment: .leading, spacing: 10) {
                Text(game.title)
                    .font(.headline)
                    .lineLimit(2, reservesSpace: true)

                HStack(spacing: 6) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 7, height: 7)
                    Text(status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Placeholder cover with a stable color per title (real cover art comes later).
    private var coverColors: [Color] {
        let seed = game.title.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let hue = Double(seed % 360) / 360
        return [
            Color(hue: hue, saturation: 0.6, brightness: 0.55),
            Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.35)
        ]
    }
}
