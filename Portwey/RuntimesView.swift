import SwiftUI
import AppKit
import LauncherCore

struct RuntimesView: View {
    @Environment(SetupManager.self) private var setup

    @State private var rosettaInstalled: Bool?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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

                runtimeCard(
                    title: "Wine",
                    icon: "wineglass",
                    status: setup.runtime?.version ?? "Not installed",
                    isInstalled: setup.runtime != nil,
                    details: [("Location", setup.runtime?.installPath ?? "—")]
                )

                runtimeCard(
                    title: "DXVK-macOS",
                    icon: "cube.transparent",
                    status: setup.dxvk?.tag ?? "Not installed",
                    isInstalled: setup.dxvk != nil,
                    details: [("DLLs", setup.dxvk?.dllNames.joined(separator: ", ") ?? "—")]
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
                    .disabled(setup.isBusy)
                }
                .controlSize(.large)
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Runtimes")
        .task {
            rosettaInstalled = await RosettaService.isInstalled()
        }
    }

    private var rosettaStatus: String {
        switch rosettaInstalled {
        case .some(true): return "Installed"
        case .some(false): return "Not installed"
        case .none: return "Checking…"
        }
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
