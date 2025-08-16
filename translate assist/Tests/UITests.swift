#if canImport(XCTest)
import XCTest

/// Basic UI smoke using XCUIApplication launched with the app test host.
/// Note: This is a lightweight sanity check within the unit test bundle scope.
final class UITests: XCTestCase {
    func testMenubarPopoverOpensAndHasControls() throws {
        throw XCTSkip("UI tests execute in a separate UI Test target. This test is a placeholder in unit tests and is skipped.")
    }
}
#endif


