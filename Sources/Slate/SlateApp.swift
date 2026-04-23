import AppKit
import SwiftUI

@main
struct SlateApp: App {
    @StateObject private var settings = SettingsStore()
    @StateObject private var workspace = WorkspaceModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(workspace)
                .frame(minWidth: 820, minHeight: 520)
                .onAppear {
                    workspace.ensureInitialTab(settings: settings)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SlateCommands(settings: settings, workspace: workspace)
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .frame(width: 520)
        }
    }
}
