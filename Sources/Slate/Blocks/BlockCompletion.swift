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
        let token = currentToken(in: context.text)
        guard !token.isEmpty else { return [] }

        if token.contains("/") || token.hasPrefix(".") || token.hasPrefix("~") {
            return pathSuggestions(for: token, currentDirectory: context.currentDirectory)
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
        let range = currentTokenRange(in: text)
        return nsText.replacingCharacters(in: range, with: suggestion.replacement)
    }

    private static func currentToken(in text: String) -> String {
        let range = currentTokenRange(in: text)
        return (text as NSString).substring(with: range)
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

    private static func pathSuggestions(for token: String, currentDirectory: String?) -> [CompletionSuggestion] {
        let expandedToken = NSString(string: token).expandingTildeInPath
        let basePath: String
        if expandedToken.hasPrefix("/") {
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
            .filter { $0.hasPrefix(prefix) }
            .sorted()
            .prefix(10)
            .map { name in
                var isDirectory: ObjCBool = false
                let fullPath = directory.appendingPathComponent(name).path
                FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory)

                let suffix = isDirectory.boolValue ? "/" : ""
                let replacementPrefix = (token as NSString).deletingLastPathComponent
                let replacement = replacementPrefix.isEmpty || replacementPrefix == "."
                    ? "\(escapedPathComponent(name))\(suffix)"
                    : "\(replacementPrefix)/\(escapedPathComponent(name))\(suffix)"
                return CompletionSuggestion(
                    title: "\(name)\(suffix)",
                    detail: isDirectory.boolValue ? "Folder" : "File",
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
