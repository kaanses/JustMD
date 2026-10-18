import XCTest
@testable import JustMD

@MainActor
final class TabNavigationTests: XCTestCase {

    private func state(_ names: String...) -> TabState {
        let s = TabState()
        names.forEach { s.open(url: URL(fileURLWithPath: "/tmp/\($0).md"), content: $0) }
        return s
    }

    private func selectedName(_ s: TabState) -> String? { s.selectedTab?.url.deletingPathExtension().lastPathComponent }

    func test_selectNext_movesRight_andWrapsToFirst() {
        let s = state("a", "b", "c")          // opening selects the last one: c
        s.selectNext()
        XCTAssertEqual(selectedName(s), "a")
        s.selectNext()
        XCTAssertEqual(selectedName(s), "b")
    }

    func test_selectPrevious_movesLeft_andWrapsToLast() {
        let s = state("a", "b", "c")
        s.select(index: 0)
        s.selectPrevious()
        XCTAssertEqual(selectedName(s), "c")
    }

    func test_selectIndex_outOfRange_isIgnored() {
        let s = state("a", "b")
        s.select(index: 5)
        XCTAssertEqual(selectedName(s), "b")
    }

    func test_selectLast_matchesCommandNine() {
        let s = state("a", "b", "c")
        s.select(index: 0)
        s.selectLast()
        XCTAssertEqual(selectedName(s), "c")
    }

    func test_closeSelected_selectsNeighbour() {
        let s = state("a", "b", "c")
        s.select(index: 1)
        s.closeSelected()
        XCTAssertEqual(s.tabs.map { $0.url.lastPathComponent }, ["a.md", "c.md"])
        XCTAssertEqual(selectedName(s), "c")
    }

    func test_navigation_withNoTabs_doesNothing() {
        let s = TabState()
        s.selectNext(); s.selectPrevious(); s.selectLast(); s.closeSelected()
        XCTAssertNil(s.selectedTabID)
    }
}
