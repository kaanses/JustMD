import XCTest
@testable import JustMD

@MainActor
final class FileWatcherTests: XCTestCase {

    private func tempFile(_ content: String = "one") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("doc.md")
        try content.write(to: url, atomically: false, encoding: .utf8)
        return url
    }

    /// Plain in-place write, like `echo >> file`
    private func appendInPlace(_ url: URL, _ text: String) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    func test_inPlaceWrite_isReported() async throws {
        let url = try tempFile()
        let changed = expectation(description: "change")
        let watcher = FileWatcher { if $0 == url { changed.fulfill() } }
        watcher.watch(url)
        try appendInPlace(url, " two")
        await fulfillment(of: [changed], timeout: 2)
    }

    func test_atomicReplace_isReported_andWatchingContinues() async throws {
        let url = try tempFile()
        var changes = 0
        let first = expectation(description: "replace")
        let second = expectation(description: "edit after replace")
        let watcher = FileWatcher { _ in
            changes += 1
            if changes == 1 { first.fulfill() } else if changes == 2 { second.fulfill() }
        }
        watcher.watch(url)

        // Editors save by writing a temp file and renaming it over the original
        try "replaced".write(to: url, atomically: true, encoding: .utf8)
        await fulfillment(of: [first], timeout: 2)

        try await Task.sleep(for: .milliseconds(300))   // let the watcher re-arm on the new file
        try appendInPlace(url, " again")
        await fulfillment(of: [second], timeout: 2)
    }

    func test_unwatch_stopsReports() async throws {
        let url = try tempFile()
        let changed = expectation(description: "no change")
        changed.isInverted = true
        let watcher = FileWatcher { _ in changed.fulfill() }
        watcher.watch(url)
        watcher.unwatch(url)
        try appendInPlace(url, " two")
        await fulfillment(of: [changed], timeout: 0.6)
    }

    func test_openFile_reloadsWhenChangedOnDisk() async throws {
        let url = try tempFile("# Before")
        let store = BookmarkStore(storePath: url.deletingLastPathComponent().appendingPathComponent("bookmarks.plist"))
        let tabs = TabState()
        let coordinator = FileCoordinator(tabState: tabs, bookmarkStore: store)
        coordinator.open(url: url)
        XCTAssertEqual(tabs.tabs.first?.content, "# Before")

        try "# After".write(to: url, atomically: true, encoding: .utf8)
        for _ in 0..<40 where tabs.tabs.first?.content != "# After" {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(tabs.tabs.first?.content, "# After")
    }
}
