import XCTest

/// Native navigation/interaction checks use synthetic scenario glue around the
/// vendored authenticated Compose corpus. They are not physical-output proof.
@MainActor final class ComposeUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func tapReady(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"), object: element)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else {
            XCTFail("Compose control must be ready: \(element.debugDescription)", file: file, line: line)
            return
        }
        element.tap()
    }

    func testComposeSheetShowsExplicitDurationSilenceAndRetainsCanceledDraft() {
        let app = isolatedApplication()
        launchFixture(app, scenario: "i8-compose")
        tapReady(app.buttons["homeCompose"])
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap(); source.typeText("Dinner at seven")
        XCTAssertTrue(app.buttons["composeShowNow"].exists)
        XCTAssertTrue(app.buttons["composeDisplayPicker"].exists)
        XCTAssertTrue(app.buttons["composeDuration"].exists)
        app.buttons["composeSilence"].tap()
        XCTAssertTrue(app.buttons["Hold until silence ends"].waitForExistence(timeout: 3))
        app.buttons["Hold until silence ends"].tap()
        shot("i8-compose-typing-native-sheet")
        app.buttons["composeCancel"].tap()
        XCTAssertTrue(app.buttons["homeCompose"].waitForExistence(timeout: 5))
        tapReady(app.buttons["homeCompose"])
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, "Dinner at seven")
    }

    func testLEDToolbarDoesNotOfferUnadvertisedIconAndWarnsAboutActualClipping() {
        let app = isolatedApplication()
        launchFixture(app, scenario: "i8-compose")
        tapReady(app.buttons["homeCompose"])
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
        shot("i8-compose-led-capability-menu")
    }

    func testUnconfirmedSendKeepsSourceAndBlocksRetargetAndReplay() {
        let app = isolatedApplication()
        launchFixture(app, scenario: "i8-compose-unknown")
        tapReady(app.buttons["homeCompose"])
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap(); source.typeText("Keep this draft")
        tapReady(app.buttons["composeShowNow"])
        XCTAssertTrue(app.staticTexts["composeOutcome"].waitForExistence(timeout: 8))
        XCTAssertEqual(source.value as? String, "Keep this draft")
        XCTAssertFalse(app.buttons["composeDisplayPicker"].isEnabled)
        XCTAssertFalse(app.buttons["composeShowNow"].isEnabled)
        shot("i8-compose-unconfirmed-source-retained")
        app.buttons["composeCancel"].tap()
        tapReady(app.buttons["homeCompose"])
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, "Keep this draft")
        XCTAssertFalse(app.buttons["composeShowNow"].isEnabled)
    }

    func testSaveAsPageKeepsTheUnsentComposeSource() {
        let app = isolatedApplication()
        launchFixture(app, scenario: "i8-compose")
        tapReady(app.buttons["homeCompose"])
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap(); source.typeText("Dinner at seven")
        app.buttons["composeMore"].tap()
        app.buttons["Save as Page"].tap()
        XCTAssertTrue(app.textFields["composePageName"].waitForExistence(timeout: 5))
        shot("i8-save-as-page-native-sheet")
        app.buttons["composeSavePage"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        XCTAssertEqual(source.value as? String, "Dinner at seven")
    }

    func testComposeControlsRemainAccessibleInDarkAX3() {
        let app = isolatedApplication()
        launchFixture(app, arguments: ["-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraLarge.rawValue], scenario: "i8-compose")
        tapReady(app.buttons["homeCompose"])
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.label, "Message text")
        XCTAssertEqual(app.buttons["composeShowNow"].label, "Show now")
        XCTAssertTrue(app.buttons["composeCancel"].isHittable)
        source.tap(); source.typeText("Dinner at seven")
        shot("i8-compose-dark-ax3-native-sheet")
    }
}
