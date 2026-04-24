@preconcurrency import AppKit
import Darwin
import Foundation
@preconcurrency import SwiftTerm

@MainActor
final class TerminalSessionController: NSObject, ObservableObject {
    @Published var title: String = "~"
    @Published var currentDirectory: String?
    @Published var isRunning: Bool = true
    @Published var hasForegroundProcess: Bool = false

    var onExit: (() -> Void)?

    let terminalView: LocalProcessTerminalView
    private var didStart = false
    private var shellReportedTitle: String?
    private var foregroundPollTask: Task<Void, Never>?

    override init() {
        self.terminalView = LocalProcessTerminalView(frame: .zero)
        self.terminalView.translatesAutoresizingMaskIntoConstraints = false
        self.terminalView.wantsLayer = true
        self.terminalView.nativeForegroundColor = .textColor
        self.terminalView.nativeBackgroundColor = .textBackgroundColor
        self.terminalView.caretColor = .controlAccentColor
        self.terminalView.selectedTextBackgroundColor = .selectedTextBackgroundColor
        self.terminalView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
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
        terminalView.nativeForegroundColor = .textColor
        terminalView.nativeBackgroundColor = .textBackgroundColor
        terminalView.caretColor = .controlAccentColor
        terminalView.selectedTextBackgroundColor = .selectedTextBackgroundColor
        terminalView.wantsLayer = true
        terminalView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
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
        stopForegroundPolling()
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
        startForegroundPolling()
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
        stopForegroundPolling()
        self.isRunning = false
        self.hasForegroundProcess = false
        self.shellReportedTitle = nil
        if self.title == "Shell" || self.title == "~" || self.title.isEmpty {
            self.title = "Exited"
        }
        onExit?()
    }
}

@MainActor
private extension TerminalSessionController {
    func startForegroundPolling() {
        guard foregroundPollTask == nil else { return }

        foregroundPollTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.refreshForegroundProcessState()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    func stopForegroundPolling() {
        foregroundPollTask?.cancel()
        foregroundPollTask = nil
    }

    func refreshForegroundProcessState() {
        guard terminalView.process.running else {
            hasForegroundProcess = false
            return
        }

        let shellPid = terminalView.process.shellPid
        let childfd = terminalView.process.childfd

        guard shellPid > 0, childfd >= 0 else {
            hasForegroundProcess = false
            return
        }

        let foregroundGroup = tcgetpgrp(childfd)
        hasForegroundProcess = foregroundGroup > 0 && foregroundGroup != shellPid
    }
}
