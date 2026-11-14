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

    /// Real app sign-in against the loopback HTTP fixture, never a shipping demo path.
    @MainActor func launchFixture(_ app: XCUIApplication, arguments: [String] = []) {
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
        address.tap()
        let port = ProcessInfo.processInfo.environment["FIXTURE_PORT"] ?? "18442"
        address.typeText("http://127.0.0.1:\(port)/board-manual-\(UUID().uuidString.lowercased())")
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
        for _ in 0..<12 {
            if switchTapIsVisible() { break }
            if localHTTP.exists && localHTTP.frame.midY <= app.navigationBars.firstMatch.frame.maxY + 8 {
                app.swipeDown()
            } else { app.swipeUp() }
        }
        XCTAssertTrue(switchTapIsVisible(), "HTTP switch tap point must be above the keyboard")
        if localHTTP.value as? String != "1" { localHTTP.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        XCTAssertEqual(localHTTP.value as? String, "1", "Explicitly allow the loopback HTTP fixture before connecting")
        let connect = app.buttons["connectionConnect"]
        reveal(connect); connect.tap()
        let username = app.textFields["Username"]
        reveal(username)
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        reveal(username); username.tap(); username.typeText("fixture_admin")
        let password = app.secureTextFields["connectionPassword"]
        reveal(password); password.tap(); password.typeText("fixture-password")
        let signIn = app.buttons["connectionSignIn"]
        reveal(signIn); signIn.tap()
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 15))
    }
}
