import XCTest
@testable import JustMD

final class StatusBadgeTests: XCTestCase {

    func test_plainOkWord_isOkBadge() {
        XCTAssertEqual(PreviewRenderer.statusBadge(for: "Done"), .ok("DONE"))
    }

    func test_warnWord_isWarnBadge() {
        XCTAssertEqual(PreviewRenderer.statusBadge(for: "error"), .warn("ERROR"))
    }

    func test_emojiPrefix_isStrippedBeforeMatching() {
        XCTAssertEqual(PreviewRenderer.statusBadge(for: "✅ OK"), .ok("OK"))
        XCTAssertEqual(PreviewRenderer.statusBadge(for: "⚠️ Warn"), .warn("WARN"))
    }

    func test_nonStatusText_isNotABadge() {
        XCTAssertNil(PreviewRenderer.statusBadge(for: "Backend"))
        XCTAssertNil(PreviewRenderer.statusBadge(for: "OK then"))
    }

    func test_digitsSurviveEmojiStripping() {
        // Digits carry the Unicode isEmoji property (keycap bases); they must not be stripped
        XCTAssertNil(PreviewRenderer.statusBadge(for: "12.4"))
    }
}
