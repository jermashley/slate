import SwiftUI

struct CommandHistorySearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [SessionSearchResult] = []

    let searchService = SessionSearchService()
    let onInsert: (String) -> Void
    let onRerun: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search command history", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit {
                        if let first = results.first {
                            insert(first.command)
                        }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { result in
                        Button {
                            insert(result.command)
                        } label: {
                            HistoryResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Insert Command") { insert(result.command) }
                            Button("Run Command") { rerun(result.command) }
                        }
                    }
                }
            }
            .frame(minHeight: 280)

            Divider()

            HStack {
                Text("Return inserts. Context menu can rerun.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 640, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: refresh)
        .onChange(of: query) { _, _ in refresh() }
    }

    private func refresh() {
        results = searchService.searchCommands(query)
    }

    private func insert(_ command: String) {
        onInsert(command)
        dismiss()
    }

    private func rerun(_ command: String) {
        onRerun(command)
        dismiss()
    }
}

private struct HistoryResultRow: View {
    let result: SessionSearchResult

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.command)
                    .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let workingDirectory = result.workingDirectory {
                        Text(displayPath(workingDirectory))
                    }
                    if let startedAt = result.startedAt {
                        Text(startedAt, style: .relative)
                    }
                    if let exitCode = result.exitCode {
                        Text("exit \(exitCode)")
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 1)
                .padding(.leading, 32)
        }
    }

    private var statusColor: Color {
        guard let exitCode = result.exitCode else { return Color(nsColor: .controlAccentColor) }
        return exitCode == 0 ? Color(nsColor: .systemGreen) : Color(nsColor: .systemRed)
    }

    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~/" + path.dropFirst(home.count + 1)
        }
        return path
    }
}
