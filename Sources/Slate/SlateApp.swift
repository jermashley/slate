import AppKit
import SwiftUI

@main
struct SlateApp: App {
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup("Slate", id: "main") {
            SlateWindowRoot()
                .environmentObject(settings)
                .frame(minWidth: 820, minHeight: 520)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .commands {
            SlateCommands(settings: settings)
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .frame(width: 520)
        }
    }
}

private struct SlateWindowRoot: View {
    @StateObject private var workspace = WorkspaceModel()

    var body: some View {
        RootView()
            .environmentObject(workspace)
            .focusedSceneObject(workspace)
    }
}
