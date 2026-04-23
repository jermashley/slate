import Foundation

@MainActor
final class TerminalTab: Identifiable {
    let id = UUID()
    let controller = TerminalSessionController()

    var fallbackTitle: String {
        controller.title
    }
}
