import SwiftUI

struct SlateCommands: Commands {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var settings: SettingsStore
    @ObservedObject var workspace: WorkspaceModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") {
                workspace.newTab(settings: settings)
                DispatchQueue.main.async {
                    workspace.focusSelectedTerminal()
                }
            }
            .keyboardShortcut("t", modifiers: [.command])

            Button("Close Tab") {
                workspace.requestCloseSelectedTab()
            }
            .keyboardShortcut("w", modifiers: [.command])
        }

        CommandMenu("Tab") {
            Button("Next Tab") {
                workspace.selectNextTab()
                DispatchQueue.main.async {
                    workspace.focusSelectedTerminal()
                }
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button("Previous Tab") {
                workspace.selectPreviousTab()
                DispatchQueue.main.async {
                    workspace.focusSelectedTerminal()
                }
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
        }

        CommandGroup(after: .textEditing) {
            Button("Find in Scrollback") {
                workspace.selectedTab?.controller.showFind()
            }
            .keyboardShortcut("f", modifiers: [.command])

            Divider()

            Button("Settings...") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}
