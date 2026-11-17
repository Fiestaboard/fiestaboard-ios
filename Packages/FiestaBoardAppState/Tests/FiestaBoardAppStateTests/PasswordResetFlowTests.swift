import XCTest
@testable import FiestaBoardAppState

final class PasswordResetFlowTests: XCTestCase {
    // A client-side validation bypass would send a code with an invalid or unconfirmed password.
    func testInvalidFieldsNeverPrepareANetworkAttempt() {
        var flow = PasswordResetFlow()
        flow.enterCode()
        XCTAssertNil(flow.prepare(code: "", newPassword: "abcdefgh", confirmation: "abcdefgh"))
        XCTAssertEqual(flow.invalidFields, [.code])
        XCTAssertNil(flow.prepare(code: "fb_reset_fixture", newPassword: "short", confirmation: "short"))
        XCTAssertEqual(flow.invalidFields, [.newPassword])
        XCTAssertNil(flow.prepare(code: "fb_reset_fixture", newPassword: "abcdefgh", confirmation: "different"))
        XCTAssertEqual(flow.invalidFields, [.confirmation])
    }

    // Swift grapheme count is not Python/Pydantic's Unicode scalar length at the HTTP boundary.
    func testRequestLimitsUseTheRecordedServersUnicodeScalarRules() throws {
        var flow = PasswordResetFlow()
        flow.enterCode()
        XCTAssertNil(flow.prepare(code: String(repeating: "c", count: 257), newPassword: "abcdefgh", confirmation: "abcdefgh"))
        XCTAssertEqual(flow.invalidFields, [.code])
        let oversized = String(repeating: "a", count: 1_025)
        XCTAssertNil(flow.prepare(code: "fb_reset_fixture", newPassword: oversized, confirmation: oversized))
        XCTAssertEqual(flow.invalidFields, [.newPassword])
        let eightScalars = "e\u{301}e\u{301}e\u{301}e\u{301}"
        let valid = try XCTUnwrap(flow.prepare(code: "fb_reset_fixture", newPassword: eightScalars, confirmation: eightScalars))
        XCTAssertEqual(valid.newPassword, eightScalars)
    }

    // Only the one matching successful response may announce changed; preparing never means success.
    func testConfirmedMatchingResponseChangesThePasswordState() throws {
        var flow = PasswordResetFlow()
        flow.enterCode()
        let attempt = try XCTUnwrap(flow.prepare(code: "  fb_reset_fixture  ", newPassword: "  password  ", confirmation: "  password  "))
        XCTAssertEqual(attempt.code, "fb_reset_fixture")
        XCTAssertEqual(attempt.newPassword, "  password  ", "Password whitespace is meaningful")
        XCTAssertEqual(flow.phase, .submitting)
        XCTAssertNil(flow.prepare(code: "fb_reset_fixture", newPassword: "abcdefgh", confirmation: "abcdefgh"))
        flow.receive(.changed, for: attempt.id)
        XCTAssertEqual(flow.phase, .passwordChanged)
    }

    // Ambiguous reset results must not be replayed merely because a connection returns.
    func testUnknownResultRequiresExplicitUserRecoveryWithoutReplay() throws {
        var flow = PasswordResetFlow()
        flow.enterCode()
        let attempt = try XCTUnwrap(flow.prepare(code: "fb_reset_fixture", newPassword: "abcdefgh", confirmation: "abcdefgh"))
        flow.receive(.unknownOutcome, for: attempt.id)
        XCTAssertEqual(flow.phase, .uncertain)
        XCTAssertNil(flow.prepare(code: "fb_reset_fixture", newPassword: "abcdefgh", confirmation: "abcdefgh"))
        flow.receive(.changed, for: attempt.id)
        XCTAssertEqual(flow.phase, .uncertain, "A completed ambiguous attempt cannot publish another result")
    }

    // Old-hub/cancelled success must not replace the state of a new reset intention.
    func testCancellationInvalidatesAnOutstandingReply() throws {
        var flow = PasswordResetFlow()
        flow.enterCode()
        let old = try XCTUnwrap(flow.prepare(code: "fb_reset_old", newPassword: "abcdefgh", confirmation: "abcdefgh"))
        flow.cancel()
        flow.enterCode()
        let current = try XCTUnwrap(flow.prepare(code: "fb_reset_new", newPassword: "ijklmnop", confirmation: "ijklmnop"))
        flow.receive(.changed, for: old.id)
        XCTAssertEqual(flow.phase, .submitting)
        flow.receive(.invalidCode, for: current.id)
        XCTAssertEqual(flow.phase, .enterCode)
        XCTAssertEqual(flow.invalidFields, [.code])
    }
}
