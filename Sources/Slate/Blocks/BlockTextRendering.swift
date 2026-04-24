import AppKit
import SwiftUI

enum ShellSyntaxHighlighter {
    static func attributedCommand(_ text: String, fontSize: Double, enabled: Bool) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: max(12, fontSize - 0.5), weight: .regular)
        let baseColor: NSColor = enabled ? .textColor : .disabledControlTextColor
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: baseColor
            ]
        )

        let nsText = text as NSString
        let operators = CharacterSet(charactersIn: "|&;<>()")
        var tokenStart: Int?
        var quote: unichar?

        func styleToken(_ range: NSRange, index: Int) {
            guard range.length > 0 else { return }
            let token = nsText.substring(with: range)
            let color: NSColor
            if index == 0 {
                color = .labelColor
                attributed.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: max(12, fontSize - 0.5), weight: .medium), range: range)
            } else if token.hasPrefix("-") {
                color = .systemPink
            } else if token.contains("="), !token.hasPrefix("=") {
                color = .systemPurple
            } else if token.hasPrefix("#") {
                color = .tertiaryLabelColor
            } else {
                color = baseColor
            }
            attributed.addAttribute(.foregroundColor, value: color.withAlphaComponent(enabled ? 0.92 : 0.5), range: range)
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
                attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: index, length: 1))
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
}

enum ANSIOutputRenderer {
    static func attributedOutput(_ text: String, fontSize: Double) -> NSAttributedString {
        let output = NSMutableAttributedString()
        var currentColor = NSColor.textColor
        var isBold = false
        var buffer = ""
        var index = text.startIndex

        func flush() {
            guard !buffer.isEmpty else { return }
            let fontWeight: NSFont.Weight = isBold ? .semibold : .regular
            output.append(NSAttributedString(
                string: buffer,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: fontWeight),
                    .foregroundColor: currentColor
                ]
            ))
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
                applySGR(sequence, color: &currentColor, bold: &isBold)
            } else {
                buffer.append(text[index])
                index = text.index(after: index)
            }
        }
        flush()
        return output
    }

    static func plainText(_ text: String) -> String {
        attributedOutput(text, fontSize: 13).string
    }

    private static func applySGR(_ sequence: String, color: inout NSColor, bold: inout Bool) {
        let codes = sequence.split(separator: ";").compactMap { Int($0) }
        if codes.isEmpty {
            color = .textColor
            bold = false
            return
        }

        for code in codes {
            switch code {
            case 0:
                color = .textColor
                bold = false
            case 1:
                bold = true
            case 22:
                bold = false
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
            default:
                continue
            }
        }
    }
}

struct OutputTextView: NSViewRepresentable {
    let text: String
    let fontSize: Double
    @Binding var measuredHeight: CGFloat

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        textView.textStorage?.setAttributedString(ANSIOutputRenderer.attributedOutput(text, fontSize: fontSize))
        DispatchQueue.main.async {
            measure(textView)
        }
    }

    private func measure(_ textView: NSTextView) {
        guard let textContainer = textView.textContainer else { return }
        let width = max(1, textView.bounds.width)
        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.layoutManager?.ensureLayout(for: textContainer)
        let usedRect = textView.layoutManager?.usedRect(for: textContainer) ?? .zero
        measuredHeight = max(1, ceil(usedRect.height))
    }
}
