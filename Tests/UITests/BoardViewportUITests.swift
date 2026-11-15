import XCTest

@MainActor final class BoardViewportUITests: XCTestCase {
    func testWideMergedBoardReachesMiddleEndAndReturnsWithoutNoteSnapping() {
        let app = XCUIApplication()
        app.launchArguments = ["-fiestaboard.parityFixture", "viewport"]
        app.launch()
        defer { app.terminate() }
        let viewport = app.descendants(matching: .any).matching(identifier: "board-viewport").firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 10))
        func waitForValue(_ value: String) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: viewport)], timeout: 5), .completed)
        }
        waitForValue("Start of board")
        // A short drag must leave the one wide target at an intermediate offset.
        let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        let middle = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: middle, withVelocity: .slow, thenHoldForDuration: 0.1)
        waitForValue("More columns on both sides")
        for _ in 0..<8 where viewport.value as? String != "End of board" { viewport.swipeLeft() }
        waitForValue("End of board")
        for _ in 0..<8 where viewport.value as? String != "Start of board" { viewport.swipeRight() }
        waitForValue("Start of board")
    }
}
