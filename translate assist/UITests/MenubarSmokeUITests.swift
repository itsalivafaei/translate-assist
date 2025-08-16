#if canImport(XCTest)
import XCTest

final class MenubarSmokeUITests: XCTestCase {
    func testPopoverOpensAndShowsControls() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-UITestOpenPopover")
        app.launch()

        let input = app.textFields["Input text to translate"]
        XCTAssertTrue(input.waitForExistence(timeout: 5.0))

        let translateButton = app.buttons["Translate button"]
        XCTAssertTrue(translateButton.exists)

        // Persona control is a segmented picker; we assert by label
        let persona = app.staticTexts["Persona preset"]
        XCTAssertTrue(persona.exists)
    }
}
#endif


