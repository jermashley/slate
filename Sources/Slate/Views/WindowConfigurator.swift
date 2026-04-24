import AppKit
import SwiftUI

private extension NSToolbarItem.Identifier {
    static let tabBar = NSToolbarItem.Identifier("Slate.TabBar")
}

// Allows click-and-drag anywhere in the toolbar to move the window.
// mouseDownCanMoveWindow alone isn't sufficient because NSWindow's hit-test
// reaches SwiftUI's internal child views, which don't override it. Instead we
// store the mouseDown event and call performDrag on the first real drag movement.
private class DraggableHostingView<Content: View>: NSHostingView<Content> {
    private var mouseDownEvent: NSEvent?

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let initial = mouseDownEvent else {
            super.mouseDragged(with: event)
            return
        }
        let dx = event.locationInWindow.x - initial.locationInWindow.x
        let dy = event.locationInWindow.y - initial.locationInWindow.y
        if dx * dx + dy * dy > 9 {
            window?.performDrag(with: initial)
            mouseDownEvent = nil
        }
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        super.mouseUp(with: event)
    }
}

struct WindowConfigurator<TabBar: View>: NSViewRepresentable {
    let tabBar: TabBar

    func makeCoordinator() -> Coordinator {
        Coordinator(tabBar: tabBar)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateTabBar(tabBar)
        DispatchQueue.main.async {
            context.coordinator.configure(window: nsView.window)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSToolbarDelegate {
        private let hostingView: DraggableHostingView<TabBar>
        private weak var configuredWindow: NSWindow?

        init(tabBar: TabBar) {
            self.hostingView = DraggableHostingView(rootView: tabBar)
            self.hostingView.translatesAutoresizingMaskIntoConstraints = false
            super.init()

            // Fixed height; low hugging priority lets the item expand to fill toolbar width.
            NSLayoutConstraint.activate([
                hostingView.heightAnchor.constraint(equalToConstant: 32),
                hostingView.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            ])
            hostingView.setContentHuggingPriority(.init(rawValue: 1), for: .horizontal)
        }

        func updateTabBar(_ tabBar: TabBar) {
            hostingView.rootView = tabBar
            hostingView.invalidateIntrinsicContentSize()
        }

        func configure(window: NSWindow?) {
            guard let window, window !== configuredWindow else { return }
            configuredWindow = window

            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = false
            window.toolbarStyle = .unified
            window.isMovableByWindowBackground = true

            let toolbar = NSToolbar(identifier: "Slate.MainToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            toolbar.showsBaselineSeparator = true
            window.toolbar = toolbar
        }

        // MARK: - NSToolbarDelegate

        func toolbar(
            _ toolbar: NSToolbar,
            itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            guard itemIdentifier == .tabBar else { return nil }
            let item = NSToolbarItem(itemIdentifier: .tabBar)
            item.view = hostingView
            return item
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [.tabBar]
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [.tabBar]
        }
    }
}
