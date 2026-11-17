import XCTest

@MainActor final class ShellUITests: XCTestCase {
    func testFiveDestinationsAndDisplayAccessory() {
        let app = XCUIApplication()
        launchFixture(app)
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 10))
        for label in ["Home", "Pages", "Schedule", "Displays", "More"] {
            XCTAssertTrue(app.buttons["destination-" + label].waitForExistence(timeout: 5), app.debugDescription)
        }
        XCTAssertFalse(app.buttons["destination-Collections"].exists)
        XCTAssertTrue(app.buttons["shellDisplaySwitcher"].exists)
        app.buttons["destination-More"].tap()
        app.buttons["shellHubs"].tap()
        XCTAssertTrue(app.navigationBars["Hubs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shellAddHub"].exists)
    }
}
