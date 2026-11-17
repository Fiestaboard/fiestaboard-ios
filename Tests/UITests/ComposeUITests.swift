import XCTest

/// Native navigation/interaction checks use synthetic scenario glue around the
/// vendored authenticated Compose corpus. They are not physical-output proof.
@MainActor final class ComposeUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    func testComposeSheetShowsExplicitDurationSilenceAndRetainsCanceledDraft() {
        let app = isolatedApplication()
        launchFixture(app, scenario: "i8-compose")
        app.buttons["homeCompose"].tap()
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap(); source.typeText("Dinner at seven")
        XCTAssertTrue(app.buttons["composeShowNow"].exists)
        XCTAssertTrue(app.buttons["composeDisplayPicker"].exists)
        XCTAssertTrue(app.buttons["composeDuration"].exists)
        app.buttons["composeSilence"].tap()
        XCTAssertTrue(app.buttons["Hold until silence ends"].waitForExistence(timeout: 3))
        app.buttons["Hold until silence ends"].tap()
        app.buttons["composeCancel"].tap()
        XCTAssertTrue(app.buttons["homeCompose"].waitForExistence(timeout: 5))
        app.buttons["homeCompose"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, "Dinner at seven")
    }

    func testLEDToolbarDoesNotOfferUnadvertisedIconAndWarnsAboutActualClipping() {
        let app = isolatedApplication()
        launchFixture(app, scenario: "i8-compose")
        app.buttons["homeCompose"].tap()
        app.buttons["composeDisplayPicker"].tap()
        app.buttons["Entry clock"].tap()
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap(); source.typeText("ABCDEFGHIJKLMNOPQRS")
        XCTAssertTrue(app.staticTexts["composeClippingWarning"].waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, "ABCDEFGHIJKLMNOPQRS")
        app.buttons["composeIcons"].tap()
        XCTAssertTrue(app.buttons["sun"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["cake"].exists)
    }

    func testUnconfirmedSendKeepsSourceAndBlocksRetargetAndReplay() {
        let app = isolatedApplication()
        launchFixture(app, scenario: "i8-compose-unknown")
        app.buttons["homeCompose"].tap()
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap(); source.typeText("Keep this draft")
        app.buttons["composeShowNow"].tap()
        XCTAssertTrue(app.staticTexts["composeOutcome"].waitForExistence(timeout: 8))
        XCTAssertEqual(source.value as? String, "Keep this draft")
        XCTAssertFalse(app.buttons["composeDisplayPicker"].isEnabled)
        XCTAssertFalse(app.buttons["composeShowNow"].isEnabled)
        app.buttons["composeCancel"].tap()
        app.buttons["homeCompose"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, "Keep this draft")
        XCTAssertFalse(app.buttons["composeShowNow"].isEnabled)
    }

    func testSaveAsPageKeepsTheUnsentComposeSource() {
        let app = isolatedApplication()
        launchFixture(app, scenario: "i8-compose")
        app.buttons["homeCompose"].tap()
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap(); source.typeText("Dinner at seven")
        app.buttons["composeMore"].tap()
        app.buttons["Save as Page"].tap()
        XCTAssertTrue(app.textFields["composePageName"].waitForExistence(timeout: 5))
        app.buttons["composeSavePage"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        XCTAssertEqual(source.value as? String, "Dinner at seven")
    }
}
