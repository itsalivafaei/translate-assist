#if canImport(XCTest)
import XCTest

final class MenubarSmokeUITests: XCTestCase {
    func testPopoverOpensAndShowsControls() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-UITestOpenPopover")
        app.launch()
        // Keep app active during test to avoid popover closing
        app.activate()

        // Wait for input field to appear; retry by re-activating app if needed (popover can auto-close on focus loss)
        let input = app.textFields["Input text to translate"]
        if !input.waitForExistence(timeout: 3.0) {
            app.activate()
            XCTAssertTrue(input.waitForExistence(timeout: 3.0))
        }

        let translateButton = app.buttons["Translate button"]
        XCTAssertTrue(translateButton.waitForExistence(timeout: 1.5))

        // Persona control exists (label attached to Picker)
        let persona = app.descendants(matching: .any)["Persona preset"]
        XCTAssertTrue(persona.exists)
    }
}
#endif


