import XCTest

@MainActor
private func selectTab(_ name: String, in app: XCUIApplication) {
    let destination = app.descendants(matching: .any).matching(identifier: "destination-" + name).firstMatch
    if destination.exists && destination.isHittable { destination.tap(); return }
    let direct = app.cells["destination-" + name].firstMatch
    if direct.exists && direct.isHittable { direct.tap(); return }
    // Standard split views collapse to a destination list on compact windows.
    for _ in 0..<5 {
        if destination.exists && destination.isHittable { destination.tap(); return }
        if direct.exists && direct.isHittable { direct.tap(); return }
        let sidebar = app.buttons["Show Sidebar"].firstMatch
        if sidebar.exists && sidebar.isHittable { sidebar.tap(); continue }
        let routes: [(String, String)] = [
            ("Schedule entry", "Schedule"), ("Welcome", "Pages"),
            ("Demo Kitchen", "Displays"), ("Pages", "FiestaBoard"),
            ("Collections", "FiestaBoard"), ("Schedule", "FiestaBoard"),
            ("Displays", "FiestaBoard"), ("Settings", "FiestaBoard"),
            ("FiestaBoard", "FiestaBoard")
        ]
        if let back = routes.map({ app.navigationBars[$0.0].buttons[$0.1] })
            .first(where: { $0.exists && $0.isHittable }) { back.tap() }
    }
    XCTAssertTrue(destination.waitForExistence(timeout: 5), "Destination missing: " + name)
    destination.tap()
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
        let hideKeyboard = app.buttons["Hide keyboard"]
        if hideKeyboard.waitForExistence(timeout: 3) {
            hideKeyboard.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        }
        XCTAssertTrue(review.isEnabled)
        review.tap()
        XCTAssertTrue(app.buttons["Confirm simulated action"].waitForExistence(timeout: 3))
        app.buttons["Confirm simulated action"].tap()
        XCTAssertTrue(app.staticTexts["Simulated — server acknowledged a send. Physical output is not verified."].waitForExistence(timeout: 5))
        selectTab("Pages", in: app)
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
        selectTab("Pages", in: app)
        app.staticTexts["Welcome"].tap()
        app.buttons["editLocalDraft"].tap()
        XCTAssertTrue(app.buttons["templateCanvasRow0"].waitForExistence(timeout: 5))
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
        selectTab("Pages", in: app)
        XCTAssertTrue(app.staticTexts["Welcome"].waitForExistence(timeout: 5))
        app.staticTexts["Welcome"].tap()
        app.buttons["editLocalDraft"].tap()
        XCTAssertTrue(app.navigationBars["Page editor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Name"].exists)
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        for _ in 0..<12 {
            let navigationBottom = app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? 0
            let container = app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable })
            let frame = container?.frame.intersection(app.frame) ?? app.frame
            let top = max(frame.minY, navigationBottom) + 20
            var bottom = frame.maxY - 20
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 12) }
            guard bottom > top + 40 else { return }
            var moveUp = upwards
            if element.exists {
                let y = element.frame.midY
                if element.isHittable && y >= top && y <= bottom { return }
                if y < top { moveUp = false }
                else if y > bottom { moveUp = true }
            }
            // Short drags keep a field from jumping across an iPad sheet's viewport.
            let middle = (top + bottom) / 2
            let distance = min(160, (bottom - top) * 0.45)
            let startY = middle + (moveUp ? distance / 2 : -distance / 2)
            let endY = middle + (moveUp ? -distance / 2 : distance / 2)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: startY - app.frame.minY))
            let end = origin.withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: endY - app.frame.minY))
            start.press(forDuration: 0.1, thenDragTo: end)
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
    func testMixedLibraryPreservesUnknownPagesAndShowsReadOnlyRoute() async throws {
        try await requireFixture()
        let app = XCUIApplication(); app.launchArguments = []; app.launch()
        let alias = connect(app, scenario: "mixed")
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10))
        selectTab("Pages", in: app)
        XCTAssertTrue(app.staticTexts["Document"].waitForExistence(timeout: 5))
        for title in ["Flexible document", "Future document"] {
            let row = app.staticTexts[title].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
            if title == "Flexible document" {
                XCTAssertTrue(app.buttons["editLocalDraft"].waitForExistence(timeout: 5))
            } else {
                XCTAssertTrue(app.staticTexts["This document cannot be edited in this native draft. Open the web editor for its full content and display previews."].waitForExistence(timeout: 5))
                XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "openWebEditor").firstMatch.exists)
                XCTAssertFalse(app.buttons["editLocalDraft"].exists)
            }
            let deletion = app.buttons["deleteLibraryPage"]
            reveal(deletion, app); XCTAssertFalse(deletion.isEnabled)
            let evidence = XCTAttachment(screenshot: app.screenshot())
            evidence.name = title; evidence.lifetime = .keepAlways; add(evidence)
            app.navigationBars.buttons["Pages"].tap()
        }
        selectTab("Settings", in: app)
        let disconnect = app.buttons["Disconnect"]
        reveal(disconnect, app); disconnect.tap()
        removeSaved(alias, app)
    }

    @MainActor
    func testExplicitPhysicalPreviewDisplaysItsPixelDimensions() async throws {
        try await requireFixture()
        let app = XCUIApplication(); app.launchArguments = []; app.launch()
        let alias = connect(app, scenario: "mixed")
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10))
        selectTab("Pages", in: app)
        app.staticTexts["Document"].tap()
        app.buttons["editLocalDraft"].tap()
        let picker = app.buttons["evaluationBoardPicker"]
        reveal(picker, app); picker.tap()
        app.buttons["Contract board"].tap()
        let preview = app.buttons["previewPage"]
        reveal(preview, app); XCTAssertTrue(preview.isEnabled); preview.tap()
        let surface = app.descendants(matching: .any).matching(identifier: "physicalPreview").firstMatch
        reveal(surface, app)
        XCTAssertTrue(surface.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(surface.label, "Server preview, 32 by 8 pixels")
        let dimensions = app.staticTexts["32 × 8 pixels"]
        reveal(dimensions, app); XCTAssertTrue(dimensions.exists)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Physical preview 32 by 8"; evidence.lifetime = .keepAlways; add(evidence)
        app.buttons["Close"].tap()
        app.navigationBars.buttons["Pages"].tap()
        selectTab("Settings", in: app)
        let disconnect = app.buttons["Disconnect"]
        reveal(disconnect, app); disconnect.tap(); removeSaved(alias, app)
    }

    /// Runs on both controller-selected iPhone and iPad destinations. Test server is synthetic.
    @MainActor
    func testFlexibleTextCanvasPreviewConditionalSaveAndReopen() async throws {
        try await requireFixture()
        let app = XCUIApplication(); app.launchArguments = []; app.launch()
        let alias = connect(app, scenario: "flexible")
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10))
        selectTab("Settings", in: app)
        let writes = app.switches["Enable changes on this server"]
        reveal(writes, app); writes.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let apply = app.buttons["Apply change setting"]
        reveal(apply, app); apply.tap()
        XCTAssertTrue(app.buttons["Disconnect"].waitForExistence(timeout: 10))
        selectTab("Pages", in: app)
        let row = app.staticTexts["Flexible document"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        app.buttons["editLocalDraft"].tap()
        let text = app.textViews["flexibleTextEditor"]
        reveal(text, app); XCTAssertTrue(text.waitForExistence(timeout: 5), app.debugDescription)
        text.tap(); text.typeText(" UI text")
        try hideFlexibleKeyboard(app, text: text)
        let blockTextLabel = app.staticTexts["flexibleTextEditor_label"]
        XCTAssertEqual(blockTextLabel.label, "Block text")
        revealFlexibleEditor([blockTextLabel], app); XCTAssertTrue(blockTextLabel.isHittable)
        XCTAssertTrue((text.value as? String)?.contains("UI text") == true)
        let textEvidence = XCTAttachment(screenshot: app.screenshot())
        textEvidence.name = "Editable flexible text"; textEvidence.lifetime = .keepAlways; add(textEvidence)
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(text.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue((text.value as? String)?.contains("UI text") == true)
        let adapted = XCTAttachment(screenshot: app.screenshot())
        adapted.name = "Flexible editor retains text across width change"; adapted.lifetime = .keepAlways; add(adapted)
        XCUIDevice.shared.orientation = .portrait

        // A populated style field must keep a visible name, independent of its placeholder.
        let blockStyle = app.buttons["Block style"]
        revealFlexibleEditor([blockStyle], app); blockStyle.tap()
        let color = app.descendants(matching: .any).matching(identifier: "flexibleField_color").firstMatch
        revealFlexibleEditor([color], app); color.tap(); color.typeText("white")
        assertVisibleFlexibleField(app, label: "Color", identifier: "flexibleField_color", value: "white")
        attachFlexibleInspector(app, name: "Populated text style retains Color label with keyboard")
        dismissFlexibleKeyboard(app)
        XCTAssertEqual(color.value as? String, "white")
        revealFlexibleEditor([blockStyle], app); blockStyle.tap()
        XCTAssertTrue(color.waitForNonExistence(timeout: 5), "Block style must actually collapse before querying page fields")
        let pageOptions = app.buttons["Page style, layout and targets"]
        revealFlexibleEditor([pageOptions], app); pageOptions.tap()
        let targets = app.textFields["flexibleTargets_boards"]
        revealFlexibleEditor([targets], app); targets.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Target field tap must focus native input")
        targets.typeText("contract-board")
        assertVisibleFlexibleField(app, label: "Allowed board IDs", identifier: "flexibleTargets_boards", value: "contract-board")
        attachFlexibleInspector(app, name: "Populated target restriction retains label with keyboard")
        dismissFlexibleKeyboard(app)
        XCTAssertEqual(targets.value as? String, "contract-board")
        revealFlexibleEditor([pageOptions], app); pageOptions.tap()
        XCTAssertTrue(targets.waitForNonExistence(timeout: 5), "Page options must actually collapse before querying Canvas fields")

        let canvasBlock = app.buttons["flexibleBlock_drawing"]
        revealFlexibleEditor([canvasBlock], app); canvasBlock.tap()
        XCTAssertTrue(canvasBlock.isSelected)
        assertVisibleFlexibleField(app, label: "Canvas Width", identifier: "canvasSize_0", value: "32")
        assertVisibleFlexibleField(app, label: "Canvas Height", identifier: "canvasSize_1", value: "16")
        assertVisibleFlexibleField(app, label: "Background", identifier: "flexibleField_background", value: "black")
        attachFlexibleInspector(app, name: "Populated Canvas dimensions and background labels")
        // Expanded styles are a valid user state: their duplicate Background field
        // must not compress or obscure the populated Canvas Background above them.
        revealFlexibleEditor([blockStyle], app); blockStyle.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "flexibleField_color").firstMatch.waitForExistence(timeout: 5))
        assertVisibleFlexibleField(app, label: "Background", identifier: "flexibleField_background", value: "black", matchingContexts: 2)
        attachFlexibleInspector(app, name: "Canvas Background remains readable with Block style expanded")
        revealFlexibleEditor([blockStyle], app); blockStyle.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "flexibleField_color").firstMatch.waitForNonExistence(timeout: 5))
        let textShape = app.buttons["canvasShape_0"]
        revealFlexibleEditor([textShape], app); textShape.tap()
        assertVisibleFlexibleField(app, label: "Shape text", identifier: "flexibleField_text", value: "Canvas")
        assertVisibleFlexibleField(app, label: "Text color", identifier: "flexibleField_color", value: "white")
        attachFlexibleInspector(app, name: "Populated shape text and color labels")
        let rectangle = app.buttons["canvasShape_1"]
        revealFlexibleEditor([rectangle], app); rectangle.tap()
        for (label, key, value) in [("X position", "x", "2"), ("Y position", "y", "9"), ("Width", "w", "10"), ("Height", "h", "5"), ("Fill", "fill", "red")] {
            assertVisibleFlexibleField(app, label: label, identifier: "flexibleField_\(key)", value: value)
        }
        let strokeLabel = app.staticTexts["flexibleField_stroke_label"]
        XCTAssertEqual(strokeLabel.label, "Stroke")
        revealFlexibleEditor([strokeLabel], app); XCTAssertTrue(strokeLabel.isHittable)
        attachFlexibleInspector(app, name: "Populated rectangle dimensions and fill labels")
        let width = app.descendants(matching: .any).matching(identifier: "flexibleField_w").firstMatch
        revealFlexibleEditor([width], app); XCTAssertTrue(width.exists)
        let increaseWidth = app.buttons["Increase Width"]
        revealFlexibleEditor([increaseWidth], app); increaseWidth.tap()
        XCTAssertEqual(width.value as? String, "11", "Only the selected width adjustment should run")
        let xPosition = app.descendants(matching: .any).matching(identifier: "flexibleField_x").firstMatch
        XCTAssertEqual(xPosition.value as? String, "2", "Resizing width must not also move the shape")
        XCTAssertFalse(app.staticTexts["Remove selected shape?"].exists)
        XCTAssertFalse(app.navigationBars["Insert expression"].exists)
        app.buttons["Undo"].tap()
        XCTAssertEqual(width.value as? String, "10")
        width.tap(); width.typeText("1")
        let typedWidth = try XCTUnwrap(width.value as? String)
        XCTAssertTrue(["101", "110"].contains(typedWidth), "Typing 1 into 10 must produce an exact valid insertion result; received \(typedWidth)")
        XCTAssertEqual(xPosition.value as? String, "2", "Typing width must not move the shape")
        assertVisibleFlexibleField(app, label: "Width", identifier: "flexibleField_w", value: typedWidth)
        attachFlexibleInspector(app, name: "Edited rectangle Width retains label with keyboard")
        dismissFlexibleKeyboard(app)
        XCTAssertEqual(width.value as? String, typedWidth, "Keyboard dismissal must preserve the numeric draft")
        XCTAssertEqual(xPosition.value as? String, "2")
        XCTAssertTrue(canvasBlock.isSelected)
        revealFlexibleEditor([width], app)
        let canvasEvidence = XCTAttachment(screenshot: app.screenshot())
        canvasEvidence.name = "Editable rectangle inspector"; canvasEvidence.lifetime = .keepAlways; add(canvasEvidence)
        let picker = app.buttons["evaluationBoardPicker"]
        reveal(picker, app); picker.tap(); app.buttons["Contract board"].tap()
        let preview = app.buttons["previewPage"]
        reveal(preview, app); XCTAssertTrue(preview.isEnabled); preview.tap()
        let dimensions = app.staticTexts["32 × 16 pixels"]
        reveal(dimensions, app); XCTAssertTrue(dimensions.waitForExistence(timeout: 8))
        let previewEvidence = XCTAttachment(screenshot: app.screenshot())
        previewEvidence.name = "Flexible server preview and warnings"; previewEvidence.lifetime = .keepAlways; add(previewEvidence)
        let save = app.buttons["savePageOnServer"]
        reveal(save, app); XCTAssertTrue(save.isEnabled); save.tap()
        app.buttons["Save page on server"].tap()
        let acknowledged = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Page storage acknowledged.")).firstMatch
        reveal(acknowledged, app); XCTAssertTrue(acknowledged.waitForExistence(timeout: 8))
        reveal(save, app); XCTAssertFalse(save.isEnabled)
        app.buttons["Close"].tap()
        let saveLocal = app.buttons["Save local draft and close"]
        if saveLocal.waitForExistence(timeout: 2) { saveLocal.tap() }
        XCTAssertTrue(app.buttons["editLocalDraft"].waitForExistence(timeout: 5))
        app.buttons["editLocalDraft"].tap()
        let reopenedText = app.textViews["flexibleTextEditor"]
        reveal(reopenedText, app); XCTAssertTrue(reopenedText.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue((reopenedText.value as? String)?.contains("UI text") == true)
        revealFlexibleEditor([canvasBlock], app); canvasBlock.tap()
        revealFlexibleEditor([rectangle], app); rectangle.tap()
        let reopenedWidth = app.descendants(matching: .any).matching(identifier: "flexibleField_w").firstMatch
        revealFlexibleEditor([reopenedWidth], app); XCTAssertEqual(reopenedWidth.value as? String, typedWidth, "Reopen must retain the exact width produced by real typing")
        assertVisibleFlexibleField(app, label: "Width", identifier: "flexibleField_w", value: typedWidth)
        attachFlexibleInspector(app, name: "Reopened rectangle retains Width label and exact edited value")
        app.buttons["Close"].tap()
        app.navigationBars.buttons["Pages"].tap()
        selectTab("Settings", in: app)
        let disconnect = app.buttons["Disconnect"]
        reveal(disconnect, app); disconnect.tap(); removeSaved(alias, app)
    }

    @MainActor
    func testFlexibleInvalidHiddenCanvasRoutesBackToRepairAndUndo() async throws {
        try await requireFixture()
        let app = XCUIApplication(); app.launchArguments = []; app.launch()
        let alias = connect(app, scenario: "flexible")
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10))
        selectTab("Settings", in: app)
        let writes = app.switches["Enable changes on this server"]
        reveal(writes, app); writes.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let apply = app.buttons["Apply change setting"]
        reveal(apply, app); apply.tap()
        selectTab("Pages", in: app)
        let flexible = app.staticTexts["Flexible document"].firstMatch
        XCTAssertTrue(flexible.waitForExistence(timeout: 8)); flexible.tap()
        app.buttons["editLocalDraft"].tap()
        let source = app.textViews["flexibleTextEditor"]
        reveal(source, app); XCTAssertTrue(source.waitForExistence(timeout: 5), app.debugDescription)
        source.tap(); source.typeText(" valid dirty edit")
        try hideFlexibleKeyboard(app, text: source)
        let picker = app.buttons["evaluationBoardPicker"]
        reveal(picker, app); picker.tap(); app.buttons["Contract board"].tap()
        let preview = app.buttons["previewPage"]
        reveal(preview, app); XCTAssertTrue(preview.isEnabled)
        let save = app.buttons["savePageOnServer"]
        reveal(save, app); XCTAssertTrue(save.isEnabled)
        let canvas = app.buttons["flexibleBlock_drawing"]
        reveal(canvas, app); canvas.tap()
        let rectangle = app.buttons["canvasShape_1"]
        reveal(rectangle, app); rectangle.tap()
        let width = app.descendants(matching: .any).matching(identifier: "flexibleField_w").firstMatch
        reveal(width, app); width.tap(); width.typeText(".")
        let invalidWidth = try XCTUnwrap(width.value as? String)
        dismissFlexibleKeyboard(app)
        XCTAssertEqual(width.value as? String, invalidWidth, "Keyboard dismissal must preserve the invalid intermediate draft")
        XCTAssertTrue(canvas.isSelected)
        reveal(preview, app); XCTAssertFalse(preview.isEnabled)
        reveal(save, app); XCTAssertFalse(save.isEnabled)
        let text = app.buttons["flexibleBlock_welcome"]
        reveal(text, app); text.tap()
        reveal(preview, app); XCTAssertFalse(preview.isEnabled, "Hidden invalid Canvas still gates preview")
        reveal(save, app); XCTAssertFalse(save.isEnabled, "Hidden invalid Canvas still gates save")
        let issue = app.buttons["flexibleIssue_w"]
        reveal(issue, app); XCTAssertTrue(issue.exists); issue.tap()
        XCTAssertTrue(width.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let widthLabel = app.staticTexts["flexibleField_w_label"]
        XCTAssertEqual(widthLabel.label, "Width")
        XCTAssertTrue(widthLabel.exists && widthLabel.isHittable, "Invalid focused drafts must retain their visible field name")
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Hidden invalid Canvas field revealed for repair"; evidence.lifetime = .keepAlways; add(evidence)
        app.buttons["Undo"].tap()
        XCTAssertTrue(issue.waitForNonExistence(timeout: 5))
        reveal(preview, app); XCTAssertTrue(preview.isEnabled)
        reveal(save, app); XCTAssertTrue(save.isEnabled, "Earlier valid text edit remains unsaved")
        app.buttons["Redo"].tap(); XCTAssertTrue(issue.waitForExistence(timeout: 5))
        reveal(preview, app); XCTAssertFalse(preview.isEnabled)
        reveal(save, app); XCTAssertFalse(save.isEnabled)
        app.buttons["Undo"].tap()
        reveal(preview, app); XCTAssertTrue(preview.isEnabled)
        reveal(save, app); XCTAssertTrue(save.isEnabled)
        app.buttons["Close"].tap()
        let discard = app.buttons["Discard unsaved changes"]
        if discard.waitForExistence(timeout: 2) { discard.tap() }
        XCTAssertTrue(app.buttons["editLocalDraft"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Pages"].tap(); selectTab("Settings", in: app)
        let disconnect = app.buttons["Disconnect"]
        reveal(disconnect, app); disconnect.tap(); removeSaved(alias, app)
    }

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
        selectTab("Pages", in: app)
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

    @MainActor private func flexibleEditorViewport(_ app: XCUIApplication, form: XCUIElement) -> CGRect {
        let bounds = form.frame.intersection(app.frame)
        let navigation = app.navigationBars["Page editor"]
        let top = max(bounds.minY, navigation.exists ? navigation.frame.maxY : bounds.minY) + 12
        let keyboard = app.keyboards.firstMatch
        let bottom = min(bounds.maxY, keyboard.exists ? keyboard.frame.minY : bounds.maxY) - 12
        return CGRect(x: bounds.minX + 4, y: top, width: bounds.width - 8, height: max(0, bottom - top))
    }

    /// Scroll the outer Form's margin, avoiding nested text views and keyboard gestures.
    /// AX isHittable alone can accept a control underneath the navigation bar.
    @MainActor private func revealFlexibleEditor(_ elements: [XCUIElement], _ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let form = app.collectionViews.containing(.button, identifier: "flexibleBlockActions").firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5), file: file, line: line)
        for attempt in 0..<24 {
            let viewport = flexibleEditorViewport(app, form: form)
            let frames = elements.filter { $0.exists && !$0.frame.isEmpty }.map(\.frame)
            let visible = elements.allSatisfy { $0.exists && !$0.frame.isEmpty && viewport.contains($0.frame) && $0.isHittable }
            if visible { return }
            guard viewport.height > 80 else { break }
            let target = frames.reduce(CGRect.null) { $0.union($1) }
            let moveDown: Bool
            if !target.isNull && target.minY < viewport.minY { moveDown = true }
            else if !target.isNull && target.maxY > viewport.maxY { moveDown = false }
            else if !target.isNull {
                // A sibling label is on screen but its field has no usable frame.
                // Preserve this as a real visibility failure rather than choosing another field.
                break
            } else { moveDown = attempt >= 12 }
            let distance = min(180, viewport.height * 0.45)
            let startY = viewport.midY + (moveDown ? -distance / 2 : distance / 2)
            let endY = viewport.midY + (moveDown ? distance / 2 : -distance / 2)
            let origin = form.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: 8, dy: startY - form.frame.minY))
            let end = origin.withOffset(CGVector(dx: 8, dy: endY - form.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        attachFlexibleInspector(app, name: "Flexible field visibility failure")
        XCTFail("Controls must fit below navigation and above keyboard: \(elements.map { $0.debugDescription }.joined(separator: "; "))", file: file, line: line)
    }

    @MainActor private func assertVisibleFlexibleField(_ app: XCUIApplication, label: String, identifier: String, value: String, matchingContexts: Int = 1, file: StaticString = #filePath, line: UInt = #line) {
        let names = app.staticTexts.matching(identifier: identifier + "_label")
        let fields = app.descendants(matching: .any).matching(identifier: identifier)
        if names.count != matchingContexts || fields.count != matchingContexts {
            let matches = names.allElementsBoundByIndex.enumerated().map { index, element in
                "Label match \(index):\n\(element.debugDescription)"
            } + fields.allElementsBoundByIndex.enumerated().map { index, element in
                "Field match \(index):\n\(element.debugDescription)"
            }
            let detail = XCTAttachment(string: "Expected \(matchingContexts) contexts for \(identifier), visible label \(label), value \(value).\n\n" + matches.joined(separator: "\n\n"))
            detail.name = "Flexible label and field match diagnostics - \(identifier)"
            detail.lifetime = .keepAlways; add(detail)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Full accessibility hierarchy before context assertion - \(identifier)"
            hierarchy.lifetime = .keepAlways; add(hierarchy)
            attachFlexibleInspector(app, name: "Context count mismatch before assertion - \(identifier)")
        }
        XCTAssertEqual(names.count, matchingContexts, "Verify the expected inspector contexts before choosing their first field", file: file, line: line)
        XCTAssertEqual(fields.count, matchingContexts, "Verify shared field IDs are from the expected disclosure state", file: file, line: line)
        // Canvas precedes Block style in the native inspector. Exact value and geometry
        // checks below prevent a later empty style field from satisfying Canvas acceptance.
        let name = names.firstMatch
        let field = fields.firstMatch
        revealFlexibleEditor([name, field], app, file: file, line: line)
        XCTAssertTrue(name.exists && name.isHittable, "Populated field must retain visible label: \(label)", file: file, line: line)
        XCTAssertEqual(name.label, label, "The identified native label must display the field name", file: file, line: line)
        XCTAssertTrue(field.isHittable, file: file, line: line)
        XCTAssertEqual(field.value as? String, value, file: file, line: line)
        XCTAssertTrue(name.isHittable, "Label and populated value must be visible together", file: file, line: line)
    }

    @MainActor private func attachFlexibleInspector(_ app: XCUIApplication, name: String) {
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = name; evidence.lifetime = .keepAlways; add(evidence)
    }

    @MainActor private func dismissFlexibleKeyboard(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), file: file, line: line)
        let actions = app.buttons.matching(identifier: "flexibleHideKeyboard")
        XCTAssertEqual(actions.count, 1, "Exactly one app dismissal action should own this identifier", file: file, line: line)
        let hide = actions.firstMatch
        XCTAssertTrue(hide.isHittable, "Keyboard dismissal must be reachable without scrolling the editor", file: file, line: line)
        hide.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), app.debugDescription, file: file, line: line)
        XCTAssertFalse(app.navigationBars["Insert expression"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["Keep editing"].exists, "Dismissing the keyboard must not initiate closing the draft", file: file, line: line)
    }

    @MainActor private func hideFlexibleKeyboard(_ app: XCUIApplication, text: XCUIElement) throws {
        let expectedText = try XCTUnwrap(text.value as? String)
        let selectedBlock = app.buttons["flexibleBlock_welcome"]
        XCTAssertTrue(selectedBlock.isSelected)
        let blockFont = app.descendants(matching: .any).matching(identifier: "flexibleField_font").firstMatch
        let pageAlignment = app.descendants(matching: .any).matching(identifier: "flexibleChoice_valign").firstMatch
        XCTAssertFalse(blockFont.exists, "Block styles start collapsed")
        XCTAssertFalse(pageAlignment.exists, "Page styles start collapsed")
        dismissFlexibleKeyboard(app)
        XCTAssertFalse(app.navigationBars["Insert expression"].exists, "Hide keyboard must not open the expression sheet")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "flexibleExpressionSource").firstMatch.exists)
        XCTAssertEqual(text.value as? String, expectedText, "Dismissing input must preserve exact text")
        XCTAssertTrue(selectedBlock.isSelected, "Dismissing input must retain the selected block")
        XCTAssertFalse(app.buttons["flexibleBlock_drawing"].isSelected)
        XCTAssertFalse(blockFont.exists, "Hide keyboard must not expand block styles")
        XCTAssertFalse(pageAlignment.exists, "Hide keyboard must not expand page styles")
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
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), app.debugDescription)
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
        reveal(name, app); name.tap(); name.typeText(alias + "\n")
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
        selectTab("Pages", in: app)
        let create = app.buttons["newLibraryPage"]
        XCTAssertTrue(create.waitForExistence(timeout: 3)); create.tap()
        let name = app.textFields["New page name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3)); name.tap(); name.typeText("Native LED test")
        if app.buttons["Hide keyboard"].waitForExistence(timeout: 3) {
            app.buttons["Hide keyboard"].tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        }
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

@MainActor final class CreativeEditorUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    func testRichTokenSourceRoundTripAndStructuralUndo() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        selectTab("Pages", in: app)
        app.staticTexts["Welcome"].tap(); app.buttons["editLocalDraft"].tap()
        XCTAssertTrue(app.buttons["templateCanvasRow0"].waitForExistence(timeout: 8))
        reveal(app.buttons["addTemplateRow"], app); app.buttons["addTemplateRow"].tap()
        let row = app.textViews["templateRowText"]
        reveal(row, app); XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap(); row.typeText("NATIVE ")
        app.buttons["editorHideKeyboard"].tap()
        reveal(app.buttons["insertTemplateToken"], app); app.buttons["insertTemplateToken"].tap()
        app.buttons["Variable"].tap()
        XCTAssertTrue(app.textFields["tokenSource"].waitForExistence(timeout: 4) || app.textViews["tokenSource"].exists)
        app.navigationBars.buttons["Insert"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 4))
        XCTAssertTrue(NSPredicate(format: "value == %@", "NATIVE {{weather.temperature}}").evaluate(with: row) ||
                      XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "NATIVE {{weather.temperature}}"), object: row)], timeout: 4) == .completed)
        reveal(app.buttons["Source"], app); app.buttons["Source"].tap()
        XCTAssertEqual(row.value as? String, "NATIVE {{weather.temperature}}")
        app.buttons["Rich"].tap()
        XCTAssertEqual(row.value as? String, "NATIVE {{weather.temperature}}")
        app.navigationBars.buttons["Undo"].tap()
        XCTAssertEqual(row.value as? String, "NATIVE ")
        app.navigationBars.buttons["Redo"].tap()
        XCTAssertEqual(row.value as? String, "NATIVE {{weather.temperature}}")
        reveal(app.buttons["templateRowActions"], app); app.buttons["templateRowActions"].tap()
        app.buttons["Duplicate row"].tap()
        reveal(app.buttons["Source"], app); app.buttons["Source"].tap()
        XCTAssertEqual(app.textViews["templateRowText"].value as? String, "NATIVE {{weather.temperature}}", "Changing row must not replay the last insertion")
        app.buttons["Rich"].tap()
        let richRow = app.textViews["templateRowText"]
        richRow.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 160, dy: 26)).tap()
        let tokenSource = app.textFields["tokenSource"]
        XCTAssertTrue(tokenSource.waitForExistence(timeout: 4), "Tapping a chip opens its editor")
        // Applying an unchanged chip must replace it, never insert a second copy.
        XCTAssertEqual(tokenSource.value as? String, "{{weather.temperature}}")
        XCTAssertTrue(app.navigationBars.buttons["Insert"].isEnabled)
        app.navigationBars.buttons["Insert"].tap()
        XCTAssertEqual(app.textViews["templateRowText"].value as? String, "NATIVE {{weather.temperature}}")
        reveal(app.buttons["insertTemplateToken"], app); app.buttons["insertTemplateToken"].tap()
        app.buttons["Flexible space"].tap()
        XCTAssertEqual(app.textViews["templateRowText"].value as? String, "NATIVE {{weather.temperature}}{{fill_space}}", "An unchanged chip replacement must still advance the caret")
        app.navigationBars.buttons["Close"].tap(); app.buttons["Discard unsaved changes"].tap()
        XCTAssertTrue(app.buttons["editLocalDraft"].waitForExistence(timeout: 5))
    }
    func testFreshSplitFlapPaletteAndFormattingSave() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        selectTab("Pages", in: app)
        app.buttons["newLibraryPage"].tap()
        let name = app.textFields["New page name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3)); name.tap(); name.typeText("Creative flap test")
        name.typeText("\n")
        app.buttons["createLibraryPage"].tap()
        let first = app.buttons["addFirstTemplateRow"]
        XCTAssertTrue(first.waitForExistence(timeout: 8)); first.tap()
        let row = app.textViews["templateRowText"]
        reveal(row, app); row.tap(); row.typeText("HELLO")
        app.buttons["editorHideKeyboard"].tap()
        reveal(app.buttons["insertTemplateToken"], app); app.buttons["insertTemplateToken"].tap()
        app.buttons["Red"].tap()
        reveal(app.buttons["Source"], app); app.buttons["Source"].tap()
        XCTAssertEqual(row.value as? String, "HELLO{{red}}")
        reveal(app.buttons["Right"], app); app.buttons["Right"].tap()
        let wrap = app.switches["Wrap text"]
        reveal(wrap, app); wrap.tap()
        let save = app.buttons["savePageOnServer"]
        reveal(save, app); XCTAssertTrue(save.isEnabled); save.tap()
        app.buttons["Simulate save"].tap()
        let acknowledged = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Page storage acknowledged")).firstMatch
        reveal(acknowledged, app); XCTAssertTrue(acknowledged.waitForExistence(timeout: 8))
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp(velocity: .slow)
        }
    }
}


extension DemoUITests {
    @MainActor
    func testDestinationJourneysAndActualReadOnlyScheduleDetails() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10))
        selectTab("Pages", in: app)
        XCTAssertTrue(app.staticTexts["Welcome"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["newLibraryPage"].isHittable)
        selectTab("Collections", in: app)
        XCTAssertTrue(app.buttons["createCollection"].waitForExistence(timeout: 3))
        selectTab("Schedule", in: app)
        let schedule = app.buttons["schedule-demo-morning"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        schedule.tap()
        XCTAssertTrue(app.staticTexts["Server time semantics"].waitForExistence(timeout: 3))
        let dayPattern = app.descendants(matching: .any).matching(identifier: "scheduleDayPattern").firstMatch
        let start = app.descendants(matching: .any).matching(identifier: "scheduleStart").firstMatch
        XCTAssertTrue(dayPattern.waitForExistence(timeout: 3))
        XCTAssertEqual(dayPattern.value as? String, "weekdays")
        XCTAssertTrue(start.exists)
        XCTAssertEqual(start.value as? String, "08:00")
        XCTAssertFalse(app.buttons["Save schedule"].exists)
        selectTab("Displays", in: app)
        app.staticTexts["Demo Kitchen"].firstMatch.tap()
        app.buttons["displayPlayback"].tap()
        XCTAssertTrue(app.buttons["Pause updates"].waitForExistence(timeout: 3))
        let playbackBack = app.navigationBars["Playback"].buttons["Demo Kitchen"]
        XCTAssertTrue(playbackBack.isHittable); playbackBack.tap()
        XCTAssertTrue(app.buttons["displayPlayback"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testEditorSheetAndSelectionSurviveWindowAdaptation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10))
        selectTab("Pages", in: app)
        app.staticTexts["Welcome"].tap()
        app.buttons["editLocalDraft"].tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText(" resize")
        let before = name.value as? String
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, before)
        XCTAssertTrue(app.buttons["Close"].isHittable)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(name.value as? String, before)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Discard unsaved changes"].waitForExistence(timeout: 3))
        app.buttons["Discard unsaved changes"].tap()
        XCTAssertTrue(app.buttons["editLocalDraft"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testRecoveryInventoryReachableConnectedAndDisconnected() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Compose text"].waitForExistence(timeout: 10))
        selectTab("Settings", in: app)
        let entry = app.buttons["localDraftRecovery"]
        scrollTo(entry, in: app)
        XCTAssertTrue(entry.isHittable); entry.tap()
        XCTAssertTrue(app.navigationBars["Draft recovery & export"].waitForExistence(timeout: 3))
        let recoveryBack = app.navigationBars["Draft recovery & export"].buttons["Settings"]
        XCTAssertTrue(recoveryBack.isHittable); recoveryBack.tap()
        XCTAssertTrue(app.buttons["Disconnect"].waitForExistence(timeout: 3))
        scrollTo(app.buttons["Disconnect"], in: app, upwards: false)
        app.buttons["Disconnect"].tap()
        XCTAssertTrue(app.buttons["findFiestaBoard"].waitForExistence(timeout: 5))
        let disconnectedEntry = app.buttons["localDraftRecovery"]
        scrollTo(disconnectedEntry, in: app)
        XCTAssertTrue(disconnectedEntry.exists)
        XCTAssertTrue(disconnectedEntry.isHittable)
        disconnectedEntry.tap()
        XCTAssertTrue(app.navigationBars["Draft recovery & export"].waitForExistence(timeout: 3))
    }
}
