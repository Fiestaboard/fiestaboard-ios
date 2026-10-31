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
        app.buttons["Hide keyboard"].tap()
        let textEvidence = XCTAttachment(screenshot: app.screenshot())
        textEvidence.name = "Editable flexible text"; textEvidence.lifetime = .keepAlways; add(textEvidence)
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(text.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue((text.value as? String)?.contains("UI text") == true)
        let adapted = XCTAttachment(screenshot: app.screenshot())
        adapted.name = "Flexible editor retains text across width change"; adapted.lifetime = .keepAlways; add(adapted)
        XCUIDevice.shared.orientation = .portrait

        let canvasBlock = app.buttons["flexibleBlock_drawing"]
        reveal(canvasBlock, app); canvasBlock.tap()
        let rectangle = app.buttons["canvasShape_1"]
        reveal(rectangle, app); rectangle.tap()
        let width = app.descendants(matching: .any).matching(identifier: "flexibleField_w").firstMatch
        reveal(width, app); XCTAssertTrue(width.exists)
        width.tap(); width.typeText("1")
        app.buttons["Close"].tap()
        let keep = app.buttons["Keep editing"]
        if keep.exists && keep.isHittable { keep.tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap() }
        reveal(width, app)
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
        app.buttons["flexibleBlock_drawing"].tap()
        reveal(app.buttons["canvasShape_1"], app); app.buttons["canvasShape_1"].tap()
        let reopenedWidth = app.descendants(matching: .any).matching(identifier: "flexibleField_w").firstMatch
        reveal(reopenedWidth, app); XCTAssertEqual(reopenedWidth.value as? String, "101")
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
        app.buttons["Hide keyboard"].tap()
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
        app.buttons["Close"].tap()
        let keep = app.buttons["Keep editing"]
        if keep.exists && keep.isHittable { keep.tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap() }
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
