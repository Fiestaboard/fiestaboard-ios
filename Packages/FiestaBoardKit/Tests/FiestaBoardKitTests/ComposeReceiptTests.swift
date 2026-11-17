import XCTest
import FiestaBoardDocuments
@testable import FiestaBoardKit

final class ComposeReceiptTests: XCTestCase {
    private func record(_ name: String) throws -> [String: Any] {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/Compose/compose-authenticated.json"))
        let corpus = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(corpus["source_sha"] as? String, "b33160f3cae395d95ff62772653b4e2d45862ea7")
        let records = try XCTUnwrap(corpus["records"] as? [[String: Any]])
        return try XCTUnwrap(records.first { $0["case"] as? String == name })
    }
    private func decode(_ record: [String: Any], response: [String: Any]? = nil) throws -> ComposeReceipt {
        let request = try XCTUnwrap(record["request"] as? [String: Any])
        let id = try XCTUnwrap((request["request_id"] as? String).flatMap(UUID.init(uuidString:)))
        let path = try XCTUnwrap(record["path"] as? String).split(separator: "/")
        let duration: ComposeBufferDuration = (request["duration"] as? [String: Any])?["kind"] as? String == "until_cancel" ? .untilCancel : .minutes(120)
        let body = try XCTUnwrap(response ?? record["response"] as? [String: Any])
        return try ComposeReceipt(rawData: JSONSerialization.data(withJSONObject: body),
            httpStatus: try XCTUnwrap(record["status"] as? Int), expectedBoardID: String(path[2]),
            expectedRequestID: id, expectedDuration: duration)
    }
    func testActualAuthenticatedReceiptsPreserveEveryRecordedOutcome() throws {
        let cases = [("formatted-timed-primary", "sent"), ("indefinite-secondary", "sent"),
            ("explicit-hold", "held"), ("paused", "rejected"), ("geometry-mismatch", "rejected"),
            ("rate-limit", "not_sent"), ("partial", "partial"), ("unknown", "unknown")]
        for (name, expected) in cases {
            let receipt = try decode(record(name))
            XCTAssertEqual(receipt.state.rawValue, expected, name)
            if expected == "sent" { XCTAssertEqual(receipt.sent, true) }
            if expected == "held" { XCTAssertEqual(receipt.sent, false); XCTAssertNil(receipt.startedAt); XCTAssertNil(receipt.expiresAt); XCTAssertNotNil(receipt.heldUntil) }
            if expected == "partial" || expected == "unknown" { XCTAssertNil(receipt.sent) }
            if name == "rate-limit" { XCTAssertEqual(receipt.retryAfterSeconds, 9) }
        }
    }
    func testUnexpectedSuccessAndCrossTargetReceiptsNeverBecomeAcknowledged() throws {
        let recorded = try record("formatted-timed-primary")
        let original = try XCTUnwrap(recorded["response"] as? [String: Any])
        for (key, bad) in [("protocol", "future-v2" as Any), ("board_id", "other"),
                           ("request_id", UUID().uuidString), ("sent", false), ("duration", ["kind": "until_cancel"])] {
            var changed = original; changed[key] = bad
            XCTAssertThrowsError(try decode(recorded, response: changed), key)
        }
        for key in ["protocol", "request_id", "board_id", "status", "sent", "started_at", "duration"] {
            var changed = original; changed.removeValue(forKey: key)
            XCTAssertThrowsError(try decode(recorded, response: changed), key)
        }
    }
    func testErrorStringAndContradictoryHeldReceiptStayUnknown() throws {
        let held = try record("explicit-hold")
        var changed = try XCTUnwrap(held["response"] as? [String: Any])
        changed["sent"] = true
        XCTAssertThrowsError(try decode(held, response: changed))
        XCTAssertThrowsError(try decode(held, response: ["detail": "proxy failed"]))
    }
}

extension ComposeReceiptTests {
    func testActualTargetReadbackCarriesCapturedComposeUUIDAndMalformedIdentityFailsClosed() throws {
        var object = try record("primary-readback")["response"] as! [String: Any]
        let board = try JSONDecoder().decode(BoardDetail.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(board.composeRequestID, UUID(uuidString: "5a8989cf-7303-4345-a3fa-4432706bf795"))
        var acknowledgement = object["compose_receipt"] as! [String: Any]
        acknowledgement["request_id"] = "invalid"; object["compose_receipt"] = acknowledgement
        let malformed = try JSONDecoder().decode(BoardDetail.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(malformed.composeRequestID)
    }
}
