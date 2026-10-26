import XCTest
final class DemoUITests: XCTestCase {
    @MainActor
    func testDemoNavigationAndCompose() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10))
        app.buttons["Compose text"].tap()
        XCTAssertTrue(app.textViews["Message text"].waitForExistence(timeout: 3))
        app.textViews["Message text"].tap()
        app.textViews["Message text"].typeText("HELLO")
        app.buttons["Review action"].tap()
        XCTAssertTrue(app.buttons["Confirm simulated action"].waitForExistence(timeout: 3))
        app.buttons["Confirm simulated action"].tap()
        XCTAssertTrue(app.staticTexts["Simulated — server acknowledged a send. Physical output is not verified."].waitForExistence(timeout: 5))
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Welcome"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Displays"].tap()
        XCTAssertTrue(app.staticTexts["Demo Kitchen"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Disconnect"].waitForExistence(timeout: 3))
    }
}

extension DemoUITests {
    @MainActor
    func testLocalDraftEntryAndUnsavedCloseConfirmation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Library"].tap()
        app.staticTexts["Welcome"].tap()
        app.buttons["editLocalDraft"].tap()
        XCTAssertTrue(app.staticTexts["Local draft only"].waitForExistence(timeout: 5))
        let name = app.textFields["Name"]
        XCTAssertTrue(name.exists)
        name.tap()
        name.typeText(" local UI draft")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 3))
        app.buttons["Keep editing"].tap()
        XCTAssertTrue(name.exists)
        app.buttons["Close"].tap()
        app.buttons["Discard unsaved changes"].tap()
        XCTAssertTrue(app.buttons["editLocalDraft"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Local draft only"].exists)
    }

    @MainActor
    func testBoardControlCancelAndConfirmedPause() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        let entry = app.buttons["boardControlsEntry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.buttons["Pause updates"].waitForExistence(timeout: 3))
        app.buttons["Pause updates"].tap()
        XCTAssertTrue(app.buttons["Confirm"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Pause updates"].exists)
        app.buttons["Pause updates"].tap()
        app.buttons["Confirm"].tap()
        XCTAssertTrue(app.buttons["Resume updates"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["FiestaBoard"].tap()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 3))
    }
}
