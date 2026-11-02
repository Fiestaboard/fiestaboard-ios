import XCTest

/// Uses native input/recovery. Synthetic export files are seeded externally by the controller.
@MainActor final class CollectionRecoveryUITests: XCTestCase {
    private func destination(_ name: String, app: XCUIApplication) {
        let target = app.descendants(matching: .any).matching(identifier: "destination-" + name).firstMatch
        for _ in 0..<6 {
            if target.exists && target.isHittable { target.tap(); return }
            let sidebar = app.buttons["Show Sidebar"].firstMatch
            if sidebar.exists && sidebar.isHittable { sidebar.tap(); continue }
            let back = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["FiestaBoard", "Pages", "Settings", "Collections"])).firstMatch
            if back.exists && back.isHittable { back.tap() }
        }
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        target.tap()
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, upwards: Bool = true) {
        for _ in 0..<16 {
            let container = app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable })
            let frame = container?.frame.intersection(app.frame) ?? app.frame
            let top = max(frame.minY, app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? 0) + 20
            let bottom = min(frame.maxY - 20, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 12 : frame.maxY - 20)
            if element.exists && element.isHittable && element.frame.midY >= top && element.frame.midY <= bottom { return }
            guard bottom > top + 40 else { break }
            let up = element.exists ? element.frame.midY > bottom : upwards
            let middle = (top + bottom) / 2, distance = min(160, (bottom - top) * 0.45)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: middle + (up ? distance / 2 : -distance / 2) - app.frame.minY))
            let end = origin.withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: middle + (up ? -distance / 2 : distance / 2) - app.frame.minY))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    private func openCreation(_ app: XCUIApplication) {
        destination("Collections", app: app)
        let create = app.buttons["createCollection"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        XCTAssertTrue(app.textFields["collectionName"].waitForExistence(timeout: 5), app.debugDescription)
    }
    func testSameScopeCreationDraftRecoversExactNativeInputAfterRelaunch() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 10))
        openCreation(app)
        let name = "Collection recovery UI " + UUID().uuidString
        let nameField = app.textFields["collectionName"]
        nameField.tap(); nameField.typeText(name)
        XCTAssertEqual(nameField.value as? String, name)
        let interval = app.textFields["Time interval in seconds, 5 through 86400"]
        reveal(interval, app: app); interval.tap(); interval.typeText(".")
        let enteredInterval = try XCTUnwrap(interval.value as? String)
        XCTAssertTrue(enteredInterval.contains(".")); XCTAssertNil(Int(enteredInterval))
        app.navigationBars.buttons["Close"].tap()
        let keep = app.buttons["Keep local draft and close"]
        XCTAssertTrue(keep.waitForExistence(timeout: 3)); keep.tap()
        XCTAssertTrue(app.buttons["createCollection"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 10))
        openCreation(app)
        let recover = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Recover ‘" + name + "’")).firstMatch
        reveal(recover, app: app, upwards: false)
        XCTAssertTrue(recover.isEnabled); recover.tap()
        reveal(nameField, app: app, upwards: false)
        XCTAssertEqual(nameField.value as? String, name)
        capture(app, "collection-same-scope-recovered-name")
        reveal(interval, app: app)
        XCTAssertEqual(interval.value as? String, enteredInterval)
        capture(app, "collection-same-scope-recovered-invalid-interval")
        let save = app.buttons["saveCollection"]; reveal(save, app: app)
        XCTAssertFalse(save.isEnabled, "The preserved invalid numeric input must remain invalid")
        app.navigationBars.buttons["Close"].tap()
        let discard = app.buttons["Discard draft and close"]
        XCTAssertTrue(discard.waitForExistence(timeout: 3)); discard.tap()
        XCTAssertTrue(app.buttons["createCollection"].waitForExistence(timeout: 5))
        openCreation(app)
        XCTAssertFalse(recover.exists, "Only this recovered test lineage was explicitly discarded")
        app.navigationBars.buttons["Close"].tap()
    }
    func testOriginalCollectionInventoryAndShareSheetConnectedThenDisconnected() throws {
        guard ProcessInfo.processInfo.environment["COLLECTION_RECOVERY_SEEDED"] == "1" else {
            throw XCTSkip("Controller must seed Tests/Fixtures/CollectionRecovery originals; see setup.md")
        }
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 10))
        destination("Settings", app: app)
        for disconnected in [false, true] {
            if disconnected {
                let disconnect = app.buttons["Disconnect"]; reveal(disconnect, app: app, upwards: false); disconnect.tap()
                XCTAssertTrue(app.buttons["findFiestaBoard"].waitForExistence(timeout: 5))
            }
            let recovery = app.buttons["localDraftRecovery"]; reveal(recovery, app: app); recovery.tap()
            XCTAssertTrue(app.navigationBars["Draft recovery & export"].waitForExistence(timeout: 5))
            for (filename, classification) in [
                ("00000000-0000-4000-8000-000000000201.json", "Unassigned legacy draft"),
                ("00000000-0000-4000-8000-000000000202.json", "Unsupported archive format"),
                ("00000000-0000-4000-8000-000000000203.json", "Damaged draft")
            ] {
                let file = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", filename)).firstMatch; reveal(file, app: app); file.tap()
                XCTAssertTrue(app.navigationBars["Collection draft details"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts[classification].exists, app.debugDescription)
                XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recover ‘'")).firstMatch.exists)
                XCTAssertFalse(app.buttons["saveCollection"].exists)
                XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'adopt'")).firstMatch.exists)
                let export = app.buttons["exportOriginalCollectionDraft"]; reveal(export, app: app)
                capture(app, "collection-original-" + (disconnected ? "disconnected-" : "connected-") + filename)
                export.tap()
                let copy = app.buttons["Copy"].firstMatch
                let saveFile = app.buttons["Save to Files"].firstMatch
                let activity = app.otherElements["ActivityListView"].firstMatch
                let shareVisible = NSPredicate { _, _ in copy.exists || saveFile.exists || activity.exists }
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: shareVisible, object: nil)], timeout: 5), .completed, app.debugDescription)
                let close = app.buttons["Close"].firstMatch
                XCTAssertTrue(close.waitForExistence(timeout: 3), app.debugDescription); close.tap()
                XCTAssertTrue(app.navigationBars["Collection draft details"].exists)
                app.navigationBars["Collection draft details"].buttons.firstMatch.tap()
            }
            capture(app, disconnected ? "collection-inventory-disconnected" : "collection-inventory-connected")
            app.navigationBars["Draft recovery & export"].buttons.firstMatch.tap()
        }
    }
}
