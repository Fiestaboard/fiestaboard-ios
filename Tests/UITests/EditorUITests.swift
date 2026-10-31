import XCTest

/// Document editor (PLAN B12, B15, B16, B19, B25, B33). Runs against the in-app demo service,
/// a mock fixture: no real server, no hardware. Screenshots are attached with `-mockfixture` names.
@MainActor final class EditorUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name + "-mockfixture"; shot.lifetime = .keepAlways; add(shot)
    }

    /// Demo → Pages → New page (Flagship) → the document editor.
    private func openNewPage(_ app: XCUIApplication, name: String) -> XCUIElement {
        app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10))
        openPages(app)
        let create = app.buttons["newLibraryPage"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        let field = app.textFields["New page name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3)); field.tap(); field.typeText(name + "\n")
        app.buttons["createLibraryPage"].tap()
        let document = app.textViews["boardDocument"]
        XCTAssertTrue(document.waitForExistence(timeout: 8), app.debugDescription)
        return document
    }
    private func openPages(_ app: XCUIApplication) {
        let destination = app.descendants(matching: .any).matching(identifier: "destination-Pages").firstMatch
        for _ in 0..<5 {
            if destination.exists && destination.isHittable { destination.tap(); return }
            let sidebar = app.buttons["Show Sidebar"].firstMatch
            if sidebar.exists && sidebar.isHittable { sidebar.tap(); continue }
            let back = app.navigationBars.buttons["FiestaBoard"].firstMatch
            if back.exists && back.isHittable { back.tap() }
        }
        XCTAssertTrue(destination.waitForExistence(timeout: 5)); destination.tap()
    }
    /// Put the caret at the end of row `n` (1-based) by tapping the document at that row's height.
    private func placeCaret(row n: Int, _ app: XCUIApplication, _ document: XCUIElement) {
        let gutter = app.staticTexts["documentRow_\(n)"]
        XCTAssertTrue(gutter.waitForExistence(timeout: 3))
        let y = gutter.frame.midY - document.frame.minY
        document.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: document.frame.width - 12, dy: y)).tap()
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

    /// B12/B33: a new Flagship page is a title, a toolbar and six numbered rows of one surface,
    /// under the pinned 6×22 board. No JSON, no per-row fields, no inspector.
    func testNewPageIsBoardShaped() {
        let app = XCUIApplication()
        let document = openNewPage(app, name: "Board shaped")
        XCTAssertEqual(app.textViews.matching(identifier: "boardDocument").count, 1, "Exactly one document surface")
        XCTAssertEqual((document.value as? String)?.components(separatedBy: "\n").count, 6, "The surface's value spans six paragraphs")
        for n in 1...6 { XCTAssertTrue(app.staticTexts["documentRow_\(n)"].exists, "Gutter row \(n)") }
        XCTAssertFalse(app.staticTexts["documentRow_7"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "templateRowText").firstMatch.exists, "No per-row text views")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "templateCanvasRow0").firstMatch.exists, "No row cards")
        let title = app.textFields["pageTitle"]
        XCTAssertTrue(title.exists); XCTAssertEqual(title.value as? String, "Board shaped")
        XCTAssertEqual(app.staticTexts["lineCounter"].label, "1 / 6 lines")
        XCTAssertEqual(app.staticTexts["boardSizeReadout"].label, "Board size 6 by 22")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "saveStatus").firstMatch.value as? String, "Saved")
        // B33: the board is the largest element of the first screen; only title + toolbar above it.
        let stage = app.descendants(matching: .any).matching(identifier: "boardStage").firstMatch
        XCTAssertTrue(stage.exists)
        XCTAssertGreaterThan(stage.frame.width * stage.frame.height, title.frame.width * title.frame.height)
        // Text between the title and the board may only belong to the stage header row
        // (size readout, display picker label, fit note, updating) — no captions or disclaimers.
        let header = app.staticTexts["boardSizeReadout"].frame
        let aboveStage = app.staticTexts.allElementsBoundByIndex.filter { $0.exists && $0.frame.maxY <= stage.frame.minY && $0.frame.minY > title.frame.maxY }
        let strays = aboveStage.filter { $0.frame.midY < header.minY - 4 || $0.frame.midY > header.maxY + 4 }
        XCTAssertTrue(strays.isEmpty, "Only the stage header sits between the title and the board: \(strays.map(\.label))")
        attach(app, "D1-B12-new-page")
        attach(app, "D1-B33-editor")
        attach(app, "D1-B20-stage-header")

        // B16: Return on the last row adds a 7th numbered row; the counter and strip warn.
        placeCaret(row: 6, app, document)
        document.typeText("SIX\n")
        XCTAssertTrue(app.staticTexts["documentRow_7"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["lineCounter"].label, "7 / 6 lines — exceeds the 6-line board limit")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "rowOverflowWarning").firstMatch.exists)
        document.typeText("SEVEN")
        app.buttons["editorHideKeyboard"].tap()
        XCTAssertTrue(app.buttons["savePageOnServer"].isEnabled, "Save stays enabled past the board limit")
        attach(app, "D1-B16-overflow")
    }

    /// B15: Align/Wrap act on the caret row and reflect it; the stage row follows.
    func testAlignAndWrapFollowCaretRow() {
        let app = XCUIApplication()
        let document = openNewPage(app, name: "Align test")
        placeCaret(row: 1, app, document); document.typeText("ONE")
        placeCaret(row: 2, app, document); document.typeText("TWO")
        placeCaret(row: 3, app, document); document.typeText("THREE")
        placeCaret(row: 2, app, document)
        let center = app.buttons["toolbar_alignCenter"]
        center.tap()
        XCTAssertTrue(center.isSelected, "Toolbar reflects the caret row")
        XCTAssertTrue(waitForStage(app) { $0.count > 2 && $0[1].hasPrefix(" ") && $0[1].trimmingCharacters(in: .whitespaces) == "TWO" }, "\(stageLines(app))")
        let lines = stageLines(app)
        XCTAssertEqual(lines[0], "ONE", "Row 1 unchanged"); XCTAssertEqual(lines[2], "THREE", "Row 3 unchanged")
        XCTAssertEqual(lines[1], String(repeating: " ", count: 9) + "TWO")
        attach(app, "D1-B15-align")
        placeCaret(row: 1, app, document)
        XCTAssertFalse(center.isSelected, "Row 1 is still left-aligned")
        XCTAssertTrue(app.buttons["toolbar_alignLeft"].isSelected)
        let wrap = app.buttons["toolbar_wrap"]
        XCTAssertFalse(wrap.isSelected); wrap.tap(); XCTAssertTrue(wrap.isSelected)
        placeCaret(row: 2, app, document)
        XCTAssertFalse(wrap.isSelected, "Wrap follows the caret row too")
        XCTAssertTrue(center.isSelected)
        // One Undo removes the last toolbar action only.
        app.buttons["toolbar_undo"].tap()
        placeCaret(row: 1, app, document)
        XCTAssertFalse(wrap.isSelected)
        placeCaret(row: 2, app, document)
        XCTAssertTrue(center.isSelected)
    }

    /// B19: typed letters reach the stage within 750 ms of the last keystroke (UI-test clock;
    /// mock fixture RTT ≈ 0, so this measures the 250 ms debounce plus the pipeline).
    func testTypingReachesTheBoard() {
        let app = XCUIApplication()
        let document = openNewPage(app, name: "Typing test")
        placeCaret(row: 1, app, document)
        XCTAssertTrue(waitForStage(app) { $0.first == "" })
        document.typeText("hello")
        let lastKeystroke = Date()
        XCTAssertEqual((document.value as? String)?.components(separatedBy: "\n").first, "HELLO", "Typed letters are uppercased on flap pages")
        let reached = waitForStage(app, timeout: 2) { $0.first == "HELLO" }
        let elapsed = Date().timeIntervalSince(lastKeystroke)
        let note = XCTAttachment(string: String(format: "Stage reached HELLO %.0f ms after the last keystroke", elapsed * 1000))
        note.name = "B19 latency"; note.lifetime = .keepAlways; add(note)
        XCTAssertTrue(reached, "\(stageLines(app))")
        XCTAssertLessThanOrEqual(elapsed, 0.75, "Stage must update within 750 ms of the last keystroke")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "saveStatus").firstMatch.value as? String, "Unsaved changes")
        attach(app, "D1-B19-typing")
        // B25: one Save, one status word; an acknowledged save says "Page updated" and closes.
        app.buttons["editorHideKeyboard"].tap()
        attach(app, "D1-B25-save-chip")
        app.buttons["savePageOnServer"].tap()
        let toast = app.staticTexts["editorToast"]
        let closed = app.textViews["boardDocument"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5) || closed.waitForNonExistence(timeout: 5))
        if toast.exists { attach(app, "D1-B25-saved-toast") }
        XCTAssertTrue(closed.waitForNonExistence(timeout: 5), "Back to Pages after saving")
        XCTAssertTrue(app.staticTexts["Typing test"].firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: Against the fixture server (`FIXTURE_PORT=18443 python3 Tests/UITests/fixture_server.py`)

    private var fixturePort: Int { Int(ProcessInfo.processInfo.environment["FIXTURE_PORT"] ?? "") ?? 18443 }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeUp() }
        for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeDown() }
    }
    /// Connect and sign in to the mock fixture's `/board-<scenario>-<id>/` prefix (iOS-R1 hook).
    private func connectToFixture(_ app: XCUIApplication, scenario: String) throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(fixturePort)/ready")!); request.timeoutInterval = 3
        let semaphore = DispatchSemaphore(value: 0); var ready = false
        URLSession.shared.dataTask(with: request) { _, response, _ in ready = (response as? HTTPURLResponse)?.statusCode == 200; semaphore.signal() }.resume()
        semaphore.wait()
        try XCTSkipUnless(ready, "Start the fixture: FIXTURE_PORT=\(fixturePort) python3 Tests/UITests/fixture_server.py")
        app.launchArguments = []; app.launch()
        let alias = "board-" + scenario + "-" + UUID().uuidString.prefix(8).lowercased()
        let address = app.textFields["connectionAddress"]
        XCTAssertTrue(app.buttons["exploreDemo"].waitForExistence(timeout: 8))
        reveal(address, app); address.tap(); address.typeText("http://127.0.0.1:\(fixturePort)/" + alias)
        let name = app.textFields["Server name (optional)"]
        reveal(name, app); name.tap(); name.typeText(alias + "\n")
        let localHTTP = app.switches["connectionLocalHTTP"]
        reveal(localHTTP, app); localHTTP.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let connect = app.buttons["connectionConnect"]
        reveal(connect, app); connect.tap()
        let username = app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout: 8), app.staticTexts["connectionMessage"].firstMatch.debugDescription)
        reveal(username, app); username.tap(); username.typeText("fixture_admin")
        let password = app.secureTextFields["connectionPassword"]
        reveal(password, app); password.tap(); password.typeText("fixture-password")
        let signIn = app.buttons["connectionSignIn"]
        reveal(signIn, app); signIn.tap()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10), app.staticTexts["connectionMessage"].firstMatch.debugDescription)
    }

    /// B19 through the fixture's `POST /templates/render` (table + toy fallback): typing in the
    /// Lobby page reaches the board via a real request/response, within 750 ms of the last key.
    func testTypingReachesTheBoardThroughFixtureRender() throws {
        let app = XCUIApplication()
        try connectToFixture(app, scenario: "manual")
        openPages(app)
        let row = app.staticTexts["Lobby"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        app.buttons["editLocalDraft"].tap()
        let document = app.textViews["boardDocument"]
        XCTAssertTrue(document.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(app.buttons["evaluationBoardPicker"].value as? String, "Kitchen")
        XCTAssertTrue(waitForStage(app, timeout: 5) { $0.first == "WELCOME TO THE LOBBY" }, "First server frame: \(stageLines(app))")
        XCTAssertEqual(app.staticTexts["boardSizeReadout"].label, "Board size 12 by 29")
        placeCaret(row: 3, app, document)
        document.typeText("HELLO")
        let lastKeystroke = Date()
        let reached = waitForStage(app, timeout: 2) { $0.count > 2 && $0[2] == "HELLO" }
        let elapsed = Date().timeIntervalSince(lastKeystroke)
        let note = XCTAttachment(string: String(format: "Fixture render: stage reached HELLO %.0f ms after the last keystroke", elapsed * 1000))
        note.name = "B19 latency (fixture render)"; note.lifetime = .keepAlways; add(note)
        XCTAssertTrue(reached, "\(stageLines(app))")
        XCTAssertLessThanOrEqual(elapsed, 0.75)
        XCTAssertFalse(app.staticTexts["Demo · local preview, expressions are not evaluated"].exists, "This frame is the fixture server's render")
        attach(app, "D1-B19-fixture-render")
        app.buttons["editorHideKeyboard"].tap()
        app.navigationBars.buttons["Close"].tap(); app.buttons["Discard and leave"].tap()
    }
}
