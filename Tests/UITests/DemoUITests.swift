import XCTest

@MainActor
private func selectTab(_ name: String, in app: XCUIApplication) {
    let phoneTab = app.tabBars.buttons[name]
    if phoneTab.exists { phoneTab.tap(); return }
    // iPad floating tabs expose cells on current SDKs; sidebars can expose buttons.
    let tabletTab = app.cells[name].firstMatch
    if tabletTab.exists && tabletTab.isHittable { tabletTab.tap(); return }
    app.buttons[name].firstMatch.tap()
}
final class DemoUITests: XCTestCase {
    @MainActor
    private func dismissConfirmation(_ app: XCUIApplication, cancel: String = "Cancel") {
        let button = app.buttons[cancel]
        if button.exists && button.isHittable { button.tap() }
        else {
            // Native popovers omit cancel actions. Tapping outside dismisses them.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        }
    }
    @MainActor
    func testDemoNavigationAndCompose() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10), app.staticTexts["connectionMessage"].firstMatch.debugDescription)
        app.buttons["Compose text"].tap()
        XCTAssertTrue(app.textViews["Message text"].waitForExistence(timeout: 3))
        app.textViews["Message text"].tap()
        app.textViews["Message text"].typeText("HELLO")
        let review = app.buttons["Review action"]
        if app.buttons["Hide keyboard"].exists { app.buttons["Hide keyboard"].tap() }
        XCTAssertTrue(review.isEnabled)
        let frame = review.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        XCTAssertTrue(app.buttons["Confirm simulated action"].waitForExistence(timeout: 3))
        app.buttons["Confirm simulated action"].tap()
        XCTAssertTrue(app.staticTexts["Simulated — server acknowledged a send. Physical output is not verified."].waitForExistence(timeout: 5))
        selectTab("Library", in: app)
        XCTAssertTrue(app.staticTexts["Welcome"].waitForExistence(timeout: 3))
        selectTab("Displays", in: app)
        XCTAssertTrue(app.staticTexts["Demo Kitchen"].waitForExistence(timeout: 3))
        selectTab("Settings", in: app)
        XCTAssertTrue(app.buttons["Disconnect"].waitForExistence(timeout: 3))
    }
}

extension DemoUITests {
    @MainActor
    func testLocalDraftEntryAndUnsavedCloseConfirmation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10), app.staticTexts["connectionMessage"].firstMatch.debugDescription)
        selectTab("Library", in: app)
        app.staticTexts["Welcome"].tap()
        app.buttons["editLocalDraft"].tap()
        XCTAssertTrue(app.staticTexts["Local draft"].waitForExistence(timeout: 5))
        let name = app.textFields["Name"]
        XCTAssertTrue(name.exists)
        name.tap()
        name.typeText(" local UI draft")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Discard unsaved changes"].waitForExistence(timeout: 3))
        dismissConfirmation(app, cancel: "Keep editing")
        XCTAssertTrue(name.exists)
        app.buttons["Close"].tap()
        app.buttons["Discard unsaved changes"].tap()
        XCTAssertTrue(app.buttons["editLocalDraft"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Local draft"].exists)
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
        dismissConfirmation(app)
        XCTAssertTrue(app.buttons["Pause updates"].exists)
        app.buttons["Pause updates"].tap()
        app.buttons["Confirm"].tap()
        XCTAssertTrue(app.buttons["Resume updates"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["FiestaBoard"].tap()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testUnknownConfigurationShowsReadbackRecoveryOnControlsScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10), app.staticTexts["connectionMessage"].firstMatch.debugDescription)
        selectTab("Settings", in: app)
        app.buttons["demoOutcomePicker"].tap()
        app.buttons["Unknown"].tap()
        selectTab("Home", in: app)
        let entry = app.buttons["boardControlsEntry"]
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        app.buttons["Pause updates"].tap()
        app.buttons["Confirm"].tap()
        let outcome = app.staticTexts["actionOutcome"]
        XCTAssertTrue(outcome.waitForExistence(timeout: 5))
        XCTAssertTrue(outcome.label.contains("result is unknown"))
        XCTAssertTrue(outcome.label.contains("some settings may have changed"))
        XCTAssertTrue(outcome.isHittable)
        XCTAssertTrue(app.staticTexts["controlReadbackPrompt"].isHittable)
        XCTAssertFalse(app.buttons["Pause updates"].isEnabled)
        let refresh = app.buttons["refreshBoardControls"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: refresh)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        refresh.tap()
        XCTAssertTrue(app.buttons["Resume updates"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Resume updates"].isEnabled)
        XCTAssertFalse(app.staticTexts["controlReadbackPrompt"].exists)
    }

    @MainActor
    func testPausedRestoreRefusalIsVisibleOnControlsScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        let entry = app.buttons["boardControlsEntry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        app.buttons["Pause updates"].tap()
        app.buttons["Confirm"].tap()
        XCTAssertTrue(app.buttons["Resume updates"].waitForExistence(timeout: 5))
        let restore = app.buttons["Restore board content"]
        if !restore.isHittable { app.swipeUp() }
        restore.tap()
        app.buttons["Confirm"].tap()
        app.swipeDown()
        let outcome = app.staticTexts["actionOutcome"]
        let refused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "server refused this action"), object: outcome
        )
        XCTAssertEqual(XCTWaiter.wait(for: [refused], timeout: 5), .completed)
        XCTAssertTrue(outcome.isHittable)
        XCTAssertFalse(app.staticTexts["controlReadbackPrompt"].exists)
        XCTAssertTrue(app.buttons["refreshBoardControls"].isEnabled)
    }

}


extension DemoUITests {
    @MainActor
    func testPagePreviewAndConfirmedSimulatedSave() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        openPageEditor(app)

        let preview = app.buttons["previewPage"]
        scrollTo(preview, in: app)
        XCTAssertFalse(preview.isEnabled, "Evaluation requires an explicit board choice.")
        let boardPicker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Board for evaluation")).firstMatch
        scrollTo(boardPicker, in: app)
        boardPicker.tap()
        app.buttons["Demo Kitchen"].tap()
        preview.tap()
        let simulatedPreview = app.staticTexts["Demo preview · simulated, expressions are not evaluated"]
        scrollTo(simulatedPreview, in: app)
        XCTAssertTrue(simulatedPreview.waitForExistence(timeout: 5))

        let name = app.textFields["Name"]
        scrollTo(name, in: app, upwards: false)
        name.tap()
        name.typeText(" UI save")
        app.navigationBars.buttons["Close"].tap()
        dismissConfirmation(app, cancel: "Keep editing")
        let save = app.buttons["savePageOnServer"]
        scrollTo(save, in: app)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.buttons["Simulate save"].waitForExistence(timeout: 3))
        dismissConfirmation(app)
        XCTAssertTrue(save.isEnabled, "Cancelling confirmation must leave the edit pending.")
        save.tap()
        app.buttons["Simulate save"].tap()
        let acknowledgement = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Simulated save. Page storage acknowledged.")).firstMatch
        scrollTo(acknowledgement, in: app)
        XCTAssertTrue(acknowledgement.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        scrollTo(app.buttons["Undo"], in: app)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
    }

    @MainActor
    func testPageConflictPreservesDraftUntilExplicitReload() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10), app.staticTexts["connectionMessage"].firstMatch.debugDescription)
        selectTab("Settings", in: app)
        app.buttons["demoOutcomePicker"].tap()
        app.buttons["Rejected"].tap()
        openPageEditor(app)
        let name = app.textFields["Name"]
        scrollTo(name, in: app)
        name.tap()
        name.typeText(" conflict work")
        app.navigationBars.buttons["Close"].tap()
        dismissConfirmation(app, cancel: "Keep editing")
        let save = app.buttons["savePageOnServer"]
        scrollTo(save, in: app)
        save.tap()
        app.buttons["Simulate save"].tap()
        let conflict = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "The server page changed.")).firstMatch
        scrollTo(conflict, in: app)
        XCTAssertTrue(conflict.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        let fetch = app.buttons["Fetch server page for comparison"]
        scrollTo(fetch, in: app, upwards: false)
        fetch.tap()
        let reload = app.buttons["Reload compared page…"]
        scrollTo(reload, in: app)
        XCTAssertTrue(reload.waitForExistence(timeout: 5))
        scrollTo(name, in: app, upwards: false)
        XCTAssertTrue((name.value as? String)?.contains("conflict work") == true)
        scrollTo(reload, in: app)
        reload.tap()
        dismissConfirmation(app, cancel: "Keep local work")
        XCTAssertTrue(reload.exists)
        reload.tap()
        app.buttons["Preserve local draft and reload"].tap()
        let reloaded = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Reloaded the compared server page")).firstMatch
        scrollTo(reloaded, in: app)
        XCTAssertTrue(reloaded.waitForExistence(timeout: 5))
        scrollTo(name, in: app, upwards: false)
        XCTAssertEqual(name.value as? String, "Welcome")
        scrollTo(app.buttons["Undo"], in: app)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
    }

    @MainActor
    private func openPageEditor(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10))
        selectTab("Library", in: app)
        app.staticTexts["Welcome"].tap()
        app.buttons["editLocalDraft"].tap()
        XCTAssertTrue(app.navigationBars["Page editor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Name"].exists)
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        for _ in 0..<10 {
            // A field partly under the sheet's navigation bar may report
            // hittable although a tap lands on the bar and never focuses it.
            let navigationBottom = app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? 0
            if element.exists && element.isHittable && element.frame.midY > navigationBottom + 12 { return }
            if upwards { app.swipeUp() } else { app.swipeDown() }
        }
    }
}

extension DemoUITests {
    @MainActor
    func testDemoDisconnectReturnsToNativeServerPicker() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10), app.staticTexts["connectionMessage"].firstMatch.debugDescription)
        selectTab("Settings", in: app)
        app.buttons["Disconnect"].tap()
        XCTAssertTrue(app.buttons["findFiestaBoard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["connectionAddress"].exists)
        XCTAssertTrue(app.buttons["exploreDemo"].exists)
        XCTAssertFalse(app.secureTextFields["connectionPassword"].exists)
    }
}

/// These scenarios use a loopback fixture process, never the user's server.
/// Start with: python3 Tests/UITests/fixture_server.py
final class ConnectionUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    @MainActor
    func testFirstRunCreatesAdministratorAndLoadsShell() async throws {
        try await requireFixture()
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let alias = connect(app, scenario: "setup")
        let requireSignIn = app.buttons["Require sign-in"]
        XCTAssertTrue(requireSignIn.waitForExistence(timeout: 8), app.staticTexts["connectionMessage"].firstMatch.debugDescription)
        reveal(requireSignIn, app)
        requireSignIn.tap()
        let username = app.textFields["Administrator username"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        reveal(username, app); username.tap(); username.typeText("fixture_admin")
        let password = app.secureTextFields["connectionNewPassword"]
        reveal(password, app); password.tap()
        if app.buttons["Fill Strong Password"].waitForExistence(timeout: 2) {
            app.buttons["Close"].firstMatch.tap()
        }
        password.typeText("fixture-password")
        let create = app.buttons["Create administrator"]
        reveal(create, app); create.tap()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10), app.staticTexts["connectionMessage"].firstMatch.debugDescription)
        XCTAssertFalse(app.buttons["Compose text"].isEnabled, "Setup must not implicitly enable board changes.")
        selectTab("Library", in: app)
        XCTAssertTrue(app.staticTexts["Document"].waitForExistence(timeout: 5))
        selectTab("Settings", in: app)
        let logout = app.buttons["Log out & disconnect"]
        reveal(logout, app); logout.tap()
        XCTAssertTrue(app.buttons["exploreDemo"].waitForExistence(timeout: 5))
        removeSaved(alias, app)
    }

    @MainActor
    func testWrongPasswordRotationRememberedReopenAndLogout() async throws {
        try await requireFixture()
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let alias = connect(app, scenario: "signin")
        let username = app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout: 8), app.staticTexts["connectionMessage"].firstMatch.debugDescription)
        reveal(username, app); username.tap(); username.typeText("fixture_admin")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(username.value as? String, "fixture_admin")
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let password = app.secureTextFields["connectionPassword"]
        reveal(password, app); password.tap(); password.typeText("wrong-fixture-password")
        let signIn = app.buttons["connectionSignIn"]
        reveal(signIn, app); signIn.tap()
        let error = app.staticTexts["connectionMessage"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "The username or password is incorrect.")
        XCTAssertEqual(username.value as? String, "fixture_admin")
        reveal(password, app); password.tap(); password.typeText("fixture-password")
        let remember = app.switches["Remember sign-in"]
        reveal(remember, app); remember.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(remember.value as? String, "1")
        reveal(signIn, app); signIn.tap()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10), app.staticTexts["connectionMessage"].firstMatch.debugDescription)
        selectTab("Settings", in: app)
        XCTAssertFalse(app.staticTexts["Remembered sign-in needs attention. Sign in again or forget the saved session."].exists,
                       "The active login must have persisted successfully before testing relaunch.")
        app.terminate(); app.launch()
        let saved = app.buttons.containing(.staticText, identifier: alias).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        reveal(saved, app); saved.tap()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10), "Remembered sign-in must survive process relaunch.")
        selectTab("Settings", in: app)
        let logout = app.buttons["Log out & disconnect"]
        reveal(logout, app); logout.tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        reveal(saved, app); saved.tap()
        XCTAssertTrue(password.waitForExistence(timeout: 8), "Logging out must forget the remembered session.")
        let choose = app.buttons["Choose another server"]
        reveal(choose, app); choose.tap()
        removeSaved(alias, app)
    }

    @MainActor
    func testFirstRunWithoutAuthenticationAtLargeTextSize() async throws {
        try await requireFixture()
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let alias = connect(app, scenario: "setup")
        let skip = app.buttons["Continue without sign-in"]
        reveal(skip, app)
        XCTAssertTrue(skip.waitForExistence(timeout: 8))
        skip.tap()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10), app.staticTexts["connectionMessage"].firstMatch.debugDescription)
        XCTAssertFalse(app.buttons["Compose text"].isEnabled)
        selectTab("Settings", in: app)
        let disconnect = app.buttons["Disconnect"]
        reveal(disconnect, app); disconnect.tap()
        removeSaved(alias, app)
    }

    @MainActor private func removeSaved(_ alias: String, _ app: XCUIApplication) {
        let row = app.cells.containing(.staticText, identifier: alias).firstMatch
        reveal(row, app)
        let remove = row.buttons["Remove"]
        XCTAssertTrue(remove.exists)
        remove.tap()
        let confirm = app.buttons["Remove server & forget sign-in"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
    }

    @MainActor @discardableResult
    private func connect(_ app: XCUIApplication, scenario: String) -> String {
        let alias = scenario + "-" + UUID().uuidString.prefix(8).lowercased()
        let address = app.textFields["connectionAddress"]
        XCTAssertTrue(app.buttons["exploreDemo"].waitForExistence(timeout: 8))
        reveal(address, app)
        XCTAssertTrue(address.exists)
        address.tap(); address.typeText("http://127.0.0.1:18442/" + alias)
        let name = app.textFields["Server name (optional)"]
        reveal(name, app); name.tap(); name.typeText(alias)
        let localHTTP = app.switches["connectionLocalHTTP"]
        reveal(localHTTP, app); localHTTP.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(localHTTP.value as? String, "1")
        let connect = app.buttons["connectionConnect"]
        reveal(connect, app); connect.tap()
        return alias
    }

    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeDown()
        }
    }

    @MainActor private func requireFixture() async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:18442/ready")!)
        request.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("native-onboarding"),
                      "Start Tests/UITests/fixture_server.py before the UI suite.")
    }
}

@MainActor final class PageLibraryUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    func testCreateLEDPageOpenEditorAndDeleteFromLibrary() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10))
        selectTab("Library", in: app)
        let create = app.buttons["newLibraryPage"]
        XCTAssertTrue(create.waitForExistence(timeout: 3)); create.tap()
        let name = app.textFields["New page name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3)); name.tap(); name.typeText("Native LED test")
        app.buttons["pageFamilyPicker"].tap(); app.buttons["LED panel"].tap()
        app.buttons["createLibraryPage"].tap()
        XCTAssertTrue(app.navigationBars["Page editor"].waitForExistence(timeout: 8))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Native LED test"].waitForExistence(timeout: 4))
        app.staticTexts["Native LED test"].tap()
        let remove = app.buttons["deleteLibraryPage"]
        if !remove.isHittable { app.swipeUp() }
        remove.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Delete page"].tap()
        XCTAssertTrue(app.buttons["newLibraryPage"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Native LED test"].exists)
    }
}
