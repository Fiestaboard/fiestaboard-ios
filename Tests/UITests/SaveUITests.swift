import XCTest

/// W4 (PLAN B25/B28, end to end): Save against the mock fixture's legacy page write path
/// (`PUT /v1/pages/{id}` in `fixture_boards.py`), then close and reopen. Each test proves the change
/// twice: in the fixture's storage (`GET /fixture-state/<alias>/pages/<id>`, a loopback, test-only,
/// read-only route) and in the reopened editor. No real server, no hardware. Screenshots are
/// attached and, with `SHOT_DIR` (`TEST_RUNNER_SHOT_DIR`), written as `W4-save-*-<device>-mockfixture.png`.
@MainActor final class SaveUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipadair11m4" : "iphone17promax" }
    private var fixturePort: Int { Int(ProcessInfo.processInfo.environment["FIXTURE_PORT"] ?? "") ?? 18442 }
    private var alias = ""

    // MARK: The four edits

    /// A text edit: row 1 of "Hello World" is typed, saved, and reads back after reopening.
    func testTextEditPersistsAfterReopen() throws {
        let app = try signInWithChanges()
        var document = openEditor(app, page: "Hello World")
        placeCaret(row: 1, app, document)
        document.typeText("SAVED TEXT")
        XCTAssertTrue(waitFor(10) { self.stageLines(app).first == "SAVED TEXT" }, "\(stageLines(app))")
        hideKeyboard(app)
        shot(app, "W4-save-text-edited")
        save(app)
        let stored = try fixturePage("hello")
        XCTAssertEqual((stored["template"] as? [String])?.first, "SAVED TEXT", "the fixture stored the edit")
        let rows = stored["template"] as? [String] ?? []
        XCTAssertEqual(rows.count > 2 ? rows[2] : nil, "HELLO {{red}}{{orange}}{{yellow}} WORLD 62°", "untouched rows kept: \(rows)")
        document = reopen(app, page: "Hello World")
        XCTAssertEqual(source(document).components(separatedBy: "\n").first, "SAVED TEXT")
        XCTAssertTrue(waitFor(6) { self.stageLines(app).first == "SAVED TEXT" }, "\(stageLines(app))")
        XCTAssertEqual(element(app, "saveStatus").value as? String, "Saved")
        shot(app, "W4-save-text-reopened")
        close(app)
    }

    /// A geometry change: the 12 × 29 "Lobby" panel becomes a Flagship (6 × 22), confirmed with
    /// "Resize and save" (B28), and reopens as a 6 × 22 board.
    func testGeometryChangePersistsAfterReopen() throws {
        let app = try signInWithChanges()
        _ = openEditor(app, page: "Lobby")
        XCTAssertEqual(app.staticTexts["boardSizeReadout"].label, "Board size 12 by 29")
        app.buttons["evaluationBoardPicker"].tap()
        // The menu lists the displays first; the board sizes may be below its fold.
        let flagship = app.buttons["Flagship · 6 × 22"].firstMatch
        XCTAssertTrue(flagship.waitForExistence(timeout: 3), app.debugDescription)
        let window = app.windows.firstMatch.frame
        for _ in 0..<6 where !(flagship.isHittable && flagship.frame.maxY < window.maxY - 10) {
            if !flagship.exists { app.buttons["evaluationBoardPicker"].tap(); _ = flagship.waitForExistence(timeout: 3); continue }
            // Scroll the menu itself (a swipe on one of its items), never across the page.
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Living room TV")).firstMatch.swipeUp(velocity: .slow)
        }
        flagship.tap()
        XCTAssertTrue(waitFor(10) { app.staticTexts["boardSizeReadout"].label == "Board size 6 by 22" })
        shot(app, "W4-save-geometry-changed")
        app.buttons["savePageOnServer"].tap()
        let resize = app.buttons["resizeAndSave"].firstMatch
        XCTAssertTrue(resize.waitForExistence(timeout: 3), "Shrinking asks first (B28)")
        resize.tap()
        waitForClosed(app)
        let stored = try fixturePage("lobby")
        XCTAssertEqual(stored["device_type"] as? String, "flagship")
        // grid_rows/grid_cols are left as stored: 10.3.2 reads them only for panels (PageUpdate).
        XCTAssertEqual((stored["template"] as? [String])?.first, "WELCOME TO THE LOBBY")
        _ = reopen(app, page: "Lobby")
        XCTAssertTrue(waitFor(10) { app.staticTexts["boardSizeReadout"].label == "Board size 6 by 22" }, app.staticTexts["boardSizeReadout"].label)
        XCTAssertFalse(app.staticTexts["documentRow_7"].exists, "6 rows for a Flagship")
        shot(app, "W4-save-geometry-reopened")
        close(app)
    }

    /// A draw-mode stroke (B23): five red tiles painted on the empty row 3 of "Good Morning" are
    /// saved as `{{red}}` tiles and come back after reopening.
    func testDrawStrokePersistsAfterReopen() throws {
        let app = try signInWithChanges()
        var document = openEditor(app, page: "Good Morning")
        XCTAssertTrue(waitFor(6) { self.stageLines(app).first == "     GOOD MORNING" }, "\(stageLines(app))")
        let draw = app.buttons["toolbar_draw"]
        XCTAssertTrue(draw.waitForExistence(timeout: 3)); draw.tap()
        XCTAssertTrue(element(app, "drawHint").waitForExistence(timeout: 3))
        app.buttons["drawBrush_red"].tap()
        let stage = element(app, "boardStage")
        tile(stage, row: 2, col: 0).press(forDuration: 0.1, thenDragTo: tile(stage, row: 2, col: 4))
        app.buttons["drawDone"].tap()
        XCTAssertTrue(document.waitForExistence(timeout: 4))
        let painted = String(repeating: "{{red}}", count: 5)
        XCTAssertEqual(source(document).components(separatedBy: "\n").dropFirst(2).first, painted, source(document))
        shot(app, "W4-save-draw-painted")
        save(app)
        let stored = try fixturePage("morning")
        let template = stored["template"] as? [String] ?? []
        XCTAssertEqual(template.count > 2 ? template[2] : nil, painted, "the fixture stored the stroke: \(template)")
        XCTAssertEqual(template.first, "GOOD MORNING", "untouched rows kept")
        document = reopen(app, page: "Good Morning")
        XCTAssertEqual(source(document).components(separatedBy: "\n").dropFirst(2).first, painted, source(document))
        shot(app, "W4-save-draw-reopened")
        close(app)
    }

    /// A canvas edit (B24): the "sun" canvas's area is dragged to rows 3–8 × columns 5–14 on
    /// "Pixel Clock" (Pixoo), saved, and the area picker reads the same after reopening.
    func testCanvasEditPersistsAfterReopen() throws {
        let app = try signInWithChanges()
        _ = openEditor(app, page: "Pixel Clock")
        let surface = app.segmentedControls["editingSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        surface.buttons["Canvases"].tap()
        let picker = element(app, "canvasAreaPicker")
        XCTAssertTrue(picker.waitForExistence(timeout: 4))
        revealInPanel(picker, app)
        XCTAssertEqual(picker.value as? String, "Rows 1 to 5, columns 1 to 8")
        let frame = picker.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let from = origin.withOffset(CGVector(dx: frame.minX + frame.width * 4.5 / 16, dy: frame.minY + frame.height * 2.5 / 10))
        let to = origin.withOffset(CGVector(dx: frame.minX + frame.width * 13.5 / 16, dy: frame.minY + frame.height * 7.5 / 10))
        from.press(forDuration: 0.2, thenDragTo: to, withVelocity: 150, thenHoldForDuration: 0.2)
        // The drag lands within a cell of its target (the grid is small); what matters is that
        // the area the picker shows is the area saved and reopened.
        XCTAssertTrue(waitFor(10) { (picker.value as? String)?.hasPrefix("Rows 3 to 8") == true }, "\(picker.value ?? "")")
        let edited = picker.value as? String ?? ""
        let numbers = edited.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        shot(app, "W4-save-canvas-edited")
        save(app)
        let stored = try fixturePage("pixel")
        let canvas = (stored["canvases"] as? [[String: Any]])?.first
        let area = canvas?["area"] as? [String: Int]
        XCTAssertEqual(numbers.count, 4, edited)
        if numbers.count == 4 {
            XCTAssertEqual(area, ["row": numbers[0], "col": numbers[2], "rows": numbers[1] - numbers[0] + 1, "cols": numbers[3] - numbers[2] + 1], "\(stored["canvases"] ?? "-")")
        }
        XCTAssertEqual(canvas?["id"] as? String, "sun")
        XCTAssertEqual(((canvas?["content"] as? [String: Any])?["shapes"] as? [Any])?.count, 2, "untouched shapes kept")
        _ = reopen(app, page: "Pixel Clock")
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        surface.buttons["Canvases"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 4))
        revealInPanel(picker, app)
        XCTAssertEqual(picker.value as? String, edited)
        shot(app, "W4-save-canvas-reopened")
        close(app)
    }

    // MARK: Flow helpers

    /// Sign in to a fresh `/board-manual-<id>/` prefix and turn on changes for this server, so the
    /// session may write pages (the same opt-in a person makes in Settings).
    private func signInWithChanges() throws -> XCUIApplication {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(fixturePort)/ready")!); request.timeoutInterval = 3
        let semaphore = DispatchSemaphore(value: 0); var ready = false
        URLSession.shared.dataTask(with: request) { _, response, _ in ready = (response as? HTTPURLResponse)?.statusCode == 200; semaphore.signal() }.resume()
        semaphore.wait()
        try XCTSkipUnless(ready, "Start the fixture: FIXTURE_PORT=\(fixturePort) python3 Tests/UITests/fixture_server.py")
        let app = isolatedApplication()
        app.launchArguments = []; app.launch()
        alias = "board-manual-" + UUID().uuidString.prefix(8).lowercased()
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
    private func selectDestination(_ name: String, _ app: XCUIApplication) {
        let destination = element(app, "destination-" + name)
        for _ in 0..<5 {
            if destination.exists && destination.isHittable { destination.tap(); return }
            let sidebar = app.buttons["Show Sidebar"].firstMatch
            if sidebar.exists && sidebar.isHittable { sidebar.tap(); continue }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists && back.isHittable { back.tap() }
        }
        XCTAssertTrue(destination.waitForExistence(timeout: 3)); destination.tap()
    }
    /// Pages → the page's screen → Edit Page. Save must be possible once there are changes.
    private func openEditor(_ app: XCUIApplication, page: String) -> XCUIElement {
        selectDestination("Pages", app)
        let row = pageCard(app, named: page)
        XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        let edit = app.buttons["editLocalDraft"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let document = app.textViews["boardDocument"]
        XCTAssertTrue(document.waitForExistence(timeout: 8), app.debugDescription)
        return document
    }
    /// Save, the "Page updated" acknowledgement, and back out of the editor.
    private func save(_ app: XCUIApplication) {
        hideKeyboard(app)
        let save = app.buttons["savePageOnServer"]
        XCTAssertTrue(waitFor(5) { save.isEnabled }, "Save is enabled: \(element(app, "saveDisabledReason").label)")
        save.tap()
        waitForClosed(app)
    }
    private func waitForClosed(_ app: XCUIApplication) {
        XCTAssertTrue(app.textViews["boardDocument"].waitForNonExistence(timeout: 10), "Saved and back out of the editor: \(element(app, "saveDisabledReason").label)")
    }
    /// Close → reopen from the Pages list (the page screen re-reads the stored page).
    private func reopen(_ app: XCUIApplication, page: String) -> XCUIElement {
        let edit = app.buttons["editLocalDraft"]
        if edit.waitForExistence(timeout: 2) && edit.isHittable {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists && back.isHittable { back.tap() }
        }
        let document = openEditor(app, page: page)
        XCTAssertFalse(element(app, "recoveryBanner").waitForExistence(timeout: 2), "A saved page reopens without a recovery prompt")
        return document
    }
    private func close(_ app: XCUIApplication) {
        hideKeyboard(app)
        app.navigationBars.buttons["Close"].tap()
        let discard = app.buttons["Discard and leave"]
        if discard.waitForExistence(timeout: 2) { discard.tap() }
    }

    /// The fixture's stored copy of a page for this test's prefix.
    private func fixturePage(_ id: String) throws -> [String: Any] {
        let url = URL(string: "http://127.0.0.1:\(fixturePort)/fixture-state/\(alias)/pages/\(id)")!
        let semaphore = DispatchSemaphore(value: 0); var body: Data?; var status = 0
        URLSession.shared.dataTask(with: url) { data, response, _ in
            body = data; status = (response as? HTTPURLResponse)?.statusCode ?? 0; semaphore.signal()
        }.resume()
        semaphore.wait()
        XCTAssertEqual(status, 200)
        let page = try XCTUnwrap(try body.flatMap { try JSONSerialization.jsonObject(with: $0) } as? [String: Any])
        XCTAssertTrue((page["revision"] as? String)?.contains("saved") == true, "the fixture saw a PUT: \(page["revision"] ?? "-")")
        let note = XCTAttachment(string: String(data: try JSONSerialization.data(withJSONObject: page, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8) ?? "")
        note.name = "fixture page \(id) after save"; note.lifetime = .keepAlways; add(note)
        return page
    }

    // MARK: Small helpers

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func source(_ document: XCUIElement) -> String { (document.value as? String) ?? "" }
    private func stageLines(_ app: XCUIApplication) -> [String] {
        ((element(app, "boardStage").value as? String) ?? "").components(separatedBy: "\n").map { line in
            var line = line; while line.last == " " { line.removeLast() }; return line
        }
    }
    private func waitFor(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat { if condition() { return true }; Thread.sleep(forTimeInterval: 0.2) } while Date() < deadline
        return condition()
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<20 { if element.exists && element.isHittable { break }; app.swipeUp() }
        for _ in 0..<20 { if element.exists && element.isHittable { break }; app.swipeDown() }
    }
    private func placeCaret(row n: Int, _ app: XCUIApplication, _ document: XCUIElement) {
        let gutter = app.staticTexts["documentRow_\(n)"]
        XCTAssertTrue(gutter.waitForExistence(timeout: 3))
        document.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: document.frame.width - 12, dy: gutter.frame.midY - document.frame.minY)).tap()
    }
    private func hideKeyboard(_ app: XCUIApplication) {
        let hide = app.buttons["editorHideKeyboard"]
        if hide.exists && hide.isHittable { hide.tap() }
        _ = waitFor(3) { !app.keyboards.firstMatch.exists || !hide.isHittable }
    }
    /// The centre of a tile on the 6 × 22 stage (the board frame's bezel and gutter proportions).
    private func tile(_ stage: XCUIElement, row: Int, col: Int, rows: Int = 6, cols: Int = 22) -> XCUICoordinate {
        let width = Double(cols) * 0.845 - 0.145 + 2 * 0.50
        let height = Double(rows) * 1.145 - 0.145 + 2 * 0.65
        let x = (0.50 + Double(col) * 0.845 + 0.35) / width
        let y = (0.65 + Double(row) * 1.145 + 0.50) / height
        return stage.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }
    /// Scroll the canvases panel by a caption that sits on no drawing surface (a drag that starts
    /// on the area grid edits it instead of scrolling).
    private func revealInPanel(_ target: XCUIElement, _ app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let toggle = app.segmentedControls["editingSurface"]
        func top() -> CGFloat { toggle.exists ? toggle.frame.maxY + 8 : window.minY + 80 }
        func visible() -> Bool { target.exists && target.isHittable && target.frame.maxY < window.maxY - 20 && target.frame.minY > top() }
        for _ in 0..<12 {
            if visible() { break }
            let handle = element(app, "canvasesPanelHandle")
            let from = handle.exists ? handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                : app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let up = !target.exists || target.frame.maxY >= window.maxY - 20
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: up ? -160 : 160)), withVelocity: 600, thenHoldForDuration: 0.1)
        }
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1.5)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(name)-\(device)-mockfixture"; attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(device)-mockfixture.png"))
        }
    }
}
