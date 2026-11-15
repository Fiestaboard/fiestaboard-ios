import XCTest

/// P5 polish round, against the mock fixture (`/board-<scenario>-<n>/` and `/flexible-<n>/`
/// prefixes). No real server, no hardware. With `SHOT_DIR`, captures are written as
/// `W4b-<item>-<device>-mockfixture.png` (and the B31 label dump as `.txt`).
@MainActor final class PolishUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipadair11m4" : "iphone17promax" }
    private var fixturePort: Int { Int(FixtureHTTPServer.shared.port) }

    /// B16 (P5): charset issues grouped per row and per reason, at most three lines collapsed,
    /// "Show all" for the rest; the board stays the largest element either way.
    func testCharsetIssuesAreGroupedWithShowAll() throws {
        let app = try signIn(scenario: "manual")
        openEditor(app, page: "Charset Mix")
        let issues = element(app, "charsetIssues")
        XCTAssertTrue(issues.waitForExistence(timeout: 10), app.debugDescription)
        let expected = [
            "Line 1: lowercase letters show as capitals on this board (5).",
            "Line 3: lowercase letters show as capitals on this board (9).",
            "Line 4: “ñ” and “é” can't be shown; the board draws ? (2).",
            "Line 5: lowercase letters show as capitals on this board (7).",
            "Line 6: lowercase letters show as capitals on this board (3).",
        ]
        XCTAssertEqual(issues.label, expected.prefix(3).joined(separator: "\n"))
        let showAll = element(app, "charsetIssuesShowAll")
        XCTAssertTrue(showAll.exists)
        XCTAssertEqual(showAll.label, "Show all (5)")
        let stage = element(app, "boardStage")
        XCTAssertGreaterThan(area(stage), area(issues) * 2, "the board stays the largest element")
        XCTAssertLessThanOrEqual(issues.frame.height, 80, "collapsed: about three lines")
        shot(app, "W4b-B16-charset-grouped", settle: 2)
        showAll.tap()
        XCTAssertTrue(waitFor(5) { issues.label == expected.joined(separator: "\n") }, issues.label)
        XCTAssertEqual(showAll.label, "Show less")
        XCTAssertGreaterThan(area(stage), area(issues), "the board stays the largest element when expanded")
        shot(app, "W4b-B16-charset-show-all", settle: 1.5)
        close(app)
    }

    /// B8 (P5): the override badge keeps its ✕. With changes off it is dimmed and says why;
    /// with changes on it sends `DELETE /settings/temporary-override` and the mode goes back.
    func testOverrideBadgeCancel() throws {
        let app = try signIn(scenario: "override")
        let mode = element(app, "modeBadge")
        XCTAssertTrue(waitFor(10) { mode.exists && mode.label == "Override: 9m remaining" }, app.debugDescription)
        let cancel = element(app, "overrideCancel")
        XCTAssertTrue(waitFor(15) { cancel.exists && (cancel.value as? String ?? "") != "Unavailable" }, app.debugDescription)
        shot(app, "W4b-B8-override-changes-on", settle: 2)
        cancel.tap()
        XCTAssertTrue(waitFor(10) { mode.exists && mode.label == "Schedule Mode" }, "\(mode.label)")
        XCTAssertFalse(cancel.exists)
        shot(app, "W4b-B8-override-cancelled", settle: 3)
    }

    /// B26 (P5): Show when and Priority sit under "Advanced"; when set and closed, a chip says so.
    func testShowWhenAndPriorityAreAdvanced() throws {
        let app = isolatedApplication(); app.launchArguments = []; app.launch()
        connect(app, path: "flexible-" + UUID().uuidString.prefix(8).lowercased())
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 15))
        selectDestination("Pages", in: app)
        let row = pageCard(app, named: "Flexible document")
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        app.buttons["editLocalDraft"].tap()
        let advanced = app.buttons["Advanced"]
        reveal(advanced, app)
        XCTAssertTrue(advanced.exists, app.debugDescription)
        XCTAssertEqual(advanced.value as? String, "Collapsed")
        XCTAssertFalse(element(app, "flexibleField_if").exists, "Show when is behind Advanced")
        XCTAssertFalse(element(app, "flexibleField_priority").exists, "Priority is behind Advanced")
        shot(app, "W4b-B26-advanced-collapsed", settle: 1)
        advanced.tap()
        let condition = element(app, "flexibleField_if")
        XCTAssertTrue(condition.waitForExistence(timeout: 4))
        reveal(condition, app)
        condition.tap(); condition.typeText("{{weather.rain}}")
        let priority = element(app, "flexibleField_priority")
        reveal(priority, app); priority.tap(); priority.typeText("5")
        shot(app, "W4b-B26-advanced-open", settle: 1)
        reveal(advanced, app); advanced.tap()
        let summary = element(app, "flexibleAdvancedSummary")
        XCTAssertTrue(summary.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(summary.label.contains("Shown when {{weather.rain}}"), summary.label)
        XCTAssertTrue(summary.label.contains("Priority 5"), summary.label)
        reveal(summary, app)
        shot(app, "W4b-B26-advanced-summary", settle: 1)
        app.navigationBars.buttons["Close"].firstMatch.tap()
        let discard = app.buttons["Discard and leave"]
        if discard.waitForExistence(timeout: 2) { discard.tap() }
    }

    /// Item 4 (P5): on iPad portrait with the keyboard down, the document fills the height
    /// under the board (no empty band); on iPhone it still hugs its rows under the board.
    func testDocumentFillsTheHeightOnIPad() throws {
        let app = try signIn(scenario: "manual")
        XCUIDevice.shared.orientation = .portrait
        openEditor(app, page: "Good Morning")
        let document = app.textViews["boardDocument"]
        let stage = element(app, "boardStage")
        XCTAssertTrue(stage.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1.5)
        let counter = element(app, "lineCounter")
        let window = app.windows.firstMatch.frame
        if UIDevice.current.userInterfaceIdiom == .pad {
            // The counter row sits at the bottom: nothing but the margin below it.
            XCTAssertGreaterThan(counter.frame.maxY, window.maxY - 60, "counter \(counter.frame) window \(window)")
            let row1 = element(app, "documentRow_1").frame, row2 = element(app, "documentRow_2").frame
            XCTAssertGreaterThan(row2.minY - row1.minY, 34, "rows spread out")
        }
        XCTAssertGreaterThan(area(stage), area(document), "the board stays the largest element")
        shot(app, "W4b-B33-editor-portrait", settle: 2.5)
        document.tap()
        Thread.sleep(forTimeInterval: 1)
        shot(app, "W4b-B30-keyboard-up", settle: 1)
        let hide = app.buttons["editorHideKeyboard"]
        if hide.waitForExistence(timeout: 3) && hide.isHittable { hide.tap() }
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            Thread.sleep(forTimeInterval: 2)
            shot(app, "W4b-B29-landscape", settle: 2.5)
            shot(app, "W4b-B29-landscape-window", settle: 0.5, window: app)
            XCUIDevice.shared.orientation = .portrait
            Thread.sleep(forTimeInterval: 1.5)
        }
        close(app)
    }

    /// B31 (P5): what VoiceOver reads on Home and in the editor, written out as text: each
    /// element's identifier, label, value and traits (the chips' own labels are dumped by the
    /// app-hosted `VoiceOverLabelDumpTests`).
    func testVoiceOverLabelDump() throws {
        let app = try signIn(scenario: "manual")
        var lines = ["# B31 VoiceOver label dump, \(device), against the mock fixture", "", "## Home"]
        let board = element(app, "homeBoard")
        XCTAssertTrue(waitFor(10) { ((board.value as? String) ?? board.label).contains("HELLO") }, "\(board.label)")
        lines += describe(app, ids: ["nowShowingName", "modeBadge", "homeBoard", "homeDisplayPicker", "boardControlsEntry", "homeChangesOff"])
        openEditor(app, page: "Good Morning")
        Thread.sleep(forTimeInterval: 2.5)
        lines += ["", "## Editor (Good Morning)"]
        lines += describe(app, ids: ["pageTitle", "boardStage", "boardDocument"] + (1...6).map { "documentRow_\($0)" }
                          + ["toolbar_draw", "lineCounter", "editingMode"])
        let toolbar = app.buttons.allElementsBoundByIndex.filter { $0.identifier.hasPrefix("toolbar_") }
        lines += ["", "## Toolbar buttons"] + toolbar.map { "- \($0.identifier): label=\"\($0.label)\" enabled=\($0.isEnabled)" }
        let stage = element(app, "boardStage")
        XCTAssertTrue(((stage.value as? String) ?? stage.label).contains("GOOD MORNING"), "the stage reads its lines")
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? lines.joined(separator: "\n").appending("\n").write(toFile: dir + "/W4b-B31-voiceover-labels-\(device)-mockfixture.txt", atomically: true, encoding: .utf8)
        }
        let attachment = XCTAttachment(string: lines.joined(separator: "\n")); attachment.name = "B31 labels"; attachment.lifetime = .keepAlways; add(attachment)
        close(app)
    }

    // MARK: Recordings (B14, B17, B28): paced so `simctl io recordVideo` shows each step

    /// B14: → steps over a chip in one press, Shift+← outlines it, Backspace deletes it whole.
    func testRecordCaretOverChips() throws {
        let app = try signIn(scenario: "manual")
        let document = openEditor(app, page: "Good Morning")
        let original = try XCTUnwrap(document.value as? String)
        var expectedRows = original.components(separatedBy: "\n")
        XCTAssertGreaterThan(expectedRows.count, 1)
        XCTAssertEqual(expectedRows[1], "{{weather.temperature|pad:3}}° {{weather.condition}}")
        expectedRows[1] = "° {{weather.condition}}"
        document.tap(); Thread.sleep(forTimeInterval: 1)
        let row = app.staticTexts["documentRow_2"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        document.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: document.frame.width - 12, dy: row.frame.midY - document.frame.minY)).tap()
        document.typeKey(.leftArrow, modifierFlags: .command) // start of row 2, before the chip
        document.typeKey(.rightArrow, modifierFlags: []); Thread.sleep(forTimeInterval: 1.2) // after the chip
        document.typeKey(.leftArrow, modifierFlags: .shift); Thread.sleep(forTimeInterval: 1.5) // outlined
        document.typeKey(.rightArrow, modifierFlags: []); Thread.sleep(forTimeInterval: 1)
        document.typeText(XCUIKeyboardKey.delete.rawValue); Thread.sleep(forTimeInterval: 1.5)   // whole chip gone
        let value = (document.value as? String) ?? ""
        // The later formula also references weather.temperature and must remain intact.
        XCTAssertEqual(value, expectedRows.joined(separator: "\n"), "only the selected chip is deleted")
        app.buttons["accessory_undo"].tap(); Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(document.value as? String, original, "undo restores the exact document")
        close(app)
    }

    /// B17: typing is coalesced into bursts; one Undo removes the last burst, Redo puts it back,
    /// and the buttons disable at the ends of history.
    func testRecordTypingUndoRedo() throws {
        let app = try signIn(scenario: "manual")
        let document = openEditor(app, page: "Hello World")
        document.tap(); Thread.sleep(forTimeInterval: 1)
        document.typeKey(.upArrow, modifierFlags: .command)
        let undo = app.buttons["accessory_undo"], redo = app.buttons["accessory_redo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 4))
        XCTAssertFalse(undo.isEnabled, "nothing to undo yet")
        document.typeText("FIRST"); Thread.sleep(forTimeInterval: 1.2)
        document.typeText(" SECOND"); Thread.sleep(forTimeInterval: 1.5)
        func row1() -> String { ((document.value as? String) ?? "").components(separatedBy: "\n").first ?? "" }
        XCTAssertEqual(row1(), "FIRST SECOND")
        undo.tap(); Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(row1(), "FIRST", "one Undo removes the last burst")
        undo.tap(); Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(row1(), "")
        XCTAssertFalse(undo.isEnabled, "Undo disables at the start of history")
        redo.tap(); Thread.sleep(forTimeInterval: 1.2)
        redo.tap(); Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(row1(), "FIRST SECOND")
        XCTAssertFalse(redo.isEnabled, "Redo disables at the end of history")
        close(app)
    }

    /// B28: type, kill the app, reopen: the recovery prompt brings the work back; then leaving
    /// with changes asks "Discard unsaved changes?".
    func testRecordKillAndReopen() throws {
        let app = try signIn(scenario: "manual", remember: true)
        let document = openEditor(app, page: "Hello World")
        document.tap(); Thread.sleep(forTimeInterval: 1)
        document.typeKey(.upArrow, modifierFlags: .command)
        document.typeText("KEEP ME"); Thread.sleep(forTimeInterval: 3.5) // the automatic checkpoint (2 s)
        app.terminate(); Thread.sleep(forTimeInterval: 1.5)
        app.launch()
        // A relaunch shows the connection picker. Reuse the persisted deployment,
        // not a fresh fixture prefix, so this still exercises draft recovery.
        let saved = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "board-manual-")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), app.debugDescription)
        reveal(saved, app); saved.tap()
        // Restore, rather than log in again: a fresh login deliberately gets a new
        // connection ID and must not adopt another connection's draft.
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 15), app.debugDescription)
        let reopened = openEditor(app, page: "Hello World")
        let banner = element(app, "recoveryBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 8), app.debugDescription)
        Thread.sleep(forTimeInterval: 2)
        let recover = app.buttons["Recover local draft"]
        XCTAssertTrue(recover.exists); recover.tap(); Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(((reopened.value as? String) ?? "").hasPrefix("KEEP ME"), "\(reopened.value ?? "")")
        app.navigationBars.buttons["Close"].firstMatch.tap()
        let discard = app.buttons["Discard and leave"]
        XCTAssertTrue(discard.waitForExistence(timeout: 3), "leaving with changes asks first")
        Thread.sleep(forTimeInterval: 2)
        discard.tap(); Thread.sleep(forTimeInterval: 1)
    }

    // MARK: Helpers

    private func describe(_ app: XCUIApplication, ids: [String]) -> [String] {
        ids.map { id in
            let e = element(app, id)
            guard e.exists else { return "- \(id): (not on screen)" }
            let value = (e.value as? String).map { "\"\($0.replacingOccurrences(of: "\n", with: "⏎"))\"" } ?? "nil"
            return "- \(id) [\(e.elementType.rawValue)]: label=\"\(e.label)\" value=\(value)"
        }
    }
    private func area(_ e: XCUIElement) -> CGFloat { e.frame.width * e.frame.height }
    private func connect(_ app: XCUIApplication, path: String) {
        let address = app.textFields["connectionAddress"]
        XCTAssertTrue(app.textFields["connectionAddress"].waitForExistence(timeout: 10))
        reveal(address, app); typeConnectionAddress("http://127.0.0.1:\(fixturePort)/" + path, into: address, in: app)
        let name = app.textFields["Server name (optional)"]
        reveal(name, app); name.tap(); name.typeText(path + "\n")
        let localHTTP = app.switches["connectionLocalHTTP"]
        reveal(localHTTP, app)
        for _ in 0..<3 where localHTTP.value as? String != "1" {
            localHTTP.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: localHTTP)], timeout: 2)
        }
        let connect = app.buttons["connectionConnect"]
        reveal(connect, app); connect.tap()
    }
    private func signIn(scenario: String, remember: Bool = false) throws -> XCUIApplication {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(fixturePort)/ready")!); request.timeoutInterval = 3
        let semaphore = DispatchSemaphore(value: 0); var ready = false
        URLSession.shared.dataTask(with: request) { _, response, _ in ready = (response as? HTTPURLResponse)?.statusCode == 200; semaphore.signal() }.resume()
        semaphore.wait()
        try XCTSkipUnless(ready, "Native in-process fixture must be reachable")
        let app = isolatedApplication()
        app.launchArguments = []; app.launch()
        connect(app, path: "board-\(scenario)-" + UUID().uuidString.prefix(8).lowercased())
        authenticate(app, remember: remember)
        return app
    }
    private func authenticate(_ app: XCUIApplication, remember: Bool) {
        let username = app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout: 10), app.debugDescription)
        reveal(username, app); username.tap(); username.typeText("fixture_admin")
        let password = app.secureTextFields["connectionPassword"]
        reveal(password, app); password.tap(); password.typeText("fixture-password")
        if remember {
            let toggle = app.switches["Remember sign-in"]
            reveal(toggle, app)
            if toggle.value as? String != "1" {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
            XCTAssertEqual(toggle.value as? String, "1", "recovery uses an explicitly remembered connection")
        }
        let signIn = app.buttons["connectionSignIn"]
        reveal(signIn, app); signIn.tap()
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 15), app.debugDescription)
    }
    private func selectDestination(_ name: String, in app: XCUIApplication) {
        let destination = app.buttons.matching(identifier: "destination-" + name).firstMatch
        for _ in 0..<5 {
            if destination.exists && destination.isHittable { destination.tap(); return }
            let sidebar = app.buttons["Show Sidebar"].firstMatch
            if sidebar.exists && sidebar.isHittable { sidebar.tap(); continue }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists && back.isHittable { back.tap() }
        }
        XCTAssertTrue(destination.waitForExistence(timeout: 3)); destination.tap()
    }
    @discardableResult private func openEditor(_ app: XCUIApplication, page: String) -> XCUIElement {
        selectDestination("Pages", in: app)
        let row = pageCard(app, named: page)
        XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        row.tap()
        let edit = app.buttons["editLocalDraft"]
        for _ in 0..<4 { if edit.exists && edit.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let document = app.textViews["boardDocument"]
        XCTAssertTrue(document.waitForExistence(timeout: 8), app.debugDescription)
        return document
    }
    private func close(_ app: XCUIApplication) {
        app.navigationBars.buttons["Close"].firstMatch.tap()
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
        for _ in 0..<12 { if element.exists && element.isHittable { break }; app.swipeUp() }
        for _ in 0..<16 { if element.exists && element.isHittable { break }; app.swipeDown() }
    }
    private func shot(_ app: XCUIApplication, _ name: String, settle: TimeInterval = 1.5, window: XCUIApplication? = nil) {
        Thread.sleep(forTimeInterval: settle)
        let screenshot = window?.windows.firstMatch.screenshot() ?? XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(name)-\(device)-mockfixture"; attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(device)-mockfixture.png"))
        }
    }
}
