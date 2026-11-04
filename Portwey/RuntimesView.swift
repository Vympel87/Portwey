import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LauncherCore

struct RuntimesView: View {
    @Environment(SetupManager.self) private var setup
    @Environment(GameRunner.self) private var runner

    @State private var rosettaInstalled: Bool?
    @State private var showAvailable = false
    @State private var runtimeToDelete: RuntimeInfo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Runtimes")
                        .font(.system(size: 34, weight: .bold))
                    Text("Everything Portwey uses to run Windows games.")
                        .foregroundStyle(.secondary)
                }

                runtimeCard(
                    title: "Rosetta 2",
                    icon: "cpu",
                    status: rosettaStatus,
                    isInstalled: rosettaInstalled == true,
                    details: [("Purpose", "Runs Intel (x86_64) code on Apple Silicon")]
                )

                wineSection

                runtimeCard(
                    title: "DXVK-macOS",
                    icon: "cube.transparent",
                    status: setup.dxvk?.tag ?? "Not installed",
                    isInstalled: setup.dxvk != nil,
                    details: [("DLLs", setup.dxvk?.dllNames.joined(separator: ", ") ?? "—")]
                )

                runtimeCard(
                    title: "DXMT (experimental)",
                    icon: "square.stack.3d.forward.dottedline",
                    status: DXMTService.installed()?.tag ?? "Downloaded on first use",
                    isInstalled: DXMTService.installed() != nil,
                    details: [("Needs", "A Wine built from CrossOver's source (use Import… above)")]
                )

                runtimeCard(
                    title: "NW.js (native RPG Maker MV/MZ)",
                    icon: "macwindow",
                    status: NWJSService.installed()?.version ?? "Downloaded on first use",
                    isInstalled: NWJSService.installed() != nil,
                    details: [("Purpose", "Runs RPG Maker MV/MZ games natively, without Wine")]
                )

                runtimeCard(
                    title: "Godot (native Godot games)",
                    icon: "gamecontroller",
                    status: godotStatus,
                    isInstalled: !GodotService.installedRuntimes().isEmpty,
                    details: [("Purpose", "Runs Godot games natively with the matching engine version")]
                )

                HStack(spacing: 12) {
                    Button {
                        NSWorkspace.shared.open(AppPaths.root)
                    } label: {
                        Label("Show Data Folder", systemImage: "folder")
                    }

                    Button {
                        Task { await setup.start() }
                    } label: {
                        Label("Run Setup Again", systemImage: "arrow.clockwise")
                    }
                    .disabled(setup.isBusy || setup.runtimeTask != nil)
                }
                .controlSize(.large)
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Runtimes")
        .task {
            rosettaInstalled = await RosettaService.isInstalled()
            setup.refreshRuntimes()
        }
        .confirmationDialog(
            "Delete \(runtimeToDelete?.version ?? "this Wine version")?",
            isPresented: Binding(get: { runtimeToDelete != nil }, set: { if !$0 { runtimeToDelete = nil } }),
            presenting: runtimeToDelete
        ) { runtime in
            Button("Delete", role: .destructive) {
                setup.uninstallRuntime(runtime)
            }
        } message: { _ in
            Text("Its files and any DXVK/DXMT copies made from it will be removed. You can install it again later.")
        }
    }

    // MARK: - Wine

    private var wineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Wine", systemImage: "wineglass")
                    .font(.title3.bold())
                Spacer()
                Button {
                    chooseWineToImport()
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                .help("Add a Wine build you already have, for example one built from CrossOver's source (needed for DXMT)")
                .disabled(setup.runtimeTask != nil)

                Button {
                    showAvailable.toggle()
                    if showAvailable && setup.availableReleases.isEmpty {
                        Task { await setup.loadAvailableReleases() }
                    }
                } label: {
                    Label(showAvailable ? "Hide Available Versions" : "Check Available Versions",
                          systemImage: showAvailable ? "chevron.up" : "arrow.down.circle")
                }
            }

            Text("All games use the default version. After switching, Wine updates each bottle the first time it starts. Going back to an older version can break bottles made by a newer one; reset the bottle if that happens.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(setup.installedRuntimes) { runtime in
                installedRow(runtime)
            }

            if let task = setup.runtimeTask {
                taskBanner(task)
            }

            if let error = setup.runtimeError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if showAvailable {
                availableList
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private func chooseWineToImport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle, .folder]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Wine app or folder (it must contain bin/wine)"
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await setup.importRuntime(from: url) }
    }

    private func installedRow(_ runtime: RuntimeInfo) -> some View {
        let isDefault = runtime.installPath == setup.runtime?.installPath

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(runtime.version)
                        .font(.headline)
                    if isDefault {
                        Text("Default")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(.green)
                            .background(.green.opacity(0.15), in: Capsule())
                    }
                    if runtime.tag.hasPrefix("imported-") {
                        Text("Imported")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(.blue)
                            .background(.blue.opacity(0.15), in: Capsule())
                    }
                }
                Text(runtime.tag)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: runtime.installPath)])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")

            if !isDefault {
                Button("Make Default") {
                    setup.makeDefault(runtime)
                }
                .disabled(runner.isBusy)

                Button("Delete…", role: .destructive) {
                    runtimeToDelete = runtime
                }
                .disabled(setup.runtimeTask != nil)
            }
        }
        .padding(12)
        .background(.background.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func taskBanner(_ task: SetupManager.RuntimeTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch task {
            case .downloading(let name, let progress):
                Text("Downloading \(name)… \(Int(progress * 100))%")
                ProgressView(value: progress)
            case .extracting(let name):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Extracting \(name)…")
                }
            case .verifying(let name):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Testing \(name)…")
                }
            }
        }
        .font(.callout)
        .padding(12)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var availableList: some View {
        if setup.isLoadingReleases {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading versions from GitHub…")
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Available to install")
                    .font(.headline)
                    .padding(.top, 4)

                ForEach(setup.availableReleases.prefix(20)) { release in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(release.displayName)
                            Text("\(release.asset.name) · \(release.sizeText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isInstalled(release) {
                            Text("Installed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Install") {
                                Task { await setup.installRuntime(release) }
                            }
                            .disabled(setup.runtimeTask != nil)
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    /// Matches both new installs (folder named after the asset) and the first setup install (folder named after the tag).
    private func isInstalled(_ release: WineRelease) -> Bool {
        setup.installedRuntimes.contains { runtime in
            runtime.tag == release.folderName
                || (runtime.tag == release.tag && release.asset.name.hasPrefix("wine-devel"))
        }
    }

    // MARK: - Generic card

    private var rosettaStatus: String {
        switch rosettaInstalled {
        case .some(true): return "Installed"
        case .some(false): return "Not installed"
        case .none: return "Checking…"
        }
    }

    private var godotStatus: String {
        let versions = GodotService.installedRuntimes().map(\.version)
        return versions.isEmpty ? "Downloaded on first use" : versions.joined(separator: ", ")
    }

    private func runtimeCard(
        title: String,
        icon: String,
        status: String,
        isInstalled: Bool,
        details: [(String, String)]
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Label(status, systemImage: isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(isInstalled ? .green : .secondary)
                }
                ForEach(details, id: \.0) { detail in
                    HStack(alignment: .top, spacing: 8) {
                        Text(detail.0)
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                        Text(detail.1)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    .font(.callout)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
}
