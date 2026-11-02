import XCTest

/// Document editor (PLAN B12, B15, B16, B19, B25, B33). Runs against the in-app demo service,
/// a mock fixture: no real server, no hardware. Screenshots are attached with `-mockfixture` names.
@MainActor final class EditorUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    private func attach(_ app: XCUIApplication, _ name: String) {
        // Evidence shows the settled frame: assertions run as soon as the stage's value changes,
        // while the tiles may still be flipping. The drum only walks forward (80 ms per step), so
        // a letter turning blank wraps through the colour tiles and can take several seconds.
        Thread.sleep(forTimeInterval: 6)
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
    /// A toolbar action: the button under the title, or (phone, keyboard up, where the title and
    /// toolbar step aside for the board — W2 B30) its keyboard-accessory mirror.
    private func tool(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let toolbar = app.buttons["toolbar_" + name]
        return toolbar.exists && toolbar.isHittable ? toolbar : app.buttons["accessory_" + name]
    }
    private func stageLines(_ app: XCUIApplication) -> [String] {
        ((app.descendants(matching: .any).matching(identifier: "boardStage").firstMatch.value as? String) ?? "")
            .components(separatedBy: "\n").map { line in
                var line = line; while line.last == " " { line.removeLast() }; return line
            }
    }
    private func waitForCondition(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat { if condition() { return true }; Thread.sleep(forTimeInterval: 0.2) } while Date() < deadline
        return false
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
        XCTAssertGreaterThan(stage.frame.width * stage.frame.height, document.frame.width * document.frame.height,
                             "The board is larger than the document surface: \(stage.frame) vs \(document.frame)")
        // The toolbar sits directly under the title (B12/B15), above the board.
        let alignLeft = app.buttons["toolbar_alignLeft"]
        XCTAssertTrue(alignLeft.isHittable)
        XCTAssertGreaterThan(alignLeft.frame.minY, title.frame.maxY - 1); XCTAssertLessThan(alignLeft.frame.maxY, stage.frame.minY)
        // Text between the title and the board may only belong to the stage header row
        // (size readout, display picker label, fit note, updating) — no captions or disclaimers.
        let header = app.staticTexts["boardSizeReadout"].frame
        // Scoped to visible text in the board's own column: labels behind the iPad sheet
        // (sidebar, Pages rows) are reported by XCUITest but are not hittable.
        let aboveStage = app.staticTexts.allElementsBoundByIndex.filter {
            $0.exists && $0.frame.maxY <= stage.frame.minY && $0.frame.minY > title.frame.maxY
                && $0.frame.maxX > stage.frame.minX && $0.frame.minX < stage.frame.maxX && $0.isHittable
        }
        let strays = aboveStage.filter { $0.frame.midY < header.minY - 4 || $0.frame.midY > header.maxY + 4 }
        XCTAssertTrue(strays.isEmpty, "Only the stage header sits between the title and the board: \(strays.map(\.label))")
        attach(app, "D1-B12-new-page")
        attach(app, "D1-B33-editor")
        attach(app, "D1-B20-stage-header")
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Wide layout (iPad landscape): the board sits beside the document, still the largest element.
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(waitForCondition(timeout: 5) { stage.frame.minX > document.frame.maxX }, "Stage beside the document: \(stage.frame) vs \(document.frame)")
            XCTAssertGreaterThan(stage.frame.width * stage.frame.height, document.frame.width * document.frame.height)
            XCTAssertLessThan(app.buttons["toolbar_alignLeft"].frame.maxY, stage.frame.minY, "Toolbar under the title, above the board")
            attach(app, "D1-B33-editor-landscape")
            XCUIDevice.shared.orientation = .portrait
            XCTAssertTrue(waitForCondition(timeout: 5) { stage.frame.maxY < document.frame.minY }, "Stage above the document in portrait")
        }

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
        // Re-recorded (W2): on a phone the toolbar steps aside while typing, so actions go through
        // `tool(...)` (toolbar or its accessory mirror); the assertions are unchanged.
        let center = tool(app, "alignCenter")
        center.tap()
        XCTAssertTrue(center.isSelected, "Toolbar reflects the caret row")
        // The keyboard accessory mirrors the toolbar while the keyboard is up.
        let accessoryCenter = app.buttons["accessory_alignCenter"]
        XCTAssertTrue(accessoryCenter.waitForExistence(timeout: 3), "Keyboard accessory mirrors the toolbar")
        XCTAssertTrue(accessoryCenter.isSelected); XCTAssertFalse(app.buttons["accessory_alignLeft"].isSelected)
        for id in ["accessory_undo", "accessory_redo", "accessory_alignRight", "accessory_wrap", "editorHideKeyboard"] {
            XCTAssertTrue(app.buttons[id].exists, id)
        }
        // W2 integration: Wrap must be reachable without scrolling on a phone (it fell off the
        // 440 pt row at 40 pt buttons).
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertTrue(app.buttons["accessory_wrap"].isHittable, "accessory_wrap is on screen")
            XCTAssertTrue(app.buttons["editorHideKeyboard"].isHittable, "Hide stays pinned")
        }
        XCTAssertTrue(waitForStage(app) { $0.count > 2 && $0[1].hasPrefix(" ") && $0[1].trimmingCharacters(in: .whitespaces) == "TWO" }, "\(stageLines(app))")
        let lines = stageLines(app)
        XCTAssertEqual(lines[0], "ONE", "Row 1 unchanged"); XCTAssertEqual(lines[2], "THREE", "Row 3 unchanged")
        XCTAssertEqual(lines[1], String(repeating: " ", count: 9) + "TWO")
        attach(app, "D1-B15-align")
        placeCaret(row: 1, app, document)
        XCTAssertFalse(tool(app, "alignCenter").isSelected, "Row 1 is still left-aligned")
        XCTAssertTrue(tool(app, "alignLeft").isSelected)
        let wrap = tool(app, "wrap")
        XCTAssertFalse(wrap.isSelected); wrap.tap(); XCTAssertTrue(wrap.isSelected)
        placeCaret(row: 2, app, document)
        XCTAssertFalse(wrap.isSelected, "Wrap follows the caret row too")
        XCTAssertTrue(center.isSelected)
        // One Undo removes the last toolbar action only.
        tool(app, "undo").tap()
        placeCaret(row: 1, app, document)
        XCTAssertFalse(wrap.isSelected)
        placeCaret(row: 2, app, document)
        XCTAssertTrue(tool(app, "alignCenter").isSelected)
    }

    /// B19: typed letters reach the stage within 750 ms of the last keystroke (UI-test clock;
    /// mock fixture RTT ≈ 0, so this measures the 250 ms debounce plus the pipeline).
    func testTypingReachesTheBoard() {
        let app = XCUIApplication()
        let document = openNewPage(app, name: "Typing test")
        // iPad runs this in landscape: the wide layout (board beside the document). Portrait iPad
        // stacks like the phone, which the phone run covers.
        let wide = UIDevice.current.userInterfaceIdiom == .pad
        if wide {
            XCUIDevice.shared.orientation = .landscapeLeft
            let stage = app.descendants(matching: .any).matching(identifier: "boardStage").firstMatch
            XCTAssertTrue(waitForCondition(timeout: 5) { stage.frame.minX > document.frame.maxX }, "Wide layout: board beside the document")
        }
        defer { if wide { XCUIDevice.shared.orientation = .portrait } }
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

    // MARK: Against the fixture server (`FIXTURE_PORT=18442 python3 Tests/UITests/fixture_server.py`)

    private var fixturePort: Int { Int(ProcessInfo.processInfo.environment["FIXTURE_PORT"] ?? "") ?? 18442 }
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

    /// P1 compact chips (fixture "Good Morning"): a variable chip is a short label (the field, with
    /// its source as a small mark) no wider than a few board cells; a tap shows its full name and
    /// filters in a callout, whose Edit opens the exact source. The chip stays one character.
    func testCompactChipCalloutShowsTheFullName() throws {
        let app = XCUIApplication()
        try connectToFixture(app, scenario: "manual")
        openPages(app)
        let row = app.staticTexts["Good Morning"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        app.buttons["editLocalDraft"].tap()
        let document = app.textViews["boardDocument"]
        XCTAssertTrue(document.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(waitForStage(app, timeout: 5) { $0.first?.contains("GOOD MORNING") == true }, "\(stageLines(app))")
        attach(app, "P1-1-chips-\(device())")
        // Row 2 starts with the pad:3 chip: tap its middle.
        let charWidth = ("M" as NSString).size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)]).width
        let gutter = app.staticTexts["documentRow_2"]
        XCTAssertTrue(gutter.waitForExistence(timeout: 3))
        let chip = document.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 9 + 2 * charWidth, dy: gutter.frame.midY - document.frame.minY))
        chip.tap()
        let callout = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "weather.temperature | pad:3")).firstMatch
        XCTAssertTrue(callout.waitForExistence(timeout: 4), "The callout names the variable and its filter")
        attach(app, "P1-1-chip-callout-\(device())")
        // The caret sits after the chip: the detail line under the document names it in full.
        let detail = app.staticTexts["chip-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        XCTAssertEqual(detail.label, "weather.temperature | pad:3")
        callout.tap()
        let tokenSource = app.textFields["tokenSource"]
        XCTAssertTrue(tokenSource.waitForExistence(timeout: 4), "Edit opens the chip's source")
        XCTAssertEqual(tokenSource.value as? String, "{{weather.temperature|pad:3}}")
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(source(document).components(separatedBy: "\n")[1].hasPrefix("{{weather.temperature|pad:3}}"), source(document))
        // Keyboard up: the chips and the stage together.
        placeCaret(row: 3, app, document)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        attach(app, "P1-1-chips-keyboard-up-\(device())")
        // P1 item 2: the free space between the document and the keyboard goes to the board (W2
        // left ~85 pt empty there on this phone). The board stays above the keyboard.
        let stage = app.descendants(matching: .any).matching(identifier: "boardStage").firstMatch
        let hide = app.buttons["editorHideKeyboard"]
        let mode = app.descendants(matching: .any).matching(identifier: "editingMode").firstMatch
        XCTAssertLessThan(stage.frame.maxY, hide.frame.minY, "The board is above the keyboard")
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertLessThan(hide.frame.minY - mode.frame.maxY, 50, "Little empty space is left under the document")
            XCTAssertGreaterThan(stage.frame.height, stage.frame.width * 0.45, "The board grew taller than its width-bound aspect (≈0.41)")
        }
        app.buttons["editorHideKeyboard"].tap()
        app.navigationBars.buttons["Close"].tap()
        let discard = app.buttons["Discard and leave"]
        if discard.waitForExistence(timeout: 2) { discard.tap() }
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

    // MARK: Wave 2 (iOS-E2): chips, insert buttons, keyboard-up layout

    private func device() -> String { UIDevice.current.userInterfaceIdiom == .pad ? "ipadair11m4" : "iphone17promax" }
    private func source(_ document: XCUIElement) -> String { (document.value as? String) ?? "" }
    /// Opens a menu button and taps through its items by label (menus keep the keyboard up).
    private func pick(_ app: XCUIApplication, _ button: String, _ path: [String]) {
        let opener = app.buttons[button]
        XCTAssertTrue(opener.waitForExistence(timeout: 3), button); opener.tap()
        for label in path {
            let item = app.collectionViews.buttons[label].firstMatch.exists ? app.collectionViews.buttons[label].firstMatch : app.buttons[label].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 3), "\(label) in \(button)"); item.tap()
        }
    }

    /// B13/B14/B15: Variables, Colors and Insert formula on the keyboard accessory insert chips at
    /// the caret (the keyboard stays up); the board follows; Backspace removes a chip whole; an
    /// unknown variable is flagged with a reason for the board's ???.
    func testInsertChipsFromTheKeyboardAccessory() {
        let app = XCUIApplication()
        let document = openNewPage(app, name: "Chips")
        placeCaret(row: 1, app, document)
        document.typeText("TEMP ")
        pick(app, "accessory_variables", ["Weather", "insertVariable_weather.temperature"])
        XCTAssertTrue(waitForCondition(timeout: 3) { self.source(document).hasPrefix("TEMP {{weather.temperature}}") }, source(document))
        XCTAssertTrue(app.keyboards.firstMatch.exists, "The keyboard stays up after a menu insert")
        document.typeText(" ")
        pick(app, "accessory_colors", ["insertColor_red"])
        XCTAssertTrue(waitForCondition(timeout: 3) { self.source(document).hasPrefix("TEMP {{weather.temperature}} {{red}}") }, source(document))
        // The stage's value carries letters only (a colour flap reads as a gap), so the tile is
        // checked in the evidence; the sample value replaces the variable on the board.
        XCTAssertTrue(waitForStage(app) { $0.first == "TEMP 72" }, "Sample value on the board: \(stageLines(app))")
        attach(app, "W2-B13-chips-keyboard-up-\(device())")
        // Insert formula: a sheet for the expression; the pill lands at the caret.
        placeCaret(row: 2, app, document)
        app.buttons["accessory_formula"].tap()
        let expression = app.textFields["formulaExpression"].exists ? app.textFields["formulaExpression"] : app.textViews["formulaExpression"]
        XCTAssertTrue(expression.waitForExistence(timeout: 3))
        expression.typeText(#"IF(weather.temperature > 70, "WARM", "COOL")"#)
        app.buttons["formulaInsert"].tap()
        XCTAssertTrue(waitForCondition(timeout: 3) { self.source(document).components(separatedBy: "\n").dropFirst().first == #"{{= IF(weather.temperature > 70, "WARM", "COOL") }}"# }, source(document))
        XCTAssertTrue(waitForStage(app) { $0.count > 1 && $0[1] == "WARM" }, "\(stageLines(app))")
        // Backspace right after the pill deletes the whole pill (one character for the caret).
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Focus returns to the document after the sheet")
        document.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(waitForCondition(timeout: 3) { self.source(document).components(separatedBy: "\n").dropFirst().first == "" }, source(document))
        app.buttons["accessory_undo"].tap()
        XCTAssertTrue(waitForCondition(timeout: 3) { self.source(document).contains("{{= IF(") }, "One Undo restores the pill: \(source(document))")
        // An unknown variable gets the warning treatment and says why the board shows ???.
        placeCaret(row: 3, app, document)
        document.typeText("{{bogus.thing}}")
        let issue = app.descendants(matching: .any).matching(identifier: "unknownVariableIssue").firstMatch
        XCTAssertTrue(issue.waitForExistence(timeout: 3))
        XCTAssertTrue(issue.label.contains("???"), issue.label)
        XCTAssertTrue(waitForStage(app) { $0.count > 2 && $0[2] == "???" }, "\(stageLines(app))")
        attach(app, "W2-B13-formula-and-unknown-\(device())")
        // B30: with the keyboard up the board is not covered and keeps (almost) the full width.
        let stage = app.descendants(matching: .any).matching(identifier: "boardStage").firstMatch
        let keyboard = app.keyboards.firstMatch
        XCTAssertLessThan(stage.frame.maxY, keyboard.frame.minY, "The board is above the keyboard")
        XCTAssertGreaterThanOrEqual(stage.frame.width, document.frame.width - 1, "The board keeps the editor's full width while typing")
        app.buttons["editorHideKeyboard"].tap()
        attach(app, "W2-B13-chips-\(device())")
    }

    /// Web port: Return at the end of a row on a padded new page moves to the next row instead of
    /// adding a 7th ("7 / 6" on a beginner's first Return).
    func testReturnMovesToTheNextEmptyRow() {
        let app = XCUIApplication()
        let document = openNewPage(app, name: "Return test")
        placeCaret(row: 1, app, document)
        document.typeText("ONE\nTWO\nTHREE")
        XCTAssertTrue(waitForCondition(timeout: 3) { self.source(document).components(separatedBy: "\n").count == 6 }, source(document))
        XCTAssertEqual(source(document).components(separatedBy: "\n").prefix(3), ["ONE", "TWO", "THREE"])
        XCTAssertEqual(app.staticTexts["lineCounter"].label, "3 / 6 lines")
        XCTAssertFalse(app.staticTexts["documentRow_7"].exists)
    }

    /// B30/B33 (phone): all six rows and the whole board are visible with the keyboard down, and
    /// the stage is the largest element; the title does not truncate.
    func testBoardStaysBigAndAllRowsShow() {
        let app = XCUIApplication()
        let document = openNewPage(app, name: "Six rows")
        placeCaret(row: 1, app, document)
        document.typeText("ONE\nTWO\nTHREE\nFOUR\nFIVE\nSIX")
        app.buttons["editorHideKeyboard"].tap()
        let row6 = app.staticTexts["documentRow_6"]
        XCTAssertTrue(row6.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(row6.frame.maxY, document.frame.maxY + 1, "Row 6 is not cut off: \(row6.frame) vs \(document.frame)")
        let stage = app.descendants(matching: .any).matching(identifier: "boardStage").firstMatch
        XCTAssertGreaterThan(stage.frame.width * stage.frame.height, document.frame.width * document.frame.height)
        XCTAssertFalse(app.staticTexts["Demo · local preview, expressions are not evaluated"].exists)
        // Minimum tile width (~15 pt): 22 tiles plus bezel fit in the stage width.
        XCTAssertGreaterThanOrEqual(stage.frame.width / 22, 15, "Tiles are at least ~15 pt wide")
        attach(app, "W2-B30-keyboard-down-\(device())")
        placeCaret(row: 6, app, document)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertLessThan(stage.frame.maxY, app.keyboards.firstMatch.frame.minY)
        attach(app, "W2-B30-keyboard-up-\(device())")
    }

    /// B12 (Note) / B28: a page whose `line_metadata` is shorter than its rows (fixture "Desk Note",
    /// 3 × 15, two entries for three rows) opens in the document editor, not the read-only form.
    func testShortMetadataNoteOpensInTheDocumentEditor() throws {
        let app = XCUIApplication()
        try connectToFixture(app, scenario: "manual")
        openPages(app)
        let row = app.staticTexts["Desk Note"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        app.buttons["editLocalDraft"].tap()
        let document = app.textViews["boardDocument"]
        XCTAssertTrue(document.waitForExistence(timeout: 8), "Desk Note opens in the document editor")
        XCTAssertEqual(app.staticTexts["boardSizeReadout"].label, "Board size 3 by 15")
        XCTAssertEqual(source(document).components(separatedBy: "\n").first, "HELLO")
        XCTAssertTrue(app.staticTexts["documentRow_3"].exists); XCTAssertFalse(app.staticTexts["documentRow_4"].exists)
        attach(app, "W2-B12-note-\(device())")
        // Edit row 3 (no metadata entry) and align it: Save stays available.
        placeCaret(row: 3, app, document)
        document.typeText("!")
        app.buttons["accessory_alignRight"].tap()
        XCTAssertTrue(waitForStage(app, timeout: 5) { $0.count == 3 }, "\(stageLines(app))")
        app.buttons["editorHideKeyboard"].tap()
        attach(app, "W2-B28-note-edited-\(device())")
        app.navigationBars.buttons["Close"].tap(); app.buttons["Discard and leave"].tap()
    }

    /// E1 open issue 4: when Save is off with unsaved changes, the reason sits beside it.
    func testDisabledSaveSaysWhy() throws {
        let app = XCUIApplication()
        try connectToFixture(app, scenario: "manual")
        openPages(app)
        let row = app.staticTexts["Lobby"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        app.buttons["editLocalDraft"].tap()
        let document = app.textViews["boardDocument"]
        XCTAssertTrue(document.waitForExistence(timeout: 8))
        placeCaret(row: 3, app, document); document.typeText("HI")
        app.buttons["editorHideKeyboard"].tap()
        let save = app.buttons["savePageOnServer"]
        XCTAssertTrue(waitForCondition(timeout: 3) { !save.isEnabled || save.isEnabled })
        if !save.isEnabled {
            let reason = app.descendants(matching: .any).matching(identifier: "saveDisabledReason").firstMatch
            XCTAssertTrue(reason.waitForExistence(timeout: 3), "A disabled Save says why")
            XCTAssertTrue(reason.label.hasPrefix("Can't save:"), reason.label)
            XCTAssertLessThan(reason.frame.minY, document.frame.minY, "The reason is at the top, under Save")
            attach(app, "W2-save-reason-\(device())")
        } else {
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "saveDisabledReason").firstMatch.exists)
        }
        app.navigationBars.buttons["Close"].tap(); app.buttons["Discard and leave"].tap()
    }

    /// B18: Plain shows alignment/wrap as prefixes; prefixes typed in Plain become alignment.
    func testPlainModeShowsPrefixes() {
        let app = XCUIApplication()
        let document = openNewPage(app, name: "Plain test")
        placeCaret(row: 1, app, document); document.typeText("ONE")
        app.buttons["accessory_alignCenter"].tap()
        app.buttons["editorHideKeyboard"].tap()
        app.buttons["Plain"].tap()
        XCTAssertTrue(waitForCondition(timeout: 3) { self.source(document).hasPrefix("{center}ONE") }, source(document))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "plainHelp").firstMatch.exists)
        placeCaret(row: 2, app, document); document.typeText("{right}TWO")
        app.buttons["editorHideKeyboard"].tap()
        attach(app, "W2-B18-plain-\(device())")
        app.buttons["Rich"].tap()
        XCTAssertTrue(waitForCondition(timeout: 3) { self.source(document).components(separatedBy: "\n").prefix(2) == ["ONE", "TWO"] }, source(document))
        placeCaret(row: 2, app, document)
        XCTAssertTrue(waitForCondition(timeout: 2) { self.tool(app, "alignRight").isSelected }, "The prefix became the row's alignment")
        XCTAssertTrue(waitForStage(app) { $0.count > 1 && $0[1].hasSuffix("TWO") && $0[1].hasPrefix(" ") }, "\(stageLines(app))")
        app.buttons["editorHideKeyboard"].tap()
        app.buttons["Plain"].tap(); app.buttons["Rich"].tap() // leave Rich for the next test (the choice persists)
    }

    /// B20/B28: choosing Note in the stage header redraws a 3 × 15 board and 3 rows; saving a page
    /// whose board got smaller asks "Change board size?" first.
    func testGeometryChangeAndShrinkConfirmation() {
        let app = XCUIApplication()
        let document = openNewPage(app, name: "Shape test")
        placeCaret(row: 1, app, document); document.typeText("HI")
        app.buttons["editorHideKeyboard"].tap()
        app.buttons["evaluationBoardPicker"].tap()
        let note = app.buttons["Note · 3 × 15"]
        XCTAssertTrue(note.waitForExistence(timeout: 3)); note.tap()
        XCTAssertTrue(waitForCondition(timeout: 3) { app.staticTexts["boardSizeReadout"].label == "Board size 3 by 15" })
        XCTAssertTrue(waitForCondition(timeout: 3) { !app.staticTexts["documentRow_4"].exists }, "3 rows for a Note")
        XCTAssertTrue(waitForStage(app) { $0.count == 3 && $0[0] == "HI" }, "\(stageLines(app))")
        attach(app, "W2-B20-note-shape-\(device())")
        app.buttons["savePageOnServer"].tap()
        let resize = app.buttons["resizeAndSave"].firstMatch
        XCTAssertTrue(resize.waitForExistence(timeout: 3), "Shrinking asks first")
        attach(app, "W2-B28-resize-confirm-\(device())")
        resize.tap()
        XCTAssertTrue(app.textViews["boardDocument"].waitForNonExistence(timeout: 8), "Saved and back to Pages")
    }
}
