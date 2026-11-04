import SwiftUI
import LauncherCore

/// Form for creating or editing one of your presets.
struct PresetEditorSheet: View {
    let isNew: Bool
    let onSave: (GamePreset) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var preset: GamePreset
    @State private var executable: String
    @State private var titleContains: String
    @State private var engine: GameEngine?
    @State private var notes: String

    init(preset: GamePreset, isNew: Bool, onSave: @escaping (GamePreset) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        _preset = State(initialValue: preset)
        _executable = State(initialValue: preset.match.executable ?? "")
        _titleContains = State(initialValue: preset.match.titleContains ?? "")
        _engine = State(initialValue: preset.match.engine)
        _notes = State(initialValue: preset.notes ?? "")
    }

    private var canSave: Bool {
        !preset.title.trimmed.isEmpty && (!executable.trimmed.isEmpty || !titleContains.trimmed.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Save as My Preset" : "Edit Preset")
                .font(.title2.bold())

            Form {
                Section("Preset") {
                    TextField("Title", text: $preset.title)

                    Picker("Status", selection: Binding(
                        get: { preset.status ?? .works },
                        set: { preset.status = $0 }
                    )) {
                        ForEach(GamePreset.Status.allCases) { status in
                            Text(status.label).tag(status)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                        TextEditor(text: $notes)
                            .font(.body)
                            .frame(height: 80)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                        Text("How well does it run? Anything other players should know?")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Matches games where") {
                    TextField(".exe name", text: $executable, prompt: Text("Starmaker Story.exe"))
                    TextField("Title or folder contains", text: $titleContains, prompt: Text("Needed for generic names like Game.exe"))
                    Picker("Engine", selection: $engine) {
                        Text("Any").tag(GameEngine?.none)
                        ForEach(GameEngine.allCases.filter { $0 != .unknown }, id: \.self) { item in
                            Text(item.displayName).tag(GameEngine?.some(item))
                        }
                    }
                }

                Section("Settings") {
                    Text(preset.settingsSummary)
                        .foregroundStyle(.secondary)
                    Text("Settings come from the game. To change them, adjust the game's settings and save the preset again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            if !canSave {
                Text("Give it a title and at least an .exe name or title text to match.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isNew ? "Save Preset" : "Save Changes") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 560, height: 640)
    }

    private func save() {
        var result = preset
        result.title = preset.title.trimmed
        result.match = GamePreset.Match(
            executable: executable.trimmed.nilIfEmpty,
            titleContains: titleContains.trimmed.nilIfEmpty,
            engine: engine
        )
        result.notes = notes.trimmed.nilIfEmpty
        onSave(result)
        dismiss()
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
