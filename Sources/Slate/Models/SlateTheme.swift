import SwiftUI
import AppKit

struct SlateTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let background: Color
    let foreground: Color
    let muted: Color
    let accent: Color
    let selection: Color

    static let system = SlateTheme(
        id: "system",
        name: "System",
        background: Color(nsColor: .textBackgroundColor),
        foreground: Color(nsColor: .textColor),
        muted: Color(nsColor: .secondaryLabelColor),
        accent: Color.accentColor,
        selection: Color(nsColor: .selectedTextBackgroundColor)
    )

    static let all: [SlateTheme] = [
        system,
        SlateTheme(
            id: "obsidian",
            name: "Obsidian",
            background: Color(red: 0.055, green: 0.058, blue: 0.064),
            foreground: Color(red: 0.88, green: 0.88, blue: 0.84),
            muted: Color(red: 0.46, green: 0.48, blue: 0.50),
            accent: Color(red: 0.72, green: 0.80, blue: 0.72),
            selection: Color(red: 0.20, green: 0.27, blue: 0.24)
        ),
        SlateTheme(
            id: "paper",
            name: "Paper",
            background: Color(red: 0.965, green: 0.957, blue: 0.936),
            foreground: Color(red: 0.13, green: 0.14, blue: 0.15),
            muted: Color(red: 0.49, green: 0.49, blue: 0.47),
            accent: Color(red: 0.18, green: 0.39, blue: 0.48),
            selection: Color(red: 0.78, green: 0.86, blue: 0.86)
        ),
        SlateTheme(
            id: "graphite",
            name: "Graphite",
            background: Color(red: 0.12, green: 0.125, blue: 0.13),
            foreground: Color(red: 0.83, green: 0.84, blue: 0.82),
            muted: Color(red: 0.46, green: 0.47, blue: 0.47),
            accent: Color(red: 0.68, green: 0.75, blue: 0.82),
            selection: Color(red: 0.24, green: 0.27, blue: 0.30)
        ),
        SlateTheme(
            id: "field",
            name: "Field",
            background: Color(red: 0.09, green: 0.12, blue: 0.10),
            foreground: Color(red: 0.84, green: 0.88, blue: 0.78),
            muted: Color(red: 0.47, green: 0.54, blue: 0.46),
            accent: Color(red: 0.80, green: 0.68, blue: 0.46),
            selection: Color(red: 0.22, green: 0.29, blue: 0.20)
        ),
        SlateTheme(
            id: "ink",
            name: "Ink",
            background: Color(red: 0.975, green: 0.975, blue: 0.965),
            foreground: Color(red: 0.08, green: 0.09, blue: 0.10),
            muted: Color(red: 0.43, green: 0.44, blue: 0.45),
            accent: Color(red: 0.45, green: 0.24, blue: 0.20),
            selection: Color(red: 0.88, green: 0.83, blue: 0.76)
        )
    ]

    static func theme(for id: String) -> SlateTheme {
        all.first { $0.id == id } ?? all[0]
    }

    var nsBackground: NSColor {
        id == "system" ? .textBackgroundColor : NSColor(background)
    }

    var nsForeground: NSColor {
        id == "system" ? .textColor : NSColor(foreground)
    }

    var nsMuted: NSColor {
        id == "system" ? .secondaryLabelColor : NSColor(muted)
    }

    var nsAccent: NSColor {
        id == "system" ? .controlAccentColor : NSColor(accent)
    }

    var nsSelection: NSColor {
        id == "system" ? .selectedTextBackgroundColor : NSColor(selection)
    }
}
