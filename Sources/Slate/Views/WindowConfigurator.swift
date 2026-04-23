import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let backgroundColor: NSColor

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.backgroundColor = backgroundColor
        DispatchQueue.main.async {
            context.coordinator.configure(window: nsView.window)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(backgroundColor: backgroundColor)
    }

    @MainActor
    final class Coordinator {
        var backgroundColor: NSColor
        private weak var window: NSWindow?

        init(backgroundColor: NSColor) {
            self.backgroundColor = backgroundColor
        }

        func configure(window: NSWindow?) {
            guard let window else { return }
            self.window = window

            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = backgroundColor
            window.toolbar = nil
        }
    }
}
