import XCTest
@testable import JustMD

@MainActor
final class TabStateTests: XCTestCase {

    func test_open_appendsTab() async {
        let state = TabState()
        let url = URL(fileURLWithPath: "/tmp/test.md")
        state.open(url: url, content: "# Hello")
        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.tabs[0].filename, "test.md")
    }

    func test_openDuplicate_focusesExistingTab() async {
        let state = TabState()
        let url = URL(fileURLWithPath: "/tmp/test.md")
        state.open(url: url, content: "# Hello")
        state.open(url: url, content: "# Hello")
        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.selectedTabID, state.tabs[0].id)
    }

    func test_close_removesTab() async {
        let state = TabState()
        let url = URL(fileURLWithPath: "/tmp/test.md")
        state.open(url: url, content: "# Hello")
        let id = state.tabs[0].id
        state.close(id: id)
        XCTAssertEqual(state.tabs.count, 0)
        XCTAssertNil(state.selectedTabID)
    }

    func test_close_selectsNeighbourTab() async {
        let state = TabState()
        state.open(url: URL(fileURLWithPath: "/tmp/a.md"), content: "a")
        state.open(url: URL(fileURLWithPath: "/tmp/b.md"), content: "b")
        let firstID = state.tabs[0].id
        state.selectedTabID = firstID
        state.close(id: firstID)
        XCTAssertEqual(state.selectedTabID, state.tabs[0].id)
    }

    func test_close_lastTab_clearsSelection() async {
        let state = TabState()
        state.open(url: URL(fileURLWithPath: "/tmp/a.md"), content: "a")
        state.open(url: URL(fileURLWithPath: "/tmp/b.md"), content: "b")
        state.open(url: URL(fileURLWithPath: "/tmp/c.md"), content: "c")
        let lastID = state.tabs[2].id
        state.selectedTabID = lastID
        state.close(id: lastID)
        XCTAssertEqual(state.selectedTabID, state.tabs[1].id)
    }

    func test_selectedTab_returnsCorrectTab() async {
        let state = TabState()
        let url = URL(fileURLWithPath: "/tmp/test.md")
        state.open(url: url, content: "hello")
        XCTAssertEqual(state.selectedTab?.filename, "test.md")
    }
}
