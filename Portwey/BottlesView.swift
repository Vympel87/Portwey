import SwiftUI
import AppKit
import LauncherCore

/// Friendly name for a bottle.
func bottleDisplayName(_ name: String) -> String {
    name == BottleManager.defaultBottleName ? "Shared (default)" : "Own bottle (\(name))"
}

struct BottlesView: View {
    @Environment(SetupManager.self) private var setup
    @Environment(GameLibrary.self) private var library
    @Environment(GameRunner.self) private var runner

    @State private var bottles: [BottleInfo] = []
    @State private var sizes: [String: Int64] = [:]
    @State private var bottleToReset: BottleInfo?
    @State private var bottleToDelete: BottleInfo?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bottles")
                        .font(.system(size: 34, weight: .bold))
                    Text("Each bottle is a separate Windows environment with its own C: drive, settings and saves.")
                        .foregroundStyle(.secondary)
                }

                if bottles.isEmpty {
                    Text("No bottles yet. One is created automatically the first time you play a game with Wine.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 20)
                } else {
                    ForEach(bottles) { bottle in
                        bottleCard(bottle)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Bottles")
        .task {
            await reload()
        }
        .confirmationDialog(
            "Reset “\(bottleToReset.map { bottleDisplayName($0.name) } ?? "")”?",
            isPresented: Binding(get: { bottleToReset != nil }, set: { if !$0 { bottleToReset = nil } }),
            presenting: bottleToReset
        ) { bottle in
            Button("Reset", role: .destructive) {
                Task { await remove(bottle) }
            }
        } message: { _ in
            Text("Everything inside this Windows environment will be erased, including settings and any saves stored in it. It's recreated the next time a game starts.")
        }
        .confirmationDialog(
            "Delete “\(bottleToDelete.map { bottleDisplayName($0.name) } ?? "")”?",
            isPresented: Binding(get: { bottleToDelete != nil }, set: { if !$0 { bottleToDelete = nil } }),
            presenting: bottleToDelete
        ) { bottle in
            Button("Delete", role: .destructive) {
                Task { await remove(bottle) }
            }
        } message: { _ in
            Text("No game uses this bottle anymore. Its files will be deleted.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Card

    private func bottleCard(_ bottle: BottleInfo) -> some View {
        let users = library.games(usingBottle: bottle.name)
        let isBusy = runner.activeGameID.flatMap { id in library.games.first { $0.id == id } }?.bottleName == bottle.name

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(bottleDisplayName(bottle.name), systemImage: "shippingbox.fill")
                    .font(.headline)
                Spacer()
                Text(sizeText(for: bottle))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text(users.isEmpty
                 ? "Not used by any game"
                 : "Used by: " + users.map(\.title).joined(separator: ", "))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 10) {
                Button {
                    NSWorkspace.shared.open(bottle.url.appendingPathComponent("drive_c", isDirectory: true))
                } label: {
                    Label("Open C: Drive", systemImage: "folder")
                }

                Button {
                    openWinecfg(for: bottle)
                } label: {
                    Label("Wine Settings", systemImage: "gearshape")
                }
                .disabled(setup.runtime == nil)

                Button {
                    Task {
                        if let runtime = setup.runtime {
                            await BottleManager.killAll(in: bottle.url, runtime: runtime)
                        }
                    }
                } label: {
                    Label("Stop All Processes", systemImage: "xmark.octagon")
                }
                .disabled(setup.runtime == nil)

                Spacer()

                if users.isEmpty && bottle.name != BottleManager.defaultBottleName {
                    Button("Delete…", role: .destructive) {
                        bottleToDelete = bottle
                    }
                    .disabled(isBusy)
                } else {
                    Button("Reset…", role: .destructive) {
                        bottleToReset = bottle
                    }
                    .disabled(isBusy)
                    .help(isBusy ? "Stop the running game first" : "Erase and recreate this bottle")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Actions

    private func reload() async {
        bottles = BottleManager.listBottles()
        for bottle in bottles {
            sizes[bottle.name] = await BottleManager.diskSize(of: bottle.url)
        }
    }

    private func remove(_ bottle: BottleInfo) async {
        do {
            try await BottleManager.deleteBottle(named: bottle.name, runtime: setup.runtime)
        } catch {
            errorMessage = error.localizedDescription
        }
        await reload()
    }

    private func openWinecfg(for bottle: BottleInfo) {
        guard let runtime = setup.runtime else { return }
        do {
            try BottleManager.openWinecfg(in: bottle.url, runtime: runtime)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sizeText(for bottle: BottleInfo) -> String {
        guard let size = sizes[bottle.name] else { return "Calculating…" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
