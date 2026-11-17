import XCTest
@testable import FiestaBoardAppState

final class LoginRetryDeadlineTests: XCTestCase {
    // A restarted per-second countdown would incorrectly extend the server's lockout after suspension.
    func testAbsoluteDeadlineAccountsForFractionalSecondsAndBackgroundElapsedTime() {
        let received = Date(timeIntervalSince1970: 1_000)
        let deadline = LoginRetryDeadline(retryAfterSeconds: 60, receivedAt: received)!
        XCTAssertEqual(deadline.remainingSeconds(at: received), 60)
        XCTAssertEqual(deadline.remainingSeconds(at: Date(timeIntervalSince1970: 1_000.1)), 60)
        XCTAssertEqual(deadline.remainingSeconds(at: Date(timeIntervalSince1970: 1_059.01)), 1)
        XCTAssertEqual(deadline.remainingSeconds(at: Date(timeIntervalSince1970: 1_060)), 0)
        XCTAssertEqual(deadline.remainingSeconds(at: Date(timeIntervalSince1970: 1_600)), 0)
    }

    // An absent/malformed Retry-After must not manufacture an exact countdown.
    func testMissingOrNegativeDelayDoesNotInventADeadline() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(LoginRetryDeadline(retryAfterSeconds: nil, receivedAt: now))
        XCTAssertNil(LoginRetryDeadline(retryAfterSeconds: -1, receivedAt: now))
        XCTAssertEqual(LoginRetryDeadline(retryAfterSeconds: 0, receivedAt: now)?.remainingSeconds(at: now), 0)
    }

    // A malicious but representable header must never trap converting Double back to Int.
    func testVeryLargeDelaySaturatesWithoutCrashingOrEnablingAnEarlyRetry() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let deadline = try XCTUnwrap(LoginRetryDeadline(retryAfterSeconds: Int.max, receivedAt: now))
        XCTAssertEqual(deadline.remainingSeconds(at: now), Int.max)
        XCTAssertGreaterThan(deadline.remainingSeconds(at: now.addingTimeInterval(60)), 0)
    }
}
