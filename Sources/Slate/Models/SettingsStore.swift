import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @AppStorage("themeID") var themeID: String = "system" { didSet { objectWillChange.send() } }
    @AppStorage("fontName") var fontName: String = "SF Mono" { didSet { objectWillChange.send() } }
    @AppStorage("fontSize") var fontSize: Double = 13.5 { didSet { objectWillChange.send() } }
    @AppStorage("cursorStyle") var cursorStyleRaw: String = CursorStyle.block.rawValue { didSet { objectWillChange.send() } }
    @AppStorage("shellOverride") var shellOverride: String = "" { didSet { objectWillChange.send() } }
    @AppStorage("startupDirectory") var startupDirectory: String = "" { didSet { objectWillChange.send() } }
    @AppStorage("scrollbackLimit") var scrollbackLimit: Int = 5_000 { didSet { objectWillChange.send() } }

    var theme: SlateTheme {
        SlateTheme.system
    }

    var cursorStyle: CursorStyle {
        get { CursorStyle(rawValue: cursorStyleRaw) ?? .block }
        set { cursorStyleRaw = newValue.rawValue }
    }

    var resolvedShell: String {
        if !shellOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return shellOverride
        }

        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }

        return "/bin/zsh"
    }

    var resolvedStartupDirectory: String {
        let trimmed = startupDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return NSString(string: trimmed).expandingTildeInPath
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }
}
