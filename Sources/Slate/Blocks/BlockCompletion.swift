import Foundation

struct CompletionSuggestion: Identifiable, Equatable {
    enum Kind: String {
        case command
        case path
        case history
        case alias
        case function
        case variable
        case branch
        case script
        case option
    }

    enum Source: String {
        case fallback
        case zsh
        case history
    }

    let id = UUID()
    let title: String
    let detail: String
    let replacement: String
    let kind: Kind
    let replacementRange: NSRange
    let source: Source
    let annotation: String?

    init(
        title: String,
        detail: String,
        replacement: String,
        kind: Kind,
        replacementRange: NSRange = NSRange(location: 0, length: 0),
        source: Source = .fallback,
        annotation: String? = nil
    ) {
        self.title = title
        self.detail = detail
        self.replacement = replacement
        self.kind = kind
        self.replacementRange = replacementRange
        self.source = source
        self.annotation = annotation
    }
}

struct CompletionContext {
    let text: String
    let currentDirectory: String?
    let history: [String]
    let shell: String
}

protocol CompletionProvider {
    func suggestions(for context: CompletionContext) -> [CompletionSuggestion]
}

final class BlockCompletionEngine {
    private let providers: [CompletionProvider]

    init(shell: String) {
        if URL(fileURLWithPath: shell).lastPathComponent == "zsh" {
            providers = [
                ZshCompletionProvider(shell: shell),
                FallbackCompletionProvider()
            ]
        } else {
            providers = [FallbackCompletionProvider()]
        }
    }

    func suggestions(for context: CompletionContext) -> [CompletionSuggestion] {
        var merged: [CompletionSuggestion] = []
        var seen = Set<String>()

        for provider in providers {
            for suggestion in provider.suggestions(for: context) {
                let key = "\(suggestion.kind.rawValue):\(suggestion.replacement):\(suggestion.replacementRange.location):\(suggestion.replacementRange.length)"
                guard seen.insert(key).inserted else { continue }
                merged.append(suggestion)
            }
            if merged.count >= 24 {
                break
            }
        }

        return Array(merged.prefix(24))
    }

    func apply(_ suggestion: CompletionSuggestion, to text: String) -> String {
        if suggestion.kind == .history {
            return suggestion.replacement
        }

        let nsText = text as NSString
        let range = suggestion.replacementRange.location >= 0
            ? suggestion.replacementRange
            : CompletionQuery.parse(text).tokenRange
        return nsText.replacingCharacters(in: range, with: suggestion.replacement)
    }
}

struct FallbackCompletionProvider: CompletionProvider {
    func suggestions(for context: CompletionContext) -> [CompletionSuggestion] {
        let query = completionQuery(in: context.text)
        let token = query.token

        if query.expectsDirectory {
            return pathSuggestions(
                for: token,
                currentDirectory: context.currentDirectory,
                directoriesOnly: true,
                replacementRange: query.tokenRange
            )
        }

        guard !token.isEmpty else { return [] }

        if token.hasPrefix("$") {
            return variableSuggestions(prefix: token, replacementRange: query.tokenRange)
        }

        if token.contains("/") || token.hasPrefix(".") || token.hasPrefix("~") {
            return pathSuggestions(
                for: token,
                currentDirectory: context.currentDirectory,
                directoriesOnly: false,
                replacementRange: query.tokenRange
            )
        }

        let commandSuggestions = query.isCommandPosition ? executableSuggestions(prefix: token, replacementRange: query.tokenRange) : []
        let historySuggestions = context.history
            .reversed()
            .filter { $0.hasPrefix(context.text) && $0 != context.text }
            .uniqued()
            .prefix(5)
            .map {
                CompletionSuggestion(
                    title: $0,
                    detail: "History",
                    replacement: $0,
                    kind: .history,
                    replacementRange: NSRange(location: 0, length: (context.text as NSString).length),
                    source: .history
                )
            }

        return Array(historySuggestions + commandSuggestions.prefix(8))
    }

    private func completionQuery(in text: String) -> CompletionQuery {
        CompletionQuery.parse(text)
    }

    private func executableSuggestions(prefix: String, replacementRange: NSRange) -> [CompletionSuggestion] {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let executableNames = path
            .split(separator: ":")
            .flatMap { directory -> [String] in
                guard let names = try? FileManager.default.contentsOfDirectory(atPath: String(directory)) else { return [] }
                return names.filter { $0.hasPrefix(prefix) }
            }
            .uniqued()
            .sorted()

        return executableNames.map {
            CompletionSuggestion(title: $0, detail: "Command", replacement: $0, kind: .command, replacementRange: replacementRange)
        }
    }

    private func variableSuggestions(prefix: String, replacementRange: NSRange) -> [CompletionSuggestion] {
        let rawPrefix = String(prefix.dropFirst())
        return ProcessInfo.processInfo.environment.keys
            .filter { rawPrefix.isEmpty || $0.hasPrefix(rawPrefix) }
            .sorted()
            .prefix(12)
            .map {
                CompletionSuggestion(
                    title: "$\($0)",
                    detail: "Variable",
                    replacement: "$\($0)",
                    kind: .variable,
                    replacementRange: replacementRange
                )
            }
    }

    private func pathSuggestions(for token: String, currentDirectory: String?, directoriesOnly: Bool, replacementRange: NSRange) -> [CompletionSuggestion] {
        let expandedToken = NSString(string: token).expandingTildeInPath
        let basePath: String
        if token.isEmpty {
            basePath = currentDirectory ?? FileManager.default.currentDirectoryPath
        } else if expandedToken.hasPrefix("/") {
            basePath = expandedToken
        } else {
            basePath = URL(fileURLWithPath: currentDirectory ?? FileManager.default.currentDirectoryPath)
                .appendingPathComponent(expandedToken)
                .path
        }

        let directory = URL(fileURLWithPath: basePath).deletingLastPathComponent()
        let prefix = URL(fileURLWithPath: basePath).lastPathComponent
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }

        return names
            .compactMap { name -> (name: String, isDirectory: Bool)? in
                guard prefix.isEmpty || name.localizedCaseInsensitiveCompare(prefix) == .orderedSame || name.lowercased().hasPrefix(prefix.lowercased()) else {
                    return nil
                }

                var isDirectory: ObjCBool = false
                let fullPath = directory.appendingPathComponent(name).path
                guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory) else {
                    return nil
                }

                if directoriesOnly, !isDirectory.boolValue {
                    return nil
                }
                return (name, isDirectory.boolValue)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(14)
            .map { name in
                let suffix = name.isDirectory ? "/" : ""
                let replacementPrefix = (token as NSString).deletingLastPathComponent
                let replacement = replacementPrefix.isEmpty || replacementPrefix == "."
                    ? "\(escapedPathComponent(name.name))\(suffix)"
                    : "\(replacementPrefix)/\(escapedPathComponent(name.name))\(suffix)"
                return CompletionSuggestion(
                    title: "\(name.name)\(suffix)",
                    detail: name.isDirectory ? "Folder" : "File",
                    replacement: replacement,
                    kind: .path,
                    replacementRange: replacementRange
                )
            }
    }

    private func escapedPathComponent(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "\\ ")
    }
}

final class ZshCompletionProvider: CompletionProvider {
    private struct ZshSymbol {
        let name: String
        let kind: CompletionSuggestion.Kind
        let detail: String
    }

    private let shell: String
    private lazy var symbols: [ZshSymbol] = loadSymbols()

    init(shell: String) {
        self.shell = shell
    }

    func suggestions(for context: CompletionContext) -> [CompletionSuggestion] {
        let query = CompletionQuery.parse(context.text)
        let token = query.token
        guard !token.isEmpty else { return [] }

        if token.hasPrefix("$") {
            return environmentSuggestions(prefix: token, range: query.tokenRange)
        }

        if let command = query.command {
            let commandSuggestions = commandSpecificSuggestions(command: command, query: query, context: context)
            if !commandSuggestions.isEmpty {
                return commandSuggestions
            }
        }

        guard query.isCommandPosition else { return [] }
        return symbols
            .filter { $0.name.hasPrefix(token) }
            .sorted { lhs, rhs in
                if lhs.kind.rawValue != rhs.kind.rawValue {
                    return lhs.kind.rawValue < rhs.kind.rawValue
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(16)
            .map {
                CompletionSuggestion(
                    title: $0.name,
                    detail: $0.detail,
                    replacement: $0.name,
                    kind: $0.kind,
                    replacementRange: query.tokenRange,
                    source: .zsh
                )
            }
    }

    private func commandSpecificSuggestions(command: String, query: CompletionQuery, context: CompletionContext) -> [CompletionSuggestion] {
        switch command {
        case "git":
            return gitSuggestions(query: query, currentDirectory: context.currentDirectory)
        case "npm", "pnpm", "yarn":
            return packageScriptSuggestions(query: query, currentDirectory: context.currentDirectory)
        default:
            return []
        }
    }

    private func gitSuggestions(query: CompletionQuery, currentDirectory: String?) -> [CompletionSuggestion] {
        guard ["checkout", "switch", "branch"].contains(query.wordsBeforeToken.dropFirst().first ?? "") else {
            return []
        }
        let branches = runProcess(
            "/usr/bin/git",
            arguments: ["branch", "--format=%(refname:short)"],
            currentDirectory: currentDirectory
        )
        return branches
            .split(separator: "\n")
            .map(String.init)
            .filter { query.token.isEmpty || $0.hasPrefix(query.token) }
            .prefix(16)
            .map {
                CompletionSuggestion(
                    title: $0,
                    detail: "Branch",
                    replacement: $0,
                    kind: .branch,
                    replacementRange: query.tokenRange,
                    source: .zsh
                )
            }
    }

    private func packageScriptSuggestions(query: CompletionQuery, currentDirectory: String?) -> [CompletionSuggestion] {
        guard query.wordsBeforeToken.dropFirst().first == "run" else { return [] }
        let directory = URL(fileURLWithPath: currentDirectory ?? FileManager.default.currentDirectoryPath)
        let packageJSON = directory.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageJSON),
              let text = String(data: data, encoding: .utf8),
              let scriptsRange = text.range(of: #""scripts"\s*:\s*\{"#, options: .regularExpression) else {
            return []
        }

        let tail = text[scriptsRange.upperBound...]
        let scriptPattern = #""([^"]+)"\s*:"#
        let regex = try? NSRegularExpression(pattern: scriptPattern)
        let nsTail = String(tail) as NSString
        let matches = regex?.matches(in: String(tail), range: NSRange(location: 0, length: nsTail.length)) ?? []

        return matches
            .compactMap { match -> String? in
                guard match.numberOfRanges > 1 else { return nil }
                return nsTail.substring(with: match.range(at: 1))
            }
            .filter { query.token.isEmpty || $0.hasPrefix(query.token) }
            .prefix(16)
            .map {
                CompletionSuggestion(
                    title: $0,
                    detail: "Script",
                    replacement: $0,
                    kind: .script,
                    replacementRange: query.tokenRange,
                    source: .zsh
                )
            }
    }

    private func environmentSuggestions(prefix: String, range: NSRange) -> [CompletionSuggestion] {
        let rawPrefix = String(prefix.dropFirst())
        return ProcessInfo.processInfo.environment.keys
            .filter { rawPrefix.isEmpty || $0.hasPrefix(rawPrefix) }
            .sorted()
            .prefix(16)
            .map {
                CompletionSuggestion(
                    title: "$\($0)",
                    detail: "Variable",
                    replacement: "$\($0)",
                    kind: .variable,
                    replacementRange: range,
                    source: .zsh
                )
            }
    }

    private func loadSymbols() -> [ZshSymbol] {
        let script = """
        print -rl -- '__SLATE_ALIASES__'
        print -rl -- ${(k)aliases}
        print -rl -- '__SLATE_FUNCTIONS__'
        print -rl -- ${(k)functions}
        print -rl -- '__SLATE_COMMANDS__'
        print -rl -- ${(k)commands}
        """

        let output = runProcess(shell, arguments: ["-ic", script], currentDirectory: nil)
        var section: CompletionSuggestion.Kind?
        var symbols: [ZshSymbol] = []
        var seen = Set<String>()

        for line in output.split(separator: "\n").map(String.init) {
            switch line {
            case "__SLATE_ALIASES__":
                section = .alias
            case "__SLATE_FUNCTIONS__":
                section = .function
            case "__SLATE_COMMANDS__":
                section = .command
            default:
                guard let section, !line.isEmpty, seen.insert("\(section.rawValue):\(line)").inserted else {
                    continue
                }
                let detail: String
                switch section {
                case .alias: detail = "Alias"
                case .function: detail = "Function"
                default: detail = "Command"
                }
                symbols.append(ZshSymbol(name: line, kind: section, detail: detail))
            }
        }

        return symbols
    }

    private func runProcess(_ executable: String, arguments: [String], currentDirectory: String?) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

struct CompletionQuery {
    let token: String
    let tokenRange: NSRange
    let wordsBeforeToken: [String]

    var command: String? {
        wordsBeforeToken.first
    }

    var isCommandPosition: Bool {
        wordsBeforeToken.isEmpty
            || ["|", "&&", "||", ";"].contains(wordsBeforeToken.last ?? "")
    }

    var expectsDirectory: Bool {
        guard let command = command?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return ["cd", "pushd"].contains(command) && wordsBeforeToken.count >= 1
    }

    static func parse(_ text: String) -> CompletionQuery {
        let tokenRange = currentTokenRange(in: text)
        let token = (text as NSString).substring(with: tokenRange)
        let prefix = (text as NSString).substring(to: tokenRange.location)
        return CompletionQuery(
            token: token,
            tokenRange: tokenRange,
            wordsBeforeToken: shellWords(in: prefix)
        )
    }

    private static func currentTokenRange(in text: String) -> NSRange {
        let nsText = text as NSString
        var start = nsText.length

        while start > 0 {
            let scalar = nsText.character(at: start - 1)
            if CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(scalar)!) {
                break
            }
            start -= 1
        }

        return NSRange(location: start, length: nsText.length - start)
    }

    private static func shellWords(in text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var isEscaped = false

        for character in text {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            if character == "\"" || character == "'" {
                if quote == nil {
                    quote = character
                } else if quote == character {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if quote == nil, character.isWhitespace {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
            } else if quote == nil, ["|", ";"].contains(character) {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                words.append(String(character))
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            words.append(current)
        }
        return words
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
