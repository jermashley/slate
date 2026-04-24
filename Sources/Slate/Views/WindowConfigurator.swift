import AppKit
import SwiftUI

struct WindowConfigurator<Accessory: View>: NSViewRepresentable {
    let accessory: Accessory

    func makeCoordinator() -> Coordinator {
        Coordinator(accessory: accessory)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateAccessory(accessory)
        DispatchQueue.main.async {
            context.coordinator.configure(window: nsView.window)
        }
    }

    @MainActor
    final class Coordinator {
        private var hostingView: NSHostingView<Accessory>
        private var accessoryController: NSTitlebarAccessoryViewController?
        private weak var configuredWindow: NSWindow?

        init(accessory: Accessory) {
            self.hostingView = NSHostingView(rootView: accessory)
            self.hostingView.translatesAutoresizingMaskIntoConstraints = false
        }

        func updateAccessory(_ accessory: Accessory) {
            hostingView.rootView = accessory
            hostingView.invalidateIntrinsicContentSize()
        }

        func configure(window: NSWindow?) {
            guard let window else { return }

            configuredWindow = window
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = false
            window.toolbarStyle = .unified
            window.toolbar = toolbar(for: window)

            if accessoryController == nil {
                let controller = NSTitlebarAccessoryViewController()
                controller.layoutAttribute = .bottom
                controller.view = hostingView
                controller.fullScreenMinHeight = 38
                accessoryController = controller
                window.addTitlebarAccessoryViewController(controller)
            }
        }

        private func toolbar(for window: NSWindow) -> NSToolbar {
            if let toolbar = window.toolbar {
                return toolbar
            }

            let toolbar = NSToolbar(identifier: "Slate.MainToolbar")
            toolbar.displayMode = .iconOnly
            toolbar.sizeMode = .regular
            toolbar.allowsUserCustomization = false
            toolbar.showsBaselineSeparator = false
            return toolbar
        }
    }
}
