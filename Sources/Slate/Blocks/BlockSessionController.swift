@preconcurrency import AppKit
import Darwin
import Foundation
@preconcurrency import SwiftTerm

@MainActor
final class BlockSessionController: NSObject, ObservableObject {
    enum SuggestionMode {
        case none
        case completion
        case history
    }

    @Published var title: String = "Blocks"
    @Published var currentDirectory: String?
    @Published var isRunning: Bool = true
    @Published var hasForegroundProcess: Bool = false
    @Published var blocks: [TerminalBlock] = []
    @Published var draftCommand: String = ""
    @Published var completions: [CompletionSuggestion] = []
    @Published var suggestionMode: SuggestionMode = .none
    @Published var selectedCompletionIndex: Int = 0
    @Published var followScrollRequest = UUID()
    @Published var focusToken = UUID()
    @Published var unsupportedShellMessage: String?

    var onExit: (() -> Void)?

    let rawTerminalView: BlockCaptureTerminalView
    private let processHost = BlockProcessHost()
    private let completionEngine: BlockCompletionEngine
    private let sessionStore: BlockSessionStore

    private let tabID: UUID
    private let shell: String
    private let startupDirectory: String
    private var parser = BlockEventParser()
    private var didStart = false
    private var shellIntegrationReady = false
    private var activeBlockID: UUID?
    private var foregroundPollTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var isApplyingHistorySelection = false
    private var suppressNextDraftChange = false

    init(tabID: UUID, settings: SettingsStore, restoredSession: PersistedSession? = nil, sessionStore: BlockSessionStore = .shared) {
        self.tabID = tabID
        self.shell = restoredSession?.shell ?? settings.resolvedShell
        self.startupDirectory = restoredSession?.startupDirectory ?? settings.resolvedStartupDirectory
        self.currentDirectory = restoredSession?.currentDirectory ?? restoredSession?.startupDirectory ?? settings.resolvedStartupDirectory
        self.rawTerminalView = BlockCaptureTerminalView(frame: .zero)
        self.completionEngine = BlockCompletionEngine(shell: restoredSession?.shell ?? settings.resolvedShell)
        self.sessionStore = sessionStore
        super.init()

        if let restoredSession {
            self.blocks = restoredSession.blocks.map { persistedBlock in
                var block = persistedBlock.terminalBlock
                if [.submitted, .running, .rawTerminal].contains(block.state) {
                    block.state = .interrupted
                    block.endedAt = block.endedAt ?? Date()
                    block.exitCode = block.exitCode ?? 130
                }
                return block
            }
            self.title = restoredSession.title
        }
        apply(settings: settings)
        processHost.onDataReceived = { [weak self] slice in
            Task { @MainActor in
                self?.handleOutput(slice)
            }
        }
        processHost.onTerminated = { [weak self] exitCode in
            Task { @MainActor in
                self?.handleProcessTerminated(exitCode: exitCode)
            }
        }
        updateDisplayedTitle()
        persistSession()

        if isSupportedShell {
            isRunning = false
        } else {
            isRunning = false
            unsupportedShellMessage = "Block Mode currently supports zsh. Switch the default session style to Classic for \(URL(fileURLWithPath: shell).lastPathComponent)."
        }
    }

    var isSupportedShell: Bool {
        URL(fileURLWithPath: shell).lastPathComponent == "zsh"
    }

    var visibleSuggestions: [CompletionSuggestion] {
        suggestionMode == .none ? [] : completions
    }

    func startIfNeeded(settings: SettingsStore) {
        guard !didStart, isSupportedShell else { return }
        apply(settings: settings)

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Slate"
        environment["TERM_PROGRAM_VERSION"] = "0.1"
        environment["SLATE_BLOCK_MODE"] = "1"
        environment["SLATE_CLASSIC_MODE"] = nil
        if let integrationDirectory = prepareZshIntegrationDirectory() {
            environment["ZDOTDIR"] = integrationDirectory.path
        }

        processHost.start(
            executable: shell,
            args: ["-i"],
            environment: environment.map { "\($0.key)=\($0.value)" },
            execName: URL(fileURLWithPath: shell).lastPathComponent,
            currentDirectory: startupDirectory
        )
        didStart = true
        isRunning = true
        unsupportedShellMessage = nil
        startForegroundPolling()
    }

    func mountRawTerminal(in containerView: NSView, settings: SettingsStore) {
        startIfNeeded(settings: settings)
        if rawTerminalView.superview !== containerView {
            rawTerminalView.removeFromSuperview()
            rawTerminalView.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(rawTerminalView)
            NSLayoutConstraint.activate([
                rawTerminalView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                rawTerminalView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                rawTerminalView.topAnchor.constraint(equalTo: containerView.topAnchor),
                rawTerminalView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
        }
        apply(settings: settings)
    }

    func apply(settings: SettingsStore) {
        rawTerminalView.font = NSFont(name: settings.fontName, size: settings.fontSize) ?? NSFont.monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
        rawTerminalView.nativeForegroundColor = .textColor
        rawTerminalView.nativeBackgroundColor = .textBackgroundColor
        rawTerminalView.caretColor = .controlAccentColor
        rawTerminalView.selectedTextBackgroundColor = .selectedTextBackgroundColor
        rawTerminalView.wantsLayer = true
        rawTerminalView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        rawTerminalView.changeScrollback(settings.scrollbackLimit)
        rawTerminalView.getTerminal().setCursorStyle(settings.cursorStyle.swiftTermStyle)
        rawTerminalView.onDataReceived = { [weak self] slice in
            Task { @MainActor in
                self?.handleOutput(slice)
            }
        }
    }

    func focusComposer() {
        focusToken = UUID()
    }

    func draftDidChange() {
        if suppressNextDraftChange {
            suppressNextDraftChange = false
            return
        }

        guard !isApplyingHistorySelection else { return }

        if draftCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if suggestionMode != .history {
                dismissSuggestions()
            }
            return
        }

        completions = completionEngine.suggestions(for: CompletionContext(
            text: draftCommand,
            currentDirectory: currentDirectory,
            history: blocks.map(\.command),
            shell: shell
        ))
        selectedCompletionIndex = min(selectedCompletionIndex, max(0, completions.count - 1))
        suggestionMode = completions.isEmpty ? .none : .completion
    }

    func moveSuggestionSelection(delta: Int) -> Bool {
        if visibleSuggestions.isEmpty, draftCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, delta < 0 {
            return showHistorySuggestions()
        }

        guard !visibleSuggestions.isEmpty else { return false }
        selectedCompletionIndex = (selectedCompletionIndex + delta + completions.count) % completions.count
        if suggestionMode == .history {
            applySelectedHistorySuggestionToDraft()
        }
        return true
    }

    func acceptSelectedSuggestion() -> Bool {
        guard visibleSuggestions.indices.contains(selectedCompletionIndex) else { return false }
        if suggestionMode == .history {
            applySelectedHistorySuggestionToDraft()
            dismissSuggestions()
            focusComposer()
            return true
        }

        draftCommand = completionEngine.apply(completions[selectedCompletionIndex], to: draftCommand)
        draftDidChange()
        focusComposer()
        return true
    }

    func showHistorySuggestions() -> Bool {
        var seenCommands = Set<String>()
        let commands = blocks
            .map(\.command)
            .reversed()
            .filter { seenCommands.insert($0).inserted }
            .prefix(24)
            .map {
                CompletionSuggestion(
                    title: $0,
                    detail: "History",
                    replacement: $0,
                    kind: .history
                )
            }

        guard !commands.isEmpty else { return false }
        completions = Array(commands)
        suggestionMode = .history
        selectedCompletionIndex = 0
        applySelectedHistorySuggestionToDraft()
        focusComposer()
        return true
    }

    func dismissSuggestions() {
        completions = []
        suggestionMode = .none
        selectedCompletionIndex = 0
    }

    func submitDraft() {
        let command = draftCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, isSupportedShell, processHost.running else { return }
        draftCommand = ""
        dismissSuggestions()

        let block = TerminalBlock(
            command: command,
            workingDirectory: currentDirectory,
            shell: shell,
            startedAt: Date(),
            state: .submitted
        )
        activeBlockID = block.id
        blocks.append(block)
        persistSession()

        processHost.send(text: command + "\n")
    }

    func rerun(_ block: TerminalBlock) {
        draftCommand = block.command
        submitDraft()
    }

    func insertCommand(_ command: String) {
        draftCommand = command
        dismissSuggestions()
        focusComposer()
    }

    func rerunCommand(_ command: String) {
        draftCommand = command
        submitDraft()
    }

    func toggleCollapsed(_ block: TerminalBlock) {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        blocks[index].isCollapsed.toggle()
        persistSession()
    }

    func clearHistory() {
        blocks.removeAll()
        activeBlockID = nil
        sessionStore.clearSession(id: tabID)
    }

    func copyCommand(_ block: TerminalBlock) {
        writeToPasteboard(block.command)
    }

    func copyOutput(_ block: TerminalBlock) {
        writeToPasteboard(ANSIOutputRenderer.plainText(block.output))
    }

    func copyBlock(_ block: TerminalBlock) {
        var text = "$ \(block.command)"
        if !block.output.isEmpty {
            text += "\n\(ANSIOutputRenderer.plainText(block.output))"
        }
        writeToPasteboard(text)
    }

    func interrupt() {
        processHost.send(bytes: [3])
        if let index = activeBlockIndex {
            blocks[index].state = .interrupted
            blocks[index].endedAt = Date()
            blocks[index].exitCode = 130
            persistSession()
        }
    }

    func terminate() {
        stopForegroundPolling()
        persistenceTask?.cancel()
        persistSession()
        processHost.terminate()
    }

    private func applySelectedHistorySuggestionToDraft() {
        guard suggestionMode == .history,
              completions.indices.contains(selectedCompletionIndex) else {
            return
        }
        isApplyingHistorySelection = true
        suppressNextDraftChange = true
        draftCommand = completions[selectedCompletionIndex].replacement
        isApplyingHistorySelection = false
        focusComposer()
    }

    private func handleOutput(_ slice: ArraySlice<UInt8>) {
        let result = parser.parse(bytes: slice)

        for event in result.events {
            handle(event)
        }

        if result.enteredAlternateScreen, let index = activeBlockIndex {
            blocks[index].state = .rawTerminal
        }
        if result.exitedAlternateScreen, let index = activeBlockIndex {
            blocks[index].state = .running
        }

        let visible = Self.cleanedVisibleOutput(result.visibleText)
        if !visible.isEmpty, let index = activeBlockIndex, shellIntegrationReady, blocks[index].state != .submitted {
            blocks[index].output += visible
            followScrollRequest = UUID()
            schedulePersistence()
        }
    }

    private func handle(_ event: BlockShellEvent) {
        switch event {
        case .prompt:
            shellIntegrationReady = true
        case let .commandStart(command):
            if let command, Self.isInternalIntegrationCommand(command) {
                return
            }
            if let index = activeBlockIndex {
                blocks[index].state = .running
                blocks[index].startedAt = blocks[index].startedAt ?? Date()
                persistSession()
            } else if let command, !command.isEmpty {
                let block = TerminalBlock(
                    command: command,
                    workingDirectory: currentDirectory,
                    shell: shell,
                    startedAt: Date(),
                    state: .running
                )
                activeBlockID = block.id
                blocks.append(block)
                persistSession()
            }
        case .outputStart:
            if let index = activeBlockIndex {
                blocks[index].state = .running
                persistSession()
            }
        case let .commandFinished(status):
            if let index = activeBlockIndex {
                blocks[index].exitCode = status
                blocks[index].endedAt = Date()
                blocks[index].state = status == 0 ? .succeeded : .failed
                activeBlockID = nil
                followScrollRequest = UUID()
                persistSession()
            }
        case let .cwd(directory):
            currentDirectory = directory
            updateDisplayedTitle()
            persistSession()
        }
    }

    private var activeBlockIndex: Int? {
        guard let activeBlockID else { return nil }
        return blocks.firstIndex { $0.id == activeBlockID }
    }

    private func prepareZshIntegrationDirectory() -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlateBlockZDOTDIR", isDirectory: true)
            .appendingPathComponent(tabID.uuidString, isDirectory: true)
        let zshrc = directory.appendingPathComponent(".zshrc")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.zshIntegrationScript.write(to: zshrc, atomically: true, encoding: .utf8)
            return directory
        } catch {
            unsupportedShellMessage = "Block Mode could not prepare zsh integration: \(error.localizedDescription)"
            return nil
        }
    }

    private static let zshIntegrationScript = """
        emulate -L zsh
        setopt prompt_subst no_prompt_cr
        PROMPT=''
        RPROMPT=''
        PS1=''
        RPS1=''
        PROMPT_EOL_MARK=''
        function __slate_osc() { printf '\\e]%s\\a' "$1" }
        function preexec() {
          local encoded
          encoded=$(printf '%s' "$1" | /usr/bin/base64 | tr -d '\\n')
          __slate_osc "133;B;cmd64=$encoded"
          __slate_osc "133;C"
        }
        function precmd() {
          local slate_status=$?
          __slate_osc "133;D;$slate_status"
          __slate_osc "7;file://$HOST$PWD"
          __slate_osc "133;A"
        }
        function chpwd() {
          __slate_osc "7;file://$HOST$PWD"
        }
        __slate_osc "7;file://$HOST$PWD"
        __slate_osc "133;A"

        """

    private static func isInternalIntegrationCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("__slate_osc")
            || trimmed.contains("slate_status")
            || trimmed.contains("PROMPT_EOL_MARK")
            || trimmed.contains("function precmd")
            || trimmed.contains("function chpwd")
            || trimmed.contains("function preexec")
            || trimmed == "PS1=''"
            || trimmed.hasPrefix("PROMPT=")
            || trimmed.hasPrefix("RPROMPT=")
            || trimmed.hasPrefix("RPS1=")
    }

    private static func cleanedVisibleOutput(_ output: String) -> String {
        output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed != "%"
            }
            .joined(separator: "\n")
    }

    private func updateDisplayedTitle() {
        guard let currentDirectory else {
            title = "Blocks"
            return
        }
        title = Self.displayTitle(for: currentDirectory)
    }

    private static func displayTitle(for directory: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if directory == home {
            return "~"
        }
        if directory.hasPrefix(home + "/") {
            return "~/" + directory.dropFirst(home.count + 1)
        }
        let last = URL(fileURLWithPath: directory).lastPathComponent
        return last.isEmpty ? directory : last
    }

    private func writeToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([text as NSString])
    }
    private func handleProcessTerminated(exitCode: Int32?) {
        stopForegroundPolling()
        isRunning = false
        hasForegroundProcess = false
        if let index = activeBlockIndex {
            blocks[index].exitCode = exitCode
            blocks[index].endedAt = Date()
            blocks[index].state = (exitCode == 0) ? .succeeded : .interrupted
            activeBlockID = nil
            persistSession()
        }
        unsupportedShellMessage = "The Block Mode shell exited\(Self.describeTermination(exitCode)). New commands cannot run in this tab."
    }

    private func persistSession() {
        sessionStore.saveSession(
            id: tabID,
            shell: shell,
            startupDirectory: startupDirectory,
            currentDirectory: currentDirectory,
            title: title,
            blocks: blocks
        )
    }

    private func schedulePersistence() {
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self else { return }
            self.persistSession()
        }
    }
    
    private static func describeTermination(_ status: Int32?) -> String {
        guard let status else { return "" }
        let statusBits = status & 0x7f
        if statusBits == 0 {
            return " with status \((status >> 8) & 0xff)"
        }
        if statusBits != 0x7f {
            return " after signal \(statusBits)"
        }
        return " with status \(status)"
    }
}

@MainActor
private extension BlockSessionController {
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
        guard processHost.running else {
            hasForegroundProcess = false
            return
        }

        let shellPid = processHost.shellPid
        let childfd = processHost.childfd

        guard shellPid > 0, childfd >= 0 else {
            hasForegroundProcess = false
            return
        }

        let foregroundGroup = tcgetpgrp(childfd)
        hasForegroundProcess = foregroundGroup > 0 && foregroundGroup != shellPid
    }
}

private extension String {
    var removingTerminalControlSequences: String {
        var result = ""
        var index = startIndex

        while index < endIndex {
            if self[index] == "\u{1B}" {
                let next = self.index(after: index)
                guard next < endIndex else { break }
                if self[next] == "[" {
                    index = self.index(after: next)
                    while index < endIndex {
                        let scalar = self[index].unicodeScalars.first?.value ?? 0
                        let current = self[index]
                        index = self.index(after: index)
                        if scalar >= 0x40 && scalar <= 0x7E && current != ";" && current != "?" {
                            break
                        }
                    }
                    continue
                }
                index = self.index(after: next)
                continue
            }

            result.append(self[index])
            index = self.index(after: index)
        }

        return result
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
