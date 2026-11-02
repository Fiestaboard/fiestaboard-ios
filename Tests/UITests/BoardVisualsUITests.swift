import XCTest

/// Home "now showing" + the shared renderer, against the loopback fixture's
/// `/board-<scenario>-<n>/` prefix family (mock content, never a real server).
/// Start with: FIXTURE_PORT=<port> python3 Tests/UITests/fixture_server.py and
/// pass the same port as TEST_RUNNER_FIXTURE_PORT (default 18442). Screenshots go
/// to TEST_RUNNER_SHOT_DIR when set (always as attachments too).
final class BoardVisualsUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    private var port: String { ProcessInfo.processInfo.environment["FIXTURE_PORT"] ?? "18442" }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipadair11m4" : "iphone17promax" }

    /// B8 (+B33 hierarchy): the status row for every delivered scenario.
    @MainActor
    func testHomeStatusRowStates() async throws {
        try await requireFixture()
        let expectations: [(String, String, String, [String])] = [
            ("manual", "Hello World", "Manual Mode", []),
            ("schedule", "Hello World", "Schedule Mode", []),
            ("schedule-gap", "Schedule gap (no default page set)", "Schedule Mode", []),
            ("collection", "Morning rotation › ", "Schedule Mode", ["collectionBadge"]),
            ("collection-native-null", "Morning rotation › Device selecting…", "Schedule Mode", ["collectionBadge"]),
            ("override", "Desk Note", "Override: 9m remaining", []),
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
            XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "may be cached")).firstMatch.exists,
                           "no permanent cache disclaimer")
            XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Source")).firstMatch.exists, "no source: label")
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
            XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "web preview")).firstMatch.exists)
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
        let confirm = app.buttons["Confirm board action"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let back = app.navigationBars.buttons["FiestaBoard"]
        if back.waitForExistence(timeout: 3) { back.tap() }
        waitFor(board, NSPredicate(format: "value CONTAINS %@", "GOOD MORNING"), 8, "flipped frame")
        let name = app.descendants(matching: .any)["nowShowingName"]
        waitFor(name, NSPredicate(format: "label == %@", "Good Morning"), 8, "now showing follows the send")
        settle(4)
        shot(app, "D1-B6-after-change")
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

    @MainActor private func waitFor(_ element: XCUIElement, _ predicate: NSPredicate, _ timeout: TimeInterval, _ what: String) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && predicate.evaluate(with: element) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail("\(what): \(predicate) not met; label=\(element.exists ? element.label : "-") value=\(element.exists ? String(describing: element.value) : "-")")
    }

    @MainActor private func choose(_ display: String, in app: XCUIApplication) {
        let picker = app.descendants(matching: .any)["homeDisplayPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let item = app.buttons[display].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        item.tap()
    }

    @MainActor private func enableChanges(_ app: XCUIApplication) {
        selectDestination("Settings", in: app)
        let toggle = app.switches["Enable changes on this server"]
        reveal(toggle, app)
        if toggle.value as? String != "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        let apply = app.buttons["Apply change setting"]
        reveal(apply, app); apply.tap()
        selectDestination("Home", in: app)
    }

    @MainActor private func launchSignedIn(scenario: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = []; app.launch()
        let alias = "board-\(scenario)-" + UUID().uuidString.prefix(6).lowercased()
        let address = app.textFields["connectionAddress"]
        XCTAssertTrue(app.buttons["exploreDemo"].waitForExistence(timeout: 10))
        reveal(address, app); address.tap(); address.typeText("http://127.0.0.1:\(port)/" + alias)
        let name = app.textFields["Server name (optional)"]
        reveal(name, app); name.tap(); name.typeText(alias + "\n")
        let localHTTP = app.switches["connectionLocalHTTP"]
        reveal(localHTTP, app); localHTTP.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
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
        let destination = app.descendants(matching: .any).matching(identifier: "destination-" + name).firstMatch
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
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/ready")!)
        request.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("native-onboarding"))
    }
}
