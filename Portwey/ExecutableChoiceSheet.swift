import SwiftUI

struct ExecutableChoice: Identifiable {
    let id = UUID()
    let folder: URL
    let candidates: [URL]
}

/// Asks which .exe starts the game when a folder contains several.
struct ExecutableChoiceSheet: View {
    let choice: ExecutableChoice
    let onChoose: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Which file starts the game?")
                .font(.title2.bold())
            Text("Portwey found several .exe files in “\(choice.folder.lastPathComponent)”. The first one is its best guess.")
                .foregroundStyle(.secondary)

            List(choice.candidates, id: \.self, selection: $selection) { url in
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.body.weight(.medium))
                    Text(relativePath(of: url))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 220)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add Game") {
                    if let selection {
                        onChoose(selection)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear {
            selection = choice.candidates.first
        }
    }

    private func relativePath(of url: URL) -> String {
        url.path.replacingOccurrences(of: choice.folder.path + "/", with: "")
    }
}
