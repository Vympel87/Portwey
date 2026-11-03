import SwiftUI
import LauncherCore

struct GameSettingsView: View {
    @Environment(GameLibrary.self) private var library
    @Environment(GameRunner.self) private var runner

    let gameID: UUID
    let engine: GameEngine?

    @State private var title: String
    @State private var launchMethod: LaunchMethod
    @State private var backend: GraphicsBackend
    @State private var useOwnBottle: Bool
    @State private var argumentsText: String
    @State private var envRows: [EnvRow]

    init(game: Game) {
        gameID = game.id
        engine = game.engine
        _title = State(initialValue: game.title)
        _launchMethod = State(initialValue: game.launchMethod)
        _backend = State(initialValue: game.graphicsBackend)
        _useOwnBottle = State(initialValue: game.bottleName != BottleManager.defaultBottleName)
        _argumentsText = State(initialValue: ArgumentsFormatter.join(game.arguments))
        _envRows = State(initialValue: game.environment
            .sorted { $0.key < $1.key }
            .map { EnvRow(key: $0.key, value: $0.value) })
    }

    private var isLocked: Bool {
        runner.activeGameID == gameID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLocked {
                Label("Settings are locked while the game is running.", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }

            GroupBox("General") {
                LabeledContent("Title") {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                }
                .padding(8)
            }

            if engine?.supportsNativeNWJS == true {
                GroupBox("Runs with") {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Runner", selection: $launchMethod) {
                            ForEach(LaunchMethod.allCases) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        .frame(maxWidth: 420)

                        Text("\(engine?.displayName ?? "This game") runs natively on macOS through NW.js: no Wine, no Rosetta and better performance. Switch to Wine only if the native version has problems.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if launchMethod == .wine {
                GroupBox("Windows environment") {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Bottle", selection: $useOwnBottle) {
                            Text("Shared with other games").tag(false)
                            Text("Own bottle for this game").tag(true)
                        }
                        .frame(maxWidth: 420)

                        Text("An own bottle keeps this game's settings and Windows components separate, so problems can't affect other games. It uses more disk space. Saves stored inside the previous bottle don't move over.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox("Graphics") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Backend", selection: $backend) {
                        ForEach(GraphicsBackend.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .frame(maxWidth: 420)
                    .disabled(launchMethod == .nwjs)

                    Text(launchMethod == .nwjs
                         ? "Not used: native games render with Metal directly."
                         : "DXVK works best for DirectX 10/11 games (most Unity games). Use WineD3D for older DirectX 9 or OpenGL games.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Launch arguments") {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Arguments", text: $argumentsText, prompt: Text("-screen-fullscreen 0"))
                        .textFieldStyle(.roundedBorder)
                    Text("Passed to the game when it starts. Wrap values that contain spaces in quotes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox("Environment variables") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($envRows) { $row in
                        HStack {
                            TextField("NAME", text: $row.key)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 220)
                            Text("=")
                                .foregroundStyle(.secondary)
                            TextField("value", text: $row.value)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Button {
                                envRows.removeAll { $0.id == row.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        envRows.append(EnvRow(key: "", value: ""))
                    } label: {
                        Label("Add variable", systemImage: "plus")
                    }

                    Text("Example: DXVK_HUD = fps shows an FPS counter in DXVK games.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .disabled(isLocked)
        .onChange(of: title) { save() }
        .onChange(of: launchMethod) { save() }
        .onChange(of: backend) { save() }
        .onChange(of: useOwnBottle) { save() }
        .onChange(of: argumentsText) { save() }
        .onChange(of: envRows) { save() }
    }

    /// Applies only the editable fields to the latest copy of the game,
    /// so playtime and last-played info are never overwritten.
    private func save() {
        guard var game = library.games.first(where: { $0.id == gameID }) else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            game.title = trimmedTitle
        }
        game.launchMethod = launchMethod
        game.graphicsBackend = backend
        game.bottleName = useOwnBottle
            ? BottleManager.ownBottleName(for: gameID)
            : BottleManager.defaultBottleName
        game.arguments = ArgumentsFormatter.split(argumentsText)

        var environment: [String: String] = [:]
        for row in envRows {
            let key = row.key.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                environment[key] = row.value
            }
        }
        game.environment = environment

        library.update(game)
    }
}

struct EnvRow: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
}

enum ArgumentsFormatter {
    /// Splits a command line into arguments, keeping "quoted values" together.
    static func split(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var hasToken = false

        for character in text {
            if character == "\"" {
                inQuotes.toggle()
                hasToken = true
            } else if character.isWhitespace && !inQuotes {
                if hasToken {
                    result.append(current)
                    current = ""
                    hasToken = false
                }
            } else {
                current.append(character)
                hasToken = true
            }
        }
        if hasToken {
            result.append(current)
        }
        return result
    }

    static func join(_ arguments: [String]) -> String {
        arguments
            .map { $0.isEmpty || $0.contains(" ") ? "\"\($0)\"" : $0 }
            .joined(separator: " ")
    }
}
