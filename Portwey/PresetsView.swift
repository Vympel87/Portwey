import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LauncherCore

struct PresetsView: View {
    @Environment(GameLibrary.self) private var library

    @State private var editingPreset: GamePreset?
    @State private var presetToDelete: GamePreset?
    @State private var isRefreshing = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Presets")
                        .font(.system(size: 34, weight: .bold))
                    Text("Settings known to work for specific games. Portwey applies a matching preset automatically when you add a game.")
                        .foregroundStyle(.secondary)
                }

                section(
                    title: "My Presets",
                    footer: "Saved on this Mac. They win over community presets when both match a game."
                ) {
                    if library.myPresets.isEmpty {
                        Text("None yet. Open a game's settings and choose Save as My Preset.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(library.myPresets) { preset in
                            row(preset, isMine: true)
                        }
                    }
                }

                section(
                    title: "Community Presets",
                    footer: "Loaded from presets.json in Portwey's GitHub repo and kept for offline use."
                ) {
                    if library.communityPresets.isEmpty {
                        Text("No community presets loaded yet. Check your internet connection and refresh.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(library.communityPresets) { preset in
                            row(preset, isMine: false)
                        }
                    }
                }

                GroupBox("For the Portwey maintainer") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Export a presets.json that combines the community presets with yours. Save it over presets.json in the repo folder, then commit and push to publish it to everyone.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button {
                            export()
                        } label: {
                            Label("Export presets.json…", systemImage: "square.and.arrow.up.on.square")
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Presets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        isRefreshing = true
                        await library.refreshPresets()
                        isRefreshing = false
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
                .help("Download the latest community presets")
            }
        }
        .sheet(item: $editingPreset) { preset in
            PresetEditorSheet(preset: preset, isNew: false) { saved in
                library.saveMyPreset(saved)
            }
        }
        .confirmationDialog(
            "Delete “\(presetToDelete?.title ?? "")”?",
            isPresented: Binding(get: { presetToDelete != nil }, set: { if !$0 { presetToDelete = nil } }),
            presenting: presetToDelete
        ) { preset in
            Button("Delete", role: .destructive) {
                library.deleteMyPreset(preset)
            }
        } message: { _ in
            Text("Games that use it keep their current settings.")
        }
        .alert(
            "Presets",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: - Pieces

    private func section<Content: View>(
        title: String,
        footer: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ preset: GamePreset, isMine: Bool) -> some View {
        let usedBy = library.games(usingPreset: preset).count

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let status = preset.status {
                        PresetStatusBadge(status: status)
                    }
                    Text(preset.title)
                        .font(.headline)
                    if usedBy > 0 {
                        Text(usedBy == 1 ? "Used by 1 game" : "Used by \(usedBy) games")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(preset.matchSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(preset.settingsSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notes = preset.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .padding(.top, 2)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if isMine {
                    Button("Edit") {
                        editingPreset = preset
                    }
                    if let url = PresetService.shareURL(for: preset) {
                        Button("Share…") {
                            NSWorkspace.shared.open(url)
                        }
                        .help("Open a pre-filled GitHub issue so the preset can be added for everyone")
                    }
                }
                Button("Copy JSON") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(PresetService.json(for: preset), forType: .string)
                }
                if isMine {
                    Button("Delete…", role: .destructive) {
                        presetToDelete = preset
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Export

    private func export() {
        do {
            let data = try library.exportPresetsFile()
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "presets.json"
            panel.allowedContentTypes = [.json]
            panel.message = "Save over presets.json in your Portwey repo folder"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            message = "Saved \(url.lastPathComponent). Commit and push it to publish the presets."
        } catch {
            message = "Couldn't export presets: \(error.localizedDescription)"
        }
    }
}

// MARK: - Shared badges

struct PresetStatusBadge: View {
    let status: GamePreset.Status

    private var color: Color {
        switch status {
        case .works: return .green
        case .playable: return .orange
        case .broken: return .red
        }
    }

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct PresetSourceBadge: View {
    let isMine: Bool

    var body: some View {
        Text(isMine ? "Mine" : "Community")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(isMine ? Color.blue : Color.purple)
            .background((isMine ? Color.blue : Color.purple).opacity(0.15), in: Capsule())
    }
}
