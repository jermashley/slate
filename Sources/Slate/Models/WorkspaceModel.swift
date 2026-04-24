import Foundation

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var tabs: [TerminalTab]
    @Published var selectedTabID: TerminalTab.ID?
    @Published var pendingCloseTabID: TerminalTab.ID?

    init(settings: SettingsStore) {
        let initialTab = Self.makeTab(settings: settings)
        tabs = [initialTab]
        selectedTabID = initialTab.id
        installExitHandler(for: initialTab)
    }

    var selectedTab: TerminalTab? {
        guard let selectedTabID else { return tabs.first }
        return tabs.first { $0.id == selectedTabID }
    }

    var pendingCloseTab: TerminalTab? {
        guard let pendingCloseTabID else { return nil }
        return tabs.first { $0.id == pendingCloseTabID }
    }

    func ensureInitialTab(settings: SettingsStore) {
        guard tabs.isEmpty else { return }
        newTab(settings: settings)
    }

    func newTab(settings: SettingsStore) {
        let tab = Self.makeTab(settings: settings)
        installExitHandler(for: tab)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func requestCloseSelectedTab() {
        guard let selectedTab else { return }
        requestClose(tab: selectedTab)
    }

    func requestClose(tab: TerminalTab) {
        if tab.hasForegroundProcess {
            pendingCloseTabID = tab.id
        } else {
            forceClose(tab: tab)
        }
    }

    func confirmPendingClose() {
        guard let tab = pendingCloseTab else { return }
        pendingCloseTabID = nil
        forceClose(tab: tab)
    }

    func cancelPendingClose() {
        pendingCloseTabID = nil
    }

    func forceClose(tab: TerminalTab) {
        forceClose(tab: tab, terminate: true)
    }

    func selectNextTab() {
        guard tabs.count > 1, let selectedTabID, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        self.selectedTabID = tabs[(index + 1) % tabs.count].id
    }

    func selectPreviousTab() {
        guard tabs.count > 1, let selectedTabID, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        self.selectedTabID = tabs[(index - 1 + tabs.count) % tabs.count].id
    }

    func focusSelectedTerminal() {
        selectedTab?.focus()
    }

    func showFindInSelectedTab() {
        switch selectedTab?.style {
        case .classic:
            selectedTab?.classicController?.showFind()
        case .block:
            selectedTab?.focus()
        case .none:
            break
        }
    }

    func clearSelectedTabHistory() {
        selectedTab?.clearHistory()
        selectedTab?.focus()
    }

    private static func makeTab(settings: SettingsStore) -> TerminalTab {
        TerminalTab(style: settings.sessionStyle, settings: settings)
    }

    private func installExitHandler(for tab: TerminalTab) {
        tab.installExitHandler { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.forceClose(tab: tab, terminate: false)
        }
    }

    private func forceClose(tab: TerminalTab, terminate: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if terminate {
            tab.clearExitHandler()
            tab.terminate()
        }
        tabs.remove(at: index)

        if tabs.isEmpty {
            selectedTabID = nil
        } else {
            let nextIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[nextIndex].id
        }
    }
}
