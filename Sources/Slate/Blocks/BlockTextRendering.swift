import AppKit
import SwiftUI

enum ShellSyntaxHighlighter {
    static func attributedCommand(_ text: String, fontSize: Double, enabled: Bool) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: max(12, fontSize - 0.5), weight: .regular)
        let baseColor: NSColor = enabled ? .textColor : .disabledControlTextColor
        let dimColor = NSColor.secondaryLabelColor.withAlphaComponent(enabled ? 0.82 : 0.45)
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: baseColor
            ]
        )

        let nsText = text as NSString
        let operators = CharacterSet(charactersIn: "|&;<>")
        var tokenStart: Int?
        var quote: unichar?
        var commandPosition = true

        func styleToken(_ range: NSRange, index: Int) {
            guard range.length > 0 else { return }
            let token = nsText.substring(with: range)
            let color: NSColor
            if token.hasPrefix("#") {
                color = .tertiaryLabelColor
            } else if token.hasPrefix("$") {
                color = .systemPurple
            } else if token.hasPrefix("-") {
                color = .systemBlue
            } else if token.contains("="), !token.hasPrefix("="), !token.hasSuffix("=") {
                color = .systemPurple
            } else if token.hasPrefix("/") || token.hasPrefix("./") || token.hasPrefix("../") || token.hasPrefix("~") {
                color = .systemBlue
            } else if commandPosition || index == 0 {
                color = .systemBlue
                attributed.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: max(12, fontSize - 0.5), weight: .medium), range: range)
            } else {
                color = baseColor
            }
            attributed.addAttribute(.foregroundColor, value: color.withAlphaComponent(enabled ? 0.92 : 0.5), range: range)
            commandPosition = false
        }

        var tokenIndex = 0
        for index in 0..<nsText.length {
            let char = nsText.character(at: index)
            if char == 34 || char == 39 {
                if quote == nil {
                    quote = char
                    tokenStart = tokenStart ?? index
                } else if quote == char {
                    quote = nil
                }
                continue
            }

            if quote != nil {
                continue
            }

            if let scalar = UnicodeScalar(char), operators.contains(scalar) {
                if let start = tokenStart {
                    styleToken(NSRange(location: start, length: index - start), index: tokenIndex)
                    tokenIndex += 1
                    tokenStart = nil
                }
                attributed.addAttribute(.foregroundColor, value: dimColor, range: NSRange(location: index, length: 1))
                if char == 124 || char == 59 || char == 38 {
                    commandPosition = true
                }
                continue
            }

            if CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(char)!) {
                if let start = tokenStart {
                    styleToken(NSRange(location: start, length: index - start), index: tokenIndex)
                    tokenIndex += 1
                    tokenStart = nil
                }
            } else if tokenStart == nil {
                tokenStart = index
            }
        }

        if let start = tokenStart {
            styleToken(NSRange(location: start, length: nsText.length - start), index: tokenIndex)
        }

        highlightQuotedStrings(in: nsText, attributed: attributed, enabled: enabled)
        highlightSubstitutions(in: nsText, attributed: attributed, enabled: enabled)
        return attributed
    }

    private static func highlightQuotedStrings(in text: NSString, attributed: NSMutableAttributedString, enabled: Bool) {
        var start: Int?
        var quote: unichar?
        for index in 0..<text.length {
            let char = text.character(at: index)
            guard char == 34 || char == 39 else { continue }
            if quote == nil {
                quote = char
                start = index
            } else if quote == char, let stringStart = start {
                attributed.addAttribute(
                    .foregroundColor,
                    value: NSColor.systemGreen.withAlphaComponent(enabled ? 0.88 : 0.5),
                    range: NSRange(location: stringStart, length: index - stringStart + 1)
                )
                quote = nil
                start = nil
            }
        }
    }

    private static func highlightSubstitutions(in text: NSString, attributed: NSMutableAttributedString, enabled: Bool) {
        let color = NSColor.systemPurple.withAlphaComponent(enabled ? 0.9 : 0.5)
        for pattern in ["\\$[A-Za-z_][A-Za-z0-9_]*", "\\$\\{[^}]+\\}", "`[^`]+`"] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            regex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
                guard let range = match?.range else { return }
                attributed.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
    }
}

enum ANSIOutputRenderer {
    static func attributedOutput(_ text: String, fontSize: Double) -> NSAttributedString {
        let output = NSMutableAttributedString()
        var currentColor = NSColor.textColor
        var currentBackgroundColor: NSColor?
        var isBold = false
        var isUnderline = false
        var buffer = ""
        var index = text.startIndex

        func flush() {
            guard !buffer.isEmpty else { return }
            let fontWeight: NSFont.Weight = isBold ? .semibold : .regular
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: fontWeight),
                .foregroundColor: currentColor
            ]
            if let currentBackgroundColor {
                attributes[.backgroundColor] = currentBackgroundColor.withAlphaComponent(0.18)
            }
            if isUnderline {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            output.append(NSAttributedString(string: buffer, attributes: attributes))
            buffer = ""
        }

        while index < text.endIndex {
            if text[index] == "\u{1B}", text.index(after: index) < text.endIndex, text[text.index(after: index)] == "[" {
                flush()
                index = text.index(index, offsetBy: 2)
                var sequence = ""
                while index < text.endIndex {
                    let char = text[index]
                    index = text.index(after: index)
                    if char == "m" { break }
                    sequence.append(char)
                }
                applySGR(sequence, color: &currentColor, backgroundColor: &currentBackgroundColor, bold: &isBold, underline: &isUnderline)
            } else {
                buffer.append(text[index])
                index = text.index(after: index)
            }
        }
        flush()
        applyLongListingHighlights(output, fontSize: fontSize)
        applySemanticHighlights(output)
        return output
    }

    static func plainText(_ text: String) -> String {
        attributedOutput(text, fontSize: 13).string
    }

    static func swiftUIOutput(_ text: String, fontSize: Double) -> AttributedString {
        (try? AttributedString(attributedOutput(text, fontSize: fontSize), including: \.appKit))
            ?? AttributedString(plainText(text))
    }

    private static func applySGR(_ sequence: String, color: inout NSColor, backgroundColor: inout NSColor?, bold: inout Bool, underline: inout Bool) {
        let codes = sequence.split(separator: ";").compactMap { Int($0) }
        if codes.isEmpty {
            color = .textColor
            backgroundColor = nil
            bold = false
            underline = false
            return
        }

        var index = 0
        func nextColor(after colorModeIndex: Int) -> (NSColor?, Int) {
            guard codes.indices.contains(colorModeIndex + 1) else { return (nil, colorModeIndex) }
            let mode = codes[colorModeIndex + 1]
            if mode == 5, codes.indices.contains(colorModeIndex + 2) {
                return (ansi256Color(codes[colorModeIndex + 2]), colorModeIndex + 2)
            }
            if mode == 2, codes.indices.contains(colorModeIndex + 4) {
                return (
                    NSColor(
                        calibratedRed: CGFloat(codes[colorModeIndex + 2]) / 255,
                        green: CGFloat(codes[colorModeIndex + 3]) / 255,
                        blue: CGFloat(codes[colorModeIndex + 4]) / 255,
                        alpha: 1
                    ),
                    colorModeIndex + 4
                )
            }
            return (nil, colorModeIndex)
        }

        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0:
                color = .textColor
                backgroundColor = nil
                bold = false
                underline = false
            case 1:
                bold = true
            case 22:
                bold = false
            case 4:
                underline = true
            case 24:
                underline = false
            case 30: color = .labelColor
            case 31: color = .systemRed
            case 32: color = .systemGreen
            case 33: color = .systemYellow
            case 34: color = .systemBlue
            case 35: color = .systemPurple
            case 36: color = .systemTeal
            case 37: color = .textColor
            case 90: color = .tertiaryLabelColor
            case 91: color = .systemRed
            case 92: color = .systemGreen
            case 93: color = .systemYellow
            case 94: color = .systemBlue
            case 95: color = .systemPurple
            case 96: color = .systemTeal
            case 97: color = .labelColor
            case 39: color = .textColor
            case 40...47:
                backgroundColor = basicColor(code - 40)
            case 100...107:
                backgroundColor = brightColor(code - 100)
            case 49:
                backgroundColor = nil
            case 38:
                let parsed = nextColor(after: index)
                if let parsedColor = parsed.0 {
                    color = parsedColor
                    index = parsed.1
                }
            case 48:
                let parsed = nextColor(after: index)
                if let parsedColor = parsed.0 {
                    backgroundColor = parsedColor
                    index = parsed.1
                }
            default:
                break
            }
            index += 1
        }
    }

    private static func basicColor(_ code: Int) -> NSColor {
        switch code {
        case 0: .labelColor
        case 1: .systemRed
        case 2: .systemGreen
        case 3: .systemYellow
        case 4: .systemBlue
        case 5: .systemPurple
        case 6: .systemTeal
        default: .textColor
        }
    }

    private static func brightColor(_ code: Int) -> NSColor {
        basicColor(code).withAlphaComponent(0.95)
    }

    private static func ansi256Color(_ code: Int) -> NSColor {
        if code < 16 {
            return code < 8 ? basicColor(code) : brightColor(code - 8)
        }
        if code >= 232 {
            let value = CGFloat(8 + (code - 232) * 10) / 255
            return NSColor(calibratedWhite: value, alpha: 1)
        }
        let adjusted = code - 16
        let r = adjusted / 36
        let g = (adjusted % 36) / 6
        let b = adjusted % 6
        func component(_ value: Int) -> CGFloat {
            value == 0 ? 0 : CGFloat(55 + value * 40) / 255
        }
        return NSColor(calibratedRed: component(r), green: component(g), blue: component(b), alpha: 1)
    }

    private static func applySemanticHighlights(_ output: NSMutableAttributedString) {
        let text = output.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        let patterns: [(String, [NSAttributedString.Key: Any])] = [
            ("(?i)\\b(error|failed|failure|fatal|exception)\\b", [.foregroundColor: NSColor.systemRed]),
            ("(?i)\\b(warn|warning|deprecated)\\b", [.foregroundColor: NSColor.systemOrange]),
            ("https?://[^\\s]+", [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue])
        ]

        for (pattern, attributes) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            regex.enumerateMatches(in: output.string, range: fullRange) { match, _, _ in
                guard let range = match?.range else { return }
                for (key, value) in attributes {
                    if key == .font, output.attribute(.font, at: max(0, range.location), effectiveRange: nil) != nil {
                        continue
                    }
                    output.addAttribute(key, value: value, range: range)
                }
            }
        }
    }

    private static func applyLongListingHighlights(_ output: NSMutableAttributedString, fontSize: Double) {
        let string = output.string as NSString
        let text = output.string
        let metadataColor = NSColor.secondaryLabelColor.withAlphaComponent(0.8)
        let directoryColor = NSColor.systemBlue
        let executableColor = NSColor.systemGreen.withAlphaComponent(0.9)
        let symlinkTargetColor = NSColor.systemBlue
        let separatorColor = NSColor.secondaryLabelColor.withAlphaComponent(0.55)
        let listingPattern = #"^([bcdlps-][rwxStTs-]{9}[@+]?)(\s+\d+)(\s+\S+)(\s+\S+)(\s+\S+)(\s+[A-Z][a-z]{2}\s+\d+\s+(?:\d{2}:\d{2}|\d{4}))(\s+)(.+)$"#
        let listingRegex = try? NSRegularExpression(pattern: listingPattern)

        var offset = 0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let lineRange = NSRange(location: offset, length: (line as NSString).length)
            defer { offset += lineRange.length + 1 }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("total ") {
                output.addAttribute(.foregroundColor, value: metadataColor, range: lineRange)
                continue
            }

            guard let match = listingRegex?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
                  match.numberOfRanges >= 9 else {
                continue
            }

            let permissionRange = NSRange(location: lineRange.location + match.range(at: 1).location, length: match.range(at: 1).length)
            let metadataStart = match.range(at: 1).location
            let metadataEnd = match.range(at: 7).location + match.range(at: 7).length
            output.addAttribute(
                .foregroundColor,
                value: metadataColor,
                range: NSRange(location: lineRange.location + metadataStart, length: metadataEnd - metadataStart)
            )
            output.addAttribute(.foregroundColor, value: metadataColor.withAlphaComponent(0.95), range: permissionRange)

            let nameRangeInLine = match.range(at: 8)
            let absoluteNameRange = NSRange(location: lineRange.location + nameRangeInLine.location, length: nameRangeInLine.length)
            let permission = string.substring(with: permissionRange)
            let name = (line as NSString).substring(with: nameRangeInLine)

            if permission.hasPrefix("d") {
                output.addAttributes([
                    .foregroundColor: directoryColor,
                    .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
                ], range: absoluteNameRange)
            } else if permission.hasPrefix("l"), let arrowRange = name.range(of: " -> ") {
                let nsName = name as NSString
                let arrowLocation = nsName.range(of: " -> ").location
                let arrowAbsolute = NSRange(location: absoluteNameRange.location + arrowLocation, length: 4)
                let targetStart = arrowLocation + 4
                let targetAbsolute = NSRange(location: absoluteNameRange.location + targetStart, length: nsName.length - targetStart)
                output.addAttribute(.foregroundColor, value: separatorColor, range: arrowAbsolute)
                output.addAttributes([
                    .foregroundColor: symlinkTargetColor,
                    .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
                ], range: targetAbsolute)
                _ = arrowRange
            } else if permission.contains("x") {
                output.addAttribute(.foregroundColor, value: executableColor, range: absoluteNameRange)
            }
        }
    }
}

struct OutputText: View {
    let text: String
    let fontSize: Double

    var body: some View {
        Text(ANSIOutputRenderer.swiftUIOutput(text, fontSize: fontSize))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
