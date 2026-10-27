import XCTest
import AppKit
@testable import JustMD

final class ChangedLinesTests: XCTestCase {

    private func changed(_ old: String, _ new: String) -> [String] {
        let ns = new as NSString
        return RenderedDocument.changedLines(from: old, to: new).map { ns.substring(with: $0) }
    }

    func test_identicalText_hasNoChanges() {
        XCTAssertEqual(RenderedDocument.changedLines(from: "a\nb\n", to: "a\nb\n"), [])
    }

    func test_editedLine_isReported() {
        XCTAssertEqual(changed("one\ntwo\nthree\n", "one\nTWO\nthree\n"), ["TWO"])
    }

    func test_appendedLine_isReported() {
        XCTAssertEqual(changed("one\ntwo\n", "one\ntwo\nthree\n"), ["three"])
    }

    func test_deletionOnly_hasNothingToShow() {
        XCTAssertEqual(changed("one\ntwo\nthree\n", "one\nthree\n"), [])
    }

    func test_adjacentChangedLines_mergeIntoOneBlock() {
        XCTAssertEqual(changed("a\nb\nc\nd\n", "a\nB\nC\nd\n"), ["B\nC"])
    }

    func test_separateChanges_stayApart() {
        XCTAssertEqual(changed("a\nb\nc\nd\ne\n", "A\nb\nc\nD\ne\n"), ["A", "D"])
    }

    func test_emptyInsertedLines_areIgnored() {
        XCTAssertEqual(changed("a\nb\n", "a\n\n\nb\n"), [])
    }

    func test_rangesAreUTF16_afterNonASCIIText() {
        XCTAssertEqual(changed("🚀 café\nold\n", "🚀 café\nnew ✓\n"), ["new ✓"])
    }

    // A line diff that is quadratic in the changes took 91 s for a fully rewritten 1 MB file.
    func test_fullRewrite_ofManyLines_staysFast() {
        let old = (0..<5000).map { "line \($0) as it was" }.joined(separator: "\n")
        let new = (0..<5000).map { "line \($0) rewritten" }.joined(separator: "\n")
        let start = Date()
        XCTAssertEqual(RenderedDocument.changedLines(from: old, to: new).count, 1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }

    func test_duplicatedLine_isReportedOnlyForTheExtraCopy() {
        XCTAssertEqual(changed("a\nb\n", "a\nb\na\n"), ["a"])
    }

    func test_offset_shiftsRangesIntoTheDocument() {
        let ranges = RenderedDocument.changedLines(from: "x\n", to: "y\n", offset: 10)
        XCTAssertEqual(ranges, [NSRange(location: 10, length: 1)])
    }
}
