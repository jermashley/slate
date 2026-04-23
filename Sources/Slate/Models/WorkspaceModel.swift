import Foundation

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var tabs: [TerminalTab] = []
    @Published var selectedTabID: TerminalTab.ID?
    @Published var pendingCloseTabID: TerminalTab.ID?

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
        let tab = TerminalTab()
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func requestCloseSelectedTab() {
        guard let selectedTab else { return }
        requestClose(tab: selectedTab)
    }

    func requestClose(tab: TerminalTab) {
        if tab.controller.isRunning {
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
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tab.controller.terminate()
        tabs.remove(at: index)

        if tabs.isEmpty {
            selectedTabID = nil
        } else {
            let nextIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[nextIndex].id
        }
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
        selectedTab?.controller.focus()
    }
}
