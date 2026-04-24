import Foundation

struct CompletionSuggestion: Identifiable, Equatable {
    enum Kind: String {
        case command
        case path
        case history
    }

    let id = UUID()
    let title: String
    let detail: String
    let replacement: String
    let kind: Kind
}

struct CompletionContext {
    let text: String
    let currentDirectory: String?
    let history: [String]
}

enum BlockCompletionEngine {
    static func suggestions(for context: CompletionContext) -> [CompletionSuggestion] {
        let query = completionQuery(in: context.text)
        let token = query.token

        if query.expectsDirectory {
            return pathSuggestions(
                for: token,
                currentDirectory: context.currentDirectory,
                directoriesOnly: true
            )
        }

        guard !token.isEmpty else { return [] }

        if token.contains("/") || token.hasPrefix(".") || token.hasPrefix("~") {
            return pathSuggestions(
                for: token,
                currentDirectory: context.currentDirectory,
                directoriesOnly: false
            )
        }

        let commandSuggestions = executableSuggestions(prefix: token)
        let historySuggestions = context.history
            .reversed()
            .filter { $0.hasPrefix(context.text) && $0 != context.text }
            .uniqued()
            .prefix(5)
            .map {
                CompletionSuggestion(title: $0, detail: "History", replacement: $0, kind: .history)
            }

        return Array(historySuggestions + commandSuggestions.prefix(8))
    }

    static func apply(_ suggestion: CompletionSuggestion, to text: String) -> String {
        if suggestion.kind == .history {
            return suggestion.replacement
        }

        let nsText = text as NSString
        let range = completionQuery(in: text).tokenRange
        return nsText.replacingCharacters(in: range, with: suggestion.replacement)
    }

    private struct CompletionQuery {
        let token: String
        let tokenRange: NSRange
        let wordsBeforeToken: [String]

        var command: String? {
            wordsBeforeToken.first
        }

        var expectsDirectory: Bool {
            guard let command = command?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return ["cd", "pushd"].contains(command) && wordsBeforeToken.count >= 1
        }
    }

    private static func completionQuery(in text: String) -> CompletionQuery {
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
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            words.append(current)
        }
        return words
    }

    private static func executableSuggestions(prefix: String) -> [CompletionSuggestion] {
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
            CompletionSuggestion(title: $0, detail: "Command", replacement: $0, kind: .command)
        }
    }

    private static func pathSuggestions(for token: String, currentDirectory: String?, directoriesOnly: Bool) -> [CompletionSuggestion] {
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
                    kind: .path
                )
            }
    }

    private static func escapedPathComponent(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "\\ ")
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
