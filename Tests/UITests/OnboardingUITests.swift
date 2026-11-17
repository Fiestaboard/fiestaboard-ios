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

    func testPresentationExitClearsUnsubmittedResetFieldsBeforeReopening() throws {
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
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Drag the actual native form; this does not invoke toolbar Close.
            let bar = app.navigationBars["Reset password"]
            let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 650)))
            let reopen = app.buttons["reopenOnboarding"]
            XCTAssertTrue(reopen.waitForExistence(timeout: 8)); reopen.tap()
        } else {
            // Phone onboarding is a navigation stack rather than a dismissible form.
            app.buttons["cancelPasswordReset"].tap()
            let back = app.buttons["Back to Welcome"]
            XCTAssertTrue(back.waitForExistence(timeout: 5)); back.tap()
            let savedHubs = app.buttons["Choose a saved hub"]
            XCTAssertTrue(savedHubs.waitForExistence(timeout: 5)); reveal(savedHubs, in: app); savedHubs.tap()
        }
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

    // Exercises DraftScene's real conditional host, not an isolated ConnectionView preview.
    func testActualRootKeepsEnrollmentMountedThroughHeldAuthAndConnectedHandoff() throws {
        let app = isolatedApplication(), server = FixtureHTTPServer.shared
        try server.requireReady(); app.launch(); openManualHubEntry(app); allowFixtureHTTP(app)
        let address = app.textFields["connectionAddress"]
        let deployment = "http://127.0.0.1:\(server.port)/signin-i9-root-\(UUID().uuidString.lowercased())"
        typeConnectionAddress(deployment, into: address, in: app)
        server.holdOnboardingBootstrap(true)
        defer { server.holdOnboardingBootstrap(false) }
        let connect = app.buttons["connectionConnect"]; reveal(connect, in: app); connect.tap()
        let held = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.onboardingBootstrapWaiting }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [held], timeout: 4), .completed, "The actual app must reach held auth/status")
        // A root switch to ShellContainer removes the address sheet during checking.
        XCTAssertFalse(address.waitForNonExistence(timeout: 1), "Enrollment's actual presenter must survive bootstrap")
        XCTAssertFalse(app.navigationBars["Home"].exists, "User enrollment is not cold saved-hub shell restoration")
        let checking = XCTAttachment(screenshot: app.screenshot()); checking.name = "i9-root-held-auth-presenter"; add(checking)
        server.holdOnboardingBootstrap(false)
        let username = app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout: 10), "Auth-required return must retain the verified hub instead of restarting chooser")
        XCTAssertFalse(app.buttons["reopenOnboarding"].exists)
        XCTAssertTrue(app.staticTexts["UI Test Server"].exists)
        reveal(username, in: app); username.tap(); username.typeText("fixture_admin")
        let password = app.secureTextFields["connectionPassword"]
        reveal(password, in: app); password.tap(); password.typeText("fixture-password")
        app.keyboards.buttons["Go"].tap()
        XCTAssertTrue(app.navigationBars["Home"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["Username"].exists, "Connected handoff must retire the form while keeping the live session")
        let connected = XCTAttachment(screenshot: app.screenshot()); connected.name = "i9-root-connected-handoff"; add(connected)
        // Relaunch the same namespace: catalog restoration has no user presentation owner.
        app.terminate(); server.holdOnboardingBootstrap(true); app.launch()
        let restoring = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.onboardingBootstrapWaiting }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restoring], timeout: 4), .completed)
        XCTAssertTrue(app.navigationBars["Home"].firstMatch.waitForExistence(timeout: 1), "Cold saved-hub checking retains the shell")
        XCTAssertFalse(app.textFields["connectionAddress"].exists)
        server.holdOnboardingBootstrap(false)
        XCTAssertTrue(app.textFields["Username"].waitForExistence(timeout: 10), "Unsigned cold restore must reach sign-in without a remount cancelling its hub")
        XCTAssertTrue(app.staticTexts["UI Test Server"].exists)
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
