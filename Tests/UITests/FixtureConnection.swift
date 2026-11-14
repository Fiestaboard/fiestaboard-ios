import XCTest

extension XCTestCase {
    /// Real app sign-in against the loopback HTTP fixture, never a shipping demo path.
    @MainActor func launchFixture(_ app: XCUIApplication, arguments: [String] = []) {
        app.launchArguments = arguments
        app.launch()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<12 where !(element.exists && element.isHittable) { app.swipeUp() }
            for _ in 0..<12 where !(element.exists && element.isHittable) { app.swipeDown() }
        }
        let address = app.textFields["connectionAddress"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        reveal(address); address.tap()
        let port = ProcessInfo.processInfo.environment["FIXTURE_PORT"] ?? "18442"
        address.typeText("http://127.0.0.1:\(port)/board-manual-\(UUID().uuidString.lowercased())")
        let localHTTP = app.switches["connectionLocalHTTP"]
        reveal(localHTTP)
        if localHTTP.value as? String != "1" { localHTTP.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        let connect = app.buttons["connectionConnect"]
        reveal(connect); connect.tap()
        let username = app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        reveal(username); username.tap(); username.typeText("fixture_admin")
        let password = app.secureTextFields["connectionPassword"]
        reveal(password); password.tap(); password.typeText("fixture-password")
        let signIn = app.buttons["connectionSignIn"]
        reveal(signIn); signIn.tap()
        XCTAssertTrue(app.buttons["boardControlsEntry"].waitForExistence(timeout: 15))
    }
}
