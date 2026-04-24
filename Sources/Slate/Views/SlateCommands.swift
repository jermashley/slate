import SwiftUI

struct SlateCommands: Commands {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @FocusedObject private var workspace: WorkspaceModel?
    @ObservedObject var settings: SettingsStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("New Tab") {
                workspace?.newTab(settings: settings)
                DispatchQueue.main.async {
                    workspace?.focusSelectedTerminal()
                }
            }
            .keyboardShortcut("t", modifiers: [.command])
            .disabled(workspace == nil)

            Button("Close Tab") {
                workspace?.requestCloseSelectedTab()
            }
            .keyboardShortcut("w", modifiers: [.command])
            .disabled(workspace == nil)
        }

        CommandMenu("Tab") {
            Button("Next Tab") {
                workspace?.selectNextTab()
                DispatchQueue.main.async {
                    workspace?.focusSelectedTerminal()
                }
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(workspace == nil)

            Button("Previous Tab") {
                workspace?.selectPreviousTab()
                DispatchQueue.main.async {
                    workspace?.focusSelectedTerminal()
                }
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(workspace == nil)
        }

        CommandGroup(after: .textEditing) {
            Button("Find in Scrollback") {
                workspace?.showFindInSelectedTab()
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(workspace == nil)

            Button("Clear History") {
                workspace?.clearSelectedTabHistory()
            }
            .keyboardShortcut("k", modifiers: [.command])
            .disabled(workspace == nil)

            Divider()

            Button("Settings...") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}
