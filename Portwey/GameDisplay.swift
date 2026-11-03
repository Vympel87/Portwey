import SwiftUI
import LauncherCore

enum GameStatus {
    case ready, preparing, running, missing

    @MainActor
    init(game: Game, runner: GameRunner) {
        if runner.isRunning(game.id) {
            self = .running
        } else if runner.isPreparing(game.id) {
            self = .preparing
        } else if !game.executableExists {
            self = .missing
        } else {
            self = .ready
        }
    }

    var label: String {
        switch self {
        case .ready: return "Ready to play"
        case .preparing: return "Preparing…"
        case .running: return "Running"
        case .missing: return "File missing"
        }
    }

    var color: Color {
        switch self {
        case .ready: return .green
        case .preparing: return .orange
        case .running: return .blue
        case .missing: return .red
        }
    }
}

extension Game {
    var playtimeText: String {
        guard playtimeSeconds >= 60 else {
            return playtimeSeconds > 0 ? "< 1 min" : "None yet"
        }
        return Duration.seconds(playtimeSeconds)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    var lastPlayedText: String {
        lastPlayedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "Never"
    }

    /// Placeholder cover with a stable color per title (real cover art comes later).
    var coverColors: [Color] {
        let seed = title.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let hue = Double(seed % 360) / 360
        return [
            Color(hue: hue, saturation: 0.6, brightness: 0.55),
            Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.35)
        ]
    }
}

extension GameRunner {
    var activeGameID: UUID? {
        switch state {
        case .preparing(let id), .running(let id):
            return id
        case .idle:
            return nil
        }
    }
}

@MainActor
func playGame(_ game: Game, runner: GameRunner, setup: SetupManager) {
    guard let runtime = setup.runtime, !runner.isBusy else { return }
    Task { await runner.launch(game, runtime: runtime) }
}
