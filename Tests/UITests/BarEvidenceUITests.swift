import XCTest

/// W4 bar pass: captures for bar items no other UI test photographs (B4, B5, B7 on Home; the
/// editor at accessibility text size, B31; the editor and Home in the current appearance, B34),
/// against the mock fixture's `/board-<scenario>-<n>/` prefix. No real server, no hardware.
/// Screenshots are attachments and, with `SHOT_DIR`, files named `W4-<item>-<device>[-<SHOT_SUFFIX>]-mockfixture.png`.
/// Run the appearance test once per appearance (`xcrun simctl ui <udid> appearance dark|light`),
/// passing `TEST_RUNNER_SHOT_SUFFIX=dark|light`.
@MainActor final class BarEvidenceUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipadair11m4" : "iphone17promax" }
    private var fixturePort: Int { Int(FixtureHTTPServer.shared.port) }
    private var suffix: String { ProcessInfo.processInfo.environment["SHOT_SUFFIX"].map { "-" + $0 } ?? "" }

    /// B4 (Pixoo, LED dots, `Hi {red}!`), B7 (its `layers` composited) and B5 (the monochrome
    /// "Marquee" and the unknown-model "Mystery" drawn as flaps) on Home.
    func testLedAndModelBoardsOnHome() throws {
        let app = try signIn(scenario: "manual")
        let board = element(app, "homeBoard")
        for (display, file, check) in [("Pixoo", "B4-B7-pixoo", "Hi"), ("Marquee — mock-only", "B5-marquee", "HOT"),
                                       ("Mystery", "B5-mystery", "UNKNOWN MODEL")] {
            choose(display, app)
            XCTAssertTrue(waitFor(10) { ((board.value as? String) ?? "").localizedCaseInsensitiveContains(check) }, "\(display): \(board.value ?? "-")")
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "web preview")).firstMatch.exists)
            shot(app, "W4-\(file)", settle: 3)
        }
    }

    /// I7: capture the actual Home hierarchy at AX3, with its audited scoped fixture.
    func testHomeAtAccessibilityTextSize() throws {
        try requireReadyFixture(port: String(fixturePort))
        let app = isolatedApplication()
        launchFixture(app, arguments: ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraLarge.rawValue], scenario: "i7-manual")
        let board = element(app, "homeBoard")
        XCTAssertTrue(waitFor(10) { ((board.value as? String) ?? board.label).contains("HELLO") }, "Home must contain its delivered board")
        XCTAssertTrue(app.navigationBars["Home"].exists)
        XCTAssertTrue(element(app, "nowShowingName").exists)
        shot(app, "I7-home-AX3", settle: 4)
        let change = app.buttons["changePage"]
        reveal(change, app)
        XCTAssertTrue(change.isHittable, "Change Page must remain reachable at AX3")
        XCTAssertTrue(change.isEnabled, "The scoped fixture must preserve the actual Home control")
        close(app)
    }

    /// B31: the editor at accessibility XL text: chips, tiles and rows re-rasterise at the size.
    /// (The in-app demo: at this size the connection form's fields move out of the helper's reach.)
    func testEditorAtAccessibilityTextSize() throws {
        let app = isolatedApplication()
        launchFixture(app, arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 15))
        let destination = app.buttons.matching(identifier: "destination-Pages").firstMatch
        for _ in 0..<5 where !(destination.exists && destination.isHittable) {
            let sidebar = app.buttons["Show Sidebar"].firstMatch
            if sidebar.exists && sidebar.isHittable { sidebar.tap(); continue }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists && back.isHittable { back.tap() }
        }
        destination.tap()
        let create = app.buttons["newLibraryPage"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        let field = app.textFields["New page name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3)); field.tap(); field.typeText("Large text\n")
        app.buttons["createLibraryPage"].tap()
        let document = app.textViews["boardDocument"]
        XCTAssertTrue(document.waitForExistence(timeout: 8), app.debugDescription)
        document.tap(); document.typeText("HELLO ")
        app.buttons["accessory_colors"].tap()
        let red = app.buttons["insertColor_red"]
        if red.waitForExistence(timeout: 4) { red.tap() }
        let hide = app.buttons["editorHideKeyboard"]
        if hide.waitForExistence(timeout: 3) && hide.isHittable { hide.tap() }
        shot(app, "W4-B31-editor-accessibility-xl", settle: 4)
        close(app)
    }

    /// B31/B34: Home, the editor and the formula editor in the current appearance (run light and dark).
    func testAppearance() throws {
        let app = try signIn(scenario: "manual")
        shot(app, "W4-B34-home", settle: 4)
        let document = openEditor(app, page: "Good Morning")
        XCTAssertTrue(document.exists)
        shot(app, "W4-B34-editor", settle: 4)
        close(app)
    }

    /// B16 (W4, real-server behaviour): "Mixed Case" keeps its lowercase row; on the Kitchen
    /// (a flap board) the render reports each lowercase letter in `charset_issues`, and the editor
    /// lists them, grouped per row and reason (P5: "Line 2: lowercase letters show as capitals on
    /// this board (12)."). The document is not changed.
    func testCharsetIssuesAreListed() throws {
        let app = try signIn(scenario: "manual")
        let document = openEditor(app, page: "Mixed Case")
        XCTAssertTrue(((document.value as? String) ?? "").contains("lower row kept"), "the lowercase row is kept as written")
        let issues = element(app, "charsetIssues")
        XCTAssertTrue(issues.waitForExistence(timeout: 8), app.debugDescription)
        // Re-recorded (P5): grouped per row and reason, not one line per letter.
        XCTAssertEqual(issues.label, "Line 2: lowercase letters show as capitals on this board (12).")
        // One group can still truncate on a narrow display. Expansion must preserve its text.
        let more = app.buttons["charsetIssuesShowAll"]
        if more.exists {
            more.tap()
            XCTAssertEqual(issues.label, "Line 2: lowercase letters show as capitals on this board (12).")
            XCTAssertEqual(more.label, "Show less")
        }
        shot(app, "W4-B16-charset-issues", settle: 3)
        close(app)
    }

    // MARK: Helpers

    private func signIn(scenario: String, arguments: [String] = []) throws -> XCUIApplication {
        try requireReadyFixture(port: String(fixturePort))
        let app = isolatedApplication()
        app.launchArguments = arguments; app.launch()
        let alias = "board-\(scenario)-" + UUID().uuidString.prefix(8).lowercased()
        let address = app.textFields["connectionAddress"]
        XCTAssertTrue(app.textFields["connectionAddress"].waitForExistence(timeout: 10))
        reveal(address, app); typeConnectionAddress("http://127.0.0.1:\(fixturePort)/" + alias, into: address, in: app)
        let name = app.textFields["Server name (optional)"]
        reveal(name, app); name.tap(); name.typeText(alias + "\n")
        let localHTTP = app.switches["connectionLocalHTTP"]
        reveal(localHTTP, app)
        for _ in 0..<3 where localHTTP.value as? String != "1" {
            localHTTP.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: localHTTP)], timeout: 2)
        }
        let connect = app.buttons["connectionConnect"]
        reveal(connect, app); connect.tap()
        let username = app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout: 10), app.staticTexts["connectionMessage"].firstMatch.debugDescription)
        reveal(username, app); username.tap(); username.typeText("fixture_admin")
        let password = app.secureTextFields["connectionPassword"]
        reveal(password, app); password.tap(); password.typeText("fixture-password")
        let signIn = app.buttons["connectionSignIn"]
        reveal(signIn, app); signIn.tap()
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 15), app.debugDescription)
        return app
    }
    private func choose(_ display: String, _ app: XCUIApplication) {
        selectFixtureDisplay(display, in: app)
    }
    private func openEditor(_ app: XCUIApplication, page: String) -> XCUIElement {
        let destination = app.buttons.matching(identifier: "destination-Pages").firstMatch
        for _ in 0..<5 {
            if destination.exists && destination.isHittable { destination.tap(); break }
            let sidebar = app.buttons["Show Sidebar"].firstMatch
            if sidebar.exists && sidebar.isHittable { sidebar.tap(); continue }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists && back.isHittable { back.tap() }
        }
        let row = pageCard(app, named: page)
        XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        let edit = app.buttons["editLocalDraft"]
        for _ in 0..<4 { if edit.exists && edit.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let document = app.textViews["boardDocument"]
        XCTAssertTrue(document.waitForExistence(timeout: 8), app.debugDescription)
        return document
    }
    private func close(_ app: XCUIApplication) {
        app.navigationBars.buttons["Close"].tap()
        let discard = app.buttons["Discard and leave"]
        if discard.waitForExistence(timeout: 2) { discard.tap() }
    }
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func waitFor(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat { if condition() { return true }; Thread.sleep(forTimeInterval: 0.2) } while Date() < deadline
        return false
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<20 { if element.exists && element.isHittable { break }; app.swipeUp() }
        for _ in 0..<20 { if element.exists && element.isHittable { break }; app.swipeDown() }
    }
    private func shot(_ app: XCUIApplication, _ name: String, settle: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: settle)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(name)-\(device)\(suffix)-mockfixture"; attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(device)\(suffix)-mockfixture.png"))
        }
    }
}
