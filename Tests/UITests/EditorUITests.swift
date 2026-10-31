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
            .components(separatedBy: "\n")
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
        let aboveStage = app.staticTexts.allElementsBoundByIndex.filter { $0.exists && $0.frame.maxY <= stage.frame.minY && $0.frame.minY > app.navigationBars.firstMatch.frame.maxY }
        let allowed: Set<String> = ["boardSizeReadout", "boardFitNote", "previewUpdating"]
        XCTAssertTrue(aboveStage.allSatisfy { allowed.contains($0.identifier) }, "Only the stage header sits between the title and the board: \(aboveStage.map(\.identifier))")
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
        // B25: one Save, one status word, toast, back to the page.
        app.buttons["editorHideKeyboard"].tap()
        app.buttons["savePageOnServer"].tap()
        XCTAssertTrue(app.staticTexts["Page updated (simulated)"].waitForExistence(timeout: 5))
        attach(app, "D1-B25-save-chip")
        XCTAssertTrue(app.buttons["editLocalDraft"].waitForExistence(timeout: 5), "Back to the page after saving")
    }
}
