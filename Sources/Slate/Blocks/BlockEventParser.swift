import Foundation

enum BlockShellEvent: Equatable {
    case prompt
    case commandStart(String?)
    case outputStart
    case commandFinished(Int32)
    case cwd(String)
}

struct BlockParserResult {
    var visibleText: String = ""
    var events: [BlockShellEvent] = []
    var enteredAlternateScreen = false
    var exitedAlternateScreen = false
}

struct BlockEventParser {
    private var pending = ""

    mutating func parse(bytes: ArraySlice<UInt8>) -> BlockParserResult {
        guard let chunk = String(bytes: bytes, encoding: .utf8), !chunk.isEmpty else {
            return BlockParserResult()
        }

        pending += chunk
        var result = BlockParserResult()

        while !pending.isEmpty {
            if pending.hasPrefix("\u{1B}]") {
                guard let terminator = oscTerminatorRange(in: pending) else {
                    break
                }

                let bodyStart = pending.index(pending.startIndex, offsetBy: 2)
                let body = String(pending[bodyStart..<terminator.lowerBound])
                if let event = parseOSC(body) {
                    result.events.append(event)
                }
                pending.removeSubrange(pending.startIndex..<terminator.upperBound)
                continue
            }

            if pending.hasPrefix("\u{1B}[?1049h") || pending.hasPrefix("\u{1B}[?47h") || pending.hasPrefix("\u{1B}[?1047h") {
                result.enteredAlternateScreen = true
            } else if pending.hasPrefix("\u{1B}[?1049l") || pending.hasPrefix("\u{1B}[?47l") || pending.hasPrefix("\u{1B}[?1047l") {
                result.exitedAlternateScreen = true
            }

            let nextOSC = pending.range(of: "\u{1B}]")?.lowerBound ?? pending.endIndex
            result.visibleText += String(pending[..<nextOSC])
            pending.removeSubrange(pending.startIndex..<nextOSC)
        }

        return result
    }

    private func oscTerminatorRange(in text: String) -> Range<String.Index>? {
        let bel = text.range(of: "\u{7}")
        let st = text.range(of: "\u{1B}\\")

        switch (bel, st) {
        case let (.some(bel), .some(st)):
            return bel.lowerBound < st.lowerBound ? bel : st
        case let (.some(bel), nil):
            return bel
        case let (nil, .some(st)):
            return st
        case (nil, nil):
            return nil
        }
    }

    private func parseOSC(_ body: String) -> BlockShellEvent? {
        if body == "133;A" {
            return .prompt
        }
        if body.hasPrefix("133;B") {
            let command = fieldValue(named: "cmd64", in: body).flatMap { encoded in
                Data(base64Encoded: encoded).flatMap { String(data: $0, encoding: .utf8) }
            } ?? fieldValue(named: "cmd", in: body)
            return .commandStart(command)
        }
        if body == "133;C" {
            return .outputStart
        }
        if body.hasPrefix("133;D") {
            let parts = body.split(separator: ";", omittingEmptySubsequences: false)
            if let rawStatus = parts.last, let status = Int32(rawStatus) {
                return .commandFinished(status)
            }
            if let status = fieldValue(named: "exit", in: body).flatMap(Int32.init) {
                return .commandFinished(status)
            }
            return .commandFinished(0)
        }
        if body.hasPrefix("7;") || body.hasPrefix("1337;CurrentDir=") {
            if let cwd = parseCwd(from: body) {
                return .cwd(cwd)
            }
        }
        return nil
    }

    private func fieldValue(named name: String, in body: String) -> String? {
        let prefix = "\(name)="
        return body
            .split(separator: ";")
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)).removingPercentEncoding ?? String($0.dropFirst(prefix.count)) }
    }

    private func parseCwd(from body: String) -> String? {
        if body.hasPrefix("1337;CurrentDir=") {
            return String(body.dropFirst("1337;CurrentDir=".count)).removingPercentEncoding
        }
        guard body.hasPrefix("7;") else { return nil }
        let raw = String(body.dropFirst(2))
        if let url = URL(string: raw), url.isFileURL {
            return url.path
        }
        return raw.removingPercentEncoding
    }
}
