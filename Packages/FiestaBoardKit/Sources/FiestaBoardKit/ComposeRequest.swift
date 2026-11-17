import Foundation
import FiestaBoardDocuments

/// Geometry of the captured display, resolved from current verified board
/// metadata. A panel always spells both axes; it never inherits a server default.
public enum ComposeGeometry: Equatable, Sendable, Encodable {
    case flagship, note
    case noteArray(wide: Int, tall: Int)
    case panel(rows: Int, cols: Int)
    func validate() throws {
        switch self {
        case .flagship, .note: break
        case .noteArray(let wide, let tall):
            guard (1...8).contains(wide), (1...8).contains(tall) else { throw FiestaBoardError.invalidTarget }
        case .panel(let rows, let cols):
            guard (1...96).contains(rows), (5...128).contains(cols) else { throw FiestaBoardError.invalidTarget }
        }
    }
    private enum CodingKeys: String, CodingKey { case device_type, notes_wide, notes_tall, grid_rows, grid_cols }
    public func encode(to encoder: any Encoder) throws {
        try validate()
        var fields = encoder.container(keyedBy: CodingKeys.self)
        var wide = 1, tall = 1
        switch self {
        case .flagship: try fields.encode("flagship", forKey: .device_type)
        case .note: try fields.encode("note", forKey: .device_type)
        case .noteArray(let w, let t):
            try fields.encode("note_array", forKey: .device_type); wide = w; tall = t
        case .panel(let rows, let cols):
            try fields.encode("panel", forKey: .device_type)
            try fields.encode(rows, forKey: .grid_rows); try fields.encode(cols, forKey: .grid_cols)
        }
        try fields.encode(wide, forKey: .notes_wide); try fields.encode(tall, forKey: .notes_tall)
    }
}

/// The request's nonsecret proof and target are local guards, excluded from its
/// body. Original source, duration and consent are captured once for one UUID.
public struct ComposeRequest: Sendable {
    public let principal: ComposePrincipalProof
    public let target: BoardTarget
    public let requestID: UUID
    public let preparedAt: Date
    public let text: String
    public let lineMetadata: [ComposeBufferLine]
    public let geometry: ComposeGeometry
    public let duration: ComposeBufferDuration
    public let silence: ComposeBufferSilence
    public init(principal: ComposePrincipalProof, target: BoardTarget, requestID: UUID = UUID(), preparedAt: Date = Date(),
                text: String, lineMetadata: [ComposeBufferLine], geometry: ComposeGeometry,
                duration: ComposeBufferDuration, silence: ComposeBufferSilence) {
        self.principal = principal; self.target = target; self.requestID = requestID; self.preparedAt = preparedAt
        self.text = text; self.lineMetadata = lineMetadata; self.geometry = geometry; self.duration = duration; self.silence = silence
    }
    public func encoded(now: Date = Date()) throws -> Data {
        let lines = text.components(separatedBy: "\n")
        guard principal.verifiedOnline, principal.identity.deploymentID == target.deployment.description,
              now.timeIntervalSince1970.isFinite, preparedAt.timeIntervalSince1970.isFinite,
              abs(preparedAt.timeIntervalSince(now)) <= 300,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              lines.count <= 512, lines.reduce(0, { $0 + $1.utf8.count }) <= 65_536,
              lines.allSatisfy({ $0.unicodeScalars.count <= 4096 }), lineMetadata.count == lines.count,
              lineMetadata.allSatisfy({ ["left", "center", "right"].contains($0.alignment) }) else { throw FiestaBoardError.invalidRequestContext }
        try geometry.validate()
        struct DurationBody: Encodable {
            let kind: String
            let minutes: Int?
            let ends_at: String?
        }
        let durationBody: DurationBody
        switch duration {
        case .minutes(let minutes):
            guard (1...480).contains(minutes) else { throw FiestaBoardError.invalidRequestContext }
            durationBody = .init(kind: "minutes", minutes: minutes, ends_at: nil)
        case .until(let end):
            guard end.timeIntervalSince1970.isFinite, end > now, end.timeIntervalSince(now) <= 28_800 else { throw FiestaBoardError.invalidRequestContext }
            durationBody = .init(kind: "until", minutes: nil, ends_at: Self.instant(end))
        case .untilCancel:
            durationBody = .init(kind: "until_cancel", minutes: nil, ends_at: nil)
        }
        struct Body: Encodable {
            let `protocol` = "compose-intent-v1"
            let request_id: UUID
            let prepared_at: String
            let template: [String]
            let line_metadata: [ComposeBufferLine]
            let geometry: ComposeGeometry
            let duration: DurationBody
            let silence: ComposeBufferSilence
        }
        return try JSONEncoder().encode(Body(request_id: requestID, prepared_at: Self.instant(preparedAt),
            template: lines, line_metadata: lineMetadata, geometry: geometry, duration: durationBody, silence: silence))
    }
    private static func instant(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
