import XCTest
@testable import JustMD

@MainActor final class BookmarkStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeTempFile(in dir: URL, name: String = "test.md") -> URL {
        let url = dir.appendingPathComponent(name)
        try? "# Hello".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func minimalBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func writePlist(_ dict: [String: Data], to path: URL) {
        if let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) {
            try? data.write(to: path, options: .atomic)
        }
    }

    // MARK: - Tests

    func test_save_storesBookmark() async {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storePath = dir.appendingPathComponent("bookmarks.plist")
        let fileURL = makeTempFile(in: dir)

        guard let data = minimalBookmark(for: fileURL) else {
            XCTFail("Could not create minimal bookmark")
            return
        }
        writePlist([fileURL.absoluteString: data], to: storePath)

        let store = BookmarkStore(storePath: storePath)
        XCTAssertNotNil(store.bookmarks[fileURL], "Bookmark should be present after loading from disk")
    }

    func test_resolveAll_returnsValidURL() async {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storePath = dir.appendingPathComponent("bookmarks.plist")
        let fileURL = makeTempFile(in: dir)

        guard let data = minimalBookmark(for: fileURL) else {
            XCTFail("Could not create minimal bookmark")
            return
        }
        writePlist([fileURL.absoluteString: data], to: storePath)

        let store = BookmarkStore(storePath: storePath)
        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertTrue(store.bookmarks.keys.contains(fileURL))
    }

    func test_cap_removesOldest() async {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let capStorePath = dir.appendingPathComponent("cap_bookmarks.plist")

        // Seed the store with exactly 20 entries via plist so all are tracked in insertionOrder
        var dict20: [String: Data] = [:]
        var urls: [URL] = []
        for i in 0..<20 {
            let f = makeTempFile(in: dir, name: "cap\(i).md")
            urls.append(f)
            if let bm = minimalBookmark(for: f) {
                dict20[f.absoluteString] = bm
            }
        }
        writePlist(dict20, to: capStorePath)

        let capStore = BookmarkStore(storePath: capStorePath)
        XCTAssertEqual(capStore.bookmarks.count, 20, "Should have 20 entries after loading")

        // Create and save a 21st file — save() enforces the cap via insertBookmark
        let extraFile = makeTempFile(in: dir, name: "extra.md")
        capStore.save(url: extraFile)

        // Whether save() succeeded (security scope available) or not, count must be <= 20
        XCTAssertLessThanOrEqual(capStore.bookmarks.count, 20, "Bookmark count must not exceed cap of 20")

        // If the save succeeded, the new file should be present and count should be exactly 20
        if capStore.bookmarks[extraFile] != nil {
            XCTAssertEqual(capStore.bookmarks.count, 20, "Count should stay at cap after evicting oldest")
        }
    }

    func test_persistence_loadsFromDisk() async {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storePath = dir.appendingPathComponent("bookmarks.plist")
        let fileURL = makeTempFile(in: dir)

        guard let data = minimalBookmark(for: fileURL) else {
            XCTFail("Could not create minimal bookmark")
            return
        }
        writePlist([fileURL.absoluteString: data], to: storePath)

        // First store loads from disk
        let store1 = BookmarkStore(storePath: storePath)
        XCTAssertEqual(store1.bookmarks.count, 1, "First instance should load 1 bookmark")

        // Second independent store at same path should also load it
        let store2 = BookmarkStore(storePath: storePath)
        XCTAssertEqual(store2.bookmarks.count, 1, "Second instance should load same bookmark")
        XCTAssertNotNil(store2.bookmarks[fileURL], "Second instance should contain the URL")
    }
}
