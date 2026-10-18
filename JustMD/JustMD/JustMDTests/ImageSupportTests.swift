import XCTest
@testable import JustMD

final class ImageSupportTests: XCTestCase {

    // MARK: Sizing

    func test_wideImage_shrinksToTheColumn_keepingAspect() {
        XCTAssertEqual(ImageAttachment.fittedSize(natural: CGSize(width: 800, height: 400), available: 400),
                       CGSize(width: 400, height: 200))
    }

    func test_smallImage_keepsItsNaturalSize() {
        XCTAssertEqual(ImageAttachment.fittedSize(natural: CGSize(width: 32, height: 32), available: 400),
                       CGSize(width: 32, height: 32))
    }

    func test_degenerateSizes_neverProduceZeroOrNaN() {
        let size = ImageAttachment.fittedSize(natural: .zero, available: 0)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    // MARK: Local references

    func test_references_findMarkdownAndHTMLImages_butNotRemoteOnes() {
        let md = """
        ![a](shots/a.png) ![b](https://x.y/b.png) <img src="logo.svg" width=80>
        ![c](data:image/png;base64,AAAA) ![d](<my docs/d.png>)
        """
        XCTAssertEqual(Set(LocalImages.references(in: md)), ["shots/a.png", "logo.svg", "my docs/d.png"])
    }

    func test_imageSyntaxInsideCode_isIgnored() {
        XCTAssertEqual(LocalImages.references(in: "```\n![a](x.png)\n```\nand `![b](y.png)`\n"), [])
    }

    func test_folderNeedingAccess_isTheDocumentFolder_whenItsImagesAreUnreadable() {
        let folder = URL(fileURLWithPath: "/Users/me/notes", isDirectory: true)
        let needed = LocalImages.folderNeedingAccess(markdown: "![a](shots/a.png)", documentFolder: folder) { _ in false }
        XCTAssertEqual(needed?.path, "/Users/me/notes")
    }

    func test_folderNeedingAccess_widensToCoverImagesOutsideTheFolder() {
        let folder = URL(fileURLWithPath: "/Users/me/notes/daily", isDirectory: true)
        let needed = LocalImages.folderNeedingAccess(markdown: "![a](../assets/a.png)", documentFolder: folder) { _ in false }
        XCTAssertEqual(needed?.path, "/Users/me/notes")
    }

    func test_folderNeedingAccess_isNil_whenEverythingIsReadable() {
        let folder = URL(fileURLWithPath: "/Users/me/notes", isDirectory: true)
        XCTAssertNil(LocalImages.folderNeedingAccess(markdown: "![a](a.png)", documentFolder: folder) { _ in true })
        XCTAssertNil(LocalImages.folderNeedingAccess(markdown: "no images", documentFolder: folder) { _ in false })
    }

    // MARK: Folder grants

    @MainActor
    func test_grantedFolder_persists_andCoversFilesInside() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("folders.plist")

        FolderAccess(storePath: store).grant(folder)
        let reloaded = FolderAccess(storePath: store)

        XCTAssertTrue(reloaded.covers(folder.appendingPathComponent("shots/a.png")))
        XCTAssertFalse(reloaded.covers(root.appendingPathComponent("elsewhere/b.png")))
        XCTAssertFalse(reloaded.covers(URL(fileURLWithPath: folder.path + "-sibling/c.png")), "a name prefix is not containment")
    }
}
