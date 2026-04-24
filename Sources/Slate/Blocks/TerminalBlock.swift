import Foundation

enum TerminalBlockState: String, Codable {
    case editing
    case submitted
    case running
    case succeeded
    case failed
    case interrupted
    case rawTerminal
}

struct TerminalBlock: Identifiable, Codable, Equatable {
    let id: UUID
    var command: String
    var workingDirectory: String?
    var shell: String
    var startedAt: Date?
    var endedAt: Date?
    var exitCode: Int32?
    var state: TerminalBlockState
    var isCollapsed: Bool
    var output: String

    init(
        id: UUID = UUID(),
        command: String,
        workingDirectory: String?,
        shell: String,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        exitCode: Int32? = nil,
        state: TerminalBlockState = .submitted,
        isCollapsed: Bool = false,
        output: String = ""
    ) {
        self.id = id
        self.command = command
        self.workingDirectory = workingDirectory
        self.shell = shell
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exitCode = exitCode
        self.state = state
        self.isCollapsed = isCollapsed
        self.output = output
    }

    var duration: TimeInterval? {
        guard let startedAt else { return nil }
        return (endedAt ?? Date()).timeIntervalSince(startedAt)
    }
}
