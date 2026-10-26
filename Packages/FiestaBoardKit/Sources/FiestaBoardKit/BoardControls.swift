import Foundation

public enum DefaultPageChange: Sendable, Equatable { case omit, set(String), clear }
/// Only explicit fields are encoded. Clearing the default differs from leaving it untouched.
public struct BoardPatch: Encodable, Sendable, Equatable {
    public let paused: Bool?
    public let scheduleEnabled: Bool?
    public let autoRestore: Bool?
    public let defaultPage: DefaultPageChange
    public init(paused: Bool? = nil, scheduleEnabled: Bool? = nil, autoRestore: Bool? = nil,
                defaultPage: DefaultPageChange = .omit) {
        self.paused = paused; self.scheduleEnabled = scheduleEnabled
        self.autoRestore = autoRestore; self.defaultPage = defaultPage
    }
    public var isEmpty: Bool { paused == nil && scheduleEnabled == nil && autoRestore == nil && defaultPage == .omit }
    public func validate() throws {
        guard !isEmpty else { throw FiestaBoardError.invalidTarget }
        if case .set(let id) = defaultPage, !DeploymentURL.validSegment(id) { throw FiestaBoardError.invalidPath }
    }
    enum CodingKeys: String, CodingKey {
        case paused, scheduleEnabled = "schedule_enabled", autoRestore = "auto_restore", defaultPage = "default_page_id"
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(paused, forKey: .paused)
        try c.encodeIfPresent(scheduleEnabled, forKey: .scheduleEnabled)
        try c.encodeIfPresent(autoRestore, forKey: .autoRestore)
        switch defaultPage {
        case .omit: break
        case .set(let id): try c.encode(id, forKey: .defaultPage)
        case .clear: try c.encodeNil(forKey: .defaultPage)
        }
    }
}
/// The server returned a configuration snapshot. This never acknowledges a hardware send.
public struct BoardConfigurationReceipt: Sendable {
    public let board: BoardDetail
    public init(board: BoardDetail) { self.board = board }
}
/// Restore retains the pinned selection. Accepted writes do not establish physical output.
public struct BoardRestoreReceipt: Decodable, Sendable {
    public let boardID: String
    public let pageID: String?
    public let sent: Bool
    public let reason: String?
    public let deviceObserved: Bool
    enum CodingKeys: String, CodingKey {
        case boardID = "board_id", pageID = "page_id", sent, reason, deviceObserved = "device_observed"
    }
}
