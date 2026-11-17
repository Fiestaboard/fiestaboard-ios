import XCTest

@MainActor final class ShellUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func waitValue(_ element: XCUIElement, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed, element.debugDescription, file: file, line: line)
    }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testFiveDestinationsAndDisplayAccessory() {
        XCUIDevice.shared.orientation = .portrait
        let app = isolatedApplication()
        launchFixture(app)
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 10))
        let expected = ["Home", "Pages", "Schedule", "Displays", "More"].map { "destination-" + $0 }
        for id in expected { XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5), app.debugDescription) }
        let tabs = app.tabBars.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "destination-")).allElementsBoundByIndex
        XCTAssertEqual(tabs.map(\.identifier), expected)
        XCTAssertFalse(app.buttons["destination-Collections"].exists)
        let accessory = app.buttons["shellDisplaySwitcher"]
        XCTAssertTrue(accessory.exists)
        accessory.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "127.0.0.1")).firstMatch.exists)
        let hall = app.buttons["Hall"].firstMatch
        XCTAssertTrue(hall.waitForExistence(timeout: 5)); hall.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Hall"), object: accessory)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        shot("i6-active-display-accessory")
        app.buttons["destination-More"].tap()
        XCTAssertTrue(app.buttons["shellHubs"].waitForExistence(timeout: 5))
        shot("i6-more-native-system-screen")
        app.buttons["shellHubs"].tap()
        XCTAssertTrue(app.navigationBars["Hubs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shellAddHub"].exists)
        shot("i6-hubs-root")
    }
    func testIndependentTabStackAndEditorCloseRestoreShell() {
        XCUIDevice.shared.orientation = .portrait
        let app = isolatedApplication()
        launchFixture(app)
        app.buttons["destination-Pages"].tap()
        app.buttons["shellCollections"].tap()
        XCTAssertTrue(app.navigationBars["Collections"].waitForExistence(timeout: 5))
        app.buttons["destination-Displays"].tap()
        app.buttons["destination-Pages"].tap()
        XCTAssertTrue(app.navigationBars["Collections"].waitForExistence(timeout: 5), "Each tab must retain its own navigation stack")
        app.navigationBars.buttons["Pages"].firstMatch.tap()
        let create = app.buttons["newLibraryPage"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        let name = app.textFields["New page name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Shell editor\n")
        app.buttons["createLibraryPage"].tap()
        XCTAssertTrue(app.textViews["boardDocument"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["destination-More"].isHittable)
        shot("i6-editor-full-width-shell-hidden")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["destination-More"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["destination-More"].isHittable)
        shot("i6-editor-closed-shell-restored")
    }
    func testSwitchingSavedHubsDoesNotReuseAnotherHubCredentialsOrContent() {
        XCUIDevice.shared.orientation = .portrait
        let app = isolatedApplication()
        launchFixture(app)
        app.buttons["destination-More"].tap()
        app.buttons["shellHubs"].tap()
        let addressLabel = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "http://127.0.0.1:")).firstMatch
        XCTAssertTrue(addressLabel.waitForExistence(timeout: 5))
        let originalAddress = addressLabel.label
        app.buttons["shellAddHub"].tap()
        let address = app.textFields["connectionAddress"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        let secondAddress = "http://127.0.0.1:\(FixtureHTTPServer.shared.port)/board-manual-\(UUID().uuidString.lowercased())"
        allowFixtureHTTP(app)
        typeConnectionAddress(secondAddress, into: address, in: app)
        let alias = app.textFields["Server name (optional)"]
        alias.tap(); alias.typeText("Second hub\n")
        app.buttons["connectionConnect"].tap()
        let username = app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout: 10)); username.tap(); username.typeText("fixture_admin")
        let password = app.secureTextFields["connectionPassword"]
        password.tap(); password.typeText("fixture-password")
        app.keyboards.buttons["Go"].tap()
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 15))
        app.buttons["destination-More"].tap()
        app.buttons["shellHubs"].tap()
        let original = app.buttons.containing(.staticText, identifier: originalAddress).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 5)); original.tap()
        XCTAssertTrue(app.textFields["Username"].waitForExistence(timeout: 10), "An unremembered sign-in must not borrow the other hub's bearer")
        XCTAssertFalse(app.buttons["boardControlsEntry"].exists)
        XCTAssertFalse(app.staticTexts[secondAddress].exists)
        shot("i6-switch-hub-isolated-authentication")
    }
    func testNativeMinimizationAndAdaptiveIPadPlacement() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = isolatedApplication()
        launchFixture(app)
        let placement = app.descendants(matching: .any).matching(identifier: "shellTabPlacement").firstMatch
        if UIDevice.current.userInterfaceIdiom == .pad {
            waitValue(placement, "top")
            shot("i6-ipad-portrait-top-tabs")
            XCUIDevice.shared.orientation = .landscapeLeft
            waitValue(placement, "sidebar")
            shot("i6-ipad-landscape-sidebar")
        } else {
            waitValue(placement, "bottom")
            let accessory = app.descendants(matching: .any).matching(identifier: "shellTabAccessoryPlacement").firstMatch
            waitValue(accessory, "expanded")
            shot("i6-phone-expanded-native-glass")
            let scroll = app.scrollViews.firstMatch
            XCTAssertTrue(scroll.exists)
            scroll.swipeUp()
            waitValue(accessory, "inline")
            shot("i6-phone-minimized-native-glass")
            scroll.swipeDown()
            waitValue(accessory, "expanded")
        }
    }
}
