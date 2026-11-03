import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LauncherCore

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All games"
    case recent = "Recently played"
    case notPlayed = "Not played yet"

    var id: String { rawValue }
}

struct LibraryView: View {
    @Environment(GameLibrary.self) private var library
    @Environment(GameRunner.self) private var runner
    @Environment(SetupManager.self) private var setup

    @State private var path: [UUID] = []
    @State private var searchText = ""
    @State private var filter: LibraryFilter = .all
    @State private var isImporting = false

    private let exeType = UTType(filenameExtension: "exe") ?? .item
    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 20)]

    private var visibleGames: [Game] {
        var games = library.games
        switch filter {
        case .all:
            break
        case .recent:
            games = games
                .filter { $0.lastPlayedAt != nil }
                .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        case .notPlayed:
            games = games.filter { $0.lastPlayedAt == nil }
        }
        if !searchText.isEmpty {
            games = games.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        return games
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    filterBar

                    if library.games.isEmpty {
                        emptyState
                    } else if visibleGames.isEmpty {
                        noResults
                    } else {
                        grid
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search games")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isImporting = true
                    } label: {
                        Label("Add game", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                GameDetailView(gameID: id)
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [exeType], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                let game = library.addGame(executable: url)
                path = [game.id]
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your games")
                .font(.system(size: 34, weight: .bold))
            Text(library.games.count == 1 ? "1 game in your library" : "\(library.games.count) games in your library")
                .foregroundStyle(.secondary)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(LibraryFilter.allCases) { item in
                Button {
                    filter = item
                } label: {
                    Text(item.rawValue)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            filter == item ? Color.accentColor : Color.secondary.opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(filter == item ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            ForEach(visibleGames) { game in
                GameCard(
                    game: game,
                    status: GameStatus(game: game, runner: runner),
                    canPlay: !runner.isBusy && game.executableExists && setup.runtime != nil,
                    onPlay: { playGame(game, runner: runner, setup: setup) }
                ) {
                    GameMenuItems(game: game, onOpenDetails: { path.append(game.id) })
                }
                .onTapGesture {
                    path.append(game.id)
                }
                .contextMenu {
                    GameMenuItems(game: game, onOpenDetails: { path.append(game.id) })
                }
            }
        }
    }

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
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No games match")
                .font(.title3.bold())
            Text("Try another search or filter.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}
