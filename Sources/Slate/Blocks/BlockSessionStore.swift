import Foundation

struct PersistedSession: Identifiable, Equatable {
    let id: UUID
    var shell: String
    var startupDirectory: String
    var currentDirectory: String?
    var title: String
    var blocks: [PersistedBlock]
}

struct PersistedBlock: Identifiable, Equatable {
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

    init(block: TerminalBlock) {
        self.id = block.id
        self.command = block.command
        self.workingDirectory = block.workingDirectory
        self.shell = block.shell
        self.startedAt = block.startedAt
        self.endedAt = block.endedAt
        self.exitCode = block.exitCode
        self.state = block.state
        self.isCollapsed = block.isCollapsed
        self.output = block.output
    }

    var terminalBlock: TerminalBlock {
        TerminalBlock(
            id: id,
            command: command,
            workingDirectory: workingDirectory,
            shell: shell,
            startedAt: startedAt,
            endedAt: endedAt,
            exitCode: exitCode,
            state: state,
            isCollapsed: isCollapsed,
            output: output
        )
    }
}

struct SessionSearchResult: Identifiable, Equatable {
    let id: UUID
    let sessionID: UUID
    let command: String
    let workingDirectory: String?
    let exitCode: Int32?
    let startedAt: Date?
}

@MainActor
final class SessionSearchService {
    private let store: BlockSessionStore

    init(store: BlockSessionStore = .shared) {
        self.store = store
    }

    func searchCommands(_ query: String) -> [SessionSearchResult] {
        store.searchCommands(query)
    }
}

@MainActor
final class BlockSessionStore {
    static let shared = BlockSessionStore()

    private let databaseURL: URL
    private let sqlitePath = "/usr/bin/sqlite3"

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = appSupport.appendingPathComponent("Slate", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        databaseURL = directory.appendingPathComponent("BlockSessions.sqlite3")
        migrate()
    }

    func loadSessions() -> [PersistedSession] {
        let rows = query("""
            SELECT id, shell, startup_directory, current_directory, title
            FROM sessions
            ORDER BY updated_at DESC;
            """)

        return rows.compactMap { row in
            guard row.count >= 5, let id = UUID(uuidString: row[0]) else { return nil }
            return PersistedSession(
                id: id,
                shell: row[1],
                startupDirectory: row[2],
                currentDirectory: row[3].isEmpty ? nil : row[3],
                title: row[4],
                blocks: loadBlocks(sessionID: id)
            )
        }
    }

    func saveSession(id: UUID, shell: String, startupDirectory: String, currentDirectory: String?, title: String, blocks: [TerminalBlock]) {
        let now = Date().timeIntervalSince1970
        var sql = "BEGIN IMMEDIATE;\n"
        sql += """
            INSERT INTO sessions(id, shell, startup_directory, current_directory, title, updated_at)
            VALUES('\(escape(id.uuidString))', '\(escape(shell))', '\(escape(startupDirectory))', \(sqlString(currentDirectory)), '\(escape(title))', \(now))
            ON CONFLICT(id) DO UPDATE SET
              shell=excluded.shell,
              startup_directory=excluded.startup_directory,
              current_directory=excluded.current_directory,
              title=excluded.title,
              updated_at=excluded.updated_at;
            DELETE FROM blocks WHERE session_id='\(escape(id.uuidString))';
            DELETE FROM blocks_fts WHERE session_id='\(escape(id.uuidString))';
            """

        for (position, block) in blocks.enumerated() {
            sql += """
                INSERT INTO blocks(id, session_id, position, command, cwd, shell, started_at, ended_at, exit_code, state, collapsed, output)
                VALUES('\(escape(block.id.uuidString))', '\(escape(id.uuidString))', \(position), '\(escape(block.command))', \(sqlString(block.workingDirectory)), '\(escape(block.shell))', \(sqlDate(block.startedAt)), \(sqlDate(block.endedAt)), \(sqlInt(block.exitCode)), '\(escape(block.state.rawValue))', \(block.isCollapsed ? 1 : 0), '\(escape(block.output))');
                INSERT INTO blocks_fts(block_id, session_id, command, output)
                VALUES('\(escape(block.id.uuidString))', '\(escape(id.uuidString))', '\(escape(block.command))', '\(escape(block.output))');
                """
        }

        sql += "COMMIT;"
        execute(sql)
    }

    func clearSession(id: UUID) {
        execute("""
            BEGIN IMMEDIATE;
            DELETE FROM blocks WHERE session_id='\(escape(id.uuidString))';
            DELETE FROM blocks_fts WHERE session_id='\(escape(id.uuidString))';
            DELETE FROM sessions WHERE id='\(escape(id.uuidString))';
            COMMIT;
            """)
    }

    func searchCommands(_ queryText: String) -> [SessionSearchResult] {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let escapedQuery = escapeFTS(trimmed)
        let rows = query("""
            SELECT b.id, b.session_id, b.command, IFNULL(b.cwd, ''), IFNULL(b.exit_code, ''), IFNULL(b.started_at, '')
            FROM blocks_fts f
            JOIN blocks b ON b.id = f.block_id
            WHERE blocks_fts MATCH '\(escape(escapedQuery))'
            ORDER BY b.started_at DESC
            LIMIT 50;
            """)

        return rows.compactMap { row in
            guard row.count >= 6,
                  let id = UUID(uuidString: row[0]),
                  let sessionID = UUID(uuidString: row[1]) else {
                return nil
            }
            return SessionSearchResult(
                id: id,
                sessionID: sessionID,
                command: row[2],
                workingDirectory: row[3].isEmpty ? nil : row[3],
                exitCode: Int32(row[4]),
                startedAt: Double(row[5]).map(Date.init(timeIntervalSince1970:))
            )
        }
    }

    private func migrate() {
        execute("""
            CREATE TABLE IF NOT EXISTS sessions(
              id TEXT PRIMARY KEY,
              shell TEXT NOT NULL,
              startup_directory TEXT NOT NULL,
              current_directory TEXT,
              title TEXT NOT NULL,
              updated_at REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS blocks(
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              position INTEGER NOT NULL,
              command TEXT NOT NULL,
              cwd TEXT,
              shell TEXT NOT NULL,
              started_at REAL,
              ended_at REAL,
              exit_code INTEGER,
              state TEXT NOT NULL,
              collapsed INTEGER NOT NULL DEFAULT 0,
              output TEXT NOT NULL DEFAULT ''
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS blocks_fts USING fts5(
              block_id UNINDEXED,
              session_id UNINDEXED,
              command,
              output
            );
            """)
    }

    private func loadBlocks(sessionID: UUID) -> [PersistedBlock] {
        let rows = query("""
            SELECT id, command, IFNULL(cwd, ''), shell, IFNULL(started_at, ''), IFNULL(ended_at, ''), IFNULL(exit_code, ''), state, collapsed, output
            FROM blocks
            WHERE session_id='\(escape(sessionID.uuidString))'
            ORDER BY position ASC;
            """)

        return rows.compactMap { row in
            guard row.count >= 10,
                  let id = UUID(uuidString: row[0]),
                  let state = TerminalBlockState(rawValue: row[7]) else {
                return nil
            }
            return PersistedBlock(
                id: id,
                command: row[1],
                workingDirectory: row[2].isEmpty ? nil : row[2],
                shell: row[3],
                startedAt: Double(row[4]).map(Date.init(timeIntervalSince1970:)),
                endedAt: Double(row[5]).map(Date.init(timeIntervalSince1970:)),
                exitCode: Int32(row[6]),
                state: state,
                isCollapsed: row[8] == "1",
                output: row[9]
            )
        }
    }

    private func execute(_ sql: String) {
        _ = runSQLite(arguments: [databaseURL.path], input: sql)
    }

    private func query(_ sql: String) -> [[String]] {
        let output = runSQLite(arguments: ["-separator", "\u{1f}", "-newline", "\u{1e}", databaseURL.path], input: sql)
        return output
            .split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .map { row in
                row.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            }
    }

    private func runSQLite(arguments: [String], input: String) -> String {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: sqlitePath)
        process.arguments = arguments
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            if let data = input.data(using: .utf8) {
                stdin.fileHandleForWriting.write(data)
            }
            stdin.fileHandleForWriting.closeFile()
            process.waitUntilExit()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private func escapeFTS(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
            .joined(separator: " ")
    }

    private func sqlString(_ value: String?) -> String {
        guard let value else { return "NULL" }
        return "'\(escape(value))'"
    }

    private func sqlDate(_ value: Date?) -> String {
        guard let value else { return "NULL" }
        return "\(value.timeIntervalSince1970)"
    }

    private func sqlInt(_ value: Int32?) -> String {
        guard let value else { return "NULL" }
        return "\(value)"
    }
}

private extension PersistedBlock {
    init(
        id: UUID,
        command: String,
        workingDirectory: String?,
        shell: String,
        startedAt: Date?,
        endedAt: Date?,
        exitCode: Int32?,
        state: TerminalBlockState,
        isCollapsed: Bool,
        output: String
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
}
