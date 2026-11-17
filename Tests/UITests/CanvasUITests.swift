import XCTest

/// PLAN B24 (iOS-F2): the pixel-canvas editor on a legacy LED page ("Pixel Clock", a 10 × 16 panel
/// on the Pixoo, one canvas "sun"), against the mock fixture
/// (`FIXTURE_PORT=<port> python3 Tests/UITests/fixture_server.py`). No real server, no hardware.
/// Screenshots are attachments named `F2-…-mockfixture`, also written to SHOT_DIR when set.
@MainActor final class CanvasUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private var port: String { ProcessInfo.processInfo.environment["FIXTURE_PORT"] ?? "18442" }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipadair11m4" : "iphone17promax" }

    /// First visible result: add a rectangle, drag it on the pixel grid, see the stage's layer move;
    /// the dragged values are whole numbers; one Undo puts it back.
    func testDragRectangleUpdatesTheStage() throws {
        let app = isolatedApplication()
        try openPixelClock(app)
        let surface = app.segmentedControls["editingSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 5), "Text | Canvases appears on the Pixoo (an LED pixel display)")
        XCTAssertTrue(waitFor(8) { self.layers(app).hasPrefix("1 layers") }, "the sun canvas is a layer on the stage: \(layers(app))")
        shot(app, "F2-B24-text-led-stage")
        surface.buttons["Canvases"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "canvasesPanel").firstMatch.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["canvasChip_sun"].exists)
        shot(app, "F2-B24-canvases-panel")

        app.segmentedControls["canvasTabs"].buttons["Shapes"].tap()
        let shapes = element(app, "canvasShapesSurface")
        XCTAssertTrue(shapes.waitForExistence(timeout: 4))
        reveal(shapes, app)
        XCTAssertTrue(element(app, "canvasShapeOverlay_1").exists, "the gradient is drawn as a preserved overlay")
        shot(app, "F2-B24-shapes-preserved")
        let before = layers(app)

        // Add a rectangle (it lands selected, in the middle of the 32 × 30 content).
        let addShape = app.buttons["canvasAddShape"]
        reveal(addShape, app); addShape.tap()
        let rectangle = app.buttons["Rectangle"].firstMatch
        XCTAssertTrue(rectangle.waitForExistence(timeout: 3)); rectangle.tap()
        let overlay = element(app, "canvasShapeOverlay_2")
        XCTAssertTrue(overlay.waitForExistence(timeout: 4))
        XCTAssertTrue(waitFor(4) { self.layers(app) != before }, "the new rectangle shows on the stage")
        let x0 = fieldValue(app, "canvasField_x"), y0 = fieldValue(app, "canvasField_y")
        let added = layers(app)

        // Drag it right and down by about a quarter of the content.
        reveal(shapes, app)
        let start = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: shapes.frame.width * 0.25, dy: shapes.frame.height * 0.2))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: 120, thenHoldForDuration: 0.3)
        XCTAssertTrue(waitFor(4) { self.fieldValue(app, "canvasField_x") != x0 }, "x moved")
        let x1 = fieldValue(app, "canvasField_x"), y1 = fieldValue(app, "canvasField_y")
        XCTAssertNotNil(Int(x1), "x is an integer lexeme: \(x1)"); XCTAssertNotNil(Int(y1), "y is an integer lexeme: \(y1)")
        XCTAssertGreaterThan(Int(x1) ?? 0, Int(x0) ?? 0); XCTAssertGreaterThan(Int(y1) ?? 0, Int(y0) ?? 0)
        XCTAssertTrue(waitFor(4) { self.layers(app) != added }, "the stage follows the drag: \(layers(app))")
        XCTAssertEqual(app.staticTexts["Unsaved changes"].exists || app.buttons["Unsaved changes"].exists ||
                       app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Unsaved changes")).firstMatch.exists, true)
        shot(app, "F2-B24-rect-dragged")

        // One Undo puts the rectangle back where it was added.
        reveal(app.buttons["canvasUndo"], app)
        app.buttons["canvasUndo"].tap()
        XCTAssertTrue(waitFor(4) { self.layers(app) == added }, "undo restores the stage: \(layers(app)) vs \(added)")
        close(app)
    }

    /// Area drag-select, bleed/scale/text controls, the Draw tab and the expression lock.
    func testAreaDrawAndExpressionLock() throws {
        let app = isolatedApplication()
        try openPixelClock(app)
        app.segmentedControls["editingSurface"].buttons["Canvases"].tap()
        let picker = element(app, "canvasAreaPicker")
        XCTAssertTrue(picker.waitForExistence(timeout: 4))
        reveal(picker, app)
        XCTAssertEqual(picker.value as? String, "Rows 1 to 5, columns 1 to 8", "picker \(picker.frame), panel \(element(app, "canvasesPanel").frame)")
        // Drag from cell (row 3, col 5) to (row 8, col 14), 1-based.
        let frame = picker.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let from = origin.withOffset(CGVector(dx: frame.minX + frame.width * 4.5 / 16, dy: frame.minY + frame.height * 2.5 / 10))
        let to = origin.withOffset(CGVector(dx: frame.minX + frame.width * 13.5 / 16, dy: frame.minY + frame.height * 7.5 / 10))
        XCTAssertLessThan(frame.minY + frame.height * 7.5 / 10, app.windows.firstMatch.frame.maxY - 20)
        from.press(forDuration: 0.2, thenDragTo: to, withVelocity: 150, thenHoldForDuration: 0.2)
        XCTAssertTrue(waitFor(4) { picker.value as? String == "Rows 3 to 8, columns 5 to 14" }, "\(picker.value ?? "")")
        XCTAssertEqual(fieldValue(app, "canvasAreaRow"), "3"); XCTAssertEqual(fieldValue(app, "canvasAreaCols"), "10")
        shot(app, "F2-B24-area-drag")

        // Draw tab: a red stroke across the pad is one undo step.
        let pad = element(app, "canvasPixelPad")
        reveal(pad, app)
        let painted = pad.value as? String
        app.buttons["canvasColor_red"].tap()
        let a = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.4))
        a.press(forDuration: 0.1, thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45)), withVelocity: 200, thenHoldForDuration: 0.1)
        XCTAssertTrue(waitFor(4) { pad.value as? String != painted }, "the stroke painted pixels: \(pad.value ?? "")")
        shot(app, "F2-B24-draw-stroke")

        // Expression lock: the circle's centre X becomes an expression; its X axis is locked.
        reveal(app.segmentedControls["canvasTabs"], app)
        app.segmentedControls["canvasTabs"].buttons["Shapes"].tap()
        let row = element(app, "canvasShapeRow_0")
        reveal(row, app); row.buttons.firstMatch.tap()
        let cx = app.textFields["canvasField_cx"]
        reveal(cx, app); cx.tap()
        cx.press(forDuration: 1.0)
        let selectAll = app.menuItems["Select All"].firstMatch
        if selectAll.waitForExistence(timeout: 2) { selectAll.tap() }
        cx.typeText("{{weather.x}}\n")
        XCTAssertTrue(waitFor(4) { self.fieldValue(app, "canvasField_cx") == "{{weather.x}}" }, fieldValue(app, "canvasField_cx"))
        let badge = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "expression")).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 3), "the expression badge shows")
        shot(app, "F2-B24-expression-locked")
        close(app)
    }

    /// The split-flap notice: on a Flagship display the toggle goes and the page says why.
    func testSplitFlapDisplayShowsTheNotice() throws {
        let app = isolatedApplication()
        try openPixelClock(app)
        XCTAssertTrue(app.segmentedControls["editingSurface"].waitForExistence(timeout: 5))
        let picker = app.buttons["evaluationBoardPicker"]
        picker.tap()
        let kitchen = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Kitchen")).firstMatch
        XCTAssertTrue(kitchen.waitForExistence(timeout: 3)); kitchen.tap()
        let notice = element(app, "canvasNotPixelNotice")
        XCTAssertTrue(notice.waitForExistence(timeout: 4))
        XCTAssertTrue(notice.label.hasPrefix("This page has pixel canvases. This board can't draw them"), notice.label)
        XCTAssertFalse(app.segmentedControls["editingSurface"].exists, "Text | Canvases only on a pixel display")
        shot(app, "F2-B24-split-flap-notice")
        close(app)
    }

    // MARK: Helpers

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func layers(_ app: XCUIApplication) -> String { (element(app, "stageCanvasLayers").value as? String) ?? "" }
    private func fieldValue(_ app: XCUIApplication, _ id: String) -> String { (app.textFields[id].value as? String) ?? "" }
    private func waitFor(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat { if condition() { return true }; Thread.sleep(forTimeInterval: 0.2) } while Date() < deadline
        return false
    }
    /// Reveal controls inside the panel viewport, using its rail without editing the canvas.
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let toggle = app.segmentedControls["editingSurface"]
        let rail = self.element(app, "canvasesPanelHandle")
        func bounds() -> (top: CGFloat, bottom: CGFloat) {
            if toggle.exists, rail.exists {
                return CanvasRevealGeometry.panelBounds(viewport: rail.frame, coveringTop: toggle.frame.maxY)
            }
            return (window.minY + 80, window.maxY - 20)
        }
        func visible() -> Bool {
            guard element.exists, element.isHittable else { return false }
            let frame = element.frame, viewport = bounds()
            return CanvasRevealGeometry.isExposed(frame, top: viewport.top, bottom: viewport.bottom)
        }
        for _ in 0..<12 {
            if visible() { break }
            let viewport = bounds()
            let distance: CGFloat
            if element.exists {
                distance = CanvasRevealGeometry.scrollDistance(element.frame, top: viewport.top, bottom: viewport.bottom)
            } else { distance = -min(160, (viewport.bottom - viewport.top) / 2) }
            if distance == 0 { break }
            let from = rail.exists ? rail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                : app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: distance)), withVelocity: 600, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(visible(), "The interaction target must be exposed inside its scroll viewport")
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
    private func close(_ app: XCUIApplication) {
        app.navigationBars.buttons["Close"].tap()
        let discard = app.buttons["Discard and leave"]
        if discard.waitForExistence(timeout: 2) { discard.tap() }
    }

    private func openPixelClock(_ app: XCUIApplication) throws {
        try connectToFixture(app, scenario: "manual")
        let destination = app.buttons.matching(identifier: "destination-Pages").firstMatch
        for _ in 0..<5 {
            if destination.exists && destination.isHittable { destination.tap(); break }
            let sidebar = app.buttons["Show Sidebar"].firstMatch
            if sidebar.exists && sidebar.isHittable { sidebar.tap(); continue }
            let back = app.navigationBars.buttons["FiestaBoard"].firstMatch
            if back.exists && back.isHittable { back.tap() }
        }
        let row = pageCard(app, named: "Pixel Clock")
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        app.buttons["editLocalDraft"].tap()
        XCTAssertTrue(app.textViews["boardDocument"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(app.buttons["evaluationBoardPicker"].value as? String, "Pixoo", "the 10 × 16 page opens on the Pixoo")
    }

    private func connectToFixture(_ app: XCUIApplication, scenario: String) throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/ready")!); request.timeoutInterval = 3
        let semaphore = DispatchSemaphore(value: 0); var ready = false
        URLSession.shared.dataTask(with: request) { _, response, _ in ready = (response as? HTTPURLResponse)?.statusCode == 200; semaphore.signal() }.resume()
        semaphore.wait()
        try requireReadyFixture(ready, port: port)
        app.launchArguments = []; app.launch()
        let alias = "board-" + scenario + "-" + UUID().uuidString.prefix(8).lowercased()
        func revealForm(_ element: XCUIElement) {
            for _ in 0..<8 { if element.exists && element.isHittable { break }; app.swipeUp() }
            for _ in 0..<8 { if element.exists && element.isHittable { break }; app.swipeDown() }
        }
        let address = app.textFields["connectionAddress"]
        XCTAssertTrue(app.textFields["connectionAddress"].waitForExistence(timeout: 8))
        revealForm(address); typeConnectionAddress("http://127.0.0.1:\(port)/" + alias, into: address, in: app)
        let name = app.textFields["Server name (optional)"]
        revealForm(name); name.tap(); name.typeText(alias + "\n")
        let localHTTP = app.switches["connectionLocalHTTP"]
        revealForm(localHTTP)
        for _ in 0..<3 where (localHTTP.value as? String) != "1" {
            localHTTP.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap(); Thread.sleep(forTimeInterval: 0.5)
        }
        let connect = app.buttons["connectionConnect"]
        revealForm(connect); connect.tap()
        let username = app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout: 8), app.staticTexts["connectionMessage"].firstMatch.debugDescription)
        revealForm(username); username.tap(); username.typeText("fixture_admin")
        let password = app.secureTextFields["connectionPassword"]
        revealForm(password); password.tap(); password.typeText("fixture-password")
        let signIn = app.buttons["connectionSignIn"]
        revealForm(signIn); signIn.tap()
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 10), app.staticTexts["connectionMessage"].firstMatch.debugDescription)
    }
}
