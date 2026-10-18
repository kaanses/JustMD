import XCTest
@testable import JustMD

@MainActor
final class RecentFilesTests: XCTestCase {

    private func makeFiles(_ names: String...) throws -> (store: URL, files: [URL]) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let files = try names.map { name -> URL in
            let url = dir.appendingPathComponent(name)
            try "# \(name)".write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        return (dir.appendingPathComponent("bookmarks.plist"), files)
    }

    func test_recentFiles_areMostRecentFirst_andSurviveRelaunch() throws {
        let (storePath, files) = try makeFiles("a.md", "b.md", "c.md")
        let store = BookmarkStore(storePath: storePath)
        files.forEach(store.save)
        store.save(url: files[0])                        // reopening a moves it to the top

        let names = { (s: BookmarkStore) in s.recentFiles.map(\.lastPathComponent) }
        XCTAssertEqual(names(store), ["a.md", "c.md", "b.md"])
        XCTAssertEqual(names(BookmarkStore(storePath: storePath)), ["a.md", "c.md", "b.md"], "order must persist, not come back in dictionary order")
    }

    func test_removeAll_clearsAndPersists() throws {
        let (storePath, files) = try makeFiles("a.md")
        let store = BookmarkStore(storePath: storePath)
        store.save(url: files[0])
        store.removeAll()
        XCTAssertTrue(store.recentFiles.isEmpty)
        XCTAssertTrue(BookmarkStore(storePath: storePath).recentFiles.isEmpty)
    }

    func test_legacyDictionaryFormat_stillLoads() throws {
        let (storePath, files) = try makeFiles("a.md")
        let bookmark = try files[0].bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        let legacy = try PropertyListSerialization.data(fromPropertyList: [files[0].absoluteString: bookmark], format: .binary, options: 0)
        try legacy.write(to: storePath)
        XCTAssertEqual(BookmarkStore(storePath: storePath).recentFiles, [files[0]])
    }
}

final class ZoomTests: XCTestCase {
    func test_zoomSteps_moveThroughTheLadder_andClampAtTheEnds() {
        XCTAssertEqual(Zoom.larger(than: 1.0), 1.15)
        XCTAssertEqual(Zoom.smaller(than: 1.0), 0.9)
        XCTAssertEqual(Zoom.larger(than: Zoom.steps.last!), Zoom.steps.last!)
        XCTAssertEqual(Zoom.smaller(than: Zoom.steps.first!), Zoom.steps.first!)
    }

    func test_offLadderValue_snapsToTheNextStepInThatDirection() {
        XCTAssertEqual(Zoom.larger(than: 1.07), 1.15)    // e.g. after a pinch
        XCTAssertEqual(Zoom.smaller(than: 1.07), 1.0)
    }
}
