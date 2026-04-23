@preconcurrency import AppKit
import Foundation
@preconcurrency import SwiftTerm

@MainActor
final class TerminalSessionController: NSObject, ObservableObject {
    @Published var title: String = "~"
    @Published var currentDirectory: String?
    @Published var isRunning: Bool = false

    let terminalView: LocalProcessTerminalView
    private var didStart = false
    private var shellReportedTitle: String?

    override init() {
        self.terminalView = LocalProcessTerminalView(frame: .zero)
        self.terminalView.translatesAutoresizingMaskIntoConstraints = false
        super.init()
    }

    func configureIfNeeded(settings: SettingsStore) {
        terminalView.processDelegate = self
        terminalView.optionAsMetaKey = true
        terminalView.allowMouseReporting = true
        terminalView.caretViewTracksFocus = true
        apply(settings: settings)

        if !didStart {
            startProcess(in: terminalView, settings: settings)
        }
    }

    func mount(in containerView: NSView, settings: SettingsStore) {
        configureIfNeeded(settings: settings)

        if terminalView.superview !== containerView {
            terminalView.removeFromSuperview()
            containerView.addSubview(terminalView)
            NSLayoutConstraint.activate([
                terminalView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                terminalView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                terminalView.topAnchor.constraint(equalTo: containerView.topAnchor),
                terminalView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
        }
    }

    @MainActor
    func apply(settings: SettingsStore) {
        terminalView.font = NSFont(name: settings.fontName, size: settings.fontSize) ?? NSFont.monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
        terminalView.nativeForegroundColor = settings.theme.nsForeground
        terminalView.nativeBackgroundColor = settings.theme.nsBackground
        terminalView.caretColor = settings.theme.nsAccent
        terminalView.layer?.backgroundColor = settings.theme.nsBackground.cgColor
        terminalView.changeScrollback(settings.scrollbackLimit)
        terminalView.getTerminal().setCursorStyle(settings.cursorStyle.swiftTermStyle)
    }

    @MainActor
    func focus() {
        guard let window = terminalView.window else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(terminalView)
    }

    @MainActor
    func terminate() {
        terminalView.terminate()
    }

    @MainActor
    func showFind() {
        let menuItem = NSMenuItem()
        menuItem.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        terminalView.performFindPanelAction(menuItem)
        focus()
    }

    @MainActor
    private func startProcess(in terminalView: LocalProcessTerminalView, settings: SettingsStore) {
        let shell = settings.resolvedShell
        let execName = "-" + URL(fileURLWithPath: shell).lastPathComponent
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Slate"
        environment["TERM_PROGRAM_VERSION"] = "0.1"
        environment["SLATE_CLASSIC_MODE"] = "1"

        let envList = environment.map { "\($0.key)=\($0.value)" }
        currentDirectory = settings.resolvedStartupDirectory
        shellReportedTitle = nil
        updateDisplayedTitle()
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: envList,
            execName: execName,
            currentDirectory: settings.resolvedStartupDirectory
        )
        didStart = true
        isRunning = true
    }

    private func updateDisplayedTitle() {
        if let shellReportedTitle, !shellReportedTitle.isEmpty {
            title = shellReportedTitle
            return
        }

        if let currentDirectory {
            title = Self.displayTitle(for: currentDirectory)
            return
        }

        title = "Shell"
    }

    private static func displayTitle(for directory: String) -> String {
        let normalizedPath: String
        if let url = URL(string: directory), url.isFileURL {
            normalizedPath = url.path
        } else {
            normalizedPath = directory
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if normalizedPath == home {
            return "~"
        }
        if normalizedPath.hasPrefix(home + "/") {
            return "~/" + normalizedPath.dropFirst(home.count + 1)
        }

        let last = URL(fileURLWithPath: normalizedPath).lastPathComponent
        return last.isEmpty ? normalizedPath : last
    }
}

extension TerminalSessionController: @preconcurrency LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // Slate keeps window sizing stable in this pass; SwiftTerm handles internal resize propagation.
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        self.shellReportedTitle = title.isEmpty ? nil : title
        updateDisplayedTitle()
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        self.currentDirectory = directory
        if shellReportedTitle == nil {
            updateDisplayedTitle()
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        self.isRunning = false
        self.shellReportedTitle = nil
        if self.title == "Shell" || self.title == "~" || self.title.isEmpty {
            self.title = "Exited"
        }
    }
}
