import XCTest
import AppKit
@testable import JustMD

final class ChunkingTests: XCTestCase {

    private func section(_ n: Int, bodyLines: Int = 40) -> String {
        "# Section \(n)\n\n" + String(repeating: "Some prose for section \(n) that fills space.\n", count: bodyLines) + "\n"
    }

    // MARK: - Splitting

    func test_smallDocument_isOneChunk() {
        let md = section(1) + section(2)
        XCTAssertEqual(PreviewRenderer.chunks(of: md, targetSize: 100_000), [md])
    }

    func test_chunks_rejoinToTheOriginal() {
        let md = (1...20).map { section($0) }.joined()
        let parts = PreviewRenderer.chunks(of: md, targetSize: 2_000)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertEqual(parts.joined(), md)
    }

    func test_chunks_startAtHeadings() {
        let md = (1...20).map { section($0) }.joined()
        let parts = PreviewRenderer.chunks(of: md, targetSize: 2_000)
        XCTAssertTrue(parts.dropFirst().allSatisfy { $0.hasPrefix("# Section ") })
    }

    func test_headingInsideCodeFence_isNeverASplitPoint() {
        let fence = "```bash\n" + String(repeating: "# a shell comment, not a heading\n", count: 200) + "```\n\n"
        let md = section(1) + fence + section(2)
        let parts = PreviewRenderer.chunks(of: md, targetSize: 500)
        XCTAssertEqual(parts.joined(), md)
        XCTAssertFalse(parts.contains { $0.hasPrefix("# a shell comment") })
        XCTAssertTrue(parts.allSatisfy { $0.components(separatedBy: "```").count % 2 == 1 }, "Every chunk must close the fences it opens")
    }

    func test_documentWithoutHeadings_staysWhole() {
        let md = String(repeating: "paragraph line\n\n", count: 5_000)
        XCTAssertEqual(PreviewRenderer.chunks(of: md, targetSize: 1_000).count, 1)
    }

    func test_hashWithoutSpace_isNotAHeading() {
        let md = String(repeating: "x\n", count: 600) + "#hashtag\n" + String(repeating: "y\n", count: 10)
        XCTAssertEqual(PreviewRenderer.chunks(of: md, targetSize: 500).count, 1)
    }

    // MARK: - Reference definitions

    func test_linkReferenceDefinitions_areCollected() {
        let md = "See [docs][d].\n\n# Later\n\n[d]: https://example.com\n  [Other]: <https://x.y> \"t\"\nnot [a]: def\n"
        XCTAssertEqual(PreviewRenderer.linkReferenceDefinitions(in: md),
                       ["[d]: https://example.com", "  [Other]: <https://x.y> \"t\""])
    }

    // MARK: - Concatenation

    private func doc(_ text: String, code: NSRange, heading: NSRange, table: NSRange) -> RenderedDocument {
        RenderedDocument(text: NSAttributedString(string: text),
                         codeBlocks: [CodeBlockInfo(range: code, language: "swift")],
                         headingRanges: [(heading, 1)],
                         checkboxRanges: [(heading, true)],
                         listPrefixRanges: [(heading, false)],
                         tableRanges: [table])
    }

    func test_concatenation_offsetsEveryRangeBySpliceLength() {
        let a = doc("aaaa\n", code: NSRange(location: 1, length: 2), heading: NSRange(location: 0, length: 4), table: NSRange(location: 2, length: 1))
        let b = doc("bbbbbb", code: NSRange(location: 3, length: 2), heading: NSRange(location: 0, length: 6), table: NSRange(location: 1, length: 2))
        let joined = RenderedDocument(concatenating: [a, b])

        XCTAssertEqual(joined.text.string, "aaaa\nbbbbbb")
        XCTAssertEqual(joined.codeBlocks.map(\.range), [NSRange(location: 1, length: 2), NSRange(location: 8, length: 2)])
        XCTAssertEqual(joined.headingRanges.map(\.range), [NSRange(location: 0, length: 4), NSRange(location: 5, length: 6)])
        XCTAssertEqual(joined.checkboxRanges.map(\.range).last, NSRange(location: 5, length: 6))
        XCTAssertEqual(joined.listPrefixRanges.map(\.range).last, NSRange(location: 5, length: 6))
        XCTAssertEqual(joined.tableRanges, [NSRange(location: 2, length: 1), NSRange(location: 6, length: 2)])
    }

    func test_concatenation_insertsParagraphBreakWhenChunkLacksOne() {
        let a = doc("aaaa", code: NSRange(location: 0, length: 1), heading: NSRange(location: 0, length: 1), table: NSRange(location: 0, length: 1))
        let b = doc("bb", code: NSRange(location: 0, length: 1), heading: NSRange(location: 0, length: 2), table: NSRange(location: 0, length: 1))
        let joined = RenderedDocument(concatenating: [a, b])

        XCTAssertEqual(joined.text.string, "aaaa\nbb", "Without a break the next chunk's heading would join the previous block")
        XCTAssertEqual(joined.headingRanges.map(\.range).last, NSRange(location: 5, length: 2))
    }

    // MARK: - End to end

    func test_chunkedRender_matchesSinglePassText() {
        // Chunks end in every block kind: table, code block, list, paragraph
        let tails = ["| A | B |\n|---|---|\n| 1 | ok |\n\n", "```swift\nlet x = 1\n```\n\n", "- item\n- [x] done\n\n", "Closing paragraph.\n\n"]
        let md = (1...32).map { section($0, bodyLines: 5) + "```swift\nlet y = 2\n```\n\n" + tails[$0 % tails.count] }.joined()
        let single = PreviewRenderer.renderChunk(md)
        let chunked = PreviewRenderer.render(md, targetSize: 1_000)

        XCTAssertEqual(chunked.text.string, single.text.string)
        XCTAssertEqual(chunked.codeBlocks.map(\.range), single.codeBlocks.map(\.range))
        XCTAssertEqual(chunked.codeBlocks.map(\.language), single.codeBlocks.map(\.language))
        XCTAssertEqual(chunked.headingRanges.map(\.range), single.headingRanges.map(\.range))
        XCTAssertEqual(chunked.checkboxRanges.map(\.range), single.checkboxRanges.map(\.range))
        XCTAssertEqual(chunked.tableRanges, single.tableRanges)
    }
}

final class SegmentDiffTests: XCTestCase {

    private func seg(_ key: String, _ length: Int) -> RenderedDocument.Segment { .init(key: ContentKey(key), length: length) }

    func test_editInMiddleChunk_replacesOnlyThatChunk() {
        let old = [seg("a", 10), seg("b", 20), seg("c", 30)]
        let new = [seg("a", 10), seg("b2", 21), seg("c", 30)]
        let diff = RenderedDocument.changedRange(from: old, to: new)
        XCTAssertEqual(diff.old, NSRange(location: 10, length: 20))
        XCTAssertEqual(diff.new, NSRange(location: 10, length: 21))
    }

    func test_identicalDocuments_changeNothing() {
        let segs = [seg("a", 10), seg("b", 20)]
        let diff = RenderedDocument.changedRange(from: segs, to: segs)
        XCTAssertEqual(diff.old.length, 0)
        XCTAssertEqual(diff.new.length, 0)
    }

    func test_sameKeyWithDifferentLength_isAChange() {
        // A chunk gains a trailing separator when another chunk is appended after it
        let diff = RenderedDocument.changedRange(from: [seg("a", 10)], to: [seg("a", 11), seg("b", 5)])
        XCTAssertEqual(diff.old, NSRange(location: 0, length: 10))
        XCTAssertEqual(diff.new, NSRange(location: 0, length: 16))
    }

    func test_insertedChunk_keepsPrefixAndSuffix() {
        let diff = RenderedDocument.changedRange(from: [seg("a", 10), seg("c", 30)],
                                                 to: [seg("a", 10), seg("b", 5), seg("c", 30)])
        XCTAssertEqual(diff.old, NSRange(location: 10, length: 0))
        XCTAssertEqual(diff.new, NSRange(location: 10, length: 5))
    }

    func test_repeatedChunks_prefixAndSuffixDoNotOverlap() {
        let diff = RenderedDocument.changedRange(from: [seg("x", 5), seg("x", 5)],
                                                 to: [seg("x", 5), seg("x", 5), seg("x", 5)])
        XCTAssertEqual(diff.old, NSRange(location: 10, length: 0))
        XCTAssertEqual(diff.new, NSRange(location: 10, length: 5))
    }

    func test_segments_coverTheWholeText() {
        let md = (1...12).map { "# H\($0)\n\n" + String(repeating: "text \($0) ", count: 80) + "\n\n" }.joined()
        let doc = PreviewRenderer.render(md, targetSize: 500)
        XCTAssertGreaterThan(doc.segments.count, 1)
        XCTAssertEqual(doc.segments.map(\.length).reduce(0, +), doc.text.length)
    }
}

final class ContentKeyTests: XCTestCase {
    func test_equalText_equalKeys() {
        let a = "Heading — ünïcödé 🚀" + String(repeating: "x", count: 5000)
        let b = String(decoding: Array(a.utf8), as: UTF8.self)   // distinct buffer, same text
        XCTAssertEqual(ContentKey(a), ContentKey(b))
        XCTAssertEqual(ContentKey(a).hashValue, ContentKey(b).hashValue)
    }

    func test_differentText_differentKeys() {
        XCTAssertNotEqual(ContentKey("abc"), ContentKey("abd"))
        XCTAssertNotEqual(ContentKey("abc"), ContentKey("abc "))
    }
}

final class AdjacentBlockTests: XCTestCase {
    func test_backToBackCodeBlocks_stayDistinct() {
        let doc = PreviewRenderer.render("```bash\nls\n```\n\n```python\nprint(1)\n```\n")
        XCTAssertEqual(doc.codeBlocks.map(\.language), ["bash", "python"])
    }

    func test_tableRightAfterCodeBlock_isStillRendered() {
        let doc = PreviewRenderer.render("```swift\nlet x = 1\n```\n\n| A | B |\n|---|---|\n| 1 | 2 |\n")
        XCTAssertEqual(doc.codeBlocks.map(\.language), ["swift"])
        XCTAssertEqual(doc.tableRanges.count, 1)
    }

    func test_codeBlockRightAfterTable_isStillRendered() {
        let doc = PreviewRenderer.render("| A | B |\n|---|---|\n| 1 | 2 |\n\n```swift\nlet x = 1\n```\n")
        XCTAssertEqual(doc.codeBlocks.map(\.language), ["swift"])
        XCTAssertEqual(doc.tableRanges.count, 1)
    }

    func test_tableTouchingCodeFence_isStillRendered() {
        let doc = PreviewRenderer.render("```swift\nlet x = 1\n```\n| A | B |\n|---|---|\n| 1 | 2 |\n")
        XCTAssertEqual(doc.codeBlocks.map(\.language), ["swift"])
        XCTAssertEqual(doc.tableRanges.count, 1)
    }

    func test_codeFenceTouchingTable_isStillRendered() {
        let doc = PreviewRenderer.render("| A | B |\n|---|---|\n| 1 | 2 |\n```swift\nlet x = 1\n```\n")
        XCTAssertEqual(doc.codeBlocks.map(\.language), ["swift"])
        XCTAssertEqual(doc.tableRanges.count, 1)
    }
}

final class CheckboxPositionTests: XCTestCase {
    func test_checkboxRanges_pointAtTheBoxes_evenAfterCodeAndTables() {
        let md = "```swift\nlet x = 1\n```\n\n| A |\n|---|\n| 1 |\n\n- [x] done\n- [ ] todo\n"
        let doc = PreviewRenderer.render(md)
        let marks = doc.checkboxRanges.map { (doc.text.string as NSString).substring(with: $0.range) }
        XCTAssertEqual(marks, ["\u{2611}", "\u{2610}"])
    }
}
