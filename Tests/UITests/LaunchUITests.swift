import XCTest

final class LaunchUITests: XCTestCase {
    func testLaunchShowsConnectionEntry() {
        let app = isolatedApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(app.textFields["connectionAddress"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["localDraftRecovery"].exists)
        XCTAssertFalse(app.buttons["exploreDemo"].exists)
    }
}
