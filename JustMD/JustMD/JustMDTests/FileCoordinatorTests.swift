import XCTest
@testable import JustMD

@MainActor final class FileCoordinatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeTempFile(in dir: URL, name: String = "test.md", content: String = "# Hello") -> URL {
        let url = dir.appendingPathComponent(name)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Tests

    func test_open_addsTab() async {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storePath = dir.appendingPathComponent("bookmarks.plist")
        let fileURL = makeTempFile(in: dir)

        let tabState = TabState()
        let bookmarkStore = BookmarkStore(storePath: storePath)
        let coordinator = FileCoordinator(tabState: tabState, bookmarkStore: bookmarkStore)

        coordinator.open(url: fileURL)

        XCTAssertEqual(tabState.tabs.count, 1)
    }

    func test_open_setsContent() async {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storePath = dir.appendingPathComponent("bookmarks.plist")
        let markdownText = "# Hello World"
        let fileURL = makeTempFile(in: dir, content: markdownText)

        let tabState = TabState()
        let bookmarkStore = BookmarkStore(storePath: storePath)
        let coordinator = FileCoordinator(tabState: tabState, bookmarkStore: bookmarkStore)

        coordinator.open(url: fileURL)

        XCTAssertEqual(tabState.tabs.count, 1)
        XCTAssertTrue(tabState.tabs[0].content.contains(markdownText))
    }

    func test_open_nonexistentFile_addsErrorTab() async {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storePath = dir.appendingPathComponent("bookmarks.plist")
        let nonExistentURL = dir.appendingPathComponent("does_not_exist.md")

        let tabState = TabState()
        let bookmarkStore = BookmarkStore(storePath: storePath)
        let coordinator = FileCoordinator(tabState: tabState, bookmarkStore: bookmarkStore)

        coordinator.open(url: nonExistentURL)

        XCTAssertEqual(tabState.tabs.count, 1)
        XCTAssertTrue(tabState.tabs[0].isErrorTab)
    }

    func test_restoreBookmarks_restoresSavedFile() async {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storePath = dir.appendingPathComponent("bookmarks.plist")
        let fileURL = makeTempFile(in: dir)

        let tabState = TabState()
        let bookmarkStore = BookmarkStore(storePath: storePath)
        let coordinator = FileCoordinator(tabState: tabState, bookmarkStore: bookmarkStore)

        // Open the file first — this calls bookmarkStore.save internally
        coordinator.open(url: fileURL)
        XCTAssertEqual(tabState.tabs.count, 1, "Should have 1 tab after initial open")

        // Create a new coordinator with the same bookmarkStore and restore
        let coordinator2 = FileCoordinator(tabState: tabState, bookmarkStore: bookmarkStore)
        coordinator2.restoreBookmarks()

        // tabState deduplicates — the URL is already open, so count stays at 1
        XCTAssertEqual(tabState.tabs.count, 1, "Tabs should not duplicate after restoreBookmarks")
    }

    func test_restoreBookmarks_keepsSelectionOnFileOpenedAtLaunch() async {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storePath = dir.appendingPathComponent("bookmarks.plist")
        let previous = (1...5).map { makeTempFile(in: dir, name: "previous\($0).md") }
        let launched = makeTempFile(in: dir, name: "launched.md")

        // A previous session remembered several files (bookmark order is unspecified, so use
        // enough of them that a correct result can't come from launched.md being restored last)
        let earlier = FileCoordinator(tabState: TabState(), bookmarkStore: BookmarkStore(storePath: storePath))
        previous.forEach(earlier.open)

        // Cold launch: the Finder open event arrives before restoration runs
        let tabState = TabState()
        let coordinator = FileCoordinator(tabState: tabState, bookmarkStore: BookmarkStore(storePath: storePath))
        coordinator.open(url: launched)
        coordinator.restoreBookmarks()

        XCTAssertEqual(tabState.tabs.count, 6)
        XCTAssertEqual(tabState.selectedTab?.url, launched, "Restored tabs must not steal focus from the opened file")
    }

    func test_restoreBookmarks_withNothingOpen_selectsARestoredTab() async {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storePath = dir.appendingPathComponent("bookmarks.plist")
        let previous = makeTempFile(in: dir, name: "previous.md")
        FileCoordinator(tabState: TabState(), bookmarkStore: BookmarkStore(storePath: storePath)).open(url: previous)

        let tabState = TabState()
        FileCoordinator(tabState: tabState, bookmarkStore: BookmarkStore(storePath: storePath)).restoreBookmarks()

        XCTAssertEqual(tabState.selectedTab?.url, previous)
    }
}
