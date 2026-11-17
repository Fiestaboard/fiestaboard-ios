import XCTest

extension XCTestCase {
    /// A fresh namespace per application object; relaunching that object preserves state.
    @MainActor func isolatedApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FIESTABOARD_TEST_NAMESPACE"] = UUID().uuidString
        return app
    }

    @MainActor func pageCard(_ app: XCUIApplication, named name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "pageCard_"))
            .containing(.staticText, identifier: name).firstMatch
    }

    /// A delivered menu tap is not evidence that the requested display became selected.
    @MainActor func selectFixtureDisplay(_ display: String, in app: XCUIApplication,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let picker = app.buttons["homeDisplayPicker"]
        let actionable = NSPredicate(format: "exists == true AND enabled == true AND hittable == true")
        // A board can appear before its refresh finishes. Opening this menu
        // while the picker is disabled exposes rows that exist but cannot tap.
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: actionable, object: picker)], timeout: 5) == .completed else {
            XCTFail("Display picker must be enabled and visible", file: file, line: line)
            return
        }
        if picker.label.contains(display) { return }
        picker.tap()
        let item = app.buttons[display].firstMatch
        for _ in 0..<3 {
            if picker.label.contains(display) { return }
            guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: actionable, object: item)], timeout: 5) == .completed else {
                XCTFail("Display menu row must be enabled and visible: \(display)", file: file, line: line)
                return
            }
            item.tap()
            let selected = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label CONTAINS %@", display), object: picker)
            if XCTWaiter.wait(for: [selected], timeout: 3) == .completed { return }
        }
        XCTFail("Display menu must select \(display); selected label: \(picker.label)", file: file, line: line)
    }

    /// Missing loopback infrastructure must fail a required journey, never skip it.
    @MainActor func requireReadyFixture(port: String,
                                       file: StaticString = #filePath, line: UInt = #line) throws {
        do {
            try FixtureReadiness.require(URL(string: "http://127.0.0.1:\(port)/ready")!)
        } catch {
            XCTFail("Required native fixture unavailable or invalid (\(error)); loopback port \(port)",
                    file: file, line: line)
            throw error
        }
    }

    /// Cold simulator keyboard startup may accept a caret without becoming ready for typing.
    @MainActor func typeConnectionAddress(_ text: String, into address: XCUIElement, in app: XCUIApplication,
                                         file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<2 {
            address.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 8) {
                address.typeText(text)
                return
            }
        }
        XCTFail("The connection address keyboard must be ready before typing", file: file, line: line)
    }

    /// Verify real loopback permission before opening a fixture form keyboard.
    @MainActor func allowFixtureHTTP(_ app: XCUIApplication) {
        func reveal(_ element: XCUIElement) {
            for _ in 0..<12 { if element.exists && element.isHittable { break }; app.swipeUp() }
            for _ in 0..<12 { if element.exists && element.isHittable { break }; app.swipeDown() }
        }
        let localHTTP = app.switches["connectionLocalHTTP"]
        reveal(localHTTP)
        // At accessibility sizes a visible label makes the whole switch "hittable"
        // even while its actual tap point is covered by the software keyboard.
        func switchTapIsVisible() -> Bool {
            guard localHTTP.exists, localHTTP.isHittable else { return false }
            let keyboard = app.keyboards.firstMatch
            let bottom = keyboard.exists ? keyboard.frame.minY : app.windows.firstMatch.frame.maxY
            let top = app.navigationBars.firstMatch.frame.maxY
            return localHTTP.frame.midY > top + 8 && localHTTP.frame.midY < bottom - 8
        }
        // Require the observed state transition, as the other fixture helpers do.
        // A cold tap can be delivered inside the visible switch without activating it.
        for _ in 0..<3 {
            if localHTTP.value as? String == "1" { break }
            for _ in 0..<12 {
                if switchTapIsVisible() { break }
                if localHTTP.exists && localHTTP.frame.midY <= app.navigationBars.firstMatch.frame.maxY + 8 {
                    app.swipeDown()
                } else { app.swipeUp() }
            }
            guard switchTapIsVisible() else {
                XCTFail("HTTP switch tap point must be above the keyboard")
                return
            }
            localHTTP.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == '1'"), object: localHTTP)], timeout: 2)
        }
        XCTAssertEqual(localHTTP.value as? String, "1", "Explicitly allow the loopback HTTP fixture before connecting")
    }

    /// Real app sign-in against the loopback HTTP fixture, never a shipping demo path.
    @MainActor func launchFixture(_ app: XCUIApplication, arguments: [String] = []) {
        // A fixture starts at enrollment; same-app relaunches retain this namespace.
        if app.launchEnvironment["FIESTABOARD_TEST_NAMESPACE"] == nil {
            app.launchEnvironment["FIESTABOARD_TEST_NAMESPACE"] = UUID().uuidString
        }
        app.launchArguments = arguments
        app.launch()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<12 { if element.exists && element.isHittable { break }; app.swipeUp() }
            for _ in 0..<12 { if element.exists && element.isHittable { break }; app.swipeDown() }
        }
        let address = app.textFields["connectionAddress"]
        // At accessibility sizes the form may not instantiate this off-screen row yet.
        reveal(address)
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        let port = String(FixtureHTTPServer.shared.port)
        allowFixtureHTTP(app)
        reveal(address)
        typeConnectionAddress("http://127.0.0.1:\(port)/board-manual-\(UUID().uuidString.lowercased())", into: address, in: app)
        let connect = app.buttons["connectionConnect"]
        reveal(connect); connect.tap()
        let username = app.textFields["Username"]
        reveal(username)
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        reveal(username); username.tap(); username.typeText("fixture_admin")
        let password = app.secureTextFields["connectionPassword"]
        reveal(password); password.tap(); password.typeText("fixture-password")
        // SecureField's native Go action invokes the same sign-in handler and clears focus.
        // At accessibility sizes the form button can remain below the keyboard.
        let go = app.keyboards.buttons["Go"]
        XCTAssertTrue(go.waitForExistence(timeout: 8), "The password keyboard must expose its Go action")
        go.tap()
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 15))
    }
}
