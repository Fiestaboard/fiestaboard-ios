import XCTest

/// Home "now showing" + the shared renderer, against the loopback fixture's
/// `/board-<scenario>-<n>/` prefix family (mock content, never a real server).
/// Uses the native in-process loopback fixture. Screenshots go
/// to TEST_RUNNER_SHOT_DIR when set (always as attachments too).
final class BoardVisualsUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    private var port: String { String(FixtureHTTPServer.shared.port) }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipadair11m4" : "iphone17promax" }

    /// B8 (+B33 hierarchy): the status row for every delivered scenario.
    @MainActor
    func testHomeStatusRowStates() async throws {
        try await requireFixture()
        let expectations: [(String, String, String, [String])] = [
            ("manual", "Hello World", "Manual Mode", []),
            ("schedule", "Hello World", "Schedule Mode", []),
            ("schedule-gap", "Schedule gap (no default page set)", "Schedule Mode", []),
            ("collection", "Morning rotation › ", "Collection", ["collectionBadge"]),
            ("collection-native-null", "Morning rotation › Device selecting…", "Collection", ["collectionBadge"]),
            ("override", "Desk Note", "Override", []),
            ("paused", "Hello World", "Manual Mode", ["pausedBadge"]),
            ("silence", "Hello World", "Manual Mode", ["silenceBadge"]),
        ]
        for (scenario, name, mode, badges) in expectations {
            let app = launchSignedIn(scenario: scenario)
            let nowShowing = app.descendants(matching: .any)["nowShowingName"]
            let label = NSPredicate(format: "label BEGINSWITH %@", name)
            XCTAssertTrue(nowShowing.waitForExistence(timeout: 10), "\(scenario): \(app.debugDescription)")
            waitFor(nowShowing, label, 10, "\(scenario) name")
            let modeBadge = app.descendants(matching: .any)["modeBadge"]
            waitFor(modeBadge, NSPredicate(format: "label == %@", mode), 10, "\(scenario) mode")
            for id in ["collectionBadge", "silenceBadge", "pausedBadge"] {
                XCTAssertEqual(app.descendants(matching: .any)[id].exists, badges.contains(id), "\(scenario): \(id)")
            }
            let board = app.descendants(matching: .any)["homeBoard"]
            XCTAssertTrue(board.waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "may be cached")).firstMatch.exists,
                           "no permanent cache disclaimer")
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Source")).firstMatch.exists, "no source: label")
            assertBoardIsTheLargestElement(board, in: app, allowedAbove: [name, mode, "Collection", "Paused", "Silence mode active"])
            settle(1.2) // let the flip settle before the picture
            shot(app, "D1-B8-\(scenario)")
            if scenario == "manual" { shot(app, "D1-B33-home") }
            app.terminate()
        }
    }

    /// B1, B2, B5 (flap fallback): the shared renderer on the fixture boards.
    @MainActor
    func testBoardGallery() async throws {
        try await requireFixture()
        let app = launchSignedIn(scenario: "manual")
        let board = app.descendants(matching: .any)["homeBoard"]
        waitFor(board, NSPredicate(format: "value CONTAINS %@", "HELLO"), 10, "kitchen frame")
        XCTAssertTrue((board.value as? String ?? "").contains("WORLD 62°"), "Kitchen draws code 62 as a degree")
        settle(2.5)
        shot(app, "D1-B1-kitchen")
        for (display, file, check) in [("Hall", "D1-B1-hall", "WORLD 62♥"), ("Desk", "D1-B2-desk", "LOVE ♥"),
                                       ("Wall", "D1-B3-wall-home", "FOUR NOTES"), ("Mystery", "D1-B5-mystery", "UNKNOWN MODEL")] {
            choose(display, in: app)
            waitFor(board, NSPredicate(format: "value CONTAINS %@", check), 10, display)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "web preview")).firstMatch.exists)
            settle(2.5)
            shot(app, file)
        }
    }

    /// B6: Change page → pick a page; the tiles flip and the board re-reads by itself.
    @MainActor
    func testChangePageFlipsTheBoard() async throws {
        try await requireFixture()
        let app = launchSignedIn(scenario: "manual")
        enableChanges(app)
        let board = app.descendants(matching: .any)["homeBoard"]
        waitFor(board, NSPredicate(format: "value CONTAINS %@", "HELLO"), 15, "kitchen frame")
        let change = app.buttons["changePage"]
        XCTAssertTrue(change.waitForExistence(timeout: 10))
        waitFor(change, NSPredicate(format: "isEnabled == true"), 10, "change page enabled")
        settle(1.5)
        change.tap()
        let page = app.buttons["Good Morning"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        page.tap()
        let show = app.buttons["homeShowPage"]
        XCTAssertTrue(show.waitForExistence(timeout: 5)); show.tap()
        let back = app.navigationBars.buttons["FiestaBoard"]
        if back.waitForExistence(timeout: 3) { back.tap() }
        waitFor(board, NSPredicate(format: "value CONTAINS %@", "GOOD MORNING"), 8, "flipped frame")
        let name = app.descendants(matching: .any)["nowShowingName"]
        waitFor(name, NSPredicate(format: "label == %@", "Good Morning"), 8, "now showing follows the send")
        settle(4)
        shot(app, "D1-B6-after-change")
    }

    @MainActor
    func testHomeHeroShowsTitleAndScopedChangePageSheet() async throws {
        try await requireFixture()
        let app = launchSignedIn(scenario: "manual")
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["homeBoard"].exists)
        XCTAssertTrue(app.buttons["homeCompose"].exists)
        let change = app.buttons["changePage"]
        XCTAssertTrue(change.waitForExistence(timeout: 10)); change.tap()
        XCTAssertTrue(app.navigationBars["Change Page"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Home"].exists)
        app.terminate()
    }

    // MARK: helpers

    @MainActor private func settle(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    @MainActor private func assertBoardIsTheLargestElement(_ board: XCUIElement, in app: XCUIApplication, allowedAbove: [String]) {
        let boardFrame = board.frame
        let area = boardFrame.width * boardFrame.height
        let navBottom = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : 0
        for kind in [XCUIElement.ElementType.staticText, .button, .image] {
            for element in app.descendants(matching: kind).allElementsBoundByIndex where element.exists && !element.frame.isEmpty {
                let frame = element.frame.intersection(app.frame)
                // Only the board's own column counts (the iPad sidebar sits beside it).
                guard !frame.isNull, frame.minY >= navBottom, frame.maxX > boardFrame.minX, frame.minX < boardFrame.maxX else { continue }
                if element.identifier != "homeBoard" {
                    XCTAssertLessThan(frame.width * frame.height, area, "\(element.identifier) \(element.label) is larger than the board")
                }
                if kind == .staticText, frame.maxY <= boardFrame.minY + 1 {
                    XCTAssertTrue(allowedAbove.contains { element.label.hasPrefix($0) } || element.label.isEmpty,
                                  "unexpected text above the board: \(element.label)")
                }
            }
        }
    }

    /// W2 (iOS-R2): Home in plain words with a useful lower half — no server
    /// URL, no "read-only" jargon, the next schedule entry and the other displays.
    @MainActor
    func testHomeIsPlainAndUseful() async throws {
        try await requireFixture()
        let app = launchSignedIn(scenario: "schedule")
        let upNext = app.descendants(matching: .any)["homeUpNext"]
        XCTAssertTrue(upNext.waitForExistence(timeout: 10), app.debugDescription)
        let others = app.descendants(matching: .any)["otherDisplay_hall"]
        XCTAssertTrue(others.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["homeDisplayPicker"].label.contains("127.0.0.1"), "The display switcher includes its host line")
        for jargon in ["read-only", "checked separately", "Board controls enabled"] {
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", jargon)).firstMatch.exists, jargon)
        }
        XCTAssertFalse(app.descendants(matching: .any)["homeChangesOff"].exists)
        try await Task.sleep(nanoseconds: 2_500_000_000)
        shot(app, "W2-home")
        app.swipeUp()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        shot(app, "W2-home-lower")
        // Tapping another display switches Home to it.
        reveal(others, app); others.tap()
        let name = app.descendants(matching: .any)["nowShowingName"]
        waitFor(name, NSPredicate(format: "label == %@", "Hall Hello"), 10, "Hall's page")
    }

    /// B11 (iOS-R2): Pages as cards with server-rendered static thumbnails drawn
    /// as the selected display, type badges and "Not on this display".
    @MainActor
    func testPagesThumbnails() async throws {
        try await requireFixture()
        let app = launchSignedIn(scenario: "manual")
        selectDestination("Pages", in: app)
        let morning = app.descendants(matching: .any)["pageThumbnail_morning"]
        XCTAssertTrue(morning.waitForExistence(timeout: 10), app.debugDescription)
        waitFor(morning, NSPredicate(format: "value == %@", "rendered"), 10, "Good Morning thumbnail")
        XCTAssertTrue(morning.label.contains("GOOD MORNING"), morning.label)
        XCTAssertTrue(morning.label.contains("WARM OUT"), "the server's render, not the template source: \(morning.label)")
        XCTAssertFalse(morning.label.contains("WEATHER."), "no variable names on the thumbnail")
        XCTAssertTrue(app.descendants(matching: .any)["notOnThisDisplay_note"].exists, "a Note page on a Flagship")
        XCTAssertFalse(app.descendants(matching: .any)["notOnThisDisplay_morning"].exists)
        XCTAssertTrue(app.staticTexts["Note Array"].exists && app.staticTexts["Panel"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "no fixed grid")).firstMatch.exists)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        shot(app, "W2-B11-pages")
        app.swipeUp()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        shot(app, "W2-B11-pages-lower")
    }

    /// B9 (iOS-R2): the three out-of-sync faces with the web's actions, then
    /// Save as page and Restore against the fixture.
    @MainActor
    func testOutOfSyncFaces() async throws {
        try await requireFixture()
        for (scenario, restore, save, dismiss) in [("overwritten", true, false, false), ("kept", false, true, true)] {
            let app = launchSignedIn(scenario: scenario)
            let banner = app.descendants(matching: .any)["outOfSyncBanner_\(scenario)"]
            XCTAssertTrue(banner.waitForExistence(timeout: 15), "\(scenario): \(app.debugDescription)")
            XCTAssertEqual(app.buttons["outOfSyncRestore"].exists, restore, scenario)
            XCTAssertEqual(app.buttons["outOfSyncSave"].exists, save, scenario)
            XCTAssertEqual(app.buttons["outOfSyncDismiss"].exists, dismiss, scenario)
            try await Task.sleep(nanoseconds: 1_500_000_000)
            shot(app, "W2-B9-\(scenario)")
            if dismiss {
                XCTAssertTrue(app.buttons["outOfSyncDismiss"].isEnabled, "An authenticated connection can dismiss")
                enableChanges(app)
                let button = app.buttons["outOfSyncDismiss"]
                XCTAssertTrue(button.waitForExistence(timeout: 15)); reveal(button, app)
                waitFor(button, NSPredicate(format: "enabled == true"), 10, "Dismiss enabled")
                button.tap()
                XCTAssertTrue(banner.waitForNonExistence(timeout: 8), "Dismiss forgets the held frame")
            }
            app.terminate()
        }
        let app = launchSignedIn(scenario: "out-of-sync")
        let banner = app.descendants(matching: .any)["outOfSyncBanner_out-of-sync"]
        XCTAssertTrue(banner.waitForExistence(timeout: 15), app.debugDescription)
        let board = app.descendants(matching: .any)["homeBoard"]
        XCTAssertTrue((board.value as? String ?? "").contains("SOMEONE ELSE"), "the board shows the foreign frame")
        XCTAssertFalse(app.buttons["outOfSyncDismiss"].exists)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        shot(app, "W2-B9-out-of-sync")
        enableChanges(app)
        XCTAssertTrue(banner.waitForExistence(timeout: 15))
        let save = app.buttons["outOfSyncSave"]
        reveal(save, app)
        waitFor(save, NSPredicate(format: "enabled == true"), 10, "Save as page enabled")
        save.tap()
        let saved = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Saved as “From board")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), app.debugDescription)
        shot(app, "W2-B9-saved-as-page")
        let restore = app.buttons["outOfSyncRestore"]
        reveal(restore, app); restore.tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 15),
                      "Restore puts the page back; outcome: \(app.staticTexts["actionOutcome"].exists ? app.staticTexts["actionOutcome"].label : "none")")
        waitFor(board, NSPredicate(format: "value CONTAINS %@", "HELLO"), 15, "the page is back")
    }

    /// B10 (iOS-R2): Displays cards (static preview, badges) and the detail's Now showing.
    @MainActor
    func testDisplaysCardsAndNowShowing() async throws {
        try await requireFixture()
        let app = launchSignedIn(scenario: "manual")
        selectDestination("Displays", in: app)
        let kitchen = app.descendants(matching: .any)["displayCard_kitchen"]
        XCTAssertTrue(kitchen.waitForExistence(timeout: 10), app.debugDescription)
        let badge = { (board: String, name: String) in app.descendants(matching: .any)["displayBadge_\(board)_\(name)"] }
        XCTAssertTrue(badge("kitchen", "Connected").waitForExistence(timeout: 20))
        XCTAssertFalse(badge("kitchen", "Paused").exists)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        shot(app, "W2-B10-displays")
        // The grid is lazy: scroll the later cards into existence.
        for (board, name) in [("tv", "FiestaPanel"), ("marquee", "Not configured"), ("mystery", "Unavailable")] {
            for _ in 0..<6 where !badge(board, name).exists { app.swipeUp() }
            XCTAssertTrue(badge(board, name).exists, "\(board): \(name)")
        }
        XCTAssertFalse(badge("mystery", "Connected").exists, "an unavailable display is never also Connected")
        shot(app, "W2-B10-displays-lower")
        for _ in 0..<6 where !kitchen.isHittable { app.swipeDown() }
        kitchen.tap()
        XCTAssertTrue(app.staticTexts["Now showing"].waitForExistence(timeout: 5))
        let preview = app.descendants(matching: .any)["displayNowShowing"]
        waitFor(preview, NSPredicate(format: "value CONTAINS %@", "HELLO"), 10, "Kitchen's frame")
        XCTAssertTrue(app.buttons["displayPlayback"].exists)
        shot(app, "W2-B10-display-detail")
    }

    /// B32 (iOS-R2): no displays and no pages.
    @MainActor
    func testEmptyStates() async throws {
        try await requireFixture()
        let app = launchSignedIn(scenario: "no-boards")
        XCTAssertTrue(app.staticTexts["No displays yet. Add one to start showing pages on it."].waitForExistence(timeout: 10))
        shot(app, "W2-B32-no-boards")
        app.terminate()
        let pages = launchSignedIn(scenario: "no-pages")
        selectDestination("Pages", in: pages)
        XCTAssertTrue(pages.staticTexts["No pages created yet."].waitForExistence(timeout: 10))
        XCTAssertTrue(pages.staticTexts["Create your first page to display on the board."].exists)
        XCTAssertTrue(pages.buttons["createFirstPage"].exists)
        shot(pages, "W2-B32-no-pages")
    }

    /// Library (iOS-R2; E1 open issues 5 and 6), in demo: after naming the page the
    /// next tap opens the format menu (not the keyboard); and after the created page's editor closes, the Pages list shows no stale
    /// "Page created. Open its editor…" note.
    @MainActor
    func testLibraryCreateSheetKeyboardAndOutcome() throws {
        let app = isolatedApplication(); launchFixture(app)
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 10))
        selectDestination("Pages", in: app)
        let create = app.buttons["newLibraryPage"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        let name = app.textFields["New page name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3)); name.tap(); name.typeText("Keyboard check")
        // The iPad Hide-key path (E1 issue 5) is fixed in the app (the field resigns on
        // keyboardWillHide) but not driven here: these simulators attach a hardware keyboard,
        // so the software keyboard's Hide key is off screen. Return resigns on both idioms.
        name.typeText("\n")
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 5)
        app.buttons["pageFamilyPicker"].tap()
        let flap = app.buttons["Split-flap · 6 × 22"]
        if !flap.waitForExistence(timeout: 3) { shot(app, "W2-library-format-menu-failure") }
        XCTAssertTrue(flap.exists, "the format menu opens instead of the keyboard; keyboard up: \(app.keyboards.firstMatch.exists)")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "the keyboard did not come back")
        flap.tap()
        app.buttons["createLibraryPage"].tap()
        XCTAssertTrue(app.navigationBars["Edit Page"].waitForExistence(timeout: 8))
        app.buttons["Close"].tap()
        let search = app.searchFields["Find a page"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Keyboard check")
        XCTAssertTrue(pageCard(app, named: "Keyboard check").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Open its editor")).firstMatch.exists,
                       "no stale creation note once the editor has closed")
        shot(app, "W2-library-after-create")
    }

    @MainActor private func waitFor(_ element: XCUIElement, _ predicate: NSPredicate, _ timeout: TimeInterval, _ what: String) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && predicate.evaluate(with: element) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail("\(what): \(predicate) not met; label=\(element.exists ? element.label : "-") value=\(element.exists ? String(describing: element.value) : "-")")
    }

    @MainActor private func choose(_ display: String, in app: XCUIApplication) {
        selectFixtureDisplay(display, in: app)
    }

    @MainActor private func enableChanges(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 10))
    }

    @MainActor private func launchSignedIn(scenario: String) -> XCUIApplication {
        let app = isolatedApplication(); app.launchArguments = []; app.launch()
        let alias = "board-i7-\(scenario)-" + UUID().uuidString.prefix(6).lowercased()
        let address = app.textFields["connectionAddress"]
        XCTAssertTrue(app.textFields["connectionAddress"].waitForExistence(timeout: 10))
        reveal(address, app); typeConnectionAddress("http://127.0.0.1:\(port)/" + alias, into: address, in: app)
        let name = app.textFields["Server name (optional)"]
        reveal(name, app); name.tap(); name.typeText(alias + "\n")
        let localHTTP = app.switches["connectionLocalHTTP"]
        reveal(localHTTP, app)
        // On iPad the first tap sometimes lands while the keyboard is still leaving; retry until on.
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
        XCTAssertTrue(app.descendants(matching: .any)["homeBoard"].waitForExistence(timeout: 15), app.debugDescription)
        return app
    }

    @MainActor private func selectDestination(_ name: String, in app: XCUIApplication) {
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

    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 { if element.exists && element.isHittable { return }; app.swipeUp() }
        for _ in 0..<12 { if element.exists && element.isHittable { return }; app.swipeDown() }
    }

    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(name)-\(device)-mockfixture"; attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(device)-mockfixture.png")
            try? screenshot.pngRepresentation.write(to: url)
        }
    }

    @MainActor private func requireFixture() async throws {
        try FixtureHTTPServer.shared.requireReady()
    }
}
