import Foundation
import Combine

@MainActor
final class TabState: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var selectedTabID: UUID?

    var selectedTab: Tab? {
        tabs.first { $0.id == selectedTabID }
    }

    func open(url: URL, content: String) {
        if let existing = tabs.first(where: { $0.url == url }) {
            selectedTabID = existing.id
            return
        }
        let tab = Tab(url: url, content: content)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func openError(url: URL, message: String) {
        if let existing = tabs.first(where: { $0.url == url }) {
            selectedTabID = existing.id
            return
        }
        let tab = Tab(url: url, content: message, isErrorTab: true)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func close(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
    }

    // MARK: Keyboard navigation (⌃Tab, ⌃⇧Tab, ⌘1…⌘9, ⌘W)

    private var selectedIndex: Int? { tabs.firstIndex { $0.id == selectedTabID } }

    func selectNext() { step(by: 1) }
    func selectPrevious() { step(by: -1) }

    private func step(by offset: Int) {
        guard !tabs.isEmpty else { return }
        let current = selectedIndex ?? 0
        selectedTabID = tabs[(current + offset + tabs.count) % tabs.count].id   // wraps both ways
    }

    func select(index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedTabID = tabs[index].id
    }

    /// ⌘9 means "last tab" in every Mac tabbed app, whatever the count
    func selectLast() { tabs.last.map { selectedTabID = $0.id } }

    func closeSelected() { selectedTabID.map(close) }

    func updateContent(id: UUID, content: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].content = content
    }

    func markUnavailable(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].isUnavailable = true
    }
}
