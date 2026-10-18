import Foundation
import Combine

@MainActor
final class FileCoordinator {
    private let tabState: TabState
    private let bookmarkStore: BookmarkStore
    private lazy var watcher = FileWatcher { [weak self] url in self?.reload(url) }
    /// Security-scoped URLs we started accessing; held while their tab is open so reloads can read
    private var scoped: Set<URL> = []
    private var tabsObserver: AnyCancellable?

    init(tabState: TabState, bookmarkStore: BookmarkStore) {
        self.tabState = tabState
        self.bookmarkStore = bookmarkStore
        // Closing a tab ends its watch and its sandbox access
        tabsObserver = tabState.$tabs
            .map { Set($0.map(\.url)) }
            .removeDuplicates()
            .scan((Set<URL>(), Set<URL>())) { previous, current in (previous.1, current) }
            .sink { [weak self] previous, current in
                previous.subtracting(current).forEach { self?.release($0) }
            }
    }

    /// Open a file from a URL (called from drag-drop, file picker, or bookmark restore)
    func open(url: URL) { open(url: url, remember: true) }

    private func open(url: URL, remember: Bool) {
        // True only for security-scoped (bookmark) URLs; Finder/panel/drag URLs are already reachable
        if url.startAccessingSecurityScopedResource() { scoped.insert(url) }

        switch read(url) {
        case .failure(let error):
            release(url)
            tabState.openError(url: url, message: error.message)
        case .success(let content):
            // Restored tabs open in the background; only a file the user opened is about to be shown
            if remember {
                PreviewRenderer.prefetch(content, folder: url.deletingLastPathComponent())
                bookmarkStore.save(url: url)
            }
            tabState.open(url: url, content: content)
            watcher.watch(url)
        }
    }

    /// Restore previously bookmarked files on launch
    func restoreBookmarks() {
        // Finder's open event arrives before restoration; that file must stay in front
        let selected = tabState.selectedTabID
        // Already bookmarked — re-saving would rewrite the plist once per restored file
        bookmarkStore.resolveAll().forEach { open(url: $0, remember: false) }
        if let selected { tabState.selectedTabID = selected }
    }

    /// The file changed on disk (usually the user saved in their editor)
    private func reload(_ url: URL) {
        guard let tab = tabState.tabs.first(where: { $0.url == url }) else { return }
        switch read(url) {
        case .success(let content) where content != tab.content:
            PreviewRenderer.prefetch(content, folder: url.deletingLastPathComponent())
            tabState.updateContent(id: tab.id, content: content)
        case .success:
            break   // touched, not changed
        case .failure:
            tabState.markUnavailable(id: tab.id)
        }
    }

    private func release(_ url: URL) {
        watcher.unwatch(url)
        if scoped.remove(url) != nil { url.stopAccessingSecurityScopedResource() }
    }

    private func read(_ url: URL) -> Result<String, ReadError> {
        var coordinatorError: NSError?
        var result: Result<String, ReadError> = .failure(ReadError("Could not read file."))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
            if let text = (try? String(contentsOf: coordinatedURL, encoding: .utf8))
                ?? (try? String(contentsOf: coordinatedURL, encoding: .isoLatin1)) {
                result = .success(text)
            }
        }
        return coordinatorError.map { .failure(ReadError($0.localizedDescription)) } ?? result
    }

    struct ReadError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
