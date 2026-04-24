import AppKit
import SwiftTerm
import SwiftUI

private final class TerminalContainerView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

struct TerminalHostView: NSViewRepresentable {
    @ObservedObject var controller: TerminalSessionController
    @EnvironmentObject private var settings: SettingsStore

    func makeNSView(context: Context) -> NSView {
        let container = TerminalContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        container.onAppearanceChange = {
            controller.apply(settings: settings)
        }
        controller.mount(in: container, settings: settings)
        DispatchQueue.main.async {
            controller.focus()
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let container = nsView as? TerminalContainerView {
            container.onAppearanceChange = {
                controller.apply(settings: settings)
            }
        }
        controller.mount(in: nsView, settings: settings)
        controller.apply(settings: settings)
    }
}
