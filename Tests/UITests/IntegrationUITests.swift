import XCTest

/// Wave-2 integration checks (iOS-E2 editor × iOS-R2 shell), against the mock fixture
/// (the native in-process loopback fixture) or the in-app demo service.
/// No real server, no hardware. Screenshots go to SHOT_DIR when set (always attached too).
@MainActor final class IntegrationUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait; super.tearDown() }

    private var port: String { String(FixtureHTTPServer.shared.port) }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipadair11m4" : "iphone17promax" }

    // MARK: B29 on iPad: the sidebar gives way to the editor and comes back

    /// An existing page opened from the Pages list collapses the sidebar; Close restores it. The
    /// stage shows the fixture's sample values, never token names.
    func testIPadSidebarFollowsTheEditorForAnExistingPage() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        XCUIDevice.shared.orientation = .portrait
        let app = isolatedApplication()
        // Sign in upright: the iPad connection form is flaky in landscape (E1 open issue 5).
        try connectToFixture(app, scenario: "manual")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1)
        openPages(app)
        XCTAssertTrue(waitForSidebar(app, visible: true), "sidebar shows on the Pages list")
        shot(app, "W2-INT-sidebar-pages")

        openEditor(app, page: "Good Morning")
        XCTAssertTrue(waitForSidebar(app, visible: false), "sidebar collapses while the editor is open")
        // Sample values, not token names. (The formula row reads ??? today: the editor's request
        // carries board_id/canvases, so it misses render-cases.r2.json's exact case and the toy
        // fallback answers; routed to iOS-R2.)
        XCTAssertTrue(waitForStage(app, timeout: 8) { $0.contains { $0.contains("72") && $0.contains("SUNNY") } }, "\(stageLines(app))")
        assertNoTokenNames(app)
        shot(app, "W2-INT-existing-open")
        close(app)
        XCTAssertTrue(waitForSidebar(app, visible: true), "sidebar comes back after Close")
        shot(app, "W2-INT-existing-closed")

        // Close returns to the page's detail; go back to the list.
        for label in ["Pages", "Back"] where !app.staticTexts["Desk Note"].exists {
            let back = app.navigationBars.buttons[label].firstMatch
            if back.exists && back.isHittable { back.tap() }
        }
        // E2 saw the fixture's toy render print DATE_TIME.TIME here; R2's fallback answers 08:15.
        openEditor(app, page: "Desk Note")
        XCTAssertTrue(waitForStage(app, timeout: 8) { $0.count > 1 && $0[1].trimmingCharacters(in: .whitespaces) == "08:15" }, "\(stageLines(app))")
        assertNoTokenNames(app)
        shot(app, "W2-INT-stage-sample-values")
        close(app)
        XCTAssertTrue(waitForSidebar(app, visible: true))
    }

    /// A new page after Create collapses the sidebar too; rotating with the editor open keeps the
    /// text and the caret; Close restores the sidebar.
    func testIPadSidebarAndRotationForANewPage() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = isolatedApplication(); launchFixture(app)
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 10))
        openPages(app)
        XCTAssertTrue(waitForSidebar(app, visible: true))
        let create = app.buttons["newLibraryPage"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        let field = app.textFields["New page name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3)); field.tap(); field.typeText("Rotate check\n")
        app.buttons["createLibraryPage"].tap()
        let document = app.textViews["boardDocument"]
        XCTAssertTrue(document.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(waitForSidebar(app, visible: false), "sidebar collapses for the new page's editor")
        shot(app, "W2-INT-new-open")

        placeCaret(row: 1, app, document); document.typeText("ROTATE")
        placeCaret(row: 2, app, document); document.typeText("AB")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(document.exists, "the editor survives the rotation")
        document.typeText("C")
        XCTAssertTrue(waitForRows(document) { $0.count > 1 && $0[0] == "ROTATE" && $0[1] == "ABC" }, "caret kept in portrait: \(rows(document))")
        shot(app, "W2-INT-rotated-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        document.typeText("D")
        XCTAssertTrue(waitForRows(document) { $0.count > 1 && $0[0] == "ROTATE" && $0[1] == "ABCD" }, "caret kept in landscape: \(rows(document))")
        XCTAssertTrue(waitForSidebar(app, visible: false), "still collapsed after rotating back")
        shot(app, "W2-INT-rotated-landscape")
        close(app)
        XCTAssertTrue(waitForSidebar(app, visible: true), "sidebar comes back after closing the new page")
        shot(app, "W2-INT-new-closed")
    }

    // MARK: B29/B30 on iPhone: the editor covers the screen on both paths; Wrap is reachable

    func testPhoneEditorIsFullScreenOnBothPaths() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone only")
        let app = isolatedApplication()
        try connectToFixture(app, scenario: "manual")
        openPages(app)
        openEditor(app, page: "Good Morning")
        assertFullScreen(app, "existing page")
        shot(app, "W2-INT-existing-fullscreen")
        close(app)

        app.terminate(); launchFixture(app)
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 10))
        openPages(app)
        let create = app.buttons["newLibraryPage"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        let field = app.textFields["New page name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3)); field.tap(); field.typeText("Cover check\n")
        app.buttons["createLibraryPage"].tap()
        let document = app.textViews["boardDocument"]
        XCTAssertTrue(document.waitForExistence(timeout: 8), app.debugDescription)
        assertFullScreen(app, "after Create")
        shot(app, "W2-INT-create-fullscreen")
        placeCaret(row: 1, app, document); document.typeText("WRAP")
        let wrap = app.buttons["accessory_wrap"]
        XCTAssertTrue(wrap.waitForExistence(timeout: 3) && wrap.isHittable, "Wrap is on screen with the keyboard up")
        wrap.tap()
        XCTAssertTrue(wrap.isSelected, "Wrap toggles the caret row")
        shot(app, "W2-INT-keyboard-up")
        close(app)
    }

    // MARK: helpers

    /// A full-screen cover leaves nothing of the presenting screen: no grey band, no inset card.
    /// The editor's bar sits at the top of the window and spans its full width.
    private func assertFullScreen(_ app: XCUIApplication, _ path: String) {
        let bar = app.navigationBars.containing(.button, identifier: "Close").firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "editor bar (\(path))")
        Thread.sleep(forTimeInterval: 1)
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(bar.frame.width, window.width, accuracy: 1, "\(path): bar spans the window (a page sheet is inset)")
        XCTAssertLessThan(bar.frame.minY, 80, "\(path): bar is under the status bar, not below a sheet's grey band")
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "\(path): nothing of the presenting screen is reachable")
    }

    private func sidebarItem(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "destination-Pages").firstMatch
    }
    private func waitForSidebar(_ app: XCUIApplication, visible: Bool, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let item = sidebarItem(app)
            if (item.exists && item.isHittable) == visible { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return false
    }

    private func openPages(_ app: XCUIApplication) {
        let destination = sidebarItem(app)
        for _ in 0..<5 {
            if destination.exists && destination.isHittable { destination.tap(); return }
            let sidebar = app.buttons["Show Sidebar"].firstMatch
            if sidebar.exists && sidebar.isHittable { sidebar.tap(); continue }
            let back = app.navigationBars.buttons["FiestaBoard"].firstMatch
            if back.exists && back.isHittable { back.tap() }
        }
        XCTAssertTrue(destination.waitForExistence(timeout: 5)); destination.tap()
    }

    private func openEditor(_ app: XCUIApplication, page: String) {
        let card = app.staticTexts[page].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8), page); card.tap()
        let edit = app.buttons["editLocalDraft"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        XCTAssertTrue(app.textViews["boardDocument"].waitForExistence(timeout: 8), app.debugDescription)
    }

    private func close(_ app: XCUIApplication) {
        let hide = app.buttons["editorHideKeyboard"]
        if hide.exists && hide.isHittable { hide.tap() }
        app.navigationBars.buttons["Close"].firstMatch.tap()
        let discard = app.buttons["Discard and leave"]
        if discard.waitForExistence(timeout: 2) { discard.tap() }
        XCTAssertTrue(app.textViews["boardDocument"].waitForNonExistence(timeout: 5), "the editor closes")
    }

    private func placeCaret(row n: Int, _ app: XCUIApplication, _ document: XCUIElement) {
        let gutter = app.staticTexts["documentRow_\(n)"]
        XCTAssertTrue(gutter.waitForExistence(timeout: 3))
        let y = gutter.frame.midY - document.frame.minY
        document.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: document.frame.width - 12, dy: y)).tap()
    }
    private func rows(_ document: XCUIElement) -> [String] { ((document.value as? String) ?? "").components(separatedBy: "\n") }
    private func waitForRows(_ document: XCUIElement, timeout: TimeInterval = 3, _ condition: ([String]) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat { if condition(rows(document)) { return true } } while Date() < deadline
        return false
    }

    private func stageLines(_ app: XCUIApplication) -> [String] {
        ((app.descendants(matching: .any).matching(identifier: "boardStage").firstMatch.value as? String) ?? "")
            .components(separatedBy: "\n").map { line in
                var line = line; while line.last == " " { line.removeLast() }; return line
            }
    }
    private func waitForStage(_ app: XCUIApplication, timeout: TimeInterval = 3, _ condition: ([String]) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat { if condition(stageLines(app)) { return true } } while Date() < deadline
        return false
    }
    private func assertNoTokenNames(_ app: XCUIApplication) {
        let lines = stageLines(app)
        for token in ["WEATHER.", "DATE_TIME.", "{{", "IF("] {
            XCTAssertFalse(lines.contains { $0.contains(token) }, "stage shows a token name (\(token)): \(lines)")
        }
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 5) // let the flaps settle
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(name)-\(device)-mockfixture"; attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(device)-mockfixture.png"))
        }
    }

    /// Connect and sign in to the fixture's `/board-<scenario>-<id>/` prefix. The local-HTTP
    /// switch tap is retried (iOS-R2: on iPad the first tap can land while the keyboard leaves).
    private func connectToFixture(_ app: XCUIApplication, scenario: String) throws {
        try FixtureHTTPServer.shared.requireReady()
        app.launchArguments = []; app.launch()
        let alias = "board-" + scenario + "-" + UUID().uuidString.prefix(8).lowercased()
        let address = app.textFields["connectionAddress"]
        XCTAssertTrue(app.textFields["connectionAddress"].waitForExistence(timeout: 10))
        reveal(address, app); typeConnectionAddress("http://127.0.0.1:\(port)/" + alias, into: address, in: app)
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
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 15), app.staticTexts["connectionMessage"].firstMatch.debugDescription)
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 { if element.exists && element.isHittable { break }; app.swipeUp() }
        for _ in 0..<8 { if element.exists && element.isHittable { break }; app.swipeDown() }
    }
}
