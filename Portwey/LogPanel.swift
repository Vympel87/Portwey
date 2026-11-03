import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct LogPanel: View {
    let lines: [String]

    @State private var searchText = ""
    @State private var errorsOnly = false

    private var filteredLines: [String] {
        lines.filter { line in
            let matchesLevel = !errorsOnly || Self.isErrorLine(line)
            let matchesSearch = searchText.isEmpty || line.localizedCaseInsensitiveContains(searchText)
            return matchesLevel && matchesSearch
        }
    }

    var body: some View {
        let visible = filteredLines

        VStack(alignment: .leading, spacing: 8) {
            toolbar(visible: visible)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, line in
                        Text(highlighted(line))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Self.isErrorLine(line) ? Color.red : Color.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
            }
            .defaultScrollAnchor(.bottom)
            .frame(height: 240)
            .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                if visible.isEmpty {
                    Text(lines.isEmpty ? "No logs yet" : "No matching lines")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Toolbar

    private func toolbar(visible: [String]) -> some View {
        HStack(spacing: 10) {
            Text("Logs")
                .font(.headline)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search logs", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: 240)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))

            Toggle("Errors only", isOn: $errorsOnly)
                .toggleStyle(.checkbox)

            Text("\(visible.count) / \(lines.count) lines")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer()

            Button("Copy") {
                copy(visible)
            }
            .help("Copy the lines currently shown")
            .disabled(visible.isEmpty)

            Button("Save…") {
                save()
            }
            .help("Save the full log to a text file")
            .disabled(lines.isEmpty)
        }
    }

    // MARK: - Helpers

    static func isErrorLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("err:")
            || lower.contains("error")
            || lower.contains("failed")
            || lower.contains("exception")
            || line.contains("❌")
    }

    private func highlighted(_ line: String) -> AttributedString {
        var attributed = AttributedString(line)
        guard !searchText.isEmpty else { return attributed }

        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
              let range = attributed[searchStart...].range(of: searchText, options: .caseInsensitive) {
            attributed[range].backgroundColor = Color.yellow.opacity(0.35)
            searchStart = range.upperBound
        }
        return attributed
    }

    private func copy(_ lines: [String]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "portwey-log-\(Date().formatted(.iso8601.year().month().day())).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
