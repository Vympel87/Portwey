import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LauncherCore

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All games"
    case steam = "Steam"
    case added = "Added games"
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
    @State private var isImportBusy = false
    @State private var isDropTargeted = false
    @State private var executableChoice: ExecutableChoice?
    @State private var importError: String?

    private let exeType = UTType(filenameExtension: "exe") ?? .item
    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 20)]

    private var visibleGames: [Game] {
        var games = library.games
        switch filter {
        case .all:
            break
        case .steam:
            games = games.filter(\.isSteamGame)
        case .added:
            games = games.filter { !$0.isSteamGame }
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
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            Label("Drop to add game", systemImage: "plus.circle.fill")
                                .font(.title2.bold())
                                .foregroundStyle(.tint)
                        }
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if isImportBusy {
                    ProgressView("Importing…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                importItem(url)
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
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
                    .disabled(isImportBusy)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                GameDetailView(gameID: id)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [exeType, .folder, .zip],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                importItem(url)
            }
        }
        .sheet(item: $executableChoice) { choice in
            ExecutableChoiceSheet(choice: choice) { exe in
                addGame(exe)
            }
        }
        .alert(
            "Couldn't add game",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Importing

    /// Accepts an .exe, a game folder, or a .zip.
    private func importItem(_ url: URL) {
        Task {
            isImportBusy = true
            defer { isImportBusy = false }

            do {
                let fileExtension = url.pathExtension.lowercased()
                if fileExtension == "exe" {
                    addGame(url)
                    return
                }

                var folder = url
                if fileExtension == "zip" {
                    folder = try await GameImporter.extractZip(url)
                }

                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    importError = "Portwey can add a game's .exe, its folder, or a .zip file."
                    return
                }

                let candidates = GameImporter.findExecutables(in: folder)
                switch candidates.count {
                case 0:
                    importError = "No Windows .exe was found in “\(folder.lastPathComponent)”."
                case 1:
                    addGame(candidates[0])
                default:
                    executableChoice = ExecutableChoice(folder: folder, candidates: candidates)
                }
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func addGame(_ executable: URL) {
        let game = library.addGame(executable: executable)
        path = [game.id]
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
            Text("Add a game's .exe, folder or .zip, or just drag it here.")
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
