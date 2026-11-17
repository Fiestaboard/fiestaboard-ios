import XCTest

/// iOS-F1 (PLAN B21, B22, B23, B32): the formula editor, the Variables / Colors / Formatting
/// pickers and Draw on board, against the mock fixture's `/board-<scenario>-<n>/` prefix
/// (`fixture_catalog.py`, `fixture_render.py`): no real server, no hardware. Screenshots are
/// attached and, with `SHOT_DIR` (`TEST_RUNNER_SHOT_DIR`), written as `F1-*-<device>-mockfixture.png`.
@MainActor final class FormulaUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipadair11m4" : "iphone17promax" }
    private var fixturePort: Int { Int(ProcessInfo.processInfo.environment["FIXTURE_PORT"] ?? "") ?? 18442 }

    // MARK: Helpers

    private func shot(_ app: XCUIApplication, _ name: String, settle: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: settle)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "F1-\(name)-\(device)-mockfixture"; attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("F1-\(name)-\(device)-mockfixture.png"))
        }
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        // Saved servers from earlier runs pile up above the address field: allow plenty of swipes.
        for _ in 0..<20 { if element.exists && element.isHittable { break }; app.swipeUp() }
        for _ in 0..<20 { if element.exists && element.isHittable { break }; app.swipeDown() }
    }
    private func waitFor(_ timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat { if condition() { return true }; Thread.sleep(forTimeInterval: 0.15) } while Date() < deadline
        return condition()
    }
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func source(_ document: XCUIElement) -> String { (document.value as? String) ?? "" }
    private func stageLines(_ app: XCUIApplication) -> [String] {
        ((element(app, "boardStage").value as? String) ?? "").components(separatedBy: "\n").map { line in
            var line = line; while line.last == " " { line.removeLast() }; return line
        }
    }

    /// Sign in to the fixture's board prefix and open "Good Morning" in the document editor.
    private func openGoodMorning(scenario: String = "manual") throws -> (XCUIApplication, XCUIElement) {
        try requireReadyFixture(port: String(fixturePort))
        let app = isolatedApplication()
        app.launchArguments = []; app.launch()
        let alias = "board-" + scenario + "-" + UUID().uuidString.prefix(8).lowercased()
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
        let pages = app.buttons.matching(identifier: "destination-Pages").firstMatch
        for _ in 0..<5 where !(pages.exists && pages.isHittable) {
            let sidebar = app.buttons["Show Sidebar"].firstMatch
            if sidebar.exists && sidebar.isHittable { sidebar.tap(); continue }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists && back.isHittable { back.tap() }
        }
        XCTAssertTrue(pages.waitForExistence(timeout: 5)); pages.tap()
        let row = pageCard(app, named: "Good Morning")
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        let edit = app.buttons["editLocalDraft"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let document = app.textViews["boardDocument"]
        XCTAssertTrue(document.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(waitFor(6) { self.stageLines(app).first?.contains("GOOD MORNING") == true }, "\(stageLines(app))")
        return (app, document)
    }
    /// Caret at the end of row `n` (1-based).
    private func placeCaret(row n: Int, _ app: XCUIApplication, _ document: XCUIElement) {
        let gutter = app.staticTexts["documentRow_\(n)"]
        XCTAssertTrue(gutter.waitForExistence(timeout: 3))
        document.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: document.frame.width - 12, dy: gutter.frame.midY - document.frame.minY)).tap()
    }
    /// The toolbar button under the title, or its keyboard-accessory mirror when the keyboard is up.
    private func tool(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let toolbar = app.buttons["toolbar_" + name]
        return toolbar.exists && toolbar.isHittable ? toolbar : app.buttons["accessory_" + name]
    }
    private func hideKeyboard(_ app: XCUIApplication) {
        let hide = app.buttons["editorHideKeyboard"]
        if hide.exists && hide.isHittable { hide.tap() }
        _ = waitFor(3) { !app.keyboards.firstMatch.exists || !hide.isHittable }
    }
    private func statusValue(_ app: XCUIApplication) -> String { (element(app, "formulaStatus").value as? String) ?? "" }

    // MARK: B21 formula editor

    /// B21: Insert formula opens the editor: Functions | Variables, categories in the web order
    /// (unknown appended), a function scaffolds `IF(` / `)`, a variable inserts its bare path,
    /// 300 ms later a green check; `BOGUS(1)` turns it red with the server's message without
    /// "Formula "; Insert is off while red. The confirmed formula is a compact ƒ chip whose
    /// callout shows the whole formula.
    func testFormulaEditorValidates() throws {
        let (app, document) = try openGoodMorning()
        placeCaret(row: 3, app, document)
        tool(app, "formula").tap()
        let expression = app.textViews["formulaExpression"]
        XCTAssertTrue(expression.waitForExistence(timeout: 5))
        let confirm = app.buttons["formulaConfirm"]
        XCTAssertFalse(confirm.isEnabled, "Nothing to insert yet")
        // Categories: logic, array, date, math, text, conversion, color, then the unknown one.
        // Collapsing the seven known ones brings the appended category into view.
        let order = ["logic", "array", "date", "math", "text", "convert", "color", "experimental"]
        XCTAssertTrue(element(app, "formulaCategory_logic").waitForExistence(timeout: 5))
        for category in order.dropLast() {
            let header = element(app, "formulaCategory_\(category)")
            XCTAssertTrue(header.waitForExistence(timeout: 3), category); header.tap()
        }
        let headers = order.map { element(app, "formulaCategory_\($0)") }
        XCTAssertTrue(headers.last!.waitForExistence(timeout: 3), "An unknown category is appended, not dropped")
        XCTAssertEqual(headers.map(\.frame.minY), headers.map(\.frame.minY).sorted(), "Web category order")
        shot(app, "B21-function-categories")
        headers[0].tap()
        XCTAssertTrue(element(app, "formulaFunction_IF").waitForExistence(timeout: 3))
        // IF(1>0,"A","B") → valid. The code box has focus when the editor opens.
        expression.typeText(#"IF(1>0,"A","B")"#)
        XCTAssertTrue(waitFor(4) { self.statusValue(app) == "valid" }, statusValue(app))
        XCTAssertTrue(confirm.isEnabled)
        shot(app, "B21-valid")
        // BOGUS(1) → invalid, the stripped server message, Insert off.
        expression.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        expression.typeText("BOGUS(1)")
        XCTAssertTrue(waitFor(4) { self.statusValue(app) == "invalid" }, statusValue(app))
        let errors = element(app, "formulaErrors")
        XCTAssertTrue(errors.waitForExistence(timeout: 3))
        XCTAssertTrue(errors.label.contains("#NAME?: Unknown function: BOGUS"), errors.label)
        XCTAssertFalse(errors.label.contains("Formula #NAME"), "The leading \"Formula \" is stripped")
        XCTAssertFalse(confirm.isEnabled, "Insert stays off while the formula is red")
        shot(app, "B21-bogus-invalid")
        // A function scaffolds IF( / ) with the caret inside; a variable inserts its bare path.
        expression.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        element(app, "formulaFunction_IF").tap()
        XCTAssertTrue(waitFor(3) { (expression.value as? String) == "IF(\n  \n)" }, "\(expression.value ?? "")")
        element(app, "formulaTabs").buttons["Variables"].tap()
        let search = app.textFields["variableSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap(); search.typeText("temp")
        let temperature = app.buttons["insertVariable_weather.temperature"]
        XCTAssertTrue(temperature.waitForExistence(timeout: 3)); temperature.tap()
        XCTAssertTrue(waitFor(3) { (expression.value as? String) == "IF(\n  weather.temperature\n)" }, "Bare token, no braces: \(expression.value ?? "")")
        expression.typeText(#" > 70, "WARM", "COOL""#)
        XCTAssertTrue(waitFor(4) { self.statusValue(app) == "valid" }, statusValue(app))
        shot(app, "B21-colouring-and-catalog")
        confirm.tap()
        XCTAssertTrue(waitFor(4) { self.source(document).components(separatedBy: "\n")[2] == #"{{= IF(weather.temperature > 70, "WARM", "COOL") }}"# },
                      "One line again (the pretty-printed lines collapse): \(source(document))")
        hideKeyboard(app)
        // The pill is compact (ƒ IF); a tap shows the whole formula.
        let gutter = app.staticTexts["documentRow_3"]
        let charWidth = ("M" as NSString).size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)]).width
        document.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 9 + 1.5 * charWidth, dy: gutter.frame.midY - document.frame.minY)).tap()
        let callout = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "ƒ IF(weather.temperature")).firstMatch
        XCTAssertTrue(callout.waitForExistence(timeout: 4), "The callout shows the whole formula")
        shot(app, "formula-chip-compact-callout")
        app.navigationBars.buttons["Close"].tap(); app.buttons["Discard and leave"].tap()
    }

    // MARK: B22 pickers

    /// B22: plugins as sections with an icon and a readable name (manifest name, else Title Case),
    /// group headers, pills with a faded preview, array items with their index; search `temp`
    /// narrows to the temperature; a pill closes the picker and the chip is at the caret.
    func testVariablesPickerSearchAndInsert() throws {
        let (app, document) = try openGoodMorning()
        placeCaret(row: 3, app, document)
        document.typeText("NOW ")
        tool(app, "variables").tap()
        let search = app.textFields["variableSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        // The search field has focus when the picker opens (a second tap would show AutoFill).
        for (id, name) in [("weather", "Weather"), ("date_time", "Date & Time"), ("baywheels", "Bay Wheels"), ("stocks", "Stocks")] {
            let header = element(app, "variablePlugin_\(id)")
            XCTAssertTrue(header.waitForExistence(timeout: 3), id)
            XCTAssertTrue(header.label.contains(name), "\(id): \(header.label)")
        }
        XCTAssertFalse(element(app, "variablePlugin_home_assistant").exists, "Only the server's plugins")
        XCTAssertTrue(app.staticTexts["RIGHT NOW"].exists, "Group header")
        XCTAssertTrue(app.buttons["insertVariable_weather.temperature"].label.contains("72"), "Pill carries its value preview")
        shot(app, "B22-variables")
        search.typeText("temp")
        XCTAssertTrue(waitFor(3) { !self.element(app, "variablePlugin_baywheels").exists })
        XCTAssertTrue(app.buttons["insertVariable_weather.temperature"].exists)
        XCTAssertFalse(app.buttons["insertVariable_weather.condition"].exists)
        shot(app, "B22-search-temp")
        // Words split on ._- : "bikes" finds every station's bikes, expanded.
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "bikes")
        XCTAssertTrue(app.buttons["insertVariable_baywheels.stations.1.bikes"].waitForExistence(timeout: 3))
        shot(app, "B22-search-array-items")
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "feels like")
        let feels = app.buttons["insertVariable_weather.feels_like"]
        XCTAssertTrue(feels.waitForExistence(timeout: 3), "Words split on _ match a spaced query")
        feels.tap()
        XCTAssertFalse(search.waitForExistence(timeout: 1), "The picker closes")
        XCTAssertTrue(waitFor(4) { self.source(document).components(separatedBy: "\n")[2] == "NOW {{weather.feels_like}}" }, source(document))
        shot(app, "B22-inserted-chip")
        app.navigationBars.buttons["Close"].tap(); app.buttons["Discard and leave"].tap()
    }

    /// Colors (real tiles, code 62) and Formatting (fill space; repeat asks for a pattern) pickers.
    func testColorsAndFormattingPickers() throws {
        let (app, document) = try openGoodMorning()
        placeCaret(row: 3, app, document)
        tool(app, "colors").tap()
        let blue = app.buttons["insertColor_blue"]
        XCTAssertTrue(blue.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["insertDegree"].exists)
        shot(app, "colors-picker")
        blue.tap()
        XCTAssertTrue(waitFor(4) { self.source(document).components(separatedBy: "\n")[2] == "{{blue}}" }, source(document))
        tool(app, "formatting").tap()
        let repeatFill = app.buttons["insertFormatting_{{fill_space_repeat:pattern}}"]
        XCTAssertTrue(repeatFill.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["insertFormatting_{{fill_space}}"].exists)
        shot(app, "formatting-picker")
        repeatFill.tap()
        let dashes = app.buttons["insertFormatting_{{fill_space_repeat:-}}"]
        XCTAssertTrue(dashes.waitForExistence(timeout: 3))
        shot(app, "formatting-repeat-pattern")
        dashes.tap()
        XCTAssertTrue(waitFor(4) { self.source(document).components(separatedBy: "\n")[2] == "{{blue}}{{fill_space_repeat:-}}" }, source(document))
        app.navigationBars.buttons["Close"].tap(); app.buttons["Discard and leave"].tap()
    }

    /// B32 (no plugins): Variables is disabled with "No template variables available. Configure
    /// plugins in Settings."; Colors and Formatting stay because the server lists them.
    func testNoPluginsDisablesVariables() throws {
        let (app, _) = try openGoodMorning(scenario: "no-plugins")
        let variables = app.buttons["toolbar_variables"]
        XCTAssertTrue(variables.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(5) { !variables.isEnabled }, "Variables is disabled")
        let note = element(app, "noVariablesNote")
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertTrue(note.label.contains("No template variables available. Configure plugins in Settings."), note.label)
        XCTAssertTrue(app.buttons["toolbar_colors"].exists && app.buttons["toolbar_formatting"].exists)
        shot(app, "B32-no-plugins")
        app.navigationBars.buttons["Close"].tap()
        if app.buttons["Discard and leave"].waitForExistence(timeout: 1) { app.buttons["Discard and leave"].tap() }
    }

    // MARK: B23 draw mode

    /// Centre of tile (row, col) of a flagship board inside the stage element: the stage keeps the
    /// board's proportions vertically (its stretch scales every row alike), so fractions of the
    /// board's height and width in tile-height units place the tile (bezel 0.40/0.55 + 0.10
    /// border; tile 0.70 wide; gutter 0.145).
    private func tile(_ stage: XCUIElement, row: Int, col: Int, rows: Int = 6, cols: Int = 22) -> XCUICoordinate {
        let width = Double(cols) * 0.845 - 0.145 + 2 * 0.50
        let height = Double(rows) * 1.145 - 0.145 + 2 * 0.65
        let x = (0.50 + Double(col) * 0.845 + 0.35) / width
        let y = (0.65 + Double(row) * 1.145 + 0.50) / height
        return stage.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    /// B23: Draw on board → the rows collapse, 8 swatches + eraser + stamps and the hint; a drag
    /// across the stage paints red tiles at once; release is one undo step; the row becomes
    /// positional (dynamic tokens dropped) and left/no-wrap; Undo restores the text and the row's
    /// centre alignment; Done exits.
    func testDrawModePaintsOneUndoStep() throws {
        let (app, document) = try openGoodMorning()
        XCTAssertTrue(waitFor(6) { self.stageLines(app).first == "     GOOD MORNING" }, "\(stageLines(app))")
        let draw = app.buttons["toolbar_draw"]
        XCTAssertTrue(draw.waitForExistence(timeout: 3)); draw.tap()
        XCTAssertTrue(element(app, "drawHint").waitForExistence(timeout: 3))
        XCTAssertTrue(element(app, "drawHint").label.contains("Drawing mode is on — drag on the preview to paint tiles"))
        XCTAssertFalse(document.exists, "The rows collapse while drawing")
        for color in ["red", "orange", "yellow", "green", "blue", "violet", "white", "black"] {
            XCTAssertTrue(app.buttons["drawBrush_\(color)"].exists, color)
        }
        XCTAssertTrue(app.buttons["drawBrush_eraser"].exists && element(app, "drawStamp").exists)
        shot(app, "B23-draw-mode")
        app.buttons["drawBrush_red"].tap()
        let stage = element(app, "boardStage")
        // Row 1 holds the centred GOOD MORNING; paint its first five cells.
        tile(stage, row: 0, col: 0).press(forDuration: 0.1, thenDragTo: tile(stage, row: 0, col: 4))
        XCTAssertTrue(waitFor(3) { self.stageLines(app).first == "     MORNING" }, "Painted tiles read as gaps; the row is now left-aligned: \(stageLines(app))")
        // Row 2 has a variable: painting it drops the token (web semantics).
        tile(stage, row: 1, col: 3).press(forDuration: 0.1, thenDragTo: tile(stage, row: 1, col: 3))
        XCTAssertTrue(waitFor(3) { self.stageLines(app).count > 1 && self.stageLines(app)[1] == "°" },
                      "The variables are dropped; ° stays, the painted tile reads as a gap: \(stageLines(app))")
        shot(app, "B23-painted")
        app.buttons["drawUndo"].tap()
        XCTAssertTrue(waitFor(4) { self.stageLines(app).count > 1 && self.stageLines(app)[1].hasPrefix("72") }, "One undo restores row 2: \(stageLines(app))")
        app.buttons["drawUndo"].tap()
        XCTAssertTrue(waitFor(4) { self.stageLines(app).first == "     GOOD MORNING" }, "One undo restores the text and the centring: \(stageLines(app))")
        shot(app, "B23-undone")
        app.buttons["drawRedo"].tap()
        XCTAssertTrue(waitFor(4) { self.stageLines(app).first == "     MORNING" }, "\(stageLines(app))")
        app.buttons["drawDone"].tap()
        XCTAssertTrue(document.waitForExistence(timeout: 4), "Done exits draw mode")
        XCTAssertEqual(source(document).components(separatedBy: "\n").first, "{{red}}{{red}}{{red}}{{red}}{{red}}MORNING")
        placeCaret(row: 1, app, document)
        XCTAssertTrue(waitFor(3) { self.tool(app, "alignLeft").isSelected }, "The painted row is left-aligned")
        hideKeyboard(app)
        shot(app, "B23-after-done")
        app.navigationBars.buttons["Close"].tap(); app.buttons["Discard and leave"].tap()
    }
}
