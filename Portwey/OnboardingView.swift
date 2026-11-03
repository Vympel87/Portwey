import SwiftUI
import LauncherCore

struct OnboardingView: View {
    @Environment(SetupManager.self) private var setup

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Welcome to Portwey")
                    .font(.largeTitle.bold())
                Text("To run Windows games, Portwey needs to set up Rosetta 2, Wine and DXVK first. You only have to do this once.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            statusSection
            actionButton
            logSection
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var statusSection: some View {
        switch setup.phase {
        case .idle:
            EmptyView()
        case .downloadingWine(let progress):
            downloadProgress(title: "Downloading Wine…", progress: progress)
        case .downloadingDXVK(let progress):
            downloadProgress(title: "Downloading DXVK…", progress: progress)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(4)
                .frame(maxWidth: 520)
        case .ready:
            Label("Ready!", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        default:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(statusText).foregroundStyle(.secondary)
            }
        }
    }

    private func downloadProgress(title: String, progress: Double) -> some View {
        VStack(spacing: 8) {
            ProgressView(value: progress)
            Text("\(title) \(Int(progress * 100))%")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 420)
    }

    private var statusText: String {
        switch setup.phase {
        case .checkingRosetta: return "Checking Rosetta 2…"
        case .installingRosetta: return "Installing Rosetta 2 (enter your Mac password if asked)…"
        case .fetchingRelease: return "Looking for the latest Wine version…"
        case .extractingWine: return "Extracting Wine…"
        case .verifyingWine: return "Testing Wine…"
        case .fetchingDXVK: return "Looking for the latest DXVK version…"
        case .extractingDXVK: return "Extracting DXVK…"
        default: return ""
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch setup.phase {
        case .idle:
            Button("Start Setup") {
                Task { await setup.start() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .failed:
            Button("Try Again") {
                Task { await setup.start() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var logSection: some View {
        if !setup.logs.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(setup.logs.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            .defaultScrollAnchor(.bottom)
            .frame(maxWidth: 640, maxHeight: 180)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
