import XCTest

@MainActor final class BoardViewportUITests: XCTestCase {
    func testWideMergedBoardReachesMiddleEndAndReturnsWithoutNoteSnapping() {
        let app = XCUIApplication()
        app.launchArguments = ["-fiestaboard.parityFixture", "viewport"]
        app.launch()
        defer { app.terminate() }
        let viewport = app.descendants(matching: .any).matching(identifier: "board-viewport").firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 10))
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        XCTAssertTrue(viewport.frame.contains(scroll.frame), "The native scroll region must remain inside the fixed bezel")
        func waitForValue(_ value: String) {
            let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", value), object: viewport)], timeout: 5)
            if result != .completed {
                let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screen.name = "Viewport while expecting \(value)"
                screen.lifetime = .keepAlways
                add(screen)
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "Viewport hierarchy while expecting \(value)"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
            }
            XCTAssertEqual(result, .completed, "Expected \(value); observed \(String(describing: viewport.value))")
        }
        func drag(from startX: CGFloat, to endX: CGFloat) {
            // The outer AX element includes an eight-point hardware bezel.
            // XCTest's automatic swipe begins five points from that outer edge,
            // outside the native scroll view, so it never starts a scroll pan.
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.5))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        waitForValue("Start of board")
        // A short drag must leave the one wide target at an intermediate offset.
        drag(from: 0.75, to: 0.4)
        waitForValue("More columns on both sides")
        for _ in 0..<8 where viewport.value as? String != "End of board" { drag(from: 0.9, to: 0.1) }
        waitForValue("End of board")
        for _ in 0..<8 where viewport.value as? String != "Start of board" { drag(from: 0.1, to: 0.9) }
        waitForValue("Start of board")
    }
}
