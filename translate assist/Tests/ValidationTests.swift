#if canImport(XCTest)
import XCTest
@testable import translate_assist

final class ValidationTests: XCTestCase {
    func testSanitizeNonEmpty() throws {
        let v = try sanitizeNonEmptyText(field: "lemma", value: "  hi  ", maxLen: FieldLimits.lemma)
        XCTAssertEqual(v, "hi")
    }

    func testSanitizeTooLong() {
        XCTAssertThrowsError(try sanitizeNonEmptyText(field: "lemma", value: String(repeating: "a", count: FieldLimits.lemma + 1), maxLen: FieldLimits.lemma))
    }
}
#endif


