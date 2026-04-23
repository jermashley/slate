import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var workspace: WorkspaceModel

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if let tab = workspace.selectedTab {
                    TerminalHostView(controller: tab.controller)
                        .environmentObject(settings)
                        .background(settings.theme.background)
                        .id(tab.id)
                } else {
                    emptyState
                }
            }
            .padding(.top, 44)

            topBar
        }
        .background(settings.theme.background)
        .foregroundStyle(settings.theme.foreground)
        .ignoresSafeArea(.container, edges: .top)
        .background(
            WindowConfigurator(backgroundColor: settings.theme.nsBackground)
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

    private var topBar: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 10) {
                tabStrip

                Spacer(minLength: 8)

                Button {
                    workspace.newTab(settings: settings)
                    DispatchQueue.main.async {
                        workspace.focusSelectedTerminal()
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(settings.theme.muted)
                .help("New Tab")
            }
            .padding(.leading, 86)
            .padding(.trailing, 14)
            .frame(height: 42)

            VStack(spacing: 0) {
                Spacer()
                Divider()
                    .opacity(0.25)
            }
            .frame(height: 42)
        }
        .background(settings.theme.background.opacity(0.98))
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
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
                    .environmentObject(settings)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        .fill(controller.isRunning ? settings.theme.accent : settings.theme.muted)
                        .frame(width: 6, height: 6)
                    Text(controller.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            if isSelected || isHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(settings.theme.muted)
                .opacity(1)
            } else {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .hidden()
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(isSelected ? settings.theme.selection.opacity(0.9) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .foregroundStyle(isSelected ? settings.theme.foreground : settings.theme.muted)
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
