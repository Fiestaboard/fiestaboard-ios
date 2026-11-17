import XCTest

@MainActor final class LaunchUITests: XCTestCase {
    func testLaunchShowsConnectionEntry() {
        let app = isolatedApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(app.buttons["enterHubAddress"].waitForExistence(timeout: 10))
        openManualHubEntry(app)
        XCTAssertTrue(app.textFields["connectionAddress"].exists)
        XCTAssertFalse(app.buttons["localDraftRecovery"].exists)
        XCTAssertFalse(app.buttons["exploreDemo"].exists)
    }
}
