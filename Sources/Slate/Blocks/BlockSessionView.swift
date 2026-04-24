import AppKit
import SwiftUI

struct BlockSessionView: View {
    @ObservedObject var controller: BlockSessionController
    @EnvironmentObject private var settings: SettingsStore
    @State private var composerHeight: CGFloat = 30

    private let composerMinHeight: CGFloat = 30
    private let composerMaxHeight: CGFloat = 132
    private let contentHorizontalPadding: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            if let message = controller.unsupportedShellMessage {
                unsupportedShell(message)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(controller.blocks) { block in
                            BlockRow(
                                block: block,
                                controller: controller
                            )
                            .id(block.id)
                        }
                    }
                    .padding(.horizontal, contentHorizontalPadding)
                    .padding(.top, 54)
                    .padding(.bottom, 14)
                }
                .onChange(of: controller.blocks.count) { _, _ in
                    scrollToLatestBlock(proxy: proxy)
                }
                .onChange(of: controller.followScrollRequest) { _, _ in
                    scrollToLatestBlock(proxy: proxy)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Text(">")
                    .font(.system(size: max(12, settings.fontSize - 0.5), weight: .semibold, design: .monospaced))
                    .foregroundStyle(controller.isRunning ? Color(nsColor: .controlAccentColor) : Color.secondary)
                    .frame(width: 12, height: composerMinHeight, alignment: .center)
                    .textSelection(.disabled)

                ZStack(alignment: .topLeading) {
                    CommandComposer(
                        text: $controller.draftCommand,
                        measuredHeight: $composerHeight,
                        minHeight: composerMinHeight,
                        maxHeight: composerMaxHeight,
                        focusToken: controller.focusToken,
                        isEnabled: controller.isSupportedShell && controller.isRunning,
                        fontSize: settings.fontSize,
                        hasCompletions: !controller.completions.isEmpty,
                        onTextChange: {
                            controller.draftDidChange()
                        },
                        onAcceptCompletion: {
                            controller.acceptSelectedCompletion()
                        },
                        onMoveCompletion: { delta in
                            controller.moveCompletionSelection(delta: delta)
                        },
                        onSubmit: {
                            controller.submitDraft()
                        },
                        onInterrupt: {
                            controller.interrupt()
                        }
                    )
                    .frame(height: composerHeight)

                    if controller.draftCommand.isEmpty {
                        Text(controller.isRunning ? "Type a command" : "Shell is not running")
                            .font(.system(size: max(12, settings.fontSize - 0.5), design: .monospaced))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            .padding(.leading, 6)
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(.horizontal, 0)
            .padding(.vertical, 8)
            .background {
                Color(nsColor: .textBackgroundColor)
            }
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.55))
                    .frame(height: 1)
            }
            .overlay(alignment: .topLeading) {
                if !controller.completions.isEmpty {
                    CompletionPanel(
                        suggestions: controller.completions,
                        selectedIndex: controller.selectedCompletionIndex,
                        onSelect: { index in
                            controller.selectedCompletionIndex = index
                            _ = controller.acceptSelectedCompletion()
                        }
                    )
                    .offset(x: contentHorizontalPadding + 20, y: -min(CGFloat(controller.completions.count) * 30 + 10, 190))
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .foregroundStyle(Color(nsColor: .textColor))
        .onAppear {
            controller.startIfNeeded(settings: settings)
            controller.apply(settings: settings)
            DispatchQueue.main.async {
                controller.focusComposer()
            }
        }
        .onChange(of: settings.fontName) { _, _ in controller.apply(settings: settings) }
        .onChange(of: settings.fontSize) { _, _ in controller.apply(settings: settings) }
        .onChange(of: settings.cursorStyleRaw) { _, _ in controller.apply(settings: settings) }
        .onChange(of: controller.draftCommand) { _, _ in controller.draftDidChange() }
    }

    private func unsupportedShell(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13))
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.55))
    }

    private func scrollToLatestBlock(proxy: ScrollViewProxy) {
        guard let last = controller.blocks.last else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.16)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct BlockRow: View {
    let block: TerminalBlock
    @ObservedObject var controller: BlockSessionController
    @EnvironmentObject private var settings: SettingsStore
    @State private var outputHeight: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                statusDot
                Text(block.command)
                    .font(.system(size: settings.fontSize, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                blockActions
            }

            HStack(spacing: 8) {
                if let workingDirectory = block.workingDirectory {
                    Text(Self.displayPath(workingDirectory))
                }
                if let duration = block.duration {
                    Text(Self.format(duration: duration))
                }
                if let exitCode = block.exitCode {
                    Text("exit \(exitCode)")
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

            if !block.isCollapsed {
                if block.state == .rawTerminal {
                    BlockRawTerminalView(controller: controller)
                        .frame(minHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else if !block.output.isEmpty {
                    OutputTextView(text: block.output, fontSize: settings.fontSize, measuredHeight: $outputHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: outputHeight)
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.55))
                .frame(height: 1)
        }
        .contextMenu {
            Button("Rerun") { controller.rerun(block) }
            Button("Copy Command") { controller.copyCommand(block) }
            Button("Copy Output") { controller.copyOutput(block) }
            Button("Copy Block") { controller.copyBlock(block) }
            Button(block.isCollapsed ? "Expand" : "Collapse") { controller.toggleCollapsed(block) }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 7, height: 7)
            .padding(.top, 4)
    }

    private var blockActions: some View {
        HStack(spacing: 4) {
            Button {
                controller.rerun(block)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 22)
            }
            .help("Rerun")

            Button {
                controller.copyBlock(block)
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 24, height: 22)
            }
            .help("Copy Block")

            Button {
                controller.toggleCollapsed(block)
            } label: {
                Image(systemName: block.isCollapsed ? "chevron.right" : "chevron.down")
                    .frame(width: 24, height: 22)
            }
            .help(block.isCollapsed ? "Expand" : "Collapse")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var statusColor: Color {
        switch block.state {
        case .editing, .submitted, .running, .rawTerminal:
            Color(nsColor: .controlAccentColor)
        case .succeeded:
            Color(nsColor: .systemGreen)
        case .failed:
            Color(nsColor: .systemRed)
        case .interrupted:
            Color(nsColor: .systemOrange)
        }
    }

    private static func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~/" + path.dropFirst(home.count + 1)
        }
        return path
    }

    private static func format(duration: TimeInterval) -> String {
        if duration < 1 {
            return "\(Int(duration * 1000))ms"
        }
        return String(format: "%.1fs", duration)
    }
}

private struct BlockRawTerminalView: NSViewRepresentable {
    @ObservedObject var controller: BlockSessionController
    @EnvironmentObject private var settings: SettingsStore

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        controller.mountRawTerminal(in: container, settings: settings)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.mountRawTerminal(in: nsView, settings: settings)
    }
}

private struct CompletionPanel: View {
    let suggestions: [CompletionSuggestion]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(suggestions.prefix(6).enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    onSelect(index)
                } label: {
                    HStack(spacing: 10) {
                        Text(suggestion.title)
                            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(index == selectedIndex ? Color(nsColor: .selectedMenuItemTextColor) : Color.primary)
                            .lineLimit(1)
                        Spacer(minLength: 16)
                        Text(suggestion.detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(index == selectedIndex ? Color(nsColor: .selectedMenuItemTextColor).opacity(0.72) : Color.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                    .background {
                        if index == selectedIndex {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(nsColor: .controlAccentColor))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
    }
}

private struct CommandComposer: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let focusToken: UUID
    let isEnabled: Bool
    let fontSize: Double
    let hasCompletions: Bool
    let onTextChange: () -> Void
    let onAcceptCompletion: () -> Bool
    let onMoveCompletion: (Int) -> Bool
    let onSubmit: () -> Void
    let onInterrupt: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.font = NSFont.monospacedSystemFont(ofSize: max(12, fontSize - 0.5), weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.backgroundColor = .clear
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        textView.textStorage?.setAttributedString(ShellSyntaxHighlighter.attributedCommand(text, fontSize: fontSize, enabled: isEnabled))
        textView.isEditable = isEnabled

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = NSColor.clear.cgColor

        context.coordinator.textView = textView
        context.coordinator.remeasure()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.font = NSFont.monospacedSystemFont(ofSize: max(12, fontSize - 0.5), weight: .regular)
        if textView.string != text {
            context.coordinator.setHighlightedText(text, in: textView)
        }
        context.coordinator.applyHighlighting()
        textView.isEditable = isEnabled
        textView.textColor = isEnabled ? .textColor : .disabledControlTextColor
        scrollView.hasVerticalScroller = measuredHeight >= maxHeight - 1
        context.coordinator.remeasure()

        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CommandComposer
        weak var textView: NSTextView?
        var lastFocusToken: UUID?
        private var lastMeasuredHeight: CGFloat = 0

        init(_ parent: CommandComposer) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyHighlighting()
            parent.onTextChange()
            remeasure()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                return parent.onAcceptCompletion()
            }

            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                return parent.onMoveCompletion(1)
            }

            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                return parent.onMoveCompletion(-1)
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let event = NSApp.currentEvent
                let modifiers = event?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []

                if modifiers.contains(.shift) || modifiers.contains(.option) {
                    textView.insertText("\n", replacementRange: textView.selectedRange())
                    return true
                }

                if textView.string.contains("\n") && !modifiers.contains(.command) {
                    textView.insertText("\n", replacementRange: textView.selectedRange())
                } else {
                    parent.onSubmit()
                }
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onInterrupt()
                return true
            }

            return false
        }

        func setHighlightedText(_ text: String, in textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(ShellSyntaxHighlighter.attributedCommand(text, fontSize: parent.fontSize, enabled: parent.isEnabled))
            textView.setSelectedRange(NSRange(location: min(selectedRange.location, (text as NSString).length), length: 0))
        }

        func applyHighlighting() {
            guard let textView else { return }
            setHighlightedText(textView.string, in: textView)
        }

        func remeasure() {
            guard let textView, let textContainer = textView.textContainer else { return }
            textView.layoutManager?.ensureLayout(for: textContainer)
            let usedRect = textView.layoutManager?.usedRect(for: textContainer) ?? .zero
            let inset = textView.textContainerInset.height * 2
            let rawHeight = ceil(usedRect.height + inset)
            let nextHeight = min(parent.maxHeight, max(parent.minHeight, rawHeight))

            guard abs(nextHeight - lastMeasuredHeight) > 0.5 else { return }
            lastMeasuredHeight = nextHeight
            DispatchQueue.main.async {
                self.parent.measuredHeight = nextHeight
            }
        }
    }
}
