import Foundation

/// Read projection only. Recurrence and times remain in server semantics, never local dates.
public struct ScheduleEntry: Decodable, Sendable, Identifiable {
    public let id: String
    public let revision: String?
    public let editProtocol: String?
    public let boardID: String?
    public let pageID: String
    public let startTime: String
    public let endTime: String?
    public let dayPattern: String
    public let customDays: [String]?
    public let enabled: Bool
    public let recurrenceType: String?
    public let annualDate: String?
    public let annualEndDate: String?
    public let oneOffDate: String?
    public let oneOffEndDate: String?
    public let startType: String?
    public let endType: String?
    public let startSunOffset: Int?
    public let endSunOffset: Int?
    public let resolvedStartTime: String?
    public let resolvedEndTime: String?
    public let createdAt: String?
    public let updatedAt: String?
    enum CodingKeys: String, CodingKey {
        case id, revision, enabled
        case editProtocol = "edit_protocol", boardID = "board_id", pageID = "page_id"
        case startTime = "start_time", endTime = "end_time", dayPattern = "day_pattern", customDays = "custom_days"
        case recurrenceType = "recurrence_type", annualDate = "annual_date", annualEndDate = "annual_end_date"
        case oneOffDate = "one_off_date", oneOffEndDate = "one_off_end_date"
        case startType = "start_type", endType = "end_type", startSunOffset = "start_sun_offset", endSunOffset = "end_sun_offset"
        case resolvedStartTime = "resolved_start_time", resolvedEndTime = "resolved_end_time"
        case createdAt = "created_at", updatedAt = "updated_at"
    }
}

public struct ScheduleList: Sendable {
    /// Exact envelope, including absent/null values, revisions and unknown fields.
    /// This read projection must never be reconstructed into a write payload.
    public let rawData: Data
    public let schedules: [ScheduleEntry]
    public let total: Int
    public let defaultPageID: String?
    public let enabled: Bool?
    public init(data: Data, boardID: String) throws {
        struct Envelope: Decodable {
            let schedules: [ScheduleEntry]
            let total: Int
            let defaultPageID: String?
            let enabled: Bool?
            enum CodingKeys: String, CodingKey {
                case schedules, total, enabled
                case defaultPageID = "default_page_id"
            }
        }
        guard let value = try? JSONDecoder().decode(Envelope.self, from: data),
              value.total == value.schedules.count,
              Set(value.schedules.map(\.id)).count == value.total,
              value.schedules.allSatisfy({ !$0.id.isEmpty && !$0.pageID.isEmpty && ($0.boardID == nil || $0.boardID == "" || $0.boardID == boardID) }) else {
            throw FiestaBoardError.invalidResponse
        }
        rawData = data; schedules = value.schedules; total = value.total
        defaultPageID = value.defaultPageID; enabled = value.enabled
    }
}

public extension FiestaBoardService {
    func schedules(on target: BoardTarget) async throws -> ScheduleList { throw FiestaBoardError.unsupportedOperation }
}
