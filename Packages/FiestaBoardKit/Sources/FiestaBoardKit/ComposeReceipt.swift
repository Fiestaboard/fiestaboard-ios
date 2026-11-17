import Foundation
import FiestaBoardDocuments

/// The outcome of one captured UUID, including accepted content that was held
/// or already present. An HTTP success alone never means physical delivery.
public struct ComposeReceipt: Sendable {
    public enum State: String, Decodable, Sendable {
        case preparing, dispatching, held, sent, unchanged
        case notSent = "not_sent"
        case partial, expired, superseded, unknown, rejected
    }
    public let requestID: UUID
    public let boardID: String
    public let state: State
    public let sent: Bool?
    public let expiresAt: Date?
    public let startedAt: Date?
    public let heldUntil: Date?
    public let duration: ComposeBufferDuration
    public let reason: String?
    public let retryAfterSeconds: Int?
    public let failedRegions: [[String: Int]]
    public let rawData: Data

    private struct Wire: Decodable {
        let `protocol`: String
        let request_id: UUID
        let board_id: String
        let status: State
        let sent: Bool?
        let expires_at: String?
        let started_at: String?
        let held_until: String?
        let reason: String?
        let duration: WireDuration
        let retry_after_seconds: Int?
        let failed_regions: [[String: Int]]
    }
    private struct WireDuration: Decodable {
        let kind: String
        let minutes: Int?
        let ends_at: String?
        func value() throws -> ComposeBufferDuration {
            switch kind {
            case "minutes":
                guard let minutes, (1...480).contains(minutes), ends_at == nil else { throw FiestaBoardError.unknownMutationOutcome }
                return .minutes(minutes)
            case "until_cancel":
                guard minutes == nil, ends_at == nil else { throw FiestaBoardError.unknownMutationOutcome }
                return .untilCancel
            case "until":
                guard minutes == nil, let ends_at, let end = ComposeReceipt.instant(ends_at) else { throw FiestaBoardError.unknownMutationOutcome }
                return .until(end)
            default: throw FiestaBoardError.unknownMutationOutcome
            }
        }
    }
    public init(rawData: Data, httpStatus: Int, expectedBoardID: String,
                expectedRequestID: UUID, expectedDuration: ComposeBufferDuration) throws {
        guard rawData.count <= 1_048_576,
              let top = try? RawJSONObject.members(rawData) else { throw FiestaBoardError.unknownMutationOutcome }
        let body = httpStatus >= 400 ? top["detail"] : rawData
        guard let body, let fields = try? RawJSONObject.members(body),
              ["protocol", "request_id", "board_id", "status", "sent", "expires_at", "started_at", "held_until", "duration", "failed_regions"].allSatisfy({ fields[$0] != nil }),
              let wire = try? JSONDecoder().decode(Wire.self, from: body),
              wire.protocol == "compose-intent-v1", wire.request_id == expectedRequestID,
              wire.board_id == expectedBoardID,
              wire.retry_after_seconds.map({ $0 >= 0 }) ?? true else { throw FiestaBoardError.unknownMutationOutcome }
        let duration = try wire.duration.value()
        guard Self.sameDuration(duration, expectedDuration) else { throw FiestaBoardError.unknownMutationOutcome }
        func date(_ value: String?) throws -> Date? {
            guard let value else { return nil }
            guard let parsed = Self.instant(value) else { throw FiestaBoardError.unknownMutationOutcome }
            return parsed
        }
        let expiry = try date(wire.expires_at), start = try date(wire.started_at), held = try date(wire.held_until)
        let expectedStatus: Int
        switch wire.status {
        case .sent, .unchanged:
            expectedStatus = 200
            guard wire.sent == (wire.status == .sent), let start, held == nil,
                  wire.retry_after_seconds == nil else { throw FiestaBoardError.unknownMutationOutcome }
            switch duration {
            case .minutes(let minutes):
                guard let expiry, abs(expiry.timeIntervalSince(start) - Double(minutes * 60)) < 1 else { throw FiestaBoardError.unknownMutationOutcome }
            case .until(let end):
                guard let expiry, expiry > start, abs(expiry.timeIntervalSince(end)) < 0.001 else { throw FiestaBoardError.unknownMutationOutcome }
            case .untilCancel:
                guard expiry == nil else { throw FiestaBoardError.unknownMutationOutcome }
            }
        case .held:
            expectedStatus = 202
            guard wire.sent == false, start == nil, expiry == nil, wire.retry_after_seconds == nil else { throw FiestaBoardError.unknownMutationOutcome }
        case .preparing, .dispatching:
            expectedStatus = 202
            guard wire.sent != true, start == nil, expiry == nil else { throw FiestaBoardError.unknownMutationOutcome }
        case .notSent:
            expectedStatus = wire.retry_after_seconds == nil ? 502 : 429
            guard wire.sent == false, start == nil, expiry == nil else { throw FiestaBoardError.unknownMutationOutcome }
        case .partial:
            expectedStatus = 502
            guard wire.sent == nil, start == nil, expiry == nil else { throw FiestaBoardError.unknownMutationOutcome }
        case .unknown:
            expectedStatus = 503
            guard wire.sent == nil, start == nil, expiry == nil else { throw FiestaBoardError.unknownMutationOutcome }
        case .rejected:
            expectedStatus = 409
            guard wire.sent == false, start == nil, expiry == nil else { throw FiestaBoardError.unknownMutationOutcome }
        case .expired, .superseded:
            // A display can accept bytes before a later policy/intent check.
            // Keep that physical fact separate from the rejected final intent.
            expectedStatus = 409
        }
        guard expectedStatus == httpStatus else { throw FiestaBoardError.unknownMutationOutcome }
        requestID = wire.request_id; boardID = wire.board_id; state = wire.status
        sent = wire.sent; expiresAt = expiry; startedAt = start; heldUntil = held
        self.duration = duration; reason = wire.reason; retryAfterSeconds = wire.retry_after_seconds
        failedRegions = wire.failed_regions; self.rawData = rawData
    }
    private static func sameDuration(_ lhs: ComposeBufferDuration, _ rhs: ComposeBufferDuration) -> Bool {
        if case .until(let left) = lhs, case .until(let right) = rhs { return abs(left.timeIntervalSince(right)) < 0.001 }
        return lhs == rhs
    }
    private static func instant(_ value: String) -> Date? {
        guard value.utf8.count <= 40,
              value.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: value) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: value)
    }
}
