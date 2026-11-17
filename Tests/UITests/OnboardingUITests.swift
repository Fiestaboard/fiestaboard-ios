import XCTest

/// Production onboarding journeys with isolated metadata and the native loopback fixture.
@MainActor final class OnboardingUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    func testWelcomeExplanationAndManualAddressKeepPermissionContextual() {
        let app = isolatedApplication(); app.launch()
        let initialTitle = UIDevice.current.userInterfaceIdiom == .pad ? "Choose your hub" : "Welcome to FiestaBoard"
        XCTAssertTrue(app.staticTexts[initialTitle].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["connectionAddress"].exists)
        app.buttons["findFiestaBoard"].tap()
        XCTAssertTrue(app.staticTexts["Find your hub on this Wi-Fi"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["discoveryContinue"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists, "No browser or Local Network request precedes Continue")
        app.buttons["enterAddressInstead"].tap()
        XCTAssertTrue(app.textFields["connectionAddress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["connectionConnect"].exists)
    }

    func testManualAddressAtAX3KeepsValidationAndConnectReachable() {
        let app = isolatedApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraLarge"]
        app.launch()
        let manual = app.buttons["enterHubAddress"]
        XCTAssertTrue(manual.waitForExistence(timeout: 10)); reveal(manual, in: app); manual.tap()
        let address = app.textFields["connectionAddress"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        typeConnectionAddress("https://bad.example/?query=not-allowed", into: address, in: app)
        let connect = app.buttons["connectionConnect"]
        reveal(connect, in: app); connect.tap()
        XCTAssertTrue(app.staticTexts["connectionMessage"].waitForExistence(timeout: 5))
        XCTAssertTrue(address.exists, "An invalid address keeps the editable manual form")
    }

    func testWrongPasswordResetValidationAndCancelRetainSameHubAndUsername() throws {
        let app = isolatedApplication()
        let server = FixtureHTTPServer.shared
        try server.requireReady()
        app.launch()
        openManualHubEntry(app)
        allowFixtureHTTP(app)
        let address = app.textFields["connectionAddress"]
        typeConnectionAddress("http://127.0.0.1:\(server.port)/signin-\(UUID().uuidString.lowercased())", into: address, in: app)
        let connect = app.buttons["connectionConnect"]; reveal(connect, in: app); connect.tap()
        let user = app.textFields["Username"]
        XCTAssertTrue(user.waitForExistence(timeout: 10)); user.tap(); user.typeText("retained-owner")
        let password = app.secureTextFields["connectionPassword"]
        reveal(password, in: app); password.tap(); password.typeText("wrong-password")
        app.keyboards.buttons["Go"].tap()
        XCTAssertTrue(app.staticTexts["signInCredentialError"].waitForExistence(timeout: 8))
        XCTAssertEqual(user.value as? String, "retained-owner")
        let forgot = app.buttons["forgotPassword"]; reveal(forgot, in: app); forgot.tap()
        XCTAssertTrue(app.buttons["copyResetCommand"].waitForExistence(timeout: 5))
        let haveCode = app.buttons["haveResetCode"]; reveal(haveCode, in: app); haveCode.tap()
        let code = app.secureTextFields["resetCode"]
        XCTAssertTrue(code.waitForExistence(timeout: 5)); code.tap(); code.typeText("fb_reset_fixture")
        let newPassword = app.secureTextFields["resetNewPassword"]
        reveal(newPassword, in: app); newPassword.tap(); newPassword.typeText("new-fixture-password")
        let confirmation = app.secureTextFields["resetConfirmation"]
        reveal(confirmation, in: app); confirmation.tap(); confirmation.typeText("different-password")
        app.keyboards.buttons["Go"].tap()
        XCTAssertTrue(app.staticTexts["resetConfirmationError"].waitForExistence(timeout: 5))
        app.buttons["cancelPasswordReset"].tap()
        XCTAssertTrue(user.waitForExistence(timeout: 5))
        XCTAssertEqual(user.value as? String, "retained-owner")
        XCTAssertTrue(app.staticTexts["UI Test Server"].exists)
    }

    func testIPadInteractiveDismissalClearsUnsubmittedResetFieldsBeforeReopening() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad form presentation")
        let app = isolatedApplication(), server = FixtureHTTPServer.shared
        try server.requireReady(); app.launch(); openManualHubEntry(app)
        allowFixtureHTTP(app)
        let address = app.textFields["connectionAddress"]
        typeConnectionAddress("http://127.0.0.1:\(server.port)/signin-\(UUID().uuidString.lowercased())", into: address, in: app)
        let connect = app.buttons["connectionConnect"]; reveal(connect, in: app); connect.tap()
        let forgot = app.buttons["forgotPassword"]
        XCTAssertTrue(forgot.waitForExistence(timeout: 10)); reveal(forgot, in: app); forgot.tap()
        let haveCode = app.buttons["haveResetCode"]; reveal(haveCode, in: app); haveCode.tap()
        let values = [("resetCode", "fb_reset_unsubmitted"), ("resetNewPassword", "unsubmitted-password"), ("resetConfirmation", "unsubmitted-password")]
        for (identifier, text) in values {
            let field = app.secureTextFields[identifier]
            XCTAssertTrue(field.waitForExistence(timeout: 5)); reveal(field, in: app); field.tap(); field.typeText(text)
        }
        // Drag the real native form; this does not invoke the toolbar Close action.
        let bar = app.navigationBars["Reset password"]
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 650)))
        let reopen = app.buttons["reopenOnboarding"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 8)); reopen.tap()
        let saved = app.buttons.containing(.staticText, identifier: "UI Test Server").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5)); saved.tap()
        XCTAssertTrue(forgot.waitForExistence(timeout: 10)); reveal(forgot, in: app); forgot.tap()
        XCTAssertTrue(haveCode.waitForExistence(timeout: 5)); reveal(haveCode, in: app); haveCode.tap()
        for (identifier, _) in values {
            let field = app.secureTextFields[identifier]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            XCTAssertEqual(field.value as? String, field.placeholderValue ?? "", "Dismissed secrets must not return: \(identifier)")
        }
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable {
                let keyboard = app.keyboards.firstMatch
                if !keyboard.exists || element.frame.midY < keyboard.frame.minY - 8 { return }
            }
            app.swipeUp()
        }
    }
}
