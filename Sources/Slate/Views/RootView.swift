import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var workspace: WorkspaceModel

    @State private var tabStripWidth: CGFloat = 0

    private let tabMinWidth: CGFloat = 80
    private let tabMaxWidth: CGFloat = 180
    private let tabSpacing: CGFloat = 6

    var body: some View {
        Group {
            if let tab = workspace.selectedTab {
                TerminalHostView(controller: tab.controller)
                    .environmentObject(settings)
                    .background(Color(nsColor: .textBackgroundColor))
                    .id(tab.id)
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .foregroundStyle(Color(nsColor: .textColor))
        .background(
            WindowConfigurator(tabBar: tabBarView)
        )
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                workspace.focusSelectedTerminal()
            }
        }
        .onChange(of: workspace.selectedTabID) { _, _ in
            DispatchQueue.main.async {
                workspace.focusSelectedTerminal()
            }
        }
        .alert("Close this tab?", isPresented: closeAlertBinding) {
            Button("Cancel", role: .cancel) {
                workspace.cancelPendingClose()
            }
            Button("Close Tab", role: .destructive) {
                workspace.confirmPendingClose()
            }
        } message: {
            Text("A shell is still running in this tab. Closing it will terminate the current session.")
        }
    }

    private var tabBarView: some View {
        HStack(spacing: 10) {
            tabStrip

            Spacer(minLength: 10)

            Button {
                workspace.newTab(settings: settings)
                DispatchQueue.main.async {
                    workspace.focusSelectedTerminal()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .contentShape(Circle())
            .help("New Tab")
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity)
    }

    private var tabStrip: some View {
        let count = CGFloat(workspace.tabs.count)
        let totalSpacing = max(0, count - 1) * tabSpacing
        let ideal = tabStripWidth > 0 && count > 0
            ? (tabStripWidth - totalSpacing) / count
            : tabMaxWidth
        let tabWidth = min(tabMaxWidth, max(tabMinWidth, ideal))
        let needsScroll = ideal < tabMinWidth

        return Group {
            if needsScroll {
                ScrollView(.horizontal, showsIndicators: false) {
                    chipRow(width: tabMinWidth)
                }
            } else {
                chipRow(width: tabWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { tabStripWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, new in tabStripWidth = new }
            }
        }
    }

    @ViewBuilder
    private func chipRow(width: CGFloat) -> some View {
        HStack(spacing: tabSpacing) {
            ForEach(workspace.tabs) { tab in
                TabChip(
                    tab: tab,
                    isSelected: tab.id == workspace.selectedTabID,
                    onSelect: {
                        workspace.selectedTabID = tab.id
                        DispatchQueue.main.async {
                            workspace.focusSelectedTerminal()
                        }
                    },
                    onClose: {
                        workspace.selectedTabID = tab.id
                        workspace.requestClose(tab: tab)
                    }
                )
                .frame(width: width)
                .environmentObject(settings)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("Slate")
                .font(.system(size: 24, weight: .semibold))
            Button("New Terminal") {
                workspace.newTab(settings: settings)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var closeAlertBinding: Binding<Bool> {
        Binding(
            get: { workspace.pendingCloseTab != nil },
            set: { newValue in
                if !newValue {
                    workspace.cancelPendingClose()
                }
            }
        )
    }
}

struct TabChip: View {
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var controller: TerminalSessionController
    let tab: TerminalTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovered = false

    init(tab: TerminalTab, isSelected: Bool, onSelect: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.tab = tab
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onClose = onClose
        _controller = ObservedObject(wrappedValue: tab.controller)
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(controller.isRunning ? Color(nsColor: .systemGreen) : Color(nsColor: .tertiaryLabelColor))
                        .frame(width: 6, height: 6)
                    Text(controller.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isSelected || isHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .hidden()
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 26)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .selectedContentBackgroundColor).opacity(0.18))
            } else if isHovered {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .foregroundStyle(isSelected ? .primary : .secondary)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("Close Tab") {
                onClose()
            }
        }
    }
}
