import Combine
import Foundation

@MainActor
final class TerminalTab: ObservableObject, Identifiable {
    let id = UUID()
    let style: SessionStyle
    let classicController: TerminalSessionController?
    let blockController: BlockSessionController?
    private var cancellables: Set<AnyCancellable> = []

    init(style: SessionStyle, settings: SettingsStore) {
        self.style = style
        switch style {
        case .classic:
            self.classicController = TerminalSessionController()
            self.blockController = nil
        case .block:
            self.classicController = nil
            self.blockController = BlockSessionController(tabID: id, settings: settings)
        }

        classicController?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)

        blockController?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }

    var fallbackTitle: String {
        switch style {
        case .classic:
            classicController?.title ?? "Shell"
        case .block:
            blockController?.title ?? "Blocks"
        }
    }

    var hasForegroundProcess: Bool {
        switch style {
        case .classic:
            classicController?.hasForegroundProcess ?? false
        case .block:
            blockController?.hasForegroundProcess ?? false
        }
    }

    func focus() {
        switch style {
        case .classic:
            classicController?.focus()
        case .block:
            blockController?.focusComposer()
        }
    }

    func terminate() {
        switch style {
        case .classic:
            classicController?.terminate()
        case .block:
            blockController?.terminate()
        }
    }

    func clearHistory() {
        switch style {
        case .classic:
            classicController?.terminalView.getTerminal().resetNormalBuffer()
        case .block:
            blockController?.clearHistory()
        }
    }

    func installExitHandler(_ handler: @escaping () -> Void) {
        switch style {
        case .classic:
            classicController?.onExit = handler
        case .block:
            blockController?.onExit = handler
        }
    }

    func clearExitHandler() {
        switch style {
        case .classic:
            classicController?.onExit = nil
        case .block:
            blockController?.onExit = nil
        }
    }
}
