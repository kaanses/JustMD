import XCTest
import AppKit
@testable import JustMD

final class MarkdownFeatureTests: XCTestCase {

    private func render(_ md: String, folder: URL? = nil) -> RenderedDocument {
        PreviewRenderer.renderChunk(md, folder: folder)
    }

    private func attribute<T>(_ key: NSAttributedString.Key, of needle: String, in doc: RenderedDocument) -> T? {
        let range = (doc.text.string as NSString).range(of: needle)
        guard range.location != NSNotFound else { XCTFail("'\(needle)' not rendered"); return nil }
        return doc.text.attribute(key, at: range.location, effectiveRange: nil) as? T
    }

    // MARK: Inline

    func test_strikethrough_isStruck_andMarkersRemoved() {
        let doc = render("Before ~~gone~~ after\n")
        XCTAssertFalse(doc.text.string.contains("~~"))
        XCTAssertEqual(attribute(.strikethroughStyle, of: "gone", in: doc), NSUnderlineStyle.single.rawValue)
    }

    func test_bareURL_becomesLink_withoutTrailingPunctuation() {
        let doc = render("See https://github.com/apple/swift-markdown. Also www.example.com!\n")
        let first: URL? = attribute(.link, of: "https://github.com/apple/swift-markdown", in: doc)
        XCTAssertEqual(first?.absoluteString, "https://github.com/apple/swift-markdown")
        let second: URL? = attribute(.link, of: "www.example.com", in: doc)
        XCTAssertEqual(second?.absoluteString, "https://www.example.com")
        let period = (doc.text.string as NSString).range(of: "markdown. Also").location + "markdown".count
        XCTAssertNil(doc.text.attribute(.link, at: period, effectiveRange: nil), "the sentence's full stop is not part of the URL")
    }

    func test_urlInsideCode_isNotLinked() {
        let doc = render("Run `curl https://example.com` now\n")
        let link: URL? = attribute(.link, of: "https://example.com", in: doc)
        XCTAssertNil(link)
    }

    func test_relativeLink_resolvesAgainstDocumentFolder() {
        let folder = URL(fileURLWithPath: "/Users/me/notes/", isDirectory: true)
        let doc = render("Read [the guide](docs/guide.md)\n", folder: folder)
        let link: URL? = attribute(.link, of: "the guide", in: doc)
        XCTAssertEqual(link?.path, "/Users/me/notes/docs/guide.md")
    }

    func test_inlineHTML_formatsInsteadOfPrintingTags() {
        let doc = render("Press <kbd>Cmd</kbd>, <b>bold</b><br>next line\n")
        XCTAssertFalse(doc.text.string.contains("<kbd>"))
        XCTAssertFalse(doc.text.string.contains("<b>"))
        XCTAssertTrue(doc.text.string.contains("\u{2028}next line"))
        let font: NSFont? = attribute(.font, of: "bold", in: doc)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
        let kbd: NSFont? = attribute(.font, of: "Cmd", in: doc)
        XCTAssertTrue(kbd?.isFixedPitch ?? false)
    }

    // MARK: Footnotes

    func test_footnotes_numberReferences_andListDefinitionsAtTheEnd() {
        let md = "First[^a] and second[^b].\n\n[^b]: Bee note.\n[^a]: Ay note.\n"
        let resolved = PreviewRenderer.resolveFootnotes(in: md)
        let doc = render(resolved)
        XCTAssertFalse(doc.text.string.contains("[^"))
        // Numbered by first reference, not by definition order
        XCTAssertTrue(doc.text.string.contains("First1 and second2."))
        let sup: CGFloat? = attribute(.baselineOffset, of: "1 and", in: doc)
        XCTAssertGreaterThan(sup ?? 0, 0)
        let notes = doc.text.string.components(separatedBy: "Ay note")[0]
        XCTAssertTrue(notes.hasSuffix("1.\t"), "definition 'a' is footnote 1")
    }

    func test_footnoteSyntaxInsideCodeFence_isLeftAlone() {
        let md = "```\nx[^1]\n[^1]: not a note\n```\n"
        XCTAssertEqual(PreviewRenderer.resolveFootnotes(in: md), md)
    }

    // MARK: Blocks

    func test_headings_areRecordedWithTheirLevels() {
        let doc = render("# One\n\n### Three\n\n###### Six\n")
        XCTAssertEqual(doc.headingRanges.map(\.level), [1, 3, 6])
        let texts = doc.headingRanges.map { (doc.text.string as NSString).substring(with: $0.range) }
        XCTAssertEqual(texts, ["One", "THREE", "Six"])
    }

    func test_codeBlocks_keepTheirLanguage_andStayDistinct() {
        let doc = render("```swift\nlet a = 1\n```\n```Python extra\nprint(1)\n```\n")
        XCTAssertEqual(doc.codeBlocks.map(\.language), ["swift", "python"])
        XCTAssertEqual(NSIntersectionRange(doc.codeBlocks[0].range, doc.codeBlocks[1].range).length, 0)
    }

    func test_orderedList_honoursStartNumber() {
        let doc = render("3. three\n4. four\n")
        XCTAssertTrue(doc.text.string.hasPrefix("3.\tthree\n4.\tfour"))
    }

    func test_taskList_recordsBoxes_andStrikesDoneItems() {
        let doc = render("- [x] done\n- [ ] todo\n")
        XCTAssertEqual(doc.checkboxRanges.map(\.isDone), [true, false])
        XCTAssertEqual(doc.checkboxRanges.map { (doc.text.string as NSString).substring(with: $0.range) }, ["\u{2611}", "\u{2610}"])
        XCTAssertEqual(attribute(.strikethroughStyle, of: "done", in: doc), NSUnderlineStyle.single.rawValue)
        XCTAssertTrue(doc.listPrefixRanges.isEmpty, "task items show a box, not a bullet")
    }

    func test_nestedBullets_areMarkedNested() {
        let doc = render("- top\n  - inner\n")
        XCTAssertEqual(doc.listPrefixRanges.map(\.nested), [false, true])
    }

    func test_tableAlignment_isHonoured() {
        let doc = render("| L | C | R | D |\n|:--|:-:|--:|---|\n| a | b | c | d |\n")
        let alignments = ["a", "b", "c", "d"].map { needle -> NSTextAlignment? in
            let style: NSParagraphStyle? = attribute(.paragraphStyle, of: needle, in: doc)
            return style?.alignment
        }
        XCTAssertEqual(alignments, [.left, .center, .right, .center])
        XCTAssertEqual(doc.tableRanges.count, 1)
    }

    func test_tableCells_renderInlineMarkdown() {
        let doc = render("| A |\n|---|\n| **bold** and ~~gone~~ |\n")
        XCTAssertFalse(doc.text.string.contains("**"))
        XCTAssertEqual(attribute(.strikethroughStyle, of: "gone", in: doc), NSUnderlineStyle.single.rawValue)
    }

    func test_htmlBlock_isReducedToText() {
        let doc = render("<div align=\"center\">\n  <p>Centred <b>intro</b></p>\n</div>\n")
        XCTAssertTrue(doc.text.string.contains("Centred intro"))
        XCTAssertFalse(doc.text.string.contains("<"))
        let style: NSParagraphStyle? = attribute(.paragraphStyle, of: "Centred", in: doc)
        XCTAssertEqual(style?.alignment, .center)
    }
}
