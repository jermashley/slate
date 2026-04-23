import AppKit
import SwiftTerm
import SwiftUI

struct TerminalHostView: NSViewRepresentable {
    @ObservedObject var controller: TerminalSessionController
    @EnvironmentObject private var settings: SettingsStore

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        controller.mount(in: container, settings: settings)
        DispatchQueue.main.async {
            controller.focus()
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.mount(in: nsView, settings: settings)
        controller.apply(settings: settings)
    }
}
