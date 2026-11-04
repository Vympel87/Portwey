import SwiftUI
import AppKit
import LauncherCore

struct GameSettingsView: View {
    @Environment(GameLibrary.self) private var library
    @Environment(GameRunner.self) private var runner

    let gameID: UUID
    let engine: GameEngine?
    /// Why this game can't use its native runner, if that's the case.
    let nativeIssue: String?

    @State private var title: String
    @State private var launchMethod: LaunchMethod
    @State private var backend: GraphicsBackend
    @State private var useOwnBottle: Bool
    @State private var argumentsText: String
    @State private var envRows: [EnvRow]
    @State private var editingPreset: GamePreset?

    init(game: Game) {
        gameID = game.id
        engine = game.engine
        nativeIssue = game.engine?.nativeLaunchMethod == .godot
            ? GodotService.nativeSupport(for: game.executableURL).reason
            : nil
        _title = State(initialValue: game.title)
        _launchMethod = State(initialValue: game.launchMethod)
        _backend = State(initialValue: game.graphicsBackend)
        _useOwnBottle = State(initialValue: game.bottleName != BottleManager.defaultBottleName)
        _argumentsText = State(initialValue: ArgumentsFormatter.join(game.arguments))
        _envRows = State(initialValue: Self.rows(from: game.environment))
    }

    private var game: Game? {
        library.games.first { $0.id == gameID }
    }

    private var isLocked: Bool {
        runner.activeGameID == gameID
    }

    /// Wine, plus this engine's native runner if it has one.
    private var launchOptions: [LaunchMethod] {
        [.wine] + [engine?.nativeLaunchMethod].compactMap { $0 }
    }

    private var nativeDescription: String {
        switch engine?.nativeLaunchMethod {
        case .nwjs:
            return "\(engine?.displayName ?? "This game") runs natively on macOS through NW.js: no Wine, no Rosetta and better performance."
        case .godot:
            return "Runs on the macOS build of the same Godot version the game was made with: no Wine, no Rosetta. Saves are kept separately from the Wine version."
        default:
            return ""
        }
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

            presetSection

            if engine?.nativeLaunchMethod != nil {
                GroupBox("Runs with") {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Runner", selection: $launchMethod) {
                            ForEach(launchOptions) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        .frame(maxWidth: 420)

                        Text(nativeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let nativeIssue {
                            Label(nativeIssue, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
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
                    .disabled(launchMethod.isNative)

                    Text(launchMethod.isNative
                         ? "Not used: native games render with Metal directly."
                         : "DXVK works best for DirectX 10/11 games (most Unity games). DXMT needs a CrossOver-based Wine. Use WineD3D for older DirectX 9 or OpenGL games.")
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
        .sheet(item: $editingPreset) { preset in
            PresetEditorSheet(preset: preset, isNew: !library.isMyPreset(preset)) { saved in
                library.saveMyPreset(saved, appliedTo: gameID)
            }
        }
    }

    // MARK: - Preset

    private var presetSection: some View {
        GroupBox("Preset") {
            VStack(alignment: .leading, spacing: 10) {
                if let game, let preset = library.preset(for: game) {
                    HStack(spacing: 8) {
                        if let status = preset.status {
                            PresetStatusBadge(status: status)
                        }
                        Text(preset.title)
                            .font(.headline)
                        PresetSourceBadge(isMine: library.isMyPreset(preset))
                        Spacer()
                        if game.presetID == preset.id {
                            Label("Applied", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Apply Preset") {
                                apply(preset)
                            }
                        }
                    }
                    Text(preset.settingsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let notes = preset.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                    }
                } else {
                    Text("No preset matches this game yet.")
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack(spacing: 10) {
                    Button {
                        openPresetEditor()
                    } label: {
                        Label("Save as My Preset…", systemImage: "square.and.arrow.down")
                    }

                    if let game,
                       let preset = library.preset(for: game),
                       library.isMyPreset(preset),
                       let url = PresetService.shareURL(for: preset) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Share…", systemImage: "square.and.arrow.up")
                        }
                        .help("Open a pre-filled GitHub issue so the preset can be added for everyone")
                    }
                }

                Text("Found settings that work? Save them as your own preset, then share it so other players get them automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Starts from your existing preset for this game (with fresh settings), or a brand-new one.
    private func openPresetEditor() {
        guard let game else { return }
        let fresh = PresetService.makePreset(from: game)

        if let existing = library.preset(for: game), library.isMyPreset(existing) {
            var updated = existing
            updated.settings = fresh.settings
            editingPreset = updated
        } else {
            editingPreset = fresh
        }
    }

    private func apply(_ preset: GamePreset) {
        library.applyPreset(preset, to: gameID)
        // Reflect the new settings in the fields below.
        guard let updated = game else { return }
        launchMethod = updated.launchMethod
        backend = updated.graphicsBackend
        useOwnBottle = updated.bottleName != BottleManager.defaultBottleName
        argumentsText = ArgumentsFormatter.join(updated.arguments)
        envRows = Self.rows(from: updated.environment)
    }

    // MARK: - Saving

    /// Applies only the editable fields to the latest copy of the game,
    /// so playtime, last-played info and the applied preset are never overwritten.
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

    private static func rows(from environment: [String: String]) -> [EnvRow] {
        environment
            .sorted { $0.key < $1.key }
            .map { EnvRow(key: $0.key, value: $0.value) }
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
